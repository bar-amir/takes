import Foundation

/// `Takes --bench --tone inline|separate [--runs N] [--model M] [--takes N]`
/// Compares two ways to get a tone note per take: asking the writing model for a `[tone]` line per take
/// (inline), or the separate Haiku call Takes uses (separate). Prints when the takes and the notes are ready.
enum ToneBench {
    static let inlineInstruction = """

    End each version with one more line: [tone] and 2 to 4 lowercase words on how it may come across, \
    e.g. "[tone] warm and clear" or "[tone] a bit curt". Takes removes that line before pasting.
    """

    static func run(arguments: [String]) {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        let inline = value("--tone") == "inline"
        let runs = Int(value("--runs") ?? "") ?? 2
        let takes = Int(value("--takes") ?? "") ?? 3
        let draft = "ya thursday works but i need the specs by wed eod otherwise qa slips again, also can someone own the release notes this time"
        let base = PromptBuilder.system(preset: Store.defaultPresets[0], takes: takes, rules: AppSettings().voiceRules)
        let request = EngineRequest(system: inline ? base + inlineInstruction : base,
                                    user: PromptBuilder.user(draft: draft, mode: .fresh, takes: takes),
                                    takes: takes, model: value("--model") ?? Models.sonnet, effort: "low")
        let engine: TakesEngine = arguments.contains("--api") ? APIEngine() : ClaudeCodeEngine()
        print("tone=\(inline ? "inline" : "separate") model=\(request.model) takes=\(takes) runs=\(runs)")

        for i in 1...runs {
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached {
                do {
                    let result = try await engine.run(request) { _ in }
                    var notes: [String?]
                    var notesMs = result.wallMs
                    if inline {
                        notes = result.takes.map { take in
                            take.components(separatedBy: "\n").last
                                .flatMap { $0.hasPrefix("[tone]") ? ToneCheck.clean(String($0.dropFirst(6))) : nil }
                        }
                    } else {
                        let started = Date()
                        let read = try await engine.run(ToneCheck.takesRequest(takes: result.takes, showTone: true)!) { _ in }
                        notesMs += Int(Date().timeIntervalSince(started) * 1000)
                        notes = ToneCheck.parseTakeTones(read.takes.joined(separator: "\n"), count: result.takes.count)
                    }
                    print("run \(i): first words \(result.firstTextMs ?? -1) ms · takes \(result.wallMs) ms · notes \(notesMs) ms · \(notes.compactMap { $0 }.count)/\(result.takes.count): \(notes.map { $0 ?? "–" })")
                } catch {
                    print("run \(i): error \(error.localizedDescription)")
                }
                semaphore.signal()
            }
            semaphore.wait()
        }
    }
}
