extends Node
## aa2_slot_polarity.gd —— AA2 的**改前清点**：每一个文案槽位，实际引用的那些事件
## 在【极性】那一维上长什么样。
##
## ★为什么必须先量这个（docs/41「先确认你量的是哪个对象」）：
##   Y3 漏网的 19 条全是"同类型对调"，而它们**能不能被抓住**取决于一件事——
##   被引用的那条事件身上有没有一个【仿真侧写的、能把两条文案分开的字段】。
##   候选只有两个：`accepted`（bool）与 `note`（string）。
##   而"匹配器声明了 accepted:true"**不等于**"真世界里引用到的事件都是 true"——
##   有些槽位的匹配器**根本没声明**（如 secret/open 的 {"type":["confide"]}）。
##   ⇒ 这一遍量的正是：**每个槽位实际引用到的事件，(accepted, note) 的真实分布**。
##
## 顺带回答一个只有真数据能回答的问题：
##   有没有槽位的匹配器对 accepted 沉默，而真世界两种极性都会落进来？
##   —— 那种槽位今天就在屏幕上把"被婉拒"讲成"做成了"。
##
## 用法：godot --headless --path <iso>/game res://scenes/aa2_slot_polarity.tscn -- [--seeds 1-12] [--days 60]

const StoryScript = preload("res://scripts/Story.gd")

func _ready() -> void:
	var seeds := _parse_seeds(_arg("--seeds", "1-12"))
	var days := int(_arg("--days", "60"))
	var total := days * int(Sim.TICKS_PER_DAY)

	# 槽位 → { "<accepted>|<note前缀>" : 条数 }
	var slot_pol: Dictionary = {}
	# 槽位 → 引用总条数
	var slot_n: Dictionary = {}
	# 事件类型 → { true: n, false: n }（全日志口径，与是否被引用无关）
	var type_pol: Dictionary = {}
	var rows_total := 0

	for sd in seeds:
		Sim.backend = null
		Sim.record_decisions = false
		Sim.auto_run = false
		Sim.start_new(sd)
		for t in range(total):
			Sim.tick()
		var log: Array = Sim.event_log.duplicate()
		var by_id: Dictionary = {}
		for e in log:
			by_id[int((e as Dictionary)["id"])] = e
			var tt := String((e as Dictionary).get("type", ""))
			if not type_pol.has(tt):
				type_pol[tt] = {"t": 0, "f": 0, "notes": {}}
			var b: Dictionary = type_pol[tt]
			if bool((e as Dictionary).get("accepted", false)):
				b["t"] = int(b["t"]) + 1
			else:
				b["f"] = int(b["f"]) + 1
			var nn := String((e as Dictionary).get("note", ""))
			(b["notes"] as Dictionary)[nn] = int((b["notes"] as Dictionary).get(nn, 0)) + 1

		var st := StoryScript.new()
		st.recompute(log)
		for arc in st.arcs:
			var d := st.def_of(arc)
			var did := String(d["id"])
			for row in st.narrate_cited(arc, func(id): return id):
				var r: Dictionary = row
				var kind := String(r["kind"])
				var ids: Array = []
				if kind == "aside":
					ids = (r["evs"] as Array).duplicate()
				elif int(r["ev"]) >= 0:
					ids = [int(r["ev"])]
				if ids.is_empty():
					continue
				var slot := ""
				match kind:
					"open": slot = did + "/open"
					"beat": slot = did + "/beat:" + String(r["mid"])
					"end": slot = did + "/end:" + String(r["mid"])
					"aside": slot = did + "/aside"
					_: continue
				for eid in ids:
					if not by_id.has(int(eid)):
						continue
					var ev: Dictionary = by_id[int(eid)]
					var np := String(ev.get("note", ""))
					if np.contains(":"):
						np = np.substr(0, np.find(":"))      # "backers:3" / "dissolved:freerider" → 前缀
					if np.contains("*"):
						np = np.substr(0, np.find("*"))      # "craft*3" 这类计量后缀
					var k := ("+" if bool(ev.get("accepted", false)) else "-") + " note=" + (np if np != "" else "∅")
					if not slot_pol.has(slot):
						slot_pol[slot] = {}
						slot_n[slot] = 0
					(slot_pol[slot] as Dictionary)[k] = int((slot_pol[slot] as Dictionary).get(k, 0)) + 1
					slot_n[slot] = int(slot_n[slot]) + 1
					rows_total += 1

	print("=== AA2 槽位 × 引用事件极性 · seeds=%s · %d 天 · N=%d ===" % [str(seeds), days, Sim.agents.size()])
	print("（accepted 记作 +/-；note 只取冒号/星号前的前缀）")
	var ks: Array = slot_pol.keys()
	ks.sort()
	for k in ks:
		var b: Dictionary = slot_pol[k]
		var parts: Array = []
		var bk: Array = b.keys()
		bk.sort()
		for x in bk:
			parts.append("%s×%d" % [String(x), int(b[x])])
		print("%-28s 引用 %6d 条  →  %s%s" % [k, int(slot_n[k]), "  ".join(PackedStringArray(parts)),
			("   ⚠️ 两种极性都落进来了" if bk.size() > 1 else "")])

	print("")
	print("=== 全日志：事件类型 × accepted × note（与是否被引用无关）===")
	var tk: Array = type_pol.keys()
	tk.sort()
	for t2 in tk:
		var b2: Dictionary = type_pol[t2]
		var nk: Array = (b2["notes"] as Dictionary).keys()
		nk.sort()
		var np2: Array = []
		for x2 in nk:
			np2.append("%s×%d" % [(String(x2) if String(x2) != "" else "∅"), int((b2["notes"] as Dictionary)[x2])])
		print("%-14s +%-7d -%-7d  note: %s" % [t2, int(b2["t"]), int(b2["f"]), "  ".join(PackedStringArray(np2))])

	print("")
	print("引用行合计 %d 条" % rows_total)
	get_tree().quit(0)

func _arg(name: String, dflt: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
	return dflt

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
