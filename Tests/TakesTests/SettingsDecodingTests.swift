import XCTest
@testable import Takes

final class SettingsDecodingTests: XCTestCase {
    /// Settings saved by an older version must keep their values when new keys are added.
    func testOlderSettingsKeepTheirValues() throws {
        let old = #"{"engine":"apiKey","defaultTakes":5,"restoreClipboard":false}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        XCTAssertEqual(settings.engine, .apiKey)
        XCTAssertEqual(settings.defaultTakes, 5)
        XCTAssertFalse(settings.restoreClipboard)
        // Missing keys fall back to defaults.
        XCTAssertFalse(settings.privacyAccepted)
        XCTAssertEqual(settings.defaultModel, Models.sonnet)
        XCTAssertEqual(settings.summonHotKey.display, "⌃⌥Space")
    }

    func testRoundTrip() throws {
        var settings = AppSettings()
        settings.privacyAccepted = true
        settings.voiceRules = [VoiceRule(text: "Be brief")]
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(decoded.privacyAccepted)
        XCTAssertEqual(decoded.voiceRules.map(\.text), ["Be brief"])
    }

    func testDefaultPresetsAreValid() {
        XCTAssertFalse(Store.defaultPresets.isEmpty)
        XCTAssertEqual(Set(Store.defaultPresets.map(\.id)).count, Store.defaultPresets.count)
        for preset in Store.defaultPresets {
            XCTAssertTrue((1...5).contains(preset.takes), preset.name)
            XCTAssertTrue(Models.all.contains { $0.id == preset.model }, preset.name)
        }
    }
}
