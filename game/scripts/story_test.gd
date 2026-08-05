extends Node
## story_test.gd — 「小镇故事」(scripts/Story.gd) 的验收门。docs/47 §二-E2 的验收在此机器化。
##
## 用法：godot --headless --path game res://scenes/story_test.tscn -- [--seeds 1-12] [--days 14] [--stats]
##
## ── 为什么先写 F 段（合成 fixture）再写 A 段（真世界） ──────────────────────
## D2 的回执把话说死了：`live == replay` **一个什么都不记的 tracker 平凡通过**，
## 「每个 seed 至少 N 条」**一个在第 1 天全部点亮的坏设计也满分**。两条都没有判别力。
## 所以本门的**牙齿**在 F 段：五组手写的合成事件流，每组都有**唯一正确的答案**，且互相构成对照 ——
##   F1  只喂 greet（200 条） → 故事数**必须是 0**。（挡住"什么都开一条弧"）
##   F2  手写一条完整因果链   → 必须恰好 1 条 grudge、结局 mended、幕次与旁支计数逐项对上。（挡住"什么都不开"）
##   F3  一段怨气之后长期无下文 → 必须以 **cold** 收场，且收场日 = 最后一幕 + cold，不随"发现它冷了"的时刻漂；
##   F3′ 反过来：cold 之内**不许**判死。（挡住阈值写成 0 / 单位写错）
##   F4  爽约支 invite+ → meet- → 结局必须是 **broken** 而不是 kept。（挡住"结局只认一个分支"）
##   F5  泄密支 / 盟约散伙支的正对照 —— 这两支在默认沙盘 60 天里**一次都不发生**，
##       没有 F5 的话"0 段"读作"世界没给机会"还是"文法是死的"根本分不开。
## A 段（真世界 12 seed）验的是另一件事：这套折叠在**真实事件流**上仍然是纯函数（增量≡全量≡回放）。
##
## ── A 段四条臂（每个 seed 各跑一遍；顺序有意义，与 goals_test 同构）────────
##   A0 无故事基线 —— 完全不碰 Story 地跑完，记下 Inv.digest / event_digest / 事件数。
##   A1 实时臂     —— 同种子重跑，每 tick 调一次 story.sync(Sim.event_log)（与 Main._on_tick 同一条路）。
##        断言 A1 的 Inv.digest / event_digest 与 A0 **逐字节相同** ⇒ 没写世界状态、没改 event_log 任何字段。
##   A2 重算臂     —— 对**同一份** event_log 从空态全量折一遍，断言 == A1（增量折 ≡ 全量折）。
##   A3 回放臂     —— Sim.goto_tick(T) 之后重算 == A1；再 goto_tick(T/2) 与实时臂 T/2 的快照对拍。
##        ★这就是「它留在 View 侧」的机器证明：同一份存档沿不同观看路径回放，故事必须一模一样。
##   断言比的是 (digest, chain, 逐弧快照) 三样，不是只比 digest。

const Inv = preload("res://bench/Invariants.gd")
const StoryScript = preload("res://scripts/Story.gd")

var _fail := 0

