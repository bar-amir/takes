import AppKit
import SwiftUI

extension Snapshot {
    /// The preset editor's "How it writes" card, with and without a preset hotkey.
    static func renderPresetOptions(to folder: URL) {
        var withKey = Preset.proofread
        withKey.hotKey = KeyCombo(keyCode: 35, modifiers: 0x1100, display: "⌃⌘P")
        withKey.instantMode = true
        var noKey = PresetGallery.all[1]
        noKey.showTone = true
        for (name, start) in [("hotkey", withKey), ("no-hotkey", noKey)] {
            var preset = start
            let card = PresetOptionsCard(preset: Binding(get: { preset }, set: { preset = $0 }))
                .padding(28).frame(width: 640).frame(maxHeight: .infinity).background(Theme.surface)
            for dark in [false, true] {
                writeOptions(card, size: CGSize(width: 640, height: name == "hotkey" ? 330 : 370), dark: dark,
                      to: folder.appendingPathComponent("options-\(name)-\(dark ? "dark" : "light").png"))
            }
        }
    }

    private static func writeOptions<V: View>(_ view: V, size: CGSize, dark: Bool, to url: URL) {
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
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
