import AppKit
import Carbon

/// Global hotkeys through Carbon's RegisterEventHotKey, which needs no extra permission.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var refs: [EventHotKeyRef] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async { HotKeyCenter.shared.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// Replaces every registered hotkey. Returns the combos macOS refused (already taken).
    @discardableResult
    func replaceAll(with bindings: [(KeyCombo, () -> Void)]) -> [KeyCombo] {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        handlers = [:]
        var failed: [KeyCombo] = []
        for (combo, handler) in bindings {
            let id = nextID
            nextID += 1
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, EventHotKeyID(signature: OSType(0x5441_4B53), id: id),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                handlers[id] = handler
            } else {
                failed.append(combo)
            }
        }
        return failed
    }

    /// Whether `combo` could be registered now. Tries it on its own, so the hotkeys already in place stay put.
    func isFree(_ combo: KeyCombo) -> Bool {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, EventHotKeyID(signature: OSType(0x5441_4B53), id: 0),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        UnregisterEventHotKey(ref)
        return true
    }
}

extension KeyCombo {
    /// Builds a combo from a key press, or nil when it has no ⌃, ⌥ or ⌘ (plain keys would hijack typing).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.control, .option, .command]).isEmpty else { return nil }
        var modifiers = 0
        var symbols = ""
        if flags.contains(.control) { modifiers |= controlKey; symbols += "⌃" }
        if flags.contains(.option) { modifiers |= optionKey; symbols += "⌥" }
        if flags.contains(.shift) { modifiers |= shiftKey; symbols += "⇧" }
        if flags.contains(.command) { modifiers |= cmdKey; symbols += "⌘" }
        self.init(keyCode: UInt32(event.keyCode), modifiers: UInt32(modifiers), display: symbols + KeyCombo.keyName(event))
    }

    private static func keyName(_ event: NSEvent) -> String {
        let names: [Int: String] = [kVK_Space: "Space", kVK_Return: "↵", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "Esc",
                                    kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
                                    kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
                                    kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"]
        if let name = names[Int(event.keyCode)] { return name }
        // Name the key by the US layout so a Hebrew layout doesn't show "ש" for S.
        let usNames: [Int: String] = [kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
                                      kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
                                      kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
                                      kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
                                      kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
                                      kVK_ANSI_Z: "Z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
                                      kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8",
                                      kVK_ANSI_9: "9", kVK_ANSI_Slash: "/", kVK_ANSI_Period: ".", kVK_ANSI_Comma: ",",
                                      kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "="]
        return usNames[Int(event.keyCode)] ?? (event.charactersIgnoringModifiers?.uppercased() ?? "?")
    }
}
