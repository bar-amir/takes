import SwiftUI

/// Word-level diff between the draft and a take, for the "Changes" view.
enum WordDiff {
    enum Kind { case same, added, removed }
    struct Segment { let kind: Kind; let text: String }

    static func segments(from old: String, to new: String) -> [Segment] {
        let a = words(old), b = words(new)
        let key = { (word: String) in word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        // Longest common subsequence over words.
        var lcs = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lcs[i][j] = key(a[i]) == key(b[j]) ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }

        var result: [Segment] = []
        func push(_ kind: Kind, _ text: String) {
            if let last = result.last, last.kind == kind {
                result[result.count - 1] = Segment(kind: kind, text: last.text + text)
            } else {
                result.append(Segment(kind: kind, text: text))
            }
        }
        var i = 0, j = 0
        while i < a.count && j < b.count {
            if key(a[i]) == key(b[j]) { push(.same, b[j]); i += 1; j += 1 }
            else if lcs[i + 1][j] >= lcs[i][j + 1] { push(.removed, a[i]); i += 1 }
            else { push(.added, b[j]); j += 1 }
        }
        while i < a.count { push(.removed, a[i]); i += 1 }
        while j < b.count { push(.added, b[j]); j += 1 }
        return result
    }

    static func attributed(from old: String, to new: String) -> AttributedString {
        var output = AttributedString()
        for segment in segments(from: old, to: new) {
            var piece = AttributedString(segment.text)
            switch segment.kind {
            case .same: break
            case .added:
                piece.foregroundColor = Theme.doText
                piece.backgroundColor = Theme.doFill
            case .removed:
                piece.foregroundColor = Theme.avoidText
                piece.backgroundColor = Theme.avoidFill
                piece.strikethroughStyle = .single
            }
            output += piece
        }
        return output
    }

    /// Words with their trailing whitespace, so joining them rebuilds the text.
    private static func words(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inSpace = false
        for character in text {
            if character.isWhitespace {
                inSpace = true
                current.append(character)
            } else {
                if inSpace { result.append(current); current = ""; inSpace = false }
                current.append(character)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
