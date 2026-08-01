extends Node
## story_census.gd — W3 的**改前清点表**（隔离副本里跑，不入库到 game/）。
## 问的是一个很窄的问题：`Sim.event_log` 里的每一种事件类型，**被 Story.gd 的折叠消费了没有**？
##
## ★量的是哪个对象（docs/41 §「先确认你量的是哪个对象」）：
##   本脚本**不重新实现** Story 的匹配逻辑（那样量到的是我抄的那一份，不是真的那一份）。
##   它把**真的 Story.gd** 逐条喂事件，比对每条事件前后的弧快照差分，据此把这条事件归类为
##   open / beat / end / aside / sweep(冷场清扫被它触发) / none。
##
## 用法：godot --headless --path <iso>/game res://scenes/story_census.tscn -- [--seeds 1-6] [--days 60]

const StoryScript = preload("res://scripts/Story.gd")

func _ready() -> void:
	var seeds := _parse_seeds(_arg("--seeds", "1-6"))
	var days := int(_arg("--days", "60"))
	var agents := int(_arg("--agents", "0"))
	if agents > 0:
		Sim.spawn_count = agents

	var total := days * int(Sim.TICKS_PER_DAY)
	# key = 事件类型（pact/world/produce 再按 note/witnesses 细分，因为那是 Story 文法真正分辨的粒度）
	var cnt: Dictionary = {}
	var role: Dictionary = {}          # key -> {open:n, beat:n, end:n, aside:n, sweep:n, none:n}
	var seedcov: Dictionary = {}       # key -> {seed:true}

	for sd in seeds:
		Sim.backend = null
		Sim.record_decisions = false
		Sim.auto_run = false
		Sim.start_new(sd)
		for t in range(total):
			Sim.tick()
		var log: Array = Sim.event_log.duplicate()

		var st := StoryScript.new()
		var acc: Array = []
		var before := _snapmap(st)
		for ev in log:
			var k := _key(ev)
			cnt[k] = int(cnt.get(k, 0)) + 1
			if not seedcov.has(k):
				seedcov[k] = {}
			(seedcov[k] as Dictionary)[sd] = true
			if not role.has(k):
				role[k] = {"open": 0, "beat": 0, "end": 0, "aside": 0, "sweep": 0, "none": 0, "hit": 0}
			acc.append(ev)
			var fresh: Array = st.sync(acc)
			var after := _snapmap(st)
			var r: Dictionary = role[k]
			var touched := false
			var consumed_here := false      # 「这条事件被弧的文法消费了」——open/beat/end/aside 任一（sweep 不算：那是时钟推的）
			# ① 新开的弧
			for n in after:
				if not before.has(n):
					r["open"] = int(r["open"]) + 1
					touched = true
					consumed_here = true
					break
			# ② 幕 / 旁支 / 结局（只看两侧都在的弧；被裁掉的只会消失，不会长）
			var got_beat := false
			var got_aside := false
			var got_end := false
			for n in after:
				if not before.has(n):
					continue
				var a: Array = after[n]
				var b: Array = before[n]
				if a[0] + a[1] > b[0] + b[1]:
					got_beat = true
				if a[2] > b[2]:
					got_aside = true
			# ★收场只能从 sync() 交回的 `fresh` 读，**不能**从前后快照差分读：
			#   `_close` 之后紧跟 `_trim()`，刚收场的弧可能在同一步里就被 MAX_CLOSED 裁掉、
			#   于是它在 `after` 里根本不存在 ⇒ 差分法会把这次收场记成"没发生"。
			#   （第一版就是这么写的，`pact/dissolved` 因此被记成 0 命中。）
			var got_sweep := false
			for arc in fresh:
				if String(arc["end"]) == "cold":
					got_sweep = true
				else:
					got_end = true
			if got_sweep:
				r["sweep"] = int(r["sweep"]) + 1
				touched = true
			if got_beat:
				r["beat"] = int(r["beat"]) + 1
				touched = true
				consumed_here = true
			if got_aside:
				r["aside"] = int(r["aside"]) + 1
				touched = true
				consumed_here = true
			if got_end:
				r["end"] = int(r["end"]) + 1
				touched = true
				consumed_here = true
			if consumed_here:
				r["hit"] = int(r["hit"]) + 1
			if not touched:
				r["none"] = int(r["none"]) + 1
			before = after

	# ── 输出 ────────────────────────────────────────────────────────────────
	print("=== W3 改前清点表 · seeds=%s · %d 天 · N=%d 居民 ===" % [str(seeds), days, Sim.agents.size()])
	print("弧文法里的类型（ARCS 静态读）：%s" % str(_grammar_types()))
	print("")
	var skip := _feed_skip()
	var prose := _prose_arms()
	print("播报侧（对象A · Main.gd）：FEED_SKIP=%s" % str(skip))
	print("播报侧有【专属中文成文】的类型（扫 _event_prose 的 match 臂）：%s" % str(prose))
	print("")
	print("%-20s %8s %5s | %6s %6s %6s %6s %6s %6s | %-12s %s" % [
		"事件类型", "条数", "seed", "open", "beat", "end", "aside", "sweep", "命中", "播报侧(A)", "故事侧(B)"])
	var keys: Array = cnt.keys()
	keys.sort()
	var used := 0
	var total_types := 0
	var used_events := 0
	var all_events := 0
	for k in keys:
		var r: Dictionary = role[k]
		var n := int(cnt[k])
		var base := String(String(k).split("/")[0])
		all_events += n
		total_types += 1
		var hit := int(r["hit"])
		var verdictB := "不进故事"
		if hit > 0:
			used += 1
			used_events += hit
			verdictB = "进故事 %d/%d=%.1f%%" % [hit, n, 100.0 * float(hit) / float(n)]
		var verdictA := "专属成文"
		if base in skip:
			verdictA = "FEED_SKIP 挡掉"
		elif not (base in prose):
			verdictA = "兜底/枚举名"
		print("%-20s %8d %5s | %6d %6d %6d %6d %6d %6d | %-12s %s" % [
			k, n, "%d" % (seedcov[k] as Dictionary).size(),
			int(r["open"]), int(r["beat"]), int(r["end"]), int(r["aside"]), int(r["sweep"]), hit,
			verdictA, verdictB])
	print("")
	print("覆盖率（类型口径 · 故事侧）：%d/%d = %.1f%%" % [used, total_types, 100.0 * float(used) / float(total_types)])
	print("覆盖率（事件条数口径 · 故事侧）：%d/%d = %.1f%%" % [used_events, all_events, 100.0 * float(used_events) / float(all_events)])
	get_tree().quit(0)

