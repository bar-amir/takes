import AppKit
import SwiftUI

/// Where Settings › English coach is. `home` is the intro while the coach is off and the overview once it's on.
enum CoachScreen: Hashable {
    case home, setup
    case lesson(String)
}

// MARK: - Takes screen

/// The English coach under the takes. While the check runs, a quiet shimmering line; then one line with the top
/// fix and its rule ("Coach · 6 notes · top: if you will send → if you send (Conditionals)"). ⌘; or a click shows
/// every fix as a chip; picking one shows why, and "Not a mistake" hides it for good. Nothing shows while the coach
/// is off or found nothing.
struct CoachStrip: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var run: CoachRun
    @State private var picked = 0

    var body: some View {
        Group {
            if run.state == .checking {
                card {
                    HStack(spacing: Spacing.item) {
                        Text("Coach").font(.system(size: 13, weight: .bold))
                        Text("· checking your English").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                        CoachShimmer().frame(maxWidth: 160, maxHeight: 6)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("English coach is checking your draft")
                }
            } else if !run.findings.isEmpty || !run.tips.isEmpty {
                card {
                    VStack(alignment: .leading, spacing: Spacing.item + 2) {
                        summaryLine
                        if model.coachExpanded {
                            if !run.findings.isEmpty {
                                FlowLayout(spacing: 6) {
                                    ForEach(Array(run.findings.enumerated()), id: \.element) { index, finding in
                                        chip(index, finding)
                                    }
                                }
                                if let finding = selected { detail(finding) }
                            }
                            ForEach(run.tips, id: \.self) { tip in
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.doText)
                                    Text("\(tip.goal):").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.doText)
                                    (Text("“\(tip.wrong)” could be ") + Text("“\(tip.better)”").fontWeight(.semibold))
                                        .font(.system(size: 12)).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// The finding the collapsed line leads with: the pattern the user repeats most, else the first.
    static func top(_ findings: [CoachCheck.Finding], counts: (String) -> Int) -> CoachCheck.Finding? {
        findings.enumerated().max { a, b in
            let ca = counts(a.element.pattern), cb = counts(b.element.pattern)
            return ca != cb ? ca < cb : a.offset > b.offset
        }?.element
    }

    private var summaryLine: some View {
        let n = run.findings.count
        let top = Self.top(run.findings) { CoachStore.shared.sightings($0).count }
        return Button { toggle() } label: {
            HStack(spacing: Spacing.item) {
                HStack(spacing: 0) {
                    Text("Coach").font(.system(size: 13, weight: .bold))
                    Text(n == 0 ? " · a tip for your goals" : " · \(n) note\(n == 1 ? "" : "s")\(top == nil || model.coachExpanded ? "" : " · top: ")")
                        .font(.system(size: 13)).foregroundStyle(Theme.controlText)
                    if let top, !model.coachExpanded {
                        CoachFix(wrong: top.wrong, right: top.right, size: 13).layoutPriority(-1)
                        if let rule = CoachGuide.pattern(top.pattern)?.name {
                            Text(" (\(rule.lowercased()))").font(.system(size: 13)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                                .layoutPriority(-2)
                        }
                    }
                }
                .lineLimit(1)
                Spacer(minLength: Spacing.item)
                HStack(spacing: 5) {
                    Text(model.coachExpanded ? "Hide" : "Show all")
                    Kbd("⌘;")
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text)
                .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.coachExpanded ? "Hide the coach's notes" : "Show all \(n) coach notes")
        .accessibilityHint("Command semicolon")
    }

    private func toggle() {
        withAnimation(Motion.animation()) { model.coachExpanded.toggle() }
    }

    private var selected: CoachCheck.Finding? {
        run.findings.indices.contains(picked) ? run.findings[picked] : run.findings.first
    }

    private func chip(_ index: Int, _ finding: CoachCheck.Finding) -> some View {
        let on = finding == selected
        return Button { picked = index } label: {
            CoachFix(wrong: finding.wrong, right: finding.right, size: 12)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surface.opacity(on ? 1 : 0.7)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? Theme.accent : Theme.border, lineWidth: on ? 1.5 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(finding.why)
        .accessibilityLabel("\(finding.wrong) to \(finding.right)")
        .accessibilityHint(finding.why)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// "Conditionals · a future condition takes the present after if            Not a mistake"
    private func detail(_ finding: CoachCheck.Finding) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.item) {
            (Text(CoachGuide.pattern(finding.pattern)?.name ?? "").fontWeight(.semibold).foregroundStyle(Theme.controlText)
                + Text("  \(finding.why)").foregroundStyle(Theme.secondaryText))
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.item)
            Button("Not a mistake") { run.dismiss(finding) }
                .buttonStyle(QuietButtonStyle())
                .help("Hide this note and never flag this phrase again")
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.inner)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.accentSoft))
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.section)
    }
}

/// The coach's "checking" state: a soft highlight sweeping across a bar. Still under Reduce Motion.
struct CoachShimmer: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            Capsule().fill(Theme.border)
                .overlay {
                    LinearGradient(colors: [.clear, Theme.surface.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: phase * geo.size.width)
                }
                .clipShape(Capsule())
        }
        .onAppear {
            guard !Motion.reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) { phase = 1.2 }
        }
        .accessibilityHidden(true)
    }
}

