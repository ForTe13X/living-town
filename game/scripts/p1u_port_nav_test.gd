extends Node
## P1-u East Ocean solid-prop authority gate: one authored footprint must drive draw, nav,
## save-location rejection, and both keyboard/A* reachability without sealing the warehouse door.
const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

const EXPECTED_PROPS := [
	{"id": "port_boathouse", "kind": "boathouse", "pos": [56, 7], "footprint": [1, 2]},
	{"id": "port_crate", "kind": "crate", "pos": [57, 7], "footprint": [1, 1]},
	{"id": "port_barrel", "kind": "barrel", "pos": [58, 7], "footprint": [1, 1]},
	{"id": "port_sacks", "kind": "sacks", "pos": [58, 8], "footprint": [1, 1]},
]
const EXPECTED_CELLS := [Vector2i(56, 7), Vector2i(56, 8), Vector2i(57, 7), Vector2i(58, 7), Vector2i(58, 8)]

var _fails := 0

func ck(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
	print(("  OK   " if ok else "  FAIL ") + msg)

func blocked(S, cell: Vector2i) -> bool:
	var w := int(S.world.get("width", 0))
	return S._blocked.has(cell.y * w + cell.x)

func prop_projection(raw_props) -> Array:
	var out: Array = []
	for raw_prop in raw_props:
		var prop: Dictionary = raw_prop
		var pos: Array = prop.get("pos", []); var footprint: Array = prop.get("footprint", [])
		out.append({"id": String(prop.get("id", "")), "kind": String(prop.get("kind", "")),
			"pos": [int(pos[0]), int(pos[1])], "footprint": [int(footprint[0]), int(footprint[1])]})
	return out

func mutate_save(source_path: String, target_path: String, arm: String) -> bool:
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null or source.get_length() < 8:
		return false
	var header := source.get_32(); var raw_blob = source.get_var(); source.close()
	if not (raw_blob is Dictionary) or not ((raw_blob as Dictionary).get("state") is Dictionary):
		return false
	var blob: Dictionary = (raw_blob as Dictionary).duplicate(true)
	var state: Dictionary = blob["state"]
	if arm == "player_inside_sacks":
		for raw_agent in state.get("agents", []):
			if raw_agent is Dictionary and String((raw_agent as Dictionary).get("id", "")) == "player":
				(raw_agent as Dictionary)["pos"] = Vector2i(58, 8)
				(raw_agent as Dictionary)["area"] = "dock"
				(raw_agent as Dictionary)["room"] = ""
	elif arm == "forged_prop_kind":
		var props: Array = state["world"]["areas"]["dock"]["solid_props"]
		(props[0] as Dictionary)["kind"] = "crate"
	else:
		return false
	var target := FileAccess.open(target_path, FileAccess.WRITE)
	if target == null:
		return false
	target.store_32(header); target.store_var(blob); target.close()
	return true

func guard_snapshot(S) -> Dictionary:
	var pl: Dictionary = S.get_agent("player")
	return {"digest": Inv.digest(S), "event_digest": S.event_digest, "tick": S.tick_no, "day": S.day,
		"world": S.world.duplicate(true), "path_cache": S._path_cache.duplicate(true),
		"player": {"space": pl.get("space"), "floor": pl.get("floor"), "pos": pl.get("pos"),
			"area": pl.get("area"), "room": pl.get("room")}}

func _ready() -> void:
	var S = SimScript.new()
	add_child(S)
	S.auto_run = false
	S.backend = null
	S.start_new(3)
	var dock: Dictionary = S.world.get("areas", {}).get("dock", {})
	ck(prop_projection(dock.get("solid_props", [])) == EXPECTED_PROPS, "East Ocean solid props authored exact-set/order/footprints")
	ck(S._solid_prop_cells_in_world(S.world) == EXPECTED_CELLS, "shared pure footprint projection is exact and ordered")
	for cell in EXPECTED_CELLS:
		ck(blocked(S, cell), "visible solid prop cell blocks runtime nav: %s" % str(cell))
	ck(not blocked(S, Vector2i(57, 8)) and not blocked(S, Vector2i(59, 7)),
		"warehouse door and dock interaction approach remain walkable")
	var props0: Array = dock.get("solid_props", []).duplicate(true)
	dock.erase("solid_props"); S._build_nav()
	ck(EXPECTED_CELLS.all(func(cell): return not blocked(S, cell)),
		"OFF arm removes only authored solid-prop collision")
	dock["solid_props"] = props0; S._build_nav()
	ck(EXPECTED_CELLS.all(func(cell): return blocked(S, cell)),
		"restoring authored records restores all five collision cells")
	var tao: Dictionary = S.get_agent("tao")
	ck(tao.get("home") == Vector2i(59, 7) and tao.get("pos") == Vector2i(59, 7),
		"Tao home/spawn migrates off the sacks onto the open dock approach")

	var pl: Dictionary = S.add_player(Vector2i(57, 8))
	for direction in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0)]:
		var before: Vector2i = pl.get("pos", Vector2i.ZERO)
		S.player_move(direction)
		ck(pl.get("pos") == before, "player movement cannot enter visible solid prop via %s" % str(direction))
	S.player_move(Vector2i(0, 1))
	ck(pl.get("pos") == Vector2i(57, 9), "warehouse door has a live southern approach")
	var town_grid: Dictionary = S._grid_for("town", "outdoor")
	var door_path: Array = S._astar_path(town_grid, Vector2i(57, 9), Vector2i(57, 8))
	var port_path: Array = S._astar_path(town_grid, Vector2i(59, 7), Vector2i(59, 8))
	ck(door_path == [Vector2i(57, 9), Vector2i(57, 8)], "A* reaches the warehouse portal exactly")
	ck(port_path == [Vector2i(59, 7), Vector2i(59, 8)], "A* keeps the port object as an adjacent interaction goal")

	var valid_save := "user://p1u_valid_port_nav.save"
	var corrupt_save := "user://p1u_corrupt_port_nav.save"
	ck(S.save_game(valid_save), "valid authored prop/nav state is writable")
	for arm in ["player_inside_sacks", "forged_prop_kind"]:
		ck(mutate_save(valid_save, corrupt_save, arm), "offline transformer creates %s negative" % arm)
		var Guard = SimScript.new(); add_child(Guard); Guard.auto_run = false; Guard.backend = null
		Guard.start_new(19); Guard.add_player(Vector2i(57, 8)); Guard._path_cache["player"] = {"goal": Vector2i(1, 1)}
		var before := guard_snapshot(Guard)
		ck(Guard.peek_save(corrupt_save).is_empty() and not Guard.load_game(corrupt_save)
			and guard_snapshot(Guard) == before,
			"%s save is hidden/rejected before receiver mutation" % arm)
		Guard.queue_free()
	for path in [valid_save, corrupt_save]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	print("p1u_port_nav_test: " + ("PASS ✅" if _fails == 0 else "FAIL ❌ (%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)
