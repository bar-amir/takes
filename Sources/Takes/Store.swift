import AppKit
import Carbon
import Combine

// MARK: - Models

struct KeyCombo: Codable, Hashable {
    var keyCode: UInt32
    /// Carbon modifier mask (controlKey, optionKey, shiftKey, cmdKey).
    var modifiers: UInt32
    var display: String
    /// `display` for use inside a sentence: kept left to right ("⌥⇧Space") in right-to-left languages.
    var inline: String { "\u{2066}" + display + "\u{2069}" }
}

struct AppRef: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

enum TakeLength: String, Codable, CaseIterable, Identifiable {
    case sameOrShorter, shorter, any, longer
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sameOrShorter: return String(localized: "Same or shorter")
        case .shorter: return String(localized: "Shorter")
        case .any: return String(localized: "Any length")
        case .longer: return String(localized: "Longer")
        }
    }
    /// The label as it reads mid-line, after a " · " ("3 takes · Sonnet 5.5 · same or shorter").
    var inlineLabel: String {
        switch self {
        case .sameOrShorter: return String(localized: "same or shorter", comment: "Take length, mid-line")
        case .shorter: return String(localized: "shorter", comment: "Take length, mid-line")
        case .any: return String(localized: "any length", comment: "Take length, mid-line")
        case .longer: return String(localized: "longer", comment: "Take length, mid-line")
        }
    }
}

enum Models {
    static let haiku = "claude-haiku-5-5"
    static let sonnet = "claude-sonnet-5-5"
    static let opus = "claude-opus-5-5"
    /// Full model IDs: on some plans the short aliases ("sonnet") still resolve to older models.
    static let all: [(id: String, label: String)] = [(haiku, "Haiku 5.5"), (sonnet, "Sonnet 5.5"), (opus, "Opus 5.5")]
    static let efforts = ["low", "medium", "high"]

    static func label(_ id: String) -> String { all.first { $0.id == id }?.label ?? id }

    /// "Low", "Medium" or "High" for an effort's raw value, for menus.
    static func effortLabel(_ effort: String) -> String {
        switch effort {
        case "low": return String(localized: "Low", comment: "Effort level")
        case "medium": return String(localized: "Medium", comment: "Effort level")
        case "high": return String(localized: "High", comment: "Effort level")
        default: return effort.capitalized
        }
    }
}

struct Preset: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String
    var colorHex: String
    var hotKey: KeyCombo?
    var instruction: String
    var dos: [String] = []
    var avoid: [String] = []
    /// "Write like me": messages in the user's own voice, up to five.
    var examples: [String] = []
    var language: ReplyLanguage = .sameAsDraft
    var length: TakeLength = .sameOrShorter
    /// Apps where this preset is picked automatically.
    var apps: [AppRef] = []
    var takes = 3
    var model = Models.sonnet
    var effort = "low"
    /// Instant mode: the preset's hotkey writes 1 take and pastes it with no panel. Optional so presets saved
    /// before it existed still load; read it through `writesInstantly`.
    var instantMode: Bool?
    /// Proofread-style: fix mistakes only and show the fixes inline. Optional so older presets decode
    /// (missing means off); read it through `isMinimalEdits`.
    var minimalEdits: Bool? = nil
    /// The gallery template this preset was copied from, so the gallery can show it as added.
    var galleryID: String?
    /// A short note on how each take may come across, and ⌘T in compose.
    var showTone = true

    static let maxExamples = 5
    /// How many takes a preset can ask for: the range its picker offers.
    static let takesRange = 1...5
    static let colors = ["#2F55E0", "#1D6B4F", "#8A4B08", "#7A3FD1", "#B42318", "#0E6E8C", "#55555E"]

    var summary: String {
        let count = takes == 1 ? String(localized: "1 take") : String(localized: "\(takes) takes")
        let effortText: String
        switch effort {
        case "low": effortText = String(localized: "Low effort")
        case "medium": effortText = String(localized: "Medium effort")
        case "high": effortText = String(localized: "High effort")
        default: effortText = String(localized: "\(effort.capitalized) effort")
        }
        return "\(count) · \(Models.label(model)) · \(effortText) · \(length.inlineLabel)"
    }
}

