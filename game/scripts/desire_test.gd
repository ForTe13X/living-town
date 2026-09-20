extends Node
## desire_test.gd — 欲望 v0 步骤 1-4 的门（docs/187 §五/§七·七/§八）。
## 用法：godot --headless --path game res://scenes/desire_test.tscn -- [--seeds 1-2] [--days 3]
##       （或 CI_DESIRE_SEEDS / CI_DESIRE_DAYS 环境变量）
##
## 本步只有【状态 + 候选 + 强度】、没有任何行为效应，所以这里的门比 docs/187 §五 的 D1 更强：
##   D1  开着跑（enabled=true）的逐 tick 前缀链 / Inv.digest / event_digest 必须与关时【逐字节相同】。
##       ⇒ 证明本步是纯观测：没加分、没碰 need、没写 event_log、没消耗 RNG、没用 _rel 顺手建关系。
##       （步骤 3 起行为会分叉，届时这条要降回"缺文件时与 master 相同"的弱形式。）
##   D1f fail-closed：{} / enabled=1 / enabled="true" / 缺 enabled / enabled=false ⇒ 没有任何 agent 长出 "desire" 键。
##   D2  生存门：任一 need < SURVIVAL_GATE ⇒ 强度增量恒 0；门上 ⇒ 增量 > 0（单元级，直接调 _desire_tick）。
##   KB  知识边界：每个 person 对象都必须能在 event_log 里找到一条【被接受的深层动作、目标=它、我在 witnesses 里】。
##   LV  活性（判别力，docs/41 §6-★）：一个什么都不做的实现能过 D1/D1f/D2/KB ⇒ 另要求每个 seed 至少一半居民有对象且强度>0。
##   SL  存档往返：开着跑到 T/2 存档、新实例读档，两边续跑后每人的 desire 字典逐字节相同。
const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")
## 步骤 3 起 D1 分两臂：OBS（开、无 bonus_k ⇒ 纯观测）必须与关逐字节相同；ON（bonus_k=8）必须真分叉。
##   D3  bonus 作用面：同一时刻同一 agent，bonus_k 0↔8 两次枚举候选，分数变了的只能是
##       【社交候选】×（person：对 target 的 give/invite/confide；status：aid/endorse）。greet / 物件候选一律不许动。
const OBS_CFG := {"enabled": true, "gain": 0.15, "mimetic_cap": 5.0}
const ON_CFG := {"enabled": true, "gain": 0.15, "mimetic_cap": 5.0, "bonus_k": 8.0}
## 步骤 4：ON_CFG 故意【不带】rho/r_max ⇒ 上面 D1'/D3/SL 仍逐字节复现步骤 3。S4_CFG 另开一臂：
##   D4  逐 tick：每人 rebuffs < r_max，且当前 target ∉ recent（放弃/满足后不回锅）；
##       自然轨迹报告满足/放弃次数；定向事件夹具必须逐条验证满足、阈值前保留和阈值后释放。
##       这样一个从不释放对象的实现仍然必红，不依赖短窗口里恰好发生足够的目击和相遇。
##   CR  拥挤项（单元级）：同一份手搭证据，缺 crowd_k ⇒ 被 4 个不同的人示好的 X 胜（外中介）；
##       crowd_k=0.5 ⇒ 被 1 个人反复示好的 Y 胜（内中介）。证明拥挤项真的翻转了选择，且缺键时不起作用。
##   MS  最少证据（单元级）：seen < min_seen ⇒ 不选；达到 ⇒ 选。
##   RV  满足后重估（单元级）：他人权重 > 当前 × (1+margin) ⇒ 换且旧对象入 recent；不够 ⇒ 不换；缺 switch_margin ⇒ 从不换。
## = docs/187 §七·十 选定的步骤 4 缺省配置（用户 2026-09-12 选定）。
const S4_CFG := {"enabled": true, "gain": 0.15, "mimetic_cap": 5.0, "bonus_k": 8.0, "rho": 0.6, "r_max": 3, "crowd_k": 1.0,
	"min_seen": 8, "switch_margin": 0.5}

var _fails := 0
func ck(c: bool, m: String) -> void:
	if not c: _fails += 1
	print(("  OK   " if c else "  FAIL ") + m)

