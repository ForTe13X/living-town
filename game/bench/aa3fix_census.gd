extends SceneTree
## fix_census.gd — AA3-FIX 的测量探针（docs/112）。只读 Sim（--mutate 除外，且只改 event_log 副本内存）。
## 逐 seed 输出：
##   buy_total / buy_witnessed(wn>0) / buy_vendor_in(witnesses 含商贩) / buy_vendor_only(witnesses 只有商贩)
##   spill_nonbuy_witnessed（非买卖 pay 带目击者——#43 反向臂的原料）
##   digest / event_digest / events_total（自证不扰动 or 观测变更定位）
##   inv43: {ok, detail} 与 hard_fails（check_all 全量）
## --mutate vendoronly：跑完后把每条 buy pay 事件的 witnesses 改成 [商贩]（合成"全部自证"），
##   再跑一遍 check_all —— 新判据(#43 sales_w 数商贩以外)必须红，旧判据(wn>0)会绿。牙齿测试用。
## --mutate keepone：只保留【第一条带非商贩目击者的 buy 事件】的 witnesses，其余全部清空——
##   合成"99% 通道损失"。#43 正向臂只要 sales_w>=1 就绿 ⇒ 预期【绿】（does_not_detect，跑出来的）。
const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

func _init() -> void:
	var seeds := _parse_seeds("1-12")
	var days := 60
	var agents := 12
	var mutate := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])
		elif args[i] == "--agents" and i + 1 < args.size():
			agents = int(args[i + 1])
		elif args[i] == "--mutate" and i + 1 < args.size():
			mutate = args[i + 1]
	print("=== fix_census · agents=%d seeds=%s days=%d mutate=%s ===" % [agents, str(seeds), days, mutate])
	for sd in seeds:
		var rec := _run_once(sd, days, agents, mutate)
		print("[FIXCENSUS] " + JSON.stringify(rec))
	quit(0)

func _run_once(seed: int, days: int, agents: int, mutate: String) -> Dictionary:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	if agents > 0:
		S.spawn_count = agents
	S.start_new(seed)
	var starved := 0
	var by_need := {}
	for _t in range(days * int(S.TICKS_PER_DAY)):
		S.tick()
		for ag in S.agents:
			for nid in ag["needs"]:
				if float(ag["needs"][nid]) <= 0.5:
					starved += 1
					by_need[nid] = int(by_need.get(nid, 0)) + 1
	var vend: Dictionary = S.production.get("vendor", {}) if S.production.get("vendor", {}) is Dictionary else {}
	var v_id := String(S._holder_of_title(String(vend.get("title", ""))))
	var buy_note := "buy:" + String(vend.get("action", ""))
	var digest_pre := str(Inv.digest(S))
	if mutate == "vendoronly":
		for e0 in S.event_log:
			if String(e0.get("type", "")) == "pay" and String(e0.get("note", "")) == buy_note \
					and String(e0.get("target", "")) == v_id:
				e0["witnesses"] = [v_id]
	elif mutate == "keepone":
		var kept := false
		for e1 in S.event_log:
			if String(e1.get("type", "")) == "pay" and String(e1.get("note", "")) == buy_note \
					and String(e1.get("target", "")) == v_id:
				var has_other := false
				for w1 in (e1.get("witnesses", []) as Array):
					if String(w1) != v_id:
						has_other = true
				if has_other and not kept:
					kept = true          # 第一条带非商贩目击者的留着
				else:
					e1["witnesses"] = []
	var buy_total := 0
	var buy_witnessed := 0
	var buy_vendor_in := 0
	var buy_vendor_only := 0
	var spill := 0
	for e in S.event_log:
		if String(e.get("type", "")) != "pay":
			continue
		var wits: Array = e.get("witnesses", []) as Array
		if v_id != "" and String(e.get("note", "")) == buy_note and String(e.get("target", "")) == v_id:
			buy_total += 1
			if wits.size() > 0:
				buy_witnessed += 1
				var others := 0
				var vin := false
				for w in wits:
					if String(w) == v_id:
						vin = true
					else:
						others += 1
				if vin:
					buy_vendor_in += 1
				if vin and others == 0:
					buy_vendor_only += 1
		elif wits.size() > 0:
			spill += 1
	var checks: Array = Inv.check_all(S, starved, by_need)
	var inv43 := {}
	var hard_fails: Array = []
	for c in checks:
		if int(c["id"]) == 43:
			inv43 = {"ok": bool(c["ok"]), "detail": String(c["detail"])}
		if not bool(c["ok"]) and bool(c.get("hard", false)) and not (int(c["id"]) in Inv.DIAG_IDS):
			hard_fails.append(int(c["id"]))
	var rec := {"seed": seed, "days": days, "n_agents": S.agents.size(),
		"vendor_id": v_id, "mutate": mutate,
		"buy_total": buy_total, "buy_witnessed": buy_witnessed,
		"buy_vendor_in": buy_vendor_in, "buy_vendor_only": buy_vendor_only,
		"spill_nonbuy_witnessed": spill,
		"digest": digest_pre, "event_digest": str(S.event_digest), "events_total": S.event_log.size(),
		"hard_fails": hard_fails, "inv43": inv43}
	get_root().remove_child(S)
	S.free()
	return rec

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
