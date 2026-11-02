import AppKit
import SwiftUI

/// The "Local model" card in Settings › Engine: finds Ollama or LM Studio, lists installed models,
/// and says plainly what to do when nothing is running or nothing is installed. It never downloads anything.
struct LocalEngineSettings: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var local = LocalModels.shared
    let selected: Bool

    enum TestState: Equatable { case idle, running, passed(Int), failed(String) }
    @State var test = TestState.idle
    @State private var editingAddress = false
    @State private var addressInput = ""
    @State private var addressError: String?
    @State private var copied = false

    private var baseURL: String { store.settings.localBaseURL }
    private var current: LocalModels.Server? { local.server(at: baseURL) }
    private var kind: LocalServerKind { LocalServerKind.guess(baseURL) ?? .ollama }
    private var serverName: String { LocalServerKind.displayName(baseURL) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Local model").font(.system(size: 15, weight: .semibold))
                badge
            }
            Text("Runs on this Mac with Ollama or LM Studio, so your drafts never leave it. Small models write plainer takes than Claude. It's free, but uses this Mac's memory and battery.")
                .font(.system(size: 13)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            if selected {
                details.padding(.top, 4)
            }
        }
        .task { if !local.checked { await local.refresh() } }
    }

    @ViewBuilder private var badge: some View {
        if !local.checked || (local.checking && current == nil) {
            ProgressView().controlSize(.mini).accessibilityLabel("Looking for local models")
        } else {
            let (text, good): (String, Bool) = {
                guard let models = current?.models else { return ("Not running", false) }
                if models.isEmpty { return ("\(serverName) · no models", false) }
                return ("\(serverName) · \(models.count) model\(models.count == 1 ? "" : "s")", true)
            }()
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .foregroundStyle(good ? Theme.doText : Theme.avoidText)
                .background(Capsule().fill(good ? Theme.doFill : Theme.avoidFill))
        }
    }

    @ViewBuilder private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !local.checked {
                hint("Looking for Ollama and LM Studio on this Mac…")
            } else if let models = current?.models {
                if models.isEmpty { noModels } else { modelPicker(models) }
            } else if let other = local.running.first(where: { $0.baseURL != baseURL }) {
                hint("\(serverName) isn't running at \(baseURL), but \(other.name) is.")
                Button("Use \(other.name)") { use(other) }.buttonStyle(PrimaryButtonStyle(height: 30))
            } else {
                notRunning
            }
            footer
        }
    }

    // MARK: States

    private var notRunning: some View {
        VStack(alignment: .leading, spacing: 10) {
            hint(kind == .ollama
                 ? (kind.appURL == nil && LocalServerKind.ollamaCommand != nil
                    ? "Ollama isn't running. Start it with “ollama serve” in Terminal, then check again. LM Studio works too: start its local server."
                    : "Ollama isn't running. Open it, or install it from ollama.com. LM Studio works too: start its local server.")
                 : "LM Studio's server isn't running. In LM Studio, load a model and start the server, then check again.",
                 warning: true)
            HStack(spacing: 8) {
                if kind == .ollama, kind.appURL == nil, LocalServerKind.ollamaCommand != nil {
                    copyButton("ollama serve")
                } else if let app = kind.appURL {
                    Button("Open \(kind.name)") {
                        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            await local.refresh()
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(height: 30))
                } else {
                    Button("Get \(kind.name)") { NSWorkspace.shared.open(kind.website) }
                        .buttonStyle(PrimaryButtonStyle(height: 30))
                        .accessibilityHint("Opens \(kind.website.host ?? "") in your browser")
                }
            }
        }
    }

    private var noModels: some View {
        VStack(alignment: .leading, spacing: 10) {
            if kind == .ollama {
                hint("Ollama is running but has no models yet. Download one in Terminal, then check again. \(LocalServerKind.suggestedOllamaModel) is small (about 2 GB) and quick.",
                     warning: true)
                copyButton("ollama pull \(LocalServerKind.suggestedOllamaModel)")
            } else {
                hint("\(serverName) is running but has no model loaded. Download and load one there, then check again.", warning: true)
            }
        }
    }

    private func modelPicker(_ models: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 18) {
                if local.running.count > 1 {
                    LabeledMenu(label: "Server",
                                options: local.running.map { (value: $0.baseURL, title: $0.name) },
                                selection: Binding(get: { baseURL },
                                                   set: { url in if let server = local.server(at: url) { use(server) } }))
                }
                HStack(spacing: 10) {
                    LabeledMenu(label: "Model",
                                options: LocalModels.shared.modelOptions(at: baseURL, picked: store.settings.localModel)
                                    .map { (value: $0, title: LocalModelList.label($0)) },
                                selection: Binding(get: { store.settings.localModel },
                                                   set: { store.settings.localModel = $0; test = .idle }))
                    Button("Test") { runTest() }
                        .buttonStyle(SecondaryButtonStyle(height: 30))
                        .disabled(test == .running || store.settings.localModel.isEmpty)
                        .accessibilityHint("Asks the model for a one-word answer")
                }
            }
            if !store.settings.localModel.isEmpty, !models.contains(store.settings.localModel) {
                hint("\(LocalModelList.label(store.settings.localModel)) isn't installed in \(serverName) any more. Pick another.", warning: true)
            }
            testResult
        }
    }

    @ViewBuilder private var testResult: some View {
        switch test {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                hint("Asking \(LocalModelList.label(store.settings.localModel))… the first run can take a while as it loads.")
            }
        case .passed(let ms):
            Text(String(format: "Works. Answered in %.1f s.", Double(ms) / 1000))
                .font(.system(size: 12)).foregroundStyle(Theme.doText)
        case .failed(let message):
            hint(message, warning: true)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("Check again") { Task { await local.refresh() } }
                    .buttonStyle(SecondaryButtonStyle(height: 26))
                    .disabled(local.checking)
                if !editingAddress {
                    Button("Use another address…") {
                        addressInput = baseURL
                        addressError = nil
                        editingAddress = true
                    }
                    .buttonStyle(SecondaryButtonStyle(height: 26))
                }
            }
            if editingAddress {
                HStack(spacing: 8) {
                    StyledTextField(placeholder: "http://localhost:11434/v1", text: $addressInput, height: 30, onSubmit: saveAddress)
                        .accessibilityLabel("Server address")
                    Button("Save", action: saveAddress).buttonStyle(SecondaryButtonStyle(height: 30))
                    Button("Cancel") { editingAddress = false }.buttonStyle(SecondaryButtonStyle(height: 30))
                }
                hint(addressError ?? "Only addresses on this Mac work, such as localhost or 127.0.0.1.", warning: addressError != nil)
            }
        }
    }

    // MARK: Actions

    private func copyButton(_ command: String) -> some View {
        Button(copied ? "Copied" : "Copy “\(command)”") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            copied = true
        }
        .buttonStyle(PrimaryButtonStyle(height: 30))
        .accessibilityHint("Copies the command to paste in Terminal")
    }

    private func hint(_ text: String, warning: Bool = false) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(warning ? Theme.avoidText : Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func use(_ server: LocalModels.Server) {
        store.settings.localBaseURL = server.baseURL
        if !(server.models ?? []).contains(store.settings.localModel) {
            store.settings.localModel = server.models?.first ?? ""
        }
        test = .idle
    }

    private func saveAddress() {
        guard let url = LocalEndpoint.normalize(addressInput) else {
            addressError = "That address isn't on this Mac. Use localhost or 127.0.0.1 with the server's port."
            return
        }
        store.settings.localBaseURL = url
        editingAddress = false
        test = .idle
        Task { await local.refresh() }
    }

    private func runTest() {
        test = .running
        let base = baseURL, model = store.settings.localModel
        Task {
            switch await LocalEngine.test(baseURL: base, model: model) {
            case .success(let ms): test = .passed(ms)
            case .failure(let error): test = .failed(error.localizedDescription)
            }
        }
    }
}

/// Under the Claude model menus: with a local engine, says which model really runs.
struct LocalEngineModelNote: View {
    @ObservedObject var store = Store.shared

    var body: some View {
        if store.settings.engine.usesOneModel {
            let model = store.settings.oneModel.isEmpty ? "the model you pick" : LocalModelList.label(store.settings.oneModel)
            let engine = store.settings.engine == .local ? "a local model" : store.settings.engine == .chatGPT ? "ChatGPT" : Provider.current(store.settings).name
            Text("While the engine is \(engine), every preset runs on \(model). The Claude model and effort here apply when you switch back to Claude.")
                .font(.system(size: 12)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
    }
}
