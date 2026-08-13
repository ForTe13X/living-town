#!/usr/bin/env bash
# space_roundtrip.sh — 【进店 → 出店 → 截图】采集 + 判据（docs/47 §五-E6 的 W7）。
#
# 为什么要有它：2026-07-28 外部对抗评审的原话 ——「**没有人看过空间切换之后的任何一帧**」。
# 那句话不是修辞：`--shot` 结构上就拍不到那些帧（它 `auto_run=false`、渲一帧、存图、退出，
# 一次空间切换都没发生过），`--probe-space` 只有"进"没有"出"，而 docs/46 §二·九-① 的真 bug
# **恰恰在回来的那一刻才显形**（`_void_key` 停在旧值 ⇒ 出店时键重算又恰好相等 ⇒ 不排重画 ⇒ 界外层永久空白）。
#
# 它与 `--void-gate`（在 visual_gate.sh 里那一条）是**两层**证据，不是一件事重做两遍：
#   · `--void-gate` 量**计数器**（`_void_draws` 涨没涨）。它能证明"重画被排上了"。
#   · 本脚本量**像素**。重画被排上、却画成一块纯色，计数器照样绿——那正是"没人看过那些帧"的含义。
#
# ── 三帧 + 三条判据（判据在 tools/assert_space_roundtrip.py，这里只负责把帧拍出来）──
#   rt_town_before.png → rt_interior.png → rt_town_after.png
#   A 往返不变式：`town_after` 必须与 `town_before` 逐像素相同（世界已冻结、取景由 `go_home()` 复位）。
#   B 界外带活着：`town_after` 的界外带必须仍然是**有纹理**的（颜色数 / 标准差下界）。
#   C 判别力配对：`interior` 必须与 town 两帧**大不相同** —— 否则 A 是"什么都没发生"空过的。
#     （docs/41 §6-★：写下判据先问"一个什么都不做的改动能不能通过它"。A 单独看**会**空过，
#       所以 A 与 C **必须成对**报告，这与 docs/46 D7 那条 `bbox=None` 的纪律是同一条。）
#
# ── 退出码 ──────────────────────────────────────────────────────────────────
#   0 PASS   1 FAIL（拍不出帧 / 前提破了 / 判据红）   77 SKIP（本机没有渲染环境，不是失败）
#
# ── 开关（与 visual_gate.sh 同名同义，两条门共用一套心智模型）────────────────
#   LT_RT=auto|require|off        默认 auto（无渲染环境 ⇒ 77）
#   LT_RT_RUNNER=auto|docker|native
#   LT_RT_IMAGE=gamecraft-runner:4.6.2
#   LT_RT_OUT=<dir>               留下三帧眼验（默认 mktemp，跑完即弃）
#   LT_RT_GAME=<dir>              拿【别的一棵 game/】来渲 —— **负对照专用**：
#                                 把 game/ 拷进 scratchpad、在拷贝上回滚 WorldView 的 `_void_key` 修复，
#                                 再用这个变量指过去，本门必须变红。判据没有过这一关就不是判据。
#   LT_RT_JOURNEY=simple|full     默认 simple（玩家 town↔cafe/1f 往返门）。
#                                 full = 玩家进出 + Probe 观察 owner-only 2F（非玩家上楼证据），
#                                 逐段断言 Probe Floor + 回程取景一致 + 2F 与 1F 可分；判据走 assert_floor_roundtrip.py。
#   LT_RT_DRAW_SKIP=<pass>        透传 --draw-skip <pass> 给引擎（负对照用）。
#   LT_RT_SKIP_FURN=1             LT_RT_DRAW_SKIP=interior_furniture 的便捷别名 ——
#                                 让 2F/1F 家具都不画 ⇒ 两层帧变得一样 ⇒ full 门的"2F 与 1F 可分"臂必红（那条牙）。
#   LT_RT_MODE=portal|flip        默认 portal（走出货路径 `_portal_click`）
#   LT_RT_REDRAW=auto|none        默认 auto。none = 【暂停复现】：不补 `_redraw_all()`，
#                                 拍出来的 rt_interior.png 就是“暂停时点门进店，画面停在小镇上”那一帧
#                                 （2026-07-30 由本脚本第一次跑就量到的真问题，归属 Main.gd/WorldView.gd）。
#   LT_RT_SPACE=cafe              进哪个 Space
#   GODOT / PYTHON                同 ci.sh
#
# ── 单独跑 ──────────────────────────────────────────────────────────────────
#   LT_RT_OUT=/tmp/rt bash tools/space_roundtrip.sh
set -uo pipefail

SKIP_RC=77
SEED="${LT_RT_SEED:-3}"
TICK="${LT_RT_TICK:-600}"     # 第 3 天 12:00 正午 —— 与 visual_gate 的 NOON_TICK 同一个时刻，
                              # 于是"界外带是不是活的"不会被夜间乘子压低对比而混淆。
W=1280; H=768

