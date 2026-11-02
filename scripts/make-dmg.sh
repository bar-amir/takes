#!/bin/zsh
# make-dmg.sh <Takes.app> <out.dmg> <volume name>
# Builds the install disk image: the foil t sticker as the disk's icon, and a window with
# the branded background, Takes on the left and Applications on the right.
# The window layout is set through Finder; if Finder can't be scripted (no Automation
# permission), the image is still built, just without the layout.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=$1 DMG=$2 VOLNAME=$3

WORK=$(mktemp -d)
MOUNT=
cleanup() {
  [[ -n "$MOUNT" ]] && hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

STAGING=$WORK/staging
mkdir -p "$STAGING/.background"
ditto "$APP" "$STAGING/Takes.app"
ln -s /Applications "$STAGING/Applications"
cp Resources/dmg/background.tiff "$STAGING/.background/background.tiff"

hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg" >/dev/null
MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$WORK/rw.dmg" | grep -o '/Volumes/.*$')

if ! osascript scripts/dmg-layout.applescript "$(basename "$MOUNT")" 2>"$WORK/osascript.log"; then
  print "warning: couldn't lay out the disk image window through Finder; building it without the layout."
  cat "$WORK/osascript.log"
fi
# The disk's icon, with FinderInfo's kHasCustomIcon flag. It goes in last: hdiutil leaves
# .VolumeIcon.icns out of -srcfolder, and Finder's layout pass drops it.
cp Resources/dmg/VolumeIcon.icns "$MOUNT/.VolumeIcon.icns"
if xcrun --find SetFile >/dev/null 2>&1; then
  xcrun SetFile -a C "$MOUNT"
else
  xattr -wx com.apple.FinderInfo "0000000000000000040000000000000000000000000000000000000000000000" "$MOUNT"
fi

chmod -Rf go-w "$MOUNT" || true
sync
hdiutil detach "$MOUNT" >/dev/null
MOUNT=
hdiutil convert "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null
