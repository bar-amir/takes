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

    /// Where `copyToApplications` left things.
    enum Placed: Equatable {
        /// This copy is now in Applications, in place of an older one if there was one.
        case copied(URL)
        /// A newer Takes is already there. It's left as it is and opened instead.
        case newerThere(URL)
    }

    /// Copies this app to /Applications (or ~/Applications when that isn't writable), replacing an older copy, lets
    /// go of the download quarantine so macOS runs it in place, opens the copy and quits this one. A newer Takes
    /// already there is opened instead. Only ever called from a button the user pressed. Every way it can fail is
    /// thrown, so the button can say what happened.
    @MainActor
    static func moveToApplications() async throws {
        switch try copyToApplications() {
        case .copied(let destination):
            removeQuarantine(destination)
            try await open(destination)
        case .newerThere(let destination):
            try await open(destination)
        }
        NSApp.terminate(nil)
    }

    /// The copy step of `moveToApplications`. The copy goes in under a temporary name and takes the place of the old
    /// one only once it's whole, so a copy that fails part-way never leaves Applications without Takes.
    static func copyToApplications(from source: URL = bundleURL, fileManager fm: FileManager = .default,
                                   applications: URL? = nil) throws -> Placed {
        let system = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let folder = applications
            ?? (fm.isWritableFile(atPath: system.path) ? system : fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true))
        let destination = folder.appendingPathComponent(source.lastPathComponent)
        guard destination.standardizedFileURL != source.standardizedFileURL else { throw MoveError.alreadyThere }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let replacing = fm.fileExists(atPath: destination.path)
            if replacing {
                // Only an older Takes is replaced, never something else with the same name, and never a newer Takes.
                guard Bundle(url: destination)?.bundleIdentifier == Bundle(url: source)?.bundleIdentifier else {
                    throw MoveError.copyFailed(String(localized: "something that isn't Takes is already at \(destination.path)"))
                }
                if isNewer(destination, than: source) { return .newerThere(destination) }
            }
            let temporary = folder.appendingPathComponent(".\(source.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).app")
            do {
                try fm.copyItem(at: source, to: temporary)
                if replacing {
                    _ = try fm.replaceItemAt(destination, withItemAt: temporary)
                } else {
                    try fm.moveItem(at: temporary, to: destination)
                }
            } catch {
                try? fm.removeItem(at: temporary)
                throw error
            }
        } catch let error as MoveError {
            throw error
        } catch {
            throw MoveError.copyFailed(error.localizedDescription)
        }
        return .copied(destination)
    }

    /// Whether the Takes at `installed` is a newer version than the one at `source`: the version, then the build.
    static func isNewer(_ installed: URL, than source: URL) -> Bool {
        func info(_ url: URL) -> [String: Any] {
            (NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any]) ?? [:]
        }
        let (a, b) = (info(installed), info(source))
        for key in ["CFBundleShortVersionString", "CFBundleVersion"] {
            guard let x = a[key] as? String, let y = b[key] as? String else { continue }
            switch ClaudeCodeEngine.compareVersions(x, y) {
            case .orderedDescending: return true
            case .orderedAscending: return false
            case .orderedSame: continue
            }
        }
        return false
    }

    /// Opens the copy as a new instance; throws `couldNotOpen` when macOS doesn't start it.
    @MainActor
    private static func open(_ destination: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        let opened: Bool = await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { app, error in
                continuation.resume(returning: app != nil && error == nil)
            }
        }
        guard opened else { throw MoveError.couldNotOpen }
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
