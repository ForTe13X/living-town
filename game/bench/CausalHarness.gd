extends SceneTree
## bench/CausalHarness.gd — Causal Bench S5：配对反事实（PN/PS/ACE）+ 系统指标（PI/cascade/Gini）。
## 用法：godot --headless --path . --script res://bench/CausalHarness.gd -- [--seeds 1-8] [--days 40] [--only trust|standing|xi] [--receipt|--receipt-only]
## 方法：同 seed 同初态，对目标 agent 只翻转一个干预位 do(X=high)/do(X=low)/control，跑确定性轨迹对比结果 Y。
##   PS=P(Y|do高) 在 control 无 Y 的 seed；PN=P(¬Y|do低) 在 control 有 Y 的 seed；ACE=mean(Y_high−Y_low)。
##   standing / xi 声明的是充分性方向，守 ACE≥0.30；trust 在引擎里只是 give/invite 的必要门，
##   不会凭空创造同场、礼物或邀约机会，因此守 control 有 Y 的支持数≥2 且 PN=1.00，并把 PS/ACE 作为诊断量。
##   纯注入式干预（不改 Sim）；后端宏观矩阵(legality/macro-drift)因 AIBackend 引用全局 Sim 留作 scene 模式。
## 纪律同 soak/S0：--script 的 _init() 阶段 autoload 尚未挂上（docs/41 §2 更正：autoload 其实是加载的） → preload 实例化，backend=null 走确定性 logic。

const SimScript = preload("res://scripts/Sim.gd")
const M = preload("res://bench/Metrics.gd")
const NECESSARY_MIN_SUPPORT := 2  # 0/1 个 control-positive 不足以让必要性门有牙；宁可红成“样本不足”。
var _last_opportunity_receipt := {}

func _init() -> void:
	var seeds := _parse_seeds("1-8")
	var days := 40
	var only := ""
	var receipt := false
	var receipt_only := false
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])
		elif args[i] == "--only" and i + 1 < args.size():
			only = String(args[i + 1]).strip_edges()
		elif args[i] == "--receipt":
			receipt = true
		elif args[i] == "--receipt-only":
			receipt = true
			receipt_only = true

	print("=== Causal Bench S5 · 配对反事实 + 系统指标  seeds=%s days=%d ===" % [str(seeds), days])

	# 三个因果假设（target 用 agent 下标，id 跨 seed 稳定）
	var H := [
		{"key": "standing→放逐", "idx": 2, "kind": "standing", "Y": "ostracized", "gate": "ace"},
		{"key": "开放(xi)→观点迁移", "idx": 0, "kind": "xi", "Y": "moved", "gate": "ace"},
		{"key": "trust→投资", "idx": 0, "idx2": 1, "kind": "trust", "Y": "invested", "gate": "necessary"},
	]
	if only != "":
		H = H.filter(func(h): return String(h["kind"]) == only or String(h["key"]) == only)
		if H.is_empty():
			print("CausalHarness CLI: FAIL: --only must be one of trust, standing, xi (got '%s')" % only)
			quit(2)
			return
	# 收集每假设的 (yc, yh, yl)
	var data := {}
	for h in H:
		data[h["key"]] = {"yc": [], "yh": [], "yl": []}
	# 指标基线（control 跑）
	var pis: Array = []
	var casc: Array = []
	var ginis: Array = []
	var opportunity_receipts: Array = []

	for sd in seeds:
		# control 跑一次：取 id、Y_ctrl、指标
		var Sc = _run(sd, days, {}, receipt)
		if receipt:
			var row: Dictionary = _last_opportunity_receipt.duplicate(true)
			row["seed"] = sd
			opportunity_receipts.append(row)
		var ids: Array = []
		for ag in Sc.agents:
			ids.append(ag["id"])
		pis.append(M.polarization(Sc))
		casc.append(M.cascade_max(Sc))
		ginis.append(M.gini_acceptance(Sc))
		for h in H:
			data[h["key"]]["yc"].append(_outcome(Sc, h, ids))
		_dispose(Sc)
		if not receipt_only:
			# 每假设 high/low 各跑一次
			for h in H:
				var hi := _opts(h, ids, true)
				var lo := _opts(h, ids, false)
				var Sh = _run(sd, days, hi)
				data[h["key"]]["yh"].append(_outcome(Sh, h, ids))
				_dispose(Sh)
				var Sl = _run(sd, days, lo)
				data[h["key"]]["yl"].append(_outcome(Sl, h, ids))
				_dispose(Sl)

	# ── 报告 ──
	print("\n— 系统指标基线（control，%d seed）—" % seeds.size())
	print("  PI 极化   : %s" % _stat(pis))
	print("  cascade   : %s" % _stat(casc))
	print("  Gini 接纳 : %s" % _stat(ginis))
	if receipt:
		_print_opportunity_receipt(opportunity_receipts)
	if receipt_only:
		print("\n=== S5 RECEIPT: PASS ✅  (control-only observation; no counterfactual gate requested) ===")
		quit(0)
		return

	print("\n— 配对反事实因果强度 —")
	var gate_ok := true
	for h in H:
		var d = data[h["key"]]
		var ace := _mean(d["yh"]) - _mean(d["yl"])
		var ps := _cond(d["yh"], d["yc"], 0)   # do高 | control=0 → Y
		var pn := _cond_neg(d["yl"], d["yc"], 1) # do低 | control=1 → ¬Y
		var necessary_support := 0
		var necessary_blocked := 0
		for i in d["yc"].size():
			if int(d["yc"][i]) == 1:
				necessary_support += 1
				if int(d["yl"][i]) == 0:
					necessary_blocked += 1
		var ok := (necessary_support >= NECESSARY_MIN_SUPPORT and necessary_blocked == necessary_support) \
			if String(h.get("gate", "ace")) == "necessary" else ace >= 0.3
		if not ok:
			gate_ok = false
		print("  %s %s" % ["✅" if ok else "❌", String(h["key"])])
		print("      base=%.2f  do(高)=%.2f  do(低)=%.2f  → ACE=%.2f  (PS=%s  PN=%s)" % [
			_mean(d["yc"]), _mean(d["yh"]), _mean(d["yl"]), ace, ps, pn])
		if String(h.get("gate", "ace")) == "necessary":
			print("      necessary gate: blocked=%d/%d control-positive seeds（需 support≥%d 且全部阻断）" % [necessary_blocked, necessary_support, NECESSARY_MIN_SUPPORT])
		var paired: Array[String] = []
		for i in seeds.size():
			paired.append("%s:%d/%d/%d" % [str(seeds[i]), int(d["yc"][i]), int(d["yh"][i]), int(d["yl"][i])])
		print("      paired seed:control/high/low = " + " · ".join(paired))

	print("\n=== S5 GATE: %s  (%d 假设按各自声明的因果门判定)===" % [("PASS ✅" if gate_ok else "FAIL ❌"), H.size()])
	quit(0 if gate_ok else 1)

