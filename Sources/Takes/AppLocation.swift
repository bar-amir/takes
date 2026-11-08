import AppKit

/// Where Takes is running from. Opened straight from the disk image, or from Downloads before it was moved,
/// macOS runs a downloaded app from a hidden read-only copy ("app translocation"). Then "Show Takes in Finder"
/// points at a folder nobody can find, the login item can't be made, and updates can't be installed. Onboarding
/// and setup offer to move it to Applications and open it again from there.
enum AppLocation {
    static var bundleURL: URL { Bundle.main.bundleURL }

    /// Running from macOS's translocation copy.
    static func isTranslocated(_ url: URL = bundleURL) -> Bool { url.path.contains("/AppTranslocation/") }

    /// Running from a read-only volume, such as the mounted disk image.
    static func isOnReadOnlyVolume(_ url: URL = bundleURL) -> Bool {
        (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true
    }

    static func isInApplications(_ url: URL = bundleURL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        return url.path.hasPrefix("/Applications/") || url.path.hasPrefix(home + "/")
    }

    /// Whether to offer the move: a translocated or disk-image copy. A copy sitting in Downloads that macOS ran in
    /// place is left alone; it works, and moving it is the user's call.
    static var needsMove: Bool { isTranslocated() || isOnReadOnlyVolume() }

    /// "the disk image" or "a temporary folder", for the note.
    static var whereItRuns: String { isOnReadOnlyVolume() ? String(localized: "the disk image") : String(localized: "a temporary folder") }

    enum MoveError: LocalizedError {
        case alreadyThere, copyFailed(String), couldNotOpen

        var errorDescription: String? {
            switch self {
            case .alreadyThere: return String(localized: "Takes is already in Applications.")
            case .copyFailed(let why): return String(localized: "Couldn't copy Takes to Applications: \(why)")
            case .couldNotOpen: return String(localized: "Takes was copied to Applications but couldn't be opened from there. Open it from Applications yourself.")
            }
        }
    }

    /// Copies this app to /Applications (or ~/Applications when that isn't writable), replacing an older copy, lets
    /// go of the download quarantine so macOS runs it in place, opens the copy and quits this one. Only ever
    /// called from a button the user pressed.
    @MainActor
    static func moveToApplications() throws {
        let source = bundleURL
        let fm = FileManager.default
        let system = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let folder = fm.isWritableFile(atPath: system.path) ? system : fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(source.lastPathComponent)
        guard destination.standardizedFileURL != source.standardizedFileURL else { throw MoveError.alreadyThere }
        do {
            // Only an older Takes is replaced, never something else with the same name.
            if fm.fileExists(atPath: destination.path) {
                guard Bundle(url: destination)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                    throw MoveError.copyFailed(String(localized: "something that isn't Takes is already at \(destination.path)"))
                }
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: source, to: destination)
        } catch let error as MoveError {
            throw error
        } catch {
            throw MoveError.copyFailed(error.localizedDescription)
        }
        removeQuarantine(destination)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { app, _ in
            DispatchQueue.main.async {
                if app != nil { NSApp.terminate(nil) }
            }
        }
    }

    /// The download quarantine on the copy; without this macOS would translocate the copy too.
    private static func removeQuarantine(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
