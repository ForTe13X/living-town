extends SceneTree
## bench/lod_observation_probe.gd — B10：「激进 LOD 的 Gini 塌陷是【观测的】还是【行为的】？」判别探针。
##
## 背景（docs/35 §2.5，外部对抗评审 GPT-5 Pro）：聚合档改的不只是行为，还有【观测口径】。
## 若聚合路径把 cohort 的结果池化 / 对一整组用同一个估计概率 / 只上报一部分 agent /
## 减少每个 agent 的接受机会数，则「接受率 Gini」会【机械地】塌下去，底层社交倾向却没被抹平。
##
## 判别实验（本文件）：跑【全保真】(LOD off)，把它的观测按聚合档的【完全相同的采样节奏与暴露模式】
## 降采样后重算 Gini：
##   · D1 计数匹配   ——每个 agent 只保留 m_i 条提议（m_i = 该 agent 在激进档的提议数，按其自身序列均匀抽）。
##                     m_i=0 的 agent 直接剔除（复刻 Metrics.gini_acceptance 对 prop==0 的剔除）。
##   · D2 提交期节奏 ——只保留「事件发生那 tick 该 actor 在影子 cohort 内」的提议。
##   · D3 决策期节奏 ——只保留「该 option 被【创建】那 tick actor 在影子 cohort 内」的提议（最忠实：
##                     聚合档的闸门在【决策】不在【提交】——有 option 的 agent 恒 salient 恒在 cohort 内）。
## 影子 cohort = 在 off 跑里【只读地】复刻 Sim._compute_lod_cohort 的谓词（玩家 ∪ _is_salient ∪ id%span==tick%span）。
## 纯读：不写任何 Sim 态、不抽 RNG、不进 tools/ci.sh ⇒ 对 golden digest 零扰动。
##
## 同时补齐评审要的三件事：
##   · 逐 seed 效应量（Gini 绝对值 + 提议数/agent + 零观测 agent 数），不只百分比；
##   · #14「standing 跨度塌成 0」是否【字面为零】——直接打原始 standing 的 min/max/方差/非零条数；
##   · #8/#11/#14/#17/#26 的原始计数（Invariants 的 detail 串），看 14 条红是不是【一个缺陷的相关症状】；
##   · off vs 激进的【首次因果分歧 tick】（第一条不一致的 event）。
##
## 用法：godot --headless --path game --script res://bench/lod_observation_probe.gd -- [--seeds 1-3] [--agents 60] [--days 20] [--period 4]
const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")
const Met = preload("res://bench/Metrics.gd")

## Metrics.gini_acceptance 数的就是这 6 类「作为发起方的提议」——逐字沿用，别在这里另立口径。
const PROP_TYPES := ["greet", "give", "gossip", "invite", "gossip_rep", "discuss"]
const FOCUS_IDS := [8, 11, 14, 17, 26]

