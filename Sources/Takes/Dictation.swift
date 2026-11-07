import AppKit
import AVFoundation
import Speech

/// Speak a draft into the compose box. Speech is turned into text on this Mac only
/// (`requiresOnDeviceRecognition`); if the language has no on-device model, Takes says so and never falls back to
/// Apple's servers. ⌘D starts and stops; Esc stops.
@MainActor
final class Dictation: ObservableObject {
    enum Access: Equatable { case notAsked, allowed, denied }

    /// What's blocking dictation for good until the user changes something.
    enum Blocked: Equatable { case microphone, speech }

    enum Unavailable: Equatable {
        /// No on-device speech model for this language (the name is shown, e.g. "English (US)").
        case language(String)
        case noMicrophone
        /// Recognition couldn't start or stopped with an error.
        case failed(String)
    }

    enum State: Equatable {
        case idle
        /// `explain`: our short note before the macOS dialogs. `waiting`: the macOS dialogs are up.
        case asking(explained: Bool)
        case recording
        /// Audio has stopped; waiting briefly for the final words.
        case stopping
        case denied(Blocked)
        case unavailable(Unavailable)
    }

    /// For onboarding and setup screens: is dictation ready, never asked, or blocked?
    enum PermissionState: Equatable { case notAsked, allowed, denied(Blocked) }

    static var permissionState: PermissionState { permissionState(SystemSpeech.access()) }

    static func permissionState(_ access: (mic: Access, speech: Access)) -> PermissionState {
        if access.mic == .denied { return .denied(.microphone) }
        if access.speech == .denied { return .denied(.speech) }
        return access.mic == .allowed && access.speech == .allowed ? .allowed : .notAsked
    }

    @Published private(set) var state = State.idle
    /// Input level, 0...1, for the meter.
    @Published private(set) var level: Float = 0
    /// The language being listened for, shown while recording.
    @Published private(set) var languageName = ""

    /// Each new transcript of the current recording (it replaces the previous one).
    var onTranscript: (String) -> Void = { _ in }
    /// After a macOS permission dialog the panel may have lost keyboard focus; the controller takes it back.
    var onRegainFocus: () -> Void = {}

    /// Replaceable for tests.
    var backend: SpeechBackend
    var language: () -> String
    private var session = 0
    private var stopTimeout: Task<Void, Never>?
    private var accessWatch: Task<Void, Never>?
    /// How long to wait for the final words after audio stops.
    var stopGrace: Duration = .milliseconds(1200)

    init(backend: SpeechBackend = SystemSpeech(), language: @escaping () -> String = { Store.shared.settings.dictationLanguage }) {
        self.backend = backend
        self.language = language
    }

    var isActive: Bool { state == .recording || state == .stopping }
    /// A note (asking, denied, unavailable) is showing in place of the status line.
    var showsNote: Bool {
        switch state {
        case .asking, .denied, .unavailable: return true
        default: return false
        }
    }

    // MARK: Keys

    /// ⌘D and the mic button.
    func toggle() {
        switch state {
        case .idle, .denied, .unavailable: begin()
        case .asking(explained: false): dismiss()
        case .asking(explained: true): break
        case .recording: stop()
        case .stopping: finish()
        }
    }

    /// ↵ in the draft. Returns true when dictation used it, so the draft isn't sent.
    func handleReturn() -> Bool {
        switch state {
        case .asking(explained: false): continueAsking(); return true
        case .asking(explained: true): return true
        case .denied(let blocked): openSettings(for: blocked); return true
        case .unavailable(.language): openSettings(for: nil); return true
        case .unavailable: dismiss(); return true
        // ↵ while speaking: keep what's there and let the draft be sent.
        case .recording, .stopping: finish(); return false
        case .idle: return false
        }
    }

    /// Esc. Returns true when dictation used it (stopped or closed a note), so the panel stays open.
    func handleEscape() -> Bool {
        switch state {
        case .idle: return false
        case .recording: stop()
        case .stopping: finish()
        case .asking(explained: true): return true
        case .asking, .denied, .unavailable: dismiss()
        }
        return true
    }

    /// Typing while dictating keeps the words so far and hands the box back to the keyboard.
    func userTyped() {
        if isActive { finish() }
    }

    // MARK: Flow

    func begin() {
        accessWatch?.cancel()
        let access = backend.access()
        switch Self.permissionState(access) {
        case .denied(let blocked): show(denied: blocked)
        case .notAsked: state = .asking(explained: false)
        case .allowed: startRecording()
        }
    }

