import SwiftUI

struct PanelRootView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store = Store.shared

    var body: some View {
        Group {
            switch model.screen {
            case .compose: ComposeView(model: model)
            case .presets: PresetPickerView(model: model)
            case .takes: TakesView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
        .tint(Theme.accent)
    }
}

// MARK: - Shared pieces

private struct PanelHeader: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Theme.accent)
                .frame(width: 24, height: 24)
                .overlay(Image(systemName: "text.bubble.fill").font(.system(size: 12)).foregroundStyle(.white))
            (Text("Into ").foregroundStyle(.secondary) + Text(model.appName).fontWeight(.semibold))
                .font(.system(size: 13))
            Spacer()
            KeyHint(keys: ["esc"], label: "close")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

private struct PillButtonStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.accentSoft : Color.primary.opacity(configuration.isPressed ? 0.08 : 0.0)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.accent : Theme.border, lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
    }
}

/// Invisible buttons that carry keyboard shortcuts.
private struct ShortcutButton: View {
    let key: KeyEquivalent
    var modifiers: EventModifiers = .command
    let action: () -> Void

    var body: some View {
        Button("", action: action)
            .keyboardShortcut(key, modifiers: modifiers)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}

// MARK: - Compose

struct ComposeView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(model: model)
            Divider()

            ZStack(alignment: .topLeading) {
                DraftEditor(text: $model.draft, focusToken: model.focusToken,
                            onSubmit: model.generate, onPresets: model.openPicker, onEscape: model.escape)
                if model.draft.isEmpty {
                    Text("Write what you want to say…")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 7)
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 96, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Text([model.sourceLabel, "\(model.wordCount) word\(model.wordCount == 1 ? "" : "s")"].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)

            Divider()
            presetRow
            Divider()
            settingsStrip
            Divider()
            footer
        }
        .background(shortcuts)
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            Button(action: model.openPicker) {
                HStack(spacing: 7) {
                    PresetDot(hex: model.preset.colorHex)
                    Text(model.preset.name).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                }
            }
            .buttonStyle(PillButtonStyle(selected: true))
            if model.autoPicked {
                Text("picked for this app").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.store.presets.filter { $0.id != model.presetID }.prefix(3)) { preset in
                Button(preset.name) { model.choose(preset.id) }
                    .buttonStyle(PillButtonStyle())
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var settingsStrip: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Text("Takes").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize()
                Picker("Takes", selection: $model.takeCount) {
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
            }
            HStack(spacing: 6) {
                Text("Model").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize()
                Picker("Model", selection: $model.modelID) {
                    ForEach(Models.all, id: \.id) { Text($0.label).tag($0.id) }
                }
                .labelsHidden()
                .fixedSize()
            }
            HStack(spacing: 6) {
                Text("Effort").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize()
                Picker("Effort", selection: $model.effort) {
                    ForEach(Models.efforts, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            Spacer(minLength: 0)
            Text(model.isOverridden ? "Changed for this run" : "From the preset")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(-1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.strip)
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 14) {
                KeyHint(keys: ["⇥"], label: "presets")
                KeyHint(keys: ["⌘", "1–9"], label: "jump")
                KeyHint(keys: ["⌘", "K"], label: "more")
            }
            Spacer()
            Button(action: model.generate) {
                HStack(spacing: 8) {
                    Text(model.takeCount == 1 ? "Write 1 take" : "Write \(model.takeCount) takes")
                    Text("↵").opacity(0.8)
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var shortcuts: some View {
        ZStack {
            ForEach(1...9, id: \.self) { number in
                ShortcutButton(key: KeyEquivalent(Character("\(number)"))) { model.choose(number: number) }
            }
            ShortcutButton(key: "k") { model.onMore() }
            ShortcutButton(key: ",") { model.onOpenSettings(.presets, false) }
        }
    }
}

// MARK: - Preset picker

struct PresetPickerView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(spacing: 0) {
            Text(model.draft.isEmpty ? "No draft yet" : model.draft.replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            Divider()

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                KeyTextField(text: Binding(get: { model.filter }, set: { model.filter = $0; model.filterChanged() }),
                             placeholder: "Filter presets…", fontSize: 15, focusToken: model.focusToken,
                             onSubmit: model.chooseHighlighted, onUp: { model.moveHighlight(-1) },
                             onDown: { model.moveHighlight(1) }, onEscape: model.escape)
                HStack(spacing: 4) {
                    Kbd("↑"); Kbd("↓")
                    Text("move ·").font(.caption).foregroundStyle(.secondary)
                    Kbd("↵")
                    Text("choose").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            Divider()

            HStack(spacing: 0) {
                list
                    .frame(width: 370)
                Divider()
                preview
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 2) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    let rows = Array(model.filteredPresets.enumerated())
                    let pickedIDs = Set(model.pickedForApp.map(\.id))
                    let picked = rows.filter { pickedIDs.contains($0.element.id) }
                    let others = rows.filter { !pickedIDs.contains($0.element.id) }
                    if !picked.isEmpty {
                        sectionTitle("Picked for \(model.appName)")
                        ForEach(picked, id: \.element.id) { row($0.element, index: $0.offset) }
                    }
                    if !others.isEmpty {
                        sectionTitle("All presets")
                        ForEach(others, id: \.element.id) { row($0.element, index: $0.offset) }
                    }
                    if rows.isEmpty {
                        Text("No preset matches “\(model.filter)”.")
                            .font(.callout).foregroundStyle(.secondary).padding(12)
                    }
                }
                .padding(10)
            }
            Divider()
            HStack(spacing: 8) {
                Button { model.onOpenSettings(.presets, true) } label: {
                    HStack(spacing: 6) { Text("New preset"); Kbd("⌘N") }.frame(maxWidth: .infinity)
                }
                Button { model.onOpenSettings(.presets, false) } label: {
                    HStack(spacing: 6) { Text("Edit presets"); Kbd("⌘,") }.frame(maxWidth: .infinity)
                }
            }
            .controlSize(.large)
            .padding(10)
        }
        .background(
            ZStack {
                ShortcutButton(key: "n") { model.onOpenSettings(.presets, true) }
                ShortcutButton(key: ",") { model.onOpenSettings(.presets, false) }
                ForEach(1...9, id: \.self) { number in
                    ShortcutButton(key: KeyEquivalent(Character("\(number)"))) { model.choose(number: number) }
                }
            }
        )
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func row(_ preset: Preset, index: Int) -> some View {
        let isHighlighted = model.highlightedPreset?.id == preset.id
        return Button { model.choose(preset.id) } label: {
            HStack(spacing: 10) {
                PresetDot(hex: preset.colorHex)
                Text(preset.name)
                    .font(.system(size: 14, weight: isHighlighted ? .semibold : .regular))
                    .lineLimit(1)
                Spacer()
                if let number = model.shortcutNumber(of: preset) { Kbd("⌘\(number)") }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(isHighlighted ? Theme.accentSoft : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { model.highlighted = index } }
    }

    @ViewBuilder private var preview: some View {
        if let preset = model.highlightedPreset {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preset.name).font(.system(size: 17, weight: .bold))
                        Text(preset.summary).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(preset.instruction).font(.system(size: 14)).foregroundStyle(.primary.opacity(0.85))
                    if !preset.dos.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Do").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.doText)
                            FlowLayout { ForEach(preset.dos, id: \.self) { Chip(text: $0, style: .positive) } }
                        }
                    }
                    if !preset.avoid.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Avoid").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.avoidText)
                            FlowLayout { ForEach(preset.avoid, id: \.self) { Chip(text: $0, style: .negative) } }
                        }
                    }
                    Text(previewFootnote(preset)).font(.caption).foregroundStyle(.secondary)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.strip)
        } else {
            Color.clear
        }
    }

