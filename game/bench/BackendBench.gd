extends Node
## bench/BackendBench.gd — S5 后端矩阵 + L2 gap 量化（scene 模式，autoload Sim/AIBackend 可用）。
## 用法：godot [--headless] --path . res://bench/BackendBench.tscn -- --backend logic|mock|slm|llm [--gpu] [--seeds 1-4] [--days N] [--endpoint URL]
## 度量：合法率(landed/(landed+bad_parse+timeout)) + 截止线命中率((landed+bad_parse)/fired) + 宏观指标 PI/cascade/Gini + 采样真台词。
## ⚠ 决策占比看 landed/decisions（诚实分母），不要看 landed/fired——后者只说"发出去的按时回来几成"，
##   分母里没有"因为串行 worker 正忙而干脆没发"的那一大片。见 AIBackend.decision_stats 与 docs/35。
## --realtime：按 Sim.tick_interval 的墙钟节奏推 tick（复刻 Sim._process 的累加器，落后就连补不等），
##   这样 landed/decisions 才是【出货配置】下的占比；默认的 0.03s/tick 只是"跑得快"，占比不可外推。
## logic/mock 容器跑（快、验宏观不变性）；slm 本机原生 --gpu 跑（量真模型合法率+口吻，days 小即可）。
## 后端宏观矩阵需此 scene（AIBackend.decide 引用全局 Sim，--script 跑不了）。

const M = preload("res://bench/Metrics.gd")

var _swap_at := -1     # >=0：在该 tick 调 AIBackend.set_model_path（测 C1 换模型延后拆不崩）
var _realtime := false # true：按 Sim.tick_interval 墙钟推进（出货节奏），量真实决策占比

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
		elif args[i] == "--model" and i + 1 < args.size(): AIBackend.slm_model_path = args[i + 1]  # 指定 gguf（默认 3B 不在仓里时用）
		elif args[i] == "--cpu": AIBackend.slm_use_gpu = false                                     # 强制 CPU 推理（对照 GPU）
		elif args[i] == "--swap" and i + 1 < args.size(): _swap_at = int(args[i + 1])              # 在第 N tick 调 set_model_path（测 C1 换模型不崩）
		elif args[i] == "--gpu": AIBackend.slm_use_gpu = true
		elif args[i] == "--tier" and i + 1 < args.size(): AIBackend.tier = args[i + 1]   # 强制算力档(测节流)
		elif args[i] == "--agents" and i + 1 < args.size(): Sim.spawn_count = int(args[i + 1])  # 扩 N
		elif args[i] == "--budget" and i + 1 < args.size(): AIBackend.llm_budget = int(args[i + 1])  # L5 全镇令牌桶
		elif args[i] == "--aging" and i + 1 < args.size(): AIBackend.llm_aging = args[i + 1] != "off"  # L5 老化优先门(默认 on)
		elif args[i] == "--realtime": _realtime = true   # 出货节奏（1 sim-日=19.2s 墙钟）→ landed/decisions 才可外推
	var is_async := backend == "slm" or backend == "llm"
	if days <= 0:
		days = 8 if is_async else 40       # 异步真模型 days 小（每决策秒级）；确定性后端可大网格
	print("=== BackendBench  backend=%s seeds=%s days=%d gpu=%s N=%d realtime=%s ===" % [
		backend, seeds, days, str(AIBackend.slm_use_gpu), Sim.spawn_count, str(_realtime)])
	await _run(backend, _parse_seeds(seeds), days, is_async)
	get_tree().quit(0)

