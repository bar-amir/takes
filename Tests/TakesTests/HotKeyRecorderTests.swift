import AppKit
import XCTest
@testable import Takes

/// Recording a shortcut lets go of every hotkey. Closing Settings or onboarding mid-recording used to leave them all
/// let go, because SwiftUI doesn't tell a view whose retained window only closed. Now the recorder stops when its
/// window closes or loses the keyboard, and a suspension that outlives its recorder ends on its own.
@MainActor
final class HotKeyRecorderTests: XCTestCase {
    private var monitors: [Int] = []
    private var removed: [Int] = []

    private func recording(_ center: NotificationCenter) -> HotKeyRecording {
        let recording = HotKeyRecording()
        recording.notifications = center
        recording.addMonitor = { [unowned self] _ in
            monitors.append(monitors.count)
            return monitors.count - 1
        }
        recording.removeMonitor = { [unowned self] monitor in removed.append(monitor as! Int) }
        return recording
    }

    private func window() -> NSWindow {
        _ = NSApplication.shared
        return NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless], backing: .buffered, defer: true)
    }

    override func tearDown() {
        XCTAssertFalse(HotKeyCenter.shared.suspended, "No test may leave the hotkeys let go")
        super.tearDown()
    }

    // MARK: The center

    func testASuspensionEndsWhenItIsEndedOrLetGo() {
        let center = HotKeyCenter.shared
        var suspension: HotKeyCenter.Suspension? = center.suspend()
        XCTAssertTrue(center.suspended)
        suspension?.end()
        XCTAssertFalse(center.suspended)
        suspension?.end()
        XCTAssertEqual(center.suspensions, 0, "Ending twice counts once")

        suspension = center.suspend()
        XCTAssertTrue(center.suspended)
        suspension = nil
        XCTAssertFalse(center.suspended, "A suspension nobody holds can't keep the hotkeys away")
    }

    func testTheHotkeysComeBackOnlyWhenEverySuspensionHasEnded() {
        let center = HotKeyCenter.shared
        let first = center.suspend()
        let second = center.suspend()
        first.end()
        XCTAssertTrue(center.suspended, "Another recorder still records")
        second.end()
        XCTAssertFalse(center.suspended)
    }

    // MARK: The recorder

    func testClosingTheWindowStopsRecordingAndPutsTheHotkeysBack() {
        let center = NotificationCenter()
        let window = window()
        let recording = recording(center)
        recording.start(in: window) { _ in false }
        XCTAssertTrue(recording.isRecording)
        XCTAssertTrue(HotKeyCenter.shared.suspended)

        center.post(name: NSWindow.willCloseNotification, object: window)
        XCTAssertFalse(recording.isRecording)
        XCTAssertFalse(HotKeyCenter.shared.suspended)
        XCTAssertEqual(removed, [0], "The key monitor is removed, or it would swallow every key press")
    }

    func testLosingTheKeyboardStopsRecording() {
        let center = NotificationCenter()
        let window = window()
        let recording = recording(center)
        recording.start(in: window) { _ in false }
        center.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertFalse(recording.isRecording)
        XCTAssertFalse(HotKeyCenter.shared.suspended)
    }

    func testAnotherWindowClosingDoesNotStopIt() {
        let center = NotificationCenter()
        let mine = window(), other = window()
        let recording = recording(center)
        recording.start(in: mine) { _ in false }
        center.post(name: NSWindow.willCloseNotification, object: other)
        XCTAssertTrue(recording.isRecording)
        recording.stop()
        XCTAssertFalse(HotKeyCenter.shared.suspended)
    }

    func testWithNoWindowKnownNoOtherWindowStopsIt() {
        let center = NotificationCenter()
        let recording = recording(center)
        recording.start(in: nil) { _ in false }
        center.post(name: NSWindow.willCloseNotification, object: window())
        center.post(name: NSWindow.didResignKeyNotification, object: window())
        XCTAssertTrue(recording.isRecording, "The panel or a popover closing has nothing to do with it")
        recording.stop()
    }

    func testAfterStoppingTheWindowIsNoLongerWatched() {
        let center = NotificationCenter()
        let window = window()
        let recording = recording(center)
        recording.start(in: window) { _ in false }
        recording.stop()
        recording.start(in: window) { _ in false }
        center.post(name: NSWindow.willCloseNotification, object: window)
        center.post(name: NSWindow.willCloseNotification, object: window)
        XCTAssertEqual(removed, [0, 1], "Each recording removes its own monitor once")
    }

    func testARecorderThatGoesAwayPutsTheHotkeysBack() {
        let center = NotificationCenter()
        var recording: HotKeyRecording? = recording(center)
        recording?.start(in: window()) { _ in false }
        XCTAssertTrue(HotKeyCenter.shared.suspended)
        recording = nil
        XCTAssertFalse(HotKeyCenter.shared.suspended)
        XCTAssertEqual(removed, [0])
    }

    func testAKeyThatFinishesRecordingStopsIt() throws {
        let recording = HotKeyRecording()
        recording.notifications = NotificationCenter()
        var handler: ((NSEvent) -> NSEvent?)?
        recording.addMonitor = { handler = $0; return 7 }
        recording.removeMonitor = { [unowned self] in removed.append($0 as! Int) }
        var seen = 0
        recording.start(in: nil) { _ in
            seen += 1
            return seen == 2
        }
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                   windowNumber: 0, context: nil, characters: "a",
                                                   charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
        XCTAssertNil(handler?(event), "Keys go to the recorder, not the window")
        XCTAssertTrue(recording.isRecording, "A plain key isn't a shortcut")
        _ = handler?(event)
        XCTAssertFalse(recording.isRecording)
        XCTAssertEqual(removed, [7])
    }
}
