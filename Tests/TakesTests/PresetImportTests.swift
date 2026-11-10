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
}
