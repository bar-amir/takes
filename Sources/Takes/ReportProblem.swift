import AppKit

/// "Report a Problem…" in the menu: opens a new GitHub bug report with the Takes version, the macOS version
/// and the engine type filled in. Never any text, presets, model names or anything else from the Mac.
enum ReportProblem {
    static let newIssue = "https://github.com/bar-amir/takes/issues/new"

    static func url(takesVersion: String, macOSVersion: String, engine: EngineKind) -> URL {
        var components = URLComponents(string: newIssue)!
        components.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "engine", value: engineOption(engine)),
            URLQueryItem(name: "versions", value: "Takes \(takesVersion), macOS \(macOSVersion)"),
        ]
        return components.url!
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

    static var currentURL: URL {
        let takes = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let macOS =
            os.patchVersion == 0
            ? "\(os.majorVersion).\(os.minorVersion)"
            : "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        return url(takesVersion: takes, macOSVersion: macOS, engine: Store.shared.settings.engine)
    }

    @MainActor static func open() { NSWorkspace.shared.open(currentURL) }
}
