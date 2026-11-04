import Foundation
import Network
import XCTest
@testable import Takes

final class LocalEndpointTests: XCTestCase {
    func testOnlyLoopbackHostsAreAllowed() {
        let allowed = ["http://localhost:11434/v1", "http://127.0.0.1:1234/v1", "http://127.3.2.1/v1", "http://[::1]:11434/v1",
                       "https://localhost/v1", "http://LOCALHOST:11434/v1"]
        let refused = ["http://192.168.1.10:11434/v1", "http://localhost.evil.com/v1", "http://evil.com/localhost",
                       "http://localhost@evil.com/v1", "http://user:pw@localhost/v1", "ftp://localhost/v1",
                       "http://128.0.0.1/v1", "http://127.0.0.256/v1", "http://0.0.0.0:11434/v1", "file:///etc/hosts",
                       "http://api.anthropic.com/v1"]
        for text in allowed { XCTAssertTrue(LocalEndpoint.isLoopback(URL(string: text)!), text) }
        for text in refused { XCTAssertFalse(URL(string: text).map(LocalEndpoint.isLoopback) ?? false, text) }
    }

    func testNormalizeAddsSchemeAndPathAndRefusesRemote() {
        XCTAssertEqual(LocalEndpoint.normalize("localhost:11434"), "http://localhost:11434/v1")
        XCTAssertEqual(LocalEndpoint.normalize(" http://127.0.0.1:1234/v1/ "), "http://127.0.0.1:1234/v1")
        XCTAssertEqual(LocalEndpoint.normalize("http://localhost:8080/api/v1"), "http://localhost:8080/api/v1")
        XCTAssertNil(LocalEndpoint.normalize("my-gpu-box.local:11434"))
        XCTAssertNil(LocalEndpoint.normalize(""))
    }

    func testEngineRefusesRemoteAddressBeforeSending() async {
        let engine = LocalEngine(baseURL: "http://example.com/v1")
        do {
            _ = try await engine.run(request(takes: 1)) { _ in }
            XCTFail("should refuse")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("only talks to model servers on this Mac"))
        }
        let probe = await LocalEngine.models(at: "http://example.com/v1")
        XCTAssertNil(probe)
    }

    func testServerNamesFromPort() {
        XCTAssertEqual(LocalServerKind.displayName("http://localhost:11434/v1"), "Ollama")
        XCTAssertEqual(LocalServerKind.displayName("http://localhost:1234/v1"), "LM Studio")
        XCTAssertEqual(LocalServerKind.displayName("http://localhost:9000/v1"), "The local model server")
    }
}

