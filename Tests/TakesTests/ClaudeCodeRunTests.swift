import XCTest
@testable import Takes

/// `ClaudeCodeEngine` against shell scripts that act like `claude -p --output-format stream-json`: no real CLI, no
/// model call, no account.
final class ClaudeCodeRunTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("claude-fake-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A fake `claude`: saves its arguments and a copy of the prompt file with its mode, then runs `body`.
    private func fakeClaude(_ body: String) throws -> String {
        let script = folder.appendingPathComponent("claude")
        let text = """
            #!/bin/sh
            dir='\(folder.path)'
            printf '%s\\n' "$@" > "$dir/args"
            if [ "$2" = "--system-prompt-file" ]; then cp "$3" "$dir/prompt"; stat -f %Lp "$3" > "$dir/mode"; fi
            cat > "$dir/stdin" &
            \(body)
            """
        try text.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script.path
    }

    private static func delta(_ text: String) -> String {
        let json = try! JSONSerialization.data(withJSONObject: [
            "type": "stream_event",
            "event": ["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": text]],
        ])
        return "printf '%s\\n' '\(String(decoding: json, as: UTF8.self))'"
    }

    private static func line(_ json: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: json)
        return "printf '%s\\n' '\(String(decoding: data, as: UTF8.self))'"
    }

    private static func result(_ text: String, isError: Bool = false) -> String {
        line(["type": "result", "subtype": isError ? "error_during_execution" : "success", "is_error": isError, "result": text])
    }

    private static let request = EngineRequest(system: "SECRET PRESET INSTRUCTIONS", user: "<draft>\nhi\n</draft>", takes: 2,
                                               model: Models.sonnet, effort: "low")

    private func engine(_ path: String, idle: TimeInterval = 10, overall: TimeInterval = 20) -> ClaudeCodeEngine {
        var engine = ClaudeCodeEngine()
        engine.executable = path
        engine.idleLimit = idle
        engine.runLimit = overall
        return engine
    }

    private func failure(_ engine: ClaudeCodeEngine, file: StaticString = #filePath, line: UInt = #line) async -> String {
        do {
            _ = try await engine.run(Self.request) { _ in }
            XCTFail("should fail", file: file, line: line)
            return ""
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: A normal run, and the system prompt kept out of the arguments

    func testStreamsTakesAndKeepsThePromptOutOfTheArguments() async throws {
        let path = try fakeClaude([
            Self.delta("Thursday works.\n==="), Self.delta("\nSure, Thursday."),
            Self.line(["type": "stream_event", "event": ["type": "message_delta", "delta": ["stop_reason": "end_turn"]]]),
            Self.line(["type": "stream_event", "event": ["type": "message_stop"]]),
            Self.result("Thursday works.\n===\nSure, Thursday."),
        ].joined(separator: "\n"))
        let result = try await engine(path).run(Self.request) { _ in }
        XCTAssertEqual(result.takes, ["Thursday works.", "Sure, Thursday."])
        XCTAssertFalse(result.cutShort)

        let args = try String(contentsOf: folder.appendingPathComponent("args"), encoding: .utf8)
        XCTAssertFalse(args.contains("SECRET"), "the system prompt is in the arguments: \(args)")
        XCTAssertFalse(args.contains("--system-prompt\n"), args)
        let lines = args.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let promptPath = try XCTUnwrap(lines.firstIndex(of: "--system-prompt-file").map { lines[$0 + 1] })
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("prompt"), encoding: .utf8), "SECRET PRESET INSTRUCTIONS")
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("mode"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), "600")
        // Removed once the run is over.
        XCTAssertFalse(FileManager.default.fileExists(atPath: promptPath))
        // Lean runs still skip settings, tools and MCP servers.
        for flag in ["--setting-sources", "--strict-mcp-config", "--tools", "--no-session-persistence"] {
            XCTAssertTrue(lines.contains(flag), "\(flag) missing")
        }
    }

    func testWorkFolderIsMadeAgainIfMacOSCleanedIt() async throws {
        try? FileManager.default.removeItem(at: ClaudeCodeEngine.workFolder())
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("takes-engine"))
        let path = try fakeClaude(Self.result("Thursday works."))
        let result = try await engine(path).run(Self.request) { _ in }
        XCTAssertEqual(result.takes, ["Thursday works."])
        var isFolder: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: ClaudeCodeEngine.workFolder().path, isDirectory: &isFolder))
        XCTAssertTrue(isFolder.boolValue)
    }

    // MARK: Cut short

    func testMaxTokensKeepsTheTakesAndSaysCutShort() async throws {
        let path = try fakeClaude([
            Self.delta("Thursday works.\n===\nSure, Thurs"),
            Self.line(["type": "stream_event", "event": ["type": "message_delta", "delta": ["stop_reason": "max_tokens"]]]),
            Self.result("Thursday works.\n===\nSure, Thurs"),
        ].joined(separator: "\n"))
        let result = try await engine(path).run(Self.request) { _ in }
        XCTAssertEqual(result.takes, ["Thursday works.", "Sure, Thurs"])
        XCTAssertTrue(result.cutShort)
    }

    func testAnErrorAfterTheOutputCapKeepsTheTakes() async throws {
        let path = try fakeClaude([
            Self.delta("Thursday works.\n===\nSure, Thurs"),
            Self.line(["type": "stream_event", "event": ["type": "message_delta", "delta": ["stop_reason": "max_tokens"]]]),
            Self.result("API Error: the response exceeded the 32000 output token maximum.", isError: true),
        ].joined(separator: "\n"))
        let result = try await engine(path).run(Self.request) { _ in }
        XCTAssertEqual(result.takes, ["Thursday works.", "Sure, Thurs"])
        XCTAssertTrue(result.cutShort)
    }

    func testIdleTimeoutAfterWholeTakesReturnsThemCutShort() async throws {
        let path = try fakeClaude([Self.delta("Thursday works.\n===\nSure, Thu"), "exec sleep 30"].joined(separator: "\n"))
        let started = Date()
        let result = try await engine(path, idle: 2).run(Self.request) { _ in }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        XCTAssertEqual(result.takes, ["Thursday works.", "Sure, Thu"])
        XCTAssertTrue(result.cutShort)
    }

    func testIdleTimeoutWithoutAWholeTakeFails() async throws {
        let path = try fakeClaude([Self.delta("Thursday wor"), "exec sleep 30"].joined(separator: "\n"))
        let message = await failure(engine(path, idle: 2))
        XCTAssertTrue(message.contains("stopped answering"), message)
    }

    func testOutputKeepsAnIdleRunAliveUntilTheOverallLimit() async throws {
        // A delta every 0.2 s: never idle for 2 s, so only the 3 s overall limit stops it.
        let path = try fakeClaude([Self.delta("One.\n===\n"), "while true; do \(Self.delta("x")); sleep 0.2; done"].joined(separator: "\n"))
        let started = Date()
        let result = try await engine(path, idle: 2, overall: 3).run(Self.request) { _ in }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 2.9)
        XCTAssertTrue(result.cutShort)
        XCTAssertEqual(result.takes.first, "One.")
    }

    func testAFinishedAnswerIsWholeEvenIfTheCLIHangsOnExit() async throws {
        let path = try fakeClaude([
            Self.delta("Thursday works.\n===\nSure, Thursday."),
            Self.line(["type": "stream_event", "event": ["type": "message_delta", "delta": ["stop_reason": "end_turn"]]]),
            Self.line(["type": "stream_event", "event": ["type": "message_stop"]]),
            "exec sleep 30",
        ].joined(separator: "\n"))
        let result = try await engine(path, idle: 2).run(Self.request) { _ in }
        XCTAssertEqual(result.takes, ["Thursday works.", "Sure, Thursday."])
        XCTAssertFalse(result.cutShort)
    }

    func testATermIgnoringCLIIsStillStopped() async throws {
        let path = try fakeClaude([Self.delta("Thursday works.\n===\n"), "trap '' TERM", "while true; do sleep 1; done"].joined(separator: "\n"))
        let started = Date()
        let result = try await engine(path, idle: 2).run(Self.request) { _ in }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        XCTAssertTrue(result.cutShort)
    }

    func testCancelStopsTheRun() async throws {
        let path = try fakeClaude([Self.delta("Thurs"), "exec sleep 30"].joined(separator: "\n"))
        let task = Task { try await engine(path).run(Self.request) { _ in } }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("should be cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }

    // MARK: Errors always say why

    func testSilentExitGivesTheExitStatus() async throws {
        let message = await failure(engine(try fakeClaude("exit 3")))
        XCTAssertEqual(message, "Claude Code quit without an answer (exit status 3). Try again, or pick another engine in Settings › Model.")
    }

    func testErrorOutputIsQuoted() async throws {
        let message = await failure(engine(try fakeClaude("echo 'Error: something broke' >&2; exit 1")))
        XCTAssertEqual(message, "Claude Code failed: Error: something broke")
    }

    func testPlainTextOnStandardOutputIsQuoted() async throws {
        let message = await failure(engine(try fakeClaude("echo 'Invalid model name'; exit 1")))
        XCTAssertEqual(message, "Claude Code failed: Invalid model name")
    }

    func testEmptyErrorResultStillSaysSomething() async throws {
        let message = await failure(engine(try fakeClaude(Self.result("", isError: true))))
        XCTAssertEqual(message, "Claude Code: it stopped with “error_during_execution”")
    }

    func testLotsOfErrorOutputDoesNotStallTheRun() async throws {
        // 300 KB on standard error before the answer: more than a pipe holds.
        let path = try fakeClaude(["i=0; while [ $i -lt 3000 ]; do printf '%0100d\\n' 0 >&2; i=$((i+1)); done",
                                   Self.result("Thursday works.")].joined(separator: "\n"))
        let result = try await engine(path, idle: 5).run(Self.request) { _ in }
        XCTAssertEqual(result.takes, ["Thursday works."])
    }

    func testOutcomeMessages() {
        let signaled = "Claude Code was stopped (signal 9) before it answered. Try again, or pick another engine in Settings › Model."
        XCTAssertEqual(ClaudeCodeEngine.failureMessage(errorOutput: " \n", stdoutNoise: "", status: 9, signaled: true), signaled)
        let oldCLI = "error: unknown option '--system-prompt-file'"
        XCTAssertEqual(ClaudeCodeEngine.failureMessage(errorOutput: oldCLI, stdoutNoise: "", status: 1, signaled: false),
                       ClaudeCodeEngine.outOfDateMessage)
        let signedOut = "Not logged in · Please run /login"
        XCTAssertEqual(ClaudeCodeEngine.failureMessage(errorOutput: signedOut, stdoutNoise: "", status: 1, signaled: false),
                       ClaudeCodeEngine.signedOutMessage)
        XCTAssertEqual(ClaudeCodeEngine.resultMessage(["is_error": true, "errors": ["", "Overloaded"]], status: 1), "Overloaded")
        XCTAssertEqual(ClaudeCodeEngine.resultMessage(["is_error": true, "result": ""], status: 2),
                       "it reported an error without saying what (exit status 2)")
        let idle = "Claude Code stopped answering for 2 minutes, so Takes stopped it. Try again, or pick another engine."
        XCTAssertEqual(ClaudeCodeEngine.timeoutMessage(.idle, idleLimit: 120), idle)
        let overall = "Claude Code was still writing after 10 minutes, so Takes stopped it. Try a shorter draft, or another engine."
        XCTAssertEqual(ClaudeCodeEngine.timeoutMessage(.overall, runLimit: 600), overall)
    }

    // MARK: Status

    func testStatusReadsVersionAndSignInWithoutUserSettings() throws {
        let path = try fakeClaude("""
            case "$*" in
              --version) echo '2.1.310 (Claude Code)' ;;
              *"auth status"*) echo '{"loggedIn": true, "subscriptionType": "max"}' ;;
            esac
            """)
        let status = ClaudeCodeEngine.status(of: path, timeout: 5)
        XCTAssertEqual(status.version, "2.1.310")
        XCTAssertTrue(status.signedIn)
        XCTAssertEqual(status.plan, "max")
        XCTAssertEqual(status.state, .ready)
        XCTAssertNil(status.problem)
        let args = try String(contentsOf: folder.appendingPathComponent("args"), encoding: .utf8)
        XCTAssertEqual(args, "--setting-sources\n\nauth\nstatus\n")
    }

    func testStatusThatCannotStartIsNotSignedOut() throws {
        let file = folder.appendingPathComponent("claude")
        try "not a program".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        let status = ClaudeCodeEngine.status(of: file.path, timeout: 5)
        XCTAssertTrue(status.found)
        XCTAssertNotNil(status.launchError)
        XCTAssertTrue(status.timedOut, "older checks must say 'didn't answer', not 'signed out'")
        guard case .couldNotStart(let reason) = status.state else { return XCTFail("\(status.state)") }
        XCTAssertTrue(reason.hasPrefix("Takes couldn't start Claude Code: "), reason)
        XCTAssertEqual(status.problem, reason)
        XCTAssertNil(status.version)
    }

    func testStatusThatHangsIsNotAnswering() throws {
        let path = try fakeClaude("exec sleep 30")
        let started = Date()
        let status = ClaudeCodeEngine.status(of: path, timeout: 0.5)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertEqual(status.state, .notAnswering)
        XCTAssertEqual(status.problem, "Claude Code didn't answer")
    }

    func testStatesKeepNotFoundAndStillLookingApart() {
        typealias S = ClaudeCodeEngine.Status
        XCTAssertEqual(S(found: false).state, .notInstalled)
        XCTAssertEqual(S(found: false, timedOut: true).state, .stillLooking)
        XCTAssertEqual(S(found: true, signedIn: false, version: "2.1.310").state, .signedOut)
        XCTAssertEqual(S(found: true, signedIn: true, version: "2.1.280").state, .tooOld("2.1.280"))
        XCTAssertEqual(S(found: false).problem, "Claude Code isn't installed")
        XCTAssertEqual(S(found: false, timedOut: true).problem, "Still looking for Claude Code")
    }

    func testMinimumVersionKnowsEveryModelTakesOffers() {
        // Haiku 5.5 arrived in 2.1.293, Sonnet 5.5 in 2.1.284, Opus 5.5 in 2.1.280.
        XCTAssertTrue(ClaudeCodeEngine.isSupported(version: "2.1.293"))
        XCTAssertFalse(ClaudeCodeEngine.isSupported(version: "2.1.292"))
        XCTAssertFalse(ClaudeCodeEngine.isSupported(version: "2.1.41"))
    }

    // MARK: Prompt files

    func testPromptFileIsPrivateAndStaleOnesAreRemoved() throws {
        let prompts = folder.appendingPathComponent("prompts", isDirectory: true)
        let first = try PromptFile.write("Be brief.", in: prompts)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "Be brief.")
        let fileMode = try FileManager.default.attributesOfItem(atPath: first.path)[.posixPermissions] as? Int
        let folderMode = try FileManager.default.attributesOfItem(atPath: prompts.path)[.posixPermissions] as? Int
        XCTAssertEqual(fileMode, 0o600)
        XCTAssertEqual(folderMode, 0o700)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: first.path)
        let second = try PromptFile.write("Again.", in: prompts)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        PromptFile.remove(second)
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
    }

    // MARK: Whole takes

    func testWholeTakeNeedsAFinishedSeparator() {
        XCTAssertFalse(TakeSplitter.hasWholeTake("Thursday works."))
        XCTAssertFalse(TakeSplitter.hasWholeTake("Thursday works.\n==="))
        XCTAssertFalse(TakeSplitter.hasWholeTake("===\nThursday"))
        XCTAssertTrue(TakeSplitter.hasWholeTake("Thursday works.\n===\n"))
        XCTAssertTrue(TakeSplitter.hasWholeTake("Thursday works.\n===\nSure"))
    }
}

