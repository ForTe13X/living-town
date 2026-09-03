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

# ══ AK1：季节可分门（AF2）+ 降水可见门（AI1）要拍的帧 ════════════════════════════
# 都在下面 --shoot 的【同一个 Xvfb】里拍（省容器启动），判据在宿主侧【原地引用】
# analysis/af2/assert_season.py 与 analysis/ai1/assert_precip.py（不搬进 tools/：assert_season 按
# analysis/af2/ 逐级上溯 import tools/{assert_daynight,ciede2000}，搬走 import 路径就断）。
# ── 季节：seed3 的四个【晴天】× 昼夜 = 8 帧。纯 f(seed,day)，与 analysis/af2/run_season_gate.sh 的
#   PAIRS 逐值相同：春 gd2 / 夏 gd20 / 秋 gd35 / 冬 gd51；noon=(gd-1)*240+120，night=(gd-1)*240+8。
#   ⚠️ 必须晴天：天气罩（阴/雨）会把两季推蓝、拉近（assert_season 抬头证）。四季色是 f(季)、与 seed
#   无关（AF2 实测 seed 1/3/5 零方差）⇒ 单 seed(3) 标定在这道门上安全，且这句话是 AF2 证出来的。
SEASON_PAIRS="spring_noon:360 spring_night:248 summer_noon:4680 summer_night:4568 autumn_noon:8280 autumn_night:8168 winter_noon:12120 winter_night:12008"
# ── 降水：冬雪 + 非冬雨，各 on/off（off 用 --draw-skip 关该层 = 内建负对照）× 3 seed = 12 帧。
#   冬 tick 11160（游戏日47=冬，season 与 seed 无关 ⇒ 全 seed 下雪，密度随该 seed 当日 weather 变）；
#   雨为各 seed 最早的【非冬】雨日正午（都是春·雨，纯 f(seed,day)，见 analysis/ai1/run_precip_gate.sh）。
#   ★ 多 seed 展布（S3 教训）：雪密度随 weather 变（晴40/阴54/雨70）⇒ 三 seed 都拍、floor 恒在晴档；
#     雨零方差（coverage=f(map)、与 seed 无关，AI1 证）。阈值取自 AF2/AI1 已标定的地板，本棒不再收紧。
PRECIP_SEEDS="${LT_VISUAL_PRECIP_SEEDS:-1 3 5}"
WINTER_TICK=11160
rain_tick(){ case "$1" in 1) echo 600 ;; 3) echo 840 ;; 5) echo 1560 ;; *) echo 600 ;; esac; }

# ══ 模式 B：在渲染环境【内部】拍两帧 ════════════════════════════════════════
# 容器里用 `bash /tools/visual_gate.sh --shoot /out`；native 路径下同一份脚本原地跑。
# 写成"自我再入"而不是再开一个脚本，是为了让容器内外只有一份拍图参数——两份必然漂移。
check_cafe_player_meta() {
  local meta="$1"
  [ -s "$meta" ] || { echo "  cafe-player metadata missing: $meta"; return 1; }
  "$PY" - "$meta" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    m = json.load(f)
required = ("player_journey", "player_invited", "player_entered", "player_occupied_2f", "player_returned_1f", "player_returned", "cam_same")
bad = [f"{k}={m.get(k)!r}" for k in required if m.get(k) is not True]
if m.get("stairs_probe_only") is not False:
    bad.append(f"stairs_probe_only={m.get('stairs_probe_only')!r}")
if bad:
    print("  cafe-player metadata FAIL: " + ", ".join(bad))
    raise SystemExit(1)
print("  cafe-player metadata PASS: invited player occupied cafe/2f and returned; stairs_probe_only=false")
PY
}

