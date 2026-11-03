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

        func tab(_ screen: CoachScreen) -> some View {
            let state = SettingsState()
            state.tab = .coach
            state.coachScreen = screen
            return SettingsView(state: state)
        }
        let size = CGSize(width: 1200, height: 860)

        store.settings.coach = CoachSettings()
        render(tab(.home), size: size, to: folder.appendingPathComponent("coach-1-off.png"))
        render(tab(.setup), size: size, to: folder.appendingPathComponent("coach-2-setup.png"))

        var on = CoachSettings()
        on.enabled = true
        on.focus = ["conditionals", "presentPerfect"]
        on.goals = ["Use more phrasal verbs", "Sound less formal in Slack"]
        store.settings.coach = on
        CoachStore.shared.data = sampleData()
        render(tab(.home), size: size, to: folder.appendingPathComponent("coach-3-overview.png"))
        render(tab(.lesson("conditionals")), size: size, to: folder.appendingPathComponent("coach-4-lesson.png"))

        CoachStore.shared.data = CoachData()
        render(tab(.home), size: size, to: folder.appendingPathComponent("coach-5-overview-empty.png"))

        let draft = "If you will send me the link today I will review it tomorrow, I did a mistake in the dashboard numbers."
        let model = PanelModel()
        model.reset(focus: FocusSnapshot(app: nil, text: draft, source: .field, caretRect: nil), presetID: store.presets.first?.id)
        model.previewAppName = "Slack"
        model.screen = .takes
        model.sourceDraft = draft
        model.takes = [
            "If you send me the link today, I'll review it tomorrow. I made a mistake in the dashboard numbers.",
            "Send me the link today and I'll look at it tomorrow. Heads up: I made a mistake in the dashboard numbers.",
            "Link today → review tomorrow. Also, the dashboard numbers had a mistake on my side.",
        ]
        model.timing = "first words 1.3 s · all takes 2.8 s"
        model.coach.preview(.done(.init(findings: [
            .init(pattern: "conditionals", wrong: "If you will send", right: "If you send", why: "present after “if”"),
            .init(pattern: "collocations", wrong: "I did a mistake", right: "I made a mistake", why: "you make a mistake"),
        ], tips: [.init(goal: "Use more phrasal verbs", wrong: "review it", better: "look it over")])))
        render(PanelRootView(model: model), size: CGSize(width: 1060, height: fittedHeight(model)),
               to: folder.appendingPathComponent("coach-6-takes.png"))

        let toast = ToastView(message: "Pasted take 1 · your clipboard is back", showUndo: true,
                              coachNote: "“If you will send” → “If you send” · 11th time this month · lesson ready",
                              onSaveExample: {}, onDone: {})
            .padding(20).background(Color(hex: "#E9E7E1"))
        render(toast, size: CGSize(width: 820, height: 140), to: folder.appendingPathComponent("coach-7-toast.png"))
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
