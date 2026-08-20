extends Node2D

const SiteBlueprintModel = preload("res://scripts/labs/resource_pool/SiteBlueprintModel.gd")
const RegionRouteModel = preload("res://scripts/labs/resource_pool/RegionRouteModel.gd")

const DESIGN := Vector2(1280.0, 768.0)
const MAP_PANEL := Rect2(24.0, 92.0, 860.0, 590.0)
const SIDE_PANEL := Rect2(900.0, 92.0, 356.0, 590.0)
const GRID_RECT := Rect2(70.0, 137.0, 768.0, 528.0)
const CELL_SIZE := 24.0

const C_BG := Color("#11140f")
const C_HEADER := Color("#171a14")
const C_PANEL := Color("#1c1e19")
const C_PANEL_2 := Color("#24251f")
const C_CARD := Color("#181a16")
const C_CARD_HI := Color("#22241e")
const C_EDGE := Color("#565846")
const C_EDGE_HI := Color("#89866d")
const C_TEXT := Color("#ded8c4")
const C_MUTED := Color("#929382")
const C_GOLD := Color("#d2a85c")
const C_TEAL := Color("#78a999")
const C_GOOD := Color("#8fb56d")
const C_DANGER := Color("#c45b50")
const C_DIRT := Color("#35372d")
const C_ROAD := Color("#756549")
const C_FLOOR := Color("#59564a")
const C_WALL := Color("#33342d")
const C_WINDOW := Color("#6a9991")
const C_TREE := Color("#496348")
const C_RUBBLE := Color("#6d6558")
const C_WATER := Color("#355b5b")
const C_FENCE := Color("#77735e")
const C_CROP := Color("#687341")
const C_PIT := Color("#292521")

const FIXTURE_SITE_KEYS := [
	"ash_market",
	"saint_vey_clinic",
	"orra_relay",
	"redglass_quarry",
	"dunlin_homestead",
	"cinder_crossing",
]
const FIXTURE_KINDS := ["ruins", "clinic", "relay", "quarry", "farm", "haven"]
const FIXTURE_LABELS := [
	"A  RUINS", "B  CLINIC", "C  RELAY", "D  QUARRY", "E  FARM", "F  HAVEN",
]

const KIND_TITLES := {
	"ruins": "RUINED MARKET BLOCK",
	"clinic": "FIELD CLINIC CAMPUS",
	"relay": "ORRA RELAY COMPOUND",
	"quarry": "REDGLASS QUARRY WORKS",
	"farm": "DUNLIN HOMESTEAD",
	"haven": "CROSSING HAVEN",
}

const DECISION_COPY := {
	"ruins": {
		"promise": "Four salvage fronts around a fast central split.",
		"read": "Pick one storefront before road crossfire closes the exit.",
		"haul": "MIXED FOOD / MEDS / PARTS",
	},
	"clinic": {
		"promise": "Medicine is rich, but split between two exposed wings.",
		"read": "Commit to treatment or pharmacy; the cross-road punishes greed.",
		"haul": "HIGH-VALUE MEDICAL STOCK",
	},
	"relay": {
		"promise": "A fenced choke protects control, generator, and watch bunk.",
		"read": "The gate is safe to read and dangerous to overstay.",
		"haul": "SIGNAL PARTS / POWER PARTS",
	},
	"quarry": {
		"promise": "Dense machine parts sit beside a pit that deletes fallback lanes.",
		"read": "Clear the road first; water and quarry walls trap a deep sweep.",
		"haul": "HEAVY PARTS / REDGLASS SCRAP",
	},
	"farm": {
		"promise": "Food is dispersed across house, barn, cellar, and field.",
		"read": "Choose a short pantry raid or a longer yard circuit.",
		"haul": "BULK FOOD / FARM PARTS",
	},
	"haven": {
		"promise": "Low-pressure resupply is spread across four safe-stop buildings.",
		"read": "The threat is light; travel distance is the real cost.",
		"haul": "FOOD / TRAVEL MEDS / WAGON PARTS",
	},
}

const SCAR_PROFILES := {
	"ruins": {"loot": 3, "threats": 2, "buildings": 2, "props": 2, "resolution": "extracted", "turns": 19},
	"clinic": {"loot": 4, "threats": 1, "buildings": 3, "props": 1, "resolution": "extracted", "turns": 24},
	"relay": {"loot": 2, "threats": 2, "buildings": 2, "props": 1, "resolution": "retreated", "turns": 17},
	"quarry": {"loot": 3, "threats": 2, "buildings": 2, "props": 1, "resolution": "retreated", "turns": 28},
	"farm": {"loot": 3, "threats": 1, "buildings": 2, "props": 1, "resolution": "extracted", "turns": 16},
	# Haven is the explicit empty-hand terminal fixture: the visit commits roof intel,
	# but no loot, threat, or prop outcome is claimed.
	"haven": {"loot": 0, "threats": 0, "buildings": 1, "props": 0, "resolution": "retreated", "turns": 7},
}

var _font: Font
var _atlas: Dictionary = {}
var _atlas_state: Dictionary = {}
var _promise: Dictionary = {}
var _blueprint: Dictionary = {}
var _fresh_state: Dictionary = {}
var _scarred_state: Dictionary = {}
var _active_state: Dictionary = {}
var _arrival_plan: Dictionary = {}
var _arrival_journey: Dictionary = {}
var _arrival_receipt: Dictionary = {}
var _enter_transition: Dictionary = {}
var _visit_delta: Dictionary = {}
var _scar_transition: Dictionary = {}
var _fixture_index := 0
var _show_scarred := false
var _shot_path := ""
var _load_ok := false
var _mouse := Vector2(-1000.0, -1000.0)
var _fixture_rects: Array[Rect2] = []
var _state_rect := Rect2()


