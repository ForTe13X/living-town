extends SceneTree
## bench/LodAblation.gd — L3 LOD 合约（三路）：固定 N 下比较 off / 保守(降频) / 激进(远端聚合统计) 三配置，
## 跨 seed 看 PI/cascade/Gini 漂移、候选枚举成本(cand_calls)、饥饿数、33 不变量。
##   · 保守版守护(docs/12 §L3 R3)：度量不显著漂移（|ΔPI|≤0.04·|Δcascade|≤1·|ΔGini|≤0.05）且不变量全绿。
##   · 激进版契约：远端 agent 成本≈0（cand_calls 大降）+ 不批量饿死 + 结构不变量全绿；
##     全局涌现度量允许漂移（远端=背景群演，不再驱动社交），这是冲上百 NPC 的取舍，如实报告。
##
## ⚠ 契约的适用边界（docs/35）：「软不变量按设计可漂」对【bench 里量成本】是站得住的，
##   但它【不是】"激进 LOD 该不该默认开"的证据——因为软不变量量的就是涌现社交行为，而涌现社交行为
##   就是这个产品本身。用只查硬不变量的门去批准一个默认值，等于用"状态没坏"证明"东西还好玩"。
##   故本文件加一条【只报告、默认不成门】的软不变量臂：按配置打出失败条数 + 【失败的具体 id】
##   （不写死条数——#15 已被降级为诊断项，见 Invariants.DIAG_IDS）+ 接受度 Gini。
##   --soft-gate 才把它变成门（要求激进版的非诊断软失败不多于 off 基线）。
## 用法：godot --headless --path . --script res://bench/LodAblation.gd -- [--seeds 1-8] [--agents 30] [--days 40] [--period 4] [--soft-gate]
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
	var soft_gate := false  # 默认 false：软臂只报告，不改既有门的判定（不把已绿的 bench 弄红）
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size(): seeds = _parse(args[i + 1])
		elif args[i] == "--agents" and i + 1 < args.size(): n = int(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size(): days = int(args[i + 1])
		elif args[i] == "--period" and i + 1 < args.size(): period = int(args[i + 1])
		elif args[i] == "--radius" and i + 1 < args.size(): radius = int(args[i + 1])
		elif args[i] == "--cap" and i + 1 < args.size(): cap = int(args[i + 1])
		elif args[i] == "--gate" and i + 1 < args.size(): gate = args[i + 1]
		elif args[i] == "--soft-gate": soft_gate = true   # 把软臂变成门（默认只报告）

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

	# ── 软不变量臂（docs/35）：默认【只报告】。这里才看得见"激进 LOD 到底毁掉了哪些涌现行为"。
	# 失败 id 逐条打出、不写死条数（Invariants 的 HARD/DIAG 划分随时会变，写死等于埋一颗定时炸弹）。
	print("\n— 软不变量臂（涌现行为；默认只报告，加 --soft-gate 才成门）—")
	_soft_row("off ", off, seeds.size())
	_soft_row("保守", con, seeds.size())
	_soft_row("激进", agg, seeds.size())
	# 接受度 Gini：报【绝对值 + 逐 seed 极差】，不只百分比（B10/评审：0.10→0.03 的实际变化是 −0.07；
	# 用百分比说话会让一个小绝对量听起来像塌方）。并列出观测口径，因为 Gini 塌陷可能是【观测的】而非行为的：
	# 见 bench/lod_observation_probe.gd 的判别实验与 docs/35 §2.4。
	print("  接受度 Gini（绝对值，逐 seed 极差）: off=%.4f [%.4f,%.4f]  保守=%.4f [%.4f,%.4f]  激进=%.4f [%.4f,%.4f]" % [
		_mean(off["gini"]), _min(off["gini"]), _max(off["gini"]),
		_mean(con["gini"]), _min(con["gini"]), _max(con["gini"]),
		_mean(agg["gini"]), _min(agg["gini"]), _max(agg["gini"])])
	print("    激进 − off = %+.4f 绝对（= %+.0f%% 相对；百分比在小绝对量上会放大观感，两者并列）" % [
		_mean(agg["gini"]) - _mean(off["gini"]),
		100.0 * (_mean(agg["gini"]) / maxf(0.0001, _mean(off["gini"])) - 1.0)])
	print("    观测口径（Gini 是否可比的前提）: 提议数/agent off=%.1f 保守=%.1f 激进=%.1f；" % [
		_mean(off["propspa"]), _mean(con["propspa"]), _mean(agg["propspa"])]
		+ " 均接受率 off=%.3f 保守=%.3f 激进=%.3f；" % [_mean(off["rate"]), _mean(con["rate"]), _mean(agg["rate"])]
		+ " 零观测 agent(被 Metrics 整个剔除，不计 0 也不计 1) off=%.1f 保守=%.1f 激进=%.1f" % [
			_mean(off["zero"]), _mean(con["zero"]), _mean(agg["zero"])])
	print("    ⚠ 均接受率贴近 1.0 时 Gini 必然趋 0（全体挤在同一个值），这与「社会分化被抹平」不是同一件事。")
	# #14 的原始量：跨度过没过阈是个二值，说明不了「跨度塌成 0」。直接打 standing 的跨度与方差。
	print("  standing 原始分化（#14 量的是跨度>0 这个二值；这里给原始量）: 跨度 off=%.2f 保守=%.2f 激进=%.2f；方差 off=%.4f 保守=%.4f 激进=%.4f" % [
		_mean(off["stspan"]), _mean(con["stspan"]), _mean(agg["stspan"]),
		_mean(off["stvar"]), _mean(con["stvar"]), _mean(agg["stvar"])])
	var off_ng := int(off["fs"]) - int(off["fdiag"])
	var agg_ng := int(agg["fs"]) - int(agg["fdiag"])
	var soft_ok := agg_ng <= off_ng
	print("  软臂判定: %s  (激进非诊断软失败 %d ≤ off 基线 %d ?)  ← %s" % [
		"PASS ✅" if soft_ok else "FAIL ❌", agg_ng, off_ng,
		"计入总门(--soft-gate)" if soft_gate else "仅报告，不计入总门"])

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
	if soft_gate:
		ok = ok and soft_ok
	print("=== LOD ABLATION(3路, gate=%s, soft-gate=%s): %s ===" % [gate, str(soft_gate), "PASS ✅" if ok else "FAIL ❌"])
	quit(0 if ok else 1)

## 打一行软不变量明细：失败总数 / 其中诊断项(不该成门) / 逐 id 的失败 seed 数。
func _soft_row(label: String, acc: Dictionary, nseeds: int) -> void:
	var ids: Dictionary = acc["soft_by_id"]
	var keys := ids.keys()
	keys.sort()
	var parts := PackedStringArray()
	for k in keys:
		var diag := " (诊断,不成门)" if int(k) in _diag_ids() else ""
		parts.append("#%d×%d%s" % [int(k), int(ids[k]), diag])
	print("  %s: 软失败 %d 次(%d seed 累计, 其中诊断项 %d 次) 失败项: %s" % [
		label, int(acc["fs"]), nseeds, int(acc["fdiag"]),
		", ".join(parts) if parts.size() > 0 else "无"])

## 诊断项 id（永不成门）。从 Invariants 读，绝不在此写死——B1 已把 #15 降级，将来还会变。
func _diag_ids() -> Array:
	if "DIAG_IDS" in Inv:
		return Inv.DIAG_IDS
	return []

func _acc() -> Dictionary:
	return {"pi": [], "casc": [], "gini": [], "cand": [], "starv": [], "fh": 0, "fs": 0, "fdiag": 0, "soft_by_id": {},
		# B10 观测口径 + #14 原始量（纯报告，不参与任何门的判定）
		"propspa": [], "rate": [], "zero": [], "stspan": [], "stvar": []}

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
	# B10 观测口径 + standing 原始量。【必须在 Inv.check_all 之前算】：check_all 里的 perceived 会用
	# S._rel() 惰性建出一堆 standing=0 的关系条目，跑完再统计会被这些零稀释方差。纯读，零扰动。
	_observe(S, acc)
	# 自己走一遍 check_all（而不是 Inv.split_fails）——为的是拿到【失败的 id】。
	# 硬/软的归类逐字沿用 split_fails（hard 标志位），故 fh/fs 与旧值恒等 → 既有门判定逐字节不变。
	# 额外记：每个失败 id 的累计次数、以及其中属于诊断项(DIAG_IDS)的次数。
	var diag: Array = _diag_ids()
	for c in Inv.check_all(S, starved):
		if bool(c["ok"]):
			continue
		if bool(c["hard"]):
			acc["fh"] = int(acc["fh"]) + 1
			continue
		acc["fs"] = int(acc["fs"]) + 1
		var cid := int(c["id"])
		if cid in diag:
			acc["fdiag"] = int(acc["fdiag"]) + 1
		var by: Dictionary = acc["soft_by_id"]
		by[cid] = int(by.get(cid, 0)) + 1
	get_root().remove_child(S)
	S.free()

## 纯读的观测口径统计（B10）：每 agent 的提议数（=接受机会数）、均接受率、零观测 agent 数，
## 以及 standing 的原始跨度/方差。提议事件类型逐字沿用 Metrics.gini_acceptance 的那 6 类——
## 另立口径就没法和 Gini 对照了。不写 Sim 态、不抽 RNG ⇒ digest 零扰动。
func _observe(S, acc: Dictionary) -> void:
	const PROP_TYPES := ["greet", "give", "gossip", "invite", "gossip_rep", "discuss"]
	var prop := {}
	var got := {}
	for ag in S.agents:
		prop[ag["id"]] = 0; got[ag["id"]] = 0
	for e in S.event_log:
		if String(e["type"]) in PROP_TYPES and prop.has(e["actor"]):
			prop[e["actor"]] = int(prop[e["actor"]]) + 1
			if bool(e["accepted"]): got[e["actor"]] = int(got[e["actor"]]) + 1
	var rates: Array = []
	var zero := 0
	var tot := 0
	for ag in S.agents:
		var p := int(prop[ag["id"]])
		tot += p
		if p > 0: rates.append(float(got[ag["id"]]) / float(p))
		else: zero += 1
	(acc["propspa"] as Array).append(float(tot) / maxf(1.0, float(S.agents.size())))
	(acc["rate"] as Array).append(_mean(rates))
	(acc["zero"] as Array).append(zero)
	var st: Array = []
	for ag in S.agents:
		for oid in ag["relationships"]:
			st.append(float(ag["relationships"][oid]["standing"]))
	var lo := 0.0
	var hi := 0.0
	for v in st: lo = minf(lo, float(v)); hi = maxf(hi, float(v))
	var m := _mean(st)
	var vr := 0.0
	for v in st: vr += (float(v) - m) * (float(v) - m)
	(acc["stspan"] as Array).append(hi - lo)
	(acc["stvar"] as Array).append(vr / maxf(1.0, float(st.size())))

func _row(label: String, off: Dictionary, con: Dictionary, agg: Dictionary, key: String, fmt: String) -> void:
	print(("  %s: " + fmt + "  |  " + fmt + "  |  " + fmt) % [label, _mean(off[key]), _mean(con[key]), _mean(agg[key])])

func _mean(a: Array) -> float:
	if a.is_empty(): return 0.0
	var s := 0.0
	for x in a: s += float(x)
	return s / float(a.size())

func _min(a: Array) -> float:
	if a.is_empty(): return 0.0
	var m := float(a[0])
	for x in a: m = minf(m, float(x))
	return m

func _max(a: Array) -> float:
	if a.is_empty(): return 0.0
	var m := float(a[0])
	for x in a: m = maxf(m, float(x))
	return m

func _parse(spec: String) -> Array:
	var out: Array = []
	if "-" in spec:
		var ab := spec.split("-")
		for s in range(int(ab[0]), int(ab[1]) + 1): out.append(s)
	else:
		for s in spec.split(","): out.append(int(s))
	return out
