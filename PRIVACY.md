# Privacy

Last updated: 2026-10-26

Takes runs entirely on your Mac. The developer runs no server and never receives your text, your settings or anything about how you use the app. Takes has no analytics, crash reporting or tracking.

## What Takes reads

Only when you press the Takes hotkey (or a preset's hotkey), Takes reads:

- **The text box you're typing in:** the selected text, or the text already in the box, depending on your "Start with" setting. It reads this through macOS Accessibility, which you grant in System Settings. Takes only ever reads a real text box, never the page or window around it.
- **The clipboard, briefly:** if an app doesn't expose its text box to Accessibility, Takes copies the text with ⌘A ⌘C and then puts your previous clipboard back. When pasting a take, it puts the take on the clipboard, sends ⌘V, and then restores your clipboard (unless you turn this off).

Takes doesn't read anything in the background, and it doesn't take screenshots.

## Where your text goes

When you ask for takes, Takes sends the following **directly from your Mac to Anthropic**, under **your own** Claude account:

- your draft;
- the chosen preset (instruction, Do and Avoid rules, your "write like me" examples);
- your voice rules.

It goes through one of two routes, whichever you choose:

- **Claude Code on this Mac:** Takes runs the Claude Code you installed and signed in to. Your Claude subscription and Anthropic's terms for it apply.
- **Anthropic API key:** Takes calls Anthropic's API with your key. The key is stored in your macOS keychain, never in Takes' files.

What Anthropic does with that text is covered by [Anthropic's privacy policy](https://www.anthropic.com/legal/privacy) and the terms of your Claude account, not by Takes.

**Don't use Takes on text you're not allowed to share with an AI provider,** for example confidential work material, other people's personal data, or anything your employer's policies forbid sending to third parties.

## What stays on your Mac

| What | Where | How to remove it |
|---|---|---|
| Presets, voice rules, settings | `~/Library/Application Support/Takes/` | Delete the folder |
| History of drafts and takes (last 30 days) | `~/Library/Application Support/Takes/history.json` | Settings › History › Clear history, or turn history off in Settings › Engine |
| Run timings (model, timing, the app you were in; no text) | `~/Library/Logs/Takes/runs.jsonl` | Delete the file |
| Field-reading log (app, kind of text box, how it was read, character count; no text) | `~/Library/Logs/Takes/focus.log` | Delete the file |
| API key, if you add one | macOS keychain, item "com.baramir.takes" | Settings › Engine › Remove |

## AI output

Takes shows text written by Claude. It can be wrong or say things you didn't mean. Read a take before you paste or send it, and don't rely on factual statements in it without checking.

## Changes

If Takes ever starts sending anything anywhere else (for example, checking for updates), this page will say so first and the app will ask you.

## Contact

Questions: open an issue at [github.com/bar-amir/takes](https://github.com/bar-amir/takes/issues).
