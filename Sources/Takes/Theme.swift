import SwiftUI

enum Theme {
    static let accent = Color(hex: "#2F55E0")
    static let accentSoft = Color(hex: "#EEF2FE")
    static let doText = Color(hex: "#14513A")
    static let doFill = Color(hex: "#E6F2EC")
    static let avoidText = Color(hex: "#8A2418")
    static let avoidFill = Color(hex: "#FBEAE7")
    static let border = Color.primary.opacity(0.12)
    static let strip = Color.primary.opacity(0.035)
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

/// A keycap, as in the mockups' key hints.
struct Kbd: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.15)))
    }
}

/// "⇥ presets"-style hint: keycaps followed by a label.
struct KeyHint: View {
    let keys: [String]
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { Kbd($0) }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct Chip: View {
    enum Style { case positive, negative, neutral }
    let text: String
    var style: Style = .neutral

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(background))
    }

    private var foreground: Color {
        switch style {
        case .positive: return Theme.doText
        case .negative: return Theme.avoidText
        case .neutral: return .primary
        }
    }

    private var background: Color {
        switch style {
        case .positive: return Theme.doFill
        case .negative: return Theme.avoidFill
        case .neutral: return Color.primary.opacity(0.06)
        }
    }
}

struct PresetDot: View {
    let hex: String
    var body: some View { Circle().fill(Color(hex: hex)).frame(width: 8, height: 8) }
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
