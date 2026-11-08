# Takes feature wave: shared brief

Eight sessions work in parallel, each in its own worktree and branch, cut from `claude/competitor-feature-analysis-8dcb80`.
An orchestrator session reviews every branch and merges them. Read this whole file before you start, and again before you commit.

## The end goal

Takes should feel like a premium, native Mac utility: fast, calm, keyboard-first, never in the way. Every feature in this
wave must reach that bar, not just work. When in doubt, choose the simpler UI with fewer controls, and make the default right
so most people never touch the setting.

## The eight workstreams

| # | Session | What it delivers |
|---|---|---|
| 1 | `instant-mode` | A per-preset "write and paste right away" mode: the preset hotkey writes 1 take and pastes it with no panel. Progress, undo and failure shown in the toast. |
| 2 | `proofread` | A built-in Proofread preset tuned for minimal edits (fix mistakes only, keep voice), plus clear inline change marks for proofread results. |
| 3 | `preset-gallery` | A starter pack of built-in presets and a gallery to add them (from Settings › Presets and the empty/new-preset state). Exposes `PresetGallery` (see contracts). |
| 4 | `reply-context` | Opt-in context: what you're replying to (selection, clipboard or the thread text the user explicitly gives) goes into the prompt as context, never rewritten. Shown as a removable chip in compose. |
| 5 | `tone-check` | A one-line read of how a draft / each take will land ("comes across as curt"), cheap and fast, never blocking writing. |
| 6 | `dictation` | Speak a draft into the compose box. On-device speech recognition only (Apple Speech, `requiresOnDeviceRecognition`). |
| 7 | `local-models` | A third engine: local models through Ollama or LM Studio (OpenAI-compatible server on localhost). Claude stays the default. No cloud providers other than Anthropic. |
| 8 | `onboarding` | A first-run onboarding flow that replaces the bare setup window for new users: welcome, permissions, engine, hotkey, a guided first try. The existing setup window stays for "something is missing later". |

## UX rules (all sessions)

- **Use the house style.** Colors from `Theme`, spacing from `Spacing`, the button styles in `Theme.swift`, the controls in
  `FormControls.swift` and `TextInputs.swift`. Don't add new colors, fonts, corner radii or spacing values unless the existing
  ones truly can't do it; if you add one, add it to `Theme`/`Spacing` with a comment.
- **The panel never activates Takes.** The app being typed in keeps focus. That's why the panel draws its own controls; follow
  the same approach for anything in the panel.
- **Keyboard first.** Every new action in the panel has a shortcut shown on its control (the existing `kbd` style), and Esc always
  backs out one step. Don't steal shortcuts already used (see README "The panel" and `PanelController`/`PanelViews`). If you need a
  new shortcut, list it in your change note so the orchestrator can check for clashes across sessions.
- **Copy.** Match the README voice: plain words, short sentences, sentence case, no exclamation marks, no "AI magic" talk. Say
  what happens, not what the feature is called. Error messages say what went wrong and what to do.
- **Light and dark mode**, both checked in snapshots. VoiceOver labels on every new control. Respect Reduce Motion.
- **Privacy is a feature.** Nothing leaves the Mac except to the user's chosen engine. Any new data read or sent must be added to
  `PRIVACY.md` (only the section about your feature) and be opt-in where the README promise ("reads only the focused text box")
  would otherwise change.
- **No nagging, no dark patterns.** Calm defaults, easy to turn off.

## UX research sources (use them, cite them in your change note)

- **Affordance knowledge base**, local: `~/personal/repos/knowledge/affordance`. Start at `kb/domains.yaml`. Read at least
  `kb/auditing/checklist-macos.md`, the `kb/macos/` topics that apply, and the `kb/ai-ux/` topics for AI features
  (`setting-expectations.md`, `ai-errors-and-uncertainty.md`, `trust-and-explainability.md`). Onboarding: `kb/flows/onboarding.md`,
  `kb/flows/permission-requests.md`, `kb/flows/first-use-and-empty-data.md`. Run the checks under "How to evaluate it" against your UI.
