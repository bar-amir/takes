# Developing Takes

How to build Takes, how it works inside, and the tools for checking it. Start with [CONTRIBUTING.md](../CONTRIBUTING.md) for how changes get in, and [architecture.md](architecture.md) for a walk through the code.

## Build and run

Takes is a Swift package (Swift 6, macOS 14+). No Xcode project is needed.

```
./build.sh
open build/Takes.app
```

`swift test` runs the unit tests in `Tests/TakesTests`. `scripts/check.sh` runs everything CI runs: the release build, the tests, and `swift format lint` on the Swift files you changed (style in `.swift-format` and `.editorconfig`).

On first launch macOS asks for Accessibility access (System Settings › Privacy & Security › Accessibility). Takes needs it to read the focused field and to paste. `build.sh` signs ad hoc with a fixed designated requirement, so the permission usually survives rebuilds. If the hotkey works but nothing gets prefilled or pasted, remove Takes from the list and add it again.

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

`build/Takes.app/Contents/MacOS/Takes --snapshot <folder>` renders every screen with sample data to PNGs. Include the relevant ones in pull requests that change the UI. The images in `site/img` come from it.

## Translations

The UI is translated into the languages in `Resources/Localizations`, one `<language>.lproj` folder each with `Localizable.strings` and `InfoPlist.strings` (the microphone and speech recognition prompts). `assemble-app.sh` copies them into the app, and macOS picks the language from System Settings › General › Language & Region, including per-app languages.

- Text given to SwiftUI as a literal (`Text("…")`, `Button("…")`, `.help("…")`) is translated already. Any other text shown to people, such as a `String` passed to the app's own components, an error message or a menu item, goes through `String(localized: "…")`. Prompts, logs and anything saved or compared stay as they are.
- After changing UI text, run `scripts/localization.py extract` to update `en.lproj`, then `scripts/localization.py check` to see what each language is missing. `scripts/localization.py missing de` prints the English entries German doesn't have yet. Until a string is translated, the English shows.
- Interpolated Strings become `%@` and Ints `%lld`; add new Int interpolations to `INT_INTERPOLATIONS` in the script. Translations must keep the same specifiers (in any order, as `%1$@`), and `LocalizationTests` fails if they don't.
- A helper of the app's own that takes a `LocalizedStringKey` (like the coach's `tile("…")`) translates at runtime but isn't extracted until it's listed in `LOCAL_KEY_CALLS` in the script.
- A sentence with keycaps in it is one string with `KeysSentence.marker` where the keys go (`"Press \(KeysSentence<EmptyView>.marker) in any text box."`), so each language can put the words around them in its own order.
- To see a language, run `build/Takes.app/Contents/MacOS/Takes --snapshot <folder> -AppleLanguages '(de)'`. For Arabic, Hebrew, Persian and Urdu add `-AppleTextDirection YES` to get the mirrored right-to-left layout.
- Right to left, SwiftUI mirrors the layout and any `Shape`. Keep left to right what has a direction of its own: the Takes mark (`BrandMarkShape` does this itself), checks, shortcuts (`.environment(\.layoutDirection, .leftToRight)`) and anything placed on a photo. For icons that point "forward" or "back", use the `.forward` and `.backward` SF Symbols, which flip on their own.
- After adding Arabic, Hebrew, Persian or Urdu strings, run `scripts/localization.py rtl`. It starts a sentence that opens with a Latin word or a placeholder ("Takes …") with a right-to-left mark, so its lines and punctuation stay in order, and keeps shortcuts written in a sentence ("⌘Z") left to right. `check` reports strings that need it. A shortcut the code puts into a sentence uses `KeyCombo.inline`.
- The person's own text (a draft, a take, a preset's instruction) and the English coach guide follow their own direction with `.contentDirection(text)`, so English stays left-aligned in a right-to-left interface.

## How it calls the model

With Claude Code: `claude -p` with a preset-built system prompt, `--model`, `--effort` and `--output-format stream-json --include-partial-messages`. Takes are separated by `===` lines and appear in the panel as they're written. It runs from an empty temp folder so no CLAUDE.md is picked up. See `Sources/Takes/ClaudeCodeEngine.swift`.

With an API key, the Messages API is called directly with streaming (`Sources/Takes/APIEngine.swift`).

With a local model, Takes streams from the server's OpenAI-compatible chat endpoint and only ever connects to `localhost` (`Sources/Takes/LocalEngine.swift`).

With another provider, Takes streams from the provider's OpenAI-compatible chat endpoint over https with the user's key, reusing the local engine's parser (`Sources/Takes/ProviderEngine.swift`).

With a ChatGPT plan, Takes signs the user in with OpenAI's Sign in with ChatGPT (OIDC + PKCE, loopback callback on 127.0.0.1, `Sources/Takes/ChatGPTAuth.swift`) and streams from the Responses API with `store: false` and the system prompt in `instructions` (`Sources/Takes/ChatGPTEngine.swift`). The one-model engines share the hooks at the end of `LocalEngine.swift`.

Tone notes are one extra short request after the takes (Haiku, or the local model).

## How Takes reads text fields

Takes only ever reads a real text box (text area, text field, search or combo box), never the page or document around it. A box's value is trusted even when it's blank: an empty web text box reports a line break, which means empty. Only when a text box has no value at all does Takes try its character range, then its own Chromium text-marker range. Only after those does it copy with ⌘A ⌘C, then restore your clipboard. Drafts longer than 10,000 characters are never prefilled. Before pasting it puts focus back into the original field.

Tools for debugging an app where reading or pasting fails:

- `build/Takes.app/Contents/MacOS/Takes --focus-test` reads the frontmost app's focused box without sending any keys and prints how it was read.
- `open -n build/Takes.app --args --ax-probe 3` waits 3 seconds and writes what the frontmost app reports about its focused element to `~/Library/Logs/Takes/ax-probe.txt`.
- Every summon is logged to `~/Library/Logs/Takes/focus.log` (app, element role, which method worked, how many characters).

## Performance

```
build/Takes.app/Contents/MacOS/Takes --bench --runs 5 --model claude-sonnet-5-5 --effort low
build/Takes.app/Contents/MacOS/Takes --bench --runs 5 --model claude-haiku-5-5 --takes 5
```

Each run prints the time to the first streamed words and the time until all takes are done. `--naive` runs Claude Code with its default setup: tools, MCP servers and user settings all load. Each real run's timing is logged to `~/Library/Logs/Takes/runs.jsonl`.

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

## Releasing

See [releasing.md](releasing.md).
