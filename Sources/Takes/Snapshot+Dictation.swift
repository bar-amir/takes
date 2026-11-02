import AppKit
import SwiftUI

/// Dictation states of the compose screen, light and dark (`--snapshot`).
extension Snapshot {
    static func dictation(to folder: URL) {
        let draft = "ya thursday works but i need the specs by wed eod"
        let spoken = "Also, can someone own the release notes this time"

        func model(_ state: Dictation.State, level: Float = 0, text: String = draft) -> PanelModel {
            let model = PanelModel()
            model.reset(focus: FocusSnapshot(app: nil, text: text, source: .field, caretRect: nil), presetID: Store.shared.presets.first?.id)
            model.previewAppName = "Slack"
            model.dictation.preview(state, level: level)
            return model
        }

        let recording = model(.recording, level: 0.7)
        recording.insertDictated(spoken)
        let screens: [(String, PanelModel)] = [
            ("idle", model(.idle)),
            ("explain", model(.asking(explained: false))),
            ("recording", recording),
            ("denied", model(.denied(.microphone))),
            ("unavailable", model(.unavailable(.language("Hebrew (Israel)")))),
        ]
        for (name, model) in screens {
            for dark in [false, true] {
                let url = folder.appendingPathComponent("7-dictation-\(name)-\(dark ? "dark" : "light").png")
                try? themedBitmap(of: PanelRootView(model: model), size: CGSize(width: 720, height: 400), dark: dark)?
                    .representation(using: .png, properties: [:])?.write(to: url)
            }
        }
        for dark in [false, true] {
            let settings = VStack(alignment: .leading, spacing: 14) { SectionTitle("Dictation"); DictationSettings() }
                .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Theme.sidebar)
            try? themedBitmap(of: settings, size: CGSize(width: 600, height: 180), dark: dark)?
                .representation(using: .png, properties: [:])?
                .write(to: folder.appendingPathComponent("7-dictation-settings-\(dark ? "dark" : "light").png"))
        }
    }

    /// Like `bitmap`, but in the given appearance, so `Theme`'s dynamic colors resolve to it.
    static func themedBitmap<V: View>(of view: V, size: CGSize, dark: Bool) -> NSBitmapImageRep? {
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        for _ in 0..<5 { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }
        defer { window.orderOut(nil) }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }
}
