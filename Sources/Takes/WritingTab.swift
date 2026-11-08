import SwiftUI

/// Settings › Writing: the rules every preset follows and the languages you write in.
struct WritingTab: View {
    var body: some View {
        SettingsPage {
            FormSection(String(localized: "Rules for every preset"),
                        footer: String(localized: "These apply on top of each preset's own Do and Avoid lists. Untick a rule to pause it.")) {
                VoiceRulesEditor()
            }
            WritingLanguagesSection()
        }
    }
}

/// The voice rules as checkbox rows, ending with "+ Add rule".
struct VoiceRulesEditor: View {
    @ObservedObject var store = Store.shared

    var body: some View {
        ForEach($store.settings.voiceRules) { $rule in
            HStack(spacing: 12) {
                Checkbox(isOn: $rule.enabled, label: rule.text)
                TextField("Rule", text: $rule.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(rule.enabled ? Theme.text : Theme.secondaryText)
                Button { store.settings.voiceRules.removeAll { $0.id == rule.id } } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Delete rule")
                .accessibilityLabel("Delete rule")
            }
            .formRowPadding()
            FormDivider(inset: 42)
        }
        Button { store.settings.voiceRules.append(VoiceRule(text: "")) } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).frame(width: 16)
                Text("Add rule")
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.controlText)
            .formRowPadding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The languages the user writes in: presets can reply in any of them, and the gallery offers a translate preset for each.
struct WritingLanguagesSection: View {
    @ObservedObject var store = Store.shared

    var body: some View {
        FormSection(String(localized: "Languages you write in"),
                    footer: String(localized: "Presets can reply in any of these, and Browse presets offers a translate preset for each.")) {
            HStack(alignment: .center, spacing: 12) {
                LanguageChips(languages: Binding(get: { store.settings.writingLanguages },
                                                 set: { store.settings.languages = $0 }))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if store.settings.languages != nil, store.settings.languages != Languages.fromSystem() {
                    Button("Use my Mac's languages") { store.settings.languages = nil }
                        .buttonStyle(SecondaryButtonStyle(height: 28))
                        .fixedSize()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}
