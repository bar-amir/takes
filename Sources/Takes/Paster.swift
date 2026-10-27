import AppKit
import Carbon

/// Pastes text into the field the draft came from, then optionally puts the user's clipboard back.
enum Paster {
    /// `done(true)` once ⌘V was sent to the field's app; `done(false)` when that app couldn't be brought
    /// back to the front, so nothing was typed anywhere and the take is left on the clipboard.
    static func paste(_ text: String, into target: FocusSnapshot?, replaceAll: Bool, restoreClipboard: Bool,
                      done: @escaping (Bool) -> Void = { _ in }) {
        let pasteboard = NSPasteboard.general
        let saved = restoreClipboard ? snapshot(pasteboard) : []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Web-based apps can drop the field's focus while the panel had the keyboard, and another app
        // (a macOS shortcut on the same keys, say) can have come forward; put the field back first.
        FocusReader.refocus(target)
        let pid = target?.app?.processIdentifier
        waitUntil(timeout: 1.5, { targetIsFrontmost(pid) && interferingFlags(CGEventSource.flagsState(.combinedSessionState)).isEmpty }) { _ in
            // Never type ⌘A ⌘V blind into whatever app is in front instead.
            guard targetIsFrontmost(pid) else { return done(false) }
            // Let the app settle keyboard focus into the field before the keys arrive.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                if replaceAll { press(CGKeyCode(kVK_ANSI_A)) }
                press(CGKeyCode(kVK_ANSI_V))
                done(true)
                guard restoreClipboard else { return }
                // Give the target app time to read the clipboard before restoring it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    pasteboard.clearContents()
                    if !saved.isEmpty { pasteboard.writeObjects(saved) }
                }
            }
        }
    }

    private static func targetIsFrontmost(_ pid: pid_t?) -> Bool {
        guard let pid else { return true }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    /// Keys still held that would turn ⌘V into another command (⌥⌘V, ⇧⌘V, ⌃⌘V…). ⌘ itself is harmless.
    static func interferingFlags(_ flags: CGEventFlags) -> CGEventFlags {
        flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskSecondaryFn])
    }

    /// The ⌘+key events `press` posts: exactly ⌘, whatever the user is still holding.
    static func commandKeyEvents(_ key: CGKeyCode) -> [CGEvent] {
        // A private source carries no modifier state of its own, so a held ⌃ or ⌥ can't leak in.
        let source = CGEventSource(stateID: .privateState)
        return [true, false].compactMap { down in
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = .maskCommand
            return event
        }
    }

    /// Sends ⌘+key to the frontmost app.
    static func press(_ key: CGKeyCode) {
        commandKeyEvents(key).forEach { $0.post(tap: .cghidEventTap) }
    }

    /// Blocks (briefly) until the user has let go of ⇧ ⌃ ⌥, for keys sent while the hotkey may still be held.
    static func waitForModifierRelease(timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while !interferingFlags(CGEventSource.flagsState(.combinedSessionState)).isEmpty && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    /// Polls on the main run loop without blocking it; `then(true)` if `condition` came true in time.
    private static func waitUntil(timeout: TimeInterval, _ condition: @escaping () -> Bool, then: @escaping (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            if condition() { return then(true) }
            if Date() >= deadline { return then(false) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: poll)
        }
        poll()
    }

    static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }
}
