import Carbon
import XCTest
@testable import Takes

/// Guards for the hotkey and the synthetic ⌘A/⌘C/⌘V (Ori, 2026-10-27: Finder search opening,
/// the take not replacing the text, the field not being read).
final class KeystrokeTests: XCTestCase {
    private let summon = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), display: "⌃⌥Space")

    /// Ori's Mac: Spotlight on ⌃Space and "Show Finder search window" on ⌃⌥Space, Takes's default.
    private let orisHotKeys: [String: Any] = [
        "60": ["enabled": true, "value": ["parameters": [32, 49, 1_048_576], "type": "standard"]],
        "61": ["enabled": true, "value": ["parameters": [32, 49, 1_572_864], "type": "standard"]],
        "64": ["enabled": true, "value": ["parameters": [32, 49, 262_144], "type": "standard"]],
        "65": ["enabled": true, "value": ["parameters": [32, 49, 786_432], "type": "standard"]],
    ]

    func testHotKeyClashingWithFinderSearchIsReported() {
        XCTAssertEqual(SystemShortcuts.owner(of: summon, in: orisHotKeys), "Show Finder search window")
    }

    func testStockInputSourceShortcutClashes() {
        // Stock macOS puts "Select next source in Input menu" on ⌃⌥Space.
        let stock: [String: Any] = ["61": ["enabled": true, "value": ["parameters": [32, 49, 786_432]]]]
        XCTAssertEqual(SystemShortcuts.owner(of: summon, in: stock), "Select next source in Input menu")
    }

    func testDisabledOrDifferentShortcutsDoNotClash() {
        let off: [String: Any] = ["65": ["enabled": false, "value": ["parameters": [32, 49, 786_432]]]]
        XCTAssertNil(SystemShortcuts.owner(of: summon, in: off))
        let other = KeyCombo(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey), display: "⌃⌥T")
        XCTAssertNil(SystemShortcuts.owner(of: other, in: orisHotKeys))
        let withShift = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey | shiftKey), display: "⌃⌥⇧Space")
        XCTAssertNil(SystemShortcuts.owner(of: withShift, in: orisHotKeys))
    }

    func testFnAndKeypadBitsAreIgnored() {
        // macOS adds fn (0x800000) to F-key shortcuts; only ⇧⌃⌥⌘ decide a clash.
        let f5: [String: Any] = ["99": ["enabled": true, "value": ["parameters": [65535, 96, 0x800000 | 0x40000]]]]
        let ctrlF5 = KeyCombo(keyCode: UInt32(kVK_F5), modifiers: UInt32(controlKey), display: "⌃F5")
        XCTAssertNotNil(SystemShortcuts.owner(of: ctrlF5, in: f5))
    }

    func testPostedKeysCarryExactlyCommand() {
        for key in [kVK_ANSI_A, kVK_ANSI_C, kVK_ANSI_V] {
            let events = Paster.commandKeyEvents(CGKeyCode(key))
            XCTAssertEqual(events.count, 2)
            XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [Int64(key), Int64(key)])
            for event in events { XCTAssertEqual(Paster.interferingFlags(event.flags), [], "no ⌃⌥⇧ on posted ⌘\(key)") }
            XCTAssertTrue(events.allSatisfy { $0.flags.contains(.maskCommand) })
        }
    }

    func testPasteWaitsWhileHotKeyModifiersAreHeld() {
        XCTAssertFalse(Paster.interferingFlags([.maskControl, .maskAlternate]).isEmpty)
        XCTAssertFalse(Paster.interferingFlags(.maskShift).isEmpty)
        // ⌘ held (pasting with ⌘1) doesn't change ⌘V, and caps lock doesn't either.
        XCTAssertTrue(Paster.interferingFlags([.maskCommand, .maskAlphaShift]).isEmpty)
    }

    func testFocusWaitOutlastsElectronTreeBuild() {
        // 3 × 80 ms missed Claude desktop's first build ("no focused element"); keep at least ~0.6 s.
        XCTAssertGreaterThanOrEqual(Double(FocusReader.focusRetries) * 0.08, 0.6)
    }
}
