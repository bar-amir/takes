import AppKit
import SwiftUI

/// Onboarding's opening screen: one photograph, the headline and Get started, in a borderless window.
/// Get started (or ↵) shrinks it away and opens the step window. Esc closes it; onboarding resumes from the
/// menu bar or by opening Takes again.
@MainActor
final class OpeningWindowController: NSObject {
    static let shared = OpeningWindowController()
    static let size = CGSize(width: 960, height: 540)

    private var window: NSWindow?
    private let state = OpeningState()

    func show(onStart: @escaping () -> Void) {
        state.leaving = false
        let window = self.window ?? makeWindow()
        self.window = window
        window.alphaValue = 1
        window.hasShadow = true
        window.contentView = NSHostingView(rootView: OpeningView(state: state, onStart: { [weak self] in self?.start(onStart) },
                                                                 onClose: { [weak self] in self?.window?.orderOut(nil) }))
        window.setFrameOrigin(ScreenChoice.centred(window.frame.size, in: ScreenChoice.active.visibleFrame))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func start(_ onStart: @escaping () -> Void) {
        guard !state.leaving else { return }
        window?.hasShadow = false
        withAnimation(Motion.animation(.easeIn(duration: Motion.standard))) { state.leaving = true }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Motion.standard * 1_000_000_000))
            onStart()
            self?.window?.orderOut(nil)
        }
    }

    private func makeWindow() -> NSWindow {
        let window = OpeningWindow(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless],
                                   backing: .buffered, defer: false)
        window.title = String(localized: "Welcome to Takes")
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.fullScreenNone]
        return window
    }
}

/// A borderless window that can take the keyboard, so ↵ and Esc reach it.
private final class OpeningWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class OpeningState: ObservableObject {
    @Published var leaving = false
}

struct OpeningView: View {
    @ObservedObject var state: OpeningState
    var onStart: () -> Void
    var onClose: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    static let ink = Color(hex: "#171714")
    static let paper = Color(hex: "#F3EBDD")
    static let acid = Color(hex: "#E8F449")

    /// DIN Condensed Bold when the Mac has it (it ships with macOS), else the system's condensed bold.
    static func headlineFont(_ size: CGFloat) -> Font {
        if NSFont(name: "DINCondensed-Bold", size: size) != nil { return .custom("DINCondensed-Bold", fixedSize: size) }
        return .system(size: size, weight: .bold).width(.condensed)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            photo
            VStack(alignment: .leading, spacing: 26) {
                // The headline stays in the photo's empty space, left of the cards: a smaller size for a language
                // whose headline runs longer, or whose letters the condensed font doesn't have.
                ViewThatFits(in: .horizontal) {
                    ForEach([62, 54, 46, 40] as [CGFloat], id: \.self) { size in
                        VStack(alignment: .leading, spacing: -6 * size / 62) {
                            Text("WRITE IT ROUGH.")
                            Text("PICK YOUR TAKE.")
                        }
                        .font(Self.headlineFont(size))
                        .fixedSize()
                    }
                }
                .frame(maxWidth: 340)
                .foregroundStyle(Self.ink)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Write it rough. Pick your take.")
                .accessibilityAddTraits(.isHeader)

                Button(action: onStart) {
                    HStack(spacing: 10) {
                        Text("Get started").font(.system(size: 16, weight: .bold))
                        Text("↵")
                            .font(.mono(13, bold: true))
                            .foregroundStyle(Self.ink)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Self.acid))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Self.paper)
                    .padding(.leading, 18)
                    .padding(.trailing, 12)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Self.ink))
                    .shadow(color: Color(red: 0.24, green: 0.16, blue: 0.08).opacity(0.22), radius: 9, y: 8)
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("Starts setting up Takes")
            }
            // Right to left, the words still read and align from the right, but the block keeps its place on the
            // photograph, which isn't mirrored.
            .environment(\.layoutDirection, layoutDirection)
            .padding(.leading, 77)
            .padding(.top, 96)
        }
        .environment(\.layoutDirection, .leftToRight)
        .frame(width: OpeningWindowController.size.width, height: OpeningWindowController.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(state.leaving && !reduceMotion ? 0.94 : 1)
        .opacity(state.leaving ? 0 : 1)
        .onExitCommand(perform: onClose)
    }

    @ViewBuilder private var photo: some View {
        if let image = BrandResources.openingImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: OpeningWindowController.size.width, height: OpeningWindowController.size.height)
                .clipped()
                .accessibilityLabel("A messy draft on a sticky note, a small keyboard, and three polished takes on paper cards")
        } else {
            Color(hex: "#F1DEC9")
        }
    }
}
