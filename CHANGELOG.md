# Changelog

All notable changes to Takes. Versions follow [semantic versioning](https://semver.org).

## 0.3.0

- **Onboarding.** A guided first run: Accessibility, connecting Claude (or a local model), privacy, hotkey, starter presets, and a practice box that ends with a real take. Existing users don't see it. The setup window shares its look.
- **Write and paste right away.** A preset's own hotkey can write 1 take and paste it with no panel, with a note to cancel, undo or open it in Takes. Nothing is typed if you've switched apps.
- **Proofread.** A built-in Proofread preset and a "Minimal edits" option for any preset. Fixes are marked inline with a count, and "No mistakes found" replaces an identical take. The word diff handles punctuation and case better and reads each change to VoiceOver.
- **Preset gallery.** 12 ready-made presets to add from Settings › Presets, the new-preset state and the panel's preset list. New installs start with 7; existing presets are never touched.
- **Reply context.** ⌘J or ⇧⌘V adds what you're replying to, as reference only. Optional: use a message you just copied automatically (off by default).
- **Tone.** A short note on how each take may come across, and ⌘T for your draft. Per preset, on by default (off for Proofread).
- **Dictation.** ⌘D speaks a draft, recognised on this Mac only.
- **Local models.** A third engine: Ollama or LM Studio on this Mac, localhost only.
- Preset options (Minimal edits, Show tone, Write and paste right away) sit together in one "How it writes" card.
- Release builds can use the microphone (hardened-runtime entitlement), for dictation.

## 0.2.0 · 2026-11-02

- A new look from the Takes brand book: Ink and Paper accents throughout, and the compact t (a speech bubble whose t flows into its tail) in the menu bar and the panel header.
- A new app icon: the holographic t, with a matching disk icon and a branded install window when you open the .dmg.
- The panel header shows the icon of the app you're writing in, and preset app chips and the app menu show app icons too.
- The panel is evenly spaced: one spacing scale on every screen, and the takes window fits its cards instead of leaving a gap under them.
- The panel opens beside the text box you're writing in, never over it. Settings › Engine › Open the panel lets you pick a spot instead (next to the text box, a screen corner, top or bottom center, or the center); if that spot would cover the text box, the panel moves to the nearest clear spot.
- Setup now flags a Takes hotkey that macOS also uses (for example ⌃⌥Space for "Show Finder search window" or for switching input sources). Both used to fire: Finder opened, took the focus and pulled full-screen apps off their Space.
- The chosen take is pasted only once the app you were writing in is back in front. If Takes can't get back to it, nothing is typed anywhere else; the take stays on the clipboard and the toast says to press ⌘V.
- The first summon in Electron apps (Claude, Slack) now reads the field's text without you selecting it first.
- The panel and the confirmation toast open on the display the caret is on, also when the caret sits at the edge between two displays.

## 0.1.0 · 2026-10-27

First public release.

- Hotkey panel in any text field: draft, preset, 1–5 takes from Claude, paste back.
- Presets with instructions, Do and Avoid rules, write-like-me examples, reply language, per-app auto-pick and their own hotkeys.
- Takes stream in side by side, with a "Changes" view, refine, and "More like this".
- Two engines: your own Claude Code (subscription) or your own Anthropic API key.
- Works in Slack, Claude and other web-based apps; reads only the focused text box.
- Setup window that checks Accessibility, the Claude connection, privacy consent and the hotkey.
- Settings for presets, voice rules, engine, panel behavior and local history.
- Automatic updates (Sparkle). Takes asks before it starts checking.
