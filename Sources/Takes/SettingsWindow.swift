import AppKit
import SwiftUI

@MainActor
final class SettingsState: ObservableObject {
    @Published var tab = SettingsTab.presets
    @Published var selectedPresetID: String?
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private let state = SettingsState()

    func show(tab: SettingsTab, newPreset: Bool = false) {
        let store = Store.shared
        state.tab = tab
        if newPreset {
            let preset = store.newPreset()
            store.presets.append(preset)
            state.selectedPresetID = preset.id
        } else if state.selectedPresetID == nil || store.preset(id: state.selectedPresetID) == nil {
            state.selectedPresetID = store.presets.first?.id
        }

        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 860),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Takes"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 1000, height: 660)
        window.backgroundColor = NSColor(Theme.surface)
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(state: state))
        window.center()
        return window
    }
}

struct SettingsView: View {
    @ObservedObject var state: SettingsState

    var body: some View {
        VStack(spacing: 0) {
            // The title bar: traffic lights on the left, section tabs centered.
            TabPills(options: SettingsTab.allCases.map { (value: $0, title: $0.rawValue) }, selection: $state.tab)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Theme.chrome)
            RowDivider()

            Group {
                switch state.tab {
                case .presets: PresetsTab(state: state)
                case .voice: VoiceTab()
                case .engine: EngineTab()
                case .history: HistoryTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(Theme.text)
        .background(Theme.surface)
        .tint(Theme.accent)
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 1000, minHeight: 660)
    }
}

// MARK: - Shared editors

/// Chips with ✕ and an inline "+ Add" field.
struct ChipsEditor: View {
    @Binding var items: [String]
    var style: Chip.Style
    @State private var adding = false
    @State private var newText = ""

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 6) {
                    Text(item).font(.system(size: 13))
                    Button { items.removeAll { $0 == item } } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(item)")
                }
                .foregroundStyle(style == .positive ? Theme.doText : style == .negative ? Theme.avoidText : Theme.text)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(style == .positive ? Theme.doFill : style == .negative ? Theme.avoidFill : Theme.kbdFill))
            }
            if adding {
                StyledTextField(placeholder: "Type and press ↵", text: $newText, height: 28, onSubmit: commit)
                    .frame(width: 220)
                    .onExitCommand { adding = false; newText = "" }
            } else {
                Button("+ Add") { adding = true }.buttonStyle(DashedButtonStyle())
            }
        }
    }

    private func commit() {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty && !items.contains(text) { items.append(text) }
        newText = ""
        adding = false
    }
}

/// Click, then press a shortcut. Esc cancels, ⌫ clears.
struct HotKeyRecorder: View {
    @Binding var combo: KeyCombo?
    var allowClear = true
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            Text(recording ? "Press a shortcut…" : (combo?.display ?? "Record shortcut"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(recording ? Theme.accent : Theme.text)
                .frame(minWidth: 110)
        }
        .buttonStyle(SecondaryButtonStyle(height: 36))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent, lineWidth: recording ? 1.5 : 0))
        .onDisappear(perform: stop)
        .help("Click, then press a shortcut. Esc cancels\(allowClear ? ", ⌫ clears" : "").")
    }

    private func toggle() { recording ? stop() : start() }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Esc
            if event.keyCode == 51 && allowClear { combo = nil; stop(); return nil } // ⌫
            if let recorded = KeyCombo(event: event) {
                combo = recorded
                stop()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

struct VoiceRulesEditor: View {
    @ObservedObject var store = Store.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RowGroup {
                ForEach($store.settings.voiceRules) { $rule in
                    HStack(spacing: 12) {
                        Checkbox(isOn: $rule.enabled, label: rule.text)
                        TextField("Rule", text: $rule.text)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .foregroundStyle(rule.enabled ? Theme.text : Theme.secondaryText)
                        Button { store.settings.voiceRules.removeAll { $0.id == rule.id } } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete rule")
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    if rule.id != store.settings.voiceRules.last?.id { RowDivider() }
                }
            }
            Button("+ Add rule") { store.settings.voiceRules.append(VoiceRule(text: "")) }
                .buttonStyle(DashedButtonStyle(capsule: false))
        }
    }
}
