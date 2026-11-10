import AppKit
import ApplicationServices
import Carbon

/// What was focused when the hotkey fired: the app, its text, and where the caret is.
struct FocusSnapshot {
    /// Where `text` came from. `tooLong` and `secure` are text boxes Takes found but didn't read: one holding more
    /// than `FocusReader.maxPrefill` characters, and a password field. Neither is ever treated as an empty `field`.
    enum Source { case selection, field, none, tooLong, secure }

    let app: NSRunningApplication?
    let text: String
    let source: Source
    /// Caret bounds (or the field's frame) in Cocoa screen coordinates (origin bottom-left).
    let caretRect: CGRect?
    /// The focused element, so paste can put focus back into it.
    var element: AXUIElement? = nil
    /// How the text was read, for the focus log.
    var method = ""
    /// False when the text is known to take no typing (a selection on a web page). A take can't be pasted there,
    /// so it's left on the clipboard instead.
    var editable = true

    /// The same text box once a take has replaced everything in it, so a later paste checks for the take.
    func holding(_ text: String) -> FocusSnapshot {
        FocusSnapshot(app: app, text: text, source: source, caretRect: caretRect, element: element, method: method, editable: editable)
    }
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

        // An app that has stopped answering must not freeze the hotkey: every question gets a short timeout
        // (`focusedElement`, and the element below), and the read as a whole gets a budget.
        budget = ReadBudget(seconds: readBudget)
        defer { budget = nil }
        // Electron and Chromium apps (Slack, Claude…) only build their accessibility tree when asked to,
        // and build it asynchronously. `prepare` asks as soon as an app comes forward; this covers an app
        // that was already in front. The first build can take well over 240 ms, so wait up to ~0.7 s.
        prepare(app, again: true)
        var focused = focusedElement(in: app)
        for _ in 0..<Self.focusRetries where focused == nil {
            // The retries are for a tree still being built, not for an app that takes the whole timeout to say nothing.
            guard budget?.mayAsk() ?? true else { break }
            Thread.sleep(forTimeInterval: 0.08)
            focused = focusedElement(in: app)
        }

