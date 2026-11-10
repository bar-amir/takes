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
                    // A cross-fade with a 12 pt push in the direction of travel; a plain cross-fade under Reduce Motion.
                    .transition(.asymmetric(insertion: .offset(x: reduceMotion ? 0 : (model.forward ? 12 : -12)).combined(with: .opacity),
                                            removal: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 36)
            .padding(.top, 44)
            .padding(.bottom, Spacing.section)
            .clipped()
            .animation(Motion.animation(.easeOut(duration: Motion.slow)), value: model.step)
            footer
        }
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(1)
    }

    @ViewBuilder private var stepBody: some View {
        switch model.step {
        case .accessibility: AccessibilityStep(model: model)
        case .engine: EngineStep(model: model)
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
            if let numbered = model.flow.numbered {
                Text("Step \(numbered.index) of \(numbered.count)")
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
                Text(verbatim: "Takes").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
            }
            .padding(.bottom, 26)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(OnboardingStep.numbered.enumerated()), id: \.element) { index, step in
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
        case .current: spoken = String(localized: "current step")
        case .done: spoken = String(localized: "done")
        case .skipped: spoken = String(localized: "skipped")
        case .todo: spoken = String(localized: "to do")
        }
        return HStack(spacing: 10) {
            StepBadge(number: number, state: state, size: 22)
                .animation(Motion.animation(.easeOut(duration: Motion.standard)), value: state)
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

/// The hotkey drawn as large keycaps: ⌥ ⇧ Space.
struct BigKeys: View {
    let combo: KeyCombo
    var size: CGFloat = 44

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
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(Theme.text)
                    .frame(minWidth: size, minHeight: size)
                    .padding(.horizontal, key.count > 1 ? size * 0.27 : 0)
                    .background(
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 9).fill(Theme.controlBorder)
                            RoundedRectangle(cornerRadius: 9).fill(Theme.kbdFill).padding([.horizontal, .top], 1).padding(.bottom, 3)
                        }
                    )
            }
        }
        // Shortcuts read left to right in every language, as in macOS menus.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hotkey \(combo.display)")
    }
}

// MARK: - Steps

/// Small keycaps, inline with text.
private struct BigKeysMini: View {
    let combo: KeyCombo
    var body: some View {
        HStack(spacing: 3) { ForEach(Array(BigKeys.parts(combo.display).enumerated()), id: \.offset) { Kbd($0.element) } }
            .environment(\.layoutDirection, .leftToRight)
    }
}

private struct AccessibilityStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        let allowed = model.flow.isCurrentSatisfied
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: String(localized: "Allow Accessibility access"),
                       subtitle: String(localized: "Takes needs it to read the text box you're typing in, and to paste your take back into it."))
            StepCard(highlighted: !allowed) {
                VStack(alignment: .leading, spacing: Spacing.inner) {
                    InfoRow(icon: "text.cursor", text: String(localized: "Reads only the text box you're in, and only when you press the hotkey."))
                    InfoRow(icon: "keyboard", text: String(localized: "Types nothing until you pick a take."))
                    InfoRow(icon: "switch.2", text: String(localized: "You can turn it off any time in System Settings › Privacy & Security › Accessibility."))
                }
            }
            HStack(spacing: Spacing.item) {
                StatusPill(text: allowed ? String(localized: "Access allowed") : String(localized: "Waiting for access"), good: allowed, waiting: !allowed)
                if !allowed {
                    Text("Switch Takes on in the list. This page moves on by itself.")
                        .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.top, Spacing.section)
            if !allowed {
                if model.needsMove {
                    MoveToApplicationsNote(model: model).padding(.top, Spacing.inner)
                } else if model.accessibilityHelp {
                    HStack(spacing: Spacing.item) {
                        Button("Show Takes in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(.top, Spacing.inner)
                }
                // Only once a check has failed: before that it's in the way of the one thing to do.
                if model.accessibilityHelp {
                    StepNote(String(localized: "Takes already listed and switched on? Select it, remove it with –, and add it again. macOS keeps access tied to the previous version after an update."))
                        .padding(.top, Spacing.inner)
                }
            }
        }
    }
}