## 按假设 + 方向构造干预 opts
func _opts(h: Dictionary, ids: Array, high: bool) -> Dictionary:
	match String(h["kind"]):
		"standing":
			# 高=坏名声(-3,易放逐) / 低=好名声(+3)
			return {"standing": {"target": ids[h["idx"]], "value": (-3.0 if high else 3.0)}}
		"xi":
			# 高=开放(易随大流) / 低=固执(锚定天生立场)
			return {"xi": {ids[h["idx"]]: (0.9 if high else 0.02)}}
		"trust":
			# 高=高信任(过投资门) / 低=负信任(挡投资)
			return {"trust": {"a": ids[h["idx"]], "b": ids[h["idx2"]], "value": (60.0 if high else -60.0)}}
	return {}

## 判定结果 Y
func _outcome(S, h: Dictionary, ids: Array) -> int:
	match String(h["Y"]):
		"ostracized": return 1 if M.ostracized(S, ids[h["idx"]]) else 0
		"moved": return 1 if M.opinion_moved(S, ids[h["idx"]]) else 0
		"invested": return 1 if M.invested(S, ids[h["idx"]], ids[h["idx2"]]) else 0
	return 0

## 跑一局，opts 指定干预（xi 在 tick0 注入；standing/trust 从 tick0 持续保持）。
func _run(seed: int, days: int, opts: Dictionary, watch_opportunity := false) -> Object:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	S.start_new(seed)
	# xi 是初始性格参数：在任何自然动力学前置入，效应作用全程。
	if opts.has("xi"):
		for id in opts["xi"]:
			var ag: Dictionary = S.get_agent(id)
			if not ag.is_empty():
				ag["xi"] = float(opts["xi"][id])
	var tr = opts.get("trust", null)
	# standing 持续保持（do(声誉=v) held）：每 tick 重注入以覆盖引擎的 GTFT 向0漂移，干净测「持续坏名声→放逐」边
	var st = opts.get("standing", null)
	var watch: Dictionary = _new_opportunity_receipt(S) if watch_opportunity else {}
	if watch_opportunity:
		S.decision_sink = _observe_investment_decision.bind(watch)
	var total: int = days * int(S.TICKS_PER_DAY)
	for t in range(total):
		# trust 是必要候选门：持续 do() 隔离自然关系更新，避免“低信任后来被别的事件抬回门内”。
		if tr != null:
			var a: Dictionary = S.get_agent(String(tr["a"]))
			if not a.is_empty():
				S._rel(a, String(tr["b"]))["trust"] = float(tr["value"])
		if st != null:
			for b in S.agents:
				if b["id"] != String(st["target"]):
					S._rel(b, String(st["target"]))["standing"] = float(st["value"])
		var event_start: int = S.event_log.size()
		if watch_opportunity:
			_observe_opportunity_before(S, watch)
		S.tick()
		if watch_opportunity:
			_observe_opportunity_events(S, watch, event_start)
	_last_opportunity_receipt = watch.duplicate(true) if watch_opportunity else {}
	return S

