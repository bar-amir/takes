import AppKit
import ApplicationServices

/// `open -n Takes.app --args --ax-probe <seconds>` waits, then writes what the frontmost app's
/// accessibility tree reports about the focused element to ~/Library/Logs/Takes/ax-probe.txt.
/// Used to work out why a particular app's text box can't be read.
enum AXProbe {
    static func run(arguments: [String]) {
        let delay = arguments.firstIndex(of: "--ax-probe").flatMap { arguments.indices.contains($0 + 1) ? Double(arguments[$0 + 1]) : nil } ?? 3
        Thread.sleep(forTimeInterval: delay)

        var lines: [String] = ["Takes AX probe · \(Date())", "trusted: \(FocusReader.isTrusted(prompt: false))"]
        guard let app = NSWorkspace.shared.frontmostApplication else { return write(lines + ["no frontmost app"]) }
        lines.append("frontmost: \(app.localizedName ?? "?") (\(app.bundleIdentifier ?? "?")) pid \(app.processIdentifier)")

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let systemWide = AXUIElementCreateSystemWide()
        lines.append("before enabling, app focused: \(describe(focused(appElement)))")
        let manual = AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        lines.append("set AXManualAccessibility: \(manual.rawValue)")

        for step in 0..<6 {
            Thread.sleep(forTimeInterval: 0.15)
            lines.append("t+\(150 * (step + 1))ms app focused: \(describe(focused(appElement)))")
            lines.append("t+\(150 * (step + 1))ms system-wide focused: \(describe(focused(systemWide)))")
        }

        if let element = focused(appElement) ?? focused(systemWide) {
            lines.append("")
            lines.append("attributes: \(attributeNames(element).joined(separator: ", "))")
            var current: AXUIElement? = element
            for depth in 0..<8 {
                guard let node = current else { break }
                lines.append("ancestor \(depth): \(describe(node))")
                current = copy(node, kAXParentAttribute)
            }
        }
        write(lines)
    }

    private static func focused(_ element: AXUIElement) -> AXUIElement? { copy(element, kAXFocusedUIElementAttribute) }

    private static func copy<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func attributeNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    private static func describe(_ element: AXUIElement?) -> String {
        guard let element else { return "nil" }
        let role: String = copy(element, kAXRoleAttribute) ?? "?"
        let subrole: String = copy(element, kAXSubroleAttribute) ?? "-"
        let value: String? = copy(element, kAXValueAttribute)
        let selected: String? = copy(element, kAXSelectedTextAttribute)
        let editable: Bool? = copy(element, "AXEditableAncestor").map { (_: AXUIElement) in true }
        let chars: Int? = copy(element, kAXNumberOfCharactersAttribute)
        return "role=\(role) subrole=\(subrole) value=\(value.map { "\"\($0.prefix(60))\"" } ?? "nil") "
            + "selected=\(selected.map { "\"\($0.prefix(40))\"" } ?? "nil") chars=\(chars.map(String.init) ?? "nil") editableAncestor=\(editable ?? false)"
    }

    private static func write(_ lines: [String]) {
        let url = RunLog.url.deletingLastPathComponent().appendingPathComponent("ax-probe.txt")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
