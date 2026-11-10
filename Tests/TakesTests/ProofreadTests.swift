import XCTest
@testable import Takes

final class ProofreadTests: XCTestCase {
    // MARK: Prompt

    func testMinimalEditsAddsTheRules() {
        let system = PromptBuilder.system(preset: .proofread, takes: 1, rules: [])
        for rule in Proofread.rules { XCTAssertTrue(system.contains(rule), rule) }
        XCTAssertTrue(system.contains("return the draft exactly as written"))
    }

    func testRegularPresetHasNoMinimalEditRules() {
        var preset = Preset.proofread
        preset.isMinimalEdits = false
        let system = PromptBuilder.system(preset: preset, takes: 1, rules: [])
        XCTAssertFalse(system.contains("Minimal edits:"))
    }

    func testMinimalEditsDropsLengthAndVarietyAsks() {
        var preset = Preset.proofread
        preset.length = .shorter
        let system = PromptBuilder.system(preset: preset, takes: 3, rules: [])
        XCTAssertFalse(system.contains("Length:"))
        XCTAssertFalse(system.contains("meaningfully different"))
        XCTAssertTrue(system.contains("They may be identical"))
        XCTAssertTrue(system.contains(TakeSplitter.separator))

        preset.isMinimalEdits = false
        let regular = PromptBuilder.system(preset: preset, takes: 3, rules: [])
        XCTAssertTrue(regular.contains("Length: noticeably shorter"))
        XCTAssertTrue(regular.contains("meaningfully different"))
    }

    func testVoiceRulesStillApply() {
        let system = PromptBuilder.system(preset: .proofread, takes: 1, rules: [VoiceRule(text: "Spell Takes with a capital T")])
        XCTAssertTrue(system.contains("- Spell Takes with a capital T"))
    }

    // MARK: Preset and decoding

    func testBuiltInPreset() {
        let preset = Preset.proofread
        XCTAssertTrue(preset.isMinimalEdits)
        XCTAssertEqual(preset.takes, 1)
        XCTAssertEqual(preset.model, Models.haiku)
        XCTAssertEqual(preset.effort, "low")
        XCTAssertEqual(preset.id, Preset.proofread.id, "fixed id, so the gallery can spot it")
    }

    func testOldPresetsDecodeWithMinimalEditsOff() throws {
        let old = ##"[{"id":"a","name":"Slack","colorHex":"#2F55E0","instruction":"Be clear.","dos":[],"avoid":[],"examples":[],"language":"sameAsDraft","length":"sameOrShorter","apps":[],"takes":3,"model":"claude-sonnet-5-5","effort":"low"}]"##
        let presets = try JSONDecoder().decode([Preset].self, from: Data(old.utf8))
        XCTAssertEqual(presets.first?.name, "Slack")
        XCTAssertNil(presets.first?.minimalEdits)
        XCTAssertEqual(presets.first?.isMinimalEdits, false)
    }

    func testMinimalEditsRoundTrips() throws {
        let decoded = try JSONDecoder().decode(Preset.self, from: JSONEncoder().encode(Preset.proofread))
        XCTAssertTrue(decoded.isMinimalEdits)
    }

    // MARK: Upgrade

    private var legacy: Preset {
        Preset(name: Proofread.legacyName, colorHex: "#1D6B4F", instruction: Proofread.legacyInstruction,
               avoid: ["Rewording anything that is already correct"], takes: 1)
    }

    func testLegacyProofreadPresetIsUpgraded() {
        var old = legacy
        old.apps = [AppRef(bundleID: "com.apple.mail", name: "Mail")]
        let new = Proofread.upgraded([old])[0]
        XCTAssertEqual(new.id, old.id)
        XCTAssertEqual(new.name, "Proofread")
        XCTAssertTrue(new.isMinimalEdits)
        XCTAssertEqual(new.instruction, Preset.proofread.instruction)
        XCTAssertEqual(new.model, Models.haiku)
        XCTAssertEqual(new.apps, old.apps)
    }

    func testUpgradeKeepsWhatTheUserChanged() {
        var renamed = legacy
        renamed.name = "My proofread"
        renamed.model = Models.opus
        let new = Proofread.upgraded([renamed])[0]
        XCTAssertEqual(new.name, "My proofread")
        XCTAssertEqual(new.model, Models.opus)
        XCTAssertTrue(new.isMinimalEdits)

        var edited = legacy
        edited.instruction = "Fix typos only."
        XCTAssertEqual(Proofread.upgraded([edited])[0], edited)
    }

    func testUpgradeRunsOnceAndRespectsTurningItOff() {
        let once = Proofread.upgraded([legacy])
        XCTAssertEqual(Proofread.upgraded(once), once)

        var off = legacy
        off.isMinimalEdits = false
        XCTAssertEqual(Proofread.upgraded([off])[0], off)
    }

    func testFreshInstallsGetAMinimalEditsPreset() {
        XCTAssertTrue(Proofread.upgraded(Store.defaultPresets).contains { $0.isMinimalEdits && $0.name == "Proofread" })
    }

    // MARK: Fixes

    func testNothingToFix() {
        let draft = "Thursday works for me.\nSee you then"
        XCTAssertTrue(Proofread.nothingToFix(draft: draft, takes: [draft]))
        XCTAssertTrue(Proofread.nothingToFix(draft: draft, takes: [draft + "\n"]), "a trailing line break isn't a fix")
        XCTAssertFalse(Proofread.nothingToFix(draft: draft, takes: ["Thursday  works for me.\nSee you then"]), "spacing is pasted too")
        XCTAssertFalse(Proofread.nothingToFix(draft: draft, takes: ["Thursday works for me.\nSee you then."]))
        XCTAssertFalse(Proofread.nothingToFix(draft: draft, takes: [draft, "thursday works for me.\nSee you then"]))
        XCTAssertFalse(Proofread.nothingToFix(draft: draft, takes: []))
    }

    func testFixesAreCountedPerRun() {
        let fixes = WordDiff.fixes(from: "i think teh specs are due wed", to: "I think the specs are due Wed.")
        XCTAssertEqual(fixes, [WordDiff.Fix(removed: "i", added: "I"), WordDiff.Fix(removed: "teh", added: "the"),
                               WordDiff.Fix(removed: "wed", added: "Wed.")])
        XCTAssertEqual(Proofread.fixLabel(fixes.count), "3 fixes")
        XCTAssertEqual(Proofread.fixLabel(1), "1 fix")
        XCTAssertEqual(Proofread.fixLabel(0), "No fixes")
    }

    @MainActor
    func testOptionFlipsChangesBothWays() {
        let model = PanelModel()
        model.takes = ["One.", "Two."]
        model.changesShown = [0, 1]
        XCTAssertTrue(model.showsChanges(0))
        model.optionHeld = true
        XCTAssertFalse(model.showsChanges(0), "⌥ shows a proofread take without its changes")

        model.changesShown = []
        XCTAssertTrue(model.showsChanges(1), "⌥ shows a regular take's changes")
        model.optionHeld = false
        XCTAssertFalse(model.showsChanges(1))

        model.optionHeld = true
        model.running = true
        XCTAssertFalse(model.showsChanges(1), "a take still being written never shows changes")
    }

    func testSpokenDescription() {
        let spoken = WordDiff.spoken(from: "i think teh specs", to: "I think the specs, ok")
        XCTAssertEqual(spoken, "3 changes: capitalised I; teh changed to the; added , ok. Result: I think the specs, ok")
        XCTAssertEqual(WordDiff.spoken(from: "Hi", to: "Hi"), "No changes. Hi")
    }
}