extension Preset {
    /// Tolerant decoding: presets saved by an older version (missing newer keys) still load, and a value that can't
    /// be read falls back to its default instead of losing the preset. A preset without a name or instruction isn't one.
    init(from decoder: Decoder) throws {
        let r = try LenientReader(decoder, keyedBy: CodingKeys.self)
        let d = Preset(name: "", colorHex: Preset.colors[0], instruction: "")
        id = r.value(String.self, .id) ?? d.id
        name = try r.container.decode(String.self, forKey: .name)
        colorHex = r.value(String.self, .colorHex) ?? d.colorHex
        hotKey = r.value(KeyCombo.self, .hotKey)
        instruction = try r.container.decode(String.self, forKey: .instruction)
        dos = r.list(String.self, .dos) ?? d.dos
        avoid = r.list(String.self, .avoid) ?? d.avoid
        examples = r.list(String.self, .examples) ?? d.examples
        language = r.value(ReplyLanguage.self, .language) ?? d.language
        length = r.value(TakeLength.self, .length) ?? d.length
        apps = r.list(AppRef.self, .apps) ?? d.apps
        takes = r.value(Int.self, .takes) ?? d.takes
        model = r.value(String.self, .model) ?? d.model
        effort = r.value(String.self, .effort) ?? d.effort
        showTone = r.value(Bool.self, .showTone) ?? d.showTone
        instantMode = r.value(Bool.self, .instantMode)
        minimalEdits = r.value(Bool.self, .minimalEdits)
        galleryID = r.value(String.self, .galleryID)
    }
}

struct VoiceRule: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var text: String
    var enabled = true
}

enum EngineKind: String, Codable {
    case claudeCode, apiKey, local
    /// Your own API key for OpenAI or another OpenAI-compatible provider (ProviderEngine.swift).
    case provider
    /// Sign in with ChatGPT: a Plus or Pro plan used through OpenAI's OAuth flow (ChatGPTEngine.swift).
    case chatGPT

    /// Engines where every preset runs on the one model picked in Settings › Model, and Effort (a Claude setting) is hidden.
    var usesOneModel: Bool { self == .local || self == .provider || self == .chatGPT }
    /// Engines that talk to Anthropic.
    var isClaude: Bool { self == .claudeCode || self == .apiKey }
}
/// Where the panel opens. Whichever is picked, the panel moves aside rather than cover the text box.
enum PanelPosition: String, Codable, CaseIterable, Identifiable {
    case nearCursor, topLeft, topCenter, topRight, center, bottomLeft, bottomCenter, bottomRight
    var id: String { rawValue }
    var label: String {
        switch self {
        case .nearCursor: String(localized: "Next to the text box")
        case .topLeft: String(localized: "Top left")
        case .topCenter: String(localized: "Top center")
        case .topRight: String(localized: "Top right")
        case .center: String(localized: "Center of the screen")
        case .bottomLeft: String(localized: "Bottom left")
        case .bottomCenter: String(localized: "Bottom center")
        case .bottomRight: String(localized: "Bottom right")
        }
    }
}
enum Prefill: String, Codable, CaseIterable, Identifiable {
    case fieldText, selectionOnly, empty
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fieldText: return String(localized: "Text already in the field")
        case .selectionOnly: return String(localized: "Selected text only")
        case .empty: return String(localized: "An empty draft")
        }
    }
}

