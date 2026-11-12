# Developing Takes

How to build Takes, how it works inside, and the tools for checking it. Start with [CONTRIBUTING.md](../CONTRIBUTING.md) for how changes get in, and [architecture.md](architecture.md) for a walk through the code.

## Build and run

Takes is a Swift package (Swift 6, macOS 14+). No Xcode project is needed.

```
./build.sh
open build/Takes.app
```

`swift test` runs the unit tests in `Tests/TakesTests`. `scripts/check.sh` runs everything CI runs: the release build, the tests, and `swift format lint` on the Swift files you changed (style in `.swift-format` and `.editorconfig`). It ends with a count of lint warnings in those files. Style warnings don't fail the check, so fix the ones on lines you changed; `swift format` itself failing does fail it. `scripts/check.sh --all` lints the whole tree.

On first launch macOS asks for Accessibility access (System Settings › Privacy & Security › Accessibility). Takes needs it to read the focused field and to paste. `build.sh` signs ad hoc with a fixed designated requirement, so the permission usually survives rebuilds. To sign with your own certificate instead, set `TAKES_SIGN_IDENTITY` to its name (from `security find-identity -v -p codesigning`) and the permission follows that certificate. If the hotkey works but nothing gets prefilled or pasted, remove Takes from the list and add it again.

Copies you build yourself never check for updates.

## Where things are

| Area | Files in `Sources/Takes/` |
|---|---|
| Hotkey, panel window and placement | `HotKey.swift`, `PanelController.swift`, `Placement.swift` |
| Panel state and screens | `PanelModel.swift`, `PanelViews.swift` |
| Reading the focused field | `FocusReader.swift`, `AXProbe.swift` |
| Pasting and restoring the clipboard | `Paster.swift`, `Toast.swift` |
| Prompts and engines | `Prompt.swift`, `Engine.swift`, `ClaudeCodeEngine.swift`, `APIEngine.swift`, `LocalEngine.swift`, `ProviderEngine.swift`, `ChatGPTEngine.swift`, `ChatGPTAuth.swift` |
| Presets, gallery and options | `Store.swift`, `PresetsTab.swift`, `PresetGallery*.swift`, `PresetOptions.swift` |
| Features | `Proofread.swift`, `Diff.swift`, `InstantMode*.swift`, `ReplyContext*.swift`, `ToneCheck*.swift`, `Dictation*.swift` |
| Setup and onboarding | `Setup.swift`, `Onboarding*.swift`, `SystemShortcuts.swift` |
| Settings | `SettingsWindow.swift` (window, toolbar tabs), `SettingsForm.swift` (grouped form parts), `GeneralTab.swift`, `PresetsTab.swift`, `WritingTab.swift`, `EngineTab.swift` (Model), `HistoryTab.swift`, `LocalEngineViews.swift`, `ProviderEngineViews.swift`, `ChatGPTEngineViews.swift` |
| Screenshots | `Snapshot*.swift` |
| Speed tests | `Bench.swift`, `ToneBench.swift`, `RunLog.swift` |

## Screenshots

`build/Takes.app/Contents/MacOS/Takes --snapshot <folder>` renders every screen with sample data to PNGs. It uses starter presets and default settings, reads and writes none of your Takes files, and runs none of the setup checks (no `claude`, no probe of a model server), so it works in a distributed build too. Include the relevant ones in pull requests that change the UI. The images in `site/img` come from it.

## Translations

The UI is translated into the languages in `Resources/Localizations`, one `<language>.lproj` folder each with `Localizable.strings` and `InfoPlist.strings` (the microphone and speech recognition prompts). `assemble-app.sh` copies them into the app, and macOS picks the language from System Settings › General › Language & Region, including per-app languages.

