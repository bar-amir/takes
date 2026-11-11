#!/bin/zsh
# Development build: Takes.app in ./build, ad-hoc signed. For a signed, notarized release use scripts/release.sh.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/Takes.app
scripts/assemble-app.sh .build/release/Takes "$APP"
# Ad-hoc signing normally ties macOS permissions (Accessibility) to this exact build. A designated requirement on
# the bundle ID keeps the permission across rebuilds. The trade-off: any ad-hoc binary with that identifier meets
# the requirement, so the permission isn't tied to a key only you hold.
# With a signing identity of your own, set TAKES_SIGN_IDENTITY (a name from `security find-identity -v -p codesigning`)
# and the permission follows that certificate instead:
#   TAKES_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./build.sh
# A build signed that way carries a team identifier, so `--bench` refuses to run in it, as in a release.
if [[ -n "${TAKES_SIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$TAKES_SIGN_IDENTITY" --identifier com.baramir.takes "$APP"
else
  codesign --force --sign - --identifier com.baramir.takes \
    -r='designated => identifier "com.baramir.takes"' "$APP"
fi
echo "Built $APP"