func _ready() -> void:
	var seeds := _parse_seeds(_env("CI_STORY_SEEDS", "1-12"))
	var days := int(_env("CI_STORY_DAYS", "14"))
	var stats := false
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])
		elif args[i] == "--stats":
			stats = true
		elif args[i] == "--agents" and i + 1 < args.size():
			# 出货目标是最多 60 居民（红线#3）。弧数随对数 ~O(N²) 涨，MAX_CLOSED 在那一档会真的咬人（第一版封"弧总数"的写法就是在这里被打死的，见 Story.MAX_CLOSED），
			# 而"裁剪之后 live 仍 ≡ replay"正是最容易被裁剪逻辑写坏的一条 —— 所以这一档必须能跑。
			# CI 默认不带（12 居民），本旗标只给手跑的规模验证用。
			Sim.spawn_count = int(args[i + 1])

	var w1_only := false
	for i in args.size():
		if args[i] == "--w1-only":
			w1_only = true

	print("小镇故事验收：%d 种弧 · seeds=%s · %d 天" % [StoryScript.ARCS.size(), str(seeds), days])
	if w1_only:
		_w1()
		print("")
		print("✅ W1 段全绿" if _fail == 0 else "❌ W1 段 %d 条断言失败" % _fail)
		get_tree().quit(1 if _fail > 0 else 0)
		return
	_fixtures()

	var total := int(days) * int(Sim.TICKS_PER_DAY)
	var half := total / 2
	var rows: Array = []
	var cov: Dictionary = {}
	for sd in seeds:
		# ── A0 无故事基线 ───────────────────────────────────────────────
		Sim.backend = null                 # 红线#2：零模型地板；本门只验 View 侧派生，与后端无关
		Sim.record_decisions = false
		Sim.auto_run = false
		Sim.start_new(sd)
		for t in range(total):
			Sim.tick()
		var d0 := Inv.digest(Sim)
		var ed0 := Sim.event_digest
		var n0 := Sim.event_log.size()

		# ── A1 实时臂 ───────────────────────────────────────────────────
		var live := StoryScript.new()
		Sim.start_new(sd)
		var snap_half := {}
		for t in range(total):
			Sim.tick()
			live.sync(Sim.event_log)
			if Sim.tick_no == half:
				snap_half = {"digest": live.digest(), "chain": live.chain, "snap": _snap(live)}
		var d1 := Inv.digest(Sim)
		_expect(d0 == d1 and ed0 == Sim.event_digest and n0 == Sim.event_log.size(),
			"seed %d · A0≡A1 零扰动（Inv %d/%d · event_digest %d/%d · 事件 %d/%d）" % [
				sd, d0, d1, ed0, Sim.event_digest, n0, Sim.event_log.size()])

		# ── 覆盖率：镇上**真的发生过**的了结，有几件被系进了一段故事？────────
		# 这条指标是自曝短板用的：一段弧冷场收摊之后，后来的 apologize+ 就没处安放了（fold 不回头）。
		# 只报"讲出了 N 段和解"是好看的，报"全镇 M 次和解里讲到了 N 次"才是诚实的。
		# ★必须在 A3 之前数：A3 会 goto_tick(half) 把 event_log 截短一半（第一版就栽在这里，
		#   量出 "apologize+ 3 次 → 讲成 28 段 = 933%" 这种一眼就知道分母坏了的数）。
		var nconf := 0
		for e in Sim.event_log:
			var ty := String(e.get("type", ""))
			var okk := bool(e.get("accepted", false))
			if ty == "conflict":
				nconf += 1
			if ty == "apologize" and okk:
				cov["apologize+"] = int(cov.get("apologize+", 0)) + 1
			elif ty == "meet":
				cov["meet"] = int(cov.get("meet", 0)) + 1
			elif ty == "invite" and okk:
				cov["invite+"] = int(cov.get("invite+", 0)) + 1
			elif ty == "invite":
				cov["invite-"] = int(cov.get("invite-", 0)) + 1
			elif ty == "conflict":
				cov["conflict"] = int(cov.get("conflict", 0)) + 1
			elif ty == "confide":
				cov["confide"] = int(cov.get("confide", 0)) + 1
			elif ty == "betray" or ty == "leak":
				cov[ty] = int(cov.get(ty, 0)) + 1

		# ── 可追溯性审计（W3，docs/90 §三）：屏幕上的每一行都要指得回一条真事件 ──
		# ★位置是被踩出来的，不是随手放的：**必须在 A3 之前**。A3 会 `goto_tick(half)` 把 event_log
		#   截短一半，之后再审计，一半的引用会因为"事件不存在"而报假红 —— 与上面 §覆盖率 那条
		#   "必须在 A3 之前数"是同一个坑的第二次发作（我第一版就放到了 A3 后面，被这条注释救回来）。
		# 判据本身：`narrate_cited()` 是**唯一**的成文入口（`narrate()` 只是它的壳），
		#   于是"屏幕上的每一行"与"被审计的每一行"在构造上是同一批，没有旁路。
		var by_id: Dictionary = {}
		for e in Sim.event_log:
			by_id[int(e.get("id", -1))] = e
		var bad: Array = []
		var lines := 0
		for arc in live.arcs:
			lines += live.narrate_cited(arc, _nm).size()
			bad.append_array(live.audit(arc, by_id))
		_expect(bad.is_empty() and lines > 0,
			"seed %d · 可追溯：%d 条弧共 %d 行叙述逐行回 event_log 核出处 —— 违规 %d 条%s" % [
				sd, live.arcs.size(), lines, bad.size(), ("" if bad.is_empty() else "：" + str(bad.slice(0, 3)))])

		# ── A2 重算臂 ───────────────────────────────────────────────────
		var recomp := StoryScript.new()
		recomp.recompute(Sim.event_log)
		_expect(recomp.digest() == live.digest() and recomp.chain == live.chain and _eq(_snap(live), _snap(recomp)),
			"seed %d · A1≡A2 增量折 ≡ 全量折（digest %d/%d · chain %d/%d · 弧 %d/%d）" % [
				sd, live.digest(), recomp.digest(), live.chain, recomp.chain, live.arcs.size(), recomp.arcs.size()])

		# ── A3 回放臂 ───────────────────────────────────────────────────
		Sim.goto_tick(total)
		var rep := StoryScript.new()
		rep.recompute(Sim.event_log)
		_expect(rep.digest() == live.digest() and rep.chain == live.chain and _eq(_snap(live), _snap(rep)),
			"seed %d · A1≡A3 回放安全 @T=%d（digest %d/%d · chain %d/%d）" % [
				sd, total, live.digest(), rep.digest(), live.chain, rep.chain])
		Sim.goto_tick(half)
		var rep2 := StoryScript.new()
		rep2.recompute(Sim.event_log)
		_expect(not snap_half.is_empty()
				and rep2.digest() == int(snap_half["digest"]) and rep2.chain == int(snap_half["chain"])
				and _eq(snap_half["snap"], _snap(rep2)),
			"seed %d · A1≡A3 回放安全 @T/2=%d（digest %d/%s · chain %d/%s）" % [
				sd, half, rep2.digest(), str(snap_half.get("digest", "n/a")),
				rep2.chain, str(snap_half.get("chain", "n/a"))])

		# ── 账本自洽（裁剪一开始咬人，这两条就是唯一能发现的地方）────────
		var st: Dictionary = live.stats()
		_expect(live.open_count() + live.closed_count() == live._serial,
			"seed %d · 账本自洽：进行中 %d + 终身收场 %d == 开过 %d 段（裁掉 %d 段不影响这条）" % [
				sd, live.open_count(), live.closed_count(), live._serial, live._dropped])
		_expect(int((st["grudge"] as Dictionary)["opened"]) == int(nconf),
			"seed %d · grudge 开场数 %d == event_log 里的 conflict 事件数 %d（1:1，没有被吞掉的开头）" % [
				sd, int((st["grudge"] as Dictionary)["opened"]), nconf])

		# ── 故事线本身（打出来看，不只看一个绿字）────────────────────────
		rows.append({"seed": sd, "st": st, "open": live.open_count(), "closed": live.closed_count(),
			"arcs": live.arcs.size(), "drop": live._dropped})
		if stats:
			print("  —— seed %d 最近收场的三段 ——" % sd)
			var cl: Array = live.recent_closed()      # 与面板同一个取法（纯按最近取会打出三段"约了→见了"，那不是面板会讲的东西）
			for i in mini(3, cl.size()):
				for ln in live.narrate(cl[i], _nm):
					print("     " + _plain(ln))
				print("")

	# ── 逐 seed × 逐弧种矩阵 ────────────────────────────────────────────────
	print("\n逐 seed 故事矩阵（%d 天）· 每格 = 进行中/已收场（**终身口径**，含被裁掉的）" % days)
	var ids: Array = []
	for d in StoryScript.ARCS:
		ids.append(String(d["id"]))
	var hdr := "seed  "
	for id in ids:
		hdr += "%-9s" % id
	print(hdr + " 合计(开/收) 裁剪")
	for r in rows:
		var line := "%4d  " % int(r["seed"])
		for id in ids:
			var row: Dictionary = (r["st"] as Dictionary)[id]
			line += "%-9s" % ("%d/%d" % [int(row["open"]), int(row["closed"])])
		line += " %d/%d      %d" % [int(r["open"]), int(r["closed"]), int(r["drop"])]
		print(line)
	# 结局分布：这才是"有没有讲出不同结局"看得见的地方（全一个结局 = 分支是死的）
	print("\n结局分布（%d seed 合计）：" % rows.size())
	for id in ids:
		var agg: Dictionary = {}
		var op := 0
		for r in rows:
			var row: Dictionary = (r["st"] as Dictionary)[id]
			op += int(row["open"])
			for e in (row["ends"] as Dictionary):
				agg[e] = int(agg.get(e, 0)) + int(row["ends"][e])
		var parts: Array = []
		var ek: Array = agg.keys(); ek.sort()
		for e in ek:
			parts.append("%s=%d" % [e, int(agg[e])])
		print("  %-8s 进行中 %-4d  %s" % [id, op, ("  ".join(PackedStringArray(parts)) if not parts.is_empty() else "（无收场）")])

	# 覆盖率（自曝短板）：镇上真的发生过的了结 vs 被讲进故事的了结
	var mended := 0
	var kept := 0
	var broken := 0
	var leaked := 0
	for r in rows:
		mended += int(((r["st"] as Dictionary)["grudge"]["ends"] as Dictionary).get("mended", 0))
		kept += int(((r["st"] as Dictionary)["promise"]["ends"] as Dictionary).get("kept", 0))
		broken += int(((r["st"] as Dictionary)["promise"]["ends"] as Dictionary).get("broken", 0))
		leaked += int(((r["st"] as Dictionary)["secret"]["ends"] as Dictionary).get("leaked", 0))
	print("\n覆盖率（真实事件 → 被系进故事的那一份；分母是 event_log 里数出来的）：")
	print("  和解  apologize+ %d 次 → 讲成 mended %d 段（%s）" % [
		int(cov.get("apologize+", 0)), mended, _pct(mended, int(cov.get("apologize+", 0)))])
	print("  约定  invite+ %d / invite- %d · meet %d 次 → 讲成 kept %d + broken %d 段（%s）" % [
		int(cov.get("invite+", 0)), int(cov.get("invite-", 0)), int(cov.get("meet", 0)), kept, broken,
		_pct(kept + broken, int(cov.get("meet", 0)))])
	print("  心事  confide %d 次 · betray %d · leak %d → 讲成 leaked %d 段" % [
		int(cov.get("confide", 0)), int(cov.get("betray", 0)), int(cov.get("leak", 0)), leaked])
	print("  梁子  conflict %d 次（= grudge 弧的开头数，必然 1:1）" % int(cov.get("conflict", 0)))

	# W1 段放最后：它会开玩家、换后端、动世界，跑完不该有别的臂再读那份世界。
	_w1()

	print("")
	if _fail == 0:
		print("✅ 小镇故事验收全绿（fixture 6 组 + %d seed × %d 天）" % [seeds.size(), days])
	else:
		print("❌ 小镇故事验收 %d 条断言失败" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

# ── F 段：合成 fixture（本门的判别力都在这里）──────────────────────────────
func _fixtures() -> void:
	_fixture_trim()
	print("\n[F] 合成对照 —— 每条都有唯一正确答案")
	# F1 只喂 greet：一个"什么都开一条弧"的追踪器会在这里爆掉，而 live==replay 是照过的。
	var f1: Array = []
	for i in 200:
		f1.append(_ev(i, i * 3, "greet", "aria", "ben", true))
	var s1 := StoryScript.new()
	s1.recompute(f1)
	_expect(s1.arcs.size() == 0 and s1.chain != 0,
		"F1 只喂 200 条 greet → 故事 %d 条（必须 0）· chain=%d（必须非 0，证明它确实折了这 200 条）" % [s1.arcs.size(), s1.chain])

	# F2 手写一条完整因果链：aria 怨 ben → 当面挑明 → ben 道歉被拒 → 再道歉被接受；期间 aria 议论 ben 三次。
	var f2: Array = [
		_ev(0, 100, "conflict", "aria", "ben", false),
		_ev(1, 130, "gossip_rep", "aria", "coco", false, "ben"),
		_ev(2, 160, "gossip_rep", "aria", "dan", false, "ben"),
		_ev(3, 200, "confront", "aria", "ben", true),
		_ev(4, 220, "apologize", "ben", "aria", false),
		_ev(5, 240, "gossip_rep", "aria", "coco", false, "ben"),
		_ev(6, 300, "apologize", "ben", "aria", true),
	]
	var s2 := StoryScript.new()
	var fresh2 := s2.recompute(f2)
	var ok2 := s2.arcs.size() == 1
	var a2: Dictionary = s2.arcs[0] if ok2 else {}
	ok2 = ok2 and String(s2.def_of(a2)["id"]) == "grudge" and String(a2["end"]) == "mended" \
		and int(a2["t0"]) == 100 and int(a2["t1"]) == 300 and int(a2["aside"]) == 3 \
		and (a2["beats"] as Array).size() == 2 and String((a2["beats"] as Array)[0][0]) == "heard" \
		and String((a2["beats"] as Array)[1][0]) == "rebuff" and fresh2.size() == 1
	_expect(ok2, "F2 手写因果链 → 1 条 grudge/mended/幕=[heard,rebuff]/旁支=3/第%s→%s tick（实得 %d 条 · %s · 幕%s · 旁支%d · %s→%s）" % [
		"100", "300", s2.arcs.size(), String(a2.get("end", "-")),
		str(_beat_ids(a2)), int(a2.get("aside", -1)), str(a2.get("t0", -1)), str(a2.get("t1", -1))])
	# 成文不许出现原始英文 id / 占位符残留（D2 的 R10 教训：屏幕上的字也要被断言）
	var prose := " ".join(PackedStringArray(s2.narrate(a2, _nm_fake)))
	_expect(not prose.contains("%A") and not prose.contains("%B") and not prose.contains("%d")
			and prose.contains("解开了"),
		"F2 成文无占位符残留且讲出了结局：%s" % _plain(prose).replace("\n", " / "))
	# 增量折 ≡ 全量折（合成流上也要成立，且这里的分岔比真世界更容易看清）
	var s2b := StoryScript.new()
	for i in f2.size():
		s2b.sync(f2.slice(0, i + 1))
	_expect(s2b.digest() == s2.digest() and s2b.chain == s2.chain, "F2 逐条增量折 ≡ 全量折")

	# F3 冷场：一段怨气之后 cold 内无下文，很久以后来了一件**别人的**事 → 它必须以 cold 收场，
	#    且收场时刻 = 最后一幕 + cold，**不是**"发现它冷了的那一刻"（否则同一段历史在不同的事件疏密下收场日会漂）。
	#    阈值从 Story.ARCS 里读，不抄第二份 —— 抄一份就等着有人改了一处忘了另一处。
	var cold: int = int((StoryScript.ARCS[0] as Dictionary)["cold"])
	var f3: Array = [
		_ev(0, 100, "conflict", "aria", "ben", false),
		_ev(1, 100 + cold * 2, "greet", "coco", "dan", true),
	]
	var s3 := StoryScript.new()
	s3.recompute(f3)
	var ok3 := s3.arcs.size() == 1 and String(s3.arcs[0]["end"]) == "cold" and int(s3.arcs[0]["t1"]) == 100 + cold
	_expect(ok3, "F3 无下文 → cold 收场于 tick %d（最后一幕+cold=%d，不随发现时刻 %d 漂）；实得 %d 条 · %s · t1=%s" % [
		100 + cold, cold, 100 + cold * 2,
		s3.arcs.size(), String(s3.arcs[0]["end"]) if s3.arcs.size() > 0 else "-",
		str(s3.arcs[0]["t1"]) if s3.arcs.size() > 0 else "-"])
	# 负半边：cold 之内的下文**不许**被判死（挡住"阈值写成 0 / 单位写错"这类改坏）。
	var s3b := StoryScript.new()
	s3b.recompute([_ev(0, 100, "conflict", "aria", "ben", false), _ev(1, 100 + cold - 1, "greet", "coco", "dan", true)])
	_expect(s3b.arcs.size() == 1 and not bool(s3b.arcs[0]["closed"]),
		"F3′ cold 之内（%d tick）不许判死：仍在进行中 = %s" % [cold - 1, str(s3b.arcs.size() == 1 and not bool(s3b.arcs[0]["closed"]))])

	# F4 爽约支：invite+ → meet- 必须收成 broken；同一份流里再加一条 invite+ → meet+ 收成 kept。
	var f4: Array = [
		_ev(0, 10, "invite", "aria", "ben", true),
		_ev(1, 50, "meet", "aria", "ben", false),
		_ev(2, 60, "invite", "coco", "dan", true),
		_ev(3, 90, "meet", "coco", "dan", true),
	]
	var s4 := StoryScript.new()
	s4.recompute(f4)
	var ends4: Array = []
	for arc in s4.arcs:
		ends4.append(String(arc["end"]))
	_expect(ends4 == ["broken", "kept"], "F4 两条约定分别收成 [broken, kept]（实得 %s）" % str(ends4))

	# F5 「泄密」与「盟约散伙」两支的**正对照**。
	# ★为什么非要有它：默认沙盘 6 seed × 60 天里 betray/leak/pact-dissolved 一次都不发生
	#   （见报告的结局分布：secret 开 47 段收 0 段、pact 开 24 段收 0 段）。
	#   那个 0 既可以读作"这个镇子上没人背叛"，也可以读作"我这两支文法根本是死的" —— 两种读法在真世界数据上无法分辨。
	#   本 fixture 把它分开：文法是活的，**是世界没给它机会**。
	#   顺带钉死两处方向：betray 的 actor 是【说漏的人】、target 是【被辜负的人】（与 confide 相反）；
	#   pact dissolved 的 actor 是【受害方】，与 formed 未必同序 ⇒ 必须 dir=any（这里故意写成反序）。
	var f5: Array = [
		_ev(0, 10, "confide", "aria", "ben", false, "S_aria"),
		_ev(1, 20, "aid", "ben", "aria", true),
		_ev(2, 40, "betray", "ben", "aria", true, "S_aria", "leaked"),
		_ev(3, 50, "pact", "coco", "dan", true, "", "formed"),
		_ev(4, 60, "aid", "dan", "coco", true),
		_ev(5, 70, "pact", "dan", "coco", false, "", "dissolved:freerider"),
	]
	var s5 := StoryScript.new()
	s5.recompute(f5)
	var got5: Array = []
	for arc in s5.arcs:
		got5.append("%s/%s/%d幕" % [String(s5.def_of(arc)["id"]), String(arc["end"]), (arc["beats"] as Array).size()])
	_expect(got5 == ["secret/leaked/1幕", "pact/dissolved/1幕"],
		"F5 泄密支与散伙支都认得（含反序的 dissolved）：实得 %s" % str(got5))

	# ── W3 新增（docs/90）────────────────────────────────────────────────────
	# F6「手艺」弧：一条 produce 被两个人看见 ⇒ **两条**独立的弧（本文件里唯一的一对多），
	#    且两条各自走到不同的结局（扑空 / 结盟）。它同时钉死 PAIR_WIT 的方向：
	#    A=看见的人、B=干活的人 —— 反过来的话 shortage 与 gossip_rep 两条都会落空。
	var f6: Array = [
		_ev(0, 100, "produce", "aria", "town", true, "柴薪", "樵夫*3", ["ben", "coco"]),
		_ev(1, 200, "produce", "aria", "town", true, "柴薪", "樵夫*3", ["ben"]),
		_ev(2, 240, "gossip_rep", "ben", "dan", false, "aria"),      # 旁支：ben 在 dan 面前提起 aria
		_ev(3, 300, "shortage", "ben", "aria", false, "柴薪", "吃饭"),
		_ev(4, 320, "pact", "aria", "coco", true, "", "formed"),     # 故意反序：dir=any 才认得
	]
	var s6 := StoryScript.new()
	s6.recompute(f6)
	var got6: Array = []
	for arc in s6.arcs:
		got6.append("%s/%s>%s/%s/%d幕/旁%d" % [String(s6.def_of(arc)["id"]), String(arc["a"]), String(arc["b"]),
			String(arc["end"]), (arc["beats"] as Array).size(), int(arc["aside"])])
	_expect(got6 == ["craft/ben>aria/failed/1幕/旁1", "craft/coco>aria/allied/0幕/旁0", "pact/aria>coco//0幕/旁0"],
		"F6 一条 produce 两个目击者 → 两条手艺弧，分别以扑空/结盟收场：实得 %s" % str(got6))
	# F6′ 没有目击者的 produce（= `craft_credit` 未开或无人在场）**一条弧都不许开**。
	#    这是 V1 回滚路径的机器证明：删掉那个 JSON 键 ⇒ witnesses 恒空 ⇒ 本弧自动消失。
	var s6b := StoryScript.new()
	s6b.recompute([_ev(0, 100, "produce", "aria", "town", true, "柴薪", "樵夫*3"),
		_ev(1, 200, "produce", "aria", "town", true, "柴薪", "樵夫*3")])
	_expect(s6b.arcs.size() == 0,
		"F6′ produce 无目击者 → 手艺弧 %d 条（必须 0；这就是 craft_credit 关掉后的样子）" % s6b.arcs.size())

	# F7「说和」：玩家的两种介入都必须在故事里看得见。
	#    调解失败只写一条 mediate（actor="player" 是非居民，当事两人在 target/subject ⇒ PAIR_TS）；
	#    调解成功补记的 confront/apologize 带 note="mediated" ⇒ 必须走 mediated 那两条，**不是** heard/mended。
	var f7: Array = [
		_ev(0, 100, "conflict", "aria", "ben", false),
		_ev(1, 150, "mediate", "player", "aria", false, "ben"),
		_ev(2, 200, "confront", "aria", "ben", true, "", "mediated"),
		_ev(3, 210, "endorse", "coco", "dan", true, "ben"),          # 负对照：(coco,ben) 上没有弧 ⇒ 不许算进来
		_ev(4, 220, "endorse", "aria", "coco", true, "ben"),         # 幕 sided：pair=subject ⇒ (aria,ben)
		_ev(5, 300, "apologize", "ben", "aria", true, "", "mediated"),
	]
	var s7 := StoryScript.new()
	s7.recompute(f7)
	var ok7 := s7.arcs.size() == 1
	var a7: Dictionary = s7.arcs[0] if ok7 else {}
	ok7 = ok7 and String(a7["end"]) == "mediated" and _beat_ids(a7) == ["tried", "mediated", "sided"]
	_expect(ok7, "F7 玩家说和：1 条 grudge/mediated/幕=[tried,mediated,sided]（实得 %d 条 · %s · %s）" % [
		s7.arcs.size(), String(a7.get("end", "-")), str(_beat_ids(a7))])
	var pr7 := " ".join(PackedStringArray(s7.narrate(a7, _nm_fake)))
	_expect(pr7.contains("在你的说和下") and not pr7.contains("%A") and not pr7.contains("%B"),
		"F7 成文里玩家出场了：%s" % _plain(pr7).replace("\n", " / "))

	# F8「说漏嘴」这一支**今天是够不着的**——把它钉下来，别让"0 段"继续读作"世界没给机会"。
	#    `leak` 事件是 (说漏的人 → 听的人)，而秘密的主人只在 `beliefs[...]["owner"]` 里、**不在事件上**
	#    （Sim.gd:2435）。于是 `slipped` 的 dir=rev 查的是 (听的人 → 说漏的人)，
	#    只有"说漏给主人本人听"这一种退化情形才对得上。修它要 Sim 侧把 owner 写进事件 ⇒ 不在本棒的行里。
	#    ⇒ 本 fixture 断言的是**现状**：泄密给第三方，心事弧仍然开着。它红了 = 有人修好了，请回来改这条。
	var s8 := StoryScript.new()
	s8.recompute([_ev(0, 10, "confide", "aria", "ben", false, "S_aria"),
		_ev(1, 40, "leak", "ben", "coco", true, "S_aria")])
	_expect(s8.arcs.size() == 1 and not bool(s8.arcs[0]["closed"]),
		"F8 泄密给第三方 → `slipped` 结局**够不着**（心事弧仍开着 = %s）；见 docs/90 的已知边界" % str(
			s8.arcs.size() == 1 and not bool(s8.arcs[0]["closed"])))

	# F9 审计自身有没有牙 —— 先自证，再拿去守真世界（同 F-trim「fixture 有效性先自证」那条纪律）。
	#    真世界那道断言（A 段）只会说"0 违规"，而**一个什么都不查的 audit 也会说 0 违规**。
	var by9: Dictionary = {}
	for e in f2:
		by9[int((e as Dictionary)["id"])] = e
	var s9 := StoryScript.new()
	s9.recompute(f2)
	_expect(s9.audit(s9.arcs[0], by9).is_empty(), "F9a 未动手脚的弧 → 审计 0 违规（不许假红）")
	var m1: Dictionary = (s9.arcs[0] as Dictionary).duplicate(true)
	(m1["beats"] as Array)[0][2] = 99999
	_expect(not s9.audit(m1, by9).is_empty(), "F9b 幕指向一条不存在的 event → 审计必红")
	var m2: Dictionary = (s9.arcs[0] as Dictionary).duplicate(true)
	m2["a"] = "coco"
	_expect(not s9.audit(m2, by9).is_empty(), "F9c 把弧系到第三个人身上（引用还都在）→ 审计必红")
	var m3: Dictionary = (s9.arcs[0] as Dictionary).duplicate(true)
	m3["aside"] = 99
	_expect(not s9.audit(m3, by9).is_empty(), "F9d 旁支虚报次数（引用只有 3 条）→ 审计必红")
	var m4: Dictionary = (s9.arcs[0] as Dictionary).duplicate(true)
	(m4["beats"] as Array)[0][1] = 12345
	_expect(not s9.audit(m4, by9).is_empty(), "F9e 幕上印的天数与它引用的 event 的 tick 对不上 → 审计必红")
	_phrase_lock()
	print("")

# ── PL 段：措辞锁（Y3，docs/98 §三）─────────────────────────────────────────
## **这一段存在的全部理由是 W3 自己写下的那条边界**（docs/90 §七 的 `M2`）：
## 把 grudge 与 pact 的开头文案对调 ⇒ 屏幕上逐字打出「阿丽 与 本 结成了互助盟约 …
## 这段梁子解开了」，而审计 **0 违规、整门 rc=0 全绿**。
## ⇒ 那道审计守的是"有依据"，不是"说得对"。措辞锁把这条边界往前挪了**有限的一段**，
##   而这一段自己的边界（`does_not_detect`）就是下面 PL3 量出来的那个比率。
func _phrase_lock() -> void:
	print("\n[PL] 措辞锁 —— 往「说得对」那一侧挪的一步（判据的真值取自事件自己的 type）")

	# ── PL1 干净树自证：**不许假红** ────────────────────────────────────────
	# 同 F9a 那条纪律：一道只会说"0 违规"的门，与一个什么都不查的门在真世界上无法分辨。
	# 先证明它在**未动手脚的树上是绿的**，再拿 PL2/PL3 证明它动了手脚会红。
	var lg: Dictionary = StoryScript.lint_grammar()
	_expect((lg["bad"] as Array).is_empty(),
		"PL1 未动手脚的文法表 → 措辞锁 0 违规（不许假红）；实得 %d 条%s" % [
			(lg["bad"] as Array).size(),
			("" if (lg["bad"] as Array).is_empty() else "：" + str((lg["bad"] as Array).slice(0, 3)))])
	# 没上锁的文案**只报数不判红**：空短语表 = 没约束，那是本机制的定义域而不是缺陷。
	# 报它是为了让"锁的覆盖面"这个数字看得见，而不是靠读者去数。
	var slots := _all_slots()
	print("     文案槽位 %d 个 · 已上【措辞】锁 %d 个 · 没有任何标志性短语的 %d 个：%s" % [
		slots.size(), slots.size() - (lg["unlocked"] as Array).size(), (lg["unlocked"] as Array).size(),
		str((lg["unlocked"] as Array).slice(0, 4))])
	# AA2：极性锁的覆盖面单独报 —— 它按定义只盖得住"仿真侧有字段能把两条文案分开"的那些槽位，
	# 报出来是为了让"盖了多少"这个数看得见，而不是靠读者去数（同上面那条的理由）。
	print("     其中带【极性】锁的 %d 个（accepted / note 两维；仿真侧没有字段可分的槽位盖不住，见 docs/105）" % [
		int(lg.get("pol_locked", 0))])

	# ── PL2 逐字复现 W3 的 M2 ──────────────────────────────────────────────
	# W3 那个变异体是"把 grudge 与 pact 的 open_text 对调"。对调之后：
	#   grudge 的开头会打出 pact 的话，而它引用的仍然是一条 **conflict**；
	#   pact 的开头会打出 grudge 的话，而它引用的仍然是一条 **pact**。
	# `_audit_one` 的第⑤条查的正是 `phrase_conflicts(模板, [事件真实type])` —— 这里逐字调它。
	var g_open := ""
	var p_open := ""
	for d in StoryScript.ARCS:
		if String(d["id"]) == "grudge":
			g_open = String(d["open_text"])
		elif String(d["id"]) == "pact":
			p_open = String(d["open_text"])
	var m2a: Array = StoryScript.phrase_conflicts(p_open, ["conflict"])
	var m2b: Array = StoryScript.phrase_conflicts(g_open, ["pact"])
	_expect(not m2a.is_empty(),
		"PL2 W3 的 M2（梁子的开头改说盟约的话，出处仍是 conflict）→ 必红：%s" % str(m2a))
	_expect(not m2b.is_empty(),
		"PL2′ 反向对调（盟约的开头改说梁子的话，出处仍是 pact）→ 必红：%s" % str(m2b))
	# 阴性对照：同一条文案配**它自己**的类型，一条都不许响（否则 PL2 的红只是"什么都红"）。
	_expect(StoryScript.phrase_conflicts(g_open, ["conflict"]).is_empty()
			and StoryScript.phrase_conflicts(p_open, ["pact"]).is_empty(),
		"PL2″ 阴性对照：文案配回自己的类型 → 0 违规（证明 PL2 的红不是「逢查必红」）")

	# ── PL2‴ 极性锁的手写正/反对照（AA2）──────────────────────────────────
	# Y3 点名的那一条：`promise/end:kept ↔ promise/end:broken`（赴约 ↔ 爽约）。
	# 它在 Y3 的措辞锁上 **0 违规**（两者都引 meet），在极性锁上必须当场红。
	var kept_t := ""
	var broken_t := ""
	var kept_m: Dictionary = {}
	var broken_m: Dictionary = {}
	for d2 in StoryScript.ARCS:
		if String(d2["id"]) != "promise":
			continue
		for e2 in (d2["ends"] as Array):
			if String(e2["id"]) == "kept":
				kept_t = String(e2["text"]); kept_m = e2["m"]
			elif String(e2["id"]) == "broken":
				broken_t = String(e2["text"]); broken_m = e2["m"]
	_expect(StoryScript.phrase_conflicts(broken_t, kept_m.get("type", []) as Array).is_empty()
			and StoryScript.phrase_conflicts(kept_t, broken_m.get("type", []) as Array).is_empty(),
		"PL2‴-0 前提复核：赴约↔爽约对调在【措辞锁】上仍然 0 违规（Y3 的 19 条漏网之一，本条一红就说明前提变了）")
	var pol_a: Array = StoryScript.polarity_conflicts_matcher(broken_t, kept_m)
	var pol_b: Array = StoryScript.polarity_conflicts_matcher(kept_t, broken_m)
	_expect(not pol_a.is_empty() and not pol_b.is_empty(),
		"PL2‴ 赴约↔爽约对调 → 极性锁必红（双向）：%s ／ %s" % [str(pol_a), str(pol_b)])
	# 阴性对照：配回自己的匹配器，一条都不许响。
	_expect(StoryScript.polarity_conflicts_matcher(kept_t, kept_m).is_empty()
			and StoryScript.polarity_conflicts_matcher(broken_t, broken_m).is_empty(),
		"PL2⁗ 阴性对照：文案配回自己的匹配器 → 极性锁 0 违规（证明 PL2‴ 的红不是「逢查必红」）")

	# ── PL3 检出【比率】，不是一发子弹（docs/41 §2.5 外审那条度量学批评）──────
	# 外审原话：「负对照测的是 recall（这一发打中了），不是 coverage（弹药库里有多少种打不中）」。
	# 所以这里把**整个"两条文案对调"的变异空间**跑一遍：C(n,2) 个变异体，逐个问三道锁认不认。
	# 这个比率就是本机制的 `confidence`，`does_not_detect` 也是从这里的漏网名单里抄出来的。
	#
	# ★AA2 把它拆成【跨类型 / 同类型】两栏（Y3 给的规格照抄）：
	#   Y3 漏网的 19 条**无一例外全是"两条文案引用同一种事件"**，而"同类型"这件事有一个
	#   精确的机器判据 —— **两个槽位声明的 type 集合相同**。分开报，才看得出这一波买到的是哪一栏。
	var st := _mutation_stats(slots)
	var tot := int(st["tot"])
	var caught := int(st["caught"])
	var cross_tot := int(st["cross_tot"])
	var cross_caught := int(st["cross_caught"])
	var same_tot := int(st["same_tot"])
	var same_caught := int(st["same_caught"])
	var missed: Array = st["missed"]
	var same_newly: Array = st["same_newly"]
	print("     两条文案对调的**全变异空间**：%d 个变异体，三道锁合计认出 %d 个（%.1f%%）" % [
		tot, caught, 100.0 * float(caught) / float(maxi(1, tot))])
	print("       · 跨类型（两槽位 type 集合不同）：%d/%d" % [cross_caught, cross_tot])
	print("       · 同类型（两槽位 type 集合相同）：%d/%d   ← Y3 这一栏是 0/%d" % [same_caught, same_tot, same_tot])
	print("       · 各锁单独的检出（可重叠）：措辞 %d · 极性 %d · 复述 %d" % [
		int(st["lock_type"]), int(st["lock_pol"]), int(st["lock_rep"])])
	print("     同类型里被抓住的 %d 条，逐条列：" % same_caught)
	for x2 in same_newly:
		print("       ✔ " + String(x2))
	# 漏网的**逐条全列**，不给样例 —— 这一栏就是 does_not_detect，抽样等于把边界说小了。
	print("     漏网 %d 条（= does_not_detect 那一栏，跑出来的不是想出来的）：" % missed.size())
	for x in missed:
		print("       · " + String(x))
	# 非空自证：变异空间塌成 0 的话，下面每一条棘轮都会变成一句永远为真的话。
	_expect(tot > 0 and same_tot > 0,
		"PL3 变异空间非空（%d 个变异体，其中同类型 %d 个；逐次重算，不冻结字面量）" % [tot, same_tot])
	_pl3_ratchet(st)
	_pl3_named_ratchet(slots)
	_false_red_sweep(slots, st)

	# ── PL4 词表不是我一个人说了算：拿**另一份独立渲染**交叉验 ────────────────
	# W3 的原话是"判对错要有第二份文案的真值"，并判定它没有廉价的补法。
	# **那第二份真值一直在树上**：`Main._event_prose`（编年史，另一个文件、另一位作者，
	# 对同一批事件的另一份渲染）+ `Sim._verb()`（仿真自己的中文动词表）。
	# 这里用它做两件事，强弱分开记：
	#   ①**安全向（断言）**：任何一条短语都不许出现在它**不允许**的类型的独立渲染里
	#     —— 那意味着这条短语根本不是那个意思的标志，词表写错了。
	#   ②**佐证向（只报数）**：有多少条短语在独立渲染里逐字对得上。对不上不算错（用词本来就可以不同），
	#     但这个数说明了词表里有多大一块**不是本文件自说自话**。
	var prose := _prose_by_type()
	var contam: Array = []
	var corrob := 0
	for p in StoryScript.PHRASE_LOCK:
		var allow: Array = StoryScript.PHRASE_LOCK[p]
		var ok_here := false
		for t in prose:
			if not String(prose[t]).contains(String(p)):
				continue
			if String(t) in allow:
				ok_here = true
			else:
				contam.append("「%s」只允许 %s，却出现在独立渲染的 `%s` 里" % [String(p), str(allow), String(t)])
		if ok_here:
			corrob += 1
	_expect(contam.is_empty(),
		"PL4 安全向：%d 条短语无一出现在【不允许】的类型的独立渲染里（编年史 %d 类 + Sim._verb）%s" % [
			(StoryScript.PHRASE_LOCK as Dictionary).size(), prose.size(),
			("" if contam.is_empty() else "；实得 " + str(contam.slice(0, 3)))])
	print("     佐证向：%d/%d 条短语被独立渲染逐字佐证（对不上不算错——用词本来可以不同，见 docs/98）" % [
		corrob, (StoryScript.PHRASE_LOCK as Dictionary).size()])
	_polarity_cross_check()

## 把「两条文案对调」的**全变异空间**跑一遍，返回逐项统计。
##
## ★AC2 把它从 PL3 的函数体里抽出来，理由是**代价对照（PL3″）必须拿同一份算法**去跑
##   "多了一条文案"的假想树 —— 两处各写一份的话，比出来的差可能是两份实现的差，不是那条文案的差。
##   （docs/41 §5「对照要等量而非等时」的同一条纪律：先把量具配平。）
func _mutation_stats(sl: Array) -> Dictionary:
	var tot := 0
	var caught := 0
	var cross_tot := 0
	var cross_caught := 0
	var same_tot := 0
	var same_caught := 0
	var lock_type := 0                      # 每道锁**单独**能抓到几个（可重叠）
	var lock_pol := 0
	var lock_rep := 0
	var missed: Array = []
	var same_newly: Array = []
	for i in sl.size():
		for j in range(i + 1, sl.size()):
			var a: Array = sl[i]
			var b: Array = sl[j]
			if String(a[1]) == String(b[1]):
				continue                      # 两条文案本来就一样 ⇒ 对调是恒等变换，不是变异体
			tot += 1
			var same := _same_types(a[2] as Array, b[2] as Array)
			var hit_type := not StoryScript.phrase_conflicts(String(b[1]), a[2] as Array).is_empty() \
				or not StoryScript.phrase_conflicts(String(a[1]), b[2] as Array).is_empty()
			var hit_pol := not StoryScript.polarity_conflicts_matcher(String(b[1]), a[3] as Dictionary).is_empty() \
				or not StoryScript.polarity_conflicts_matcher(String(a[1]), b[3] as Dictionary).is_empty()
			var hit_rep := not StoryScript.repeat_conflicts(String(b[1]), String(a[4])).is_empty() \
				or not StoryScript.repeat_conflicts(String(a[1]), String(b[4])).is_empty()
			if hit_type:
				lock_type += 1
			if hit_pol:
				lock_pol += 1
			if hit_rep:
				lock_rep += 1
			var hit := hit_type or hit_pol or hit_rep
			if same:
				same_tot += 1
				if hit:
					same_caught += 1
					same_newly.append("%s ↔ %s  ←%s%s" % [String(a[0]), String(b[0]),
						("极性" if hit_pol else ""), ("复述" if hit_rep else "")])
			else:
				cross_tot += 1
				if hit:
					cross_caught += 1
			if hit:
				caught += 1
			else:
				missed.append("%s ↔ %s" % [String(a[0]), String(b[0])])
	return {"tot": tot, "caught": caught, "cross_tot": cross_tot, "cross_caught": cross_caught,
		"same_tot": same_tot, "same_caught": same_caught,
		"lock_type": lock_type, "lock_pol": lock_pol, "lock_rep": lock_rep,
		"missed": missed, "same_newly": same_newly}

# ── PL3′ 棘轮（AC2）：把"量得很准然后只断言 > 0"那一步补上 ────────────────────
## **本段存在的全部理由是外部评审（Codex，2026-08-02）抓到的那一条**：
## AA2 把同类型反转的检出量到 **13/19**、跨类型量到 **573/573**，**然后只断言 `caught > 0`
## 与 `same_caught > 0`** ⇒ **同类型从 13/19 退到 1/19，这道门照样绿。**
##
## ★而 AA2 那么写是**有理由的、写下来的、并且不是糊涂**（`story_test.gd:575-582` 原注释）：
##   > 具体比率写进回执，不写成阈值门 —— **写成阈值门就等着有人加一条没上锁的文案时收一次假红**
##   > （docs/41 §6「写死的绝对数」那条）。
##   **这个担心是真的**，所以本段不是"宣布 AA2 错了"，是把那个担心**量出来**再选形状。
##
## ★量的结果（PL3″ 每跑一次都重量一遍，不是我在这里写一句话）：**那条担心打中的是【比例】那一形状。**
##   「新增一条没上锁的文案」只会**往变异空间里加新的配对**，既有配对的判定一个都不动
##   ⇒ 绝对计数**单调不减**，比例**会被稀释**。⇒ 比例地板假红，绝对棘轮不假红。
##   这不是推的：PL3″ 把"这条新文案落在哪个槽位形状上"的**全部落点**扫一遍，逐个报两种形状的红/绿。
##
## ★为什么这组写死的绝对数**不是** docs/41 §6 警告的那一类，而这句话也是量出来的：
##   §6 那条警告的原话是「凡是判据里出现**写死的绝对次数/时长/帧数**，都要先想清楚
##   **它在别的机器上是什么**」，它的实例是界外层重画门 —— 按帧数计、按写死的 0 判，
##   **同一棵树在更快的机器上多跑几个 tick 就变红**。那条数是**环境的函数**。
##   本组数是 `Story.gd` 里 `ARCS` + 三张 const 表的**纯函数**：不读时钟、不读文件、不掷随机、
##   不数帧、不看 seed / 天数 / 居民数 —— `_mutation_stats` 的函数体里一个 I/O 都没有，
##   同一份字节在任何机器上给出同一组数。**"写死的绝对数"这个类别里有两种东西，§6 骂的是另一种。**
##
## ★动这组数的协议（照抄本仓库已有的文化：R12 的 `_meta.rebake_history`、art gate 的棘轮）：
##   **只有"检出真的退步了、而那是一个被接受的决定"才可以往下调**，且必须在
##   `PL3_RATCHET_HISTORY` 里补一条（日期 + 一句原因）。往下调而不留条 = 把这道门废掉。
## ⚠️ 实测值**高于**基线时本门**不红**，只打印一行"基线该往上收了" —— 棘轮只往一个方向走，
##   而一个从不上收的棘轮会烂掉，所以那一行必须刺眼。
const PL3_RATCHET := {
	"caught": 586,          # 592 个变异体里三道锁合计认出的
	"cross_caught": 573,    # 跨类型那一栏（Y3 建的措辞锁买的）
	"same_caught": 13,      # 同类型那一栏（AA2 建的极性锁 + 复述标记买的）← 评审点名的那一栏
	"lock_type": 573,       # 逐锁归因：措辞锁**单独**能抓到几个
	"lock_pol": 338,        # 极性锁单独
	"lock_rep": 35,         # 复述标记单独
}
## ⚠️ 逐锁归因（`lock_*`）不是冗余：只钉合计的话，**一道锁被削掉而另一道恰好补上**
## 会让合计不动 ⇒ 削掉的那道锁静默消失。这与 docs/41 §2.5「名字里每个词都有代码在查吗」是同一条。
const PL3_RATCHET_HISTORY := [
	"2026-08-02 AC2 立基线：592 个变异体 / 认出 586（跨类型 573/573 · 同类型 13/19；逐锁 措辞 573 · 极性 338 · 复述 35）。",
]

## ── ②b 具名棘轮：**评审点名的那 13 条，逐条按名字钉住，并钉住是哪道锁抓的** ────────
## 计数棘轮（②a）说得出"退了几个"，说不出"退的是哪一个" —— 而**这两句话的差别就是诊断**。
## 它同时补上 ②a 的一个盲区：13 = 11 极性 + 2 复述，**一道锁被削、另一道恰好补上**时合计不动。
## ⚠️ 槽位被删掉时本条**只打印不判红**（那一对已经不存在了，再断言它就是断言一件不存在的事）——
##    而"靠删槽位来消音"这条路由 ②a 的计数堵着：删一条文案 35/35 会让计数退步 ⇒ 必须走重烘。
##    **两层各自的盲区正好被对方盖住**，这是刻意的，不是冗余。
const PL3_SAME_TYPE_CAUGHT := [
	["grudge/beat:mediated", "grudge/beat:heard", "pol"],
	["grudge/beat:mediated", "grudge/beat:denied", "pol"],
	["grudge/beat:heard", "grudge/beat:denied", "pol"],
	["grudge/beat:rally", "grudge/beat:alone", "pol"],
	["grudge/beat:rebuff", "grudge/end:mediated", "pol"],
	["grudge/beat:rebuff", "grudge/end:mended", "pol"],
	["grudge/end:mediated", "grudge/end:mended", "pol"],
	["promise/end:kept", "promise/end:broken", "pol"],      # ← 评审与 Y3 都点名的那一条（赴约↔爽约）
	["promise/end:broken", "pact/beat:met", "pol"],
	["secret/open", "secret/beat:more", "rep"],
	["pact/open", "pact/end:dissolved", "pol"],
	["pact/end:dissolved", "craft/end:allied", "pol"],
	["craft/open", "craft/beat:again", "rep"],
]

func _pl3_ratchet(st: Dictionary) -> void:
	var short: Array = []
	var over: Array = []
	for k in PL3_RATCHET:
		var got := int(st[String(k)])
		var want := int(PL3_RATCHET[k])
		if got < want:
			short.append("%s %d < 基线 %d（退了 %d）" % [String(k), got, want, want - got])
		elif got > want:
			over.append("%s %d > 基线 %d" % [String(k), got, want])
	_expect(short.is_empty(),
		"PL3′ 棘轮：检出不许退步（同类型 %d/%d · 跨类型 %d/%d · 合计 %d/%d；逐锁 措辞 %d · 极性 %d · 复述 %d）%s" % [
			int(st["same_caught"]), int(st["same_tot"]), int(st["cross_caught"]), int(st["cross_tot"]),
			int(st["caught"]), int(st["tot"]),
			int(st["lock_type"]), int(st["lock_pol"]), int(st["lock_rep"]),
			("" if short.is_empty() else "\n        ❗退步：" + "\n        ❗".join(PackedStringArray(short))
				+ "\n        ⇒ 这不是「没有回归」，是有人把锁削了。若这是一个被接受的决定，"
				+ "改 PL3_RATCHET 并在 PL3_RATCHET_HISTORY 里补一条（日期 + 原因），别只改数字。")])
	if not over.is_empty():
		print("     ⚠ 棘轮基线该往上收了（实测高于基线，本门**不红**）：%s" % str(over))
		print("       ⇒ 照 PL3_RATCHET_HISTORY 的协议补一条再上收。一个从不上收的棘轮会烂掉。")

## ②b 具名棘轮：13 条逐条按名字复查，并复查是**哪道锁**抓的。
func _pl3_named_ratchet(sl: Array) -> void:
	var by_name := {}
	for s in sl:
		by_name[String((s as Array)[0])] = s
	var lost: Array = []
	var vanished: Array = []
	var wrong_lock: Array = []
	for row in PL3_SAME_TYPE_CAUGHT:
		var na := String((row as Array)[0])
		var nb := String((row as Array)[1])
		var want := String((row as Array)[2])
		if not by_name.has(na) or not by_name.has(nb):
			vanished.append("%s ↔ %s（槽位已不在表里）" % [na, nb])
			continue
		var a: Array = by_name[na]
		var b: Array = by_name[nb]
		var hit_pol := not StoryScript.polarity_conflicts_matcher(String(b[1]), a[3] as Dictionary).is_empty() \
			or not StoryScript.polarity_conflicts_matcher(String(a[1]), b[3] as Dictionary).is_empty()
		var hit_rep := not StoryScript.repeat_conflicts(String(b[1]), String(a[4])).is_empty() \
			or not StoryScript.repeat_conflicts(String(a[1]), String(b[4])).is_empty()
		var hit_type := not StoryScript.phrase_conflicts(String(b[1]), a[2] as Array).is_empty() \
			or not StoryScript.phrase_conflicts(String(a[1]), b[2] as Array).is_empty()
		var got := hit_pol or hit_rep or hit_type
		var by_want := hit_pol if want == "pol" else (hit_rep if want == "rep" else hit_type)
		if not got:
			lost.append("%s ↔ %s（对调之后三道锁一个都不响了）" % [na, nb])
		elif not by_want:
			wrong_lock.append("%s ↔ %s（原本由【%s】抓，现在改由别的锁兜住 —— 那道锁被削了）" % [na, nb, want])
	_expect(lost.is_empty() and wrong_lock.is_empty(),
		"PL3‴ 具名棘轮：评审点名的那 %d 条同类型反转逐条仍被抓、且仍由原来那道锁抓（%d 条已随槽位消失）%s" % [
			PL3_SAME_TYPE_CAUGHT.size(), vanished.size(),
			("" if lost.is_empty() and wrong_lock.is_empty()
				else "\n        ❗丢了：" + str(lost) + "\n        ❗换了锁：" + str(wrong_lock))])
	if not vanished.is_empty():
		print("     ⚠ 具名棘轮有 %d 条**只打印不判红**（槽位已不在表里）：%s" % [vanished.size(), str(vanished)])
		print("       ⇒ 靠删槽位消音这条路由 ②a 的计数棘轮堵着（删一条文案实测 35/35 会让计数退步）。")

## ── PL3″ 代价对照：把 AA2 担心的那个情形【跑出来】，而不是各执一词 ──────────────
## 情形逐字是「**有人加了一条没上锁的文案**」。它有一个精确的机器版本：
## 往 `_all_slots()` 里塞进一个**新槽位**，其文案不含任何标志性短语 / 极性短语 / 复述标记。
## **落点不止一种**（新文案声明的 type 集合、匹配器、行的 kind 都会改变结果），
## 所以这里**不挑一个样例**，而是把新槽位挂到**每一个既有槽位的形状**上各扫一遍
## —— 这就是 docs/41 §2.5 那条批评（recall 不是 coverage）在**假红**这一侧的同一个做法。
##
## 四种形状同台，逐个报"会不会因为这条新文案变红"：
##   ⓪ 现状（`> 0`）        —— AA2 那一版，什么都不会红（这正是评审抓到的）
##   ① 比例地板             —— 判占比：`caught/tot`、`same_caught/same_tot` 不许低于基线比例
##   ② 绝对棘轮（本波选的） —— 判绝对数，退步即红 + 显式重烘协议
##   ③ 两段式               —— 绝对棘轮判红 + 比例退步只警告
## ⚠️ 本段自己也必须有夹具有效性自证：若合成文案不小心撞上了某条短语，整段就退化成
##    "加了一条**上锁**的文案"，而那是另一个情形。所以先断言它真的没上锁。
const SYNTH_TEXT := "%A 和 %B 的这桩事，镇上记了一笔"

func _false_red_sweep(base: Array, st0: Dictionary) -> void:
	_expect(StoryScript._locked_phrases(SYNTH_TEXT).is_empty()
			and StoryScript._polarity_phrases(SYNTH_TEXT).is_empty()
			and StoryScript.repeat_conflicts(SYNTH_TEXT, "open").is_empty(),
		"PL3″-0 夹具自证：合成的那条新文案**真的没上锁**（措辞 %s · 极性 %s · 复述 %s 三张表都不命中）" % [
			str(StoryScript._locked_phrases(SYNTH_TEXT)), str(StoryScript._polarity_phrases(SYNTH_TEXT)),
			str(StoryScript.repeat_conflicts(SYNTH_TEXT, "open"))])
	# ── 情形 A：加一条没上锁的文案。**落点不止一种**，这里穷举三族 ──────────────
	#   A1 新文案抄某个既有槽位的（type 集合 / 匹配器 / kind）—— 35 个，覆盖表里出现过的每一种形状；
	#   A2 新文案引一种**全新的事件类型** —— 措辞锁对它一律不设防（allow 表里没有），是比例最有利的一端；
	#   A3 新文案**不声明任何事件类型** —— `phrase_conflicts` 对空 types 恒空，是比例最不利的一端。
	#   ⚠ A2/A3 是刻意加的**两端**：只扫 A1 会得出"比例地板 35/35 必假红"，而那是抄了既有匹配器
	#     这个巧合造出来的（新槽位与被抄的那个必然互不冲突 ⇒ 至少一对漏网）。**报极值要连另一端一起报。**
	var cases: Array = []
	for k in base.size():
		var src: Array = base[k]
		cases.append(["A1 抄「%s」的形状" % String(src[0]), src[2], src[3], src[4]])
	cases.append(["A2 引一种全新事件类型", ["__新事件类型__"], {"type": ["__新事件类型__"]}, "beat"])
	cases.append(["A3 不声明任何事件类型", [], {}, "beat"])
	var rows: Array = []
	for c2 in cases:
		var sl: Array = base.duplicate()
		sl.append(["＋新增", SYNTH_TEXT, c2[1], c2[2], c2[3]])
		rows.append([String(c2[0]), _mutation_stats(sl)])
	_shape_table("A · 加一条没上锁的文案（%s）" % SYNTH_TEXT, st0, rows, true)

	# ── 情形 B：删掉一条既有文案（弧改版、幕合并——同样是"正当改动"）───────────────
	# 它是情形 A 的镜像，而**镜像那一侧才是绝对棘轮真正要付的价**。不报它 = 只报对自己有利的一半。
	var rows_b: Array = []
	for k in base.size():
		var sl2: Array = base.duplicate()
		sl2.remove_at(k)
		rows_b.append(["B 删掉「%s」" % String((base[k] as Array)[0]), _mutation_stats(sl2)])
	_shape_table("B · 删掉一条既有文案", st0, rows_b, false)

	# ── 情形 C：把一条既有文案**改写**成没上锁的（换措辞、去掉标志性短语）─────────────
	var rows_c: Array = []
	for k in base.size():
		var sl3: Array = base.duplicate()
		var old: Array = sl3[k]
		sl3[k] = [String(old[0]), SYNTH_TEXT, old[2], old[3], old[4]]
		rows_c.append(["C 改写「%s」" % String(old[0]), _mutation_stats(sl3)])
	_shape_table("C · 把一条既有文案改写成没上锁的", st0, rows_c, false)

## 四种门形状在一批假想树上的红/绿对照。`must_all_green_abs` = 这一族是否**要求**绝对棘轮全绿。
func _shape_table(title: String, st0: Dictionary, rows: Array, must_all_green_abs: bool) -> void:
	var n0 := int(st0["tot"])
	var c0 := int(st0["caught"])
	var sn0 := int(st0["same_tot"])
	var sc0 := int(st0["same_caught"])
	var red_now := 0
	var red_ratio := 0
	var red_abs := 0
	var warn_two := 0
	var lo_pct := 1e9
	var hi_pct := -1.0
	var lo := ""
	var hi := ""
	var lo_ties := 0
	var hi_ties := 0
	var abs_red_names: Array = []
	for r in rows:
		var nm := String((r as Array)[0])
		var st: Dictionary = (r as Array)[1]
		var n := int(st["tot"])
		var c := int(st["caught"])
		var sn := int(st["same_tot"])
		var sc := int(st["same_caught"])
		if not (c > 0 and sc > 0):                          # ⓪ 现状 `>0`
			red_now += 1
		var rr := (c * n0 < c0 * n) or (sc * sn0 < sc0 * sn)  # ① 比例地板（交叉相乘，不走浮点）
		if rr:
			red_ratio += 1
		# ② 绝对棘轮。★这一列拿【本树自己的基线 st0】比，**不是**拿 `PL3_RATCHET` 比 ——
		#   否则一棵已经退步的树会让这一整段跟着红一遍，而那只是 PL3′ 的红被复读了一次、不是新证据。
		#   （docs/105 §五 就地记过这个记账坑：`PL2‴` 在 M4 上"也红了"，但抓住 M4 的不是它。
		#     实测：`norep` 变异体上本段原先跟着红，去掉这一处误比之后只有 PL3′/PL3‴ 红。）
		#   在**未退步**的树上 `st0 == PL3_RATCHET`，两种比法逐位同值 ⇒ 这不是放松，是去掉一次重复计数。
		var ra := false
		for kk in PL3_RATCHET:
			if int(st[String(kk)]) < int(st0[String(kk)]):
				ra = true
		if ra:
			red_abs += 1
			if abs_red_names.size() < 3:
				abs_red_names.append(nm)
		elif rr:                                             # ③ 两段式：② 判红 + ① 只警告
			warn_two += 1
		var pct := 100.0 * float(c) / float(maxi(1, n))
		if pct < lo_pct - 0.0001:
			lo_pct = pct; lo = "%s → %d/%d = %.2f%%" % [nm, c, n, pct]; lo_ties = 1
		elif absf(pct - lo_pct) <= 0.0001:
			lo_ties += 1
		if pct > hi_pct + 0.0001:
			hi_pct = pct; hi = "%s → %d/%d = %.2f%%" % [nm, c, n, pct]; hi_ties = 1
		elif absf(pct - hi_pct) <= 0.0001:
			hi_ties += 1
	print("     ── PL3″ 代价对照 · 情形 %s ── 共 %d 种落点，基线 合计 %d/%d = %.2f%% · 同类型 %d/%d = %.2f%%" % [
		title, rows.size(), c0, n0, 100.0 * float(c0) / float(maxi(1, n0)),
		sc0, sn0, 100.0 * float(sc0) / float(maxi(1, sn0))])
	print("       ⓪ 现状 `>0`      红 %d/%d" % [red_now, rows.size()])
	print("       ① 比例地板        红 %d/%d" % [red_ratio, rows.size()])
	print("       ② 绝对棘轮(本波)  红 %d/%d%s" % [red_abs, rows.size(),
		("" if abs_red_names.is_empty() else "   例：" + str(abs_red_names))])
	print("       ③ 两段式          红 %d/%d（另有 %d 次只警告）" % [red_abs, rows.size(), warn_two])
	print("       比例最低的落点：%s（并列 %d 个）｜最高：%s（并列 %d 个）" % [lo, lo_ties, hi, hi_ties])
	if must_all_green_abs:
		# 这就是本波给「别把它做成一个会因为无关改动变红的门」的机器证明（docs/41 §6）。
		# ★它同时是一条**单调性**断言：新增槽位只往变异空间里**加**配对，既有配对的判定一个都不动
		#   ⇒ 六个绝对计数只可能不减。它一旦红，说明这条结构性事实被上游改动破坏了，回来重读。
		_expect(red_abs == 0,
			"PL3″ 绝对棘轮在【新增一条没上锁的文案】的全部 %d 种落点上 0 次假红（同一批落点上比例地板 %d 次）" % [
				rows.size(), red_ratio])
		# 判别力自证：这一段若连"比例地板会假红"都量不出来，说明扫描本身空转了（同 PL5-0 那条纪律）。
		_expect(red_ratio > 0,
			"PL3″-1 扫描非空转：比例地板在这批落点上**确实**会假红 %d 次 —— 它归零 = 这段对照什么都没比" % red_ratio)

## ── PL5 极性词表的第二来源交叉验（AA2，docs/105 §二）──────────────────────
## Y3 的原话：让锁去看 `accepted` **需要 `accepted` 的第二个独立来源**，否则退回自证。
## 本段把那两个来源**按极性切开**，再拿本表逐条比：
##   ① `Main._event_prose` 的极性分支 —— `meet`/`confront`/`apologize`/`mediate`/`election`
##      的 `X if ok else Y` 三元式，与 `pact` 的 `note.begins_with("dissolved")` 分支。
##      **另一个文件、另一位作者**，而 `meet` 那条分支从 `ebac5a3`（2026-07-03）起就在，
##      比 `Story.gd`（2026-07-30）早 27 天。
##   ② `data/goals.json` 的 `title`+`hint` 与它自己的 `match/first/then` 里的极性**配成对**
##      —— 另一位作者（D2，2026-07-26）、而且是**数据不是代码**。
## 两件事，强弱分开记（与 PL4 同一套口径）：
##   **安全向（断言）**：任何一条极性短语都不许出现在**相反极性**的独立渲染里。
##   **佐证向（只报数）**：有多少条在同极性的独立渲染里逐字对得上。
func _polarity_cross_check() -> void:
	var bucket := _prose_by_polarity()
	# ── PL5-0 夹具有效性自证（同 F9a / PL1 那条纪律）───────────────────────────
	# ★本段的语料是**源码扫描**来的，而源码扫描最坏的失效方式**不是报错，是悄悄扫出一个空语料**：
	#   那样下面那句"0 条污染"就变成一句**永远为真**的话，而它读起来和真断言一模一样
	#   （docs/41 §2 第三个盲区 + §6 那条 `getbbox()` 陷阱，是同一个形状）。
	#   所以先断言四条解析路各自**真的解析到了内容**。它红了 = 上游把 `_event_prose` 的形状改了，
	#   请回来重读那段解析，别让本门静默失明。
	_expect(String(bucket["+"]) != "" and String(bucket["-"]) != ""
			and String(bucket["note:formed"]) != "" and String(bucket["note:dissolved"]) != "",
		"PL5-0 语料非空自证：编年史的 ±两支 与 pact 的 formed/dissolved 两支都解析到了内容（%d/%d/%d/%d 字符）" % [
			String(bucket["+"]).length(), String(bucket["-"]).length(),
			String(bucket["note:formed"]).length(), String(bucket["note:dissolved"]).length()])
	var contam: Array = []
	var corrob: Array = []
	var vacuous: Array = []          # 【相反极性】那一桶是空的 ⇒ 这一条的安全向检查是**空真**的
	for p in StoryScript.POLARITY_LOCK:
		var need: Dictionary = StoryScript.POLARITY_LOCK[p]
		var mine := ""
		var anti := ""
		if need.has("accepted"):
			mine = "+" if bool(need["accepted"]) else "-"
			anti = "-" if bool(need["accepted"]) else "+"
		else:
			mine = "note:" + String(need["note_prefix"])
			anti = "note:!" + String(need["note_prefix"])
		if String(bucket.get(anti, "")) == "":
			vacuous.append(String(p))
		elif String(bucket.get(anti, "")).contains(String(p)):
			contam.append("「%s」宣称 %s，却出现在独立渲染的 %s 那一支里" % [String(p), mine, anti])
		if String(bucket.get(mine, "")).contains(String(p)):
			corrob.append(String(p))
	_expect(contam.is_empty(),
		"PL5 安全向：%d 条极性短语无一出现在【相反极性】的独立渲染里（编年史分支 + goals.json 的 hint）%s" % [
			(StoryScript.POLARITY_LOCK as Dictionary).size(),
			("" if contam.is_empty() else "；实得 " + str(contam))])
	print("     PL5 佐证向：%d/%d 条极性短语被独立渲染**逐字**佐证：%s" % [
		corrob.size(), (StoryScript.POLARITY_LOCK as Dictionary).size(), str(corrob)])
	print("        （对不上不算错——两位作者用词本来可以不同；安全向那条断言才是牙齿）")
	# 空真的那几条**必须报出来**，理由与 `lint_grammar` 的 `unlocked` 一栏相同：
	# 一条空真的断言与一条通过了的断言在输出里长得一模一样，不点名就没人知道边界在哪。
	print("        ⚠ 其中 %d 条的【相反极性】那一桶是空的 ⇒ 它们的安全向是**空真**的：%s" % [
		vacuous.size(), str(vacuous)])
	# 判别力底线：佐证向归零 = 解析还活着但配不上任何一条，同样说明形状变了。不写成具体比率。
	_expect(corrob.size() > 0,
		"PL5′ 佐证向 > 0（%d/%d 条逐字对得上）—— 它归零 = 独立渲染的措辞整体换过一轮，请回来重看词表" % [
			corrob.size(), (StoryScript.POLARITY_LOCK as Dictionary).size()])

## 两份独立渲染**按极性切开**后的语料桶。
##   "+" / "-"                = accepted 真 / 假
##   "note:X" / "note:!X"     = note 以 X 开头 / 不以 X 开头
##
## ★为什么是源码扫描而不是实例化 Main：同 `_prose_by_type()` 那条注释（Main 是整个 HUD 的根）。
## ★`rally_oust` 这一支的桥接是**读过 Sim 才敢写的**：`Sim.gd:4235` 那条 `_log_event` 的
##   `accepted` 参数**逐字就是** `backers > 0` ⇒ 编年史按 `backers` 分的岔，与本表按 `accepted`
##   分的岔是同一条界线。不是我把两个字段"当成"一回事，是仿真侧同一个表达式写的。
func _prose_by_polarity() -> Dictionary:
	var out := {"+": "", "-": "", "note:mediated": "", "note:!mediated": "",
		"note:formed": "", "note:!formed": "", "note:dissolved": "", "note:!dissolved": ""}
	var f := FileAccess.open("res://scripts/Main.gd", FileAccess.READ)
	if f != null:
		var src := f.get_as_text()
		var i := src.find("func _event_prose")
		var j := src.find("func _salience", i)
		if i >= 0 and j > i:
			for line in src.substr(i, j - i).split("\n"):
				var s := String(line).strip_edges()
				# ① 三元式的分支：`… X if ok else Y`（meet / confront / apologize / mediate / election）
				var k := s.find(" if ok else ")
				if k > 0:
					out["+"] = String(out["+"]) + s.substr(0, k)
					out["-"] = String(out["-"]) + s.substr(k + 12)
					continue
				# ② note 分支：pact 的 `dissolved` 那一支只有一行 return，其余归"非 dissolved"
				if s.contains("互助盟约散了"):
					out["note:dissolved"] = String(out["note:dissolved"]) + s
					out["note:!formed"] = String(out["note:!formed"]) + s
				elif s.contains("结成了互助盟约"):
					out["note:formed"] = String(out["note:formed"]) + s
					out["note:!dissolved"] = String(out["note:!dissolved"]) + s
				# ③ rally_oust：`backers > 0` 那一支 == accepted=true（Sim.gd:4235 逐字如此）
				elif s.contains("串联了"):
					out["+"] = String(out["+"]) + s
				elif s.contains("没人应和"):
					out["-"] = String(out["-"]) + s
	# ④ goals.json：每条目标的 title+hint 归到它自己 match/first/then 声明的那个极性桶里。
	var gf := FileAccess.open("res://data/goals.json", FileAccess.READ)
	if gf != null:
		var parsed = JSON.parse_string(gf.get_as_text())
		if parsed is Dictionary and (parsed as Dictionary).has("goals"):
			for g in ((parsed as Dictionary)["goals"] as Array):
				var gd: Dictionary = g
				var words := String(gd.get("title", "")) + String(gd.get("hint", ""))
				for key in ["match", "first", "then"]:
					if not gd.has(key):
						continue
					var m: Dictionary = gd[key]
					if m.has("accepted"):
						var b := "+" if bool(m["accepted"]) else "-"
						out[b] = String(out[b]) + words
					if m.has("note_prefix"):
						var nk := "note:" + String(m["note_prefix"])
						out[nk] = String(out.get(nk, "")) + words
	return out

## 文法表里所有**带文案且有事件依据**的槽位，展平成
## `[名字, 模板, 类型集合, 完整匹配器, kind]`（AA2 把后两项加进来了，极性/复述两道锁要用）。
func _all_slots() -> Array:
	var out: Array = []
	for d in StoryScript.ARCS:
		for row in StoryScript._grammar_slots(d):
			if String(row[1]) != "":
				out.append(["%s/%s" % [String(d["id"]), String(row[0])], String(row[1]), row[2], row[3], row[4]])
	return out

## 两个槽位声明的事件类型集合是否**相同**（顺序无关）。
## 这就是"同类型对调"的机器判据 —— Y3 漏网的 19 条无一例外全落在这一栏里。
func _same_types(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for x in a:
		var found := false
		for y in b:
			if String(x) == String(y):
				found = true
				break
		if not found:
			return false
	return true

## 每个事件类型的**独立渲染**：`Main._event_prose` 的 match 臂（源码扫描——它是实例方法，
## 无 Main 节点调不了）+ `Sim._verb()`（可执行，直接调）。
##
## ★为什么是源码扫描而不是实例化 Main：Main 是整个 HUD 的根，实例化它要拉起视图层，
##   而本门是 headless 的 View 侧只读门。口径差异照 W3 清点表那条注释办：**分别标注，不混成一个数**。
func _prose_by_type() -> Dictionary:
	var out: Dictionary = {}
	var f := FileAccess.open("res://scripts/Main.gd", FileAccess.READ)
	if f != null:
		var src := f.get_as_text()
		var i := src.find("func _event_prose")
		var j := src.find("func _salience", i)
		if i >= 0 and j > i:
			var body := src.substr(i, j - i)
			var cut := body.find("# 兜底")          # 兜底段不属于任何一个 match 臂，切掉免得算到最后一臂头上
			if cut > 0:
				body = body.substr(0, cut)
			var cur := ""
			for line in body.split("\n"):
				var s := String(line).strip_edges()
				var q := s.find("\"", 1)
				if s.begins_with("\"") and q > 1 and s.substr(q + 1, 1) == ":":
					cur = s.substr(1, q - 1)
					out[cur] = String(out.get(cur, "")) + s
				elif cur != "":
					out[cur] = String(out.get(cur, "")) + s
	# Sim._verb：仿真自己的中文动词表。它是编年史兜底真正会打出来的字，故与 match 臂同权。
	for t in out.keys():
		out[t] = String(out[t]) + String(Sim._verb(String(t)))
	for t2 in ["produce", "shortage", "consume", "spoil", "gossip_rep", "discuss", "gossip"]:
		out[t2] = String(out.get(t2, "")) + String(Sim._verb(t2))
	return out

# ── W1 段：回放安全到底覆盖到哪（docs/47 §五-E4 / docs/46 §二·九-⑧）────────
## 与 `goals_test._w1()` **同构**（同一套 Q1/Q2/R/F 口径、同一套断言）——两个折叠器的红线是同一条，
## 判据分叉了才是问题。完整论证写在 goals_test.gd 的同名段落里，这里只记 Story 特有的那一句：
##
## ★ **故事比目标更怕这件事。** 目标只会前进（`done` 一旦点亮就不再被后来的事件挪动），
##   而弧会**收场**：顺着旧游标把新时间线的尾巴折进来，面板上就会挂着一段"在这条时间线里从没发生过的结局"。
##   这正是评审说的「`chain` 见证一个从未存在过的序列」在屏幕上的样子。
const W1_GREET_EVERY := 60

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
	var live := StoryScript.new()
	var fwd := StoryScript.new()                       # 只折到 half 就停手 = 玩家在 half 处拖了时间轴
	var acts := 0
	for t in range(total):
		Sim.tick()
		if with_player and Sim.tick_no % W1_GREET_EVERY == 0 and _w1_player_beat(Sim.tick_no):
			acts += 1
		live.sync(Sim.event_log)
		if Sim.tick_no <= half:
			fwd.sync(Sim.event_log)
	var log_live: Array = Sim.event_log.duplicate()    # start_new 是 clear() 就地清 ⇒ 必须先 duplicate
	var ed_live: int = Sim.event_digest
	var n_live: int = log_live.size()

	var pure := StoryScript.new()
	pure.recompute(log_live)
	var q1: bool = pure.digest() == live.digest() and pure.chain == live.chain and _eq(_snap(live), _snap(pure))

	Sim.goto_tick(total)
	var q2: bool = (Sim.event_digest == ed_live) and (Sim.event_log.size() == n_live)

	var rep := StoryScript.new()
	rep.recompute(Sim.event_log)
	var r_ok: bool = rep.digest() == live.digest() and rep.chain == live.chain and _eq(_snap(live), _snap(rep))

	fwd.sync(Sim.event_log)
	var f_ok: bool = fwd.digest() == rep.digest() and fwd.chain == rep.chain and _eq(_snap(fwd), _snap(rep))

	print("  [%s] seed=%d%s" % [label, sd, ("  玩家动作 %d 次" % acts) if with_player else ""])
	print("     Q1 折叠纯函数（同一份日志）      %s" % ("✅" if q1 else "❌"))
	print("     Q2 重演出同一份日志              %s   事件 %d→%d · event_digest %d→%d" % [
		"✅" if q2 else "❌", n_live, Sim.event_log.size(), ed_live, Sim.event_digest])
	print("     R  重演后整份重算 ≡ live         %s   开过 %d/%d 段 · 收场 %d/%d 段 · digest %d/%d" % [
		"✅" if r_ok else "❌", live._serial, rep._serial, live.closed_count(), rep.closed_count(),
		live.digest(), rep.digest()])
	print("     F  重演后顺游标续折 ≡ 整份重算   %s   digest %d/%d · 锚触发重折 %d 次（live 侧 %d 次，必须 0）" % [
		"✅" if f_ok else "❌", fwd.digest(), rep.digest(), fwd.resyncs, live.resyncs])
	_expect(q1, "%s seed %d · Q1 折叠是纯函数（**这条与后端/玩家无关**，它是 Story.gd 的红线本身）" % [label, sd])
	_expect(f_ok, "%s seed %d · F 前向拖动后顺游标续折 ≡ 整份重算（`_anchor` 守着；负对照：删掉 `_anchor` 这条必红）" % [label, sd])
	_expect(live.resyncs == 0, "%s seed %d · 锚在 live 逐 tick 路上**一次都不触发**（实得 %d 次）" % [label, sd, live.resyncs])
	if q2:
		_expect(r_ok, "%s seed %d · Q2 ✅ ⇒ R 必须 ✅（同一份日志 + 纯折叠 ⇒ 同一批故事）" % [label, sd])
	return q2

## 确定性玩家剧本（与 goals_test 逐字同款）：把一位居民召到身边，打个招呼。
func _w1_player_beat(t: int) -> bool:
	var pl: Dictionary = Sim.get_agent("player")
	if pl.is_empty():
		return false
	var ids: Array = []
	for ag in Sim.agents:
		if String(ag["id"]) != "player":
			ids.append(String(ag["id"]))
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

func _pct(a: int, b: int) -> String:
	return "n/a" if b <= 0 else "%.1f%%" % (100.0 * float(a) / float(b))

func _beat_ids(arc: Dictionary) -> Array:
	var out: Array = []
	for b in (arc.get("beats", []) as Array):
		out.append(String(b[0]))
	return out

## 合成事件：字段与 Sim._log_event 完全同名（本门因此不依赖 Sim 就能造流）。
# ── F-trim：把 MAX_CLOSED 裁剪【真的触发一次】───────────────────────────────
## 为什么必须有这一条（2026-07-30）：A 段那两条「账本自洽」的注释写着"裁剪一开始咬人，
## 这两条就是唯一能发现的地方"，而它们跑的 14 天里 **裁掉 0 段**——被守的那件事根本没发生。
## 实测四格（负对照 = 把 closed_count() 改成从 `arcs` 数，即注释里警告的那个朴素写法）：
##     干净 @14 天(CI)   裁掉    0  ✅        干净 @150 天  裁掉 1018  ✅
##     朴素 @14 天(CI)   裁掉    0  ✅ ←缺陷隐形   朴素 @150 天  裁掉 1018  ❌ 32 vs 1085
## ⇒ 判据有牙，但牙咬不到 CI 跑的那个 horizon。真世界要 150 天才裁得动（一局 3 分钟），
##    合成 fixture 毫秒级就能把 MAX_CLOSED 顶穿 ⇒ 用 fixture，不给 CI 加三分钟。
func _fixture_trim() -> void:
	var n_arc := StoryScript.MAX_CLOSED + 8      # 阈值从 Story 读，不抄第二份
	var f: Array = []
	var eid := 0
	for k in n_arc:
		var a := "p%d" % k
		var b := "q%d" % k
		var t0 := 100 + k * 400                   # 每条弧独占一段时间，互不干扰
		f.append(_ev(eid, t0, "conflict", a, b, false)); eid += 1
		f.append(_ev(eid, t0 + 40, "confront", a, b, true)); eid += 1
		f.append(_ev(eid, t0 + 80, "apologize", b, a, true)); eid += 1
	var st := StoryScript.new()
	st.recompute(f)
	# ① fixture 有效性先自证：**裁剪必须真的发生过**，否则下面两条又是空门。
	_expect(st._dropped > 0,
		"F-trim fixture 有效性：%d 条弧全部收场 ⇒ 裁掉 %d 段（必须 >0，否则本 fixture 自己是空门）" % [n_arc, st._dropped])
	# ② 终身账在裁剪下不缩水 —— 负对照：把 closed_count() 改成从 `arcs` 数，这条必红。
	_expect(st.closed_count() == n_arc,
		"F-trim 终身收场 %d == 开过 %d（负对照：closed_count() 改从 `arcs` 数则为 %d ⇒ 必红）" % [
			st.closed_count(), n_arc, st.closed_kept()])
	# ③ 留存账确实比终身账少，且差额正好是裁掉的数目。
	_expect(st.closed_kept() == n_arc - st._dropped and st.closed_kept() < st.closed_count(),
		"F-trim 留存 %d = 终身 %d − 裁掉 %d，且严格小于终身（面板翻得到的比讲过的少）" % [
			st.closed_kept(), st.closed_count(), st._dropped])
	# ④ A 段那条账本恒等式，这次是在【裁剪真的发生过】的前提下过的。
	_expect(st.open_count() + st.closed_count() == st._serial,
		"F-trim 账本自洽：进行中 %d + 终身收场 %d == 开过 %d（这次裁掉的是 %d 段，不是 0）" % [
			st.open_count(), st.closed_count(), st._serial, st._dropped])

## ★`witnesses` 是**第九个可选参数**（W3 加的）：`Sim._log_event` 存的是**id 字符串数组**
##   （`wids.append(w["id"])`，Sim.gd:3646-3647），不是 agent 字典 —— 手艺弧就是从这一列取人的。
func _ev(id: int, tick: int, type: String, actor: String, target: String, accepted: bool,
		subject: String = "", note: String = "", witnesses: Array = []) -> Dictionary:
	return {"id": id, "tick": tick, "type": type, "actor": actor, "target": target,
		"subject": subject, "accepted": accepted, "witnesses": witnesses, "note": note}

# ── 工具 ────────────────────────────────────────────────────────────────────
func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("  ✅ " + msg)
	else:
		print("  ❌ " + msg)
		_fail += 1

## 弧的可比快照（只取会被断言的字段，避开纯呈现字符串）。
func _snap(s) -> Array:
	var out: Array = []
	for arc in s.arcs:
		out.append([int(arc["n"]), String(s.def_of(arc)["id"]), String(arc["a"]), String(arc["b"]),
			int(arc["t0"]), int(arc["t1"]), String(arc["end"]), (arc["beats"] as Array).size(),
			int(arc["extra"]), int(arc["aside"]), int(arc["last"])])
	return out

func _eq(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		var x: Array = a[i]
		var y: Array = b[i]
		for j in x.size():
			if x[j] != y[j]:
				return false
	return true

func _nm(id: String) -> String:
	return Sim._name(Sim.get_agent(id))

func _nm_fake(id: String) -> String:
	return {"aria": "阿丽", "ben": "本", "coco": "可可", "dan": "丹"}.get(id, id)

## 去掉 BBCode，便于在终端把成文原样打出来读（R10：屏幕上的字自己也要看一遍）。
func _plain(s: String) -> String:
	var out := ""
	var i := 0
	while i < s.length():
		if s[i] == "[":
			var j := s.find("]", i)
			if j > i and j - i < 40:
				i = j + 1
				continue
		out += s[i]
		i += 1
	return out

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
