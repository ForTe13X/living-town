extends Node
## bench/PickCtxDump.gd — B21 第1步：导出【与出货路径逐字符一致】的闭集选号 prompt + 打分原料。
##
## 为什么不复用 bench/log_decisions.gd（已查，reuse-first 红线#5 的交代）：
##   它的 _cap_order() 【总是】按 score 降序重排候选再建 prompt；而出货路径 AIBackend._cap_for_llm()
##   在 |C| ≤ 36 时【原样返回】（保持引擎枚举序，N=12 下 |C|≈11 ⇒ 永远走这一支）。
##   对一篇研究「位置塌陷」的报告来说，把候选按分数排好再问模型 = 把答案写在 0 号位上，结论全废。
##   所以本文件走【scene 模式】直接调 AIBackend 的真函数（_system_prompt/_cap_for_llm/build_prompt），
##   零重实现、零漂移；log_decisions.gd 那份是 --script 模式的手抄件，抄的时候就已经分叉了。
##
## 零扰动论证（红线#1）：
##   · 采集挂在 Sim.decision_sink（Sim.gd:242 既有 Phase-0 钩子：只读、不抽 RNG、不进 event_log/digest）。
##   · 唯一需要额外求值的是「引擎在冻结闭集上的基线选择」= Sim._logic_decide(ag, capped)。
##     它是纯函数（_rng_at 无状态，docs/36 §2.1 逐行验过），但会【再次触发 decision_sink】⇒ 必须先摘钩子再还原
##     （与 AIBackend._shadow_compare 同一手法）。
##   · backend 恒 null ⇒ 世界完全由 logic 地板推进，导出的上下文就是引擎自己的分布。
##
## 用法：
##   godot --headless --path game res://bench/PickCtxDump.tscn -- \
##       --seeds 1-8 --days 8 --agents 12 --out <绝对路径>.jsonl
##
## 每行一条决策点（|C| ≥ 2 才记，单候选决策对模型无意义）：
##   seed/tick/day/tod/agent/persona/min_need/crisis
##   n            全量候选数
##   n_cap        闭集大小（= AIBackend._cap_for_llm 后）
##   sys          AIBackend._system_prompt() 原文
##   user_nat     出货 prompt（自然枚举序）——这是唯一"真"的那一份
##   user_shuf    同一批候选、确定性洗牌后的 prompt（位置 vs 内容的判决性消融）
##   user_rev     同一批候选、逆序后的 prompt（最狠的重排，零随机）
##   perm_shuf / perm_rev   变体位置 i → 自然序下标，用来把模型的答案映回同一批候选
##   cands        闭集逐候选：action/kind/score/key/label（自然序）
##   base_idx     引擎在【同一冻结闭集】上会挑的下标（= Δ 的对照基线，含平局抖动）
##   argmax_idx   纯 argmax(score) 的下标（= 完美复读机/"鹦鹉地板"的答案）
##   pick_full    引擎在全量候选上挑的原下标（sink 给的 best_i；|C|≤36 时与 base_idx 同集）

var _f: FileAccess = null
var _n := 0
var _seed := 0
var _skipped_nocap := 0

func _ready() -> void:
	var seeds := _parse_seeds("1-8")
	var days := 8
	var agents := 12
	var out := "user://pick_ctx.jsonl"
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size(): seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size(): days = int(args[i + 1])
		elif args[i] == "--agents" and i + 1 < args.size(): agents = int(args[i + 1])
		elif args[i] == "--out" and i + 1 < args.size(): out = args[i + 1]

	_f = FileAccess.open(out, FileAccess.WRITE)
	if _f == null:
		printerr("无法写 %s (err %d)" % [out, FileAccess.get_open_error()])
		get_tree().quit(1)
		return

	Sim.spawn_count = agents
	Sim.auto_run = false
	Sim.backend = null
	print("=== PickCtxDump seeds=%s days=%d N=%d out=%s ===" % [str(seeds), days, agents, out])
	for sd in seeds:
		_seed = sd
		Sim.start_new(sd)
		Sim.decision_sink = Callable(self, "_on_decision")
		var total: int = days * int(Sim.TICKS_PER_DAY)
		for t in range(total):
			Sim.tick()
		Sim.decision_sink = Callable()
		print("  seed %d 完成，累计 %d 条" % [sd, _n])
	_f.close()
	print("导出 %d 条决策上下文（跳过 %d 条无闭集）→ %s" % [_n, _skipped_nocap, out])
	get_tree().quit(0)


