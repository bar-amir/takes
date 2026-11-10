# Plan · providers: write takes with another cloud model (OpenAI and friends)

Status: proposal, 2 November 2026. Nothing here is built. Estimate: 4–7 days for one person.

## What it is

A fourth engine in Settings › Engine, **Other provider**: the user pastes their own API key for OpenAI, Google Gemini,
OpenRouter, Groq, Mistral or any server that speaks the OpenAI chat-completions API, picks a model, and Takes writes
with it. Claude Code stays the default and the product stays "takes written by Claude" first; this is the escape hatch
for people who already pay another provider.

It reverses one line of `docs/orchestration/BRIEF.md` ("No cloud providers other than Anthropic") and of
`docs/changes/7-local-models.md`. That's a product decision; this plan assumes it's been made.

Not in scope: signing in with a ChatGPT or Gemini account (see Legal), per-preset models for other providers, images,
tools, or anything beyond text in → takes out.

## Legal: what's allowed, and what isn't

Checked on 2 November 2026 against the providers' own pages. Not legal advice; the pages change, so re-read them before
release and link the versions you read in the change note.

### Bring-your-own API key is the clean path. Account login is not.

- **OpenAI.** A user's own API key, billed to them, is ordinary API use; nothing in the terms forbids a desktop app
  that stores the key on the user's Mac. Using a **ChatGPT Plus/Pro subscription** instead is only allowed through
  OpenAI's opt-in **Sign in with ChatGPT** program (terms dated 29 September 2026). Its rules are compatible with
  Takes (requests from the user's own Mac, tokens stored locally, no charge for the feature, the user's plan used only
  for Takes) but it needs an application registered with OpenAI, their OAuth flow and their approval. Treat it as a
  possible phase 2, never as "paste your ChatGPT session". Never ask for a ChatGPT password or cookie: that's
  explicitly prohibited.
- **Google Gemini.** The Gemini API terms allow API clients where the user brings a key; in the EEA, Switzerland and
  the UK an app may only be offered against **paid** (billed) Gemini keys, so the Settings card should say the key
  must be on a project with billing on. Google's OpenAI-compatible endpoint is the documented way to reach it. No
  login with a Google account.
- **OpenRouter, Groq, Mistral, others.** Standard API key use. Nothing special found; check each one's terms when it's
  added to the list of known providers (one line each in the change note).
- **Anthropic (already shipped).** Anthropic's Claude Code legal page (updated February 2026) says consumer OAuth is
  "exclusively" for Claude Code and native Anthropic apps, that developers may not "route requests through Free, Pro,
  Max, or Ultra plan credentials on behalf of their users", and that it does not prevent "an end user from signing in
  to the unmodified Claude Code binary with their own Claude subscription", including where a product runs Claude
  Code. Takes runs the unmodified `claude` binary, never sees a token, and the user signs in through Anthropic's own
  flow, so it sits on the allowed side, but it's a grey zone worth a one-paragraph note in `PRIVACY.md` and a sentence
  in the README. This plan doesn't change it. The API-key engine is plainly fine.

### Names and logos

- **No provider logos** in the app, the website or the DMG. OpenAI's guidelines require permission for the logo and
  forbid using it "more prominently than your own". Anthropic's say the same for theirs. Text only, which is also the
  house style.
- **No model or provider name in the app name, feature names or domain.** "Takes" is fine. Don't call the feature
  "GPT mode" or anything with "GPT" in it: OpenAI does "not permit our GPT brand to be used in app, product, developer
  or company names" and enforces it.
- **Plain, accurate text is allowed:** "Works with your OpenAI API key", "Model: gpt-5.4", "Written by Gemini 3 Flash".
  Be exact about model names; don't say "ChatGPT" when you mean the API (they're different products in OpenAI's own
  wording). Never imply partnership or endorsement ("in collaboration with", "official").
- README, website and the menu-bar tagline keep "written by Claude" as the default story and add one line:
  "or a model of your choice: a local one, or your own OpenAI, Gemini or OpenRouter key."

