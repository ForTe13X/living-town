extends Node
## P1 Gate（analysis §9）：Space/Floor/Portal 合同 + 兼容层 + Probe 切换/返回栈。
## 用 autoload（Sim）→ 必须走场景：godot --headless --path game res://scenes/space_test.tscn
var _fails := 0
func ck(c: bool, m: String) -> void:
	if not c: _fails += 1
	print(("  OK   " if c else "  FAIL ") + m)

## Main._portal_click 的查表：点 (space,floor,cell) 落在哪条 portal 上 → 目的地 [space,floor]；无则 ["",""]。
func _portal_dest(sg, sp: String, fl: String, cell: Vector2i) -> Array:
	for p in sg.portals:
		for side in ["from", "to"]:
			var e: Dictionary = p[side]
			if String(e["space"]) == sp and String(e["floor"]) == fl and Vector2i(int(e["pos"][0]), int(e["pos"][1])) == cell:
				var o: Dictionary = p["to"] if side == "from" else p["from"]
				return [String(o["space"]), String(o["floor"])]
	return ["", ""]

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
	# town 有 spaces.json 显式 bounds（P2-2 起 = 64×48 大镇）→ 对齐真图尺寸（world.width/height），不再 = Sim.GRID
	ck(tb.size == Vector2(int(Sim.world.get("width", 24)) * 48, int(Sim.world.get("height", 16)) * 48), "town bounds = 真图 %s" % str(tb.size))
	ck(sg.bounds_px("test_loft").size == Vector2(6 * 48, 5 * 48), "test_loft bounds = 6x5 格")
	# 未知 space 无 bounds → 回落 Sim.GRID（保守小兜底，与 town 的显式 bounds 现在不同了）
	ck(sg.bounds_px("no_such").size == Vector2(Sim.GRID.x * 48, Sim.GRID.y * 48), "未知 space → 回落 Sim.GRID（off 门，不崩）")

	# ── Portal：双向边的反向查询也要能查到 ──
	# P3：town/outdoor 现在有两扇门（测试阁楼 p_loft_door + 阿丽咖啡馆 p_cafe_door）——从"恰好 1 扇"放宽到"两扇都在"。
	var pt_town: Array = sg.portals_from("town", "outdoor")
	var town_ids := pt_town.map(func(p): return String(p["id"]))
	ck("p_loft_door" in town_ids and "p_cafe_door" in town_ids, "town/outdoor 出发有测试阁楼门 + 咖啡馆门")
	var pt_2f: Array = sg.portals_from("test_loft", "2f")
	ck(pt_2f.size() == 1 and String(pt_2f[0]["to"]["floor"]) == "1f", "2f 经双向楼梯反查回 1f")
	# P3：咖啡馆 Space 合同——1f/2f 存在、街门反查、楼梯反查回 1f
	ck(sg.has_space("cafe") and sg.has_floor("cafe", "1f") and sg.has_floor("cafe", "2f"), "cafe/1f/2f 存在")
	ck(sg.has_space("port_warehouse") and sg.has_floor("port_warehouse", "1f")
		and sg.bounds_px("port_warehouse").size == Vector2(9 * 48, 6 * 48), "东海货仓 9x6/1f 存在")
	var pt_cafe1: Array = sg.portals_from("cafe", "1f")
	var cafe1_ids := pt_cafe1.map(func(p): return String(p["id"]))
	ck("p_cafe_door" in cafe1_ids and "p_cafe_stairs" in cafe1_ids, "cafe/1f 有街门（反查）+ 上楼梯")
	var pt_cafe2: Array = sg.portals_from("cafe", "2f")
	ck(pt_cafe2.size() == 1 and String(pt_cafe2[0]["to"]["floor"]) == "1f", "cafe/2f 经双向楼梯反查回 1f")

	# ── P3 UX：点门/楼梯穿越（Main._portal_click 的查表逻辑，纳入 CI）──
	ck(_portal_dest(sg, "town", "outdoor", Vector2i(41, 19)) == ["cafe", "1f"], "点镇上咖啡馆门 → cafe/1f（进店）")
	ck(_portal_dest(sg, "cafe", "1f", Vector2i(1, 1)) == ["cafe", "2f"], "点 1F 楼梯 → cafe/2f（上楼）")
	ck(_portal_dest(sg, "cafe", "2f", Vector2i(1, 1)) == ["cafe", "1f"], "点 2F 楼梯 → cafe/1f（下楼）")
	ck(_portal_dest(sg, "cafe", "1f", Vector2i(4, 5)) == ["town", "outdoor"], "点 1F 门 → town/outdoor（出门）")
	ck(_portal_dest(sg, "town", "outdoor", Vector2i(57, 8)) == ["port_warehouse", "1f"], "点东港门 → port_warehouse/1f")
	ck(_portal_dest(sg, "port_warehouse", "1f", Vector2i(8, 3)) == ["town", "outdoor"], "点货仓门 → East Ocean town/outdoor")
	ck(_portal_dest(sg, "town", "outdoor", Vector2i(9, 9)) == ["", ""], "点空地 → 无 portal（不误穿）")
	# P3 数据驱动室内：镇上【每一扇门】都要能点进一个真 Space（且该层有室内内容）——没有空壳建筑。
	var doors_ok := true; var doors_n := 0; var bad := ""
	for d in Sim.world.get("doors", []):
		var dp: Array = (d as Dictionary).get("pos", [0, 0])
		var dest := _portal_dest(sg, "town", "outdoor", Vector2i(int(dp[0]), int(dp[1])))
		doors_n += 1
		if dest[0] == "" or not sg.has_floor(dest[0], dest[1]):
			doors_ok = false; bad = String(d.get("name", "?"))
	ck(doors_ok and doors_n > 0, "镇上 %d 扇门都能进真 Space（无空壳）%s" % [doors_n, ("← 坏门:" + bad) if not doors_ok else ""])

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

	# P1-i 玩家门与室内碰撞：真玩家经同一 portal 原子换平面；WASD 读室内网，不穿货架/外墙。
	var pl: Dictionary = Sim.add_player(Vector2i(57, 8))
	var player_public := Sim._portals_from("town", "outdoor", pl)
	var player_can_warehouse := false
	for h in player_public:
		if h.get("from_pos") == Vector2i(57, 8) and String(h.get("to_space", "")) == "port_warehouse":
			player_can_warehouse = true
	ck(player_can_warehouse, "玩家权限表允许 public 东海货仓门")
	var player_private := Sim._portals_from("cafe", "1f", pl)
	var player_can_private := false
	for h in player_private:
		if String(h.get("to_space", "")) == "cafe" and String(h.get("to_floor", "")) == "2f":
			player_can_private = true
	ck(not player_can_private, "普通玩家不能用点击旁路 owner-only 咖啡馆楼梯")
	var aria: Dictionary = Sim.get_agent("aria")
	var owner_private := Sim._portals_from("cafe", "1f", aria)
	var owner_can_private := false
	for h in owner_private:
		if String(h.get("to_space", "")) == "cafe" and String(h.get("to_floor", "")) == "2f":
			owner_can_private = true
	ck(owner_can_private, "空间主人仍可走 owner-only 楼梯")
	Sim._traverse_portal(pl, {"to_space": "port_warehouse", "to_floor": "1f", "to_pos": Vector2i(8, 3)})
	ck(String(pl.get("space", "")) == "port_warehouse" and pl.get("pos") == Vector2i(8, 3), "玩家实体经门进入货仓")
	Sim.player_move(Vector2i(1, 0))
	ck(pl.get("pos") == Vector2i(8, 3), "货仓外墙阻止玩家向右穿墙")
	Sim.player_move(Vector2i(-1, 0))
	ck(pl.get("pos") == Vector2i(7, 3), "货仓入口向左的地毯格允许玩家踏入室内")
	Sim._traverse_portal(pl, {"to_space": "town", "to_floor": "outdoor", "to_pos": Vector2i(57, 8)})
	ck(String(pl.get("space", "")) == "town" and pl.get("pos") == Vector2i(57, 8), "玩家实体经同门返回东港")

	print("space_test: %d fail" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
