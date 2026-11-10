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

    /// `method` when "Start with: the selection" found nothing selected. The box itself wasn't read.
    static let noSelection = "no selection"

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
        let (snapshot, role) = read(element, in: app, prefill: prefill, allowCopy: allowCopy)
        FocusLog.append(snapshot, role: role)
        return snapshot
    }

    /// Reads the focused element: what it is, then its selection or its text. Everything it asks goes through
    /// `ax`, and its keys and clipboard through `copyEnvironment`, so tests can run it with no app.
    static func read(_ element: AXUIElement, in app: NSRunningApplication?, prefill: Prefill, allowCopy: Bool) -> (FocusSnapshot, role: String) {
        // What the element is comes first: a box that can't say isn't read at all, so a password field is never
        // read just because the app was slow to name it.
        let (roleValue, roleError): (String?, AXError) = ask(element, kAXRoleAttribute)
        let (subroleValue, subroleError): (String?, AXError) = ask(element, kAXSubroleAttribute)
        let role = roleValue ?? "?"
        let subrole = subroleValue ?? "-"
        func result(_ text: String, _ source: FocusSnapshot.Source, _ caret: CGRect?, _ method: String, editable: Bool = true)
            -> (FocusSnapshot, role: String)
        {
            let snapshot = FocusSnapshot(app: app, text: text, source: source, caretRect: caret, element: element, method: method, editable: editable)
            return (snapshot, "\(role)/\(subrole)")
        }

        if roleError == .cannotComplete || subroleError == .cannotComplete {
            return result("", .none, nil, "app not answering")
        }
        // A password field is never read, copied from or selected in. It isn't asked where its caret or its
        // selection is either: its frame is enough to place the panel.
        if isSecure(subrole: subrole) {
            return result("", .secure, frame(of: element), "password field")
        }
        let caret = caretRect(of: element) ?? frame(of: element)
        // Keys (⌘A ⌘C) go only to an app that is still answering: one that went quiet half-way would act on
        // them later, with nobody watching.
        func keysAllowed() -> Bool { allowCopy && budget?.mayAsk() != false }

        let editable = isEditable(element, role: role)
        // Only real text boxes are ever read or copied from, never a page or a document around them.
        let textBox = Self.textRoles.contains(role)
        if prefill == .empty {
            return result("", editable ? .field : .none, caret, "prefill off")
        }

        if let selected: String = copy(element, kAXSelectedTextAttribute), !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // A selection in text that can't be edited (a web page) is still worth rewriting, but the take
            // can't go back there.
            return result(selected, .selection, caret, "AXSelectedText", editable: !isReadOnly(element, role: role))
        }
        if prefill == .selectionOnly {
            // Some apps don't report selections; ⌘C without ⌘A copies only what's selected.
            switch textBox && keysAllowed() ? copyFromApp(selectAll: false, element: element) : .nothing {
            case .text(let copied): return result(copied, .selection, caret, "copy selection")
            case .tooLong: return result("", .tooLong, caret, "too long (copy selection)")
            case .nothing: return result("", editable ? .field : .none, caret, FocusSnapshot.noSelection)
            }
        }

        guard textBox || editable else { return result("", .none, caret, "not a text field") }
        switch afterRead(readText(element), textBox: textBox) {
        case .use(let text, let method):
            return result(text, .field, caret, method)
        case .tooLong(let method):
            // Known to be over the limit: it is never selected and copied, and never passes for an empty box.
            return result("", .tooLong, caret, method)
        case .notText:
            return result("", .none, caret, "not a text field")
        case .copyAll:
            guard keysAllowed() else {
                // `--focus-test` sends no keys and reports an editable box, as before. A quiet app's box wasn't read.
                return allowCopy ? result("", .none, caret, "app not answering") : result("", .field, caret, "editable, empty")
            }
            switch copyFromApp(selectAll: true, element: element) {
            case .text(let copied): return result(copied, .field, caret, "copy (⌘A ⌘C)")
            case .tooLong: return result("", .tooLong, caret, "too long (copy)")
            case .nothing: return result("", .field, caret, "editable, empty")
            }
        }
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
            /// Another element has it, but one that stands in for the box: a text box of the same app that still
            /// holds what was read (`standsIn`). Some apps build their text box anew while the panel has the keyboard.
            case equivalent
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
    ///
    /// A different element is accepted only as `.equivalent`, which already means its content matched what was
    /// read; replacing everything in it still needs that match to have been on the text.
    static func mayPaste(replaceAll: Bool, check: FieldCheck) -> Bool {
        switch check.focus {
        case .other: return false
        case .unknown: return !replaceAll
        case .equivalent: return !replaceAll || check.text == .same
        case .same: return !replaceAll || check.text == .same || check.text == .notCompared
        }
    }

    /// The paste-time check: `mayPaste` on what the app says now. A paste into no known app passes.
    static func confirmed(_ snapshot: FocusSnapshot?, replaceAll: Bool) -> Bool {
        guard let snapshot, snapshot.app != nil else {
            lastVerdict = "no app to check"
            return true
        }
        let check = check(snapshot, compareText: replaceAll)
        lastVerdict = "focus \(check.focus), text \(check.text)"
        return mayPaste(replaceAll: replaceAll, check: check)
    }

    /// What `confirmed` last found, for the focus log: which path a paste took, or why it wasn't sent. No text.
    private(set) static var lastVerdict = ""

    /// What another element must still hold to stand in for the one a snapshot read.
    enum Expected: Equatable {
        /// The box's whole text, read through accessibility; "" for a box that was empty.
        case text(String)
        /// The selected text, reported through accessibility.
        case selection(String)
        /// Nothing that can be compared: the text was read by copying, or the box wasn't read at all.
        case unknown
    }

    /// The ways `readText` reads a box through accessibility. Only text read one of these ways can be compared.
    static let accessibilityReads: Set<String> = ["AXValue", "empty (character count)", "AXStringForRange", "element text markers"]

    static func expected(of snapshot: FocusSnapshot) -> Expected {
        switch snapshot.source {
        case .field: return accessibilityReads.contains(snapshot.method) ? .text(snapshot.text) : .unknown
        case .selection: return snapshot.method == "AXSelectedText" ? .selection(snapshot.text) : .unknown
        case .none, .tooLong, .secure: return .unknown
        }
    }

    /// Whether `current`, a different element from the one a snapshot read, can take its paste. Only a text box
    /// (never a password field) that still holds what was read: the same text, the same selection, or, for a box
    /// that was empty, still nothing. Returns what matched, or nil.
    static func standsIn(_ current: AXUIElement, for snapshot: FocusSnapshot) -> FieldCheck? {
        let role: String? = copy(current, kAXRoleAttribute)
        let subrole: String? = copy(current, kAXSubroleAttribute)
        guard let role, textRoles.contains(role), !isSecure(subrole: subrole) else { return nil }
        switch expected(of: snapshot) {
        case .text(let text):
            guard case .text(let now, _) = readText(current), now == text else { return nil }
            return FieldCheck(focus: .equivalent, text: .same)
        case .selection(let selection):
            let selected: String? = copy(current, kAXSelectedTextAttribute)
            return selected == selection ? FieldCheck(focus: .equivalent) : nil
        case .unknown:
            return nil
        }
    }

    /// Where a hotkey press came from, for a panel still open on the box a snapshot read.
    enum PressOrigin: Equatable {
        /// That box has the keyboard.
        case sameBox
        /// The same app, with the keyboard in nothing that takes text (its window, a list of messages), or the
        /// app can't say what has it.
        case sameApp
        /// Another app, or another text box of the same one: a new summon.
        case elsewhere
    }

    static func pressOrigin(for snapshot: FocusSnapshot?) -> PressOrigin {
        guard let snapshot, let app = snapshot.app else { return .elsewhere }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return .elsewhere }
        guard let current = focusedElement(in: app, timeout: 0.25) else { return .sameApp }
        if let element = snapshot.element, CFEqual(current, element) { return .sameBox }
        AXUIElementSetMessagingTimeout(current, 0.25)
        if standsIn(current, for: snapshot) != nil { return .sameBox }
        let role: String = copy(current, kAXRoleAttribute) ?? ""
        return isEditable(current, role: role) ? .elsewhere : .sameApp
    }

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
        guard CFEqual(current, element) else {
            AXUIElementSetMessagingTimeout(current, 0.25)
            return standsIn(current, for: snapshot) ?? FieldCheck(focus: .other)
        }
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
    /// Set while `snapshot` reads. (Tests set it to see what a read does once its time is up.)
    static var budget: ReadBudget?

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
        for attribute in [kAXValueAttribute, kAXSelectedTextAttribute] where ax.isSettable(element, attribute) == true {
            return true
        }
        let editableAncestor: AXUIElement? = copy(element, "AXEditableAncestor")
        return editableAncestor != nil
    }

    /// Whether the element's text is known to take no typing, so a paste there would change nothing. That takes
    /// the element's own word for it; where it says nothing either way, the paste is tried as before.
    private static func isReadOnly(_ element: AXUIElement, role: String) -> Bool {
        let settable: [Bool?] = [kAXValueAttribute, kAXSelectedTextAttribute].map { ax.isSettable(element, $0) }
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

    /// What the ⌘A ⌘C fallback touches outside Takes: the clipboard and the keys it sends. Tests put their own here.
    struct CopyEnvironment {
        var pasteboard = NSPasteboard.general
        /// Sends a key to the frontmost app, with ⌘ or on its own.
        var press: (_ key: CGKeyCode, _ command: Bool) -> Void = { Paster.press($0, command: $1) }
        /// The hotkey's ⌃ ⌥ may still be held; they are let go of first so the app sees a plain ⌘A ⌘C.
        var waitForModifierRelease: () -> Void = { Paster.waitForModifierRelease(timeout: 0.5) }
        var clipboardWillChange: () -> Void = { ClipboardWatch.aboutToWrite() }
        var clipboardChanged: (ClipboardFreshness.OwnWrite) -> Void = { ClipboardWatch.ownWrite($0) }
        /// How long the copy may take to land before the box counts as empty.
        var copyWait: TimeInterval = 0.3
        /// How much longer a copy that missed `copyWait` is watched for, so it can still be undone.
        var lateWait: TimeInterval = 1
    }

    static var copyEnvironment = CopyEnvironment()

    /// Copies from the frontmost app with ⌘C (after ⌘A when `selectAll`), then restores the clipboard.
    /// The ⌘A is undone every time, so the box is left as it was found, whether or not the copy is used: text
    /// left selected is replaced by the next key typed there. A paste that replaces everything sends its own ⌘A.
    private static func copyFromApp(selectAll: Bool, element: AXUIElement) -> Copied {
        let env = copyEnvironment
        let pasteboard = env.pasteboard
        // A restore Takes still owes (the last paste's, or an earlier late copy's) goes first: what is saved
        // here must be the user's clipboard, never Takes' own text.
        Paster.settleOwedRestore()
        let saved = Paster.snapshot(pasteboard)
        env.clipboardWillChange()
        let before = pasteboard.changeCount
        let selection: CFTypeRef? = selectAll ? copy(element, kAXSelectedTextRangeAttribute) : nil
        env.waitForModifierRelease()
        if selectAll { env.press(CGKeyCode(kVK_ANSI_A), true) }
        env.press(CGKeyCode(kVK_ANSI_C), true)
        let deadline = Date().addingTimeInterval(env.copyWait)
        while pasteboard.changeCount == before && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        let arrived = pasteboard.changeCount != before
        var text: String?
        if arrived {
            let copyCount = pasteboard.changeCount
            text = pasteboard.string(forType: .string)
            // Put the clipboard back only while it still holds this copy.
            if Paster.restore(saved, to: pasteboard, ifCount: copyCount) { env.clipboardChanged(.borrowed) }
        } else {
            watchForLateCopy(saved, since: before, env)
        }
        // With no copy yet, a slow app may not have got to the keys: → waits its turn behind them, where a
        // selection put back now could be undone by the ⌘A still on its way.
        if selectAll { deselect(element, restoring: arrived ? selection : nil, env) }
        return copied(text)
    }

    /// A ⌘C that missed the wait can still land a moment later, in a slow app: the clipboard would then hold the
    /// whole box, the user's own clipboard would be gone, and it would count as something they copied. So the
    /// clipboard is watched a little longer, and a change in that time is taken to be that copy and undone.
    private static func watchForLateCopy(_ saved: [NSPasteboardItem], since before: Int, _ env: CopyEnvironment) {
        let pasteboard = env.pasteboard
        let deadline = Date().addingTimeInterval(env.lateWait)
        func undoIfLanded() -> Bool {
            let count = pasteboard.changeCount
            guard count != before else { return false }
            if Paster.restore(saved, to: pasteboard, ifCount: count) { env.clipboardChanged(.borrowed) }
            return true
        }
        // Owed, so a paste or another read that starts meanwhile checks one last time before it saves the clipboard.
        let owed = Paster.owe { _ = undoIfLanded() }
        func poll() {
            guard Paster.isOwed(owed) else { return }
            if undoIfLanded() || Date() >= deadline { return Paster.forget(owed) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
    }

    /// Undoes Takes' own ⌘A: puts the selection back where it was, or, in an app that can't do that, moves the
    /// caret to the end with →.
    private static func deselect(_ element: AXUIElement, restoring selection: CFTypeRef?, _ env: CopyEnvironment) {
        if let selection, ax.set(element, kAXSelectedTextRangeAttribute, selection) == .success { return }
        env.press(CGKeyCode(kVK_RightArrow), false)
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

    /// The accessibility calls made while reading a text box. Tests answer them in an app's place.
    static var ax = AXClient.live

    private static func copy<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        ask(element, attribute).0
    }

    /// An attribute's value, and how the app answered: `.cannotComplete` when it didn't in time, or when the
    /// read's time was already up and it wasn't asked.
    private static func ask<T>(_ element: AXUIElement, _ attribute: String) -> (T?, AXError) {
        guard budget?.mayAsk() ?? true else { return (nil, .cannotComplete) }
        let (value, result) = ax.attribute(element, attribute)
        guard result == .success, let value else { return (nil, result) }
        return (value as? T, result)
    }

    private static func parameterized<T>(_ element: AXUIElement, _ attribute: String, _ parameter: CFTypeRef) -> T? {
        guard budget?.mayAsk() ?? true else { return nil }
        return ax.parameterized(element, attribute, parameter) as? T
    }
}

/// The accessibility calls `FocusReader` makes about a text box.
struct AXClient {
    /// An attribute's value, and the app's answer.
    var attribute: (AXUIElement, String) -> (CFTypeRef?, AXError)
    var parameterized: (AXUIElement, String, CFTypeRef) -> CFTypeRef?
    /// Whether an attribute can be set; nil when the element doesn't say.
    var isSettable: (AXUIElement, String) -> Bool?
    var set: (AXUIElement, String, CFTypeRef) -> AXError

    static let live = AXClient(
        attribute: { element, attribute in
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            return (result == .success ? value : nil, result)
        },
        parameterized: { element, attribute, parameter in
            var value: CFTypeRef?
            let result = AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &value)
            return result == .success ? value : nil
        },
        isSettable: { element, attribute in
            var settable = DarwinBoolean(false)
            return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success ? settable.boolValue : nil
        },
        set: { element, attribute, value in AXUIElementSetAttributeValue(element, attribute as CFString, value) })
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
/// Each paste gets a line too: which check let it through, or why it wasn't sent. Never any text.
enum FocusLog {
    /// Tests write to a file of their own.
    static var fileOverride: URL?
    static var url: URL { fileOverride ?? RunLog.url.deletingLastPathComponent().appendingPathComponent("focus.log") }
    /// Past `cap` bytes the oldest lines are dropped, down to about `keep`.
    static let cap = 512 * 1024
    static let keep = 384 * 1024

    static func append(_ snapshot: FocusSnapshot, role: String) {
        let caret = snapshot.caretRect.map { "\(Int($0.minX)),\(Int($0.minY))" } ?? "none"
        write("\(snapshot.app?.bundleIdentifier ?? "?")\t\(role)\t\(snapshot.method)\tchars=\(snapshot.text.count)\tcaret=\(caret)")
    }

    /// `entry` is "paste sent" or "paste not sent", then what the check found.
    static func paste(_ target: FocusSnapshot?, _ entry: String) {
        write("\(target?.app?.bundleIdentifier ?? "?")\t\(entry)")
    }

    private static func write(_ entry: String) {
        let url = url
        let line = "\(ISO8601DateFormatter().string(from: Date()))\t\(entry)\n"
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if size > cap, let data = try? Data(contentsOf: url) {
            try? (newest(of: data, keeping: keep) + Data(line.utf8)).write(to: url, options: .atomic)
            return
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    /// The newest whole lines of `data` that fit in `keeping` bytes.
    static func newest(of data: Data, keeping: Int) -> Data {
        guard data.count > keeping else { return data }
        let tail = data.suffix(keeping)
        guard let lineEnd = tail.firstIndex(of: 0x0A) else { return Data() }
        return Data(tail[tail.index(after: lineEnd)...])
    }
}