# Registered fail-closed tooth for floor separation. It preserves the genuine
# full-journey metadata and every evidence frame except the task-owned 2F PNG.
floor_roundtrip_negative_self_test() {
  local positive="$1" negative="$2" log="$2/identical-frame.log" nrc=0 vrc=0
  rm -rf "$negative"
  mkdir -p "$negative"
  local f
  for f in rt_town_before.png rt_cafe_1f.png rt_cafe_2f.png rt_cafe_1f_back.png rt_town_after.png rt_meta.json; do
    cp "$positive/$f" "$negative/$f" || return 1
  done
  cp "$negative/rt_cafe_1f.png" "$negative/rt_cafe_2f.png" || return 1

  "$PY" tools/assert_floor_roundtrip.py "$negative" >"$log" 2>&1
  nrc=$?
  "$PY" - "$positive" "$negative" "$negative/negative-control.json" <<'PY'
import hashlib, json, pathlib, sys
src, neg, receipt = map(pathlib.Path, sys.argv[1:])
same = ("rt_town_before.png", "rt_cafe_1f.png", "rt_cafe_1f_back.png", "rt_town_after.png", "rt_meta.json")
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
checks = {name: digest(src / name) == digest(neg / name) for name in same}
checks["2f_equals_1f"] = digest(neg / "rt_cafe_2f.png") == digest(neg / "rt_cafe_1f.png")
data = {
    "schema": "living-town.floor-roundtrip.identical-frame-negative.v1",
    "mutation": "rt_cafe_2f.png := rt_cafe_1f.png",
    "metadata_sha256": digest(neg / "rt_meta.json"),
    "checks": checks,
}
receipt.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
if not all(checks.values()):
    raise SystemExit("floor negative changed evidence outside the registered pixel mutation")
PY
  vrc=$?
  if [ "$nrc" -ne 1 ] || [ "$vrc" -ne 0 ] \
     || [ "$(grep -c '^  PASS L\[' "$log")" -ne 5 ] \
     || ! grep -q '^  PASS A1\[map' "$log" \
     || ! grep -q '^  PASS A2\[' "$log" \
     || ! grep -q '^  FAIL B\[2F.*=0\.0000 ' "$log" \
     || ! grep -q '^  PASS C\[' "$log" \
     || ! grep -q '^=== FLOOR ROUNDTRIP GATE: FAIL (1) ===$' "$log" \
     || grep -Eq '^  FAIL (L|A|C)\[' "$log"; then
    echo "  floor-roundtrip identical-frame negative FAIL: expected B-only rc=1 at 0.0000 (got rc=$nrc verify_rc=$vrc)"
    cat "$log"
    return 1
  fi
  echo "  floor-roundtrip identical-frame negative PASS: metadata and companion frames preserved; B alone failed at 0.0000"
}

# The simple roundtrip has its own schema and is validated below by
# assert_space_roundtrip.py. Only the full floor journey owns the invited-player
# 2F evidence fields; keeping this routing explicit prevents schema bleed.
check_cafe_meta_scope() {
  local journey="$1" meta="$2"
  case "$journey" in
    simple) return 0 ;;
    full) check_cafe_player_meta "$meta" ;;
    *) echo "  cafe-player metadata scope invalid: $journey"; return 2 ;;
  esac
}

cafe_meta_contract_self_test() {
  local d="${TMPDIR:-/tmp}/lt-cafe-meta-contract-$$"
  mkdir -p "$d"
  printf '%s\n' '{"player_journey":true,"player_entered":true,"player_returned":true,"cam_same":true}' > "$d/simple.json"
  printf '%s\n' '{"player_journey":true,"player_entered":true,"player_returned":true,"cam_same":true,"stairs_probe_only":false}' > "$d/full_missing.json"
  printf '%s\n' '{"player_journey":true,"player_invited":true,"player_entered":true,"player_occupied_2f":true,"player_returned_1f":true,"player_returned":true,"cam_same":true,"stairs_probe_only":false}' > "$d/full_valid.json"
  printf '%s\n' '{"player_journey":true,"player_invited":true,"player_entered":true,"player_occupied_2f":true,"player_returned_1f":true,"player_returned":true,"cam_same":true,"stairs_probe_only":true}' > "$d/full_probe_only.json"

  check_cafe_meta_scope simple "$d/simple.json" || { echo "  cafe metadata contract FAIL: simple schema falsely rejected"; rm -rf "$d"; return 1; }
  if check_cafe_meta_scope full "$d/full_missing.json" > "$d/missing.log" 2>&1; then
    echo "  cafe metadata contract FAIL: full journey accepted missing fields"; rm -rf "$d"; return 1
  fi
  grep -q 'player_invited=None' "$d/missing.log" || { echo "  cafe metadata contract FAIL: missing-field tooth not observed"; rm -rf "$d"; return 1; }
  if check_cafe_meta_scope full "$d/full_probe_only.json" > "$d/probe.log" 2>&1; then
    echo "  cafe metadata contract FAIL: full journey accepted stairs_probe_only=true"; rm -rf "$d"; return 1
  fi
  grep -q 'stairs_probe_only=True' "$d/probe.log" || { echo "  cafe metadata contract FAIL: probe-only tooth not observed"; rm -rf "$d"; return 1; }
  check_cafe_meta_scope full "$d/full_valid.json" || { echo "  cafe metadata contract FAIL: valid full journey rejected"; rm -rf "$d"; return 1; }
  rm -rf "$d"
  echo "  cafe metadata contract PASS: simple schema remains scoped; full missing/probe-only fail; full valid passes"
}

