import AppKit
import SwiftUI

/// Onboarding's screens for `--snapshot`: the opening screen, every step and state, and the menu-bar popover,
/// light and dark, in `<folder>/onboarding`.
extension Snapshot {
    static func renderOnboarding(to folder: URL) {
        let url = folder.appendingPathComponent("onboarding", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let none = OnboardingConditions(accessibility: false, engineReady: false, privacyAccepted: false, hotKeyFree: true)
        let granted = OnboardingConditions(accessibility: true, engineReady: false, privacyAccepted: false, hotKeyFree: true)
        let ready = OnboardingConditions(accessibility: true, engineReady: true, privacyAccepted: false, hotKeyFree: true)
        let all = OnboardingConditions(accessibility: true, engineReady: true, privacyAccepted: true, hotKeyFree: true)

        func model(_ step: OnboardingStep, _ conditions: OnboardingConditions, history: [OnboardingStep]? = nil,
                   auto: Set<OnboardingStep> = [], skipped: Set<OnboardingStep> = []) -> OnboardingModel {
            let steps = OnboardingStep.allCases
            let before = history ?? Array(steps.prefix(while: { $0 != step }))
            let model = OnboardingModel(progress: OnboardingProgress(step: step, history: before, autoPassed: auto, skipped: skipped,
                                                                     openingSeen: true), conditions: conditions)
            model.engineStatus = conditions.engineReady ? .ready("Claude Code signed in · Max plan") : .problem("Claude Code isn't signed in")
            model.claudeState = conditions.engineReady ? .ready : .signedOut
            model.claudeInstalled = true
            model.engineChosen = true
            return model
        }
        // Claude Code in a given state, picked on Connect a model.
        func claude(_ state: ClaudeCodeEngine.Status.State, status: String, installed: Bool = true) -> OnboardingModel {
            let model = model(.engine, granted)
            model.claudeInstalled = installed
            model.claudeState = state
            model.engineStatus = .problem(status)
            return model
        }

        var screens: [(String, OnboardingModel)] = []
        screens.append(("1-accessibility-waiting", model(.accessibility, none)))
        let help = model(.accessibility, none)
        help.accessibilityHelp = true
        screens.append(("1-accessibility-help", help))
        let justGranted = model(.accessibility, granted)
        justGranted.justPassed = .accessibility
        screens.append(("1-accessibility-allowed", justGranted))
        let needsMove = model(.accessibility, none)
        needsMove.needsMove = true
        screens.append(("1-accessibility-move-to-applications", needsMove))

        // Nothing set up on this Mac: every way to connect, none picked for the user.
        let nonePicked = model(.engine, granted)
        nonePicked.engineChosen = false
        nonePicked.claudeInstalled = false
        screens.append(("2-engine-none-picked", nonePicked))
        let found = model(.engine, granted)
        found.engineChosen = false
        found.localRunning = true
        screens.append(("2-engine-none-picked-found", found))
        let checking = model(.engine, granted)
        checking.engineStatus = .checking
        screens.append(("2-engine-checking", checking))
        screens.append(("2-engine-sign-in", model(.engine, granted)))
        let opened = model(.engine, granted)
        opened.signInOpened = true
        screens.append(("2-engine-sign-in-opened", opened))
        // Claude Code missing: the offer to install it, the install running, and an install that failed.
        func missing(_ state: ClaudeInstaller.State) -> OnboardingModel {
            let missing = claude(.notInstalled, status: SetupMonitor.claudeMissing, installed: false)
            missing.installer = ClaudeInstaller()
            missing.installer.state = state
            return missing
        }
        screens.append(("2-engine-not-installed", missing(.idle)))
        screens.append(("2-engine-installing", missing(.downloading)))
        screens.append(("2-engine-install-failed", missing(.failed(ClaudeInstaller.failureMessage(status: 6, output: "curl: (6) Could not resolve host: claude.ai", timedOut: false) ?? ""))))
        screens.append(("2-engine-too-old", claude(.tooOld("2.0.24"), status: "Claude Code 2.0.24 is too old; update it (claude update)")))
        let launchError = "Takes couldn't start Claude Code: The file “claude” couldn't be opened."
        screens.append(("2-engine-could-not-start", claude(.couldNotStart(launchError), status: "Claude Code couldn't start")))
        screens.append(("2-engine-not-answering", claude(.notAnswering, status: "Claude Code didn't answer; trying again")))
        let apiKey = model(.engine, granted)
        apiKey.engineKind = .apiKey
        apiKey.engineStatus = .problem("No API key saved yet")
        screens.append(("2-engine-api-key", apiKey))
        let refused = model(.engine, granted)
        refused.engineKind = .apiKey
        refused.savedEngine = .apiKey
        refused.engineStatus = .problem("No API key saved yet")
        refused.apiKeySave = .refused("Anthropic refused this key. Check it in the Anthropic Console and paste it again.")
        screens.append(("2-engine-api-key-refused", refused))
        let local = model(.engine, ready)
        local.engineKind = .local
        local.savedEngine = .local
        local.localRunning = true
        local.engineStatus = .ready("Ollama · llama3.2")
        screens.append(("2-engine-local", local))
        screens.append(("2-engine-ready", model(.engine, ready)))

        var practiceTaken = all
        practiceTaken.hotKeyFree = false
        screens.append(("3-practice-write", model(.practice, all)))
        let taken = model(.practice, practiceTaken)
        taken.hotKeyOwner = "macOS: Select next source in Input menu"
        taken.hotKeySuggestions = Array(HotKeyChoice.candidates.prefix(3))
        screens.append(("3-practice-hotkey-taken", taken))
        // The longest combo the recorder takes, free and taken: no key may wrap.
        let longCombo = KeyCombo(keyCode: 49, modifiers: 0x1B00, display: "⌃⌥⇧⌘Space")
        let long = model(.practice, all)
        long.hotKey = longCombo
        screens.append(("3-practice-long-hotkey", long))
        let longTaken = model(.practice, practiceTaken)
        longTaken.hotKey = longCombo
        longTaken.hotKeyOwner = "macOS: Select next source in Input menu"
        longTaken.hotKeySuggestions = Array(HotKeyChoice.candidates.prefix(3))
        screens.append(("3-practice-long-hotkey-taken", longTaken))
        let open = model(.practice, all)
        open.practiceStage = .panelOpen
        screens.append(("3-practice-panel-open", open))
        let pasted = model(.practice, all)
        pasted.practicePasted("Hi, could you send me the deck before Friday? I need to go over it with legal first, and they take a while.")
        screens.append(("3-practice-pasted", pasted))

        // Someone who had access already: that step passed by itself; Try it was skipped.
        let done = model(.done, all, history: [.accessibility, .engine, .practice], auto: [.accessibility], skipped: [.practice])
        screens.append(("4-done", done))
        let loginOn = model(.done, all, history: [.accessibility, .engine, .practice])
        loginOn.launchAtLogin = true
        screens.append(("4-done-login-on", loginOn))

        // The provider path, finished here: no key yet, then a key saved and the provider's models listed.
        let providers = ProviderModels.shared
        providers.frozen = true
        let savedSettings = Store.shared.settings
        Store.shared.settings.providerID = Provider.openAI.id
        Store.shared.settings.providerBaseURL = Provider.openAI.baseURL
        Store.shared.settings.providerModel = ""
        let provider = model(.engine, granted)
        provider.engineKind = .provider
        provider.engineStatus = .problem("No API key saved yet")
        let providerModels = model(.engine, granted)
        providerModels.engineKind = .provider
        providerModels.savedEngine = .provider
        providerModels.engineStatus = .problem("Pick a model")
        func write(_ name: String, _ model: OnboardingModel) {
            for scheme in [ColorScheme.light, .dark] {
                let file = url.appendingPathComponent("\(name)-\(scheme == .light ? "light" : "dark").png")
                try? bitmap(of: OnboardingView(model: model), size: OnboardingWindowController.size, scheme: scheme)?
                    .representation(using: .png, properties: [:])?.write(to: file)
            }
        }
        for (name, model) in screens { write(name, model) }
        providers.models = []
        providers.state = .noKey
        providers.hasKey = false
        providers.checked = true
        write("2-engine-provider", provider)
        providers.models = ["gpt-4.1-mini", "gpt-5.4", "gpt-5.4-mini"]
        providers.state = .ready
        providers.hasKey = true
        write("2-engine-provider-models", providerModels)
        Store.shared.settings = savedSettings

        // The setup window, for someone who had Takes before: what's missing, and each Claude Code state's action.
        let setups: [(String, SetupMonitor)] = [
            ("signed-out", SetupMonitor(accessibility: false, engine: .problem("Claude Code isn't signed in"),
                                        claudeCode: .init(found: true, version: "2.1.310"))),
            ("too-old", SetupMonitor(accessibility: true, engine: .problem("Claude Code 2.0.24 is too old; update it (claude update)"),
                                     claudeCode: .init(found: true, signedIn: true, version: "2.0.24"))),
            ("could-not-start", SetupMonitor(accessibility: true, engine: .problem("Claude Code couldn't start"),
                                             claudeCode: .init(found: true, timedOut: true, launchError: launchError))),
            ("ready", SetupMonitor(accessibility: true, engine: .ready("Claude Code signed in · Max plan"),
                                   claudeCode: .init(found: true, signedIn: true, plan: "max", version: "2.1.310"))),
        ]
        for (name, monitor) in setups {
            for scheme in [ColorScheme.light, .dark] {
                let view = SetupView(monitor: monitor, onDone: {})
                let size = NSHostingView(rootView: view).fittingSize
                try? bitmap(of: view, size: size, scheme: scheme)?.representation(using: .png, properties: [:])?
                    .write(to: url.appendingPathComponent("9-setup-\(name)-\(scheme == .light ? "light" : "dark").png"))
            }
        }
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .light ? "light" : "dark"
            // The opening screen sits on a photo, so it looks the same in both; rendered in both to check that.
            try? bitmap(of: OpeningView(state: OpeningState(), onStart: {}), size: OpeningWindowController.size, scheme: scheme)?
                .representation(using: .png, properties: [:])?.write(to: url.appendingPathComponent("0-opening-\(suffix).png"))
            let hotKey = Store.shared.settings.summonHotKey
            let popovers: [(String, StatusPopoverController.Kind)] = [
                ("welcome", .welcome),
                ("reopen", .reopen(missing: nil)),
                ("reopen-setup", .reopen(missing: SetupMonitor.missingSummary(accessibility: false, engine: .ready(""), privacyAccepted: true, hotKeyFree: true))),
                ("reopen-setup-several", .reopen(missing: SetupMonitor.missingSummary(accessibility: false, engine: .problem(""), privacyAccepted: true, hotKeyFree: true))),
            ]
            for (name, kind) in popovers {
                let view = StatusPopoverView(kind: kind, hotKey: hotKey)
                    .background(Theme.chrome)
                    .fixedSize(horizontal: false, vertical: true)
                try? bitmap(of: view, size: CGSize(width: StatusPopoverView.width, height: NSHostingView(rootView: view).fittingSize.height), scheme: scheme)?
                    .representation(using: .png, properties: [:])?.write(to: url.appendingPathComponent("6-popover-\(name)-\(suffix).png"))
            }
            let crash = CrashOfferView().background(Theme.chrome).fixedSize(horizontal: false, vertical: true)
            try? bitmap(of: crash, size: CGSize(width: StatusPopoverView.width, height: NSHostingView(rootView: crash).fittingSize.height), scheme: scheme)?
                .representation(using: .png, properties: [:])?.write(to: url.appendingPathComponent("6-popover-crash-\(suffix).png"))
        }
    }

    /// Like `bitmap(of:size:)`, in light or dark mode.
    static func bitmap<V: View>(of view: V, size: CGSize, scheme: ColorScheme) -> NSBitmapImageRep? {
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.appearance = appearance
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
        hosting.appearance = appearance
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        for _ in 0..<5 { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }
        defer { window.orderOut(nil) }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }
}
