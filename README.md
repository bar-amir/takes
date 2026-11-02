# Takes

A macOS menu-bar app. Focus any text field and press ⌃⌥Space. Write what you mean, pick a preset, and choose from several takes written by Claude. The one you choose is pasted back into the field you were in.

## Install

1. Download `Takes-<version>.dmg` from [Releases](https://github.com/bar-amir/takes/releases), open it and drag Takes to Applications.
2. Open Takes. It lives in the menu bar (a speech-bubble icon) and opens a setup window.
3. A short guided window walks you through it:
   - allow Accessibility access;
   - connect Claude, with your own Claude Code (subscription) or an Anthropic API key, or pick a local model (Ollama or LM Studio);
   - read what Takes reads and sends;
   - check the hotkey is free and pick your starter presets;
   - try it once in a practice box, ending with a real take.
4. Click into any text box, press ⌃⌥Space and write.

Requires macOS 14 or later. Takes is signed with a Developer ID and notarized by Apple.

**Uninstall:** quit Takes from its menu, move it from Applications to the Trash, and delete `~/Library/Application Support/Takes` and `~/Library/Logs/Takes`. You can also remove it from System Settings › Privacy & Security › Accessibility.

## Releasing

Releases are built by GitHub Actions ([.github/workflows/release.yml](.github/workflows/release.yml)):

1. In a pull request, bump `VERSION` and add a `## <version>` section to `CHANGELOG.md`. Merge it.
2. Tag the merge commit and push the tag: `git tag v0.1.0 && git push origin v0.1.0`.
3. Approve the run in the protected `release` environment (GitHub › Actions). Only then can it read the signing secrets.
4. It builds a universal app, signs it with the Developer ID (hardened runtime, Sparkle signed inside out), notarizes and staples the app and the disk image, checks them with Gatekeeper, signs the update for Sparkle, attests build provenance, and publishes the GitHub Release with the `.dmg`, its checksum and `appcast.xml`.

Installed copies find updates through `https://github.com/bar-amir/takes/releases/latest/download/appcast.xml`. Each release also carries the same disk image as `Takes.dmg`, so `https://github.com/bar-amir/takes/releases/latest/download/Takes.dmg` always downloads the latest version (use it for download buttons).

One-time setup: run `scripts/setup-release-secrets.sh` to store the Developer ID certificate, an App Store Connect API key and the Sparkle update key as environment secrets. `scripts/release.sh` runs the same steps on your Mac (`--unsigned` to test without signing).

## Build and run

```
./build.sh
open build/Takes.app
```

On first launch macOS asks for Accessibility access (System Settings › Privacy & Security › Accessibility). Takes needs it to read the focused field and to paste. Each rebuild is ad-hoc signed with a new signature, so macOS may ask again. If the hotkey works but nothing gets prefilled or pasted, remove Takes from the list and add it again.

## Setup

On first launch Takes opens the onboarding window described under Install. You can close it at any time; it reopens where you left off (menu-bar icon › Finish setting up Takes…). People who used Takes before onboarding existed never see it.

After that, Takes watches everything it needs and opens a "Set up Takes" window when something's missing: Accessibility access, a working Claude engine (Claude Code signed in, or an API key) and a free hotkey. The window updates live as each step is done. While something is missing, the menu-bar icon shows an exclamation mark and the hotkey opens this window instead of the panel. You can open it any time from the menu-bar icon › Setup and permissions.

## The panel

- **Compose.** The draft starts with the field's text (or the selection). The preset picked for this app is pre-selected. Change the number of takes, the model and the effort for this run only. ↵ writes the takes, ⇧↵ adds a line, ⇥ (or / in an empty draft) opens the presets, ⌘1–9 switches preset, ⌘K opens a menu of settings.
- **What you're replying to.** ⌘J adds the message you're answering (paste or type it), ⇧⌘V uses the clipboard's text. It shows as a chip above the draft and goes to Claude as reference only, never rewritten. ⇧⌘⌫ removes it. It's cleared on every summon.
- **Dictation.** ⌘D speaks into the draft at the caret; ⌘D or Esc stops, ↵ stops and writes the takes. Speech is recognised on this Mac only; if the Mac has no on-device model for the language, Takes says so instead of using a server.
- **How it reads.** ⌘T gives one line on how your draft may come across, and at most one thing to try. It goes away when you edit the draft.
- **Presets.** Type to filter, ↑↓ and ↵ to choose. A preview on the right shows the preset's instruction and its Do and Avoid rules.
- **Takes.** The takes stream in side by side, each with a short note on how it may come across (presets can turn this off). ←→ select a take, ↵ or double-click pastes it, ⌘1–5 pastes directly, ⌘C copies without pasting. "Changes" shows the edits against your draft. The refine box reworks the selected take ("warmer", "drop the second ask"), and "More like take N" writes new takes in its style. ⌘E edits the draft, ⌘R regenerates, Esc goes back.
- **Proofread.** Presets with "Minimal edits" (like the built-in Proofread) fix mistakes only. Their takes open with each fix marked (struck through and underlined, not color alone) and "N fixes"; when there's nothing to fix the panel says "No mistakes found" and ↵ pastes your original.
- **Write and paste right away.** A preset with its own hotkey can skip the panel: the hotkey writes 1 take and pastes it. A note by the text box shows it writing (Esc cancels), then ⌘Z to undo and "Open in Takes" to refine or pick another. If you've switched apps by then, nothing is typed anywhere.
- **After pasting.** A toast confirms the paste and that your clipboard is back. ⌘Z in the app undoes the paste, and "Save as example" adds the take to the preset's write-like-me examples.

## Settings (menu-bar icon, or ⌘, in the panel)

- **Presets:** Browse presets adds ready-made ones (Proofread, Slack message, Polish email, Shorter, Friendlier, More direct, and more) as your own copies; new installs start with seven. Each preset has a name, color, an optional hotkey of its own, instruction, Do and Avoid lists, up to five write-like-me examples, reply language, the apps where it's picked automatically, the defaults for takes, model, effort and length, and "How it writes": Minimal edits, Show tone, and Write and paste right away. "Try it" runs the preset as edited. Presets can be duplicated, exported and imported as JSON.
- **Voice:** rules applied on top of every preset, and the languages you write in. These start as your Mac's languages (System Settings › General › Language & Region); presets can reply in any language, and Browse presets offers a "Translate to …" preset for each of yours.
- **Engine:** Claude Code on this Mac (your subscription), an Anthropic API key (stored in the keychain), or a local model (Ollama or LM Studio on this Mac; Takes finds them and lists their models, with a Test button). Also the dictation language, and an opt-in to use the clipboard as reply context when it looks like a message you just copied. Also defaults for new presets, the summon hotkey, where the panel opens, what the draft starts with, clipboard restore and history.
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

With Claude Code: `claude -p` with a preset-built system prompt, `--model`, `--effort` and `--output-format stream-json --include-partial-messages`. Takes are separated by `===` lines and appear in the panel as they're written. It runs from an empty temp folder so no CLAUDE.md is picked up. See `Sources/Takes/ClaudeCodeEngine.swift`. With an API key, the Messages API is called directly with streaming (`Sources/Takes/APIEngine.swift`). With a local model, Takes streams from the server's OpenAI-compatible chat endpoint and only ever connects to `localhost` (`Sources/Takes/LocalEngine.swift`). Tone notes are one extra short request after the takes (Haiku, or the local model).

## Privacy

Takes sends your draft only to Anthropic, directly from your Mac and under your own Claude account, or, with a local model, nowhere outside your Mac. Dictation audio never leaves the Mac. The developer runs no server and receives nothing; there's no analytics or tracking. See [PRIVACY.md](PRIVACY.md) for exactly what's read, sent and stored. Claude can get things wrong: read a take before you send it.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) and sign the [Contributor License Agreement](CLA.md) before your first pull request.

## License

The code is released under the [MIT License](LICENSE). The "Takes" name and icon aren't covered by the license; please don't use them for your own fork or product.

Takes isn't made, endorsed or supported by Anthropic. It runs Claude Code or calls the Claude API with your own account.
