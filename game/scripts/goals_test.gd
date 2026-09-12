extends Node
## goals_test.gd — 「小镇纪事」(scripts/Goals.gd) 的验收门。docs/46 §二-D2 的三条验收在此机器化。
##
## 用法：godot --headless --path game res://scenes/goals_test.tscn -- [--seeds 1-12] [--days 14] [--stats]
##
## 四条臂（每个 seed 各跑一遍；顺序有意义）：
##   A0 无目标基线 —— 完全不碰 Goals 地跑完，记下 Inv.digest / event_digest / 事件数。
##   A1 实时臂     —— 同种子重跑，每 tick 调一次 goals.sync(Sim.event_log)（与 Main._on_tick 同一条路）。
##        断言 A1 的 Inv.digest / event_digest 与 A0 **逐字节相同**
##        ⇒ Goals 既没有写世界状态、也没有改 event_log 里任何一个字段
##          （Inv.digest 覆盖 id/type/actor/target/accepted/subject/tick/witnesses/note 全字段）。
##   A2 重算臂     —— 对**同一份** event_log 从空态全量折一遍，断言 == A1。
##        证明「增量折 ≡ 全量折」，即 sync 的游标没有把状态藏在折叠之外。
##   A3 回放臂     —— Sim.goto_tick(T)（全新重演一遍历史，玩家拖时间轴走的正是这条）之后重算，
##        断言 == A1；再 goto_tick(T/2) 与实时臂在 T/2 的**快照**对拍。
##        ★这一条就是 docs/46 §二-D2 说的「它留在 View 侧」的机器证明：
##          同一份存档沿不同观看路径回放，目标状态必须一模一样。
##
## 断言的判别力（docs/41 §6-★「一个什么都不做的改动能不能通过它？」）：
##   光比 digest 是不够的 —— 一个**什么都不记**的 tracker 在 A1==A2==A3 上恒过。
##   故本门同时要求：①每个 seed 至少达成 1 条；②`chain`（折进来的事件序列见证）三臂一致；
##   ③打印逐 seed × 逐目标矩阵与达成时刻，让"是不是全部瞬间点亮"这件事看得见（不是只看一个绿字）。

const Inv = preload("res://bench/Invariants.gd")
const GoalsScript = preload("res://scripts/Goals.gd")

var _fail := 0

