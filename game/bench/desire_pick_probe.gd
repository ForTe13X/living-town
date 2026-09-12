extends SceneTree
## 诊断：欲望对象【何时】选定、选定后是否还动过。回答"拥挤项为何不起作用"（docs/187 §七·九）。
## 用法：godot --headless --path game --script res://bench/desire_pick_probe.gd -- [--seeds 1-4] [--days 20] [--n 12]
const SimScript = preload("res://scripts/Sim.gd")

func _arg(name: String, dflt: String) -> String:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == name and i + 1 < a.size(): return a[i + 1]
	return dflt

func _init() -> void:
	var p := _arg("--seeds", "1-4").split("-")
	var days := int(_arg("--days", "20"))
	var n := int(_arg("--n", "12"))
	for seed in range(int(p[0]), int(p[p.size() - 1]) + 1):
		var S = SimScript.new(); get_root().add_child(S)
		S._load_data(); S.auto_run = false; S.backend = null
		if n > 12: S.spawn_count = n
		S.desire_cfg = {"enabled": true, "gain": 0.15, "mimetic_cap": 5.0, "bonus_k": 8.0, "rho": 0.6, "r_max": 3, "crowd_k": 0.5,
			"min_seen": int(_arg("--minseen", "8")), "switch_margin": float(_arg("--margin", "0.5"))}
		S.start_new(seed)
		var picks := 0
		var pick_ticks: Array = []
		var seen_at_pick: Array = []
		var prev := {}
		for t in range(days * int(S.TICKS_PER_DAY)):
			S.tick()
			for ag in S.agents:
				var d = ag.get("desire")
				if d == null: continue
				var tg := String(d["kind"]) + ":" + String(d["target"])
				if String(d["kind"]) != "" and prev.get(ag["id"], "") != tg:
					picks += 1
					pick_ticks.append(S.tick_no)
					var actors := {}
					for s in d["seen"]:
						if String(s[3]) == String(d["target"]): actors[s[2]] = true
					seen_at_pick.append("%d/%d" % [(d["seen"] as Array).size(), actors.size()])
				prev[ag["id"]] = tg
		pick_ticks.sort()
		var first_day := pick_ticks.filter(func(x): return x <= int(S.TICKS_PER_DAY)).size()
		print("seed %d N=%d: picks=%d  within_day1=%d  last_pick_tick=%d  median_pick_tick=%d" % [
			seed, S.agents.size(), picks, first_day, pick_ticks.back() if not pick_ticks.is_empty() else -1,
			pick_ticks[pick_ticks.size() / 2] if not pick_ticks.is_empty() else -1])
		print("   evidence at pick (seen_events/distinct_courters_of_target): %s" % ", ".join(PackedStringArray(seen_at_pick.slice(0, 14))))
		get_root().remove_child(S); S.free()
	quit()
