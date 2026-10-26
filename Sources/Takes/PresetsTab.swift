import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PresetsTab: View {
    @ObservedObject var state: SettingsState
    @ObservedObject var store = Store.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 260)
            Rectangle().fill(Theme.border).frame(width: 1)
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
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(store.presets.enumerated()), id: \.element.id) { index, preset in
                        row(preset, index: index)
                    }
                }
                .padding(12)
            }
            HStack(spacing: 6) {
                Button {
                    let preset = store.newPreset()
                    store.presets.append(preset)
                    state.selectedPresetID = preset.id
                } label: { Text("New").lineLimit(1).frame(maxWidth: .infinity) }
                Button { if let preset = store.preset(id: state.selectedPresetID) { duplicate(preset) } } label: {
                    Text("Duplicate").lineLimit(1).fixedSize().frame(maxWidth: .infinity)
                }
                .disabled(state.selectedPresetID == nil)
                Button(action: importPresets) { Text("Import").lineLimit(1).frame(maxWidth: .infinity) }
            }
            .buttonStyle(SecondaryButtonStyle(height: 34))
            .padding(12)
        }
        .background(Theme.sidebar)
    }

    private func row(_ preset: Preset, index: Int) -> some View {
        let selected = preset.id == state.selectedPresetID
        return Button { state.selectedPresetID = preset.id } label: {
            HStack(spacing: 10) {
                PresetDot(hex: preset.colorHex)
                Text(preset.name)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if index < 9 { Text("⌘\(index + 1)").font(.system(size: 11)).foregroundStyle(Theme.tertiaryText) }
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.selectedRow : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Move up") { move(preset, by: -1) }.disabled(index == 0)
            Button("Move down") { move(preset, by: 1) }.disabled(index == store.presets.count - 1)
            Divider()
            Button("Duplicate") { duplicate(preset) }
            Button("Export…") { export(preset) }
            Divider()
            Button("Delete…", role: .destructive) { delete(preset) }.disabled(store.presets.count <= 1)
        }
    }

    private func move(_ preset: Preset, by offset: Int) {
        guard let index = store.index(of: preset.id) else { return }
        let target = index + offset
        guard store.presets.indices.contains(target) else { return }
        store.presets.swapAt(index, target)
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
                VStack(alignment: .leading, spacing: 22) {
                    nameRow
                    VStack(alignment: .leading, spacing: 6) {
                        FieldLabel("Instruction")
                        StyledTextEditor(text: $preset.instruction, height: 76)
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
                    HStack(alignment: .top, spacing: 28) {
                        VStack(alignment: .leading, spacing: 6) {
                            FieldLabel("Reply language")
                            ChoiceSegments(options: ReplyLanguage.allCases.map { (value: $0, title: $0.label) }, selection: $preset.language)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            FieldLabel("Picked automatically in")
                            AppsEditor(apps: $preset.apps)
                        }
                    }
                    runDefaults
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 540)
            Rectangle().fill(Theme.border).frame(width: 1)
            TryItPanel(preset: preset).frame(width: 370)
        }
    }

    private var nameRow: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("Name")
                StyledTextField(placeholder: "Name", text: $preset.name)
            }
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("Color")
                HStack(spacing: 7) {
                    ForEach(Preset.colors, id: \.self) { hex in
                        Button { preset.colorHex = hex } label: {
                            Circle().fill(Color(hex: hex)).frame(width: 18, height: 18)
                                .overlay(Circle().stroke(Theme.text, lineWidth: preset.colorHex == hex ? 2 : 0).padding(-3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Color \(hex)")
                        .accessibilityAddTraits(preset.colorHex == hex ? .isSelected : [])
                    }
                }
                .frame(height: 36)
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
            FlowLayout(spacing: 18) {
                LabeledMenu(label: "Takes", options: (1...5).map { (value: $0, title: "\($0)") }, selection: $preset.takes)
                LabeledMenu(label: "Model", options: Models.all.map { (value: $0.id, title: $0.label) }, selection: $preset.model)
                LabeledMenu(label: "Effort", options: Models.efforts.map { (value: $0, title: $0.capitalized) }, selection: $preset.effort)
                LabeledMenu(label: "Length", options: TakeLength.allCases.map { (value: $0, title: $0.label) }, selection: $preset.length)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
                Text("\(examples.count) of \(Preset.maxExamples)").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            }
            ForEach(examples.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 8) {
                    StyledTextEditor(text: Binding(get: { examples.indices.contains(index) ? examples[index] : "" },
                                                   set: { if examples.indices.contains(index) { examples[index] = $0 } }),
                                     height: 58, fontSize: 13, fill: Theme.sidebar)
                    Button { examples.remove(at: index) } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .accessibilityLabel("Remove example")
                }
            }
            if examples.isEmpty {
                Text("[A message you wrote and liked, saved from a take or pasted in]")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.sidebar))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
            }
            HStack(spacing: 10) {
                if examples.count < Preset.maxExamples {
                    Button("+ Add a message you wrote") { examples.append("") }.buttonStyle(DashedButtonStyle(capsule: false))
                }
                Text("Or choose “Save as example” after pasting a take you like.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

private struct AppsEditor: View {
    @Binding var apps: [AppRef]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(apps) { app in
                HStack(spacing: 6) {
                    Text(app.name).font(.system(size: 13))
                    Button { apps.removeAll { $0.id == app.id } } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(app.name)")
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.kbdFill))
            }
            Button("+ App", action: showMenu).buttonStyle(DashedButtonStyle(capsule: false))
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        for app in runningApps {
            let item = ClosureMenuItem(title: app.name) { if !apps.contains(app) { apps.append(app) } }
            item.state = apps.contains(app) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Choose from Applications…", handler: chooseApp))
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
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
                Text("Try it").font(.system(size: 16, weight: .bold))
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel("Sample draft")
                    StyledTextEditor(text: $sample, height: 100)
                }
                Button(action: run) {
                    Text(running ? "Writing…" : "Run with these settings").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(running || sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let error { Text(error).font(.system(size: 13)).foregroundStyle(Theme.avoidText).textSelection(.enabled) }
                ForEach(Array(takes.enumerated()), id: \.offset) { index, take in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Take \(index + 1)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                        Text(take).font(.system(size: 14)).lineSpacing(3).textSelection(.enabled)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                }
                Text("Saved automatically. Presets are a plain file you can back up or share (right-click a preset › Export).")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineSpacing(2)
            }
            .padding(22)
        }
        .background(Theme.sidebar)
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
