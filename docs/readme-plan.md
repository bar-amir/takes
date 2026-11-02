# README overhaul: gap analysis and plan

Goal: the README should turn a visitor from HN, Reddit or Product Hunt into someone who downloads Takes within one screen, and turn a curious developer into a contributor within two.

## What well-regarded Mac apps do

Looked at Rectangle, Ice, Maccy, Stats, AltTab, Jan and Ollama.

- **First screen = icon, name, one sentence, picture, download.** Ice, Stats and Maccy all show the icon and a screenshot or banner before any text section. Stats makes the screenshot itself the download link. AltTab's README is nothing but a banner that links to the site.
- **One-line pitch that says what it is and for whom.** "Maccy is a lightweight clipboard manager for macOS." No feature list in the first sentence.
- **A handful of badges, not a wall.** Ice: download, platform, macOS 14+, sponsor, website, license. Maccy: downloads, build.
- **Two install paths side by side:** a direct download link and `brew install --cask …`. Every one of them has the Homebrew line.
- **Features as short bullets, details in screenshots** (Ice's "Gallery", Stats' two images).
- **FAQ for the predictable questions** (Maccy, Stats): permissions, "why doesn't it paste", hotkey conflicts.
- **User docs first, developer docs last or elsewhere.** Rectangle and Maccy keep advanced settings below the fold; Jan and Ollama put build-from-source near the end and push depth to a docs site. Release processes never appear in the README.

## Where the current README falls short

1. **No picture.** The first screen is plain text; there's no screenshot even though `site/img` has good ones.
2. **The pitch undersells the hook.** "A macOS menu-bar app" doesn't say the two things that make Takes different: it works in *any* app, and it uses the Claude subscription you already pay for, with no server or account.
3. **No download button.** Install points to the Releases page and asks for `Takes-<version>.dmg`; the stable `releases/latest/download/Takes.dmg` link isn't used. No Homebrew line.
4. **Maintainer material sits second.** "Releasing" (secrets, notarization, Sparkle) is the second section a visitor sees.
5. **It reads like a manual.** "The panel" and "Settings" are exhaustive shortcut references, good for users who have installed it, noise for someone deciding whether to.
6. **Deep engineering detail is mixed with user docs:** AX reading fallbacks, `--focus-test`, `--ax-probe`, bench numbers, CLI flags.
7. **No FAQ.** Cost, which apps it works in, "is my text sent anywhere", "is this made by Anthropic" are answered on the site but not in the README.
8. **Weak contributor path.** One line pointing to CONTRIBUTING.md and the CLA; no "how to build", no project layout, no pointer to `good first issue`.

## Proposed outline

```
[icon]  Takes
One-line pitch: rewrite anything you type, in any app, with the Claude
subscription you already have. No server, no account.
Badges: latest release · macOS 14+ · MIT · Sponsor
[Download for Mac]  ·  brew install --cask bar-amir/tap/takes  ·  Website

HERO: site/img/takes.png (real UI from `Takes --snapshot`), linked to the site
<!-- TODO: replace with a 10-second demo GIF: Slack field → ⌃⌥Space → 3 takes → paste -->

## How it works          3 steps: Draft (⌃⌥Space) → Choose → Paste
## Features              6–8 bullets, one line each (presets, takes side by side + changes,
                         proofread, write-and-paste-right-away, reply context, tone,
                         dictation, local models, your languages)
                         + 2 screenshots (presets.png, proofread.png) in a small gallery
## Install               DMG, Homebrew (placeholder), first-run onboarding in 3 lines,
                         requirements, uninstall
## Choose your engine    small table: Claude Code (subscription) / API key / Local model —
                         what you need, where text goes
## Privacy               keep the promise verbatim-ish + link to PRIVACY.md
## Costs and responsibility   ← slot reserved for the other session's section (merge)
## FAQ                   cost, which apps, hotkey conflict, Accessibility re-prompt,
                         not affiliated with Anthropic
## Contributing          build in 2 commands, project layout, snapshot tool,
                         good first issues, CLA, link to docs/development.md
## License               MIT + trademark note + "not made or endorsed by Anthropic"
```

## What moves out of the README

| Section today | New home |
|---|---|
| The panel, Settings (full shortcut and option reference) | `docs/usage.md` |
| Reading and pasting in web-based apps, `--focus-test`, `--ax-probe` | `docs/development.md` → "How Takes reads text fields" |
| Measuring (bench commands, results table, what made it fast) | `docs/development.md` → "Performance" |
| How it calls Claude | `docs/development.md` → "Engines" |
| Build and run | short version in README, full in `docs/development.md` |
| Releasing | `docs/releasing.md` |
| Setup (setup window behavior) | `docs/usage.md` |

Nothing is deleted; every paragraph lands in one of these three files.

## Rules kept

- Privacy promise and the link to PRIVACY.md stay in the README.
- "Takes isn't made, endorsed or supported by Anthropic" stays.
- No other product or trademark is named.
- The Homebrew line is marked as coming once the tap is published.
- Leave a `## Costs and responsibility` heading for the other session's text so the merge is a drop-in.

## Open questions

1. Hero: use the real UI screenshot (`takes.png`) now, or the product-render photo (`hero-og.jpg`) from the site? The plan uses the real UI; the render is more striking but doesn't show the app.
2. Badges: include a downloads badge? At ~6 downloads it may hurt more than help; the plan leaves it out for now.
