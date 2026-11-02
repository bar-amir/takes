# Security

Takes has Accessibility access on your Mac: it can read the text box you're typing in and paste into it. Security problems matter, so please report them privately.

## Reporting a problem

Use GitHub's private reporting: [Report a vulnerability](https://github.com/bar-amir/takes/security/advisories/new). Please don't open a public issue.

If the problem affects Sign in with ChatGPT (the "Your ChatGPT plan" engine), we also report it to OpenAI promptly, as its [Sign in with ChatGPT terms](https://openai.com/policies/sign-in-with-chatgpt-terms/) require, through OpenAI's [coordinated vulnerability disclosure policy](https://openai.com/policies/coordinated-vulnerability-disclosure-policy/). You're welcome to report it there yourself too.

Include what you found, how to reproduce it, and which Takes and macOS versions you used. You'll get a reply within a week. Once a fix is released, you'll be credited in the release notes unless you'd rather not be.

## What's in scope

- Takes reading text outside the text box you summoned it from, or at times other than when you press its hotkey.
- Text, settings, keys or sign-in tokens leaving your Mac anywhere other than to the engine you chose (Anthropic, OpenAI or another provider you picked, or your local model server).
- Your clipboard not being restored, or being exposed.
- API keys or ChatGPT sign-in tokens being readable outside the macOS keychain.
- Ways to make Takes paste or type something you didn't choose.
- Problems in the signed and notarized download or in automatic updates.

## Supported versions

Only the latest release gets security fixes.
