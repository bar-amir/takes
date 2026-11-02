import AppKit
import SwiftUI

// A fifth engine: Sign in with ChatGPT. A Plus or Pro plan, used through OpenAI's OAuth flow (OIDC + PKCE, loopback
// callback on 127.0.0.1, ChatGPTAuth.swift) and the Responses API (`store: false`, `stream: true`, system prompt in
// `instructions`). Requests come from this Mac, for this user, for Takes only; tokens live in the keychain. Free for the
// user, always. Rules: https://openai.com/policies/sign-in-with-chatgpt-terms/ and
// https://developers.openai.com/siwc/token-sharing-open-source (models-and-inference, preview-limitations, errors-and-recovery).

/// Streams takes from the Responses API with the signed-in user's plan.
struct ChatGPTEngine: TakesEngine {
    static let defaultBaseURL = "https://api.openai.com/v1"
    /// Tests point this at a mock server on 127.0.0.1.
    var baseURL = ChatGPTEngine.defaultBaseURL
    var tokens = ChatGPTTokens.shared
    var session = URLSession.shared

    func run(_ request: EngineRequest, onUpdate: @escaping @Sendable ([String]) -> Void) async throws -> EngineResult {
        guard !request.model.isEmpty else { throw EngineError.failed("Pick a ChatGPT model in Settings › Engine.") }
        let started = Date()
        let elapsedMs = { Int(Date().timeIntervalSince(started) * 1000) }

        let (bytes, http) = try await authorized { token in
            try await session.bytes(for: Self.responsesRequest(baseURL: baseURL, token: token, model: request.model,
                                                               instructions: request.system, user: request.user))
        }
        if http.statusCode != 200 {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw Self.httpError(status: http.statusCode, body: data, requestID: http.value(forHTTPHeaderField: "x-request-id"))
        }

        var parser = SSEParser()
        var text = ""
        var firstTextMs: Int?
        var finished: ResponsesEvent?
        var line = Data()

        func handle(_ events: [SSEParser.Event]) throws {
            for event in events {
                guard case .data(let payload) = event, let parsed = ResponsesEvent.parse(payload) else { continue }
                switch parsed {
                case .delta(let piece):
                    guard !piece.isEmpty else { continue }
                    if firstTextMs == nil { firstTextMs = elapsedMs() }
                    text += piece
                    onUpdate(TakeSplitter.split(text, streaming: true))
                case .completed, .incomplete:
                    finished = parsed
                case .failed(let code, let message, let param):
                    throw EngineError.failed(Self.message(code: code, message: message, param: param, status: nil))
                }
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
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw EngineError.failed("The connection to ChatGPT dropped. Try again.")
        }

        let takes = TakeSplitter.split(text, streaming: false)
        switch finished {
        case .completed?:
            guard !takes.isEmpty else { throw EngineError.failed("ChatGPT returned no takes. Try again, or pick another model.") }
        case .incomplete?:
            guard !takes.isEmpty else { throw EngineError.failed("ChatGPT stopped early. Try again.") }
        default:
            // Only `response.completed` means success; a stream that just ends is a dropped connection.
            throw EngineError.failed("The connection to ChatGPT dropped before the takes were done. Try again.")
        }
        return EngineResult(takes: takes, wallMs: elapsedMs(), firstTextMs: firstTextMs)
    }

    /// Sends with the current token; after a 401 refreshes once and sends again.
    private func authorized<Body>(_ send: (String) async throws -> (Body, URLResponse)) async throws -> (Body, HTTPURLResponse) {
        var (body, response) = try await friendly { try await send(try await tokens.accessToken()) }
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            (body, response) = try await friendly { try await send(try await tokens.accessToken(forceRefresh: true)) }
            if (response as? HTTPURLResponse)?.statusCode == 401 {
                throw EngineError.failed(ChatGPTAuthError.signInAgain.errorDescription!)
            }
        }
        guard let http = response as? HTTPURLResponse else { throw EngineError.failed("No answer from ChatGPT.") }
        return (body, http)
    }

