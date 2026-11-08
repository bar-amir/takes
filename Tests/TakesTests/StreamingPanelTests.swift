import AppKit
import XCTest
@testable import Takes

/// While takes stream in, the panel shows a card for every take it asked for, even before that take has any
/// text. Drawing one of those placeholder cards used to read `model.takes[index]` and crash Takes.
@MainActor
final class StreamingPanelTests: XCTestCase {
    func testPlaceholderCardsDrawWhileTakesStream() throws {
        _ = NSApplication.shared
        let model = PanelModel()
        let draft = "thurs is hard for me, investor call most of the day. fri morning works"
        model.reset(focus: FocusSnapshot(app: nil, text: draft, source: .field, caretRect: nil), presetID: Store.shared.presets.first?.id)
        model.screen = .takes
        model.sourceDraft = draft
        model.running = true
        model.takeCount = 3
        model.takes = ["Thursday is tough for me, since I have an investor call"]
        XCTAssertGreaterThan(model.cardCount, model.takes.count, "the test needs placeholder cards")
        let height = Snapshot.fittedHeight(model, width: 1060)
        XCTAssertNotNil(Snapshot.bitmap(of: PanelRootView(model: model), size: CGSize(width: 1060, height: height)))
    }
}
