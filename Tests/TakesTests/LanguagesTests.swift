import XCTest
@testable import Takes

final class LanguagesTests: XCTestCase {
    func testLanguagesComeFromTheMacInOrderWithoutDuplicates() {
        XCTAssertEqual(Languages.fromSystem(["he-IL", "en-US", "en-GB", "fr-FR", "es-ES"]), ["he", "en", "fr"])
        XCTAssertEqual(Languages.fromSystem([]), ["en"])
    }

    func testNames() {
        XCTAssertEqual(Languages.englishName("he"), "Hebrew")
        XCTAssertEqual(Languages.nativeName("he"), "עברית")
        XCTAssertEqual(Languages.nativeName("es"), "Español")
    }

    func testOldReplyLanguagesStillDecode() throws {
        let decoded = try JSONDecoder().decode([ReplyLanguage].self, from: Data(#"["sameAsDraft","english","hebrew","es"]"#.utf8))
        XCTAssertEqual(decoded, [.sameAsDraft, .language("en"), .language("he"), .language("es")])
        let encoded = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
        XCTAssertEqual(encoded, #"["sameAsDraft","en","he","es"]"#)
    }

    func testPromptNamesTheLanguageInEnglish() {
        var preset = Preset(name: "T", colorHex: Preset.colors[0], instruction: "Rewrite.")
        preset.language = .language("es")
        XCTAssertTrue(PromptBuilder.system(preset: preset, takes: 1, rules: []).contains("Write in Spanish."))
        preset.language = .sameAsDraft
        XCTAssertTrue(PromptBuilder.system(preset: preset, takes: 1, rules: []).contains("language of the draft"))
    }

    func testOneTranslatePresetPerLanguage() {
        let presets = PresetGallery.translations(for: ["he", "en"])
        XCTAssertEqual(presets.map(\.name), ["Translate to Hebrew", "Translate to English"])
        XCTAssertEqual(presets.map(\.id), ["gallery.translate.he", "gallery.translate"], "English keeps its earlier id")
        XCTAssertEqual(presets[0].language, .language("he"))
        XCTAssertEqual(PresetGallery.blurb(for: PresetGallery.copy(of: presets[0])), "Natural Hebrew from any language.")
    }

    func testOnlyMultilingualPeopleStartWithTranslatePresets() {
        XCTAssertFalse(PresetGallery.starters(languages: ["en"]).contains { $0.name.hasPrefix("Translate") })
        XCTAssertEqual(PresetGallery.starters(languages: ["he", "en"]).filter { $0.name.hasPrefix("Translate") }.count, 2)
    }

    func testSettingsWithoutLanguagesFollowTheMac() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertNil(settings.languages)
        XCTAssertEqual(settings.writingLanguages, Languages.fromSystem())
    }

    @MainActor
    func testOnboardingLanguageChangesPickTranslatePresets() {
        let model = OnboardingModel()
        model.languages = ["en"]
        XCTAssertFalse(model.chosenPresets.contains("Translate to Hebrew"))
        model.languages = ["en", "he"]
        XCTAssertTrue(model.chosenPresets.contains("Translate to Hebrew"))
        XCTAssertTrue(model.chosenPresets.contains("Translate to English"))
        model.languages = ["en"]
        XCTAssertFalse(model.chosenPresets.contains("Translate to Hebrew"))
        XCTAssertFalse(model.chosenPresets.contains("Translate to English"))
        XCTAssertTrue(model.chosenPresets.contains("Proofread"))
    }
}
