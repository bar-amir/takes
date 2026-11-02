import XCTest
@testable import Takes

/// Rewrites a casual lowercase draft with real presets. Skipped unless `TAKES_LIVE_CLAUDE=1`.
final class RewriteLiveTests: XCTestCase {
    func testRewritesStartWithCapitals() async throws {
        guard ProcessInfo.processInfo.environment["TAKES_LIVE_CLAUDE"] == "1" else { throw XCTSkip("Set TAKES_LIVE_CLAUDE=1") }
        let draft = "hey can u send me the deck before fri, need to go over it w legal first and they're slow"
        for preset in [PresetGallery.slack, PresetGallery.friendlier] {
            let request = EngineRequest(system: PromptBuilder.system(preset: preset, takes: 3, rules: []),
                                        user: PromptBuilder.user(draft: draft, mode: .fresh, takes: 3),
                                        takes: 3, model: Models.haiku, effort: "low")
            let takes = try await ClaudeCodeEngine().run(request) { _ in }.takes
            for take in takes { print("LIVE \(preset.name): \(take)") }
            XCTAssertTrue(takes.allSatisfy { $0.first?.isUppercase == true }, preset.name)
        }
    }
}
