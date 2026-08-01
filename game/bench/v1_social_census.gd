extends SceneTree
## bench/v1_social_census.gd — V1（docs/83 §一 的"先量"那一步）：**九个岗位各自的【社会产出】是多少？**
##
## 回答的问题（派单原文）：一个岗位的工作有没有产生任何 `event_log` 事件被别人**看见**、
## 被 `gossip`/`gossip_rep` 转述、进入 `attitudes`/`affinity`/`familiarity`、或改变任何人的 `belief`？
##
## ★归因规则（**跑之前就写死在这里**，避免事后挑口径）：
##   一次社会状态变化算在岗位 J 头上，当且仅当产生它的那条代码路径**由 J 的职位/产物门控**。
##   在 event_log 与终态里，这一条落成三类可数的东西：
##     ① `produce` 事件（actor = J 的现任持有人）——`_stock_move` 写的，`witnesses` 恒 []；
##     ② `shortage` 事件（target = J 的持有人，即 goods[good].blame 指向他）——`_shortage_fallout` 写的，
##        带 witnesses，并派生 `SH:<good>` belief + `_adjust_standing`；
##     ③ `pay` 事件 reason=`wage:<J 的动作>`——`transfer` 写的，`witnesses` 恒 []。
##   其余社交事件（greet/gossip/…）**与岗位无关**，不算 J 的产出（它们是"这个人"的社交，不是"这门手艺"的）。
##
## ★同时量一条【反事实上界】：产出的那一刻，身边真的有人吗？
##   每 tick 结束后扫这一 tick 新增的 produce 事件，对持有人当场调 `_nearby_agents` 数在场人数。
##   ⚠ 近似的边界写在这里：`_advance_object` 的 use 分支**不移动 agent**，所以持有人自己的位置
##   与产出那一刻逐格相同；但同一 tick 里**排在他后面**的居民可能已经走了一格。
##   ⇒ 这个数是"当时在场人数"的一个**同量级估计**，不是逐格精确值。它的用途是分辨
##   "通道空着是因为没人在旁边" 与 "有人在旁边而代码把 witnesses 写成了 []"——这两件事差得很远。
##
## 口径纪律（docs/41 §5）：逐 seed 输出，**探针内不做任何平均**。
## ⚠ 本文件只读 Sim，不写任何仿真状态。`digest` 一并输出用于自证不扰动。
##
## 用法：
##   godot --headless --path game -s res://bench/v1_social_census.gd -- \
##       --agents 12 --seeds 1-5 --days 60 [--out x.jsonl]

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

