extends SceneTree
## bench/PrivacyCongestion.gd — 直接检验子问题的两个反事实：
##  A) 基线：当前"广义earshot"隐私门 → confide 数（对照）。
##  B) "仅同封闭房间"门(移除 earshot 广义化) → 模拟"把 meet 约到唯一卧室、且严格要求同室"时会怎样。
##  C) 数据层修复：给每 persona 一间独立卧室(独立 home 坐标+独立 enclosed room) → 私密容量 1→6。
##     用 monkey-patch 运行期改 world/agents(仅本探针内，不落盘、不影响 shipping digest)。
## 目的：量化"私密容量"从 1→N 时 confide 上限曲线，并检测 privacy congestion 是否出现。
## 用法: godot --headless --path . --script res://bench/PrivacyCongestion.gd -- [--seeds 1-8] [--days 60]

const SimScript = preload("res://scripts/Sim.gd")

func _init() -> void:
	var seeds := _parse_seeds("1-8")
	var days := 60
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])

	print("=== PrivacyCongestion  seeds=%s days=%d ===" % [str(seeds), days])

	# ---- 反事实 A: 基线（不改动） ----
	var A := _run_variant(seeds, days, "A_baseline_generalized_gate", func(_S): pass)

	# ---- 反事实 B: 仅同封闭房间（把每个 agent 的 home 都塞进同一间 home_bedroom，且强制赴约落点=该室中心；
	#      earshot 广义门在"同封闭房间"分支下不生效——因为 _same_enclosed_room 先返 true。
	#      为真正暴露 congestion：把 confide 判定改为"必须同封闭房间 AND 房内仅此两人"）----
	var B := _run_variant(seeds, days, "B_enclosed_room_solo_only", func(S):
		S.set_meta("gate_mode", "enclosed_solo"))

	# ---- 反事实 C: 每人独立卧室（6 个独立 home 坐标 + 6 间 enclosed room） ----
	var C := _run_variant(seeds, days, "C_six_private_bedrooms", func(S):
		_give_each_agent_own_bedroom(S))

	print("\n================= 结果对照 =================")
	print("变体                            confide  betray  ready对  私密独处对  被隐私阻断对")
	for row in [A, B, C]:
		print("  %-30s %6d  %5d  %6d  %9d  %11d" % [row["name"], row["confide"], row["betray"], row["ready"], row["private"], row["blocked"]])
	print("")
	print("解读:")
	print("  A(基线)与C(6卧室)的 confide 若相近 → 私密容量不是瓶颈, 加卧室=零收益(上限被秘密供给锁死).")
	print("  B 若 confide 崩到接近0 → 证明'仅同封闭房间/严格同室独处'才是会自我拆台的设计(congestion).")
	quit(0)

