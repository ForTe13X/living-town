extends SceneTree
## bench/as5_export_probe.gd — 车道 E-export 标定 + held-out 展布（docs/158 移金标纪律 deliverable 4）。
##
## 逐 seed 报（改后、export 激活）：
##   town_coin min/final · external final · wages_skipped · 出口货(豆子)出港量 export_qty · export 事件数 ·
##   external 付不起被跳过的出港日 export_stall · 豆子期末库存 · #40/#34/#35/#45/#46 各 ok（硬门必全绿）。
## 汇总跨 seed 展布 + 硬门通过计数。
##
## 纯读、不改 Sim、不写 digest（同 as4_econ_probe）。
## 用法：godot --headless --path game -s res://bench/as5_export_probe.gd -- --seeds 13-30 --days 60 [--agents N] [--out x.jsonl]

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

func _init() -> void:
	var seeds := _parse_seeds("13-30")
	var days := 60
	var agents := 0
	var out_path := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])
		elif args[i] == "--agents" and i + 1 < args.size():
			agents = int(args[i + 1])
		elif args[i] == "--out" and i + 1 < args.size():
			out_path = args[i + 1]
	var f: FileAccess = null
	if out_path != "":
		f = FileAccess.open(out_path, FileAccess.WRITE)
	print("=== as5_export_probe · agents=%d seeds=%s days=%d ===" % [agents, str(seeds), days])
	var town_min: Array = []; var town_fin: Array = []; var ext_fin: Array = []
	var wskip: Array = []; var xqty: Array = []; var xev: Array = []; var xstall: Array = []
	var h40 := 0; var h34 := 0; var h35 := 0; var h45 := 0; var h46 := 0; var n := 0
	for sd in seeds:
		var rec := _run_once(sd, days, agents)
		n += 1
		town_min.append(int(rec["town_coin_min"])); town_fin.append(int(rec["town_coin_final"]))
		ext_fin.append(int(rec["external_final"])); wskip.append(int(rec["wages_skipped"]))
		xqty.append(int(rec["export_qty"])); xev.append(int(rec["export_events"])); xstall.append(int(rec["export_stall_days"]))
		if bool(rec["i40"]): h40 += 1
		if bool(rec["i34"]): h34 += 1
		if bool(rec["i35"]): h35 += 1
		if bool(rec["i45"]): h45 += 1
		if bool(rec["i46"]): h46 += 1
		var line := JSON.stringify(rec)
		print("[AS5EXP] " + line)
		if f: f.store_line(line)
	var summ := {
		"seeds": str(seeds), "days": days, "n": n,
		"town_coin_min": _spread_i(town_min), "town_coin_final": _spread_i(town_fin),
		"external_final": _spread_i(ext_fin), "wages_skipped": _spread_i(wskip),
		"export_qty(豆子)": _spread_i(xqty), "export_events": _spread_i(xev), "export_stall_days": _spread_i(xstall),
		"hard_pass": "#40 %d/%d · #34 %d/%d · #35 %d/%d · #45 %d/%d · #46 %d/%d" % [h40, n, h34, n, h35, n, h45, n, h46, n],
	}
	var sline := JSON.stringify(summ)
	print("[AS5EXPSUM] " + sline)
	if f:
		f.store_line(sline); f.close()
	# 硬门必全绿（#34/#35/#45/#46 硬；#40 软但 export 不该打红它）。
	var all_hard := (h34 == n and h35 == n and h45 == n and h46 == n and h40 == n)
	quit(0 if all_hard else 1)

func _run_once(seed: int, days: int, agents: int) -> Dictionary:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data(); S.auto_run = false; S.backend = null
	if agents > 0:
		S.spawn_count = agents
	S.start_new(seed)
	var tpd := int(S.TICKS_PER_DAY)
	var tmin := int(S.town_coin)
	for _t in range(days * tpd):
		S.tick()
		tmin = mini(tmin, int(S.town_coin))
	# 出港量 = Σ export 事件件数；export 事件数；付不起被跳的出港日 = 排期日 − 实际出港日。
	var xqty := 0; var xev := 0
	var deliv_days := {}
	for e in S.event_log:
		if String(e["type"]) == "export":
			xqty += Inv._amt_of(String(e.get("note", ""))); xev += 1
			deliv_days[int(int(e.get("tick", 0)) / tpd)] = true
	var scheduled := 0
	for ln in S.logistics.get("export_lanes", []):
		if not (ln is Dictionary): continue
		var every := int((ln as Dictionary).get("every_days", 0))
		if every <= 0: continue
		for d in range(1, days + 1):
			if d % every == 0: scheduled += 1
	var rep := Inv.check_all(S, 0)
	var rec := {
		"seed": seed, "n_agents": S.agents.size(),
		"town_coin_min": tmin, "town_coin_final": int(S.town_coin),
		"external_final": int(S.external_coin), "econ_total0": int(S.econ_total0), "money_total": int(S.money_total()),
		"wages_skipped": int(S.econ_stats.get("wages_skipped", 0)),
		"export_qty": xqty, "export_events": xev,
		"export_scheduled_days": scheduled, "export_stall_days": scheduled - deliv_days.size(),
		"bean_stock_final": int(S._stock_of("豆子")),
		"i40": _ok(rep, 40), "i34": _ok(rep, 34), "i35": _ok(rep, 35), "i45": _ok(rep, 45), "i46": _ok(rep, 46),
		"d40": _detail(rep, 40),
	}
	get_root().remove_child(S); S.free()
	return rec

func _ok(rep: Array, iid: int) -> bool:
	for r in rep:
		if int(r.get("id", 0)) == iid: return bool(r.get("ok", false))
	return true
func _detail(rep: Array, iid: int) -> String:
	for r in rep:
		if int(r.get("id", 0)) == iid: return String(r.get("detail", ""))
	return ""
func _spread_i(a: Array) -> String:
	if a.is_empty(): return "n/a"
	var lo = a[0]; var hi = a[0]; var s := 0
	for v in a:
		lo = mini(lo, int(v)); hi = maxi(hi, int(v)); s += int(v)
	return "min=%d mean~=%d max=%d sum=%d (n=%d)" % [lo, int(s / a.size()), hi, s, a.size()]
func _parse_seeds(spec: String) -> Array:
	var out: Array = []
	if "-" in spec:
		var ab := spec.split("-")
		for s in range(int(ab[0]), int(ab[1]) + 1): out.append(s)
	elif "," in spec:
		for s in spec.split(","): out.append(int(s))
	else: out.append(int(spec))
	return out