func _ready() -> void:
	_font = ThemeDB.fallback_font
	var requested_fixture := 0
	var requested_scarred := false
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		var argument := String(args[index])
		if argument == "--site-fixture" and index + 1 < args.size():
			index += 1
			requested_fixture = _fixture_from_argument(String(args[index]))
		elif argument.begins_with("--site-fixture="):
			requested_fixture = _fixture_from_argument(argument.trim_prefix("--site-fixture="))
		elif argument == "--site-state" and index + 1 < args.size():
			index += 1
			requested_scarred = _state_from_argument(String(args[index]))
		elif argument.begins_with("--site-state="):
			requested_scarred = _state_from_argument(argument.trim_prefix("--site-state="))
		elif argument == "--lab-shot" and index + 1 < args.size():
			index += 1
			_shot_path = String(args[index])
		elif argument.begins_with("--lab-shot="):
			_shot_path = argument.trim_prefix("--lab-shot=")
		index += 1
	_load_ok = _apply_fixture(requested_fixture, requested_scarred)
	set_process(true)
	queue_redraw()
	if _shot_path != "":
		if not _load_ok:
			get_tree().quit(1)
			return
		get_tree().create_timer(0.8).timeout.connect(_save_shot)


func _process(_delta: float) -> void:
	if _shot_path != "":
		return
	queue_redraw()


func _fixture_from_argument(value: String) -> int:
	match value.strip_edges().to_lower():
		"a", "1", "ruins", "ash_market", "ash-market":
			return 0
		"b", "2", "clinic", "saint_vey_clinic", "saint-vey-clinic":
			return 1
		"c", "3", "relay", "orra_relay", "orra-relay":
			return 2
		"d", "4", "quarry", "redglass_quarry", "redglass-quarry":
			return 3
		"e", "5", "farm", "dunlin_homestead", "dunlin-homestead":
			return 4
		"f", "6", "haven", "cinder_crossing", "cinder-crossing":
			return 5
	return 0


func _state_from_argument(value: String) -> bool:
	return value.strip_edges().to_lower() in ["scarred", "visited", "after", "1", "true"]


func _apply_fixture(index: int, scarred: bool = false) -> bool:
	_fixture_index = clampi(index, 0, FIXTURE_SITE_KEYS.size() - 1)
	_show_scarred = scarred
	_atlas = RegionRouteModel.make_atlas(RegionRouteModel.DEFAULT_ROOT_SEED)
	_atlas_state = RegionRouteModel.make_initial_atlas_state(_atlas)
	_promise = SiteBlueprintModel.make_site_promise(_atlas, String(FIXTURE_SITE_KEYS[_fixture_index]))
	_blueprint = SiteBlueprintModel.compile_site(_promise)
	_fresh_state = SiteBlueprintModel.make_initial_state(_promise, _blueprint)
	if _atlas.is_empty() or _atlas_state.is_empty() or _promise.is_empty() \
			or _blueprint.is_empty() or _fresh_state.is_empty():
		push_error("SiteCompilerLab could not compile fixture %s" % String(FIXTURE_LABELS[_fixture_index]))
		return false
	if not SiteBlueprintModel.validate_blueprint(_promise, _blueprint).is_empty() \
			or not SiteBlueprintModel.validate_state_snapshot(_promise, _blueprint, _fresh_state).is_empty():
		push_error("SiteCompilerLab fixture failed blueprint or initial-state validation")
		return false
	if not _build_real_scar_transition():
		return false
	_active_state = _scarred_state if _show_scarred else _fresh_state
	queue_redraw()
	return true


