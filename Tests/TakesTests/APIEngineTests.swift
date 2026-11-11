import Security
import XCTest
@testable import Takes

/// Answers every request from a handler, so no request leaves the Mac.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
        var error: URLError?
    }

    nonisolated(unsafe) static var handler: (URLRequest) -> Reply = { _ in Reply(status: 500) }
    nonisolated(unsafe) static var requests: [URLRequest] = []
    private static let lock = NSLock()

    static func session(_ handler: @escaping (URLRequest) -> Reply) -> URLSession {
        lock.withLock {
            self.handler = handler
            requests = []
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    static var seen: [URLRequest] { lock.withLock { requests } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = request
        // URLSession moves the body to a stream; read it back so tests can look at it.
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
            request.httpBody = data
        }
        let reply = Self.lock.withLock {
            Self.requests.append(request)
            return Self.handler(request)
        }
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class APIEngineCutShortTests: XCTestCase {
    private static func sse(_ events: [[String: Any]]) -> Data {
        Data(events.map { "event: x\ndata: \(String(decoding: try! JSONSerialization.data(withJSONObject: $0), as: UTF8.self))\n\n" }.joined().utf8)
    }

    private static func text(_ chunk: String) -> [String: Any] {
        ["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": chunk]]
    }

    private static func stop(_ reason: String) -> [String: Any] {
        ["type": "message_delta", "delta": ["stop_reason": reason]]
    }

    private static let request = EngineRequest(system: "Rewrite.", user: "<draft>\nhi\n</draft>", takes: 2, model: Models.sonnet, effort: "low")

    private func run(_ events: [[String: Any]], request: EngineRequest = request) async throws -> EngineResult {
        let session = StubURLProtocol.session { _ in .init(status: 200, headers: ["content-type": "text/event-stream"], body: Self.sse(events)) }
        return try await APIEngine(session: session, keyOverride: "sk-ant-test").run(request) { _ in }
    }

    func testMaxTokensKeepsTheTakesAndSaysCutShort() async throws {
        let result = try await run([Self.text("Thursday works.\n===\nSure, Thurs"), Self.stop("max_tokens"), ["type": "message_stop"]])
        XCTAssertEqual(result.takes, ["Thursday works.", "Sure, Thurs"])
        XCTAssertTrue(result.cutShort)
    }

    func testContextWindowIsCutShortToo() async throws {
        let result = try await run([Self.text("Thursday works.\n===\nSure"), Self.stop("model_context_window_exceeded")])
        XCTAssertEqual(result.takes, ["Thursday works.", "Sure"])
        XCTAssertTrue(result.cutShort)
    }

    func testStoppingRightAfterASeparatorLeavesWholeTakes() async throws {
        // A separator, finished or half-written, ends the take before it: nothing is unfinished.
        for text in ["Thursday works.\n===\n", "Thursday works.\n=="] {
            let result = try await run([Self.text(text), Self.stop("max_tokens")])
            XCTAssertEqual(result.takes, ["Thursday works."])
            XCTAssertFalse(result.cutShort, text)
        }
    }

    func testARefusalAfterSomeTextIsDeclined() async throws {
        for events in [[Self.text("Thursday works.\n===\nSure"), Self.stop("refusal")], [Self.stop("refusal")]] {
            do {
                _ = try await run(events)
                XCTFail("should be declined")
            } catch {
                XCTAssertEqual(error.localizedDescription, "Claude declined to rewrite this draft.")
            }
        }
    }

    func testAStreamThatEndsWithoutAStopReasonIsUnfinished() async throws {
        let result = try await run([Self.text("Thursday works.\n===\nSure, Thu")])
        XCTAssertEqual(result.takes, ["Thursday works.", "Sure, Thu"])
        XCTAssertTrue(result.cutShort)
        do {
            _ = try await run([["type": "message_start", "message": [:] as [String: Any]]])
            XCTFail("should fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The connection to Claude dropped before the takes were done. Try again.")
        }
    }

    func testFinishedAnswerIsNotCutShort() async throws {
        let result = try await run([Self.text("Thursday works.\n===\nSure, Thursday."), Self.stop("end_turn")])
        XCTAssertEqual(result.takes, ["Thursday works.", "Sure, Thursday."])
        XCTAssertFalse(result.cutShort)
    }

    func testOutOfRoomBeforeAnyTextFails() async throws {
        do {
            _ = try await run([Self.stop("max_tokens")])
            XCTFail("should fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Claude ran out of room before writing a take. Try again, or pick a lower effort.")
        }
    }

    func testTheCapGrowsWithTheRequest() async throws {
        _ = try await run([Self.text("OK"), Self.stop("end_turn")])
        let short = try XCTUnwrap(StubURLProtocol.seen.first?.httpBody)
        let shortCap = try XCTUnwrap((JSONSerialization.jsonObject(with: short) as? [String: Any])?["max_tokens"] as? Int)
        XCTAssertEqual(shortCap, APIEngine.outputFloor)

        // Three takes of a 10,000-character draft at high effort: well above the old fixed 8,000.
        let long = EngineRequest(system: "Rewrite.", user: String(repeating: "word ", count: 2000), takes: 3, model: Models.opus, effort: "high")
        XCTAssertEqual(APIEngine.maxTokens(for: long), 3334 * 3 * 2 + 32_000)
        let huge = EngineRequest(system: "", user: String(repeating: "a", count: 300_000), takes: 5, model: Models.opus, effort: "high")
        XCTAssertEqual(APIEngine.maxTokens(for: huge), 128_000)
    }

    func testOutputBudget() {
        let request = EngineRequest(system: "", user: String(repeating: "é", count: 3000), takes: 2, model: "", effort: "low")
        // 6,000 bytes of UTF-8 → 2,000 tokens; two takes at twice the length.
        XCTAssertEqual(OutputBudget.tokens(in: request.user), 2000)
        XCTAssertEqual(OutputBudget.maxTokens(for: request, floor: 1000, ceiling: 100_000), 8000)
        XCTAssertEqual(OutputBudget.maxTokens(for: request, floor: 10_000, ceiling: 100_000), 10_000)
        XCTAssertEqual(OutputBudget.maxTokens(for: request, floor: 1000, ceiling: 5000), 5000)
        XCTAssertEqual(OutputBudget.maxTokens(for: request, floor: 1000, ceiling: 100_000, reserve: 500), 8500)
    }
}

final class APIKeyCheckTests: XCTestCase {
    private func check(_ reply: StubURLProtocol.Reply) async -> APIKeyCheck {
        await APIEngine.checkKey(" sk-ant-test\n", session: StubURLProtocol.session { _ in reply })
    }

    private static func error(_ type: String) -> Data {
        Data(#"{"type":"error","error":{"type":"\#(type)","message":"x"}}"#.utf8)
    }

    func testValidKeyListsAModelAndSpendsNothing() async throws {
        let result = await check(.init(status: 200, body: Data(#"{"data":[{"id":"claude-opus-5-5"}]}"#.utf8)))
        XCTAssertEqual(result, .valid)
        let request = try XCTUnwrap(StubURLProtocol.seen.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/models?limit=1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "anthropic-version"))
        XCTAssertTrue(request.httpBody?.isEmpty ?? true)
    }

    func testRefusedKeyIsInvalid() async {
        let refused = APIKeyCheck.invalid("Anthropic refused this key. Check it in the Anthropic Console and paste it again.")
        let unauthorized = await check(.init(status: 401, body: Self.error("authentication_error")))
        let forbidden = await check(.init(status: 403, body: Self.error("permission_error")))
        XCTAssertEqual(unauthorized, refused)
        XCTAssertEqual(forbidden, refused)
    }

    func testOutOfCreditOrRateLimitedKeyIsStillValid() async {
        let rateLimited = await check(.init(status: 429, body: Self.error("rate_limit_error")))
        let noCredit = await check(.init(status: 402, body: Self.error("billing_error")))
        XCTAssertEqual(rateLimited, .valid)
        XCTAssertEqual(noCredit, .valid)
    }

    func testNoAnswerIsCouldNotCheck() async {
        let offline = await check(.init(error: URLError(.notConnectedToInternet)))
        XCTAssertEqual(offline, .couldNotCheck("Couldn't reach Anthropic to check the key. Check your internet connection and try again."))
        let busy = await check(.init(status: 529, body: Self.error("overloaded_error")))
        XCTAssertEqual(busy, .couldNotCheck("Anthropic didn't answer the key check (HTTP 529). Try again in a moment."))
    }

    func testEmptyKeyIsNotSent() async {
        let result = await APIEngine.checkKey("  ", session: StubURLProtocol.session { _ in .init(status: 200) })
        XCTAssertEqual(result, .invalid("Paste your Anthropic API key first."))
        XCTAssertTrue(StubURLProtocol.seen.isEmpty)
    }
}

/// `Keychain.set` against a fake keychain that holds values: the user's keychain is never touched.
final class KeychainWriteTests: XCTestCase {
    private final class FakeKeychain {
        var items: [String: Data] = [:]
        var log: [String] = []
        var attributes: [[String: Any]] = []
        /// Forced results; nil does what a keychain would.
        var update: OSStatus?
        var add: OSStatus?
        var delete: OSStatus?

        private func account(_ query: [String: Any]) -> String { query[kSecAttrAccount as String] as? String ?? "" }

        var calls: Keychain.Items {
            Keychain.Items(
                update: { [self] query, attributes in
                    log.append("update")
                    self.attributes.append(attributes)
                    if let update { return update }
                    guard items[account(query)] != nil else { return errSecItemNotFound }
                    items[account(query)] = attributes[kSecValueData as String] as? Data
                    return errSecSuccess
                },
                add: { [self] item in
                    log.append("add")
                    attributes.append(item)
                    if let add { return add }
                    items[account(item)] = item[kSecValueData as String] as? Data
                    return errSecSuccess
                },
                delete: { [self] query in
                    log.append("delete")
                    if let delete { return delete }
                    return items.removeValue(forKey: account(query)) == nil ? errSecItemNotFound : errSecSuccess
                })
        }
    }

    func testUpdatesInPlace() {
        let keychain = FakeKeychain()
        keychain.items["test"] = Data("old".utf8)
        XCTAssertTrue(Keychain.set("sk-1", account: "test", items: keychain.calls))
        XCTAssertEqual(keychain.log, ["update"])
        XCTAssertEqual(keychain.items["test"], Data("sk-1".utf8))
        // The login keychain ignores an accessibility attribute, so none is sent.
        XCTAssertNil(keychain.attributes.first?[kSecAttrAccessible as String])
    }

    func testAddsANewItem() {
        let keychain = FakeKeychain()
        XCTAssertTrue(Keychain.set("sk-1", account: "test", items: keychain.calls))
        XCTAssertEqual(keychain.log, ["update", "add"])
        XCTAssertEqual(keychain.items["test"], Data("sk-1".utf8))
        XCTAssertEqual(keychain.attributes.last?[kSecAttrService as String] as? String, "com.baramir.takes")
    }

    func testARefusedWriteKeepsTheOldKey() {
        for refusal in [errSecInteractionNotAllowed, errSecAuthFailed, errSecParam] {
            let keychain = FakeKeychain()
            keychain.items["test"] = Data("old".utf8)
            keychain.update = refusal
            XCTAssertFalse(Keychain.set("sk-new", account: "test", items: keychain.calls))
            XCTAssertEqual(keychain.items["test"], Data("old".utf8))
            XCTAssertFalse(keychain.log.contains("delete"), "\(keychain.log)")
        }
    }

    func testAFailedAddIsReported() {
        let keychain = FakeKeychain()
        keychain.add = errSecInteractionNotAllowed
        XCTAssertFalse(Keychain.set("sk-1", account: "test", items: keychain.calls))
        XCTAssertNil(keychain.items["test"])
    }

    func testRemoving() {
        let keychain = FakeKeychain()
        keychain.items["test"] = Data("old".utf8)
        XCTAssertTrue(Keychain.set("", account: "test", items: keychain.calls))
        XCTAssertNil(keychain.items["test"])
        // Removing a key that isn't there is fine; a refused removal isn't.
        XCTAssertTrue(Keychain.set(nil, account: "test", items: keychain.calls))
        keychain.items["test"] = Data("old".utf8)
        keychain.delete = errSecAuthFailed
        XCTAssertFalse(Keychain.set(nil, account: "test", items: keychain.calls))
    }

    func testChatGPTTokensUseTheSameWrite() {
        let keychain = FakeKeychain()
        keychain.items["chatgpt-credentials"] = Data("old".utf8)
        keychain.update = errSecInteractionNotAllowed
        XCTAssertFalse(Keychain.setData(Data("new".utf8), account: "chatgpt-credentials", items: keychain.calls))
        XCTAssertEqual(keychain.items["chatgpt-credentials"], Data("old".utf8))
    }
}
