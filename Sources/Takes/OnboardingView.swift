import AppKit
import SwiftUI

/// The onboarding window: the step list on the left, one step on the right, Back / Skip / the step's one primary
/// action at the bottom. ↵ runs the primary action, Esc goes back (or closes on the first step), ⌘W closes.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            OnboardingStepList(model: model)
                .frame(width: 210)
            Rectangle().fill(Theme.border).frame(width: 1)
            content
        }
        // VoiceOver reads the step first, then the step list.
        .accessibilityElement(children: .contain)
        .frame(width: OnboardingWindowController.size.width, height: OnboardingWindowController.size.height)
        .background(Theme.surface)
        .tint(Theme.accent)
        .onExitCommand(perform: model.escape)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                stepBody
                    .id(model.step)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                                      removal: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 36)
            .padding(.top, 44)
            .clipped()
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.step)
            footer
        }
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(1)
    }

    @ViewBuilder private var stepBody: some View {
        switch model.step {
        case .welcome: WelcomeStep(model: model)
        case .accessibility: AccessibilityStep(model: model)
        case .engine: EngineStep(model: model)
        case .privacy: PrivacyStep(model: model)
        case .hotkey: HotKeyStep(model: model)
        case .presets: PresetsStep(model: model)
        case .practice: PracticeStep(model: model)
        case .done: DoneStep(model: model)
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.item) {
            if model.flow.canGoBack {
                Button(action: model.back) {
                    HStack(spacing: Spacing.item) {
                        Text("Back")
                        Text("esc").font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
                    }
                }
                .buttonStyle(SecondaryButtonStyle(height: 36))
                .accessibilityHint("Goes to the previous step")
            }
            if model.canSkip {
                Button("Skip", action: model.skip)
                    .buttonStyle(SecondaryButtonStyle(height: 36))
                    .accessibilityHint("Skips this step. You can change it later in Settings.")
            }
            Spacer()
            if model.step != .done {
                Text("Step \(model.flow.index + 1) of \(model.flow.steps.count)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.trailing, Spacing.item)
            }
            primaryButton
        }
        .padding(.horizontal, 36)
        .padding(.vertical, Spacing.bar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    @ViewBuilder private var primaryButton: some View {
        let button = Button(action: model.primary) {
            HStack(spacing: Spacing.item) {
                Text(model.primaryTitle)
                if model.primaryEnabled { Text("↵").font(.system(size: 12)).opacity(0.85).accessibilityHidden(true) }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!model.primaryEnabled)
        // In the practice box ↵ is for typing; the button is clicked or the hotkey is used instead.
        if model.step == .practice && model.practiceStage != .pasted {
            button
        } else {
            button.keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Step list

/// The steps down the side: a check for each one done (or already true), the current one highlighted.
struct OnboardingStepList: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.item) {
                AppGlyph(size: 26)
                Text("Takes").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
            }
            .padding(.bottom, 26)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(model.flow.steps.enumerated()), id: \.element) { index, step in
                    row(step, number: index + 1)
                }
            }
            Spacer()
            Text("You can close this window at any time. Takes keeps your place.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.section)
        .padding(.top, 48)
        .padding(.bottom, 22)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Setup steps")
    }

    private func row(_ step: OnboardingStep, number: Int) -> some View {
        let mark = model.flow.mark(for: step)
        let state: StepBadge.State
        switch mark {
        case .current: state = model.justPassed == step ? .done : .current
        case .done: state = .done
        case .skipped: state = .skipped
        case .todo: state = .todo
        }
        let spoken: String
        switch mark {
        case .current: spoken = "current step"
        case .done: spoken = "done"
        case .skipped: spoken = "skipped"
        case .todo: spoken = "to do"
        }
        return HStack(spacing: 10) {
            StepBadge(number: number, state: state, size: 22)
            Text(step.title)
                .font(.system(size: 13, weight: mark == .current ? .semibold : .regular))
                .foregroundStyle(mark == .current ? Theme.text : mark == .todo ? Theme.tertiaryText : Theme.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.item)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(mark == .current ? Theme.accentSoft : .clear))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(number), \(step.title), \(spoken)")
    }
}

// MARK: - Shared step pieces

private struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.item) {
            Text(title).font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 22)
    }
}

