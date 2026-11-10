import XCTest
@testable import Takes

/// Under an error the takes screen offers nothing to paste, and a take cut short is marked and can't be pasted
/// while whole takes still can. The footers themselves are checked in the `--snapshot` renders.
@MainActor
final class TakesFooterTests: XCTestCase {
    private func model() -> PanelModel {
        let model = PanelModel()
        model.sourceDraft = "ya thursday works but i need the specs by wed eod"
        model.takes = [
            "Thursday works. I need the specs by Wednesday EOD.", "Sure, Thursday. Specs by Wed EOD, please.",
            "Thursday's fine if the specs land by",
        ]
        return model
    }

    func testWholeTakesCanBePasted() {
        let model = model()
        XCTAssertEqual((0..<3).map { TakesView.canPaste($0, in: model) }, [true, true, true])
        XCTAssertFalse(TakesView.canPaste(3, in: model))
    }

    func testNothingCanBePastedUnderAnError() {
        let model = model()
        // Part of a take arrived before the connection dropped.
        model.takes = ["Thursday works. I need"]
        model.error = "The connection was lost. Check your network and try again."
        XCTAssertFalse(TakesView.canPaste(0, in: model))
        model.limit = ClaudeCodeEngine.resultError("5-hour limit reached ∙ resets 3pm") as? UsageLimitError
        XCTAssertFalse(TakesView.canPaste(0, in: model))
    }

    func testOnlyTheLastTakeOfAFinishedRunIsCutShort() {
        let model = model()
        XCTAssertFalse(TakesView.isCutShort(2, in: model))
        model.cutShort = true
        XCTAssertEqual((0..<3).map { TakesView.isCutShort($0, in: model) }, [false, false, true])
        model.running = true
        XCTAssertFalse(TakesView.isCutShort(2, in: model), "a new run's takes aren't marked by the last one")
        model.running = false
        model.error = "The connection was lost."
        XCTAssertFalse(TakesView.isCutShort(2, in: model))
    }

    func testACutShortTakeCannotBePastedButWholeOnesCan() {
        let model = model()
        model.cutShort = true
        XCTAssertEqual((0..<3).map { TakesView.canPaste($0, in: model) }, [true, true, false])
    }

    /// A take still being written isn't pasteable either, as before.
    func testATakeBeingWrittenCannotBePasted() {
        let model = model()
        model.running = true
        XCTAssertEqual((0..<3).map { TakesView.canPaste($0, in: model) }, [true, true, false])
    }

    // MARK: Diffs off the main thread

    func testATakeIsDiffedOnlyOnceWholeAndWanted() {
        let model = model()
        XCTAssertNil(TakesView.changesKey(0, in: model), "a regular run diffs only when ⌥ shows the changes")
        model.optionHeld = true
        XCTAssertEqual(TakesView.changesKey(0, in: model), ChangesKey(draft: model.sourceDraft, take: model.takes[0]))

        // Streaming: the take being written is never diffed, however often it grows.
        model.running = true
        XCTAssertNotNil(TakesView.changesKey(1, in: model))
        XCTAssertNil(TakesView.changesKey(2, in: model))
        model.running = false

        model.cutShort = true
        XCTAssertNil(TakesView.changesKey(2, in: model), "a take cut short isn't shown as changes")
    }

    func testMinimalEditRunsDiffForTheFixCount() {
        let model = model()
        model.previewPreset = .proofread
        XCTAssertNotNil(TakesView.changesKey(0, in: model))
        model.running = true
        XCTAssertNil(TakesView.changesKey(2, in: model))
    }
}
