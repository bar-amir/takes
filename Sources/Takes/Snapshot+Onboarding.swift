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
            model.claudeInstalled = true
            return model
        }

        var screens: [(String, OnboardingModel)] = []
        screens.append(("1-accessibility-waiting", model(.accessibility, none)))
        let justGranted = model(.accessibility, granted)
        justGranted.justPassed = .accessibility
        screens.append(("1-accessibility-allowed", justGranted))

        let checking = model(.engine, granted)
        checking.engineStatus = .checking
        screens.append(("2-engine-checking", checking))
        screens.append(("2-engine-sign-in", model(.engine, granted)))
        let others = model(.engine, granted)
        others.showOtherEngines = true
        screens.append(("2-engine-other-ways", others))
        let opened = model(.engine, granted)
        opened.signInOpened = true
        screens.append(("2-engine-sign-in-opened", opened))
        // Claude Code missing: the offer to install it, the install running, and an install that failed.
        func missing(_ state: ClaudeInstaller.State) -> OnboardingModel {
            let missing = model(.engine, granted)
            missing.claudeInstalled = false
            missing.engineStatus = .problem(SetupMonitor.claudeMissing)
            missing.installer = ClaudeInstaller()
            missing.installer.state = state
            return missing
        }
        screens.append(("2-engine-not-installed", missing(.idle)))
        screens.append(("2-engine-installing", missing(.downloading)))
        screens.append(("2-engine-install-failed", missing(.failed(ClaudeInstaller.failureMessage(status: 6, output: "curl: (6) Could not resolve host: claude.ai", timedOut: false) ?? ""))))
        let apiKey = model(.engine, granted)
        apiKey.engineKind = .apiKey
        apiKey.engineStatus = .problem("No API key saved yet")
        screens.append(("2-engine-api-key", apiKey))
        let local = model(.engine, ready)
        local.engineKind = .local
        local.recommendedEngine = .local
        local.localRunning = true
        local.engineStatus = .ready("Ollama · llama3.2")
        screens.append(("2-engine-local", local))
        screens.append(("2-engine-ready", model(.engine, ready)))

        screens.append(("3-make-it-yours", model(.personalize, all)))
        var takenConditions = all
        takenConditions.hotKeyFree = false
        let taken = model(.personalize, takenConditions)
        taken.hotKeyOwner = "macOS: Select next source in Input menu"
        taken.hotKeySuggestions = Array(HotKeyChoice.candidates.prefix(3))
        screens.append(("3-make-it-yours-hotkey-taken", taken))
        let needsMove = model(.accessibility, none)
        needsMove.needsMove = true
        screens.append(("1-accessibility-move-to-applications", needsMove))
        let noPresets = model(.personalize, all)
        noPresets.chosenPresets = []
        screens.append(("3-make-it-yours-none", noPresets))

        screens.append(("4-practice-write", model(.practice, all)))
        let open = model(.practice, all)
        open.practiceStage = .panelOpen
        screens.append(("4-practice-panel-open", open))
        let pasted = model(.practice, all)
        pasted.practicePasted("Hi, could you send me the deck before Friday? I need to go over it with legal first, and they take a while.")
        screens.append(("4-practice-pasted", pasted))

        // Someone who had access already: that step passed by itself; Make it yours was skipped.
        let done = model(.done, all, history: [.accessibility, .engine, .personalize, .practice],
                         auto: [.accessibility], skipped: [.personalize])
        screens.append(("5-done", done))
        let loginOn = model(.done, all, history: [.accessibility, .engine, .personalize, .practice])
        loginOn.launchAtLogin = true
        screens.append(("5-done-login-on", loginOn))

        for (name, model) in screens {
            for scheme in [ColorScheme.light, .dark] {
                let file = url.appendingPathComponent("\(name)-\(scheme == .light ? "light" : "dark").png")
                try? bitmap(of: OnboardingView(model: model), size: OnboardingWindowController.size, scheme: scheme)?
                    .representation(using: .png, properties: [:])?.write(to: file)
            }
        }
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .light ? "light" : "dark"
            try? bitmap(of: SetupView(monitor: SetupMonitor.shared, onDone: {}), size: CGSize(width: 640, height: 820), scheme: scheme)?
                .representation(using: .png, properties: [:])?.write(to: url.appendingPathComponent("9-setup-window-\(suffix).png"))
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
