import AppKit
import Carbon
import Combine
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let panel = PanelController()
    private lazy var instant = InstantModeController(panel: panel)
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        Updater.shared.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = BrandMark.menuBarImage(alert: false)
        pinStatusItemIfNeeded()
        pinWasOn = Store.shared.settings.pinMenuBarIcon
        rebuildStatusMenu()

        // A new install starts on a hotkey this Mac leaves free (HotKeyChoice), before anything is registered.
        let store = Store.shared
        if store.isNewInstall {
            let picked = HotKeyChoice.firstLaunchDefault(taken: store.presets.compactMap(\.hotKey))
            if picked != store.settings.summonHotKey { store.settings.summonHotKey = picked }
        }
        // Re-register hotkeys whenever presets or settings change.
        Publishers.CombineLatest(store.$presets, store.$settings)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.registerHotKeys()
                self?.pinnedSettingChanged()
                self?.rebuildStatusMenu()
            }
            .store(in: &subscriptions)
        registerHotKeys()
        SetupMonitor.shared.recheckHotKeys = { [weak self] in self?.recheckTakenHotKeys() }

        // Build Electron apps' accessibility trees as they come forward, so the hotkey can read their fields.
        if let front = NSWorkspace.shared.frontmostApplication { FocusReader.prepare(front) }
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .sink { FocusReader.prepare($0) }
            .store(in: &subscriptions)

        // Keep the menu-bar icon in step with setup, and walk the user through anything missing.
        let monitor = SetupMonitor.shared
        Publishers.CombineLatest3(monitor.$accessibility, monitor.$engine, monitor.$takenHotKeys)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in self?.rebuildStatusMenu() }
            .store(in: &subscriptions)
        OnboardingWindowController.shared.openPractice = { [weak self] text, frame, paste, cancel in
            self?.panel.summonPractice(text: text, boxFrame: frame, paste: paste, cancel: cancel)
        }
        // Onboarding's last step hands off to the menu bar: point at the real icon.
        OnboardingWindowController.shared.onFinished = { [weak self] in self?.showStatusPopover(.welcome) }
        let popover = StatusPopoverController.shared
        popover.tryIt = { [weak self] in
            self?.panel.summonPractice(text: Onboarding.sampleDraft, boxFrame: nil, paste: { _ in }, cancel: {})
        }
        popover.openPanel = { [weak self] in
            // Opened from Finder, Takes is frontmost; give the keyboard back to the app the user was in first.
            NSApp.hide(nil)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                self?.summonPanel()
            }
        }
        popover.openSettings = { [weak self] in self?.openPresets() }
        popover.finishSetup = { [weak self] in self?.showSetup() }
        // New users get onboarding right away: the engine check can take a few seconds (a login shell, then
        // `claude auth status`), and a first launch that shows nothing for that long looks broken. People who had
        // Takes before never see onboarding, and get the setup window if the check finds something missing.
        if Onboarding.shouldShow(Store.shared.settings) {
            OnboardingWindowController.shared.show()
        }
        Task { [weak self] in
            await monitor.refreshEngine()
            if !Onboarding.shouldShow(Store.shared.settings), !monitor.allSet {
                // Only the model missing: give it a few more seconds before opening a window that would turn
                // green on its own.
                await monitor.settleEngine()
                if !monitor.allSet { SetupWindowController.shared.show() }
            }
            // Takes crashed last time: offer to report it. After the windows above, which would close the popover
            // by taking the keyboard.
            if let crash = CrashReports.pending(Store.shared.settings), let button = self?.statusItem.button {
                StatusPopoverController.shared.showCrashOffer(crash, from: button)
            }
        }
    }

    /// Opening Takes again (Finder, Spotlight, Launchpad) while it's running: resume onboarding if it isn't
    /// finished, otherwise point at the menu-bar icon, which is where Takes lives.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if Onboarding.shouldShow(Store.shared.settings) {
            OnboardingWindowController.shared.show()
        } else {
            showStatusPopover(.reopen(missing: SetupMonitor.shared.missingSummary))
        }
        return false
    }

    private func showStatusPopover(_ kind: StatusPopoverController.Kind) {
        guard let button = statusItem.button else { return }
        StatusPopoverController.shared.show(kind, from: button)
    }

    private var pinWasOn = false

    /// Pins the icon when "Keep the menu bar icon visible" is turned on, and only then, so a later settings change
    /// doesn't pull back an icon the user has dragged elsewhere.
    private func pinnedSettingChanged() {
        let on = Store.shared.settings.pinMenuBarIcon
        defer { pinWasOn = on }
        if on && !pinWasOn { pinStatusItemIfNeeded() }
    }

    /// With "Keep the menu bar icon visible" on, moves the icon to the right end of the menu bar: at launch, and
    /// when the setting is turned on. If it's then dragged elsewhere, it stays there until the next launch.
    private func pinStatusItemIfNeeded() {
        guard Store.shared.settings.pinMenuBarIcon, let name = statusItem.autosaveName,
              MenuBarPin.needsMove(autosaveName: name, defaults: .standard) else { return }
        MenuBarPin.pin(autosaveName: name, defaults: .standard)
        StatusPopoverController.shared.close()
        NSStatusBar.system.removeStatusItem(statusItem)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = name
        statusItem.button?.image = BrandMark.menuBarImage(alert: !SetupMonitor.shared.allSet)
        rebuildStatusMenu()
    }

    /// Opens the panel, or the setup window when Takes can't work yet.
    private func summonPanel(presetID: String? = nil) {
        let monitor = SetupMonitor.shared
        // Onboarding's practice step: the hotkey opens the panel on its practice box.
        if OnboardingWindowController.shared.handlesHotKey {
            OnboardingWindowController.shared.hotKeyPressed()
            return
        }
        if !monitor.accessibility || !monitor.privacyAccepted || { if case .problem = monitor.engine { return true }; return false }() {
            // Next to what you were typing in, not where the pointer happens to be.
            openSetup(on: ScreenChoice.focused)
            return
        }
        // Pressed again while the panel has the keyboard: it keeps its draft and takes instead of starting over.
        if panel.keepsOpenPanel(presetID: presetID) { return }
        if instant.handle(presetID: presetID) { return }
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
        // macOS's own shortcuts still fire alongside a registered hotkey, so leave those out and count them as taken.
        let clashing = bindings.filter { SystemShortcuts.owner(of: $0.0) != nil }
        let failed = HotKeyCenter.shared.replaceAll(with: bindings.filter { SystemShortcuts.owner(of: $0.0) == nil })
            + clashing.map(\.0)
        if SetupMonitor.shared.takenHotKeys != failed { SetupMonitor.shared.takenHotKeys = failed }
    }

    /// Registers the hotkeys again once a taken one has come free, without dropping the working ones every second.
    private func recheckTakenHotKeys() {
        let freed = SetupMonitor.shared.takenHotKeys.contains { SystemShortcuts.owner(of: $0) == nil && HotKeyCenter.shared.isFree($0) }
        if freed { registerHotKeys() }
    }

    /// The status menu: Open Takes and Presets first, then what Takes is set to, then Settings and the app items.
    /// Show run log and Support Takes are ⌥ alternates. Until onboarding is finished, "Finish setting up" stays at the
    /// top; after that a missing piece shows as the alert dot on the icon, and the hotkey opens setup when it's blocking.
    private func rebuildStatusMenu() {
        let monitor = SetupMonitor.shared
        let store = Store.shared
        statusItem.button?.image = BrandMark.menuBarImage(alert: !monitor.allSet)
        let menu = NSMenu()
        menu.delegate = self
        if !store.settings.onboarding.finished && !monitor.allSet {
            menu.addItem(item(String(localized: "Finish setting up Takes…"), #selector(showSetup)))
            menu.addItem(.separator())
        }
        let open = item(String(localized: "Open Takes"), #selector(summon))
        let hotKey = store.settings.summonHotKey
        if let equivalent = hotKey.menuKeyEquivalent {
            open.keyEquivalent = equivalent.key
            open.keyEquivalentModifierMask = equivalent.modifiers
        } else {
            open.title = String(localized: "Open Takes   \(hotKey.inline)")
        }
        menu.addItem(open)

        let presets = NSMenuItem(title: String(localized: "Presets"), action: nil, keyEquivalent: "")
        let presetMenu = NSMenu(title: String(localized: "Presets"))
        for preset in store.presets {
            let run = item(preset.name, #selector(runPreset(_:)))
            run.representedObject = preset.id
            if let equivalent = preset.hotKey?.menuKeyEquivalent {
                run.keyEquivalent = equivalent.key
                run.keyEquivalentModifierMask = equivalent.modifiers
            }
            presetMenu.addItem(run)
        }
        presetMenu.addItem(.separator())
        presetMenu.addItem(item(String(localized: "Edit Presets…"), #selector(openPresets)))
        presets.submenu = presetMenu
        menu.addItem(presets)

        menu.addItem(.separator())
        coachItem.isEnabled = false
        modelItem.isEnabled = false
        updateStatusRows()
        menu.addItem(coachItem)
        menu.addItem(modelItem)

        menu.addItem(.separator())
        let settings = item(String(localized: "Settings…"), #selector(openPresets))
        settings.keyEquivalent = ","
        settings.keyEquivalentModifierMask = .command
        menu.addItem(settings)

        let check = NSMenuItem(title: String(localized: "Check for Updates…"), action: nil, keyEquivalent: "")
        if let updater = Updater.shared.controller {
            check.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
            check.target = updater
        }
        check.keyEquivalentModifierMask = []
        menu.addItem(check)
        menu.addItem(alternate(item(String(localized: "Support Takes…"), #selector(showSponsors))))
        menu.addItem(item(String(localized: "Report a Problem…"), #selector(reportProblem)))
        let about = item(String(localized: "About Takes"), #selector(showAbout))
        about.keyEquivalentModifierMask = []
        menu.addItem(about)
        menu.addItem(alternate(item(String(localized: "Show run log"), #selector(showLog))))
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quit Takes"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func reportProblem() { ReportProblem.open() }

    private let coachItem = NSMenuItem(title: String(localized: "English Coach: off"), action: nil, keyEquivalent: "")
    private let modelItem = NSMenuItem(title: String(localized: "Model"), action: nil, keyEquivalent: "")

    /// The status rows read what's set now, so they're refreshed each time the menu opens.
    private func updateStatusRows() {
        let settings = Store.shared.settings
        coachItem.title = Self.coachStatus(enabled: settings.coach.enabled, lessonsReady: Self.lessonsReady())
        modelItem.title = Self.modelStatus(settings)
    }

    func menuNeedsUpdate(_ menu: NSMenu) { updateStatusRows() }

    /// Lessons the coach has put together that haven't been opened yet.
    private static func lessonsReady() -> Int {
        let coach = CoachStore.shared
        return coach.stats().filter { $0.count >= CoachStore.lessonAt && coach.data.lessonsRead[$0.id] == nil }.count
    }

    nonisolated static func coachStatus(enabled: Bool, lessonsReady: Int) -> String {
        guard enabled else { return String(localized: "English Coach: off") }
        switch lessonsReady {
        case 0: return String(localized: "English Coach: on")
        case 1: return String(localized: "English Coach: on · 1 lesson ready")
        default: return String(localized: "English Coach: on · \(lessonsReady) lessons ready")
        }
    }

    static func modelStatus(_ settings: AppSettings) -> String {
        let engine: String, model: String
        switch settings.engine {
        case .claudeCode: engine = "Claude Code"; model = Models.label(settings.defaultModel)
        case .apiKey: engine = "Anthropic API"; model = Models.label(settings.defaultModel)
        case .chatGPT: engine = "ChatGPT"; model = settings.chatGPTModel
        case .provider: engine = Provider.current(settings).name; model = settings.providerModel
        case .local: engine = LocalServerKind.displayName(settings.localBaseURL); model = settings.localModel
        }
        return model.isEmpty ? String(localized: "Model: \(engine)") : String(localized: "Model: \(engine) · \(model)")
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// Shown in place of the item above it while ⌥ is held.
    private func alternate(_ item: NSMenuItem) -> NSMenuItem {
        item.keyEquivalentModifierMask = .option
        item.isAlternate = true
        return item
    }

    /// Takes shows no menu bar, but the Edit menu's shortcuts still work in the Settings window.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(localized: "Settings…"), action: #selector(openPresets), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: String(localized: "Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: String(localized: "Quit Takes"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: String(localized: "Edit"))
        edit.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }

    @objc private func summon() { summonPanel() }

    @objc private func showSetup() { openSetup(on: nil) }

    private func openSetup(on screen: NSScreen?) {
        if Onboarding.shouldShow(Store.shared.settings) {
            OnboardingWindowController.shared.show(on: screen)
        } else {
            SetupWindowController.shared.show(on: screen)
        }
    }

    @objc private func openPresets() { SettingsWindowController.shared.show(tab: .presets) }

    @objc private func runPreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        summonPanel(presetID: id)
    }

    @objc private func showAbout() {
        AboutWindowController.shared.show()
    }

    @objc private func showSponsors() {
        NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/bar-amir")!)
    }

    @objc private func showLog() {
        NSWorkspace.shared.activateFileViewerSelecting([RunLog.url])
    }
}

extension KeyCombo {
    /// The combo as a menu item's key equivalent and modifier mask, so AppKit draws and aligns the glyphs itself;
    /// nil for a key a menu can't show that way.
    var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags)? {
        var modifiers: NSEvent.ModifierFlags = []
        if self.modifiers & UInt32(controlKey) != 0 { modifiers.insert(.control) }
        if self.modifiers & UInt32(optionKey) != 0 { modifiers.insert(.option) }
        if self.modifiers & UInt32(shiftKey) != 0 { modifiers.insert(.shift) }
        if self.modifiers & UInt32(cmdKey) != 0 { modifiers.insert(.command) }
        let name = String(display.drop { "⌃⌥⇧⌘".contains($0) })
        func function(_ key: Int) -> String { String(UnicodeScalar(UInt16(key)).map(Character.init) ?? " ") }
        let named: [String: String] = [
            "Space": " ", "↵": "\r", "⇥": "\t", "⌫": "\u{8}", "Esc": "\u{1b}",
            "←": function(NSLeftArrowFunctionKey), "→": function(NSRightArrowFunctionKey),
            "↑": function(NSUpArrowFunctionKey), "↓": function(NSDownArrowFunctionKey),
        ]
        if let key = named[name] { return (key, modifiers) }
        if name.count >= 2, name.first == "F", let n = Int(name.dropFirst()), (1...12).contains(n) {
            return (function(NSF1FunctionKey + n - 1), modifiers)
        }
        guard name.count == 1 else { return nil }
        return (name.lowercased(), modifiers)
    }
}
