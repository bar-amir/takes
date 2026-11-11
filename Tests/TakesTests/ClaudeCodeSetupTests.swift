import XCTest
@testable import Takes

/// Every place that shows Claude Code's status (setup, onboarding, Settings › Model) switches on its state, and each
/// state gets its own message and the action that fits it. "Sign in to Claude" is no longer the answer to everything.
final class ClaudeCodeSetupTests: XCTestCase {
    typealias S = ClaudeCodeEngine.Status

    private let notInstalled = S(found: false)
    private let stillLooking = S(found: false, timedOut: true)
    private let couldNotStart = S(found: true, timedOut: true, launchError: "Takes couldn't start Claude Code: Permission denied")
    private let notAnswering = S(found: true, version: "2.1.310", timedOut: true)
    private let tooOld = S(found: true, signedIn: true, version: "2.0.24")
    private let signedOut = S(found: true, version: "2.1.310")
    private let ready = S(found: true, signedIn: true, plan: "pro", version: "2.1.310")

    func testEachStateHasItsOwnAction() {
        XCTAssertEqual(ClaudeCodeAction(notInstalled.state), .install)
        XCTAssertEqual(ClaudeCodeAction(tooOld.state), .update)
        XCTAssertEqual(ClaudeCodeAction(signedOut.state), .signIn)
        XCTAssertEqual(ClaudeCodeAction(couldNotStart.state), .checkAgain)
        XCTAssertEqual(ClaudeCodeAction(notAnswering.state), .checkAgain)
        XCTAssertEqual(ClaudeCodeAction(stillLooking.state), .checkAgain)
        XCTAssertNil(ClaudeCodeAction(ready.state))
        XCTAssertEqual([ClaudeCodeAction.install, .update, .signIn, .checkAgain].map(\.title),
                       ["Install Claude Code", "Update Claude Code", "Sign in to Claude", "Check again"])
    }

    func testTheSetupLineForEachState() {
        XCTAssertEqual(SetupMonitor.claudeCodeStatus(notInstalled), .problem("Claude Code isn't installed"))
        XCTAssertEqual(SetupMonitor.claudeCodeStatus(stillLooking), .problem("Still looking for Claude Code; trying again"))
        XCTAssertEqual(SetupMonitor.claudeCodeStatus(couldNotStart), .problem("Claude Code couldn't start"))
        XCTAssertEqual(SetupMonitor.claudeCodeStatus(notAnswering), .problem("Claude Code didn't answer; trying again"))
        XCTAssertEqual(SetupMonitor.claudeCodeStatus(tooOld), .problem("Claude Code 2.0.24 is too old; update it (claude update)"))
        XCTAssertEqual(SetupMonitor.claudeCodeStatus(signedOut), .problem("Claude Code isn't signed in"))
        XCTAssertEqual(SetupMonitor.claudeCodeStatus(ready), .ready("Claude Code signed in · Pro plan"))
    }

    func testSettingsBadgeForEachState() {
        XCTAssertEqual(ClaudeCodeAction.badge(for: notInstalled).text, "Not installed")
        XCTAssertEqual(ClaudeCodeAction.badge(for: stillLooking).text, "Still looking…", "A slow lookup isn't \"not installed\"")
        XCTAssertEqual(ClaudeCodeAction.badge(for: couldNotStart).text, "Couldn't start")
        XCTAssertEqual(ClaudeCodeAction.badge(for: notAnswering).text, "Didn't answer")
        XCTAssertEqual(ClaudeCodeAction.badge(for: tooOld).text, "Too old (2.0.24)")
        XCTAssertEqual(ClaudeCodeAction.badge(for: signedOut).text, "Not signed in")
        XCTAssertEqual(ClaudeCodeAction.badge(for: ready).text, "Signed in · Pro plan")
        XCTAssertTrue(ClaudeCodeAction.badge(for: ready).good)
        XCTAssertFalse(ClaudeCodeAction.badge(for: stillLooking).good)
    }

    func testCouldNotStartSaysWhy() {
        XCTAssertEqual(ClaudeCodeAction.note(for: couldNotStart.state), "Takes couldn't start Claude Code: Permission denied")
        XCTAssertEqual(ClaudeCodeAction.note(for: tooOld.state), "Terminal opens and runs claude update. Then press Check again.")
        XCTAssertNil(ClaudeCodeAction.note(for: ready.state))
        for status in [notInstalled, stillLooking, notAnswering, signedOut] { XCTAssertNotNil(ClaudeCodeAction.note(for: status.state)) }
    }

    func testTheUpdateWindowRunsClaudeUpdateByItsFullPath() {
        let script = ClaudeCodeEngine.updateScript(claudePath: "/Users/o'neil/.local/bin/claude")
        XCTAssertTrue(script.hasPrefix("#!/bin/zsh"))
        XCTAssertTrue(script.contains(#"'/Users/o'\''neil/.local/bin/claude' update"#), "Quoted for the shell")
    }
}
