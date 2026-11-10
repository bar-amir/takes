import XCTest
@testable import Takes

/// The shorter first run: Allow access, Connect a model and Try it, then a closing screen. The ways to connect are
/// offered as equals with nothing picked for the user unless it's already set up; the consent is a sentence, not a
/// button label; Accessibility's troubleshooting waits for a failed check; the provider path finishes in onboarding.
@MainActor
final class OnboardingShortFlowTests: XCTestCase {
    private let granted = OnboardingConditions(accessibility: true, engineReady: false, privacyAccepted: false, hotKeyFree: true)

    private func engineModel() -> OnboardingModel {
        OnboardingModel(progress: OnboardingProgress(step: .engine, history: [.accessibility]), conditions: granted)
    }

    // MARK: Steps

    func testStepCountsLeaveOutTheClosingScreen() {
        let flow = OnboardingFlow(progress: OnboardingProgress(step: .engine, history: [.accessibility]))
        XCTAssertEqual(flow.numbered?.index, 2)
        XCTAssertEqual(flow.numbered?.count, 3, "Step 2 of 3")
        XCTAssertNil(OnboardingFlow(progress: OnboardingProgress(step: .done)).numbered)
    }

    func testTheWholeFirstRunInOrder() {
        let model = OnboardingModel(progress: OnboardingProgress(openingSeen: true))
        model.autoAdvanceDelay = 0
        XCTAssertEqual(model.step, .accessibility)
        model.setConditions(granted)
        XCTAssertEqual(model.step, .engine)
        model.setConditions(OnboardingConditions(accessibility: true, engineReady: true, privacyAccepted: false, hotKeyFree: true))
        model.engineChosen = true
        model.primary()  // continuing is the consent
        XCTAssertEqual(model.step, .practice, "Straight to Try it: no Make it yours")
        model.skip()
        XCTAssertEqual(model.step, .done)
        var finished = false
        model.onFinish = { finished = true }
        XCTAssertEqual(model.primaryTitle, "Start using Takes")
        model.primary()
        XCTAssertTrue(finished)
        XCTAssertTrue(model.flow.progress.finished)
    }

    func testPeopleWhoFinishedAreNeverSentBack() throws {
        // A finished 0.5-era progress, and a finished one from the last version with Make it yours in it.
        for json in [#"{"step":"done","history":["welcome","accessibility","engine","privacy","hotkey","presets","practice"],"finished":true}"#,
                     #"{"step":"done","history":["accessibility","engine","personalize","practice"],"skipped":["personalize"],"finished":true,"openingSeen":true}"#,
        ] {
            var settings = AppSettings()
            settings.onboarding = try JSONDecoder().decode(OnboardingProgress.self, from: Data(json.utf8))
            XCTAssertFalse(Onboarding.shouldShow(settings))
            var flow = OnboardingFlow(progress: settings.onboarding)
            flow.resume()
            XCTAssertEqual(flow.step, .done)
        }
    }

    // MARK: Ways to connect

    func testEveryWayIsListedAndNoneIsFolded() {
        XCTAssertEqual(Set(Onboarding.engineOrder), Set([EngineKind.claudeCode, .apiKey, .chatGPT, .provider, .local]))
        XCTAssertEqual(Onboarding.engineOrder.count, 5)
    }

    func testNothingIsPickedForTheUserWhenNothingIsSetUp() {
        let model = engineModel()
        XCTAssertFalse(model.engineChosen)
        for kind in Onboarding.engineOrder { XCTAssertFalse(model.isChosen(kind)) }
        XCTAssertEqual(model.primaryTitle, "Continue")
        XCTAssertFalse(model.primaryEnabled, "Pick one first")
        XCTAssertFalse(model.needsConsent, "Where the text goes depends on the pick")
        model.preselect()
        XCTAssertFalse(model.engineChosen, "No company is favoured")
    }

    func testWhatIsAlreadySetUpIsHighlightedOnly() {
        let model = engineModel()
        var written: [EngineKind] = []
        model.writeEngine = { written.append($0) }
        model.detected = true
        model.engineStatus = .problem("Claude Code isn't installed")
        model.setUpEngines = [.local]
        model.preselect()
        XCTAssertTrue(model.isChosen(.local))
        XCTAssertEqual(written, [], "Highlighting writes nothing")
        XCTAssertTrue(model.needsConsent)
        XCTAssertEqual(model.primaryTitle, "Continue", "Set up but not saved: pressing saves it")
        model.primary()
        XCTAssertEqual(written, [.local], "The button saves the engine")
    }

