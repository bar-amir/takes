import SwiftUI

/// State behind the floating panel: compose a draft, pick a preset, choose a take.
@MainActor
final class PanelModel: ObservableObject {
    enum Screen { case compose, presets, takes }

    @Published var screen = Screen.compose
    @Published var draft = ""
    @Published var presetID = ""
    @Published var autoPicked = false
    @Published var takeCount = 3
    @Published var modelID = Models.sonnet
    @Published var effort = "low"

    @Published var takes: [String] = []
    /// How each take may come across, filled in after the takes are written.
    let takeTones = TakeTones()
    /// "How does this read?" for the draft in compose.
    let toneRead = ToneReadModel()
    /// The English coach's check of the draft, run alongside the takes when the coach is on.
    let coach = CoachRun()
    /// The coach's line for the paste toast, set just before `onPaste`.
    var coachNudge: String?
    @Published var running = false
    @Published var error: String?
    @Published var selected = 0
    @Published var changesShown: Set<Int> = []
    @Published var refineText = ""
    @Published var timing = ""
    @Published var startedAt = Date()
    /// The draft the shown takes were written from, for "Changes".
    @Published var sourceDraft = ""

    @Published var filter = ""
    @Published var highlighted = 0
    /// Bumped to move keyboard focus to the screen's main input.
    @Published var focusToken = 0

    /// What the user is replying to (ReplyContext.swift). Cleared on every summon.
    @Published var replyContext: ReplyContext?
    @Published var editingContext = false
    @Published var contextFocusToken = 0
    @Published var contextNotice: String?
    /// The clipboard as it was at summon, for the opt-in clipboard context.
    var summonClipboard: ClipboardCandidate?
    /// Speaking into the draft (⌘D).
    let dictation = Dictation()
    /// Where the draft editor puts the caret after the draft changes from outside (UTF-16 offset); nil is the end.
    @Published var draftCaret: Int?
    /// The draft editor's selection, reported as it changes.
    var draftSelection: NSRange?
    private var dictationInsertion: DictationInsertion?

    let store = Store.shared
    private(set) var focus: FocusSnapshot?
    private var historyID: String?
    private var runToken = 0

    var onPaste: (Int, String, String?) -> Void = { _, _, _ in }
    var onCopy: (Int, String) -> Void = { _, _ in }
    var onClose: () -> Void = {}
    var onOpenSettings: (SettingsTab, Bool) -> Void = { _, _ in }
    var onMore: () -> Void = {}
    var onOpenGallery: () -> Void = {}
    var onScreenChange: () -> Void = {}
    /// The takes screen reports the height it needs; the panel grows or shrinks to it.
    var onContentHeight: (CGFloat) -> Void = { _ in }
    /// The takes screen's last measured height.
    var takesContentHeight: CGFloat = 0
    /// True when a text field in the panel has selected text, so ⌘C copies that instead of a take.
    var textSelectionActive: () -> Bool = { false }

    // MARK: Derived

    var preset: Preset { previewPreset ?? store.preset(id: presetID) ?? store.presets.first ?? Store.defaultPresets[0] }
    /// Stands in for the chosen preset in `--snapshot` renders, without touching the saved presets.
    var previewPreset: Preset?
    /// Stands in for the focused app in `--snapshot` renders.
    var previewAppName: String?
    var previewAppURL: URL?
    var appName: String { previewAppName ?? focus?.app?.localizedName ?? "the focused app" }
    var appURL: URL? { previewAppName != nil ? previewAppURL : focus?.app?.bundleURL }
    var appBundleID: String? { focus?.app?.bundleIdentifier }

    var sourceLabel: String {
        switch focus?.source {
        case .selection: return "From your selection"
        case .field: return draft.isEmpty ? "The field was empty" : "Prefilled from the field"
        default: return focus?.app == nil ? "" : "Couldn't read the field"
        }
    }

    var wordCount: Int { WordCounter.count(draft) }

    var isOverridden: Bool {
        takeCount != preset.takes || modelID != store.settings.runModel(for: preset) || (!usesOneModel && effort != preset.effort)
    }

    /// Cards to show: the takes so far plus placeholders for ones still coming.
    var cardCount: Int { running ? max(takeCount, takes.count) : takes.count }

    func isFinished(_ index: Int) -> Bool {
        index < takes.count && (!running || index < takes.count - 1)
    }