/// An icon and a line of text, for the "what this means" lists.
private struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.inner) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent).frame(width: 18)
                .accessibilityHidden(true)
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The hotkey drawn as large keycaps: ⌃ ⌥ Space.
struct BigKeys: View {
    let combo: KeyCombo

    static func parts(_ display: String) -> [String] {
        let modifiers: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        var parts: [String] = []
        var rest = Substring(display)
        while let first = rest.first, modifiers.contains(first) {
            parts.append(String(first))
            rest = rest.dropFirst()
        }
        if !rest.isEmpty { parts.append(String(rest)) }
        return parts
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(Self.parts(combo.display).enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(minWidth: 44, minHeight: 44)
                    .padding(.horizontal, key.count > 1 ? 12 : 0)
                    .background(
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 9).fill(Theme.controlBorder)
                            RoundedRectangle(cornerRadius: 9).fill(Theme.kbdFill).padding([.horizontal, .top], 1).padding(.bottom, 3)
                        }
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hotkey \(combo.display)")
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "Rewrite anything, in any text box",
                       subtitle: "Press a hotkey wherever you're typing, write what you mean, and pick from a few takes by Claude or a model of your choice. The one you pick is pasted back.")
            HStack(alignment: .top, spacing: 6) {
                tile(number: 1, title: "Press the hotkey") { BigKeysMini(combo: model.hotKey) }
                arrow
                tile(number: 2, title: "Write your draft") { icon("pencil.line") }
                arrow
                tile(number: 3, title: "Pick a take") { icon("square.stack.3d.up") }
                arrow
                tile(number: 4, title: "It's pasted back") { icon("arrow.down.doc") }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Press \(model.hotKey.display), write your draft, pick a take, and it's pasted back.")
            Text("Setup takes about two minutes, and ends with a try in a practice box.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 26)
        }
    }

    private var arrow: some View {
        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.tertiaryText)
            .frame(height: 96)
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 22)).foregroundStyle(Theme.accent)
    }

    private func tile<V: View>(number: Int, title: String, @ViewBuilder art: () -> V) -> some View {
        VStack(spacing: 10) {
            art().frame(height: 40)
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.strip))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }
}

/// Small keycaps for the welcome tile.
private struct BigKeysMini: View {
    let combo: KeyCombo
    var body: some View {
        HStack(spacing: 3) { ForEach(Array(BigKeys.parts(combo.display).enumerated()), id: \.offset) { Kbd($0.element) } }
    }
}

private struct AccessibilityStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        let allowed = model.flow.isCurrentSatisfied
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "Allow Accessibility access",
                       subtitle: "Takes needs it to read the text box you're typing in, and to paste your take back into it.")
            StepCard(highlighted: !allowed) {
                VStack(alignment: .leading, spacing: Spacing.inner) {
                    InfoRow(icon: "text.cursor", text: "Reads only the text box you're in, and only when you press the hotkey.")
                    InfoRow(icon: "keyboard", text: "Types nothing until you pick a take.")
                    InfoRow(icon: "switch.2", text: "You can turn it off any time in System Settings › Privacy & Security › Accessibility.")
                }
            }
            HStack(spacing: Spacing.item) {
                StatusPill(text: allowed ? "Access allowed" : "Waiting for access", good: allowed, waiting: !allowed)
                if !allowed {
                    Text("Switch Takes on in the list. This page moves on by itself.")
                        .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.top, Spacing.section)
            if !allowed {
                HStack(spacing: Spacing.item) {
                    Button("Show Takes in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.top, Spacing.inner)
                StepNote("Takes already listed and switched on? Select it, remove it with –, and add it again. macOS keeps access tied to the previous version after an update.")
                    .padding(.top, Spacing.inner)
            }
        }
    }
}