    /// "Continue" on the note: ask macOS for what's still missing, then start.
    func continueAsking() {
        guard state == .asking(explained: false) else { return }
        state = .asking(explained: true)
        let token = session
        Task {
            var access = backend.access()
            if access.mic == .notAsked { access.mic = await backend.requestMicrophone() ? .allowed : .denied }
            if access.mic == .allowed, access.speech == .notAsked {
                access.speech = await backend.requestSpeech() ? .allowed : .denied
            }
            guard session == token, state == .asking(explained: true) else { return }
            onRegainFocus()
            switch Self.permissionState(access) {
            case .allowed: startRecording()
            case .denied(let blocked): show(denied: blocked)
            case .notAsked: state = .idle
            }
        }
    }

    /// Stop listening and wait briefly for the last words.
    func stop() {
        guard state == .recording else { return }
        state = .stopping
        backend.stop()
        let token = session
        stopTimeout = Task { [stopGrace] in
            try? await Task.sleep(for: stopGrace)
            guard !Task.isCancelled, self.session == token, self.state == .stopping else { return }
            self.finish()
        }
    }

    /// Stop now, keeping whatever is already in the draft.
    func finish() {
        guard isActive else { return }
        endSession()
        state = .idle
    }

    /// Close a note, or end everything when the panel closes.
    func dismiss() {
        endSession()
        state = .idle
    }

    private func endSession() {
        session += 1
        stopTimeout?.cancel()
        accessWatch?.cancel()
        backend.cancel()
        level = 0
    }

    private func show(denied blocked: Blocked) {
        state = .denied(blocked)
        watchForAccess()
    }

