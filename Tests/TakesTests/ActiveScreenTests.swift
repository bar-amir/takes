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
}
