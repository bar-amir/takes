import AppKit
import XCTest
@testable import Takes

/// Signs in with a real ChatGPT account in the browser, lists the plan's models and writes one short take, then revokes
/// the session. Tokens stay in memory, never in the keychain. Skipped unless `TAKES_LIVE_CHATGPT=1`:
/// `TAKES_LIVE_CHATGPT=1 swift test --filter ChatGPTLiveTests`. Someone has to finish the sign-in in the browser.
final class ChatGPTLiveTests: XCTestCase {
    func testSignInListModelsAndWrite() async throws {
        guard ProcessInfo.processInfo.environment["TAKES_LIVE_CHATGPT"] == "1" else { throw XCTSkip("Set TAKES_LIVE_CHATGPT=1") }
        let store = ChatGPTMemoryStore()
        let started = Date()
        let credentials = try await ChatGPTSignIn.signIn(store: store, client: ChatGPTAuthClient(), hostID: ChatGPTHost.id()) { url in
            print("LIVE opening the browser for sign-in")
            NSWorkspace.shared.open(url)
        }
        print("LIVE signed in after \(Int(Date().timeIntervalSince(started))) s; client \(credentials.clientID.prefix(7))…; sharing \(credentials.sharing); scopes \(credentials.scopes)")
        XCTAssertTrue(credentials.clientID.hasPrefix("oaiapp_"))
        do {
            try await write(store: store, sharing: credentials.sharing)
        } catch {
            XCTFail("LIVE failed: \(error.localizedDescription)")
        }
        if let refresh = store.load()?.refreshToken {
            print("LIVE revoked: \(await ChatGPTSignIn.revoke(refresh, clientID: credentials.clientID))")
        }
    }

    private func write(store: ChatGPTMemoryStore, sharing: Bool) async throws {
        guard sharing else { return XCTFail("plan usage wasn't granted") }

        let engine = ChatGPTEngine(tokens: ChatGPTTokens(store: store))
        guard case .success(let models) = await engine.models() else { return XCTFail("no model list") }
        print("LIVE models: \(models.map { "\($0.slug) (\($0.displayName))" })")
        let model = try XCTUnwrap(models.first?.slug)
        let preset = Store.defaultPresets[0]
        let request = EngineRequest(system: PromptBuilder.system(preset: preset, takes: 2, rules: []),
                                    user: PromptBuilder.user(draft: "ya thursday works but i need the specs by wed eod", mode: .fresh, takes: 2),
                                    takes: 2, model: model, effort: "low")
        let result = try await engine.run(request) { _ in }
        print("LIVE \(model): \(result.wallMs) ms, first words \(result.firstTextMs ?? -1) ms")
        for (index, take) in result.takes.enumerated() { print("LIVE take \(index + 1): \(take)") }
        XCTAssertEqual(result.takes.count, 2)
    }
}
