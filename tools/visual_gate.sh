#!/usr/bin/env bash
# visual_gate.sh — 本仓库【第一条视觉门】：昼夜量具（docs/41 §6 盲区④ 的机器化）。
#
# 为什么要有它：`--shot` 曾经【永远渲不出昼夜】——CanvasModulate 建出来是白的，`_daylight` 只在
# `_on_tick`/`_after_jump`/`_after_load` 里施加，而 `--shot` 把 `auto_run=false` ⇒ 三条路一条都不走。
# 症状是【所有静帧一律按正午渲染】，而 HUD 老老实实写着「夜」。C3 在 `Main.gd:271`（CanvasModulate
# 建好处）补了一行修掉它。这道门守的就是那一行——它是这个项目所有视觉判断用的尺子。
#
# ── 退出码（ci.sh 依赖这三个值）──────────────────────────────────────────────
#   0  PASS      1  FAIL（真的坏了）      77 SKIP（本机没有渲染环境，**不是**失败）
#
# ── 可移植性：为什么它敢跳过，以及跳过为什么不是偷懒 ─────────────────────────
# `tools/ci.sh` 同时跑在本机（Windows/Git-Bash + Docker）和 GitHub Actions（ubuntu-latest）。
# GHA 那条路上**既没有 `gamecraft-runner:4.6.2` 镜像**（它是 22nd 项目本地构建的，不在任何 registry），
# **也没有装 Xvfb**（runner 镜像不带），而 `setup-python` 给的是裸解释器（**没有 Pillow**）。
# ⇒ 一道"必须有 Docker+Xvfb"的硬门放进 CI，在 GHA 上会**每次都环境性变红**。
# 而**在别人机器上因环境变红的门比没有门更坏**：它训练所有人忽略红色。所以本门的判据是：
#
#   * **能力探测在拍图之前**（有没有 pin 死的镜像 / 有没有 Xvfb），探不到 ⇒ 立刻 77 SKIP，一帧都不拍；
#   * 探到了就**必须给出判决**：拍不出图或断言不过 ⇒ 1 FAIL（这时候红色是真信号）；
#   * 唯一的例外是 native（未 pin）路径：见下面 `LT_VISUAL` 的 auto 档。
#
# 逐字节的颜色断言只有在**光栅器被钉死**时才可信：换一个 mesa 版本，软件光栅可能差 1 个 LSB。
# 所以 docker（镜像 pin 死 mesa）走 tol=0；native（未 pin）走 tol=4——而本门要挡的回归会让夜帧
# 从 (57,82,63) 跳回 (134,173,79)，**每通道差 77/91/16**，tol=4 一分判别力都不损失。
#
# ── 想在 GitHub Actions 上把它打开（**C4 没做，因为 .github/ 不在本棒的所有权表里**）──────
# 在 `.github/workflows/ci.yml` 的 "CI gate" 之前加一步，然后给 CI gate 那步加两个环境变量：
#     - run: sudo apt-get update && sudo apt-get install -y xvfb libgl1 libglx-mesa0
#     env:  LT_VISUAL_RUNNER: native
#           LT_VISUAL: require          # 想让它咬人才加；不加就是 auto（拍不出帧算 SKIP）
# **可信度**：native 分支已在 Ubuntu 22.04 + Xvfb + mesa 软件渲染下**实测跑通并 PASS**
# （在 gamecraft-runner 容器里以 native 模式跑，那条路上**没有 Pillow**，走的正是 stdlib PNG 读取器）。
# 但 **GitHub Actions 本身没跑过**——上面这段是推断，第一次开它的人请先用 `LT_VISUAL`(auto) 观察一轮
# 再升成 require。这正是本门默认不自己打开的原因。
#
# ── 开关 ────────────────────────────────────────────────────────────────────
#   LT_VISUAL=auto|require|off   默认 auto。
#       auto    : 无渲染环境 ⇒ 77 SKIP；native 路径下【拍图失败】也算 77（未 pin 的环境不背这个锅），
#                 但断言一旦跑起来就是硬判决。
#       require : 任何跳过都升级成 1 FAIL。CI 里想让这道门真正咬人时用（例如宿主 CI）。
#       off     : 直接 77，什么都不做。
#   LT_VISUAL_RUNNER=auto|docker|native      默认 auto（docker 优先，因为它 pin 死）
#   LT_VISUAL_IMAGE=gamecraft-runner:4.6.2
#   LT_VISUAL_OUT=<dir>          留下证据 PNG 的目录（默认 mktemp，跑完即弃）
#   LT_VISUAL_GAME=<dir>         拿【别的一棵 game/】来渲（默认本仓库的 game/）。
#                                存在的理由是**负对照**：docs/43 要求每道新门都要有一次真的变红，
#                                而 C4 不许碰 `game/`（文件所有权表）⇒ 只能把 game/ 拷进 scratchpad、
#                                在拷贝上注释掉 Main.gd 的修复行，再用这个变量指过去。
#   GODOT / PYTHON               同 ci.sh
#
# ── 单独跑 ──────────────────────────────────────────────────────────────────
#   bash tools/visual_gate.sh                       # 本机（自动选 docker）
#   LT_VISUAL=require bash tools/visual_gate.sh     # 不许跳过
#   LT_VISUAL_OUT=/tmp/vg bash tools/visual_gate.sh # 把两帧留下来眼验
set -uo pipefail

