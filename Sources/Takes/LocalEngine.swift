import AppKit
import Foundation

// A third engine: a model running on this Mac through Ollama or LM Studio, which both serve the
// OpenAI-compatible chat-completions API on localhost. Nothing leaves the Mac: Takes refuses any address
// that isn't loopback, ignores system proxies and won't follow redirects off the Mac.
//
// Per-preset model: presets keep their Claude model (used again when you switch back to Claude). While the
// engine is a local model, every preset runs on the one local model picked in Settings › Model; the panel's
// Model menu lists the installed local models to switch for one run. Effort is a Claude setting and is hidden.

/// The local servers Takes knows how to find.
enum LocalServerKind: String, CaseIterable {
    case ollama, lmStudio

    var name: String { self == .ollama ? "Ollama" : "LM Studio" }
    var defaultBaseURL: String { self == .ollama ? "http://localhost:11434/v1" : "http://localhost:1234/v1" }
    var bundleIDs: [String] { self == .ollama ? ["com.electron.ollama"] : ["ai.elementlabs.lmstudio"] }
    var website: URL { URL(string: self == .ollama ? "https://ollama.com" : "https://lmstudio.ai")! }
    /// A small model that writes well enough, suggested when the server has none.
    static let suggestedOllamaModel = "llama3.2"

    /// Guesses the server from its port, for messages ("Ollama isn't running").
    static func guess(_ baseURL: String) -> LocalServerKind? {
        guard let port = URL(string: baseURL)?.port else { return nil }
        return port == 11434 ? .ollama : port == 1234 ? .lmStudio : nil
    }

    static func displayName(_ baseURL: String) -> String { guess(baseURL)?.name ?? String(localized: "The local model server") }

    /// The `ollama` command, for people who installed it with Homebrew rather than the app.
    static var ollamaCommand: String? {
        ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var appURL: URL? {
        for id in bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return url }
        }
        let path = self == .ollama ? "/Applications/Ollama.app" : "/Applications/LM Studio.app"
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }
}

/// Only addresses on this Mac are allowed.
enum LocalEndpoint {
    static func isLoopback(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.user == nil, url.password == nil,
              let rawHost = url.host?.lowercased() else { return false }
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host == "::1" { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts[0] == "127" && parts.allSatisfy { UInt8($0) != nil }
    }

    /// Turns what the user typed ("localhost:11434") into a base URL ending in /v1, or nil if it isn't on this Mac.
    static func normalize(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard var components = URLComponents(string: text) else { return nil }
        if components.path.isEmpty { components.path = "/v1" }
        guard let url = components.url, isLoopback(url) else { return nil }
        return url.absoluteString
    }

    /// `{base}/{path}`, only when the result is loopback.
    static func url(_ baseURL: String, _ path: String) -> URL? {
        var base = baseURL
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/" + path), isLoopback(url) else { return nil }
        return url
    }

    /// No proxies, no cookies or cache on disk, and no redirects off the Mac.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config, delegate: LoopbackRedirectGuard(), delegateQueue: nil)
    }()
}

final class LoopbackRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(LocalEndpoint.isLoopback) == true ? request : nil)
    }
}

/// Server-sent events, fed with bytes as they arrive (a chunk can end mid-line or mid-character).
struct SSEParser {
    enum Event: Equatable { case data(String), done }
    private var buffer = Data()

    mutating func feed(_ data: Data) -> [Event] {
        buffer.append(data)
        var events: [Event] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            var line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if line.last == 0x0D { line = line.dropLast() }
            if let event = Self.event(String(decoding: line, as: UTF8.self)) { events.append(event) }
        }
        return events
    }

    /// A last line without a newline.
    mutating func finish() -> [Event] {
        defer { buffer = Data() }
        return Self.event(String(decoding: buffer, as: UTF8.self)).map { [$0] } ?? []
    }

    static func event(_ line: String) -> Event? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Some servers send a plain JSON error body instead of an event.
        if trimmed.hasPrefix("{") { return .data(trimmed) }
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        return payload.isEmpty ? nil : .data(payload)
    }
}

/// One chat-completions stream chunk.
struct LocalChunk: Equatable {
    var text: String?
    var finishReason: String?
    var error: String?

