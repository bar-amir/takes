import SwiftUI

extension Preset {
    /// Instant mode, off unless turned on. Only takes effect while the preset has a hotkey.
    var writesInstantly: Bool {
        get { instantMode ?? false }
        set { instantMode = newValue ? true : nil }
    }
}

/// The toast instant mode shows near the caret: writing, pasted, failed, cancelled. Always dark, like the
/// paste toast in `Toast.swift`, so it reads the same over any app.
struct InstantToast: View {
    enum State: Equatable {
        case writing(preset: String)
        case pasted(clipboardBack: Bool, hotKey: String?)
        /// The take matched the draft, so nothing was pasted.
        case unchanged(hotKey: String?)
        case failed(message: String, hotKey: String?)
        case cancelled

        /// Writing stays up until it's done; failures stay longer than success, to be read.
        var hideAfter: TimeInterval? {
            switch self {
            case .writing: return nil
            case .pasted, .unchanged: return InstantToast.pastedSeconds
            case .failed: return InstantToast.failedSeconds
            case .cancelled: return 2
            }
        }

        var spoken: String {
            switch self {
            case .writing(let preset): return String(localized: "Writing with \(preset). Press Escape to cancel.")
            case .pasted: return String(localized: "Pasted. Command Z undoes it.")
            case .unchanged: return String(localized: "No changes needed. Nothing was pasted.")
            case .failed(let message, _): return message
            case .cancelled: return String(localized: "Cancelled. Nothing was pasted.")
            }
        }
    }

    static let pastedSeconds: TimeInterval = 6
    static let failedSeconds: TimeInterval = 10

    let state: State
    var onCancel: () -> Void = {}
    var onOpen: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The paste toast's own colors (`ToastView`); the failure mark is Theme.avoidText's dark value.
    private static let fill = Color(hex: "#24242B")
    private static let success = Color(hex: "#7FD4A8")
    static let failure = Color(hex: "#F2A196")
    private static let dim = Color.white.opacity(0.75)

    var body: some View {
        HStack(spacing: 12) {
            icon
            content
        }
        .foregroundStyle(.white)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .frame(minHeight: 46)
        .background(RoundedRectangle(cornerRadius: 12).fill(Self.fill))
        .fixedSize()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var icon: some View {
        switch state {
        case .writing:
            if reduceMotion {
                Image(systemName: "ellipsis").font(.system(size: 14, weight: .bold)).foregroundStyle(Self.dim)
            } else {
                // The spinner follows the appearance; the toast is always dark.
                ProgressView().controlSize(.small).environment(\.colorScheme, .dark).frame(width: 16, height: 16)
            }
        case .pasted, .unchanged:
            Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Self.success)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Self.failure)
        case .cancelled:
            Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Self.dim)
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .writing(let preset):
            Text("Writing with \(Text(preset).fontWeight(.semibold))…").font(.system(size: 13))
            Button(action: onCancel) { keyLabel("esc", String(localized: "cancel", comment: "Key hint: esc cancels the instant take")) }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel, nothing will be pasted")
        case .pasted(let clipboardBack, let hotKey):
            Text(clipboardBack ? "Pasted · your clipboard is back" : "Pasted").font(.system(size: 13))
            keyLabel("⌘Z", String(localized: "undo", comment: "Key hint: ⌘Z undoes the paste")).accessibilityLabel("Command Z undoes the paste")
            openButton(hotKey)
        case .unchanged(let hotKey):
            Text("No changes needed. Your text is as you wrote it.").font(.system(size: 13))
            openButton(hotKey)
        case .failed(let message, let hotKey):
            Text(message).font(.system(size: 13)).lineLimit(3).frame(maxWidth: 360, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            openButton(hotKey)
        case .cancelled:
            Text("Cancelled. Nothing was pasted.").font(.system(size: 13))
        }
    }

    /// "Open in Takes": the panel with this run, to refine it or write more takes. The preset's hotkey,
    /// pressed again while the toast is up, does the same.
    private func openButton(_ hotKey: String?) -> some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                Text("Open in Takes")
                if let hotKey { key(hotKey) }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.3)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hotKey.map { String(localized: "Open in Takes, or press \($0) again") } ?? String(localized: "Open in Takes"))
    }

    private func keyLabel(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            key(keys)
            Text(label).font(.caption)
        }
        .foregroundStyle(Self.dim)
    }

    /// The paste toast's key cap, for a dark background.
    private func key(_ text: String) -> some View {
        // The mark keeps "⌃⌥2" from turning into "2⌃⌥" in right-to-left languages.
        Text(verbatim: "\u{200E}" + text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.12)))
    }
}

/// The preset editor's last section: turn instant mode on, or set the hotkey it needs.
struct InstantModeSection: View {
    @Binding var preset: Preset

    private var hasHotKey: Bool { preset.hotKey != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PresetOptionRow(isOn: $preset.writesInstantly, title: String(localized: "Write and paste right away"),
                            detail: hasHotKey
                                ? String(localized: "\(preset.hotKey!.inline) writes 1 take and pastes it, without opening the panel. Esc cancels while it writes, ⌘Z undoes the paste. An empty text box opens the panel instead. You won't see the take before it's pasted, so read it before you send.")
                                : String(localized: "This preset's own hotkey would write 1 take and paste it, without opening the panel. It needs a hotkey of its own first."),
                            enabled: hasHotKey)
            if !hasHotKey {
                HStack(spacing: 10) {
                    HotKeyRecorder(combo: $preset.hotKey)
                    Text("Set one here, then turn this on.").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                }
                .padding(.leading, 26)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
