import AppKit
import SwiftUI

/// The Takes mark: the brand book's compact t, where the light t flows into the bubble's tail.
/// Drawn on a 1000-high grid (y down) from `brand/mark-t.svg`. The t is a hole, so fill it even-odd.
enum BrandMark {
    static let bounds = CGRect(x: 0, y: 0, width: 995.5, height: 1000)

    /// The bubble with the t cut out, fitted into `rect`.
    static func path(in rect: CGRect, flipped: Bool = false) -> CGPath {
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        var transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: flipped ? -scale : scale)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
        return master.copy(using: &transform) ?? master
    }

    /// Builds the path from `outline`, which uses only absolute M, L, C and Z.
    private static let master: CGPath = {
        let path = CGMutablePath()
        var tokens = outline.split(separator: " ")[...]
        func point() -> CGPoint {
            let x = Double(tokens.popFirst() ?? "") ?? 0
            let y = Double(tokens.popFirst() ?? "") ?? 0
            return CGPoint(x: x, y: y)
        }
        while let command = tokens.popFirst() {
            switch command {
            case "M": path.move(to: point())
            case "L": path.addLine(to: point())
            case "C":
                let control1 = point(), control2 = point()
                path.addCurve(to: point(), control1: control1, control2: control2)
            case "Z": path.closeSubpath()
            default: break
            }
        }
        return path
    }()

    private static let outline =
        "M 530.2 2.5 C 517.5 3.1 481.1 7.6 461.5 11 C 364.9 27.8 262 74.1 185.8 135.1 C 93.6 209 34 299.8 11.8 400.3 C " +
        "-13.6 515.5 15.4 637.9 89.1 725.9 C 171.7 824.5 291.8 882.3 454 901.5 C 475.9 904.1 501.1 905.3 566.2 906.6 C " +
        "645 908.2 657.7 908.9 671 912.3 C 693.1 918 711.9 927.1 743 946.8 C 776.9 968.3 797.4 979.1 818.7 986.4 C 875.2 " +
        "1005.9 921.6 997.7 921.6 968.3 C 921.6 960.9 918.8 955.3 904.2 933.2 C 898.4 924.5 892.6 915.3 891.3 912.8 C 882 " +
        "895.6 878.4 882.1 877.8 862.1 C 876.8 831.9 885.8 806.7 912.5 764.6 C 931 735.5 950.3 698 962.8 666.8 C 971.8 " +
        "644.4 981 609.1 987 573.9 C 991.7 546.5 992.5 534.2 992.9 484 C 993.3 436 992.6 419 989.2 395.6 C 978.9 322.6 " +
        "964.3 271.8 939.6 221.5 C 901.8 145.1 847.3 87.6 776.7 49.9 C 729.1 24.4 660 5.5 605.6 3 C 591.2 2.3 540.6 2 " +
        "530.2 2.5 Z M 550.4 48 C 569.3 48.8 576.2 49.9 589.4 54.2 C 625.9 66.4 646 89.5 648.9 122.5 C 651.2 150.8 639.3 " +
        "176.8 607.8 212 C 583.2 239.5 578.7 245.5 576.6 253.2 C 575.6 257.2 575.4 267.5 576.3 270.6 C 578.3 277.4 586.7 " +
        "280.5 602.9 280.5 C 617.7 280.5 622 279.4 656.6 267.1 C 700.9 251.4 720 247.1 744 247.1 C 778.5 247.1 805.1 " +
        "260.7 818.8 285.4 C 828 301.9 829.5 322.3 823.1 342.6 C 816.9 362.3 801.5 381.7 781.5 395.1 C 749.4 416.6 715.4 " +
        "421.9 656.2 414.3 C 632.1 411.3 626.5 410.9 609.1 410.8 C 574.5 410.8 557.2 417 538.4 436.4 C 516.7 458.7 509.8 " +
        "480.5 511.5 521.5 C 512.1 537.2 514.3 546.2 520.7 559.2 C 530.4 578.9 544.3 591.9 563.5 599.1 C 572.6 602.4 " +
        "587.3 603.7 603.1 602.4 C 626.2 600.5 636.7 597 683.1 574.9 C 732.8 551.2 739.3 548.7 759.5 544.8 C 771.4 542.5 " +
        "774 542.2 787.5 542.2 C 799.7 542.3 800.8 542.3 806.9 543.6 C 817.8 545.9 828.9 550 837.8 555 C 875.2 576.1 " +
        "892.9 628.1 881.6 684.3 C 877 707.2 869.1 729 851 768.5 C 833.6 806.6 828.2 827.1 828.8 852.1 C 829.5 877.6 " +
        "837.7 903 853.7 929.4 C 856.1 933.2 859.9 939.5 862.3 943.4 C 864.7 947.3 866.6 950.8 866.6 951.2 C 866.6 955.1 " +
        "838.7 947.6 821.6 939 C 805.9 931.2 784.8 911.7 765.4 887.2 C 748.1 865.4 739 857.3 722.4 849.2 C 709.3 842.9 " +
        "708.1 842.7 683.5 842.7 C 656 842.7 648.4 843.4 620.1 849 C 570.3 858.7 553.5 860.3 504.5 860.3 C 464.6 860.3 " +
        "452.3 859.4 430.9 855.1 C 355.8 840.1 307.5 807.4 281.2 754 C 267.5 726 264.1 709.8 264.1 670.6 C 264 626.1 " +
        "271.2 598.2 297.5 541.3 C 313.1 507.1 315.2 500.9 315.2 487.1 C 315.2 471.3 310.5 463.5 299 460.5 C 285.8 457.2 " +
        "274.2 460.8 234 481 C 190.1 503 175 507.7 146 508.3 C 118.4 508.9 101.1 504.9 85.3 494.4 C 70.7 484.7 56.4 463.4 " +
        "53.9 447.6 C 53.3 443.3 53.3 419.5 54 413.8 C 57.2 386.9 79.5 354.3 109.9 332.1 C 134.4 314.2 158.8 304.3 205.5 " +
        "293.3 C 238.7 285.4 257 277.7 275.2 263.7 C 290.7 251.9 299.4 241.1 308.8 221.8 C 331 176.4 332.7 173.2 341.9 " +
        "159.4 C 366.3 122.4 400.3 92.9 442.6 71.9 C 474.4 56.2 498.3 49.4 526.1 48 C 537.3 47.5 538.2 47.5 550.4 48 Z"

    /// Menu-bar template image; `alert` adds a dot when setup needs attention.
    static func menuBarImage(alert: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(path(in: rect.insetBy(dx: 0.5, dy: 0.5), flipped: true))
            context.fillPath(using: .evenOdd)
            if alert {
                let dot = CGRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 6, height: 6)
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
