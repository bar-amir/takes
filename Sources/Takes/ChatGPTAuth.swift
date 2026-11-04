import CryptoKit
import Foundation
import Network
import Security

// Sign in with ChatGPT, the OAuth half: registration, PKCE, the loopback callback, token exchange and refresh,
// ID-token checks, and where the tokens live. Follows https://developers.openai.com/siwc/token-sharing-open-source/sign-in
// and .../profiles-and-sessions, .../token-reference, .../errors-and-recovery (read 2 November 2026).

enum ChatGPTOAuth {
    static let issuer = "https://auth.openai.com"
    static let authorizeURL = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    static let tokenURL = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    static let discoveryURL = URL(string: "https://auth.openai.com/.well-known/openid-configuration")!
    static let resource = "https://api.openai.com/v1"
    static let scopes = ["openid", "profile", "email", "offline_access", "resource.invoke", "chatgpt.tokens.use.direct"]
    /// Without this scope the user signed in but didn't let Takes use the plan; no inference is allowed.
    static let sharingScope = "chatgpt.tokens.use.direct"
    /// The client ID for a first sign-in; OpenAI answers with the app's own issued one (`oaiapp_…`).
    static let registrationClientID = "dynamic_agent_client"
    static let appName = "Takes"
    static let callbackPath = "/auth/callback"
    static let preferredPort: UInt16 = 1455
    static let signInTimeout: TimeInterval = 5 * 60
    /// Where the user sets how much of the plan each app may use.
    static let usageURL = URL(string: "https://chatgpt.com/settings/usage")!
    /// Refresh this long before the access token expires.
    static let refreshMargin: TimeInterval = 60

    static func redirectURI(port: UInt16) -> String { "http://127.0.0.1:\(port)\(callbackPath)" }

    /// Base64url without padding (RFC 7636 §3, RFC 7515 §2).
    static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64urlDecode(_ text: Substring) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    static func randomToken(bytes: Int = 32) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return base64url(data)
    }
}

/// PKCE with S256 (RFC 7636).
struct PKCE: Equatable {
    let verifier: String
    var challenge: String { Self.challenge(for: verifier) }

    static func random() -> PKCE { PKCE(verifier: ChatGPTOAuth.randomToken(bytes: 32)) }
    static func challenge(for verifier: String) -> String {
        ChatGPTOAuth.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
}

/// One browser sign-in: fresh state, nonce and PKCE values, and the redirect it must come back to.
struct ChatGPTAuthorization {
    var hostID: String
    /// The issued client ID from an earlier sign-in, or nil to register Takes.
    var clientID: String?
    var port: UInt16
    var state = ChatGPTOAuth.randomToken()
    var nonce = ChatGPTOAuth.randomToken()
    var pkce = PKCE.random()

    var redirectURI: String { ChatGPTOAuth.redirectURI(port: port) }

