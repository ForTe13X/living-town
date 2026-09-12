extends SceneTree
## bench/x1_starve_trace.gd — X1：**#01 在大 N 上红的时候，那个人到底处在哪一种状态。**
##
## 为什么不用现成的 find_starve.gd（docs/41 §0 红线5「复用优先」——这里说清为什么复用不到）：
##   `find_starve.gd` 回答的是「谁 / 哪条 need / 在干嘛」，M1 用它定位到 `npc_13`。
##   本棒要判的是**族**：M2 那条注释把 N=20 的那一例叫作**吸收态**，判据是
##   「跌破 SURVIVAL_GATE 之后 `_social_candidates` 返回的候选数**恒为 0**」。
##   而 W2 在 N=40 上扫出的两颗（27 need·tick / 125 need·tick）**比它小两个数量级**
##   ——同一条不变量红，可能是完全不同的两件事。`find_starve` 不打候选数、不打连续段、
##   不打「候选为 0 是因为哪一条」⇒ 分不了族。本探针补的就是这三样。
##
## ⚠ **纯只读**：本探针**不调用** `_social_candidates()`。
##   理由是实测的：它内部 `_rel(ag, o["id"])`（Sim.gd:3608）在关系不存在时**会 auto-create**
##   ⇒ 从探针里调它会往 `relationships` 里塞条目，进而动 `Inv.digest` 与后续枚举。
##   替代做法**等价且更强**：`_social_candidates` 的前两道门是
##     ① `_min_need(ag) < SURVIVAL_GATE` → return []
##     ② `social >= SOCIAL_FULL`         → return []
##   过了这两道之后，对**每一个** `talking==0` 的同区在场者都会**无条件**产出一条 greet
##   （Sim.gd:2022，注释原文「greet / smalltalk —— 总可发起」）
##   ⇒ **候选数 == 0  ⟺  ①gated ∨ ②full ∨ ③同区可搭话的人数为 0**，三者互斥地记账。
##   这不是估计，是把那段代码的控制流逐条读出来的；而它只用到纯读的 `_min_need` /
##   `_nearby_agents` / `talking`，一个字节都不会写进世界。
##
## 用法：
##   godot --headless --path game -s res://bench/x1_starve_trace.gd -- \
##       --seed 8 --agents 40 --days 60 [--focus npc_21] [--window 720] [--out <path>]
##
## 输出：①每个触底者的汇总（need·tick / 连续段 / 首末天）；②焦点者的逐日轨迹；
##      ③焦点者在触底窗口内的逐 tick 明细；④焦点者全程的社交收支（作为发起方/被动方，接受/被拒）；
##      ⑤同一局的 `口粮` 满足率与断供天数——**为了当场判「#01 与 #40 是不是同一件事」**。
const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed := 8
	var n := 40
	var days := 60
	var focus := ""
	var window := 720
	var out_path := ""
	for i in args.size():
		if args[i] == "--seed" and i + 1 < args.size(): seed = int(args[i + 1])
		elif args[i] == "--agents" and i + 1 < args.size(): n = int(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size(): days = int(args[i + 1])
		elif args[i] == "--focus" and i + 1 < args.size(): focus = String(args[i + 1])
		elif args[i] == "--window" and i + 1 < args.size(): window = int(args[i + 1])
		elif args[i] == "--out" and i + 1 < args.size(): out_path = String(args[i + 1])

	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	if n > 0: S.spawn_count = n
	S.start_new(seed)
	var tpd: int = int(S.TICKS_PER_DAY)
	var total: int = days * tpd

	# ── 第一遍：全量记账（口径逐字照 Harness._run_once：所有 agent × 所有 need × 每 tick）──
	var starved := 0
	var by_need := {}
	var by_agent := {}                 # id -> need·tick
	var by_agent_need := {}            # "id/need" -> need·tick
	var run_last := {}
	var run_start := {}
	var run_max := {}                  # "id/need" -> 最长连续段
	var first_tick := {}               # "id/need" -> 首次触底 tick
	var last_tick := {}
	# 第一遍**只**记账（口径与 Harness 逐字相同）；焦点的逐日曲线放到第二遍再采，
	# 免得为了 40×5 条曲线在热路径上每 tick 做一次数组写（实测那样会把探针拖慢一个数量级）。
	for t in range(total):
		S.tick()
		for ag in S.agents:
			var aid := String(ag["id"])
			for nid in ag["needs"]:
				var v := float(ag["needs"][nid])
				var k := aid + "/" + String(nid)
				if v <= 0.5:
					starved += 1
					by_need[String(nid)] = int(by_need.get(String(nid), 0)) + 1
					by_agent[aid] = int(by_agent.get(aid, 0)) + 1
					by_agent_need[k] = int(by_agent_need.get(k, 0)) + 1
					if int(run_last.get(k, -2)) != t - 1: run_start[k] = t
					run_last[k] = t
					var ln: int = t - int(run_start[k]) + 1
					if ln > int(run_max.get(k, 0)): run_max[k] = ln
					if not first_tick.has(k): first_tick[k] = t
					last_tick[k] = t

	var checks: Array = Inv.check_all(S, starved, by_need)
	var hard := []
	var soft := []
	for c in checks:
		if c["ok"]: continue
		if int(c["id"]) in Inv.DIAG_IDS: continue
		if bool(c.get("hard", false)): hard.append(int(c["id"]))
		else: soft.append(int(c["id"]))
	var inv40 := ""
	for c in checks:
		if int(c["id"]) == 40: inv40 = String(c["detail"])

	var lines := PackedStringArray()
	lines.append("=== X1 starve trace  seed=%d N=%d(agents=%d) days=%d ===" % [seed, n, S.agents.size(), days])
	lines.append("  starved(need·tick 合计)=%d  by_need=%s" % [starved, JSON.stringify(by_need)])
	lines.append("  hard_fails=%s  soft_fails=%s" % [str(hard), str(soft)])
	lines.append("  #40 detail: %s" % inv40)
	lines.append("  --- 每个触底者（id / need·tick / 最长连续段 tick / 首日 / 末日 / 有无岗位）---")
	var keys: Array = by_agent_need.keys()
	keys.sort_custom(func(x, y): return int(by_agent_need[x]) > int(by_agent_need[y]))
	for k in keys:
		var parts := String(k).split("/")
		var aid := String(parts[0])
		var job := S._job_of(aid)
		lines.append("    %-22s %-8s need·tick=%-6d 最长连续=%-5d (%.2f 天)  首日=%d 末日=%d  岗位=%s" % [
			aid, parts[1], int(by_agent_need[k]), int(run_max.get(k, 0)),
			float(int(run_max.get(k, 0))) / float(tpd),
			int(first_tick[k]) / tpd + 1, int(last_tick[k]) / tpd + 1,
			"—(无)" if job.is_empty() else String(job.get("title", "?"))])
	if focus == "" and not keys.is_empty():
		focus = String(String(keys[0]).split("/")[0])
	lines.append("  ⇒ 焦点 = %s" % focus)

	# ── 第二遍：同一 seed 重跑，只对焦点者做逐 tick 明细（确定性 ⇒ 两遍逐字等价）──
	var S2 = SimScript.new()
	get_root().add_child(S2)
	S2._load_data(); S2.auto_run = false; S2.backend = null
	if n > 0: S2.spawn_count = n
	S2.start_new(seed)
	var fag: Dictionary = S2._agent_by_id.get(focus, {})
	if fag.is_empty():
		lines.append("  ⚠ 焦点 %s 不存在" % focus)
	else:
		var GATE: float = S2.SURVIVAL_GATE
		var FULL: float = S2.SOCIAL_FULL
		# 计数：候选数为 0 的三种互斥原因 + 候选数 > 0 的 tick 数
		var c_gated := 0; var c_full := 0; var c_alone := 0; var c_ok := 0; var c_talking := 0
		# ★这一组是本探针的第二个问题：**社交并不是"没有无条件满足物"**。
		#   map.json 的 `bench_1`(长椅·plaza·社交 +40/18t) 与 `counter_1`(吧台·cafe·闲聊 +42/20t)
		#   都广告 need=social，而 `_object_candidates` **不过 SURVIVAL_GATE**（那道门只在
		#   `_social_candidates` 里）⇒ 一个 social 见底的人**理论上**还有这条出路。
		#   所以"他为什么没走这条"必须分成两问：**枚举得到吗** / **枚举到了但分数没赢**。
		#   下面两个计数分别回答这两问；`_object_candidates` 是纯读（不碰 `_rel`，不 `cand_calls++`），
		#   而"纯读"这件事本身由 pass1/pass2 的 starved 逐字相等来当场证伪（见收尾那行 ORACLE）。
		var so_have := 0        # social<GATE 期间，枚举里有 need=social 的【物件】候选的 tick 数
		var so_none := 0        # 同期，一条都没有的 tick 数
		var so_best := -1.0e18  # 同期这些候选的最高分
		var so_taken := 0       # 同期真的在做 need=social 物件动作的 tick 数
		var below := 0          # social < GATE 的 tick 数（分母）
		# 只在触底期统计的同一组
		var s_gated := 0; var s_full := 0; var s_alone := 0; var s_ok := 0
		var ev_seen: int = S2.event_log.size()
		var trace := PackedStringArray()
		var lo := 999999; var hi := -1
		for k in by_agent_need:
			if String(k).begins_with(focus + "/"):
				lo = mini(lo, int(first_tick[k])); hi = maxi(hi, int(last_tick[k]))
		var wlo := maxi(0, lo - window)
		var whi := mini(total - 1, hi + window / 2)
		# 焦点者的社交收支
		var as_actor := {}      # "action|accepted" -> n
		var as_target := {}
		var day_line := PackedStringArray()
		var dmin_cur := 999.0
		var dname_cur := "?"
		for t in range(total):
			S2.tick()
			var mn: float = S2._min_need(fag)
			var soc := float(fag["needs"].get("social", 100.0))
			var near: Array = S2._nearby_agents(fag)
			var free := 0
			for o in near:
				if int(o["talking"]) == 0: free += 1
			var gated := mn < GATE
			var full := soc >= FULL
			var alone := free == 0
			var cand0 := gated or full or alone
			var bottom := false
			for nid in fag["needs"]:
				if float(fag["needs"][nid]) <= 0.5: bottom = true
			if soc < GATE:
				below += 1
				var objs: Array = S2._object_candidates(fag)
				var n_soc := 0
				for c in objs:
					if String(c.get("need", "")) == "social":
						n_soc += 1
						if float(c.get("score", -1.0e18)) > so_best: so_best = float(c["score"])
				if n_soc > 0: so_have += 1
				else: so_none += 1
				var opt0 = fag.get("option")
				if opt0 is Dictionary and String(opt0.get("need", "")) == "social" \
						and String(opt0.get("kind", "")) == "object":
					so_taken += 1
			if int(fag["talking"]) > 0: c_talking += 1
			if gated: c_gated += 1
			elif full: c_full += 1
			elif alone: c_alone += 1
			else: c_ok += 1
			if bottom:
				if gated: s_gated += 1
				elif full: s_full += 1
				elif alone: s_alone += 1
				else: s_ok += 1
			# 新事件里与焦点相关的
			for i in range(ev_seen, S2.event_log.size()):
				var e: Dictionary = S2.event_log[i]
				var ty := String(e.get("type", ""))
				var acc := bool(e.get("accepted", e.get("ok", true)))
				if String(e.get("actor", "")) == focus:
					var kk := ty + "|" + ("acc" if acc else "ref")
					as_actor[kk] = int(as_actor.get(kk, 0)) + 1
				if String(e.get("target", "")) == focus:
					var kk2 := ty + "|" + ("acc" if acc else "ref")
					as_target[kk2] = int(as_target.get(kk2, 0)) + 1
			ev_seen = S2.event_log.size()
			if t >= wlo and t <= whi and (t % 5 == 0 or bottom):
				var opt = fag.get("option")
				var okind := "idle"
				if opt is Dictionary:
					okind = String(opt.get("kind", "?")) + "/" + String(opt.get("action", ""))
				trace.append("    t=%-6d d=%-3d hun=%5.1f ene=%5.1f soc=%5.1f fun=%5.1f hyg=%5.1f | min=%5.1f %s near=%d free=%d talk=%d %s do=%s" % [
					t, t / tpd + 1,
					float(fag["needs"].get("hunger", -1)), float(fag["needs"].get("energy", -1)),
					soc, float(fag["needs"].get("fun", -1)), float(fag["needs"].get("hygiene", -1)),
					mn, "GATED" if gated else ("FULL " if full else ("ALONE" if alone else "cand>0")),
					near.size(), free, int(fag["talking"]),
					"BOTTOM" if bottom else "      ", okind])
			# 焦点的逐日最低 need（在第二遍现采，见第一遍那段注释）
			if mn < dmin_cur:
				dmin_cur = mn
				for nid in fag["needs"]:
					if is_equal_approx(float(fag["needs"][nid]), mn): dname_cur = String(nid)
			if (t + 1) % tpd == 0:
				day_line.append("      d%-3d 最低 need=%.1f (%s)  soc日末=%.1f" % [
					t / tpd + 1, dmin_cur, dname_cur, soc])
				dmin_cur = 999.0; dname_cur = "?"
		lines.append("  --- 焦点 %s 全程（%d tick）候选结构 ---" % [focus, total])
		lines.append("    候选数必为 0： GATED(min_need<%.0f)=%d  FULL(social>=%.0f)=%d  ALONE(同区可搭话=0)=%d" % [
			GATE, c_gated, FULL, c_full, c_alone])
		lines.append("    候选数 >0（至少一条 greet）= %d tick   其中本人正在对话 talking>0 = %d tick" % [c_ok, c_talking])
		lines.append("  --- 焦点在【触底的那些 tick】上的候选结构（判吸收态的那一条）---")
		lines.append("    GATED=%d  FULL=%d  ALONE=%d  候选>0=%d" % [s_gated, s_full, s_alone, s_ok])
		lines.append("  --- 焦点在【social < %.0f】期间还有没有【物件】这条出路（社交并非无满足物）---" % GATE)
		lines.append("    social<GATE 的 tick=%d：枚举里有 social 物件候选=%d · 一条都没有=%d · 最高分=%.2f · 真的在做=%d" % [
			below, so_have, so_none, so_best, so_taken])
		lines.append("  --- 焦点的社交收支 ---")
		lines.append("    作为发起方: %s" % JSON.stringify(as_actor))
		lines.append("    作为被动方: %s" % JSON.stringify(as_target))
		lines.append("  --- 焦点逐 tick（窗口 t∈[%d,%d]，每 5 tick 一行 + 全部触底 tick）---" % [wlo, whi])
		lines.append_array(trace)
		lines.append("  --- 焦点逐日最低 need ---")
		lines.append_array(day_line)
		# ★ORACLE：第二遍多调了 `_object_candidates`。若它其实**不是**纯读（例如某天有人往里加了
		#   一句 `_rel(...)`，那个函数会 auto-create 关系），两遍的 digest 立刻分叉。
		#   这一行把"我以为它是只读的"从推断变成**每次运行都重跑一次的断言**。
		var d1 := str(Inv.digest(S))
		var d2 := str(Inv.digest(S2))
		lines.append("  ORACLE 两遍 digest: pass1=%s pass2=%s  %s" % [
			d1, d2, "✅ 一致 ⇒ 探针未扰动仿真" if d1 == d2 else "❌ 分叉 ⇒ 探针在写世界，本文全部数字作废"])

	var txt := "\n".join(lines)
	print(txt)
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f: f.store_string(txt + "\n"); f.close()
	quit(0)
