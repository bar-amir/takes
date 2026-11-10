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

    // MARK: Setup's status, and one request per save

    func testOneSaveAsksAnthropicOnce() async {
        let cache = APIKeyCheckCache()
        var asked = 0
        cache.ask = { _ in asked += 1; return .valid }
        let result = await APIKeySave.save("sk-ant-1", check: { await cache.check($0) }, store: store(true))
        XCTAssertEqual(result, .saved)
        // The setup check that follows the save uses the answer the save got.
        let status = await SetupMonitor.apiKeyStatus(key: "sk-ant-1", check: { await cache.check($0) })
        XCTAssertEqual(status, .ready("Anthropic API key saved"))
        _ = await SetupMonitor.apiKeyStatus(key: "sk-ant-1", check: { await cache.check($0) })
        XCTAssertEqual(asked, 1)
        _ = await SetupMonitor.apiKeyStatus(key: "sk-ant-2", check: { await cache.check($0) })
        XCTAssertEqual(asked, 2, "A new key is asked about")
    }

    func testAnOfflineKeyIsNotAskedAboutOnEveryRefresh() async {
        let cache = APIKeyCheckCache()
        var asked = 0
        cache.ask = { _ in asked += 1; return .couldNotCheck("offline") }
        let start = Date()
        let first = await cache.check("sk-ant-1", now: start)
        XCTAssertEqual(first, .couldNotCheck("offline"))
        _ = await cache.check("sk-ant-1", now: start.addingTimeInterval(60))
        XCTAssertEqual(asked, 1)
        _ = await cache.check("sk-ant-1", now: start.addingTimeInterval(APIKeyCheckCache.retryAfter))
        XCTAssertEqual(asked, 2, "Asked again after a while")
    }

    func testAnExplicitSaveAlwaysAsks() async {
        let cache = APIKeyCheckCache()
        var asked = 0
        cache.ask = { _ in asked += 1; return asked == 1 ? .invalid("refused") : .valid }
        _ = await cache.check("sk-ant-1")
        let kept = await cache.check("sk-ant-1")
        XCTAssertEqual(kept, .invalid("refused"), "Setup's checks reuse the answer")
        let saved = await APIKeySave.save("sk-ant-1", check: { await cache.check($0, fresh: true) }, store: store(true))
        XCTAssertEqual(saved, .saved, "Saving the same key again asks again: the refusal may have been passing")
        XCTAssertEqual(asked, 2)
    }

    func testSetupSaysWhenTheKeyIsRefused() async {
        let refused = await SetupMonitor.apiKeyStatus(key: "sk-ant-bad", check: { _ in .invalid("no") })
        XCTAssertEqual(refused, .problem("The key was refused"))
        let none = await SetupMonitor.apiKeyStatus(key: nil, check: { _ in .valid })
        XCTAssertEqual(none, .problem("No API key saved yet"))
        let empty = await SetupMonitor.apiKeyStatus(key: "", check: { _ in .valid })
        XCTAssertEqual(empty, .problem("No API key saved yet"))
        let offline = await SetupMonitor.apiKeyStatus(key: "sk-ant-1", check: { _ in .couldNotCheck("offline") })
        XCTAssertEqual(offline, .ready("Anthropic API key saved"), "Offline counts as ready; a run says what's wrong")
    }

    func testRemoveKeySaysWhenTheKeychainKeepsIt() {
        XCTAssertEqual(APIKeySave.notRemoved.note?.text, "Takes couldn't remove the key from your keychain. Try again.")
        XCTAssertEqual(APIKeySave.notRemoved.note?.problem, true)
    }

    func testTestsNeverTouchTheRealKeychain() {
        XCTAssertTrue(Store.runningTests)
        XCTAssertTrue(Keychain.setAPIKey("sk-ant-test"))
        XCTAssertEqual(Keychain.apiKey, "sk-ant-test")
        XCTAssertEqual(Keychain.memoryLock.withLock { Keychain.memory["anthropic-api-key"] }, Data("sk-ant-test".utf8),
                       "Saved in memory, not the login keychain")
        XCTAssertTrue(Keychain.setAPIKey(nil))
        XCTAssertNil(Keychain.apiKey)
    }
}
