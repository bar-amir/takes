# Privacy

Last updated: 2026-11-02

Takes runs entirely on your Mac. The developer runs no server and never receives your text, your settings or anything about how you use the app. Takes has no analytics, crash reporting or tracking. The only other connection it makes is the optional update check described below.

## What Takes reads

Only when you press the Takes hotkey (or a preset's hotkey), Takes reads:

- **The text box you're typing in:** the selected text, or the text already in the box, depending on your "Start with" setting. It reads this through macOS Accessibility, which you grant in System Settings. Takes only ever reads a real text box, never the page or window around it.
- **The clipboard, briefly:** if an app doesn't expose its text box to Accessibility, Takes copies the text with ⌘A ⌘C and then puts your previous clipboard back. When pasting a take, it puts the take on the clipboard, sends ⌘V, and then restores your clipboard (unless you turn this off).
- **What you're replying to, only if you add it:** in the panel you can add the message you're answering (⌘J to type or paste it, ⇧⌘V to use the clipboard's text). Nothing is added unless you do it, and it's cleared every time the panel opens.
- **The clipboard as context, only if you turn it on** (Settings › Engine › Reply context, off by default): when the panel opens, Takes checks whether the clipboard changed in the last 2 minutes and holds plain text. Only then does it read that text, and it attaches it only if it looks like a message (a few words, under 4,000 characters, not a link, number or code). Passwords marked as private by password managers, files and images are skipped. While this is on, Takes notes when the clipboard changes (not what's on it) so it can tell a fresh copy from an old one. The chip in the panel says "copied just now", and one click or ⇧⌘⌫ removes it.

Takes doesn't read anything in the background, and it doesn't take screenshots. It never reads the screen or other windows for context.

## Where your text goes

When you ask for takes, Takes sends the following **directly from your Mac to Anthropic**, under **your own** Claude account:

- your draft;
- the chosen preset (instruction, Do and Avoid rules, your "write like me" examples);
- your voice rules;
- what you're replying to, if you added it (up to 8,000 characters), marked as reference only.

It goes through one of two routes, whichever you choose:

- **Claude Code on this Mac:** Takes runs the Claude Code you installed and signed in to. Your Claude subscription and Anthropic's terms for it apply.
- **Anthropic API key:** Takes calls Anthropic's API with your key. The key is stored in your macOS keychain, never in Takes' files.

**Tone notes** go the same way. When a preset has "Show tone" on (the default), Takes sends the finished takes once more, in one short request to Claude Haiku, to get a few words on how each may come across. ⌘T in compose sends your current draft the same way, only when you press it. Nothing else is added, and the notes aren't saved. Turn "Show tone" off in a preset and neither request is made.

### Local model: nothing leaves your Mac

If you choose **Local model** in Settings › Engine, Takes sends the same draft, preset and voice rules to a model server running **on your own Mac** (Ollama or LM Studio) instead of to Anthropic, and nothing leaves your Mac:

- Takes only connects to addresses on this Mac (`localhost`, `127.0.0.1`, `::1`). It refuses any other address, ignores system proxies for these requests, and won't follow a redirect to another machine.
- To find a server, Takes asks `localhost:11434` (Ollama) and `localhost:1234` (LM Studio) which models are installed, when you open Settings › Engine or the panel. It never downloads or installs models or apps.
- What the server and model do with your text is up to them. Ollama and LM Studio run models locally, but check their own settings if you've connected them to anything else.

What Anthropic does with that text is covered by [Anthropic's privacy policy](https://www.anthropic.com/legal/privacy) and the terms of your Claude account, not by Takes.

**Don't use Takes on text you're not allowed to share with an AI provider,** for example confidential work material, other people's personal data, or anything your employer's policies forbid sending to third parties.

## Dictation

Dictation is off until you use it. Only while you dictate a draft (⌘D or the mic button in the panel), Takes listens to the microphone and turns your speech into text **on this Mac**, with Apple's on-device speech recognition. The audio is never recorded to a file and never leaves your Mac: not to Anthropic, not to Apple, not to the developer. If your Mac has no on-device speech model for the language, Takes tells you and doesn't dictate; it never falls back to Apple's servers. macOS shows the orange microphone dot in the menu bar whenever the microphone is on.

The words you dictate become part of your draft, and like any draft they're sent to Anthropic only when you ask for takes. The first time you dictate, macOS asks you to allow the microphone and speech recognition for Takes; you can turn either off in System Settings › Privacy & Security.

## What stays on your Mac

| What | Where | How to remove it |
|---|---|---|
| Presets, voice rules, settings | `~/Library/Application Support/Takes/` | Delete the folder |
| History of drafts and takes (last 30 days; never the context you replied to) | `~/Library/Application Support/Takes/history.json` | Settings › History › Clear history, or turn history off in Settings › Engine |
| Run timings (model, timing, the app you were in; no text) | `~/Library/Logs/Takes/runs.jsonl` | Delete the file |
| Field-reading log (app, kind of text box, how it was read, character count; no text) | `~/Library/Logs/Takes/focus.log` | Delete the file |
| API key, if you add one | macOS keychain, item "com.baramir.takes" | Settings › Engine › Remove |

## AI output

Takes shows text written by Claude. It can be wrong or say things you didn't mean. Read a take before you paste or send it, and don't rely on factual statements in it without checking.

### Write and paste right away

A preset can be set to write 1 take and paste it as soon as you press its own hotkey, without showing the panel first. It's off for every preset until you turn it on. It reads and sends exactly what the panel would (the text box, then your draft to your chosen engine), except that it reads the text box even when "Start with" is set to an empty draft, since it has nothing else to write from. Because you don't see the take before it's pasted, read it in the text box before you send it; ⌘Z in that app undoes the paste.

## Update checks

Downloaded copies of Takes can check for new versions with [Sparkle](https://sparkle-project.org). The second time you open Takes, it asks whether to check automatically; you can also use "Check for Updates…" in its menu. A check downloads the update feed (`appcast.xml`) from GitHub's servers at github.com. Like any web request, GitHub sees your IP address. Takes sends no information about you, your Mac or your text with it (Sparkle's "system profile" reporting is off). Updates are only installed if they're signed with the developer's update key and Developer ID. Copies you build yourself never check for updates.

## Changes

If Takes ever starts sending anything anywhere else, this page will say so first and the app will ask you.

## Contact

Questions: open an issue at [github.com/bar-amir/takes](https://github.com/bar-amir/takes/issues).
