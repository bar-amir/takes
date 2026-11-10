import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Presets: the source list on the left (with add, remove and Browse… under it), the preset as a grouped
/// form in the middle, and "Try it" on the right.
struct PresetsTab: View {
    @ObservedObject var state: SettingsState
    @ObservedObject var store = Store.shared

    var body: some View {
        VStack(spacing: 0) {
            SetAsideBanner(store: store)
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
                Text(preset.name.isEmpty ? String(localized: "Untitled") : preset.name)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.onAccent : Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if index < 9 {
                    Text(verbatim: "\u{200E}⌘\(index + 1)").font(.system(size: 11))
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
        copy.name = String(localized: "\(copy.name) copy")
        copy.hotKey = nil
        copy.apps = []
        let index = (store.index(of: preset.id) ?? store.presets.count - 1) + 1
        store.presets.insert(copy, at: index)
        state.selectedPresetID = copy.id
    }

    private func delete(_ preset: Preset) {
        guard store.presets.count > 1 else { return }
        guard confirmDestructive(String(localized: "Delete “\(preset.name)”?"), message: String(localized: "You can't undo this."),
                                 button: String(localized: "Delete")) else { return }
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
        let result = PresetImport.importFiles(panel.urls, into: store)
        if let id = result.lastID { state.selectedPresetID = id }
        let alert = NSAlert()
        alert.messageText = result.summary.title
        alert.informativeText = result.summary.message
        alert.alertStyle = result.summary.imported > 0 ? .informational : .warning
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }
}

/// What a preset file turned into: the presets kept (checked, see `PresetImport.checked`), and what was left out or changed.
struct PresetImportResult {
    var presets: [Preset] = []
    /// What changed in each preset, in words, by name.
    var changes: [(name: String, notes: [String])] = []
    /// Presets in the file that couldn't be read.
    var skipped = 0
    /// Presets beyond `PresetImport.maxPresets`, left out.
    var leftOut = 0
    /// Nothing in the file could be read as a preset.
    var unreadable = false
    /// A removed hotkey, app binding or paste-right-away setting, which the summary explains how to set again.
    var removedBindings = false
}

/// Reading a preset file someone else wrote: it comes from outside, so what it asks for is checked first.
enum PresetImport {
    /// A preset file is a few kilobytes; a bigger one isn't one.
    static let maxFileSize = 1_000_000
    /// One file adds at most this many presets.
    static let maxPresets = 50
    /// Every example is sent with every run, so a pasted-in essay isn't kept whole.
    static let maxExampleLength = 2000
    /// The same goes for the rest of what a preset says: its name, instruction and Do and Avoid rules.
    static let maxNameLength = 80
    static let maxInstructionLength = 4000
    static let maxRules = 20
    static let maxRuleLength = 200

    struct FileReport {
        var file: String
        var result: PresetImportResult
    }

    /// Reads each file and adds what it holds to the store in one go (so the presets are saved once), and says what
    /// happened. `lastID` is the preset to select.
    static func importFiles(_ urls: [URL], into store: Store) -> (summary: (title: String, message: String, imported: Int), lastID: String?) {
        let settings = store.settings
        var reports: [FileReport] = []
        var added: [Preset] = []
        for url in urls {
            let result = read(url, defaultModel: settings.defaultModel, defaultEffort: settings.defaultEffort)
            added += result.presets
            reports.append(FileReport(file: url.lastPathComponent, result: result))
        }
        if !added.isEmpty { store.presets += added }
        return (summary(reports), added.last?.id)
    }

    static func read(_ url: URL, defaultModel: String, defaultEffort: String) -> PresetImportResult {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= maxFileSize, let data = try? Data(contentsOf: url) else { return PresetImportResult(unreadable: true) }
        return read(data, defaultModel: defaultModel, defaultEffort: defaultEffort)
    }

    /// A file holds a list of presets (an export) or one preset. A preset that can't be read is skipped, and a value
    /// in one that can't be read is reset and reported.
    static func read(_ data: Data, defaultModel: String, defaultEffort: String) -> PresetImportResult {
        var result = PresetImportResult()
        var found: [Preset] = []
        var resets: [[String]] = []
        let listProblems = DecodeProblems()
        let listDecoder = JSONDecoder()
        listDecoder.userInfo[.decodeProblems] = listProblems
        let oneProblems = DecodeProblems()
        let oneDecoder = JSONDecoder()
        oneDecoder.userInfo[.decodeProblems] = oneProblems
        if let list = try? listDecoder.decode(LossyList<Preset>.self, from: data) {
            found = list.elements
            resets = list.resets
            result.skipped = list.skipped
        } else if let one = try? oneDecoder.decode(Preset.self, from: data) {
            found = [one]
            resets = [oneProblems.keys]
        } else {
            result.unreadable = true
        }
        if found.count > maxPresets {
            result.leftOut = found.count - maxPresets
            found = Array(found.prefix(maxPresets))
        }
        for (index, imported) in found.enumerated() {
            let (preset, checkedNotes, removed) = checked(imported, defaultModel: defaultModel, defaultEffort: defaultEffort)
            var notes = checkedNotes
            let reset = resets[index].reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            if !reset.isEmpty {
                let keys = reset.joined(separator: ", ")
                notes.insert(String(localized: "couldn't read \(keys), which were reset"), at: 0)
            }
            result.presets.append(preset)
            if !notes.isEmpty { result.changes.append((preset.name.isEmpty ? String(localized: "Untitled") : preset.name, notes)) }
            if removed { result.removedBindings = true }
        }
        return result
    }

    /// The preset as it may come in: a new id, takes inside what the picker offers, a model and effort this version has,
    /// a few short examples, and nothing that acts without the user seeing it. A file can't bring a hotkey, apps that pick
    /// the preset automatically, or paste-right-away; the user sets those in the preset. Returns what it changed, in words.
    static func checked(_ imported: Preset, defaultModel: String, defaultEffort: String) -> (preset: Preset, notes: [String], removedBindings: Bool) {
        var preset = imported
        var notes: [String] = []
        var removed = false
        preset.id = UUID().uuidString

        if preset.hotKey != nil {
            preset.hotKey = nil
            notes.append(String(localized: "hotkey removed"))
            removed = true
        }
        if !preset.apps.isEmpty {
            let names = preset.apps.map(\.name).joined(separator: ", ")
            notes.append(String(localized: "app bindings removed (\(names))"))
            preset.apps = []
            removed = true
        }
        if preset.instantMode == true {
            notes.append(String(localized: "“Write and paste right away” turned off"))
            removed = true
        }
        preset.instantMode = nil

        let takes = min(max(preset.takes, Preset.takesRange.lowerBound), Preset.takesRange.upperBound)
        if takes != preset.takes {
            notes.append(String(localized: "takes set to \(takes) (was \(preset.takes))"))
            preset.takes = takes
        }
        if !Models.all.contains(where: { $0.id == preset.model }) {
            let model = Models.all.contains { $0.id == defaultModel } ? defaultModel : Models.sonnet
            notes.append(String(localized: "model set to \(Models.label(model))"))
            preset.model = model
        }
        if !Models.efforts.contains(preset.effort) {
            let effort = Models.efforts.contains(defaultEffort) ? defaultEffort : "low"
            notes.append(String(localized: "effort set to \(Models.effortLabel(effort))"))
            preset.effort = effort
        }

        var examples = preset.examples
        if examples.count > Preset.maxExamples {
            notes.append(String(localized: "examples cut to \(Preset.maxExamples) (had \(examples.count))"))
            examples = Array(examples.prefix(Preset.maxExamples))
        }
        if examples.contains(where: { $0.count > maxExampleLength }) {
            notes.append(String(localized: "long examples shortened"))
            examples = examples.map { String($0.prefix(maxExampleLength)) }
        }
        preset.examples = examples

        if preset.name.count > maxNameLength {
            preset.name = String(preset.name.prefix(maxNameLength))
            notes.append(String(localized: "name shortened"))
        }
        if preset.instruction.count > maxInstructionLength {
            preset.instruction = String(preset.instruction.prefix(maxInstructionLength))
            notes.append(String(localized: "instruction shortened"))
        }
        let dos = limited(preset.dos)
        if dos.cutRules { notes.append(String(localized: "extra Do rules left out")) }
        if dos.shortened { notes.append(String(localized: "long Do rules shortened")) }
        preset.dos = dos.rules
        let avoid = limited(preset.avoid)
        if avoid.cutRules { notes.append(String(localized: "extra Avoid rules left out")) }
        if avoid.shortened { notes.append(String(localized: "long Avoid rules shortened")) }
        preset.avoid = avoid.rules
        return (preset, notes, removed)
    }

    private static func limited(_ rules: [String]) -> (rules: [String], cutRules: Bool, shortened: Bool) {
        let kept = Array(rules.prefix(maxRules))
        let shortened = kept.contains { $0.count > maxRuleLength }
        return (kept.map { String($0.prefix(maxRuleLength)) }, rules.count > maxRules, shortened)
    }

    /// The alert after an import: what was added, what was changed and what couldn't be read.
    static func summary(_ reports: [FileReport]) -> (title: String, message: String, imported: Int) {
        let imported = reports.reduce(0) { $0 + $1.result.presets.count }
        let title: String
        if imported == 0 {
            title = String(localized: "No presets imported")
        } else if imported == 1 {
            title = String(localized: "Imported 1 preset")
        } else {
            title = String(localized: "Imported \(imported) presets")
        }
        var lines: [String] = []
        for report in reports {
            let result = report.result
            if result.unreadable {
                lines.append(String(localized: "“\(report.file)” isn't a preset file Takes can read."))
            } else if result.presets.isEmpty && result.skipped == 0 {
                lines.append(String(localized: "“\(report.file)” has no presets."))
            }
            if result.leftOut > 0 {
                let total = result.presets.count + result.leftOut
                lines.append(String(localized: "“\(report.file)”: only the first \(maxPresets) of \(total) presets were imported."))
            }
            if result.skipped == 1 {
                lines.append(String(localized: "“\(report.file)”: 1 preset couldn't be read and was skipped."))
            } else if result.skipped > 1 {
                lines.append(String(localized: "“\(report.file)”: \(result.skipped) presets couldn't be read and were skipped."))
            }
        }
        let changes = reports.flatMap(\.result.changes)
        let shown = 6
        lines += changes.prefix(shown).map { "“\($0.name)”: \($0.notes.joined(separator: ", "))." }
        if changes.count > shown { lines.append(String(localized: "And \(changes.count - shown) more were adjusted.")) }
        if reports.contains(where: \.result.removedBindings) {
            lines.append(String(localized: "A file can't bring a hotkey, apps or “Write and paste right away”. Set them in the preset."))
        }
        return (title, lines.joined(separator: "\n"), imported)
    }
}

/// Shown at the top of Presets and History while a file Takes set aside at launch hasn't been dismissed:
/// what happened and where the original is.
struct SetAsideBanner: View {
    @ObservedObject var store: Store
    /// A card (in a page) rather than a strip across the window.
    var rounded = false

    var body: some View {
        if !store.setAside.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13)).foregroundStyle(Theme.avoidText)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(store.setAside) { file in
                            Text(file.message).font(.system(size: 13)).foregroundStyle(Theme.controlText)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Button("Show in Finder") { store.revealSetAside() }.buttonStyle(SecondaryButtonStyle(height: 28)).fixedSize()
                    if store.canDismissSetAside {
                        Button("Dismiss") { store.dismissSetAside() }.buttonStyle(SecondaryButtonStyle(height: 28)).fixedSize()
                    }
                }
                .padding(.leading, 27)
            }
            .padding(.horizontal, rounded ? 14 : 28)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.avoidFill)
            .clipShape(RoundedRectangle(cornerRadius: rounded ? 10 : 0))
            .accessibilityElement(children: .contain)
        }
    }
}

