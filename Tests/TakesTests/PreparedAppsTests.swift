import XCTest

@testable import Takes

/// Electron and Chromium apps build their accessibility tree only when asked. Takes asks each process once as it
/// comes forward, not on every activation.
final class PreparedAppsTests: XCTestCase {
    func testEachProcessIsAskedOnce() {
        var apps = PreparedApps()
        XCTAssertTrue(apps.needs(501))
        apps.asked(501, answered: true)
        XCTAssertFalse(apps.needs(501), "not again on every activation")
        XCTAssertTrue(apps.needs(502), "another process is asked on its own")
    }

    func testAnAppThatDidNotAnswerIsAskedAgain() {
        var apps = PreparedApps()
        apps.asked(501, answered: false)
        XCTAssertTrue(apps.needs(501), "an app still launching can't be reached yet")
        apps.asked(501, answered: true)
        XCTAssertFalse(apps.needs(501))
    }

    func testAProcessIdIsForgottenWhenItsAppQuits() {
        var apps = PreparedApps()
        apps.asked(501, answered: true)
        apps.forget(501)
        XCTAssertTrue(apps.needs(501), "the id can come back as another app")
    }
}
