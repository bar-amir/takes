import CryptoKit
import Foundation
import Network
import Security
import XCTest
@testable import Takes

// MARK: - OAuth pieces

final class ChatGPTPKCETests: XCTestCase {
    /// RFC 7636, appendix B.
    func testS256TestVector() {
        XCTAssertEqual(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testRandomVerifierIsLongEnoughAndURLSafe() {
        let pkce = PKCE.random()
        XCTAssertGreaterThanOrEqual(pkce.verifier.count, 43)
        XCTAssertTrue(pkce.verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        XCTAssertNotEqual(PKCE.random().verifier, pkce.verifier)
        XCTAssertFalse(pkce.challenge.contains("="))
    }
}

final class ChatGPTAuthorizationTests: XCTestCase {
    private func items(_ url: URL) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    func testFirstSignInRegistersTakes() {
        let attempt = ChatGPTAuthorization(hostID: "urn:uuid:1b4e28ba-2fa1-41d2-883f-0016d3cca427", clientID: nil, port: 1455)
        let url = attempt.url(idTokenHint: "ignored", loginHint: "ignored@example.com")
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "auth.openai.com")
        XCTAssertEqual(url.path, "/api/accounts/authorize")
        let query = items(url)
        XCTAssertEqual(query["client_id"], "dynamic_agent_client")
        XCTAssertEqual(query["agent_name_hint"], "Takes")
        XCTAssertEqual(query["ext_agent_host_id"], "urn:uuid:1b4e28ba-2fa1-41d2-883f-0016d3cca427")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["redirect_uri"], "http://127.0.0.1:1455/auth/callback")
        XCTAssertEqual(query["scope"], "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct")
        XCTAssertEqual(query["resource"], "https://api.openai.com/v1")
        XCTAssertEqual(query["state"], attempt.state)
        XCTAssertEqual(query["nonce"], attempt.nonce)
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["code_challenge"], attempt.pkce.challenge)
        XCTAssertNil(query["id_token_hint"])
        XCTAssertNil(query["login_hint"])
        // Every value fully encoded: no raw spaces, colons or slashes in the query.
        let raw = url.query ?? ""
        XCTAssertTrue(raw.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A1455%2Fauth%2Fcallback"), raw)
        XCTAssertTrue(raw.contains("scope=openid%20profile"), raw)
    }

    func testLaterSignInReusesTheIssuedClient() {
        let attempt = ChatGPTAuthorization(hostID: "urn:uuid:x", clientID: "oaiapp_123", port: 50123)
        let query = items(attempt.url(idTokenHint: "a.b.c", loginHint: "sam+work@example.com"))
        XCTAssertEqual(query["client_id"], "oaiapp_123")
        XCTAssertNil(query["agent_name_hint"])
        XCTAssertEqual(query["ext_agent_host_id"], "urn:uuid:x")
        XCTAssertEqual(query["id_token_hint"], "a.b.c")
        XCTAssertEqual(query["login_hint"], "sam+work@example.com")
        XCTAssertEqual(query["redirect_uri"], "http://127.0.0.1:50123/auth/callback")
        XCTAssertTrue(attempt.url(loginHint: "sam+work@example.com").query!.contains("sam%2Bwork%40example.com"))
    }

    func testFreshValuesPerAttempt() {
        let a = ChatGPTAuthorization(hostID: "h", clientID: nil, port: 1), b = ChatGPTAuthorization(hostID: "h", clientID: nil, port: 1)
        XCTAssertNotEqual(a.state, b.state)
        XCTAssertNotEqual(a.nonce, b.nonce)
        XCTAssertNotEqual(a.pkce, b.pkce)
    }

    func testCallbackParsing() {
        let first = ChatGPTAuthorization(hostID: "h", clientID: nil, port: 1455)
        func q(_ pairs: [String: String]) -> [URLQueryItem] { pairs.map { URLQueryItem(name: $0.key, value: $0.value) } }

        XCTAssertEqual(first.parseCallback(q(["code": "c1", "state": first.state, "scope": "openid", "client_id": "oaiapp_9"])),
                       .success(.init(code: "c1", clientID: "oaiapp_9", scope: "openid")))
        XCTAssertEqual(first.parseCallback(q(["code": "c1", "state": "nope", "client_id": "oaiapp_9"])), .failure(.stateMismatch))
        XCTAssertEqual(first.parseCallback(q(["code": "c1"])), .failure(.stateMismatch))
        XCTAssertEqual(first.parseCallback(q(["error": "access_denied", "state": first.state])), .failure(.denied))
        // A forged denial with the wrong state is still a state mismatch.
        XCTAssertEqual(first.parseCallback(q(["error": "access_denied", "state": "x"])), .failure(.stateMismatch))
        XCTAssertEqual(first.parseCallback(q(["state": first.state, "client_id": "oaiapp_9"])), .failure(.missingCode))
        XCTAssertEqual(first.parseCallback(q(["code": "c1", "state": first.state])), .failure(.missingClientID))
        // "dynamic_agent_client" is never taken as the issued ID.
        XCTAssertEqual(first.parseCallback(q(["code": "c1", "state": first.state, "client_id": "dynamic_agent_client"])), .failure(.missingClientID))

        let later = ChatGPTAuthorization(hostID: "h", clientID: "oaiapp_9", port: 1455)
        XCTAssertEqual(later.parseCallback(q(["code": "c2", "state": later.state])), .success(.init(code: "c2", clientID: "oaiapp_9", scope: nil)))
        XCTAssertEqual(later.parseCallback(q(["code": "c2", "state": later.state, "client_id": "oaiapp_other"])), .failure(.clientMismatch))
    }

    func testHostIDIsMadeOnceAndKept() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let id = ChatGPTHost.id(in: folder)
        XCTAssertTrue(id.hasPrefix("urn:uuid:"))
        XCTAssertNotNil(UUID(uuidString: String(id.dropFirst("urn:uuid:".count))))
        XCTAssertEqual(ChatGPTHost.id(in: folder), id)
    }
}

