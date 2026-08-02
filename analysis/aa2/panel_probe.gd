extends Node
## aa2_panel.gd —— 把「小镇故事」面板**逐字**打出来（去掉 BBCode），
## 用来给"屏幕上每一次赴约都被说成爽约"这句话一份可以逐字抄的证据，
## 而不是只报一个违规计数。
##
## 用法：godot --headless --path <iso>/game res://scenes/aa2_panel.tscn -- [--seed 1] [--days 40]

const StoryScript = preload("res://scripts/Story.gd")

func _ready() -> void:
	var sd := int(_arg("--seed", "1"))
	var days := int(_arg("--days", "40"))
	Sim.backend = null
	Sim.record_decisions = false
	Sim.auto_run = false
	Sim.start_new(sd)
	for t in range(days * int(Sim.TICKS_PER_DAY)):
		Sim.tick()
	var st := StoryScript.new()
	st.recompute(Sim.event_log)
	print("=== 小镇故事面板 · seed %d · 第 %d 天 ===" % [sd, days])
	print(_plain(st.panel_text(func(id): return String(Sim.get_agent(id).get("name", id)), 16)))
	print("")
	print("=== promise 弧的全部结局（终身账）===")
	var s: Dictionary = st.stats()
	print("promise: " + str((s["promise"] as Dictionary)["ends"]))
	print("")
	print("=== 头 6 段已收场的 promise 弧，逐字成文 ===")
	var n := 0
	for arc in st.closed_arcs():
		if String(st.def_of(arc)["id"]) != "promise":
			continue
		n += 1
		if n > 6:
			break
		var ev1 := int(arc["ev1"])
		var acc := "?"
		for e in Sim.event_log:
			if int((e as Dictionary)["id"]) == ev1:
				acc = str(bool((e as Dictionary).get("accepted", false)))
				break
		print("  [结局=%s · 依据 event #%d 的 accepted=%s]" % [String(arc["end"]), ev1, acc])
		for ln in st.narrate(arc, func(id): return String(Sim.get_agent(id).get("name", id))):
			print("    " + _plain(String(ln)))
	get_tree().quit(0)

func _plain(s: String) -> String:
	var out := ""
	var i := 0
	while i < s.length():
		if s[i] == "[":
			var j := s.find("]", i)
			if j > i:
				i = j + 1
				continue
		out += s[i]
		i += 1
	return out

func _arg(name: String, dflt: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
	return dflt
