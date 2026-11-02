import AppKit
import Carbon
import Combine

// MARK: - Models

struct KeyCombo: Codable, Hashable {
    var keyCode: UInt32
    /// Carbon modifier mask (controlKey, optionKey, shiftKey, cmdKey).
    var modifiers: UInt32
    var display: String
}

struct AppRef: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

enum ReplyLanguage: String, Codable, CaseIterable, Identifiable {
    case sameAsDraft, english, hebrew
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sameAsDraft: return "Same as draft"
        case .english: return "English"
        case .hebrew: return "עברית"
        }
    }
}

enum TakeLength: String, Codable, CaseIterable, Identifiable {
    case sameOrShorter, shorter, any, longer
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sameOrShorter: return "Same or shorter"
        case .shorter: return "Shorter"
        case .any: return "Any length"
        case .longer: return "Longer"
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
    static let colors = ["#2F55E0", "#1D6B4F", "#8A4B08", "#7A3FD1", "#B42318", "#0E6E8C", "#55555E"]

    var summary: String {
        "\(takes) take\(takes == 1 ? "" : "s") · \(Models.label(model)) · \(effort.capitalized) effort · \(length.label.lowercased())"
    }
}

extension Preset {
    /// Tolerant decoding: presets saved by an older version (missing newer keys) still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preset(name: "", colorHex: Preset.colors[0], instruction: "")
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? d.id
        name = try c.decode(String.self, forKey: .name)
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? d.colorHex
        hotKey = try c.decodeIfPresent(KeyCombo.self, forKey: .hotKey)
        instruction = try c.decode(String.self, forKey: .instruction)
        dos = try c.decodeIfPresent([String].self, forKey: .dos) ?? d.dos
        avoid = try c.decodeIfPresent([String].self, forKey: .avoid) ?? d.avoid
        examples = try c.decodeIfPresent([String].self, forKey: .examples) ?? d.examples
        language = try c.decodeIfPresent(ReplyLanguage.self, forKey: .language) ?? d.language
        length = try c.decodeIfPresent(TakeLength.self, forKey: .length) ?? d.length
        apps = try c.decodeIfPresent([AppRef].self, forKey: .apps) ?? d.apps
        takes = try c.decodeIfPresent(Int.self, forKey: .takes) ?? d.takes
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        effort = try c.decodeIfPresent(String.self, forKey: .effort) ?? d.effort
        showTone = try c.decodeIfPresent(Bool.self, forKey: .showTone) ?? d.showTone
    }
}

struct VoiceRule: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var text: String
    var enabled = true
}

enum EngineKind: String, Codable { case claudeCode, apiKey, local }
/// Where the panel opens. Whichever is picked, the panel moves aside rather than cover the text box.
enum PanelPosition: String, Codable, CaseIterable, Identifiable {
    case nearCursor, topLeft, topCenter, topRight, center, bottomLeft, bottomCenter, bottomRight
    var id: String { rawValue }
    var label: String {
        switch self {
        case .nearCursor: "Next to the text box"
        case .topLeft: "Top left"
        case .topCenter: "Top center"
        case .topRight: "Top right"
        case .center: "Center of the screen"
        case .bottomLeft: "Bottom left"
        case .bottomCenter: "Bottom center"
        case .bottomRight: "Bottom right"
        }
    }
}
enum Prefill: String, Codable, CaseIterable, Identifiable {
    case fieldText, selectionOnly, empty
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fieldText: return "Text already in the field"
        case .selectionOnly: return "Selected text only"
        case .empty: return "An empty draft"
        }
    }
}

struct AppSettings: Codable {
    var engine = EngineKind.claudeCode
    var summonHotKey = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), display: "⌃⌥Space")
    var panelPosition = PanelPosition.nearCursor
    var prefill = Prefill.fieldText
    var restoreClipboard = true
    var keepHistory = true
    var voiceRules: [VoiceRule] = [
        VoiceRule(text: "Never use em dashes"),
        VoiceRule(text: "No corporate filler (\"hope this finds you well\")"),
        VoiceRule(text: "Keep Hebrew and English as I wrote them unless a preset translates"),
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
}

