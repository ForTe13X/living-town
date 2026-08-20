class_name MapTileLabModel
extends RefCounted

## A deliberately isolated gameplay model for the map-tile experiment.
## It does not read or mutate Sim: the lab can be deleted, compared, or promoted
## without making the deterministic town history depend on a player's camera.

enum Mode { WORLD, LOCAL }
enum Cell { GROUND, ROAD, FLOOR, WALL, DOOR, WINDOW, RUBBLE, WATER, EXIT, TREE }

const WORLD_W := 11
const WORLD_H := 7
const LOCAL_W := 32
const LOCAL_H := 22

const BIOME_COST := {
	"pine": 1.15,
	"steppe": 1.0,
	"scrub": 1.25,
	"marsh": 1.8,
	"highland": 1.55,
	"ash": 1.35,
}

const WORLD_NAMES := [
	"Kestrel", "Morrow", "Sable", "Redglass", "Hollow", "Dunlin",
	"Saint Orra", "Bracken", "Pale Mile", "Gannet", "Black Reed",
]
const WORLD_SUFFIX := ["Reach", "Fen", "Waste", "Vale", "March", "Ridge", "Cut"]

var seed: int
var mode := Mode.WORLD
var world_tiles: Array = []
var caravan_tile := Vector2i(2, 4)
var selected_tile := Vector2i(7, 2)
var route: Array[Vector2i] = []
var route_step := 0
var travel_progress := 0.0
var traveling := false
var supplies := 18.0
var condition := 92.0
var morale := 74.0
var world_day := 12
var world_hour := 8.0
var stash_value := 0

var local_cells := PackedInt32Array()
var buildings: Array = []
var props: Array = []
var loot: Array = []
var threats: Array = []
var player := Vector2i.ZERO
var extraction := Vector2i.ZERO
var local_turns := 0
var health := 100
var noise := 0
var cargo_weight := 0.0
var cargo_value := 0
var inventory := {"scrap": 0, "meds": 0, "food": 0, "parts": 0}
var site_title := ""
var current_building := "OUTDOORS"
var local_start_minutes := 8 * 60
var messages: Array[String] = []


func _init(p_seed: int = 260814) -> void:
	reset(p_seed)


func reset(p_seed: int) -> void:
	seed = p_seed
	mode = Mode.WORLD
	world_tiles.clear()
	caravan_tile = Vector2i(2, 4)
	selected_tile = Vector2i(7, 2)
	route.clear()
	route_step = 0
	travel_progress = 0.0
	traveling = false
	supplies = 18.0
	condition = 92.0
	morale = 74.0
	world_day = 12
	world_hour = 8.0
	stash_value = 0
	_generate_world()
	plan_route(selected_tile)
	messages = ["Route table unfolded. Ash Market is marked in red pencil."]


func _hash2(x: int, y: int, salt: int = 0) -> int:
	var n := (x * 73856093) ^ (y * 19349663) ^ (seed * 83492791) ^ (salt * 265443576)
	n = (n ^ (n >> 13)) * 1274126177
	return (n ^ (n >> 16)) & 0x7fffffff


func noise01(x: int, y: int, salt: int = 0) -> float:
	return float(_hash2(x, y, salt) % 10000) / 9999.0


