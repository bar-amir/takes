import AppKit
import SwiftUI

/// A panel that takes keyboard focus without activating Takes, so the app the user was
/// typing in stays frontmost and receives the paste.
final class KeyPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

@MainActor
final class PanelController {
    private var panel: KeyPanel?
    private let model = RunModel()

    func summon() {
        let summonedAt = Date()
        let focus = FocusReader.snapshot()
        model.reset(with: focus, summonedAt: summonedAt)
        model.onPaste = { [weak self] text in self?.paste(text) }
        model.onClose = { [weak self] in self?.close() }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel, near: focus.caretRect)
        panel.makeKeyAndOrderFront(nil)
        model.panelShownMs = Int(Date().timeIntervalSince(summonedAt) * 1000)
    }

    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
                             styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
                             backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onCancel = { [weak self] in self?.close() }
        panel.contentView = NSHostingView(rootView: RunView(model: model))
        return panel
    }

    private func position(_ panel: KeyPanel, near caret: CGRect?) {
        let size = panel.frame.size
        let screen = NSScreen.screens.first { caret.map($0.frame.intersects) ?? false } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        var origin: CGPoint
        if let caret {
            // Prefer just above the caret (chat composers sit at the bottom), else below it.
            origin = CGPoint(x: caret.minX - 40, y: caret.maxY + 12)
            if origin.y + size.height > visible.maxY { origin.y = caret.minY - size.height - 12 }
        } else {
            origin = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + 80)
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
    }

    private func paste(_ text: String) {
        let replaceAll = model.focus?.source == .field
        close()
        Paster.paste(text, replaceAll: replaceAll)
    }

    private func close() {
        panel?.orderOut(nil)
    }
}
