import SwiftUI

/// Settings › Presets › Browse presets: ready-made presets with a preview. Check several and add them at once;
/// each becomes the user's own copy to edit. ↑↓ move, space checks, ↵ adds, Esc closes.
struct PresetGalleryView: View {
    @ObservedObject var store = Store.shared
    /// Called with the copies just added.
    var onAdd: ([Preset]) -> Void = { _ in }
    var onClose: () -> Void = {}

    @State var highlightedID = PresetGallery.all.first?.id ?? ""
    @State var checked: Set<String> = []
    @FocusState private var listFocused: Bool

    private var templates: [Preset] { PresetGallery.all }
    private var highlighted: Preset? { templates.first { $0.id == highlightedID } }
    private func isAdded(_ template: Preset) -> Bool { PresetGallery.isAdded(template, in: store.presets) }

    /// What ↵ adds: the checked presets, or else the highlighted one if it isn't added yet.
    private var toAdd: [Preset] {
        let picked = templates.filter { checked.contains($0.id) && !isAdded($0) }
        if !picked.isEmpty { return picked }
        if let highlighted, !isAdded(highlighted) { return [highlighted] }
        return []
    }

    private var addTitle: String {
        let items = toAdd
        if items.count > 1 { return String(localized: "Add \(items.count) presets") }
        if let one = items.first { return String(localized: "Add “\(one.name)”") }
        return String(localized: "Added")
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Preset gallery").font(.system(size: 18, weight: .bold))
                Text("Ready-made presets. Adding one gives you your own copy to change.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.section)
            RowDivider()

            HStack(spacing: 0) {
                list.frame(width: 320)
                Rectangle().fill(Theme.border).frame(width: 1)
                if let highlighted {
                    GalleryPresetPreview(preset: highlighted, added: isAdded(highlighted))
                } else {
                    Theme.strip
                }
            }
            RowDivider()

            HStack(spacing: Spacing.item) {
                HStack(spacing: 3) {
                    Kbd("↑"); Kbd("↓")
                    Text("move ·").font(.system(size: 12)).foregroundStyle(Theme.secondaryText).padding(.horizontal, 2)
                    Kbd("space")
                    Text("check").font(.system(size: 12)).foregroundStyle(Theme.secondaryText).padding(.leading, 2)
                }
                Spacer()
                Button(action: onClose) { HStack(spacing: 6) { Text("Cancel"); Kbd("esc") } }
                    .buttonStyle(SecondaryButtonStyle(height: 34))
                    .keyboardShortcut(.cancelAction)
                Button(action: add) { HStack(spacing: 6) { Text(addTitle); Kbd("↵") } }
                    .buttonStyle(PrimaryButtonStyle(height: 34))
                    .keyboardShortcut(.defaultAction)
                    .disabled(toAdd.isEmpty)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.bar)
            .background(Theme.chrome)
        }
        .frame(width: 860, height: 580)
        .foregroundStyle(Theme.text)
        .background(Theme.surface)
        .onAppear { listFocused = true }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(templates) { row($0) }
                }
                .padding(Spacing.gutter / 2)
            }
            .background(Theme.sidebar)
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            .onKeyPress(.upArrow) { move(-1, proxy); return .handled }
            .onKeyPress(.downArrow) { move(1, proxy); return .handled }
            .onKeyPress(.space) { toggle(highlightedID); return .handled }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Gallery presets")
        }
    }

    private func row(_ template: Preset) -> some View {
        let isHighlighted = template.id == highlightedID
        let added = isAdded(template)
        return HStack(spacing: Spacing.inner) {
            if added {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.doText)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            } else {
                Checkbox(isOn: Binding(get: { checked.contains(template.id) }, set: { _ in toggle(template.id) }),
                         label: String(localized: "Add \(template.name)"))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    PresetDot(hex: template.colorHex)
                    Text(template.name)
                        .font(.system(size: 14, weight: isHighlighted ? .semibold : .regular))
                        .lineLimit(1)
                }
                Text(PresetGallery.blurb(for: template))
                    .font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 4)
            if added { Text("Added").font(.system(size: 12)).foregroundStyle(Theme.tertiaryText) }
        }
        .padding(.horizontal, Spacing.gutter / 2)
        .frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 8).fill(isHighlighted ? Theme.selectedRow : .clear))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if !added { highlightedID = template.id; checked = []; add() } }
        .onTapGesture { highlightedID = template.id; listFocused = true }
        .id(template.id)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
        .accessibilityValue(added ? "Added" : (checked.contains(template.id) ? "Checked" : ""))
    }

    private func move(_ delta: Int, _ proxy: ScrollViewProxy) {
        guard let index = templates.firstIndex(where: { $0.id == highlightedID }) else { return }
        let next = min(max(index + delta, 0), templates.count - 1)
        highlightedID = templates[next].id
        proxy.scrollTo(highlightedID)
    }

    private func toggle(_ id: String) {
        guard let template = templates.first(where: { $0.id == id }), !isAdded(template) else { return }
        if checked.contains(id) { checked.remove(id) } else { checked.insert(id) }
    }

    private func add() {
        let items = toAdd
        guard !items.isEmpty else { return }
        let added = PresetGallery.add(items, to: &store.presets)
        checked = []
        onAdd(added)
    }
}