func _run(backend: String, seed_list: Array, days: int, is_async: bool) -> void:
	AIBackend.backend = backend
	AIBackend.backend_requested = backend   # 必须同步：否则 decide() 的运行期切换逻辑(backend!=requested→回退)会把 backend 立刻拽回 logic → fired=0
	var pis: Array = []
	var casc: Array = []
	var ginis: Array = []
	var fired := 0
	var landed := 0
	var bad := 0
	var timeout := 0
	var vginis: Array = []   # L5 发声公平：per-agent 触发次数的 Gini（越低越均）
	var vzeros: Array = []   # L5 从未发声的 agent 数（饿死之声）
	var calls := 0           # 诚实分母原料：decide() 被叫的总次数
	var waits := 0           #               其中"思考中，本 tick 不落地"的次数
	var wall_ms := 0         # 墙钟耗时（算 sim-日实际时长 → 判 --realtime 是否真跑到了出货节奏）
	var sim_ticks := 0
	var samples: Array = []
	var seen := {}
	for sd in seed_list:
		Sim.start_new(sd)
		Sim.backend = AIBackend
		Sim.auto_run = false
		AIBackend.reset_stats()
		var total: int = days * int(Sim.TICKS_PER_DAY)
		var t_run0 := Time.get_ticks_msec()
		for t in range(total):
			if t == _swap_at and AIBackend.slm_model_path != "":       # C1 测：运行中换模型（很可能撞上在飞决策→测 busy-defer 分支不崩）
				print("[BB] set_model_path @tick %d (fired so far=%d)" % [t, int(AIBackend.stats["fired"])])
				AIBackend.set_model_path(AIBackend.slm_model_path)
			Sim.tick()
			if _realtime:
				# 复刻 Sim._process 的累加器：第 k 个 tick 的墙钟目标 = t0 + k×tick_interval；
				# 已经落后就【立刻】跑下一 tick（不补睡），正如掉帧时 while 循环会连补——sim 时间只会落后、不会被拉长。
				var target := t_run0 + int(round(float(t + 1) * Sim.tick_interval * 1000.0))
				while Time.get_ticks_msec() < target:
					await get_tree().process_frame
			elif is_async:
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
		var ds: Dictionary = AIBackend.decision_stats()
		fired += int(AIBackend.stats["fired"])
		landed += int(AIBackend.stats["landed"])
		bad += int(AIBackend.stats["bad_parse"])
		timeout += int(AIBackend.stats["timeout"])
		calls += int(ds["calls"])
		waits += int(ds["waits"])
		wall_ms += Time.get_ticks_msec() - t_run0
		sim_ticks += total
		print("[BB] " + JSON.stringify({"backend": backend, "seed": sd, "fired": int(AIBackend.stats["fired"]),
			"landed": int(AIBackend.stats["landed"]), "bad": int(AIBackend.stats["bad_parse"]), "timeout": int(AIBackend.stats["timeout"]),
			"decisions": int(ds["decisions"]), "calls": int(ds["calls"]), "waits": int(ds["waits"]),
			"PI": snappedf(M.polarization(Sim), 0.001), "cascade": M.cascade_max(Sim), "Gini": snappedf(M.gini_acceptance(Sim), 0.001)}))

	var resolved := landed + bad + timeout
	var decisions := maxi(0, calls - waits)
	var sim_days := float(sim_ticks) / float(Sim.TICKS_PER_DAY)
	print("\n— 后端 %s 汇总（%d seed × %d 天, N=%d）—" % [backend, seed_list.size(), days, Sim.agents.size()])
	print("  宏观指标: PI %s | cascade %s | Gini %s" % [_stat(pis), _stat(casc), _stat(ginis)])
	# 分母审计：这几行才是"模型到底做了几成决策"的原始证据。落地决策 = decide() 调用数 − 思考中(_wait)次数
	# （对照 Sim.gd:1076-1086：非 _wait 的返回一律 agent_apply 落地，空 {} 由引擎兜底后落地）。
	print("  决策分母: decide()调用=%d  其中思考中(_wait)=%d  → 落地决策=%d  (%.1f 次/sim-日)" % [
		calls, waits, decisions, float(decisions) / maxf(0.001, sim_days)])
	if fired > 0:
		print("  模型决策: fired=%d landed=%d bad_parse=%d timeout=%d" % [fired, landed, bad, timeout])
		print("  合法率 = %.1f%% (landed/resolved)   截止线命中率 = %.1f%% ((landed+bad)/fired)" % [
			100.0 * float(landed) / float(maxi(1, resolved)), 100.0 * float(landed + bad) / float(fired)])
		print("  ★ 决策占比 = %.2f%% (landed/落地决策)   ← 诚实口径；对照 landed/fired = %.1f%%（只说发出去的按时回来几成）" % [
			100.0 * float(landed) / float(maxi(1, decisions)), 100.0 * float(landed) / float(fired)])
		print("    模型决策 %.2f 次/sim-日（全镇；串行 worker → 与 N 无关的墙钟天花板）" % [float(landed) / maxf(0.001, sim_days)])
		if not vginis.is_empty():
			print("  发声公平(L5 aging=%s): Gini %s | 从未发声 agent 数 %s (越低越均/越少饿死)" % [str(AIBackend.llm_aging), _stat(vginis), _stat(vzeros)])
	else:
		print("  模型决策: 0（logic 后端无模型调用，作宏观基线；落地决策数即为诚实分母的分母）")
	# 节奏审计：不报这个，上面的"次/sim-日"就没法外推到出货配置。
	var real_day_s := (float(wall_ms) / 1000.0) / maxf(0.001, sim_days)
	var ship_day_s := float(Sim.TICKS_PER_DAY) * Sim.tick_interval
	print("  节奏: 本 run 1 sim-日 ≈ %.1fs 墙钟；出货(auto_run,speed=1) = %.1fs。%s" % [real_day_s, ship_day_s,
		"节奏相符，占比可外推。" if absf(real_day_s - ship_day_s) <= 0.25 * ship_day_s else "★ 节奏不符 → 上面的占比【不可】直接外推到真机，只作分母审计用（用 --realtime 复现出货节奏）。"])
	if fired > 0:
		print("  串行天花板: 解码 %.0fs/发 → 全镇上限 %.1f 次/sim-日；解码 %.0fs/发 → %.1f 次/sim-日（真机 CPU 实测 3-8s，docs/34）" % [
			3.0, AIBackend.slm_ceiling_per_sim_day(3.0), 8.0, AIBackend.slm_ceiling_per_sim_day(8.0)])
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
