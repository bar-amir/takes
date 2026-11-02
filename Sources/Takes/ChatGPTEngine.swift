import AppKit
import SwiftUI

// A fifth engine: Sign in with ChatGPT. A Plus or Pro plan, used through OpenAI's OAuth flow (OIDC + PKCE, loopback
// callback on 127.0.0.1) and the Responses API (`store: false`, `stream: true`, system prompt in `instructions`).
// Requests come from this Mac, for this user, for Takes only; tokens live in the keychain. Free for the user, always.
// Rules: https://openai.com/policies/sign-in-with-chatgpt-terms/ and https://developers.openai.com/siwc/token-sharing-open-source
//
// SCAFFOLD: the types below are stubs so the app builds; the `chatgpt-signin` session fills them in. See docs/plans/providers.md.

/// Streams takes from the Responses API with the signed-in user's plan.
struct ChatGPTEngine: TakesEngine {
    func run(_ request: EngineRequest, onUpdate: @escaping @Sendable ([String]) -> Void) async throws -> EngineResult {
        throw EngineError.failed("Sign in with ChatGPT isn't ready yet. Pick another engine in Settings › Engine.")
    }
}

/// The browser sign-in: registers Takes on first use, exchanges the code, keeps the tokens fresh.
@MainActor
final class ChatGPTSignIn: ObservableObject {
    static let shared = ChatGPTSignIn()
    enum State: Equatable { case signedOut, signingIn, signedIn(email: String?, sharing: Bool), failed(String) }
    @Published var state = State.signedOut

    func start() {}
    func signOut() {}
}

/// The models the signed-in account may use, for Settings › Engine and the panel's Model menu.
@MainActor
final class ChatGPTModels: ObservableObject {
    static let shared = ChatGPTModels()
    @Published var models: [String] = []
    @Published var checking = false
    @Published var checked = false
    /// Snapshots set the state by hand and keep it.
    var frozen = false

    func refresh() async {}

    /// The models to offer, always including the picked one.
    func modelOptions(picked: String) -> [String] {
        var options = models
        if !picked.isEmpty, !options.contains(picked) { options.insert(picked, at: 0) }
        return options
    }
}

/// The "Sign in with ChatGPT" card body in Settings › Engine.
struct ChatGPTEngineSettings: View {
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your ChatGPT plan").font(.system(size: 15, weight: .semibold))
            Text("Sign in with ChatGPT and write with the models in your Plus or Pro plan. No extra cost; your plan's limits apply.")
                .font(.system(size: 13)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// What the onboarding engine step shows under the "Your ChatGPT plan" option when it's selected.
struct ChatGPTOnboardingDetail: View {
    @ObservedObject var model: OnboardingModel
    var body: some View { EmptyView() }
}

extension SetupMonitor {
    /// Ready when signed in, plan usage was granted, and a model is picked.
    static func chatGPTEngineStatus() async -> EngineStatus {
        .problem("Sign in with ChatGPT isn't ready yet")
    }
}

extension Snapshot {
    static func runChatGPT(to url: URL) {}
}
