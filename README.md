# Takes

A macOS menu-bar app. Focus any text field and press ⌃⌥Space. Write what you mean, pick a preset, and choose from several takes written by Claude. The one you choose is pasted back into the field you were in.

## Build and run

```
./build.sh
open build/Takes.app
```

On first launch macOS asks for Accessibility access (System Settings › Privacy & Security › Accessibility). Takes needs it to read the focused field and to paste. Each rebuild is ad-hoc signed with a new signature, so macOS may ask again. If the hotkey works but nothing gets prefilled or pasted, remove Takes from the list and add it again.

## Setup

Takes watches everything it needs and opens a "Set up Takes" window when something's missing: Accessibility access, a working Claude engine (Claude Code signed in, or an API key) and a free hotkey. The window updates live as each step is done. While something is missing, the menu-bar icon shows an exclamation mark and the hotkey opens this window instead of the panel. You can open it any time from the menu-bar icon › Setup and permissions.

## The panel

- **Compose.** The draft starts with the field's text (or the selection). The preset picked for this app is pre-selected. Change the number of takes, the model and the effort for this run only. ↵ writes the takes, ⇧↵ adds a line, ⇥ (or / in an empty draft) opens the presets, ⌘1–9 switches preset, ⌘K opens a menu of settings.
- **Presets.** Type to filter, ↑↓ and ↵ to choose. A preview on the right shows the preset's instruction and its Do and Avoid rules.
- **Takes.** The takes stream in side by side. ←→ select a take, ↵ or double-click pastes it, ⌘1–5 pastes directly, ⌘C copies without pasting. "Changes" shows the edits against your draft. The refine box reworks the selected take ("warmer", "drop the second ask"), and "More like take N" writes new takes in its style. ⌘E edits the draft, ⌘R regenerates, Esc goes back.
- **After pasting.** A toast confirms the paste and that your clipboard is back. ⌘Z in the app undoes the paste, and "Save as example" adds the take to the preset's write-like-me examples.

## Settings (menu-bar icon, or ⌘, in the panel)

- **Presets:** name, color, an optional hotkey of its own, instruction, Do and Avoid lists, up to five write-like-me examples, reply language, the apps where it's picked automatically, and the defaults for takes, model, effort and length. "Try it" runs the preset as edited. Presets can be duplicated, exported and imported as JSON.
- **Voice:** rules applied on top of every preset.
- **Engine:** Claude Code on this Mac (your subscription) or an Anthropic API key (stored in the keychain). Also defaults for new presets, the summon hotkey, where the panel opens, what the draft starts with, clipboard restore and history.
- **History:** the last 30 days of runs, stored only on this Mac.

Everything is saved in `~/Library/Application Support/Takes/`. Each run's timing is logged to `~/Library/Logs/Takes/runs.jsonl`.

`Takes --snapshot <folder>` renders every screen with sample data to PNGs.

## Reading and pasting in web-based apps

Takes only ever reads a real text box (text area, text field, search or combo box), never the page or document around it. A box's value is trusted even when it's blank: an empty web text box reports a line break, which means empty. Only when a text box has no value at all does Takes try its character range, then its own Chromium text-marker range. Only after those does it copy with ⌘A ⌘C, then restore your clipboard. Drafts longer than 10,000 characters are never prefilled.

`build/Takes.app/Contents/MacOS/Takes --focus-test` reads the frontmost app's focused box without sending any keys and prints how it was read. Before pasting it puts focus back into the original field. Every summon is logged to `~/Library/Logs/Takes/focus.log` (app, element role, which method worked, how many characters).

`open -n build/Takes.app --args --ax-probe 3` waits 3 seconds and writes what the frontmost app reports about its focused element to `~/Library/Logs/Takes/ax-probe.txt`.

## Measuring

```
build/Takes.app/Contents/MacOS/Takes --bench --runs 5 --model claude-sonnet-5-5 --effort low
build/Takes.app/Contents/MacOS/Takes --bench --runs 5 --model claude-haiku-5-5 --takes 5
```

Each run prints the time to the first streamed words and the time until all takes are done. `--naive` runs Claude Code with its default setup: tools, MCP servers and user settings all load.

Results on 2026-10-26, 3 takes of a 25-word draft, low effort:

| Model | First words (median) | All takes (median) |
|---|---|---|
| Haiku 5.5 | 1.2 s | 2.6 s |
| Sonnet 5.5 | 1.3 s | 2.8 s |
| Sonnet 5.5, 5 takes | 1.2 s | 3.4 s |
| Opus 5.5 | 1.8 s | 4.1 s |
| Opus 5.5, medium effort | 1.6 s | 3.9 s |

What made it fast:
- **Plain text, not `--json-schema`.** Structured output costs Claude Code a second model turn, about doubling the time (Sonnet: about 8.6 s with it, 2.8 s without).
- **Full model IDs.** On this account the `sonnet` alias still resolved to Sonnet 4.6 and `haiku` to Haiku 4.5. Those were 2 to 6 times slower.
- Claude Code's own startup is under 0.5 s. Switching off tools, MCP servers and settings barely changes the total.

Opus 5.5 needs Claude Code 2.1.280 or newer (`claude update`). The Opus rows were measured on 2.1.310.

## How it calls Claude

With Claude Code: `claude -p` with a preset-built system prompt, `--model`, `--effort` and `--output-format stream-json --include-partial-messages`. Takes are separated by `===` lines and appear in the panel as they're written. It runs from an empty temp folder so no CLAUDE.md is picked up. See `Sources/Takes/ClaudeCodeEngine.swift`. With an API key, the Messages API is called directly with streaming (`Sources/Takes/APIEngine.swift`).

## Privacy

Takes sends your draft only to Anthropic, directly from your Mac and under your own Claude account. The developer runs no server and receives nothing; there's no analytics or tracking. See [PRIVACY.md](PRIVACY.md) for exactly what's read, sent and stored. Claude can get things wrong: read a take before you send it.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) and sign the [Contributor License Agreement](CLA.md) before your first pull request.

## License

The code is released under the [MIT License](LICENSE). The "Takes" name and icon aren't covered by the license; please don't use them for your own fork or product.

Takes isn't made, endorsed or supported by Anthropic. It runs Claude Code or calls the Claude API with your own account.
