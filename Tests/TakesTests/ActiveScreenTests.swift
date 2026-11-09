import XCTest
@testable import Takes

/// Windows open on the display you're on. These are the displays of a MacBook with two monitors to its left.
final class ActiveScreenTests: XCTestCase {
    private let builtIn = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let middle = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
    private let left = CGRect(x: -5120, y: 0, width: 2560, height: 1440)
    private var displays: [CGRect] { [builtIn, middle, left] }

    func testThePointerPicksTheDisplay() {
        XCTAssertEqual(ScreenChoice.index(containing: CGPoint(x: 800, y: 500), in: displays), 0)
        XCTAssertEqual(ScreenChoice.index(containing: CGPoint(x: -1202, y: 355), in: displays), 1)
        XCTAssertEqual(ScreenChoice.index(containing: CGPoint(x: -4000, y: 900), in: displays), 2)
    }

    func testAClickInTheMenuBarCountsForThatDisplay() {
        // The top row of a display is at its maxY.
        XCTAssertEqual(ScreenChoice.index(containing: CGPoint(x: -778, y: 1440), in: displays), 1)
        XCTAssertEqual(ScreenChoice.index(containing: CGPoint(x: 1500, y: 1117), in: displays), 0)
    }

    func testTheSeamBetweenDisplays() {
        XCTAssertEqual(ScreenChoice.index(containing: CGPoint(x: 0, y: 500), in: displays), 0)
        XCTAssertEqual(ScreenChoice.index(containing: CGPoint(x: -0.5, y: 500), in: displays), 1)
        XCTAssertEqual(ScreenChoice.index(containing: CGPoint(x: -2560, y: 500), in: displays), 1)
    }

    func testAPointOffEveryDisplayGoesToTheNearest() {
        // Above the built-in display, which is shorter than the monitors.
        XCTAssertEqual(ScreenChoice.index(containing: CGPoint(x: 900, y: 1300), in: displays), 0)
        XCTAssertNil(ScreenChoice.index(containing: .zero, in: []))
    }

    func testAWindowIsCentredOnTheDisplay() {
        let visible = CGRect(x: -2560, y: 0, width: 2560, height: 1415)
        let origin = ScreenChoice.centred(CGSize(width: 780, height: 515), in: visible)
        XCTAssertEqual(origin.x, -2560 + (2560 - 780) / 2)
        // A little above the middle: more room below than above.
        let above = visible.maxY - (origin.y + 515)
        let below = origin.y - visible.minY
        XCTAssertGreaterThan(below, above)
        XCTAssertTrue(visible.contains(CGRect(origin: origin, size: CGSize(width: 780, height: 515))))
    }

    func testAWindowTallerThanTheDisplayKeepsItsTitleBarOnScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1728, height: 1080)
        let origin = ScreenChoice.centred(CGSize(width: 640, height: 1200), in: visible)
        XCTAssertEqual(origin.y + 1200, visible.maxY)
    }

    // MARK: Opened by the hotkey

    private func window(_ pid: pid_t, layer: Int = 0, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> [String: Any] {
        [kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer,
         kCGWindowBounds as String: CGRect(x: x, y: y, width: w, height: h).dictionaryRepresentation]
    }

    func testTheHotkeyFollowsTheWindowYouAreTypingIn() throws {
        // Front to back: a floating palette, the app's front window on the left monitor, an older one on the
        // built-in display, then another app.
        let list = [
            window(42, layer: 3, 100, 100, 300, 200),
            window(42, -4800, 100, 1200, 800),
            window(42, 200, 100, 800, 600),
            window(7, -2000, 100, 800, 600),
        ]
        let front = try XCTUnwrap(ScreenChoice.frontWindow(of: 42, in: list, primaryHeight: 1117))
        // Top-left origin on the primary display, flipped to Cocoa's bottom-left.
        XCTAssertEqual(front, CGRect(x: -4800, y: 1117 - 900, width: 1200, height: 800))
        XCTAssertEqual(ScreenChoice.index(for: front, in: displays), 2)
    }

    func testNoWindowForAnAppWithoutOne() {
        let list = [window(7, -2000, 100, 800, 600), window(42, 0, 0, 1, 1)]
        XCTAssertNil(ScreenChoice.frontWindow(of: 42, in: list, primaryHeight: 1117))
    }
}