    static func parse(_ payload: String) -> LocalChunk? {
        guard let json = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any] else { return nil }
        if let message = errorMessage(json) { return LocalChunk(error: message) }
        let choice = (json["choices"] as? [[String: Any]])?.first
        let delta = choice?["delta"] as? [String: Any] ?? choice?["message"] as? [String: Any]
        return LocalChunk(text: delta?["content"] as? String, finishReason: choice?["finish_reason"] as? String)
    }

    /// `{"error": {"message": …}}` (OpenAI, Ollama) or `{"error": "…"}` (LM Studio).
    static func errorMessage(_ json: [String: Any]) -> String? {
        if let error = json["error"] as? [String: Any] { return error["message"] as? String ?? "unknown error" }
        return json["error"] as? String
    }
}

enum LocalModelList {
    /// Model IDs from `/v1/models`, without embedding models (they can't write). Ollama sends `"data": null` when empty.
    static func parse(_ data: Data) -> [String]? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let entries = json["data"] as? [[String: Any]] ?? []
        return entries.compactMap { $0["id"] as? String }
            .filter { !$0.lowercased().contains("embed") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// "llama3.2:latest" → "llama3.2", "lmstudio-community/qwen2.5-7b" → "qwen2.5-7b".
    static func label(_ id: String) -> String {
        if let name = ChatGPTModelNames.name(for: id) { return name }
        var name = id.split(separator: "/").last.map(String.init) ?? id
        if name.hasSuffix(":latest") { name.removeLast(":latest".count) }
        return name.isEmpty ? id : name
    }
}

/// Small models need firmer format rules, and their output needs more forgiving parsing.
enum LocalPrompt {
    static func formatRules(takes: Int) -> String {
        var lines = ["", "Output format, follow it exactly:",
                     "- Start with the first version right away. No greeting, title, label or explanation."]
        if takes > 1 {
            lines.append("- Between versions, put a line containing only \(TakeSplitter.separator) and nothing else.")
            lines.append("- Don't number the versions or write \"Version 1\".")
        }
        lines.append("- Write exactly \(takes == 1 ? "1 version" : "\(takes) versions"), then stop. Nothing after the last one.")
        return lines.joined(separator: "\n")
    }
}

/// Splits a small model's output into takes, forgiving its usual quirks: reasoning in `<think>` tags, a
/// "Here are three versions:" preamble, "Version 2:" labels or numbering instead of `===`, `---` separators,
/// wrapping quotes, code fences, a closing remark, or more versions than asked for.
enum LocalTakeCleaner {
    static func split(_ raw: String, streaming: Bool, expected: Int) -> [String] {
        var lines: [String] = []
        for line in stripThinking(raw).components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { continue }
            if isSeparator(trimmed) {
                lines.append(TakeSplitter.separator)
            } else if let rest = labelRest(trimmed) {
                lines.append(TakeSplitter.separator)
                if !rest.isEmpty { lines.append(rest) }
            } else {
                lines.append(line)
            }
        }
        var takes = TakeSplitter.split(lines.joined(separator: "\n"), streaming: streaming)
        if takes.count < expected, expected > 1, let numbered = splitNumbered(takes.joined(separator: "\n\n"), expected: expected) {
            takes = numbered
        }
        if let first = takes.first {
            let lines = first.components(separatedBy: "\n")
            if lines.count > 1, isPreamble(lines[0], strict: true) {
                // "Here are two versions:" straight above the first take, with no blank line between.
                takes[0] = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if isPreamble(first), takes.count > 1 || streaming || first.hasSuffix(":") {
                takes.removeFirst()
            }
        }
        // Small models also introduce later versions ("Here is a more formal suggestion:"): drop those lines too,
        // except while the last one is still streaming in.
        takes = takes.enumerated().compactMap { index, take in
            guard index > 0, !(streaming && index == takes.count - 1) else { return take }
            let lines = take.components(separatedBy: "\n")
            guard isIntro(lines[0]) else { return take }
            let rest = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return rest.isEmpty ? nil : rest
        }
        if takes.count > max(expected, 1), let last = takes.last, isClosingRemark(last) { takes.removeLast() }
        takes = takes.map(unquote).filter { !$0.isEmpty }
        return Array(takes.prefix(max(expected, 1)))
    }

