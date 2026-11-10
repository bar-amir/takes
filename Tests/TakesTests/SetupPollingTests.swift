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
        polling.started(at: start)
        polling.checked(ready: true)
        XCTAssertFalse(polling.engineDue(ready: true, now: start.addingTimeInterval(3600)))
    }

    func testAFailingModelIsCheckedLessOften() {
        var polling = SetupPolling()
        let start = Date()
        XCTAssertTrue(polling.engineDue(ready: false, now: start), "Never checked yet")
        polling.started(at: start)
        polling.checked(ready: false)
        XCTAssertFalse(polling.engineDue(ready: false, now: start.addingTimeInterval(4)))
        XCTAssertTrue(polling.engineDue(ready: false, now: start.addingTimeInterval(5)))
        polling.started(at: start.addingTimeInterval(5))
        polling.checked(ready: false)
        XCTAssertFalse(polling.engineDue(ready: false, now: start.addingTimeInterval(14)), "Second failure: 10 s")
        XCTAssertTrue(polling.engineDue(ready: false, now: start.addingTimeInterval(15)))
        for _ in 0..<10 { polling.checked(ready: false) }
        polling.started(at: start.addingTimeInterval(100))
        XCTAssertFalse(polling.engineDue(ready: false, now: start.addingTimeInterval(159)))
        XCTAssertTrue(polling.engineDue(ready: false, now: start.addingTimeInterval(160)))
    }

    func testTheWaitCountsFromWhenACheckStarts() {
        var polling = SetupPolling()
        let start = Date()
        polling.started(at: start)
        // A slow check (a login shell, `claude auth status`) hasn't answered yet: it isn't due again meanwhile.
        XCTAssertFalse(polling.engineDue(ready: false, now: start.addingTimeInterval(3)))
    }

    func testOpeningAWindowStartsOverWithoutTheBackOff() {
        var polling = SetupPolling()
        let start = Date()
        for _ in 0..<6 { polling.checked(ready: false) }
        polling.started(at: start)
        XCTAssertEqual(polling.failures, 6)
        polling.reset()
        XCTAssertEqual(polling.failures, 0)
        XCTAssertTrue(polling.engineDue(ready: false, now: start.addingTimeInterval(5)))
    }

    func testASuccessClearsTheFailures() {
        var polling = SetupPolling()
        polling.checked(ready: false)
        polling.checked(ready: false)
        polling.checked(ready: true)
        XCTAssertEqual(polling.failures, 0)
    }

    // MARK: A hotkey press

    func testAPressNeverWaitsOnACheck() {
        typealias Monitor = SetupMonitor
        XCTAssertEqual(Monitor.summonRoute(accessibility: true, privacyAccepted: true, needsChoice: false,
                                           engine: .problem("Claude Code isn't signed in")), .setup,
                       "A model problem opens setup at once, which checks and shows the answer")
        XCTAssertEqual(Monitor.summonRoute(accessibility: true, privacyAccepted: true, needsChoice: false, engine: .checking), .panel,
                       "A check under way doesn't hold the press up")
        XCTAssertEqual(Monitor.summonRoute(accessibility: true, privacyAccepted: true, needsChoice: false, engine: .ready("ok")), .panel)
        XCTAssertEqual(Monitor.summonRoute(accessibility: false, privacyAccepted: true, needsChoice: false, engine: .ready("ok")), .setup)
        XCTAssertEqual(Monitor.summonRoute(accessibility: true, privacyAccepted: false, needsChoice: false, engine: .ready("ok")), .setup)
        XCTAssertEqual(Monitor.summonRoute(accessibility: true, privacyAccepted: true, needsChoice: true, engine: .problem("Pick a model")),
                       .pickModel)
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
        var checks = 0
        let monitor = SetupMonitor(accessibility: false, engine: .problem("Claude Code isn't signed in")) { _ in
            checks += 1
            return (.ready("ok"), nil)
        }
        // The shared store exists before the flag is set, so it stays the tests' temporary one.
        _ = Store.shared
        Store.readOnly = true
        defer { Store.readOnly = false }
        monitor.window("setup", visible: true)
        XCTAssertFalse(monitor.isPolling, "Snapshots never start the timer")
        await monitor.refreshEngine()
        monitor.tick()
        monitor.checkOnce()
        await Task.yield()
        XCTAssertEqual(checks, 0, "The read-only guard stops every check")
        XCTAssertEqual(monitor.engine, .problem("Claude Code isn't signed in"))
        monitor.window("setup", visible: false)
    }

    // MARK: One check at a time

    @MainActor
    func testManyTicksDuringASlowCheckStartOneCheck() async {
        var checks = 0
        var answer: CheckedContinuation<Void, Never>?
        let monitor = SetupMonitor(accessibility: true, engine: .problem("Claude Code isn't signed in")) { _ in
            checks += 1
            await withCheckedContinuation { answer = $0 }
            return (.problem("Claude Code isn't signed in"), nil)
        }
        let start = Date()
        for second in 0..<30 { monitor.tick(now: start.addingTimeInterval(Double(second))) }
        for _ in 0..<20 where answer == nil { await Task.yield() }
        XCTAssertEqual(checks, 1, "No new process every second while the first check hangs")
        XCTAssertTrue(monitor.isChecking)
        monitor.checkOnce()
        let waiting = Task { await monitor.refreshEngineUnlessRecent() }
        await Task.yield()
        XCTAssertEqual(checks, 1, "The menu and a window opening join the check under way")
        answer?.resume()
        await waiting.value
        for _ in 0..<20 where monitor.isChecking { await Task.yield() }
        XCTAssertFalse(monitor.isChecking)
        XCTAssertEqual(monitor.engine, .problem("Claude Code isn't signed in"), "The answer lands")
    }

    @MainActor
    func testARequestDuringACheckWaitsForItsAnswer() async {
        var checks = 0
        let monitor = SetupMonitor(accessibility: true) { _ in
            checks += 1
            try? await Task.sleep(nanoseconds: 50_000_000)
            return (.ready("Claude Code signed in"), nil)
        }
        async let first: Void = monitor.refreshEngine()
        async let second: Void = monitor.refreshEngine()
        _ = await (first, second)
        XCTAssertEqual(checks, 1)
        XCTAssertEqual(monitor.engine, .ready("Claude Code signed in"), "Both callers see the answer")
        await monitor.refreshEngine()
        XCTAssertEqual(checks, 2, "A new request after the answer is a new check")
    }

    // MARK: Taken hotkeys

    @MainActor
    func testATakenHotkeyIsTriedSlowlyWithNoWindowOpen() {
        let monitor = SetupMonitor(accessibility: true) { _ in (.ready("ok"), nil) }
        XCTAssertFalse(monitor.isRecheckingHotKeys)
        monitor.takenHotKeys = [AppSettings().summonHotKey]
        XCTAssertTrue(monitor.isRecheckingHotKeys, "Another app may quit and free it")
        XCTAssertEqual(SetupPolling.hotKeyRecheck, 10)
        monitor.window("settings", visible: true)
        XCTAssertFalse(monitor.isRecheckingHotKeys, "The every-second look covers it while a window is open")
        monitor.window("settings", visible: false)
        XCTAssertTrue(monitor.isRecheckingHotKeys)
        monitor.takenHotKeys = []
        XCTAssertFalse(monitor.isRecheckingHotKeys)
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
