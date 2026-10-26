import Foundation

/// `Takes --bench [--runs N] [--model M] [--effort E] [--takes N] [--naive]`
/// Runs the engine N times on a sample draft and prints timings.
enum Bench {
    static func run(arguments: [String]) {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        let runs = Int(value("--runs") ?? "") ?? 3
        let draft = value("--draft") ?? "ya thursday works but i need the specs by wed eod otherwise qa slips again, also can someone own the release notes this time"
        let takes = Int(value("--takes") ?? "") ?? 3
        let preset = Store.defaultPresets[0]
        let request = EngineRequest(
            system: PromptBuilder.system(preset: preset, takes: takes, rules: AppSettings().voiceRules),
            user: PromptBuilder.user(draft: draft, mode: .fresh, takes: takes),
            takes: takes,
            model: value("--model") ?? Models.sonnet,
            effort: value("--effort") ?? "low"
        )
        let useAPI = arguments.contains("--api")
        let engine: TakesEngine = useAPI ? APIEngine() : ClaudeCodeEngine(lean: !arguments.contains("--naive"))
        print("engine: \(useAPI ? "API key" : "Claude Code at \(ClaudeCodeEngine.claudePath ?? "not found")")")
        print("model=\(request.model) effort=\(request.effort) takes=\(request.takes) runs=\(runs)")

        var walls: [Int] = []
        var firsts: [Int] = []
        for i in 1...runs {
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached {
                do {
                    let result = try await engine.run(request) { _ in }
                    walls.append(result.wallMs)
                    if let first = result.firstTextMs { firsts.append(first) }
                    print("run \(i): first words \(result.firstTextMs ?? -1) ms · all \(result.takes.count) takes \(result.wallMs) ms")
                    if i == 1 { result.takes.enumerated().forEach { print("  \($0.offset + 1). \($0.element)") } }
                    RunLog.append(["kind": "bench", "model": request.model, "effort": request.effort,
                                   "takes": request.takes, "wallMs": result.wallMs,
                                   "firstTextMs": result.firstTextMs ?? -1])
                } catch {
                    print("run \(i): error \(error.localizedDescription)")
                }
                semaphore.signal()
            }
            semaphore.wait()
        }
        func summary(_ name: String, _ values: [Int]) {
            guard !values.isEmpty else { return }
            let sorted = values.sorted()
            print("median \(name): \(sorted[sorted.count / 2]) ms (min \(sorted.first!), max \(sorted.last!))")
        }
        summary("first words", firsts)
        summary("all takes", walls)
    }
}
