import Foundation

struct EngineRequest {
    var system: String
    var user: String
    var takes: Int
    var model: String
    var effort: String
    /// Called, off the main thread, each time the engine waits to try again (rate limited, overloaded, no answer),
    /// so a slow run says why instead of looking stuck.
    var onRetry: (@Sendable (EngineRetry) -> Void)? = nil
}

/// The engine is waiting to try the request again.
struct EngineRetry: Equatable, Sendable {
    var attempt: Int
    var maxAttempts: Int?
    /// The HTTP status that caused it, when there was one: 429 rate limited, 529 overloaded.
    var status: Int?

    /// Short, for the panel's footer: "Rate limited · retry 2 of 10".
    var label: String {
        let reason: String = switch status {
        case 429: String(localized: "Rate limited")
        case 529: String(localized: "Claude is busy")
        case nil: String(localized: "No answer yet")
        default: String(localized: "Server error")
        }
        let retry = maxAttempts.map { String(localized: "retry \(attempt) of \($0)") } ?? String(localized: "retry \(attempt)")
        return "\(reason) · \(retry)"
    }
}

struct EngineResult {
    let takes: [String]
    /// Request start to the last word.
    let wallMs: Int
    /// Request start to the first streamed word.
    let firstTextMs: Int?
    /// The engine stopped before the answer was finished (it reached its length limit, ran out of time, or its
    /// stream ended early), so the last take is incomplete. The takes before it are whole. Set through
    /// `TakeSplitter.cutShort`, so an answer that stopped right after a separator isn't marked.
    var cutShort = false
}

/// How many tokens an engine lets the model write for one request. A fixed cap cut long drafts short: three takes of
/// a 10,000-character draft are about 7,500 tokens before any thinking. So the cap grows with the request.
enum OutputBudget {
    /// A generous token count for `text`: one token per 3 bytes of UTF-8. English runs near 4 characters a token and
    /// Chinese or Japanese near 1 (3 bytes each), so this errs on the side of room.
    static func tokens(in text: String) -> Int { (text.utf8.count + 2) / 3 }

    /// Room for every take at twice the length of the user message (a take can run longer than the draft), plus
    /// `reserve` for thinking; never below `floor` (short drafts keep the cap they always had) or above `ceiling`.
    static func maxTokens(for request: EngineRequest, floor: Int, ceiling: Int, reserve: Int = 0) -> Int {
        let room = tokens(in: request.user) * max(request.takes, 1) * 2 + reserve
        return min(max(room, floor), ceiling)
    }
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

    /// `EngineResult.cutShort` for an answer: true only when it stopped early (`stoppedEarly`: out of room, out of
    /// time, or a stream that ended without saying it was done) and something was written after the last separator,
    /// so the last take is unfinished. An answer that stopped right after a separator has only whole takes. Every
    /// engine sets `cutShort` through this. `endsTake` says which lines end a take (small models also write `---` or
    /// "Version 2:"); a line of only `=` counts too, as a separator still being written.
    static func cutShort(_ text: String, stoppedEarly: Bool, endsTake: (String) -> Bool = { $0 == separator }) -> Bool {
        guard stoppedEarly else { return false }
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = lines.last(where: { !$0.isEmpty }) else { return false }
        return !(last.allSatisfy { $0 == "=" } || endsTake(last))
    }

    /// Whether `text` has at least one take followed by a finished separator line: a take known to be whole.
    static func hasWholeTake(_ text: String) -> Bool {
        var sawText = false
        // The last line may still be coming, so only lines that ended count.
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).dropLast() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == separator {
                if sawText { return true }
            } else if !trimmed.isEmpty {
                sawText = true
            }
        }
        return false
    }
}
