extends Node
## bench/DistillDump.gd — L3 蒸馏第1步：跑真 sim，导出「真实决策上下文」(sys+user+候选) 到 JSONL。
## 用真引擎状态(避免分布漂移)；teacher(8B) 之后离线给 label。scene 模式(autoload 可用)。
## 用法：godot --headless --path . res://scenes/distill_dump.tscn -- [--n 200] [--seed 20260626] [--out res://bench/distill_contexts.jsonl]

func _ready() -> void:
	var n := 200
	var seed := 20260626
	var out := "res://bench/distill_contexts.jsonl"
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--n" and i + 1 < args.size(): n = int(args[i + 1])
		elif args[i] == "--seed" and i + 1 < args.size(): seed = int(args[i + 1])
		elif args[i] == "--out" and i + 1 < args.size(): out = args[i + 1]
	Sim.start_new(seed)
	Sim.backend = null   # logic 驱动推进世界；我们只在每个决策点旁观抓上下文
	Sim.auto_run = false
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		print("无法写 ", out); get_tree().quit(1); return
	var dumped := 0
	var seen := {}        # 去重 key（人设+候选集+大致时段）避免大量近重样本
	var t := 0
	while dumped < n and t < 40000:
		t += 1
		Sim.tick()
		for ag in Sim.agents:
			if dumped >= n: break
			var cands := Sim.agent_candidates(ag)
			if cands.size() < 2: continue          # 无得选的跳过
			var ctx := Sim._context(ag)
			# 去重：同人设+同候选标签集+同时段桶 → 只留一条
			var labels := []
			for c in cands:
				var lab := String(c.get("action", ""))
				if String(c.get("kind", "")) == "social":
					lab += "→" + Sim._name(Sim.get_agent(String(c.get("partner", ""))))
				labels.append(lab)
			var key := String(ag["id"]) + "|" + "/".join(labels) + "|" + str(int(float(ctx.get("tod", 0.0)) * 4))
			if seen.has(key): continue
			seen[key] = true
			f.store_line(JSON.stringify({
				"sys": AIBackend._system_prompt(),
				"user": AIBackend.build_prompt(ag, cands, ctx),
				"cands": labels, "n": cands.size(), "agent": Sim._name(ag),
			}))
			dumped += 1
	f.close()
	print("导出 %d 条决策上下文 → %s" % [dumped, out])
	get_tree().quit(0)