struct AppSettings: Codable {
    var engine = EngineKind.claudeCode
    /// ⌥⇧Space (HotKeyChoice.preferred). A new install starts on the first candidate its Mac leaves free.
    var summonHotKey = HotKeyChoice.preferred
    var panelPosition = PanelPosition.nearCursor
    var prefill = Prefill.fieldText
    var restoreClipboard = true
    var keepHistory = true
    var voiceRules: [VoiceRule] = [
        VoiceRule(text: "Never use em dashes"),
        VoiceRule(text: "No corporate filler (\"hope this finds you well\")"),
        VoiceRule(text: "Keep each language as I wrote it unless a preset translates"),
        VoiceRule(text: "Spell these names exactly: [names, product terms]", enabled: false),
    ]
    var defaultTakes = 3
    var defaultModel = Models.sonnet
    var defaultEffort = "low"
    /// Hotkey to first streamed words, for the Engine tab.
    var lastFirstTextMs: Int?
    /// The user has read what Takes reads and where it sends it (setup step).
    var privacyAccepted = false
    /// Local engine: an OpenAI-compatible server on this Mac, and the model every preset runs on with it.
    var localBaseURL = LocalServerKind.ollama.defaultBaseURL
    var localModel = ""
    /// Attach the clipboard as reply context when it looks like a message copied just now (ReplyContext.swift). Off by default.
    var clipboardContext = false
    /// Dictation language (a locale identifier); empty follows macOS.
    var dictationLanguage = ""
    /// The languages the user writes in (codes such as "he"); nil follows the Mac's list. Read it through `writingLanguages`.
    var languages: [String]?
    /// Where a new user is in onboarding. Settings saved before onboarding existed decode as finished.
    var onboarding = OnboardingProgress()
    /// Other provider (API key): which known provider ("openai", "gemini", …, or "custom"), its base URL and the one model every preset runs on.
    var providerID = "openai"
    var providerBaseURL = "https://api.openai.com/v1"
    var providerModel = ""
    /// Sign in with ChatGPT: the one model every preset runs on (a slug from OpenAI's model list).
    var chatGPTModel = ""
    /// English coach (EnglishCoach.swift). Off by default.
    var coach = CoachSettings()
    /// After a crash, the next launch offers to open a bug report with it (CrashReports). "Don't ask again" turns it off.
    var offerCrashReports = true
    /// The newest crash report the user was asked about, so each crash is offered once.
    var lastCrashReport: Date?
    /// Keep the menu-bar icon at the right end of the menu bar (MenuBarPin). Off by default.
    var pinMenuBarIcon = false
}

extension AppSettings {
    /// Tolerant decoding: settings saved by an older version (missing newer keys) keep their values
    /// instead of resetting everything to defaults, and so does a file with one value that can't be read.
    init(from decoder: Decoder) throws {
        let r = try LenientReader(decoder, keyedBy: CodingKeys.self)
        let d = AppSettings()
        // An engine this version doesn't know (saved by a newer one) falls back to the default.
        engine = r.value(EngineKind.self, .engine) ?? d.engine
        summonHotKey = r.value(KeyCombo.self, .summonHotKey) ?? d.summonHotKey
        panelPosition = r.value(PanelPosition.self, .panelPosition) ?? d.panelPosition
        prefill = r.value(Prefill.self, .prefill) ?? d.prefill
        restoreClipboard = r.value(Bool.self, .restoreClipboard) ?? d.restoreClipboard
        keepHistory = r.value(Bool.self, .keepHistory) ?? d.keepHistory
        voiceRules = r.list(VoiceRule.self, .voiceRules) ?? d.voiceRules
        defaultTakes = r.value(Int.self, .defaultTakes) ?? d.defaultTakes
        defaultModel = r.value(String.self, .defaultModel) ?? d.defaultModel
        defaultEffort = r.value(String.self, .defaultEffort) ?? d.defaultEffort
        lastFirstTextMs = r.value(Int.self, .lastFirstTextMs)
        privacyAccepted = r.value(Bool.self, .privacyAccepted) ?? d.privacyAccepted
        localBaseURL = r.value(String.self, .localBaseURL) ?? d.localBaseURL
        localModel = r.value(String.self, .localModel) ?? d.localModel
        clipboardContext = r.value(Bool.self, .clipboardContext) ?? d.clipboardContext
        dictationLanguage = r.value(String.self, .dictationLanguage) ?? d.dictationLanguage
        languages = r.list(String.self, .languages)
        onboarding = r.value(OnboardingProgress.self, .onboarding) ?? .existingUser
        providerID = r.value(String.self, .providerID) ?? d.providerID
        providerBaseURL = r.value(String.self, .providerBaseURL) ?? d.providerBaseURL
        providerModel = r.value(String.self, .providerModel) ?? d.providerModel
        chatGPTModel = r.value(String.self, .chatGPTModel) ?? d.chatGPTModel
        coach = r.value(CoachSettings.self, .coach) ?? d.coach
        offerCrashReports = r.value(Bool.self, .offerCrashReports) ?? d.offerCrashReports
        lastCrashReport = r.value(Date.self, .lastCrashReport)
        pinMenuBarIcon = r.value(Bool.self, .pinMenuBarIcon) ?? d.pinMenuBarIcon
    }
}

