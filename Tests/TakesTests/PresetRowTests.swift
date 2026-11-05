import XCTest
@testable import Takes

/// The compose row names the chosen preset and the ones used most in the app; the rest fold into "+N".
final class PresetRowTests: XCTestCase {
    private let presets = Store.defaultPresets
    private var ids: [String] { presets.map(\.id) }

    func testChosenFirstThenSettingsOrder() {
        let layout = PresetRow.layout(presets: presets, current: ids[4], usage: [:], pickedForApp: [], limit: 3)
        XCTAssertEqual(layout.shown, [ids[4], ids[0], ids[1]])
        XCTAssertEqual(layout.overflow, presets.count - 3)
    }

    func testMostUsedInThisAppComeNext() {
        let usage = [ids[6]: 9, ids[2]: 4, ids[0]: 1]
        let layout = PresetRow.layout(presets: presets, current: ids[0], usage: usage, pickedForApp: [], limit: 3)
        XCTAssertEqual(layout.shown, [ids[0], ids[6], ids[2]], "the chosen preset isn't repeated, whatever its use")
    }

    func testPickedForTheAppBreaksTies() {
        let layout = PresetRow.layout(presets: presets, current: ids[0], usage: [:], pickedForApp: [ids[5]], limit: 3)
        XCTAssertEqual(layout.shown, [ids[0], ids[5], ids[1]])
    }

    func testOverflowCountsEverythingNotNamed() {
        for limit in 1...3 {
            let layout = PresetRow.layout(presets: presets, current: ids[0], usage: [:], pickedForApp: [], limit: limit)
            XCTAssertEqual(layout.shown.count, limit)
            XCTAssertEqual(layout.shown.count + layout.overflow, presets.count, "limit \(limit)")
        }
        let few = Array(presets.prefix(2))
        let layout = PresetRow.layout(presets: few, current: few[1].id, usage: [:], pickedForApp: [], limit: 3)
        XCTAssertEqual(layout.shown, [few[1].id, few[0].id])
        XCTAssertEqual(layout.overflow, 0, "no \"+0\"")
    }

    func testUnknownChosenFallsBackToTheFirst() {
        let layout = PresetRow.layout(presets: presets, current: "gone", usage: [:], pickedForApp: [], limit: 2)
        XCTAssertEqual(layout.shown, [ids[0], ids[1]])
        XCTAssertEqual(PresetRow.layout(presets: [], current: "", usage: [:], pickedForApp: [], limit: 3),
                       PresetRow.Layout(shown: [], overflow: 0))
    }
}
