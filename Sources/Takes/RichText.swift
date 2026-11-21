import AppKit

/// Text boxes in mail, docs and notes apps (and web pages in a browser: Gmail, Google Docs, Notion, Outlook on the
/// web) hold links and styles, and a take pasted as plain text loses them. Those apps put HTML or RTF on the
/// clipboard when they copy, and read HTML when they paste.
///
/// So, as in Slack (`SlackText`), a paste that replaces text first copies it (`Paster`), finds each link and styled
/// phrase the take still has word for word, and puts the take on the clipboard as HTML with those marked again,
/// next to the plain text. A take that kept none of them is pasted plain, so a box that holds only plain text
/// (a browser's text area, a chat box) never gets HTML. Nothing here is logged or kept.
enum RichText {
    /// Apps whose text boxes keep links and styles, by bundle ID.
    static let bundleIDs: Set<String> = [
        // Browsers, for Gmail, Google Docs, Outlook, Notion and other web apps.
        "com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser",
        "org.mozilla.firefox",
        // Mail and messaging.
        "com.apple.mail", "com.microsoft.Outlook", "com.microsoft.teams2",
        // Docs and notes.
        "notion.id", "com.apple.Notes", "com.microsoft.Word", "com.apple.iWork.Pages", "com.linear",
    ]

    static func applies(to target: FocusSnapshot?) -> Bool {
        guard let bundleID = target?.app?.bundleIdentifier else { return false }
        return bundleIDs.contains(bundleID)
    }

    /// What a stretch of text is besides its characters. A link's address is kept as the app wrote it.
    struct Style: Equatable {
        var link: String?
        var bold = false
        var italic = false
        var underline = false
        var strikethrough = false
        var code = false

        var isPlain: Bool { self == Style() }
    }

    /// A marked stretch of the copied draft, on one line: "the doc" with its address, "today" in bold.
    struct Run: Equatable {
        let text: String
        let style: Style
    }