    func url(idTokenHint: String? = nil, loginHint: String? = nil) -> URL {
        var items = [URLQueryItem(name: "client_id", value: clientID ?? ChatGPTOAuth.registrationClientID)]
        if clientID == nil {
            items.append(URLQueryItem(name: "agent_name_hint", value: ChatGPTOAuth.appName))
        } else {
            if let idTokenHint { items.append(URLQueryItem(name: "id_token_hint", value: idTokenHint)) }
            if let loginHint { items.append(URLQueryItem(name: "login_hint", value: loginHint)) }
        }
        items += [
            URLQueryItem(name: "ext_agent_host_id", value: hostID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: ChatGPTOAuth.scopes.joined(separator: " ")),
            URLQueryItem(name: "resource", value: ChatGPTOAuth.resource),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
        ]
        var components = URLComponents(url: ChatGPTOAuth.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = items
        // URLComponents leaves "+" and "@" alone in queries; encode every value fully, as the docs ask.
        components.percentEncodedQuery = items.map { "\($0.name)=\(Self.formEncode($0.value ?? ""))" }.joined(separator: "&")
        return components.url!
    }

    /// What the browser brought back to the loopback callback.
    struct Callback: Equatable {
        var code: String
        /// The issued client ID: set on a first registration, maybe absent on later sign-ins.
        var clientID: String
        var scope: String?
    }

    enum CallbackError: Error, Equatable {
        case stateMismatch, denied, missingCode, missingClientID, clientMismatch, other(String)
    }

    /// Checks `state` first, then everything else. A first registration must bring an issued client ID back.
    func parseCallback(_ items: [URLQueryItem]) -> Result<Callback, CallbackError> {
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let returned = value("state"), returned == state else { return .failure(.stateMismatch) }
        if let error = value("error") { return .failure(error == "access_denied" ? .denied : .other(value("error_description") ?? error)) }
        guard let code = value("code"), !code.isEmpty else { return .failure(.missingCode) }
        let issued = value("client_id").flatMap { $0.isEmpty || $0 == ChatGPTOAuth.registrationClientID ? nil : $0 }
        if let clientID {
            if let issued, issued != clientID { return .failure(.clientMismatch) }
            return .success(Callback(code: code, clientID: clientID, scope: value("scope")))
        }
        guard let issued else { return .failure(.missingClientID) }
        return .success(Callback(code: code, clientID: issued, scope: value("scope")))
    }

    static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

// MARK: - Tokens

struct ChatGPTTokenResponse: Decodable, Equatable {
    var access_token: String
    var refresh_token: String?
    var id_token: String?
    var token_type: String?
    var expires_in: Double?
    var scope: String?
}

/// The signed-in account's tokens and who it is. One keychain item, so a refresh replaces everything at once.
struct ChatGPTCredentials: Codable, Equatable {
    var clientID: String
    var accessToken: String
    var refreshToken: String?
    var idToken: String?
    var expiresAt: Date
    var scopes: [String]
    var subject: String?
    var email: String?
    var name: String?

    /// The user allowed Takes to use the plan.
    var sharing: Bool { scopes.contains(ChatGPTOAuth.sharingScope) }

    func needsRefresh(now: Date = Date()) -> Bool { now.addingTimeInterval(ChatGPTOAuth.refreshMargin) >= expiresAt }

    init(clientID: String, response: ChatGPTTokenResponse, claims: ChatGPTIDToken.Claims?, now: Date = Date()) {
        self.clientID = clientID
        accessToken = response.access_token
        refreshToken = response.refresh_token
        idToken = response.id_token
        expiresAt = now.addingTimeInterval(response.expires_in ?? 3600)
        scopes = Self.scopes(response.scope)
        subject = claims?.sub
        email = claims?.email
        name = claims?.name
    }

    /// After a refresh: access token, expiry, granted scopes and the rotated refresh token are replaced together.
    /// A field the server leaves out keeps its old value; the identity never changes on a refresh.
    func refreshed(with response: ChatGPTTokenResponse, now: Date = Date()) -> ChatGPTCredentials {
        var next = self
        next.accessToken = response.access_token
        next.expiresAt = now.addingTimeInterval(response.expires_in ?? 3600)
        if response.scope != nil { next.scopes = Self.scopes(response.scope) }
        if let refresh = response.refresh_token { next.refreshToken = refresh }
        if let id = response.id_token { next.idToken = id }
        return next
    }

    static func scopes(_ scope: String?) -> [String] {
        (scope ?? "").split(separator: " ").map(String.init).sorted()
    }
}

/// OpenID Connect ID-token checks: issuer, audience (the issued client ID), expiry, nonce, and the RS256 signature
/// against the keys the issuer publishes.
enum ChatGPTIDToken {
    struct Claims: Equatable {
        var iss: String?
        var aud: [String]
        var exp: Date?
        var nonce: String?
        var sub: String?
        var email: String?
        var name: String?
    }

    enum Problem: Error, Equatable { case malformed, issuer, audience, expired, nonce, signature }

    static func claims(_ token: String) -> Claims? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let data = ChatGPTOAuth.base64urlDecode(parts[1]),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let aud = (json["aud"] as? [String]) ?? (json["aud"] as? String).map { [$0] } ?? []
        return Claims(iss: json["iss"] as? String, aud: aud, exp: (json["exp"] as? Double).map(Date.init(timeIntervalSince1970:)),
                      nonce: json["nonce"] as? String, sub: json["sub"] as? String, email: json["email"] as? String,
                      name: json["name"] as? String)
    }

    /// The claim checks; a little clock skew is allowed on expiry.
    static func validate(_ token: String, nonce: String, clientID: String, now: Date = Date()) -> Result<Claims, Problem> {
        guard let claims = claims(token) else { return .failure(.malformed) }
        guard claims.iss == ChatGPTOAuth.issuer else { return .failure(.issuer) }
        guard claims.aud.contains(clientID) else { return .failure(.audience) }
        guard let exp = claims.exp, exp.addingTimeInterval(120) > now else { return .failure(.expired) }
        guard claims.nonce == nonce else { return .failure(.nonce) }
        return .success(claims)
    }

    static func header(_ token: String) -> [String: Any]? {
        guard let first = token.split(separator: ".").first, let data = ChatGPTOAuth.base64urlDecode(first) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// RS256 over "header.payload".
    static func verify(_ token: String, key: SecKey) -> Bool {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, (header(token)?["alg"] as? String) == "RS256",
              let signature = ChatGPTOAuth.base64urlDecode(parts[2]) else { return false }
        let input = Data("\(parts[0]).\(parts[1])".utf8)
        return SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, input as CFData, signature as CFData, nil)
    }

    /// The matching RSA key from a JWKS document (by `kid`, or the only RSA key).
    static func key(for token: String, jwks: Data) -> SecKey? {
        guard let json = (try? JSONSerialization.jsonObject(with: jwks)) as? [String: Any],
              let keys = json["keys"] as? [[String: Any]] else { return nil }
        let rsa = keys.filter { $0["kty"] as? String == "RSA" }
        let kid = header(token)?["kid"] as? String
        guard let jwk = rsa.first(where: { kid != nil && $0["kid"] as? String == kid }) ?? (rsa.count == 1 ? rsa.first : nil),
              let n = (jwk["n"] as? String).flatMap({ ChatGPTOAuth.base64urlDecode(Substring($0)) }),
              let e = (jwk["e"] as? String).flatMap({ ChatGPTOAuth.base64urlDecode(Substring($0)) }) else { return nil }
        return rsaKey(modulus: n, exponent: e)
    }

    /// A public key from its modulus and exponent, as a PKCS#1 RSAPublicKey (SEQUENCE { INTEGER n, INTEGER e }).
    static func rsaKey(modulus: Data, exponent: Data) -> SecKey? {
        func length(_ count: Int) -> [UInt8] {
            if count < 0x80 { return [UInt8(count)] }
            var bytes: [UInt8] = []
            var value = count
            while value > 0 { bytes.insert(UInt8(value & 0xFF), at: 0); value >>= 8 }
            return [0x80 | UInt8(bytes.count)] + bytes
        }
        func integer(_ data: Data) -> [UInt8] {
            var bytes = Array(data.drop { $0 == 0 })
            if bytes.first.map({ $0 & 0x80 != 0 }) ?? true { bytes.insert(0, at: 0) }
            return [0x02] + length(bytes.count) + bytes
        }
        let body = integer(modulus) + integer(exponent)
        let der = Data([0x30] + length(body.count) + body)
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
        return SecKeyCreateWithData(der as CFData, attributes as CFDictionary, nil)
    }
}

enum ChatGPTAuthError: LocalizedError, Equatable {
    case timedOut, denied, failed(String)
    /// The refresh token can't be used any more; only a fresh sign-in helps.
    case signInAgain

