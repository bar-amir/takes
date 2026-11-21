import AppKit
import AVFoundation
import SwiftUI

/// Onboarding's opening screen: one photograph (looping ⌥⇧Space on its keyboard), the headline and Get started, in a
/// borderless window.
/// Get started (or ↵) shrinks it away and opens the step window. Esc closes it; onboarding resumes from the
/// menu bar or by opening Takes again.
@MainActor
final class OpeningWindowController: NSObject {
    static let shared = OpeningWindowController()
    static let size = CGSize(width: 960, height: 540)

    private var window: NSWindow?
    private let state = OpeningState()

    func show(on screen: NSScreen, onStart: @escaping () -> Void) {
        state.leaving = false
        state.pressed = false
        let window = self.window ?? makeWindow()
        self.window = window
        window.alphaValue = 1
        window.hasShadow = true
        window.contentView = NSHostingView(rootView: OpeningView(state: state, onStart: { [weak self] in self?.start(onStart) },
                                                                 onClose: { [weak self] in self?.window?.orderOut(nil) }))
        window.setFrameOrigin(ScreenChoice.centred(window.frame.size, in: screen.visibleFrame))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func start(_ onStart: @escaping () -> Void) {
        guard !state.leaving, !state.pressed else { return }
        // The button goes down and comes back up before the window shrinks away, so the press reads, even from ↵.
        state.pressed = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Motion.quick * 1_000_000_000))
            self?.leave(onStart)
        }
    }

    private func leave(_ onStart: @escaping () -> Void) {
        state.pressed = false
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
    /// Get started is down: shown for ↵ too, which presses the button without a mouse.
    @Published var pressed = false
    @Published var leaving = false
}

/// Get started: an Ink key with an Acid ↵ cap. It lifts a little under the pointer, and when pressed it sinks, its
/// shadow tightens and the ↵ cap goes down with it, like the keys on the photo. Reduce Motion keeps the shadow and
/// colour change and drops the movement.
struct OpeningButtonStyle: ButtonStyle {
    var pressedByKey = false

    func makeBody(configuration: Configuration) -> some View {
        OpeningButton(label: configuration.label, down: configuration.isPressed || pressedByKey)
    }
}

private struct OpeningButton: View {
    let label: ButtonStyleConfiguration.Label
    let down: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let lift: CGFloat = reduceMotion ? 0 : (down ? 2 : hovering ? -1 : 0)
        return HStack(spacing: 10) {
            label
            Text("↵")
                .font(.mono(13, bold: true))
                .foregroundStyle(OpeningView.ink)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(OpeningView.acid)
                        .shadow(color: .black.opacity(down ? 0 : 0.35), radius: 0, y: down ? 0 : 2)
                )
                .offset(y: down && !reduceMotion ? 1.5 : 0)
                .accessibilityHidden(true)
        }
        .foregroundStyle(OpeningView.paper.opacity(down ? 0.85 : 1))
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 10).fill(OpeningView.ink))
        .shadow(color: Color(red: 0.24, green: 0.16, blue: 0.08).opacity(down ? 0.3 : hovering ? 0.26 : 0.22),
                radius: down ? 3 : hovering ? 12 : 9, y: down ? 2 : hovering ? 10 : 8)
        .scaleEffect(down && !reduceMotion ? 0.97 : 1)
        .offset(y: lift)
        .fixedSize()
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(reduceMotion ? .easeOut(duration: Motion.quick) : .spring(response: 0.22, dampingFraction: 0.6), value: down)
        .animation(.easeOut(duration: Motion.standard), value: hovering)
    }
}

struct OpeningView: View {
    @ObservedObject var state: OpeningState
    var onStart: () -> Void
    var onClose: () -> Void = {}
    /// Only the photo, without the loop: for snapshots.
    var still = false
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
                    Text("Get started").font(.system(size: 16, weight: .bold))
                }
                .buttonStyle(OpeningButtonStyle(pressedByKey: state.pressed))
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
                // The photo stays underneath, so nothing blinks before the loop's first frame, and it is all that
                // shows with Reduce Motion on.
                if !still && !reduceMotion, let loop = BrandResources.openingLoop {
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

/// The muted, looping video over the opening photo. Clicks and drags pass through to the window, which moves by its
/// background; playback stops when the window goes away.
private struct OpeningLoop: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> OpeningLoopView { OpeningLoopView(url: url) }
    func updateNSView(_ view: OpeningLoopView, context: Context) {}
}

final class OpeningLoopView: NSView {
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    init(url: URL) {
        super.init(frame: .zero)
        wantsLayer = true
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        playerLayer.backgroundColor = .clear
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        layer?.sublayers?.forEach { $0.frame = bounds }
    }

    override var mouseDownCanMoveWindow: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { player.pause() } else { player.play() }
    }
}
