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
    /// Looking for what's set up on this Mac has finished.
    var detected = false
    /// An option is highlighted on Connect a model. Until the user picks one, or one is already set up, none is.
    /// Highlighting writes nothing: the engine is saved, and checked, only when the step's button is pressed.
    @Published var engineChosen = false
    /// The status of the saved engine, from `SetupMonitor`.
    @Published var engineStatus = SetupMonitor.EngineStatus.checking
    /// Claude Code's state from the last check, which picks its button; nil before a check.
    @Published var claudeState: ClaudeCodeEngine.Status.State?
    /// The highlighted option.
    @Published var engineKind = EngineKind.claudeCode
    /// The engine saved in settings, and whether it's one this version doesn't know.
    @Published var savedEngine = EngineKind.claudeCode
    var savedNeedsChoice = false
    /// The saved engine works.
    private(set) var savedReady = false
    /// The button just saved an engine: a status from before its check started is about the old engine.
    private var awaitingCheck = false
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
    /// "Move Takes to Applications" is under way; its button is off meanwhile.
    @Published private(set) var moving = false
    /// Moves Takes to Applications; tests pass a fake.
    var move: () async throws -> Void = { try await AppLocation.moveToApplications() }
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
    /// Saves the engine to settings, when the step's button is pressed.
    var writeEngine: (EngineKind) -> Void = { _ in }
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
    /// Reads whether Accessibility access is allowed now (the app: `FocusReader.isTrusted`).
    var isTrusted: () -> Bool = { false }
    /// Asks Anthropic about a key, and saves one to the keychain; the app uses the real ones.
    var checkAPIKey: (String) async -> APIKeyCheck = { _ in .couldNotCheck("") }
    var storeAPIKey: (String) -> Bool = { _ in false }
    /// Checks the engine again (the app: `SetupMonitor.refreshEngine`).
    var refreshEngine: () async -> Void = {}
    /// Asks the provider for its models (`force`: not from the cache), and reads whether a key is saved without
    /// asking the provider anything; the app uses `ProviderModels`.
    var refreshProvider: (_ force: Bool) async -> Void = { _ in }
    var readProviderKey: () -> Void = {}
    /// Looks for Ollama and LM Studio on this Mac (the app: `LocalModels.refresh`).
    var refreshLocal: () async -> Void = {}

    private var subscriptions: Set<AnyCancellable> = []
    private var installerSubscription: AnyCancellable?

    init(progress: OnboardingProgress = OnboardingProgress(), conditions: OnboardingConditions = OnboardingConditions()) {
        flow = OnboardingFlow(progress: progress, conditions: conditions)
        savedReady = conditions.engineReady
        observeInstaller()
    }

    private func observeInstaller() {
        installerSubscription = installer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// What Claude Code's button does: install, update, sign in or check again. Before a check has said which,
    /// the saved engine's status line decides, or else whether Claude Code was found.
    var claudeAction: ClaudeCodeAction {
        if let state = claudeState { return ClaudeCodeAction(state) ?? .checkAgain }
        if savedEngine == .claudeCode, case .problem(let line) = engineStatus { return line == SetupMonitor.claudeMissing ? .install : .signIn }
        return claudeInstalled ? .signIn : .install
    }

    /// The highlighted option is the engine saved in settings, so the monitor's status is about it.
    var pickedIsSaved: Bool { engineKind == savedEngine && !savedNeedsChoice }

    /// Claude Code isn't on this Mac, so Connect a model offers to install it.
    var claudeMissing: Bool { claudeAction == .install }

    var step: OnboardingStep { flow.step }

    /// The option shown as picked.
    func isChosen(_ kind: EngineKind) -> Bool { engineChosen && engineKind == kind }

    /// The user clicked an option. It's highlighted only; the button saves it.
    func choose(_ kind: EngineKind) {
        apiKeySave = nil
        providerKeyNotSaved = false
        highlight(kind)
    }

    private func highlight(_ kind: EngineKind) {
        engineChosen = true
        engineKind = kind
        updateEngineReady()
    }

    /// The step counts as done only for the option on screen: a working saved engine doesn't carry another one.
    private func updateEngineReady() {
        var conditions = flow.conditions
        conditions.engineReady = savedReady && (!engineChosen || pickedIsSaved)
        if conditions != flow.conditions { setConditions(conditions) }
    }

    /// The step's button: saves the highlighted engine (also replacing one saved by a newer version), which starts
    /// its check. Before this nothing is written and nothing is asked of any service.
    private func commitEngine() {
        guard !pickedIsSaved else { return }
        writeEngine(engineKind)
        savedEngine = engineKind
        savedNeedsChoice = false
        savedReady = false
        engineStatus = .checking
        awaitingCheck = true
    }

    /// The saved engine or its status changed (`SetupMonitor`).
    func savedEngineChanged(_ kind: EngineKind, needsChoice: Bool, status: SetupMonitor.EngineStatus) {
        // Until the monitor says it's checking the engine just saved, its answer is still the old engine's.
        if awaitingCheck, status == .checking { awaitingCheck = false }
        let status = awaitingCheck ? .checking : status
        savedEngine = kind
        savedNeedsChoice = needsChoice
        engineStatus = status
        savedReady = status.isReady && !needsChoice
        if !engineChosen { engineKind = kind }
        preselect()
        updateEngineReady()
    }

    // MARK: Live

    /// Follows `SetupMonitor` and the settings, and writes progress and choices back.
    func bindLive() {
        let monitor = SetupMonitor.shared
        let store = Store.shared
        engineKind = store.settings.engine
        claudeInstalled = ClaudeCodeEngine.claudePath != nil
        hotKey = store.settings.summonHotKey
        recordPrivacyAccepted = { store.settings.privacyAccepted = true }
        save = { progress in if store.settings.onboarding != progress { store.settings.onboarding = progress } }
        requestAccess = { monitor.requestAccessibility() }
        isTrusted = { FocusReader.isTrusted(prompt: false) }
        checkAPIKey = { await APIKeyCheckCache.shared.check($0) }
        storeAPIKey = { Keychain.setAPIKey($0) }
        refreshEngine = { await monitor.refreshEngine() }
        refreshProvider = { await ProviderModels.shared.refresh(force: $0) }
        readProviderKey = { ProviderModels.shared.readKey() }
        refreshLocal = { await LocalModels.shared.refresh() }
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
        writeEngine = { kind in
            if store.settings.engine != kind || store.settings.engineNeedsChoice { store.settings.engine = kind }
        }

        func read(_ accessibility: Bool, _ engine: SetupMonitor.EngineStatus, _ taken: [KeyCombo], _ settings: AppSettings) -> OnboardingConditions {
            if let state = monitor.claudeCode?.state { claudeState = state }
            savedEngineChanged(settings.engine, needsChoice: settings.engineNeedsChoice, status: engine)
            hotKey = settings.summonHotKey
            let clash = taken.contains(settings.summonHotKey)
            hotKeyOwner = clash ? HotKeyChoice.owner(of: settings.summonHotKey) : nil
            // Registering a candidate is how "free" is known, so only look while there's a reason to show them.
            hotKeySuggestions = clash ? HotKeyChoice.suggestions(current: settings.summonHotKey, taken: taken) : []
            return OnboardingConditions(accessibility: accessibility, engineReady: savedReady && (!engineChosen || pickedIsSaved),
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
            .sink { [weak self] status in if let status { self?.claudeState = status.state } }
            .store(in: &subscriptions)
        detectEngine()
    }

    /// Before Connect a model is reached, looks for what's already set up on this Mac (no request to any service:
    /// the keychain, the sign-in kept on this Mac, Claude Code's own status, and the local model servers), then
    /// highlights it once the saved engine's first check is in.
    private func detectEngine() {
        guard flow.index <= OnboardingStep.allCases.firstIndex(of: .engine) ?? 0, !flow.conditions.engineReady else {
            detected = true
            return
        }
        let settings = Store.shared.settings
        Task { [weak self] in
            await LocalModels.shared.refresh()
            let claudePath = await ClaudeCodeEngine.locate()
            let running = LocalModels.shared.running.contains { !($0.models ?? []).isEmpty }
            var setUp: Set<EngineKind> = []
            // The saved engine is checked by SetupMonitor; Claude Code is asked here only when it isn't that one.
            var claude: ClaudeCodeEngine.Status?
            if claudePath != nil, settings.engine != .claudeCode || settings.engineNeedsChoice {
                claude = await ClaudeCodeEngine.status()
                if claude?.state == .ready { setUp.insert(.claudeCode) }
            }
            if Keychain.apiKey?.isEmpty == false { setUp.insert(.apiKey) }
            if ChatGPTSignIn.shared.canUsePlan { setUp.insert(.chatGPT) }
            if Provider.current(settings).key != nil { setUp.insert(.provider) }
            if running { setUp.insert(.local) }
            guard let self else { return }
            claudeInstalled = claudePath != nil
            if let claude { claudeState = claude.state }
            localRunning = running
            setUpEngines = setUp
            detected = true
            preselect()
        }
    }

    /// Highlights the option already set up on this Mac, if the user hasn't picked one: the saved engine when it
    /// works, else the first one set up. Waits for the saved engine's first check, so a working Claude Code isn't
    /// passed over for an old key. Writes nothing.
    func preselect() {
        guard !engineChosen, detected, engineStatus != .checking else { return }
        if let pick = Onboarding.preselectedEngine(current: savedEngine, currentReady: savedReady, setUp: setUpEngines) {
            highlight(pick)
        }
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

    /// What Connect a model's button does for the highlighted option. An option that's set up but not saved yet says
    /// Continue: pressing saves it and checks it.
    private var engineAction: String {
        let checking = pickedIsSaved && engineStatus == .checking
        switch engineKind {
        case .apiKey:
            if checkingKey { return String(localized: "Checking your key…") }
            if apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, setUpEngines.contains(.apiKey) {
                return checking ? String(localized: "Checking…") : pickedIsSaved ? String(localized: "Check again") : String(localized: "Continue")
            }
            return String(localized: "Save key")
        case .local:
            if checking { return String(localized: "Checking…") }
            return pickedIsSaved ? String(localized: "Check again") : String(localized: "Continue")
        case .chatGPT:
            if ChatGPTSignIn.shared.state == .signingIn { return String(localized: "Waiting for the browser…") }
            // Signed in but no model yet (the list couldn't be fetched): ask OpenAI again, not for another sign-in.
            if ChatGPTSignIn.shared.canUsePlan { return pickedIsSaved ? String(localized: "Check again") : String(localized: "Continue") }
            return String(localized: "Continue with ChatGPT")
        case .provider:
            if !ProviderModels.shared.hasKey { return String(localized: "Save key") }
            if checking || ProviderModels.shared.state == .checking { return String(localized: "Checking…") }
            return pickedIsSaved ? String(localized: "Check again") : String(localized: "Continue")
        case .claudeCode:
            if checking { return String(localized: "Checking…") }
            if installer.state.isBusy { return String(localized: "Installing…") }
            if claudeState == .ready, !pickedIsSaved { return String(localized: "Continue") }
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
            let checking = pickedIsSaved && engineStatus == .checking
            switch engineKind {
            case .apiKey:
                let typed = !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                return !checkingKey && !checking && (typed || setUpEngines.contains(.apiKey))
            case .chatGPT: return ChatGPTSignIn.shared.state != .signingIn
            case .provider:
                if !ProviderModels.shared.hasKey { return !providerKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                return !checking && ProviderModels.shared.state != .checking
            case .local, .claudeCode: return !checking && !installer.state.isBusy
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
            // From here the highlighted engine is saved and checked: the consent above the button was given.
            let typedKey = !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            commitEngine()
            switch engineKind {
            case .apiKey: if typedKey { saveAPIKey() } else { Task { await refreshEngine() } }
            case .local: checkLocalEngine()
            case .chatGPT: ChatGPTSignIn.shared.canUsePlan ? checkChatGPTModels() : ChatGPTSignIn.shared.start()
            case .provider: ProviderModels.shared.hasKey ? checkProvider() : saveProviderKey()
            case .claudeCode: if claudeState == .ready { Task { await refreshEngine() } } else { runClaude(claudeAction) }
            }
        case .practice:
            if practiceStage == .pasted { go { $0.next() } } else { startPractice() }
        case .done:
            finish()
        }
    }

    // MARK: Steps

    /// "Open System Settings" on Allow access. A while later access is checked again; if that check fails, the
    /// troubleshooting (Takes listed but switched on after an update) shows. Before that it would only be in the way.
    func requestAccessibility() {
        requestAccess()
        let delay = accessibilityHelpDelay
        Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard let self, self.step == .accessibility, !self.flow.conditions.accessibility else { return }
            if !isTrusted() { accessibilityHelp = true }
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
            await refreshLocal()
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
            await refreshProvider(true)
            await refreshEngine()
        }
    }

    /// The provider option opened: what's saved is read from the keychain; the provider itself is asked only once
    /// the consent above the button has been given.
    func providerShown() {
        if flow.conditions.privacyAccepted { Task { await refreshProvider(false) } } else { readProviderKey() }
    }

    /// Another provider picked in the menu; asked only after the consent, as above.
    func selectProvider(_ id: String) {
        ProviderModels.shared.select(id, refresh: flow.conditions.privacyAccepted)
        if !flow.conditions.privacyAccepted { readProviderKey() }
    }

    func saveProviderKey() {
        let key = providerKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        providerKeyInput = ""
        providerKeyNotSaved = !ProviderModels.shared.saveKey(key)
    }

    /// One move at a time: a second click would remove the copy the first is opening.
    func moveToApplications() {
        guard !moving else { return }
        moving = true
        Task {
            do {
                try await move()
                moveError = nil
            } catch {
                moveError = error.localizedDescription
            }
            moving = false
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
