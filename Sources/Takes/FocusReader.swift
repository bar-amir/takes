import AppKit
import ApplicationServices
import Carbon

/// What was focused when the hotkey fired: the app, its text, and where the caret is.
struct FocusSnapshot {
    enum Source { case selection, field, none }

    let app: NSRunningApplication?
    let text: String
    let source: Source
    /// Caret bounds (or the field's frame) in Cocoa screen coordinates (origin bottom-left).
    let caretRect: CGRect?
    /// The focused element, so paste can put focus back into it.
    var element: AXUIElement? = nil
    /// How the text was read, for the focus log.
    var method = ""
}

enum FocusReader {
    static func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// `allowCopy: false` never sends ⌘A/⌘C, for the `--focus-test` dry run.
    static func snapshot(prefill: Prefill, allowCopy: Bool = true) -> FocusSnapshot {
        let app = NSWorkspace.shared.frontmostApplication
        guard let app, isTrusted(prompt: false), app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            let snapshot = FocusSnapshot(app: app, text: "", source: .none, caretRect: nil,
                                         method: isTrusted(prompt: false) ? "no app" : "no Accessibility access")
            FocusLog.append(snapshot, role: "-")
            return snapshot
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 1)
        // Electron and Chromium apps (Slack, Claude…) only build their accessibility tree when asked to,
        // and build it asynchronously. `prepare` asks as soon as an app comes forward; this covers an app
        // that was already in front. The first build can take well over 240 ms, so wait up to ~0.7 s.
        prepare(app)
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 1)
        func focusedElement() -> AXUIElement? {
            if let element: AXUIElement = copy(appElement, kAXFocusedUIElementAttribute) { return element }
            // Some apps answer only through the system-wide element; accept it only if it is the same app's.
            guard let element: AXUIElement = copy(systemWide, kAXFocusedUIElementAttribute) else { return nil }
            var owner: pid_t = 0
            return AXUIElementGetPid(element, &owner) == .success && owner == app.processIdentifier ? element : nil
        }
        var focused = focusedElement()
        for _ in 0..<Self.focusRetries where focused == nil {
            Thread.sleep(forTimeInterval: 0.08)
            focused = focusedElement()
        }

        guard let element = focused else {
            // No accessibility at all: fall back to copying, which works in almost any app.
            // Don't copy blind: with nothing known to be focused, ⌘A could select a whole page.
            let snapshot = FocusSnapshot(app: app, text: "", source: .none, caretRect: nil, method: "no focused element")
            FocusLog.append(snapshot, role: "nil")
            return snapshot
        }

        let caret = caretRect(of: element) ?? frame(of: element)
        let role: String = copy(element, kAXRoleAttribute) ?? "?"
        let subrole: String = copy(element, kAXSubroleAttribute) ?? "-"
        var snapshot = FocusSnapshot(app: app, text: "", source: .none, caretRect: caret, element: element)

        defer { FocusLog.append(snapshot, role: "\(role)/\(subrole)") }

        let editable = isEditable(element, role: role)
        // Only real text boxes are ever read or copied from, never a page or a document around them.
        let textBox = Self.textRoles.contains(role)
        if prefill == .empty {
            snapshot = FocusSnapshot(app: app, text: "", source: editable ? .field : .none, caretRect: caret, element: element, method: "prefill off")
            return snapshot
        }

        if let selected: String = copy(element, kAXSelectedTextAttribute), !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            snapshot = FocusSnapshot(app: app, text: selected, source: .selection, caretRect: caret, element: element, method: "AXSelectedText")
            return snapshot
        }
        if prefill == .selectionOnly {
            // Some apps don't report selections; ⌘C without ⌘A copies only what's selected.
            if textBox, allowCopy, let copied = copyFromApp(selectAll: false) {
                snapshot = FocusSnapshot(app: app, text: copied, source: .selection, caretRect: caret, element: element, method: "copy selection")
            } else {
                snapshot = FocusSnapshot(app: app, text: "", source: editable ? .field : .none, caretRect: caret, element: element, method: "no selection")
            }
            return snapshot
        }

        guard textBox || editable else {
            snapshot = FocusSnapshot(app: app, text: "", source: .none, caretRect: caret, element: element, method: "not a text field")
            return snapshot
        }
        if let (text, method) = readText(element) {
            snapshot = FocusSnapshot(app: app, text: text, source: .field, caretRect: caret, element: element, method: method)
            return snapshot
        }
        if textBox {
            if allowCopy, let copied = copyFromApp(selectAll: true) {
                snapshot = FocusSnapshot(app: app, text: copied, source: .field, caretRect: caret, element: element, method: "copy (⌘A ⌘C)")
            } else {
                snapshot = FocusSnapshot(app: app, text: "", source: .field, caretRect: caret, element: element, method: "editable, empty")
            }
            return snapshot
        }
        snapshot = FocusSnapshot(app: app, text: "", source: .none, caretRect: caret, element: element, method: "not a text field")
        return snapshot
    }

    /// Retries (80 ms apart) while an app's accessibility tree is still being built.
    static let focusRetries = 8

    /// Turns on an Electron or Chromium app's accessibility tree ahead of time, so the first summon
    /// in it can read the field. Harmless for native apps.
    static func prepare(_ app: NSRunningApplication) {
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier, isTrusted(prompt: false) else { return }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Brings the field the text came from back to the front with keyboard focus in it, before pasting.
    static func refocus(_ snapshot: FocusSnapshot?) {
        guard let snapshot, let app = snapshot.app else { return }
        // `activate()` from an app that isn't active is only a request on macOS 14+, and is refused when
        // another app took the front (Finder, from a macOS shortcut on the same keys). Accessibility isn't.
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app.activate()
        if let element = snapshot.element {
            if let window: AXUIElement = copy(element, kAXWindowAttribute) {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            }
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
    }

    // MARK: Reading text

    static let textRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField"]
    /// Longest draft Takes will prefill; anything longer is almost certainly not a message being written.
    static let maxPrefill = 10_000

    /// Reads a text box's own text. A value that is present is trusted even when blank: an empty
    /// web text box reports "\n", and that means empty, not "try harder".
    private static func readText(_ element: AXUIElement) -> (String, String)? {
        func clean(_ text: String) -> String {
            let stripped = text.replacingOccurrences(of: "\u{FFFC}", with: "")
            return stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : stripped.trimmingCharacters(in: .newlines)
        }

        if let value: String = copy(element, kAXValueAttribute) {
            return value.count > maxPrefill ? nil : (clean(value), "AXValue")
        }

        if let count: Int = copy(element, kAXNumberOfCharactersAttribute) {
            guard count > 0 else { return ("", "empty (character count)") }
            guard count <= maxPrefill else { return nil }
            var range = CFRange(location: 0, length: count)
            if let rangeValue = AXValueCreate(.cfRange, &range),
               let text: String = parameterized(element, kAXStringForRangeParameterizedAttribute, rangeValue) {
                return (clean(text), "AXStringForRange")
            }
        }

        // Chromium: the text-marker range of this element only (never the document's start and end markers).
        if let range: CFTypeRef = parameterized(element, "AXTextMarkerRangeForUIElement", element),
           let text: String = parameterized(element, "AXStringForTextMarkerRange", range), text.count <= maxPrefill {
            return (clean(text), "element text markers")
        }
        return nil
    }

    private static func isEditable(_ element: AXUIElement, role: String) -> Bool {
        if ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField"].contains(role) { return true }
        for attribute in [kAXValueAttribute, kAXSelectedTextAttribute] {
            var settable = DarwinBoolean(false)
            if AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success, settable.boolValue { return true }
        }
        let editableAncestor: AXUIElement? = copy(element, "AXEditableAncestor")
        return editableAncestor != nil
    }

    /// Copies from the frontmost app with ⌘C (after ⌘A when `selectAll`), then restores the clipboard.
    private static func copyFromApp(selectAll: Bool) -> String? {
        let pasteboard = NSPasteboard.general
        let saved = Paster.snapshot(pasteboard)
        let before = pasteboard.changeCount
        // The hotkey's ⌃ ⌥ may still be held; let go of them first so the app sees a plain ⌘A ⌘C.
        Paster.waitForModifierRelease(timeout: 0.5)
        if selectAll { Paster.press(CGKeyCode(kVK_ANSI_A)) }
        Paster.press(CGKeyCode(kVK_ANSI_C))
        let deadline = Date().addingTimeInterval(0.3)
        while pasteboard.changeCount == before && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        guard pasteboard.changeCount != before else { return nil }
        let text = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        if !saved.isEmpty { pasteboard.writeObjects(saved) }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= maxPrefill else { return nil }
        return text
    }

    // MARK: Geometry

    private static func caretRect(of element: AXUIElement) -> CGRect? {
        guard let range: CFTypeRef = copy(element, kAXSelectedTextRangeAttribute),
              let bounds: CFTypeRef = parameterized(element, kAXBoundsForRangeParameterizedAttribute, range),
              let rect = cgRect(bounds), rect.height > 0, rect.origin != .zero else { return nil }
        return flipped(rect)
    }

    /// The field's own frame, for apps that don't report caret bounds.
    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let value: CFTypeRef = copy(element, "AXFrame"), let rect = cgRect(value), rect.width > 0 else { return nil }
        // Treat the field's top-left corner as the caret, so the panel opens just above it.
        return flipped(CGRect(x: rect.minX + 20, y: rect.minY, width: 2, height: min(rect.height, 24)))
    }

    private static func cgRect(_ value: CFTypeRef) -> CGRect? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
    }

    /// Accessibility uses a top-left origin on the primary screen; Cocoa uses bottom-left.
    private static func flipped(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: AX helpers

    private static func copy<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return nil }
        return value as? T
    }

    private static func parameterized<T>(_ element: AXUIElement, _ attribute: String, _ parameter: CFTypeRef) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &value) == .success,
              let value else { return nil }
        return value as? T
    }
}

/// One line per summon in ~/Library/Logs/Takes/focus.log: which app, what kind of element, how its text was read.
enum FocusLog {
    static func append(_ snapshot: FocusSnapshot, role: String) {
        let url = RunLog.url.deletingLastPathComponent().appendingPathComponent("focus.log")
        let caret = snapshot.caretRect.map { "\(Int($0.minX)),\(Int($0.minY))" } ?? "none"
        let line = "\(ISO8601DateFormatter().string(from: Date()))\t\(snapshot.app?.bundleIdentifier ?? "?")\t\(role)\t"
            + "\(snapshot.method)\tchars=\(snapshot.text.count)\tcaret=\(caret)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
