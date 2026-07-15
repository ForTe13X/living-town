#!/usr/bin/env bash
# shot1.sh — 容器内渲【一帧】存 png（美术迭代快环；比 record+extract 快一个量级）。
# 用法（容器内）：bash /tools/shot1.sh /out/x.png [seed=20260626] [warmup_days=3] [speed=1.0]
# 宿主：docker run --rm -v .../game:/game -v <out>:/out -v .../tools:/tools gamecraft-runner:4.6.2 bash /tools/shot1.sh /out/x.png
set -uo pipefail
OUT="${1:-/out/shot.png}"; SEED="${2:-20260626}"; WARM="${3:-3}"; SPEED="${4:-1.0}"
W=1280; H=768; DISP=:90
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 GODOT_SILENCE_ROOT_WARNING=1
Xvfb $DISP -screen 0 ${W}x${H}x24 -nolisten tcp >/tmp/xvfb.log 2>&1 & XV=$!
sleep 1.2
export DISPLAY=$DISP
godot --path /game --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
  --resolution ${W}x${H} --single-window -- \
  --seed "$SEED" --speed "$SPEED" --warmup "$WARM" --backend logic --shot "$OUT" >/tmp/godot.log 2>&1
RC=$?
kill $XV 2>/dev/null
if [ -f "$OUT" ]; then echo "shot ok: $OUT"; else echo "shot FAIL rc=$RC"; tail -20 /tmp/godot.log; fi
