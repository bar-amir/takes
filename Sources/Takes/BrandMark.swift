import AppKit
import SwiftUI

/// The Takes mark, the compact t: a speech bubble whose light t flows into the tail.
/// Drawn from the brand master's 1000 grid (y down); see `brand/t-mark.svg`.
enum BrandMark {
    static let bounds = CGRect(x: 25, y: 30, width: 945, height: 948)
    /// Extra outline for small sizes, so the bubble's edge survives at 16 px. The t keeps its exact shape.
    static let smallRim: CGFloat = 90

    /// The bubble with the t cut out. `small` thickens the bubble's outline for 16–32 px use.
    static func path(in rect: CGRect, flipped: Bool = false, small: Bool = false) -> CGPath {
        let inset = small ? smallRim / 2 : 0
        let frame = bounds.insetBy(dx: -inset, dy: -inset)
        let scale = min(rect.width / frame.width, rect.height / frame.height)
        var transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: flipped ? -scale : scale)
            .translatedBy(x: -frame.midX, y: -frame.midY)
        var outline = bubble
        if small {
            outline = outline.union(outline.copy(strokingWithWidth: smallRim, lineCap: .round, lineJoin: .round, miterLimit: 10))
        }
        let mark = outline.subtracting(letter)
        return mark.copy(using: &transform) ?? mark
    }

    /// Menu-bar template image; `alert` adds a dot when setup needs attention.
    static func menuBarImage(alert: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(path(in: rect.insetBy(dx: 0.5, dy: 0.5), flipped: true, small: true))
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
        image.accessibilityDescription = alert ? String(localized: "Takes needs setup") : "Takes"
        return image
    }

    private static let bubble = parse(bubbleData)
    private static let letter = parse(tData)

    /// Reads the masters' path data, which uses only absolute M, C and Z.
    private static func parse(_ data: String) -> CGPath {
        let path = CGMutablePath()
        var numbers: [CGFloat] = []
        var command: Character = " "
        func flush() {
            switch command {
            case "M" where numbers.count == 2:
                path.move(to: CGPoint(x: numbers[0], y: numbers[1]))
            case "C" where numbers.count == 6:
                path.addCurve(to: CGPoint(x: numbers[4], y: numbers[5]),
                              control1: CGPoint(x: numbers[0], y: numbers[1]), control2: CGPoint(x: numbers[2], y: numbers[3]))
            case "Z":
                path.closeSubpath()
            default:
                break
            }
            numbers = []
        }
        for token in data.split(separator: " ") {
            if let value = Double(token) {
                numbers.append(value)
                if command == "C", numbers.count == 6 { flush() }
            } else {
                flush()
                command = token.first ?? " "
                if command == "Z" { flush(); command = " " }
            }
        }
        flush()
        return path
    }

    private static let bubbleData = """
        M 521.320 31.163 C 518.219 31.551 507.171 32.907 497.093 34.070 C 432.359 41.435 371.113 60.041 306.186 91.827 C \
        251.142 118.961 206.953 150.165 162.957 192.804 C 44.342 308.318 2.672 463.175 52.289 605.629 C 70.507 657.765 98.029 \
        700.986 139.505 742.268 C 216.643 819.406 326.730 865.922 468.021 880.845 C 479.262 882.202 524.614 883.753 568.804 \
        884.528 C 641.291 886.078 650.788 886.466 664.161 890.148 C 685.287 895.769 705.637 905.847 732.577 923.485 C 745.369 \
        931.819 764.557 943.060 775.216 948.293 C 834.136 978.140 895.575 976.784 899.452 945.773 C 900.614 936.664 897.707 \
        930.849 879.682 904.491 C 865.340 883.559 859.526 867.860 858.169 845.959 C 856.231 816.111 865.728 788.977 892.474 \
        748.082 C 910.305 720.367 935.113 670.363 943.641 644.004 C 951.781 618.808 958.953 587.410 963.604 556.206 C 967.868 \
        527.522 968.449 438.755 964.573 409.876 C 954.301 334.482 939.959 283.509 914.569 233.505 C 876.775 158.693 820.375 \
        102.487 749.245 68.569 C 712.808 51.126 660.672 36.784 616.870 32.132 C 599.621 30.194 535.080 29.612 521.320 31.163 Z
        """
    private static let tData = """
        M 584.697 79.035 C 619.971 90.470 639.740 112.953 642.066 144.157 C 644.004 172.647 632.181 197.262 599.621 232.536 C \
        588.186 245.134 577.332 258.313 575.588 261.802 C 572.680 268.198 571.711 279.245 573.843 284.866 C 576.944 293.006 \
        597.682 296.107 616.870 291.262 C 621.909 290.099 637.608 284.866 651.951 279.633 C 695.365 263.740 723.856 258.701 \
        748.082 262.577 C 824.252 274.788 832.586 362.392 761.649 405.031 C 732.771 422.280 700.210 426.544 650.400 419.761 C \
        587.410 411.233 560.276 416.272 536.631 441.274 C 518.412 460.462 511.823 479.262 512.016 511.629 C 512.016 528.491 \
        512.986 535.662 516.280 545.353 C 525.196 570.936 541.476 587.798 564.540 595.163 C 578.495 599.621 609.311 598.070 \
        626.948 592.062 C 633.926 589.736 656.602 579.852 677.340 569.773 C 722.305 548.454 726.569 546.709 745.757 542.833 C \
        773.860 537.019 796.730 539.732 819.212 551.748 C 840.726 563.184 856.231 586.054 862.239 615.707 C 869.992 653.113 \
        862.239 691.101 835.493 748.276 C 820.181 781.225 815.530 795.179 812.623 815.142 C 808.553 844.408 816.887 876.388 \
        837.237 908.948 C 843.052 918.252 847.897 926.198 847.897 926.586 C 847.897 930.849 816.499 921.740 801.575 913.212 C \
        788.202 905.654 767.076 885.691 752.928 867.278 C 736.841 846.540 726.763 837.431 711.258 830.066 C 697.885 823.864 \
        697.303 823.670 671.526 823.864 C 651.369 823.864 639.740 825.027 620.165 828.903 C 571.711 838.788 551.361 840.920 \
        505.814 840.920 C 470.540 840.726 459.105 840.144 440.111 836.656 C 357.159 821.344 305.992 781.612 284.866 716.103 C \
        280.408 702.148 279.439 695.171 278.664 671.526 C 277.113 625.979 284.478 594.194 309.093 541.670 C 324.792 507.946 \
        326.730 502.132 327.118 488.565 C 327.505 470.928 319.753 462.206 303.472 462.206 C 293.200 462.206 279.052 467.633 \
        250.173 482.557 C 211.992 502.520 191.641 508.722 162.763 508.722 C 124.000 508.722 99.386 495.155 85.431 466.082 C \
        80.004 454.454 79.423 451.934 79.616 434.103 C 79.616 418.598 80.586 412.396 84.268 403.093 C 97.254 369.563 125.551 \
        341.460 164.313 323.629 C 178.849 316.845 200.169 310.449 231.567 303.278 C 259.282 296.882 283.122 284.672 299.596 \
        268.392 C 311.031 256.957 314.520 251.724 324.598 230.210 C 339.909 198.037 342.816 192.610 354.252 175.555 C 375.959 \
        143.188 409.682 114.503 447.670 95.897 C 484.882 77.872 508.528 72.445 545.546 73.414 C 564.928 73.996 572.874 75.159 \
        584.697 79.035 Z
        """
}

struct BrandMarkShape: Shape {
    var small = false
    func path(in rect: CGRect) -> Path { Path(BrandMark.path(in: rect, small: small)) }
}

extension BrandMarkShape {
    /// The mark filled with `style`. A logo keeps its shape in right-to-left languages, where SwiftUI would mirror a shape.
    func fill<S: ShapeStyle>(_ style: S) -> some View {
        _ShapeView(shape: self, style: style).environment(\.layoutDirection, .leftToRight)
    }
}
