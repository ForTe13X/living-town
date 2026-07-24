extends SceneTree
## 定位饿穿：谁/哪个 need/在哪/在干嘛。用法：--script res://bench/find_starve.gd -- [seed] [N=spawn_count] [days]
## N>0 时克隆扩容到 N 个 agent（规模诊断：确认高 N 下到底哪个 need 触底 = 该扩哪种资源）。
const SimScript = preload("res://scripts/Sim.gd")
func _init():
	var a := OS.get_cmdline_user_args()
	var seed := int(a[0]) if a.size() > 0 else 4
	var N := int(a[1]) if a.size() > 1 else 0
	var days := int(a[2]) if a.size() > 2 else 60
	var S = SimScript.new(); get_root().add_child(S)
	S._load_data(); S.auto_run = false; S.backend = null
	if N > 0: S.spawn_count = N
	S.start_new(seed)
	var TPD := int(S.TICKS_PER_DAY)
	var reported := {}
	var by_need := {}       # need -> 饿穿 tick 实例数
	var by_agent := {}      # agent -> 首次饿穿的 need
	var doing := {}         # "need/okind" -> 计数（饿穿时在干嘛）
	var first_events := []
	for t in range(days * TPD):
		S.tick()
		for ag in S.agents:
			if String(ag["id"]) == "player": continue
			for nid in ag["needs"]:
				var v := float(ag["needs"][nid])
				if v <= 0.5:
					by_need[nid] = int(by_need.get(nid, 0)) + 1
					if not by_agent.has(ag["id"]): by_agent[ag["id"]] = nid
					var opt = ag.get("option")
					var okind = (String(opt.get("kind", "?")) + "/" + String(opt.get("action", ""))) if opt is Dictionary else "idle/none"
					doing["%s|%s" % [nid, okind]] = int(doing.get("%s|%s" % [nid, okind], 0)) + 1
					var kk := "%s:%s" % [ag["id"], nid]
					if not reported.has(kk) or S.tick_no - int(reported[kk]) > 30:
						reported[kk] = S.tick_no
						if first_events.size() < 12:
							first_events.append("STARVE tick=%d day=%d %s need=%s=%.2f pos=%s doing=%s" % [
								S.tick_no, S.tick_no / TPD + 1, S._name(ag), nid, v, str(ag["pos"]), okind])
	print("=== 饿穿诊断  seed=%d N=%d(agents=%d) days=%d ===" % [seed, N, S.agents.size(), days])
	for e in first_events: print("  ", e)
	print("  按 need 汇总(饿穿 tick 实例数): ", by_need)
	print("  饿穿的 agent 数: %d / %d" % [by_agent.size(), S.agents.size()])
	# 饿穿时在干嘛 top5
	var items := doing.keys(); items.sort_custom(func(x, y): return int(doing[x]) > int(doing[y]))
	print("  饿穿时在干嘛(need|option top): ")
	for i in mini(6, items.size()): print("    %s : %d" % [items[i], int(doing[items[i]])])
	quit()
