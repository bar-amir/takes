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

    /// A run that prints nothing for this long is stopped, so a hung `claude` can't keep the panel spinning. Text,
    /// thinking and Claude Code's own retry notices all count as output.
    static let idleTimeout: TimeInterval = 120
    /// However much it prints, a run is stopped after this long.
    static let runTimeout: TimeInterval = 600

    /// An empty folder, so Claude Code finds no CLAUDE.md or project settings. Made again before each launch:
    /// macOS clears old files from the temporary folder.
    static func workFolder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("takes-engine", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return url
    }

    /// Skip what a rewrite doesn't need: tools, MCP servers, user settings, session files.
    var lean = true
    /// The `claude` to run, when it isn't the one found on this Mac (tests run a script that acts like it).
    var executable: String?
    var idleLimit = ClaudeCodeEngine.idleTimeout
    var runLimit = ClaudeCodeEngine.runTimeout

    func run(_ request: EngineRequest, onUpdate: @escaping @Sendable ([String]) -> Void) async throws -> EngineResult {
        guard let claudePath = executable ?? Self.claudePath else {
            throw EngineError.failed(String(localized: "Couldn't find the `claude` command. Install Claude Code, or switch to an API key in Settings › Model."))
        }

        // The system prompt (preset instructions, tone notes) goes in a file only this user can read, not in the
        // arguments, which other processes can see in `ps`. It's removed when the run ends.
        let promptFile: URL
        do {
            promptFile = try PromptFile.write(request.system)
        } catch {
            throw EngineError.failed(String(localized: "Takes couldn't prepare the request for Claude Code: \(error.localizedDescription)"))
        }
        defer { PromptFile.remove(promptFile) }

        // The user message goes in on stdin, never as an argument: as a positional argument, text starting with "-"
        // would be parsed as a CLI option (a draft of "--mcp-config=…" could start a program), and arguments are
        // visible to other processes in `ps`.
        var args = [
            "-p",
            "--system-prompt-file", promptFile.path,
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
        let idleLimit = idleLimit, runLimit = runLimit

        // Esc, closing the panel or asking again cancels the task; the process is stopped too, so it doesn't
        // keep running (and using the person's Claude plan) for a result nobody will see.
        let stop = ProcessStopper(process)
        let result: EngineResult = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: EngineError.failed(
                            String(localized: "Takes couldn't start Claude Code: \(error.localizedDescription)")))
                        return
                    }
                    stop.started()
                    stop.watch(idle: idleLimit, overall: runLimit)
                    // Written on its own queue: a long draft can fill the pipe before claude starts reading.
                    let input = stdin.fileHandleForWriting
                    // If claude exits before reading everything, the write fails instead of killing Takes with SIGPIPE.
                    _ = fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1)
                    DispatchQueue.global().async {
                        try? input.write(contentsOf: Data(request.user.utf8))
                        try? input.close()
                    }
                    // Read on its own queue too: a CLI that writes a lot of errors would otherwise block on a full
                    // pipe while Takes waits for standard output to end. Only the end is kept.
                    let errors = PipeTail(stderr.fileHandleForReading, keep: 8_000) { stop.touch() }

                    var stream = ClaudeStream()
                    var buffer = Data()
                    let reader = stdout.fileHandleForReading

                    func handle(line: Data) {
                        switch stream.read(line, elapsedMs: elapsedMs) {
                        case .text: onUpdate(TakeSplitter.split(stream.text, streaming: true))
                        case .retry(let retry): request.onRetry?(retry)
                        case .none: break
                        }
                    }

                    while true {
                        let data = reader.availableData
                        if data.isEmpty { break }
                        stop.touch()
                        buffer.append(data)
                        while let newline = buffer.firstIndex(of: 0x0A) {
                            handle(line: buffer[buffer.startIndex..<newline])
                            buffer.removeSubrange(buffer.startIndex...newline)
                        }
                    }
                    if !buffer.isEmpty { handle(line: buffer) }
                    process.waitUntilExit()
                    stop.finished()
                    let errorOutput = errors.text(waiting: 2)

                    if stop.wasCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    continuation.resume(with: Result {
                        try Self.outcome(of: stream, expired: stop.expiry, errorOutput: errorOutput,
                                         status: process.terminationStatus,
                                         signaled: process.terminationReason == .uncaughtSignal,
                                         wallMs: elapsedMs(), idleLimit: idleLimit, runLimit: runLimit)
                    })
                }
            }
        } onCancel: {
            stop.cancel()
        }
        return result
    }

    /// What a finished run comes to: takes (cut short when the model ran out of room, or when Takes stopped a run
    /// that already had whole takes), or an error that always says why.
    static func outcome(of stream: ClaudeStream, expired: ProcessStopper.Expiry?, errorOutput: String, status: Int32,
                        signaled: Bool, wallMs: Int, idleLimit: TimeInterval = idleTimeout,
                        runLimit: TimeInterval = runTimeout) throws -> EngineResult {
        if let expired {
            // The answer was done and only the CLI hung on exit: the takes are whole.
            if stream.messageStopped, !APIEngine.ranOutOfRoom(stream.stopReason) {
                let takes = TakeSplitter.split(stream.text, streaming: false)
                if !takes.isEmpty { return EngineResult(takes: takes, wallMs: wallMs, firstTextMs: stream.firstTextMs) }
            }
            if TakeSplitter.hasWholeTake(stream.text) {
                return EngineResult(takes: TakeSplitter.split(stream.text, streaming: true), wallMs: wallMs,
                                    firstTextMs: stream.firstTextMs, cutShort: true)
            }
            throw EngineError.failed(timeoutMessage(expired, idleLimit: idleLimit, runLimit: runLimit))
        }
        guard let result = stream.result else {
            throw EngineError.failed(failureMessage(errorOutput: errorOutput, stdoutNoise: stream.noise, status: status, signaled: signaled))
        }
        if result["is_error"] as? Bool == true {
            // Claude Code calls a reply that hit its output cap an error; the takes written so far still count.
            let partial = TakeSplitter.split(stream.text, streaming: true)
            if APIEngine.ranOutOfRoom(stream.stopReason), !partial.isEmpty {
                return EngineResult(takes: partial, wallMs: wallMs, firstTextMs: stream.firstTextMs, cutShort: true)
            }
            throw resultError(resultMessage(result, status: status))
        }
        let stopReason = result["stop_reason"] as? String ?? stream.stopReason
        let cutShort = APIEngine.ranOutOfRoom(stopReason)
        // The result line holds the full text; prefer it over the streamed pieces, unless the answer was cut off
        // (the streamed text is then what the model wrote).
        let text = cutShort && !stream.text.isEmpty ? stream.text : result["result"] as? String ?? stream.text
        let takes = TakeSplitter.split(text, streaming: cutShort)
        guard !takes.isEmpty else {
            throw EngineError.failed(
                cutShort ? String(localized: "Claude ran out of room before writing a take. Try again, or pick a lower effort.")
                         : String(localized: "Claude returned no takes."))
        }
        return EngineResult(takes: takes, wallMs: wallMs, firstTextMs: stream.firstTextMs, cutShort: cutShort)
    }

    static func timeoutMessage(_ expiry: ProcessStopper.Expiry, idleLimit: TimeInterval = idleTimeout,
                               runLimit: TimeInterval = runTimeout) -> String {
        switch expiry {
        case .idle:
            let minutes = max(1, Int((idleLimit / 60).rounded()))
            return minutes == 1
                ? String(localized: "Claude Code stopped answering for a minute, so Takes stopped it. Try again, or pick another engine.")
                : String(localized: "Claude Code stopped answering for \(minutes) minutes, so Takes stopped it. Try again, or pick another engine.")
        case .overall:
            let minutes = max(1, Int((runLimit / 60).rounded()))
            return String(localized: "Claude Code was still writing after \(minutes) minutes, so Takes stopped it. Try a shorter draft, or another engine.")
        }
    }

    /// Why a run ended without a result: the CLI's own words (its error output, or a stray line on standard
    /// output), else its exit status. Never empty.
    static func failureMessage(errorOutput: String, stdoutNoise: String, status: Int32, signaled: Bool) -> String {
        for output in [errorOutput, stdoutNoise] {
            let detail = String(output.trimmingCharacters(in: .whitespacesAndNewlines).suffix(400))
            guard !detail.isEmpty else { continue }
            if isOutOfDate(detail) { return outOfDateMessage }
            if isSignInProblem(detail) { return signedOutMessage }
            return String(localized: "Claude Code failed: \(detail)")
        }
        if signaled {
            return String(localized: "Claude Code was stopped (signal \(status)) before it answered. Try again, or pick another engine in Settings › Model.")
        }
        return String(localized: "Claude Code quit without an answer (exit status \(status)). Try again, or pick another engine in Settings › Model.")
    }

    /// The words of a result line with `is_error`: its `result`, else its `errors`, else its `subtype`, else the
    /// exit status. Never empty.
    static func resultMessage(_ result: [String: Any], status: Int32) -> String {
        if let text = (result["result"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
        let errors = (result["errors"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !errors.isEmpty { return errors.joined(separator: "; ") }
        if let subtype = result["subtype"] as? String, !subtype.isEmpty, subtype != "success" {
            return String(localized: "it stopped with “\(subtype)”")
        }
        return String(localized: "it reported an error without saying what (exit status \(status))")
    }

    /// A `{"type":"system","subtype":"api_retry",…}` line: Claude Code is waiting to try the request again.
    static func retry(from json: [String: Any]) -> EngineRetry? {
        guard json["type"] as? String == "system", json["subtype"] as? String == "api_retry" else { return nil }
        return EngineRetry(attempt: json["attempt"] as? Int ?? 1, maxAttempts: json["max_retries"] as? Int,
                           status: json["error_status"] as? Int)
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
        return when.isEmpty ? nil : resetSentence(when)
    }

    /// "3pm" → "It resets at 3pm.", "Nov 9, 10am (Europe/London)" → "It resets on Nov 9 at 10am (Europe/London).",
    /// "Monday" → "It resets on Monday.", "in 2 hours" → "It resets in 2 hours."
    static func resetSentence(_ when: String) -> String {
        let lower = when.lowercased()
        if ["at ", "on ", "in ", "tomorrow", "today", "tonight"].contains(where: lower.hasPrefix) {
            return String(localized: "It resets \(when).")
        }
        if when.first?.isNumber == true { return String(localized: "It resets at \(when).") }
        if let comma = when.range(of: ", "), when[comma.upperBound...].first?.isNumber == true {
            let day = String(when[..<comma.lowerBound]), time = String(when[comma.upperBound...])
            return String(localized: "It resets on \(day) at \(time).")
        }
        return String(localized: "It resets on \(when).")
    }

    /// Shown instead of the CLI's own wording when the login is the problem. Plain words, no commands: the
    /// panel puts a "Sign in to Claude" button under it. The Claude desktop app keeps its own sign-in, so
    /// it can still work while this one has expired; say so, or the message looks wrong.
    static let signedOutMessage = String(localized: "Takes got signed out of Claude. Sign in again to keep going. This sign-in is separate from the Claude app, so it can expire even while the app still works.")

    /// The CLI's error, in words a person can act on. A sign-in problem (not signed in, or a session that
    /// expired and couldn't be refreshed: "Failed to authenticate: OAuth session expired…") becomes
    /// `signedOutMessage`; anything else keeps the CLI's wording.
    static func errorMessage(_ message: String) -> String {
        if isSignInProblem(message) { return signedOutMessage }
        if isOutOfDate(message) { return outOfDateMessage }
        return String(localized: "Claude Code: \(message)")
    }

    /// An old CLI rejects a flag Takes passes ("error: unknown option '--effort'").
    static let outOfDateMessage = String(localized: "This version of Claude Code is too old for Takes. Update it (run `claude update` in Terminal), or pick another engine in Settings › Model.")

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

    /// What the sign-in window runs. Its messages are in the app's language, quoted for the shell.
    static func signInScript(claudePath: String) -> String {
        func quoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let intro = quoted(String(localized: "Signing Takes in to Claude. Finish in the browser window that opens, then go back to Takes."))
        let done = quoted(String(localized: "You can close this window now."))
        return """
            #!/bin/zsh
            clear
            echo \(intro)
            echo
            \(signInCommand(claudePath: claudePath))
            echo
            echo \(done)
            """
    }

    /// What `status()` found out about the CLI.
    struct Status: Equatable {
        var found: Bool
        var signedIn = false
        var plan: String?
        /// "2.1.310", or nil when the CLI didn't say.
        var version: String?
        /// `claude auth status` didn't answer within `statusTimeout`, or (not found) looking for `claude` ran out
        /// of time; either way nothing is known yet. Also set when the CLI couldn't be started (`launchError`), so a
        /// check that doesn't know that field says "didn't answer" rather than "not signed in".
        var timedOut = false
        /// The CLI is there but couldn't be started (it isn't executable, or macOS refused): why, in words.
        var launchError: String? = nil

        enum State: Equatable {
            /// No `claude` on this Mac.
            case notInstalled
            /// Looking for `claude` through the login shell ran out of time; Takes keeps looking.
            case stillLooking
            /// `claude` is there but couldn't be started; the message says why.
            case couldNotStart(String)
            /// `claude auth status` didn't answer in time.
            case notAnswering
            /// Older than `minimumVersion`.
            case tooOld(String)
            case signedOut
            case ready
        }

        /// What setup and Settings › Model should say, with "not installed", "still looking", "couldn't start" and
        /// "didn't answer" kept apart from "signed out".
        var state: State {
            if !found { return timedOut ? .stillLooking : .notInstalled }
            if let launchError { return .couldNotStart(launchError) }
            if timedOut { return .notAnswering }
            if let version, !ClaudeCodeEngine.isSupported(version: version) { return .tooOld(version) }
            return signedIn ? .ready : .signedOut
        }

        /// One short line for `state`, or nil when ready.
        var problem: String? {
            switch state {
            case .notInstalled: String(localized: "Claude Code isn't installed")
            case .stillLooking: String(localized: "Still looking for Claude Code")
            case .couldNotStart(let reason): reason
            case .notAnswering: String(localized: "Claude Code didn't answer")
            case .tooOld(let version): String(localized: "Claude Code \(version) is too old; update it (claude update)")
            case .signedOut: String(localized: "Claude Code isn't signed in")
            case .ready: nil
            }
        }
    }

    /// `claude auth status` and `claude --version` get this long each. A hung CLI must not stop setup from showing.
    static let statusTimeout: TimeInterval = 15

    /// The oldest CLI that knows every model Takes offers: Opus 5.5 arrived in 2.1.280, Sonnet 5.5 in 2.1.284 and
    /// Haiku 5.5 (the default for tone notes) in 2.1.293. Everything else Takes uses is older: `--system-prompt-file`
    /// (1.0.55), `claude auth status` (2.1.41), `--effort` and `--setting-sources`.
    static let minimumVersion = "2.1.293"

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
        guard let claudePath else { return Status(found: false, timedOut: ClaudeLocator.shared.lastLookupTimedOut) }
        return await Task.detached { status(of: claudePath) }.value
    }

    /// `status()` for the CLI at `path`.
    static func status(of path: String, timeout: TimeInterval = statusTimeout) -> Status {
        var status = Status(found: true)
        // The version is asked once per install and remembered: it's a process start each time. A run that
        // couldn't start or didn't finish isn't remembered.
        if let version = ClaudeLocator.shared.version(of: path, read: {
            if case .output(let output) = run(path, ["--version"], timeout: timeout) { return parseVersion(output) ?? "" }
            return nil
        }), !version.isEmpty {
            status.version = version
        }
        // No user or project settings, as for a run: their hooks mustn't run, and the answer should be what a run sees.
        switch run(path, ["--setting-sources", "", "auth", "status"], timeout: timeout) {
        case .timedOut:
            status.timedOut = true
        case .couldNotStart(let reason):
            status.timedOut = true
            status.launchError = String(localized: "Takes couldn't start Claude Code: \(reason)")
        case .output(let output):
            let json = (try? JSONSerialization.jsonObject(with: Data(output.utf8))) as? [String: Any]
            status.signedIn = json?["loggedIn"] as? Bool ?? false
            status.plan = json?["subscriptionType"] as? String
        }
        return status
    }

    enum RunOutcome: Equatable {
        case output(String)
        /// Didn't finish within the timeout, and was stopped.
        case timedOut
        /// The process couldn't be started; why.
        case couldNotStart(String)
    }

    /// Runs the CLI for its standard output. One that doesn't finish within `timeout` is stopped.
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = statusTimeout) -> RunOutcome {
        let process = Self.process(path, arguments)
        let pipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do {
            try process.run()
        } catch {
            return .couldNotStart(error.localizedDescription)
        }
        // Read as it comes: a CLI that writes more than the pipe holds would never exit otherwise.
        let output = PipeTail(pipe.fileHandleForReading, keep: 1_000_000)
        if done.wait(timeout: .now() + timeout) == .timedOut {
            ProcessStopper.kill(process)
            return .timedOut
        }
        return .output(output.text(waiting: 2))
    }

    static func process(_ path: String, _ arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.currentDirectoryURL = workFolder()
        var env = ProcessInfo.processInfo.environment
        // Apps launched from Finder get a bare PATH; keep claude's own folder on it.
        let claudeDir = (path as NSString).deletingLastPathComponent
        env["PATH"] = "\(claudeDir):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        process.environment = env
        return process
    }
}

/// What a `claude -p --output-format stream-json` run has said so far.
struct ClaudeStream {
    enum Event: Equatable {
        /// More text arrived.
        case text
        /// Claude Code is waiting to try the request again.
        case retry(EngineRetry)
    }

    var text = ""
    var firstTextMs: Int?
    /// The `result` line.
    var result: [String: Any]?
    /// Why the model stopped ("end_turn", "max_tokens"), from the stream's `message_delta`.
    var stopReason: String?
    /// The model finished its message (`message_stop`).
    var messageStopped = false
    /// The last line that wasn't JSON: some errors are printed on standard output.
    var noise = ""

    mutating func read(_ line: Data, elapsedMs: () -> Int) -> Event? {
        guard let json = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
            let plain = String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !plain.isEmpty { noise = String(plain.prefix(400)) }
            return nil
        }
        switch json["type"] as? String {
        case "stream_event":
            guard let event = json["event"] as? [String: Any] else { return nil }
            switch event["type"] as? String {
            case "content_block_delta":
                guard let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                      let chunk = delta["text"] as? String else { return nil }
                if firstTextMs == nil { firstTextMs = elapsedMs() }
                text += chunk
                return .text
            case "message_delta":
                if let reason = (event["delta"] as? [String: Any])?["stop_reason"] as? String { stopReason = reason }
            case "message_stop":
                messageStopped = true
            default:
                break
            }
            return nil
        case "system":
            // Claude Code retries a rate-limited or overloaded request on its own, for a minute or more, and says
            // so only here.
            return ClaudeCodeEngine.retry(from: json).map { .retry($0) }
        case "result":
            result = json
            return nil
        default:
            return nil
        }
    }
}

