import XCTest
@testable import Takes

final class CrashReportsTests: XCTestCase {
    private let bundleID = "com.baramir.takes"

    /// A crash report as macOS writes it: a one-line JSON header, then the JSON body.
    private func report(bundleID: String = "com.baramir.takes", frames: Int = 3, crashed: Date? = nil) -> String {
        let timestamp: Any = crashed.map { Self.stamp.string(from: $0) } ?? NSNull()
        let header: [String: Any] = [
            "app_name": "Takes", "app_version": "0.8.0", "build_version": "90", "bundleID": bundleID,
            "os_version": "macOS 26.1 (25B78)", "timestamp": timestamp, "slice_uuid": "560f1a55-0f18-3bad-a638-fc3e13ee93a8", "bug_type": "309",
        ]
        var threadFrames: [[String: Any]] = [
            ["imageOffset": 1_651_928, "imageIndex": 0, "symbol": "Swift runtime failure: Index out of range",
             "sourceFile": "/Users/runner/work/takes/Sources/Takes/PanelController.swift", "sourceLine": 342],
            ["imageOffset": 4096, "imageIndex": 0],
            ["imageOffset": 12, "imageIndex": 1, "symbol": "-[NSApplication run]"],
        ]
        while threadFrames.count < frames { threadFrames.append(["imageOffset": 1, "imageIndex": 1]) }
        let body: [String: Any] = [
            "exception": ["type": "EXC_BREAKPOINT", "signal": "SIGTRAP"],
            "termination": ["indicator": "Trace/BPT trap: 5"],
            "asi": ["Takes": ["a message the app wrote"]],
            "faultingThread": 1,
            "threads": [["frames": [["imageOffset": 0, "imageIndex": 1]]], ["frames": threadFrames]],
            "usedImages": [
                ["name": "Takes", "path": "/Users/ido/Applications/Takes.app/Contents/MacOS/Takes"],
                ["name": "AppKit", "path": "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"],
            ],
        ]
        func line(_ object: [String: Any]) -> String {
            String(data: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), encoding: .utf8)!
        }
        return line(header) + "\n" + line(body)
    }

    func testSummaryHasVersionsExceptionAndCrashedThread() throws {
        let summary = try XCTUnwrap(CrashReports.summary(of: report(), bundleID: bundleID))
        XCTAssertEqual(summary, """
            Takes 0.8.0 (90), macOS 26.1 (25B78)
            EXC_BREAKPOINT (SIGTRAP), Trace/BPT trap: 5
            Binary 560f1a55-0f18-3bad-a638-fc3e13ee93a8
            Thread 1 crashed:
            0  Takes  Swift runtime failure: Index out of range  (PanelController.swift:342)
            1  Takes  0x1000
            2  AppKit  -[NSApplication run]
            """)
    }

    func testSummaryLeavesOutPathsAndAppMessages() throws {
        let summary = try XCTUnwrap(CrashReports.summary(of: report(), bundleID: bundleID))
        XCTAssertFalse(summary.contains("/Users"))
        XCTAssertFalse(summary.contains("ido"))
        XCTAssertFalse(summary.contains("a message the app wrote"))
    }

    func testSummaryIsCutShort() throws {
        let summary = try XCTUnwrap(CrashReports.summary(of: report(frames: 60), bundleID: bundleID))
        XCTAssertEqual(summary.split(separator: "\n").count, 4 + CrashReports.frameLimit + 1)
        XCTAssertTrue(summary.hasSuffix("…"))
    }

    func testOtherAppsAndOtherFilesAreNotReports() {
        XCTAssertNil(CrashReports.summary(of: report(bundleID: "com.example.other"), bundleID: bundleID))
        XCTAssertNil(CrashReports.summary(of: "not a crash report", bundleID: bundleID))
        XCTAssertNil(CrashReports.summary(of: "{\"bundleID\":\"com.baramir.takes\"}\n{}", bundleID: bundleID))
    }

    // MARK: Finding one

    private func folder(_ files: [(String, String, Date)]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        for (name, text, date) in files {
            let file = url.appendingPathComponent(name)
            try text.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
        }
        return url
    }

    func testLatestPicksTheNewestReportOfThisApp() throws {
        let now = Date()
        let url = try folder([
            ("Takes-old.ips", report(), now.addingTimeInterval(-3600)),
            ("Takes-new.ips", report(), now.addingTimeInterval(-60)),
            ("Takes-other.ips", report(bundleID: "com.example.other"), now),
            ("Takes-hang.spin", report(), now),
            ("Other-app.ips", report(), now),
        ])
        let latest = try XCTUnwrap(CrashReports.latest(in: url, bundleID: bundleID, version: "0.8.0", after: nil, now: now))
        XCTAssertEqual(latest.file.lastPathComponent, "Takes-new.ips")
    }

    func testAReportIsOfferedOnce() throws {
        let now = Date()
        let crashed = now.addingTimeInterval(-60.4)
        let url = try folder([("Takes-a.ips", report(), crashed)])
        XCTAssertNotNil(CrashReports.latest(in: url, bundleID: bundleID, version: "0.8.0", after: nil, now: now))
        // Settings save the date to the second, so the same report reads back a little earlier.
        let saved = Date(timeIntervalSince1970: crashed.timeIntervalSince1970.rounded(.down))
        XCTAssertNil(CrashReports.latest(in: url, bundleID: bundleID, version: "0.8.0", after: saved, now: now))
        XCTAssertNotNil(CrashReports.latest(in: url, bundleID: bundleID, version: "0.8.0", after: crashed.addingTimeInterval(-120), now: now))
    }

    func testCrashesOfAnotherVersionAreNotOffered() throws {
        let now = Date()
        let url = try folder([("Takes-a.ips", report(), now.addingTimeInterval(-60))])
        XCTAssertNil(CrashReports.latest(in: url, bundleID: bundleID, version: "0.9.0", after: nil, now: now))
        XCTAssertNil(CrashReports.summary(of: report(), bundleID: bundleID, version: "0.9.0"))
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SS Z"
        return formatter
    }()

    func testTheCrashTimeComesFromTheReportNotTheFile() throws {
        let now = Date()
        // macOS touched an old report just now; it crashed three weeks ago.
        let old = now.addingTimeInterval(-21 * 86_400)
        let url = try folder([("Takes-old.ips", report(crashed: old), now)])
        XCTAssertNil(CrashReports.latest(in: url, bundleID: bundleID, version: "0.8.0", after: nil, now: now))
        let date = try XCTUnwrap(CrashReports.crashDate(of: report(crashed: old)))
        XCTAssertEqual(date.timeIntervalSince1970, old.timeIntervalSince1970, accuracy: 1)
    }

    func testOldReportsAreNotOffered() throws {
        let now = Date()
        let url = try folder([("Takes-a.ips", report(), now.addingTimeInterval(-(CrashReports.recentDays + 1) * 86_400))])
        XCTAssertNil(CrashReports.latest(in: url, bundleID: bundleID, version: "0.8.0", after: nil, now: now))
    }

    // MARK: Offering one

    func testNoOfferWhenTheUserSaidNotToAsk() throws {
        let now = Date()
        let url = try folder([("Takes-a.ips", report(), now.addingTimeInterval(-60))])
        var settings = AppSettings()
        XCTAssertNotNil(CrashReports.pending(settings, in: url, bundleID: bundleID, version: "0.8.0", now: now))
        settings.offerCrashReports = false
        XCTAssertNil(CrashReports.pending(settings, in: url, bundleID: bundleID, version: "0.8.0", now: now))
    }

    func testNoOfferForACrashAlreadyAnswered() throws {
        let now = Date()
        let url = try folder([("Takes-a.ips", report(), now.addingTimeInterval(-60))])
        var settings = AppSettings()
        let report = try XCTUnwrap(CrashReports.pending(settings, in: url, bundleID: bundleID, version: "0.8.0", now: now))
        settings.lastCrashReport = CrashReports.answered(report, after: settings.lastCrashReport)
        // Saved and read back, the date loses its fraction of a second.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let saved = try decoder.decode(AppSettings.self, from: encoder.encode(settings))
        XCTAssertNil(CrashReports.pending(saved, in: url, bundleID: bundleID, version: "0.8.0", now: now))
    }

    func testAnsweringAnOlderReportKeepsTheNewerDate() {
        let now = Date()
        let older = CrashReports.Report(file: URL(fileURLWithPath: "/tmp/a.ips"), date: now.addingTimeInterval(-600), summary: "")
        XCTAssertNil(CrashReports.answered(older, after: now))
        XCTAssertEqual(CrashReports.answered(older, after: nil), older.date)
        XCTAssertEqual(CrashReports.answered(older, after: now.addingTimeInterval(-3600)), older.date)
    }

    func testACrashedThreadThatIsntThereIsNotAReport() throws {
        let text = report().replacingOccurrences(of: "\"faultingThread\":1", with: "\"faultingThread\":7")
        XCTAssertTrue(text.contains("\"faultingThread\":7"))
        XCTAssertNil(CrashReports.summary(of: text, bundleID: bundleID))
    }

    // MARK: The bug form

    func testBugReportCarriesTheSummary() throws {
        let url = ReportProblem.url(takesVersion: "0.8.0", macOSVersion: "26.1", engine: .claudeCode, crash: "Thread 0 crashed:")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "crash" }?.value, "Thread 0 crashed:")
        XCTAssertEqual(items.first { $0.name == "title" }?.value, "Takes quit unexpectedly")
        let plain = ReportProblem.url(takesVersion: "0.8.0", macOSVersion: "26.1", engine: .claudeCode)
        XCTAssertFalse(plain.absoluteString.contains("crash"))
    }

    func testAFullSummaryFitsInAURL() throws {
        let summary = try XCTUnwrap(CrashReports.summary(of: report(frames: 60), bundleID: bundleID))
        let url = ReportProblem.url(takesVersion: "0.8.0", macOSVersion: "26.1", engine: .claudeCode, crash: summary)
        XCTAssertLessThan(url.absoluteString.count, 8000)
    }

    func testSettingsFromBeforeKeepOffering() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(settings.offerCrashReports)
        XCTAssertNil(settings.lastCrashReport)
    }
}
