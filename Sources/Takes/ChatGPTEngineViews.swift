import AppKit
import SwiftUI

/// The "Your ChatGPT plan" row's status in Settings › Model. It describes the sign-in, never which engine is in use,
/// so it can't suggest the plan is writing while another engine is selected.
struct ChatGPTEngineBadge: View {
    @ObservedObject var signIn = ChatGPTSignIn.shared

    var body: some View {
        switch signIn.state {
        case .signedIn(_, true): StatusBadge(text: "Signed in", good: true)
        case .signedIn(_, false): StatusBadge(text: "Plan usage not allowed", good: false)
        case .signingIn: ProgressView().controlSize(.mini).accessibilityLabel("Waiting for the browser")
        default: Text("Plus or Pro").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
        }
    }
}

/// The selected "Your ChatGPT plan" row in Settings › Model: sign in through the browser, pick a model, test it,
/// manage usage. Text only: no OpenAI logo or colours (OpenAI's brand guidelines), and the sign-in button says
/// "Continue with ChatGPT".
struct ChatGPTEngineSettings: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var signIn = ChatGPTSignIn.shared
    @ObservedObject var models = ChatGPTModels.shared

    enum TestState: Equatable { case idle, running, passed(Int), failed(String) }
    @State var test = TestState.idle

    var body: some View {
        details
            .task(id: signIn.canUsePlan) { if signIn.canUsePlan, !models.checked { await models.refresh() } }
    }

    @ViewBuilder private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch signIn.state {
            case .signedOut:
                continueButton("Continue with ChatGPT")
                hint("The browser opens. Sign in, choose your account, and allow Takes to use your plan.")
                if let note = signIn.signOutNote { hint(note, warning: true) }
            case .signingIn:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).accessibilityLabel("Waiting for the browser")
                    Text("Waiting for the browser…").font(.system(size: 13)).foregroundStyle(Theme.text)
                    Button("Cancel") { signIn.cancel() }
                        .buttonStyle(SecondaryButtonStyle(height: 26))
                        .keyboardShortcut(.cancelAction)
                }
                hint("Finish signing in in your browser. Takes waits up to 5 minutes.")
            case .signedIn(let email, true):
                hint(email.map { "Signed in as \($0)." } ?? "Signed in.")
                modelPicker
                accountButtons
            case .signedIn(let email, false):
                hint("Signed in\(email.map { " as \($0)" } ?? ""), but plan usage wasn't allowed. Sign in again and allow it.", warning: true)
                HStack(spacing: 8) {
                    continueButton("Sign in again")
                    Button("Sign out") { signIn.signOut() }.buttonStyle(SecondaryButtonStyle(height: 30))
                }
            case .failed(let message):
                hint(message, warning: true)
                continueButton("Try again")
            }
        }
    }

    private func continueButton(_ title: String) -> some View {
        Button(title) { test = .idle; signIn.start() }
            .buttonStyle(PrimaryButtonStyle(height: 30))
            .accessibilityHint("Opens ChatGPT sign-in in your browser")
    }

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            if models.models.isEmpty, !models.checked || models.checking {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    hint("Getting your plan's models…")
                }
            } else if models.models.isEmpty {
                hint(models.error ?? "ChatGPT didn't list any models for this account.", warning: true)
                Button("Check again") { Task { await models.refresh() } }.buttonStyle(SecondaryButtonStyle(height: 26))
            } else {
                HStack(spacing: 10) {
                    LabeledMenu(label: "Model",
                                options: models.modelOptions(picked: store.settings.chatGPTModel).map { (value: $0, title: models.label(for: $0)) },
                                selection: Binding(get: { store.settings.chatGPTModel },
                                                   set: { store.settings.chatGPTModel = $0; test = .idle }))
                    Button("Test") { runTest() }
                        .buttonStyle(SecondaryButtonStyle(height: 30))
                        .disabled(test == .running || store.settings.chatGPTModel.isEmpty)
                        .accessibilityHint("Asks the model for a one-word answer, using a little of your plan")
                }
                if !store.settings.chatGPTModel.isEmpty, !models.models.contains(store.settings.chatGPTModel) {
                    hint("\(models.label(for: store.settings.chatGPTModel)) isn't in your plan's list any more. Pick another.", warning: true)
                }
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
                hint("Asking \(models.label(for: store.settings.chatGPTModel))…")
            }
        case .passed(let ms):
            Text(String(format: "Works. Answered in %.1f s.", Double(ms) / 1000))
                .font(.system(size: 12)).foregroundStyle(Theme.doText)
        case .failed(let message):
            hint(message, warning: true)
        }
    }

    private var accountButtons: some View {
        HStack(spacing: 8) {
            Button("Manage usage") { NSWorkspace.shared.open(ChatGPTOAuth.usageURL) }
                .buttonStyle(SecondaryButtonStyle(height: 26))
                .accessibilityHint("Opens ChatGPT usage settings in your browser")
            Button("Sign out") { test = .idle; signIn.signOut() }
                .buttonStyle(SecondaryButtonStyle(height: 26))
                .accessibilityHint("Removes your ChatGPT sign-in from this Mac")
        }
    }

    private func hint(_ text: String, warning: Bool = false) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(warning ? Theme.avoidText : Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func runTest() {
        test = .running
        let model = store.settings.chatGPTModel
        Task {
            switch await ChatGPTEngine().test(model: model) {
            case .success(let ms): test = .passed(ms)
            case .failure(let error): test = .failed(error.localizedDescription)
            }
        }
    }
}

/// What the onboarding engine step shows under the "Your ChatGPT plan" option when it's selected: one line for where
/// sign-in stands. The step's primary button ("Continue with ChatGPT") starts it.
struct ChatGPTOnboardingDetail: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var signIn = ChatGPTSignIn.shared

    var body: some View {
        StepNote(note)
            .padding(.top, 4)
            .accessibilityLabel(note)
            // The primary button's title and state read the sign-in state; nudge the step to redraw.
            .onChange(of: signIn.state) { _, _ in model.objectWillChange.send() }
    }

    private var note: String {
        switch signIn.state {
        case .signedOut: "The browser will open. Sign in, choose your account, and allow Takes to use your plan."
        case .signingIn: "Waiting for the browser…"
        case .signedIn(let email, true): email.map { "Signed in as \($0)." } ?? "Signed in."
        case .signedIn(_, false): "Signed in, but plan usage wasn't allowed. Sign in again and allow it."
        case .failed(let message): message
        }
    }
}
