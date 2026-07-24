extends SceneTree
## Phase-D 闭环因果 A/B：在不同【配置】下跑真仿真，量玩家可感的下游产出。config 只改 CHARACTER 门/BLUNT/SURVIVAL_GATE，
## 其余一律相同 → 差异纯归因于 CHARACTER 政策。指标：need_floor（无饿穿）/社交吞吐/冲突完成率/悬空弧/事件多样性/戏剧节拍。
## 用法：godot --headless --path game --script res://bench/ab_metrics.gd -- --char on|off --gate 30 --blunt new|old --seeds 1-12 --days 45
const SimScript = preload("res://scripts/Sim.gd")

func _arg(name: String, dflt: String) -> String:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == name and i + 1 < a.size(): return a[i + 1]
	return dflt

func _seeds(s: String) -> Array:
	if "-" in s:
		var p := s.split("-"); var out := []
		for v in range(int(p[0]), int(p[1]) + 1): out.append(v)
		return out
	return [int(s)]

func _mean(a: Array) -> float:
	if a.is_empty(): return 0.0
	var s := 0.0
	for v in a: s += float(v)
	return s / a.size()

func _init():
	var char_on := _arg("--char", "on") == "on"
	var gate := float(_arg("--gate", "30"))
	var blunt := _arg("--blunt", "new")
	var fade := _arg("--fade", "on") == "on"
	var seeds := _seeds(_arg("--seeds", "1-12"))
	var days := int(_arg("--days", "45"))
	var acc := {}
	for seed in seeds:
		var S = SimScript.new(); get_root().add_child(S)
		S._load_data(); S.auto_run = false; S.backend = null
		S.SURVIVAL_GATE = gate                         # 配置（在 start_new 前设 → 播种+决策都按此档）
		if not char_on:                                # CHARACTER 门全关 → 退回 logic 地板（恒对质/泄密/合围/串谋）
			S.CHARACTER_DEFER = false; S.DRAMA_GOSSIP_LEAK = false
			S.FACTION_MOB_DEFER = false; S.FACTION_ENDORSE_DEFER = false
		# 显式两档（不靠 Sim 默认——默认现已回退为仅耿直，否则 new==old、C/D 档无法复现）：
		S.BLUNT_TRAITS = ["耿直"] if blunt == "old" else ["耿直", "莽撞", "爽快"]
		S.DRAMA_FORGIVE_FADE = fade                     # 宽恕归档开关
		S.start_new(seed)
		var TPD := int(S.TICKS_PER_DAY)
		var need_floor := 100.0
		for t in range(days * TPD):
			S.tick()
			for ag in S.agents:
				for nid in ag["needs"]:
					need_floor = minf(need_floor, float(ag["needs"][nid]))
		# 事件类型直方图 → 多样性/戏剧节拍/社交吞吐
		var types := {}
		for e in S.event_log:
			var ty := String(e.get("type", ""))
			types[ty] = int(types.get(ty, 0)) + 1
		var total_ev: int = S.event_log.size()
		var ent := 0.0
		for ty in types:
			var pr := float(types[ty]) / float(maxi(1, total_ev))
			if pr > 0.0: ent -= pr * (log(pr) / log(2.0))
		# 冲突完成率 / 悬空弧
		var repaired := 0; var faded := 0
		var n_sev := 0; var rep_sev := 0; var n_small := 0; var rep_small := 0
		for c in S.conflicts:
			var st := String(c.get("status", ""))
			var esc := int(c.get("escalations", 0)) > 0
			var eligible := esc or float(c.get("severity", 0.0)) >= float(S.DRAMA_ERUPT_SEV)  # 够戏（会被导演引爆）
			var done := st == "repaired" or st == "faded"    # 已了结=对质和解 或 被时间原谅归档
			if st == "repaired": repaired += 1
			if st == "faded": faded += 1
			if eligible:
				n_sev += 1
				if done: rep_sev += 1
			else:
				n_small += 1
				if done: rep_small += 1
		var nconf: int = S.conflicts.size()
		var drama := int(types.get("confront", 0)) + int(types.get("betray", 0)) + int(types.get("rally_oust", 0))
		var rec := {
			"need_floor": need_floor, "starved": 1.0 if need_floor <= 0.5 else 0.0,
			"events_per_day": float(total_ev) / float(days), "event_types": types.size(), "entropy": ent,
			"conflicts": nconf, "completion": (float(repaired + faded) / nconf) if nconf > 0 else 1.0,  # 对质和解+时间原谅
			"comp_severe": (float(rep_sev) / n_sev) if n_sev > 0 else 1.0,   # 够戏的（该被引爆结清）——诊断 DRAMA 有没有干活
			"comp_small": (float(rep_small) / n_small) if n_small > 0 else 1.0,  # 小怨（该淡着/被原谅，保 #15）
			"n_severe": n_sev, "n_small": n_small,
			"faded_pct": (float(faded) / nconf) if nconf > 0 else 0.0,        # 被时间原谅归档的占比
			"dangling": float(nconf - repaired - faded),                     # 真·还活着的悬空怨
			"drama_per_day": float(drama) / float(days),
			"confront": int(types.get("confront", 0)), "betray": int(types.get("betray", 0)),
			"rally_oust": int(types.get("rally_oust", 0)), "apologize": int(types.get("apologize", 0)),
		}
		for k in rec:
			if not acc.has(k): acc[k] = []
			acc[k].append(rec[k])
		get_root().remove_child(S); S.free()
	var out := {"char": "on" if char_on else "off", "gate": gate, "blunt": blunt, "n_seeds": seeds.size(), "days": days}
	for k in acc: out[k] = snappedf(_mean(acc[k]), 0.001)
	print("ABMETRIC " + JSON.stringify(out))
	quit()
