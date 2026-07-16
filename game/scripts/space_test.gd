extends Node
## P1 Gate（analysis §9）：Space/Floor/Portal 合同 + 兼容层 + Probe 切换/返回栈。
## 用 autoload（Sim）→ 必须走场景：godot --headless --path game res://scenes/space_test.tscn
var _fails := 0
func ck(c: bool, m: String) -> void:
	if not c: _fails += 1
	print(("  OK   " if c else "  FAIL ") + m)

func _ready() -> void:
	Sim.start_new(1)
	var sg = preload("res://scripts/SpaceGraph.gd").new()
	sg.load_from()

	# ── 合同：真数据必须自洽（无悬挂 Portal / floor 引用）──
	ck(sg.loaded, "spaces.json 已加载")
	var errs: Array = sg.validate()
	ck(errs.is_empty(), "validate() 无错 (%s)" % ("ok" if errs.is_empty() else str(errs)))
	ck(sg.has_space("town") and sg.has_floor("town", "outdoor"), "town/outdoor 存在")
	ck(sg.has_space("test_loft") and sg.has_floor("test_loft", "2f"), "test_loft/2f 存在")
	ck(not sg.has_floor("town", "2f"), "town 没有 2f（floor 归属正确）")

	# ── bounds：Probe 相机边界来源（不再直读 Sim.GRID）──
	var tb: Rect2 = sg.bounds_px("town")
	ck(tb.size == Vector2(Sim.GRID.x * 48, Sim.GRID.y * 48), "town bounds = 全图 %s" % str(tb.size))
	ck(sg.bounds_px("test_loft").size == Vector2(6 * 48, 5 * 48), "test_loft bounds = 6x5 格")
	ck(sg.bounds_px("no_such").size == tb.size, "未知 space → 回落全图（off 门，不崩）")

	# ── Portal：双向边的反向查询也要能查到 ──
	var pt_town: Array = sg.portals_from("town", "outdoor")
	ck(pt_town.size() == 1 and String(pt_town[0]["id"]) == "p_loft_door", "town/outdoor 出发有 door portal")
	var pt_2f: Array = sg.portals_from("test_loft", "2f")
	ck(pt_2f.size() == 1 and String(pt_2f[0]["to"]["floor"]) == "1f", "2f 经双向楼梯反查回 1f")

	# ── 兼容层：不带 spatial_address 的老 agent 一律 town/outdoor（Sim 一行没改）──
	var ag: Dictionary = Sim.agents[0]
	var a0: Dictionary = sg.address_of(ag)
	ck(String(a0["space_id"]) == "town" and String(a0["floor_id"]) == "outdoor", "老 agent → 兜底 town/outdoor")
	ck(a0["position"] == ag["pos"], "兜底地址的 position == agent.pos")
	var ag2 := {"pos": Vector2i(1, 1), "spatial_address": {"space_id": "test_loft", "floor_id": "2f", "position": Vector2i(2, 2)}}
	var a1: Dictionary = sg.address_of(ag2)
	ck(String(a1["space_id"]) == "test_loft" and String(a1["floor_id"]) == "2f", "带 spatial_address 的 agent → 用它")

	# ── Probe：切 Space/Floor + 返回栈（inspect-only）──
	var probe = preload("res://scripts/ProbeController.gd").new()
	add_child(probe)
	probe.setup(self, sg.bounds_px("town"))
	ck(probe.active_space == "town" and probe.active_floor == "outdoor", "Probe 初始 town/outdoor")
	probe.set_space("test_loft", sg.default_floor("test_loft"), sg.bounds_px("test_loft"))
	ck(probe.active_space == "test_loft" and probe.active_floor == "1f", "Probe 切到 test_loft/1f")
	ck(probe.cam.limit_right == int(6 * 48) + probe.CAM_MARGIN, "相机边界跟着 active Space 走")
	ck(probe.go_back() and probe.active_space == "town", "go_back 回到 town（返回栈）")

	# ── 红线：Probe 操作没碰 Sim ──
	var before := Sim.tick_no
	probe.set_space("test_loft", "2f", sg.bounds_px("test_loft"))
	probe.follow(String(ag["id"])); probe.unfollow(); probe.go_home()
	ck(Sim.tick_no == before, "Probe 一通操作后 Sim.tick_no 未变（不写 Sim）")

	print("space_test: %d fail" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
