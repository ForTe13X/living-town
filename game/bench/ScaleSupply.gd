extends SceneTree
## bench/ScaleSupply.gd — I3：把 #40 的供给满足率在 N ∈ {12,30,60} 上量出来（**只量，不修**）。
##
## 为什么要新写一个探针而不是读 Harness 的 [S0] 行：
##   [S0] 只吐 pass/hard_fails/soft_fails——**它告诉你 #40 红了，不告诉你红在哪种货、红多深**。
##   而本棒要回答的问题（"如果红，是真短缺还是判据在大 N 下失准"）只能由**分布**分开，
##   pass/fail 那条线上两者长得一模一样（docs/53 §三 原话）。
##
## 口径纪律（docs/41 §5）：
##   · 逐 seed 输出，**不在探针里做任何平均**。均值由报告方自己算，且必须连展布一起报。
##   · 满足率的分子/分母**逐字照抄 Invariants.gd:513-579** 的算法（含"当日待入账"那一截与
##     "原料需求从在班完成次数补"那一条）。同一份数据同时跑 `Inv.check_all`，
##     于是探针自算的 rate 与门真正的判决**互为对照**——对不上就是我抄错了，会当场打印 MISMATCH。
##   · 中途快照（--checkpoints）用于回答"60 天够不够收敛"：`SUPPLY_MIN_DAYS=60` 是 N=12 标的，
##     大 N 下那条瞬态可能更长也可能更短，而这一格没人量过。
##
## 用法：
##   godot --headless --path game -s res://bench/ScaleSupply.gd -- \
##       --agents 60 --seeds 1-12 --days 60 [--checkpoints 30,40,50,60] [--out <path.jsonl>]
##   --agents 0 = 数据原样（12 人；agents.json 6 条 + personas 轮转到 12？见回执，实测是 12）
##
## ⚠ 本文件**只读** Sim，不写任何仿真状态；跑它不改金标、不进 ci.sh（docs/53 §三：接不接线是下一波的决定）。

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

func _init() -> void:
	var seeds := _parse_seeds("1-12")
	var days := 60
	var agents := 0
	var checkpoints: Array = []
	var out_path := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])
		elif args[i] == "--agents" and i + 1 < args.size():
			agents = int(args[i + 1])
		elif args[i] == "--checkpoints" and i + 1 < args.size():
			for c in String(args[i + 1]).split(","):
				checkpoints.append(int(c))
		elif args[i] == "--out" and i + 1 < args.size():
			out_path = args[i + 1]
	checkpoints.sort()

	var f: FileAccess = null
	if out_path != "":
		f = FileAccess.open(out_path, FileAccess.WRITE)

	print("=== ScaleSupply · agents=%d seeds=%s days=%d checkpoints=%s ===" % [
		agents, str(seeds), days, str(checkpoints)])
	var t_all := Time.get_ticks_msec()
	for sd in seeds:
		var t0 := Time.get_ticks_msec()
		var rec := _run_once(sd, days, agents, checkpoints)
		rec["wall_ms"] = Time.get_ticks_msec() - t0
		var line := JSON.stringify(rec)
		print("[SCALE] " + line)
		if f: f.store_line(line)
	print("=== ScaleSupply done  总墙钟=%.1fs ===" % ((Time.get_ticks_msec() - t_all) / 1000.0))
	if f: f.close()
	quit(0)

