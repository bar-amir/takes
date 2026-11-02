import SwiftUI

/// The line under the draft: the status and a mic button, or, while dictating, what's being heard and how loud.
/// Notes (first-use explanation, access off, language not on this Mac) take its place.
struct DictationRow<Status: View, Trailing: View>: View {
    @ObservedObject var dictation: Dictation
    let onToggle: () -> Void
    @ViewBuilder var status: Status
    /// Other compose actions shown left of the mic while idle (reply context).
    @ViewBuilder var trailing: Trailing

    var body: some View {
        switch dictation.state {
        case .idle:
            HStack(spacing: Spacing.item) {
                status
                Spacer(minLength: 0)
                trailing
                MicButton(recording: false, action: onToggle)
            }
        case .recording, .stopping:
            HStack(spacing: Spacing.item) {
                RecordingDot(live: dictation.state == .recording)
                Text(dictation.state == .recording ? "Listening in \(dictation.languageName)" : "Finishing…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.controlText)
                    .lineLimit(1)
                LevelMeter(level: dictation.state == .recording ? dictation.level : 0)
                Spacer(minLength: 0)
                KeyHint(keys: ["↵"], label: "write takes")
                MicButton(recording: true, action: onToggle)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(dictation.state == .recording ? "Listening" : "Finishing dictation")
        case .asking(explained: false):
            DictationNote(icon: "mic", text: "Speak your draft. It's turned into text on this Mac and the audio never leaves it. macOS asks for access next.") {
                Button { dictation.dismiss() } label: { HStack(spacing: 6) { Text("Not now"); Kbd("esc") } }
                    .buttonStyle(SecondaryButtonStyle(height: 28))
                Button { dictation.continueAsking() } label: {
                    HStack(spacing: 6) { Text("Continue"); Text("↵").font(.system(size: 12)).opacity(0.85) }
                }
                .buttonStyle(PrimaryButtonStyle(height: 28))
            }
        case .asking(explained: true):
            DictationNote(icon: "mic", text: "Answer the macOS dialogs to turn on dictation.") {
                ProgressView().controlSize(.small)
            }
        case .denied(let blocked):
            DictationNote(icon: "mic.slash", text: Self.deniedText(blocked)) {
                Button { dictation.openSettings(for: blocked) } label: {
                    HStack(spacing: 6) { Text("Open System Settings"); Text("↵").font(.system(size: 12)).opacity(0.85) }
                }
                .buttonStyle(PrimaryButtonStyle(height: 28))
                KeyHint(keys: ["esc"], label: "close")
            }
        case .unavailable(let reason):
            DictationNote(icon: "exclamationmark.bubble", text: Self.unavailableText(reason)) {
                if case .language = reason {
                    Button { dictation.openSettings(for: nil) } label: {
                        HStack(spacing: 6) { Text("Keyboard Settings"); Text("↵").font(.system(size: 12)).opacity(0.85) }
                    }
                    .buttonStyle(PrimaryButtonStyle(height: 28))
                }
                KeyHint(keys: ["esc"], label: "close")
            }
        }
    }

    static func deniedText(_ blocked: Dictation.Blocked) -> String {
        switch blocked {
        case .microphone:
            return "Microphone access is off. Turn on Takes in Privacy & Security › Microphone, then press ⌘D."
        case .speech:
            return "Speech recognition is off. Turn on Takes in Privacy & Security › Speech Recognition, then press ⌘D."
        }
    }

    static func unavailableText(_ reason: Dictation.Unavailable) -> String {
        switch reason {
        case .language(let name):
            return "No on-device speech for \(name) yet. Add it in Keyboard › Dictation, or pick another language in Settings."
        case .noMicrophone:
            return "No microphone found. Connect one, then press ⌘D."
        case .failed(let message):
            return "Dictation stopped: \(message) Press ⌘D to try again."
        }
    }
}

/// "Dictate ⌘D", or "Stop ⌘D" while listening.
private struct MicButton: View {
    let recording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: recording ? "stop.fill" : "mic")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(recording ? Theme.recording : Theme.controlText)
                Text(recording ? "Stop" : "Dictate")
                Kbd("⌘D")
            }
        }
        .buttonStyle(SecondaryButtonStyle(height: 26))
        .accessibilityLabel(recording ? "Stop dictation" : "Dictate")
        .accessibilityHint(recording ? "Keeps the words so far" : "Speak your draft. Speech is turned into text on this Mac.")
    }
}

/// The red "live" dot. It pulses while the microphone is on, unless Reduce Motion is on.
private struct RecordingDot: View {
    let live: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(live ? Theme.recording : Theme.tertiaryText)
            .frame(width: 8, height: 8)
            .opacity(live && dim && !reduceMotion ? 0.45 : 1)
            .onAppear {
                guard live, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityHidden(true)
    }
}

/// Five bars that rise with the input level, so it's clear the microphone hears you.
struct LevelMeter: View {
    let level: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let weights: [CGFloat] = [0.55, 0.8, 1, 0.8, 0.55]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Self.weights.indices, id: \.self) { index in
                Capsule()
                    .fill(level > 0.02 ? Theme.recording : Theme.controlBorder)
                    .frame(width: 3, height: 3 + 11 * CGFloat(level) * Self.weights[index])
            }
        }
        .frame(height: 14)
        .animation(reduceMotion ? nil : .linear(duration: 0.08), value: level)
        .accessibilityHidden(true)
    }
}

/// A short note in place of the status line, with its actions on the right.
private struct DictationNote<Actions: View>: View {
    let icon: String
    let text: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.inner) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.controlText)
                // Two lines at most, so the note fits the compose screen; VoiceOver reads all of it.
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Spacing.item) { actions }.fixedSize()
        }
        .padding(.horizontal, Spacing.inner)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.strip))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        .accessibilityElement(children: .contain)
    }
}

/// Settings › Engine: the language dictation listens for.
struct DictationSettings: View {
    @ObservedObject var store = Store.shared
    @State private var languages: [(id: String, name: String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.item) {
            LabeledMenu(label: "Language",
                        options: [(value: "", title: "Same as macOS · \(Dictation.displayName(Locale.current))")]
                            + languages.map { (value: $0.id, title: $0.name) },
                        selection: $store.settings.dictationLanguage)
            Text("Press ⌘D in the panel to speak your draft. Speech is turned into text on this Mac and the audio never leaves it, so only languages your Mac can do on its own are listed.")
                .font(.system(size: 13)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
        .task { languages = Dictation.onDeviceLanguages }
    }
}

extension DictationRow where Trailing == EmptyView {
    init(dictation: Dictation, onToggle: @escaping () -> Void, @ViewBuilder status: () -> Status) {
        self.init(dictation: dictation, onToggle: onToggle, status: status, trailing: { EmptyView() })
    }
}