        guard let element = focused else {
            // No accessibility at all: fall back to copying, which works in almost any app.
            // Don't copy blind: with nothing known to be focused, ⌘A could select a whole page.
            let method = budget?.mayAsk() == false ? "app not answering" : "no focused element"
            let snapshot = FocusSnapshot(app: app, text: "", source: .none, caretRect: nil, method: method)
            FocusLog.append(snapshot, role: "nil")
            return snapshot
        }
        // The wait for the tree doesn't count against reading the box itself.
        budget = ReadBudget(seconds: readBudget)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)

        // What the element is comes first: a box that can't say isn't read at all, so a password field is never
        // read just because the app was slow to name it.
        let (roleValue, roleError): (String?, AXError) = ask(element, kAXRoleAttribute)
        let (subroleValue, subroleError): (String?, AXError) = ask(element, kAXSubroleAttribute)
        let role = roleValue ?? "?"
        let subrole = subroleValue ?? "-"
        let caret = caretRect(of: element) ?? frame(of: element)
        var snapshot = FocusSnapshot(app: app, text: "", source: .none, caretRect: caret, element: element)

        defer { FocusLog.append(snapshot, role: "\(role)/\(subrole)") }

        if roleError == .cannotComplete || subroleError == .cannotComplete {
            snapshot = FocusSnapshot(app: app, text: "", source: .none, caretRect: caret, element: element, method: "app not answering")
            return snapshot
        }
        // A password field is never read, copied from or selected in.
        if isSecure(subrole: subrole) {
            snapshot = FocusSnapshot(app: app, text: "", source: .secure, caretRect: caret, element: element, method: "password field")
            return snapshot
        }
        // Keys (⌘A ⌘C) go only to an app that is still answering: one that went quiet half-way would act on
        // them later, with nobody watching.
        func keysAllowed() -> Bool { allowCopy && budget?.mayAsk() != false }

        let editable = isEditable(element, role: role)
        // Only real text boxes are ever read or copied from, never a page or a document around them.
        let textBox = Self.textRoles.contains(role)
        if prefill == .empty {
            snapshot = FocusSnapshot(app: app, text: "", source: editable ? .field : .none, caretRect: caret, element: element, method: "prefill off")
            return snapshot
        }

        if let selected: String = copy(element, kAXSelectedTextAttribute), !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // A selection in text that can't be edited (a web page) is still worth rewriting, but the take
            // can't go back there.
            snapshot = FocusSnapshot(
                app: app, text: selected, source: .selection, caretRect: caret, element: element,
                method: "AXSelectedText", editable: !isReadOnly(element, role: role))
            return snapshot
        }
        if prefill == .selectionOnly {
            // Some apps don't report selections; ⌘C without ⌘A copies only what's selected.
            switch textBox && keysAllowed() ? copyFromApp(selectAll: false, element: element) : .nothing {
            case .text(let copied):
                snapshot = FocusSnapshot(app: app, text: copied, source: .selection, caretRect: caret, element: element, method: "copy selection")
            case .tooLong:
                snapshot = FocusSnapshot(app: app, text: "", source: .tooLong, caretRect: caret, element: element, method: "too long (copy selection)")
            case .nothing:
                snapshot = FocusSnapshot(app: app, text: "", source: editable ? .field : .none, caretRect: caret, element: element, method: "no selection")
            }
            return snapshot
        }

        guard textBox || editable else {
            snapshot = FocusSnapshot(app: app, text: "", source: .none, caretRect: caret, element: element, method: "not a text field")
            return snapshot
        }
        switch afterRead(readText(element), textBox: textBox) {
        case .use(let text, let method):
            snapshot = FocusSnapshot(app: app, text: text, source: .field, caretRect: caret, element: element, method: method)
        case .tooLong(let method):
            // Known to be over the limit: it is never selected and copied, and never passes for an empty box.
            snapshot = FocusSnapshot(app: app, text: "", source: .tooLong, caretRect: caret, element: element, method: method)
        case .notText:
            snapshot = FocusSnapshot(app: app, text: "", source: .none, caretRect: caret, element: element, method: "not a text field")
        case .copyAll:
            guard keysAllowed() else {
                // `--focus-test` sends no keys and reports an editable box, as before. A quiet app's box wasn't read.
                snapshot = FocusSnapshot(
                    app: app, text: "", source: allowCopy ? .none : .field, caretRect: caret, element: element,
                    method: allowCopy ? "app not answering" : "editable, empty")
                return snapshot
            }
            switch copyFromApp(selectAll: true, element: element) {
            case .text(let copied):
                snapshot = FocusSnapshot(app: app, text: copied, source: .field, caretRect: caret, element: element, method: "copy (⌘A ⌘C)")
            case .tooLong:
                snapshot = FocusSnapshot(app: app, text: "", source: .tooLong, caretRect: caret, element: element, method: "too long (copy)")
            case .nothing:
                snapshot = FocusSnapshot(app: app, text: "", source: .field, caretRect: caret, element: element, method: "editable, empty")
            }
        }
        return snapshot
    }

    /// Retries (80 ms apart) while an app's accessibility tree is still being built.
    static let focusRetries = 8

    /// Turns on an Electron or Chromium app's accessibility tree ahead of time, so the first summon
    /// in it can read the field. Harmless for native apps.
    ///
    /// Each process is asked once as it comes forward, not on every activation: the tree stays on for the life
    /// of the process. `again` asks regardless; the hotkey does, so a summon never depends on what was asked earlier.
    static func prepare(_ app: NSRunningApplication, again: Bool = false) {
        let pid = app.processIdentifier
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier, again || prepared.needs(pid), isTrusted(prompt: false) else { return }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        let result = AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        // An app still launching can't be reached yet; it is asked again the next time it comes forward.
        prepared.asked(pid, answered: result != .cannotComplete && result != .apiDisabled)
    }

    /// The app quit; its process id can come back as another app.
    static func forget(_ pid: pid_t) { prepared.forget(pid) }

    private static var prepared = PreparedApps()

    /// Brings the field the text came from back to the front with keyboard focus in it, before pasting.
    /// False when the app says that text box is gone (a chat that was closed or switched away from), so
    /// there is nothing to paste into; `confirmed` then checks what has focus.
    @discardableResult
    static func refocus(_ snapshot: FocusSnapshot?) -> Bool {
        guard let snapshot, let app = snapshot.app else { return true }
        // `activate()` from an app that isn't active is only a request on macOS 14+, and is refused when
        // another app took the front (Finder, from a macOS shortcut on the same keys). Accessibility isn't.
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app.activate()
        guard let element = snapshot.element else { return true }
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        if let window: AXUIElement = copy(element, kAXWindowAttribute) {
            AXUIElementSetMessagingTimeout(window, messagingTimeout)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
        // Many apps refuse or ignore this and keep focus where it was, which is fine. Only "no such element" is a no.
        return AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) != .invalidUIElement
    }

    // MARK: Is it still the same text box?

    /// What the app says, at paste time, about the text box a snapshot was read from.
    struct FieldCheck: Equatable {
        enum Focus {
            /// The box the snapshot read has keyboard focus.
            case same
            /// Something else has it.
            case other
            /// The app didn't say what has focus (thin accessibility, or no answer in time).
            case unknown
        }
        enum Text {
            case same, changed
            /// It was read through accessibility at summon and can't be read now.
            case unreadable
            /// Nothing to compare: the text was read by copying, or no text was read from the box.
            case notCompared
        }
        var focus: Focus
        var text = Text.notCompared
    }

    /// Whether keys may be sent, after `refocus`, to paste a take. Pure, so the rule can be tested.
    ///
    /// Replacing everything (⌘A ⌘V) destroys what's in the box, so it needs proof: the same box has focus and,
    /// where its text can be compared, it still holds what was read. Without that proof nothing is typed.
    /// A paste at the caret or over a selection (⌘V alone) only adds text and ⌘Z takes it back, so it is
    /// refused only when the app says another box has focus. An app that can't say what has focus still gets
    /// it: that is the only way Takes ever worked in apps with thin accessibility. Its selection isn't
    /// compared either, because many apps drop or stop reporting it while the panel has the keyboard.
    static func mayPaste(replaceAll: Bool, check: FieldCheck) -> Bool {
        switch check.focus {
        case .other: return false
        case .unknown: return !replaceAll
        case .same: return !replaceAll || check.text == .same || check.text == .notCompared
        }
    }

    /// The paste-time check: `mayPaste` on what the app says now. A paste into no known app passes.
    static func confirmed(_ snapshot: FocusSnapshot?, replaceAll: Bool) -> Bool {
        guard let snapshot, snapshot.app != nil else { return true }
        let check = check(snapshot, compareText: replaceAll)
        let allowed = mayPaste(replaceAll: replaceAll, check: check)
        lastRefusal = allowed ? nil : "focus \(check.focus), text \(check.text)"
        return allowed
    }

    /// Why `confirmed` last said no, for the focus log.
    private(set) static var lastRefusal: String?

    /// Whether the user is still in the text box a snapshot read, with the text that was read: instant mode asks
    /// this before it brings the box back to the front, so a take isn't pasted into a box the user has left or
    /// typed more into. Answers yes when the app can't tell; `confirmed` is the strict check, at the paste itself.
    static func stillEditing(_ snapshot: FocusSnapshot) -> Bool {
        let check = check(snapshot, compareText: true)
        return check.focus != .other && check.text != .changed
    }

    private static func check(_ snapshot: FocusSnapshot, compareText: Bool) -> FieldCheck {
        guard let app = snapshot.app, let element = snapshot.element else { return FieldCheck(focus: .unknown) }
        guard let current = focusedElement(in: app, timeout: 0.25) else { return FieldCheck(focus: .unknown) }
        guard CFEqual(current, element) else { return FieldCheck(focus: .other) }
        // Text read by copying can differ from what accessibility reports; only compare like with like.
        guard compareText, snapshot.source == .field, !snapshot.method.hasPrefix("copy") else { return FieldCheck(focus: .same) }
        AXUIElementSetMessagingTimeout(element, 0.25)
        guard case .text(let text, _) = readText(element) else { return FieldCheck(focus: .same, text: .unreadable) }
        return FieldCheck(focus: .same, text: text == snapshot.text ? .same : .changed)
    }

    /// The element with keyboard focus in `app`.
    private static func focusedElement(in app: NSRunningApplication, timeout: Float = messagingTimeout) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, timeout)
        if let element: AXUIElement = copy(appElement, kAXFocusedUIElementAttribute) { return element }
        // Some apps answer only through the system-wide element; accept it only if it is the same app's.
        // (A timeout set on the system-wide element is the default for every element without its own.)
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        guard let element: AXUIElement = copy(systemWide, kAXFocusedUIElementAttribute) else { return nil }
        var owner: pid_t = 0
        return AXUIElementGetPid(element, &owner) == .success && owner == app.processIdentifier ? element : nil
    }

    // MARK: An app that stops answering

    /// How long one question to an app may take. The default is several seconds a question, and a summon asks many.
    static let messagingTimeout: Float = 0.5
    /// How long finding the focused element, and then reading it, may each take in all. Past it no more questions
    /// are sent, so a hung app costs the hotkey about two seconds instead of freezing it.
    static let readBudget: TimeInterval = 1.5
    /// Set while `snapshot` reads.
    private static var budget: ReadBudget?

    // MARK: Reading text

    static let textRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField"]
    /// Longest draft Takes will prefill; anything longer is almost certainly not a message being written.
    static let maxPrefill = 10_000

    /// A password field (`AXSecureTextField`): Takes never reads it, copies from it or selects in it.
    static func isSecure(subrole: String?) -> Bool { subrole == (kAXSecureTextFieldSubrole as String) }

    /// What asking a text box for its own text gave.
    enum Read: Equatable {
        case text(String, method: String)
        /// More than `maxPrefill` characters: not read, and not the same thing as empty.
        case tooLong(method: String)
        case unreadable
    }

    /// How a text box's own text counts. A value that is present is trusted even when blank: an empty
    /// web text box reports "\n", and that means empty, not "try harder".
    static func read(_ text: String, method: String) -> Read {
        guard text.count <= maxPrefill else { return .tooLong(method: method) }
        let stripped = text.replacingOccurrences(of: "\u{FFFC}", with: "")
        let clean = stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : stripped.trimmingCharacters(in: .newlines)
        return .text(clean, method: method)
    }

    /// What to do with a text box once its own text was asked for.
    enum AfterRead: Equatable {
        case use(text: String, method: String)
        case tooLong(method: String)
        /// Unreadable through accessibility: select all and copy.
        case copyAll
        case notText
    }

    /// Pure, so the rule can be tested: ⌘A ⌘C is only for a text box whose text couldn't be read at all. A box
    /// already known to be over the limit is never selected.
    static func afterRead(_ read: Read, textBox: Bool) -> AfterRead {
        switch read {
        case .text(let text, let method): return .use(text: text, method: method)
        case .tooLong(let method): return .tooLong(method: "too long (\(method))")
        case .unreadable: return textBox ? .copyAll : .notText
        }
    }

    /// Reads a text box's own text.
    private static func readText(_ element: AXUIElement) -> Read {
        if let value: String = copy(element, kAXValueAttribute) { return read(value, method: "AXValue") }

        if let count: Int = copy(element, kAXNumberOfCharactersAttribute) {
            guard count > 0 else { return .text("", method: "empty (character count)") }
            guard count <= maxPrefill else { return .tooLong(method: "character count") }
            var range = CFRange(location: 0, length: count)
            if let rangeValue = AXValueCreate(.cfRange, &range),
               let text: String = parameterized(element, kAXStringForRangeParameterizedAttribute, rangeValue) {
                return read(text, method: "AXStringForRange")
            }
        }

        // Chromium: the text-marker range of this element only (never the document's start and end markers).
        if let range: CFTypeRef = parameterized(element, "AXTextMarkerRangeForUIElement", element),
            let text: String = parameterized(element, "AXStringForTextMarkerRange", range)
        {
            return read(text, method: "element text markers")
        }
        return .unreadable
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

    /// Whether the element's text is known to take no typing, so a paste there would change nothing. That takes
    /// the element's own word for it; where it says nothing either way, the paste is tried as before.
    private static func isReadOnly(_ element: AXUIElement, role: String) -> Bool {
        let settable: [Bool?] = [kAXValueAttribute, kAXSelectedTextAttribute].map { attribute in
            var settable = DarwinBoolean(false)
            return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success ? settable.boolValue : nil
        }
        let editableAncestor: AXUIElement? = copy(element, "AXEditableAncestor")
        return readOnly(textBox: textRoles.contains(role), settable: settable, editableAncestor: editableAncestor != nil)
    }

    /// Pure, so it can be tested. `settable` holds what the element said about setting its value and its selected
    /// text; nil where it didn't say. A text box counts as editable whatever it says: some that take typing
    /// (terminals, web editors) report their value as fixed.
    static func readOnly(textBox: Bool, settable: [Bool?], editableAncestor: Bool) -> Bool {
        if textBox || editableAncestor || settable.contains(true) { return false }
        return settable.contains(false)
    }

    /// What the copy fallback got.
    enum Copied: Equatable {
        case text(String)
        /// More than `maxPrefill` characters.
        case tooLong
        /// Nothing was copied, or only blank text.
        case nothing
    }

    /// How copied text counts. Pure, so it can be tested.
    static func copied(_ text: String?) -> Copied {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .nothing }
        return text.count <= maxPrefill ? .text(text) : .tooLong
    }

    /// Copies from the frontmost app with ⌘C (after ⌘A when `selectAll`), then restores the clipboard.
    /// When the copy isn't used (too long, blank, or none arrived), the ⌘A is undone, so the box is left as it
    /// was found: text left selected would be replaced by the next key typed, or by a take pasted at the caret.
    private static func copyFromApp(selectAll: Bool, element: AXUIElement) -> Copied {
        let pasteboard = NSPasteboard.general
        let saved = Paster.snapshot(pasteboard)
        ClipboardWatch.aboutToWrite()
        let before = pasteboard.changeCount
        let selection: CFTypeRef? = selectAll ? copy(element, kAXSelectedTextRangeAttribute) : nil
        // The hotkey's ⌃ ⌥ may still be held; let go of them first so the app sees a plain ⌘A ⌘C.
        Paster.waitForModifierRelease(timeout: 0.5)
        if selectAll { Paster.press(CGKeyCode(kVK_ANSI_A)) }
        Paster.press(CGKeyCode(kVK_ANSI_C))
        let deadline = Date().addingTimeInterval(0.3)
        while pasteboard.changeCount == before && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        let arrived = pasteboard.changeCount != before
        var text: String?
        if arrived {
            let copyCount = pasteboard.changeCount
            text = pasteboard.string(forType: .string)
            // Put the clipboard back only while it still holds this copy.
            if Paster.restore(saved, to: pasteboard, ifCount: copyCount) { ClipboardWatch.ownWrite(.borrowed) }
        }
        let result = copied(text)
        if selectAll, case .text = result { return result }
        // With no copy yet, a slow app may not have got to the keys: → waits its turn behind them, where a
        // selection put back now could be undone by the ⌘A still on its way.
        if selectAll { deselect(element, restoring: arrived ? selection : nil) }
        return result
    }

    /// Undoes Takes' own ⌘A: puts the selection back where it was, or, in an app that can't do that, moves the
    /// caret to the end with →.
    private static func deselect(_ element: AXUIElement, restoring selection: CFTypeRef?) {
        if let selection, AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, selection) == .success { return }
        Paster.press(CGKeyCode(kVK_RightArrow), command: false)
    }

    // MARK: Geometry

    private static func caretRect(of element: AXUIElement) -> CGRect? {
        guard let range: CFTypeRef = copy(element, kAXSelectedTextRangeAttribute),
              let bounds: CFTypeRef = parameterized(element, kAXBoundsForRangeParameterizedAttribute, range),
              let rect = cgRect(bounds), rect.height > 0, rect.origin != .zero else { return nil }
        return flipped(rect)
    }

    /// The whole text box in Cocoa screen coordinates, so the panel can open beside it instead of over it.
    static func fieldFrame(of element: AXUIElement?) -> CGRect? {
        guard let element, let value: CFTypeRef = copy(element, "AXFrame"), let rect = cgRect(value),
              rect.width > 0, rect.height > 0 else { return nil }
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
        ask(element, attribute).0
    }

    /// An attribute's value, and how the app answered: `.cannotComplete` when it didn't in time, or when the
    /// read's time was already up and it wasn't asked.
    private static func ask<T>(_ element: AXUIElement, _ attribute: String) -> (T?, AXError) {
        guard budget?.mayAsk() ?? true else { return (nil, .cannotComplete) }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else { return (nil, result) }
        return (value as? T, result)
    }

    private static func parameterized<T>(_ element: AXUIElement, _ attribute: String, _ parameter: CFTypeRef) -> T? {
        guard budget?.mayAsk() ?? true else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &value) == .success,
              let value else { return nil }
        return value as? T
    }
}

