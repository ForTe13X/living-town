extends Node
## bench/BackendGate.gd — 【外部后端】硬不变量门（docs/38 §8-2 开的方子）。
## 用法：godot --headless --path game res://bench/BackendGate.tscn -- [--seeds 1-4] [--days 8] [--agents 12]
##
## 为什么必须单独有这一门（Harness / DetGate 都盖不住这块）：
##   金标与 DetGate 恒 `Sim.backend = null`（红线#2 的零模型地板）⇒ `AIBackend.decide()` 从不被调用
##   ⇒ 硬不变量 #01「无饿穿」只在【引擎自己挑】的路径上被验过，**从没在任何外部后端挑的路径上被验过**。
##   docs/38 §五 实测：同一份配置下 `logic` 0/8 seed 饿穿，`random`/`slm` 都是 8/8 seed 饿穿——
##   **CI 全绿与产品已破可以同时成立**。这一门就是把那块空白补上。
##
## 为什么这一门【可以】进 CI（不引入不确定性）：
##   `random` 后端的选号来自项目自己的确定性种子流 `Sim._rng_at(RANDOM_SALT, who)`，不是 `randi()`，
##   也不碰墙钟——合成解码时延按 tick 计（`--decode-ticks`）。故同 (seed, tick, agent) → 同一选择，
##   逐字节可重跑（docs/38 §1.1 三跑同 digest，含 `--realtime` 开/关）。本门自己把这条性质【机检】了（下面 B）。
##   真模型 `slm` 做不到这点，永远【不】进 CI —— 但它与 `random` 走的是【同一条落地路】
##   （decide→闭集选号→重验→agent_apply），所以这条路上的结构性护栏一旦立住，两条臂同时受保护。
##   ⚠ **上面这句"两条臂同时受保护"对 A/B 成立，对 C 不成立**——见下面 W5 那一节。
##
## 每条 arm × 每个 seed 断言三件事：
##   A. 所有【硬】不变量绿（含 #01「无饿穿」；软/诊断只报告——8 天小网格本就不该硬断言涌现统计）
##   B. 同 seed 两跑：Inv.digest / Sim.event_digest / 逐 tick 前缀链 三路一致（真确定性，不是「跑了没崩」）
##   C. 【闭集封闭性】：后端交回的每一个 intent 都必须是**引擎本次枚举出来的那一批候选之一**（同 `_cand_key`）
## 外加一条**自检臂**（下面 W5）。exit 0/1。
##
## ── ★ W5（2026-07-30，docs/47 §五-E6）：C 臂此前【在它跑的两条臂上都不可能变红】────────────
## 外部对抗评审 2026-07-28 的原话，实测复核**成立**：
##   `random` 全剂量档走 `_instant_random` → `_rand_index` 只产一个下标，落地的是 `capped[i]`；
##   `random@K=2` 走异步路，回包由 `parse_decision` 解成 `candidates[pk].duplicate()`，
##   再被 `decide()` 用 `_cand_key` 对**当前** `capped` 重验一次，对不上就返回 `{}`。
##   而 `capped = _cap_for_llm(candidates) ⊆ candidates`（AIBackend.gd:926，只做子集挑选，不改字段）。
##   ⇒ **两条臂的 escape 数按构造恒为 0。** 8 个 seed 印出来的 `闭集=1332/1332 ✅` 是**恒真**，不是证据。
##   一道恒绿的门读起来像保护，实际上连"探针自己坏没坏"都发现不了。
##
## 于是本门加了**第三条臂，只在门内部存在，绝不进出货路径**：`inject:fabricate`。
## 它把 `AIBackend` 交回来的 object 类 intent 的 `amount` 字段 **+1** 再交给 `Sim` ——
## 一个引擎**从没枚举过**的 `_cand_key`。判据是**反的**：这条臂的 C **必须变红**；
## 它要是绿了，说明探针（而不是被测后端）坏了 ⇒ 整个 C 臂失去意义 ⇒ 本门 FAIL。
##
## **为什么挑 `amount` 而不是凭空造一个 dict**：`_cand_key` 的谓词是"这个键在不在本次候选里"，
##   改一个键内字段与整只捏造一个 dict 对**探针**是同一件事，多出来的判别力是零；而 `amount`
##   是唯一一个既进 `_cand_key`、又**不**被引擎的两条否决用到的字段
##   （`_survival_ok` 只看 `need`，`_horizon_ok` 只看 dist+`dur_total`，`_object_intent_ok` 只查存在性与除零）
##   ⇒ 伪造出来的 intent **必然原样落地**，于是本门可以顺带量到第二件事（见下条）。
##   换成 `dur_total` 会偶发触发 `_horizon_ok` 否决，换成整只新 dict 有触发 `_object_intent_ok` 兜底
##   甚至 push_error 的风险 —— 那会让 `ci.sh` 的 `scan` 变红，而红的原因是注入本身，不是被测性质。
##
## **这条臂证明什么、不证明什么（必须一起写，否则它会被当成别的东西引用）**：
##   ✅ 证明 C 臂的探针**有判别力**：一个越界的 `_cand_key` 会被抓到并点名（注入时红、不注入时绿）。
##   ✅ 证明 D1 那句"引擎自己并不强制闭包"是**真的**，而且是**量出来的**：
##      本臂另记 `landed`——伪造的 intent 被 `agent_apply` **原样写进** `ag["option"]["amount"]` 的次数。
##      实测 8 天 × 12 人 ≈ 每 seed 三百余次，一次都没有被引擎挡下。
##   ❌ **不**证明任何出货后端会捏造 intent —— 上面刚说了，`random`/`slm` 结构上做不到。
##      C 臂守的是**未来**：任何新后端（或 `parse_decision` 的一次改写）一旦能返回候选集外的东西，
##      这道门会红。它是**回归门**，不是"当前后端已被验过"的证书。
##   ❌ **不**是一条被保护的臂：本臂**不**断言 A（硬不变量）与 B（两跑一致）——它是一个**蓄意坏掉**的后端，
##      拿它的饿穿数/digest 去下结论没有意义。
##
## 出货路径隔离：`inject_every` 只出现在本文件的 `ClosureProbe` 里，默认 0（= 逐字节等于改动前的纯转发），
##   且只在 `SELFTEST` 这一条 arm 字典里被置成非 0。`game/scripts/*` 一个字节没动。
##
## ⚠ 2026-07-26（D1）修正：C 臂原本是「饿穿 agent-tick ≤ --max-starve（默认 0）」，那**不是第三条臂**——
##   `scenario==""` 时 `Invariants` 的 #1 化简为 `starved == 0`（Invariants.gd:18,21），而本门从不设 scenario
##   ⇒ 旧 C ≡ A 的 #1，**逐位同一个谓词**。收据的负对照表自己就露了馅（短路时"硬 0/8"与"饿穿 0/8"同时点亮）。
##   连带删掉 `--max-starve`：它是个**死旋钮**——#1 在 `HARD_IDS` 里（Invariants.gd:388），调高它只能让旧 C 变绿，
##   `Inv.check_all` 仍然红 ⇒ 照样 `quit(1)`。而按 docs/41 §3-5，硬不变量本来就**不该有预算旋钮**。
##
##   新 C 量的是**真正不同、且此前全仓库没有任何门在守**的一条：红线#2 的后半句——
##   「模型只能在引擎枚举出的合法候选里挑一个下标，永远不能写世界状态」。
##   **引擎侧并没有强制它**：`Sim.gd:1181-1201` 只查 `_survival_ok`/`_horizon_ok`，一个凭空捏造的 intent
##   只要不违反生存否决就会被 `agent_apply` 原样落地。它与 A（会不会饿穿）、B（两跑一不一致）正交：
##   一个后端完全可以**确定性地**捏造 intent、还谁都不饿死 —— A/B 全绿，红线#2 已破。
##
## ⚠ 必须是 scene 而不是 --script：本门要的是 autoload 的 `Sim`/`AIBackend` **单例**（而非 DetGate 那样 new 出来的实例），
##   scene 路径最直白。**注意**：原注释写的"--script 模式不加载 autoload"是**假的**，已由 docs/41 §2 逐字撤回——
##   真正的机制窄得多：autoload 挂在主循环对象**构造之后**，故只有 `_init()` 里的代码看不见它们。

