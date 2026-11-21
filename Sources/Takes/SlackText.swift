import AppKit

/// Slack's message box holds more than characters: a mention is a person, a link has an address, a word can be
/// bold. Takes reads and pastes plain text, so a take pasted as it is turns all of that back into characters.
///
/// Slack keeps the difference on the clipboard, in a format of its own next to the plain text. So a paste into
/// Slack first copies what it is about to replace (`Paster`), finds each mention, link and styled phrase that the
/// take still has word for word, and puts the take on the clipboard in that format with those marked again.
/// Nothing here is logged or kept.
enum SlackText {
    static let bundleID = "com.tinyspeck.slackmacgap"
    /// Slack's own clipboard format: the message as a list of inserts, each with its attributes (a Quill delta).
    static let format = "slack/texty"

    static func applies(to target: FocusSnapshot?) -> Bool { target?.app?.bundleIdentifier == bundleID }

    /// A stretch of the message that is more than its characters, on one line: "@Evan" with who that is,
    /// "the doc" with its address, "today" in bold.
    struct Run {
        let text: String
        /// As Slack wrote them, and given back untouched.
        let attributes: [String: Any]

        /// A mention says who it is by itself, so it is the same person wherever the take names them.
        var isMention: Bool { attributes["slackmention"] != nil }
    }

    /// What goes on the clipboard next to the take's plain text, given the clipboard as Slack's own ⌘C left it.
    /// Nil when Slack copied nothing in its format, or the take kept none of it: then the take is pasted plain.
    static func clipboardData(for take: String, copied pasteboard: NSPasteboard) -> Data? {
        guard let data = pasteboard.data(forType: ChromiumCustomData.type),
            let copied = ChromiumCustomData.decode(data)[format],
            let delta = delta(for: take, keeping: runs(in: copied))
        else { return nil }
        return ChromiumCustomData.encode([format: delta])
    }

    /// The marked stretches of a copied message. Whole-line styles (lists, quotes, code blocks) sit on the line
    /// breaks and are left out: a rewrite doesn't keep the draft's lines.
    static func runs(in delta: String) -> [Run] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(delta.utf8)) as? [String: Any],
            let ops = object["ops"] as? [[String: Any]]
        else { return [] }
        var runs: [Run] = []
        for op in ops {
            guard let insert = op["insert"] as? String, let attributes = op["attributes"] as? [String: Any] else { continue }
            let kept = attributes.filter { !($0.value is NSNull) }
            guard !kept.isEmpty else { continue }
            for line in insert.split(whereSeparator: \.isNewline) {
                let text = line.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { runs.append(Run(text: text, attributes: kept)) }
            }
        }
        return runs
    }

    /// The take in Slack's format, with every run it still has word for word marked as it was. Nil when it has none.
    ///
    /// A run is looked for as whole words, in any case ("@evan" at the start of a sentence comes back "@Evan").
    /// Runs with the same text are given out in the order they were in the draft, and no more of them than the
    /// draft had, except a mention: every place the take names that person is the mention.
    static func delta(for take: String, keeping runs: [Run]) -> String? {
        var groups: [String: [Run]] = [:]
        var texts: [String] = []
        for run in runs {
            let key = run.text.lowercased()
            if groups[key] == nil { texts.append(key) }
            groups[key, default: []].append(run)
        }
        // Longest first, so "the launch doc" is matched before a "doc" inside it.
        let longestFirst = texts.enumerated().sorted { ($1.element.count, $0.offset) < ($0.element.count, $1.offset) }.map(\.element)

        var kept: [(range: Range<String.Index>, run: Run)] = []
        for text in longestFirst {
            guard let group = groups[text], let last = group.last else { continue }
            var next = 0
            for range in occurrences(of: text, in: take) where !kept.contains(where: { $0.range.overlaps(range) }) {
                guard next < group.count || last.isMention else { break }
                kept.append((range, next < group.count ? group[next] : last))
                next += 1
            }
        }
        guard !kept.isEmpty else { return nil }

        var ops: [[String: Any]] = []
        var position = take.startIndex
        for (range, run) in kept.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            if position < range.lowerBound { ops.append(["insert": String(take[position..<range.lowerBound])]) }
            // A mention shows the person's name as Slack has it, whatever case the take wrote it in.
            ops.append(["insert": run.isMention ? run.text : String(take[range]), "attributes": run.attributes])
            position = range.upperBound
        }
        if position < take.endIndex { ops.append(["insert": String(take[position...])]) }
        guard let data = try? JSONSerialization.data(withJSONObject: ["ops": ops]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Where `text` is in `take` as whole words: not inside a longer word, name or address.
    private static func occurrences(of text: String, in take: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        var from = take.startIndex
        while from < take.endIndex, let range = take.range(of: text, options: .caseInsensitive, range: from..<take.endIndex),
            !range.isEmpty
        {
            let before = range.lowerBound > take.startIndex ? take[take.index(before: range.lowerBound)] : nil
            let after = range.upperBound < take.endIndex ? take[range.upperBound] : nil
            if joins(before) || joins(after) {
                from = take.index(after: range.lowerBound)
            } else {
                found.append(range)
                from = range.upperBound
            }
        }
        return found
    }

    /// Whether a character next to a match makes it part of a longer word. Scripts written without spaces
    /// between words (Chinese, Japanese, Thai) never do: there a word's neighbours are always letters.
    private static func joins(_ character: Character?) -> Bool {
        guard let character, character.isLetter || character.isNumber || character == "_" else { return false }
        guard let scalar = character.unicodeScalars.first?.value else { return false }
        let unspaced: [ClosedRange<UInt32>] = [0x0E00...0x0EFF, 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x3FFFF]
        return !unspaced.contains { $0.contains(scalar) }
    }
}

