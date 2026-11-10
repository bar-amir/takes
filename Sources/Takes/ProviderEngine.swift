import AppKit
import CryptoKit
import Foundation

// A fourth engine: the user's own API key for OpenAI, or another provider that serves the OpenAI chat-completions
// API over https (Gemini, OpenRouter, Groq, Mistral, or a custom address). Billed by the provider under the user's
// account. The wire format is the one LocalEngine already speaks (SSEParser, LocalChunk, LocalEngine.chatRequest);
// this engine adds a bearer key, https-only addresses and provider-specific wording.
//
// One model for every preset while this engine is on, like Local model (see LocalEngine.swift's hooks). Keys live in
// the login keychain, one item per provider host ("provider-api.openai.com"), never in settings, logs or snapshots.

/// A provider Takes knows how to talk to.
struct Provider: Equatable, Identifiable {
    var id: String
    var name: String
    var baseURL: String
    /// Where to get a key ("Get a key").
    var consoleURL: URL?
    /// How the provider's keys start, for the placeholder and the "wrong key" note.
    var keyPrefix: String?
    /// One line on the card: where drafts go and under whose terms.
    var dataNote: String
    /// Small models: append `LocalPrompt.formatRules` and parse with `LocalTakeCleaner`.
    var strictFormat = false
    var extraHeaders: [String: String] = [:]
    /// Tried in order when no model is picked: an exact ID first, then the shortest ID starting with it.
    var preferredModels: [String] = []
    /// Where to add credit; `consoleURL` when nil.
    var billingURL: URL?

    var isCustom: Bool { id == Provider.customID }
    static let customID = "custom"

    // https://platform.openai.com/docs/api-reference/chat · models: https://platform.openai.com/docs/api-reference/models/list
    // Data: https://openai.com/enterprise-privacy/ (API data isn't used for training by default).
    static let openAI = Provider(
        id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1",
        consoleURL: URL(string: "https://platform.openai.com/api-keys"), keyPrefix: "sk-",
        dataNote: String(localized: "Takes sends your drafts to OpenAI under your own API account. OpenAI's API terms apply, and it bills you per use."),
        preferredModels: ["gpt-5.4-mini", "gpt-5-mini", "gpt-4.1-mini", "gpt-4o-mini"],
        billingURL: URL(string: "https://platform.openai.com/settings/organization/billing/overview"))

    // OpenAI compatibility: https://ai.google.dev/gemini-api/docs/openai · terms: https://ai.google.dev/gemini-api/terms
    // (in the EEA, Switzerland and the UK, apps may only use paid keys).
    static let gemini = Provider(
        id: "gemini", name: "Google Gemini", baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
        consoleURL: URL(string: "https://aistudio.google.com/apikey"), keyPrefix: "AIza",
        dataNote: String(localized: "Takes sends your drafts to Google under your own Gemini API key. Google's Gemini API terms apply, and it bills your project."),
        preferredModels: ["gemini-3-flash", "gemini-2.5-flash", "gemini-flash-latest"])

    // https://openrouter.ai/docs/api-reference/overview · app attribution headers: https://openrouter.ai/docs/app-attribution
    // Data: https://openrouter.ai/privacy (requests go on to the company that runs the model).
    static let openRouter = Provider(
        id: "openrouter", name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1",
        consoleURL: URL(string: "https://openrouter.ai/settings/keys"), keyPrefix: "sk-or-",
        dataNote: String(localized: "Takes sends your drafts to OpenRouter under your own account, and OpenRouter passes them to the company that runs the model you pick. Both companies' terms apply."),
        extraHeaders: ["X-Title": "Takes"],
        preferredModels: ["openai/gpt-5.4-mini", "openai/gpt-5-mini", "google/gemini-2.5-flash"],
        billingURL: URL(string: "https://openrouter.ai/settings/credits"))

    // OpenAI compatibility: https://console.groq.com/docs/openai · data: https://console.groq.com/docs/your-data
    static let groq = Provider(
        id: "groq", name: "Groq", baseURL: "https://api.groq.com/openai/v1",
        consoleURL: URL(string: "https://console.groq.com/keys"), keyPrefix: "gsk_",
        dataNote: String(localized: "Takes sends your drafts to Groq under your own API account. Groq's terms apply, and it bills you per use."),
        strictFormat: true,
        preferredModels: ["llama-3.3-70b-versatile", "openai/gpt-oss-120b"],
        billingURL: URL(string: "https://console.groq.com/settings/billing"))

    // https://docs.mistral.ai/api/ · terms: https://mistral.ai/terms
    static let mistral = Provider(
        id: "mistral", name: "Mistral", baseURL: "https://api.mistral.ai/v1",
        consoleURL: URL(string: "https://console.mistral.ai/api-keys"),
        dataNote: String(localized: "Takes sends your drafts to Mistral under your own API account. Mistral's terms apply, and it bills you per use."),
        preferredModels: ["mistral-medium-latest", "mistral-small-latest", "mistral-large-latest"])

    static let known: [Provider] = [openAI, gemini, openRouter, groq, mistral]

    /// Any server that speaks the OpenAI chat-completions API over https, at the address the user typed.
    static func custom(baseURL: String) -> Provider {
        Provider(id: customID, name: URL(string: baseURL)?.host ?? String(localized: "Your server"), baseURL: baseURL,
                 dataNote: String(localized: "Takes sends your drafts to this address. Only use a server you trust."), strictFormat: true)
    }

