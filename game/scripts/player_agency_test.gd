extends Node
## player_agency_test.gd — 玩家能动性 M1 headless 验证（scene 模式，autoload Sim 可用）。
## 断言：玩家入社交图、greet/give/gossip/invite 走完整 SocialTransaction（账本/记忆/事件/知识边界）、
## 约见靠"人到场"兑现、坏关系会被拒、调解成功/失败两分支、NPC 会主动找玩家。任一失败 quit(1)。
##
## "NPC 会主动找玩家"这条见第 14 节：它是【跨种子分布门】，不是单局首达计时（原因与实测见那里）。

# ── 第 14 节（挂机社交分布门）的标定常量 ────────────────────────────────────
# 阈值全部由实测定，不猜。测量方法与数据见 14 节注释。
const AGENCY_SEEDS: Array = [1, 2, 3, 4, 5, 6, 7, 8]
const AGENCY_DAYS := 4            # 每个 seed 的挂机时长
const AGENCY_MIN_TOTAL := 50      # 8 seed 合计接触次数下限。★ 余量【现算现打印】，见第 14 节
                                  #   （这里原本写着"实测地板 101 → 2.0× 余量"。那个数已经过期两代：
                                  #    S2 在 bbe1dc6 上量到 81、X3 在 0667018 上量到 85，
                                  #    而 101 一直照常印在屏幕上。别再往这行里写死任何实测数。）
const AGENCY_MIN_SEEDS := 6       # 至少几个 seed 要"有人来搭话"（实测 8/8 → 可先坏掉 2 个 seed 才红）
const AGENCY_MIN_ACTORS := 4      # 合计有多少个【不同】NPC 来找过（实测 11-12/12 → 挡"一个人刷满"的空过）

var _fails := 0

func _ck(name: String, ok: bool, detail: String = "") -> void:
	print("  %s %s  %s" % [("✅" if ok else "❌"), name, detail])
	if not ok:
		_fails += 1

func _tickn(n: int) -> void:
	for i in n:
		Sim.tick()

## 把 agent 传送到玩家所在格旁（同区、可社交），并清空双方进行中的事务。
## （玩家可能正被 NPC 主动搭话占用 talking——这正是特性生效；测试里强制释放以隔离断言。）
func _summon(id: String) -> void:
	var pl: Dictionary = Sim.get_agent("player")
	pl["option"] = null
	pl["talking"] = 0
	var ag: Dictionary = Sim.get_agent(id)
	ag["option"] = null
	ag["talking"] = 0
	ag["space"] = pl.get("space", "town")        # P3 Tier-B：召到玩家身边=同【平面】（aria 现住 cafe/2f，
	ag["floor"] = pl.get("floor", "outdoor")     # 只挪 pos 会把她留在咖啡馆层→隔平面搭不上话，与真游戏一致）
	Sim._move_agent(ag, pl["pos"] + Vector2i(1, 0))

## 在 event_log[from..] 中找 (type, actor, target) 的最新事件；无 → {}。
func _find_ev(from: int, type: String, actor: String, target: String) -> Dictionary:
	var log: Array = Sim.event_log
	for i in range(log.size() - 1, from - 1, -1):
		var e: Dictionary = log[i]
		if String(e["type"]) == type and String(e["actor"]) == actor and String(e["target"]) == target:
			return e
	return {}

