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
# 所以每个【运行期】步骤（4 / 4b / 4c / 4d / 4e / 5）的输出都必须做模式扫描，只靠 exit code 是不够的。
#
# ── 白名单纪律（2026-07-26 D1 收窄）────────────────────────────────────────
# 唯一合法的噪声是 NobodyWho（端侧 SLM）GDExtension 的开场白：红线#4 不许 .so/.dll 入库，于是
# `--import` 之后【每一次】godot 启动都固定打这 4 行（实测：--script 与 scene 两种模式都恰好 4 行）。
# 旧白名单是 `nobodywho|GDExtension|open_dynamic_library|load_extensions|Condition "!FileAccess::exists(path)" is true`，
# 按【裸子串】放行，于是那条 Condition 把**每一个被扫步骤里的任何 FileAccess::exists 失败**都遮住了
# ——数据文件、场景、存档、资源缺失全在内（docs/43 §1.2j-④ 点的名）。现在改成【绑上下文】：
#   · 两行指名 nobodywho ⇒ 按名放行。换成别的扩展缺失，名字对不上 ⇒ 红。
#   · 两行是裸的 Condition ⇒ 只在它紧随的 "at:" 行是 `open_dynamic_library` 时放行；
#     且任何多出来的缺失动态库都会同时产生一条【指名】的 "not found: '<path>'" ⇒ 那条名字对不上 ⇒ 红。
#     （全仓库 .gd 里没有任何 `OS.open_dynamic_library` 调用，故不存在"只有裸行、没有指名行"的路径。）
# 额外白名单（第 3 参）现在必须带【预期条数】（第 4 参）：放行的是**被断言的那一条**，不是这个模式的所有出现。
ERR_PAT='SCRIPT ERROR|USER ERROR|Parse Error|Failed to load script|ERROR:'
ERR_OK='(GDExtension dynamic library not found|Error loading extension): .res://addons/nobodywho/|Condition "!FileAccess::exists\(path\)" is true\..* at: open_dynamic_library '

