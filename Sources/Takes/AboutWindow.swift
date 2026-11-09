import AVFoundation
import AppKit
import SwiftUI

/// The About window: the marbled logo looping on its own (no background), the name, the version and the copyright.
/// Replaces the standard About panel, which can only show a still icon.
@MainActor
final class AboutWindowController: NSObject, NSWindowDelegate {
    static let shared = AboutWindowController()
    private var window: NSWindow?

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.moveToActiveScreen()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: AboutView())
        window.setContentSize(window.contentView?.fittingSize ?? NSSize(width: 300, height: 300))
        window.center()
        window.moveToActiveScreen()
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil // Stops the loop; the next About starts fresh.
    }
}

struct AboutView: View {
    /// A still frame instead of the loop, for snapshots.
    var still = false

    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    private var version: String {
        let short = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String
        return build.map { $0 == short ? String(localized: "Version \(short)") : String(localized: "Version \(short) (\($0))") }
            ?? String(localized: "Version \(short)")
    }
    private var copyright: String { info["NSHumanReadableCopyright"] as? String ?? "© 2026 Bar Amir. MIT License." }

    var body: some View {
        VStack(spacing: 0) {
            AboutLogo(still: still)
                .frame(width: 236, height: 162) // The clip is 368 × 252.
                .accessibilityLabel(Text(verbatim: "Takes"))
            Text(verbatim: "Takes")
                .font(.system(size: 20, weight: .bold))
                .padding(.top, 2)
            Text(version)
                .font(.mono(11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 4)
            Text(copyright)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 10)
        }
        .padding(.horizontal, 40)
        .padding(.top, 28)
        .padding(.bottom, 28)
        .frame(minWidth: 280)
    }
}

/// The looping logo video (`Resources/About/logo-loop.mov`, HEVC with alpha). Shows the still frame when Reduce
/// Motion is on, in snapshots, or when the video is missing; falls back to the app icon when both are.
private struct AboutLogo: NSViewRepresentable {
    var still: Bool

    func makeNSView(context: Context) -> LogoLoopView {
        let view = LogoLoopView()
        view.configure(still: still || Motion.reduceMotion)
        return view
    }

    func updateNSView(_ view: LogoLoopView, context: Context) {}
}

final class LogoLoopView: NSView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private let imageView = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(still: Bool) {
        let folder = BrandResources.folder?.appendingPathComponent("About")
        let stillImage = folder.flatMap { NSImage(contentsOf: $0.appendingPathComponent("logo-still.png")) }
        imageView.image = stillImage ?? NSApp.applicationIconImage
        guard !still, let url = folder?.appendingPathComponent("logo-loop.mov"),
              FileManager.default.fileExists(atPath: url.path) else { return }
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: item)
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        playerLayer.videoGravity = .resizeAspect
        playerLayer.pixelBufferAttributes = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        playerLayer.backgroundColor = .clear
        layer?.addSublayer(playerLayer)
        self.player = player
        // The still stays underneath until the first frame is on screen, so the logo never blinks.
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async { self?.imageView.isHidden = true }
        }
        player.play()
    }

    private var readyObservation: NSKeyValueObservation?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { player?.pause() }
    }
}
