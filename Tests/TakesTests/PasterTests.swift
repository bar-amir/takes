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
    private var notSent: [String] = []
    private let target = FocusSnapshot(app: nil, text: "ya thursday works", source: .field, caretRect: nil)

    override func setUp() async throws {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.baramir.takes.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("what the user copied", forType: .string)
        keys = []
        ownWrites = []
        notSent = []
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
    }

    /// An app that comes forward and still has the same text box, unless a test says otherwise.
    private func environment(
        frontmost: @escaping () -> Bool = { true }, boxThere: Bool = true,
        confirm: @escaping (Bool) -> Bool = { _ in true }
    ) -> Paster.Environment {
        var env = Paster.Environment()
        env.pasteboard = pasteboard
        env.refocus = { _ in boxThere }
        env.isFrontmost = { _ in frontmost() }
        env.heldModifiers = { [] }
        env.confirm = { _, replaceAll in confirm(replaceAll) }
        env.press = { [unowned self] key in keys.append(Int(key)) }
        env.clipboardWillChange = {}
        env.clipboardChanged = { [unowned self] in ownWrites.append($0) }
        env.notSent = { [unowned self] _, reason in notSent.append(reason) }
        env.frontTimeout = 0.1
        env.settle = 0
        env.confirmTimeout = 0.06
        env.restoreDelay = 0.05
        return env
    }

    private func paste(
        _ env: Paster.Environment, text: String = "Thursday works for me.", replaceAll: Bool = true,
        restore: Bool = true, keepTake: Bool = true
    ) async -> Paster.Outcome {
        await withCheckedContinuation { continuation in
            Paster.paste(
                text, into: target, replaceAll: replaceAll, restoreClipboard: restore, keepTakeIfFieldChanged: keepTake,
                environment: env
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
        XCTAssertEqual(notSent.count, 1)
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
        XCTAssertEqual(notSent, ["text box gone"])
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
        XCTAssertEqual(notSent, ["app not in front"])
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
