# Takes (M0 spike)

Press ⌃⌥Space in any text field, rewrite the draft with a preset, and get several takes back from Claude. Pick a take and it's pasted into the field you were in.

This spike exists to answer one question: is running the local Claude Code CLI (which uses your Claude subscription) fast enough for a hotkey tool?

## Build and run

```
./build.sh
open build/Takes.app
```

On first launch macOS asks for Accessibility access (System Settings › Privacy & Security › Accessibility). Takes needs it to read the focused field and to send ⌘V. Each rebuild is ad-hoc signed with a new signature, so macOS may ask again. If the hotkey works but nothing gets prefilled or pasted, remove Takes from the list and add it again.

The `claude` command must be signed in (`claude auth login`). The desktop app has its own login, separate from this one.

## Using it

- ⌃⌥Space opens the panel next to the caret, prefilled with the selection, or else with the field's text.
- Pick a preset, the number of takes, the model and the effort. ⌘↵ writes the takes.
- Click a take or press ⌘1–5 to paste it. If the draft came from the whole field, the field's text is replaced (⌘A, then ⌘V). Your clipboard is restored afterwards.
- Esc closes the panel.

Each run is logged to `~/Library/Logs/Takes/runs.jsonl`.

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

`claude -p` with a preset-built system prompt, `--model`, `--effort` and `--output-format stream-json --include-partial-messages`. Takes are separated by `===` lines and appear in the panel as they're written. It runs from an empty temp folder so no CLAUDE.md is picked up. See `Sources/Takes/Engine.swift`.