check_clean_player_meta() {
  local meta="$1"
  [ -s "$meta" ] || { echo "  clean-player metadata missing: $meta"; return 1; }
  "$PY" - "$meta" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f: m = json.load(f)
p = m.get("clean_player_evidence", {})
checks = {
    "desktop.in_bounds": p.get("desktop", {}).get("in_bounds") is True,
    "mobile.in_bounds": p.get("mobile", {}).get("in_bounds") is True,
    "desktop.clean": p.get("desktop", {}).get("clean") is True,
    "mobile.clean": p.get("mobile", {}).get("clean") is True,
    "developer chrome": all(p.get("desktop", {}).get(k) is v for k, v in {
        "developer_chrome_hidden": True, "relationship_overlay": False, "navigation_overlay": False}.items()),
    "common input action": p.get("desktop", {}).get("touch_common_action") == "_player_do"
        and p.get("desktop", {}).get("keyboard_common_action") == "_player_do",
    "common revoke action": p.get("desktop", {}).get("touch_revoke_action") == "_player_return_cafe_pass"
        and p.get("desktop", {}).get("keyboard_revoke_action") == "_player_return_cafe_pass",
    "reduced motion": p.get("reduced_motion") is True,
    "revoked": p.get("revoke", {}).get("recorded") is True and p.get("revoke", {}).get("status") == "revoked",
    "persistent": all(p.get("persistence", {}).get(k) is True for k in ("save", "load_exact", "replay_exact")),
    "evidence negatives": all(p.get("negative_evidence", {}).get(k) is True for k in ("missing_rejected", "corrupt_rejected", "atomic")),
}
bad = [k for k, ok in checks.items() if not ok]
if bad:
    print("  clean-player metadata FAIL: " + ", ".join(bad)); raise SystemExit(1)
print("  clean-player metadata PASS: clean desktop/mobile + common inputs + reduced motion + revoke persistence + negative evidence")
PY
}

clean_player_contract_self_test() {
  local d="${TMPDIR:-/tmp}/lt-clean-player-contract-$$"
  mkdir -p "$d"
  printf '%s\n' '{}' > "$d/missing.json"
  printf '%s\n' '{"clean_player_evidence":{"desktop":{"clean":true,"in_bounds":true,"developer_chrome_hidden":true,"relationship_overlay":false,"navigation_overlay":false,"touch_common_action":"_player_do","keyboard_common_action":"_player_do","touch_revoke_action":"_player_return_cafe_pass","keyboard_revoke_action":"_player_return_cafe_pass"},"mobile":{"clean":true,"in_bounds":true},"reduced_motion":true,"revoke":{"recorded":true,"status":"revoked"},"persistence":{"save":true,"load_exact":true,"replay_exact":true},"negative_evidence":{"missing_rejected":true,"corrupt_rejected":true,"atomic":true}}}' > "$d/valid.json"
  if check_clean_player_meta "$d/missing.json" > "$d/missing.log" 2>&1; then
    echo "  clean-player contract FAIL: missing evidence accepted"; rm -rf "$d"; return 1
  fi
  grep -q 'desktop.in_bounds' "$d/missing.log" || { echo "  clean-player contract FAIL: missing-evidence tooth absent"; rm -rf "$d"; return 1; }
  check_clean_player_meta "$d/valid.json" || { rm -rf "$d"; return 1; }
  rm -rf "$d"
  echo "  clean-player contract PASS: missing fails closed; valid focused receipt passes"
}

if [ "${1:-}" = "--cafe-meta-contract-self-test" ]; then
  PY="${PYTHON:-python}" cafe_meta_contract_self_test
  exit $?
fi

if [ "${1:-}" = "--clean-player-contract-self-test" ]; then
  PY="${PYTHON:-python}" clean_player_contract_self_test
  exit $?
fi

if [ "${1:-}" = "--check-clean-player-meta" ]; then
  PY="${PYTHON:-python}" check_clean_player_meta "${2:-}"
  exit $?
fi

if [ "${1:-}" = "--clean-player-focused-manifest" ]; then
  ROOT="${2:-/out}"
  PY="${PYTHON:-python3}"
  "$PY" - "$ROOT" <<'PY'
import hashlib, json, os, pathlib, struct, sys
root = pathlib.Path(sys.argv[1])
expected = {k: os.environ.get("RT_" + k.upper(), "") for k in ("head", "tree", "game_tree", "parent")}
if any(not v for v in expected.values()): raise SystemExit("focused manifest: incomplete exact identity")
image = os.environ.get("RT_IMAGE", "")
if "@sha256:" not in image: raise SystemExit("focused manifest: image is not digest pinned")
def load(path):
    with path.open(encoding="utf-8") as f: return json.load(f)
def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""): h.update(chunk)
    return h.hexdigest()
def png_size(path):
    with path.open("rb") as f:
        if f.read(8) != b"\x89PNG\r\n\x1a\n": return (0, 0)
        length = struct.unpack(">I", f.read(4))[0]
        if f.read(4) != b"IHDR" or length < 8: return (0, 0)
        return struct.unpack(">II", f.read(8))
