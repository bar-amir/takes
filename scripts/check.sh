#!/bin/zsh
# Runs what CI runs: build, unit tests, and swift-format lint on the Swift files changed from main.
# Usage: scripts/check.sh [--all]   (--all lints every Swift file, not only the changed ones)
set -euo pipefail
cd "$(dirname "$0")/.."

echo "› Build"
swift build -c release

echo "› Test"
swift test

echo "› Lint"
if [[ "${1:-}" == "--all" ]]; then
  files=(Sources/**/*.swift Tests/**/*.swift)
else
  base=$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || echo HEAD)
  files=(${(f)"$( { git diff --name-only --diff-filter=ACMR "$base" -- '*.swift'; git ls-files --others --exclude-standard -- '*.swift'; } | sort -u)"})
fi
if (( ${#files} == 0 )); then
  echo "No changed Swift files."
else
  # Warnings only, as in CI. The existing code isn't fully formatted yet; please don't reformat whole files.
  swift format lint --configuration .swift-format "${files[@]}" || true
fi
echo "✓ Done"
