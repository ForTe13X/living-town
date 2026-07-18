#!/usr/bin/env bash
# shot_tick.sh — 渲【精确 tick】一帧存 png（眼验某一瞬社交事件）。容器内用。
# 用法: shot_tick.sh <out.png> [seed=1] [tick=1122] [speed=1.0] [select_id]
set -uo pipefail
OUT="${1:-/out/shot.png}"; SEED="${2:-1}"; TICK="${3:-1122}"; SPEED="${4:-1.0}"; SEL="${5:-}"
W=1280; H=768; DISP=:91
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 GODOT_SILENCE_ROOT_WARNING=1
SEL_ARG=""; [ -n "$SEL" ] && SEL_ARG="--select $SEL"
Xvfb $DISP -screen 0 ${W}x${H}x24 -nolisten tcp >/tmp/xvfb.log 2>&1 & XV=$!
sleep 1.2
export DISPLAY=$DISP
godot --path /game --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
  --resolution ${W}x${H} --single-window -- \
  --seed "$SEED" --speed "$SPEED" --warmup-tick "$TICK" $SEL_ARG --backend logic --shot "$OUT" >/tmp/godot.log 2>&1
RC=$?
kill $XV 2>/dev/null
if [ -f "$OUT" ]; then echo "shot ok: $OUT"; else echo "shot FAIL rc=$RC"; tail -25 /tmp/godot.log; fi