func _generate_world() -> void:
	for y in WORLD_H:
		for x in WORLD_W:
			var elevation := noise01(x, y, 3) * 0.68 + noise01(x / 2, y / 2, 11) * 0.32
			var moisture := noise01(x, y, 7) * 0.62 + noise01(x / 3, y / 2, 19) * 0.38
			var biome := "steppe"
			if elevation > 0.76:
				biome = "highland"
			elif moisture > 0.72:
				biome = "marsh"
			elif moisture > 0.52:
				biome = "pine"
			elif elevation < 0.28:
				biome = "ash"
			elif moisture < 0.32:
				biome = "scrub"
			var road := (y == 4 and x >= 1 and x <= 9) or (x == 5 and y >= 1 and y <= 5)
			var discovered := world_distance(caravan_tile, Vector2i(x, y)) <= 3 or road
			var name_i := _hash2(x, y, 23) % WORLD_NAMES.size()
			var suffix_i := _hash2(x, y, 29) % WORLD_SUFFIX.size()
			world_tiles.append({
				"pos": Vector2i(x, y),
				"biome": biome,
				"risk": 1 + _hash2(x, y, 31) % 5,
				"forage": 1 + _hash2(x, y, 37) % 4,
				"road": road,
				"discovered": discovered,
				"site": "",
				"site_kind": "",
				"name": "%s %s" % [WORLD_NAMES[name_i], WORLD_SUFFIX[suffix_i]],
			})

	_set_site(Vector2i(2, 4), "Cinder Crossing", "haven")
	_set_site(Vector2i(7, 2), "Ash Market", "ruins")
	_set_site(Vector2i(5, 1), "Orra Relay", "tower")
	_set_site(Vector2i(5, 5), "Saint Vey Clinic", "clinic")
	_set_site(Vector2i(9, 4), "Redglass Quarry", "quarry")
	_set_site(Vector2i(1, 1), "Dunlin Homestead", "farm")


func _set_site(pos: Vector2i, label: String, kind: String) -> void:
	var tile := tile_at(pos)
	if tile.is_empty():
		return
	tile["site"] = label
	tile["site_kind"] = kind
	tile["road"] = true
	tile["discovered"] = true


func tile_at(pos: Vector2i) -> Dictionary:
	if not world_in_bounds(pos):
		return {}
	return world_tiles[pos.y * WORLD_W + pos.x]


func world_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < WORLD_W and pos.y < WORLD_H


func world_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var even := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
	var odd := [Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0)]
	var result: Array[Vector2i] = []
	var dirs: Array = even if pos.x % 2 == 0 else odd
	for delta: Vector2i in dirs:
		var n := pos + delta
		if world_in_bounds(n):
			result.append(n)
	return result


func is_world_neighbor(a: Vector2i, b: Vector2i) -> bool:
	return b in world_neighbors(a)


func _axial(pos: Vector2i) -> Vector2i:
	return Vector2i(pos.x, pos.y - (pos.x - (pos.x & 1)) / 2)


func world_distance(a: Vector2i, b: Vector2i) -> int:
	var aa := _axial(a)
	var bb := _axial(b)
	var dq := aa.x - bb.x
	var dr := aa.y - bb.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


func _world_step_cost(pos: Vector2i) -> float:
	var tile := tile_at(pos)
	var cost := float(BIOME_COST.get(String(tile.get("biome", "steppe")), 1.0))
	if bool(tile.get("road", false)):
		cost *= 0.68
	cost += float(int(tile.get("risk", 1)) - 1) * 0.035
	return cost


func plan_route(destination: Vector2i) -> bool:
	if traveling or not world_in_bounds(destination):
		return false
	selected_tile = destination
	var open: Array[Vector2i] = [caravan_tile]
	var came := {}
	var score := {caravan_tile: 0.0}
	var estimate := {caravan_tile: float(world_distance(caravan_tile, destination))}
	while not open.is_empty():
		var best_i := 0
		for i in range(1, open.size()):
			if float(estimate.get(open[i], INF)) < float(estimate.get(open[best_i], INF)):
				best_i = i
		var current: Vector2i = open.pop_at(best_i)
		if current == destination:
			route.clear()
			var cursor: Vector2i = current
			route.push_front(cursor)
			while came.has(cursor):
				cursor = came[cursor]
				route.push_front(cursor)
			route_step = 0
			travel_progress = 0.0
			return true
		for n in world_neighbors(current):
			var tentative := float(score.get(current, INF)) + _world_step_cost(n)
			if tentative < float(score.get(n, INF)):
				came[n] = current
				score[n] = tentative
				# The cheapest legal road leg is below 1.0, so raw hex distance would
				# overestimate and could make A* settle a merely-good route. 0.64 stays
				# below every BIOME_COST * road multiplier in this table.
				estimate[n] = tentative + float(world_distance(n, destination)) * 0.64
				if n not in open:
					open.append(n)
	route.clear()
	return false


