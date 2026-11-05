import AppKit
import SwiftUI

/// "Your ChatGPT plan" screens for `--snapshot`, in light and dark: the Settings › Model card signed out, waiting for
/// the browser, signed in with the plan's models, and signed in without plan usage; and the panel on a ChatGPT model.
/// The sign-in state and model list are set by hand; nothing is saved, fetched or opened.
extension Snapshot {
    static func runChatGPT(to url: URL) {
        Store.readOnly = true
        let signIn = ChatGPTSignIn.shared, models = ChatGPTModels.shared
        let savedState = signIn.state
        models.frozen = true
        let saved = Store.shared.settings
        defer {
            Store.shared.settings = saved
            signIn.state = savedState
        }
        Store.shared.settings.engine = .chatGPT
        models.set([.init(slug: "gpt-5.4", displayName: "GPT-5.4"), .init(slug: "gpt-5.4-mini", displayName: "GPT-5.4 mini"),
                    .init(slug: "gpt-5.4-thinking", displayName: "GPT-5.4 Thinking")])
        models.checked = true

        let states: [(name: String, state: ChatGPTSignIn.State, model: String)] = [
            ("signed-out", .signedOut, ""),
            ("waiting", .signingIn, ""),
            ("signed-in", .signedIn(email: "sam@example.com", sharing: true), "gpt-5.4"),
            ("not-allowed", .signedIn(email: "sam@example.com", sharing: false), ""),
        ]
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            for state in states {
                signIn.state = state.state
                Store.shared.settings.chatGPTModel = state.model
                let settings = SettingsState()
                settings.tab = .engine
                renderChatGPT(SettingsView(state: settings), size: CGSize(width: 780, height: 760), dark: dark,
                              to: url.appendingPathComponent("10-chatgpt-card-\(state.name)-\(suffix).png"))
            }

            signIn.state = .signedIn(email: "sam@example.com", sharing: true)
            Store.shared.settings.chatGPTModel = "gpt-5.4"
            let compose = PanelModel()
            compose.reset(focus: FocusSnapshot(app: nil, text: "ya thursday works but i need the specs by wed eod otherwise qa slips again",
                                               source: .field, caretRect: nil), presetID: Store.shared.presets.first?.id)
            compose.previewAppName = "Slack"
            renderChatGPT(PanelRootView(model: compose), size: CGSize(width: 720, height: ComposeView.height), dark: dark,
                          to: url.appendingPathComponent("10-chatgpt-panel-compose-\(suffix).png"))
        }
    }

    private static func renderChatGPT<V: View>(_ view: V, size: CGSize, dark: Bool, to url: URL) {
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
