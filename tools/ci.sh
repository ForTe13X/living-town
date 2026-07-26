#!/usr/bin/env bash
# Living Town CI — runs locally and in GitHub Actions. Fails (exit 1) on any red step.
#   GODOT     path to the Godot 4.6.2 headless binary (default: godot on PATH)
#   CI_SEEDS  S0 seed range (default 1-12)      CI_DAYS  S0 days (default 60)   CI_DET  det seeds (default 3)
#   CI_BG_SEEDS/CI_BG_DAYS/CI_BG_N  4d 外部后端门 (default 1-4 / 8 / 12)
# Fast local plumbing check: CI_SEEDS=1-3 CI_DAYS=30 bash tools/ci.sh
#   （原注释写的是 CI_DAYS=20 —— 实测在【改动之前的树上就已经是红的】：软不变量 #08「承诺生命周期」
#     在 20 天里 0/3（invite→meet 的赴约要更长的 horizon），所以那条"快跑"从来跑不绿。30 天是实测最近的绿点。
#     注意 CI_DAYS≠60 时金标无可比行（摘要与天数绑定），会打印"0 条可比"——快跑只查管路，不构成跨进程锚。）
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
CI_SEEDS="${CI_SEEDS:-1-12}"; CI_DAYS="${CI_DAYS:-60}"; CI_DET="${CI_DET:-3}"
# 日志目录按【本仓库路径 + PID】隔离：多 worktree 并行跑 CI 时，固定的 /tmp/lt_*.log 会互相覆盖——
# 判定本身走 PIPESTATUS 不受影响，但 scan 步骤会去读【别人的】日志，误报/漏报都可能（B10 实测踩到）。
LT_LOG="${LT_LOG:-/tmp/lt-$(printf '%s' "$PWD" | tr -c 'A-Za-z0-9' '_' | tail -c 40)-$$}"
mkdir -p "$LT_LOG"
PY="${PYTHON:-python}"
FAIL=0
ok(){ echo "  ✅ $1"; }
bad(){ echo "  ❌ FAIL: $1"; FAIL=1; }

