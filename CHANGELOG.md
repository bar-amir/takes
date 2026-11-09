# Changelog

All notable changes to Takes. Versions follow [semantic versioning](https://semver.org).

## 0.9.1 · 2026-11-09

- **Windows open where you are.** With more than one display, Settings, About, Setup and onboarding used to open on the built-in display. They now open on the display you clicked on. When the hotkey opens setup, it opens on the display you're typing on. The panel still opens next to the text box you're in.

## 0.9.0 · 2026-11-09

- **Report a crash in two clicks.** If Takes quits unexpectedly, the next launch offers to open a bug report on GitHub with the versions and where it stopped already filled in, and shows the full crash report in Finder so you can attach it. Nothing is sent until you submit the report yourself. Crash reports hold Takes's code, not your text. Choose "Don't ask again" to turn the offer off.
- **Report a Problem…** in the menu includes the latest crash, if there is one.

## 0.8.1 · 2026-11-09

- Fixed a crash when takes start to appear. It happened on many runs in 0.8.0, as soon as the first take began streaming in.

## 0.8.0 · 2026-11-08

- **A new hotkey: ⌥⇧Space.** The old ⌃⌥Space is a stock macOS shortcut (it switches input sources), so on most Macs Takes couldn't register it and new installs ended setup with a hotkey that did nothing. ⌥⇧Space is free on a stock Mac and isn't used by Raycast, Alfred, 1Password, Rectangle or Magnet. Existing installs keep the hotkey they have.
- **A free hotkey, every time.** A new install starts on the first hotkey its Mac leaves free. When a hotkey is taken, setup, Settings › General and the preset editor say who has it (macOS, an installed app such as Raycast or 1Password, or another preset) and offer free ones to pick with one click.
- **Open Takes at login.** A checkbox on the last setup step and a switch in Settings › General, off until you turn it on.
- **Moving from the disk image.** Opened from the disk image or a download folder, Takes offers to move itself to Applications first, so the access you allow, the login item and updates all stick.
- Setup opens right away instead of waiting for the engine check, and a Claude Code that doesn't answer no longer leaves a first launch with no window.
- Claude Code is found through your own shell (fish and bash too), so nvm and Volta installs work. A Claude Code older than 2.1.41 is reported as too old, with the command to update it.
- The setup window no longer floats over System Settings, Terminal and the browser it sends you to.
- Signed in with ChatGPT but no model listed yet: the button says Check again instead of starting another sign-in.
- Recording a shortcut that Takes already uses records it instead of opening the panel.
- The film on takes.rocks shows the new hotkey, with a tighter ending.

## 0.7.0 · 2026-11-08

- **Takes speaks your language.** The interface is translated into 46 languages besides English, and follows your Mac's language. Hebrew, Arabic and Persian are laid out right to left, with shortcuts still reading left to right. Preset names and instructions stay as you wrote them.
- **Install Claude Code from Takes.** When Claude Code isn't on your Mac, setup, Settings › Model and the Setup window offer "Install Claude Code". After you confirm, Takes runs Anthropic's official installer in the background and shows its progress. Takes doesn't ship or change Claude Code; it's downloaded from Anthropic each time.
- **Sign in to Claude without typing.** Every "Sign in to Claude" button opens Terminal already running Claude Code's own sign-in, which sends you to the browser. Signing in right after installing used to fail with "command not found".
- Takes notices Claude Code as soon as it's installed during setup.
- Cancelling a run (Esc, asking again or starting a new one) stops Claude Code, so it no longer keeps using your plan. A run that takes more than 2 minutes stops with a plain message.
- "Write and paste right away" checks that the text box it read still has focus and still holds your draft, so it never pastes over a different conversation.
- **Report a Problem…** in the menu opens a GitHub bug report with the Takes version, macOS version and engine type filled in, and nothing else.
- Fixed a misspelled word on the onboarding opening image.

## 0.6.1 · 2026-11-05

- **A new About window.** The marbled takes logo loops on its own (a still frame with Reduce Motion), above the version and copyright. The open-source notices still ship inside the app.
- "Finish setting up Takes…" leaves the menu once setup is done. If something stops working later, the menu bar icon shows its dot and the hotkey opens setup.
- Settings grows and shrinks around its centre when you switch tabs, and the Coach tab has the same background as the others.
- Update notes in the updater show bold text and links instead of Markdown symbols.
- In the preset picker (Tab), moving with the arrow keys scrolls the list to keep the highlighted preset in view.

## 0.6.0 · 2026-11-05

- **A new first run.** Takes opens on a full-window photo, then five steps: Allow access, Connect a model (it starts on what already works on your Mac and names exactly where your text goes), Make it yours, Try it, Done.
- **Never lose Takes.** When setup ends, a popover points at the menu bar icon. Opening Takes again from Finder, Spotlight or Launchpad shows the same popover. The menu is shorter, shows the hotkey like a real shortcut, runs presets directly and shows whether the English coach is on and which model you use.
- **A calmer panel.** Presets and run options share one row; the run options are one chip (⌘K). Take cards drop their footers (hold ⌥ to see changes), and the coach note is one line until you open it (⌘;).
- **The English coach offers itself.** When your takes keep fixing the same kind of English mistake and the coach is off, a short note under the takes shows your own fixes and offers to turn it on. At most once a week, and "Don't ask again" means never. Setup is three short steps with sensible defaults.
- **Settings, reorganised.** Six tabs in a smaller native window: General, Presets, Writing, Coach, Model and History.
- Short, consistent motion everywhere (all of it follows Reduce Motion), and labels set in JetBrains Mono, like the website.
- **Signed out of Claude?** Any Claude Code sign-in failure now says so plainly, explains that this sign-in is separate from the Claude app, and offers a "Sign in to Claude" button that opens the sign-in for you.
- **Out of credit or at a limit.** When your engine runs out of credit or hits its usage limit, Takes says so plainly and links to the page that fixes it.
- **Safer updates.** The update feed itself is now signed and checked, and each update is verified before it's opened. Sparkle 2.10.1.
- **Privacy and security fixes.** Takes put back on the clipboard are hidden from clipboard-history apps; an imported preset never arrives with "Write and paste right away" turned on; ChatGPT sign-in can't be ended by a stray web page; the Claude Code engine receives your text on standard input, never as a command-line option; debug options no longer print any of your text.
- About lists the open-source notices that ship with Takes.

## 0.5.1 · 2026-11-04

- The English coach sits below the takes in its own card. Fixes are compact chips; pick one to see why, or mark it "Not a mistake" to never see that phrase flagged again.
- "Checking your English…" shows while the coach is working.
- Your draft is easier to read above the takes, with each phrase the coach flagged underlined.
- Reasons are worded for your sentence ("a future condition takes the present after if") instead of rules that sound absolute, and keep their quote marks.

## 0.5.0 · 2026-11-03

- **English coach.** Off by default; turn it on in Settings › English coach. When a draft is in English, a short check runs next to your takes on the quick model of whichever engine you use (about 1,000 tokens, roughly 40% on top of a run) and points out repeated mistakes: grammar such as conditionals, tenses, articles and prepositions, and word choice such as collocations, false friends and phrasal verbs. A built-in guide of 22 patterns, with notes for Hebrew speakers, keeps the check small and its explanations consistent.
- **Learn from your own drafts.** Pick focus areas and your own goals ("less formal in Slack"). Fixes appear under your draft in the panel; after you paste, a short note with "See why" says when a mistake is a repeat (Nudges: off, focus areas only, or any repeat). The last 30 days show what you repeat most and whether it's going down, and after 10 sightings of a pattern there's a short lesson built from your own sentences, made on this Mac at no token cost.
- Choose which presets count (translations into another language start off), American or British English, "Not a mistake" and mute per pattern. Coach data stays on this Mac for 30 days and can be cleared at any time.

## 0.4.0 · 2026-11-02

- **Your ChatGPT plan.** Sign in with ChatGPT in the browser and write with the models in your Plus or Pro plan, at no extra cost. Tokens stay in your keychain; requests come from this Mac, for you, for Takes only. "Manage usage" opens your ChatGPT settings, also when the week's allowance runs out.
- **Other provider.** Your own API key for OpenAI, Google Gemini, OpenRouter, Groq, Mistral, or any https server that speaks the OpenAI API. Keys stay in your keychain; the Engine tab lists the provider's models and tests the key.
- **Privacy notice.** One section per engine, and a new section on how Takes follows Anthropic's and OpenAI's rules. Setup, onboarding, the Engine tab, the README and the website name whichever engine you picked. The disabled "Sign in with Claude" card is gone: Anthropic doesn't allow it for third-party apps.
- With a ChatGPT plan, a provider or a local model, every preset runs on the one model picked in Settings › Engine, and the panel says which model and where ("gpt-5.4 via OpenAI", "GPT-5.4 with your ChatGPT plan").
- The onboarding engine step scrolls now that it has five options.

## 0.3.0 · 2026-11-02

- **Onboarding.** A guided first run: Accessibility, connecting Claude (or a local model), privacy, hotkey, starter presets, and a practice box that ends with a real take. Existing users don't see it. The setup window shares its look.
- **Write and paste right away.** A preset's own hotkey can write 1 take and paste it with no panel, with a note to cancel, undo or open it in Takes. Nothing is typed if you've switched apps.
- **Proofread.** A built-in Proofread preset and a "Minimal edits" option for any preset. Fixes are marked inline with a count, and "No mistakes found" replaces an identical take. The word diff handles punctuation and case better and reads each change to VoiceOver.
- **Preset gallery.** 12 ready-made presets to add from Settings › Presets, the new-preset state and the panel's preset list. New installs start with 7; existing presets are never touched.
- **Reply context.** ⌘J or ⇧⌘V adds what you're replying to, as reference only. Optional: use a message you just copied automatically (off by default).
- **Tone.** A short note on how each take may come across, and ⌘T for your draft. Per preset, on by default (off for Proofread).
- **Dictation.** ⌘D speaks a draft, recognised on this Mac only.
- **Local models.** A third engine: Ollama or LM Studio on this Mac, localhost only.
- **Your languages.** Takes starts from your Mac's languages instead of a fixed English/Hebrew choice. Presets can reply in any language, the gallery has a "Translate to …" preset for each of yours, and you can change the list in onboarding and Settings › Voice. Existing presets keep their language.
- Preset options (Minimal edits, Show tone, Write and paste right away) sit together in one "How it writes" card.
- Release builds can use the microphone (hardened-runtime entitlement), for dictation.

## 0.2.0 · 2026-11-02

- A new look from the Takes brand book: Ink and Paper accents throughout, and the compact t (a speech bubble whose t flows into its tail) in the menu bar and the panel header.
- A new app icon: the holographic t, with a matching disk icon and a branded install window when you open the .dmg.
- The panel header shows the icon of the app you're writing in, and preset app chips and the app menu show app icons too.
- The panel is evenly spaced: one spacing scale on every screen, and the takes window fits its cards instead of leaving a gap under them.
- The panel opens beside the text box you're writing in, never over it. Settings › Engine › Open the panel lets you pick a spot instead (next to the text box, a screen corner, top or bottom center, or the center); if that spot would cover the text box, the panel moves to the nearest clear spot.
- Setup now flags a Takes hotkey that macOS also uses (for example ⌃⌥Space for "Show Finder search window" or for switching input sources). Both used to fire: Finder opened, took the focus and pulled full-screen apps off their Space.
- The chosen take is pasted only once the app you were writing in is back in front. If Takes can't get back to it, nothing is typed anywhere else; the take stays on the clipboard and the toast says to press ⌘V.
- The first summon in Electron apps (Claude, Slack) now reads the field's text without you selecting it first.
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
