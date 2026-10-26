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
        let request = EngineRequest(
            draft: value("--draft") ?? "ya thursday works but i need the specs by wed eod otherwise qa slips again, also can someone own the release notes this time",
            preset: Preset.builtIn[0],
            takes: Int(value("--takes") ?? "") ?? 3,
            model: value("--model") ?? "sonnet",
            effort: value("--effort") ?? "low",
            lean: !arguments.contains("--naive")
        )
        print("claude: \(Engine.claudePath ?? "not found")")
        print("model=\(request.model) effort=\(request.effort) takes=\(request.takes) lean=\(request.lean) runs=\(runs)")

        var walls: [Int] = []
        for i in 1...runs {
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached {
                do {
                    let result = try await Engine.run(request)
                    walls.append(result.wallMs)
                    let overhead = result.apiMs.map { result.wallMs - $0 }
                    print("run \(i): wall \(result.wallMs) ms · claude \(result.durationMs ?? -1) ms · api \(result.apiMs ?? -1) ms · overhead \(overhead ?? -1) ms")
                    if i == 1 { result.takes.enumerated().forEach { print("  \($0.offset + 1). \($0.element)") } }
                    RunLog.append(["kind": "bench", "model": request.model, "effort": request.effort, "lean": request.lean,
                                   "takes": request.takes, "wallMs": result.wallMs, "apiMs": result.apiMs ?? -1])
                } catch {
                    print("run \(i): error \(error.localizedDescription)")
                }
                semaphore.signal()
            }
            semaphore.wait()
        }
        if !walls.isEmpty {
            let sorted = walls.sorted()
            print("median wall: \(sorted[sorted.count / 2]) ms (min \(sorted.first!), max \(sorted.last!))")
        }
    }
}
