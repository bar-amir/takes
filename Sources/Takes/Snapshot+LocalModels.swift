import AppKit
import SwiftUI

/// Local engine screens for `--snapshot`, in light and dark: Settings › Engine with Ollama found, not running and
/// with no models, and the panel and preset picker running on a local model. Nothing is saved or fetched.
extension Snapshot {
    static func runLocalModels(to url: URL) {
        Store.readOnly = true
        let local = LocalModels.shared
        local.frozen = true
        let saved = Store.shared.settings
        defer { Store.shared.settings = saved }
        Store.shared.settings.engine = .local
        Store.shared.settings.localBaseURL = LocalServerKind.ollama.defaultBaseURL

        let ollama = LocalServerKind.ollama.defaultBaseURL, lmStudio = LocalServerKind.lmStudio.defaultBaseURL
        let states: [(name: String, servers: [LocalModels.Server], model: String)] = [
            ("detected", [.init(baseURL: ollama, models: ["gemma3:4b", "llama3.2:latest", "qwen3:8b"]), .init(baseURL: lmStudio, models: nil)], "llama3.2:latest"),
            ("not-running", [.init(baseURL: ollama, models: nil), .init(baseURL: lmStudio, models: nil)], ""),
            ("no-models", [.init(baseURL: ollama, models: []), .init(baseURL: lmStudio, models: nil)], ""),
        ]
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            for state in states {
                local.servers = state.servers
                local.checked = true
                Store.shared.settings.localModel = state.model
                let settings = SettingsState()
                settings.tab = .engine
                render(SettingsView(state: settings), size: CGSize(width: 1200, height: 1000), dark: dark,
                       to: url.appendingPathComponent("7-local-engine-\(state.name)-\(suffix).png"))
            }

            local.servers = states[0].servers
            Store.shared.settings.localModel = states[0].model
            let compose = PanelModel()
            compose.reset(focus: FocusSnapshot(app: nil, text: "ya thursday works but i need the specs by wed eod otherwise qa slips again",
                                               source: .field, caretRect: nil), presetID: Store.shared.presets.first?.id)
            compose.previewAppName = "Slack"
            render(PanelRootView(model: compose), size: CGSize(width: 720, height: ComposeView.height), dark: dark,
                   to: url.appendingPathComponent("7-local-panel-compose-\(suffix).png"))
            compose.openPicker()
            compose.highlighted = 0
            render(PanelRootView(model: compose), size: CGSize(width: 800, height: 560), dark: dark,
                   to: url.appendingPathComponent("7-local-panel-presets-\(suffix).png"))
            render(LocalModelMenuPreview(options: compose.modelOptions, selected: compose.modelID), size: CGSize(width: 260, height: 150),
                   dark: dark, to: url.appendingPathComponent("7-local-panel-model-menu-\(suffix).png"))
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

/// The panel's Model menu is a native NSMenu, which can't be drawn offscreen; this draws its items the same way.
private struct LocalModelMenuPreview: View {
    let options: [(value: String, title: String)]
    let selected: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(options, id: \.value) { option in
                HStack(spacing: 6) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).opacity(option.value == selected ? 1 : 0)
                    Text(option.title).font(.system(size: 13))
                }
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 8)
                .frame(height: 22)
            }
        }
        .padding(6)
        .frame(width: 200, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.strip)
    }
}