/// "Your takes fixed 3 English slips." under the takes while the coach is off: the user's own fixes, what the
/// coach would do with them and what it costs, then "Don't ask again" and "Turn on coach". It never takes focus,
/// so Return still pastes.
struct CoachInvitationStrip: View {
    @ObservedObject var model: PanelModel
    let offer: CoachInvitation.Offer

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.item) {
                (Text("Your takes fixed \(offer.found.count == 1 ? "an English slip" : "\(offer.found.count) English slips"). ").fontWeight(.semibold)
                    + Text("You made the first one in \(offer.drafts) drafts this month.").foregroundStyle(Theme.secondaryText))
                    .font(.system(size: 13.5))
                    .lineLimit(1)
                Spacer(minLength: Spacing.item)
                Button(action: model.dismissInvitation) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 20, height: 20)
                }
                .buttonStyle(QuietButtonStyle())
                .help("Not now")
                .accessibilityLabel("Dismiss")
            }
            FlowLayout(spacing: 6) {
                ForEach(Array(offer.found.enumerated()), id: \.offset) { _, item in
                    CoachFix(wrong: item.fix.removed, right: item.fix.added, size: 12.5)
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border))
                        .help(CoachGuide.pattern(item.pattern)?.name ?? "")
                }
            }
            Text("English Coach tracks repeats like these and turns them into short lessons. About 1,000 tokens per English draft.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Spacing.item) {
                Spacer(minLength: 0)
                Button("Don't ask again", action: model.neverInvite)
                    .buttonStyle(SecondaryButtonStyle(height: 28))
                Button("Turn on coach", action: model.acceptInvitation)
                    .buttonStyle(InkButtonStyle(height: 28))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.inner + 2)
        .padding(.vertical, Spacing.inner)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentSoft))
        .padding(.horizontal, Spacing.gutter)
        .padding(.bottom, Spacing.section)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("English coach invitation")
    }
}

/// A compact Ink button at a secondary button's size, so the invitation's two answers weigh the same.
struct InkButtonStyle: ButtonStyle {
    var height: CGFloat = 28
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(configuration.isPressed ? 0.82 : 1)))
            .opacity(isEnabled ? 1 : 0.45)
            .lineLimit(1)
            .fixedSize()
            .contentShape(Rectangle())
    }
}

