import AppKit
import Combine
import SwiftUI

/// State behind the onboarding window: the step flow plus what each step shows.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var flow: OnboardingFlow {
        didSet {
            if flow.progress != oldValue.progress { save(flow.progress) }
            if flow.step != oldValue.step {
                forward = flow.index >= oldValue.index
                onStepChange(flow.step)
            }
        }
    }
    /// Which way the last step change went, so the new step pushes in from that side.
    private(set) var forward = true
    /// Claude Code was found on this Mac; Connect a model says so on its card.
    @Published var claudeInstalled = false
    /// Ollama or LM Studio answered with at least one model.
    @Published var localRunning = false
    /// Ways to connect that are already set up on this Mac (signed in, a key saved, a model running).
    @Published var setUpEngines: Set<EngineKind> = []
    /// An option is picked on Connect a model. Until the user picks one, or one is already set up, none is.
    @Published var engineChosen = false
    @Published var engineStatus = SetupMonitor.EngineStatus.checking
    /// Claude Code's state from the last check, which picks its button; nil before a check.
    @Published var claudeState: ClaudeCodeEngine.Status.State?
    @Published var engineKind = EngineKind.claudeCode {
        didSet { if engineKind != oldValue { onEngineKindChange(engineKind) } }
    }
    @Published var hotKey = AppSettings().summonHotKey
    /// Who already uses the hotkey ("macOS: Show Finder search window", "Raycast", "another app"), or nil when it's free.
    @Published var hotKeyOwner: String?
    /// Free hotkeys to pick instead, from HotKeyChoice; empty in tests and snapshots unless set.
    @Published var hotKeySuggestions: [KeyCombo] = []
    /// Open Takes when the user logs in (Done step). Off by default; the app wires it to LaunchAtLogin.
    @Published var launchAtLogin = false {
        didSet { if launchAtLogin != oldValue { setLaunchAtLogin(launchAtLogin) } }
    }
    /// Why the login item couldn't be set, shown under the toggle; nil when it worked.
    @Published var launchAtLoginError: String?
    var setLaunchAtLogin: (Bool) -> Void = { _ in }
    /// Takes runs from the disk image or a temporary copy (AppLocation); Allow access offers to move it first.
    @Published var needsMove = false
    @Published var moveError: String?
    /// "Open System Settings" was pressed and access still isn't there a while later: the troubleshooting shows.
    @Published var accessibilityHelp = false
    var accessibilityHelpDelay: TimeInterval = 8
    @Published var apiKeyInput = ""
    /// Anthropic is being asked about the key just pasted.
    @Published var checkingKey = false
    /// What saving the Anthropic key found; nil when it was saved and works, or nothing was saved yet.
    @Published var apiKeySave: APIKeySave?
    /// The provider key being pasted; the primary button saves it.
    @Published var providerKeyInput = ""
    /// The keychain refused the provider key.
    @Published var providerKeyNotSaved = false
    /// Terminal was opened to sign in to Claude; the page says what to do there.
    @Published var signInOpened = false
    /// Installs Claude Code when it's missing. Its progress shows on the page and in the button.
    var installer = ClaudeInstaller.shared {
        didSet { observeInstaller() }
    }
    @Published var practiceText = Onboarding.sampleDraft
    @Published var practiceStage = PracticeStage.write
    /// A step that has just become true, shown with its check for a moment before moving on.
    @Published var justPassed: OnboardingStep?

    // Seams: the app wires these to the real Mac; tests and snapshots leave them or use fakes.
    var save: (OnboardingProgress) -> Void = { _ in }
    var onStepChange: (OnboardingStep) -> Void = { _ in }
    var onEngineKindChange: (EngineKind) -> Void = { _ in }
    var onClose: () -> Void = {}
    var onFinish: () -> Void = {}
    /// Opens the panel on the practice box: (text, box frame on screen, paste, cancel).
    var openPractice: (String, CGRect?, @escaping (String) -> Void, @escaping () -> Void) -> Void = { _, _, _, _ in }
    /// The practice box's frame on screen, so the panel opens beside it.
    var practiceBoxFrame: () -> CGRect? = { nil }
    var autoAdvanceDelay: TimeInterval = 0.9
    /// Saves the privacy consent; the app writes it to settings, tests and snapshots leave it.
    var recordPrivacyAccepted: () -> Void = {}
    /// Shows macOS's Accessibility prompt and its Settings pane.
    var requestAccess: () -> Void = {}
    /// Asks Anthropic about a key, and saves one to the keychain; the app uses the real ones.
    var checkAPIKey: (String) async -> APIKeyCheck = { _ in .couldNotCheck("") }
    var storeAPIKey: (String) -> Bool = { _ in false }
    /// Checks the engine again (the app: `SetupMonitor.refreshEngine`).
    var refreshEngine: () async -> Void = {}

    private var subscriptions: Set<AnyCancellable> = []
    private var installerSubscription: AnyCancellable?

    init(progress: OnboardingProgress = OnboardingProgress(), conditions: OnboardingConditions = OnboardingConditions()) {
        flow = OnboardingFlow(progress: progress, conditions: conditions)
        observeInstaller()
    }

    private func observeInstaller() {
        installerSubscription = installer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// What Claude Code's button does: install, update, sign in or check again. Before a check has said which,
    /// the status line decides between installing and signing in.
    var claudeAction: ClaudeCodeAction {
        if let state = claudeState { return ClaudeCodeAction(state) ?? .checkAgain }
        return engineStatus == .problem(SetupMonitor.claudeMissing) ? .install : .signIn
    }

    /// Claude Code isn't on this Mac, so Connect a model offers to install it.
    var claudeMissing: Bool { claudeAction == .install }

    var step: OnboardingStep { flow.step }

    /// The option shown as picked.
    func isChosen(_ kind: EngineKind) -> Bool { engineChosen && engineKind == kind }

    /// Picks a way to connect. Picking also replaces an engine saved by a newer version that this one doesn't know.
    func choose(_ kind: EngineKind) {
        engineChosen = true
        apiKeySave = nil
        providerKeyNotSaved = false
        if engineKind != kind { engineKind = kind } else { onEngineKindChange(kind) }
    }

    // MARK: Live

    /// Follows `SetupMonitor` and the settings, and writes progress and choices back.
    func bindLive() {
        let monitor = SetupMonitor.shared
        let store = Store.shared
        engineKind = store.settings.engine
        engineChosen = monitor.engine.isReady && !store.settings.engineNeedsChoice
        claudeInstalled = ClaudeCodeEngine.claudePath != nil
        hotKey = store.settings.summonHotKey
        recordPrivacyAccepted = { store.settings.privacyAccepted = true }
        save = { progress in if store.settings.onboarding != progress { store.settings.onboarding = progress } }
        requestAccess = { monitor.requestAccessibility() }
        checkAPIKey = { await APIEngine.checkKey($0) }
        storeAPIKey = { Keychain.setAPIKey($0) }
        refreshEngine = { await monitor.refreshEngine() }
        launchAtLogin = LaunchAtLogin.isEnabled
        needsMove = AppLocation.needsMove
        setLaunchAtLogin = { [weak self] on in
            do {
                try LaunchAtLogin.set(on)
                self?.launchAtLoginError = nil
            } catch {
                self?.launchAtLoginError = LaunchAtLogin.explain(error)
                if self?.launchAtLogin != LaunchAtLogin.isEnabled { self?.launchAtLogin = LaunchAtLogin.isEnabled }
            }
        }
        onEngineKindChange = { [weak self] kind in
            if store.settings.engine != kind || store.settings.engineNeedsChoice { store.settings.engine = kind }
            if kind == .local { self?.checkLocalEngine() }
        }

        func read(_ accessibility: Bool, _ engine: SetupMonitor.EngineStatus, _ taken: [KeyCombo], _ settings: AppSettings) -> OnboardingConditions {
            engineStatus = engine
            claudeState = monitor.claudeCode?.state
            if engineKind != settings.engine { engineKind = settings.engine }
            // Set up while this window was open (signed in to Claude Code in Terminal): that's the one.
            if engine.isReady, !settings.engineNeedsChoice, !engineChosen { engineChosen = true }
            hotKey = settings.summonHotKey
            let clash = taken.contains(settings.summonHotKey)
            hotKeyOwner = clash ? HotKeyChoice.owner(of: settings.summonHotKey) : nil
            // Registering a candidate is how "free" is known, so only look while there's a reason to show them.
            hotKeySuggestions = clash ? HotKeyChoice.suggestions(current: settings.summonHotKey, taken: taken) : []
            return OnboardingConditions(accessibility: accessibility, engineReady: engine.isReady && !settings.engineNeedsChoice,
                                        privacyAccepted: settings.privacyAccepted, hotKeyFree: !clash)
        }
        // Start from how things are now, so a step finished while Takes was closed isn't asked again.
        var resumed = flow
        resumed.conditions = read(monitor.accessibility, monitor.engine, monitor.takenHotKeys, store.settings)
        resumed.resume()
        flow = resumed

        Publishers.CombineLatest4(monitor.$accessibility, monitor.$engine, monitor.$takenHotKeys, store.$settings)
            .receive(on: RunLoop.main)
            .sink { [weak self] accessibility, engine, taken, settings in
                guard let self else { return }
                // Claude Code installed while setup is open: the engine check just found it.
                if !claudeInstalled, ClaudeCodeEngine.knownClaudePath != nil { claudeInstalled = true }
                setConditions(read(accessibility, engine, taken, settings))
            }
            .store(in: &subscriptions)
        monitor.$claudeCode
            .receive(on: RunLoop.main)
            .sink { [weak self] status in self?.claudeState = status?.state }
            .store(in: &subscriptions)
        detectEngine()
    }

    /// Before Connect a model is reached, looks for what's already set up on this Mac, and opens on it.
    private func detectEngine() {
        guard flow.index <= OnboardingStep.allCases.firstIndex(of: .engine) ?? 0, !flow.conditions.engineReady else { return }
        let settings = Store.shared.settings
        Task { [weak self] in
            await LocalModels.shared.refresh()
            let claudePath = await ClaudeCodeEngine.locate()
            let running = LocalModels.shared.running.contains { !($0.models ?? []).isEmpty }
            var setUp: Set<EngineKind> = []
            // The engine already picked is checked by SetupMonitor; Claude Code is asked here only otherwise.
            if claudePath != nil, settings.engine != .claudeCode || settings.engineNeedsChoice,
               await ClaudeCodeEngine.status().state == .ready {
                setUp.insert(.claudeCode)
            }
            if Keychain.apiKey?.isEmpty == false { setUp.insert(.apiKey) }
            if ChatGPTSignIn.shared.canUsePlan { setUp.insert(.chatGPT) }
            if Provider.current(settings).key != nil { setUp.insert(.provider) }
            if running { setUp.insert(.local) }
            guard let self else { return }
            claudeInstalled = claudePath != nil
            localRunning = running
            setUpEngines = setUp
            preselect()
        }
    }

    /// Picks the option already set up on this Mac, if any and if the user hasn't picked one.
    func preselect() {
        guard !engineChosen else { return }
        let ready = engineStatus.isReady && !Store.shared.settings.engineNeedsChoice
        if let pick = Onboarding.preselectedEngine(current: engineKind, currentReady: ready, setUp: setUpEngines) { choose(pick) }
    }

    /// Get started on the opening screen.
    func openingDone() { go { $0.progress.openingSeen = true } }

    /// New conditions. A step that has just come true shows its check, then moves on by itself.
    func setConditions(_ conditions: OnboardingConditions) {
        var next = flow
        let passed = next.update(conditions)
        flow = next
        guard passed else { return }
        let step = flow.step
        justPassed = step
        let advance = { [weak self] in
            guard let self, self.flow.step == step, self.flow.isCurrentSatisfied else { return }
            self.justPassed = nil
            self.go { $0.next() }
        }
        if autoAdvanceDelay > 0 {
            let delay = UInt64(autoAdvanceDelay * 1_000_000_000)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: delay)
                advance()
            }
        } else {
            advance()
        }
    }

    private func go(_ change: (inout OnboardingFlow) -> Void) {
        var next = flow
        change(&next)
        flow = next
    }

    // MARK: Navigation

    func back() { justPassed = nil; go { $0.back() } }

    func skip() {
        justPassed = nil
        if step == .practice, practiceStage == .panelOpen { return }
        go { $0.skip() }
    }

    /// Esc: back one step, or close the window on the first one.
    func escape() { flow.canGoBack ? back() : onClose() }

    func finish() {
        go { $0.finish() }
        onFinish()
    }

    var canSkip: Bool { step == .practice && practiceStage != .pasted }

    // MARK: Primary action

    /// Connect a model asks for consent in a sentence above the button until it's been given; pressing the button
    /// is the consent.
    var needsConsent: Bool { step == .engine && engineChosen && !flow.conditions.privacyAccepted }

    /// What Connect a model's button does for the picked engine.
    private var engineAction: String {
        switch engineKind {
        case .apiKey: return checkingKey ? String(localized: "Checking your key…") : String(localized: "Save key")
        case .local:
            if engineStatus == .checking { return String(localized: "Checking…") }
            return String(localized: "Check again")
        case .chatGPT:
            if ChatGPTSignIn.shared.state == .signingIn { return String(localized: "Waiting for the browser…") }
            // Signed in but no model yet (the list couldn't be fetched): ask OpenAI again, not for another sign-in.
            if ChatGPTSignIn.shared.canUsePlan { return String(localized: "Check again") }
            return String(localized: "Continue with ChatGPT")
        case .provider:
            if !ProviderModels.shared.hasKey { return String(localized: "Save key") }
            return ProviderModels.shared.state == .checking ? String(localized: "Checking…") : String(localized: "Check again")
        case .claudeCode:
            if engineStatus == .checking { return String(localized: "Checking…") }
            if installer.state.isBusy { return String(localized: "Installing…") }
            return claudeAction.title
        }
    }

    var primaryTitle: String {
        switch step {
        case .accessibility: return flow.isCurrentSatisfied ? String(localized: "Continue") : String(localized: "Open System Settings")
        case .engine:
            if flow.isCurrentSatisfied || flow.conditions.engineReady || !engineChosen { return String(localized: "Continue") }
            return engineAction
        case .practice: return practiceStage == .pasted ? String(localized: "Continue") : String(localized: "Open Takes")
        case .done: return String(localized: "Start using Takes")
        }
    }

    var primaryEnabled: Bool {
        switch step {
        case .engine:
            if flow.isCurrentSatisfied { return true }
            guard engineChosen else { return false }
            if flow.conditions.engineReady { return true }
            switch engineKind {
            case .apiKey: return !checkingKey && !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .chatGPT: return ChatGPTSignIn.shared.state != .signingIn
            case .provider:
                if !ProviderModels.shared.hasKey { return !providerKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                return ProviderModels.shared.state != .checking
            case .local, .claudeCode: return engineStatus != .checking && !installer.state.isBusy
            }
        case .practice: return practiceStage != .panelOpen
        default: return true
        }
    }

    func primary() {
        guard primaryEnabled else { return }
        switch step {
        case .accessibility:
            if flow.isCurrentSatisfied { go { $0.next() } } else { requestAccessibility() }
        case .engine:
            acceptPrivacy()
            if flow.isCurrentSatisfied { go { $0.next() }; return }
            switch engineKind {
            case .apiKey: saveAPIKey()
            case .local: checkLocalEngine()
            case .chatGPT: ChatGPTSignIn.shared.canUsePlan ? checkChatGPTModels() : ChatGPTSignIn.shared.start()
            case .provider: ProviderModels.shared.hasKey ? checkProvider() : saveProviderKey()
            case .claudeCode: runClaude(claudeAction)
            }
        case .practice:
            if practiceStage == .pasted { go { $0.next() } } else { startPractice() }
        case .done:
            finish()
        }
    }

    // MARK: Steps

    /// "Open System Settings" on Allow access. If access still isn't there a while later, the troubleshooting
    /// (Takes listed but switched on after an update) shows; before that it would only be in the way.
    func requestAccessibility() {
        requestAccess()
        let delay = accessibilityHelpDelay
        Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard let self, self.step == .accessibility, !self.flow.conditions.accessibility else { return }
            self.accessibilityHelp = true
        }
    }

    /// Pressing Connect a model's button below the consent sentence: the user has read where their text goes.
    func acceptPrivacy() {
        guard !flow.conditions.privacyAccepted else { return }
        recordPrivacyAccepted()
        var conditions = flow.conditions
        conditions.privacyAccepted = true
        go { _ = $0.update(conditions) }
    }

    /// Looks for Ollama / LM Studio again; picks the first installed model if none is picked yet.
    func checkLocalEngine() {
        Task {
            await LocalModels.shared.refresh()
            await refreshEngine()
        }
    }

    /// Signed in with ChatGPT but no model yet (the list couldn't be fetched): ask OpenAI again.
    func checkChatGPTModels() {
        Task {
            ChatGPTModels.shared.checked = false
            await ChatGPTModels.shared.refresh()
            await refreshEngine()
        }
    }

    /// Asks the provider again, not answered from the cache.
    func checkProvider() {
        Task {
            await ProviderModels.shared.refresh(force: true)
            await refreshEngine()
        }
    }

    func saveProviderKey() {
        let key = providerKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        providerKeyInput = ""
        providerKeyNotSaved = !ProviderModels.shared.saveKey(key)
    }

    func moveToApplications() {
        Task {
            do {
                try await AppLocation.moveToApplications()
                moveError = nil
            } catch {
                moveError = error.localizedDescription
            }
        }
    }

    /// The hotkey chips on Try it: one click picks the combo.
    func pickHotKey(_ combo: KeyCombo) { Store.shared.settings.summonHotKey = combo }

    /// Claude Code's button: install, update, sign in, or check again.
    func runClaude(_ action: ClaudeCodeAction) {
        switch action {
        case .install: installClaudeCode()
        case .update: ClaudeCodeEngine.openUpdate()
        case .signIn: openSignIn()
        case .checkAgain: Task { await refreshEngine() }
        }
    }

    /// Opens Terminal running Claude Code's own sign-in. Nothing to type or paste; the page moves on once
    /// `claude auth status` says signed in.
    func openSignIn() {
        ClaudeCodeEngine.openSignIn()
        signInOpened = true
    }

    /// Installs Claude Code after the person confirms, then goes straight on to sign-in.
    func installClaudeCode() {
        Task { [weak self] in
            guard let self, await installer.installAfterConfirming() else { return }
            claudeInstalled = true
            await refreshEngine()
            if claudeState == .signedOut { openSignIn() }
        }
    }

    /// Saves the pasted Anthropic key after Anthropic has seen it (no tokens spent). A refused key isn't saved.
    func saveAPIKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !checkingKey else { return }
        checkingKey = true
        apiKeySave = nil
        Task { [weak self] in
            guard let self else { return }
            let result = await APIKeySave.save(key, check: checkAPIKey, store: storeAPIKey)
            checkingKey = false
            apiKeySave = result
            if result != .notSaved { apiKeyInput = "" }
            await refreshEngine()
        }
    }

    // MARK: Practice

    /// The hotkey or "Open Takes" on the practice step: the real panel opens on the practice box.
    func startPractice() {
        guard step == .practice, practiceStage != .panelOpen else { return }
        practiceStage = .panelOpen
        openPractice(practiceText, practiceBoxFrame(), { [weak self] take in
            self?.practicePasted(take)
        }, { [weak self] in
            guard let self, self.practiceStage == .panelOpen else { return }
            self.practiceStage = .write
        })
    }

    func practicePasted(_ take: String) {
        practiceText = take
        practiceStage = .pasted
        go { $0.progress.practiced = true }
    }
}

