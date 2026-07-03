extends SceneTree
## bench/LodAblation.gd — L3 LOD 合约（三路）：固定 N 下比较 off / 保守(降频) / 激进(远端聚合统计) 三配置，
## 跨 seed 看 PI/cascade/Gini 漂移、候选枚举成本(cand_calls)、饥饿数、33 不变量。
##   · 保守版守护(docs/12 §L3 R3)：度量不显著漂移（|ΔPI|≤0.04·|Δcascade|≤1·|ΔGini|≤0.05）且不变量全绿。
##   · 激进版契约：远端 agent 成本≈0（cand_calls 大降）+ 不批量饿死 + 结构不变量全绿；
##     全局涌现度量允许漂移（远端=背景群演，不再驱动社交），这是冲上百 NPC 的取舍，如实报告。
## 用法：godot --headless --path . --script res://bench/LodAblation.gd -- [--seeds 1-8] [--agents 30] [--days 40] [--period 4]
const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")
const Met = preload("res://bench/Metrics.gd")

func _init() -> void:
	var seeds := _parse("1-8")
	var n := 30
	var days := 40
	var period := 4
	var radius := 8
	var cap := 12
	var gate := "both"   # both=保守+激进都须过；agg=只查激进(用于超出保守验证档的大 N)；con=只查保守
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size(): seeds = _parse(args[i + 1])
		elif args[i] == "--agents" and i + 1 < args.size(): n = int(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size(): days = int(args[i + 1])
		elif args[i] == "--period" and i + 1 < args.size(): period = int(args[i + 1])
		elif args[i] == "--radius" and i + 1 < args.size(): radius = int(args[i + 1])
		elif args[i] == "--cap" and i + 1 < args.size(): cap = int(args[i + 1])
		elif args[i] == "--gate" and i + 1 < args.size(): gate = args[i + 1]

	print("=== L3 LOD ablation (3路)  N=%d seeds=%s days=%d period=%d near-cap=%d ===" % [n, str(seeds), days, period, cap])
	var off := _acc()
	var con := _acc()
	var agg := _acc()
	for sd in seeds:
		_run_one(sd, n, days, period, radius, cap, "off", off)
		_run_one(sd, n, days, period, radius, cap, "con", con)
		_run_one(sd, n, days, period, radius, cap, "agg", agg)

	print("\n— 配置对比 (off | 保守 | 激进) —")
	_row("PI     ", off, con, agg, "pi", "%.3f")
	_row("cascade", off, con, agg, "casc", "%.2f")
	_row("Gini   ", off, con, agg, "gini", "%.3f")
	print("  cand_calls 均: off=%.0f  保守=%.0f  激进=%.0f   →  保守省 %.0f%% / 激进省 %.0f%%" % [
		_mean(off["cand"]), _mean(con["cand"]), _mean(agg["cand"]),
		100.0 * (1.0 - _mean(con["cand"]) / maxf(1.0, _mean(off["cand"]))),
		100.0 * (1.0 - _mean(agg["cand"]) / maxf(1.0, _mean(off["cand"])))])
	print("  饥饿(need≤0.5)累计均: off=%.0f  保守=%.0f  激进=%.0f" % [_mean(off["starv"]), _mean(con["starv"]), _mean(agg["starv"])])
	print("  不变量失败 硬/软: off=%d/%d  保守=%d/%d  激进=%d/%d" % [int(off["fh"]), int(off["fs"]), int(con["fh"]), int(con["fs"]), int(agg["fh"]), int(agg["fs"])])

	# 保守门：度量不漂 + 不变量全绿（硬+软；已验证的安全默认）
	var dpi := absf(_mean(off["pi"]) - _mean(con["pi"]))
	var dcas := absf(_mean(off["casc"]) - _mean(con["casc"]))
	var dgini := absf(_mean(off["gini"]) - _mean(con["gini"]))
	var con_ok := int(off["fh"]) + int(off["fs"]) == 0 and int(con["fh"]) + int(con["fs"]) == 0 and dpi <= 0.04 and dcas <= 1.0 and dgini <= 0.05
	# 激进门（契约=L4 两分）：硬不变量全绿(状态合法) + 成本大降(<off 70%) + 不批量饿死 + 近端仍活(liveness)。软不变量按设计可漂。
	var cost_cut := _mean(agg["cand"]) < 0.70 * _mean(off["cand"])
	var no_mass_starve := _mean(agg["starv"]) <= 1.5 * maxf(1.0, _mean(off["starv"]))
	var live := _mean(agg["cand"]) > 0.0   # 近端 cohort 仍在跑（非整镇冻结）
	var agg_ok := cost_cut and no_mass_starve and live and int(agg["fh"]) == 0
	print("\n  保守门: %s  (|ΔPI|=%.3f |Δcascade|=%.2f |ΔGini|=%.3f 不变量全绿)" % ["PASS ✅" if con_ok else "FAIL ❌", dpi, dcas, dgini])
	print("  激进门: %s  (硬不变量绿=%s 成本降=%s 不批量饿死=%s 近端活=%s；软不变量按设计可漂)" % ["PASS ✅" if agg_ok else "FAIL ❌", str(int(agg["fh"]) == 0), str(cost_cut), str(no_mass_starve), str(live)])
	var ok := con_ok and agg_ok
	if gate == "agg": ok = agg_ok
	elif gate == "con": ok = con_ok
	print("=== LOD ABLATION(3路, gate=%s): %s ===" % [gate, "PASS ✅" if ok else "FAIL ❌"])
	quit(0 if ok else 1)

func _acc() -> Dictionary:
	return {"pi": [], "casc": [], "gini": [], "cand": [], "starv": [], "fh": 0, "fs": 0}

func _run_one(seed: int, n: int, days: int, period: int, radius: int, cap: int, mode: String, acc: Dictionary) -> void:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	S.spawn_count = n
	S.decide_period = period
	S.lod_near_radius = radius
	S.lod_near_cap = cap if mode != "off" else 0
	S.lod = mode == "con"
	S.lod_aggregate = mode == "agg"
	S.start_new(seed)
	var total := days * int(S.TICKS_PER_DAY)
	var starved := 0
	for t in range(total):
		S.tick()
		for ag in S.agents:
			for nid in ag["needs"]:
				if float(ag["needs"][nid]) <= 0.5:
					starved += 1
	(acc["pi"] as Array).append(Met.polarization(S))
	(acc["casc"] as Array).append(Met.cascade_max(S))
	(acc["gini"] as Array).append(Met.gini_acceptance(S))
	(acc["cand"] as Array).append(S.cand_calls)
	(acc["starv"] as Array).append(starved)
	var sf: Dictionary = Inv.split_fails(S, starved)
	acc["fh"] = int(acc["fh"]) + int(sf["hard"])
	acc["fs"] = int(acc["fs"]) + int(sf["soft"])
	get_root().remove_child(S)
	S.free()

func _row(label: String, off: Dictionary, con: Dictionary, agg: Dictionary, key: String, fmt: String) -> void:
	print(("  %s: " + fmt + "  |  " + fmt + "  |  " + fmt) % [label, _mean(off[key]), _mean(con[key]), _mean(agg[key])])

func _mean(a: Array) -> float:
	if a.is_empty(): return 0.0
	var s := 0.0
	for x in a: s += float(x)
	return s / float(a.size())

func _parse(spec: String) -> Array:
	var out: Array = []
	if "-" in spec:
		var ab := spec.split("-")
		for s in range(int(ab[0]), int(ab[1]) + 1): out.append(s)
	else:
		for s in spec.split(","): out.append(int(s))
	return out
