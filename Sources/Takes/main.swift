import AppKit

// `Takes --bench …` measures the engine from the terminal without the UI. Development builds only: it spends the
// user's accounts, and any local program can launch the installed app. `Bench.run` refuses in a distributed build.
if CommandLine.arguments.contains("--bench") {
    exit(Bench.run(arguments: CommandLine.arguments) ? 0 : 1)
}

// Dry run of field reading on the frontmost app: prints how its text box was read, never sends keys.
// It prints no text: any program can launch Takes with this flag, and it runs with Takes' Accessibility access.
if CommandLine.arguments.contains("--focus-test") {
    let snapshot = FocusReader.snapshot(prefill: .fieldText, allowCopy: false)
    print("\(snapshot.app?.bundleIdentifier ?? "?") · \(snapshot.method) · \(snapshot.text.count) chars")
    exit(0)
}

if CommandLine.arguments.contains("--ax-probe") {
    AXProbe.run(arguments: CommandLine.arguments)
    exit(0)
}

BrandResources.registerFonts()

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
