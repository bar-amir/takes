import AppKit
import QuartzCore
import SwiftUI

/// The popover under the menu-bar icon that says where Takes lives: once onboarding is done, and whenever Takes is
/// opened again from Finder, Spotlight or Launchpad. It closes on any click outside it.
@MainActor
final class StatusPopoverController: NSObject, NSPopoverDelegate {
    static let shared = StatusPopoverController()

    enum Kind: Equatable {
        /// Right after onboarding: "Takes lives up here", Got it / Try it now.
        case welcome
        /// Opened again: "Takes is already up here", Settings… / Open the panel, and what's missing, if anything.
        case reopen(missing: String?)
    }

    /// Wired by the app delegate.
    var tryIt: () -> Void = {}
    var openPanel: () -> Void = {}
    var openSettings: () -> Void = {}
    var finishSetup: () -> Void = {}

    private var popover: NSPopover?
    private let pulse = StatusPulse()

    func show(_ kind: Kind, from button: NSStatusBarButton) {
        popover?.performClose(nil)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let close = { [weak popover] in popover?.performClose(nil) }
        let view = StatusPopoverView(kind: kind, hotKey: Store.shared.settings.summonHotKey,
                                     primary: { [weak self] in
                                         close()
                                         if kind == .welcome { self?.tryIt() } else { self?.openPanel() }
                                     },
                                     secondary: { [weak self] in
                                         close()
                                         if kind != .welcome { self?.openSettings() }
                                     },
                                     finishSetup: { [weak self] in
                                         close()
                                         self?.finishSetup()
                                     })
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        self.popover = popover
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        pulse.run(around: button)
    }

    func close() { popover?.performClose(nil) }

    func popoverDidClose(_ notification: Notification) {
        if (notification.object as? NSPopover) === popover { popover = nil }
    }
}

struct StatusPopoverView: View {
    let kind: StatusPopoverController.Kind
    let hotKey: KeyCombo
    var primary: () -> Void = {}
    var secondary: () -> Void = {}
    var finishSetup: () -> Void = {}

    static let width: CGFloat = 340

    private var isWelcome: Bool { kind == .welcome }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                BrandMarkShape().fill(Theme.text).frame(width: 28, height: 28).accessibilityHidden(true)
                Text(isWelcome ? "Takes lives up here" : "Takes is already up here")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(isWelcome ? "Press" : "No window needed. Press")
                    ForEach(Array(BigKeys.parts(hotKey.display).enumerated()), id: \.offset) { Kbd($0.element) }
                    Text("in any text box.")
                }
                .lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(isWelcome ? "Press" : "No window needed. Press") \(hotKey.display) in any text box.")
                Text(isWelcome ? "Click this icon for presets, the coach and settings." : "Or click this icon for presets and settings.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 13.5))
            .foregroundStyle(Theme.controlText)
            note
            HStack(spacing: Spacing.item) {
                Spacer(minLength: 0)
                Button(isWelcome ? "Got it" : "Settings…", action: secondary)
                    .buttonStyle(SecondaryButtonStyle(height: 28))
                    .lineLimit(1)
                    .fixedSize()
                    .keyboardShortcut(isWelcome ? .cancelAction : KeyboardShortcut(",", modifiers: .command))
                Button(isWelcome ? "Try it now" : "Open the panel", action: primary)
                    .buttonStyle(PrimaryButtonStyle(height: 28))
                    .lineLimit(1)
                    .fixedSize()
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: Self.width, alignment: .leading)
    }

    @ViewBuilder private var note: some View {
        switch kind {
        case .welcome:
            Text("Can't see it? A busy menu bar can hide icons behind the notch. Hold ⌘ and drag Takes to the right.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        case .reopen(let missing?):
            Button(action: finishSetup) {
                (Text(missing + " ") + Text("Finish setup ›").fontWeight(.semibold))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.avoidText)
                    .lineLimit(1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(missing) Finish setup")
        case .reopen(nil):
            EmptyView()
        }
    }
}

/// Two rings that spread out from the menu-bar icon, 900 ms each, so the eye finds it. Under Reduce Motion, one
/// ring that stays for two seconds. Drawn in a small click-through window over the menu bar.
@MainActor
final class StatusPulse {
    private var window: NSWindow?

    static let cobalt = NSColor(red: 0x30 / 255, green: 0x45 / 255, blue: 0xFF / 255, alpha: 1)

    func run(around button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let iconFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let side: CGFloat = 64
        let frame = NSRect(x: iconFrame.midX - side / 2, y: iconFrame.midY - side / 2, width: side, height: side)
        window?.orderOut(nil)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        window.contentView = view
        self.window = window

        let ring = CAShapeLayer()
        let diameter: CGFloat = 28
        ring.frame = view.bounds
        ring.path = CGPath(ellipseIn: CGRect(x: (side - diameter) / 2, y: (side - diameter) / 2, width: diameter, height: diameter), transform: nil)
        ring.fillColor = nil
        ring.strokeColor = Self.cobalt.cgColor
        ring.lineWidth = 2
        view.layer?.addSublayer(ring)
        window.orderFrontRegardless()

        let duration: Double
        if Motion.reduceMotion {
            ring.opacity = 0.55
            duration = 2
        } else {
            ring.opacity = 0
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.8
            scale.toValue = 2.0
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.7
            fade.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [scale, fade]
            group.duration = 0.9
            group.repeatCount = 2
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ring.add(group, forKey: "pulse")
            duration = 1.8
        }
        Task { @MainActor [weak self, weak window] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            window?.orderOut(nil)
            if self?.window === window { self?.window = nil }
        }
    }
}
