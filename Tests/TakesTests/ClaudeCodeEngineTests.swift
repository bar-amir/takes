import XCTest
@testable import Takes

final class ClaudeCodeEngineTests: XCTestCase {
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
