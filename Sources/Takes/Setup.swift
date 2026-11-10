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
    @Published var takenHotKeys: [KeyCombo] = [] {
        didSet { updateHotKeyRecheck() }
    }
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

    /// What the last Claude Code check found, for the views that say what to do about it; nil before one has run.
    @Published private(set) var claudeCode: ClaudeCodeEngine.Status?

    private var timer: Timer?
    /// While a hotkey is taken and no setup window is open: a slow look at whether it has come free (the app that held
    /// it quit). Registering a combo starts no process.
    private var hotKeyTimer: Timer?
    private var polling = SetupPolling()
    /// Windows that show setup state and are open now ("setup", "onboarding", "settings"). Only while there is one
    /// does the monitor look every second; otherwise it checks when the setup window opens or the menu opens.
    private(set) var watchers: Set<String> = []
    /// The engine check under way. There's one at a time: a check asked for meanwhile waits for this one.
    private var inFlight: Task<Void, Never>?
    /// The engine changed while a check was under way, so its answer is about the old one: check once more.
    private var checkAgain = false
    /// Checks the engine the settings name; tests pass a fake.
    private let checkEngine: @MainActor (AppSettings) async -> (EngineStatus, ClaudeCodeEngine.Status?)
    private var settingsSubscription: AnyCancellable?

    private init() {
        checkEngine = { await SetupMonitor.check($0) }
        settingsSubscription = Store.shared.$settings
            .map { EngineChoice(kind: $0.engine, needsChoice: $0.engineNeedsChoice) }
            .removeDuplicates()
            .sink { [weak self] _ in
                // The status is about the engine that was saved; until the new one is checked it's unknown. Said at
                // once, so nothing reads the old engine's "ready" as the new one's.
                if Thread.isMainThread { MainActor.assumeIsolated { self?.engine = .checking } }
                Task { @MainActor in
                    guard let self else { return }
                    self.polling.reset()
                    if self.inFlight != nil { self.checkAgain = true }
                    await self.refreshEngine()
                }
            }
    }

    /// For snapshots and tests: a monitor that shows the given state and never checks anything.
    init(accessibility: Bool, engine: EngineStatus, claudeCode: ClaudeCodeEngine.Status? = nil) {
        self.accessibility = accessibility
        self.engine = engine
        self.claudeCode = claudeCode
        checkEngine = { _ in (engine, claudeCode) }
        frozen = true
    }

    /// For tests: a monitor that checks the engine with `check`, and doesn't follow the settings.
    init(accessibility: Bool, engine: EngineStatus = .checking,
         check: @escaping @MainActor (AppSettings) async -> (EngineStatus, ClaudeCodeEngine.Status?)) {
        self.accessibility = accessibility
        self.engine = engine
        checkEngine = check
    }

    /// Set for a monitor made with fixed state: nothing is checked or polled.
    private var frozen = false

    private struct EngineChoice: Equatable {
        var kind: EngineKind
        var needsChoice: Bool
    }

    /// A window that shows setup state opened (`visible`) or closed. Polling runs while any is open, and starts
    /// afresh, without the back-off, when one opens.
    func window(_ name: String, visible: Bool) {
        if visible {
            if watchers.insert(name).inserted { polling.reset() }
        } else {
            watchers.remove(name)
        }
        // A monitor with fixed state runs the timer too, but its ticks check nothing.
        let poll = !watchers.isEmpty && !Store.readOnly
        if poll, timer == nil {
            // Accessibility can be granted at any moment in System Settings; check every second while setup shows.
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } else if !poll {
            timer?.invalidate()
            timer = nil
        }
        updateHotKeyRecheck()
    }

    /// Whether the once-a-second check is running.
    var isPolling: Bool { timer != nil }

    /// Whether the slow look at taken hotkeys is running (no setup window open).
    var isRecheckingHotKeys: Bool { hotKeyTimer != nil }

    private func updateHotKeyRecheck() {
        let slow = !takenHotKeys.isEmpty && watchers.isEmpty && !Store.readOnly
        if slow, hotKeyTimer == nil {
            hotKeyTimer = Timer.scheduledTimer(withTimeInterval: SetupPolling.hotKeyRecheck, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.recheckHotKeys?() }
            }
        } else if !slow {
            hotKeyTimer?.invalidate()
            hotKeyTimer = nil
        }
    }

    /// The once-a-second look while a setup window is open.
    func tick(now: Date = Date()) {
        refreshAccessibility()
        if !takenHotKeys.isEmpty { recheckHotKeys?() }
        // The model is checked less often, and less often again while it keeps failing: it can run a process. Never
        // while a check is still under way.
        if inFlight == nil, polling.engineDue(ready: engine.isReady, now: now) { startCheck() }
    }

    /// Reads Accessibility access again; it's cheap.
    func refreshAccessibility() {
        guard !frozen, !Store.readOnly else { return }
        let trusted = FocusReader.isTrusted(prompt: false)
        if trusted != accessibility { accessibility = trusted }
    }

    /// One look at everything, for when the menu opens: nothing polls while no setup window is open.
    func checkOnce() {
        refreshAccessibility()
        if !takenHotKeys.isEmpty { recheckHotKeys?() }
        if !engine.isReady, Date().timeIntervalSince(polling.lastCheck) > SetupPolling.recentCheck { startCheck() }
    }

    /// `refreshEngine`, unless a check started moments ago.
    func refreshEngineUnlessRecent() async {
        guard Date().timeIntervalSince(polling.lastCheck) > SetupPolling.recentCheck else { return }
        await refreshEngine()
    }

    nonisolated static let claudeMissing = String(localized: "Claude Code isn't installed")

    enum SummonRoute: Equatable { case panel, setup, pickModel }

    /// Where a hotkey press goes, decided at once from what's known: the setup window while something it needs is
    /// missing (it checks the model as it opens), Settings › Model for an engine this version doesn't know, else the
    /// panel. A model still being checked doesn't hold the press up.
    nonisolated static func summonRoute(accessibility: Bool, privacyAccepted: Bool, needsChoice: Bool,
                                        engine: EngineStatus) -> SummonRoute {
        if !accessibility || !privacyAccepted { return .setup }
        if needsChoice { return .pickModel }
        if case .problem = engine { return .setup }
        return .panel
    }

    /// Whether launch should check the model again before opening the setup window: when it's the only thing
    /// missing. A check can fail once and pass seconds later (a busy Mac right after an update), and the window
    /// shouldn't open just to turn green.
    nonisolated static func recheckBeforeSetup(accessibility: Bool, privacyAccepted: Bool, hotKeyFree: Bool,
                                               engine: EngineStatus) -> Bool {
        accessibility && privacyAccepted && hotKeyFree && !engine.isReady
    }

    /// At launch: checks the model again, up to `attempts` times `pause` apart, while it's the only thing missing.
    func settleEngine(attempts: Int = 3, pause: TimeInterval = 3) async {
        for _ in 0..<attempts {
            guard Self.recheckBeforeSetup(accessibility: accessibility, privacyAccepted: privacyAccepted,
                                          hotKeyFree: takenHotKeys.isEmpty, engine: engine) else { return }
            try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
            // The once-a-second tick may have checked meanwhile.
            if engine.isReady { return }
            await refreshEngine()
        }
    }

    /// The status line while the saved engine is one this version doesn't know (settings from a newer version).
    static let pickAModel = String(localized: "Pick a model")
    /// Why, in setup and Settings › Model.
    static let needsChoiceNote = String(localized: "Your settings name a model this version of Takes doesn't have. Pick one to go on.")

    /// Checks the chosen engine, or waits for the check already under way. Snapshots never check: it would start
    /// `claude` or reach a model server.
    func refreshEngine() async {
        await startCheck()?.value
    }

    /// Starts a check unless one is under way, and returns the one to wait for.
    @discardableResult
    private func startCheck() -> Task<Void, Never>? {
        guard !frozen, !Store.readOnly else { return nil }
        if let inFlight { return inFlight }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                checkAgain = false
                // The back-off counts from when a check starts, so a slow one isn't started again on top of itself.
                polling.started(at: Date())
                let settings = Store.shared.settings
                let answer: (EngineStatus, ClaudeCodeEngine.Status?) = settings.engineNeedsChoice
                    ? (.problem(Self.pickAModel), nil) : await checkEngine(settings)
                if checkAgain { continue }
                polling.checked(ready: answer.0.isReady)
                if let claude = answer.1, claude != claudeCode { claudeCode = claude }
                engine = answer.0
            } while checkAgain
            inFlight = nil
        }
        inFlight = task
        return task
    }

    /// Whether an engine check is under way.
    var isChecking: Bool { inFlight != nil }

    /// The status of the engine `settings` name, and Claude Code's own status when that's the engine.
    static func check(_ settings: AppSettings) async -> (EngineStatus, ClaudeCodeEngine.Status?) {
        switch settings.engine {
        case .local: return (await localEngineStatus(), nil)
        case .provider: return (await providerEngineStatus(), nil)
        case .chatGPT: return (await chatGPTEngineStatus(), nil)
        case .apiKey: return (await apiKeyStatus(), nil)
        case .claudeCode:
            let status = await ClaudeCodeEngine.status()
            return (claudeCodeStatus(status), status)
        }
    }

    /// Ready when a key is saved and Anthropic doesn't refuse it. A key that couldn't be checked (offline) counts as
    /// ready: a run says what's wrong if it still fails. Answers come from `APIKeyCheckCache`, so a key just checked
    /// on saving isn't asked about again.
    static func apiKeyStatus(key: String? = Keychain.apiKey,
                             check: (String) async -> APIKeyCheck = { await APIKeyCheckCache.shared.check($0) })
        async -> EngineStatus {
        guard let key, !key.isEmpty else { return .problem(String(localized: "No API key saved yet")) }
        switch await check(key) {
        case .valid, .couldNotCheck: return .ready(String(localized: "Anthropic API key saved"))
        case .invalid: return .problem(String(localized: "The key was refused"))
        }
    }

    /// Claude Code's status in one line. An old CLI has no `claude auth` and no `--effort`, so it can't be used
    /// until it's updated; a check that hung or a CLI that couldn't start is said so, not reported as signed out.
    nonisolated static func claudeCodeStatus(_ status: ClaudeCodeEngine.Status) -> EngineStatus {
        switch status.state {
        case .notInstalled: return .problem(claudeMissing)
        case .stillLooking: return .problem(String(localized: "Still looking for Claude Code; trying again"))
        case .couldNotStart: return .problem(String(localized: "Claude Code couldn't start"))
        case .notAnswering: return .problem(String(localized: "Claude Code didn't answer; trying again"))
        case .tooOld(let version): return .problem(String(localized: "Claude Code \(version) is too old; update it (claude update)"))
        case .signedOut: return .problem(String(localized: "Claude Code isn't signed in"))
        case .ready:
            return .ready(status.plan.map { String(localized: "Claude Code signed in · \($0.capitalized) plan") }
                ?? String(localized: "Claude Code signed in"))
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

/// When setup looks at the model again. A check can start a login shell and `claude auth status`, so it only runs
/// while a setup, onboarding or Settings window is open, and less often each time it still fails: 5 s after the
/// first failure, then 10, 20 and 40, then once a minute. Opening a window or changing the engine starts over.
struct SetupPolling: Equatable {
    static let firstRetry: TimeInterval = 5
    static let longestRetry: TimeInterval = 60
    /// A check started this recently is answer enough for a window that has just opened or the menu.
    static let recentCheck: TimeInterval = 2
    /// How often a taken hotkey is tried again while no setup window is open.
    static let hotKeyRecheck: TimeInterval = 10

    /// Checks in a row that found the model not ready.
    private(set) var failures = 0
    /// When the last check started.
    private(set) var lastCheck = Date.distantPast

    static func retryDelay(failures: Int) -> TimeInterval {
        min(firstRetry * pow(2, Double(max(0, failures - 1))), longestRetry)
    }

    /// Whether the model is due for another check at `now`.
    func engineDue(ready: Bool, now: Date) -> Bool {
        !ready && now.timeIntervalSince(lastCheck) >= Self.retryDelay(failures: failures)
    }

    mutating func started(at date: Date) { lastCheck = date }

    mutating func checked(ready: Bool) { failures = ready ? 0 : failures + 1 }

    mutating func reset() { failures = 0 }
}

/// What setup, onboarding and Settings › Model offer for each Claude Code state: install it when it's missing,
/// update it when it's too old, sign in when signed out, and check again when it didn't answer or couldn't start.
enum ClaudeCodeAction: Equatable {
    case install, update, signIn, checkAgain

    init?(_ state: ClaudeCodeEngine.Status.State) {
        switch state {
        case .notInstalled: self = .install
        case .tooOld: self = .update
        case .signedOut: self = .signIn
        case .stillLooking, .couldNotStart, .notAnswering: self = .checkAgain
        case .ready: return nil
        }
    }

    /// The button's title.
    var title: String {
        switch self {
        case .install: String(localized: "Install Claude Code")
        case .update: String(localized: "Update Claude Code")
        case .signIn: String(localized: "Sign in to Claude")
        case .checkAgain: String(localized: "Check again")
        }
    }

    /// The line under the button: what happens, or what went wrong.
    static func note(for state: ClaudeCodeEngine.Status.State) -> String? {
        switch state {
        case .notInstalled: String(localized: "Takes installs it for you from Anthropic, then Terminal opens so you can sign in.")
        case .tooOld: String(localized: "Terminal opens and runs claude update. Then press Check again.")
        case .signedOut: String(localized: "Terminal opens and takes you to your browser to sign in. Nothing to type.")
        case .couldNotStart(let reason): reason
        case .notAnswering: String(localized: "Claude Code didn't answer. Check again in a moment.")
        case .stillLooking: String(localized: "Takes is still looking for Claude Code on this Mac.")
        case .ready: nil
        }
    }

    /// The badge in Settings › Model.
    static func badge(for status: ClaudeCodeEngine.Status) -> (text: String, good: Bool) {
        badge(for: status.state, plan: status.plan)
    }

    /// The badge for `state`; also onboarding's status pill, where the setup line would wrap.
    static func badge(for state: ClaudeCodeEngine.Status.State, plan: String? = nil) -> (text: String, good: Bool) {
        switch state {
        case .notInstalled: (String(localized: "Not installed"), false)
        case .stillLooking: (String(localized: "Still looking…"), false)
        case .couldNotStart: (String(localized: "Couldn't start"), false)
        case .notAnswering: (String(localized: "Didn't answer"), false)
        case .tooOld(let version): (String(localized: "Too old (\(version))"), false)
        case .signedOut: (String(localized: "Not signed in"), false)
        case .ready:
            (plan.map { String(localized: "Signed in · \($0.capitalized) plan") } ?? String(localized: "Signed in"), true)
        }
    }
}

extension ClaudeCodeEngine {
    /// Opens Terminal running `claude update`, the same way `openSignIn` opens the sign-in.
    static func openUpdate() {
        let claude = knownClaudePath ?? ClaudeLocator.fixedPath() ?? "claude"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Update Claude Code.command")
        do {
            try updateScript(claudePath: claude).write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        }
    }

    /// What the update window runs: `claude update` by its full path, quoted for the shell.
    static func updateScript(claudePath: String) -> String {
        func quoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let intro = quoted(String(localized: "Updating Claude Code for Takes. When it's done, go back to Takes and press Check again."))
        let done = quoted(String(localized: "You can close this window now."))
        return """
            #!/bin/zsh
            clear
            echo \(intro)
            echo
            \(quoted(claudePath)) update
            echo
            echo \(done)
            """
    }
}

@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    static let shared = SetupWindowController()
    private var window: NSWindow?

    /// On `screen`, else the display under the pointer.
    func show(on screen: NSScreen? = nil) {
        let window = self.window ?? makeWindow()
        self.window = window
        SetupMonitor.shared.window("setup", visible: true)
        Task { await SetupMonitor.shared.refreshEngineUnlessRecent() }
        window.moveToActiveScreen(screen ?? ScreenChoice.active)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        SetupMonitor.shared.window("setup", visible: false)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = String(localized: "Set up Takes")
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        // Stay above System Settings so the steps are visible while granting access.
        window.level = .floating
        window.backgroundColor = NSColor(Theme.chrome)
        window.collectionBehavior = [.fullScreenNone]
        window.delegate = self
        // The window takes the checklist's height and follows it as steps open and close.
        let hosting = NSHostingView(rootView: SetupView(monitor: SetupMonitor.shared, onDone: { [weak self] in self?.close() }))
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.center()
        return window
    }
}

struct SetupView: View {
    @ObservedObject var monitor: SetupMonitor
    @ObservedObject var store = Store.shared
    let onDone: () -> Void
    @State private var copied = false
    @State private var suggestions: [KeyCombo] = []
    @State private var moveError: String?
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
            .padding(.bottom, 24)

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
        .frame(width: 640)
        .fixedSize(horizontal: false, vertical: true)
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
                    if AppLocation.needsMove {
                        Button("Move Takes to Applications") {
                            Task {
                                do { try await AppLocation.moveToApplications(); moveError = nil } catch { moveError = error.localizedDescription }
                            }
                        }
                    } else {
                        Button("Show Takes in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                        }
                    }
                }
                if AppLocation.needsMove {
                    Text(moveError ?? String(localized: "Takes is running from \(AppLocation.whereItRuns). Move it to Applications first, so the access you allow stays with it."))
                        .font(.system(size: 12))
                        .foregroundStyle(moveError == nil ? Theme.secondaryText : Theme.avoidText)
                        .fixedSize(horizontal: false, vertical: true)
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
                if !store.settings.engineNeedsChoice, store.settings.engine == .claudeCode, let state = monitor.claudeCode?.state,
                   let action = installer.state.isBusy ? .install : ClaudeCodeAction(state) {
                    HStack(spacing: 8) {
                        Button(installer.state.isBusy ? String(localized: "Installing…") : action.title) { run(action) }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(installer.state.isBusy)
                        if action != .checkAgain {
                            Button("Check again") { Task { await monitor.refreshEngine() } }
                        }
                    }
                    if let note = installer.state.progress ?? installer.state.error ?? ClaudeCodeAction.note(for: state) {
                        Text(note)
                            .font(.system(size: 12))
                            .foregroundStyle(installer.state.error == nil && !isFailure(state) ? Theme.secondaryText : Theme.avoidText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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

    /// A state whose note says what went wrong rather than what happens next.
    private func isFailure(_ state: ClaudeCodeEngine.Status.State) -> Bool {
        if case .couldNotStart = state { return true }
        return state == .notAnswering
    }

    private func run(_ action: ClaudeCodeAction) {
        switch action {
        case .install:
            Task {
                if await installer.installAfterConfirming() {
                    await monitor.refreshEngine()
                    if monitor.claudeCode?.state == .signedOut { ClaudeCodeEngine.openSignIn() }
                }
            }
        case .update: ClaudeCodeEngine.openUpdate()
        case .signIn: ClaudeCodeEngine.openSignIn()
        case .checkAgain: Task { await monitor.refreshEngine() }
        }
    }

    private var engineDetail: String {
        if store.settings.engineNeedsChoice {
            return SetupMonitor.needsChoiceNote
        }
        switch store.settings.engine {
        case .claudeCode: return String(localized: "Takes runs Claude Code on this Mac, using your Claude subscription.")
        case .apiKey: return String(localized: "Takes calls Claude with your Anthropic API key.")
        case .local: return String(localized: "Takes runs a local model with Ollama or LM Studio. Nothing leaves this Mac.")
        case .chatGPT: return String(localized: "Takes writes with your ChatGPT plan after you sign in with ChatGPT.")
        case .provider: return String(localized: "Takes calls \(Provider.current(store.settings).name) with your own API key.")
        }
    }

    private var engineButton: String {
        if store.settings.engineNeedsChoice { return String(localized: "Open Settings") }
        switch store.settings.engine {
        case .chatGPT: return String(localized: "Sign in with ChatGPT")
        case .local: return String(localized: "Open Engine settings")
        case .claudeCode: return String(localized: "Open Settings")
        case .apiKey, .provider: return String(localized: "Add your API key")
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
        let taken = monitor.takenHotKeys.map { String(localized: "\($0.inline) (\(HotKeyChoice.owner(of: $0)))") }.joined(separator: ", ")
        return SetupStep(number: 4, title: String(localized: "Hotkey"), done: free,
                         status: free ? store.settings.summonHotKey.display : String(localized: "Taken: \(taken)"),
                         detail: free ? String(localized: "Press it in any text field to open Takes.")
                                      : String(localized: "Pick a different shortcut, or turn the other one off in that app or in System Settings › Keyboard › Keyboard Shortcuts.")) {
            if !free {
                HStack(spacing: 8) {
                    Button("Change shortcut") {
                        onDone()
                        SettingsWindowController.shared.show(tab: .general)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    HotKeySuggestionChips(suggestions: suggestions) { store.settings.summonHotKey = $0 }
                }
                .onAppear(perform: refreshSuggestions)
                .onChange(of: monitor.takenHotKeys) { _, _ in refreshSuggestions() }
            }
        }
    }

    private func refreshSuggestions() {
        suggestions = HotKeyChoice.suggestions(current: store.settings.summonHotKey, taken: monitor.takenHotKeys)
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
