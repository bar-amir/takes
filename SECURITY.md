# Security

Takes has Accessibility access on your Mac: it can read the text box you're typing in and paste into it. Security problems matter, so please report them privately.

## Reporting a problem

Use GitHub's private reporting: [Report a vulnerability](https://github.com/bar-amir/takes/security/advisories/new). Please don't open a public issue, pull request or discussion about it.

Include:

- what you found and what an attacker could do with it;
- how to reproduce it (steps, a proof of concept, or a draft or file that triggers it);
- the Takes version (Takes menu › About), the macOS version, and the engine you used.

If the problem affects Sign in with ChatGPT (the "Your ChatGPT plan" engine), we also report it to OpenAI promptly, as its [Sign in with ChatGPT terms](https://openai.com/policies/sign-in-with-chatgpt-terms/) require, through OpenAI's [coordinated vulnerability disclosure policy](https://openai.com/policies/coordinated-vulnerability-disclosure-policy/). You're welcome to report it there yourself too. A problem in Claude Code, Sparkle, Ollama, LM Studio or a provider's API belongs with that project; tell us too if it affects Takes users.

## What happens next

Takes has one maintainer, so these are targets, not guarantees.

1. **Within 7 days:** a reply saying the report arrived, and whether more details are needed.
2. **Within 14 days:** whether it's accepted as a vulnerability, and how serious it looks.
3. **A fix:** within 90 days of the report, sooner for anything that exposes text, keys or tokens or lets someone run code. It ships as a normal release through automatic updates.
4. **Disclosure:** once the fix is released, a GitHub security advisory describes the problem (with a CVE when it warrants one), and you're credited in it and in the release notes unless you'd rather not be. We agree a date with you; if a fix takes longer than 90 days, we tell you why and agree a new date.

You're welcome to publish your own write-up after the advisory is out.

## What's in scope

- Takes reading text outside the text box you summoned it from, or at times other than when you press its hotkey.
- Text, settings, keys or sign-in tokens leaving your Mac anywhere other than to the engine you chose (Anthropic, OpenAI or another provider you picked, or your local model server).
- Your clipboard not being restored, or being exposed.
- API keys or ChatGPT sign-in tokens being readable outside the macOS keychain, or written to files or logs.
- Ways to make Takes paste or type something you didn't choose, or run a program, through a draft, a reply context, a preset file or a model's answer.
- Problems in the signed and notarized download, the update feed or automatic updates.
- The release workflows in `.github/workflows/` (for example, a way for a pull request to reach the signing secrets).

## Out of scope

- A model writing something wrong, rude or unexpected. Takes shows every take before pasting (unless you turned on "write and paste right away" for a preset), and what you send is up to you.
- Attacks that need someone who already controls your Mac account, or physical access to an unlocked Mac.
- A custom provider address or a local model server that you chose and that misbehaves: Takes sends it your drafts by design (see [PRIVACY.md](PRIVACY.md)).
- Missing hardening with no way to exploit it, reports from automated scanners without a working example, and the landing page's content.

## Safe harbor

Research done in good faith under this policy is welcome: we won't take legal action or ask anyone else to. Please only test against your own Mac and accounts, don't access other people's data, and give us a reasonable time to fix a problem before you share it.

## Supported versions

Only the latest release gets security fixes. Automatic updates (Takes menu › Check for Updates…) keep you on it.

## How releases are protected

- The app and disk image are signed with the developer's Developer ID, use the hardened runtime, and are notarized by Apple.
- Updates come from `appcast.xml` on GitHub Releases over https. Takes only installs an update whose download is signed with the developer's EdDSA update key (checked before the disk image is opened), and releases after 0.5.1 also refuse a feed that isn't signed with that key.
- Each release's disk image has a build provenance attestation. To check a download came from this repository's release workflow:
  ```
  gh attestation verify Takes-<version>.dmg --repo bar-amir/takes
  ```
- The signing secrets live only in the protected `release` environment, which needs the maintainer's approval and only runs for version tags on `main`. Workflows that run for pull requests use no secrets and a read-only token.

## For contributors

- **Never commit keys or tokens**, even test ones. Tests use mock servers and in-memory credentials; the opt-in live tests (`TAKES_LIVE_*`) use the engines you're already signed in to.
- **Turn on the secrets hook** once per clone. It runs [gitleaks](https://github.com/gitleaks/gitleaks) on what you're about to commit:
  ```
  brew install gitleaks
  git config core.hooksPath .githooks
  ```
- Every pull request runs the same gitleaks scan and CodeQL (`.github/workflows/security.yml`). GitHub's secret scanning with push protection also blocks pushes that contain known token formats.
- Pin new GitHub Actions to a full commit SHA with the version in a comment (`uses: owner/action@<sha> # v1.2.3`), give each job only the `permissions:` it needs, and never check out or run pull request code in a `pull_request_target` workflow. Dependabot keeps the pins current.

### If a secret is ever committed

Treat it as leaked the moment it's pushed, even if the commit is removed: forks, clones and caches keep it.

1. **Revoke or rotate it first**, where it was issued (provider dashboard, App Store Connect, Apple Developer, GitHub settings, 1Password).
2. Update the copy the workflows use (`gh secret set <NAME> --env release`), and check the provider's logs for use of the old one.
3. Only then think about removing it from history, which needs a force-push and coordination; rotating is what actually protects you.
4. The Sparkle update key is special: users' copies of Takes trust its public half (`Resources/SUPublicEDKey`). If the private key leaks, generate a new one and ship a release, signed with the old key, whose Info.plist carries the new `SUPublicEDKey`; later updates are signed with the new key ([Sparkle: rotating keys](https://sparkle-project.org/documentation/#rotating-signing-keys)). Back the new key up to 1Password and update `SPARKLE_PRIVATE_KEY` in the `release` environment.
