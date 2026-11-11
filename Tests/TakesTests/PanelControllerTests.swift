import XCTest

@testable import Takes

private final class SlowEngine: TakesEngine, @unchecked Sendable {
    private(set) var runs = 0
    private(set) var cancelled = 0

    func run(_ request: EngineRequest, onUpdate: @escaping @Sendable ([String]) -> Void) async throws -> EngineResult {
        runs += 1
        do {
            try await Task.sleep(nanoseconds: 5_000_000_000)
        } catch {
            cancelled += 1
            throw error
        }
        return EngineResult(takes: ["Take one."], wallMs: 10, firstTextMs: 5)
    }
}

/// The panel's controller: when the hotkey keeps the open panel instead of opening it afresh, and what closing it
/// does to a run. No window is shown and nothing is read from another app.
@MainActor
final class PanelControllerTests: XCTestCase {
    private typealias Origin = FocusReader.PressOrigin
    private var wasReadOnly = false

    override func setUp() async throws {
        wasReadOnly = Store.readOnly
        Store.readOnly = true
    }

    override func tearDown() async throws {
        Store.readOnly = wasReadOnly
    }

    private func keeps(visible: Bool = true, isKey: Bool = false, hasWork: Bool = true, from origin: Origin) -> Bool {
        PanelController.keepsPanel(visible: visible, isKey: isKey, hasWork: hasWork) { origin }
    }

    // MARK: The hotkey while the panel is open

    func testPanelWithTheKeyboardIsAlwaysKept() {
        var asked = false
        let kept = PanelController.keepsPanel(visible: true, isKey: true, hasWork: false) {
            asked = true
            return .elsewhere
        }
        XCTAssertTrue(kept)
        XCTAssertFalse(asked, "no need to ask the app where the press came from")
    }

    func testPanelLeftToReadTheChatBehindItIsKeptWithItsWork() {
        // The keyboard went to the app behind the panel; the hotkey brings the panel back as it was.
        XCTAssertTrue(keeps(from: .sameBox))
        XCTAssertTrue(keeps(from: .sameApp), "the keyboard is in the message list, not in a text box")
    }

    func testPressFromAnotherTextBoxOrAppIsAFreshSummon() {
        XCTAssertFalse(keeps(from: .elsewhere))
        XCTAssertFalse(keeps(hasWork: false, from: .elsewhere))
    }

    func testPanelWithNothingToLoseOpensAfreshToShowTheBoxAsItIsNow() {
        var asked = false
        let kept = PanelController.keepsPanel(visible: true, isKey: false, hasWork: false) {
            asked = true
            return .sameBox
        }
        XCTAssertFalse(kept)
        XCTAssertFalse(asked)
    }

    func testHiddenPanelIsNeverKept() {
        XCTAssertFalse(keeps(visible: false, isKey: false, from: .sameBox))
        XCTAssertFalse(PanelController(watchClipboard: false).keepsOpenPanel(presetID: nil), "a panel that was never opened")
    }

    func testPressFromNoKnownAppIsAFreshSummon() {
        XCTAssertEqual(FocusReader.pressOrigin(for: nil), .elsewhere)
        // The practice box, or Takes itself in front: nothing was read from an app.
        XCTAssertEqual(FocusReader.pressOrigin(for: FocusSnapshot(app: nil, text: "x", source: .field, caretRect: nil)), .elsewhere)
    }

    // MARK: Closing

    func testClosingThePanelStopsItsRun() async {
        let engine = SlowEngine()
        let controller = PanelController(watchClipboard: false)
        let model = controller.model
        model.makeEngine = { _ in engine }
        model.logRun = { _ in }
        model.refreshModels = { _ in }
        // Not English, so the coach stays out of it; no tone notes, which would ask the real engine.
        model.reset(focus: FocusSnapshot(app: nil, text: "אפשר להזיז את הפגישה ליום חמישי?", source: .field, caretRect: nil), presetID: nil)
        var preset = Preset(name: "Test preset", colorHex: "#2F55E0", instruction: "Make it friendly.")
        preset.showTone = false
        model.previewPreset = preset
        model.generate()
        for _ in 0..<200 where engine.runs == 0 { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(model.running)

        controller.close()
        XCTAssertFalse(model.running)
        for _ in 0..<200 where engine.cancelled == 0 { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(engine.cancelled, 1, "the engine is told to stop, not left writing")
    }
}
