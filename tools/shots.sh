#!/usr/bin/env bash
# 从录屏抽取若干截图。用法：bash /tools/shots.sh /out/town_raw.mp4 /out
set -uo pipefail
SRC="${1:-/out/town_raw.mp4}"; DIR="${2:-/out}"
for ts in 12 28 45 65 85 105 125 145; do
  ffmpeg -y -ss "$ts" -i "$SRC" -frames:v 1 "$DIR/shot_${ts}s.png" >/dev/null 2>&1 && echo "shot ${ts}s ok" || echo "shot ${ts}s FAIL"
done
ls -la "$DIR"/shot_*.png | awk '{print $5, $9}'
