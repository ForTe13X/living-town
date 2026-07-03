#!/usr/bin/env bash
# observe-shoot.sh — 在容器内启动 Main 场景，用 xdotool 注入输入验证观察台/回放交互，逐步截图。
# 用法（容器内）: bash /tools/observe-shoot.sh [seed=20260626] [outdir=/out]
set -uo pipefail
SEED="${1:-20260626}"; OUT="${2:-/out}"
W=1280; H=768; DISP=:78
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 GODOT_SILENCE_ROOT_WARNING=1

Xvfb $DISP -screen 0 ${W}x${H}x24 -nolisten tcp >/tmp/xvfb.log 2>&1 & XV=$!
sleep 1.2
export DISPLAY=$DISP
godot --path /game --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
  --resolution ${W}x${H} --single-window -- --seed "$SEED" --speed 4.0 >/tmp/godot.log 2>&1 & GD=$!
sleep 3
WID=$(xdotool search --onlyvisible --pid $GD 2>/dev/null | tail -1)
[ -z "${WID:-}" ] && WID=$(xdotool search --name ".*" 2>/dev/null | tail -1)
xdotool windowfocus --sync "$WID" 2>/dev/null || true
grab(){ ffmpeg -y -f x11grab -video_size ${W}x${H} -i $DISP -frames:v 1 "$1" >/dev/null 2>&1; }

sleep 5                                   # 让小镇先跑出一些关系/冲突
xdotool key --window "$WID" space; sleep 0.3      # 暂停
xdotool key --window "$WID" Tab;   sleep 0.4      # 选第 1 个居民
grab "$OUT/obs_select.png"
xdotool key --window "$WID" Tab;   sleep 0.4      # 切下一个
grab "$OUT/obs_select2.png"
xdotool key --window "$WID" bracketleft; sleep 0.5  # 时间轴回跳一天（确定性重演）
grab "$OUT/obs_scrub_back.png"
xdotool key --window "$WID" 3; sleep 0.2          # 恢复 ×4 速度
grab "$OUT/obs_resume.png"

kill $GD $XV 2>/dev/null || true
echo "--- godot errors? ---"; grep -iE 'SCRIPT ERROR|Parse Error' /tmp/godot.log | head -8 || echo none
echo done; ls -la "$OUT"/obs_*.png
