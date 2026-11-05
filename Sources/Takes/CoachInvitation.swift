import Foundation

// The English coach's just-in-time invitation. While the coach is off, Takes already diffs each English draft
// against its takes (the same diff as "Changes"). A cheap local heuristic files the small fixes under the coach
// guide's pattern ids. When the same kind of fix has shown up in 3 or more drafts, a strip under the takes offers
// the coach, at most once a week. Nothing here calls a model, and only pattern ids and dates are kept.

// MARK: - Heuristic

/// Files one draft → take fix under a coach pattern, or nil when it isn't a recognisable grammar or word-choice fix.
/// Deliberately narrow: a rewrite that changes many words is never filed, so rewriting presets add little noise.
enum FixHeuristic {
    static let articles: Set<String> = ["a", "an", "the"]
    static let timeWords: Set<String> = ["until", "till", "by", "since", "for", "ago", "during", "before"]
    static let prepositions: Set<String> = ["in", "on", "at", "to", "for", "of", "with", "about", "from", "into", "onto",
                                            "by", "until", "since", "over", "under", "after", "before", "during", "towards"]
    static let lightVerbs: [String: String] = [
        "make": "make", "makes": "make", "made": "make", "making": "make",
        "do": "do", "does": "do", "did": "do", "doing": "do",
        "take": "take", "takes": "take", "took": "take", "taking": "take",
        "give": "give", "gives": "give", "gave": "give", "giving": "give",
        "have": "have", "has": "have", "had": "have", "having": "have",
        "say": "say", "says": "say", "said": "say", "tell": "tell", "tells": "tell", "told": "tell",
        "open": "open", "close": "close", "turn": "turn", "switch": "switch", "put": "put", "get": "get", "got": "get",
    ]
    static let perfect: Set<String> = ["have", "has"]
    static let contractions: [String: String] = ["'ll": "will", "'ve": "have", "'m": "am", "'re": "are", "'d": "would"]
    static let agreementPairs: [Set<String>] = [["is", "are"], ["was", "were"], ["has", "have"], ["does", "do"], ["doesn't", "don't"]]
    /// More words than this on either side is a rewrite, not a fix.
    static let maxWords = 6

