import Foundation
import Security

/// Calls the Claude Messages API directly with the user's own API key (billed per use by Anthropic).
struct APIEngine: TakesEngine {
    /// Tests pass a session with a stubbed `URLProtocol`.
    var session: URLSession = .shared
    /// The key, when it doesn't come from the keychain (tests).
    var keyOverride: String?

    /// The models' output limit: Opus 5.5, Sonnet 5.5 and Haiku 5.5 each write up to 128K tokens.
    static let outputCeiling = 128_000
    /// The cap for a short draft. Thinking is on for every model Takes offers and counts against `max_tokens`;
    /// a higher cap costs nothing (only written tokens are billed, and `max_tokens` doesn't count against the
    /// output rate limit), while one hit too early cuts the takes short.
    static let outputFloor = 16_000

    /// Thinking room by effort, on top of the takes themselves.
    static func thinkingReserve(_ effort: String) -> Int {
        switch effort {
        case "low": 8_000
        case "high": 32_000
        default: 16_000
        }
    }

    static func maxTokens(for request: EngineRequest) -> Int {
        OutputBudget.maxTokens(for: request, floor: outputFloor, ceiling: outputCeiling, reserve: thinkingReserve(request.effort))
    }

    func run(_ request: EngineRequest, onUpdate: @escaping @Sendable ([String]) -> Void) async throws -> EngineResult {
        guard let key = keyOverride ?? Keychain.apiKey, !key.isEmpty else {
            throw EngineError.failed(String(localized: "Add your Anthropic API key in Settings › Model."))
        }

        var urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(key, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")

        var body: [String: Any] = [
            "model": request.model,
            "max_tokens": Self.maxTokens(for: request),
            "stream": true,
            "system": request.system,
            "messages": [["role": "user", "content": request.user]],
            "output_config": ["effort": request.effort],
        ]
        // If a safety classifier declines, let the API retry on its recommended fallback model.
        // Haiku has no server-side fallback.
        if request.model != Models.haiku {
            body["fallbacks"] = "default"
            urlRequest.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let started = Date()
        let elapsedMs = { Int(Date().timeIntervalSince(started) * 1000) }
        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw EngineError.failed(String(localized: "No response from the API.")) }

        if http.statusCode != 200 {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = json?["error"] as? [String: Any]
            throw Self.apiError(status: http.statusCode, type: error?["type"] as? String,
                                message: error?["message"] as? String ?? "HTTP \(http.statusCode)",
                                retryAfter: http.value(forHTTPHeaderField: "retry-after"))
        }

        var text = ""
        var firstTextMs: Int?
        var stopReason: String?
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let json = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any] else { continue }
            switch json["type"] as? String {
            case "content_block_delta":
                guard let delta = json["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                      let chunk = delta["text"] as? String else { continue }
                if firstTextMs == nil { firstTextMs = elapsedMs() }
                text += chunk
                onUpdate(TakeSplitter.split(text, streaming: true))
            case "message_delta":
                stopReason = (json["delta"] as? [String: Any])?["stop_reason"] as? String ?? stopReason
            case "error":
                let error = json["error"] as? [String: Any]
                throw Self.apiError(status: nil, type: error?["type"] as? String,
                                    message: error?["message"] as? String ?? String(localized: "stream error"), retryAfter: nil)
            default:
                break
            }
        }

        // A refusal at the end means no fallback took over; text before it is a partial answer, not takes.
        if stopReason == "refusal" { throw EngineError.failed(Self.declinedMessage) }
        // No stop reason: the stream ended before the message did (a dropped connection), so it's unfinished too.
        let stoppedEarly = Self.ranOutOfRoom(stopReason) || stopReason == nil
        let takes = TakeSplitter.split(text, streaming: stoppedEarly)
        guard !takes.isEmpty else {
            if stopReason == nil {
                throw EngineError.failed(String(localized: "The connection to Claude dropped before the takes were done. Try again."))
            }
            if stoppedEarly {
                throw EngineError.failed(String(localized: "Claude ran out of room before writing a take. Try again, or pick a lower effort."))
            }
            throw EngineError.failed(String(localized: "Claude returned no takes."))
        }
        return EngineResult(takes: takes, wallMs: elapsedMs(), firstTextMs: firstTextMs,
                            cutShort: TakeSplitter.cutShort(text, stoppedEarly: stoppedEarly))
    }

    static let declinedMessage = String(localized: "Claude declined to rewrite this draft.")

    /// The model stopped because it reached `max_tokens` or the end of its context window, not because it was done.
    static func ranOutOfRoom(_ stopReason: String?) -> Bool {
        stopReason == "max_tokens" || stopReason == "model_context_window_exceeded"
    }
}

extension APIEngine {
    static let billingURL = URL(string: "https://console.anthropic.com/settings/billing")!
    static let limitsURL = URL(string: "https://console.anthropic.com/settings/limits")!