# ══ 模式 B：在渲染环境【内部】拍三帧 ═══════════════════════════════════════
if [ "${1:-}" = "--shoot" ]; then
  OUT="${2:-/out}"
  GAME="${RT_GAME:-/game}"
  GBIN="${GODOT:-godot}"
  DISP="${RT_DISPLAY:-:95}"
  MODE="${RT_MODE:-portal}"
  SPACE="${RT_SPACE:-cafe}"
  REDRAW="${RT_REDRAW:-auto}"
  JOURNEY="${RT_JOURNEY:-simple}"   # simple=玩家进出三帧；full=玩家进出 + Probe 观察 owner-only 楼层
  DRAWSKIP="${RT_DRAW_SKIP:-}"      # 非空 ⇒ 透传 --draw-skip <pass>（AM3 负对照：interior_furniture ⇒ 2F 与 1F 都空 ⇒ 不可分 ⇒ 门红）
  CORRUPT_MANIFEST="${RT_CORRUPT_MANIFEST:-}"
  DENY_PORTAL="${RT_DENY_PORTAL:-}"
  export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 GODOT_SILENCE_ROOT_WARNING=1
  OWN_XV=0
  if [ -z "${DISPLAY:-}" ] || [ "${RT_OWN_XVFB:-1}" = "1" ]; then
    Xvfb "$DISP" -screen 0 ${W}x${H}x24 -nolisten tcp >/tmp/rt-xvfb.log 2>&1 & XV=$!
    OWN_XV=1
    sleep 1.5
    export DISPLAY="$DISP"
  fi
  rm -f "$OUT"/rt_*.png "$OUT/rt_meta.json"
  DS_ARGS=()
  [ -n "$DRAWSKIP" ] && DS_ARGS=(--draw-skip "$DRAWSKIP")
  PLAYER_ARGS=()
  if [ -n "${RT_PLAYER_POS:-}" ]; then
    read -r PX PY <<< "${RT_PLAYER_POS//,/ }"
    PLAYER_ARGS=(--player-pos "$PX" "$PY" --select player)
  fi
  CORRUPT_ARGS=()
  [ -n "$CORRUPT_MANIFEST" ] && CORRUPT_ARGS=(--rt-corrupt-manifest "$CORRUPT_MANIFEST")
  DENY_ARGS=()
  [ -n "$DENY_PORTAL" ] && DENY_ARGS=(--rt-deny-portal "$DENY_PORTAL")
  "$GBIN" --path "$GAME" --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
    --resolution ${W}x${H} --single-window res://bench/SpaceShot.tscn -- \
    --backend logic --seed "$SEED" --warmup-tick "$TICK" \
    --rt-out "$OUT" --rt-space "$SPACE" --rt-mode "$MODE" --rt-journey "$JOURNEY" --rt-redraw "$REDRAW" \
    "${PLAYER_ARGS[@]}" "${DS_ARGS[@]}" "${CORRUPT_ARGS[@]}" "${DENY_ARGS[@]}"
  rc=$?
  [ "$OWN_XV" = "1" ] && kill $XV 2>/dev/null
  exit $rc
fi

# ══ 模式 A：宿主编排 ═══════════════════════════════════════════════════════
cd "$(dirname "$0")/.."
REPO="$PWD"
case "$(uname -s)" in MINGW*|MSYS*) REPO="$(pwd -W)" ;; esac
GODOT="${GODOT:-godot}"
PY="${PYTHON:-python}"
MODE="${LT_RT:-auto}"
RUNNER="${LT_RT_RUNNER:-auto}"
IMG="${LT_RT_IMAGE:-gamecraft-runner:4.6.2}"
JOURNEY="${LT_RT_JOURNEY:-simple}"    # simple=玩家 1F 往返；full=玩家进出 + Probe 楼层观察
DRAWSKIP="${LT_RT_DRAW_SKIP:-}"        # AM3 负对照：LT_RT_DRAW_SKIP=interior_furniture ⇒ 2F/1F 都空 ⇒ B 臂（可分）红
[ "${LT_RT_SKIP_FURN:-0}" = "1" ] && DRAWSKIP="interior_furniture"   # 便捷别名：让 2F 帧==1F 帧 的那条牙

skip(){
  if [ "$MODE" = "require" ]; then
    echo "  ❌ ROUNDTRIP GATE 无法运行且 LT_RT=require：$1"; exit 1
  fi
  echo "  ⏭  ROUNDTRIP GATE SKIP：$1"
  exit $SKIP_RC
}

[ "$MODE" = "off" ] && skip "LT_RT=off"

# GitHub Actions：显式跳过。理由与 visual_gate.sh 抬头逐字相同（GL 栈没 pin ⇒ 红绿会自己变），
# 不重复论证；两条门在这一点上必须同进同退，否则又出现"同一波两处相反说法"（docs/46 §二·九-⑦）。
if [ "${GITHUB_ACTIONS:-}" = "true" ] && [ "$MODE" != "require" ] && [ -z "${LT_RT_RUNNER:-}" ]; then
  skip "GitHub Actions —— GL 栈没有 pin（同 visual_gate.sh 抬头）"
