import XCTest
@testable import Takes

/// Which display the panel opens on. The full-screen jump itself was macOS's Finder-search shortcut sharing the hotkey
/// (guarded in the bug-4 branch's KeystrokeTests); this keeps a full-screen app on a second display with its panel.
final class FullScreenPanelTests: XCTestCase {
    // Built-in display on the left, a 2560×1440 display to its right (Cocoa coordinates, origin bottom-left).
    private let displays = [CGRect(x: 0, y: 0, width: 1728, height: 1117), CGRect(x: 1728, y: 0, width: 2560, height: 1440)]

    func testCaretPicksItsOwnDisplay() {
        XCTAssertEqual(ScreenChoice.index(for: CGRect(x: 100, y: 60, width: 0, height: 18), in: displays), 0)
        XCTAssertEqual(ScreenChoice.index(for: CGRect(x: 3000, y: 1200, width: 0, height: 18), in: displays), 1)
    }

    func testCaretOnTheSeamGoesWhereMostOfItIs() {
        // Starts 2pt before the seam, mostly on the second display; `first(where: intersects)` picked the first.
        XCTAssertEqual(ScreenChoice.index(for: CGRect(x: 1726, y: 400, width: 20, height: 18), in: displays), 1)
    }

    func testNoCaretOrOffEveryDisplayFallsBack() {
        XCTAssertNil(ScreenChoice.index(for: nil, in: displays))
        XCTAssertNil(ScreenChoice.index(for: CGRect(x: -500, y: -500, width: 2, height: 18), in: displays))
    }
}
