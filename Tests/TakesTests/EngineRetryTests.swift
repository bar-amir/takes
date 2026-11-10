import XCTest
@testable import Takes

final class EngineRetryTests: XCTestCase {
    private func line(_ text: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
    }

    /// Claude Code's stream line while it waits out a rate limit: it was ignored, so the panel looked stuck.
    func testRateLimitRetryIsRead() {
        let json = line(#"{"type":"system","subtype":"api_retry","attempt":2,"max_retries":10,"retry_delay_ms":4000,"error_status":429,"error":"rate_limit"}"#)
        let retry = ClaudeCodeEngine.retry(from: json)
        XCTAssertEqual(retry, EngineRetry(attempt: 2, maxAttempts: 10, status: 429))
        XCTAssertEqual(retry?.label, "Rate limited · retry 2 of 10")
    }

    func testOverloadedAndNoResponseRetries() {
        let overloaded = ClaudeCodeEngine.retry(from: line(#"{"type":"system","subtype":"api_retry","attempt":1,"max_retries":10,"error_status":529}"#))
        XCTAssertEqual(overloaded?.label, "Claude is busy · retry 1 of 10")
        let silent = ClaudeCodeEngine.retry(from: line(#"{"type":"system","subtype":"api_retry","attempt":3,"error_status":null}"#))
        XCTAssertEqual(silent, EngineRetry(attempt: 3, maxAttempts: nil, status: nil))
        XCTAssertEqual(silent?.label, "No answer yet · retry 3")
    }

    func testOtherSystemLinesAreNotRetries() {
        XCTAssertNil(ClaudeCodeEngine.retry(from: line(#"{"type":"system","subtype":"init"}"#)))
        XCTAssertNil(ClaudeCodeEngine.retry(from: line(#"{"type":"system","subtype":"post_turn_summary"}"#)))
        XCTAssertNil(ClaudeCodeEngine.retry(from: line(#"{"type":"result","subtype":"api_retry"}"#)))
    }

    /// The panel reopened at the height of an earlier, taller run and, while writing, never shrank.
    func testFirstFitAfterOpeningMayShrinkWhileWriting() {
        XCTAssertTrue(PanelController.shouldFit(target: 480, current: 760, running: true, fittedThisOpen: false))
    }

    /// A regenerate in the same panel doesn't shrink and regrow it while takes stream in.
    func testLaterFitsOnlyGrowWhileWriting() {
        XCTAssertFalse(PanelController.shouldFit(target: 480, current: 760, running: true, fittedThisOpen: true))
        XCTAssertTrue(PanelController.shouldFit(target: 800, current: 760, running: true, fittedThisOpen: true))
        XCTAssertTrue(PanelController.shouldFit(target: 480, current: 760, running: false, fittedThisOpen: true))
        XCTAssertFalse(PanelController.shouldFit(target: 760.5, current: 760, running: false, fittedThisOpen: false))
    }
}
