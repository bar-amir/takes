import AppKit
import Carbon

/// "Write and paste right away": a preset's own hotkey writes 1 take and pastes it in place, with no panel.
/// The decisions live here, apart from the UI, so they can be tested.
enum InstantMode {
    /// What the hotkey does with what was read from the field.
    enum Start: Equatable {
        /// Nothing to rewrite (empty field, or no text box): open the normal panel instead.
        case openPanel
        /// Write from `draft`. `replaceAll` replaces the whole field; otherwise the paste replaces the selection.
        case write(draft: String, replaceAll: Bool)
        /// The text box holds too much text to rewrite whole. Nothing is written or pasted, and the toast says why.
        case tooLong
    }

    /// `editable` is false for a selection in text that takes no typing (a web page).
    static func start(text: String, source: FocusSnapshot.Source, editable: Bool = true) -> Start {
        // Before the draft is looked at: a box too long to read comes with no text, and isn't an empty box.
        if source == .tooLong { return .tooLong }
        let draft = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A take has nowhere to go in text that can't be edited: the panel shows the takes and copies the chosen one.
        guard !draft.isEmpty, editable else { return .openPanel }
        switch source {
        case .field: return .write(draft: draft, replaceAll: true)
        case .selection: return .write(draft: draft, replaceAll: false)
        // Text that wasn't read from a text box has nowhere safe to go back to.
        case .none, .secure, .tooLong: return .openPanel
        }
    }

    static func tooLongMessage(app: String) -> String {
        String(localized: "The text box in \(app) has too much text to rewrite at once. Select the part you want and try again.")
    }

    /// What a hotkey press does, given what instant mode is doing.
    enum HotKeyAction: Equatable {
        /// The panel opens: the summon hotkey, a preset that doesn't write right away, or one picked in the
        /// menu. A run in progress is stopped first, so its take can't be pasted once the panel is up.
        case openPanel
        /// Already writing with an instant preset: the press is ignored.
        case keepWriting
        /// The preset's result toast is still up: open that result in Takes.
        case openResult
        case write
    }

    static func hotKeyAction(writesInstantly: Bool, running: Bool, resultShowing: Bool) -> HotKeyAction {
        guard writesInstantly else { return .openPanel }
        if running { return .keepWriting }
        return resultShowing ? .openResult : .write
    }

    /// The prefill used for instant mode. "An empty draft" would leave it nothing to write, so it reads the field.
    static func prefill(_ setting: Prefill) -> Prefill { setting == .empty ? .fieldText : setting }

    enum Outcome: Equatable {
        case pasted(take: String)
        /// The take is the draft as written (nothing to fix): nothing was typed.
        case unchanged
        /// Esc, or the panel was opened: nothing was typed.
        case cancelled
        case failed(Failure)
    }

    /// Every failure leaves the field untouched.
    enum Failure: Equatable {
        case engine(String)
        case noTake
        /// The user moved to another app while it was writing.
        case leftField(take: String)
        /// Same app, but focus moved to another text box or its text changed while it was writing.
        case fieldChanged(take: String)
        /// The field's app couldn't be brought back to the front; the take is on the clipboard.
        case couldNotReturn(take: String)
        /// The engine stopped before the take was finished. Half a take is never pasted unseen.
        case cutShort(take: String)

        /// The take that was written, for "Open in Takes".
        var take: String? {
            switch self {
            case .leftField(let take), .fieldChanged(let take), .couldNotReturn(let take), .cutShort(let take): return take
            case .engine, .noTake: return nil
            }
        }

        func message(app: String) -> String {
            switch self {
            case .engine(let reason): return String(localized: "Nothing was pasted. \(reason)")
            case .noTake: return String(localized: "The model sent back an empty take. Nothing was pasted.")
            case .leftField: return String(localized: "You left \(app), so nothing was pasted.")
            case .fieldChanged: return String(localized: "Couldn't confirm the text box in \(app), so nothing was pasted.")
            case .couldNotReturn: return String(localized: "Couldn't get back to \(app). The take is on the clipboard: press ⌘V.")
            case .cutShort: return String(localized: "The take was cut off before it was finished, so nothing was pasted.")
            }
        }

        /// Why a paste sent no keys: the text box had changed by the time the paste checked it, or its app couldn't
        /// be brought back to the front.
        static func notPasted(_ outcome: Paster.Outcome, take: String) -> Failure {
            outcome == .fieldChanged ? .fieldChanged(take: take) : .couldNotReturn(take: take)
        }
    }

