import XCTest
@testable import Takes

final class ClaudeCodeEngineTests: XCTestCase {
    /// The official installer puts `claude` in ~/.local/bin, which a new Terminal often doesn't have on its PATH:
    /// sign-in must run it by its full path, never a bare `claude auth login`.
    func testSignInRunsClaudeByItsFullPath() {
        let script = ClaudeCodeEngine.signInScript(claudePath: "/Users/sam/.local/bin/claude")
        XCTAssertTrue(script.contains("'/Users/sam/.local/bin/claude' auth login"))
        XCTAssertFalse(script.contains("\nclaude auth login"))
        XCTAssertTrue(script.hasPrefix("#!/bin/zsh"))
    }

    func testSignInCommandQuotesThePath() {
        XCTAssertEqual(ClaudeCodeEngine.signInCommand(claudePath: "/Users/o'neil/My Apps/claude"),
                       "'/Users/o'\\''neil/My Apps/claude' auth login")
    }

    func testExpiredOAuthSessionReadsAsSignedOut() {
        let message = ClaudeCodeEngine.errorMessage("Failed to authenticate: OAuth session expired and could not be refreshed")
        XCTAssertEqual(message, ClaudeCodeEngine.signedOutMessage)
    }

    func testNotLoggedInReadsAsSignedOut() {
        XCTAssertEqual(ClaudeCodeEngine.errorMessage("Not logged in · Please run /login"), ClaudeCodeEngine.signedOutMessage)
    }

    func testSignedOutMessageHasNoCommands() {
        XCTAssertFalse(ClaudeCodeEngine.signedOutMessage.contains("`"))
        XCTAssertFalse(ClaudeCodeEngine.signedOutMessage.contains("Terminal"))
    }

    func testOtherErrorsKeepTheCLIWording() {
        XCTAssertEqual(ClaudeCodeEngine.errorMessage("You've hit your usage limit. It resets at 4 pm."),
                       "Claude Code: You've hit your usage limit. It resets at 4 pm.")
    }
}