/// Takes was opened from the disk image or a download folder, so macOS runs a hidden copy: offer to move it to
/// Applications first, where access, login items and updates all stick. Shared by onboarding and the setup window.
struct MoveToApplicationsNote: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.inner) {
            HStack(spacing: Spacing.item) {
                Button("Move Takes to Applications", action: model.moveToApplications)
                    .buttonStyle(PrimaryButtonStyle(height: 32))
                    .accessibilityHint("Copies Takes to the Applications folder and opens it from there")
                Text(String(localized: "Takes is running from \(AppLocation.whereItRuns). Move it first, so the access you allow stays with it."))
                    .font(.system(size: 12)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.moveError {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.avoidText).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Free hotkeys offered as keycap chips; one click picks it.
struct HotKeySuggestionChips: View {
    let suggestions: [KeyCombo]
    let pick: (KeyCombo) -> Void

    var body: some View {
        if !suggestions.isEmpty {
            HStack(spacing: Spacing.item) {
                Text("Free right now:").font(.system(size: 12)).foregroundStyle(Theme.secondaryText).fixedSize()
                ForEach(suggestions, id: \.self) { combo in
                    Button { pick(combo) } label: {
                        HStack(spacing: 3) { ForEach(Array(BigKeys.parts(combo.display).enumerated()), id: \.offset) { Kbd($0.element) } }
                            .padding(.horizontal, 6)
                            .frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.controlBorder))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use \(combo.display)")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Free hotkeys")
        }
    }
}

/// Connect a model: every way to connect, offered as equals, and where the text goes with the one picked. A
/// sentence above the button says that going on is the consent; the button says what it does.
private struct EngineStep: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var store = Store.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: String(localized: "Connect a model"), subtitle: String(localized: "Takes writes with a model under your own account, or with one on this Mac."))
            // Every option shows when they fit; when an open one makes them too tall, they scroll, with a visible
            // scroller and a fade at the bottom edge, and where the text goes stays in view below.
            ViewThatFits(in: .vertical) {
                options.padding(2)
                ScrollView {
                    options.padding(2).padding(.bottom, 24)
                }
                .scrollIndicators(.visible)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [Theme.surface.opacity(0), Theme.surface], startPoint: .top, endPoint: .bottom)
                        .frame(height: 28)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .layoutPriority(1)
            if model.engineChosen {
                privacy.padding(.top, Spacing.inner)
            }
            Spacer(minLength: 0)
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Onboarding.engineOrder, id: \.self) { option($0) }
        }
    }

    /// The settings with the engine picked here.
    private var settings: AppSettings {
        var settings = store.settings
        settings.engine = model.engineKind
        return settings
    }

    /// Where the text goes, naming who gets it for the picked engine.
    private var privacy: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("WHERE YOUR TEXT GOES").font(.mono(10.5, bold: true)).tracking(Font.labelSpacing(0.6)).foregroundStyle(Theme.tertiaryText)
            if let recipient = SetupMonitor.recipient(for: settings) {
                line("arrow.up.forward", Text("Your draft and preset go from this Mac to \(Text(recipient).bold()), under your account."))
            } else {
                line("lock", Text("\(Text("Nothing leaves this Mac.").bold()) Your draft goes to the model server running on it."))
            }
            line("minus", Text("Nothing goes to the developer. No server, no tracking."))
            HStack(spacing: 4) {
                Text(model.engineKind.isClaude ? "Claude can get things wrong: read each take before you send it." : "Models can get things wrong: read each take before you send it.")
                Button("Privacy notice") { NSWorkspace.shared.open(SetupMonitor.privacyURL) }
                    .buttonStyle(.plain).underline().foregroundStyle(Theme.text)
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondaryText)
            .lineLimit(1)
            if model.needsConsent {
                Text("By continuing, you agree to this.")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 4)
            }
        }
        .padding(.top, Spacing.inner)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Where your text goes")
    }

    private func line(_ icon: String, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.item) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText).frame(width: 14)
                .accessibilityHidden(true)
            text.font(.system(size: 12.5)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ready: Bool { model.flow.conditions.engineReady }

    private var statusText: String {
        if model.engineKind == .claudeCode, model.installer.state.isBusy { return String(localized: "Installing Claude Code") }
        // Claude Code's problems in a word or two ("Too old (2.0.24)"); the card says what to do.
        if model.engineKind == .claudeCode, case .problem = model.engineStatus, let state = model.claudeState, state != .ready {
            return ClaudeCodeAction.badge(for: state).text
        }
        switch model.engineStatus {
        case .checking: return String(localized: "Checking…")
        case .ready(let text), .problem(let text): return text
        }
    }

    private func title(_ kind: EngineKind) -> String {
        switch kind {
        case .claudeCode: return String(localized: "Your Claude subscription")
        case .apiKey: return String(localized: "An Anthropic API key")
        case .chatGPT: return String(localized: "Your ChatGPT plan")
        case .provider: return String(localized: "An OpenAI or other API key")
        case .local: return String(localized: "A model on this Mac")
        }
    }

    private func detail(_ kind: EngineKind) -> String {
        switch kind {
        case .claudeCode: return model.claudeInstalled && model.claudeAction == .signIn
            ? String(localized: "Claude Code is installed. Sign in once in Terminal, and Takes notices on its own. Counts toward your plan's limits.")
            : String(localized: "Through Claude Code on this Mac. Counts toward your plan's usage limits.")
        case .apiKey: return String(localized: "Pay per use, billed by Anthropic. Usually a cent or two per run; Takes doesn't cap your spending.")
        case .chatGPT: return String(localized: "Sign in with ChatGPT. Plus or Pro, no extra cost; counts toward your plan's limits.")
        case .provider: return String(localized: "Pay per use, billed by the provider; Takes doesn't cap your spending.")
        case .local: return String(localized: "Ollama or LM Studio. Free, and nothing leaves your Mac.")
        }
    }

    /// "Found on this Mac" for an option that's already there.
    private func found(_ kind: EngineKind) -> Bool {
        model.setUpEngines.contains(kind) || (kind == .claudeCode && model.claudeInstalled) || (kind == .local && model.localRunning)
    }

    private func option(_ kind: EngineKind) -> some View {
        let selected = model.isChosen(kind)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(Motion.animation()) { model.choose(kind) }
            } label: {
                HStack(spacing: Spacing.inner) {
                    Circle()
                        .stroke(selected ? Theme.accent : Theme.controlBorder, lineWidth: selected ? 5 : 1.5)
                        .frame(width: 16, height: 16)
                    Text(title(kind)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    if selected {
                        let installing = kind == .claudeCode && model.installer.state.isBusy
                        StatusPill(text: statusText, good: model.engineStatus.isReady, waiting: model.engineStatus == .checking || installing)
                    } else if found(kind) {
                        StatusPill(text: String(localized: "Found on this Mac"), good: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            if selected {
                VStack(alignment: .leading, spacing: 6) {
                    Text(detail(kind)).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    more(kind)
                }
                .padding(.leading, 16 + Spacing.inner)
            }
        }
        .padding(.horizontal, selected ? Spacing.section : Spacing.inner)
        .padding(.vertical, selected ? Spacing.inner : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Theme.accentSoft.opacity(0.5) : Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Theme.accent : Theme.border, lineWidth: selected ? 1.5 : 1))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func more(_ kind: EngineKind) -> some View {
        switch kind {
        case .claudeCode: claudeCodeDetail
        case .apiKey: apiKeyDetail
        case .chatGPT: ChatGPTOnboardingDetail(model: model)
        case .provider: ProviderOnboardingDetail(model: model)
        case .local: localDetail
        }
    }

    @ViewBuilder private var claudeCodeDetail: some View {
        let install = model.installer.state
        if !ready, model.engineStatus != .checking {
            VStack(alignment: .leading, spacing: 6) {
                if let progress = install.progress {
                    HStack(spacing: Spacing.item) {
                        ProgressView().controlSize(.small)
                        Text(progress).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
                    }
                    StepNote(String(localized: "This takes about a minute. Then Terminal opens so you can sign in."))
                } else {
                    switch model.claudeAction {
                    case .install:
                        if let error = install.error {
                            Text(error).font(.system(size: 12)).foregroundStyle(Theme.avoidText)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Install it yourself") { NSWorkspace.shared.open(ClaudeInstaller.manualURL) }
                                .buttonStyle(SecondaryButtonStyle(height: 28))
                        } else {
                            StepNote(String(localized: "Takes installs it for you from Anthropic, then you sign in once. No password, nothing to type."))
                        }
                    case .signIn:
                        if model.signInOpened {
                            StepNote(String(localized: "Finish signing in in the browser. This page moves on by itself."))
                            Button("Open Terminal again", action: model.openSignIn)
                                .buttonStyle(SecondaryButtonStyle(height: 28))
                        } else {
                            StepNote(String(localized: "Terminal opens and takes you to your browser to sign in. Nothing to type."))
                        }
                    case .update:
                        StepNote(ClaudeCodeAction.note(for: model.claudeState ?? .tooOld("")) ?? "")
                        Button("Check again") { model.runClaude(.checkAgain) }
                            .buttonStyle(SecondaryButtonStyle(height: 28))
                    case .checkAgain:
                        if let state = model.claudeState, let note = ClaudeCodeAction.note(for: state) {
                            Text(note).font(.system(size: 12)).foregroundStyle(state == .stillLooking ? Theme.secondaryText : Theme.avoidText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder private var localDetail: some View {
        if !ready, model.engineStatus != .checking {
            VStack(alignment: .leading, spacing: 6) {
                if case .problem(let text) = model.engineStatus, text == String(localized: "\(LocalServerKind.displayName(Store.shared.settings.localBaseURL)) isn't running") {
                    StepNote(String(localized: "Open Ollama or LM Studio, then press Check again. Takes doesn't download or install anything."))
                    Button("Get Ollama") { NSWorkspace.shared.open(URL(string: "https://ollama.com")!) }
                        .buttonStyle(SecondaryButtonStyle(height: 28))
                } else {
                    StepNote(String(localized: "Install a model in Ollama or LM Studio (for example llama3.2), then press Check again. You can pick another model later in Settings."))
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder private var apiKeyDetail: some View {
        if !ready {
            StyledTextField(placeholder: String(localized: "Paste your key (sk-ant-…)"), text: $model.apiKeyInput, secure: true, height: 34,
                            onSubmit: model.primary)
                .padding(.top, 4)
                .accessibilityLabel("Anthropic API key")
                .disabled(model.checkingKey)
            if let note = model.apiKeySave?.note {
                Text(note.text).font(.system(size: 12)).foregroundStyle(note.problem ? Theme.avoidText : Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                StepNote(String(localized: "Saved in your keychain. Create one at console.anthropic.com."))
            }
        }
    }
}

private struct PracticeStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        let stage = model.practiceStage
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: stage == .pasted ? String(localized: "That's the whole flow") : String(localized: "Try it here"),
                       subtitle: stage == .pasted
                           ? String(localized: "Your take was pasted back into the box, the same way it goes into Slack, Mail or any other app.")
                           : String(localized: "This box works like any text box on your Mac. Use the draft below or write your own."))
            PracticeBox(text: $model.practiceText, model: model)
                .frame(height: 104)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(stage == .pasted ? Theme.doText.opacity(0.6) : Theme.controlBorder,
                                                                   lineWidth: stage == .pasted ? 1.5 : 1))
            VStack(alignment: .leading, spacing: 10) {
                row(1, done: stage != .write, current: stage == .write) {
                    KeysSentence(sentence: String(localized: "Click in the box and press \(KeysSentence<EmptyView>.marker)")) {
                        BigKeysMini(combo: model.hotKey)
                    }
                }
                row(2, done: stage == .pasted, current: stage == .panelOpen) { Text("Press ↵ to write a few takes") }
                row(3, done: stage == .pasted, current: stage == .panelOpen) { Text("Choose one with ← →, press ↵ to paste it here") }
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.text)
            .padding(.top, Spacing.section)
            if stage == .write {
                PracticeHotKey(model: model).padding(.top, Spacing.section)
            }
            if stage == .panelOpen {
                StepNote(String(localized: "Takes is open beside this window. Esc in Takes comes back here.")).padding(.top, Spacing.inner)
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

/// The hotkey, where it's first used: its keycaps, whether it's free, and a recorder to change it. When something
/// else has it, the free ones are offered and Open Takes still works.
private struct PracticeHotKey: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        let free = model.hotKeyOwner == nil
        VStack(alignment: .leading, spacing: Spacing.item) {
            HStack(spacing: Spacing.inner) {
                Text("Your hotkey").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondaryText).fixedSize()
                BigKeysMini(combo: model.hotKey)
                StatusPill(text: free ? String(localized: "Free to use")
                                      : String(localized: "Taken", comment: "The hotkey is already used by something else"),
                           good: free)
                Spacer(minLength: 0)
                Text("Change:").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                HotKeyRecorder(combo: Binding(get: { model.hotKey }, set: { combo in
                    guard let combo else { return }
                    Store.shared.settings.summonHotKey = combo
                }), allowClear: false, height: 28)
                .fixedSize()
                .accessibilityLabel("Change hotkey")
            }
            if !free {
                StepNote(String(localized: "Also used by \(model.hotKeyOwner ?? String(localized: "another app")). Pick another, or turn that one off in System Settings › Keyboard."))
                HotKeySuggestionChips(suggestions: model.hotKeySuggestions, pick: model.pickHotKey)
            }
        }
        .accessibilityElement(children: .contain)
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
        textView.setAccessibilityLabel(String(localized: "Practice box"))
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

/// The closing screen: the one thing to remember, the hotkey, and whether Takes opens at login.
private struct DoneStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: String(localized: "You're set"), subtitle: String(localized: "Press \(model.hotKey.inline) in any text box to start."))
            BigKeys(combo: model.hotKey)
            HStack(alignment: .firstTextBaseline, spacing: Spacing.inner) {
                Checkbox(isOn: $model.launchAtLogin, label: String(localized: "Open Takes when I log in"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Takes when I log in").font(.system(size: 13)).foregroundStyle(Theme.text)
                    Text(model.launchAtLoginError ?? String(localized: "So the hotkey is ready without opening Takes first. Change it any time in Settings › General."))
                        .font(.system(size: 12)).foregroundStyle(model.launchAtLoginError == nil ? Theme.secondaryText : Theme.avoidText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 28)
            .accessibilityElement(children: .contain)
        }
    }
}
