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

## ── docs/38 追加：产品侧三方对拍（logic vs random vs slm）─────────────────────
## docs/36 已坐实"模型的覆写在【引擎效用轴】上与均匀瞎猜不可区分"，但它明确没答的是：
## 那些偏离在【产品轴】上买到了什么？——事件构成、戏剧事件活性、行为多样性、迟疑成本。
## 所以下面加的全是【产品层】读数，且三条臂用【同一段代码】采集，保证可比：
##   · 事件构成 event_mix：全镇各类事件的占比（"小镇做的事不一样了"，而不只是"多少次不一样"）
##   · 戏剧事件活性：aid/confide/leak/betray/pact/… 的次数 + 出现过的 seed 数（罕见事件看活性比看均值有意义）
##   · 行为多样性：已提交动作分布的香农熵 + 人均动作种类数
##   · 迟疑账：全镇 agent-tick 里 option==null 的比例（_wait 的产品侧影子）
## 采集一律是【只读观测】：每 tick 末扫一遍 Sim.agents、末态扫 event_log，不写 sim 态、不抽 RNG ⇒ digest 零扰动（红线#1）。
const M = preload("res://bench/Metrics.gd")
## 罕见但"有戏"的事件。前三条是社交动作（Sim 用 _log_event(action,…) 记），后几条是引擎专道事件。
const DRAMA := ["aid", "confide", "leak", "betray", "pact", "rally_oust", "mediate", "confront", "apologize"]

var _swap_at := -1     # >=0：在该 tick 调 AIBackend.set_model_path（测 C1 换模型延后拆不崩）
var _realtime := false # true：按 Sim.tick_interval 墙钟推进（出货节奏），量真实决策占比
var _shadow := true    # true：每次模型落地时顺手求一次引擎基线 → 覆写率 Δ/C（docs/36；纯函数，不扰仿真）

