import XCTest
@testable import Takes

/// The word diff after the audit: same results as before on everyday drafts, bounded time on long ones, and
/// spacing changes that count.
final class WordDiffScaleTests: XCTestCase {
    // MARK: Same results as before

    func testEverydayDraftsDiffAsBefore() {
        let pairs = [
            ("ya thursday works but i need the specs", "Sure, Thursday works. I need the specs by Wednesday"),
            ("i think teh specs are due wed", "I think the specs are due Wed."),
            ("If you will send me the file until tomorrow, I will check it.", "If you send me the file by tomorrow, I'll check it."),
            ("hey dana, i think teh specs are due wed but lets confirm", "Hey Dana, I think the specs are due Wed, but let's confirm."),
            ("make you a feedback", "give you feedback"),
            ("Thanks Dana see you then", "Thanks Dana, see you then"),
            ("Can you send it.", "Can you send it?"),
            ("a b c", "x y z"),
            ("works", "works for me"),
            ("works for me", "works"),
            ("Shipped it 🎉 notes at https://example.com/notes", "Shipped it 🎉, notes at https://example.com/notes"),
            ("Hi Dana,\nThursday works", "Hi Dana,\nThursday works for me.\nThanks"),
            ("יום חמישי מתאים", "יום חמישי מתאים לי"),
            ("a a a b", "a b a b a"),
            ("", "Hello there"),
            ("Hello there", ""),
        ]
        for (old, new) in pairs {
            let segments = describe(WordDiff.segments(from: old, to: new))
            XCTAssertEqual(segments, describe(LegacyWordDiff.segments(from: old, to: new)), "\(old) → \(new)")
            XCTAssertEqual(WordDiff.readableFixes(from: old, to: new), LegacyWordDiff.readableFixes(from: old, to: new))
            XCTAssertEqual(WordDiff.fixes(from: old, to: new), LegacyWordDiff.fixes(from: old, to: new))
        }
    }

    func testRandomEditsDiffAsBefore() {
        var random = SeededRandom(seed: 7)
        for _ in 0..<400 {
            let old = Self.words(random.next(in: 1...40), &random).joined(separator: " ")
            let new = Self.edited(old, rate: 0.3, &random)
            let segments = describe(WordDiff.segments(from: old, to: new))
            XCTAssertEqual(segments, describe(LegacyWordDiff.segments(from: old, to: new)), "\(old) → \(new)")
            XCTAssertEqual(WordDiff.readableFixes(from: old, to: new), LegacyWordDiff.readableFixes(from: old, to: new))
        }
    }

    // MARK: The faster diff on long texts

    /// Myers' diff, used past the table's size, must find as many unchanged tokens as the table does, and its
    /// script must rebuild both texts.
    func testLongTextDiffIsAsGoodAsTheTable() {
        var random = SeededRandom(seed: 11)
        for round in 0..<300 {
            let a: [String], b: [String]
            if round % 2 == 0 {
                // Few distinct tokens: many equally good answers, the hard case for the search from both ends.
                a = (0..<random.next(in: 0...60)).map { _ in ["a", "b", "c", " "][random.next(in: 0...3)] }
                b = (0..<random.next(in: 0...60)).map { _ in ["a", "b", "c", " "][random.next(in: 0...3)] }
            } else {
                a = WordDiff.tokens(Self.words(random.next(in: 1...80), &random).joined(separator: " "))
                b = WordDiff.tokens(Self.edited(a.joined(), rate: 0.25, &random))
            }
            let table = WordDiff.script(a, b, tableLimit: .max)
            let myers = WordDiff.script(a, b, tableLimit: 0)
            assertRebuilds(myers, a, b)
            XCTAssertEqual(myers.filter { $0 == .same }.count, table.filter { $0 == .same }.count, "\(a) → \(b)")
        }
    }

    /// Past the step budget, the changed middle becomes one replacement instead of a long wait.
    func testOverBudgetTheChangedMiddleIsOneReplacement() {
        var random = SeededRandom(seed: 3)
        let shared = Self.words(1_500, &random).joined(separator: " ")
        let old = "First " + shared + " last.", new = "Opening " + Self.edited(shared, rate: 0.3, &random) + " ending."
        let segments = WordDiff.segments(from: old, to: new, budget: 0)
        XCTAssertEqual(segments.map(\.kind), [.removed, .added, .same])
        XCTAssertEqual(segments.filter { $0.kind != .removed }.map(\.text).joined(), new)
        XCTAssertEqual(segments.filter { $0.kind != .added }.map(\.text).joined(), old)
        XCTAssertFalse(Proofread.nothingToFix(draft: old, takes: [new]))
    }