    /// Plain words for the Messages API's errors: https://docs.anthropic.com/en/api/errors
    static func apiError(status: Int?, type: String?, message: String, retryAfter: String?) -> Error {
        let lower = message.lowercased()
        if type == "billing_error" || status == 402 || lower.contains("credit balance") {
            return UsageLimitError(kind: .outOfCredit,
                                   message: String(localized: "Your Anthropic account is out of credit. Add credit in the Anthropic Console, or pick another engine."),
                                   manage: billingURL)
        }
        // "You have reached your specified API usage limits. You will regain access on …"
        if lower.contains("usage limit") || lower.contains("spend limit") {
            let message = String(localized: "Your Anthropic account reached the spend limit set for it. Raise the limit in the Anthropic Console, or pick another engine.")
            return UsageLimitError(kind: .planLimit, message: message, manage: limitsURL)
        }
        if type == "rate_limit_error" || status == 429 {
            return UsageLimitError(kind: .rateLimited,
                                   message: String(localized: "Your Anthropic key hit its rate limit. \(UsageLimitError.retryHint(retryAfter))"),
                                   manage: limitsURL)
        }
        return EngineError.failed(String(localized: "API error: \(message)"))
    }
}

// MARK: - Checking a key

/// What checking an Anthropic API key found.
enum APIKeyCheck: Equatable {
    /// Anthropic accepted the key.
    case valid
    /// Anthropic refused the key; `message` says so in plain words.
    case invalid(String)
    /// The check didn't get an answer about the key (offline, Anthropic busy); `message` says why.
    case couldNotCheck(String)
}

extension APIEngine {
    /// Checks a key without spending tokens: lists one model (`GET /v1/models?limit=1`), which needs a valid key and
    /// costs nothing. A key that's out of credit or rate limited is still a valid key.
    static func checkKey(_ key: String, session: URLSession = .shared) async -> APIKeyCheck {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .invalid(String(localized: "Paste your Anthropic API key first.")) }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1")!)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .couldNotCheck(String(localized: "Couldn't reach Anthropic to check the key. Check your internet connection and try again."))
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let type = (json?["error"] as? [String: Any])?["type"] as? String
        // Out of credit (402) or rate limited (429) means Anthropic knew the key.
        if status == 200 || status == 402 || status == 429 || type == "billing_error" || type == "rate_limit_error" {
            return .valid
        }
        if status == 401 || status == 403 || type == "authentication_error" || type == "permission_error" {
            return .invalid(String(localized: "Anthropic refused this key. Check it in the Anthropic Console and paste it again."))
        }
        return .couldNotCheck(String(localized: "Anthropic didn't answer the key check (HTTP \(status)). Try again in a moment."))
    }
}

// MARK: - Keychain

/// API keys live in the login keychain, never in the settings file. One item per account: the Anthropic key, and
/// one per other provider host ("provider-api.openai.com").
enum Keychain {
    static let service = "com.baramir.takes"
    private static let anthropicAccount = "anthropic-api-key"

    // No `kSecAttrAccessible`: the login keychain (file-based) accepts it but doesn't store it, and the data protection
    // keychain, which would honour it, needs an entitlement ad-hoc builds don't have (SecItemAdd returns -34018).
    // Checked on macOS 27 with a throwaway item.

    /// The keychain calls `set` makes; tests swap in fakes so they never touch the user's keychain.
    struct Items {
        var update: (_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus
        var add: (_ item: [String: Any]) -> OSStatus
        var delete: (_ query: [String: Any]) -> OSStatus

        static let system = Items(
            update: { SecItemUpdate($0 as CFDictionary, $1 as CFDictionary) },
            add: { SecItemAdd($0 as CFDictionary, nil) },
            delete: { SecItemDelete($0 as CFDictionary) }
        )
    }

    static var apiKey: String? { string(account: anthropicAccount) }

    /// Saves the Anthropic key; nil or empty removes it. False when the keychain refused.
    @discardableResult
    static func setAPIKey(_ key: String?) -> Bool { set(key, account: anthropicAccount) }

    static func string(account: String) -> String? {
        // Snapshots never read the keychain: a rebuilt app would stop at macOS's access prompt.
        guard !Store.readOnly else { return nil }
        var item: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Replaces the item; nil or empty removes it. True when the keychain did it (removing a missing item counts).
    @discardableResult
    static func set(_ value: String?, account: String, items: Items = .system) -> Bool {
        setData(value.flatMap { $0.isEmpty ? nil : Data($0.utf8) }, account: account, items: items)
    }

    /// Writes the item in place, or adds it when there's none; nil removes it. Never deletes to make room, so a write
    /// the keychain refuses (locked, or access denied) leaves the old value as it was. True when the keychain did it.
    @discardableResult
    static func setData(_ data: Data?, account: String, items: Items = .system) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
        ]
        guard let data, !data.isEmpty else {
            let status = items.delete(query)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let attributes: [String: Any] = [kSecValueData as String: data]
        var status = items.update(query, attributes)
        if status == errSecItemNotFound {
            status = items.add(query.merging(attributes) { $1 })
        }
        return status == errSecSuccess
    }
}
