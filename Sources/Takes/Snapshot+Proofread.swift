import AppKit
import SwiftUI

/// Proofread screens for `--snapshot`: takes with fixes, no mistakes found and the preset editor's
/// minimal-edits option, each in light and dark.
extension Snapshot {
    static func renderProofread(to url: URL) {
        let fixed = (draft: "hey dana, i think teh specs are due wed but lets confirm with qa before we promise anything",
                     take: "Hey Dana, I think the specs are due Wed, but let's confirm with QA before we promise anything.")
        let clean = "Thanks, that works for me. I'll send the notes after the call."

        func model(draft: String, takes: [String], preset: Preset = .proofread) -> PanelModel {
            let model = PanelModel()
            model.reset(focus: FocusSnapshot(app: nil, text: draft, source: .field, caretRect: nil), presetID: nil)
            model.previewAppName = "Slack"
            model.previewPreset = preset
            model.takeCount = preset.takes
            model.modelID = preset.model
            model.effort = preset.effort
            model.screen = .takes
            model.sourceDraft = draft
            model.takes = takes
            model.changesShown = model.showsFixes ? Set(takes.indices) : []
            model.timing = "first words 0.9 s · all takes 1.4 s"
            return model
        }

        var threeTakes = Preset.proofread
        threeTakes.name = "Proofread, 3 takes"
        threeTakes.takes = 3
        let screens: [(name: String, model: PanelModel, width: CGFloat)] = [
            ("7-proofread-fixes", model(draft: fixed.draft, takes: [fixed.take]), 720),
            ("7-proofread-no-mistakes", model(draft: clean, takes: [clean]), 720),
            ("7-proofread-three-takes", model(draft: fixed.draft, takes: [
                fixed.take,
                "Hey Dana, I think the specs are due Wed, but let's confirm with QA before we promise anything.",
                fixed.draft,
            ], preset: threeTakes), 1060),
        ]
        for screen in screens {
            let height = fittedHeight(screen.model, width: screen.width)
            for dark in [false, true] {
                write(PanelRootView(model: screen.model), size: CGSize(width: screen.width, height: height), dark: dark,
                      to: url.appendingPathComponent("\(screen.name)-\(dark ? "dark" : "light").png"))
            }
        }

        let editor = SnapshotEditorBox()
        for dark in [false, true] {
            write(editor, size: CGSize(width: 560, height: 96), dark: dark,
                  to: url.appendingPathComponent("7-proofread-editor-\(dark ? "dark" : "light").png"))
        }
    }

    private static func write<V: View>(_ view: V, size: CGSize, dark: Bool, to url: URL) {
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

/// The preset editor's minimal-edits option on its own, as it sits under "Run defaults".
private struct SnapshotEditorBox: View {
    @State var preset = Preset.proofread
    var body: some View {
        MinimalEditsSection(preset: $preset)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface)
    }
}