final class ChatGPTTokenTests: XCTestCase {
    let response = #"{"access_token":"at1","refresh_token":"rt1","id_token":"x.y.z","token_type":"Bearer","expires_in":3600,"scope":"openid profile email offline_access resource.invoke chatgpt.tokens.use.direct","earliest_refresh_at":123}"#

    func testDecodesTheTokenResponse() throws {
        let tokens = try JSONDecoder().decode(ChatGPTTokenResponse.self, from: Data(response.utf8))
        XCTAssertEqual(tokens.access_token, "at1")
        XCTAssertEqual(tokens.refresh_token, "rt1")
        XCTAssertEqual(tokens.expires_in, 3600)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let claims = ChatGPTIDToken.Claims(iss: nil, aud: [], exp: nil, nonce: nil, sub: "user-1", email: "sam@example.com", name: "Sam")
        let credentials = ChatGPTCredentials(clientID: "oaiapp_1", response: tokens, claims: claims, now: now)
        XCTAssertEqual(credentials.expiresAt, now.addingTimeInterval(3600))
        XCTAssertTrue(credentials.sharing)
        XCTAssertEqual(credentials.email, "sam@example.com")
        XCTAssertEqual(credentials.subject, "user-1")
        XCTAssertFalse(credentials.needsRefresh(now: now))
        XCTAssertTrue(credentials.needsRefresh(now: now.addingTimeInterval(3541)))
    }

    func testRefreshReplacesEverythingTogether() throws {
        let tokens = try JSONDecoder().decode(ChatGPTTokenResponse.self, from: Data(response.utf8))
        let old = ChatGPTCredentials(clientID: "oaiapp_1", response: tokens, claims: nil, now: Date(timeIntervalSince1970: 0))
        let now = Date(timeIntervalSince1970: 5000)
        let next = old.refreshed(with: ChatGPTTokenResponse(access_token: "at2", refresh_token: "rt2", expires_in: 1800,
                                                            scope: "openid offline_access"), now: now)
        XCTAssertEqual(next.accessToken, "at2")
        XCTAssertEqual(next.refreshToken, "rt2")
        XCTAssertEqual(next.expiresAt, now.addingTimeInterval(1800))
        XCTAssertEqual(next.scopes, ["offline_access", "openid"])
        XCTAssertFalse(next.sharing)
        XCTAssertEqual(next.clientID, "oaiapp_1")

        // Fields the server leaves out keep their values.
        let kept = old.refreshed(with: ChatGPTTokenResponse(access_token: "at3"), now: now)
        XCTAssertEqual(kept.refreshToken, "rt1")
        XCTAssertTrue(kept.sharing)
        XCTAssertEqual(kept.idToken, "x.y.z")
    }

    func testCredentialsRoundTrip() throws {
        let tokens = try JSONDecoder().decode(ChatGPTTokenResponse.self, from: Data(response.utf8))
        let credentials = ChatGPTCredentials(clientID: "c", response: tokens, claims: nil)
        XCTAssertEqual(try JSONDecoder().decode(ChatGPTCredentials.self, from: JSONEncoder().encode(credentials)), credentials)
    }

    func testFormBodyEncodesEverything() {
        let body = String(decoding: ChatGPTAuthClient.formBody([("redirect_uri", "http://127.0.0.1:1455/auth/callback"), ("code", "a+b/c=")]), as: UTF8.self)
        XCTAssertEqual(body, "redirect_uri=http%3A%2F%2F127.0.0.1%3A1455%2Fauth%2Fcallback&code=a%2Bb%2Fc%3D")
    }
}

