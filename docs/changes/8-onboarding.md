# 8 · Onboarding

## What changed and why

A new user used to land on a "Set up Takes" checklist and then had to find a text box somewhere to try the hotkey.
Now the first launch opens a short guided window that ends with a real take pasted into a practice box inside it,
so the first good take happens before the window closes.

- One step at a time, with the step list on the left: a check for each step that's done (or was already true), a dash
  for a skipped one.
- Each step has one primary action (↵), Back (Esc), and Skip where skipping is safe (hotkey, presets, try it).
- Steps that are already true pass by themselves with a check. A step that comes true while you're on it (access
  granted in System Settings, Claude Code signed in in Terminal) shows its check for a moment, then moves on and brings
  the window back to the front.
- Close the window any time (⌘W, or Esc on the first step). Takes keeps your place in settings and reopens there. The
  menu-bar item "Finish setting up Takes…" and the hotkey reopen it.
- **People who already use Takes never see onboarding.** Settings saved before this change have no `onboarding` key and
  decode as finished. They keep the setup window as before.
- The setup window stays for "something broke later" (access revoked, signed out, hotkey taken). It now uses the same
  step components (badge, status pill, card) and background as onboarding, and Esc closes it.

## The flow

| Step | Screenshot (light / dark) | Notes |
|---|---|---|
| 1 Welcome | `img/onboarding/1-welcome-*.png` | One-line promise and the flow: press the hotkey → write → pick a take → pasted back. |
| 2 Accessibility | `2-accessibility-waiting-*`, `2-accessibility-allowed-*` | What access means in three plain lines before the system pane opens. "Waiting for access" with a spinner, live check every second. Window floats above System Settings on this step only. |
| 3 Connect Claude | `3-engine-checking-*`, `3-engine-sign-in-*`, `3-engine-copied-*`, `3-engine-not-installed-*`, `3-engine-api-key-*`, `3-engine-ready-*` | Two options. Claude subscription: the primary copies `claude auth login` and opens Terminal; the page moves on when sign-in is detected. API key: pasted inline, saved to the keychain (no trip to Settings). |
| 4 Your text | `4-privacy-*` | Same consent meaning and wording as the setup step, split into four lines. Primary "I understand". |
| 5 Hotkey | `5-hotkey-free-*`, `5-hotkey-taken-*` | Large keycaps. Clash detection uses the existing `SystemShortcuts` + Carbon registration (`takenHotKeys`), names the macOS shortcut, and lets you record another one in place. Passes by itself when free. |
| 6 Presets | `6-presets-*`, `6-presets-none-*` | Keep the starters you'll use (all kept by default). Needs at least one. Custom presets are never touched. |
| 7 Try it | `7-practice-write-*`, `7-practice-panel-open-*`, `7-practice-pasted-*` | A practice box with a sample draft. The hotkey (or "Open Takes") opens the real panel beside the box; the chosen take is pasted back into the box. A three-line checklist follows along. |
| 8 Done | `8-done-*` | Points at the menu-bar icon, repeats the hotkey, mentions Settings for anything skipped. |
| Setup window | `9-setup-window-*` | Restyled with the shared components. |

All 38 PNGs are in `docs/changes/img/onboarding/`. Render them with `Takes --snapshot <folder>` (they go in
`<folder>/onboarding`).

## Code

- `Onboarding.swift`: `OnboardingStep`, `OnboardingConditions`, `OnboardingProgress` (saved), and `OnboardingFlow`,
  the UI-free state machine: Continue, Back (skips auto-passed steps), Skip, auto-pass, live "came true", resume.
- `OnboardingModel.swift`: the window's model (live binding to `SetupMonitor` and `Store`, the primary action per
  step, presets, practice) and `OnboardingWindowController`.
- `OnboardingView.swift`: the window's views.
- `StepComponents.swift`: `StepBadge`, `StatusPill`, `StepCard`, `StepNote`, shared with the setup window.
- `Snapshot+Onboarding.swift`: every step and state, light and dark (sets `NSAppearance` too, so dynamic colors resolve).
- Shared files, small edits:
  - `Store.swift`: `AppSettings.onboarding` at the end, decoded with `decodeIfPresent ?? .existingUser`.
  - `AppDelegate.swift`: first launch shows onboarding instead of setup; "Finish setting up" and the blocked hotkey
    open onboarding while it's unfinished; on the practice step the hotkey goes to the practice box.
  - `PanelController.swift`: `summonPractice(text:boxFrame:paste:cancel:)`, the test seam. Same panel and
    `PanelModel`; the box's text and frame stand in for the focused field; the chosen take goes back to onboarding
    instead of `Paster`. `summon()` and `close()` end a practice run.
  - `Setup.swift`: `SetupStep` built from the shared components; window background and `.fullScreenNone`; Esc closes.
  - `Snapshot.swift`: one line calling `renderOnboarding`.

