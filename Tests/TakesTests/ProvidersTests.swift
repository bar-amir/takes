import Foundation
import Network
import XCTest
@testable import Takes

final class ProviderEndpointTests: XCTestCase {
    func testOnlyPublicHTTPSHostsAreAllowed() {
        let allowed = ["https://api.openai.com/v1", "https://openrouter.ai/api/v1", "https://llm.example.com:8443/v1",
                       "https://generativelanguage.googleapis.com/v1beta/openai"]
        let refused = ["http://api.openai.com/v1", "https://user:pw@api.openai.com/v1", "https://localhost/v1",
                       "https://127.0.0.1/v1", "https://[::1]/v1", "https://10.0.0.5/v1", "https://192.168.1.2:443/v1",
                       "https://2130706433/v1", "https://0x7f.1/v1", "https://[2001:db8::1]/v1", "https://app.localhost/v1",
                       "ftp://api.openai.com/v1", "https:///v1"]
        for address in allowed { XCTAssertTrue(ProviderEndpoint.isAllowed(URL(string: address)!), address) }
        for address in refused {
            if let url = URL(string: address) { XCTAssertFalse(ProviderEndpoint.isAllowed(url), address) }
        }
    }

    func testNormalizeAddsSchemeAndPath() {
        XCTAssertEqual(ProviderEndpoint.normalize("llm.example.com"), "https://llm.example.com/v1")
        XCTAssertEqual(ProviderEndpoint.normalize(" https://llm.example.com/api/v1/ "), "https://llm.example.com/api/v1")
        XCTAssertNil(ProviderEndpoint.normalize("http://llm.example.com/v1"))
        XCTAssertNil(ProviderEndpoint.normalize("localhost:11434"))
        XCTAssertNil(ProviderEndpoint.normalize("https://8.8.8.8/v1"))
        XCTAssertNil(ProviderEndpoint.normalize("https://llm.example.com/v1?key=x"))
        XCTAssertNil(ProviderEndpoint.normalize("  "))
    }

    func testTestOverrideIsOffByDefault() {
        XCTAssertFalse(ProviderEndpoint.allowInsecureForTests)
        XCTAssertNil(ProviderEndpoint.url("http://127.0.0.1:9/v1", "models"))
    }

    func testEngineRefusesPlainHTTPBeforeSending() async {
        var settings = AppSettings()
        settings.engine = .provider
        settings.providerID = "custom"
        settings.providerBaseURL = "http://llm.example.com/v1"
        do {
            _ = try await ProviderEngine(settings: settings, key: "k").run(request(takes: 1)) { _ in }
            XCTFail("should fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("https address"), error.localizedDescription)
        }
    }
}

final class ProviderTableTests: XCTestCase {
    func testKnownProviders() {
        XCTAssertEqual(Provider.known.map(\.name), ["OpenAI", "Google Gemini", "OpenRouter", "Groq", "Mistral"])
        for provider in Provider.known {
            XCTAssertTrue(ProviderEndpoint.isAllowed(URL(string: provider.baseURL)!), provider.name)
            XCTAssertNotNil(provider.consoleURL, provider.name)
            XCTAssertFalse(provider.name.contains("GPT"))
        }
        XCTAssertEqual(Provider.openRouter.extraHeaders["X-Title"], "Takes")
        XCTAssertTrue(Provider.groq.strictFormat)
        XCTAssertFalse(Provider.openAI.strictFormat)
        XCTAssertTrue(Provider.custom(baseURL: "https://x.example.com/v1").strictFormat)
    }

    func testCurrentAndKeyAccount() {
        var settings = AppSettings()
        XCTAssertEqual(Provider.current(settings), .openAI)
        XCTAssertEqual(Provider.openAI.keyAccount, "provider-api.openai.com")
        settings.providerID = "gemini"
        settings.providerBaseURL = "https://evil.example.com/v1"
        // A known provider always uses its own address.
        XCTAssertEqual(Provider.current(settings).baseURL, Provider.gemini.baseURL)
        settings.providerID = "custom"
        XCTAssertEqual(Provider.current(settings).name, "evil.example.com")
        XCTAssertEqual(Provider.current(settings).keyAccount, "provider-evil.example.com")
        settings.providerBaseURL = ""
        XCTAssertNil(Provider.current(settings).keyAccount)
    }

