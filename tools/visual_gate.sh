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
# ── 可移植性：为什么它在 GitHub Actions 上跳过（2026-07-26 D1 更正）─────────
# ⚠ 这一段原来写的是「GHA 的 ubuntu-latest **没有装 Xvfb**（runner 镜像不带）⇒ auto 会 SKIP」。
#   **那是假的**，而整段跳过逻辑的正当性就架在它上面。实测核对（D1）：
#     · `actions/runner-images` 的 Ubuntu2404-Readme.md 里 `xvfb | 2:21.1.12-1ubuntu1.6`；
#       Ubuntu2204 是 `2:21.1.4-2ubuntu1.7~22.04.16`。**两个镜像都自带 Xvfb。**
#     · `.github/workflows/ci.yml` 把 godot 装到 `/usr/local/bin/godot` 并设 `GODOT: godot`。
#   ⇒ `have_native()` 的两个条件在 GHA 上**都为真** ⇒ `RUNNER=auto` 选的是 **native，不是 SKIP**。
#   这道门在 GHA 上其实一直是**开着**的，只是没人去看它到底跑没跑。
#   （docker 在 GHA 上装了，但 `gamecraft-runner:4.6.2` 是 22nd 项目本地构建、不在任何 registry
#     ⇒ `docker image inspect` 失败 ⇒ `have_docker()` 为假。这一半原文没说错。）
#
# 那么该让它在 GHA 上跑吗？**不该，显式跳过。** 真实理由不是"跑不起来"，而是**跑起来的那部分没有 pin**：
#   ① 断言本身是 mesa 无关的（A1 比的是 `night == quant(noon × _daylight)` 这个**比值**，基色现量），
#      所以危险不在判据，**在拍图那一步**：两个 runner README 的 apt 清单里**都没有 mesa/libgl1**，
#      于是 `--rendering-driver opengl3` 能不能拿到 GL context 是**未定义**的，且随 GitHub 每月滚镜像而变。
#   ② 一道**没有任何 commit 却会自己变色**的门，正是「在别人机器上因环境变红的门比没有门更坏」
#      要防的那一种——它训练所有人忽略红色。
#   ③ `auto` 档"拍不出帧就算 SKIP"**并不能**兜住这个：SKIP 与 PASS 在 CI 汇总里都读作"没红"，
#      于是这道门会退化成一枚**看不见结果的硬币**，同时还要在 15 分钟的 job 预算里烧掉两次 1280×768 软渲染。
#   ④ 跳过**没有损失任何已有的判别力**：docs/41 §2 的验证契约是"在开发机上跑 `bash tools/ci.sh`"，
#      那条路上 docker 镜像把 mesa 钉死、`tol=0` 逐字节——判别力最强的一档本来就在那里跑。
#      GHA 从来就没有过一个 **pin 死**的版本可以失去。
#   ⇒ 想在 GHA 上开它的人：显式给 `LT_VISUAL_RUNNER=native`（或 `LT_VISUAL=require`）即可越过这条自动跳过，
#     但**请先把 GL 栈 pin 住**（apt 装 `libgl1 libglx-mesa0` 并记下版本），否则你只是把硬币换了个地方扔。
#
# 其余判据不变：
#   * **能力探测在拍图之前**（有没有 pin 死的镜像 / 有没有 Xvfb），探不到 ⇒ 立刻 77 SKIP，一帧都不拍；
#   * 探到了就**必须给出判决**：拍不出图或断言不过 ⇒ 1 FAIL（这时候红色是真信号）；
#   * 唯一的例外是 native（未 pin）路径：见下面 `LT_VISUAL` 的 auto 档。
#
# 逐字节的颜色断言只有在**光栅器被钉死**时才可信：换一个 mesa 版本，软件光栅可能差 1 个 LSB。
# 所以 docker（镜像 pin 死 mesa）走 tol=0；native（未 pin）走 tol=4——而本门要挡的回归会让夜帧
# 从 (57,82,63) 跳回 (134,173,79)，**每通道差 77/91/16**，tol=4 一分判别力都不损失。
#
# ── 想在 GitHub Actions 上把它打开（**C4/D1 都没做，.github/ 不在这两棒的所有权表里**）──────
# 在 `.github/workflows/ci.yml` 的 "CI gate" 之前加一步，然后给 CI gate 那步加环境变量：
#     - run: sudo apt-get update && sudo apt-get install -y libgl1 libglx-mesa0   # xvfb 镜像自带，不必装
#     env:  LT_VISUAL_RUNNER: native    # ← 必须显式给，否则被下面的 GITHUB_ACTIONS 自动跳过挡掉
#           LT_VISUAL: require          # 想让它咬人才加；不加就是 auto（拍不出帧算 SKIP）
# **可信度**：native 分支已在 Ubuntu 22.04 + Xvfb + mesa 软件渲染下**实测跑通并 PASS**
# （在 gamecraft-runner 容器里以 native 模式跑，那条路上**没有 Pillow**，走的正是 stdlib PNG 读取器）。
# 但 **GitHub Actions 本身仍然没跑过**——第一次开它的人请先用 `LT_VISUAL`(auto) 观察一轮再升成 require，
# 并且**把 mesa 版本记进 workflow**：不 pin 光栅器，这道门的红色就不构成信号（见抬头②）。
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
# R2 室内外壳门要拍的 Space（四类各一 + library 撑 B 臂，理由见下面采集处）
# ★ S3 增拍 home2 与 shop（**两张都是判别力，不是冗余**，理由见下面采集处）。
INT_SPACES="${LT_VISUAL_INT_SPACES:-home home2 cafe shop wash work library}"

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
  # ── D7 的界外层重画门（同一个 Xvfb，省一次容器启动）──────────────────────
  # 为什么它在这里而不是自己一步：它和昼夜断言一样，**需要一个真 framebuffer**，
  # 于是也需要同一套「探不到就 SKIP、GHA 上显式跳过」的可移植性逻辑。
  # 它守的性质是 D7 那 9 倍帧时的【结构性根因】：**相机不动时，界外层不得随 tick 重画**。
  # ⚠️ 这道门存在，是因为 draw-call 数【判别不出】那个修复：2903 draws→83.3ms 与 2911 draws→11.1ms
  #    同样的 draw 数、7.5 倍的帧时差。真正的变量是「命令表是不是每帧重建」，不是它有多长。
  #    （所以 docs/46 的 R11 已按 D7 的实测改写：视觉棒要报的是**帧时**，draw 数只是线索。）
  if "$GBIN" --path "$GAME" --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
       --resolution ${W}x${H} --single-window -- --backend logic --seed "$SEED" --void-gate \
       >>/tmp/vg-godot.log 2>&1; then
    echo "  void-gate ok   (静态不重画 + settle 期真的画过 + 空间往返必重画)"
  else
    # rc=2 只在【帧确实拍出来了】时才设。原来无条件覆盖 ⇒ 拍不出帧 + 门也红时 rc 被改写成 2，
    # 于是打印「帧拍出来了，是这条性质破了」——而帧根本没拍出来。（2026-07-28 外部评审抓到，
    # 与 §二·八-③ 想修的是同一个病：**误导性的失败信息会把人送去查错误的方向**。）
    echo "  void-gate FAIL (见上面的 [VOIDGATE] 行)"; [ "$rc" -eq 0 ] && rc=2
  fi
  # ── E6/W7 的空间往返采集（同一个 Xvfb，省一次容器启动）────────────────────
  # 为什么它在这里而不是自己一步：与上面两条同理——它也需要一个真 framebuffer，
  # 于是也需要同一套「探不到就 SKIP、GHA 上显式跳过」的可移植性逻辑。
  # ⚠️ 它与 void-gate **不是**同一件事重做两遍：void-gate 量的是**计数器**（`_void_draws` 涨没涨），
  #    本步拍的是**像素**。评审那句「没有人看过空间切换之后的任何一帧」说的正是后者——
  #    重画被排上了、却画成一块纯色，计数器照样绿。判据在 tools/assert_space_roundtrip.py（宿主侧跑）。
  # 本步只负责**采集**：拍不出三帧 / 前提断言（出店取景复位）破了 ⇒ rc=3。
  # RT_OWN_XVFB=0：**复用上面这个 Xvfb**（再起一个会白烧一份 1280x768 软渲染，还多一个要收的进程）。
  if RT_OWN_XVFB=0 RT_GAME="$GAME" GODOT="$GBIN" \
       bash "$(dirname "$0")/space_roundtrip.sh" --shoot "$OUT" >>/tmp/vg-godot.log 2>&1; then
    echo "  space-roundtrip 采集 ok  (town_before → interior → town_after)"
  else
    echo "  space-roundtrip 采集 FAIL (见上面的 [SPACESHOT] 行)"; [ "$rc" -eq 0 ] && rc=3
  fi
  # ── R2 的室内外壳采集（同一个 Xvfb）────────────────────────────────────────
  # 判据在 tools/assert_interior_shell.py（宿主侧跑），本步只负责拍。
  # 为什么是这五栋：四种 areas[].type 各一栋（home=residential / cafe=commercial /
  # wash=public / work=workshop）**再加一栋 library**——library 与 wash 同为 public，
  # 它撑的是判据的 B 臂（同类必须相同）。只拍四栋的话，"给每栋楼各挑一个色"这种
  # 假修法会全绿通过。**第五张是判别力，不是冗余。**
  #
  # ★ S3 又加了两栋，同样是判别力（判据在 tools/assert_furniture_role.py）：
  #   · `home2` —— 与 `home` 同为住宅、架子该是同一个书架 ⇒ 它撑家具门的 **B 臂**
  #     （"同类必须相同"）。没有它，"按 space id 各挑一个画法"这种假修法全绿通过。
  #   · `shop`  —— **全镇唯一一间同层放了两个 `shelf` 的屋子** ⇒ 它撑家具门的 **C 臂**
  #     （同屋同 slot 逐像素一致），挡的是比 B 臂更细一档的"按家具实例哈希"。
  #     它同时也是 `store` 这一档物件（货架）在门里的唯一样本。
  #   顺带：这两张给 R2 的外壳门各多了一对**同类**对子（home2↔home 住宅、shop↔cafe 商业），
  #   即两道门都因此变严了一点，没有任何一道被放松。
  for sid in $INT_SPACES; do
    rm -f "$OUT/vg_int_${sid}.png"
    "$GBIN" --path "$GAME" --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
      --resolution ${W}x${H} --single-window -- \
      --backend logic --seed "$SEED" --warmup-tick "$NOON_TICK" \
      --probe-space "$sid" --probe-floor 1f --shot-fit --shot "$OUT/vg_int_${sid}.png" \
      >>/tmp/vg-godot.log 2>&1
    if [ -s "$OUT/vg_int_${sid}.png" ]; then echo "  shot ok   vg_int_${sid}.png"
    else echo "  shot FAIL vg_int_${sid}.png"; [ "$rc" -eq 0 ] && rc=4; fi
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

