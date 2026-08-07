extends Node
## state_projection_gate.gd — AO1 · state_projection_v1 的【真咬门】（docs/137）
##
## 两半（docs/121 §六 阶段 1-3）：
##   ① round-trip：save→load→re-save，两次投影【规范哈希相同】（load_game 漏还原任一权威字段 → 红）。
##   ② mutation（牙）：逐字段扰动 → 投影哈希【必须变】。这半才抓得住"静默丢一个字段"。
##      - 具名 A/B：复刻 docs/121 §三.1 的五条 + 11 个 headline 家族，三列并排
##        （Inv.digest / Inv.chain_step / StateProjection），坐实"旧折叠盲、投影不盲"。
##      - 全量扫：活 agent 的每个字段 + 存档权威面的每个 world 字段，泛型扰动 → 断言变（覆盖证明=全权威面）。
##   ③ 规范序负对照：键序不同但逻辑相同的世界 → 投影相等（红线#1 命门）。
##   ④ AF1 回归：复刻 docs/121 §四——同一"漏 belief 的读档"，save_load 的 Inv.digest 门盲（PASS），投影抓住（FAIL）。
##   ⑤ does_not_detect 包络（实测）：非持久面（派生缓存/视口/bench/存档名）扰动 → 投影 SAME（按设计，正确）。
## 用法：godot --headless --path game res://scenes/state_projection_gate.tscn
const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")
const Proj = preload("res://bench/StateProjection.gd")

var _fails := 0
const SEED := 20260626
const T := 160

func ck(c: bool, m: String) -> void:
	if not c: _fails += 1
	print(("  OK   " if c else "  FAIL ") + m)

func _boot() -> Object:
	var S = SimScript.new()
	add_child(S)
	S.start_new(SEED)
	for i in range(T): S.tick()
	return S

func _ph(S) -> int:
	return int(Proj.project_sim(S)["hash"])

# 点对点 digest / chain（固定 prev/ev_from → 只量"这一刻"能不能分辨，不掺未来）
func _dg(S) -> int: return int(Inv.digest(S))
func _ch(S) -> int: return int(Inv.chain_step(0, S, S.event_log.size()))

func _cget(c, f):
	if c is Dictionary: return c[f]
	return c.get(f)
func _cset(c, f, v) -> void:
	if c is Dictionary: c[f] = v
	else: c.set(f, v)

# 泛型扰动：返回 [can_mutate, new_value]。dict/array 走深拷贝改副本（原引用不动，还原免快照）。
func _mutate_value(v) -> Array:
	match typeof(v):
		TYPE_DICTIONARY:
			var d = (v as Dictionary).duplicate(true); d["__ao1_probe__"] = 424242; return [true, d]
		TYPE_ARRAY:
			var a = (v as Array).duplicate(true); a.append("__ao1_probe__"); return [true, a]
		TYPE_STRING, TYPE_STRING_NAME:
			return [true, String(v) + "_ao1probe"]
		TYPE_INT:
			return [true, int(v) + 424242]
		TYPE_FLOAT:
			return [true, float(v) + 1.5]
		TYPE_BOOL:
			return [true, not v]
		TYPE_VECTOR2I:
			return [true, (v as Vector2i) + Vector2i(1, 1)]
		TYPE_VECTOR2:
			return [true, (v as Vector2) + Vector2(1, 1)]
		TYPE_NIL:
			return [true, 424242]
		_:
			return [false, null]

func _ready() -> void:
	print("=== state_projection_gate (v%d) ===" % Proj.PROJECTION_VERSION)
	_test_roundtrip()
	_test_named_ab()
	_test_full_sweep()
	_test_canonical_order()
	_test_af1_regression()
	_test_does_not_detect()
	_test_perf()
	print("state_projection_gate: %s (%d fail)" % [("PASS ✅" if _fails == 0 else "FAIL ❌"), _fails])
	get_tree().quit(1 if _fails > 0 else 0)