private struct PresetEditor: View {
    @Binding var preset: Preset
    @ObservedObject var monitor = SetupMonitor.shared
    @State private var suggestions: [KeyCombo] = []

    /// Who else has this preset's hotkey: the Open Takes hotkey, another preset, macOS or another app.
    private var hotKeyNote: String? {
        guard let combo = preset.hotKey else { return nil }
        let store = Store.shared
        if combo == store.settings.summonHotKey { return String(localized: "This is the Open Takes hotkey too; only one of them can fire.") }
        if let other = store.presets.first(where: { $0.id != preset.id && $0.hotKey == combo }) { return String(localized: "Also the hotkey of “\(other.name)”.") }
        if monitor.takenHotKeys.contains(combo) { return String(localized: "Also used by \(HotKeyChoice.owner(of: combo)). Pick another.") }
        return nil
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    FormSection(String(localized: "Preset")) {
                        FormRow(String(localized: "Name")) {
                            StyledTextField(placeholder: String(localized: "Name"), text: $preset.name, height: 28).frame(width: 240)
                        }
                        FormDivider()
                        FormRow(String(localized: "Color")) { colors }
                        FormDivider()
                        FormRow(String(localized: "Own hotkey"), detail: hotKeyNote) { HotKeyRecorder(combo: $preset.hotKey, height: 28) }
                        if preset.hotKey == nil || hotKeyNote != nil, !suggestions.isEmpty {
                            HotKeySuggestionChips(suggestions: suggestions) { preset.hotKey = $0 }
                                .formRowPadding()
                        }
                        FormDivider()
                        FormRow(String(localized: "Picked automatically in")) {
                            AppsEditor(apps: $preset.apps).frame(maxWidth: 280, alignment: .trailing)
                        }
                    }

                    FormSection(String(localized: "Instruction")) {
                        TextEditor(text: $preset.instruction)
                            .font(.system(size: 13))
                            .lineSpacing(3)
                            .scrollContentBackground(.hidden)
                            .frame(height: 78)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 8)
                            .accessibilityLabel("Instruction")
                    }

