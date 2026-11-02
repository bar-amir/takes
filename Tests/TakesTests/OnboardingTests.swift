import XCTest
@testable import Takes

final class OnboardingFlowTests: XCTestCase {
    private let nothing = OnboardingConditions(accessibility: false, engineReady: false, privacyAccepted: false, hotKeyFree: true)
    private let everything = OnboardingConditions(accessibility: true, engineReady: true, privacyAccepted: true, hotKeyFree: true)

    // MARK: First launch vs existing users

    func testNewInstallSeesOnboarding() {
        XCTAssertTrue(Onboarding.shouldShow(AppSettings()))
        XCTAssertEqual(AppSettings().onboarding.step, .welcome)
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
        settings.onboarding = OnboardingProgress(step: .hotkey, history: [.welcome, .accessibility, .engine, .privacy],
                                                 autoPassed: [.engine], skipped: [], practiced: false)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.onboarding, settings.onboarding)
        XCTAssertTrue(Onboarding.shouldShow(decoded))
    }

    func testUnknownStepNamesFromANewerVersionAreDropped() throws {
        let json = #"{"step":"pickTheme","history":["welcome","pickTheme","accessibility"],"autoPassed":["somethingNew"],"finished":false}"#
        let progress = try JSONDecoder().decode(OnboardingProgress.self, from: Data(json.utf8))
        XCTAssertEqual(progress.step, .welcome)
        XCTAssertEqual(progress.history, [.welcome, .accessibility])
        XCTAssertTrue(progress.autoPassed.isEmpty)
    }

    // MARK: Moving through

    func testWalksEveryStepWhenNothingIsDone() {
        var flow = OnboardingFlow(conditions: nothing)
        flow.next()
        XCTAssertEqual(flow.step, .accessibility)
        flow.next() // Required and not done: stays.
        XCTAssertEqual(flow.step, .accessibility)
        XCTAssertFalse(flow.canContinue)
        flow.update(OnboardingConditions(accessibility: true, engineReady: false, privacyAccepted: false, hotKeyFree: true))
        flow.next()
        XCTAssertEqual(flow.step, .engine)
    }

    func testSatisfiedStepsPassByThemselvesWithACheck() {
        var flow = OnboardingFlow(conditions: OnboardingConditions(accessibility: true, engineReady: true, privacyAccepted: false, hotKeyFree: true))
        flow.next()
        XCTAssertEqual(flow.step, .privacy, "Accessibility and Claude were already done")
        XCTAssertEqual(flow.progress.autoPassed, [.accessibility, .engine])
        XCTAssertEqual(flow.mark(for: .accessibility), .done)
        XCTAssertEqual(flow.mark(for: .engine), .done)
        XCTAssertEqual(flow.mark(for: .presets), .todo)
    }

    func testBackSkipsStepsThatPassedByThemselves() {
        var flow = OnboardingFlow(conditions: OnboardingConditions(accessibility: true, engineReady: true, privacyAccepted: false, hotKeyFree: true))
        flow.next()
        XCTAssertEqual(flow.step, .privacy)
        XCTAssertTrue(flow.canGoBack)
        flow.back()
        XCTAssertEqual(flow.step, .welcome)
        XCTAssertTrue(flow.progress.history.isEmpty)
        XCTAssertTrue(flow.progress.autoPassed.isEmpty)
        XCTAssertFalse(flow.canGoBack)
    }

    func testBackReturnsToTheStepBefore() {
        var flow = OnboardingFlow(conditions: everything)
        flow.next() // welcome → presets (everything else is done)
        XCTAssertEqual(flow.step, .presets)
        flow.next()
        XCTAssertEqual(flow.step, .practice)
        flow.back()
        XCTAssertEqual(flow.step, .presets)
    }

    func testOnlyOptionalStepsCanBeSkipped() {
        var flow = OnboardingFlow(progress: OnboardingProgress(step: .privacy, history: [.welcome, .accessibility, .engine]),
                                  conditions: OnboardingConditions(accessibility: true, engineReady: true, privacyAccepted: false, hotKeyFree: true))
        flow.skip()
        XCTAssertEqual(flow.step, .privacy, "Privacy can't be skipped")

        flow = OnboardingFlow(progress: OnboardingProgress(step: .presets, history: [.welcome]), conditions: everything)
        flow.skip()
        XCTAssertEqual(flow.step, .practice)
        XCTAssertEqual(flow.mark(for: .presets), .skipped)
        flow.back()
        XCTAssertEqual(flow.step, .presets)
        XCTAssertFalse(flow.progress.skipped.contains(.presets), "Going back undoes the skip")
    }

    func testATakenHotkeyIsShownNotPassed() {
        var conditions = everything
        conditions.hotKeyFree = false
        var flow = OnboardingFlow(progress: OnboardingProgress(step: .privacy, history: [.welcome]), conditions: conditions)
        flow.next()
        XCTAssertEqual(flow.step, .hotkey)
        XCTAssertTrue(flow.canContinue, "A taken hotkey doesn't block onboarding")
        XCTAssertTrue(flow.step.canSkip)
    }

    func testStepThatComesTrueMovesOnByItself() {
        var flow = OnboardingFlow(progress: OnboardingProgress(step: .accessibility, history: [.welcome]), conditions: nothing)
        XCTAssertFalse(flow.update(nothing))
        var granted = nothing
        granted.accessibility = true
        XCTAssertTrue(flow.update(granted), "Access granted in System Settings")
        XCTAssertFalse(flow.update(granted), "Only once")
        // Welcome never moves on by itself.
        var welcome = OnboardingFlow(conditions: nothing)
        XCTAssertFalse(welcome.update(everything))
    }

    func testFinish() {
        var flow = OnboardingFlow(progress: OnboardingProgress(step: .done, history: [.welcome]), conditions: everything)
        flow.finish()
        XCTAssertTrue(flow.progress.finished)
        XCTAssertFalse(Onboarding.shouldShow({ var s = AppSettings(); s.onboarding = flow.progress; return s }()))
    }

    // MARK: Resuming

    func testResumesAtTheSameStep() throws {
        let saved = OnboardingProgress(step: .presets, history: [.welcome, .accessibility, .engine, .privacy, .hotkey], autoPassed: [.hotkey])
        let reloaded = try JSONDecoder().decode(OnboardingProgress.self, from: JSONEncoder().encode(saved))
        var flow = OnboardingFlow(progress: reloaded, conditions: everything)
        flow.resume()
        XCTAssertEqual(flow.step, .presets)
        XCTAssertEqual(flow.progress, saved)
    }

    func testRevokedAccessComesBackOnResume() {
        let saved = OnboardingProgress(step: .practice, history: [.welcome, .accessibility, .engine, .privacy, .hotkey, .presets],
                                       autoPassed: [.engine, .hotkey])
        var revoked = everything
        revoked.accessibility = false
        var flow = OnboardingFlow(progress: saved, conditions: revoked)
        flow.resume()
        XCTAssertEqual(flow.step, .accessibility)
        XCTAssertEqual(flow.progress.history, [.welcome])
        XCTAssertTrue(flow.progress.autoPassed.isEmpty)
        // Granting it again carries on, passing what's still true.
        XCTAssertTrue(flow.update(everything))
        flow.next()
        XCTAssertEqual(flow.step, .presets)
    }

    func testSignedOutWhileAwayComesBack() {
        let saved = OnboardingProgress(step: .presets, history: [.welcome, .accessibility, .engine, .privacy, .hotkey])
        var signedOut = everything
        signedOut.engineReady = false
        var flow = OnboardingFlow(progress: saved, conditions: signedOut)
        flow.resume()
        XCTAssertEqual(flow.step, .engine)
    }

    func testStepDoneWhileAwayIsPassedOnResume() {
        let saved = OnboardingProgress(step: .accessibility, history: [.welcome])
        var granted = nothing
        granted.accessibility = true
        var flow = OnboardingFlow(progress: saved, conditions: granted)
        flow.resume()
        XCTAssertEqual(flow.step, .engine)
        flow.back()
        XCTAssertEqual(flow.step, .welcome, "Back skips the step that passed by itself")
    }

    func testFinishedOnboardingIsLeftAlone() {
        var flow = OnboardingFlow(progress: .existingUser, conditions: nothing)
        flow.resume()
        XCTAssertEqual(flow.step, .done)
        XCTAssertTrue(flow.progress.finished)
    }

    // MARK: Pieces

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
}

/// The practice step drives the real panel through `openPractice`; here a fake panel stands in.
@MainActor
final class OnboardingPracticeTests: XCTestCase {
    private func practiceModel() -> (OnboardingModel, FakePanel) {
        let model = OnboardingModel(progress: OnboardingProgress(step: .practice, history: [.welcome]),
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
        let model = OnboardingModel(progress: OnboardingProgress(step: .presets, history: [.welcome]))
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
        let model = OnboardingModel(progress: OnboardingProgress(step: .accessibility, history: [.welcome]))
        model.autoAdvanceDelay = 0
        model.setConditions(OnboardingConditions(accessibility: true, engineReady: false, privacyAccepted: false, hotKeyFree: true))
        XCTAssertEqual(model.step, .engine)
        XCTAssertNil(model.justPassed)
    }

    func testEscBacksOutThenCloses() {
        let model = OnboardingModel(progress: OnboardingProgress(step: .presets, history: [.welcome]))
        var closed = false
        model.onClose = { closed = true }
        model.escape()
        XCTAssertEqual(model.step, .welcome)
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
