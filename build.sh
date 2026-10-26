#!/bin/zsh
# Development build: Takes.app in ./build, ad-hoc signed. For a signed, notarized release use scripts/release.sh.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/Takes.app
scripts/assemble-app.sh .build/release/Takes "$APP"
# Ad-hoc signing normally ties macOS permissions (Accessibility) to this exact build.
# A designated requirement on the bundle ID keeps the permission across rebuilds.
codesign --force --sign - --identifier com.baramir.takes \
  -r='designated => identifier "com.baramir.takes"' "$APP"
echo "Built $APP"
