# Using Takes

The full reference for the panel and settings. For a quick start, see the [README](../README.md).

## Setup

On first launch Takes opens a guided setup with three steps:

- **Allow access.** Accessibility access, so Takes can read the text box you're in and paste into it.
- **Connect a model.** Your Claude subscription (through Claude Code), your ChatGPT plan, an Anthropic API key, an OpenAI or other provider key, or a model on this Mac (Ollama or LM Studio). All five are listed as equals, and the one already working on your Mac is picked. A sentence under the list says where your text goes; continuing agrees to it.
- **Try it.** A practice box, ending with a real take. The hotkey is shown here, with a recorder to change it, and it says if something else uses it.

A closing screen then offers to open Takes when you log in. Languages and starter presets start from your Mac's defaults; change them in Settings (Writing, Presets).

You can close it at any time; it reopens where you left off (menu-bar icon › Finish setting up Takes…). People who used Takes before onboarding existed never see it.

After that, Takes opens a "Set up Takes" window when something it needs is missing: Accessibility access, a working engine (Claude Code installed, 2.1.293 or newer and signed in; an Anthropic API key saved; signed in with ChatGPT; a provider key saved with a model picked; or a local model server running with a model) and a free hotkey. Each Claude Code problem has its own message and one action: Install Claude Code, Update Claude Code (opens Terminal and runs `claude update`), Sign in to Claude or Check again. While something blocks Takes, the menu-bar icon shows a dot and the hotkey opens this window instead of the panel. If you open Takes again from Finder or Spotlight while it's running, its popover offers to finish setup.

Takes keeps watching these only while a setup, onboarding or Settings window is open (Accessibility and hotkeys every second, the model less often), so the window updates as each step is done. Otherwise it checks when you press the hotkey after a problem, when you open the menu-bar menu, at launch and when you change the engine. If your settings name a model this version of Takes doesn't have (saved by a newer version), the hotkey opens Settings › Model so you can pick one, and nothing runs until you do.

## The panel

- **Compose.** The draft starts with the field's text (or the selection). The preset picked for this app is pre-selected. Change the number of takes, the model and the effort for this run only (⌘K). ↵ writes the takes, ⇧↵ adds a line, ⇥ (or / in an empty draft) opens the presets, ⌘1–9 switches preset.
- **What you're replying to.** ⌘J adds the message you're answering (paste or type it), ⇧⌘V uses the clipboard's text. It shows as a chip above the draft and goes to the model as reference only, never rewritten. ⇧⌘⌫ removes it. It's cleared on every summon.
- **Dictation.** ⌘D speaks into the draft at the caret; ⌘D or Esc stops, ↵ stops and writes the takes. Speech is recognised on this Mac only; if the Mac has no on-device model for the language, Takes says so instead of using a server.
- **How it reads.** ⌘T gives one line on how your draft may come across, and at most one thing to try. It goes away when you edit the draft.
- **Presets.** Type to filter, ↑↓ and ↵ to choose. A preview on the right shows the preset's instruction and its Do and Avoid rules.
- **Pressing the hotkey again.** If the panel holds a draft you changed, reply context or takes, pressing the hotkey again from the same text box keeps them instead of starting over. From another app or text box it starts fresh.
- **Takes.** The takes stream in side by side, each with a short note on how it may come across (presets can turn this off). ←→ select a take, ↵ or double-click pastes it, ⌘1–5 pastes directly, ⌘C copies without pasting. Hold ⌥ to see what each take changed against your draft. A take that was cut off before its end shows "Cut short" and can't be pasted; ⌘R writes new ones. The refine box reworks the selected take ("warmer", "drop the second ask"), and "More like take N" writes new takes in its style. ⌘E edits the draft, ⌘R regenerates, Esc goes back.
- **Proofread.** Presets with "Minimal edits" (like the built-in Proofread) fix mistakes only. Their takes open with each fix marked (struck through and underlined, not color alone) and "N fixes", and holding ⌥ hides the marks. Spacing and line-break changes count as fixes too. When there's nothing to fix the panel says "No mistakes found" and ↵ pastes your original.
- **Write and paste right away.** A preset with its own hotkey can skip the panel: the hotkey writes 1 take and pastes it. A note by the text box shows it writing (Esc cancels), then ⌘Z to undo and "Open in Takes" to refine or pick another. If you've switched apps by then, nothing is typed anywhere.
- **English coach.** If you turned it on, "Checking your English…" shows below the takes while it checks an English draft, then a card lists what it found as compact chips. Pick one to see why, or "Not a mistake" to never see that phrase flagged again. Your draft above the takes underlines each flagged phrase. After you paste, the toast can add one nudge when a mistake repeats, with "See why".
- **After pasting.** A toast confirms the paste and that your clipboard is back. If the text box changed meanwhile, or Takes can't get back to the app, it types nothing: the toast says so, and in the panel the take is on the clipboard for you to paste. ⌘Z in the app undoes the paste, and "Save as example" adds the take to the preset's write-like-me examples.

