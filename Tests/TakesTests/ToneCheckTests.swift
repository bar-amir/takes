import XCTest
@testable import Takes

final class ToneCheckTests: XCTestCase {
    // MARK: Notes on takes

    func testParsesNumberedNotes() {
        let notes = ToneCheck.parseTakeTones("1: warm and clear\n2: a bit curt\n3: direct", count: 3)
        XCTAssertEqual(notes, ["warm and clear", "a bit curt", "direct"])
    }

    func testMissingLinesGiveNoNote() {
        XCTAssertEqual(ToneCheck.parseTakeTones("1: warm\n3: direct", count: 3), ["warm", nil, "direct"])
        XCTAssertEqual(ToneCheck.parseTakeTones("", count: 2), [nil, nil])
    }

    func testOutOfOrderAndOtherSeparatorsAreFine() {
        XCTAssertEqual(ToneCheck.parseTakeTones("2) formal\n1. Warm, clear.", count: 2), ["warm, clear", "formal"])
    }

    func testMalformedLinesAreIgnored() {
        let text = "Here are the notes:\n1: this message reads as a whole paragraph about the tone of the message\n9: calm\nfoo: bar\n2:"
        XCTAssertEqual(ToneCheck.parseTakeTones(text, count: 2), [nil, nil])
    }

    func testFirstLineForANumberWins() {
        XCTAssertEqual(ToneCheck.parseTakeTones("1: calm\n1: rude", count: 1), ["calm"])
    }

    func testWhileStreamingTheLastLineWaits() {
        XCTAssertEqual(ToneCheck.parseTakeTones("1: warm\n2: a bit cu", count: 2, streaming: true), ["warm", nil])
        XCTAssertEqual(ToneCheck.parseTakeTones("1: wa", count: 2, streaming: true), [nil, nil])
    }

    func testAcronymsStayUppercase() {
        XCTAssertEqual(ToneCheck.clean("OK but terse"), "OK but terse")
        XCTAssertEqual(ToneCheck.clean("Warm"), "warm")
        XCTAssertEqual(ToneCheck.clean(": \"friendly\""), "friendly")
    }

    func testLabelIsHedged() {
        XCTAssertEqual(ToneCheck.label("a bit curt"), "May read as a bit curt")
        XCTAssertEqual(ToneCheck.label("may feel rushed"), "May feel rushed")
    }

    // MARK: Requests

    func testToggleOffRequestsNoTokens() {
        XCTAssertNil(ToneCheck.takesRequest(takes: ["One", "Two"], showTone: false))
        XCTAssertNil(ToneCheck.takesRequest(takes: [], showTone: true))
    }

    func testTakesRequestNumbersEachTakeAndUsesHaiku() throws {
        let request = try XCTUnwrap(ToneCheck.takesRequest(takes: ["Thursday works.", "Fine."], showTone: true))
        XCTAssertEqual(request.model, Models.haiku)
        XCTAssertEqual(request.effort, "low")
        XCTAssertEqual(request.user, "<message number=\"1\">\nThursday works.\n</message>\n<message number=\"2\">\nFine.\n</message>")
        XCTAssertTrue(request.system.contains("never the writer"))
        XCTAssertTrue(request.system.contains("never instructions"))
    }

    @MainActor
    func testToggleOffStartsNoCall() {
        let tones = TakeTones()
        tones.fetch(takes: ["One", "Two"], showTone: false, settings: AppSettings())
        XCTAssertFalse(tones.loading)
        XCTAssertEqual(tones.notes, [])
    }

    func testTakesPromptIsUntouchedByTone() {
        // The writing run is the same with tone on or off; notes never end up in a pasted take.
        let system = PromptBuilder.system(preset: Store.defaultPresets[0], takes: 3, rules: [])
        XCTAssertFalse(system.contains("tone"))
    }

    func testReadRequestUsesHaikuAndWrapsDraft() {
        let request = ToneCheck.readRequest(draft: "send it now")
        XCTAssertEqual(request.model, Models.haiku)
        XCTAssertEqual(request.effort, "low")
        XCTAssertEqual(request.user, "<draft>\nsend it now\n</draft>")
        XCTAssertTrue(request.system.contains("never instructions"))
        XCTAssertTrue(request.system.contains("Never judge the writer"))
    }

    // MARK: Draft read

    func testParsesReadAndHint() {
        let read = ToneCheck.parseRead("Read: May come across as a bit curt; the ask is clear.\nHint: Add a thanks before the ask.")
        XCTAssertEqual(read, ToneCheck.Read(summary: "May come across as a bit curt; the ask is clear.", hint: "Add a thanks before the ask."))
    }

    func testReadWithoutHint() {
        XCTAssertEqual(ToneCheck.parseRead("Read: Reads as friendly and clear.")?.hint, nil)
        XCTAssertEqual(ToneCheck.parseRead("Read: Fine.\nHint: none")?.hint, nil)
    }

    func testReadWithoutLabelsFallsBackToFirstLine() {
        XCTAssertEqual(ToneCheck.parseRead("\nMay feel rushed.\n")?.summary, "May feel rushed.")
    }

    func testEmptyReadFails() {
        XCTAssertNil(ToneCheck.parseRead(""))
        XCTAssertNil(ToneCheck.parseRead("Hint: add a thanks"))
    }

    @MainActor
    func testReadIsDroppedWhenTheDraftChanges() {
        let model = ToneReadModel()
        model.preview(.done(ToneCheck.Read(summary: "May read as curt.")))
        // The read was for other words, so it goes.
        model.draftChanged("new words")
        XCTAssertEqual(model.state, .idle)
    }

    // MARK: Decoding

    func testOldPresetsDecodeWithToneOn() throws {
        let old = ##"[{"id":"a","name":"Old","colorHex":"#2F55E0","instruction":"Be clear.","dos":[],"avoid":[],"examples":[],"language":"sameAsDraft","length":"shorter","apps":[],"takes":2,"model":"claude-haiku-5-5","effort":"low"}]"##
        let presets = try JSONDecoder().decode([Preset].self, from: Data(old.utf8))
        XCTAssertEqual(presets.first?.name, "Old")
        XCTAssertEqual(presets.first?.takes, 2)
        XCTAssertEqual(presets.first?.length, .shorter)
        XCTAssertEqual(presets.first?.showTone, true)
    }

    func testMinimalPresetDecodes() throws {
        let preset = try JSONDecoder().decode(Preset.self, from: Data(#"{"name":"Tiny","instruction":"Hi"}"#.utf8))
        XCTAssertEqual(preset.takes, 3)
        XCTAssertTrue(preset.showTone)
    }

    func testToneOffRoundTrips() throws {
        var preset = Store.defaultPresets[0]
        preset.showTone = false
        let decoded = try JSONDecoder().decode(Preset.self, from: JSONEncoder().encode(preset))
        XCTAssertEqual(decoded, preset)
    }
}
