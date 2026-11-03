import AppKit
import SwiftUI

/// Where Settings › English coach is. `home` is the intro while the coach is off and the overview once it's on.
enum CoachScreen: Hashable {
    case home, setup
    case lesson(String)
}

// MARK: - Takes screen

/// "English coach · 2 notes" under the draft on the takes screen: what the check found, each with a reason and a
/// "Not a mistake" button. Nothing shows while the coach is off or found nothing.
struct CoachStrip: View {
    @ObservedObject var run: CoachRun

    var body: some View {
        if !run.findings.isEmpty || !run.tips.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.item) {
                HStack(spacing: Spacing.item) {
                    Text("English coach").font(.system(size: 12, weight: .bold))
                    Text(summary).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                }
                ForEach(Array(run.findings.enumerated()), id: \.element) { index, finding in
                    HStack(spacing: Spacing.item) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Theme.accent))
                        CoachFix(wrong: finding.wrong, right: finding.right)
                        Text("· \(finding.why)").font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                        Spacer(minLength: 0)
                        Button("Not a mistake") { run.dismiss(finding) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                ForEach(run.tips, id: \.self) { tip in
                    HStack(spacing: Spacing.item) {
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.doText)
                            .frame(width: 18)
                        Text("\(tip.goal):").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.doText)
                        (Text("“\(tip.wrong)” could be ") + Text("“\(tip.better)”").fontWeight(.semibold))
                            .font(.system(size: 13)).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.inner)
            RowDivider()
        }
    }

    private var summary: String {
        let n = run.findings.count
        return n == 0 ? "a tip for your goals" : "\(n) note\(n == 1 ? "" : "s") on your draft · kept when you paste"
    }
}

/// "if you will send → if you send": the old words struck through, the fix in green.
struct CoachFix: View {
    let wrong: String
    let right: String
    var size: CGFloat = 13
    var lines: Int? = 1

    var body: some View {
        (Text(wrong).strikethrough().foregroundStyle(Theme.avoidText) + Text("  →  ").foregroundStyle(Theme.tertiaryText)
            + Text(right).fontWeight(.semibold).foregroundStyle(Theme.doText))
            .font(.system(size: size))
            .lineLimit(lines)
            .fixedSize(horizontal: false, vertical: lines == nil)
    }
}

// MARK: - Settings tab

struct EnglishCoachTab: View {
    @ObservedObject var state: SettingsState
    @ObservedObject var store = Store.shared

    var body: some View {
        Group {
            switch state.coachScreen {
            case .setup: CoachSetupView(state: state)
            case .lesson(let id):
                if let pattern = CoachGuide.pattern(id) { CoachLessonView(state: state, pattern: pattern) } else { overviewOrIntro }
            case .home: overviewOrIntro
            }
        }
        .background(Theme.surface)
    }

    @ViewBuilder private var overviewOrIntro: some View {
        if store.settings.coach.enabled { CoachOverviewView(state: state) } else { CoachIntroView(state: state) }
    }
}

/// "‹ English coach": a quiet back button above a screen's title.
struct CoachBackButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(hovering ? Theme.text : Theme.secondaryText)
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Theme.kbdFill : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.leading, -4)
    }
}

/// An on/off switch drawn in the theme's colors.
struct CoachSwitch: View {
    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 10) {
                Text(isOn ? "On" : "Off").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                Capsule()
                    .fill(isOn ? Theme.accent : Theme.controlBorder)
                    .frame(width: 38, height: 22)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle().fill(isOn ? Theme.onAccent : Theme.surface).frame(width: 18, height: 18).padding(2)
                            .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "on" : "off")
    }
}

/// "Nudges ▾": a menu whose choices each carry a line on what they do.
struct NudgesMenu: View {
    @Binding var selection: CoachSettings.Nudges
    var showsChoice = false

    var body: some View {
        Button(action: showMenu) {
            HStack(spacing: 6) {
                Text(showsChoice ? selection.title : "Nudges").font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Theme.text)
        }
        .buttonStyle(SecondaryButtonStyle(height: 30))
        .help(selection.detail)
    }

