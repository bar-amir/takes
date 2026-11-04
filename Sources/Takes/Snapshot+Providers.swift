import AppKit
import SwiftUI

/// Other-provider screens for `--snapshot`, in light and dark: the Settings › Engine card with no key, ready with the
/// model menu and a passed test, with a refused key, and with a custom address; and the panel running on a provider
/// model. Nothing is saved, fetched or read from the keychain.
extension Snapshot {
    static func runProviders(to url: URL) {
        Store.readOnly = true
        let models = ProviderModels.shared
        models.frozen = true
        let saved = Store.shared.settings
        defer { Store.shared.settings = saved }
        Store.shared.settings.engine = .provider

        let openAIModels = ["gpt-4.1-mini", "gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano", "o4-mini"]
        let states: [(name: String, provider: Provider, state: ProviderModels.State, hasKey: Bool, model: String,
                      test: ProviderModels.TestState)] = [
            ("no-key", .openAI, .noKey, false, "", .idle),
            ("ready", .openAI, .ready, true, "gpt-5.4", .passed(820)),
            ("key-refused", .openAI, .refused(Provider.openAI.refusedMessage), true, "gpt-5.4", .idle),
            ("gemini", .gemini, .noKey, false, "", .idle),
            ("custom", .custom(baseURL: "https://llm.example.com/v1"), .failed("llm.example.com error: HTTP 404"), true,
             "qwen3-32b", .passed(1430)),
        ]
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            for state in states {
                Store.shared.settings.providerID = state.provider.id
                Store.shared.settings.providerBaseURL = state.provider.baseURL
                Store.shared.settings.providerModel = state.model
                models.models = state.state == .ready ? openAIModels : []
                models.state = state.state
                models.hasKey = state.hasKey
                models.test = state.test
                models.checked = true
                let settings = SettingsState()
                settings.tab = .engine
                render(SettingsView(state: settings), size: CGSize(width: 1200, height: 1500), dark: dark,
                       to: url.appendingPathComponent("9-provider-engine-\(state.name)-\(suffix).png"))
            }

            Store.shared.settings.providerID = Provider.openAI.id
            Store.shared.settings.providerBaseURL = Provider.openAI.baseURL
            Store.shared.settings.providerModel = "gpt-5.4"
            models.models = openAIModels
            models.state = .ready
            models.hasKey = true
            let compose = PanelModel()
            compose.reset(focus: FocusSnapshot(app: nil, text: "ya thursday works but i need the specs by wed eod otherwise qa slips again",
                                               source: .field, caretRect: nil), presetID: Store.shared.presets.first?.id)
            compose.previewAppName = "Slack"
            render(PanelRootView(model: compose), size: CGSize(width: 720, height: ComposeView.height), dark: dark,
                   to: url.appendingPathComponent("9-provider-panel-compose-\(suffix).png"))
            compose.openPicker()
            compose.highlighted = 0
            render(PanelRootView(model: compose), size: CGSize(width: 800, height: 560), dark: dark,
                   to: url.appendingPathComponent("9-provider-panel-presets-\(suffix).png"))
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
