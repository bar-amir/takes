import AppKit
import SwiftUI

/// The languages someone writes in. They start as the Mac's own list (System Settings › General › Language & Region),
/// read without asking for location, and can be changed in onboarding and Settings › Voice.
enum Languages {
    /// Languages kept from the Mac's list: enough for "Translate to …" presets without crowding the gallery.
    static let maxFromSystem = 3

    /// Language codes ("en", "he") from the Mac's preferred languages, in order, without duplicates.
    static func fromSystem(_ preferred: [String] = Locale.preferredLanguages) -> [String] {
        var codes: [String] = []
        for identifier in preferred {
            guard let code = Locale(identifier: identifier).language.languageCode?.identifier, !codes.contains(code) else { continue }
            codes.append(code)
            if codes.count == maxFromSystem { break }
        }
        return codes.isEmpty ? ["en"] : codes
    }

    /// The name people recognise their language by, in that language ("עברית", "Español").
    static func nativeName(_ code: String) -> String {
        guard let name = Locale(identifier: code).localizedString(forLanguageCode: code) else { return code }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// The English name, for prompts and preset names ("Hebrew").
    static func englishName(_ code: String) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }

    /// Offered by "Add language" and "Other language": widely written languages, sorted by English name.
    static let common: [String] = ["ar", "zh", "cs", "da", "nl", "en", "fi", "fr", "de", "el", "he", "hi", "hu", "id", "it",
                                   "ja", "ko", "nb", "fa", "pl", "pt", "ro", "ru", "es", "sv", "th", "tr", "uk", "vi"]
        .sorted { englishName($0) < englishName($1) }
}

/// What language a preset writes in: the draft's own, or a fixed one (an ISO 639 code such as "he").
enum ReplyLanguage: Hashable, Identifiable {
    case sameAsDraft
    case language(String)

    static var english: ReplyLanguage { .language("en") }
    static var hebrew: ReplyLanguage { .language("he") }

    var id: String { rawValue }

    var rawValue: String {
        switch self {
        case .sameAsDraft: return "sameAsDraft"
        case .language(let code): return code
        }
    }

    /// Also reads the names saved before any language could be picked ("english", "hebrew").
    init(rawValue: String) {
        switch rawValue {
        case "sameAsDraft", "": self = .sameAsDraft
        case "english": self = .english
        case "hebrew": self = .hebrew
        default: self = .language(rawValue)
        }
    }

    var label: String {
        switch self {
        case .sameAsDraft: return "Same as draft"
        case .language(let code): return Languages.nativeName(code)
        }
    }
}

extension ReplyLanguage: Codable {
    init(from decoder: Decoder) throws { self.init(rawValue: try decoder.singleValueContainer().decode(String.self)) }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension AppSettings {
    /// The languages someone writes in: the ones they chose, or the Mac's.
    var writingLanguages: [String] { languages?.isEmpty == false ? languages! : Languages.fromSystem() }
}

// MARK: - Views

/// The languages someone writes in, as removable chips with "+ Add language". At least one always stays.
struct LanguageChips: View {
    @Binding var languages: [String]

    var body: some View {
        FlowLayout(spacing: Spacing.item) {
            ForEach(languages, id: \.self) { code in
                HStack(spacing: 6) {
                    Text(Languages.nativeName(code)).font(.system(size: 13)).foregroundStyle(Theme.text)
                    if languages.count > 1 {
                        Button { languages.removeAll { $0 == code } } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(Languages.englishName(code))")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.controlBorder))
            }
            Button("+ Add language") {
                LanguageMenu.show(excluding: languages) { languages.append($0) }
            }
            .buttonStyle(DashedButtonStyle())
        }
    }
}

/// Reply language in the preset editor: the draft's own or one of your languages, plus any other from a menu.
struct ReplyLanguagePicker: View {
    @Binding var selection: ReplyLanguage
    var writingLanguages: [String]

    private var options: [(value: ReplyLanguage, title: String)] {
        var values: [ReplyLanguage] = [.sameAsDraft] + writingLanguages.map { .language($0) }
        if !values.contains(selection) { values.append(selection) }
        return values.map { ($0, $0.label) }
    }

    var body: some View {
        HStack(spacing: Spacing.item) {
            ChoiceSegments(options: options, selection: $selection)
            Button("Other…") {
                let shown = options.compactMap { if case .language(let code) = $0.value { return code } else { return nil } }
                LanguageMenu.show(excluding: shown) { selection = .language($0) }
            }
            .buttonStyle(SecondaryButtonStyle(height: 32))
            .fixedSize()
            .accessibilityLabel("Other reply language")
        }
    }
}

enum LanguageMenu {
    /// A native menu of `Languages.common`, each in its own name with the English one after it.
    static func show(excluding: [String], pick: @escaping (String) -> Void) {
        let menu = NSMenu()
        for code in Languages.common where !excluding.contains(code) {
            let native = Languages.nativeName(code), english = Languages.englishName(code)
            menu.addItem(ClosureMenuItem(title: native == english ? english : "\(native) · \(english)") { pick(code) })
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}