## 播报侧两列：常量走**执行**（preload 读 const），成文臂走**源码扫描**（`_event_prose` 是实例方法，
## 无 Main 节点不可调用）——两者口径不同，故在表头分别标注，不混成一个数。
func _feed_skip() -> Array:
	return (preload("res://scripts/Main.gd").FEED_SKIP as Array).duplicate()

func _prose_arms() -> Array:
	var f := FileAccess.open("res://scripts/Main.gd", FileAccess.READ)
	if f == null:
		return []
	var src := f.get_as_text()
	var i := src.find("func _event_prose")
	var j := src.find("func _salience", i)
	if i < 0 or j < 0:
		return []
	var out: Array = []
	for line in src.substr(i, j - i).split("\n"):
		var s := String(line).strip_edges()
		if not s.begins_with("\""):
			continue
		var q := s.find("\"", 1)
		if q > 1 and s.substr(q + 1, 1) == ":":
			out.append(s.substr(1, q - 1))
	out.sort()
	return out

## 细分键：Story 的文法在 note / witnesses 上分叉，所以清点也要在同一粒度上。
func _key(ev: Dictionary) -> String:
	var t := String(ev.get("type", ""))
	var note := String(ev.get("note", ""))
	if t == "pact":
		return "pact/" + ("formed" if note.begins_with("formed") else "dissolved")
	if t == "world":
		return "world/" + note
	if t == "produce":
		return "produce/" + ("witnessed" if not (ev.get("witnesses", []) as Array).is_empty() else "unseen")
	if t == "confront" or t == "apologize":
		return t + ("/mediated" if note.begins_with("mediated") else "")
	return t

func _grammar_types() -> Array:
	var s: Dictionary = {}
	for d in StoryScript.ARCS:
		for tt in ((d["open"] as Dictionary).get("type", []) as Array):
			s[tt] = true
		for bt in (d["beats"] as Array):
			for tt in ((bt["m"] as Dictionary).get("type", []) as Array):
				s[tt] = true
		for e in (d["ends"] as Array):
			for tt in ((e["m"] as Dictionary).get("type", []) as Array):
				s[tt] = true
		for tt in ((d["aside"] as Dictionary).get("type", []) as Array):
			s[tt] = true
	var out: Array = s.keys()
	out.sort()
	return out

## n -> [beats.size(), extra, aside, closed?1:0, end]
func _snapmap(st) -> Dictionary:
	var out: Dictionary = {}
	for arc in st.arcs:
		out[int(arc["n"])] = [(arc["beats"] as Array).size(), int(arc["extra"]), int(arc["aside"]),
			(1 if bool(arc["closed"]) else 0), String(arc["end"])]
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
