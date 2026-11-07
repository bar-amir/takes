import AppKit

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
            throw EngineError.failed(String(localized: "Couldn't find the `claude` command. Install Claude Code, or switch to an API key in Settings › Model."))
        }

        // The user message goes in on stdin, never as an argument: as a positional argument, text starting with "-"
        // would be parsed as a CLI option (a draft of "--mcp-config=…" could start a program), and arguments are
        // visible to other processes in `ps`.
        var args = [
            "-p",
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
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
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
                // Written on its own queue: a long draft can fill the pipe before claude starts reading.
                let input = stdin.fileHandleForWriting
                // If claude exits before reading everything, the write fails instead of killing Takes with SIGPIPE.
                _ = fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1)
                DispatchQueue.global().async {
                    try? input.write(contentsOf: Data(request.user.utf8))
                    try? input.close()
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
                    let message = String((String(data: errorOutput, encoding: .utf8) ?? "").prefix(400))
                    continuation.resume(throwing: EngineError.failed(String(localized: "Claude Code failed: \(message)")))
                    return
                }
                if result["is_error"] as? Bool == true {
                    continuation.resume(throwing: Self.resultError(result["result"] as? String ?? "unknown error"))
                    return
                }
                // The result line holds the full text; prefer it over the streamed pieces.
                let takes = TakeSplitter.split(result["result"] as? String ?? text, streaming: false)
                guard !takes.isEmpty else {
                    continuation.resume(throwing: EngineError.failed(String(localized: "Claude returned no takes.")))
                    return
                }
                continuation.resume(returning: EngineResult(takes: takes, wallMs: elapsedMs(), firstTextMs: firstTextMs))
            }
        }
    }

    static let usageURL = URL(string: "https://claude.ai/settings/usage")!

    /// The error for a result line with `is_error`, in plain words for plan limits and credit.
    static func resultError(_ message: String, now: Date = Date()) -> Error {
        let lower = message.lowercased()
        if lower.contains("credit balance") {
            let message = String(localized: "The Anthropic account Claude Code uses is out of credit. Add credit in the Anthropic Console, or pick another engine.")
            return UsageLimitError(kind: .outOfCredit, message: message, manage: APIEngine.billingURL)
        }
        // "Claude AI usage limit reached|1767225600", "5-hour limit reached ∙ resets 3pm", "You've hit your limit · resets 3pm"
        if lower.contains("limit reached") || lower.contains("hit your limit") || lower.contains("usage limit") {
            let limitMessage: String = if let reset = resetPhrase(message, now: now) {
                String(localized: "You've reached your Claude plan's usage limit. \(reset) Pick another engine to keep going.")
            } else {
                String(localized: "You've reached your Claude plan's usage limit. Pick another engine to keep going.")
            }
            return UsageLimitError(kind: .planLimit, message: limitMessage, manage: usageURL)
        }
        return EngineError.failed(errorMessage(message))
    }

    /// "It resets 3pm." from Claude Code's limit message: a "resets …" phrase, or a Unix time after "|".
    static func resetPhrase(_ message: String, now: Date = Date()) -> String? {
        if let bar = message.lastIndex(of: "|"),
           let seconds = TimeInterval(message[message.index(after: bar)...].trimmingCharacters(in: .whitespaces)) {
            let date = Date(timeIntervalSince1970: seconds)
            guard date > now else { return nil }
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = Calendar.current.isDate(date, inSameDayAs: now) ? .none : .medium
            let time = formatter.string(from: date)
            return Calendar.current.isDate(date, inSameDayAs: now)
                ? String(localized: "It resets at \(time).") : String(localized: "It resets \(time).")
        }
        guard let range = message.range(of: "resets ", options: .caseInsensitive) else { return nil }
        let when = message[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return when.isEmpty ? nil : String(localized: "It resets \(when).")
    }

    /// Shown instead of the CLI's own wording when the login is the problem. Plain words, no commands: the
    /// panel puts a "Sign in to Claude" button under it. The Claude desktop app keeps its own sign-in, so
    /// it can still work while this one has expired; say so, or the message looks wrong.
    static let signedOutMessage = String(localized: "Takes got signed out of Claude. Sign in again to keep going. This sign-in is separate from the Claude app, so it can expire even while the app still works.")

    /// The CLI's error, in words a person can act on. A sign-in problem (not signed in, or a session that
    /// expired and couldn't be refreshed: "Failed to authenticate: OAuth session expired…") becomes
    /// `signedOutMessage`; anything else keeps the CLI's wording.
    static func errorMessage(_ message: String) -> String {
        isSignInProblem(message) ? signedOutMessage : String(localized: "Claude Code: \(message)")
    }

    static func isSignInProblem(_ message: String) -> Bool {
        let lower = message.lowercased()
        return ["not logged in", "failed to authenticate", "oauth", "/login", "invalid api key", "token has expired"]
            .contains { lower.contains($0) }
    }

    /// Opens Terminal already running `claude auth login`, which sends the person to the browser to sign in.
    /// A .command file runs on open without the Automation permission that scripting Terminal would need.
    static func openSignIn() {
        let claude = claudePath ?? "claude"
        func shellQuoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let quoted = shellQuoted(claude)
        let intro = shellQuoted(String(localized: "Signing Takes in to Claude. Finish in the browser window that opens, then go back to Takes and press Try again."))
        let done = shellQuoted(String(localized: "You can close this window now."))
        let script = """
            #!/bin/zsh
            clear
            echo \(intro)
            echo
            \(quoted) auth login
            echo
            echo \(done)
            """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Sign in to Claude.command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            // Fall back to what onboarding does: copy the command and open Terminal.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("claude auth login", forType: .string)
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        }
    }

    /// Whether the CLI is installed and signed in, for Settings › Model.
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