final class ChatGPTIDTokenTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func token(_ claims: [String: Any], key: SecKey? = nil, kid: String = "k1") -> String {
        func part(_ json: [String: Any]) -> String { ChatGPTOAuth.base64url(try! JSONSerialization.data(withJSONObject: json)) }
        let input = part(["alg": "RS256", "typ": "JWT", "kid": kid]) + "." + part(claims)
        guard let key else { return input + ".c2ln" }
        let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data(input.utf8) as CFData, nil)! as Data
        return input + "." + ChatGPTOAuth.base64url(signature)
    }

    private var good: [String: Any] {
        ["iss": "https://auth.openai.com", "aud": "oaiapp_1", "exp": now.timeIntervalSince1970 + 600, "nonce": "n1",
         "sub": "user-1", "email": "sam@example.com", "name": "Sam"]
    }

    func testClaimChecks() {
        func check(_ change: (inout [String: Any]) -> Void) -> Result<ChatGPTIDToken.Claims, ChatGPTIDToken.Problem> {
            var claims = good
            change(&claims)
            return ChatGPTIDToken.validate(token(claims), nonce: "n1", clientID: "oaiapp_1", now: now)
        }
        guard case .success(let claims) = check({ _ in }) else { return XCTFail("valid token refused") }
        XCTAssertEqual(claims.email, "sam@example.com")
        XCTAssertEqual(claims.sub, "user-1")
        XCTAssertEqual(check { $0["aud"] = ["other", "oaiapp_1"] }.map(\.sub), .success("user-1"))
        XCTAssertEqual(check { $0["nonce"] = "n2" }.map(\.sub), .failure(.nonce))
        XCTAssertEqual(check { $0["nonce"] = nil }.map(\.sub), .failure(.nonce))
        XCTAssertEqual(check { $0["aud"] = "dynamic_agent_client" }.map(\.sub), .failure(.audience))
        XCTAssertEqual(check { $0["iss"] = "https://evil.example" }.map(\.sub), .failure(.issuer))
        XCTAssertEqual(check { $0["exp"] = self.now.timeIntervalSince1970 - 600 }.map(\.sub), .failure(.expired))
        XCTAssertEqual(ChatGPTIDToken.validate("not-a-jwt", nonce: "n1", clientID: "oaiapp_1", now: now).map(\.sub), .failure(.malformed))
    }

    func testSignatureAgainstJWKS() throws {
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048]
        let privateKey = try XCTUnwrap(SecKeyCreateRandomKey(attributes as CFDictionary, nil))
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(privateKey))
        let der = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, nil) as Data?)
        let (n, e) = try XCTUnwrap(Self.rsaComponents(der))
        let jwks = try JSONSerialization.data(withJSONObject: ["keys": [
            ["kty": "RSA", "kid": "other", "n": ChatGPTOAuth.base64url(Data([1, 2, 3])), "e": "AQAB"],
            ["kty": "RSA", "kid": "k1", "use": "sig", "alg": "RS256", "n": ChatGPTOAuth.base64url(n), "e": ChatGPTOAuth.base64url(e)],
        ]])

        let signed = token(good, key: privateKey)
        let key = try XCTUnwrap(ChatGPTIDToken.key(for: signed, jwks: jwks))
        XCTAssertEqual(SecKeyCopyExternalRepresentation(key, nil) as Data?, der)
        XCTAssertTrue(ChatGPTIDToken.verify(signed, key: key))
        // A changed payload, an unsigned token and an unknown key all fail.
        var parts = signed.split(separator: ".").map(String.init)
        var claims = good
        claims["email"] = "eve@example.com"
        parts[1] = ChatGPTOAuth.base64url(try JSONSerialization.data(withJSONObject: claims))
        XCTAssertFalse(ChatGPTIDToken.verify(parts.joined(separator: "."), key: key))
        XCTAssertFalse(ChatGPTIDToken.verify(token(good), key: key))
        XCTAssertNil(ChatGPTIDToken.key(for: token(good, key: privateKey, kid: "missing"), jwks: jwks))
    }

    /// OpenAI's published key (from https://auth.openai.com/.well-known/jwks.json, 2 November 2026) loads.
    func testRealJWKLoads() {
        let n = "xYNYiGEZikcuWUbwx0gQbjhupTZtvy_EntH-EEGio3sMZMJmSHo92j1XKTSVdHCAOj7A1tLaEG3AFQ_34Bdrlq4kgAJBXggEesNCFq4KmgTiQNtsusIyG3oo8B7Z3-inPuaR-kJwTmfrKob9euhXzj6Qf5mEzL5hkbqrDyQPdIg8jZSajeKdsPHt2YOjy6eGd4kI1sgZplpxU2wyTRmayfXkMjPLDvFX7_8yu0G7axTTjeGzyyS-8uCOWw5E2Q_Jzxp8G3Nsuug73eazaYr1zhU7FENYgMm29VrDx1PCfKRsPrbBfkfMbnzKqmzfFBSJSfDJgnDFeymZFg03WEY8uQ"
        XCTAssertNotNil(ChatGPTIDToken.rsaKey(modulus: ChatGPTOAuth.base64urlDecode(Substring(n))!, exponent: ChatGPTOAuth.base64urlDecode("AQAB")!))
    }

    /// Reads SEQUENCE { INTEGER n, INTEGER e } back out of a PKCS#1 key.
    static func rsaComponents(_ der: Data) -> (Data, Data)? {
        let bytes = [UInt8](der)
        var i = 0
        func length() -> Int {
            let first = Int(bytes[i]); i += 1
            guard first & 0x80 != 0 else { return first }
            var value = 0
            for _ in 0..<(first & 0x7F) { value = value << 8 | Int(bytes[i]); i += 1 }
            return value
        }
        guard bytes.first == 0x30 else { return nil }
        i = 1; _ = length()
        func integer() -> Data? {
            guard bytes[i] == 0x02 else { return nil }
            i += 1
            let count = length()
            defer { i += count }
            return Data(bytes[i..<i + count])
        }
        guard let n = integer(), let e = integer() else { return nil }
        return (n, e)
    }
}

