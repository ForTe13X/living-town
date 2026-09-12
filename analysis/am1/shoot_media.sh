#!/usr/bin/env bash
# shoot_media.sh — AM1 一次性媒体渲染（docker gamecraft-runner，Xvfb+opengl3 软渲，与 visual_gate 同镜像）。
# 用法（host，Git Bash）：  bash analysis/am1/shoot_media.sh <out_dir_hostwin> <tag>
#   在 <out_dir> 落 cafe_1f_<tag>.png / cafe_2f_<tag>.png（真引擎 --shot，红线 R2：非生成图）。
# 参数经 docker mount：GAME=/game, OUT=/out。seed3 正午 tick600，--shot-fit 整室入画。
set -uo pipefail
OUT_WIN="$1"; TAG="$2"
REPO="$(cd "$(dirname "$0")/../.." && pwd -W)"
GAME_WIN="$REPO/game"
IMG="gamecraft-runner:4.6.2"
MSYS_NO_PATHCONV=1 docker run --rm \
  -v "$GAME_WIN:/game" -v "$OUT_WIN:/out" "$IMG" bash -c '
set -e
Xvfb :95 -screen 0 1280x768x24 -nolisten tcp >/tmp/xvfb.log 2>&1 & sleep 1.6
export DISPLAY=:95 LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 GODOT_SILENCE_ROOT_WARNING=1
for fl in 1f 2f; do
  godot --path /game --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
    --resolution 1280x768 --single-window -- \
    --backend logic --shot "/out/cafe_${fl}_'"$TAG"'.png" --seed 3 --warmup-tick 600 \
    --probe-space cafe --probe-floor "$fl" --shot-fit >>/tmp/shot.log 2>&1 || { echo "FAIL $fl"; tail -20 /tmp/shot.log; exit 1; }
  [ -s "/out/cafe_${fl}_'"$TAG"'.png" ] && echo "ok cafe_${fl}_'"$TAG"'.png" || { echo "empty $fl"; exit 1; }
done
'
