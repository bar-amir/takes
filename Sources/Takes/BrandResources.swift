import AppKit
import CoreText
import SwiftUI

/// Files that ship inside Takes.app/Contents/Resources: the mono label font and the onboarding photo.
/// `scripts/assemble-app.sh` copies them from `Resources/`. Builds without them (tests, `swift run`) fall back quietly.
enum BrandResources {
    /// The app's Resources folder, or the repository's `Resources/` when running from `.build`.
    static var folder: URL? {
        if let url = Bundle.main.resourceURL, FileManager.default.fileExists(atPath: url.appendingPathComponent("Fonts").path) {
            return url
        }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources")
        return FileManager.default.fileExists(atPath: repo.path) ? repo : nil
    }

    private static var registered = false

    /// Registers JetBrains Mono (Medium and Bold) for this process. Safe to call more than once.
    static func registerFonts() {
        guard !registered, let fonts = folder?.appendingPathComponent("Fonts") else { return }
        registered = true
        for name in ["JetBrainsMono-Medium", "JetBrainsMono-Bold"] {
            let url = fonts.appendingPathComponent("\(name).ttf")
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// The opening screen's photo (`Resources/Onboarding/opening.jpg`).
    static var openingImage: NSImage? {
        guard let url = folder?.appendingPathComponent("Onboarding/opening.jpg") else { return nil }
        return NSImage(contentsOf: url)
    }
}

extension Font {
    /// Mono labels (TAKE 1, keycaps, small cues), set in JetBrains Mono like the website; falls back to SF Mono.
    static func mono(_ size: CGFloat, bold: Bool = false) -> Font {
        let name = bold ? "JetBrainsMono-Bold" : "JetBrainsMono-Medium"
        if NSFont(name: name, size: size) != nil { return .custom(name, fixedSize: size) }
        return .system(size: size, weight: bold ? .bold : .medium, design: .monospaced)
    }
}

/// One spring and three durations for every motion in the app. Use `Motion.animation(_:)` so Reduce Motion is respected.
enum Motion {
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let quick: Double = 0.12
    static let standard: Double = 0.18
    static let slow: Double = 0.24
    /// Stagger between takes appearing.
    static let stagger: Double = 0.12

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// The given animation, or a plain short fade when Reduce Motion is on.
    static func animation(_ animation: Animation = spring) -> Animation {
        reduceMotion ? .easeOut(duration: quick) : animation
    }
}