## Settings

Open them from the menu-bar icon, or with ⌘, in the panel. There are six tabs:

- **General:** the hotkey that opens Takes, where the panel opens, what the draft starts with, putting your clipboard back after pasting, an opt-in to use the clipboard as reply context when it looks like a message you just copied, the dictation language, whether Takes opens when you log in and keeps its menu bar icon visible, and which permissions macOS has given Takes.
- **Presets:** Browse presets adds ready-made ones (Proofread, Slack message, Polish email, Shorter, Friendlier, More direct, and more) as your own copies; new installs start with seven. Each preset has a name, color, an optional hotkey of its own, instruction, Do and Avoid lists, up to five write-like-me examples, reply language, the apps where it's picked automatically, the defaults for takes, model, effort and length, and "How it writes": Minimal edits, Show tone, and Write and paste right away. "Try it" runs the preset as edited. Presets can be duplicated, exported and imported as JSON. An imported file adds at most 50 presets and can't switch on a hotkey, app bindings or "Write and paste right away"; Takes lists what it changed or left out.
- **Writing:** rules applied on top of every preset, and the languages you write in. These start as your Mac's languages (System Settings › General › Language & Region); presets can reply in any language, and Browse presets offers a "Translate to …" preset for each of yours.
- **Coach:** the English coach, off by default. Setup picks what it watches (grammar, word choice, natural phrasing, and your own goals such as "less formal in Slack"), your first language, American or British English, when to nudge after paste (off, focus areas only, or any repeat) and which presets count; translation presets start off. Each English draft costs one extra check on your engine's quick model, about 1,000 tokens. The coach screen shows the last 30 days: mistakes per 1,000 words, what you repeat most, short lessons once a pattern shows up 10 times, mute per pattern, token use per month, and "Clear coach data". Turning the coach off deletes everything it kept.
- **Model:** where your takes are written. Claude Code on this Mac (your subscription; its status shows with the one action that fixes what's wrong), an Anthropic API key (stored in the keychain; Takes asks Anthropic whether it works before keeping it), your ChatGPT plan (Sign in with ChatGPT), another provider's API key (OpenAI, Google Gemini, OpenRouter, Groq, Mistral or a custom https server; stored in the keychain), or a local model (Ollama or LM Studio on this Mac; Takes finds them and lists their models, with a Test button). With ChatGPT, a provider or a local model, every preset runs on the one model picked here. Also the defaults for new presets: the number of takes, and model and effort for the Claude engines.
- **History:** the last 30 days of runs, stored only on this Mac, whether to keep them, Clear History…, and the run log (timings only, never your text).

Everything is saved in `~/Library/Application Support/Takes/`. Each run's timing is logged to `~/Library/Logs/Takes/runs.jsonl`. [PRIVACY.md](../PRIVACY.md) lists every file and how to remove it.

## Uninstall

Before you delete it, remove any API keys and sign out of ChatGPT in Settings › Model: they're in your macOS keychain (service "com.baramir.takes"), and deleting the app leaves them there. Then quit Takes from its menu, move it from Applications to the Trash (or `brew uninstall --cask takes`), and delete `~/Library/Application Support/Takes` and `~/Library/Logs/Takes`. You can also remove it from System Settings › Privacy & Security › Accessibility.