const Inv = preload("res://bench/Invariants.gd")
const SimScript = preload("res://scripts/Sim.gd")
const H = preload("res://bench/Harness.gd")           # 只用它的静态工具（首个分叉 tick 定位），不实例化

## 两条 arm 覆盖【剂量】的两端，中间的都被夹住：
##   · full     ── decode_ticks=0：每一次决策都由后端挑（L/C=100%）。engine 的护栏若能在这一档守住，
##                 任何更低剂量必然也守得住 —— 这是最严的一档，也是最便宜的（零 _wait）。
##   · dose(K=2)── 复刻真 SLM 的串行解码剂量（docs/38 §1.2 标定：与 slm 的 L/C 61-63% 配平）。
##                 单跑 full 是不够的：K>0 才会走 _pending/_wait/迟到回包重验那条【异步落地路】，
##                 而 docs/38 §五 实测饿穿在这一档同样发生（8/8 seed）。两档的代码路径不同，故都要跑。
const ARMS := [
	{"label": "random(full)", "backend": "random", "decode_ticks": 0},
	{"label": "random@K=2", "backend": "random", "decode_ticks": 2},
]

## 自检臂（W5）。**它不是第三条被保护的臂，是 C 臂自己的负对照。** 判据是反的：C 必须变红。
## 配置刻意与 `random(full)` 完全相同（同 backend、同剂量、同 seed、同天数），唯一的差别就是 `inject_every`
## ⇒ 与 ARMS[0] 构成一对**只差一个变量**的对照，digest 的差可以全部归因给注入。
## `inject_every=3`：每第 3 个落地的 object 类 intent 伪造一次。取 3 而不是 1，是为了让同一跑里
## **合法与非法两种 intent 都出现**——若探针把"每一个"intent 都判成越界（例如键算错了），
## 那样的坏探针在 inject_every=1 下同样"红"，这条负对照就分辨不出来；而 ARMS 那两条恒绿的臂
## 正好是它的另一半（同一份探针、零注入、必须 0/N 越界）。两边合起来才是一个完整的判别对。
const SELFTEST := {"label": "inject:fabricate", "backend": "random", "decode_ticks": 0, "inject_every": 3}

