extends Node
## P1-c East Ocean carrier 合同门：物理锚闭合；一 route/node 至多一艘可见货船；manifest 仍是唯一权威。

const SimScript = preload("res://scripts/Sim.gd")
const ViewScript = preload("res://scripts/WorldView.gd")
const Inv = preload("res://bench/Invariants.gd")

var _fails := 0

func ck(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
	print(("  OK   " if ok else "  FAIL ") + msg)

func projection(S) -> Array:
	return ViewScript.carrier_projections_for(S.logistics, S.cargo_manifests, S.cargo_manifest_order)

func v2(raw) -> Vector2i:
	return Vector2i(int(raw[0]), int(raw[1])) if raw is Array and raw.size() >= 2 else Vector2i(-1, -1)

func population_projection(S) -> Array:
	var out: Array = []
	for aid in S._population_area_ids():
		out.append([String(aid), S._area_centroid(String(aid))])
	return out

func clone_projection(S, first: int, last_exclusive: int) -> Array:
	var out: Array = []
	for i in range(first, last_exclusive):
		var ag: Dictionary = S.get_agent("npc_%d" % i)
		out.append([String(ag.get("id", "")), ag.get("home"), ag.get("pos")])
	return out

func _ready() -> void:
	var S = SimScript.new()
	add_child(S)
	S.auto_run = false
	S.backend = null
	S.start_new(1)

	var dock: Dictionary = S.world.get("areas", {}).get("dock", {})
	var north_pier: Dictionary = S.world.get("areas", {}).get("north_pier", {})
	var port: Dictionary = S.world.get("objects", {}).get("port_dock", {})
	var bench: Dictionary = S.world.get("objects", {}).get("bench_pier", {})
	var tao: Dictionary = S.get_agent("tao")
	var dr: Array = dock.get("rect", [])
	var nr: Array = north_pier.get("rect", [])
	ck(dr.size() == 4 and int(dr[0]) == 56 and int(dr[1]) == 7 and int(dr[2]) == 4 and int(dr[3]) == 2
		and dock.get("facing") == "east" and v2(dock.get("berth", [])) == Vector2i(60, 8)
		and dock.get("route_id") == "east_ocean",
		"East Ocean dock rect/facing/berth/route 物理锚闭合（dock=%s）" % str(dock))
	ck(nr.size() == 4 and int(nr[0]) == 30 and int(nr[1]) == 7 and int(nr[2]) == 4 and int(nr[3]) == 2
		and north_pier.get("type") == "plaza"
		and bool(north_pier.get("population_anchor", false))
		and not bool(dock.get("population_anchor", true))
		and bench.get("area") == "north_pier" and bench.get("pos") == Vector2i(31, 7),
		"north_pier 独立承载渔台，并精确保留旧人口扩容锚（north=%s bench=%s）" % [str(north_pier), str(bench)])
	ck(port.get("pos") == Vector2i(59, 8) and tao.get("home") == Vector2i(58, 8)
		and tao.get("pos") == Vector2i(58, 8),
		"port_dock/Tao home+spawn 闭合到 East Ocean")
	var expected_population := [
		["home", Vector2i(22, 16)], ["cafe", Vector2i(41, 16)],
		["wash", Vector2i(22, 31)], ["work", Vector2i(41, 31)],
		["home2", Vector2i(12, 6)], ["shop", Vector2i(52, 8)],
		["library", Vector2i(12, 41)], ["plaza", Vector2i(32, 24)],
		["north_pier", Vector2i(32, 8)],
	]
	ck(population_projection(S) == expected_population,
		"扩容锚 ID/著者序/质心逐项等于旧 9-area 合同")
	var areas0: Dictionary = S.world.get("areas", {}).duplicate(true)
	var mutated: Dictionary = areas0.duplicate(true)
	mutated["dock"]["population_anchor"] = true
	S.world["areas"] = mutated
	ck(population_projection(S) != expected_population, "East dock 错开 population_anchor 会被 exact tuple 牙抓住")
	for bad_flag in [0, "false", null]:
		mutated = areas0.duplicate(true)
		mutated["north_pier"]["population_anchor"] = bad_flag
		S.world["areas"] = mutated
		ck(not S._population_area_ids().has("north_pier"),
			"非 bool population_anchor=%s 在 runtime fail-closed" % str(bad_flag))
	mutated = areas0.duplicate(true)
	mutated["home"]["rect"][0] = 21
	S.world["areas"] = mutated
	ck(population_projection(S) != expected_population, "前八区任一 rect/质心漂移会被 exact tuple 抓住")
	S.world["areas"] = areas0
	var carriers0 = S.logistics.get("carriers", []).duplicate(true)
	S.logistics["carriers"] = []
	ck(population_projection(S) == expected_population, "carrier View off-gate 不绕过空间/人口锚合同")
	S.logistics["carriers"] = carriers0

	var Scale = SimScript.new()
	add_child(Scale)
	Scale.auto_run = false
	Scale.backend = null
	Scale.spawn_count = 23 # total N=24 after Tao affiliate
	Scale.start_new(7)
	var first_six := clone_projection(Scale, 12, 18)
	var expected_first_six := [
		["npc_12", Vector2i(40, 31), Vector2i(40, 31)],
		["npc_13", Vector2i(12, 6), Vector2i(12, 6)],
		["npc_14", Vector2i(53, 8), Vector2i(53, 8)],
		["npc_15", Vector2i(11, 42), Vector2i(11, 42)],
		["npc_16", Vector2i(32, 25), Vector2i(32, 25)],
		["npc_17", Vector2i(33, 9), Vector2i(33, 9)],
	]
	ck(first_six == expected_first_six, "N24 npc_12..17 使用冻结旧 anchor 几何（含第9锚）")
	var clones0 := clone_projection(Scale, 12, 23)
	Scale.start_new(7)
	ck(clone_projection(Scale, 12, 23) == clones0, "N24 同 seed restart 的 clone home/pos 序列不漂")
	var scale_save := "user://p1c_population_anchor_test.save"
	ck(Scale.save_game(scale_save) and Scale.load_game(scale_save)
		and clone_projection(Scale, 12, 23) == clones0,
		"N24 save/load 保留 clone home/pos 序列")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scale_save))
	ck(projection(S).is_empty(), "零 ready manifest 时零 cargo carrier")

	var stock0: Dictionary = S.town_stock.duplicate(true)
	var town0 := int(S.town_coin)
	var external0 := int(S.external_coin)
	var ev0 := int(S.event_log.size())
	S.day = 3
	S._logi_import()
	var p := projection(S)
	ck(S.event_log.size() == ev0 + 1 and S.town_stock == stock0
		and int(S.town_coin) == town0 and int(S.external_coin) == external0,
		"arrival 只增 manifest receipt，不改钱库")
	ck(p.size() == 1 and String(p[0].get("manifest_id", "")) == "manifest_east_ocean_3_0"
		and v2(p[0].get("berth", [])) == Vector2i(60, 8) and int(p[0].get("ready_count", 0)) == 1,
		"首张 ready manifest 投影为 berth 上恰一艘货船（projection=%s）" % str(p))
	var dup_ev := int(S.event_log.size())
	S._logi_import()
	ck(S.event_log.size() == dup_ev and projection(S) == p, "同日重复 arrival 幂等且不复制货船")

	var U = SimScript.new()
	add_child(U)
	U.auto_run = false
	U.backend = null
	U.start_new(1)
	U.day = 3
	U._logi_import()
	var unload_id := "manifest_east_ocean_3_0"
	var unload_good := String(U.cargo_manifests[unload_id].get("good", ""))
	U.town_stock[unload_good] = 0 # focused positive fixture: guarantee room for the exact batch
	ck(projection(U).size() == 1
		and U._commit_manifest_unload(unload_id, "tao", "port_dock", true) == 4
		and projection(U).is_empty(),
		"真实 exact unload 把唯一 ready cargo 清零后货船立即消失")

	for d in [6, 9]:
		S.day = d
		S._logi_import()
	p = projection(S)
	ck(p.size() == 1 and int(p[0].get("ready_count", 0)) == 3
		and int(p[0].get("ready_qty", 0)) == 12
		and String(p[0].get("manifest_id", "")) == "manifest_east_ocean_3_0",
		"三单 backlog 仍是一艘船 + 3 单徽记，FIFO 绑定最早 manifest")
	S.cargo_manifests["manifest_east_ocean_3_0"]["remaining_qty"] = 0
	S.cargo_manifests["manifest_east_ocean_3_0"]["state"] = "complete"
	p = projection(S)
	ck(p.size() == 1 and int(p[0].get("ready_count", 0)) == 2
		and String(p[0].get("manifest_id", "")) == "manifest_east_ocean_6_0",
		"最早单完成后同一艘船确定重绑下一单")

	var chain0 := int(Inv.chain_step(0, S, S.event_log.size()))
	var save_path := "user://p1c_east_ocean_carrier_test.save"
	ck(S.save_game(save_path), "carrier backlog 的 manifest 权威态可存档")
	S.cargo_manifests.clear()
	S.cargo_manifest_order.clear()
	ck(S.load_game(save_path) and projection(S) == p
		and int(Inv.chain_step(0, S, S.event_log.size())) == chain0,
		"读档恢复 manifest 后纯 View carrier projection/chain 同一")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	# View off-gate：删 carrier 声明只关闭表现，不触碰 manifest、事件、导航或 chain。
	var logistics_off: Dictionary = S.logistics.duplicate(true)
	logistics_off.erase("carriers")
	var manifests0: Dictionary = S.cargo_manifests.duplicate(true)
	var order0: Array = S.cargo_manifest_order.duplicate(true)
	var events0: Array = S.event_log.duplicate(true)
	ck(ViewScript.carrier_projections_for(logistics_off, S.cargo_manifests, S.cargo_manifest_order).is_empty()
		and S.cargo_manifests == manifests0 and S.cargo_manifest_order == order0 and S.event_log == events0
		and int(Inv.chain_step(0, S, S.event_log.size())) == chain0,
		"删 carriers 配置时只有货船不可见，Sim 权威态/事件/chain 不变")
	var manifests_rekeyed: Dictionary = {}
	for i in range(order0.size() - 1, -1, -1):
		var mid := String(order0[i])
		manifests_rekeyed[mid] = manifests0[mid].duplicate(true)
	ck(ViewScript.carrier_projections_for(S.logistics, manifests_rekeyed, order0) == p,
		"Dictionary 插入序反转不影响 authored order 的 carrier projection")

	print("p1c_east_ocean_carrier_test: %s (%d fail)" % [("PASS ✅" if _fails == 0 else "FAIL ❌"), _fails])
	get_tree().quit(1 if _fails > 0 else 0)