# ── 运行期错误哨兵 ──────────────────────────────────────────────────────────
# 为什么需要：GDScript 的 push_error() / SCRIPT ERROR 【不改变进程退出码】。
# 例：Sim.gd:304 在数据文件缺失时 push_error("缺数据文件: ...") 然后继续跑——整条 CI 依旧全绿。
# 所以每个【运行期】步骤（4 / 4b / 4c / 5）的输出都必须做模式扫描，只靠 exit code 是不够的。
# 白名单只有一条：NobodyWho（端侧 SLM）的 GDExtension 动态库是【故意不入库】的（红线#4：不分发权重/二进制），
#   于是 headless 每次启动必打这 4 行 ERROR。除此之外任何 ERROR/SCRIPT ERROR/USER ERROR 一律致命。
ERR_PAT='SCRIPT ERROR|USER ERROR|Parse Error|Failed to load script|ERROR:'
ERR_OK='nobodywho|GDExtension|open_dynamic_library|load_extensions|Condition "!FileAccess::exists\(path\)" is true'
scan(){  # scan <label> <logfile> [额外白名单正则]
  local allow="$ERR_OK"
  [ $# -ge 3 ] && allow="$allow|$3"
  local hits
  hits=$(grep -aE "$ERR_PAT" "$2" 2>/dev/null | grep -avE "$allow")
  if [ -n "$hits" ]; then echo "$hits" | head -12; bad "$1 (运行期错误行，见上)"; fi
}

echo "### 0. 版权红线：git 里不得有模型权重 / 预编译二进制"
# 红线#4。.gitignore 今天只挡 game/models/*.gguf —— 换个目录放权重就会被静默入库。
# 这里对【整棵已跟踪树】把关，而不是对某个目录。
BIN_TRACKED=$(git ls-files | grep -iE '\.(gguf|so|dll|bin|safetensors|pt)$')
if [ -n "$BIN_TRACKED" ]; then
  echo "$BIN_TRACKED" | head -20; bad "tracked weights/binaries (红线#4：权重与二进制一律不入库)"
else ok "no tracked weights/binaries"; fi

echo "### 1. data lint (json parse + foreign keys + 必需数据文件在位)"
"$PY" tools/lint_data.py && ok "lint_data" || bad "lint_data"

echo "### 1b. map audit (town-world 导航自洽：typed-layers 一致 + 全可达 + 每家具有交互格 + ≥2 路线)"
"$PY" tools/audit_map.py && ok "audit_map" || bad "audit_map"

echo "### 2. link lint (markdown relative links)"
"$PY" tools/lint_links.py && ok "lint_links" || bad "lint_links"

echo "### 3. godot import + parse smoke"
"$GODOT" --headless --path game --import >"$LT_LOG/import.log" 2>&1 || true
if grep -qiE 'SCRIPT ERROR|Parse Error|Failed to load script' "$LT_LOG/import.log"; then
  grep -iE 'SCRIPT ERROR|Parse Error|Failed to load script' "$LT_LOG/import.log" | head; bad "godot parse"
else ok "import/parse clean"; fi

echo "### 4. S0 gate (invariants + determinism + 金标; seeds=$CI_SEEDS days=$CI_DAYS det=$CI_DET)"
# --golden：跨进程/跨提交/跨引擎版本锚（红线#1）。没有它，CI 只证明「同一二进制同一进程内跑两次一样」。
"$GODOT" --headless --path game --script res://bench/Harness.gd -- \
  --seeds "$CI_SEEDS" --days "$CI_DAYS" --det "$CI_DET" \
  --golden game/bench/golden_digests.json 2>&1 | tee "$LT_LOG/s0.log"
[ "${PIPESTATUS[0]}" -eq 0 ] && ok "S0 gate" || bad "S0 gate"
scan "S0 gate" "$LT_LOG/s0.log"

echo "### 4b. LOD 观察无关红线 (V2 相机路径无关 + V3 确定性/存读/fresh-restart)"
# 永久门：aggregate LOD 的 cohort 必须【只由 committed sim 态】选、绝不读相机 lod_focus。
# 若日后有人把 cohort 从相机取回，V2(5 个 lod_focus→同 digest) 立即变红（Main.gd:159 红线机器化）。
"$GODOT" --headless --path game --script res://bench/lod_verify.gd -- "${CI_LOD_N:-48}" "${CI_LOD_DAYS:-3}" 2>&1 | tee "$LT_LOG/lod.log"
[ "${PIPESTATUS[0]}" -eq 0 ] && ok "LOD viewer-independence gate" || bad "LOD viewer-independence gate"
scan "LOD gate" "$LT_LOG/lod.log"

echo "### 4c. DetGate 场景确定性门 (default / faction / betray / freerider)"
# Invariants.gd:15 对任何非空 scenario 豁免硬不变量 #1，且 Harness 没有 --scenario ——
# 在此门落地之前，三条内置定向场景在 CI 里跑过 0 次（docs/17 早就开了这个方子）。
"$GODOT" --headless --path game --script res://bench/DetGate.gd -- \
  --seeds "${CI_DG_SEEDS:-1-4}" --days "${CI_DG_DAYS:-20}" 2>&1 | tee "$LT_LOG/detgate.log"
[ "${PIPESTATUS[0]}" -eq 0 ] && ok "DetGate scenario determinism" || bad "DetGate scenario determinism"
scan "DetGate" "$LT_LOG/detgate.log"

echo "### 4d. BackendGate 外部后端硬不变量门 (#01「无饿穿」在【模型/随机后端挑】的那条路上)"
# 为什么必须单独有这一步：上面每一道门（金标 / LOD / DetGate）都恒 Sim.backend=null（红线#2 的零模型地板）
# ⇒ AIBackend.decide() 从不被调用 ⇒ 硬不变量 #01 只在【引擎自己挑】的路径上验过。
# docs/38 §五 实测：同一份配置下 logic 0/8 seed 饿穿，random/slm 都是 8/8 —— CI 全绿与产品已破可以同时成立。
# 用 random 而不是 slm：random 的选号来自 Sim._rng_at(RANDOM_SALT) 确定性流、时延按 tick 计，逐字节可重跑
#   （本门自己把这条性质机检了：每个 seed 跑两遍比 digest/链）；slm 有 run-to-run 噪声，永远不进 CI。
#   两条臂走的是【同一条落地路】(decide→闭集选号→重验→agent_apply)，故这条路上的护栏一旦立住，两者同时受保护。
"$GODOT" --headless --path game res://bench/BackendGate.tscn -- \
  --seeds "${CI_BG_SEEDS:-1-4}" --days "${CI_BG_DAYS:-8}" --agents "${CI_BG_N:-12}" 2>&1 | tee "$LT_LOG/backendgate.log"
[ "${PIPESTATUS[0]}" -eq 0 ] && ok "BackendGate 外部后端 #01 门" || bad "BackendGate 外部后端 #01 门"
scan "BackendGate" "$LT_LOG/backendgate.log"

echo "### 4e. ModelPathGate 出货 prompt 编码门 (闭集编号字母表 / 示例编号 / 裁剪保序)"
# 为什么和 4d 分开：4d 守的是【落地之后】的世界（硬不变量 #01、两跑一致），
# 4e 守的是【问出去之前】那一份 prompt 的编码性质——docs/42 量到的三条病都活在这里：
#   ① 系统 prompt 里的字面示例编号把三成决策焊在一个候选位上；
#   ② 字符 '0' 的先验让模型从不选 0 号槽，而 index 0 有 74.84% 是吃饭/睡觉 ⇒ 系统性跳过维生动作；
#   ③ 裁剪路径若按 score 重排候选，会把引擎 argmax 顶到首位——那正是 docs/42 §9-4 判定
#      bench/log_decisions.gd 不可用于位置研究的同一个混淆，且它会悄悄抵消 ① ② 的修复。
# 允许 'Parse JSON failed'：fail-closed 规则下模型回 prose 会先撞 JSON 兼容路，同 m2_test 的既有豁免。
"$GODOT" --headless --path game res://bench/ModelPathGate.tscn -- \
  --seeds "${CI_MP_SEEDS:-1-4}" --days "${CI_MP_DAYS:-8}" --agents "${CI_MP_N:-12}" 2>&1 | tee "$LT_LOG/modelpath.log"
[ "${PIPESTATUS[0]}" -eq 0 ] && ok "ModelPathGate 模型路径编码门" || bad "ModelPathGate 模型路径编码门"
scan "ModelPathGate" "$LT_LOG/modelpath.log" 'Parse JSON failed'

echo "### 5. unit / integration scenes"
for scene in m2_test reqlife_test player_agency_test s4_replay_test space_test save_load_test; do
  "$GODOT" --headless --path game "res://scenes/$scene.tscn" >"$LT_LOG/$scene.log" 2>&1
  code=$?
  if [ $code -eq 0 ]; then ok "$scene"; else tail -8 "$LT_LOG/$scene.log"; bad "$scene (exit $code)"; fi
  case "$scene" in
    # m2_test 是【负例测试】：故意把畸形 JSON 喂给 AIBackend.parse_decision(:560) 验证它拒收，
    # 引擎因此必打两行 "Parse JSON failed"。这是被断言的行为，不是回归 → 只对本场景放行这一条。
    m2_test) scan "$scene" "$LT_LOG/$scene.log" 'Parse JSON failed' ;;
    *)       scan "$scene" "$LT_LOG/$scene.log" ;;
  esac
