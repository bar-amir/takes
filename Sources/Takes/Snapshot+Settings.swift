import AppKit
import SwiftUI

/// Settings for `--snapshot`: every tab in light and dark, each at the size the window takes for it, under a drawing
/// of the window's toolbar. Also the Model tab with ChatGPT signed in but not selected, whose row must not claim
/// it's in use. Sample history stands in for the real one; nothing is saved or fetched.
extension Snapshot {
    static func renderSettings(to url: URL) {
        Store.readOnly = true
        let store = Store.shared
        let saved = store.settings, savedHistory = store.history
        let signIn = ChatGPTSignIn.shared, savedSignIn = signIn.state
        let local = LocalModels.shared, providers = ProviderModels.shared
        local.frozen = true
        providers.frozen = true
        defer {
            store.settings = saved
            store.history = savedHistory
            signIn.state = savedSignIn
        }
        store.settings.engine = .claudeCode
        store.settings.lastFirstTextMs = 1700
        store.history = sampleHistory()
        local.servers = [.init(baseURL: LocalServerKind.ollama.defaultBaseURL, models: ["llama3.2:latest"])]
        local.checked = true
        providers.state = .noKey
        providers.hasKey = false
        providers.checked = true
        signIn.state = .signedOut

        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            for tab in SettingsTab.allCases {
                renderSettingsTab(tab, dark: dark, to: url.appendingPathComponent("5-settings-\(tab.rawValue.lowercased())-\(suffix).png"))
            }
            signIn.state = .signedIn(email: "sam@example.com", sharing: true)
            renderSettingsTab(.model, dark: dark, to: url.appendingPathComponent("5-settings-model-chatgpt-not-selected-\(suffix).png"))
            store.settings.engine = .apiKey
            renderSettingsTab(.model, dark: dark, to: url.appendingPathComponent("5-settings-model-api-key-\(suffix).png"))
            store.settings.engine = .claudeCode
            signIn.state = .signedOut
        }
    }

    /// One tab at the size the window would take for it.
    private static func renderSettingsTab(_ tab: SettingsTab, dark: Bool, to url: URL) {
        let state = SettingsState()
        state.tab = tab
        state.selectedPresetID = Store.shared.presets.first?.id
        var size = CGSize(width: SettingsMetrics.width, height: 480)
        _ = settingsBitmap(SettingsView(state: state, onSize: { size = $0 }), size: CGSize(width: 1100, height: 1000), dark: dark)
        let framed = VStack(spacing: 0) {
            SettingsToolbarPreview(selected: tab)
            SettingsView(state: state)
        }
        let rep = settingsBitmap(framed, size: CGSize(width: size.width, height: size.height + SettingsToolbarPreview.height), dark: dark)
        try? rep?.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func settingsBitmap<V: View>(_ view: V, size: CGSize, dark: Bool) -> NSBitmapImageRep? {
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        for _ in 0..<6 { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }
        defer { window.orderOut(nil) }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    private static func sampleHistory() -> [HistoryEntry] {
        let now = Date()
        return [
            HistoryEntry(date: now.addingTimeInterval(-600), appName: "Slack", presetName: Store.shared.presets.first?.name ?? "Slack message",
                         draft: "ya thursday works but i need the specs by wed eod otherwise qa slips again",
                         takes: ["Thursday works. I need the specs by Wednesday EOD, otherwise QA slips again.",
                                 "Sure, Thursday it is. Could I get the specs by Wednesday EOD so QA doesn't slip?"],
                         pastedIndex: 0),
            HistoryEntry(date: now.addingTimeInterval(-3000), appName: "Mail", presetName: "Polish email",
                         draft: "thanks for the quick turnaround on the contract, couple of small notes inline",
                         takes: ["Thanks for the quick turnaround on the contract. I've left a couple of small notes inline."],
                         pastedIndex: nil),
            HistoryEntry(date: now.addingTimeInterval(-86_400 - 3600), appName: "Linear", presetName: "Proofread",
                         draft: "If you will send me the file by tomorrow, I review it before standup",
                         takes: ["If you send me the file by tomorrow, I'll review it before standup."],
                         pastedIndex: 0),
        ]
    }
}

/// The Settings window's toolbar as macOS draws it (title over six icon tabs), for snapshots only: the real one is an
/// NSToolbar, which can't be drawn offscreen.
private struct SettingsToolbarPreview: View {
    static let height: CGFloat = 78
    let selected: SettingsTab

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                HStack(spacing: 8) {
                    ForEach(["#FF5F57", "#FEBC2E", "#28C840"], id: \.self) { Circle().fill(Color(hex: $0)).frame(width: 12, height: 12) }
                    Spacer()
                }
                Text(selected.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
            }
            HStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol).font(.system(size: 16)).frame(height: 20)
                        Text(tab.title).font(.system(size: 11))
                    }
                    .foregroundStyle(tab == selected ? Theme.text : Theme.secondaryText)
                    .frame(minWidth: 58)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7).fill(tab == selected ? Theme.text.opacity(0.08) : .clear))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height, alignment: .top)
        .background(Theme.chrome)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.formGroupBorder).frame(height: 1) }
    }
}
