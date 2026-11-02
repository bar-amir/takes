# Releasing

Releases are built by GitHub Actions ([.github/workflows/release.yml](../.github/workflows/release.yml)):

1. In a pull request, bump `VERSION` and add a `## <version>` section to `CHANGELOG.md`. Merge it.
2. Tag the merge commit and push the tag: `git tag v0.1.0 && git push origin v0.1.0`.
3. Approve the run in the protected `release` environment (GitHub › Actions). Only then can it read the signing secrets.
4. It builds a universal app, signs it with the Developer ID (hardened runtime, Sparkle signed inside out), notarizes and staples the app and the disk image, checks them with Gatekeeper, signs the update for Sparkle, attests build provenance, and publishes the GitHub Release with the `.dmg`, its checksum and `appcast.xml`.
5. A second job points the Homebrew cask in [bar-amir/homebrew-tap](https://github.com/bar-amir/homebrew-tap) at the new version and checksum.

Installed copies find updates through `https://github.com/bar-amir/takes/releases/latest/download/appcast.xml`. Each release also carries the same disk image as `Takes.dmg`, so `https://github.com/bar-amir/takes/releases/latest/download/Takes.dmg` always downloads the latest version (use it for download buttons).

## One-time setup

Run `scripts/setup-release-secrets.sh` to store the Developer ID certificate, an App Store Connect API key and the Sparkle update key as environment secrets. `scripts/release.sh` runs the same steps on your Mac (`--unsigned` to test without signing).

For the Homebrew bump, create a [fine-grained personal access token](https://github.com/settings/personal-access-tokens/new) with access to `bar-amir/homebrew-tap` only, permission Contents: Read and write, and store it as the repository secret `HOMEBREW_TAP_TOKEN` (Settings › Secrets and variables › Actions, or `gh secret set HOMEBREW_TAP_TOKEN -R bar-amir/takes`). Without it the job skips with a warning.
