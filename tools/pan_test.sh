#!/usr/bin/env bash
# pan_test.sh — 验证"拖拽平移/缩放"真的动了镜头：暂停仿真 → 截一帧 → xdotool 注入左键拖 → 再截一帧。
# 仿真暂停后，两帧之间【唯一】的变化只能来自相机 → 画面有位移=拖拽生效。
# 用法（容器内）：bash /tools/pan_test.sh /out [seed]
set -uo pipefail
OUT="${1:-/out}"; SEED="${2:-20260626}"
W=1280; H=768; DISP=:91
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 GODOT_SILENCE_ROOT_WARNING=1
Xvfb $DISP -screen 0 ${W}x${H}x24 -nolisten tcp >/tmp/xvfb.log 2>&1 & XV=$!
sleep 1.2
export DISPLAY=$DISP
godot --path /game --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
  --resolution ${W}x${H} --single-window -- --seed "$SEED" --warmup 3 --backend logic >/tmp/godot.log 2>&1 & GD=$!
sleep 14                                          # 必须等过 Godot 启动闪屏 + warmup，否则 before 帧抓到的是 splash（血泪）
WID=$(xdotool search --onlyvisible --pid $GD 2>/dev/null | tail -1)
[ -z "${WID:-}" ] && WID=$(xdotool search --name ".*" 2>/dev/null | tail -1)
xdotool windowfocus --sync "$WID" 2>/dev/null || true
grab(){ ffmpeg -y -f x11grab -video_size ${W}x${H} -i $DISP -frames:v 1 "$1" >/dev/null 2>&1; }

xdotool key --window "$WID" space; sleep 0.5      # 暂停仿真：之后画面变化只可能来自相机
grab "$OUT/pan_before.png"
# 左键从 (420,300) 拖到 (760,470)：远超 DRAG_THRESH → 应从"可能点选"转成拖镜头
xdotool mousemove 420 300; sleep 0.2; xdotool mousedown 1; sleep 0.2
for i in 1 2 3 4 5 6 7 8; do xdotool mousemove $((420 + i*43)) $((300 + i*21)); sleep 0.06; done
xdotool mouseup 1; sleep 0.6
grab "$OUT/pan_after.png"
# 再验缩放（键盘 +）
xdotool key --window "$WID" plus; sleep 0.1; xdotool key --window "$WID" plus; sleep 0.5
grab "$OUT/zoom_after.png"
kill $GD $XV 2>/dev/null
ls -la "$OUT"/pan_before.png "$OUT"/pan_after.png "$OUT"/zoom_after.png 2>/dev/null | awk '{print $5, $9}'
