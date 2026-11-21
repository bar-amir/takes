import AppKit

/// Ready-made presets. Adding one gives the user their own copy (a new id) to edit; the template
/// itself never changes. Fresh installs start with `starters`.
enum PresetGallery {
    static var all: [Preset] {
        [fitted(slack), .proofread, fitted(email), fitted(promptForAI), fitted(casual), shorter, friendlier, direct, professional,
         explainSimply, summarize, statusUpdate, decline]
            + translations(for: Store.shared.settings.writingLanguages)
    }

    /// Installed on a fresh setup. Existing users keep their own presets. People who write in more than one
    /// language also start with "Translate to …" for each of them.
    static var starters: [Preset] { starters(languages: Store.shared.settings.writingLanguages) }

    /// The starters are tied to the common apps on this Mac (`installed`), and "Prompt for AI" and "Casual message"
    /// are added only when one of the apps they're for is installed.
    static func starters(languages: [String], installed: (String) -> Bool = InstalledApps.contains) -> [Preset] {
        let forApps = [promptForAI, casual].map { fitted($0, installed: installed) }
            .filter { $0.apps.contains { !$0.isSite && !alwaysInstalled.contains($0.bundleID) } }
        // A rewriting preset comes first: it's the default when no preset is picked for the app.
        return [fitted(slack, installed: installed), .proofread, fitted(email, installed: installed)] + forApps
            + [shorter, friendlier, direct, decline] + (languages.count > 1 ? translations(for: languages) : [])
    }

    /// A template with the apps on this Mac it's picked in. Slack and Mail stay on their presets as before; Teams and
    /// other email apps join them when installed, and the chat preset is called "Work chat" once it covers Teams too.
    /// "Prompt for AI" and "Casual message" keep only the apps that are installed. Websites are always kept.
    static func fitted(_ template: Preset, installed: (String) -> Bool = InstalledApps.contains) -> Preset {
        var preset = template
        switch template.id {
        case slack.id:
            let teamsApps = teams.filter { installed($0.bundleID) }
            if !teamsApps.isEmpty { preset.name = String(localized: "Work chat") }
            preset.apps = template.apps.filter { !$0.isSite } + teamsApps + template.apps.filter { $0.isSite }
        case email.id:
            preset.apps = template.apps.filter { !$0.isSite } + emailApps.filter { installed($0.bundleID) }
                + template.apps.filter { $0.isSite }
        case promptForAI.id, casual.id:
            preset.apps = template.apps.filter { $0.isSite || installed($0.bundleID) }
        default:
            break
        }
        return preset
    }

    // MARK: Common apps

    /// Microsoft Teams, new and classic: picked by the Slack preset too.
    static let teams = [
        AppRef(bundleID: "com.microsoft.teams2", name: "Microsoft Teams"),
        AppRef(bundleID: "com.microsoft.teams", name: "Microsoft Teams"),
    ]

    /// Email apps picked by "Polish email" besides Mail.
    static let emailApps = [
        AppRef(bundleID: "com.microsoft.Outlook", name: "Outlook"),
        AppRef(bundleID: "com.readdle.SparkDesktop", name: "Spark"),
        AppRef(bundleID: "com.readdle.smartemail-Mac", name: "Spark Classic"),
        AppRef(bundleID: "com.superhuman.electron", name: "Superhuman"),
    ]

    /// Apps every Mac has. They're tied to a preset that's added, but don't add one on their own: everyone would get it.
    static let alwaysInstalled: Set<String> = ["com.apple.MobileSMS", "com.apple.mail"]

    /// One "Translate to …" per language the user writes in.
    static func translations(for languages: [String]) -> [Preset] { languages.map(translate(to:)) }

    /// The panel's picker ends with "Browse more presets" while the user has fewer presets than this.
    static let browseRowLimit = 8

    /// One line for the gallery list.
    static func blurb(for preset: Preset) -> String {
        let id = preset.galleryID ?? preset.id
        if id.hasPrefix("gallery.translate"), case .language(let code) = preset.language {
            return String(localized: "Natural \(Languages.displayName(code)) from any language.")
        }
        return blurbs[id] ?? ""
    }

    // MARK: Adding

