import AVFoundation
import AppKit
import SwiftUI

/// Settings › General: how the panel opens, the clipboard, dictation and what macOS has allowed.
struct GeneralTab: View {
    @ObservedObject var store = Store.shared

    var body: some View {
        SettingsPage {
            FormSection(String(localized: "Opening Takes")) {
                FormRow(String(localized: "Hotkey")) {
                    HotKeyRecorder(combo: Binding(get: { store.settings.summonHotKey },
                                                  set: { if let combo = $0 { store.settings.summonHotKey = combo } }),
                                   allowClear: false, height: 28)
                }
                FormDivider()
                FormRow(String(localized: "Open the panel"), detail: String(localized: "Wherever it opens, it moves aside rather than cover the text box.")) {
                    PanelPositionPicker(selection: $store.settings.panelPosition)
                }
                FormDivider()
                FormRow(String(localized: "Start with")) {
                    MenuPicker(options: Prefill.allCases.map { (value: $0, title: $0.label) }, selection: $store.settings.prefill)
                }
            }

            FormSection(String(localized: "Clipboard"), footer: String(localized: "In the panel, ⌘J adds what you're replying to and ⇧⌘V uses the clipboard. Context isn't kept in history.")) {
                FormToggle(String(localized: "Put my clipboard back after pasting"), isOn: $store.settings.restoreClipboard)
                FormDivider()
                ReplyContextSettings()
            }

            DictationSettings()

            FormSection(String(localized: "System")) {
                FormRow(String(localized: "Permissions")) { PermissionsStatus() }
            }
        }
    }
}

/// "✓ Accessibility · ✓ Microphone  Check…": what macOS allows Takes, with a link to the setup window.
struct PermissionsStatus: View {
    @ObservedObject var monitor = SetupMonitor.shared

    var body: some View {
        HStack(spacing: 10) {
            item(String(localized: "Accessibility"), state: monitor.accessibility ? .allowed : .denied)
            Text("·").foregroundStyle(Theme.tertiaryText)
            item(String(localized: "Microphone"), state: microphone)
            Button("Check…") { SetupWindowController.shared.show() }
                .buttonStyle(FormLinkButtonStyle())
                .accessibilityHint("Opens setup and permissions")
                .padding(.leading, 4)
        }
        .font(.system(size: 12.5))
    }

    private enum Access { case allowed, denied, notAsked }

    private var microphone: Access {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .allowed
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    private func item(_ name: String, state: Access) -> some View {
        let (symbol, color): (String, Color) = switch state {
        case .allowed: ("checkmark", Theme.doText)
        case .denied: ("xmark", Theme.avoidText)
        case .notAsked: ("minus", Theme.secondaryText)
        }
        return HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
            Text(name)
        }
        .foregroundStyle(color)
        .fixedSize()
        .help(state == .notAsked ? String(localized: "\(name): macOS asks the first time it's needed.")
              : state == .allowed ? String(localized: "\(name): allowed") : String(localized: "\(name): off"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state == .allowed ? String(localized: "\(name): allowed")
                            : state == .denied ? String(localized: "\(name): off") : String(localized: "\(name): not asked yet"))
    }
}
