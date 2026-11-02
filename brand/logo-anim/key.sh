#!/bin/sh
# key.sh <in.mp4> <out-basename> <key-hex> : green screen -> transparent WebM (VP9 alpha) + HEVC-alpha MOV for Safari.
# SS/TO=<seconds> trim the still opening and ending, so a hover always meets a moving clip.
ss=${SS:-0}; to=${TO:+-to $TO}; in="$1"; out="$2"; k="$3"; size=${SIZE:-432}
key="chromakey=0x$k:${SIM:-0.14}:${BLEND:-0.05},despill=type=green:mix=0.7,scale=${size}:${size}:flags=lanczos"
ffmpeg -y -loglevel error -ss "$ss" $to -i "$in" -an -vf "$key,format=yuva420p" -c:v libvpx-vp9 -pix_fmt yuva420p -b:v 0 -crf 34 -row-mt 1 -auto-alt-ref 0 "$out.webm"
ffmpeg -y -loglevel error -ss "$ss" $to -i "$in" -an -vf "$key,format=bgra" -c:v hevc_videotoolbox -allow_sw 1 -alpha_quality 0.8 -q:v 55 -tag:v hvc1 "$out.mov"
