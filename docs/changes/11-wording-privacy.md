# 11 · Engine-aware wording and provider compliance

Every user-facing sentence that assumed Claude/Anthropic now names the engine the user picked. Claude stays the default
and the first thing mentioned ("takes written by Claude, or a model of your choice"). No logos, no "GPT" in any name,
"ChatGPT" only for the plan sign-in.

## How Takes follows the providers' rules (from `PRIVACY.md`)

> **Anthropic.** With Claude Code, Takes runs the unmodified Claude Code you installed, and you sign in to it through Anthropic's own flow. Takes never sees, stores or forwards your Claude credentials or session tokens. Every request is yours, billed to your own plan or key, and nobody else's requests ever use your account. With an API key, the key is yours, it stays in your keychain, and Anthropic bills you for it. See [Anthropic's Claude Code legal and compliance page](https://code.claude.com/docs/en/legal-and-compliance).

> **OpenAI.** With Sign in with ChatGPT, Takes is an open-source app that runs on your Mac. You sign in in your browser, on OpenAI's pages, and Takes never asks for your ChatGPT password. The tokens are stored only in your macOS keychain. Requests come from your Mac, for you, for Takes only. Takes never pools, shares or resells plan usage, and never charges for this. You can see and cap Takes' usage, and revoke it, in ChatGPT › Settings. With an OpenAI API key, the key is yours, it stays in your keychain, and OpenAI bills you for it. See [OpenAI's Sign in with ChatGPT terms](https://openai.com/policies/sign-in-with-chatgpt-terms/) and [ChatGPT plan usage for open-source apps](https://developers.openai.com/siwc/token-sharing-open-source).

Sources, read 2 November 2026: Anthropic's [Claude Code legal and compliance](https://code.claude.com/docs/en/legal-and-compliance),
OpenAI's [Sign in with ChatGPT terms](https://openai.com/policies/sign-in-with-chatgpt-terms/) (29 Sep 2026) and
[ChatGPT plan usage for open-source apps](https://developers.openai.com/siwc/token-sharing-open-source). The SIWC terms
(§3) say to "promptly contact OpenAI" about vulnerabilities but name no address; `SECURITY.md` points to OpenAI's
[coordinated vulnerability disclosure policy](https://openai.com/policies/coordinated-vulnerability-disclosure-policy/),
which is their published channel.

## Files and strings

- `PRIVACY.md`: "Where your text goes" is now a shared list of what's sent, then one subsection per engine with the
  same shape (to whom, how, terms, what's stored, data-use link): Claude Code on this Mac, Anthropic API key, Your
  ChatGPT plan (with the Plus/Pro and "preview" note), Other provider (incl. "a custom address is your
  responsibility"), Local model. Tone notes go "to the model your engine uses (Claude Haiku with Claude; your picked
  model otherwise)". New subsection "How Takes follows the providers' rules". Dictation, the keychain row and "AI
  output" no longer say Anthropic/Claude only. Other sections unchanged.
- `SECURITY.md`: scope line names any chosen engine and sign-in tokens; ChatGPT sign-in vulnerabilities are also
  reported to OpenAI (terms + disclosure link).
- `CONTRIBUTING.md`: "the user's chosen engine".
- `README.md`: intro, install step 3, setup ("a working engine" and what counts), panel reply-context line, Engine
  settings line, "How it calls the model" (+ ProviderEngine and ChatGPTEngine sentences), Privacy, and the disclaimer
  (not made by Anthropic, OpenAI or any other provider).
- `site/index.html`: og:description, privacy heading "Your Mac. Your model. Your choice.", "Your connection" row,
  FAQ "What do I need?", new FAQ "Which models can it use?" (the short engines list, so no layout change),
  "What does it cost?", "Is it made by Anthropic or OpenAI?", footer. Hero had no Claude-only copy. "Use Ollama or LM
  Studio instead of Claude" stays (a comparison). No images, videos or styles touched.
- `Setup.swift`: doc comment; step 2 "Connect a model" with a detail and button label per engine (ChatGPT: "Sign in
  with ChatGPT"; API key/provider: "Add your API key"; local: "Open Engine settings"); step 3 "Your text and the
  model". New `SetupMonitor.privacySummary(for:)` (where the text goes, one sentence per engine; a custom provider is
  "the server you added") and `SetupMonitor.mistakesNote(for:)` ("Claude can…" only for Claude engines, else
  "Models can…").
- `OnboardingView.swift`: welcome subtitle ("by Claude or a model of your choice"); engine step "Connect a model" with
  the new subtitle; privacy step "Your text and the model", engine-aware "In short: …" subtitle, and its two rows use
  the shared functions (with the engine picked a step earlier).
- `Onboarding.swift`: step list "Connect a model".
- `EngineTab.swift`: the Privacy section's first sentence is a switch on engine (local, Claude, ChatGPT, provider,
  custom server); the "no server of ours…" sentence is shared.
- `InstantMode.swift`: "The model sent back an empty take." `AppDelegate.swift` About credits: "…with Claude or a model
  of your choice." `PresetGalleryView.swift`: a comment.
- Kept: Claude-Code-specific errors and labels (`ClaudeCodeEngine`, `APIEngine`, engine cards), `LocalEngineViews`
  "plainer takes than Claude" and the model note. `Prompt.swift` never said "You are Claude"; unchanged.
- Tests: `OnboardingTests.swift` gains `PrivacySummaryTests` (each engine's destination, mistakes note); one assertion
  message reworded. `swift build` has no warnings; `swift test`: 245 tests, 0 failures.

## For the orchestrator

- Snapshots checked: `6-setup.png`, onboarding `4-privacy`, `1-welcome`, `3-engine-*`. Copy fits. With five engine
  options the onboarding engine step is taller than the window and the title sits at the top edge (it comes from the
  scaffold adding two options, not from this copy); worth a layout look after the sibling details land.
- The provider sentences use `Provider.current(settings).name` and treat `id == "custom"` as "the server you added".
- `PRIVACY.md` links per-provider data pages (OpenAI, Gemini API terms, OpenRouter, Groq, Mistral); recheck them against
  the provider table the `provider-api` session ships.
