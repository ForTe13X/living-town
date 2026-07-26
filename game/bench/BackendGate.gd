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
##
## 每条 arm × 每个 seed 断言三件事：
##   A. 所有【硬】不变量绿（含 #01「无饿穿」；软/诊断只报告——8 天小网格本就不该硬断言涌现统计）
##   B. 同 seed 两跑：Inv.digest / Sim.event_digest / 逐 tick 前缀链 三路一致（真确定性，不是「跑了没崩」）
##   C. 【闭集封闭性】：后端交回的每一个 intent 都必须是**引擎本次枚举出来的那一批候选之一**（同 `_cand_key`）
## exit 0/1。
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

	print("\n=== BackendGate: %s  (硬不变量 %d/%d, 同seed两跑一致 %d/%d, 闭集封闭 %d/%d) ===" % [
		"PASS ✅" if not red else "FAIL ❌", n_hard_ok, total, n_det_ok, total, n_closed_ok, total])
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
	Sim.backend = probe
	Sim.auto_run = false
	AIBackend.reset_stats()                                # 跨 seed/跨跑清零（否则 _last_llm/_synth_busy_until 串味）
	var total: int = days * int(Sim.TICKS_PER_DAY)
	var starved := 0
	var chain: int = Inv.CHAIN_INIT
	var chain_ticks := PackedInt64Array()
	chain_ticks.resize(total)
	var ev_seen: int = Sim.event_log.size()
	for t in range(total):
		Sim.tick()
		chain = Inv.chain_step(chain, Sim, ev_seen)
		ev_seen = Sim.event_log.size()
		chain_ticks[t] = chain
		for ag in Sim.agents:
			for nid in ag["needs"]:
				if float(ag["needs"][nid]) <= 0.5:
					starved += 1
	Sim.backend = null                                     # 探针不跨 seed 续命（下一跑自己新建一个）
	return {"starved": starved, "chain": chain, "chain_ticks": chain_ticks,
		"intents": probe.n_intent, "escapes": probe.n_escape, "escape_eg": probe.first_escape}


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
class ClosureProbe extends RefCounted:
	var n_intent := 0        # 真正落地的 intent 数（分母，排除 {} 与 _wait）
	var n_escape := 0        # 其中【不在本次候选里】的
	var first_escape := ""   # 首例的可读描述（给失败消息用）
	func decide(ag: Dictionary, cands: Array, ctx: Dictionary) -> Dictionary:
		var intent: Dictionary = AIBackend.decide(ag, cands, ctx)
		if intent.is_empty() or intent.get("_wait", false):
			return intent
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
