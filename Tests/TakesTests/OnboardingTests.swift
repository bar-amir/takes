import AppKit
import Carbon
import XCTest
@testable import Takes

final class OnboardingFlowTests: XCTestCase {
    private let nothing = OnboardingConditions(accessibility: false, engineReady: false, privacyAccepted: false, hotKeyFree: true)
    private let everything = OnboardingConditions(accessibility: true, engineReady: true, privacyAccepted: true, hotKeyFree: true)

    // MARK: First launch vs existing users

    func testNewInstallSeesOnboarding() {
        XCTAssertTrue(Onboarding.shouldShow(AppSettings()))
        XCTAssertEqual(AppSettings().onboarding.step, .accessibility)
        XCTAssertFalse(AppSettings().onboarding.openingSeen, "A new install starts on the opening screen")
    }

    func testTheFiveSteps() {
        XCTAssertEqual(OnboardingStep.allCases, [.accessibility, .engine, .personalize, .practice, .done])
        XCTAssertEqual(OnboardingStep.allCases.map(\.title), ["Allow access", "Connect a model", "Make it yours", "Try it", "Done"])
        XCTAssertEqual(OnboardingStep.allCases.filter(\.isRequired), [.accessibility, .engine])
        XCTAssertEqual(OnboardingStep.allCases.filter(\.canSkip), [.personalize, .practice])
    }

