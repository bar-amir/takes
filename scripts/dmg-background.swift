import AppKit

// dmg-background <out.png> <scale>: draws the disk image window's background at 1x or 2x.
// The window shows 800 x 480 points (Finder won't go much narrower, and a tab bar takes height);
// Takes sits at (240, 230) and Applications at (560, 230), matching scripts/dmg-layout.applescript.
// The canvas runs larger in Paper, so a wider window or taller title bar never shows a white strip.
let args = CommandLine.arguments
guard args.count == 3, let scale = Int(args[2]) else {
    FileHandle.standardError.write("usage: dmg-background <out.png> <scale>\n".data(using: .utf8)!)
    exit(1)
}
let size = NSSize(width: 1200, height: 800)
let ink = NSColor(srgbRed: 0x17 / 255, green: 0x17 / 255, blue: 0x14 / 255, alpha: 1)
let paper = NSColor(srgbRed: 0xF3 / 255, green: 0xEB / 255, blue: 0xDD / 255, alpha: 1)
let muted = NSColor(srgbRed: 0x5C / 255, green: 0x57 / 255, blue: 0x4D / 255, alpha: 1)
let rule = NSColor(srgbRed: 0xD8 / 255, green: 0xCF / 255, blue: 0xBF / 255, alpha: 1)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = context
// Draw top-down, like Finder positions icons.
context.cgContext.translateBy(x: 0, y: size.height)
context.cgContext.scaleBy(x: 1, y: -1)

paper.setFill()
NSRect(origin: .zero, size: size).fill()

let window = CGFloat(800)
func draw(_ text: String, font: NSFont, color: NSColor, centerY: CGFloat, kern: CGFloat = 0) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
    let string = NSAttributedString(string: text, attributes: attributes)
    let bounds = string.size()
    NSGraphicsContext.saveGraphicsState()
    // Text draws upright in a flipped context only when the context says it's flipped.
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    string.draw(at: NSPoint(x: (window - bounds.width) / 2, y: centerY - bounds.height / 2))
    NSGraphicsContext.restoreGraphicsState()
}

let headline = NSFont(name: "DINCondensed-Bold", size: 34) ?? .systemFont(ofSize: 30, weight: .heavy)
draw("DRAG TAKES INTO APPLICATIONS", font: headline, color: ink, centerY: 72, kern: 0.5)
draw("Then open it from Applications. It lives in your menu bar.",
     font: NSFont(name: "Arial", size: 13) ?? .systemFont(ofSize: 13), color: muted, centerY: 108)

// A liquid arrow from Takes to Applications, in the spirit of the wordmark's tail.
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 326, y: 236))
arrow.curve(to: NSPoint(x: 400, y: 230), controlPoint1: NSPoint(x: 348, y: 208), controlPoint2: NSPoint(x: 376, y: 256))
arrow.curve(to: NSPoint(x: 468, y: 228), controlPoint1: NSPoint(x: 424, y: 204), controlPoint2: NSPoint(x: 446, y: 214))
arrow.lineWidth = 7
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
ink.setStroke()
arrow.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 452, y: 210))
head.line(to: NSPoint(x: 474, y: 229))
head.line(to: NSPoint(x: 450, y: 244))
head.lineWidth = 7
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.stroke()

rule.setFill()
NSRect(x: 48, y: 362, width: window - 96, height: 1).fill()
draw("ONE DRAFT. A FEW TAKES. YOUR CHOICE.", font: NSFont(name: "Courier New", size: 11) ?? .monospacedSystemFont(ofSize: 11, weight: .regular),
     color: muted, centerY: 392, kern: 1.5)

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
