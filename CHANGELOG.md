# Changelog

All notable changes to Takes. Versions follow [semantic versioning](https://semver.org).

## Unreleased

- Setup now flags a Takes hotkey that macOS also uses (for example ⌃⌥Space for "Show Finder search window" or for switching input sources). Both used to fire: Finder opened, took the focus and pulled full-screen apps off their Space.
- The chosen take is pasted only once the app you were writing in is back in front. If Takes can't get back to it, nothing is typed anywhere else; the take stays on the clipboard and the toast says to press ⌘V.
- The first summon in Electron apps (Claude, Slack) now reads the field's text without you selecting it first.

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
