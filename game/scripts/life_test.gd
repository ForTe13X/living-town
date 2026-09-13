extends Node
## life_test.gd — 生活模式（docs/190）Sim 侧 headless 验证（scene 模式，autoload Sim/AIBackend 可用）。
## 断言：附身后引擎不再替他决策但需求照常衰减；「按 E」列出身边的物件/居民/门；
## life_use 走引擎自己的 object 单（走过去→用→需求回升）；life_move 打断手头的事；
## life_social 带「说法」台词走完整 SocialTransaction；说法解析只收合法动词；Portal 权限照验；world_reset 清附身。

var _fails := 0

func _ck(name: String, ok: bool, detail: String = "") -> void:
	print("  %s %s  %s" % [("✅" if ok else "❌"), name, detail])
	if not ok:
		_fails += 1

func _tickn(n: int) -> void:
	for i in n:
		Sim.tick()

func _free_neighbor(sp: String, fl: String, c: Vector2i) -> Vector2i:
	var g := Sim._grid_for(sp, fl)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if Sim._cell_walkable(g, c + d):
			return c + d
	return Vector2i(-99, -99)

func _place(ag: Dictionary, sp: String, fl: String, pos: Vector2i) -> void:
	ag["option"] = null
	ag["talking"] = 0
	ag["space"] = sp
	ag["floor"] = fl
	Sim._move_agent(ag, pos)

