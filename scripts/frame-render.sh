#!/bin/bash
# Post-processes a transparent Higgsfield render for the site (see brand/campaign/HIGGSFIELD-KIT.md).
#   scripts/frame-render.sh slide <render.png> <out.webp>  carousel slide: centred in the right 55% of a 1600 x 900 frame
#   scripts/frame-render.sh part  <render.png> <out.webp>  takes-panel sprite: cropped tight, at most 1400 px wide
# Both drop the faint light haze the model sometimes leaves around objects (light pixels with low alpha) and crop
# to what is visible. Needs ffmpeg and cwebp.
set -euo pipefail
mode=$1; in=$2; out=$3; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
ffmpeg -loglevel error -y -i "$in" -vf "format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='if(lt(alpha(X,Y),150)*gt(0.3*r(X,Y)+0.59*g(X,Y)+0.11*b(X,Y),170),0,alpha(X,Y))'" "$t/clean.png"
crop=$(ffmpeg -i "$t/clean.png" -vf "alphaextract,cropdetect=limit=1:round=2:skip=0:reset=0" -frames:v 1 -f null - 2>&1 | grep -o 'crop=[0-9:]*' | tail -1)
if [ "$mode" = slide ]; then
  ffmpeg -loglevel error -y -i "$t/clean.png" -vf "$crop,scale=w=1760:h=1512:force_original_aspect_ratio=decrease,pad=3200:1800:(2224-iw/2):(900-ih/2):color=0x00000000" "$t/out.png"
  cwebp -quiet -q 86 -alpha_q 100 -m 6 -resize 1600 0 "$t/out.png" -o "$out"
else
  ffmpeg -loglevel error -y -i "$t/clean.png" -vf "$crop" "$t/out.png"
  w=$(ffprobe -v error -show_entries stream=width -of csv=p=0 "$t/out.png"); [ "$w" -gt 1400 ] && w=1400
  cwebp -quiet -q 88 -alpha_q 100 -m 6 -resize "$w" 0 "$t/out.png" -o "$out"
fi
echo "$out"
