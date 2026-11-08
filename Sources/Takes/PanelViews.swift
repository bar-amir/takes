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
        // The panel is a titled window with its title bar hidden: draw from the very top, as the snapshots do,
        // or the reserved title-bar height pushes everything down and clips the bottom row.
        .ignoresSafeArea(.container, edges: .top)
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
        HStack(spacing: Spacing.inner) {
            AppGlyph(appURL: model.appURL)
            Text("Into \(Text(model.displayAppName).fontWeight(.semibold).foregroundStyle(Theme.text))").foregroundStyle(Theme.secondaryText)
                .font(.system(size: 13))
            Spacer()
            KeyHint(keys: ["esc"], label: String(localized: "close", comment: "Key hint: esc closes the panel"))
        }
        .frame(height: Spacing.control)
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, Spacing.bar)
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

/// A quiet text button with its shortcut ("Dictate ⌘D"): secondary text that darkens on hover.
struct QuietButtonStyle: ButtonStyle {
    var size: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        QuietLabel(configuration: configuration, size: size)
    }

    private struct QuietLabel: View {
        let configuration: Configuration
        let size: CGFloat
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: size))
                .foregroundStyle(hovering || configuration.isPressed ? Theme.text : Theme.secondaryText)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

// MARK: - Compose

struct ComposeView: View {
    @ObservedObject var model: PanelModel

    /// The compose panel's height without reply context: header, draft, status line, presets row and footer.
    static let height: CGFloat = 320
    /// The presets row: 32 pt controls with 12 pt above and below.
    static let rowHeight: CGFloat = Spacing.control + 2 * Spacing.inner
    static let footerHeight: CGFloat = Spacing.control + 2 * Spacing.bar

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(model: model)
            Rule()
            ReplyContextBar(model: model)