runs, container_ids = {}, set()
for arm, reduced in (("motion_on", True), ("motion_off", False)):
    d = root / arm
    status, meta = load(d / "focused-status.json"), load(d / "rt_meta.json")
    if status.get("identity") != expected: raise SystemExit(f"{arm}: identity mismatch")
    c = status.get("container", {})
    if c.get("image") != image or c.get("network") != "none": raise SystemExit(f"{arm}: image/network mismatch")
    if ":ro" not in c.get("mounts", "") or "tmpfs" not in c.get("scratch", ""): raise SystemExit(f"{arm}: mount/scratch isolation missing")
    if status.get("status", {}).get("exit_code") != 0: raise SystemExit(f"{arm}: nonzero status")
    cid = c.get("id", "")
    if not cid or cid in container_ids: raise SystemExit(f"{arm}: container not fresh")
    container_ids.add(cid)
    receipt = meta.get("reduced_motion_receipt", {})
    if receipt.get("enabled") is not reduced or receipt.get("pass") is not True: raise SystemExit(f"{arm}: reduced-motion receipt failed")
    if receipt.get("camera_changed") is reduced: raise SystemExit(f"{arm}: camera behavior inverted")
    negatives = meta.get("control_negatives", {})
    for action in ("invite", "revoke"):
        n = negatives.get(action, {})
        if n.get("disabled") is not True or n.get("disconnected") is not True or n.get("connection_count", 0) < 1:
            raise SystemExit(f"{arm}: {action} negative controls failed")
    proof = meta.get("clean_player_evidence", {})
    persistence = proof.get("persistence", {})
    if not all(persistence.get(k) is True for k in ("save", "load_exact", "replay_exact", "view_exact", "pixels_exact")):
        raise SystemExit(f"{arm}: persistence/view/pixel equivalence failed")
    state = persistence.get("state_before", {})
    if state.get("viewport") != [320, 192] or state.get("in_bounds") is not True or state.get("readable") is not True:
        raise SystemExit(f"{arm}: native layout/readability failed")
    captures = []
    for key, value in meta.items():
        if isinstance(value, dict) and "png" in value:
            p = d / pathlib.Path(value["png"]).name
            if png_size(p) != (320, 192) or value.get("native_source") is not True or value.get("post_capture_resize") is not False:
                raise SystemExit(f"{arm}: {key} is not a native 320x192 source PNG")
            captures.append(p.name)
    if len(captures) < 8: raise SystemExit(f"{arm}: incomplete reviewed capture set")
    runs[arm] = {"status_receipt_sha256": sha(d / "focused-status.json"),
        "meta_sha256": sha(d / "rt_meta.json"), "launch_command_sha256": status.get("launch_command_sha256", ""),
        "container_id": cid, "captures": sorted(captures), "reduced_motion": receipt,
        "cleanup": os.environ.get("RT_CLEANUP_" + arm.upper(), "")}
    if runs[arm]["cleanup"] != "absent": raise SystemExit(f"{arm}: auto-remove cleanup not observed")
reviewed = []
for p in sorted(root.rglob("*")):
    if p.is_file() and p.name != "focused-evidence-manifest.json" and p.suffix.lower() in (".png", ".log", ".json"):
        reviewed.append({"path": p.relative_to(root).as_posix(), "bytes": p.stat().st_size, "sha256": sha(p)})
for suffix in (".png", ".log"):
    found = {p.relative_to(root).as_posix() for p in root.rglob("*" + suffix)}
    hashed = {r["path"] for r in reviewed if r["path"].endswith(suffix)}
    if found != hashed: raise SystemExit(f"unhashed reviewed {suffix} files")
sources = {}
for label, p in {"game/scripts/Main.gd": pathlib.Path("/game/scripts/Main.gd"),
        "game/bench/SpaceShot.gd": pathlib.Path("/game/bench/SpaceShot.gd"),
        "tools/space_roundtrip.sh": pathlib.Path("/tools/space_roundtrip.sh"),
        "tools/visual_gate.sh": pathlib.Path("/tools/visual_gate.sh")}.items():
    sources[label] = {"bytes": p.stat().st_size, "sha256": sha(p)}
manifest = {"schema": "living-town.pr38-clean-player.focused-evidence.v1", "identity": expected,
    "reservation": os.environ.get("RT_RESERVATION", ""), "image": image,
    "host": {"client": os.environ.get("RT_HOST_CLIENT", ""), "server": os.environ.get("RT_HOST_SERVER", ""),
        "context": os.environ.get("RT_HOST_CONTEXT", ""), "platform": os.environ.get("RT_HOST_PLATFORM", "")},
    "runs": runs, "source_files": sources, "reviewed_files": reviewed,
    "does_not_prove": ["full tools/ci.sh", "complement ledger freshness", "visual art-floor acceptance", "remote PR or protection state"]}
out = root / "focused-evidence-manifest.json"
with out.open("w", encoding="utf-8", newline="\n") as f:
    json.dump(manifest, f, ensure_ascii=False, indent=2, sort_keys=True); f.write("\n")
print("  clean-player focused manifest PASS:", out, sha(out), "reviewed", len(reviewed))
PY
  exit $?
fi

