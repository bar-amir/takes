import AppKit
import SwiftUI

/// The small dark confirmation shown after pasting or copying. It never takes focus. It slides up 8 pt as it
/// appears, waits while the pointer is on it, and goes away on its own; Esc dismisses it sooner while a Takes
/// window has the keyboard.
@MainActor
final class ToastController {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    /// When the toast hides, while it's counting down; how long was left when the pointer paused it.
    private var hideAt: Date?
    private var pausedRemaining: TimeInterval?
    private var escMonitors: [Any] = []

    /// `coachNote` is the English coach's nudge, shown as a second line with a way to its lesson.
    func show(message: String, showUndo: Bool, near caret: CGRect?, coachNote: String? = nil, notDone: Bool = false,
              onSaveExample: (() -> Void)?) {
        let view = ToastView(message: message, showUndo: showUndo, coachNote: coachNote, notDone: notDone,
                             onSaveExample: onSaveExample) { [weak self] in
            self?.dismiss()
        }
        present(view, near: caret, hideAfter: coachNote == nil ? 5 : 8)
    }

    /// Shows any toast content near the caret. `hideAfter: nil` keeps it up until it's dismissed or replaced.
    func present<V: View>(_ view: V, near caret: CGRect?, hideAfter: TimeInterval?) {
        dismiss(animated: false)
        let hosting = NSHostingView(rootView: ToastHover(content: view) { [weak self] inside in self?.hover(inside) })
        // Toasts are always dark, so system controls in them (instant mode's spinner) draw for dark.
        hosting.appearance = NSAppearance(named: .darkAqua)
        let size = hosting.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.acceptsMouseMovedEvents = true
        panel.contentView = hosting

        let screen = ScreenChoice.screen(for: caret)
        let visible = screen.visibleFrame
        var origin = caret.map { CGPoint(x: $0.minX - 20, y: $0.maxY + 16) }
            ?? CGPoint(x: visible.midX - size.width / 2, y: visible.minY + 80)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        // Slides up 8 pt with a fade; Reduce Motion: the fade alone.
        let rise: CGFloat = Motion.reduceMotion ? 0 : 8
        panel.setFrameOrigin(CGPoint(x: origin.x, y: origin.y - rise))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.standard
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(origin)
        }

        guard let hideAfter else { return }
        schedule(after: hideAfter)
        watchEscape()
    }

    func dismiss() { dismiss(animated: true) }

    private func dismiss(animated: Bool) {
        hideWork?.cancel()
        hideWork = nil
        hideAt = nil
        pausedRemaining = nil
        escMonitors.forEach(NSEvent.removeMonitor)
        escMonitors = []
        guard let panel else { return }
        self.panel = nil
        guard animated else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.quick
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func schedule(after delay: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hideWork = work
        hideAt = Date().addingTimeInterval(delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// The countdown stops while the pointer is on the toast, and resumes (with at least 1.5 s) when it leaves.
    private func hover(_ inside: Bool) {
        if inside, let hideAt, hideWork != nil {
            hideWork?.cancel()
            hideWork = nil
            pausedRemaining = max(hideAt.timeIntervalSinceNow, 0)
        } else if !inside, let remaining = pausedRemaining {
            pausedRemaining = nil
            schedule(after: max(remaining, 1.5))
        }
    }

    /// Esc dismisses the toast while a Takes window has the keyboard; the key still reaches that window. Keys typed
    /// in other apps are never watched (Takes reads nothing in the background), so there the toast times out.
    private func watchEscape() {
        let isEscape: (NSEvent) -> Bool = { $0.keyCode == 53 && $0.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if isEscape(event), self?.panel != nil { self?.dismiss() }
            return event
        }) { escMonitors.append(local) }
    }
}

/// Reports the pointer entering and leaving the toast.
private struct ToastHover<Content: View>: View {
    let content: Content
    let onHover: (Bool) -> Void

    var body: some View { content.onHover(perform: onHover) }
}

struct ToastView: View {
    let message: String
    let showUndo: Bool
    var coachNote: String?
    /// What the toast reports didn't happen (the take wasn't pasted): a warning mark, not the check of a paste.
    var notDone = false
    let onSaveExample: (() -> Void)?
    let onDone: () -> Void
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            mainLine
            if let coachNote {
                Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)
                HStack(spacing: 10) {
                    Text("Coach").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: "#F3EBDD"))
                    Text(coachNote).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.85))
                    Button("See why") {
                        onDone()
                        SettingsWindowController.shared.show(tab: .coach, newPreset: false)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.3)))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#24242B")))
        .fixedSize()
    }

    private var mainLine: some View {
        HStack(spacing: 12) {
            Image(systemName: notDone ? "exclamationmark.circle.fill" : "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(notDone ? InstantToast.failure : Color(hex: "#7FD4A8"))
            Text(message).font(.system(size: 13))
            if showUndo {
                HStack(spacing: 4) {
                    Text("⌘Z")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.12)))
                    Text("undo").font(.caption)
                }
                .foregroundStyle(Color.white.opacity(0.75))
            }
            if let onSaveExample {
                Button(saved ? "Saved as example" : "Save as example") {
                    onSaveExample()
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: onDone)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.3)))
                .disabled(saved)
            }
        }
    }
}