func _ready() -> void:
	# 默认 = docs/46 §二-D2 写死的验收网格（12 seed × 14 天），这样 CI 跑的就是验收本身。
	# tools/ci.sh 的场景循环不传参 ⇒ 想调档只能走环境变量（CI_GOALS_SEEDS / CI_GOALS_DAYS）。
	var seeds := _parse_seeds(_env("CI_GOALS_SEEDS", "1-12"))
	var days := int(_env("CI_GOALS_DAYS", "14"))
	var stats := false
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])
		elif args[i] == "--stats":
			stats = true

	var w1_only := false
	for i in args.size():
		if args[i] == "--w1-only":
			w1_only = true

	var probe := GoalsScript.new()
	if not probe.load_defs():
		print("❌ 读不到 data/goals.json（或表为空）")
		get_tree().quit(1)
		return
	if w1_only:
		_w1()
		print("")
		if _fail == 0:
			print("✅ W1 段全绿")
		else:
			print("❌ W1 段 %d 条断言失败" % _fail)
		get_tree().quit(1 if _fail > 0 else 0)
		return
	var titles: Array = []
	for d in probe.defs:
		titles.append(String(d.get("id", "")))
	var total := int(days) * int(Sim.TICKS_PER_DAY)
	var half := total / 2
	print("小镇纪事验收：%d 个目标 · seeds=%s · %d 天(%d tick) · 居民 %d" % [
		titles.size(), str(seeds), days, total, Sim.agents.size()])
	print("目标序：%s" % ", ".join(PackedStringArray(titles)))

	# 逐 seed × 逐目标：0=未达成，否则=达成的那一天
	var matrix: Array = []
	var evtypes: Dictionary = {}
	var wit_hist: Dictionary = {}

	for sd in seeds:
		# ── A0 无目标基线 ───────────────────────────────────────────────
		Sim.backend = null                # 红线#2：零模型地板；本门只验 View 侧派生，与后端无关
		Sim.record_decisions = false
		Sim.auto_run = false
		Sim.start_new(sd)
		for t in range(total):
			Sim.tick()
		var d0 := Inv.digest(Sim)
		var ed0 := Sim.event_digest
		var n0 := Sim.event_log.size()

		# ── A1 实时臂（每 tick 折一次，与 Main._on_tick 同路）─────────────
		var live := GoalsScript.new()
		live.load_defs()
		Sim.start_new(sd)
		var snap_half := {}
		for t in range(total):
			Sim.tick()
			live.sync(Sim.event_log)
			if Sim.tick_no == half:
				snap_half = {"digest": live.digest(), "chain": live.chain, "state": _snap(live)}
		var d1 := Inv.digest(Sim)
		var ed1 := Sim.event_digest
		var n1 := Sim.event_log.size()
		_expect(d0 == d1 and ed0 == ed1 and n0 == n1,
			"seed %d · A0≡A1 零扰动（Inv %d/%d · event_digest %d/%d · 事件 %d/%d）" % [sd, d0, d1, ed0, ed1, n0, n1])

		if stats:
			for e in Sim.event_log:
				var ty := String(e.get("type", ""))
				evtypes[ty] = int(evtypes.get(ty, 0)) + 1
				var w := (e.get("witnesses", []) as Array).size()
				wit_hist[w] = int(wit_hist.get(w, 0)) + 1

		# ── A2 重算臂（同一份 event_log，从空态全量折）────────────────────
		var recomp := GoalsScript.new()
		recomp.load_defs()
		recomp.recompute(Sim.event_log)
		_expect(recomp.digest() == live.digest() and recomp.chain == live.chain and _eq(live, recomp),
			"seed %d · A1≡A2 增量折 ≡ 全量折（digest %d/%d · chain %d/%d）" % [
				sd, live.digest(), recomp.digest(), live.chain, recomp.chain])

		# ── A3 回放臂：goto_tick 全新重演历史后重算 ───────────────────────
		Sim.goto_tick(total)
		var rep := GoalsScript.new()
		rep.load_defs()
		rep.recompute(Sim.event_log)
		_expect(rep.digest() == live.digest() and rep.chain == live.chain and _eq(live, rep),
			"seed %d · A1≡A3 回放安全 @T=%d（digest %d/%d · chain %d/%d）" % [
				sd, total, live.digest(), rep.digest(), live.chain, rep.chain])

		# 中途点：拖回一半，与实时臂在同一 tick 的快照对拍（"同存档不同观看路径"的真正形状）
		Sim.goto_tick(half)
		var rep2 := GoalsScript.new()
		rep2.load_defs()
		rep2.recompute(Sim.event_log)
		_expect(not snap_half.is_empty()
				and rep2.digest() == int(snap_half["digest"]) and rep2.chain == int(snap_half["chain"])
				and _eq_snap(snap_half["state"], _snap(rep2)),
			"seed %d · A1≡A3 回放安全 @T/2=%d（digest %d/%s · chain %d/%s）" % [
				sd, half, rep2.digest(), str(snap_half.get("digest", "n/a")),
				rep2.chain, str(snap_half.get("chain", "n/a"))])

		# ── 进度线本身 ────────────────────────────────────────────────
		var row: Array = []
		for s in live.state:
			row.append((int(s["done_tick"]) / int(Sim.TICKS_PER_DAY) + 1) if bool(s["done"]) else 0)
		matrix.append({"seed": sd, "row": row, "done": live.done_count()})
		_expect(live.done_count() >= 1, "seed %d · 至少达成 1 条（实际 %d/%d：%s）" % [
			sd, live.done_count(), live.state.size(), ", ".join(PackedStringArray(live.done_ids()))])

	# ── 逐 seed × 逐目标矩阵（数字 = 第几天达成；· = 14 天内未达成）──────────
	print("\n达成矩阵（列 = goals.json 书写序；数字 = 第几天达成，· = %d 天内未达成）" % days)
	var hdr := "seed  "
	for i in titles.size():
		hdr += "%3d" % (i + 1)
	print(hdr + "   合计")
	for m in matrix:
		var line := "%4d  " % int(m["seed"])
		for v in m["row"]:
			line += ("%3d" % int(v)) if int(v) > 0 else "  ·"
		print(line + "   %d/%d" % [int(m["done"]), titles.size()])
	# 逐目标命中率（这才是"判据有没有判别力"看得见的地方：全 12/12 与全 0/12 都是坏消息）
	print("\n逐目标命中 seed 数 / %d：" % matrix.size())
	for i in titles.size():
		var hit := 0
		var days_sum := 0
		for m in matrix:
			if int(m["row"][i]) > 0:
				hit += 1
				days_sum += int(m["row"][i])
		print("  %2d %-16s %2d/%d%s" % [i + 1, titles[i], hit, matrix.size(),
			("   中位达成日≈%.1f" % (float(days_sum) / float(hit))) if hit > 0 else ""])

	if stats:
		print("\n[stats] 事件类型直方图：")
		var keys: Array = evtypes.keys()
		keys.sort()
		for k in keys:
			print("  %-12s %d" % [k, int(evtypes[k])])
		print("[stats] 旁观者人数直方图：")
		var wk: Array = wit_hist.keys()
		wk.sort()
		for k in wk:
			print("  %d 人 %d" % [int(k), int(wit_hist[k])])

	# W1 段放在最后：它会开玩家、换后端、动世界，跑完不该有别的臂再读那份世界。
	_w1()

	print("")
	if _fail == 0:
		print("✅ 小镇纪事验收全绿（%d seed × %d 天）" % [seeds.size(), days])
	else:
		print("❌ 小镇纪事验收 %d 条断言失败" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

# ── W1 段：回放安全到底覆盖到哪（docs/47 §五-E4 / docs/46 §二·九-⑧）────────
## 上面的 A3 臂把 `Sim.backend = null` 钉死（红线#2 的零模型地板）。W1 问的是**离开那个地板之后**
## 这条"回放安全"还剩多少 —— 外部评审点了三条 A3 够不到的路，本段逐条给一条**能证伪**的臂。
##
## ★ 每条臂必须拆成两问，混在一起就成了一句糊话（本段的全部价值在这个拆分上）：
##   Q1「**折叠**本身还是不是纯函数？」= 增量折 ≡ 对**同一份日志**的全量重算。
##   Q2「**重演**出来的还是不是同一份日志？」= `goto_tick` 之后 `Sim.event_digest` 与 live 的是否相同。
##   实测答案：**Q1 恒真，Q2 只在 logic 地板 + 无玩家时为真。** 所以"回放安全"窄在 Q2，不在 Q1 ——
##   目标/故事是 event_log 的纯函数（这条一直成立），而**一次 scrub 会换掉那份 event_log**。
##
## 三条臂（前两条的红是**真实且不可在本文件里修**的，根因在 Sim；第三条是本棒修掉的那条）：
##   W1-a 非 logic 后端：`random` 是出货后端之一，`_rand_index` 走 `Sim._rng_at` ⇒ 确定、可两跑对拍。
##        `AIBackend.gd:788` 让**重演期强制走 logic 地板** ⇒ 重演出的是另一段历史。
##   W1-b 玩家在场：`player_act` 写进 event_log，而 `Sim.gd:939-940` 自己写着"玩家的历史干预不在重演里"
##        ⇒ 重演出的是**无玩家的平行世界**（实测：它与 W1-0 对照臂的 event_digest 逐字节相同）。
##   W1-c 前向拖动：`]` = `goto_tick(tick+240)`，日志**变长** ⇒ 旧版 `sync` 的自重置条件（只看变短）够不到。
##        ★但它**不是第三个独立缺陷**：实测 F 臂只在 Q2 已经红的臂上红 ⇒ 它是 ①② 的投影，不是新病因
##        （docs/41 §5「相关症状 ≠ 独立证据」）。且出货路径上 `Main._after_jump → _rebuild_feed` 每次都整份
##        `recompute`，这条路根本走不到。本棒仍然把它在**类一级**堵死（`Goals._anchor`），理由是"别人别踩"。
##
## 本段的判据自身要有判别力（docs/41 §6-★）：
##   · Q1 / F / resyncs==0 三条**必须全绿** —— 它们守的是折叠纯度、锚的正确性、锚的零成本。
##   · 「Q2 ✅ ⇒ R ✅ 且 F ✅」是**蕴含式**断言：将来若 Sim 真的能忠实重放模型决策/玩家历史，它照样绿。
##   · 而「网格里至少有一条臂 Q2 ❌」是**边界标记**：没有它，上面那条蕴含式可以平凡通过。
const W1_GREET_EVERY := 60        # 玩家臂：每 60 tick 走一次社交（确定性剧本，不抽 RNG、不读墙钟）

func _w1() -> void:
	var days := int(_env("CI_W1_DAYS", "8"))
	var total := days * int(Sim.TICKS_PER_DAY)
	var half := total / 2
	print("\n[W1] 回放安全的真实适用范围（%d 天 · 非 logic 后端 / 玩家在场 / 前向拖动）" % days)
	var q2_red := 0
	var q2_arms := 0
	for sd in _parse_seeds(_env("CI_W1_SEEDS", "1-2")):
		q2_arms += 3
		if not _w1_arm("W1-a 非logic后端(random)", sd, total, half, "random", false):
			q2_red += 1
		if not _w1_arm("W1-b 玩家在场(logic)", sd, total, half, "logic", true):
			q2_red += 1
		# 对照臂：这才是 README / docs/46 写的那条"回放安全 30/30"真正覆盖的配置。
		var ctrl := _w1_arm("W1-0 对照:纯logic无玩家", sd, total, half, "logic", false)
		_expect(ctrl, "W1-0 seed %d · 对照臂必须 Q2 ✅（logic 地板 + 无玩家 ⇒ 重演逐字节复现 event_log）" % sd)
	_expect(q2_red > 0,
		"W1 判别力：%d/%d 条臂的重演给出了**另一份** event_log —— 若这条红了，说明重演已经能忠实重放模型决策/玩家历史（好消息），"
		% [q2_red, q2_arms] + "请回来删掉本断言并把 README/docs/46 的适用范围放宽")
	_w1_restore()

func _w1_restore() -> void:
	Sim.backend = null
	AIBackend.backend = "logic"
	AIBackend.backend_requested = "logic"
	AIBackend.sim_decode_ticks = 0
	AIBackend.reset_stats()

## 一条臂 = 一次 live 跑 + 一次 goto_tick 重演 + 四份对拍。返回 Q2（重演是否给出同一份日志）。
func _w1_arm(label: String, sd: int, total: int, half: int, backend: String, with_player: bool) -> bool:
	_w1_restore()
	Sim.record_decisions = false
	Sim.auto_run = false
	if backend != "logic":
		AIBackend.backend = backend
		AIBackend.backend_requested = backend
		AIBackend.sim_decode_ticks = 0
		AIBackend.shadow_baseline = false
		Sim.backend = AIBackend
	Sim.start_new(sd)
	if with_player:
		Sim.add_player()
	var live := GoalsScript.new(); live.load_defs()
	var fwd := GoalsScript.new(); fwd.load_defs()     # 只折到 half 就停手 = 玩家在 half 处拖了时间轴
	var acts := 0
	for t in range(total):
		Sim.tick()
		if with_player and Sim.tick_no % W1_GREET_EVERY == 0:
			if _w1_player_beat(Sim.tick_no):
				acts += 1
		live.sync(Sim.event_log)
		if Sim.tick_no <= half:
			fwd.sync(Sim.event_log)
	var log_live: Array = Sim.event_log.duplicate()    # start_new 是 clear() 就地清 ⇒ 必须先 duplicate
	var ed_live: int = Sim.event_digest
	var n_live: int = log_live.size()

	# Q1：折叠是不是纯函数（对**同一份**日志）——这一条与后端/玩家无关，是本文件的红线本身。
	var pure := GoalsScript.new(); pure.load_defs()
	pure.recompute(log_live)
	var q1: bool = pure.digest() == live.digest() and pure.chain == live.chain and _eq(live, pure)

	# Q2：重演出来的还是不是同一份日志。
	Sim.goto_tick(total)
	var ed_rep: int = Sim.event_digest
	var n_rep: int = Sim.event_log.size()
	var q2: bool = (ed_rep == ed_live) and (n_rep == n_live)

	# R：重演之后**整份重算**（= Main._rebuild_feed 走的那条路）与 live 的目标状态是否相同。
	var rep := GoalsScript.new(); rep.load_defs()
	rep.recompute(Sim.event_log)
	var r_ok: bool = rep.digest() == live.digest() and rep.chain == live.chain and _eq(live, rep)

	# F：重演之后**顺着旧游标往下折**（= 假如 Main 不 recompute）与"整份重算"是否相同。
	fwd.sync(Sim.event_log)
	var f_ok: bool = fwd.digest() == rep.digest() and fwd.chain == rep.chain and _eq(fwd, rep)

	print("  [%s] seed=%d%s" % [label, sd, ("  玩家动作 %d 次" % acts) if with_player else ""])
	print("     Q1 折叠纯函数（同一份日志）      %s" % ("✅" if q1 else "❌"))
	print("     Q2 重演出同一份日志              %s   事件 %d→%d · event_digest %d→%d" % [
		"✅" if q2 else "❌", n_live, n_rep, ed_live, ed_rep])
	print("     R  重演后整份重算 ≡ live         %s   digest %d/%d · chain %d/%d · 达成 %d/%d" % [
		"✅" if r_ok else "❌", live.digest(), rep.digest(), live.chain, rep.chain,
		live.done_count(), rep.done_count()])
	print("     F  重演后顺游标续折 ≡ 整份重算   %s   digest %d/%d · chain %d/%d · 锚触发重折 %d 次（live 侧 %d 次，必须 0）" % [
		"✅" if f_ok else "❌", fwd.digest(), rep.digest(), fwd.chain, rep.chain, fwd.resyncs, live.resyncs])
	if not r_ok:
		print("     ↳ live 达成：%s" % ", ".join(PackedStringArray(live.done_ids())))
		print("     ↳ rep  达成：%s" % ", ".join(PackedStringArray(rep.done_ids())))
	# ── 四条硬断言（论证见本段抬头）──────────────────────────────────────
	_expect(q1, "%s seed %d · Q1 折叠是纯函数（**这条与后端/玩家无关**，它是 Goals.gd 的红线本身）" % [label, sd])
	_expect(f_ok, "%s seed %d · F 前向拖动后顺游标续折 ≡ 整份重算（`_anchor` 守着；负对照：删掉 `_anchor` 这条必红）" % [label, sd])
	_expect(live.resyncs == 0, "%s seed %d · 锚在 live 逐 tick 路上**一次都不触发**（实得 %d 次；非 0 = 每 tick 白折一遍全量）" % [
		label, sd, live.resyncs])
	if q2:
		_expect(r_ok, "%s seed %d · Q2 ✅ ⇒ R 必须 ✅（同一份日志 + 纯折叠 ⇒ 同一个目标状态）" % [label, sd])
	return q2

## 确定性玩家剧本：把一位居民召到身边，打个招呼。返回是否真的落地了一次动作。
## 名单写死、按 tick 取模轮转 ⇒ 不抽 RNG、不读墙钟，两跑逐字节一致。
func _w1_player_beat(t: int) -> bool:
	var pl: Dictionary = Sim.get_agent("player")
	if pl.is_empty():
		return false
	var ids: Array = []
	for ag in Sim.agents:
		var i := String(ag["id"])
		if i != "player":
			ids.append(i)
	if ids.is_empty():
		return false
	ids.sort()
	var tgt: Dictionary = Sim.get_agent(String(ids[(t / W1_GREET_EVERY) % ids.size()]))
	if tgt.is_empty():
		return false
	pl["option"] = null
	pl["talking"] = 0
	tgt["option"] = null
	tgt["talking"] = 0
	tgt["space"] = pl.get("space", "town")
	tgt["floor"] = pl.get("floor", "outdoor")
	Sim._move_agent(tgt, pl["pos"] + Vector2i(1, 0))
	return Sim.player_act("greet", String(tgt["id"])) == ""

# ── 工具 ────────────────────────────────────────────────────────────────────
func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("  ✅ " + msg)
	else:
		print("  ❌ " + msg)
		_fail += 1

## 目标状态的可比快照（只取会被断言的字段，避免比到 title/hint 这类纯呈现字符串）。
func _snap(g) -> Array:
	var out: Array = []
	for s in g.state:
		out.append([String(s["id"]), int(s["progress"]), bool(s["done"]), int(s["done_tick"]), int(s["done_ev"])])
	return out

func _eq(a, b) -> bool:
	return _eq_snap(_snap(a), _snap(b))

func _eq_snap(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		var x: Array = a[i]
		var y: Array = b[i]
		for j in x.size():
			if x[j] != y[j]:
				return false
	return true

func _env(key: String, dflt: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else dflt

func _parse_seeds(spec: String) -> Array:
	var out: Array = []
	if spec.contains("-"):
		var p := spec.split("-")
		for s in range(int(p[0]), int(p[1]) + 1):
			out.append(s)
	else:
		for s in spec.split(","):
			out.append(int(s))
	return out
