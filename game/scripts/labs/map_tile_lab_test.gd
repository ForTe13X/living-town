extends Node

const ModelScript = preload("res://scripts/labs/MapTileLabModel.gd")

var _fails := 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	print("  %s %s%s" % [("PASS" if condition else "FAIL"), label, ("  " + detail if detail != "" else "")])
	if not condition:
		_fails += 1


func _ready() -> void:
	print("=== map tile lab model ===")
	var a = ModelScript.new(81426)
	var b = ModelScript.new(81426)
	var c = ModelScript.new(81427)
	_check("same seed has the same world receipt", a.world_signature() == b.world_signature())
	_check("a different seed changes the world receipt", a.world_signature() != c.world_signature())
	_check("fixed sites survive procedural terrain", String(a.tile_at(Vector2i(7, 2))["site"]) == "Ash Market")

	var destination := Vector2i(7, 2)
	_check("route can be planned", a.plan_route(destination), str(a.route))
	_check("route starts at the caravan", not a.route.is_empty() and a.route[0] == a.caravan_tile)
	_check("route ends at the selected tile", not a.route.is_empty() and a.route[-1] == destination)
	var continuous := true
	for i in range(1, a.route.size()):
		continuous = continuous and a.is_world_neighbor(a.route[i - 1], a.route[i])
	_check("every route leg is a real hex neighbor", continuous)
	var supply_before: float = float(a.supplies)
	_check("travel begins", a.begin_travel())
	for i in 200:
		a.tick_travel(0.25)
		if not a.traveling:
			break
	_check("travel arrives", a.caravan_tile == destination and not a.traveling, str(a.caravan_tile))
	_check("travel consumes supply monotonically", a.supplies < supply_before, "%.2f -> %.2f" % [supply_before, a.supplies])

	a.selected_tile = a.caravan_tile
	_check("arrived tile opens a local map", a.enter_local())
	_check("local receipt is deterministic", a.local_signature() == b_local_signature(81426, destination))
	_check("local map has four building shells", a.buildings.size() == 4)
	_check("local map has furnished loot and pressure", a.props.size() >= 20 and a.loot.size() >= 8 and a.threats.size() >= 3)
	_check("extraction starts on a walkable marker", a.cell_at(a.extraction) == ModelScript.Cell.EXIT and a.is_walkable(a.extraction))
	_check("extraction requires the exact striped cell", not a.can_extract())
	_check("every loot cell is reachable from extraction", _all_loot_reachable(a))

	# Collision: stand directly south of the store's west wall and attempt to enter through masonry.
	a.player = Vector2i(4, 11)
	var blocked_at: Vector2i = a.player
	_check("solid building wall blocks a step", not a.move_player(Vector2i(0, -1)) and a.player == blocked_at)

	# Cutaway: using the authored door then crossing the threshold reveals exactly that roof group.
	var first: Dictionary = a.buildings[0]
	var door: Vector2i = first["door"]
	a.player = door
	a.move_player(Vector2i(0, -1))
	_check("crossing a door reveals its building", bool(a.buildings[0]["revealed"]) and a.current_building == "ROADSIDE STORE")

	# Loot can be collected from an adjacent cell and remains in the caravan receipt after extraction.
	var item: Dictionary = a.loot[0]
	var item_pos: Vector2i = item["pos"]
	a.player = item_pos + Vector2i(0, 1)
	var value_before: int = int(a.cargo_value)
	_check("adjacent interaction collects a container", a.interact() and a.cargo_value > value_before)
	a.player = a.extraction
	var extracted_value: int = int(a.cargo_value)
	_check("extraction returns to world mode", a.extract_local() and a.mode == ModelScript.Mode.WORLD)
	_check("extracted value reaches the caravan stash", a.stash_value == extracted_value and extracted_value > 0)

	var stranded = ModelScript.new(81426)
	stranded.plan_route(Vector2i(7, 2))
	stranded.supplies = 0.1
	stranded.begin_travel()
	stranded.tick_travel(3.0)
	_check("supply exhaustion strands instead of reporting arrival",
		not stranded.traveling and stranded.caravan_tile != Vector2i(7, 2)
		and stranded.route.size() == 1 and "Stranded" in stranded.latest_message())

	var doomed = ModelScript.new(81426)
	doomed.caravan_tile = Vector2i(7, 2)
	doomed.selected_tile = doomed.caravan_tile
	doomed.plan_route(doomed.caravan_tile)
	doomed.enter_local()
	doomed.player = Vector2i(10, 13)
	doomed.threats = [{"pos": Vector2i(11, 13), "hp": 2, "alerted": true, "dead": false}]
	doomed.health = 7
	doomed.cargo_value = 99
	doomed._spend_turn()
	_check("zero health terminates the raid and loses carried value",
		doomed.health == 0 and doomed.mode == ModelScript.Mode.WORLD
		and doomed.cargo_value == 0 and doomed.stash_value == 0)

	print("map_tile_lab_test: %s (%d fail)" % [("PASS" if _fails == 0 else "FAIL"), _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func b_local_signature(p_seed: int, destination: Vector2i) -> String:
	var other = ModelScript.new(p_seed)
	other.caravan_tile = destination
	other.selected_tile = destination
	other.plan_route(destination)
	other.enter_local()
	return other.local_signature()


func _all_loot_reachable(lab) -> bool:
	var open: Array[Vector2i] = [lab.extraction]
	var seen := {lab.extraction: true}
	while not open.is_empty():
		var current: Vector2i = open.pop_front()
		for delta in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = current + delta
			if not seen.has(next) and lab.local_in_bounds(next) and lab.is_walkable(next):
				seen[next] = true
				open.append(next)
	for item: Dictionary in lab.loot:
		if not seen.has(item["pos"]):
			return false
	return true
