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
    /// The text box being written in, which the panel opens beside.
    private var fieldRect: CGRect?
    private var lastScreen: PanelModel.Screen?
    /// What the takes screen last said it needs (0 until it has laid out).
    private var takesHeight: CGFloat = 0
    /// Onboarding's practice box: the chosen take goes back to it instead of being pasted into another app.
    private var practice: (paste: (String) -> Void, cancel: () -> Void)?

    init() {
        model.onClose = { [weak self] in self?.close() }
        model.onScreenChange = { [weak self] in self?.layout() }
        model.onContentHeight = { [weak self] height in self?.fitTakes(height: height) }
        model.onPaste = { [weak self] index, text, presetID in self?.paste(index: index, text: text, presetID: presetID) }
        model.onCopy = { [weak self] index, text in self?.copy(index: index, text: text) }
        model.onOpenSettings = { [weak self] tab, newPreset in
            self?.close()
            SettingsWindowController.shared.show(tab: tab, newPreset: newPreset)
        }
        model.onMore = { [weak self] in self?.showMoreMenu() }
        model.onOpenGallery = { [weak self] in
            self?.close()
            SettingsWindowController.shared.show(tab: .presets, gallery: true)
        }
        model.onSetUpCoach = { [weak self] patterns in
            self?.close()
            CoachSetupRequest.shared.pending = patterns
            SettingsWindowController.shared.show(tab: .coach, newPreset: false)
        }
        model.dictation.onRegainFocus = { [weak self] in self?.panel?.makeKey() }
        model.textSelectionActive = { [weak self] in
            guard let textView = self?.panel?.firstResponder as? NSTextView else { return false }
            return textView.selectedRange().length > 0
        }
        ClipboardWatch.shared.activate()
    }

    var isVisible: Bool { panel?.isVisible == true }

    func summon(presetID: String? = nil) {
        // Before the field is read: its ⌘A ⌘C fallback changes the clipboard.
        let clipboard = ClipboardWatch.shared.captureForSummon()
        summon(focus: FocusReader.snapshot(prefill: Store.shared.settings.prefill), presetID: presetID, clipboard: clipboard)
    }

    /// Opens the panel on a field already read (instant mode hands over here), letting the caller set it up.
    func summon(focus: FocusSnapshot, presetID: String?, clipboard: ClipboardCandidate? = nil,
                configure: (PanelModel) -> Void = { _ in }) {
        toast.dismiss()
        endPractice()
        model.summonClipboard = clipboard
        caretRect = focus.caretRect
        fieldRect = FocusReader.fieldFrame(of: focus.element)
        open(focus: focus, presetID: presetID, configure: configure)
    }

    /// Opens the panel on onboarding's practice box: the same panel and model, with the box's text and frame
    /// standing in for the focused field. `paste` gets the chosen take; `cancel` runs if the panel closes without one.
    func summonPractice(text: String, boxFrame: CGRect?, paste: @escaping (String) -> Void, cancel: @escaping () -> Void) {
        toast.dismiss()
        endPractice()
        practice = (paste, cancel)
        caretRect = boxFrame
        fieldRect = boxFrame
        // The first try should show several takes to choose from, so it starts on a rewriting preset, not a proofreader.
        let presetID = Store.shared.presets.first { !$0.isMinimalEdits }?.id
        open(focus: FocusSnapshot(app: nil, text: text, source: .field, caretRect: boxFrame), presetID: presetID)
        model.previewAppName = String(localized: "the practice box")
    }

    private func endPractice() {
        let cancel = practice?.cancel
        practice = nil
        cancel?()
    }

    private func open(focus: FocusSnapshot, presetID: String?, configure: (PanelModel) -> Void = { _ in }) {
        model.previewAppName = nil
        model.reset(focus: focus, presetID: presetID)
        configure(model)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let wasVisible = panel.isVisible
        lastScreen = nil
        // A height from an earlier draft (more takes, longer text) would leave the panel padded with blank space.
        takesHeight = 0
        layout()
        if wasVisible {
            panel.makeKeyAndOrderFront(nil)
        } else {
            summonAnimated(panel)
        }
    }

    // MARK: Motion

    /// The panel grows from the caret: scale 0.96 → 1 and a fade, 180 ms. Reduce Motion: the fade only.
    private func summonAnimated(_ panel: KeyPanel) {
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        if !Motion.reduceMotion, let view = panel.contentView {
            view.wantsLayer = true
            view.layoutSubtreeIfNeeded()
            let anchor = caretRect.map { caret in
                CGPoint(x: min(max(caret.midX - panel.frame.minX, 0), panel.frame.width),
                        y: min(max(caret.midY - panel.frame.minY, 0), panel.frame.height))
            } ?? CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            view.layer?.add(Self.scale(from: 0.96, to: 1, about: anchor, duration: Motion.standard), forKey: "summon")
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.standard
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    /// A scale animation about a point in the layer, ending where the layer already is.
    static func scale(from: CGFloat, to: CGFloat, about point: CGPoint, duration: Double) -> CABasicAnimation {
        func transform(_ scale: CGFloat) -> CATransform3D {
            var t = CATransform3DMakeTranslation(point.x, point.y, 0)
            t = CATransform3DScale(t, scale, scale, 1)
            return CATransform3DTranslate(t, -point.x, -point.y, 0)
        }
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = transform(from)
        animation.toValue = transform(to)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return animation
    }

    /// Dismissing is faster than summoning (120 ms). The panel itself leaves at once, so focus and the paste go back
    /// to the app straight away; a still picture of it fades and shrinks a little in its place.
    private func dismissAnimated(_ panel: NSPanel) {
        guard panel.isVisible else { return }
        guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            panel.orderOut(nil)
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        let ghost = NSPanel(contentRect: panel.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        ghost.isOpaque = false
        ghost.backgroundColor = .clear
        ghost.hasShadow = true
        ghost.level = panel.level
        ghost.ignoresMouseEvents = true
        ghost.collectionBehavior = panel.collectionBehavior
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: panel.frame.size))
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 12
        imageView.layer?.masksToBounds = true
        ghost.contentView = imageView
        ghost.orderFrontRegardless()
        panel.orderOut(nil)
        if !Motion.reduceMotion {
            let size = imageView.bounds.size
            let shrink = Self.scale(from: 1, to: 0.98, about: CGPoint(x: size.width / 2, y: size.height / 2), duration: Motion.quick)
            shrink.fillMode = .forwards
            shrink.isRemovedOnCompletion = false
            imageView.layer?.add(shrink, forKey: "dismiss")
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.quick
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ghost.animator().alphaValue = 0
        }, completionHandler: {
            ghost.orderOut(nil)
        })
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
        let hosting = NSHostingView(rootView: PanelRootView(model: model))
        // The controller sizes the panel (`layout`, `fitTakes`); the content must not resize it on its own.
        hosting.sizingOptions = []
        panel.contentView = hosting
        return panel
    }

    /// Each screen has its own size; the panel is re-placed whenever it changes.
    private func layout() {
        guard let panel else { return }
        let size: CGSize
        switch model.screen {
        case .compose: size = CGSize(width: 720, height: ComposeView.height + ReplyContextBar.extraHeight(model))
        case .presets: size = CGSize(width: 800, height: 560)
        case .takes:
            let count = max(model.cardCount, model.takeCount)
            let width: CGFloat = count <= 1 ? 720 : count == 2 ? 880 : 1060
            size = CGSize(width: width, height: takesHeight > 0 ? takesHeight : 520)
        }
        if model.screen == lastScreen, panel.frame.size == size { return }
        lastScreen = model.screen
        panel.setFrame(NSRect(origin: origin(for: size), size: size), display: true, animate: false)
    }

    /// Resizes the takes screen to what it needs. While takes stream in it only grows, so a regenerate doesn't
    /// shrink and regrow the panel.
    private func fitTakes(height: CGFloat) {
        guard let panel, model.screen == .takes, height > 0 else { return }
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        let target = min(height.rounded(.up), visible.height - 16)
        guard Self.shouldFit(target: target, current: panel.frame.height, running: model.running,
                             fittedThisOpen: takesHeight > 0) else { return }
        takesHeight = target
        // Grow away from the text box: a panel above it keeps its bottom edge, any other keeps its top edge.
        var frame = panel.frame
        let clear = keepClear(on: visible)
        if clear.map({ frame.minY < $0.maxY }) ?? true { frame.origin.y += frame.height - target }
        frame.size.height = target
        if !visible.contains(frame) || clear.map(frame.intersects) == true {
            frame.origin = origin(for: frame.size)
        }
        panel.setFrame(frame, display: true, animate: false)
    }

    /// Whether the takes screen should change to `target`. While a run is writing it only grows, but the first fit
    /// after the panel opens may shrink it: the size it opened at was a guess, not this run's.
    nonisolated static func shouldFit(target: CGFloat, current: CGFloat, running: Bool, fittedThisOpen: Bool) -> Bool {
        if abs(target - current) < 1 { return false }
        return !(running && fittedThisOpen && target < current)
    }

    private func keepClear(on visible: CGRect) -> CGRect? {
        PanelPlacement.keepClear(caret: caretRect, field: fieldRect, visible: visible)
    }

    private func origin(for size: CGSize) -> CGPoint {
        let visible = ScreenChoice.screen(for: caretRect).visibleFrame
        return PanelPlacement.origin(for: Store.shared.settings.panelPosition, size: size,
                                     keepClear: keepClear(on: visible), in: visible)
    }

    private func paste(index: Int, text: String, presetID: String?) {
        if let practice {
            self.practice = nil
            close()
            practice.paste(text)
            return
        }
        let focus = model.focus
        let replaceAll = focus?.source == .field && !(focus?.text.isEmpty ?? true)
        let restore = Store.shared.settings.restoreClipboard
        let nudge = model.coachNudge
        model.coachNudge = nil
        close()
        Paster.paste(text, into: focus, replaceAll: replaceAll, restoreClipboard: restore) { [weak self] pasted in
            guard let self else { return }
            let number = index + 1
            guard pasted else {
                // The field's app couldn't be brought back; nothing was typed anywhere.
                let app = focus?.app?.localizedName ?? String(localized: "the app")
                self.toast.show(message: String(localized: "Couldn't get back to \(app). Take \(number) is on the clipboard: press ⌘V"),
                                showUndo: false, near: self.caretRect, onSaveExample: nil)
                return
            }
            self.toast.show(message: restore ? String(localized: "Pasted take \(number) · your clipboard is back")
                                             : String(localized: "Pasted take \(number)"),
                            showUndo: true, near: self.caretRect, coachNote: nudge) { [presetID] in
                guard let presetID else { return }
                Store.shared.addExample(text, toPreset: presetID)
            }
        }
    }

    private func copy(index: Int, text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        close()
        toast.show(message: String(localized: "Copied take \(index + 1)"), showUndo: false, near: caretRect, onSaveExample: nil)
    }

    private func showMoreMenu() {
        guard let panel, let view = panel.contentView else { return }
        let menu = NSMenu()
        let items: [(String, SettingsTab)] = [
            (String(localized: "Edit presets…"), .presets), (String(localized: "Writing rules…"), .writing),
            (String(localized: "English coach…"), .coach), (String(localized: "Model and defaults…"), .model),
            (String(localized: "History…"), .history),
        ]
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
        model.dictation.dismiss()
        if let panel { dismissAnimated(panel) }
        endPractice()
    }
}

/// Which display the panel and toast open on: the one the caret is on.
enum ScreenChoice {
    /// The caret's display, so a full-screen app on a second display keeps the panel with it.
    @MainActor static func screen(for caret: CGRect?) -> NSScreen {
        let screens = NSScreen.screens
        return index(for: caret, in: screens.map(\.frame)).map { screens[$0] } ?? NSScreen.main ?? screens[0]
    }

    /// The display holding the caret's centre, else the one it overlaps most (Cocoa coordinates). A caret on the
    /// seam used to go to whichever display came first in the list.
    static func index(for caret: CGRect?, in frames: [CGRect]) -> Int? {
        guard let caret else { return nil }
        let centre = CGPoint(x: caret.midX, y: caret.midY)
        if let hit = frames.firstIndex(where: { $0.contains(centre) }) { return hit }
        let overlaps = frames.enumerated().map { ($0.offset, $0.element.intersection(caret)) }.filter { !$0.1.isNull }
        return overlaps.max { $0.1.width * $0.1.height < $1.1.width * $1.1.height }?.0
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
