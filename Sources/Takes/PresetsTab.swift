import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PresetsTab: View {
    @ObservedObject var state: SettingsState
    @ObservedObject var store = Store.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 250)
            Divider()
            if let index = store.presets.firstIndex(where: { $0.id == state.selectedPresetID }) {
                PresetEditor(preset: $store.presets[index])
                    .id(store.presets[index].id)
            } else {
                Text("Choose a preset").foregroundStyle(Theme.secondaryText).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $state.selectedPresetID) {
                ForEach(Array(store.presets.enumerated()), id: \.element.id) { index, preset in
                    HStack(spacing: 10) {
                        PresetDot(hex: preset.colorHex)
                        Text(preset.name).lineLimit(1)
                        Spacer()
                        if index < 9 { Text("⌘\(index + 1)").font(.caption).foregroundStyle(Theme.secondaryText) }
                    }
                    .tag(preset.id)
                    .contextMenu {
                        Button("Duplicate") { duplicate(preset) }
                        Button("Export…") { export(preset) }
                        Divider()
                        Button("Delete", role: .destructive) { delete(preset) }
                    }
                }
                .onMove { store.presets.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.sidebar)

            HStack(spacing: 6) {
                Button("New") {
                    let preset = store.newPreset()
                    store.presets.append(preset)
                    state.selectedPresetID = preset.id
                }
                Button("Duplicate") {
                    if let preset = store.preset(id: state.selectedPresetID) { duplicate(preset) }
                }
                .disabled(state.selectedPresetID == nil)
                Button("Import") { importPresets() }
                Button { if let preset = store.preset(id: state.selectedPresetID) { delete(preset) } } label: {
                    Image(systemName: "trash")
                }
                .disabled(store.presets.count <= 1)
                .accessibilityLabel("Delete preset")
            }
            .padding(10)
        }
    }

    private func duplicate(_ preset: Preset) {
        var copy = preset
        copy.id = UUID().uuidString
        copy.name += " copy"
        copy.hotKey = nil
        copy.apps = []
        let index = (store.index(of: preset.id) ?? store.presets.count - 1) + 1
        store.presets.insert(copy, at: index)
        state.selectedPresetID = copy.id
    }

    private func delete(_ preset: Preset) {
        guard store.presets.count > 1 else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(preset.name)”?"
        alert.informativeText = "You can't undo this."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.presets.removeAll { $0.id == preset.id }
        state.selectedPresetID = store.presets.first?.id
    }

    private func export(_ preset: Preset) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(preset.name).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode([preset]).write(to: url)
    }

    private func importPresets() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let decoded = (try? JSONDecoder().decode([Preset].self, from: data))
                ?? (try? JSONDecoder().decode(Preset.self, from: data)).map { [$0] } ?? []
            for var preset in decoded {
                preset.id = UUID().uuidString
                preset.hotKey = nil
                store.presets.append(preset)
                state.selectedPresetID = preset.id
            }
        }
    }
}

private struct PresetEditor: View {
    @Binding var preset: Preset

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    nameRow
                    VStack(alignment: .leading, spacing: 6) {
                        FieldLabel("Instruction")
                        TextEditor(text: $preset.instruction)
                            .font(.system(size: 14))
                            .frame(height: 76)
                            .padding(6)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        FieldLabel("Do", color: Theme.doText)
                        ChipsEditor(items: $preset.dos, style: .positive)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        FieldLabel("Avoid", color: Theme.avoidText)
                        ChipsEditor(items: $preset.avoid, style: .negative)
                    }
                    ExamplesEditor(examples: $preset.examples)
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            FieldLabel("Reply language").fixedSize()
                            Picker("Reply language", selection: $preset.language) {
                                ForEach(ReplyLanguage.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            FieldLabel("Picked automatically in")
                            AppsEditor(apps: $preset.apps)
                        }
                    }
                    runDefaults
                }
                .padding(26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 520)
            Divider()
            TryItPanel(preset: preset).frame(width: 360)
        }
    }

    private var nameRow: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("Name")
                TextField("Name", text: $preset.name).textFieldStyle(.roundedBorder).font(.system(size: 14))
            }
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("Color")
                HStack(spacing: 6) {
                    ForEach(Preset.colors, id: \.self) { hex in
                        Button { preset.colorHex = hex } label: {
                            Circle().fill(Color(hex: hex)).frame(width: 16, height: 16)
                                .overlay(Circle().stroke(Color.primary, lineWidth: preset.colorHex == hex ? 2 : 0).padding(-3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Color \(hex)")
                    }
                }
                .frame(height: 22)
            }
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("Own hotkey")
                HotKeyRecorder(combo: $preset.hotKey)
            }
        }
    }

    private var runDefaults: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Run defaults")
            FlowLayout(spacing: 16) {
            Picker("Takes", selection: $preset.takes) { ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }
                .fixedSize()
            Picker("Model", selection: $preset.model) { ForEach(Models.all, id: \.id) { Text($0.label).tag($0.id) } }
                .fixedSize()
            Picker("Effort", selection: $preset.effort) { ForEach(Models.efforts, id: \.self) { Text($0.capitalized).tag($0) } }
                .fixedSize()
            Picker("Length", selection: $preset.length) { ForEach(TakeLength.allCases) { Text($0.label).tag($0) } }
                .fixedSize()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.strip))
    }
}