    func testExistingUsersNeverSeeOnboarding() throws {
        // Settings saved by a version without onboarding.
        let old = #"{"engine":"claudeCode","privacyAccepted":true}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        XCTAssertFalse(Onboarding.shouldShow(settings))
        // Even one who never finished the old setup: they keep the setup window.
        let unfinished = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"privacyAccepted":false}"#.utf8))
        XCTAssertFalse(Onboarding.shouldShow(unfinished))
    }

    func testProgressSurvivesQuitting() throws {
        var settings = AppSettings()
        settings.onboarding = OnboardingProgress(step: .personalize, history: [.accessibility, .engine],
                                                 autoPassed: [.accessibility], skipped: [], practiced: false, openingSeen: true)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.onboarding, settings.onboarding)
        XCTAssertTrue(Onboarding.shouldShow(decoded))
    }

    func testUnknownStepNamesFromANewerVersionAreDropped() throws {
        let json = #"{"step":"pickTheme","history":["accessibility","pickTheme"],"autoPassed":["somethingNew"],"finished":false}"#
        let progress = try JSONDecoder().decode(OnboardingProgress.self, from: Data(json.utf8))
        XCTAssertEqual(progress.step, .accessibility)
        XCTAssertEqual(progress.history, [], "The current step isn't also in its own history")
        XCTAssertTrue(progress.autoPassed.isEmpty)
    }

    // MARK: Progress saved by 0.5 (eight steps)

    private func decode(_ json: String) throws -> OnboardingProgress {
        try JSONDecoder().decode(OnboardingProgress.self, from: Data(json.utf8))
    }

    func testOldWelcomeResumesOnTheOpeningScreen() throws {
        let progress = try decode(#"{"step":"welcome","history":[],"autoPassed":[],"skipped":[],"practiced":false,"finished":false}"#)
        XCTAssertEqual(progress.step, .accessibility)
        XCTAssertFalse(progress.openingSeen)
        XCTAssertTrue(progress.history.isEmpty)
    }

    func testOldPrivacyStepIsNowConnectAModel() throws {
        let progress = try decode(#"{"step":"privacy","history":["welcome","accessibility","engine"],"autoPassed":["accessibility","engine"],"finished":false}"#)
        XCTAssertEqual(progress.step, .engine)
        XCTAssertEqual(progress.history, [.accessibility])
        XCTAssertEqual(progress.autoPassed, [.accessibility])
        XCTAssertTrue(progress.openingSeen, "Past Welcome means the opening was seen")
    }

    func testOldHotkeyAndPresetsAreNowMakeItYours() throws {
        let atHotkey = try decode(#"{"step":"hotkey","history":["welcome","accessibility","engine","privacy"],"autoPassed":["engine"]}"#)
        XCTAssertEqual(atHotkey.step, .personalize)
        XCTAssertEqual(atHotkey.history, [.accessibility, .engine])
        XCTAssertTrue(atHotkey.autoPassed.isEmpty, "Your text was walked, so the merged step wasn't passed by itself")

        let atPresets = try decode(#"{"step":"presets","history":["welcome","accessibility","engine","privacy","hotkey"],"autoPassed":["hotkey"]}"#)
        XCTAssertEqual(atPresets.step, .personalize)
        XCTAssertEqual(atPresets.history, [.accessibility, .engine])
    }

    func testOldSkipsAndAutoPassesMap() throws {
        let progress = try decode(#"{"step":"practice","history":["welcome","accessibility","engine","privacy","hotkey","presets"],"autoPassed":["accessibility","engine","hotkey"],"skipped":["presets"],"practiced":false}"#)
        XCTAssertEqual(progress.step, .practice)
        XCTAssertEqual(progress.history, [.accessibility, .engine, .personalize])
        XCTAssertEqual(progress.autoPassed, [.accessibility])
        XCTAssertEqual(progress.skipped, [.personalize], "Hotkey passed by itself and Presets was skipped")

        let partly = try decode(#"{"step":"practice","history":["welcome","accessibility","engine","privacy","hotkey","presets"],"skipped":["hotkey"]}"#)
        XCTAssertTrue(partly.skipped.isEmpty, "Presets were chosen, so Make it yours wasn't skipped")
    }

    func testMigratedProgressResumesWhereItWas() throws {
        let progress = try decode(#"{"step":"presets","history":["welcome","accessibility","engine","privacy","hotkey"],"autoPassed":[]}"#)
        var flow = OnboardingFlow(progress: progress, conditions: everything)
        flow.resume()
        XCTAssertEqual(flow.step, .personalize)
        flow.back()
        XCTAssertEqual(flow.step, .engine)
    }

    func testFinishedOldProgressStaysFinished() throws {
        let progress = try decode(#"{"step":"done","history":["welcome","accessibility","engine","privacy","hotkey","presets","practice"],"finished":true}"#)
        XCTAssertTrue(progress.finished)
        XCTAssertEqual(progress.step, .done)
        XCTAssertTrue(progress.openingSeen)
    }

    // MARK: Moving through

    func testWalksEveryStepWhenNothingIsDone() {
        var flow = OnboardingFlow(conditions: nothing)
        XCTAssertEqual(flow.step, .accessibility)
        flow.next() // Required and not done: stays.
        XCTAssertEqual(flow.step, .accessibility)
        XCTAssertFalse(flow.canContinue)
        flow.update(OnboardingConditions(accessibility: true, engineReady: false, privacyAccepted: false, hotKeyFree: true))
        flow.next()
        XCTAssertEqual(flow.step, .engine)
    }

    func testConnectAModelNeedsBothAnEngineAndConsent() {
        var flow = OnboardingFlow(progress: OnboardingProgress(step: .engine, history: [.accessibility]),
                                  conditions: OnboardingConditions(accessibility: true, engineReady: true, privacyAccepted: false, hotKeyFree: true))
        XCTAssertFalse(flow.canContinue, "A working engine alone isn't enough: where the text goes must be accepted")
        XCTAssertTrue(flow.update(everything), "Accepting moves on by itself")
        flow.next()
        XCTAssertEqual(flow.step, .personalize)
    }

    func testSatisfiedStepsPassByThemselvesWithACheck() {
        var flow = OnboardingFlow(progress: OnboardingProgress(step: .accessibility), conditions: everything)
        flow.resume()
        XCTAssertEqual(flow.step, .personalize, "Access and the engine were already done")
        XCTAssertEqual(flow.progress.autoPassed, [.accessibility, .engine])
        XCTAssertEqual(flow.mark(for: .accessibility), .done)
        XCTAssertEqual(flow.mark(for: .engine), .done)
        XCTAssertEqual(flow.mark(for: .practice), .todo)
    }

    func testStepsNotReachedYetAreNotChecked() {
        // Access is granted and the engine works, but the user is still on the first step.
        let flow = OnboardingFlow(progress: OnboardingProgress(step: .accessibility),
                                  conditions: OnboardingConditions(accessibility: false, engineReady: true, privacyAccepted: true, hotKeyFree: true))
        XCTAssertEqual(flow.mark(for: .accessibility), .current)
        XCTAssertEqual(flow.mark(for: .engine), .todo)
        XCTAssertEqual(flow.mark(for: .personalize), .todo)
    }

    func testBackSkipsStepsThatPassedByThemselves() {
        var flow = OnboardingFlow(progress: OnboardingProgress(step: .accessibility), conditions: everything)
        flow.resume()
        XCTAssertEqual(flow.step, .personalize)
        XCTAssertFalse(flow.canGoBack, "Nothing before it was seen")
        flow.next()
        XCTAssertEqual(flow.step, .practice)
        flow.back()
        XCTAssertEqual(flow.step, .personalize)
    }

    func testOnlyOptionalStepsCanBeSkipped() {
        var flow = OnboardingFlow(progress: OnboardingProgress(step: .engine, history: [.accessibility]),
                                  conditions: OnboardingConditions(accessibility: true, engineReady: true, privacyAccepted: false, hotKeyFree: true))
        flow.skip()
        XCTAssertEqual(flow.step, .engine, "Connect a model can't be skipped")

        flow = OnboardingFlow(progress: OnboardingProgress(step: .personalize, history: [.accessibility, .engine]), conditions: everything)
        flow.skip()
        XCTAssertEqual(flow.step, .practice)
        XCTAssertEqual(flow.mark(for: .personalize), .skipped)
        flow.back()
        XCTAssertEqual(flow.step, .personalize)
        XCTAssertFalse(flow.progress.skipped.contains(.personalize), "Going back undoes the skip")
    }

    func testATakenHotkeyDoesntBlock() {
        var conditions = everything
        conditions.hotKeyFree = false
        let flow = OnboardingFlow(progress: OnboardingProgress(step: .personalize, history: [.accessibility, .engine]), conditions: conditions)
        XCTAssertTrue(flow.canContinue, "A taken hotkey doesn't block onboarding")
        XCTAssertTrue(flow.step.canSkip)
    }

    func testStepThatComesTrueMovesOnByItself() {
        var flow = OnboardingFlow(progress: OnboardingProgress(step: .accessibility), conditions: nothing)
        XCTAssertFalse(flow.update(nothing))
        var granted = nothing
        granted.accessibility = true
        XCTAssertTrue(flow.update(granted), "Access granted in System Settings")
        XCTAssertFalse(flow.update(granted), "Only once")
        // Make it yours never moves on by itself.
        var personalize = OnboardingFlow(progress: OnboardingProgress(step: .personalize), conditions: nothing)
        XCTAssertFalse(personalize.update(everything))
    }

    func testFinish() {
        var flow = OnboardingFlow(progress: OnboardingProgress(step: .done, history: [.accessibility]), conditions: everything)
        flow.finish()
        XCTAssertTrue(flow.progress.finished)
        XCTAssertFalse(Onboarding.shouldShow({ var s = AppSettings(); s.onboarding = flow.progress; return s }()))
    }

    // MARK: Resuming

    func testResumesAtTheSameStep() throws {
        let saved = OnboardingProgress(step: .personalize, history: [.accessibility, .engine], autoPassed: [.accessibility], openingSeen: true)
        let reloaded = try JSONDecoder().decode(OnboardingProgress.self, from: JSONEncoder().encode(saved))
        var flow = OnboardingFlow(progress: reloaded, conditions: everything)
        flow.resume()
        XCTAssertEqual(flow.step, .personalize)
        XCTAssertEqual(flow.progress, saved)
    }

    func testRevokedAccessComesBackOnResume() {
        let saved = OnboardingProgress(step: .practice, history: [.accessibility, .engine, .personalize], autoPassed: [.engine])
        var revoked = everything
        revoked.accessibility = false
        var flow = OnboardingFlow(progress: saved, conditions: revoked)
        flow.resume()
        XCTAssertEqual(flow.step, .accessibility)
        XCTAssertEqual(flow.progress.history, [])
        XCTAssertTrue(flow.progress.autoPassed.isEmpty)
        // Granting it again carries on, passing what's still true.
        XCTAssertTrue(flow.update(everything))
        flow.next()
        XCTAssertEqual(flow.step, .personalize)
    }

    func testSignedOutWhileAwayComesBack() {
        let saved = OnboardingProgress(step: .personalize, history: [.accessibility, .engine])
        var signedOut = everything
        signedOut.engineReady = false
        var flow = OnboardingFlow(progress: saved, conditions: signedOut)
        flow.resume()
        XCTAssertEqual(flow.step, .engine)
    }

    func testStepDoneWhileAwayIsPassedOnResume() {
        let saved = OnboardingProgress(step: .accessibility)
        var granted = nothing
        granted.accessibility = true
        var flow = OnboardingFlow(progress: saved, conditions: granted)
        flow.resume()
        XCTAssertEqual(flow.step, .engine)
        XCTAssertFalse(flow.canGoBack, "Back skips the step that passed by itself")
    }

    func testFinishedOnboardingIsLeftAlone() {
        var flow = OnboardingFlow(progress: .existingUser, conditions: nothing)
        flow.resume()
        XCTAssertEqual(flow.step, .done)
        XCTAssertTrue(flow.progress.finished)
    }

    // MARK: Pieces

    func testRecommendedEngine() {
        XCTAssertEqual(Onboarding.recommendedEngine(current: .chatGPT, currentReady: true, claudeInstalled: true, localRunning: true), .chatGPT,
                       "What already works wins")
        XCTAssertEqual(Onboarding.recommendedEngine(current: .claudeCode, currentReady: false, claudeInstalled: true, localRunning: true), .claudeCode)
        XCTAssertEqual(Onboarding.recommendedEngine(current: .claudeCode, currentReady: false, claudeInstalled: false, localRunning: true), .local)
        XCTAssertEqual(Onboarding.recommendedEngine(current: .claudeCode, currentReady: false, claudeInstalled: false, localRunning: false), .claudeCode)
    }

    func testApplyingPresetsKeepsCustomOnesAndAddsMissingStarters() {
        let starters = Array(Store.defaultPresets.prefix(3))
        let custom = Preset(name: "Mine", colorHex: "#000000", instruction: "x")
        let installed = [starters[0], custom, starters[1]]
        let result = OnboardingModel.applying(chosen: [starters[1].name, starters[2].name], starters: starters, to: installed)
        XCTAssertEqual(result.map(\.name), ["Mine", starters[1].name, starters[2].name])
    }

    func testHotkeyKeycaps() {
        XCTAssertEqual(BigKeys.parts("⌃⌥Space"), ["⌃", "⌥", "Space"])
        XCTAssertEqual(BigKeys.parts("⌘⇧K"), ["⌘", "⇧", "K"])
        XCTAssertEqual(BigKeys.parts("F5"), ["F5"])
    }

    func testHotkeyAsAMenuKeyEquivalent() throws {
        let space = try XCTUnwrap(AppSettings().summonHotKey.menuKeyEquivalent)
        XCTAssertEqual(space.key, " ")
        XCTAssertEqual(space.modifiers, [.control, .option])
        let letter = try XCTUnwrap(KeyCombo(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | shiftKey), display: "⇧⌘K").menuKeyEquivalent)
        XCTAssertEqual(letter.key, "k", "Lowercase, so the mask alone carries ⇧")
        XCTAssertEqual(letter.modifiers, [.shift, .command])
        let f5 = try XCTUnwrap(KeyCombo(keyCode: UInt32(kVK_F5), modifiers: UInt32(optionKey), display: "⌥F5").menuKeyEquivalent)
        XCTAssertEqual(f5.key.unicodeScalars.first?.value, UInt32(NSF5FunctionKey))
        XCTAssertNil(KeyCombo(keyCode: 999, modifiers: UInt32(cmdKey), display: "⌘Mystery").menuKeyEquivalent)
    }
}

/// The practice step drives the real panel through `openPractice`; here a fake panel stands in.
@MainActor
final class OnboardingPracticeTests: XCTestCase {
    private func practiceModel() -> (OnboardingModel, FakePanel) {
        let model = OnboardingModel(progress: OnboardingProgress(step: .practice, history: [.accessibility, .engine, .personalize]),
                                    conditions: OnboardingConditions(accessibility: true, engineReady: true, privacyAccepted: true, hotKeyFree: true))
        let panel = FakePanel()
        model.openPractice = { text, frame, paste, cancel in panel.open(text: text, frame: frame, paste: paste, cancel: cancel) }
        model.practiceBoxFrame = { CGRect(x: 100, y: 100, width: 400, height: 100) }
        return (model, panel)
    }

    func testSummonWritePickPaste() {
        let (model, panel) = practiceModel()
        var saved: [OnboardingProgress] = []
        model.save = { saved.append($0) }
        XCTAssertEqual(model.primaryTitle, "Open Takes")

        model.startPractice() // the hotkey, or Open Takes
        XCTAssertEqual(model.practiceStage, .panelOpen)
        XCTAssertEqual(panel.openedText, Onboarding.sampleDraft)
        XCTAssertEqual(panel.openedFrame, CGRect(x: 100, y: 100, width: 400, height: 100), "The panel opens beside the box")
        XCTAssertFalse(model.primaryEnabled)

        model.startPractice() // a second press while open does nothing
        XCTAssertEqual(panel.opens, 1)

        panel.paste?("Could you send me the deck before Friday?")
        XCTAssertEqual(model.practiceStage, .pasted)
        XCTAssertEqual(model.practiceText, "Could you send me the deck before Friday?")
        XCTAssertTrue(model.flow.progress.practiced)
        XCTAssertEqual(saved.last?.practiced, true)
        XCTAssertEqual(model.primaryTitle, "Continue")
        XCTAssertFalse(model.canSkip)

        model.primary()
        XCTAssertEqual(model.step, .done)
    }

    func testClosingThePanelGoesBackToWriting() {
        let (model, panel) = practiceModel()
        model.practiceText = "my own draft"
        model.primary()
        XCTAssertEqual(panel.openedText, "my own draft")
        panel.cancel?()
        XCTAssertEqual(model.practiceStage, .write)
        XCTAssertFalse(model.flow.progress.practiced)
    }

    func testHotkeyOutsideThePracticeStepDoesNothing() {
        let panel = FakePanel()
        let model = OnboardingModel(progress: OnboardingProgress(step: .personalize, history: [.accessibility, .engine]))
        model.openPractice = { text, frame, paste, cancel in panel.open(text: text, frame: frame, paste: paste, cancel: cancel) }
        model.startPractice()
        XCTAssertEqual(panel.opens, 0)
        XCTAssertEqual(model.practiceStage, .write)
    }

    func testPracticeCanBeSkipped() {
        let (model, _) = practiceModel()
        XCTAssertTrue(model.canSkip)
        model.skip()
        XCTAssertEqual(model.step, .done)
        XCTAssertTrue(model.flow.progress.skipped.contains(.practice))
    }

    func testAccessGrantedMovesOnAfterTheCheck() {
        let model = OnboardingModel(progress: OnboardingProgress(step: .accessibility))
        model.autoAdvanceDelay = 0
        model.setConditions(OnboardingConditions(accessibility: true, engineReady: false, privacyAccepted: false, hotKeyFree: true))
        XCTAssertEqual(model.step, .engine)
        XCTAssertNil(model.justPassed)
    }

    func testConnectAModelAsksForConsentInItsButton() {
        let model = OnboardingModel(progress: OnboardingProgress(step: .engine, history: [.accessibility]),
                                    conditions: OnboardingConditions(accessibility: true, engineReady: true, privacyAccepted: false, hotKeyFree: true))
        var recorded = false
        model.recordPrivacyAccepted = { recorded = true }
        XCTAssertEqual(model.primaryTitle, "Understood, continue")
        model.primary()
        XCTAssertTrue(recorded)
        XCTAssertEqual(model.step, .personalize)
    }

    func testConsentButtonNamesTheEngineAction() {
        let model = OnboardingModel(progress: OnboardingProgress(step: .engine, history: [.accessibility]),
                                    conditions: OnboardingConditions(accessibility: true))
        model.engineStatus = .problem("Claude Code isn't signed in")
        XCTAssertEqual(model.primaryTitle, "Understood, open Terminal")
        model.engineKind = .apiKey
        XCTAssertEqual(model.primaryTitle, "Understood, save key")
        model.engineKind = .local
        XCTAssertEqual(model.primaryTitle, "Understood, check again")
        model.engineStatus = .checking
        XCTAssertEqual(model.primaryTitle, "Checking…")
    }

    func testEscBacksOutThenCloses() {
        let model = OnboardingModel(progress: OnboardingProgress(step: .personalize, history: [.engine]))
        var closed = false
        model.onClose = { closed = true }
        model.escape()
        XCTAssertEqual(model.step, .engine)
        XCTAssertFalse(closed)
        model.escape()
        XCTAssertTrue(closed)
    }
}

private final class FakePanel {
    var opens = 0
    var openedText: String?
    var openedFrame: CGRect?
    var paste: ((String) -> Void)?
    var cancel: (() -> Void)?

    func open(text: String, frame: CGRect?, paste: @escaping (String) -> Void, cancel: @escaping () -> Void) {
        opens += 1
        openedText = text
        openedFrame = frame
        self.paste = paste
        self.cancel = cancel
    }
}

/// Setup and onboarding share one sentence on where the text goes; it must name the right place for each engine.
@MainActor
final class PrivacySummaryTests: XCTestCase {
    private func settings(_ engine: EngineKind) -> AppSettings {
        var settings = AppSettings()
        settings.engine = engine
        return settings
    }

    func testEachEngineNamesWhereTheTextGoes() {
        XCTAssertTrue(SetupMonitor.privacySummary(for: settings(.claudeCode)).contains("to Anthropic, under your own Claude account"))
        XCTAssertTrue(SetupMonitor.privacySummary(for: settings(.apiKey)).contains("to Anthropic"))
        XCTAssertTrue(SetupMonitor.privacySummary(for: settings(.chatGPT)).contains("to OpenAI, under your own ChatGPT plan"))
        var openAI = settings(.provider)
        openAI.providerID = "openai"
        XCTAssertTrue(SetupMonitor.privacySummary(for: openAI).contains("to OpenAI, under your own account"))
        var custom = settings(.provider)
        custom.providerID = "custom"
        XCTAssertTrue(SetupMonitor.privacySummary(for: custom).contains("to the server you added"))
        XCTAssertTrue(SetupMonitor.privacySummary(for: settings(.local)).contains("nothing leaves it"))
        XCTAssertFalse(SetupMonitor.privacySummary(for: settings(.local)).contains("Anthropic"))
    }

    func testOnlyClaudeIsNamedInTheMistakesNote() {
        XCTAssertTrue(SetupMonitor.mistakesNote(for: settings(.claudeCode)).hasPrefix("Claude can get things wrong"))
        XCTAssertTrue(SetupMonitor.mistakesNote(for: settings(.chatGPT)).hasPrefix("Models can get things wrong"))
        XCTAssertTrue(SetupMonitor.mistakesNote(for: settings(.local)).hasPrefix("Models can get things wrong"))
    }
}
