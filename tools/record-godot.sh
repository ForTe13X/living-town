#!/usr/bin/env bash
# record-godot.sh — 在容器内用 Xvfb + opengl3(软件渲染) + ffmpeg x11grab 录制 Main 场景。
# 配方照搬 22nd 的 verifier/replay.py。用法（容器内）：
#   bash /tools/record-godot.sh [秒数=135] [seed=20260626] [speed=3.0] [输出=/out/town_raw.mp4]
set -uo pipefail
SECS="${1:-135}"; SEED="${2:-20260626}"; SPEED="${3:-3.0}"; OUT="${4:-/out/town_raw.mp4}"; BACKEND="${5:-logic}"; ENDPOINT="${6:-}"; SCENARIO="${7:-}"
W=1280; H=768; FPS=30; DISP=:77
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 GODOT_SILENCE_ROOT_WARNING=1
EP_ARG=""; [ -n "$ENDPOINT" ] && EP_ARG="--endpoint $ENDPOINT"   # backend=llm 时连宿主 LM Studio
SC_ARG=""; [ -n "$SCENARIO" ] && SC_ARG="--scenario $SCENARIO"   # S3 定向场景

Xvfb $DISP -screen 0 ${W}x${H}x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
XVFB_PID=$!
sleep 1.5
export DISPLAY=$DISP

godot --path /game --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
  --resolution ${W}x${H} --single-window -- --seed "$SEED" --speed "$SPEED" --backend "$BACKEND" $EP_ARG $SC_ARG >/tmp/godot.log 2>&1 &
GODOT_PID=$!
sleep 3

ffmpeg -y -f x11grab -framerate $FPS -video_size ${W}x${H} -i $DISP -t "$SECS" \
  -c:v libx264 -preset veryfast -pix_fmt yuv420p "$OUT" >/tmp/ffmpeg.log 2>&1
RC=$?

kill $GODOT_PID 2>/dev/null || true
kill $XVFB_PID 2>/dev/null || true
sleep 0.3
if [ $RC -ne 0 ] || [ ! -s "$OUT" ]; then
  echo "RECORD FAILED rc=$RC"; echo "--- godot.log tail ---"; tail -20 /tmp/godot.log; echo "--- ffmpeg.log tail ---"; tail -20 /tmp/ffmpeg.log; exit 1
fi
echo "wrote $OUT"; ls -la "$OUT"
