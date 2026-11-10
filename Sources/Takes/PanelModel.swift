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
    /// Set with `error` when the engine's account is out of credit or at a limit: the panel offers a way to fix it.
    @Published var limit: UsageLimitError?
    /// The last take of the shown run was cut short (`EngineResult.cutShort`), so the takes screen can say so.
    @Published var cutShort = false
    @Published var selected = 0
    @Published var changesShown: Set<Int> = []
    /// ⌥ held on the takes screen: every card flips between its changes and the clean take.
    @Published var optionHeld = false
    /// The run-options popover on compose (the chip, or ⌘K).
    @Published var optionsOpen = false
    /// The coach's notes under the takes: one line until ⌘; or a click.
    @Published var coachExpanded = false
    /// The coach's invitation under the takes, while the coach is off (CoachInvitation.swift).
    @Published var invitation: CoachInvitation.Offer?
    /// The last draft whose fixes were recorded for the invitation, so regenerating doesn't count it twice.
    private var invitationDraft = ""
    @Published var refineText = ""
    @Published var timing = ""
    @Published var startedAt = Date()
    /// Set while the engine waits to try again, so the footer says why the run is slow.
    @Published var retry: EngineRetry?
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
    /// The history entry of the takes on screen. Nil while a run is still writing, and for takes that were never filed.
    private var historyID: String?
    /// Bumped whenever a run is replaced or abandoned; the old run's task is cancelled with it, which also
    /// stops a Claude Code process still writing.
    private var runToken = 0 { didSet { runTask?.cancel(); runTask = nil } }
    private var runTask: Task<Void, Never>?
    /// The engine a run uses, and where its timing is logged. Tests put their own here.
    var makeEngine: (AppSettings) -> TakesEngine = { Engines.current($0) }
    var logRun: ([String: Any]) -> Void = { RunLog.append($0) }
    /// Asks the engine in use for its list of models as the panel opens. Tests leave it out.
    var refreshModels: (EngineKind) -> Void = { engine in
        switch engine {
        case .local: Task { await LocalModels.shared.refresh() }
        case .provider: Task { await ProviderModels.shared.refresh() }
        case .chatGPT: Task { await ChatGPTModels.shared.refresh() }
        case .claudeCode, .apiKey: break
        }
    }

    var onPaste: (Int, String, String?) -> Void = { _, _, _ in }
    var onCopy: (Int, String) -> Void = { _, _ in }
    var onClose: () -> Void = {}
    var onOpenSettings: (SettingsTab, Bool) -> Void = { _, _ in }
    var onMore: () -> Void = {}
    var onOpenGallery: () -> Void = {}
    /// "Turn on coach" in the invitation: Settings › English coach's setup, pre-filled with these patterns.
    var onSetUpCoach: ([String]) -> Void = { _ in }
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
    /// The preset whose own hotkey opened the panel, or nil when it was opened another way.
    private(set) var openedWithPresetID: String?

    /// The chosen preset's own hotkey, as a reminder that it opens this preset straight away. Nil when the preset
    /// has none, when that hotkey just opened the panel, or when another app holds it.
    func presetHotKeyReminder(taken: [KeyCombo]) -> KeyCombo? {
        guard let combo = preset.hotKey, preset.id != openedWithPresetID, !taken.contains(combo) else { return nil }
        return combo
    }
    /// Stands in for the focused app in `--snapshot` renders.
    var previewAppName: String?
    var previewAppURL: URL?
    var appName: String { previewAppName ?? focus?.app?.localizedName ?? "the focused app" }
    /// `appName` for the screen: the fallback is translated. History and the coach keep `appName`.
    var displayAppName: String { previewAppName ?? focus?.app?.localizedName ?? String(localized: "the focused app") }
    var appURL: URL? { previewAppName != nil ? previewAppURL : focus?.app?.bundleURL }
    var appBundleID: String? { focus?.app?.bundleIdentifier }

    var sourceLabel: String {
        switch focus?.source {
        case .selection: return String(localized: "From your selection")
        case .field:
            // "Start with: the selection" and nothing was selected. The box wasn't read, so it isn't known to be empty.
            if focus?.method == FocusSnapshot.noSelection { return String(localized: "Nothing was selected") }
            return draft.isEmpty ? String(localized: "The field was empty") : String(localized: "From the field")
        // Not an empty field: its text is still there, unread. A take pasted from here goes in at the caret.
        case .tooLong: return String(localized: "The text is too long. Select part of it first")
        case .secure: return String(localized: "Takes doesn't read password fields")
        default: return focus?.app == nil ? "" : String(localized: "Couldn't read the field")
        }
    }

    var wordCount: Int { WordCounter.count(draft) }

    /// The compose row's word count. A box that wasn't read (too long, a password field) has no count until
    /// something is written here: "0 words" would read as an empty box.
    var showsWordCount: Bool {
        guard draft.isEmpty else { return true }
        return focus?.source != .tooLong && focus?.source != .secure
    }

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
        openedWithPresetID = forced.flatMap { store.preset(id: $0)?.id }
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
        refreshModels(store.settings.engine)
        resetReplyContext(draft: focus.text)
        takes = []
        cutShort = false
        historyID = nil
        lastPaste = nil
        takeTones.reset()
        toneRead.dismiss()
        coach.reset()
        invitation = nil
        coachExpanded = false
        optionsOpen = false
        optionHeld = false
        running = false
        error = nil
        limit = nil
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
            // One step back at a time: the options popover, dictation, then the tone read, then close.
            if optionsOpen { optionsOpen = false; return }
            if dictation.handleEscape() { return }
            if toneRead.isShown { toneRead.dismiss() } else { onClose() }
        }
    }

    func show(_ next: Screen) {
        if next != .compose { dictation.dismiss(); optionsOpen = false }
        screen = next
        focusToken += 1
        onScreenChange()
    }

    /// Whether the open panel holds anything a fresh summon would throw away: a draft that was typed or changed,
    /// what it replies to, takes, or a run still writing.
    var hasWork: Bool {
        func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        return running || !takes.isEmpty || hasReplyContext || trimmed(draft) != trimmed(focus?.text ?? "")
    }

    /// The panel closed. A run still writing is abandoned, which also stops its Claude Code process.
    func panelClosed() {
        guard running else { return }
        runToken += 1
        running = false
    }

    /// The hotkey pressed again while the panel has the keyboard. Opening the panel afresh would throw away the typed
    /// draft, the takes and a run still writing, so nothing is reset. A preset's own hotkey picks that preset while
    /// the draft is being written; anything else only puts the keyboard back in the panel's main input.
    func hotKeyPressedAgain(presetID: String?) {
        if screen == .compose, let presetID, presetID != self.presetID, store.preset(id: presetID) != nil {
            choose(presetID)
        } else {
            focusToken += 1
        }
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

    /// The compose row: the chosen preset, then the ones used most in this app, by name; the rest fold into "+N".
    func presetRow(limit: Int = PresetRow.named) -> PresetRow.Layout {
        PresetRow.layout(presets: store.presets, current: presetID, usage: presetUsage,
                         pickedForApp: pickedForApp.map(\.id), limit: limit)
    }

    /// How often each preset was used in the focused app, from history.
    var presetUsage: [String: Int] {
        var byName: [String: Int] = [:]
        for entry in store.history where entry.appName == appName { byName[entry.presetName, default: 0] += 1 }
        var usage: [String: Int] = [:]
        for preset in store.presets { if let n = byName[preset.name] { usage[preset.id] = n } }
        return usage
    }

    /// "3 · Sonnet 5.5 · Low": the run options on the compose chip.
    var runOptionsLabel: String {
        usesOneModel ? "\(takeCount) · \(Models.displayLabel(modelID))" : "\(takeCount) · \(Models.label(modelID)) · \(Models.effortLabel(effort))"
    }

    func choose(number: Int) {
        guard number >= 1, number <= store.presets.count else { return }
        choose(store.presets[number - 1].id)
    }

    /// Back to the preset's takes, model and effort.
    func resetRunOptions() { applyPresetSettings() }

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
        var request = EngineRequest(
            system: PromptBuilder.system(preset: preset, takes: takeCount, rules: store.settings.voiceRules,
                                         hasContext: promptContext != nil),
            user: PromptBuilder.user(draft: draft, mode: mode, takes: takeCount, context: promptContext),
            takes: takeCount, model: modelID, effort: effort)
        let engine = makeEngine(store.settings)

        runToken += 1
        let token = runToken
        request.onRetry = { retry in
            Task { @MainActor in
                guard self.runToken == token, self.running else { return }
                self.retry = retry
            }
        }
        running = true
        retry = nil
        error = nil
        limit = nil
        takes = []
        cutShort = false
        // The entry on file belongs to the takes this run replaces.
        historyID = nil
        takeTones.reset()
        toneRead.dismiss()
        // Refining keeps the same draft, so its check stands.
        if case .fresh = mode { coach.start(draft: draft, preset: preset, appName: appName, settings: store.settings) }
        invitation = nil
        coachExpanded = false
        optionsOpen = false
        selected = 0
        changesShown = showsFixes ? Set(0..<takeCount) : []
        timing = ""
        sourceDraft = draft
        startedAt = Date()
        show(.takes)

        runTask = Task {
            do {
                let result = try await engine.run(request) { partial in
                    Task { @MainActor in
                        guard self.runToken == token, self.running else { return }
                        self.takes = partial
                    }
                }
                guard runToken == token else { return }
                finish(result, request: request, mode: mode)
            } catch {
                guard runToken == token else { return }
                running = false
                self.error = error.localizedDescription
                limit = error as? UsageLimitError
                onScreenChange()
            }
        }
    }

    private func finish(_ result: EngineResult, request: EngineRequest, mode: PromptBuilder.Mode) {
        running = false
        takes = result.takes
        cutShort = result.cutShort
        selected = min(selected, max(takes.count - 1, 0))
        let seconds = { (ms: Int) in String(format: NSLocalizedString("%.1f s", comment: "Seconds"), locale: .current, Double(ms) / 1000) }
        timing = [result.firstTextMs.map { String(localized: "first words \(seconds($0))") }, String(localized: "all takes \(seconds(result.wallMs))")]
            .compactMap { $0 }.joined(separator: " · ")
        store.settings.lastFirstTextMs = result.firstTextMs

        let entry = HistoryEntry(appName: appName, presetName: preset.name, draft: sourceDraft, takes: result.takes)
        historyID = entry.id
        store.record(entry)
        logRun([
            "kind": "app", "model": request.model, "effort": request.effort, "takes": request.takes,
            "engine": store.settings.engine.rawValue, "wallMs": result.wallMs,
            "firstTextMs": result.firstTextMs ?? -1, "app": appBundleID ?? "",
        ])
        takeTones.fetch(takes: takes, showTone: preset.showTone, settings: store.settings)
        if case .fresh = mode { considerInvitation() }
        onScreenChange()
    }

    // MARK: Coach invitation

    /// Files the takes' fixes and, when the same kind keeps coming back while the coach is off, offers it.
    /// Comparing every take with the draft is real work, so it happens off the main thread, and the result is
    /// used only if the run it belongs to is still the one on screen.
    func considerInvitation(store invites: CoachInviteStore? = nil, now: Date = Date()) {
        let settings = store.settings
        let context = CoachInvitation.Context(coachOn: settings.coach.enabled, english: CoachCheck.isEnglish(sourceDraft),
                                              presetCounts: settings.coach.counts(preset), localEngine: settings.engine == .local)
        guard !context.coachOn, context.english, context.presetCounts, sourceDraft != invitationDraft else { return }
        invitationDraft = sourceDraft
        let draft = sourceDraft
        let takes = takes
        let token = runToken
        invitationTask = Task.detached(priority: .userInitiated) {
            let found = FixHeuristic.analyse(draft: draft, takes: takes)
            await MainActor.run {
                guard self.runToken == token else { return }
                self.invitation = (invites ?? .shared).consider(context: context, found: found, now: now)
            }
        }
    }

    /// The check started by `considerInvitation`, so a test can wait for it.
    private(set) var invitationTask: Task<Void, Never>?

    /// ✕: not now; asks again in a month at the earliest.
    func dismissInvitation() {
        CoachInviteStore.shared.dismiss()
        invitation = nil
        focusToken += 1
    }

    func neverInvite() {
        CoachInviteStore.shared.neverAgain()
        invitation = nil
        focusToken += 1
    }

    func acceptInvitation() {
        let patterns = invitation?.repeating ?? []
        invitation = nil
        onSetUpCoach(patterns)
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

    /// Whether a finished take shows its changes: ⌥ flips each card, so it reveals them on a regular run and hides
    /// them on a minimal-edit one, which opens with them shown.
    func showsChanges(_ index: Int) -> Bool {
        isFinished(index) && changesShown.contains(index) != optionHeld
    }

    /// The takes shown came from a run filed elsewhere (instant mode): a take pasted from here is marked on that entry.
    func continueHistory(entryID: String?) { historyID = entryID }

    /// Whether a take may be pasted or copied: a finished one, not while a run's error is showing, and not the
    /// take the engine cut short, which is the last one once the run has ended. Every way to paste or copy comes
    /// through here, whatever the views allow.
    func canUse(_ index: Int) -> Bool {
        guard isFinished(index), error == nil else { return false }
        return !(cutShort && !running && index == takes.count - 1)
    }

    /// What a paste needs once its outcome is known: which history entry, and which take in it.
    struct PasteReceipt: Equatable {
        var entryID: String?
        var index: Int
    }

    /// Set by `paste` for the take being pasted now; the panel's controller takes it along with the paste.
    private var lastPaste: PasteReceipt?

    func takePasteReceipt() -> PasteReceipt? {
        defer { lastPaste = nil }
        return lastPaste
    }

    func paste(_ index: Int) {
        guard canUse(index) else { return }
        if historyID == nil, running {
            // Pasted while later takes were still being written. The run ends here, as the panel closes, so it is
            // filed now with the takes that were finished.
            let entry = HistoryEntry(appName: appName, presetName: preset.name, draft: sourceDraft, takes: Array(takes.dropLast()))
            historyID = entry.id
            store.record(entry)
        }
        // History says "pasted" once the paste is known to have gone in (`pasteEnded`), not before.
        lastPaste = PasteReceipt(entryID: historyID, index: index)
        coachNudge = coach.commit()
        onPaste(index, takes[index], presetID)
    }

    /// The outcome of a paste: only a take that was really typed into the text box is marked as pasted. One left
    /// on the clipboard (the box changed, the app didn't come back, the text can't be edited) is not.
    func pasteEnded(_ outcome: Paster.Outcome, receipt: PasteReceipt?) {
        guard outcome == .pasted, let receipt, let entryID = receipt.entryID else { return }
        store.markPasted(entryID: entryID, index: receipt.index)
    }

    func pasteSelected() { paste(selected) }

    func copySelected() {
        guard canUse(selected) else { return }
        onCopy(selected, takes[selected])
    }
}

/// Which presets the compose row names, and how many fold into "+N".
enum PresetRow {
    /// Names shown at most, the chosen preset included.
    static let named = 3

    struct Layout: Equatable {
        var shown: [String]
        var overflow: Int
    }

    /// The chosen preset first, then the rest by use in this app, then those picked for the app, then Settings order.
    static func layout(presets: [Preset], current: String, usage: [String: Int], pickedForApp: [String], limit: Int) -> Layout {
        let ids = presets.map(\.id)
        let first = ids.contains(current) ? [current] : Array(ids.prefix(1))
        let rest = ids.enumerated().filter { !first.contains($0.element) }.sorted { a, b in
            let ua = usage[a.element] ?? 0, ub = usage[b.element] ?? 0
            if ua != ub { return ua > ub }
            let pa = pickedForApp.contains(a.element), pb = pickedForApp.contains(b.element)
            if pa != pb { return pa }
            return a.offset < b.offset
        }.map(\.element)
        let shown = Array((first + rest).prefix(max(1, limit)))
        return Layout(shown: shown, overflow: ids.count - shown.count)
    }
}

enum WordCounter {
    static func count(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}
