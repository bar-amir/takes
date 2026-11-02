import AppKit
import SwiftUI

/// The "Other provider" card in Settings › Engine: pick a provider, paste a key (kept in the keychain), pick a model
/// from the provider's list (or type one when there's no list), and test it. Text only: no provider logos.
struct ProviderEngineSettings: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var models = ProviderModels.shared
    let selected: Bool

    @State private var keyInput = ""
    @State private var keyNote: String?
    @State private var addressInput = ""
    @State private var addressError: String?
    @State private var modelInput = ""

    private var provider: Provider { Provider.current(store.settings) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Other provider").font(.system(size: 15, weight: .semibold))
                badge
            }
            Text("Your own API key for OpenAI, Gemini, OpenRouter, Groq or Mistral, or any OpenAI-compatible server. Billed by the provider under your account.")
                .font(.system(size: 13)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            if selected {
                details.padding(.top, 4)
            }
        }
        .task { if !models.checked { await models.refresh() } }
    }

    @ViewBuilder private var badge: some View {
        if models.state == .checking || (!models.checked && selected) {
            ProgressView().controlSize(.mini).accessibilityLabel("Checking your key")
        } else if let badge = models.badge(store.settings) {
            Text(badge.text)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .foregroundStyle(badge.good ? Theme.doText : Theme.avoidText)
                .background(Capsule().fill(badge.good ? Theme.doFill : Theme.avoidFill))
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                LabeledMenu(label: "Provider",
                            options: Provider.known.map { (value: $0.id, title: $0.name) } + [(value: Provider.customID, title: "Custom address")],
                            selection: Binding(get: { provider.id }, set: { id in resetInputs(); models.select(id) }))
                if let console = provider.consoleURL {
                    Button("Get a key") { NSWorkspace.shared.open(console) }
                        .buttonStyle(SecondaryButtonStyle(height: 30))
                        .accessibilityHint("Opens \(console.host ?? "the provider's site") in your browser")
                }
            }
            if provider.isCustom { address }
            hint(provider.dataNote)
            if provider.id == Provider.gemini.id {
                hint("Google requires a key on a project with billing on in the EEA, Switzerland and the UK.")
            }
            if models.state != .noAddress {
                keyRow
                if models.hasKey { modelSection }
            }
        }
    }

    // MARK: Parts

    private var address: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StyledTextField(placeholder: "https://llm.example.com/v1", text: $addressInput, height: 30, onSubmit: saveAddress)
                    .accessibilityLabel("Server address")
                Button("Save", action: saveAddress)
                    .buttonStyle(SecondaryButtonStyle(height: 30))
                    .disabled(addressInput.trimmingCharacters(in: .whitespaces).isEmpty || addressInput == store.settings.providerBaseURL)
            }
            if let addressError { hint(addressError, warning: true) }
        }
        .onAppear { if addressInput.isEmpty { addressInput = store.settings.providerBaseURL } }
    }

    @ViewBuilder private var keyRow: some View {
        if models.hasKey {
            HStack(spacing: 10) {
                Text("Saved in your keychain").font(.system(size: 13)).foregroundStyle(Theme.doText)
                Button("Remove") { keyNote = nil; models.removeKey() }
                    .buttonStyle(SecondaryButtonStyle(height: 26))
                    .accessibilityLabel("Remove the \(provider.name) key")
            }
        } else {
            HStack(spacing: 8) {
                StyledTextField(placeholder: provider.keyPlaceholder, text: $keyInput, secure: true, height: 30, onSubmit: saveKey)
                    .accessibilityLabel("\(provider.name) API key")
                Button("Save", action: saveKey)
                    .buttonStyle(SecondaryButtonStyle(height: 30))
                    .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        if let note = keyNote ?? provider.keyNote(keyInput) { hint(note, warning: true) }
    }

    @ViewBuilder private var modelSection: some View {
        switch models.state {
        case .checking, .idle:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                hint("Looking up \(provider.name)'s models…")
            }
        case .refused(let message):
            hint(message + " Or remove it and paste a new one.", warning: true)
        case .ready where !models.models.isEmpty:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    LabeledMenu(label: "Model",
                                options: models.modelOptions(picked: store.settings.providerModel).map { (value: $0, title: $0) },
                                selection: Binding(get: { store.settings.providerModel },
                                                   set: { store.settings.providerModel = $0; models.test = .idle }))
                    testButton
                }
                if !store.settings.providerModel.isEmpty, !models.models.contains(store.settings.providerModel) {
                    hint("\(provider.name) doesn't list \(store.settings.providerModel) any more. Pick another.", warning: true)
                }
                testResult
            }
        case .ready, .failed, .noKey, .noAddress:
            VStack(alignment: .leading, spacing: 8) {
                if case .failed(let message) = models.state {
                    hint("Couldn't load the model list. \(message)", warning: true)
                } else {
                    hint("\(provider.name) didn't list any models. Type the model ID instead.")
                }
                HStack(spacing: 8) {
                    StyledTextField(placeholder: "Model ID", text: $modelInput, height: 30, onSubmit: saveModel)
                        .accessibilityLabel("Model ID")
                    Button("Save", action: saveModel)
                        .buttonStyle(SecondaryButtonStyle(height: 30))
                        .disabled(modelInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    testButton
                    Button("Check again") { Task { await models.refresh() } }
                        .buttonStyle(SecondaryButtonStyle(height: 30))
                }
                testResult
            }
            .onAppear { if modelInput.isEmpty { modelInput = store.settings.providerModel } }
        }
    }

    private var testButton: some View {
        Button("Test") { models.runTest() }
            .buttonStyle(SecondaryButtonStyle(height: 30))
            .disabled(models.test == .running || store.settings.providerModel.isEmpty)
            .accessibilityHint("Sends \(provider.name) a one-word request")
    }

    @ViewBuilder private var testResult: some View {
        switch models.test {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                hint("Asking \(store.settings.providerModel)…")
            }
        case .passed(let ms):
            Text(String(format: "Works. Answered in %.1f s.", Double(ms) / 1000))
                .font(.system(size: 12)).foregroundStyle(Theme.doText)
        case .failed(let message):
            hint(message, warning: true)
        }
    }

    private func hint(_ text: String, warning: Bool = false) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(warning ? Theme.avoidText : Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Actions

    private func resetInputs() {
        keyInput = ""
        keyNote = nil
        addressError = nil
        addressInput = ""
        modelInput = ""
    }

    private func saveKey() {
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        keyNote = provider.keyNote(key)
        keyInput = ""
        models.saveKey(key)
    }

    private func saveAddress() {
        guard let url = ProviderEndpoint.normalize(addressInput) else {
            addressError = "Use an https address on the internet, such as https://llm.example.com/v1. Servers on this Mac go in the Local model card."
            return
        }
        addressError = nil
        addressInput = url
        store.settings.providerBaseURL = url
        store.settings.providerModel = ""
        Task {
            await models.refresh()
            await SetupMonitor.shared.refreshEngine()
        }
    }

    private func saveModel() {
        let model = modelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }
        store.settings.providerModel = model
        models.test = .idle
        Task { await SetupMonitor.shared.refreshEngine() }
    }
}

