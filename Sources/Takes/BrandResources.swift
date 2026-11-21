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

    /// The opening screen's key-press loop (`Resources/Onboarding/opening-loop.mp4`), when it's there.
    static var openingLoop: URL? {
        guard let url = folder?.appendingPathComponent("Onboarding/opening-loop.mp4") else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

extension Font {
    /// Whether the app's language is written in Latin, Cyrillic or Greek letters. Mono labels and letter spacing are
    /// for those; Hebrew, Arabic, Japanese, Devanagari and other scripts fall back to wide, broken-up glyphs with them.
    static let spacedLabels = spacesLabels(Bundle.main.preferredLocalizations.first ?? "en")

    static func spacesLabels(_ language: String) -> Bool {
        let script = Locale.Language(identifier: language).maximalIdentifier.split(separator: "-").first { $0.count == 4 }
        return ["Latn", "Cyrl", "Grek"].contains(script.map { String($0) } ?? "Latn")
    }

    /// Letter spacing for a small label, or none where the script doesn't take it.
    static func labelSpacing(_ value: CGFloat) -> CGFloat { spacedLabels ? value : 0 }

    /// Mono labels (TAKE 1, keycaps, small cues), set in JetBrains Mono like the website; falls back to SF Mono.
    /// In other scripts, the system font.
    static func mono(_ size: CGFloat, bold: Bool = false) -> Font {
        guard spacedLabels else { return .system(size: size, weight: bold ? .bold : .medium) }
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
