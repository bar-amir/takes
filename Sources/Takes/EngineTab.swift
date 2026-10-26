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
                    engineCard(selected: false, enabled: false) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sign in with Claude").font(.system(size: 15, weight: .semibold))
                            Text("Public build, only if Anthropic approves it.").font(.system(size: 13))
                        }
                        .foregroundStyle(Theme.secondaryText)
                    }

                    SectionTitle("Defaults for new presets").padding(.top, 10)
                    HStack(spacing: 14) {
                        Picker("Takes", selection: $store.settings.defaultTakes) { ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }
                            .fixedSize()
                        Picker("Model", selection: $store.settings.defaultModel) { ForEach(Models.all, id: \.id) { Text($0.label).tag($0.id) } }
                            .fixedSize()
                        Picker("Effort", selection: $store.settings.defaultEffort) { ForEach(Models.efforts, id: \.self) { Text($0.capitalized).tag($0) } }
                            .fixedSize()
                    }
                    if let ms = store.settings.lastFirstTextMs {
                        Text(String(format: "Last run: first words after %.1f s.", Double(ms) / 1000))
                            .font(.callout).foregroundStyle(Theme.secondaryText)
                    }
                }
                .padding(28)
            }
            .frame(maxWidth: .infinity)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle("Voice rules for every preset")
                    VoiceRulesEditor()
                    SectionTitle("Panel and paste").padding(.top, 10)
                    PanelSettings()
                }
                .padding(28)
            }
            .frame(maxWidth: .infinity)
            .background(Theme.strip)
        }
        .task { status = await ClaudeCodeEngine.status() }
    }

    private var claudeCodeCard: some View {
        engineCard(selected: store.settings.engine == .claudeCode, enabled: true, select: { store.settings.engine = .claudeCode }) {
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
                    .controlSize(.small)
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
        engineCard(selected: store.settings.engine == .apiKey, enabled: true, select: { store.settings.engine = .apiKey }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Anthropic API key").font(.system(size: 15, weight: .semibold))
                Text("Pay per use, billed by Anthropic. Usually a cent or two per run.").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                if hasKey {
                    HStack {
                        Text("Key saved in your keychain").font(.system(size: 12)).foregroundStyle(Theme.doText)
                        Button("Remove") { Keychain.setAPIKey(nil); hasKey = false }.controlSize(.small)
                    }
                } else {
                    HStack {
                        SecureField("Paste your key", text: $keyInput).textFieldStyle(.roundedBorder)
                        Button("Save") {
                            Keychain.setAPIKey(keyInput.trimmingCharacters(in: .whitespacesAndNewlines))
                            keyInput = ""
                            hasKey = Keychain.apiKey != nil
                        }
                        .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func engineCard<Content: View>(selected: Bool, enabled: Bool, select: @escaping () -> Void = {},
                                            @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(selected ? Theme.accent : .secondary)
                .padding(.top, 2)
            content()
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Theme.accentSoft : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Theme.accent : Theme.border,
                                                           style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: enabled ? [] : [4])))
        .contentShape(Rectangle())
        .onTapGesture { if enabled { select() } }
        .opacity(enabled ? 1 : 0.7)
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
            Divider()
            row("Open the panel") {
                Picker("", selection: $store.settings.panelPosition) { ForEach(PanelPosition.allCases) { Text($0.label).tag($0) } }
                    .labelsHidden().fixedSize()
            }
            Divider()
            row("Start with") {
                Picker("", selection: $store.settings.prefill) { ForEach(Prefill.allCases) { Text($0.label).tag($0) } }
                    .labelsHidden().fixedSize()
            }
            Divider()
            row("Put my clipboard back after pasting") { Toggle("", isOn: $store.settings.restoreClipboard).labelsHidden() }
            Divider()
            row("Keep 30 days of history, on this Mac only") { Toggle("", isOn: $store.settings.keepHistory).labelsHidden() }
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack {
            Text(title).font(.system(size: 14))
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct VoiceTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle("Voice rules for every preset")
                Text("These apply on top of each preset's own Do and Avoid lists. Untick a rule to pause it.")
                    .font(.callout).foregroundStyle(Theme.secondaryText)
                VoiceRulesEditor()
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
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
                    .font(.callout).foregroundStyle(Theme.secondaryText)
                Spacer()
                Button("Clear history") { store.history = [] }.disabled(store.history.isEmpty)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            Divider()
            if store.history.isEmpty {
                Text("No runs yet.").foregroundStyle(Theme.secondaryText).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(store.history) { entry in entryView(entry) }
                    }
                    .padding(28)
                }
            }
        }
    }

    private func entryView(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(Self.dateFormat.string(from: entry.date)).font(.system(size: 12, weight: .semibold))
                Text("· \(entry.appName) · \(entry.presetName)").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            }
            Text(entry.draft).font(.system(size: 13)).foregroundStyle(Theme.secondaryText).lineLimit(3)
            ForEach(Array(entry.takes.enumerated()), id: \.offset) { index, take in
                HStack(alignment: .top, spacing: 10) {
                    Text(entry.pastedIndex == index ? "Pasted" : "Take \(index + 1)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(entry.pastedIndex == index ? Theme.accent : .secondary)
                        .frame(width: 52, alignment: .leading)
                    Text(take).font(.system(size: 14)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(take, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy take")
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }
}
