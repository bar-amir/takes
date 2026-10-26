import AppKit

// `Takes --bench …` measures the engine from the terminal without the UI.
if CommandLine.arguments.contains("--bench") {
    Bench.run(arguments: CommandLine.arguments)
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