# ── ① round-trip ─────────────────────────────────────────────────────────────
func _test_roundtrip() -> void:
	print("— ① round-trip（save→load→re-save 投影相等）—")
	var pa := "user://__ao1_rt_a.dat"; var pb := "user://__ao1_rt_b.dat"
	for p in [pa, pb]:
		if FileAccess.file_exists(p): DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var A = _boot()
	ck(A.save_game(pa, {"name": "rt"}), "save A")
	var ha := int(Proj.project_file(pa)["hash"])
	var B = SimScript.new(); add_child(B)
	ck(B.load_game(pa), "load B")
	ck(B.save_game(pb, {"name": "rt"}), "re-save B")
	var hb := int(Proj.project_file(pb)["hash"])
	ck(ha != 0 and ha == hb, "round-trip 投影相等 (A=%d B=%d)" % [ha, hb])
	# 活 Sim 直投 vs 文件投一致（project_sim 与 project_file 同源）
	ck(_ph(A) == ha, "project_sim(A) == project_file(A)")

# ── ② 具名 A/B：三列并排（digest / chain / proj）复刻 docs/121 §三.1 ─────────────
func _test_named_ab() -> void:
	print("— ② 具名 A/B：点对点 digest·chain·proj（SAME=盲，DIFF=抓住）—")
	print("    %-26s | %-8s %-8s %-8s | 判" % ["干预(只改一个字段)", "digest", "chain", "proj"])
	var families := [
		"清空某 agent beliefs", "town_stock 每种 +20", "某 agent 换平面(space/floor/area)",
		"某 agent attitude=0.9", "某 agent standing=-30", "relationships.affinity=-50",
		"agent.affinity[pid]=1.0", "某 agent 加一条 pact", "某 agent faction=PROBE",
		"某 agent skills[act]+=5", "inventory.coin=99999(money)", "inventory.gift=999",
		"memory 加一条", "complementSeen[pid]=9", "faction_size=99",
		"town_coin+=1000", "day+=1", "weather_today=PROBE",
		"factions[probe]", "pacts_index 加一条",
	]
	for name in families:
		var S = _boot()
		var ag = S.agents[0]
		var pid := String(S.agents[1]["id"]) if S.agents.size() > 1 else "x"
		var d0 := _dg(S); var c0 := _ch(S); var p0 := _ph(S)
		_apply_named(S, ag, pid, name)
		var d1 := _dg(S); var c1 := _ch(S); var p1 := _ph(S)
		var dsame := d0 == d1; var csame := c0 == c1; var pdiff := p0 != p1
		print("    %-26s | %-8s %-8s %-8s | %s" % [
			name, ("SAME" if dsame else "DIFF"), ("SAME" if csame else "DIFF"),
			("DIFF" if pdiff else "SAME"), ("✓" if pdiff else "✗ 投影没抓住!")])
		ck(pdiff, "投影抓住 [%s]" % name)
		S.free()

func _apply_named(S, ag, pid, name) -> void:
	match name:
		"清空某 agent beliefs":
			var who = _agent_with(S, "beliefs")
			if who != null: (who["beliefs"] as Dictionary).clear()
		"town_stock 每种 +20":
			if (S.town_stock as Dictionary).is_empty(): S.town_stock["__probe__"] = 20
			else:
				for k in S.town_stock: S.town_stock[k] = int(S.town_stock[k]) + 20
		"某 agent 换平面(space/floor/area)":
			ag["space"] = "cafe"; ag["floor"] = "2f"; ag["area"] = "cafe:2f"
		"某 agent attitude=0.9":
			for t in ag["attitudes"]: ag["attitudes"][t] = 0.9
			if (ag["attitudes"] as Dictionary).is_empty(): ag["attitudes"]["__probe__"] = 0.9
		"某 agent standing=-30":
			ag["relationships"][pid] = {"affinity": 0.0, "standing": -30.0}
		"relationships.affinity=-50":
			ag["relationships"][pid] = {"affinity": -50.0, "standing": 0.0}
		"agent.affinity[pid]=1.0":
			ag["affinity"][pid] = 1.0
		"某 agent 加一条 pact":
			ag["pacts"][pid] = {"partner": pid, "status": "active"}
		"某 agent faction=PROBE":
			ag["faction"] = "PROBE"
		"某 agent skills[act]+=5":
			ag["skills"]["__probe__"] = int(ag["skills"].get("__probe__", 0)) + 5
		"inventory.coin=99999(money)":
			ag["inventory"]["coin"] = 99999
		"inventory.gift=999":
			ag["inventory"]["gift"] = 999
		"memory 加一条":
			var m = ag["memory"]
			if m is Object and "items" in m: m.items.append({"__probe__": 1})
		"complementSeen[pid]=9":
			ag["complementSeen"][pid] = 9.0
		"faction_size=99":
			ag["faction_size"] = 99
		"town_coin+=1000":
			S.town_coin += 1000
		"day+=1":
			S.day += 1
		"weather_today=PROBE":
			S.weather_today = "PROBE"
		"factions[probe]":
			S.factions["__probe__"] = ["x"]
		"pacts_index 加一条":
			S.pacts_index.append({"id": -424242})

