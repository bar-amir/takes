import AppKit
import ApplicationServices
import Carbon
import XCTest

@testable import Takes

/// Answers `FocusReader`'s accessibility questions in an app's place, and keeps a list of what was asked.
private final class FakeApp {
    var values: [String: Any] = [:]
    var errors: [String: AXError] = [:]
    var settable: [String: Bool] = [:]
    var setResult = AXError.success
    /// Called as each attribute is asked for, before it is answered.
    var onAsk: (String) -> Void = { _ in }
    private(set) var asked: [String] = []
    private(set) var sets: [String] = []

    var client: AXClient {
        AXClient(
            attribute: { [unowned self] _, attribute in
                asked.append(attribute)
                onAsk(attribute)
                if let error = errors[attribute] { return (nil, error) }
                guard let value = values[attribute] else { return (nil, .attributeUnsupported) }
                return (value as CFTypeRef, .success)
            },
            parameterized: { [unowned self] _, attribute, _ in
                asked.append(attribute)
                return nil
            },
            isSettable: { [unowned self] _, attribute in settable[attribute] },
            set: { [unowned self] _, attribute, _ in
                sets.append(attribute)
                return setResult
            })
    }

    static func range(_ location: Int, _ length: Int) -> AXValue {
        var range = CFRange(location: location, length: length)
        return AXValueCreate(.cfRange, &range)!
    }

    static func frame(_ rect: CGRect) -> AXValue {
        var rect = rect
        return AXValueCreate(.cgRect, &rect)!
    }
}

/// `FocusReader.read` against a fake app and a clipboard of the test's own: what it asks, which keys it would
/// send, and what it leaves behind. No real app is read or typed into.
@MainActor
final class FocusReadTests: XCTestCase {
    private var app: FakeApp!
    private var pasteboard: NSPasteboard!
    /// Keys the read would send: "⌘A", "⌘C", "→".
    private var keys: [String] = []
    private var ownWrites: [ClipboardFreshness.OwnWrite] = []
    /// What the fake app puts on the clipboard when it gets ⌘C; nil copies nothing.
    private var copies: String?
    // An element that is never asked anything for real: every question goes to `app`.
    private let element = AXUIElementCreateApplication(1)
    private let long = String(repeating: "word ", count: 2001)

    override func setUp() async throws {
        app = FakeApp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.baramir.takes.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("what the user copied", forType: .string)
        keys = []
        ownWrites = []
        copies = nil
        FocusReader.ax = app.client
        var env = FocusReader.CopyEnvironment()
        env.pasteboard = pasteboard
        env.press = { [unowned self] key, command in
            let names = [kVK_ANSI_A: "A", kVK_ANSI_C: "C", kVK_RightArrow: "→"]
            keys.append((command ? "⌘" : "") + (names[Int(key)] ?? "?"))
            if command, Int(key) == kVK_ANSI_C, let copies {
                pasteboard.clearContents()
                pasteboard.setString(copies, forType: .string)
            }
        }
        env.waitForModifierRelease = {}
        env.clipboardWillChange = {}
        env.clipboardChanged = { [unowned self] in ownWrites.append($0) }
        env.copyWait = 0.05
        env.lateWait = 0.4
        FocusReader.copyEnvironment = env
    }

    override func tearDown() async throws {
        Paster.settleOwedRestore()
        FocusReader.ax = .live
        FocusReader.copyEnvironment = FocusReader.CopyEnvironment()
        FocusReader.budget = nil
        pasteboard.releaseGlobally()
    }

    private func read(_ prefill: Prefill = .fieldText, allowCopy: Bool = true) -> FocusSnapshot {
        FocusReader.read(element, in: nil, prefill: prefill, allowCopy: allowCopy).0
    }

    /// A text box that says nothing about its text, so it can only be read by copying.
    private func unreadableBox(selection: AXValue? = nil) {
        app.values[kAXRoleAttribute] = "AXTextArea"
        if let selection { app.values[kAXSelectedTextRangeAttribute] = selection }
    }

    private func clipboard() -> String? { pasteboard.string(forType: .string) }

    // MARK: Password fields

