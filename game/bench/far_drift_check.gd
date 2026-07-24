extends SceneTree
## 行为验证：远端 agent 是否随作息迁移（夜→靠近家、昼→靠近广场），而非冻住。对比 drift 前应=冻住(距离不变)。
## 用法：--script res://bench/far_drift_check.gd -- [N] [days]
const SimScript = preload("res://scripts/Sim.gd")

func _init():
	var a := OS.get_cmdline_user_args()
	var N := int(a[0]) if a.size() > 0 else 48
	var days := int(a[1]) if a.size() > 1 else 3
	var S = SimScript.new(); get_root().add_child(S)
	S._load_data(); S.auto_run = false; S.backend = null
	S.spawn_count = N; S.decide_period = 4; S.lod_near_radius = 8; S.lod_near_cap = 12; S.lod_aggregate = true
	S.lod_focus = Vector2i(1, 1)   # 焦点放角落 → 全镇几乎都是 far（隔离观察 far 迁移，不被 near 全量跑干扰）
	S.start_new(1)
	var TPD := int(S.TICKS_PER_DAY)
	var plaza := S._area_centroid("plaza")
	# 采样：每天深夜(tod≈0.1)与正午(tod≈0.5) 的 far agent 平均到-家 / 到-广场 曼哈顿距离
	var samples := {}   # "day_phase" -> [sum_home, sum_plaza, n]
	for t in range(days * TPD):
		S.tick()
		var tod := float(S.tick_no % TPD) / float(TPD)
		var key := ""
		if abs(tod - 0.10) < 0.005: key = "night"
		elif abs(tod - 0.50) < 0.005: key = "noon"
		if key != "":
			var sh := 0.0; var sp := 0.0; var n := 0
			for ag in S.agents:
				if String(ag.get("space","town")) != "town": continue
				var p: Vector2i = ag["pos"]; var h: Vector2i = ag["home"]
				sh += absi(p.x-h.x)+absi(p.y-h.y); sp += absi(p.x-plaza.x)+absi(p.y-plaza.y); n += 1
			if not samples.has(key): samples[key] = [0.0,0.0,0]
			samples[key][0]+=sh; samples[key][1]+=sp; samples[key][2]+=n
	print("=== far-drift 行为验证  N=%d(agents=%d) days=%d  plaza=%s ===" % [N, S.agents.size(), days, str(plaza)])
	for key in samples:
		var s = samples[key]; var n = maxf(1.0, s[2])
		print("  %-6s: 平均到家距离=%.1f  平均到广场距离=%.1f" % [key, s[0]/n, s[1]/n])
	print("  预期：night 到家距离应【小】(回家)；noon 到广场距离应【小】(出门聚广场)。drift 前=冻住则两者都不随时段变。")
	quit()
