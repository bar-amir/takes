import SwiftUI

/// The preset editor's on/off options, in one card after "Run defaults": each feature adds a row here,
/// so the editor keeps one look however many options there are.
struct PresetOptionsCard: View {
    @Binding var preset: Preset

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.inner) {
            FieldLabel("How it writes")
            VStack(alignment: .leading, spacing: Spacing.section) {
                MinimalEditsSection(preset: $preset)
                PresetToneSection(preset: $preset)
                InstantModeSection(preset: $preset)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.strip))
        .accessibilityElement(children: .contain)
    }
}

/// A checkbox with a title and one line of detail; clicking the text toggles it too.
struct PresetOptionRow: View {
    @Binding var isOn: Bool
    let title: String
    let detail: String
    var enabled = true

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Checkbox(isOn: $isOn, label: title)
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.5)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(enabled ? Theme.text : Theme.secondaryText)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
            .onTapGesture { if enabled { isOn.toggle() } }
            .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
    }
}
