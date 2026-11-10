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
            case .fieldChanged: return String(localized: "The text box in \(app) changed while Takes was writing, so nothing was pasted.")
            case .couldNotReturn: return String(localized: "Couldn't get back to \(app). The take is on the clipboard: press ⌘V.")
            case .cutShort: return String(localized: "The take was cut off before it was finished, so nothing was pasted.")
            }
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
    typealias Paste = (_ take: String, _ done: @escaping (Paster.Outcome) -> Void) -> Void

    private let engine: TakesEngine
    private let paste: Paste
    private let stillInField: () -> Bool
    private let sameField: () -> Bool
    private let unchanged: (String) -> Bool
    private(set) var isCancelled = false
    private(set) var result: EngineResult?

    /// `unchanged` says whether a take is the draft as written; such a take is never pasted.
    /// `sameField` says whether the text box read from still has focus with the text that was read.
    init(engine: TakesEngine, paste: @escaping Paste, stillInField: @escaping () -> Bool,
         sameField: @escaping () -> Bool = { true }, unchanged: @escaping (String) -> Bool = { _ in false }) {
        self.engine = engine
        self.paste = paste
        self.stillInField = stillInField
        self.sameField = sameField
        self.unchanged = unchanged
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
        guard stillInField() else { return .failed(.leftField(take: take)) }
        guard sameField() else { return .failed(.fieldChanged(take: take)) }
        let outcome = await withCheckedContinuation { continuation in
            paste(take) { continuation.resume(returning: $0) }
        }
        switch outcome {
        case .pasted: return .pasted(take: take)
        case .couldNotReturn: return .failed(.couldNotReturn(take: take))
        // The paste checks the text box once more, after bringing it back; it put the clipboard back too.
        case .fieldChanged: return .failed(.fieldChanged(take: take))
        }
    }
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

    init(panel: PanelController) { self.panel = panel }

    /// Handles a preset hotkey when the preset writes right away. Returns false to open the panel as usual.
    func handle(presetID: String?) -> Bool {
        guard let presetID else {
            // The summon hotkey: the panel takes over from a run in progress.
            if run != nil {
                stop()
                toast.dismiss()
            }
            return false
        }
        let store = Store.shared
        guard let preset = store.preset(id: presetID), preset.writesInstantly, preset.hotKey != nil else { return false }
        if run != nil { return true }
        // Pressed again while the result is showing: open it in Takes.
        if let last, last.presetID == presetID, last.until > Date(), last.hotKeyOpens {
            openInTakes()
            return true
        }
        start(preset)
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
        let run = InstantRun(
            engine: Engines.current(store.settings),
            paste: { take, done in
                // When the box can't be confirmed the toast says nothing was pasted, so the clipboard goes back.
                Paster.paste(take, into: focus, replaceAll: replaceAll, restoreClipboard: restore, keepTakeIfFieldChanged: false, done: done)
            },
            stillInField: { pid == nil || NSWorkspace.shared.frontmostApplication?.processIdentifier == pid },
            // Select all and paste must not wipe another text box (another Slack channel) or text typed meanwhile.
            sameField: { !replaceAll || FocusReader.stillEditing(focus) },
            unchanged: { take in Proofread.nothingToFix(draft: draft, takes: [take]) })
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
