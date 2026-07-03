#!/usr/bin/env bash
# chat-shoot.sh — 验证玩家→NPC 对话（mock 后端）：暂停→Tab 选 NPC→按 C 打招呼→截图看回复气泡+日志。
set -uo pipefail
SEED="${1:-20260626}"; OUT="${2:-/out}"; BACKEND="${3:-mock}"
W=1280; H=768; DISP=:79
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 GODOT_SILENCE_ROOT_WARNING=1
Xvfb $DISP -screen 0 ${W}x${H}x24 -nolisten tcp >/tmp/xvfb.log 2>&1 & XV=$!
sleep 1.2
export DISPLAY=$DISP
godot --path /game --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
  --resolution ${W}x${H} --single-window -- --seed "$SEED" --speed 2.0 --backend "$BACKEND" >/tmp/godot.log 2>&1 & GD=$!
sleep 3
WID=$(xdotool search --onlyvisible --pid $GD 2>/dev/null | tail -1)
[ -z "${WID:-}" ] && WID=$(xdotool search --name ".*" 2>/dev/null | tail -1)
xdotool windowfocus --sync "$WID" 2>/dev/null || true
grab(){ ffmpeg -y -f x11grab -video_size ${W}x${H} -i $DISP -frames:v 1 "$1" >/dev/null 2>&1; }
sleep 4
xdotool key --window "$WID" space; sleep 0.3      # 暂停
xdotool key --window "$WID" Tab;   sleep 0.3      # 选第 1 个居民
xdotool key --window "$WID" c;     sleep 0.6      # 玩家对它打招呼 → chat 回复
grab "$OUT/chat1.png"
xdotool key --window "$WID" Tab;   sleep 0.2
xdotool key --window "$WID" c;     sleep 0.6
grab "$OUT/chat2.png"
kill $GD $XV 2>/dev/null || true
echo "--- errors? ---"; grep -iE 'SCRIPT ERROR|Parse Error' /tmp/godot.log | head -8 || echo none
echo done; ls -la "$OUT"/chat*.png
