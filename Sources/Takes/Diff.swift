import SwiftUI

/// Word-level diff between the draft and a take, for the "Changes" view.
enum WordDiff {
    enum Kind { case same, added, removed }
    struct Segment { let kind: Kind; let text: String }

    /// One run of changes: what the draft had and what the take has instead. A change to spacing or line breaks
    /// alone keeps its spaces, so it's never empty.
    struct Fix: Equatable {
        let removed: String
        let added: String

        /// Only spaces or line breaks changed.
        var isSpacing: Bool { removed.allSatisfy(\.isWhitespace) && added.allSatisfy(\.isWhitespace) }
    }

    /// What a take's card shows for its changes, worked out in one pass.
    struct Changes: Sendable {
        let attributed: AttributedString
        let spoken: String
        let fixCount: Int
    }

    /// Up to this many cells (draft tokens × take tokens, after the shared start), the full table runs: about 4 MB.
    static let tableLimit = 1 << 20
    /// Steps the faster diff may take on bigger texts; past it, what's left to compare becomes one replacement.
    static let stepBudget = 20_000_000

    static func segments(from old: String, to new: String) -> [Segment] {
        segments(from: old, to: new, budget: stepBudget)
    }

    static func segments(from old: String, to new: String, budget: Int) -> [Segment] {
        // Spaces and line breaks around the text aren't compared; the take keeps its own.
        let oldCore = core(old), newCore = core(new)
        let a = tokens(String(oldCore)), b = tokens(String(newCore))
        var builder = SegmentBuilder()
        let lead = new[..<newCore.startIndex], trail = new[newCore.endIndex...]
        if !lead.isEmpty { builder.push(.same, String(lead)) }
        builder.build(a, b, script(a, b, budget: budget))
        if !trail.isEmpty { builder.push(.same, String(trail)) }
        return builder.finish()
    }

    /// The text without the spaces and line breaks around it.
    static func core(_ text: String) -> Substring {
        guard let first = text.firstIndex(where: { !$0.isWhitespace }) else { return text[text.endIndex...] }
        let last = text.lastIndex(where: { !$0.isWhitespace }) ?? first
        return text[first...last]
    }

    /// The runs of changes. Changes to spacing or line breaks count too: they change what gets pasted.
    static func fixes(from old: String, to new: String) -> [Fix] {
        fixes(in: segments(from: old, to: new))
    }

    private static func fixes(in segments: [Segment]) -> [Fix] {
        var fixes: [Fix] = []
        var removed = "", added = ""
        func close() {
            defer { removed = ""; added = "" }
            guard !removed.isEmpty || !added.isEmpty else { return }
            let fix = Fix(removed: removed.trimmingCharacters(in: .whitespacesAndNewlines),
                          added: added.trimmingCharacters(in: .whitespacesAndNewlines))
            fixes.append(fix.removed.isEmpty && fix.added.isEmpty ? Fix(removed: removed, added: added) : fix)
        }
        for segment in segments {
            switch segment.kind {
            case .same: close()
            case .removed: removed += segment.text
            case .added: added += segment.text
            }
        }
        close()
        return fixes
    }