    /// Drops `<think>…</think>` blocks. An unclosed block (still thinking) hides everything after it.
    static func stripThinking(_ text: String) -> String {
        var result = text
        for tag in ["think", "thinking"] {
            while let open = result.range(of: "<\(tag)>") {
                if let close = result.range(of: "</\(tag)>", range: open.upperBound..<result.endIndex) {
                    result.removeSubrange(open.lowerBound..<close.upperBound)
                } else {
                    result.removeSubrange(open.lowerBound..<result.endIndex)
                }
            }
        }
        return result
    }

    /// `===`, `====`, `=== Take 2 ===`, `---`, `***`, `___`.
    static func isSeparator(_ line: String) -> Bool {
        if line.hasPrefix("===") { return true }
        guard line.count >= 3, let first = line.first, "-*_".contains(first) else { return false }
        return line.allSatisfy { $0 == first || $0 == " " }
    }

    private static let labelPattern = try! NSRegularExpression(
        pattern: #"^(?:#{1,6}\s*)?(?:\*\*|__)?\s*(?:take|version|option|variant|alternative|rewrite)\s*#?\d+\s*(?:\*\*|__)?\s*[:.)\-–]?\s*(?:\*\*|__)?\s*"#,
        options: [.caseInsensitive])

    /// For "Version 2: Thursday works.", the text after the label ("" for a label-only line); nil if it isn't a label.
    static func labelRest(_ line: String) -> String? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = labelPattern.firstMatch(in: line, range: range), let end = Range(match.range, in: line) else { return nil }
        let rest = String(line[end.upperBound...]).trimmingCharacters(in: .whitespaces)
        // "Version 2 of the plan is ready" is a sentence, not a label: a label ends in punctuation or the line.
        let labelText = line[end]
        let endsInMark = labelText.trimmingCharacters(in: .whitespaces).last.map { ":.)-–*_".contains($0) } ?? false
        return rest.isEmpty || endsInMark ? rest : nil
    }

