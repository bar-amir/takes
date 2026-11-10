import XCTest

@testable import Takes

/// runs.jsonl is capped (the oldest lines go first) and holds metadata only.
/// Every test writes to its own temporary file, never to ~/Library/Logs/Takes.
final class RunLogTests: XCTestCase {
    private var file: URL!
    private var wasReadOnly = false

    override func setUpWithError() throws {
        file = FileManager.default.temporaryDirectory.appendingPathComponent("takes-runlog-\(UUID().uuidString).jsonl")
        wasReadOnly = Store.readOnly
        Store.readOnly = false
    }

    override func tearDownWithError() throws {
        Store.readOnly = wasReadOnly
        try? FileManager.default.removeItem(at: file)
    }

    private func lines() throws -> [[String: Any]] {
        try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
    }

    private func run(_ number: Int) -> [String: Any] {
        [
            "kind": "app", "model": Models.sonnet, "effort": "low", "takes": 3, "engine": "claudeCode",
            "wallMs": 4200 + number, "firstTextMs": 900, "app": "com.tinyspeck.slackmacgap", "n": number,
        ]
    }

    func testEachRunIsOneLine() throws {
        RunLog.append(run(1), to: file)
        RunLog.append(run(2), to: file)
        let written = try lines()
        XCTAssertEqual(written.map { $0["n"] as? Int }, [1, 2])
        XCTAssertNotNil(written[0]["at"])
    }

    func testTheLogStaysUnderItsCapAndKeepsTheNewestRuns() throws {
        let runs = RunLog.maxBytes / 150
        for n in 1...runs { RunLog.append(run(n), to: file) }
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int ?? 0
        XCTAssertLessThanOrEqual(size, RunLog.maxBytes)
        let written = try lines()
        XCTAssertEqual(written.last?["n"] as? Int, runs, "the newest run is there")
        XCTAssertNotEqual(written.first?["n"] as? Int, 1, "the oldest are gone")
        let numbers = written.compactMap { $0["n"] as? Int }
        XCTAssertEqual(numbers, Array(numbers[0]...runs), "in order, with nothing missing in between")
    }

    func testALogAlreadyTooBigIsCutBackOnTheNextRun() throws {
        let old = Data(String(repeating: "{\"n\":0}\n", count: RunLog.maxBytes / 8 * 3).utf8)
        try old.write(to: file)
        XCTAssertGreaterThan(old.count, RunLog.maxBytes)
        RunLog.append(run(7), to: file)
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int ?? 0
        XCTAssertLessThanOrEqual(size, RunLog.maxBytes)
        XCTAssertEqual(try lines().last?["n"] as? Int, 7)
    }

    func testCuttingKeepsWholeLinesOnly() {
        // Three lines of 8 bytes each.
        let data = Data("{\"n\":1}\n{\"n\":2}\n{\"n\":3}\n".utf8)
        XCTAssertEqual(String(decoding: RunLog.newest(data, within: 12), as: UTF8.self), "{\"n\":3}\n", "the partial line before it is dropped")
        XCTAssertEqual(String(decoding: RunLog.newest(data, within: 16), as: UTF8.self), "{\"n\":2}\n{\"n\":3}\n", "a cut that falls on a line start keeps it")
        XCTAssertEqual(String(decoding: RunLog.newest(data, within: 17), as: UTF8.self), "{\"n\":2}\n{\"n\":3}\n")
        XCTAssertEqual(RunLog.newest(data, within: 3), Data(), "less than one line leaves nothing")
        XCTAssertEqual(RunLog.newest(data, within: 1000), data)
    }

    func testOnlyMetadataIsLogged() throws {
        var entry = run(1)
        entry["draft"] = String(repeating: "Dear team, ", count: 40)
        entry["takes"] = ["A whole take", "Another"]
        entry["nested"] = ["text": "hi"]
        RunLog.append(entry, to: file)
        let written = try XCTUnwrap(lines().first)
        XCTAssertNil(written["draft"], "long text isn't metadata")
        XCTAssertNil(written["nested"])
        XCTAssertEqual(written["takes"] as? Int, nil, "a list of takes is dropped, even under the number's name")
        XCTAssertEqual(written["model"] as? String, Models.sonnet)
        XCTAssertEqual(written["wallMs"] as? Int, 4201)
        XCTAssertEqual(written["app"] as? String, "com.tinyspeck.slackmacgap")
    }

    func testSnapshotsWriteNothing() {
        Store.readOnly = true
        RunLog.append(run(1), to: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
