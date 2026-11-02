import AppKit
import XCTest
@testable import Takes

/// Ori: "the takes window spacing looks off and uneven". Renders the takes screen and measures the white gaps
/// down one column and across one row, so a padding that drifts off the `Spacing` scale fails here.
@MainActor
final class PanelSpacingTests: XCTestCase {
    private let width: CGFloat = 1060

    private func takesScreen() throws -> (rep: NSBitmapImageRep, scale: CGFloat) {
        _ = NSApplication.shared
        let model = PanelModel()
        let draft = "ya thursday works but i need the specs by wed eod otherwise qa slips again, also can someone own the release notes this time"
        model.reset(focus: FocusSnapshot(app: nil, text: draft, source: .field, caretRect: nil), presetID: Store.shared.presets.first?.id)
        model.screen = .takes
        model.sourceDraft = draft
        model.takes = [
            "Thursday works for me. One ask: I need the specs by Wednesday EOD, otherwise QA slips again. Also, can someone own the release notes this time?",
            "Sure, Thursday it is. I'll need the specs by Wednesday EOD so QA doesn't slip again. Could someone take the release notes this round?",
            "Thursday's fine as long as specs land by Wed EOD (QA slipped last time without them).",
        ]
        model.timing = "first words 1.3 s · all takes 2.8 s"
        let height = Snapshot.fittedHeight(model, width: width)
        let rep = try XCTUnwrap(Snapshot.bitmap(of: PanelRootView(model: model), size: CGSize(width: width, height: height)))
        return (rep, CGFloat(rep.pixelsWide) / width)
    }

    /// Lengths in points of the runs of background (white) and other pixels along a line.
    private func runs(_ rep: NSBitmapImageRep, scale: CGFloat, column x: CGFloat? = nil, row y: CGFloat? = nil) -> [(white: Bool, length: CGFloat)] {
        let count = x != nil ? rep.pixelsHigh : rep.pixelsWide
        var result: [(white: Bool, length: CGFloat)] = []
        for i in 0..<count {
            let px = x.map { Int($0 * scale) } ?? i, py = y.map { Int($0 * scale) } ?? i
            let color = rep.colorAt(x: px, y: py)?.usingColorSpace(.sRGB)
            let white = (color?.redComponent ?? 0) > 0.98 && (color?.greenComponent ?? 0) > 0.98 && (color?.blueComponent ?? 0) > 0.98
            if let last = result.last, last.white == white {
                result[result.count - 1].length += 1 / scale
            } else {
                result.append((white, 1 / scale))
            }
        }
        return result
    }

    /// Take 3's left edge: three equal columns between the gutters, `Spacing.section` apart.
    private var thirdCardLeft: CGFloat {
        let card = (width - 2 * Spacing.gutter - 2 * Spacing.section) / 3
        return Spacing.gutter + 2 * (card + Spacing.section)
    }

    func testVerticalGapsFollowTheScale() throws {
        let (rep, scale) = try takesScreen()
        // Down take 3's left padding, clear of the cards' rounded corners and of any text: the header is blank
        // there, then the draft strip, the gap, take 3, the gap, the refine bar, the gap.
        let whites = runs(rep, scale: scale, column: thirdCardLeft + 14).filter(\.white).map(\.length)
        XCTAssertGreaterThanOrEqual(whites.count, 6, "\(whites)")
        XCTAssertEqual(whites[0], 2 * Spacing.bar + Spacing.control, accuracy: 1, "header \(whites)")
        XCTAssertEqual(whites[1], Spacing.section, accuracy: 1, "above the cards \(whites)")
        XCTAssertEqual(whites[3], Spacing.section, accuracy: 1, "between the cards and the refine bar \(whites)")
        XCTAssertEqual(whites[5], Spacing.section, accuracy: 1, "below the refine bar \(whites)")
    }

    func testSideGutterAndCardGapFollowTheScale() throws {
        let (rep, scale) = try takesScreen()
        // A row through the cards' top padding. The selected take 1's glow tints its own surroundings, so the
        // measured gap is take 2 to take 3, and the gutter is the right one.
        let top = try cardsTop(rep, scale: scale)
        let whites = runs(rep, scale: scale, row: top + 14).filter(\.white).map(\.length)
        XCTAssertEqual(whites.last ?? 0, Spacing.gutter, accuracy: 1, "right gutter \(whites)")
        XCTAssertGreaterThanOrEqual(whites.count, 3, "\(whites)")
        XCTAssertEqual(whites[whites.count - 3], Spacing.section, accuracy: 1, "gap between takes 2 and 3 \(whites)")
    }

    /// The y (from the top, in points) where the cards begin: the end of the gap above them, down take 3's padding.
    private func cardsTop(_ rep: NSBitmapImageRep, scale: CGFloat) throws -> CGFloat {
        var y: CGFloat = 0, whitesSeen = 0
        for run in runs(rep, scale: scale, column: thirdCardLeft + 14) {
            y += run.length
            if run.white { whitesSeen += 1; if whitesSeen == 2 { return y } }
        }
        throw XCTSkip("cards not found")
    }
}
