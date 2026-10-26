import Foundation

/// Runs the Claude Code CLI on this Mac, so requests use the user's own Claude login.
struct ClaudeCodeEngine: TakesEngine {
    static let claudePath: String? = resolveClaude()

    private static let workDir: URL = {
        // An empty folder, so Claude Code finds no CLAUDE.md or project settings.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("takes-engine", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Skip what a rewrite doesn't need: tools, MCP servers, user settings, session files.
    var lean = true

    func run(_ request: EngineRequest, onUpdate: @escaping @Sendable ([String]) -> Void) async throws -> EngineResult {
        guard let claudePath = Self.claudePath else {
            throw EngineError.failed("Couldn't find the `claude` command. Install Claude Code, or switch to an API key in Settings › Engine.")
        }

        var args = [
            "-p", request.user,
            "--system-prompt", request.system,
            "--model", request.model,
            "--effort", request.effort,
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--no-session-persistence",
        ]
        if lean {
            args += ["--tools", "", "--strict-mcp-config", "--setting-sources", ""]
        }

        let process = Self.process(claudePath, args)
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
                        onUpdate(TakeSplitter.split(text, streaming: true))
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
                    let message = result["result"] as? String ?? "unknown error"
                    let hint = message.contains("Not logged in") ? " Run `claude auth login` in Terminal." : ""
                    continuation.resume(throwing: EngineError.failed("Claude Code: \(message)\(hint)"))
                    return
                }
                // The result line holds the full text; prefer it over the streamed pieces.
                let takes = TakeSplitter.split(result["result"] as? String ?? text, streaming: false)
                guard !takes.isEmpty else {
                    continuation.resume(throwing: EngineError.failed("Claude returned no takes."))
                    return
                }
                continuation.resume(returning: EngineResult(takes: takes, wallMs: elapsedMs(), firstTextMs: firstTextMs))
            }
        }
    }

    /// Whether the CLI is installed and signed in, for Settings › Engine.
    static func status() async -> (found: Bool, signedIn: Bool, plan: String?) {
        guard let claudePath else { return (false, false, nil) }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Self.process(claudePath, ["auth", "status"])
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                guard (try? process.run()) != nil else {
                    continuation.resume(returning: (true, false, nil))
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                continuation.resume(returning: (true, json?["loggedIn"] as? Bool ?? false, json?["subscriptionType"] as? String))
            }
        }
    }

    private static func process(_ path: String, _ arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.currentDirectoryURL = workDir
        var env = ProcessInfo.processInfo.environment
        // Apps launched from Finder get a bare PATH; keep claude's own folder on it.
        let claudeDir = (path as NSString).deletingLastPathComponent
        env["PATH"] = "\(claudeDir):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        process.environment = env
        return process
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
