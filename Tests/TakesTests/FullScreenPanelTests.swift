import Carbon
import XCTest
@testable import Takes

/// The panel jumped off a full-screen app: macOS's "Show Finder search window" was on ⌃⌥Space too, so each summon
/// also opened Finder, which pulled the full-screen Space away.
final class FullScreenPanelTests: XCTestCase {
    private let summon = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), display: "⌃⌥Space")

    private func entry(enabled: Bool, keyCode: Int, cocoaModifiers: UInt) -> [String: Any] {
        ["enabled": NSNumber(value: enabled),
         "value": ["parameters": [NSNumber(value: 32), NSNumber(value: keyCode), NSNumber(value: cocoaModifiers)], "type": "standard"]]
    }

    /// Ori's com.apple.symbolichotkeys, as read on the M4 Mac.
    private var orisHotKeys: [String: Any] {
        ["60": entry(enabled: true, keyCode: 49, cocoaModifiers: 1_048_576),   // ⌘Space
         "61": entry(enabled: true, keyCode: 49, cocoaModifiers: 1_572_864),   // ⌥⌘Space
         "64": entry(enabled: true, keyCode: 49, cocoaModifiers: 262_144),     // ⌃Space
         "65": entry(enabled: true, keyCode: 49, cocoaModifiers: 786_432)]     // ⌃⌥Space
    }

    func testFinderSearchOnTheSameComboIsAClash() {
        XCTAssertEqual(SystemShortcuts.clash(with: summon, in: orisHotKeys), "Show Finder search window")
    }

    func testDisabledOrDifferentShortcutsDontClash() {
        XCTAssertNil(SystemShortcuts.clash(with: summon, in: ["65": entry(enabled: false, keyCode: 49, cocoaModifiers: 786_432)]))
        XCTAssertNil(SystemShortcuts.clash(with: summon, in: ["65": entry(enabled: true, keyCode: 49, cocoaModifiers: 1_572_864)]))
        XCTAssertNil(SystemShortcuts.clash(with: summon, in: ["65": entry(enabled: true, keyCode: 0xFFFF, cocoaModifiers: 786_432)]))
        let shifted = KeyCombo(keyCode: summon.keyCode, modifiers: summon.modifiers | UInt32(shiftKey), display: "⌃⌥⇧Space")
        XCTAssertNil(SystemShortcuts.clash(with: shifted, in: orisHotKeys))
    }

    func testUnknownShortcutStillClashes() {
        XCTAssertEqual(SystemShortcuts.clash(with: summon, in: ["190": entry(enabled: true, keyCode: 49, cocoaModifiers: 786_432)]),
                       "a macOS keyboard shortcut")
    }

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
