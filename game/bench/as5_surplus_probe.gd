extends SceneTree
## bench/as5_surplus_probe.gd — 车道 E-export（docs/157/158）F4：物理库存 surplus 探针（选货 + 标 floor）。
##
## 回答 F4 的三个命门（都是【物理库存】的问题，不是 coverage 指标）：
##   ① 哪种货【常年物理有余量】？逐货逐 seed 追整局 town_stock 的 min/median/max（日界快照）。
##      —— surplus 货 = 它的【全局 stock 最小值】持续远高于 0（有可安全抽走的地板以上余量）。
##   ② 若以 floor 出口，最坏多日净消耗是多少？逐货算【任意起点、任意窗口】的最大净抽干
##      max_drawdown = max over windows (Σconsume − Σproduce)，这是 floor 必须盖住的量（防饿）。
##   ③ 现役 #40 满足率 headroom：逐 seed 最差货满足率（改前基线，选货不能碰贴地板的货）。
##
## 反馈耦合红线（F4）：整洁 _clean_mult=stock/cap 驱动广场吸引力 ⇒ 探针把它单列、标 [FEEDBACK]，选货时排除。
## 供给紧红线（docs/157 §一.3）：口粮/屋瓦/柴薪 是满足率紧的货，标 [TIGHT]，排除。
##
## 纯读、不改 Sim、不写 digest（同 as4_econ_probe：SimScript.new + start_new + 手动 tick）。
## 用法：godot --headless --path game -s res://bench/as5_surplus_probe.gd -- --seeds 13-30 --days 60 [--agents N]
## 逐 (seed,good) 一行 [AS5]{json}；末尾逐货一行 [AS5G]{json} 汇总跨 seed 展布。

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

# 反馈耦合货（_clean_mult 驱动广场吸引力）+ 供给紧货（#40 满足率紧）——选货红线，仅标注不参与自动挑选。
const FEEDBACK_GOODS := ["整洁"]
const TIGHT_GOODS := ["口粮", "屋瓦", "柴薪"]

func _init() -> void:
	var seeds := _parse_seeds("13-30")
	var days := 60
	var agents := 0
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])
		elif args[i] == "--agents" and i + 1 < args.size():
			agents = int(args[i + 1])
	print("=== as5_surplus_probe · agents=%d seeds=%s days=%d ===" % [agents, str(seeds), days])
	# good -> arrays over seeds
	var acc := {}   # good -> {min:[], med:[], max:[], final:[], drawdown:[], rate:[]}
	for sd in seeds:
		var rec := _run_once(sd, days, agents)
		for g in rec.keys():
			if not acc.has(g):
				acc[g] = {"min": [], "med": [], "max": [], "final": [], "drawdown": [], "rate": []}
			acc[g]["min"].append(int(rec[g]["min"]))
			acc[g]["med"].append(int(rec[g]["med"]))
			acc[g]["max"].append(int(rec[g]["max"]))
			acc[g]["final"].append(int(rec[g]["final"]))
			acc[g]["drawdown"].append(int(rec[g]["drawdown"]))
			acc[g]["rate"].append(float(rec[g]["rate"]))
			var line := JSON.stringify({"seed": sd, "good": g,
				"min": int(rec[g]["min"]), "med": int(rec[g]["med"]), "max": int(rec[g]["max"]),
				"final": int(rec[g]["final"]), "drawdown": int(rec[g]["drawdown"]), "cap": int(rec[g]["cap"]),
				"rate": float(rec[g]["rate"])})
			print("[AS5] " + line)
	for g in acc.keys():
		var tag := ""
		if g in FEEDBACK_GOODS: tag = "FEEDBACK"
		elif g in TIGHT_GOODS: tag = "TIGHT"
		else: tag = "candidate"
		var summ := {"good": g, "tag": tag,
			"stock_min": _spread_i(acc[g]["min"]),      # 跨 seed 的【全局最小 stock】展布：min 越高越有余量
			"stock_med": _spread_i(acc[g]["med"]),
			"stock_max": _spread_i(acc[g]["max"]),
			"stock_final": _spread_i(acc[g]["final"]),
			"max_drawdown": _spread_i(acc[g]["drawdown"]),  # floor 必须 ≥ 这个（最坏多日净消耗）
			"sat_rate": _spread_f(acc[g]["rate"])}
		print("[AS5G] " + JSON.stringify(summ))
	quit(0)