extension AppSettings {
    /// Tolerant decoding: settings saved by an older version (missing newer keys) keep their values
    /// instead of resetting everything to defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        // An engine this version doesn't know (saved by a newer one) falls back to the default.
        engine = (try? c.decodeIfPresent(EngineKind.self, forKey: .engine)) ?? d.engine
        summonHotKey = try c.decodeIfPresent(KeyCombo.self, forKey: .summonHotKey) ?? d.summonHotKey
        panelPosition = try c.decodeIfPresent(PanelPosition.self, forKey: .panelPosition) ?? d.panelPosition
        prefill = try c.decodeIfPresent(Prefill.self, forKey: .prefill) ?? d.prefill
        restoreClipboard = try c.decodeIfPresent(Bool.self, forKey: .restoreClipboard) ?? d.restoreClipboard
        keepHistory = try c.decodeIfPresent(Bool.self, forKey: .keepHistory) ?? d.keepHistory
        voiceRules = try c.decodeIfPresent([VoiceRule].self, forKey: .voiceRules) ?? d.voiceRules
        defaultTakes = try c.decodeIfPresent(Int.self, forKey: .defaultTakes) ?? d.defaultTakes
        defaultModel = try c.decodeIfPresent(String.self, forKey: .defaultModel) ?? d.defaultModel
        defaultEffort = try c.decodeIfPresent(String.self, forKey: .defaultEffort) ?? d.defaultEffort
        lastFirstTextMs = try c.decodeIfPresent(Int.self, forKey: .lastFirstTextMs)
        privacyAccepted = try c.decodeIfPresent(Bool.self, forKey: .privacyAccepted) ?? d.privacyAccepted
        localBaseURL = try c.decodeIfPresent(String.self, forKey: .localBaseURL) ?? d.localBaseURL
        localModel = try c.decodeIfPresent(String.self, forKey: .localModel) ?? d.localModel
        clipboardContext = try c.decodeIfPresent(Bool.self, forKey: .clipboardContext) ?? d.clipboardContext
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

// MARK: - Store

/// Presets, settings and history, saved as JSON in ~/Library/Application Support/Takes.
final class Store: ObservableObject {
    static let shared = Store()

    @Published var presets: [Preset] { didSet { save(presets, "presets.json") } }
    @Published var settings: AppSettings { didSet { save(settings, "settings.json") } }
    @Published var history: [HistoryEntry] { didSet { save(history, "history.json") } }

    static let directory: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Takes", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private init() {
        let existingUser = FileManager.default.fileExists(atPath: Store.directory.appendingPathComponent("settings.json").path)
        let presetsFile = Store.directory.appendingPathComponent("presets.json")
        presets = Proofread.upgraded(Store.load("presets.json") ?? PresetGallery.initialPresets(existingUser: existingUser))
        settings = Store.load("settings.json") ?? AppSettings()
        history = Store.load("history.json") ?? []
        pruneHistory()
        // Saved right away so the starters keep their ids across launches.
        if !FileManager.default.fileExists(atPath: presetsFile.path) { save(presets, "presets.json") }
    }

    func preset(id: String?) -> Preset? { presets.first { $0.id == id } }

    func index(of id: String) -> Int? { presets.firstIndex { $0.id == id } }

    /// The preset auto-picked for an app, if any preset lists it.
    func preset(forApp bundleID: String?) -> Preset? {
        guard let bundleID else { return nil }
        return presets.first { $0.apps.contains { $0.bundleID == bundleID } }
    }

    func newPreset() -> Preset {
        Preset(name: "New preset", colorHex: Preset.colors[presets.count % Preset.colors.count],
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
        guard !Store.readOnly else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: Store.directory.appendingPathComponent(name), options: .atomic)
    }

    private static func load<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    static let defaultPresets: [Preset] = [
        Preset(name: "Slack · clear & friendly", colorHex: "#2F55E0",
               instruction: "Rewrite my draft as a message to teammates. Clear first, friendly second. Lead with the answer.",
               dos: ["One ask per sentence", "Keep EOD, QA, PR"],
               avoid: ["Exclamation marks", "\"Just\", \"quick question\"", "Emoji unless I used them"],
               apps: [AppRef(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")]),
        Preset(name: "Proofread only, keep my words", colorHex: "#1D6B4F",
               instruction: "Fix spelling, grammar and punctuation only. Keep my words, tone and structure.",
               avoid: ["Rewording anything that is already correct"], takes: 1),
        Preset(name: "Shorter", colorHex: "#8A4B08",
               instruction: "Say the same thing in as few words as possible without dropping any ask or fact.",
               length: .shorter),
        Preset(name: "Formal email", colorHex: "#7A3FD1",
               instruction: "Rewrite my draft as a polite, professional email body. No subject line, no signature.",
               dos: ["Short paragraphs"], length: .any,
               apps: [AppRef(bundleID: "com.apple.mail", name: "Mail")]),
        Preset(name: "Push back politely", colorHex: "#B42318",
               instruction: "Say no or push back on the request, politely and firmly. Keep the relationship warm. Offer an alternative only if my draft suggests one.",
               avoid: ["Over-apologising", "Vague maybes"]),
        Preset(name: "Hebrew → English, keep my tone", colorHex: "#0E6E8C",
               instruction: "Translate my Hebrew draft into natural English, the way a native speaker would write it. Keep my tone and register.",
               language: .english, length: .any),
        Preset(name: "English → עברית", colorHex: "#0E6E8C",
               instruction: "Translate my English draft into natural Hebrew, the way Israelis write at work. Keep my tone and register.",
               language: .hebrew, length: .any),
    ]
}