if [ "${1:-}" = "--shoot" ]; then
  OUT="${2:-/out}"
  GAME="${VG_GAME:-/game}"
  GBIN="${GODOT:-godot}"
  DISP="${VG_DISPLAY:-:94}"
  export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 GODOT_SILENCE_ROOT_WARNING=1
  # AK1：硬化的拍帧封装（rc + 无致命日志标记 + 图非空，三者结合；理由见 tools/vg_shoot.sh 抬头）。
  # 下面每一处 godot 拍帧都改走 vg_shoot，不再是只看 `[ -s x.png ]` 的 fail-open。
  export VG_GODOT_LOG=/tmp/vg-godot.log
  . "$(dirname "$0")/vg_shoot.sh"
  Xvfb "$DISP" -screen 0 ${W}x${H}x24 -nolisten tcp >/tmp/vg-xvfb.log 2>&1 & XV=$!
  sleep 1.5
  export DISPLAY="$DISP"
  rc=0
  : >/tmp/vg-godot.log
  for pair in "night $NIGHT_TICK" "noon $NOON_TICK"; do
    nm="${pair%% *}"; tk="${pair##* }"
    vg_shoot "$OUT/vg_${nm}.png" --path "$GAME" --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
      --resolution ${W}x${H} --single-window -- \
      --backend logic --shot "$OUT/vg_${nm}.png" --seed "$SEED" --warmup-tick "$tk" --shot-fit \
      || rc=1
  done
  # P1-c：同 seed / 同 tick 的货船 ON/OFF 负对照。货船是 CargoManifest 的纯 View 投影，
  # 因此两帧除了 East Ocean 泊位里的 carrier 像素外必须相同；无 cargo 或永久装饰船都会判红。
  vg_shoot "$OUT/vg_noon_no_carrier.png" --path "$GAME" --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
    --resolution ${W}x${H} --single-window -- \
    --backend logic --shot "$OUT/vg_noon_no_carrier.png" --seed "$SEED" --warmup-tick "$NOON_TICK" --shot-fit --draw-skip carrier \
    || { [ "$rc" -eq 0 ] && rc=9; }
  # 产品集成参照：同一确定性到港时刻，把【真实 player agent】放在 East Ocean dock 陆格，
  # 以玩家为中心拍特写。它不是宣传图伪舞台：货船来自 ready manifest，底部 7 个动作按钮走真实
  # player_do 路径，NPC/观察台/HUD 也都是出货 UI。失败只表示参照帧没产出；玩法语义另由
  # player_touch_test + P1-b/P1-c focused contracts 守住。
  vg_shoot "$OUT/vg_player_east_ocean.png" --path "$GAME" --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
    --resolution ${W}x${H} --single-window -- \
    --backend logic --shot "$OUT/vg_player_east_ocean.png" --seed "$SEED" --warmup-tick "$NOON_TICK" \
    --player --player-pos 59 7 --select player \
    || { [ "$rc" -eq 0 ] && rc=10; }
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
  if RT_OWN_XVFB=0 RT_GAME="$GAME" RT_PLAYER_POS=41,19 GODOT="$GBIN" \
       bash "$(dirname "$0")/space_roundtrip.sh" --shoot "$OUT" >>/tmp/vg-godot.log 2>&1; then
    echo "  space-roundtrip 采集 ok  (town_before → interior → town_after)"
  else
    echo "  space-roundtrip 采集 FAIL (见上面的 [SPACESHOT] 行)"; [ "$rc" -eq 0 ] && rc=3
  fi
  # P1-i：真实 player 从东港门走进货仓并返回；另拍 status OFF 作为像素负对照。
  # 独立目录避免覆盖上面的 legacy cafe 三帧；两次共享 seed/tick 与 pinned framebuffer。
  mkdir -p "$OUT/warehouse" "$OUT/warehouse_off" "$OUT/warehouse_corrupt"
  if RT_OWN_XVFB=0 RT_GAME="$GAME" RT_SPACE=port_warehouse RT_PLAYER_POS=57,8 GODOT="$GBIN" \
       bash "$(dirname "$0")/space_roundtrip.sh" --shoot "$OUT/warehouse" >>/tmp/vg-godot.log 2>&1 \
     && RT_OWN_XVFB=0 RT_GAME="$GAME" RT_SPACE=port_warehouse RT_PLAYER_POS=57,8 RT_DRAW_SKIP=warehouse_status GODOT="$GBIN" \
       bash "$(dirname "$0")/space_roundtrip.sh" --shoot "$OUT/warehouse_off" >>/tmp/vg-godot.log 2>&1 \
     && RT_OWN_XVFB=0 RT_GAME="$GAME" RT_SPACE=port_warehouse RT_PLAYER_POS=57,8 RT_CORRUPT_MANIFEST=price_per GODOT="$GBIN" \
       bash "$(dirname "$0")/space_roundtrip.sh" --shoot "$OUT/warehouse_corrupt" >>/tmp/vg-godot.log 2>&1; then
    echo "  p1i/p1o-warehouse 采集 ok  (player 往返 + status ON/OFF + corrupt authority)"
  else
    echo "  p1i-warehouse 采集 FAIL (见上面的 [SPACESHOT] 行)"; [ "$rc" -eq 0 ] && rc=11
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
    vg_shoot "$OUT/vg_int_${sid}.png" --path "$GAME" --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
      --resolution ${W}x${H} --single-window -- \
      --backend logic --seed "$SEED" --warmup-tick "$NOON_TICK" \
      --probe-space "$sid" --probe-floor 1f --shot-fit --shot "$OUT/vg_int_${sid}.png" \
      || { [ "$rc" -eq 0 ] && rc=4; }
  done
  # ── AM1（编号133）：cafe 2F 像素门采集（同一个 Xvfb）──────────────────────────
  # 现役室内壳采集只拍 1f（上面 --probe-floor 1f 写死）⇒ cafe 2F 从没被任何门看过（docs/126 §一.2）。
  # 补拍 cafe 2F 两帧：正常 + `--draw-skip interior_furniture`（家具跳掉的【空 2F】= 真渲染负对照）。
  # 判据在宿主侧 tools/assert_cafe_2f.py（非空 + 与 1F 可分 + 空2F 会判红=有牙）。rc=7 专给它。
  # ⚠️ 命名【不用 vg_int_ 前缀】：那前缀会被 assert_interior_shell/assert_furniture_role 当成 space id
  #    globby 进去（cafe_2f 不是 space ⇒ 壳门会红）。1F 参照直接复用上面的 vg_int_cafe.png。
  vg_shoot "$OUT/vg_cafe2f.png" --path "$GAME" --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
    --resolution ${W}x${H} --single-window -- \
    --backend logic --seed "$SEED" --warmup-tick "$NOON_TICK" \
    --probe-space cafe --probe-floor 2f --shot-fit --shot "$OUT/vg_cafe2f.png" \
    || { [ "$rc" -eq 0 ] && rc=7; }
  vg_shoot "$OUT/vg_cafe2f_bare.png" --path "$GAME" --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
    --resolution ${W}x${H} --single-window -- \
    --backend logic --seed "$SEED" --warmup-tick "$NOON_TICK" \
    --probe-space cafe --probe-floor 2f --shot-fit --draw-skip interior_furniture --shot "$OUT/vg_cafe2f_bare.png" \
    || { [ "$rc" -eq 0 ] && rc=7; }
  # ── AM3（编号135）：全楼层往返门采集（同一个 Xvfb，省一次容器启动）──────────────
  # 现役空间往返门只走 town↔cafe/1f（上面那步）⇒ 楼梯往返（1f↔2f）没门（docs/126 §一.3）。
  # 本步走完整旅程 town→cafe/1f→上楼2f→下楼1f→出门（SpaceShot --rt-journey full，出货路径 tapped→_portal_click），
  # 拍 5 帧 + 逐段断言落在对的 Floor。判据在宿主侧 tools/assert_floor_roundtrip.py。rc=8 专给它。
  # RT_OWN_XVFB=0：复用上面这个 Xvfb（同 space-roundtrip 那步的理由）。写进 $OUT/floor 子目录，避免 rt_*.png 撞名。
  mkdir -p "$OUT/floor"
  if RT_OWN_XVFB=0 RT_JOURNEY=full RT_CLEAN_PLAYER=1 RT_GAME="$GAME" RT_PLAYER_POS=41,19 GODOT="$GBIN" \
       bash "$(dirname "$0")/space_roundtrip.sh" --shoot "$OUT/floor" >>/tmp/vg-godot.log 2>&1; then
    echo "  floor-roundtrip 采集 ok  (town→1f→上楼2f→下楼1f→town，逐段楼层对)"
  else
    echo "  floor-roundtrip 采集 FAIL (见上面的 [SPACESHOT] 行)"; [ "$rc" -eq 0 ] && rc=8
  fi
  # ── AK1：AF2 四季可分门的采集（同一个 Xvfb）——晴天四季 × 昼夜 8 帧 ─────────────
  # 判据在宿主侧 analysis/af2/assert_season.py（原地引用）。晴天 tick 是 f(seed3,day)，见抬头 SEASON_PAIRS。
  # 这批帧【不能复用】上面的 vg_noon/vg_night：那两帧只是 seed3 游戏日3=春，季节门要吃全四季。
  mkdir -p "$OUT/season"
  for item in $SEASON_PAIRS; do
    snm="${item%%:*}"; stk="${item##*:}"
    vg_shoot "$OUT/season/${snm}.png" --path "$GAME" --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
      --resolution ${W}x${H} --single-window -- \
      --backend logic --shot "$OUT/season/${snm}.png" --seed "$SEED" --warmup-tick "$stk" --shot-fit \
      || { [ "$rc" -eq 0 ] && rc=5; }
  done
  # ── AK1：AI1 降水可见门的采集（同一个 Xvfb）——冬雪 on/off + 非冬雨 on/off × 3 seed = 12 帧 ──
  # 判据在宿主侧 analysis/ai1/assert_precip.py（原地引用）。off 帧用 --draw-skip 关该层 = 内建负对照。
  mkdir -p "$OUT/precip"
  for s in $PRECIP_SEEDS; do
    rtk="$(rain_tick "$s")"
    vg_shoot "$OUT/precip/s${s}_winter_on.png"  --path "$GAME" --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
      --resolution ${W}x${H} --single-window -- \
      --backend logic --shot "$OUT/precip/s${s}_winter_on.png"  --seed "$s" --warmup-tick "$WINTER_TICK" --shot-fit \
      || { [ "$rc" -eq 0 ] && rc=6; }
    vg_shoot "$OUT/precip/s${s}_winter_off.png" --path "$GAME" --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
      --resolution ${W}x${H} --single-window -- \
      --backend logic --shot "$OUT/precip/s${s}_winter_off.png" --seed "$s" --warmup-tick "$WINTER_TICK" --shot-fit --draw-skip snow \
      || { [ "$rc" -eq 0 ] && rc=6; }
    vg_shoot "$OUT/precip/s${s}_rain_on.png"    --path "$GAME" --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
      --resolution ${W}x${H} --single-window -- \
      --backend logic --shot "$OUT/precip/s${s}_rain_on.png"    --seed "$s" --warmup-tick "$rtk"         --shot-fit \
      || { [ "$rc" -eq 0 ] && rc=6; }
    vg_shoot "$OUT/precip/s${s}_rain_off.png"   --path "$GAME" --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
      --resolution ${W}x${H} --single-window -- \
      --backend logic --shot "$OUT/precip/s${s}_rain_off.png"   --seed "$s" --warmup-tick "$rtk"         --shot-fit --draw-skip rain \
      || { [ "$rc" -eq 0 ] && rc=6; }
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

