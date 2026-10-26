import Foundation
import Security

/// Calls the Claude Messages API directly with the user's own API key (billed per use by Anthropic).
struct APIEngine: TakesEngine {
    func run(_ request: EngineRequest, onUpdate: @escaping @Sendable ([String]) -> Void) async throws -> EngineResult {
        guard let key = Keychain.apiKey, !key.isEmpty else {
            throw EngineError.failed("Add your Anthropic API key in Settings › Engine.")
        }

        var urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(key, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")

        var body: [String: Any] = [
            "model": request.model,
            "max_tokens": 8000,
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
        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw EngineError.failed("No response from the API.") }

        if http.statusCode != 200 {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (json?["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(http.statusCode)"
            throw EngineError.failed("API error: \(message)")
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
                let message = (json["error"] as? [String: Any])?["message"] as? String ?? "stream error"
                throw EngineError.failed("API error: \(message)")
            default:
                break
            }
        }

        if stopReason == "refusal" && text.isEmpty {
            throw EngineError.failed("Claude declined to rewrite this draft.")
        }
        let takes = TakeSplitter.split(text, streaming: false)
        guard !takes.isEmpty else { throw EngineError.failed("Claude returned no takes.") }
        return EngineResult(takes: takes, wallMs: elapsedMs(), firstTextMs: firstTextMs)
    }
}

/// The API key lives in the login keychain, never in the settings file.
enum Keychain {
    private static let service = "com.baramir.takes"
    private static let account = "anthropic-api-key"

    static var apiKey: String? {
        var item: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setAPIKey(_ key: String?) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard let key, !key.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(key.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