    func testTenThousandCharactersFinishQuickly() {
        assertQuick(characters: 10_000, within: 5)
    }

    func testThirtyThousandCharactersFinishQuickly() {
        assertQuick(characters: 30_000, within: 10)
    }

    /// A proofread of a long text, a rewrite of it and an unrelated text, each diffed the way the panel does.
    private func assertQuick(characters: Int, within seconds: TimeInterval) {
        var random = SeededRandom(seed: UInt64(characters))
        var draft = ""
        while draft.count < characters { draft += Self.words(12, &random).joined(separator: " ") + ".\n" }
        var other = ""
        while other.count < characters { other += Self.words(12, &random).joined(separator: " ") + ".\n" }
        let proofread = Self.edited(draft, rate: 0.03, &random), rewrite = Self.edited(draft, rate: 0.4, &random)
        for (name, take) in [("proofread", proofread), ("rewrite", rewrite), ("unrelated", other)] {
            let start = Date()
            let changes = WordDiff.changes(from: draft, to: take)
            let elapsed = Date().timeIntervalSince(start)
            XCTAssertLessThan(elapsed, seconds, "\(name), \(characters) characters")
            XCTAssertGreaterThan(changes.fixCount, 0, name)
            XCTAssertFalse(changes.attributed.characters.isEmpty, name)
            // A deleted word's leading space stays unmarked ("for ~~it~~."), so compare without spaces.
            let segments = WordDiff.segments(from: draft, to: take)
            let letters = { (text: String) in text.filter { !$0.isWhitespace } }
            XCTAssertEqual(letters(segments.filter { $0.kind != .removed }.map(\.text).joined()), letters(take), name)
            XCTAssertEqual(letters(segments.filter { $0.kind != .added }.map(\.text).joined()), letters(draft), name)
        }
        // A proofread with a few fixes stays a word-level diff, not one big replacement.
        let fixes = WordDiff.fixes(from: draft, to: draft.replacingOccurrences(of: "teh", with: "the"))
        XCTAssertGreaterThan(fixes.count, 5)
        XCTAssertTrue(fixes.allSatisfy { $0.removed.hasPrefix("teh") && $0.added.hasPrefix("the") }, "\(fixes.prefix(3))")
    }

