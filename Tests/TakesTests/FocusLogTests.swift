import XCTest

@testable import Takes

/// focus.log holds one line per summon and per paste, metadata only, and doesn't grow without end.
final class FocusLogTests: XCTestCase {
    private var file: URL!

    override func setUp() {
        file = FileManager.default.temporaryDirectory.appendingPathComponent("takes-focus-\(UUID().uuidString).log")
        FocusLog.fileOverride = file
    }

    override func tearDown() {
        FocusLog.fileOverride = nil
        try? FileManager.default.removeItem(at: file)
    }

    private func lines() -> [String] {
        ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    func testPasteLinesSayWhichPathWasTakenAndCarryNoText() {
        let target = FocusSnapshot(app: nil, text: "a secret draft", source: .field, caretRect: nil)
        FocusLog.paste(target, "paste sent\tfocus same, text same")
        FocusLog.paste(target, "paste sent\tfocus equivalent, text same")
        FocusLog.paste(target, "paste not sent\tfocus other, text notCompared")
        let lines = lines()
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasSuffix("\t?\tpaste sent\tfocus same, text same"))
        XCTAssertTrue(lines[1].hasSuffix("\tpaste sent\tfocus equivalent, text same"))
        XCTAssertTrue(lines[2].hasSuffix("\tpaste not sent\tfocus other, text notCompared"))
        XCTAssertFalse(lines.joined().contains("secret"))
    }

    func testSummonLineHasTheCountNotTheText() {
        FocusLog.append(FocusSnapshot(app: nil, text: "a secret draft", source: .field, caretRect: nil, method: "AXValue"), role: "AXTextArea/-")
        XCTAssertEqual(lines().count, 1)
        XCTAssertTrue(lines()[0].contains("AXTextArea/-\tAXValue\tchars=14"))
        XCTAssertFalse(lines()[0].contains("secret"))
    }

    func testOldestLinesAreDroppedPastTheCap() throws {
        let line = String(repeating: "x", count: 99) + "\n"
        let big = String(repeating: line, count: FocusLog.cap / 100 + 50)
        try Data(big.utf8).write(to: file)
        XCTAssertGreaterThan(big.utf8.count, FocusLog.cap)

        FocusLog.paste(nil, "paste sent\tfocus same, text same")
        let data = try Data(contentsOf: file)
        XCTAssertLessThanOrEqual(data.count, FocusLog.keep + 200)
        let lines = lines()
        XCTAssertTrue(lines.last?.hasSuffix("paste sent\tfocus same, text same") == true, "the newest line is kept")
        XCTAssertTrue(lines.dropLast().allSatisfy { $0.count == 99 }, "cut at a line, never through one")
    }

    func testNewestKeepsWholeLines() {
        let data = Data("first line\nsecond line\nthird line\n".utf8)
        XCTAssertEqual(FocusLog.newest(of: data, keeping: 100), data, "under the limit: untouched")
        XCTAssertEqual(String(decoding: FocusLog.newest(of: data, keeping: 15), as: UTF8.self), "third line\n")
        XCTAssertEqual(String(decoding: FocusLog.newest(of: data, keeping: 27), as: UTF8.self), "second line\nthird line\n")
    }
}