    /// The provider the settings point at ("custom" for an address Takes doesn't know).
    static func current(_ settings: AppSettings) -> Provider {
        known.first { $0.id == settings.providerID } ?? custom(baseURL: settings.providerBaseURL)
    }

    // MARK: Key

    /// The keychain account for this provider's key: one per host.
    var keyAccount: String? {
        guard let host = URL(string: baseURL)?.host?.lowercased(), !host.isEmpty else { return nil }
        return "provider-\(host)"
    }

    var key: String? {
        guard let keyAccount, let key = Keychain.string(account: keyAccount), !key.isEmpty else { return nil }
        return key
    }

    /// Saves or removes the key. False when there's no host to save it under or the keychain refused.
    @discardableResult
    func setKey(_ key: String?) -> Bool {
        guard let keyAccount else { return false }
        return Keychain.set(key?.trimmingCharacters(in: .whitespacesAndNewlines), account: keyAccount)
    }

    var keyPlaceholder: String { keyPrefix.map { String(localized: "Paste your key (\($0)…)") } ?? String(localized: "Paste your key") }

    /// Longest prefix first: "sk-ant-" and "sk-or-" also start with "sk-".
    private static let keyOwners: [(prefix: String, name: String, article: String)] = [
        ("sk-ant-", "Anthropic", "an"), ("sk-or-", "OpenRouter", "an"), ("gsk_", "Groq", "a"),
        ("AIza", "Google Gemini", "a"), ("sk-", "OpenAI", "an"),
    ]

    /// "This looks like an Anthropic key…" when a key's prefix belongs to another provider; nil when it fits or can't tell.
    func keyNote(_ key: String) -> String? {
        guard !isCustom else { return nil }
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let owner = Self.keyOwners.first(where: { key.hasPrefix($0.prefix) }), owner.name != name else { return nil }
        return owner.article == "an"
            ? String(localized: "This looks like an \(owner.name) key. \(name) needs a key from its own dashboard.")
            : String(localized: "This looks like a \(owner.name) key. \(name) needs a key from its own dashboard.")
    }

    /// "Check it in your OpenAI dashboard."
    var refusedMessage: String {
        isCustom ? String(localized: "The server refused the key. Check it and try again.") : String(localized: "The key was refused. Check it in your \(name) dashboard.")
    }
}

// MARK: - Addresses

/// The inverse of `LocalEndpoint`: https only, no userinfo, nothing on this Mac (that's the Local model row), no IP
/// literals. Checked on every request URL, not just in settings.
enum ProviderEndpoint {
    /// Tests run a mock server on http://127.0.0.1. Never set outside tests.
    static var allowInsecureForTests = false

    static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), url.user == nil, url.password == nil,
              let rawHost = url.host?.lowercased(), !rawHost.isEmpty else { return false }
        if allowInsecureForTests, scheme == "http" || scheme == "https", LocalEndpoint.isLoopback(url) { return true }
        guard scheme == "https" else { return false }
        var host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        while host.hasSuffix(".") { host.removeLast() }
        if host.isEmpty || host == "localhost" || host.hasSuffix(".localhost") { return false }
        return !isIPLiteral(host)
    }

    /// IPv6 has colons; IPv4 in any spelling ("127.1", "2130706433", "0x7f.1") ends in a label no real domain ends in.
    static func isIPLiteral(_ host: String) -> Bool {
        if host.contains(":") { return true }
        guard let last = host.split(separator: ".").last else { return true }
        return last.allSatisfy(\.isNumber) || last.hasPrefix("0x")
    }

    /// Turns what the user typed ("llm.example.com") into a base URL ("https://llm.example.com/v1"), or nil if it isn't allowed.
    static func normalize(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard var components = URLComponents(string: text), components.query == nil, components.fragment == nil else { return nil }
        if components.path.isEmpty { components.path = "/v1" }
        guard let url = components.url, isAllowed(url) else { return nil }
        return url.absoluteString
    }

    /// `{base}/{path}`, only when the result is allowed.
    static func url(_ baseURL: String, _ path: String) -> URL? {
        var base = baseURL
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty, let url = URL(string: base + "/" + path), isAllowed(url) else { return nil }
        return url
    }

    /// No cookies or cache on disk; system proxies apply (unlike local); redirects only to the same host.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config, delegate: SameHostRedirectGuard(), delegateQueue: nil)
    }()
}

final class SameHostRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let from = task.originalRequest?.url?.host?.lowercased()
        let allowed = request.url.map { ProviderEndpoint.isAllowed($0) && $0.host?.lowercased() == from } ?? false
        completionHandler(allowed ? request : nil)
    }
}

// MARK: - Errors

/// What went wrong, in words the user can act on. `kind` drives the card's badge.
struct ProviderError: LocalizedError, Equatable {
    enum Kind: Equatable { case keyRefused, missingModel, declined, other }
    var kind: Kind
    var message: String
    var errorDescription: String? { message }

    static let declined = ProviderError(kind: .declined, message: String(localized: "The provider declined to rewrite this draft."))
}

// MARK: - Model lists

