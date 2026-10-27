import AppKit
import Carbon

/// macOS's own keyboard shortcuts (System Settings › Keyboard › Keyboard Shortcuts). RegisterEventHotKey accepts a
/// combo macOS already uses, and then both fire: with "Show Finder search window" on ⌃⌥Space, every summon also
/// opened a Finder window, and Finder taking focus pulled a full-screen app's Space away under the panel.
enum SystemShortcuts {
    /// Names for the shortcuts people most often move onto ⌃/⌥ + Space and friends.
    private static let names: [Int: String] = [
        7: "Move focus to the menu bar", 8: "Move focus to the Dock", 9: "Move focus to active or next window",
        27: "Move focus to next window", 32: "Mission Control", 33: "Application windows", 36: "Show Desktop",
        60: "Select the previous input source", 61: "Select next source in Input menu",
        64: "Show Spotlight search", 65: "Show Finder search window",
        79: "Move left a space", 81: "Move right a space",
    ]

    /// The macOS shortcut that already uses `combo`, if any.
    static func clash(with combo: KeyCombo) -> String? {
        clash(with: combo, in: symbolicHotKeys())
    }

    /// `hotKeys` is the `AppleSymbolicHotKeys` dictionary from com.apple.symbolichotkeys:
    /// id → { enabled, value: { parameters: (character, key code, Cocoa modifier flags) } }.
    static func clash(with combo: KeyCombo, in hotKeys: [String: Any]) -> String? {
        let hits = hotKeys.compactMap { id, entry -> Int? in
            guard let entry = entry as? [String: Any], (entry["enabled"] as? NSNumber)?.boolValue == true,
                  let value = entry["value"] as? [String: Any], let parameters = value["parameters"] as? [NSNumber],
                  parameters.count >= 3, parameters[1].intValue != 0xFFFF,
                  UInt32(parameters[1].intValue) == combo.keyCode,
                  carbonModifiers(cocoa: parameters[2].uintValue) == combo.modifiers else { return nil }
            return Int(id) ?? -1
        }
        guard let id = hits.min() else { return nil }
        return names[id] ?? "a macOS keyboard shortcut"
    }

    private static func carbonModifiers(cocoa flags: UInt) -> UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: flags)
        var modifiers = 0
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        if flags.contains(.command) { modifiers |= cmdKey }
        return UInt32(modifiers)
    }

    private static func symbolicHotKeys() -> [String: Any] {
        UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys") ?? [:]
    }
}
