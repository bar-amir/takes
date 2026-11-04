import AppKit
import SwiftUI

/// Reply context screens for `--snapshot`, in light and dark.
extension Snapshot {
    static func renderReplyContext(to folder: URL) {
        let draft = "ya thursday works but i need the specs by wed eod otherwise qa slips again"
        let message = "Hey team, can we move the release review to Thursday? Marketing needs Wednesday for the launch prep.\nAlso, who's writing the release notes this time?"

        func model(_ configure: (PanelModel) -> Void) -> PanelModel {
            let model = PanelModel()
            model.reset(focus: FocusSnapshot(app: nil, text: draft, source: .field, caretRect: nil), presetID: Store.shared.presets.first?.id)
            model.previewAppName = "Slack"
            configure(model)
            return model
        }

        let states: [(String, PanelModel)] = [
            ("none", model { _ in }),
            ("chip", model { $0.replyContext = ReplyContext(text: message, source: .clipboard) }),
            ("chip-auto", model { $0.replyContext = ReplyContext(text: message, source: .autoClipboard) }),
            ("expanded", model { $0.replyContext = ReplyContext(text: message, source: .typed); $0.editingContext = true }),
            ("expanded-empty", model { $0.replyContext = ReplyContext(text: "", source: .typed); $0.editingContext = true }),
            ("clipboard-empty", model { $0.contextNotice = "The clipboard has no text. Copy the message first, or press ⌘J to paste it." }),
        ]
        for (dark, suffix) in [(false, "light"), (true, "dark")] {
            for (name, model) in states {
                let size = CGSize(width: 720, height: 400 + ReplyContextBar.extraHeight(model))
                write(PanelRootView(model: model), size: size, dark: dark, to: folder.appendingPathComponent("rc-compose-\(name)-\(suffix).png"))
            }
            let settings = SettingsState()
            settings.tab = .general
            write(SettingsView(state: settings), size: CGSize(width: 780, height: 760), dark: dark,
                  to: folder.appendingPathComponent("rc-settings-general-\(suffix).png"))
        }
    }

    private static func write<V: View>(_ view: V, size: CGSize, dark: Bool, to url: URL) {
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