## 跑一局，返回一条机读记录。结构照抄 Harness._run_once（backend=null、auto_run=false、显式 _load_data）。
func _run_once(seed: int, days: int, agents: int, checkpoints: Array) -> Dictionary:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	if agents > 0:
		S.spawn_count = agents
	S.start_new(seed)
	var tpd: int = int(S.TICKS_PER_DAY)
	var total: int = days * tpd
	var starved := 0
	var starve_by_need: Dictionary = {}
	var starve_by_ag: Dictionary = {}
	var starve_first_tick := -1
	# 快照：day -> {ev_n, stock_day, attempts, work, stock, spoiled, short}
	var snaps: Dictionary = {}
	var cp: Dictionary = {}
	for c in checkpoints:
		if int(c) > 0 and int(c) <= days:
			cp[int(c) * tpd - 1] = int(c)
	for t in range(total):
		S.tick()
		if cp.has(t):
			snaps[int(cp[t])] = {
				"ev_n": S.event_log.size(),
				"stock_day": (S._stock_day as Dictionary).duplicate(true),
				"attempts": ((S.prod_stats.get("attempts", {})) as Dictionary).duplicate(true),
				"work": ((S.prod_stats.get("work", {})) as Dictionary).duplicate(true),
				"short": ((S.prod_stats.get("short", {})) as Dictionary).duplicate(true),
				"spoiled": ((S.prod_stats.get("spoiled", {})) as Dictionary).duplicate(true),
				"stock": (S.town_stock as Dictionary).duplicate(true),
			}
		for ag in S.agents:
			for nid in ag["needs"]:
				if float(ag["needs"][nid]) <= 0.5:
					starved += 1
					# 硬 #1 只给一个总数（"触底 need·tick=N"），分不出是谁的哪个需求。
					# 大 N 上它偶发变红（本棒实测：6 个 N × 12 seed 里 3 例），而"缺货绝不阻断动作"是设计红线
					# （Sim._consume_for 不改 option/不改 need）⇒ 红的原因不可能是供给，必须能指名道姓才判得了。
					# 实测三例 3/3 触底的都是 social 而非 hunger —— 名字叫"无饿穿"，查的却是【任何】need≤0.5（docs/54 §五）。
					starve_by_need[String(nid)] = int(starve_by_need.get(String(nid), 0)) + 1
					starve_by_ag[String(ag["id"])] = int(starve_by_ag.get(String(ag["id"]), 0)) + 1
					if starve_first_tick < 0:
						starve_first_tick = t

	var rec: Dictionary = {
		"agents_arg": agents, "n_agents": S.agents.size(), "seed": seed, "days": days,
		"starved": starved, "events": S.event_log.size(),
		"starve_by_need": starve_by_need, "starve_by_agent": starve_by_ag,
		"starve_first_tick": starve_first_tick, "starve_first_day": (starve_first_tick / tpd) if starve_first_tick >= 0 else -1,
		"digest": str(Inv.digest(S)),
	}
	# ── 门真正的判决（同一份 S）：拿 #40 的 ok/detail，作为探针自算 rate 的对照 ──
	var checks: Array = Inv.check_all(S, starved)
	var hard_fails: Array = []
	var soft_fails: Array = []
	for c in checks:
		if c["ok"]:
			continue
		if int(c["id"]) in Inv.DIAG_IDS:
			continue
		if bool(c.get("hard", false)):
			hard_fails.append(int(c["id"]))
		else:
			soft_fails.append(int(c["id"]))
		rec["fail_detail_%d" % int(c["id"])] = String(c["detail"])
		if int(c["id"]) == 40:
			rec["inv40_detail"] = String(c["detail"])
	rec["hard_fails"] = hard_fails
	rec["soft_fails"] = soft_fails
	rec["inv40_ok"] = not (40 in hard_fails or 40 in soft_fails)

	# ── 逐 good 指标（终态 + 各快照）──
	rec["final"] = _measure(S, S.event_log.size(), days,
		S._stock_day, S.prod_stats.get("attempts", {}), S.prod_stats.get("work", {}),
		S.prod_stats.get("short", {}), S.prod_stats.get("spoiled", {}), S.town_stock)
	var cps: Dictionary = {}
	for d in snaps:
		var sn: Dictionary = snaps[d]
		cps[str(d)] = _measure(S, int(sn["ev_n"]), int(d),
			sn["stock_day"], sn["attempts"], sn["work"], sn["short"], sn["spoiled"], sn["stock"])
	rec["checkpoints"] = cps
	# 谁在干活：逐职位在班完成次数（G3 说"一个泥瓦匠对 60 个睡觉的人" —— 这一行是那句话的分子）
	rec["work_by_title"] = (S.prod_stats.get("work", {}) as Dictionary).duplicate(true)
	rec["attempts_by_action"] = (S.prod_stats.get("attempts", {}) as Dictionary).duplicate(true)

	# 探针自算 vs 门的判决：算出"按 SUPPLY_FLOOR 该不该红"，与 inv40_ok 对照
	var should_red := false
	for g in (rec["final"]["goods"] as Dictionary):
		var gg: Dictionary = (rec["final"]["goods"] as Dictionary)[g]
		if bool(gg.get("gated", false)) and float(gg["rate"]) < Inv.SUPPLY_FLOOR:
			should_red = true
	rec["probe_says_red"] = should_red
	if should_red == rec["inv40_ok"]:
		# 只有在 #40 因【断链】而红、而满足率全部达标时才允许不一致 —— 打出来让人判
		print("  ⚠ MISMATCH seed=%d：探针算得 red=%s，而 #40 ok=%s（detail=%s）" % [
			seed, str(should_red), str(rec["inv40_ok"]), String(rec.get("inv40_detail", "-"))])

	_dispose(S)
	return rec

