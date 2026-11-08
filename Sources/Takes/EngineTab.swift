import AppKit
import SwiftUI

/// Settings › Model: where takes are written (one compact row per engine; the selected one shows its key field or
/// sign-in), the defaults for new presets, and where drafts go.
struct ModelTab: View {
    @ObservedObject var store = Store.shared
    @State private var status: (found: Bool, signedIn: Bool, plan: String?)?
    @State private var keyInput = ""
    @State private var hasKey = Keychain.apiKey != nil
    @ObservedObject var installer = ClaudeInstaller.shared
    /// For snapshots: shown instead of asking Claude Code.
    var fixedStatus: (found: Bool, signedIn: Bool, plan: String?)?

    var body: some View {
        SettingsPage {
            FormSection("Where your takes are written") {
                EngineRow(engine: .claudeCode, title: "Claude Code on this Mac",
                          summary: "Uses your Claude subscription; each run counts toward its usage limits. Personal build only.") {
                    claudeCodeBadge
                } details: { claudeCodeDetails }
                FormDivider(inset: 40)
                EngineRow(engine: .apiKey, title: "Anthropic API key",
                          summary: "Pay per use, billed by Anthropic. Usually a cent or two per run, more with Opus or more takes. Takes doesn't cap your spending; set a limit in the Anthropic Console.") {
                    if hasKey { StatusBadge(text: "Key saved", good: true) } else { muted("Pay per use") }
                } details: { apiKeyDetails }
                FormDivider(inset: 40)
                EngineRow(engine: .chatGPT, title: "Your ChatGPT plan",
                          summary: "Sign in with ChatGPT and write with the models in your Plus or Pro plan. No extra cost; your plan's limits apply.") {
                    ChatGPTEngineBadge()
                } details: { ChatGPTEngineSettings() }
                FormDivider(inset: 40)
                EngineRow(engine: .provider, title: "Other provider",
                          summary: "Your own API key for OpenAI, Gemini, OpenRouter, Groq or Mistral, or any OpenAI-compatible server. Billed by the provider under your account.") {
                    ProviderEngineBadge()
                } details: { ProviderEngineSettings() }
                FormDivider(inset: 40)
                EngineRow(engine: .local, title: "Local model",
                          summary: "Runs on this Mac with Ollama or LM Studio, so your drafts never leave it. Small models write plainer takes than Claude. It's free, but uses this Mac's memory and battery.") {
                    LocalEngineBadge()
                } details: { LocalEngineSettings() }
            }

            FormSection(header: "Defaults for new presets") {
                FormRow("Takes · Model · Effort") {
                    HStack(spacing: 6) {
                        MenuPicker(options: (1...5).map { (value: $0, title: "\($0)") }, selection: $store.settings.defaultTakes)
                        MenuPicker(options: Models.all.map { (value: $0.id, title: $0.label) }, selection: $store.settings.defaultModel)
                        MenuPicker(options: Models.efforts.map { (value: $0, title: $0.capitalized) }, selection: $store.settings.defaultEffort)
                    }
                }
                if let ms = store.settings.lastFirstTextMs {
                    FormDivider()
                    FormRow("Last run") {
                        Text(String(format: "First words after %.1f s", Double(ms) / 1000))
                            .font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText)
                    }
                }
            } footer: {
                LocalEngineModelNote()
            }

            FormSection("Privacy", footer: privacyText + " No server of ours, no tracking; logs never contain your text.") {
                FormRow("Privacy notice") {
                    Button("Open…") { NSWorkspace.shared.open(SetupMonitor.privacyURL) }
                        .buttonStyle(SecondaryButtonStyle(height: 28))
                        .fixedSize()
                }
            }
        }
        .task { if fixedStatus == nil { status = await ClaudeCodeEngine.status() } }
    }

    /// Where the draft goes with the chosen engine, in one sentence.
    private var privacyText: String {
        switch store.settings.engine {
        case .local: return "With a local model, your drafts stay on this Mac."
        case .claudeCode, .apiKey: return "Takes sends your draft only to Anthropic, under your own account."
        case .chatGPT: return "Takes sends your draft to OpenAI under your own ChatGPT plan."
        case .provider:
            let provider = Provider.current(store.settings)
            return provider.id == "custom" ? "Takes sends your draft to the server you added, under your own account."
                                           : "Takes sends your draft to \(provider.name) under your own account."
        }
    }

    private func muted(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
    }

    // MARK: Claude Code

    private var claudeStatus: (found: Bool, signedIn: Bool, plan: String?)? { fixedStatus ?? status }

    @ViewBuilder private var claudeCodeBadge: some View {
        if installer.state.isBusy {
            StatusBadge(text: "Installing…", good: false)
        } else if let status = claudeStatus {
            if !status.found {
                StatusBadge(text: "Not installed", good: false)
            } else if status.signedIn {
                StatusBadge(text: "Signed in" + (status.plan.map { " · \($0.capitalized) plan" } ?? ""), good: true)
            } else {
                StatusBadge(text: "Not signed in", good: false)
            }
        } else {
            ProgressView().controlSize(.mini).accessibilityLabel("Checking Claude Code")
        }
    }

    private var claudeCodeDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let progress = installer.state.progress {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(progress).font(.system(size: 12)).foregroundStyle(Theme.text)
                }
                Text("This takes about a minute. Then Terminal opens so you can sign in.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            } else if let status = claudeStatus, !status.found {
                if let error = installer.state.error {
                    Text(error).font(.system(size: 12)).foregroundStyle(Theme.avoidText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Claude Code isn't on this Mac. Takes can install it for you from Anthropic; no password needed.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Button("Install Claude Code…", action: install)
                        .buttonStyle(PrimaryButtonStyle(height: 28))
                        .fixedSize()
                    if installer.state.error != nil {
                        Button("Install it yourself") { NSWorkspace.shared.open(ClaudeInstaller.manualURL) }
                            .buttonStyle(SecondaryButtonStyle(height: 28))
                            .fixedSize()
                    }
                }
            } else if let status = claudeStatus, !status.signedIn {
                Text("Sign in once: Terminal opens and takes you to your browser. Then press Check again.")
                    .font(.system(size: 12)).foregroundStyle(Theme.avoidText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Sign in to Claude", action: ClaudeCodeEngine.openSignIn)
                        .buttonStyle(PrimaryButtonStyle(height: 28))
                        .fixedSize()
                    checkAgain
                }
            } else {
                checkAgain
            }
        }
    }

    private var checkAgain: some View {
        Button("Check again") { Task { status = nil; status = await ClaudeCodeEngine.status() } }
            .buttonStyle(SecondaryButtonStyle(height: 26))
            .fixedSize()
    }

    /// Installs Claude Code after the person confirms, then opens sign-in.
    private func install() {
        Task {
            guard await installer.installAfterConfirming() else { return }
            status = await ClaudeCodeEngine.status()
            if status?.signedIn == false { ClaudeCodeEngine.openSignIn() }
        }
    }

    // MARK: API key

    @ViewBuilder private var apiKeyDetails: some View {
        if hasKey {
            HStack(spacing: 10) {
                Text("Key saved in your keychain").font(.system(size: 13)).foregroundStyle(Theme.doText)
                Button("Remove Key…") {
                    guard confirmDestructive("Remove your Anthropic API key?",
                                             message: "Takes deletes it from your keychain. You'll need to paste it again to write with it.",
                                             button: "Remove Key") else { return }
                    Keychain.setAPIKey(nil)
                    hasKey = false
                }
                .buttonStyle(DestructiveButtonStyle(height: 26))
            }
        } else {
            HStack(spacing: 8) {
                StyledTextField(placeholder: "Paste your key", text: $keyInput, secure: true, height: 30, onSubmit: saveKey)
                    .frame(maxWidth: 360)
                    .accessibilityLabel("Anthropic API key")
                Button("Save", action: saveKey)
                    .buttonStyle(SecondaryButtonStyle(height: 30))
                    .fixedSize()
                    .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func saveKey() {
        Keychain.setAPIKey(keyInput.trimmingCharacters(in: .whitespacesAndNewlines))
        keyInput = ""
        hasKey = Keychain.apiKey != nil
    }
}

/// One engine as a compact radio row: its name and status on one line. The selected row also shows a line about
/// it and its key field or sign-in.
private struct EngineRow<Status: View, Details: View>: View {
    @ObservedObject var store = Store.shared
    let engine: EngineKind
    let title: String
    let summary: String
    @ViewBuilder var status: Status
    @ViewBuilder var details: Details

    private var selected: Bool { store.settings.engine == engine }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().strokeBorder(selected ? Theme.accent : Theme.dashed, lineWidth: selected ? 5 : 1.5)
                }
                .frame(width: 16, height: 16)
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular)).foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                status
            }
            .frame(minHeight: 24)
            .contentShape(Rectangle())
            .onTapGesture { select() }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
            .accessibilityValue(selected ? "Selected" : "Not selected")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { select() }

            if selected {
                VStack(alignment: .leading, spacing: 10) {
                    Text(summary)
                        .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    details
                }
                .padding(.leading, 28)
                .padding(.bottom, 4)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Theme.formSelectedRow : Color.clear)
    }

    private func select() {
        guard !selected else { return }
        withAnimation(Motion.animation()) { store.settings.engine = engine }
    }
}
