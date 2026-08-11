extends SceneTree
## 夹具有效性探针（**只读**，不改任何判据，不入 ci.sh）。
##
## 它回答的问题：在 `tools/ci.sh` 每一步**实际跑的那个夹具**（seeds / days / N / 场景）下，
## 每一条不变量【要判的那件事】到底发生过几次？**零次 = 这一格结构上不可能变红。**
## 这是 docs/41 §2 第三个盲区（"门跑在一个它守的那件事不可能发生的配置上"）的**普查**版本：
## 此前每次都是靠人偶然撞见（E4 的 player_touch_test、D1 的 BackendGate C 臂、W3 的 story_test）。
##
## 做法（两条都必要）：
##   ① 原样调 `Invariants.check_all`，把 41 条的 ok + **detail 全文**打出来
##      —— detail 里本来就带很多活输入（`aid总=%d`、`背叛=%d`、`派系=%d ingroup对=%d`…），
##      而 Harness 只在**失败**时打 detail，所以绿的时候这些数字谁都看不见。
##   ② 另从 S **只读**地算一批活输入（betray 事件数、pact 各状态数、需溯源 belief 数…），
##      因为有些条目的前件根本不进 detail。
##
## ⚠ 它**不是**门，永远不判红。理由与 `recalc_registry` 里那条 `gate:false` 相同：
##   活输入是【随语料移动的快照】，给它上门等于造一道会因为无关改动变红的门。
##
## 本文件住在 `tools/`（不在 `game/bench/`）：它是量具不是 bench，且 `game/**` 不属于建它那根棒的行。
## `tools/gate_fixture_audit.py` 会把它拷进一份 `git archive` 出来的隔离副本再跑。
##
## 用法（一般走 audit.py；手跑的话）：
##   godot --headless --path <iso>/game --script res://bench/gate_fixture_probe.gd -- \
##       --seeds 1-12 --days 60 [--agents N] [--scenario faction] [--tag S0]
const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