private struct ExamplesEditor: View {
    @Binding var examples: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                FieldLabel("Write like me · examples")
                Spacer()
                Text("\(examples.count) of \(Preset.maxExamples)").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            ForEach(examples.indices, id: \.self) { index in
                HStack(alignment: .top) {
                    TextEditor(text: Binding(get: { examples.indices.contains(index) ? examples[index] : "" },
                                             set: { if examples.indices.contains(index) { examples[index] = $0 } }))
                        .font(.system(size: 13))
                        .frame(height: 54)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.strip))
                    Button { examples.remove(at: index) } label: { Image(systemName: "minus.circle").foregroundStyle(Theme.secondaryText) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove example")
                }
            }
            if examples.count < Preset.maxExamples {
                Button("+ Add a message you wrote") { examples.append("") }
            }
            Text("Tip: after pasting a take you like, choose “Save as example”.")
                .font(.caption).foregroundStyle(Theme.secondaryText)
        }
    }
}

private struct AppsEditor: View {
    @Binding var apps: [AppRef]

    var body: some View {
        FlowLayout {
            ForEach(apps) { app in
                HStack(spacing: 4) {
                    Text(app.name).font(.system(size: 12))
                    Button { apps.removeAll { $0.id == app.id } } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(app.name)")
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
            }
            Menu("+ App") {
                ForEach(runningApps, id: \.bundleID) { app in
                    Button(app.name) { if !apps.contains(app) { apps.append(app) } }
                }
                Divider()
                Button("Choose from Applications…", action: chooseApp)
            }
            .fixedSize()
        }
    }

    private var runningApps: [AppRef] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.bundleIdentifier.map { AppRef(bundleID: $0, name: app.localizedName ?? $0) } }
            .filter { $0.bundleID != Bundle.main.bundleIdentifier }
            .sorted { $0.name < $1.name }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        let app = AppRef(bundleID: id, name: name)
        if !apps.contains(app) { apps.append(app) }
    }
}

/// Runs the preset as edited, on a sample draft.
private struct TryItPanel: View {
    let preset: Preset
    @State private var sample = "ya thursday works but i need the specs by wed eod otherwise qa slips again"
    @State private var takes: [String] = []
    @State private var running = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Try it").font(.system(size: 15, weight: .bold))
                FieldLabel("Sample draft")
                TextEditor(text: $sample)
                    .font(.system(size: 14))
                    .frame(height: 96)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                Button(action: run) {
                    Text(running ? "Writing…" : "Run with these settings").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(running || sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let error { Text(error).font(.callout).foregroundStyle(Theme.avoidText).textSelection(.enabled) }
                ForEach(Array(takes.enumerated()), id: \.offset) { index, take in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Take \(index + 1)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                        Text(take).font(.system(size: 14)).textSelection(.enabled)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                }
                Text("Saved automatically. Presets are a plain file you can back up or share (right-click › Export).")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
            .padding(22)
        }
        .background(Theme.strip)
    }

    private func run() {
        let store = Store.shared
        let request = EngineRequest(
            system: PromptBuilder.system(preset: preset, takes: preset.takes, rules: store.settings.voiceRules),
            user: PromptBuilder.user(draft: sample, mode: .fresh, takes: preset.takes),
            takes: preset.takes, model: preset.model, effort: preset.effort)
        let engine = Engines.current(store.settings)
        running = true
        error = nil
        takes = []
        Task { @MainActor in
            do {
                let result = try await engine.run(request) { partial in
                    Task { @MainActor in if running { takes = partial } }
                }
                takes = result.takes
            } catch {
                self.error = error.localizedDescription
            }
            running = false
        }
    }
}