/// "Your draft" above the takes, with each phrase the coach flagged underlined. Hovering one shows its fix.
struct DraftStrip: View {
    let draft: String
    @ObservedObject var run: CoachRun

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your draft").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
            MarkedDraftText(text: draft, marks: marks)
                .accessibilityLabel(draft)
                .accessibilityHint(run.findings.isEmpty ? "" : run.findings.map { "\($0.wrong) to \($0.right)" }.joined(separator: "; "))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, Spacing.inner)
        .background(Theme.strip)
    }

    /// Each finding's place in the draft, with its tooltip.
    private var marks: [MarkedDraftText.Mark] {
        let ns = draft as NSString
        return run.findings.compactMap { finding in
            let range = ns.range(of: finding.wrong, options: .caseInsensitive)
            guard range.location != NSNotFound else { return nil }
            let rule = CoachGuide.pattern(finding.pattern)?.name
            let tip = "\(finding.wrong) → \(finding.right)" + (rule.map { " (\($0))" } ?? "") + (finding.why.isEmpty ? "" : "\n\(finding.why)")
            return .init(range: range, tip: tip)
        }
    }
}

/// Up to three lines of the draft, selectable, with underlined ranges that show a tooltip on hover.
struct MarkedDraftText: NSViewRepresentable {
    struct Mark: Equatable {
        let range: NSRange
        let tip: String
    }

    let text: String
    let marks: [Mark]
    var fontSize: CGFloat = 14
    var lines = 3

    func makeNSView(context: Context) -> TipTextView {
        let view = TipTextView(frame: .zero)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.maximumNumberOfLines = lines
        view.textContainer?.lineBreakMode = .byTruncatingTail
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.baseWritingDirection = .natural
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        update(view)
        return view
    }

    func updateNSView(_ view: TipTextView, context: Context) { update(view) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: TipTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 600
        guard let container = view.textContainer, let layout = view.layoutManager else { return nil }
        container.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return CGSize(width: width, height: ceil(layout.usedRect(for: container).height))
    }

