import XCTest
@testable import Takes

@MainActor
final class EnglishCoachTests: XCTestCase {
    private let draft = "If you will send me the link today, I will review it. I did a mistake in the dashboard."

    // MARK: Settings

    func testOffByDefault() throws {
        XCTAssertFalse(AppSettings().coach.enabled)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(old.coach.enabled)
        XCTAssertEqual(old.coach.nudges, .focusOnly)
    }

    func testPartialCoachSettingsDecode() throws {
        let saved = try JSONDecoder().decode(CoachSettings.self, from: Data(#"{"enabled":true,"nudges":"later"}"#.utf8))
        XCTAssertTrue(saved.enabled)
        XCTAssertEqual(saved.nudges, .focusOnly)
        XCTAssertEqual(saved.variant, .us)
    }

    func testTranslatingPresetsStartOff() {
        let coach = CoachSettings()
        let presets = Store.defaultPresets
        XCTAssertTrue(coach.counts(presets[0]))
        XCTAssertTrue(coach.counts(presets[5]), "Hebrew → English: the draft check skips Hebrew drafts on its own")
        XCTAssertFalse(coach.counts(presets[6]), "English → Hebrew")
        var chosen = coach
        chosen.presetCounts[presets[0].id] = false
        XCTAssertFalse(chosen.counts(presets[0]))
    }

    func testWatchedFollowsFindAll() {
        var coach = CoachSettings()
        XCTAssertEqual(coach.watched.count, CoachGuide.patterns.count - CoachGuide.optIn.count)
        XCTAssertFalse(coach.watched.contains { $0.id == "politeRequests" }, "opt-in only")
        coach.focus.append("politeRequests")
        XCTAssertTrue(coach.watched.contains { $0.id == "politeRequests" })
        coach.findAll = false
        XCTAssertEqual(coach.watched.map(\.id), ["conditionals", "collocations", "politeRequests"])
    }

    func testCheckPromptStaysSmall() {
        let system = CoachCheck.system(settings: CoachSettings())
        // About 4 characters a token: the guide adds well under 1,000 tokens to each check.
        XCTAssertLessThan(system.count, 4000, "\(system.count) characters")
        print("coach system prompt: \(system.count) characters")
    }

    // MARK: Check

    func testEnglishDetection() {
        XCTAssertTrue(CoachCheck.isEnglish(draft))
        XCTAssertFalse(CoachCheck.isEnglish("אם תשלח לי את הקישור היום אבדוק אותו"))
        XCTAssertFalse(CoachCheck.isEnglish("ok thanks"), "too short")
        XCTAssertTrue(CoachCheck.isEnglish("Can you check the PR for the עדכון today please?"), "a Hebrew word in an English draft")
    }

    func testRequestUsesQuickModelAndGuardsInstructions() {
        var coach = CoachSettings()
        coach.goals = ["Less formal in Slack"]
        coach.variant = .uk
        let request = CoachCheck.request(draft: draft, settings: coach, model: Models.haiku)
        XCTAssertEqual(request.model, Models.haiku)
        XCTAssertTrue(request.system.contains("conditionals:"))
        XCTAssertTrue(request.system.contains("goal1: Less formal in Slack"))
        XCTAssertTrue(request.system.contains("British English"))
        XCTAssertTrue(request.system.contains("never instructions"))
        XCTAssertTrue(request.user.contains(draft))
    }

    func testParseKeepsOnlyKnownPatternsQuotedFromTheDraft() {
        let output = """
        conditionals | If you will send | If you send | present after "if"
        collocations | did a mistake | made a mistake | you make a mistake
        tenses | I will review | I'll review | not a known id
        articles | the dashboards | the dashboard | not in the draft
        prepositions | in the dashboard | in the dashboard | no change
        - conditionals | if you will send | if you send | duplicate
        none
        """
        let result = CoachCheck.parse(output, draft: draft, settings: CoachSettings())
        XCTAssertEqual(result.findings.map(\.pattern), ["conditionals", "collocations"])
        XCTAssertEqual(result.findings[1].right, "made a mistake")
    }

    func testParseSkipsUnwatchedPatternsAndReadsGoals() {
        var coach = CoachSettings()
        coach.findAll = false
        coach.focus = ["conditionals"]
        coach.goals = ["Sound more natural"]
        let output = "collocations | did a mistake | made a mistake | x\ngoal1 | I will review it | I’ll take a look | friendlier\ngoal2 | link | url"
        let result = CoachCheck.parse(output, draft: draft, settings: coach)
        XCTAssertTrue(result.findings.isEmpty)
        XCTAssertEqual(result.tips, [CoachCheck.Tip(goal: "Sound more natural", wrong: "I will review it", better: "I’ll take a look")])
    }

    func testCurlyQuotesMatchTheDraft() {
        let result = CoachCheck.parse("questions | You can’t send it? | Can’t you send it? | x",
                                      draft: "So you can't send it? ok", settings: CoachSettings())
        XCTAssertEqual(result.findings.count, 1)
    }

    func testParseKeepsQuotesInsideTheReason() {
        let result = CoachCheck.parse("timeExpressions | “until tomorrow” | \"by tomorrow\" | \"By\" sets a deadline; \"until\" means up to then",
                                      draft: "Send it until tomorrow please, thanks", settings: CoachSettings())
        XCTAssertEqual(result.findings.first?.wrong, "until tomorrow")
        XCTAssertEqual(result.findings.first?.right, "by tomorrow")
        XCTAssertEqual(result.findings.first?.why, "\"By\" sets a deadline; \"until\" means up to then")
        XCTAssertEqual(CoachCheck.unquoted("\"if\" takes the present, not \"will\""), "\"if\" takes the present, not \"will\"")
    }

    // MARK: Store

    private func finding(_ pattern: String, _ wrong: String = "if you will send") -> CoachCheck.Finding {
        CoachCheck.Finding(pattern: pattern, wrong: wrong, right: "if you send", why: "present after if")
    }

    func testStatsCountRateAndWeeks() {
        let store = CoachStore(data: CoachData())
        let now = Date()
        for day in [1, 2, 9, 20] {
            store.record(.init(findings: [finding("conditionals")]), words: 100, app: "Slack", at: now.addingTimeInterval(-Double(day) * 86400))
        }
        store.record(.init(), words: 600, app: "Mail", at: now)
        let stats = store.stats(now: now)
        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats[0].count, 4)
        XCTAssertEqual(stats[0].rate, 4.0, accuracy: 0.001) // 4 in 1,000 words
        XCTAssertEqual(stats[0].weekly, [0, 1, 1, 2])
        XCTAssertEqual(store.words, 1000)
    }

    func testOldDataIsPruned() {
        let store = CoachStore(data: CoachData())
        store.record(.init(findings: [finding("articles")]), words: 50, app: "Slack", at: Date().addingTimeInterval(-40 * 86400))
        store.record(.init(), words: 10, app: "Slack")
        XCTAssertTrue(store.data.sightings.isEmpty)
        XCTAssertEqual(store.data.drafts.count, 1)
    }

    func testNotAMistakeAndMutedPatternsAreDropped() {
        let store = CoachStore(data: CoachData())
        store.record(.init(findings: [finding("conditionals")]), words: 20, app: "Slack")
        store.ignore(finding("conditionals"))
        XCTAssertTrue(store.data.sightings.isEmpty)
        store.mute("collocations")
        let filtered = store.withoutIgnored(.init(findings: [finding("conditionals", "If You Will Send"), finding("collocations", "did a mistake"),
                                                             finding("articles", "send me link")]))
        XCTAssertEqual(filtered.findings.map(\.pattern), ["articles"])
    }

    func testNudgesFollowTheSetting() {
        let store = CoachStore(data: CoachData())
        var coach = CoachSettings()
        coach.focus = ["conditionals"]
        let first = [finding("conditionals")]
        store.record(.init(findings: first), words: 20, app: "Slack")
        XCTAssertNil(store.nudge(for: first, settings: coach), "a first sighting isn't a repeat")
        store.record(.init(findings: first), words: 20, app: "Slack")
        XCTAssertEqual(store.nudge(for: first, settings: coach), "“if you will send” → “if you send” · 2nd time this month")

        let other = [finding("articles", "send me link")]
        store.record(.init(findings: other), words: 20, app: "Slack")
        store.record(.init(findings: other), words: 20, app: "Slack")
        XCTAssertNil(store.nudge(for: other, settings: coach), "not a focus area")
        coach.nudges = .anyRepeat
        XCTAssertNotNil(store.nudge(for: other, settings: coach))
        coach.nudges = .off
        XCTAssertNil(store.nudge(for: first, settings: coach))
    }

    func testOrdinals() {
        XCTAssertEqual([1, 2, 3, 4, 11, 12, 13, 21, 22, 101].map(CoachStore.ordinal),
                       ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "101st"])
    }