## 逐 good 指标。**分子/分母的算法逐字对齐 Invariants.gd #40**（见文件头口径纪律）。
## ev_n = 只统计 event_log 的前 ev_n 条（中途快照用）；days_run = 该快照对应的天数。
func _measure(S, ev_n: int, days_run: int, stock_day, attempts, work, short_c, spoiled, stock) -> Dictionary:
	var out: Dictionary = {"days_run": days_run, "goods": {}}
	if S.production.is_empty():
		return out
	var tpd: int = maxi(1, int(S.TICKS_PER_DAY))
	var per_p: Dictionary = {}
	var per_c: Dictionary = {}
	var sh_day: Dictionary = {}
	var producible: Dictionary = {}
	var demanded: Dictionary = {}
	var demand: Dictionary = {}
	for g in S.production.get("goods", {}):
		var gid0 := String(g)
		per_p[gid0] = 0; per_c[gid0] = 0; sh_day[gid0] = {}
		producible[gid0] = false; demanded[gid0] = false; demand[gid0] = 0
	for title in S.production.get("produce", {}):
		var prec: Dictionary = (S.production["produce"] as Dictionary)[String(title)]
		if producible.has(String(prec.get("good", ""))):
			producible[String(prec.get("good", ""))] = true
		var pins = prec.get("inputs", {})
		if pins is Dictionary:
			var nw := int((work as Dictionary).get(String(title), 0))
			for ing in (pins as Dictionary):
				var ig := String(ing)
				if demanded.has(ig):
					demanded[ig] = true
					demand[ig] = int(demand[ig]) + nw * int((pins as Dictionary)[ing])
	for act in S.production.get("consume", {}):
		var crec: Dictionary = (S.production["consume"] as Dictionary)[String(act)]
		var cg := String(crec.get("good", ""))
		if demanded.has(cg):
			demanded[cg] = true
			demand[cg] = int(demand[cg]) \
				+ int((attempts as Dictionary).get(String(act), 0)) * int(crec.get("amount", 1))
	var log: Array = S.event_log
	var n_prod := 0
	var n_cons := 0
	for i in range(mini(ev_n, log.size())):
		var e: Dictionary = log[i]
		var ty := String(e["type"])
		var g2 := String(e["subject"])
		if ty == "produce":
			n_prod += 1
			if per_p.has(g2): per_p[g2] = int(per_p[g2]) + Inv._amt_of(String(e.get("note", "")))
		elif ty == "consume":
			n_cons += 1
			if per_c.has(g2): per_c[g2] = int(per_c[g2]) + Inv._amt_of(String(e.get("note", "")))
		elif ty == "shortage":
			if sh_day.has(g2): (sh_day[g2] as Dictionary)[int(int(e.get("tick", 0)) / tpd)] = true
	for g0 in per_c.keys():
		per_c[g0] = int(per_c[g0]) + int((stock_day as Dictionary).get(String(g0), 0))
	out["n_produce_events"] = n_prod
	out["n_consume_events"] = n_cons
	for g in per_p:
		var gid := String(g)
		var dm := int(demand[gid])
		var gated: bool = bool(demanded[gid]) and int(per_c[gid]) > 0 \
			and dm >= Inv.SUPPLY_MIN_DEMAND and days_run >= Inv.SUPPLY_MIN_DAYS
		(out["goods"] as Dictionary)[gid] = {
			"produced": int(per_p[gid]),
			"served": int(per_c[gid]),
			"demand": dm,
			"rate": (float(per_c[gid]) / float(dm)) if dm > 0 else -1.0,
			"shortage_days": (sh_day[gid] as Dictionary).size(),
			"shortage_events": int((short_c as Dictionary).get(gid, 0)),
			"spoiled": int((spoiled as Dictionary).get(gid, 0)),
			"stock_end": int((stock as Dictionary).get(gid, 0)),
			"producible": bool(producible[gid]),
			"demanded": bool(demanded[gid]),
			"gated": gated,   # 这一格【真的进了 #40 的判决】还是被 MIN_DEMAND/MIN_DAYS 豁免掉了
		}
	return out

func _dispose(S) -> void:
	get_root().remove_child(S)
	S.free()

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