    func testPasswordFieldIsNotAskedForItsTextSelectionOrCaret() {
        app.values[kAXRoleAttribute] = "AXTextField"
        app.values[kAXSubroleAttribute] = "AXSecureTextField"
        app.values[kAXValueAttribute] = "hunter2"
        app.values[kAXSelectedTextAttribute] = "hunter2"
        app.values[kAXSelectedTextRangeAttribute] = FakeApp.range(0, 7)
        app.values["AXFrame"] = FakeApp.frame(CGRect(x: 100, y: 100, width: 300, height: 24))

        for prefill in [Prefill.fieldText, .selectionOnly, .empty] {
            let snapshot = read(prefill)
            XCTAssertEqual(snapshot.source, .secure, "\(prefill)")
            XCTAssertEqual(snapshot.text, "")
            XCTAssertNotNil(snapshot.caretRect, "its frame still places the panel")
        }
        // What it is, and where it is. Nothing about what is in it.
        XCTAssertEqual(Set(app.asked), [kAXRoleAttribute, kAXSubroleAttribute, "AXFrame"])
        XCTAssertTrue(keys.isEmpty, "never selected or copied from")
        XCTAssertEqual(clipboard(), "what the user copied")
    }

    // MARK: A text box over the limit

    func testBoxOverTheLimitIsReportedAndNeverSelected() {
        app.values[kAXRoleAttribute] = "AXTextArea"
        app.values[kAXValueAttribute] = long
        let snapshot = read()
        XCTAssertEqual(snapshot.source, .tooLong)
        XCTAssertEqual(snapshot.text, "")
        XCTAssertEqual(snapshot.method, "too long (AXValue)")
        XCTAssertTrue(keys.isEmpty, "no ⌘A for a box known to be over the limit")
    }

    func testBoxOverTheLimitByItsCharacterCountIsNeverSelected() {
        app.values[kAXRoleAttribute] = "AXTextArea"
        app.values[kAXNumberOfCharactersAttribute] = 25_000
        XCTAssertEqual(read().source, .tooLong)
        XCTAssertTrue(keys.isEmpty)
    }

    func testSelectionInsideALongBoxIsStillRead() {
        app.values[kAXRoleAttribute] = "AXTextArea"
        app.values[kAXValueAttribute] = long
        app.values[kAXSelectedTextAttribute] = "just this paragraph"
        let snapshot = read()
        XCTAssertEqual(snapshot.source, .selection)
        XCTAssertEqual(snapshot.text, "just this paragraph")
        XCTAssertTrue(snapshot.editable)
    }

    // MARK: Reading through accessibility

    func testBoxWithAValueIsReadWithoutKeys() {
        app.values[kAXRoleAttribute] = "AXTextArea"
        app.values[kAXValueAttribute] = "ya thursday works\n"
        let snapshot = read()
        XCTAssertEqual(snapshot.source, .field)
        XCTAssertEqual(snapshot.text, "ya thursday works")
        XCTAssertEqual(snapshot.method, "AXValue")
        XCTAssertTrue(keys.isEmpty)
    }

    func testSelectionOnAWebPageIsReadButNotEditable() {
        app.values[kAXRoleAttribute] = "AXWebArea"
        app.values[kAXSelectedTextAttribute] = "a sentence on a page"
        app.settable = [kAXValueAttribute: false, kAXSelectedTextAttribute: false]
        let snapshot = read()
        XCTAssertEqual(snapshot.source, .selection)
        XCTAssertFalse(snapshot.editable)
        XCTAssertTrue(keys.isEmpty)
    }

    func testStartWithTheSelectionAndNothingSelectedIsNotAnEmptyBox() {
        app.values[kAXRoleAttribute] = "AXTextArea"
        app.values[kAXValueAttribute] = "text that was not selected"
        let snapshot = read(.selectionOnly)
        XCTAssertEqual(snapshot.method, FocusSnapshot.noSelection)
        XCTAssertEqual(snapshot.text, "")
        XCTAssertFalse(app.asked.contains(kAXValueAttribute), "only the selection is read")
        XCTAssertEqual(keys, ["⌘C"], "⌘C alone copies a selection the app doesn't report; never ⌘A")
    }