func route_cost() -> float:
	var total := 0.0
	var first_leg := route_step + 1 if traveling else 1
	for i in range(first_leg, route.size()):
		total += _world_step_cost(route[i])
	return total


func begin_travel() -> bool:
	if mode != Mode.WORLD or route.size() < 2 or supplies <= 0.0:
		return false
	traveling = true
	_note("The caravan leaves %s." % String(tile_at(caravan_tile).get("site", tile_at(caravan_tile).get("name", "camp"))))
	return true


func tick_travel(delta: float) -> bool:
	if not traveling:
		return false
	travel_progress += delta * 0.48
	var changed := true
	while travel_progress >= 1.0 and traveling:
		travel_progress -= 1.0
		route_step += 1
		caravan_tile = route[route_step]
		var step_cost := _world_step_cost(caravan_tile)
		supplies = maxf(0.0, supplies - step_cost * 0.72)
		condition = maxf(0.0, condition - float(int(tile_at(caravan_tile).get("risk", 1))) * 0.18)
		_advance_world_hours(step_cost * 2.2)
		_discover_around(caravan_tile)
		if route_step >= route.size() - 1:
			traveling = false
			travel_progress = 0.0
			var arrived_name := display_name(tile_at(caravan_tile))
			_anchor_route_here()
			_note("Reached %s. The engine ticks itself cool." % arrived_name)
		elif supplies <= 0.0:
			traveling = false
			travel_progress = 0.0
			morale = maxf(0.0, morale - 8.0)
			_anchor_route_here()
			_note("Stranded without supply. Search this tile or turn back with help.")
	return changed


func _anchor_route_here() -> void:
	selected_tile = caravan_tile
	route.clear()
	route.append(caravan_tile)
	route_step = 0


func _discover_around(center: Vector2i) -> void:
	for tile: Dictionary in world_tiles:
		if world_distance(center, tile["pos"]) <= 1:
			tile["discovered"] = true


func display_name(tile: Dictionary) -> String:
	var site := String(tile.get("site", ""))
	return site if site != "" else String(tile.get("name", "Unknown tile"))


func enter_local() -> bool:
	if mode != Mode.WORLD or traveling or selected_tile != caravan_tile:
		return false
	_generate_local(caravan_tile)
	mode = Mode.LOCAL
	_note("Boots down. Mark the exit before entering a building.")
	return true