enum ProviderModelList {
    /// Words in IDs of models that can't write takes: embeddings, speech, images, moderation, realtime audio, and
    /// OpenAI's Responses-only models.
    private static let notChat = ["embed", "audio", "image", "tts", "whisper", "dall-e", "moderation", "realtime",
                                  "transcribe", "babbage", "davinci", "sora", "computer-use", "imagen", "veo", "aqa",
                                  "lyria", "guard", "ocr", "codex", "deep-research"]

    /// Model IDs from `GET /models`, filtered to chat models and sorted; nil when the answer isn't a model list.
    static func parse(_ data: Data, provider: Provider) -> [String]? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let entries = json["data"] as? [[String: Any]] ?? json["models"] as? [[String: Any]] ?? []
        let ids = entries.compactMap { entry -> String? in
            guard var id = entry["id"] as? String ?? entry["name"] as? String, isChat(entry, id: id, provider: provider) else { return nil }
            // Gemini lists "models/gemini-2.5-flash"; chat completions takes "gemini-2.5-flash".
            if id.hasPrefix("models/") { id.removeFirst("models/".count) }
            return id
        }
        return Array(Set(ids)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func isChat(_ entry: [String: Any], id: String, provider: Provider) -> Bool {
        let lower = id.lowercased()
        if notChat.contains(where: lower.contains) { return false }
        // OpenAI's "-pro" models (o3-pro, gpt-5-pro) only answer on the Responses API.
        if provider.id == Provider.openAI.id, lower.hasSuffix("-pro") || lower.contains("-pro-") { return false }
        // OpenRouter: keep models that write text and nothing else.
        if let architecture = entry["architecture"] as? [String: Any] {
            if let outputs = architecture["output_modalities"] as? [String] { return outputs == ["text"] }
            if let modality = architecture["modality"] as? String { return modality.hasSuffix("->text") }
        }
        // Mistral says which models chat.
        if let capabilities = entry["capabilities"] as? [String: Any], let chat = capabilities["completion_chat"] as? Bool { return chat }
        // Groq marks retired models inactive.
        if let active = entry["active"] as? Bool { return active }
        return true
    }

    /// The model to pick when none is: the provider's preferred one if listed, else the first.
    static func autoPick(_ models: [String], provider: Provider) -> String? {
        for preferred in provider.preferredModels {
            if models.contains(preferred) { return preferred }
            if let match = models.filter({ $0.hasPrefix(preferred) }).min(by: { $0.count < $1.count }) { return match }
        }
        return models.first
    }
}

// MARK: - Requests

/// Fields some models reject. Starts from what the model is known to need, and changes once per 400 that names a field.
struct ProviderRequestOptions: Equatable {
    var tokenField = "max_tokens"
    var temperature = true
    var reasoningEffort: String?
    /// The most tokens this model takes, once a 400 has said so ("max_tokens is too large … at most 16384").
    var tokenLimit: Int?

    /// OpenAI's reasoning models (o1, o3, o4-mini, gpt-5…) take `max_completion_tokens`, no temperature, and a
    /// reasoning effort; takes are short rewrites, so low effort keeps them quick.
    static func initial(provider: Provider, model: String) -> ProviderRequestOptions {
        guard provider.id == Provider.openAI.id, isReasoningModel(model) else { return ProviderRequestOptions() }
        return ProviderRequestOptions(tokenField: "max_completion_tokens", temperature: false, reasoningEffort: "low")
    }

    static func isReasoningModel(_ model: String) -> Bool {
        let id = model.lowercased()
        if id.contains("chat") { return false }
        if id.hasPrefix("gpt-5") { return true }
        guard id.hasPrefix("o"), let second = id.dropFirst().first else { return false }
        return second.isNumber
    }

    /// The options to retry with after a 400 that names a field, or nil when there's nothing left to change.
    /// `maxTokens` is the cap the refused request asked for.
    func adjusted(after message: String, maxTokens: Int? = nil) -> ProviderRequestOptions? {
        let lower = message.lowercased()
        var next = self
        if Self.saysCapTooBig(lower) {
            // The field was fine, the number too big: keep the field and ask for less, if there's less to ask for.
            if let limit = Self.tokenLimit(in: lower, asked: maxTokens) { next.tokenLimit = min(limit, tokenLimit ?? .max) }
        } else if lower.contains("max_tokens"), tokenField == "max_tokens" {
            next.tokenField = "max_completion_tokens"
        }
        if lower.contains("temperature"), temperature { next.temperature = false }
        if lower.contains("reasoning_effort") || lower.contains("reasoning effort"), reasoningEffort != nil { next.reasoningEffort = nil }
        return next == self ? nil : next
    }

    /// A 400 about the token cap's size (not its name), or about the prompt and the cap not fitting the context.
    static func saysCapTooBig(_ message: String) -> Bool {
        let lower = message.lowercased()
        if saysContextTooSmall(lower) { return true }
        let namesCap = ["max_tokens", "max_completion_tokens", "max_output_tokens", "max tokens", "maximum tokens"].contains(where: lower.contains)
        let tooBig = ["too large", "at most", "less than or equal", "exceed", "maximum value", "maximum allowed", "greater than",
                      "must be <=", "out of range"].contains(where: lower.contains)
        return namesCap && tooBig
    }

    /// "This model's maximum context length is 32768 tokens. However, you requested 34000 tokens (2000 in the
    /// messages, 32000 in the completion)", vLLM's "… and your request has 2000 input tokens", `context_length_exceeded`.
    static func saysContextTooSmall(_ message: String) -> Bool {
        let lower = message.lowercased()
        return ["context length", "context window", "context_length_exceeded", "maximum context", "context size"].contains(where: lower.contains)
    }

