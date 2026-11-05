import XCTest
@testable import Takes

final class UsageLimitTests: XCTestCase {
    func testAnthropicAPIErrors() {
        func error(_ status: Int?, _ type: String?, _ message: String, retryAfter: String? = nil) -> Error {
            APIEngine.apiError(status: status, type: type, message: message, retryAfter: retryAfter)
        }
        let credit = error(400, "invalid_request_error",
                           "Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits.")
            as? UsageLimitError
        XCTAssertEqual(credit?.kind, .outOfCredit)
        XCTAssertEqual(credit?.manage, APIEngine.billingURL)
        XCTAssertEqual(credit?.title, "Out of credit")
        XCTAssertEqual(credit?.manageTitle, "Add credit")
        XCTAssertEqual((error(402, "billing_error", "Billing problem") as? UsageLimitError)?.kind, .outOfCredit)

        let spend = error(400, "invalid_request_error",
                          "You have reached your specified API usage limits. You will regain access on 2026-12-01 at 00:00 UTC.")
            as? UsageLimitError
        XCTAssertEqual(spend?.kind, .planLimit)
        XCTAssertEqual(spend?.manage, APIEngine.limitsURL)

        let busy = error(429, "rate_limit_error", "Number of request tokens has exceeded your per-minute rate limit", retryAfter: "1")
            as? UsageLimitError
        XCTAssertEqual(busy?.kind, .rateLimited)
        XCTAssertEqual(busy?.message, "Your Anthropic key hit its rate limit. Try again in 1 second.")
        // A rate limit in the middle of the stream has no status.
        XCTAssertEqual((error(nil, "rate_limit_error", "x") as? UsageLimitError)?.kind, .rateLimited)

        XCTAssertNil(error(500, "api_error", "Internal server error") as? UsageLimitError)
        XCTAssertEqual(error(500, "api_error", "Internal server error").localizedDescription, "API error: Internal server error")
    }

    func testClaudeCodePlanLimits() {
        let limit = ClaudeCodeEngine.resultError("5-hour limit reached ∙ resets 3pm") as? UsageLimitError
        XCTAssertEqual(limit?.kind, .planLimit)
        XCTAssertEqual(limit?.message, "You've reached your Claude plan's usage limit. It resets 3pm. Pick another engine to keep going.")
        XCTAssertEqual(limit?.manage, ClaudeCodeEngine.usageURL)
        XCTAssertEqual(limit?.manageTitle, "Manage usage")

        XCTAssertEqual(ClaudeCodeEngine.resultError("You've hit your limit · resets Nov 9, 10am (Europe/London)").localizedDescription,
                       "You've reached your Claude plan's usage limit. It resets Nov 9, 10am (Europe/London). Pick another engine to keep going.")

        // The older form ends with a Unix time.
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = ClaudeCodeEngine.resultError("Claude AI usage limit reached|1800003600", now: now)
        XCTAssertTrue(old.localizedDescription.contains("It resets at "), old.localizedDescription)
        // A reset time already past says nothing about it.
        XCTAssertEqual(ClaudeCodeEngine.resultError("Claude AI usage limit reached|1700000000", now: now).localizedDescription,
                       "You've reached your Claude plan's usage limit. Pick another engine to keep going.")

        XCTAssertEqual((ClaudeCodeEngine.resultError("Credit balance is too low") as? UsageLimitError)?.kind, .outOfCredit)
        XCTAssertEqual(ClaudeCodeEngine.resultError("Not logged in · Please run /login").localizedDescription,
                       "Claude Code: Not logged in · Please run /login Run `claude auth login` in Terminal.")
    }

    func testRetryHint() {
        XCTAssertEqual(UsageLimitError.retryHint(nil), "Try again in a moment.")
        XCTAssertEqual(UsageLimitError.retryHint("Wed, 21 Oct 2026 07:28:00 GMT"), "Try again in a moment.")
        XCTAssertEqual(UsageLimitError.retryHint("45"), "Try again in 45 seconds.")
        XCTAssertEqual(UsageLimitError.retryHint("120"), "Try again in 2 minutes.")
    }
}
