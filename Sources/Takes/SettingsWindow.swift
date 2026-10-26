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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Takes"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 980, height: 640)
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
            Picker("Section", selection: $state.tab) {
                ForEach(SettingsTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 380)
            .padding(.top, 10)
            .padding(.bottom, 10)
            Divider()

            switch state.tab {
            case .presets: PresetsTab(state: state)
            case .voice: VoiceTab()
            case .engine: EngineTab()
            case .history: HistoryTab()
            }
        }
        .tint(Theme.accent)
        .frame(minWidth: 980, minHeight: 640)
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
        FlowLayout {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 4) {
                    Text(item).font(.system(size: 12))
                    Button { items.removeAll { $0 == item } } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(item)")
                }
                .foregroundStyle(style == .positive ? Theme.doText : style == .negative ? Theme.avoidText : .primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(style == .positive ? Theme.doFill : style == .negative ? Theme.avoidFill : Color.primary.opacity(0.06)))
            }
            if adding {
                TextField("Type and press ↵", text: $newText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit(commit)
                    .onExitCommand { adding = false; newText = "" }
            } else {
                Button("+ Add") { adding = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .overlay(Capsule().stroke(style: StrokeStyle(lineWidth: 1, dash: [3])).foregroundStyle(Theme.secondaryText))
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
                .font(.system(size: 13, weight: .semibold))
                .frame(minWidth: 120)
        }
        .onDisappear(perform: stop)
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

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 17, weight: .bold)) }
}

struct FieldLabel: View {
    let text: String
    var color: Color = .secondary
    init(_ text: String, color: Color = .secondary) { self.text = text; self.color = color }
    var body: some View { Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(color) }
}

/// A rounded group of rows, as in macOS settings.
struct RowGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }
}

struct VoiceRulesEditor: View {
    @ObservedObject var store = Store.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RowGroup {
                ForEach($store.settings.voiceRules) { $rule in
                    HStack(spacing: 10) {
                        Toggle("", isOn: $rule.enabled).labelsHidden().toggleStyle(.checkbox)
                        TextField("Rule", text: $rule.text).textFieldStyle(.plain)
                        Button { store.settings.voiceRules.removeAll { $0.id == rule.id } } label: {
                            Image(systemName: "minus.circle").foregroundStyle(Theme.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete rule")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    if rule.id != store.settings.voiceRules.last?.id { Divider() }
                }
            }
            Button("+ Add rule") { store.settings.voiceRules.append(VoiceRule(text: "")) }
        }
    }
}