func _ready() -> void:
	var seeds_spec := "1-4"
	var days := 8
	var agents := 12
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size(): seeds_spec = args[i + 1]
		elif args[i] == "--days" and i + 1 < args.size(): days = int(args[i + 1])
		elif args[i] == "--agents" and i + 1 < args.size(): agents = int(args[i + 1])

	# 哈希自检（同 Harness/DetGate）：随机流与摘要都由 Sim.fnv1a32 定义，先证明尺子没变。
	var hash_bad := SimScript.hash_self_test()
	if hash_bad != "":
		print("❌ 项目自有哈希测试向量不符：%s（尺子变了，任何比对无意义）" % hash_bad)
		get_tree().quit(1)
		return

	Sim.spawn_count = agents
	var seeds := _parse_seeds(seeds_spec)
	print("=== BackendGate · 外部后端硬不变量门  arms=%d seeds=%s days=%d N=%d ===" % [
		ARMS.size(), seeds_spec, days, agents])

	var red := false
	var n_hard_ok := 0
	var n_det_ok := 0
	var n_closed_ok := 0
	var total := 0
	var clean_digest := {}                                 # seed -> random(full) 干净臂的 Inv.digest（自检臂的对照基准）
	for arm in ARMS:
		for sd in seeds:
			total += 1
			var r1 := _run(arm, sd, days)
			var starved: int = r1["starved"]
			var checks: Array = Inv.check_all(Sim, starved)
			var hard_fails: Array = []
			for c in checks:
				if bool(c["ok"]): continue
				if int(c["id"]) in Inv.DIAG_IDS: continue      # 诊断档永不成门（#15，见 docs/31）
				if bool(c.get("hard", false)):
					hard_fails.append("#%d %s — %s" % [int(c["id"]), String(c["name"]), String(c["detail"])])
			var d1: int = Inv.digest(Sim)
			var e1: int = Sim.event_digest
			if String(arm["label"]) == "random(full)":
				clean_digest[sd] = d1                      # 自检臂唯一变量是注入 ⇒ 拿它做同 seed 的对照
			var c1: int = int(r1["chain"])
			var t1: PackedInt64Array = r1["chain_ticks"]
			var landed: int = int(AIBackend.stats["landed"])
			var decisions: int = maxi(0, int(AIBackend.stats["calls"]) - int(AIBackend.stats["waits"]))

			var r2 := _run(arm, sd, days)                      # 同 seed 二跑 → 真确定性（本门进 CI 的前提）
			var d2: int = Inv.digest(Sim)
			var e2: int = Sim.event_digest
			var c2: int = int(r2["chain"])
			var det_ok: bool = (d1 == d2) and (e1 == e2) and (c1 == c2) and (starved == int(r2["starved"]))
			var det_where := ""
			if not det_ok:
				var ft := H.first_tick_mismatch(t1, r2["chain_ticks"])   # 逐 tick 前缀链 → 精确到 tick 的首个分叉
				det_where = H.tick_label(ft) if ft >= 0 else "  （链一致，分歧只在终态摘要）"

			# C：闭集封闭性。两跑各自都测，取并集——迟到回包那条路在两跑里落地的 tick 相同，但多测一遍不花钱。
			var esc: int = int(r1["escapes"]) + int(r2["escapes"])
			var n_int: int = int(r1["intents"]) + int(r2["intents"])
			var closed_ok := esc == 0
			if hard_fails.is_empty(): n_hard_ok += 1
			else: red = true
			if det_ok: n_det_ok += 1
			else: red = true
			if closed_ok: n_closed_ok += 1
			else: red = true

			print("  [%s] seed=%d L/C=%.0f%% d=%d e=%d 饿穿=%d 硬=%s 确定=%s 闭集=%s" % [
				String(arm["label"]), sd, 100.0 * float(landed) / float(maxi(1, decisions)), d1, e1, starved,
				"✅" if hard_fails.is_empty() else ("❌ " + "; ".join(hard_fails)),
				"✅" if det_ok else ("❌ %d/%d/%d vs %d/%d/%d%s" % [d1, e1, c1, d2, e2, c2, det_where]),
				("%d/%d ✅" % [n_int - esc, n_int]) if closed_ok else
					("❌ %d/%d 个 intent 不在本次候选里 —— 首例：%s" % [esc, n_int, String(r1["escape_eg"]) if String(r1["escape_eg"]) != "" else String(r2["escape_eg"])])])

	# ── 自检臂（W5）：判据是【反】的——C 必须变红，否则探针本身没有判别力 ────────────────
	# 只跑一遍（不做两跑一致：本臂是蓄意坏掉的后端，它的确定性没有意义，也不构成任何承诺）。
	var st_ok := 0
	var st_land_ok := 0
	print("  ── 自检臂（gate-internal，绝不在出货路径上）：C 臂的负对照，判据是【必须红】──")
	for sd in seeds:
		var ri := _run(SELFTEST, sd, days)
		var esc_i: int = int(ri["escapes"])
		var n_i: int = int(ri["intents"])
		var inj: int = int(ri["injected"])
		var lnd: int = int(ri["landed_fab"])
		var di: int = Inv.digest(Sim)
		# 不多不少：每一次伪造都被抓到（≥），且没有误报任何合法 intent（≤）。
		# 实测 seeds 1-4 × 8 天恒 145/145、145/145、141/141、147/147 —— 严格相等是**量出来的**，不是假设。
		# 若日后它变成 esc<inj：说明某次 amount+1 撞上了另一个枚举候选的 _cand_key（两个候选只差 amount），
		#   那就换一个进 _cand_key 但不进引擎否决的字段来注入，别把判据放松成 ">=1"（那会把探针的误报放跑）。
		var detected := esc_i >= 1 and esc_i == inj
		var moved := (not clean_digest.has(sd)) or di != int(clean_digest[sd])
		if detected: st_ok += 1
		else: red = true
		if lnd >= 1: st_land_ok += 1
		else: red = true                                  # 一次都没落地 ⇒ 下面那句"引擎不强制闭包"就不该再说
		print("    [%s] seed=%d 伪造=%d 抓到=%d/%d %s | 引擎原样落地=%d %s | 世界轨迹 vs 干净臂: %s" % [
			String(SELFTEST["label"]), sd, inj, esc_i, n_i,
			("✅ 探针有判别力" if detected else
				("❌ 本臂一次都没伪造成功（inject_every 被关掉？object 类 intent 为 0？）⇒ 这条负对照没跑到" if inj == 0
				else "❌ 伪造 %d 次、探针只报 %d 次越界 ⇒ C 臂抓不到它该抓的东西，是装饰" % [inj, esc_i])),
			lnd, "✅ 引擎不强制闭包（红线#2 靠的就是这道门）" if lnd >= 1 else "❌ 一次都没落地 —— 注入被别的护栏吃掉了，这条证据不成立",
			("d=%d ≠ %d 已移动" % [di, int(clean_digest.get(sd, 0))]) if moved else "d=%d 未移动（可疑）" % di])

	print("\n=== BackendGate: %s  (硬不变量 %d/%d, 同seed两跑一致 %d/%d, 闭集封闭 %d/%d, 自检臂必红 %d/%d, 伪造落地 %d/%d) ===" % [
		"PASS ✅" if not red else "FAIL ❌", n_hard_ok, total, n_det_ok, total, n_closed_ok, total,
		st_ok, seeds.size(), st_land_ok, seeds.size()])
	get_tree().quit(0 if not red else 1)