    /// The coach invitation diffs every take on the main thread when a run finishes, on a smaller budget.
    func testCoachAnalysisOfALongDraftIsQuick() {
        var random = SeededRandom(seed: 21)
        let draft = Self.words(6_000, &random).joined(separator: " ")
        let takes = (0..<5).map { _ in Self.words(6_000, &random).joined(separator: " ") }
        let start = Date()
        _ = FixHeuristic.analyse(draft: draft, takes: takes)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    // MARK: Spacing counts

    func testAMovedSpaceIsAFix() {
        let draft = "Thanks ,see you then", take = "Thanks, see you then"
        XCTAssertFalse(Proofread.nothingToFix(draft: draft, takes: [take]))
        let fixes = WordDiff.fixes(from: draft, to: take)
        XCTAssertEqual(fixes.count, 2)
        XCTAssertTrue(fixes.allSatisfy(\.isSpacing))
        XCTAssertEqual(WordDiff.spoken(from: draft, to: take), "2 changes: changed spacing; changed spacing. Result: \(take)")
    }

    func testAnExtraSpaceIsOneFix() {
        XCTAssertEqual(WordDiff.fixes(from: "Thursday  works", to: "Thursday works"), [WordDiff.Fix(removed: " ", added: "")])
        let segments = describe(WordDiff.segments(from: "Thursday  works", to: "Thursday works"))
        XCTAssertEqual(segments, ["same:Thursday ", "removed: ", "same:works"])
    }

    func testJoinedLinesAreAFix() {
        let draft = "Hi Dana,\n\nThursday works", take = "Hi Dana, Thursday works"
        XCTAssertEqual(WordDiff.fixes(from: draft, to: take), [WordDiff.Fix(removed: "\n\n", added: " ")])
        XCTAssertEqual(WordDiff.spoken(from: draft, to: take), "1 change: changed line breaks. Result: \(take)")
    }

    /// Spacing changes would be invisible, so they show as marks: struck ␣ or ↵ for removed, underlined for added.
    func testSpacingChangesAreVisible() {
        let removed = WordDiff.attributed(from: "Thanks ,see you", to: "Thanks, see you")
        let struck = removed.runs.filter { $0.strikethroughStyle != nil }.map { String(removed[$0.range].characters) }
        let underlined = removed.runs.filter { $0.underlineStyle != nil }.map { String(removed[$0.range].characters) }
        XCTAssertEqual(struck, ["␣"])
        XCTAssertEqual(underlined, ["␣"])

        let lines = WordDiff.attributed(from: "Hi Dana, Thursday works", to: "Hi Dana,\nThursday works")
        let added = lines.runs.filter { $0.underlineStyle != nil }.map { String(lines[$0.range].characters) }
        XCTAssertEqual(added, ["↵"])
        XCTAssertTrue(String(lines.characters).contains("↵\nThursday"), "an added line break still breaks the line")
    }

    func testSpacesAroundTheTextDontCount() {
        let draft = "Thursday works for me."
        XCTAssertTrue(WordDiff.fixes(from: draft, to: draft + "\n").isEmpty)
        XCTAssertTrue(WordDiff.fixes(from: "  " + draft, to: draft).isEmpty)
        XCTAssertEqual(WordDiff.segments(from: draft, to: "\n" + draft + " ").map(\.text).joined(), "\n" + draft + " ")
    }

    /// "No mistakes found" exactly when the diff has nothing to show.
    func testNothingToFixMatchesTheDiff() {
        let draft = "Thursday works for me.\nSee you then"
        let takes = [
            draft, draft + "\n", " " + draft, "Thursday  works for me.\nSee you then", "Thursday works for me. See you then",
            "Thursday works for me.\n\nSee you then", "Thursday works for me.\nSee you then.", "thursday works for me.\nSee you then",
            "Thursday works for me.\tSee you then", "",
        ]
        for take in takes {
            let unchanged = Proofread.nothingToFix(draft: draft, takes: [take])
            XCTAssertEqual(unchanged, WordDiff.fixes(from: draft, to: take).isEmpty, take.debugDescription)
        }
        var random = SeededRandom(seed: 5)
        for _ in 0..<200 {
            let old = Self.words(random.next(in: 1...12), &random).joined(separator: random.next(in: 0...3) == 0 ? "  " : " ")
            let new = random.next(in: 0...2) == 0 ? old : Self.edited(old, rate: 0.2, &random)
            XCTAssertEqual(Proofread.nothingToFix(draft: old, takes: [new]), WordDiff.fixes(from: old, to: new).isEmpty)
        }
    }

    // MARK: Helpers

    private func describe(_ segments: [WordDiff.Segment]) -> [String] { segments.map { "\($0.kind):\($0.text)" } }

    private func assertRebuilds(_ script: [WordDiff.Kind], _ a: [String], _ b: [String], line: UInt = #line) {
        var i = 0, j = 0
        for op in script {
            switch op {
            case .same:
                guard i < a.count, j < b.count, a[i] == b[j] else { return XCTFail("bad match at \(i), \(j)", line: line) }
                i += 1; j += 1
            case .removed: i += 1
            case .added: j += 1
            }
        }
        XCTAssertEqual(i, a.count, line: line)
        XCTAssertEqual(j, b.count, line: line)
    }

    private static let vocabulary = [
        "i", "I", "think", "teh", "the", "specs", "are", "due", "wed", "Wed,", "but", "lets", "let's", "confirm", "with",
        "qa", "QA", "before", "we", "promise", "anything.", "Thursday", "works", "for", "me.", "send", "file", "by",
        "tomorrow", "until", "dont", "don't", "x.com/a", "🎉", "(see", "notes)", "a", "an", "and", "or", "it", "is",
        "יום", "мы", "feedback", "review", "Dana", "hey", "Hey", "\"quoted\"", "—", "3pm", "ok?",
    ]

    private static func words(_ count: Int, _ random: inout SeededRandom) -> [String] {
        (0..<count).map { _ in vocabulary[random.next(in: 0...(vocabulary.count - 1))] }
    }

    /// Replaces, drops, adds or recapitalises about `rate` of the words, keeping single spaces and line breaks.
    private static func edited(_ text: String, rate: Double, _ random: inout SeededRandom) -> String {
        let lines = text.components(separatedBy: "\n")
        return lines.map { line in
            var out: [String] = []
            for word in line.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
                guard random.unit() < rate else { out.append(word); continue }
                switch random.next(in: 0...3) {
                case 0: out.append(vocabulary[random.next(in: 0...(vocabulary.count - 1))])
                case 1: break
                case 2: out.append(word); out.append(vocabulary[random.next(in: 0...(vocabulary.count - 1))])
                default: out.append(word.prefix(1).uppercased() + word.dropFirst())
                }
            }
            return out.joined(separator: " ")
        }.joined(separator: "\n")
    }
}

/// A small fixed-seed generator, so the random cases are the same on every run.
private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

