import Carbon
import Foundation

/// macOS's own keyboard shortcuts (System Settings › Keyboard › Keyboard Shortcuts).
/// RegisterEventHotKey doesn't refuse a combo macOS already uses, and both then fire: with
/// "Show Finder search window" on ⌃⌥Space, the Takes hotkey also opened Finder and took the focus.
enum SystemShortcuts {
    /// Names for the ids in com.apple.symbolichotkeys that use ordinary keys.
    static let names: [Int: String] = [
        60: "Select the previous input source", 61: "Select next source in Input menu",
        64: "Show Spotlight search", 65: "Show Finder search window",
        32: "Mission Control", 33: "Application windows", 36: "Show Desktop",
        79: "Move left a space", 81: "Move right a space", 118: "Switch to Desktop 1",
        162: "Turn Dock hiding on/off", 7: "Move focus to the menu bar", 8: "Move focus to the Dock",
        9: "Move focus to the active or next window", 10: "Move focus to the window toolbar",
        11: "Move focus to the floating window", 27: "Move focus to next window",
        28: "Save picture of screen as a file", 29: "Copy picture of screen to the clipboard",
        30: "Save picture of selected area as a file", 31: "Copy picture of selected area to the clipboard",
        184: "Screenshot and recording options", 98: "Show Help menu",
    ]

    /// The macOS shortcut that already uses `combo`, if one is turned on.
    static func owner(of combo: KeyCombo) -> String? {
        owner(of: combo, in: UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys") ?? [:])
    }

    /// `hotKeys` is the AppleSymbolicHotKeys dictionary: id → {enabled, value: {parameters: [char, keyCode, flags]}}.
    static func owner(of combo: KeyCombo, in hotKeys: [String: Any]) -> String? {
        let flags = cocoaFlags(carbon: combo.modifiers)
        for (id, entry) in hotKeys.sorted(by: { $0.key < $1.key }) {
            guard let entry = entry as? [String: Any], (entry["enabled"] as? Bool) == true,
                  let value = entry["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [Int], parameters.count >= 3,
                  parameters[1] == Int(combo.keyCode),
                  UInt(parameters[2]) & relevantFlags == flags else { continue }
            return names[Int(id) ?? -1] ?? "macOS shortcut \(id)"
        }
        return nil
    }

    /// ⇧ ⌃ ⌥ ⌘ in NSEvent.ModifierFlags raw values, which is how macOS stores its shortcuts.
    static let relevantFlags: UInt = 0x20000 | 0x40000 | 0x80000 | 0x100000

    static func cocoaFlags(carbon: UInt32) -> UInt {
        var flags: UInt = 0
        if carbon & UInt32(shiftKey) != 0 { flags |= 0x20000 }
        if carbon & UInt32(controlKey) != 0 { flags |= 0x40000 }
        if carbon & UInt32(optionKey) != 0 { flags |= 0x80000 }
        if carbon & UInt32(cmdKey) != 0 { flags |= 0x100000 }
        return flags
    }
}
