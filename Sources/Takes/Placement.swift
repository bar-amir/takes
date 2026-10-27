import CoreGraphics

/// Where the panel opens: beside the text box being written in, never over it (Cocoa coordinates).
enum PanelPlacement {
    /// Space between the panel and the box.
    static let gap: CGFloat = 12

    /// What the panel must not cover: the whole box, or for a box too tall to step around (a document, a
    /// full-height editor) the caret's line with a line of room above and below.
    static func keepClear(caret: CGRect?, field: CGRect?, visible: CGRect) -> CGRect? {
        if let field, field.height <= visible.height / 3 {
            return caret.map { field.union($0) } ?? field
        }
        guard let caret else { return field }
        return caret.insetBy(dx: 0, dy: -max(caret.height, 16))
    }

    /// Anchor points tried in order: next to the box (above it first, since chat boxes sit at the bottom, then
    /// below, right, left), then fixed spots on the screen (top and bottom centre, the corners, the middle), nearest
    /// to the box first. The panel goes to the first one that fits on screen without touching `keepClear`.
    static func origin(size: CGSize, keepClear box: CGRect, in visible: CGRect) -> CGPoint {
        let area = visible.insetBy(dx: 8, dy: 8)
        let x = clamp(box.minX - Spacing.gutter, area.minX, area.maxX - size.width)
        let y = clamp(box.maxY - size.height, area.minY, area.maxY - size.height)
        let besideBox = [
            CGPoint(x: x, y: box.maxY + gap),
            CGPoint(x: x, y: box.minY - gap - size.height),
            CGPoint(x: box.maxX + gap, y: y),
            CGPoint(x: box.minX - gap - size.width, y: y),
        ]
        let onScreen = [PanelPosition.topCenter, .bottomCenter, .topLeft, .topRight, .bottomLeft, .bottomRight, .center]
            .compactMap { anchor($0, size: size, in: visible) }
            .sorted { distance(CGRect(origin: $0, size: size), box) < distance(CGRect(origin: $1, size: size), box) }
        let anchors = besideBox + onScreen
        if let fit = anchors.first(where: { area.contains(CGRect(origin: $0, size: size)) && !CGRect(origin: $0, size: size).intersects(box) }) {
            return fit
        }
        // Nothing clears it (a panel taller than the room around the box): cover as little of it as possible.
        return onScreen.min { overlap(CGRect(origin: $0, size: size), box) < overlap(CGRect(origin: $1, size: size), box) } ?? CGPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
    }

    /// One of the fixed spots on the screen people can choose in Settings (`nil` for "next to the text box").
    static func anchor(_ position: PanelPosition, size: CGSize, in visible: CGRect) -> CGPoint? {
        let area = visible.insetBy(dx: 8, dy: 8)
        let left = area.minX, centre = area.midX - size.width / 2, right = area.maxX - size.width
        let bottom = area.minY, middle = area.midY - size.height / 2, top = area.maxY - size.height
        switch position {
        case .nearCursor: return nil
        case .topLeft: return CGPoint(x: left, y: top)
        case .topCenter: return CGPoint(x: centre, y: top)
        case .topRight: return CGPoint(x: right, y: top)
        case .center: return CGPoint(x: centre, y: middle)
        case .bottomLeft: return CGPoint(x: left, y: bottom)
        case .bottomCenter: return CGPoint(x: centre, y: bottom)
        case .bottomRight: return CGPoint(x: right, y: bottom)
        }
    }

    /// Where the panel goes for the chosen position: that spot, unless it would cover the text box; then the
    /// first clear anchor beside the box or on the screen.
    static func origin(for position: PanelPosition, size: CGSize, keepClear box: CGRect?, in visible: CGRect) -> CGPoint {
        let middle = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        let chosen = anchor(position, size: size, in: visible)
        guard let box else { return chosen ?? middle }
        if let chosen, !CGRect(origin: chosen, size: size).intersects(box) { return chosen }
        return origin(size: size, keepClear: box, in: visible)
    }

    private static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        hypot(max(0, max(a.minX - b.maxX, b.minX - a.maxX)), max(0, max(a.minY - b.maxY, b.minY - a.maxY)))
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let both = a.intersection(b)
        return both.isNull ? 0 : both.width * both.height
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        max(low, min(value, high))
    }
}
