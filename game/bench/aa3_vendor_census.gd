extends SceneTree
## bench/aa3_vendor_census.gd — AA3（docs/103 §三 的"先量"那一步）：**消费侧的"被看见"到底是什么？**
##
## V1/Z2 量的是 `produce` 那一侧：「产出那一刻工位旁有谁」（`game/bench/v1_social_census.gd`，本文件的祖本）。
## 商贩 mei 在那张表上是一行空白——**不是因为他没干活**（他有岗位/班次/两条广告位、实测拿走全镇约 14% 的饭口），
## 而是因为 `craft_credit` 挂在 `produce` 管线上，**而他的产出在消费侧**（`赶集` = 全镇唯一一条人→人的货钱通道）。
##
## ★归因规则（**跑之前就写死在这里**，避免事后挑口径 —— 同 v1_social_census 的纪律）：
##   一次「赶集」的落点在 `Sim._advance_object` 的 travel→use 交界（`_manh(买家, 摊位) <= 1` 的那一 tick）：
##     ① `_consume_for("赶集")` 扣一件口粮（**不写逐笔事件**——消耗按天汇总，见 `_stock_nightly`）；
##     ② `transfer(买家, 商贩, price)` 写一条 `pay` 事件，note = `buy:赶集`；
##        买家恰好是商贩本人 / 镇上没有商贩 ⇒ payee="town"、note = `price:赶集`；
##        **买家付不起 ⇒ `transfer` 返回 false ⇒ 一条事件都不写**（meals_free，与 #01 同一条红线）。
##   ⇒ **`pay` 事件是逐笔的，但它漏掉 meals_free 那一档。** 所以本探针**不以事件为准**，
##      以 `option` 的相位翻转为准（下面 ★量具校准），并把两者的差额逐 seed 报出来。
##
## ★量具（**逐笔精确，不是估计**）：每 tick 结束后扫每个 agent 的 `option`：
##   `action=="赶集" and phase=="use" and remaining==dur_total` ⇔ 这一 tick 刚刚成交。
##   为什么它是精确的（两条，都是代码里读出来的、不是推断）：
##     · `_advance_object` 的 travel 分支把 `phase` 置 "use" 之后**当场 return**（if/else 互斥），
##       use 分支要下一 tick 才跑 ⇒ 成交那一 tick 结束时 `remaining` 恰为 `dur_total`，此后逐 tick 递减；
##     · use 分支**不移动 agent** ⇒ 买家在成交那一刻的位置与 tick 末逐格相同（比 v1 的 produce 侧还强一档，
##       因为那一侧只有产者自己精确、旁人可能已经走了一格 —— 这里连"旁人"也只在 tick 末读一次，
##       所以 `bystanders` 这一列与 v1 同为**同量级估计**，而 `vendor_present` 这一列的口径见下）。
##
## ★本探针不替派单挑定义：**它把消费侧"被看见"的四种候选口径同时量出来**，让判定有依据。
##   D1 `buyer`      —— 买家自己就是见证者（成交=他知道这顿饭是谁卖的）。**只在钱真的付给了商贩本人时成立。**
##   D2 `vendor_here`—— 成交那一刻商贩**真的站在场**（同平面同区，走 `_nearby_agents(买家)`）。
##                      ⚠ 这一条是本探针最要紧的一列：`_market_open` 只要求商贩**在班**，
##                      **不要求他在摊位上** ⇒ "无人售货" 在结构上是允许的。
##   D3 `bystander`  —— 成交那一刻旁边还有**第三个人**（买家与商贩之外）。这是 produce 侧口径的直译。
##   D4 `vendor+by`  —— D2 且 D3。
##
## ★余量（**判定用的统计量，照抄 docs/101 Z2 §一.3，不是平均在场人数**）：
##   余量 = 在这一格里，"赶集次数 ≥ 豁免线" 的每个 seed 上，"该口径下有见证者的赶集条数"的【最小值】。
##   汇总在 analysis/aa3/margin.py 里做，本探针只逐 seed 吐原始计数（探针内不做任何平均）。
##
## ⚠ 本文件**只读** Sim，不写任何仿真状态。`digest` 一并输出用于自证不扰动。
##
## 用法：
##   godot --headless --path game -s res://bench/aa3_vendor_census.gd -- \
##       --agents 12 --seeds 1-12 --days 60 [--out x.jsonl]

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
	print("=== aa3_vendor_census · agents=%d seeds=%s days=%d ===" % [agents, str(seeds), days])
	for sd in seeds:
		var rec := _run_once(sd, days, agents)
		print("[AA3CENSUS] " + JSON.stringify(rec))
		if f: f.store_line(JSON.stringify(rec))
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

	var vend: Dictionary = S.production.get("vendor", {}) if S.production.get("vendor", {}) is Dictionary else {}
	var v_title := String(vend.get("title", ""))
	var v_action := String(vend.get("action", ""))
	var v_id := String(S._holder_of_title(v_title))
	# 摊位（那件同时挂着"摆摊"与"赶集"两条广告位的家具）——用来量"商贩离摊子多远"
	var stall_id := ""
	var stall_pos := Vector2i(0, 0)
	for oid in S.world["objects"]:
		var o: Dictionary = S.world["objects"][oid]
		for adv in o.get("advertises", []):
			if adv is Dictionary and String(adv.get("action", "")) == v_action:
				stall_id = String(oid)
				stall_pos = o["pos"]
	# 岗位表（start_new 之后才合并 production.jobs）
	var title_of: Dictionary = {}
	for ag in S.agents:
		var jb: Dictionary = S._job_of(String(ag["id"]))
		if not jb.is_empty():
			title_of[String(ag["id"])] = String(jb.get("title", ""))

	# ── 逐 tick 扫成交 ────────────────────────────────────────────────────────
	var deals := 0                     # 全部赶集成交（含 meals_free）
	var d_buyer := 0                   # D1：钱真的进了商贩口袋（买家≠商贩 且 付得起）
	var d_vendor_here := 0             # D2：成交那一刻商贩在场
	var d_bystander := 0               # D3：成交那一刻有第三个人在场
	var d_both := 0                    # D4
	var d_paid := 0                    # 逐 tick 对齐出来的"钱真到手"（与 pay_buy 互为校准）
	var d_paid_by := 0                 # D5：钱真到手 **且** 当场有旁人（= 出货实现里 pay 事件带目击者的条数）
	var by_slots := 0                  # D5 的目击人次
	var d_self := 0                    # 买家就是商贩本人
	var d_free := 0                    # 付不起（meals_free）：没有 pay 事件
	var near_sum := 0                  # 在场人次（含商贩）
	var near_max := 0
	var near_zero := 0                 # 成交那一刻一个人都没有
	var v_dist_sum := 0                # 商贩离摊位的曼哈顿距离和（只在他与买家不同区时才有意义，一并记）
	var v_onstall := 0                 # 商贩此刻正在"摆摊"（option.action == 摆摊）
	var buyers: Dictionary = {}        # 买家 id -> 次数
	var seen_ev := 0
	var pay_buy := 0                   # note=buy:赶集 的 pay 事件数
	var pay_price := 0                 # note=price:赶集
	var tpd := int(S.TICKS_PER_DAY)
	var v_own_action := String(S._job_action(S._job_of(v_id))) if v_id != "" else ""
	for _t in range(days * tpd):
		var scan := seen_ev
		var paid_this_tick: Dictionary = {}
		S.tick()
		# ① 事件侧计数（量具校准用）
		while scan < S.event_log.size():
			var ev: Dictionary = S.event_log[scan]
			scan += 1
			if String(ev.get("type", "")) != "pay":
				continue
			var nt := String(ev.get("note", ""))
			if nt == "buy:" + v_action:
				pay_buy += 1
				paid_this_tick[String(ev.get("actor", ""))] = true
			elif nt == "price:" + v_action:
				pay_price += 1
		seen_ev = S.event_log.size()
		# ② option 相位侧计数（本探针的主口径）
		for ag in S.agents:
			var opt = ag.get("option")
			if not (opt is Dictionary):
				continue
			var o2: Dictionary = opt
			if String(o2.get("action", "")) != v_action:
				continue
			if String(o2.get("phase", "")) != "use":
				continue
			if int(o2.get("remaining", -1)) != int(o2.get("dur_total", -2)):
				continue
			# ↑ 刚刚成交的那一 tick
			deals += 1
			var bid := String(ag["id"])
			buyers[bid] = int(buyers.get(bid, 0)) + 1
			var near: Array = S._nearby_agents(ag)
			var n := near.size()
			near_sum += n
			near_max = maxi(near_max, n)
			if n == 0:
				near_zero += 1
			var vendor_here := false
			var others := 0
			for p in near:
				if String(p["id"]) == v_id:
					vendor_here = true
				else:
					others += 1
			var is_self := (bid == v_id)
			if is_self:
				d_self += 1
			if vendor_here:
				d_vendor_here += 1
			if others > 0:
				d_bystander += 1
			if vendor_here and others > 0:
				d_both += 1
			# ★D5 = 出货实现真正会用到的那个量：**钱真的到了商贩手里 且 当场至少有一个旁人**
			#   （`pay` 事件的 actor=买家、witnesses=旁人 —— 逐条照抄 `_shortage_fallout` 的形状）
			if paid_this_tick.has(bid):
				d_paid += 1
				if others > 0:
					d_paid_by += 1
					by_slots += others
			if not is_self and v_id != "" and S._agent_by_id.has(v_id):
				var vag: Dictionary = S._agent_by_id[v_id]
				v_dist_sum += S._manh(vag["pos"], stall_pos)
				var vopt = vag.get("option")
				if vopt is Dictionary and v_own_action != "" \
						and String((vopt as Dictionary).get("action", "")) == v_own_action:
					v_onstall += 1
	# 付不起的那一档 = 成交总数 − 有 pay 事件的
	d_free = deals - (pay_buy + pay_price)
	# D1 严格口径：钱进了【商贩本人】口袋（排除 price: 那一档，那一档收款方是镇库）
	d_buyer = pay_buy

	# ── 终态：商贩这一行在 v1 口径下长什么样（用来说明"他不是没干活"）────────────
	var wage_ev := 0
	var pay_total := 0
	var pay_wit := 0
	for ev2 in S.event_log:
		if String(ev2.get("type", "")) != "pay":
			continue
		pay_total += 1
		if (ev2.get("witnesses", []) as Array).size() > 0:
			pay_wit += 1
		if String(ev2.get("target", "")) == v_id and String(ev2.get("note", "")).begins_with("wage:"):
			wage_ev += 1
	var v_coin := 0
	if v_id != "" and S._agent_by_id.has(v_id):
		v_coin = int((S._agent_by_id[v_id]["inventory"] as Dictionary).get("coin", 0))
	# 全镇吃饭口径（"14% 的饭口"那句话的分母）
	var eat_attempts := int((S.prod_stats.get("attempts", {}) as Dictionary).get("吃饭", 0))
	var market_attempts := int((S.prod_stats.get("attempts", {}) as Dictionary).get(v_action, 0))
	# 对商贩的 standing 非零人数（改后要对照的那一列）
	var st_nonzero := 0
	var st_sum := 0
	var cr_holders := 0
	var cr_via: Dictionary = {}
	for ag3 in S.agents:
		for oid2 in ag3["relationships"]:
			if String(oid2) != v_id:
				continue
			var st := float((ag3["relationships"][oid2] as Dictionary).get("standing", 0.0))
			if absf(st) >= 0.0005:
				st_nonzero += 1
				st_sum += int(round(st * 1000.0))
		for cid in ag3["beliefs"]:
			var b3: Dictionary = ag3["beliefs"][cid]
			if String(b3.get("subject", "")) != v_id:
				continue
			# 以商贩为主语的信念，按【键前缀】分桶：TR:* 是本机制写的，CR:*/SH:*/其余照旧
			var pre := String(cid).split(":")[0] if ":" in String(cid) else String(cid)
			cr_holders += 1
			var vk := "%s|%s" % [pre, String(b3.get("via", ""))]
			cr_via[vk] = int(cr_via.get(vk, 0)) + 1

	var rec: Dictionary = {
		"seed": seed, "n_agents": S.agents.size(), "days": days,
		"digest": str(Inv.digest(S)),
		"events_total": S.event_log.size(),
		"vendor": {"title": v_title, "action": v_action, "id": v_id, "stall": stall_id,
			"job_title_ok": String(title_of.get(v_id, "")) == v_title},
		# ★量具校准：两条独立的计数路必须对得上（差额 = meals_free）
		"deals": deals, "pay_buy": pay_buy, "pay_price": pay_price, "meals_free": d_free,
		"econ_meals_free": int(S.econ_stats.get("meals_free", 0)),
		"attempts_market": market_attempts, "attempts_eat": eat_attempts,
		# ★四种候选口径
		"D1_buyer": d_buyer, "D2_vendor_here": d_vendor_here, "D3_bystander": d_bystander, "D4_both": d_both,
		"D5_paid_bystander": d_paid_by, "paid_tickmatch": d_paid, "D5_slots": by_slots,
		"self_buy": d_self,
		"near_sum": near_sum, "near_max": near_max, "near_zero": near_zero,
		"distinct_buyers": buyers.size(), "buyers": buyers,
		"vendor_dist_sum": v_dist_sum, "vendor_on_stall": v_onstall,
		# ★对照：v1 口径下商贩这一行
		"wage_events": wage_ev, "pay_events_total": pay_total, "pay_events_witnessed": pay_wit,
		"vendor_coin": v_coin, "vendor_standing_nonzero": st_nonzero, "vendor_standing_sum_x1000": st_sum,
		"vendor_CR_holders": cr_holders, "vendor_CR_via": cr_via,
		# ★#40 的【连续量】原料：红数不是判据（docs/103 §四），要对着零假设臂比连续余量。
		#   两条臂各自的连续量：下限臂 = 逐货 produced/consumed；上限臂 = 全年零缺货的货数。
		"prod_produced": S.prod_stats.get("produced", {}),
		"prod_consumed": S.prod_stats.get("consumed", {}),
		"prod_short": S.prod_stats.get("short", {}),
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