    /// The take as HTML, given the clipboard as the app's own ⌘C left it. Nil when the copy has no HTML or RTF, or
    /// the take kept none of its links and styles: then the take is pasted plain.
    static func clipboardHTML(for take: String, copied pasteboard: NSPasteboard) -> String? {
        let copied: [(text: String, style: Style)]
        if let html = pasteboard.string(forType: .html) {
            copied = segments(html: html)
        } else if let rtf = pasteboard.data(forType: .rtf), let text = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            copied = segments(text)
        } else {
            return nil
        }
        return html(for: take, keeping: runs(in: copied))
    }

    // MARK: Reading the copy

    /// The marked stretches of a copy, from its pieces in order. A style the whole copy has is the box's own look
    /// (a code editor's font, a bold heading), not a mark, and is left out. A line break ends a run: a rewrite
    /// doesn't keep the draft's lines.
    static func runs(in segments: [(text: String, style: Style)]) -> [Run] {
        var pieces = segments
        let written = pieces.filter { !$0.text.allSatisfy(\.isWhitespace) }
        let looks: [WritableKeyPath<Style, Bool>] = [\.bold, \.italic, \.underline, \.strikethrough, \.code]
        let everywhere = looks.filter { key in !written.isEmpty && written.allSatisfy { $0.style[keyPath: key] } }
        for index in pieces.indices {
            for key in everywhere { pieces[index].style[keyPath: key] = false }
            // A link's underline is how links look, not a style of its own.
            if pieces[index].style.link != nil { pieces[index].style.underline = false }
        }
        // Next to each other with the same look, two pieces are one run ("the launch doc" split by a color).
        var merged: [(text: String, style: Style)] = []
        for piece in pieces {
            if let last = merged.last, last.style == piece.style {
                merged[merged.count - 1].text += piece.text
            } else {
                merged.append(piece)
            }
        }
        var runs: [Run] = []
        for piece in merged where !piece.style.isPlain {
            for line in piece.text.split(whereSeparator: \.isNewline) {
                let text = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                if !text.isEmpty { runs.append(Run(text: text, style: piece.style)) }
            }
        }
        return runs
    }

    /// The pieces of copied RTF (what Mail, Notes and Pages copy), each with its look.
    static func segments(_ text: NSAttributedString) -> [(text: String, style: Style)] {
        var pieces: [(text: String, style: Style)] = []
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            var style = Style()
            if let url = attributes[.link] as? URL {
                style.link = url.absoluteString
            } else if let link = attributes[.link] as? String, !link.isEmpty {
                style.link = link
            }
            if let font = attributes[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                style.bold = traits.contains(.bold)
                style.italic = traits.contains(.italic)
                style.code = traits.contains(.monoSpace)
            }
            style.underline = (attributes[.underlineStyle] as? Int ?? 0) != 0
            style.strikethrough = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
            pieces.append((text.attributedSubstring(from: range).string, style))
        }
        return pieces
    }

    /// The pieces of copied HTML, each with its look. Only what decides a look is read: links, the tags that
    /// style text (b, i, u, s, code…) and inline `style` (Google Docs styles spans, and wraps a whole copy in a
    /// `<b>` that isn't bold). Never loaded as a web page, so nothing in it (an image, a stylesheet) is fetched.
    static func segments(html: String) -> [(text: String, style: Style)] {
        var pieces: [(text: String, style: Style)] = []
        var stack: [(name: String, apply: (inout Style) -> Void)] = []
        // Inside <head>, <style> or <script>: not text.
        var hidden = 0
        var current: Style {
            var style = Style()
            for element in stack { element.apply(&style) }
            return style
        }
        func lineBreak() { pieces.append(("\n", Style())) }

        var rest = Substring(html)
        while !rest.isEmpty {
            if rest.hasPrefix("<!--") {
                rest = rest.range(of: "-->").map { rest[$0.upperBound...] } ?? ""
                continue
            }
            // <!DOCTYPE html>, <?xml …?>
            if rest.hasPrefix("<!") || rest.hasPrefix("<?") {
                rest = rest.firstIndex(of: ">").map { rest[rest.index(after: $0)...] } ?? ""
                continue
            }
            if rest.hasPrefix("<"), let tag = Tag(rest) {
                rest = rest[tag.end...]
                if Tag.hidden.contains(tag.name) {
                    if tag.closes { hidden = max(0, hidden - 1) } else if !tag.selfCloses { hidden += 1 }
                    continue
                }
                if Tag.blocks.contains(tag.name) { lineBreak() }
                if tag.closes {
                    if let index = stack.lastIndex(where: { $0.name == tag.name }) { stack.removeSubrange(index...) }
                } else if !tag.selfCloses && !Tag.void.contains(tag.name) {
                    stack.append((tag.name, tag.apply))
                }
                continue
            }
            // Text, up to the next tag. A "<" that starts no tag is text too.
            let next = rest.dropFirst().firstIndex(of: "<") ?? rest.endIndex
            if hidden == 0 {
                // As a browser shows it: any run of spaces and line breaks in the source is one space.
                var text = ""
                for character in decode(rest[..<next]) {
                    if !character.isWhitespace {
                        text.append(character)
                    } else if text.last != " " {
                        text.append(" ")
                    }
                }
                if !text.isEmpty { pieces.append((text, current)) }
            }
            rest = rest[next...]
        }
        return pieces
    }

    /// One tag of copied HTML, read just far enough to know what it does to the look of the text in it.
    private struct Tag {
        static let blocks: Set<String> = [
            "address", "article", "blockquote", "br", "dd", "div", "dl", "dt", "figcaption", "footer", "h1", "h2", "h3", "h4", "h5", "h6",
            "header", "hr", "li", "ol", "p", "pre", "section", "table", "td", "th", "tr", "ul",
        ]
        static let void: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]
        static let hidden: Set<String> = ["head", "noscript", "script", "style", "template", "title"]

        let name: String
        let closes: Bool
        let selfCloses: Bool
        let attributes: [String: String]
        /// Where the text after the tag starts.
        let end: Substring.Index

        init?(_ html: Substring) {
            var index = html.index(after: html.startIndex)
            closes = index < html.endIndex && html[index] == "/"
            if closes { index = html.index(after: index) }
            let nameStart = index
            while index < html.endIndex, html[index].isLetter || html[index].isNumber { index = html.index(after: index) }
            guard index > nameStart else { return nil }
            name = html[nameStart..<index].lowercased()
            // The tag ends at the first ">" outside quotes.
            var quote: Character?
            let attributesStart = index
            while index < html.endIndex {
                let character = html[index]
                if let opening = quote {
                    if character == opening { quote = nil }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == ">" {
                    break
                }
                index = html.index(after: index)
            }
            guard index < html.endIndex else { return nil }
            let inside = html[attributesStart..<index]
            selfCloses = inside.last == "/"
            attributes = Tag.parseAttributes(inside)
            end = html.index(after: index)
        }

        /// `name="value"`, `name='value'` and `name=value`, by lowercased name.
        private static func parseAttributes(_ text: Substring) -> [String: String] {
            var found: [String: String] = [:]
            var rest = text
            while true {
                rest = rest.drop { $0.isWhitespace || $0 == "/" }
                let name = rest.prefix { !$0.isWhitespace && $0 != "=" && $0 != "/" && $0 != ">" }
                guard !name.isEmpty else { return found }
                rest = rest[name.endIndex...].drop(while: \.isWhitespace)
                var value = ""
                if rest.first == "=" {
                    rest = rest.dropFirst().drop(while: \.isWhitespace)
                    if let quote = rest.first, quote == "\"" || quote == "'" {
                        let body = rest.dropFirst()
                        let close = body.firstIndex(of: quote) ?? body.endIndex
                        value = String(body[..<close])
                        rest = close < body.endIndex ? body[body.index(after: close)...] : ""
                    } else {
                        let bare = rest.prefix { !$0.isWhitespace }
                        value = String(bare)
                        rest = rest[bare.endIndex...]
                    }
                }
                found[name.lowercased()] = decode(Substring(value))
            }
        }

        /// What the tag does to the look of the text in it. Inline `style` wins over what the tag means by itself.
        var apply: (inout Style) -> Void {
            var link: String?
            var bold: Bool?
            var italic: Bool?
            var underline: Bool?
            var strikethrough: Bool?
            var code: Bool?
            switch name {
            case "a":
                if let href = attributes["href"]?.trimmingCharacters(in: .whitespaces), !href.isEmpty,
                    !href.lowercased().hasPrefix("javascript:")
                {
                    link = href
                }
            case "b", "strong": bold = true
            case "i", "em", "cite", "var": italic = true
            case "u", "ins": underline = true
            case "s", "strike", "del": strikethrough = true
            case "code", "kbd", "samp", "tt": code = true
            default: break
            }
            for declaration in (attributes["style"] ?? "").split(separator: ";") {
                let parts = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                guard parts.count == 2 else { continue }
                let value = parts[1].replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: .whitespaces)
                switch parts[0] {
                case "font-weight":
                    if let weight = Int(value) {
                        bold = weight >= 600
                    } else if value == "bold" || value == "bolder" {
                        bold = true
                    } else if value == "normal" || value == "lighter" {
                        bold = false
                    }
                case "font-style":
                    italic = value.hasPrefix("italic") || value.hasPrefix("oblique")
                case "text-decoration", "text-decoration-line":
                    underline = value.contains("underline")
                    strikethrough = value.contains("line-through")
                case "font-family":
                    code = ["monospace", "courier", "menlo", "monaco", "consolas", "sf mono", "roboto mono", "source code"].contains { value.contains($0) }
                default: break
                }
            }
            return { [link, bold, italic, underline, strikethrough, code] style in
                if let link { style.link = link }
                if let bold { style.bold = bold }
                if let italic { style.italic = italic }
                if let underline { style.underline = underline }
                if let strikethrough { style.strikethrough = strikethrough }
                if let code { style.code = code }
            }
        }
    }

    /// Text with its character references (`&amp;`, `&nbsp;`, `&#39;`, `&#x2019;`) turned back into characters.
    private static func decode(_ text: Substring) -> String {
        guard text.contains("&") else { return String(text) }
        let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]
        var decoded = ""
        var rest = text
        while let ampersand = rest.firstIndex(of: "&") {
            decoded += rest[..<ampersand]
            let after = rest[rest.index(after: ampersand)...]
            if let semicolon = after.prefix(10).firstIndex(of: ";") {
                let name = String(after[..<semicolon])
                var character: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    character = UInt32(name.dropFirst(2), radix: 16).flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
                } else if name.hasPrefix("#") {
                    character = UInt32(name.dropFirst(), radix: 10).flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
                } else {
                    character = named[name.lowercased()]
                }
                if let character {
                    // A no-break space is a space, so "the doc" matches a copy that wrote "the&nbsp;doc".
                    decoded += character == "\u{A0}" ? " " : character
                    rest = after[after.index(after: semicolon)...]
                    continue
                }
            }
            decoded += "&"
            rest = after
        }
        return decoded + rest
    }

    // MARK: Writing the take

    /// The take as HTML, with every run it still has word for word marked as it was. Nil when it has none.
    /// Each line is a `<div>`, as a rich text box writes its own lines. No fonts or colors: the take takes the box's.
    static func html(for take: String, keeping runs: [Run]) -> String? {
        let kept = KeptRuns.place(runs.map { (text: $0.text, repeats: false) }, in: take)
        guard !kept.isEmpty else { return nil }

        var body = ""
        var position = take.startIndex
        for (range, index) in kept {
            body += escape(take[position..<range.lowerBound])
            body += marked(escape(take[range]), runs[index].style)
            position = range.upperBound
        }
        body += escape(take[position...])
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? "<div><br></div>" : "<div>\($0)</div>" }
        return "<meta charset=\"utf-8\">" + lines.joined()
    }

    private static func marked(_ text: String, _ style: Style) -> String {
        var html = text
        if style.code { html = "<code>\(html)</code>" }
        if style.strikethrough { html = "<s>\(html)</s>" }
        if style.underline { html = "<u>\(html)</u>" }
        if style.italic { html = "<i>\(html)</i>" }
        if style.bold { html = "<b>\(html)</b>" }
        if let link = style.link { html = "<a href=\"\(escape(Substring(link)))\">\(html)</a>" }
        return html
    }

    private static func escape(_ text: Substring) -> String {
        var escaped = ""
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            default: escaped.append(character)
            }
        }
        return escaped
    }
}

