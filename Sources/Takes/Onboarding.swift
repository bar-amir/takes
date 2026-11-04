import Foundation

/// The first-run walk-through: an opening screen, then five steps. New installs see it once; people who already
/// had Takes never do (their settings have no `onboarding` key). Later problems go to the setup window instead.
enum OnboardingStep: String, Codable, CaseIterable, Identifiable {
    case accessibility, engine, personalize, practice, done
    var id: String { rawValue }

    /// The short name in the step list.
    var title: String {
        switch self {
        case .accessibility: return "Allow access"
        case .engine: return "Connect a model"
        case .personalize: return "Make it yours"
        case .practice: return "Try it"
        case .done: return "Done"
        }
    }

    /// Takes can't work without these, so they can't be skipped (the window can still be closed and resumed).
    /// Connect a model includes where the text goes, so it needs both a working engine and that consent.
    var isRequired: Bool { self == .accessibility || self == .engine }

    /// Optional steps with a Skip button.
    var canSkip: Bool { self == .personalize || self == .practice }

    /// Steps that are passed by themselves, with a check, when what they ask for is already true.
    var passesWhenSatisfied: Bool { isRequired }

    func isSatisfied(_ conditions: OnboardingConditions) -> Bool {
        switch self {
        case .accessibility: return conditions.accessibility
        case .engine: return conditions.engineReady && conditions.privacyAccepted
        default: return false
        }
    }

    /// Reads a step name saved by any version. 0.5 and earlier had eight steps: Welcome is now the opening screen
    /// (nil here), Your text is part of Connect a model, and Hotkey and Presets are Make it yours.
    static func named(_ name: String) -> OnboardingStep? {
        if let step = OnboardingStep(rawValue: name) { return step }
        switch name {
        case "privacy": return .engine
        case "hotkey", "presets": return .personalize
        default: return nil
        }
    }
}

/// What the Mac looks like right now, from `SetupMonitor`.
struct OnboardingConditions: Equatable {
    var accessibility = false
    var engineReady = false
    var privacyAccepted = false
    var hotKeyFree = true
}

/// Where the user is in onboarding, saved in settings so quitting half-way picks up at the same step.
struct OnboardingProgress: Codable, Equatable {
    var step = OnboardingStep.accessibility
    /// Steps left forward, in order; Back walks this.
    var history: [OnboardingStep] = []
    /// Steps passed by themselves because they were already done; Back skips over them.
    var autoPassed: Set<OnboardingStep> = []
    var skipped: Set<OnboardingStep> = []
    /// The user pasted a take in the practice box.
    var practiced = false
    var finished = false
    /// Get started was pressed on the opening screen, so it isn't shown again on resume.
    var openingSeen = false

    /// Someone who used Takes before onboarding existed.
    static let existingUser = OnboardingProgress(step: .done, finished: true, openingSeen: true)

    enum CodingKeys: String, CodingKey { case step, history, autoPassed, skipped, practiced, finished, openingSeen }

    init(step: OnboardingStep = .accessibility, history: [OnboardingStep] = [], autoPassed: Set<OnboardingStep> = [],
         skipped: Set<OnboardingStep> = [], practiced: Bool = false, finished: Bool = false, openingSeen: Bool = false) {
        self.step = step
        self.history = history
        self.autoPassed = autoPassed
        self.skipped = skipped
        self.practiced = practiced
        self.finished = finished
        self.openingSeen = openingSeen
    }

    /// Steps are decoded by name. Names from 0.5 and earlier map onto the step that now holds them (see
    /// `OnboardingStep.named`); a name this version doesn't know (saved by a newer one) is dropped.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func names(_ key: CodingKeys) -> [String] { (try? c.decodeIfPresent([String].self, forKey: key)) ?? [] }
        let savedStep = (try? c.decodeIfPresent(String.self, forKey: .step)) ?? nil
        step = savedStep.flatMap(OnboardingStep.named) ?? .accessibility
        practiced = (try? c.decodeIfPresent(Bool.self, forKey: .practiced)) ?? false
        finished = (try? c.decodeIfPresent(Bool.self, forKey: .finished)) ?? false
        // Older versions had a Welcome step where the opening screen is now: anyone past it has seen it.
        openingSeen = ((try? c.decodeIfPresent(Bool.self, forKey: .openingSeen)) ?? nil)
            ?? (finished || (savedStep != nil && savedStep != "welcome"))

        let oldHistory = names(.history), oldAuto = Set(names(.autoPassed)), oldSkipped = Set(names(.skipped))
        var history: [OnboardingStep] = []
        for name in oldHistory {
            guard let mapped = OnboardingStep.named(name), mapped != step, !history.contains(mapped) else { continue }
            history.append(mapped)
        }
        self.history = history
        // A merged step passed by itself only if every old step in it did, and counts as skipped only if every old
        // step in it the user saw was skipped.
        let seen = Set(oldHistory).union(oldAuto).union(oldSkipped)
        func members(of new: OnboardingStep) -> [String] { seen.filter { OnboardingStep.named($0) == new } }
        let others = OnboardingStep.allCases.filter { $0 != step }
        autoPassed = Set(others.filter { new in
            let old = members(of: new)
            return !old.isEmpty && old.allSatisfy(oldAuto.contains)
        })
        skipped = Set(others.filter { new in
            let old = members(of: new)
            return old.contains(where: oldSkipped.contains) && old.allSatisfy { oldSkipped.contains($0) || oldAuto.contains($0) }
        })
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(step.rawValue, forKey: .step)
        try c.encode(history.map(\.rawValue), forKey: .history)
        try c.encode(autoPassed.map(\.rawValue).sorted(), forKey: .autoPassed)
        try c.encode(skipped.map(\.rawValue).sorted(), forKey: .skipped)
        try c.encode(practiced, forKey: .practiced)
        try c.encode(finished, forKey: .finished)
        try c.encode(openingSeen, forKey: .openingSeen)
    }
}

