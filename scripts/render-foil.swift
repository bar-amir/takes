import AppKit

// render-foil <app|sticker> <pixels> <out.png> [small]
// Draws the Night (holographic) edition of the compact t: a Paper die-cut rim, an Ink bubble,
// and the t in foil (brand/foil-texture.jpg masked to the exact master path, brand/t-paths.json).
//   app      the app icon: an Ink tile on the macOS grid (824 of 1024, radius 186) holding the sticker
//   sticker  the sticker alone on transparency, for the disk image's icon
//   small    a heavier rim and a bigger mark, for 16 and 32 px
let args = CommandLine.arguments
guard args.count >= 4, let pixels = Int(args[2]), ["app", "sticker"].contains(args[1]) else {
    FileHandle.standardError.write("usage: render-foil <app|sticker> <pixels> <out.png> [small]\n".data(using: .utf8)!)
    exit(1)
}
let app = args[1] == "app", small = args.count > 4 && args[4] == "small"
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let data = try Data(contentsOf: root.appendingPathComponent("brand/t-paths.json"))
let paths = try JSONDecoder().decode([String].self, from: data)
let foil = NSImage(contentsOf: root.appendingPathComponent("brand/foil-texture.jpg"))!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let ink = color(0x171714), paper = color(0xF3EBDD)

/// The masters use only absolute M, C and Z.
func parse(_ d: String) -> CGPath {
    let path = CGMutablePath()
    var numbers: [CGFloat] = [], command = ""
    for token in d.split(separator: " ") {
        if let value = Double(token) {
            numbers.append(value)
            if command == "M", numbers.count == 2 { path.move(to: CGPoint(x: numbers[0], y: numbers[1])); numbers = [] }
            if command == "C", numbers.count == 6 {
                path.addCurve(to: CGPoint(x: numbers[4], y: numbers[5]), control1: CGPoint(x: numbers[0], y: numbers[1]),
                              control2: CGPoint(x: numbers[2], y: numbers[3]))
                numbers = []
            }
        } else {
            command = String(token)
            if command == "Z" { path.closeSubpath() }
        }
    }
    return path
}
let bubble = parse(paths[0]), letter = parse(paths[1])

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let ns = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ns
let cg = ns.cgContext
cg.interpolationQuality = .high
// Work on a 1024 grid, y down like the SVG masters.
cg.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
cg.translateBy(x: 0, y: 1024)
cg.scaleBy(x: 1, y: -1)

if app {
    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 186, cornerHeight: 186, transform: nil)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: color(0x000000, 0.35))
    cg.addPath(tile)
    cg.setFillColor(ink)
    cg.fillPath()
    cg.restoreGState()
    // A soft light from above, so the tile isn't a flat hole in the Dock.
    cg.saveGState()
    cg.addPath(tile)
    cg.clip()
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0x34342E), color(0x171714), color(0x10100E)] as CFArray,
                          locations: [0, 0.55, 1])!
    cg.drawLinearGradient(glow, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    cg.restoreGState()
}

// Place the 1000-grid mark.
let markSize: CGFloat = app ? (small ? 780 : 620) : 860
let origin = CGPoint(x: (1024 - markSize) / 2, y: (1024 - markSize) / 2 - (app ? 4 : 10))
cg.translateBy(x: origin.x, y: origin.y)
cg.scaleBy(x: markSize / 1000, y: markSize / 1000)

let rim: CGFloat = small ? 80 : (app ? 64 : 72)
if !app {
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: 18), blur: 30, color: color(0x000000, 0.3))
    cg.addPath(bubble)
    cg.setLineWidth(rim)
    cg.setLineJoin(.round)
    cg.setStrokeColor(paper)
    cg.setFillColor(paper)
    cg.drawPath(using: .fillStroke)
    cg.restoreGState()
}
cg.addPath(bubble)
cg.setLineWidth(rim)
cg.setLineJoin(.round)
cg.setStrokeColor(paper)
cg.setFillColor(paper)
cg.drawPath(using: .fillStroke)
cg.addPath(bubble)
cg.setFillColor(ink)
cg.fillPath()

// The foil, clipped to the t. The texture's sheen runs corner to corner across the mark.
cg.saveGState()
cg.addPath(letter)
cg.clip()
let box = letter.boundingBoxOfPath.insetBy(dx: -40, dy: -40)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
foil.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
NSGraphicsContext.restoreGraphicsState()
// A faint inner edge, so the foil reads as a separate layer printed on the bubble.
cg.addPath(letter)
cg.setLineWidth(small ? 0 : 10)
cg.setStrokeColor(color(0x000000, 0.18))
cg.strokePath()
cg.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