# ── per-seed 产品侧采集器（每个 seed 开跑前清零）──────────────────────────────
var _prev_opt := {}    # agent id → 上一 tick 末 option 的身份串（""=空闲）；用来把"新提交的一次动作"数出来
var _act_count := {}   # action → 提交次数（全镇本 seed）
var _act_agents := {}  # agent id → {action:true} → 人均行为种类数
var _idle_ticks := 0   # Σ(option==null 的 agent-tick)：迟疑的【产品侧】影子，三条臂同法可比
var _agent_ticks := 0  # Σ(agent × tick)：上式的分母
## ★ 这两条是"玩家看不看得见"的硬读数，也是 CI 结构上【永远查不到】的那一块：
##   金标恒 Sim.backend=null ⇒ decide() 不被调用 ⇒ 硬不变量 #01「无饿穿」只在【引擎地板】上被验过，
##   从没在任何模型/随机后端下被验过。这里用与 Harness._run_once 逐字一致的口径（need ≤ 0.5 的 agent-tick）
##   把它补上——若某条臂 starve>0，那就是 CI 全绿但产品已破的情形。
var _starve_ticks := 0 # Σ(任一 need ≤ 0.5 的 agent-tick)：硬不变量 #01「无饿穿」的口径（Harness.gd:599-601 同款）
var _crisis_ticks := 0 # Σ(min_need < NEED_CRISIS 的 agent-tick)：没到饿穿、但已进"危机"的生活质量读数

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
		elif args[i] == "--no-shadow": _shadow = false   # 关影子基线对拍（默认开；只影响埋点，不影响仿真）
		# docs/38：把 slm 的【剂量】复制给合成臂 —— K 个 tick 的解码时延 + 全镇串行。
		# 出货节奏下 1 tick = 0.08s ⇒ K = 解码秒数/0.08。用 tick 而非墙钟 ⇒ 这条臂无需 --realtime 也能复现剂量，且逐字节可复现。
		elif args[i] == "--decode-ticks" and i + 1 < args.size(): AIBackend.sim_decode_ticks = int(args[i + 1])
		# docs/38 迟疑账：思考期不阻塞该 agent（发起同 tick 先按引擎地板行动，答案留给下一次决策点）
		elif args[i] == "--nowait": AIBackend.block_while_thinking = false
		# docs/38 §机制：位置鹦鹉对照臂——逗号分隔的下标权重（喂 slm 实测选号直方图 → 只复制"位置偏好"，看不见候选内容）
		elif args[i] == "--pick-dist" and i + 1 < args.size():
			AIBackend.rand_pick_weights = Array(args[i + 1].split(",")).map(func(s): return float(s))
	AIBackend.shadow_baseline = _shadow                  # docs/36：落地时顺手求一次引擎基线 → 量真覆写率 Δ/C
	var is_async := backend == "slm" or backend == "llm"
	if days <= 0:
		days = 8 if is_async else 40       # 异步真模型 days 小（每决策秒级）；确定性后端可大网格
	print("=== BackendBench  backend=%s seeds=%s days=%d gpu=%s N=%d realtime=%s decode_ticks=%d block=%s ===" % [
		backend, seeds, days, str(AIBackend.slm_use_gpu), Sim.spawn_count, str(_realtime),
		AIBackend.sim_decode_ticks, str(AIBackend.block_while_thinking)])
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
	var delta := 0           # docs/36 真影响力：落地的模型选择 ≠ 引擎在【同一冻结候选集】上会挑的那个
	var delta_full := 0      #               ≠ 引擎在【本 tick 全量候选】上会挑的那个（真·反事实支：Sim.gd:1090）
	var delta_action := 0    #               其中连"立即动作种类"都换了的（廉价的"有没有所谓"信号）
	var capped_n := 0        #               落地时候选 >36（被裁过）的次数 → 判 frozen/full 两口径该不该分家
	var cand_sum := 0        # 退化排查：Σ|候选集|、Σ选中下标、选 0 号次数、Σ1/|候选集|
	var pick_sum := 0        #   —— 没有这几个数，"Δ/L 很高"分不清是【有主见】还是【扔骰子】
	var pick0 := 0
	var inv_cand_sum := 0.0
	var pick_hist := {}      #   选号分布（合并各 seed）：总答同一个号 = 退化
	var rank_sum := 0.0      # Σ归一化分数名次（0=最高分,0.5=随机,1=最低分）——比选号分布硬得多的判据
	var gap_sum := 0.0       # Σ(引擎基线 score − 模型选择 score) = 模型实际放弃的效用
	var gap_rand_sum := 0.0  # Σ(引擎基线 score − 候选均值 score) = 【随机挑一个】会放弃的效用（期望）
	var exp_kind_sum := 0.0  # Σ P(随机挑一个会换动作种类) = 随机换动作种类率的精确期望
	var parse_fail := 0      # bad_parse 分账①：模型输出本身不合格（格式不遵从）
	var stale_cand := 0      # bad_parse 分账②：输出合格但等待期候选失效（世界变了，不是模型的错）
	var wall_ms := 0         # 墙钟耗时（算 sim-日实际时长 → 判 --realtime 是否真跑到了出货节奏）
	var sim_ticks := 0
	var agent_ticks_tot := 0 # Σ(agent × tick)：迟疑账的分母（waits 占它多少）
	var nowait := 0          # docs/38：不阻塞档下"本可空等、改为照常行动"的次数
	# ── docs/38 产品侧（逐 seed 存，报 per-seed 散布而不只是均值）────────────────
	var evmix: Array = []    # 每 seed 的 {事件类型: 次数}
	var evtot: Array = []    # 每 seed 的事件总数
	var acc_rate: Array = [] # 每 seed 的社交提议被接受率
	var acts: Array = []     # 每 seed 的 {动作: 提交次数}
	var ents: Array = []     # 每 seed 的动作分布香农熵(bit)
	var varis: Array = []    # 每 seed 的人均动作种类数
	var commits: Array = []  # 每 seed 的提交动作总数
	var idles: Array = []    # 每 seed 的空闲 agent-tick 占比（迟疑的产品侧影子）
	var needs_mean: Array = []  # 每 seed 末态全镇需求均值（"玩家看得见吗"的最粗读数）
	var needs_min: Array = []   # 每 seed 末态全镇最低需求（生存压力）
	var starves: Array = []     # 每 seed 的饿穿 agent-tick（硬不变量 #01 口径）
	var crises: Array = []      # 每 seed 的"需求危机" agent-tick 占比
	var samples: Array = []
	var seen := {}
	for sd in seed_list:
		Sim.start_new(sd)
		Sim.backend = AIBackend
		Sim.auto_run = false
		AIBackend.reset_stats()
		_reset_probe()
		var total: int = days * int(Sim.TICKS_PER_DAY)
		var t_run0 := Time.get_ticks_msec()
		for t in range(total):
			if t == _swap_at and AIBackend.slm_model_path != "":       # C1 测：运行中换模型（很可能撞上在飞决策→测 busy-defer 分支不崩）
				print("[BB] set_model_path @tick %d (fired so far=%d)" % [t, int(AIBackend.stats["fired"])])
				AIBackend.set_model_path(AIBackend.slm_model_path)
			Sim.tick()
			_sample_tick()                # docs/38 只读观测：提交动作 + 空闲 agent-tick（不写 sim 态、不抽 RNG）
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
		# docs/38 产品侧收口（全部只读末态/日志）
		var mix := _event_mix()
		evmix.append(mix)
		var mtot := 0
		for k in mix: mtot += int(mix[k])
		evtot.append(mtot)
		acc_rate.append(_accept_rate())
		acts.append(_act_count.duplicate())
		ents.append(_entropy(_act_count))
		varis.append(_variety())
		var ctot := 0
		for k in _act_count: ctot += int(_act_count[k])
		commits.append(ctot)
		idles.append(float(_idle_ticks) / maxf(1.0, float(_agent_ticks)))
		var nm := _needs_stat()
		needs_mean.append(nm["mean"]); needs_min.append(nm["min"])
		starves.append(_starve_ticks); crises.append(float(_crisis_ticks) / maxf(1.0, float(_agent_ticks)))
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
		nowait += int(ds.get("nowait", 0))
		delta += int(ds["delta"])
		delta_full += int(ds["delta_full"])
		delta_action += int(ds["delta_action"])
		capped_n += int(AIBackend.stats.get("capped_n", 0))
		cand_sum += int(ds["cand_sum"]); pick_sum += int(ds["pick_sum"]); pick0 += int(ds["pick0"])
		inv_cand_sum += float(AIBackend.stats.get("inv_cand_sum", 0.0))
		rank_sum += float(AIBackend.stats.get("rank_sum", 0.0))
		gap_sum += float(AIBackend.stats.get("gap_sum", 0.0))
		gap_rand_sum += float(AIBackend.stats.get("gap_rand_sum", 0.0))
		exp_kind_sum += float(AIBackend.stats.get("exp_kind_sum", 0.0))
		parse_fail += int(ds["parse_fail"]); stale_cand += int(ds["stale_cand"])
		for k in AIBackend._pick_hist:
			pick_hist[k] = int(pick_hist.get(k, 0)) + int(AIBackend._pick_hist[k])
		wall_ms += Time.get_ticks_msec() - t_run0
		sim_ticks += total
		agent_ticks_tot += _agent_ticks
		# event_digest：L4 增量滚动摘要，本局全程事件的确定性见证。印出来是为了能做【影子基线开/关】的
		# 逐字节 A/B——CI 的金标恒 Sim.backend=null，证不到 decide() 路径上的影子调用无扰动（docs/36 §二）。
		print("[BB] " + JSON.stringify({"backend": backend, "seed": sd, "digest": Sim.event_digest, "fired": int(AIBackend.stats["fired"]),
			"landed": int(AIBackend.stats["landed"]), "bad": int(AIBackend.stats["bad_parse"]), "timeout": int(AIBackend.stats["timeout"]),
			"decisions": int(ds["decisions"]), "calls": int(ds["calls"]), "waits": int(ds["waits"]), "nowait": int(ds.get("nowait", 0)),
			"delta": int(ds["delta"]), "delta_full": int(ds["delta_full"]), "delta_action": int(ds["delta_action"]),
			"PI": snappedf(M.polarization(Sim), 0.001), "cascade": M.cascade_max(Sim), "Gini": snappedf(M.gini_acceptance(Sim), 0.001),
			# ── docs/38 产品侧 per-seed 原始数据（下游脚本按此行做三方对拍与散布统计）──
			"ev_total": mtot, "ev_mix": mix, "accept": snappedf(_accept_rate(), 0.0001),
			"acts": _act_count, "commits": ctot, "entropy": snappedf(_entropy(_act_count), 0.0001),
			"variety": snappedf(_variety(), 0.001), "idle_frac": snappedf(float(_idle_ticks) / maxf(1.0, float(_agent_ticks)), 0.0001),
			"agent_ticks": _agent_ticks, "needs_mean": snappedf(nm["mean"], 0.01), "needs_min": snappedf(nm["min"], 0.01),
			"starve_ticks": _starve_ticks, "crisis_frac": snappedf(float(_crisis_ticks) / maxf(1.0, float(_agent_ticks)), 0.0001)}))

	var resolved := landed + bad + timeout
	var decisions := maxi(0, calls - waits)
	var sim_days := float(sim_ticks) / float(Sim.TICKS_PER_DAY)
	print("\n— 后端 %s 汇总（%d seed × %d 天, N=%d）—" % [backend, seed_list.size(), days, Sim.agents.size()])
	print("  宏观指标: PI %s | cascade %s | Gini %s" % [_stat(pis), _stat(casc), _stat(ginis)])
	# ── docs/38 产品侧：三条臂就是拿这一段互相比 ─────────────────────────────
	print("  ── 产品侧（docs/38）──")
	print("  提交动作: 总数 %s | 香农熵 %s bit | 人均动作种类 %s" % [_stat(commits), _stat(ents), _stat(varis)])
	print("  事件: 总数 %s | 社交提议被接受率 %s" % [_stat(evtot), _stat(acc_rate)])
	print("  迟疑: 空闲 agent-tick 占比 %s（option==null；_wait 的产品侧影子）" % _stat(idles))
	print("  末态需求: 均值 %s | 最低 %s" % [_stat(needs_mean), _stat(needs_min)])
	# ★ CI 结构上查不到的那一块：金标恒 backend=null ⇒「无饿穿」从没在模型/随机后端下被验过（见变量处长注释）。
	print("  生存: 饿穿 agent-tick %s（硬不变量 #01 要求 =0）| 需求危机 agent-tick 占比 %s" % [
		_stat(starves), _stat(crises)])
	print("  事件构成(占比%，按总数降序): " + _mix_line(evmix))
	print("  戏剧事件活性(次数均值 / 出现过的 seed 数): " + _drama_line(evmix, seed_list.size()))
	print("  动作构成(占比%，按总数降序): " + _mix_line(acts))
	# 分母审计：这几行才是"模型到底做了几成决策"的原始证据。落地决策 = decide() 调用数 − 思考中(_wait)次数
	# （对照 Sim.gd:1076-1086：非 _wait 的返回一律 agent_apply 落地，空 {} 由引擎兜底后落地）。
	print("  决策分母: decide()调用=%d  其中思考中(_wait)=%d  → 落地决策=%d  (%.1f 次/sim-日)" % [
		calls, waits, decisions, float(decisions) / maxf(0.001, sim_days)])
	if not AIBackend.block_while_thinking:
		print("  ★ 不阻塞档(--nowait)：思考期照常按引擎地板行动 %d 次（这些【是】落地决策，故 waits=%d 应≈0）" % [nowait, waits])
	# docs/38 迟疑账：_wait 的每一次都精确等于"某个 agent 这一 tick 什么也没做"。
	if waits > 0:
		print("  ★ 迟疑账: 因思考而作废的 agent-tick = %d，占全镇 agent-tick 的 %.2f%%（%d 个 agent × %d tick）" % [
			waits, 100.0 * float(waits) / maxf(1.0, float(agent_ticks_tot)), Sim.agents.size(), sim_ticks])
	if fired > 0:
		print("  模型决策: fired=%d landed=%d bad_parse=%d timeout=%d" % [fired, landed, bad, timeout])
		print("  合法率 = %.1f%% (landed/resolved)   截止线命中率 = %.1f%% ((landed+bad)/fired)" % [
			100.0 * float(landed) / float(maxi(1, resolved)), 100.0 * float(landed + bad) / float(fired)])
		# bad_parse 的两笔账必须分开：一笔怪模型（格式不遵从），一笔怪世界（等待期候选失效）。
		# 混在一起会把"世界变太快"记到模型的格式能力头上——这是读 1.5B 合法率时最容易犯的错。
		print("    其中 bad_parse 分账: 格式不遵从(模型的锅)=%d (%.1f%% of fired) | 候选失效(等待期世界变了,不是模型的锅)=%d (%.1f%% of fired)" % [
			parse_fail, 100.0 * float(parse_fail) / float(maxi(1, fired)),
			stale_cand, 100.0 * float(stale_cand) / float(maxi(1, fired))])
		print("  ★ 决策占比 = %.2f%% (landed/落地决策)   ← 诚实口径；对照 landed/fired = %.1f%%（只说发出去的按时回来几成）" % [
			100.0 * float(landed) / float(maxi(1, decisions)), 100.0 * float(landed) / float(fired)])
		print("    模型决策 %.2f 次/sim-日（全镇；串行 worker → 与 N 无关的墙钟天花板）" % [float(landed) / maxf(0.001, sim_days)])
		# ── docs/36 真影响力：landed ≠ drove ─────────────────────────────────
		# 上面那个 landed/C 只是【上界】：模型挑中的很可能正是引擎自己也会挑的那个。
		# 下面的 Δ 是落地时【真的和引擎选得不一样】的次数 —— 这才是"模型改变了什么"的直接度量。
		if _shadow:
			print("  ★★ 真影响力(影子基线对拍): Δ=%d  →  Δ/C = %.2f%%（★真·覆写率）| L/C = %.2f%%（上界）| Δ/L = %.1f%%（落地时的分歧率）" % [
				delta, 100.0 * float(delta) / float(maxi(1, decisions)),
				100.0 * float(landed) / float(maxi(1, decisions)), 100.0 * float(delta) / float(maxi(1, landed))])
			print("     其中换了【立即动作种类】的: %d (%.1f%% of Δ, %.2f%% of C) ← 廉价的\"有没有所谓\"信号；同 action 换对象不计" % [
				delta_action, 100.0 * float(delta_action) / float(maxi(1, delta)),
				100.0 * float(delta_action) / float(maxi(1, decisions))])
			print("     全量候选口径 Δ_full=%d (%.2f%% of C) ← 真·反事实支(Sim.gd:1090 模型弃权时走全量 _logic_decide)；落地时候选>36 被裁过 %d 次%s" % [
				delta_full, 100.0 * float(delta_full) / float(maxi(1, decisions)), capped_n,
				"（=0 → 两口径同集，Δ 应恒等）" if capped_n == 0 else "（>0 → 两口径分家，差值即裁剪引入的）"])
			# ── 退化排查：高 Δ ≠ 有判断力 ────────────────────────────────────
			# 一个【均匀瞎猜】的模型期望分歧率 = 1 − mean(1/|C|)；一个【总答 0 号】的模型 Δ 也不低。
			# 所以 Δ/L 必须对着这条随机基线读，并看选号分布是否塌成一个点。
			var rnull := 100.0 * (1.0 - inv_cand_sum / maxf(1.0, float(landed)))
			var dl := 100.0 * float(delta) / float(maxi(1, landed))
			print("     退化排查: 平均候选集 %.1f 个 | 平均选中下标 %.2f | 选 0 号 %d 次(%.1f%%) | 不同下标 %d 种" % [
				float(cand_sum) / maxf(1.0, float(landed)), float(pick_sum) / maxf(1.0, float(landed)),
				pick0, 100.0 * float(pick0) / float(maxi(1, landed)), pick_hist.size()])
			print("     ⚠ 随机基线: 均匀瞎猜的期望 Δ/L = %.1f%%；实测 Δ/L = %.1f%% → %s" % [rnull, dl,
				"实测【低于】随机基线 %.1f pt：模型确实在向引擎的偏好靠拢，分歧是有结构的，不是掷骰子。" % (rnull - dl) if dl < rnull - 5.0
				else ("实测与随机基线仅差 %.1f pt → 【无法与均匀瞎猜区分】，Δ 不可解读为\"判断力\"。" % absf(rnull - dl) if absf(rnull - dl) <= 5.0
				else "实测【高于】随机基线 %.1f pt → 比瞎猜还爱唱反调（系统性偏离引擎偏好，需查 prompt/解析）。" % (dl - rnull))])
			# ── 三条对着【引擎自己的效用函数 score】的硬判据 ────────────────────
			# 选号分布只说"有没有塌成一个点"；下面三条才回答"这些覆写是不是就等于随机换一个"。
			var Lf := maxf(1.0, float(landed))
			var mrank := rank_sum / Lf                    # 0=总挑最高分, 0.5=与随机不可分, 1=总挑最低分
			var mgap := gap_sum / Lf                      # 实际放弃的效用
			var mgap_r := gap_rand_sum / Lf               # 随机挑一个会放弃的效用（期望）
			var mkind := float(delta_action) / Lf         # 实测换动作种类率
			var mkind_r := exp_kind_sum / Lf              # 随机挑一个的换种率（期望）
			print("     ── 对引擎效用函数(score)的三条硬判据 ──")
			print("     ① 分数名次: 模型选择的归一化名次 %.3f  (0=总挑最高分 / 0.5=与随机不可分 / 1=总挑最低分)" % mrank)
			print("     ② 效用落差: 实测放弃 %.3f 分 vs 随机挑一个会放弃 %.3f 分  → 保住了随机损失的 %.1f%%" % [
				mgap, mgap_r, 100.0 * (1.0 - mgap / maxf(0.0001, mgap_r))])
			print("     ③ 换动作种类: 实测 %.1f%% vs 随机期望 %.1f%%  → %s" % [100.0 * mkind, 100.0 * mkind_r,
				"低于随机，覆写偏保守" if mkind < mkind_r - 0.05 else ("与随机不可分" if absf(mkind - mkind_r) <= 0.05 else "高于随机")])
			var hist_keys := pick_hist.keys()
			hist_keys.sort()
			var hs: Array = []
			for k in hist_keys:
				hs.append("%s:%d" % [str(k), int(pick_hist[k])])
			print("     选号分布(下标:次数): " + ", ".join(hs))
		else:
			print("  真影响力: 未测（--no-shadow）。landed/C 只是上界，别当成\"模型驱动了几成决策\"。")
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

