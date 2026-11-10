import AppKit
import Carbon

/// Which hotkey opens Takes: a default that stock macOS leaves free, the ones tried when it isn't, who already
/// uses a combo, and free ones to offer in onboarding and Settings.
enum HotKeyChoice {
    /// ⌥⇧Space. No macOS shortcut uses it, and neither do the launchers, password managers and window managers
    /// in `knownApps`, so it works out of the box on a stock Mac. (⌃⌥Space, the old default, is "Select next
    /// source in Input menu" on stock macOS, and ⌥Space, ⇧⌘Space and ⌥⌘Space belong to Raycast, 1Password and Finder.)
    static let preferred = combo(kVK_Space, optionKey | shiftKey, "⌥⇧Space")

    /// In the order they're offered. All stay off macOS's own shortcuts on a stock Mac except ⌃⌥Space, which is
    /// kept for Macs where the input-source shortcuts are turned off.
    static let candidates: [KeyCombo] = [
        preferred,
        combo(kVK_Space, controlKey | optionKey, "⌃⌥Space"),
        combo(kVK_Space, controlKey | optionKey | cmdKey, "⌃⌥⌘Space"),
        combo(kVK_ANSI_T, optionKey | shiftKey, "⌥⇧T"),
        combo(kVK_ANSI_T, controlKey | shiftKey, "⌃⇧T"),
        combo(kVK_ANSI_T, controlKey | optionKey, "⌃⌥T"),
        combo(kVK_ANSI_T, controlKey | optionKey | cmdKey, "⌃⌥⌘T"),
    ]

    /// Offered for a preset's own hotkey: ⌃⌥ and ⌃⌥⌘ with a digit. No macOS shortcut or app in `knownApps` ships
    /// with them (⌃ + digit alone is "Switch to Desktop"), and the digit is easy to tie to a preset.
    static let presetCandidates: [KeyCombo] = [(controlKey | optionKey, "⌃⌥"), (controlKey | optionKey | cmdKey, "⌃⌥⌘")].flatMap { modifiers, symbols in
        [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
            .enumerated().map { index, key in combo(key, modifiers, symbols + "\(index + 1)") }
    }

    static func combo(_ key: Int, _ modifiers: Int, _ display: String) -> KeyCombo {
        KeyCombo(keyCode: UInt32(key), modifiers: UInt32(modifiers), display: display)
    }

    // MARK: Who has it

    /// Apps whose default global shortcuts are well known, so a refused hotkey can be named instead of blamed on
    /// "another app". Only apps installed on this Mac are named.
    struct KnownApp {
        let name: String
        let bundleIDs: [String]
        /// (key code, Carbon modifiers) of the shortcuts the app ships with.
        let shortcuts: [(key: Int, modifiers: Int)]

        func uses(_ combo: KeyCombo) -> Bool {
            shortcuts.contains { UInt32($0.key) == combo.keyCode && UInt32($0.modifiers) == combo.modifiers }
        }
    }

    private static let ctrlOpt = controlKey | optionKey
    private static let ctrlOptCmd = controlKey | optionKey | cmdKey
    /// Rectangle's and Magnet's ⌃⌥ keys: halves, thirds, corners, maximize, restore, bigger and smaller.
    private static let windowManagerKeys = [
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_ANSI_C, kVK_ANSI_F, kVK_ANSI_D, kVK_ANSI_E,
        kVK_ANSI_G, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_Return, kVK_Delete, kVK_ANSI_Minus, kVK_ANSI_Equal,
    ]

    static let knownApps: [KnownApp] = [
        KnownApp(name: "Raycast", bundleIDs: ["com.raycast.macos"], shortcuts: [(kVK_Space, optionKey)]),
        KnownApp(name: "Alfred", bundleIDs: ["com.runningwithcrayons.Alfred", "com.runningwithcrayons.Alfred-3"],
                 shortcuts: [(kVK_Space, optionKey)]),
        KnownApp(name: "1Password", bundleIDs: ["com.1password.1password"], shortcuts: [(kVK_Space, shiftKey | cmdKey)]),
        KnownApp(name: "ChatGPT", bundleIDs: ["com.openai.chat"], shortcuts: [(kVK_Space, optionKey)]),
        KnownApp(name: "Claude", bundleIDs: ["com.anthropic.claudefordesktop"], shortcuts: [(kVK_Space, optionKey)]),
        KnownApp(name: "Rectangle", bundleIDs: ["com.knollsoft.Rectangle", "com.knollsoft.Hookshot"],
                 shortcuts: windowManagerKeys.map { ($0, ctrlOpt) } + [kVK_LeftArrow, kVK_RightArrow, kVK_ANSI_F].map { ($0, ctrlOptCmd) }),
        KnownApp(name: "Magnet", bundleIDs: ["com.crowdcafe.windowmagnet"],
                 shortcuts: windowManagerKeys.map { ($0, ctrlOpt) } + [kVK_LeftArrow, kVK_RightArrow].map { ($0, ctrlOptCmd) }),
    ]

    static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// The installed app whose stock shortcut is `combo`, if one is known.
    static func knownApp(using combo: KeyCombo, installed: (String) -> Bool = isInstalled) -> String? {
        knownApps.first { app in app.uses(combo) && app.bundleIDs.contains(where: installed) }?.name
    }

    /// Who has `combo`, for a hotkey macOS refused or also fires on: "macOS: Show Finder search window",
    /// "Raycast", or "another app" when nothing more can be told.
    static func owner(of combo: KeyCombo, macOS: String? = nil, installed: (String) -> Bool = isInstalled) -> String {
        if let macOS { return String(localized: "macOS: \(macOS)") }
        if let system = SystemShortcuts.owner(of: combo) { return String(localized: "macOS: \(system)") }
        return knownApp(using: combo, installed: installed) ?? String(localized: "another app")
    }

    // MARK: Free ones

    /// Whether Takes could use `combo` now: no macOS shortcut on it, not one of Takes's own in `taken`, and macOS
    /// accepts it. Registering it is the only way to know if another app has it.
    static func isAvailable(_ combo: KeyCombo, taken: [KeyCombo] = [],
                            systemOwner: (KeyCombo) -> String? = SystemShortcuts.owner(of:),
                            isFree: (KeyCombo) -> Bool = { HotKeyCenter.shared.isFree($0) }) -> Bool {
        !taken.contains(combo) && systemOwner(combo) == nil && isFree(combo)
    }

    /// Up to `limit` of `from` that are free right now, leaving out `current` and the hotkeys in `taken`.
    static func suggestions(from: [KeyCombo] = candidates, current: KeyCombo?, taken: [KeyCombo] = [], limit: Int = 3,
                            systemOwner: (KeyCombo) -> String? = SystemShortcuts.owner(of:),
                            isFree: (KeyCombo) -> Bool = { HotKeyCenter.shared.isFree($0) }) -> [KeyCombo] {
        Array(from.filter { $0 != current && isAvailable($0, taken: taken, systemOwner: systemOwner, isFree: isFree) }.prefix(limit))
    }

    /// The hotkey a new install starts with: the first candidate this Mac leaves free, else the preferred one
    /// (setup then says who has it).
    static func firstLaunchDefault(taken: [KeyCombo] = [],
                                   systemOwner: (KeyCombo) -> String? = SystemShortcuts.owner(of:),
                                   isFree: (KeyCombo) -> Bool = { HotKeyCenter.shared.isFree($0) }) -> KeyCombo {
        candidates.first { isAvailable($0, taken: taken, systemOwner: systemOwner, isFree: isFree) } ?? preferred
    }
}