/// The step state machine, free of UI so it can be tested: Continue, Back, Skip, steps that pass by themselves,
/// resuming after a quit, and access revoked while away.
struct OnboardingFlow: Equatable {
    var progress: OnboardingProgress
    var conditions: OnboardingConditions
    let steps: [OnboardingStep]

    init(progress: OnboardingProgress = OnboardingProgress(), conditions: OnboardingConditions = OnboardingConditions(),
         steps: [OnboardingStep] = OnboardingStep.allCases) {
        self.progress = progress
        self.conditions = conditions
        self.steps = steps
        if !steps.contains(progress.step) { self.progress.step = steps.first ?? .accessibility }
    }

    var step: OnboardingStep { progress.step }
    var index: Int { steps.firstIndex(of: step) ?? 0 }
    var canGoBack: Bool { progress.history.contains { !progress.autoPassed.contains($0) } }
    var isCurrentSatisfied: Bool { step.isSatisfied(conditions) }

    /// Continue is allowed once a required step is done; optional steps can always move on.
    var canContinue: Bool { !step.isRequired || isCurrentSatisfied }

    enum Mark: Equatable { case current, done, skipped, todo }

    /// What the step list shows for `other`. Steps the user hasn't reached yet stay numbered, even when what they
    /// ask for is already true; they get their check once they're passed.
    func mark(for other: OnboardingStep) -> Mark {
        if other == step { return .current }
        guard let position = steps.firstIndex(of: other), position < index else { return .todo }
        if progress.skipped.contains(other) && !other.isSatisfied(conditions) { return .skipped }
        if other.isRequired && !other.isSatisfied(conditions) { return .todo }
        return .done
    }

    /// Moves to the next step that still needs the user, passing satisfied ones on the way.
    mutating func next() {
        guard canContinue, let start = steps.firstIndex(of: step), start + 1 < steps.count else { return }
        progress.history.append(step)
        var i = start + 1
        while i < steps.count - 1, steps[i].passesWhenSatisfied, steps[i].isSatisfied(conditions) {
            progress.history.append(steps[i])
            progress.autoPassed.insert(steps[i])
            i += 1
        }
        progress.step = steps[i]
    }

    mutating func skip() {
        guard step.canSkip else { return }
        progress.skipped.insert(step)
        next()
    }

    /// Back to the last step the user actually saw (not ones that passed by themselves).
    mutating func back() {
        guard canGoBack else { return }
        while let last = progress.history.popLast() {
            let wasAuto = progress.autoPassed.remove(last) != nil
            if !wasAuto {
                progress.skipped.remove(last)
                progress.step = last
                return
            }
        }
    }

    /// New conditions from the monitor. Returns true when the current step has just become satisfied and should
    /// move on by itself (after the check has been seen).
    @discardableResult
    mutating func update(_ new: OnboardingConditions) -> Bool {
        let was = step.isSatisfied(conditions)
        conditions = new
        return step.passesWhenSatisfied && !was && step.isSatisfied(new)
    }

    /// On opening and reopening: a required step that's no longer true (access revoked, signed out) comes back,
    /// and everything after it is walked again. The step shown, if already done (access granted before Get
    /// started, or while Takes was closed), is passed by itself.
    mutating func resume() {
        guard !progress.finished, let current = steps.firstIndex(of: step) else { return }
        if let broken = steps[..<current].first(where: { $0.isRequired && !$0.isSatisfied(conditions) }) {
            if let cut = progress.history.firstIndex(of: broken) {
                for dropped in progress.history[cut...] { progress.autoPassed.remove(dropped) }
                progress.history.removeSubrange(cut...)
            }
            progress.step = broken
        }
        // Done while Takes was closed (access granted, signed in): move on as if it had happened here.
        if step.passesWhenSatisfied && isCurrentSatisfied {
            let resumedAt = step
            next()
            if step != resumedAt { progress.autoPassed.insert(resumedAt) }
        }
    }

    mutating func finish() {
        if step != .done { progress.history.append(step) }
        progress.step = .done
        progress.finished = true
    }
}

/// The practice box: write, open Takes on it, pick a take, and see it pasted back.
enum PracticeStage: Equatable {
    case write
    case panelOpen
    case pasted
}

enum Onboarding {
    /// First launch of a new install: no settings yet, or onboarding started and not finished.
    static func shouldShow(_ settings: AppSettings) -> Bool { !settings.onboarding.finished }

    static let sampleDraft = "hey can u send me the deck before fri, need to go over it w legal first and they're slow"

    /// The engine Connect a model opens on: the one that already works, else Claude Code when it's installed,
    /// else a local model server that's running, else whatever is picked.
    static func recommendedEngine(current: EngineKind, currentReady: Bool, claudeInstalled: Bool, localRunning: Bool) -> EngineKind {
        if currentReady { return current }
        if claudeInstalled { return .claudeCode }
        if localRunning { return .local }
        return current
    }
}
