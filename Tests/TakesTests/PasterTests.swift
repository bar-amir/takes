import AppKit
import Carbon
import XCTest

@testable import Takes

/// `Paster.paste` against a clipboard of the test's own and no real app: which keys it would send, when it sends
/// none, and what it leaves on the clipboard.
@MainActor
final class PasterTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var keys: [Int] = []
    private var ownWrites: [ClipboardFreshness.OwnWrite] = []
    private var notes: [String] = []
    private var cancelled = false
    private var heldModifiers: CGEventFlags = []
    private let target = FocusSnapshot(app: nil, text: "ya thursday works", source: .field, caretRect: nil)

    override func setUp() async throws {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.baramir.takes.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("what the user copied", forType: .string)
        keys = []
        ownWrites = []
        notes = []
        cancelled = false
        heldModifiers = []
    }

    override func tearDown() async throws {
        // A restore still waiting belongs to this test's clipboard, not the next one's.
        Paster.settleOwedRestore()
        pasteboard.releaseGlobally()
    }

    /// An app that comes forward and still has the same text box, unless a test says otherwise.
    private func environment(
        frontmost: @escaping () -> Bool = { true }, boxThere: Bool = true, frontTimeout: TimeInterval = 0.1,
        restoreDelay: TimeInterval = 0.05, confirm: @escaping (Bool) -> Bool = { _ in true }
    ) -> Paster.Environment {
        var env = Paster.Environment()
        env.pasteboard = pasteboard
        env.refocus = { _ in boxThere }
        env.isFrontmost = { _ in frontmost() }
        env.heldModifiers = { [unowned self] in heldModifiers }
        env.confirm = { _, replaceAll in confirm(replaceAll) }
        env.press = { [unowned self] key in keys.append(Int(key)) }
        env.clipboardWillChange = {}
        env.clipboardChanged = { [unowned self] in ownWrites.append($0) }
        env.note = { [unowned self] _, entry in notes.append(entry) }
        env.verdict = { "what the check found" }
        env.frontTimeout = frontTimeout
        env.settle = 0
        env.confirmTimeout = 0.06
        env.restoreDelay = restoreDelay
        return env
    }

    private func paste(
        _ env: Paster.Environment, text: String = "Thursday works for me.", replaceAll: Bool = true,
        restore: Bool = true, keepTake: Bool = true
    ) async -> Paster.Outcome {
        await withCheckedContinuation { continuation in
            Paster.paste(
                text, into: target, replaceAll: replaceAll, restoreClipboard: restore, keepTakeIfFieldChanged: keepTake,
                cancelled: { [unowned self] in cancelled }, environment: env
            ) { continuation.resume(returning: $0) }
        }
    }

    private func settle() async { try? await Task.sleep(nanoseconds: 200_000_000) }

    // MARK: Pasting

    func testReplaceAllSendsSelectAllThenPaste() async {
        let outcome = await paste(environment())
        XCTAssertEqual(outcome, .pasted)
        XCTAssertEqual(keys, [kVK_ANSI_A, kVK_ANSI_V])
        XCTAssertEqual(pasteboard.string(forType: .string), "Thursday works for me.", "the app reads the take from the clipboard")
    }

    func testEveryPasteLeavesALineSayingWhichCheckLetItThrough() async {
        _ = await paste(environment())
        XCTAssertEqual(notes, ["paste sent\twhat the check found"])
    }

    func testPasteAtTheCaretSendsOnlyPaste() async {
        let outcome = await paste(environment(), replaceAll: false)
        XCTAssertEqual(outcome, .pasted)
        XCTAssertEqual(keys, [kVK_ANSI_V])
    }

    // MARK: When the text box can't be confirmed

    func testNoKeysWhenTheBoxIsNotConfirmedAndTheTakeStaysOnTheClipboard() async {
        let outcome = await paste(environment(confirm: { _ in false }))
        XCTAssertEqual(outcome, .fieldChanged)
        XCTAssertTrue(keys.isEmpty, "nothing is typed into another text box")
        await settle()
        XCTAssertEqual(pasteboard.string(forType: .string), "Thursday works for me.")
        XCTAssertEqual(ownWrites, [.take])
        XCTAssertEqual(notes, ["paste not sent\twhat the check found"])
    }

    func testNoKeysWhenTheBoxIsGone() async {
        var asked = false
        let outcome = await paste(
            environment(
                boxThere: false,
                confirm: { _ in
                    asked = true; return true
                }))
        XCTAssertEqual(outcome, .fieldChanged)
        XCTAssertTrue(keys.isEmpty)
        XCTAssertFalse(asked, "a box the app says is gone is not asked about again")
        XCTAssertEqual(notes, ["paste not sent\ttext box gone"])
    }

    func testTheCheckKnowsWhetherThePasteReplacesEverything() async {
        var seen: [Bool] = []
        _ = await paste(
            environment(confirm: {
                seen.append($0); return true
            }), replaceAll: true)
        _ = await paste(
            environment(confirm: {
                seen.append($0); return true
            }), replaceAll: false)
        XCTAssertEqual(seen, [true, false])
    }

    func testTheBoxMayTakeAMomentToReportFocusAgain() async {
        var asks = 0
        let outcome = await paste(
            environment(confirm: { _ in
                asks += 1; return asks >= 2
            }))
        XCTAssertEqual(outcome, .pasted)
        XCTAssertEqual(keys, [kVK_ANSI_A, kVK_ANSI_V])
    }

    func testCallerThatSaysNothingWasPastedGetsTheClipboardBack() async {
        let outcome = await paste(environment(confirm: { _ in false }), keepTake: false)
        XCTAssertEqual(outcome, .fieldChanged)
        XCTAssertTrue(keys.isEmpty)
        XCTAssertEqual(pasteboard.string(forType: .string), "what the user copied")
        XCTAssertEqual(ownWrites, [.take, .putBack])
    }

    // MARK: When the app can't be brought back

    func testNoKeysWhenTheAppIsNotInFront() async {
        let outcome = await paste(environment(frontmost: { false }))
        XCTAssertEqual(outcome, .couldNotReturn)
        XCTAssertTrue(keys.isEmpty)
        await settle()
        XCTAssertEqual(pasteboard.string(forType: .string), "Thursday works for me.", "left there on purpose, for ⌘V")
        XCTAssertEqual(notes, ["paste not sent\tapp not in front"])
    }

    func testNoKeysWhenTheAppLeavesTheFrontDuringTheCheck() async {
        var front = true
        let outcome = await paste(
            environment(
                frontmost: { front },
                confirm: { _ in
                    front = false; return true
                }))
        XCTAssertEqual(outcome, .couldNotReturn)
        XCTAssertTrue(keys.isEmpty)
    }

    // MARK: A paste that is called off

    func testCancelledPasteSendsNoKeysAndPutsTheClipboardBack() async {
        cancelled = true
        let outcome = await paste(environment())
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertTrue(keys.isEmpty)
        XCTAssertEqual(pasteboard.string(forType: .string), "what the user copied")
        XCTAssertEqual(ownWrites, [.take, .putBack])
        XCTAssertEqual(notes, ["paste not sent\tcancelled"])
    }

    func testCancelledPastePutsTheClipboardBackEvenWhenRestoreIsOff() async {
        cancelled = true
        let outcome = await paste(environment(), restore: false)
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(pasteboard.string(forType: .string), "what the user copied", "nothing was pasted, so nothing is left behind")
    }

    func testPasteCancelledWhileItWaitsForAHeldKeySendsNothing() async {
        // ⌥ is still down, so the paste waits. Esc arrives meanwhile; then the key is let go.
        heldModifiers = .maskAlternate
        async let outcome = paste(environment(frontTimeout: 2))
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(keys.isEmpty, "still waiting")
        cancelled = true
        heldModifiers = []
        let result = await outcome
        XCTAssertEqual(result, .cancelled)
        XCTAssertTrue(keys.isEmpty)
        XCTAssertEqual(pasteboard.string(forType: .string), "what the user copied")
    }

    func testPasteCancelledDuringTheLastCheckSendsNothing() async {
        let callOffDuringTheCheck: (Bool) -> Bool = { [unowned self] _ in
            cancelled = true
            return true
        }
        let outcome = await paste(environment(confirm: callOffDuringTheCheck))
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertTrue(keys.isEmpty)
    }

    // MARK: The user's clipboard

    func testClipboardComesBackAfterAPaste() async {
        _ = await paste(environment())
        await settle()
        XCTAssertEqual(pasteboard.string(forType: .string), "what the user copied")
        XCTAssertEqual(ownWrites, [.take, .putBack])
    }

    func testSomethingCopiedMeanwhileIsNotOverwritten() async {
        _ = await paste(environment())
        // Copied in the moment between the paste and the restore.
        pasteboard.clearContents()
        pasteboard.setString("copied just after the paste", forType: .string)
        await settle()
        XCTAssertEqual(pasteboard.string(forType: .string), "copied just after the paste")
        XCTAssertEqual(ownWrites, [.take], "nothing was put back")
    }

    func testClipboardIsLeftAloneWhenRestoreIsOff() async {
        _ = await paste(environment(), restore: false)
        await settle()
        XCTAssertEqual(pasteboard.string(forType: .string), "Thursday works for me.")
        XCTAssertEqual(ownWrites, [.take])
    }

    func testAnEmptyClipboardComesBackEmpty() async {
        pasteboard.clearContents()
        _ = await paste(environment())
        await settle()
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testRestoreStillOwedIsMadeBeforeTheClipboardIsSavedAgain() async {
        // A second paste right behind the first: what it saves must be the user's clipboard, not the first take.
        _ = await paste(environment(restoreDelay: 5), text: "First take.")
        XCTAssertEqual(pasteboard.string(forType: .string), "First take.", "not put back yet")
        _ = await paste(environment(), text: "Second take.")
        await settle()
        XCTAssertEqual(pasteboard.string(forType: .string), "what the user copied")
        XCTAssertEqual(ownWrites, [.take, .putBack, .take, .putBack])
    }

    func testRestoreStillOwedCanBeMadeAtOnce() async {
        _ = await paste(environment(restoreDelay: 5))
        Paster.settleOwedRestore()
        XCTAssertEqual(pasteboard.string(forType: .string), "what the user copied")
        // Asking again does nothing more.
        pasteboard.clearContents()
        pasteboard.setString("copied since", forType: .string)
        Paster.settleOwedRestore()
        XCTAssertEqual(pasteboard.string(forType: .string), "copied since")
    }

    func testRestoreOnlyWhileTheClipboardIsStillTakes() {
        let saved = Paster.snapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("a take", forType: .string)
        let ours = pasteboard.changeCount
        pasteboard.clearContents()
        pasteboard.setString("copied since", forType: .string)
        XCTAssertFalse(Paster.restore(saved, to: pasteboard, ifCount: ours))
        XCTAssertEqual(pasteboard.string(forType: .string), "copied since")
        XCTAssertTrue(Paster.restore(saved, to: pasteboard, ifCount: pasteboard.changeCount))
        XCTAssertEqual(pasteboard.string(forType: .string), "what the user copied")
    }
}