done

echo "### 6. 昼夜量具视觉门（本仓库第一条【视觉】断言 —— 无渲染环境时自动 SKIP，不假红）"
# 为什么是这一条先进 CI：docs/41 §6 盲区④——`--shot` 曾经【永远渲不出昼夜】，
# 于是【这个项目所有视觉判断用的尺子】是坏的（"偏亮/偏暗"的结论全部不可信）。C3 用 Main.gd:271 一行修好了它，
# 而在此之前没有任何门守着那一行：把它删掉，上面 0-5 每一步都照样全绿。
#
# ⚠️ 它跟前面五步不一样：**需要一个能真的出图的渲染环境**（pin 死的 gamecraft-runner 镜像，或 Xvfb+godot）。
# GitHub Actions 的 ubuntu-latest 两样都没有 ⇒ 那条路上本步 **SKIP**，不计入 FAIL。
# 这是蓄意的：**一道在别人机器上因环境变红的门比没有门更坏**——它训练所有人忽略红色。
# 判据都在 tools/visual_gate.sh 抬头；想让它必须跑（例如宿主 CI）：`LT_VISUAL=require bash tools/ci.sh`。
bash tools/visual_gate.sh 2>&1 | tee "$LT_LOG/visual.log"
VRC="${PIPESTATUS[0]}"
case "$VRC" in
  0)  ok "DayNight 视觉门" ;;
  77) echo "  ⏭  SKIP: DayNight 视觉门（本机没有渲染环境；LT_VISUAL=require 可让它变红）" ;;
  *)  bad "DayNight 视觉门 (exit $VRC)" ;;
esac

echo
[ $FAIL -eq 0 ] && echo "=== CI PASS ✅ ===" || echo "=== CI FAIL ❌ ==="
exit $FAIL
