import ApplicationServices
import Carbon
import XCTest

@testable import Takes

/// The rules that keep Takes from losing text in another app: what counts as too long to read, what is never
/// read at all, and when a take may replace everything in a text box. All pure: no app is read or typed into.
@MainActor
final class TextSafetyTests: XCTestCase {
    private let long = String(repeating: "word ", count: 2001)

    private func focus(_ source: FocusSnapshot.Source, _ text: String = "", editable: Bool = true) -> FocusSnapshot {
        FocusSnapshot(app: nil, text: text, source: source, caretRect: nil, editable: editable)
    }

    // MARK: A text box over the limit

    func testTextOverTheLimitIsTooLongNotEmpty() {
        XCTAssertGreaterThan(long.count, FocusReader.maxPrefill)
        XCTAssertEqual(FocusReader.read(long, method: "AXValue"), .tooLong(method: "AXValue"))
        let atLimit = String(repeating: "a", count: FocusReader.maxPrefill)
        XCTAssertEqual(FocusReader.read(atLimit, method: "AXValue"), .text(atLimit, method: "AXValue"))
        // A blank value is still an empty box.
        XCTAssertEqual(FocusReader.read("\n", method: "AXValue"), .text("", method: "AXValue"))
    }

    func testBoxKnownToBeTooLongIsNeverSelectedAndCopied() {
        XCTAssertEqual(FocusReader.afterRead(.tooLong(method: "AXValue"), textBox: true), .tooLong(method: "too long (AXValue)"))
        // Select all and copy is only for a text box whose text couldn't be read at all.
        XCTAssertEqual(FocusReader.afterRead(.unreadable, textBox: true), .copyAll)
        XCTAssertEqual(FocusReader.afterRead(.unreadable, textBox: false), .notText)
        XCTAssertEqual(FocusReader.afterRead(.text("hi", method: "AXValue"), textBox: true), .use(text: "hi", method: "AXValue"))
    }

    func testCopiedTextOverTheLimitIsTooLongNotEmpty() {
        XCTAssertEqual(FocusReader.copied(long), .tooLong)
        XCTAssertEqual(FocusReader.copied("ya thursday works"), .text("ya thursday works"))
        XCTAssertEqual(FocusReader.copied(" \n "), .nothing)
        XCTAssertEqual(FocusReader.copied(nil), .nothing)
    }

    func testPanelSaysTheTextIsTooLong() {
        let model = PanelModel()
        model.refreshModels = { _ in }
        model.reset(focus: focus(.tooLong), presetID: nil)
        XCTAssertEqual(model.draft, "")
        XCTAssertEqual(model.sourceLabel, "The text is too long. Select part of it first")
        XCTAssertNotEqual(model.sourceLabel, "The field was empty")
        // Still true once a draft is typed into the panel.
        model.draft = "a new line"
        XCTAssertEqual(model.sourceLabel, "The text is too long. Select part of it first")

        model.reset(focus: focus(.field), presetID: nil)
        XCTAssertEqual(model.sourceLabel, "The field was empty")
    }

    func testNothingSelectedIsNotCalledAnEmptyField() {
        // "Start with: the selection", and nothing was selected: the box wasn't read, so it isn't known to be empty.
        let model = PanelModel()
        model.refreshModels = { _ in }
        model.reset(focus: focus(.field).read(FocusSnapshot.noSelection), presetID: nil)
        XCTAssertEqual(model.sourceLabel, "Nothing was selected")
        XCTAssertEqual(PanelController.pasteAction(for: model.focus), .paste(replaceAll: false))
    }

    func testPasteFromATooLongBoxNeverReplacesEverything() {
        XCTAssertEqual(PanelController.pasteAction(for: focus(.tooLong)), .paste(replaceAll: false))
        XCTAssertEqual(PanelController.pasteAction(for: focus(.tooLong, "text that was never read")), .paste(replaceAll: false))
    }

