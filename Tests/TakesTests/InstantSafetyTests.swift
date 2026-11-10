import XCTest

@testable import Takes

private struct CutShortEngine: TakesEngine {
    var takes = ["Thursday works for me, but I need the specs by"]
    var cutShort = true

    func run(_ request: EngineRequest, onUpdate: @escaping @Sendable ([String]) -> Void) async throws -> EngineResult {
        EngineResult(takes: takes, wallMs: 10, firstTextMs: 5, cutShort: cutShort)
    }
}

/// Instant mode pastes a take nobody has seen yet, so it stops whenever the take or its target is in doubt.
@MainActor
final class InstantSafetyTests: XCTestCase {
    private var pasted: [String] = []
    private let request = InstantMode.request(preset: Store.defaultPresets[0], draft: "ya thursday works", rules: [])

    private func run(_ engine: CutShortEngine, paste outcome: Paster.Outcome = .pasted) -> InstantRun {
        InstantRun(
            engine: engine,
            paste: { [unowned self] take, done in
                pasted.append(take)
                done(outcome == .pasted)
            },
            stillInField: { true },
            notPasted: { InstantMode.Failure.notPasted(outcome, take: $0) })
    }

    func testCutShortTakeIsNotPasted() async {
        let outcome = await run(CutShortEngine()).run(request)
        XCTAssertEqual(outcome, .failed(.cutShort(take: "Thursday works for me, but I need the specs by")))
        XCTAssertTrue(pasted.isEmpty)
    }

    func testCutShortIsCheckedBeforeAnythingElse() async {
        // Even a take that reads the same as the draft so far is reported as cut off, not as "no changes needed".
        let run = InstantRun(
            engine: CutShortEngine(),
            paste: { [unowned self] take, done in
                pasted.append(take)
                done(true)
            },
            stillInField: { false }, unchanged: { _ in true })
        let outcome = await run.run(request)
        XCTAssertEqual(outcome, .failed(.cutShort(take: "Thursday works for me, but I need the specs by")))
        XCTAssertTrue(pasted.isEmpty)
    }

    func testWholeTakeIsStillPasted() async {
        let outcome = await run(CutShortEngine(takes: ["Thursday works for me."], cutShort: false)).run(request)
        XCTAssertEqual(outcome, .pasted(take: "Thursday works for me."))
        XCTAssertEqual(pasted, ["Thursday works for me."])
    }

    func testCutShortFailureSaysSoAndKeepsTheTakeForThePanel() {
        let failure = InstantMode.Failure.cutShort(take: "half a take")
        XCTAssertEqual(failure.message(app: "Slack"), "The take was cut off before it was finished, so nothing was pasted.")
        XCTAssertEqual(failure.take, "half a take", "Open in Takes shows what was written")
    }

    func testBoxThatChangedAtThePasteItselfIsReportedAsChanged() async {
        // The paste checks the text box once more after bringing it back, and sends no keys if it isn't the same.
        let outcome = await run(CutShortEngine(takes: ["Thursday works for me."], cutShort: false), paste: .fieldChanged).run(request)
        XCTAssertEqual(outcome, .failed(.fieldChanged(take: "Thursday works for me.")))
    }

    func testAppThatWontComeBackIsReportedAsSuch() async {
        let outcome = await run(CutShortEngine(takes: ["Thursday works for me."], cutShort: false), paste: .couldNotReturn).run(request)
        XCTAssertEqual(outcome, .failed(.couldNotReturn(take: "Thursday works for me.")))
    }
}