    /// Asked for when a model's own limit is too big to read from its error.
    static let fallbackTokenLimit = 8000
    /// No cap is lowered below this: fewer tokens can't hold a take, and a smaller number in a message isn't a limit.
    static let minimumTokenLimit = 256

    /// For a 400 that says the cap is too big, the cap to ask for instead: what the context leaves after the prompt,
    /// when the message gives both; else the limit it names ("supports at most 16,384 completion tokens", "must be
    /// less than or equal to `32768`"); else `fallback` (the cap that always worked) when that's less than was asked.
    /// Nil when the message isn't about the cap, or no smaller cap can help (the prompt alone fills the context).
    static func tokenLimit(in message: String, asked: Int?, fallback: Int = fallbackTokenLimit) -> Int? {
        let lower = joiningDigitGroups(message.lowercased())
        guard saysCapTooBig(lower) else { return nil }
        var limit: Int?
        if saysContextTooSmall(lower), let context = firstNumber(in: lower, after: contextPattern) {
            if let input = firstNumber(in: lower, after: inputPattern) {
                // A little room for the chat template's own tokens.
                let fit = context - input - 64
                guard fit >= minimumTokenLimit else { return nil }
                limit = fit
            }
        } else {
            limit = numbers(in: lower, after: limitPattern).filter { $0 >= minimumTokenLimit }.min()
        }
        if let limit, limit >= minimumTokenLimit, asked.map({ limit < $0 }) ?? true { return limit }
        guard let asked else { return fallback }
        return asked > fallback ? fallback : nil
    }

    private static let contextPattern = try! NSRegularExpression(
        pattern: #"context (?:length|window|size)(?: is| of)?(?: only)?\s*[`'"]?(\d+)"#)
    private static let inputPattern = try! NSRegularExpression(
        pattern: #"(\d+)\s*(?:tokens?\s*)?(?:in the (?:messages|prompt)|input tokens|prompt tokens)|request has\s*(\d+)"#)
    private static let limitPattern = try! NSRegularExpression(
        pattern: #"(?:at most|less than or equal to|<=|>|up to|maximum(?: value)?(?: is| of)?|limit(?: is| of)?|supports)\s*[`'"]?(\d+)"#)

    /// "16,384" → "16384", "32_000" → "32000".
    static func joiningDigitGroups(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?<=\d)[,_](?=\d{3}(?!\d))"#, with: "", options: .regularExpression)
    }

    private static func numbers(in text: String, after pattern: NSRegularExpression) -> [Int] {
        pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            (1..<match.numberOfRanges).lazy.compactMap { Range(match.range(at: $0), in: text).flatMap { Int(text[$0]) } }.first
        }
    }

    private static func firstNumber(in text: String, after pattern: NSRegularExpression) -> Int? {
        numbers(in: text, after: pattern).first
    }
}

/// Streams takes from an OpenAI-compatible server over https with the user's key.
struct ProviderEngine: TakesEngine {
    var settings: AppSettings
    /// The key and provider, when they don't come from the keychain and settings (tests).
    var keyOverride: String?
    var providerOverride: Provider?

    init(settings: AppSettings, key: String? = nil, provider: Provider? = nil) {
        self.settings = settings
        keyOverride = key
        providerOverride = provider
    }

