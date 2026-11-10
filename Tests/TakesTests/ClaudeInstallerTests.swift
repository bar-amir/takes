import XCTest
@testable import Takes

final class ClaudeInstallerTests: XCTestCase {
    func testSuccessIsNoFailure() {
        XCTAssertNil(ClaudeInstaller.failureMessage(status: 0, output: "✅ Installation complete!", timedOut: false))
    }

    func testRunsAnthropicsOfficialInstaller() {
        XCTAssertEqual(ClaudeInstaller.installerURL, "https://claude.ai/install.sh")
        // A failed download must fail the install, not run an empty script.
        XCTAssertTrue(ClaudeInstaller.command.hasPrefix("set -o pipefail;"))
        XCTAssertTrue(ClaudeInstaller.command.hasSuffix("| bash"))
        // https only, even after a redirect, and no TLS older than 1.2.
        XCTAssertEqual(ClaudeInstaller.command, "set -o pipefail; curl --proto '=https' --tlsv1.2 -fsSL https://claude.ai/install.sh | bash")
    }

    func testNoNetwork() {
        let offline = "Couldn't reach Anthropic. Check your internet connection, then try again."
        XCTAssertEqual(ClaudeInstaller.failureMessage(status: 6, output: "curl: (6) Could not resolve host: claude.ai", timedOut: false), offline)
        XCTAssertEqual(ClaudeInstaller.failureMessage(status: 7, output: "", timedOut: false), offline)
        XCTAssertEqual(ClaudeInstaller.failureMessage(status: 1, output: "curl: (7) Failed to connect to downloads.claude.ai port 443", timedOut: false), offline)
    }

    func testTimeout() {
        let message = ClaudeInstaller.failureMessage(status: 15, output: "", timedOut: true)
        XCTAssertEqual(message, "The download took too long, so Takes stopped it. Check your internet connection, then try again.")
    }

    func testRegion() {
        let output = """
            Failed to get a valid version from downloads.claude.ai (got unexpected content).
            This can happen if the download service is unreachable or not available in your region - see https://www.anthropic.com/supported-countries
            """
        XCTAssertEqual(ClaudeInstaller.failureMessage(status: 1, output: output, timedOut: false),
                       "Claude Code's download isn't available from here. Anthropic lists where it is at anthropic.com/supported-countries.")
    }

    func testOtherFailuresShowTheInstallersLastLine() {
        let output = "Setting up Claude Code...\n\u{1B}[31mChecksum verification failed\u{1B}[0m\n\n"
        XCTAssertEqual(ClaudeInstaller.failureMessage(status: 1, output: output, timedOut: false),
                       "Couldn't install Claude Code: Checksum verification failed. Try again, or install it yourself.")
        XCTAssertEqual(ClaudeInstaller.failureMessage(status: 1, output: "", timedOut: false),
                       "Couldn't install Claude Code. Try again, or install it yourself.")
    }

    func testLongLinesAreCut() {
        let line = ClaudeInstaller.lastLine(String(repeating: "x", count: 400))
        XCTAssertEqual(line?.count, 161)
        XCTAssertEqual(line?.last, "…")
    }

    @MainActor
    func testProgressText() {
        XCTAssertEqual(ClaudeInstaller.State.downloading.progress, "Downloading Claude Code from Anthropic…")
        XCTAssertTrue(ClaudeInstaller.State.settingUp.isBusy)
        XCTAssertNil(ClaudeInstaller.State.failed("x").progress)
        XCTAssertEqual(ClaudeInstaller.State.failed("x").error, "x")
    }
}