/// The onboarding window: one per launch, closed with ⌘W or Esc on the first step, reopened where it was left.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?
    private(set) var model: OnboardingModel?
    /// Opens the panel on the practice box; set by the app delegate to its panel controller.
    var openPractice: (String, CGRect?, @escaping (String) -> Void, @escaping () -> Void) -> Void = { _, _, _, _ in }

    static let size = CGSize(width: 780, height: 620)

    var isVisible: Bool { window?.isVisible == true }

    /// While the practice step is on screen, the hotkey opens the panel on the practice box.
    var handlesHotKey: Bool { isVisible && model?.step == .practice }

    /// Runs once onboarding's last step is done and its window has closed; the app points at the menu-bar icon.
    var onFinished: () -> Void = {}

    /// Opens onboarding where it was left: the opening screen first if Get started hasn't been pressed yet.
    /// On `screen`, else the display under the pointer.
    func show(on screen: NSScreen? = nil) {
        let model = self.model ?? makeModel()
        self.model = model
        let screen = screen ?? ScreenChoice.active
        if !model.flow.progress.openingSeen && window?.isVisible != true {
            OpeningWindowController.shared.show(on: screen) { [weak self] in
                model.openingDone()
                self?.showSteps(on: screen)
            }
            return
        }
        showSteps(on: screen)
    }

    private func showSteps(on screen: NSScreen) {
        guard let model else { return }
        let window = self.window ?? makeWindow(model: model)
        self.window = window
        SetupMonitor.shared.window("onboarding", visible: true)
        Task { await SetupMonitor.shared.refreshEngineUnlessRecent() }
        window.moveToActiveScreen(screen)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func hotKeyPressed() { model?.startPractice() }

    func windowWillClose(_ notification: Notification) {
        SetupMonitor.shared.window("onboarding", visible: false)
    }

    private func makeModel() -> OnboardingModel {
        let model = OnboardingModel(progress: Store.shared.settings.onboarding)
        model.bindLive()
        model.onClose = { [weak self] in self?.window?.performClose(nil) }
        model.onFinish = { [weak self] in
            self?.window?.close()
            // Anything still missing (a skipped hotkey) is in the setup window from here on.
            self?.onFinished()
        }
        model.onStepChange = { [weak self] step in self?.stepChanged(step) }
        model.openPractice = { [weak self] text, frame, paste, cancel in
            self?.openPractice(text, frame, { take in
                paste(take)
                self?.window?.makeKeyAndOrderFront(nil)
            }, cancel)
        }
        return model
    }

    private func makeWindow(model: OnboardingModel) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = String(localized: "Welcome to Takes")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.fullScreenNone]
        window.backgroundColor = NSColor(Theme.surface)
        window.delegate = self
        window.contentView = NSHostingView(rootView: OnboardingView(model: model))
        window.center()
        window.setFrameAutosaveName("TakesOnboarding")
        stepChanged(model.step, window: window)
        return window
    }

    private func stepChanged(_ step: OnboardingStep, window: NSWindow? = nil) {
        guard let window = window ?? self.window else { return }
        // An ordinary window: System Settings, Terminal and the browser the steps send people to must open in
        // front of it, not under it. The step that follows brings it back (below).
        window.level = .normal
        // Back from System Settings: bring the window forward for the next step.
        if step != .accessibility, window.isVisible, !window.isKeyWindow, model?.step != .practice {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
}
