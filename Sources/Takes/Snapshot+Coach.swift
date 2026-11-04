import AppKit
import SwiftUI

/// English coach screens for `--snapshot`: the tab off, setup, the overview with sample data, a lesson,
/// the takes screen's notes and the paste toast's nudge.
@MainActor
extension Snapshot {
    static func renderCoach(to folder: URL) {
        Store.readOnly = true
        let store = Store.shared
        let saved = store.settings.coach
        let savedData = CoachStore.shared.data
        defer {
            store.settings.coach = saved
            CoachStore.shared.data = savedData
        }

        // The coach tab on its own, at the Settings window's new width, light and dark.
        func page<V: View>(_ view: V, _ name: String, height: CGFloat = 720) {
            for (dark, suffix) in [(false, "light"), (true, "dark")] {
                try? themedBitmap(of: view, size: CGSize(width: 780, height: height), dark: dark)?
                    .representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("\(name)-\(suffix).png"))
            }
        }
        func tab(_ screen: CoachScreen) -> some View {
            let state = SettingsState()
            state.tab = .coach
            state.coachScreen = screen
            return EnglishCoachTab(state: state)
        }
        func setup(step: Int, picking: Bool = false, editingPresets: Bool = false) -> some View {
            let state = SettingsState()
            state.coachScreen = .setup
            return ZStack {
                CoachIntroView(state: state)
                Color.black.opacity(0.28)
                CoachSetupView(state: state, suggested: ["conditionals", "prepositions", "collocations"], step: step,
                               picking: picking, editingPresets: editingPresets)
            }
            .background(Theme.surface)
        }

        store.settings.coach = CoachSettings()
        page(tab(.home), "coach-1-off")
        page(setup(step: 1), "coach-2a-setup-focus")
        page(setup(step: 1, picking: true), "coach-2b-setup-focus-pick")
        page(setup(step: 2), "coach-2c-setup-language")
        page(setup(step: 3), "coach-2d-setup-presets")
        page(setup(step: 3, editingPresets: true), "coach-2e-setup-presets-edit")

        var on = CoachSettings()
        on.enabled = true
        on.focus = ["conditionals", "presentPerfect"]
        on.goals = ["Use more phrasal verbs", "Sound less formal in Slack"]
        store.settings.coach = on
        CoachStore.shared.data = sampleData()
        page(tab(.home), "coach-3-overview", height: 760)
        page(tab(.lesson("conditionals")), "coach-4-lesson")
        page(tab(.lesson("gerundInfinitive")), "coach-4b-lesson-new-pattern")
        // The old 1200 pt window, to check the pages still sit well in a wide one.
        let wide = SettingsState()
        wide.tab = .coach
        render(SettingsView(state: wide), size: CGSize(width: 1200, height: 860), to: folder.appendingPathComponent("coach-3-overview-wide.png"))

        CoachStore.shared.data = CoachData()
        page(tab(.home), "coach-5-overview-empty")

        let draft = "If you will send me the file until tomorrow, I will check it and make you a feedback. I am working here since 2020, so I know what means this error."
        let model = PanelModel()
        model.reset(focus: FocusSnapshot(app: nil, text: draft, source: .field, caretRect: nil), presetID: store.presets.first?.id)
        model.previewAppName = "Slack"
        model.screen = .takes
        model.sourceDraft = draft
        model.takes = [
            "Send me the file by tomorrow and I'll review it and give you feedback. I've worked here since 2020, so I know this error well.",
            "Please send me the file by tomorrow. I'll check it and share my feedback, since I've been here since 2020 and know this error well.",
            "Can you send me the file by tomorrow? I'll review it and get back to you with feedback. I've seen this error many times since 2020.",
        ]
        model.timing = "first words 1.6 s · all takes 3.9 s"
        model.coach.preview(.checking)
        render(PanelRootView(model: model), size: CGSize(width: 1060, height: fittedHeight(model)),
               to: folder.appendingPathComponent("coach-6a-takes-checking.png"))
        model.coach.preview(.done(.init(findings: [
            .init(pattern: "conditionals", wrong: "If you will send", right: "If you send",
                  why: "A future condition takes the present after \"if\"; \"will\" goes in the result."),
            .init(pattern: "timeExpressions", wrong: "until tomorrow", right: "by tomorrow",
                  why: "\"By\" sets a deadline; \"until\" means continuing up to then."),
            .init(pattern: "collocations", wrong: "make you a feedback", right: "give you feedback", why: "You give feedback, not make it."),
            .init(pattern: "countable", wrong: "a feedback", right: "feedback", why: "\"Feedback\" is uncountable here, so no \"a\"."),
            .init(pattern: "presentPerfect", wrong: "I am working here since", right: "I've been working here since",
                  why: "With \"since\", a situation running up to now takes the present perfect."),
            .init(pattern: "wordOrder", wrong: "what means this error", right: "what this error means",
                  why: "Inside a sentence, a question keeps normal word order."),
        ])))
        render(PanelRootView(model: model), size: CGSize(width: 1060, height: fittedHeight(model)),
               to: folder.appendingPathComponent("coach-6-takes.png"))

    }

    private static func sampleData() -> CoachData {
        let now = Date()
        func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86400) }
        var data = CoachData()
        data.drafts = (0..<214).map { CoachDraftRecord(date: ago(Double($0) * 0.14), words: 46) }
        func add(_ pattern: String, _ wrong: String, _ right: String, _ app: String, days: [Double]) {
            for day in days {
                data.sightings.append(CoachSighting(date: ago(day), finding: .init(pattern: pattern, wrong: wrong, right: right, why: ""), app: app))
            }
        }
        add("conditionals", "if you will send", "if you send", "Slack", days: [1, 3, 4, 6, 8, 10, 12, 18, 22, 25, 27])
        add("articles", "send me link to dashboard", "send me the link to the dashboard", "Slack",
            days: [0.2, 1, 2, 4, 5, 9, 11, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29])
        add("presentPerfect", "I work on it since Monday", "I’ve been working on it since Monday", "Mail",
            days: [2, 4, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29])
        add("prepositions", "waiting to your answer", "waiting for your answer", "Mail", days: [4, 8, 16, 19, 20, 22, 24, 26, 28])
        add("collocations", "I did a mistake", "I made a mistake", "Linear", days: [3, 5, 6, 8, 9, 10, 11, 12])
        data.lessonsRead["conditionals"] = ago(9)
        data.tips = (0..<12).map { CoachTipRecord(date: ago(Double($0) * 2), tip: .init(goal: "Use more phrasal verbs", wrong: "", better: "")) }
        data.tokens[CoachStore.month(now)] = 257_000
        data.checks[CoachStore.month(now)] = 214
        return data
    }
}