# Do not allow a capture with no real player journey to pass merely because
# SpaceShot omitted the optional player fields.
if [ -f "$OUT/rt_meta.json" ] && ! check_cafe_meta_scope simple "$OUT/rt_meta.json"; then
  [ "$SHOT_RC" -eq 0 ] && SHOT_RC=3
fi
if [ -f "$OUT/floor/rt_meta.json" ] && ! check_cafe_meta_scope full "$OUT/floor/rt_meta.json"; then
  [ "$SHOT_RC" -eq 0 ] && SHOT_RC=8
fi

# rc 分档（必须分开，否则失败信息指向错误方向 —— 误导性诊断和假红一样坏）：
#   1 昼夜两帧拍不出（含 vg_shoot 三信号任一不过：rc≠0 / 致命日志标记 / 空图）
#   2 void-gate 判红   3 空间往返采集失败   4 室内帧采集失败
#   5 季节四季帧采集失败（AK1）   6 降水帧采集失败（AK1）   7 cafe 2F 帧采集失败（AM1）
#   8 全楼层往返采集失败（AM3：某一跳没落在对的 Floor / 前提断言破了）
#   9 East Ocean 货船 OFF 负对照帧采集失败（P1-c）
#   10 玩家位于 East Ocean 码头的产品参照帧采集失败
#   11 P1-i 玩家货仓往返/状态负对照帧采集失败
# 2026-07-28 第一版把 1 和 2 混成一个 rc，于是 void-gate 变红时打印的是"渲染环境在位却拍不出帧"——
# 一条**指向错误方向**的诊断（帧其实拍出来了）。rc=3 是 2026-07-30 加的第三种，理由同上。
# rc=5/6 是 AK1（2026-08-06）加的第五、六种：季节/降水的采集失败与上面各步修法不同，分开报。
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
if [ $SHOT_RC -eq 5 ]; then
  echo "  ❌ VISUAL GATE：季节四季帧采集失败（前面几步都过了）—— 见上面的 shot FAIL season/* 行"
  exit 1
