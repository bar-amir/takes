import AppKit
import Combine
import SwiftUI

/// Watches everything Takes needs to work: Accessibility access, a working engine, and a free hotkey.
@MainActor
final class SetupMonitor: ObservableObject {
    static let shared = SetupMonitor()

    @Published private(set) var accessibility = FocusReader.isTrusted(prompt: false)
    @Published private(set) var engine: EngineStatus = .checking
    /// Shortcuts macOS refused because another app already uses them, or that a macOS shortcut also fires on.
    @Published var takenHotKeys: [KeyCombo] = []
    /// Re-registers the hotkeys once a taken one is free, so a shortcut freed in System Settings is picked up.
    var recheckHotKeys: (() -> Void)?

    enum EngineStatus: Equatable {
        case checking
        case ready(String)
        case problem(String)
        var isReady: Bool { if case .ready = self { return true }; return false }
    }

    var privacyAccepted: Bool { Store.shared.settings.privacyAccepted }
    var allSet: Bool { accessibility && engine.isReady && privacyAccepted && takenHotKeys.isEmpty }
    /// Missing pieces that stop Takes from working (a taken hotkey only stops that hotkey).
    var blocking: Bool { !accessibility || !engine.isReady || !privacyAccepted }

    static let privacyURL = URL(string: "https://github.com/bar-amir/takes/blob/main/PRIVACY.md")!

    /// Where the text goes with the chosen engine, in one sentence. Setup and onboarding both show it, so they can't drift.
    static func privacySummary(for settings: AppSettings) -> String {
        switch settings.engine {
        case .claudeCode, .apiKey:
            return String(localized: "When you ask for takes, it sends your draft, your preset's instructions and any context you add straight from your Mac to Anthropic, under your own Claude account.")
        case .chatGPT:
            return String(localized: "When you ask for takes, it sends your draft, your preset's instructions and any context you add straight from your Mac to OpenAI, under your own ChatGPT plan.")
        case .provider:
            let provider = Provider.current(settings)
            if provider.id == "custom" {
                return String(localized: "When you ask for takes, it sends your draft, your preset's instructions and any context you add straight from your Mac to the server you added, under your own account.")
            }
            let name = provider.name
            return String(localized: "When you ask for takes, it sends your draft, your preset's instructions and any context you add straight from your Mac to \(name), under your own account.")
        case .local: return String(localized: "When you ask for takes, it sends your draft, your preset's instructions and any context you add to the model server on this Mac; nothing leaves it.")
        }
    }

    /// Who receives the draft with the chosen engine, for onboarding's "where your text goes": the company or
    /// server, or nil when nothing leaves the Mac.
    static func recipient(for settings: AppSettings) -> String? {
        switch settings.engine {
        case .claudeCode, .apiKey: return "Anthropic"
        case .chatGPT: return "OpenAI"
        case .provider:
            let provider = Provider.current(settings)
            return provider.id == "custom" ? String(localized: "the server you added") : provider.name
        case .local: return nil
        }
    }

    /// One short line on what's still missing, for the menu-bar popover; nil when Takes is ready.
    static func missingSummary(accessibility: Bool, engine: EngineStatus, privacyAccepted: Bool, hotKeyFree: Bool) -> String? {
        var missing: [String] = []
        if !accessibility { missing.append(String(localized: "allow Accessibility")) }
        if case .problem = engine { missing.append(String(localized: "connect a model")) }
        if !privacyAccepted { missing.append(String(localized: "review where text goes")) }
        if !hotKeyFree { missing.append(String(localized: "pick a free hotkey")) }
        switch missing.count {
        case 0: return nil
        case 1: return String(localized: "One thing left: \(missing[0]).")
        default: return String(localized: "\(missing.count) things left to set up.")
        }
    }

    /// `missingSummary` for the Mac right now.
    var missingSummary: String? {
        Self.missingSummary(accessibility: accessibility, engine: engine, privacyAccepted: privacyAccepted, hotKeyFree: takenHotKeys.isEmpty)
    }

    /// The reminder to check a take, naming Claude only when it's Claude writing.
    static func mistakesNote(for settings: AppSettings) -> String {
        settings.engine.isClaude
            ? String(localized: "Claude can get things wrong, and takes are only as good as your preset's instructions. Read a take before you send it: what you send is up to you.")
            : String(localized: "Models can get things wrong, and takes are only as good as your preset's instructions. Read a take before you send it: what you send is up to you.")
    }

    private var timer: Timer?
    private var lastEngineCheck = Date.distantPast
    private var settingsSubscription: AnyCancellable?

