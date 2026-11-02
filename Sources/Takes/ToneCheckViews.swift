import SwiftUI

extension PanelModel {
    /// ⌘T in compose: how the draft may come across.
    func checkTone() {
        guard preset.showTone, screen == .compose else { return }
        toneRead.check(draft: draft, settings: store.settings)
    }
}

/// "May read as warm and clear", under a take's text once all takes are written. The line keeps its
/// height while the note is on its way, so the cards don't jump when it arrives.
struct TakeToneLine: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var tones: TakeTones
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: PanelModel, index: Int) {
        self.model = model
        tones = model.takeTones
        self.index = index
    }

    var body: some View {
        if model.preset.showTone, !model.running, model.isFinished(index) {
            let note = tones.note(index)
            Text(note.map(ToneCheck.label) ?? (tones.loading ? "Reading the tone…" : " "))
                .font(.system(size: 12))
                .foregroundStyle(note == nil ? Theme.tertiaryText : Theme.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: note)
                .accessibilityLabel(note.map { "Tone: \(ToneCheck.label($0).lowercased())" } ?? "")
                .accessibilityHidden(note == nil && !tones.loading)
        }
    }
}

/// The "⌘T how it reads" hint in the compose footer. It's also the button.
struct ToneReadHint: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        if model.preset.showTone {
            Button(action: model.checkTone) { KeyHint(keys: ["⌘", "T"], label: "how it reads") }
                .buttonStyle(.plain)
                .keyboardShortcut("t", modifiers: .command)
                .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("How does this read?")
        }
    }
}

/// The read of the draft, inline under it. Nothing is shown until ⌘T; editing the draft or Esc removes it.
struct ToneReadSection: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var toneRead: ToneReadModel

    init(model: PanelModel) {
        self.model = model
        toneRead = model.toneRead
    }

    var body: some View {
        Group {
            if toneRead.isShown {
                HStack(alignment: .top, spacing: Spacing.item) {
                    content.frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: toneRead.dismiss) { KeyHint(keys: ["esc"], label: "dismiss") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss the tone read")
                }
                .padding(.horizontal, Spacing.inner)
                .padding(.vertical, Spacing.item + 2)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.strip))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
                .padding(.horizontal, Spacing.gutter)
                .padding(.bottom, Spacing.section)
                .accessibilityElement(children: .contain)
            }
        }
        .onChange(of: model.draft) { _, draft in toneRead.draftChanged(draft) }
    }

    @ViewBuilder private var content: some View {
        switch toneRead.state {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: Spacing.item) {
                ProgressView().controlSize(.mini)
                Text("Reading how this may land…").foregroundStyle(Theme.secondaryText)
            }
            .font(.system(size: 13))
            .accessibilityElement(children: .combine)
        case .done(let read):
            VStack(alignment: .leading, spacing: 3) {
                Text(read.summary).foregroundStyle(Theme.text)
                if let hint = read.hint {
                    (Text("Try: ").fontWeight(.semibold) + Text(hint)).foregroundStyle(Theme.secondaryText)
                }
            }
            .font(.system(size: 13))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        case .failed(let message):
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.avoidText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "Tone" at the end of the preset editor.
struct PresetToneSection: View {
    @Binding var preset: Preset

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Tone")
            HStack(alignment: .top, spacing: 10) {
                Checkbox(isOn: $preset.showTone, label: "Show tone")
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Show how each take may come across").font(.system(size: 14)).foregroundStyle(Theme.text)
                    Text("A few words under each take, like “may read as a bit curt”. ⌘T in compose checks your draft.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .contentShape(Rectangle())
                .onTapGesture { preset.showTone.toggle() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.strip))
    }
}