private struct EngineStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "Connect a model", subtitle: "Takes writes with Claude under your own account, with your ChatGPT plan or another provider's key, or with a model on your Mac.")
            VStack(spacing: Spacing.inner) {
                option(.claudeCode, title: "Your Claude subscription", detail: "Through Claude Code on this Mac.") { claudeCodeDetail }
                option(.apiKey, title: "An Anthropic API key", detail: "Pay per use, billed by Anthropic. Usually a cent or two per run.") { apiKeyDetail }
                option(.chatGPT, title: "Your ChatGPT plan", detail: "Sign in with ChatGPT. Plus or Pro, no extra cost.") { ChatGPTOnboardingDetail(model: model) }
                option(.provider, title: "An OpenAI or other API key", detail: "Pay per use, billed by the provider.") { ProviderOnboardingDetail(model: model) }
                option(.local, title: "A model on this Mac", detail: "Ollama or LM Studio. Nothing leaves your Mac.") { localDetail }
            }
        }
    }

    private var ready: Bool { model.flow.isCurrentSatisfied }

    private var statusText: String {
        switch model.engineStatus {
        case .checking: return "Checking…"
        case .ready(let text), .problem(let text): return text
        }
    }

    private func option<Detail: View>(_ kind: EngineKind, title: String, detail: String, @ViewBuilder more: () -> Detail) -> some View {
        let selected = model.engineKind == kind
        return Button { model.engineKind = kind } label: {
            HStack(alignment: .top, spacing: Spacing.inner) {
                Circle()
                    .stroke(selected ? Theme.accent : Theme.controlBorder, lineWidth: selected ? 5 : 1.5)
                    .frame(width: 16, height: 16)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: Spacing.item) {
                        Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                        if selected {
                            StatusPill(text: statusText, good: model.engineStatus.isReady, waiting: model.engineStatus == .checking)
                        }
                    }
                    Text(detail).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                    if selected { more() }
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.section)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Theme.accentSoft.opacity(0.5) : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Theme.accent : Theme.border, lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var claudeCodeDetail: some View {
        if !ready, model.engineStatus != .checking {
            VStack(alignment: .leading, spacing: 6) {
                if case .problem(let text) = model.engineStatus, text.contains("installed") {
                    StepNote("Install Claude Code first, then come back. This page checks again every few seconds.")
                    Button("How to install Claude Code") { NSWorkspace.shared.open(URL(string: "https://claude.com/claude-code")!) }
                        .buttonStyle(SecondaryButtonStyle(height: 28))
                } else {
                    StepNote(model.copiedSignIn
                             ? "Copied. Paste it in Terminal, sign in in the browser, then paste the code it shows back into Terminal. This page moves on by itself."
                             : "Sign in once with “claude auth login” in Terminal. The button below copies it and opens Terminal.")
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder private var localDetail: some View {
        if !ready, model.engineStatus != .checking {
            VStack(alignment: .leading, spacing: 6) {
                if case .problem(let text) = model.engineStatus, text.contains("isn't running") {
                    StepNote("Open Ollama or LM Studio, then press Check again. Takes doesn't download or install anything.")
                    Button("Get Ollama") { NSWorkspace.shared.open(URL(string: "https://ollama.com")!) }
                        .buttonStyle(SecondaryButtonStyle(height: 28))
                } else {
                    StepNote("Install a model in Ollama or LM Studio (for example llama3.2), then press Check again. You can pick another model later in Settings › Engine.")
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder private var apiKeyDetail: some View {
        if !ready {
            StyledTextField(placeholder: "Paste your key (sk-ant-…)", text: $model.apiKeyInput, secure: true, height: 34,
                            onSubmit: model.saveAPIKey)
                .padding(.top, 4)
                .accessibilityLabel("Anthropic API key")
            StepNote("Saved in your keychain. Create one at console.anthropic.com.")
        }
    }
}

private struct PrivacyStep: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var store = Store.shared

    /// The settings with the engine picked a step earlier.
    private var settings: AppSettings {
        var settings = store.settings
        settings.engine = model.engineKind
        return settings
    }

    private var recipients: String {
        switch settings.engine {
        case .claudeCode, .apiKey: return "your Mac and Anthropic"
        case .chatGPT: return "your Mac and OpenAI"
        case .provider:
            let provider = Provider.current(settings)
            return provider.id == "custom" ? "your Mac and the server you added" : "your Mac and \(provider.name)"
        case .local: return "your Mac"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "Your text and the model", subtitle: "What Takes reads, and where it goes. In short: \(recipients), nobody else.")
            StepCard {
                VStack(alignment: .leading, spacing: Spacing.inner) {
                    InfoRow(icon: "text.cursor", text: "When you press the hotkey, Takes reads the text box you're typing in.")
                    InfoRow(icon: "arrow.up.right", text: SetupMonitor.privacySummary(for: settings))
                    InfoRow(icon: "lock", text: "Nothing goes to the developer: there's no server and no tracking. History stays on this Mac.")
                    InfoRow(icon: "eye", text: SetupMonitor.mistakesNote(for: settings))
                }
            }
            StepNote("Don't use Takes on text you're not allowed to share with an AI provider, such as confidential work material.")
                .padding(.top, Spacing.section)
            HStack(spacing: Spacing.item) {
                Button("Read the privacy notice") { NSWorkspace.shared.open(SetupMonitor.privacyURL) }
                    .buttonStyle(SecondaryButtonStyle())
                if model.flow.isCurrentSatisfied { StatusPill(text: "Understood", good: true) }
            }
            .padding(.top, Spacing.inner)
        }
    }
}

private struct HotKeyStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        let free = model.hotKeyOwner == nil
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "Your hotkey", subtitle: "Press it in any text box to open Takes. It works in every app.")
            StepCard(highlighted: !free) {
                HStack(spacing: Spacing.section) {
                    BigKeys(combo: model.hotKey)
                    VStack(alignment: .leading, spacing: 6) {
                        StatusPill(text: free ? "Ready to use" : "Taken", good: free)
                        Text(free ? "Nothing else on this Mac uses it." : "Already used by \(model.hotKeyOwner ?? "another app"), so pressing it would open that too.")
                            .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: Spacing.inner) {
                Text(free ? "Prefer another one?" : "Pick another shortcut:").font(.system(size: 13)).foregroundStyle(Theme.text)
                HotKeyRecorder(combo: Binding(get: { model.hotKey }, set: { combo in
                    guard let combo else { return }
                    Store.shared.settings.summonHotKey = combo
                }), allowClear: false)
                .accessibilityLabel("Change hotkey")
            }
            .padding(.top, Spacing.section)
            if !free {
                StepNote("Or keep it and turn the other shortcut off in System Settings › Keyboard › Keyboard Shortcuts.")
                    .padding(.top, Spacing.inner)
            }
        }
    }
}

private struct PresetsStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "Pick your presets",
                       subtitle: "A preset says how to rewrite a draft. Keep the ones you'll use; each language you write in gets a translate preset.")
            HStack(alignment: .firstTextBaseline, spacing: Spacing.inner) {
                Text("You write in").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondaryText).fixedSize()
                LanguageChips(languages: $model.languages)
            }
            .padding(.bottom, Spacing.section)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Languages you write in")
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(model.starters, id: \.name) { preset in card(preset) }
                }
                .padding(1)
            }
            if model.chosenPresets.isEmpty {
                StepNote("Keep at least one to continue.").padding(.top, Spacing.item)
            }
        }
    }

    private func card(_ preset: Preset) -> some View {
        let on = model.chosenPresets.contains(preset.name)
        return Button { model.togglePreset(preset.name) } label: {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(on ? Theme.accent : Theme.surface)
                    .frame(width: 16, height: 16)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(on ? Theme.accent : Theme.dashed))
                    .overlay(Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.onAccent).opacity(on ? 1 : 0))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        PresetDot(hex: preset.colorHex)
                        Text(preset.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    }
                    Text(PresetGallery.blurb(for: preset).isEmpty ? preset.instruction : PresetGallery.blurb(for: preset))
                        .font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.inner)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(on ? Theme.accentSoft.opacity(0.5) : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.accent.opacity(0.6) : Theme.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.name)
        .accessibilityValue(on ? "kept" : "not kept")
        .accessibilityHint(preset.instruction)
    }
}