func _initialize() -> void:
	var seeds_spec := "1-12"
	var days := 60
	var agents := 0
	var scen := ""
	var tag := "X"
	var trade_control := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size(): seeds_spec = String(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size(): days = int(args[i + 1])
		elif args[i] == "--agents" and i + 1 < args.size(): agents = int(args[i + 1])
		elif args[i] == "--scenario" and i + 1 < args.size(): scen = String(args[i + 1])
		elif args[i] == "--tag" and i + 1 < args.size(): tag = String(args[i + 1])
		elif args[i] == "--trade-control" and i + 1 < args.size(): trade_control = String(args[i + 1])
	if not trade_control in ["", "zero-import", "zero-export", "zero-both"]:
		push_error("unknown --trade-control: " + trade_control)
		quit(2)
		return
	var seeds := _parse_seeds(seeds_spec)
	for sd in seeds:
		var S = SimScript.new()
		get_root().add_child(S)
		S._load_data()
		# 量具专用方向消融：保持 logistics 字典/另一方向开启，只归零目标 lane，
		# 用于证明 #44/#46 provider 读的是事件而不是“配置存在”。不进入游戏运行时。
		if trade_control == "zero-import" or trade_control == "zero-both":
			S.logistics["import_lanes"] = []
		if trade_control == "zero-export" or trade_control == "zero-both":
			S.logistics["export_lanes"] = []
		S.auto_run = false
		S.backend = null
		if agents > 0: S.spawn_count = agents
		if scen != "": S.scenario = scen
		S.start_new(sd)
		var total: int = days * int(S.TICKS_PER_DAY)
		var starved := 0
		var by_need := {}
		for t in range(total):
			S.tick()
			for ag in S.agents:
				for nid in ag["needs"]:
					if float(ag["needs"][nid]) <= 0.5:
						starved += 1
						by_need[nid] = int(by_need.get(nid, 0)) + 1
		var R: Array = Inv.check_all(S, starved, by_need, {})
		for c in R:
			print("[X3CHK] " + JSON.stringify({
				"tag": tag, "seed": sd, "id": int(c["id"]), "ok": bool(c["ok"]),
				"hard": bool(c["hard"]), "name": String(c["name"]), "detail": String(c["detail"])}))
		print("[X3LIVE] " + JSON.stringify(_live(S, starved)))
		get_root().remove_child(S)
		S.free()
	quit(0)

## 只读地算每条不变量的"活输入"（= 它扫的那个集合有多大 / 它的前件发生了几次）。
func _live(S, starved: int) -> Dictionary:
	var log: Array = S.event_log
	var ty := {}
	for e in log:
		var k := String(e["type"])
		ty[k] = int(ty.get(k, 0)) + 1
		if k == "pact":
			var nk := "pact/" + String(e.get("note", ""))
			ty[nk] = int(ty.get(nk, 0)) + 1
	# 承诺 / 冲突
	var c_broken := 0
	var c_active_past := 0
	for c in S.commitments:
		if String(c["status"]) == "broken": c_broken += 1
		elif String(c["status"]) == "active" and int(c["deadline"]) < S.tick_no: c_active_past += 1
	var cf_rep := 0
	for c in S.conflicts:
		if String(c["status"]) == "repaired": cf_rep += 1
	# 信念：总条数 / 需溯源条数（via 不是 seed/seen）/ 秘密条数
	var bel_all := 0
	var bel_traceable := 0
	var bel_secret := 0
	for ag in S.agents:
		for cid in ag["beliefs"]:
			bel_all += 1
			var b: Dictionary = ag["beliefs"][cid]
			if not (String(b.get("via", "")) in ["seed", "seen"]): bel_traceable += 1
			if bool(b.get("secret", false)): bel_secret += 1
	# 关系指针（#7 扫的那个集合）
	var relptr := 0
	for ag in S.agents:
		for oid in ag["relationships"]:
			var r: Dictionary = ag["relationships"][oid]
			if int(r["last_pos"]) > 0: relptr += 1
			if int(r["last_neg"]) > 0: relptr += 1
	# 盟约
	var p_active := 0
	var p_broken := 0
	var p_broken_free := 0
	for p in S.pacts_index:
		match String(p["status"]):
			"active": p_active += 1
			"broken":
				p_broken += 1
				if String(p.get("reason", "")).begins_with("freerider"): p_broken_free += 1
	# 节日对象
	var fest_now := 0
	for oid in S.world.get("objects", {}):
		if String(oid).begins_with("fest_"): fest_now += 1
	# 产出
	var prod_n := 0
	var prod_wit := 0
	for e in log:
		if String(e["type"]) == "produce":
			prod_n += 1
			if (e.get("witnesses", []) as Array).size() > 0: prod_wit += 1
	var craft_tbl = S.production.get("craft_credit", {}) if not S.production.is_empty() else {}
	var craft_titles := 0
	if craft_tbl is Dictionary:
		for t in craft_tbl:
			if not String(t).begins_with("_"): craft_titles += 1
	var stifled := 0
	for ag in S.agents:
		stifled += ag["stifled"].size()
	var st_min := 0.0
	for ag in S.agents:
		for oid in ag["relationships"]:
			st_min = minf(st_min, float(ag["relationships"][oid]["standing"]))
	# 贸易硬门 #44/#46 的真实前件。不能用“logistics 开着”代替：系统开启但本局
	# 零进/出口时，逐事件断言仍然是真空为真，不能算作 complement provider。
	var import_events := int(ty.get("import", 0))
	var export_seq: Array = []
	for e in log:
		var ety := String(e.get("type", ""))
		if ety == "export":
			export_seq.append("stock")
		elif ety == "pay" and String(e.get("note", "")).split("*")[0] == "export":
			export_seq.append("pay")
	# 与 #46 的 pay,stock 流同口径，只数相邻的一一交易前件；不比较 qty/合法性，
	# 因为 probe 只量“判据有没有东西可判”，判对判错仍由 Invariants.gd 独立负责。
	var export_pairs := 0
	var xi := 0
	while xi < export_seq.size():
		if export_seq[xi] == "pay" and xi + 1 < export_seq.size() and export_seq[xi + 1] == "stock":
			export_pairs += 1
			xi += 2
		else:
			xi += 1
	var export_related := export_seq.size()
	return {
		"tag_seed": [S.agents.size(), S.tick_no],
		"scenario": String(S.scenario), "n_agents": S.agents.size(),
		"starved": starved, "events": log.size(), "types": ty,
		"commitments": S.commitments.size(), "c_broken": c_broken, "c_active_past_due": c_active_past,
		"conflicts": S.conflicts.size(), "cf_repaired": cf_rep,
		"beliefs": bel_all, "beliefs_need_trace": bel_traceable, "beliefs_secret": bel_secret,
		"rel_ptrs": relptr,
		"aid_accepted": int(S.aid_accepted), "st_neg_events": int(S.st_neg_events),
		"refused_by_bound": int(S.refused_by_bound), "stifled": stifled,
		"st_min": st_min, "rep_gossip_th": float(S.REP_GOSSIP_TH),
		"factions": S.factions.size(), "fac_unmet_ever": int(S.fac_unmet_placements),
		"pacts": S.pacts_index.size(), "pacts_active": p_active, "pacts_broken": p_broken,
		"pacts_broken_freerider": p_broken_free,
		"economy_on": not S.economy.is_empty(), "production_on": not S.production.is_empty(),
		"elections": S.election_log.size(), "fest_objects": fest_now, "festival_active": String(S.festival_active),
		"produce_events": prod_n, "produce_with_witness": prod_wit, "craft_titles_on": craft_titles,
		"import_events": import_events,
		"export_related": export_related, "export_pairs": export_pairs,
	}

func _parse_seeds(spec: String) -> Array:
	var out: Array = []
	if "-" in spec:
		var ab := spec.split("-")
		for s in range(int(ab[0]), int(ab[1]) + 1): out.append(s)
	elif "," in spec:
		for s in spec.split(","): out.append(int(s))
	else: out.append(int(spec))
	return out
