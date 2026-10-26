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
build/Takes.app/Contents/MacOS/Takes --bench --runs 5 --model haiku --effort low
build/Takes.app/Contents/MacOS/Takes --bench --runs 5 --model sonnet --effort low
build/Takes.app/Contents/MacOS/Takes --bench --runs 5 --model sonnet --naive
```

`--naive` runs Claude Code with its default setup: tools, MCP servers and user settings all load. Without it, the engine skips all of these. Each run prints three numbers: total time, the time Claude Code reports for the model call, and the difference between them (startup overhead).

## How it calls Claude

`claude -p` with a preset-built system prompt, `--model`, `--effort`, `--output-format json` and a `--json-schema` that asks for exactly N takes in one call. It runs from an empty temp folder so no CLAUDE.md is picked up. See `Sources/Takes/Engine.swift`.
