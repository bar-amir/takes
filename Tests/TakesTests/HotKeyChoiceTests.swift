import Carbon
import XCTest
@testable import Takes

/// The default hotkey, the ones offered instead, and who is named when one is taken.
final class HotKeyChoiceTests: XCTestCase {
    private let stockMac: (KeyCombo) -> String? = { combo in
        // Stock macOS: ⌃Space and ⌃⌥Space switch input sources, ⌘Space is Spotlight, ⌥⌘Space is Finder search.
        guard combo.keyCode == UInt32(kVK_Space) else { return nil }
        switch Int(combo.modifiers) {
        case controlKey: return "Select the previous input source"
        case controlKey | optionKey: return "Select next source in Input menu"
        case cmdKey: return "Show Spotlight search"
        case optionKey | cmdKey: return "Show Finder search window"
        default: return nil
        }
    }

    func testTheDefaultIsFreeOnAStockMac() {
        XCTAssertEqual(AppSettings().summonHotKey, HotKeyChoice.preferred)
        XCTAssertEqual(HotKeyChoice.preferred.display, "⌥⇧Space")
        XCTAssertNil(stockMac(HotKeyChoice.preferred))
        XCTAssertNil(SystemShortcuts.owner(of: HotKeyChoice.preferred, in: [
            "60": ["enabled": true, "value": ["parameters": [32, 49, 262_144]]],
            "61": ["enabled": true, "value": ["parameters": [32, 49, 786_432]]],
            "64": ["enabled": true, "value": ["parameters": [32, 49, 1_048_576]]],
            "65": ["enabled": true, "value": ["parameters": [32, 49, 1_572_864]]],
        ]))
        // And none of the apps Takes knows about ship with it.
        XCTAssertNil(HotKeyChoice.knownApp(using: HotKeyChoice.preferred, installed: { _ in true }))
    }

    func testFirstLaunchTakesTheFirstFreeCandidate() {
        XCTAssertEqual(HotKeyChoice.firstLaunchDefault(systemOwner: stockMac, isFree: { _ in true }), HotKeyChoice.preferred)
        // Another app has ⌥⇧Space: the next candidate that macOS doesn't own.
        let next = HotKeyChoice.firstLaunchDefault(systemOwner: stockMac, isFree: { $0 != HotKeyChoice.preferred })
        XCTAssertEqual(next.display, "⌃⌥⌘Space")
        // Everything taken: the preferred one, and setup says who has it.
        XCTAssertEqual(HotKeyChoice.firstLaunchDefault(systemOwner: stockMac, isFree: { _ in false }), HotKeyChoice.preferred)
    }

    func testFirstLaunchAvoidsPresetHotkeys() {
        let picked = HotKeyChoice.firstLaunchDefault(taken: [HotKeyChoice.preferred], systemOwner: stockMac, isFree: { _ in true })
        XCTAssertNotEqual(picked, HotKeyChoice.preferred)
    }

    func testSuggestionsLeaveOutTheCurrentAndTakenOnes() {
        let current = HotKeyChoice.candidates[1] // ⌃⌥Space, taken on a stock Mac
        let offered = HotKeyChoice.suggestions(current: current, taken: [current], systemOwner: stockMac, isFree: { _ in true })
        XCTAssertEqual(offered.count, 3)
        XCTAssertFalse(offered.contains(current))
        XCTAssertEqual(offered.first, HotKeyChoice.preferred)
        XCTAssertTrue(offered.allSatisfy { stockMac($0) == nil })
    }

    func testPresetSuggestionsSkipTakesOwnAndTakenHotkeys() {
        let first = HotKeyChoice.presetCandidates[0]
        XCTAssertEqual(first.display, "⌃⌥1")
        // ⌃⌥1 is another preset's, ⌃⌥2 is this one's, another app has ⌃⌥3.
        let offered = HotKeyChoice.suggestions(from: HotKeyChoice.presetCandidates, current: HotKeyChoice.presetCandidates[1],
                                               taken: [first], systemOwner: stockMac,
                                               isFree: { $0 != HotKeyChoice.presetCandidates[2] })
        XCTAssertEqual(offered.map(\.display), ["⌃⌥4", "⌃⌥5", "⌃⌥6"])
    }

    func testPresetCandidatesAreFreeOnAStockMac() {
        XCTAssertEqual(Set(HotKeyChoice.presetCandidates).count, HotKeyChoice.presetCandidates.count)
        for combo in HotKeyChoice.presetCandidates {
            XCTAssertNil(stockMac(combo), combo.display)
            XCTAssertNil(HotKeyChoice.knownApp(using: combo, installed: { _ in true }), combo.display)
            XCTAssertNotNil(combo.menuKeyEquivalent, combo.display)
        }
    }

    func testOwnerNamesMacOSFirstThenAKnownApp() {
        let optSpace = HotKeyChoice.combo(kVK_Space, optionKey, "⌥Space")
        XCTAssertEqual(HotKeyChoice.owner(of: optSpace, macOS: "Show Spotlight search", installed: { _ in true }), "macOS: Show Spotlight search")
        XCTAssertEqual(HotKeyChoice.owner(of: optSpace, installed: { $0 == "com.raycast.macos" }), "Raycast")
        XCTAssertEqual(HotKeyChoice.owner(of: optSpace, installed: { _ in false }), "another app")
        let shiftCmdSpace = HotKeyChoice.combo(kVK_Space, shiftKey | cmdKey, "⇧⌘Space")
        XCTAssertEqual(HotKeyChoice.knownApp(using: shiftCmdSpace, installed: { $0 == "com.1password.1password" }), "1Password")
        // Window managers own most of ⌃⌥ + letter.
        let ctrlOptT = HotKeyChoice.combo(kVK_ANSI_T, controlKey | optionKey, "⌃⌥T")
        XCTAssertEqual(HotKeyChoice.knownApp(using: ctrlOptT, installed: { $0 == "com.knollsoft.Rectangle" }), "Rectangle")
        XCTAssertNil(HotKeyChoice.knownApp(using: ctrlOptT, installed: { _ in false }))
    }

    func testCandidatesAreDistinctAndNamed() {
        XCTAssertEqual(Set(HotKeyChoice.candidates).count, HotKeyChoice.candidates.count)
        for combo in HotKeyChoice.candidates {
            XCTAssertFalse(combo.display.isEmpty)
            XCTAssertNotNil(combo.menuKeyEquivalent, combo.display)
        }
    }
}