    func testReplaceAllIsOnlyForABoxWhoseTextWasRead() {
        XCTAssertEqual(PanelController.pasteAction(for: focus(.field, "ya thursday works")), .paste(replaceAll: true))
        XCTAssertEqual(PanelController.pasteAction(for: focus(.field)), .paste(replaceAll: false))
        XCTAssertEqual(PanelController.pasteAction(for: focus(.selection, "thursday")), .paste(replaceAll: false))
        XCTAssertEqual(PanelController.pasteAction(for: focus(.none, "x")), .paste(replaceAll: false))
        XCTAssertEqual(PanelController.pasteAction(for: focus(.secure, "x")), .paste(replaceAll: false))
        XCTAssertEqual(PanelController.pasteAction(for: nil), .paste(replaceAll: false))
    }

    func testInstantModeDoesNotWriteForATooLongBox() {
        XCTAssertEqual(InstantMode.start(text: "", source: .tooLong), .tooLong)
        XCTAssertEqual(InstantMode.start(text: "anything", source: .tooLong), .tooLong)
        let message = InstantMode.tooLongMessage(app: "Notes")
        XCTAssertTrue(message.contains("Notes"))
        XCTAssertTrue(message.contains("too much text"))
        XCTAssertTrue(message.contains("Select"))
    }

    // MARK: Password fields

    func testPasswordFieldsAreRecognised() {
        XCTAssertTrue(FocusReader.isSecure(subrole: "AXSecureTextField"))
        XCTAssertFalse(FocusReader.isSecure(subrole: "AXSearchField"))
        XCTAssertFalse(FocusReader.isSecure(subrole: "-"))
        XCTAssertFalse(FocusReader.isSecure(subrole: nil))
    }

    func testPasswordFieldIsNeverWrittenFromOrReplaced() {
        XCTAssertEqual(InstantMode.start(text: "", source: .secure), .openPanel)
        XCTAssertEqual(InstantMode.start(text: "hunter2", source: .secure), .openPanel)
        let model = PanelModel()
        model.refreshModels = { _ in }
        model.reset(focus: focus(.secure), presetID: nil)
        XCTAssertEqual(model.sourceLabel, "Takes doesn't read password fields")
    }

    // MARK: Text that can't be edited

    func testReadOnlyNeedsTheElementsOwnWord() {
        // A web page: it reports its selection and says neither it nor its value can be set.
        XCTAssertTrue(FocusReader.readOnly(textBox: false, settable: [false, false], editableAncestor: false))
        XCTAssertTrue(FocusReader.readOnly(textBox: false, settable: [nil, false], editableAncestor: false))
        // Anything that points to editing wins.
        XCTAssertFalse(FocusReader.readOnly(textBox: false, settable: [false, true], editableAncestor: false))
        XCTAssertFalse(FocusReader.readOnly(textBox: false, settable: [false, false], editableAncestor: true))
        XCTAssertFalse(FocusReader.readOnly(textBox: true, settable: [false, false], editableAncestor: false))
        // An element that says nothing either way gets the paste, as before.
        XCTAssertFalse(FocusReader.readOnly(textBox: false, settable: [nil, nil], editableAncestor: false))
    }

    func testTakeForReadOnlyTextIsCopiedNotPasted() {
        XCTAssertEqual(PanelController.pasteAction(for: focus(.selection, "from a web page", editable: false)), .copyOnly)
        let message = PanelController.notPastedMessage(.readOnly, app: "Safari", number: 2)
        XCTAssertEqual(message, "This text can't be edited. Take 2 is on the clipboard: press ⌘V")
    }

    func testInstantModeOpensThePanelForReadOnlyText() {
        XCTAssertEqual(InstantMode.start(text: "from a web page", source: .selection, editable: false), .openPanel)
        XCTAssertEqual(InstantMode.start(text: "from a text box", source: .selection, editable: true), .write(draft: "from a text box", replaceAll: false))
    }

    // MARK: Is it still the same text box?

    func testReplacingEverythingNeedsTheSameBoxWithTheSameText() {
        typealias Check = FocusReader.FieldCheck
        XCTAssertTrue(FocusReader.mayPaste(replaceAll: true, check: Check(focus: .same, text: .same)))
        // Text read by copying can't be compared; the same box is all there is to go on.
        XCTAssertTrue(FocusReader.mayPaste(replaceAll: true, check: Check(focus: .same, text: .notCompared)))
        XCTAssertFalse(FocusReader.mayPaste(replaceAll: true, check: Check(focus: .same, text: .changed)))
        XCTAssertFalse(FocusReader.mayPaste(replaceAll: true, check: Check(focus: .same, text: .unreadable)))
        // Another chat, or an app that can't say what has focus: never ⌘A ⌘V.
        XCTAssertFalse(FocusReader.mayPaste(replaceAll: true, check: Check(focus: .other)))
        XCTAssertFalse(FocusReader.mayPaste(replaceAll: true, check: Check(focus: .unknown)))
    }