## Read-only funnel for the fixed trust pair used by S5. It reconstructs only the explicit gates in
## _advance_agent/_social_candidates; it never calls agent_candidates or _rel, so observation cannot
## create relationships, consume RNG, reorder candidates, or move the trajectory being measured.
func _new_opportunity_receipt(S) -> Dictionary:
	var a: Dictionary = S.agents[0]
	var b: Dictionary = S.agents[1]
	return {
		"actor": String(a["id"]), "target": String(b["id"]),
		"_active": {},
		"pair_selected": 0, "pair_accepted": 0, "pair_give": 0, "pair_invite": 0,
		"actor_any_selected": 0, "actor_any_accepted": 0, "actor_give": 0, "actor_invite": 0,
		"actor_targets": {},
		"decision_candidates": {"give": 0, "invite": 0},
		"decision_selected": {"give": 0, "invite": 0},
		"decision_candidate_pairs": {"give": {}, "invite": {}},
		"all_events": {"give": 0, "invite": 0},
		"all_accepted": {"give": 0, "invite": 0},
	}

## Exact competitive denominator from Sim._logic_decide. The hook is invoked after candidate construction and
## receives the chosen index; Sim documents it as read-only and excludes it from digests.
func _observe_investment_decision(ag: Dictionary, cands: Array, best_i: int, row: Dictionary) -> void:
	for c in cands:
		if not (c is Dictionary) or String((c as Dictionary).get("kind", "")) != "social":
			continue
		var action := String((c as Dictionary).get("action", ""))
		if not (action in ["give", "invite"]):
			continue
		(row["decision_candidates"] as Dictionary)[action] = int((row["decision_candidates"] as Dictionary)[action]) + 1
		var pair_key := String(ag["id"]) + "→" + String((c as Dictionary).get("partner", ""))
		var pairs: Dictionary = (row["decision_candidate_pairs"] as Dictionary)[action]
		pairs[pair_key] = int(pairs.get(pair_key, 0)) + 1
	if best_i < 0 or best_i >= cands.size() or not (cands[best_i] is Dictionary):
		return
	var chosen: Dictionary = cands[best_i]
	var chosen_action := String(chosen.get("action", ""))
	if String(chosen.get("kind", "")) == "social" and chosen_action in ["give", "invite"]:
		(row["decision_selected"] as Dictionary)[chosen_action] = int((row["decision_selected"] as Dictionary)[chosen_action]) + 1

func _mark_stage(row: Dictionary, key: String, active: bool, tick: int) -> void:
	if active:
		row[key + "_ticks"] = int(row.get(key + "_ticks", 0)) + 1
		if not bool((row["_active"] as Dictionary).get(key, false)):
			row[key + "_windows"] = int(row.get(key + "_windows", 0)) + 1
			if not row.has(key + "_first"):
				row[key + "_first"] = tick
	(row["_active"] as Dictionary)[key] = active