    private func showMenu() {
        let menu = NSMenu()
        for option in CoachSettings.Nudges.allCases {
            let item = ClosureMenuItem(title: option.title) { selection = option }
            item.state = option == selection ? .on : .off
            if #available(macOS 14.4, *) { item.subtitle = option.detail } else { item.toolTip = option.detail }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let note = NSMenuItem(title: "Never more than one nudge per paste", action: nil, keyEquivalent: "")
        note.isEnabled = false
        menu.addItem(note)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// Small caps heading used across the coach screens ("WHAT IT WATCHES").
struct CoachHeading: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .bold)).kerning(0.6).foregroundStyle(Theme.secondaryText)
    }
}

enum CoachCopy {
    static let tokens = "Each English draft gets one extra check on your engine’s quick model: about 1,000 tokens, roughly 40% on top of a typical 3-take run. Lessons are put together on this Mac from a built-in guide, so they cost nothing."
    static let billing = "Claude Code or ChatGPT: counts toward your plan. An API key (Anthropic, OpenAI or other): billed like any run. A local model: free, but slower and less accurate. Usage is shown here every month."
    static let privacy = "Only the phrase around each mistake is kept, never your whole message, for 30 days. Your draft goes to your engine, as it already does for takes. Turning the coach off deletes everything it kept."

    static func engineName(_ settings: AppSettings) -> String {
        let engine: String
        switch settings.engine {
        case .claudeCode: engine = "Claude Code"
        case .apiKey: engine = "Anthropic API key"
        case .local: engine = "Local model"
        case .provider: engine = "API key"
        case .chatGPT: engine = "ChatGPT"
        }
        let model = settings.quickModel
        return model.isEmpty ? engine : "\(engine) · \(Models.label(model))"
    }
}

// MARK: Intro (coach off)

struct CoachIntroView: View {
    @ObservedObject var state: SettingsState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("English coach").font(.system(size: 24, weight: .bold))
                        Text("Learn from the English you already write. The coach spots the mistakes your takes fix, finds the ones you repeat, and turns them into short lessons built from your own sentences.")
                            .font(.system(size: 14)).foregroundStyle(Theme.secondaryText).frame(maxWidth: 680, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    CoachSwitch(isOn: Binding(get: { false }, set: { if $0 { state.coachScreen = .setup } }), label: "English coach")
                }