# ── docs/38 产品侧采集/统计 ───────────────────────────────────────────────────
## 每个 seed 开跑前清零（否则跨 seed 的动作分布/空闲计数会串味，正是 reset_stats 那个坑的孪生）。
func _reset_probe() -> void:
	_prev_opt = {}
	_act_count = {}
	_act_agents = {}
	_idle_ticks = 0
	_agent_ticks = 0
	_starve_ticks = 0
	_crisis_ticks = 0

## 每 tick 末的只读观测。两件事：
##   ① 数【新提交的一次动作】——option 的身份串从上一 tick 变了且非空 ⇒ 这 tick 该 agent 提交了一次新动作。
##      为什么可靠：Sim 是"这一 tick 把 option 置 null → 下一 tick 才重决策"（_advance_agent 顶部先判 opt==null），
##      所以两次相邻动作之间必有至少一个 option==null 的 tick 落在观测点上 ⇒ 连做两次同样的事也不会漏数。
##   ② 数【空闲 agent-tick】——option==null 就是"这一 tick 这个人没在干任何事"，
##      正是 _wait 迟疑在产品侧的影子；三条臂同法采集，故可比。
func _sample_tick() -> void:
	for ag in Sim.agents:
		_agent_ticks += 1
		for nid in ag["needs"]:                                  # 口径与 Harness._run_once 逐字一致
			if float(ag["needs"][nid]) <= 0.5:
				_starve_ticks += 1
				break
		if Sim._min_need(ag) < Sim.NEED_CRISIS:
			_crisis_ticks += 1
		var opt = ag.get("option")
		var key := ""
		if opt is Dictionary:
			key = "%s|%s|%s|%s|%s" % [String((opt as Dictionary).get("kind", "")), String((opt as Dictionary).get("action", "")),
				String((opt as Dictionary).get("target", "")), String((opt as Dictionary).get("partner", "")),
				String((opt as Dictionary).get("area", ""))]
		else:
			_idle_ticks += 1
		var id := String(ag["id"])
		if key != "" and key != String(_prev_opt.get(id, "")):
			var a := String((opt as Dictionary).get("action", ""))
			if a == "":
				a = String((opt as Dictionary).get("kind", "?"))     # attend 没有 action 字段 → 用 kind 记
			_act_count[a] = int(_act_count.get(a, 0)) + 1
			if not _act_agents.has(id):
				_act_agents[id] = {}
			(_act_agents[id] as Dictionary)[a] = true
		_prev_opt[id] = key