    func run(_ request: EngineRequest, onUpdate: @escaping @Sendable ([String]) -> Void) async throws -> EngineResult {
        let provider = providerOverride ?? Provider.current(settings)
        guard let url = ProviderEndpoint.url(provider.baseURL, "chat/completions") else {
            throw EngineError.failed(String(localized: "Add an https address for your server in Settings › Model."))
        }
        guard let key = keyOverride ?? provider.key else {
            throw EngineError.failed(String(localized: "Add your \(provider.name) API key in Settings › Model."))
        }
        guard !request.model.isEmpty else { throw EngineError.failed(String(localized: "Pick a model in Settings › Model.")) }
        let system = provider.strictFormat ? request.system + "\n" + LocalPrompt.formatRules(takes: request.takes) : request.system

        let started = Date()
        let elapsedMs = { Int(Date().timeIntervalSince(started) * 1000) }
        var options = ProviderRequestOptions.initial(provider: provider, model: request.model)
        var bytes: URLSession.AsyncBytes!
        // Each 400 names one thing to change. Fields (token field, temperature, effort) and a smaller cap each get two
        // retries of their own, so at most five requests in all.
        var fieldRetries = 0, capRetries = 0
        while true {
            let maxTokens = Self.maxTokens(for: request, options: options)
            let urlRequest = try Self.chatRequest(url: url, key: key, provider: provider, model: request.model, system: system,
                                                  user: request.user, stream: true, maxTokens: maxTokens,
                                                  options: options)
            let response: URLResponse
            do {
                (bytes, response) = try await ProviderEndpoint.session.bytes(for: urlRequest)
            } catch {
                throw Self.friendly(error, provider: provider)
            }
            guard let http = response as? HTTPURLResponse else { throw EngineError.failed(String(localized: "No answer from \(provider.name).")) }
            if http.statusCode == 200 { break }
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            if http.statusCode == 400, let next = options.adjusted(after: Self.message(data), maxTokens: maxTokens) {
                var sameFields = next
                sameFields.tokenLimit = options.tokenLimit
                let capOnly = sameFields == options
                if capOnly ? capRetries < 2 : fieldRetries < 2 {
                    if capOnly { capRetries += 1 } else { fieldRetries += 1 }
                    options = next
                    continue
                }
            }
            throw Self.httpError(status: http.statusCode, body: data, provider: provider, model: request.model,
                                 retryAfter: http.value(forHTTPHeaderField: "retry-after"))
        }

        var parser = SSEParser()
        var text = ""
        var firstTextMs: Int?
        var filtered = false
        var ranOut = false
        var done = false
        var line = Data()

        func handle(_ events: [SSEParser.Event]) throws {
            for event in events {
                if event == .done { done = true }
                guard case .data(let payload) = event, let chunk = LocalChunk.parse(payload) else { continue }
                if let error = chunk.error { throw EngineError.failed(String(localized: "\(provider.name): \(error)")) }
                if chunk.finishReason == "content_filter" { filtered = true }
                if chunk.finishReason != nil { done = true }
                if chunk.ranOutOfRoom { ranOut = true }
                guard let piece = chunk.text, !piece.isEmpty else { continue }
                if firstTextMs == nil { firstTextMs = elapsedMs() }
                text += piece
                onUpdate(Self.split(text, provider: provider, streaming: true, expected: request.takes))
            }
        }

        do {
            for try await byte in bytes {
                line.append(byte)
                if byte == 0x0A {
                    try handle(parser.feed(line))
                    line.removeAll(keepingCapacity: true)
                }
            }
            try handle(parser.feed(line))
            try handle(parser.finish())
        } catch let error as EngineError {
            throw error
        } catch {
            throw Self.friendly(error, provider: provider)
        }

        if filtered { throw ProviderError.declined }
        // Out of room, or a stream that ended with neither a finish reason nor [DONE] (a dropped connection): the
        // answer is unfinished, and split like one still streaming so a half-written separator isn't kept as text.
        let stoppedEarly = ranOut || !done
        let takes = Self.split(text, provider: provider, streaming: stoppedEarly, expected: request.takes)
        guard !takes.isEmpty else {
            if !done {
                throw EngineError.failed(String(localized: "The connection to \(provider.name) dropped before the takes were done. Try again."))
            }
            if ranOut {
                throw EngineError.failed(String(localized: "\(provider.name) ran out of room before writing a take. Try again, or pick another model."))
            }
            throw EngineError.failed(String(localized: "\(provider.name) returned no takes. Try again, or pick another model."))
        }
        let cutShort = provider.strictFormat
            ? TakeSplitter.cutShort(text, stoppedEarly: stoppedEarly, endsTake: LocalTakeCleaner.endsTake)
            : TakeSplitter.cutShort(text, stoppedEarly: stoppedEarly)
        return EngineResult(takes: takes, wallMs: elapsedMs(), firstTextMs: firstTextMs, cutShort: cutShort)
    }

    /// The cap for this request: room for every take, 4,000 more for a model that reasons first, at least the 8,000
    /// that always worked and at most 32,000; lower once the model has said what it takes.
    static func maxTokens(for request: EngineRequest, options: ProviderRequestOptions) -> Int {
        let reserve = options.tokenField == "max_completion_tokens" || options.reasoningEffort != nil ? 4000 : 0
        let budget = OutputBudget.maxTokens(for: request, floor: 8000, ceiling: 32_000, reserve: reserve)
        return min(budget, options.tokenLimit ?? .max)
    }

    /// Big models follow the `===` format; small ones (and a result with fewer takes than asked) get the forgiving parser.
    static func split(_ text: String, provider: Provider, streaming: Bool, expected: Int) -> [String] {
        if provider.strictFormat { return LocalTakeCleaner.split(text, streaming: streaming, expected: expected) }
        let takes = TakeSplitter.split(text, streaming: streaming)
        guard !streaming, takes.count < expected else { return takes }
        let cleaned = LocalTakeCleaner.split(text, streaming: false, expected: expected)
        return cleaned.count > takes.count ? cleaned : takes
    }