    func testAnotherElementIsReplacedOnlyWhenItsTextMatched() {
        typealias Check = FocusReader.FieldCheck
        // The app built its text box anew while the panel had the keyboard: same text, different element.
        XCTAssertTrue(FocusReader.mayPaste(replaceAll: true, check: Check(focus: .equivalent, text: .same)))
        for text in [Check.Text.notCompared, .changed, .unreadable] {
            XCTAssertFalse(FocusReader.mayPaste(replaceAll: true, check: Check(focus: .equivalent, text: text)), "\(text)")
        }
        // A paste at the caret or over the selection: the element stood in because its content matched.
        XCTAssertTrue(FocusReader.mayPaste(replaceAll: false, check: Check(focus: .equivalent)))
    }

    func testWhatAnotherElementMustStillHold() {
        XCTAssertEqual(FocusReader.expected(of: focus(.field, "ya thursday works").read("AXValue")), .text("ya thursday works"))
        XCTAssertEqual(FocusReader.expected(of: focus(.field).read("AXValue")), .text(""), "a box that was empty must still be empty")
        XCTAssertEqual(FocusReader.expected(of: focus(.field).read("empty (character count)")), .text(""))
        XCTAssertEqual(FocusReader.expected(of: focus(.selection, "thursday").read("AXSelectedText")), .selection("thursday"))
        // After an instant paste the box is expected to hold the take.
        let after = focus(.field, "ya thursday works").read("AXValue").holding("Thursday works for me.")
        XCTAssertEqual(FocusReader.expected(of: after), .text("Thursday works for me."))
    }

    func testPasteAtTheCaretIsRefusedOnlyWhenAnotherBoxHasFocus() {
        typealias Check = FocusReader.FieldCheck
        XCTAssertTrue(FocusReader.mayPaste(replaceAll: false, check: Check(focus: .same)))
        XCTAssertTrue(FocusReader.mayPaste(replaceAll: false, check: Check(focus: .unknown)), "apps with thin accessibility keep working")
        XCTAssertFalse(FocusReader.mayPaste(replaceAll: false, check: Check(focus: .other)))
    }

    func testPasteIntoNoKnownAppIsNotChecked() {
        // Nothing was read from an app (no Accessibility access, or Takes itself in front): nothing to compare.
        XCTAssertTrue(FocusReader.confirmed(nil, replaceAll: false))
        XCTAssertTrue(FocusReader.confirmed(focus(.none), replaceAll: false))
    }

    func testFieldChangedToastLeavesTheTakeOnTheClipboard() {
        XCTAssertEqual(
            PanelController.notPastedMessage(.fieldChanged, app: "Slack", number: 1),
            "Couldn't confirm the text box in Slack. Take 1 is on the clipboard: press ⌘V")
        XCTAssertEqual(
            PanelController.notPastedMessage(.couldNotReturn, app: "Slack", number: 3),
            "Couldn't get back to Slack. Take 3 is on the clipboard: press ⌘V")
    }

    func testSnapshotAfterAnInstantPasteExpectsTheTake() {
        let after = focus(.field, "ya thursday works").holding("Thursday works for me.")
        XCTAssertEqual(after.text, "Thursday works for me.")
        XCTAssertEqual(after.source, .field)
        XCTAssertTrue(after.editable)
    }

    // MARK: Keys

    func testTheKeyThatDropsASelectionCarriesNoModifiers() {
        let events = Paster.plainKeyEvents(CGKeyCode(kVK_RightArrow))
        XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [Int64(kVK_RightArrow), Int64(kVK_RightArrow)])
        for event in events {
            XCTAssertTrue(event.flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate]).isEmpty)
        }
    }
}

private extension FocusSnapshot {
    /// The same snapshot, as read by `method`.
    func read(_ method: String) -> FocusSnapshot {
        FocusSnapshot(app: app, text: text, source: source, caretRect: caretRect, element: element, method: method, editable: editable)
    }
}