/// The system prompt for one `claude` run, in a file only this user can read (0600) in a folder only this user can
/// open (0700). It's passed with `--system-prompt-file`, so the prompt never shows in `ps`, and removed afterwards.
enum PromptFile {
    static var folder: URL { FileManager.default.temporaryDirectory.appendingPathComponent("takes-prompts", isDirectory: true) }

    static func write(_ text: String, in folder: URL = folder) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        removeStale(in: folder)
        let url = folder.appendingPathComponent(UUID().uuidString + ".txt")
        // Made with its permissions in one step, and never an existing file (O_EXCL), before a byte is written.
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
        } catch {
            remove(url)
            throw error
        }
        return url
    }

    static func remove(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    /// Prompt files a crash left behind.
    static func removeStale(in folder: URL, olderThan age: TimeInterval = 3600) {
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.pathExtension == "txt" {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture
            if Date().timeIntervalSince(modified) > age { try? manager.removeItem(at: file) }
        }
    }
}

/// Reads a pipe to its end on its own thread, keeping only the last `keep` bytes, so the writer never blocks on a full
/// pipe while Takes waits for something else.
final class PipeTail: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let keep: Int
    private let group = DispatchGroup()

    init(_ handle: FileHandle, keep: Int, onData: @escaping @Sendable () -> Void = {}) {
        self.keep = keep
        group.enter()
        DispatchQueue.global().async { [self] in
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                onData()
                lock.withLock {
                    data.append(chunk)
                    if data.count > keep * 2 { data = Data(data.suffix(keep)) }
                }
            }
            group.leave()
        }
    }

    /// What was read, after waiting up to `seconds` for the end: a process the writer started can keep the pipe open
    /// after the writer itself has exited, and that mustn't hold Takes up.
    func text(waiting seconds: TimeInterval) -> String {
        _ = group.wait(timeout: .now() + seconds)
        return lock.withLock { String(decoding: data.suffix(keep), as: UTF8.self) }
    }
}

