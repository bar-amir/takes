import XCTest
@testable import Takes

/// An engine that answers after `delay` with fixed takes, or throws.
private struct FakeEngine: TakesEngine {
    var takes: [String] = ["Thursday works for me."]
    var error: Error?
    var delay: TimeInterval = 0

    func run(_ request: EngineRequest, onUpdate: @escaping @Sendable ([String]) -> Void) async throws -> EngineResult {
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        if let error { throw error }
        return EngineResult(takes: takes, wallMs: 10, firstTextMs: 5)
    }
}

@MainActor
final class InstantModeTests: XCTestCase {
    private var pasted: [String] = []

    private func runner(_ engine: FakeEngine, inField: Bool = true, pasteWorks: Bool = true) -> InstantRun {
        InstantRun(engine: engine,
                   paste: { [unowned self] take, done in pasted.append(take); done(pasteWorks) },
                   stillInField: { inField })
    }

    private let request = InstantMode.request(preset: Store.defaultPresets[0], draft: "ya thursday works", rules: [])

    // MARK: Deciding

    func testEmptyDraftOpensThePanel() {
        XCTAssertEqual(InstantMode.start(text: "", source: .field), .openPanel)
        XCTAssertEqual(InstantMode.start(text: " \n ", source: .field), .openPanel)
    }

    func testUnreadableFieldOpensThePanel() {
        XCTAssertEqual(InstantMode.start(text: "hello", source: .none), .openPanel)
    }

    func testFieldTextReplacesTheField() {
        XCTAssertEqual(InstantMode.start(text: "  hello \n", source: .field), .write(draft: "hello", replaceAll: true))
    }

    func testSelectionReplacesOnlyTheSelection() {
        XCTAssertEqual(InstantMode.start(text: "hello", source: .selection), .write(draft: "hello", replaceAll: false))
    }

    func testEmptyPrefillStillReadsTheField() {
        XCTAssertEqual(InstantMode.prefill(.empty), .fieldText)
        XCTAssertEqual(InstantMode.prefill(.selectionOnly), .selectionOnly)
        XCTAssertEqual(InstantMode.prefill(.fieldText), .fieldText)
    }

    func testRequestWritesOneTakeWithThePresetsSettings() {
        var preset = Store.defaultPresets[0]
        preset.takes = 4
        preset.model = Models.haiku
        preset.effort = "medium"
        let request = InstantMode.request(preset: preset, draft: "hi", rules: [])
        XCTAssertEqual(request.takes, 1)
        XCTAssertEqual(request.model, Models.haiku)
        XCTAssertEqual(request.effort, "medium")
        XCTAssertTrue(request.system.contains("Write exactly 1 version."))
    }

    // MARK: Running

    func testSuccessPastesTheFirstTake() async {
        let outcome = await runner(FakeEngine(takes: ["  Thursday works.  "])).run(request)
        XCTAssertEqual(outcome, .pasted(take: "Thursday works."))
        XCTAssertEqual(pasted, ["Thursday works."])
    }

    func testEngineErrorPastesNothing() async {
        let outcome = await runner(FakeEngine(error: EngineError.failed("Add your Anthropic API key in Settings › Engine."))).run(request)
        XCTAssertEqual(outcome, .failed(.engine("Add your Anthropic API key in Settings › Engine.")))
        XCTAssertTrue(pasted.isEmpty)
    }

    func testEmptyTakePastesNothing() async {
        let outcome = await runner(FakeEngine(takes: ["   "])).run(request)
        XCTAssertEqual(outcome, .failed(.noTake))
        XCTAssertTrue(pasted.isEmpty)
    }

    func testCancelPastesNothing() async {
        let run = runner(FakeEngine(delay: 0.2))
        let task = Task { await run.run(request) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        run.cancel()
        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertTrue(pasted.isEmpty)
    }

    func testCancelDuringAFailureStillCountsAsCancelled() async {
        let run = runner(FakeEngine(error: EngineError.failed("boom"), delay: 0.2))
        let task = Task { await run.run(request) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        run.cancel()
        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelled)
    }

    func testLeavingTheFieldPastesNothing() async {
        let outcome = await runner(FakeEngine(), inField: false).run(request)
        XCTAssertEqual(outcome, .failed(.leftField(take: "Thursday works for me.")))
        XCTAssertTrue(pasted.isEmpty)
    }

    func testAppThatWontComeBackLeavesTheTakeOnTheClipboard() async {
        let outcome = await runner(FakeEngine(), pasteWorks: false).run(request)
        XCTAssertEqual(outcome, .failed(.couldNotReturn(take: "Thursday works for me.")))
        XCTAssertEqual(InstantMode.Failure.couldNotReturn(take: "x").take, "x")
    }

    func testFailureMessagesSayWhatHappenedAndWhatToDo() {
        XCTAssertEqual(InstantMode.Failure.leftField(take: "x").message(app: "Slack"), "You left Slack, so nothing was pasted.")
        XCTAssertTrue(InstantMode.Failure.couldNotReturn(take: "x").message(app: "Mail").contains("press ⌘V"))
        XCTAssertTrue(InstantMode.Failure.engine("API error: overloaded").message(app: "Mail").hasPrefix("Nothing was pasted."))
        XCTAssertNil(InstantMode.Failure.noTake.take)
    }

    // MARK: Settings

    func testPresetsSavedBeforeInstantModeStillLoad() throws {
        let old = #"""
        [{"id":"a","name":"Shorter","colorHex":"#8A4B08","instruction":"Shorter.","dos":[],"avoid":[],"examples":[],
          "language":"sameAsDraft","length":"shorter","apps":[],"takes":3,"model":"claude-sonnet-5-5","effort":"low"}]
        """#
        let presets = try JSONDecoder().decode([Preset].self, from: Data(old.utf8))
        XCTAssertEqual(presets.first?.name, "Shorter")
        XCTAssertEqual(presets.first?.writesInstantly, false)
    }

    func testInstantModeRoundTrips() throws {
        var preset = Store.defaultPresets[2]
        preset.writesInstantly = true
        let decoded = try JSONDecoder().decode(Preset.self, from: JSONEncoder().encode(preset))
        XCTAssertTrue(decoded.writesInstantly)

        // Off is stored as absent, so presets exported with it off look the same as before.
        preset.writesInstantly = false
        let json = String(decoding: try JSONEncoder().encode(preset), as: UTF8.self)
        XCTAssertFalse(json.contains("instantMode"))
    }

    func testDefaultPresetsAreOff() {
        XCTAssertTrue(Store.defaultPresets.allSatisfy { !$0.writesInstantly })
    }
}