    /// `model` is the one the current engine runs (a local model with the local engine); nil uses the preset's.
    static func request(preset: Preset, draft: String, rules: [VoiceRule], model: String? = nil) -> EngineRequest {
        EngineRequest(system: PromptBuilder.system(preset: preset, takes: 1, rules: rules),
                      user: PromptBuilder.user(draft: draft, mode: .fresh, takes: 1),
                      takes: 1, model: model ?? preset.model, effort: preset.effort)
    }
}

/// One instant run: write, check the field is still there, paste. The engine, the paste and the focus check
/// are passed in, so tests can run it without Claude or another app.
@MainActor
final class InstantRun {
    typealias Paste = (_ take: String, _ done: @escaping (Bool) -> Void) -> Void

    private let engine: TakesEngine
    private let paste: Paste
    private let stillInField: () -> Bool
    private let sameField: () -> Bool
    private let unchanged: (String) -> Bool
    private let notPasted: (String) -> InstantMode.Failure
    private let note: (String) -> Void
    private let verdict: () -> String
    private(set) var isCancelled = false
    private(set) var result: EngineResult?

    /// `unchanged` says whether a take is the draft as written; such a take is never pasted.
    /// `sameField` says whether the text box read from still has focus with the text that was read.
    /// `notPasted` says why a paste sent no keys. Unless told otherwise, the app couldn't be brought back.
    /// `note` gets a line for focus.log when the run stops before the paste; `verdict` is what the check found.
    init(
        engine: TakesEngine, paste: @escaping Paste, stillInField: @escaping () -> Bool,
        sameField: @escaping () -> Bool = { true }, unchanged: @escaping (String) -> Bool = { _ in false },
        notPasted: @escaping (String) -> InstantMode.Failure = { .couldNotReturn(take: $0) },
        note: @escaping (String) -> Void = { _ in }, verdict: @escaping () -> String = { FocusReader.lastVerdict }
    ) {
        self.engine = engine
        self.paste = paste
        self.stillInField = stillInField
        self.sameField = sameField
        self.unchanged = unchanged
        self.notPasted = notPasted
        self.note = note
        self.verdict = verdict
    }

    /// Nothing is pasted after this, even if the take arrives a moment later.
    func cancel() { isCancelled = true }

    func run(_ request: EngineRequest) async -> InstantMode.Outcome {
        let result: EngineResult
        do {
            result = try await engine.run(request) { _ in }
        } catch {
            return isCancelled ? .cancelled : .failed(.engine(error.localizedDescription))
        }
        if isCancelled { return .cancelled }
        self.result = result
        guard let take = result.takes.first?.trimmingCharacters(in: .whitespacesAndNewlines), !take.isEmpty else {
            return .failed(.noTake)
        }
        if result.cutShort { return .failed(.cutShort(take: take)) }
        if unchanged(take) { return .unchanged }
        guard stillInField() else {
            note("paste not sent\tapp not in front")
            return .failed(.leftField(take: take))
        }
        guard sameField() else {
            note("paste not sent\t" + verdict())
            return .failed(.fieldChanged(take: take))
        }
        let pasted = await withCheckedContinuation { continuation in
            paste(take) { continuation.resume(returning: $0) }
        }
        if pasted { return .pasted(take: take) }
        // Cancelled while the paste was waiting to send its keys: it sent none.
        return isCancelled ? .cancelled : .failed(notPasted(take))
    }
}

/// The paste an instant run makes. It can be called off until the moment its keys go out (Esc, or the panel
/// taking over, while it waits for a held key or for the app), and it remembers why it sent none.
@MainActor
final class InstantPaste {
    private let focus: FocusSnapshot
    private let replaceAll: Bool
    private let restoreClipboard: Bool
    private let environment: Paster.Environment
    /// Whether the run was cancelled. Set once the run exists.
    var cancelled: () -> Bool = { false }
    private(set) var outcome = Paster.Outcome.pasted

    init(focus: FocusSnapshot, replaceAll: Bool, restoreClipboard: Bool, environment: Paster.Environment = Paster.Environment()) {
        self.focus = focus
        self.replaceAll = replaceAll
        self.restoreClipboard = restoreClipboard
        self.environment = environment
    }