final class LocalRequestTests: XCTestCase {
    func testChatRequestBody() throws {
        let url = URL(string: "http://localhost:11434/v1/chat/completions")!
        let request = try LocalEngine.chatRequest(url: url, model: "llama3.2:latest", system: "SYS", user: "USER", stream: true, maxTokens: 4000)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "authorization"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "llama3.2:latest")
        XCTAssertEqual(body["stream"] as? Bool, true)
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [["role": "system", "content": "SYS"], ["role": "user", "content": "USER"]])
    }

    func testFormatRulesAreStricterForSeveralTakes() {
        let three = LocalPrompt.formatRules(takes: 3)
        XCTAssertTrue(three.contains("a line containing only ==="))
        XCTAssertTrue(three.contains("exactly 3 versions"))
        let one = LocalPrompt.formatRules(takes: 1)
        XCTAssertFalse(one.contains("==="))
        XCTAssertTrue(one.contains("exactly 1 version"))
    }

    func testHTTPErrors() {
        let missing = LocalEngine.httpError(status: 404, body: Data(#"{"error":{"message":"model \"qwen3\" not found, try pulling it first"}}"#.utf8),
                                            server: "Ollama", model: "qwen3:latest")
        XCTAssertEqual(missing.localizedDescription, "Ollama doesn't have the model “qwen3”. Pick an installed model in Settings › Model.")
        let other = LocalEngine.httpError(status: 500, body: Data(#"{"error":"out of memory"}"#.utf8), server: "LM Studio", model: "x")
        XCTAssertEqual(other.localizedDescription, "LM Studio error: out of memory")
    }
}

final class SSEParserTests: XCTestCase {
    func testChunksSplitMidLineAndMidCharacter() {
        var parser = SSEParser()
        let stream = "data: {\"a\":\"שלום\"}\r\n\r\n: keep-alive\ndata: {\"b\":1}\n\ndata: [DONE]\n"
        let bytes = Array(stream.utf8)
        var events: [SSEParser.Event] = []
        // Feed 3 bytes at a time: splits lines, "data:", and the two-byte Hebrew letters.
        for start in stride(from: 0, to: bytes.count, by: 3) {
            events += parser.feed(Data(bytes[start..<min(start + 3, bytes.count)]))
        }
        events += parser.finish()
        XCTAssertEqual(events, [.data(#"{"a":"שלום"}"#), .data(#"{"b":1}"#), .done])
    }

    func testLastLineWithoutNewline() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed(Data("data: {\"x\":1}".utf8)), [])
        XCTAssertEqual(parser.finish(), [.data(#"{"x":1}"#)])
    }

    func testIgnoresEventNamesAndBlankData() {
        XCTAssertNil(SSEParser.event("event: message"))
        XCTAssertNil(SSEParser.event("data: "))
        XCTAssertEqual(SSEParser.event("data:[DONE]"), .done)
        XCTAssertEqual(SSEParser.event(#"{"error":"bad"}"#), .data(#"{"error":"bad"}"#))
    }

    func testChunkParsing() {
        XCTAssertEqual(LocalChunk.parse(#"{"choices":[{"delta":{"content":"Hi"},"finish_reason":null}]}"#), LocalChunk(text: "Hi"))
        XCTAssertEqual(LocalChunk.parse(#"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#), LocalChunk(finishReason: "stop"))
        XCTAssertEqual(LocalChunk.parse(#"{"choices":[{"delta":{"role":"assistant","content":null}}]}"#), LocalChunk())
        XCTAssertEqual(LocalChunk.parse(#"{"error":{"message":"model is loading"}}"#), LocalChunk(error: "model is loading"))
        XCTAssertEqual(LocalChunk.parse(#"{"error":"Model unloaded"}"#), LocalChunk(error: "Model unloaded"))
        XCTAssertNil(LocalChunk.parse("not json"))
    }
}

final class LocalModelListTests: XCTestCase {
    func testParsesAndSortsAndDropsEmbeddingModels() {
        let json = #"{"object":"list","data":[{"id":"qwen3:8b","object":"model"},{"id":"llama3.2:latest","object":"model"},{"id":"text-embedding-nomic-embed-text-v1.5","object":"model"},{"id":"gemma3:4b"}]}"#
        XCTAssertEqual(LocalModelList.parse(Data(json.utf8)), ["gemma3:4b", "llama3.2:latest", "qwen3:8b"])
    }

    func testOllamaWithNoModelsSendsNull() {
        XCTAssertEqual(LocalModelList.parse(Data(#"{"object":"list","data":null}"#.utf8)), [])
        XCTAssertEqual(LocalModelList.parse(Data(#"{"object":"list","data":[]}"#.utf8)), [])
        XCTAssertNil(LocalModelList.parse(Data("<html>".utf8)))
    }

    func testLabels() {
        XCTAssertEqual(LocalModelList.label("llama3.2:latest"), "llama3.2")
        XCTAssertEqual(LocalModelList.label("qwen3:8b"), "qwen3:8b")
        XCTAssertEqual(LocalModelList.label("lmstudio-community/qwen2.5-7b-instruct"), "qwen2.5-7b-instruct")
        XCTAssertEqual(Models.displayLabel(Models.sonnet), "Sonnet 5.5")
        XCTAssertEqual(Models.displayLabel("llama3.2:latest"), "llama3.2")
        XCTAssertEqual(Models.displayLabel(""), "No model")
    }
}

final class LocalTakeCleanerTests: XCTestCase {
    private func split(_ text: String, _ expected: Int = 3, streaming: Bool = false) -> [String] {
        LocalTakeCleaner.split(text, streaming: streaming, expected: expected)
    }

    func testCleanOutputPassesThrough() {
        XCTAssertEqual(split("One.\n===\nTwo.\n===\nThree."), ["One.", "Two.", "Three."])
    }

    func testPreambleIsDropped() {
        XCTAssertEqual(split("Here are three versions:\n\nOne.\n===\nTwo.\n===\nThree."), ["One.", "Two.", "Three."])
        XCTAssertEqual(split("Sure! Here are 3 rewritten versions of your message:\n===\nOne.\n===\nTwo.\n===\nThree."), ["One.", "Two.", "Three."])
    }

    func testPreambleRightAboveTheFirstTake() {
        XCTAssertEqual(split("Here are three versions:\nOne.\n===\nTwo.\n===\nThree."), ["One.", "Two.", "Three."])
        // A take that is a short list keeps its lead-in.
        XCTAssertEqual(split("Two things before Thursday:\n- specs\n- QA", 1), ["Two things before Thursday:\n- specs\n- QA"])
    }

    func testPreambleIsHiddenWhileStreaming() {
        XCTAssertEqual(split("Here are three versions:", streaming: true), [])
    }

    func testLabelsInsteadOfSeparators() {
        let text = "**Version 1:**\nOne.\n\n**Version 2:**\nTwo.\n\n**Version 3:**\nThree."
        XCTAssertEqual(split(text), ["One.", "Two.", "Three."])
        XCTAssertEqual(split("Take 1: One.\nTake 2: Two.\nTake 3: Three."), ["One.", "Two.", "Three."])
        XCTAssertEqual(split("### Option 1\nOne.\n### Option 2\nTwo.\n### Option 3\nThree."), ["One.", "Two.", "Three."])
    }

    func testSentencesThatStartLikeLabelsAreKept() {
        XCTAssertEqual(split("Take 5 minutes to read the spec.", 1), ["Take 5 minutes to read the spec."])
    }

    func testOtherSeparators() {
        XCTAssertEqual(split("One.\n---\nTwo.\n=====\nThree."), ["One.", "Two.", "Three."])
        XCTAssertEqual(split("One.\n=== Take 2 ===\nTwo.\n***\nThree."), ["One.", "Two.", "Three."])
    }

    func testNumberedTakesWithoutSeparators() {
        XCTAssertEqual(split("1. One.\n\n2. Two.\n\n3. Three."), ["One.", "Two.", "Three."])
        // A numbered list inside a single take stays whole.
        XCTAssertEqual(split("Agenda:\n1. Specs\n2. QA", 1), ["Agenda:\n1. Specs\n2. QA"])
    }

    func testMissingSeparatorsKeepTheText() {
        XCTAssertEqual(split("Hi team,\n\nThursday works.\n\nThanks"), ["Hi team,\n\nThursday works.\n\nThanks"])
    }

    func testThinkingIsRemoved() {
        XCTAssertEqual(split("<think>The user wants three.</think>\nOne.\n===\nTwo.\n===\nThree."), ["One.", "Two.", "Three."])
        XCTAssertEqual(split("<think>still going", streaming: true), [])
    }

    func testQuotesFencesClosingRemarksAndExtras() {
        XCTAssertEqual(split("```\n\"One.\"\n===\n“Two.”\n```", 2), ["One.", "Two."])
        XCTAssertEqual(split("One.\n===\nTwo.\n===\nLet me know if you want changes.", 2), ["One.", "Two."])
        XCTAssertEqual(split("One.\n===\nTwo.\n===\nThree.\n===\nFour.", 2), ["One.", "Two."])
        XCTAssertEqual(split("He said \"yes\" and \"no\"", 1), ["He said \"yes\" and \"no\""])
    }

    func testHalfWrittenSeparatorWhileStreaming() {
        XCTAssertEqual(split("One.\n==", streaming: true), ["One."])
    }
}

final class LocalSettingsTests: XCTestCase {
    func testOldSettingsGetLocalDefaults() throws {
        let old = #"{"engine":"claudeCode","defaultTakes":4}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        XCTAssertEqual(settings.engine, .claudeCode)
        XCTAssertEqual(settings.defaultTakes, 4)
        XCTAssertEqual(settings.localBaseURL, "http://localhost:11434/v1")
        XCTAssertEqual(settings.localModel, "")
    }

    func testLocalSettingsRoundTrip() throws {
        var settings = AppSettings()
        settings.engine = .local
        settings.localBaseURL = "http://localhost:1234/v1"
        settings.localModel = "qwen3:8b"
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.engine, .local)
        XCTAssertEqual(decoded.localBaseURL, "http://localhost:1234/v1")
        XCTAssertEqual(decoded.localModel, "qwen3:8b")
    }

    func testUnknownEngineFallsBackWithoutLosingOtherSettings() throws {
        let future = #"{"engine":"somethingNew","defaultTakes":2,"privacyAccepted":true}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(future.utf8))
        XCTAssertEqual(settings.engine, .claudeCode)
        XCTAssertEqual(settings.defaultTakes, 2)
        XCTAssertTrue(settings.privacyAccepted)
    }

    func testPresetKeepsClaudeModelAndSummaryNamesTheLocalOne() {
        let preset = Preset(name: "P", colorHex: "#000000", instruction: "x")
        var settings = AppSettings()
        XCTAssertEqual(settings.runModel(for: preset), Models.sonnet)
        XCTAssertTrue(preset.summary(for: settings).contains("Sonnet 5.5"))
        settings.engine = .local
        settings.localModel = "llama3.2:latest"
        XCTAssertEqual(settings.runModel(for: preset), "llama3.2:latest")
        XCTAssertEqual(preset.summary(for: settings), "3 takes · llama3.2 on this Mac · same or shorter")
        XCTAssertEqual(preset.model, Models.sonnet)
    }

    func testEnginesPicksLocal() {
        var settings = AppSettings()
        settings.engine = .local
        XCTAssertTrue(Engines.current(settings) is LocalEngine)
    }
}

// MARK: - Against a mock server on 127.0.0.1

final class LocalEngineServerTests: XCTestCase {
    func testStreamsTakesFromServer() async throws {
        let sse = [
            #"data: {"choices":[{"delta":{"role":"assistant","content":""}}]}"#, "",
            #"data: {"choices":[{"delta":{"content":"Here are two versions:\nThursday "}}]}"#, "",
            #"data: {"choices":[{"delta":{"content":"works.\n==="}}]}"#, "",
            #"data: {"choices":[{"delta":{"content":"=\nSure, Thursday."}}]}"#, "",
            #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#, "",
            "data: [DONE]", "", "",
        ].joined(separator: "\n")
        let server = try MockServer { path, body in
            XCTAssertEqual(path, "/v1/chat/completions")
            let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            XCTAssertEqual(json?["model"] as? String, "llama3.2:latest")
            XCTAssertTrue(((json?["messages"] as? [[String: String]])?.first?["content"] ?? "").contains("Output format"))
            return .init(status: 200, contentType: "text/event-stream", chunks: Self.chunked(sse, size: 17))
        }
        defer { server.stop() }

        let updates = UpdateLog()
        let result = try await LocalEngine(baseURL: server.baseURL).run(request(takes: 2)) { updates.add($0) }
        XCTAssertEqual(result.takes, ["Thursday works.", "Sure, Thursday."])
        XCTAssertNotNil(result.firstTextMs)
        XCTAssertFalse(updates.all.isEmpty)
        // The preamble and the half-written separator never showed as a take.
        XCTAssertFalse(updates.all.flatMap { $0 }.contains { $0.contains("Here are") || $0.contains("=") })
    }

    func testStreamErrorIsReported() async throws {
        let sse = #"data: {"error":{"message":"model requires more system memory"}}"# + "\n\n"
        let server = try MockServer { _, _ in .init(status: 200, contentType: "text/event-stream", chunks: [Data(sse.utf8)]) }
        defer { server.stop() }
        do {
            _ = try await LocalEngine(baseURL: server.baseURL).run(request(takes: 1)) { _ in }
            XCTFail("should fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The local model server: model requires more system memory")
        }
    }

    func testMissingModel() async throws {
        let server = try MockServer { _, _ in
            .init(status: 404, contentType: "application/json", chunks: [Data(#"{"error":{"message":"model 'nope' not found"}}"#.utf8)])
        }
        defer { server.stop() }
        do {
            _ = try await LocalEngine(baseURL: server.baseURL).run(request(takes: 1, model: "nope")) { _ in }
            XCTFail("should fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("doesn't have the model “nope”"), error.localizedDescription)
        }
    }

    func testRedirectOffTheMacIsNotFollowed() async throws {
        let server = try MockServer { _, _ in
            .init(status: 302, contentType: "text/plain", chunks: [Data()], headers: ["Location": "http://example.com/v1/chat/completions"])
        }
        defer { server.stop() }
        do {
            _ = try await LocalEngine(baseURL: server.baseURL).run(request(takes: 1)) { _ in }
            XCTFail("should fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("only talks to servers on this Mac"), error.localizedDescription)
        }
    }

    func testNothingRunning() async throws {
        let server = try MockServer { _, _ in .init(status: 200, contentType: "text/plain", chunks: []) }
        let address = server.baseURL
        server.stop()
        try await Task.sleep(for: .milliseconds(100))
        do {
            _ = try await LocalEngine(baseURL: address).run(request(takes: 1)) { _ in }
            XCTFail("should fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("isn't running at 127.0.0.1"), error.localizedDescription)
        }
        let models = await LocalEngine.models(at: address)
        XCTAssertNil(models)
    }

    func testModelListAndTest() async throws {
        let server = try MockServer { path, _ in
            if path == "/v1/models" {
                return .init(status: 200, contentType: "application/json", chunks: [Data(#"{"data":[{"id":"b:latest"},{"id":"a"}]}"#.utf8)])
            }
            return .init(status: 200, contentType: "application/json",
                         chunks: [Data(#"{"choices":[{"message":{"role":"assistant","content":"OK"},"finish_reason":"stop"}]}"#.utf8)])
        }
        defer { server.stop() }
        let models = await LocalEngine.models(at: server.baseURL)
        XCTAssertEqual(models, ["a", "b:latest"])
        let result = await LocalEngine.test(baseURL: server.baseURL, model: "a")
        if case .failure(let error) = result { XCTFail(error.localizedDescription) }
    }

    static func chunked(_ text: String, size: Int) -> [Data] {
        let bytes = Array(text.utf8)
        return stride(from: 0, to: bytes.count, by: size).map { Data(bytes[$0..<min($0 + size, bytes.count)]) }
    }
}

private func request(takes: Int, model: String = "llama3.2:latest") -> EngineRequest {
    EngineRequest(system: "Rewrite.", user: "<draft>\nhi\n</draft>", takes: takes, model: model, effort: "low")
}

private final class UpdateLog: @unchecked Sendable {
    private let lock = NSLock()
    private var updates: [[String]] = []
    func add(_ takes: [String]) { lock.lock(); updates.append(takes); lock.unlock() }
    var all: [[String]] { lock.lock(); defer { lock.unlock() }; return updates }
}

/// A one-route HTTP server on 127.0.0.1 that answers each request with canned chunks, sent one by one.
private final class MockServer: @unchecked Sendable {
    struct Response {
        var status: Int
        var contentType: String
        var chunks: [Data]
        var headers: [String: String] = [:]
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "mock-server")
    private let handler: (String, Data) -> Response
    private(set) var port: UInt16 = 0
    var baseURL: String { "http://127.0.0.1:\(port)/v1" }

    init(handler: @escaping (String, Data) -> Response) throws {
        self.handler = handler
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port?.rawValue else {
            throw URLError(.cannotConnectToHost)
        }
        self.port = port
    }

    func stop() { listener.cancel() }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, _ in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if !done { self.receive(connection, buffer: buffer) }
                return
            }
            let head = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
            let length = head.split(separator: "\r\n")
                .first { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
            let body = buffer[headerEnd.upperBound...]
            if body.count < length, !done {
                self.receive(connection, buffer: buffer)
                return
            }
            let path = head.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            self.respond(connection, self.handler(path, Data(body)))
        }
    }

    private func respond(_ connection: NWConnection, _ response: Response) {
        var head = "HTTP/1.1 \(response.status) Mock\r\nContent-Type: \(response.contentType)\r\nConnection: close\r\n"
        for (key, value) in response.headers { head += "\(key): \(value)\r\n" }
        if response.contentType != "text/event-stream" {
            head += "Content-Length: \(response.chunks.reduce(0) { $0 + $1.count })\r\n"
        }
        head += "\r\n"
        var pieces = [Data(head.utf8)] + response.chunks
        func sendNext() {
            guard !pieces.isEmpty else {
                connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            let piece = pieces.removeFirst()
            connection.send(content: piece, completion: .contentProcessed { _ in
                self.queue.asyncAfter(deadline: .now() + 0.005) { sendNext() }
            })
        }
        sendNext()
    }
}

/// Features from other sessions must run on the local model when the local engine is picked.
final class LocalEngineIntegrationTests: XCTestCase {
    func testHelperCallsUseTheLocalModel() {
        var settings = AppSettings()
        XCTAssertEqual(settings.quickModel, Models.haiku)
        settings.engine = .local
        settings.localModel = "llama3.2"
        XCTAssertEqual(settings.quickModel, "llama3.2")
    }

    func testInstantModeUsesTheEngineModel() {
        var settings = AppSettings()
        settings.engine = .local
        settings.localModel = "llama3.2"
        let preset = Preset.proofread
        let request = InstantMode.request(preset: preset, draft: "hi", rules: [], model: settings.runModel(for: preset))
        XCTAssertEqual(request.model, "llama3.2")
        XCTAssertEqual(InstantMode.request(preset: preset, draft: "hi", rules: []).model, preset.model)
    }
}

final class LocalIntroLineTests: XCTestCase {
    func testIntroBeforeALaterVersionIsDropped() {
        let raw = "Thursday works, I need the specs by Wednesday.\n===\nThursday is fine if specs land Wednesday.\n===\nHere is a more formal suggestion, still friendly and clear:\nThursday works for me, provided the specs arrive by Wednesday."
        XCTAssertEqual(LocalTakeCleaner.split(raw, streaming: false, expected: 3).last,
                       "Thursday works for me, provided the specs arrive by Wednesday.")
    }

    func testAnIntroWithNothingAfterItIsNotATake() {
        let raw = "One.\n===\nTwo.\n===\nHere is a more formal suggestion:"
        XCTAssertEqual(LocalTakeCleaner.split(raw, streaming: false, expected: 3), ["One.", "Two."])
    }

    func testAMessageEndingInAColonStays() {
        let raw = "One.\n===\nTwo things before Thursday:\n- specs\n- notes"
        XCTAssertEqual(LocalTakeCleaner.split(raw, streaming: false, expected: 2).last, "Two things before Thursday:\n- specs\n- notes")
    }
}
