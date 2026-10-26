import AppKit
import SwiftUI

/// The small dark confirmation shown after pasting or copying. It never takes focus.
@MainActor
final class ToastController {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(message: String, showUndo: Bool, near caret: CGRect?, onSaveExample: (() -> Void)?) {
        dismiss()
        let view = ToastView(message: message, showUndo: showUndo, onSaveExample: onSaveExample) { [weak self] in
            self?.dismiss()
        }
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting

        let screen = NSScreen.screens.first { caret.map($0.frame.intersects) ?? false } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        var origin = caret.map { CGPoint(x: $0.minX - 20, y: $0.maxY + 16) }
            ?? CGPoint(x: visible.midX - size.width / 2, y: visible.minY + 80)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        self.panel = panel

        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    func dismiss() {
        hideWork?.cancel()
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct ToastView: View {
    let message: String
    let showUndo: Bool
    let onSaveExample: (() -> Void)?
    let onDone: () -> Void
    @State private var saved = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(hex: "#7FD4A8"))
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
        .foregroundStyle(.white)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#24242B")))
        .fixedSize()
    }
}