final class ChatGPTScopeTests: XCTestCase {
    private func credentials(scopes: String, expiresIn: Double = 3600) -> ChatGPTCredentials {
        ChatGPTCredentials(clientID: "oaiapp_1", response: ChatGPTTokenResponse(access_token: "at", refresh_token: "rt", expires_in: expiresIn, scope: scopes), claims: nil)
    }

    func testNoInferenceWithoutPlanUsage() async {
        let tokens = ChatGPTTokens(store: ChatGPTMemoryStore(credentials(scopes: "openid profile email offline_access")))
        do {
            _ = try await tokens.accessToken()
            XCTFail("should refuse")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("plan usage wasn't allowed"), error.localizedDescription)
        }
    }

    func testNoTokensMeansSignIn() async {
        do {
            _ = try await ChatGPTTokens(store: ChatGPTMemoryStore()).accessToken()
            XCTFail("should refuse")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Sign in to ChatGPT in Settings › Engine.")
        }
    }

    func testFreshTokenIsUsedAsIs() async throws {
        let tokens = ChatGPTTokens(store: ChatGPTMemoryStore(credentials(scopes: "openid chatgpt.tokens.use.direct")),
                                   client: ChatGPTAuthClient(tokenURL: URL(string: "http://127.0.0.1:9/never")!, discoveryURL: nil))
        let token = try await tokens.accessToken()
        XCTAssertEqual(token, "at")
    }
}

// MARK: - Responses API