SKIP_RC=77
NIGHT_TICK=488        # 第 3 天 00:48（夜）  ┐ C3 记录在案的那条命令，逐字沿用
NOON_TICK=600         # 第 3 天 12:00（正午）┘ （改这两个数就要同步改 assert_daynight.py 的期望值来源）
SEED=3
W=1280; H=768

# ══ 模式 B：在渲染环境【内部】拍两帧 ════════════════════════════════════════
# 容器里用 `bash /tools/visual_gate.sh --shoot /out`；native 路径下同一份脚本原地跑。
# 写成"自我再入"而不是再开一个脚本，是为了让容器内外只有一份拍图参数——两份必然漂移。
if [ "${1:-}" = "--shoot" ]; then
  OUT="${2:-/out}"
  GAME="${VG_GAME:-/game}"
  GBIN="${GODOT:-godot}"
  DISP="${VG_DISPLAY:-:94}"
  export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 GODOT_SILENCE_ROOT_WARNING=1
  Xvfb "$DISP" -screen 0 ${W}x${H}x24 -nolisten tcp >/tmp/vg-xvfb.log 2>&1 & XV=$!
  sleep 1.5
  export DISPLAY="$DISP"
  rc=0
  : >/tmp/vg-godot.log
  for pair in "night $NIGHT_TICK" "noon $NOON_TICK"; do
    nm="${pair%% *}"; tk="${pair##* }"
    rm -f "$OUT/vg_${nm}.png"
    "$GBIN" --path "$GAME" --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
      --resolution ${W}x${H} --single-window -- \
      --backend logic --shot "$OUT/vg_${nm}.png" --seed "$SEED" --warmup-tick "$tk" --shot-fit \
      >>/tmp/vg-godot.log 2>&1
    if [ -s "$OUT/vg_${nm}.png" ]; then echo "  shot ok   vg_${nm}.png (tick=$tk)"
    else echo "  shot FAIL vg_${nm}.png (tick=$tk)"; rc=1; fi
  done
  kill $XV 2>/dev/null
  [ $rc -ne 0 ] && tail -25 /tmp/vg-godot.log
  exit $rc
fi

# ══ 模式 A：宿主编排 ═══════════════════════════════════════════════════════
cd "$(dirname "$0")/.."
REPO="$PWD"
case "$(uname -s)" in MINGW*|MSYS*) REPO="$(pwd -W)" ;; esac   # Docker Desktop 要 Windows 形状的路径
GODOT="${GODOT:-godot}"
PY="${PYTHON:-python}"
MODE="${LT_VISUAL:-auto}"
RUNNER="${LT_VISUAL_RUNNER:-auto}"
IMG="${LT_VISUAL_IMAGE:-gamecraft-runner:4.6.2}"