### Privacy and disclosure

- `PRIVACY.md` gets a subsection, **Another provider's API**, matching the Anthropic one: what is sent (draft, preset
  instruction, reply context, tone requests), to whom (the host the user picked, under their own account and that
  provider's terms), what is stored (the key in the macOS keychain, never in files), and that nothing goes to the
  developer. Link each known provider's API data-use page.
- The Settings card says, in one line, where the text goes and under whose terms, before the key field. Same in
  onboarding (step 3, "Your text and Claude", becomes engine-aware).
- Keys stay in the login keychain, one keychain item per provider host. Never logged, never in `RunLog`, never in
  `--snapshot` output or screenshots.
- Takes sends nothing to any provider until the user has pressed the hotkey and asked for takes. Model-list probes
  (`GET /models`) happen only when the Engine tab is open or the panel opens with this engine, same as local.

## Design

### Settings › Engine

A fourth card under "Where your takes are written", after Local model:

> **Other provider** · Your own API key for OpenAI, Gemini, OpenRouter, Groq or Mistral, or any OpenAI-compatible
> server. Billed by the provider under your account.

Selecting it shows:

- **Provider** menu: OpenAI, Google Gemini, OpenRouter, Groq, Mistral, Custom address… Each known provider sets the
  base URL, the key's console link ("Get a key" opens the provider's page in the browser), and a one-line data note.
- **API key** secure field, commits on Return, "Saved in your keychain" under it. Pasting a key with a known prefix
  for a different provider ("sk-ant-" into OpenAI) gets an inline note.
