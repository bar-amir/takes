import AppKit

/// Installs Claude Code with Anthropic's official installer, in the background, for people who have never used
/// Terminal. Takes doesn't ship or change Claude Code: each install downloads the installer from claude.ai, which
/// fetches the current release from Anthropic, checks its checksum and puts `claude` in ~/.local/bin. No password.
@MainActor
final class ClaudeInstaller: ObservableObject {
    static let shared = ClaudeInstaller()

    enum State: Equatable {
        case idle
        /// Fetching the installer and the release.
        case downloading
        /// The installer's own setup step, after the download.
        case settingUp
        case failed(String)

        var isBusy: Bool { self == .downloading || self == .settingUp }

        /// The progress line under the button while it runs.
        var progress: String? {
            switch self {
            case .downloading: return String(localized: "Downloading Claude Code from Anthropic…")
            case .settingUp: return String(localized: "Setting up Claude Code…")
            case .idle, .failed: return nil
            }
        }

        var error: String? { if case .failed(let message) = self { return message }; return nil }
    }

    @Published var state = State.idle

    nonisolated static let installerURL = "https://claude.ai/install.sh"
    /// Anthropic's install page, for installing by hand when this fails.
    static let manualURL = URL(string: "https://code.claude.com/docs/en/setup")!
    /// The official one-liner. `pipefail`, so a failed download fails the install instead of running an empty script;
    /// `--proto '=https' --tlsv1.2`, so curl never follows a redirect to plain http or uses old TLS.
    nonisolated static let command = "set -o pipefail; curl --proto '=https' --tlsv1.2 -fsSL \(installerURL) | bash"
    /// Usually under a minute; a stalled download is stopped after this.
    nonisolated static let timeout: TimeInterval = 600

    /// Asks first, then installs. True once Claude Code is on this Mac, installed now or already there.
    func installAfterConfirming() async -> Bool {
        guard !state.isBusy else { return false }
        if await ClaudeCodeEngine.locate() != nil {
            state = .idle
            return true
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Install Claude Code?")
        alert.informativeText = String(localized: "Takes downloads Claude Code from Anthropic and installs it in your home folder. It takes about a minute and needs no password. Then Terminal opens so you can sign in to Claude.")
        alert.addButton(withTitle: String(localized: "Install"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        // Takes is a menu-bar app; unless it's active, the alert shows but can't be clicked.
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        return await install()
    }

    /// Runs the installer and reports how it went in `state`. True when `claude` is found afterwards.
    func install() async -> Bool {
        guard !state.isBusy else { return false }
        state = .downloading
        let outcome = await Self.run { [weak self] line in
            guard line.hasPrefix("Setting up") else { return }
            Task { @MainActor in if self?.state == .downloading { self?.state = .settingUp } }
        }
        if let failure = Self.failureMessage(status: outcome.status, output: outcome.output, timedOut: outcome.timedOut) {
            state = .failed(failure)
            return false
        }
        guard await ClaudeCodeEngine.locate() != nil else {
            state = .failed(String(localized: "Claude Code installed, but Takes can't find it. Quit and reopen Takes, then try again."))
            return false
        }
        state = .idle
        await SetupMonitor.shared.refreshEngine()
        return true
    }

    /// The installer's exit status and the end of what it printed. Runs off the main thread.
    nonisolated private static func run(onLine: @escaping @Sendable (String) -> Void) async -> (status: Int32, output: String, timedOut: Bool) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", command]
                process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
                process.environment = env
                let pipe = Pipe()
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: (-1, error.localizedDescription, false))
                    return
                }
                let stopper = ProcessStopper(process)
                stopper.started()
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { stopper.timeOut() }

                var output = Data()
                var pending = Data()
                let reader = pipe.fileHandleForReading
                while true {
                    let data = reader.availableData
                    if data.isEmpty { break }
                    output.append(data)
                    // Only the end is kept for the error message.
                    if output.count > 16_000 { output = output.suffix(8_000) }
                    pending.append(data)
                    while let newline = pending.firstIndex(of: 0x0A) {
                        onLine(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
                        pending.removeSubrange(pending.startIndex...newline)
                    }
                }
                process.waitUntilExit()
                continuation.resume(returning: (process.terminationStatus, String(decoding: output, as: UTF8.self), stopper.timedOut))
            }
        }
    }

    /// What to show when the install didn't work, or nil when it did.
    nonisolated static func failureMessage(status: Int32, output: String, timedOut: Bool) -> String? {
        if timedOut {
            return String(localized: "The download took too long, so Takes stopped it. Check your internet connection, then try again.")
        }
        guard status != 0 else { return nil }
        let lower = output.lowercased()
        // curl's exit codes for no connection: 6 can't resolve the host, 7 can't connect, 28 timed out, 35 TLS.
        let offline = ["could not resolve host", "failed to connect", "couldn't connect", "network is unreachable",
                       "operation timed out", "connection timed out"]
        if [6, 7, 28, 35].contains(status) || offline.contains(where: lower.contains) {
            return String(localized: "Couldn't reach Anthropic. Check your internet connection, then try again.")
        }
        if lower.contains("supported-countries") || lower.contains("not available in your region") {
            return String(localized: "Claude Code's download isn't available from here. Anthropic lists where it is at anthropic.com/supported-countries.")
        }
        if lower.contains("no space left") {
            return String(localized: "There isn't enough free space on this Mac to install Claude Code. Free some up, then try again.")
        }
        guard let line = lastLine(output) else { return String(localized: "Couldn't install Claude Code. Try again, or install it yourself.") }
        let detail = line + (line.hasSuffix("…") ? "" : ".")
        return String(localized: "Couldn't install Claude Code: \(detail) Try again, or install it yourself.")
    }

    /// The installer's last line, without terminal colours, cut to a sentence's length.
    nonisolated static func lastLine(_ output: String) -> String? {
        let plain = output.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
        guard let line = plain.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) })
            .last(where: { !$0.isEmpty }) else { return nil }
        if line.count > 160 { return String(line.prefix(160)) + "…" }
        return line.hasSuffix(".") ? String(line.dropLast()) : line
    }
}