## Hooks for the orchestrator

- `// ORCHESTRATOR: wire to PresetGallery.starters` in `OnboardingModel.swift` (`OnboardingPresets.starters`, a stand-in
  that returns `Store.defaultPresets`). Presets are matched by name.
- `// ORCHESTRATOR: add local engine option` in `OnboardingView.swift` (`EngineStep`, a third `option(...)`) and in
  `OnboardingModel.primaryTitle` (its primary action, also in `primary()`). Nothing in onboarding switches over
  `EngineKind`, so the new case compiles; until wired, `.local` is treated like the Claude Code option.
- `// ORCHESTRATOR: dictation permission status` in `OnboardingView.swift` (`DoneStep`): one line with the microphone /
  speech status from `dictation`. Dictation is opt-in, so it isn't a required step and its permission is still asked in
  context, the first time someone dictates.

## Settings and defaults

- `AppSettings.onboarding` (`OnboardingProgress`): step, history, auto-passed, skipped, practiced, finished. New installs
  start at Welcome; old settings decode as finished.
- No new user-facing settings.

## Shortcuts

In the onboarding window only: ↵ primary action (not on the practice step, where ↵ types in the box), Esc back / close on
the first step, ⌘W close. No new global or panel shortcuts. The summon hotkey is reused on the practice step.

## Privacy

No new data is read or sent. The practice box's text goes to Claude exactly like any other draft, and only when the user
asks for takes. The API key typed in onboarding goes to the keychain, as in Settings. `PRIVACY.md` unchanged.

## Research

- Affordance KB: `kb/flows/onboarding.md` (shortest path to the first success; teach by doing; skip as visible as
  continue), `kb/flows/permission-requests.md` (explain before the system pane; live detection; resume without relaunch),
  `kb/flows/first-use-and-empty-data.md` (sample draft in the practice box), `kb/ethics/nagging-and-forced-action.md`
  (no re-asking; the window can always be closed; skipped steps aren't re-prompted, only mentioned once on Done),
  `kb/macos/mac-install-update-permissions.md` (Accessibility needs a guided flow), `kb/macos/menu-bar-extras.md`
  (activate the app when an agent app opens a window; point out the menu-bar icon).
- Mobbin: Linear web onboarding (page progress, "I'll do this later" skip, the "That was easy, remember ⌘K" practice
  moment shaped the Try it → Done pair), Air and Twenty onboarding (one centred task per screen, one primary button).
  Raycast/CleanShot/1Password Mac flows aren't on Mobbin (web/iOS only); their pattern (sidebar of steps, live permission
  check) is the macOS installer convention used here.

## Self-audit (Affordance checks run against the snapshots)

- Screens before first success: 6 at most, fewer when things are already set; each satisfied step passes by itself.
- Every optional step has Skip next to Back, same style weight; required ones can be left by closing the window.
- No permission prompt before its explanation; the system pane opens only from the primary button.
- Recovery: revoked access or sign-out while away brings that step back on reopen (tested); after finishing, problems
  go to the setup window, not onboarding.
- Preselected: starter presets are all kept by default (they're already installed); nothing marketing-like.
- Light and dark checked for every state. VoiceOver: the step reads before the step list; each list row says
  "Step n, title, done/current/to do"; the practice box, preset cards, hotkey recorder and API key field have labels.
  Reduce Motion: step changes cross-fade instead of sliding.
- Window: fixed 780×560, no full screen, remembers its position, floats only on the Accessibility and Claude steps.

## Tests

`Tests/TakesTests/OnboardingTests.swift` (25 tests): new install vs existing user, progress round trip, unknown step
names from a newer version, walking every step, auto-pass with checks, Back over auto-passed steps, Skip only on optional
steps and Back undoing it, taken hotkey, "came true" fires once, finish, resume at the same step, revoked access and
sign-out on resume, a step done while away, finished left alone, applying presets, keycaps; the practice step through a
fake panel (summon → write → pick → paste, panel closed without a take, hotkey outside the practice step, skip), the
auto-advance after access is granted, and Esc backing out then closing.

## Live check for the orchestrator

1. Move `~/Library/Application Support/Takes/settings.json` aside, remove Takes from Accessibility, launch the built app.
   Onboarding opens. Continue → Accessibility → "Open System Settings", switch Takes on: the check appears and the
   window comes back on the Claude step.
2. With Claude Code signed in, the Claude step should pass by itself. Quit Takes on the Presets step, relaunch: it
   reopens on Presets.
3. On Try it, click in the box and press ⌥⇧Space. The panel opens beside the window with the sample draft. ↵, pick a
   take, ↵: it lands in the practice box, the checklist ticks, Continue → Done → Start using Takes.
4. Put the old `settings.json` back and relaunch: no onboarding.
5. Check the hotkey step with the summon hotkey bound to a macOS shortcut such as "Show Finder search window" (taken state names it).