    /// While the "turn it on in System Settings" note shows, notice the switch being flipped and clear the note.
    private func watchForAccess() {
        accessWatch?.cancel()
        accessWatch = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, case .denied = state else { return }
                if case .denied = Self.permissionState(backend.access()) { continue }
                state = .idle
                return
            }
        }
    }

    private func startRecording() {
        let identifier = language()
        let locale = identifier.isEmpty ? Locale.current : Locale(identifier: identifier)
        languageName = Self.displayName(locale)
        session += 1
        let token = session
        do {
            try backend.start(locale: locale, onText: { [weak self] text, isFinal in
                Task { @MainActor in self?.received(text, isFinal: isFinal, token: token) }
            }, onLevel: { [weak self] level in
                Task { @MainActor in
                    guard let self, self.session == token, self.state == .recording else { return }
                    self.level = level
                }
            }, onEnd: { [weak self] error in
                Task { @MainActor in self?.ended(error: error, token: token) }
            })
            state = .recording
        } catch let error as SpeechError {
            backend.cancel()
            switch error {
            case .noOnDeviceModel: state = .unavailable(.language(languageName))
            case .noMicrophone: state = .unavailable(.noMicrophone)
            case .failed(let message): state = .unavailable(.failed(message))
            }
        } catch {
            backend.cancel()
            state = .unavailable(.failed(error.localizedDescription))
        }
    }

    private func received(_ text: String, isFinal: Bool, token: Int) {
        guard session == token, isActive else { return }
        onTranscript(text)
        if isFinal, state == .stopping { finish() }
    }

    private func ended(error: Error?, token: Int) {
        guard session == token, isActive else { return }
        // Silence or a stop isn't worth a message; the words so far stay in the draft.
        if let error, state == .recording, !SystemSpeech.isQuietEnd(error) {
            endSession()
            state = .unavailable(.failed(error.localizedDescription))
        } else {
            finish()
        }
    }

    // MARK: Settings links

    func openSettings(for blocked: Blocked?) {
        let pane: String
        switch blocked {
        case .microphone: pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .speech: pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        case nil: pane = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
        }
        if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
    }

    static func displayName(_ locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    /// Languages with an on-device model, for the setting.
    static var onDeviceLanguages: [(id: String, name: String)] {
        SFSpeechRecognizer.supportedLocales()
            .filter { SFSpeechRecognizer(locale: $0)?.supportsOnDeviceRecognition == true }
            .map { (id: $0.identifier, name: displayName($0)) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// For `--snapshot` renders and tests.
    func preview(_ state: State, level: Float = 0, languageName: String = "English (US)") {
        self.state = state
        self.level = level
        self.languageName = languageName
    }
}

/// Puts dictated words into the draft at the caret. Each new transcript replaces the previous one, so the words
/// settle in place while the recognizer revises them. A selection is replaced, as with macOS dictation.
struct DictationInsertion {
    let original: String
    let selection: NSRange
    private let before: String
    private let after: String

    init(text: String, selection: NSRange) {
        original = text
        let length = (text as NSString).length
        let location = min(max(selection.location, 0), length)
        let clamped = NSRange(location: location, length: min(max(selection.length, 0), length - location))
        self.selection = clamped
        before = (text as NSString).substring(to: clamped.location)
        after = (text as NSString).substring(from: NSMaxRange(clamped))
    }

    /// The draft with `transcript` in place, and where the caret goes (UTF-16 offset, just after the words).
    func apply(_ transcript: String) -> (text: String, caret: Int) {
        let words = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return (original, NSMaxRange(selection)) }
        let lead = Self.needsSpace(between: before.last, and: words.first) ? " " : ""
        let trail = Self.needsSpace(between: words.last, and: after.first) ? " " : ""
        let head = before + lead + words
        return (head + trail + after, (head as NSString).length)
    }

    private static func needsSpace(between left: Character?, and right: Character?) -> Bool {
        guard let left, let right else { return false }
        if left.isWhitespace || right.isWhitespace { return false }
        // No space before closing punctuation or after an opening bracket or quote.
        if ".,;:!?)]}…".contains(right) { return false }
        if "([{\"“‘".contains(left) { return false }
        return true
    }
}

// MARK: - Speech

enum SpeechError: Error {
    case noOnDeviceModel, noMicrophone, failed(String)
}

/// The microphone and the recognizer, behind a protocol so the state machine can be tested without either.
protocol SpeechBackend: AnyObject {
    func access() -> (mic: Dictation.Access, speech: Dictation.Access)
    func requestMicrophone() async -> Bool
    func requestSpeech() async -> Bool
    /// Starts listening. Callbacks may arrive on any thread.
    func start(locale: Locale, onText: @escaping (String, Bool) -> Void, onLevel: @escaping (Float) -> Void,
               onEnd: @escaping (Error?) -> Void) throws
    /// Stops the microphone; the recognizer still delivers its final words.
    func stop()
    /// Stops everything at once.
    func cancel()
}

/// AVAudioEngine feeding SFSpeechRecognizer, on-device only.
final class SystemSpeech: SpeechBackend {
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    static func access() -> (mic: Dictation.Access, speech: Dictation.Access) {
        let mic: Dictation.Access
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: mic = .allowed
        case .notDetermined: mic = .notAsked
        default: mic = .denied
        }
        let speech: Dictation.Access
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: speech = .allowed
        case .notDetermined: speech = .notAsked
        default: speech = .denied
        }
        return (mic, speech)
    }

    func access() -> (mic: Dictation.Access, speech: Dictation.Access) { Self.access() }

    func requestMicrophone() async -> Bool { await AVCaptureDevice.requestAccess(for: .audio) }

    func requestSpeech() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    func start(locale: Locale, onText: @escaping (String, Bool) -> Void, onLevel: @escaping (Float) -> Void,
               onEnd: @escaping (Error?) -> Void) throws {
        cancel()
        // Never fall back to server recognition: no on-device model means no dictation.
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else {
            throw SpeechError.noOnDeviceModel
        }
        guard AVCaptureDevice.default(for: .audio) != nil else { throw SpeechError.noMicrophone }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { throw SpeechError.noMicrophone }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            onLevel(Self.level(of: buffer))
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw SpeechError.failed(String(localized: "The microphone couldn't start: \(error.localizedDescription)"))
        }

        task = recognizer.recognitionTask(with: request) { result, error in
            if let result { onText(result.bestTranscription.formattedString, result.isFinal) }
            if error != nil || result?.isFinal == true { onEnd(error) }
        }
        self.engine = engine
        self.request = request
    }

    func stop() {
        stopAudio()
        request?.endAudio()
    }

    func cancel() {
        stopAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    private func stopAudio() {
        guard let engine else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        self.engine = nil
    }

    /// RMS of the buffer on a -50...0 dB scale, mapped to 0...1.
    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let db = 20 * log10(max(rms, 1e-6))
        return min(max((db + 50) / 50, 0), 1)
    }

    /// "No speech detected" and a cancelled task end a recording without anything worth reporting.
    static func isQuietEnd(_ error: Error) -> Bool {
        let error = error as NSError
        return (error.domain == "kAFAssistantErrorDomain" && [203, 216, 1110].contains(error.code))
            || error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError
    }
}