/// Stops a `claude` process on cancel or timeout, and remembers which, from any thread.
final class ProcessStopper: @unchecked Sendable {
    /// Why a run was stopped for time.
    enum Expiry: Equatable {
        /// No output for the idle limit.
        case idle
        /// The overall limit.
        case overall
    }

    private let process: Process
    private let lock = NSLock()
    private var running = false
    private var cancelled = false
    private var expired: Expiry?
    private var lastOutput = Date()
    private var timer: DispatchSourceTimer?

    init(_ process: Process) { self.process = process }

    var wasCancelled: Bool { lock.withLock { cancelled } }
    var timedOut: Bool { lock.withLock { expired != nil } }
    var expiry: Expiry? { lock.withLock { expired } }

    /// Called once the process runs; a cancel that came first stops it now.
    func started() {
        let stopNow = lock.withLock { running = true; return cancelled }
        if stopNow { Self.kill(process) }
    }

    func cancel() {
        let stopNow = lock.withLock { cancelled = true; return running }
        if stopNow && process.isRunning { Self.kill(process) }
    }

    /// Stops it for running out of time (the caller's own deadline).
    func timeOut() { timeOut(.overall) }

    func timeOut(_ why: Expiry) {
        let stopNow = lock.withLock { () -> Bool in
            guard running, !cancelled, expired == nil, process.isRunning else { return false }
            expired = why
            return true
        }
        if stopNow { Self.kill(process) }
    }