func _build_real_scar_transition() -> bool:
	var tile_id := RegionRouteModel.site_tile_id(_atlas, String(FIXTURE_SITE_KEYS[_fixture_index]))
	_arrival_plan = RegionRouteModel.make_route_plan(
		_atlas, _atlas_state, tile_id, tile_id, "autumn", "safe", [], "", "site_lab_arrival"
	)
	_arrival_journey = RegionRouteModel.begin_journey(
		_atlas, _atlas_state, _arrival_plan, "site_lab_slot", 8500, 92000
	)
	_arrival_receipt = RegionRouteModel.route_receipt(
		_atlas, _atlas_state, _arrival_plan, _arrival_journey
	)
	_enter_transition = SiteBlueprintModel.enter_site(
		_promise, _blueprint, _fresh_state, String(_fresh_state.get("state_receipt", "")),
		_atlas, _atlas_state, _arrival_plan,
		_arrival_journey, _arrival_receipt,
		String(_arrival_journey.get("state_receipt", "")), "site_lab_visit"
	)
	if _arrival_plan.is_empty() or _arrival_journey.is_empty() or _arrival_receipt.is_empty() \
			or _enter_transition.is_empty():
		push_error("SiteCompilerLab could not produce arrived admission evidence")
		return false
	var active_state: Dictionary = _enter_transition.get("after_state", {}) as Dictionary
	var kind := String(_blueprint.get("site_kind", ""))
	var profile: Dictionary = SCAR_PROFILES.get(kind, {}) as Dictionary
	var depleted := _first_entity_ids(_blueprint.get("loot", []) as Array, int(profile.get("loot", 0)))
	var cleared := _first_entity_ids(_blueprint.get("threats", []) as Array, int(profile.get("threats", 0)))
	var revealed := _first_entity_ids(_blueprint.get("buildings", []) as Array, int(profile.get("buildings", 0)))
	var destructible: Array = []
	for raw_prop in _blueprint.get("props", []) as Array:
		var prop: Dictionary = raw_prop as Dictionary
		if bool(prop.get("destructible", false)):
			destructible.append(prop)
	var destroyed := _first_entity_ids(destructible, int(profile.get("props", 0)))
	_visit_delta = SiteBlueprintModel.make_visit_delta(
		_promise, _blueprint, active_state, _enter_transition,
		String(_fresh_state.get("state_receipt", "")), _atlas, _atlas_state,
		_arrival_plan, _arrival_journey, _arrival_receipt,
		String(_arrival_journey.get("state_receipt", "")), "site_lab_visit",
		String(profile.get("resolution", "retreated")), int(profile.get("turns", 1)),
		depleted, cleared, revealed, destroyed
	)
	_scar_transition = SiteBlueprintModel.apply_visit_delta(
		_promise, _blueprint, active_state, _enter_transition,
		String(_fresh_state.get("state_receipt", "")), _atlas, _atlas_state,
		_arrival_plan, _arrival_journey, _arrival_receipt,
		String(_arrival_journey.get("state_receipt", "")), _visit_delta
	)
	_scarred_state = _scar_transition.get("after_state", {}) as Dictionary
	if _visit_delta.is_empty() or _scar_transition.is_empty() or _scarred_state.is_empty():
		push_error("SiteCompilerLab could not settle its active visit into scarred idle state")
		return false
	if not SiteBlueprintModel.validate_enter_transition(
		_promise, _blueprint, _fresh_state, String(_fresh_state.get("state_receipt", "")),
		_atlas, _atlas_state, _arrival_plan,
		_arrival_journey, _arrival_receipt,
		String(_arrival_journey.get("state_receipt", "")), "site_lab_visit", _enter_transition
	).is_empty():
		push_error("SiteCompilerLab admission transition failed recomputation")
		return false
	if not SiteBlueprintModel.validate_state_transition(
		_promise, _blueprint, active_state, _enter_transition,
		String(_fresh_state.get("state_receipt", "")), _atlas, _atlas_state,
		_arrival_plan, _arrival_journey, _arrival_receipt,
		String(_arrival_journey.get("state_receipt", "")), _visit_delta, _scar_transition
	).is_empty():
		push_error("SiteCompilerLab scar transition failed recomputation")
		return false
	return true


func _first_entity_ids(entities: Array, count: int) -> Array:
	var ids: Array = []
	var limit := mini(count, entities.size())
	for index in range(limit):
		var entity: Dictionary = entities[index] as Dictionary
		ids.append(String(entity.get("id", "")))
	return ids


func _set_scarred(value: bool) -> void:
	_show_scarred = value
	_active_state = _scarred_state if _show_scarred else _fresh_state
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, DESIGN), C_BG)
	_draw_noise_field()
	_draw_header()
	_panel(MAP_PANEL, "LOCAL SITE / 32 x 22 TACTICAL BLUEPRINT")
	_panel(SIDE_PANEL, "PROMISE / TOPOLOGY / SCAR LEDGER")
	if _load_ok:
		_draw_site_map()
		_draw_side_ledger()
	else:
		_text("SITE COMPILER CONTRACT FAILED", Vector2(70.0, 180.0), 20, C_DANGER)
	_draw_footer()


func _draw_noise_field() -> void:
	for index in range(190):
		var x := float((index * 97 + 31) % 1280)
		var y := float((index * 53 + 17) % 768)
		draw_rect(Rect2(x, y, 2.0, 2.0), Color(0.72, 0.67, 0.48, 0.035))


