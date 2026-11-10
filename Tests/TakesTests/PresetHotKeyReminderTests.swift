import XCTest
@testable import Takes

/// The compose footer reminds you of the chosen preset's own hotkey, unless that hotkey just opened the panel.
@MainActor
final class PresetHotKeyReminderTests: XCTestCase {
    private let combo = KeyCombo(keyCode: 3, modifiers: 0x0A00, display: "⌥⇧F")
    private let focus = FocusSnapshot(app: nil, text: "", source: .field, caretRect: nil)
    private var saved: [Preset] = []
    private var wasReadOnly = false

    override func setUp() async throws {
        wasReadOnly = Store.readOnly
        Store.readOnly = true
        saved = Store.shared.presets
        XCTAssertGreaterThan(saved.count, 1, "the test needs two presets")
        var withKey = saved[0]
        withKey.hotKey = combo
        var withoutKey = saved[1]
        withoutKey.hotKey = nil
        Store.shared.presets = [withKey, withoutKey] + saved.dropFirst(2)
    }

    override func tearDown() async throws {
        Store.shared.presets = saved
        Store.readOnly = wasReadOnly
    }

    func testShownWhenChosenAnotherWay() {
        let model = PanelModel()
        model.reset(focus: focus, presetID: nil)
        model.choose(saved[0].id)
        XCTAssertEqual(model.presetHotKeyReminder(taken: []), combo)
    }

    func testHiddenWhenItsHotKeyOpenedThePanel() {
        let model = PanelModel()
        model.reset(focus: focus, presetID: saved[0].id)
        XCTAssertNil(model.presetHotKeyReminder(taken: []))
    }

    func testShownAfterSwitchingBackFromAnotherPreset() {
        let model = PanelModel()
        model.reset(focus: focus, presetID: saved[1].id)
        XCTAssertNil(model.presetHotKeyReminder(taken: []), "this preset has no hotkey")
        model.choose(saved[0].id)
        XCTAssertEqual(model.presetHotKeyReminder(taken: []), combo)
    }

    func testHiddenWhenAnotherAppHoldsIt() {
        let model = PanelModel()
        model.reset(focus: focus, presetID: nil)
        model.choose(saved[0].id)
        XCTAssertNil(model.presetHotKeyReminder(taken: [combo]))
    }
}