    private func update(_ view: TipTextView) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = .natural
        paragraph.lineBreakMode = .byWordWrapping
        let string = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor(Theme.text), .paragraphStyle: paragraph,
        ])
        for mark in marks where NSMaxRange(mark.range) <= string.length {
            string.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: NSColor(Theme.avoidText)],
                                 range: mark.range)
        }
        if view.textStorage?.isEqual(to: string) != true { view.textStorage?.setAttributedString(string) }
        if view.marks != marks {
            view.marks = marks
            view.needsLayout = true
        }
    }

    final class TipTextView: NSTextView {
        var marks: [Mark] = []

        override func layout() {
            super.layout()
            removeAllToolTips()
            guard let layout = layoutManager, let container = textContainer else { return }
            for mark in marks {
                let glyphs = layout.glyphRange(forCharacterRange: mark.range, actualCharacterRange: nil)
                layout.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                               in: container) { rect, _ in
                    self.addToolTip(rect.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y),
                                    owner: mark.tip as NSString, userData: nil)
                }
            }
        }
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
    @ObservedObject private var request = CoachSetupRequest.shared
    /// Patterns handed over by the panel's invitation, for setup to suggest.
    @State private var suggested: [String]?

    var body: some View {
        Group {
            switch state.coachScreen {
            case .setup:
                ZStack {
                    overviewOrIntro.allowsHitTesting(false)
                    Color.black.opacity(0.28).ignoresSafeArea()
                    CoachSetupView(state: state, suggested: suggested ?? CoachSetupView.defaultSuggestions())
                        .padding(24)
                }
            case .lesson(let id):
                if let pattern = CoachGuide.pattern(id) { CoachLessonView(state: state, pattern: pattern) } else { overviewOrIntro }
            case .home: overviewOrIntro
            }
        }
        .background(Theme.surface)
        .onAppear(perform: takeRequest)
        .onChange(of: request.pending) { takeRequest() }
    }

    @ViewBuilder private var overviewOrIntro: some View {
        if store.settings.coach.enabled { CoachOverviewView(state: state) } else { CoachIntroView(state: state) }
    }

    private func takeRequest() {
        guard let pending = request.pending else { return }
        request.pending = nil
        suggested = pending.isEmpty ? nil : pending
        state.coachScreen = .setup
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

/// Settings › English coach while it's off: show what it looks like, then one clear choice.
struct CoachIntroView: View {
    @ObservedObject var state: SettingsState
    @State private var costDetails = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("English Coach").font(.system(size: 24, weight: .bold))
                        Text("Learn from the English you already write. The coach notices mistakes you repeat and turns them into short lessons built from your own sentences.")
                            .font(.system(size: 14)).foregroundStyle(Theme.controlText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 460, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                    Button("Set up coach…") { state.coachScreen = .setup }
                        .buttonStyle(PrimaryButtonStyle())
                        .fixedSize()
                        .keyboardShortcut(.defaultAction)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("WHAT YOU'LL SEE").font(.mono(10.5, bold: true)).kerning(1).foregroundStyle(Theme.secondaryText)
                    HStack(alignment: .top, spacing: 12) {
                        tile("Notes under your takes") {
                            CoachFix(wrong: "if you will send", right: "if you send", size: 12.5)
                                .padding(.horizontal, 9).frame(height: 26)
                                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.surface))
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border))
                            caption("Each fix in your draft, with a one-line rule: future “if” takes the present tense.")
                        }
                        tile("A nudge when you repeat one") {
                            miniToast
                            caption("One extra line in the paste confirmation, only for mistakes you keep making.")
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    tile(nil) {
                        HStack {
                            Text("Your progress").font(.system(size: 12, weight: .bold))
                            Spacer()
                            Text("↓ 50% articles this month").font(.system(size: 12)).foregroundStyle(Theme.doText)
                        }
                        ProgressBars(values: [0.9, 0.75, 0.6, 0.42]).frame(height: 30)
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.strip))

                HStack(alignment: .top, spacing: 16) {
                    column("Watches", Text("Grammar, word choice, natural phrasing. Never typos, names or code."))
                    column("Costs", Text("~1,000 tokens per English draft. Lessons are free. "), details: true)
                    column("Keeps", Text("Only the phrase around each mistake, on this Mac, for 30 days."))
                }
                if costDetails {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(CoachCopy.tokens)
                        Text(CoachCopy.billing).foregroundStyle(Theme.secondaryText)
                    }
                    .font(.system(size: 12.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
                    .transition(.opacity)
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    /// The paste toast in miniature: "✓ Pasted take 1", then the coach's line.
    private var miniToast: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color(hex: "#8FD19E"))
                Text("Pasted take 1")
            }
            Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)
            (Text("Coach").fontWeight(.bold) + Text(" · “close the light” → “turn off the light” · 4th time"))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .foregroundStyle(Color(hex: "#F3EBDD"))
        .padding(.horizontal, 9).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#24242B")))
    }

    private func tile<Content: View>(_ title: String?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.system(size: 12, weight: .bold)) }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
    }

    private func column(_ title: String, _ text: Text, details: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12.5, weight: .bold))
            text.font(.system(size: 12.5)).foregroundStyle(Theme.controlText).fixedSize(horizontal: false, vertical: true)
            if details {
                Button(costDetails ? "Hide details" : "Details") { withAnimation(Motion.animation()) { costDetails.toggle() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .underline()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Four bars falling toward this week, the last in green: the progress sparkline on the coach's intro.
struct ProgressBars: View {
    let values: [CGFloat]

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(index == values.count - 1 ? Theme.doText : Theme.controlBorder)
                        .frame(height: geo.size.height * value)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityLabel("A sample chart: mistakes falling week by week")
    }
}

// MARK: Setup

/// "Set up coach…": a 3-step sheet. Focus (let the coach find patterns, or pick), first language, and which
/// presets count. Each step has a default, so Return three times starts it. Also used to edit while it's on.
struct CoachSetupView: View {
    @ObservedObject var state: SettingsState
    @ObservedObject var store = Store.shared
    let suggested: [String]
    /// Edited here, saved by the last step.
    @State private var draft: CoachSettings
    @State private var step: Int
    @State private var picking: Bool
    @State private var editingPresets: Bool

    init(state: SettingsState, suggested: [String], step: Int = 1, picking: Bool = false, editingPresets: Bool = false) {
        self.state = state
        self.suggested = suggested
        var settings = Store.shared.settings.coach
        settings.findAll = true
        if !settings.enabled { settings.focus = suggested }
        _draft = State(initialValue: settings)
        _step = State(initialValue: step)
        // While on, the focus areas the user picked open in "I'll pick".
        _picking = State(initialValue: picking || (settings.enabled && settings.focus != suggested))
        _editingPresets = State(initialValue: editingPresets)
    }

    /// From the invitation's record of recent drafts, or two common starting points.
    @MainActor static func defaultSuggestions() -> [String] {
        let seen = CoachInviteStore.shared.suggestions()
        return seen.isEmpty ? ["conditionals", "collocations"] : seen
    }

    private var editing: Bool { store.settings.coach.enabled }
    private var englishPresets: [Preset] { store.presets.filter { CoachSettings().counts($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    ForEach(1...3, id: \.self) { index in
                        Capsule().fill(index <= step ? Theme.accent : Theme.controlBorder).frame(width: 28, height: 4)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Step \(step) of 3")
                Text(title).font(.system(size: 19, weight: .bold)).padding(.top, 10)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 12)

            Group {
                switch step {
                case 1: focusStep
                case 2: languageStep
                default: presetsStep
                }
            }
            .padding(.horizontal, 22).padding(.bottom, 18)

            RowDivider()
            HStack(spacing: Spacing.item) {
                Text(footnote).font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                Spacer(minLength: Spacing.item)
                if step > 1 {
                    Button("Back") { step -= 1 }.buttonStyle(QuietButtonStyle(size: 13)).fixedSize()
                }
                Button("Cancel") { state.coachScreen = .home }
                    .buttonStyle(SecondaryButtonStyle(height: 30))
                    .fixedSize()
                    .keyboardShortcut(.cancelAction)
                Button { next() } label: {
                    HStack(spacing: 6) {
                        Text(step < 3 ? "Continue" : (editing ? "Save" : "Start coaching"))
                        Text("↵").font(.system(size: 12)).opacity(0.85)
                    }
                }
                .buttonStyle(PrimaryButtonStyle(height: 30))
                .keyboardShortcut(.defaultAction)
                .disabled(step == 1 && draft.focus.isEmpty)
                .fixedSize()
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 22).padding(.vertical, 12)
        }
        .frame(width: 580)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface).shadow(color: .black.opacity(0.2), radius: 24, y: 10))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border))
        .animation(Motion.animation(), value: step)
        .animation(Motion.animation(), value: picking)
        .animation(Motion.animation(), value: editingPresets)
    }

    private var title: String {
        switch step {
        case 1: "What should the coach focus on?"
        case 2: "What’s your first language?"
        default: "Which drafts should it check?"
        }
    }

    private var subtitle: String {
        switch step {
        case 1: "It watches everything either way. Focus areas get nudges after you paste."
        case 2: "Lessons explain why a mistake feels right in it, like false friends."
        default: "Only drafts you write in English are checked."
        }
    }

    private var footnote: String {
        switch step {
        case 1: "Step 1 of 3 · next: your first language"
        case 2: "Step 2 of 3 · next: presets"
        default: "Step 3 of 3 · about 1,000 tokens per English draft"
        }
    }

    private func next() {
        guard step == 3 else { step += 1; return }
        draft.enabled = true
        store.settings.coach = draft
        state.coachScreen = .home
    }

    // Step 1

    private var focusStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            option(selected: !picking, action: { picking = false; draft.focus = suggested }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Let the coach find my patterns").font(.system(size: 13, weight: .bold))
                    Text(CoachInviteStore.shared.data.drafts.isEmpty ? "Suggested to start with:" : "Suggested from your recent drafts:")
                        .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                    FlowLayout(spacing: 6) {
                        ForEach(suggested, id: \.self) { id in
                            Text(CoachGuide.pattern(id)?.name ?? id)
                                .font(.system(size: 12.5))
                                .foregroundStyle(picking ? Theme.controlText : Theme.onAccent)
                                .padding(.horizontal, 11).frame(height: 26)
                                .background(Capsule().fill(picking ? Theme.surface : Theme.accent))
                                .overlay(Capsule().strokeBorder(picking ? Theme.controlBorder : Theme.accent))
                        }
                    }
                    .padding(.top, 6)
                }
            }
            option(selected: picking, action: { picking = true }) {
                VStack(alignment: .leading, spacing: 10) {
                    (Text("I’ll pick").fontWeight(.bold) + Text(" · \(CoachGuide.patterns.count) areas in grammar, word choice and phrasing").foregroundStyle(Theme.secondaryText))
                        .font(.system(size: 13))
                    if picking {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(CoachGuide.Group.allCases, id: \.self) { group in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(group.rawValue).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                                        FlowLayout(spacing: 6) {
                                            ForEach(CoachGuide.patterns.filter { $0.group == group }) { pattern in
                                                Button(pattern.name) { toggleFocus(pattern.id) }
                                                    .buttonStyle(PillButtonStyle(selected: draft.focus.contains(pattern.id), height: 28))
                                                    .help(pattern.definition)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 230)
                    }
                }
            }
        }
    }

    // Step 2

    private var languageStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: Spacing.inner) {
                MenuPicker(options: Languages.common.filter { $0 != "en" }.map { ($0, Languages.englishName($0)) },
                           selection: Binding(get: { draft.firstLanguage.isEmpty ? "he" : draft.firstLanguage }, set: { draft.firstLanguage = $0 }))
                Button("Skip") {
                    draft.firstLanguage = ""
                    step = 3
                }
                .buttonStyle(QuietButtonStyle(size: 13))
                Spacer(minLength: 0)
            }
            Text(firstLanguageNote).font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var firstLanguageNote: String {
        let code = draft.firstLanguage.isEmpty ? "he" : draft.firstLanguage
        return CoachGuide.patterns.contains { $0.firstLanguage[code] != nil }
            ? "Lessons explain why a mistake feels right in \(Languages.englishName(code))."
            : "Lessons have notes for Hebrew so far; other languages get the rule and your own examples."
    }

    // Step 3

    private var presetsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    Text(presetsSummary).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: Spacing.item)
                    Button(editingPresets ? "Done" : "Edit") { editingPresets.toggle() }.buttonStyle(QuietButtonStyle(size: 13))
                }
                .padding(.horizontal, 12).frame(height: 40)
                if editingPresets {
                    RowDivider()
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(store.presets) { preset in
                                HStack(spacing: 10) {
                                    Checkbox(isOn: Binding(get: { draft.counts(preset) }, set: { draft.presetCounts[preset.id] = $0 }), label: preset.name)
                                    PresetDot(hex: preset.colorHex)
                                    Text(preset.name).font(.system(size: 13)).foregroundStyle(draft.counts(preset) ? Theme.text : Theme.secondaryText)
                                    Spacer()
                                    if preset.isMinimalEdits { Text("best signal").font(.system(size: 12)).foregroundStyle(Theme.doText) }
                                }
                                .padding(.horizontal, 12).frame(height: 32)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.strip))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))

            HStack(spacing: Spacing.inner) {
                Text("English").font(.system(size: 13, weight: .semibold))
                ChoiceSegments(options: [(CoachSettings.Variant.us, "US"), (.uk, "UK")], selection: $draft.variant)
                    .fixedSize()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.controlBorder))
                Spacer(minLength: 0)
            }
        }
    }

    private var presetsSummary: String {
        let counted = store.presets.filter { draft.counts($0) }
        if counted.map(\.id) == englishPresets.map(\.id) { return "All presets that write English (\(counted.count))" }
        return "\(counted.count) of \(store.presets.count) presets"
    }

    private func option<Content: View>(selected: Bool, action: @escaping () -> Void, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .strokeBorder(selected ? Theme.accent : Theme.controlBorder, lineWidth: selected ? 5 : 1.5)
                .frame(width: 16, height: 16)
                .padding(.top, 1)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Theme.strip : Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Theme.accent : Theme.border, lineWidth: selected ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggleFocus(_ id: String) {
        if let i = draft.focus.firstIndex(of: id) { draft.focus.remove(at: i) } else { draft.focus.append(id) }
    }
}

