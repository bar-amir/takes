import XCTest
@testable import Takes

/// The preset gallery's button named a checked preset while another row's preview was on screen. It now names a
/// preset only when it's the highlighted one.
final class PresetGalleryButtonTests: XCTestCase {
    private let templates = [
        Preset(name: "Polish email", colorHex: "#000000", instruction: "a"),
        Preset(name: "Summarize", colorHex: "#000000", instruction: "b"),
        Preset(name: "Shorter", colorHex: "#000000", instruction: "c"),
    ]

    func testTheButtonNamesOnlyTheHighlightedPreset() {
        let (email, summarize, shorter) = (templates[0], templates[1], templates[2])
        // The highlighted row is already added; one checked further down.
        let items = PresetGallery.toAdd(templates, checked: [summarize.id], highlightedID: email.id) { $0.id == email.id }
        XCTAssertEqual(items.map(\.name), ["Summarize"])
        XCTAssertEqual(PresetGallery.addTitle(items, highlightedID: email.id), "Add 1 checked preset",
                       "Not “Summarize” while Polish email's preview is on screen")
        XCTAssertEqual(PresetGallery.addTitle(items, highlightedID: summarize.id), "Add “Summarize”")

        let none = PresetGallery.toAdd(templates, checked: [], highlightedID: shorter.id) { _ in false }
        XCTAssertEqual(PresetGallery.addTitle(none, highlightedID: shorter.id), "Add “Shorter”")
        let two = PresetGallery.toAdd(templates, checked: [summarize.id, shorter.id], highlightedID: email.id) { _ in false }
        XCTAssertEqual(PresetGallery.addTitle(two, highlightedID: email.id), "Add 2 presets")
        let added = PresetGallery.toAdd(templates, checked: [], highlightedID: email.id) { _ in true }
        XCTAssertEqual(PresetGallery.addTitle(added, highlightedID: email.id), "Added")
    }
}
