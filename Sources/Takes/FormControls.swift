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

/// A small screen with the spots the panel can open at. "Next to the text box" sits on the dashed text box;
/// the others are fixed spots on the screen. Whichever is picked, the panel still moves aside rather than cover
/// the text box.
struct PanelPositionPicker: View {
    @Binding var selection: PanelPosition
    private let screen = CGSize(width: 240, height: 150)
    private let spot = CGSize(width: 40, height: 24)
    /// The text box being written in, drawn on the right so "next to it" stays clear of the fixed spots.
    private let textBox = CGRect(x: 150, y: 94, width: 76, height: 10)

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(Theme.chrome)
                RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.controlBorder)
                // The text box the person is writing in, with "next to it" just above.
                RoundedRectangle(cornerRadius: 3).fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.dashed, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                    .frame(width: textBox.width, height: textBox.height)
                    .offset(x: textBox.minX, y: textBox.minY)
                ForEach(PanelPosition.allCases) { position in
                    let frame = spotFrame(position)
                    let selected = position == selection
                    Button { selection = position } label: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(selected ? Theme.accent : Theme.surface)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(selected ? Theme.accent : Theme.controlBorder))
                            .frame(width: frame.width, height: frame.height)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(position.label)
                    .accessibilityLabel(position.label)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .offset(x: frame.minX, y: frame.minY)
                }
            }
            .frame(width: screen.width, height: screen.height)
            Text(selection.label).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 10)
    }

    /// The spot's place on the little screen (top-left origin).
    private func spotFrame(_ position: PanelPosition) -> CGRect {
        let inset: CGFloat = 8
        let left = inset, centre = (screen.width - spot.width) / 2, right = screen.width - spot.width - inset
        let top = inset, middle = (screen.height - spot.height) / 2, bottom = screen.height - spot.height - inset
        switch position {
        case .nearCursor: return CGRect(origin: CGPoint(x: textBox.midX - spot.width / 2, y: textBox.minY - spot.height - 6), size: spot)
        case .topLeft: return CGRect(origin: CGPoint(x: left, y: top), size: spot)
        case .topCenter: return CGRect(origin: CGPoint(x: centre, y: top), size: spot)
        case .topRight: return CGRect(origin: CGPoint(x: right, y: top), size: spot)
        case .center: return CGRect(origin: CGPoint(x: centre, y: middle), size: spot)
        case .bottomLeft: return CGRect(origin: CGPoint(x: left, y: bottom), size: spot)
        case .bottomCenter: return CGRect(origin: CGPoint(x: centre, y: bottom), size: spot)
        case .bottomRight: return CGRect(origin: CGPoint(x: right, y: bottom), size: spot)
        }
    }
}
