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
    /// Claude Code's own `duration_ms` and `duration_api_ms` from its JSON output.
    let durationMs: Int?
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
enum Engine {
    static let claudePath: String? = resolveClaude()

    private static let workDir: URL = {
        // An empty folder, so Claude Code finds no CLAUDE.md or project settings.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("takes-engine", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func run(_ request: EngineRequest) async throws -> EngineResult {
        guard let claudePath else { throw EngineError.claudeNotFound }

        let schema = """
        {"type":"object","properties":{"takes":{"type":"array","items":{"type":"string"},"minItems":\(request.takes),"maxItems":\(request.takes)}},"required":["takes"],"additionalProperties":false}
        """
        var args = [
            "-p", "<draft>\n\(request.draft)\n</draft>",
            "--system-prompt", request.preset.systemPrompt(takes: request.takes),
            "--model", request.model,
            "--effort", request.effort,
            "--output-format", "json",
            "--json-schema", schema,
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
        // Apps launched from Finder get a bare PATH; the claude script needs node from its own folder.
        let claudeDir = (claudePath as NSString).deletingLastPathComponent
        env["PATH"] = "\(claudeDir):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        process.environment = env

        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let started = Date()
        let (out, err): (Data, Data) = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try process.run()
                    let out = stdout.fileHandleForReading.readDataToEndOfFile()
                    let err = stderr.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: (out, err))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        let wallMs = Int(Date().timeIntervalSince(started) * 1000)

        guard let json = try? JSONSerialization.jsonObject(with: out) as? [String: Any] else {
            let message = String(data: err.isEmpty ? out : err, encoding: .utf8) ?? "No output"
            throw EngineError.failed("Claude Code failed: \(message.prefix(400))")
        }
        if json["is_error"] as? Bool == true {
            throw EngineError.failed("Claude Code: \(json["result"] as? String ?? "unknown error")")
        }

        let takes = parseTakes(json)
        guard !takes.isEmpty else {
            throw EngineError.failed("No takes in the response: \(String(data: out, encoding: .utf8)?.prefix(400) ?? "")")
        }
        return EngineResult(takes: takes, wallMs: wallMs,
                            durationMs: json["duration_ms"] as? Int, apiMs: json["duration_api_ms"] as? Int)
    }

    private static func parseTakes(_ json: [String: Any]) -> [String] {
        if let structured = json["structured_output"] as? [String: Any], let takes = structured["takes"] as? [String] {
            return takes
        }
        // Fall back to the text result holding the JSON object.
        if let text = json["result"] as? String, let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let takes = object["takes"] as? [String] {
            return takes
        }
        return []
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
