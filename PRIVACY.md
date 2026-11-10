# Privacy

Last updated: 2026-11-10

Takes runs entirely on your Mac. The developer runs no server and never receives your text, your settings or anything about how you use the app. Takes has no analytics, automatic crash reporting or tracking. Apart from the engine you choose, the only connection it makes is the optional update check described below. If Takes crashes, it can help you report it yourself (see [Crash reports](#crash-reports)).

## What Takes reads

Only when you press the Takes hotkey (or a preset's hotkey), Takes reads:

- **The text box you're typing in:** the selected text, or the text already in the box, depending on your "Start with" setting. It reads this through macOS Accessibility, which you grant in System Settings. Takes only ever reads a real text box, never the page or window around it.
- **The clipboard, briefly:** if an app doesn't expose its text box to Accessibility, Takes copies the text with ⌘A ⌘C and then puts your previous clipboard back. When pasting a take, it puts the take on the clipboard, sends ⌘V, and then restores your clipboard (unless you turn this off). Your old clipboard goes back only if nothing else was copied in the meantime; anything you copy then stays. Before it sends keys, Takes checks that the text box you read from still has focus (or that, in the same app, another text box holds the same text), and, when it replaces all your text, that the text hasn't changed. If the app says otherwise, Takes sends no keys.
- **What you're replying to, only if you add it:** in the panel you can add the message you're answering (⌘J to type or paste it, ⇧⌘V to use the clipboard's text). Nothing is added unless you do it, and it's cleared every time the panel opens.
- **The clipboard as context, only if you turn it on** (Settings › General › Clipboard › "Use the clipboard as context when it looks like a message", off by default): when the panel opens, Takes checks whether the clipboard changed in the last 2 minutes and holds plain text. Only then does it read that text, and it attaches it only if it looks like a message (a few words, under 4,000 characters, not a link, number or code). Passwords marked as private by password managers, files and images are skipped. While this is on, Takes notes when the clipboard changes (not what's on it) so it can tell a fresh copy from an old one. A take Takes pastes, or an old clipboard it puts back, doesn't count as a fresh copy. The chip in the panel says "copied just now", and one click or ⇧⌘⌫ removes it.

Takes doesn't read anything in the background, and it doesn't take screenshots. It never reads the screen or other windows for context.

## Where your text goes

Takes sends your text only when you ask for takes, and only to the engine you chose in Settings › Model. Whichever engine you use, it sends:

- your draft;
- the chosen preset (instruction, Do and Avoid rules, your "write like me" examples);
- your voice rules;
- what you're replying to, if you added it (up to 8,000 characters), marked as reference only.

It goes **straight from your Mac** to that engine. Nothing goes through a server of ours, because there isn't one. Here is where it goes for each engine.

### Claude Code on this Mac

- **To whom:** Anthropic, under **your own** Claude account.
- **How:** Takes runs the Claude Code you installed and signed in to, unmodified. You sign in through Anthropic's own flow; Takes never sees your Claude credentials.
- **Installing:** if Claude Code isn't on your Mac and you press Install Claude Code, Takes runs Anthropic's official installer (`curl --proto '=https' --tlsv1.2 -fsSL https://claude.ai/install.sh | bash`), which downloads Claude Code from Anthropic. Nothing about you is sent. Sign-in then happens in Terminal, in Claude Code itself.
- **Updating:** if your Claude Code is too old for Takes and you press Update Claude Code, Takes opens Terminal and runs `claude update`, Claude Code's own updater.
- **Terms:** your Claude subscription and Anthropic's terms for it.
- **Stored:** nothing new. Claude Code keeps its own sign-in; Takes doesn't read or copy it.
- **Data use:** [Anthropic's privacy policy](https://www.anthropic.com/legal/privacy).

### Anthropic API key

- **To whom:** Anthropic's API, under **your own** API account.
- **Terms:** [Anthropic's Commercial Terms](https://www.anthropic.com/legal/commercial-terms). Billed to you by Anthropic.
- **Also sent:** when you save the key, Takes asks Anthropic whether it works, in one request that lists a model. It spends no tokens and carries no text. A key Anthropic refuses isn't kept; if you're offline, the key is kept and Takes says it wasn't checked. Takes asks the same way when it checks that setup works with this engine, but keeps the answer in memory while it runs, so a key you just saved is asked about once. If Anthropic couldn't be reached, it asks again after 5 minutes.
- **Stored:** the key, in your macOS keychain, never in Takes' files.
- **Data use:** [Anthropic's privacy policy](https://www.anthropic.com/legal/privacy).

### Your ChatGPT plan

- **To whom:** OpenAI's API, under **your own** ChatGPT plan, through OpenAI's Sign in with ChatGPT.
- **How:** you sign in in your browser, on OpenAI's pages. Takes never asks for your ChatGPT password. Requests are sent from your Mac with `store: false`, so OpenAI doesn't save the response for later use in its API.
- **Terms:** your ChatGPT plan's terms and its usage limits. You can see and cap what Takes uses, or revoke it, in ChatGPT › Settings.
- **Stored:** the sign-in tokens, in your macOS keychain only. Signing out deletes them and asks OpenAI to revoke them.
- **Data use:** [OpenAI's privacy policy](https://openai.com/policies/privacy-policy/).

Plus and Pro plans can use it. OpenAI calls Sign in with ChatGPT a preview, so its limits and rules may change.

### Other provider

- **To whom:** the provider you picked (OpenAI, Google Gemini, OpenRouter, Groq or Mistral) or a custom address you typed, under **your own** account with them. Takes only connects over https.
- **Terms:** that provider's terms. Billed to you by the provider.
- **Also sent:** when setup, Settings › Model or the panel needs the provider's list of models, Takes asks for it with your key. No text is sent. In setup, it asks only after you've agreed to where your text goes. The answer is kept for up to 10 minutes unless you press Check again.
- **Stored:** the key, in your macOS keychain, one item per provider, never in Takes' files or logs.
- **Data use:** [OpenAI](https://openai.com/policies/privacy-policy/), [Google Gemini API](https://ai.google.dev/gemini-api/terms), [OpenRouter](https://openrouter.ai/privacy), [Groq](https://groq.com/privacy-policy/), [Mistral](https://mistral.ai/terms/).

With a **custom address**, your drafts go to whatever server is at that address. Takes can't tell who runs it or what it does with your text, so only use a server you trust. That choice is yours.

### Local model: nothing leaves your Mac

If you choose **Local model**, Takes sends the same draft, preset and voice rules to a model server running **on your own Mac** (Ollama or LM Studio), and nothing leaves your Mac:

- Takes only connects to addresses on this Mac (`localhost`, `127.0.0.1`, `::1`). It refuses any other address, ignores system proxies for these requests, and won't follow a redirect to another machine.
- To find a server, Takes asks `localhost:11434` (Ollama) and `localhost:1234` (LM Studio) which models are installed, when you open Settings › Model, setup or the panel. It never downloads or installs models or apps.
- What the server and model do with your text is up to them. Ollama and LM Studio run models locally, but check their own settings if you've connected them to anything else.

### Tone notes

**Tone notes** go the same way, to the model your engine uses (Claude Haiku with Claude; your picked model otherwise). When a preset has "Show tone" on (the default), Takes sends the finished takes once more, in one short request, to get a few words on how each may come across. ⌘T in compose sends your current draft the same way, only when you press it. Nothing else is added, and the notes aren't saved. Turn "Show tone" off in a preset and neither request is made.

### English coach

The English coach is **off until you turn it on** in Settings › Coach. While it's on, each draft you send for takes that is mostly English (and from a preset you chose to count) goes once more, in one short request, to your engine's quick model, alongside the takes. That request carries only the draft and the list of patterns you chose to watch; it never includes what you're replying to. The answer is checked against the draft on your Mac, and lessons are put together on your Mac from a built-in guide, so they send nothing.

When you paste a take, Takes keeps on your Mac, in `coach.json`: a short excerpt of each mistake and its correction (cut to about 100 characters each), the reason (about 140), the app you were in, the date and the draft's word count. Takes never saves your whole draft here. Entries older than 30 days are deleted, phrases you mark "Not a mistake" are kept so they aren't flagged again, and monthly token estimates are kept for a year. Turning the coach off deletes `coach.json`.

While the coach is off, Takes still compares each English draft with its takes on your Mac, with no model and no network, to see whether the same kind of fix keeps coming up. If it does, a strip can offer the coach, at most once a week. For that, `coach-invite.json` keeps only which kinds of fix were seen (such as articles or prepositions) and when, for 30 days, plus your answer to the offer. It never holds text.

What a provider does with your text is covered by its own privacy policy and the terms of your account with it, not by Takes.

**Don't use Takes on text you're not allowed to share with an AI provider,** for example confidential work material, other people's personal data, or anything your employer's policies forbid sending to third parties.

### How Takes follows the providers' rules

**Anthropic.** With Claude Code, Takes runs the unmodified Claude Code you installed, and you sign in to it through Anthropic's own flow. Takes never sees, stores or forwards your Claude credentials or session tokens. Every request is yours, billed to your own plan or key, and nobody else's requests ever use your account. With an API key, the key is yours, it stays in your keychain, and Anthropic bills you for it. See [Anthropic's Claude Code legal and compliance page](https://code.claude.com/docs/en/legal-and-compliance).

**OpenAI.** With Sign in with ChatGPT, Takes is an open-source app that runs on your Mac. You sign in in your browser, on OpenAI's pages, and Takes never asks for your ChatGPT password. The tokens are stored only in your macOS keychain. Requests come from your Mac, for you, for Takes only. Takes never pools, shares or resells plan usage, and never charges for this. You can see and cap Takes' usage, and revoke it, in ChatGPT › Settings. With an OpenAI API key, the key is yours, it stays in your keychain, and OpenAI bills you for it. See [OpenAI's Sign in with ChatGPT terms](https://openai.com/policies/sign-in-with-chatgpt-terms/) and [ChatGPT plan usage for open-source apps](https://developers.openai.com/siwc/token-sharing-open-source).

## Dictation

Dictation is off until you use it. Only while you dictate a draft (⌘D or the mic button in the panel), Takes listens to the microphone and turns your speech into text **on this Mac**, with Apple's on-device speech recognition. The audio is never recorded to a file and never leaves your Mac: not to your engine, not to Apple, not to the developer. If your Mac has no on-device speech model for the language, Takes tells you and doesn't dictate; it never falls back to Apple's servers. macOS shows the orange microphone dot in the menu bar whenever the microphone is on.

The words you dictate become part of your draft, and like any draft they're sent to your engine only when you ask for takes. The first time you dictate, macOS asks you to allow the microphone and speech recognition for Takes; you can turn either off in System Settings › Privacy & Security.

## What stays on your Mac

| What | Where | How to remove it |
|---|---|---|
| Presets (instructions, Do and Avoid rules, examples, hotkeys, apps) | `~/Library/Application Support/Takes/presets.json` | Delete the file |
| Settings, including your voice rules (never keys or tokens) | `~/Library/Application Support/Takes/settings.json` | Delete the file |
| History of drafts and takes (last 30 days; never the context you replied to) | `~/Library/Application Support/Takes/history.json` | Settings › History › Clear History…, or turn history off in Settings › History |
| English coach notes, if you turn it on (short excerpts of mistakes, never whole drafts; 30 days) | `~/Library/Application Support/Takes/coach.json` | Settings › Coach › Clear coach data…, or turn the coach off |
| Which kinds of fix showed up in your English drafts while the coach is off, and when (30 days; no text), and your answer to the coach offer | `~/Library/Application Support/Takes/coach-invite.json` | Delete the file |
| A random ID for this Mac that OpenAI asks for when you sign in with ChatGPT (not tied to you) | `~/Library/Application Support/Takes/chatgpt-host.json` | Settings › Model › Sign out removes it |
| A copy of a file Takes couldn't read, kept so nothing is lost: `presets.unreadable-<date>.json`, `settings.unreadable-<date>.json`, `history.unreadable-<date>.json`, `coach.unreadable-<date>.json` (at most 3 per file) | `~/Library/Application Support/Takes/` | Delete the copy. Takes tells you at launch when it has set a file aside. The history and coach copies hold the same text as the originals: they expire 30 days after the original was last written, and Clear History and Clear coach data delete them too |
| Run timings (model, effort, engine, number of takes, timing, the app you were in; no text). Capped at about 512 KB: the oldest lines are dropped | `~/Library/Logs/Takes/runs.jsonl` | Delete the file |
| Field-reading log (app, kind of text box, how it was read, character count, caret position; a line for each paste, sent or not, with which check let it through or why it wasn't sent; no text). Capped at about 512 KB: the oldest lines are dropped | `~/Library/Logs/Takes/focus.log` | Delete the file |
| Probe of one app's text box, only if a developer runs Takes with `--ax-probe` (roles and lengths only, no text; a password field isn't read at all) | `~/Library/Logs/Takes/ax-probe.txt` | Delete the file |
| API keys and ChatGPT sign-in tokens, if you add them | macOS keychain, service "com.baramir.takes" | Settings › Model › Remove Key… or Sign out |

If Takes can't read `settings.json`, it starts with history off.

While Claude Code writes takes, its instructions (the preset and your voice rules, not your draft) are in a file in your Mac's temporary folder that only you can read. Takes deletes it when the run ends.

## AI output

Takes shows text written by the model your engine uses (Claude, unless you picked another). It can be wrong or say things you didn't mean, and it's only as good as the preset's instructions, examples and the model you pick. Read a take before you paste or send it, and don't rely on factual statements in it without checking. What you send is up to you.

### Write and paste right away

A preset can be set to write 1 take and paste it as soon as you press its own hotkey, without showing the panel first. It's off for every preset until you turn it on. It reads and sends exactly what the panel would (the text box, then your draft to your chosen engine), except that it reads the text box even when "Start with" is set to an empty draft, since it has nothing else to write from. Because you don't see the take before it's pasted, read it in the text box before you send it; ⌘Z in that app undoes the paste.

## Cost

Takes itself is free. Runs through Claude Code count toward your Claude plan's usage limits, and runs with your ChatGPT plan toward that plan's limits (OpenAI lets you cap Takes' share in ChatGPT › Settings › Usage). Runs with an API key, Anthropic's or another provider's, are billed to your account with that provider by the tokens they use, and Takes doesn't cap that spending. A local model is free. More takes, bigger models, higher effort, tone notes, refine and regenerate each use more. See [Costs and responsibility](README.md#costs-and-responsibility).

## Update checks

Downloaded copies of Takes can check for new versions with [Sparkle](https://sparkle-project.org). The second time you open Takes, it asks whether to check automatically; you can also use "Check for Updates…" in its menu. A check downloads the update feed (`appcast.xml`) from GitHub's servers at github.com. Like any web request, GitHub sees your IP address. Takes sends no information about you, your Mac or your text with it (Sparkle's "system profile" reporting is off). Updates are only installed if they're signed with the developer's update key and Developer ID. Copies you build yourself never check for updates.

## Crash reports

When an app crashes, macOS saves a crash report on your Mac, in `~/Library/Logs/DiagnosticReports`. Apple doesn't pass these on to developers of apps outside the App Store, so the developer of Takes never gets them on their own.

The next time you open Takes after a crash, it reads its own crash report there and asks whether you want to report it. Report… opens a new bug report on GitHub in your browser, filled in with a short summary: the Takes and macOS versions, the kind of crash and where in Takes's code it stopped. The link is never longer than 8,000 characters, so a long summary is cut and says so. Takes also shows the full report in Finder so you can attach it. Crash reports hold the app's code and the state of your Mac when it crashed (such as its model and memory), not your text. Nothing is sent unless you submit the bug report on GitHub, where it's public. Takes asks once per crash, only about crashes in the version you're running from the last two weeks, and "Don't ask again" stops it asking. "Report a Problem…" in the menu adds the latest crash the same way.

## The website

This notice is about the app. The Takes website (the landing page on GitHub Pages) counts visits with [GoatCounter](https://www.goatcounter.com). GoatCounter sets no cookies and doesn't store IP addresses. It records the page, the site you came from, your country (worked out from your IP address, which isn't kept), language, screen width, browser and operating system, and clicks on the download, film and Support Takes buttons. The film on the site is served from the site itself too. The app never loads it. The site's fonts and images are served from the site itself, not from Google Fonts. The one other file it loads from outside is the three.js library for the live 3D product picture, from the jsDelivr network, which sees your IP address as any web host does. The developer also keeps GitHub's own counts of release downloads, update-feed downloads and repository visits, which say nothing about who you are.

## Changes

If Takes ever starts sending anything anywhere else, this page will say so first and the app will ask you.

## Who's responsible

Takes and its website are made by Bar Amir, an individual developer, who is responsible for this notice. For the website's visit counts, that makes Bar Amir the controller under data protection laws such as the GDPR.

## Contact

Questions, or a request about your data: email [baramir93@gmail.com](mailto:baramir93@gmail.com). For anything that doesn't need to be private, you can also open an issue at [github.com/bar-amir/takes](https://github.com/bar-amir/takes/issues).
