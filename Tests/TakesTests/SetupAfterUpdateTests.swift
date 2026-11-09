import XCTest
@testable import Takes

/// After an update, setup opened saying Claude Code wasn't there, then turned green a few seconds later: `claude`
/// installed with nvm is only found by a login shell, which ran out of time on a Mac busy with the update.
final class SetupAfterUpdateTests: XCTestCase {
    private let nvmClaude = "/Users/me/.nvm/versions/node/v22.22.0/bin/claude"

    private func defaults() -> UserDefaults {
        let name = "takes-tests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }

    /// Calls `path()` off the main thread, as the engine check does (the main thread never asks the shell).
    private func path(_ locator: ClaudeLocator) -> String? {
        var result: String?
        let done = expectation(description: "path")
        DispatchQueue.global().async { result = locator.path(); done.fulfill() }
        wait(for: [done], timeout: 5)
        return result
    }

    // MARK: Remembering where claude is

    func testAPathFoundByTheShellIsRememberedForTheNextLaunch() {
        let store = defaults()
        var lookups = 0
        let first = ClaudeLocator(remember: store, fixed: { nil }, lookup: { lookups += 1; return (self.nvmClaude, false) },
                                  isExecutable: { _ in true })
        XCTAssertEqual(path(first), nvmClaude)
        XCTAssertEqual(lookups, 1)

        // Next launch: found at once, no shell.
        let next = ClaudeLocator(remember: store, fixed: { nil }, lookup: { lookups += 1; return (nil, true) },
                                 isExecutable: { _ in true })
        XCTAssertEqual(next.known ?? path(next), nvmClaude)
        XCTAssertEqual(lookups, 1)
    }

    func testTheRememberedPathIsFoundOnTheMainThread() {
        let store = defaults()
        store.set(nvmClaude, forKey: ClaudeLocator.rememberedKey)
        let locator = ClaudeLocator(remember: store, fixed: { nil }, lookup: { XCTFail("no shell"); return (nil, false) },
                                    isExecutable: { _ in true })
        XCTAssertEqual(locator.path(), nvmClaude)
    }

    func testARememberedPathThatIsGoneIsLookedUpAgain() {
        let store = defaults()
        store.set("/Users/me/.nvm/versions/node/v20.0.0/bin/claude", forKey: ClaudeLocator.rememberedKey)
        let locator = ClaudeLocator(remember: store, fixed: { nil }, lookup: { (self.nvmClaude, false) },
                                    isExecutable: { $0 == self.nvmClaude })
        XCTAssertEqual(path(locator), nvmClaude)
        XCTAssertEqual(store.string(forKey: ClaudeLocator.rememberedKey), nvmClaude)
    }

    func testTheUsualInstallPlacesComeFirst() {
        let store = defaults()
        store.set(nvmClaude, forKey: ClaudeLocator.rememberedKey)
        let locator = ClaudeLocator(remember: store, fixed: { "/opt/homebrew/bin/claude" }, lookup: { (nil, false) },
                                    isExecutable: { _ in true })
        XCTAssertEqual(locator.path(), "/opt/homebrew/bin/claude")
    }

    // MARK: Checks at the same time

    func testACheckDuringALookupWaitsForItsAnswer() {
        var lookups = 0
        let lookupsLock = NSLock()
        let locator = ClaudeLocator(remember: defaults(), fixed: { nil }, lookup: {
            lookupsLock.withLock { lookups += 1 }
            Thread.sleep(forTimeInterval: 0.3)
            return (self.nvmClaude, false)
        }, isExecutable: { _ in true })
        // Launch starts two checks at once (settings and the launch task). The second used to get nil, which read
        // as "Claude Code isn't installed".
        var results: [String?] = [nil, nil]
        let done = expectation(description: "both")
        done.expectedFulfillmentCount = 2
        for i in 0..<2 {
            DispatchQueue.global().async {
                let found = locator.path()
                lookupsLock.withLock { results[i] = found }
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(results, [nvmClaude, nvmClaude])
        XCTAssertEqual(lookups, 1)
    }

    // MARK: A slow shell isn't a missing install

    func testALookupThatRanOutOfTimeIsSaidSo() {
        let locator = ClaudeLocator(remember: defaults(), fixed: { nil }, lookup: { (nil, true) }, isExecutable: { _ in true })
        XCTAssertNil(path(locator))
        XCTAssertTrue(locator.lastLookupTimedOut)

        let missing = ClaudeLocator(remember: defaults(), fixed: { nil }, lookup: { (nil, false) }, isExecutable: { _ in true })
        XCTAssertNil(path(missing))
        XCTAssertFalse(missing.lastLookupTimedOut)
    }

    func testStatusLineForASlowLookup() {
        XCTAssertEqual(SetupMonitor.claudeCodeStatus(.init(found: false, timedOut: true)),
                       .problem("Still looking for Claude Code; trying again"))
        XCTAssertEqual(SetupMonitor.claudeCodeStatus(.init(found: false)), .problem("Claude Code isn't installed"))
    }

    // MARK: Launch waits before opening setup

    func testLaunchChecksTheModelAgainWhenItIsTheOnlyThingMissing() {
        let problem = SetupMonitor.EngineStatus.problem("Claude Code isn't installed")
        XCTAssertTrue(SetupMonitor.recheckBeforeSetup(accessibility: true, privacyAccepted: true, hotKeyFree: true, engine: problem))
        XCTAssertTrue(SetupMonitor.recheckBeforeSetup(accessibility: true, privacyAccepted: true, hotKeyFree: true, engine: .checking))
        // Anything else missing: setup opens right away.
        XCTAssertFalse(SetupMonitor.recheckBeforeSetup(accessibility: false, privacyAccepted: true, hotKeyFree: true, engine: problem))
        XCTAssertFalse(SetupMonitor.recheckBeforeSetup(accessibility: true, privacyAccepted: false, hotKeyFree: true, engine: problem))
        XCTAssertFalse(SetupMonitor.recheckBeforeSetup(accessibility: true, privacyAccepted: true, hotKeyFree: false, engine: problem))
        XCTAssertFalse(SetupMonitor.recheckBeforeSetup(accessibility: true, privacyAccepted: true, hotKeyFree: true, engine: .ready("ok")))
    }
}
