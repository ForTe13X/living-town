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
	print("     文案槽位 %d 个 · 已上锁 %d 个 · 没有任何标志性短语的 %d 个：%s" % [
		slots.size(), slots.size() - (lg["unlocked"] as Array).size(), (lg["unlocked"] as Array).size(),
		str((lg["unlocked"] as Array).slice(0, 4))])

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

	# ── PL3 检出【比率】，不是一发子弹（docs/41 §2.5 外审那条度量学批评）──────
	# 外审原话：「负对照测的是 recall（这一发打中了），不是 coverage（弹药库里有多少种打不中）」。
	# 所以这里把**整个"两条文案对调"的变异空间**跑一遍：C(n,2) 个变异体，逐个问措辞锁认不认。
	# 这个比率就是本机制的 `confidence`，`does_not_detect` 也是从这里的漏网名单里抄出来的。
	var tot := 0
	var caught := 0
	var missed: Array = []
	for i in slots.size():
		for j in range(i + 1, slots.size()):
			var a: Array = slots[i]
			var b: Array = slots[j]
			if String(a[1]) == String(b[1]):
				continue                      # 两条文案本来就一样 ⇒ 对调是恒等变换，不是变异体
			tot += 1
			var hit := not StoryScript.phrase_conflicts(String(b[1]), a[2] as Array).is_empty() \
				or not StoryScript.phrase_conflicts(String(a[1]), b[2] as Array).is_empty()
			if hit:
				caught += 1
			else:
				missed.append("%s ↔ %s" % [String(a[0]), String(b[0])])
	print("     两条文案对调的**全变异空间**：%d 个变异体，措辞锁认出 %d 个（%.1f%%）" % [
		tot, caught, 100.0 * float(caught) / float(maxi(1, tot))])
	# 漏网的**逐条全列**，不给样例 —— 这一栏就是 does_not_detect，抽样等于把边界说小了。
	print("     漏网 %d 条（= does_not_detect 那一栏，跑出来的不是想出来的）：" % missed.size())
	for x in missed:
		print("       · " + String(x))
	# 只钉一条底线：**必须显著优于 0**。具体比率写进回执，不写成阈值门 ——
	# 写成阈值门就等着有人加一条没上锁的文案时收一次假红（docs/41 §6「写死的绝对数」那条）。
	_expect(caught > 0 and tot > 0, "PL3 变异空间非空且检出 > 0（比率 %d/%d，逐次重算，不冻结字面量）" % [caught, tot])

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

## 文法表里所有**带文案且有事件依据**的槽位，展平成 `[名字, 模板, 类型集合]`。
func _all_slots() -> Array:
	var out: Array = []
	for d in StoryScript.ARCS:
		for row in StoryScript._grammar_slots(d):
			if String(row[1]) != "":
				out.append(["%s/%s" % [String(d["id"]), String(row[0])], String(row[1]), row[2]])
	return out

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