    var errorDescription: String? {
        switch self {
        case .timedOut: "The browser sign-in didn't finish within 5 minutes. Try again."
        case .denied: "Sign-in was cancelled in the browser. Try again when you're ready."
        case .failed(let message): message
        case .signInAgain: "Sign in to ChatGPT again in Settings › Engine."
        }
    }

    /// Refresh errors after which the tokens are useless (errors-and-recovery, "Refresh errors").
    static let terminalRefreshCodes: Set = ["invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired",
                                            "refresh_token_invalidated", "refresh_token_reused"]
}

/// Talks to the token endpoint. The URLs are overridable so tests can point it at a mock server.
struct ChatGPTAuthClient {
    var tokenURL = ChatGPTOAuth.tokenURL
    var discoveryURL: URL? = ChatGPTOAuth.discoveryURL
    var session = URLSession.shared

    static func formBody(_ fields: [(String, String)]) -> Data {
        Data(fields.map { "\($0.0)=\(ChatGPTAuthorization.formEncode($0.1))" }.joined(separator: "&").utf8)
    }

    /// The `authorization_code` grant. No client secret: Takes is a public client.
    func exchange(_ callback: ChatGPTAuthorization.Callback, for attempt: ChatGPTAuthorization) async throws -> ChatGPTTokenResponse {
        try await post([("grant_type", "authorization_code"), ("client_id", callback.clientID), ("code", callback.code),
                        ("code_verifier", attempt.pkce.verifier), ("redirect_uri", attempt.redirectURI),
                        ("resource", ChatGPTOAuth.resource)])
    }