func _draw_header() -> void:
	draw_rect(Rect2(0.0, 0.0, 1280.0, 72.0), C_HEADER)
	draw_line(Vector2(0.0, 71.0), Vector2(1280.0, 71.0), C_EDGE, 1.0)
	_text("SITE COMPILER LAB // RP-0004", Vector2(24.0, 31.0), 22, C_TEXT)
	_text("One tile promise, six local decisions, one durable scar chain.", Vector2(24.0, 55.0), 13, C_MUTED)
	var state_copy := "SCARRED / VISIT COMMITTED" if _show_scarred else "FRESH / UNVISITED"
	_text(state_copy, Vector2(912.0, 31.0), 13, C_TEAL if _show_scarred else C_GOLD,
		344.0, HORIZONTAL_ALIGNMENT_RIGHT)
	_text("SEED 260814  /  ARRIVAL IS ADMISSION ONLY", Vector2(912.0, 54.0), 10, C_MUTED,
		344.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _panel(panel_rect: Rect2, title: String) -> void:
	draw_rect(Rect2(panel_rect.position + Vector2(4.0, 5.0), panel_rect.size), Color(0.0, 0.0, 0.0, 0.32))
	draw_rect(panel_rect, C_PANEL)
	draw_rect(panel_rect, C_EDGE, false, 2.0)
	draw_rect(Rect2(panel_rect.position, Vector2(panel_rect.size.x, 31.0)), C_PANEL_2)
	draw_line(panel_rect.position + Vector2(0.0, 31.0), panel_rect.position + Vector2(panel_rect.size.x, 31.0), C_EDGE, 1.0)
	_text(title, panel_rect.position + Vector2(12.0, 22.0), 13, C_GOLD)


func _draw_site_map() -> void:
	draw_rect(Rect2(GRID_RECT.position + Vector2(4.0, 5.0), GRID_RECT.size), Color(0.0, 0.0, 0.0, 0.42))
	for y in range(int(_blueprint.get("height", 0))):
		for x in range(int(_blueprint.get("width", 0))):
			_draw_cell(Vector2i(x, y), _cell_value(Vector2i(x, y)))
	_draw_grid_guides()
	_draw_props()
	_draw_loot()
	_draw_threats()
	_draw_building_roofs()
	_draw_scar_marks()
	_draw_building_doors()
	_draw_entry_and_extraction()
	_draw_map_overlay()


func _cell_value(cell: Vector2i) -> int:
	var width := int(_blueprint.get("width", 0))
	var cells: Array = _blueprint.get("cells", []) as Array
	var index := cell.y * width + cell.x
	return int(cells[index]) if index >= 0 and index < cells.size() else SiteBlueprintModel.CELL_GROUND


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(
		GRID_RECT.position + Vector2(float(cell.x), float(cell.y)) * CELL_SIZE,
		Vector2(CELL_SIZE, CELL_SIZE)
	)


func _cell_center(cell: Vector2i) -> Vector2:
	return _cell_rect(cell).get_center()


func _draw_cell(cell: Vector2i, cell_type: int) -> void:
	var cell_rect := _cell_rect(cell)
	var inset := Rect2(cell_rect.position + Vector2.ONE * 0.5, cell_rect.size - Vector2.ONE)
	var checker := Color(0.035, 0.035, 0.025, 0.0 if (cell.x + cell.y) % 2 == 0 else 0.05)
	match cell_type:
		SiteBlueprintModel.CELL_ROAD:
			draw_rect(inset, C_ROAD.darkened(0.20))
			draw_line(cell_rect.position + Vector2(0.0, 12.0), cell_rect.position + Vector2(24.0, 12.0), Color(0.72, 0.62, 0.42, 0.12), 1.0)
		SiteBlueprintModel.CELL_FLOOR:
			draw_rect(inset, C_FLOOR)
			draw_line(cell_rect.position + Vector2(3.0, 19.0), cell_rect.position + Vector2(21.0, 19.0), Color(0.9, 0.85, 0.7, 0.08), 1.0)
		SiteBlueprintModel.CELL_WALL:
			draw_rect(inset, C_WALL)
			draw_rect(Rect2(cell_rect.position + Vector2(3.0, 3.0), cell_rect.size - Vector2(6.0, 6.0)), C_EDGE)
		SiteBlueprintModel.CELL_DOOR:
			draw_rect(inset, C_FLOOR)
			draw_rect(Rect2(cell_rect.position + Vector2(4.0, 9.0), Vector2(16.0, 6.0)), C_GOLD.darkened(0.16))
		SiteBlueprintModel.CELL_WINDOW:
			draw_rect(inset, C_WALL)
			draw_rect(Rect2(cell_rect.position + Vector2(4.0, 8.0), Vector2(16.0, 8.0)), C_WINDOW)
		SiteBlueprintModel.CELL_TREE:
			draw_rect(inset, C_DIRT)
			draw_circle(cell_rect.get_center(), 8.0, C_TREE)
			draw_circle(cell_rect.get_center() + Vector2(-2.0, -2.0), 4.0, C_TREE.lightened(0.12))
		SiteBlueprintModel.CELL_RUBBLE:
			draw_rect(inset, C_DIRT)
			draw_rect(Rect2(cell_rect.position + Vector2(5.0, 6.0), Vector2(7.0, 6.0)), C_RUBBLE)
			draw_rect(Rect2(cell_rect.position + Vector2(12.0, 12.0), Vector2(7.0, 6.0)), C_RUBBLE.darkened(0.12))
		SiteBlueprintModel.CELL_WATER:
			draw_rect(inset, C_WATER.darkened(0.24))
			draw_line(cell_rect.position + Vector2(3.0, 8.0), cell_rect.position + Vector2(20.0, 8.0), C_TEAL.darkened(0.2), 1.0)
			draw_line(cell_rect.position + Vector2(7.0, 16.0), cell_rect.position + Vector2(22.0, 16.0), C_TEAL.darkened(0.3), 1.0)
		SiteBlueprintModel.CELL_EXIT:
			draw_rect(inset, C_ROAD.darkened(0.18))
		SiteBlueprintModel.CELL_FENCE:
			draw_rect(inset, C_DIRT)
			draw_line(cell_rect.position + Vector2(4.0, 5.0), cell_rect.position + Vector2(20.0, 19.0), C_FENCE, 2.0)
			draw_line(cell_rect.position + Vector2(20.0, 5.0), cell_rect.position + Vector2(4.0, 19.0), C_FENCE, 2.0)
		SiteBlueprintModel.CELL_CROP:
			draw_rect(inset, C_DIRT.lightened(0.04))
			for row in [6.0, 12.0, 18.0]:
				draw_line(cell_rect.position + Vector2(3.0, row), cell_rect.position + Vector2(21.0, row), C_CROP, 2.0)
		SiteBlueprintModel.CELL_PIT:
			draw_rect(inset, C_PIT)
			draw_line(cell_rect.position + Vector2(3.0, 5.0), cell_rect.position + Vector2(20.0, 18.0), Color(0.65, 0.45, 0.34, 0.22), 1.0)
		_:
			draw_rect(inset, C_DIRT)
	draw_rect(inset, checker)


func _draw_grid_guides() -> void:
	for x in range(0, 33, 4):
		var px := GRID_RECT.position.x + float(x) * CELL_SIZE
		draw_line(Vector2(px, GRID_RECT.position.y), Vector2(px, GRID_RECT.end.y), Color(0.78, 0.74, 0.59, 0.055), 1.0)
	for y in range(0, 23, 4):
		var py := GRID_RECT.position.y + float(y) * CELL_SIZE
		draw_line(Vector2(GRID_RECT.position.x, py), Vector2(GRID_RECT.end.x, py), Color(0.78, 0.74, 0.59, 0.055), 1.0)
	draw_rect(GRID_RECT, C_EDGE_HI, false, 1.0)


func _draw_props() -> void:
	var destroyed := _id_set(_active_state.get("destroyed_prop_ids", []) as Array)
	for raw_prop in _blueprint.get("props", []) as Array:
		var prop: Dictionary = raw_prop as Dictionary
		var entity_id := String(prop.get("id", ""))
		if destroyed.has(entity_id) or _inside_closed_roof(_entity_pos(prop)):
			continue
		var center := _cell_center(_entity_pos(prop))
		var kind := String(prop.get("kind", "prop"))
		if kind == "tower":
			draw_line(center + Vector2(0.0, 8.0), center + Vector2(0.0, -9.0), C_TEAL, 2.0)
			draw_line(center + Vector2(-5.0, -4.0), center + Vector2(5.0, -4.0), C_TEAL, 2.0)
			draw_circle(center + Vector2(0.0, -9.0), 2.5, C_GOLD)
		else:
			draw_rect(Rect2(center - Vector2(6.0, 5.0), Vector2(12.0, 10.0)), C_EDGE_HI)
			draw_rect(Rect2(center - Vector2(4.0, 3.0), Vector2(8.0, 6.0)), C_CARD)


func _draw_loot() -> void:
	var depleted := _id_set(_active_state.get("depleted_loot_ids", []) as Array)
	for raw_loot in _blueprint.get("loot", []) as Array:
		var loot: Dictionary = raw_loot as Dictionary
		if depleted.has(String(loot.get("id", ""))) or _inside_closed_roof(_entity_pos(loot)):
			continue
		var center := _cell_center(_entity_pos(loot))
		var diamond := PackedVector2Array([
			center + Vector2(0.0, -7.0), center + Vector2(7.0, 0.0),
			center + Vector2(0.0, 7.0), center + Vector2(-7.0, 0.0),
		])
		draw_colored_polygon(diamond, C_GOLD)
		draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), C_TEXT, 1.0)


