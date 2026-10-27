# Changelog

All notable changes to Takes. Versions follow [semantic versioning](https://semver.org).

## Unreleased

- Fixed: over a full-screen app the panel could jump to the desktop. When the Takes hotkey is also one of macOS's own shortcuts (for example "Show Finder search window" on ⌃⌥Space), both fired; Takes now leaves such a hotkey unregistered and setup names the clash.
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