struct HistoryEntry: Codable, Identifiable {
    var id = UUID().uuidString
    var date = Date()
    var appName: String
    var presetName: String
    var draft: String
    var takes: [String]
    var pastedIndex: Int?
}

extension HistoryEntry {
    /// An entry needs its date and draft; anything else that can't be read falls back to a default, so one odd
    /// value doesn't cost the entry (and `StoredJSON` skips an entry that can't be read at all, not the whole file).
    init(from decoder: Decoder) throws {
        let r = try LenientReader(decoder, keyedBy: CodingKeys.self)
        id = r.value(String.self, .id) ?? UUID().uuidString
        date = try r.container.decode(Date.self, forKey: .date)
        appName = r.value(String.self, .appName) ?? ""
        presetName = r.value(String.self, .presetName) ?? ""
        draft = try r.container.decode(String.self, forKey: .draft)
        takes = r.list(String.self, .takes) ?? []
        pastedIndex = r.value(Int.self, .pastedIndex)
    }
}

// MARK: - Reading files without losing them

/// Counts the values a tolerant decode had to skip or reset, so the file they came from can be kept before it is rewritten.
final class DecodeProblems {
    var count = 0
}

extension CodingUserInfoKey {
    static let decodeProblems = CodingUserInfoKey(rawValue: "takes.decodeProblems")!
}

/// A list that keeps the entries it can read: one that doesn't decode is skipped, not the whole list.
struct LossyList<Element: Decodable>: Decodable {
    var elements: [Element] = []
    var skipped = 0

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                skipped += 1
                // A failed decode doesn't move on to the next entry; decoding nothing does.
                _ = try? container.decode(Skipped.self)
            }
        }
    }

    private struct Skipped: Decodable {
        init(from decoder: Decoder) throws {}
    }
}

/// Reads the keys of one JSON object leniently: a value that is missing or can't be read gives nil, for the caller to
/// replace with a default. A value that can't be read (not one that is missing) is counted in `DecodeProblems`.
struct LenientReader<Key: CodingKey> {
    let container: KeyedDecodingContainer<Key>
    private let problems: DecodeProblems?

    init(_ decoder: Decoder, keyedBy keys: Key.Type) throws {
        container = try decoder.container(keyedBy: keys)
        problems = decoder.userInfo[.decodeProblems] as? DecodeProblems
    }

    func value<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        do {
            return try container.decodeIfPresent(type, forKey: key)
        } catch {
            problems?.count += 1
            return nil
        }
    }

    /// A list that keeps the entries it can read.
    func list<T: Decodable>(_ type: T.Type, _ key: Key) -> [T]? {
        guard let list = value(LossyList<T>.self, key) else { return nil }
        problems?.count += list.skipped
        return list.elements
    }
}

/// A file Takes couldn't fully read. Its original bytes are kept in a copy beside it, made before anything can overwrite it.
struct SetAsideFile: Identifiable, Equatable {
    /// The file that couldn't be read ("presets.json").
    let name: String
    /// The copy's file name ("presets.unreadable-20261110-101530.json"); nil when no copy could be made.
    let copy: String?
    /// How many entries or values were skipped or reset; nil when nothing in the file could be read.
    let skipped: Int?
    var id: String { name }

    /// What happened, for the notice.
    var message: String {
        guard let copy else {
            return String(localized: "Takes couldn't read \(name) or keep a copy of it, so it won't change that file. Fix or remove it, then restart Takes.")
        }
        return skipped == nil
            ? String(localized: "Takes couldn't read \(name) and started over. Your original is kept as \(copy).")
            : String(localized: "Takes skipped part of \(name) that it couldn't read. Your original is kept as \(copy).")
    }
}

/// The copies kept of files Takes couldn't read: `presets.unreadable-20261110-101530.json` beside `presets.json`.
enum SetAside {
    /// How many copies of one file are kept. Older ones are deleted.
    static let keepCopies = 3
    /// History and coach notes hold the user's text, so their copies go after the 30 days those are kept for.
    static let textFiles = ["history.json", "coach.json"]
    static let textMaxAge: TimeInterval = 30 * 24 * 3600

    private static func stem(_ name: String) -> String { (name as NSString).deletingPathExtension }