final class ChatGPTRequestTests: XCTestCase {
    func testBodyIsExactlyTheAllowedFields() throws {
        let request = try ChatGPTEngine.responsesRequest(baseURL: "https://api.openai.com/v1", token: "tok", model: "gpt-5.4",
                                                         instructions: "Rewrite.", user: "<draft>hi</draft>")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["model", "instructions", "input", "store", "stream"])
        XCTAssertEqual(json["model"] as? String, "gpt-5.4")
        XCTAssertEqual(json["instructions"] as? String, "Rewrite.")
        XCTAssertEqual(json["store"] as? Bool, false)
        XCTAssertEqual(json["stream"] as? Bool, true)
        let input = try XCTUnwrap(json["input"] as? [[String: String]])
        XCTAssertEqual(input, [["role": "user", "content": "<draft>hi</draft>"]])
        XCTAssertFalse(input.contains { $0["role"] == "system" })
    }

    func testStreamEvents() {
        XCTAssertEqual(ResponsesEvent.parse(#"{"type":"response.output_text.delta","item_id":"m","output_index":0,"content_index":0,"delta":"Hi"}"#), .delta("Hi"))
        XCTAssertEqual(ResponsesEvent.parse(#"{"type":"response.completed","response":{"id":"r","status":"completed"}}"#), .completed)
        XCTAssertEqual(ResponsesEvent.parse(#"{"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"}}}"#),
                       .incomplete(reason: "max_output_tokens"))
        XCTAssertEqual(ResponsesEvent.parse(#"{"type":"response.failed","response":{"error":{"code":"subscription_sharing_usage_limit_exceeded","message":"limit"}}}"#),
                       .failed(code: "subscription_sharing_usage_limit_exceeded", message: "limit", param: nil))
        XCTAssertEqual(ResponsesEvent.parse(#"{"type":"error","code":"subscription_sharing_usage_unavailable","message":"later","param":null}"#),
                       .failed(code: "subscription_sharing_usage_unavailable", message: "later", param: nil))
        XCTAssertEqual(ResponsesEvent.parse(#"{"error":{"code":"model_not_found","message":"no","param":"model"}}"#),
                       .failed(code: "model_not_found", message: "no", param: "model"))
        XCTAssertNil(ResponsesEvent.parse(#"{"type":"response.created","response":{}}"#))
        XCTAssertNil(ResponsesEvent.parse(#"{"type":"response.output_text.done","text":"Hi"}"#))
        XCTAssertNil(ResponsesEvent.parse("not json"))
    }

    func testErrorWording() {
        XCTAssertEqual(ChatGPTEngine.message(code: "subscription_sharing_usage_limit_exceeded", message: nil, param: nil, status: 429),
                       "You've used this week's ChatGPT allowance for Takes. Manage it in ChatGPT › Settings › Usage, or pick another engine.")
        XCTAssertEqual(ChatGPTEngine.message(code: "subscription_sharing_usage_unavailable", message: nil, param: nil, status: 503),
                       "Your ChatGPT plan can't be used in Takes right now. Check ChatGPT › Settings › Usage.")
        XCTAssertEqual(ChatGPTEngine.message(code: nil, message: nil, param: nil, status: 401), "Sign in to ChatGPT again in Settings › Engine.")
        XCTAssertTrue(ChatGPTEngine.message(code: "subscription_sharing_unsupported_capability", message: "x", param: "model", status: 400)
            .contains("Pick another"))
        XCTAssertEqual(ChatGPTEngine.httpError(status: 403, body: Data(#"{"detail":"Unsupported region"}"#.utf8), requestID: "req_1")
            .localizedDescription, "ChatGPT refused the request: Unsupported region (request req_1)")
    }

    func testModelListKeepsListedModelsInOrder() {
        let data = Data(#"""
        {"models":[
          {"slug":"gpt-5.4","display_name":"GPT-5.4","visibility":"list"},
          {"slug":"gpt-5.4-internal","display_name":"Hidden","visibility":"hide"},
          {"slug":"gpt-5.4-mini","display_name":"GPT-5.4 mini","visibility":"list"},
          {"slug":"codex-auto","display_name":"Auto"},
          {"slug":"o9","visibility":"list"}
        ]}
        """#.utf8)
        XCTAssertEqual(ChatGPTModelList.parse(data), [.init(slug: "gpt-5.4", displayName: "GPT-5.4"),
                                                      .init(slug: "gpt-5.4-mini", displayName: "GPT-5.4 mini"),
                                                      .init(slug: "o9", displayName: "o9")])
        XCTAssertNil(ChatGPTModelList.parse(Data("nope".utf8)))
    }

    func testDisplayNamesReachThePanelLabels() {
        ChatGPTModelNames.set([.init(slug: "gpt-test-label", displayName: "GPT Test Label")])
        XCTAssertEqual(LocalModelList.label("gpt-test-label"), "GPT Test Label")
        XCTAssertEqual(Models.displayLabel("gpt-test-label"), "GPT Test Label")
        XCTAssertEqual(LocalModelList.label("llama3.2:latest"), "llama3.2")
    }
}

final class ChatGPTSettingsTests: XCTestCase {
    func testOldSettingsGetChatGPTDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"engine":"local","localModel":"llama3.2"}"#.utf8))
        XCTAssertEqual(settings.chatGPTModel, "")
        XCTAssertEqual(settings.localModel, "llama3.2")
    }

    func testChatGPTSettingsRoundTrip() throws {
        var settings = AppSettings()
        settings.engine = .chatGPT
        settings.chatGPTModel = "gpt-5.4"
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.engine, .chatGPT)
        XCTAssertEqual(decoded.chatGPTModel, "gpt-5.4")
        XCTAssertTrue(decoded.engine.usesOneModel)
        XCTAssertEqual(decoded.quickModel, "gpt-5.4")
        XCTAssertEqual(decoded.oneModelPlace, "with your ChatGPT plan")
        XCTAssertTrue(Engines.current(decoded) is ChatGPTEngine)
    }
}

// MARK: - Against a mock server on 127.0.0.1

final class ChatGPTServerTests: XCTestCase {
    private func signedIn(_ store: ChatGPTMemoryStore = ChatGPTMemoryStore(), access: String = "at1", expiresIn: Double = 3600) -> ChatGPTMemoryStore {
        store.save(ChatGPTCredentials(clientID: "oaiapp_1", response: ChatGPTTokenResponse(
            access_token: access, refresh_token: "rt1", expires_in: expiresIn,
            scope: "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"), claims: nil))
        return store
    }

    private func engine(_ server: ChatGPTMockServer, _ store: ChatGPTCredentialStore) -> ChatGPTEngine {
        ChatGPTEngine(baseURL: server.baseURL,
                      tokens: ChatGPTTokens(store: store, client: ChatGPTAuthClient(tokenURL: server.url("/oauth/token"), discoveryURL: nil)))
    }

    private static func sse(_ events: [String]) -> String {
        events.map { "event: x\ndata: \($0)\n\n" }.joined()
    }

    private static let request = EngineRequest(system: "Rewrite.", user: "<draft>\nhi\n</draft>", takes: 2, model: "gpt-5.4", effort: "low")

    func testStreamsTakesUntilCompleted() async throws {
        let stream = Self.sse([
            #"{"type":"response.created","response":{"id":"r1"}}"#,
            #"{"type":"response.output_text.delta","delta":"Thursday "}"#,
            #"{"type":"response.output_text.delta","delta":"works.\n=="}"#,
            #"{"type":"response.output_text.delta","delta":"=\nSure, Thursday."}"#,
            #"{"type":"response.output_text.done","text":"…"}"#,
            #"{"type":"response.completed","response":{"id":"r1","status":"completed"}}"#,
        ])
        let server = try ChatGPTMockServer { request in
            XCTAssertEqual(request.path, "/v1/responses")
            XCTAssertEqual(request.headers["authorization"], "Bearer at1")
            let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any]
            XCTAssertEqual(json?["instructions"] as? String, "Rewrite.")
            XCTAssertEqual(json?["store"] as? Bool, false)
            return .init(status: 200, contentType: "text/event-stream", chunks: ChatGPTMockServer.chunked(stream, size: 23))
        }
        defer { server.stop() }

        let updates = ChatGPTUpdateLog()
        let result = try await engine(server, signedIn()).run(Self.request) { updates.add($0) }
        XCTAssertEqual(result.takes, ["Thursday works.", "Sure, Thursday."])
        XCTAssertNotNil(result.firstTextMs)
        XCTAssertFalse(updates.all.isEmpty)
        XCTAssertFalse(updates.all.flatMap { $0 }.contains { $0.contains("=") })
    }

    func testUsageLimitMidStream() async throws {
        let stream = Self.sse([
            #"{"type":"response.output_text.delta","delta":"Thurs"}"#,
            #"{"type":"response.failed","response":{"status":"failed","error":{"code":"subscription_sharing_usage_limit_exceeded","message":"Usage limit"}}}"#,
        ])
        let server = try ChatGPTMockServer { _ in .init(status: 200, contentType: "text/event-stream", chunks: [Data(stream.utf8)]) }
        defer { server.stop() }
        await assertFails(engine(server, signedIn()), contains: "this week's ChatGPT allowance")
    }

    func testUsageUnavailableAsHTTPError() async throws {
        let server = try ChatGPTMockServer { _ in
            .init(status: 503, contentType: "application/json",
                  chunks: [Data(#"{"error":{"code":"subscription_sharing_usage_unavailable","message":"x"}}"#.utf8)])
        }
        defer { server.stop() }
        await assertFails(engine(server, signedIn()), contains: "can't be used in Takes right now")
    }

    func testIncompleteKeepsWhatStreamed() async throws {
        let partial = Self.sse([
            #"{"type":"response.output_text.delta","delta":"Thursday works.\n===\nSure"}"#,
            #"{"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"}}}"#,
        ])
        let empty = Self.sse([#"{"type":"response.incomplete","response":{}}"#])
        var body = partial
        let server = try ChatGPTMockServer { _ in .init(status: 200, contentType: "text/event-stream", chunks: [Data(body.utf8)]) }
        defer { server.stop() }
        let result = try await engine(server, signedIn()).run(Self.request) { _ in }
        XCTAssertEqual(result.takes, ["Thursday works.", "Sure"])
        body = empty
        await assertFails(engine(server, signedIn()), contains: "ChatGPT stopped early. Try again.")
    }

    func testStreamThatEndsWithoutCompletedFails() async throws {
        let stream = Self.sse([#"{"type":"response.output_text.delta","delta":"Thursday works."}"#])
        let server = try ChatGPTMockServer { _ in .init(status: 200, contentType: "text/event-stream", chunks: [Data(stream.utf8)]) }
        defer { server.stop() }
        await assertFails(engine(server, signedIn()), contains: "dropped")
    }

    func testRefreshesOn401ThenRetries() async throws {
        let done = Self.sse([#"{"type":"response.output_text.delta","delta":"OK"}"#, #"{"type":"response.completed","response":{}}"#])
        let log = ChatGPTUpdateLog()
        let server = try ChatGPTMockServer { request in
            log.add([request.path, request.headers["authorization"] ?? String(decoding: request.body, as: UTF8.self)])
            if request.path == "/oauth/token" {
                return .init(status: 200, contentType: "application/json",
                             chunks: [Data(#"{"access_token":"at2","refresh_token":"rt2","expires_in":3600,"token_type":"Bearer"}"#.utf8)])
            }
            if request.headers["authorization"] == "Bearer at1" {
                return .init(status: 401, contentType: "application/json", chunks: [Data(#"{"detail":"Unauthorized"}"#.utf8)])
            }
            return .init(status: 200, contentType: "text/event-stream", chunks: [Data(done.utf8)])
        }
        defer { server.stop() }
        let store = signedIn()
        let result = try await engine(server, store).run(Self.request) { _ in }
        XCTAssertEqual(result.takes, ["OK"])
        XCTAssertEqual(log.all.map { $0[0] }, ["/v1/responses", "/oauth/token", "/v1/responses"])
        let refresh = log.all[1][1]
        XCTAssertTrue(refresh.contains("grant_type=refresh_token"), refresh)
        XCTAssertTrue(refresh.contains("client_id=oaiapp_1"), refresh)
        XCTAssertTrue(refresh.contains("refresh_token=rt1"), refresh)
        XCTAssertTrue(refresh.contains("resource=https%3A%2F%2Fapi.openai.com%2Fv1"), refresh)
        XCTAssertFalse(refresh.contains("scope="), refresh)
        // Replaced together; the plan permission is kept since the refresh didn't send scopes.
        XCTAssertEqual(store.load()?.accessToken, "at2")
        XCTAssertEqual(store.load()?.refreshToken, "rt2")
        XCTAssertEqual(store.load()?.sharing, true)
    }

    func testRefreshesBeforeExpiry() async throws {
        let log = ChatGPTUpdateLog()
        let server = try ChatGPTMockServer { request in
            log.add([request.path])
            return .init(status: 200, contentType: "application/json",
                         chunks: [Data(#"{"access_token":"at2","refresh_token":"rt2","expires_in":3600}"#.utf8)])
        }
        defer { server.stop() }
        let tokens = ChatGPTTokens(store: signedIn(expiresIn: 30), client: ChatGPTAuthClient(tokenURL: server.url("/oauth/token"), discoveryURL: nil))
        async let a = tokens.accessToken()
        async let b = tokens.accessToken()
        let both = try await [a, b]
        XCTAssertEqual(both, ["at2", "at2"])
        // Two callers, one refresh: the rotating refresh token is used once.
        XCTAssertEqual(log.all.count, 1)
    }

    func testDeadRefreshTokenSignsOut() async throws {
        let server = try ChatGPTMockServer { request in
            if request.path == "/oauth/token" {
                return .init(status: 400, contentType: "application/json", chunks: [Data(#"{"error":"invalid_grant"}"#.utf8)])
            }
            return .init(status: 401, contentType: "application/json", chunks: [Data("{}".utf8)])
        }
        defer { server.stop() }
        let store = signedIn()
        store.saveRegistration(ChatGPTRegistration(clientID: "oaiapp_1", subject: "user-1"))
        await assertFails(engine(server, store), contains: "Sign in to ChatGPT again in Settings › Engine.")
        XCTAssertNil(store.load())
        XCTAssertEqual(store.loadRegistration()?.clientID, "oaiapp_1")
    }

    func testModelsAndTest() async throws {
        let server = try ChatGPTMockServer { request in
            if request.path == "/v1/models" {
                XCTAssertEqual(request.headers["authorization"], "Bearer at1")
                return .init(status: 200, contentType: "application/json", chunks: [Data(
                    #"{"models":[{"slug":"b","display_name":"B","visibility":"list"},{"slug":"a","display_name":"A","visibility":"hide"}]}"#.utf8)])
            }
            return .init(status: 200, contentType: "text/event-stream", chunks: [Data(Self.sse([
                #"{"type":"response.output_text.delta","delta":"OK"}"#, #"{"type":"response.completed","response":{}}"#]).utf8)])
        }
        defer { server.stop() }
        let engine = engine(server, signedIn())
        guard case .success(let models) = await engine.models() else { return XCTFail("no models") }
        XCTAssertEqual(models, [.init(slug: "b", displayName: "B")])
        if case .failure(let error) = await engine.test(model: "b") { XCTFail(error.localizedDescription) }
    }

    /// The whole browser flow with a fake browser: register, callback, exchange, ID token, scopes, saved together.
    func testSignInEndToEnd() async throws {
        let attemptBox = ChatGPTUpdateLog()
        let server = try ChatGPTMockServer { request in
            XCTAssertEqual(request.path, "/oauth/token")
            let form = String(decoding: request.body, as: UTF8.self)
            attemptBox.add([form])
            let nonce = attemptBox.nonce
            let idToken = Self.unsignedIDToken(["iss": "https://auth.openai.com", "aud": "oaiapp_new", "nonce": nonce,
                                                "exp": Date().timeIntervalSince1970 + 600, "sub": "user-1", "email": "sam@example.com"])
            return .init(status: 200, contentType: "application/json", chunks: [Data(
                #"{"access_token":"at","refresh_token":"rt","id_token":"\#(idToken)","token_type":"Bearer","expires_in":3600,"scope":"openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"}"#.utf8)])
        }
        defer { server.stop() }

        let store = ChatGPTMemoryStore()
        let client = ChatGPTAuthClient(tokenURL: server.url("/oauth/token"), discoveryURL: nil)
        let credentials = try await ChatGPTSignIn.signIn(store: store, client: client, hostID: "urn:uuid:test", timeout: 10) { url in
            let query = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
            XCTAssertEqual(query["client_id"], "dynamic_agent_client")
            attemptBox.nonce = query["nonce"]!
            var callback = URLComponents(string: query["redirect_uri"]!)!
            callback.queryItems = [.init(name: "code", value: "code-1"), .init(name: "state", value: query["state"]),
                                   .init(name: "scope", value: query["scope"]), .init(name: "client_id", value: "oaiapp_new")]
            _ = Task {
                let (data, response) = try await URLSession.shared.data(from: callback.url!)
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
                XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("You can close this tab and go back to Takes."))
            }
        }
        XCTAssertEqual(credentials.email, "sam@example.com")
        XCTAssertTrue(credentials.sharing)
        XCTAssertEqual(store.load(), credentials)
        XCTAssertEqual(store.loadRegistration(), ChatGPTRegistration(clientID: "oaiapp_new", subject: "user-1"))
        let form = attemptBox.all.first?.first ?? ""
        for field in ["grant_type=authorization_code", "client_id=oaiapp_new", "code=code-1", "code_verifier=",
                      "redirect_uri=http%3A%2F%2F127.0.0.1%3A", "resource=https%3A%2F%2Fapi.openai.com%2Fv1"] {
            XCTAssertTrue(form.contains(field), "\(field) missing from \(form)")
        }
        XCTAssertFalse(form.contains("client_secret"))
    }

    /// A callback with the wrong state (from any web page or local program) is refused and doesn't end the sign-in:
    /// it keeps waiting for the real one, here until it times out.
    func testSignInIgnoresAForgedCallback() async throws {
        let store = ChatGPTMemoryStore()
        let client = ChatGPTAuthClient(tokenURL: URL(string: "http://127.0.0.1:9/never")!, discoveryURL: nil)
        let forged = ChatGPTUpdateLog()
        do {
            _ = try await ChatGPTSignIn.signIn(store: store, client: client, hostID: "urn:uuid:test", timeout: 2) { url in
                let redirect = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "redirect_uri" }!.value!
                Task {
                    let response = try? await URLSession.shared.data(from: URL(string: redirect + "?code=evil&state=wrong&client_id=oaiapp_evil")!).1
                    forged.add(["\((response as? HTTPURLResponse)?.statusCode ?? 0)"])
                }
            }
            XCTFail("should refuse")
        } catch {
            XCTAssertEqual(error as? ChatGPTAuthError, .timedOut)
        }
        XCTAssertEqual(forged.all, [["400"]])
        XCTAssertNil(store.load())
        XCTAssertNil(store.loadRegistration())
    }

    func testCallbackTimesOut() async throws {
        let server = try await ChatGPTCallbackServer.start(preferredPort: 0)
        defer { server.stop() }
        do {
            _ = try await server.waitForCallback(timeout: 0.2)
            XCTFail("should time out")
        } catch {
            XCTAssertEqual(error as? ChatGPTAuthError, .timedOut)
        }
    }

    func testCallbackServerIgnoresOtherPaths() async throws {
        let server = try await ChatGPTCallbackServer.start(preferredPort: 0)
        defer { server.stop() }
        let base = "http://127.0.0.1:\(server.port)"
        let (_, favicon) = try await URLSession.shared.data(from: URL(string: base + "/favicon.ico")!)
        XCTAssertEqual((favicon as? HTTPURLResponse)?.statusCode, 404)
        Task { _ = try? await URLSession.shared.data(from: URL(string: base + "/auth/callback?code=c&state=s")!) }
        let items = try await server.waitForCallback(timeout: 5)
        XCTAssertEqual(items.first { $0.name == "code" }?.value, "c")
    }

    private func assertFails(_ engine: ChatGPTEngine, contains text: String, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await engine.run(Self.request) { _ in }
            XCTFail("should fail", file: file, line: line)
        } catch {
            XCTAssertTrue(error.localizedDescription.contains(text), error.localizedDescription, file: file, line: line)
        }
    }

    static func unsignedIDToken(_ claims: [String: Any]) -> String {
        func part(_ json: [String: Any]) -> String { ChatGPTOAuth.base64url(try! JSONSerialization.data(withJSONObject: json)) }
        return part(["alg": "RS256", "kid": "k"]) + "." + part(claims) + ".c2ln"
    }
}

private final class ChatGPTUpdateLog: @unchecked Sendable {
    private let lock = NSLock()
    private var updates: [[String]] = []
    private var _nonce = ""
    func add(_ takes: [String]) { lock.lock(); updates.append(takes); lock.unlock() }
    var all: [[String]] { lock.lock(); defer { lock.unlock() }; return updates }
    var nonce: String {
        get { lock.lock(); defer { lock.unlock() }; return _nonce }
        set { lock.lock(); _nonce = newValue; lock.unlock() }
    }
}

/// An HTTP server on 127.0.0.1 that answers each request with canned chunks, and shows the handler the headers.
private final class ChatGPTMockServer: @unchecked Sendable {
    struct Request {
        var path: String
        var headers: [String: String]
        var body: Data
    }
    struct Response {
        var status: Int
        var contentType: String
        var chunks: [Data]
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "chatgpt-mock-server")
    private let handler: (Request) -> Response
    private(set) var port: UInt16 = 0
    var baseURL: String { "http://127.0.0.1:\(port)/v1" }
    func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)\(path)")! }

    init(handler: @escaping (Request) -> Response) throws {
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

    static func chunked(_ text: String, size: Int) -> [Data] {
        let bytes = Array(text.utf8)
        return stride(from: 0, to: bytes.count, by: size).map { Data(bytes[$0..<min($0 + size, bytes.count)]) }
    }

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
            let lines = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self).split(separator: "\r\n")
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            let length = Int(headers["content-length"] ?? "") ?? 0
            let body = buffer[headerEnd.upperBound...]
            if body.count < length, !done {
                self.receive(connection, buffer: buffer)
                return
            }
            let target = lines.first?.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let path = URLComponents(string: target)?.path ?? target
            self.respond(connection, self.handler(Request(path: path, headers: headers, body: Data(body))))
        }
    }

    private func respond(_ connection: NWConnection, _ response: Response) {
        var head = "HTTP/1.1 \(response.status) Mock\r\nContent-Type: \(response.contentType)\r\nConnection: close\r\n"
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
