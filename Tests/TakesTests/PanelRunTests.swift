import XCTest

@testable import Takes

/// An engine the test steers: it streams `partial`, then waits `delay` before answering with `result`.
private final class SteeredEngine: TakesEngine, @unchecked Sendable {
    var result: EngineResult
    var partial: [String]?
    var delay: TimeInterval
    private(set) var runs = 0
    private(set) var cancelled = 0

    init(takes: [String], cutShort: Bool = false, partial: [String]? = nil, delay: TimeInterval = 0) {
        result = EngineResult(takes: takes, wallMs: 10, firstTextMs: 5, cutShort: cutShort)
        self.partial = partial
        self.delay = delay
    }

    func run(_ request: EngineRequest, onUpdate: @escaping @Sendable ([String]) -> Void) async throws -> EngineResult {
        runs += 1
        if let partial { onUpdate(partial) }
        if delay > 0 {
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                cancelled += 1
                throw error
            }
        }
        return result
    }
}

/// What the panel's model does with a run: the cut-short flag, history, a run that outlives the panel, and the
/// hotkey pressed again while the panel is open. Uses a fake engine and never saves to the real files.
@MainActor
final class PanelRunTests: XCTestCase {
    // Not English, so the English coach and its invitation stay out of these runs.
    private let draft = "אפשר להזיז את הפגישה ליום חמישי? אני צריך את המפרט עד יום רביעי"
    private var savedHistory: [HistoryEntry] = []
    private var savedSettings = AppSettings()
    private var wasReadOnly = false

    override func setUp() async throws {
        wasReadOnly = Store.readOnly
        Store.readOnly = true
        savedHistory = Store.shared.history
        savedSettings = Store.shared.settings
        Store.shared.history = []
        Store.shared.settings.keepHistory = true
        Store.shared.settings.coach.enabled = false
    }

    override func tearDown() async throws {
        Store.shared.history = savedHistory
        Store.shared.settings = savedSettings
        Store.readOnly = wasReadOnly
    }

    private func model(_ engine: SteeredEngine, text: String? = nil) -> PanelModel {
        let model = PanelModel()
        model.makeEngine = { _ in engine }
        model.logRun = { _ in }
        model.refreshModels = { _ in }
        model.reset(focus: FocusSnapshot(app: nil, text: text ?? draft, source: .field, caretRect: nil), presetID: nil)
        // No tone notes: they would ask the real engine.
        var preset = Preset(name: "Test preset", colorHex: "#2F55E0", instruction: "Make it friendly.")
        preset.showTone = false
        model.previewPreset = preset
        model.takeCount = 2
        return model
    }

    private func wait(_ what: String, until condition: @escaping () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(condition(), "timed out waiting until \(what)")
    }

    // MARK: Cut short

    func testCutShortComesFromTheResult() async {
        let engine = SteeredEngine(takes: ["Take one.", "Take tw"], cutShort: true)
        let model = model(engine)
        XCTAssertFalse(model.cutShort)
        model.generate()
        await wait("the run ends") { !model.running }
        XCTAssertEqual(model.takes, ["Take one.", "Take tw"])
        XCTAssertTrue(model.cutShort)
    }

    func testCutShortIsClearedWhenANewRunStarts() async {
        let engine = SteeredEngine(takes: ["Take one.", "Take tw"], cutShort: true)
        let model = model(engine)
        model.generate()
        await wait("the run ends") { !model.running }
        XCTAssertTrue(model.cutShort)

        engine.result = EngineResult(takes: ["Take one.", "Take two."], wallMs: 10, firstTextMs: 5)
        engine.delay = 0.2
        model.generate()
        XCTAssertFalse(model.cutShort, "cleared as the run starts, not when it ends")
        await wait("the run ends") { !model.running }
        XCTAssertFalse(model.cutShort)
    }

    func testCutShortIsClearedOnReset() async {
        let model = model(SteeredEngine(takes: ["Take one.", "Take tw"], cutShort: true))
        model.generate()
        await wait("the run ends") { !model.running }
        XCTAssertTrue(model.cutShort)
        model.reset(focus: FocusSnapshot(app: nil, text: "something else", source: .field, caretRect: nil), presetID: nil)
        XCTAssertFalse(model.cutShort)
    }

    // MARK: History

    func testPastingAFinishedRunMarksItsOwnEntry() async {
        let model = model(SteeredEngine(takes: ["Take one.", "Take two."]))
        model.generate()
        await wait("the run ends") { !model.running }
        model.paste(1)
        XCTAssertEqual(Store.shared.history.count, 1)
        XCTAssertEqual(Store.shared.history.first?.pastedIndex, 1)
    }

    func testPastingBeforeTheRunEndsLeavesThePreviousEntryAlone() async {
        let engine = SteeredEngine(takes: ["First one.", "First two."])
        let model = model(engine)
        model.generate()
        await wait("the first run ends") { !model.running }
        let first = Store.shared.history[0].id

        // A second run: its first take is done, its second is still being written.
        engine.partial = ["Second one.", "Second tw"]
        engine.delay = 5
        var pasted: [String] = []
        model.onPaste = { _, text, _ in pasted.append(text) }
        model.generate()
        await wait("the second run streams") { model.takes.count == 2 }
        XCTAssertTrue(model.running)
        model.paste(0)

        XCTAssertEqual(pasted, ["Second one."])
        let history = Store.shared.history
        XCTAssertEqual(history.count, 2)
        XCTAssertNil(history.first { $0.id == first }?.pastedIndex, "the earlier run's entry isn't the one that was pasted")
        XCTAssertEqual(history[0].takes, ["Second one."], "the take that was finished; the half-written one is left out")
        XCTAssertEqual(history[0].pastedIndex, 0)
        model.panelClosed()
    }