    /// `LocalEngine.chatRequest` with the bearer key, the provider's headers and the fields this model takes.
    static func chatRequest(url: URL, key: String, provider: Provider, model: String, system: String, user: String,
                            stream: Bool, maxTokens: Int, options: ProviderRequestOptions) throws -> URLRequest {
        var request = try LocalEngine.chatRequest(url: url, model: model, system: system, user: user, stream: stream, maxTokens: maxTokens)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        for (name, value) in provider.extraHeaders { request.setValue(value, forHTTPHeaderField: name) }
        guard var body = request.httpBody.flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) else { return request }
        if options.tokenField != "max_tokens" {
            body[options.tokenField] = body.removeValue(forKey: "max_tokens")
        }
        if !options.temperature { body.removeValue(forKey: "temperature") }
        if let effort = options.reasoningEffort { body["reasoning_effort"] = effort }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// The error message in a body: `{"error": {"message": …}}`, `{"error": "…"}`, or Gemini's `[{"error": …}]`.
    static func message(_ body: Data) -> String {
        let json = try? JSONSerialization.jsonObject(with: body)
        let object = json as? [String: Any] ?? (json as? [[String: Any]])?.first
        if let object, let message = LocalChunk.errorMessage(object) { return message }
        if let detail = object?["detail"] as? String { return detail }
        return String(decoding: body.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A `ProviderError`, or a `UsageLimitError` for 402 and 429.
    static func httpError(status: Int, body: Data, provider: Provider, model: String, retryAfter: String? = nil) -> Error {
        let message = message(body)
        let lower = message.lowercased()
        let badKey = lower.contains("api key") && (lower.contains("not valid") || lower.contains("invalid") || lower.contains("incorrect"))
        if status == 401 || badKey || (status == 403 && lower.contains("key")) {
            return ProviderError(kind: .keyRefused, message: provider.refusedMessage)
        }
        // OpenAI says "out of credit" with a 429 and `insufficient_quota`; Gemini's quota errors mention billing.
        if status == 402 || (status == 429 && (errorCode(body) == "insufficient_quota"
                                               || ["credit", "billing", "insufficient_quota"].contains(where: lower.contains))) {
            let creditMessage = provider.isCustom
                ? String(localized: "\(provider.name) says your account is out of credit or quota. Check the account for this server, or pick another engine.")
                : String(localized: "\(provider.name) says your account is out of credit or quota. Check billing in your \(provider.name) dashboard, or pick another engine.")
            return UsageLimitError(kind: .outOfCredit,
                                   message: creditMessage,
                                   manage: provider.isCustom ? nil : provider.billingURL ?? provider.consoleURL)
        }
        if status == 429 {
            return UsageLimitError(kind: .rateLimited,
                                   message: String(localized: "\(provider.name) is limiting requests from your key. \(UsageLimitError.retryHint(retryAfter))"))
        }
        let modelMissing = lower.contains("model") && ["not found", "does not exist", "not exist", "invalid model", "no such model", "unknown model", "not a valid model"].contains(where: lower.contains)
        if status == 404 && (lower.contains("model") || message.isEmpty) || (status == 400 && modelMissing) {
            return ProviderError(kind: .missingModel,
                                 message: String(localized: "\(provider.name) doesn't have the model “\(model)”. Pick another in Settings › Model."))
        }
        if (300..<400).contains(status) {
            return ProviderError(kind: .other, message: String(localized: "\(provider.name) tried to send Takes to another address, and Takes didn't follow."))
        }
        if status >= 500 {
            return ProviderError(kind: .other, message: String(localized: "\(provider.name) is having trouble (HTTP \(status)). Try again in a minute."))
        }
        let detail = message.isEmpty ? "HTTP \(status)" : message
        return ProviderError(kind: .other, message: String(localized: "\(provider.name) error: \(detail)"))
    }

    /// `error.code` when it's a string ("insufficient_quota"), from an object or Gemini's one-item array.
    static func errorCode(_ body: Data) -> String? {
        let json = try? JSONSerialization.jsonObject(with: body)
        let object = json as? [String: Any] ?? (json as? [[String: Any]])?.first
        return (object?["error"] as? [String: Any])?["code"] as? String
    }

    static func friendly(_ error: Error, provider: Provider) -> Error {
        guard let urlError = error as? URLError else { return error }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return EngineError.failed(String(localized: "Couldn't reach \(provider.name): this Mac seems to be offline. Check your connection and try again."))
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return EngineError.failed(provider.isCustom
                                      ? String(localized: "Couldn't reach \(provider.name). Check the address in Settings › Model.")
                                      : String(localized: "Couldn't reach \(provider.name). Check your internet connection and try again."))
        case .timedOut:
            return EngineError.failed(String(localized: "\(provider.name) took too long to answer. Try again, or pick a faster model."))
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot, .clientCertificateRejected:
            return EngineError.failed(String(localized: "The secure connection to \(provider.name) failed, so Takes didn't send anything."))
        case .cancelled:
            return CancellationError()
        default:
            return EngineError.failed(String(localized: "Couldn't reach \(provider.name): \(urlError.localizedDescription)"))
        }
    }

    /// The provider's chat models. Throws `ProviderError` (`.keyRefused` for a bad key) or a friendly network error.
    /// The answer is kept for a while per address and key (see `ProviderModelCache`), because setup and each panel open
    /// ask for it and every ask sends the key; `force` asks the provider again now (a "Check again" button).
    static func models(provider: Provider, key: String, force: Bool = false,
                       cache: ProviderModelCache = .shared) async throws -> [String] {
        try await cache.models(baseURL: provider.baseURL, key: key, force: force) {
            try await fetchModels(provider: provider, key: key)
        }
    }

    private static func fetchModels(provider: Provider, key: String) async throws -> [String] {
        guard let url = ProviderEndpoint.url(provider.baseURL, "models") else {
            throw EngineError.failed(String(localized: "Add an https address for your server in Settings › Model."))
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        for (name, value) in provider.extraHeaders { request.setValue(value, forHTTPHeaderField: name) }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await ProviderEndpoint.session.data(for: request)
        } catch {
            throw friendly(error, provider: provider)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw httpError(status: status, body: data, provider: provider, model: "") }
        guard let models = ProviderModelList.parse(data, provider: provider) else {
            throw EngineError.failed(String(localized: "\(provider.name) didn't send a model list."))
        }
        return models
    }

    /// A tiny request, to show that the key and model work and how fast.
    static func test(settings: AppSettings, key: String? = nil, provider: Provider? = nil) async -> Result<Int, Error> {
        let provider = provider ?? Provider.current(settings)
        let model = settings.providerModel
        guard let url = ProviderEndpoint.url(provider.baseURL, "chat/completions") else {
            return .failure(EngineError.failed(String(localized: "Add an https address for your server first.")))
        }
        guard let key = key ?? provider.key else { return .failure(EngineError.failed(String(localized: "Save your \(provider.name) API key first."))) }
        guard !model.isEmpty else { return .failure(EngineError.failed(String(localized: "Pick a model first."))) }
        var options = ProviderRequestOptions.initial(provider: provider, model: model)
        let started = Date()
        do {
            for attempt in 0..<3 {
                // Reasoning models spend tokens thinking before they answer; give them room.
                let budget = options.tokenField == "max_tokens" ? 16 : 1000
                let request = try chatRequest(url: url, key: key, provider: provider, model: model, system: "Reply with the single word OK.",
                                              user: "Ready?", stream: false, maxTokens: budget, options: options)
                let (data, response) = try await ProviderEndpoint.session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 400, attempt < 2, let next = options.adjusted(after: message(data)) {
                    options = next
                    continue
                }
                guard status == 200 else { return .failure(httpError(status: status, body: data, provider: provider, model: model)) }
                // A reasoning model can run out of room before it writes "OK"; the request still worked.
                guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], json["choices"] is [Any] else {
                    return .failure(EngineError.failed(String(localized: "\(provider.name) answered, but not with a chat reply. Check the model.")))
                }
                return .success(Int(Date().timeIntervalSince(started) * 1000))
            }
            return .failure(EngineError.failed(String(localized: "\(provider.name) refused the request.")))
        } catch {
            return .failure(friendly(error, provider: provider))
        }
    }
}

// MARK: - Model list cache

/// The last `GET /models` answer per base URL and key. A list is kept for `lifetime`; after a failure the provider
/// isn't asked again for `failurePause`, and the same error is given. Asks that arrive while one is on its way wait
/// for it instead of sending the key again. Keys are held only as a SHA-256 digest.
actor ProviderModelCache {
    static let shared = ProviderModelCache()

    static let lifetime: TimeInterval = 10 * 60
    static let failurePause: TimeInterval = 30

    private struct Entry {
        var at: Date
        var result: Result<[String], Error>
    }
    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<[String], Error>] = [:]
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { Date() }) { self.now = now }

