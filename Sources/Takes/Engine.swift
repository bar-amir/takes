import Foundation

struct EngineRequest {
    var system: String
    var user: String
    var takes: Int
    var model: String
    var effort: String
}

struct EngineResult {
    let takes: [String]
    /// Request start to the last word.
    let wallMs: Int
    /// Request start to the first streamed word.
    let firstTextMs: Int?
}

enum EngineError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// The engine's account can't take more requests: out of credit, at its plan or spend limit, or rate limited for now.
/// The panel shows a title, `message`, and a button to `manage`, the page where the user can fix it.
struct UsageLimitError: LocalizedError, Equatable {
    enum Kind: Equatable { case outOfCredit, planLimit, rateLimited }
    var kind: Kind
    var message: String
    var manage: URL?
    var errorDescription: String? { message }

    var title: String {
        switch kind {
        case .outOfCredit: String(localized: "Out of credit")
        case .planLimit: String(localized: "Usage limit reached")
        case .rateLimited: String(localized: "Too many requests")
        }
    }

    /// The button that opens `manage`.
    var manageTitle: String { kind == .outOfCredit ? String(localized: "Add credit") : String(localized: "Manage usage") }

    /// "Try again in 20 seconds." from a Retry-After header in seconds.
    static func retryHint(_ retryAfter: String?) -> String {
        guard let seconds = retryAfter.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }), seconds > 0, seconds <= 3600
        else { return String(localized: "Try again in a moment.") }
        if seconds < 90 {
            return seconds == 1 ? String(localized: "Try again in 1 second.") : String(localized: "Try again in \(seconds) seconds.")
        }
        let minutes = (seconds + 59) / 60
        return String(localized: "Try again in \(minutes) minutes.")
    }
}

/// Something that turns a request into streamed takes.
protocol TakesEngine {
    /// `onUpdate` receives the takes written so far (the last may be partial), off the main thread.
    func run(_ request: EngineRequest, onUpdate: @escaping @Sendable ([String]) -> Void) async throws -> EngineResult
}

enum Engines {
    static func current(_ settings: AppSettings) -> TakesEngine {
        switch settings.engine {
        case .apiKey: APIEngine()
        case .local: LocalEngine(baseURL: settings.localBaseURL)
        case .claudeCode: ClaudeCodeEngine()
        case .provider: ProviderEngine(settings: settings)
        case .chatGPT: ChatGPTEngine()
        }
    }
}

/// Takes come back as plain text separated by `===` lines.
/// Plain text matters: structured JSON output costs Claude Code a second model turn, about doubling the time.
enum TakeSplitter {
    static let separator = "==="

    /// While streaming, a half-written separator at the end is dropped.
    static func split(_ text: String, streaming: Bool) -> [String] {
        var takes: [[Substring]] = [[]]
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if streaming, let last = lines.last, !last.isEmpty, last.allSatisfy({ $0 == "=" }) {
            lines.removeLast()
        }
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces) == separator {
                takes.append([])
            } else {
                takes[takes.count - 1].append(line)
            }
        }
        return takes
            .map { $0.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
