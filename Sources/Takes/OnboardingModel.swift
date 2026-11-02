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
            if flow.step != oldValue.step { onStepChange(flow.step) }
        }
    }
    @Published var engineStatus = SetupMonitor.EngineStatus.checking
    @Published var engineKind = EngineKind.claudeCode {
        didSet { if engineKind != oldValue { onEngineKindChange(engineKind) } }
    }
    @Published var hotKey = AppSettings().summonHotKey
    /// Who already uses the hotkey ("macOS: Show Finder search window", "another app"), or nil when it's free.
    @Published var hotKeyOwner: String?
    @Published var apiKeyInput = ""
    @Published var copiedSignIn = false
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

    private var subscriptions: Set<AnyCancellable> = []

    init(progress: OnboardingProgress = OnboardingProgress(), conditions: OnboardingConditions = OnboardingConditions()) {
        flow = OnboardingFlow(progress: progress, conditions: conditions)
        let languages = Languages.fromSystem()
        self.languages = languages
        chosenPresets = Set(OnboardingPresets.starters(languages: languages).map(\.name))
    }

    var step: OnboardingStep { flow.step }

    // MARK: Live

    /// Follows `SetupMonitor` and the settings, and writes progress and choices back.
    func bindLive() {
        let monitor = SetupMonitor.shared
        let store = Store.shared
        engineKind = store.settings.engine
        hotKey = store.settings.summonHotKey
        let installed = Set(store.presets.map(\.name))
        languages = store.settings.writingLanguages
        chosenPresets = Set(starters.map(\.name)).intersection(installed)
        saveLanguages = { languages in store.settings.languages = languages }
        save = { progress in if store.settings.onboarding != progress { store.settings.onboarding = progress } }
        onEngineKindChange = { [weak self] kind in
            if store.settings.engine != kind { store.settings.engine = kind }
            if kind == .local { self?.checkLocalEngine() }
        }

        func read(_ accessibility: Bool, _ engine: SetupMonitor.EngineStatus, _ taken: [KeyCombo], _ settings: AppSettings) -> OnboardingConditions {
            engineStatus = engine
            if engineKind != settings.engine { engineKind = settings.engine }
            hotKey = settings.summonHotKey
            let clash = taken.contains(settings.summonHotKey)
            hotKeyOwner = clash ? SystemShortcuts.owner(of: settings.summonHotKey).map { "macOS: \($0)" } ?? "another app" : nil
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
                setConditions(read(accessibility, engine, taken, settings))
            }
            .store(in: &subscriptions)
    }

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
        case .hotkey: return !flow.isCurrentSatisfied
        case .presets: return true
        case .practice: return practiceStage != .pasted
        default: return false
        }
    }

    // MARK: Primary action

    var primaryTitle: String {
        switch step {
        case .welcome: return "Get started"
        case .accessibility: return flow.isCurrentSatisfied ? "Continue" : "Open System Settings"
        case .engine:
            if flow.isCurrentSatisfied { return "Continue" }
            if engineKind == .apiKey { return "Save key" }
            if engineKind == .local { return engineStatus == .checking ? "Checking…" : "Check again" }
            if engineKind == .chatGPT { return ChatGPTSignIn.shared.state == .signingIn ? "Waiting for the browser…" : "Continue with ChatGPT" }
            if engineKind == .provider { return "Open Engine settings" }
            return engineStatus == .checking ? "Checking…" : "Copy command and open Terminal"
        case .privacy: return flow.isCurrentSatisfied ? "Continue" : "I understand"
        case .hotkey, .presets: return "Continue"
        case .practice: return practiceStage == .pasted ? "Continue" : "Open Takes"
        case .done: return "Start using Takes"
        }
    }

    var primaryEnabled: Bool {
        switch step {
        case .engine:
            if flow.isCurrentSatisfied { return true }
            if engineKind == .apiKey { return !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if engineKind == .chatGPT { return ChatGPTSignIn.shared.state != .signingIn }
            if engineKind == .provider { return true }
            return engineStatus != .checking
        case .presets: return !chosenPresets.isEmpty
        case .practice: return practiceStage != .panelOpen
        default: return true
        }
    }

    func primary() {
        guard primaryEnabled else { return }
        switch step {
        case .welcome, .hotkey:
            go { $0.next() }
        case .accessibility:
            if flow.isCurrentSatisfied { go { $0.next() } } else { SetupMonitor.shared.requestAccessibility() }
        case .engine:
            if flow.isCurrentSatisfied { go { $0.next() } }
            else if engineKind == .apiKey { saveAPIKey() }
            else if engineKind == .local { checkLocalEngine() }
            else if engineKind == .chatGPT { ChatGPTSignIn.shared.start() }
            else if engineKind == .provider { SettingsWindowController.shared.show(tab: .engine) }
            else { copySignInCommand() }
        case .privacy:
            acceptPrivacy()
        case .presets:
            applyPresets()
            go { $0.next() }
        case .practice:
            if practiceStage == .pasted { go { $0.next() } } else { startPractice() }
        case .done:
            finish()
        }
    }

    // MARK: Steps

    func acceptPrivacy() {
        if !flow.conditions.privacyAccepted {
            Store.shared.settings.privacyAccepted = true
            var conditions = flow.conditions
            conditions.privacyAccepted = true
            go { _ = $0.update(conditions) }
        }
        go { $0.next() }
    }

    /// Looks for Ollama / LM Studio again; picks the first installed model if none is picked yet.
    func checkLocalEngine() {
        Task {
            await LocalModels.shared.refresh()
            await SetupMonitor.shared.refreshEngine()
        }
    }

    func copySignInCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("claude auth login", forType: .string)
        copiedSignIn = true
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
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

    func show() {
        let model = self.model ?? makeModel()
        self.model = model
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
        // Stay above System Settings and Terminal while access is granted or Claude is signed in.
        window.level = step == .accessibility || step == .engine ? .floating : .normal
        // Back from System Settings: bring the window forward for the next step.
        if step != .accessibility, window.isVisible, !window.isKeyWindow, model?.step != .practice {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
}