    func testANewSummonForgetsTheLastRunsEntry() async {
        let model = model(SteeredEngine(takes: ["Take one.", "Take two."]))
        model.generate()
        await wait("the run ends") { !model.running }

        // Instant mode hands its take over with no run in the panel, and no entry of its own here.
        model.reset(focus: FocusSnapshot(app: nil, text: draft, source: .field, caretRect: nil), presetID: nil)
        model.takes = ["An instant take."]
        model.screen = .takes
        model.paste(0)
        XCTAssertNil(Store.shared.history[0].pastedIndex, "an older run's entry is not marked for it")
    }

    func testTakesHandedOverMarkTheEntryTheyCameWith() {
        let entry = HistoryEntry(appName: "Slack", presetName: "Test preset", draft: draft, takes: ["An instant take."])
        Store.shared.record(entry)
        let model = model(SteeredEngine(takes: []))
        model.takes = ["An instant take."]
        model.continueHistory(entryID: entry.id)
        model.screen = .takes
        model.paste(0)
        XCTAssertEqual(Store.shared.history.first { $0.id == entry.id }?.pastedIndex, 0)
        XCTAssertEqual(Store.shared.history.count, 1)
    }

    // MARK: A run and its panel

    func testClosingThePanelStopsTheRun() async {
        let engine = SteeredEngine(takes: ["Take one.", "Take two."], delay: 5)
        let model = model(engine)
        model.generate()
        await wait("the engine starts") { engine.runs == 1 }
        XCTAssertTrue(model.running)

        model.panelClosed()
        XCTAssertFalse(model.running)
        await wait("the engine is cancelled") { engine.cancelled == 1 }
        XCTAssertTrue(model.takes.isEmpty)
        XCTAssertTrue(Store.shared.history.isEmpty, "a run that was abandoned is not filed")
    }

    func testClosingThePanelLeavesAFinishedRunAlone() async {
        let model = model(SteeredEngine(takes: ["Take one.", "Take two."]))
        model.generate()
        await wait("the run ends") { !model.running }
        model.panelClosed()
        XCTAssertEqual(model.takes, ["Take one.", "Take two."])
    }

    // MARK: The hotkey, pressed again

    func testHotKeyAgainKeepsATypedDraft() {
        let model = model(SteeredEngine(takes: []), text: "what the field held")
        model.draft = "what I have typed since"
        model.replyContext = ReplyContext(text: "They asked about Thursday", source: .typed)
        let focusToken = model.focusToken
        model.hotKeyPressedAgain(presetID: nil)
        XCTAssertEqual(model.draft, "what I have typed since")
        XCTAssertEqual(model.replyContext?.text, "They asked about Thursday")
        XCTAssertEqual(model.screen, .compose)
        XCTAssertGreaterThan(model.focusToken, focusToken, "the keyboard goes back to the draft")
    }

    func testHotKeyAgainKeepsFinishedTakes() async {
        let model = model(SteeredEngine(takes: ["Take one.", "Take two."]))
        model.generate()
        await wait("the run ends") { !model.running }
        model.selected = 1
        model.hotKeyPressedAgain(presetID: Store.shared.presets.last?.id)
        XCTAssertEqual(model.takes, ["Take one.", "Take two."])
        XCTAssertEqual(model.screen, .takes)
        XCTAssertEqual(model.selected, 1)
        XCTAssertEqual(model.draft, draft)
    }

    func testHotKeyAgainKeepsARunThatIsStillWriting() async {
        let engine = SteeredEngine(takes: ["Take one.", "Take two."], delay: 0.3)
        let model = model(engine)
        model.generate()
        await wait("the engine starts") { engine.runs == 1 }
        model.hotKeyPressedAgain(presetID: nil)
        XCTAssertTrue(model.running)
        await wait("the run ends") { !model.running }
        XCTAssertEqual(model.takes, ["Take one.", "Take two."])
        XCTAssertEqual(engine.cancelled, 0)
    }

    func testPresetHotKeyAgainPicksThatPresetAndKeepsTheDraft() throws {
        let presets = Store.shared.presets
        try XCTSkipIf(presets.count < 2, "needs two presets")
        let model = PanelModel()
        model.refreshModels = { _ in }
        model.reset(focus: FocusSnapshot(app: nil, text: "what the field held", source: .field, caretRect: nil), presetID: presets[0].id)
        model.draft = "what I have typed since"
        model.hotKeyPressedAgain(presetID: presets[1].id)
        XCTAssertEqual(model.presetID, presets[1].id)
        XCTAssertEqual(model.draft, "what I have typed since")
        XCTAssertEqual(model.screen, .compose)
        // A hotkey for a preset that no longer exists changes nothing.
        model.hotKeyPressedAgain(presetID: "gone")
        XCTAssertEqual(model.presetID, presets[1].id)
    }
}