    /// The process wrote something: the idle clock starts again.
    func touch() { lock.withLock { lastOutput = Date() } }

    /// Stops the process after `idle` seconds without output (see `touch`) or `overall` seconds in all.
    func watch(idle: TimeInterval, overall: TimeInterval) {
        let start = Date()
        let tick = max(0.05, min(1, idle / 4, overall / 4))
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + tick, repeating: tick)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let quiet = self.lock.withLock { Date().timeIntervalSince(self.lastOutput) }
            if Date().timeIntervalSince(start) >= overall {
                self.timeOut(.overall)
            } else if quiet >= idle {
                self.timeOut(.idle)
            }
        }
        lock.withLock {
            lastOutput = start
            self.timer = timer
        }
        timer.resume()
    }

    /// The process has ended: no more checks.
    func finished() {
        let timer = lock.withLock { () -> DispatchSourceTimer? in
            defer { self.timer = nil }
            return self.timer
        }
        timer?.cancel()
    }

    /// Asks the process to stop (SIGTERM). If it's still there a moment later, it and everything it started (its
    /// process group: `Process` starts each child in a group of its own) are killed, so nothing keeps a pipe open.
    static func kill(_ process: Process, grace: TimeInterval = 2) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + grace) {
            guard process.isRunning else { return }
            Darwin.kill(-pid, SIGKILL)
            Darwin.kill(pid, SIGKILL)
        }
    }
}

