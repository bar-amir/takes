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

/// Something that turns a request into streamed takes.
protocol TakesEngine {
    /// `onUpdate` receives the takes written so far (the last may be partial), off the main thread.
    func run(_ request: EngineRequest, onUpdate: @escaping @Sendable ([String]) -> Void) async throws -> EngineResult
}

enum Engines {
    static func current(_ settings: AppSettings) -> TakesEngine {
        settings.engine == .apiKey ? APIEngine() : ClaudeCodeEngine()
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
