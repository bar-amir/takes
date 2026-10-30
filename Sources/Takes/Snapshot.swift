import AppKit
import SwiftUI

/// `Takes --snapshot <folder>` renders every screen with sample data to PNGs, for checking the UI
/// without driving another app.
@MainActor
enum Snapshot {
    static func run(arguments: [String]) {
        let folder = arguments.firstIndex(of: "--snapshot").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            ?? FileManager.default.temporaryDirectory.path
        let url = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        let draft = "ya thursday works but i need the specs by wed eod otherwise qa slips again, also can someone own the release notes this time"
        let takes = [
            "Thursday works for me. One ask: I need the specs by Wednesday EOD, otherwise QA slips again. Also, can someone own the release notes this time?",
            "Sure, Thursday it is. I'll need the specs by Wednesday EOD so QA doesn't slip again. Could someone take the release notes this round?",
            "Thursday's fine as long as specs land by Wed EOD (QA slipped last time without them).",
        ]

        func model() -> PanelModel {
            let model = PanelModel()
            model.reset(focus: FocusSnapshot(app: nil, text: draft, source: .field, caretRect: nil), presetID: Store.shared.presets.first?.id)
            model.previewAppName = "Slack"
            return model
        }

        let compose = model()
        render(PanelRootView(model: compose), size: CGSize(width: 720, height: 400), to: url.appendingPathComponent("1-compose.png"))

        let picker = model()
        picker.openPicker()
        picker.highlighted = 0
        render(PanelRootView(model: picker), size: CGSize(width: 800, height: 560), to: url.appendingPathComponent("2-presets.png"))

        let streaming = model()
        streaming.screen = .takes
        streaming.sourceDraft = draft
        streaming.running = true
        streaming.takes = Array(takes.prefix(2)) + ["Thursday's fine as long as specs land"]
        streaming.changesShown = [1]
        render(PanelRootView(model: streaming), size: CGSize(width: 1060, height: fittedHeight(streaming)), to: url.appendingPathComponent("3-takes-streaming.png"))

        let done = model()
        done.screen = .takes
        done.sourceDraft = draft
        done.takes = takes
        done.changesShown = [1]
        done.timing = "first words 1.3 s · all takes 2.8 s"
        render(PanelRootView(model: done), size: CGSize(width: 1060, height: fittedHeight(done)), to: url.appendingPathComponent("4-takes.png"))

        for tab in SettingsTab.allCases {
            let state = SettingsState()
            state.tab = tab
            state.selectedPresetID = Store.shared.presets.first?.id
            render(SettingsView(state: state), size: CGSize(width: 1200, height: 860), to: url.appendingPathComponent("5-settings-\(tab.rawValue.lowercased()).png"))
        }
        render(SetupView(monitor: SetupMonitor.shared, onDone: {}), size: CGSize(width: 640, height: 820),
               to: url.appendingPathComponent("6-setup.png"))
        print("Wrote snapshots to \(url.path)")
    }

    /// The height the takes screen asks the panel for, as `PanelController` would size it.
    static func fittedHeight(_ model: PanelModel, width: CGFloat = 1060) -> CGFloat {
        var height: CGFloat = 520
        model.onContentHeight = { height = $0 }
        _ = bitmap(of: PanelRootView(model: model), size: CGSize(width: width, height: 520))
        return height.rounded(.up)
    }

    private static func render<V: View>(_ view: V, size: CGSize, to url: URL) {
        try? bitmap(of: view, size: size)?.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// Draws a view offscreen in light mode at `size` points.
    static func bitmap<V: View>(of view: V, size: CGSize) -> NSBitmapImageRep? {
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, .light))
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        // Let SwiftUI lay out and AppKit views draw.
        for _ in 0..<5 { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }
        defer { window.orderOut(nil) }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }
}
