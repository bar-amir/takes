import XCTest
@testable import Takes

final class PresetGalleryTests: XCTestCase {
    func testFreshInstallGetsStarters() {
        let presets = PresetGallery.initialPresets(existingUser: false)
        XCTAssertEqual(presets.map(\.name), PresetGallery.starters.map(\.name))
        XCTAssertEqual(presets.map(\.galleryID), PresetGallery.starters.map(\.id))
        XCTAssertTrue(presets.allSatisfy { !$0.id.hasPrefix("gallery.") }, "Starters are installed as copies")
    }

    /// Someone upgrading without a presets file keeps what they were seeing: no surprise additions.
    func testExistingUserKeepsTheOldDefaults() {
        let presets = PresetGallery.initialPresets(existingUser: true)
        XCTAssertEqual(presets.map(\.id), Store.defaultPresets.map(\.id))
        XCTAssertTrue(presets.allSatisfy { $0.galleryID == nil })
    }

    func testAddingMakesAnIndependentCopy() {
        var presets: [Preset] = []
        let added = PresetGallery.add([PresetGallery.direct], to: &presets)
        XCTAssertEqual(added.count, 1)
        XCTAssertNotEqual(presets[0].id, PresetGallery.direct.id)
        XCTAssertEqual(presets[0].galleryID, PresetGallery.direct.id)
        XCTAssertNil(presets[0].hotKey)

        presets[0].instruction = "Edited"
        presets[0].dos.append("Mine")
        XCTAssertNotEqual(PresetGallery.direct.instruction, "Edited", "Editing the copy leaves the template alone")
        XCTAssertFalse(PresetGallery.direct.dos.contains("Mine"))
        XCTAssertTrue(PresetGallery.isAdded(PresetGallery.direct, in: presets), "Still added after renaming fields")
    }

    func testNoDuplicates() {
        var presets: [Preset] = []
        PresetGallery.add([PresetGallery.shorter, PresetGallery.decline], to: &presets)
        let again = PresetGallery.add([PresetGallery.shorter, PresetGallery.decline, PresetGallery.email], to: &presets)
        XCTAssertEqual(again.map(\.name), ["Polish email"])
        XCTAssertEqual(presets.count, 3)
        XCTAssertEqual(Set(presets.map(\.id)).count, 3)
    }

    /// A preset with the same name from an older version counts as added.
    func testSameNameCountsAsAdded() {
        var presets = Store.defaultPresets
        XCTAssertTrue(PresetGallery.isAdded(PresetGallery.shorter, in: presets))
        XCTAssertTrue(PresetGallery.add([PresetGallery.shorter], to: &presets).isEmpty)
    }

    func testTwoCopiesNeverShareAnID() {
        XCTAssertNotEqual(PresetGallery.copy(of: PresetGallery.slack).id, PresetGallery.copy(of: PresetGallery.slack).id)
    }

    func testAllGalleryPresetsAreValid() {
        let all = PresetGallery.all
        XCTAssertTrue((8...12).contains(all.count))
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "Unique ids")
        XCTAssertEqual(Set(all.map { $0.name.lowercased() }).count, all.count, "Unique names")
        for preset in all {
            XCTAssertTrue(preset.id.hasPrefix("gallery.") || preset.id.hasPrefix("builtin."), preset.name)
            XCTAssertFalse(preset.name.isEmpty)
            XCTAssertGreaterThan(preset.instruction.count, 40, preset.name)
            XCTAssertFalse(preset.dos.isEmpty, preset.name)
            XCTAssertFalse(preset.avoid.isEmpty, preset.name)
            XCTAssertTrue(Preset.colors.contains(preset.colorHex), preset.name)
            XCTAssertTrue((1...5).contains(preset.takes), preset.name)
            XCTAssertTrue(Models.all.contains { $0.id == preset.model }, preset.name)
            XCTAssertTrue(Models.efforts.contains(preset.effort), preset.name)
            XCTAssertNil(preset.hotKey, preset.name)
            XCTAssertNil(preset.galleryID, preset.name)
            XCTAssertFalse(PresetGallery.blurb(for: preset).isEmpty, preset.name)
            XCTAssertFalse((preset.instruction + preset.dos.joined() + preset.avoid.joined()).contains("—"), "No em dashes: \(preset.name)")
        }
        let starterIDs = Set(PresetGallery.starters.map(\.id))
        XCTAssertTrue(starterIDs.isSubset(of: Set(all.map(\.id))))
    }

    func testUntouchedNewPreset() {
        let blank = Preset(name: "New preset", colorHex: "#2F55E0", instruction: "Rewrite my draft so it is clear and natural.")
        var preset = blank
        preset.id = "other"
        XCTAssertTrue(PresetGallery.isUntouchedNew(preset, blank: blank))
        preset.dos = ["Be brief"]
        XCTAssertFalse(PresetGallery.isUntouchedNew(preset, blank: blank))
    }

    /// Presets saved before `galleryID` existed still load.
    func testOldPresetsDecode() throws {
        let old = ##"[{"id":"a","name":"Mine","colorHex":"#2F55E0","instruction":"Do it","dos":[],"avoid":[],"examples":[],"language":"sameAsDraft","length":"any","apps":[],"takes":2,"model":"claude-sonnet-5-5","effort":"low"}]"##
        let presets = try JSONDecoder().decode([Preset].self, from: Data(old.utf8))
        XCTAssertEqual(presets.first?.name, "Mine")
        XCTAssertNil(presets.first?.galleryID)
        let copy = PresetGallery.copy(of: PresetGallery.email)
        let decoded = try JSONDecoder().decode(Preset.self, from: JSONEncoder().encode(copy))
        XCTAssertEqual(decoded.galleryID, PresetGallery.email.id)
    }

    @MainActor
    func testPickerBrowseRow() {
        let model = PanelModel()
        model.browseRowLimit = .max
        model.filter = ""
        XCTAssertTrue(model.showsBrowseRow)
        model.highlighted = model.filteredPresets.count
        XCTAssertTrue(model.browseRowHighlighted)
        XCTAssertNil(model.highlightedPreset)
        var opened = false
        model.onOpenGallery = { opened = true }
        model.chooseHighlighted()
        XCTAssertTrue(opened)

        model.browseRowLimit = 0
        model.highlighted = 0
        XCTAssertFalse(model.showsBrowseRow, "Hidden once the user has plenty of presets")
        model.filter = "zzz no preset matches this"
        XCTAssertTrue(model.showsBrowseRow, "Offered when the filter matches nothing")
        model.moveHighlight(1)
        XCTAssertTrue(model.browseRowHighlighted)
    }
}
