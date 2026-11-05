import SwiftUI

/// Pieces shared by onboarding and the setup window, so both look like one app.

/// The round step marker: a number while to do, a check when done, a dash when skipped.
struct StepBadge: View {
    enum State { case todo, current, done, skipped }
    let number: Int
    var state: State = .todo
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            Circle().fill(fill).frame(width: size, height: size)
            if state == .current { Circle().stroke(Theme.accent, lineWidth: 1.5).frame(width: size, height: size) }
            switch state {
            case .done:
                DrawnCheck(lineWidth: max(1.5, size * 0.09))
                    .foregroundStyle(Theme.doText)
                    .frame(width: size * 0.44, height: size * 0.44)
                    .transition(.opacity)
            case .skipped:
                Image(systemName: "minus").font(.system(size: size * 0.43, weight: .bold)).foregroundStyle(Theme.tertiaryText)
            default:
                Text("\(number)").font(.system(size: size * 0.47, weight: .bold))
                    .foregroundStyle(state == .current ? Theme.accent : Theme.secondaryText)
            }
        }
        .accessibilityHidden(true)
    }

    private var fill: Color {
        switch state {
        case .done: return Theme.doFill
        case .current: return Theme.accentSoft
        case .skipped, .todo: return Theme.kbdFill
        }
    }
}

/// A check that draws itself on with a stroke when it appears (300 ms), or is simply there under Reduce Motion.
struct DrawnCheck: View {
    var lineWidth: CGFloat = 2
    @State private var drawn: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CheckShape()
            .trim(from: 0, to: reduceMotion ? 1 : drawn)
            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .onAppear {
                guard drawn == 0 else { return }
                withAnimation(.easeOut(duration: 0.3)) { drawn = 1 }
            }
    }

    struct CheckShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.08))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
            return path
        }
    }
}

/// "Allowed" / "Needed" capsule next to a step title. `waiting` adds a small spinner for live checks.
struct StatusPill: View {
    let text: String
    var good: Bool
    var waiting = false

    var body: some View {
        HStack(spacing: 5) {
            if waiting { ProgressView().controlSize(.mini).accessibilityHidden(true) }
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .foregroundStyle(good ? Theme.doText : waiting ? Theme.secondaryText : Theme.avoidText)
        .background(Capsule().fill(good ? Theme.doFill : waiting ? Theme.kbdFill : Theme.avoidFill))
        .accessibilityElement(children: .combine)
    }
}

/// The rounded card a step's content sits in. `highlighted` gets the accent outline (a step still to do).
struct StepCard<Content: View>: View {
    var highlighted = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Spacing.section)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(highlighted ? Theme.accent.opacity(0.5) : Theme.border))
    }
}

/// Small grey explanatory line under a step.
struct StepNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
