#!/usr/bin/env bash
# run_season_gate.sh —— 四季可分门的【端到端复现】：在 docker gamecraft(mesa 钉死) 里拍 8 张晴天四季帧
# （seed3 的四个晴天：春=游戏日2 / 夏=20 / 秋=35 / 冬=51，各拍昼+夜），再在宿主侧跑 analysis/af2/assert_season.py。
#
# 这是给【合流接线的人】的参照实现（本棒不碰 tools/**）。它与 tools/visual_gate.sh 同构：
#   * 能力探测（有没有 pin 死的镜像）→ 探不到就 77 SKIP，不假红；
#   * 容器里起一个 Xvfb 拍 8 帧（软渲染、mesa 钉死 ⇒ 逐字节可比）；
#   * 判据在宿主侧跑。
# 想接进 CI：把 8 条 godot 拍帧命令并进 visual_gate.sh 已有的那个 Xvfb（省一次容器启动），
#   把 assert_season.py 挪到 tools/，在 ci.sh 第 6 步后跑它。晴天 tick 已算好（见下 PAIRS，纯 f(seed,day)）。
#
# 用法:  bash analysis/af2/run_season_gate.sh            # 本机 docker
#        OUT=/some/dir bash analysis/af2/run_season_gate.sh   # 留下 8 帧眼验
set -uo pipefail
SKIP_RC=77
SEED=3
W=1280; H=768
IMG="${LT_VISUAL_IMAGE:-gamecraft-runner:4.6.2}"
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
case "$(uname -s)" in MINGW*|MSYS*) REPO="$(cd "$REPO" && pwd -W)";; esac
GAME="${LT_GAME:-$REPO/game}"
PY="${PYTHON:-python}"

# seed3 晴天：春 gd2(tick 360/248) 夏 gd20(4680/4568) 秋 gd35(8280/8168) 冬 gd51(12120/12008)
#   noon = (gd-1)*240+120, night = (gd-1)*240+8; weather(seed3,day)=晴 已核（纯 f(seed,day)）。
PAIRS="spring_noon 360;spring_night 248;summer_noon 4680;summer_night 4568;autumn_noon 8280;autumn_night 8168;winter_noon 12120;winter_night 12008"

# ── 容器内：拍 8 帧（--shoot 再入，与 visual_gate.sh 同一手法）──────────────────
if [ "${1:-}" = "--shoot" ]; then
  OUT="${2:-/out}"; GAME_IN="/game"; GBIN="${GODOT:-godot}"; DISP=":95"
  export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 GODOT_SILENCE_ROOT_WARNING=1
  Xvfb "$DISP" -screen 0 ${W}x${H}x24 -nolisten tcp >/tmp/season-xvfb.log 2>&1 & XV=$!
  sleep 1.5; export DISPLAY="$DISP"; rc=0; : >/tmp/season-godot.log
  IFS=';' read -ra ITEMS <<< "$PAIRS"
  for item in "${ITEMS[@]}"; do
    nm="${item%% *}"; tk="${item##* }"; rm -f "$OUT/${nm}.png"
    "$GBIN" --path "$GAME_IN" --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
      --resolution ${W}x${H} --single-window -- \
      --backend logic --shot "$OUT/${nm}.png" --seed "$SEED" --warmup-tick "$tk" --shot-fit \
      >>/tmp/season-godot.log 2>&1
    if [ -s "$OUT/${nm}.png" ]; then echo "  shot ok   ${nm}.png (tick=$tk)"
    else echo "  shot FAIL ${nm}.png (tick=$tk)"; rc=1; fi
  done
  kill $XV 2>/dev/null; [ $rc -ne 0 ] && tail -25 /tmp/season-godot.log; exit $rc
fi

# ── 宿主编排 ────────────────────────────────────────────────────────────────
command -v docker >/dev/null 2>&1 && docker image inspect "$IMG" >/dev/null 2>&1 || {
  echo "  ⏭  SEASON GATE SKIP：本机没有 $IMG（这不是失败）"; exit $SKIP_RC; }
OUT="${OUT:-$(mktemp -d 2>/dev/null || echo /tmp/season-$$)}"; mkdir -p "$OUT"
OUT_HOST="$OUT"; case "$(uname -s)" in MINGW*|MSYS*) OUT_HOST="$(cd "$OUT" && pwd -W)";; esac
echo "  runner=docker  game=$GAME  out=$OUT"
MSYS_NO_PATHCONV=1 docker run --rm --name "lt-season-gate-$$" \
  -v "$GAME:/game" -v "$OUT_HOST:/out" -v "$REPO/analysis:/analysis" \
  "$IMG" bash /analysis/af2/run_season_gate.sh --shoot /out
SRC=$?
[ $SRC -ne 0 ] && { echo "  ❌ SEASON GATE：拍帧失败 rc=$SRC"; exit 1; }
"$PY" "$DIR/assert_season.py" \
  --noon  "$OUT/spring_noon.png"  "$OUT/summer_noon.png"  "$OUT/autumn_noon.png"  "$OUT/winter_noon.png" \
  --night "$OUT/spring_night.png" "$OUT/summer_night.png" "$OUT/autumn_night.png" "$OUT/winter_night.png"
exit $?
