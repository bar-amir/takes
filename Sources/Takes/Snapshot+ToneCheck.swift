import AppKit
import SwiftUI

/// Tone screens for `--snapshot`, in light and dark.
@MainActor
extension Snapshot {
    static func renderToneCheck(to folder: URL) {
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

        func takesModel(notes: [String?], loading: Bool = false) -> PanelModel {
            let model = model()
            model.screen = .takes
            model.sourceDraft = draft
            model.takes = takes
            model.timing = "first words 1.3 s · all takes 2.8 s"
            model.takeTones.preview(notes: notes, loading: loading)
            return model
        }

        func composeModel(_ state: ToneReadModel.State) -> PanelModel {
            let model = model()
            model.toneRead.preview(state)
            return model
        }

        let read = ToneCheck.Read(summary: "May come across as a bit rushed; the asks are clear.",
                                  hint: "Add a thanks before asking someone to own the release notes.")
        let screens: [(String, PanelModel, CGSize)] = [
            ("tone-1-takes", takesModel(notes: ["direct and clear", "warm and polite", "brief, a bit curt"]), CGSize(width: 1060, height: 0)),
            ("tone-2-takes-loading", takesModel(notes: [], loading: true), CGSize(width: 1060, height: 0)),
            ("tone-3-compose-read", composeModel(.done(read)), CGSize(width: 720, height: 460)),
            ("tone-4-compose-loading", composeModel(.loading), CGSize(width: 720, height: 430)),
            ("tone-5-compose-error", composeModel(.failed("Couldn't check the tone: Claude Code: Not logged in. Run `claude auth login` in Terminal.")),
             CGSize(width: 720, height: 450)),
        ]
        for (name, model, size) in screens {
            var size = size
            if size.height == 0 { size.height = fittedHeight(model, width: size.width) }
            for dark in [false, true] {
                write(PanelRootView(model: model), size: size, dark: dark,
                      to: folder.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            }
        }

        var preset = Store.defaultPresets[0]
        let section = PresetToneSection(preset: Binding(get: { preset }, set: { preset = $0 }))
            .padding(28).frame(width: 600).background(Theme.surface)
        for dark in [false, true] {
            write(section, size: CGSize(width: 600, height: 140), dark: dark,
                  to: folder.appendingPathComponent("tone-6-preset-section-\(dark ? "dark" : "light").png"))
        }
    }

    /// Like `bitmap(of:size:)`, with a choice of appearance (Theme's colors follow the window's appearance).
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