    func models(baseURL: String, key: String, force: Bool = false,
                fetch: @escaping @Sendable () async throws -> [String]) async throws -> [String] {
        let id = Self.id(baseURL: baseURL, key: key)
        if !force, let entry = entries[id] {
            let age = now().timeIntervalSince(entry.at)
            switch entry.result {
            case .success(let models) where age < Self.lifetime: return models
            case .failure(let error) where age < Self.failurePause: throw error
            default: break
            }
        }
        if let running = inFlight[id] { return try await running.value }
        let task = Task { try await fetch() }
        inFlight[id] = task
        defer { inFlight[id] = nil }
        do {
            let models = try await task.value
            entries[id] = Entry(at: now(), result: .success(models))
            return models
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            entries[id] = Entry(at: now(), result: .failure(error))
            throw error
        }
    }

    /// Forgets every answer (tests).
    func removeAll() { entries = [:] }

    private static func id(baseURL: String, key: String) -> String {
        var base = baseURL.lowercased()
        while base.hasSuffix("/") { base.removeLast() }
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return base + " " + digest
    }
}

// MARK: - Models and key state, for Settings › Model, onboarding and the panel

/// The provider's models, for Settings › Model and the panel's Model menu.
@MainActor
final class ProviderModels: ObservableObject {
    static let shared = ProviderModels()

    enum State: Equatable {
        case idle, noAddress, noKey, checking, ready
        case refused(String)
        case failed(String)
    }
    enum TestState: Equatable { case idle, running, passed(Int), failed(String) }

    @Published var models: [String] = []
    @Published var state = State.idle
    @Published var checking = false
    @Published var checked = false
    /// Whether a key is saved for the current provider (read from the keychain on refresh, not on every redraw).
    @Published var hasKey = false
    @Published var test = TestState.idle
    /// Snapshots set the state by hand and keep it.
    var frozen = false

    /// Loads the models for the saved provider and key. `force` asks the provider again instead of using the list
    /// kept for a few minutes (a "Check again" button).
    func refresh(force: Bool = false) async {
        guard !frozen else { return }
        let settings = Store.shared.settings
        let provider = Provider.current(settings)
        test = .idle
        guard ProviderEndpoint.url(provider.baseURL, "models") != nil else {
            hasKey = false
            models = []
            state = .noAddress
            checked = true
            return
        }
        guard let key = provider.key else {
            hasKey = false
            models = []
            state = .noKey
            checked = true
            return
        }
        hasKey = true
        checking = true
        state = .checking
        let result: State, found: [String]
        do {
            found = try await ProviderEngine.models(provider: provider, key: key, force: force)
            result = .ready
        } catch let error as ProviderError where error.kind == .keyRefused {
            found = []
            result = .refused(error.message)
        } catch {
            found = []
            result = .failed(error.localizedDescription)
        }
        // The provider changed while this was loading: a newer refresh owns the state.
        guard !frozen, Provider.current(Store.shared.settings) == provider else { return }
        models = found
        state = result
        checking = false
        checked = true
        autoPick(provider)
    }