    func testAWorkingClaudeCodeIsNotPassedOverForAnOldKey() {
        let model = engineModel()
        var written: [EngineKind] = []
        model.writeEngine = { written.append($0) }
        var asked = 0
        model.checkAPIKey = { _ in asked += 1; return .valid }
        model.detected = true
        model.setUpEngines = [.apiKey]
        model.preselect()
        XCTAssertFalse(model.engineChosen, "Waits for the saved engine's first check")
        model.savedEngineChanged(.claudeCode, needsChoice: false, status: .ready("Claude Code signed in · Max plan"))
        XCTAssertTrue(model.isChosen(.claudeCode), "The saved engine works, so it's the one")
        XCTAssertTrue(model.flow.conditions.engineReady)
        XCTAssertEqual(written, [])
        XCTAssertEqual(asked, 0)
    }

    func testAWorkingSavedEngineDoesntCarryAnotherOption() {
        let model = engineModel()
        model.detected = true
        model.savedEngineChanged(.claudeCode, needsChoice: false, status: .ready("Claude Code signed in"))
        XCTAssertTrue(model.flow.conditions.engineReady)
        model.choose(.apiKey)
        XCTAssertFalse(model.flow.conditions.engineReady, "Continue mustn't go on with Claude Code while the key row is picked")
        XCTAssertEqual(model.primaryTitle, "Save key")
        model.choose(.claudeCode)
        XCTAssertTrue(model.flow.conditions.engineReady)
    }

    func testTheOldEnginesReadyIsNotTakenForTheNewOne() {
        let model = engineModel()
        model.autoAdvanceDelay = 0
        model.detected = true
        model.savedEngineChanged(.claudeCode, needsChoice: false, status: .ready("Claude Code signed in"))
        model.choose(.local)
        model.primary()  // the consent, and saves the local model
        XCTAssertTrue(model.flow.conditions.privacyAccepted)
        // The settings change can reach the window before the monitor has started the new check.
        model.savedEngineChanged(.local, needsChoice: false, status: .ready("Claude Code signed in"))
        XCTAssertEqual(model.step, .engine, "Claude Code's answer doesn't pass the local model")
        XCTAssertFalse(model.flow.conditions.engineReady)
        model.savedEngineChanged(.local, needsChoice: false, status: .checking)
        model.savedEngineChanged(.local, needsChoice: false, status: .ready("Ollama · llama3.2"))
        XCTAssertEqual(model.step, .practice, "Its own answer does")
    }

    /// Before the button below the consent line is pressed, Takes sends nothing anywhere: nothing is saved (which
    /// would start the saved engine's check), no key is checked, no provider is asked.
    func testNothingIsSentBeforeTheButton() {
        URLProtocol.registerClass(RefuseRequests.self)
        defer { URLProtocol.unregisterClass(RefuseRequests.self) }
        RefuseRequests.seen = []
        let model = engineModel()
        var written: [EngineKind] = [], keys = 0, providers = 0, engines = 0, keyReads = 0
        model.writeEngine = { written.append($0) }
        model.checkAPIKey = { _ in keys += 1; return .valid }
        model.refreshProvider = { _ in providers += 1 }
        model.refreshEngine = { engines += 1 }
        model.readProviderKey = { keyReads += 1 }
        model.detected = true
        model.setUpEngines = [.apiKey, .provider]
        model.savedEngineChanged(.claudeCode, needsChoice: false, status: .problem("Claude Code isn't installed"))
        XCTAssertTrue(model.isChosen(.apiKey), "Highlighted")
        model.choose(.provider)
        model.providerShown()
        model.choose(.local)
        model.choose(.apiKey)
        XCTAssertEqual(written, [])
        XCTAssertEqual(keys + providers + engines, 0)
        XCTAssertEqual(keyReads, 1, "Only the keychain was read")
        XCTAssertTrue(RefuseRequests.seen.isEmpty, "No request: \(RefuseRequests.seen)")
    }

    func testTheProviderIsAskedOnlyAfterTheConsent() async {
        let model = OnboardingModel(progress: OnboardingProgress(step: .engine, history: [.accessibility]),
                                    conditions: OnboardingConditions(accessibility: true, privacyAccepted: true))
        var providers: [Bool] = []
        model.refreshProvider = { providers.append($0) }
        model.providerShown()
        for _ in 0..<20 where providers.isEmpty { await Task.yield() }
        XCTAssertEqual(providers, [false], "After the consent the list loads, from the cache if it's fresh")
    }

    // MARK: Move to Applications

