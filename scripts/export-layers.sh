#!/bin/bash
# Exports the layout frames for the Higgsfield renders (brand/campaign/HIGGSFIELD-KIT.md) from site/js/layers.js:
#   brand/campaign/frames/parts/<part>.png   each part of the takes panel alone, front-on (sprites for the live scene)
#   brand/campaign/frames/slides/<scene>.png each feature scene in its carousel framing (1600 x 900)
# Needs Google Chrome. Serves site/ on a free local port while it runs.
set -euo pipefail
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PORT=${PORT:-8799}; OUT=brand/campaign/frames; PROFILE=$(mktemp -d)
python3 -m http.server "$PORT" -d site >/dev/null 2>&1 & SERVER=$!
trap 'kill $SERVER; rm -rf "$PROFILE"' EXIT
sleep 1
shoot() { # url file w h
  "$CHROME" --headless=new --user-data-dir="$PROFILE/$RANDOM" --use-angle=swiftshader --enable-unsafe-swiftshader --hide-scrollbars \
    --force-device-scale-factor=1 --window-size="$3,$4" --default-background-color=00000000 --virtual-time-budget=8000 \
    --screenshot="$2" "http://localhost:$PORT/layers.html?$1&export=1&w=$3&h=$4" 2>/dev/null
}
mkdir -p "$OUT/parts" "$OUT/slides"
for p in ${PARTS:-base chip draft take1 take2 take3 ring paste}; do shoot "scene=takes&part=$p" "$OUT/parts/$p.png" 1200 1200; done
for s in ${SLIDES:-shortcut presets proofread coach local instant dictation tone languages}; do shoot "scene=$s&shot=1" "$OUT/slides/$s.png" 1600 900; done
echo "frames in $OUT"