## 运行一个反事实，返回聚合指标。gate_mode 通过 meta 传入(探针内用反射式判定, 不改 Sim 源码)。
func _run_variant(seeds: Array, days: int, name: String, setup: Callable) -> Dictionary:
	var tot_conf := 0; var tot_bet := 0; var tot_ready := 0; var tot_priv := 0; var tot_blocked := 0
	for sd in seeds:
		var S = SimScript.new()
		get_root().add_child(S)
		S._load_data()
		S.auto_run = false
		S.backend = null
		setup.call(S)              # 变体改造（在 start_new 之前改 world；之后改 agents 需在 start_new 后）
		var needs_post: bool = S.has_meta("post_setup")
		S.start_new(sd)
		if S.has_meta("_post_bedroom"):
			(S.get_meta("_post_bedroom") as Callable).call(S)   # start_new 重建 agents 后再定位 home
		var TT: int = int(S.TICKS_PER_DAY)
		var total := days * TT
		var CT: float = S.CONFIDE_TRUST
		var AF: float = S.SECRET_AFF_FLOOR
		var gate_mode: String = String(S.get_meta("gate_mode", "generalized"))

		var ready := {}; var priv := {}; var conf := {}
		for t in range(total):
			S.tick()
			for a in S.agents:
				for b in S.agents:
					if a["id"] == b["id"]:
						continue
					var r: Dictionary = S._rel(a, b["id"])
					if float(r["trust"]) < CT or float(r["affinity"]) < AF:
						continue
					if S._confidable_secret(a, b) == "":
						continue
					var key: String = String(a["id"]) + ">" + String(b["id"])
					ready[key] = true
					if _gate(S, a, b, gate_mode):
						priv[key] = true
		for e in S.event_log:
			if String(e["type"]) == "confide":
				conf[String(e["actor"]) + ">" + String(e["target"])] = true
		var n_conf := 0; var n_bet := 0
		for e in S.event_log:
			if String(e["type"]) == "confide": n_conf += 1
			elif String(e["type"]) == "betray": n_bet += 1
		var blocked := 0
		for k in ready:
			if not conf.has(k) and not priv.has(k):
				blocked += 1
		tot_conf += n_conf; tot_bet += n_bet
		tot_ready += ready.size(); tot_priv += priv.size(); tot_blocked += blocked
		get_root().remove_child(S)
		S.free()
	return {"name": name, "confide": tot_conf, "betray": tot_bet, "ready": tot_ready, "private": tot_priv, "blocked": tot_blocked}

## 隐私判定（探针侧, 用于统计 private-copresence）。
func _gate(S, a: Dictionary, b: Dictionary, mode: String) -> bool:
	if mode == "enclosed_solo":
		# 必须同一封闭房间, 且房内仅此两人（最严格版本, 暴露 congestion）
		var rid := String(a.get("room", ""))
		if rid == "" or String(b.get("room", "")) != rid:
			return false
		if not bool(S.world.get("rooms", {}).get(rid, {}).get("enclosed", false)):
			return false
		for x in S.agents:
			if String(x["id"]) == String(a["id"]) or String(x["id"]) == String(b["id"]):
				continue
			if String(x.get("room", "")) == rid:
				return false     # 房里还有第三者 → 不私密
		return true
	return S._secret_private(a, b)

## 反事实C: 6 个独立卧室 —— 改 map(加 6 间 enclosed room + 6 张床) & 改 agents 的 home。
func _give_each_agent_own_bedroom(S) -> void:
	# home 区 rect=[1,1,8,6] → 内部可放 6 个 2x2 卧室. 用不重叠 rect.
	var slots := [Vector2i(1,1), Vector2i(3,1), Vector2i(5,1), Vector2i(1,3), Vector2i(3,3), Vector2i(5,3)]
	var rooms: Dictionary = S.world.get("rooms", {})
	# 移除原共享卧室, 换 6 间独立
	rooms.erase("home_bedroom")
	var ids := ["aria","ben","coco","dan","evy","fei"]
	for i in ids.size():
		var s: Vector2i = slots[i]
		rooms["bed_" + ids[i]] = {"rect": [s.x, s.y, 2, 2], "enclosed": true, "type": "bedroom", "building": "home"}
	S.world["rooms"] = rooms
	# start_new 后重定位每个 agent 的 home 到自己卧室中心
	var post := func(SS):
		var homes := {"aria": Vector2i(1,1), "ben": Vector2i(3,1), "coco": Vector2i(5,1),
			"dan": Vector2i(1,3), "evy": Vector2i(3,3), "fei": Vector2i(5,3)}
		for ag in SS.agents:
			if homes.has(String(ag["id"])):
				ag["home"] = homes[String(ag["id"])]
	S.set_meta("_post_bedroom", post)

func _parse_seeds(spec: String) -> Array:
	var out: Array = []
	if "-" in spec:
		var ab := spec.split("-")
		for s in range(int(ab[0]), int(ab[1]) + 1): out.append(s)
	elif "," in spec:
		for s in spec.split(","): out.append(int(s))
	else: out.append(int(spec))
	return out