/// The time one read of a text box may take. Once it's up, no more questions are sent to the app.
struct ReadBudget {
    let until: Date

    init(seconds: TimeInterval, from start: Date = Date()) { until = start.addingTimeInterval(seconds) }

    func mayAsk(now: Date = Date()) -> Bool { now < until }
}

/// Which processes were already asked to build their accessibility tree (`FocusReader.prepare`).
struct PreparedApps {
    private var asked: Set<pid_t> = []

    func needs(_ pid: pid_t) -> Bool { !asked.contains(pid) }

    /// An app that didn't answer (still launching, or busy) is asked again next time.
    mutating func asked(_ pid: pid_t, answered: Bool) {
        if answered { asked.insert(pid) }
    }

    mutating func forget(_ pid: pid_t) { asked.remove(pid) }
}

/// One line per summon in ~/Library/Logs/Takes/focus.log: which app, what kind of element, how its text was read.
/// A paste that wasn't sent gets a line too, with the reason. Never any text.
enum FocusLog {
    static func append(_ snapshot: FocusSnapshot, role: String) {
        let caret = snapshot.caretRect.map { "\(Int($0.minX)),\(Int($0.minY))" } ?? "none"
        write("\(snapshot.app?.bundleIdentifier ?? "?")\t\(role)\t\(snapshot.method)\tchars=\(snapshot.text.count)\tcaret=\(caret)")
    }

    static func pasteNotSent(_ target: FocusSnapshot?, reason: String) {
        write("\(target?.app?.bundleIdentifier ?? "?")\tpaste not sent\t\(reason)")
    }

    private static func write(_ entry: String) {
        let url = RunLog.url.deletingLastPathComponent().appendingPathComponent("focus.log")
        let line = "\(ISO8601DateFormatter().string(from: Date()))\t\(entry)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
