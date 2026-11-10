# How Takes works inside

A guide for new contributors. It covers what happens between pressing the hotkey and pasting a take, and where to make the most common changes. For building, debugging tools and the file table, see [development.md](development.md).

## The big picture

Takes is one executable target (`Sources/Takes`) with no server. It's an `LSUIElement` menu-bar app: AppKit owns the menu bar, windows, hotkeys and accessibility calls, and SwiftUI draws the screens.

```
 hotkey (HotKey.swift)
   │
   ▼
 AppDelegate.summonPanel ──► setup missing? ──► Setup window / onboarding
   │
   ├─► preset writes instantly? ──► InstantMode: 1 take, paste, toast
   │
   ▼
 PanelController.summon
   │  FocusReader.snapshot: read the focused text box (AX value → range → ⌘A ⌘C fallback)
   ▼
 PanelModel (screens, draft, preset, takes)
   │  PromptBuilder.system/user ──► EngineRequest
   │  Engines.current(settings) ──► TakesEngine.run (streams partial takes)
   │      ├─ ClaudeCodeEngine  `claude -p` subprocess
   │      ├─ APIEngine         Anthropic Messages API
   │      ├─ ChatGPTEngine     Responses API, signed in with ChatGPT
   │      ├─ ProviderEngine    OpenAI-compatible https API, user's key
   │      └─ LocalEngine       OpenAI-compatible server on localhost
   │  TakeSplitter: plain text split on "===" lines
   │  side checks: tone notes (ToneCheck), English coach (CoachRun)
   ▼
 PanelViews (SwiftUI): takes side by side, Changes (Diff), refine, more like
   │
   ▼
 Paster.paste: refocus, check it is the same text box, paste, restore the clipboard if nothing else was copied
```

## Main pieces

| Piece | Type and file | What it does |
|---|---|---|
| App entry | `main.swift`, `AppDelegate` | Menu-bar item and menu, registers hotkeys, decides between setup, instant mode and the panel. |
| Hotkeys | `HotKeyCenter` (`HotKey.swift`) | Carbon global hotkeys: the summon hotkey plus one per preset. |
| Reading the field | `FocusReader`, `FocusSnapshot` | Reads only the focused text box, its caret and frame, and never a password field. Logs metadata to `focus.log`, never text. |
| Panel window | `PanelController`, `KeyPanel`, `Placement` | Floating panel near the caret. Owns summon, close and paste. |
| Panel state | `PanelModel` | The current screen, draft, preset, take count, streamed takes, history entry and side checks. One run at a time (`runToken`). |
| Prompts | `PromptBuilder` (`Prompt.swift`) | Turns a preset (instruction, Do, Avoid, examples, language) and voice rules into the system prompt, and the draft plus mode (fresh, refine, more like) into the user message. |
| Engines | `TakesEngine` protocol, `Engines.current` (`Engine.swift`) | One `run(_:onUpdate:)` that streams takes. Each engine file implements it. |
| Pasting | `Paster` | Puts focus back and checks it's the same text box, then pastes or replaces all and restores the user's clipboard if nothing else was copied. Reports a `Paster.Outcome` (pasted, couldn't return, field changed); a refused paste sends no keys. |
| Storage | `Store` (`Store.swift`) | Presets, settings and history as JSON in `~/Library/Application Support/Takes`. A file it can't read is first copied to `<name>.unreadable-<date>.json`, so nothing is saved over it. Secrets go in the Keychain, never here. |
| Settings | `SettingsWindow` and `*Tab.swift`, `*Views.swift` | One tab per area: General, Presets, Writing, Coach, Model, History. |
| First run | `Onboarding*`, `Setup.swift` (`SetupMonitor`) | Accessibility, engine connection, privacy notice, hotkey, starter presets and practice. |
| Crash reports | `CrashReports`, `CrashOfferView` (`StatusPopover.swift`) | After a crash, offers once to open a GitHub bug report with a summary of macOS's crash report and shows the file in Finder. Reads only; sends nothing. `ReportProblem` builds the link and keeps it under 8,000 characters, cutting a longer summary and saying so. |
| Updates | `Updater` (Sparkle) | Only in signed release builds, and only after the user agrees. |
| Screenshots | `Snapshot*.swift` | `--snapshot <folder>` renders every screen with sample data. |

## Threads and state

- UI types (`PanelModel`, `Store`, view models) are `ObservableObject`s used on the main thread.
- Engines stream on background tasks. `onUpdate` is called off the main thread, and `PanelModel` hops back with `Task { @MainActor in … }` and ignores updates from an older run (`runToken`).
- The package builds with Swift 6 tools in Swift 5 language mode (`swiftLanguageMode(.v5)`), so strict concurrency checking isn't on yet.

## Common changes

**A new built-in preset or gallery entry.** Add it in `PresetGallery.swift`. Its prompt comes from `PromptBuilder`, so check the result with a `PromptBuilderTests` case.

**A change to how prompts are written.** Edit `Prompt.swift` and update `PromptBuilderTests`. Keep the `===` separator contract with `TakeSplitter`, because plain text streams faster than structured output (see [development.md › Performance](development.md#performance)).

**A new engine or provider.** Talk about it in an issue first. Implement `TakesEngine`, add an `EngineKind` case in `Store.swift`, wire it in `Engines.current`, add its settings view, and update [PRIVACY.md](../PRIVACY.md) with where the draft goes. Most OpenAI-compatible services fit into `ProviderEngine` without a new engine.

**An app where reading or pasting fails.** Reproduce it with `--focus-test` and `--ax-probe` (see [development.md](development.md#how-takes-reads-text-fields)), then fix it in `FocusReader` or `Paster`. Never widen what's read beyond the focused text box.

**A new setting.** Add it to `AppSettings` in `Store.swift` with a default, decoded with `decodeIfPresent` so older settings files still load (`SettingsDecodingTests`), and add the control to the matching tab.

**A new screen or UI change.** Build it in SwiftUI with the shared pieces in `Theme.swift`, `FormControls.swift` and `StepComponents.swift`, add it to the snapshot renderer, and include light and dark screenshots in the pull request.

## Tests

`Tests/TakesTests` holds unit tests for prompt building, take splitting, word diffs, settings decoding, panel placement, onboarding, presets and each feature. `*LiveTests.swift` call real models and are skipped unless an environment variable is set, so CI never runs them.
