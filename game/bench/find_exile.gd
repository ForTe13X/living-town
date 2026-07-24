extends SceneTree
## #15 涌现放逐 诊断：跑一个 seed（可设 --exile-damp），复算 #15 明细——最坏名声者、其接受率 rw、镇均、
## actives 数（样本量），并按【对手】拆解最坏者的社交发起（accepted/proposed + 对手对他的 standing + 对手家在哪），
## 检验"被少数友好/在场者过度接受"假说 vs 纯小样本噪声。用法：--script res://bench/find_exile.gd -- [seed] [damp] [days]
const SimScript = preload("res://scripts/Sim.gd")

func _init():
	var seed := 17; var damp := 0.0; var days := 60
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: seed = int(a[0])
	if a.size() > 1: damp = float(a[1])
	if a.size() > 2: days = int(a[2])
	var S = SimScript.new(); get_root().add_child(S)
	S._load_data(); S.auto_run = false; S.backend = null
	S.EXILE_NEED_DAMP = damp
	S.start_new(seed)
	for t in range(days * int(S.TICKS_PER_DAY)): S.tick()
	# perceived + actives + worst（镜像 Invariants）
	var perceived := {}; var prop := {}; var acc := {}
	for ag in S.agents:
		var s := 0.0; var n := 0
		for b in S.agents:
			if b["id"] != ag["id"]:
				s += float(S._rel(b, ag["id"])["standing"]); n += 1
		perceived[ag["id"]] = s / max(1, n); prop[ag["id"]] = 0; acc[ag["id"]] = 0
	for e in S.event_log:
		if String(e["type"]) in ["greet","give","gossip","invite","gossip_rep"]:
			prop[e["actor"]] = int(prop[e["actor"]]) + 1
			if bool(e["accepted"]): acc[e["actor"]] = int(acc[e["actor"]]) + 1
	var actives := []
	for ag in S.agents:
		if int(prop[ag["id"]]) >= 5: actives.append(ag["id"])
	actives.sort_custom(func(x,y): return float(perceived[x]) < float(perceived[y]))
	print("== #15 诊断  seed %d  damp %.1f  days %d ==" % [seed, damp, days])
	if actives.size() < 2:
		print("  actives<2, #15 n/a"); S.free(); quit(); return
	var town := 0.0
	for id in actives: town += float(acc[id]) / float(prop[id])
	town /= float(actives.size())
	var worst: String = actives[0]
	var rw := float(acc[worst]) / float(prop[worst])
	var fails := float(perceived[worst]) <= -0.8 and rw > town + 0.08
	print("  actives=%d (样本量)  最坏=%s perceived=%.2f" % [actives.size(), S._name(S.get_agent(worst)), perceived[worst]])
	print("  rw(最坏接受率)=%.3f  镇均=%.3f  门=镇均+0.08=%.3f  → #15 %s (超出 %.3f)" % [rw, town, town+0.08, "❌FAIL" if fails else "✅ok", rw-(town+0.08)])
	# 按对手拆解最坏者的发起
	var by := {}
	for e in S.event_log:
		if String(e["actor"]) == worst and String(e["type"]) in ["greet","give","gossip","invite","gossip_rep"]:
			var tg := String(e["target"])
			if not by.has(tg): by[tg] = [0,0]
			by[tg][0] += 1
			if bool(e["accepted"]): by[tg][1] += 1
	print("  最坏者对各对手的发起（accepted/proposed · 对手→最坏standing · 对手家）：")
	var wag := S.get_agent(worst)
	for tg in by:
		var tgag := S.get_agent(tg)
		var stnd := float(S._rel(tgag, worst)["standing"])
		var home := String(tgag.get("home_space","town"))
		print("    %-6s %d/%d  st=%+.2f  home=%s" % [S._name(tgag), by[tg][1], by[tg][0], stnd, home])
	S.free(); quit()
