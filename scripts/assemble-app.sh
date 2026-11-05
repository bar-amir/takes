#!/bin/zsh
# Wraps a built Takes binary into Takes.app, with Sparkle.framework embedded.
# Usage: scripts/assemble-app.sh <binary> <output .app> [build number]
# RELEASE=1 adds the update feed and public key, so only release builds check for updates.
set -euo pipefail
cd "$(dirname "$0")/.."

BINARY=$1
APP=$2
VERSION=$(cat VERSION)
BUILD=${3:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Takes"

# Sparkle.framework sits next to the binary (single-arch builds) or in PackageFrameworks (universal builds).
BIN_DIR=$(dirname "$BINARY")
FRAMEWORK=$BIN_DIR/Sparkle.framework
[[ -d "$FRAMEWORK" ]] || FRAMEWORK=$BIN_DIR/PackageFrameworks/Sparkle.framework
mkdir -p "$APP/Contents/Frameworks"
ditto "$FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
# Takes isn't sandboxed, so Sparkle's XPC services aren't needed (Sparkle's docs allow removing them).
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"

SPARKLE_KEYS=""
if [[ "${RELEASE:-0}" == "1" ]]; then
  # SURequireSignedFeed: the appcast itself must carry a valid EdDSA signature, so a tampered feed (release notes,
  # versions) is refused, not only a tampered download. generate_appcast signs it because of this key.
  # SUVerifyUpdateBeforeExtraction: the download's signature is checked before the disk image is opened.
  SPARKLE_KEYS="  <key>SUFeedURL</key><string>https://github.com/bar-amir/takes/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>$(cat Resources/SUPublicEDKey)</string>
  <key>SURequireSignedFeed</key><true/>
  <key>SUVerifyUpdateBeforeExtraction</key><true/>"
fi
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp THIRD-PARTY-NOTICES.md "$APP/Contents/Resources/THIRD-PARTY-NOTICES.md"
# Mono label font (JetBrains Mono, SIL OFL 1.1; license travels with it) and the onboarding opening photo.
[[ -d Resources/Fonts ]] && ditto Resources/Fonts "$APP/Contents/Resources/Fonts"
[[ -d Resources/Onboarding ]] && ditto Resources/Onboarding "$APP/Contents/Resources/Onboarding"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.baramir.takes</string>
  <key>CFBundleName</key><string>Takes</string>
  <key>CFBundleDisplayName</key><string>Takes</string>
  <key>CFBundleExecutable</key><string>Takes</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 Bar Amir. MIT License.</string>
  <key>NSMicrophoneUsageDescription</key><string>Takes listens only while you dictate a draft (⌘D in the panel). Your speech is turned into text on this Mac and the audio never leaves it.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Takes turns your dictated draft into text on this Mac, using on-device speech recognition only. Nothing is sent to Apple or anyone else.</string>
$SPARKLE_KEYS
</dict>
</plist>
PLIST