## 跑一局。饿穿口径与 Harness._run_once（Harness.gd:597-601）/ DetGate._run 逐字一致：
##   Σ over (agent, tick, need) of [need ≤ 0.5] —— 【不】按 agent 去重，一个人同时饿又困计 2。
##   ⚠ 与 BackendBench 的 `_starve_ticks` 差一个 `break`（那边是 per-agent-tick 口径），
##   所以本门印的数会 ≥ docs/38 表里的数。判定不受影响（两者同零同非零），但引用数字时别混。
##   这里跟 Harness 而不是跟 BackendBench：#01 的口径由喂给 Invariants.check_all 的那个数定义，
##   而那个数一直是 Harness 产的。
## 只读观测 + 逐 tick 前缀链，不写 sim 态、不抽 RNG ⇒ 对被测轨迹零扰动（红线#1）。
func _run(arm: Dictionary, seed: int, days: int) -> Dictionary:
	AIBackend.backend = String(arm["backend"])
	AIBackend.backend_requested = String(arm["backend"])   # 必须同步，否则 decide() 的运行期切换会把它拽回 logic（BackendBench.gd:82 同坑）
	AIBackend.sim_decode_ticks = int(arm["decode_ticks"])
	AIBackend.shadow_baseline = false                      # 门不需要影子基线（省一次纯函数对拍；开/关都不扰 digest）
	Sim.start_new(seed)                                    # 发 world_reset → AIBackend.cancel_all（清在飞/串行 worker）
	# C 臂的量具：纯转发探针夹在 Sim 与 AIBackend 之间。Sim 对 backend 是鸭子类型（Sim.gd:1181/2375 只查
	# has_method("decide"/"reflect")），所以夹一层不改变任何调用语义；探针只读、不抽 RNG、不改参数 ⇒ 零扰动。
	# 【这条零扰动是量出来的，不是声称的】：夹探针前后 8 行 d=/e= 逐字节相同，且与 ModelPathGate C 段
	# （另一条独立实现的探针）的 random(full) digest 也逐字节相同。
	var probe := ClosureProbe.new()
	probe.inject_every = int(arm.get("inject_every", 0))   # 缺省 0 = 纯转发（ARMS 两条臂逐字节等于改动前）
	Sim.backend = probe
	Sim.auto_run = false
	AIBackend.reset_stats()                                # 跨 seed/跨跑清零（否则 _last_llm/_synth_busy_until 串味）
	var total: int = days * int(Sim.TICKS_PER_DAY)
	var starved := 0
	var landed_fab := 0
	var chain: int = Inv.CHAIN_INIT
	var chain_ticks := PackedInt64Array()
	chain_ticks.resize(total)
	var ev_seen: int = Sim.event_log.size()
	for t in range(total):
		Sim.tick()
		# 自检臂专用（inject_every==0 时 fab_watch 恒空 ⇒ 本段是 no-op，零扰动）：
		# 伪造发生在本 tick 的 decide 里，而 Sim.tick 在 agent_apply 之后立刻 return
		# ⇒ 此刻 option 若真是那一份伪造的，必然还停在刚建好的形状（phase=travel、remaining==dur_total）。
		# 比对 action/target/amount 三者同时相等：amount 是我们 +1 出来的、引擎从没枚举过的那个值。
		for f in probe.fab_watch:
			var ag2: Dictionary = Sim.get_agent(String(f["id"]))
			if ag2.is_empty():
				continue
			var opt = ag2.get("option")
			if opt is Dictionary and String(opt.get("kind", "")) == "object" \
					and String(opt.get("action", "")) == String(f["action"]) \
					and String(opt.get("target", "")) == String(f["target"]) \
					and int(opt.get("amount", -1)) == int(f["amount"]) \
					and int(opt.get("remaining", -1)) == int(opt.get("dur_total", -2)):
				landed_fab += 1
		probe.fab_watch.clear()
		chain = Inv.chain_step(chain, Sim, ev_seen)
		ev_seen = Sim.event_log.size()
		chain_ticks[t] = chain
		for ag in Sim.agents:
			for nid in ag["needs"]:
				if float(ag["needs"][nid]) <= 0.5:
					starved += 1
	Sim.backend = null                                     # 探针不跨 seed 续命（下一跑自己新建一个）
	return {"starved": starved, "chain": chain, "chain_ticks": chain_ticks,
		"intents": probe.n_intent, "escapes": probe.n_escape, "escape_eg": probe.first_escape,
		"injected": probe.n_inject, "landed_fab": landed_fab}