    // MARK: Lifecycle

    func reset(focus: FocusSnapshot, presetID forced: String?) {
        runToken += 1
        self.focus = focus
        dictation.dismiss()
        draftCaret = nil
        draftSelection = nil
        draft = focus.text
        if let forced, store.preset(id: forced) != nil {
            presetID = forced
            autoPicked = false
        } else if let picked = store.preset(forApp: appBundleID) {
            presetID = picked.id
            autoPicked = true
        } else {
            if store.preset(id: presetID) == nil { presetID = store.presets.first?.id ?? "" }
            autoPicked = false
        }
        applyPresetSettings()
        switch store.settings.engine {
        case .local: Task { await LocalModels.shared.refresh() }
        case .provider: Task { await ProviderModels.shared.refresh() }
        case .chatGPT: Task { await ChatGPTModels.shared.refresh() }
        case .claudeCode, .apiKey: break
        }
        resetReplyContext(draft: focus.text)
        takes = []
        takeTones.reset()
        toneRead.dismiss()
        coach.reset()
        running = false
        error = nil
        refineText = ""
        timing = ""
        filter = ""
        screen = .compose
        focusToken += 1
    }

    func escape() {
        switch screen {
        case .presets:
            show(.compose)
        case .takes:
            runToken += 1
            running = false
            show(.compose)
        case .compose:
            // One step back at a time: dictation first, then the tone read, then close.
            if dictation.handleEscape() { return }
            if toneRead.isShown { toneRead.dismiss() } else { onClose() }
        }
    }

    func show(_ next: Screen) {
        if next != .compose { dictation.dismiss() }
        screen = next
        focusToken += 1
        onScreenChange()
    }

    // MARK: Presets

    var pickedForApp: [Preset] {
        guard let id = appBundleID else { return [] }
        return store.presets.filter { $0.apps.contains { $0.bundleID == id } }
    }

    var otherPresets: [Preset] {
        let picked = Set(pickedForApp.map(\.id))
        return store.presets.filter { !picked.contains($0.id) }
    }

