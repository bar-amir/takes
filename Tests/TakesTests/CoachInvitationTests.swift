import XCTest
@testable import Takes

@MainActor
final class CoachInvitationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let on = CoachInvitation.Context(coachOn: false, english: true, presetCounts: true, localEngine: false)
    private let day: TimeInterval = 24 * 3600

    private func fix(_ removed: String, _ added: String) -> WordDiff.Fix { .init(removed: removed, added: added) }
    private func found(_ pattern: String) -> FixHeuristic.Found { .init(pattern: pattern, fix: fix("x", "y")) }

    // MARK: Heuristic

    func testClassifiesCommonFixes() {
        let draft = "If you will send me the file until tomorrow, I will make you a feedback."
        XCTAssertEqual(FixHeuristic.classify(fix("will send", "send"), draft: draft), "conditionals")
        XCTAssertEqual(FixHeuristic.classify(fix("until", "by"), draft: draft), "timeExpressions")
        XCTAssertEqual(FixHeuristic.classify(fix("make you a feedback", "give you feedback"), draft: draft), "collocations")
        XCTAssertEqual(FixHeuristic.classify(fix("send me link", "send me the link"), draft: "send me link"), "articles")
        XCTAssertEqual(FixHeuristic.classify(fix("waiting to", "waiting for"), draft: "waiting to your answer"), "prepositions")
        XCTAssertEqual(FixHeuristic.classify(fix("I am working", "I've been working"), draft: "I am working here since 2020"), "presentPerfect")
        XCTAssertEqual(FixHeuristic.classify(fix("what means this error", "what this error means"), draft: "I know what means this error"), "wordOrder")
        XCTAssertEqual(FixHeuristic.classify(fix("he are", "he is"), draft: "he are late"), "agreement")
    }

    func testIgnoresStyleAndRewrites() {
        XCTAssertNil(FixHeuristic.classify(fix("ya thursday", "Thursday"), draft: "ya thursday works"))
        XCTAssertNil(FixHeuristic.classify(fix("thursday", "Thursday"), draft: "thursday"), "capitals only")
        XCTAssertNil(FixHeuristic.classify(fix("eod", "EOD,"), draft: "eod"), "punctuation only")
        XCTAssertNil(FixHeuristic.classify(fix("can someone own the release notes this time", "could someone take the notes"), draft: ""),
                     "a rewrite of many words")
        XCTAssertNil(FixHeuristic.classify(fix("will", ""), draft: "I will check it"), "no if: not a conditional")
    }

    func testAnalyseKeepsFixesMostTakesAgreeOn() {
        let draft = "If you will send me the file until tomorrow, I will check it."
        let takes = [
            "If you send me the file by tomorrow, I will check it.",
            "If you send me the file by tomorrow, I'll check it.",
            "If you send me the file until tomorrow, I will check it.",
        ]
        let found = FixHeuristic.analyse(draft: draft, takes: takes)
        XCTAssertEqual(found.map(\.pattern), ["conditionals", "timeExpressions"])
        XCTAssertEqual(found.first?.fix, fix("will send", "send"))
        XCTAssertTrue(FixHeuristic.analyse(draft: draft, takes: []).isEmpty)
    }

    func testReadableFixesBorrowAWordForInsertionsAndDeletions() {
        XCTAssertEqual(WordDiff.readableFixes(from: "If you will send it", to: "If you send it"), [fix("will send", "send")])
        XCTAssertEqual(WordDiff.readableFixes(from: "send me link", to: "send me the link"), [fix("link", "the link")])
        XCTAssertEqual(WordDiff.readableFixes(from: "I did it", to: "I made it"), [fix("did", "made")])
    }

    func testCollapsedCoachLeadsWithTheMostRepeatedPattern() {
        let findings = [CoachCheck.Finding(pattern: "articles", wrong: "a", right: "b", why: ""),
                        CoachCheck.Finding(pattern: "conditionals", wrong: "c", right: "d", why: "")]
        XCTAssertEqual(CoachStrip.top(findings) { $0 == "conditionals" ? 4 : 1 }?.pattern, "conditionals")
        XCTAssertEqual(CoachStrip.top(findings) { _ in 0 }?.pattern, "articles", "a tie keeps the first")
    }

    // MARK: Eligibility

    private func history(_ pattern: String, drafts: Int, daysAgo: Double = 1) -> CoachInviteData {
        var data = CoachInviteData()
        data.drafts = (0..<drafts).map { .init(date: now.addingTimeInterval(-(daysAgo + Double($0)) * day), patterns: [pattern]) }
        return data
    }

    func testOffersOnTheThirdDraftWithTheSameKindOfFix() {
        XCTAssertNil(CoachInvitation.offer(context: on, found: [found("conditionals")], data: history("conditionals", drafts: 1), now: now))
        let offer = CoachInvitation.offer(context: on, found: [found("articles"), found("conditionals")],
                                          data: history("conditionals", drafts: 2), now: now)
        XCTAssertEqual(offer?.drafts, 3)
        XCTAssertEqual(offer?.repeating, ["conditionals"])
        XCTAssertEqual(offer?.found.first?.pattern, "conditionals", "the repeating fix leads")
    }

    func testOnlyRecentDraftsCount() {
        XCTAssertNil(CoachInvitation.offer(context: on, found: [found("conditionals")], data: history("conditionals", drafts: 2, daysAgo: 31), now: now))
    }

    func testNeverWhenTheCoachCannotHelp() {
        let data = history("conditionals", drafts: 5)
        let finds = [found("conditionals")]
        var context = on
        context.coachOn = true
        XCTAssertNil(CoachInvitation.offer(context: context, found: finds, data: data, now: now), "coach already on")
        context = on; context.english = false
        XCTAssertNil(CoachInvitation.offer(context: context, found: finds, data: data, now: now), "not English")
        context = on; context.presetCounts = false
        XCTAssertNil(CoachInvitation.offer(context: context, found: finds, data: data, now: now), "translating preset")
        context = on; context.localEngine = true
        XCTAssertNil(CoachInvitation.offer(context: context, found: finds, data: data, now: now), "slow local engine")
        XCTAssertNil(CoachInvitation.offer(context: on, found: [], data: data, now: now), "takes changed no grammar")
    }

    // MARK: Rate limit

    func testAtMostOnceAWeek() {
        var data = history("conditionals", drafts: 5)
        data.lastShown = now.addingTimeInterval(-6 * day)
        XCTAssertNil(CoachInvitation.offer(context: on, found: [found("conditionals")], data: data, now: now))
        data.lastShown = now.addingTimeInterval(-7 * day)
        XCTAssertNotNil(CoachInvitation.offer(context: on, found: [found("conditionals")], data: data, now: now))
    }

    func testDismissBacksOffForAMonthAndNeverIsPermanent() {
        var data = history("conditionals", drafts: 5)
        data.dismissed = now.addingTimeInterval(-29 * day)
        XCTAssertFalse(CoachInvitation.allowed(data, now: now))
        data.dismissed = now.addingTimeInterval(-30 * day)
        XCTAssertTrue(CoachInvitation.allowed(data, now: now))
        data.never = true
        XCTAssertFalse(CoachInvitation.allowed(data, now: now.addingTimeInterval(1000 * day)))
    }

    func testStoreRecordsDraftsAndCountsAShowing() {
        let store = CoachInviteStore(file: nil)
        let finds = [found("conditionals")]
        XCTAssertNil(store.consider(context: on, found: finds, now: now.addingTimeInterval(-2 * day)))
        XCTAssertNil(store.consider(context: on, found: finds, now: now.addingTimeInterval(-1 * day)))
        XCTAssertEqual(store.data.drafts.count, 2)
        XCTAssertNotNil(store.consider(context: on, found: finds, now: now))
        XCTAssertEqual(store.data.lastShown, now)
        XCTAssertNil(store.consider(context: on, found: finds, now: now.addingTimeInterval(60)), "shown this week")
        XCTAssertEqual(store.suggestions(now: now), ["conditionals"])

        store.dismiss(now: now)
        XCTAssertNil(store.consider(context: on, found: finds, now: now.addingTimeInterval(8 * day)), "dismissed: a month")
        store.neverAgain()
        XCTAssertNil(store.consider(context: on, found: finds, now: now.addingTimeInterval(60 * day)))
    }

    func testPersistsAcrossLaunches() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("coach-invite-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = CoachInviteStore(file: file)
        store.neverAgain()
        _ = store.consider(context: on, found: [found("articles")], now: now)
        let reopened = CoachInviteStore(file: file)
        XCTAssertTrue(reopened.data.never)
        XCTAssertEqual(reopened.data.drafts.map(\.patterns), [["articles"]])
    }

    func testCoachOnRecordsNothing() {
        let store = CoachInviteStore(file: nil)
        var context = on
        context.coachOn = true
        _ = store.consider(context: context, found: [found("articles")], now: now)
        XCTAssertTrue(store.data.drafts.isEmpty)
    }
}