    /// The `refresh_token` grant; `scope` is left out to keep the existing grant.
    func refresh(_ credentials: ChatGPTCredentials) async throws -> ChatGPTTokenResponse {
        guard let refreshToken = credentials.refreshToken else { throw ChatGPTAuthError.signInAgain }
        return try await post([("grant_type", "refresh_token"), ("client_id", credentials.clientID),
                               ("refresh_token", refreshToken), ("resource", ChatGPTOAuth.resource)])
    }

    private func post(_ fields: [(String, String)]) async throws -> ChatGPTTokenResponse {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.httpBody = Self.formBody(fields)
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 200, let tokens = try? JSONDecoder().decode(ChatGPTTokenResponse.self, from: data) { return tokens }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let code = json?["error"] as? String ?? (json?["error"] as? [String: Any])?["code"] as? String
        if let code, ChatGPTAuthError.terminalRefreshCodes.contains(code) { throw ChatGPTAuthError.signInAgain }
        let detail = json?["error_description"] as? String ?? code ?? "HTTP \(status)"
        throw ChatGPTAuthError.failed("ChatGPT sign-in failed: \(detail).")
    }

    /// Checks the ID token's claims, and its signature when the issuer's keys can be fetched. The token came straight
    /// from the token endpoint over TLS, so when the keys can't be reached the claim checks still stand (OIDC Core 3.1.3.7).
    func validate(_ idToken: String, nonce: String, clientID: String) async -> Result<ChatGPTIDToken.Claims, ChatGPTIDToken.Problem> {
        let result = ChatGPTIDToken.validate(idToken, nonce: nonce, clientID: clientID)
        guard case .success = result, let jwks = await fetchJWKS() else { return result }
        guard let key = ChatGPTIDToken.key(for: idToken, jwks: jwks), ChatGPTIDToken.verify(idToken, key: key) else {
            return .failure(.signature)
        }
        return result
    }

    private func fetchJWKS() async -> Data? {
        guard let discoveryURL,
              let (data, _) = try? await session.data(from: discoveryURL),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["issuer"] as? String == ChatGPTOAuth.issuer,
              let jwksURL = (json["jwks_uri"] as? String).flatMap(URL.init(string:)), jwksURL.scheme == "https",
              let (keys, _) = try? await session.data(from: jwksURL) else { return nil }
        return keys
    }
}

// MARK: - Where it's kept

/// The opaque ID of this Mac for OpenAI (`ext_agent_host_id`): a random UUID, made once, never tied to the user.
/// Kept in Application Support next to settings, so it survives sign-out.
enum ChatGPTHost {
    static func id(in directory: URL = Store.directory) -> String {
        let file = directory.appendingPathComponent("chatgpt-host.json")
        if let data = try? Data(contentsOf: file),
           let saved = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["ext_agent_host_id"],
           saved.hasPrefix("urn:uuid:") {
            return saved
        }
        let id = "urn:uuid:" + UUID().uuidString.lowercased()
        if let data = try? JSONSerialization.data(withJSONObject: ["ext_agent_host_id": id], options: [.prettyPrinted]) {
            try? data.write(to: file, options: .atomic)
        }
        return id
    }
}

/// Generic-password items in the login keychain, service `com.baramir.takes`, accounts `chatgpt-…`.
enum ChatGPTKeychain {
    static let service = "com.baramir.takes"