    func testKeyNotes() {
        XCTAssertEqual(Provider.openAI.keyNote("sk-ant-api03-abc"), "This looks like an Anthropic key. OpenAI needs a key from its own dashboard.")
        XCTAssertNil(Provider.openAI.keyNote("sk-proj-abc"))
        XCTAssertNil(Provider.openRouter.keyNote("sk-or-v1-abc"))
        XCTAssertEqual(Provider.groq.keyNote("sk-or-v1-abc"), "This looks like an OpenRouter key. Groq needs a key from its own dashboard.")
        XCTAssertEqual(Provider.mistral.keyNote("AIzaSyabc"), "This looks like a Google Gemini key. Mistral needs a key from its own dashboard.")
        XCTAssertNil(Provider.mistral.keyNote("abc123"))
        XCTAssertNil(Provider.custom(baseURL: "https://x.example.com/v1").keyNote("sk-ant-abc"))
        XCTAssertEqual(Provider.gemini.keyPlaceholder, "Paste your key (AIza…)")
    }
}

final class ProviderRequestTests: XCTestCase {
    private func body(_ request: URLRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
    }

    func testBearerHeaderAndBody() throws {
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        let request = try ProviderEngine.chatRequest(url: url, key: "sk-or-1", provider: .openRouter, model: "openai/gpt-5.4",
                                                     system: "S", user: "U", stream: true, maxTokens: 100,
                                                     options: .initial(provider: .openRouter, model: "openai/gpt-5.4"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Title"), "Takes")
        let json = body(request)
        XCTAssertEqual(json["model"] as? String, "openai/gpt-5.4")
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["max_tokens"] as? Int, 100)
        XCTAssertNotNil(json["temperature"])
        XCTAssertNil(json["reasoning_effort"])
        let messages = json["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.map { $0["role"] ?? "" }, ["system", "user"])
    }

    func testOpenAIReasoningModels() throws {
        XCTAssertTrue(ProviderRequestOptions.isReasoningModel("gpt-5.4"))
        XCTAssertTrue(ProviderRequestOptions.isReasoningModel("o4-mini"))
        XCTAssertTrue(ProviderRequestOptions.isReasoningModel("o3"))
        XCTAssertFalse(ProviderRequestOptions.isReasoningModel("gpt-4.1-mini"))
        XCTAssertFalse(ProviderRequestOptions.isReasoningModel("gpt-5-chat-latest"))
        XCTAssertFalse(ProviderRequestOptions.isReasoningModel("omni-moderation"))
        let options = ProviderRequestOptions.initial(provider: .openAI, model: "gpt-5.4")
        let request = try ProviderEngine.chatRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!, key: "k",
                                                     provider: .openAI, model: "gpt-5.4", system: "S", user: "U",
                                                     stream: true, maxTokens: 100, options: options)
        let json = body(request)
        XCTAssertEqual(json["max_completion_tokens"] as? Int, 100)
        XCTAssertNil(json["max_tokens"])
        XCTAssertNil(json["temperature"])
        XCTAssertEqual(json["reasoning_effort"] as? String, "low")
        // Only OpenAI gets the reasoning treatment up front; others learn it from a 400.
        XCTAssertEqual(ProviderRequestOptions.initial(provider: .openRouter, model: "gpt-5.4"), ProviderRequestOptions())
    }

    func testRetryOptionsFromErrors() {
        let start = ProviderRequestOptions()
        let noMax = start.adjusted(after: "Unsupported parameter: 'max_tokens' is not supported with this model. Use 'max_completion_tokens' instead.")
        XCTAssertEqual(noMax?.tokenField, "max_completion_tokens")
        let noTemp = start.adjusted(after: "Unsupported value: 'temperature' does not support 0.7 with this model.")
        XCTAssertEqual(noTemp?.temperature, false)
        let effort = ProviderRequestOptions.initial(provider: .openAI, model: "o3").adjusted(after: "Unrecognized request argument supplied: reasoning_effort")
        XCTAssertNil(effort?.reasoningEffort)
        XCTAssertNil(start.adjusted(after: "Something else went wrong"))
        XCTAssertNil(noTemp?.adjusted(after: "temperature again"))
    }

    func testErrorWording() {
        struct Wording { let message: String; let kind: ProviderError.Kind? }
        func error(_ status: Int, _ body: String, _ provider: Provider = .openAI, model: String = "gpt-x") -> Wording {
            let error = ProviderEngine.httpError(status: status, body: Data(body.utf8), provider: provider, model: model)
            return Wording(message: error.localizedDescription, kind: (error as? ProviderError)?.kind)
        }
        XCTAssertEqual(error(401, #"{"error":{"message":"Incorrect API key provided"}}"#).message,
                       "The key was refused. Check it in your OpenAI dashboard.")
        XCTAssertEqual(error(401, "").kind, .keyRefused)
        // Gemini says a bad key with a 400, wrapped in an array.
        let gemini = error(400, #"[{"error":{"code":400,"message":"API key not valid. Please pass a valid API key."}}]"#, .gemini)
        XCTAssertEqual(gemini.message, "The key was refused. Check it in your Google Gemini dashboard.")
        XCTAssertEqual(error(404, #"{"error":{"message":"The model `gpt-x` does not exist or you do not have access to it."}}"#).message,
                       "OpenAI doesn't have the model “gpt-x”. Pick another in Settings › Model.")
        XCTAssertEqual(error(400, #"{"error":{"message":"Invalid model: nope"}}"#, .mistral, model: "nope").kind, .missingModel)
        XCTAssertEqual(error(503, "upstream down").message, "OpenAI is having trouble (HTTP 503). Try again in a minute.")
        XCTAssertEqual(error(400, #"{"error":"bad request body"}"#).message, "OpenAI error: bad request body")
        XCTAssertEqual(error(401, "", .custom(baseURL: "https://x.example.com/v1")).message, "The server refused the key. Check it and try again.")
    }

    func testLimitErrors() {
        func limit(_ status: Int, _ body: String, _ provider: Provider = .openAI, retryAfter: String? = nil) -> UsageLimitError? {
            ProviderEngine.httpError(status: status, body: Data(body.utf8), provider: provider, model: "m", retryAfter: retryAfter)
                as? UsageLimitError
        }
        let busy = limit(429, #"{"error":{"message":"Rate limit reached for gpt-x on tokens per min","code":"rate_limit_exceeded"}}"#,
                         retryAfter: "20")
        XCTAssertEqual(busy?.kind, .rateLimited)
        XCTAssertEqual(busy?.message, "OpenAI is limiting requests from your key. Try again in 20 seconds.")

        // OpenAI says "out of credit" with a 429.
        let quota = limit(429, #"{"error":{"message":"You exceeded your current quota.","code":"insufficient_quota"}}"#)
        XCTAssertEqual(quota?.kind, .outOfCredit)
        XCTAssertEqual(quota?.manage, Provider.openAI.billingURL)
        XCTAssertEqual(quota?.message,
                       "OpenAI says your account is out of credit or quota. Check billing in your OpenAI dashboard, or pick another engine.")

        let credits = limit(402, #"{"error":{"message":"Insufficient credits","code":402}}"#, .openRouter)
        XCTAssertEqual(credits?.kind, .outOfCredit)
        XCTAssertEqual(credits?.manage, URL(string: "https://openrouter.ai/settings/credits"))
        // No billing page known: the key page.
        XCTAssertEqual(limit(402, "", .mistral)?.manage, Provider.mistral.consoleURL)
        // Gemini's quota errors come as a one-item array and mention billing.
        let quotaBody = #"[{"error":{"code":429,"message":"You exceeded your current quota, please check your plan and billing details."}}]"#
        let gemini = limit(429, quotaBody, .gemini)
        XCTAssertEqual(gemini?.kind, .outOfCredit)
        XCTAssertNil(limit(402, "", .custom(baseURL: "https://x.example.com/v1"))?.manage)
    }

    func testSplitting() {
        let clean = "Thursday works.\n===\nSure, Thursday."
        XCTAssertEqual(ProviderEngine.split(clean, provider: .openAI, streaming: false, expected: 2), ["Thursday works.", "Sure, Thursday."])
        // A big model that numbered its takes instead of separating them: the forgiving parser catches it.
        let numbered = "1. Thursday works.\n\n2. Sure, Thursday."
        XCTAssertEqual(ProviderEngine.split(numbered, provider: .openAI, streaming: false, expected: 2), ["Thursday works.", "Sure, Thursday."])
        // Small models always go through the cleaner.
        let labelled = "Here are two versions:\nVersion 1: Thursday works.\nVersion 2: Sure, Thursday."
        XCTAssertEqual(ProviderEngine.split(labelled, provider: .groq, streaming: false, expected: 2), ["Thursday works.", "Sure, Thursday."])
    }
}

final class ProviderModelListTests: XCTestCase {
    private func parse(_ json: String, _ provider: Provider) -> [String]? {
        ProviderModelList.parse(Data(json.utf8), provider: provider)
    }

    func testOpenAIDropsNonChatModels() {
        let ids = ["gpt-5.4", "gpt-5.4-mini", "text-embedding-3-small", "whisper-1", "tts-1", "dall-e-3", "gpt-image-1",
                   "omni-moderation-latest", "gpt-4o-realtime-preview", "gpt-4o-audio-preview", "gpt-4o-transcribe",
                   "babbage-002", "o3-pro", "gpt-5-pro-2025-10-06", "gpt-5-codex", "o3-deep-research", "o4-mini", "sora-2"]
        let json = #"{"object":"list","data":["# + ids.map { #"{"id":"\#($0)","object":"model"}"# }.joined(separator: ",") + "]}"
        XCTAssertEqual(parse(json, .openAI), ["gpt-5.4", "gpt-5.4-mini", "o4-mini"])
    }

    func testGeminiStripsPrefixAndKeepsPro() {
        let json = #"{"data":[{"id":"models/gemini-2.5-pro"},{"id":"models/gemini-2.5-flash"},{"id":"models/text-embedding-004"},{"id":"models/imagen-4.0"}]}"#
        XCTAssertEqual(parse(json, .gemini), ["gemini-2.5-flash", "gemini-2.5-pro"])
    }

    func testOpenRouterKeepsTextOutputAndSorts() {
        let json = #"""
        {"data":[
          {"id":"openai/gpt-5.4","architecture":{"input_modalities":["text","image"],"output_modalities":["text"]}},
          {"id":"google/gemini-2.5-flash-image","architecture":{"output_modalities":["image","text"]}},
          {"id":"anthropic/claude-sonnet-4.5","architecture":{"modality":"text+image->text"}},
          {"id":"some/old-model","architecture":{"modality":"text->image"}}
        ]}
        """#
        XCTAssertEqual(parse(json, .openRouter), ["anthropic/claude-sonnet-4.5", "openai/gpt-5.4"])
    }

    func testMistralAndGroqFlags() {
        let mistral = #"{"data":[{"id":"mistral-small-latest","capabilities":{"completion_chat":true}},{"id":"mistral-embed","capabilities":{"completion_chat":false}},{"id":"codestral-mamba","capabilities":{"completion_chat":false}}]}"#
        XCTAssertEqual(parse(mistral, .mistral), ["mistral-small-latest"])
        let groq = #"{"data":[{"id":"llama-3.3-70b-versatile","active":true},{"id":"retired-model","active":false},{"id":"whisper-large-v3","active":true},{"id":"meta-llama/llama-guard-4-12b","active":true}]}"#
        XCTAssertEqual(parse(groq, .groq), ["llama-3.3-70b-versatile"])
    }

    func testNotAListAndAutoPick() {
        XCTAssertNil(parse("<html>", .openAI))
        XCTAssertEqual(parse(#"{"data":[]}"#, .openAI), [])
        XCTAssertEqual(ProviderModelList.autoPick(["gpt-4.1", "gpt-4.1-mini", "gpt-5.4", "gpt-5.4-mini", "gpt-5.4-mini-2026-03-01"], provider: .openAI), "gpt-5.4-mini")
        XCTAssertEqual(ProviderModelList.autoPick(["gemini-3-flash-preview", "gemini-3-flash-preview-09", "gemini-2.5-pro"], provider: .gemini), "gemini-3-flash-preview")
        XCTAssertEqual(ProviderModelList.autoPick(["b", "a"], provider: .custom(baseURL: "https://x.example.com/v1")), "b")
        XCTAssertNil(ProviderModelList.autoPick([], provider: .openAI))
    }
}

final class ProviderSettingsTests: XCTestCase {
    func testOldSettingsGetProviderDefaults() throws {
        let old = #"{"engine":"local","localModel":"llama3.2","defaultTakes":2}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        XCTAssertEqual(settings.engine, .local)
        XCTAssertEqual(settings.providerID, "openai")
        XCTAssertEqual(settings.providerBaseURL, "https://api.openai.com/v1")
        XCTAssertEqual(settings.providerModel, "")
    }

    func testProviderSettingsRoundTrip() throws {
        var settings = AppSettings()
        settings.engine = .provider
        settings.providerID = "custom"
        settings.providerBaseURL = "https://llm.example.com/v1"
        settings.providerModel = "qwen3-32b"
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.engine, .provider)
        XCTAssertEqual(decoded.providerID, "custom")
        XCTAssertEqual(decoded.providerBaseURL, "https://llm.example.com/v1")
        XCTAssertEqual(decoded.providerModel, "qwen3-32b")
        // The key is never in the settings file.
        let text = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        XCTAssertFalse(text.lowercased().contains("apikey\""))
    }

    func testOneModelHooks() {
        let preset = Preset(name: "P", colorHex: "#000000", instruction: "x")
        var settings = AppSettings()
        settings.engine = .provider
        settings.providerModel = "gpt-5.4"
        XCTAssertTrue(settings.engine.usesOneModel)
        XCTAssertEqual(settings.runModel(for: preset), "gpt-5.4")
        XCTAssertEqual(settings.quickModel, "gpt-5.4")
        XCTAssertEqual(settings.oneModelPlace, "via OpenAI")
        XCTAssertEqual(preset.summary(for: settings), "3 takes · gpt-5.4 via OpenAI · same or shorter")
        XCTAssertEqual(preset.model, Models.sonnet)
        settings.engine = .claudeCode
        XCTAssertEqual(settings.runModel(for: preset), Models.sonnet)
    }

    func testEnginesPicksProvider() {
        var settings = AppSettings()
        settings.engine = .provider
        XCTAssertTrue(Engines.current(settings) is ProviderEngine)
    }

    func testKeychainAccountsAreSeparate() {
        let account = "provider-test-\(UUID().uuidString).example.com"
        defer { Keychain.set(nil, account: account) }
        XCTAssertNil(Keychain.string(account: account))
        Keychain.set("secret-1", account: account)
        XCTAssertEqual(Keychain.string(account: account), "secret-1")
        Keychain.set("secret-2", account: account)
        XCTAssertEqual(Keychain.string(account: account), "secret-2")
        Keychain.set("", account: account)
        XCTAssertNil(Keychain.string(account: account))
    }
}

// MARK: - Against a mock server on 127.0.0.1

final class ProviderEngineServerTests: XCTestCase {
    override func setUp() { ProviderEndpoint.allowInsecureForTests = true }
    override func tearDown() { ProviderEndpoint.allowInsecureForTests = false }

    /// A provider that talks like OpenAI (no strict format) at the mock server's address.
    private func provider(_ server: ProviderMockServer, id: String = "openai") -> Provider {
        var provider = Provider.custom(baseURL: server.baseURL)
        provider.id = id
        provider.name = "OpenAI"
        provider.strictFormat = false
        return provider
    }

    func testStreamsTakesWithBearerKey() async throws {
        let sse = [
            #"data: {"choices":[{"delta":{"role":"assistant","content":""}}]}"#, "",
            #"data: {"choices":[{"delta":{"content":"Thursday "}}]}"#, "",
            #"data: {"choices":[{"delta":{"content":"works.\n==="}}]}"#, "",
            #"data: {"choices":[{"delta":{"content":"\nSure, Thursday."}}]}"#, "",
            #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#, "",
            "data: [DONE]", "", "",
        ].joined(separator: "\n")
        let server = try ProviderMockServer { path, headers, body in
            XCTAssertEqual(path, "/v1/chat/completions")
            XCTAssertTrue(headers.contains("authorization: Bearer sk-test"), headers)
            let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            XCTAssertEqual(json?["model"] as? String, "gpt-4.1-mini")
            XCTAssertFalse(((json?["messages"] as? [[String: String]])?.first?["content"] ?? "").contains("Output format"))
            return .init(status: 200, contentType: "text/event-stream", chunks: LocalEngineServerTestsChunks.chunked(sse, size: 13))
        }
        defer { server.stop() }
        let updates = ProviderUpdateLog()
        let engine = ProviderEngine(settings: AppSettings(), key: "sk-test", provider: provider(server))
        let result = try await engine.run(request(takes: 2, model: "gpt-4.1-mini")) { updates.add($0) }
        XCTAssertEqual(result.takes, ["Thursday works.", "Sure, Thursday."])
        XCTAssertNotNil(result.firstTextMs)
        XCTAssertFalse(updates.all.flatMap { $0 }.contains { $0.contains("=") })
    }

    func testRetriesWithoutRejectedField() async throws {
        let bodies = ProviderUpdateLog()
        let server = try ProviderMockServer { _, _, body in
            let json = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
            bodies.add([json["temperature"] == nil ? "no-temperature" : "temperature"])
            if json["temperature"] != nil {
                return .init(status: 400, contentType: "application/json",
                             chunks: [Data(#"{"error":{"message":"Unsupported value: 'temperature' does not support 0.7 with this model."}}"#.utf8)])
            }
            let sse = #"data: {"choices":[{"delta":{"content":"Thursday works."}}]}"# + "\n\ndata: [DONE]\n\n"
            return .init(status: 200, contentType: "text/event-stream", chunks: [Data(sse.utf8)])
        }
        defer { server.stop() }
        let engine = ProviderEngine(settings: AppSettings(), key: "k", provider: provider(server, id: "custom"))
        let result = try await engine.run(request(takes: 1, model: "some-model")) { _ in }
        XCTAssertEqual(result.takes, ["Thursday works."])
        XCTAssertEqual(bodies.all.flatMap { $0 }, ["temperature", "no-temperature"])
    }

    func testContentFilterIsReported() async throws {
        let sse = #"data: {"choices":[{"delta":{"content":""},"finish_reason":"content_filter"}]}"# + "\n\ndata: [DONE]\n\n"
        let server = try ProviderMockServer { _, _, _ in .init(status: 200, contentType: "text/event-stream", chunks: [Data(sse.utf8)]) }
        defer { server.stop() }
        do {
            _ = try await ProviderEngine(settings: AppSettings(), key: "k", provider: provider(server)).run(request(takes: 1)) { _ in }
            XCTFail("should fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The provider declined to rewrite this draft.")
        }
    }

    func testRefusedKeyAndMissingModel() async throws {
        let server = try ProviderMockServer { path, _, body in
            if String(decoding: body, as: UTF8.self).contains("nope") {
                return .init(status: 404, contentType: "application/json",
                             chunks: [Data(#"{"error":{"message":"The model `nope` does not exist"}}"#.utf8)])
            }
            return .init(status: 401, contentType: "application/json", chunks: [Data(#"{"error":{"message":"Incorrect API key"}}"#.utf8)])
        }
        defer { server.stop() }
        let engine = ProviderEngine(settings: AppSettings(), key: "bad", provider: provider(server))
        do {
            _ = try await engine.run(request(takes: 1)) { _ in }
            XCTFail("should fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The key was refused. Check it in your OpenAI dashboard.")
        }
        do {
            _ = try await engine.run(request(takes: 1, model: "nope")) { _ in }
            XCTFail("should fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "OpenAI doesn't have the model “nope”. Pick another in Settings › Model.")
        }
        do {
            _ = try await ProviderEngine.models(provider: provider(server), key: "bad")
            XCTFail("should fail")
        } catch let error as ProviderError {
            XCTAssertEqual(error.kind, .keyRefused)
        }
    }

    func testRedirectToAnotherHostIsNotFollowed() async throws {
        let server = try ProviderMockServer { _, _, _ in
            .init(status: 302, contentType: "text/plain", chunks: [Data()], headers: ["Location": "https://example.com/v1/chat/completions"])
        }
        defer { server.stop() }
        do {
            _ = try await ProviderEngine(settings: AppSettings(), key: "k", provider: provider(server)).run(request(takes: 1)) { _ in }
            XCTFail("should fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("another address"), error.localizedDescription)
        }
    }

    func testModelListAndTest() async throws {
        let server = try ProviderMockServer { path, headers, _ in
            XCTAssertTrue(headers.contains("authorization: Bearer k"), headers)
            if path == "/v1/models" {
                return .init(status: 200, contentType: "application/json",
                             chunks: [Data(#"{"data":[{"id":"text-embedding-3-small"},{"id":"gpt-5.4"},{"id":"gpt-4.1-mini"}]}"#.utf8)])
            }
            return .init(status: 200, contentType: "application/json",
                         chunks: [Data(#"{"choices":[{"message":{"role":"assistant","content":"OK"},"finish_reason":"stop"}]}"#.utf8)])
        }
        defer { server.stop() }
        let models = try await ProviderEngine.models(provider: provider(server), key: "k")
        XCTAssertEqual(models, ["gpt-4.1-mini", "gpt-5.4"])
        var settings = AppSettings()
        settings.providerModel = "gpt-5.4"
        let result = await ProviderEngine.test(settings: settings, key: "k", provider: provider(server))
        if case .failure(let error) = result { XCTFail(error.localizedDescription) }
    }

    func testNothingAnswering() async throws {
        let server = try ProviderMockServer { _, _, _ in .init(status: 200, contentType: "text/plain", chunks: []) }
        let gone = provider(server, id: "custom")
        server.stop()
        try await Task.sleep(for: .milliseconds(100))
        do {
            _ = try await ProviderEngine(settings: AppSettings(), key: "k", provider: gone).run(request(takes: 1)) { _ in }
            XCTFail("should fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.hasPrefix("Couldn't reach"), error.localizedDescription)
        }
    }
}

private enum LocalEngineServerTestsChunks {
    static func chunked(_ text: String, size: Int) -> [Data] {
        let bytes = Array(text.utf8)
        return stride(from: 0, to: bytes.count, by: size).map { Data(bytes[$0..<min($0 + size, bytes.count)]) }
    }
}

private func request(takes: Int, model: String = "gpt-5.4") -> EngineRequest {
    EngineRequest(system: "Rewrite.", user: "<draft>\nhi\n</draft>", takes: takes, model: model, effort: "low")
}

private final class ProviderUpdateLog: @unchecked Sendable {
    private let lock = NSLock()
    private var updates: [[String]] = []
    func add(_ takes: [String]) { lock.lock(); updates.append(takes); lock.unlock() }
    var all: [[String]] { lock.lock(); defer { lock.unlock() }; return updates }
}

/// A one-route HTTP server on 127.0.0.1, like the one in LocalModelsTests, that also hands the handler the request headers.
private final class ProviderMockServer: @unchecked Sendable {
    struct Response {
        var status: Int
        var contentType: String
        var chunks: [Data]
        var headers: [String: String] = [:]
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "provider-mock-server")
    private let handler: (String, String, Data) -> Response
    private(set) var port: UInt16 = 0
    var baseURL: String { "http://127.0.0.1:\(port)/v1" }

    init(handler: @escaping (_ path: String, _ headers: String, _ body: Data) -> Response) throws {
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
            // Header names lowercased, values kept, so tests can look for "authorization: Bearer …".
            let headers = head.split(separator: "\r\n").dropFirst().map { line -> String in
                guard let colon = line.firstIndex(of: ":") else { return String(line) }
                return line[..<colon].lowercased() + ":" + line[line.index(after: colon)...]
            }.joined(separator: "\n")
            self.respond(connection, self.handler(path, headers, Data(body)))
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