/// The one pasteboard type a Chromium app (Slack, Chrome, anything built on Electron) keeps its pages' own
/// clipboard formats in: a map from each format's name to its text.
///
/// The layout is Chromium's "pickle": the payload's size, then how many entries, then for each entry its name and
/// its text. A string is its length in UTF-16 units and then the units, padded to four bytes. Every number is a
/// little-endian 32-bit integer.
enum ChromiumCustomData {
    static let type = NSPasteboard.PasteboardType("org.chromium.web-custom-data")

    /// The formats in `data`, by name. Empty when it isn't laid out as expected.
    static func decode(_ data: Data) -> [String: String] {
        let bytes = [UInt8](data)
        var offset = 0
        func number() -> Int? {
            guard offset + 4 <= bytes.count else { return nil }
            defer { offset += 4 }
            return Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }
        func string() -> String? {
            guard let units = number(), units >= 0, offset + units * 2 <= bytes.count else { return nil }
            let text = String(decoding: (0..<units).map { UInt16(bytes[offset + $0 * 2]) | UInt16(bytes[offset + $0 * 2 + 1]) << 8 }, as: UTF16.self)
            offset += (units * 2 + 3) / 4 * 4
            return text
        }
        guard let size = number(), size <= bytes.count - 4, let count = number() else { return [:] }
        var entries: [String: String] = [:]
        for _ in 0..<count {
            guard let name = string(), let text = string() else { return [:] }
            entries[name] = text
        }
        return entries
    }

    static func encode(_ entries: [String: String]) -> Data {
        func number(_ value: Int) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }
        func string(_ text: String) -> [UInt8] {
            let units = Array(text.utf16)
            var bytes = number(units.count) + units.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8(truncatingIfNeeded: $0 >> 8)] }
            while bytes.count % 4 != 0 { bytes.append(0) }
            return bytes
        }
        var payload = number(entries.count)
        for (name, text) in entries.sorted(by: { $0.key < $1.key }) { payload += string(name) + string(text) }
        return Data(number(payload.count) + payload)
    }
}