func _ready() -> void:
	Sim.backend = null
	Sim.auto_run = false
	Sim.start_new(7)
	print("=== 生活模式 life_* 验证 ===")

	# ── 0) 附身 ──
	_ck("附身不存在的人被拒", not Sim.possess("nobody"))
	_ck("附身 ben", Sim.possess("ben") and Sim.controlled_id == "ben")
	var ben: Dictionary = Sim.get_agent("ben")
	var sp := String(ben.get("space", "town")); var fl := String(ben.get("floor", "outdoor"))

	# ── 1) 引擎不再替他挑事，但需求照常衰减 ──
	ben["option"] = null
	ben["talking"] = 0
	var h0 := float(ben["needs"]["hunger"])
	var picked := false
	for i in 30:
		Sim.tick()
		var o = ben.get("option")
		if o is Dictionary and String(o.get("kind", "")) != "social":
			picked = true
	_ck("附身后引擎不自动决策", not picked)
	_ck("需求照常衰减", float(ben["needs"]["hunger"]) < h0, "hunger %.1f → %.1f" % [h0, float(ben["needs"]["hunger"])])

	# ── 2) 「按 E」：身边的物件 ──
	var target_obj := ""
	var target_act := ""
	var target_need := ""
	for oid in Sim.world["objects"]:
		var o: Dictionary = Sim.world["objects"][oid]
		if String(o.get("space", "town")) != sp or String(o.get("floor", "outdoor")) != fl:
			continue
		for a in Sim._life_object_actions(ben, o):
			if bool(a["ok"]) and int(a["duration"]) >= 2 and _free_neighbor(sp, fl, o["pos"]).x > -99:
				target_obj = String(oid); target_act = String(a["action"]); target_need = String(a["need"])
				break
		if target_obj != "":
			break
	_ck("找到可用物件", target_obj != "", "%s / %s" % [target_obj, target_act])
	var opos: Vector2i = Sim.world["objects"][target_obj]["pos"]
	_place(ben, sp, fl, _free_neighbor(sp, fl, opos))
	var near := Sim.life_interactions()
	var listed := false
	for e in near:
		if String(e["kind"]) == "object" and String(e["id"]) == target_obj:
			listed = true
	_ck("身边物件出现在互动列表", listed, "%d 项" % near.size())

	# ── 3) life_use：引擎自己的 object 单 ──
	ben["needs"][target_need] = 20.0
	var r := Sim.life_use(target_obj, target_act)
	_ck("下单成功", r == "" and ben.get("option") is Dictionary, r)
	var done := false
	for i in 200:
		Sim.tick()
		if ben.get("option") == null:
			done = true
			break
	_ck("用完自然结束", done)
	_ck("需求回升", float(ben["needs"][target_need]) > 20.0, "%s=%.1f" % [target_need, float(ben["needs"][target_need])])
	_ck("用完后不自动续单", ben.get("option") == null)
	_ck("不可用动作被拒", Sim.life_use(target_obj, "不存在的动作") != "")

	# ── 4) life_move 打断手头的事 ──
	Sim.life_use(target_obj, target_act)
	var moved := false
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if Sim.life_move(d) == "":
			moved = true
			break
	_ck("走一格", moved)
	_ck("走动打断行动", ben.get("option") == null)

	# ── 5) 社交 + 说法 ──
	var aria: Dictionary = Sim.get_agent("aria")
	var spot := _free_neighbor(sp, fl, ben["pos"])
	_place(aria, sp, fl, spot)
	var vopts := Sim.life_verb_options("aria")
	var greet_ok := false
	for v in vopts:
		if String(v["action"]) == "greet" and bool(v["ok"]):
			greet_ok = true
	_ck("打招呼可用", greet_ok, str(vopts))
	var legal: Array = []
	for v in vopts:
		if bool(v["ok"]):
			legal.append(String(v["action"]))
	var aps := AIBackend.approach_floor(ben, aria, legal)
	_ck("规则地板给出说法", aps.size() >= 2 and String(aps[0]["line"]) != "", str(aps.slice(0, 2)))
	var aps2 := AIBackend.approach_floor(ben, aria, legal)
	_ck("规则地板确定", str(aps) == str(aps2))
	var bad_verb := false
	for a in aps:
		if not (String(a["verb"]) in legal):
			bad_verb = true
	_ck("说法只用合法动词", not bad_verb)
	var mark := Sim.event_log.size()
	var line := String(aps[0]["line"])
	r = Sim.life_social(String(aps[0]["verb"]), "aria", line)
	_ck("开口成功", r == "", r)
	_ck("台词换成挑中的说法", String(ben.get("last_say", "")) == line, String(ben.get("last_say", "")))
	_tickn(14)
	var ev_ok := false
	for i in range(mark, Sim.event_log.size()):
		var e: Dictionary = Sim.event_log[i]
		if String(e["actor"]) == "ben" and String(e["target"]) == "aria" and String(e["type"]) == String(aps[0]["verb"]):
			ev_ok = true
	_ck("事务落账（事件）", ev_ok)
	_ck("理论无疙瘩时被拒", Sim.life_social("confront", "aria") != "")
	var mood := Sim.life_mood()
	var has_social := false
	for p in mood["parts"]:
		if String(p["text"]).find("阿丽") >= 0:
			has_social = true
	_ck("心情记得刚才的社交", has_social and int(mood["score"]) >= -10 and int(mood["score"]) <= 10 and String(mood["label"]) != "", str(mood))
	_ck("心情确定（同状态同结果）", str(Sim.life_mood()) == str(mood))

	# ── 6) 模型说法解析：只收合法动词 ──
	var parsed := AIBackend.parse_approaches("1. 打招呼|热情|开心|今天海风真舒服！\n送礼|温柔|害羞|给你\n乱写一行\ngreet|随和|平静|嗨", ["greet"])
	_ck("解析丢掉非法动词与坏行", parsed.size() == 2 and String(parsed[0]["verb"]) == "greet" and String(parsed[0]["line"]) == "今天海风真舒服！", str(parsed))
	var got: Array = []                       # lambda 按值捕获局部变量 ⇒ 只能原地改数组，不能重新赋值
	var calls: Array = []
	AIBackend.suggest_approaches(ben, aria, legal, {}, func(l: Array): calls.append(1); got.append_array(l))
	_ck("logic 档不发模型请求", calls.is_empty())
	var prev_be := AIBackend.backend
	AIBackend.backend = "mock"
	AIBackend.suggest_approaches(ben, aria, legal, {}, func(l: Array): calls.append(1); got.append_array(l))
	AIBackend.backend = prev_be
	_ck("模型档回包标记为 ai 且只含合法动词", not got.is_empty() and String(got[0]["src"]) == "ai" and String(got[0]["verb"]) in legal, str(got.slice(0, 1)))

	# ── 6a) 自由对话落账：双方记忆各一条；远了拒 ──
	_place(aria, String(ben["space"]), String(ben["floor"]), _free_neighbor(String(ben["space"]), String(ben["floor"]), ben["pos"]))   # 招呼后 14 tick 她可能已走开
	var ma: int = aria["memory"].items.size() if aria["memory"].get("items") != null else -1
	var cr := Sim.life_chat_commit("aria", "今天海风大吗", "大着呢，帽子都吹跑了")
	var ma2: int = aria["memory"].items.size() if aria["memory"].get("items") != null else -1
	_ck("自由对话落账", bool(cr.get("ok", false)) and (ma < 0 or ma2 == ma + 1), "%s mem %d→%d" % [str(cr), ma, ma2])
	_ck("对自己说话被拒", not bool(Sim.life_chat_commit("ben", "x", "y").get("ok", false)))

	# ── 6b) 语气项：确定、按性格/交情分档，默认路径恒 0 ──
	var coco: Dictionary = Sim.get_agent("coco")      # 内向·敏感
	_ck("语气归类（自由文本）", Sim._tone_class("有点害羞地") == "腼腆" and Sim._tone_class("开玩笑") == "调侃" and Sim._tone_class("莫名其妙") == "")
	_ck("热情对热情的人加分", Sim._tone_term(ben, aria, "热情") > 0.0, "%.1f" % Sim._tone_term(ben, aria, "热情"))
	_ck("热情对内向敏感的人减分", Sim._tone_term(ben, coco, "热情") < 0.0, "%.1f" % Sim._tone_term(ben, coco, "热情"))
	_ck("陌生人开不起玩笑", Sim._tone_term(ben, coco, "调侃") < 0.0)
	_ck("无法归类的语气不加减", Sim._tone_term(ben, aria, "嗯") == 0.0)
	_ck("判定加项默认复位为 0", Sim._tone_bonus == 0.0)
	var fam_before := (ben["relationships"] as Dictionary).has("coco")
	Sim.life_tone_hint("coco", "热情")
	_ck("语气提示只读（不建空账）", (ben["relationships"] as Dictionary).has("coco") == fam_before)

	# ── 6c) 点地走路：A* 逐格，被附身者自己的步频 ──
	var start: Vector2i = ben["pos"]
	var goal := start
	var g2 := Sim._grid_for(String(ben["space"]), String(ben["floor"]))
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			var c := start + Vector2i(dx, dy)
			if absi(dx) + absi(dy) >= 3 and Sim._cell_walkable(g2, c) and goal == start:
				goal = c
	var arrived := false
	for i in 40:
		var sr := Sim.life_step_toward(goal)
		if sr == "arrived":
			arrived = true
			break
		if sr == "blocked":
			break
	_ck("点地走到目标格", arrived and ben["pos"] == goal, "%s → %s" % [str(start), str(goal)])

	# ── 6d) 完成信号：被附身者做完一件物件动作 → life_action_done ──
	var done_log: Array = []
	var cb := func(a: String, t: String, _w: int): done_log.append([a, t])
	Sim.life_action_done.connect(cb)
	_place(ben, sp, fl, _free_neighbor(sp, fl, opos))
	Sim.life_use(target_obj, target_act)
	for i in 200:
		Sim.tick()
		if ben.get("option") == null:
			break
	Sim.life_action_done.disconnect(cb)
	_ck("做完发 life_action_done", done_log.size() == 1 and String(done_log[0][0]) == target_act, str(done_log))

	# ── 7) Portal：贴身穿门，权限照验 ──
	_place(ben, "town", "outdoor", ben["pos"] if sp == "town" else Sim._area_centroid("plaza"))
	var hop: Dictionary = {}
	for h in Sim._portals_from("town", "outdoor", ben):
		if String(h.get("access", "")) == "public" and _free_neighbor("town", "outdoor", h["from_pos"]).x > -99:
			hop = h
			break
	_ck("找到公共门", not hop.is_empty(), str(hop.get("portal_id", "")))
	if not hop.is_empty():
		_place(ben, "town", "outdoor", _free_neighbor("town", "outdoor", hop["from_pos"]))
		var far := Sim.life_portal(hop["from_pos"] + Vector2i(5, 5))
		_ck("离门远被拒", not bool(far.get("ok", false)))
		var pr := Sim.life_portal(hop["from_pos"])
		_ck("穿门成功", bool(pr.get("ok", false)) and String(ben["space"]) == String(hop["to_space"]), str(pr.get("reason", "")))

	# ── 7b) 存档 meta 读回（生活模式状态随档走）──
	var sp_path := "user://life_test_meta.sav"
	var saved := Sim.save_game(sp_path, {"name": "t", "life": {"pid": "ben", "score": 123}})
	var loaded := Sim.load_game(sp_path)
	_ck("存读档带回生活模式 meta", saved and loaded and int((Sim.loaded_meta.get("life", {}) as Dictionary).get("score", -1)) == 123, "saved=%s loaded=%s meta=%s" % [saved, loaded, str(Sim.loaded_meta)])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sp_path))

	# ── 8) 解除 / 重开 ──
	Sim.possess("")
	_ck("解除附身", Sim.controlled_id == "" and Sim.life_status().is_empty())
	Sim.possess("coco")
	Sim.start_new(7)
	_ck("world_reset 清附身", Sim.controlled_id == "")

	print("=== %s（失败 %d） ===" % [("全部通过" if _fails == 0 else "有失败"), _fails])
	get_tree().quit(1 if _fails > 0 else 0)
