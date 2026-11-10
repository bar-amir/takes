import AppKit

/// Crash reports the user sends themselves. macOS writes one to ~/Library/Logs/DiagnosticReports when Takes
/// crashes, but only App Store apps get them back from Apple. On the next launch Takes offers to open a GitHub bug
/// report with a short summary filled in and shows the full file in Finder, so the user can look at both and decide.
/// Takes reads the file on this Mac and never sends anything itself.
enum CrashReports {
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    }

    /// Reports older than this aren't offered at launch: by then the user has moved on, or updated.
    static let recentDays: Double = 14
    /// Frames of the crashed thread put in the summary; enough to see where it stopped, short enough for a URL.
    static let frameLimit = 20
    /// Longest symbol kept in a frame; Swift generics can make one run to thousands of characters.
    static let symbolLimit = 160

    struct Report: Equatable {
        let file: URL
        let date: Date
        let summary: String
    }

    static var currentVersion: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }

    /// The newest crash report of this version of the app in `folder`, if it is newer than `after` and
    /// `recentDays`. A crash in an older version is left out: the update may well have fixed it.
    static func latest(in folder: URL = folder, bundleID: String? = Bundle.main.bundleIdentifier,
                       version: String? = currentVersion, after: Date?, now: Date = Date()) -> Report? {
        guard let bundleID, let version else { return nil }
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        // Settings keep dates to the second, so the report already asked about must not come back as newer.
        let cutoff = max((after ?? .distantPast).addingTimeInterval(1), now.addingTimeInterval(-recentDays * 86_400))
        let candidates = files
            .filter { $0.pathExtension == "ips" && $0.lastPathComponent.hasPrefix("Takes") }
            .compactMap { url -> (URL, Date, String)? in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                // When it crashed, from the report itself: macOS sometimes touches old reports, so the file's date
                // can be much later than the crash.
                guard let date = crashDate(of: text)
                        ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate),
                      date > cutoff else { return nil }
                return (url, date, text)
            }
            .sorted { $0.1 > $1.1 }
        for (url, date, text) in candidates {
            guard let summary = summary(of: text, bundleID: bundleID, version: version) else { continue }
            return Report(file: url, date: date, summary: summary)
        }
        return nil
    }

    /// The header's "timestamp" ("2026-11-09 08:05:41.00 +0200").
    static func crashDate(of text: String) -> Date? {
        guard let line = text.split(separator: "\n", maxSplits: 1).first,
              let stamp = json(line)?["timestamp"] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SS Z"
        return formatter.date(from: stamp)
    }

    /// What the bug report says about a crash: versions, the exception and the crashed thread's frames. Nothing
    /// else from the report: no paths (they hold the user name), no other threads, no messages from the app.
    /// Nil when `text` isn't a crash report of `bundleID` (and of `version`, when given).
    static func summary(of text: String, bundleID: String, version wanted: String? = nil) -> String? {
        let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let header = json(parts[0]), let body = json(parts[1]),
              header["bundleID"] as? String == bundleID,
              wanted == nil || header["app_version"] as? String == wanted,
              let threads = body["threads"] as? [[String: Any]] else { return nil }
        let images = body["usedImages"] as? [[String: Any]] ?? []
        let crashed = body["faultingThread"] as? Int ?? 0
        guard threads.indices.contains(crashed) else { return nil }

        var lines: [String] = []
        let version = header["app_version"] as? String ?? "?"
        let build = (header["build_version"] as? String).map { " (\($0))" } ?? ""
        lines.append("Takes \(version)\(build), \(header["os_version"] as? String ?? "macOS ?")")
        let exception = body["exception"] as? [String: Any] ?? [:]
        var what = exception["type"] as? String ?? "?"
        if let signal = exception["signal"] as? String { what += " (\(signal))" }
        if let indicator = (body["termination"] as? [String: Any])?["indicator"] as? String { what += ", \(indicator)" }
        lines.append(what)
        if let slice = header["slice_uuid"] as? String { lines.append("Binary \(slice)") }
        lines.append("Thread \(crashed) crashed:")

        let frames = threads[crashed]["frames"] as? [[String: Any]] ?? []
        for (number, frame) in frames.prefix(frameLimit).enumerated() {
            let index = frame["imageIndex"] as? Int ?? -1
            let image = images.indices.contains(index) ? images[index]["name"] as? String ?? "?" : "?"
            var line = "\(number)  \(image)  "
            if let symbol = frame["symbol"] as? String {
                line += symbol.count > symbolLimit ? String(symbol.prefix(symbolLimit)) + "…" : symbol
            } else {
                line += "0x" + String(frame["imageOffset"] as? Int ?? 0, radix: 16)
            }
            if let file = frame["sourceFile"] as? String, let lineNumber = frame["sourceLine"] as? Int {
                line += "  (\(URL(fileURLWithPath: file).lastPathComponent):\(lineNumber))"
            }
            lines.append(line)
        }
        if frames.count > frameLimit { lines.append("…") }
        return lines.joined(separator: "\n")
    }

    private static func json(_ text: Substring) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }

    // MARK: Offering one

    /// A crash since the last one the user was asked about, unless they said not to ask.
    static func pending(_ settings: AppSettings, in folder: URL = folder, bundleID: String? = Bundle.main.bundleIdentifier,
                        version: String? = currentVersion, now: Date = Date()) -> Report? {
        guard settings.offerCrashReports else { return nil }
        return latest(in: folder, bundleID: bundleID, version: version, after: settings.lastCrashReport, now: now)
    }

    /// The bug form with the summary filled in, and the full report shown in Finder to attach.
    @MainActor static func send(_ report: Report) {
        NSWorkspace.shared.open(ReportProblem.currentURL(crash: report.summary))
        NSWorkspace.shared.activateFileViewerSelecting([report.file])
        handled(report)
    }

    @MainActor static func handled(_ report: Report) {
        let store = Store.shared
        if let date = answered(report, after: store.settings.lastCrashReport) { store.settings.lastCrashReport = date }
    }

    /// The date to remember once `report` is answered, or nil to keep `last`: an older report answered later
    /// mustn't bring back newer ones already asked about.
    static func answered(_ report: Report, after last: Date?) -> Date? {
        (last ?? .distantPast) < report.date ? report.date : nil
    }
}