func _observe_opportunity_before(S, row: Dictionary) -> void:
	var a: Dictionary = S.get_agent(String(row["actor"]))
	var b: Dictionary = S.get_agent(String(row["target"]))
	if a.is_empty() or b.is_empty():
		return
	var min_need := float(S._min_need(a))
	var decision_ready := a.get("option", null) == null
	if decision_ready and int(S.decide_period) > 1 and min_need >= float(S.SURVIVAL_GATE):
		decision_ready = (int(S.tick_no) % int(S.decide_period)) == (absi(int(S._aid(a))) % int(S.decide_period))
	var same_area: bool = S._same_plane(a, b) and String(a.get("area", "")) != "" \
		and String(a.get("area", "")) == String(b.get("area", ""))
	var social_ready: bool = decision_ready and min_need >= float(S.SURVIVAL_GATE) \
		and float(a["needs"].get("social", 100.0)) < float(S.SOCIAL_FULL)
	var target_available: bool = social_ready and same_area and int(b.get("talking", 0)) == 0
	var rel: Dictionary = (a.get("relationships", {}) as Dictionary).get(String(b["id"]), {})
	var trust_open: bool = target_available and float(rel.get("trust", 0.0)) >= float(S.INVEST_TRUST)
	var give_ready: bool = trust_open and int(a.get("inventory", {}).get("gift", 0)) > 0
	var invite_ready: bool = trust_open and not S._any_active_meet(String(a["id"])) \
		and not S._has_active_meet(String(a["id"]), String(b["id"]))
	_mark_stage(row, "same_area", same_area, int(S.tick_no))
	_mark_stage(row, "decision_ready", decision_ready, int(S.tick_no))
	_mark_stage(row, "social_ready", social_ready, int(S.tick_no))
	_mark_stage(row, "target_available", target_available, int(S.tick_no))
	_mark_stage(row, "trust_open", trust_open, int(S.tick_no))
	_mark_stage(row, "give_ready", give_ready, int(S.tick_no))
	_mark_stage(row, "invite_ready", invite_ready, int(S.tick_no))
	_mark_stage(row, "candidate_ready", give_ready or invite_ready, int(S.tick_no))

func _observe_opportunity_events(S, row: Dictionary, event_start: int) -> void:
	for i in range(event_start, S.event_log.size()):
		var e: Dictionary = S.event_log[i]
		var event_action := String(e.get("type", ""))
		if not (event_action in ["give", "invite"]):
			continue
		(row["all_events"] as Dictionary)[event_action] = int((row["all_events"] as Dictionary)[event_action]) + 1
		if bool(e.get("accepted", false)):
			(row["all_accepted"] as Dictionary)[event_action] = int((row["all_accepted"] as Dictionary)[event_action]) + 1
		if String(e.get("actor", "")) != String(row["actor"]):
			continue
		row["actor_any_selected"] = int(row["actor_any_selected"]) + 1
		var action_key := "actor_" + String(e["type"])
		row[action_key] = int(row[action_key]) + 1
		var target_id := String(e.get("target", ""))
		(row["actor_targets"] as Dictionary)[target_id] = int((row["actor_targets"] as Dictionary).get(target_id, 0)) + 1
		if bool(e.get("accepted", false)):
			row["actor_any_accepted"] = int(row["actor_any_accepted"]) + 1
		if String(e.get("target", "")) != String(row["target"]):
			continue
		row["pair_selected"] = int(row["pair_selected"]) + 1
		var type_key := "pair_" + String(e["type"])
		row[type_key] = int(row[type_key]) + 1
		if bool(e.get("accepted", false)):
			row["pair_accepted"] = int(row["pair_accepted"]) + 1

