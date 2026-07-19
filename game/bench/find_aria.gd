extends SceneTree
## P3 Tier-B 验证：跑一局，追踪阿丽的跨平面生活——她进出咖啡馆的 (space,floor) 变化 + 用了哪些对象。
## 期望：她在 cafe/2f(睡) / cafe/1f(看摊闲聊) / town(吃饭洗澡) 之间来回，需求恒 >0.5（不饿穿）。
## 用法：godot --headless --path game --script res://bench/find_aria.gd -- [seed] [days]
const SimScript = preload("res://scripts/Sim.gd")
func _init():
	var seed := 1
	var days := 6
	var ua := OS.get_cmdline_user_args()
	if ua.size() > 0: seed = int(ua[0])
	if ua.size() > 1: days = int(ua[1])
	var S = SimScript.new(); get_root().add_child(S)
	S._load_data(); S.auto_run = false; S.backend = null; S.start_new(seed)
	var TPD := int(S.TICKS_PER_DAY)
	var planes := {}          # 访问过的平面计数
	var transitions := 0
	var last_plane := ""
	var min_need := 100.0
	var used := {}            # 用过的对象
	var aria: Dictionary = S.get_agent("aria")
	print("seed %d · 阿丽起始平面 = %s/%s pos=%s" % [seed, aria.get("space"), aria.get("floor"), str(aria.get("pos"))])
	for t in range(days * TPD):
		S.tick()
		aria = S.get_agent("aria")
		var pl := "%s/%s" % [aria.get("space"), aria.get("floor")]
		planes[pl] = int(planes.get(pl, 0)) + 1
		if pl != last_plane:
			transitions += 1
			last_plane = pl
		var mn := 100.0
		for nid in aria["needs"]:
			mn = minf(mn, float(aria["needs"][nid]))
		min_need = minf(min_need, mn)
		var opt = aria.get("option")
		if opt != null and String(opt.get("kind","")) == "object":
			used[String(opt.get("target",""))] = int(used.get(String(opt.get("target","")),0)) + 1
	print("  跨平面切换次数: %d" % transitions)
	print("  各平面停留 tick: %s" % str(planes))
	print("  用过的对象(含平面): %s" % str(used))
	print("  阿丽全程最低需求: %.1f  %s" % [min_need, "✅ 不饿穿" if min_need > 0.5 else "❌ 饿穿!"])
	# 采样：找几个阿丽在咖啡馆各层的定格 tick（供 --shot 眼验）
	S.start_new(seed)
	var t1f := -1; var t2f := -1; var t1f_mid := -1
	for t in range(days * TPD):
		S.tick()
		var a2: Dictionary = S.get_agent("aria")
		if String(a2.get("space")) == "cafe":
			if String(a2.get("floor")) == "1f" and t1f < 0: t1f = S.tick_no
			if String(a2.get("floor")) == "2f" and t2f < 0 and S.tick_no > 30: t2f = S.tick_no
			if String(a2.get("floor")) == "1f" and t1f_mid < 0 and S.tick_no > 700: t1f_mid = S.tick_no
	print("  眼验 tick：cafe/1f=%d  cafe/2f=%d  cafe/1f(中段>700)=%d" % [t1f, t2f, t1f_mid])
	quit()