func _ready() -> void:
	Sim.backend = null
	Sim.auto_run = false
	Sim.start_new(7)
	print("=== 玩家能动性 M1 验证 ===")

	# ── 0) 入镇 ──
	var resident_count := Sim.agents.size()
	var pl := Sim.add_player()
	_ck("入镇", Sim.agents.size() == resident_count + 1 and pl.get("is_player", false) and Sim.get_agent("player") == pl,
		"agents=%d (%d residents + player)" % [Sim.agents.size(), resident_count])
	Sim.player_move(Vector2i(1, 0))
	_ck("移动", true, "pos=%s area=%s" % [str(pl["pos"]), Sim._area_at(pl["pos"])])

	# ── 1) greet：完整事务 + 双向账本 + 双方记忆 ──
	_summon("aria")
	var mark := Sim.event_log.size()
	var err := Sim.player_act("greet", "aria")
	_tickn(12)
	var ev := _find_ev(mark, "greet", "player", "aria")
	_ck("greet 发起", err == "", err)
	_ck("greet 事件入账本", not ev.is_empty(), str(ev))
	var aria: Dictionary = Sim.get_agent("aria")
	_ck("双向关系账本", pl["relationships"].has("aria") and aria["relationships"].has("player"))
	var aria_mem := false
	for it in aria["memory"].items:
		if "player" in (it["tags"] as Array):
			aria_mem = true
	_ck("对方写了记忆", aria_mem)

	# ── 2) give：礼物消耗 + 好感上升 ──
	_summon("aria")
	var gifts0 := int(pl["inventory"]["gift"])
	var aff0 := float(Sim._rel(aria, "player")["affinity"])
	mark = Sim.event_log.size()
	err = Sim.player_act("give", "aria")
	_tickn(12)
	ev = _find_ev(mark, "give", "player", "aria")
	_ck("give 发起+入账", err == "" and not ev.is_empty(), err)
	if not ev.is_empty() and bool(ev["accepted"]):
		_ck("礼物-1", int(pl["inventory"]["gift"]) == gifts0 - 1, "%d→%d" % [gifts0, int(pl["inventory"]["gift"])])
		_ck("好感上升", float(Sim._rel(aria, "player")["affinity"]) > aff0, "%.1f→%.1f" % [aff0, float(Sim._rel(aria, "player")["affinity"])])

	# ── 3) gossip：知识边界（对方 belief 带 source=player via=gossip）──
	pl["beliefs"]["R9"] = {"claim": "码头夜里有灯光", "subject": "dan", "source": "player", "via": "seed", "tick": Sim.tick_no}
	_summon("aria")
	mark = Sim.event_log.size()
	err = Sim.player_act("gossip", "aria")
	_tickn(12)
	ev = _find_ev(mark, "gossip", "player", "aria")
	_ck("gossip 发起+入账", err == "" and not ev.is_empty(), err)
	if not ev.is_empty() and bool(ev["accepted"]):
		var b: Dictionary = aria["beliefs"].get("R9", {})
		_ck("知识边界(source/via)", String(b.get("source", "")) == "player" and String(b.get("via", "")) == "gossip", str(b))

	# ── 4) invite：承诺创建 + 人到场即兑现 ──
	_summon("aria")
	mark = Sim.event_log.size()
	err = Sim.player_act("invite", "aria")
	_tickn(12)
	var cmt := {}
	for c in Sim.commitments:
		if String(c["a"]) == "player" and String(c["b"]) == "aria":
			cmt = c
	ev = _find_ev(mark, "invite", "player", "aria")
	if not ev.is_empty() and bool(ev["accepted"]):
		_ck("meet 承诺创建", not cmt.is_empty(), str(cmt.get("area", "")))
		# 双方都已在该区（发起地）→ 数 tick 内应 fulfilled
		_tickn(4)
		_ck("到场即兑现", String(cmt.get("status", "")) == "fulfilled", String(cmt.get("status", "")))
	else:
		_ck("invite 发起+入账", err == "" and not ev.is_empty(), err)

	# ── 5) 拒绝分支：坏关系 → NPC 婉拒玩家 ──
	Sim._rel(aria, "player")["affinity"] = -90.0
	_summon("aria")
	mark = Sim.event_log.size()
	err = Sim.player_act("greet", "aria")
	_tickn(12)
	ev = _find_ev(mark, "greet", "player", "aria")
	_ck("坏关系被拒", not ev.is_empty() and not bool(ev["accepted"]), str(ev.get("accepted", "?")))
	var pl_refuse_mem := false
	for it in pl["memory"].items:
		if "refuse" in (it["tags"] as Array):
			pl_refuse_mem = true
	_ck("玩家记住被拒", pl_refuse_mem)
	Sim._rel(aria, "player")["affinity"] = 0.0   # 复原

	# ── 6) 调解：失败(好感不够) → 成功(双方信任) ──
	Sim.conflicts.append({"a": "ben", "b": "coco", "status": "simmering", "severity": 8.0,
		"escalations": 0, "confronted": 0, "repaired": 0, "triggered": Sim.tick_no, "lastEscalate": Sim.tick_no})
	_summon("ben")
	_summon("coco")
	var ben: Dictionary = Sim.get_agent("ben")
	var coco: Dictionary = Sim.get_agent("coco")
	Sim._rel(ben, "player")["affinity"] = -10.0
	Sim._rel(coco, "player")["affinity"] = 10.0
	var msg := Sim.player_mediate("ben")
	_ck("调解被拒(好感不够)", msg != "", msg)
	Sim._rel(ben, "player")["affinity"] = 10.0
	msg = Sim.player_mediate("ben")
	var cf: Dictionary = Sim.conflicts[Sim.conflicts.size() - 1]
	_ck("调解成功", msg == "" and String(cf["status"]) == "repaired", msg + " status=" + String(cf["status"]))
	_ck("怨气清零", float(Sim._rel(ben, "coco")["resentment"]) == 0.0)
	var thanks := false
	for it in ben["memory"].items:
		if "player" in (it["tags"] as Array) and "repair" in (it["tags"] as Array):
			thanks = true
	_ck("当事人感谢玩家", thanks)

	# ── 7) 挂机推进世界（本节【不再断言】；"NPC 会主动找玩家"已移到第 14 节的分布门）──
	# 这里保留原样的 4 天推进，只为让下面 8-13 节看到与从前一致的世界态；本局这个计数
	# 只作现场参考打印。理由：单局单窗口的首达计时是【涌现时机】量，对轨迹极敏感——
	# B9 的候选加盐把 seed 7 的首次 NPC→player 从 +190 tick 推到 +523 tick，而 30 天社交
	# 总量反而从 161 升到 172。也就是说它红过一次不是社交退化，是断言坐在边界上。
	# 把窗口从 2 天放宽到 4 天只是治标：下一次轨迹扰动照样能推红，而"再放宽一次"会一路
	# 把门蚀空。真正的门在第 14 节：跨 8 个 seed 的【分布】，见那里的实测标定。
	_tickn(4 * int(Sim.TICKS_PER_DAY))
	var npc_to_player := 0
	for e in Sim.event_log:
		if String(e["target"]) == "player" and String(e["actor"]) != "player":
			npc_to_player += 1
	print("  ·  (参考，不断言) 本局 seed 7 前置扰动后挂机 4 天：被动收到 %d 次社交" % npc_to_player)

	# ── 8) 对抗审查回归：invite 叠约门（#7）──
	var fake := {"id": 9999, "type": "meet", "a": "player", "b": "aria", "area": "plaza",
		"created": Sim.tick_no, "deadline": Sim.tick_no + 40, "status": "active"}
	Sim.commitments.append(fake)
	Sim._active_commitments.append(fake)
	_summon("aria")
	_ck("叠约被挡", Sim.player_act("invite", "aria") != "")
	fake["status"] = "fulfilled"   # 清场

	# ── 9) 对抗审查回归：区域外 ""=="" 隔图社交漏洞（#6）──
	Sim._move_agent(pl, Vector2i(0, 0))         # 区域外走廊
	var dan: Dictionary = Sim.get_agent("dan")
	dan["option"] = null; dan["talking"] = 0
	dan["space"] = "town"; dan["floor"] = "outdoor"   # P3：dan 现住 home/1f；本用例是【镇上贴身社交】→ 把他放回镇平面（_move_agent 只改 pos 不改平面）
	Sim._move_agent(dan, Vector2i(14, 2))       # 另一片区域外，距离>2
	_ck("区外隔图社交被挡", Sim.player_act("greet", "dan") != "", Sim.player_act("greet", "dan"))
	Sim._move_agent(dan, Vector2i(1, 0))        # 贴身(dist≤2)则放行（同为区外也行）
	_ck("贴身社交放行", Sim.player_act("greet", "dan") == "")
	pl["option"] = null; pl["talking"] = 0

	# ── 10) 对抗审查回归：玩家委屈方冲突可 confront，NPC 会来道歉（#5）──
	Sim.conflicts.append({"a": "player", "b": "aria", "status": "simmering", "severity": 6.0,
		"escalations": 0, "confronted": 0, "repaired": 0, "triggered": Sim.tick_no, "lastEscalate": Sim.tick_no})
	_summon("aria")
	err = Sim.player_act("confront", "aria")
	_tickn(12)
	var pc: Dictionary = Sim._find_conflict("player", "aria", ["confronted", "escalated"])
	_ck("玩家可当面理论", err == "" and not pc.is_empty(), err + " status=" + String(pc.get("status", "?")))

	# ── 11) 对抗审查回归：mediate 跳过玩家自身冲突（#4）──
	var msg2 := Sim.player_mediate("aria")
	_ck("不能自我调解", msg2 != "" and not pl["relationships"].has("player"), msg2)

	# ── 12) 对抗审查回归：玩家不入夜间派系/盟约（#9）──
	var in_faction := String(pl.get("faction", "")) != ""
	var in_pact := false
	for p in Sim.pacts_index:
		if p["a"] == "player" or p["b"] == "player":
			in_pact = true
	_ck("玩家不入派系/盟约", not in_faction and not in_pact)

	# ── 13) 对抗审查回归：goto_tick 后玩家健在（#1，放最后——会重置世界）──
	# 前 12 节包含测试专用的直接关系/位置注入，故不能拿那段非玩家输入假装可回放。
	# 这里另开一个只经 public PlayerTraceV1 边界的最小局，验证诚实 scrub。
	Sim.start_new(7)
	Sim.add_player()
	Sim.player_move(Vector2i.RIGHT)
	_tickn(5)
	var scrub_ok := Sim.goto_tick(100)
	var pl2: Dictionary = Sim.get_agent("player")
	var scrub_witness := {"pos": pl2.get("pos"), "inventory": pl2.get("inventory", {}).duplicate(true),
		"event_digest": Sim.event_digest, "trace": Sim.get_player_trace()}
	var scrub_repeat_ok := Sim.goto_tick(100)
	var pl3: Dictionary = Sim.get_agent("player")
	var scrub_repeat := {"pos": pl3.get("pos"), "inventory": pl3.get("inventory", {}).duplicate(true),
		"event_digest": Sim.event_digest, "trace": Sim.get_player_trace()}
	_ck("scrub 后玩家历史由 PlayerTraceV1 精确重演", scrub_ok and scrub_repeat_ok and not pl3.is_empty() and scrub_repeat == scrub_witness,
		"gift=%d trace=%d" % [int(pl3.get("inventory", {}).get("gift", -1)), int(Sim.player_trace_status()["entries"])])

	# ── 14) NPC 主动找玩家：跨种子【分布】门（取代原第 7 节的单样本首达断言）──────────
	# 意图一字未改：一个【什么都不做】的玩家不该被小镇社交无视。变的是怎么问这句话。
	#
	# 为什么不能问单局：单局"首次被搭话在第几 tick"是一个【最小值统计量】——整局里最早的
	# 那一次。最小值对轨迹扰动的敏感度是所有统计量里最高的，任何合法改动（换 tie-break、
	# 挪一栋房子、改一条 need 曲线）都能把它翻倍，而社交总量纹丝不动。B9 就是这么红的。
	#
	# 改成问分布：8 个 seed 各自新开世界、放一个纯挂机玩家、跑 4 天，然后看【合起来】的
	# 三个量。跨 seed 求和把轨迹噪声平均掉了——单 seed 的 4 天接触数在 6-29 之间摆（约 5 倍），
	# 8 seed 合计却几乎不动。
	#
	# 实测标定（本棒，Godot 4.6.2 headless，共 14 组独立的 8-seed 合计）：
	#   · 轨迹扰动敏感度——让世界先空跑 W tick 再放玩家进去（"谁恰好路过"整体换人，
	#     与 B9 加盐同类的扰动），W ∈ {0,1,2,3,5,13,37,97,240,617}：
	#       合计 = 102 102 102 102 103 104 111 123 138 153   （只升不降，地板在 W=0）
	#       有人搭话的 seed = 8/8（全部 10 组）   单 seed 最小值 = 6..11   不同 NPC = 11-12
	#   · 种子总体敏感度——四组互不相交的 seed（1-8 / 9-16 / 17-24 / 31,37,41,43,47,53,59,61）：
	#       合计 = 102 / 101 / 110 / 107（±4.5%）   有人搭话 = 8/8 全部四组   不同 NPC = 11-12
	#   · 单 seed 首达 tick（32 个 seed）：min 141 / max 395，全部 < 960（=4 天窗口）→ 2.4× 余量。
	# 阈值即由此定：合计地板实测 101 → 门取 50（2.0×，社交要腰斩才红）；seed 命中实测 8/8 →
	# 门取 6/8（可以先坏掉 2 个 seed）；不同 NPC 实测 11-12/12 → 门取 4（≈3×，且挡住
	# "一个 NPC 刷满次数"的空过）。轨迹噪声实测只能让合计动 ±5%，推不动 2 倍的余量。
	var tpd := int(Sim.TICKS_PER_DAY)
	var agency_total := 0
	var agency_seeds_hit := 0
	var agency_actors := {}
	var agency_per_seed: Array = []
	for s in AGENCY_SEEDS:
		Sim.start_new(int(s))
		Sim.add_player()                      # 纯挂机：入镇后不发任何指令
		var base := Sim.event_log.size()
		_tickn(AGENCY_DAYS * tpd)
		var n := 0
		var elog: Array = Sim.event_log
		for i in range(base, elog.size()):
			var e2: Dictionary = elog[i]
			if String(e2["target"]) == "player" and String(e2["actor"]) != "player":
				agency_actors[String(e2["actor"])] = true
				n += 1
		agency_total += n
		agency_per_seed.append(n)
		if n > 0:
			agency_seeds_hit += 1
	# ★ 余量现算现打印（2026-08-02 Y2）。原来这里是 "实测地板 101" —— 一个写死在格式串里的字面量，
	#   S2（编号 73 §一·4-N1）把它更正成 81，X3（编号 94 §四·3④）量到 85：**同一个字面量的第三代**。
	#   S2 在 11 条臂上量出的统一结论是：**每次重算并打印的臂至今全准，打印冻结字面量的两族全部过期。**
	#   ⇒ 这一行从此不写任何历史数，只印**这一跑**的余量与逐 seed 极值（极值带并列个数：
	#   `0..16` 与 `0×8..16` 在"这道门离红有多远"上完全是两回事，docs/41 §4）。
	var _amin: int = agency_per_seed.min() if not agency_per_seed.is_empty() else 0
	var _amax: int = agency_per_seed.max() if not agency_per_seed.is_empty() else 0
	var _nmin := 0
	var _nmax := 0
	for _v in agency_per_seed:
		if int(_v) == _amin:
			_nmin += 1
		if int(_v) == _amax:
			_nmax += 1
	var _margin := (float(agency_total) / float(AGENCY_MIN_TOTAL)) if AGENCY_MIN_TOTAL > 0 else 0.0
	_ck("挂机社交·合计接触量", agency_total >= AGENCY_MIN_TOTAL,
		"%d 次 / %d seed × %d 天 (门 %d；本跑余量 %.2f× · 逐 seed %d×%d..%d×%d)" % [
			agency_total, AGENCY_SEEDS.size(), AGENCY_DAYS, AGENCY_MIN_TOTAL,
			_margin, _amin, _nmin, _amax, _nmax])
	_ck("挂机社交·没有被无视的 seed", agency_seeds_hit >= AGENCY_MIN_SEEDS,
		"%d/%d seed 有人主动搭话 (门 %d) 各 seed=%s" % [agency_seeds_hit, AGENCY_SEEDS.size(), AGENCY_MIN_SEEDS, str(agency_per_seed)])
	_ck("挂机社交·搭话者不止一人", agency_actors.size() >= AGENCY_MIN_ACTORS,
		"%d 个不同 NPC 找过玩家 (门 %d)" % [agency_actors.size(), AGENCY_MIN_ACTORS])

	print("=== 玩家能动性: %s (%d fail) ===" % [("PASS ✅" if _fails == 0 else "FAIL ❌"), _fails])
	get_tree().quit(0 if _fails == 0 else 1)