            ZStack(alignment: .topLeading) {
                DraftEditor(text: $model.draft, focusToken: model.focusToken,
                            onSubmit: model.submitDraft, onPresets: model.openPicker, onEscape: model.escape,
                            caret: model.draftCaret, onSelection: { model.draftSelection = $0 },
                            onType: model.dictation.userTyped)
                if model.draft.isEmpty {
                    Text("Write what you want to say…")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.leading, 7)
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                }
            }
            // 62 (about three lines) leaves room for a two-line dictation note on the fixed-height compose screen.
            .frame(minHeight: 62, maxHeight: .infinity)
            // The text view insets its text by 7 pt (container inset 2 + line padding 5), so text starts on the gutter.
            .padding(.horizontal, Spacing.gutter - 7)
            .padding(.top, Spacing.inner)

            ComposeStatusRow(model: model, dictation: model.dictation)
                .padding(.horizontal, Spacing.gutter)
                .padding(.top, Spacing.item)
                .padding(.bottom, Spacing.inner)
            ToneReadSection(model: model)

            Rule()
            presetRow
            Rule()
            footer
        }
        .background(shortcuts)
        .overlay(alignment: .bottomTrailing) { optionsPopover }
    }

    /// One row that never wraps: the chosen preset, the next most used by name, "+N ⇥", and the run options chip.
    private var presetRow: some View {
        HStack(spacing: Spacing.item) {
            ViewThatFits(in: .horizontal) {
                presets(limit: PresetRow.named)
                presets(limit: 2)
                presets(limit: 1)
            }
            Spacer(minLength: Spacing.item)
            RunOptionsChip(model: model)
        }
        .frame(height: Spacing.control)
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, Spacing.inner)
    }

    private func presets(limit: Int) -> some View {
        let layout = model.presetRow(limit: limit)
        return HStack(spacing: 6) {
            ForEach(layout.shown, id: \.self) { id in
                if let preset = model.store.preset(id: id) {
                    if id == model.presetID {
                        Button(action: model.openPicker) {
                            HStack(spacing: Spacing.item) {
                                PresetDot(hex: preset.colorHex)
                                Text(preset.name).lineLimit(1)
                            }
                        }
                        .buttonStyle(PillButtonStyle(selected: true, height: 30))
                        .help(model.autoPicked ? "Picked for \(model.displayAppName). Tab shows every preset." : "Tab shows every preset.")
                        .accessibilityLabel("Preset: \(preset.name)")
                        .accessibilityHint("Opens the preset list. Tab.")
                    } else {
                        Button(preset.name) { model.choose(preset.id) }
                            .buttonStyle(PillButtonStyle(height: 30))
                            .lineLimit(1)
                            .help(model.shortcutNumber(of: preset).map { "⌘\($0)" } ?? preset.name)
                    }
                }
            }
            if layout.overflow > 0 {
                Button(action: model.openPicker) {
                    HStack(spacing: 4) { Text(verbatim: "\u{200E}+\(layout.overflow.formatted())"); Kbd("⇥") }
                        .environment(\.layoutDirection, .leftToRight)
                        .padding(.horizontal, 6)
                        .frame(height: 30)
                }
                .buttonStyle(QuietButtonStyle(size: 13))
                .accessibilityLabel("\(layout.overflow) more presets")
                .accessibilityHint("Opens the preset list. Tab.")
            }
        }
        .fixedSize()
    }

    @ViewBuilder private var optionsPopover: some View {
        if model.optionsOpen {
            ZStack(alignment: .bottomTrailing) {
                // A click anywhere else closes it, like a popover.
                Color.clear.contentShape(Rectangle()).onTapGesture { withAnimation(Motion.animation()) { model.optionsOpen = false } }
                RunOptionsPopover(model: model)
                    .padding(.trailing, Spacing.gutter - 4)
                    .padding(.bottom, Self.footerHeight + 1 + Self.rowHeight - Spacing.inner + 6)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: Spacing.section) {
                KeyHint(keys: ["⇥"], label: String(localized: "presets", comment: "Key hint: Tab opens the preset list"))
                Button { toggleOptions() } label: { KeyHint(keys: ["⌘", "K"], label: String(localized: "options", comment: "Key hint: ⌘K opens the run options")) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Run options")
                ToneReadHint(model: model)
            }
            Spacer()
            Button(action: model.generate) {
                HStack(spacing: Spacing.item) {
                    Text(model.takeCount == 1 ? "Write 1 take" : "Write \(model.takeCount) takes")
                    Text("↵").font(.system(size: 12)).opacity(0.85)
                }
            }
            .buttonStyle(PrimaryButtonStyle(height: Spacing.control))
            .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, Spacing.bar)
    }

    private func toggleOptions() {
        withAnimation(Motion.animation(.easeOut(duration: Motion.quick))) { model.optionsOpen.toggle() }
    }

    private var shortcuts: some View {
        ZStack {
            ForEach(1...9, id: \.self) { number in
                ShortcutButton(key: KeyEquivalent(Character("\(number)"))) { model.choose(number: number) }
            }
            ShortcutButton(key: "k") { toggleOptions() }
            ShortcutButton(key: ",") { model.onOpenSettings(.presets, false) }
            ReplyContextShortcuts(model: model)
            ShortcutButton(key: "d") { model.toggleDictation() }
        }
    }
}

/// The line under the draft: where it came from and its length, then the quiet "Replying to" and "Dictate"
/// buttons. While dictating, or when dictation has something to say, its own row takes over.
private struct ComposeStatusRow: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var dictation: Dictation

    var body: some View {
        if case .idle = dictation.state {
            HStack(spacing: Spacing.section) {
                let words = model.wordCount == 1 ? String(localized: "1 word") : String(localized: "\(model.wordCount) words")
                Text([model.sourceLabel, words].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                ReplyContextAddButton(model: model)
                Button(action: model.toggleDictation) {
                    HStack(spacing: 5) { Text("Dictate"); Kbd("⌘D") }
                }
                .buttonStyle(QuietButtonStyle())
                .fixedSize()
                .accessibilityLabel("Dictate")
                .accessibilityHint("Command D. Speak your draft. Speech is turned into text on this Mac.")
            }
            .frame(height: 22)
        } else {
            DictationRow(dictation: dictation, onToggle: model.toggleDictation) { EmptyView() } trailing: { EmptyView() }
        }
    }
}