func _draw_threats() -> void:
	var cleared := _id_set(_active_state.get("neutralized_threat_ids", []) as Array)
	for raw_threat in _blueprint.get("threats", []) as Array:
		var threat: Dictionary = raw_threat as Dictionary
		if cleared.has(String(threat.get("id", ""))) or _inside_closed_roof(_entity_pos(threat)):
			continue
		var center := _cell_center(_entity_pos(threat))
		draw_circle(center, 8.0, C_DANGER.darkened(0.18))
		draw_circle(center, 8.0, C_DANGER, false, 2.0)
		_text("!", center + Vector2(-3.5, 4.5), 11, C_TEXT)


func _draw_building_roofs() -> void:
	var revealed := _id_set(_active_state.get("revealed_building_ids", []) as Array)
	for raw_building in _blueprint.get("buildings", []) as Array:
		var building: Dictionary = raw_building as Dictionary
		var roof_rect := _building_rect(building)
		if revealed.has(String(building.get("id", ""))):
			draw_rect(roof_rect.grow(-2.0), C_TEAL, false, 2.0)
			var cutaway_copy := "CUTAWAY / " + String(building.get("label", "BUILDING"))
			var copy_width := _font.get_string_size(
				cutaway_copy, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8
			).x
			var tag_width := minf(roof_rect.size.x - 8.0, maxf(96.0, copy_width + 14.0))
			var tag_position := roof_rect.position + Vector2(4.0, 4.0)
			if String(building.get("entrance_side", "")) == "north":
				tag_position.x = roof_rect.end.x - tag_width - 4.0
			var tag_rect := Rect2(
				tag_position, Vector2(tag_width, 17.0)
			)
			draw_rect(tag_rect, Color(0.08, 0.10, 0.08, 0.88))
			_text(cutaway_copy, tag_rect.position + Vector2(5.0, 12.0), 8, C_TEAL,
				tag_rect.size.x - 10.0)
			continue
		var tone := int(building.get("roof_tone", 0))
		var roof_color := Color("#4b493f")
		if tone == 1:
			roof_color = Color("#535044")
		elif tone == 2:
			roof_color = Color("#41453d")
		draw_rect(Rect2(roof_rect.position + Vector2(3.0, 5.0), roof_rect.size), Color(0.0, 0.0, 0.0, 0.38))
		draw_rect(roof_rect, roof_color)
		draw_rect(roof_rect, C_EDGE_HI, false, 2.0)
		var seam_y := roof_rect.position.y + roof_rect.size.y * 0.5
		draw_line(Vector2(roof_rect.position.x + 5.0, seam_y), Vector2(roof_rect.end.x - 5.0, seam_y), roof_color.lightened(0.14), 2.0)
		for offset in range(36, int(roof_rect.size.x), 48):
			var seam_x := roof_rect.position.x + float(offset)
			draw_line(Vector2(seam_x, roof_rect.position.y + 5.0), Vector2(seam_x, roof_rect.end.y - 5.0), Color(0.85, 0.80, 0.66, 0.08), 1.0)
		var label := String(building.get("label", "BUILDING"))
		_text(label, roof_rect.position + Vector2(8.0, 23.0), 10, C_TEXT, roof_rect.size.x - 16.0)
		_text("ROOF CLOSED", roof_rect.position + Vector2(8.0, 41.0), 8, C_MUTED, roof_rect.size.x - 16.0)


