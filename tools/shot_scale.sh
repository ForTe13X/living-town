#!/usr/bin/env bash
# shot_scale.sh — 容器内渲【一帧】存 png，可指定 NPC 数 + 观察无关 aggregate LOD（规模/LOD 眼验）。
# tools/shot1.sh 写死参数不转发 N/--lod-agg，故加此参数化版（交付 scope workflow 建议）。
# 用法（容器内）：bash /tools/shot_scale.sh /out/x.png [N=200] [lodagg=1] [seed=20260626] [warmup_days=3]
# 宿主：docker run --rm -v .../game:/game -v <out>:/out -v .../tools:/tools gamecraft-runner:4.6.2 \
#         bash /tools/shot_scale.sh /out/x.png 200 1
set -uo pipefail
OUT="${1:-/out/shot.png}"; N="${2:-200}"; LODAGG="${3:-1}"; SEED="${4:-20260626}"; WARM="${5:-3}"
W=1280; H=768; DISP=:90
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 GODOT_SILENCE_ROOT_WARNING=1
Xvfb $DISP -screen 0 ${W}x${H}x24 -nolisten tcp >/tmp/xvfb.log 2>&1 & XV=$!
sleep 1.2
export DISPLAY=$DISP
LOD_ARG=""; [ "$LODAGG" = "1" ] && LOD_ARG="--lod-agg"
godot --path /game --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
  --resolution ${W}x${H} --single-window -- \
  --seed "$SEED" --warmup "$WARM" --backend logic --agents "$N" $LOD_ARG --shot-fit --shot "$OUT" >/tmp/godot.log 2>&1
RC=$?
kill $XV 2>/dev/null
if [ -f "$OUT" ]; then echo "shot ok: $OUT (N=$N lodagg=$LODAGG)"; else echo "shot FAIL rc=$RC"; tail -25 /tmp/godot.log; fi
