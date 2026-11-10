import XCTest

@testable import Takes

private struct QuickEngine: TakesEngine {
    func run(_ request: EngineRequest, onUpdate: @escaping @Sendable ([String]) -> Void) async throws -> EngineResult {
        EngineResult(takes: ["Thursday works for me."], wallMs: 10, firstTextMs: 5)
    }
}

/// Fixes from the pre-launch review: finding `claude`, stopping runs, the instant paste check, Report a Problem.
final class LaunchFixesTests: XCTestCase {
    // MARK: Finding claude

    func testFixedPathPrefersTheEnvironmentOverride() {
        let path = ClaudeLocator.fixedPath(
            environment: ["CLAUDE_PATH": "/opt/claude"], home: "/Users/a",
            isExecutable: { _ in true })
        XCTAssertEqual(path, "/opt/claude")
    }

    func testFixedPathFindsTheOlderLocalInstall() {
        let path = ClaudeLocator.fixedPath(
            environment: [:], home: "/Users/a",
            isExecutable: { $0 == "/Users/a/.claude/local/claude" })
        XCTAssertEqual(path, "/Users/a/.claude/local/claude")
    }

    func testFixedPathIsNilWhenNothingIsInstalled() {
        XCTAssertNil(ClaudeLocator.fixedPath(environment: [:], home: "/Users/a", isExecutable: { _ in false }))
    }

    func testShellOutputGivesTheLastLine() {
        let output = "Welcome back\n/Users/a/.nvm/versions/node/v22/bin/claude\n"
        XCTAssertEqual(ClaudeLocator.parse(output, isExecutable: { _ in true }), "/Users/a/.nvm/versions/node/v22/bin/claude")
    }

    func testShellAliasGivesItsTarget() {
        let home = NSHomeDirectory()
        let parsed = ClaudeLocator.parse("alias claude='~/.claude/local/claude'", isExecutable: { _ in true })
        XCTAssertEqual(parsed, "\(home)/.claude/local/claude")
    }

    func testShellOutputThatIsNotAFileIsIgnored() {
        XCTAssertNil(ClaudeLocator.parse("claude not found", isExecutable: { _ in false }))
        XCTAssertNil(ClaudeLocator.parse("", isExecutable: { _ in true }))
    }

    // MARK: Stopping a claude process

    func testCancelStopsARunningProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        let stop = ProcessStopper(process)
        try process.run()
        stop.started()
        stop.cancel()
        process.waitUntilExit()
        XCTAssertTrue(stop.wasCancelled)
        XCTAssertFalse(stop.timedOut)
    }

    func testCancelBeforeStartStopsItOnStart() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        let stop = ProcessStopper(process)
        stop.cancel()
        try process.run()
        stop.started()
        process.waitUntilExit()
        XCTAssertTrue(stop.wasCancelled)
    }

    func testTimeoutStopsAndIsReported() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        let stop = ProcessStopper(process)
        try process.run()
        stop.started()
        stop.timeOut()
        process.waitUntilExit()
        XCTAssertTrue(stop.timedOut)
        XCTAssertFalse(stop.wasCancelled)
    }

    // MARK: Instant paste

    @MainActor
    func testInstantRunDoesNotPasteIntoAChangedField() async {
        var pasted: [String] = []
        let run = InstantRun(
            engine: QuickEngine(),
            paste: { take, done in
                pasted.append(take); done(true)
            },
            stillInField: { true }, sameField: { false })
        let request = InstantMode.request(preset: Store.defaultPresets[0], draft: "ya thursday works", rules: [])
        let outcome = await run.run(request)
        XCTAssertEqual(outcome, .failed(.fieldChanged(take: "Thursday works for me.")))
        XCTAssertTrue(pasted.isEmpty)
    }

    func testFieldChangedMessage() {
        XCTAssertEqual(
            InstantMode.Failure.fieldChanged(take: "x").message(app: "Slack"),
            "Couldn't confirm the text box in Slack, so nothing was pasted.")
        XCTAssertEqual(InstantMode.Failure.fieldChanged(take: "x").take, "x")
    }

    // MARK: Report a Problem

    func testReportURLFillsVersionsAndEngineOnly() throws {
        let url = ReportProblem.url(takesVersion: "0.7.0", macOSVersion: "26.1", engine: .chatGPT)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/bar-amir/takes/issues/new")
        XCTAssertEqual(Set(items.map(\.name)), ["template", "engine", "versions"])
        XCTAssertEqual(items.first { $0.name == "template" }?.value, "bug_report.yml")
        XCTAssertEqual(items.first { $0.name == "engine" }?.value, "ChatGPT plan")
        XCTAssertEqual(items.first { $0.name == "versions" }?.value, "Takes 0.7.0, macOS 26.1")
    }

    func testEngineOptionsMatchTheBugForm() throws {
        let form = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".github/ISSUE_TEMPLATE/bug_report.yml"), encoding: .utf8)
        for engine in [EngineKind.claudeCode, .apiKey, .chatGPT, .provider, .local] {
            XCTAssertTrue(form.contains("- \(ReportProblem.engineOption(engine))"), "\(engine) isn't an option in the bug form")
        }
    }
}
