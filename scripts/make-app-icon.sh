#!/bin/zsh
# Rebuilds the icons and disk-image artwork from the masters in brand/:
#   Resources/AppIcon.icns, brand/app-icon-1024.png   app icon: the holographic (Night edition) t on an Ink tile,
#                                                      drawn by scripts/render-foil.swift; 16 and 32 px use a bigger mark
#   Resources/dmg/VolumeIcon.icns                      the mounted disk's icon: the holographic t sticker
#   Resources/dmg/background.tiff                      the install window (1x and 2x)
#   site/favicon.ico, site/apple-touch-icon.png        favicon fallbacks for browsers without SVG favicons
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
swiftc -O scripts/svg2png.swift -o "$WORK/svg2png"
swiftc -O scripts/render-foil.swift -o "$WORK/render-foil"
swiftc -O scripts/dmg-background.swift -o "$WORK/dmg-background"

iconset() { # iconset <name> <app|sticker>
  local set=$WORK/$1.iconset
  mkdir "$set"
  for spec in 16:icon_16x16:small 32:icon_16x16@2x:small 32:icon_32x32:small 64:icon_32x32@2x: 128:icon_128x128: \
              256:icon_128x128@2x: 256:icon_256x256: 512:icon_256x256@2x: 512:icon_512x512: 1024:icon_512x512@2x:; do
    IFS=: read px name small <<< "$spec"
    "$WORK/render-foil" $2 "$px" "$set/$name.png" $small
  done
}

iconset AppIcon app
iconutil -c icns "$WORK/AppIcon.iconset" -o Resources/AppIcon.icns
cp "$WORK/AppIcon.iconset/icon_512x512@2x.png" brand/app-icon-1024.png

mkdir -p Resources/dmg
iconset VolumeIcon sticker
iconutil -c icns "$WORK/VolumeIcon.iconset" -o Resources/dmg/VolumeIcon.icns
"$WORK/dmg-background" "$WORK/background.png" 1
"$WORK/dmg-background" "$WORK/background@2x.png" 2
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out Resources/dmg/background.tiff 2>/dev/null

# favicon.ico holds 16, 32 and 48 px PNGs; the small sizes use the heavier rim.
for px in 16 32 48; do "$WORK/svg2png" brand/t-mark-small.svg "$WORK/fav-$px.png" $px; done
python3 -I - "$WORK" site/favicon.ico <<'PY'
import struct, sys
work, out = sys.argv[1], sys.argv[2]
images = [(px, open(f"{work}/fav-{px}.png", "rb").read()) for px in (16, 32, 48)]
header = struct.pack("<HHH", 0, 1, len(images))
offset, entries = 6 + 16 * len(images), b""
for px, data in images:
    entries += struct.pack("<BBBBHHII", px, px, 0, 0, 1, 32, len(data), offset)
    offset += len(data)
open(out, "wb").write(header + entries + b"".join(data for _, data in images))
PY
"$WORK/render-foil" app 180 site/apple-touch-icon.png
print "Wrote Resources/AppIcon.icns, Resources/dmg/, site/favicon.ico and site/apple-touch-icon.png"