private struct PracticeStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        let stage = model.practiceStage
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: stage == .pasted ? "That's the whole flow" : "Try it here",
                       subtitle: stage == .pasted
                           ? "Your take was pasted back into the box, the same way it goes into Slack, Mail or any other app."
                           : "This box works like any text box on your Mac. Use the draft below or write your own.")
            PracticeBox(text: $model.practiceText, model: model)
                .frame(height: 104)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(stage == .pasted ? Theme.doText.opacity(0.6) : Theme.controlBorder,
                                                                   lineWidth: stage == .pasted ? 1.5 : 1))
            VStack(alignment: .leading, spacing: 10) {
                row(1, done: stage != .write, current: stage == .write) {
                    HStack(spacing: 4) {
                        Text("Click in the box and press")
                        BigKeysMini(combo: model.hotKey)
                    }
                }
                row(2, done: stage == .pasted, current: stage == .panelOpen) { Text("Press ↵ to write a few takes") }
                row(3, done: stage == .pasted, current: stage == .panelOpen) { Text("Choose one with ← →, press ↵ to paste it here") }
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.text)
            .padding(.top, Spacing.section)
            if stage == .write && model.hotKeyOwner != nil {
                StepNote("Your hotkey is taken right now, so use Open Takes below.").padding(.top, Spacing.inner)
            }
            if stage == .panelOpen {
                StepNote("Takes is open beside this window. Esc in Takes comes back here.").padding(.top, Spacing.inner)
            }
        }
    }

    private func row<Label: View>(_ number: Int, done: Bool, current: Bool, @ViewBuilder label: () -> Label) -> some View {
        HStack(spacing: 10) {
            StepBadge(number: number, state: done ? .done : current ? .current : .todo, size: 22)
            label().opacity(done || current ? 1 : 0.6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "done" : current ? "now" : "")
    }
}

