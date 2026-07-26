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

	var probe := GoalsScript.new()
	if not probe.load_defs():
		print("❌ 读不到 data/goals.json（或表为空）")
		get_tree().quit(1)
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

	print("")
	if _fail == 0:
		print("✅ 小镇纪事验收全绿（%d seed × %d 天）" % [seeds.size(), days])
	else:
		print("❌ 小镇纪事验收 %d 条断言失败" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

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
