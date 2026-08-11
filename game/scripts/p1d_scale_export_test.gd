extends Node
## P1-d scale export contract: N>12 has real pay→stock providers without weakening the local floor.

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

var _fails := 0

func ck(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
	print(("  OK   " if ok else "  FAIL ") + msg)

func inv_ok(S, iid: int) -> bool:
	for row in Inv.check_all(S, 0):
		if int(row.get("id", -1)) == iid:
			return bool(row.get("ok", false))
	return false

func trade_events(events: Array) -> Array:
	var out: Array = []
	for e in events:
		if not (e is Dictionary):
			continue
		var ty := String(e.get("type", ""))
		if ty == "export" or (ty == "pay" and String(e.get("note", "")).split("*")[0] == "export"):
			out.append(e)
	return out

func fresh(core: int, seed: int):
	var S = SimScript.new()
	add_child(S)
	S.auto_run = false
	S.backend = null
	S.spawn_count = core
	S.start_new(seed)
	return S

func dispose(S) -> void:
	remove_child(S)
	S.free()

func scale_case(core: int, expected_floor: int, expected_odd_floor: int) -> void:
	var S = fresh(core, 100 + core)
	var lane: Dictionary = S.logistics.get("export_lanes", [])[0]
	var good := String(lane.get("good", ""))
	var batch := int(lane.get("batch", 0))
	var every := int(lane.get("every_days", 0))
	var floor := int(lane.get("floor", 0))
	ck(S.agents.size() == core + 1 and S.prod_pool_num == core and S.prod_pool_den == 12,
		"core=%d/total=%d 使用 production pool 而非 affiliate 总数" % [core, core + 1])
	ck(bool(lane.get("scale_floor", false)) and S._scaled_export_floor(floor) == expected_floor,
		"core=%d effective floor=%d" % [core, expected_floor])
	ck(S._scaled_export_floor(35) == expected_odd_floor,
		"core=%d odd floor=35 uses integer ceil => %d" % [core, expected_odd_floor])
	S.day = every
	S.town_stock[good] = expected_floor + batch
	S.external_coin = 100
	var town0 := int(S.town_coin)
	var ev0: int = S.event_log.size()
	S._logi_export()
	var rel := trade_events(S.event_log.slice(ev0))
	var scan := Inv.export_pair_scan(rel)
	ck(int(scan["related"]) == 2 and int(scan["pairs"]) == 1 and (scan["bad"] as Array).is_empty(),
		"core=%d 真实 provider 恰一 pay→stock pair" % core)
	ck(rel.size() == 2 and String(rel[0].get("type", "")) == "pay" and String(rel[1].get("type", "")) == "export",
		"core=%d export 提交顺序 pay→stock" % core)
	ck(int(S.town_stock[good]) == expected_floor and int(S.town_coin) == town0 + batch / 2
		and int(S.external_coin) == 100 - batch / 2,
		"core=%d 固定 batch=%d 的库存/钱 exact commit" % [core, batch])
	ck(inv_ok(S, 46), "core=%d #46 在非空 provider 上通过" % core)
	dispose(S)

func boundary_cases() -> void:
	var S = fresh(15, 215)
	var lane: Dictionary = S.logistics.get("export_lanes", [])[0]
	var good := String(lane.get("good", ""))
	var node := String(lane.get("node", ""))
	var every := int(lane.get("every_days", 0))
	var floor := S._scaled_export_floor(int(lane.get("floor", 0)))
	var batch := int(lane.get("batch", 0))
	S.day = every

	S.town_stock[good] = floor
	S.external_coin = 100
	var state0 := [S.town_stock.duplicate(true), S.town_coin, S.external_coin, S.event_log.size()]
	S._logi_export()
	ck([S.town_stock, S.town_coin, S.external_coin, S.event_log.size()] == state0,
		"stock<=effective floor 时零副作用")

	S.town_stock[good] = floor + batch
	S.external_coin = 0
	state0 = [S.town_stock.duplicate(true), S.town_coin, S.external_coin, S.event_log.size()]
	S._logi_export()
	ck([S.town_stock, S.town_coin, S.external_coin, S.event_log.size()] == state0,
		"external=0 时零副作用")

	S.external_coin = 100
	state0 = [S.town_stock.duplicate(true), S.town_coin, S.external_coin, S.event_log.size()]
	S._export_commit(good, 1, node, 1, 2)
	ck([S.town_stock, S.town_coin, S.external_coin, S.event_log.size()] == state0,
		"revenue 整数地板为 0 时零副作用")

	for bad_flag in [false, 0, "true", null]:
		lane["scale_floor"] = bad_flag
		state0 = [S.town_stock.duplicate(true), S.town_coin, S.external_coin, S.event_log.size()]
		S._logi_export()
		ck([S.town_stock, S.town_coin, S.external_coin, S.event_log.size()] == state0,
			"N>12 scale_floor=%s 未 opt-in/fail-closed" % str(bad_flag))
	lane["scale_floor"] = true

	S.external_coin = 1
	var town0 := int(S.town_coin)
	var ev0: int = S.event_log.size()
	S._logi_export()
	var rel := trade_events(S.event_log.slice(ev0))
	var scan := Inv.export_pair_scan(rel)
	ck(int(scan["pairs"]) == 1 and int(S.town_stock[good]) == floor + batch - 2
		and int(S.town_coin) == town0 + 1 and int(S.external_coin) == 0,
		"external 只负担 2 件时部分 batch 仍 exact commit")
	dispose(S)

	# start_new 只扩不缩；直接把已加载的 pool ratio 置到低于 base，验证函数边界仍 fail-closed。
	var Low = fresh(12, 211)
	Low.prod_pool_num = 11
	var low_lane: Dictionary = Low.logistics.get("export_lanes", [])[0]
	var low_good := String(low_lane.get("good", ""))
	Low.day = int(low_lane.get("every_days", 0))
	Low.town_stock[low_good] = 999
	Low.external_coin = 100
	ev0 = Low.event_log.size()
	Low._logi_export()
	ck(trade_events(Low.event_log.slice(ev0)).is_empty(), "N<base 保持 fail-closed")
	dispose(Low)

	var Base = fresh(12, 212)
	var base_lane: Dictionary = Base.logistics.get("export_lanes", [])[0]
	var base_good := String(base_lane.get("good", ""))
	var base_floor := int(base_lane.get("floor", 0))
	var base_batch := int(base_lane.get("batch", 0))
	Base.day = int(base_lane.get("every_days", 0))
	for ignored_flag in [false, 0, "true", null]:
		base_lane["scale_floor"] = ignored_flag
		Base.town_stock[base_good] = base_floor + base_batch
		Base.external_coin = 100
		var base_town0 := int(Base.town_coin)
		ev0 = Base.event_log.size()
		Base._logi_export()
		var base_scan := Inv.export_pair_scan(Base.event_log.slice(ev0))
		ck(int(base_scan["pairs"]) == 1 and (base_scan["bad"] as Array).is_empty()
			and int(Base.town_stock[base_good]) == base_floor
			and int(Base.town_coin) == base_town0 + base_batch / 2 and int(Base.external_coin) == 100 - base_batch / 2,
			"N=12 ignores scale_floor=%s and preserves authored export" % str(ignored_flag))
	dispose(Base)

func scanner_teeth() -> void:
	var empty := Inv.export_pair_scan([])
	ck(int(empty["related"]) == 0 and int(empty["pairs"]) == 0 and (empty["bad"] as Array).is_empty(),
		"scanner 空输入真空但 provider=0")
	var orphan := Inv.export_pair_scan([{"id": 1, "type": "export", "note": "export*6"}])
	ck(int(orphan["related"]) == 1 and int(orphan["pairs"]) == 0 and not (orphan["bad"] as Array).is_empty(),
		"orphan stock provider 非零且判红")
	var paired := Inv.export_pair_scan([
		{"id": 2, "type": "pay", "note": "export*6"},
		{"id": 3, "type": "world", "note": "unrelated"},
		{"id": 4, "type": "export", "note": "export*6"},
	])
	ck(int(paired["related"]) == 2 and int(paired["pairs"]) == 1 and (paired["bad"] as Array).is_empty(),
		"filtered seq 忽略无关事件并配成一对")
	var mismatch := Inv.export_pair_scan([
		{"id": 5, "type": "pay", "note": "export*6"},
		{"id": 6, "type": "export", "note": "export*3"},
	])
	ck(int(mismatch["related"]) == 2 and int(mismatch["pairs"]) == 1 and not (mismatch["bad"] as Array).is_empty(),
		"qty mismatch 仍计 provider pair 且判红")

func _ready() -> void:
	scanner_teeth()
	boundary_cases()
	scale_case(15, 45, 44)
	scale_case(23, 69, 68)
	scale_case(59, 177, 173)
	if _fails == 0:
		print("P1-d scale export test: PASS")
	else:
		push_error("P1-d scale export test: FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