    // MARK: An app that stops answering

    func testBoxThatCannotSayWhatItIsIsNotRead() {
        app.errors[kAXRoleAttribute] = .cannotComplete
        app.values[kAXValueAttribute] = "text of a box in a hung app"
        let snapshot = read()
        XCTAssertEqual(snapshot.source, .none)
        XCTAssertEqual(snapshot.method, "app not answering")
        XCTAssertEqual(app.asked, [kAXRoleAttribute, kAXSubroleAttribute], "nothing more is asked of it")
        XCTAssertTrue(keys.isEmpty)
    }

    func testNoQuestionIsSentOnceTheReadsTimeIsUp() {
        app.values[kAXRoleAttribute] = "AXTextArea"
        app.values[kAXValueAttribute] = "ya thursday works"
        FocusReader.budget = ReadBudget(seconds: 0)
        let snapshot = read()
        XCTAssertEqual(snapshot.method, "app not answering")
        XCTAssertTrue(app.asked.isEmpty, "a hung app costs the budget, not a timeout per question")
        XCTAssertTrue(keys.isEmpty)
    }

    func testNoKeysGoToAnAppThatWentQuietHalfWay() {
        // It says what it is, then stops answering: the time runs out while its text is being asked for.
        unreadableBox()
        app.onAsk = { attribute in
            if attribute == kAXValueAttribute { FocusReader.budget = ReadBudget(seconds: 0) }
        }
        FocusReader.budget = ReadBudget(seconds: 60)
        let snapshot = read()
        XCTAssertEqual(snapshot.source, .none)
        XCTAssertEqual(snapshot.method, "app not answering")
        XCTAssertTrue(keys.isEmpty, "⌘A ⌘C would be acted on later, with nobody watching")
    }

    func testReadBudgetStopsAskingWhenItsTimeIsUp() {
        let start = Date()
        let budget = ReadBudget(seconds: 1.5, from: start)
        XCTAssertTrue(budget.mayAsk(now: start.addingTimeInterval(1.4)))
        XCTAssertFalse(budget.mayAsk(now: start.addingTimeInterval(1.5)))
        // The wait for an Electron app's first tree build still fits in it.
        XCTAssertGreaterThanOrEqual(FocusReader.readBudget, Double(FocusReader.focusRetries) * 0.08 + 0.5)
    }

    // MARK: The ⌘A ⌘C fallback

    func testCopyThatIsUsedLeavesNothingSelected() {
        unreadableBox(selection: FakeApp.range(4, 0))
        copies = "ya thursday works"
        let snapshot = read()
        XCTAssertEqual(snapshot.source, .field)
        XCTAssertEqual(snapshot.text, "ya thursday works")
        XCTAssertEqual(snapshot.method, "copy (⌘A ⌘C)")
        XCTAssertEqual(keys, ["⌘A", "⌘C"])
        XCTAssertEqual(app.sets, [kAXSelectedTextRangeAttribute], "the caret goes back where it was")
        XCTAssertEqual(clipboard(), "what the user copied")
        XCTAssertEqual(ownWrites, [.borrowed])
    }

    func testAppThatCannotPutTheSelectionBackGetsTheCaretMovedToTheEnd() {
        unreadableBox()
        copies = "ya thursday works"
        XCTAssertEqual(read().text, "ya thursday works")
        XCTAssertEqual(keys, ["⌘A", "⌘C", "→"])

        // The same when the app refuses to set it.
        keys = []
        unreadableBox(selection: FakeApp.range(4, 0))
        app.setResult = .attributeUnsupported
        XCTAssertEqual(read().text, "ya thursday works")
        XCTAssertEqual(keys, ["⌘A", "⌘C", "→"])
    }

    func testCopyOverTheLimitIsTooLongAndLeavesTheBoxAsItWas() {
        unreadableBox(selection: FakeApp.range(4, 0))
        copies = long
        let snapshot = read()
        XCTAssertEqual(snapshot.source, .tooLong)
        XCTAssertEqual(snapshot.text, "")
        XCTAssertEqual(app.sets, [kAXSelectedTextRangeAttribute])
        XCTAssertEqual(clipboard(), "what the user copied")
    }

