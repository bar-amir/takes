import AVFoundation
import AppKit
import SwiftUI

/// Onboarding's opening screen: one photograph, the headline and Get started, in a borderless window.
/// The photo's keys type ⌥ ⇧ ↵ in a gentle loop (a muted video over the still; the still alone with Reduce Motion).
/// Get started (or ↵) presses in like a key, springs back, then shrinks the window away and opens the step window. Esc closes it; onboarding resumes from the
/// menu bar or by opening Takes again.
@MainActor
final class OpeningWindowController: NSObject {
    static let shared = OpeningWindowController()
    static let size = CGSize(width: 960, height: 540)

    private var window: NSWindow?
    private let state = OpeningState()

    func show(on screen: NSScreen, onStart: @escaping () -> Void, onClose: (() -> Void)? = nil) {
        state.leaving = false
        let window = self.window ?? makeWindow()
        self.window = window
        window.alphaValue = 1
        window.hasShadow = true
        window.contentView = NSHostingView(rootView: OpeningView(state: state, onStart: { [weak self] in self?.start(onStart) },
                                                                 onClose: { [weak self] in self?.hide(); onClose?() }))
        window.setFrameOrigin(ScreenChoice.centred(window.frame.size, in: screen.visibleFrame))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func start(_ onStart: @escaping () -> Void) {
        guard !state.leaving, !state.pressing else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !Motion.reduceMotion {
                // The button presses in like a key, then springs back as its ↵ pops.
                withAnimation(OpeningView.pressIn) { self.state.pressing = true }
                try? await Task.sleep(nanoseconds: 110_000_000)
                withAnimation(OpeningView.release) { self.state.pressing = false }
                self.state.pops += 1
                try? await Task.sleep(nanoseconds: 260_000_000)
            }
            self.window?.hasShadow = false
            withAnimation(Motion.animation(.easeIn(duration: Motion.standard))) { self.state.leaving = true }
            try? await Task.sleep(nanoseconds: UInt64(Motion.standard * 1_000_000_000))
            onStart()
            self.hide()
        }
    }

    /// Orders the window out and drops its view, which stops the looping video.
    private func hide() {
        window?.orderOut(nil)
        window?.contentView = nil
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
    /// Get started is held down: by the mouse, or briefly after ↵.
    @Published var pressing = false
    /// Counts presses, so the ↵ on the button pops each time.
    @Published var pops = 0
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
    static let pressIn = Animation.spring(response: 0.16, dampingFraction: 0.7)
    static let release = Animation.spring(response: 0.34, dampingFraction: 0.45)

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
                            .keyframeAnimator(initialValue: Pop(), trigger: state.pops) { chip, pop in
                                chip.scaleEffect(pop.scale).rotationEffect(.degrees(pop.tilt))  // `pops` only changes with motion on
                            } keyframes: { _ in
                                KeyframeTrack(\.scale) {
                                    SpringKeyframe(1.35, duration: 0.12, spring: .snappy)
                                    SpringKeyframe(1, duration: 0.4, spring: .bouncy)
                                }
                                KeyframeTrack(\.tilt) {
                                    SpringKeyframe(-12, duration: 0.12, spring: .snappy)
                                    SpringKeyframe(0, duration: 0.4, spring: .bouncy)
                                }
                            }
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Self.paper)
                    .padding(.leading, 18)
                    .padding(.trailing, 12)
                    .frame(height: 44)
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(KeyButtonStyle(held: state.pressing, still: reduceMotion))
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
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                // The loop starts and ends on the still, so it can come and go without a jump.
                if !reduceMotion, let loop = BrandResources.openingLoop {
                    OpeningLoop(url: loop).accessibilityHidden(true)
                }
            }
            .frame(width: OpeningWindowController.size.width, height: OpeningWindowController.size.height)
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("A messy draft on a sticky note, a small keyboard, and three polished takes on paper cards")
        } else {
            Color(hex: "#F1DEC9")
        }
    }
}

/// The ↵ chip's pop when Get started is pressed.
private struct Pop {
    var scale = 1.0
    var tilt = 0.0
}

/// Get started as a key: it sinks a little and its shadow tucks in while held, and springs back when let go.
private struct KeyButtonStyle: ButtonStyle {
    var held: Bool
    var still: Bool

    func makeBody(configuration: Configuration) -> some View {
        let down = !still && (configuration.isPressed || held)
        configuration.label
            .background(RoundedRectangle(cornerRadius: 10).fill(OpeningView.ink))
            .shadow(color: Color(red: 0.24, green: 0.16, blue: 0.08).opacity(down ? 0.3 : 0.22), radius: down ? 3 : 9, y: down ? 2 : 8)
            .scaleEffect(down ? 0.95 : 1)
            .offset(y: down ? 4 : 0)
            .animation(down ? OpeningView.pressIn : OpeningView.release, value: down)
    }
}

/// The opening photo's key-press loop: a muted video that repeats for as long as the view is on screen.
private struct OpeningLoop: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> LoopView { LoopView(url: url) }
    func updateNSView(_ view: LoopView, context: Context) {}
    static func dismantleNSView(_ view: LoopView, coordinator: ()) { view.stop() }

    final class LoopView: NSView {
        private let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?

        init(url: URL) {
            super.init(frame: .zero)
            wantsLayer = true
            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            self.layer = layer
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            player.play()
        }

        required init?(coder: NSCoder) { nil }

        func stop() {
            player.pause()
            looper?.disableLooping()
            looper = nil
        }
    }
}

/// `Takes --opening-preview`: shows the opening screen alone, and again a moment after Get started, to watch its
/// motion while working on it. Esc quits. It reads and writes nothing.
@MainActor
enum OpeningPreview {
    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        func show() {
            guard let screen = NSScreen.main else { return }
            OpeningWindowController.shared.show(
                on: screen,
                onStart: { DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { show() } },
                onClose: { NSApp.terminate(nil) })
        }
        show()
        app.run()
    }
}