// MARK: Overview

/// Settings › English coach while it's on: grouped rows. The switch, your patterns, then the coach's settings.
struct CoachOverviewView: View {
    @ObservedObject var state: SettingsState
    @ObservedObject var store = Store.shared
    @ObservedObject var coach = CoachStore.shared
    @State private var confirmOff = false
    @State private var confirmClear = false
    @State private var editingGoals = false

    var body: some View {
        let stats = coach.stats()
        let focus = store.settings.coach.focus
        let sorted = stats.filter { focus.contains($0.id) } + stats.filter { !focus.contains($0.id) }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                group(nil) {
                    row {
                        (Text("English Coach").fontWeight(.bold)
                         + Text(" · \(coach.data.drafts.count) draft\(coach.data.drafts.count == 1 ? "" : "s"), \(coach.words.formatted()) words in 30 days")
                            .foregroundStyle(Theme.secondaryText))
                            .lineLimit(1)
                        Spacer(minLength: Spacing.item)
                        CoachSwitch(isOn: Binding(get: { true }, set: { if !$0 { confirmOff = true } }), label: "English coach")
                    }
                }

                group("Your patterns · per 1,000 words") {
                    if sorted.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nothing yet").font(.system(size: 13, weight: .semibold))
                            Text("Write and paste a few English drafts. Notes show with your takes right away; trends here mean more after about 1,500 words.")
                                .font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, stat in
                        if index > 0 { RowDivider() }
                        patternRow(stat, focus: focus.contains(stat.id))
                    }
                }

