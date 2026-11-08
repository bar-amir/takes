import AppKit

/// Runs the Claude Code CLI on this Mac, so requests use the user's own Claude login.
struct ClaudeCodeEngine: TakesEngine {
    /// Where the `claude` command is. Looked up again while it isn't found, so installing Claude Code while
    /// setup is open is noticed without restarting Takes.
    static var claudePath: String? { ClaudeLocator.shared.path() }
    /// The last answer, without looking: for the main thread, which must never wait on a shell.
    static var knownClaudePath: String? { ClaudeLocator.shared.known }

    /// Looks for `claude` off the main thread, the login shell included.
    static func locate() async -> String? { await Task.detached { claudePath }.value }

    /// A run that hasn't finished by then is stopped, so a hung `claude` can't keep the panel spinning.
    static let runTimeout: TimeInterval = 120

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
            throw EngineError.failed("Couldn't find the `claude` command. Install Claude Code, or switch to an API key in Settings › Model.")
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

        // Esc, closing the panel or asking again cancels the task; the process is stopped too, so it doesn't
        // keep running (and using the person's Claude plan) for a result nobody will see.
        let stop = ProcessStopper(process)
        let result: EngineResult = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                    stop.started()
                    DispatchQueue.global().asyncAfter(deadline: .now() + Self.runTimeout) { stop.timeOut() }
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