skip(){ # skip <理由>
  if [ "$MODE" = "require" ]; then
    echo "  ❌ VISUAL GATE 无法运行且 LT_VISUAL=require：$1"; exit 1
  fi
  echo "  ⏭  VISUAL GATE SKIP：$1"
  echo "     （这不是失败。想让它必须跑：LT_VISUAL=require；补齐环境的办法见本脚本抬头。）"
  exit $SKIP_RC
}

[ "$MODE" = "off" ] && skip "LT_VISUAL=off"

have_docker(){ command -v docker >/dev/null 2>&1 && docker image inspect "$IMG" >/dev/null 2>&1; }
have_native(){ command -v Xvfb >/dev/null 2>&1 && command -v "$GODOT" >/dev/null 2>&1; }

PICK=""
case "$RUNNER" in
  docker) have_docker && PICK=docker || skip "LT_VISUAL_RUNNER=docker 但镜像 $IMG 不在本机" ;;
  native) have_native && PICK=native || skip "LT_VISUAL_RUNNER=native 但缺 Xvfb 或 GODOT($GODOT)" ;;
  auto)   if have_docker; then PICK=docker
          elif have_native; then PICK=native
          else skip "既没有镜像 $IMG，也没有 Xvfb+GODOT —— 例如 GitHub Actions 的 ubuntu-latest"; fi ;;
  *)      echo "  ❌ 未知 LT_VISUAL_RUNNER=$RUNNER"; exit 1 ;;
esac

GAME="${LT_VISUAL_GAME:-$REPO/game}"
case "$(uname -s)" in MINGW*|MSYS*) GAME="$(cd "$GAME" && pwd -W)" ;; esac

OUT="${LT_VISUAL_OUT:-}"
EPHEMERAL=0
if [ -z "$OUT" ]; then OUT="$(mktemp -d 2>/dev/null || echo /tmp/vg-$$)"; EPHEMERAL=1; fi
mkdir -p "$OUT"
OUT_HOST="$OUT"
case "$(uname -s)" in MINGW*|MSYS*) OUT_HOST="$(cd "$OUT" && pwd -W)" ;; esac

echo "  runner=$PICK  mode=$MODE  game=$GAME  out=$OUT"
SHOT_RC=0
if [ "$PICK" = docker ]; then
  TOL=0                      # 镜像把 mesa 钉死 ⇒ 逐字节
  # ⚠️ 并行期纪律（docs/43 R6）：**只按自己的名字杀自己的容器**，禁止 `docker ps -q | xargs docker kill`。
  CNAME="lt-visual-gate-$$"
  MSYS_NO_PATHCONV=1 docker run --rm --name "$CNAME" \
    -v "$GAME:/game" -v "$REPO/tools:/tools" -v "$OUT_HOST:/out" \
    "$IMG" bash /tools/visual_gate.sh --shoot /out
  SHOT_RC=$?
else
  TOL=4                      # 未 pin 的光栅器：容忍 1 个 LSB 级的漂移，判别力不受影响（见抬头）
  VG_GAME="$GAME" GODOT="$GODOT" bash "$0" --shoot "$OUT"
  SHOT_RC=$?
fi

if [ $SHOT_RC -ne 0 ]; then
  if [ "$PICK" = native ] && [ "$MODE" != "require" ]; then
    skip "native 渲染路径拍不出帧（未 pin 的环境不背这个锅；LT_VISUAL=require 可让它变红）"
  fi
  echo "  ❌ VISUAL GATE：渲染环境在位却拍不出帧 —— 这是真信号，不是环境问题"
  exit 1
fi

"$PY" tools/assert_daynight.py "$OUT/vg_night.png" "$OUT/vg_noon.png" "$NIGHT_TICK" "$NOON_TICK" --tol "$TOL"
ARC=$?
[ $EPHEMERAL -eq 1 ] && rm -rf "$OUT"
exit $ARC
