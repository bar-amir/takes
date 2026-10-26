import AppKit
import SwiftUI

struct EngineTab: View {
    @ObservedObject var store = Store.shared
    @State private var status: (found: Bool, signedIn: Bool, plan: String?)?
    @State private var keyInput = ""
    @State private var hasKey = Keychain.apiKey != nil

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle("Where Claude runs")
                    claudeCodeCard
                    apiKeyCard
                    EngineCard(selected: false, enabled: false) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sign in with Claude").font(.system(size: 15, weight: .semibold))
                            Text("Public build, only if Anthropic approves it.").font(.system(size: 13))
                        }
                        .foregroundStyle(Theme.secondaryText)
                    }

                    SectionTitle("Defaults for new presets").padding(.top, 14)
                    FlowLayout(spacing: 18) {
                        LabeledMenu(label: "Takes", options: (1...5).map { (value: $0, title: "\($0)") }, selection: $store.settings.defaultTakes)
                        LabeledMenu(label: "Model", options: Models.all.map { (value: $0.id, title: $0.label) }, selection: $store.settings.defaultModel)
                        LabeledMenu(label: "Effort", options: Models.efforts.map { (value: $0, title: $0.capitalized) }, selection: $store.settings.defaultEffort)
                    }
                    if let ms = store.settings.lastFirstTextMs {
                        Text(String(format: "Last run: first words after %.1f s.", Double(ms) / 1000))
                            .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(Theme.border).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle("Voice rules for every preset")
                    VoiceRulesEditor()
                    SectionTitle("Panel and paste").padding(.top, 14)
                    PanelSettings()
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.sidebar)
        }
        .task { status = await ClaudeCodeEngine.status() }
    }

    private var claudeCodeCard: some View {
        EngineCard(selected: store.settings.engine == .claudeCode, enabled: true, select: { store.settings.engine = .claudeCode }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Claude Code on this Mac").font(.system(size: 15, weight: .semibold))
                    statusBadge
                }
                Text("Uses your Claude subscription. Personal build only.").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                if let status, status.found, !status.signedIn {
                    Text("Run `claude auth login` in Terminal, then check again.").font(.system(size: 12)).foregroundStyle(Theme.avoidText)
                }
                Button("Check again") { Task { status = nil; status = await ClaudeCodeEngine.status() } }
                    .buttonStyle(SecondaryButtonStyle(height: 26))
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder private var statusBadge: some View {
        if let status {
            let (text, good): (String, Bool) = !status.found ? ("Not installed", false)
                : status.signedIn ? ("Found · signed in" + (status.plan.map { " · \($0.capitalized) plan" } ?? ""), true)
                : ("Not signed in", false)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .foregroundStyle(good ? Theme.doText : Theme.avoidText)
                .background(Capsule().fill(good ? Theme.doFill : Theme.avoidFill))
        } else {
            ProgressView().controlSize(.mini)
        }
    }

    private var apiKeyCard: some View {
        EngineCard(selected: store.settings.engine == .apiKey, enabled: true, select: { store.settings.engine = .apiKey }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Anthropic API key").font(.system(size: 15, weight: .semibold))
                Text("Pay per use, billed by Anthropic. Usually a cent or two per run.").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                if hasKey {
                    HStack(spacing: 10) {
                        Text("Key saved in your keychain").font(.system(size: 13)).foregroundStyle(Theme.doText)
                        Button("Remove") { Keychain.setAPIKey(nil); hasKey = false }.buttonStyle(SecondaryButtonStyle(height: 26))
                    }
                } else {
                    HStack(spacing: 8) {
                        StyledTextField(placeholder: "Paste your key", text: $keyInput, secure: true, height: 34, onSubmit: saveKey)
                        Button("Save", action: saveKey)
                            .buttonStyle(SecondaryButtonStyle(height: 34))
                            .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func saveKey() {
        Keychain.setAPIKey(keyInput.trimmingCharacters(in: .whitespacesAndNewlines))
        keyInput = ""
        hasKey = Keychain.apiKey != nil
    }
}

/// A selectable option card with a radio dot, as in the mockup.
private struct EngineCard<Content: View>: View {
    let selected: Bool
    let enabled: Bool
    var select: () -> Void = {}
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().stroke(selected ? Theme.accent : Theme.dashed, lineWidth: 1.5).frame(width: 16, height: 16)
                if selected { Circle().fill(Theme.accent).frame(width: 8, height: 8) }
            }
            .padding(.top, 3)
            content
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Theme.accentSoft : Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Theme.accent : Theme.border,
                                                           style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: enabled ? [] : [4, 3])))
        .contentShape(Rectangle())
        .onTapGesture { if enabled { select() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

struct PanelSettings: View {
    @ObservedObject var store = Store.shared

    var body: some View {
        RowGroup {
            row("Hotkey") {
                HotKeyRecorder(combo: Binding(get: { store.settings.summonHotKey },
                                              set: { if let combo = $0 { store.settings.summonHotKey = combo } }),
                               allowClear: false)
            }
            RowDivider()
            row("Open the panel") {
                MenuPicker(options: PanelPosition.allCases.map { (value: $0, title: $0.label) }, selection: $store.settings.panelPosition)
            }
            RowDivider()
            row("Start with") {
                MenuPicker(options: Prefill.allCases.map { (value: $0, title: $0.label) }, selection: $store.settings.prefill)
            }
            RowDivider()
            row("Put my clipboard back after pasting") { Checkbox(isOn: $store.settings.restoreClipboard, label: "Restore clipboard") }
            RowDivider()
            row("Keep 30 days of history, on this Mac only") { Checkbox(isOn: $store.settings.keepHistory, label: "Keep history") }
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack {
            Text(title).font(.system(size: 14))
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
    }
}

struct VoiceTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle("Voice rules for every preset")
                Text("These apply on top of each preset's own Do and Avoid lists. Untick a rule to pause it.")
                    .font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
                VoiceRulesEditor()
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.sidebar)
    }
}

struct HistoryTab: View {
    @ObservedObject var store = Store.shared

    private static let dateFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.settings.keepHistory ? "Last 30 days, stored only on this Mac." : "History is off (Settings › Engine).")
                    .font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
                Spacer()
                Button("Clear history") { store.history = [] }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(store.history.isEmpty)
            }
            .padding(.horizontal, 32)
            .frame(height: 60)
            RowDivider()
            if store.history.isEmpty {
                Text("No runs yet.").foregroundStyle(Theme.secondaryText).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(store.history) { entry in entryView(entry) }
                    }
                    .padding(32)
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Theme.sidebar)
    }

    private func entryView(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(Self.dateFormat.string(from: entry.date)).font(.system(size: 12, weight: .semibold))
                Text("· \(entry.appName) · \(entry.presetName)").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            }
            (Text("Your draft: ").fontWeight(.semibold).foregroundStyle(Theme.controlText) + Text(entry.draft).foregroundStyle(Theme.secondaryText))
                .font(.system(size: 13)).lineLimit(3)
            ForEach(Array(entry.takes.enumerated()), id: \.offset) { index, take in
                HStack(alignment: .top, spacing: 12) {
                    Text(entry.pastedIndex == index ? "Pasted" : "Take \(index + 1)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(entry.pastedIndex == index ? Theme.accent : Theme.secondaryText)
                        .frame(width: 52, alignment: .leading)
                        .padding(.top, 2)
                    Text(take).font(.system(size: 14)).lineSpacing(3).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(take, forType: .string)
                    } label: { Image(systemName: "doc.on.doc").font(.system(size: 11, weight: .medium)) }
                    .buttonStyle(SecondaryButtonStyle(height: 28))
                    .accessibilityLabel("Copy take")
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }
}
