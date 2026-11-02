#!/bin/zsh
# Rebuilds Resources/AppIcon.icns and brand/app-icon-1024.png from brand/app-icon.svg.
# 16 and 32 px use brand/app-icon-16.svg, which has one bolder wave so it stays readable.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
swiftc -O scripts/svg2png.swift -o "$WORK/svg2png"
SET=$WORK/AppIcon.iconset
mkdir "$SET"
for spec in 16:icon_16x16:-16 32:icon_16x16@2x:-16 32:icon_32x32:-16 64:icon_32x32@2x: 128:icon_128x128: \
            256:icon_128x128@2x: 256:icon_256x256: 512:icon_256x256@2x: 512:icon_512x512: 1024:icon_512x512@2x:; do
  IFS=: read px name suffix <<< "$spec"
  "$WORK/svg2png" "brand/app-icon$suffix.svg" "$SET/$name.png" "$px"
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
cp "$SET/icon_512x512@2x.png" brand/app-icon-1024.png
print "Wrote Resources/AppIcon.icns"
