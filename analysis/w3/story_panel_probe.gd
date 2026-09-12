extends Node
## story_panel_probe.gd — W3：**新加的弧到底上不上得了屏幕。**
## 覆盖率是"进了纪事"，不是"玩家看得见"——这两件事差一层排序（`open_arcs` 按最近有动静排、
## `panel_text` 只有 16 行预算）。本探针量的是后者，别拿前者冒充。
## 用法：godot --headless --path <iso2>/game res://scenes/story_panel_probe.tscn -- [--seeds 1-6] [--days 60]

const StoryScript = preload("res://scripts/Story.gd")

func _ready() -> void:
	var seeds := _parse_seeds(_arg("--seeds", "1-6"))
	var days := int(_arg("--days", "60"))
	var total := days * int(Sim.TICKS_PER_DAY)
	var panel_hits := 0
	var panel_seeds := 0
	var person_hits := 0
	var person_seeds := 0
	for sd in seeds:
		Sim.backend = null
		Sim.record_decisions = false
		Sim.auto_run = false
		Sim.start_new(sd)
		for t in range(total):
			Sim.tick()
		var st := StoryScript.new()
		st.recompute(Sim.event_log)
		var txt := _plain(st.panel_text(_nm, 16))
		var n := txt.count("◇ 手艺")
		panel_hits += n
		if n > 0:
			panel_seeds += 1
		print("── seed %d · 第 %d 天 · 面板（16 行预算）· 手艺行 %d ──" % [sd, days, n])
		print(txt)
		# 卷宗侧：谁的故事里有手艺弧（person_lines 按【戏份】排，不是按最近）
		var who_hit: Array = []
		for ag in Sim.agents:
			var id := String(ag["id"])
			var lines: Array = st.person_lines(id, _nm, 2)
			for ln in lines:
				if String(ln).contains("◇ 手艺"):
					who_hit.append("%s：%s" % [Sim._name(ag), _plain(String(ln))])
					break
		person_hits += who_hit.size()
		if not who_hit.is_empty():
			person_seeds += 1
		print("  卷宗「他的故事」前 2 行里出现手艺弧的居民：%d/%d" % [who_hit.size(), Sim.agents.size()])
		for w in who_hit:
			print("    " + w)
		print("")
	print("=== 合计：面板出现手艺行 %d 次（%d/%d seed）；卷宗前两行出现手艺 %d 人次（%d/%d seed）===" % [
		panel_hits, panel_seeds, seeds.size(), person_hits, person_seeds, seeds.size()])
	get_tree().quit(0)

func _nm(id: String) -> String:
	return Sim._name(Sim.get_agent(id))

func _plain(s: String) -> String:
	var out := ""
	var i := 0
	while i < s.length():
		if s[i] == "[":
			var j := s.find("]", i)
			if j > i and j - i < 40:
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