/// What the onboarding engine step shows under the "Other provider" option: the provider, the key field and which
/// model was picked, so a new user can finish the step without opening Settings.
struct ProviderOnboardingDetail: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var store = Store.shared
    @ObservedObject var models = ProviderModels.shared
    @State private var keyInput = ""

    private var provider: Provider { Provider.current(store.settings) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !provider.isCustom {
                HStack(spacing: 10) {
                    LabeledMenu(label: "Provider", options: Provider.known.map { (value: $0.id, title: $0.name) },
                                selection: Binding(get: { provider.id }, set: { keyInput = ""; models.select($0) }))
                    if let console = provider.consoleURL {
                        Button("Get a key") { NSWorkspace.shared.open(console) }
                            .buttonStyle(SecondaryButtonStyle(height: 28))
                            .accessibilityHint("Opens \(console.host ?? "the provider's site") in your browser")
                    }
                }
            }
            if models.state == .noAddress {
                StepNote("Set your server's address in Settings › Engine.")
            } else if !models.hasKey {
                StyledTextField(placeholder: provider.keyPlaceholder, text: $keyInput, secure: true, height: 34, onSubmit: saveKey)
                    .accessibilityLabel("\(provider.name) API key")
                if let note = provider.keyNote(keyInput) {
                    Text(note).font(.system(size: 12)).foregroundStyle(Theme.avoidText).fixedSize(horizontal: false, vertical: true)
                }
                StepNote("Press Return to save it in your keychain. \(provider.dataNote)")
            } else {
                StepNote(status)
            }
        }
        .padding(.top, 4)
        .task { if !models.checked { await models.refresh() } }
    }

    private var status: String {
        switch models.state {
        case .checking, .idle: return "Key saved. Looking up \(provider.name)'s models…"
        case .refused(let message): return message + " Change it in Settings › Engine."
        case .failed: return "Key saved, but the model list didn't load. Type a model ID in Settings › Engine."
        case .ready, .noKey, .noAddress:
            return store.settings.providerModel.isEmpty
                ? "Key saved. Pick a model in Settings › Engine."
                : "Key saved. Takes will write with \(store.settings.providerModel); change it any time in Settings › Engine."
        }
    }

    private func saveKey() {
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        keyInput = ""
        models.saveKey(key)
    }
}
