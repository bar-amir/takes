import XCTest
@testable import Takes

/// Ori: the panel must not cover the text box being written in. Cocoa coordinates (origin bottom-left).
final class PanelPlacementTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 0, width: 1728, height: 1080)
    private let panel = CGSize(width: 1060, height: 511)

    private func placed(_ box: CGRect) -> CGRect {
        CGRect(origin: PanelPlacement.origin(size: panel, keepClear: box, in: visible), size: panel)
    }

    func testChatBoxAtTheBottomGetsThePanelAboveIt() {
        let box = CGRect(x: 300, y: 40, width: 900, height: 90)
        let frame = placed(box)
        XCTAssertFalse(frame.intersects(box))
        XCTAssertEqual(frame.minY, box.maxY + PanelPlacement.gap)
        XCTAssertTrue(visible.contains(frame))
    }

    func testBoxAtTheTopGetsThePanelBelowIt() {
        let box = CGRect(x: 200, y: 900, width: 700, height: 120)
        let frame = placed(box)
        XCTAssertFalse(frame.intersects(box))
        XCTAssertEqual(frame.maxY, box.minY - PanelPlacement.gap)
    }

    func testMidScreenBoxWithNoRoomAboveOrBelowGetsASide() {
        let box = CGRect(x: 60, y: 380, width: 500, height: 300)
        let frame = placed(box)
        XCTAssertFalse(frame.intersects(box))
        XCTAssertTrue(visible.contains(frame))
    }

    func testMultiLineBoxIsClearedWhole() {
        // The caret on the box's last line used to be all the panel avoided, so it covered the lines above.
        let field = CGRect(x: 300, y: 300, width: 800, height: 200)
        let caret = CGRect(x: 420, y: 310, width: 2, height: 18)
        let clear = PanelPlacement.keepClear(caret: caret, field: field, visible: visible)
        XCTAssertEqual(clear, field)
        XCTAssertFalse(placed(field).intersects(field))
    }

    func testFullHeightEditorClearsTheCaretLine() {
        // A document fills the screen: step around the line being written, with a line of room either side.
        let field = CGRect(x: 0, y: 0, width: 1728, height: 1000)
        let caret = CGRect(x: 500, y: 200, width: 2, height: 18)
        let clear = PanelPlacement.keepClear(caret: caret, field: field, visible: visible)!
        XCTAssertTrue(clear.contains(caret))
        XCTAssertGreaterThanOrEqual(clear.height, 18 * 3)
        XCTAssertFalse(placed(clear).intersects(clear))
    }

    func testNoFieldFrameFallsBackToTheCaret() {
        let caret = CGRect(x: 500, y: 200, width: 2, height: 18)
        XCTAssertNotNil(PanelPlacement.keepClear(caret: caret, field: nil, visible: visible))
        XCTAssertNil(PanelPlacement.keepClear(caret: nil, field: nil, visible: visible))
    }

    func testBoxAcrossTheScreenGetsTheFirstClearAnchor() {
        // A box across the middle of the screen: no room beside it, so the panel goes above it.
        let box = CGRect(x: 40, y: 500, width: 1640, height: 90)
        let small = CGSize(width: 720, height: 400)
        let frame = CGRect(origin: PanelPlacement.origin(size: small, keepClear: box, in: visible), size: small)
        XCTAssertFalse(frame.intersects(box))
        XCTAssertTrue(visible.contains(frame))
        XCTAssertGreaterThan(frame.minY, box.maxY)
    }

    func testPanelTallerThanAnyRoomCoversAsLittleAsPossible() {
        let box = CGRect(x: 100, y: 400, width: 1500, height: 300)
        let frame = placed(box)
        XCTAssertTrue(visible.contains(frame))
        let covered = frame.intersection(box)
        // Falls back to the screen anchor that covers the least: the bottom edge, leaving the box's top lines free.
        XCTAssertLessThan(covered.height, box.height, "should leave part of the box visible")
    }

    func testChosenSpotIsUsedWhenItIsClear() {
        let box = CGRect(x: 300, y: 40, width: 900, height: 90)
        let origin = PanelPlacement.origin(for: .topRight, size: panel, keepClear: box, in: visible)
        XCTAssertEqual(origin, PanelPlacement.anchor(.topRight, size: panel, in: visible))
    }

    func testChosenSpotMovesAsideRatherThanCoverTheBox() {
        // Bottom center over a chat box at the bottom: the panel goes above the box instead.
        let box = CGRect(x: 300, y: 40, width: 900, height: 90)
        let frame = CGRect(origin: PanelPlacement.origin(for: .bottomCenter, size: panel, keepClear: box, in: visible), size: panel)
        XCTAssertFalse(frame.intersects(box))
        XCTAssertTrue(visible.contains(frame))
    }

    func testEverySpotFitsOnScreen() {
        for position in PanelPosition.allCases where position != .nearCursor {
            let origin = PanelPlacement.anchor(position, size: panel, in: visible)!
            XCTAssertTrue(visible.contains(CGRect(origin: origin, size: panel)), position.rawValue)
        }
    }

    func testSettingsSavedBeforeTheNewSpotsStillLoad() throws {
        for raw in ["nearCursor", "center"] {
            let decoded = try JSONDecoder().decode(PanelPosition.self, from: Data("\"\(raw)\"".utf8))
            XCTAssertEqual(decoded.rawValue, raw)
        }
    }
}