    private static let numberPattern = try! NSRegularExpression(pattern: #"^\s*(\d+)[.)]\s+"#)

    /// "1. …\n\n2. …\n\n3. …" when numbered 1 to `expected` in order at the start of paragraphs.
    static func splitNumbered(_ text: String, expected: Int) -> [String]? {
        let lines = text.components(separatedBy: "\n")
        var starts: [(line: Int, markerEnd: String.Index)] = []
        for (index, line) in lines.enumerated() {
            guard index == 0 || lines[index - 1].trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = numberPattern.firstMatch(in: line, range: range),
                  let numberRange = Range(match.range(at: 1), in: line), let end = Range(match.range, in: line),
                  Int(line[numberRange]) == starts.count + 1 else { continue }
            starts.append((index, end.upperBound))
        }
        guard starts.count == expected else { return nil }
        // Anything before "1." is a preamble.
        var takes: [String] = []
        for (n, start) in starts.enumerated() {
            let endLine = n + 1 < starts.count ? starts[n + 1].line : lines.count
            var body = [String(lines[start.line][start.markerEnd...])]
            body += lines[(start.line + 1)..<endLine]
            takes.append(body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return takes
    }

    /// `strict`: only "Here are three versions:"-style lines, not any line ending in a colon (a take can open with one).
    static func isPreamble(_ take: String, strict: Bool = false) -> Bool {
        guard !take.contains("\n") else { return false }
        let lower = take.lowercased()
        if take.hasSuffix(":"), !strict { return true }
        return ["here are", "here is", "here's", "sure", "certainly", "of course", "okay, here"].contains { lower.hasPrefix($0) }
            && (lower.contains("version") || lower.contains("rewrite") || lower.contains("take") || lower.contains("option"))
    }

    /// A line that only introduces a version: "Here is a more formal suggestion, still friendly:".
    static func isIntro(_ line: String) -> Bool {
        let lower = line.trimmingCharacters(in: .whitespaces).lowercased()
        return lower.hasSuffix(":") && ["here are", "here is", "here's", "and here", "this one", "a more", "or, ", "or "].contains { lower.hasPrefix($0) }
    }

    static func isClosingRemark(_ take: String) -> Bool {
        guard !take.contains("\n") else { return false }
        let lower = take.lowercased()
        return ["let me know", "i hope", "feel free", "note:", "each version", "these versions"].contains { lower.hasPrefix($0) }
    }

    /// `"Thursday works."` → `Thursday works.` when the quotes wrap the whole take.
    static func unquote(_ take: String) -> String {
        for (open, close) in [("\"", "\""), ("“", "”")] where take.count >= 2 && take.hasPrefix(open) && take.hasSuffix(close) {
            let inner = take.dropFirst().dropLast()
            if !inner.contains(open), !inner.contains(close) { return inner.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return take
    }
}

/// Streams takes from a local OpenAI-compatible server.
struct LocalEngine: TakesEngine {
    var baseURL: String

    func run(_ request: EngineRequest, onUpdate: @escaping @Sendable ([String]) -> Void) async throws -> EngineResult {
        let server = LocalServerKind.displayName(baseURL)
        guard let url = LocalEndpoint.url(baseURL, "chat/completions") else {
            throw EngineError.failed(String(localized: "Takes only talks to model servers on this Mac (localhost). Change the address in Settings › Model."))
        }
        guard !request.model.isEmpty else { throw EngineError.failed(String(localized: "Pick a local model in Settings › Model.")) }

        let urlRequest = try Self.chatRequest(url: url, model: request.model,
                                              system: request.system + "\n" + LocalPrompt.formatRules(takes: request.takes),
                                              user: request.user, stream: true, maxTokens: 4000)
        let started = Date()
        let elapsedMs = { Int(Date().timeIntervalSince(started) * 1000) }

        let bytes: URLSession.AsyncBytes, response: URLResponse
        do {
            (bytes, response) = try await LocalEndpoint.session.bytes(for: urlRequest)
        } catch {
            throw Self.friendly(error, server: server, baseURL: baseURL)
        }
        guard let http = response as? HTTPURLResponse else { throw EngineError.failed(String(localized: "No answer from \(server).")) }
        if http.statusCode != 200 {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw Self.httpError(status: http.statusCode, body: data, server: server, model: request.model)
        }

        var parser = SSEParser()
        var text = ""
        var firstTextMs: Int?
        var line = Data()

        func handle(_ events: [SSEParser.Event]) throws {
            for event in events {
                guard case .data(let payload) = event, let chunk = LocalChunk.parse(payload) else { continue }
                if let error = chunk.error { throw EngineError.failed(String(localized: "\(server): \(error)")) }
                guard let piece = chunk.text, !piece.isEmpty else { continue }
                if firstTextMs == nil { firstTextMs = elapsedMs() }
                text += piece
                onUpdate(LocalTakeCleaner.split(text, streaming: true, expected: request.takes))
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
            throw Self.friendly(error, server: server, baseURL: baseURL)
        }

        let takes = LocalTakeCleaner.split(text, streaming: false, expected: request.takes)
        guard !takes.isEmpty else { throw EngineError.failed(String(localized: "The local model returned no takes. Try again, or pick another model.")) }
        return EngineResult(takes: takes, wallMs: elapsedMs(), firstTextMs: firstTextMs)
    }

    static func chatRequest(url: URL, model: String, system: String, user: String, stream: Bool, maxTokens: Int) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": model,
            "stream": stream,
            "max_tokens": maxTokens,
            "temperature": 0.7,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func httpError(status: Int, body: Data, server: String, model: String) -> EngineError {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let message = json.flatMap(LocalChunk.errorMessage) ?? String(decoding: body.prefix(300), as: UTF8.self)
        if status == 404, message.lowercased().contains("model") || message.isEmpty {
            let label = LocalModelList.label(model)
            return .failed(String(localized: "\(server) doesn't have the model “\(label)”. Pick an installed model in Settings › Model."))
        }
        if (300..<400).contains(status) {
            return .failed(String(localized: "\(server) tried to send Takes to another address. Takes only talks to servers on this Mac."))
        }
        let detail = message.isEmpty ? "HTTP \(status)" : message
        return .failed(String(localized: "\(server) error: \(detail)"))
    }

    static func friendly(_ error: Error, server: String, baseURL: String) -> Error {
        guard let urlError = error as? URLError else { return error }
        let place = URL(string: baseURL).map { "\($0.host ?? "localhost"):\($0.port.map(String.init) ?? "")" } ?? baseURL
        switch urlError.code {
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
            return EngineError.failed(String(localized: "\(server) isn't running at \(place). Open it and try again, or pick another engine in Settings › Model."))
        case .timedOut:
            return EngineError.failed(String(localized: "The local model took too long to answer. Big models are slow the first time while they load; try again or pick a smaller one."))
        case .cancelled:
            return CancellationError()
        default:
            return EngineError.failed(String(localized: "Couldn't reach \(server): \(urlError.localizedDescription)"))
        }
    }

    /// Installed models, or nil when nothing answers at `baseURL`.
    static func models(at baseURL: String, timeout: TimeInterval = 1.5) async -> [String]? {
        guard let url = LocalEndpoint.url(baseURL, "models") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        guard let (data, response) = try? await LocalEndpoint.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return LocalModelList.parse(data) ?? []
    }

    /// A tiny request, to show that the model answers and how fast.
    static func test(baseURL: String, model: String) async -> Result<Int, Error> {
        let server = LocalServerKind.displayName(baseURL)
        guard let url = LocalEndpoint.url(baseURL, "chat/completions") else {
            return .failure(EngineError.failed(String(localized: "Only addresses on this Mac work.")))
        }
        let started = Date()
        do {
            let request = try chatRequest(url: url, model: model, system: "Reply with the single word OK.", user: "Ready?",
                                          stream: false, maxTokens: 8)
            let (data, response) = try await LocalEndpoint.session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { return .failure(httpError(status: status, body: data, server: server, model: model)) }
            guard let text = String(data: data, encoding: .utf8).flatMap(LocalChunk.parse)?.text, !text.isEmpty else {
                return .failure(EngineError.failed(String(localized: "\(server) answered, but with no text.")))
            }
            return .success(Int(Date().timeIntervalSince(started) * 1000))
        } catch {
            return .failure(friendly(error, server: server, baseURL: baseURL))
        }
    }
}

// MARK: - Detection

/// What's running on this Mac, for Settings › Model, the panel's Model menu and setup.
@MainActor
final class LocalModels: ObservableObject {
    static let shared = LocalModels()

    struct Server: Equatable {
        var baseURL: String
        /// nil: nothing answers there.
        var models: [String]?
        var name: String { LocalServerKind.displayName(baseURL) }
        var running: Bool { models != nil }
    }

    @Published var servers: [Server] = []
    @Published var checking = false
    @Published var checked = false
    /// Snapshots set the state by hand and keep it.
    var frozen = false

    /// The configured server first, then the known ones.
    func server(at baseURL: String) -> Server? { servers.first { $0.baseURL == baseURL } }
    var running: [Server] { servers.filter(\.running) }

    func refresh() async {
        guard !frozen else { return }
        checking = true
        let configured = Store.shared.settings.localBaseURL
        var addresses = LocalServerKind.allCases.map(\.defaultBaseURL)
        if !addresses.contains(configured) { addresses.insert(configured, at: 0) }
        let found = await withTaskGroup(of: (Int, Server).self) { group in
            for (index, address) in addresses.enumerated() {
                group.addTask { (index, Server(baseURL: address, models: await LocalEngine.models(at: address))) }
            }
            var results: [(Int, Server)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
        guard !frozen else { return }
        servers = found
        checking = false
        checked = true
        autoPick()
    }

    /// With no model picked yet, pick the first installed one (on another running server if this one is off).
    private func autoPick() {
        let settings = Store.shared.settings
        guard settings.localModel.isEmpty else { return }
        let preferred = server(at: settings.localBaseURL)
        guard let source = preferred?.models?.isEmpty == false ? preferred : running.first(where: { $0.models?.isEmpty == false }),
              let first = source.models?.first else { return }
        Store.shared.settings.localBaseURL = source.baseURL
        Store.shared.settings.localModel = first
    }

    /// The models to offer for `baseURL`, always including the picked one.
    func modelOptions(at baseURL: String, picked: String) -> [String] {
        var models = server(at: baseURL)?.models ?? []
        if !picked.isEmpty, !models.contains(picked) { models.insert(picked, at: 0) }
        return models
    }
}

// MARK: - Hooks used by the rest of the app

extension AppSettings {
    /// With a one-model engine (local, other provider, ChatGPT), the model every preset runs on; empty when none is picked yet.
    var oneModel: String {
        switch engine {
        case .local: localModel
        case .provider: providerModel
        case .chatGPT: chatGPTModel
        case .claudeCode, .apiKey: ""
        }
    }
    /// "on this Mac", "via OpenAI", "with your ChatGPT plan": where the one model runs, for labels.
    var oneModelPlace: String {
        switch engine {
        case .local: String(localized: "on this Mac")
        case .provider: String(localized: "via \(Provider.current(self).name)")
        case .chatGPT: String(localized: "with your ChatGPT plan")
        case .claudeCode, .apiKey: ""
        }
    }
    /// The model a preset runs on with the current engine.
    func runModel(for preset: Preset) -> String { engine.usesOneModel ? oneModel : preset.model }
    /// The model for small helper calls (tone notes): Haiku with Claude, the picked model with a one-model engine.
    var quickModel: String { engine.usesOneModel ? oneModel : Models.haiku }
}

extension Models {
    /// Claude models by name, other models by their short ID.
    static func displayLabel(_ id: String) -> String {
        all.contains { $0.id == id } ? label(id) : id.isEmpty ? String(localized: "No model") : LocalModelList.label(id)
    }
}

extension Preset {
    /// The summary for the engine in use, so it never names a model that won't run.
    func summary(for settings: AppSettings) -> String {
        guard settings.engine.usesOneModel else { return summary }
        let model = Models.displayLabel(settings.oneModel), place = settings.oneModelPlace, size = length.inlineLabel
        return takes == 1
            ? String(localized: "1 take · \(model) \(place) · \(size)")
            : String(localized: "\(takes) takes · \(model) \(place) · \(size)")
    }
}

extension PanelModel {
    var usesOneModel: Bool { store.settings.engine.usesOneModel }

    var modelOptions: [(value: String, title: String)] {
        let models: [String]
        switch store.settings.engine {
        case .local: models = LocalModels.shared.modelOptions(at: store.settings.localBaseURL, picked: modelID)
        case .provider: models = ProviderModels.shared.modelOptions(picked: modelID)
        case .chatGPT: models = ChatGPTModels.shared.modelOptions(picked: modelID)
        case .claudeCode, .apiKey: return Models.all.map { (value: $0.id, title: $0.label) }
        }
        return models.isEmpty ? [(value: modelID, title: String(localized: "No model"))] : models.map { (value: $0, title: LocalModelList.label($0)) }
    }

    /// "3 takes · Sonnet 5.5 · Low", or "3 takes · llama3.2 on this Mac".
    var runLabel: String {
        let takes = takeCount == 1 ? String(localized: "1 take") : String(localized: "\(takeCount) takes")
        return usesOneModel ? "\(takes) · \(Models.displayLabel(modelID)) \(store.settings.oneModelPlace)"
            : "\(takes) · \(Models.label(modelID)) · \(effort.capitalized)"
    }
}

extension SetupMonitor {
    /// Ready when the server answers and has the picked model.
    static func localEngineStatus() async -> EngineStatus {
        let settings = Store.shared.settings
        let server = LocalServerKind.displayName(settings.localBaseURL)
        guard let models = await LocalEngine.models(at: settings.localBaseURL) else {
            return .problem(String(localized: "\(server) isn't running"))
        }
        if settings.localModel.isEmpty { return .problem(models.isEmpty ? String(localized: "\(server) has no models yet") : String(localized: "No local model picked")) }
        let label = LocalModelList.label(settings.localModel)
        guard models.contains(settings.localModel) else { return .problem(String(localized: "\(label) isn't installed")) }
        return .ready("\(server) · \(LocalModelList.label(settings.localModel))")
    }
}