    private func previewFootnote(_ preset: Preset) -> String {
        var parts: [String] = []
        let rules = model.store.settings.voiceRules.filter(\.enabled).count
        if rules > 0 { parts.append("Plus your \(rules) voice rule\(rules == 1 ? "" : "s")") }
        if !preset.examples.isEmpty { parts.append("\(preset.examples.count) example\(preset.examples.count == 1 ? "" : "s") of your voice") }
        if !preset.apps.isEmpty { parts.append("auto-picked in " + preset.apps.map(\.name).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Takes

struct TakesView: View {
    @ObservedObject var model: PanelModel
    @FocusState private var gridFocused: Bool
    @State private var refineFocus = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            (Text("Your draft: ").fontWeight(.semibold).foregroundStyle(.primary) + Text(model.sourceDraft).foregroundStyle(.secondary))
                .font(.system(size: 13))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Theme.strip)
            Divider()

            if let error = model.error {
                VStack(alignment: .leading, spacing: 12) {
                    Text(error).foregroundStyle(Theme.avoidText).textSelection(.enabled)
                    HStack {
                        Button("Try again", action: model.generate)
                        Button("Edit draft") { model.show(.compose) }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: max(1, min(model.cardCount, 3))),
                              spacing: 14) {
                        ForEach(0..<model.cardCount, id: \.self) { index in
                            TakeCard(model: model, index: index)
                                .onTapGesture(count: 2) { model.paste(index) }
                                .onTapGesture { model.select(index); gridFocused = true }
                        }
                    }
                    .padding(18)
                }
                .focusable()
                .focusEffectDisabled()
                .focused($gridFocused)
                .onKeyPress(.leftArrow) { model.moveSelection(-1); return .handled }
                .onKeyPress(.rightArrow) { model.moveSelection(1); return .handled }
                .onKeyPress(.upArrow) { model.moveSelection(-3); return .handled }
                .onKeyPress(.downArrow) { model.moveSelection(3); return .handled }
                .onKeyPress(.return) { model.pasteSelected(); return .handled }
                .onKeyPress(.escape) { model.escape(); return .handled }

                refineBar
            }

            Divider()
            footer
        }
        .background(shortcuts)
        .onAppear { gridFocused = true }
        .onChange(of: model.focusToken) { gridFocused = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                PresetDot(hex: model.preset.colorHex)
                Text(model.preset.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.accentSoft))
            Text("\(model.takeCount) take\(model.takeCount == 1 ? "" : "s") · \(Models.label(model.modelID)) · \(model.effort.capitalized)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Button { model.show(.compose) } label: { HStack(spacing: 6) { Text("Edit draft"); Kbd("⌘E") } }
            Button(action: model.generate) { HStack(spacing: 6) { Text("Regenerate"); Kbd("⌘R") } }
                .disabled(model.running)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var refineBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil").foregroundStyle(.secondary)
            KeyTextField(text: $model.refineText,
                         placeholder: "Refine take \(model.selected + 1): warmer, drop the second ask, add a thanks…",
                         fontSize: 14, focusToken: refineFocus,
                         onSubmit: { model.refine(); gridFocused = true },
                         onEscape: { gridFocused = true })
            Button("More like take \(model.selected + 1)", action: model.moreLikeSelected)
                .disabled(!model.isFinished(model.selected) || model.running)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 14) {
                KeyHint(keys: ["←", "→"], label: "move")
                KeyHint(keys: ["⌘", "C"], label: "copy only")
                KeyHint(keys: ["esc"], label: "back")
            }
            Spacer()
            if model.running {
                TimelineView(.periodic(from: model.startedAt, by: 0.1)) { context in
                    Text(String(format: "Writing… %.1f s", context.date.timeIntervalSince(model.startedAt)))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            } else if !model.timing.isEmpty {
                Text(model.timing).font(.caption).foregroundStyle(.secondary)
            }
            Button(action: model.pasteSelected) {
                HStack(spacing: 8) {
                    Text("Paste take \(model.selected + 1)")
                    Text("↵").opacity(0.8)
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.isFinished(model.selected))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var shortcuts: some View {
        ZStack {
            ForEach(1...5, id: \.self) { number in
                ShortcutButton(key: KeyEquivalent(Character("\(number)"))) { model.paste(number - 1) }
            }
            ShortcutButton(key: "e") { model.show(.compose) }
            ShortcutButton(key: "r") { model.generate() }
            ShortcutButton(key: "c") {
                if model.textSelectionActive() {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                } else {
                    model.copySelected()
                }
            }
        }
    }
}

private struct TakeCard: View {
    @ObservedObject var model: PanelModel
    let index: Int

    var body: some View {
        let isSelected = model.selected == index
        let finished = model.isFinished(index)
        let hasText = index < model.takes.count
        let showChanges = model.changesShown.contains(index) && finished

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(label(isSelected: isSelected, finished: finished, hasText: hasText, showChanges: showChanges))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.accent : .secondary)
                Spacer()
                if index < 5 { Kbd("⌘\(index + 1)") }
            }

            Group {
                if showChanges {
                    Text(WordDiff.attributed(from: model.sourceDraft, to: model.takes[index]))
                } else if hasText {
                    Text(model.takes[index])
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)).frame(height: 11)
                        RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)).frame(width: 140, height: 11)
                    }
                }
            }
            .font(.system(size: 15))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)

            Divider()
            HStack(spacing: 8) {
                Text(finished ? "\(WordCounter.count(model.takes[index])) words" : "writing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if finished {
                    Button("Changes") { model.toggleChanges(index) }
                        .buttonStyle(PillButtonStyle(selected: showChanges))
                        .controlSize(.small)
                    Button { model.onCopy(index, model.takes[index]) } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 11))
                    }
                    .buttonStyle(PillButtonStyle())
                    .accessibilityLabel("Copy take \(index + 1)")
                } else {
                    ProgressView().controlSize(.mini)
                }
            }
            .frame(height: 28)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Theme.accent : Theme.border, lineWidth: isSelected ? 2 : 1))
        .shadow(color: isSelected ? Theme.accent.opacity(0.15) : .clear, radius: 8, y: 3)
        .contentShape(Rectangle())
    }

    private func label(isSelected: Bool, finished: Bool, hasText: Bool, showChanges: Bool) -> String {
        let base = "Take \(index + 1)"
        if !finished { return "\(base) · writing…" }
        if showChanges { return "\(base) · showing changes" }
        return isSelected ? "\(base) · selected" : base
    }
}
