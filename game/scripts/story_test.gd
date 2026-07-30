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

	print("小镇故事验收：%d 种弧 · seeds=%s · %d 天" % [StoryScript.ARCS.size(), str(seeds), days])
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

	print("")
	if _fail == 0:
		print("✅ 小镇故事验收全绿（fixture 5 组 + %d seed × %d 天）" % [seeds.size(), days])
	else:
		print("❌ 小镇故事验收 %d 条断言失败" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

# ── F 段：合成 fixture（本门的判别力都在这里）──────────────────────────────
func _fixtures() -> void:
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
	print("")

func _pct(a: int, b: int) -> String:
	return "n/a" if b <= 0 else "%.1f%%" % (100.0 * float(a) / float(b))

func _beat_ids(arc: Dictionary) -> Array:
	var out: Array = []
	for b in (arc.get("beats", []) as Array):
		out.append(String(b[0]))
	return out

## 合成事件：字段与 Sim._log_event 完全同名（本门因此不依赖 Sim 就能造流）。
func _ev(id: int, tick: int, type: String, actor: String, target: String, accepted: bool,
		subject: String = "", note: String = "") -> Dictionary:
	return {"id": id, "tick": tick, "type": type, "actor": actor, "target": target,
		"subject": subject, "accepted": accepted, "witnesses": [], "note": note}

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