    func paste(_ take: String, done: @escaping (Bool) -> Void) {
        // When the box can't be confirmed the toast says nothing was pasted, so the clipboard goes back.
        Paster.paste(
            take, into: focus, replaceAll: replaceAll, restoreClipboard: restoreClipboard, keepTakeIfFieldChanged: false,
            cancelled: { [weak self] in self?.cancelled() ?? true }, environment: environment
        ) { [weak self] outcome in
            self?.outcome = outcome
            done(outcome == .pasted)
        }
    }

    /// Why the paste sent no keys, for the toast.
    func failure(take: String) -> InstantMode.Failure { InstantMode.Failure.notPasted(outcome, take: take) }
}

/// Runs instant mode for the app: reads the field, shows progress in the toast, pastes, and hands over to
/// the panel for "Open in Takes".
@MainActor
final class InstantModeController {
    private let panel: PanelController
    private let toast = ToastController()
    private var run: InstantRun?
    private var runTask: Task<Void, Never>?
    private var escapeID: UInt32?
    /// Where the field's caret was, so every toast of a run shows in the same place.
    private var caret: CGRect?
    /// What the last run left for "Open in Takes", while its toast is up.
    private struct Last {
        var presetID: String
        var focus: FocusSnapshot
        var draft: String
        var take: String?
        /// The take was cut off; the panel says so.
        var cutShort = false
        /// The run's history entry, so a take pasted from the panel is marked on it.
        var historyID: String?
        /// Whether the preset's hotkey, pressed again while the toast is up, opens this in Takes. Not after "too much
        /// text": the next press should write from the part just selected.
        var hotKeyOpens = true
        var until: Date
    }
    private var last: Last?

    init(panel: PanelController) {
        self.panel = panel
        panel.onTakingKeyboard = { [weak self] in self?.panelTakesOver() }
    }

    /// Handles a preset hotkey when the preset writes right away. Returns false to open the panel as usual.
    func handle(presetID: String?) -> Bool {
        let preset = presetID.flatMap { Store.shared.preset(id: $0) }
        let instant = preset.map { $0.writesInstantly && $0.hotKey != nil } ?? false
        let showing = last.map { $0.presetID == presetID && $0.until > Date() && $0.hotKeyOpens } ?? false
        switch InstantMode.hotKeyAction(writesInstantly: instant, running: run != nil, resultShowing: showing) {
        case .openPanel:
            panelTakesOver()
            return false
        case .keepWriting:
            break
        case .openResult:
            openInTakes()
        case .write:
            if let preset { start(preset) }
        }
        return true
    }

    private func start(_ preset: Preset) {
        panel.close()
        let store = Store.shared
        let focus = FocusReader.snapshot(prefill: InstantMode.prefill(store.settings.prefill))
        let app = focus.app?.localizedName ?? String(localized: "the app")
        let draft: String, replaceAll: Bool
        switch InstantMode.start(text: focus.text, source: focus.source, editable: focus.editable) {
        case .openPanel:
            panel.summon(focus: focus, presetID: preset.id)
            return
        case .tooLong:
            caret = focus.caretRect
            last = Last(
                presetID: preset.id, focus: focus, draft: "", hotKeyOpens: false,
                until: Date().addingTimeInterval(InstantToast.failedSeconds))
            show(.failed(message: InstantMode.tooLongMessage(app: app), hotKey: nil), near: focus.caretRect)
            return
        case .write(let text, let all):
            draft = text
            replaceAll = all
        }
        last = nil
        caret = focus.caretRect
        let pid = focus.app?.processIdentifier
        let restore = store.settings.restoreClipboard
        // The paste checks the text box once more after bringing it back; what it reports picks the failure toast.
        let paste = InstantPaste(focus: focus, replaceAll: replaceAll, restoreClipboard: restore)
        let run = InstantRun(
            engine: Engines.current(store.settings),
            paste: { take, done in paste.paste(take, done: done) },
            stillInField: { pid == nil || NSWorkspace.shared.frontmostApplication?.processIdentifier == pid },
            // Select all and paste must not wipe another text box (another Slack channel) or text typed meanwhile.
            sameField: { !replaceAll || FocusReader.stillEditing(focus) },
            unchanged: { take in Proofread.nothingToFix(draft: draft, takes: [take]) },
            notPasted: { take in paste.failure(take: take) },
            note: { FocusLog.paste(focus, $0) })
        paste.cancelled = { [weak run] in run?.isCancelled ?? true }
        self.run = run
        show(.writing(preset: preset.name), near: focus.caretRect)
        listenForEscape()

        let request = InstantMode.request(preset: preset, draft: draft, rules: store.settings.voiceRules,
                                          model: store.settings.runModel(for: preset))
        runTask = Task {
            let outcome = await run.run(request)
            guard self.run === run else { return }
            self.run = nil
            stopListeningForEscape()
            finish(outcome, preset: preset, focus: focus, draft: draft, app: app, restore: restore, result: run.result)
        }
    }

