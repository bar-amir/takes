import AppKit
import SwiftUI

/// Instant mode's screens for `--snapshot`: each toast state and the preset editor section, light and dark.
extension Snapshot {
    static func instantMode(to folder: URL) {
        let hotKey = "⌃⌥2"
        let toasts: [(String, InstantToast.State)] = [
            ("writing", .writing(preset: "Proofread only, keep my words")),
            ("pasted", .pasted(clipboardBack: true, hotKey: hotKey)),
            ("unchanged", .unchanged(hotKey: hotKey)),
            ("failed-engine", .failed(message: InstantMode.Failure.engine("Claude Code: You've hit your usage limit. It resets at 4 pm.").message(app: "Slack"), hotKey: hotKey)),
            ("failed-left", .failed(message: InstantMode.Failure.leftField(take: "").message(app: "Slack"), hotKey: hotKey)),
            ("cancelled", .cancelled),
        ]
        var preset = Store.defaultPresets[1]
        preset.hotKey = KeyCombo(keyCode: 19, modifiers: 0, display: hotKey)
        preset.writesInstantly = true
        var noHotKey = preset
        noHotKey.hotKey = nil
        noHotKey.writesInstantly = false

        // "Open in Takes" after a paste: the takes screen with the one take, set up as `InstantModeController` does.
        let draft = "ya thursday works but i need the specs by wed eod otherwise qa slips again"
        let opened = PanelModel()
        opened.reset(focus: FocusSnapshot(app: nil, text: draft, source: .field, caretRect: nil), presetID: Store.shared.presets.first?.id)
        opened.previewAppName = "Slack"
        opened.sourceDraft = draft
        opened.takes = ["Thursday works for me. I need the specs by Wednesday EOD, otherwise QA slips again."]
        opened.screen = .takes
        let openedHeight = fittedHeight(opened, width: 720)

        for (scheme, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            write(PanelRootView(model: opened), size: CGSize(width: 720, height: openedHeight), appearance: scheme,
                  to: folder.appendingPathComponent("7-instant-open-in-takes-\(name).png"))
            for (index, (label, state)) in toasts.enumerated() {
                let view = InstantToast(state: state).padding(24).frame(width: 760, height: 120).background(Theme.surface)
                write(view, size: CGSize(width: 760, height: 120), appearance: scheme,
                      to: folder.appendingPathComponent("7-instant-toast-\(index + 1)-\(label)-\(name).png"))
            }
            for (label, value) in [("on", preset), ("needs-hotkey", noHotKey)] {
                let view = InstantModeSection(preset: .constant(value)).padding(28).frame(width: 600).background(Theme.surface)
                write(view, size: CGSize(width: 600, height: label == "on" ? 150 : 190), appearance: scheme,
                      to: folder.appendingPathComponent("7-instant-editor-\(label)-\(name).png"))
            }
        }
    }

    /// Like `bitmap`, with a chosen appearance: Theme's colors follow the view's appearance, not SwiftUI's scheme.
    private static func write<V: View>(_ view: V, size: CGSize, appearance: NSAppearance.Name, to url: URL) {
        let dark = appearance == .darkAqua
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        hosting.appearance = NSAppearance(named: appearance)
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
