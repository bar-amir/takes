import XCTest
@testable import Takes

/// `TakeSplitter.cutShort`, the one rule every engine uses for `EngineResult.cutShort`.
final class CutShortTests: XCTestCase {
    func testOnlyAnUnfinishedLastTakeIsCutShort() {
        // One whole take, then a partial one.
        XCTAssertTrue(TakeSplitter.cutShort("Thursday works.\n===\nSure, Thu", stoppedEarly: true))
        // Only a partial take.
        XCTAssertTrue(TakeSplitter.cutShort("Thursday wor", stoppedEarly: true))
        // Stopped right after a separator, finished or still being written: every take is whole.
        XCTAssertFalse(TakeSplitter.cutShort("Thursday works.\n===\n", stoppedEarly: true))
        XCTAssertFalse(TakeSplitter.cutShort("Thursday works.\n===", stoppedEarly: true))
        XCTAssertFalse(TakeSplitter.cutShort("Thursday works.\n=\n  \n", stoppedEarly: true))
        // Nothing written, or an answer that finished.
        XCTAssertFalse(TakeSplitter.cutShort("", stoppedEarly: true))
        XCTAssertFalse(TakeSplitter.cutShort("Thursday works.\n===\nSure, Thu", stoppedEarly: false))
    }

    func testSmallModelSeparatorsEndATakeToo() {
        let ends = LocalTakeCleaner.endsTake
        XCTAssertFalse(TakeSplitter.cutShort("Thursday works.\n---\n", stoppedEarly: true, endsTake: ends))
        XCTAssertFalse(TakeSplitter.cutShort("Thursday works.\n\nVersion 2:", stoppedEarly: true, endsTake: ends))
        XCTAssertFalse(TakeSplitter.cutShort("Thursday works.\n--", stoppedEarly: true, endsTake: ends))
        XCTAssertTrue(TakeSplitter.cutShort("Thursday works.\n---\nSure", stoppedEarly: true, endsTake: ends))
        XCTAssertTrue(TakeSplitter.cutShort("Version 2: Sure", stoppedEarly: true, endsTake: ends))
    }
}
