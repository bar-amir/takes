import Foundation

/// Ready-made presets. Adding one gives the user their own copy (a new id) to edit; the template
/// itself never changes. Fresh installs start with `starters`.
enum PresetGallery {
    static var all: [Preset] {
        [.proofread, slack, email, shorter, friendlier, direct, professional, explainSimply, summarize, statusUpdate, decline]
            + translations(for: Store.shared.settings.writingLanguages)
    }

    /// Installed on a fresh setup. Existing users keep their own presets. People who write in more than one
    /// language also start with "Translate to …" for each of them.
    static var starters: [Preset] { starters(languages: Store.shared.settings.writingLanguages) }

    static func starters(languages: [String]) -> [Preset] {
        [.proofread, slack, email, shorter, friendlier, direct, decline] + (languages.count > 1 ? translations(for: languages) : [])
    }

    /// One "Translate to …" per language the user writes in.
    static func translations(for languages: [String]) -> [Preset] { languages.map(translate(to:)) }

    /// The panel's picker ends with "Browse more presets" while the user has fewer presets than this.
    static let browseRowLimit = 8

    /// One line for the gallery list.
    static func blurb(for preset: Preset) -> String {
        let id = preset.galleryID ?? preset.id
        if id.hasPrefix("gallery.translate"), case .language(let code) = preset.language {
            return "Natural \(Languages.englishName(code)) from any language."
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

    /// A preset just made with "New" and not edited yet: the moment to suggest the gallery instead.
    static func isUntouchedNew(_ preset: Preset, blank: Preset) -> Bool {
        preset.name == blank.name && preset.instruction == blank.instruction && preset.dos.isEmpty
            && preset.avoid.isEmpty && preset.examples.isEmpty && preset.galleryID == nil
    }

    // MARK: Templates

    static let slack = Preset(
        id: "gallery.slack", name: "Slack message", colorHex: "#2F55E0",
        instruction: "Rewrite my draft as a chat message to teammates. Lead with the answer or the ask, then only the context they need. Warm but brief, the way a respected colleague writes in Slack.",
        dos: ["Answer or ask in the first sentence", "One ask per sentence", "Keep shorthand like EOD, QA, PR"],
        avoid: ["Exclamation marks", "\"Just\", \"quick question\", \"hope you're well\"", "Emoji unless I used them", "Bullets for a short message"],
        apps: [AppRef(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")])

    static let email = Preset(
        id: "gallery.email", name: "Polish email", colorHex: "#7A3FD1",
        instruction: "Rewrite my draft as a clear, professional email body. Keep my points; fix the order and flow so the reader knows what I need by the end of the first paragraph. Keep any greeting or sign-off I wrote. No subject line, no signature.",
        dos: ["Short paragraphs, one idea each", "The ask or decision near the top", "Concrete dates and owners"],
        avoid: ["\"I hope this email finds you well\"", "Stacked apologies", "Facts or promises I didn't write"],
        length: .any, apps: [AppRef(bundleID: "com.apple.mail", name: "Mail")])

    static let shorter = Preset(
        id: "gallery.shorter", name: "Shorter", colorHex: "#8A4B08",
        instruction: "Say the same thing in as few words as possible. Keep every ask, fact, number, name and date.",
        dos: ["Cut filler, hedges and repetition", "Merge points that say the same thing"],
        avoid: ["Dropping any ask or detail", "Clipped fragments that read as rude"],
        length: .shorter)

    static let friendlier = Preset(
        id: "gallery.friendlier", name: "Friendlier", colorHex: "#1D6B4F",
        instruction: "Make my draft warmer and easier to receive without changing what it says. Sound like a kind colleague, not a greeting card.",
        dos: ["Acknowledge the other person where it fits", "Soften blunt phrasing", "Keep every ask and fact"],
        avoid: ["Gushing (\"amazing\", \"so excited\")", "Exclamation marks in every sentence", "Emoji unless I used them", "Burying the point"])

    static let direct = Preset(
        id: "gallery.direct", name: "More direct", colorHex: "#B42318",
        instruction: "Make my draft more direct and confident. Put the point and the ask first, in plain words. Stay polite.",
        dos: ["Lead with the point", "Turn hedges into clear statements", "Name the date or owner if I gave one"],
        avoid: ["\"Just\", \"I think\", \"sort of\", \"maybe\"", "Apologising for asking", "Exclamation marks", "Sounding cold or curt"])

    static let professional = Preset(
        id: "gallery.professional", name: "Professional", colorHex: "#55555E",
        instruction: "Rewrite my draft for a client, leadership or someone I don't know well: polished and confident, still plain and human. Keep my meaning exactly.",
        dos: ["Complete sentences", "Calm, neutral tone"],
        avoid: ["Slang and in-jokes", "Jargon (\"synergy\", \"circle back\", \"leverage\")", "Stiff, legal-sounding phrasing"])

    static let explainSimply = Preset(
        id: "gallery.explain", name: "Explain simply", colorHex: "#0E6E8C",
        instruction: "Rewrite my draft so someone outside my field understands it on the first read. Swap jargon for plain words. Add a short example only if it makes the point clearer.",
        dos: ["Short sentences", "Explain a term the first time if it has to stay", "Keep the facts accurate"],
        avoid: ["Unexplained acronyms", "Talking down to the reader", "Claims I didn't make"],
        length: .any)

    static let summarize = Preset(
        id: "gallery.summarize", name: "Summarize", colorHex: "#2F55E0",
        instruction: "Turn my draft (notes, a long update or text I pasted) into a short summary I can post as a reply: the bottom line first, then the key points, decisions and open asks.",
        dos: ["Bottom line in the first sentence", "Up to 3 short bullets if there are several points", "Names, numbers and dates exactly as written"],
        avoid: ["Opinions or conclusions that aren't in the text", "Restating everything", "Headings"],
        length: .shorter)

    static let statusUpdate = Preset(
        id: "gallery.status", name: "Status update", colorHex: "#1D6B4F",
        instruction: "Turn my notes into a short status update for the team: what's done, what's next and what's blocked, with owners and dates where I gave them.",
        dos: ["Done, next, blocked, in that order", "Skip a part that has nothing in it"],
        avoid: ["Padding a short update", "Progress, owners or dates I didn't mention"],
        length: .any)

    static let decline = Preset(
        id: "gallery.decline", name: "Decline politely", colorHex: "#B42318",
        instruction: "Say no to the request in my draft, politely and clearly, and keep the relationship warm. Give a reason only if my draft has one. Offer an alternative only if I suggested one.",
        dos: ["Make the no unmistakable", "Thank them once, briefly"],
        avoid: ["Over-apologising", "Vague maybes that invite a follow-up", "Reasons or alternatives I didn't give"])

    /// English keeps the id it had when it was the only translate preset, so copies made then still show as added.
    static func translate(to code: String) -> Preset {
        let name = Languages.englishName(code)
        return Preset(
            id: code == "en" ? "gallery.translate" : "gallery.translate.\(code)", name: "Translate to \(name)", colorHex: "#0E6E8C",
            instruction: "Translate my draft into natural \(name), the way a native speaker would write it. Keep my meaning, tone, register and formatting.",
            dos: ["Names, product terms, links and numbers as written", "Idioms become natural equivalents"],
            avoid: ["Word-for-word translation", "Adding or dropping anything", "More formal than my draft"],
            language: .language(code), length: .any)
    }

    private static let blurbs: [String: String] = [
        Preset.proofread.id: "Fixes mistakes only. Keeps your words.",
        slack.id: "Lead with the answer, warm and brief.",
        email.id: "A clear email body, ask near the top.",
        shorter.id: "Fewer words, nothing lost.",
        friendlier.id: "Warmer, same message.",
        direct.id: "Point first, no hedging, still polite.",
        professional.id: "Polished for clients and leadership.",
        explainSimply.id: "Plain words for people outside your field.",
        summarize.id: "Notes or a long thread into a short reply.",
        statusUpdate.id: "Done, next and blocked.",
        decline.id: "A clear no that keeps things warm.",
    ]
}