    /// Picker rows in display order, filtered by what's typed.
    var filteredPresets: [Preset] {
        let all = pickedForApp + otherPresets
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.lowercased().contains(query) || $0.instruction.lowercased().contains(query) }
    }

    var highlightedPreset: Preset? {
        if browseRowHighlighted { return nil }
        let list = filteredPresets
        return list.indices.contains(highlighted) ? list[highlighted] : list.first
    }

    /// The picker ends with a quiet "Browse more presets" row while the user has only a few presets,
    /// and whenever the filter matches none.
    var browseRowLimit = PresetGallery.browseRowLimit
    var showsBrowseRow: Bool {
        filteredPresets.isEmpty || (filter.trimmingCharacters(in: .whitespaces).isEmpty && store.presets.count < browseRowLimit)
    }
    var browseRowHighlighted: Bool { showsBrowseRow && highlighted == filteredPresets.count }

    /// ⌘1–9 follow the order in Settings › Presets.
    func shortcutNumber(of preset: Preset) -> Int? {
        guard let index = store.index(of: preset.id), index < 9 else { return nil }
        return index + 1
    }

    func openPicker() {
        filter = ""
        highlighted = filteredPresets.firstIndex { $0.id == presetID } ?? 0
        show(.presets)
    }

    func moveHighlight(_ delta: Int) {
        let count = filteredPresets.count + (showsBrowseRow ? 1 : 0)
        guard count > 0 else { return }
        highlighted = (highlighted + delta + count) % count
    }

    func filterChanged() { highlighted = 0 }

    func chooseHighlighted() {
        if browseRowHighlighted { onOpenGallery(); return }
        if let preset = highlightedPreset { choose(preset.id) }
    }

    func choose(_ id: String) {
        presetID = id
        autoPicked = store.preset(forApp: appBundleID)?.id == id
        applyPresetSettings()
        show(.compose)
    }

    func choose(number: Int) {
        guard number >= 1, number <= store.presets.count else { return }
        choose(store.presets[number - 1].id)
    }

    private func applyPresetSettings() {
        let preset = self.preset
        takeCount = preset.takes
        modelID = store.settings.runModel(for: preset)
        effort = preset.effort
    }

    // MARK: Running

    func generate() { run(.fresh) }

    func refine() {
        let instruction = refineText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty, isFinished(selected) else { return }
        refineText = ""
        run(.refine(take: takes[selected], instruction: instruction))
    }

    func moreLikeSelected() {
        guard isFinished(selected) else { return }
        run(.moreLike(take: takes[selected]))
    }

    private func run(_ mode: PromptBuilder.Mode) {
        let draft = self.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return }
        let request = EngineRequest(
            system: PromptBuilder.system(preset: preset, takes: takeCount, rules: store.settings.voiceRules,
                                         hasContext: promptContext != nil),
            user: PromptBuilder.user(draft: draft, mode: mode, takes: takeCount, context: promptContext),
            takes: takeCount, model: modelID, effort: effort)
        let engine = Engines.current(store.settings)

        runToken += 1
        let token = runToken
        running = true
        error = nil
        takes = []
        takeTones.reset()
        toneRead.dismiss()
        // Refining keeps the same draft, so its check stands.
        if case .fresh = mode { coach.start(draft: draft, preset: preset, appName: appName, settings: store.settings) }
        selected = 0
        changesShown = showsFixes ? Set(0..<takeCount) : []
        timing = ""
        sourceDraft = draft
        startedAt = Date()
        show(.takes)

        Task {
            do {
                let result = try await engine.run(request) { partial in
                    Task { @MainActor in
                        guard self.runToken == token, self.running else { return }
                        self.takes = partial
                    }
                }
                guard runToken == token else { return }
                finish(result, request: request)
            } catch {
                guard runToken == token else { return }
                running = false
                self.error = error.localizedDescription
                onScreenChange()
            }
        }
    }

    private func finish(_ result: EngineResult, request: EngineRequest) {
        running = false
        takes = result.takes
        selected = min(selected, max(takes.count - 1, 0))
        let seconds = { (ms: Int) in String(format: "%.1f s", Double(ms) / 1000) }
        timing = [result.firstTextMs.map { "first words \(seconds($0))" }, "all takes \(seconds(result.wallMs))"]
            .compactMap { $0 }.joined(separator: " · ")
        store.settings.lastFirstTextMs = result.firstTextMs

        let entry = HistoryEntry(appName: appName, presetName: preset.name, draft: sourceDraft, takes: result.takes)
        historyID = entry.id
        store.record(entry)
        RunLog.append(["kind": "app", "model": request.model, "effort": request.effort, "takes": request.takes,
                       "engine": store.settings.engine.rawValue, "wallMs": result.wallMs,
                       "firstTextMs": result.firstTextMs ?? -1, "app": appBundleID ?? ""])
        takeTones.fetch(takes: takes, showTone: preset.showTone, settings: store.settings)
        onScreenChange()
    }

    // MARK: Dictation

    func toggleDictation() {
        guard screen == .compose else { return }
        if !dictation.isActive { dictationInsertion = nil }
        dictation.onTranscript = { [weak self] in self?.insertDictated($0) }
        dictation.toggle()
    }

    /// ↵ in the draft: dictation's note uses it first, otherwise it writes the takes.
    func submitDraft() {
        if dictation.handleReturn() { return }
        generate()
    }

    /// Puts the latest transcript at the caret, replacing the previous one from the same recording.
    func insertDictated(_ transcript: String) {
        let insertion = dictationInsertion ?? DictationInsertion(
            text: draft, selection: draftSelection ?? NSRange(location: (draft as NSString).length, length: 0))
        dictationInsertion = insertion
        let result = insertion.apply(transcript)
        draftCaret = result.caret
        draft = result.text
    }

    // MARK: Takes

    func select(_ index: Int) {
        guard index >= 0, index < cardCount else { return }
        selected = index
    }

    func moveSelection(_ delta: Int) { select(min(max(selected + delta, 0), max(cardCount - 1, 0))) }

    func toggleChanges(_ index: Int) {
        if changesShown.contains(index) { changesShown.remove(index) } else { changesShown.insert(index) }
    }

    func paste(_ index: Int) {
        guard isFinished(index) else { return }
        if let historyID { store.markPasted(entryID: historyID, index: index) }
        coachNudge = coach.commit()
        onPaste(index, takes[index], presetID)
    }

    func pasteSelected() { paste(selected) }

    func copySelected() {
        guard isFinished(selected) else { return }
        onCopy(selected, takes[selected])
    }
}

enum WordCounter {
    static func count(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}
