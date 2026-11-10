import AppKit
import SwiftUI

/// The panel's redesigned screens for `--snapshot`, light and dark: compose with its one-row presets and the run
/// options popover, the takes with the coach collapsed and expanded, the coach invitation, limits and errors, a take
/// cut short, and the paste toast.
@MainActor
extension Snapshot {
    static func renderPanel(to folder: URL) {
        Store.readOnly = true
        let store = Store.shared
        let savedCoach = store.settings.coach
        let savedHistory = store.history
        defer {
            store.settings.coach = savedCoach
            store.history = savedHistory
        }
        store.settings.coach = CoachSettings()

        let draft = "If you will send me the file until tomorrow, I will check it and make you a feedback. I am working here since 2020, so I know what means this error."
        let takes = [
            "Send me the file by tomorrow and I'll review it and give you feedback. I've worked here since 2020, so I know this error well.",
            "Please send me the file by tomorrow. I'll check it and share my feedback, since I've been here since 2020 and know this error well.",
            "Can you send me the file by tomorrow? I'll review it and get back to you with feedback. I've seen this error many times since 2020.",
        ]
        func model(_ text: String = draft) -> PanelModel {
            let model = PanelModel()
            model.reset(focus: FocusSnapshot(app: nil, text: text, source: .field, caretRect: nil), presetID: store.presets.first?.id)
            model.previewAppName = "Slack"
            model.previewAppURL = AppGlyph.url(forBundleID: "com.tinyspeck.slackmacgap")
            return model
        }
        func takesModel() -> PanelModel {
            let model = model()
            model.screen = .takes
            model.sourceDraft = draft
            model.takes = takes
            model.timing = "first words 1.6 s · all takes 3.9 s"
            return model
        }

        // Compose: the Slack draft with history saying which presets get used in Slack.
        let slack = "ya thursday works but i need the specs by wed eod otherwise qa slips again, also can someone own the release notes this time"
        let presets = store.presets
        if presets.count > 4 {
            store.history = [presets[3], presets[3], presets[1], presets[1], presets[1]].map {
                HistoryEntry(appName: "Slack", presetName: $0.name, draft: "", takes: [])
            }
        }
        let compose = model(slack)
        // The chosen preset has its own hotkey, so the footer reminds you of it.
        let withHotKey = model(slack)
        // Opened with the summon hotkey, not the preset's own one.
        withHotKey.reset(focus: FocusSnapshot(app: nil, text: slack, source: .field, caretRect: nil), presetID: nil)
        if var preset = presets.first {
            preset.hotKey = KeyCombo(keyCode: 3, modifiers: 0x0A00, display: "⌥⇧F")
            withHotKey.previewPreset = preset
        }
        let options = model(slack)
        options.optionsOpen = true
        let changed = model(slack)
        changed.takeCount = 5
        changed.effort = "medium"
        changed.optionsOpen = true

        let collapsed = takesModel()
        collapsed.coach.preview(.done(.init(findings: sampleFindings)))
        let expanded = takesModel()
        expanded.coach.preview(.done(.init(findings: sampleFindings)))
        expanded.coachExpanded = true
        let checking = takesModel()
        checking.coach.preview(.checking)
        let changes = takesModel()
        changes.optionHeld = true
        changes.selected = 1

        let invited = takesModel()
        invited.invitation = CoachInvitation.Offer(found: [
            .init(pattern: "conditionals", fix: .init(removed: "If you will send", added: "If you send")),
            .init(pattern: "timeExpressions", fix: .init(removed: "until tomorrow", added: "by tomorrow")),
            .init(pattern: "collocations", fix: .init(removed: "make you a feedback", added: "give you feedback")),
        ], repeating: ["conditionals"], drafts: 4)

        // Limits: the engine's account is out of credit, at its plan limit, or rate limited.
        func limitModel(_ error: Error) -> PanelModel {
            let model = takesModel()
            model.takes = []
            model.timing = ""
            model.error = error.localizedDescription
            model.limit = error as? UsageLimitError
            return model
        }
        let limits = [
            ("10-limit-out-of-credit", limitModel(APIEngine.apiError(status: 400, type: "invalid_request_error",
                                                                     message: "Your credit balance is too low", retryAfter: nil))),
            ("11-limit-plan", limitModel(ClaudeCodeEngine.resultError("5-hour limit reached ∙ resets 3pm"))),
            ("12-limit-rate", limitModel(ProviderEngine.httpError(status: 429, body: Data(), provider: .openAI, model: "", retryAfter: "20"))),
        ]

        // The model stopped before the end of the last take: it's marked and can't be pasted.
        let cutShort = takesModel()
        cutShort.takes[2] = "Can you send me the file by tomorrow? I'll review it and get back to you with"
        cutShort.cutShort = true
        cutShort.selected = 2
        // An error after part of a take arrived: only the notice and the way back.
        let failed = takesModel()
        failed.takes = [String(takes[0].prefix(40))]
        failed.timing = ""
        failed.error = "The connection was lost. Check your network and try again."
        let ends = [("13-takes-cut-short", cutShort), ("14-takes-error", failed)]

        let toast = ToastView(message: "Pasted take 1 · your clipboard is back", showUndo: true,
                              coachNote: "“If you will send” → “If you send” · 4th time this month",
                              onSaveExample: {}, onDone: {})
        // The text box changed before the paste: the take waits on the clipboard instead.
        let notPasted = ToastView(message: PanelController.notPastedMessage(.fieldChanged, app: "Slack", number: 2), showUndo: false,
                                  notDone: true, onSaveExample: nil, onDone: {})

        // What the compose row says when the text box wasn't read: too long, a password field, nothing selected.
        func unread(_ source: FocusSnapshot.Source, method: String = "") -> PanelModel {
            let model = PanelModel()
            var focus = FocusSnapshot(app: nil, text: "", source: source, caretRect: nil)
            focus.method = method
            model.reset(focus: focus, presetID: store.presets.first?.id)
            model.previewAppName = "Slack"
            model.previewAppURL = AppGlyph.url(forBundleID: "com.tinyspeck.slackmacgap")
            return model
        }
        let unreadBoxes = [("1b-compose-too-long", unread(.tooLong)), ("1c-compose-password", unread(.secure)),
                           ("1d-compose-nothing-selected", unread(.field, method: FocusSnapshot.noSelection))]

        for (dark, suffix) in [(false, "light"), (true, "dark")] {
            func write<V: View>(_ view: V, _ size: CGSize, _ name: String) {
                try? themedBitmap(of: view, size: size, dark: dark)?.representation(using: .png, properties: [:])?
                    .write(to: folder.appendingPathComponent("panel-\(name)-\(suffix).png"))
            }
            let compose720 = CGSize(width: 720, height: ComposeView.height)
            write(PanelRootView(model: compose), compose720, "1-compose")
            write(PanelRootView(model: options), compose720, "2-compose-options")
            write(PanelRootView(model: changed), compose720, "3-compose-options-changed")
            write(PanelRootView(model: withHotKey), compose720, "3b-compose-preset-hotkey")
            for (name, model) in unreadBoxes { write(PanelRootView(model: model), compose720, name) }
            for (name, model) in [("4-takes-coach-collapsed", collapsed), ("5-takes-coach-expanded", expanded),
                                  ("6-takes-coach-checking", checking), ("7-takes-changes-option-held", changes),
                                  ("8-takes-coach-invitation", invited)] + limits + ends {
                write(PanelRootView(model: model), CGSize(width: 1060, height: fittedHeight(model)), name)
            }
            write(toast.padding(20).frame(width: 820, height: 140).background(Color(hex: dark ? "#3A3A3F" : "#E9E7E1")),
                  CGSize(width: 820, height: 140), "9-toast")
            write(notPasted.padding(20).frame(width: 820, height: 100).background(Color(hex: dark ? "#3A3A3F" : "#E9E7E1")),
                  CGSize(width: 820, height: 100), "9b-toast-not-pasted")
        }
    }

    static let sampleFindings: [CoachCheck.Finding] = [
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
    ]
}