    static func maxAge(for name: String) -> TimeInterval? { textFiles.contains(name) ? textMaxAge : nil }

    /// The copies of `name` in the folder, newest first.
    static func copies(of name: String, in folder: URL) -> [URL] {
        let prefix = "\(stem(name)).unreadable-"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let dated = names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".json") }.map { file -> (url: URL, date: Date) in
            let url = folder.appendingPathComponent(file)
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return (url, date)
        }
        return dated.sorted { ($0.date, $0.url.lastPathComponent) > ($1.date, $1.url.lastPathComponent) }.map(\.url)
    }

    /// Keeps the original bytes under a name that's free, and returns that name. A copy with the same bytes already
    /// there is reused, so a file that stays unreadable isn't copied again at every launch. Nil when nothing could be written.
    static func keep(_ data: Data, name: String, in folder: URL, now: Date = Date()) -> String? {
        defer { prune(name, in: folder, now: now) }
        if let same = copies(of: name, in: folder).first(where: { (try? Data(contentsOf: $0)) == data }) {
            return same.lastPathComponent
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = "\(stem(name)).unreadable-\(formatter.string(from: now))"
        for attempt in 1...50 {
            let file = attempt == 1 ? "\(base).json" : "\(base)-\(attempt).json"
            let url = folder.appendingPathComponent(file)
            // `withoutOverwriting` fails if the name is taken, so an earlier copy is never replaced.
            if (try? data.write(to: url, options: .withoutOverwriting)) != nil { return file }
        }
        return nil
    }

    /// Deletes copies beyond the newest few, and the ones older than the file's retention.
    static func prune(_ name: String, in folder: URL, now: Date = Date()) {
        guard !Store.readOnly else { return }
        for (index, url) in copies(of: name, in: folder).enumerated() {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now
            let expired = maxAge(for: name).map { now.timeIntervalSince(date) > $0 } ?? false
            if index >= keepCopies || expired { try? FileManager.default.removeItem(at: url) }
        }
    }
}

/// Reading a JSON file so that what can't be read is never lost: whatever fails to decode, the original bytes are
/// copied aside before the next save can overwrite them, and the rest of the file is kept.
enum StoredJSON {
    enum Contents {
        case missing, empty, unreadable
        case data(Data)
    }

    private struct NothingReadable: Error {}

    static func contents(of name: String, in folder: URL) -> Contents {
        let url = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url) else { return .unreadable }
        return data.allSatisfy({ [0x20, 0x09, 0x0A, 0x0D].contains($0) }) ? .empty : .data(data)
    }

    /// One value (settings). A file that can't be read as a whole gives nil.
    static func load<T: Decodable>(_ type: T.Type, _ name: String, in folder: URL, notices: inout [SetAsideFile]) -> T? {
        read(name, in: folder, notices: &notices) { decoder, data in (try decoder.decode(type, from: data), 0) }
    }

    /// A list (presets, history): an entry that can't be read is skipped and the others are kept.
    static func loadList<T: Decodable>(_ type: T.Type, _ name: String, in folder: URL, notices: inout [SetAsideFile]) -> [T]? {
        read(name, in: folder, notices: &notices) { decoder, data in
            let list = try decoder.decode(LossyList<T>.self, from: data)
            if list.elements.isEmpty, list.skipped > 0 { throw NothingReadable() }
            return (list.elements, list.skipped)
        }
    }

    private static func read<T>(
        _ name: String,
        in folder: URL,
        notices: inout [SetAsideFile],
        decode: (JSONDecoder, Data) throws -> (value: T, skipped: Int)
    ) -> T? {
        let data: Data
        switch contents(of: name, in: folder) {
        case .missing, .empty:
            return nil
        case .unreadable:
            // Something is there but can't be opened: leave it alone, and don't write over it either.
            if !Store.readOnly { notices.append(SetAsideFile(name: name, copy: nil, skipped: nil)) }
            return nil
        case .data(let bytes):
            data = bytes
        }
        let problems = DecodeProblems()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.userInfo[.decodeProblems] = problems
        do {
            let (value, skipped) = try decode(decoder, data)
            if skipped + problems.count > 0 { setAside(data, name, in: folder, skipped: skipped + problems.count, notices: &notices) }
            return value
        } catch {
            setAside(data, name, in: folder, skipped: nil, notices: &notices)
            return nil
        }
    }

    private static func setAside(_ data: Data, _ name: String, in folder: URL, skipped: Int?, notices: inout [SetAsideFile]) {
        // `--snapshot` renders write nothing.
        guard !Store.readOnly else { return }
        notices.append(SetAsideFile(name: name, copy: SetAside.keep(data, name: name, in: folder), skipped: skipped))
    }
}