    private init() {
        settingsSubscription = Store.shared.$settings
            .map { $0.engine }
            .removeDuplicates()
            .sink { [weak self] _ in Task { await self?.refreshEngine() } }
        // Accessibility can be granted at any moment in System Settings; check every second.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let trusted = FocusReader.isTrusted(prompt: false)
        if trusted != accessibility { accessibility = trusted }
        if !takenHotKeys.isEmpty { recheckHotKeys?() }
        // Claude Code's sign-in is checked less often: it runs a process.
        if !engine.isReady && Date().timeIntervalSince(lastEngineCheck) > 5 {
            Task { await refreshEngine() }
        }
    }

    static let claudeMissing = String(localized: "Claude Code isn't installed")

    func refreshEngine() async {
        lastEngineCheck = Date()
        switch Store.shared.settings.engine {
        case .local:
            engine = await Self.localEngineStatus()
        case .provider:
            engine = await Self.providerEngineStatus()
        case .chatGPT:
            engine = await Self.chatGPTEngineStatus()
        case .apiKey:
            engine = Keychain.apiKey?.isEmpty == false ? .ready(String(localized: "Anthropic API key saved")) : .problem(String(localized: "No API key saved yet"))
        case .claudeCode:
            let status = await ClaudeCodeEngine.status()
            if !status.found {
                engine = .problem(Self.claudeMissing)
            } else if !status.signedIn {
                engine = .problem(String(localized: "Claude Code isn't signed in"))
            } else {
                engine = .ready(status.plan.map { String(localized: "Claude Code signed in · \($0.capitalized) plan") }
                    ?? String(localized: "Claude Code signed in"))
            }
        }
    }

    func requestAccessibility() {
        // Shows macOS's own prompt, which offers to open the right Settings pane.
        _ = FocusReader.isTrusted(prompt: true)
        openAccessibilitySettings()
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    static let shared = SetupWindowController()
    private var window: NSWindow?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        Task { await SetupMonitor.shared.refreshEngine() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 820),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = String(localized: "Set up Takes")
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        // Stay above System Settings so the steps are visible while granting access.
        window.level = .floating
        window.backgroundColor = NSColor(Theme.chrome)
        window.collectionBehavior = [.fullScreenNone]
        window.delegate = self
        window.contentView = NSHostingView(rootView: SetupView(monitor: SetupMonitor.shared, onDone: { [weak self] in self?.close() }))
        window.center()
        return window
    }
}

