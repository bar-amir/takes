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
  scope="Swift files"
else
  base=$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || echo HEAD)
  files=(${(f)"$( { git diff --name-only --diff-filter=ACMR "$base" -- '*.swift'; git ls-files --others --exclude-standard -- '*.swift'; } | sort -u)"})
  scope="changed Swift files"
fi
warnings=0
if (( ${#files} == 0 )); then
  echo "No changed Swift files."
else
  # Style warnings don't fail the check, as in CI: the existing code isn't formatted with swift-format yet
  # (the whole tree had 2,179 warnings in 105 files on 2026-11-10), so failing on them would block every change.
  # Make them fail once `scripts/check.sh --all` reports 0. swift-format itself failing (a file it can't parse,
  # a bad .swift-format) does fail the check, because then nothing was linted.
  lint_status=0
  lint_output=$(swift format lint --configuration .swift-format "${files[@]}" 2>&1) || lint_status=$?
  [[ -z "$lint_output" ]] || print -r -- "$lint_output"
  warnings=$(print -r -- "$lint_output" | grep -c ': warning: ' || true)
  if (( lint_status != 0 )); then
    echo "✗ swift format failed (exit $lint_status), so nothing was linted"
    exit "$lint_status"
  fi
fi
echo "Lint: $warnings warning(s) in ${#files} $scope. Warnings don't fail the check; fix the ones in lines you changed."
echo "✓ Done"
