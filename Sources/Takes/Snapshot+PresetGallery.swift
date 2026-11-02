import AppKit
import SwiftUI

/// Preset gallery screens for `--snapshot`, in light and dark.
@MainActor
extension Snapshot {
    static func presetGallery(to url: URL, draft: String) {
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"

            let gallery = PresetGalleryView(highlightedID: PresetGallery.email.id,
                                            checked: [PresetGallery.friendlier.id, PresetGallery.summarize.id])
            render(gallery, size: CGSize(width: 860, height: 580), dark: dark,
                   to: url.appendingPathComponent("7-gallery-\(suffix).png"))

            let picker = PanelModel()
            picker.reset(focus: FocusSnapshot(app: nil, text: draft, source: .field, caretRect: nil), presetID: Store.shared.presets.first?.id)
            picker.previewAppName = "Slack"
            picker.browseRowLimit = .max
            picker.openPicker()
            picker.highlighted = picker.filteredPresets.count
            render(PanelRootView(model: picker), size: CGSize(width: 800, height: 640), dark: dark,
                   to: url.appendingPathComponent("7-picker-browse-\(suffix).png"))

            let state = SettingsState()
            state.selectedPresetID = Store.shared.presets.first?.id
            render(SettingsView(state: state), size: CGSize(width: 1200, height: 860), dark: dark,
                   to: url.appendingPathComponent("7-settings-presets-\(suffix).png"))

            render(GalleryHintBar {}.frame(width: 830), size: CGSize(width: 830, height: 48), dark: dark,
                   to: url.appendingPathComponent("7-new-preset-hint-\(suffix).png"))
        }
    }

    private static func render<V: View>(_ view: V, size: CGSize, dark: Bool, to url: URL) {
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        for _ in 0..<5 { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }
        defer { window.orderOut(nil) }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