    /// Lowercased words, with punctuation at their edges removed; apostrophes are normalised to '.
    static func words(_ text: String) -> [String] {
        text.lowercased().replacingOccurrences(of: "’", with: "'")
            .split { $0.isWhitespace }
            .map { $0.trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "'"))) }
            .filter { !$0.isEmpty }
            .flatMap { word -> [String] in
                // "I'll" is "I will", so contracting a word is never filed as a fix.
                for (suffix, full) in contractions where word.hasSuffix(suffix) && word.count > suffix.count {
                    return [String(word.dropLast(suffix.count)), full]
                }
                return [word]
            }
    }

    /// The pattern id for a fix, given the draft it came from (for context such as "if").
    static func classify(_ fix: WordDiff.Fix, draft: String) -> String? {
        let removed = words(fix.removed), added = words(fix.added)
        guard !(removed.isEmpty && added.isEmpty), removed.count <= maxWords, added.count <= maxWords else { return nil }
        // Capitals and punctuation only: not grammar or word choice.
        if removed == added { return nil }
        let gone = subtract(removed, added), new = subtract(added, removed)
        if gone.isEmpty && new.isEmpty {
            return removed.count >= 2 ? "wordOrder" : nil
        }

        let draftWords = Set(words(draft))
        if gone.contains("will"), !new.contains("will"), draftWords.contains("if") {
            return "conditionals"
        }
        if !new.filter(perfect.contains).isEmpty, gone.filter(perfect.contains).isEmpty,
           !gone.isEmpty || draftWords.contains("since") || draftWords.contains("for") {
            return "presentPerfect"
        }
        let goneVerbs = gone.compactMap { lightVerbs[$0] }, newVerbs = new.compactMap { lightVerbs[$0] }
        if let a = goneVerbs.first, let b = newVerbs.first, a != b,
           (gone.filter { lightVerbs[$0] == nil && !articles.contains($0) }).isEmpty,
           new.filter({ lightVerbs[$0] == nil && !articles.contains($0) && !prepositions.contains($0) }).count <= 1 {
            return "collocations"
        }
        if (gone + new).allSatisfy(articles.contains) { return "articles" }
        if gone.count <= 1, new.count <= 1, (gone + new).allSatisfy(timeWords.contains),
           (gone + new).contains(where: { ["until", "till", "by", "since", "ago", "during"].contains($0) }) {
            return "timeExpressions"
        }
        if (gone + new).allSatisfy(prepositions.contains) { return "prepositions" }
        if gone.count == 1, new.count == 1, agreementPairs.contains(where: { $0 == [gone[0], new[0]] }) { return "agreement" }
        return nil
    }

    /// What's left of `a` after taking out each word of `b` once.
    private static func subtract(_ a: [String], _ b: [String]) -> [String] {
        var rest = b
        return a.filter { word in
            if let i = rest.firstIndex(of: word) { rest.remove(at: i); return false }
            return true
        }
    }

    /// One recognised fix in a draft: the words and the pattern they fall under.
    struct Found: Equatable {
        let pattern: String
        let fix: WordDiff.Fix
    }

    /// The fixes the takes agree on: a kind of fix counts when at least half the takes make it. Each pattern
    /// appears once, with the shortest example.
    static func analyse(draft: String, takes: [String]) -> [Found] {
        let takes = takes.filter { !$0.isEmpty }
        guard !takes.isEmpty else { return [] }
        var counts: [String: Int] = [:]
        var examples: [String: WordDiff.Fix] = [:]
        var order: [String] = []
        for take in takes {
            var seen = Set<String>()
            for fix in WordDiff.readableFixes(from: draft, to: take) {
                guard let pattern = classify(fix, draft: draft) else { continue }
                if !order.contains(pattern) { order.append(pattern) }
                if let old = examples[pattern] {
                    if fix.removed.count + fix.added.count < old.removed.count + old.added.count { examples[pattern] = fix }
                } else {
                    examples[pattern] = fix
                }
                if seen.insert(pattern).inserted { counts[pattern, default: 0] += 1 }
            }
        }
        let needed = max(1, (takes.count + 1) / 2)
        return order.filter { (counts[$0] ?? 0) >= needed }.compactMap { id in examples[id].map { Found(pattern: id, fix: $0) } }
    }
}

// MARK: - Eligibility and rate limit

struct CoachInviteData: Codable, Equatable {
    struct Draft: Codable, Equatable {
        var date: Date
        var patterns: [String]
    }

    /// English drafts that had recognised fixes: dates and pattern ids only.
    var drafts: [Draft] = []
    var lastShown: Date?
    /// The ✕: backs off for a month.
    var dismissed: Date?
    /// "Don't ask again".
    var never = false
}

enum CoachInvitation {
    static let day: TimeInterval = 24 * 3600
    /// The same kind of fix in this many drafts (counting this one).
    static let repeatsNeeded = 3
    static let window: TimeInterval = 30 * day
    static let showEvery: TimeInterval = 7 * day
    static let dismissBackoff: TimeInterval = 30 * day

    /// What the strip shows: the user's own fixes and how often the first kind came up.
    struct Offer: Equatable {
        var found: [FixHeuristic.Found]
        /// Pattern ids that repeat, most often first: what setup pre-fills.
        var repeating: [String]
        /// Drafts (this one included) with the top repeating pattern.
        var drafts: Int
    }

    struct Context {
        var coachOn: Bool
        var english: Bool
        /// The preset is one the coach would count (not translating into another language).
        var presetCounts: Bool
        /// A local model: slow, so never offered.
        var localEngine: Bool
    }

    /// True when the rate limit and the user's answers allow showing it now.
    static func allowed(_ data: CoachInviteData, now: Date) -> Bool {
        if data.never { return false }
        if let shown = data.lastShown, now.timeIntervalSince(shown) < showEvery { return false }
        if let dismissed = data.dismissed, now.timeIntervalSince(dismissed) < dismissBackoff { return false }
        return true
    }

