import XCTest

@testable import Takes

/// A preset file comes from outside, so what it asks for is checked before it joins the user's presets.
final class PresetImportTests: XCTestCase {
    private func preset(_ change: (inout Preset) -> Void = { _ in }) -> Preset {
        var preset = Preset(name: "Imported", colorHex: "#2F55E0", instruction: "Rewrite it.")
        change(&preset)
        return preset
    }

    private func checked(_ preset: Preset) -> (preset: Preset, notes: [String], removedBindings: Bool) {
        PresetImport.checked(preset, defaultModel: Models.sonnet, defaultEffort: "low")
    }

    func testAnOrdinaryPresetComesInUnchanged() {
        let original = preset {
            $0.takes = 4; $0.model = Models.opus; $0.effort = "high"; $0.examples = ["one", "two"]
        }
        let result = checked(original)
        XCTAssertTrue(result.notes.isEmpty)
        XCTAssertFalse(result.removedBindings)
        XCTAssertNotEqual(result.preset.id, original.id, "it gets an id of its own")
        var same = result.preset
        same.id = original.id
        XCTAssertEqual(same, original)
    }

    func testTakesStayInsideWhatThePickerOffers() {
        XCTAssertEqual(checked(preset { $0.takes = 50 }).preset.takes, 5)
        XCTAssertEqual(checked(preset { $0.takes = 0 }).preset.takes, 1)
        XCTAssertEqual(checked(preset { $0.takes = -3 }).preset.takes, 1)
        XCTAssertEqual(checked(preset { $0.takes = 2 }).preset.takes, 2)
        XCTAssertEqual(checked(preset { $0.takes = 50 }).notes, ["takes set to 5 (was 50)"])
    }

    func testAnUnknownModelOrEffortGetsTheDefault() {
        let result = checked(
            preset {
                $0.model = "gpt-9"; $0.effort = "max"
            })
        XCTAssertEqual(result.preset.model, Models.sonnet)
        XCTAssertEqual(result.preset.effort, "low")
        XCTAssertEqual(result.notes.count, 2)

        let own = PresetImport.checked(
            preset {
                $0.model = "gpt-9"; $0.effort = "max"
            }, defaultModel: Models.haiku, defaultEffort: "high")
        XCTAssertEqual(own.preset.model, Models.haiku, "the user's own defaults, when they are valid")
        XCTAssertEqual(own.preset.effort, "high")

        let broken = PresetImport.checked(preset { $0.model = "x" }, defaultModel: "also unknown", defaultEffort: "nope")
        XCTAssertEqual(broken.preset.model, Models.sonnet, "never a default this version doesn't have")
    }

    func testExamplesAreFewAndShort() {
        let long = String(repeating: "word ", count: 2000)
        let result = checked(preset { $0.examples = (1...9).map { "example \($0)" } + [long] })
        XCTAssertEqual(result.preset.examples.count, Preset.maxExamples)
        XCTAssertEqual(result.preset.examples.first, "example 1")

        let shortened = checked(preset { $0.examples = [long, "short"] })
        XCTAssertEqual(shortened.preset.examples.map(\.count), [PresetImport.maxExampleLength, 5])
        XCTAssertEqual(shortened.notes, ["long examples shortened"])
    }