    private func friendly<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                throw EngineError.failed("Couldn't reach ChatGPT. Check your internet connection and try again.")
            case .timedOut: throw EngineError.failed("ChatGPT took too long to answer. Try again.")
            default: throw EngineError.failed("Couldn't reach ChatGPT: \(error.localizedDescription)")
            }
        }
    }

    /// The whole body: these five fields and nothing else (no temperature, token cap, metadata, user or system items).
    static func responsesRequest(baseURL: String, token: String, model: String, instructions: String, user: String) throws -> URLRequest {
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/responses") else {
            throw EngineError.failed("Bad ChatGPT address.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("text/event-stream", forHTTPHeaderField: "accept")
        request.timeoutInterval = 120
        let body: [String: Any] = [
            "model": model,
            "instructions": instructions,
            "input": [["role": "user", "content": user]],
            "store": false,
            "stream": true,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func httpError(status: Int, body: Data, requestID: String?) -> EngineError {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let error = json?["error"] as? [String: Any]
        let message = error?["message"] as? String ?? json?["detail"] as? String
            ?? String(decoding: body.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(Self.message(code: error?["code"] as? String, message: message, param: error?["param"] as? String,
                                    status: status, requestID: requestID))
    }

    static let usageLimitMessage = "You've used this week's ChatGPT allowance for Takes. Manage it in ChatGPT › Settings › Usage, or pick another engine."
    static let unavailableMessage = "Your ChatGPT plan can't be used in Takes right now. Check ChatGPT › Settings › Usage."

    /// Plain words for OpenAI's error codes (errors-and-recovery); the HTTP status when there's no code.
    static func message(code: String?, message: String?, param: String?, status: Int?, requestID: String? = nil) -> String {
        switch code {
        case "subscription_sharing_usage_limit_exceeded": return usageLimitMessage
        case "subscription_sharing_usage_unavailable": return unavailableMessage
        case "subscription_sharing_user_unavailable": return "ChatGPT can't take requests from Takes right now. Try again in a moment."
        case "subscription_sharing_user_not_eligible":
            return "This ChatGPT account can't use its plan in other apps. Pick another engine in Settings › Engine."
        case "subscription_sharing_invalid_user": return ChatGPTAuthError.signInAgain.errorDescription!
        case "chatpass_v2_scope_not_authorized", "chatpass_v2_invalid_authorization_context":
            return "Plan usage wasn't allowed for Takes. Sign in again in Settings › Engine and allow it."
        case "model_not_found":
            return "This model isn't available with your ChatGPT plan. Pick another in Settings › Engine."
        case "subscription_sharing_unsupported_capability" where param == "model":
            return "This model isn't available with your ChatGPT plan. Pick another in Settings › Engine."
        case "rate_limit_exceeded": return "ChatGPT is busy. Try again in a moment."
        default: break
        }
        let detail = (message?.isEmpty == false ? message! : status.map { "HTTP \($0)" } ?? "unknown error")
            + (requestID.map { " (request \($0))" } ?? "")
        switch status {
        case 401?: return ChatGPTAuthError.signInAgain.errorDescription!
        case 429?: return "ChatGPT is busy. Try again in a moment."
        case 503?: return "ChatGPT plan usage isn't available right now. Try again in a moment, or pick another engine."
        case 403?: return "ChatGPT refused the request: \(detail)"
        default: return "ChatGPT error: \(detail)"
        }
    }

    /// The models this account may use, in the server's order.
    func models() async -> Result<[ChatGPTModelList.Entry], Error> {
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/models") else {
            return .failure(EngineError.failed("Bad ChatGPT address."))
        }
        do {
            let (data, http) = try await authorized { token -> (Data, URLResponse) in
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
                request.timeoutInterval = 15
                return try await session.data(for: request)
            }
            guard http.statusCode == 200 else {
                return .failure(Self.httpError(status: http.statusCode, body: data, requestID: http.value(forHTTPHeaderField: "x-request-id")))
            }
            guard let entries = ChatGPTModelList.parse(data) else { return .failure(EngineError.failed("ChatGPT sent a model list Takes can't read.")) }
            return .success(entries)
        } catch {
            return .failure(error)
        }
    }

    /// A tiny request, to show that the plan answers and how fast.
    func test(model: String) async -> Result<Int, Error> {
        let request = EngineRequest(system: "Reply with the single word OK.", user: "Ready?", takes: 1, model: model, effort: "low")
        do {
            return .success(try await run(request) { _ in }.wallMs)
        } catch {
            return .failure(error)
        }
    }
}

/// The Responses stream events Takes acts on; everything else is skipped.
enum ResponsesEvent: Equatable {
    case delta(String)
    case completed
    case incomplete(reason: String?)
    case failed(code: String?, message: String?, param: String?)

    static func parse(_ payload: String) -> ResponsesEvent? {
        guard let json = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any] else { return nil }
        let response = json["response"] as? [String: Any]
        switch json["type"] as? String {
        case "response.output_text.delta": return .delta(json["delta"] as? String ?? "")
        case "response.completed": return .completed
        case "response.incomplete":
            return .incomplete(reason: (response?["incomplete_details"] as? [String: Any])?["reason"] as? String)
        case "response.failed":
            let error = response?["error"] as? [String: Any]
            return .failed(code: error?["code"] as? String, message: error?["message"] as? String, param: error?["param"] as? String)
        case "error", nil:
            // `{"type":"error","code":…}`, or a plain `{"error":{…}}` body where an event was expected.
            let error = json["error"] as? [String: Any] ?? json
            guard json["type"] != nil || json["error"] != nil else { return nil }
            return .failed(code: error["code"] as? String, message: error["message"] as? String, param: error["param"] as? String)
        default: return nil
        }
    }
}

enum ChatGPTModelList {
    struct Entry: Equatable {
        var slug: String
        var displayName: String
    }

    /// `{"models": [{"slug", "display_name", "visibility"}]}`: only `visibility == "list"`, in the server's order.
    static func parse(_ data: Data) -> [Entry]? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let models = json["models"] as? [[String: Any]] ?? json["data"] as? [[String: Any]] else { return nil }
        return models.compactMap { model in
            guard model["visibility"] as? String == "list", let slug = model["slug"] as? String, !slug.isEmpty else { return nil }
            let name = (model["display_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? slug
            return Entry(slug: slug, displayName: name)
        }
    }
}

/// Display names for ChatGPT model slugs, readable from any thread: `LocalModelList.label` asks here first,
/// so the panel's Model menu and run label say "GPT-5.4" rather than "gpt-5.4".
enum ChatGPTModelNames {
    private static let box = Box()
    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var names: [String: String] = [:]
    }

    static func name(for slug: String) -> String? { box.lock.withLock { box.names[slug] } }
    static func set(_ entries: [ChatGPTModelList.Entry]) {
        box.lock.withLock { for entry in entries { box.names[entry.slug] = entry.displayName } }
    }
}

/// The browser sign-in: registers Takes on first use, exchanges the code, keeps the tokens fresh.
@MainActor
final class ChatGPTSignIn: ObservableObject {
    static let shared = ChatGPTSignIn()
    enum State: Equatable { case signedOut, signingIn, signedIn(email: String?, sharing: Bool), failed(String) }
    @Published var state = State.signedOut
    /// Set when signing out couldn't confirm the revocation with OpenAI.
    @Published var signOutNote: String?

    let store: ChatGPTCredentialStore
    let tokens: ChatGPTTokens
    var client = ChatGPTAuthClient()
    private var task: Task<Void, Never>?

    init(store: ChatGPTCredentialStore = ChatGPTKeychainStore.shared, tokens: ChatGPTTokens = .shared) {
        self.store = store
        self.tokens = tokens
        if let credentials = store.load() { state = .signedIn(email: credentials.email, sharing: credentials.sharing) }
        Task { [weak self] in
            await tokens.setOnSignedOut { Task { @MainActor in self?.tokensWereRevoked() } }
        }
    }

    var email: String? { if case .signedIn(let email, _) = state { return email }; return nil }
    var canUsePlan: Bool { state == .signedIn(email: email, sharing: true) }

    /// Opens the browser and waits up to 5 minutes for the callback.
    func start() {
        guard state != .signingIn else { return }
        state = .signingIn
        signOutNote = nil
        let store = store, client = client, hostID = ChatGPTHost.id()
        task = Task {
            do {
                let credentials = try await Self.signIn(store: store, client: client, hostID: hostID) { url in
                    DispatchQueue.main.async { NSWorkspace.shared.open(url) }
                }
                guard !Task.isCancelled else { return }
                state = .signedIn(email: credentials.email, sharing: credentials.sharing)
                ChatGPTModels.shared.checked = false
                await ChatGPTModels.shared.refresh()
                await SetupMonitor.shared.refreshEngine()
            } catch {
                guard !Task.isCancelled else { return }
                state = error is CancellationError ? .signedOut : .failed(error.localizedDescription)
            }
        }
    }

    /// Stops waiting for the browser.
    func cancel() {
        task?.cancel()
        task = nil
        state = store.load().map { .signedIn(email: $0.email, sharing: $0.sharing) } ?? .signedOut
    }

    /// Forgets the tokens on this Mac and revokes the refresh token with OpenAI. The registration stays, so signing in
    /// again doesn't add a second "Takes" to the user's ChatGPT settings.
    func signOut() {
        task?.cancel()
        task = nil
        let credentials = store.load()
        store.save(nil)
        state = .signedOut
        signOutNote = nil
        ChatGPTModels.shared.models = []
        ChatGPTModels.shared.checked = false
        Task { await SetupMonitor.shared.refreshEngine() }
        guard let credentials, let refreshToken = credentials.refreshToken else { return }
        Task {
            if await !Self.revoke(refreshToken, clientID: credentials.clientID) {
                signOutNote = "Signed out on this Mac, but OpenAI didn't confirm it. You can also remove Takes in ChatGPT › Settings."
            }
        }
    }

    private func tokensWereRevoked() {
        guard case .signedIn = state else { return }
        state = .signedOut
        Task { await SetupMonitor.shared.refreshEngine() }
    }

    /// The whole browser flow, away from the UI so tests can drive it with a fake browser.
    nonisolated static func signIn(store: ChatGPTCredentialStore, client: ChatGPTAuthClient, hostID: String,
                                   timeout: TimeInterval = ChatGPTOAuth.signInTimeout,
                                   open: @escaping @Sendable (URL) -> Void) async throws -> ChatGPTCredentials {
        let server = try await ChatGPTCallbackServer.start()
        defer { server.stop() }
        let registration = store.loadRegistration()
        let previous = store.load()
        let attempt = ChatGPTAuthorization(hostID: hostID, clientID: registration?.clientID, port: server.port)
        server.accepts = { if case .success = attempt.parseCallback($0) { return true }; return false }
        open(attempt.url(idTokenHint: previous?.idToken, loginHint: previous?.email))

        let callback: ChatGPTAuthorization.Callback
        switch attempt.parseCallback(try await server.waitForCallback(timeout: timeout)) {
        case .success(let value): callback = value
        case .failure(.denied): throw ChatGPTAuthError.denied
        case .failure(.stateMismatch): throw ChatGPTAuthError.failed("The browser answered for a different sign-in. Try again.")
        case .failure(.clientMismatch): throw ChatGPTAuthError.failed("OpenAI answered for a different copy of Takes. Try again.")
        case .failure(.missingClientID): throw ChatGPTAuthError.failed("OpenAI didn't finish registering Takes. Try again.")
        case .failure(.missingCode): throw ChatGPTAuthError.failed("The browser came back without a sign-in code. Try again.")
        case .failure(.other(let message)): throw ChatGPTAuthError.failed("ChatGPT sign-in failed: \(message)")
        }
        // Saved before the exchange, so a failed exchange doesn't register Takes a second time.
        if registration?.clientID != callback.clientID { store.saveRegistration(ChatGPTRegistration(clientID: callback.clientID)) }

        var response: ChatGPTTokenResponse
        do {
            response = try await client.exchange(callback, for: attempt)
        } catch ChatGPTAuthError.signInAgain {
            throw ChatGPTAuthError.failed("The sign-in code expired. Try again.")
        }
        if response.scope == nil { response.scope = callback.scope }
        guard let idToken = response.id_token else { throw ChatGPTAuthError.failed("OpenAI didn't say who signed in. Try again.") }
        let claims: ChatGPTIDToken.Claims
        switch await client.validate(idToken, nonce: attempt.nonce, clientID: callback.clientID) {
        case .success(let value): claims = value
        case .failure(let problem): throw ChatGPTAuthError.failed("Takes couldn't verify the sign-in with OpenAI (\(problem)). Try again.")
        }
        // One account per Mac: the registration belongs to whoever first signed in with it.
        if let known = registration?.subject, registration?.clientID == callback.clientID, let subject = claims.sub, known != subject {
            store.saveRegistration(nil)
            throw ChatGPTAuthError.failed("That's a different ChatGPT account from the one Takes was set up with. Try again to connect this one.")
        }
        store.saveRegistration(ChatGPTRegistration(clientID: callback.clientID, subject: claims.sub))
        let credentials = ChatGPTCredentials(clientID: callback.clientID, response: response, claims: claims)
        store.save(credentials)
        return credentials
    }

    /// RFC 7009 revocation at the endpoint OpenAI's discovery document names. True when OpenAI answered 200.
    nonisolated static func revoke(_ refreshToken: String, clientID: String) async -> Bool {
        var request = URLRequest(url: URL(string: "https://auth.openai.com/api/accounts/oauth/revoke")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        request.httpBody = ChatGPTAuthClient.formBody([("token", refreshToken), ("token_type_hint", "refresh_token"), ("client_id", clientID)])
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(Double(attempt) * 2)) }
            guard let (_, response) = try? await URLSession.shared.data(for: request) else { continue }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return true }
            if status < 500 { return false }
        }
        return false
    }
}

