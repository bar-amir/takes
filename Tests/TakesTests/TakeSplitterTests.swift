import XCTest
@testable import Takes

final class TakeSplitterTests: XCTestCase {
    func testSplitsOnSeparatorLines() {
        let text = "First take.\n===\nSecond take.\n===\nThird take."
        XCTAssertEqual(TakeSplitter.split(text, streaming: false), ["First take.", "Second take.", "Third take."])
    }

    func testKeepsMultiLineTakes() {
        let text = "Hi team,\n\nThursday works.\n===\nThursday is fine."
        XCTAssertEqual(TakeSplitter.split(text, streaming: false), ["Hi team,\n\nThursday works.", "Thursday is fine."])
    }

    func testTolerantOfSpacesAroundSeparator() {
        XCTAssertEqual(TakeSplitter.split("One\n  ===  \nTwo", streaming: false), ["One", "Two"])
    }

    func testDropsEmptyTakes() {
        XCTAssertEqual(TakeSplitter.split("===\nOnly one\n===\n", streaming: false), ["Only one"])
    }

    func testHalfWrittenSeparatorIsHiddenWhileStreaming() {
        XCTAssertEqual(TakeSplitter.split("First take.\n==", streaming: true), ["First take."])
    }

    func testEqualsSignsInsideTextAreKept() {
        XCTAssertEqual(TakeSplitter.split("a == b, right?", streaming: true), ["a == b, right?"])
    }

    func testSingleTakeWithoutSeparator() {
        XCTAssertEqual(TakeSplitter.split("Just one version.", streaming: false), ["Just one version."])
    }
}