# ── GitHub Actions：显式跳过（理由见抬头「可移植性」，D1 更正）────────────────
# 必须放在能力探测【之前】：GHA 的 ubuntu-latest **自带 Xvfb**、workflow 又把 godot 放上了 PATH，
# 所以 have_native() 在那里为真、`auto` 会选 native —— 靠"探不到就跳过"是拦不住的（原设计的盲点）。
# 两条越权出口都保留：显式 LT_VISUAL_RUNNER=… 或 LT_VISUAL=require 都能越过这一条。
if [ "${GITHUB_ACTIONS:-}" = "true" ] && [ "$MODE" != "require" ] && [ -z "${LT_VISUAL_RUNNER:-}" ]; then
  skip "GitHub Actions —— 那里的 GL 栈（mesa/libgl）没有 pin，红/绿会随 GitHub 滚镜像自己变；判别力最强的一档在开发机的 docker 路径上（tol=0）。要在 GHA 上开：显式 LT_VISUAL_RUNNER=native 或 LT_VISUAL=require，并先 pin 住 mesa"
fi

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

# rc=2 是【void-gate 判定为红】，rc=3 是【空间往返采集失败】，rc=1 才是【拍不出帧】。必须分开：
# 2026-07-28 第一版把 1 和 2 混成一个 rc，于是 void-gate 变红时打印的是"渲染环境在位却拍不出帧"——
# 一条**指向错误方向**的诊断（帧其实拍出来了）。误导性的失败信息和假红一样坏：它让人去查环境。
# rc=3 是 2026-07-30 加的第三种，理由同上：它们的**修法完全不同**，混在一起就是把人送错方向。
if [ $SHOT_RC -eq 2 ]; then
  echo "  ❌ VISUAL GATE：界外层重画门变红（帧拍出来了，是这条性质破了）——见上面的 [VOIDGATE] 行"
  exit 1