                let mastered = coach.mastered()
                if !mastered.isEmpty || !coach.data.muted.isEmpty {
                    group("Mastered and not tracked") {
                        ForEach(mastered) { pattern in
                            row {
                                Text(pattern.name)
                                Spacer()
                                Label("Mastered", systemImage: "checkmark").font(.system(size: 12)).foregroundStyle(Theme.doText)
                            }
                        }
                        ForEach(coach.data.muted, id: \.self) { id in
                            RowDivider()
                            row {
                                Text(CoachGuide.pattern(id)?.name ?? id).foregroundStyle(Theme.secondaryText)
                                Spacer()
                                Button("Track again") { coach.unmute(id) }.buttonStyle(SecondaryButtonStyle(height: 26))
                            }
                        }
                    }
                }

                group("Settings") {
                    row {
                        Text("Focus areas")
                        Spacer(minLength: Spacing.item)
                        Text(focus.compactMap { CoachGuide.pattern($0)?.name }.joined(separator: ", "))
                            .font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText).lineLimit(1).truncationMode(.tail)
                        Button("Edit…") { state.coachScreen = .setup }.buttonStyle(QuietButtonStyle(size: 12.5))
                    }
                    RowDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Goals")
                            Text("· how you want to sound, tracked as tips").font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText)
                            Spacer(minLength: Spacing.item)
                            if !editingGoals {
                                Text(goalsSummary).font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                            }
                            Button(editingGoals ? "Done" : "Edit…") { editingGoals.toggle() }.buttonStyle(QuietButtonStyle(size: 12.5))
                        }
                        if editingGoals { ChipsEditor(items: $store.settings.coach.goals, style: .positive) }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    RowDivider()
                    row {
                        Text("Nudges after paste")
                        Spacer()
                        NudgesMenu(selection: $store.settings.coach.nudges, showsChoice: true)
                    }
                    RowDivider()
                    row {
                        Text("First language")
                        Spacer()
                        MenuPicker(options: [("", "None")] + Languages.common.filter { $0 != "en" }.map { ($0, Languages.englishName($0)) },
                                   selection: $store.settings.coach.firstLanguage)
                    }
                    RowDivider()
                    row {
                        Text("Tokens this month")
                        Spacer()
                        Text("≈ \(Self.compact(coach.tokens())) · \(coach.checks()) checks · lessons free")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText)
                            .help("Estimated from text length. Runs on your engine, now \(CoachCopy.engineName(store.settings)).")
                    }
                    RowDivider()
                    row {
                        Text("Kept on this Mac for 30 days")
                        Spacer()
                        Button("Clear coach data…") { confirmClear = true }
                            .buttonStyle(SecondaryButtonStyle(height: 28))
                            .foregroundStyle(Theme.avoidText)
                    }
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 18)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
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
        .alert("Clear the coach’s data?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { coach.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your patterns, counts and lessons start over. The coach stays on.")
        }
    }

    private var goalsSummary: String {
        let goals = store.settings.coach.goals
        return goals.isEmpty ? "None" : goals.joined(separator: ", ")
    }

    private func group<Content: View>(_ title: String?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title { Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.secondaryText).padding(.leading, 4) }
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: Spacing.inner) { content() }
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
    }

    private func patternRow(_ stat: CoachStore.PatternStats, focus: Bool) -> some View {
        row {
            Text(stat.pattern.name).lineLimit(1)
                .help(stat.latest.map { "Latest: “\($0.finding.wrong)” → “\($0.finding.right)” · \($0.app), \($0.date.formatted(.relative(presentation: .named)))" } ?? "")
            if focus {
                Text("Focus").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.doText)
                    .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Theme.doFill))
                    .fixedSize()
            }
            Spacer(minLength: Spacing.item)
            CoachSparkline(values: stat.weekly, color: trendColor(stat)).frame(width: 48, height: 18)
            Text(String(format: "%.1f", stat.rate)).font(.system(size: 13, weight: .bold)).monospacedDigit().frame(width: 30, alignment: .trailing)
            Text(trendLabel(stat)).font(.system(size: 11.5)).foregroundStyle(trendColor(stat)).frame(width: 52, alignment: .leading)
            if stat.count >= CoachStore.lessonAt || coach.data.lessonsRead[stat.id] != nil {
                Button("Lesson") { open(stat.id) }.buttonStyle(SecondaryButtonStyle(height: 26)).fixedSize()
                    .frame(width: 112, alignment: .trailing)
            } else {
                Text("lesson after \(CoachStore.lessonAt - stat.count) more")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText).lineLimit(1).fixedSize()
                    .frame(width: 112, alignment: .trailing)
                    .help("A lesson is put together once a pattern shows up \(CoachStore.lessonAt) times.")
            }
        }
    }

    private func open(_ id: String) {
        coach.markRead(id)
        state.coachScreen = .lesson(id)
    }

    private func trendLabel(_ stat: CoachStore.PatternStats) -> String {
        guard let trend = stat.trend else { return "\(stat.count)×" }
        if abs(trend) < 0.1 { return "→ steady" }
        return "\(trend > 0 ? "↑" : "↓") \(Int(abs(trend) * 100))%"
    }

    private func trendColor(_ stat: CoachStore.PatternStats) -> Color {
        guard let trend = stat.trend, abs(trend) >= 0.1 else { return Theme.secondaryText }
        return trend > 0 ? Theme.avoidText : Theme.doText
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
