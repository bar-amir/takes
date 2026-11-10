import Foundation

/// Keeps the menu-bar icon at the right end of the menu bar, next to the system icons, where a crowded menu bar
/// or the notch hides it last. macOS remembers where each status item goes in the app's defaults, as a distance
/// from the right edge under "NSStatusItem Preferred Position <autosave name>". 1 is the far right; 0 counts as
/// unset and puts the item at the left end.
enum MenuBarPin {
    static let pinnedPosition = 1.0

    static func positionKey(_ autosaveName: String) -> String { "NSStatusItem Preferred Position \(autosaveName)" }

    /// Whether the icon has to move to be pinned: it's elsewhere, or macOS hasn't saved a place for it yet.
    static func needsMove(autosaveName: String, defaults: UserDefaults) -> Bool {
        (defaults.object(forKey: positionKey(autosaveName)) as? Double) != pinnedPosition
    }

    /// Saves the far-right place. macOS reads it when the status item is created, so the item has to be made again.
    static func pin(autosaveName: String, defaults: UserDefaults) {
        defaults.set(pinnedPosition, forKey: positionKey(autosaveName))
    }
}
