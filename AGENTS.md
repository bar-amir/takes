# Notes for coding agents

Read by AI coding tools (Claude Code, Codex, Cursor and others) working in this repository. People should start with [CONTRIBUTING.md](CONTRIBUTING.md).

## Project

Takes is a macOS menu-bar app (Swift 6 package, macOS 14+, SwiftUI and AppKit, no Xcode project). It reads the focused text field, asks a language model for a few rewrites ("takes") and pastes the chosen one back. The flow is in [docs/architecture.md](docs/architecture.md), and file locations are in [docs/development.md](docs/development.md#where-things-are).

## Commands

- Build the app: `./build.sh` (output: `build/Takes.app`)
- Build, test and lint, as CI does: `scripts/check.sh`
- Tests only: `swift test`, or `swift test --filter <TestClass>`
- Render every screen to PNGs: `build/Takes.app/Contents/MacOS/Takes --snapshot <folder>`
- Lint the files you changed: `swift format lint <files>`

Live tests (`*LiveTests.swift`) call real models and are skipped unless their environment variable is set. Don't set it: those tests use the developer's own accounts.

## Rules

- **Privacy.** Never add analytics, telemetry, crash reporting or any network call other than to the engine the user picked. Never log draft text; the logs in `~/Library/Logs/Takes` hold metadata only.
- **Secrets.** API keys and tokens go in the Keychain only, never in `UserDefaults`, the JSON files in `~/Library/Application Support/Takes`, or logs.
- **Scope.** Change only what the task needs. No drive-by reformatting, renames or refactors, and no new dependencies.
- **Style.** 4-space indentation and the style of the surrounding code. User-facing text is short, plain and specific.
- **Tests.** Add or update unit tests in `Tests/TakesTests` for logic changes, and run `scripts/check.sh` before you finish.
- **UI changes.** Render snapshots and look at them (light and dark) before saying a UI change is done.
- **Don't edit** `CHANGELOG.md`, `VERSION`, `CLA.md`, `LICENSE`, `.github/workflows/release.yml` or the signing scripts unless the task is explicitly about them.
- **Commits.** Use an `Assisted-by:` trailer (for example `Assisted-by: Claude Code`) and describe the change in the pull request template, including the AI disclosure.