/// Finds the `claude` command. A found path is kept while it still exists, and remembered for the next launch;
/// a miss is looked up again, the slow login-shell lookup at most every few seconds and never on the main thread.
final class ClaudeLocator: @unchecked Sendable {
    static let shared = ClaudeLocator(remember: .standard)

    /// Where a path found through the shell is kept between launches. Installed with nvm or Volta, `claude` is
    /// only found by a login shell, which can take more than `shellTimeout` on a busy Mac (right after an update);
    /// with the path kept, a launch needs no shell at all. A path, not a secret.
    static let rememberedKey = "claudeCodePath"

    private let defaults: UserDefaults?
    private let fixed: () -> String?
    private let lookup: () -> (path: String?, timedOut: Bool)
    private let isExecutable: (String) -> Bool

    private let lock = NSLock()
    /// Held for a whole shell lookup, so a check that arrives meanwhile waits for its answer instead of being
    /// told Claude Code isn't there.
    private let lookupLock = NSLock()
    private var found: String?
    private var lastShellLookup: Date?
    private var lookupTimedOut = false
    private var versions: [String: String] = [:]

    init(remember defaults: UserDefaults? = nil,
         fixed: @escaping () -> String? = { ClaudeLocator.fixedPath() },
         lookup: @escaping () -> (path: String?, timedOut: Bool) = { ClaudeLocator.shellPath() },
         isExecutable: @escaping (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) {
        self.defaults = defaults
        self.fixed = fixed
        self.lookup = lookup
        self.isExecutable = isExecutable
    }
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

    /// Whether the last shell lookup ran out of time, rather than finding no `claude`.
    var lastLookupTimedOut: Bool { lock.withLock { lookupTimedOut } }

    func path() -> String? {
        if let path = lock.withLock({ withoutShell() }) { return path }
        // On the main thread, answer from what is known; a background check fills it in.
        guard !Thread.isMainThread else { return nil }
        lookupLock.lock()
        defer { lookupLock.unlock() }
        let ask: Bool = lock.withLock {
            // Found by the lookup this call waited for.
            if withoutShell() != nil { return false }
            if let last = lastShellLookup, Date().timeIntervalSince(last) < Self.shellRetry { return false }
            lastShellLookup = Date()
            return true
        }
        guard ask else { return known }
        // The shell runs outside `lock`, so `known` never waits on it.
        let result = lookup()
        lock.withLock {
            lookupTimedOut = result.path == nil && result.timedOut
            if found == nil { found = result.path }
        }
        if let path = result.path { defaults?.set(path, forKey: Self.rememberedKey) }
        return known
    }

    /// The path already found while it still exists, else the usual install places, else the one remembered from
    /// an earlier launch. Call with `lock` held.
    private func withoutShell() -> String? {
        if let found, isExecutable(found) { return found }
        found = fixed() ?? defaults?.string(forKey: Self.rememberedKey).flatMap { isExecutable($0) ? $0 : nil }
        return found
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
    /// Nil with `timedOut` when a shell ran out of time, so "not installed" isn't said of a slow shell.
    static func shellPath() -> (path: String?, timedOut: Bool) {
        let shell = loginShell()
        let first = shellPath(shell: shell)
        if first.path != nil || shell == "/bin/zsh" { return first }
        let zsh = shellPath(shell: "/bin/zsh")
        return (zsh.path, first.timedOut || zsh.timedOut)
    }

    /// One shell's answer. It runs while `lookupLock` is held, so it must always end: the output is read as it comes
    /// (a chatty `.zshrc` can't fill the pipe and stall the shell), a shell that runs out of time is killed with
    /// everything it started (an interactive shell ignores SIGTERM), and a program it left running with the pipe
    /// open can't keep Takes waiting.
    static func shellPath(shell path: String, arguments: [String] = ["-l", "-i", "-c", "command -v claude"],
                          timeout: TimeInterval = shellTimeout) -> (path: String?, timedOut: Bool) {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: path)
        // -l -i: a login, interactive shell, so .zshrc / .bashrc / config.fish run and set PATH as they do in Terminal.
        shell.arguments = arguments
        let pipe = Pipe()
        shell.standardInput = FileHandle.nullDevice
        shell.standardOutput = pipe
        shell.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        shell.terminationHandler = { _ in done.signal() }
        guard (try? shell.run()) != nil else { return (nil, false) }
        // `command -v` prints one line; only the end of a long output matters.
        let output = PipeTail(pipe.fileHandleForReading, keep: 64_000)
        if done.wait(timeout: .now() + timeout) == .timedOut {
            ProcessStopper.kill(shell, grace: 0.5)
            return (nil, true)
        }
        return (parse(output.text(waiting: 0.5)), false)
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