## 确定性洗牌：Fisher-Yates，RNG 取自项目自己的 _rng_at（纯 f(seed,tick,salt,who)，无状态）。
## 盐 907331 是本文件专用，与仿真里任何盐不重叠；且【只用于生成 prompt 文本】，不回写任何仿真态。
func _det_shuffle(n: int, who: int) -> Array:
	var perm := []
	for i in n: perm.append(i)
	var r := Sim._rng_at(907331, who)
	for i in range(n - 1, 0, -1):
		var j := int(r.randi() % (i + 1))
		var t = perm[i]; perm[i] = perm[j]; perm[j] = t
	return perm


func _label_of(i: int) -> String:
	return AIBackend._idx_label(i)


func _on_decision(ag, cands, pick_i) -> void:
	var capped: Array = AIBackend._cap_for_llm(cands)     # 出货路径的闭集（|C|≤36 → 原样，保持枚举序）
	var n_cap := capped.size()
	if n_cap < 2:
		_skipped_nocap += 1
		return

	# 引擎在同一冻结闭集上的基线（Δ 的对照）。_logic_decide 会再触发 sink → 先摘钩子，读完原样还原。
	var sink_saved: Callable = Sim.decision_sink
	Sim.decision_sink = Callable()
	var base: Dictionary = Sim._logic_decide(ag, capped)
	Sim.decision_sink = sink_saved
	var base_key := Sim._cand_key(base)

	var cand_recs := []
	var base_idx := -1
	var argmax_idx := 0
	var best_s := -INF
	for i in n_cap:
		var c: Dictionary = capped[i]
		var k := Sim._cand_key(c)
		var sc := float(c.get("score", 0.0))
		cand_recs.append({
			"action": String(c.get("action", "")), "kind": String(c.get("kind", "")),
			"partner": String(c.get("partner", "")), "need": String(c.get("need", "")),
			"score": sc, "key": k, "label": _label_of(i),
		})
		if k == base_key and base_idx < 0:
			base_idx = i
		if sc > best_s:
			best_s = sc
			argmax_idx = i

	var ctx: Dictionary = Sim._context(ag)
	var who := Sim._aid(ag)
	var perm_shuf := _det_shuffle(n_cap, who)
	var perm_rev := []
	for i in range(n_cap - 1, -1, -1):
		perm_rev.append(i)
	var cand_shuf := []
	for j in perm_shuf: cand_shuf.append(capped[j])
	var cand_rev := []
	for j in perm_rev: cand_rev.append(capped[j])

	var min_need: float = Sim._min_need(ag)
	var row := {
		"seed": _seed, "tick": Sim.tick_no, "day": Sim.day, "tod": Sim.time_of_day(),
		"agent": String(ag.get("id", "")), "persona": String(ag.get("persona_key", "")),
		"min_need": min_need, "crisis": min_need < float(Sim.NEED_CRISIS),
		"n": cands.size(), "n_cap": n_cap,
		"sys": AIBackend._system_prompt(),
		"user_nat": AIBackend.build_prompt(ag, capped, ctx),
		"user_shuf": AIBackend.build_prompt(ag, cand_shuf, ctx),
		"user_rev": AIBackend.build_prompt(ag, cand_rev, ctx),
		"perm_shuf": perm_shuf, "perm_rev": perm_rev,
		"cands": cand_recs, "base_idx": base_idx, "argmax_idx": argmax_idx,
		"pick_full": pick_i,
	}
	_f.store_line(JSON.stringify(row))
	_n += 1


func _parse_seeds(s: String) -> Array:
	if "-" in s:
		var ab := s.split("-")
		var out := []
		for v in range(int(ab[0]), int(ab[1]) + 1): out.append(v)
		return out
	return [int(s)]
