import XCTest
@testable import Takes

/// Saving an Anthropic key used to ignore both the keychain's answer and whether the key works. Now Anthropic is
/// asked first (no tokens spent): a refused key isn't kept, a key that couldn't be checked is kept and said so, and
/// a keychain that refuses the save is reported.
@MainActor
final class APIKeySaveTests: XCTestCase {
    private var stored: [String] = []

    private func store(_ result: Bool) -> (String) -> Bool {
        { [unowned self] key in stored.append(key); return result }
    }

    func testAValidKeyIsSaved() async {
        let result = await APIKeySave.save("sk-ant-good", check: { _ in .valid }, store: store(true))
        XCTAssertEqual(result, .saved)
        XCTAssertEqual(stored, ["sk-ant-good"])
        XCTAssertNil(result.note)
    }

    func testARefusedKeyIsNotKept() async {
        let result = await APIKeySave.save("sk-ant-bad", check: { _ in .invalid("Anthropic refused this key.") }, store: store(true))
        XCTAssertEqual(result, .refused("Anthropic refused this key."))
        XCTAssertTrue(stored.isEmpty)
        XCTAssertEqual(result.note?.text, "Anthropic refused this key.")
        XCTAssertEqual(result.note?.problem, true)
    }

    func testAKeyThatCouldNotBeCheckedIsStillSaved() async {
        let result = await APIKeySave.save("sk-ant-offline", check: { _ in .couldNotCheck("Couldn't reach Anthropic.") }, store: store(true))
        XCTAssertEqual(result, .savedUnchecked("Couldn't reach Anthropic."))
        XCTAssertEqual(stored, ["sk-ant-offline"])
        XCTAssertEqual(result.note?.text, "Key saved, but not checked. Couldn't reach Anthropic.")
        XCTAssertEqual(result.note?.problem, false)
    }

    func testAKeychainThatRefusesIsReported() async {
        let result = await APIKeySave.save("sk-ant-good", check: { _ in .valid }, store: store(false))
        XCTAssertEqual(result, .notSaved)
        XCTAssertEqual(result.note?.text, "Takes couldn't save the key to your keychain. Try again.")
        XCTAssertEqual(result.note?.problem, true)
    }

    // MARK: Setup's status

    func testSetupAsksAnthropicOnceAboutTheSameKey() async {
        SetupMonitor.forgetCheckedAPIKey()
        defer { SetupMonitor.forgetCheckedAPIKey() }
        var checks = 0
        let check: (String) async -> APIKeyCheck = { _ in checks += 1; return .valid }
        let status1 = await SetupMonitor.apiKeyStatus(key: "sk-ant-1", check: check)
        XCTAssertEqual(status1, .ready("Anthropic API key saved"))
        let status2 = await SetupMonitor.apiKeyStatus(key: "sk-ant-1", check: check)
        XCTAssertEqual(status2, .ready("Anthropic API key saved"))
        XCTAssertEqual(checks, 1)
        _ = await SetupMonitor.apiKeyStatus(key: "sk-ant-2", check: check)
        XCTAssertEqual(checks, 2, "A new key is checked")
    }

    func testSetupSaysWhenTheKeyIsRefused() async {
        SetupMonitor.forgetCheckedAPIKey()
        let status3 = await SetupMonitor.apiKeyStatus(key: "sk-ant-bad", check: { _ in .invalid("no") })
        XCTAssertEqual(status3, .problem("The key was refused"))
        let status4 = await SetupMonitor.apiKeyStatus(key: nil, check: { _ in .valid })
        XCTAssertEqual(status4, .problem("No API key saved yet"))
        let status5 = await SetupMonitor.apiKeyStatus(key: "", check: { _ in .valid })
        XCTAssertEqual(status5, .problem("No API key saved yet"))
    }

    func testOfflineCountsAsReadyButIsAskedAgain() async {
        SetupMonitor.forgetCheckedAPIKey()
        defer { SetupMonitor.forgetCheckedAPIKey() }
        var checks = 0
        let offline: (String) async -> APIKeyCheck = { _ in checks += 1; return .couldNotCheck("offline") }
        let status6 = await SetupMonitor.apiKeyStatus(key: "sk-ant-1", check: offline)
        XCTAssertEqual(status6, .ready("Anthropic API key saved"))
        _ = await SetupMonitor.apiKeyStatus(key: "sk-ant-1", check: offline)
        XCTAssertEqual(checks, 2)
    }
}