- Text given to SwiftUI as a literal (`Text("…")`, `Button("…")`, `.help("…")`) is translated already. Any other text shown to people, such as a `String` passed to the app's own components, an error message or a menu item, goes through `String(localized: "…")`. Prompts, logs and anything saved or compared stay as they are.
- After changing UI text, run `scripts/localization.py extract` to update `en.lproj`, then `scripts/localization.py check` to see what each language is missing. `scripts/localization.py missing de` prints the English entries German doesn't have yet. Until a string is translated, the English shows.
- Interpolated Strings become `%@` and Ints `%lld`; add new Int interpolations to `INT_INTERPOLATIONS` in the script. Translations must keep the same specifiers (in any order, as `%1$@`), and `LocalizationTests` fails if they don't.
- A helper of the app's own that takes a `LocalizedStringKey` (like the coach's `tile("…")`) translates at runtime but isn't extracted until it's listed in `LOCAL_KEY_CALLS` in the script.
- A sentence with keycaps in it is one string with `KeysSentence.marker` where the keys go (`"Press \(KeysSentence<EmptyView>.marker) in any text box."`), so each language can put the words around them in its own order.
- The opening screen's key-press loop and the Get started press don't show in a snapshot. To watch them, run `build/Takes.app/Contents/MacOS/Takes --opening-preview`: it shows the opening screen alone, again after each Get started, and quits on Esc. It reads and writes nothing.
- To see a language, run `build/Takes.app/Contents/MacOS/Takes --snapshot <folder> -AppleLanguages '(de)'`. For Arabic, Hebrew, Persian and Urdu add `-AppleTextDirection YES` to get the mirrored right-to-left layout.
- Right to left, SwiftUI mirrors the layout and any `Shape`. Keep left to right what has a direction of its own: the Takes mark (`BrandMarkShape` does this itself), checks, shortcuts (`.environment(\.layoutDirection, .leftToRight)`) and anything placed on a photo. For icons that point "forward" or "back", use the `.forward` and `.backward` SF Symbols, which flip on their own.
- After adding Arabic, Hebrew, Persian or Urdu strings, run `scripts/localization.py rtl`. It starts a sentence that opens with a Latin word or a placeholder ("Takes …") with a right-to-left mark, so its lines and punctuation stay in order, and keeps shortcuts written in a sentence ("⌘Z") left to right. `check` reports strings that need it. A shortcut the code puts into a sentence uses `KeyCombo.inline`.
- The person's own text (a draft, a take, a preset's instruction) and the English coach guide follow their own direction with `.contentDirection(text)`, so English stays left-aligned in a right-to-left interface.

## How it calls the model

With Claude Code: `claude -p` with `--model`, `--effort` and `--output-format stream-json --include-partial-messages`. The preset-built system prompt goes in with `--system-prompt-file`: a file only this user can read (0600, in a 0700 temp folder) that's removed when the run ends, so the prompt never shows in `ps`. The draft goes in on stdin. Takes are separated by `===` lines and appear in the panel as they're written. It runs from an empty temp folder so no CLAUDE.md is picked up. A run is stopped after 2 minutes without any output, or 10 minutes in all. If a whole take was already written it's kept and an unfinished one is marked cut short; otherwise the run fails with a message that says why. See `Sources/Takes/ClaudeCodeEngine.swift`.

With an API key, the Messages API is called directly with streaming (`Sources/Takes/APIEngine.swift`). Saving a key first lists one model with it (`APIEngine.checkKey`, no tokens spent): a key Anthropic refuses isn't kept, and one that couldn't be checked offline is kept and flagged. Setup reuses that answer (`APIKeyCheckCache`), so saving a key makes one request.

With a local model, Takes streams from the server's OpenAI-compatible chat endpoint and only ever connects to `localhost` (`Sources/Takes/LocalEngine.swift`).

With another provider, Takes streams from the provider's OpenAI-compatible chat endpoint over https with the user's key, reusing the local engine's parser (`Sources/Takes/ProviderEngine.swift`).

With a ChatGPT plan, Takes signs the user in with OpenAI's Sign in with ChatGPT (OIDC + PKCE, loopback callback on 127.0.0.1, `Sources/Takes/ChatGPTAuth.swift`) and streams from the Responses API with `store: false` and the system prompt in `instructions` (`Sources/Takes/ChatGPTEngine.swift`). The one-model engines share the hooks at the end of `LocalEngine.swift`.

Tone notes are one extra short request after the takes (Haiku, or the local model).

## How Takes reads text fields

Takes only ever reads a real text box (text area, text field, search or combo box), never the page or document around it. A box's value is trusted even when it's blank: an empty web text box reports a line break, which means empty. Only when a text box has no value at all does Takes try its character range, then its own Chromium text-marker range. Only after those does it copy with ⌘A ⌘C, then put your clipboard back, unless something else was copied in the meantime. Takes always undoes its own ⌘A afterwards, whether or not the copy is used: it puts the selection back, or moves the caret to the end with →. A copy that arrives late (within about a second) is undone too, so the clipboard still comes back.

