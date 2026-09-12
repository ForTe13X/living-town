extends SceneTree
## bench/as4_econ_probe.gd — 车道 E2a（docs/151/154）：import 付费的【标定 + 到货活性】只读探针。
##
## 回答三个问题（都是 price_per 标定的命门）：
##   ① town_coin 会不会被进口付费单调抽干？（min/final town_coin，逐 seed）
##   ② 进口在 60 天里【持续到货】吗，还是后 1/3 局静默断供？（import 交货天数 / 最后一次交货是第几天 /
##      「因缺钱被跳过」的进口日数 skipped_broke）
##   ③ 缺钱会不会让工资爆表跳发？（wages_skipped，对照 base）
## 附带：柴薪供给（consumed/short）+ external_coin(=累计付款) + meals/wages 计数，供逐 seed 展布。
##
## 口径：走 t1_workfloor_probe 同一套（SimScript.new + start_new + 手动 tick），backend=null 走确定性 logic。
##   探针纯读、不挂 decision_sink、不改 digest（同 seed 带/不带探针 digest 一致——本探针根本不写 Sim）。
##
## 用法：
##   godot --headless --path game -s res://bench/as4_econ_probe.gd -- --seeds 1-12 --days 60 [--agents 12] [--out x.jsonl]
##   逐 seed 一行 [AS4ECON]{json}；末尾一行 [AS4SUM] 汇总展布。

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

func _init() -> void:
	var seeds := _parse_seeds("1-12")
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
	print("=== as4_econ_probe · agents=%d seeds=%s days=%d ===" % [agents, str(seeds), days])
	var town_finals: Array = []
	var town_mins: Array = []
	var last_deliv: Array = []
	var skipped: Array = []
	var fw_rates: Array = []
	var wskip: Array = []
	for sd in seeds:
		var rec := _run_once(sd, days, agents)
		town_finals.append(int(rec["town_coin_final"]))
		town_mins.append(int(rec["town_coin_min"]))
		last_deliv.append(int(rec["import_last_deliv_day"]))
		skipped.append(int(rec["import_skipped_broke"]))
		fw_rates.append(float(rec["firewood_rate"]))
		wskip.append(int(rec["wages_skipped"]))
		var line := JSON.stringify(rec)
		print("[AS4ECON] " + line)
		if f: f.store_line(line)
	var summ := {
		"seeds": str(seeds), "days": days,
		"town_coin_final": _spread_i(town_finals),
		"town_coin_min": _spread_i(town_mins),
		"import_last_deliv_day": _spread_i(last_deliv),
		"import_skipped_broke": _spread_i(skipped),
		"firewood_rate": _spread_f(fw_rates),
		"wages_skipped": _spread_i(wskip),
	}
	var sline := JSON.stringify(summ)
	print("[AS4SUM] " + sline)
	if f:
		f.store_line(sline)
		f.close()
	quit(0)

func _run_once(seed: int, days: int, agents: int) -> Dictionary:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	if agents > 0:
		S.spawn_count = agents
	S.start_new(seed)
	var tpd := int(S.TICKS_PER_DAY)
	var town_min := int(S.town_coin)
	# 进口交货活性：跑满整局，逐 tick 追 town_coin 最小值。
	for _t in range(days * tpd):
		S.tick()
		town_min = mini(town_min, int(S.town_coin))
	# 从 event_log 直接读【真到货】：import 事件数 + 最后一次到货是第几天（== 交货活性，读 e["tick"] 稳妥，
	#   不依赖对日界相位的猜测）。scheduled = 按 lane 排期解析（day%every==0），skipped = scheduled − delivered。
	var import_evts := 0
	var last_deliv_day := -1
	for e in S.event_log:
		if String(e.get("type", "")) == "import":
			import_evts += 1
			last_deliv_day = maxi(last_deliv_day, int(int(e.get("tick", 0)) / tpd))
	var scheduled_days := 0
	for ln in S.logistics.get("import_lanes", []):
		if not (ln is Dictionary):
			continue
		var every := int((ln as Dictionary).get("every_days", 0))
		if every <= 0:
			continue
		for d in range(1, days + 1):
			if d % every == 0:
				scheduled_days += 1
	var delivered_days := import_evts
	# 柴薪供给率（复用 #40 同口径：consumed / demand），从 Inv.check_all 的 #40 detail 里解，稳妥且与门一致。
	var report: Array = Inv.check_all(S, 0)
	var fw_rate := _firewood_rate_from(report)
	# external_coin = 累计付款；econ 守恒核对
	var rec := {
		"seed": seed, "n_agents": S.agents.size(), "days": days,
		"town_coin_final": int(S.town_coin),
		"town_coin_min": town_min,
		"external_coin": int(S.external_coin),
		"econ_total0": int(S.econ_total0),
		"money_total": int(S.money_total()),
		"import_scheduled_days": scheduled_days,
		"import_delivered_days": delivered_days,
		"import_skipped_broke": scheduled_days - delivered_days,
		"import_last_deliv_day": last_deliv_day,
		"import_events": import_evts,
		"firewood_stock_final": int(S._stock_of("柴薪")),
		"firewood_rate": fw_rate,
		"meals_paid": int(S.econ_stats.get("meals_paid", 0)),
		"meals_free": int(S.econ_stats.get("meals_free", 0)),
		"wages_paid": int(S.econ_stats.get("wages_paid", 0)),
		"wages_skipped": int(S.econ_stats.get("wages_skipped", 0)),
		"inv34_ok": _inv_ok(report, 34),
		"inv35_ok": _inv_ok(report, 35),
		"inv45_ok": _inv_ok(report, 45),
	}
	get_root().remove_child(S)
	S.free()
	return rec

func _firewood_rate_from(report: Array) -> float:
	# #40 detail 里若柴薪进了 starved 列会印 "柴薪 满足率=x.xx"；否则解不到就回 -1（未进判决/够足）。
	for r in report:
		if int(r.get("id", 0)) == 40:
			var d := String(r.get("detail", ""))
			var idx := d.find("柴薪 满足率=")
			if idx >= 0:
				var sub := d.substr(idx + "柴薪 满足率=".length(), 4)
				return float(sub)
	return -1.0

func _inv_ok(report: Array, iid: int) -> bool:
	for r in report:
		if int(r.get("id", 0)) == iid:
			return bool(r.get("ok", false))
	return true

func _spread_i(a: Array) -> String:
	if a.is_empty():
		return "n/a"
	var lo = a[0]; var hi = a[0]; var s := 0
	for v in a:
		lo = mini(lo, int(v)); hi = maxi(hi, int(v)); s += int(v)
	return "min=%d med~=%d max=%d (n=%d)" % [lo, int(s / a.size()), hi, a.size()]

func _spread_f(a: Array) -> String:
	if a.is_empty():
		return "n/a"
	var lo = 9e9; var hi = -9e9; var s := 0.0
	for v in a:
		lo = minf(lo, float(v)); hi = maxf(hi, float(v)); s += float(v)
	return "min=%.3f med~=%.3f max=%.3f (n=%d)" % [lo, s / a.size(), hi, a.size()]

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