/// Which app's own clipboard format a paste keeps formatting in: Slack's, or HTML for the apps `RichText` covers.
enum KeptFormatting {
    /// The take in the app's own format, next to its plain text.
    enum Formatted: Equatable {
        case slack(Data)
        case html(String)
    }

    static func applies(to target: FocusSnapshot?) -> Bool { SlackText.applies(to: target) || RichText.applies(to: target) }

    /// The clipboard types the app's own copy carries its formatting in, to wait for once the copy lands.
    static func copiedTypes(for target: FocusSnapshot?) -> [NSPasteboard.PasteboardType] {
        if SlackText.applies(to: target) { return [ChromiumCustomData.type] }
        if RichText.applies(to: target) { return [.html, .rtf] }
        return [ChromiumCustomData.type, .html, .rtf]
    }

    /// The take with what it kept marked, given the clipboard as the app's ⌘C left it. Slack gets only its own
    /// format. Nil when the take kept nothing.
    static func formatted(_ take: String, copied pasteboard: NSPasteboard, target: FocusSnapshot?) -> Formatted? {
        if let slack = SlackText.clipboardData(for: take, copied: pasteboard) { return .slack(slack) }
        guard !SlackText.applies(to: target) else { return nil }
        return RichText.clipboardHTML(for: take, copied: pasteboard).map(Formatted.html)
    }
}