func _agent_with(S, field):
	for a in S.agents:
		if a.has(field) and (a[field] is Dictionary) and not (a[field] as Dictionary).is_empty():
			return a
	return S.agents[0]

# ── ② 全量扫：活 agent 每字段 + world 权威面每字段 → 泛型扰动 → 断言变 ──────────
func _test_full_sweep() -> void:
	print("— ② 全量扫：每个持久字段泛型扰动 → 投影必变（覆盖=全权威面）—")
	var S = _boot()
	var base := _ph(S)
	var ag = S.agents[0]
	var agent_hole := []
	var agent_ok := 0
	var agent_skip := []
	for field in ag.keys():
		var r := _probe(S, ag, String(field))
		if r == "ok": agent_ok += 1
		elif r == "hole": agent_hole.append(String(field))
		else: agent_skip.append(String(field))
		ck(_ph(S) == base, "扫后状态复原 [agent.%s]" % field)
	# world 权威面（取自 baseline 存档 manifest）
	# ⑤-does_not_detect（按设计，实测确认）：backend/ext 是【运行时 Object 服务引用】（AI 后端，`Sim.gd:407/410`
	#   `Object = null`）——save_game 落盘时它们是 null（Object 不进持久态、load 时重新接线，非从存档还原）。
	#   ⇒ 扰动它们【投影不变】是【正确】：它们不属"必须 round-trip 的权威持久态"，与 DERIVED 缓存同类。
	#   （full-sweep 泛扫所有 world script-var，会顺带碰到这两个非持久 Object 引用；这里白名单剔除、记为 dnd。）
	const WORLD_DND := ["backend", "ext"]
	var man := _manifest(S)
	var world_hole := []
	var world_ok := 0
	var world_skip := []
	var world_dnd := []
	for field in man.world_fields:
		if field == "agents": continue
		if String(field) in WORLD_DND:
			world_dnd.append(String(field))   # 运行时 Object 服务引用，非持久权威态，does_not_detect 按设计
			continue
		var r := _probe(S, S, String(field))
		if r == "ok": world_ok += 1
		elif r == "hole": world_hole.append(String(field))
		else: world_skip.append(String(field))
	print("    agent 字段: 覆盖 %d / 洞 %d / 跳过 %d %s" % [agent_ok, agent_hole.size(), agent_skip.size(), str(agent_skip)])
	print("    world 字段: 覆盖 %d / 洞 %d / 跳过 %d %s / dnd %d %s" % [world_ok, world_hole.size(), world_skip.size(), str(world_skip), world_dnd.size(), str(world_dnd)])
	if not agent_hole.is_empty(): print("    ⚠ agent 覆盖洞: %s" % str(agent_hole))
	if not world_hole.is_empty(): print("    ⚠ world 覆盖洞: %s" % str(world_hole))
	print("    ⑤ world does_not_detect（按设计，运行时 Object 服务引用）: %s" % str(world_dnd))
	ck(agent_hole.is_empty(), "agent 权威面无覆盖洞")
	ck(world_hole.is_empty(), "world 权威面无覆盖洞（backend/ext 除外：运行时 Object 服务引用，非持久态，does_not_detect 按设计）")
	print("    覆盖清单: world=%d agent=%d agents=%d" % [man.world_count, man.agent_field_count, man.agent_count])