func _print_opportunity_receipt(rows: Array) -> void:
	print("\n— Investment opportunity receipt (control trajectory; fixed trust pair) —")
	print("  seed pair       same-area social-ready trust-open candidate-ready selected/accepted  actor-any")
	for row in rows:
		print("  %4d %-11s %4d/%-4d %4d/%-4d   %4d/%-4d  %4d/%-4d       %2d/%-2d             %2d/%-2d" % [
			int(row["seed"]), String(row["actor"]) + "→" + String(row["target"]),
			int(row.get("same_area_windows", 0)), int(row.get("same_area_ticks", 0)),
			int(row.get("social_ready_windows", 0)), int(row.get("social_ready_ticks", 0)),
			int(row.get("trust_open_windows", 0)), int(row.get("trust_open_ticks", 0)),
			int(row.get("candidate_ready_windows", 0)), int(row.get("candidate_ready_ticks", 0)),
			int(row.get("pair_selected", 0)), int(row.get("pair_accepted", 0)),
			int(row.get("actor_any_selected", 0)), int(row.get("actor_any_accepted", 0)),
		])
		var routes: Array[String] = []
		for target_id in (row["actor_targets"] as Dictionary):
			routes.append("%s:%d" % [String(target_id), int((row["actor_targets"] as Dictionary)[target_id])])
		print("       routes: give=%d invite=%d → %s" % [int(row["actor_give"]), int(row["actor_invite"]), ", ".join(routes)])
	var exposed := rows.filter(func(r): return int(r.get("target_available_ticks", 0)) > 0).size()
	var eligible := rows.filter(func(r): return int(r.get("candidate_ready_ticks", 0)) > 0).size()
	var selected := rows.filter(func(r): return int(r.get("pair_selected", 0)) > 0).size()
	var actor_active := rows.filter(func(r): return int(r.get("actor_any_selected", 0)) > 0).size()
	print("  funnel coverage: pair-visible %d/%d → investment-candidate %d/%d → selected %d/%d" % [
		exposed, rows.size(), eligible, rows.size(), selected, rows.size()])
	if exposed == rows.size() and eligible == rows.size() and actor_active == rows.size() and selected < rows.size():
		print("  analysis: exposure and trust eligibility exist in every seed, and the actor invests in every seed; the sparse fixed-pair outcome is partner routing/selection competition, not investment-channel inactivity.")
	var give_candidates := 0
	var invite_candidates := 0
	var give_selected := 0
	var invite_selected := 0
	var give_pairs := {}
	var invite_pairs := {}
	var give_events := 0
	var invite_events := 0
	var give_accepted := 0
	var invite_accepted := 0
	for row in rows:
		give_candidates += int((row["decision_candidates"] as Dictionary)["give"])
		invite_candidates += int((row["decision_candidates"] as Dictionary)["invite"])
		give_selected += int((row["decision_selected"] as Dictionary)["give"])
		invite_selected += int((row["decision_selected"] as Dictionary)["invite"])
		give_events += int((row["all_events"] as Dictionary)["give"])
		invite_events += int((row["all_events"] as Dictionary)["invite"])
		give_accepted += int((row["all_accepted"] as Dictionary)["give"])
		invite_accepted += int((row["all_accepted"] as Dictionary)["invite"])
		for pair_key in ((row["decision_candidate_pairs"] as Dictionary)["give"] as Dictionary):
			give_pairs[pair_key] = true
		for pair_key in ((row["decision_candidate_pairs"] as Dictionary)["invite"] as Dictionary):
			invite_pairs[pair_key] = true
	print("  all-agent competitive denominator: give %d candidates / %d chosen / %d events / %d accepted across %d pairs" % [
		give_candidates, give_selected, give_events, give_accepted, give_pairs.size()])
	print("                                    invite %d candidates / %d chosen / %d events / %d accepted across %d pairs" % [
		invite_candidates, invite_selected, invite_events, invite_accepted, invite_pairs.size()])
	print("  counts are windows/ticks; selected/accepted are event counts. This receipt is observational and is excluded from Sim digests.")

func _dispose(S) -> void:
	get_root().remove_child(S)
	S.free()

# ── 统计小工具 ──
func _mean(a: Array) -> float:
	if a.is_empty(): return 0.0
	var s := 0.0
	for x in a: s += float(x)
	return s / float(a.size())

## P(treat=1 | control==cval)
func _cond(treat: Array, ctrl: Array, cval: int) -> String:
	var num := 0
	var den := 0
	for i in ctrl.size():
		if int(ctrl[i]) == cval:
			den += 1
			if int(treat[i]) == 1: num += 1
	return "n/a(0)" if den == 0 else ("%.2f(%d/%d)" % [float(num) / float(den), num, den])

## P(treat==0 | control==cval)
func _cond_neg(treat: Array, ctrl: Array, cval: int) -> String:
	var num := 0
	var den := 0
	for i in ctrl.size():
		if int(ctrl[i]) == cval:
			den += 1
			if int(treat[i]) == 0: num += 1
	return "n/a(0)" if den == 0 else ("%.2f(%d/%d)" % [float(num) / float(den), num, den])

func _stat(a: Array) -> String:
	if a.is_empty(): return "—"
	var mn := INF
	var mx := -INF
	var s := 0.0
	for x in a:
		var v := float(x)
		mn = minf(mn, v); mx = maxf(mx, v); s += v
	return "均 %.3f  范围 [%.3f, %.3f]" % [s / float(a.size()), mn, mx]

func _parse_seeds(spec: String) -> Array:
	var out: Array = []
	if "-" in spec:
		var ab := spec.split("-")
		for s in range(int(ab[0]), int(ab[1]) + 1):
			out.append(s)
	elif "," in spec:
		for s in spec.split(","):
			out.append(int(s))
	else:
		out.append(int(spec))
	return out