fi
if [ $SHOT_RC -eq 6 ]; then
  echo "  ❌ VISUAL GATE：降水帧采集失败（前面几步都过了）—— 见上面的 shot FAIL precip/* 行"
  exit 1
fi
if [ $SHOT_RC -eq 7 ]; then
  echo "  ❌ VISUAL GATE：cafe 2F 帧采集失败（前面几步都过了）—— 见上面的 shot FAIL vg_cafe2f* 行"
  exit 1
fi
if [ $SHOT_RC -eq 8 ]; then
  echo "  ❌ VISUAL GATE：全楼层往返采集失败（前面几步都过了）—— 见上面的 [SPACESHOT] 行（某一跳没落在对的 Floor / 前提断言破了）"
  exit 1
fi
if [ $SHOT_RC -eq 9 ]; then
  echo "  ❌ VISUAL GATE：East Ocean 货船负对照帧采集失败——见上面的 shot FAIL vg_noon_no_carrier.png 行"
  exit 1
fi
if [ $SHOT_RC -eq 10 ]; then
  echo "  ❌ VISUAL GATE：玩家 East Ocean 产品参照帧采集失败——见 shot FAIL vg_player_east_ocean.png 行"
  exit 1
fi
if [ $SHOT_RC -eq 11 ]; then
  echo "  ❌ VISUAL GATE：P1-i 玩家货仓往返/状态负对照帧采集失败——见 [SPACESHOT] 行"
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
# East Ocean 可见货船门（P1-c）。复用正午整镇帧，另吃同 tick 的 --draw-skip carrier 负对照；
# 判据同时守住“ready manifest 真可见”“零 cargo 不画永久船”“差异只落在泊位”三条性质。
"$PY" tools/assert_east_ocean_carrier.py "$OUT/vg_noon.png" "$OUT/vg_noon_no_carrier.png" --tol "$TOL"
CARC=$?
# 空间往返判据（E6/W7）。**故意跑在昼夜断言之后而不是短路**：两条门守的是不同的性质，
# 一条红了另一条的读数仍然有诊断价值（"界外带塌了" vs "整个昼夜尺子坏了"是两种完全不同的排查）。
"$PY" tools/assert_space_roundtrip.py "$OUT"
RRC=$?
# P1-i 玩家货仓：两条旅程分别守空间/玩家 receipt，再由 ON/OFF 门守实时账簿确实被渲染且只落在面板。
"$PY" tools/assert_space_roundtrip.py "$OUT/warehouse"
WRT1=$?
"$PY" tools/assert_space_roundtrip.py "$OUT/warehouse_off"
WRT2=$?
"$PY" tools/assert_p1i_warehouse.py "$OUT/warehouse" "$OUT/warehouse_off" --tol "$TOL"
WPRC=$?
"$PY" tools/assert_p1o_manifest_authority.py "$OUT/warehouse" "$OUT/warehouse_corrupt"
WMARC=$?
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
# 季节可分门（AF2 / 编号122，AK1 接线）。守第八条性质：**四季地面主色两两分得开**。
# 同样**不短路**：吃上面 season/ 里 8 帧晴天四季（noon+night 都判——夜是约束档，春↔夏夜里最紧 4.30；
# 只判正午会漏掉那一档）。判据在 analysis/af2/assert_season.py【原地引用】（它按 analysis/af2/ 上溯 import tools/）。
"$PY" analysis/af2/assert_season.py \
  --noon  "$OUT/season/spring_noon.png"  "$OUT/season/summer_noon.png"  "$OUT/season/autumn_noon.png"  "$OUT/season/winter_noon.png" \
  --night "$OUT/season/spring_night.png" "$OUT/season/summer_night.png" "$OUT/season/autumn_night.png" "$OUT/season/winter_night.png"
