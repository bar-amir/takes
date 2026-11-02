import XCTest
@testable import Takes

/// Stands in for the microphone and the recognizer.
final class FakeSpeech: SpeechBackend {
    var mic = Dictation.Access.notAsked
    var speech = Dictation.Access.notAsked
    var grantMic = true
    var grantSpeech = true
    var startError: Error?
    var started = 0, stopped = 0, cancelled = 0
    var requestedMic = 0, requestedSpeech = 0
    var onText: ((String, Bool) -> Void)?
    var onEnd: ((Error?) -> Void)?
    var locale: Locale?

    func access() -> (mic: Dictation.Access, speech: Dictation.Access) { (mic, speech) }
    func requestMicrophone() async -> Bool { requestedMic += 1; mic = grantMic ? .allowed : .denied; return grantMic }
    func requestSpeech() async -> Bool { requestedSpeech += 1; speech = grantSpeech ? .allowed : .denied; return grantSpeech }
    func start(locale: Locale, onText: @escaping (String, Bool) -> Void, onLevel: @escaping (Float) -> Void,
               onEnd: @escaping (Error?) -> Void) throws {
        if let startError { throw startError }
        started += 1
        self.locale = locale
        self.onText = onText
        self.onEnd = onEnd
    }
    func stop() { stopped += 1 }
    func cancel() { cancelled += 1 }
}