func _parse_seeds(s: String) -> Array:
	var out := []
	if "-" in s:
		var p := s.split("-")
		for v in range(int(p[0]), int(p[1]) + 1): out.append(v)
	else:
		out.append(int(s))
	return out

func _new_sim(cfg: Dictionary) -> Node:
	var S = SimScript.new(); add_child(S)          # _ready → _load_data（出货无 desire.json ⇒ desire_cfg={}）
	S.desire_cfg = cfg.duplicate(true)
	return S

## 跑 ticks 步，返回 {chain, digest, event_digest}。
func _run(S, seed: int, ticks: int) -> Dictionary:
	S.start_new(seed)
	var h: int = Inv.CHAIN_INIT
	for i in range(ticks):
		var ev_from: int = S.event_log.size()
		S.tick()
		h = Inv.chain_step(h, S, ev_from)
	return {"chain": h, "digest": Inv.digest(S), "event_digest": S.event_digest}

func _free(S) -> void:
	remove_child(S); S.free()

func _ready() -> void:
	# 默认网格压小（CI 预算 35 分钟已吃紧，见 ci.yml）：步骤 1-2 的 D1 是逐 tick 前缀链，分叉必在头几天现形。
	# ci.sh 场景循环不传参 ⇒ 调档走环境变量。
	var seeds := _parse_seeds(OS.get_environment("CI_DESIRE_SEEDS") if OS.has_environment("CI_DESIRE_SEEDS") else "1-2")
	var days := int(OS.get_environment("CI_DESIRE_DAYS")) if OS.has_environment("CI_DESIRE_DAYS") else 3
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size(): seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size(): days = int(args[i + 1])

	# ── D1f：fail-closed ──
	print("D1f fail-closed")
	for bad_cfg in [{}, {"enabled": 1}, {"enabled": "true"}, {"gain": 0.2}, {"enabled": false}]:
		var S = _new_sim(bad_cfg)
		S.start_new(1)
		for i in range(int(S.TICKS_PER_DAY)): S.tick()
		var grown: int = S.agents.filter(func(a): return a.has("desire")).size()
		ck(not S._desire_on() and grown == 0, "cfg=%s ⇒ 关，长出 desire 键的 agent=%d" % [JSON.stringify(bad_cfg), grown])
		_free(S)

	# ── D2：生存门（单元级）──
	print("D2 survival gate")
	var U = _new_sim(ON_CFG)
	U.start_new(1)
	var ag: Dictionary = U.agents[0]
	var other := String(U.agents[1]["id"])
	var d: Dictionary = U._desire_state(ag)
	d["kind"] = "person"; d["target"] = other; d["intensity"] = 10.0
	for nid in ag["needs"]: ag["needs"][nid] = U.SURVIVAL_GATE - 0.01
	U._desire_tick(ag)
	ck(float(d["intensity"]) == 10.0, "min_need=GATE-0.01 ⇒ 强度不变 (%.4f)" % float(d["intensity"]))
	for nid in ag["needs"]: ag["needs"][nid] = U.SURVIVAL_GATE
	U._desire_tick(ag)
	ck(float(d["intensity"]) > 10.0, "min_need=GATE ⇒ 强度增长 (%.4f)" % float(d["intensity"]))
	for i in range(5000): U._desire_tick(ag)
	ck(float(d["intensity"]) <= 100.0, "有界 ≤100 (%.4f)" % float(d["intensity"]))
	_free(U)

	# ── CR：拥挤项（单元级，手搭证据直接调 _desire_pick）──
	print("CR crowding")
	var C = _new_sim(ON_CFG)                       # ON_CFG 不带 crowd_k
	C.start_new(1)
	var npcs: Array = C.agents.filter(func(a): return not a.get("is_player", false))
	var me: Dictionary = npcs[0]
	var ids: Array = []
	for i in range(1, 7): ids.append(String(npcs[i]["id"]))
	var seen_c: Array = []
	for a_id in [ids[2], ids[3], ids[4], ids[5]]: seen_c.append([0, "give", a_id, ids[0]])   # X：4 个不同的人各示好一次
	for k in 3: seen_c.append([0, "give", ids[2], ids[1]])                                  # Y：同一个人示好三次
	(me["relationships"] as Dictionary).clear()                                              # admire=0，只比证据形状
	var dc: Dictionary = C._desire_state(me)
	dc["seen"] = seen_c.duplicate(true); dc["kind"] = ""; dc["target"] = ""
	C._desire_pick(me, dc)
	ck(String(dc["target"]) == ids[0], "CR 缺 crowd_k ⇒ 外中介：4 人示好的 X 胜 (got %s)" % dc["target"])
	C.desire_cfg["crowd_k"] = 0.5
	dc["seen"] = seen_c.duplicate(true); dc["kind"] = ""; dc["target"] = ""
	C._desire_pick(me, dc)
	ck(String(dc["target"]) == ids[1], "CR crowd_k=0.5 ⇒ 内中介：1 人反复示好的 Y 胜 (got %s)" % dc["target"])
	_free(C)

	# ── MS / RV：最少证据 + 满足后重估（单元级）──
	print("MS/RV")
	var R = _new_sim(ON_CFG)
	R.start_new(1)
	var rn: Array = R.agents.filter(func(a): return not a.get("is_player", false))
	var rme: Dictionary = rn[0]
	var rid: Array = []
	for i in range(1, 7): rid.append(String(rn[i]["id"]))
	(rme["relationships"] as Dictionary).clear()
	var dr: Dictionary = R._desire_state(rme)
	R.desire_cfg["min_seen"] = 5
	dr["seen"] = [[0, "give", rid[2], rid[0]], [0, "give", rid[3], rid[0]], [0, "give", rid[4], rid[1]]]
	dr["kind"] = ""; dr["target"] = ""
	R._desire_pick(rme, dr)
	ck(String(dr["kind"]) == "", "MS seen=3 < min_seen=5 ⇒ 不选 (kind=%s)" % dr["kind"])
	(dr["seen"] as Array).append_array([[0, "give", rid[2], rid[0]], [0, "give", rid[5], rid[1]]])
	R._desire_pick(rme, dr)
	ck(String(dr["kind"]) == "person", "MS seen=5 ⇒ 选 (target=%s)" % dr["target"])
	R.desire_cfg.erase("min_seen")
	# RV：当前 X 被示好 1 次，Y 被同一人示好 3 次 ⇒ 3 > 1×1.5 ⇒ 换。
	var rv_seen := [[0, "give", rid[2], rid[0]], [0, "give", rid[3], rid[1]], [0, "give", rid[3], rid[1]], [0, "give", rid[3], rid[1]]]
	dr["seen"] = rv_seen.duplicate(true); dr["kind"] = "person"; dr["target"] = rid[0]; dr["recent"] = []
	R._desire_reconsider(rme, dr)
	ck(String(dr["target"]) == rid[0], "RV 缺 switch_margin ⇒ 从不换 (target=%s)" % dr["target"])
	R.desire_cfg["switch_margin"] = 0.5
	R._desire_reconsider(rme, dr)
	ck(String(dr["target"]) == rid[1] and rid[0] in dr["recent"], "RV Y(3) > X(1)×1.5 ⇒ 换，旧对象入 recent (target=%s recent=%s)" % [dr["target"], str(dr["recent"])])
	# 不够门槛：X 2 次、Y 3 次 ⇒ 3 > 2×1.5=3 不成立 ⇒ 留
	dr["seen"] = [[0, "give", rid[2], rid[0]], [0, "give", rid[4], rid[0]], [0, "give", rid[3], rid[1]], [0, "give", rid[3], rid[1]], [0, "give", rid[3], rid[1]]]
	dr["kind"] = "person"; dr["target"] = rid[0]; dr["recent"] = []
	R._desire_reconsider(rme, dr)
	ck(String(dr["target"]) == rid[0], "RV Y(3) 未超 X(2)×1.5 ⇒ 留 (target=%s)" % dr["target"])
	_free(R)

	# ── D1 / KB / LV：逐 seed 关/开对拍 ──
	var T := days * int(SimScript.TICKS_PER_DAY)
	var diverged := 0
	for seed in seeds:
		print("seed %d · %d 天" % [seed, days])
		var A = _new_sim({})
		var ra := _run(A, seed, T)
		_free(A)
		var O = _new_sim(OBS_CFG)
		var ro := _run(O, seed, T)
		_free(O)
		ck(ra["chain"] == ro["chain"], "D1 OBS 臂前缀链与关相同 (%d)" % int(ra["chain"]))
		ck(ra["digest"] == ro["digest"] and ra["event_digest"] == ro["event_digest"], "D1 OBS 臂 digest/event_digest 与关相同")
		var B = _new_sim(ON_CFG)
		var rb := _run(B, seed, T)
		if ra["chain"] != rb["chain"]:
			diverged += 1
		print("       ℹ ON 臂 (bonus_k=8) 与关%s" % ("分叉" if ra["chain"] != rb["chain"] else "未分叉"))

		# KB：对象必须有亲眼所见的证据（全程 event_log 中找）
		var kb_bad: Array = []
		var n_obj := 0
		var n_person := 0
		var n_status := 0
		var targets := {}
		var imax := 0.0
		var npc := 0
		for a in B.agents:
			if a.get("is_player", false): continue
			npc += 1
			if not a.has("desire"): continue
			var dd: Dictionary = a["desire"]
			if String(dd["kind"]) == "": continue
			if float(dd["intensity"]) > 0.0: n_obj += 1
			imax = maxf(imax, float(dd["intensity"]))
			if String(dd["kind"]) == "status":
				n_status += 1
				continue
			n_person += 1
			var tg := String(dd["target"])
			targets[tg] = int(targets.get(tg, 0)) + 1
			var ok := false
			for e in B.event_log:
				if String(e["type"]) in SimScript.DESIRE_DEEP_ACTS and bool(e["accepted"]) \
						and String(e["target"]) == tg and String(a["id"]) in e["witnesses"]:
					ok = true; break
			if not ok or tg == String(a["id"]): kb_bad.append("%s→%s" % [a["id"], tg])
		ck(kb_bad.is_empty(), "KB 对象皆有亲眼证据 (违例=%s)" % str(kb_bad))
		ck(n_obj * 2 >= npc, "LV 有对象且强度>0 的居民 %d/%d (person=%d status=%d, 强度max=%.1f)" % [n_obj, npc, n_person, n_status, imax])
		var top := 0
		for k in targets: top = maxi(top, int(targets[k]))
		print("       ℹ 被欲望指向的不同对象=%d，最集中的一人被 %d 人指向" % [targets.size(), top])
		_free(B)
	ck(diverged > 0, "D1' bonus_k=8 至少一个 seed 行为分叉 (%d/%d)" % [diverged, seeds.size()])

	# ── D3：bonus 作用面（单独实例：agent_candidates 里的 _rel 会顺手建关系，不拿它对拍 digest）──
	print("D3 bonus 作用面")
	var P = _new_sim(ON_CFG)
	P.start_new(int(seeds[0]))
	var legal := 0
	var illegal: Array = []
	for i in range(T):
		P.tick()
		if i % 20 != 0: continue
		for a in P.agents:
			if a.get("is_player", false) or not a.has("desire"): continue
			var d3: Dictionary = a["desire"]
			if String(d3["kind"]) == "" or float(d3["intensity"]) <= 0.0: continue
			P.desire_cfg["bonus_k"] = 0.0
			var c0: Array = P.agent_candidates(a)
			P.desire_cfg["bonus_k"] = 8.0
			var c1: Array = P.agent_candidates(a)
			if c0.size() != c1.size():
				illegal.append("%s 候选数 %d→%d" % [a["id"], c0.size(), c1.size()])
				continue
			for j in c0.size():
				if float(c0[j].get("score", 0.0)) == float(c1[j].get("score", 0.0)): continue
				var act := String(c1[j].get("action", ""))
				var person := String(d3["kind"]) == "person"
				var ok3 := String(c1[j].get("kind", "")) == "social" and (
					(person and act in SimScript.DESIRE_DEEP_ACTS and String(c1[j].get("partner", "")) == String(d3["target"]))
					or (not person and act in SimScript.DESIRE_STATUS_SEEK))
				if ok3: legal += 1
				else: illegal.append("%s:%s/%s→%s" % [a["id"], c1[j].get("kind", ""), act, c1[j].get("partner", "")])
	ck(illegal.is_empty(), "D3 分数变动只落在合法 (社交×深层/求认可) 候选上 (违例=%s)" % str(illegal.slice(0, 5)))
	ck(legal > 0, "D3 活性：确有候选被加分 (%d 次)" % legal)
	_free(P)

	# ── D4：满足/放弃（反执念 + 不回锅）──
	print("D4 满足/放弃")
	var Q = _new_sim(S4_CFG)
	Q.start_new(int(seeds[0]))
	var r_max := int(S4_CFG["r_max"])
	var d4_bad: Array = []
	var releases := 0
	var sats := 0
	var prev := {}
	for i in range(T):
		Q.tick()
		for a in Q.agents:
			if not a.has("desire"): continue
			var d4: Dictionary = a["desire"]
			var aid := String(a["id"])
			if int(d4["rebuffs"]) >= r_max:
				d4_bad.append("%s@%d rebuffs=%d" % [aid, Q.tick_no, int(d4["rebuffs"])])
			if String(d4["target"]) != "" and String(d4["target"]) in d4["recent"]:
				d4_bad.append("%s@%d 回锅 %s" % [aid, Q.tick_no, d4["target"]])
			if (d4["recent"] as Array).size() > SimScript.DESIRE_RECENT_K:
				d4_bad.append("%s@%d recent 超长" % [aid, Q.tick_no])
			var tg4 := String(d4["target"])
			var in4 := float(d4["intensity"])
			if prev.has(aid):
				var p_tg := String(prev[aid][0])
				if p_tg != "" and tg4 != p_tg:
					releases += 1                                  # 放弃（或被清空后重选）
				elif p_tg != "" and tg4 == p_tg and in4 < float(prev[aid][1]) - 1e-9:
					sats += 1                                      # 满足：强度只会因满足而同对象下跌
			prev[aid] = [tg4, in4]
	ck(d4_bad.is_empty(), "D4 无执念、无回锅、recent≤K (违例=%s)" % str(d4_bad.slice(0, 5)))
	print("  D4 natural observation: satisfied=%d released=%d; branch coverage is asserted below" % [sats, releases])
	_free(Q)
	# Directed outcomes also exercise both branches independently of encounter luck.
	var V = _new_sim(S4_CFG)
	V.start_new(1)
	var va: Dictionary = V.agents[0]
	var vt := String(V.agents[1]["id"])
	var vd: Dictionary = V._desire_state(va)
	vd.merge({"kind": "person", "target": vt, "intensity": 80.0, "rebuffs": 1}, true)
	var ve := {"type": "give", "actor": String(va.id), "target": vt, "accepted": true, "witnesses": []}
	V._desire_witness(ve)
	ck(is_equal_approx(float(vd.intensity), 80.0 * (1.0 - float(S4_CFG.rho))) and int(vd.rebuffs) == 0 and String(vd.target) == vt,
		"D4 accepted event reduces intensity, clears rebuffs, and retains target")
	ve.accepted = false
	for i in range(r_max - 1): V._desire_witness(ve)
	ck(String(vd.target) == vt, "D4 target retained below rejection threshold")
	V._desire_witness(ve)
	ck(String(vd.target) == "" and vt in vd.recent and int(vd.rebuffs) == 0,
		"D4 rejection threshold releases target and records recent history")
	_free(V)

	# ── SL：存档往返 ──
	print("SL save/load")
	var path := "user://desire_test.dat"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var SA = _new_sim(ON_CFG)
	SA.start_new(int(seeds[0]))
	for i in range(T / 2): SA.tick()
	ck(SA.save_game(path, {"name": "desire_test"}), "save_game 成功（desire_cfg 在 DENY、schema 形状未变）")
	var SB = _new_sim(ON_CFG)
	ck(SB.load_game(path), "load_game 成功")
	for i in range(int(SimScript.TICKS_PER_DAY)):
		SA.tick(); SB.tick()
	var same := true
	for i in SA.agents.size():
		if var_to_str(SA.agents[i].get("desire", {})) != var_to_str(SB.agents[i].get("desire", {})):
			same = false
	ck(same, "续跑 1 天后每人 desire 逐字节相同")
	ck(Inv.digest(SA) == Inv.digest(SB), "续跑 digest 相同")
	_free(SA); _free(SB)

	print("")
	print("DESIRE_TEST_FAILS=%d" % _fails)
	print("✅ desire_test 全绿" if _fails == 0 else "❌ desire_test %d 条失败" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