    /// Like `fixes`, but a pure insertion or deletion borrows the next unchanged word (or the one before, at the
    /// end), so it reads on its own: "will send → send" rather than "will → ". Spacing changes are left out.
    static func readableFixes(from old: String, to new: String, budget: Int = stepBudget) -> [Fix] {
        let segments = segments(from: old, to: new, budget: budget)
        var fixes: [Fix] = []
        var removed = "", added = "", previousSame = ""
        var index = 0
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
            fixes.append(Fix(removed: r, added: a))
        }
        while index < segments.count {
            let segment = segments[index]
            switch segment.kind {
            case .same:
                close(next: segment.text)
                previousSame = segment.text
            case .removed: removed += segment.text
            case .added: added += segment.text
            }
            index += 1
        }
        close(next: "")
        return fixes
    }

    /// The marked-up take, its spoken form and its fix count from one diff, for work off the main thread.
    static func changes(from old: String, to new: String) -> Changes {
        let segments = segments(from: old, to: new)
        let fixes = fixes(in: segments)
        return Changes(attributed: attributed(segments), spoken: spoken(fixes, result: new), fixCount: fixes.count)
    }

    static func attributed(from old: String, to new: String) -> AttributedString {
        attributed(segments(from: old, to: new))
    }

    private static func attributed(_ segments: [Segment]) -> AttributedString {
        var output = AttributedString()
        var previous: Kind?
        for segment in segments {
            // "~~hey dana~~Hey Dana" would run together; a thin space keeps the two words apart on screen.
            if previous == .removed, segment.kind == .added, output.characters.last?.isWhitespace == false {
                output += AttributedString("\u{2009}")
            }
            previous = segment.kind
            let text = segment.text
            if segment.kind != .same, text.allSatisfy(\.isWhitespace) {
                // A changed space or line break would be invisible, so it shows as ␣ or ↵. An added line break
                // still breaks the line after its mark.
                for character in text {
                    var mark = AttributedString(character.isNewline ? "↵" : character == "\t" ? "⇥" : "␣")
                    style(&mark, segment.kind)
                    output += mark
                    if character.isNewline, segment.kind == .added { output += AttributedString(String(character)) }
                }
                continue
            }
            // Spaces at the edges of a change stay unmarked, so marks hug the words.
            let lead = text.prefix { $0.isWhitespace }
            let rest = text.dropFirst(lead.count)
            let trail = segment.kind == .same ? "" : String(rest.reversed().prefix { $0.isWhitespace }.reversed())
            let core = String(rest.dropLast(trail.count))
            var piece = AttributedString(core)
            style(&piece, segment.kind)
            output += AttributedString(String(lead)) + piece + AttributedString(trail)
        }
        return output
    }

    /// Not by color alone: removed text is struck through, added text is underlined.
    private static func style(_ piece: inout AttributedString, _ kind: Kind) {
        switch kind {
        case .same: break
        case .added:
            piece.foregroundColor = Theme.doText
            piece.backgroundColor = Theme.doFill
            piece.underlineStyle = .single
        case .removed:
            piece.foregroundColor = Theme.avoidText
            piece.backgroundColor = Theme.avoidFill
            piece.strikethroughStyle = .single
        }
    }

    /// What VoiceOver reads for the "Changes" view: each change in words, then the new text.
    static func spoken(from old: String, to new: String) -> String {
        spoken(fixes(from: old, to: new), result: new)
    }

    private static func spoken(_ fixes: [Fix], result new: String) -> String {
        guard !fixes.isEmpty else { return String(localized: "No changes. \(new)") }
        let changes = fixes.map { fix -> String in
            if fix.isSpacing {
                let breaks = fix.removed.contains(where: \.isNewline) || fix.added.contains(where: \.isNewline)
                return breaks ? String(localized: "changed line breaks") : String(localized: "changed spacing")
            }
            if fix.removed.isEmpty { return String(localized: "added \(fix.added)") }
            if fix.added.isEmpty { return String(localized: "removed \(fix.removed)") }
            if fix.removed.lowercased() == fix.added.lowercased() { return String(localized: "capitalised \(fix.added)") }
            return String(localized: "\(fix.removed) changed to \(fix.added)")
        }
        let list = changes.joined(separator: "; ")
        return fixes.count == 1 ? String(localized: "1 change: \(list). Result: \(new)")
            : String(localized: "\(fixes.count) changes: \(list). Result: \(new)")
    }

    // MARK: Tokens

    /// Words, punctuation and runs of spaces as separate tokens, so joining them rebuilds the text. Punctuation at
    /// the start or end of a word is its own token, so an added comma marks only the comma. Punctuation inside a
    /// word ("don't", "x.com/a") stays part of it.
    static func tokens(_ text: String) -> [String] {
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

    // MARK: Edit script

    /// Tokens as numbers, in place.
    private typealias Tokens = UnsafeBufferPointer<Int32>

    /// One entry per token: `.same` for a token both texts keep, `.removed` for one only the draft has, `.added`
    /// for one only the take has. Tokens compare exactly, so capitalisation ("i" → "I") and spacing are changes.
    static func script(_ a: [String], _ b: [String], budget: Int = stepBudget, tableLimit: Int = tableLimit) -> [Kind] {
        // Tokens as numbers, so comparing them is cheap.
        var ids: [String: Int32] = [:]
        func id(_ token: String) -> Int32 {
            if let id = ids[token] { return id }
            let id = Int32(ids.count)
            ids[token] = id
            return id
        }
        let x = a.map(id), y = b.map(id)
        var ops: [Kind] = []
        ops.reserveCapacity(x.count + y.count)
        var start = 0
        while start < x.count, start < y.count, x[start] == y[start] { start += 1 }
        ops.append(contentsOf: repeatElement(.same, count: start))
        if (x.count - start + 1) * (y.count - start + 1) <= tableLimit {
            tableScript(Array(x[start...]), Array(y[start...]), into: &ops)
        } else {
            var budget = budget
            x.withUnsafeBufferPointer { x in
                y.withUnsafeBufferPointer { y in
                    myers(x, start..<x.count, y, start..<y.count, budget: &budget, into: &ops)
                }
            }
        }
        return ops
    }

    /// The longest common subsequence table, walked from the start, preferring removals: the diff the panel has
    /// always shown. Quadratic, so only for inputs under `tableLimit`.
    private static func tableScript(_ a: [Int32], _ b: [Int32], into ops: inout [Kind]) {
        let n = a.count, m = b.count, width = m + 1
        var lcs = [Int32](repeating: 0, count: (n + 1) * width)
        lcs.withUnsafeMutableBufferPointer { table in
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    let here = i * width + j, below = here + width
                    table[here] = a[i] == b[j] ? table[below + 1] + 1 : max(table[below], table[here + 1])
                }
            }
        }
        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] {
                ops.append(.same); i += 1; j += 1
            } else if j >= m || (i < n && lcs[(i + 1) * width + j] >= lcs[i * width + j + 1]) {
                ops.append(.removed); i += 1
            } else {
                ops.append(.added); j += 1
            }
        }
    }

    /// Myers' diff in linear space: the middle snake splits the texts, and each half is diffed the same way. Time
    /// grows with the length times the number of changed tokens, so a long text with a few fixes stays fast. Once
    /// `budget` runs out, what's left to compare becomes one replacement.
    private static func myers(_ a: Tokens, _ aRange: Range<Int>, _ b: Tokens, _ bRange: Range<Int>, budget: inout Int, into ops: inout [Kind]) {
        var aLow = aRange.lowerBound, aHigh = aRange.upperBound, bLow = bRange.lowerBound, bHigh = bRange.upperBound
        let start = aLow
        while aLow < aHigh, bLow < bHigh, a[aLow] == b[bLow] { aLow += 1; bLow += 1 }
        ops.append(contentsOf: repeatElement(.same, count: aLow - start))
        let end = aHigh
        while aLow < aHigh, bLow < bHigh, a[aHigh - 1] == b[bHigh - 1] { aHigh -= 1; bHigh -= 1 }
        let n = aHigh - aLow, m = bHigh - bLow
        if n > 0, m > 0, let split = middleSnake(a, aLow, n, b, bLow, m, budget: &budget), split.x + split.y > 0, split.x + split.y < n + m {
            myers(a, aLow..<aLow + split.x, b, bLow..<bLow + split.y, budget: &budget, into: &ops)
            myers(a, aLow + split.x..<aHigh, b, bLow + split.y..<bHigh, budget: &budget, into: &ops)
        } else {
            ops.append(contentsOf: repeatElement(.removed, count: n))
            ops.append(contentsOf: repeatElement(.added, count: m))
        }
        ops.append(contentsOf: repeatElement(.same, count: end - aHigh))
    }

    /// Where an optimal path crosses the middle, found by searching from both ends at once. Nil once the budget
    /// runs out.
    private static func middleSnake(_ a: Tokens, _ aLow: Int, _ n: Int, _ b: Tokens, _ bLow: Int, _ m: Int, budget: inout Int) -> (x: Int, y: Int)? {
        guard budget > 0 else { return nil }
        let maxD = (n + m + 1) / 2, offset = maxD, length = 2 * maxD + 2
        var forward = [Int](repeating: -1, count: length), backward = [Int](repeating: -1, count: length)
        forward[offset + 1] = 0
        backward[offset + 1] = 0
        let delta = n - m
        // With an odd difference in length the paths meet on a forward step, otherwise on a backward one.
        let meetForward = delta % 2 != 0
        var forwardStart = 0, forwardEnd = 0, backwardStart = 0, backwardEnd = 0
        for d in 0..<maxD {
            guard budget > 0 else { return nil }
            var k = -d + forwardStart
            while k <= d - forwardEnd {
                let index = offset + k
                var x = k == -d || (k != d && forward[index - 1] < forward[index + 1]) ? forward[index + 1] : forward[index - 1] + 1
                var y = x - k
                let from = x
                while x < n, y < m, a[aLow + x] == b[bLow + y] { x += 1; y += 1 }
                budget -= 1 + x - from
                forward[index] = x
                if x > n {
                    forwardEnd += 2
                } else if y > m {
                    forwardStart += 2
                } else if meetForward {
                    let other = offset + delta - k
                    if other >= 0, other < length, backward[other] != -1, x >= n - backward[other] { return (x, y) }
                }
                k += 2
            }
            k = -d + backwardStart
            while k <= d - backwardEnd {
                let index = offset + k
                var x = k == -d || (k != d && backward[index - 1] < backward[index + 1]) ? backward[index + 1] : backward[index - 1] + 1
                var y = x - k
                let from = x
                while x < n, y < m, a[aLow + n - x - 1] == b[bLow + m - y - 1] { x += 1; y += 1 }
                budget -= 1 + x - from
                backward[index] = x
                if x > n {
                    backwardEnd += 2
                } else if y > m {
                    backwardStart += 2
                } else if !meetForward {
                    let other = offset + delta - k
                    if other >= 0, other < length, forward[other] != -1 {
                        let forwardX = forward[other]
                        if forwardX >= n - x { return (forwardX, forwardX - (other - offset)) }
                    }
                }
                k += 2
            }
        }
        return nil
    }
}

