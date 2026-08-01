extends Node
## story_landable.gd — Y3 的**改前清点第二遍**：不是"这种事件有几条"，而是
## **"这种事件有几条【落在一段已经开着的弧上】"**。
##
## ★为什么必须换这个分母（docs/41 §5「注意分母」）：
##   W3 的清点表按**原始条数**排值钱程度，于是 `greet` 以 5816 条排第一。
##   但一条事件只有在**它的有向对上已经有一段弧在跑**的时候，才可能被写成一幕
##   —— 否则它要么开一条新弧（那是另一个决定，且面板预算扛不住），要么什么都不发生。
##   ⇒ **"能落地的上界"才是加一幕能买到的东西**，原始条数是一个虚高得离谱的数。
##
## 量的是哪个对象：**真的那一份 `Story.gd`**（preload），用它自己的 `_pairs` 与 `_open`。
##   不重新实现匹配逻辑；把事件逐条喂进去，在**折叠这条事件之前**问一句
##   "此刻 `_open` 里有没有键能接住它"。
##
## 用法：godot --headless --path <iso>/game res://scenes/story_landable.tscn -- [--seeds 1-12] [--days 60]

const StoryScript = preload("res://scripts/Story.gd")

func _ready() -> void:
	var seeds := _parse_seeds(_arg("--seeds", "1-12"))
	var days := int(_arg("--days", "60"))
	var total := days * int(Sim.TICKS_PER_DAY)

	var cnt: Dictionary = {}          # 类型 → 条数
	var land: Dictionary = {}         # 类型 → 落得上（任意 def/任意取法/任意方向）的条数
	var land_by: Dictionary = {}      # 类型 → {"<def>/<mode>/<dir>": n}
	var pairable: Dictionary = {}     # 类型 → 至少有一个合法有向对的条数（= 结构上能不能系在两个人身上）
	var seedcov: Dictionary = {}

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
		for ev in log:
			var k := _key(ev)
			cnt[k] = int(cnt.get(k, 0)) + 1
			if not seedcov.has(k):
				seedcov[k] = {}
			(seedcov[k] as Dictionary)[sd] = true
			if not land.has(k):
				land[k] = 0
				pairable[k] = 0
				land_by[k] = {}

			# ── 在折叠这条事件【之前】问：_open 里有没有键能接住它 ────────────
			var any_pair := false
			var hit := false
			for mode in [StoryScript.PAIR_TARGET, StoryScript.PAIR_SUBJECT, StoryScript.PAIR_TS, StoryScript.PAIR_WIT]:
				var ps: Array = st._pairs(ev, mode)
				if not ps.is_empty():
					any_pair = true
				for p in ps:
					var fwd: String = String(p[0]) + StoryScript.KEY_SEP + String(p[1])
					var rev: String = String(p[1]) + StoryScript.KEY_SEP + String(p[0])
					for d in StoryScript.ARCS:
						var did := String(d["id"])
						for dir in ["fwd", "rev"]:
							var key := did + StoryScript.ARC_SEP + (fwd if dir == "fwd" else rev)
							if st._open.has(key):
								hit = true
								var bk := "%s/%s/%s" % [did, mode, dir]
								(land_by[k] as Dictionary)[bk] = int((land_by[k] as Dictionary).get(bk, 0)) + 1
			if any_pair:
				pairable[k] = int(pairable[k]) + 1
			if hit:
				land[k] = int(land[k]) + 1

			acc.append(ev)
			st.sync(acc)

	# ── 输出 ────────────────────────────────────────────────────────────────
	print("=== Y3 可落地上界 · seeds=%s · %d 天 · N=%d 居民 ===" % [str(seeds), days, Sim.agents.size()])
	print("%-20s %8s %5s %9s %9s %7s  %s" % ["事件类型", "条数", "seed", "有向对", "落得上", "落地率", "落在哪条弧上（前 4）"])
	var keys: Array = cnt.keys()
	keys.sort_custom(func(x, y): return int(land.get(x, 0)) > int(land.get(y, 0)))
	for k in keys:
		var n := int(cnt[k])
		var lb: Dictionary = land_by[k]
		var bks: Array = lb.keys()
		bks.sort_custom(func(x, y): return int(lb[x]) > int(lb[y]))
		var parts: Array = []
		for i in bks.size():
			parts.append("%s=%d" % [bks[i], int(lb[bks[i]])])
		print("%-20s %8d %5d %9d %9d %6.1f%%  %s" % [
			k, n, (seedcov[k] as Dictionary).size(), int(pairable[k]), int(land[k]),
			100.0 * float(land[k]) / float(n), "  ".join(PackedStringArray(parts))])

	# ── 幕位余量：加一幕之前必须知道 MAX_BEATS 还剩多少坑 ──────────────────────
	## ★这是"加 greet 会不会把有信息量的幕挤出去"唯一能先验回答的地方：
	##   一条弧的幕位只有 MAX_BEATS=6 个，第 7 幕起只进 `extra`（纯计数、**没有出处**、审计管不着）。
	##   若今天大多数弧的幕位已经满了，任何新幕都是在**挤掉**别的幕，不是在增加信息。
	print("")
	print("=== 幕位余量（同一网格 · 逐弧统计）===")
	var hist: Dictionary = {}
	var full := 0
	var withextra := 0
	var tot := 0
	for sd in seeds:
		Sim.backend = null
		Sim.record_decisions = false
		Sim.auto_run = false
		Sim.start_new(sd)
		for t in range(total):
			Sim.tick()
		var st2 := StoryScript.new()
		st2.recompute(Sim.event_log)
		for arc in st2.arcs:
			var nb: int = (arc["beats"] as Array).size()
			hist[nb] = int(hist.get(nb, 0)) + 1
			tot += 1
			if nb >= StoryScript.MAX_BEATS:
				full += 1
			if int(arc["extra"]) > 0:
				withextra += 1
	var hk: Array = hist.keys()
	hk.sort()
	for k2 in hk:
		print("  幕数 %d：%d 条弧" % [int(k2), int(hist[k2])])
	print("  合计 %d 条弧（**仅留存的**，被 MAX_CLOSED 裁掉的不在内）· 幕位已满(=%d) %d 条 (%.1f%%) · 已有 extra 的 %d 条 (%.1f%%)" % [
		tot, StoryScript.MAX_BEATS, full, 100.0 * float(full) / float(maxi(1, tot)),
		withextra, 100.0 * float(withextra) / float(maxi(1, tot))])
	get_tree().quit(0)

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
