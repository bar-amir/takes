# Security

Takes has Accessibility access on your Mac: it can read the text box you're typing in and paste into it. Security problems matter, so please report them privately.

## Reporting a problem

Use GitHub's private reporting: [Report a vulnerability](https://github.com/bar-amir/takes/security/advisories/new). Please don't open a public issue.

Include what you found, how to reproduce it, and which Takes and macOS versions you used. You'll get a reply within a week. Once a fix is released, you'll be credited in the release notes unless you'd rather not be.

## What's in scope

- Takes reading text outside the text box you summoned it from, or at times other than when you press its hotkey.
- Text, settings or keys leaving your Mac anywhere other than to Anthropic through the engine you chose.
- Your clipboard not being restored, or being exposed.
- The API key being readable outside the macOS keychain.
- Ways to make Takes paste or type something you didn't choose.
- Problems in the signed and notarized download or in automatic updates.

## Supported versions

Only the latest release gets security fixes.
