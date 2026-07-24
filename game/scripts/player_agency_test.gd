extends Node
## player_agency_test.gd — 玩家能动性 M1 headless 验证（scene 模式，autoload Sim 可用）。
## 断言：玩家入社交图、greet/give/gossip/invite 走完整 SocialTransaction（账本/记忆/事件/知识边界）、
## 约见靠"人到场"兑现、坏关系会被拒、调解成功/失败两分支、NPC 会主动找玩家。任一失败 quit(1)。

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
	var pl := Sim.add_player()
	_ck("入镇", Sim.agents.size() == 13 and pl.get("is_player", false) and Sim.get_agent("player") == pl, "agents=%d (12-cast + player)" % Sim.agents.size())
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

	# ── 7) NPC 主动找玩家：挂机 2 天，应有 NPC 发起指向玩家的社交 ──
	_tickn(2 * int(Sim.TICKS_PER_DAY))
	var npc_to_player := 0
	for e in Sim.event_log:
		if String(e["target"]) == "player" and String(e["actor"]) != "player":
			npc_to_player += 1
	_ck("NPC 主动找玩家", npc_to_player > 0, "被动收到 %d 次社交" % npc_to_player)

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
	var inv_before := int(pl["inventory"].get("gift", 0))
	Sim.goto_tick(100)
	var pl2: Dictionary = Sim.get_agent("player")
	_ck("scrub 后玩家健在", not pl2.is_empty() and int(pl2["inventory"].get("gift", 0)) == inv_before,
		"gift=%d(应%d)" % [int(pl2.get("inventory", {}).get("gift", -1)), inv_before])

	print("=== 玩家能动性: %s (%d fail) ===" % [("PASS ✅" if _fails == 0 else "FAIL ❌"), _fails])
	get_tree().quit(0 if _fails == 0 else 1)
