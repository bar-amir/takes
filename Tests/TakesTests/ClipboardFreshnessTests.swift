import AppKit
import XCTest

@testable import Takes

/// The clipboard is only attached as context when the user copied it just now. Takes changes the clipboard
/// itself when it pastes a take and puts the old clipboard back; none of that may look like a fresh copy.
final class ClipboardFreshnessTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }
    private let message = "Can we move the review to Thursday? Marketing needs Wednesday."
    private let text = [NSPasteboard.PasteboardType.string.rawValue]

    func testACopyIsFresh() {
        var clipboard = ClipboardFreshness(count: 10)
        XCTAssertNil(clipboard.age(now: at(0)), "never seen it change")
        clipboard.observe(count: 11, now: at(5))
        XCTAssertEqual(clipboard.age(now: at(15)), 10)
    }

    func testPuttingAnOldClipboardBackDoesNotMakeItFresh() {
        // Copied long before Takes started watching; then a take is pasted and the clipboard restored.
        var clipboard = ClipboardFreshness(count: 10)
        clipboard.ownWrite(.take, count: 12)
        clipboard.ownWrite(.putBack, count: 13)
        clipboard.observe(count: 13, now: at(2))
        XCTAssertNil(clipboard.age(now: at(3)))

        // So the next summon doesn't attach it.
        let candidate = ClipboardCandidate(text: message, types: text, age: clipboard.age(now: at(3)))
        XCTAssertNil(ClipboardHeuristic.context(from: candidate, draft: "sure", lastOffered: nil))
    }

    func testARecentCopyKeepsItsOwnTimeAcrossAPaste() {
        var clipboard = ClipboardFreshness(count: 10)
        clipboard.observe(count: 11, now: at(0))
        clipboard.ownWrite(.take, count: 13)
        XCTAssertNil(clipboard.age(now: at(20)), "while the take is on the clipboard, nothing there was just copied")
        clipboard.ownWrite(.putBack, count: 14)
        clipboard.observe(count: 14, now: at(21))
        XCTAssertEqual(clipboard.age(now: at(30)), 30, "measured from the copy, not from the restore")
    }

    func testATakeLeftOnTheClipboardIsNeverJustCopied() {
        // A take copied with ⌘C, or left there after a paste that couldn't be sent.
        var clipboard = ClipboardFreshness(count: 10)
        clipboard.observe(count: 11, now: at(0))
        clipboard.ownWrite(.take, count: 12)
        clipboard.observe(count: 12, now: at(1))
        XCTAssertNil(clipboard.age(now: at(2)))
        // Pasting another take over it and restoring puts the first take back, which is still Takes' own text.
        clipboard.ownWrite(.take, count: 14)
        clipboard.ownWrite(.putBack, count: 15)
        XCTAssertNil(clipboard.age(now: at(3)))
    }

    func testTheCopyFallbackLeavesTheAgeAsItWas() {
        var clipboard = ClipboardFreshness(count: 10)
        clipboard.observe(count: 11, now: at(0))
        // ⌘A ⌘C in the text box, then the clipboard put back: two changes, neither the user's.
        clipboard.aboutToWrite(count: 11, now: at(1))
        clipboard.ownWrite(.borrowed, count: 13)
        clipboard.observe(count: 13, now: at(1))
        XCTAssertEqual(clipboard.age(now: at(10)), 10)

        var old = ClipboardFreshness(count: 10)
        old.aboutToWrite(count: 10, now: at(1))
        old.ownWrite(.borrowed, count: 12)
        old.observe(count: 12, now: at(1))
        XCTAssertNil(old.age(now: at(2)))
    }

    func testALateCopyByTakesKeepsTheAgeFromBeforeIt() {
        // The copy fallback's ⌘C landed late and was seen as a change before Takes put the clipboard back.
        var clipboard = ClipboardFreshness(count: 10)
        clipboard.observe(count: 11, now: at(0))
        clipboard.aboutToWrite(count: 11, now: at(60))
        clipboard.observe(count: 12, now: at(61))
        XCTAssertEqual(clipboard.age(now: at(61)), 0, "for a moment it looks like a fresh copy")
        clipboard.ownWrite(.borrowed, count: 13)
        XCTAssertEqual(clipboard.age(now: at(70)), 70, "the user's own copy, a minute before")

        // The same for a clipboard that was never seen to change.
        var old = ClipboardFreshness(count: 10)
        old.aboutToWrite(count: 10, now: at(60))
        old.observe(count: 11, now: at(61))
        old.ownWrite(.borrowed, count: 12)
        XCTAssertNil(old.age(now: at(62)))
    }

    func testACopyJustBeforeTakesWritesIsNotedFirst() {
        var clipboard = ClipboardFreshness(count: 10)
        // Copied a moment ago, not yet seen; then the hotkey.
        clipboard.aboutToWrite(count: 11, now: at(5))
        clipboard.ownWrite(.borrowed, count: 13)
        XCTAssertEqual(clipboard.age(now: at(15)), 10)
    }

    func testACopyAfterTakesWroteCounts() {
        var clipboard = ClipboardFreshness(count: 10)
        clipboard.ownWrite(.take, count: 12)
        clipboard.observe(count: 13, now: at(4))
        XCTAssertEqual(clipboard.age(now: at(6)), 2)
        // And a restore that didn't happen (the clipboard had changed) leaves it alone.
        clipboard.observe(count: 13, now: at(7))
        XCTAssertEqual(clipboard.age(now: at(8)), 4)
    }
}