func _generate_local(world_pos: Vector2i) -> void:
	local_cells.resize(LOCAL_W * LOCAL_H)
	for i in local_cells.size():
		local_cells[i] = Cell.GROUND
	buildings.clear()
	props.clear()
	loot.clear()
	threats.clear()
	local_turns = 0
	health = 100
	noise = 0
	cargo_weight = 0.0
	cargo_value = 0
	inventory = {"scrap": 0, "meds": 0, "food": 0, "parts": 0}
	player = Vector2i(1, 13)
	extraction = Vector2i(0, 13)
	current_building = "OUTDOORS"
	local_start_minutes = int(world_hour * 60.0)
	var tile := tile_at(world_pos)
	site_title = display_name(tile).to_upper()

	# A T-junction keeps every facade legible and gives the caravan a clear extraction lane.
	for x in LOCAL_W:
		set_cell(Vector2i(x, 13), Cell.ROAD)
	for y in range(8, LOCAL_H):
		for x in range(15, 18):
			set_cell(Vector2i(x, y), Cell.ROAD)
	set_cell(extraction, Cell.EXIT)

	_stamp_building(Rect2i(4, 2, 11, 9), "ROADSIDE STORE", "store", "south")
	_stamp_building(Rect2i(19, 2, 11, 10), "FIELD CLINIC", "clinic", "south")
	_stamp_building(Rect2i(3, 15, 11, 6), "LOCKSMITH", "workshop", "north")
	_stamp_building(Rect2i(18, 15, 12, 6), "TENEMENT", "home", "north")
	props = [
		_prop(Vector2i(5, 4), "shelf", "dry goods"),
		_prop(Vector2i(5, 7), "shelf", "dry goods"),
		_prop(Vector2i(8, 8), "counter", "till counter"),
		_prop(Vector2i(13, 4), "shelf", "bottles"),
		_prop(Vector2i(13, 9), "counter", "service counter"),
		_prop(Vector2i(20, 3), "bed", "exam cot"),
		_prop(Vector2i(20, 8), "bed", "exam cot"),
		_prop(Vector2i(23, 9), "cabinet", "medical cabinet"),
		_prop(Vector2i(28, 4), "cabinet", "medical cabinet"),
		_prop(Vector2i(28, 9), "desk", "intake desk"),
		_prop(Vector2i(4, 17), "anvil", "anvil"),
		_prop(Vector2i(4, 19), "workbench", "workbench"),
		_prop(Vector2i(7, 19), "crate", "parts crate"),
		_prop(Vector2i(10, 19), "workbench", "vice bench"),
		_prop(Vector2i(12, 16), "crate", "parts crate"),
		_prop(Vector2i(19, 16), "bed", "cot"),
		_prop(Vector2i(23, 19), "stove", "iron stove"),
		_prop(Vector2i(20, 19), "table", "kitchen table"),
		_prop(Vector2i(28, 16), "wardrobe", "wardrobe"),
		_prop(Vector2i(28, 19), "bed", "cot"),
		_prop(Vector2i(25, 19), "table", "side table"),
	]

	# Exterior clutter is deterministic and never allowed to seal the road or a doorway.
	for y in LOCAL_H:
		for x in LOCAL_W:
			var pos := Vector2i(x, y)
			if cell_at(pos) != Cell.GROUND:
				continue
			var roll := _hash2(x + world_pos.x * 41, y + world_pos.y * 53, 101) % 100
			if roll < 7:
				set_cell(pos, Cell.TREE)
			elif roll < 13:
				set_cell(pos, Cell.RUBBLE)

	loot = [
		_loot(Vector2i(7, 5), "food", "sealed rations", 18, 1.2, 2),
		_loot(Vector2i(12, 7), "scrap", "cashbox scrap", 24, 2.0, 3),
		_loot(Vector2i(22, 5), "meds", "trauma pouch", 42, 0.8, 2),
		_loot(Vector2i(27, 8), "meds", "antiseptic", 28, 0.6, 1),
		_loot(Vector2i(6, 18), "parts", "machined parts", 36, 2.4, 4),
		_loot(Vector2i(11, 17), "scrap", "copper coil", 31, 1.7, 3),
		_loot(Vector2i(21, 18), "food", "cellar preserves", 20, 1.4, 2),
		_loot(Vector2i(27, 17), "parts", "radio valves", 55, 1.1, 4),
	]
	threats = [
		{"pos": Vector2i(16, 9), "hp": 2, "alerted": false, "dead": false},
		{"pos": Vector2i(30, 13), "hp": 2, "alerted": false, "dead": false},
		{"pos": Vector2i(16, 19), "hp": 2, "alerted": false, "dead": false},
	]
	_reveal_current_building()


func _stamp_building(rect: Rect2i, label: String, kind: String, entrance_side: String) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var edge := x == rect.position.x or y == rect.position.y or x == rect.end.x - 1 or y == rect.end.y - 1
			set_cell(Vector2i(x, y), Cell.WALL if edge else Cell.FLOOR)
	# Keep the street door off the center divider. A centered outer door followed
	# immediately by a center-wall cell looks valid from the roof, but is a sealed
	# threshold in the navigation graph.
	var door_x := rect.position.x + int(rect.size.x / 2) - 2
	var door := Vector2i(door_x, rect.end.y - 1)
	if entrance_side == "north":
		door.y = rect.position.y
	set_cell(door, Cell.DOOR)
	# Street-facing windows and one inner partition create readable Zomboid-like shells.
	var front_y := rect.end.y - 1 if entrance_side == "south" else rect.position.y
	set_cell(Vector2i(rect.position.x + 2, front_y), Cell.WINDOW)
	set_cell(Vector2i(rect.end.x - 3, front_y), Cell.WINDOW)
	if rect.size.x >= 11:
		var divider_x := rect.position.x + rect.size.x / 2
		for y in range(rect.position.y + 1, rect.end.y - 1):
			set_cell(Vector2i(divider_x, y), Cell.WALL)
		set_cell(Vector2i(divider_x, rect.position.y + 2), Cell.DOOR)
	buildings.append({
		"rect": rect,
		"label": label,
		"kind": kind,
		"door": door,
		"revealed": false,
		"roof_tone": _hash2(rect.position.x, rect.position.y, 131) % 3,
	})


