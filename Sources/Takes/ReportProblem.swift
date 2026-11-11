import AppKit

/// "Report a Problem…" in the menu: opens a new GitHub bug report with the Takes version, the macOS version
/// and the engine type filled in, and a crash summary when Takes crashed lately (CrashReports). Never any text,
/// presets, model names or anything else from the Mac.
enum ReportProblem {
    static let newIssue = "https://github.com/bar-amir/takes/issues/new"

    /// GitHub and browsers refuse very long links, so a link built here is never longer than this many characters.
    static let maxURLLength = 8000
    /// The last line of a crash summary that was cut to fit the link, so whoever reads it knows there was more.
    static let trimmedNote = "… (cut to fit the link; the full report is the file shown in Finder)"

    static func url(takesVersion: String, macOSVersion: String, engine: EngineKind, crash: String? = nil) -> URL {
        func link(_ crash: String?) -> URL {
            var components = URLComponents(string: newIssue)!
            components.queryItems = [
                URLQueryItem(name: "template", value: "bug_report.yml"),
                URLQueryItem(name: "engine", value: engineOption(engine)),
                URLQueryItem(name: "versions", value: "Takes \(takesVersion), macOS \(macOSVersion)"),
            ]
            if let crash {
                components.queryItems?.append(URLQueryItem(name: "title", value: "Takes quit unexpectedly"))
                components.queryItems?.append(URLQueryItem(name: "crash", value: crash))
            }
            // URLComponents leaves "+" as it is, and GitHub reads it as a space (operators in symbol names).
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            return components.url!
        }

        guard let crash, link(crash).absoluteString.count > maxURLLength else { return link(crash) }
        // The most of the summary that fits, cut at the end of a line when there is one, with the note after it.
        // A longer cut never makes a shorter link, so a binary search finds it.
        let characters = Array(crash)
        func cut(_ count: Int) -> String {
            var kept = Array(characters.prefix(count))
            if count < characters.count, let end = kept.lastIndex(where: { $0.isNewline }) { kept = Array(kept[..<end]) }
            return (kept.isEmpty ? "" : String(kept) + "\n") + trimmedNote
        }
        var fits = 0
        var tooLong = characters.count
        while fits < tooLong {
            let middle = (fits + tooLong + 1) / 2
            if link(cut(middle)).absoluteString.count <= maxURLLength { fits = middle } else { tooLong = middle - 1 }
        }
        return link(cut(fits))
    }

    /// The bug form's Engine options, word for word, so GitHub picks the right one.
    static func engineOption(_ engine: EngineKind) -> String {
        switch engine {
        case .claudeCode: return "Claude Code on this Mac"
        case .apiKey: return "Anthropic API key"
        case .chatGPT: return "ChatGPT plan"
        case .provider: return "Other provider (own API key)"
        case .local: return "Local model"
        }
    }

    static func currentURL(crash: String? = nil) -> URL {
        let takes = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let macOS =
            os.patchVersion == 0
            ? "\(os.majorVersion).\(os.minorVersion)"
            : "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        return url(takesVersion: takes, macOSVersion: macOS, engine: Store.shared.settings.engine, crash: crash)
    }

    /// From the menu: a crash in the last two weeks goes along, so a report filed after "it just quit" has it.
    @MainActor static func open() {
        if let crash = CrashReports.latest(after: nil) {
            CrashReports.send(crash)
        } else {
            NSWorkspace.shared.open(currentURL())
        }
    }
}