    func testCopyThatNeverComesReadsAsEmptyAndDropsTheSelection() async {
        unreadableBox(selection: FakeApp.range(4, 0))
        let snapshot = read()
        XCTAssertEqual(snapshot.source, .field)
        XCTAssertEqual(snapshot.text, "")
        // → queues behind the ⌘A in a slow app; a selection put back now would be undone by it.
        XCTAssertEqual(keys, ["⌘A", "⌘C", "→"])
        XCTAssertTrue(app.sets.isEmpty)
        try? await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(clipboard(), "what the user copied")
        XCTAssertTrue(ownWrites.isEmpty, "nothing landed, nothing to put back")
    }

    func testCopyThatLandsLateIsUndone() async {
        unreadableBox()
        let snapshot = read()
        XCTAssertEqual(snapshot.text, "", "it missed the wait")
        // The slow app gets to the ⌘C a moment later.
        pasteboard.clearContents()
        pasteboard.setString("the whole box, copied late", forType: .string)
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(clipboard(), "what the user copied", "the user's clipboard is back")
        XCTAssertEqual(ownWrites, [.borrowed], "and it doesn't count as something they copied")
    }

    func testSomethingCopiedLongAfterTheReadIsLeftAlone() async {
        unreadableBox()
        _ = read()
        try? await Task.sleep(nanoseconds: 600_000_000)
        pasteboard.clearContents()
        pasteboard.setString("copied by the user later", forType: .string)
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(clipboard(), "copied by the user later")
        XCTAssertTrue(ownWrites.isEmpty)
    }

    func testLateCopyIsUndoneBeforeTheNextReadSavesTheClipboard() {
        unreadableBox()
        _ = read()
        pasteboard.clearContents()
        pasteboard.setString("the whole box, copied late", forType: .string)
        // Summoned again straight away: what this read saves and restores must be the user's clipboard.
        copies = "ya thursday works"
        XCTAssertEqual(read().text, "ya thursday works")
        XCTAssertEqual(clipboard(), "what the user copied")
    }

    func testReadRightAfterAPasteDoesNotSaveTheTakeAsTheUsersClipboard() async {
        // A paste whose restore is still waiting for the app to read the take.
        var env = Paster.Environment()
        env.pasteboard = pasteboard
        env.refocus = { _ in true }
        env.isFrontmost = { _ in true }
        env.heldModifiers = { [] }
        env.confirm = { _, _ in true }
        env.press = { _ in }
        env.clipboardWillChange = {}
        env.clipboardChanged = { _ in }
        env.note = { _, _ in }
        env.frontTimeout = 0.1
        env.settle = 0
        env.restoreDelay = 5
        let target = FocusSnapshot(app: nil, text: "", source: .field, caretRect: nil)
        let outcome = await withCheckedContinuation { continuation in
            Paster.paste("Thursday works for me.", into: target, replaceAll: false, restoreClipboard: true, environment: env) {
                continuation.resume(returning: $0)
            }
        }
        XCTAssertEqual(outcome, .pasted)
        XCTAssertEqual(clipboard(), "Thursday works for me.")

        // Summoned again at once, on a box that has to be copied from.
        unreadableBox()
        copies = "ya thursday works"
        XCTAssertEqual(read().text, "ya thursday works")
        XCTAssertEqual(clipboard(), "what the user copied", "not the take, and not lost")
    }

    func testFocusTestSendsNoKeys() {
        unreadableBox()
        copies = "ya thursday works"
        let snapshot = read(allowCopy: false)
        XCTAssertEqual(snapshot.source, .field)
        XCTAssertEqual(snapshot.text, "")
        XCTAssertTrue(keys.isEmpty)
    }

    // MARK: Another element standing in for the box

    private func snapshot(_ source: FocusSnapshot.Source, _ text: String, method: String) -> FocusSnapshot {
        FocusSnapshot(app: nil, text: text, source: source, caretRect: nil, method: method)
    }

