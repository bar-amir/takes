import XCTest
@testable import Takes

/// Proofreads real drafts with Claude Code and Haiku. Skipped unless `TAKES_LIVE_CLAUDE=1`.
final class ProofreadLiveTests: XCTestCase {
    func testProofreadFixesSlipsAndKeepsShorthand() async throws {
        guard ProcessInfo.processInfo.environment["TAKES_LIVE_CLAUDE"] == "1" else { throw XCTSkip("Set TAKES_LIVE_CLAUDE=1") }
        let preset = Preset.proofread
        let drafts = ["hey can u send me the deck before fri, need to go over it w legal first and they're slow",
                      "i think teh specs are due wed, can you chek with dana if thats still ok",
                      "Thanks, that works for me. I'll send the notes after the call."]
        for draft in drafts {
            let request = EngineRequest(system: PromptBuilder.system(preset: preset, takes: 1, rules: []),
                                        user: PromptBuilder.user(draft: draft, mode: .fresh, takes: 1),
                                        takes: 1, model: preset.model, effort: preset.effort)
            let take = try await ClaudeCodeEngine().run(request) { _ in }.takes.first ?? ""
            print("LIVE \(WordDiff.fixes(from: draft, to: take).count) fixes: \(draft)\n  -> \(take)")
        }
    }
}
