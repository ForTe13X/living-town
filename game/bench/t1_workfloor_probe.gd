extends SceneTree
## bench/t1_workfloor_probe.gd — T1（docs/75 §一）：**只量，不修**。
##
## 回答的问题：**一个岗位持有人 60 天只上工 1-2 次的时候，那些机会去哪儿了？**
## docs/72 §1.5 量到「左尾由【单个岗位的在班完成次数】驱动」，但它没有拆开
## 「机会没出现」/「机会出现了但输了」/「赢了但不在班（白干）」这三件事——
## 而这三件的修法完全不同，所以先把它们分开数。
##
## 口径纪律（docs/41 §5）：
##   · 走既有只读钩子 `Sim.decision_sink`（Sim.gd:3608，只在 cands.size()>=2 时触发、不抽 RNG、不进 digest）。
##     `--selfcheck` 跑同 seed 的挂钩/不挂钩两遍，比 digest —— 探针必须逐字节不扰动。
##   · 逐 seed 输出，**不做平均**。
##   · 同时数【被枚举到】【被选中】【在不在班】三个量。
##
## 用法：
##   godot --headless --path game -s res://bench/t1_workfloor_probe.gd -- \
##       --agents 12 --seeds 18,36,40,50,58 --days 60 [--selfcheck] [--out x.jsonl]

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

var _S = null
var _stat: Dictionary = {}        # title -> 统计桶
var _title_of_id: Dictionary = {} # agent id -> title
var _act_of_id: Dictionary = {}   # agent id -> 本职动作

func _init() -> void:
	var seeds := _parse_seeds("18,36,40,50,58")
	var days := 60
	var agents := 0
	var selfcheck := false
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
		elif args[i] == "--selfcheck":
			selfcheck = true
	var f: FileAccess = null
	if out_path != "":
		f = FileAccess.open(out_path, FileAccess.WRITE)
	print("=== t1_workfloor_probe · agents=%d seeds=%s days=%d selfcheck=%s ===" % [
		agents, str(seeds), days, str(selfcheck)])
	for sd in seeds:
		var rec := _run_once(sd, days, agents, true)
		if selfcheck:
			var bare := _run_once(sd, days, agents, false)
			rec["digest_no_probe"] = bare["digest"]
			rec["probe_nonperturbing"] = (String(rec["digest"]) == String(bare["digest"]))
		var line := JSON.stringify(rec)
		print("[T1WF] " + line)
		if f: f.store_line(line)
	if f: f.close()
	quit(0)

