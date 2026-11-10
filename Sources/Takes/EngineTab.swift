import AppKit
import SwiftUI

/// Settings › Model: where takes are written (one compact row per engine; the selected one shows its key field or
/// sign-in), the defaults for new presets, and where drafts go.
struct ModelTab: View {
    @ObservedObject var store = Store.shared
    @State private var status: ClaudeCodeEngine.Status?
    @State private var keyInput = ""
    @State private var hasKey = Keychain.apiKey != nil
    /// Anthropic is being asked about the key just pasted.
    @State private var checkingKey = false
    /// What saving the key found; nil when it was saved and works.
    @State private var keySave: APIKeySave?
    @ObservedObject var installer = ClaudeInstaller.shared
    /// For snapshots: shown instead of asking Claude Code.
    var fixedStatus: ClaudeCodeEngine.Status?
    /// For snapshots of the whole window, which build this tab themselves: shown instead of asking Claude Code.
    static var snapshotStatus: ClaudeCodeEngine.Status?

    var body: some View {
        SettingsPage {
            FormSection(header: String(localized: "Where your takes are written")) {
                EngineRow(engine: .claudeCode, title: String(localized: "Claude Code on this Mac"),
                          summary: String(localized: "Uses your Claude subscription; each run counts toward its usage limits.")) {
                    claudeCodeBadge
                } details: { claudeCodeDetails }
                FormDivider(inset: 40)
                EngineRow(engine: .apiKey, title: String(localized: "Anthropic API key"),
                          summary: String(localized: "Pay per use, billed by Anthropic. Usually a cent or two per run, more with Opus or more takes. Takes doesn't cap your spending; set a limit in the Anthropic Console.")) {
                    if hasKey { StatusBadge(text: String(localized: "Key saved"), good: true) } else { muted(String(localized: "Pay per use")) }
                } details: { apiKeyDetails }
                FormDivider(inset: 40)
                EngineRow(engine: .chatGPT, title: String(localized: "Your ChatGPT plan"),
                          summary: String(localized: "Sign in with ChatGPT and write with the models in your Plus or Pro plan. No extra cost; your plan's limits apply.")) {
                    ChatGPTEngineBadge()
                } details: { ChatGPTEngineSettings() }
                FormDivider(inset: 40)
                EngineRow(engine: .provider, title: String(localized: "Other provider"),
                          summary: String(localized: "Your own API key for OpenAI, Gemini, OpenRouter, Groq or Mistral, or any OpenAI-compatible server. Billed by the provider under your account.")) {
                    ProviderEngineBadge()
                } details: { ProviderEngineSettings() }
                FormDivider(inset: 40)
                EngineRow(engine: .local, title: String(localized: "Local model"),
                          summary: String(localized: "Runs on this Mac with Ollama or LM Studio, so your drafts never leave it. Small models write plainer takes than Claude. It's free, but uses this Mac's memory and battery.")) {
                    LocalEngineBadge()
                } details: { LocalEngineSettings() }
            } footer: {
                if store.settings.engineNeedsChoice {
                    Text(SetupMonitor.needsChoiceNote).foregroundStyle(Theme.avoidText)
                }
            }

            // Model and effort are Claude's; with a one-model engine only the number of takes applies.
            FormSection(String(localized: "Defaults for new presets")) {
                FormRow(store.settings.engine.isClaude ? String(localized: "Takes · Model · Effort") : String(localized: "Takes")) {
                    HStack(spacing: 6) {
                        MenuPicker(options: (1...5).map { (value: $0, title: "\($0)") }, selection: $store.settings.defaultTakes)
                        if store.settings.engine.isClaude {
                            MenuPicker(options: Models.all.map { (value: $0.id, title: $0.label) }, selection: $store.settings.defaultModel)
                            MenuPicker(options: Models.efforts.map { (value: $0, title: Models.effortLabel($0)) }, selection: $store.settings.defaultEffort)
                        }
                    }
                }
                if let ms = store.settings.lastFirstTextMs {
                    FormDivider()
                    FormRow(String(localized: "Last run")) {
                        Text(String(format: NSLocalizedString("First words after %.1f s", comment: ""), locale: .current, Double(ms) / 1000))
                            .font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText)
                    }
                }
            }

            FormSection(String(localized: "Privacy"),
                        footer: privacyText + " " + String(localized: "No server of ours, no tracking; logs never contain your text.")) {
                FormRow(String(localized: "Privacy notice")) {
                    Button("Open…") { NSWorkspace.shared.open(SetupMonitor.privacyURL) }
                        .buttonStyle(SecondaryButtonStyle(height: 28))
                        .fixedSize()
                }
            }
        }
        // Snapshots never run `claude`.
        .task { if fixedStatus == nil, !Store.readOnly { status = await ClaudeCodeEngine.status() } }
    }

    /// Where the draft goes with the chosen engine, in one sentence.
    private var privacyText: String {
        // The engine reads as Claude Code until one is picked, but nothing is sent before that.
        if store.settings.engineNeedsChoice { return String(localized: "Nothing is sent until you pick a model.") }
        switch store.settings.engine {
        case .local: return String(localized: "With a local model, your drafts stay on this Mac.")
        case .claudeCode, .apiKey: return String(localized: "Takes sends your draft only to Anthropic, under your own account.")
        case .chatGPT: return String(localized: "Takes sends your draft to OpenAI under your own ChatGPT plan.")
        case .provider:
            let provider = Provider.current(store.settings)
            return provider.id == "custom" ? String(localized: "Takes sends your draft to the server you added, under your own account.")
                                           : String(localized: "Takes sends your draft to \(provider.name) under your own account.")
        }
    }

    private func muted(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
    }

    // MARK: Claude Code

    private var claudeStatus: ClaudeCodeEngine.Status? { fixedStatus ?? status ?? (Store.readOnly ? Self.snapshotStatus : nil) }

    @ViewBuilder private var claudeCodeBadge: some View {
        if installer.state.isBusy {
            StatusBadge(text: String(localized: "Installing…"), good: false)
        } else if let status = claudeStatus {
            let badge = ClaudeCodeAction.badge(for: status)
            StatusBadge(text: badge.text, good: badge.good)
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
            } else if claudeStatus?.state == .notInstalled {
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
            } else if let state = claudeStatus?.state, state != .ready {
                if let note = ClaudeCodeAction.note(for: state) {
                    Text(note)
                        .font(.system(size: 12)).foregroundStyle(state == .stillLooking ? Theme.secondaryText : Theme.avoidText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    switch ClaudeCodeAction(state) {
                    case .update:
                        Button(ClaudeCodeAction.update.title, action: ClaudeCodeEngine.openUpdate)
                            .buttonStyle(PrimaryButtonStyle(height: 28))
                            .fixedSize()
                    case .signIn:
                        Button(ClaudeCodeAction.signIn.title, action: ClaudeCodeEngine.openSignIn)
                            .buttonStyle(PrimaryButtonStyle(height: 28))
                            .fixedSize()
                    default:
                        EmptyView()
                    }
                    checkAgain
                }
            } else {
                checkAgain
            }
        }
    }

    private var checkAgain: some View {
        Button("Check again") {
            Task {
                status = nil
                status = await ClaudeCodeEngine.status()
                // Setup and the menu-bar icon follow the new answer too.
                if store.settings.engine == .claudeCode { await SetupMonitor.shared.refreshEngine() }
            }
        }
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
                    guard confirmDestructive(String(localized: "Remove your Anthropic API key?"),
                                             message: String(localized: "Takes deletes it from your keychain. You'll need to paste it again to write with it."),
                                             button: String(localized: "Remove Key")) else { return }
                    keySave = Keychain.setAPIKey(nil) ? nil : .notRemoved
                    hasKey = Keychain.apiKey != nil
                    Task { await SetupMonitor.shared.refreshEngine() }
                }
                .buttonStyle(DestructiveButtonStyle(height: 26))
            }
        } else {
            HStack(spacing: 8) {
                StyledTextField(placeholder: String(localized: "Paste your key"), text: $keyInput, secure: true, height: 30, onSubmit: saveKey)
                    .frame(maxWidth: 360)
                    .accessibilityLabel("Anthropic API key")
                if checkingKey {
                    ProgressView().controlSize(.small).accessibilityLabel("Checking your key")
                } else {
                    Button("Save", action: saveKey)
                        .buttonStyle(SecondaryButtonStyle(height: 30))
                        .fixedSize()
                        .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        if let note = keySave?.note {
            Text(note.text).font(.system(size: 12)).foregroundStyle(note.problem ? Theme.avoidText : Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Asks Anthropic about the key (no tokens spent), then saves it unless it was refused.
    private func saveKey() {
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !checkingKey else { return }
        checkingKey = true
        keySave = nil
        Task {
            let result = await APIKeySave.save(key, check: { await APIKeyCheckCache.shared.check($0) }, store: { Keychain.setAPIKey($0) })
            checkingKey = false
            keySave = result
            if result != .notSaved { keyInput = "" }
            hasKey = Keychain.apiKey != nil
            await SetupMonitor.shared.refreshEngine()
        }
    }
}

/// What Anthropic last said about a key, kept in memory under a hash of the key, so saving a key and the setup check
/// after it make one request between them, and setup doesn't ask about the same key on every check. An answer that
/// couldn't be had (offline) is asked for again after `retryAfter`.
@MainActor
final class APIKeyCheckCache {
    static let shared = APIKeyCheckCache()
    static let retryAfter: TimeInterval = 5 * 60

    /// Asks Anthropic; tests pass a fake.
    var ask: (String) async -> APIKeyCheck = { await APIEngine.checkKey($0) }
    private var last: (key: Int, at: Date, answer: APIKeyCheck)?

    func check(_ key: String, now: Date = Date()) async -> APIKeyCheck {
        if let last, last.key == key.hashValue {
            if case .couldNotCheck = last.answer, now.timeIntervalSince(last.at) >= Self.retryAfter {
                // Asked again below.
            } else {
                return last.answer
            }
        }
        let answer = await ask(key)
        last = (key.hashValue, now, answer)
        return answer
    }

    func forget() { last = nil }
}

/// Saving an Anthropic API key, from Settings or onboarding. Anthropic is asked about the key first (no tokens
/// spent): a key it refuses isn't kept, and a key that couldn't be checked (offline) is kept and said so.
enum APIKeySave: Equatable {
    case saved
    case savedUnchecked(String)
    case refused(String)
    /// The keychain didn't take it.
    case notSaved
    /// Remove Key: the keychain wouldn't delete it.
    case notRemoved

    static func save(_ key: String, check: (String) async -> APIKeyCheck, store: (String) -> Bool) async -> APIKeySave {
        let result = await check(key)
        if case .invalid(let message) = result { return .refused(message) }
        guard store(key) else { return .notSaved }
        if case .couldNotCheck(let message) = result { return .savedUnchecked(message) }
        return .saved
    }

    static let keychainRefused = String(localized: "Takes couldn't save the key to your keychain. Try again.")
    static let keychainKept = String(localized: "Takes couldn't remove the key from your keychain. Try again.")

    /// The line under the key field, and whether it's a problem; nil when the key was saved and works.
    var note: (text: String, problem: Bool)? {
        switch self {
        case .saved: nil
        case .savedUnchecked(let why): (String(localized: "Key saved, but not checked. \(why)"), false)
        case .refused(let why): (why, true)
        case .notSaved: (Self.keychainRefused, true)
        case .notRemoved: (Self.keychainKept, true)
        }
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

    /// An engine saved by a newer version that this one doesn't know reads as Claude Code; no row is picked then.
    private var selected: Bool { store.settings.engine == engine && !store.settings.engineNeedsChoice }

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
