#!/bin/zsh
# Builds a signed, notarized Takes-<version>.dmg, its Sparkle update feed (appcast.xml),
# a checksum and the release notes, all in ./dist.
#
#   scripts/release.sh             sign with your Developer ID, notarize, sign the update
#   scripts/release.sh --unsigned  run the same steps without signing, to test the pipeline
#
# Credentials. GitHub Actions passes environment variables; on your Mac the keychain is used:
#   SIGN_ID                              Developer ID identity (default: the first "Developer ID Application" found)
#   NOTARY_KEY_PATH, NOTARY_KEY_ID,      App Store Connect API key for notarization (CI)
#   NOTARY_ISSUER
#   NOTARY_PROFILE                       notarytool keychain profile (local; default "takes-notary")
#   SPARKLE_KEY_FILE                     Sparkle EdDSA private key file (CI); locally the keychain account "takes"
set -euo pipefail
cd "$(dirname "$0")/.."

UNSIGNED=false
[[ "${1:-}" == "--unsigned" ]] && UNSIGNED=true
VERSION=$(cat VERSION)
TAG=v$VERSION
REPO_URL=https://github.com/bar-amir/takes
NOTARY_PROFILE=${NOTARY_PROFILE:-takes-notary}
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin
DIST=dist
APP=$DIST/Takes.app
DMG=$DIST/Takes-$VERSION.dmg
step() { print -P "\n%B==> $1%b" }

scripts/release-notes.sh "$VERSION" >/dev/null

if $UNSIGNED; then
  SIGN_ID=-
else
  SIGN_ID=${SIGN_ID:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')}
  [[ -n "$SIGN_ID" ]] || { print "No \"Developer ID Application\" certificate found."; exit 1 }
  if [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
    NOTARY_ARGS=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
  else
    NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
  fi
  xcrun notarytool history "${NOTARY_ARGS[@]}" >/dev/null 2>&1 || { print "Notarization credentials don't work (profile \"$NOTARY_PROFILE\" or API key)."; exit 1 }
  if [[ -n "${SPARKLE_KEY_FILE:-}" ]]; then
    SPARKLE_ARGS=(--ed-key-file "$SPARKLE_KEY_FILE")
  else
    SPARKLE_ARGS=(--account takes)
  fi
  [[ -z "$(git status --porcelain)" ]] || { print "There are uncommitted changes. Commit them first, so the release matches the repository."; exit 1 }
  print "Signing as: $SIGN_ID"
fi

step "Build $VERSION for Apple silicon and Intel"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
rm -rf "$DIST" && mkdir -p "$DIST"
RELEASE=1 scripts/assemble-app.sh "$BIN_DIR/Takes" "$APP" "$(git rev-list --count HEAD)"
lipo -archs "$APP/Contents/MacOS/Takes"

notarize() {
  $UNSIGNED && { print "(skipped: unsigned)"; return }
  xcrun notarytool submit "$1" "${NOTARY_ARGS[@]}" --wait --timeout 30m
}

step "Sign the app (Sparkle inside out, hardened runtime)"
scripts/sign-app.sh "$APP" "$SIGN_ID"

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
if $UNSIGNED; then codesign --force --sign - "$DMG"; else codesign --force --sign "$SIGN_ID" --timestamp "$DMG"; fi

step "Notarize the disk image"
notarize "$DMG"
$UNSIGNED || xcrun stapler staple "$DMG"

step "Release notes, checksum and update feed"
scripts/release-notes.sh "$VERSION" > "$DIST/release-notes.md"
(cd "$DIST" && shasum -a 256 "Takes-$VERSION.dmg" > "Takes-$VERSION.dmg.sha256")
if $UNSIGNED; then
  print "(update feed skipped: unsigned)"
else
  FEED=$(mktemp -d)
  cp "$DMG" "$FEED/"
  scripts/release-notes.sh "$VERSION" --html > "$FEED/Takes-$VERSION.html"
  "$SPARKLE_BIN/generate_appcast" "${SPARKLE_ARGS[@]}" \
    --download-url-prefix "$REPO_URL/releases/download/$TAG/" \
    --full-release-notes-url "$REPO_URL/releases/tag/$TAG" \
    --link "$REPO_URL" --embed-release-notes \
    -o "$DIST/appcast.xml" "$FEED"
  rm -rf "$FEED"
  grep -q 'sparkle:edSignature' "$DIST/appcast.xml" || { print "The update feed isn't signed."; exit 1 }
fi

step "Check what macOS will think of it"
if $UNSIGNED; then
  print "Unsigned build: Gatekeeper will block it on other Macs. Use it only to test the pipeline."
else
  spctl --assess --type execute --verbose=2 "$APP"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  xcrun stapler validate "$DMG"
fi

print "\nDone: $(ls $DIST)"
cat "$DIST/Takes-$VERSION.dmg.sha256"