func _init() -> void:
	var seeds := _parse("1-3")
	var n := 60
	var days := 20
	var period := 4
	var agg_days := 0   # --agg-days：只把【激进臂】跑更久，用来做「等交互量」而非「等 tick 数」的对照。
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size(): seeds = _parse(args[i + 1])
		elif args[i] == "--agents" and i + 1 < args.size(): n = int(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size(): days = int(args[i + 1])
		elif args[i] == "--period" and i + 1 < args.size(): period = int(args[i + 1])
		elif args[i] == "--agg-days" and i + 1 < args.size(): agg_days = int(args[i + 1])
	if agg_days <= 0: agg_days = days

	print("=== B10 LOD 观测 vs 行为 判别探针  N=%d seeds=%s days=%d(激进臂 %d 天) period=%d ===" % [n, str(seeds), days, agg_days, period])
	if agg_days != days:
		print("  ⚠ 激进臂跑 %d 天而非 %d 天：这是【等交互量】对照（激进档每 tick 的社交提议约为 off 的 1/3.4），" % [agg_days, days]
			+ "\n    用来判别「聚合档【毁掉】涌现社交」还是「只是把它【放慢】到与省下的成本同一个倍率」。"
			+ "\n    注意 D1/D2/D3 与首次分歧在此模式下不可比（tick 数不同），只看第 2d/3/4 节。")

	var rows: Array = []
	for sd in seeds:
		var off := _run(sd, n, days, period, "off", -1.0)
		var agg := _run(sd, n, agg_days, period, "agg", -1.0)
		# 反事实臂：同一个激进档，只把 far agent 的 social 需求钉到【全保真稳态值】而不是 _far_maintain 的 ~50。
		# 这是【bench 侧模拟】一个候选修法（不改 game/scripts，不出货），用来判定保真损失是不是由那一个常数支配。
		var fix := _run(sd, n, agg_days, period, "agg", float(off["soc"]))
		var d1 := _downsample_count_matched(off, agg)
		var d2 := _gini_of(off["prop_by_tick_cohort"], off["acc_by_tick_cohort"])
		var d3 := _gini_of(off["prop_by_dec_cohort"], off["acc_by_dec_cohort"])
		var div := _first_divergence(off["events"], agg["events"])
		rows.append({"seed": sd, "off": off, "agg": agg, "fix": fix,
			"d1": d1["g"], "d1n": d1["n"], "d1e": d1["ev"],
			"d2": d2["g"], "d2n": d2["n"], "d2e": d2["ev"],
			"d3": d3["g"], "d3n": d3["n"], "d3e": d3["ev"], "div": div})

	# ── 1. 暴露模式：每个 agent 拿到多少次「接受机会」───────────────────────────
	print("\n— 1. 暴露模式（每 agent 的提议次数 = 接受机会数）—")
	print("  seed |            off 提议/agent            |           激进 提议/agent            | 激进/off")
	print("       | 总数  均值  中位  最小 最大  零观测 |  总数  均值  中位  最小 最大  零观测 |")
	for r in rows:
		var o: Dictionary = r["off"]; var a: Dictionary = r["agg"]
		print("  %4d | %5d %5.1f %5.0f %4d %4d %6d | %5d %5.1f %5.0f %4d %4d %6d | %.3f" % [
			int(r["seed"]),
			int(o["prop_total"]), o["prop_mean"], o["prop_med"], int(o["prop_min"]), int(o["prop_max"]), int(o["zero_n"]),
			int(a["prop_total"]), a["prop_mean"], a["prop_med"], int(a["prop_min"]), int(a["prop_max"]), int(a["zero_n"]),
			float(a["prop_total"]) / maxf(1.0, float(o["prop_total"]))])
	print("  （零观测 = 整局一次都没发起过提议的 agent；Metrics.gini_acceptance 把这些 agent【整个剔除】，不计 0 也不计 1）")
	print("  影子 cohort 覆盖率（在【全保真】世界里跑聚合档的采样谓词，每 agent 平均有多少比例的 tick 在满帧集内）:")
	for r in rows:
		print("    seed %d: off 世界 %.3f | 激进世界(自身实测) %.3f" % [
			int(r["seed"]), float((r["off"] as Dictionary)["cohort_frac"]), float((r["agg"] as Dictionary)["cohort_frac"])])

	# ── 2. 决定性对照：全保真降采样后的 Gini vs 聚合仿真的 Gini ─────────────────
	print("\n— 2. 【决定性对照】把全保真的观测按激进档的采样节奏/暴露模式降采样后重算 Gini —")
	print("  seed | off全量(n/ev) | D1计数匹配(n/ev) | D2提交期节奏(n/ev) | D3决策期节奏(n/ev) | 激进仿真(n/ev)")
	for r in rows:
		var o: Dictionary = r["off"]; var a: Dictionary = r["agg"]
		print("  %4d | %.4f (%d/%d) | %.4f (%d/%d) | %.4f (%d/%d) | %.4f (%d/%d) | %.4f (%d/%d)" % [
			int(r["seed"]),
			o["gini"], int(o["xs_n"]), int(o["prop_total"]),
			r["d1"], int(r["d1n"]), int(r["d1e"]),
			r["d2"], int(r["d2n"]), int(r["d2e"]),
			r["d3"], int(r["d3n"]), int(r["d3e"]),
			a["gini"], int(a["xs_n"]), int(a["prop_total"])])
	print("  (n = 进入 Gini 的 agent 数；ev = 参与统计的提议条数。n<2 时 Gini 定义为 0 —— 这时的 0 是【没数据】不是【均等】。)")

	print("\n— 2b. 接受率分布（Gini 塌陷的机制在这里）—")
	print("  seed | 配置 | 均接受率 | 被拒条数 | 率=1.0 的 agent | 率最低    最高")
	for r in rows:
		for k in ["off", "agg"]:
			var s: Dictionary = r[k]
			print("  %4d | %-4s |  %.4f  | %8d | %14d | %.3f  %.3f" % [
				int(r["seed"]), k, s["rate_mean"], int(s["rej_total"]), int(s["rate1_n"]), s["rate_min"], s["rate_max"]])
	print("  (Gini 对【全体挤在同一个值】的分布恒为 0——率全 =1.0 时 Gini 必然 =0，与「社会分化被抹平」不是同一件事。)")
	print("  零观测 agent 若按率=0 计入（而非剔除）: off Gini=%.4f 激进 Gini=%.4f" % [
		_mean(_col(rows, "off", "gini_z")), _mean(_col(rows, "agg", "gini_z"))])

	# ── 2c. 机制：为什么激进档几乎人人被接受 ────────────────────────────────
	# Sim._acceptance_margin 里 greet 的判定式主项是 (100 − target.social) * 0.4（阈值 0，jitter ±10）。
	# 激进档的 _far_maintain 对任何 <50 的需求每 tick 无条件 +AGG_RELIEF(6.0) → far agent 的 social 需求被
	# 钉在 50 附近 → 主项恒 ≈20 → 压过 jitter → 几乎必接受。全保真档 agent 靠真社交把 social 顶到高位
	# → 主项 ≈0 → jitter 说了算 → 约一半被拒。
	print("\n— 2c. 机制：时均 social 需求（接受判定的主项是 (100−social)*0.4，阈值 0，jitter ±10）—")
	for r in rows:
		var o: Dictionary = r["off"]; var a: Dictionary = r["agg"]
		print("    seed %d: off %.1f → 主项 %.1f  |  激进 %.1f → 主项 %.1f" % [
			int(r["seed"]), o["soc"], (100.0 - float(o["soc"])) * 0.4, a["soc"], (100.0 - float(a["soc"])) * 0.4])
	var g_off := _col(rows, "off", "gini"); var g_agg := _col(rows, "agg", "gini")
	var g_d1 := _colf(rows, "d1"); var g_d2 := _colf(rows, "d2"); var g_d3 := _colf(rows, "d3")
	print("  均值±极差: off %.4f [%.4f,%.4f] | D1 %.4f [%.4f,%.4f] | D2 %.4f [%.4f,%.4f] | D3 %.4f [%.4f,%.4f] | 激进 %.4f [%.4f,%.4f]" % [
		_mean(g_off), _min(g_off), _max(g_off), _mean(g_d1), _min(g_d1), _max(g_d1),
		_mean(g_d2), _min(g_d2), _max(g_d2), _mean(g_d3), _min(g_d3), _max(g_d3),
		_mean(g_agg), _min(g_agg), _max(g_agg)])
	print("  绝对变化: 激进−off = %+.4f   D1−off = %+.4f   D3−off = %+.4f" % [
		_mean(g_agg) - _mean(g_off), _mean(g_d1) - _mean(g_off), _mean(g_d3) - _mean(g_off)])
	# 自动判读，免得人肉读表读出自己想要的结论。判据：把全保真降采样到激进档的暴露/节奏后，
	# Gini 若也塌到激进值附近（取 off→激进落差的一半为界）→ 观测假象；否则观测假象不成立。
	var mid := (_mean(g_off) + _mean(g_agg)) * 0.5
	var artefact := _mean(g_d1) <= mid or _mean(g_d3) <= mid
	print("  判读: %s" % ("【观测假象】降采样后的全保真 Gini 也塌到了激进档一侧" if artefact
		else "【非观测假象】降采样后的全保真 Gini 【没有】塌向激进档；抽样变稀反而把 Gini 推【高】（小样本噪声抬高离散度）"))
	print("        ⇒ 「更少观测/剔除零观测 agent 会机械地压低 Gini」这一假设【方向相反】，被本实验排除。")
	print("        但这【不】等于「社会分化被抹平」——真机制见下面 2b/2c：激进档几乎无人被拒，接受率全顶到 1.0（天花板压缩）。")

	# ── 2d. 反事实臂：把 far 的 social 需求钉到全保真稳态，保真损失还剩多少？────────
	print("\n— 2d. 反事实臂 agg+fix（bench 侧模拟：far 的 social 补给目标 = 全保真稳态值，而非 _far_maintain 的 ~50）—")
	print("  ⚠ 这是【bench 里的模拟】，不是 game/scripts 的改动，也不是已验证的修法——只用来判定")
	print("     保真损失是不是被 _far_maintain 那一个常数支配。")
	print("  seed | 配置    | 提议总数 | 时均social | Gini   | 均接受率 | 被拒条数 | standing跨度 | standing方差 | #11触发/对质/修复")
	for r in rows:
		for k in ["off", "agg", "fix"]:
			var s: Dictionary = r[k]
			print("  %4d | %-7s | %8d | %10.1f | %.4f |  %.4f  | %8d | %12.2f | %12.4f | %s" % [
				int(r["seed"]), ("agg+fix" if k == "fix" else k), int(s["prop_total"]), s["soc"],
				s["gini"], s["rate_mean"], int(s["rej_total"]),
				s["st_max"] - s["st_min"], s["st_var"], String((s["detail"] as Dictionary).get(11, "?"))])
	print("  均值: Gini off=%.4f 激进=%.4f agg+fix=%.4f | 均接受率 %.3f / %.3f / %.3f | standing方差 %.4f / %.4f / %.4f" % [
		_mean(_col(rows, "off", "gini")), _mean(_col(rows, "agg", "gini")), _mean(_col(rows, "fix", "gini")),
		_mean(_col(rows, "off", "rate_mean")), _mean(_col(rows, "agg", "rate_mean")), _mean(_col(rows, "fix", "rate_mean")),
		_mean(_col(rows, "off", "st_var")), _mean(_col(rows, "agg", "st_var")), _mean(_col(rows, "fix", "st_var"))])

	# ── 3. #14 到底是不是「跨度字面为零」──────────────────────────────────────
	print("\n— 3. #14 standing 分化：原始跨度/方差（不是只看阈值过没过）—")
	print("  seed | 配置 | 关系条数 | standing 非零条数 |   min    max   跨度   方差")
	for r in rows:
		for k in ["off", "agg"]:
			var s: Dictionary = r[k]
			print("  %4d | %-4s | %8d | %17d | %6.2f %6.2f %6.2f %8.4f" % [
				int(r["seed"]), k, int(s["rel_n"]), int(s["st_nz"]), s["st_min"], s["st_max"],
				s["st_max"] - s["st_min"], s["st_var"]])

	# ── 4. 5 条软不变量的原始计数（效应量，不是越界计数）─────────────────────────
	print("\n— 4. #8/#11/#14/#17/#26 的原始计数（同一个缺陷的相关症状？）—")
	for r in rows:
		for k in ["off", "agg"]:
			var s: Dictionary = r[k]
			var det: Dictionary = s["detail"]
			var parts := PackedStringArray()
			for fid in FOCUS_IDS:
				parts.append("#%d[%s]%s" % [fid, String(det.get(fid, "?")), "" if bool(s["okmap"].get(fid, true)) else " ❌"])
			print("  seed %d %-4s: %s" % [int(r["seed"]), k, "  ".join(parts)])

	# ── 5. 首次因果分歧 ─────────────────────────────────────────────────────
	print("\n— 5. off 与激进的首次因果分歧（第一条不一致的 event）—")
	for r in rows:
		print("  seed %d: %s" % [int(r["seed"]), String(r["div"])])

	print("\n=== 探针完成（纯观测，不成门）===")
	quit(0)

# ── 一次跑：全保真或激进，附影子 cohort 记账 ────────────────────────────────
## soc_target ≥ 0：反事实臂——每 tick 后把【当 tick 在 far 侧】的 agent 的 social 需求钉到 soc_target，
## 等价于「_far_maintain 的补给目标改成全保真稳态值，而不是硬编码的 <50 才补」。只碰 social 一项（接受判定里
## 只有它进主项），只在 bench 里做，绝不改 game/scripts。soc_target < 0 = 不干预。
func _run(seed: int, n: int, days: int, period: int, mode: String, soc_target: float) -> Dictionary:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	S.spawn_count = n
	S.decide_period = period
	S.lod_near_radius = 8
	S.lod_near_cap = 0
	S.lod = false
	S.lod_aggregate = mode == "agg"
	S.start_new(seed)

	var prop := {}          # 全量：每 agent 提议数
	var acc := {}
	var prop_tc := {}       # D2：事件 tick 落在影子 cohort 内的提议
	var acc_tc := {}
	var prop_dc := {}       # D3：决策 tick 落在影子 cohort 内的提议
	var acc_dc := {}
	var seq := {}           # 每 agent 的提议序列 [{accepted:bool}]，供 D1 均匀抽样
	var last_dec_in := {}   # D3：该 agent 当前 option 的创建 tick 是否在影子 cohort 内
	var cohort_ticks := {}  # 影子 cohort 命中 tick 数（暴露频率）
	for ag in S.agents:
		var aid: String = ag["id"]
		prop[aid] = 0; acc[aid] = 0; prop_tc[aid] = 0; acc_tc[aid] = 0
		prop_dc[aid] = 0; acc_dc[aid] = 0; seq[aid] = []
		last_dec_in[aid] = true; cohort_ticks[aid] = 0

	var total := days * int(S.TICKS_PER_DAY)
	var starved := 0
	var ev_ptr := 0
	var soc_sum := 0.0      # 时均 social 需求：接受判定里 (100-need)*0.4 是 greet/invite 的主项 → 机制证据
	var soc_n := 0
	var events: Array = []      # 首次分歧用的轻量事件签名
	for t in range(total):
		# 影子 cohort：用【tick 开始时】的状态 + tick_no+1 的相位，与 Sim.tick() 里 _compute_lod_cohort 的调用点逐字对齐。
		var cohort := _shadow_cohort(S, int(S.tick_no) + 1)
		var had_opt := {}
		for ag in S.agents:
			had_opt[ag["id"]] = ag.get("option") != null
			if cohort.has(ag["id"]):
				cohort_ticks[ag["id"]] = int(cohort_ticks[ag["id"]]) + 1
		S.tick()
		if soc_target >= 0.0:
			for ag in S.agents:
				if not S._near_set.has(ag["id"]):
					ag["needs"]["social"] = soc_target
		for ag in S.agents:
			soc_sum += float(ag["needs"].get("social", 0.0)); soc_n += 1
		# 本 tick 新建 option 的 agent → 记下它的决策 tick 是否在影子 cohort 内。
		for ag in S.agents:
			var aid2: String = ag["id"]
			if not bool(had_opt[aid2]):
				# option 从 null 变有 = 本 tick 做了决策；仍为 null 也可能是「决策后立即完成」→ 一并按本 tick 记。
				last_dec_in[aid2] = cohort.has(aid2)
		# 本 tick 新增的事件
		while ev_ptr < S.event_log.size():
			var e: Dictionary = S.event_log[ev_ptr]
			ev_ptr += 1
			events.append("%d|%s|%s|%s|%s" % [int(S.tick_no), String(e["type"]), String(e.get("actor", "")), String(e.get("target", "")), str(bool(e.get("accepted", false)))])
			if not (String(e["type"]) in PROP_TYPES):
				continue
			var a: String = e["actor"]
			if not prop.has(a):
				continue
			var ok := bool(e["accepted"])
			prop[a] = int(prop[a]) + 1
			(seq[a] as Array).append(ok)
			if ok: acc[a] = int(acc[a]) + 1
			if cohort.has(a):
				prop_tc[a] = int(prop_tc[a]) + 1
				if ok: acc_tc[a] = int(acc_tc[a]) + 1
			if bool(last_dec_in.get(a, true)):
				prop_dc[a] = int(prop_dc[a]) + 1
				if ok: acc_dc[a] = int(acc_dc[a]) + 1
		for ag in S.agents:
			for nid in ag["needs"]:
				if float(ag["needs"][nid]) <= 0.5:
					starved += 1

	# standing 原始统计——必须在 Inv.check_all 之前算：check_all 里的 perceived 会用 _rel() 惰性建出
	# 一堆 standing=0 的关系条目，跑完再统计会被这些零稀释方差。
	var st: Array = []
	for ag in S.agents:
		for oid in ag["relationships"]:
			st.append(float(ag["relationships"][oid]["standing"]))
	var st_min := 0.0; var st_max := 0.0; var st_nz := 0
	for v in st:
		st_min = minf(st_min, v); st_max = maxf(st_max, v)
		if absf(v) > 0.0: st_nz += 1
	var st_var := 0.0
	if st.size() > 0:
		var m := 0.0
		for v in st: m += v
		m /= float(st.size())
		for v in st: st_var += (v - m) * (v - m)
		st_var /= float(st.size())

	var gini := Met.gini_acceptance(S)
	var detail := {}
	var okmap := {}
	for c in Inv.check_all(S, starved):
		var cid := int(c["id"])
		if cid in FOCUS_IDS:
			detail[cid] = String(c["detail"]); okmap[cid] = bool(c["ok"])

	var counts: Array = []
	var rates: Array = []
	var rates_z: Array = []     # 零观测 agent 按率=0 计入的版本（对照「剔除」口径）
	var zero_n := 0
	var rate1_n := 0
	var rej_total := 0
	for ag in S.agents:
		var p := int(prop[ag["id"]])
		counts.append(p)
		if p > 0:
			var rt := float(acc[ag["id"]]) / float(p)
			rates.append(rt); rates_z.append(rt)
			if rt >= 1.0: rate1_n += 1
			rej_total += p - int(acc[ag["id"]])
		else:
			zero_n += 1; rates_z.append(0.0)
	counts.sort()

	get_root().remove_child(S)
	S.free()
	return {
		"prop": prop, "acc": acc, "seq": seq,
		"prop_by_tick_cohort": prop_tc, "acc_by_tick_cohort": acc_tc,
		"prop_by_dec_cohort": prop_dc, "acc_by_dec_cohort": acc_dc,
		"cohort_ticks": cohort_ticks, "cohort_frac": _mean(cohort_ticks.values()) / maxf(1.0, float(total)),
		"prop_total": _isum(counts), "prop_mean": _mean(counts), "prop_med": _median(counts),
		"prop_min": counts[0] if counts.size() > 0 else 0, "prop_max": counts[counts.size() - 1] if counts.size() > 0 else 0,
		"zero_n": zero_n, "gini": gini, "rate_mean": _mean(rates), "xs_n": rates.size(),
		"gini_z": _gini(rates_z), "rate1_n": rate1_n, "rej_total": rej_total,
		"soc": soc_sum / maxf(1.0, float(soc_n)),
		"rate_min": _min(rates), "rate_max": _max(rates),
		"st_min": st_min, "st_max": st_max, "st_var": st_var, "st_nz": st_nz, "rel_n": st.size(),
		"detail": detail, "okmap": okmap, "events": events, "ticks": total}

## 影子 cohort：只读地复刻 Sim._compute_lod_cohort 的谓词（玩家 ∪ _is_salient ∪ |_aid|%span == tick%span）。
## 直接调 S._is_salient / S._aid 而非重写 —— 重写就等于埋一份会漂的副本。
func _shadow_cohort(S, tick_for_phase: int) -> Dictionary:
	var out := {}
	var span := maxi(1, int(S.lod_rotate_span))
	var phase := tick_for_phase % span
	for ag in S.agents:
		if bool(ag.get("is_player", false)) or S._is_salient(ag) or (absi(S._aid(ag)) % span) == phase:
			out[ag["id"]] = true
	return out

## D1：把 off 每个 agent 的提议序列均匀降采样到 m_i 条（m_i = 激进档同 id 的提议数），再算 Gini。
## m_i=0 → 该 agent 整个剔除（复刻 Metrics 对 prop==0 的剔除口径）。均匀抽（不是取前 m 条）：
## 聚合档的稀疏是【全程】稀疏，不是只在开头有观测。
func _downsample_count_matched(off: Dictionary, agg: Dictionary) -> Dictionary:
	var xs: Array = []
	var kept := 0
	var seq: Dictionary = off["seq"]
	var m: Dictionary = agg["prop"]
	for aid in seq:
		var s: Array = seq[aid]
		var want := int(m.get(aid, 0))
		if want <= 0 or s.is_empty():
			continue
		want = mini(want, s.size())
		var a := 0
		for k in range(want):
			if bool(s[int(float(k) * float(s.size()) / float(want))]):
				a += 1
		xs.append(float(a) / float(want))
		kept += want
	return {"g": _gini(xs), "n": xs.size(), "ev": kept}

func _gini_of(prop: Dictionary, acc: Dictionary) -> Dictionary:
	var xs: Array = []
	var kept := 0
	for aid in prop:
		var p := int(prop[aid])
		if p > 0:
			xs.append(float(acc[aid]) / float(p)); kept += p
	return {"g": _gini(xs), "n": xs.size(), "ev": kept}

## Gini 的算法逐字沿用 Metrics.gini_acceptance 的后半段（同一口径才可比）。
func _gini(xs: Array) -> float:
	if xs.size() < 2:
		return 0.0
	var s := 0.0
	var tot := 0.0
	for a in xs:
		tot += float(a)
		for b in xs:
			s += absf(float(a) - float(b))
	if tot <= 0.0:
		return 0.0
	return s / (2.0 * float(xs.size()) * tot)

func _first_divergence(ea: Array, eb: Array) -> String:
	var n := mini(ea.size(), eb.size())
	for i in range(n):
		if String(ea[i]) != String(eb[i]):
			return "第 %d 条事件起分歧  off=[%s]  激进=[%s]" % [i, String(ea[i]), String(eb[i])]
	if ea.size() != eb.size():
		return "前 %d 条完全相同，之后长度不同 (off=%d 激进=%d)" % [n, ea.size(), eb.size()]
	return "全程事件序列完全相同（%d 条）" % n

# ── 小工具 ───────────────────────────────────────────────────────────────
func _col(rows: Array, k: String, f: String) -> Array:
	var out: Array = []
	for r in rows: out.append(float((r[k] as Dictionary)[f]))
	return out

func _colf(rows: Array, k: String) -> Array:
	var out: Array = []
	for r in rows: out.append(float(r[k]))
	return out

func _isum(a: Array) -> int:
	var s := 0
	for x in a: s += int(x)
	return s

func _mean(a: Array) -> float:
	if a.is_empty(): return 0.0
	var s := 0.0
	for x in a: s += float(x)
	return s / float(a.size())

func _median(a: Array) -> float:
	if a.is_empty(): return 0.0
	return float(a[a.size() / 2])

func _min(a: Array) -> float:
	if a.is_empty(): return 0.0
	var m := float(a[0])
	for x in a: m = minf(m, float(x))
	return m

func _max(a: Array) -> float:
	if a.is_empty(): return 0.0
	var m := float(a[0])
	for x in a: m = maxf(m, float(x))
	return m

func _parse(spec: String) -> Array:
	var out: Array = []
	if "-" in spec:
		var ab := spec.split("-")
		for s in range(int(ab[0]), int(ab[1]) + 1): out.append(s)
	else:
		for s in spec.split(","): out.append(int(s))
	return out
