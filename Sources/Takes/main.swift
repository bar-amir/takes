import AppKit

// `Takes --bench …` measures the engine from the terminal without the UI.
if CommandLine.arguments.contains("--bench") {
    Bench.run(arguments: CommandLine.arguments)
    exit(0)
}

// Dry run of field reading on the frontmost app: prints how its text box was read, never sends keys.
if CommandLine.arguments.contains("--focus-test") {
    let snapshot = FocusReader.snapshot(prefill: .fieldText, allowCopy: false)
    print("\(snapshot.app?.bundleIdentifier ?? "?") · \(snapshot.method) · \(snapshot.text.count) chars · \(snapshot.text.prefix(80).debugDescription)")
    exit(0)
}

if CommandLine.arguments.contains("--ax-probe") {
    AXProbe.run(arguments: CommandLine.arguments)
    exit(0)
}

if CommandLine.arguments.contains("--snapshot") {
    MainActor.assumeIsolated { Snapshot.run(arguments: CommandLine.arguments) }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
