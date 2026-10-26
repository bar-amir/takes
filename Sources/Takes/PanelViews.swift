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
        .foregroundStyle(Theme.text)
        .background(Theme.surface)
        .tint(Theme.accent)
    }
}

// MARK: - Shared pieces

private struct Rule: View {
    var body: some View { Rectangle().fill(Theme.border).frame(height: 1) }
}

private struct PanelHeader: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        HStack(spacing: 10) {
            AppGlyph()
            (Text("Into ").foregroundStyle(Theme.secondaryText) + Text(model.appName).fontWeight(.semibold).foregroundStyle(Theme.text))
                .font(.system(size: 13))
            Spacer()
            KeyHint(keys: ["esc"], label: "close")
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
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

private struct StripLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 13)).foregroundStyle(Theme.secondaryText).fixedSize() }
}

// MARK: - Compose

struct ComposeView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(model: model)
            Rule()

            ZStack(alignment: .topLeading) {
                DraftEditor(text: $model.draft, focusToken: model.focusToken,
                            onSubmit: model.generate, onPresets: model.openPicker, onEscape: model.escape)
                if model.draft.isEmpty {
                    Text("Write what you want to say…")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.leading, 7)
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 96, maxHeight: .infinity)
            .padding(.horizontal, 15)
            .padding(.top, 14)

            Text([model.sourceLabel, "\(model.wordCount) word\(model.wordCount == 1 ? "" : "s")"].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 14)

            Rule()
            presetRow
            Rule()
            settingsStrip
            Rule()
            footer
        }
        .background(shortcuts)
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            Button(action: model.openPicker) {
                HStack(spacing: 8) {
                    PresetDot(hex: model.preset.colorHex)
                    Text(model.preset.name).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                }
            }
            .buttonStyle(PillButtonStyle(selected: true))
            .fixedSize()
            if model.autoPicked {
                Text("picked for this app").font(.system(size: 12)).foregroundStyle(Theme.secondaryText).fixedSize().padding(.trailing, 4)
            }
            ForEach(model.store.presets.filter { $0.id != model.presetID }.prefix(3)) { preset in
                Button(preset.name) { model.choose(preset.id) }
                    .buttonStyle(PillButtonStyle())
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var settingsStrip: some View {
        HStack(spacing: 18) {
            HStack(spacing: 8) {
                StripLabel("Takes")
                NumberSegments(selection: $model.takeCount)
            }
            HStack(spacing: 8) {
                StripLabel("Model")
                MenuPicker(options: Models.all.map { (value: $0.id, title: $0.label) }, selection: $model.modelID)
            }
            HStack(spacing: 8) {
                StripLabel("Effort")
                MenuPicker(options: Models.efforts.map { (value: $0, title: $0.capitalized) }, selection: $model.effort)
            }
            Spacer(minLength: 0)
            Text(model.isOverridden ? "Changed for this run" : "From the preset")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .layoutPriority(-1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
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
                    Text("↵").font(.system(size: 12)).opacity(0.85)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 18)
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
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .frame(height: 52)
            Rule()

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.secondaryText)
                KeyTextField(text: Binding(get: { model.filter }, set: { model.filter = $0; model.filterChanged() }),
                             placeholder: "Filter presets…", fontSize: 15, focusToken: model.focusToken,
                             onSubmit: model.chooseHighlighted, onUp: { model.moveHighlight(-1) },
                             onDown: { model.moveHighlight(1) }, onEscape: model.escape)
                HStack(spacing: 3) {
                    Kbd("↑"); Kbd("↓")
                    Text("move ·").font(.system(size: 12)).foregroundStyle(Theme.secondaryText).padding(.horizontal, 2)
                    Kbd("↵")
                    Text("choose").font(.system(size: 12)).foregroundStyle(Theme.secondaryText).padding(.leading, 2)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 46)
            Rule()

            HStack(spacing: 0) {
                list.frame(width: 380)
                Rectangle().fill(Theme.border).frame(width: 1)
                preview
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                            .font(.system(size: 14)).foregroundStyle(Theme.secondaryText).padding(12)
                    }
                }
                .padding(10)
            }
            Rule()
            HStack(spacing: 8) {
                Button { model.onOpenSettings(.presets, true) } label: {
                    HStack(spacing: 6) { Text("New preset"); Kbd("⌘N") }.frame(maxWidth: .infinity)
                }
                Button { model.onOpenSettings(.presets, false) } label: {
                    HStack(spacing: 6) { Text("Edit presets"); Kbd("⌘,") }.frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(SecondaryButtonStyle(height: 34))
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
            .tracking(0.5)
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private func row(_ preset: Preset, index: Int) -> some View {
        let isHighlighted = model.highlightedPreset?.id == preset.id
        return Button { model.choose(preset.id) } label: {
            HStack(spacing: 10) {
                PresetDot(hex: preset.colorHex)
                Text(preset.name)
                    .font(.system(size: 14, weight: isHighlighted ? .semibold : .regular))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer()
                if let number = model.shortcutNumber(of: preset) { Kbd("⌘\(number)") }
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
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
                        Text(preset.summary).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                    }
                    Text(preset.instruction).font(.system(size: 14)).foregroundStyle(Theme.controlText).lineSpacing(3)
                    if !preset.dos.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Do").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.doText)
                            FlowLayout { ForEach(preset.dos, id: \.self) { Chip(text: $0, style: .positive) } }
                        }
                    }
                    if !preset.avoid.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Avoid").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.avoidText)
                            FlowLayout { ForEach(preset.avoid, id: \.self) { Chip(text: $0, style: .negative) } }
                        }
                    }
                    Text(previewFootnote(preset)).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.strip)
        } else {
            Theme.strip
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
            Rule()
            (Text("Your draft: ").fontWeight(.semibold).foregroundStyle(Theme.controlText) + Text(model.sourceDraft).foregroundStyle(Theme.secondaryText))
                .font(.system(size: 13))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Theme.strip)
            Rule()

            if let error = model.error {
                VStack(alignment: .leading, spacing: 12) {
                    Text(error).font(.system(size: 14)).foregroundStyle(Theme.avoidText).textSelection(.enabled)
                    HStack {
                        Button("Try again", action: model.generate).buttonStyle(PrimaryButtonStyle())
                        Button("Edit draft") { model.show(.compose) }.buttonStyle(SecondaryButtonStyle(height: 36))
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
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
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

            Rule()
            footer
        }
        .background(shortcuts)
        .onAppear { gridFocused = true }
        .onChange(of: model.focusToken) { gridFocused = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                PresetDot(hex: model.preset.colorHex)
                Text(model.preset.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.accentSoft))
            Text("\(model.takeCount) take\(model.takeCount == 1 ? "" : "s") · \(Models.label(model.modelID)) · \(model.effort.capitalized)")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Button { model.show(.compose) } label: { HStack(spacing: 6) { Text("Edit draft"); Kbd("⌘E") } }
                .buttonStyle(SecondaryButtonStyle())
            Button(action: model.generate) { HStack(spacing: 6) { Text("Regenerate"); Kbd("⌘R") } }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.running)
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
    }

    private var refineBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.secondaryText)
            KeyTextField(text: $model.refineText,
                         placeholder: "Refine take \(model.selected + 1): warmer, drop the second ask, add a thanks…",
                         fontSize: 14, focusToken: refineFocus,
                         onSubmit: { model.refine(); gridFocused = true },
                         onEscape: { gridFocused = true })
            Button("More like take \(model.selected + 1)", action: model.moreLikeSelected)
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!model.isFinished(model.selected) || model.running)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.controlBorder))
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            HStack(spacing: 14) {
                KeyHint(keys: ["←", "→"], label: "move")
                KeyHint(keys: ["⌘", "C"], label: "copy only")
                KeyHint(keys: ["esc"], label: "back")
            }
            Spacer()
            if model.running {
                TimelineView(.periodic(from: model.startedAt, by: 0.1)) { context in
                    Text(String(format: "Writing… %.1f s", context.date.timeIntervalSince(model.startedAt)))
                        .font(.system(size: 12)).foregroundStyle(Theme.secondaryText).monospacedDigit()
                }
            } else if !model.timing.isEmpty {
                Text(model.timing).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            }
            Button(action: model.pasteSelected) {
                HStack(spacing: 8) {
                    Text("Paste take \(model.selected + 1)")
                    Text("↵").font(.system(size: 12)).opacity(0.85)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!model.isFinished(model.selected))
        }
        .padding(.horizontal, 20)
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
                Text(label(isSelected: isSelected, finished: finished, showChanges: showChanges))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.secondaryText)
                Spacer()
                if index < 5 { Kbd("⌘\(index + 1)") }
            }

            Group {
                if showChanges {
                    Text(WordDiff.attributed(from: model.sourceDraft, to: model.takes[index]))
                } else if hasText {
                    Text(model.takes[index])
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 6).fill(Theme.border).frame(height: 12)
                        RoundedRectangle(cornerRadius: 6).fill(Theme.border).frame(width: 120, height: 12)
                    }
                    .padding(.top, 4)
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(Theme.text)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)

            Rule()
            HStack(spacing: 8) {
                Text(finished ? "\(WordCounter.count(model.takes[index])) words" : "writing")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                if finished {
                    Button("Changes") { model.toggleChanges(index) }
                        .buttonStyle(ToggleChipStyle(on: showChanges))
                        .accessibilityAddTraits(showChanges ? .isSelected : [])
                    Button { model.onCopy(index, model.takes[index]) } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(SecondaryButtonStyle(height: 28))
                    .accessibilityLabel("Copy take \(index + 1)")
                } else {
                    ProgressView().controlSize(.mini)
                }
            }
            .frame(height: 28)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Theme.accent : Theme.border, lineWidth: isSelected ? 2 : 1))
        .shadow(color: isSelected ? Theme.accent.opacity(0.14) : .clear, radius: 10, y: 4)
        .contentShape(Rectangle())
    }

    private func label(isSelected: Bool, finished: Bool, showChanges: Bool) -> String {
        let base = "Take \(index + 1)"
        if !finished { return "\(base) · writing…" }
        if showChanges { return "\(base) · showing changes" }
        return isSelected ? "\(base) · selected" : base
    }
}

/// The small "Changes" toggle: dark when on, as in the mockup.
private struct ToggleChipStyle: ButtonStyle {
    let on: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(on ? Theme.surface : Theme.controlText)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? Theme.controlText : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? Theme.controlText : Theme.controlBorder))
            .contentShape(Rectangle())
    }
}
