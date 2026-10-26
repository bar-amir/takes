import Foundation

struct EngineRequest {
    var draft: String
    var preset: Preset
    var takes: Int
    var model: String
    var effort: String
    /// Strip everything Claude Code loads by default that a rewrite doesn't need (tools, MCP servers, settings).
    var lean = true
}

struct EngineResult {
    let takes: [String]
    /// Process start to exit, as seen by this app.
    let wallMs: Int
    /// Process start to the first streamed word.
    let firstTextMs: Int?
    /// Claude Code's own `duration_api_ms` from its result line.
    let apiMs: Int?
}

enum EngineError: LocalizedError {
    case claudeNotFound
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .claudeNotFound: return "Couldn't find the `claude` command. Install Claude Code or set CLAUDE_PATH."
        case .failed(let message): return message
        }
    }
}

/// Runs the Claude Code CLI on this Mac, so requests use the user's own Claude login.
///
/// Takes come back as plain text separated by `===` lines and stream in as they're written.
/// Plain text matters: `--json-schema` costs Claude Code a second model turn, about doubling the time.
enum Engine {
    static let separator = "==="
    static let claudePath: String? = resolveClaude()

    private static let workDir: URL = {
        // An empty folder, so Claude Code finds no CLAUDE.md or project settings.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("takes-engine", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// `onUpdate` receives the takes written so far (the last one may be partial), off the main thread.
    static func run(_ request: EngineRequest, onUpdate: @escaping @Sendable ([String]) -> Void = { _ in }) async throws -> EngineResult {
        guard let claudePath else { throw EngineError.claudeNotFound }

        var args = [
            "-p", "<draft>\n\(request.draft)\n</draft>",
            "--system-prompt", request.preset.systemPrompt(takes: request.takes),
            "--model", request.model,
            "--effort", request.effort,
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--no-session-persistence",
        ]
        if request.lean {
            args += ["--tools", "", "--strict-mcp-config", "--setting-sources", ""]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = args
        process.currentDirectoryURL = workDir
        var env = ProcessInfo.processInfo.environment
        // Apps launched from Finder get a bare PATH; keep claude's own folder on it.
        let claudeDir = (claudePath as NSString).deletingLastPathComponent
        env["PATH"] = "\(claudeDir):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        process.environment = env

        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let started = Date()
        let elapsedMs = { Int(Date().timeIntervalSince(started) * 1000) }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                var text = ""
                var firstTextMs: Int?
                var resultLine: [String: Any]?
                var buffer = Data()
                let reader = stdout.fileHandleForReading

                func handle(line: Data) {
                    guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
                    switch json["type"] as? String {
                    case "stream_event":
                        guard let event = json["event"] as? [String: Any],
                              event["type"] as? String == "content_block_delta",
                              let delta = event["delta"] as? [String: Any],
                              delta["type"] as? String == "text_delta",
                              let chunk = delta["text"] as? String else { return }
                        if firstTextMs == nil { firstTextMs = elapsedMs() }
                        text += chunk
                        onUpdate(splitTakes(text, streaming: true))
                    case "result":
                        resultLine = json
                    default:
                        break
                    }
                }

                while true {
                    let data = reader.availableData
                    if data.isEmpty { break }
                    buffer.append(data)
                    while let newline = buffer.firstIndex(of: 0x0A) {
                        handle(line: buffer[buffer.startIndex..<newline])
                        buffer.removeSubrange(buffer.startIndex...newline)
                    }
                }
                if !buffer.isEmpty { handle(line: buffer) }
                let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard let result = resultLine else {
                    let message = String(data: errorOutput, encoding: .utf8) ?? ""
                    continuation.resume(throwing: EngineError.failed("Claude Code failed: \(message.prefix(400))"))
                    return
                }
                if result["is_error"] as? Bool == true {
                    continuation.resume(throwing: EngineError.failed("Claude Code: \(result["result"] as? String ?? "unknown error")"))
                    return
                }
                // The result line holds the full text; prefer it over the streamed pieces.
                let takes = splitTakes(result["result"] as? String ?? text, streaming: false)
                guard !takes.isEmpty else {
                    continuation.resume(throwing: EngineError.failed("Claude returned no takes."))
                    return
                }
                continuation.resume(returning: EngineResult(takes: takes, wallMs: elapsedMs(), firstTextMs: firstTextMs,
                                                            apiMs: result["duration_api_ms"] as? Int))
            }
        }
    }

    /// Splits text on `===` lines. While streaming, a half-written separator at the end is dropped.
    static func splitTakes(_ text: String, streaming: Bool) -> [String] {
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

    private static func resolveClaude() -> String? {
        if let path = ProcessInfo.processInfo.environment["CLAUDE_PATH"], FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Ask a login shell, which knows about nvm, Homebrew and ~/.local/bin.
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-lic", "command -v claude"]
        let pipe = Pipe()
        shell.standardOutput = pipe
        shell.standardError = FileHandle.nullDevice
        if (try? shell.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            shell.waitUntilExit()
            let path = String(data: data, encoding: .utf8)?
                .split(separator: "\n").last.map(String.init)?
                .trimmingCharacters(in: .whitespaces)
            if let path, FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
