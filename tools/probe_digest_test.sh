#!/usr/bin/env bash
# probe_digest_test.sh — Probe【观察者无关性】硬门（analysis §10.1 / P0-a Gate）。
# 同 seed、同单步步数：A 全程不碰相机，B 狂拖狂缩 + 捏合。两边 (tick,digest,event_digest) 必须逐字节相同。
# 关键：--speed 0 → 仿真不自走，只有注入的 '.' 单步推进 → 两跑 tick 数严格相同，
#       否则实时 tick 数受墙钟影响，会拿"跑得多/少"冒充"相机影响了历史"。
# 用法（容器内）：bash /tools/probe_digest_test.sh /out [seed]
set -uo pipefail
OUT="${1:-/out}"; SEED="${2:-20260626}"; STEPS=60; TARGET=520   # 多按几次无所谓：app 在 TARGET tick 自动写盘
W=1280; H=768
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 GODOT_SILENCE_ROOT_WARNING=1

run() {  # $1=digest file   $2=1 表示狂拖狂缩
  local FILE="$1" CAM="$2" DISP=":9$3"
  Xvfb $DISP -screen 0 ${W}x${H}x24 -nolisten tcp >/tmp/xvfb$3.log 2>&1 & local XV=$!
  sleep 1.2
  DISPLAY=$DISP godot --path /game --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
    --resolution ${W}x${H} --single-window -- --seed "$SEED" --warmup 3 --speed 0 --backend logic \
    --digest-out "$FILE" --digest-at "$TARGET" >/tmp/godot$3.log 2>&1 & local GD=$!
  sleep 14
  export DISPLAY=$DISP
  local WID=$(xdotool search --onlyvisible --pid $GD 2>/dev/null | tail -1)
  [ -z "${WID:-}" ] && WID=$(xdotool search --name ".*" 2>/dev/null | tail -1)
  xdotool windowfocus --sync "$WID" 2>/dev/null || true
  xdotool key --window "$WID" space; sleep 0.4            # 确保 running=false（speed 0 本就不自走）
  if [ "$CAM" = "1" ]; then                              # 拖 + 缩（观察者动作）
    xdotool mousemove 420 300; xdotool mousedown 1
    for i in 1 2 3 4 5 6 7 8; do xdotool mousemove $((420 + i*40)) $((300 + i*18)); sleep 0.04; done
    xdotool mouseup 1
    for k in 1 2 3; do xdotool key --window "$WID" plus; sleep 0.05; done
  fi
  for i in $(seq 1 $STEPS); do xdotool key --window "$WID" period; done   # 确定性单步
  sleep 0.5
  if [ "$CAM" = "1" ]; then                              # 步进后再动一次相机
    xdotool mousemove 700 500; xdotool mousedown 1
    for i in 1 2 3 4 5; do xdotool mousemove $((700 - i*35)) $((500 - i*22)); sleep 0.04; done
    xdotool mouseup 1
    for k in 1 2; do xdotool key --window "$WID" minus; sleep 0.05; done
  fi
  sleep 1.2                                              # app 到 TARGET tick 已自动写盘并退出
  kill $GD $XV 2>/dev/null; sleep 0.5
}

run "$OUT/digest_nocam.txt" 0 3
run "$OUT/digest_cam.txt"   1 4

echo "--- A (no camera) : $(cat "$OUT/digest_nocam.txt" 2>/dev/null || echo MISSING)"
echo "--- B (pan+zoom)  : $(cat "$OUT/digest_cam.txt"  2>/dev/null || echo MISSING)"
if [ -s "$OUT/digest_nocam.txt" ] && [ -s "$OUT/digest_cam.txt" ] && \
   [ "$(cat "$OUT/digest_nocam.txt")" = "$(cat "$OUT/digest_cam.txt")" ]; then
  echo "PROBE OBSERVER-INDEPENDENCE: PASS ✅  (相机操作未改变 tick/digest/event_digest)"
  exit 0
fi
echo "PROBE OBSERVER-INDEPENDENCE: FAIL ❌  (相机影响了 Sim 历史 → 回放红线破)"
exit 1
