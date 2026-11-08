import Foundation
import ServiceManagement

/// Open Takes at login, through the system's login items (System Settings › General › Login Items). Off until the
/// user turns it on, in onboarding's last step or Settings › General. macOS is the source of truth, so nothing is
/// kept in settings.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        guard !Store.readOnly else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func set(_ on: Bool) throws {
        guard !Store.readOnly else { return }
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    /// The error in plain words. Registration fails for an app macOS is running from a temporary place (opened
    /// from the disk image or Downloads without being moved), and when the user has blocked it in Settings.
    static func explain(_ error: Error) -> String {
        if AppLocation.needsMove {
            return String(localized: "Move Takes to Applications first; macOS doesn't keep login items for an app run from \(AppLocation.whereItRuns).")
        }
        if SMAppService.mainApp.status == .requiresApproval {
            return String(localized: "Allow Takes under System Settings › General › Login Items.")
        }
        return String(localized: "Couldn't set this: \(error.localizedDescription)")
    }
}
