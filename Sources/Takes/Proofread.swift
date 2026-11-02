import SwiftUI

/// Proofreading: fix mistakes, keep the user's words. A built-in preset, a per-preset "minimal edits" flag that
/// any preset can turn on, and the takes screen's inline fixes and "No mistakes found" state.
enum Proofread {
    /// Added to the system prompt for presets with minimal edits on.
    static let rules = [
        "Minimal edits: fix only real mistakes in spelling, grammar, punctuation, capitalisation and clear typos.",
        "Keep everything else exactly as written: word choice, voice, tone, slang, sentence order, line breaks, emoji, links, code, names and formatting.",
        "Never add, remove or reorder content. Don't rephrase a sentence that is already correct, and don't make casual writing formal.",
        "If nothing needs fixing, return the draft exactly as written.",
    ]

    /// The instruction the old built-in "Proofread only, keep my words" preset shipped with. Presets still on it
    /// are upgraded to `Preset.proofread` once.
    static let legacyInstruction = "Fix spelling, grammar and punctuation only. Keep my words, tone and structure."
    static let legacyName = "Proofread only, keep my words"

    static func fixLabel(_ count: Int) -> String {
        count == 0 ? "No fixes" : "\(count) fix\(count == 1 ? "" : "es")"
    }

    /// True when every take is the draft as written, apart from spacing.
    static func nothingToFix(draft: String, takes: [String]) -> Bool {
        !takes.isEmpty && takes.allSatisfy { WordDiff.fixes(from: draft, to: $0).isEmpty }
    }

    /// Upgrades the old built-in proofread preset, if the user never edited its instruction, to the new one.
    /// Keeps the user's id, color, hotkey, apps and examples; swaps the model only if it was left on the old default.
    static func upgraded(_ presets: [Preset]) -> [Preset] {
        presets.map { old in
            guard old.minimalEdits == nil, old.instruction == legacyInstruction else { return old }
            let new = Preset.proofread
            var preset = old
            if old.name == legacyName { preset.name = new.name }
            preset.instruction = new.instruction
            preset.dos = new.dos
            preset.avoid = new.avoid
            preset.minimalEdits = true
            if old.model == Models.sonnet, old.effort == "low" { preset.model = new.model }
            return preset
        }
    }
}

extension Preset {
    /// The built-in Proofread preset. Its id is fixed, so the gallery can tell whether it's already added.
    static var proofread: Preset {
        Preset(id: "builtin.proofread", name: "Proofread", colorHex: "#1D6B4F",
               instruction: "Fix spelling, grammar, punctuation and clear typos. Keep my words, voice and tone.",
               dos: ["Keep line breaks, emoji, links, code and names exactly as written"],
               avoid: ["Rewording what's already correct", "Adding or removing anything"],
               takes: 1, model: Models.haiku, effort: "low", minimalEdits: true, showTone: false)
    }

    var isMinimalEdits: Bool {
        get { minimalEdits ?? false }
        // Stored as false rather than nil, so turning it off is remembered and never upgraded back.
        set { minimalEdits = newValue }
    }
}

// MARK: - Takes screen

extension PanelModel {
    /// Minimal-edit takes open with their fixes marked.
    var showsFixes: Bool { preset.isMinimalEdits }

    func fixCount(_ index: Int) -> Int {
        guard takes.indices.contains(index) else { return 0 }
        return WordDiff.fixes(from: sourceDraft, to: takes[index]).count
    }

    /// Every take of a finished minimal-edit run is the draft as written.
    var noFixesFound: Bool {
        showsFixes && !running && error == nil && Proofread.nothingToFix(draft: sourceDraft, takes: takes)
    }

    /// Pastes the draft as written, for "No mistakes found".
    func pasteOriginal() {
        guard noFixesFound else { return }
        onPaste(0, sourceDraft, presetID)
    }
}

/// Shown instead of the cards when a minimal-edit run changed nothing: rather than an identical take, say so and
/// offer the draft as it is.
struct NoFixesView: View {
    @ObservedObject var model: PanelModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.inner) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.doText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.item) {
                Text("No mistakes found").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                Text("Your draft reads fine as written. Paste it as it is, or go back and keep writing.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, Spacing.section)
        .accessibilityElement(children: .contain)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.return) { model.pasteOriginal(); return .handled }
        .onKeyPress(.escape) { model.escape(); return .handled }
        .onAppear { focused = true }
        .onChange(of: model.focusToken) { focused = true }
    }
}

// MARK: - Preset editor

/// "Minimal edits" in Settings › Presets, so people can make their own proofread-style presets.
struct MinimalEditsSection: View {
    @Binding var preset: Preset

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Checkbox(isOn: $preset.isMinimalEdits, label: "Minimal edits")
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Minimal edits").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Text("Fix mistakes only and keep my words. Takes open with each fix marked, and say so when there's nothing to fix.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
            .onTapGesture { preset.isMinimalEdits.toggle() }
            .accessibilityHidden(true)
        }
    }
}