                VStack(alignment: .leading, spacing: 10) {
                    CoachHeading("What it watches")
                    HStack(alignment: .top, spacing: 12) {
                        card("Grammar", "Tenses, conditionals, articles, prepositions, -ing or to, countable nouns, word order and more.", "if you will send", "if you send")
                        card("Word choice", "The right word for what you mean: word pairs, false friends, set phrases, too and very.", "close the light", "turn off the light")
                        card("Natural phrasing", "Correct, but not how a native speaker would say it, or more direct than you meant.", "What’s with the report?", "Any update on the report?")
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Goals, not mistakes").font(.system(size: 14, weight: .bold))
                            Text("How you want to sound: less formal, more phrasal verbs. Tracked as tips.")
                                .font(.system(size: 12)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
                            Text("Never counted: typos, casual Slack style, names, code.")
                                .font(.system(size: 12)).foregroundStyle(Theme.tertiaryText).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.strip))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    CoachHeading("What it does")
                    HStack(alignment: .top, spacing: 12) {
                        does("Notes with your takes", "A short list under your draft, each with a one-line reason.")
                        does("A nudge after paste", "One line in the paste toast, only when a pattern repeats.")
                        does("Short lessons", "A rule and your own sentences, once a pattern shows up \(CoachStore.lessonAt) times. Practice is your next drafts.")
                        does("Progress", "Mistakes per 1,000 words, trends, and patterns you’ve mastered.")
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Uses extra tokens").font(.system(size: 14, weight: .bold)).foregroundStyle(Color(hex: "#5C4605"))
                        Text(CoachCopy.tokens).font(.system(size: 13)).foregroundStyle(Theme.controlText).fixedSize(horizontal: false, vertical: true)
                        Text(CoachCopy.billing).font(.system(size: 12)).foregroundStyle(Color(hex: "#5C4605")).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.dynamic(light: "#FBF6E6", dark: "#3A3320")))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.dynamic(light: "#E8D9A8", dark: "#5A4E2E")))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Stays on this Mac").font(.system(size: 14, weight: .bold))
                        Text(CoachCopy.privacy).font(.system(size: 13)).foregroundStyle(Theme.controlText).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.strip))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Spacer()
                    Text("Off by default. You choose what it watches next.").font(.system(size: 12)).foregroundStyle(Theme.tertiaryText)
                    Button("Turn on English coach…") { state.coachScreen = .setup }.buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
    }

    private func card(_ title: String, _ detail: String, _ wrong: String, _ right: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 14, weight: .bold))
            Text(detail).font(.system(size: 12)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            CoachFix(wrong: wrong, right: right, size: 12, lines: nil)
        }
        .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }

    private func does(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 13, weight: .bold))
            Text(detail).font(.system(size: 13)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: Setup

struct CoachSetupView: View {
    @ObservedObject var state: SettingsState
    @ObservedObject var store = Store.shared
    /// Edited here, saved by Start (or Save once the coach is on).
    @State private var draft = Store.shared.settings.coach

    private var editing: Bool { store.settings.coach.enabled }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        CoachBackButton(title: "English coach") { state.coachScreen = .home }
                            .padding(.bottom, 4)
                        Text(editing ? "What your English coach watches" : "Set up your English coach").font(.system(size: 24, weight: .bold))
                        Text(editing ? "Changes apply to your next drafts." : "Pick what to watch. Nothing is checked until you press Start, and you can change any of this later.")
                            .font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
                    }

                    HStack(alignment: .top, spacing: 32) {
                        VStack(alignment: .leading, spacing: 14) {
                            step(1, "What do you want to work on?")
                            Text("Your picks are focus areas: nudged after paste and listed first.")
                                .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                            Button("Find the others for me too") { draft.findAll.toggle() }
                                .buttonStyle(PillButtonStyle(selected: draft.findAll))
                            ForEach(CoachGuide.Group.allCases, id: \.self) { group in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(group.rawValue).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.secondaryText)
                                        .frame(width: 110, alignment: .leading).padding(.top, 9)
                                    FlowLayout(spacing: 8) {
                                        ForEach(CoachGuide.patterns.filter { $0.group == group }) { pattern in
                                            Button(pattern.name) { toggleFocus(pattern.id) }
                                                .buttonStyle(PillButtonStyle(selected: draft.focus.contains(pattern.id)))
                                                .help(CoachGuide.optIn.contains(pattern.id) ? "Only checked when picked. " + pattern.definition : pattern.definition)
                                        }
                                    }
                                }
                            }
                            HStack(alignment: .top, spacing: 8) {
                                Text("Goals").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.secondaryText)
                                    .frame(width: 110, alignment: .leading).padding(.top, 6)
                                ChipsEditor(items: $draft.goals, style: .positive)
                            }
                            HStack(spacing: 8) {
                                Text("English").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.secondaryText)
                                    .frame(width: 110, alignment: .leading)
                                ChoiceSegments(options: [(CoachSettings.Variant.us, "US"), (.uk, "UK")], selection: $draft.variant)
                            }

                            step(2, "Your first language").padding(.top, 8)
                            HStack(spacing: 12) {
                                MenuPicker(options: Languages.common.filter { $0 != "en" }.map { ($0, Languages.englishName($0)) },
                                           selection: $draft.firstLanguage)
                                Text(firstLanguageNote).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                            }

                            step(3, "Nudges after paste").padding(.top, 8)
                            HStack(spacing: 12) {
                                NudgesMenu(selection: $draft.nudges, showsChoice: true)
                                Text(draft.nudges.detail).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 12) {
                            step(4, "Which presets count")
                            Text("Only drafts you write in English are checked. Presets that translate into another language start off.")
                                .font(.system(size: 13)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
                            RowGroup {
                                ForEach(store.presets) { preset in
                                    HStack(spacing: 10) {
                                        Checkbox(isOn: Binding(get: { draft.counts(preset) }, set: { draft.presetCounts[preset.id] = $0 }),
                                                 label: preset.name)
                                        PresetDot(hex: preset.colorHex)
                                        Text(preset.name).font(.system(size: 14))
                                            .foregroundStyle(draft.counts(preset) ? Theme.text : Theme.secondaryText)
                                        Spacer()
                                        if preset.isMinimalEdits {
                                            Text("best signal").font(.system(size: 12)).foregroundStyle(Theme.doText)
                                        }
                                    }
                                    .padding(.horizontal, 14).frame(height: 40)
                                    if preset.id != store.presets.last?.id { RowDivider() }
                                }
                            }
                        }
                        .frame(width: 380)
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 28)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity)
            }

            RowDivider()
            HStack(spacing: 16) {
                (Text("About 1,000 extra tokens per English draft").fontWeight(.semibold).foregroundStyle(Color(hex: "#8A6A0A"))
                 + Text(" (one check on your engine’s quick model, ~40% on top of a run). Lessons are free. Keeps only the phrase around each mistake, on this Mac, for 30 days."))
                    .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(editing ? "Cancel" : "Not now") { state.coachScreen = .home }.buttonStyle(SecondaryButtonStyle(height: 36))
                Button(editing ? "Save" : "Start coaching") {
                    draft.enabled = true
                    store.settings.coach = draft
                    state.coachScreen = .home
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!draft.findAll && draft.focus.isEmpty)
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 16)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
    }

    private var firstLanguageNote: String {
        CoachGuide.patterns.contains { $0.firstLanguage[draft.firstLanguage] != nil }
            ? "Lessons explain why a mistake feels right in \(Languages.englishName(draft.firstLanguage))."
            : "Lessons have notes for Hebrew so far; other languages get the rule and your examples."
    }

    private func toggleFocus(_ id: String) {
        if let i = draft.focus.firstIndex(of: id) { draft.focus.remove(at: i) } else { draft.focus.append(id) }
    }

    private func step(_ number: Int, _ title: String) -> some View {
        HStack(spacing: 10) {
            Text("\(number)").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.onAccent)
                .frame(width: 22, height: 22).background(Circle().fill(Theme.accent))
            Text(title).font(.system(size: 15, weight: .bold))
        }
    }
}

