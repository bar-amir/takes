import AppKit
import SwiftUI

// A fourth engine: the user's own API key for OpenAI, or another provider that serves the OpenAI chat-completions
// API over https (Gemini, OpenRouter, Groq, Mistral, or a custom address). Billed by the provider under the user's
// account. The wire format is the one LocalEngine already speaks (SSEParser, LocalChunk, LocalModelList,
// LocalEngine.chatRequest); this engine adds a bearer key, https-only addresses and provider-specific wording.
//
// SCAFFOLD: the types below are stubs so the app builds; the `provider-api` session fills them in. See docs/plans/providers.md.

/// A provider Takes knows how to talk to.
struct Provider: Equatable {
    var id: String
    var name: String
    var baseURL: String
    /// Where to get a key.
    var consoleURL: URL?

    static let openAI = Provider(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1",
                                 consoleURL: URL(string: "https://platform.openai.com/api-keys"))
    static let custom = Provider(id: "custom", name: "Custom server", baseURL: "", consoleURL: nil)
    static let known: [Provider] = [openAI]

    /// The provider the settings point at ("custom" for an address Takes doesn't know).
    static func current(_ settings: AppSettings) -> Provider {
        known.first { $0.id == settings.providerID } ?? Provider(id: "custom", name: "Custom server", baseURL: settings.providerBaseURL, consoleURL: nil)
    }
}

/// Streams takes from an OpenAI-compatible server over https with the user's key.
struct ProviderEngine: TakesEngine {
    var settings: AppSettings

    func run(_ request: EngineRequest, onUpdate: @escaping @Sendable ([String]) -> Void) async throws -> EngineResult {
        throw EngineError.failed("Other providers aren't ready yet. Pick another engine in Settings › Engine.")
    }
}

/// The provider's models, for Settings › Engine and the panel's Model menu.
@MainActor
final class ProviderModels: ObservableObject {
    static let shared = ProviderModels()
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

/// The "Other provider" card body in Settings › Engine.
struct ProviderEngineSettings: View {
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Other provider").font(.system(size: 15, weight: .semibold))
            Text("Your own API key for OpenAI, or another server that speaks its API. Billed by the provider under your account.")
                .font(.system(size: 13)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// What the onboarding engine step shows under the "Other provider" option when it's selected.
struct ProviderOnboardingDetail: View {
    @ObservedObject var model: OnboardingModel
    var body: some View { EmptyView() }
}

extension SetupMonitor {
    /// Ready when a key is saved and a model is picked.
    static func providerEngineStatus() async -> EngineStatus {
        .problem("Other providers aren't ready yet")
    }
}

extension Snapshot {
    static func runProviders(to url: URL) {}
}
