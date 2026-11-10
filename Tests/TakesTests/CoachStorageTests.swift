import XCTest

@testable import Takes

/// coach.json keeps a short phrase around each mistake, never a whole draft, and a file that can't be read is kept.
/// Every test works in its own temporary folder, never in ~/Library/Application Support/Takes.
@MainActor
final class CoachStorageTests: XCTestCase {
    private var folder: URL!
    private var wasReadOnly = false
    private var reported: [SetAsideFile] = []

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("takes-coach-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        wasReadOnly = Store.readOnly
        Store.readOnly = false
        reported = []
    }

    override func tearDownWithError() throws {
        Store.readOnly = wasReadOnly
        try? FileManager.default.removeItem(at: folder)
    }

    private var coachFile: URL { folder.appendingPathComponent("coach.json") }

    private func store() -> CoachStore {
        CoachStore(folder: folder, enabled: { true }, onSetAside: { [unowned self] in reported.append($0) })
    }

    private func finding(wrong: String, right: String = "if you send", why: String = "present after if") -> CoachCheck.Finding {
        CoachCheck.Finding(pattern: "conditionals", wrong: wrong, right: right, why: why)
    }

    private let draft = String(repeating: "If you will send me the link today, I will review it. ", count: 12)

    private func saved() throws -> CoachData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CoachData.self, from: Data(contentsOf: coachFile))
    }

    // MARK: A phrase, not a draft

    func testAWholeDraftIsCutToAShortExcerptWhenKept() throws {
        let store = store()
        store.record(
            .init(findings: [finding(wrong: draft, right: draft, why: draft)], tips: [.init(goal: "Less formal", wrong: draft, better: draft)]),
            words: 120, app: "Mail")
        let kept = try XCTUnwrap(store.data.sightings.first?.finding)
        XCTAssertLessThanOrEqual(kept.wrong.count, CoachStore.maxPhrase)
        XCTAssertLessThanOrEqual(kept.right.count, CoachStore.maxPhrase)
        XCTAssertLessThanOrEqual(kept.why.count, CoachStore.maxReason)
        XCTAssertTrue(kept.wrong.hasSuffix("…"))
        XCTAssertTrue(kept.wrong.hasPrefix("If you will send me the link today"))
        let tip = try XCTUnwrap(store.data.tips.first?.tip)
        XCTAssertLessThanOrEqual(tip.wrong.count, CoachStore.maxPhrase)
        XCTAssertLessThanOrEqual(tip.better.count, CoachStore.maxPhrase)

        let onDisk = try String(contentsOf: coachFile, encoding: .utf8)
        XCTAssertFalse(onDisk.contains(draft.prefix(300)), "no long stretch of the draft reaches the file")
    }

    func testAShortPhraseIsKeptAsItIs() {
        let store = store()
        store.record(.init(findings: [finding(wrong: "if you will send")]), words: 10, app: "Slack")
        XCTAssertEqual(store.data.sightings.first?.finding.wrong, "if you will send")
        XCTAssertEqual(CoachStore.excerpt("short", limit: 100), "short")
    }

    func testExcerptsEndAtAWord() {
        let text = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda"
        let cut = CoachStore.excerpt(text, limit: 30)
        XCTAssertLessThanOrEqual(cut.count, 30)
        XCTAssertTrue(cut.hasSuffix("…"))
        XCTAssertFalse(cut.dropLast().hasSuffix(" "))
        XCTAssertTrue(text.hasPrefix(cut.dropLast()))
        XCTAssertTrue(text.hasPrefix(String(cut.dropLast()) + " "), "cut between words")
        // One long word with no break still ends up short.
        XCTAssertEqual(CoachStore.excerpt(String(repeating: "a", count: 500), limit: 20).count, 20)
    }

    func testOversizedEntriesAlreadyOnDiskAreTrimmedWhenTheyLoad() throws {
        var data = CoachData()
        data.sightings = [
            CoachSighting(finding: finding(wrong: draft, right: draft, why: draft), app: "Mail"),
            CoachSighting(finding: finding(wrong: "did a mistake"), app: "Slack"),
        ]
        data.tips = [CoachTipRecord(tip: .init(goal: "Less formal", wrong: draft, better: draft))]
        data.ignored = [CoachCheck.normalized(draft), "kept phrase"]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(data).write(to: coachFile)

        let store = store()
        let phrases = store.data.sightings.map(\.finding.wrong) + store.data.tips.map(\.tip.wrong) + store.data.tips.map(\.tip.better)
        XCTAssertTrue(phrases.allSatisfy { $0.count <= CoachStore.maxPhrase }, "\(phrases)")
        XCTAssertLessThanOrEqual(store.data.sightings[0].finding.why.count, CoachStore.maxReason)
        XCTAssertEqual(store.data.sightings[1].finding.wrong, "did a mistake", "short entries stay")
        XCTAssertTrue(store.data.ignored.allSatisfy { $0.count <= CoachStore.maxPhrase })
        XCTAssertTrue(store.data.ignored.contains("kept phrase"))

        let onDisk = try saved()
        XCTAssertTrue(onDisk.sightings.allSatisfy { $0.finding.wrong.count <= CoachStore.maxPhrase && $0.finding.right.count <= CoachStore.maxPhrase })
        XCTAssertFalse(try String(contentsOf: coachFile, encoding: .utf8).contains(draft.prefix(300)), "the file itself is rewritten shorter")
        XCTAssertTrue(reported.isEmpty, "it was readable, so nothing is set aside")
    }

    func testNotAMistakeStillWorksForALongPhrase() {
        let store = store()
        let long = finding(wrong: draft)
        store.record(.init(findings: [long]), words: 50, app: "Mail")
        XCTAssertEqual(store.data.sightings.count, 1)
        store.ignore(long)
        XCTAssertTrue(store.data.sightings.isEmpty, "the kept excerpt is matched the same way")
        XCTAssertTrue(store.withoutIgnored(.init(findings: [long])).findings.isEmpty)
        XCTAssertLessThanOrEqual(store.data.ignored.first?.count ?? 0, CoachStore.maxPhrase)
    }

    // MARK: A file that can't be read

    func testUnreadableCoachDataIsKeptAndTheCoachStartsOver() throws {
        let original = Data(#"{"sightings":[{"id":"1""#.utf8)
        try original.write(to: coachFile)
        let store = store()
        XCTAssertTrue(store.data.sightings.isEmpty)
        XCTAssertEqual(reported.map(\.name), ["coach.json"])
        let copy = try XCTUnwrap(SetAside.copies(of: "coach.json", in: folder).first)
        XCTAssertEqual(try Data(contentsOf: copy), original)

        store.record(.init(findings: [finding(wrong: "if you will send")]), words: 10, app: "Slack")
        XCTAssertEqual(try Data(contentsOf: copy), original, "saving doesn't touch the copy")
        XCTAssertEqual(try saved().sightings.count, 1)
    }

    func testOneBadEntryDoesntCostTheRest() throws {
        let good =
            #"{"id":"1","date":"\#(ISO8601DateFormatter().string(from: Date()))","app":"Slack","finding":{"pattern":"conditionals","wrong":"if you will send","right":"if you send","why":"present"}}"#
        let original = Data(#"{"sightings":[\#(good),{"id":2}],"muted":["articles"],"tokens":{"2026-11":120}}"#.utf8)
        try original.write(to: coachFile)
        let store = store()
        XCTAssertEqual(store.data.sightings.count, 1)
        XCTAssertEqual(store.data.muted, ["articles"])
        XCTAssertEqual(store.data.tokens["2026-11"], 120)
        let copy = try XCTUnwrap(SetAside.copies(of: "coach.json", in: folder).first)
        XCTAssertEqual(try Data(contentsOf: copy), original)
    }

    func testTurningTheCoachOffDeletesTheCopiesToo() throws {
        try Data("garbage".utf8).write(to: coachFile)
        let store = store()
        store.record(.init(findings: [finding(wrong: "if you will send")]), words: 10, app: "Slack")
        XCTAssertEqual(SetAside.copies(of: "coach.json", in: folder).count, 1)
        store.deleteAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: coachFile.path))
        XCTAssertTrue(SetAside.copies(of: "coach.json", in: folder).isEmpty, "a copy holds the same phrases")
    }

    func testDataGivenToTheStoreStaysInMemory() {
        let store = CoachStore(data: CoachData(), folder: folder, enabled: { true })
        store.record(.init(findings: [finding(wrong: "if you will send")]), words: 10, app: "Slack")
        XCTAssertFalse(FileManager.default.fileExists(atPath: coachFile.path))
    }

    func testOneBadValueInAMapDoesntCostTheMap() throws {
        let original = Data(
            #"{"tokens":{"2026-10":100,"2026-11":"lots"},"checks":{"2026-11":3},"lessonsRead":{"articles":"2026-11-01T10:00:00Z","bad":5}}"#.utf8)
        try original.write(to: coachFile)
        let store = store()
        XCTAssertEqual(store.data.tokens, ["2026-10": 100])
        XCTAssertEqual(store.data.checks, ["2026-11": 3])
        XCTAssertEqual(Array(store.data.lessonsRead.keys), ["articles"])
        let copy = try XCTUnwrap(SetAside.copies(of: "coach.json", in: folder).first, "what was dropped is kept")
        XCTAssertEqual(try Data(contentsOf: copy), original)
    }

    func testTheCoachFileDoesntReadWhenSnapshotting() throws {
        try Data(#"{"muted":["articles"]}"#.utf8).write(to: coachFile)
        Store.readOnly = true
        let store = CoachStore(folder: folder, enabled: { true })
        XCTAssertTrue(store.data.muted.isEmpty)
    }
}
