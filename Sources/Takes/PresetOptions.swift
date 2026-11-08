import SwiftUI

/// The preset editor's on/off options, one group after "Run": each feature adds a row here,
/// so the editor keeps one look however many options there are.
struct PresetOptionsCard: View {
    @Binding var preset: Preset

    var body: some View {
        FormSection(String(localized: "How it writes")) {
            MinimalEditsSection(preset: $preset).padding(.horizontal, 14).padding(.vertical, 10)
            FormDivider()
            PresetToneSection(preset: $preset).padding(.horizontal, 14).padding(.vertical, 10)
            FormDivider()
            InstantModeSection(preset: $preset).padding(.horizontal, 14).padding(.vertical, 10)
        }
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