func _run_once(seed: int, days: int, agents: int, hook: bool) -> Dictionary:
	_stat = {}
	_title_of_id = {}
	_act_of_id = {}
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	if agents > 0:
		S.spawn_count = agents
	_S = S
	if hook:
		S.decision_sink = Callable(self, "_on_decision")
	S.start_new(seed)
	# 岗位表（start_new 之后才合并 production.jobs）
	for ag in S.agents:
		var jb: Dictionary = S._job_of(String(ag["id"]))
		if jb.is_empty():
			continue
		var t := String(jb.get("title", ""))
		_title_of_id[String(ag["id"])] = t
		_act_of_id[String(ag["id"])] = String(S._job_action(jb))
		_stat[t] = {
			"holder": String(ag["id"]), "action": String(S._job_action(jb)),
			"shift": jb.get("shift", []), "home_space": String(ag.get("home_space", "town")),
			# 决策点（sink 触发的那些）
			"dp": 0, "dp_inshift": 0,
			# 本职广告在候选表里出现
			"offer": 0, "offer_inshift": 0,
			# 本职广告被选中
			"win": 0, "win_inshift": 0,
			# 在班的决策点里，本职广告【没出现】的次数
			"noshow_inshift": 0,
			"noshow_inshift_funfull": 0,      # 其中 fun>=95（urgency<=5 被 continue 掉）
			"noshow_inshift_offplane": 0,     # 其中 agent 不在工位那个平面
			"noshow_inshift_homebind": 0,     # 其中 家绑定把 fun 整个摘掉了
			# 在班输掉时的差距（own_score - winner_score，负数）
			"loss_margin_sum_x1000": 0, "loss_inshift": 0,
			"loss_lt_0p5": 0,                 # 差距 < 0.5 ⇒ 平局抖动本来就能翻盘
			"loss_lt_2": 0, "loss_lt_5": 0, "loss_ge_5": 0,
			"lost_to": {},                    # 在班输给谁（action -> 次数）
			"own_score_sum_x1000": 0, "win_score_sum_x1000": 0,
			# 每 tick 采样
			"tick_inshift": 0, "tick_inshift_idle": 0,
			"floor_inshift": {},              # 在班时人在哪个平面
			"stock_when_inshift_sum": 0,      # 在班时自己那种货的库存和（除以 tick_inshift = 均值）
			"stock_when_inshift_zero": 0,     # 在班且自己那种货见底的 tick 数
			# ★本探针的核心那一格：**决策时镇库有多少** × 【本职广告赢没赢】。
			#   开环的判据就在这里：若 p(赢) 在三档库存上没有差别，产出侧对短缺就是【没有反馈】的。
			#   分档按 stock/cap：empty = 0 件；low = (0, cap/4]；mid = (cap/4, 3cap/4]；high = >3cap/4
			"off_empty": 0, "win_empty": 0,
			"off_low": 0, "win_low": 0,
			"off_mid": 0, "win_mid": 0,
			"off_high": 0, "win_high": 0,
		}
	var tpd := int(S.TICKS_PER_DAY)
	for _t in range(days * tpd):
		S.tick()
		if not hook:
			continue
		for ag in S.agents:
			var aid := String(ag["id"])
			if not _title_of_id.has(aid):
				continue
			var t2: String = _title_of_id[aid]
			var jb2: Dictionary = S._job_of(aid)
			if not S._in_shift(jb2):
				continue
			var b: Dictionary = _stat[t2]
			b["tick_inshift"] = int(b["tick_inshift"]) + 1
			if ag.get("option") == null:
				b["tick_inshift_idle"] = int(b["tick_inshift_idle"]) + 1
			var pl := "%s/%s" % [String(ag.get("space", "town")), String(ag.get("floor", "outdoor"))]
			(b["floor_inshift"] as Dictionary)[pl] = int((b["floor_inshift"] as Dictionary).get(pl, 0)) + 1
			var good := _first_prod_good(S.production, t2)  # ★E4d-A 双形状：多货取首件（见 _first_prod_good）
			if good != "":
				var st := int(S._stock_of(good))
				b["stock_when_inshift_sum"] = int(b["stock_when_inshift_sum"]) + st
				if st <= 0:
					b["stock_when_inshift_zero"] = int(b["stock_when_inshift_zero"]) + 1
	var rec: Dictionary = {
		"seed": seed, "n_agents": S.agents.size(), "days": days,
		"digest": str(Inv.digest(S)),
		"work_by_title": (S.prod_stats.get("work", {}) as Dictionary).duplicate(true),
		"stock_final": S.town_stock.duplicate(true),
	}
	if hook:
		rec["jobs"] = _stat.duplicate(true)
	get_root().remove_child(S)
	S.free()
	_S = null
	return rec