/// The right side of the gallery: what the preset tells the model, as the panel's preset preview shows it.
struct GalleryPresetPreview: View {
    let preset: Preset
    var added = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Spacing.item) {
                        PresetDot(hex: preset.colorHex)
                        Text(preset.name).font(.system(size: 17, weight: .bold))
                    }
                    Text(preset.summary).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                }
                Text(preset.instruction).font(.system(size: 14)).foregroundStyle(Theme.controlText).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
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
                Text(footnote).font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.section)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.strip)
    }

    private var footnote: String {
        var parts: [String] = []
        if case .language(let code) = preset.language { parts.append(String(localized: "Always writes in \(Languages.displayName(code)).")) }
        if !preset.apps.isEmpty {
            let apps = preset.apps.map(\.name).joined(separator: ", ")
            parts.append(String(localized: "Picked automatically in \(apps)."))
        }
        parts.append(added ? String(localized: "Already in your presets. Edit it there.")
                           : String(localized: "You can change everything after adding it, including the apps it's picked in."))
        return parts.joined(separator: " ")
    }
}

// MARK: - Panel picker

/// The quiet last row of the panel's preset picker. ↵ on it, or a click, opens the gallery in Settings.
struct BrowsePresetsRow: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        let isHighlighted = model.browseRowHighlighted
        Button(action: model.onOpenGallery) {
            HStack(spacing: Spacing.inner) {
                Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).frame(width: 8)
                Text("Browse more presets").font(.system(size: 14, weight: isHighlighted ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(isHighlighted ? Theme.text : Theme.secondaryText)
            .padding(.horizontal, Spacing.gutter / 2)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 8).fill(isHighlighted ? Theme.accentSoft : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .onHover { if $0 { model.highlighted = model.filteredPresets.count } }
        .accessibilityLabel("Browse more presets")
        .accessibilityHint("Opens the preset gallery in Settings")
    }
}

/// The picker's preview while "Browse more presets" is highlighted: what's in the gallery that isn't added yet.
struct BrowsePresetsPreview: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        let missing = PresetGallery.all.filter { !PresetGallery.isAdded($0, in: model.store.presets) }
        VStack(alignment: .leading, spacing: Spacing.section) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Preset gallery").font(.system(size: 17, weight: .bold))
                Text("Opens in Settings").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
            Text(missing.isEmpty ? "You have every ready-made preset. You can still edit them or write your own."
                                 : "Ready-made presets you can add and then change.")
                .font(.system(size: 14)).foregroundStyle(Theme.controlText).lineSpacing(3)
            if !missing.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.item) {
                    ForEach(missing.prefix(6)) { template in
                        HStack(spacing: Spacing.item) {
                            PresetDot(hex: template.colorHex)
                            Text(template.name).font(.system(size: 13, weight: .semibold))
                            Text(PresetGallery.blurb(for: template)).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    if missing.count > 6 {
                        Text("and \(missing.count - 6) more").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, Spacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.strip)
    }
}

// MARK: - Settings › Presets

/// Above a just-made, still-blank preset: start from a ready-made one instead.
struct GalleryHintBar: View {
    let action: () -> Void

    var body: some View {
        HStack(spacing: Spacing.inner) {
            Image(systemName: "square.grid.2x2").font(.system(size: 13)).foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Start from a ready-made preset instead?").font(.system(size: 13)).foregroundStyle(Theme.controlText)
            Spacer()
            Button("Browse presets", action: action).buttonStyle(SecondaryButtonStyle(height: 28))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
        .background(Theme.accentSoft)
    }
}
