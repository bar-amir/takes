import AppKit
import Carbon
import SwiftUI

/// A panel that takes keyboard focus without activating Takes, so the app the user was
/// typing in stays frontmost and receives the paste.
final class KeyPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    /// Takes has no visible menu bar, so standard edit shortcuts are routed here by key position
    /// (works with a Hebrew layout too).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else { return false }
        let actions: [Int: Selector] = [kVK_ANSI_X: #selector(NSText.cut(_:)), kVK_ANSI_C: #selector(NSText.copy(_:)),
                                        kVK_ANSI_V: #selector(NSText.paste(_:)), kVK_ANSI_A: #selector(NSText.selectAll(_:)),
                                        kVK_ANSI_Z: Selector(("undo:"))]
        guard let action = actions[Int(event.keyCode)] else { return false }
        return NSApp.sendAction(action, to: nil, from: self)
    }
}

@MainActor
final class PanelController {
    private var panel: KeyPanel?
    private let model = PanelModel()
    private let toast = ToastController()
    private var caretRect: CGRect?
    private var lastScreen: PanelModel.Screen?

    init() {
        model.onClose = { [weak self] in self?.close() }
        model.onScreenChange = { [weak self] in self?.layout() }
        model.onPaste = { [weak self] index, text, presetID in self?.paste(index: index, text: text, presetID: presetID) }
        model.onCopy = { [weak self] index, text in self?.copy(index: index, text: text) }
        model.onOpenSettings = { [weak self] tab, newPreset in
            self?.close()
            SettingsWindowController.shared.show(tab: tab, newPreset: newPreset)
        }
        model.onMore = { [weak self] in self?.showMoreMenu() }
        model.textSelectionActive = { [weak self] in
            guard let textView = self?.panel?.firstResponder as? NSTextView else { return false }
            return textView.selectedRange().length > 0
        }
    }

    var isVisible: Bool { panel?.isVisible == true }

    func summon(presetID: String? = nil) {
        toast.dismiss()
        let focus = FocusReader.snapshot(prefill: Store.shared.settings.prefill)
        caretRect = focus.caretRect
        model.reset(focus: focus, presetID: presetID)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        lastScreen = nil
        layout()
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 660, height: 380),
                             styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                             backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = NSColor(Theme.surface)
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onCancel = { [weak self] in self?.model.escape() }
        panel.contentView = NSHostingView(rootView: PanelRootView(model: model))
        return panel
    }

    /// Each screen has its own size; the panel is re-placed whenever it changes.
    private func layout() {
        guard let panel else { return }
        let size: CGSize
        switch model.screen {
        case .compose: size = CGSize(width: 720, height: 360)
        case .presets: size = CGSize(width: 800, height: 560)
        case .takes:
            let count = max(model.cardCount, model.takeCount)
            let width: CGFloat = count <= 1 ? 720 : count == 2 ? 880 : 1060
            size = CGSize(width: width, height: count > 3 ? 760 : 520)
        }
        if model.screen == lastScreen, panel.frame.size == size { return }
        lastScreen = model.screen
        panel.setFrame(NSRect(origin: origin(for: size), size: size), display: true, animate: false)
    }

    private func origin(for size: CGSize) -> CGPoint {
        let screen = NSScreen.screens.first { caretRect.map($0.frame.intersects) ?? false } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        var origin: CGPoint
        if let caret = caretRect, Store.shared.settings.panelPosition == .nearCursor {
            // Prefer just above the caret (chat composers sit at the bottom), else below it.
            origin = CGPoint(x: caret.minX - 60, y: caret.maxY + 14)
            if origin.y + size.height > visible.maxY { origin.y = caret.minY - size.height - 14 }
        } else {
            origin = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + 60)
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        return origin
    }

    private func paste(index: Int, text: String, presetID: String?) {
        let focus = model.focus
        let replaceAll = focus?.source == .field && !(focus?.text.isEmpty ?? true)
        let restore = Store.shared.settings.restoreClipboard
        close()
        Paster.paste(text, into: focus, replaceAll: replaceAll, restoreClipboard: restore)
        toast.show(message: "Pasted take \(index + 1)" + (restore ? " · your clipboard is back" : ""),
                   showUndo: true, near: caretRect) { [presetID] in
            guard let presetID else { return }
            Store.shared.addExample(text, toPreset: presetID)
        }
    }

    private func copy(index: Int, text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        close()
        toast.show(message: "Copied take \(index + 1)", showUndo: false, near: caretRect, onSaveExample: nil)
    }

    private func showMoreMenu() {
        guard let panel, let view = panel.contentView else { return }
        let menu = NSMenu()
        let items: [(String, SettingsTab)] = [("Edit presets…", .presets), ("Voice rules…", .voice), ("Engine and defaults…", .engine), ("History…", .history)]
        for (title, tab) in items {
            let item = NSMenuItem(title: title, action: #selector(MenuTarget.open(_:)), keyEquivalent: "")
            item.representedObject = tab.rawValue
            item.target = MenuTarget.shared
            menu.addItem(item)
        }
        MenuTarget.shared.handler = { [weak self] tab in
            self?.close()
            SettingsWindowController.shared.show(tab: tab, newPreset: false)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 16, y: 56), in: view)
    }

    func close() {
        panel?.orderOut(nil)
    }
}

/// Target for NSMenu items, which need an Objective-C selector.
final class MenuTarget: NSObject {
    static let shared = MenuTarget()
    var handler: (SettingsTab) -> Void = { _ in }

    @objc func open(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let tab = SettingsTab(rawValue: raw) { handler(tab) }
    }
}
