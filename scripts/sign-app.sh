#!/bin/zsh
# Signs Takes.app inside out (Sparkle's nested code first, never --deep), with hardened runtime.
# Usage: scripts/sign-app.sh <app> <signing identity>
set -euo pipefail
APP=$1
IDENTITY=$2
FW=$APP/Contents/Frameworks/Sparkle.framework

sign() {
  if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --sign - --options runtime "$@"   # ad-hoc, for testing the pipeline
  else
    codesign --force --sign "$IDENTITY" --options runtime --timestamp "$@"
  fi
}

if [[ -d "$FW" ]]; then
  sign "$FW/Versions/B/Autoupdate"
  sign "$FW/Versions/B/Updater.app"
  sign "$FW"
fi
sign --identifier com.baramir.takes "$APP"
codesign --verify --strict --verbose=2 "$APP"
