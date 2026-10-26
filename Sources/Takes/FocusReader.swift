import AppKit
import ApplicationServices

/// What was focused when the hotkey fired: the app, its text, and where the caret is.
struct FocusSnapshot {
    enum Source { case selection, field, none }

    let app: NSRunningApplication?
    let text: String
    let source: Source
    /// Caret bounds in Cocoa screen coordinates (origin bottom-left), when the app reports them.
    let caretRect: CGRect?
}

enum FocusReader {
    static func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func snapshot() -> FocusSnapshot {
        let app = NSWorkspace.shared.frontmostApplication
        guard let app, isTrusted(prompt: false) else {
            return FocusSnapshot(app: app, text: "", source: .none, caretRect: nil)
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        // Electron apps (Slack, etc.) only build their accessibility tree when asked to.
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        guard let focused: AXUIElement = copy(appElement, kAXFocusedUIElementAttribute) else {
            return FocusSnapshot(app: app, text: "", source: .none, caretRect: nil)
        }

        let caret = caretRect(of: focused)
        if let selected: String = copy(focused, kAXSelectedTextAttribute), !selected.isEmpty {
            return FocusSnapshot(app: app, text: selected, source: .selection, caretRect: caret)
        }
        if let value: String = copy(focused, kAXValueAttribute) {
            return FocusSnapshot(app: app, text: value, source: .field, caretRect: caret)
        }
        return FocusSnapshot(app: app, text: "", source: .none, caretRect: caret)
    }

    private static func copy<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func caretRect(of element: AXUIElement) -> CGRect? {
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue else { return nil }
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         rangeValue, &boundsValue) == .success,
              let boundsValue, CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect), rect.width >= 0, rect.height > 0 else { return nil }
        // Accessibility uses a top-left origin on the primary screen; Cocoa uses bottom-left.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
