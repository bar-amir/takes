import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Presets: the source list on the left (with add, remove and Browse… under it), the preset as a grouped
/// form in the middle, and "Try it" on the right.
struct PresetsTab: View {
    @ObservedObject var state: SettingsState
    @ObservedObject var store = Store.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 210)
            Rectangle().fill(Theme.formGroupBorder).frame(width: 1)
            if let index = store.presets.firstIndex(where: { $0.id == state.selectedPresetID }) {
                VStack(spacing: 0) {
                    if PresetGallery.isUntouchedNew(store.presets[index], blank: store.newPreset()) {
                        GalleryHintBar { state.showGallery = true }
                    }
                    PresetEditor(preset: $store.presets[index])
                        .id(store.presets[index].id)
                }
            } else {
                VStack(spacing: 12) {
                    Text("Choose a preset, or start from a ready-made one.").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                    Button("Browse presets…") { state.showGallery = true }.buttonStyle(SecondaryButtonStyle(height: 30)).fixedSize()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.formBackground)
        .sheet(isPresented: $state.showGallery) {
            PresetGalleryView(onAdd: galleryAdded, onClose: { state.showGallery = false })
        }
    }

    /// Selects the first new copy. A blank "New preset" the gallery was opened from gives way to it.
    private func galleryAdded(_ added: [Preset]) {
        if let current = store.preset(id: state.selectedPresetID), PresetGallery.isUntouchedNew(current, blank: store.newPreset()) {
            store.presets.removeAll { $0.id == current.id }
        }
        state.selectedPresetID = added.first?.id ?? state.selectedPresetID
        state.showGallery = false
    }

    private var selected: Preset? { store.preset(id: state.selectedPresetID) }

    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(store.presets.enumerated()), id: \.element.id) { index, preset in
                        row(preset, index: index)
                    }
                }
                .padding(10)
            }
            Rectangle().fill(Theme.formGroupBorder).frame(height: 1)
            HStack(spacing: 4) {
                Button(action: addPreset) { Image(systemName: "plus") }
                    .buttonStyle(SourceListButtonStyle())
                    .help("New preset")
                    .accessibilityLabel("New preset")
                Button { if let selected { delete(selected) } } label: { Image(systemName: "minus") }
                    .buttonStyle(SourceListButtonStyle())
                    .help("Delete preset…")
                    .accessibilityLabel("Delete preset")
                    .disabled(selected == nil || store.presets.count <= 1)
                Menu {
                    Button("Duplicate") { if let selected { duplicate(selected) } }.disabled(selected == nil)
                    Button("Import…", action: importPresets)
                    Button("Export…") { if let selected { export(selected) } }.disabled(selected == nil)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(width: 26, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.controlBorder))
                .help("Duplicate, import or export")
                .accessibilityLabel("More preset actions")
                Spacer(minLength: 4)
                Button("Browse…") { state.showGallery = true }
                    .buttonStyle(SecondaryButtonStyle(height: 22))
                    .fixedSize()
                    .help("Add ready-made presets")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private func row(_ preset: Preset, index: Int) -> some View {
        let selected = preset.id == state.selectedPresetID
        return Button { state.selectedPresetID = preset.id } label: {
            HStack(spacing: 8) {
                PresetDot(hex: preset.colorHex)
                Text(preset.name.isEmpty ? "Untitled" : preset.name)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.onAccent : Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if index < 9 {
                    Text("⌘\(index + 1)").font(.system(size: 11))
                        .foregroundStyle(selected ? Theme.onAccent.opacity(0.7) : Theme.tertiaryText)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Theme.accent : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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

    private func addPreset() {
        let preset = store.newPreset()
        store.presets.append(preset)
        state.selectedPresetID = preset.id
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
        guard confirmDestructive("Delete “\(preset.name)”?", message: "You can't undo this.", button: "Delete") else { return }
        let index = store.index(of: preset.id) ?? 0
        store.presets.removeAll { $0.id == preset.id }
        state.selectedPresetID = store.presets[min(index, store.presets.count - 1)].id
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
                // A file can't turn on paste-without-looking; the user does that themselves (PRIVACY.md).
                preset.instantMode = nil
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
                    FormSection("Preset") {
                        FormRow("Name") {
                            StyledTextField(placeholder: "Name", text: $preset.name, height: 28).frame(width: 240)
                        }
                        FormDivider()
                        FormRow("Color") { colors }
                        FormDivider()
                        FormRow("Own hotkey") { HotKeyRecorder(combo: $preset.hotKey, height: 28) }
                        FormDivider()
                        FormRow("Picked automatically in") {
                            AppsEditor(apps: $preset.apps).frame(maxWidth: 280, alignment: .trailing)
                        }
                    }

                    FormSection("Instruction") {
                        TextEditor(text: $preset.instruction)
                            .font(.system(size: 13))
                            .lineSpacing(3)
                            .scrollContentBackground(.hidden)
                            .frame(height: 78)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 8)
                            .accessibilityLabel("Instruction")
                    }

                    FormSection("Do") {
                        ChipsEditor(items: $preset.dos, style: .positive).padding(10)
                    }
                    FormSection("Avoid") {
                        ChipsEditor(items: $preset.avoid, style: .negative).padding(10)
                    }

                    ExamplesEditor(examples: $preset.examples)

                    FormSection(header: "Run") {
                        FormRow("Takes · Model · Effort") {
                            HStack(spacing: 6) {
                                MenuPicker(options: (1...5).map { (value: $0, title: "\($0)") }, selection: $preset.takes)
                                MenuPicker(options: Models.all.map { (value: $0.id, title: $0.label) }, selection: $preset.model)
                                MenuPicker(options: Models.efforts.map { (value: $0, title: $0.capitalized) }, selection: $preset.effort)
                            }
                        }
                        FormDivider()
                        FormRow("Length") {
                            MenuPicker(options: TakeLength.allCases.map { (value: $0, title: $0.label) }, selection: $preset.length)
                        }
                        FormDivider()
                        FormRow("Reply language") {
                            ReplyLanguagePicker(selection: $preset.language, writingLanguages: Store.shared.settings.writingLanguages)
                        }
                    } footer: {
                        LocalEngineModelNote()
                    }

                    PresetOptionsCard(preset: $preset)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(Theme.formGroupBorder).frame(width: 1)
            TryItPanel(preset: preset).frame(width: 270)
        }
    }

    private var colors: some View {
        HStack(spacing: 8) {
            ForEach(Preset.colors, id: \.self) { hex in
                Button { preset.colorHex = hex } label: {
                    Circle().fill(Color(hex: hex)).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Theme.text, lineWidth: preset.colorHex == hex ? 1.5 : 0).padding(-3))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color \(hex)")
                .accessibilityAddTraits(preset.colorHex == hex ? .isSelected : [])
            }
        }
        .padding(.trailing, 3)
    }
}

/// "Write like me": up to five messages you wrote, one per row.
private struct ExamplesEditor: View {
    @Binding var examples: [String]

    var body: some View {
        FormSection(header: "Write like me") {
            ForEach(examples.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 8) {
                    TextEditor(text: Binding(get: { examples.indices.contains(index) ? examples[index] : "" },
                                             set: { if examples.indices.contains(index) { examples[index] = $0 } }))
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .frame(height: 52)
                        .accessibilityLabel("Example \(index + 1)")
                    Button { examples.remove(at: index) } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    .help("Remove example")
                    .accessibilityLabel("Remove example \(index + 1)")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                FormDivider()
            }
            HStack(spacing: 10) {
                if examples.count < Preset.maxExamples {
                    Button { examples.append("") } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                            Text("Add a message you wrote")
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.controlText)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("\(examples.count) of \(Preset.maxExamples)").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            }
            .formRowPadding()
        } footer: {
            Text("Or choose “Save as example” after pasting a take you like.")
        }
    }
}

private struct AppsEditor: View {
    @Binding var apps: [AppRef]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(apps) { app in
                HStack(spacing: 6) {
                    AppGlyph(appURL: AppGlyph.url(forBundleID: app.bundleID), size: 16)
                    Text(app.name).font(.system(size: 12.5))
                    Button { apps.removeAll { $0.id == app.id } } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(app.name)")
                }
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(Capsule().fill(Theme.kbdFill))
            }
            Button("+ App", action: showMenu).buttonStyle(DashedButtonStyle())
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        for app in runningApps {
            let item = ClosureMenuItem(title: app.name) { if !apps.contains(app) { apps.append(app) } }
            item.state = apps.contains(app) ? .on : .off
            item.image = AppGlyph.icon(for: AppGlyph.url(forBundleID: app.bundleID)).map { icon in
                let small = icon.copy() as! NSImage
                small.size = NSSize(width: 16, height: 16)
                return small
            }
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
                FormSection("Try it") {
                    TextEditor(text: $sample)
                        .font(.system(size: 13))
                        .lineSpacing(2)
                        .scrollContentBackground(.hidden)
                        .frame(height: 96)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 8)
                        .accessibilityLabel("Sample draft")
                }
                Button(action: run) {
                    Text(running ? "Writing…" : "Run with these settings").lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(height: 32))
                .disabled(running || sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let error { Text(error).font(.system(size: 12)).foregroundStyle(Theme.avoidText).textSelection(.enabled) }
                ForEach(Array(takes.enumerated()), id: \.offset) { index, take in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TAKE \(index + 1)").font(.mono(10, bold: true)).foregroundStyle(Theme.secondaryText)
                        Text(take).font(.system(size: 13)).lineSpacing(2).textSelection(.enabled)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.formGroup))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.formGroupBorder))
                }
                Text("Saved as you type. Right-click a preset to export it.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
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

/// The small square buttons under a source list (+ and −).
private struct SourceListButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.controlText)
            .frame(width: 26, height: 22)
            .background(RoundedRectangle(cornerRadius: 6).fill(configuration.isPressed ? Theme.strip : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.controlBorder))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}
