import AppKit
import SwiftUI

// MARK: - Grouped settings forms

/// The Settings window's grouped form, built by hand so the app's own controls sit in it: a grey section header,
/// a rounded group of rows (label left, control right), and at most one grey line under the group.
extension Theme {
    static let formBackground = Color.dynamic(light: "#F6F4EF", dark: "#1B1B1E")
    static let formGroup = Color.dynamic(light: "#FFFFFF", dark: "#26262B")
    static let formGroupBorder = Color.dynamic(light: "#E6E1D6", dark: "#34343A")
    static let formHeader = Color.dynamic(light: "#6B665C", dark: "#9A9AA3")
    static let formSelectedRow = Color.dynamic(light: "#FBF9F4", dark: "#2C2C32")
}

/// The width every Settings tab uses, except Presets, which is an editor.
enum SettingsMetrics {
    static let width: CGFloat = 780
    static let presetsWidth: CGFloat = 1040
    static let presetsHeight: CGFloat = 660
    static let coachHeight: CGFloat = 640
    /// Taller tabs scroll inside the window rather than grow past this.
    @MainActor static var maxHeight: CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 900
        return max(420, min(760, visible - 140))
    }
}

/// A Settings tab's scrolling page. It takes the height of its content, up to `SettingsMetrics.maxHeight`,
/// so the window can resize to fit it.
struct SettingsPage<Content: View>: View {
    var width: CGFloat = SettingsMetrics.width
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 20)
                .frame(width: width, alignment: .leading)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: SettingsHeightKey.self, value: proxy.size.height)
                })
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: width, height: min(max(contentHeight, 120), SettingsMetrics.maxHeight))
        .onPreferenceChange(SettingsHeightKey.self) { height in
            let rounded = height.rounded(.up)
            if abs(rounded - contentHeight) > 0.5 { contentHeight = rounded }
        }
    }
}

struct SettingsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// "Opening Takes" over a rounded group of rows, with an optional grey line under it.
struct FormSection<Content: View, Footer: View>: View {
    var header: String?
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                Text(header)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.formHeader)
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            FormGroup { content }
            footer
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension FormSection where Footer == EmptyView {
    init(_ header: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(header: header, content: content, footer: { EmptyView() })
    }
}

extension FormSection where Footer == Text {
    init(_ header: String? = nil, footer: String, @ViewBuilder content: () -> Content) {
        self.init(header: header, content: content, footer: { Text(footer) })
    }
}

/// The white rounded box rows sit in.
struct FormGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.formGroup))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.formGroupBorder))
    }
}

/// One row: the label on the left, the control on the right.
struct FormRow<Control: View>: View {
    let label: String
    var detail: String?
    @ViewBuilder var control: Control

    init(_ label: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13)).foregroundStyle(Theme.text)
                if let detail {
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            // The control keeps its size; a long label wraps instead of truncating a menu.
            control.layoutPriority(1)
        }
        .formRowPadding()
    }
}

/// A row with a switch on the right.
struct FormToggle: View {
    let label: String
    var detail: String?
    @Binding var isOn: Bool

    init(_ label: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.label = label
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        FormRow(label, detail: detail) {
            Toggle(label, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

extension View {
    /// The padding every form row uses.
    func formRowPadding() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The hairline between rows, inset from the left like System Settings.
struct FormDivider: View {
    var inset: CGFloat = 14
    var body: some View { Rectangle().fill(Theme.formGroupBorder).frame(height: 1).padding(.leading, inset) }
}

/// A short status pill, only ever on the row it describes ("Signed in", "No key yet").
struct StatusBadge: View {
    let text: String
    let good: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(good ? Theme.doText : Theme.avoidText)
            .background(Capsule().fill(good ? Theme.doFill : Theme.avoidFill))
            .fixedSize()
    }
}

/// A bordered button with red text: "Clear History…", "Remove Key…". Destructive actions go last in their group.
struct DestructiveButtonStyle: ButtonStyle {
    var height: CGFloat = 28
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .lineLimit(1)
            .foregroundStyle(Theme.avoidText)
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 8).fill(configuration.isPressed ? Theme.strip : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.controlBorder))
            .opacity(isEnabled ? 1 : 0.45)
            .fixedSize()
            .contentShape(Rectangle())
    }
}

/// A plain text link in a row ("Check…").
struct FormLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Theme.accent)
            .underline()
            .opacity(configuration.isPressed ? 0.6 : 1)
            .fixedSize()
            .contentShape(Rectangle())
    }
}

/// Asks before something that can't be undone. True when the person confirms.
@MainActor
func confirmDestructive(_ title: String, message: String, button: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
    let confirm = alert.addButton(withTitle: button)
    confirm.hasDestructiveAction = true
    alert.addButton(withTitle: String(localized: "Cancel"))
    return alert.runModal() == .alertFirstButtonReturn
}
