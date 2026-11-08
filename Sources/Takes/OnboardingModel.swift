import AppKit
import Combine
import SwiftUI

/// The starter presets offered in onboarding.
enum OnboardingPresets {
    static func starters(languages: [String]) -> [Preset] { PresetGallery.starters(languages: languages) }
}

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
    /// The option Connect a model opens on; the rest are behind "Other ways to connect".
    @Published var recommendedEngine = EngineKind.claudeCode
    @Published var showOtherEngines = false
    /// English Coach is on; when it's off, Done says it's offered later.
    @Published var coachEnabled = false
    @Published var engineStatus = SetupMonitor.EngineStatus.checking
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
    @Published var apiKeyInput = ""
    /// Terminal was opened to sign in to Claude; the page says what to do there.
    @Published var signInOpened = false
    /// Installs Claude Code when it's missing. Its progress shows on the page and in the button.
    var installer = ClaudeInstaller.shared {
        didSet { observeInstaller() }
    }
    @Published var chosenPresets: Set<String>
    /// The languages the user writes in, shown on the presets step. Adding one offers (and picks) its translate
    /// preset; removing one drops it.
    @Published var languages: [String] {
        didSet {
            guard languages != oldValue else { return }
            let before = Set(OnboardingPresets.starters(languages: oldValue).map(\.name))
            let after = Set(OnboardingPresets.starters(languages: languages).map(\.name))
            chosenPresets.subtract(before.subtracting(after))
            chosenPresets.formUnion(after.subtracting(before))
            saveLanguages(languages)
        }
    }
    var starters: [Preset] { OnboardingPresets.starters(languages: languages) }
    var saveLanguages: ([String]) -> Void = { _ in }
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

    private var subscriptions: Set<AnyCancellable> = []
    private var installerSubscription: AnyCancellable?

    init(progress: OnboardingProgress = OnboardingProgress(), conditions: OnboardingConditions = OnboardingConditions()) {
        flow = OnboardingFlow(progress: progress, conditions: conditions)
        let languages = Languages.fromSystem()
        self.languages = languages
        chosenPresets = Set(OnboardingPresets.starters(languages: languages).map(\.name))
        observeInstaller()
    }

    private func observeInstaller() {
        installerSubscription = installer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// Claude Code isn't on this Mac, so Connect a model offers to install it.
    var claudeMissing: Bool { engineStatus == .problem(SetupMonitor.claudeMissing) }

    var step: OnboardingStep { flow.step }

    // MARK: Live

    /// Follows `SetupMonitor` and the settings, and writes progress and choices back.
    func bindLive() {
        let monitor = SetupMonitor.shared
        let store = Store.shared
        engineKind = store.settings.engine
        recommendedEngine = engineKind
        claudeInstalled = ClaudeCodeEngine.claudePath != nil
        coachEnabled = store.settings.coach.enabled
        hotKey = store.settings.summonHotKey
        let installed = Set(store.presets.map(\.name))
        languages = store.settings.writingLanguages
        chosenPresets = Set(starters.map(\.name)).intersection(installed)
        saveLanguages = { languages in store.settings.languages = languages }
        recordPrivacyAccepted = { store.settings.privacyAccepted = true }
        save = { progress in if store.settings.onboarding != progress { store.settings.onboarding = progress } }
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
            if store.settings.engine != kind { store.settings.engine = kind }
            if kind == .local { self?.checkLocalEngine() }
        }

        func read(_ accessibility: Bool, _ engine: SetupMonitor.EngineStatus, _ taken: [KeyCombo], _ settings: AppSettings) -> OnboardingConditions {
            engineStatus = engine
            if engineKind != settings.engine { engineKind = settings.engine }
            hotKey = settings.summonHotKey
            let clash = taken.contains(settings.summonHotKey)
            hotKeyOwner = clash ? HotKeyChoice.owner(of: settings.summonHotKey) : nil
            // Registering a candidate is how "free" is known, so only look while there's a reason to show them.
            hotKeySuggestions = clash ? HotKeyChoice.suggestions(current: settings.summonHotKey, taken: taken) : []
            return OnboardingConditions(accessibility: accessibility, engineReady: engine.isReady,
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
        detectEngine()
    }

    /// Before Connect a model is reached, opens it on the option that already works on this Mac.
    private func detectEngine() {
        guard flow.index <= OnboardingStep.allCases.firstIndex(of: .engine) ?? 0, !flow.conditions.engineReady else { return }
        Task { [weak self] in
            await LocalModels.shared.refresh()
            let claudeFound = await ClaudeCodeEngine.locate() != nil
            guard let self else { return }
            claudeInstalled = claudeFound
            let running = LocalModels.shared.running.contains { !($0.models ?? []).isEmpty }
            localRunning = running
            let pick = Onboarding.recommendedEngine(current: engineKind, currentReady: engineStatus.isReady,
                                                    claudeInstalled: claudeInstalled, localRunning: running)
            recommendedEngine = pick
            if pick != engineKind, !engineStatus.isReady { engineKind = pick }
        }
    }

    /// The engines in the order Connect a model lists them: the recommended one first.
    var engineOrder: [EngineKind] {
        let all: [EngineKind] = [.claudeCode, .apiKey, .chatGPT, .provider, .local]
        return [recommendedEngine] + all.filter { $0 != recommendedEngine }
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

    var canSkip: Bool {
        switch step {
        case .personalize: return true
        case .practice: return practiceStage != .pasted
        default: return false
        }
    }

    // MARK: Primary action

    /// What Connect a model's button does for the picked engine, before "Understood, " is put in front of it.
    private var engineAction: String {
        switch engineKind {
        case .apiKey: return "Save key"
        case .local: return engineStatus == .checking ? "Checking…" : "Check again"
        case .chatGPT:
            if ChatGPTSignIn.shared.state == .signingIn { return "Waiting for the browser…" }
            return ChatGPTSignIn.shared.canUsePlan ? "Check again" : "Continue with ChatGPT"
        case .provider: return "Open Engine settings"
        case .claudeCode:
            if engineStatus == .checking { return "Checking…" }
            if installer.state.isBusy { return "Installing…" }
            return claudeMissing ? "Install Claude Code" : "Sign in to Claude"
        }
    }

    var primaryTitle: String {
        switch step {
        case .accessibility: return flow.isCurrentSatisfied ? "Continue" : "Open System Settings"
        case .engine:
            if flow.isCurrentSatisfied { return "Continue" }
            // Reading where the text goes is part of this step; the button says so until it's been accepted.
            let action = flow.conditions.engineReady ? "Continue" : engineAction
            if flow.conditions.privacyAccepted || action.hasSuffix("…") { return action }
            return "Understood, " + action.prefix(1).lowercased() + action.dropFirst()
        case .personalize: return "Continue"
        case .practice: return practiceStage == .pasted ? "Continue" : "Open Takes"
        case .done: return "Start using Takes"
        }
    }

    var primaryEnabled: Bool {
        switch step {
        case .engine:
            if flow.isCurrentSatisfied || flow.conditions.engineReady { return true }
            if engineKind == .apiKey { return !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if engineKind == .chatGPT { return ChatGPTSignIn.shared.state != .signingIn }
            if engineKind == .provider { return true }
            return engineStatus != .checking && !installer.state.isBusy
        case .personalize: return !chosenPresets.isEmpty
        case .practice: return practiceStage != .panelOpen
        default: return true
        }
    }

    func primary() {
        guard primaryEnabled else { return }
        switch step {
        case .accessibility:
            if flow.isCurrentSatisfied { go { $0.next() } } else { SetupMonitor.shared.requestAccessibility() }
        case .engine:
            acceptPrivacy()
            if flow.isCurrentSatisfied { go { $0.next() } }
            else if engineKind == .apiKey { saveAPIKey() }
            else if engineKind == .local { checkLocalEngine() }
            else if engineKind == .chatGPT { ChatGPTSignIn.shared.canUsePlan ? checkChatGPTModels() : ChatGPTSignIn.shared.start() }
            else if engineKind == .provider { SettingsWindowController.shared.show(tab: .model) }
            else if claudeMissing { installClaudeCode() }
            else { openSignIn() }
        case .personalize:
            applyPresets()
            go { $0.next() }
        case .practice:
            if practiceStage == .pasted { go { $0.next() } } else { startPractice() }
        case .done:
            finish()
        }
    }

    // MARK: Steps

    /// Pressing Connect a model's "Understood, …" button: the user has read where their text goes.
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
            await SetupMonitor.shared.refreshEngine()
        }
    }

    /// Signed in with ChatGPT but no model yet (the list couldn't be fetched): ask OpenAI again.
    func checkChatGPTModels() {
        Task {
            ChatGPTModels.shared.checked = false
            await ChatGPTModels.shared.refresh()
            await SetupMonitor.shared.refreshEngine()
        }
    }

    func moveToApplications() {
        do {
            try AppLocation.moveToApplications()
            moveError = nil
        } catch {
            moveError = error.localizedDescription
        }
    }

    /// The hotkey chips on Make it yours: one click picks the combo.
    func pickHotKey(_ combo: KeyCombo) { Store.shared.settings.summonHotKey = combo }

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
            await SetupMonitor.shared.refreshEngine()
            if !SetupMonitor.shared.engine.isReady { openSignIn() }
        }
    }

    func saveAPIKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        Keychain.setAPIKey(key)
        apiKeyInput = ""
        Task { await SetupMonitor.shared.refreshEngine() }
    }

    func togglePreset(_ name: String) {
        if chosenPresets.contains(name) { chosenPresets.remove(name) } else { chosenPresets.insert(name) }
    }

    /// Keeps the chosen starters (and every preset that isn't a starter), and adds chosen ones that are missing.
    nonisolated static func applying(chosen: Set<String>, starters: [Preset], to presets: [Preset]) -> [Preset] {
        let starterNames = Set(starters.map(\.name))
        var result = presets.filter { !starterNames.contains($0.name) || chosen.contains($0.name) }
        let present = Set(result.map(\.name))
        result += starters.filter { chosen.contains($0.name) && !present.contains($0.name) }
        return result
    }

    func applyPresets() {
        let store = Store.shared
        // Also the translate presets of languages removed on this step, so the ones installed at first launch go.
        let removed = Languages.fromSystem().filter { !languages.contains($0) }
        let offered = starters + PresetGallery.translations(for: removed)
        let updated = Self.applying(chosen: chosenPresets, starters: offered.map(PresetGallery.copy(of:)),
                                    to: store.presets)
        if updated.map(\.id) != store.presets.map(\.id) { store.presets = updated }
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

    static let size = CGSize(width: 780, height: 560)

    var isVisible: Bool { window?.isVisible == true }

    /// While the practice step is on screen, the hotkey opens the panel on the practice box.
    var handlesHotKey: Bool { isVisible && model?.step == .practice }

    /// Runs once onboarding's last step is done and its window has closed; the app points at the menu-bar icon.
    var onFinished: () -> Void = {}

    /// Opens onboarding where it was left: the opening screen first if Get started hasn't been pressed yet.
    func show() {
        let model = self.model ?? makeModel()
        self.model = model
        if !model.flow.progress.openingSeen && window?.isVisible != true {
            OpeningWindowController.shared.show { [weak self] in
                model.openingDone()
                self?.showSteps()
            }
            return
        }
        showSteps()
    }

    private func showSteps() {
        guard let model else { return }
        let window = self.window ?? makeWindow(model: model)
        self.window = window
        Task { await SetupMonitor.shared.refreshEngine() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func hotKeyPressed() { model?.startPractice() }

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
        window.title = "Welcome to Takes"
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