/// Turns an edit script into runs: unchanged text, and hunks of removed and added tokens between them.
private struct SegmentBuilder {
    typealias Segment = WordDiff.Segment
    private var result: [Segment] = []
    /// The last run, still growing: appending to it rather than to a finished segment keeps long texts linear.
    private var kind: WordDiff.Kind?
    private var text = ""
    private var removed = "", added = ""
    /// Whether the hunk has words, not only spaces.
    private var removedWords = false, addedWords = false

    mutating func build(_ a: [String], _ b: [String], _ script: [WordDiff.Kind]) {
        var i = 0, j = 0
        for op in script {
            switch op {
            case .same:
                if removedWords, addedWords, isSpace(a[i]) {
                    // The space after a changed word belongs to the change, so neighbouring changes join into one
                    // ("~~a b c~~ x y z" rather than "~~a~~x ~~b~~y ~~c~~z").
                    removed += a[i]; added += b[j]
                } else {
                    flush()
                    push(.same, b[j])
                }
                i += 1; j += 1
            case .removed:
                removed += a[i]
                if !isSpace(a[i]) { removedWords = true }
                i += 1
            case .added:
                added += b[j]
                if !isSpace(b[j]) { addedWords = true }
                j += 1
            }
        }
        flush()
    }

    private mutating func flush() {
        defer { removed = ""; added = ""; removedWords = false; addedWords = false }
        if removed.isEmpty != added.isEmpty {
            // A pure insertion or deletion that starts with a space ("works" → "works for me") reads better with
            // the space left unchanged before it.
            let change = removed.isEmpty ? added : removed
            let lead = String(change.prefix { $0.isWhitespace })
            if !lead.isEmpty, lead.count < change.count {
                push(.same, lead)
                if removed.isEmpty { added.removeFirst(lead.count) } else { removed.removeFirst(lead.count) }
            }
        } else if !removed.isEmpty, !removedWords, !addedWords {
            // Spacing alone: only the spaces or line breaks that differ are marked ("  " → " " removes one space).
            let old = Array(removed), new = Array(added)
            var head = 0, tail = 0
            while head < old.count, head < new.count, old[head] == new[head] { head += 1 }
            while tail < old.count - head, tail < new.count - head, old[old.count - 1 - tail] == new[new.count - 1 - tail] { tail += 1 }
            if head > 0 { push(.same, String(new[..<head])) }
            if old.count - tail > head { push(.removed, String(old[head..<old.count - tail])) }
            if new.count - tail > head { push(.added, String(new[head..<new.count - tail])) }
            if tail > 0 { push(.same, String(new[(new.count - tail)...])) }
            return
        }
        if !removed.isEmpty { push(.removed, removed) }
        if !added.isEmpty { push(.added, added) }
    }

    mutating func push(_ kind: WordDiff.Kind, _ text: String) {
        if self.kind == kind {
            self.text += text
        } else {
            if let last = self.kind { result.append(Segment(kind: last, text: self.text)) }
            self.kind = kind
            self.text = text
        }
    }

    mutating func finish() -> [Segment] {
        if let last = kind { result.append(Segment(kind: last, text: text)) }
        kind = nil
        text = ""
        return result
    }

    private func isSpace(_ token: String) -> Bool { token.first?.isWhitespace == true }
}
