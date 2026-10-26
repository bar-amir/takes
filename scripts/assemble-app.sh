#!/bin/zsh
# Wraps a built Takes binary into Takes.app.
# Usage: scripts/assemble-app.sh <binary> <output .app> [build number]
set -euo pipefail
cd "$(dirname "$0")/.."

BINARY=$1
APP=$2
VERSION=$(cat VERSION)
BUILD=${3:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Takes"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

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
</dict>
</plist>
PLIST