// MARK: Overview

struct CoachOverviewView: View {
    @ObservedObject var state: SettingsState
    @ObservedObject var store = Store.shared
    @ObservedObject var coach = CoachStore.shared
    @State private var confirmOff = false

    private static let columns: [GridItem] = []

    var body: some View {
        let stats = coach.stats()
        let focus = store.settings.coach.focus
        let sorted = stats.filter { focus.contains($0.id) } + stats.filter { !focus.contains($0.id) }
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("English coach").font(.system(size: 22, weight: .bold))
                            Text("Last 30 days · \(coach.data.drafts.count) English draft\(coach.data.drafts.count == 1 ? "" : "s") · \(coach.words.formatted()) words")
                                .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Button("What it watches") { state.coachScreen = .setup }.buttonStyle(SecondaryButtonStyle(height: 30))
                        NudgesMenu(selection: $store.settings.coach.nudges)
                        CoachSwitch(isOn: Binding(get: { true }, set: { if !$0 { confirmOff = true } }), label: "English coach")
                    }

                    if sorted.isEmpty {
                        emptyState
                    } else {
                        table(sorted, focus: focus)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
            }
            .frame(maxWidth: .infinity)

            Rectangle().fill(Theme.border).frame(width: 1)
            sidebar.frame(width: 300)
        }
        .alert("Turn off the English coach?", isPresented: $confirmOff) {
            Button("Turn off and delete", role: .destructive) {
                store.settings.coach.enabled = false
                coach.deleteAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Drafts stop being checked, and everything the coach kept on this Mac is deleted.")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing yet").font(.system(size: 15, weight: .bold))
            Text("Write and paste a few English drafts. Notes show with your takes right away; trends here mean more after about 1,500 words.")
                .font(.system(size: 13)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.strip))
    }

    private func table(_ stats: [CoachStore.PatternStats], focus: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            row(pattern: Text("Pattern"), rate: Text("Per 1,000 words"), weeks: Text("4 weeks"), latest: Text("Latest, from your drafts"),
                lesson: Text("Lesson"))
                .font(.system(size: 11, weight: .semibold)).kerning(0.5).textCase(.uppercase).foregroundStyle(Theme.tertiaryText)
                .padding(.horizontal, 16)
            RowGroup {
                ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                    statRow(stat, focus: focus.contains(stat.id))
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(index % 2 == 0 ? Theme.strip.opacity(0.5) : .clear)
                    if index < stats.count - 1 { RowDivider() }
                }
            }
        }
    }

    private func row<A: View, B: View, C: View, D: View, E: View>(pattern: A, rate: B, weeks: C, latest: D, lesson: E) -> some View {
        HStack(spacing: 16) {
            pattern.frame(width: 180, alignment: .leading)
            rate.frame(width: 110, alignment: .leading)
            weeks.frame(width: 96, alignment: .leading)
            latest.frame(maxWidth: .infinity, alignment: .leading)
            lesson.frame(width: 130, alignment: .center)
        }
    }

    private func statRow(_ stat: CoachStore.PatternStats, focus: Bool) -> some View {
        row(pattern: VStack(alignment: .leading, spacing: 4) {
                Text(stat.pattern.name).font(.system(size: 14, weight: .semibold))
                if focus {
                    Text("Focus").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                        .padding(.horizontal, 7).padding(.vertical, 1).background(Capsule().fill(Theme.accentSoft))
                } else {
                    Text(stat.pattern.group.rawValue).font(.system(size: 12)).foregroundStyle(Theme.tertiaryText)
                }
            },
            rate: VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.1f", stat.rate)).font(.system(size: 18, weight: .bold))
                Text(trendLabel(stat)).font(.system(size: 12)).foregroundStyle(trendColor(stat))
            },
            weeks: CoachSparkline(values: stat.weekly, color: trendColor(stat)).frame(width: 90, height: 26),
            latest: VStack(alignment: .leading, spacing: 2) {
                if let latest = stat.latest {
                    CoachFix(wrong: latest.finding.wrong, right: latest.finding.right, lines: 2)
                    Text("\(latest.app) · \(latest.date.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 12)).foregroundStyle(Theme.tertiaryText)
                }
            },
            lesson: Group {
                if stat.count >= CoachStore.lessonAt || coach.data.lessonsRead[stat.id] != nil {
                    Button("Open") { open(stat.id) }.buttonStyle(SecondaryButtonStyle(height: 30))
                } else {
                    let left = CoachStore.lessonAt - stat.count
                    Text("Lesson after \(left) more")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Theme.kbdFill))
                        .help("A lesson is put together once a pattern shows up \(CoachStore.lessonAt) times.")
                }
            })
    }

    private func open(_ id: String) {
        coach.markRead(id)
        state.coachScreen = .lesson(id)
    }

    private func trendLabel(_ stat: CoachStore.PatternStats) -> String {
        let times = "\(stat.count) time\(stat.count == 1 ? "" : "s")"
        guard let trend = stat.trend else { return times }
        if abs(trend) < 0.1 { return "→ steady · \(times)" }
        return "\(trend > 0 ? "↑" : "↓") \(Int(abs(trend) * 100))% · \(times)"
    }

    private func trendColor(_ stat: CoachStore.PatternStats) -> Color {
        guard let trend = stat.trend, abs(trend) >= 0.1 else { return Theme.secondaryText }
        return trend > 0 ? Theme.avoidText : Theme.doText
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Focus areas").font(.system(size: 13, weight: .bold))
                    Text("Nudged after paste, and listed first.").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                    FlowLayout(spacing: 6) {
                        ForEach(store.settings.coach.focus, id: \.self) { id in
                            Text(CoachGuide.pattern(id)?.name ?? id).font(.system(size: 13))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent, lineWidth: 1.5))
                        }
                        Button("Edit") { state.coachScreen = .setup }.buttonStyle(DashedButtonStyle(capsule: false))
                    }
                }

                if !store.settings.coach.goals.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Goals").font(.system(size: 13, weight: .bold))
                        Text("Not mistakes: how you want to sound.").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                        ForEach(store.settings.coach.goals, id: \.self) { goal in
                            HStack {
                                Text(goal)
                                Spacer()
                                let tips = coach.tipCount(goal)
                                Text("\(tips) tip\(tips == 1 ? "" : "s")").font(.system(size: 12))
                            }
                            .font(.system(size: 13)).foregroundStyle(Theme.doText)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.doFill))
                        }
                    }
                }

                let mastered = coach.mastered()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mastered").font(.system(size: 13, weight: .bold))
                    if mastered.isEmpty {
                        Text("None yet.").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(mastered) { pattern in
                        HStack { Text(pattern.name); Spacer(); Image(systemName: "checkmark").foregroundStyle(Theme.doText) }
                            .font(.system(size: 13))
                    }
                    Text("Mastered: after its lesson, 3 weeks under 0.2 per 1,000 words.")
                        .font(.system(size: 12)).foregroundStyle(Theme.tertiaryText).fixedSize(horizontal: false, vertical: true)
                }

                if !coach.data.muted.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Not tracked").font(.system(size: 13, weight: .bold))
                        ForEach(coach.data.muted, id: \.self) { id in
                            HStack {
                                Text(CoachGuide.pattern(id)?.name ?? id).font(.system(size: 13))
                                Spacer()
                                Button("Track again") { coach.unmute(id) }.buttonStyle(.plain)
                                    .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tokens this month").font(.system(size: 13, weight: .bold))
                    HStack {
                        let checks = coach.checks()
                        Text("\(checks) check\(checks == 1 ? "" : "s")")
                        Spacer()
                        Text("≈ \(Self.compact(coach.tokens()))")
                    }
                    .font(.system(size: 13))
                    HStack { Text("Lessons"); Spacer(); Text("free") }.font(.system(size: 13))
                    Text("Estimated from text length. Runs on your engine, now \(CoachCopy.engineName(store.settings)). Change it in Engine.")
                        .font(.system(size: 12)).foregroundStyle(Theme.tertiaryText).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 16)
                .overlay(alignment: .top) { RowDivider() }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Stored only on this Mac for 30 days.")
                    Button("Clear coach data") { coach.clear() }.buttonStyle(.plain).foregroundStyle(Theme.controlText).underline()
                }
                .font(.system(size: 12)).foregroundStyle(Theme.tertiaryText)
            }
            .padding(24)
        }
        .background(Theme.strip)
    }

    static func compact(_ n: Int) -> String {
        n >= 1000 ? String(format: n >= 10_000 ? "%.0fk" : "%.1fk", Double(n) / 1000) : "\(n)"
    }
}