/// "3 · Sonnet 5.5 · Low ⌄" at the end of the presets row. Quiet while it matches the preset; Ink once changed.
private struct RunOptionsChip: View {
    @ObservedObject var model: PanelModel
    @State private var hovering = false

    var body: some View {
        let changed = model.isOverridden
        Button {
            withAnimation(Motion.animation(.easeOut(duration: Motion.quick))) { model.optionsOpen.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(model.runOptionsLabel).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 12.5, weight: changed ? .semibold : .regular))
            .foregroundStyle(changed ? Theme.onAccent : (hovering ? Theme.text : Theme.controlText))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(changed ? Theme.accent : (hovering || model.optionsOpen ? Theme.kbdFill : Theme.strip)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
        .help(changed ? "Changed for this run. ⌘K" : "Takes, model and effort, from the preset. ⌘K")
        .accessibilityLabel(changed ? Text("Run options: \(model.runLabel), changed for this run") : Text("Run options: \(model.runLabel)"))
        .accessibilityHint("Command K")
    }
}

/// The run options, opened from the chip or ⌘K: the same controls the panel always had.
private struct RunOptionsPopover: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.item) {
            row(String(localized: "Takes", comment: "Run options: number of takes")) {
                NumberSegments(selection: $model.takeCount)
                Spacer(minLength: Spacing.item)
                // Changed values show on the chip in Ink; this puts them back.
                if model.isOverridden {
                    Button("Reset") { model.resetRunOptions() }.buttonStyle(QuietButtonStyle()).fixedSize()
                        .help("Back to the preset's takes, model and effort")
                } else {
                    Button("Defaults…") { model.onOpenSettings(.engine, false) }.buttonStyle(QuietButtonStyle()).fixedSize()
                        .help("Settings for new presets")
                }
            }
            row(String(localized: "Model")) { MenuPicker(options: model.modelOptions, selection: $model.modelID) }
            if !model.usesOneModel {
                row(String(localized: "Effort")) {
                    MenuPicker(options: Models.efforts.map { (value: $0, title: Models.effortLabel($0)) }, selection: $model.effort)
                }
            }
            if model.store.settings.engine == .chatGPT {
                // OpenAI's Sign in with ChatGPT guidelines: say the plan is in use next to the model, with a way to manage it.
                row(String(localized: "Plan", comment: "Run options: the ChatGPT plan in use")) {
                    Text("Your ChatGPT plan").font(.system(size: 13)).foregroundStyle(Theme.controlText)
                    Button("Manage") { NSWorkspace.shared.open(ChatGPTOAuth.usageURL) }
                        .buttonStyle(QuietButtonStyle(size: 13))
                        .accessibilityLabel("Manage ChatGPT plan usage")
                        .accessibilityHint("Opens your ChatGPT usage settings in the browser")
                }
            }
        }
        .padding(Spacing.inner)
        .frame(width: 292 + Self.labelWidth)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface).shadow(color: .black.opacity(0.16), radius: 18, y: 8))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.controlBorder))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Run options")
    }

    /// Wide enough for the longest label in the language the app is shown in ("Ansträngning", "Abonnement").
    private static let labelWidth: CGFloat = {
        let labels = [String(localized: "Takes", comment: "Run options: number of takes"), String(localized: "Model"),
                      String(localized: "Effort"), String(localized: "Plan", comment: "Run options: the ChatGPT plan in use")]
        let font = NSFont.systemFont(ofSize: 13)
        return max(52, labels.map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) + 2 }.max() ?? 52)
    }()

    private func row<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: Spacing.item) {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.secondaryText).lineLimit(1).frame(width: Self.labelWidth, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Preset picker

struct PresetPickerView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(spacing: 0) {
            let draft = model.draft.isEmpty ? String(localized: "No draft yet") : model.draft.replacingOccurrences(of: "\n", with: " ")
            Text(draft)
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .contentDirection(draft)
                .frame(height: Spacing.control)
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.bar)
            Rule()

            HStack(spacing: Spacing.inner) {
                Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.secondaryText)
                KeyTextField(text: Binding(get: { model.filter }, set: { model.filter = $0; model.filterChanged() }),
                             placeholder: String(localized: "Filter presets…"), fontSize: 15, focusToken: model.focusToken,
                             onSubmit: model.chooseHighlighted, onUp: { model.moveHighlight(-1) },
                             onDown: { model.moveHighlight(1) }, onEscape: model.escape)
                HStack(spacing: 3) {
                    Kbd("↑"); Kbd("↓")
                    Text("move ·").font(.system(size: 12)).foregroundStyle(Theme.secondaryText).padding(.horizontal, 2)
                    Kbd("↵")
                    Text("choose").font(.system(size: 12)).foregroundStyle(Theme.secondaryText).padding(.leading, 2)
                }
            }
            .frame(height: Spacing.control)
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.bar)
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
            ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    let rows = Array(model.filteredPresets.enumerated())
                    let pickedIDs = Set(model.pickedForApp.map(\.id))
                    let picked = rows.filter { pickedIDs.contains($0.element.id) }
                    let others = rows.filter { !pickedIDs.contains($0.element.id) }
                    if !picked.isEmpty {
                        sectionTitle(String(localized: "Picked for \(model.displayAppName)"))
                        ForEach(picked, id: \.element.id) { row($0.element, index: $0.offset) }
                    }
                    if !others.isEmpty {
                        sectionTitle(String(localized: "All presets"))
                        ForEach(others, id: \.element.id) { row($0.element, index: $0.offset) }
                    }
                    if model.showsBrowseRow { BrowsePresetsRow(model: model).id(PresetListRow.browse) }
                    if rows.isEmpty && !model.showsBrowseRow {
                        Text("No preset matches “\(model.filter)”.")
                            .font(.system(size: 14)).foregroundStyle(Theme.secondaryText).padding(12)
                    }
                }
                .padding(Spacing.gutter / 2)
            }
            // Arrow keys can move the highlight past the visible rows; bring it into view (no-op when it already is,
            // so hovering never scrolls).
            .onChange(of: model.highlighted) {
                let target = model.browseRowHighlighted ? PresetListRow.browse : model.highlightedPreset.map { PresetListRow.preset($0.id) }
                guard let target else { return }
                withAnimation(Motion.animation(.easeOut(duration: Motion.standard))) { scroller.scrollTo(target) }
            }
            }
            Rule()
            // Side by side while both labels fit on one line; stacked in languages with longer words.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.item) { newPresetButton; editPresetsButton }
                VStack(spacing: Spacing.inner) { newPresetButton; editPresetsButton }
            }
            .buttonStyle(SecondaryButtonStyle(height: 34))
            .padding(Spacing.gutter / 2)
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
    private var newPresetButton: some View {
        Button { model.onOpenSettings(.presets, true) } label: {
            HStack(spacing: 6) { Text("New preset"); Kbd("⌘N") }.fixedSize().frame(maxWidth: .infinity)
        }
    }

    private var editPresetsButton: some View {
        Button { model.onOpenSettings(.presets, false) } label: {
            HStack(spacing: 6) { Text("Edit presets"); Kbd("⌘,") }.fixedSize().frame(maxWidth: .infinity)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(Font.labelSpacing(0.5))
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, Spacing.gutter / 2)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private func row(_ preset: Preset, index: Int) -> some View {
        let isHighlighted = model.highlightedPreset?.id == preset.id
        return Button { model.choose(preset.id) } label: {
            HStack(spacing: Spacing.inner) {
                PresetDot(hex: preset.colorHex)
                Text(preset.name)
                    .font(.system(size: 14, weight: isHighlighted ? .semibold : .regular))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer()
                if let number = model.shortcutNumber(of: preset) { Kbd("⌘\(number)") }
            }
            // With the list inset, row text starts on the gutter.
            .padding(.horizontal, Spacing.gutter / 2)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 8).fill(isHighlighted ? Theme.accentSoft : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { model.highlighted = index } }
        .id(PresetListRow.preset(preset.id))
    }

    @ViewBuilder private var preview: some View {
        if let preset = model.highlightedPreset {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preset.name).font(.system(size: 17, weight: .bold))
                        Text(preset.summary(for: model.store.settings)).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                    }
                    Text(preset.instruction).font(.system(size: 14)).foregroundStyle(Theme.controlText).lineSpacing(3)
                        .contentDirection(preset.instruction)
                    if !preset.dos.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.item) {
                            Text("Do").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.doText)
                            FlowLayout { ForEach(preset.dos, id: \.self) { Chip(text: $0, style: .positive) } }
                        }
                    }
                    if !preset.avoid.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.item) {
                            Text("Avoid").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.avoidText)
                            FlowLayout { ForEach(preset.avoid, id: \.self) { Chip(text: $0, style: .negative) } }
                        }
                    }
                    Text(previewFootnote(preset)).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.section)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.strip)
        } else if model.browseRowHighlighted {
            BrowsePresetsPreview(model: model)
        } else {
            Theme.strip
        }
    }

    private func previewFootnote(_ preset: Preset) -> String {
        var parts: [String] = []
        let rules = model.store.settings.voiceRules.filter(\.enabled).count
        if rules > 0 { parts.append(rules == 1 ? String(localized: "Plus your 1 voice rule") : String(localized: "Plus your \(rules) voice rules")) }
        let examples = preset.examples.count
        if examples > 0 { parts.append(examples == 1 ? String(localized: "1 example of your voice") : String(localized: "\(examples) examples of your voice")) }
        if !preset.apps.isEmpty {
            let apps = preset.apps.map(\.name).joined(separator: ", ")
            parts.append(String(localized: "auto-picked in \(apps)"))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Limits

/// Out of credit, at a plan limit, or rate limited: what happened, and the page that fixes it.
struct LimitNotice: View {
    let limit: UsageLimitError
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.inner) {
            VStack(alignment: .leading, spacing: 4) {
                Text(limit.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                Text(limit.message).font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
            HStack {
                // Out of credit or at a plan limit, the fix is on the provider's site, so that's the primary action.
                if let url = limit.manage, limit.kind != .rateLimited {
                    Button(limit.manageTitle) { NSWorkspace.shared.open(url) }.buttonStyle(PrimaryButtonStyle())
                        .accessibilityHint("Opens your account's usage page in the browser")
                    Button("Try again", action: model.generate).buttonStyle(SecondaryButtonStyle(height: 36))
                } else {
                    Button("Try again", action: model.generate).buttonStyle(PrimaryButtonStyle())
                }
                Button("Change engine…") { model.onOpenSettings(.engine, false) }.buttonStyle(SecondaryButtonStyle(height: 36))
            }
        }
    }
}

// MARK: - Takes

struct TakesView: View {
    @Environment(\.layoutDirection) private var layoutDirection
    @ObservedObject var model: PanelModel
    @FocusState private var gridFocused: Bool
    @State private var refineFocus = 0
    @State private var gridHeight: CGFloat = 0
    @State private var flagsMonitor: Any?
    @Namespace private var selection

    var body: some View {
        VStack(spacing: 0) {
            header
            Rule()
            DraftStrip(draft: model.sourceDraft, run: model.coach)
            Rule()

            if let error = model.error {
                VStack(alignment: .leading, spacing: Spacing.inner) {
                    if let limit = model.limit {
                        LimitNotice(limit: limit, model: model)
                    } else {
                        Text(error).font(.system(size: 14)).foregroundStyle(Theme.avoidText).textSelection(.enabled)
                        HStack {
                            if error == ClaudeCodeEngine.signedOutMessage {
                                // Signed out: signing in is the fix, then Try again once it's done.
                                Button("Sign in to Claude", action: ClaudeCodeEngine.openSignIn).buttonStyle(PrimaryButtonStyle())
                                Button("Try again", action: model.generate).buttonStyle(SecondaryButtonStyle(height: 36))
                            } else {
                                Button("Try again", action: model.generate).buttonStyle(PrimaryButtonStyle())
                            }
                            Button("Edit draft") { model.show(.compose) }.buttonStyle(SecondaryButtonStyle(height: 36))
                        }
                    }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.section)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else if model.noFixesFound {
                NoFixesView(model: model)
            } else {
                // The grid scrolls only past `maxGridHeight`; below that the panel grows to fit it, so the gaps
                // above and below the cards stay equal.
                ScrollView {
                    grid
                        .padding(.horizontal, Spacing.gutter)
                        .padding(.vertical, Spacing.section)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { gridHeight = $0 }
                }
                .frame(height: min(gridHeight, Self.maxGridHeight))
                .focusable()
                .focusEffectDisabled()
                .focused($gridFocused)
                // The cards run right to left in right-to-left languages, so the arrows follow what's on screen.
                .onKeyPress(.leftArrow) { move(layoutDirection == .rightToLeft ? 1 : -1); return .handled }
                .onKeyPress(.rightArrow) { move(layoutDirection == .rightToLeft ? -1 : 1); return .handled }
                .onKeyPress(.upArrow) { move(-3); return .handled }
                .onKeyPress(.downArrow) { move(3); return .handled }
                .onKeyPress(.return) { model.pasteSelected(); return .handled }
                .onKeyPress(.escape) { model.escape(); return .handled }

                refineBar
            }

            CoachStrip(model: model, run: model.coach)
            if let offer = model.invitation, !model.running {
                CoachInvitationStrip(model: model, offer: offer)
                    .transition(.asymmetric(insertion: .push(from: .top).combined(with: .opacity), removal: .opacity))
            }
            Rule()
            footer
        }
        .animation(Motion.animation().delay(Motion.standard), value: model.invitation)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.takesContentHeight = $0; model.onContentHeight($0) }
        // The panel doesn't shrink while takes stream in; once they're done it fits again. Deferred and read from
        // the model, so it uses the finished screen's height (say "No mistakes found"), not the streaming one.
        .onChange(of: model.running) { DispatchQueue.main.async { model.onContentHeight(model.takesContentHeight) } }
        .background(shortcuts)
        .onAppear {
            gridFocused = true
            watchOption()
        }
        .onDisappear {
            if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
            flagsMonitor = nil
            model.optionHeld = false
        }
        .onChange(of: model.focusToken) { gridFocused = true }
    }

    static let maxGridHeight: CGFloat = 480

    private func move(_ delta: Int) {
        withAnimation(Motion.animation()) { model.moveSelection(delta) }
    }

    /// ⌥ held shows every take's changes at once.
    private func watchOption() {
        guard flagsMonitor == nil else { return }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [model] event in
            let held = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option
            if model.optionHeld != held { model.optionHeld = held }
            return event
        }
    }

    /// Rows of up to three cards. Cards in a row share its height.
    private var grid: some View {
        let columns = max(1, min(model.cardCount, 3))
        let rows = stride(from: 0, to: model.cardCount, by: columns).map { Array($0..<min($0 + columns, model.cardCount)) }
        return VStack(spacing: Spacing.section) {
            ForEach(rows, id: \.first) { row in
                HStack(alignment: .top, spacing: Spacing.section) {
                    ForEach(row, id: \.self) { index in
                        TakeCard(model: model, index: index, ring: selection)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onTapGesture(count: 2) { model.paste(index) }
                            .onTapGesture {
                                withAnimation(Motion.animation()) { model.select(index) }
                                gridFocused = true
                            }
                    }
                    ForEach(row.count..<columns, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.inner) {
            HStack(spacing: Spacing.item) {
                PresetDot(hex: model.preset.colorHex)
                Text(model.preset.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            }
            .padding(.horizontal, Spacing.inner)
            .frame(height: Spacing.control)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.accentSoft))
            Text(model.runLabel)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: Spacing.item)
            HStack(spacing: Spacing.section) {
                Button { model.show(.compose) } label: { HStack(spacing: 4) { Kbd("⌘E"); Text("edit") } }
                    .accessibilityLabel("Edit draft")
                Button(action: model.generate) { HStack(spacing: 4) { Kbd("⌘R"); Text("again") } }
                    .disabled(model.running)
                    .accessibilityLabel("Regenerate")
            }
            .buttonStyle(QuietButtonStyle())
            .fixedSize()
        }
        .frame(height: Spacing.control)
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, Spacing.bar)
    }

    private var refineBar: some View {
        HStack(spacing: Spacing.inner) {
            Image(systemName: "pencil").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.secondaryText)
            KeyTextField(text: $model.refineText,
                         placeholder: String(localized: "Refine take \(model.selected + 1): warmer, drop the second ask, add a thanks…"),
                         fontSize: 14, focusToken: refineFocus,
                         onSubmit: { model.refine(); gridFocused = true },
                         onEscape: { gridFocused = true })
            Button("More like take \(model.selected + 1)", action: model.moreLikeSelected)
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!model.isFinished(model.selected) || model.running)
        }
        .padding(.leading, Spacing.inner)
        .padding(.trailing, Spacing.item)
        .padding(.vertical, Spacing.item)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.controlBorder))
        .padding(.horizontal, Spacing.gutter)
        .padding(.bottom, Spacing.section)
    }

    private var footer: some View {
        HStack(spacing: Spacing.section) {
            // The paste button keeps its whole label; where that's tight (the one-take panel, long words) the
            // hints drop from the end.
            ViewThatFits(in: .horizontal) {
                keyHints(4)
                keyHints(3)
                keyHints(2)
                keyHints(1)
            }
            Spacer(minLength: 0)
            if model.running {
                TimelineView(.periodic(from: model.startedAt, by: 0.1)) { context in
                    Text(String(format: NSLocalizedString("Writing… %.1f s", comment: ""), locale: .current, context.date.timeIntervalSince(model.startedAt)))
                        .font(.system(size: 12)).foregroundStyle(Theme.secondaryText).monospacedDigit()
                }
            } else if !model.timing.isEmpty {
                // In the narrow one-take panel the timing gives way rather than squeeze the key hints.
                ViewThatFits(in: .horizontal) {
                    Text(model.timing).font(.system(size: 12)).foregroundStyle(Theme.secondaryText).fixedSize()
                    Color.clear.frame(width: 0, height: 0)
                }
            }
            Button(action: model.noFixesFound ? model.pasteOriginal : model.pasteSelected) {
                HStack(spacing: Spacing.item) {
                    Text(model.noFixesFound ? "Paste original" : "Paste take \(model.selected + 1)")
                    Text("↵").font(.system(size: 12)).opacity(0.85)
                }
            }
            .buttonStyle(PrimaryButtonStyle(height: Spacing.control))
            .fixedSize()
            .disabled(!model.isFinished(model.selected))
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, Spacing.bar)
    }

    private func keyHints(_ count: Int) -> some View {
        var hints: [KeyHint] = [KeyHint(keys: ["←", "→"], label: String(localized: "move", comment: "Key hint: arrows move between takes"))]
        if !model.showsFixes { hints.append(KeyHint(keys: ["⌥"], label: String(localized: "changes", comment: "Key hint: ⌥ shows each take's changes"))) }
        hints.append(KeyHint(keys: ["⌘", "C"], label: String(localized: "copy", comment: "Key hint: ⌘C copies the take")))
        hints.append(KeyHint(keys: ["esc"], label: String(localized: "back", comment: "Key hint: esc goes back")))
        let shown = Array(hints.prefix(count))
        return HStack(spacing: Spacing.section) {
            ForEach(shown.indices, id: \.self) { shown[$0] }
        }
        .fixedSize()
    }

    private var shortcuts: some View {
        ZStack {
            ForEach(1...5, id: \.self) { number in
                ShortcutButton(key: KeyEquivalent(Character("\(number)"))) { model.paste(number - 1) }
            }
            ShortcutButton(key: "e") { model.show(.compose) }
            ShortcutButton(key: "r") { model.generate() }
            ShortcutButton(key: ";") { withAnimation(Motion.animation()) { model.coachExpanded.toggle() } }
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
    let ring: Namespace.ID

    var body: some View {
        let isSelected = model.selected == index
        let finished = model.isFinished(index)
        let hasText = index < model.takes.count
        let showChanges = finished && (model.changesShown.contains(index) || model.optionHeld)

        VStack(alignment: .leading, spacing: Spacing.inner) {
            HStack(spacing: Spacing.item) {
                Text(label(finished: finished, showChanges: showChanges))
                    .font(.mono(10.5, bold: true))
                    .kerning(Font.labelSpacing(0.5))
                    .foregroundStyle(isSelected ? Theme.text : Theme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !finished && hasText { ProgressView().controlSize(.mini) }
                if index < 5 {
                    Text(verbatim: "\u{200E}⌘\(index + 1)").font(.mono(10.5)).foregroundStyle(Theme.tertiaryText)
                }
            }

            Group {
                if showChanges {
                    Text(WordDiff.attributed(from: model.sourceDraft, to: model.takes[index]))
                        .accessibilityLabel(WordDiff.spoken(from: model.sourceDraft, to: model.takes[index]))
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
            .frame(maxWidth: .infinity, minHeight: 72, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.layoutDirection, ContentDirection.layout(model.takes[index]))
            TakeToneLine(model: model, index: index)
        }
        .padding(Spacing.section)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        // Drawn inside the card's edge, so the selected card's thicker border doesn't eat into the gaps around it.
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border, lineWidth: 1))
        .overlay {
            // One ring that slides from card to card.
            if isSelected {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.accent, lineWidth: 2)
                    .shadow(color: Theme.accent.opacity(0.14), radius: 10, y: 4)
                    .matchedGeometryEffect(id: "ring", in: ring)
            }
        }
        .contentShape(Rectangle())
        // Each card rises 6 pt and fades in as its first words land, 120 ms after the one before it.
        .opacity(hasText || !model.running ? 1 : 0.55)
        .offset(y: hasText || !model.running ? 0 : 6)
        .animation(Motion.animation().delay(Double(index) * Motion.stagger), value: hasText)
        .help(tooltip(finished: finished))
    }

    private func label(finished: Bool, showChanges: Bool) -> String {
        let number = index + 1
        if !finished { return String(localized: "TAKE \(number) · WRITING") }
        return showChanges ? String(localized: "TAKE \(number) · CHANGES") : String(localized: "TAKE \(number)")
    }

    private func tooltip(finished: Bool) -> String {
        guard finished else { return "" }
        let count = WordCounter.count(model.takes[index])
        let hints = String(localized: "\(count) words · ⌥ shows changes · ⌘C copies")
        return model.showsFixes ? Proofread.fixLabel(model.fixCount(index)) + " · " + hints : hints
    }
}

/// Scroll targets in the preset picker's list.
private enum PresetListRow: Hashable {
    case preset(String)
    case browse
}
