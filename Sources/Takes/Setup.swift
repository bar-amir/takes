import AppKit
import Combine
import SwiftUI

/// Watches everything Takes needs to work: Accessibility access, a working Claude engine, and a free hotkey.
@MainActor
final class SetupMonitor: ObservableObject {
    static let shared = SetupMonitor()

    @Published private(set) var accessibility = FocusReader.isTrusted(prompt: false)
    @Published private(set) var engine: EngineStatus = .checking
    /// Shortcuts macOS refused because another app already uses them, or that a macOS shortcut also fires on.
    @Published var takenHotKeys: [KeyCombo] = []
    /// Re-registers the hotkeys, so a shortcut freed in System Settings is picked up.
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

    func refreshEngine() async {
        lastEngineCheck = Date()
        switch Store.shared.settings.engine {
        case .apiKey:
            engine = Keychain.apiKey?.isEmpty == false ? .ready("Anthropic API key saved") : .problem("No API key saved yet")
        case .claudeCode:
            let status = await ClaudeCodeEngine.status()
            if !status.found {
                engine = .problem("Claude Code isn't installed")
            } else if !status.signedIn {
                engine = .problem("Claude Code isn't signed in")
            } else {
                engine = .ready("Claude Code signed in" + (status.plan.map { " · \($0.capitalized) plan" } ?? ""))
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
        window.title = "Set up Takes"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        // Stay above System Settings so the steps are visible while granting access.
        window.level = .floating
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
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(monitor.allSet ? "You're all set" : "Takes needs a couple of things")
                    .font(.system(size: 22, weight: .bold))
                Text(monitor.allSet
                     ? "Press \(store.settings.summonHotKey.display) in any text field to start."
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
                    SettingsWindowController.shared.show(tab: .engine)
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
        .tint(Theme.accent)
        .animation(.easeOut(duration: 0.2), value: monitor.accessibility)
        .animation(.easeOut(duration: 0.2), value: monitor.engine)
    }

    private var accessibilityStep: some View {
        SetupStep(number: 1, title: "Allow Accessibility access", done: monitor.accessibility,
                  status: monitor.accessibility ? "Allowed" : "Needed",
                  detail: "Lets Takes read the text box you're typing in and paste the take back into it.") {
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
        case .checking: status = "Checking…"
        case .ready(let text), .problem(let text): status = text
        }
        return SetupStep(number: 2, title: "Connect Claude", done: done, status: status,
                         detail: store.settings.engine == .claudeCode
                            ? "Takes runs Claude Code on this Mac, using your Claude subscription."
                            : "Takes calls Claude with your Anthropic API key.") {
            if !done, monitor.engine != .checking {
                if store.settings.engine == .claudeCode {
                    HStack(spacing: 8) {
                        Button(copied ? "Copied" : "Copy “claude auth login”") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("claude auth login", forType: .string)
                            copied = true
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        Button("Open Terminal") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                        }
                        Button("Use an API key instead") {
                            onDone()
                            SettingsWindowController.shared.show(tab: .engine)
                        }
                    }
                    Text("Paste the command in Terminal, sign in in the browser, then paste the code it shows back into Terminal.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    Button("Add your API key") {
                        onDone()
                        SettingsWindowController.shared.show(tab: .engine)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    private var privacyStep: some View {
        let accepted = store.settings.privacyAccepted
        return SetupStep(number: 3, title: "Your text and Claude", done: accepted,
                         status: accepted ? "Understood" : "Please read",
                         detail: "When you press the hotkey, Takes reads the text box you're typing in. When you ask for takes, it sends your draft and your preset's instructions straight from your Mac to Anthropic, under your own Claude account. Nothing goes to the developer: there's no server and no tracking. Claude can get things wrong, so read a take before you send it.") {
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
        return SetupStep(number: 4, title: "Hotkey", done: free,
                         status: free ? store.settings.summonHotKey.display
                                      : "Taken: " + monitor.takenHotKeys.map { combo in
                                          SystemShortcuts.owner(of: combo).map { "\(combo.display) (macOS: \($0))" } ?? "\(combo.display) (another app)"
                                      }.joined(separator: ", "),
                         detail: free ? "Press it in any text field to open Takes."
                                      : "Pick a different shortcut, or turn the macOS one off in System Settings › Keyboard › Keyboard Shortcuts.") {
            if !free {
                Button("Change shortcut") {
                    onDone()
                    SettingsWindowController.shared.show(tab: .engine)
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
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(done ? Theme.doFill : Theme.accentSoft).frame(width: 30, height: 30)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.doText)
                } else {
                    Text("\(number)").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accent)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(status)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .foregroundStyle(done ? Theme.doText : Theme.avoidText)
                        .background(Capsule().fill(done ? Theme.doFill : Theme.avoidFill))
                }
                Text(detail).font(.system(size: 13)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
                actions
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(done ? Theme.border : Theme.accent.opacity(0.5)))
    }
}