## 只读钩子：cands 是本次决策的完整候选表，best_i 是被选中的那一条。
func _on_decision(ag: Dictionary, cands: Array, best_i: int) -> void:
	var aid := String(ag["id"])
	if not _title_of_id.has(aid):
		return
	var t: String = _title_of_id[aid]
	var my_act: String = _act_of_id[aid]
	var b: Dictionary = _stat[t]
	var jb: Dictionary = _S._job_of(aid)
	var ins: bool = _S._in_shift(jb)
	b["dp"] = int(b["dp"]) + 1
	if ins:
		b["dp_inshift"] = int(b["dp_inshift"]) + 1
	var own_i := -1
	var own_s := 0.0
	for i in cands.size():
		var c = cands[i]
		if not (c is Dictionary):
			continue
		if String((c as Dictionary).get("kind", "")) != "object":
			continue
		if String((c as Dictionary).get("action", "")) != my_act:
			continue
		# 本职动作可能有多个落点（看摊：town 的 counter_1 与 cafe/1f 的吧台）——取分最高的那条
		var s := float((c as Dictionary).get("score", -1e9))
		if own_i < 0 or s > own_s:
			own_i = i
			own_s = s
	if own_i < 0:
		if ins:
			b["noshow_inshift"] = int(b["noshow_inshift"]) + 1
			if float((ag["needs"] as Dictionary).get("fun", 100.0)) >= 95.0:
				b["noshow_inshift_funfull"] = int(b["noshow_inshift_funfull"]) + 1
			# ⚠ 必须把 need 成员资格一起查：出货 agents.json 的 home_needs 是 ["energy"]，
			#   **fun 不在里面** ⇒ 家绑定这一条对所有工位广告（全是 need=fun）结构上不触发。
			#   探针第一版漏了这一半，于是把"evy 在 town 而 home_space=home"误报成家绑定 7/7。
			var hs := String(ag.get("home_space", "town"))
			if "fun" in _S._home_needs(ag) and hs != "town" and String(ag.get("space", "town")) != hs:
				b["noshow_inshift_homebind"] = int(b["noshow_inshift_homebind"]) + 1
			if String(ag.get("space", "town")) != "town" or String(ag.get("floor", "outdoor")) != "outdoor":
				b["noshow_inshift_offplane"] = int(b["noshow_inshift_offplane"]) + 1
		return
	b["offer"] = int(b["offer"]) + 1
	if ins:
		b["offer_inshift"] = int(b["offer_inshift"]) + 1
		# 库存分档（只在在班的 offer 上数——不在班干活一件货都不产，那些不该进这张表）
		var good2 := _first_prod_good(_S.production, t)  # ★E4d-A 双形状：多货取首件（见 _first_prod_good）
		if good2 != "":
			var cap2 := int((_S.production.get("goods", {}) as Dictionary).get(good2, {}).get("cap", 0))
			var st2 := int(_S._stock_of(good2))
			var suf := "high"
			if st2 <= 0:
				suf = "empty"
			elif cap2 > 0 and st2 * 4 <= cap2:
				suf = "low"
			elif cap2 > 0 and st2 * 4 <= cap2 * 3:
				suf = "mid"
			b["off_" + suf] = int(b["off_" + suf]) + 1
			if own_i == best_i:
				b["win_" + suf] = int(b["win_" + suf]) + 1
	if own_i == best_i:
		b["win"] = int(b["win"]) + 1
		if ins:
			b["win_inshift"] = int(b["win_inshift"]) + 1
		return
	if not ins:
		return
	var w = cands[best_i]
	var w_s := float((w as Dictionary).get("score", 0.0))
	var m := own_s - w_s
	b["loss_inshift"] = int(b["loss_inshift"]) + 1
	b["loss_margin_sum_x1000"] = int(b["loss_margin_sum_x1000"]) + int(m * 1000.0)
	b["own_score_sum_x1000"] = int(b["own_score_sum_x1000"]) + int(own_s * 1000.0)
	b["win_score_sum_x1000"] = int(b["win_score_sum_x1000"]) + int(w_s * 1000.0)
	var am := -m
	if am < 0.5:
		b["loss_lt_0p5"] = int(b["loss_lt_0p5"]) + 1
	elif am < 2.0:
		b["loss_lt_2"] = int(b["loss_lt_2"]) + 1
	elif am < 5.0:
		b["loss_lt_5"] = int(b["loss_lt_5"]) + 1
	else:
		b["loss_ge_5"] = int(b["loss_ge_5"]) + 1
	var wk := "%s:%s" % [String((w as Dictionary).get("kind", "")), String((w as Dictionary).get("action", ""))]
	(b["lost_to"] as Dictionary)[wk] = int((b["lost_to"] as Dictionary).get(wk, 0)) + 1

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

## ★E4d-A 双形状：produce[title] 可为多货 Array of {good,amount,inputs?} 或单货 dict。
##   本探针的库存分档只看【首件货】（列表著者序第一件非空记录，与 Sim._stock_pull_mult 的首件锁一致）。
##   单货 dict → 直接读 good；缺产者/空 → ""。仅供探针显示/分档，不进金标路/CI 自动执行。
func _first_prod_good(prod, title: String) -> String:
	var praw = (prod.get("produce", {}) as Dictionary).get(title, {})
	var recs: Array = praw if praw is Array else [praw]
	for pr in recs:
		if pr is Dictionary and not (pr as Dictionary).is_empty():
			return String((pr as Dictionary).get("good", ""))
	return ""
