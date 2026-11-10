import AppKit
import SwiftUI

/// The "Other provider" row's status in Settings › Model: the key and model it would use.
struct ProviderEngineBadge: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var models = ProviderModels.shared

    var body: some View {
        Group {
            if models.state == .checking {
                ProgressView().controlSize(.mini).accessibilityLabel("Checking your key")
            } else if let badge = models.badge(store.settings) {
                StatusBadge(text: badge.text, good: badge.good)
            } else {
                Text("OpenAI, Gemini and more").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            }
        }
        .task { if !models.checked { await models.refresh() } }
    }
}

/// The selected "Other provider" row in Settings › Model: pick a provider, paste a key (kept in the keychain), pick a
/// model from the provider's list (or type one when there's no list), and test it. Text only: no provider logos.
struct ProviderEngineSettings: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var models = ProviderModels.shared

    @State private var keyInput = ""
    @State private var keyNote: String?
    @State private var addressInput = ""
    @State private var addressError: String?
    @State private var modelInput = ""

    private var provider: Provider { Provider.current(store.settings) }

    var body: some View {
        details
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                LabeledMenu(label: String(localized: "Provider"),
                            options: Provider.known.map { (value: $0.id, title: $0.name) } + [(value: Provider.customID, title: String(localized: "Custom address"))],
                            selection: Binding(get: { provider.id }, set: { id in resetInputs(); models.select(id) }))
                if let console = provider.consoleURL {
                    Button("Get a key") { NSWorkspace.shared.open(console) }
                        .buttonStyle(SecondaryButtonStyle(height: 30))
                        .accessibilityHint("Opens \(console.host ?? String(localized: "the provider's site")) in your browser")
                }
            }
            if provider.isCustom { address }
            hint(provider.dataNote)
            if provider.id == Provider.gemini.id {
                hint(String(localized: "Google requires a key on a project with billing on in the EEA, Switzerland and the UK."))
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
                Text("Key saved in your keychain").font(.system(size: 13)).foregroundStyle(Theme.doText)
                Button("Remove Key…") {
                    guard confirmDestructive(String(localized: "Remove your \(provider.name) key?"),
                                             message: String(localized: "Takes deletes it from your keychain. You'll need to paste it again to write with \(provider.name)."),
                                             button: String(localized: "Remove Key")) else { return }
                    keyNote = nil
                    models.removeKey()
                }
                .buttonStyle(DestructiveButtonStyle(height: 26))
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
                hint(String(localized: "Looking up \(provider.name)'s models…"))
            }
        case .refused(let message):
            hint(String(localized: "\(message) Or remove it and paste a new one."), warning: true)
        case .ready where !models.models.isEmpty:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    LabeledMenu(label: String(localized: "Model"),
                                options: models.modelOptions(picked: store.settings.providerModel).map { (value: $0, title: $0) },
                                selection: Binding(get: { store.settings.providerModel },
                                                   set: { store.settings.providerModel = $0; models.test = .idle }))
                    testButton
                }
                if !store.settings.providerModel.isEmpty, !models.models.contains(store.settings.providerModel) {
                    hint(String(localized: "\(provider.name) doesn't list \(store.settings.providerModel) any more. Pick another."), warning: true)
                }
                testResult
            }
        case .ready, .failed, .noKey, .noAddress:
            VStack(alignment: .leading, spacing: 8) {
                if case .failed(let message) = models.state {
                    // A typed model that answered the test is what counts; the list failing isn't a problem then.
                    if case .passed = models.test {
                        hint(String(localized: "\(provider.name) didn't list any models. Type the model ID instead."))
                    } else {
                        hint(String(localized: "Couldn't load the model list. \(message)"), warning: true)
                    }
                } else {
                    hint(String(localized: "\(provider.name) didn't list any models. Type the model ID instead."))
                }
                HStack(spacing: 8) {
                    StyledTextField(placeholder: String(localized: "Model ID"), text: $modelInput, height: 30, onSubmit: saveModel)
                        .accessibilityLabel("Model ID")
                    Button("Save", action: saveModel)
                        .buttonStyle(SecondaryButtonStyle(height: 30))
                        .disabled(modelInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    testButton
                    Button("Check again") {
                        Task {
                            await models.refresh(force: true)
                            await SetupMonitor.shared.refreshEngine()
                        }
                    }
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
                hint(String(localized: "Asking \(store.settings.providerModel)…"))
            }
        case .passed(let ms):
            Text(String(format: NSLocalizedString("Works. Answered in %.1f s.", comment: ""), locale: .current, Double(ms) / 1000))
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
        // Whether the provider takes the key shows as the model list loads (or "Key refused").
        if !models.saveKey(key) { keyNote = APIKeySave.keychainRefused }
    }

    private func saveAddress() {
        guard let url = ProviderEndpoint.normalize(addressInput) else {
            addressError = String(localized: "Use an https address on the internet, such as https://llm.example.com/v1. Servers on this Mac go in the Local model row.")
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

/// What the onboarding engine step shows under the "Other provider" option: the provider (or a server address), the
/// key field, and the model, so a new user finishes the step here. The step's button saves the key or asks again.
struct ProviderOnboardingDetail: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var store = Store.shared
    @ObservedObject var models = ProviderModels.shared
    @State private var addressInput = ""
    @State private var addressError: String?
    @State private var modelInput = ""

    private var provider: Provider { Provider.current(store.settings) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                LabeledMenu(label: String(localized: "Provider"),
                            options: Provider.known.map { (value: $0.id, title: $0.name) } + [(value: Provider.customID, title: String(localized: "Custom address"))],
                            selection: Binding(get: { provider.id }, set: { id in
                                model.providerKeyInput = ""
                                model.providerKeyNotSaved = false
                                addressInput = ""
                                addressError = nil
                                model.selectProvider(id)
                            }))
                if let console = provider.consoleURL {
                    Button("Get a key") { NSWorkspace.shared.open(console) }
                        .buttonStyle(SecondaryButtonStyle(height: 28))
                        .accessibilityHint("Opens \(console.host ?? String(localized: "the provider's site")) in your browser")
                }
            }
            if provider.isCustom { address }
            if models.state == .noAddress {
                EmptyView()
            } else if !models.hasKey {
                StyledTextField(placeholder: provider.keyPlaceholder, text: $model.providerKeyInput, secure: true, height: 34,
                                onSubmit: model.primary)
                    .accessibilityLabel("\(provider.name) API key")
                if model.providerKeyNotSaved {
                    note(APIKeySave.keychainRefused, warning: true)
                } else if let warning = provider.keyNote(model.providerKeyInput) {
                    note(warning, warning: true)
                }
                StepNote(String(localized: "Press Return to save it in your keychain. \(provider.dataNote)"))
            } else {
                saved
            }
        }
        .padding(.top, 4)
        .onAppear { model.providerShown() }
    }

    private var address: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StyledTextField(placeholder: "https://llm.example.com/v1", text: $addressInput, height: 30, onSubmit: saveAddress)
                    .accessibilityLabel("Server address")
                Button("Save", action: saveAddress)
                    .buttonStyle(SecondaryButtonStyle(height: 30))
                    .disabled(addressInput.trimmingCharacters(in: .whitespaces).isEmpty || addressInput == store.settings.providerBaseURL)
            }
            if let addressError { note(addressError, warning: true) }
        }
        .onAppear { if addressInput.isEmpty { addressInput = store.settings.providerBaseURL } }
    }

    /// With a key saved: the model to write with, picked from the provider's list or typed when there's none.
    @ViewBuilder private var saved: some View {
        switch models.state {
        case .idle:
            // Not asked yet: the provider hears from Takes only after the button below.
            StepNote(String(localized: "Key saved in your keychain"))
        case .checking:
            StepNote(String(localized: "Key saved. Looking up \(provider.name)'s models…"))
        case .refused(let message):
            note(message, warning: true)
            Button("Remove Key…") {
                guard confirmDestructive(String(localized: "Remove your \(provider.name) key?"),
                                         message: String(localized: "Takes deletes it from your keychain. You'll need to paste it again to write with \(provider.name)."),
                                         button: String(localized: "Remove Key")) else { return }
                models.removeKey()
            }
            .buttonStyle(SecondaryButtonStyle(height: 28))
        case .ready where !models.models.isEmpty:
            LabeledMenu(label: String(localized: "Model"),
                        options: models.modelOptions(picked: store.settings.providerModel).map { (value: $0, title: $0) },
                        selection: Binding(get: { store.settings.providerModel }, set: { picked in
                            store.settings.providerModel = picked
                            Task { await SetupMonitor.shared.refreshEngine() }
                        }))
        case .ready, .failed, .noKey, .noAddress:
            if case .failed(let message) = models.state {
                note(String(localized: "Couldn't load the model list. \(message)"), warning: true)
            } else {
                StepNote(String(localized: "\(provider.name) didn't list any models. Type the model ID instead."))
            }
            HStack(spacing: 8) {
                StyledTextField(placeholder: String(localized: "Model ID"), text: $modelInput, height: 30, onSubmit: saveModel)
                    .accessibilityLabel("Model ID")
                Button("Save", action: saveModel)
                    .buttonStyle(SecondaryButtonStyle(height: 30))
                    .disabled(modelInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .onAppear { if modelInput.isEmpty { modelInput = store.settings.providerModel } }
        }
    }

    private func note(_ text: String, warning: Bool) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(warning ? Theme.avoidText : Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func saveAddress() {
        guard let url = ProviderEndpoint.normalize(addressInput) else {
            addressError = String(localized: "Use an https address on the internet, such as https://llm.example.com/v1. Servers on this Mac go in the Local model row.")
            return
        }
        addressError = nil
        addressInput = url
        store.settings.providerBaseURL = url
        store.settings.providerModel = ""
        // The server hears from Takes only after the step's button.
        model.providerShown()
    }

    private func saveModel() {
        let picked = modelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !picked.isEmpty else { return }
        store.settings.providerModel = picked
        Task { await SetupMonitor.shared.refreshEngine() }
    }
}
