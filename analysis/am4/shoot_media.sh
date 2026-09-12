#!/usr/bin/env bash
# shoot_media.sh — AM4 一次性媒体渲染（docker gamecraft-runner，Xvfb+opengl3 软渲，与 visual_gate 同镜像）。
# 用法（host，Git Bash）：  bash analysis/am4/shoot_media.sh <out_dir_hostwin> <tag> [game_dir_hostwin]
#   在 <out_dir> 落 home_1f_<tag>.png / home2_1f_<tag>.png / library_1f_<tag>.png / wash_1f_<tag>.png
#   （真引擎 --shot，红线 R2：非生成图）。game_dir 可指向别的一棵 game/（拍 before：给未改动树的 game/）。默认本仓库 game/。
# 参数与 visual_gate.sh 一致：seed3、NOON_TICK=600、--shot-fit（整室入画）。
set -uo pipefail
OUT_WIN="$1"; TAG="$2"
REPO="$(cd "$(dirname "$0")/../.." && pwd -W)"
GAME_WIN="${3:-$REPO/game}"
IMG="gamecraft-runner:4.6.2"
MSYS_NO_PATHCONV=1 docker run --rm \
  -v "$GAME_WIN:/game" -v "$OUT_WIN:/out" "$IMG" bash -c '
set -e
Xvfb :96 -screen 0 1280x768x24 -nolisten tcp >/tmp/xvfb.log 2>&1 & sleep 1.6
export DISPLAY=:96 LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 GODOT_SILENCE_ROOT_WARNING=1
for sid in home home2 library wash; do
  godot --path /game --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
    --resolution 1280x768 --single-window -- \
    --backend logic --shot "/out/${sid}_1f_'"$TAG"'.png" --seed 3 --warmup-tick 600 \
    --probe-space "$sid" --probe-floor 1f --shot-fit >>/tmp/shot.log 2>&1 || { echo "FAIL $sid"; tail -20 /tmp/shot.log; exit 1; }
  [ -s "/out/${sid}_1f_'"$TAG"'.png" ] && echo "ok ${sid}_1f_'"$TAG"'.png" || { echo "empty $sid"; exit 1; }
done
'