# Godot 的一条错误占两行（"ERROR: ..." + "   at: fn (file:line)"）。把它们拼成一条记录再过滤，
# 白名单才可能要求上下文。顺带去掉 CRLF 的 \r（Windows 上的 godot 写的是 \r\n）。
pair_errs(){ awk -v P="$ERR_PAT" '{ gsub(/\r/,""); l[NR]=$0 }
  END { for (i=1;i<=NR;i++) if (l[i] ~ P) { r=l[i]; if (l[i+1] ~ /^[ \t]*at: /) r = r " " l[i+1]; print r } }' "$1"; }

scan(){  # scan <label> <logfile> [额外白名单正则] [该正则的预期条数]
  local extra="${3:-}" want="${4:-}" hits n
  hits=$(pair_errs "$2" 2>/dev/null | grep -avE "$ERR_OK")
  if [ -n "$extra" ]; then
    n=$(printf '%s\n' "$hits" | grep -acE "$extra")
    hits=$(printf '%s\n' "$hits" | grep -avE "$extra")
    if [ -n "$want" ] && [ "$n" -ne "$want" ]; then
      bad "$1 (白名单 '$extra' 出现 $n 次，预期恰好 $want 次 —— 多了=新的未解释错误，少了=那条被断言的负例没跑到)"
    fi
  fi
  hits=$(printf '%s' "$hits" | grep -av '^[[:space:]]*$')
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

echo "### 2b. art gate (出货 game/assets/art/pro 必须等于 coif_characters.py 当场重建的结果)"
# 为什么现在才有这一步（docs/49 §〇）：在它之前，本文件里【没有任何一处】提到 assets / art / palette /
# coif / deprop —— 唯一的字面命中是上面 4b 那行 `fresh-rest**art**` 里的三个字母。
# ⇒ 十张出货角色表是这个仓库唯一一类"改了没有任何门会响"的资产，而它同时是玩家唯一直接看得见的东西。
# 删一张、被 deprop 覆盖一张、手改一个像素——步骤 0-6 每一步都照样全绿。
#
# 判据不是"校验和清单对得上"（那种门可以靠更新清单通过，而更新清单正是偷改像素的人下一步会做的事），
# 是**当场从 library/ 重新生成、再逐字节比对**。
# ⚠️ 硬判据只认**解码后的 RGBA 像素**；PNG 容器字节只打印不判红（它随 zlib/Pillow 版本走，
#    而"一道在别人机器上因环境变红的门比没有门更坏"——理由与下面第 6 步同源）。
#
# 负对照（G1 实测，全部亲眼看着变红，见 docs/49 §一 验收 1/2）：
#   ① 单独跑 deprop_characters.py（已知的静默回退路径）⇒ 9/10 张红（Character-Base 它不写，故绿）；
#      逐张 13542-17508 px 不同，其中 832-1094 px 落在 12 个可达帧上。
#   ② 某张表某个像素蓝通道 +1（能做的最小改动）⇒ 红，指名 Soldier-Yellow 表内(46,14)。
#   ③ 删一张 ⇒ "缺 1 张"；④ 塞一张管线生成不出来的 ⇒ "多出 1 张"；
#   ⑤ 把重建源头指向 pro/（coif :444 记过的 x→x 退化）⇒ "抄答案不是重建"；
#   ⑥ 把比对器改成恒返回"一样" ⇒ 门内每次都跑的 1px 判别力自检把它抓住。
# ⚠️ 它需要 Pillow。装不上就没有这道门 ⇒ 直接红，不做 SKIP：
#    SKIP 与 PASS 在汇总里都读作"没红"，那会把这道门退化成一枚看不见结果的硬币（visual_gate.sh 抬头③）。
"$PY" tools/art_gate.py && ok "art gate（出货 pro/ == 当场重建）" || bad "art gate（出货 pro/ != coif_characters.py 当场重建的结果）"

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

echo "### 4d. BackendGate 外部后端门 (硬不变量含#01 / 同seed两跑一致 / 闭集封闭)"
# 为什么必须单独有这一步：上面每一道门（金标 / LOD / DetGate）都恒 Sim.backend=null（红线#2 的零模型地板）
# ⇒ AIBackend.decide() 从不被调用 ⇒ 硬不变量 #01 只在【引擎自己挑】的路径上验过。
# docs/38 §五 实测：同一份配置下 logic 0/8 seed 饿穿，random/slm 都是 8/8 —— CI 全绿与产品已破可以同时成立。
# 用 random 而不是 slm：random 的选号来自 Sim._rng_at(RANDOM_SALT) 确定性流、时延按 tick 计，逐字节可重跑
#   （本门自己把这条性质机检了：每个 seed 跑两遍比 digest/链）；slm 有 run-to-run 噪声，永远不进 CI。
#   两条臂走的是【同一条落地路】(decide→闭集选号→重验→agent_apply)，故这条路上的护栏一旦立住，两者同时受保护。
#   ⚠ 2026-07-30（E6/W5）收窄：上面这句**对 A/B 成立，对 C 不成立**。`random`/`slm` 结构上
#     都只能交回 `candidates` 的子集（`_instant_random` 挑下标 / `parse_decision` 取 `candidates[pk]`），
#     ⇒ C 的 escape 数在这两条臂上**恒为 0**，"闭集 1332/1332 ✅"是恒真、不是证据。
# 三条臂 + 一条自检臂（2026-07-26 D1 起，此前第三条是假的——它与第一条的 #01 逐位同一个谓词）：
#   A 硬不变量全绿  B 同 seed 两跑 digest/事件/逐tick前缀链一致  C 闭集封闭（后端交回的 intent 必在本次候选里）
#   S 自检臂 `inject:fabricate`（**只在门内部**，绝不进出货路径）：一个会篡改 `amount` 的假后端，
#     判据是**反的**——C 必须变红。它给 C 补上此前缺的那半：**注入时红、不注入时绿**。
#     实测（seeds 1-4 × 8 天）：伪造 141-147 次、探针恰好抓到 141-147 次、其中 109-116 次被
#     `agent_apply` **原样落地** ⇒ 下面那句"引擎自己不强制它"从此是量出来的，不是推的。
# C 守的是红线#2 的后半句，而【引擎自己不强制它】：Sim.gd:1185-1201 只做生存/视野否决，
#   一个凭空捏造的 intent 只要不违反生存否决就会被 agent_apply 原样落地。
#   ⇒ C 是一道**回归门**（守未来任何新后端 / `parse_decision` 的改写），**不是**"现有后端已被验过"的证书。
"$GODOT" --headless --path game res://bench/BackendGate.tscn -- \
  --seeds "${CI_BG_SEEDS:-1-4}" --days "${CI_BG_DAYS:-8}" --agents "${CI_BG_N:-12}" 2>&1 | tee "$LT_LOG/backendgate.log"
[ "${PIPESTATUS[0]}" -eq 0 ] && ok "BackendGate 外部后端门（硬不变量/两跑一致/闭集封闭）" || bad "BackendGate 外部后端门（硬不变量/两跑一致/闭集封闭）"
scan "BackendGate" "$LT_LOG/backendgate.log"

echo "### 4e. ModelPathGate 出货 prompt 编码门 (闭集编号字母表 / 示例编号 / 裁剪保序)"
# 为什么和 4d 分开：4d 守的是【落地之后】的世界（硬不变量 #01、两跑一致），
# 4e 守的是【问出去之前】那一份 prompt 的编码性质——docs/42 量到的三条病都活在这里：
#   ① 系统 prompt 里的字面示例编号把三成决策焊在一个候选位上；
#   ② 字符 '0' 的先验让模型从不选 0 号槽，而 index 0 有 74.84% 是吃饭/睡觉 ⇒ 系统性跳过维生动作；
#   ③ 裁剪路径若按 score 重排候选，会把引擎 argmax 顶到首位——那正是 docs/42 §9-4 判定
#      bench/log_decisions.gd 不可用于位置研究的同一个混淆，且它会悄悄抵消 ① ② 的修复。
# 允许 'Parse JSON failed'【恰好 1 次】：那是 A 段最后一条断言（prose fail-closed）故意喂 "A 去 eat"，
#   引擎在 JSON 兼容路上必打的一行（AIBackend.gd:886）。多一次 = 新的、没人解释过的错误；
#   少一次 = 那条负例断言已经不再跑到那条路上（门悄悄少了一条），两边都该红。
# C 段现在比对提交锚 game/bench/modelpath_anchor.json（此前它零条断言、只 print digest）。
#   锚移动了且是蓄意的 → --bake-anchor 重烘并在 _meta.rebake_history 里补一条原因（docs/41 §3）。
"$GODOT" --headless --path game res://bench/ModelPathGate.tscn -- \
  --seeds "${CI_MP_SEEDS:-1-4}" --days "${CI_MP_DAYS:-8}" --agents "${CI_MP_N:-12}" 2>&1 | tee "$LT_LOG/modelpath.log"
[ "${PIPESTATUS[0]}" -eq 0 ] && ok "ModelPathGate 模型路径编码门" || bad "ModelPathGate 模型路径编码门"
scan "ModelPathGate" "$LT_LOG/modelpath.log" 'Parse JSON failed' 1

echo "### 4f. VoiceGate 台词覆盖门 (每个被 offer 的候选动作都要有本人格的话可说)"
# 为什么需要它：F4 普查出 14 个动作在【任何】人格下都没有台词 = 111 对 (人格,动作) 让
#   _canned_say 返回空串，而当时没有任何一道门会响。更阴的是它不表现为沉默——
#   WorldView._set_dialogue 在 last_say 为空时回落到 DIALOG[type]，屏幕上照样有气泡，
#   只是 12 个人共用一套 12 行通用词。缺陷是【人格声音丢失】，不是哑巴。
# 口径取【被 offer 的候选】而不是【被选中的那一个】：台词只在动作被选中时上屏，
#   但候选一旦能被选中就可能上屏；只查被选中的那个，门的判别力会随机波动。
# 网格 1-3 x 60 天是量出来的：60 天才见得全 31 个可选动作，20 天的网格漏 3 个
#   （详见 game/bench/VoiceGate.gd 抬头的覆盖表与 docs/48 第七节）。
# 覆盖地板是【结构性】的，不是数量：阵容里出现过的每个人格都必须真的被枚举到过。
#   2026-07-30 外审（指令"尽力反驳"）判定原来那个 --min-pairs 250 是四条结论里最弱的一条：
#   250 与实测 293 之间没有理论依据（只是 85%），而且"数量不是语义"。
#   实测坐实了它的反例：让一个人格从此不被枚举，在 CI 这一格上仍有 271 对 > 250 ⇒ 旧地板放行；
#   结构判据当场变红并点名 [hai]。删掉一个岗位则阵容与枚举同时少掉 ⇒ 不假红。没有魔数。
# 它上线当天就考了一次真的：F5 新增 打渔/授课/劈柴 三个动作，门当场报出
#   dan|劈柴 hai|打渔 shu|授课 三对为空——写在这三个动作存在之前，仍然抓到了它们。
"$GODOT" --headless --path game --script res://bench/VoiceGate.gd -- \
  --seeds "${CI_VOICE_SEEDS:-1-3}" --days "${CI_VOICE_DAYS:-60}" 2>&1 | tee "$LT_LOG/voicegate.log"
[ "${PIPESTATUS[0]}" -eq 0 ] && ok "VoiceGate 台词覆盖门" || bad "VoiceGate 台词覆盖门"

echo "### 5. unit / integration scenes"
# player_touch_test：C3 的 31 条 + C8 的 13 条断言（触屏按钮路径 ≡ 按键路径、7 个动词可分辨、
#   观察台两档"卡片是详情的逐行前缀"）。它在 2026-07-26 Wave C 里写好后【一直没进 CI】——
#   docs/43 §1.2d 曾把它写成"已落地"，而 C8 查出这里的场景列表根本没有它。补上。
# goals_test：D2 的「小镇纪事」回放等价门 —— goto_tick 后从 event_log 重算的目标状态必须等于实时状态，
#   且挂上目标追踪前后 Inv.digest/event_digest 逐字节不动（= 它留在 View 侧的机器证明，docs/46 §二-D2）。
#   ★ tools/ci.sh 归 D1 独占，本行是【D2 声明过的越界】：只在下面这个场景名单里加一个词。
#     加它的理由就写在 docs/43 §1.2d 里 —— player_touch_test 写好后"一直没进 CI"，
#     一道没进 CI 的门不是门。冲突时直接取并集即可，回滚 = 删掉这一个词。
#   默认 12 seed × 14 天；本机约 2 分钟。CI_GOALS_SEEDS / CI_GOALS_DAYS 可调。
# story_test：E2 的「小镇故事」门（docs/47 §二-E2）。同样是 View 侧只读派生的回放等价断言，
#   但它的**牙齿不在 seed 循环里，在五组合成 fixture 上**——D2 已经实测「live==replay」和「至少 N 条」
#   两条判据都没有判别力（一个什么都不记 / 一个第一天全点亮的 tracker 都能满分）。
#   F1 只喂 greet → 故事必须 0 条；F2 手写因果链 → 必须给出指定的结局/幕次/旁支计数；
#   F3 冷场收场时刻必须等于"最后一幕+cold"（且 F3′ 反过来断言阈值之内不许判死）；F4 爽约/如约两支都要认。
#   另有两条账本自洽断言（进行中+终身收场==开过；grudge 开场数==conflict 事件数）守 MAX_CLOSED 裁剪。
#   ★ tools/ci.sh 归 D1 独占，本行是【E2 声明过的越界】：只在下面这个场景名单里再加一个词。
#     理由同 D2 那一行——一道没进 CI 的门不是门。冲突时取并集即可，回滚 = 删掉这一个词。
#   默认 12 seed × 14 天。CI_STORY_SEEDS / CI_STORY_DAYS 可调。
for scene in m2_test reqlife_test player_agency_test player_touch_test s4_replay_test space_test save_load_test goals_test story_test; do
  "$GODOT" --headless --path game "res://scenes/$scene.tscn" >"$LT_LOG/$scene.log" 2>&1
  code=$?
  if [ $code -eq 0 ]; then ok "$scene"; else tail -8 "$LT_LOG/$scene.log"; bad "$scene (exit $code)"; fi
  case "$scene" in
    # m2_test 是【负例测试】：故意把畸形 JSON 喂给 AIBackend.parse_decision 验证它拒收，
    # 引擎因此必打【恰好两行】"Parse JSON failed"（实测）。这是被断言的行为，不是回归 → 只对本场景、只放行这两条。
    m2_test) scan "$scene" "$LT_LOG/$scene.log" 'Parse JSON failed' 2 ;;
    *)       scan "$scene" "$LT_LOG/$scene.log" ;;
  esac
