# Using Takes

The full reference for the panel and settings. For a quick start, see the [README](../README.md).

## Setup

On first launch Takes opens a guided setup:

- allow Accessibility access;
- connect Claude, with your own Claude Code (subscription) or an Anthropic API key, or pick a local model (Ollama or LM Studio);
- read what Takes reads and sends;
- check the hotkey is free and pick your starter presets;
- try it once in a practice box, ending with a real take.

You can close it at any time; it reopens where you left off (menu-bar icon › Finish setting up Takes…). People who used Takes before onboarding existed never see it.

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

## Settings

Open them from the menu-bar icon, or with ⌘, in the panel.

- **Presets:** Browse presets adds ready-made ones (Proofread, Slack message, Polish email, Shorter, Friendlier, More direct, and more) as your own copies; new installs start with seven. Each preset has a name, color, an optional hotkey of its own, instruction, Do and Avoid lists, up to five write-like-me examples, reply language, the apps where it's picked automatically, the defaults for takes, model, effort and length, and "How it writes": Minimal edits, Show tone, and Write and paste right away. "Try it" runs the preset as edited. Presets can be duplicated, exported and imported as JSON.
- **Voice:** rules applied on top of every preset, and the languages you write in. These start as your Mac's languages (System Settings › General › Language & Region); presets can reply in any language, and Browse presets offers a "Translate to …" preset for each of yours.
- **Engine:** Claude Code on this Mac (your subscription), an Anthropic API key (stored in the keychain), or a local model (Ollama or LM Studio on this Mac; Takes finds them and lists their models, with a Test button). Also the dictation language, and an opt-in to use the clipboard as reply context when it looks like a message you just copied. Also defaults for new presets, the summon hotkey, where the panel opens, what the draft starts with, clipboard restore and history.
- **History:** the last 30 days of runs, stored only on this Mac.

Everything is saved in `~/Library/Application Support/Takes/`. Each run's timing is logged to `~/Library/Logs/Takes/runs.jsonl`. [PRIVACY.md](../PRIVACY.md) lists every file and how to remove it.

## Uninstall

Quit Takes from its menu, move it from Applications to the Trash (or `brew uninstall --cask takes`), and delete `~/Library/Application Support/Takes` and `~/Library/Logs/Takes`. You can also remove it from System Settings › Privacy & Security › Accessibility.