func _draw_scar_marks() -> void:
	if not _show_scarred:
		return
	for pair in [
		["depleted_loot_ids", "loot", C_GOLD],
		["neutralized_threat_ids", "threats", C_DANGER],
		["destroyed_prop_ids", "props", C_EDGE_HI],
	]:
		var field := String(pair[0])
		var source_field := String(pair[1])
		var scar_color: Color = pair[2] as Color
		var scarred := _id_set(_active_state.get(field, []) as Array)
		for raw_entity in _blueprint.get(source_field, []) as Array:
			var entity: Dictionary = raw_entity as Dictionary
			if not scarred.has(String(entity.get("id", ""))) or _inside_closed_roof(_entity_pos(entity)):
				continue
			var center := _cell_center(_entity_pos(entity))
			draw_circle(center, 8.0, Color(scar_color, 0.12))
			draw_line(center + Vector2(-6.0, -6.0), center + Vector2(6.0, 6.0), scar_color, 2.0)
			draw_line(center + Vector2(6.0, -6.0), center + Vector2(-6.0, 6.0), scar_color, 2.0)


func _draw_building_doors() -> void:
	var revealed := _id_set(_active_state.get("revealed_building_ids", []) as Array)
	for raw_building in _blueprint.get("buildings", []) as Array:
		var building: Dictionary = raw_building as Dictionary
		var building_open := revealed.has(String(building.get("id", "")))
		for raw_door in building.get("doors", []) as Array:
			var door: Dictionary = raw_door as Dictionary
			var role := String(door.get("role", ""))
			if role != "exterior" and not building_open:
				continue
			var center := _cell_center(_entity_pos(door))
			var marker_color := C_GOLD if role == "exterior" else C_TEAL
			draw_rect(Rect2(center - Vector2(7.0, 4.0), Vector2(14.0, 8.0)), Color(0.05, 0.06, 0.05, 0.92))
			draw_rect(Rect2(center - Vector2(7.0, 4.0), Vector2(14.0, 8.0)), marker_color, false, 2.0)
			if role == "exterior":
				draw_circle(center, 2.0, marker_color)


func _draw_entry_and_extraction() -> void:
	var entry: Dictionary = _blueprint.get("entry", {}) as Dictionary
	var extraction: Dictionary = _blueprint.get("extraction", {}) as Dictionary
	var entry_center := _cell_center(_entity_pos(entry))
	var exit_center := _cell_center(_entity_pos(extraction))
	var arrow := PackedVector2Array([
		entry_center + Vector2(-8.0, 6.0), entry_center + Vector2(0.0, -8.0),
		entry_center + Vector2(8.0, 6.0),
	])
	draw_colored_polygon(arrow, C_TEAL)
	draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[0]]), C_TEXT, 1.0)
	draw_circle(exit_center, 9.0, Color(0.05, 0.06, 0.05, 0.92))
	draw_circle(exit_center, 9.0, C_GOOD, false, 2.0)
	_text("X", exit_center + Vector2(-4.2, 4.2), 10, C_GOOD)


func _draw_map_overlay() -> void:
	var state_label := "SCARRED / CUTAWAYS ARE RECEIPTED" if _show_scarred else "FRESH / ROOFS HIDE INTERIORS"
	var strip := Rect2(GRID_RECT.position + Vector2(9.0, 9.0), Vector2(278.0, 28.0))
	draw_rect(strip, Color(0.055, 0.065, 0.052, 0.91))
	draw_rect(Rect2(strip.position, Vector2(5.0, strip.size.y)), C_TEAL if _show_scarred else C_GOLD)
	_text(state_label, strip.position + Vector2(13.0, 19.0), 10, C_TEXT)
	_text("ENTRY ^   EXIT X   DOOR []   LOOT <>   THREAT !", Vector2(382.0, 114.0),
		9, C_MUTED, 490.0, HORIZONTAL_ALIGNMENT_RIGHT)
	var north := GRID_RECT.position + Vector2(GRID_RECT.size.x - 25.0, 26.0)
	draw_line(north + Vector2(0.0, 9.0), north + Vector2(0.0, -8.0), C_TEXT, 2.0)
	_text("N", north + Vector2(-4.0, -12.0), 9, C_TEXT)