- **Password fields** (`AXSecureTextField`) are never read, copied from or selected in. The panel says "Takes doesn't read password fields".
- **Long text.** A text box over 10,000 characters is never prefilled. When it reports its text or length through accessibility it is never selected with ⌘A either; one that can't be read that way is copied first (⌘A ⌘C), found too long and discarded, and the selection is undone. The panel says "The text is too long. Select part of it first", and "Write and paste right away" shows a message instead of writing. A selection reported through accessibility has no length limit.
- **An app that stops answering.** Every question to an app has a 0.5 s timeout, and finding the focused box and reading it get 1.5 s each, so a hung app costs a summon about 2 seconds at most. Keys (⌘A ⌘C) go only to an app that's still answering.

### Pasting

Before pasting, Takes puts focus back into the original field. Before any key is sent it asks the app which box has focus, as far as the app answers. Some apps build their text box anew while the panel has the keyboard, so a different text box in the same app also passes if it holds what was read: the same text, the same selection, or nothing for a box that was empty. A password field never does. An app that can't say which box has focus still gets a plain ⌘V at the caret or over a selection; only replacing everything needs proof: the same (or an equivalent) box and, if the text was read through accessibility, that it still holds that text. Text read by ⌘A ⌘C can't be compared, so there a replace-all needs the same box only.

If the app says another box has focus, or (when replacing everything) the text changed, no keys are sent. The panel leaves the take on the clipboard for you to paste, and "Write and paste right away" says nothing was pasted and puts your clipboard back. If the app can't be brought to the front, nothing is typed and the take stays on the clipboard. A paste can also be called off before any key is sent (Esc during "Write and paste right away", or opening the panel again): nothing is typed and your clipboard goes back. After a paste, your clipboard is restored (unless the setting is off), but only if nothing else was copied since. Every paste adds a line to `focus.log`: "paste sent" with which check let it through, or "paste not sent" with why (the app and the reason, never text). The log is capped at about 512 KB; the oldest lines are dropped.

Tools for debugging an app where reading or pasting fails:

- `build/Takes.app/Contents/MacOS/Takes --focus-test` reads the frontmost app's focused box without sending any keys and prints how it was read.
- `open -n build/Takes.app --args --ax-probe 3` waits 3 seconds and writes what the frontmost app reports about its focused element to `~/Library/Logs/Takes/ax-probe.txt` (roles and lengths, never the text; a password field is only named, not read).
- Every summon is logged to `~/Library/Logs/Takes/focus.log` (app, element role, which method worked, how many characters, where the caret was), plus a line for each paste.

## Performance

```
build/Takes.app/Contents/MacOS/Takes --bench --runs 5 --model claude-sonnet-5-5 --effort low
build/Takes.app/Contents/MacOS/Takes --bench --runs 5 --model claude-haiku-5-5 --takes 5
```

Each run prints the time to the first streamed words and the time until all takes are done. `--naive` runs Claude Code with its default setup: tools, MCP servers and user settings all load. Each real run's timing is logged to `~/Library/Logs/Takes/runs.jsonl` (numbers, flags and short names only, capped at about 512 KB).

`--bench` (and `--bench --tone`) is for development builds only, because it spends the signed-in plan or the saved API key on text the caller picks, and any local program can launch the installed app. It works with the output of `./build.sh` (the bare `.build/release/Takes` doesn't start: it can't find Sparkle outside the app bundle). It refuses to run, with a line on stderr and exit code 1, in a build whose own code signature has a team identifier: the Developer ID release, or a `./build.sh` build signed with `TAKES_SIGN_IDENTITY` when that certificate carries a team identifier (Apple Development and Developer ID do; a self-signed one doesn't, so `--bench` still runs there). To bench from a checkout that signs with such a certificate, run `./build.sh` without `TAKES_SIGN_IDENTITY`. This stops the installed app being used this way; it can't stop a copy someone re-signed ad hoc, which carries no team identifier.

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

Takes needs Claude Code 2.1.293 or newer (`claude update`) for all three models: Opus 5.5 arrived in 2.1.280, Sonnet 5.5 in 2.1.284 and Haiku 5.5, which tone notes use, in 2.1.293. The Opus rows were measured on 2.1.310.

## Releasing

See [releasing.md](releasing.md).
