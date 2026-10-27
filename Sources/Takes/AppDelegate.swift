import AppKit
import Combine
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let panel = PanelController()
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        Updater.shared.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Takes")
        rebuildStatusMenu()

        // Re-register hotkeys whenever presets or settings change.
        let store = Store.shared
        Publishers.CombineLatest(store.$presets, store.$settings)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.registerHotKeys()
                self?.rebuildStatusMenu()
            }
            .store(in: &subscriptions)
        registerHotKeys()
        // A taken shortcut frees up when the user turns the clashing one off in System Settings; pick that up.
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if !SetupMonitor.shared.takenHotKeys.isEmpty { self?.registerHotKeys() } }
        }

        // Keep the menu-bar icon in step with setup, and walk the user through anything missing.
        let monitor = SetupMonitor.shared
        Publishers.CombineLatest3(monitor.$accessibility, monitor.$engine, monitor.$takenHotKeys)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in self?.rebuildStatusMenu() }
            .store(in: &subscriptions)
        Task {
            await monitor.refreshEngine()
            if !monitor.allSet { SetupWindowController.shared.show() }
        }
    }

    /// Opens the panel, or the setup window when Takes can't work yet.
    private func summonPanel(presetID: String? = nil) {
        let monitor = SetupMonitor.shared
        if !monitor.accessibility || !monitor.privacyAccepted || { if case .problem = monitor.engine { return true }; return false }() {
            SetupWindowController.shared.show()
            return
        }
        panel.summon(presetID: presetID)
    }

    private func registerHotKeys() {
        let store = Store.shared
        var bindings: [(KeyCombo, () -> Void)] = [(store.settings.summonHotKey, { [weak self] in self?.summonPanel() })]
        for preset in store.presets {
            guard let combo = preset.hotKey else { continue }
            let id = preset.id
            bindings.append((combo, { [weak self] in self?.summonPanel(presetID: id) }))
        }
        // A combo macOS itself uses would fire both (⌃⌥Space also opened Finder's search window and left a
        // full-screen app's Space), so it isn't registered and setup asks for another.
        let clashing = bindings.map(\.0).filter { SystemShortcuts.clash(with: $0) != nil }
        let failed = clashing + HotKeyCenter.shared.replaceAll(with: bindings.filter { !clashing.contains($0.0) })
        if SetupMonitor.shared.takenHotKeys != failed { SetupMonitor.shared.takenHotKeys = failed }
    }

    private func rebuildStatusMenu() {
        let monitor = SetupMonitor.shared
        statusItem.button?.image = NSImage(systemSymbolName: monitor.allSet ? "text.bubble" : "exclamationmark.bubble",
                                           accessibilityDescription: monitor.allSet ? "Takes" : "Takes needs setup")
        let menu = NSMenu()
        if !monitor.allSet {
            let finish = NSMenuItem(title: "Finish setting up Takes…", action: #selector(showSetup), keyEquivalent: "")
            finish.target = self
            menu.addItem(finish)
            menu.addItem(.separator())
        }
        let open = NSMenuItem(title: "Open Takes   \(Store.shared.settings.summonHotKey.display)", action: #selector(summon), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        for tab in SettingsTab.allCases {
            let item = NSMenuItem(title: "\(tab.rawValue)…", action: #selector(openSettings(_:)), keyEquivalent: "")
            item.representedObject = tab.rawValue
            item.target = self
            menu.addItem(item)
        }
        let setup = NSMenuItem(title: "Setup and permissions…", action: #selector(showSetup), keyEquivalent: "")
        setup.target = self
        menu.addItem(setup)
        menu.addItem(.separator())
        let log = NSMenuItem(title: "Show run log", action: #selector(showLog), keyEquivalent: "")
        log.target = self
        menu.addItem(log)
        let about = NSMenuItem(title: "About Takes", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        if let updater = Updater.shared.controller {
            let check = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
            check.target = updater
            menu.addItem(check)
        }
        menu.addItem(withTitle: "Quit Takes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    /// Takes shows no menu bar, but the Edit menu's shortcuts still work in the Settings window.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openPresets), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit Takes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }

    @objc private func summon() { summonPanel() }

    @objc private func showSetup() { SetupWindowController.shared.show() }

    @objc private func openPresets() { SettingsWindowController.shared.show(tab: .presets) }

    @objc private func openSettings(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tab = SettingsTab(rawValue: raw) else { return }
        SettingsWindowController.shared.show(tab: tab)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Rewrite anything, in any text box, with Claude.\ngithub.com/bar-amir/takes"),
        ])
    }

    @objc private func showLog() {
        NSWorkspace.shared.activateFileViewerSelecting([RunLog.url])
    }
}
