extends SceneTree
## 定位饿穿：谁/哪个 need/在哪/在干嘛。用法：--script res://bench/find_starve.gd -- [seed] [N=spawn_count] [days]
## N>0 时克隆扩容到 N 个 agent（规模诊断：确认高 N 下到底哪个 need 触底 = 该扩哪种资源）。
##
## ⚠ **M1 修的一个读数陷阱**：本探针原先只打 `S._name(ag)`，而 `_name` 返回的是 `persona.name`
##   （Sim.gd:3760-3763），克隆 `npc_<i>` 是**照抄某个在任居民的 persona**建出来的（Sim.gd:723）
##   ⇒ **一个没有岗位的克隆会顶着"阿本"这种在任木匠的名字打印出来**。
##   实测 N=20 seed 8：全部 2867 个触底 need·tick 属于 `npc_13`，而本探针当时印的是"阿本"。
##   docs/54 §六 整整一节在撤回"社会性触底的人是被缺货连累的责任岗位"这个假设——
##   **而唯一能查它的工具正在把无岗位克隆显示成岗位持有人**。⇒ 名字后面必须跟 id。
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
							first_events.append("STARVE tick=%d day=%d %s(%s%s) need=%s=%.2f pos=%s doing=%s" % [
								S.tick_no, S.tick_no / TPD + 1, S._name(ag), ag["id"],
								"" if S._job_of(String(ag["id"])).is_empty() else "·" + String(S._job_of(String(ag["id"])).get("title", "")),
								nid, v, str(ag["pos"]), okind])
	print("=== 饿穿诊断  seed=%d N=%d(agents=%d) days=%d ===" % [seed, N, S.agents.size(), days])
	for e in first_events: print("  ", e)
	print("  按 need 汇总(饿穿 tick 实例数): ", by_need)
	print("  饿穿的 agent 数: %d / %d  → %s（id→首次触底的 need；克隆 npc_* 顶着别人的名字，见抬头）"
		% [by_agent.size(), S.agents.size(), JSON.stringify(by_agent)])
	# 饿穿时在干嘛 top5
	var items := doing.keys(); items.sort_custom(func(x, y): return int(doing[x]) > int(doing[y]))
	print("  饿穿时在干嘛(need|option top): ")
	for i in mini(6, items.size()): print("    %s : %d" % [items[i], int(doing[items[i]])])
	quit()