fi
if [ $SHOT_RC -eq 3 ]; then
  echo "  ❌ VISUAL GATE：空间往返采集失败（昼夜两帧与 void-gate 都过了）——见上面的 [SPACESHOT] 行"
  exit 1
fi
if [ $SHOT_RC -eq 4 ]; then
  echo "  ❌ VISUAL GATE：室内帧采集失败（前面几步都过了）—— 见上面的 shot FAIL vg_int_* 行"
  exit 1
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
# 空间往返判据（E6/W7）。**故意跑在昼夜断言之后而不是短路**：两条门守的是不同的性质，
# 一条红了另一条的读数仍然有诊断价值（"界外带塌了" vs "整个昼夜尺子坏了"是两种完全不同的排查）。
"$PY" tools/assert_space_roundtrip.py "$OUT"
RRC=$?
# 岸线判据（G5 / docs/49 §七）。**不额外渲一帧**：吃的正是上面已经拍好的 vg_noon / vg_night
# ——它们已经是 `--shot-fit` 的整镇入画帧，正是 pond.py 需要的取景。
# 昼夜两帧都判：本棒实测过一版**只在白天绿、入夜就红**的判据（绝对亮度阈值），
# 一帧是不够的。同理跑在前两条之后而不短路（三条守的是不同性质）。
"$PY" tools/pond.py "$OUT/vg_noon.png" "$OUT/vg_night.png" --assert
PRC=$?
# 室内外壳类型门（R2 / docs/69）。同样**不短路**：它守的是第五条性质
# （"进屋之后这栋楼还得是这栋楼"），与上面四条各自独立，一条红了另几条的读数仍有诊断价值。
"$PY" tools/assert_interior_shell.py "$OUT" --game "$GAME"
IRC=$?
# 家具语义分化门（S3）。同样**不短路**：它守的是第六条性质（"架子上摆的东西得是这间屋子会有的"），
# 与上面五条各自独立——外壳门看【墙】、本门看【家具】，R2 的 does_not_detect 第二条明写外壳门
# 连地板都不看，家具更不在它眼里。吃的是上面已经拍好的 vg_int_*.png，**不额外渲一帧**。
"$PY" tools/assert_furniture_role.py "$OUT" --game "$GAME"
FRC=$?
# 树丛点阵门（V3 / 编号 86）。守第七条性质：**外景里唯一 100% 别名的那一层不许退回格子**
# （改前 156 棵树 = 1 种画法，逐格周期性残差 P = 0.180/0.133；改后 25.8/28.2）。
# ⚠️ V3 的接线说明写的是"再拍一帧整镇图"，**但那一帧已经拍过了**：
#   `vg_noon.png` / `vg_night.png` 本来就是 `--shot-fit` 的整镇入画帧（上面 pond.py 吃的就是它们）
#   ⇒ 复用，不额外渲——理由与 S3 让家具门吃 `vg_int_*.png` 是同一条。
# **昼夜两帧都判**：V3 在 72 次读数上标定过，**夜间是约束档**（改前上界 4.470 出现在夜里），
#   而 `visual_gate.sh` 的 fixture 写死正午 ⇒ 只判正午会把它标定得最紧的那一档漏掉。
"$PY" tools/assert_tree_stand.py --frame "$OUT/vg_noon.png"  --map "$GAME/data/map.json"; TRC=$?
"$PY" tools/assert_tree_stand.py --frame "$OUT/vg_night.png" --map "$GAME/data/map.json"; TRC2=$?
[ $TRC -eq 0 ] && TRC=$TRC2
[ $EPHEMERAL -eq 1 ] && rm -rf "$OUT"
[ $ARC -ne 0 ] && exit $ARC
[ $RRC -ne 0 ] && exit $RRC
[ $PRC -ne 0 ] && exit $PRC
[ $IRC -ne 0 ] && exit $IRC
[ $FRC -ne 0 ] && exit $FRC
exit $TRC