func _draw_side_ledger() -> void:
	var kind := String(_blueprint.get("site_kind", ""))
	var decision: Dictionary = DECISION_COPY.get(kind, {}) as Dictionary
	var topology: Dictionary = _blueprint.get("topology", {}) as Dictionary
	var accent := _kind_color(kind)

	var identity := Rect2(916.0, 137.0, 324.0, 80.0)
	_card(identity, accent)
	_text(String(KIND_TITLES.get(kind, kind.to_upper())), Vector2(930.0, 160.0), 16, C_TEXT, 294.0)
	_text("%s  /  RISK %d  /  %s" % [kind.to_upper(), int(_promise.get("risk", 0)), String(_promise.get("terrain", "")).to_upper()], Vector2(930.0, 183.0), 10, accent, 294.0)
	_text(String(_blueprint.get("layout_key", "")), Vector2(930.0, 202.0), 9, C_MUTED, 294.0)
	_text("ARRIVED EVIDENCE VERIFIED / ENTROPY UNCHANGED", Vector2(930.0, 213.0), 8, C_TEAL, 294.0)

	var promise_card := Rect2(916.0, 229.0, 324.0, 109.0)
	_card(promise_card, C_GOLD)
	_text("WHY ENTER", Vector2(930.0, 250.0), 10, C_GOLD)
	_text(String(decision.get("haul", "")), Vector2(1004.0, 250.0), 8, accent, 220.0, HORIZONTAL_ALIGNMENT_RIGHT)
	_wrapped(String(decision.get("promise", "")), Vector2(930.0, 272.0), 294.0, 10, C_TEXT, 2)
	_text("TACTICAL READ", Vector2(930.0, 305.0), 8, C_MUTED)
	_wrapped(String(decision.get("read", "")), Vector2(930.0, 321.0), 294.0, 9, C_TEXT, 2)

	var topology_card := Rect2(916.0, 350.0, 324.0, 125.0)
	_card(topology_card, C_TEAL)
	_text("TOPOLOGY GATE", Vector2(930.0, 371.0), 10, C_TEAL)
	var topology_status := "ALL TARGETS REACHABLE" if bool(topology.get("all_reachable", false)) else "CONTRACT BLOCKED"
	_text(topology_status, Vector2(1036.0, 371.0), 8, C_GOOD if bool(topology.get("all_reachable", false)) else C_DANGER, 188.0, HORIZONTAL_ALIGNMENT_RIGHT)
	_metric_pair(Vector2(930.0, 397.0), "BUILDINGS", int(topology.get("buildings_reachable", 0)), int(topology.get("buildings_total", 0)))
	_metric_pair(Vector2(1082.0, 397.0), "DOORS", int(topology.get("doors_reachable", 0)), int(topology.get("doors_total", 0)))
	_metric_pair(Vector2(930.0, 424.0), "LOOT", int(topology.get("loot_reachable", 0)), int(topology.get("loot_total", 0)))
	_metric_pair(Vector2(1082.0, 424.0), "THREATS", int(topology.get("threats_reachable", 0)), int(topology.get("threats_total", 0)))
	_text("ENTRY -> EVERY DOOR -> EXIT", Vector2(930.0, 454.0), 9, C_TEXT)
	_text("EXIT OPEN" if bool(topology.get("extraction_reachable", false)) else "EXIT BLOCKED", Vector2(1082.0, 454.0), 9, C_GOOD if bool(topology.get("extraction_reachable", false)) else C_DANGER, 142.0, HORIZONTAL_ALIGNMENT_RIGHT)

	var scar_card := Rect2(916.0, 487.0, 324.0, 174.0)
	_card(scar_card, C_TEAL if _show_scarred else C_EDGE_HI)
	_text("SCAR LEDGER", Vector2(930.0, 508.0), 10, C_TEAL if _show_scarred else C_MUTED)
	var revision := int(_active_state.get("revision", 0))
	var resolution := String(_active_state.get("last_resolution", "unvisited")).to_upper()
	_text("REV %d  /  %s" % [revision, resolution], Vector2(1045.0, 508.0), 10, C_TEXT, 179.0, HORIZONTAL_ALIGNMENT_RIGHT)
	_scar_row(535.0, "LOOT DEPLETED", (_active_state.get("depleted_loot_ids", []) as Array).size(), (_blueprint.get("loot", []) as Array).size(), C_GOLD)
	_scar_row(561.0, "THREATS CLEARED", (_active_state.get("neutralized_threat_ids", []) as Array).size(), (_blueprint.get("threats", []) as Array).size(), C_DANGER)
	_scar_row(587.0, "ROOFS REVEALED", (_active_state.get("revealed_building_ids", []) as Array).size(), (_blueprint.get("buildings", []) as Array).size(), C_TEAL)
	var destructible_count := 0
	for raw_prop in _blueprint.get("props", []) as Array:
		var prop: Dictionary = raw_prop as Dictionary
		if bool(prop.get("destructible", false)):
			destructible_count += 1
	_scar_row(613.0, "PROPS DESTROYED", (_active_state.get("destroyed_prop_ids", []) as Array).size(), destructible_count, C_EDGE_HI)
	var terminal_copy := "TAB / V BUILDS IDLE -> ACTIVE -> IDLE" if not _show_scarred else "TERMINAL CLAIMS RECEIPTED / NOT ACTION PROOF"
	if _show_scarred and kind == "haven":
		terminal_copy = "EMPTY-HAND TERMINAL / 1 ROOF INTEL CLAIM"
	_text(terminal_copy, Vector2(930.0, 646.0), 9, C_TEAL if _show_scarred else C_MUTED, 294.0)


func _card(card_rect: Rect2, accent: Color) -> void:
	draw_rect(Rect2(card_rect.position + Vector2(3.0, 4.0), card_rect.size), Color(0.0, 0.0, 0.0, 0.28))
	draw_rect(card_rect, C_CARD)
	draw_rect(card_rect, C_EDGE, false, 1.0)
	draw_rect(Rect2(card_rect.position, Vector2(5.0, card_rect.size.y)), accent)


