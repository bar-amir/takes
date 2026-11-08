import AppKit
import Combine
import SwiftUI

/// The Settings window's tabs, in toolbar order. The raw value is the title shown in the toolbar, the window title
/// and the status menu.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General", presets = "Presets", writing = "Writing", coach = "Coach", model = "Model", history = "History"

    /// Old names, kept so existing callers still compile: Voice became Writing, Engine became Model.
    static let voice = SettingsTab.writing
    static let engine = SettingsTab.model
    static let englishCoach = SettingsTab.coach

    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .presets: return String(localized: "Presets")
        case .writing: return String(localized: "Writing")
        case .coach: return String(localized: "Coach")
        case .model: return String(localized: "Model")
        case .history: return String(localized: "History")
        }
    }

    /// The SF Symbol on the tab's toolbar button.
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .presets: return "list.bullet"
        case .writing: return "pencil.line"
        case .coach: return "graduationcap"
        case .model: return "cpu"
        case .history: return "clock"
        }
    }
}

@MainActor
final class SettingsState: ObservableObject {
    @Published var tab = SettingsTab.general
    @Published var selectedPresetID: String?
    @Published var showGallery = false
    /// Where Settings › Coach is: its overview, setup or a lesson.
    @Published var coachScreen = CoachScreen.home
}

/// A native Settings window: toolbar tabs with SF Symbols, the title follows the tab, there's no OK button and every
/// change applies at once. The window takes each tab's size, with a short resize when the tab changes.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private let state = SettingsState()
    private var tabSubscription: AnyCancellable?
    /// The size the current tab asked for, applied on the next turn of the run loop so a tab's two layout passes
    /// become one resize.
    private var pendingSize: CGSize?

    func show(tab: SettingsTab, newPreset: Bool = false, gallery: Bool = false) {
        let store = Store.shared
        state.tab = tab
        if newPreset {
            let preset = store.newPreset()
            store.presets.append(preset)
            state.selectedPresetID = preset.id
        } else if state.selectedPresetID == nil || store.preset(id: state.selectedPresetID) == nil {
            state.selectedPresetID = store.presets.first?.id
        }
        if gallery { state.showGallery = true }

        let firstShow = window == nil
        let window = self.window ?? makeWindow()
        self.window = window
        if firstShow { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: SettingsMetrics.width, height: 480),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(Theme.formBackground)
        window.delegate = self
        window.toolbarStyle = .preference

        let toolbar = NSToolbar(identifier: "TakesSettings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        let hosting = NSHostingView(rootView: SettingsView(state: state, onSize: { [weak self] size in
            self?.contentWantsSize(size)
        }))
        hosting.sizingOptions = []
        window.contentView = hosting

        tabSubscription = state.$tab.removeDuplicates().sink { [weak self] tab in self?.tabChanged(to: tab) }
        tabChanged(to: state.tab)
        return window
    }

    private func tabChanged(to tab: SettingsTab) {
        window?.title = tab.title
        window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(tab.rawValue)
    }

    private func contentWantsSize(_ size: CGSize) {
        let coalesce = pendingSize == nil
        pendingSize = size
        guard coalesce else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let size = self.pendingSize else { return }
            self.pendingSize = nil
            self.resize(to: size)
        }
    }

    /// Resizes the window around `size`, keeping its horizontal centre and its top edge where they are, so a tab change
    /// grows or shrinks the window evenly on both sides instead of from the left.
    private func resize(to size: CGSize) {
        guard let window, size.width > 0, size.height > 0 else { return }
        let current = window.frame
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        guard abs(frame.width - current.width) > 0.5 || abs(frame.height - current.height) > 0.5 else { return }
        frame.origin = NSPoint(x: (current.midX - frame.width / 2).rounded(), y: current.maxY - frame.height)
        if let screen = window.screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, screen.minX), screen.maxX - frame.width)
            frame.origin.y = max(frame.minY, screen.minY)
        }
        guard window.isVisible, !Motion.reduceMotion else {
            window.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.slow
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
    }

    // MARK: Toolbar

    @objc private func selectTab(_ sender: NSToolbarItem) {
        if let tab = SettingsTab(rawValue: sender.itemIdentifier.rawValue) { state.tab = tab }
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = SettingsTab(rawValue: itemIdentifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.title
        item.paletteLabel = tab.title
        item.toolTip = tab.title
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(selectTab(_:))
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
}

/// The selected tab's page. The window's toolbar picks the tab; `onSize` reports the size the page wants.
struct SettingsView: View {
    @ObservedObject var state: SettingsState
    var onSize: (CGSize) -> Void = { _ in }

    var body: some View {
        page
            .background(GeometryReader { proxy in
                Color.clear.preference(key: SettingsSizeKey.self, value: proxy.size)
            })
            .onPreferenceChange(SettingsSizeKey.self) { onSize($0) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .foregroundStyle(Theme.text)
            .background(Theme.formBackground)
            .tint(Theme.accent)
    }

    @ViewBuilder private var page: some View {
        switch state.tab {
        case .general: GeneralTab()
        case .presets: PresetsTab(state: state).frame(width: SettingsMetrics.presetsWidth, height: SettingsMetrics.presetsHeight)
        case .writing: WritingTab()
        case .coach: EnglishCoachTab(state: state).frame(width: SettingsMetrics.width, height: SettingsMetrics.coachHeight)
        case .model: ModelTab()
        case .history: HistoryTab()
        }
    }
}

private struct SettingsSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width), height: max(value.height, next.height))
    }
}