## 事件构成：末态 event_log 的 {类型: 次数}。这是"小镇【做了什么】"的直接读数，
## 与 PI/cascade/Gini 那三个标量互补——后者只说强度，说不出构成变没变。
func _event_mix() -> Dictionary:
	var m := {}
	for e in Sim.event_log:
		var t := String(e["type"])
		m[t] = int(m.get(t, 0)) + 1
	return m

## 社交提议被接受率（与 Metrics.gini_acceptance 同一套提议类型，保持口径一致）。
func _accept_rate() -> float:
	var prop := 0
	var acc := 0
	for e in Sim.event_log:
		if String(e["type"]) in ["greet", "give", "gossip", "invite", "gossip_rep", "discuss"]:
			prop += 1
			if bool(e["accepted"]): acc += 1
	return float(acc) / maxf(1.0, float(prop))

## 香农熵(bit)：分布越平越大。"多样性"这个词很滑，落到熵上才可证伪。
func _entropy(counts: Dictionary) -> float:
	var tot := 0.0
	for k in counts: tot += float(counts[k])
	if tot <= 0.0: return 0.0
	var h := 0.0
	for k in counts:
		var p := float(counts[k]) / tot
		if p > 0.0: h -= p * (log(p) / log(2.0))
	return h

## 人均动作种类数：熵是全镇层面的，这条是【个体】层面的——"每个人自己花样多不多"。
## 两者可以背离：全镇熵高也可能是每人各做一件不同的事（个体单调）。
func _variety() -> float:
	if Sim.agents.is_empty(): return 0.0
	var s := 0.0
	for ag in Sim.agents:
		s += float((_act_agents.get(String(ag["id"]), {}) as Dictionary).size())
	return s / float(Sim.agents.size())

