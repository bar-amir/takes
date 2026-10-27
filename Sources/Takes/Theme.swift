import AppKit
import SwiftUI

/// Colors and controls from the mockups. The panel never activates Takes (the app being typed in keeps
/// focus), and macOS draws native controls in inactive windows washed out, so the panel uses these instead.
enum Theme {
    static let accent = Color(hex: "#2F55E0")
    static let accentSoft = Color.dynamic(light: "#EEF2FE", dark: "#24304F")
    static let text = Color.dynamic(light: "#1C1C1F", dark: "#F2F2F5")
    static let secondaryText = Color.dynamic(light: "#55555E", dark: "#A9A9B3")
    static let tertiaryText = Color.dynamic(light: "#8A8A94", dark: "#7A7A84")
    static let controlText = Color.dynamic(light: "#3A3A42", dark: "#D8D8DE")
    static let surface = Color.dynamic(light: "#FFFFFF", dark: "#1D1D21")
    static let strip = Color.dynamic(light: "#F7F7F9", dark: "#242429")
    static let border = Color.dynamic(light: "#E2E2E6", dark: "#36363D")
    static let controlBorder = Color.dynamic(light: "#D9D9DF", dark: "#45454D")
    static let kbdFill = Color.dynamic(light: "#F1F1F4", dark: "#2C2C32")
    static let doText = Color.dynamic(light: "#14513A", dark: "#8FD9B4")
    static let doFill = Color.dynamic(light: "#E6F2EC", dark: "#1C3A2D")
    static let avoidText = Color.dynamic(light: "#8A2418", dark: "#F2A196")
    static let avoidFill = Color.dynamic(light: "#FBEAE7", dark: "#43231F")
}

/// One spacing scale for the panel, so every screen has the same rhythm (in points).
enum Spacing {
    /// Side margin of every panel row.
    static let gutter: CGFloat = 20
    /// Above and below the controls in a bar (header, strips, footer).
    static let bar: CGFloat = 14
    /// Between blocks in the content area: cards, the refine bar, the rules around them. Also card padding.
    static let section: CGFloat = 16
    /// Between the pieces inside a card or a row.
    static let inner: CGFloat = 12
    /// Between a control and its label, or icons in a group.
    static let item: CGFloat = 8
    /// Height of the controls in a bar.
    static let control: CGFloat = 32
}

extension Color {
    init(hex: String) { self.init(nsColor: NSColor(hex: hex)) }

    /// A color that follows light and dark mode.
    static func dynamic(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

extension NSColor {
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Buttons

/// The blue call to action ("Write 3 takes ↵", "Paste take 1 ↵").
struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 36
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.accent.opacity(configuration.isPressed ? 0.82 : 1)))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

/// White, bordered ("Edit draft ⌘E", "New preset ⌘N").
struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 32
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(Theme.controlText)
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 8).fill(configuration.isPressed ? Theme.strip : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.controlBorder))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

/// Preset chips and toggles; `selected` gets the accent outline and tint.
struct PillButtonStyle: ButtonStyle {
    var selected = false
    var height: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? Theme.text : Theme.controlText)
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.accentSoft : (configuration.isPressed ? Theme.strip : Theme.surface)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.accent : Theme.controlBorder, lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
    }
}

/// "1 2 3 4 5" with the chosen one filled in the accent color.
struct NumberSegments: View {
    @Binding var selection: Int
    var range: ClosedRange<Int> = 1...5
    var label = "Number of takes"

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(range), id: \.self) { number in
                Button { selection = number } label: {
                    Text("\(number)")
                        .font(.system(size: 13, weight: number == selection ? .semibold : .regular))
                        .foregroundStyle(number == selection ? .white : Theme.controlText)
                        .frame(width: 32, height: 30)
                        .background(number == selection ? Theme.accent : Theme.surface)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(number == selection ? .isSelected : [])
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.controlBorder))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// A bordered "Sonnet 5.5 ▾" button that opens a native menu of choices.
struct MenuPicker<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        Button(action: showMenu) {
            HStack(spacing: 6) {
                Text(options.first { $0.value == selection }?.title ?? "–").font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Theme.text)
        }
        .buttonStyle(SecondaryButtonStyle(height: 30))
    }

    private func showMenu() {
        let menu = NSMenu()
        for option in options {
            let item = ClosureMenuItem(title: option.title) { selection = option.value }
            item.state = option.value == selection ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}

// MARK: - Small pieces

/// A keycap, as in the mockups' key hints.
struct Kbd: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.controlText)
            .padding(.horizontal, 6)
            .padding(.top, 1)
            .padding(.bottom, 2)
            .background(
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 5).fill(Theme.controlBorder)
                    RoundedRectangle(cornerRadius: 5).fill(Theme.kbdFill).padding([.horizontal, .top], 1).padding(.bottom, 2)
                }
            )
    }
}

/// "⇥ presets"-style hint: keycaps followed by a label.
struct KeyHint: View {
    let keys: [String]
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { Kbd($0) }
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.secondaryText).padding(.leading, 2)
        }
    }
}

struct Chip: View {
    enum Style { case positive, negative, neutral }
    let text: String
    var style: Style = .neutral

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(background))
    }

    private var foreground: Color {
        switch style {
        case .positive: return Theme.doText
        case .negative: return Theme.avoidText
        case .neutral: return Theme.text
        }
    }

    private var background: Color {
        switch style {
        case .positive: return Theme.doFill
        case .negative: return Theme.avoidFill
        case .neutral: return Theme.kbdFill
        }
    }
}

struct PresetDot: View {
    let hex: String
    var body: some View { Circle().fill(Color(hex: hex)).frame(width: 8, height: 8) }
}

/// The accent square with the app glyph, used in the panel header.
struct AppGlyph: View {
    var size: CGFloat = 24
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29)
            .fill(Theme.accent)
            .frame(width: size, height: size)
            .overlay(Image(systemName: "text.bubble.fill").font(.system(size: size * 0.5)).foregroundStyle(.white))
            .accessibilityHidden(true)
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map { $0.width }.max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var items: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
