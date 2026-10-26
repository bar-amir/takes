# Contributing to Takes

Thanks for helping. A few things before you open a pull request.

## Before your first pull request

1. **Sign the Contributor License Agreement.** Read [CLA.md](CLA.md), then add a line to [CLA-SIGNATURES.md](CLA-SIGNATURES.md) in your pull request. Pull requests from people who haven't signed can't be merged. In short: you keep your copyright, the project can use your work under MIT, and the maintainer may release future versions under other terms.
2. **Check you're allowed to contribute.** If you're employed, make sure your employment agreement lets you contribute to outside projects, or get permission. Work on your own equipment and time.

## How changes get in

- `main` is protected. Every change goes through a pull request and needs the maintainer's approval. If you push new commits after approval, it needs approval again.
- Keep pull requests focused on one change and explain what it does and how you checked it.
- Build with `./build.sh`. For UI changes, include screenshots: `build/Takes.app/Contents/MacOS/Takes --snapshot <folder>` renders every screen.

## Privacy

Takes never sends data to the project or its maintainer. Don't add analytics, crash reporting or any network call other than to the user's chosen Claude engine, unless it's discussed first and added to [PRIVACY.md](PRIVACY.md).
