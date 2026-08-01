extends SceneTree
## bench/w1_pact_clock.gd — W1（docs/88）第三把尺子：**盟约是什么时候成立的。**
##
## `w1_aid_funnel.gd` 量出漏斗第①级（盟约 tick 和 = Σ_tick 活跃盟约条数）在**每一条**扰动臂上都比基线低。
## "每一条都低"要么是机制，要么是我在读噪声。区别在于**盟约成立时刻的分布**：
##   · 若基线的成立时刻贴着一条**下界**（三道门 trust≥12 / fam≥6 / complementSeen≥3 的暖机时间），
##     那么扰动**只能推迟不能提前** ⇒ 积分被单边截断 ⇒ 每条扰动臂都低是**结构**。
##   · 若成立时刻散在中段，那"每条都低"就需要别的解释。
##
## 纯后验读 `Sim.pacts_index`（它自带 `formed` / `status` / `brokenTick`），**连 decision_sink 都不需要**。
##
## 用法：godot --headless --path game -s res://bench/w1_pact_clock.gd -- \
##          --agents 12 --seeds 1-12 --days 60 --craft on|off [--standing X] [--util k=v]

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

func _init() -> void:
	var seeds := _parse_seeds("1-12")
	var days := 60
	var agents := 0
	var craft := "on"
	var st_over := ""
	var util_over := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])
		elif args[i] == "--agents" and i + 1 < args.size():
			agents = int(args[i + 1])
		elif args[i] == "--craft" and i + 1 < args.size():
			craft = String(args[i + 1])
		elif args[i] == "--standing" and i + 1 < args.size():
			st_over = String(args[i + 1])
		elif args[i] == "--util" and i + 1 < args.size():
			util_over = String(args[i + 1])
	print("=== w1_pact_clock · agents=%d seeds=%s days=%d craft=%s standing=%s util=%s ===" % [agents, str(seeds), days, craft, st_over, util_over])
	for sd in seeds:
		print("[W1CLOCK] " + JSON.stringify(_run_once(sd, days, agents, craft, st_over, util_over)))
	quit(0)

func _run_once(seed: int, days: int, agents: int, craft: String, st_over: String, util_over: String) -> Dictionary:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	if craft == "off":
		S.production.erase("craft_credit")
		S._production_raw.erase("craft_credit")
	if util_over != "":
		var kv := util_over.split("=")
		S.utility[String(kv[0])] = float(kv[1])
	S.auto_run = false
	S.backend = null
	if agents > 0:
		S.spawn_count = agents
	S.start_new(seed)
	if st_over != "" and craft != "off":
		var tbl = S.production.get("craft_credit", {})
		if tbl is Dictionary:
			for t in tbl:
				(tbl[t] as Dictionary)["standing"] = float(st_over)
	var tpd := int(S.TICKS_PER_DAY)
	var total := days * tpd
	for _t in range(total):
		S.tick()
	var formed_days: Array = []
	var lifetimes: Array = []
	var alive := 0
	for p in S.pacts_index:
		var f := int(p["formed"])
		if f <= 0:
			continue                       # 场景预置的盟约（_seed_scenario），不是本局长出来的
		formed_days.append(int(f / tpd))
		var endt := int(p.get("brokenTick", total)) if String(p["status"]) != "active" else total
		lifetimes.append(int((endt - f) / tpd))
		if String(p["status"]) == "active":
			alive += 1
	formed_days.sort()
	var rec: Dictionary = {
		"seed": seed, "craft": craft, "standing": st_over, "util": util_over,
		"digest": str(Inv.digest(S)),
		"n_pacts": formed_days.size(), "alive_end": alive,
		"formed_days": formed_days, "lifetimes_days": lifetimes,
		"first_formed_day": (formed_days[0] if not formed_days.is_empty() else -1),
		"pactdays_sum": _sum(lifetimes),
	}
	get_root().remove_child(S)
	S.free()
	return rec

func _sum(a: Array) -> int:
	var s := 0
	for v in a:
		s += int(v)
	return s

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
