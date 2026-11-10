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

    /// Spacing changes what gets pasted, so it's a change; only the extra space is marked.
    func testSpacingChangesAreChanges() {
        let segments = WordDiff.segments(from: "Thursday  works", to: "Thursday works")
        XCTAssertEqual(rebuilt(segments, keeping: ["removed"]), " ")
        XCTAssertEqual(rebuilt(segments, keeping: ["same", "added"]), "Thursday works")
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

/// Diff edge cases that matter for proofreading.
final class WordDiffProofreadTests: XCTestCase {
    private func changed(_ old: String, _ new: String) -> (removed: String, added: String) {
        let segments = WordDiff.segments(from: old, to: new)
        return (segments.filter { $0.kind == .removed }.map(\.text).joined(),
                segments.filter { $0.kind == .added }.map(\.text).joined())
    }

    func testAddedCommaMarksOnlyTheComma() {
        let change = changed("Thanks Dana see you then", "Thanks Dana, see you then")
        XCTAssertEqual(change.removed, "")
        XCTAssertEqual(change.added, ",")
    }

    func testChangedEndPunctuationMarksOnlyThePunctuation() {
        let change = changed("Can you send it.", "Can you send it?")
        XCTAssertEqual(change.removed, ".")
        XCTAssertEqual(change.added, "?")
    }

    func testPunctuationInsideAWordStaysWithIt() {
        XCTAssertEqual(WordDiff.fixes(from: "I dont know", to: "I don't know"), [WordDiff.Fix(removed: "dont", added: "don't")])
        XCTAssertEqual(WordDiff.fixes(from: "see x.com/a.", to: "see x.com/a.").count, 0)
    }

    func testCapitalisationIsAFix() {
        XCTAssertEqual(WordDiff.fixes(from: "see you on monday", to: "see you on Monday"),
                       [WordDiff.Fix(removed: "monday", added: "Monday")])
    }

    func testRewritesGroupIntoOneChange() {
        XCTAssertEqual(WordDiff.fixes(from: "a b c", to: "x y z"), [WordDiff.Fix(removed: "a b c", added: "x y z")])
    }

    func testLineBreakChangesAreFixes() {
        let fixes = WordDiff.fixes(from: "Hi Dana,\n\nThursday works", to: "Hi Dana, Thursday works")
        XCTAssertEqual(fixes, [WordDiff.Fix(removed: "\n\n", added: " ")])
    }

    func testEmojiAndLinksAreKept() {
        let draft = "Shipped it 🎉 notes at https://example.com/notes"
        XCTAssertTrue(WordDiff.fixes(from: draft, to: draft).isEmpty)
        XCTAssertEqual(WordDiff.fixes(from: draft, to: "Shipped it 🎉, notes at https://example.com/notes"),
                       [WordDiff.Fix(removed: "", added: ",")])
    }

    func testRebuildsTextWithPunctuationChanges() {
        let old = "ya thursday works, but i need specs.", new = "Ya, Thursday works but I need the specs."
        let segments = WordDiff.segments(from: old, to: new)
        XCTAssertEqual(segments.filter { $0.kind != .removed }.map(\.text).joined(), new)
        let words = { (text: String) in text.split(whereSeparator: \.isWhitespace) }
        XCTAssertEqual(words(segments.filter { $0.kind != .added }.map(\.text).joined()), words(old))
    }

    func testAttributedMarksAreNotColorAlone() {
        let text = WordDiff.attributed(from: "teh cat", to: "the cat")
        let removed = text.runs.first { $0.strikethroughStyle != nil }
        let added = text.runs.first { $0.underlineStyle != nil }
        XCTAssertEqual(removed.map { String(text[$0.range].characters) }, "teh")
        XCTAssertEqual(added.map { String(text[$0.range].characters) }, "the")
    }
}