- **Model** menu, filled from `GET /models` once a key is saved (fallback: a typed model ID when the list fails or the
  provider doesn't serve one). First sensible model auto-picked when none is set.
- **Test** button: one tiny request, "Works. Answered in 0.8 s." or the error in plain words (401 → "The key was
  refused. Check it in your OpenAI dashboard."; 429 → "Over your provider's rate limit or out of credit.").
- Status badge on the card: "OpenAI · gpt-5.4", "No key yet", "Key refused".

Custom address: https only, no userinfo, no loopback (that's the Local card), no IP literals; the card says "Takes
sends your drafts to this address. Only use a server you trust."

### The panel

Same behaviour as Local model: one model for every preset while this engine is on; the Model menu lists the provider's
models for one run; Effort hidden (or mapped, see below); picker summary and takes header name the real model and
provider ("3 takes · gpt-5.4 via OpenAI · same or shorter"). Tone notes and proofread use the chosen model
(`quickModel`), not Haiku.

Effort: hidden in v1. Follow-up: map Takes' low/medium/high to OpenAI's `reasoning_effort` for models that take it, and
drop it silently for those that don't (a 400 mentioning the field → retry without it, once).

### Setup and onboarding

- `Setup.swift` step 2 "Connect Claude" → "Connect a model": ready when a key is saved and the model list (or Test)
  answered; problems: "No API key saved yet", "The key was refused", "Pick a model".
- Onboarding engine step: the existing `// ORCHESTRATOR: add local engine option` pattern gets a fourth choice with the
  same card; the privacy step's text picks a sentence per engine.

## Code

Principle from the brief: new code in new files, small hooks in shared ones.

### New files

- `Sources/Takes/ChatCompletions.swift`: the engine core lifted out of `LocalEngine.swift`. `SSEParser`,
  `LocalChunk` (renamed `ChatChunk`), `LocalModelList` (→ `ChatModelList`), `chatRequest`, the streaming loop and
  error mapping become a `ChatCompletionsClient` parameterised by base URL, extra headers, `URLSession` and a
  take splitter. `LocalEngine` becomes a thin wrapper (loopback session, `LocalTakeCleaner`). No behaviour change for
  local; its 37 tests must still pass unchanged.
- `Sources/Takes/ProviderEngine.swift`: `enum Provider` (known providers: name, base URL, console URL, key prefix,
  data-use URL, how to list models, quirks), `ProviderEndpoint` (https-only validation, the inverse of
  `LocalEndpoint`), `ProviderEngine: TakesEngine` (bearer header, `TakeSplitter` by default with `LocalTakeCleaner` as
  a fallback when a take looks labelled, `finish_reason == "content_filter"` → "The provider declined to rewrite this
  draft."), `ProviderEngine.test`, `ProviderEngine.models`.
- `Sources/Takes/ProviderEngineViews.swift`: the card body (provider menu, key field, model menu, Test, badge),
  reusing the `LocalEngineViews` layout and `FormControls`.
- `Sources/Takes/Snapshot+Providers.swift`: card states (no key, ready, key refused, custom address), panel compose
  with a provider model, light and dark.
- `Tests/TakesTests/ProvidersTests.swift`.
- `docs/changes/9-providers.md` when done.

### Shared-file edits

- `Store.swift`: `EngineKind.provider`; append `providerID` (`"openai"`, `"gemini"`, …, `"custom"`),
  `providerBaseURL`, `providerModel` with `decodeIfPresent` and defaults; `runModel(for:)` and `quickModel` treat
  `.provider` like `.local`. Unknown engine values already fall back to Claude Code.
- `APIEngine.swift`: `Keychain` gains an `account:` parameter (`"anthropic-api-key"` stays as is so existing keys
  keep working; providers use `"provider-<host>"`).
- `Engine.swift`: one case in `Engines.current`.
- `Setup.swift`, `OnboardingModel.swift`, `OnboardingView.swift`: engine-aware titles, details, and
  `SetupMonitor.providerEngineStatus()`.
- `EngineTab.swift`: the fourth card and its privacy line.
- `PanelModel.swift`, `PanelViews.swift`: wherever `engine == .local` gates model options and hides Effort, make it
  `engine.usesOneModel` (a computed property on `EngineKind`), so both engines share the branch.
- `PresetsTab.swift`: `LocalEngineModelNote` wording covers both ("While the engine is OpenAI, every preset runs on
  gpt-5.4…").
- `InstantMode.swift`, `ToneCheck.swift`, `Proofread.swift`: nothing if they already go through `quickModel`/
  `runModel(for:)`; check the two `Models.haiku` literals in `ToneCheck` and `Proofread`.
- `Snapshot.swift`: one line.
- `PRIVACY.md`, `README.md` (Install step 3, Setup, "How it works"), `site/` copy, `CHANGELOG.md`, `VERSION`.

### Known-provider table (v1)

| Provider | Base URL | Models from | Notes |
|---|---|---|---|
| OpenAI | `https://api.openai.com/v1` | `GET /models`, filter to chat models | `max_completion_tokens` for reasoning models; `content_filter` finish reason |
| Google Gemini | `https://generativelanguage.googleapis.com/v1beta/openai` | `GET /models` | Paid key required in EEA/CH/UK: say so on the card |
| OpenRouter | `https://openrouter.ai/api/v1` | `GET /models` (large: filter, sort) | Optional `HTTP-Referer`/`X-Title` headers identify the app; set `X-Title: Takes` |
| Groq | `https://api.groq.com/openai/v1` | `GET /models` | Fast; small models → `LocalTakeCleaner` |
| Mistral | `https://api.mistral.ai/v1` | `GET /models` | `temperature` capped lower on some models |
| Custom | user-typed, https only | `GET /models`, or typed model | Warn that drafts go to that address |

Everything not in the table is "Custom". Keep the table in code with a comment per row citing the provider's docs page.

## Phases and estimate

| Phase | Work | Days |
|---|---|---|
| 0 | Decide: product yes/no; name of the card; v1 provider list. Re-read the four terms pages and note versions. | 0.25 |
| 1 | Extract `ChatCompletionsClient` from `LocalEngine`; local tests green, build warning-free. | 0.5–1 |
| 2 | `ProviderEngine`, `Provider` table, `ProviderEndpoint`, per-provider keychain. Unit tests + mock-server tests (bearer header sent, https enforced, 401/429 wording, `content_filter`, model list filtering). | 1 |
| 3 | Settings card, badge, Test, model menu; panel branches via `usesOneModel`; `PresetsTab` note. Snapshots light/dark. | 1–1.5 |
| 4 | Setup + onboarding copy and status; privacy step text per engine. Onboarding tests. | 0.5–1 |
| 5 | `PRIVACY.md`, README, site, CHANGELOG; Claude Code grey-zone paragraph. | 0.25–0.5 |
| 6 | Live pass with one real key per provider you have (short drafts; a handful of calls): compose, proofread, tone, instant mode, refine, "more like take N". Fix format quirks. | 0.5–1 |
| | **Total** | **4–7** |

Optional later: `reasoning_effort` mapping (+0.5), Sign in with ChatGPT (+2–3 plus OpenAI's approval), per-preset
provider models (not recommended, same reasons as local).

## Risks

- **Output format.** Prompt and `===` splitting are tuned for Claude. Big OpenAI/Gemini models follow it; Groq's
  small ones may not. Phase 6 decides per provider whether to append `LocalPrompt.formatRules` and use
  `LocalTakeCleaner`; make it a flag on the `Provider` row.
- **Model lists.** OpenAI's `/models` includes audio, image and embedding models; OpenRouter's has hundreds. Filter
  by known prefixes and let the user type an ID.
- **Quota and cost.** A refine or "more like take N" is a full request. Same as the API-key engine today; the card
  says "billed by the provider".
- **Brand drift.** The product story gets fuzzier ("Claude" is in the README 40 times and in `Setup.swift` 11). Keep
  Claude the default and the first word; the rest is "or your own model".
- **Terms change.** Re-check before each release where a provider is named; keep the Legal section above current.

## Done when

- A fresh user can pick Other provider, paste an OpenAI key, see the model list, press Test, and write 3 takes from
  Safari, with the header naming the model and provider.
- Switching back to Claude Code restores every preset's own model and effort, untouched.
- `swift test` green, `./build.sh` warning-free, snapshots for every card state in both appearances, VoiceOver labels
  on the new controls.
- `PRIVACY.md` and the Settings card say the same thing about where text goes.
- No provider logo anywhere; no model or provider name in any feature name; every provider name in copy is exact.

## Phase 2 · Sign in with ChatGPT (for everyone with a Plus or Pro plan)

Checked 2 November 2026 at developers.openai.com/siwc. Takes qualifies today without applying: OpenAI's "ChatGPT plan
usage" is open to "open-source projects, personal projects that run locally, and selected private apps". Takes is MIT
and runs locally. The interest form (openai.com/form/sign-in-with-chatgpt-interest/) is only for paid or remotely hosted
apps; if Takes ever charges for this engine it loses the open-source path (the terms also say users must be able to use
their plan "without paying you").

What OpenAI requires, mapped to Takes:

| Requirement (SIWC terms + OSS docs) | In Takes |
|---|---|
| Registration through the browser flow: `client_id=dynamic_agent_client`, `agent_name_hint=Takes`, a persisted opaque `ext_agent_host_id` (UUIDv4 or JWK thumbprint, one per Mac, never user-identifying) | Generate once, store in Application Support next to settings. The issued `client_id` is saved too. |
| OIDC + PKCE (S256), `state` and `nonce`, redirect to an HTTP loopback URI on `127.0.0.1` (not `localhost`), e.g. `http://127.0.0.1:1455/auth/callback`; path and host fixed, port may change | A tiny one-shot HTTP listener on 127.0.0.1 during sign-in, same as the mock server in `LocalModelsTests`. Open the browser; close the listener on callback. |
| Scopes `openid profile email offline_access resource.invoke chatgpt.tokens.use.direct`, `resource=https://api.openai.com/v1`; check the granted scopes include `chatgpt.tokens.use.direct` before any inference (sign-in alone grants nothing) | Setup card shows "Signed in as …, using your ChatGPT plan" or "Signed in, but plan usage wasn't allowed. Try again and tick the permission." |
| Token exchange at `https://auth.openai.com/api/accounts/oauth/token`, no client secret; rotating refresh token; replace access token, expiry, scopes and refresh token together | Keychain items per profile; refresh before expiry; `invalid_grant` → start a fresh sign-in. |
| Tokens stored locally under the user's control; never ask for a ChatGPT password or cookie | Keychain. Sign-in only through the browser. |
| Inference: `POST https://api.openai.com/v1/responses`, `Authorization: Bearer`, **`store: false`**, **`stream: true`**; no `system` role items (use `instructions`); no `temperature`, `top_p`, `max_output_tokens`, `metadata`, `user`; success only on `response.completed` | A `ResponsesEngine: TakesEngine` separate from the chat-completions client: the system prompt goes in `instructions`, the draft in `input`. Handle `response.failed` with `subscription_sharing_usage_limit_exceeded` / `_unavailable` ("You've used this week's ChatGPT allowance for Takes. Manage it in ChatGPT › Settings › Usage.") and `response.incomplete`. |
| Models: `GET https://api.openai.com/v1/models` with the bearer token; show entries with `visibility: "list"`, send `slug`, display `display_name`; refresh on account switch | Fills the Model menu like the other one-model engines. |
| Requests only from the user's own Mac, only for Takes, only for this user; no pooling or sharing; no charge for the feature | Already how Takes works. Keep this engine free forever. |
| Use the app's own name at sign-in; no OpenAI logos or implied endorsement; say "Using ChatGPT plan" and offer "Manage usage" (opens ChatGPT Settings › Usage) | Text button "Continue with ChatGPT" in house style; a "Manage usage" link on the card. |
| Privacy notice before processing; reasonable security; report vulnerabilities to OpenAI | `PRIVACY.md` subsection + the onboarding privacy step; `SECURITY.md` gains the OpenAI contact. |

*Update, 10 November 2026: the host ID in the first row is no longer kept for good. Signing out deletes
`chatgpt-host.json` and the next sign-in makes a new one; the issued client ID is still saved.*

Estimate: **2–3 days** on top of phase 1–6 (OAuth listener + PKCE + refresh 1 day; Responses-API engine 0.5–1; card,
onboarding, errors, privacy copy 0.5–1). Risks: the program is labelled *preview* and "selected" for private apps,
so limits and rules can change; weekly per-app allowances are set by the user in ChatGPT and may run out mid-use (the
panel must say so and offer the API-key or Claude engine); the `agent_name_hint` is editable by the user, so don't rely
on it. Nothing comparable exists for Gemini or for Claude (Anthropic forbids third-party use of subscription
credentials), so the "sign in with your plan" story is Claude Code and ChatGPT only.

## Sources (read 2 November 2026)

- OpenAI, Sign in with ChatGPT quickstart: https://developers.openai.com/siwc/quickstart
- OpenAI, ChatGPT plan usage for open-source and local apps: https://developers.openai.com/siwc/token-sharing-open-source
  (sign-in, models-and-inference, preview-limitations subpages)
- OpenAI cookbook, Integrating Sign in with ChatGPT in your open-source app: https://developers.openai.com/cookbook/articles/sign-in-with-chatgpt

- Anthropic, Claude Code legal and compliance: https://code.claude.com/docs/en/legal-and-compliance
- Anthropic, Commercial Terms: https://www.anthropic.com/legal/commercial-terms
- OpenAI, Sign in with ChatGPT Terms (29 Sep 2026): https://openai.com/policies/sign-in-with-chatgpt-terms/
- OpenAI, Design (brand) Guidelines and Marks usage terms: https://openai.com/brand/
- OpenAI, Usage Policies: https://openai.com/policies/usage-policies/ (not re-read today; the page refused the fetch)
- Google, Gemini API Additional Terms: https://ai.google.dev/gemini-api/terms