    private func finish(_ outcome: InstantMode.Outcome, preset: Preset, focus: FocusSnapshot, draft: String,
                        app: String, restore: Bool, result: EngineResult?) {
        let hotKey = preset.hotKey?.display
        if case .cancelled = outcome {
            show(.cancelled, near: focus.caretRect)
            return
        }
        var historyID: String?
        if let result, !result.takes.isEmpty {
            var entry = HistoryEntry(appName: app, presetName: preset.name, draft: draft, takes: Array(result.takes.prefix(1)))
            if case .pasted = outcome { entry.pastedIndex = 0 }
            Store.shared.record(entry)
            historyID = entry.id
            RunLog.append([
                "kind": "instant", "model": Store.shared.settings.runModel(for: preset), "effort": preset.effort, "takes": 1,
                "engine": Store.shared.settings.engine.rawValue, "wallMs": result.wallMs,
                "firstTextMs": result.firstTextMs ?? -1, "app": focus.app?.bundleIdentifier ?? "",
            ])
        }
        var last = Last(
            presetID: preset.id, focus: focus, draft: draft, cutShort: result?.cutShort ?? false, historyID: historyID,
            until: Date().addingTimeInterval(InstantToast.pastedSeconds))
        switch outcome {
        case .cancelled:
            return
        case .unchanged:
            show(.unchanged(hotKey: hotKey), near: focus.caretRect)
        case .pasted(let take):
            last.take = take
            // The box now holds the take: a paste from "Open in Takes" checks for that, not for the old draft.
            if focus.source == .field { last.focus = focus.holding(take) }
            show(.pasted(clipboardBack: restore, hotKey: hotKey), near: focus.caretRect)
        case .failed(let failure):
            last.take = failure.take
            last.until = Date().addingTimeInterval(InstantToast.failedSeconds)
            show(.failed(message: failure.message(app: app), hotKey: hotKey), near: focus.caretRect)
        }
        self.last = last
    }

    /// The panel is opening, or taking the keyboard back. A take still being written is not pasted after that:
    /// the same app is in front, so the checks would pass and the keys would go to the panel or to the box
    /// under it. The result toast goes as well, since "Open in Takes" would replace what the panel now shows.
    private func panelTakesOver() {
        if run != nil { stop() }
        toast.dismiss()
        last = nil
    }

    /// Opens the panel with the last run: on the takes screen when there's a take, else on the draft.
    private func openInTakes() {
        guard let last else { return }
        self.last = nil
        toast.dismiss()
        panel.summon(focus: last.focus, presetID: last.presetID) { model in
            model.draft = last.draft
            guard let take = last.take else { return }
            model.sourceDraft = last.draft
            model.takes = [take]
            model.cutShort = last.cutShort
            model.continueHistory(entryID: last.historyID)
            model.selected = 0
            model.screen = .takes
        }
    }

    private func show(_ state: InstantToast.State, near caret: CGRect?) {
        let view = InstantToast(state: state,
                                onCancel: { [weak self] in self?.cancelFromToast() },
                                onOpen: { [weak self] in self?.openInTakes() })
        toast.present(view, near: caret, hideAfter: state.hideAfter)
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: state.spoken, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// Esc, or Cancel on the toast.
    private func cancelFromToast() {
        guard run != nil else { return }
        stop()
        show(.cancelled, near: caret)
    }

    /// Ends the run in progress; nothing it writes is pasted.
    private func stop() {
        run?.cancel()
        run = nil
        // Cancelling the task also stops a Claude Code process that is still writing.
        runTask?.cancel()
        runTask = nil
        stopListeningForEscape()
    }

    /// Esc cancels while writing. It's held as a hotkey only for those few seconds, so the field keeps the
    /// keyboard and nothing else loses Esc.
    private func listenForEscape() {
        let esc = KeyCombo(keyCode: UInt32(kVK_Escape), modifiers: 0, display: "Esc")
        escapeID = HotKeyCenter.shared.registerTransient(esc) { [weak self] in self?.cancelFromToast() }
    }

    private func stopListeningForEscape() {
        if let escapeID { HotKeyCenter.shared.unregisterTransient(escapeID) }
        escapeID = nil
    }
}
