import AppKit
import SwiftUI

/// The Takes mark: the logo's speech bubble with two groovy lines of "text" cut out of it.
/// Drawn on the brand artwork's 1024 grid (y down); see `brand/mark.svg`.
enum BrandMark {
    static let bounds = CGRect(x: 118, y: 150, width: 787, height: 742)
    static let lineWidth: CGFloat = 64

    /// The bubble with the lines already cut out.
    static func path(in rect: CGRect, flipped: Bool = false) -> CGPath {
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        var transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: flipped ? -scale : scale)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
        let lines = self.lines().copy(strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
        let mark = bubble().subtracting(lines)
        return mark.copy(using: &transform) ?? mark
    }

    private static func bubble() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 500, y: 160))
        p.addCurve(to: CGPoint(x: 905, y: 455), control1: CGPoint(x: 740, y: 150), control2: CGPoint(x: 905, y: 280))
        p.addCurve(to: CGPoint(x: 712, y: 726), control1: CGPoint(x: 905, y: 590), control2: CGPoint(x: 820, y: 680))
        // The tail, with the logo's fat rounded tip.
        p.addCurve(to: CGPoint(x: 800, y: 838), control1: CGPoint(x: 718, y: 772), control2: CGPoint(x: 748, y: 812))
        p.addCurve(to: CGPoint(x: 796, y: 888), control1: CGPoint(x: 826, y: 851), control2: CGPoint(x: 828, y: 884))
        p.addCurve(to: CGPoint(x: 600, y: 800), control1: CGPoint(x: 716, y: 896), control2: CGPoint(x: 640, y: 860))
        p.addCurve(to: CGPoint(x: 500, y: 808), control1: CGPoint(x: 566, y: 806), control2: CGPoint(x: 532, y: 808))
        p.addCurve(to: CGPoint(x: 118, y: 470), control1: CGPoint(x: 262, y: 808), control2: CGPoint(x: 118, y: 660))
        p.addCurve(to: CGPoint(x: 500, y: 160), control1: CGPoint(x: 118, y: 290), control2: CGPoint(x: 270, y: 168))
        p.closeSubpath()
        return p
    }

    private static func lines() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 290, y: 395))
        p.addCurve(to: CGPoint(x: 500, y: 395), control1: CGPoint(x: 360, y: 330), control2: CGPoint(x: 420, y: 460))
        p.addCurve(to: CGPoint(x: 720, y: 395), control1: CGPoint(x: 580, y: 330), control2: CGPoint(x: 640, y: 330))
        p.move(to: CGPoint(x: 290, y: 575))
        p.addCurve(to: CGPoint(x: 480, y: 575), control1: CGPoint(x: 350, y: 515), control2: CGPoint(x: 410, y: 635))
        p.addCurve(to: CGPoint(x: 600, y: 560), control1: CGPoint(x: 550, y: 515), control2: CGPoint(x: 560, y: 520))
        return p
    }

    /// Menu-bar template image; `alert` adds a dot when setup needs attention.
    static func menuBarImage(alert: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(path(in: rect.insetBy(dx: 1, dy: 1), flipped: true))
            context.fillPath()
            if alert {
                let dot = CGRect(x: rect.maxX - 7, y: rect.maxY - 7, width: 7, height: 7)
                context.setBlendMode(.clear)
                context.fillEllipse(in: dot.insetBy(dx: -1.5, dy: -1.5))
                context.setBlendMode(.normal)
                context.fillEllipse(in: dot)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = alert ? "Takes needs setup" : "Takes"
        return image
    }
}

struct BrandMarkShape: Shape {
    func path(in rect: CGRect) -> Path { Path(BrandMark.path(in: rect)) }
}