fi

have_docker(){ command -v docker >/dev/null 2>&1 && docker image inspect "$IMG" >/dev/null 2>&1; }
have_native(){ command -v Xvfb >/dev/null 2>&1 && command -v "$GODOT" >/dev/null 2>&1; }

PICK=""
case "$RUNNER" in
  docker) have_docker && PICK=docker || skip "LT_RT_RUNNER=docker 但镜像 $IMG 不在本机" ;;
  native) have_native && PICK=native || skip "LT_RT_RUNNER=native 但缺 Xvfb 或 GODOT($GODOT)" ;;
  auto)   if have_docker; then PICK=docker
          elif have_native; then PICK=native
          else skip "既没有镜像 $IMG，也没有 Xvfb+GODOT"; fi ;;
  *)      echo "  ❌ 未知 LT_RT_RUNNER=$RUNNER"; exit 1 ;;
esac

GAME="${LT_RT_GAME:-$REPO/game}"
case "$(uname -s)" in MINGW*|MSYS*) GAME="$(cd "$GAME" && pwd -W)" ;; esac

OUT="${LT_RT_OUT:-}"
EPHEMERAL=0
if [ -z "$OUT" ]; then OUT="$(mktemp -d 2>/dev/null || echo /tmp/rt-$$)"; EPHEMERAL=1; fi
mkdir -p "$OUT"
OUT_HOST="$OUT"
case "$(uname -s)" in MINGW*|MSYS*) OUT_HOST="$(cd "$OUT" && pwd -W)" ;; esac

echo "  runner=$PICK  mode=$MODE  rt-mode=${LT_RT_MODE:-portal}  journey=$JOURNEY  draw-skip=${DRAWSKIP:-none}  game=$GAME  out=$OUT"
SHOT_RC=0
if [ "$PICK" = docker ]; then
  # ⚠️ 并行期纪律（docs/43 R6）：只按自己的名字杀自己的容器，禁止 `docker ps -q | xargs docker kill`。
  CNAME="lt-space-roundtrip-$$"
  MSYS_NO_PATHCONV=1 docker run --rm --name "$CNAME" \
    -e RT_MODE="${LT_RT_MODE:-portal}" -e RT_SPACE="${LT_RT_SPACE:-cafe}" -e RT_REDRAW="${LT_RT_REDRAW:-auto}" \
    -e RT_JOURNEY="$JOURNEY" -e RT_DRAW_SKIP="$DRAWSKIP" \
    -e RT_CORRUPT_MANIFEST="${LT_RT_CORRUPT_MANIFEST:-}" \
    -e RT_DENY_PORTAL="${LT_RT_DENY_PORTAL:-}" \
    -e RT_PLAYER_POS="${LT_RT_PLAYER_POS:-}" \
    -e LT_RT_SEED="$SEED" -e LT_RT_TICK="$TICK" \
    -v "$GAME:/game" -v "$REPO/tools:/tools" -v "$OUT_HOST:/out" \
    "$IMG" bash /tools/space_roundtrip.sh --shoot /out
  SHOT_RC=$?
else
  RT_GAME="$GAME" RT_MODE="${LT_RT_MODE:-portal}" RT_SPACE="${LT_RT_SPACE:-cafe}" RT_REDRAW="${LT_RT_REDRAW:-auto}" \
    RT_JOURNEY="$JOURNEY" RT_DRAW_SKIP="$DRAWSKIP" RT_PLAYER_POS="${LT_RT_PLAYER_POS:-}" \
    RT_CORRUPT_MANIFEST="${LT_RT_CORRUPT_MANIFEST:-}" RT_DENY_PORTAL="${LT_RT_DENY_PORTAL:-}" \
    GODOT="$GODOT" bash "$0" --shoot "$OUT"
  SHOT_RC=$?
fi

if [ $SHOT_RC -ne 0 ]; then
  if [ "$PICK" = native ] && [ "$MODE" != "require" ]; then
    skip "native 渲染路径拍不出帧（未 pin 的环境不背这个锅；LT_RT=require 可让它变红）"
  fi
  echo "  ❌ ROUNDTRIP GATE：采集失败（见上面的 [SPACESHOT] 行）—— 拍不出帧或前提断言破了"
  exit 1
fi

# 判据分派：simple → 玩家 1F 往返；full → 玩家进出 + Probe 楼层观察（非玩家 owner-only 穿越证据）
if [ -n "${LT_RT_DENY_PORTAL:-}" ]; then
  "$PY" tools/assert_portal_denied.py "$OUT"
elif [ "$JOURNEY" = "full" ]; then
  "$PY" tools/assert_floor_roundtrip.py "$OUT"
else
  "$PY" tools/assert_space_roundtrip.py "$OUT"
fi
ARC=$?
[ $EPHEMERAL -eq 1 ] && rm -rf "$OUT"
exit $ARC