                    FormSection(String(localized: "Do", comment: "Things a preset should do")) {
                        ChipsEditor(items: $preset.dos, style: .positive).padding(10)
                    }
                    FormSection(String(localized: "Avoid", comment: "Things a preset should avoid")) {
                        ChipsEditor(items: $preset.avoid, style: .negative).padding(10)
                    }

                    ExamplesEditor(examples: $preset.examples)

                    FormSection(header: String(localized: "Run", comment: "Preset run settings")) {
                        FormRow(String(localized: "Takes · Model · Effort")) {
                            HStack(spacing: 6) {
                                MenuPicker(options: Preset.takesRange.map { (value: $0, title: "\($0)") }, selection: $preset.takes)
                                MenuPicker(options: Models.all.map { (value: $0.id, title: $0.label) }, selection: $preset.model)
                                MenuPicker(options: Models.efforts.map { (value: $0, title: Models.effortLabel($0)) }, selection: $preset.effort)
                            }
                        }
                        FormDivider()
                        FormRow(String(localized: "Length")) {
                            MenuPicker(options: TakeLength.allCases.map { (value: $0, title: $0.label) }, selection: $preset.length)
                        }
                        FormDivider()
                        FormRow(String(localized: "Reply language")) {
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
        .onAppear(perform: refreshSuggestions)
        .onChange(of: preset.id) { _, _ in refreshSuggestions() }
        .onChange(of: preset.hotKey) { _, _ in refreshSuggestions() }
        .onChange(of: monitor.takenHotKeys) { _, _ in refreshSuggestions() }
    }

    /// Free hotkeys for this preset: not the Open Takes hotkey, another preset's, or one macOS or an app has.
    private func refreshSuggestions() {
        let store = Store.shared
        let taken = [store.settings.summonHotKey] + monitor.takenHotKeys
            + store.presets.filter { $0.id != preset.id }.compactMap(\.hotKey)
        suggestions = HotKeyChoice.suggestions(from: HotKeyChoice.presetCandidates, current: preset.hotKey, taken: taken)
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
        FormSection(header: String(localized: "Write like me")) {
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
        menu.addItem(ClosureMenuItem(title: String(localized: "Choose from Applications…"), handler: chooseApp))
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
    @State private var retry: EngineRetry?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                FormSection(String(localized: "Try it")) {
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
                    Text(running ? retry.map { "\($0.label)…" } ?? String(localized: "Writing…") : String(localized: "Run with these settings")).lineLimit(1).frame(maxWidth: .infinity)
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
        var request = EngineRequest(
            system: PromptBuilder.system(preset: preset, takes: preset.takes, rules: store.settings.voiceRules),
            user: PromptBuilder.user(draft: sample, mode: .fresh, takes: preset.takes),
            takes: preset.takes, model: preset.model, effort: preset.effort)
        request.onRetry = { retry in Task { @MainActor in if running { self.retry = retry } } }
        let engine = Engines.current(store.settings)
        running = true
        retry = nil
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
