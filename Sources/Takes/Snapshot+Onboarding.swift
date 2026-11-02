import AppKit
import SwiftUI

/// Onboarding's screens for `--snapshot`: every step and state, light and dark, in `<folder>/onboarding`.
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
            let model = OnboardingModel(progress: OnboardingProgress(step: step, history: before, autoPassed: auto, skipped: skipped), conditions: conditions)
            model.engineStatus = conditions.engineReady ? .ready("Claude Code signed in · Max plan") : .problem("Claude Code isn't signed in")
            return model
        }

        var screens: [(String, OnboardingModel)] = []
        screens.append(("1-welcome", model(.welcome, none)))
        screens.append(("2-accessibility-waiting", model(.accessibility, none)))
        let justGranted = model(.accessibility, granted)
        justGranted.justPassed = .accessibility
        screens.append(("2-accessibility-allowed", justGranted))

        let checking = model(.engine, granted)
        checking.engineStatus = .checking
        screens.append(("3-engine-checking", checking))
        screens.append(("3-engine-sign-in", model(.engine, granted)))
        let copied = model(.engine, granted)
        copied.copiedSignIn = true
        screens.append(("3-engine-copied", copied))
        let missing = model(.engine, granted)
        missing.engineStatus = .problem("Claude Code isn't installed")
        screens.append(("3-engine-not-installed", missing))
        let apiKey = model(.engine, granted)
        apiKey.engineKind = .apiKey
        apiKey.engineStatus = .problem("No API key saved yet")
        screens.append(("3-engine-api-key", apiKey))
        screens.append(("3-engine-ready", model(.engine, ready)))

        screens.append(("4-privacy", model(.privacy, ready)))
        screens.append(("5-hotkey-free", model(.hotkey, all)))
        var takenConditions = all
        takenConditions.hotKeyFree = false
        let taken = model(.hotkey, takenConditions)
        taken.hotKeyOwner = "macOS: Show Finder search window"
        screens.append(("5-hotkey-taken", taken))

        screens.append(("6-presets", model(.presets, all)))
        let noPresets = model(.presets, all)
        noPresets.chosenPresets = []
        screens.append(("6-presets-none", noPresets))

        screens.append(("7-practice-write", model(.practice, all)))
        let open = model(.practice, all)
        open.practiceStage = .panelOpen
        screens.append(("7-practice-panel-open", open))
        let pasted = model(.practice, all)
        pasted.practicePasted("Hi, could you send me the deck before Friday? I need to go over it with legal first, and they take a while.")
        screens.append(("7-practice-pasted", pasted))

        // Someone who had access and Claude already: those steps passed by themselves, one skipped step.
        let done = model(.done, all, history: [.welcome, .accessibility, .engine, .privacy, .hotkey, .presets, .practice],
                         auto: [.accessibility, .engine, .hotkey], skipped: [.presets])
        screens.append(("8-done", done))

        for (name, model) in screens {
            for scheme in [ColorScheme.light, .dark] {
                let file = url.appendingPathComponent("\(name)-\(scheme == .light ? "light" : "dark").png")
                try? bitmap(of: OnboardingView(model: model), size: OnboardingWindowController.size, scheme: scheme)?
                    .representation(using: .png, properties: [:])?.write(to: file)
            }
        }
        for scheme in [ColorScheme.light, .dark] {
            let file = url.appendingPathComponent("9-setup-window-\(scheme == .light ? "light" : "dark").png")
            try? bitmap(of: SetupView(monitor: SetupMonitor.shared, onDone: {}), size: CGSize(width: 640, height: 820), scheme: scheme)?
                .representation(using: .png, properties: [:])?.write(to: file)
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
