import SwiftUI

/// Word-level diff between the draft and a take, for the "Changes" view.
enum WordDiff {
    enum Kind { case same, added, removed }
    struct Segment { let kind: Kind; let text: String }

    /// One run of changes: what the draft had and what the take has instead.
    struct Fix: Equatable { let removed: String; let added: String }

    static func segments(from old: String, to new: String) -> [Segment] {
        let a = tokens(old), b = tokens(new)

        // Longest common subsequence over tokens.
        var lcs = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lcs[i][j] = key(a[i]) == key(b[j]) ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }

        // Walk the table into runs: unchanged text, and hunks of removed/added tokens between them.
        var result: [Segment] = []
        var removed = "", added = ""
        func flush() {
            // A pure insertion or deletion that starts with a space ("works" → "works for me") reads better with
            // the space left unchanged before it.
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
        func push(_ kind: Kind, _ text: String) {
            if let last = result.last, last.kind == kind {
                result[result.count - 1] = Segment(kind: kind, text: last.text + text)
            } else {
                result.append(Segment(kind: kind, text: text))
            }
        }
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, key(a[i]) == key(b[j]) {
                let replacing = removed.contains { !$0.isWhitespace } && added.contains { !$0.isWhitespace }
                if replacing, isSpace(a[i]) {
                    // The space after a changed word belongs to the change, so neighbouring changes join into one
                    // ("~~a b c~~ x y z" rather than "~~a~~x ~~b~~y ~~c~~z").
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

    /// The runs of changes, ignoring ones that only change spacing or line breaks.
    static func fixes(from old: String, to new: String) -> [Fix] {
        var fixes: [Fix] = []
        var removed = "", added = ""
        func close() {
            let fix = Fix(removed: removed.trimmingCharacters(in: .whitespacesAndNewlines),
                          added: added.trimmingCharacters(in: .whitespacesAndNewlines))
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

    /// Like `fixes`, but a pure insertion or deletion borrows the next unchanged word (or the one before, at the
    /// end), so it reads on its own: "will send → send" rather than "will → ".
    static func readableFixes(from old: String, to new: String) -> [Fix] {
        let segments = segments(from: old, to: new)
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

    static func attributed(from old: String, to new: String) -> AttributedString {
        var output = AttributedString()
        var previous: Kind?
        for segment in segments(from: old, to: new) {
            // "~~hey dana~~Hey Dana" would run together; a thin space keeps the two words apart on screen.
            if previous == .removed, segment.kind == .added, output.characters.last?.isWhitespace == false {
                output += AttributedString("\u{2009}")
            }
            previous = segment.kind
            // Spaces at the edges of a change stay unmarked, so marks hug the words.
            let text = segment.text
            let lead = text.prefix { $0.isWhitespace }
            let rest = text.dropFirst(lead.count)
            let trail = segment.kind == .same ? "" : String(rest.reversed().prefix { $0.isWhitespace }.reversed())
            let core = String(rest.dropLast(trail.count))
            var piece = AttributedString(core)
            // Not by color alone: removed text is struck through, added text is underlined.
            switch segment.kind {
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
            output += AttributedString(String(lead)) + piece + AttributedString(trail)
        }
        return output
    }

    /// What VoiceOver reads for the "Changes" view: each change in words, then the new text.
    static func spoken(from old: String, to new: String) -> String {
        let fixes = fixes(from: old, to: new)
        guard !fixes.isEmpty else { return String(localized: "No changes. \(new)") }
        let changes = fixes.map { fix -> String in
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

    /// Case-sensitive: capitalisation fixes ("i" → "I") are real changes, especially when proofreading. Spacing
    /// isn't compared, only whether a run of spaces holds line breaks.
    private static func key(_ token: String) -> String {
        guard isSpace(token) else { return token }
        let breaks = token.filter(\.isNewline).count
        return breaks == 0 ? " " : String(repeating: "\n", count: breaks)
    }
}