/// The login-shell lookup runs while a lock is held, so it must always end.
final class ShellLookupTests: XCTestCase {
    func testLongShellOutputDoesNotLookLikeATimeout() {
        // 200 KB from a chatty .zshrc, then the path: more than a pipe holds before the shell can exit.
        let script = "i=0; while [ $i -lt 2000 ]; do printf '%0100d\\n' 0; i=$((i+1)); done; echo /bin/ls"
        let result = ClaudeLocator.shellPath(shell: "/bin/sh", arguments: ["-c", script], timeout: 5)
        XCTAssertEqual(result.path, "/bin/ls")
        XCTAssertFalse(result.timedOut)
    }

    func testAShellThatIgnoresTermIsKilled() throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("shell-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }
        let script = "trap '' TERM; echo $$ > '\(marker.path)'; while true; do sleep 1; done"
        let started = Date()
        let result = ClaudeLocator.shellPath(shell: "/bin/sh", arguments: ["-c", script], timeout: 0.5)
        XCTAssertTrue(result.timedOut)
        XCTAssertNil(result.path)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        let pid = try XCTUnwrap(Int32(String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        let gone = expectation(description: "shell killed")
        DispatchQueue.global().async {
            for _ in 0..<50 where kill(pid, 0) == 0 { Thread.sleep(forTimeInterval: 0.1) }
            if kill(pid, 0) != 0 { gone.fulfill() }
        }
        wait(for: [gone], timeout: 6)
    }

    func testAProgramLeftHoldingThePipeDoesNotHoldTheLookup() {
        // The shell answers and exits, but a program it started keeps standard output open.
        let script = "sleep 20 & echo /bin/ls"
        let started = Date()
        let result = ClaudeLocator.shellPath(shell: "/bin/sh", arguments: ["-c", script], timeout: 5)
        XCTAssertEqual(result.path, "/bin/ls")
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }
}
