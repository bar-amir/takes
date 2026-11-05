# Contributing to Takes

Thanks for helping. Takes is a small Swift app maintained by one person, so this page is mostly about making your time, and the review, count.

By taking part you agree to the [code of conduct](CODE_OF_CONDUCT.md). For questions, see [SUPPORT.md](SUPPORT.md).

## Ways to help

- **Report apps where Takes can't read or paste.** These reports are the most useful of all. Use the [app compatibility form](https://github.com/bar-amir/takes/issues/new?template=app_compatibility.yml).
- **Report bugs** with clear steps, and **test fixes** that others propose.
- **Share presets** that work well ([preset idea](https://github.com/bar-amir/takes/issues/new?template=preset_idea.yml)).
- **Improve the docs.** If something confused you, it will confuse the next person too.
- **Write code.** Start with issues labelled [good first issue](https://github.com/bar-amir/takes/labels/good%20first%20issue) or [help wanted](https://github.com/bar-amir/takes/labels/help%20wanted).

## Before your first pull request

1. **Sign the Contributor License Agreement.** Read [CLA.md](CLA.md). When you open your first pull request, a bot will ask you to reply with a sentence that signs it. Until everyone who wrote commits in a pull request has signed, its "CLA" check fails and it can't be merged. In short: you keep your copyright, the project can use your work under MIT, and the maintainer may release future versions under other terms. Your commits need to use an email that's linked to your GitHub account.
2. **Check you're allowed to contribute.** If you're employed, make sure your employment agreement lets you contribute to outside projects, or get permission. Work on your own equipment and time.
3. **Talk first about anything bigger than a small fix.** Open an issue, or comment on an existing one, and wait for a reply before you write a new feature, a new engine, a redesign or a large refactor. Pull requests that weren't discussed may be closed, however good they are, because every feature has to be maintained for years. Typos, small bug fixes and docs fixes don't need an issue.
4. **Say you're working on it.** Comment on the issue so two people don't do the same work. If you stop, say so too.

## Set up

You need a Mac with macOS 14 or later and Swift 6 (Xcode 26, or the Command Line Tools: `xcode-select --install`). No Xcode project and no other tools are needed.

```
git clone https://github.com/<you>/takes.git && cd takes
./build.sh && open build/Takes.app
scripts/check.sh
```

`scripts/check.sh` runs the same build, tests and lint as CI. On first launch macOS asks for Accessibility access; [docs/development.md](docs/development.md) explains that, and the debugging tools.

New to the code? [docs/architecture.md](docs/architecture.md) walks through what happens between the hotkey and the paste, and where to make common changes.

## Making the change

- **One change per pull request.** Keep it focused, and keep refactors and formatting out of feature pull requests.
- **Match the code around you.** 4-space indentation, Swift 6, SwiftUI for views. `.editorconfig` and `.swift-format` describe the style, and `swift format lint` checks the files you change (CI reports it as warnings). Please don't reformat whole files you aren't otherwise changing.
- **Add tests** in `Tests/TakesTests` for logic: prompts, parsing, diffing, settings decoding. Tests that call a real model are skipped unless an environment variable is set (see `*LiveTests.swift`); CI never runs them.
- **UI changes need screenshots.** `build/Takes.app/Contents/MacOS/Takes --snapshot <folder>` renders every screen, in light and dark. Attach before and after images.
- **User-facing text** is plain, short and specific. Read the screens next to yours and match their tone.
- **Accessibility counts.** Controls need labels VoiceOver can read, and everything should work from the keyboard.
- **No new dependencies** without discussing it first. Takes has one (Sparkle).

### Privacy rule

Takes never sends data to the project or its maintainer. Don't add analytics, crash reporting or any network call other than to the user's chosen engine, unless it's discussed first and added to [PRIVACY.md](PRIVACY.md).

## Opening the pull request

- Fill in the template: what changed, why, how you checked it, and a one-line release note.
- Link the issue (`Fixes #123`).
- Don't edit `CHANGELOG.md` or `VERSION`. The maintainer writes the changelog from your release note when releasing (see [docs/releasing.md](docs/releasing.md)).
- Pull requests from forks are safe to open: CI builds and tests them with read-only access and no secrets. For a first-time contributor, the maintainer approves the CI run before it starts.
- Draft pull requests are welcome when you want early feedback.

## Review

- `main` is protected. Every change goes through a pull request and needs the maintainer's approval. If you push new commits after approval, it needs approval again.
- The checks that must pass are **build** (build and tests) and **CLA**.
- Expect a first response within about a week. If there's been nothing for two weeks, a polite ping is fine.
- Pull requests are squash-merged, so you don't need to tidy your commit history.
- A pull request waiting on you for 30 days may be closed. You're welcome to reopen it.

## AI-assisted contributions

AI tools are welcome, and Takes itself is built with them. The rules are about responsibility, not about tools:

- **You're the author.** Read, understand, build and test everything you submit. You must be able to explain every line and answer review questions about it yourself.
- **Say so.** Tick the AI box in the pull request template, and say what the tool did ("wrote the first draft of the parser", "generated tests"). For commits that are mostly AI-written, add a trailer such as `Assisted-by: Claude Code`.
- **No unreviewed bulk output.** Pull requests or issues that look generated and unreviewed (invented APIs, made-up test results, wording no person wrote, many near-identical pull requests) will be closed without review.
- **Issues and comments are written by you.** Use an AI tool to translate or tidy your writing if it helps, but don't post generated bug reports, reviews or replies.
- **The CLA still applies.** You confirm you have the right to submit the work, including anything a tool produced.

Coding agents should read [AGENTS.md](AGENTS.md), which lists the commands and conventions for this repository.

## Recognition

Contributors are credited in the release notes of the version their work ships in.