    func testAnotherTextBoxWithTheSameTextStandsIn() {
        app.values[kAXRoleAttribute] = "AXTextArea"
        app.values[kAXValueAttribute] = "ya thursday works"
        let check = FocusReader.standsIn(element, for: snapshot(.field, "ya thursday works", method: "AXValue"))
        XCTAssertEqual(check, FocusReader.FieldCheck(focus: .equivalent, text: .same))
        XCTAssertTrue(FocusReader.mayPaste(replaceAll: true, check: check!))
    }

    func testAnotherTextBoxWithOtherTextDoesNot() {
        app.values[kAXRoleAttribute] = "AXTextArea"
        app.values[kAXValueAttribute] = "a draft in another chat"
        XCTAssertNil(FocusReader.standsIn(element, for: snapshot(.field, "ya thursday works", method: "AXValue")))
        // An empty box in another chat is not the box that held text.
        app.values[kAXValueAttribute] = "\n"
        XCTAssertNil(FocusReader.standsIn(element, for: snapshot(.field, "ya thursday works", method: "AXValue")))
    }

    func testAnEmptyBoxStandsInForOneThatWasEmpty() {
        app.values[kAXRoleAttribute] = "AXTextField"
        app.values[kAXValueAttribute] = "\n"
        let check = FocusReader.standsIn(element, for: snapshot(.field, "", method: "AXValue"))
        XCTAssertEqual(check?.focus, .equivalent)
        app.values[kAXValueAttribute] = "typed since"
        XCTAssertNil(FocusReader.standsIn(element, for: snapshot(.field, "", method: "AXValue")))
    }

    func testTheSameSelectionStandsInButNeverForAReplaceAll() {
        app.values[kAXRoleAttribute] = "AXTextArea"
        app.values[kAXSelectedTextAttribute] = "thursday"
        let check = FocusReader.standsIn(element, for: snapshot(.selection, "thursday", method: "AXSelectedText"))
        XCTAssertEqual(check, FocusReader.FieldCheck(focus: .equivalent))
        XCTAssertTrue(FocusReader.mayPaste(replaceAll: false, check: check!))
        XCTAssertFalse(FocusReader.mayPaste(replaceAll: true, check: check!), "a replace-all needs the text itself to match")
        app.values[kAXSelectedTextAttribute] = "friday"
        XCTAssertNil(FocusReader.standsIn(element, for: snapshot(.selection, "thursday", method: "AXSelectedText")))
    }

    func testOnlyATextBoxStandsInAndNeverAPasswordField() {
        app.values[kAXValueAttribute] = "ya thursday works"
        app.values[kAXRoleAttribute] = "AXWebArea"
        XCTAssertNil(FocusReader.standsIn(element, for: snapshot(.field, "ya thursday works", method: "AXValue")))
        app.values[kAXRoleAttribute] = "AXTextField"
        app.values[kAXSubroleAttribute] = "AXSecureTextField"
        XCTAssertNil(FocusReader.standsIn(element, for: snapshot(.field, "ya thursday works", method: "AXValue")))
        XCTAssertFalse(app.asked.contains(kAXValueAttribute), "a password field isn't read to find out")
    }

    func testTextThatCannotBeComparedNeverStandsIn() {
        app.values[kAXRoleAttribute] = "AXTextArea"
        app.values[kAXValueAttribute] = "ya thursday works"
        // Read by copying, not read at all, or not a box that was read.
        for snapshot in [
            snapshot(.field, "ya thursday works", method: "copy (⌘A ⌘C)"), snapshot(.field, "", method: "prefill off"),
            snapshot(.field, "", method: FocusSnapshot.noSelection), snapshot(.field, "", method: "editable, empty"),
            snapshot(.selection, "ya thursday works", method: "copy selection"), snapshot(.tooLong, "", method: "too long (AXValue)"),
            snapshot(.none, "", method: "not a text field"),
        ] {
            XCTAssertEqual(FocusReader.expected(of: snapshot), .unknown, snapshot.method)
            XCTAssertNil(FocusReader.standsIn(element, for: snapshot), snapshot.method)
        }
    }
}