@MainActor
final class DictationTests: XCTestCase {
    private func dictation(_ fake: FakeSpeech, language: String = "en-US") -> Dictation {
        let dictation = Dictation(backend: fake, language: { language })
        dictation.stopGrace = .milliseconds(50)
        return dictation
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "timed out", file: file, line: line)
    }

    private func allowed() -> FakeSpeech {
        let fake = FakeSpeech()
        fake.mic = .allowed
        fake.speech = .allowed
        return fake
    }

    // MARK: Insertion at the caret

    func testAppendsAtTheEndWithASpace() {
        let insertion = DictationInsertion(text: "Thursday works", selection: NSRange(location: 14, length: 0))
        XCTAssertEqual(insertion.apply("for me").text, "Thursday works for me")
        XCTAssertEqual(insertion.apply("for me").caret, 21)
    }

    func testInsertsAtTheCaretInTheMiddle() {
        let text = "I need specs by Wednesday"
        let insertion = DictationInsertion(text: text, selection: NSRange(location: 7, length: 0)) // before "specs"
        let result = insertion.apply("the final")
        XCTAssertEqual(result.text, "I need the final specs by Wednesday")
        XCTAssertEqual(result.caret, ("I need the final" as NSString).length)
    }

    func testEachPartialReplacesTheLastOne() {
        let insertion = DictationInsertion(text: "Hi.", selection: NSRange(location: 3, length: 0))
        _ = insertion.apply("Can")
        _ = insertion.apply("Can you")
        XCTAssertEqual(insertion.apply("Can you send it?").text, "Hi. Can you send it?")
    }

    func testReplacesTheSelection() {
        let insertion = DictationInsertion(text: "Meet on Monday at noon", selection: NSRange(location: 8, length: 6))
        XCTAssertEqual(insertion.apply("Thursday").text, "Meet on Thursday at noon")
    }

    func testNoSpaceBeforePunctuationOrInAnEmptyDraft() {
        XCTAssertEqual(DictationInsertion(text: "", selection: NSRange(location: 0, length: 0)).apply("Hello").text, "Hello")
        let beforeComma = DictationInsertion(text: "Thanks, all", selection: NSRange(location: 6, length: 0))
        XCTAssertEqual(beforeComma.apply("so much").text, "Thanks so much, all")
        let inBracket = DictationInsertion(text: "(", selection: NSRange(location: 1, length: 0))
        XCTAssertEqual(inBracket.apply("aside").text, "(aside")
    }

    func testEmptyTranscriptLeavesTheDraftAlone() {
        let insertion = DictationInsertion(text: "Keep this", selection: NSRange(location: 5, length: 4))
        XCTAssertEqual(insertion.apply("  ").text, "Keep this")
    }

    func testOutOfRangeSelectionIsClamped() {
        let insertion = DictationInsertion(text: "Hi", selection: NSRange(location: 99, length: 5))
        XCTAssertEqual(insertion.apply("there").text, "Hi there")
    }

    func testCaretCountsUTF16() {
        let insertion = DictationInsertion(text: "👋", selection: NSRange(location: 2, length: 0))
        let result = insertion.apply("שלום")
        XCTAssertEqual(result.text, "👋 שלום")
        XCTAssertEqual(result.caret, ("👋 שלום" as NSString).length)
    }

    // MARK: Permission state

    func testPermissionState() {
        XCTAssertEqual(Dictation.permissionState((.allowed, .allowed)), .allowed)
        XCTAssertEqual(Dictation.permissionState((.notAsked, .allowed)), .notAsked)
        XCTAssertEqual(Dictation.permissionState((.allowed, .notAsked)), .notAsked)
        XCTAssertEqual(Dictation.permissionState((.denied, .notAsked)), .denied(.microphone))
        XCTAssertEqual(Dictation.permissionState((.allowed, .denied)), .denied(.speech))
    }

    // MARK: State machine

    func testIdleToRecordingToStoppingToIdle() async {
        let fake = allowed()
        let dictation = dictation(fake, language: "he-IL")
        var heard: [String] = []
        dictation.onTranscript = { heard.append($0) }
        dictation.toggle()
        XCTAssertEqual(dictation.state, .recording)
        XCTAssertEqual(fake.locale?.identifier, "he-IL")

        fake.onText?("Hello", false)
        await waitUntil { heard == ["Hello"] }
        dictation.toggle()
        XCTAssertEqual(dictation.state, .stopping)
        XCTAssertEqual(fake.stopped, 1)
        fake.onText?("Hello there.", true)
        await waitUntil { dictation.state == .idle }
        XCTAssertEqual(heard, ["Hello", "Hello there."])
    }

    func testStoppingEndsWhenTheFinalWordsNeverCome() async {
        let dictation = dictation(allowed())
        dictation.toggle()
        dictation.stop()
        XCTAssertEqual(dictation.state, .stopping)
        await waitUntil { dictation.state == .idle }
    }

    func testFirstUseExplainsThenAsksMacOS() async {
        let fake = FakeSpeech()
        let dictation = dictation(fake)
        dictation.toggle()
        XCTAssertEqual(dictation.state, .asking(explained: false))
        XCTAssertEqual(fake.requestedMic, 0, "macOS isn't asked before the user continues")
        dictation.continueAsking()
        XCTAssertEqual(dictation.state, .asking(explained: true))
        await waitUntil { dictation.state == .recording }
        XCTAssertEqual(fake.requestedMic, 1)
        XCTAssertEqual(fake.requestedSpeech, 1)
    }

    func testNotNowGoesBackToIdleWithoutAsking() {
        let fake = FakeSpeech()
        let dictation = dictation(fake)
        dictation.toggle()
        XCTAssertTrue(dictation.handleEscape())
        XCTAssertEqual(dictation.state, .idle)
        XCTAssertEqual(fake.requestedMic, 0)
    }

    func testMicrophoneRefusedInTheDialog() async {
        let fake = FakeSpeech()
        fake.grantMic = false
        let dictation = dictation(fake)
        dictation.toggle()
        dictation.continueAsking()
        await waitUntil { dictation.state == .denied(.microphone) }
        XCTAssertEqual(fake.requestedSpeech, 0, "speech isn't asked once the microphone is refused")
    }

    func testSpeechRefusedInTheDialog() async {
        let fake = FakeSpeech()
        fake.grantSpeech = false
        let dictation = dictation(fake)
        dictation.toggle()
        dictation.continueAsking()
        await waitUntil { dictation.state == .denied(.speech) }
    }

    func testAlreadyDeniedShowsTheWayToSettings() {
        let fake = FakeSpeech()
        fake.mic = .denied
        let dictation = dictation(fake)
        dictation.toggle()
        XCTAssertEqual(dictation.state, .denied(.microphone))
        XCTAssertTrue(dictation.handleEscape())
        XCTAssertEqual(dictation.state, .idle)
    }

    func testDeniedNoteClearsWhenAccessIsTurnedOn() async {
        let fake = FakeSpeech()
        fake.mic = .denied
        fake.speech = .allowed
        let dictation = dictation(fake)
        dictation.toggle()
        fake.mic = .allowed
        await waitUntil { dictation.state == .idle }
        XCTAssertEqual(fake.started, 0, "it never starts listening on its own")
    }

    func testNoOnDeviceModelIsUnavailableAndNeverFallsBack() {
        let fake = allowed()
        fake.startError = SpeechError.noOnDeviceModel
        let dictation = dictation(fake, language: "en-US")
        dictation.toggle()
        guard case .unavailable(.language(let name)) = dictation.state else { return XCTFail("\(dictation.state)") }
        XCTAssertFalse(name.isEmpty)
        XCTAssertEqual(fake.started, 0)
    }

    func testNoMicrophone() {
        let fake = allowed()
        fake.startError = SpeechError.noMicrophone
        let dictation = dictation(fake)
        dictation.toggle()
        XCTAssertEqual(dictation.state, .unavailable(.noMicrophone))
        XCTAssertTrue(dictation.handleReturn())
        XCTAssertEqual(dictation.state, .idle)
    }

    func testRecognizerErrorStopsWithAMessage() async {
        let fake = allowed()
        let dictation = dictation(fake)
        dictation.toggle()
        fake.onEnd?(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Broken."]))
        await waitUntil { dictation.state == .unavailable(.failed("Broken.")) }
    }

    func testSilenceEndsQuietly() async {
        let fake = allowed()
        let dictation = dictation(fake)
        dictation.toggle()
        fake.onEnd?(NSError(domain: "kAFAssistantErrorDomain", code: 1110))
        await waitUntil { dictation.state == .idle }
    }

    func testLateWordsFromAnOldRecordingAreIgnored() async {
        let fake = allowed()
        let dictation = dictation(fake)
        var heard: [String] = []
        dictation.onTranscript = { heard.append($0) }
        dictation.toggle()
        let old = fake.onText
        dictation.finish()
        dictation.toggle()
        old?("stale", false)
        fake.onText?("fresh", false)
        await waitUntil { heard == ["fresh"] }
    }

    // MARK: Keys in the panel

    private func panel(_ fake: FakeSpeech, draft: String = "Thursday works") -> (PanelModel, () -> Int) {
        let model = PanelModel()
        model.reset(focus: FocusSnapshot(app: nil, text: draft, source: .field, caretRect: nil), presetID: nil)
        model.dictation.backend = fake
        model.dictation.language = { "en-US" }
        var closed = 0
        model.onClose = { closed += 1 }
        return (model, { closed })
    }

    func testEscapeStopsDictationBeforeClosingThePanel() {
        let (model, closed) = panel(allowed())
        model.toggleDictation()
        XCTAssertEqual(model.dictation.state, .recording)
        model.escape()
        XCTAssertEqual(model.dictation.state, .stopping)
        XCTAssertEqual(closed(), 0)
        model.escape()
        XCTAssertEqual(model.dictation.state, .idle)
        model.escape()
        XCTAssertEqual(closed(), 1)
    }

    func testCommandDStartsAndStops() {
        let (model, _) = panel(allowed())
        model.toggleDictation()
        XCTAssertEqual(model.dictation.state, .recording)
        model.toggleDictation()
        XCTAssertEqual(model.dictation.state, .stopping)
        model.toggleDictation()
        XCTAssertEqual(model.dictation.state, .idle)
    }

    func testReturnContinuesTheNoteInsteadOfWriting() {
        let (model, _) = panel(FakeSpeech())
        model.toggleDictation()
        model.submitDraft()
        XCTAssertEqual(model.dictation.state, .asking(explained: true))
        XCTAssertEqual(model.screen, .compose)
    }

    func testWordsGoInAtTheCaretAndTypingTakesOver() async {
        let fake = allowed()
        let (model, _) = panel(fake, draft: "I need specs")
        model.draftSelection = NSRange(location: 7, length: 0)
        model.toggleDictation()
        fake.onText?("the", false)
        fake.onText?("the final", false)
        await waitUntil { model.draft == "I need the final specs" }
        XCTAssertEqual(model.draftCaret, 16)
        model.dictation.userTyped()
        XCTAssertEqual(model.dictation.state, .idle)
        XCTAssertEqual(model.draft, "I need the final specs")
    }

    func testANewRecordingStartsAtTheNewCaret() async {
        let fake = allowed()
        let (model, _) = panel(fake, draft: "Hi.")
        model.toggleDictation()
        fake.onText?("One.", false)
        await waitUntil { model.draft == "Hi. One." }
        model.dictation.finish()
        model.draftSelection = NSRange(location: 0, length: 0)
        model.toggleDictation()
        fake.onText?("Zero", false)
        await waitUntil { model.draft == "Zero Hi. One." }
    }

    func testLeavingComposeStopsListening() {
        let fake = allowed()
        let (model, _) = panel(fake)
        model.toggleDictation()
        model.openPicker()
        XCTAssertEqual(model.dictation.state, .idle)
        XCTAssertGreaterThan(fake.cancelled, 0)
    }

    // MARK: Settings

    func testOlderSettingsFollowTheSystemLanguage() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"engine":"apiKey"}"#.utf8))
        XCTAssertEqual(settings.dictationLanguage, "")
        var changed = AppSettings()
        changed.dictationLanguage = "he-IL"
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(changed)).dictationLanguage, "he-IL")
    }
}