func _loot(pos: Vector2i, kind: String, label: String, value: int, weight: float, loudness: int) -> Dictionary:
	return {"pos": pos, "kind": kind, "label": label, "value": value, "weight": weight, "noise": loudness, "taken": false}


func _prop(pos: Vector2i, kind: String, label: String, blocking: bool = true) -> Dictionary:
	return {"pos": pos, "kind": kind, "label": label, "blocking": blocking}


func local_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < LOCAL_W and pos.y < LOCAL_H


func cell_at(pos: Vector2i) -> int:
	if not local_in_bounds(pos) or local_cells.is_empty():
		return Cell.WALL
	return local_cells[pos.y * LOCAL_W + pos.x]


func set_cell(pos: Vector2i, value: int) -> void:
	if local_in_bounds(pos):
		local_cells[pos.y * LOCAL_W + pos.x] = value


func is_walkable(pos: Vector2i) -> bool:
	if cell_at(pos) in [Cell.WALL, Cell.WINDOW, Cell.TREE, Cell.WATER]:
		return false
	for prop: Dictionary in props:
		if bool(prop.get("blocking", true)) and prop["pos"] == pos:
			return false
	if _threat_at(pos):
		return false
	return true


func move_player(delta: Vector2i) -> bool:
	if mode != Mode.LOCAL or health <= 0:
		return false
	var target := player + delta
	if not is_walkable(target):
		_note("Blocked. Find a door or another street angle.")
		return false
	player = target
	_spend_turn(1)
	if mode == Mode.LOCAL:
		_reveal_current_building()
	return true


func _spend_turn(loudness: int = 0) -> void:
	local_turns += 1
	noise = clampi(noise - 1 + loudness, 0, 10)
	_advance_threats()


func _advance_threats() -> void:
	for i in threats.size():
		var threat: Dictionary = threats[i]
		if bool(threat.get("dead", false)):
			continue
		var pos: Vector2i = threat["pos"]
		var distance := absi(pos.x - player.x) + absi(pos.y - player.y)
		if distance <= 4 + noise:
			threat["alerted"] = true
		if bool(threat.get("alerted", false)) and local_turns % 2 == 0:
			var dx := signi(player.x - pos.x)
			var dy := signi(player.y - pos.y)
			var choices: Array[Vector2i] = []
			if absi(player.x - pos.x) >= absi(player.y - pos.y):
				choices = [Vector2i(dx, 0), Vector2i(0, dy)]
			else:
				choices = [Vector2i(0, dy), Vector2i(dx, 0)]
			for step in choices:
				var next := pos + step
				if next == player:
					break
				if is_walkable(next) and not _threat_at(next):
					pos = next
					threat["pos"] = pos
					break
		distance = absi(pos.x - player.x) + absi(pos.y - player.y)
		if distance <= 1 and bool(threat.get("alerted", false)):
			health = maxi(0, health - 7)
			_note("Contact at arm's length. Health -7.")
			if health <= 0:
				threats[i] = threat
				_collapse_local()
				return
		threats[i] = threat


func _threat_at(pos: Vector2i) -> bool:
	for threat: Dictionary in threats:
		if not bool(threat.get("dead", false)) and threat["pos"] == pos:
			return true
	return false


func attack() -> bool:
	if mode != Mode.LOCAL or health <= 0:
		return false
	for i in threats.size():
		var threat: Dictionary = threats[i]
		if bool(threat.get("dead", false)):
			continue
		var pos: Vector2i = threat["pos"]
		if absi(pos.x - player.x) + absi(pos.y - player.y) <= 1:
			threat["hp"] = int(threat["hp"]) - 1
			threat["alerted"] = true
			if int(threat["hp"]) <= 0:
				threat["dead"] = true
				inventory["scrap"] = int(inventory["scrap"]) + 1
				cargo_value += 8
				cargo_weight += 0.4
				_note("Threat down. A usable trinket goes into the pack.")
			else:
				_note("The hit lands, but the contact keeps moving.")
			threats[i] = threat
			_spend_turn(4)
			return true
	_note("No target in the four adjacent cells.")
	return false