func _run_once(seed: int, days: int, agents: int) -> Dictionary:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data(); S.auto_run = false; S.backend = null
	if agents > 0:
		S.spawn_count = agents
	S.start_new(seed)
	var tpd := int(S.TICKS_PER_DAY)
	var goods: Array = []
	for g in S.production.get("goods", {}):
		goods.append(String(g))
	# 逐货逐日界追 town_stock 快照 + 逐日净流（consume−produce）用于 max_drawdown。
	var series := {}          # good -> [daily stock snapshots]
	var net_daily := {}       # good -> [daily net consume(=−Δ_from_flows) ...] 用 prod_stats 差分
	for g in goods:
		series[g] = [int(S._stock_of(g))]
		net_daily[g] = []
	var prev_cons := {}
	var prev_prod := {}
	for g in goods:
		prev_cons[g] = 0; prev_prod[g] = 0
	for d in range(days):
		for _t in range(tpd):
			S.tick()
		for g in goods:
			series[g].append(int(S._stock_of(g)))
			var cons_now := int((S.prod_stats.get("consumed", {}) as Dictionary).get(g, 0))
			var prod_now := int((S.prod_stats.get("produced", {}) as Dictionary).get(g, 0))
			# 净消耗 = 当日消耗 − 当日产出（>0 = 抽干日）
			net_daily[g].append((cons_now - int(prev_cons[g])) - (prod_now - int(prev_prod[g])))
			prev_cons[g] = cons_now; prev_prod[g] = prod_now
	# 满足率（改前基线，从 #40 detail 解；解不到=足→1.0）
	var report := Inv.check_all(S, 0)
	var out := {}
	for g in goods:
		var arr: Array = series[g]
		out[g] = {
			"min": _amin(arr), "med": _amed(arr), "max": _amax(arr), "final": int(arr[arr.size() - 1]),
			"drawdown": _max_window_drawdown(net_daily[g]),
			"cap": int((S.production.get("goods", {}) as Dictionary)[g].get("cap", 0)),
			"rate": _rate_from(report, g),
		}
	get_root().remove_child(S); S.free()
	return out

# 最大【多日】净抽干：任意连续窗口内 Σ(consume−produce) 的最大值（防 floor 被短窗掏空）。Kadane 变体。
func _max_window_drawdown(net: Array) -> int:
	var best := 0
	var cur := 0
	for v in net:
		cur = maxi(int(v), cur + int(v))
		best = maxi(best, cur)
	return best

func _rate_from(report: Array, good: String) -> float:
	for r in report:
		if int(r.get("id", 0)) == 40:
			var d := String(r.get("detail", ""))
			var key := good + " 满足率="
			var idx := d.find(key)
			if idx >= 0:
				return float(d.substr(idx + key.length(), 4))
	return 1.0   # 未进 starved 列 = 足

func _amin(a: Array) -> int:
	var m := int(a[0])
	for v in a: m = mini(m, int(v))
	return m
func _amax(a: Array) -> int:
	var m := int(a[0])
	for v in a: m = maxi(m, int(v))
	return m
func _amed(a: Array) -> int:
	var b := a.duplicate(); b.sort()
	return int(b[b.size() / 2])

func _spread_i(a: Array) -> String:
	if a.is_empty(): return "n/a"
	var lo = a[0]; var hi = a[0]; var s := 0
	for v in a:
		lo = mini(lo, int(v)); hi = maxi(hi, int(v)); s += int(v)
	return "min=%d mean~=%d max=%d (n=%d)" % [lo, int(s / a.size()), hi, a.size()]
func _spread_f(a: Array) -> String:
	if a.is_empty(): return "n/a"
	var lo = 9e9; var hi = -9e9; var s := 0.0
	for v in a:
		lo = minf(lo, float(v)); hi = maxf(hi, float(v)); s += float(v)
	return "min=%.3f mean~=%.3f max=%.3f (n=%d)" % [lo, s / a.size(), hi, a.size()]

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
