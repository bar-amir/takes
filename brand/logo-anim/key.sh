#!/bin/sh
# key.sh <in.mp4> <out-basename> <key-hex> : green screen -> transparent WebM (VP9 alpha) + HEVC-alpha MOV for Safari.
# SS/TO=<seconds> trim the still opening and ending, so a hover always meets a moving clip.
ss=${SS:-0}; to=${TO:+-to $TO}; in="$1"; out="$2"; k="$3"; size=${SIZE:-432}
key="chromakey=0x$k:${SIM:-0.14}:${BLEND:-0.05},despill=type=green:mix=0.7,scale=${size}:${size}:flags=lanczos"
ffmpeg -y -loglevel error -ss "$ss" $to -i "$in" -an -vf "$key,format=yuva420p" -c:v libvpx-vp9 -pix_fmt yuva420p -b:v 0 -crf 34 -row-mt 1 -auto-alt-ref 0 "$out.webm"
# The MOV goes through Apple's own HEVC-with-alpha encoder (scripts/hevc-alpha.swift): ffmpeg's hevc_videotoolbox
# output plays on macOS but iPhone Safari draws a lighter box behind it and shifts the colours.
frames=$(mktemp -d)
ffmpeg -y -loglevel error -c:v libvpx-vp9 -i "$out.webm" -pix_fmt rgba "$frames/f%04d.png"
swift "$(dirname "$0")/../../scripts/hevc-alpha.swift" "$frames" 24 "$out.mov" 0.9
rm -rf "$frames"