// MARK: - Store

/// Presets, settings and history, saved as JSON in ~/Library/Application Support/Takes.
final class Store: ObservableObject {
    static let shared = Store()

    @Published var presets: [Preset] { didSet { save(presets, "presets.json") } }
    @Published var settings: AppSettings { didSet { save(settings, "settings.json") } }
    @Published var history: [HistoryEntry] { didSet { save(history, "history.json") } }
    /// There was no settings file when Takes started: the very first launch, before onboarding has saved anything.
    let isNewInstall: Bool
    /// Files that couldn't be fully read at launch. Each has a copy of its original bytes beside it, so nothing the
    /// user had is lost when the file is saved again. The Settings tabs show these until they are dismissed.
    @Published private(set) var setAside: [SetAsideFile] = []

    static let directory: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Takes", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Where this store's files are. `Store.directory`, except in tests.
    private let folder: URL
    /// Files that couldn't be read or copied: they aren't saved over, so the user's original stays as it is.
    private var unsafeToWrite: Set<String> = []

    private convenience init() { self.init(folder: Store.directory) }

    init(folder: URL) {
        self.folder = folder
        let existingUser = FileManager.default.fileExists(atPath: folder.appendingPathComponent("settings.json").path)
        isNewInstall = !existingUser
        var notices: [SetAsideFile] = []
        let savedPresets = StoredJSON.loadList(Preset.self, "presets.json", in: folder, notices: &notices)
        presets = Proofread.upgraded(savedPresets ?? PresetGallery.initialPresets(existingUser: existingUser))
        settings = StoredJSON.load(AppSettings.self, "settings.json", in: folder, notices: &notices) ?? AppSettings()
        history = StoredJSON.loadList(HistoryEntry.self, "history.json", in: folder, notices: &notices) ?? []
        setAside = notices
        unsafeToWrite = Set(notices.filter { $0.copy == nil }.map(\.name))
        for name in ["presets.json", "settings.json", "history.json", "coach.json"] { SetAside.prune(name, in: folder) }
        pruneHistory()
        // Saved right away so the starters keep their ids across launches.
        if !FileManager.default.fileExists(atPath: folder.appendingPathComponent("presets.json").path) { save(presets, "presets.json") }
    }

    func preset(id: String?) -> Preset? { presets.first { $0.id == id } }

    func index(of id: String) -> Int? { presets.firstIndex { $0.id == id } }

    /// The preset auto-picked for an app, if any preset lists it.
    func preset(forApp bundleID: String?) -> Preset? {
        guard let bundleID else { return nil }
        return presets.first { $0.apps.contains { $0.bundleID == bundleID } }
    }

    func newPreset() -> Preset {
        Preset(name: String(localized: "New preset"), colorHex: Preset.colors[presets.count % Preset.colors.count],
               instruction: "Rewrite my draft so it is clear and natural.",
               takes: settings.defaultTakes, model: settings.defaultModel, effort: settings.defaultEffort)
    }

    func addExample(_ text: String, toPreset id: String) {
        guard let i = index(of: id) else { return }
        presets[i].examples.removeAll { $0 == text }
        presets[i].examples.insert(text, at: 0)
        presets[i].examples = Array(presets[i].examples.prefix(Preset.maxExamples))
    }

    func record(_ entry: HistoryEntry) {
        guard settings.keepHistory else { return }
        history.insert(entry, at: 0)
        pruneHistory()
    }

    func markPasted(entryID: String, index: Int) {
        guard let i = history.firstIndex(where: { $0.id == entryID }) else { return }
        history[i].pastedIndex = index
    }