// MARK: - Shared editors

/// Chips with ✕ and an inline "+ Add" field.
struct ChipsEditor: View {
    @Binding var items: [String]
    var style: Chip.Style
    @State private var adding = false
    @State private var newText = ""

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 6) {
                    Text(item).font(.system(size: 13))
                    Button { items.removeAll { $0 == item } } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(item)")
                }
                .foregroundStyle(style == .positive ? Theme.doText : style == .negative ? Theme.avoidText : Theme.text)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(style == .positive ? Theme.doFill : style == .negative ? Theme.avoidFill : Theme.kbdFill))
            }
            if adding {
                StyledTextField(placeholder: String(localized: "Type and press ↵"), text: $newText, height: 28, onSubmit: commit)
                    .frame(width: 200)
                    .onExitCommand { adding = false; newText = "" }
            } else {
                Button("+ Add") { adding = true }.buttonStyle(DashedButtonStyle())
            }
        }
    }

    private func commit() {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty && !items.contains(text) { items.append(text) }
        newText = ""
        adding = false
    }
}

/// Click, then press a shortcut. Esc cancels, ⌫ clears.
struct HotKeyRecorder: View {
    @Binding var combo: KeyCombo?
    var allowClear = true
    var height: CGFloat = 36
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            Text(recording ? String(localized: "Press a shortcut…") : (combo.map { "\u{200E}" + $0.display } ?? String(localized: "Record shortcut")))
                .font(.system(size: height < 32 ? 13 : 14, weight: .semibold))
                .foregroundStyle(recording ? Theme.accent : Theme.text)
                .lineLimit(1)
                .frame(minWidth: height < 32 ? 96 : 110)
        }
        .buttonStyle(SecondaryButtonStyle(height: height))
        .fixedSize()
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent, lineWidth: recording ? 1.5 : 0))
        .onDisappear(perform: stop)
        .help(allowClear ? String(localized: "Click, then press a shortcut. Esc cancels, ⌫ clears.") : String(localized: "Click, then press a shortcut. Esc cancels."))
    }

    private func toggle() { recording ? stop() : start() }

    private func start() {
        recording = true
        // Takes's own hotkeys are let go while recording: a registered one never reaches the window (macOS
        // handles it first), so pressing it would open the panel instead of recording it.
        HotKeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Esc
            if event.keyCode == 51 && allowClear { combo = nil; stop(); return nil } // ⌫
            if let recorded = KeyCombo(event: event) {
                combo = recorded
                stop()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        // The store's debounced re-registration follows a change; this covers Esc and a repeat of the same combo.
        HotKeyCenter.shared.resume()
    }
}