    func testNothingCanActWithoutTheUserSeeingIt() {
        let combo = KeyCombo(keyCode: 3, modifiers: 0x0A00, display: "⌥⇧F")
        let sneaky = preset {
            $0.hotKey = combo
            $0.apps = [AppRef(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"), AppRef(bundleID: "com.apple.mail", name: "Mail")]
            $0.instantMode = true
        }
        let result = checked(sneaky)
        XCTAssertNil(result.preset.hotKey)
        XCTAssertTrue(result.preset.apps.isEmpty)
        XCTAssertNil(result.preset.instantMode)
        XCTAssertTrue(result.removedBindings)
        XCTAssertEqual(result.notes.count, 3, "each one is reported")
        XCTAssertTrue(result.notes.contains { $0.contains("Slack") && $0.contains("Mail") }, "naming the apps")
        XCTAssertFalse(checked(preset { $0.instantMode = false }).removedBindings)
    }

    // MARK: Reading a file

    func testReadsAListOrOnePreset() throws {
        let list = try JSONEncoder().encode([preset(), preset { $0.name = "Other" }])
        XCTAssertEqual(PresetImport.read(list, defaultModel: Models.sonnet, defaultEffort: "low").presets.map(\.name), ["Imported", "Other"])
        let one = try JSONEncoder().encode(preset())
        XCTAssertEqual(PresetImport.read(one, defaultModel: Models.sonnet, defaultEffort: "low").presets.count, 1)
    }

    func testAPresetThatCantBeReadIsSkippedNotTheFile() throws {
        let text = #"[{"name":"Kept","instruction":"Do it.","takes":50},{"name":"No instruction"},7]"#
        let result = PresetImport.read(Data(text.utf8), defaultModel: Models.sonnet, defaultEffort: "low")
        XCTAssertEqual(result.presets.map(\.name), ["Kept"])
        XCTAssertEqual(result.presets.first?.takes, 5)
        XCTAssertEqual(result.skipped, 2)
        XCTAssertFalse(result.unreadable)
    }

    func testAFileThatIsNotPresetsIsUnreadable() {
        for text in ["", "not json", #"{"hello": 1}"#, "42"] {
            let result = PresetImport.read(Data(text.utf8), defaultModel: Models.sonnet, defaultEffort: "low")
            XCTAssertTrue(result.unreadable, text)
            XCTAssertTrue(result.presets.isEmpty, text)
        }
    }

    func testAHugeFileIsNotRead() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("takes-import-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 0x20, count: PresetImport.maxFileSize + 1).write(to: url)
        XCTAssertTrue(PresetImport.read(url, defaultModel: Models.sonnet, defaultEffort: "low").unreadable)
    }

    // MARK: What the user is told

    func testTheSummarySaysWhatChanged() {
        let text = #"[{"name":"Loud","instruction":"Do it.","takes":50,"model":"gpt-9","hotKey":{"keyCode":3,"modifiers":2560,"display":"⌥⇧F"}}]"#
        let good = PresetImport.read(Data(text.utf8), defaultModel: Models.sonnet, defaultEffort: "low")
        let bad = PresetImport.read(Data("nope".utf8), defaultModel: Models.sonnet, defaultEffort: "low")
        let summary = PresetImport.summary([.init(file: "loud.json", result: good), .init(file: "junk.json", result: bad)])
        XCTAssertEqual(summary.imported, 1)
        XCTAssertEqual(summary.title, "Imported 1 preset")
        XCTAssertTrue(summary.message.contains("“Loud”"))
        XCTAssertTrue(summary.message.contains("takes set to 5 (was 50)"))
        XCTAssertTrue(summary.message.contains("hotkey removed"))
        XCTAssertTrue(summary.message.contains("“junk.json” isn't a preset file Takes can read."))
        XCTAssertTrue(summary.message.contains("Set them in the preset."), "and says how to get the hotkey back")
    }

    func testTheSummaryForACleanImportIsShort() {
        let data = try! JSONEncoder().encode([preset(), preset { $0.name = "B" }])
        let result = PresetImport.read(data, defaultModel: Models.sonnet, defaultEffort: "low")
        let summary = PresetImport.summary([.init(file: "two.json", result: result)])
        XCTAssertEqual(summary.title, "Imported 2 presets")
        XCTAssertEqual(summary.message, "")
    }

    func testTheSummaryCountsWhatCouldntBeRead() {
        let result = PresetImport.read(Data("[1, 2]".utf8), defaultModel: Models.sonnet, defaultEffort: "low")
        let summary = PresetImport.summary([.init(file: "x.json", result: result)])
        XCTAssertEqual(summary.title, "No presets imported")
        XCTAssertTrue(summary.message.contains("2 presets couldn't be read"))
    }

    // MARK: What the limits do

    func testNameInstructionAndRulesAreLimited() {
        let long = String(repeating: "x", count: 500)
        let result = checked(
            preset {
                $0.name = long
                $0.instruction = String(repeating: "word ", count: 2000)
                $0.dos = (1...30).map { "do \($0)" }
                $0.avoid = [long, "short"]
            })
        XCTAssertEqual(result.preset.name.count, PresetImport.maxNameLength)
        XCTAssertEqual(result.preset.instruction.count, PresetImport.maxInstructionLength)
        XCTAssertEqual(result.preset.dos.count, PresetImport.maxRules)
        XCTAssertEqual(result.preset.dos.first, "do 1")
        XCTAssertEqual(result.preset.avoid.map(\.count), [PresetImport.maxRuleLength, 5])
        XCTAssertEqual(
            Set(result.notes),
            ["name shortened", "instruction shortened", "extra Do rules left out", "long Avoid rules shortened"],
            "each one is reported")
    }

    func testAnOrdinaryPresetIsNotLimited() {
        let result = checked(preset { $0.dos = (1...PresetImport.maxRules).map { "do \($0)" } })
        XCTAssertTrue(result.notes.isEmpty)
        XCTAssertEqual(result.preset.dos.count, PresetImport.maxRules)
    }

    func testValuesThatCouldntBeReadAreResetAndReported() throws {
        let text = #"[{"name":"Odd","instruction":"Do it.","takes":"lots","model":5,"examples":[1,"keep me"]},{"name":"Fine","instruction":"Do it."}]"#
        let result = PresetImport.read(Data(text.utf8), defaultModel: Models.sonnet, defaultEffort: "low")
        XCTAssertEqual(result.presets.map(\.name), ["Odd", "Fine"])
        XCTAssertEqual(result.presets[0].takes, 3)
        XCTAssertEqual(result.presets[0].model, Models.sonnet)
        XCTAssertEqual(result.presets[0].examples, ["keep me"])
        XCTAssertEqual(result.changes.map(\.name), ["Odd"], "only the one that had a problem")
        let note = try XCTUnwrap(result.changes.first?.notes.first)
        for key in ["takes", "model", "examples"] { XCTAssertTrue(note.contains(key), note) }
        XCTAssertTrue(PresetImport.summary([.init(file: "odd.json", result: result)]).message.contains("“Odd”: couldn't read"))
    }

    func testASinglePresetReportsWhatWasReset() throws {
        let text = #"{"name":"One","instruction":"Do it.","effort":false}"#
        let result = PresetImport.read(Data(text.utf8), defaultModel: Models.sonnet, defaultEffort: "low")
        XCTAssertEqual(result.presets.count, 1)
        XCTAssertTrue(try XCTUnwrap(result.changes.first?.notes.first).contains("effort"))
    }

    // MARK: The import itself

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("takes-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testAnImportAddsAtMostFiftyPresetsAndSavesOnce() throws {
        let wasReadOnly = Store.readOnly
        Store.readOnly = false
        defer { Store.readOnly = wasReadOnly }
        let store = Store(folder: folder)
        let before = store.presets.count

        var many = (1...60).map { #"{"name":"P\#($0)","instruction":"Do it."}"# }
        many[0] = #"{"name":"P1","instruction":"Do it.","takes":"lots","model":5,"examples":[1,"ok"]}"#
        let manyURL = folder.appendingPathComponent("many.json")
        try Data("[\(many.joined(separator: ","))]".utf8).write(to: manyURL)
        let oneURL = folder.appendingPathComponent("one.json")
        try JSONEncoder().encode(preset { $0.name = "Single" }).write(to: oneURL)
        let junkURL = folder.appendingPathComponent("junk.json")
        try Data("nope".utf8).write(to: junkURL)

        var changes = 0
        let watch = store.objectWillChange.sink { changes += 1 }
        let result = PresetImport.importFiles([manyURL, junkURL, oneURL], into: store)
        watch.cancel()

        XCTAssertEqual(store.presets.count, before + PresetImport.maxPresets + 1)
        XCTAssertEqual(changes, 1, "the presets go in with one assignment, so they are saved once")
        XCTAssertEqual(result.lastID, store.presets.last?.id)
        XCTAssertEqual(store.presets.last?.name, "Single")
        XCTAssertEqual(store.presets[before].name, "P1")
        XCTAssertEqual(store.presets[before].takes, 3, "the value that couldn't be read was reset")
        XCTAssertEqual(Set(store.presets.map(\.id)).count, store.presets.count, "every one has an id of its own")

        let message = result.summary.message
        XCTAssertTrue(message.contains("only the first 50 of 60 presets were imported"), message)
        XCTAssertTrue(message.contains("“junk.json” isn't a preset file Takes can read."), message)
        XCTAssertTrue(message.contains("“P1”: couldn't read"), message)
        XCTAssertEqual(result.summary.imported, PresetImport.maxPresets + 1)

        let saved = try JSONDecoder().decode([Preset].self, from: Data(contentsOf: folder.appendingPathComponent("presets.json")))
        XCTAssertEqual(saved.count, store.presets.count, "and the file has them")
    }

    func testAnImportOfNothingChangesNothing() throws {
        let store = Store(folder: folder)
        let before = store.presets
        let junk = folder.appendingPathComponent("junk.json")
        try Data("nope".utf8).write(to: junk)
        var changes = 0
        let watch = store.objectWillChange.sink { changes += 1 }
        let result = PresetImport.importFiles([junk], into: store)
        watch.cancel()
        XCTAssertEqual(store.presets, before)
        XCTAssertEqual(changes, 0)
        XCTAssertNil(result.lastID)
        XCTAssertEqual(result.summary.title, "No presets imported")
    }
}