done

echo "### 6. 视觉门：昼夜量具 + 界外层重画 + 空间往返（无渲染环境时自动 SKIP，不假红）"
# 为什么是这一条先进 CI：docs/41 §6 盲区④——`--shot` 曾经【永远渲不出昼夜】，
# 于是【这个项目所有视觉判断用的尺子】是坏的（"偏亮/偏暗"的结论全部不可信）。C3 用 Main.gd:271 一行修好了它，
# 而在此之前没有任何门守着那一行：把它删掉，上面 0-5 每一步都照样全绿。
#
# ⚠️ 它跟前面五步不一样：**需要一个能真的出图的渲染环境**（pin 死的 gamecraft-runner 镜像，或 Xvfb+godot）。
# ⚠️ 上一版这里写着"GitHub Actions 的 ubuntu-latest 两样都没有 ⇒ 自动 SKIP"——**那句是假的**，
# 且 `tools/visual_gate.sh` 抬头早已逐字撤回它，而这份文件没跟着改（同一波、同一个所有者、两处相反的说法，
# 2026-07-28 外部评审抓到）。事实：runner 镜像**自带 Xvfb**，workflow 又把 godot 放上 PATH，
# 所以 `have_native()` 在那里为真、`auto` 会选 native ——**靠"探不到就跳过"是拦不住的**。
# 真正让它在 GHA 上跳过的是 visual_gate.sh 里那条**显式** `$GITHUB_ACTIONS` 判断。
# 这是蓄意的：**一道在别人机器上因环境变红的门比没有门更坏**——它训练所有人忽略红色。
# 判据都在 tools/visual_gate.sh 抬头；想让它必须跑（例如宿主 CI）：`LT_VISUAL=require bash tools/ci.sh`。
#
# ── 2026-07-30（E6/W7）：这一步现在有【三】道门，一次 Xvfb 全跑完 ────────────────
#   ① 昼夜量具（C3 那一行修复的守门人，assert_daynight.py）
#   ② 界外层重画门（D7 的 9× 帧时那条结构性性质，`--void-gate`）
#   ③ **空间往返像素门**（assert_space_roundtrip.py）——评审那句「没有人看过空间切换之后的任何一帧」。
#      ②③ 不是同一件事做两遍：② 数的是**重画次数**，③ 看的是**画出来的像素**。
#      实测负对照（把界外层改成"照常重画但什么都不画"）：**② PASS、③ FAIL** —— ② 结构上看不见它。
#      而同一棵坏树上 ① 也会红，但它的失败信息说的是"夜帧主色不对"，把人指向昼夜乘子——
#      ③ 的失败信息才指着真正坏掉的那条性质。**误导性的失败信息和假红一样坏。**
bash tools/visual_gate.sh 2>&1 | tee "$LT_LOG/visual.log"
VRC="${PIPESTATUS[0]}"
case "$VRC" in
  0)  ok "视觉门（昼夜 / 界外层重画 / 空间往返）" ;;
  77) echo "  ⏭  SKIP: 视觉门（本机没有渲染环境；LT_VISUAL=require 可让它变红）" ;;
  *)  bad "视觉门 (exit $VRC)" ;;
esac

echo
[ $FAIL -eq 0 ] && echo "=== CI PASS ✅ ===" || echo "=== CI FAIL ❌ ==="
exit $FAIL