# 返回 "ok"(在覆盖内) / "hole"(扰动了但投影没变) / "skip"(无法泛型扰动，如 memory Object)
func _probe(S, container, field) -> String:
	var old = _cget(container, field)
	var base := _ph(S)
	# memory 是 Object：特案扰 items（save 会序列化成 __mem_items__）
	if old is Object:
		if String(field) == "memory" and ("items" in old):
			var snap = (old.items as Array).duplicate(true)
			old.items.append({"__ao1_probe__": 1})
			var hm := _ph(S)
			old.items = snap
			return "ok" if hm != base else "hole"
		return "skip"
	var mv := _mutate_value(old)
	if not mv[0]: return "skip"
	_cset(container, field, mv[1])
	var h1 := _ph(S)
	_cset(container, field, old)   # 还原（dict/array 改的是副本，old 原样）
	return "ok" if h1 != base else "hole"

func _manifest(S) -> Dictionary:
	var p := "user://__ao1_man.dat"
	S.save_game(p, {})
	var f := FileAccess.open(p, FileAccess.READ)
	f.get_32(); var blob = f.get_var(); f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	return Proj.manifest(blob)

# ── ③ 规范序负对照（红线#1 命门）─────────────────────────────────────────────
func _test_canonical_order() -> void:
	print("— ③ 规范序：键序不同、逻辑相同 → 投影相等 —")
	var d1 := {}; d1["b"] = 2; d1["a"] = 1; d1["c"] = 3; d1["nest"] = {"y": 9, "x": 8}
	var d2 := {}; d2["nest"] = {"x": 8, "y": 9}; d2["c"] = 3; d2["a"] = 1; d2["b"] = 2
	var h1 := Proj.fold(Proj.OFF, d1); var h2 := Proj.fold(Proj.OFF, d2)
	ck(h1 == h2, "键序无关：fold(d1)==fold(d2) (%d)" % h1)
	var d3 := {}; d3["a"] = 1; d3["b"] = 2; d3["c"] = 3; d3["nest"] = {"x": 8, "y": 999}
	ck(Proj.fold(Proj.OFF, d3) != h1, "值不同则哈希不同（灵敏）")
	# 类型不混：int 1 vs string "1" vs bool true
	ck(Proj.fold(Proj.OFF, 1) != Proj.fold(Proj.OFF, "1"), "int 1 ≠ string \"1\"")
	ck(Proj.fold(Proj.OFF, true) != Proj.fold(Proj.OFF, 1), "bool true ≠ int 1")
	# 真 agent 的 beliefs 字典：逆序重建 → 投影相等
	var S = _boot()
	var who = _agent_with(S, "relationships")
	var rel: Dictionary = who["relationships"]
	var rev := {}
	var ks := rel.keys(); ks.reverse()
	for k in ks: rev[k] = rel[k]
	ck(Proj.fold(Proj.OFF, rel) == Proj.fold(Proj.OFF, rev), "真 relationships 逆序重建 → fold 相等")
	S.free()

# ── ④ AF1 回归：复刻 docs/121 §四（旧门盲、投影抓住）────────────────────────────
func _test_af1_regression() -> void:
	print("— ④ AF1 回归：漏 belief 的读档，Inv.digest 门盲 vs 投影抓住 —")
	var pa := "user://__ao1_af1.dat"
	if FileAccess.file_exists(pa): DirAccess.remove_absolute(ProjectSettings.globalize_path(pa))
	var A = _boot()
	A.save_game(pa, {"name": "af1"})
	var projA := int(Proj.project_file(pa)["hash"])
	var digA := _dg(A)
	# B 完美读档
	var B = SimScript.new(); add_child(B)
	B.load_game(pa)
	# 制造"漏 belief"：清掉 B 某 agent 的一条 belief（AF1 的合成扰动 = 漏字段）
	var who = _agent_with(B, "beliefs")
	var dropped := false
	if who != null and (who["beliefs"] is Dictionary) and not (who["beliefs"] as Dictionary).is_empty():
		var k = (who["beliefs"] as Dictionary).keys()[0]
		(who["beliefs"] as Dictionary).erase(k)
		dropped = true
	ck(dropped, "构造出漏 belief 的 B（有 belief 可丢）")
	var digB := _dg(B)
	var projB := int(Proj.project_sim(B)["hash"])
	# 旧门：Inv.digest 盲（相等 → save_load_test 会判 PASS）
	print("    Inv.digest:  A=%d  B(漏档)=%d  → %s" % [digA, digB, ("SAME(盲)" if digA == digB else "DIFF")])
	print("    Projection:  A=%d  B(漏档)=%d  → %s" % [projA, projB, ("SAME" if projA == projB else "DIFF(抓住)")])
	ck(digA == digB, "复刻: Inv.digest 对漏 belief 盲（SAME）")
	ck(projA != projB, "投影抓住漏 belief（DIFF）← 这是新门的牙")
	# 续跑 N=60 复刻旧门的第二判据也盲
	var drift := -1
	for i in range(60):
		A.tick(); B.tick()
		if _dg(A) != _dg(B): drift = i; break
	print("    续跑 60 tick Inv.digest 漂移点 = %d（-1=永不现形，复刻 docs/121 §四）" % drift)

