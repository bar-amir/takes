import XCTest
@testable import Takes

final class WordDiffTests: XCTestCase {
    private func rebuilt(_ segments: [WordDiff.Segment], keeping kinds: Set<String>) -> String {
        segments.filter { kinds.contains("\($0.kind)") }.map(\.text).joined()
    }

    func testIdenticalTextIsAllSame() {
        let segments = WordDiff.segments(from: "Thursday works for me", to: "Thursday works for me")
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.kind, .same)
    }

    func testRebuildsBothVersions() {
        let old = "ya thursday works but i need the specs"
        let new = "Sure, Thursday works. I need the specs by Wednesday"
        let segments = WordDiff.segments(from: old, to: new)
        // Spacing between words isn't compared, so check the words.
        let words = { (text: String) in text.split(whereSeparator: \.isWhitespace) }
        XCTAssertEqual(words(rebuilt(segments, keeping: ["same", "removed"])), words(old))
        XCTAssertEqual(words(rebuilt(segments, keeping: ["same", "added"])), words(new))
    }

    func testCapitalisationFixesShowAsChanges() {
        let segments = WordDiff.segments(from: "i think thursday works", to: "I think Thursday works")
        XCTAssertEqual(rebuilt(segments, keeping: ["removed"]), "i thursday ")
        XCTAssertEqual(rebuilt(segments, keeping: ["added"]), "I Thursday ")
    }

    func testSpacingChangesAloneAreNotChanges() {
        let segments = WordDiff.segments(from: "Thursday  works", to: "Thursday works")
        XCTAssertTrue(segments.allSatisfy { $0.kind == .same })
    }

    func testEmptyOldTextIsAllAdded() {
        let segments = WordDiff.segments(from: "", to: "Hello there")
        XCTAssertEqual(segments.map(\.kind), [.added])
    }

    func testHebrewIsDiffedByWord() {
        let segments = WordDiff.segments(from: "יום חמישי מתאים", to: "יום חמישי מתאים לי")
        XCTAssertEqual(rebuilt(segments, keeping: ["added"]), "לי")
    }
}
