import AppKit
import Carbon

/// Pastes text into the field the draft came from, then optionally puts the user's clipboard back.
enum Paster {
    static func paste(_ text: String, into target: FocusSnapshot?, replaceAll: Bool, restoreClipboard: Bool) {
        let pasteboard = NSPasteboard.general
        let saved = restoreClipboard ? snapshot(pasteboard) : []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Web-based apps can drop the field's focus while the panel had the keyboard; put it back first.
        FocusReader.refocus(target)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if replaceAll { press(CGKeyCode(kVK_ANSI_A)) }
            press(CGKeyCode(kVK_ANSI_V))
            guard restoreClipboard else { return }
            // Give the target app time to read the clipboard before restoring it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                pasteboard.clearContents()
                if !saved.isEmpty { pasteboard.writeObjects(saved) }
            }
        }
    }

    /// Sends ⌘+key to the frontmost app.
    static func press(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
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
