import XCTest
@testable import Takes

/// A text box Takes didn't read (too long, a password field) used to show "· 0 words" in the compose row, which
/// reads as an empty box. It shows no count until something is written in the panel.
@MainActor
final class UnreadBoxWordCountTests: XCTestCase {
    private func model(_ source: FocusSnapshot.Source, text: String = "") -> PanelModel {
        let model = PanelModel()
        model.reset(focus: FocusSnapshot(app: nil, text: text, source: source, caretRect: nil), presetID: nil)
        return model
    }

    func testNoCountForABoxThatWasntRead() {
        XCTAssertFalse(model(.tooLong).showsWordCount)
        XCTAssertFalse(model(.secure).showsWordCount)
    }

    func testACountOnceSomethingIsWritten() {
        let tooLong = model(.tooLong)
        tooLong.draft = "just this part"
        XCTAssertTrue(tooLong.showsWordCount)
    }

    func testOtherBoxesKeepTheirCount() {
        XCTAssertTrue(model(.field).showsWordCount, "An empty box that was read says 0 words")
        XCTAssertTrue(model(.field, text: "hello there").showsWordCount)
        XCTAssertTrue(model(.selection, text: "hello").showsWordCount)
    }
}