func _init() -> void:
	var seeds := _parse_seeds("1-5")
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
	print("=== v1_social_census · agents=%d seeds=%s days=%d ===" % [agents, str(seeds), days])
	for sd in seeds:
		var rec := _run_once(sd, days, agents)
		var line := JSON.stringify(rec)
		print("[V1CENSUS] " + line)
		if f: f.store_line(line)
	if f: f.close()
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

	# ── 岗位表（start_new 之后才合并 production.jobs）──────────────────────────
	var title_of: Dictionary = {}      # holder id -> title
	var holder_of: Dictionary = {}     # title -> holder id
	var act_of: Dictionary = {}        # title -> 本职动作
	for ag in S.agents:
		var jb: Dictionary = S._job_of(String(ag["id"]))
		if jb.is_empty():
			continue
		var t := String(jb.get("title", ""))
		title_of[String(ag["id"])] = t
		holder_of[t] = String(ag["id"])
		act_of[t] = String(S._job_action(jb))
	# blame 反查：title -> [它被指责的货]
	var blamed_goods: Dictionary = {}
	for g in S.production.get("goods", {}):
		var bl := String((S.production["goods"] as Dictionary)[g].get("blame", ""))
		if bl == "":
			continue
		if not blamed_goods.has(bl):
			blamed_goods[bl] = []
		(blamed_goods[bl] as Array).append(String(g))

	# ── 跑，并在每 tick 之后扫新增的 produce 事件，记录当场在场人数 ─────────────
	var seen_ev := 0
	var bystanders: Dictionary = {}    # title -> {"n":产出次数, "sum":在场人数和, "zero":在场0人的次数, "max":最大}
	var tpd := int(S.TICKS_PER_DAY)
	for _t in range(days * tpd):
		S.tick()
		while seen_ev < S.event_log.size():
			var ev: Dictionary = S.event_log[seen_ev]
			seen_ev += 1
			if String(ev.get("type", "")) != "produce":
				continue
			var aid := String(ev.get("actor", ""))
			if not title_of.has(aid):
				continue
			var t2: String = title_of[aid]
			if not bystanders.has(t2):
				bystanders[t2] = {"n": 0, "sum": 0, "zero": 0, "max": 0}
			var b: Dictionary = bystanders[t2]
			var near: int = S._nearby_agents(S._agent_by_id[aid]).size()
			b["n"] = int(b["n"]) + 1
			b["sum"] = int(b["sum"]) + near
			if near == 0:
				b["zero"] = int(b["zero"]) + 1
			if near > int(b["max"]):
				b["max"] = near

	# ── 终态扫描：event_log 的岗位相关事件 + 每人的 belief / standing ────────────
	var per: Dictionary = {}
	for t in holder_of:
		per[t] = {
			"holder": String(holder_of[t]),
			"action": String(act_of.get(t, "")),
			"produces": String((S.production.get("produce", {}) as Dictionary).get(t, {}).get("good", "")),
			"blame_for": blamed_goods.get(t, []),
			"work_done": int((S.prod_stats.get("work", {}) as Dictionary).get(t, 0)),
			# ① produce 通道
			"ev_produce": 0, "ev_produce_witnessed": 0, "ev_produce_witness_slots": 0,
			# ③ 工资通道
			"ev_wage": 0, "ev_wage_witnessed": 0,
			# ② 被指责通道（shortage 事件里 target=他）
			"ev_blamed": 0, "ev_blamed_witnessed": 0, "ev_blamed_witness_slots": 0,
			# 他自己作为缺货【当事人】写出来的（这是"他消费时缺货"，不是他的手艺的产出）
			"ev_short_as_victim": 0,
			# belief：全镇有多少人持有以他为 subject 的信念，按键前缀分
			"belief_SH_holders": 0, "belief_W_holders": 0, "belief_other_holders": 0,
			"belief_CR_holders": 0, "belief_SH_via": {}, "belief_CR_via": {},
			# gossip 通道：转述了 SH:*/CR:* 信念、且该信念主语是他
			"gossip_of_SH": 0, "gossip_of_CR": 0,
			# standing：全镇对他的 standing 非零人数与和（×1000 取整，避免浮点串）
			"standing_nonzero": 0, "standing_sum_x1000": 0,
			# ★行为侧的落点：`_acceptance_rule` 读的是 `_rel(target, actor)["standing"]`
			#   ⇒ 别人对他的 standing 抬高，直接抬高**他发起的**社交被接受的概率。
			#   这一格就是"不只是多打一行日志"的判据：它是行为，不是账本。
			"soc_proposed": 0, "soc_accepted": 0,
			# 在场人数（上面 per-tick 扫出来的）
			"produce_bystanders": bystanders.get(t, {"n": 0, "sum": 0, "zero": 0, "max": 0}),
		}
	# belief cid -> subject（用于 gossip 归因；全镇任一持有者即可给出 subject）
	var cid_subject: Dictionary = {}
	for ag in S.agents:
		for cid in ag["beliefs"]:
			if not cid_subject.has(cid):
				cid_subject[cid] = String((ag["beliefs"][cid] as Dictionary).get("subject", ""))

	# 社交提议的事件类型：走 Sim 自己那张表，不在探针里另抄一份（抄的那份会过期）
	var SOC: Array = S.KNOWN_SOCIAL_ACTIONS
	for ev in S.event_log:
		var ty := String(ev.get("type", ""))
		var actor := String(ev.get("actor", ""))
		var target := String(ev.get("target", ""))
		var wn: int = (ev.get("witnesses", []) as Array).size()
		if ty in SOC and title_of.has(actor):
			var pa: Dictionary = per[title_of[actor]]
			pa["soc_proposed"] = int(pa["soc_proposed"]) + 1
			if bool(ev.get("accepted", false)):
				pa["soc_accepted"] = int(pa["soc_accepted"]) + 1
		if ty == "produce" and title_of.has(actor):
			var p1: Dictionary = per[title_of[actor]]
			p1["ev_produce"] = int(p1["ev_produce"]) + 1
			if wn > 0:
				p1["ev_produce_witnessed"] = int(p1["ev_produce_witnessed"]) + 1
			p1["ev_produce_witness_slots"] = int(p1["ev_produce_witness_slots"]) + wn
		elif ty == "pay" and title_of.has(target) and String(ev.get("note", "")).begins_with("wage:"):
			var act := String(ev.get("note", "")).substr(5)
			if act == String(act_of.get(title_of[target], "")):
				var p2: Dictionary = per[title_of[target]]
				p2["ev_wage"] = int(p2["ev_wage"]) + 1
				if wn > 0:
					p2["ev_wage_witnessed"] = int(p2["ev_wage_witnessed"]) + 1
		elif ty == "shortage":
			if title_of.has(target):
				var p3: Dictionary = per[title_of[target]]
				p3["ev_blamed"] = int(p3["ev_blamed"]) + 1
				if wn > 0:
					p3["ev_blamed_witnessed"] = int(p3["ev_blamed_witnessed"]) + 1
				p3["ev_blamed_witness_slots"] = int(p3["ev_blamed_witness_slots"]) + wn
			if title_of.has(actor):
				var p4: Dictionary = per[title_of[actor]]
				p4["ev_short_as_victim"] = int(p4["ev_short_as_victim"]) + 1
		elif ty == "gossip" or ty == "gossip_rep":
			var subj := String(ev.get("subject", ""))
			if subj == "":
				continue
			var about := String(cid_subject.get(subj, ""))
			if not title_of.has(about):
				continue
			var p5: Dictionary = per[title_of[about]]
			if subj.begins_with("SH:"):
				p5["gossip_of_SH"] = int(p5["gossip_of_SH"]) + 1
			elif subj.begins_with("CR:"):
				p5["gossip_of_CR"] = int(p5["gossip_of_CR"]) + 1

	for ag in S.agents:
		for cid in ag["beliefs"]:
			var b2: Dictionary = ag["beliefs"][cid]
			var subj2 := String(b2.get("subject", ""))
			if not title_of.has(subj2):
				continue
			var pb: Dictionary = per[title_of[subj2]]
			var cs := String(cid)
			if cs.begins_with("CR:"):
				pb["belief_CR_holders"] = int(pb["belief_CR_holders"]) + 1
				var via_c := String(b2.get("via", ""))
				(pb["belief_CR_via"] as Dictionary)[via_c] = int((pb["belief_CR_via"] as Dictionary).get(via_c, 0)) + 1
			elif cs.begins_with("SH:"):
				pb["belief_SH_holders"] = int(pb["belief_SH_holders"]) + 1
				var via := String(b2.get("via", ""))
				(pb["belief_SH_via"] as Dictionary)[via] = int((pb["belief_SH_via"] as Dictionary).get(via, 0)) + 1
			elif cs.begins_with("W:"):
				pb["belief_W_holders"] = int(pb["belief_W_holders"]) + 1
			else:
				pb["belief_other_holders"] = int(pb["belief_other_holders"]) + 1
		for oid in ag["relationships"]:
			if not title_of.has(String(oid)):
				continue
			var st := float((ag["relationships"][oid] as Dictionary).get("standing", 0.0))
			if absf(st) < 0.0005:
				continue
			var ps: Dictionary = per[title_of[String(oid)]]
			ps["standing_nonzero"] = int(ps["standing_nonzero"]) + 1
			ps["standing_sum_x1000"] = int(ps["standing_sum_x1000"]) + int(round(st * 1000.0))

	# 全局分母：整条 event_log 的事件类型分布 + 带 witnesses 的比例
	var by_type: Dictionary = {}
	for ev2 in S.event_log:
		var t3 := String(ev2.get("type", ""))
		if not by_type.has(t3):
			by_type[t3] = {"n": 0, "witnessed": 0}
		var e3: Dictionary = by_type[t3]
		e3["n"] = int(e3["n"]) + 1
		if (ev2.get("witnesses", []) as Array).size() > 0:
			e3["witnessed"] = int(e3["witnessed"]) + 1

	# ── 全镇社会状态（负对照要比的就是这一段）+ **不得静默回归的那四条通道** ─────────
	# ★为什么把 #5/#16/#20/#15 的原料直接算在这里：派单点名它们"不得静默回归"，而"静默"的意思正是
	#   **判据仍然绿、可是它守的那件事已经不发生了**（docs/41 §2 第三个盲区）。所以要报的不是 PASS/FAIL，
	#   是它们各自那个**分支还在不在**：坏名声还存不存在、gossip_rep 还发不发、谣言还冷不冷、R1 还传不传。
	var st_pos := 0; var st_neg := 0; var st_zero_skip := 0
	var st_min := 0.0; var st_max := 0.0
	var fam_pairs := 0; var fam_sum := 0.0
	var bad_rep_exists := false
	var belief_prefix: Dictionary = {}
	var r1_knowers := 0; var stifled_total := 0
	for ag in S.agents:
		for oid in ag["relationships"]:
			var r: Dictionary = ag["relationships"][oid]
			var stv := float(r.get("standing", 0.0))
			if stv > 0.0005: st_pos += 1
			elif stv < -0.0005: st_neg += 1
			else: st_zero_skip += 1
			st_min = minf(st_min, stv); st_max = maxf(st_max, stv)
			if stv <= float(S.REP_GOSSIP_TH):
				bad_rep_exists = true
			var fv := float(r.get("familiarity", 0.0))
			if fv > 0.0:
				fam_pairs += 1; fam_sum += fv
		for cid in ag["beliefs"]:
			var cs2 := String(cid)
			var pre := cs2.split(":")[0] if ":" in cs2 else cs2
			belief_prefix[pre] = int(belief_prefix.get(pre, 0)) + 1
		if ag["beliefs"].has("R1"):
			r1_knowers += 1
		stifled_total += (ag["stifled"] as Dictionary).size()
	var fac_sizes: Dictionary = {}
	for fid in S.factions:
		fac_sizes[String(fid)] = (S.factions[fid] as Array).size()

	var rec: Dictionary = {
		"seed": seed, "n_agents": S.agents.size(), "days": days,
		"digest": str(Inv.digest(S)),
		"events_total": S.event_log.size(),
		"by_type": by_type,
		"jobs": per,
		"town": {
			"standing_pos_pairs": st_pos, "standing_neg_pairs": st_neg, "standing_zero_pairs": st_zero_skip,
			"standing_min_x1000": int(round(st_min * 1000.0)), "standing_max_x1000": int(round(st_max * 1000.0)),
			"fam_pairs": fam_pairs, "fam_sum_x100": int(round(fam_sum * 100.0)),
			"belief_by_prefix": belief_prefix,
			"faction_sizes": fac_sizes,
			# ↓ 四条"不得静默回归"的原料
			"inv5_R1_knowers": r1_knowers,                     # #5 谣言传播：应 ≥2
			"inv16_bad_rep_exists": bad_rep_exists,            # #16 的前件
			"inv16_gossip_rep_events": int(by_type.get("gossip_rep", {}).get("n", 0)),
			"inv20_stifled": stifled_total,                    # #20 谣言变冷：应 >0
			"st_neg_events": int(S.st_neg_events),             # #17/#23 的原料
			"confide": int(S.confide_events), "betray": int(S.betray_events),
			"endorse": int(S.endorse_events), "aid_accepted": int(S.aid_accepted),
			"refused_by_bound": int(S.refused_by_bound),
		},
	}
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