/// Four weekly counts as a small line.
struct CoachSparkline: View {
    let values: [Int]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let top = max(values.max() ?? 1, 1)
            let step = values.count > 1 ? geo.size.width / CGFloat(values.count - 1) : 0
            Path { path in
                for (i, value) in values.enumerated() {
                    let point = CGPoint(x: CGFloat(i) * step, y: geo.size.height - 3 - (geo.size.height - 6) * CGFloat(value) / CGFloat(top))
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityLabel("Weekly counts: " + values.map(String.init).joined(separator: ", "))
    }
}

// MARK: Lesson

struct CoachLessonView: View {
    @ObservedObject var state: SettingsState
    @ObservedObject var store = Store.shared
    @ObservedObject var coach = CoachStore.shared
    let pattern: CoachGuide.Pattern

    var body: some View {
        let sightings = coach.sightings(pattern.id)
        let examples = Array(sightings.reduce(into: [CoachSighting]()) { list, s in
            if !list.contains(where: { CoachCheck.normalized($0.finding.wrong) == CoachCheck.normalized(s.finding.wrong) }) { list.append(s) }
        }.prefix(4))
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    CoachBackButton(title: "English coach") { state.coachScreen = .home }.padding(.bottom, 4)
                    Text(pattern.name).font(.system(size: 22, weight: .bold))
                    Text("\(sightings.count) time\(sightings.count == 1 ? "" : "s") in 30 days\(apps(sightings)) · from the built-in guide and your own drafts")
                        .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            }
            .padding(.horizontal, 32).padding(.top, 20)

