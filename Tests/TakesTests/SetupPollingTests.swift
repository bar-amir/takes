import XCTest
@testable import Takes

/// The setup monitor used to check the model every 5 seconds for as long as Takes ran while it wasn't ready, each
/// check a login shell or `claude auth status`. Now it polls only while a setup, onboarding or Settings window is
/// open, backs off while the check keeps failing, and never checks anything in a snapshot.
final class SetupPollingTests: XCTestCase {
    func testTheWaitGrowsWhileTheCheckKeepsFailing() {
        XCTAssertEqual(SetupPolling.retryDelay(failures: 0), 5)
        XCTAssertEqual(SetupPolling.retryDelay(failures: 1), 5)
        XCTAssertEqual(SetupPolling.retryDelay(failures: 2), 10)
        XCTAssertEqual(SetupPolling.retryDelay(failures: 3), 20)
        XCTAssertEqual(SetupPolling.retryDelay(failures: 4), 40)
        XCTAssertEqual(SetupPolling.retryDelay(failures: 5), 60, "At most once a minute")
        XCTAssertEqual(SetupPolling.retryDelay(failures: 40), 60)
    }

    func testAReadyModelIsNotCheckedAgain() {
        var polling = SetupPolling()
        let start = Date()
        polling.checked(ready: true, at: start)
        XCTAssertFalse(polling.engineDue(ready: true, now: start.addingTimeInterval(3600)))
    }

    func testAFailingModelIsCheckedLessOften() {
        var polling = SetupPolling()
        let start = Date()
        XCTAssertTrue(polling.engineDue(ready: false, now: start), "Never checked yet")
        polling.checked(ready: false, at: start)
        XCTAssertFalse(polling.engineDue(ready: false, now: start.addingTimeInterval(4)))
        XCTAssertTrue(polling.engineDue(ready: false, now: start.addingTimeInterval(5)))
        polling.checked(ready: false, at: start.addingTimeInterval(5))
        XCTAssertFalse(polling.engineDue(ready: false, now: start.addingTimeInterval(14)), "Second failure: 10 s")
        XCTAssertTrue(polling.engineDue(ready: false, now: start.addingTimeInterval(15)))
        for i in 0..<10 { polling.checked(ready: false, at: start.addingTimeInterval(100 + Double(i))) }
        XCTAssertFalse(polling.engineDue(ready: false, now: start.addingTimeInterval(109 + 59)))
        XCTAssertTrue(polling.engineDue(ready: false, now: start.addingTimeInterval(109 + 60)))
    }

    func testOpeningAWindowStartsOverWithoutTheBackOff() {
        var polling = SetupPolling()
        let start = Date()
        for i in 0..<6 { polling.checked(ready: false, at: start.addingTimeInterval(Double(i))) }
        XCTAssertEqual(polling.failures, 6)
        polling.reset()
        XCTAssertEqual(polling.failures, 0)
        XCTAssertTrue(polling.engineDue(ready: false, now: start.addingTimeInterval(5 + 5)))
    }

    func testASuccessClearsTheFailures() {
        var polling = SetupPolling()
        polling.checked(ready: false, at: Date())
        polling.checked(ready: false, at: Date())
        polling.checked(ready: true, at: Date())
        XCTAssertEqual(polling.failures, 0)
    }

    // MARK: The monitor

    @MainActor
    func testPollsOnlyWhileASetupWindowIsOpen() {
        let monitor = SetupMonitor(accessibility: true, engine: .problem("Claude Code isn't signed in"))
        XCTAssertFalse(monitor.isPolling, "Nothing open: nothing polls")
        monitor.window("settings", visible: true)
        XCTAssertTrue(monitor.isPolling)
        monitor.window("onboarding", visible: true)
        monitor.window("settings", visible: false)
        XCTAssertTrue(monitor.isPolling, "Onboarding is still open")
        monitor.window("onboarding", visible: false)
        XCTAssertFalse(monitor.isPolling, "Every window closed: the timer stops")
        XCTAssertTrue(monitor.watchers.isEmpty)
    }

    @MainActor
    func testClosingAWindowTwiceIsHarmless() {
        let monitor = SetupMonitor(accessibility: true, engine: .ready("ok"))
        monitor.window("setup", visible: false)
        XCTAssertFalse(monitor.isPolling)
        monitor.window("setup", visible: true)
        monitor.window("setup", visible: true)
        monitor.window("setup", visible: false)
        XCTAssertFalse(monitor.isPolling)
    }

    @MainActor
    func testASnapshotNeverPollsOrChecks() async {
        // The shared store exists before the flag is set, so it stays the tests' temporary one.
        _ = Store.shared
        Store.readOnly = true
        defer { Store.readOnly = false }
        let monitor = SetupMonitor(accessibility: false, engine: .problem("Claude Code isn't signed in"))
        monitor.window("setup", visible: true)
        XCTAssertFalse(monitor.isPolling, "Snapshots never start the timer")
        await monitor.refreshEngine()
        XCTAssertEqual(monitor.engine, .problem("Claude Code isn't signed in"), "Nothing was asked")
        monitor.refreshAccessibility()
        XCTAssertFalse(monitor.accessibility)
        monitor.window("setup", visible: false)
    }

    @MainActor
    func testAMonitorWithFixedStateChecksNothing() async {
        let monitor = SetupMonitor(accessibility: true, engine: .problem("Claude Code isn't signed in"),
                                   claudeCode: .init(found: true, version: "2.1.310"))
        await monitor.refreshEngine()
        XCTAssertEqual(monitor.engine, .problem("Claude Code isn't signed in"))
        XCTAssertEqual(monitor.claudeCode?.state, .signedOut)
    }
}