# ── ⑤ does_not_detect 包络（实测非持久面）──────────────────────────────────────
func _test_does_not_detect() -> void:
	print("— ⑤ does_not_detect：非持久面扰动 → 投影 SAME（按设计，正确）—")
	var S = _boot()
	var base := _ph(S)
	# 派生缓存（save_game DERIVED 排除）
	S._near_set["__probe__"] = 1
	ck(_ph(S) == base, "DERIVED _near_set 扰动 → SAME（缓存非真源）")
	S._path_cache["__probe__"] = {"x": 1}
	ck(_ph(S) == base, "DERIVED _path_cache 扰动 → SAME")
	S._player_pos = Vector2i(7, 7)
	ck(_ph(S) == base, "DERIVED _player_pos 扰动 → SAME")
	# 视口参数（VIEW_PARAMS 排除；红线：相机绝不经存档泄漏）
	S.lod_focus = Vector2i(1, 1)
	ck(_ph(S) == base, "VIEW lod_focus 扰动 → SAME")
	# bench 开关（BENCH_ONLY 排除）
	S.shadow_on = true
	ck(_ph(S) == base, "BENCH shadow_on 扰动 → SAME")
	# 存档 meta（存档名，非 sim 状态）
	var pm := "user://__ao1_meta.dat"
	S.save_game(pm, {"name": "AAAA"}); var hma := int(Proj.project_file(pm)["hash"])
	S.save_game(pm, {"name": "ZZZZ"}); var hmz := int(Proj.project_file(pm)["hash"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pm))
	ck(hma == hmz, "存档 meta(name) 不同 → SAME（投影只折 sim 状态）")

# ── 性能：折叠成本（纯 fold + save+fold 端到端）─────────────────────────────────
func _test_perf() -> void:
	print("— 性能：折叠成本（边界调用，非每 tick）—")
	var S = _boot()
	# 解码一次 blob，测【纯折叠】
	var p := "user://__ao1_perf.dat"; S.save_game(p, {})
	var f := FileAccess.open(p, FileAccess.READ); f.get_32(); var blob = f.get_var(); f.close()
	var man := Proj.manifest(blob)
	var reps := 200
	var t0 := Time.get_ticks_usec()
	for i in range(reps): Proj.project_blob(blob)
	var fold_us := float(Time.get_ticks_usec() - t0) / float(reps)
	# 端到端 save+read+fold（含文件 I/O，reps 小些）
	var reps2 := 40
	t0 = Time.get_ticks_usec()
	for i in range(reps2): Proj.project_sim(S)
	var e2e_us := float(Time.get_ticks_usec() - t0) / float(reps2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("    N=%d agents · world 字段 %d · agent 字段 %d" % [man.agent_count, man.world_count, man.agent_field_count])
	print("    纯折叠  = %.1f µs/次 (%d 次均)" % [fold_us, reps])
	print("    save+读+折 端到端 = %.1f µs/次 (%d 次均)" % [e2e_us, reps])
	ck(fold_us < 50000.0, "纯折叠 < 50ms（边界预算充裕）")
