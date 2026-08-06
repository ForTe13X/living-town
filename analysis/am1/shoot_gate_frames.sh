#!/usr/bin/env bash
# shoot_gate_frames.sh — 渲染 AM1·2F 门要判的三帧到 <out>（docker，与 visual_gate 同镜像/参数）。
#   vg_int_cafe.png       cafe 1f（1F 参照，= 现役壳门那张的同参数复刻）
#   vg_cafe2f.png         cafe 2f（被判的 2F 帧）
#   vg_cafe2f_bare.png    cafe 2f + --draw-skip interior_furniture（真渲染负对照：家具被跳掉）
# 参数与 visual_gate.sh 一致：seed3、NOON_TICK=600、--shot-fit。用法：bash shoot_gate_frames.sh <out_win>
set -uo pipefail
OUT_WIN="$1"
REPO="$(cd "$(dirname "$0")/../.." && pwd -W)"
GAME_WIN="$REPO/game"
MSYS_NO_PATHCONV=1 docker run --rm -v "$GAME_WIN:/game" -v "$OUT_WIN:/out" gamecraft-runner:4.6.2 bash -c '
set -e
Xvfb :96 -screen 0 1280x768x24 -nolisten tcp >/tmp/xvfb.log 2>&1 & sleep 1.6
export DISPLAY=:96 LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 GODOT_SILENCE_ROOT_WARNING=1
shot(){ # shot <outfile> <extra args...>
  local o="$1"; shift
  godot --path /game --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
    --resolution 1280x768 --single-window -- --backend logic --seed 3 --warmup-tick 600 --shot-fit \
    --shot "$o" "$@" >>/tmp/shot.log 2>&1 || { echo "FAIL $o"; tail -20 /tmp/shot.log; exit 1; }
  [ -s "$o" ] && echo "ok $(basename "$o")" || { echo "empty $o"; exit 1; }
}
shot /out/vg_int_cafe.png    --probe-space cafe --probe-floor 1f
shot /out/vg_cafe2f.png      --probe-space cafe --probe-floor 2f
shot /out/vg_cafe2f_bare.png --probe-space cafe --probe-floor 2f --draw-skip interior_furniture
'
