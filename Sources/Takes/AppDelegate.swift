import AppKit
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private let panel = PanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Takes")

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Takes  ⌃⌥Space", action: #selector(summon), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Show run log", action: #selector(showLog), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        // Reading the focused field and sending ⌘V both need Accessibility access.
        _ = FocusReader.isTrusted(prompt: true)

        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            MainActor.assumeIsolated { self?.panel.summon() }
        }
    }

    @objc private func summon() { panel.summon() }

    @objc private func showLog() {
        NSWorkspace.shared.activateFileViewerSelecting([RunLog.url])
    }
}
