import XCTest

@testable import Takes

/// A file Takes can't read is copied aside before anything can overwrite it, and what can be read is kept.
/// Every test works in its own temporary folder, never in ~/Library/Application Support/Takes.
final class StoredFilesTests: XCTestCase {
    private var folder: URL!
    private var wasReadOnly = false

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("takes-stored-files-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        wasReadOnly = Store.readOnly
        Store.readOnly = false
    }

    override func tearDownWithError() throws {
        Store.readOnly = wasReadOnly
        // A test may leave a file unreadable on purpose.
        for url in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        }
        try? FileManager.default.removeItem(at: folder)
    }

    private func file(_ name: String) -> URL { folder.appendingPathComponent(name) }

    private func write(_ text: String, _ name: String) throws -> Data {
        let data = Data(text.utf8)
        try data.write(to: file(name))
        return data
    }

    private func copies(_ name: String) -> [URL] { SetAside.copies(of: name, in: folder) }

    private func now() -> String { ISO8601DateFormatter().string(from: Date()) }

    private func presetJSON(_ name: String) throws -> String {
        let data = try JSONEncoder().encode(Preset(name: name, colorHex: "#2F55E0", instruction: "Rewrite it."))
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Settings

    func testUnreadableSettingsAreKeptBeforeTheNextSaveOverwritesThem() throws {
        let original = try write(#"{"engine":"apiKey","defaultTakes":5,"#, "settings.json")  // cut off mid-write
        let store = Store(folder: folder)
        XCTAssertEqual(store.settings.defaultTakes, AppSettings().defaultTakes, "defaults load")

        let copy = try XCTUnwrap(copies("settings.json").first)
        XCTAssertEqual(try Data(contentsOf: copy), original)
        XCTAssertTrue(copy.lastPathComponent.hasPrefix("settings.unreadable-"))
        XCTAssertEqual(store.setAside.map(\.name), ["settings.json"])
        XCTAssertNil(store.setAside.first?.skipped, "nothing in the file could be read")
        XCTAssertEqual(try Data(contentsOf: file("settings.json")), original, "loading alone changes nothing")

        store.settings.defaultTakes = 4
        XCTAssertNotEqual(try Data(contentsOf: file("settings.json")), original, "the next save writes the new settings")
        XCTAssertEqual(try Data(contentsOf: copy), original, "and the copy still has the original")
    }

    func testOneBadValueKeepsTheRestOfTheSettings() throws {
        let original = try write(
            """
            {"engine":"apiKey","defaultTakes":"five","privacyAccepted":true,"keepHistory":false,
             "voiceRules":[{"id":"a","text":"Be brief","enabled":true},{"id":"b","text":5,"enabled":true},{"id":"c","text":"No filler","enabled":false}]}
            """, "settings.json")
        let store = Store(folder: folder)
        XCTAssertEqual(store.settings.engine, .apiKey)
        XCTAssertTrue(store.settings.privacyAccepted)
        XCTAssertFalse(store.settings.keepHistory)
        XCTAssertEqual(store.settings.defaultTakes, AppSettings().defaultTakes, "the bad value gets its default")
        XCTAssertEqual(store.settings.voiceRules.map(\.text), ["Be brief", "No filler"], "and so does the one bad rule")

        let copy = try XCTUnwrap(copies("settings.json").first, "what the next save would drop is kept")
        XCTAssertEqual(try Data(contentsOf: copy), original)
        XCTAssertEqual(store.setAside.first?.skipped, 2)
    }

    func testSettingsFromAnOlderVersionNeedNoCopy() throws {
        _ = try write(#"{"engine":"apiKey","defaultTakes":5}"#, "settings.json")
        let store = Store(folder: folder)
        XCTAssertEqual(store.settings.defaultTakes, 5)
        XCTAssertTrue(copies("settings.json").isEmpty, "missing keys are an upgrade, not damage")
        XCTAssertTrue(store.setAside.isEmpty)
    }

    func testAnEmptyFileIsNotDamage() throws {
        _ = try write("  \n", "settings.json")
        _ = try write("", "history.json")
        let store = Store(folder: folder)
        XCTAssertTrue(store.setAside.isEmpty)
        XCTAssertTrue(copies("settings.json").isEmpty)
        XCTAssertTrue(copies("history.json").isEmpty)
    }

    // MARK: Presets

    func testPresetsThatCanBeReadAreKept() throws {
        let text = "[\(try presetJSON("First")), 5, {\"name\": \"No instruction\"}, \(try presetJSON("Second"))]"
        let original = try write(text, "presets.json")
        let store = Store(folder: folder)
        XCTAssertEqual(store.presets.map(\.name), ["First", "Second"])
        XCTAssertEqual(store.setAside.first?.skipped, 2)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(copies("presets.json").first)), original)
    }

    func testUnreadablePresetsAreKeptAndTheStartersLoad() throws {
        let original = try write("[5, 6]", "presets.json")
        let store = Store(folder: folder)
        XCTAssertFalse(store.presets.isEmpty, "the app never starts without presets")
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(copies("presets.json").first)), original)
        XCTAssertEqual(try Data(contentsOf: file("presets.json")), original, "nothing writes over it at launch")

        store.presets.append(store.newPreset())
        XCTAssertNotEqual(try Data(contentsOf: file("presets.json")), original)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(copies("presets.json").first)), original)
    }

    func testOneBadFieldInAPresetKeepsThePreset() throws {
        let text = #"[{"name":"Mine","instruction":"Do it.","takes":"lots","dos":["Be kind",7],"model":"claude-opus-5-5"}]"#
        _ = try write(text, "presets.json")
        let store = Store(folder: folder)
        let preset = try XCTUnwrap(store.presets.first)
        XCTAssertEqual(store.presets.count, 1)
        XCTAssertEqual(preset.name, "Mine")
        XCTAssertEqual(preset.takes, 3, "default")
        XCTAssertEqual(preset.dos, ["Be kind"])
        XCTAssertEqual(preset.model, Models.opus)
        XCTAssertEqual(copies("presets.json").count, 1)
    }

    // MARK: History

    func testHistoryEntriesThatCanBeReadAreKept() throws {
        let good = #"{"id":"1","date":"\#(now())","appName":"Slack","presetName":"A","draft":"hello","takes":["hi"],"pastedIndex":0}"#
        let oddIndex = #"{"id":"2","date":"\#(now())","appName":"Mail","presetName":"B","draft":"bye","takes":["see you"],"pastedIndex":"zero"}"#
        let noDraft = #"{"id":"3","date":"\#(now())","appName":"Mail","presetName":"B","takes":["x"]}"#
        let original = try write("[\(good),\(oddIndex),\(noDraft)]", "history.json")
        let store = Store(folder: folder)
        XCTAssertEqual(store.history.map(\.draft), ["hello", "bye"])
        XCTAssertEqual(store.history.map(\.pastedIndex), [0, nil])
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(copies("history.json").first)), original)
        XCTAssertEqual(store.setAside.first?.skipped, 2)
    }

    func testUnreadableHistoryIsKeptAndStartsEmpty() throws {
        let original = try write("{not json", "history.json")
        let store = Store(folder: folder)
        XCTAssertTrue(store.history.isEmpty)
        let copy = try XCTUnwrap(copies("history.json").first)
        XCTAssertEqual(try Data(contentsOf: copy), original)

        store.record(HistoryEntry(appName: "Slack", presetName: "A", draft: "new", takes: ["n"]))
        XCTAssertEqual(try Data(contentsOf: copy), original, "a new run doesn't touch the copy")
    }

    // MARK: The copies

    func testAFileThatStaysUnreadableIsCopiedOnce() throws {
        _ = try write("garbage", "settings.json")
        let first = Store(folder: folder).setAside.first?.copy
        let second = Store(folder: folder).setAside.first?.copy
        XCTAssertNotNil(first)
        XCTAssertEqual(first, second)
        XCTAssertEqual(copies("settings.json").count, 1)
    }

    func testACopyIsNeverOverwritten() throws {
        let moment = Date()
        let a = try XCTUnwrap(SetAside.keep(Data("first".utf8), name: "presets.json", in: folder, now: moment))
        let b = try XCTUnwrap(SetAside.keep(Data("second".utf8), name: "presets.json", in: folder, now: moment))
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(try String(contentsOf: file(a), encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: file(b), encoding: .utf8), "second")
    }

    func testOnlyTheNewestFewCopiesAreKept() throws {
        let start = Date()
        for i in 0..<5 {
            _ = SetAside.keep(Data("version \(i)".utf8), name: "presets.json", in: folder, now: start.addingTimeInterval(Double(i)))
        }
        let kept = copies("presets.json").map { try? String(contentsOf: $0, encoding: .utf8) }
        XCTAssertEqual(kept, ["version 4", "version 3", "version 2"])
    }

    func testCopiesOfTextFilesExpireAfterThirtyDays() throws {
        let old = file("history.unreadable-20200101-000000.json")
        try Data("drafts".utf8).write(to: old)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-31 * 24 * 3600)], ofItemAtPath: old.path)
        let oldPresets = file("presets.unreadable-20200101-000000.json")
        try Data("presets".utf8).write(to: oldPresets)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-31 * 24 * 3600)], ofItemAtPath: oldPresets.path)

        _ = Store(folder: folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path), "history holds the user's text, which is kept 30 days")
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldPresets.path), "presets copies aren't time limited")
    }

    // MARK: When it can't be copied

    func testAFileThatCantBeOpenedIsNeverWrittenOver() throws {
        let original = try write(#"{"defaultTakes":4}"#, "settings.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file("settings.json").path)
        let store = Store(folder: folder)
        XCTAssertEqual(store.setAside.map(\.name), ["settings.json"])
        XCTAssertNil(store.setAside.first?.copy, "there is no copy to point to")

        store.settings.defaultTakes = 2
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file("settings.json").path)
        XCTAssertEqual(try Data(contentsOf: file("settings.json")), original)
    }

    func testSnapshotsWriteNothing() throws {
        let original = try write("garbage", "settings.json")
        Store.readOnly = true
        let store = Store(folder: folder)
        store.settings.defaultTakes = 4
        XCTAssertTrue(copies("settings.json").isEmpty)
        XCTAssertTrue(store.setAside.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file("settings.json")), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file("presets.json").path))
    }

    // MARK: Clear History

    func testClearHistoryRemovesEveryStoredCopy() throws {
        let entry = #"{"id":"1","date":"\#(now())","appName":"Slack","presetName":"A","draft":"secret draft","takes":["secret take"]}"#
        _ = try write("[\(entry), 5]", "history.json")  // one entry can't be read, so a copy is kept
        let store = Store(folder: folder)
        store.settings.keepHistory = true
        XCTAssertEqual(store.history.count, 1)
        XCTAssertEqual(copies("history.json").count, 1)
        XCTAssertTrue(store.keepsHistoryCopy)

        XCTAssertTrue(store.clearHistory())
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file("history.json").path))
        XCTAssertTrue(copies("history.json").isEmpty, "the set-aside copy holds the same drafts")
        XCTAssertFalse(store.keepsHistoryCopy)
        XCTAssertTrue(store.setAside.isEmpty, "its notice goes with it")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file("settings.json").path), "other files stay")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file("presets.json").path))

        store.record(HistoryEntry(appName: "Slack", presetName: "A", draft: "later", takes: ["l"]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file("history.json").path), "history starts again")
    }
}