## 末态需求：均值 + 全镇最低（"玩家看不看得出来"的最粗读数；掉太低=生活质量被搞坏了）。
func _needs_stat() -> Dictionary:
	var s := 0.0
	var n := 0
	var mn := INF
	for ag in Sim.agents:
		for nid in ag["needs"]:
			var v := float(ag["needs"][nid])
			s += v; n += 1; mn = minf(mn, v)
	return {"mean": s / maxf(1.0, float(n)), "min": (0.0 if mn == INF else mn)}

## 把 per-seed 的若干 {键:次数} 合并成"占比%（每 seed 的次数散布）"一行，按总数降序，最多 12 项。
func _mix_line(per_seed: Array) -> String:
	var tot := {}
	var grand := 0
	for m in per_seed:
		for k in m:
			tot[k] = int(tot.get(k, 0)) + int((m as Dictionary)[k])
			grand += int((m as Dictionary)[k])
	var keys := tot.keys()
	keys.sort_custom(func(a, b): return int(tot[a]) > int(tot[b]))
	var out: Array = []
	for i in mini(12, keys.size()):
		var k = keys[i]
		out.append("%s %.1f%%(n=%d)" % [str(k), 100.0 * float(tot[k]) / maxf(1.0, float(grand)), int(tot[k])])
	return ", ".join(out) if not out.is_empty() else "—"

## 戏剧事件：罕见事件报【均值 + 活性(出现过的 seed 数)】。只报均值会把"4 个 seed 里 1 个爆了 8 次"
## 和"4 个 seed 各 2 次"混为一谈，而这两件事在产品上完全不同（前者是偶发奇观，后者是常态）。
func _drama_line(per_seed: Array, nseeds: int) -> String:
	var out: Array = []
	for k in DRAMA:
		var tot := 0
		var live := 0
		for m in per_seed:
			var c := int((m as Dictionary).get(k, 0))
			tot += c
			if c > 0: live += 1
		out.append("%s %.2f/%d" % [k, float(tot) / maxf(1.0, float(nseeds)), live])
	return ", ".join(out) + "  (seed 总数 %d)" % nseeds

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