    /// With no model picked yet, pick the provider's preferred one.
    private func autoPick(_ provider: Provider) {
        guard Store.shared.settings.providerModel.isEmpty, let pick = ProviderModelList.autoPick(models, provider: provider) else { return }
        Store.shared.settings.providerModel = pick
    }

    /// Saves the key and checks it by loading the model list. False when the keychain refused it.
    @discardableResult
    func saveKey(_ key: String) -> Bool {
        let provider = Provider.current(Store.shared.settings)
        let saved = provider.setKey(key)
        hasKey = provider.key != nil
        Task {
            await refresh()
            await SetupMonitor.shared.refreshEngine()
        }
        return saved
    }

    func removeKey() {
        Provider.current(Store.shared.settings).setKey(nil)
        Task {
            await refresh()
            await SetupMonitor.shared.refreshEngine()
        }
    }

    /// Whether a key is saved for the current provider, read from the keychain without asking the provider anything
    /// (onboarding, before the user has agreed to send anything).
    func readKey() {
        guard !frozen else { return }
        let provider = Provider.current(Store.shared.settings)
        test = .idle
        models = []
        guard ProviderEndpoint.url(provider.baseURL, "models") != nil else {
            hasKey = false
            state = .noAddress
            return
        }
        hasKey = provider.key != nil
        state = hasKey ? .idle : .noKey
    }

    /// Switches provider. The model is per provider, so it's picked again from the new list (asked for only with
    /// `refresh`).
    func select(_ id: String, refresh shouldRefresh: Bool = true) {
        let settings = Store.shared.settings
        guard id != settings.providerID else { return }
        Store.shared.settings.providerID = id
        if let known = Provider.known.first(where: { $0.id == id }) {
            Store.shared.settings.providerBaseURL = known.baseURL
        } else if Provider.known.contains(where: { $0.baseURL == settings.providerBaseURL }) {
            Store.shared.settings.providerBaseURL = ""
        }
        Store.shared.settings.providerModel = ""
        guard shouldRefresh else { return }
        Task {
            await refresh()
            await SetupMonitor.shared.refreshEngine()
        }
    }

    func runTest() {
        test = .running
        let settings = Store.shared.settings
        Task {
            switch await ProviderEngine.test(settings: settings) {
            case .success(let ms): test = .passed(ms)
            case .failure(let error):
                test = .failed(error.localizedDescription)
                if let error = error as? ProviderError, error.kind == .keyRefused { state = .refused(error.message) }
            }
        }
    }

    /// The models to offer, always including the picked one.
    func modelOptions(picked: String) -> [String] {
        var options = models
        if !picked.isEmpty, !options.contains(picked) { options.insert(picked, at: 0) }
        return options
    }

    /// The card's badge: "OpenAI · gpt-5.4", "No key yet", "Key refused", "Pick a model".
    func badge(_ settings: AppSettings) -> (text: String, good: Bool)? {
        let provider = Provider.current(settings)
        switch state {
        case .noAddress: return (String(localized: "No address yet"), false)
        case .noKey: return (String(localized: "No key yet"), false)
        case .refused: return (String(localized: "Key refused"), false)
        case .idle, .checking: return nil
        case .ready, .failed:
            if settings.providerModel.isEmpty { return (String(localized: "Pick a model"), false) }
            return ("\(provider.name) · \(settings.providerModel)", true)
        }
    }
}

extension SetupMonitor {
    /// The last check, reused for a minute so the setup timer doesn't ask the provider every few seconds.
    private static var lastProviderCheck: (signature: Int, at: Date, status: EngineStatus)?

    /// Ready when a key is saved, the provider answers it, and a model is picked.
    static func providerEngineStatus() async -> EngineStatus {
        let settings = Store.shared.settings
        let provider = Provider.current(settings)
        guard ProviderEndpoint.url(provider.baseURL, "models") != nil else { return .problem(String(localized: "No server address yet")) }
        guard let key = provider.key else { return .problem(String(localized: "No API key saved yet")) }
        var hasher = Hasher()
        hasher.combine(provider.baseURL)
        hasher.combine(key)
        hasher.combine(settings.providerModel)
        let signature = hasher.finalize()
        if let last = lastProviderCheck, last.signature == signature, Date().timeIntervalSince(last.at) < 60 { return last.status }

        let status: EngineStatus
        do {
            let models = try await ProviderEngine.models(provider: provider, key: key)
            if settings.providerModel.isEmpty {
                status = .problem(String(localized: "Pick a model"))
            } else if !models.isEmpty, !models.contains(settings.providerModel) {
                status = .problem(String(localized: "\(provider.name) doesn't list \(settings.providerModel)"))
            } else {
                status = .ready("\(provider.name) · \(settings.providerModel)")
            }
        } catch let error as ProviderError where error.kind == .keyRefused {
            status = .problem(String(localized: "The key was refused"))
        } catch {
            // Some servers don't list models; a picked model is the best Takes can check.
            status = settings.providerModel.isEmpty ? .problem(String(localized: "Couldn't reach \(provider.name)")) : .ready("\(provider.name) · \(settings.providerModel)")
        }
        lastProviderCheck = (signature, Date(), status)
        return status
    }
}
