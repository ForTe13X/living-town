extends Node
## AR1 可落地上界普查探针（一次性；跑完从 game/ 移除，源码留在 analysis/ar1/ 作可复现凭据）。
##
## 用途：量「有几条**候选事件**落在一段【已开着的弧】的有向对上」——这才是新幕的可落地上界，
##       不是某事件族的全局总数（那是虚高得离谱的分母）。参照 docs/98/90：sided=147、give 判死=4/432。
##
## 口径：与 story_test A 段同样把仿真跑满（backend=null 零模型地板），拿到 event_log 后
##       **逐事件**折叠——在折入第 i 条之前，用当下的 `_open`（= 折完 0..i-1 的状态）探一次这条事件
##       落在哪些弧的哪个方向上。折入本身不改这些候选（它们要么是纯幕、要么根本没进表）⇒ 上界良定义。
##
## 用法：godot --headless --path game res://scenes/census_probe.tscn -- [--seeds 1-12] [--days 60]
const StoryScript = preload("res://scripts/Story.gd")
const NON_AGENT := ["", "town"]

func _ready() -> void:
	var seeds := _parse_seeds(_env("CI_STORY_SEEDS", "1-12"))
	var days := int(_env("CI_STORY_DAYS", "60"))
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])
	var total := int(days) * int(Sim.TICKS_PER_DAY)

	var arc_ids: Array = []
	for d in StoryScript.ARCS:
		arc_ids.append(String(d["id"]))
	# 候选事件类型（PAIR_TARGET = (actor,target) 那一维；也各量一份 subject 维）
	var cand := ["greet", "give", "pay", "aid", "discuss", "gossip", "meet", "invite",
		"confide", "endorse", "leak", "betray", "gossip_rep", "confront", "apologize", "rally_oust", "shortage"]

	var type_total: Dictionary = {}       # ty -> 全局总条数
	var pay_note: Dictionary = {}         # pay 的 note 前缀 -> 全局总条数（买卖/租/工资/镇库售）
	var pay_land: Dictionary = {}         # arc_id -> note桶 -> {"fwd":n,"rev":n}  只对 pay 拆 note
	var land_t: Dictionary = {}           # arc_id -> ty -> {"fwd":n,"rev":n}  (PAIR_TARGET)
	var land_s: Dictionary = {}           # arc_id -> ty -> {"fwd":n,"rev":n}  (PAIR_SUBJECT: (actor,subject))
	var note_buckets := ["buy:", "rent", "price:", "wage:", "other"]
	for aid in arc_ids:
		land_t[aid] = {}
		land_s[aid] = {}
		pay_land[aid] = {}
		for nb in note_buckets:
			pay_land[aid][nb] = {"fwd": 0, "rev": 0}
		for ty in cand:
			land_t[aid][ty] = {"fwd": 0, "rev": 0}
			land_s[aid][ty] = {"fwd": 0, "rev": 0}
	# 聚合 stats()：arc_id -> {"opened","closed","open","kept"}
	var agg: Dictionary = {}
	for aid in arc_ids:
		agg[aid] = {"opened": 0, "closed": 0, "open": 0, "kept": 0}

	for sd in seeds:
		Sim.backend = null
		Sim.record_decisions = false
		Sim.auto_run = false
		Sim.start_new(sd)
		for t in range(total):
			Sim.tick()
		var log: Array = Sim.event_log
		var live := StoryScript.new()
		var prefix: Array = []
		for i in log.size():
			var ev: Dictionary = log[i]
			var ty := String(ev.get("type", ""))
			type_total[ty] = int(type_total.get(ty, 0)) + 1
			var a := String(ev.get("actor", ""))
			var b := String(ev.get("target", ""))
			var s := String(ev.get("subject", ""))
			var note := String(ev.get("note", ""))
			if ty == "pay":
				var nb0 := "other"
				for nb in ["buy:", "rent", "price:", "wage:"]:
					if note.begins_with(nb):
						nb0 = nb
						break
				pay_note[nb0] = int(pay_note.get(nb0, 0)) + 1
			# —— PAIR_TARGET 维 ——
			if not (a in NON_AGENT) and not (b in NON_AGENT) and a != b and (ty in cand):
				for aid in arc_ids:
					if live._open.has(aid + "#" + a + ">" + b):
						(land_t[aid][ty] as Dictionary)["fwd"] += 1
					if live._open.has(aid + "#" + b + ">" + a):
						(land_t[aid][ty] as Dictionary)["rev"] += 1
				if ty == "pay":
					var nb1 := "other"
					for nb in ["buy:", "rent", "price:", "wage:"]:
						if note.begins_with(nb):
							nb1 = nb
							break
					for aid in arc_ids:
						if live._open.has(aid + "#" + a + ">" + b):
							(pay_land[aid][nb1] as Dictionary)["fwd"] += 1
						if live._open.has(aid + "#" + b + ">" + a):
							(pay_land[aid][nb1] as Dictionary)["rev"] += 1
			# —— PAIR_SUBJECT 维 ——
			if not (a in NON_AGENT) and not (s in NON_AGENT) and a != s and (ty in cand):
				for aid in arc_ids:
					if live._open.has(aid + "#" + a + ">" + s):
						(land_s[aid][ty] as Dictionary)["fwd"] += 1
					if live._open.has(aid + "#" + s + ">" + a):
						(land_s[aid][ty] as Dictionary)["rev"] += 1
			prefix.append(ev)
			live.sync(prefix)
		var st: Dictionary = live.stats()
		for aid in arc_ids:
			var row: Dictionary = st[aid]
			agg[aid]["opened"] += int(row["opened"])
			agg[aid]["closed"] += int(row["closed"])
			agg[aid]["open"] += int(row["open"])
			agg[aid]["kept"] += int(row["kept"])

	print("=== AR1 可落地上界普查 · seeds=%s · %d 天 · N=%d ===" % [str(seeds), days, Sim.spawn_count])
	print("\n[弧量] 聚合 stats()（终身口径）：")
	print("  %-8s %8s %8s %8s %8s" % ["arc", "opened", "closed", "open", "kept"])
	for aid in arc_ids:
		var r: Dictionary = agg[aid]
		print("  %-8s %8d %8d %8d %8d" % [aid, int(r["opened"]), int(r["closed"]), int(r["open"]), int(r["kept"])])

	print("\n[事件族全局总数]（分母；注意这是虚高分母，不是可落地上界）：")
	var tk: Array = type_total.keys(); tk.sort()
	var lineb := "  "
	for ty in tk:
		lineb += "%s=%d  " % [ty, int(type_total[ty])]
	print(lineb)

	print("\n[pay 的 note 组成]（全局）：")
	var pk: Array = pay_note.keys(); pk.sort()
	var lp := "  "
	for nb in pk:
		lp += "%s=%d  " % [nb, int(pay_note[nb])]
	print(lp)
	print("\n[pay 落地按 note 拆 · PAIR_TARGET]  每格 = fwd+rev=合计（person→person 才可能落地：buy:/rent）")
	var hdrp := "  %-8s" % "note"
	for aid in arc_ids:
		hdrp += "%-16s" % aid
	print(hdrp)
	for nb in note_buckets:
		var linep := "  %-8s" % nb
		for aid in arc_ids:
			var c: Dictionary = pay_land[aid][nb]
			linep += "%-16s" % ("%d+%d=%d" % [int(c["fwd"]), int(c["rev"]), int(c["fwd"]) + int(c["rev"])])
		print(linep)

	print("\n[可落地上界 · PAIR_TARGET=(actor,target)]  每格 = fwd+rev=合计（占该族全局 %）")
	_print_matrix(arc_ids, cand, land_t, type_total)
	print("\n[可落地上界 · PAIR_SUBJECT=(actor,subject)]  每格 = fwd+rev=合计（占该族全局 %）")
	_print_matrix(arc_ids, cand, land_s, type_total)
	get_tree().quit(0)

func _print_matrix(arc_ids: Array, cand: Array, land: Dictionary, type_total: Dictionary) -> void:
	var hdr := "  %-10s" % "type"
	for aid in arc_ids:
		hdr += "%-16s" % aid
	print(hdr)
	for ty in cand:
		var line := "  %-10s" % ty
		for aid in arc_ids:
			var c: Dictionary = land[aid][ty]
			var tot := int(c["fwd"]) + int(c["rev"])
			var cell := "%d+%d=%d" % [int(c["fwd"]), int(c["rev"]), tot]
			line += "%-16s" % cell
		var gt := int(type_total.get(ty, 0))
		line += "  /%d" % gt
		print(line)

func _env(key: String, dflt: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else dflt

func _parse_seeds(spec: String) -> Array:
	var out: Array = []
	if spec.contains("-"):
		var p := spec.split("-")
		for s in range(int(p[0]), int(p[1]) + 1):
			out.append(s)
	else:
		for s in spec.split(","):
			out.append(int(s))
	return out