/// The models the signed-in account may use, for Settings › Engine and the panel's Model menu.
@MainActor
final class ChatGPTModels: ObservableObject {
    static let shared = ChatGPTModels()
    /// Slugs, sent as `model`.
    @Published var models: [String] = []
    @Published var checking = false
    @Published var checked = false
    @Published var error: String?
    /// Snapshots set the state by hand and keep it.
    var frozen = false

    func refresh() async {
        guard !frozen, ChatGPTSignIn.shared.canUsePlan, !checking else { return }
        checking = true
        let result = await ChatGPTEngine().models()
        guard !frozen else { return }
        switch result {
        case .success(let entries):
            set(entries)
            error = nil
        case .failure(let failure):
            error = failure.localizedDescription
        }
        checking = false
        checked = true
        autoPick()
    }

    func set(_ entries: [ChatGPTModelList.Entry]) {
        ChatGPTModelNames.set(entries)
        models = entries.map(\.slug)
    }

    /// With no model picked yet, pick the first one OpenAI lists.
    private func autoPick() {
        guard Store.shared.settings.chatGPTModel.isEmpty, let first = models.first else { return }
        Store.shared.settings.chatGPTModel = first
    }

    func label(for slug: String) -> String { ChatGPTModelNames.name(for: slug) ?? slug }

    /// The models to offer, always including the picked one.
    func modelOptions(picked: String) -> [String] {
        var options = models
        if !picked.isEmpty, !options.contains(picked) { options.insert(picked, at: 0) }
        return options
    }
}

extension SetupMonitor {
    /// Ready when signed in, plan usage was granted, and a model is picked.
    static func chatGPTEngineStatus() async -> EngineStatus {
        let signIn = ChatGPTSignIn.shared
        guard case .signedIn(_, let sharing) = signIn.state else { return .problem("Not signed in to ChatGPT") }
        guard sharing else { return .problem("Plan usage not allowed") }
        if Store.shared.settings.chatGPTModel.isEmpty, !ChatGPTModels.shared.checked { await ChatGPTModels.shared.refresh() }
        let model = Store.shared.settings.chatGPTModel
        guard !model.isEmpty else { return .problem("Pick a model") }
        return .ready("ChatGPT · \(ChatGPTModels.shared.label(for: model))")
    }
}