    func testASecondClickDoesNothingWhileMoving() async {
        let model = OnboardingModel(progress: OnboardingProgress(step: .accessibility))
        var moves = 0
        var finish: CheckedContinuation<Void, Never>?
        model.move = {
            moves += 1
            await withCheckedContinuation { finish = $0 }
            throw AppLocation.MoveError.couldNotOpen
        }
        model.moveToApplications()
        for _ in 0..<20 where finish == nil { await Task.yield() }
        XCTAssertTrue(model.moving)
        model.moveToApplications()
        model.moveToApplications()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(moves, 1, "A second move would remove the copy the first is opening")
        finish?.resume()
        for _ in 0..<20 where model.moving { await Task.yield() }
        XCTAssertFalse(model.moving)
        XCTAssertEqual(model.moveError, AppLocation.MoveError.couldNotOpen.localizedDescription)
    }

    func testTheUsersOwnPickIsKept() {
        let model = engineModel()
        model.choose(.chatGPT)
        model.setUpEngines = [.local]
        model.preselect()
        XCTAssertTrue(model.isChosen(.chatGPT))
    }

    func testPickingClearsTheLastKeyMessage() {
        let model = engineModel()
        model.apiKeySave = .notSaved
        model.providerKeyNotSaved = true
        model.choose(.provider)
        XCTAssertNil(model.apiKeySave)
        XCTAssertFalse(model.providerKeyNotSaved)
    }

    func testNoButtonAsksForConsentInItsLabel() {
        let model = engineModel()
        model.engineChosen = true
        model.engineStatus = .problem("x")
        for kind in Onboarding.engineOrder {
            model.engineKind = kind
            XCTAssertFalse(model.primaryTitle.contains("Understood"), "\(kind): \(model.primaryTitle)")
        }
        model.engineKind = .chatGPT
        XCTAssertEqual(ChatGPTSignIn.shared.state, .signedOut, "Tests use an empty in-memory keychain")
        XCTAssertEqual(model.primaryTitle, "Continue with ChatGPT")
    }

    // MARK: The provider path stays in onboarding

    func testTheProviderButtonSavesTheKeyRatherThanOpeningSettings() {
        ProviderModels.shared.hasKey = false
        let model = engineModel()
        model.choose(.provider)
        XCTAssertEqual(model.primaryTitle, "Save key")
        XCTAssertFalse(model.primaryEnabled, "Nothing pasted yet")
        model.providerKeyInput = "sk-test"
        XCTAssertTrue(model.primaryEnabled)
    }

    // MARK: Accessibility

    func testTroubleshootingWaitsForAFailedCheck() async {
        let model = OnboardingModel(progress: OnboardingProgress(step: .accessibility))
        var asked = 0, checks = 0
        model.requestAccess = { asked += 1 }
        model.isTrusted = { checks += 1; return false }
        model.accessibilityHelpDelay = 0
        XCTAssertFalse(model.accessibilityHelp, "Nothing to troubleshoot before a check")
        model.primary()
        XCTAssertEqual(asked, 1)
        for _ in 0..<100 where checks == 0 { await Task.yield() }
        XCTAssertEqual(checks, 1)
        XCTAssertTrue(model.accessibilityHelp, "The check found no access")
    }

    func testNoTroubleshootingWhenTheCheckFindsAccess() async {
        let model = OnboardingModel(progress: OnboardingProgress(step: .accessibility))
        var checks = 0
        model.isTrusted = { checks += 1; return true }
        model.accessibilityHelpDelay = 0
        model.primary()
        for _ in 0..<100 where checks == 0 { await Task.yield() }
        XCTAssertEqual(checks, 1)
        XCTAssertFalse(model.accessibilityHelp)
    }

    func testNoTroubleshootingOnceAccessIsAllowed() async {
        let model = OnboardingModel(progress: OnboardingProgress(step: .accessibility))
        model.isTrusted = { false }
        model.accessibilityHelpDelay = 0.05
        model.autoAdvanceDelay = 0
        model.primary()
        model.setConditions(granted)
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertFalse(model.accessibilityHelp)
    }

    // MARK: Done

    func testOnlyTryItCanBeSkipped() {
        XCTAssertFalse(engineModel().canSkip)
        let practice = OnboardingModel(progress: OnboardingProgress(step: .practice, history: [.accessibility, .engine]))
        XCTAssertTrue(practice.canSkip)
        XCTAssertFalse(OnboardingModel(progress: OnboardingProgress(step: .done)).canSkip)
    }
}

/// Connect a model's actions: each Claude Code state's button, saving an Anthropic key after Anthropic has seen it,
/// and picking an engine over one saved by a newer version.
@MainActor
final class OnboardingEngineActionTests: XCTestCase {
    private var stored: [String] = []

    private func store(_ result: Bool) -> (String) -> Bool {
        { [unowned self] key in stored.append(key); return result }
    }