    static func data(_ account: String) -> Data? {
        var item: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    static func set(_ data: Data?, _ account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard let data else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Where tokens are saved. The keychain in the app; memory in tests.
protocol ChatGPTCredentialStore: AnyObject, Sendable {
    func load() -> ChatGPTCredentials?
    func save(_ credentials: ChatGPTCredentials?)
    /// The issued client ID and who registered it; kept after sign-out so signing in again reuses the registration.
    func loadRegistration() -> ChatGPTRegistration?
    func saveRegistration(_ registration: ChatGPTRegistration?)
}

struct ChatGPTRegistration: Codable, Equatable {
    var clientID: String
    var subject: String?
}

final class ChatGPTKeychainStore: ChatGPTCredentialStore, @unchecked Sendable {
    static let shared = ChatGPTKeychainStore()
    private let credentialsAccount = "chatgpt-credentials"
    private let registrationAccount = "chatgpt-registration"

    func load() -> ChatGPTCredentials? {
        ChatGPTKeychain.data(credentialsAccount).flatMap { try? JSONDecoder().decode(ChatGPTCredentials.self, from: $0) }
    }
    func save(_ credentials: ChatGPTCredentials?) {
        ChatGPTKeychain.set(credentials.flatMap { try? JSONEncoder().encode($0) }, credentialsAccount)
    }
    func loadRegistration() -> ChatGPTRegistration? {
        ChatGPTKeychain.data(registrationAccount).flatMap { try? JSONDecoder().decode(ChatGPTRegistration.self, from: $0) }
    }
    func saveRegistration(_ registration: ChatGPTRegistration?) {
        ChatGPTKeychain.set(registration.flatMap { try? JSONEncoder().encode($0) }, registrationAccount)
    }
}

final class ChatGPTMemoryStore: ChatGPTCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: ChatGPTCredentials?
    private var registration: ChatGPTRegistration?
    init(_ credentials: ChatGPTCredentials? = nil, registration: ChatGPTRegistration? = nil) {
        self.credentials = credentials
        self.registration = registration
    }
    func load() -> ChatGPTCredentials? { lock.withLock { credentials } }
    func save(_ credentials: ChatGPTCredentials?) { lock.withLock { self.credentials = credentials } }
    func loadRegistration() -> ChatGPTRegistration? { lock.withLock { registration } }
    func saveRegistration(_ registration: ChatGPTRegistration?) { lock.withLock { self.registration = registration } }
}

/// Hands out a fresh access token, refreshing 60 s before expiry or when asked after a 401. Refreshes are serialized,
/// because each one rotates the refresh token.
actor ChatGPTTokens {
    static let shared = ChatGPTTokens(store: ChatGPTKeychainStore.shared)

    let store: ChatGPTCredentialStore
    var client: ChatGPTAuthClient
    /// Told when a refresh proves the tokens are dead, so the UI can show "signed out".
    var onSignedOut: (@Sendable () -> Void)?
    private var refreshing: Task<ChatGPTCredentials, Error>?

    init(store: ChatGPTCredentialStore, client: ChatGPTAuthClient = ChatGPTAuthClient()) {
        self.store = store
        self.client = client
    }

    func setOnSignedOut(_ handler: @escaping @Sendable () -> Void) { onSignedOut = handler }

    /// A token allowed to use the plan. `forceRefresh` after the API refused the current one.
    func accessToken(forceRefresh: Bool = false, now: Date = Date()) async throws -> String {
        guard let credentials = store.load() else { throw EngineError.failed("Sign in to ChatGPT in Settings › Engine.") }
        guard credentials.sharing else {
            throw EngineError.failed("Signed in, but plan usage wasn't allowed. Sign in again in Settings › Engine and allow it.")
        }
        guard forceRefresh || credentials.needsRefresh(now: now) else { return credentials.accessToken }
        return try await refresh(credentials).accessToken
    }

    private func refresh(_ credentials: ChatGPTCredentials) async throws -> ChatGPTCredentials {
        if let refreshing { return try await refreshing.value }
        let client = client, store = store, onSignedOut = onSignedOut
        let task = Task<ChatGPTCredentials, Error> {
            do {
                let next = credentials.refreshed(with: try await client.refresh(credentials))
                store.save(next)
                return next
            } catch ChatGPTAuthError.signInAgain {
                // Dead refresh token: clear the tokens, keep the registration so signing in again reuses it.
                store.save(nil)
                onSignedOut?()
                throw EngineError.failed(ChatGPTAuthError.signInAgain.errorDescription!)
            } catch let error as URLError {
                // Network trouble isn't a sign-out; keep the tokens.
                throw EngineError.failed("Couldn't reach ChatGPT: \(error.localizedDescription)")
            }
        }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }
}

// MARK: - The loopback callback

/// A one-shot HTTP listener on 127.0.0.1 for the browser's redirect. It answers `/auth/callback` with a short page,
/// hands the query to whoever waits, and stops. Other paths (a favicon) get a 404 and it keeps listening.
final class ChatGPTCallbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "chatgpt-callback")
    private let lock = NSLock()
    private var waiting: CheckedContinuation<[URLQueryItem], Error>?
    private var received: Result<[URLQueryItem], Error>?
    /// Picks the page the browser shows for a callback: true when sign-in can go on.
    var accepts: ([URLQueryItem]) -> Bool = { _ in true }
    /// Whether a callback is for this sign-in at all (its `state` matches). Any web page or local program can send a
    /// request to the loopback port; one that isn't for this sign-in gets a 400 and the listener keeps waiting, so it
    /// can't end the sign-in.
    var belongs: ([URLQueryItem]) -> Bool = { _ in true }
    private(set) var port: UInt16 = 0

