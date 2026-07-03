extends Node
## bench/BackendBench.gd — S5 后端矩阵 + L2 gap 量化（scene 模式，autoload Sim/AIBackend 可用）。
## 用法：godot [--headless] --path . res://bench/BackendBench.tscn -- --backend logic|mock|slm|llm [--gpu] [--seeds 1-4] [--days N] [--endpoint URL]
## 度量：合法率(landed/(landed+bad_parse+timeout)) + 截止线命中率((landed+bad_parse)/fired) + 宏观指标 PI/cascade/Gini + 采样真台词。
## logic/mock 容器跑（快、验宏观不变性）；slm 本机原生 --gpu 跑（量真模型合法率+口吻，days 小即可）。
## 后端宏观矩阵需此 scene（AIBackend.decide 引用全局 Sim，--script 跑不了）。

const M = preload("res://bench/Metrics.gd")

func _ready() -> void:
	var backend := "logic"
	var seeds := "1-4"
	var days := 0
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--backend" and i + 1 < args.size(): backend = args[i + 1]
		elif args[i] == "--seeds" and i + 1 < args.size(): seeds = args[i + 1]
		elif args[i] == "--days" and i + 1 < args.size(): days = int(args[i + 1])
		elif args[i] == "--endpoint" and i + 1 < args.size(): AIBackend.endpoint = args[i + 1]
		elif args[i] == "--gpu": AIBackend.slm_use_gpu = true
		elif args[i] == "--tier" and i + 1 < args.size(): AIBackend.tier = args[i + 1]   # 强制算力档(测节流)
		elif args[i] == "--agents" and i + 1 < args.size(): Sim.spawn_count = int(args[i + 1])  # 扩 N
		elif args[i] == "--budget" and i + 1 < args.size(): AIBackend.llm_budget = int(args[i + 1])  # L5 全镇令牌桶
		elif args[i] == "--aging" and i + 1 < args.size(): AIBackend.llm_aging = args[i + 1] != "off"  # L5 老化优先门(默认 on)
	var is_async := backend == "slm" or backend == "llm"
	if days <= 0:
		days = 8 if is_async else 40       # 异步真模型 days 小（每决策秒级）；确定性后端可大网格
	print("=== BackendBench  backend=%s seeds=%s days=%d gpu=%s ===" % [backend, seeds, days, str(AIBackend.slm_use_gpu)])
	await _run(backend, _parse_seeds(seeds), days, is_async)
	get_tree().quit(0)

func _run(backend: String, seed_list: Array, days: int, is_async: bool) -> void:
	AIBackend.backend = backend
	var pis: Array = []
	var casc: Array = []
	var ginis: Array = []
	var fired := 0
	var landed := 0
	var bad := 0
	var timeout := 0
	var vginis: Array = []   # L5 发声公平：per-agent 触发次数的 Gini（越低越均）
	var vzeros: Array = []   # L5 从未发声的 agent 数（饿死之声）
	var samples: Array = []
	var seen := {}
	for sd in seed_list:
		Sim.start_new(sd)
		Sim.backend = AIBackend
		Sim.auto_run = false
		AIBackend.reset_stats()
		var total: int = days * int(Sim.TICKS_PER_DAY)
		for t in range(total):
			Sim.tick()
			if is_async:
				await get_tree().create_timer(0.03).timeout   # 给 HTTP/worker 回调真时落地
			# 采样真台词（去重，封顶）
			if samples.size() < 12:
				for ag in Sim.agents:
					var ls := String(ag.get("last_say", "")).strip_edges()
					var key := String(ag["id"]) + ":" + ls
					if ls != "" and not seen.has(key):
						seen[key] = true
						samples.append("%s「%s」" % [Sim._name(ag), ls.substr(0, 40)])
		pis.append(M.polarization(Sim))
		casc.append(M.cascade_max(Sim))
		ginis.append(M.gini_acceptance(Sim))
		if int(AIBackend.stats["fired"]) > 0:            # L5：本 seed 发声分布（在 reset 前抓）
			var vf := _voice_fair(AIBackend._fire_count, Sim.agents)
			vginis.append(vf["gini"]); vzeros.append(vf["zeros"])
		fired += int(AIBackend.stats["fired"])
		landed += int(AIBackend.stats["landed"])
		bad += int(AIBackend.stats["bad_parse"])
		timeout += int(AIBackend.stats["timeout"])
		print("[BB] " + JSON.stringify({"backend": backend, "seed": sd, "fired": int(AIBackend.stats["fired"]),
			"landed": int(AIBackend.stats["landed"]), "bad": int(AIBackend.stats["bad_parse"]), "timeout": int(AIBackend.stats["timeout"]),
			"PI": snappedf(M.polarization(Sim), 0.001), "cascade": M.cascade_max(Sim), "Gini": snappedf(M.gini_acceptance(Sim), 0.001)}))

	var resolved := landed + bad + timeout
	print("\n— 后端 %s 汇总（%d seed × %d 天）—" % [backend, seed_list.size(), days])
	print("  宏观指标: PI %s | cascade %s | Gini %s" % [_stat(pis), _stat(casc), _stat(ginis)])
	if fired > 0:
		print("  模型决策: fired=%d landed=%d bad_parse=%d timeout=%d" % [fired, landed, bad, timeout])
		print("  合法率 = %.1f%% (landed/resolved)   截止线命中率 = %.1f%% ((landed+bad)/fired)" % [
			100.0 * float(landed) / float(maxi(1, resolved)), 100.0 * float(landed + bad) / float(fired)])
		if not vginis.is_empty():
			print("  发声公平(L5 aging=%s): Gini %s | 从未发声 agent 数 %s (越低越均/越少饿死)" % [str(AIBackend.llm_aging), _stat(vginis), _stat(vzeros)])
	else:
		print("  模型决策: 0（logic 后端无模型调用，作宏观基线）")
	if not samples.is_empty():
		print("  台词采样:")
		for s in samples:
			print("    · " + s)

## L5 发声公平：per-agent 触发次数的 Gini + 从未发声的 agent 数（覆盖全体 agent，缺席者计 0）。
func _voice_fair(fire_count: Dictionary, agents: Array) -> Dictionary:
	var vals: Array = []
	var zeros := 0
	for ag in agents:
		var c := int(fire_count.get(String(ag["id"]), 0))
		vals.append(c)
		if c == 0: zeros += 1
	var n := vals.size()
	var sum := 0.0
	for v in vals: sum += float(v)
	var gini := 0.0
	if sum > 0.0 and n > 0:
		var diff := 0.0
		for a in vals:
			for b in vals:
				diff += absf(float(a) - float(b))
		gini = diff / (2.0 * float(n) * sum)
	return {"gini": gini, "zeros": zeros}

func _stat(a: Array) -> String:
	if a.is_empty(): return "—"
	var mn := INF
	var mx := -INF
	var s := 0.0
	for x in a:
		var v := float(x)
		mn = minf(mn, v); mx = maxf(mx, v); s += v
	return "均%.3f[%.3f,%.3f]" % [s / float(a.size()), mn, mx]

func _parse_seeds(spec: String) -> Array:
	var out: Array = []
	if "-" in spec:
		var ab := spec.split("-")
		for s in range(int(ab[0]), int(ab[1]) + 1): out.append(s)
	elif "," in spec:
		for s in spec.split(","): out.append(int(s))
	else: out.append(int(spec))
	return out
