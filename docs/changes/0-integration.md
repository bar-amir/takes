# 0 · Integration

The eight feature branches were merged into `claude/competitor-feature-analysis-8dcb80` in this order: local-models,
instant-mode, proofread, preset-gallery, reply-context, tone-check, dictation, onboarding. The notes 1-8 describe each
feature as its session built it; this note lists what changed when they met.

## Conflicts resolved

- `Store.swift`: every new `Preset` and `AppSettings` field kept, each decoded with a default. `Preset`'s tolerant
  decoder (from tone-check) now also decodes `instantMode`, `minimalEdits` and `galleryID`; without that, those settings
  were lost on relaunch (caught by the round-trip tests).
- Preset loading: fresh installs get `PresetGallery.initialPresets`, then `Proofread.upgraded` runs on whatever loaded,
  so an untouched old "Proofread only, keep my words" preset becomes the new Proofread for existing users too.
- `PanelController.summon`: the clipboard is captured before the field is read (reply context), then handed through the
  instant-mode `summon(focus:…)` entry point and onboarding's `open(focus:…)`, so all three paths share one route.
- Compose status row: word count on the left; "Add what you're replying to ⌘J" and "Dictate ⌘D" on the right, in one row.
- Esc in compose backs out one layer at a time: dictation, then the tone read, then the panel.

## Cross-feature wiring

- Proofread is in the gallery (first) and in the starters; its card blurb is "Fixes mistakes only. Keeps your words."
  It has tone notes off (a tone note on a typo fix adds nothing).
- Instant mode and tone notes run on the engine's model: the local model with the local engine, instead of asking a
  local server for a Claude model. Tests: `LocalEngineIntegrationTests`.
- Onboarding: the presets step offers `PresetGallery.starters` (with gallery blurbs, added as linked copies); the engine
  step has a third option, "A model on this Mac", with Check again and Get Ollama; the done step has one line about ⌘D
  dictation that follows the microphone permission state.
- Preset editor: Minimal edits, Show tone and Write and paste right away were three differently styled blocks. They're
  now rows of one "How it writes" card (`PresetOptions.swift`). Snapshot: `options-*`.
- Release signing grants `com.apple.security.device.audio-input` (`Resources/Takes.entitlements`); the hardened runtime
  blocks the microphone without it. Checked with an ad-hoc signed copy.

## Shortcuts added (no clashes)

Compose: ⌘J, ⇧⌘V, ⇧⌘⌫ (reply context), ⌘T (tone), ⌘D (dictation). Instant mode uses each preset's own hotkey.

## Verification

- `swift test`: 227 tests, 0 failures. `./build.sh`: no warnings.
- `--snapshot`: 133 PNGs, light and dark, reviewed.
- Live, merged build, TextEdit: the Proofread hotkey (instant mode) read the field, ran Haiku and returned
  "I think the specs are due Wed, can you check with Dana if that's still ok" in 6.9 s. Another app came to the front
  before the paste, and instant mode correctly typed nothing. The paste itself, dictation with a real microphone, and a
  local model generating (Ollama here has no models) are still to be checked by hand.
