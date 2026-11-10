import XCTest
@testable import Takes

final class MenuBarPinTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "MenuBarPinTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testKeyIsTheOneMacOSUses() {
        XCTAssertEqual(MenuBarPin.positionKey("Item-0"), "NSStatusItem Preferred Position Item-0")
    }

    func testNoSavedPlaceNeedsMove() {
        XCTAssertTrue(MenuBarPin.needsMove(autosaveName: "Item-0", defaults: defaults))
    }

    func testDraggedElsewhereNeedsMove() {
        defaults.set(312.0, forKey: MenuBarPin.positionKey("Item-0"))
        XCTAssertTrue(MenuBarPin.needsMove(autosaveName: "Item-0", defaults: defaults))
    }

    func testPinSavesFarRightOnce() {
        MenuBarPin.pin(autosaveName: "Item-0", defaults: defaults)
        XCTAssertEqual(defaults.double(forKey: MenuBarPin.positionKey("Item-0")), 1)
        XCTAssertFalse(MenuBarPin.needsMove(autosaveName: "Item-0", defaults: defaults))
    }

    func testSettingIsOffByDefaultAndRoundTrips() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"engine":"apiKey"}"#.utf8))
        XCTAssertFalse(old.pinMenuBarIcon)
        var settings = AppSettings()
        settings.pinMenuBarIcon = true
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(decoded.pinMenuBarIcon)
    }
}