struct SetupView: View {
    @ObservedObject var monitor: SetupMonitor
    @ObservedObject var store = Store.shared
    let onDone: () -> Void
    @ObservedObject var installer = ClaudeInstaller.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(monitor.allSet ? "You're all set" : "Takes needs a couple of things")
                    .font(.system(size: 22, weight: .bold))
                Text(monitor.allSet
                     ? "Press \(store.settings.summonHotKey.inline) in any text field to start."
                     : "This window updates by itself as you finish each step.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 28)
            .padding(.top, 36)
            .padding(.bottom, 20)

            VStack(spacing: 12) {
                accessibilityStep
                engineStep
                privacyStep
                hotKeyStep
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 20)
            Divider()
            HStack {
                Button("Open Settings") {
                    onDone()
                    SettingsWindowController.shared.show(tab: .model)
                }
                .buttonStyle(SecondaryButtonStyle(height: 36))
                Spacer()
                Button(monitor.allSet ? "Done" : "Close", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
        .frame(width: 640, height: 820)
        .background(Theme.chrome)
        .onExitCommand(perform: onDone)
        .tint(Theme.accent)
        .animation(.easeOut(duration: 0.2), value: monitor.accessibility)
        .animation(.easeOut(duration: 0.2), value: monitor.engine)
    }

    private var accessibilityStep: some View {
        SetupStep(number: 1, title: String(localized: "Allow Accessibility access"), done: monitor.accessibility,
                  status: monitor.accessibility ? String(localized: "Allowed") : String(localized: "Needed"),
                  detail: String(localized: "Lets Takes read the text box you're typing in and paste the take back into it.")) {
            if !monitor.accessibility {
                HStack(spacing: 8) {
                    Button("Open Accessibility settings", action: monitor.requestAccessibility)
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Show Takes in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                }
                Text("Switch Takes on in the list, or drag it in from Finder. If Takes is already listed and switched on, select it, remove it with –, and add it again: macOS keeps access tied to the previous version after an update.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var engineStep: some View {
        let done = monitor.engine.isReady
        let status: String
        switch monitor.engine {
        case .checking: status = String(localized: "Checking…")
        case .ready(let text), .problem(let text): status = text
        }
        return SetupStep(number: 2, title: String(localized: "Connect a model"), done: done, status: status, detail: engineDetail) {
            if !done, monitor.engine != .checking {
                if store.settings.engine == .claudeCode {
                    let missing = monitor.engine == .problem(SetupMonitor.claudeMissing)
                    HStack(spacing: 8) {
                        if missing {
                            Button(installer.state.isBusy ? String(localized: "Installing…") : String(localized: "Install Claude Code")) {
                                Task { if await installer.installAfterConfirming() { ClaudeCodeEngine.openSignIn() } }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(installer.state.isBusy)
                        } else {
                            Button("Sign in to Claude", action: ClaudeCodeEngine.openSignIn)
                                .buttonStyle(PrimaryButtonStyle())
                        }
                        Button("Use an API key instead") {
                            onDone()
                            SettingsWindowController.shared.show(tab: .model)
                        }
                    }
                    Text(installer.state.progress ?? installer.state.error
                         ?? (missing ? String(localized: "Takes installs it for you from Anthropic, then Terminal opens so you can sign in.")
                                     : String(localized: "Terminal opens and takes you to your browser to sign in. Nothing to type.")))
                        .font(.system(size: 12))
                        .foregroundStyle(installer.state.error == nil ? Theme.secondaryText : Theme.avoidText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Button(engineButton) {
                        onDone()
                        SettingsWindowController.shared.show(tab: .model)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    private var engineDetail: String {
        switch store.settings.engine {
        case .claudeCode: return String(localized: "Takes runs Claude Code on this Mac, using your Claude subscription.")
        case .apiKey: return String(localized: "Takes calls Claude with your Anthropic API key.")
        case .local: return String(localized: "Takes runs a local model with Ollama or LM Studio. Nothing leaves this Mac.")
        case .chatGPT: return String(localized: "Takes writes with your ChatGPT plan after you sign in with ChatGPT.")
        case .provider: return String(localized: "Takes calls \(Provider.current(store.settings).name) with your own API key.")
        }
    }

    private var engineButton: String {
        switch store.settings.engine {
        case .chatGPT: return String(localized: "Sign in with ChatGPT")
        case .local: return String(localized: "Open Engine settings")
        case .claudeCode, .apiKey, .provider: return String(localized: "Add your API key")
        }
    }

    private var privacyStep: some View {
        let accepted = store.settings.privacyAccepted
        return SetupStep(number: 3, title: String(localized: "Your text and the model"), done: accepted,
                         status: accepted ? String(localized: "Understood") : String(localized: "Please read"),
                         detail: String(localized: "When you press the hotkey, Takes reads the text box you're typing in. \(SetupMonitor.privacySummary(for: store.settings)) Nothing goes to the developer: there's no server and no tracking. \(SetupMonitor.mistakesNote(for: store.settings))")) {
            HStack(spacing: 8) {
                if !accepted {
                    Button("I understand") { store.settings.privacyAccepted = true }
                        .buttonStyle(PrimaryButtonStyle())
                }
                Button("Read the privacy notice") { NSWorkspace.shared.open(SetupMonitor.privacyURL) }
                    .buttonStyle(SecondaryButtonStyle(height: accepted ? 32 : 36))
            }
            if !accepted {
                Text("Don't use Takes on text you're not allowed to share with an AI provider, such as confidential work material.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var hotKeyStep: some View {
        let free = monitor.takenHotKeys.isEmpty
        let taken = monitor.takenHotKeys.map { combo in
            SystemShortcuts.owner(of: combo).map { String(localized: "\(combo.inline) (macOS: \($0))") }
                ?? String(localized: "\(combo.inline) (another app)")
        }.joined(separator: ", ")
        return SetupStep(number: 4, title: String(localized: "Hotkey"), done: free,
                         status: free ? store.settings.summonHotKey.display : String(localized: "Taken: \(taken)"),
                         detail: free ? String(localized: "Press it in any text field to open Takes.")
                                      : String(localized: "Pick a different shortcut, or turn the macOS one off in System Settings › Keyboard › Keyboard Shortcuts.")) {
            if !free {
                Button("Change shortcut") {
                    onDone()
                    SettingsWindowController.shared.show(tab: .model)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }
}

private struct SetupStep<Actions: View>: View {
    let number: Int
    let title: String
    let done: Bool
    let status: String
    let detail: String
    @ViewBuilder var actions: Actions

    var body: some View {
        StepCard(highlighted: !done) {
            HStack(alignment: .top, spacing: 14) {
                StepBadge(number: number, state: done ? .done : .current)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(title).font(.system(size: 15, weight: .semibold))
                        StatusPill(text: status, good: done)
                    }
                    Text(detail).font(.system(size: 13)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
                    actions
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(number), \(title), \(status)")
    }
}