## 闭集封闭性探针（C 臂）。纯转发：把 Sim 的每一次 decide/reflect 原样交给 AIBackend，
## 只在**回来的路上**查一件事——非空、非 `_wait` 的 intent，其 `_cand_key` 必须等于本次
## `candidates` 里某一项的 `_cand_key`。这正是红线#2「模型只能在引擎枚举出的合法候选里挑一个下标」
## 的机检形式，而引擎自己**并不**强制它（Sim.gd:1185-1201 只做生存/视野否决）。
##
## 口径三条，写清楚免得日后被当成别的东西：
##   · `{}`（放弃/超时/脏输出/预算门）与 `{"_wait": true}`（思考中）**不计**——那两条路引擎会自己兜底；
##   · 比的是 `_cand_key`（kind/action/partner/target/subject/need/area/commit/amount/dur_total），
##     **不是** dict 相等：后端合法地会加 `say`（冻结语音库）、`duplicate()` 出新引用，那些都不算越界；
##   · 候选为空时引擎压根不问后端，故不存在"空候选里挑一个"的边界。
##
## ★ W5 起它多了一顶【只在门内部戴的】帽子：`inject_every > 0` 时它会**自己捏造**越界 intent，
##   用来给上面那条封闭性断言做负对照。默认 0 ⇒ 纯转发，与改动前逐字节相同。
##   捏造发生在**探针交给 Sim 之前**，所以引擎的 `_survival_ok`/`_horizon_ok` 会照常审它——
##   这正是我们想要的形状：伪造的是"后端交回来的东西"，不是"绕过引擎直接写世界"。
class ClosureProbe extends RefCounted:
	var n_intent := 0        # 真正落地的 intent 数（分母，排除 {} 与 _wait）
	var n_escape := 0        # 其中【不在本次候选里】的
	var first_escape := ""   # 首例的可读描述（给失败消息用）
	# ── 自检臂专用（gate-internal；出货路径上恒为 0/空）────────────────────────
	var inject_every := 0    # 0=不注入。>0：每第 N 个 object 类 intent 伪造一次
	var n_inject := 0        # 已伪造次数
	var n_obj_seen := 0      # 见过的 object 类 intent 数（注入相位的计数器，与 n_intent 分开）
	var fab_watch: Array = []  # 本 tick 刚伪造出去的 {id,action,target,amount}，交给 _run 在 tick 后核对是否原样落地
	func decide(ag: Dictionary, cands: Array, ctx: Dictionary) -> Dictionary:
		var intent: Dictionary = AIBackend.decide(ag, cands, ctx)
		if intent.is_empty() or intent.get("_wait", false):
			return intent
		if inject_every > 0 and String(intent.get("kind", "object")) == "object" and intent.has("amount"):
			n_obj_seen += 1
			if n_obj_seen % inject_every == 0:
				intent = intent.duplicate()                 # 绝不就地改 cands 里那份（那会污染引擎自己的候选）
				intent["amount"] = int(intent["amount"]) + 1  # ← 引擎从没枚举过的 _cand_key
				n_inject += 1
				fab_watch.append({"id": String(ag.get("id", "")), "action": String(intent.get("action", "")),
					"target": String(intent.get("target", "")), "amount": int(intent["amount"])})
		n_intent += 1
		var key: String = Sim._cand_key(intent)
		for c in cands:
			if Sim._cand_key(c) == key:
				return intent
		n_escape += 1
		if first_escape == "":
			first_escape = "tick=%d agent=%s key='%s'（本次 |C|=%d）" % [
				Sim.tick_no, String(ag.get("id", "?")), key, cands.size()]
		return intent
	func reflect(ag: Dictionary, floor_insight: String, recent: Array, cb: Callable) -> void:
		AIBackend.reflect(ag, floor_insight, recent, cb)

func _parse_seeds(spec: String) -> Array:
	var out: Array = []
	if "-" in spec:
		var ab := spec.split("-")
		for s in range(int(ab[0]), int(ab[1]) + 1): out.append(s)
	elif "," in spec:
		for s in spec.split(","): out.append(int(s))
	else: out.append(int(spec))
	return out