    func testOnboardingOffersTheActionForTheState() {
        let model = OnboardingModel(progress: OnboardingProgress(step: .engine, history: [.accessibility]),
                                    conditions: OnboardingConditions(accessibility: true, privacyAccepted: true))
        model.engineChosen = true
        model.installer = ClaudeInstaller()
        model.engineStatus = .problem("x")
        let cases: [(ClaudeCodeEngine.Status.State, String)] = [
            (.notInstalled, "Install Claude Code"), (.tooOld("2.0.24"), "Update Claude Code"), (.signedOut, "Sign in to Claude"),
            (.notAnswering, "Check again"), (.couldNotStart("no"), "Check again"), (.stillLooking, "Check again"),
        ]
        for (state, title) in cases {
            model.claudeState = state
            XCTAssertEqual(model.primaryTitle, title, "\(state)")
            XCTAssertTrue(model.primaryEnabled)
        }
        model.claudeState = .notInstalled
        XCTAssertTrue(model.claudeMissing)
        model.claudeState = .tooOld("2.0.24")
        XCTAssertFalse(model.claudeMissing)
    }

    private func engineModel() -> OnboardingModel {
        let model = OnboardingModel(progress: OnboardingProgress(step: .engine, history: [.accessibility]),
                                    conditions: OnboardingConditions(accessibility: true, privacyAccepted: true))
        model.engineChosen = true
        model.engineKind = .apiKey
        model.engineStatus = .problem("No API key saved yet")
        return model
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    func testOnboardingSavesAWorkingKeyAndChecksTheEngine() async {
        let model = engineModel()
        var refreshed = 0
        model.checkAPIKey = { _ in .valid }
        model.storeAPIKey = store(true)
        model.refreshEngine = { refreshed += 1 }
        model.apiKeyInput = "  sk-ant-good \n"
        XCTAssertEqual(model.primaryTitle, "Save key")
        model.primary()
        XCTAssertTrue(model.checkingKey)
        XCTAssertEqual(model.primaryTitle, "Checking your key…")
        XCTAssertFalse(model.primaryEnabled, "One check at a time")
        await waitUntil { refreshed == 1 }
        XCTAssertEqual(stored, ["sk-ant-good"])
        XCTAssertEqual(model.apiKeySave, .saved)
        XCTAssertEqual(model.apiKeyInput, "")
        XCTAssertFalse(model.checkingKey)
    }

    func testOnboardingSaysWhyAKeyWasRefused() async {
        let model = engineModel()
        var refreshed = 0
        model.checkAPIKey = { _ in .invalid("Anthropic refused this key.") }
        model.storeAPIKey = store(true)
        model.refreshEngine = { refreshed += 1 }
        model.apiKeyInput = "sk-ant-bad"
        model.primary()
        await waitUntil { refreshed == 1 }
        XCTAssertTrue(stored.isEmpty)
        XCTAssertEqual(model.apiKeySave?.note?.text, "Anthropic refused this key.")
    }

    func testOnboardingKeepsTheKeyWhenTheKeychainRefuses() async {
        let model = engineModel()
        var refreshed = 0
        model.checkAPIKey = { _ in .valid }
        model.storeAPIKey = store(false)
        model.refreshEngine = { refreshed += 1 }
        model.apiKeyInput = "sk-ant-good"
        model.primary()
        await waitUntil { refreshed == 1 }
        XCTAssertEqual(model.apiKeySave, .notSaved)
        XCTAssertEqual(model.apiKeyInput, "sk-ant-good", "Left in the field, so pressing again retries")
    }

    func testTheButtonReplacesAnEngineFromANewerVersion() {
        let model = OnboardingModel(progress: OnboardingProgress(step: .engine, history: [.accessibility]),
                                    conditions: OnboardingConditions(accessibility: true))
        var written: [EngineKind] = []
        model.writeEngine = { written.append($0) }
        model.savedEngineChanged(.claudeCode, needsChoice: true, status: .problem("Pick a model"))
        XCTAssertFalse(model.engineChosen, "Nothing is picked over an engine this version doesn't know")
        model.choose(.claudeCode)
        XCTAssertTrue(model.isChosen(.claudeCode))
        XCTAssertEqual(written, [], "Picking only highlights")
        model.primary()
        XCTAssertEqual(written, [.claudeCode], "The button saves it, though it's what the setting already reads as")
    }
}

/// Records any request that reaches URLSession's loading system and fails it.
private final class RefuseRequests: URLProtocol {
    nonisolated(unsafe) static var seen: [String] = []
    override class func canInit(with request: URLRequest) -> Bool {
        seen.append(request.url?.absoluteString ?? "?")
        return false
    }
}