SEARC=$?
# 降水可见门（AI1 / 编号129，AK1 接线）。守第九条性质：**冬天真有落雪、雨真有雨丝**（on vs off coverage）。
# 同样**不短路**：吃上面 precip/ 里 12 帧（冬雪 on/off + 非冬雨 on/off × 3 seed）。判据在 analysis/ai1/assert_precip.py。
"$PY" analysis/ai1/assert_precip.py "$OUT/precip"
PPRC=$?
# cafe 2F 像素门（AM1 / 编号133）。同样**不短路**：守第十条性质（"多楼层里 2F 真被渲出家具、且与 1F 可分"）。
# 吃上面拍的 vg_cafe2f.png / vg_cafe2f_bare.png / vg_int_cafe.png（1F 参照复用壳门那张，不额外渲）。
# 负对照【就在判据内】：vg_cafe2f_bare 是 --draw-skip interior_furniture 的空 2F，A/C 两臂拿它自证有牙。
"$PY" tools/assert_cafe_2f.py "$OUT"
C2RC=$?
# 全楼层往返门（AM3 / 编号135）。同样**不短路**：守第十一条性质（"观察者能走完整旅程，逐段落在对的 Floor、
# 2F 那一跳真换平面、回程取景逐像素复位"）。吃上面 $OUT/floor 里的 5 帧；注册 identical-frame 负对照见下方。
# 家具跳过仍由 cafe 2F 像素门的 bare 帧证明有真实消费者，但不再冒充楼层分离的红齿。
# ⚠️ 它与 assert_space_roundtrip（town↔1f）**不重叠**：那条只走 1f，本条补的是楼梯往返（1f↔2f）+ 2F 判别力。
"$PY" tools/assert_floor_roundtrip.py "$OUT/floor"
FLRC=$?
floor_roundtrip_negative_self_test "$OUT/floor" "$OUT/floor_negative_identical"
FNRC=$?
[ $EPHEMERAL -eq 1 ] && rm -rf "$OUT"
[ $ARC -ne 0 ] && exit $ARC
[ $CARC -ne 0 ] && exit $CARC
[ $RRC -ne 0 ] && exit $RRC
[ $WRT1 -ne 0 ] && exit $WRT1
[ $WRT2 -ne 0 ] && exit $WRT2
[ $WPRC -ne 0 ] && exit $WPRC
[ $WMARC -ne 0 ] && exit $WMARC
[ $PRC -ne 0 ] && exit $PRC
[ $IRC -ne 0 ] && exit $IRC
[ $FRC -ne 0 ] && exit $FRC
[ $SEARC -ne 0 ] && exit $SEARC
[ $PPRC -ne 0 ] && exit $PPRC
[ $C2RC -ne 0 ] && exit $C2RC
[ $FLRC -ne 0 ] && exit $FLRC
[ $FNRC -ne 0 ] && exit $FNRC
exit $TRC