- **Mobbin connector** (`search_screens`, `search_flows`): look at 3-5 strong references for your feature before you design it
  (for example Raycast, Linear, Arc, Superhuman, Grammarly, Things, 1Password onboarding). Note which ones shaped your design.

## Avoiding conflicts

Other sessions are changing the same app at the same time. To keep merges clean:

- **Put new code in new files** named after your feature (`InstantMode.swift`, `Dictation.swift`, ...). Keep edits to shared
  files small and local: a hook, a call, one view inserted. Never reformat, reorder or "tidy" code you don't need to change.
- **Shared files** and who may change what:
  - `Store.swift`: add new fields to `Preset` / `AppSettings` only at the end of the struct, decoded with `decodeIfPresent` and a
    default (old settings files must still load). Add a decoding test in your own test file.
  - `PanelViews.swift`, `PanelModel.swift`: insert your view/state; put the view itself in your own file.
  - `Prompt.swift`: add a builder function or a small branch; don't restructure.
  - `Snapshot.swift`: put your screens in an extension in your own file (`Snapshot+<Feature>.swift`) and add one line calling it.
  - `Setup.swift`, `AppDelegate.swift`: `onboarding` owns the first-run flow. Others only add a hook.
  - `EngineTab.swift`: `local-models` owns the engine picker. Others add one section for their setting at the end.
  - `scripts/assemble-app.sh` Info.plist: only `dictation` adds usage strings (microphone, speech recognition).
- **Don't edit** `README.md`, `CHANGELOG.md`, `VERSION`, release scripts or workflows. The orchestrator writes those from your
  change note.
- **Don't drive the live desktop.** Eight sessions share one Mac and one global hotkey (⌥⇧Space). Don't launch the app to press
  hotkeys, don't use computer use, don't change system settings. Verify with tests, `--snapshot` renders and command-line modes.
  The orchestrator does the live end-to-end pass after merging. If your feature needs a live check, describe the exact steps in
  your change note.
- **Engine calls** (Claude Code / API) cost the user's quota: keep live calls to a handful, short drafts, Haiku where possible.

## Contracts between sessions

- `preset-gallery` creates `Sources/Takes/PresetGallery.swift` with `enum PresetGallery { static var all: [Preset] }` and
  `static var starters: [Preset]` (the ones installed on a fresh setup). `proofread` adds its preset there too only after merge;
  until then `proofread` defines `static var proofread: Preset` as an extension in `Proofread.swift`, and the orchestrator lists
  it in the gallery when merging.
- `onboarding` may show a "pick your presets" step. Build it against a small local stand-in and leave a clearly marked
  `// ORCHESTRATOR: wire to PresetGallery.starters` comment; the orchestrator connects it at merge.
- `local-models` adds `EngineKind.local`. Anything that switches over `EngineKind` (setup checks, onboarding) must handle an
  unknown future case gracefully. `onboarding` should leave a `// ORCHESTRATOR: add local engine option` hook.
- `instant-mode` and `tone-check` both add per-preset options to the preset editor: put each in its own small section at the end
  of the editor form, in your own view file.

## Definition of done (every session)

1. Builds: `./build.sh` succeeds with no new warnings.
2. Tests: `swift test` passes. New logic has unit tests in `Tests/TakesTests/<Feature>Tests.swift` (model logic, prompt
   building, decoding of old settings, edge cases and failures).
3. Snapshots: your screens render through `--snapshot`, light and dark, in every state that matters (empty, loading, error,
   success). Look at every PNG yourself and fix what looks off. Copy the final PNGs to `docs/changes/img/<session>/`.
4. Self-audit: run the relevant Affordance checks against your snapshots and fix what fails. List what you checked.
5. Change note: `docs/changes/<n>-<session>.md` with: what changed and why (user words), the flow step by step with the
   screenshot for each step, new settings and their defaults, new shortcuts, privacy impact, research references (Mobbin and
   KB topics), tests added, and any live check the orchestrator must do.
6. Commit everything on your branch with clear messages. Don't push, don't open a pull request, don't merge other branches.
