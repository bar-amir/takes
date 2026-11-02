import XCTest
@testable import Takes

/// Writes real takes with a model in Ollama. Skipped unless `TAKES_LIVE_LOCAL` names an installed model,
/// for example `TAKES_LIVE_LOCAL=llama3.2 swift test --filter LocalLiveTests`.
final class LocalLiveTests: XCTestCase {
    func testLocalModelWritesThreeTakes() async throws {
        guard let model = ProcessInfo.processInfo.environment["TAKES_LIVE_LOCAL"] else { throw XCTSkip("Set TAKES_LIVE_LOCAL") }
        let preset = Store.defaultPresets[0]
        let request = EngineRequest(system: PromptBuilder.system(preset: preset, takes: 3, rules: []),
                                    user: PromptBuilder.user(draft: "ya thursday works but i need the specs by wed eod", mode: .fresh, takes: 3),
                                    takes: 3, model: model, effort: "low")
        let result = try await LocalEngine(baseURL: LocalServerKind.ollama.defaultBaseURL).run(request) { _ in }
        print("LIVE \(result.wallMs) ms, first words \(result.firstTextMs ?? -1) ms")
        for (index, take) in result.takes.enumerated() { print("LIVE take \(index + 1): \(take)") }
        XCTAssertEqual(result.takes.count, 3)
        XCTAssertTrue(result.takes.allSatisfy { !$0.isEmpty && !$0.contains("===") })
    }
}