    /// The user's own copy of a template: a new id, no hotkey, linked back so the gallery shows it as added.
    static func copy(of template: Preset) -> Preset {
        var copy = template
        copy.id = UUID().uuidString
        copy.galleryID = template.id
        copy.hotKey = nil
        return copy
    }

    /// Added before, or the user already has a preset with the same name (for example from an older version).
    static func isAdded(_ template: Preset, in presets: [Preset]) -> Bool {
        presets.contains { $0.galleryID == template.id || $0.name.caseInsensitiveCompare(template.name) == .orderedSame }
    }

    /// Appends copies of the templates not added yet, in gallery order. Returns the new copies.
    @discardableResult
    static func add(_ templates: [Preset], to presets: inout [Preset]) -> [Preset] {
        var added: [Preset] = []
        for template in templates where !isAdded(template, in: presets) {
            let copy = copy(of: template)
            presets.append(copy)
            added.append(copy)
        }
        return added
    }

    /// The presets a Store starts with when there's no presets file. Someone who used an older version
    /// (their settings file exists) gets the presets they were already seeing, so nothing changes under them.
    /// Runs inside `Store.init`, before settings load, so it reads the Mac's languages rather than `Store.shared`.
    static func initialPresets(existingUser: Bool, languages: [String] = Languages.fromSystem()) -> [Preset] {
        existingUser ? Store.defaultPresets : starters(languages: languages).map(copy(of:))
    }

    /// What the gallery's button adds: the checked presets not added yet, or else the highlighted one.
    static func toAdd(_ templates: [Preset], checked: Set<String>, highlightedID: String, isAdded: (Preset) -> Bool) -> [Preset] {
        let picked = templates.filter { checked.contains($0.id) && !isAdded($0) }
        if !picked.isEmpty { return picked }
        if let highlighted = templates.first(where: { $0.id == highlightedID }), !isAdded(highlighted) { return [highlighted] }
        return []
    }

    /// The gallery button's title. It names a preset only when that's the highlighted one, whose preview is on
    /// screen; checked presets elsewhere in the list are counted, so the button never names one you can't see.
    static func addTitle(_ items: [Preset], highlightedID: String) -> String {
        if items.count > 1 { return String(localized: "Add \(items.count) presets") }
        guard let one = items.first else { return String(localized: "Added") }
        if one.id == highlightedID { return String(localized: "Add “\(one.name)”") }
        return String(localized: "Add 1 checked preset")
    }

    /// A preset just made with "New" and not edited yet: the moment to suggest the gallery instead.
    static func isUntouchedNew(_ preset: Preset, blank: Preset) -> Bool {
        preset.name == blank.name && preset.instruction == blank.instruction && preset.dos.isEmpty
            && preset.avoid.isEmpty && preset.examples.isEmpty && preset.galleryID == nil
    }

    // MARK: Templates

