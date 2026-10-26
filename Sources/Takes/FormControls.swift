import SwiftUI

/// Designed form controls for the Settings and Setup windows, matching the mockups
/// instead of the default macOS look.
extension Theme {
    static let selectedRow = Color.dynamic(light: "#E1E4F2", dark: "#2B3352")
    static let sidebar = Color.dynamic(light: "#FAFAFB", dark: "#202024")
    static let chrome = Color.dynamic(light: "#F4F4F6", dark: "#26262B")
    static let dashed = Color.dynamic(light: "#A8A8B2", dark: "#5E5E68")
}

/// Centered section tabs, as in the mockup's settings title bar.
struct TabPills<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Theme.text : Theme.controlText)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Theme.selectedRow : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// A row of choices joined together; the chosen one is filled dark ("Same as draft | English | עברית").
struct ChoiceSegments<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.value) { index, option in
                let selected = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(.system(size: 13))
                        .foregroundStyle(selected ? Theme.surface : Theme.controlText)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(selected ? Theme.controlText : Theme.surface)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                if index < options.count - 1 { Rectangle().fill(Theme.controlBorder).frame(width: 1, height: 32) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.controlBorder))
        .fixedSize()
    }
}

struct StyledTextField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    var height: CGFloat = 36
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 14))
        .focused($focused)
        .onSubmit(onSubmit)
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(focused ? Theme.accent : Theme.controlBorder, lineWidth: focused ? 1.5 : 1))
    }
}

struct StyledTextEditor: View {
    @Binding var text: String
    var height: CGFloat = 70
    var fontSize: CGFloat = 14
    var fill: Color = Theme.surface
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: fontSize))
            .lineSpacing(3)
            .scrollContentBackground(.hidden)
            .focused($focused)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 8).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(focused ? Theme.accent : Theme.controlBorder, lineWidth: focused ? 1.5 : 1))
    }
}

struct Checkbox: View {
    @Binding var isOn: Bool
    var label = ""

    var body: some View {
        Button { isOn.toggle() } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(isOn ? Theme.accent : Theme.surface)
                .frame(width: 16, height: 16)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(isOn ? Theme.accent : Theme.dashed))
                .overlay(Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white).opacity(isOn ? 1 : 0))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "on" : "off")
    }
}

/// "+ Add"-style dashed button.
struct DashedButtonStyle: ButtonStyle {
    var capsule = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(Theme.controlText)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: capsule ? 14 : 7)
                    .stroke(Theme.dashed, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

struct FieldLabel: View {
    let text: String
    var color: Color = Theme.secondaryText
    init(_ text: String, color: Color = Theme.secondaryText) { self.text = text; self.color = color }
    var body: some View { Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(color) }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text) }
}

/// A rounded white group of rows with dividers, as in the mockup's settings lists.
struct RowGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }
}

struct RowDivider: View {
    var body: some View { Rectangle().fill(Theme.border).frame(height: 1) }
}

/// "Takes 3 · Model Sonnet 5.5 · …": a label followed by a menu button.
struct LabeledMenu<Value: Hashable>: View {
    let label: String
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.secondaryText).fixedSize()
            MenuPicker(options: options, selection: $selection)
        }
    }
}