    private func pruneHistory() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        let kept = Array(history.filter { $0.date > cutoff }.prefix(500))
        if kept.count != history.count { history = kept }
    }

    /// `--snapshot` renders change settings to show other states; they must not reach the real files.
    static var readOnly = false

    private func save<T: Encodable>(_ value: T, _ name: String) {
        guard !Store.readOnly, !unsafeToWrite.contains(name) else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: folder.appendingPathComponent(name), options: .atomic)
    }

    /// Deletes every stored copy of draft and take text that history keeps: the list, `history.json` and the copies
    /// Takes set aside when it couldn't read that file. False when a file couldn't be removed.
    @discardableResult
    func clearHistory() -> Bool {
        history = []
        guard !Store.readOnly else { return true }
        var removedAll = true
        let files = [folder.appendingPathComponent("history.json")] + SetAside.copies(of: "history.json", in: folder)
        for url in files where FileManager.default.fileExists(atPath: url.path) {
            do { try FileManager.default.removeItem(at: url) } catch { removedAll = false }
        }
        if removedAll {
            setAside.removeAll { $0.name == "history.json" }
            unsafeToWrite.remove("history.json")
        }
        return removedAll
    }

    /// A copy of an unreadable history file is on disk: it holds drafts and takes, so Clear History removes it too.
    var keepsHistoryCopy: Bool { !SetAside.copies(of: "history.json", in: folder).isEmpty }

    /// Another file Takes set aside after launch (the coach's), for the same notice.
    func noteSetAside(_ file: SetAsideFile) {
        setAside.removeAll { $0.name == file.name }
        setAside.append(file)
    }

    func dismissSetAside() { setAside = [] }

    /// Shows the copies in Finder (the folder, when no copy could be made).
    func revealSetAside() {
        let copies = setAside.compactMap(\.copy).map { folder.appendingPathComponent($0) }
        NSWorkspace.shared.activateFileViewerSelecting(copies.isEmpty ? [folder] : copies)
    }

    /// Tells the user, in an alert, about files set aside at launch, and then drops the notice. Call it once after
    /// launch; until then the Presets and History tabs show the same notice.
    @MainActor
    func announceSetAside() {
        guard !setAside.isEmpty, !Store.readOnly else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Takes couldn't read some of its files")
        alert.informativeText = setAside.map(\.message).joined(separator: "\n\n")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Show in Finder"))
        if alert.runModal() == .alertSecondButtonReturn { revealSetAside() }
        dismissSetAside()
    }

    static let defaultPresets: [Preset] = [
        Preset(name: String(localized: "Slack · clear & friendly"), colorHex: "#2F55E0",
               instruction: "Rewrite my draft as a message to teammates. Clear first, friendly second. Lead with the answer.",
               dos: ["One ask per sentence", "Keep EOD, QA, PR"],
               avoid: ["Exclamation marks", "\"Just\", \"quick question\"", "Emoji unless I used them"],
               apps: [AppRef(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")]),
        Preset(name: "Proofread only, keep my words", colorHex: "#1D6B4F",
               instruction: "Fix spelling, grammar and punctuation only. Keep my words, tone and structure.",
               avoid: ["Rewording anything that is already correct"], takes: 1),
        Preset(name: String(localized: "Shorter"), colorHex: "#8A4B08",
               instruction: "Say the same thing in as few words as possible without dropping any ask or fact.",
               length: .shorter),
        Preset(name: String(localized: "Formal email"), colorHex: "#7A3FD1",
               instruction: "Rewrite my draft as a polite, professional email body. No subject line, no signature.",
               dos: ["Short paragraphs"], length: .any,
               apps: [AppRef(bundleID: "com.apple.mail", name: "Mail")]),
        Preset(name: String(localized: "Push back politely"), colorHex: "#B42318",
               instruction: "Say no or push back on the request, politely and firmly. Keep the relationship warm. Offer an alternative only if my draft suggests one.",
               avoid: ["Over-apologising", "Vague maybes"]),
        Preset(name: String(localized: "Hebrew → English, keep my tone"), colorHex: "#0E6E8C",
               instruction: "Translate my Hebrew draft into natural English, the way a native speaker would write it. Keep my tone and register.",
               language: .english, length: .any),
        Preset(name: String(localized: "English → עברית"), colorHex: "#0E6E8C",
               instruction: "Translate my English draft into natural Hebrew, the way Israelis write at work. Keep my tone and register.",
               language: .hebrew, length: .any),
    ]
}
