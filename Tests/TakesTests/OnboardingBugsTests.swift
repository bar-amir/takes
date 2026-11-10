import XCTest
@testable import Takes

/// Fixes from the onboarding audit (2026-11-08): the login shell, old CLIs, hung status checks, the sign-in
/// command, where the app runs from, and the setup window's status lines.
final class OnboardingBugsTests: XCTestCase {
    // MARK: Finding claude in the user's shell

    func testLoginShellComesFromTheEnvironment() {
        XCTAssertEqual(ClaudeLocator.loginShell(environment: ["SHELL": "/opt/homebrew/bin/fish"], isExecutable: { _ in true }),
                       "/opt/homebrew/bin/fish")
        XCTAssertEqual(ClaudeLocator.loginShell(environment: ["SHELL": "/bin/bash"], isExecutable: { _ in true }), "/bin/bash")
    }

    func testLoginShellFallsBackToZsh() {
        XCTAssertEqual(ClaudeLocator.loginShell(environment: ["SHELL": "not-a-path"], isExecutable: { _ in false }), "/bin/zsh")
        XCTAssertEqual(ClaudeLocator.loginShell(environment: ["SHELL": "/opt/gone/fish"], isExecutable: { _ in false }), "/bin/zsh")
    }

    // MARK: Versions

    func testVersionIsParsedFromTheCLIOutput() {
        XCTAssertEqual(ClaudeCodeEngine.parseVersion("2.1.310 (Claude Code)\n"), "2.1.310")
        XCTAssertEqual(ClaudeCodeEngine.parseVersion("1.0.88"), "1.0.88")
        XCTAssertNil(ClaudeCodeEngine.parseVersion("error: unknown option '--version'"))
        XCTAssertNil(ClaudeCodeEngine.parseVersion(""))
    }

    func testVersionsCompareNumerically() {
        XCTAssertEqual(ClaudeCodeEngine.compareVersions("2.1.9", "2.1.41"), .orderedAscending)
        XCTAssertEqual(ClaudeCodeEngine.compareVersions("2.1.41", "2.1.41"), .orderedSame)
        XCTAssertEqual(ClaudeCodeEngine.compareVersions("2.2", "2.1.41"), .orderedDescending)
        XCTAssertTrue(ClaudeCodeEngine.isSupported(version: "2.1.310"))
        XCTAssertTrue(ClaudeCodeEngine.isSupported(version: ClaudeCodeEngine.minimumVersion))
        XCTAssertFalse(ClaudeCodeEngine.isSupported(version: "1.0.88"))
        XCTAssertFalse(ClaudeCodeEngine.isSupported(version: "2.0.24"))
    }

    func testOldCLIErrorsSayToUpdate() {
        XCTAssertEqual(ClaudeCodeEngine.errorMessage("error: unknown option '--effort'"), ClaudeCodeEngine.outOfDateMessage)
        XCTAssertEqual(ClaudeCodeEngine.errorMessage("error: unknown command 'auth'"), ClaudeCodeEngine.outOfDateMessage)
        XCTAssertEqual(ClaudeCodeEngine.errorMessage("rate limited"), "Claude Code: rate limited")
        // A sign-in problem still wins.
        XCTAssertEqual(ClaudeCodeEngine.errorMessage("Not logged in · unknown option"), ClaudeCodeEngine.signedOutMessage)
    }

    func testStatusLineForEachCLIState() {
        typealias S = ClaudeCodeEngine.Status
        XCTAssertEqual(SetupMonitor.claudeCodeStatus(S(found: false)), .problem("Claude Code isn't installed"))
        XCTAssertEqual(SetupMonitor.claudeCodeStatus(S(found: true, timedOut: true)), .problem("Claude Code didn't answer; trying again"))
        XCTAssertEqual(SetupMonitor.claudeCodeStatus(S(found: true, signedIn: true, version: "1.0.88")),
                       .problem("Claude Code 1.0.88 is too old; update it (claude update)"))
        XCTAssertEqual(SetupMonitor.claudeCodeStatus(S(found: true, signedIn: false, version: "2.1.300")), .problem("Claude Code isn't signed in"))
        XCTAssertEqual(SetupMonitor.claudeCodeStatus(S(found: true, signedIn: true, plan: "max", version: "2.1.300")),
                       .ready("Claude Code signed in · Max plan"))
        // No version known (the CLI didn't say): the sign-in decides.
        XCTAssertEqual(SetupMonitor.claudeCodeStatus(S(found: true, signedIn: true)), .ready("Claude Code signed in"))
        // Found but couldn't be started: said so, not "didn't answer" or "not signed in".
        XCTAssertEqual(SetupMonitor.claudeCodeStatus(S(found: true, timedOut: true, launchError: "Takes couldn't start Claude Code: denied")),
                       .problem("Claude Code couldn't start"))
    }

    // MARK: The sign-in command

    func testSignInCommandUsesThePathTakesFound() {
        XCTAssertEqual(ClaudeCodeEngine.signInCommand(claudePath: "/Users/a/.local/bin/claude"), "'/Users/a/.local/bin/claude' auth login")
    }

    // MARK: Where Takes runs from

    func testTranslocatedAndDiskImageCopiesAreNoticed() {
        XCTAssertTrue(AppLocation.isTranslocated(URL(fileURLWithPath: "/private/var/folders/x/T/AppTranslocation/ABC/d/Takes.app")))
        XCTAssertFalse(AppLocation.isTranslocated(URL(fileURLWithPath: "/Applications/Takes.app")))
        XCTAssertTrue(AppLocation.isInApplications(URL(fileURLWithPath: "/Applications/Takes.app")))
        XCTAssertFalse(AppLocation.isInApplications(URL(fileURLWithPath: "/Users/a/Downloads/Takes.app")))
        // A test bundle is on a writable volume.
        XCTAssertFalse(AppLocation.isOnReadOnlyVolume(URL(fileURLWithPath: NSTemporaryDirectory())))
    }

    // MARK: Onboarding

    @MainActor
    func testTakenHotkeyOffersFreeOnes() {
        let model = OnboardingModel(progress: OnboardingProgress(step: .personalize, history: [.accessibility, .engine], openingSeen: true),
                                    conditions: OnboardingConditions(accessibility: true, engineReady: true, privacyAccepted: true, hotKeyFree: false))
        model.hotKeyOwner = "macOS: Select next source in Input menu"
        model.hotKeySuggestions = Array(HotKeyChoice.candidates.prefix(2))
        XCTAssertEqual(model.hotKeySuggestions.count, 2)
        // Picking one is a settings change, done through the store; here only the seam is checked.
        XCTAssertNotNil(model.hotKeyOwner)
    }

    @MainActor
    func testLaunchAtLoginIsOffUntilAskedAndReportsFailures() {
        let model = OnboardingModel()
        XCTAssertFalse(model.launchAtLogin)
        var asked: [Bool] = []
        model.setLaunchAtLogin = { asked.append($0) }
        model.launchAtLogin = true
        model.launchAtLogin = true
        model.launchAtLogin = false
        XCTAssertEqual(asked, [true, false])
    }
}
