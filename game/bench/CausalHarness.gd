extends SceneTree
## bench/CausalHarness.gd — Causal Bench S5：配对反事实（PN/PS/ACE）+ 系统指标（PI/cascade/Gini）。
## 用法：godot --headless --path . --script res://bench/CausalHarness.gd -- [--seeds 1-8] [--days 40]
## 方法：同 seed 同初态，对目标 agent 只翻转一个干预位 do(X=high)/do(X=low)/control，跑确定性轨迹对比结果 Y。
##   PS=P(Y|do高) 在 control 无 Y 的 seed；PN=P(¬Y|do低) 在 control 有 Y 的 seed；ACE=mean(Y_high−Y_low)。
##   纯注入式干预（不改 Sim）；后端宏观矩阵(legality/macro-drift)因 AIBackend 引用全局 Sim 留作 scene 模式。
## 纪律同 soak/S0：--script 不加载 autoload → preload 实例化，backend=null 走确定性 logic。

const SimScript = preload("res://scripts/Sim.gd")
const M = preload("res://bench/Metrics.gd")

func _init() -> void:
	var seeds := _parse_seeds("1-8")
	var days := 40
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])

	print("=== Causal Bench S5 · 配对反事实 + 系统指标  seeds=%s days=%d ===" % [str(seeds), days])

	# 三个因果假设（target 用 agent 下标，id 跨 seed 稳定）
	var H := [
		{"key": "standing→放逐", "idx": 2, "kind": "standing", "Y": "ostracized"},
		{"key": "开放(xi)→观点迁移", "idx": 0, "kind": "xi", "Y": "moved"},
		{"key": "trust→投资", "idx": 0, "idx2": 1, "kind": "trust", "Y": "invested"},
	]
	# 收集每假设的 (yc, yh, yl)
	var data := {}
	for h in H:
		data[h["key"]] = {"yc": [], "yh": [], "yl": []}
	# 指标基线（control 跑）
	var pis: Array = []
	var casc: Array = []
	var ginis: Array = []

	for sd in seeds:
		# control 跑一次：取 id、Y_ctrl、指标
		var Sc = _run(sd, days, {})
		var ids: Array = []
		for ag in Sc.agents:
			ids.append(ag["id"])
		pis.append(M.polarization(Sc))
		casc.append(M.cascade_max(Sc))
		ginis.append(M.gini_acceptance(Sc))
		var Tinj := int(0.15 * days * int(Sc.TICKS_PER_DAY))
		for h in H:
			data[h["key"]]["yc"].append(_outcome(Sc, h, ids))
		_dispose(Sc)
		# 每假设 high/low 各跑一次
		for h in H:
			var hi := _opts(h, ids, Tinj, true)
			var lo := _opts(h, ids, Tinj, false)
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

	print("\n— 配对反事实因果强度 —")
	var gate_ok := true
	for h in H:
		var d = data[h["key"]]
		var ace := _mean(d["yh"]) - _mean(d["yl"])
		var ps := _cond(d["yh"], d["yc"], 0)   # do高 | control=0 → Y
		var pn := _cond_neg(d["yl"], d["yc"], 1) # do低 | control=1 → ¬Y
		var ok := ace >= 0.3
		if not ok:
			gate_ok = false
		print("  %s %s" % ["✅" if ok else "❌", String(h["key"])])
		print("      base=%.2f  do(高)=%.2f  do(低)=%.2f  → ACE=%.2f  (PS=%s  PN=%s)" % [
			_mean(d["yc"]), _mean(d["yh"]), _mean(d["yl"]), ace, ps, pn])

	print("\n=== S5 GATE: %s  (3 假设 ACE≥0.30 为因果显著)===" % ("PASS ✅" if gate_ok else "FAIL ❌"))
	quit(0 if gate_ok else 1)

## 按假设 + 方向构造干预 opts
func _opts(h: Dictionary, ids: Array, tinj: int, high: bool) -> Dictionary:
	match String(h["kind"]):
		"standing":
			# 高=坏名声(-3,易放逐) / 低=好名声(+3)
			return {"standing": {"target": ids[h["idx"]], "value": (-3.0 if high else 3.0), "tick": tinj}}
		"xi":
			# 高=开放(易随大流) / 低=固执(锚定天生立场)
			return {"xi": {ids[h["idx"]]: (0.9 if high else 0.02)}}
		"trust":
			# 高=高信任(过投资门) / 低=负信任(挡投资)
			return {"trust": {"a": ids[h["idx"]], "b": ids[h["idx2"]], "value": (60.0 if high else -60.0), "tick": tinj}}
	return {}

## 判定结果 Y
func _outcome(S, h: Dictionary, ids: Array) -> int:
	match String(h["Y"]):
		"ostracized": return 1 if M.ostracized(S, ids[h["idx"]]) else 0
		"moved": return 1 if M.opinion_moved(S, ids[h["idx"]]) else 0
		"invested": return 1 if M.invested(S, ids[h["idx"]], ids[h["idx2"]]) else 0
	return 0

## 跑一局，opts 指定干预（xi 在 tick0 注入；standing/trust 在指定 tick 注入）。
func _run(seed: int, days: int, opts: Dictionary) -> Object:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	S.start_new(seed)
	# tick0 初始条件注入（标准 do() at t=0：在任何自然动力学前置入，效应作用全程）
	if opts.has("xi"):
		for id in opts["xi"]:
			var ag: Dictionary = S.get_agent(id)
			if not ag.is_empty():
				ag["xi"] = float(opts["xi"][id])
	var tr = opts.get("trust", null)
	if tr != null:
		var a: Dictionary = S.get_agent(String(tr["a"]))
		if not a.is_empty():
			S._rel(a, String(tr["b"]))["trust"] = float(tr["value"])
	# standing 持续保持（do(声誉=v) held）：每 tick 重注入以覆盖引擎的 GTFT 向0漂移，干净测「持续坏名声→放逐」边
	var st = opts.get("standing", null)
	var total: int = days * int(S.TICKS_PER_DAY)
	for t in range(total):
		if st != null:
			for b in S.agents:
				if b["id"] != String(st["target"]):
					S._rel(b, String(st["target"]))["standing"] = float(st["value"])
		S.tick()
	return S

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
