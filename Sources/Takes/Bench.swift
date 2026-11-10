import Foundation
import Security

/// `Takes --bench [--runs N] [--model M] [--effort E] [--takes N] [--naive] [--draft D] [--context C]`
/// Runs the engine N times on a sample draft and prints timings.
///
/// A developer tool: it spends the signed-in plan or the saved API key on text the caller picks, and any local
/// program can launch the installed app. So it only runs in a development build (see `isAllowed`).
enum Bench {
    static let developmentOnlyMessage = "--bench is only available in development builds (./build.sh)."

    /// Whether this is a development build, from what `SecCodeCopySigningInformation` says about the app's own code
    /// signature (`nil` when it couldn't be read). A Developer ID build, as distributed, carries the developer's team
    /// identifier. The ad-hoc signature from `./build.sh` and the linker's own signature on `swift build` output
    /// carry none. When the signature can't be read the answer is no.
    static func isAllowed(signingInformation: [String: Any]?) -> Bool {
        guard let signingInformation else { return false }
        let team = signingInformation[kSecCodeInfoTeamIdentifier as String] as? String
        return team?.isEmpty ?? true
    }

    /// The signing information of the running app: an empty dictionary when it isn't signed at all, `nil` when it
    /// can't be read.
    static func currentSigningInformation() -> [String: Any]? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        let status = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        if status == errSecCSUnsigned { return [:] }
        guard status == errSecSuccess else { return nil }
        return information as? [String: Any]
    }

    /// Returns false, after saying why on stderr, when `--bench` is refused. Nothing is called before that check,
    /// so a refused run reaches no engine, no Keychain item and no account.
    @discardableResult
    static func run(arguments: [String], signingInformation: [String: Any]? = currentSigningInformation()) -> Bool {
        guard isAllowed(signingInformation: signingInformation) else {
            FileHandle.standardError.write(Data((developmentOnlyMessage + "\n").utf8))
            return false
        }
        if arguments.contains("--tone") { ToneBench.run(arguments: arguments); return true }
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        let runs = Int(value("--runs") ?? "") ?? 3
        let draft = value("--draft") ?? "ya thursday works but i need the specs by wed eod otherwise qa slips again, also can someone own the release notes this time"
        let takes = Int(value("--takes") ?? "") ?? 3
        let preset = Store.defaultPresets[0]
        let context = value("--context")
        let request = EngineRequest(
            system: PromptBuilder.system(preset: preset, takes: takes, rules: AppSettings().voiceRules, hasContext: context != nil),
            user: PromptBuilder.user(draft: draft, mode: .fresh, takes: takes, context: context),
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
        return true
    }
}