    /// The offer for this draft, or nil. `data` holds earlier drafts only; the current one is counted here.
    static func offer(context: Context, found: [FixHeuristic.Found], data: CoachInviteData, now: Date) -> Offer? {
        guard !context.coachOn, context.english, context.presetCounts, !context.localEngine, !found.isEmpty,
              allowed(data, now: now) else { return nil }
        let recent = data.drafts.filter { now.timeIntervalSince($0.date) < window }
        let counts = found.map { item in (item.pattern, recent.filter { $0.patterns.contains(item.pattern) }.count + 1) }
        let repeating = counts.filter { $0.1 >= repeatsNeeded }.sorted { $0.1 > $1.1 }
        guard let top = repeating.first else { return nil }
        // The repeating kinds lead, so the first chip is the one the count is about.
        let ids = repeating.map(\.0)
        let ordered = found.filter { ids.contains($0.pattern) } + found.filter { !ids.contains($0.pattern) }
        return Offer(found: Array(ordered.prefix(3)), repeating: ids, drafts: top.1)
    }

    /// Adds this draft's patterns to the record and drops what's older than the window.
    static func recording(_ found: [FixHeuristic.Found], in data: CoachInviteData, now: Date) -> CoachInviteData {
        var data = data
        data.drafts.removeAll { now.timeIntervalSince($0.date) >= window }
        if !found.isEmpty { data.drafts.append(.init(date: now, patterns: found.map(\.pattern))) }
        return data
    }
}

/// The invitation's record in coach-invite.json, beside the other Takes files.
@MainActor
final class CoachInviteStore {
    static let shared = CoachInviteStore(file: Store.directory.appendingPathComponent("coach-invite.json"))

    private(set) var data: CoachInviteData
    private let file: URL?

    /// `file: nil` keeps everything in memory (tests).
    init(file: URL?, data: CoachInviteData? = nil) {
        self.file = file
        self.data = data ?? file.flatMap(Self.load) ?? CoachInviteData()
    }

    /// Records the draft and returns the offer to show, if any. Showing it counts toward the weekly limit.
    func consider(context: CoachInvitation.Context, found: [FixHeuristic.Found], now: Date = Date()) -> CoachInvitation.Offer? {
        guard !context.coachOn, context.english, context.presetCounts else { return nil }
        let offer = CoachInvitation.offer(context: context, found: found, data: data, now: now)
        var next = CoachInvitation.recording(found, in: data, now: now)
        if offer != nil { next.lastShown = now }
        update(next)
        return offer
    }

    func dismiss(now: Date = Date()) { var next = data; next.dismissed = now; update(next) }

    func neverAgain() { var next = data; next.never = true; update(next) }

    /// The patterns seen most often, for setup's suggestions when it wasn't opened from the invitation.
    func suggestions(now: Date = Date(), limit: Int = 3) -> [String] {
        var counts: [String: Int] = [:]
        for draft in data.drafts where now.timeIntervalSince(draft.date) < CoachInvitation.window {
            for id in draft.patterns { counts[id, default: 0] += 1 }
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(limit).map(\.key)
    }

    func replace(_ data: CoachInviteData) { update(data) }

    private func update(_ next: CoachInviteData) {
        guard next != data else { return }
        data = next
        guard let file, !Store.readOnly else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let encoded = try? encoder.encode(data) { try? encoded.write(to: file, options: .atomic) }
    }

    private static func load(_ file: URL) -> CoachInviteData? {
        guard let raw = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CoachInviteData.self, from: raw)
    }
}

/// Hands "Turn on coach" over to Settings › English coach: the tab opens its setup pre-filled with these patterns.
@MainActor
final class CoachSetupRequest: ObservableObject {
    static let shared = CoachSetupRequest()
    /// Pattern ids to suggest; non-nil until the coach tab picks it up.
    @Published var pending: [String]?
}
