import SwiftUI

@MainActor
final class RunModel: ObservableObject {
    /// Full model IDs: on some plans the short aliases ("sonnet") still resolve to older models.
    static let models = [("claude-haiku-5-5", "Haiku 5.5"), ("claude-sonnet-5-5", "Sonnet 5.5"), ("claude-opus-5-5", "Opus 5.5")]
    static let efforts = ["low", "medium", "high"]

    @Published var draft = ""
    @Published var presetID = Preset.builtIn[0].id {
        didSet { takeCount = preset.defaultTakes }
    }
    @Published var takeCount = Preset.builtIn[0].defaultTakes
    @Published var modelName = "claude-sonnet-5-5"
    @Published var effort = "low"
    @Published var takes: [String] = []
    @Published var running = false
    @Published var startedAt = Date()
    @Published var error: String?
    @Published var timing = ""
    /// Bumped on every summon so the view can move focus back to the draft.
    @Published var summonCount = 0

    var focus: FocusSnapshot?
    var summonedAt = Date()
    var panelShownMs = 0
    var onPaste: (String) -> Void = { _ in }
    var onClose: () -> Void = {}

    var preset: Preset { Preset.builtIn.first { $0.id == presetID } ?? Preset.builtIn[0] }

    var targetDescription: String {
        let app = focus?.app?.localizedName ?? "the focused app"
        switch focus?.source {
        case .selection: return "\(app) · from your selection"
        case .field: return "\(app) · from the field"
        default: return "\(app) · couldn't read the field"
        }
    }

    func reset(with focus: FocusSnapshot, summonedAt: Date) {
        self.focus = focus
        self.summonedAt = summonedAt
        draft = focus.text
        takes = []
        error = nil
        timing = ""
        running = false
        summonCount += 1
    }

    func generate() {
        let draft = self.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty, !running else { return }
        let request = EngineRequest(draft: draft, preset: preset, takes: takeCount, model: modelName, effort: effort)
        running = true
        error = nil
        takes = []
        startedAt = Date()

        Task {
            do {
                let result = try await Engine.run(request) { partial in
                    Task { @MainActor in
                        guard self.running else { return }
                        self.takes = partial
                    }
                }
                finish(result, request: request)
            } catch {
                running = false
                self.error = error.localizedDescription
            }
        }
    }

    private func finish(_ result: EngineResult, request: EngineRequest) {
        running = false
        takes = result.takes
        let seconds = { (ms: Int) in String(format: "%.1f s", Double(ms) / 1000) }
        var parts = ["\(seconds(result.wallMs)) total"]
        if let first = result.firstTextMs { parts.append("first words \(seconds(first))") }
        timing = parts.joined(separator: " · ")
        RunLog.append(["kind": "app", "model": request.model, "effort": request.effort, "takes": request.takes,
                       "preset": request.preset.id, "panelShownMs": panelShownMs,
                       "wallMs": result.wallMs, "firstTextMs": result.firstTextMs ?? -1, "apiMs": result.apiMs ?? -1,
                       "app": focus?.app?.bundleIdentifier ?? ""])
    }

    /// While streaming, the last take may still be growing; only finished ones can be pasted.
    func isFinished(_ index: Int) -> Bool { !running || index < takes.count - 1 }

    func paste(_ index: Int) {
        guard takes.indices.contains(index), isFinished(index) else { return }
        onPaste(takes[index])
    }
}

struct RunView: View {
    @ObservedObject var model: RunModel
    @FocusState private var draftFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble.fill").foregroundStyle(.tint)
                Text(model.targetDescription).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Close") { model.onClose() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderless)
                    .font(.callout)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            TextEditor(text: $model.draft)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .focused($draftFocused)
                .frame(minHeight: 72, maxHeight: 120)
                .padding(.horizontal, 12)

            Divider().padding(.top, 8)

            HStack(spacing: 14) {
                Picker("Preset", selection: $model.presetID) {
                    ForEach(Preset.builtIn) { Text($0.name).tag($0.id) }
                }
                .frame(maxWidth: 260)
                Picker("Takes", selection: $model.takeCount) {
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                Picker("Model", selection: $model.modelName) {
                    ForEach(RunModel.models, id: \.0) { Text($0.1).tag($0.0) }
                }
                .frame(width: 140)
                Picker("Effort", selection: $model.effort) {
                    ForEach(RunModel.efforts, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .frame(width: 140)
            }
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            results
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            HStack {
                Text(model.timing.isEmpty ? "⌘↵ write · ⌘1–5 paste a take · esc close" : model.timing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(model.takeCount == 1 ? "Write 1 take" : "Write \(model.takeCount) takes") { model.generate() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.running || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 600, minHeight: 400)
        .onChange(of: model.summonCount) { draftFocused = true }
        .onAppear { draftFocused = true }
    }

    @ViewBuilder private var results: some View {
        if model.running && model.takes.isEmpty {
            TimelineView(.periodic(from: model.startedAt, by: 0.1)) { context in
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(String(format: "Writing… %.1f s", context.date.timeIntervalSince(model.startedAt)))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        } else if let error = model.error {
            Text(error)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .padding(16)
        } else if model.takes.isEmpty {
            Text("Takes appear here.")
                .foregroundStyle(.secondary)
                .padding(16)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(model.takes.enumerated()), id: \.offset) { index, take in
                        TakeRow(index: index, text: take, finished: model.isFinished(index)) { model.paste(index) }
                    }
                }
                .padding(12)
            }
        }
    }
}

private struct TakeRow: View {
    let index: Int
    let text: String
    let finished: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Group {
                    if finished {
                        Text("⌘\(index + 1)")
                    } else {
                        ProgressView().controlSize(.mini)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
                Text(text)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!finished)
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
    }
}