func interact() -> bool:
	if mode != Mode.LOCAL or health <= 0:
		return false
	for i in loot.size():
		var item: Dictionary = loot[i]
		if bool(item.get("taken", false)):
			continue
		var pos: Vector2i = item["pos"]
		if absi(pos.x - player.x) + absi(pos.y - player.y) <= 1:
			item["taken"] = true
			loot[i] = item
			var kind := String(item["kind"])
			inventory[kind] = int(inventory.get(kind, 0)) + 1
			cargo_value += int(item["value"])
			cargo_weight += float(item["weight"])
			_note("Packed %s. Value +%d." % [String(item["label"]), int(item["value"])])
			_spend_turn(int(item["noise"]))
			return true
	if can_extract():
		return extract_local()
	_note("Nothing within reach. Containers glint with a pale corner mark.")
	return false


func _reveal_current_building() -> void:
	current_building = "OUTDOORS"
	for i in buildings.size():
		var building: Dictionary = buildings[i]
		var inner: Rect2i = (building["rect"] as Rect2i).grow(-1)
		if inner.has_point(player):
			current_building = String(building["label"])
			if not bool(building["revealed"]):
				building["revealed"] = true
				buildings[i] = building
				_note("Roofline drops away: %s." % current_building)
			return


func can_extract() -> bool:
	return mode == Mode.LOCAL and health > 0 and player == extraction


func extract_local() -> bool:
	if not can_extract():
		_note("Extraction is the striped tile on the west edge.")
		return false
	stash_value += cargo_value
	supplies = minf(24.0, supplies + float(int(inventory.get("food", 0))) * 1.5)
	_advance_world_hours(float(local_turns) * 0.1)
	mode = Mode.WORLD
	traveling = false
	plan_route(caravan_tile)
	_note("Extracted with %d value at %.1f kg. Caravan stash: %d." % [cargo_value, cargo_weight, stash_value])
	return true


func _collapse_local() -> void:
	var lost_value := cargo_value
	cargo_value = 0
	cargo_weight = 0.0
	inventory = {"scrap": 0, "meds": 0, "food": 0, "parts": 0}
	condition = maxf(0.0, condition - 12.0)
	morale = maxf(0.0, morale - 18.0)
	_advance_world_hours(6.0)
	mode = Mode.WORLD
	traveling = false
	_anchor_route_here()
	_note("Raid lost. The crew recovers the scout after dark; %d value is gone." % lost_value)


func local_clock() -> String:
	var minutes := local_start_minutes + local_turns * 6
	return "%02d:%02d" % [(minutes / 60) % 24, minutes % 60]


func _advance_world_hours(hours: float) -> void:
	world_hour += hours
	while world_hour >= 24.0:
		world_hour -= 24.0
		world_day += 1


func world_clock() -> String:
	return "DAY %02d  %02d:%02d" % [world_day, int(world_hour), int(fmod(world_hour, 1.0) * 60.0)]


func _note(text: String) -> void:
	messages.append(text)
	while messages.size() > 8:
		messages.pop_front()


func latest_message() -> String:
	return messages[-1] if not messages.is_empty() else ""


func world_signature() -> String:
	var rows: Array[String] = []
	for tile: Dictionary in world_tiles:
		rows.append("%s:%d:%s" % [String(tile["biome"]), int(tile["risk"]), String(tile["site_kind"])])
	return "|".join(rows)


func local_signature() -> String:
	var cells: Array[String] = []
	for value in local_cells:
		cells.append(str(value))
	var prop_receipt: Array[String] = []
	for prop: Dictionary in props:
		prop_receipt.append("%s@%s" % [String(prop["kind"]), str(prop["pos"])])
	return ",".join(cells) + "#" + site_title + "#" + "|".join(prop_receipt)