func _metric_pair(baseline: Vector2, label: String, reachable: int, total: int) -> void:
	_text(label, baseline, 8, C_MUTED, 76.0)
	_text("%d / %d" % [reachable, total], baseline + Vector2(78.0, 0.0), 10, C_GOOD if reachable == total else C_DANGER, 56.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _scar_row(y: float, label: String, value: int, total: int, accent: Color) -> void:
	_text(label, Vector2(930.0, y), 9, C_MUTED, 140.0)
	var bar := Rect2(1073.0, y - 9.0, 112.0, 8.0)
	draw_rect(bar, Color("#2a2c25"))
	if total > 0 and value > 0:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(value) / float(total), bar.size.y)), accent)
	_text("%d / %d" % [value, total], Vector2(1187.0, y), 9, C_TEXT, 37.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_footer() -> void:
	draw_rect(Rect2(0.0, 704.0, 1280.0, 64.0), C_HEADER)
	draw_line(Vector2(0.0, 704.0), Vector2(1280.0, 704.0), C_EDGE, 1.0)
	_fixture_rects.clear()
	for index in range(FIXTURE_LABELS.size()):
		var tab_rect := Rect2(24.0 + float(index) * 138.0, 719.0, 130.0, 33.0)
		_fixture_rects.append(tab_rect)
		var selected := index == _fixture_index
		var fill := Color("#35362d") if selected else Color("#22241e")
		if tab_rect.has_point(_mouse) and not selected:
			fill = Color("#292b24")
		draw_rect(tab_rect, fill)
		draw_rect(tab_rect, C_GOLD if selected else C_EDGE, false, 1.0)
		_text(String(FIXTURE_LABELS[index]), tab_rect.position + Vector2(8.0, 22.0), 10, C_TEXT if selected else C_MUTED, tab_rect.size.x - 16.0, HORIZONTAL_ALIGNMENT_CENTER)
	_state_rect = Rect2(900.0, 719.0, 356.0, 33.0)
	draw_rect(_state_rect, C_CARD_HI)
	var half_width := _state_rect.size.x * 0.5
	var fresh_rect := Rect2(_state_rect.position, Vector2(half_width, _state_rect.size.y))
	var scarred_rect := Rect2(_state_rect.position + Vector2(half_width, 0.0), Vector2(half_width, _state_rect.size.y))
	draw_rect(fresh_rect, C_GOLD.darkened(0.55) if not _show_scarred else C_CARD_HI)
	draw_rect(scarred_rect, C_TEAL.darkened(0.55) if _show_scarred else C_CARD_HI)
	draw_rect(_state_rect, C_TEAL if _show_scarred else C_GOLD, false, 1.0)
	draw_line(Vector2(scarred_rect.position.x, scarred_rect.position.y), Vector2(scarred_rect.position.x, scarred_rect.end.y), C_EDGE, 1.0)
	_text("FRESH", fresh_rect.position + Vector2(10.0, 22.0), 10, C_TEXT, fresh_rect.size.x - 20.0, HORIZONTAL_ALIGNMENT_CENTER)
	_text("SCARRED  [TAB / V]", scarred_rect.position + Vector2(10.0, 22.0), 10, C_TEXT, scarred_rect.size.x - 20.0, HORIZONTAL_ALIGNMENT_CENTER)


func _building_rect(building: Dictionary) -> Rect2:
	var values: Array = building.get("rect", []) as Array
	if values.size() != 4:
		return Rect2()
	return Rect2(
		GRID_RECT.position + Vector2(float(values[0]), float(values[1])) * CELL_SIZE,
		Vector2(float(values[2]), float(values[3])) * CELL_SIZE
	)


func _entity_pos(entity: Dictionary) -> Vector2i:
	var values: Array = entity.get("pos", []) as Array
	return Vector2i(int(values[0]), int(values[1])) if values.size() == 2 else Vector2i(-1000, -1000)


func _inside_closed_roof(cell: Vector2i) -> bool:
	var revealed := _id_set(_active_state.get("revealed_building_ids", []) as Array)
	for raw_building in _blueprint.get("buildings", []) as Array:
		var building: Dictionary = raw_building as Dictionary
		if revealed.has(String(building.get("id", ""))):
			continue
		var values: Array = building.get("rect", []) as Array
		if values.size() == 4 and cell.x >= int(values[0]) and cell.y >= int(values[1]) \
				and cell.x < int(values[0]) + int(values[2]) \
				and cell.y < int(values[1]) + int(values[3]):
			return true
	return false


func _id_set(ids: Array) -> Dictionary:
	var result := {}
	for raw_id in ids:
		result[String(raw_id)] = true
	return result


func _kind_color(kind: String) -> Color:
	match kind:
		"clinic":
			return C_TEAL
		"relay":
			return Color("#84aebe")
		"quarry":
			return C_DANGER
		"farm":
			return C_GOOD
		"haven":
			return Color("#b1b17a")
	return C_GOLD


func _text(copy: String, baseline: Vector2, size: int, color: Color,
		width: float = -1.0, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(_font, baseline, copy, alignment, width, size, color)


func _wrapped(copy: String, baseline: Vector2, width: float, size: int,
		color: Color, max_lines: int) -> float:
	var words := copy.split(" ", false)
	var line := ""
	var y := baseline.y
	var line_count := 0
	for raw_word in words:
		var word := String(raw_word)
		var candidate := word if line == "" else line + " " + word
		if _font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x > width and line != "":
			_text(line, Vector2(baseline.x, y), size, color, width)
			y += float(size + 4)
			line_count += 1
			line = word
			if line_count >= max_lines:
				return y
		else:
			line = candidate
	if line != "" and line_count < max_lines:
		_text(line, Vector2(baseline.x, y), size, color, width)
		y += float(size + 4)
	return y


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_mouse = motion.position
		queue_redraw()
		return
	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_LEFT and button_event.pressed:
			_handle_click(button_event.position)
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F:
			_apply_fixture(int(key_event.keycode) - int(KEY_A), _show_scarred)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			_apply_fixture(int(key_event.keycode) - int(KEY_1), _show_scarred)
		KEY_TAB, KEY_V:
			_set_scarred(not _show_scarred)


func _handle_click(click_position: Vector2) -> void:
	for index in range(_fixture_rects.size()):
		if _fixture_rects[index].has_point(click_position):
			_apply_fixture(index, _show_scarred)
			return
	if _state_rect.has_point(click_position):
		_set_scarred(not _show_scarred)


func _save_shot() -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("SiteCompilerLab could not capture the viewport")
		get_tree().quit(1)
		return
	var save_error := image.save_png(_shot_path)
	if save_error != OK:
		push_error("SiteCompilerLab could not save screenshot: %s" % error_string(save_error))
		get_tree().quit(1)
		return
	get_tree().quit()