/// The word diff as it was before the audit (full table, spacing compared loosely), kept to check that everyday
/// results haven't changed.
private enum LegacyWordDiff {
    static func segments(from old: String, to new: String) -> [WordDiff.Segment] {
        let a = tokens(old), b = tokens(new)
        var lcs = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lcs[i][j] = key(a[i]) == key(b[j]) ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var result: [WordDiff.Segment] = []
        var removed = "", added = ""
        func flush() {
            if removed.isEmpty != added.isEmpty {
                let change = removed.isEmpty ? added : removed
                let lead = String(change.prefix { $0.isWhitespace })
                if !lead.isEmpty, lead.count < change.count {
                    push(.same, lead)
                    if removed.isEmpty { added.removeFirst(lead.count) } else { removed.removeFirst(lead.count) }
                }
            }
            if !removed.isEmpty { push(.removed, removed) }
            if !added.isEmpty { push(.added, added) }
            removed = ""; added = ""
        }
        func push(_ kind: WordDiff.Kind, _ text: String) {
            if let last = result.last, last.kind == kind {
                result[result.count - 1] = WordDiff.Segment(kind: kind, text: last.text + text)
            } else {
                result.append(WordDiff.Segment(kind: kind, text: text))
            }
        }
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, key(a[i]) == key(b[j]) {
                let replacing = removed.contains { !$0.isWhitespace } && added.contains { !$0.isWhitespace }
                if replacing, isSpace(a[i]) {
                    removed += a[i]; added += b[j]
                } else {
                    flush()
                    push(.same, b[j])
                }
                i += 1; j += 1
            } else if j >= b.count || (i < a.count && lcs[i + 1][j] >= lcs[i][j + 1]) {
                removed += a[i]; i += 1
            } else {
                added += b[j]; j += 1
            }
        }
        flush()
        return result
    }

    static func fixes(from old: String, to new: String) -> [WordDiff.Fix] {
        var fixes: [WordDiff.Fix] = []
        var removed = "", added = ""
        func close() {
            let r = removed.trimmingCharacters(in: .whitespacesAndNewlines), a = added.trimmingCharacters(in: .whitespacesAndNewlines)
            let fix = WordDiff.Fix(removed: r, added: a)
            if !fix.removed.isEmpty || !fix.added.isEmpty { fixes.append(fix) }
            removed = ""; added = ""
        }
        for segment in segments(from: old, to: new) {
            switch segment.kind {
            case .same: close()
            case .removed: removed += segment.text
            case .added: added += segment.text
            }
        }
        close()
        return fixes
    }

    static func readableFixes(from old: String, to new: String) -> [WordDiff.Fix] {
        let segments = segments(from: old, to: new)
        var fixes: [WordDiff.Fix] = []
        var removed = "", added = "", previousSame = ""
        func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        func close(next: String) {
            defer { removed = ""; added = "" }
            var r = trimmed(removed), a = trimmed(added)
            guard !r.isEmpty || !a.isEmpty else { return }
            if r.isEmpty || a.isEmpty {
                let after = next.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
                let before = previousSame.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
                if !after.isEmpty, after.first?.isLetter == true || after.first?.isNumber == true {
                    r = trimmed(r + " " + after); a = trimmed(a + " " + after)
                } else if !before.isEmpty {
                    r = trimmed(before + " " + r); a = trimmed(before + " " + a)
                }
            }
            fixes.append(WordDiff.Fix(removed: r, added: a))
        }
        for segment in segments {
            switch segment.kind {
            case .same:
                close(next: segment.text)
                previousSame = segment.text
            case .removed: removed += segment.text
            case .added: added += segment.text
            }
        }
        close(next: "")
        return fixes
    }

    private static func tokens(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inSpace = false
        func closeWord() {
            guard !current.isEmpty else { return }
            let lead = current.prefix { $0.isPunctuation }
            let rest = current.dropFirst(lead.count)
            let trail = String(rest.reversed().prefix { $0.isPunctuation }.reversed())
            let core = rest.dropLast(trail.count)
            for piece in [String(lead), String(core), trail] where !piece.isEmpty { result.append(piece) }
            current = ""
        }
        for character in text {
            if character.isWhitespace != inSpace {
                if inSpace { result.append(current); current = "" } else { closeWord() }
                inSpace = character.isWhitespace
            }
            current.append(character)
        }
        if inSpace { if !current.isEmpty { result.append(current) } } else { closeWord() }
        return result
    }

    private static func isSpace(_ token: String) -> Bool { token.first?.isWhitespace == true }

    private static func key(_ token: String) -> String {
        guard isSpace(token) else { return token }
        let breaks = token.filter(\.isNewline).count
        return breaks == 0 ? " " : String(repeating: "\n", count: breaks)
    }
}