/// The practice text box: a plain AppKit text view, so it behaves like the boxes Takes is used in.
private struct PracticeBox: NSViewRepresentable {
    @Binding var text: String
    let model: OnboardingModel

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 15)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.baseWritingDirection = .natural
        textView.string = text
        textView.setAccessibilityLabel("Practice box")
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        model.practiceBoxFrame = { [weak scroll] in
            guard let scroll, let window = scroll.window else { return nil }
            return window.convertToScreen(scroll.convert(scroll.bounds, to: nil))
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scroll.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

private struct DoneStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "You're set", subtitle: "Press \(model.hotKey.display) in any text box to start.")
            MenuBarHint()
            VStack(alignment: .leading, spacing: Spacing.inner) {
                InfoRow(icon: "menubar.arrow.up.rectangle", text: "Takes lives in the menu bar. Click its icon for presets, settings and setup.")
                InfoRow(icon: "slider.horizontal.3", text: "Make a preset your own in Settings › Presets: its rules, examples of how you write, and a hotkey of its own.")
                InfoRow(icon: "mic", text: Self.dictationText(Dictation.permissionState))
                if !model.flow.progress.skipped.isEmpty {
                    InfoRow(icon: "arrow.uturn.backward", text: "Skipped something? It's all in Settings, any time.")
                }
            }
            .padding(.top, 22)
        }
    }
}

extension DoneStep {
    /// Dictation is opt-in: one line here, and macOS asks the first time ⌘D is pressed.
    static func dictationText(_ state: Dictation.PermissionState) -> String {
        switch state {
        case .allowed: return "Press ⌘D in the panel to speak a draft. It's turned into text on this Mac."
        case .notAsked: return "Press ⌘D in the panel to speak a draft. macOS asks for the microphone the first time."
        case .denied: return "To speak drafts with ⌘D, allow Takes under Microphone and Speech Recognition in System Settings › Privacy & Security."
        }
    }
}

/// A sketch of the menu bar's right side with the Takes icon picked out.
private struct MenuBarHint: View {
    var body: some View {
        VStack(alignment: .takesIcon, spacing: 6) {
            HStack(spacing: 16) {
                Spacer()
                ZStack {
                    Circle().fill(Theme.accentSoft).frame(width: 30, height: 30)
                    Circle().stroke(Theme.accent, lineWidth: 1.5).frame(width: 30, height: 30)
                    Image(systemName: "text.bubble").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accent)
                }
                .alignmentGuide(.takesIcon) { $0[HorizontalAlignment.center] }
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Image(systemName: "switch.2")
                Text("Mon 9:41").font(.system(size: 13, weight: .medium))
            }
            .font(.system(size: 14))
            .foregroundStyle(Theme.controlText)
            .padding(.horizontal, Spacing.section)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.chrome))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
            VStack(spacing: 4) {
                Image(systemName: "arrow.up").font(.system(size: 12, weight: .semibold))
                Text("Takes is here, at the top of your screen")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .alignmentGuide(.takesIcon) { $0[HorizontalAlignment.center] }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Takes is in the menu bar at the top of your screen, as a speech bubble icon.")
    }
}

private extension HorizontalAlignment {
    enum TakesIcon: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[HorizontalAlignment.center] }
    }
    /// Lines the menu-bar callout up under the Takes icon.
    static let takesIcon = HorizontalAlignment(TakesIcon.self)
}