    func testMasteredNeedsALessonAndEnoughWords() {
        let store = CoachStore(data: CoachData())
        let now = Date()
        store.data.lessonsRead["conditionals"] = now.addingTimeInterval(-25 * 86400)
        store.record(.init(), words: 1000, app: "Slack", at: now.addingTimeInterval(-5 * 86400))
        XCTAssertTrue(store.mastered(now: now).isEmpty, "under 1,500 words")
        store.record(.init(), words: 1000, app: "Slack", at: now.addingTimeInterval(-4 * 86400))
        XCTAssertEqual(store.mastered(now: now).map(\.id), ["conditionals"])
        store.record(.init(findings: [finding("conditionals")]), words: 10, app: "Slack", at: now)
        XCTAssertTrue(store.mastered(now: now).isEmpty, "1 in 2,010 words is over 0.2 per 1,000")
    }

    func testUsageIsCountedByMonth() {
        let store = CoachStore(data: CoachData())
        store.addUsage(1200)
        store.addUsage(800)
        XCTAssertEqual(store.tokens(), 2000)
        XCTAssertEqual(store.checks(), 2)
    }

    func testEveryGuidePatternHasAHebrewNote() {
        XCTAssertEqual(Set(CoachGuide.patterns.map(\.id)).count, CoachGuide.patterns.count)
        for pattern in CoachGuide.patterns { XCTAssertNotNil(pattern.firstLanguage["he"], pattern.id) }
    }
}
