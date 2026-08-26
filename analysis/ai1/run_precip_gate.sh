#!/usr/bin/env bash
# run_precip_gate.sh — AI1（编号129）降水可见门的端到端复现（拍帧 + 判据），与 tools/visual_gate.sh 同构。
# 自我再入：host 模式起 docker → 容器里以 --shoot 拍 12 帧 → 回宿主跑 analysis/ai1/assert_precip.py。
#
# ⚠️ 这是【参照实现 / 未接线】。接进 CI 的做法（照 AF2 docs/122 §四）：
#   季/雨门要吃【非春·非阴】的帧，而 visual_gate.sh 现在只拍 seed3 游戏日3（春·阴）⇒ 不能复用已拍帧，
#   得多拍这 12 张（冬 on/off × 3 seed + 非冬雨 on/off × 3 seed）。把这些 godot 拍帧命令并进
#   visual_gate.sh 已有的 Xvfb，把 assert_precip.py 挪到 tools/，ci.sh 第 6 步抬头门数 +1。
#   拍帧 tick 已算好（冬=11160 恒 season 冬；雨=各 seed 最早非冬雨日正午，见下 RAIN_TICK）。
#
# 退出码：0 PASS / 1 FAIL / 77 SKIP（无 docker 镜像）。
set -uo pipefail
W=1280; H=768
WINTER_TICK=11160                      # 游戏日47 = 冬（season 与 seed 无关 ⇒ 全 seed 下雪）
# 各 seed 最早的【非冬】雨日正午（春·雨；由 _weather_of_day/_season_of_day 纯函数算得，见 docs/129 §一）
declare -A RAIN_TICK=( [1]=600 [3]=840 [5]=1560 )
SEEDS="1 3 5"

if [ "${1:-}" = "--shoot" ]; then
  OUT="${2:-/out}"; GAME="${VG_GAME:-/game}"; GBIN="${GODOT:-godot}"; DISP="${VG_DISPLAY:-:96}"
  export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 GODOT_SILENCE_ROOT_WARNING=1
  Xvfb "$DISP" -screen 0 ${W}x${H}x24 -nolisten tcp >/tmp/pg-xvfb.log 2>&1 & XV=$!
  sleep 1.5; export DISPLAY="$DISP"; rc=0; : >/tmp/pg-godot.log
  shoot(){ # shoot <name> <seed> <tick> [skip]
    local nm="$1" sd="$2" tk="$3" sk="${4:-}"; local extra=""
    [ -n "$sk" ] && extra="--draw-skip $sk"
    rm -f "$OUT/${nm}.png"
    "$GBIN" --path "$GAME" --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
      --resolution ${W}x${H} --single-window -- \
      --backend logic --shot "$OUT/${nm}.png" --seed "$sd" --warmup-tick "$tk" --shot-fit $extra \
      >>/tmp/pg-godot.log 2>&1
    if [ -s "$OUT/${nm}.png" ]; then echo "  shot ok   ${nm}.png"; else echo "  shot FAIL ${nm}.png"; rc=1; fi
  }
  for s in $SEEDS; do
    shoot "s${s}_winter_on"  "$s" "$WINTER_TICK"
    shoot "s${s}_winter_off" "$s" "$WINTER_TICK" snow
    shoot "s${s}_rain_on"    "$s" "${RAIN_TICK[$s]}"
    shoot "s${s}_rain_off"   "$s" "${RAIN_TICK[$s]}" rain
  done
  kill $XV 2>/dev/null
  [ $rc -ne 0 ] && tail -30 /tmp/pg-godot.log
  exit $rc
fi

# ── host 模式 ──
cd "$(dirname "$0")/../.."
REPO="$PWD"; case "$(uname -s)" in MINGW*|MSYS*) REPO="$(pwd -W)" ;; esac
IMG="${LT_VISUAL_IMAGE:-gamecraft-runner:4.6.2}"
PY="${PYTHON:-python}"
if ! command -v docker >/dev/null 2>&1 || ! docker image inspect "$IMG" >/dev/null 2>&1; then
  echo "  ⏭  PRECIP GATE SKIP：本机没有 docker 镜像 $IMG（不是失败）"; exit 77
fi
OUT="$(mktemp -d 2>/dev/null || echo /tmp/pg-$$)"; mkdir -p "$OUT"
OUT_HOST="$OUT"; SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
case "$(uname -s)" in MINGW*|MSYS*) OUT_HOST="$(cd "$OUT" && pwd -W)"; SELF_DIR="$(cd "$(dirname "$0")" && pwd -W)" ;; esac
CNAME="lt-precip-gate-$$"
MSYS_NO_PATHCONV=1 docker run --rm --name "$CNAME" \
  -v "$REPO/game:/game" -v "$SELF_DIR:/pg" -v "$OUT_HOST:/out" \
  "$IMG" bash /pg/run_precip_gate.sh --shoot /out
SRC=$?
if [ $SRC -ne 0 ]; then echo "  ❌ PRECIP GATE：拍帧失败"; rm -rf "$OUT"; exit 1; fi
"$PY" "$(dirname "$0")/assert_precip.py" "$OUT"
ARC=$?
rm -rf "$OUT"
exit $ARC