    static let slack = Preset(
        id: "gallery.slack", name: String(localized: "Slack message"), colorHex: "#2F55E0",
        instruction: "Rewrite my draft as a chat message to teammates. Lead with the answer or the ask, then only the context they need. Warm but brief, the way a respected colleague writes in Slack.",
        dos: ["Answer or ask in the first sentence", "One ask per sentence", "Keep shorthand like EOD, QA, PR"],
        avoid: ["Exclamation marks", "\"Just\", \"quick question\", \"hope you're well\"", "Emoji unless I used them", "Bullets for a short message"],
        apps: [
            AppRef(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"),
            .site("app.slack.com", name: "Slack web"),
            .site("teams.microsoft.com", "teams.cloud.microsoft", "teams.live.com", name: "Teams web"),
        ])

    static let email = Preset(
        id: "gallery.email", name: String(localized: "Polish email"), colorHex: "#7A3FD1",
        instruction: "Rewrite my draft as a clear, professional email body. Keep my points; fix the order and flow so the reader knows what I need by the end of the first paragraph. Keep any greeting or sign-off I wrote. No subject line, no signature.",
        dos: ["Short paragraphs, one idea each", "The ask or decision near the top", "Concrete dates and owners"],
        avoid: ["\"I hope this email finds you well\"", "Stacked apologies", "Facts or promises I didn't write"],
        length: .any,
        apps: [
            AppRef(bundleID: "com.apple.mail", name: "Mail"),
            .site("mail.google.com", name: "Gmail"),
            .site("outlook.office.com", "outlook.cloud.microsoft", "outlook.office365.com", "outlook.live.com", name: "Outlook web"),
        ])

    static let shorter = Preset(
        id: "gallery.shorter", name: String(localized: "Shorter"), colorHex: "#8A4B08",
        instruction: "Say the same thing in as few words as possible. Keep every ask, fact, number, name and date.",
        dos: ["Cut filler, hedges and repetition", "Merge points that say the same thing"],
        avoid: ["Dropping any ask or detail", "Clipped fragments that read as rude"],
        length: .shorter)

    static let friendlier = Preset(
        id: "gallery.friendlier", name: String(localized: "Friendlier"), colorHex: "#1D6B4F",
        instruction: "Make my draft warmer and easier to receive without changing what it says. Sound like a kind colleague, not a greeting card.",
        dos: ["Acknowledge the other person where it fits", "Soften blunt phrasing", "Keep every ask and fact"],
        avoid: ["Gushing (\"amazing\", \"so excited\")", "Exclamation marks in every sentence", "Emoji unless I used them", "Burying the point"])

    static let direct = Preset(
        id: "gallery.direct", name: String(localized: "More direct"), colorHex: "#B42318",
        instruction: "Make my draft more direct and confident. Put the point and the ask first, in plain words. Stay polite.",
        dos: ["Lead with the point", "Turn hedges into clear statements", "Name the date or owner if I gave one"],
        avoid: ["\"Just\", \"I think\", \"sort of\", \"maybe\"", "Apologising for asking", "Exclamation marks", "Sounding cold or curt"])

    static let professional = Preset(
        id: "gallery.professional", name: String(localized: "Professional"), colorHex: "#55555E",
        instruction: "Rewrite my draft for a client, leadership or someone I don't know well: polished and confident, still plain and human. Keep my meaning exactly.",
        dos: ["Complete sentences", "Calm, neutral tone"],
        avoid: ["Slang and in-jokes", "Jargon (\"synergy\", \"circle back\", \"leverage\")", "Stiff, legal-sounding phrasing"])

    static let explainSimply = Preset(
        id: "gallery.explain", name: String(localized: "Explain simply"), colorHex: "#0E6E8C",
        instruction: "Rewrite my draft so someone outside my field understands it on the first read. Swap jargon for plain words. Add a short example only if it makes the point clearer.",
        dos: ["Short sentences", "Explain a term the first time if it has to stay", "Keep the facts accurate"],
        avoid: ["Unexplained acronyms", "Talking down to the reader", "Claims I didn't make"],
        length: .any)

    static let summarize = Preset(
        id: "gallery.summarize", name: String(localized: "Summarize"), colorHex: "#2F55E0",
        instruction: "Turn my draft (notes, a long update or text I pasted) into a short summary I can post as a reply: the bottom line first, then the key points, decisions and open asks.",
        dos: ["Bottom line in the first sentence", "Up to 3 short bullets if there are several points", "Names, numbers and dates exactly as written"],
        avoid: ["Opinions or conclusions that aren't in the text", "Restating everything", "Headings"],
        length: .shorter)

    static let statusUpdate = Preset(
        id: "gallery.status", name: String(localized: "Status update"), colorHex: "#1D6B4F",
        instruction: "Turn my notes into a short status update for the team: what's done, what's next and what's blocked, with owners and dates where I gave them.",
        dos: ["Done, next, blocked, in that order", "Skip a part that has nothing in it"],
        avoid: ["Padding a short update", "Progress, owners or dates I didn't mention"],
        length: .any)

    static let decline = Preset(
        id: "gallery.decline", name: String(localized: "Decline politely"), colorHex: "#B42318",
        instruction: "Say no to the request in my draft, politely and clearly, and keep the relationship warm. Give a reason only if my draft has one. Offer an alternative only if I suggested one.",
        dos: ["Make the no unmistakable", "Thank them once, briefly"],
        avoid: ["Over-apologising", "Vague maybes that invite a follow-up", "Reasons or alternatives I didn't give"])

    static let promptForAI = Preset(
        id: "gallery.prompt", name: String(localized: "Prompt for AI"), colorHex: "#55555E",
        instruction: "Rewrite my draft as a clear prompt for an AI assistant: what I want first, then the context it needs, any constraints, and the form of answer I want. Keep my language and my meaning. Write the prompt only; don't answer it.",
        dos: ["The goal in the first sentence", "Context, limits and the answer's format, if I gave them", "Short lines or bullets for a long ask"],
        avoid: ["Answering the prompt", "Requirements or facts I didn't write", "Openers like \"You are an expert\"", "Politeness filler"],
        length: .any,
        apps: [
            AppRef(bundleID: "com.openai.chat", name: "ChatGPT"),
            AppRef(bundleID: "com.anthropic.claudefordesktop", name: "Claude"),
            AppRef(bundleID: "ai.perplexity.macv3", name: "Perplexity"),
            AppRef(bundleID: "ai.perplexity.mac", name: "Perplexity"),
            .site("chatgpt.com", "chat.openai.com", name: "ChatGPT web"),
            .site("claude.ai", name: "Claude web"),
            .site("perplexity.ai", name: "Perplexity web"),
            .site("gemini.google.com", name: "Gemini"),
        ],
        showTone: false)

    static let casual = Preset(
        id: "gallery.casual", name: String(localized: "Casual message"), colorHex: "#1D6B4F",
        instruction: "Rewrite my draft as a casual message to a friend or family: short, warm and natural, the way people text. Keep my meaning, my slang and my emoji.",
        dos: ["Short sentences", "Everyday words and contractions", "My emoji where I put them"],
        avoid: ["Work or formal phrasing", "Emoji or exclamation marks I didn't use", "Making it longer"],
        apps: [
            AppRef(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp"),
            AppRef(bundleID: "desktop.WhatsApp", name: "WhatsApp"),
            AppRef(bundleID: "ru.keepcoder.Telegram", name: "Telegram"),
            AppRef(bundleID: "org.telegram.desktop", name: "Telegram"),
            AppRef(bundleID: "com.hnc.Discord", name: "Discord"),
            AppRef(bundleID: "com.apple.MobileSMS", name: "Messages"),
            .site("web.whatsapp.com", name: "WhatsApp Web"),
            .site("web.telegram.org", name: "Telegram Web"),
            .site("discord.com", name: "Discord web"),
        ])

    /// English keeps the id it had when it was the only translate preset, so copies made then still show as added.
    static func translate(to code: String) -> Preset {
        let name = Languages.englishName(code)
        return Preset(
            id: code == "en" ? "gallery.translate" : "gallery.translate.\(code)", name: String(localized: "Translate to \(Languages.displayName(code))"), colorHex: "#0E6E8C",
            instruction: "Translate my draft into natural \(name), the way a native speaker would write it. Keep my meaning, tone, register and formatting.",
            dos: ["Names, product terms, links and numbers as written", "Idioms become natural equivalents"],
            avoid: ["Word-for-word translation", "Adding or dropping anything", "More formal than my draft"],
            language: .language(code), length: .any)
    }

    private static let blurbs: [String: String] = [
        Preset.proofread.id: String(localized: "Fixes mistakes only. Keeps your words."),
        slack.id: String(localized: "Lead with the answer, warm and brief."),
        email.id: String(localized: "A clear email body, ask near the top."),
        shorter.id: String(localized: "Fewer words, nothing lost."),
        friendlier.id: String(localized: "Warmer, same message."),
        direct.id: String(localized: "Point first, no hedging, still polite."),
        professional.id: String(localized: "Polished for clients and leadership."),
        explainSimply.id: String(localized: "Plain words for people outside your field."),
        summarize.id: String(localized: "Notes or a long thread into a short reply."),
        statusUpdate.id: String(localized: "Done, next and blocked."),
        decline.id: String(localized: "A clear no that keeps things warm."),
        promptForAI.id: String(localized: "A rough ask into a clear prompt."),
        casual.id: String(localized: "Short and warm, the way you text."),
    ]
}

/// Whether an app is on this Mac, by bundle id. Asked once per id: Launch Services lookups aren't free, and the gallery
/// asks every time it's drawn.
enum InstalledApps {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var known: [String: Bool] = [:]

    static func contains(_ bundleID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let found = known[bundleID] { return found }
        let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        known[bundleID] = found
        return found
    }
}
