import AppKit
import Carbon
import XCTest

@testable import Takes

private struct CutShortEngine: TakesEngine {
    var takes = ["Thursday works for me, but I need the specs by"]
    var cutShort = true

    func run(_ request: EngineRequest, onUpdate: @escaping @Sendable ([String]) -> Void) async throws -> EngineResult {
        EngineResult(takes: takes, wallMs: 10, firstTextMs: 5, cutShort: cutShort)
    }
}

/// Instant mode pastes a take nobody has seen yet, so it stops whenever the take or its target is in doubt.
/// The paste here is the real one (`InstantPaste` over `Paster.paste`), on a clipboard of the test's own with no
/// app to type into.
@MainActor
final class InstantSafetyTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var keys: [Int] = []
    private var frontmost = true
    private var confirmed = true
    private var heldModifiers: CGEventFlags = []
    private var pasteStarted = false
    /// How long the paste waits for the app to come forward and for held keys to be let go.
    private var frontTimeout: TimeInterval = 2
    private let request = InstantMode.request(preset: Store.defaultPresets[0], draft: "ya thursday works", rules: [])
    private let focus = FocusSnapshot(app: nil, text: "ya thursday works", source: .field, caretRect: nil)
    private let whole = CutShortEngine(takes: ["Thursday works for me."], cutShort: false)

    override func setUp() async throws {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.baramir.takes.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("what the user copied", forType: .string)
        keys = []
        frontmost = true
        confirmed = true
        heldModifiers = []
        pasteStarted = false
        frontTimeout = 2
    }

    override func tearDown() async throws {
        Paster.settleOwedRestore()
        pasteboard.releaseGlobally()
    }

    /// An instant run wired the way `InstantModeController` wires it, with the app and the clipboard faked.
    private func run(_ engine: CutShortEngine, stillInField: Bool = true, unchanged: Bool = false) -> InstantRun {
        var env = Paster.Environment()
        env.pasteboard = pasteboard
        env.refocus = { [unowned self] _ in
            pasteStarted = true
            return true
        }
        env.isFrontmost = { [unowned self] _ in frontmost }
        env.heldModifiers = { [unowned self] in heldModifiers }
        env.confirm = { [unowned self] _, _ in confirmed }
        env.press = { [unowned self] key in keys.append(Int(key)) }
        env.clipboardWillChange = {}
        env.clipboardChanged = { _ in }
        env.note = { _, _ in }
        env.frontTimeout = frontTimeout
        env.settle = 0
        env.confirmTimeout = 0.05
        env.restoreDelay = 0.05
        let paste = InstantPaste(focus: focus, replaceAll: true, restoreClipboard: true, environment: env)
        let run = InstantRun(
            engine: engine,
            paste: { take, done in paste.paste(take, done: done) },
            stillInField: { stillInField },
            unchanged: { _ in unchanged },
            notPasted: { paste.failure(take: $0) })
        paste.cancelled = { [weak run] in run?.isCancelled ?? true }
        return run
    }

    private func clipboard() -> String? { pasteboard.string(forType: .string) }

    // MARK: A take that was cut short

    func testCutShortTakeIsNotPasted() async {
        let outcome = await run(CutShortEngine()).run(request)
        XCTAssertEqual(outcome, .failed(.cutShort(take: "Thursday works for me, but I need the specs by")))
        XCTAssertTrue(keys.isEmpty)
        XCTAssertFalse(pasteStarted, "the paste isn't even begun")
        XCTAssertEqual(clipboard(), "what the user copied")
    }

    func testCutShortIsCheckedBeforeAnythingElse() async {
        // Even a take that reads the same as the draft so far is reported as cut off, not as "no changes needed".
        let outcome = await run(CutShortEngine(), stillInField: false, unchanged: true).run(request)
        XCTAssertEqual(outcome, .failed(.cutShort(take: "Thursday works for me, but I need the specs by")))
        XCTAssertTrue(keys.isEmpty)
    }

    func testCutShortFailureSaysSoAndKeepsTheTakeForThePanel() {
        let failure = InstantMode.Failure.cutShort(take: "half a take")
        XCTAssertEqual(failure.message(app: "Slack"), "The take was cut off before it was finished, so nothing was pasted.")
        XCTAssertEqual(failure.take, "half a take", "Open in Takes shows what was written")
    }

    // MARK: The paste itself

    func testWholeTakeReplacesTheBoxAndTheClipboardComesBack() async {
        let outcome = await run(whole).run(request)
        XCTAssertEqual(outcome, .pasted(take: "Thursday works for me."))
        XCTAssertEqual(keys, [kVK_ANSI_A, kVK_ANSI_V])
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(clipboard(), "what the user copied")
    }

    func testBoxThatChangedByTheTimeOfThePasteGetsNoKeys() async {
        // The run's own check passed, but once the app is back the text box isn't the one that was read.
        confirmed = false
        let outcome = await run(whole).run(request)
        XCTAssertEqual(outcome, .failed(.fieldChanged(take: "Thursday works for me.")))
        XCTAssertTrue(keys.isEmpty)
        XCTAssertEqual(clipboard(), "what the user copied", "the toast says nothing was pasted, so nothing is left behind")
    }

    func testAppThatWontComeBackGetsNoKeysAndTheTakeStaysOnTheClipboard() async {
        frontmost = false
        frontTimeout = 0.1
        let outcome = await run(whole).run(request)
        XCTAssertEqual(outcome, .failed(.couldNotReturn(take: "Thursday works for me.")))
        XCTAssertTrue(keys.isEmpty)
        XCTAssertEqual(clipboard(), "Thursday works for me.", "left there for ⌘V, as the toast says")
    }

    // MARK: Esc while the paste waits

    func testEscWhileThePasteWaitsForAHeldKeySendsNothing() async {
        // The hotkey's ⌥ is still down when the take arrives, so the paste waits for it.
        heldModifiers = .maskAlternate
        let run = run(whole)
        async let outcome = run.run(request)
        for _ in 0..<100 where !pasteStarted { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(pasteStarted)
        XCTAssertTrue(keys.isEmpty, "waiting for the key to be let go")

        run.cancel()
        heldModifiers = []
        let result = await outcome
        XCTAssertEqual(result, .cancelled)
        XCTAssertTrue(keys.isEmpty, "\"Cancelled. Nothing was pasted.\" has to be true")
        XCTAssertEqual(clipboard(), "what the user copied")
    }

    // MARK: A hotkey while instant mode is busy

    func testAnyHotKeyThatOpensThePanelStopsARunInProgress() {
        // The summon hotkey, a preset that doesn't write right away, or a preset picked in the menu.
        XCTAssertEqual(InstantMode.hotKeyAction(writesInstantly: false, running: true, resultShowing: false), .openPanel)
        XCTAssertEqual(InstantMode.hotKeyAction(writesInstantly: false, running: false, resultShowing: true), .openPanel)
        XCTAssertEqual(InstantMode.hotKeyAction(writesInstantly: false, running: false, resultShowing: false), .openPanel)
    }

    func testInstantHotKeyWritesOnceAndThenOpensItsResult() {
        XCTAssertEqual(InstantMode.hotKeyAction(writesInstantly: true, running: false, resultShowing: false), .write)
        XCTAssertEqual(InstantMode.hotKeyAction(writesInstantly: true, running: true, resultShowing: false), .keepWriting)
        XCTAssertEqual(InstantMode.hotKeyAction(writesInstantly: true, running: false, resultShowing: true), .openResult)
    }

    func testFailureFollowsWhatThePasteReported() {
        XCTAssertEqual(InstantMode.Failure.notPasted(.fieldChanged, take: "x"), .fieldChanged(take: "x"))
        XCTAssertEqual(InstantMode.Failure.notPasted(.couldNotReturn, take: "x"), .couldNotReturn(take: "x"))
    }
}
