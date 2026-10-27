import AppKit
import Sparkle

/// Automatic updates through Sparkle. Only release builds carry a feed URL and public key in
/// Info.plist, so development builds never touch the release channel.
@MainActor
final class Updater {
    static let shared = Updater()
    private(set) var controller: SPUStandardUpdaterController?

    var isAvailable: Bool { controller != nil }

    func start() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil,
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil else { return }
        // Sparkle asks the user on the second launch whether to check automatically
        // (PRIVACY.md promises to ask before anything new leaves the Mac).
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
}