    private init(listener: NWListener) {
        self.listener = listener
    }

    /// Listens on 127.0.0.1, on port 1455 if it's free, otherwise any free port.
    static func start(preferredPort: UInt16 = ChatGPTOAuth.preferredPort) async throws -> ChatGPTCallbackServer {
        if preferredPort != 0, let server = try? await start(port: NWEndpoint.Port(rawValue: preferredPort) ?? .any) { return server }
        return try await start(port: .any)
    }

    private static func start(port: NWEndpoint.Port) async throws -> ChatGPTCallbackServer {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        let listener = try NWListener(using: parameters)
        let server = ChatGPTCallbackServer(listener: listener)
        // NWListener refuses to start without a connection handler.
        listener.newConnectionHandler = { [weak server] connection in server?.serve(connection) }
        let queue = DispatchQueue(label: "chatgpt-callback-start")
        let bound: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let once = OnceFlag()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.take() { continuation.resume(returning: listener.port?.rawValue ?? 0) }
                case .failed(let error), .waiting(let error):
                    if once.take() { listener.cancel(); continuation.resume(throwing: error) }
                case .cancelled:
                    if once.take() { continuation.resume(throwing: CancellationError()) }
                default: break
                }
            }
            listener.start(queue: queue)
        }
        server.port = bound
        listener.stateUpdateHandler = nil
        return server
    }

    func stop() {
        listener.cancel()
        finish(.failure(CancellationError()))
    }

    /// The callback's query items, or `ChatGPTAuthError.timedOut`.
    func waitForCallback(timeout: TimeInterval = ChatGPTOAuth.signInTimeout) async throws -> [URLQueryItem] {
        try await withThrowingTaskGroup(of: [URLQueryItem].self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        self.lock.lock()
                        if let received = self.received {
                            self.lock.unlock()
                            continuation.resume(with: received)
                        } else {
                            self.waiting = continuation
                            self.lock.unlock()
                        }
                    }
                } onCancel: { self.stop() }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw ChatGPTAuthError.timedOut
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    private func finish(_ result: Result<[URLQueryItem], Error>) {
        lock.lock()
        guard received == nil else { lock.unlock(); return }
        received = result
        let continuation = waiting
        waiting = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, done, _ in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if !done, buffer.count < 65536 { self.receive(connection, buffer: buffer) } else { connection.cancel() }
                return
            }
            let line = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self).split(separator: "\r\n").first ?? ""
            let parts = line.split(separator: " ")
            let target = parts.count > 1 ? String(parts[1]) : "/"
            let components = URLComponents(string: "http://127.0.0.1\(target)")
            guard parts.first == "GET", components?.path == ChatGPTOAuth.callbackPath else {
                self.respond(connection, status: "404 Not Found", html: Self.page(title: "Not found", body: ""))
                return
            }
            let items = components?.queryItems ?? []
            guard self.belongs(items) else {
                self.respond(connection, status: "400 Bad Request",
                             html: Self.page(title: "Not this sign-in", body: "Go back to Takes. You can close this tab."))
                return
            }
            let ok = self.accepts(items)
            self.respond(connection, status: "200 OK", html: ok
                ? Self.page(title: "Signed in", body: "You can close this tab and go back to Takes.")
                : Self.page(title: "Sign-in didn't finish", body: "Go back to Takes to try again. You can close this tab."))
            self.finish(.success(items))
        }
    }

    private func respond(_ connection: NWConnection, status: String, html: String) {
        let body = Data(html.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\n"
            + "Cache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// The tab the browser lands on: plain text in the house voice, light and dark, no script.
    static func page(title: String, body: String) -> String {
        """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><title>Takes · \(title)</title>
        <meta name="viewport" content="width=device-width, initial-scale=1"><meta name="color-scheme" content="light dark">
        <style>body{font:15px -apple-system,system-ui,sans-serif;margin:0;min-height:100vh;display:grid;place-items:center;
        background:#F7F7F9;color:#1C1C1F}main{max-width:360px;padding:24px}h1{font-size:20px;margin:0 0 8px}p{margin:0;color:#55555E}
        @media(prefers-color-scheme:dark){body{background:#242429;color:#F2F2F5}p{color:#A9A9B3}}</style></head>
        <body><main><h1>\(title)</h1><p>\(body)</p></main></body></html>
        """
    }
}

/// Lets exactly one caller through, from any thread.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func take() -> Bool { lock.withLock { defer { done = true }; return !done } }
}