                    if stop.wasCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    if stop.timedOut {
                        let minutes = Int(Self.runTimeout / 60)
                        continuation.resume(throwing: EngineError.failed(
                            "Claude Code didn't answer within \(minutes) minutes, so Takes stopped it. Try again, or pick another engine in Settings › Model."))
                        return
                    }
                    guard let result = resultLine else {
                        let message = String(data: errorOutput, encoding: .utf8) ?? ""
                        continuation.resume(throwing: EngineError.failed(
                            Self.isOutOfDate(message) ? Self.outOfDateMessage : "Claude Code failed: \(message.prefix(400))"))
                        return
                    }
                    if result["is_error"] as? Bool == true {
                        continuation.resume(throwing: Self.resultError(result["result"] as? String ?? "unknown error"))
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
        } onCancel: {
            stop.cancel()
        }
        return result
    }

    static let usageURL = URL(string: "https://claude.ai/settings/usage")!

    /// The error for a result line with `is_error`, in plain words for plan limits and credit.
    static func resultError(_ message: String, now: Date = Date()) -> Error {
        let lower = message.lowercased()
        if lower.contains("credit balance") {
            let message = "The Anthropic account Claude Code uses is out of credit. Add credit in the Anthropic Console, or pick another engine."
            return UsageLimitError(kind: .outOfCredit, message: message, manage: APIEngine.billingURL)
        }
        // "Claude AI usage limit reached|1767225600", "5-hour limit reached ∙ resets 3pm", "You've hit your limit · resets 3pm"
        if lower.contains("limit reached") || lower.contains("hit your limit") || lower.contains("usage limit") {
            let reset = resetPhrase(message, now: now).map { " \($0)" } ?? ""
            return UsageLimitError(kind: .planLimit,
                                   message: "You've reached your Claude plan's usage limit.\(reset) Pick another engine to keep going.",
                                   manage: usageURL)
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
            return "It resets \(Calendar.current.isDate(date, inSameDayAs: now) ? "at " : "")\(formatter.string(from: date))."
        }
        guard let range = message.range(of: "resets ", options: .caseInsensitive) else { return nil }
        let when = message[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return when.isEmpty ? nil : "It resets \(when)."
    }

    /// Shown instead of the CLI's own wording when the login is the problem. Plain words, no commands: the
    /// panel puts a "Sign in to Claude" button under it. The Claude desktop app keeps its own sign-in, so
    /// it can still work while this one has expired; say so, or the message looks wrong.
    static let signedOutMessage = "Takes got signed out of Claude. Sign in again to keep going. This sign-in is separate from the Claude app, so it can expire even while the app still works."

    /// The CLI's error, in words a person can act on. A sign-in problem (not signed in, or a session that
    /// expired and couldn't be refreshed: "Failed to authenticate: OAuth session expired…") becomes
    /// `signedOutMessage`; anything else keeps the CLI's wording.
    static func errorMessage(_ message: String) -> String {
        if isSignInProblem(message) { return signedOutMessage }
        if isOutOfDate(message) { return outOfDateMessage }
        return "Claude Code: \(message)"
    }

    /// An old CLI rejects a flag Takes passes ("error: unknown option '--effort'").
    static let outOfDateMessage = "This version of Claude Code is too old for Takes. Update it (run `claude update` in Terminal), or pick another engine in Settings › Model."

    static func isOutOfDate(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("unknown option") || lower.contains("unknown command") || lower.contains("too many arguments")
    }

    static func isSignInProblem(_ message: String) -> Bool {
        let lower = message.lowercased()
        return ["not logged in", "failed to authenticate", "oauth", "/login", "invalid api key", "token has expired"]
            .contains { lower.contains($0) }
    }

    /// Opens Terminal already running `claude auth login`, which sends the person to the browser to sign in.
    /// A .command file runs on open without the Automation permission that scripting Terminal would need. It runs
    /// `claude` by its full path: the official installer puts it in ~/.local/bin, which a new shell often doesn't
    /// have on its PATH, so a bare `claude` would be "command not found". The sign-in itself stays in Claude Code:
    /// Takes never sees the code or the token.
    static func openSignIn() {
        let claude = knownClaudePath ?? ClaudeLocator.fixedPath() ?? "claude"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Sign in to Claude.command")
        do {
            try signInScript(claudePath: claude).write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            // Copy the full command instead, so pasting it in Terminal works too.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(signInCommand(claudePath: claude), forType: .string)
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        }
    }

    /// `claude auth login` with `claude` by its full path, quoted for the shell.
    static func signInCommand(claudePath: String) -> String {
        "'" + claudePath.replacingOccurrences(of: "'", with: "'\\''") + "' auth login"
    }

    /// What the sign-in window runs.
    static func signInScript(claudePath: String) -> String {
        """
        #!/bin/zsh
        clear
        echo "Signing Takes in to Claude. Finish in the browser window that opens, then go back to Takes."
        echo
        \(signInCommand(claudePath: claudePath))
        echo
        echo "You can close this window now."
        """
    }

    /// What `status()` found out about the CLI.
    struct Status: Equatable {
        var found: Bool
        var signedIn = false
        var plan: String?
        /// "2.1.310", or nil when the CLI didn't say.
        var version: String?
        /// `claude auth status` didn't answer within `statusTimeout`; nothing is known about the sign-in.
        var timedOut = false
    }

    /// `claude auth status` and `claude --version` get this long each. A hung CLI must not stop setup from showing.
    static let statusTimeout: TimeInterval = 15

    /// The oldest CLI Takes works with: `claude auth login` and `claude auth status` arrived in 2.1.41, and the run
    /// flags Takes passes (`--effort`, `--setting-sources`) are from the same time.
    static let minimumVersion = "2.1.41"

    static func isSupported(version: String) -> Bool { compareVersions(version, minimumVersion) != .orderedAscending }

    /// "2.1.9" < "2.1.41": numeric, part by part; missing parts count as 0.
    static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let (x, y) = (a.split(separator: ".").map { Int($0) ?? 0 }, b.split(separator: ".").map { Int($0) ?? 0 })
        for i in 0..<max(x.count, y.count) {
            let (p, q) = (i < x.count ? x[i] : 0, i < y.count ? y[i] : 0)
            if p != q { return p < q ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// The version in `claude --version` output ("2.1.310 (Claude Code)").
    static func parseVersion(_ output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(whereSeparator: { $0 == " " || $0 == "\n" }).first else { return nil }
        let digits = first.split(separator: ".")
        guard digits.count >= 2, digits.allSatisfy({ Int($0) != nil }) else { return nil }
        return String(first)
    }

    /// Whether the CLI is installed, recent enough and signed in, for setup and Settings › Model.
    static func status() async -> Status {
        guard let claudePath else { return Status(found: false) }
        return await Task.detached {
            var status = Status(found: true)
            // The version is asked once per install and remembered: it's a process start each time.
            if let version = ClaudeLocator.shared.version(of: claudePath, read: {
                run(claudePath, ["--version"]).map { parseVersion($0) ?? "" }
            }), !version.isEmpty {
                status.version = version
            }
            guard let output = run(claudePath, ["auth", "status"]) else {
                status.timedOut = true
                return status
            }
            let json = (try? JSONSerialization.jsonObject(with: Data(output.utf8))) as? [String: Any]
            status.signedIn = json?["loggedIn"] as? Bool ?? false
            status.plan = json?["subscriptionType"] as? String
            return status
        }.value
    }

    /// Runs the CLI for its standard output, or nil when it didn't finish within `statusTimeout` (it's stopped then).
    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Self.process(path, arguments)
        let pipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        guard (try? process.run()) != nil else { return "" }
        // Read first: a CLI that writes more than the pipe holds would never exit otherwise.
        var data = Data()
        let reading = DispatchQueue.global()
        let read = DispatchSemaphore(value: 0)
        reading.async { data = pipe.fileHandleForReading.readDataToEndOfFile(); read.signal() }
        if done.wait(timeout: .now() + statusTimeout) == .timedOut {
            process.terminate()
            return nil
        }
        read.wait()
        return String(data: data, encoding: .utf8) ?? ""
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
}

/// Stops a `claude` process on cancel or timeout, and remembers which, from any thread.
final class ProcessStopper: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var running = false
    private var cancelled = false
    private var expired = false

    init(_ process: Process) { self.process = process }

    var wasCancelled: Bool { lock.withLock { cancelled } }
    var timedOut: Bool { lock.withLock { expired } }

    /// Called once the process runs; a cancel that came first stops it now.
    func started() {
        let stopNow = lock.withLock { running = true; return cancelled }
        if stopNow { process.terminate() }
    }

    func cancel() {
        let stopNow = lock.withLock { cancelled = true; return running }
        if stopNow && process.isRunning { process.terminate() }
    }

    func timeOut() {
        let stopNow = lock.withLock { () -> Bool in
            guard running, !cancelled, process.isRunning else { return false }
            expired = true
            return true
        }
        if stopNow { process.terminate() }
    }
}

/// Finds the `claude` command. A found path is kept while it still exists; a miss is looked up again, the
/// slow login-shell lookup at most every few seconds and never on the main thread.
final class ClaudeLocator: @unchecked Sendable {
    static let shared = ClaudeLocator()

    private let lock = NSLock()
    private var found: String?
    private var lastShellLookup: Date?
    private var versions: [String: String] = [:]
    /// How long the login shell gets: a slow or interactive `.zshrc` must not hang Takes.
    static let shellTimeout: TimeInterval = 3
    static let shellRetry: TimeInterval = 4

    var known: String? { lock.withLock { found } }

    /// The CLI's version at `path`, read once with `read` and remembered; nil when `read` gave nothing.
    func version(of path: String, read: () -> String?) -> String? {
        if let cached = lock.withLock({ versions[path] }) { return cached }
        guard let version = read() else { return nil }
        lock.withLock { versions[path] = version }
        return version
    }

    func path() -> String? {
        let canAskShell: Bool = lock.withLock {
            if let found, FileManager.default.isExecutableFile(atPath: found) { return false }
            found = Self.fixedPath()
            // On the main thread, answer from what is known; a background check fills it in.
            guard found == nil, !Thread.isMainThread else { return false }
            if let last = lastShellLookup, Date().timeIntervalSince(last) < Self.shellRetry { return false }
            lastShellLookup = Date()
            return true
        }
        guard canAskShell else { return known }
        // The shell runs outside the lock, so `known` never waits on it.
        let path = Self.shellPath()
        lock.withLock { if found == nil { found = path } }
        return known
    }

    /// The environment override and the usual install places, which need no shell.
    static func fixedPath(environment: [String: String] = ProcessInfo.processInfo.environment,
                          home: String = FileManager.default.homeDirectoryForCurrentUser.path,
                          isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        if let path = environment["CLAUDE_PATH"], isExecutable(path) { return path }
        // ~/.claude/local is the older "local" install, where `claude` is only a shell alias.
        return ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first(where: isExecutable)
    }

    /// The user's login shell (fish, bash, zsh…), which is where nvm, Volta and the like are set up; /bin/zsh when
    /// it can't be told. `environment` is the override for tests.
    static func loginShell(environment: [String: String] = ProcessInfo.processInfo.environment,
                           isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String {
        var candidates: [String] = []
        if let shell = environment["SHELL"], shell.hasPrefix("/") { candidates.append(shell) }
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell.map({ String(cString: $0) }), shell.hasPrefix("/") {
            candidates.append(shell)
        }
        return candidates.first(where: isExecutable) ?? "/bin/zsh"
    }

    /// Asks the user's login shell, which knows about nvm and other version managers, and zsh if that found
    /// nothing. Each is stopped after `shellTimeout`.
    private static func shellPath() -> String? {
        let shell = loginShell()
        if let path = shellPath(shell: shell) { return path }
        return shell == "/bin/zsh" ? nil : shellPath(shell: "/bin/zsh")
    }

    private static func shellPath(shell path: String) -> String? {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: path)
        // -l -i: a login, interactive shell, so .zshrc / .bashrc / config.fish run and set PATH as they do in Terminal.
        shell.arguments = ["-l", "-i", "-c", "command -v claude"]
        let pipe = Pipe()
        shell.standardInput = FileHandle.nullDevice
        shell.standardOutput = pipe
        shell.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        shell.terminationHandler = { _ in done.signal() }
        guard (try? shell.run()) != nil else { return nil }
        if done.wait(timeout: .now() + shellTimeout) == .timedOut {
            shell.terminate()
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return parse(String(data: data, encoding: .utf8) ?? "")
    }

    /// The path in `command -v` output: the last line, or the target of an `alias claude=…`.
    static func parse(_ output: String, isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        guard var line = output.split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces) else { return nil }
        if line.hasPrefix("alias claude=") {
            line = String(line.dropFirst("alias claude=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            line = (line as NSString).expandingTildeInPath
        }
        return isExecutable(line) ? line : nil
    }
}
