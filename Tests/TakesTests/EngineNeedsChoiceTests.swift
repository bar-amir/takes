import XCTest
@testable import Takes

/// Settings saved by a newer version can name an engine this one doesn't know. `settings.engine` then reads as
/// Claude Code, but nothing may run on that guess: setup says to pick a model, and every run refuses until one is.
final class EngineNeedsChoiceTests: XCTestCase {
    private func newerSettings() throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(#"{"engine":"someFutureEngine","privacyAccepted":true}"#.utf8))
    }

    func testEveryRunRefusesUntilAModelIsPicked() async throws {
        let settings = try newerSettings()
        XCTAssertTrue(settings.engineNeedsChoice)
        let engine = Engines.current(settings)
        XCTAssertTrue(engine is UnchosenEngine, "Not Claude Code, whatever `engine` reads as")
        do {
            _ = try await engine.run(EngineRequest(system: "", user: "draft", takes: 1, model: "", effort: "low")) { _ in }
            XCTFail("A run must not start")
        } catch {
            XCTAssertEqual(error.localizedDescription, Engines.needsChoiceMessage)
        }
    }

    func testPickingAModelClearsIt() throws {
        var settings = try newerSettings()
        settings.engine = .claudeCode
        XCTAssertFalse(settings.engineNeedsChoice, "Picking the engine it already reads as counts")
        XCTAssertTrue(Engines.current(settings) is ClaudeCodeEngine)
    }

    func testAKnownEngineRunsAsBefore() {
        var settings = AppSettings()
        settings.engine = .local
        XCTAssertFalse(settings.engineNeedsChoice)
        XCTAssertTrue(Engines.current(settings) is LocalEngine)
    }

    @MainActor
    func testSetupSaysToPickAModel() async throws {
        let store = Store.shared
        let saved = store.settings
        defer { store.settings = saved }
        store.settings = try newerSettings()
        var checks = 0
        let monitor = SetupMonitor(accessibility: true) { _ in checks += 1; return (.ready("Claude Code signed in"), nil) }
        await monitor.refreshEngine()
        XCTAssertEqual(monitor.engine, .problem("Pick a model"))
        XCTAssertEqual(checks, 0, "Claude Code isn't checked on a guess")
        XCTAssertEqual(SetupMonitor.missingSummary(accessibility: true, engine: monitor.engine, privacyAccepted: true, hotKeyFree: true),
                       "One thing left: connect a model.")
    }

    @MainActor
    func testTheMenuSaysToPickAModel() throws {
        XCTAssertEqual(AppDelegate.modelStatus(try newerSettings()), "Pick a model", "Not \"Model: Claude Code\"")
        var settings = AppSettings()
        settings.engine = .claudeCode
        XCTAssertTrue(AppDelegate.modelStatus(settings).hasPrefix("Model: Claude Code"))
    }
}
