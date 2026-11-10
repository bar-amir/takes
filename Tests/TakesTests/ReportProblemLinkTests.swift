import XCTest
@testable import Takes

/// The prefilled bug report is a link; GitHub and browsers refuse one that is too long.
final class ReportProblemLinkTests: XCTestCase {
    private func link(crash: String?) -> URL {
        ReportProblem.url(takesVersion: "0.8.0", macOSVersion: "26.1", engine: .claudeCode, crash: crash)
    }

    private func items(_ url: URL) throws -> [URLQueryItem] {
        try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    }

    private func crashText(_ url: URL) throws -> String {
        try XCTUnwrap(items(url).first { $0.name == "crash" }?.value)
    }

    /// A summary the way `CrashReports.summary` writes one, with `frames` lines of `width` characters each.
    private func summary(frames: Int, width: Int = 100) -> String {
        (["Takes 0.8.0 (90), macOS 26.1", "EXC_BREAKPOINT (SIGTRAP)", "Thread 0 crashed:"]
            + (0..<frames).map { "\($0)  Takes  " + String(repeating: "s", count: width) }).joined(separator: "\n")
    }

    func testAShortSummaryIsLeftAlone() throws {
        let text = summary(frames: 5)
        let url = link(crash: text)
        XCTAssertEqual(try crashText(url), text)
        XCTAssertFalse(url.absoluteString.contains("cut%20to%20fit"))
    }

    func testALongSummaryIsCutToFitAndSaysSo() throws {
        let text = summary(frames: 400)
        let url = link(crash: text)
        XCTAssertLessThanOrEqual(url.absoluteString.count, ReportProblem.maxURLLength)
        let kept = try crashText(url)
        XCTAssertTrue(kept.hasSuffix(ReportProblem.trimmedNote))
        XCTAssertTrue(kept.hasPrefix("Takes 0.8.0 (90), macOS 26.1\nEXC_BREAKPOINT (SIGTRAP)\nThread 0 crashed:\n0  Takes"))
        XCTAssertLessThan(kept.count, text.count)
    }

    func testTheCutIsAsLongAsItCanBeAndEndsAtALine() throws {
        let text = summary(frames: 400)
        let kept = try crashText(link(crash: text))
        // Everything before the note is whole lines of the original, in order.
        let body = String(kept.dropLast(ReportProblem.trimmedNote.count + 1))
        XCTAssertTrue(text.hasPrefix(body + "\n"))
        // One more line would not have fit: with it (and the note) the link is cut back to the same text.
        let nextLine = text.dropFirst(body.count + 1).prefix { $0 != "\n" }
        let oneMore = body + "\n" + nextLine + "\n" + ReportProblem.trimmedNote
        XCTAssertEqual(try crashText(link(crash: oneMore)), kept)
    }

    func testTheOtherFieldsSurviveTheCut() throws {
        let url = link(crash: summary(frames: 400))
        let all = try items(url)
        XCTAssertEqual(all.first { $0.name == "template" }?.value, "bug_report.yml")
        XCTAssertEqual(all.first { $0.name == "engine" }?.value, "Claude Code on this Mac")
        XCTAssertEqual(all.first { $0.name == "versions" }?.value, "Takes 0.8.0, macOS 26.1")
        XCTAssertEqual(all.first { $0.name == "title" }?.value, "Takes quit unexpectedly")
        XCTAssertTrue(url.absoluteString.hasPrefix("https://github.com/bar-amir/takes/issues/new?"))
    }

    func testOneVeryLongLineIsCutInTheMiddleOfTheLine() throws {
        // A single symbol of 20,000 characters and nothing else: there is no line end to cut at.
        let url = link(crash: "0  Takes  " + String(repeating: "x", count: 20_000))
        XCTAssertLessThanOrEqual(url.absoluteString.count, ReportProblem.maxURLLength)
        let kept = try crashText(url)
        XCTAssertTrue(kept.hasSuffix(ReportProblem.trimmedNote))
        XCTAssertTrue(kept.hasPrefix("0  Takes  xxxx"))
    }

    func testCharactersThatEncodeToManyBytesStillFit() throws {
        // Each of these becomes 9 to 12 characters in the link.
        let url = link(crash: String(repeating: "…😀é\n", count: 2_000))
        XCTAssertLessThanOrEqual(url.absoluteString.count, ReportProblem.maxURLLength)
        let kept = try crashText(url)
        XCTAssertTrue(kept.hasSuffix(ReportProblem.trimmedNote))
        // No half characters: it decoded to text, and every line before the note is a whole "…😀é".
        for line in kept.split(separator: "\n").dropLast() { XCTAssertEqual(line, "…😀é") }
    }

