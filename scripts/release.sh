#!/bin/zsh
# Builds a signed, notarized Takes-<version>.dmg in ./dist.
#
#   scripts/release.sh            sign with your Developer ID and notarize
#   scripts/release.sh --unsigned package without signing, to test the pipeline
#
# Needs, once per Mac:
#   - a "Developer ID Application" certificate in your keychain (Xcode › Settings › Accounts › Manage Certificates)
#   - notarization credentials saved as a keychain profile:
#       xcrun notarytool store-credentials "takes-notary" --apple-id <apple id> --team-id <team id>
# Override with SIGN_ID="Developer ID Application: …" and NOTARY_PROFILE=… if needed.
set -euo pipefail
cd "$(dirname "$0")/.."

UNSIGNED=false
[[ "${1:-}" == "--unsigned" ]] && UNSIGNED=true
VERSION=$(cat VERSION)
NOTARY_PROFILE=${NOTARY_PROFILE:-takes-notary}
DIST=dist
APP=$DIST/Takes.app
DMG=$DIST/Takes-$VERSION.dmg
step() { print -P "\n%B==> $1%b" }

if ! $UNSIGNED; then
  SIGN_ID=${SIGN_ID:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')}
  if [[ -z "$SIGN_ID" ]]; then
    print "No \"Developer ID Application\" certificate found in your keychain. Create one in Xcode › Settings › Accounts › Manage Certificates."
    exit 1
  fi
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    print "No notarization credentials saved as \"$NOTARY_PROFILE\". Run: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <apple id> --team-id <team id>"
    exit 1
  fi
  if [[ -n "$(git status --porcelain)" ]]; then
    print "There are uncommitted changes. Commit them first, so the release matches the repository."
    exit 1
  fi
  print "Signing as: $SIGN_ID"
fi

step "Build $VERSION for Apple silicon and Intel"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
rm -rf "$DIST" && mkdir -p "$DIST"
scripts/assemble-app.sh "$BIN_DIR/Takes" "$APP"
lipo -archs "$APP/Contents/MacOS/Takes"

sign() {
  if $UNSIGNED; then
    codesign --force --sign - "$@"
  else
    codesign --force --sign "$SIGN_ID" --timestamp "$@"
  fi
}

notarize() {
  $UNSIGNED && { print "(skipped: unsigned)"; return; }
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m
}

step "Sign the app (hardened runtime)"
sign --options runtime --identifier com.baramir.takes "$APP"
codesign --verify --strict --verbose=2 "$APP"

step "Notarize the app"
ditto -c -k --keepParent "$APP" "$DIST/Takes-notarize.zip"
notarize "$DIST/Takes-notarize.zip"
rm "$DIST/Takes-notarize.zip"
$UNSIGNED || xcrun stapler staple "$APP"

step "Build the disk image"
STAGING=$(mktemp -d)
ditto "$APP" "$STAGING/Takes.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Takes $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGING"
sign "$DMG"

step "Notarize the disk image"
notarize "$DMG"
$UNSIGNED || xcrun stapler staple "$DMG"

step "Check what macOS will think of it"
if $UNSIGNED; then
  print "Unsigned build: Gatekeeper will block it on other Macs. Use it only to test the pipeline."
else
  spctl --assess --type execute --verbose=2 "$APP"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

print "\nDone: $DMG"
shasum -a 256 "$DMG"
