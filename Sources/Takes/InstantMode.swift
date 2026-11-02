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
    }

    static func start(text: String, source: FocusSnapshot.Source) -> Start {
        let draft = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return .openPanel }
        switch source {
        case .field: return .write(draft: draft, replaceAll: true)
        case .selection: return .write(draft: draft, replaceAll: false)
        // Text that wasn't read from a text box has nowhere safe to go back to.
        case .none: return .openPanel
        }
    }

    /// The prefill used for instant mode. "An empty draft" would leave it nothing to write, so it reads the field.
    static func prefill(_ setting: Prefill) -> Prefill { setting == .empty ? .fieldText : setting }

    enum Outcome: Equatable {
        case pasted(take: String)
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
        /// The field's app couldn't be brought back to the front; the take is on the clipboard.
        case couldNotReturn(take: String)

        /// The take that was written, for "Open in Takes".
        var take: String? {
            switch self {
            case .leftField(let take), .couldNotReturn(let take): return take
            case .engine, .noTake: return nil
            }
        }

        func message(app: String) -> String {
            switch self {
            case .engine(let reason): return "Nothing was pasted. \(reason)"
            case .noTake: return "Claude sent back an empty take. Nothing was pasted."
            case .leftField: return "You left \(app), so nothing was pasted."
            case .couldNotReturn: return "Couldn't get back to \(app). The take is on the clipboard: press ⌘V."
            }
        }
    }

    static func request(preset: Preset, draft: String, rules: [VoiceRule]) -> EngineRequest {
        EngineRequest(system: PromptBuilder.system(preset: preset, takes: 1, rules: rules),
                      user: PromptBuilder.user(draft: draft, mode: .fresh, takes: 1),
                      takes: 1, model: preset.model, effort: preset.effort)
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
    private(set) var isCancelled = false
    private(set) var result: EngineResult?

    init(engine: TakesEngine, paste: @escaping Paste, stillInField: @escaping () -> Bool) {
        self.engine = engine
        self.paste = paste
        self.stillInField = stillInField
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
        guard stillInField() else { return .failed(.leftField(take: take)) }
        let pasted = await withCheckedContinuation { continuation in
            paste(take) { continuation.resume(returning: $0) }
        }
        return pasted ? .pasted(take: take) : .failed(.couldNotReturn(take: take))
    }
}

/// Runs instant mode for the app: reads the field, shows progress in the toast, pastes, and hands over to
/// the panel for "Open in Takes".
@MainActor
final class InstantModeController {
    private let panel: PanelController
    private let toast = ToastController()
    private var run: InstantRun?
    private var escapeID: UInt32?
    /// Where the field's caret was, so every toast of a run shows in the same place.
    private var caret: CGRect?
    /// What the last run left for "Open in Takes", while its toast is up.
    private var last: (presetID: String, focus: FocusSnapshot, draft: String, take: String?, until: Date)?

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
        if let last, last.presetID == presetID, last.until > Date() {
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
        guard case .write(let draft, let replaceAll) = InstantMode.start(text: focus.text, source: focus.source) else {
            panel.summon(focus: focus, presetID: preset.id)
            return
        }
        last = nil
        caret = focus.caretRect
        let app = focus.app?.localizedName ?? "the app"
        let pid = focus.app?.processIdentifier
        let restore = store.settings.restoreClipboard
        let run = InstantRun(
            engine: Engines.current(store.settings),
            paste: { take, done in
                Paster.paste(take, into: focus, replaceAll: replaceAll, restoreClipboard: restore, done: done)
            },
            stillInField: { pid == nil || NSWorkspace.shared.frontmostApplication?.processIdentifier == pid })
        self.run = run
        show(.writing(preset: preset.name), near: focus.caretRect)
        listenForEscape()

        let request = InstantMode.request(preset: preset, draft: draft, rules: store.settings.voiceRules)
        Task {
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
        let hold: TimeInterval
        switch outcome {
        case .cancelled:
            show(.cancelled, near: focus.caretRect)
            return
        case .pasted(let take):
            hold = InstantToast.pastedSeconds
            last = (preset.id, focus, draft, take, Date().addingTimeInterval(hold))
            show(.pasted(clipboardBack: restore, hotKey: hotKey), near: focus.caretRect)
        case .failed(let failure):
            hold = InstantToast.failedSeconds
            last = (preset.id, focus, draft, failure.take, Date().addingTimeInterval(hold))
            show(.failed(message: failure.message(app: app), hotKey: hotKey), near: focus.caretRect)
        }

        if let result, !result.takes.isEmpty {
            var entry = HistoryEntry(appName: app, presetName: preset.name, draft: draft, takes: Array(result.takes.prefix(1)))
            if case .pasted = outcome { entry.pastedIndex = 0 }
            Store.shared.record(entry)
            RunLog.append(["kind": "instant", "model": preset.model, "effort": preset.effort, "takes": 1,
                           "engine": Store.shared.settings.engine.rawValue, "wallMs": result.wallMs,
                           "firstTextMs": result.firstTextMs ?? -1, "app": focus.app?.bundleIdentifier ?? ""])
        }
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