    func testASummaryThatJustFitsIsNotCut() throws {
        // Grow the summary one line at a time to the last size that fits whole: it comes back as it was.
        func whole(_ frames: Int) throws -> Bool { try crashText(link(crash: summary(frames: frames))) == summary(frames: frames) }
        var frames = 0
        while try whole(frames + 1) { frames += 1 }
        XCTAssertGreaterThan(frames, 10)
        let last = link(crash: summary(frames: frames))
        XCTAssertLessThanOrEqual(last.absoluteString.count, ReportProblem.maxURLLength)
        // One line more doesn't fit whole, so it is cut and says so.
        let next = link(crash: summary(frames: frames + 1))
        XCTAssertTrue(try crashText(next).hasSuffix(ReportProblem.trimmedNote))
        XCTAssertLessThanOrEqual(next.absoluteString.count, ReportProblem.maxURLLength)
    }

    func testPlusSignsReachGitHubAsPlusSigns() throws {
        // A raw "+" in a link is read as a space; symbols such as `static Int.+ infix` must not lose it.
        let url = link(crash: "0  Takes  static Swift.Int.+ infix(Int, Int)")
        XCTAssertFalse(url.absoluteString.contains("+"))
        XCTAssertTrue(url.absoluteString.contains("%2B"))
        XCTAssertEqual(try crashText(url), "0  Takes  static Swift.Int.+ infix(Int, Int)")
    }

    func testNoCrashMeansNoCrashFields() throws {
        let url = link(crash: nil)
        XCTAssertNil(try items(url).first { $0.name == "crash" })
        XCTAssertNil(try items(url).first { $0.name == "title" })
        XCTAssertLessThan(url.absoluteString.count, 400)
    }

    // MARK: The summary itself

    private func crashReport(symbol: String, frames: Int) -> String {
        let header: [String: Any] = ["app_version": "0.8.0", "build_version": "90", "bundleID": "com.baramir.takes", "os_version": "macOS 26.1"]
        let body: [String: Any] = [
            "exception": ["type": "EXC_BREAKPOINT"],
            "faultingThread": 0,
            "threads": [["frames": (0..<frames).map { ["imageOffset": $0, "imageIndex": 0, "symbol": symbol] as [String: Any] }]],
            "usedImages": [["name": "Takes"]],
        ]
        func line(_ object: [String: Any]) -> String {
            String(data: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), encoding: .utf8)!
        }
        return line(header) + "\n" + line(body)
    }

    func testAVeryLongSymbolIsShortenedInTheSummary() throws {
        let long = String(repeating: "g", count: 5_000)
        let summary = try XCTUnwrap(CrashReports.summary(of: crashReport(symbol: long, frames: 3), bundleID: "com.baramir.takes"))
        let frames = summary.split(separator: "\n").filter { $0.hasPrefix("0  ") || $0.hasPrefix("1  ") || $0.hasPrefix("2  ") }
        XCTAssertEqual(frames.count, 3)
        for frame in frames {
            XCTAssertTrue(frame.hasSuffix(String(repeating: "g", count: CrashReports.symbolLimit) + "…"))
            XCTAssertLessThan(frame.count, CrashReports.symbolLimit + 20)
        }
    }

    func testASymbolAtTheLimitIsKept() throws {
        let exact = String(repeating: "g", count: CrashReports.symbolLimit)
        let summary = try XCTUnwrap(CrashReports.summary(of: crashReport(symbol: exact, frames: 1), bundleID: "com.baramir.takes"))
        XCTAssertTrue(summary.hasSuffix("0  Takes  " + exact))
    }

    func testTwentyLongFramesStillMakeAUsableLink() throws {
        // The worst a summary can be: 20 frames of the longest kept symbol, as the app builds it.
        let long = String(repeating: "(Generic<A, B>) ", count: 400)
        let text = try XCTUnwrap(CrashReports.summary(of: crashReport(symbol: long, frames: 60), bundleID: "com.baramir.takes"))
        let url = link(crash: text)
        XCTAssertLessThanOrEqual(url.absoluteString.count, ReportProblem.maxURLLength)
        XCTAssertTrue(try crashText(url).hasPrefix("Takes 0.8.0 (90), macOS 26.1\nEXC_BREAKPOINT\nThread 0 crashed:\n0  Takes"))
    }
}