            HStack(alignment: .top, spacing: 24) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            CoachHeading("The rule")
                            Text(pattern.rule).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
                            Text(pattern.example).font(.system(size: 15, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                            if let note = pattern.firstLanguage[store.settings.coach.firstLanguage] {
                                Text("Why it slips: \(note)").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.strip))

                        if !examples.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                CoachHeading("From your drafts")
                                RowGroup {
                                    ForEach(Array(examples.enumerated()), id: \.element.id) { index, sighting in
                                        HStack(spacing: 16) {
                                            CoachFix(wrong: sighting.finding.wrong, right: sighting.finding.right, size: 14)
                                            Text(sighting.finding.why).font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                                            Spacer()
                                            Text("\(sighting.app) · \(sighting.date.formatted(date: .abbreviated, time: .omitted))")
                                                .font(.system(size: 12)).foregroundStyle(Theme.tertiaryText)
                                        }
                                        .padding(.horizontal, 14).padding(.vertical, 10)
                                        if index < examples.count - 1 { RowDivider() }
                                    }
                                }
                            }
                        }

                        if !pattern.contrasts.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                CoachHeading("Don’t mix them up")
                                RowGroup {
                                    ForEach(Array(pattern.contrasts.enumerated()), id: \.offset) { index, row in
                                        HStack(spacing: 12) {
                                            Text(row.label).font(.system(size: 13, weight: .semibold)).frame(width: 140, alignment: .leading)
                                            Text(row.example).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
                                            Text(row.form).font(.system(size: 13)).foregroundStyle(Theme.secondaryText).frame(width: 200, alignment: .leading)
                                        }
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(index % 2 == 0 ? Theme.strip : .clear)
                                        if index < pattern.contrasts.count - 1 { RowDivider() }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                practice.frame(width: 340)
            }
            .padding(.horizontal, 32).padding(.vertical, 20)
        }
    }

    private var practice: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Practice is your next drafts").font(.system(size: 15, weight: .bold))
                Text("No exercises. When this comes up in a draft, the coach notes it with your takes and counts it here.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                CoachHeading("Since you read this")
                let since = coach.sinceRead(pattern.id) ?? (0, 0)
                HStack { Text("English drafts"); Spacer(); Text("\(since.drafts)").fontWeight(.bold) }.font(.system(size: 13))
                HStack {
                    Text("Times it came back")
                    Spacer()
                    Text("\(since.slips)").fontWeight(.bold).foregroundStyle(since.slips == 0 ? Theme.doText : Theme.avoidText)
                }
                .font(.system(size: 13))
                Text("Mastered after 3 weeks under 0.2 per 1,000 words.")
                    .font(.system(size: 12)).foregroundStyle(Theme.tertiaryText).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Not a mistake for me") {
                    coach.mute(pattern.id)
                    state.coachScreen = .home
                }
                .buttonStyle(SecondaryButtonStyle())
                .help("Stop tracking this pattern. You can track it again from the overview.")
            }
        }
        .padding(18)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }

    private func apps(_ sightings: [CoachSighting]) -> String {
        var names: [String] = []
        for s in sightings where !names.contains(s.app) { names.append(s.app) }
        return names.isEmpty ? "" : ", in " + names.prefix(3).joined(separator: " and ")
    }
}
