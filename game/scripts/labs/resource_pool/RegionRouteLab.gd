extends Node2D

const RegionRouteModel = preload("res://scripts/labs/resource_pool/RegionRouteModel.gd")

const DESIGN := Vector2(1280.0, 768.0)
const ATLAS_PANEL := Rect2(24.0, 92.0, 824.0, 590.0)
const BOARD_PANEL := Rect2(864.0, 92.0, 392.0, 590.0)
const MAP_VIEW := Rect2(40.0, 193.0, 792.0, 419.0)
const HEX_RADIUS := 20.0
const SQRT_3 := 1.7320508075688772

const C_BG := Color("#11140f")
const C_HEADER := Color("#171a14")
const C_PANEL := Color("#1c1e19")
const C_PANEL_2 := Color("#24251f")
const C_CARD := Color("#22241e")
const C_CARD_SELECTED := Color("#303128")
const C_EDGE := Color("#565846")
const C_EDGE_HI := Color("#89866d")
const C_TEXT := Color("#ded8c4")
const C_MUTED := Color("#929382")
const C_GOLD := Color("#d2a85c")
const C_TEAL := Color("#78a999")
const C_GOOD := Color("#8fb56d")
const C_DANGER := Color("#c45b50")
const C_TIGHT := Color("#d39a55")
const C_ROAD_OUTER := Color("#3d3528")
const C_ROAD_INNER := Color("#a58d61")

const TERRAIN_COLORS := {
	"pine": Color("#4d674b"),
	"steppe": Color("#80805a"),
	"scrub": Color("#6f6846"),
	"marsh": Color("#496765"),
	"highland": Color("#726f67"),
	"ash": Color("#675b55"),
}

const FIXTURE_LABELS := ["A  AUTUMN", "B  SPRING", "C  WINTER", "D  2 LEGS", "E  EMPTY"]

var _font: Font
var _atlas: Dictionary = {}
var _atlas_state: Dictionary = {}
var _board: Dictionary = {}
var _journey: Dictionary = {}
var _active_plan: Dictionary = {}
var _diversion_preview: Dictionary = {}
var _tile_by_id: Dictionary = {}
var _fixture_index := 0
var _selected_route := 0
var _route_override := -1
var _season := "autumn"
var _supplies_milli := 8500
var _condition_milli := 92000
var _active_is_fallback := false
var _last_leg_result := ""
var _map_offset := Vector2.ZERO
var _mouse := Vector2(-1000.0, -1000.0)
var _pulse := 0.0
var _shot_path := ""
var _route_rects: Array[Rect2] = []
var _fixture_rects: Array[Rect2] = []
var _primary_rect := Rect2()
var _fallback_rect := Rect2()


func _ready() -> void:
	_font = ThemeDB.fallback_font
	var requested_fixture := 0
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size()):
		var argument := String(args[i])
		if argument == "--region-fixture" and i + 1 < args.size():
			requested_fixture = _fixture_from_argument(String(args[i + 1]))
		elif argument == "--region-route" and i + 1 < args.size():
			_route_override = _route_from_argument(String(args[i + 1]))
		elif argument == "--lab-shot" and i + 1 < args.size():
			_shot_path = String(args[i + 1])
	_atlas = RegionRouteModel.make_atlas(RegionRouteModel.DEFAULT_ROOT_SEED)
	if _atlas.is_empty():
		push_error("RegionRouteLab could not create its deterministic atlas")
		return
	_rebuild_tile_index()
	_compute_map_offset()
	_apply_fixture(requested_fixture)
	set_process(true)
	queue_redraw()
	if _shot_path != "":
		get_tree().create_timer(0.8).timeout.connect(_save_shot)


func _process(delta: float) -> void:
	if _shot_path != "":
		return
	_pulse = fmod(_pulse + delta, 1000.0)
	queue_redraw()


func _fixture_from_argument(value: String) -> int:
	match value.strip_edges().to_lower():
		"a", "autumn", "choice":
			return 0
		"b", "spring", "wet":
			return 1
		"c", "winter", "fallback":
			return 2
		"d", "2", "two_legs", "two-legs", "journey":
			return 3
		"e", "empty", "no_plan", "no-plan":
			return 4
	return 0


func _route_from_argument(value: String) -> int:
	var normalized := value.strip_edges().to_lower()
	if normalized in ["1", "orra", "orra_ridge_cut"]:
		return 0
	if normalized in ["2", "market", "old_market_road"]:
		return 1
	if normalized in ["3", "dunlin", "dunlin_supply_arc"]:
		return 2
	return -1


func _apply_fixture(index: int) -> void:
	_fixture_index = clampi(index, 0, FIXTURE_LABELS.size() - 1)
	_atlas_state = RegionRouteModel.make_initial_atlas_state(_atlas)
	_journey = {}
	_active_plan = {}
	_diversion_preview = {}
	_active_is_fallback = false
	_last_leg_result = ""
	_supplies_milli = 8500
	_condition_milli = 92000
	match _fixture_index:
		0:
			_season = "autumn"
		1:
			_season = "spring"
		2:
			_season = "winter"
		3:
			_season = "autumn"
		4:
			_season = "autumn"
			_supplies_milli = 0
	_selected_route = _route_override if _route_override >= 0 else (1 if _fixture_index == 3 else 0)
	_rebuild_board()
	if _fixture_index == 3:
		_begin_primary()
		_advance_leg()
		_advance_leg()
	queue_redraw()


func _rebuild_board() -> void:
	var start_id := RegionRouteModel.site_tile_id(_atlas, "ash_market")
	var destination_id := RegionRouteModel.site_tile_id(_atlas, "cinder_crossing")
	_board = RegionRouteModel.route_board(
		_atlas, _atlas_state, start_id, destination_id, _season,
		_supplies_milli, _condition_milli
	)
	if _board.is_empty():
		push_error("RegionRouteLab could not build its route board")


func _rebuild_tile_index() -> void:
	_tile_by_id.clear()
	var tiles: Array = _atlas.get("tiles", []) as Array
	for raw_tile in tiles:
		var tile: Dictionary = raw_tile as Dictionary
		_tile_by_id[String(tile.get("id", ""))] = tile


func _compute_map_offset() -> void:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var tiles: Array = _atlas.get("tiles", []) as Array
	for raw_tile in tiles:
		var tile: Dictionary = raw_tile as Dictionary
		var raw_center := _raw_hex_center(int(tile.get("q", 0)), int(tile.get("r", 0)))
		minimum.x = minf(minimum.x, raw_center.x - SQRT_3 * HEX_RADIUS * 0.5)
		minimum.y = minf(minimum.y, raw_center.y - HEX_RADIUS)
		maximum.x = maxf(maximum.x, raw_center.x + SQRT_3 * HEX_RADIUS * 0.5)
		maximum.y = maxf(maximum.y, raw_center.y + HEX_RADIUS)
	_map_offset = MAP_VIEW.get_center() - (minimum + maximum) * 0.5


func _raw_hex_center(q: int, r: int) -> Vector2:
	return Vector2(
		SQRT_3 * HEX_RADIUS * (float(q) + float(r) * 0.5),
		HEX_RADIUS * 1.5 * float(r)
	)


func _tile_center(tile: Dictionary) -> Vector2:
	return _raw_hex_center(int(tile.get("q", 0)), int(tile.get("r", 0))) + _map_offset


func _center_for_id(tile_id: String) -> Vector2:
	if not _tile_by_id.has(tile_id):
		return Vector2(-1000.0, -1000.0)
	return _tile_center(_tile_by_id[tile_id] as Dictionary)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, DESIGN), C_BG)
	_draw_noise_field()
	_draw_header()
	_draw_atlas_panel()
	_draw_route_board()
	_draw_fixture_footer()


func _draw_noise_field() -> void:
	for i in range(180):
		var x := float((i * 97 + 31) % 1280)
		var y := float((i * 53 + 17) % 768)
		draw_rect(Rect2(x, y, 2.0, 2.0), Color(0.72, 0.67, 0.48, 0.04))


func _draw_header() -> void:
	draw_rect(Rect2(0.0, 0.0, 1280.0, 72.0), C_HEADER)
	draw_line(Vector2(0.0, 71.0), Vector2(1280.0, 71.0), C_EDGE, 1.0)
	_text("REGION ROUTE LAB // RP-0003", Vector2(24.0, 31.0), 22, C_TEXT)
	_text("Choose what you can afford to spend: time, supply, or rig.", Vector2(24.0, 55.0), 13, C_MUTED)
	_text("ASHFALL SOUTH", Vector2(1030.0, 31.0), 13, C_GOLD, 226.0, HORIZONTAL_ALIGNMENT_RIGHT)
	_text("SEED 260814  /  INTEGER ROUTE CONTRACT", Vector2(940.0, 54.0), 11, C_MUTED, 316.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _panel(panel_rect: Rect2, title: String) -> void:
	draw_rect(Rect2(panel_rect.position + Vector2(4.0, 5.0), panel_rect.size), Color(0.0, 0.0, 0.0, 0.32))
	draw_rect(panel_rect, C_PANEL)
	draw_rect(panel_rect, C_EDGE, false, 2.0)
	draw_rect(Rect2(panel_rect.position, Vector2(panel_rect.size.x, 31.0)), C_PANEL_2)
	draw_line(panel_rect.position + Vector2(0.0, 31.0), panel_rect.position + Vector2(panel_rect.size.x, 31.0), C_EDGE, 1.0)
	_text(title, panel_rect.position + Vector2(12.0, 22.0), 13, C_GOLD)


func _draw_atlas_panel() -> void:
	_panel(ATLAS_PANEL, "REGION ATLAS / ASHFALL SOUTH")
	draw_rect(Rect2(40.0, 137.0, 792.0, 44.0), Color("#171914"))
	draw_rect(Rect2(40.0, 137.0, 5.0, 44.0), _phase_color())
	_text("ASH MARKET  ->  CINDER CROSSING", Vector2(57.0, 164.0), 14, C_TEXT)
	var condition_copy := "%s  /  SUPPLY %s  /  RIG %s" % [
		_season.to_upper(), _format_milli(_display_supply()), _format_milli(_display_condition())
	]
	_text(condition_copy, Vector2(477.0, 164.0), 12, C_MUTED, 339.0, HORIZONTAL_ALIGNMENT_RIGHT)
	_draw_hex_terrain()
	_draw_corridor_network()
	_draw_offer_routes()
	if _season == "winter":
		_draw_blocked_ridge()
	_draw_sites_and_labels()
	_draw_caravan()
	_draw_map_legend()


func _draw_hex_terrain() -> void:
	var discovered := {}
	var discovered_ids: Array = _atlas_state.get("discovered_tile_ids", []) as Array
	for raw_id in discovered_ids:
		discovered[String(raw_id)] = true
	var tiles: Array = _atlas.get("tiles", []) as Array
	for raw_tile in tiles:
		var tile: Dictionary = raw_tile as Dictionary
		var tile_id := String(tile.get("id", ""))
		var known := discovered.has(tile_id)
		var terrain := String(tile.get("terrain", "steppe"))
		var fill: Color = TERRAIN_COLORS.get(terrain, TERRAIN_COLORS["steppe"]) as Color
		if not known:
			fill = fill.lerp(Color("#252922"), 0.72)
		var center := _tile_center(tile)
		var points := _hex_points(center, HEX_RADIUS - 0.75)
		draw_colored_polygon(points, fill)
		if known:
			_draw_hex_texture(tile, center)
		draw_polyline(_closed(points), Color("#282c24"), 1.0, true)


func _hex_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(6):
		var angle := deg_to_rad(30.0 + float(i) * 60.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	if not result.is_empty():
		result.append(result[0])
	return result


func _draw_hex_texture(tile: Dictionary, center: Vector2) -> void:
	var terrain := String(tile.get("terrain", "steppe"))
	var q := int(tile.get("q", 0))
	var r := int(tile.get("r", 0))
	var tone := Color(0.09, 0.10, 0.08, 0.24)
	if terrain == "pine":
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(0.0, -7.0), center + Vector2(-5.0, 3.0), center + Vector2(5.0, 3.0)
		]), Color(0.08, 0.16, 0.09, 0.34))
	elif terrain == "marsh":
		draw_line(center + Vector2(-9.0, -4.0), center + Vector2(7.0, -4.0), Color(0.45, 0.70, 0.67, 0.24), 1.0)
		draw_line(center + Vector2(-6.0, 3.0), center + Vector2(10.0, 3.0), Color(0.45, 0.70, 0.67, 0.24), 1.0)
	elif terrain == "highland":
		draw_polyline(PackedVector2Array([
			center + Vector2(-8.0, 5.0), center + Vector2(-1.0, -6.0), center + Vector2(8.0, 5.0)
		]), Color(0.85, 0.82, 0.73, 0.25), 1.0, true)
	elif terrain == "ash":
		for i in range(3):
			var px := float(((q * 11 + r * 7 + i * 5) % 15) - 7)
			var py := float(((q * 5 + r * 13 + i * 7) % 13) - 6)
			draw_rect(Rect2(center + Vector2(px, py), Vector2(2.0, 2.0)), tone)
	elif terrain == "scrub":
		draw_line(center + Vector2(-6.0, 5.0), center + Vector2(-1.0, -3.0), tone, 1.0)
		draw_line(center + Vector2(4.0, 6.0), center + Vector2(7.0, -1.0), tone, 1.0)
	else:
		draw_circle(center + Vector2(float((q + r) % 5 - 2), 1.0), 1.5, tone)


func _draw_corridor_network() -> void:
	var edges: Array = _atlas.get("edges", []) as Array
	for raw_edge in edges:
		var edge: Dictionary = raw_edge as Dictionary
		var road_class := String(edge.get("road_class", "none"))
		var corridor := String(edge.get("corridor", "none"))
		if road_class == "none" and corridor == "none":
			continue
		var from_point := _center_for_id(String(edge.get("a", "")))
		var to_point := _center_for_id(String(edge.get("b", "")))
		if _edge_is_closed(String(edge.get("id", ""))):
			draw_line(from_point, to_point, Color(C_DANGER, 0.42), 3.0, true)
			continue
		if road_class == "road":
			draw_line(from_point, to_point, C_ROAD_OUTER, 5.0, true)
			draw_line(from_point, to_point, C_ROAD_INNER, 1.5, true)
		else:
			_draw_dashed_segment(from_point, to_point, Color(C_ROAD_OUTER, 0.95), 3.5, 7.0, 4.0)
			_draw_dashed_segment(from_point, to_point, Color(C_ROAD_INNER, 0.78), 1.2, 7.0, 4.0)


func _edge_is_closed(edge_id: String) -> bool:
	var deltas: Array = _atlas_state.get("road_deltas", []) as Array
	for raw_delta in deltas:
		var delta: Dictionary = raw_delta as Dictionary
		if String(delta.get("edge_id", "")) == edge_id and String(delta.get("state", "")) == "closed":
			return true
	return false


func _draw_offer_routes() -> void:
	var offers: Array = _board.get("offers", []) as Array
	if _journey.is_empty():
		for i in range(offers.size()):
			if i == _selected_route:
				continue
			var offer: Dictionary = offers[i] as Dictionary
			var plan: Dictionary = offer.get("plan", {}) as Dictionary
			if bool(plan.get("available", false)):
				_draw_path(plan.get("path", []) as Array, Color(C_EDGE_HI, 0.46), 1.4, false)
		var selected_offer := _selected_offer()
		var selected_plan: Dictionary = selected_offer.get("plan", {}) as Dictionary
		var selected_projection: Dictionary = selected_offer.get("projection", {}) as Dictionary
		if bool(selected_plan.get("available", false)):
			if bool(selected_projection.get("reachable", false)):
				_draw_path(selected_plan.get("path", []) as Array, Color(0.05, 0.06, 0.05, 0.76), 8.0, false)
				_draw_path(selected_plan.get("path", []) as Array, C_GOLD, 2.7, false)
				_draw_path_nodes(selected_plan.get("path", []) as Array, C_GOLD)
			else:
				_draw_path(selected_plan.get("path", []) as Array, Color(C_DANGER, 0.58), 2.0, true)
		var fallback_offer: Dictionary = _board.get("fallback_offer", {}) as Dictionary
		if not fallback_offer.is_empty():
			var fallback_plan: Dictionary = fallback_offer.get("plan", {}) as Dictionary
			_draw_path(fallback_plan.get("path", []) as Array, C_TEAL, 3.0, true)
	else:
		_draw_active_journey_path()


func _draw_active_journey_path() -> void:
	var path: Array = _active_plan.get("path", []) as Array
	if path.size() < 2:
		return
	var index := int(_journey.get("leg_index", 0))
	var traversed: Array = []
	var remaining: Array = []
	for i in range(path.size()):
		if i <= index:
			traversed.append(path[i])
		if i >= index:
			remaining.append(path[i])
	if traversed.size() > 1:
		_draw_path(traversed, Color(C_MUTED, 0.48), 5.0, false)
	if remaining.size() > 1:
		var route_color := C_TEAL if _active_is_fallback else C_GOLD
		_draw_path(remaining, Color(0.05, 0.06, 0.05, 0.76), 8.0, false)
		_draw_path(remaining, route_color, 3.0, _active_is_fallback)
		_draw_path_nodes(remaining, route_color)


func _draw_path(path: Array, color: Color, width: float, dashed: bool) -> void:
	for i in range(path.size() - 1):
		var from_point := _center_for_id(String(path[i]))
		var to_point := _center_for_id(String(path[i + 1]))
		if dashed:
			_draw_dashed_segment(from_point, to_point, color, width, 8.0, 5.0)
		else:
			draw_line(from_point, to_point, color, width, true)


func _draw_path_nodes(path: Array, color: Color) -> void:
	for raw_id in path:
		draw_circle(_center_for_id(String(raw_id)), 2.7, color)


func _draw_dashed_segment(from_point: Vector2, to_point: Vector2, color: Color,
		width: float, dash_length: float, gap_length: float) -> void:
	var delta := to_point - from_point
	var length := delta.length()
	if length <= 0.001:
		return
	var direction := delta / length
	var cursor := 0.0
	while cursor < length:
		var end_distance := minf(cursor + dash_length, length)
		draw_line(from_point + direction * cursor, from_point + direction * end_distance, color, width, true)
		cursor += dash_length + gap_length


func _draw_blocked_ridge() -> void:
	var edges: Array = _atlas.get("edges", []) as Array
	for raw_edge in edges:
		var edge: Dictionary = raw_edge as Dictionary
		if String(edge.get("corridor", "")) != "ridge":
			continue
		var from_point := _center_for_id(String(edge.get("a", "")))
		var to_point := _center_for_id(String(edge.get("b", "")))
		draw_line(from_point, to_point, Color(C_DANGER, 0.38), 2.0, true)
	var pass_center := _center_for_coord(Vector2i(5, 0))
	draw_line(pass_center + Vector2(-8.0, -8.0), pass_center + Vector2(8.0, 8.0), C_DANGER, 3.0, true)
	draw_line(pass_center + Vector2(8.0, -8.0), pass_center + Vector2(-8.0, 8.0), C_DANGER, 3.0, true)


func _center_for_coord(coord: Vector2i) -> Vector2:
	var tiles: Array = _atlas.get("tiles", []) as Array
	for raw_tile in tiles:
		var tile: Dictionary = raw_tile as Dictionary
		if int(tile.get("q", 0)) == coord.x and int(tile.get("r", 0)) == coord.y:
			return _tile_center(tile)
	return Vector2(-1000.0, -1000.0)


func _draw_sites_and_labels() -> void:
	var discovered := {}
	var discovered_ids: Array = _atlas_state.get("discovered_tile_ids", []) as Array
	for raw_id in discovered_ids:
		discovered[String(raw_id)] = true
	var tiles: Array = _atlas.get("tiles", []) as Array
	for raw_tile in tiles:
		var tile: Dictionary = raw_tile as Dictionary
		if String(tile.get("site_key", "")) == "":
			continue
		_draw_site_icon(_tile_center(tile), String(tile.get("site_kind", "")), discovered.has(String(tile.get("id", ""))))
	var origin_id := String(_board.get("origin", ""))
	var destination_id := String(_board.get("destination", ""))
	_draw_site_label(_center_for_id(origin_id) + Vector2(14.0, -24.0), "ASH MARKET", C_GOLD)
	_draw_site_label(_center_for_id(destination_id) + Vector2(14.0, 20.0), "CINDER CROSSING", C_TEXT)
	var fallback_id := _selected_fallback_id()
	if fallback_id != "" and fallback_id not in [origin_id, destination_id]:
		var fallback_center := _center_for_id(fallback_id)
		_draw_diamond(fallback_center, 7.0, C_TEAL)
		_draw_site_label(fallback_center + Vector2(13.0, 17.0), "F/B " + _label_for_id(fallback_id), C_TEAL)
	if _season == "winter":
		var pass_center := _center_for_coord(Vector2i(5, 0))
		_draw_site_label(pass_center + Vector2(13.0, -19.0), "RIDGE PASS / CLOSED", C_DANGER)


func _draw_site_icon(center: Vector2, kind: String, discovered: bool) -> void:
	var ink := C_TEXT if discovered else Color(C_MUTED, 0.55)
	if kind == "haven":
		_draw_diamond(center, 6.0, ink)
		draw_circle(center, 2.0, C_GOOD)
	elif kind == "clinic":
		draw_rect(Rect2(center - Vector2(6.0, 6.0), Vector2(12.0, 12.0)), Color("#ddd2b7"))
		draw_rect(Rect2(center - Vector2(1.5, 5.0), Vector2(3.0, 10.0)), C_DANGER)
		draw_rect(Rect2(center - Vector2(5.0, 1.5), Vector2(10.0, 3.0)), C_DANGER)
	elif kind == "farm":
		draw_rect(Rect2(center + Vector2(-6.0, -2.0), Vector2(12.0, 8.0)), ink)
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(-7.0, -2.0), center + Vector2(0.0, -8.0), center + Vector2(7.0, -2.0)
		]), Color("#6b5136"))
	elif kind == "relay":
		draw_line(center + Vector2(0.0, 7.0), center + Vector2(0.0, -7.0), ink, 2.0)
		draw_line(center + Vector2(-5.0, -3.0), center + Vector2(0.0, -7.0), ink, 2.0)
		draw_line(center + Vector2(5.0, -3.0), center + Vector2(0.0, -7.0), ink, 2.0)
	else:
		draw_rect(Rect2(center - Vector2(6.0, 5.0), Vector2(5.0, 10.0)), ink)
		draw_rect(Rect2(center + Vector2(1.0, -2.0), Vector2(6.0, 7.0)), ink.darkened(0.2))


func _draw_diamond(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0.0, -radius), center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius), center + Vector2(-radius, 0.0), center + Vector2(0.0, -radius)
	])
	draw_polyline(points, color, 2.0, true)


func _draw_site_label(anchor: Vector2, copy: String, color: Color) -> void:
	var label_width := minf(172.0, maxf(54.0, float(copy.length()) * 6.25 + 12.0))
	var label_pos := Vector2(
		clampf(anchor.x, MAP_VIEW.position.x + 2.0, MAP_VIEW.end.x - label_width - 2.0),
		clampf(anchor.y, MAP_VIEW.position.y + 13.0, MAP_VIEW.end.y - 3.0)
	)
	draw_rect(Rect2(label_pos + Vector2(-5.0, -12.0), Vector2(label_width, 16.0)), Color(0.06, 0.07, 0.055, 0.84))
	_text(copy, label_pos, 10, color, label_width - 8.0)


func _draw_caravan() -> void:
	var caravan_id := String(_board.get("origin", ""))
	if not _journey.is_empty():
		caravan_id = String(_journey.get("current_tile", caravan_id))
	var center := _center_for_id(caravan_id) + Vector2(0.0, -13.0)
	draw_circle(center + Vector2(-6.0, 7.0), 3.2, Color("#171813"))
	draw_circle(center + Vector2(6.0, 7.0), 3.2, Color("#171813"))
	draw_rect(Rect2(center + Vector2(-9.0, -2.0), Vector2(18.0, 9.0)), Color("#5b4933"))
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-10.0, -2.0), center + Vector2(-6.0, -9.0),
		center + Vector2(6.0, -9.0), center + Vector2(10.0, -2.0)
	]), Color("#d7c79f"))
	draw_circle(center, 13.0 + sin(_pulse * 3.0), Color(C_GOLD, 0.20), false, 1.5)


func _draw_map_legend() -> void:
	draw_rect(Rect2(40.0, 626.0, 792.0, 35.0), Color("#171914"))
	var x_positions := [58.0, 178.0, 296.0, 436.0, 576.0]
	_draw_legend_line(Vector2(x_positions[0], 643.0), C_ROAD_INNER, false)
	_text("ROAD", Vector2(x_positions[0] + 28.0, 648.0), 10, C_MUTED)
	_draw_legend_line(Vector2(x_positions[1], 643.0), C_ROAD_INNER, true)
	_text("TRACK", Vector2(x_positions[1] + 28.0, 648.0), 10, C_MUTED)
	_draw_legend_line(Vector2(x_positions[2], 643.0), C_GOLD, false)
	_text("SELECTED", Vector2(x_positions[2] + 28.0, 648.0), 10, C_MUTED)
	_draw_legend_line(Vector2(x_positions[3], 643.0), C_TEAL, true)
	_text("FALLBACK", Vector2(x_positions[3] + 28.0, 648.0), 10, C_MUTED)
	draw_line(Vector2(x_positions[4], 637.0), Vector2(x_positions[4] + 12.0, 649.0), C_DANGER, 2.0)
	draw_line(Vector2(x_positions[4] + 12.0, 637.0), Vector2(x_positions[4], 649.0), C_DANGER, 2.0)
	_text("CLOSED", Vector2(x_positions[4] + 28.0, 648.0), 10, C_MUTED)
	_text("SAFE >= 2.000  /  F/B >= 0.500", Vector2(634.0, 648.0), 10, C_MUTED, 182.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_legend_line(origin: Vector2, color: Color, dashed: bool) -> void:
	if dashed:
		_draw_dashed_segment(origin, origin + Vector2(20.0, 0.0), color, 2.0, 5.0, 3.0)
	else:
		draw_line(origin, origin + Vector2(20.0, 0.0), color, 2.0, true)


func _draw_route_board() -> void:
	_panel(BOARD_PANEL, "ROUTE BOARD / THREE PROMISES")
	_draw_board_summary()
	_route_rects.clear()
	var offers: Array = _board.get("offers", []) as Array
	for i in range(offers.size()):
		var card_rect := Rect2(880.0, 203.0 + float(i) * 116.0, 360.0, 108.0)
		_route_rects.append(card_rect)
		_draw_route_card(card_rect, offers[i] as Dictionary, i)
	_draw_selected_detail()


func _draw_board_summary() -> void:
	var summary_rect := Rect2(880.0, 137.0, 360.0, 54.0)
	draw_rect(summary_rect, Color("#171914"))
	var headline := "NO ROUTE BOARD"
	var explanation := "Contract data unavailable."
	var summary_color := C_DANGER
	if not _journey.is_empty():
		var phase := String(_journey.get("phase", "traveling"))
		var path: Array = _active_plan.get("path", []) as Array
		var leg := int(_journey.get("leg_index", 0))
		if phase == "traveling":
			headline = "EN ROUTE  /  LEG %d OF %d" % [leg, maxi(0, path.size() - 1)]
			summary_color = C_TEAL if _active_is_fallback else C_GOLD
		elif phase == "arrived":
			headline = "ARRIVED  /  " + _label_for_id(String(_journey.get("current_tile", "")))
			summary_color = C_GOOD
		else:
			headline = _stranded_copy()
			summary_color = C_DANGER
		explanation = "ELAPSED %s  /  SUPPLY %s  /  RIG %s" % [
			_format_minutes(int(_journey.get("elapsed_minutes", 0))),
			_format_milli(int(_journey.get("supplies_milli", 0))),
			_format_milli(int(_journey.get("condition_milli", 0)))
		]
	else:
		var decision := String(_board.get("decision_status", "no_plan"))
		var counts := _offer_status_counts()
		if decision == "routes_available":
			headline = "ROUTES AVAILABLE  /  %d SAFE" % int(counts.get("safe", 0))
			explanation = "%d TIGHT  /  %d BLOCKED  /  SAFE RESERVE 2.000" % [
				int(counts.get("tight", 0)), int(counts.get("blocked", 0))
			]
			summary_color = C_GOOD
		elif decision == "fallback_only":
			headline = "FALLBACK ONLY"
			explanation = "NO DESTINATION ROUTE MEETS 2.000  /  F/B RESERVE 0.500"
			summary_color = C_TEAL
		else:
			headline = "NO VIABLE PLAN"
			explanation = "DESTINATION AND FALLBACK RESERVES NOT MET"
			summary_color = C_DANGER
	draw_rect(Rect2(summary_rect.position, Vector2(5.0, summary_rect.size.y)), summary_color)
	_text(headline, Vector2(894.0, 159.0), 14, summary_color)
	_text(explanation, Vector2(894.0, 180.0), 10, C_MUTED, 332.0)


func _offer_status_counts() -> Dictionary:
	var result := {"safe": 0, "tight": 0, "blocked": 0}
	var offers: Array = _board.get("offers", []) as Array
	for raw_offer in offers:
		var offer: Dictionary = raw_offer as Dictionary
		var projection: Dictionary = offer.get("projection", {}) as Dictionary
		var status := String(projection.get("status", "blocked"))
		result[status] = int(result.get(status, 0)) + 1
	return result


func _draw_route_card(card_rect: Rect2, offer: Dictionary, index: int) -> void:
	var selected := index == _selected_route
	var hovered := card_rect.has_point(_mouse) and _journey.is_empty()
	var fill := C_CARD_SELECTED if selected else C_CARD
	if hovered and not selected:
		fill = Color("#292b24")
	draw_rect(card_rect, fill)
	draw_rect(card_rect, C_EDGE_HI if selected else C_EDGE, false, 1.0)
	draw_rect(Rect2(card_rect.position, Vector2(5.0, card_rect.size.y)), C_GOLD if selected else C_EDGE)
	var projection: Dictionary = offer.get("projection", {}) as Dictionary
	var plan: Dictionary = offer.get("plan", {}) as Dictionary
	var status := String(projection.get("status", "blocked"))
	var status_color := _status_color(status)
	_text("%d  %s" % [index + 1, String(offer.get("label", "ROUTE"))], card_rect.position + Vector2(14.0, 22.0), 13, C_TEXT, 225.0)
	_text(status.to_upper(), card_rect.position + Vector2(248.0, 22.0), 11, status_color, 98.0, HORIZONTAL_ALIGNMENT_RIGHT)
	var badges := _advantage_copy(offer, plan, projection)
	_text(badges, card_rect.position + Vector2(14.0, 44.0), 10, status_color if status == "blocked" else C_MUTED, 332.0)
	var totals: Dictionary = plan.get("totals", {}) as Dictionary
	var available := bool(plan.get("available", false))
	var reachable := bool(projection.get("reachable", false))
	var eta := _format_minutes(int(totals.get("minutes", 0))) if available else "--:--"
	var use_copy := _format_milli(int(totals.get("supply_milli", 0))) if available else "--"
	var arrival_copy := _format_milli(int(projection.get("arrival_supply_milli", 0))) if reachable else "--"
	_text("ETA %s" % eta, card_rect.position + Vector2(14.0, 69.0), 11, C_TEXT, 92.0)
	_text("USE %s" % use_copy, card_rect.position + Vector2(108.0, 69.0), 11, C_TEXT, 104.0)
	_text("ARRIVE %s" % arrival_copy, card_rect.position + Vector2(214.0, 69.0), 11, status_color, 132.0, HORIZONTAL_ALIGNMENT_RIGHT)
	var wear_copy := _format_milli(int(totals.get("condition_milli", 0))) if available else "--"
	var risk_copy := str(int(totals.get("risk_points", 0))) if available else "--"
	_text("WEAR %s  /  RISK %s" % [wear_copy, risk_copy], card_rect.position + Vector2(14.0, 94.0), 10, C_MUTED, 172.0)
	var fallback_id := String(plan.get("fallback", ""))
	var fallback_copy := "F/B " + _label_for_id(fallback_id) if fallback_id != "" else "NO F/B"
	_text(fallback_copy, card_rect.position + Vector2(183.0, 94.0), 10, C_TEAL if fallback_id != "" else C_MUTED, 163.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _advantage_copy(offer: Dictionary, plan: Dictionary, projection: Dictionary) -> String:
	var pieces := PackedStringArray()
	pieces.append(String(plan.get("policy", "")).to_upper())
	var advantages: Array = offer.get("advantages", []) as Array
	for raw_advantage in advantages:
		match String(raw_advantage):
			"fastest":
				pieces.append("FASTEST")
			"most_supply":
				pieces.append("LOWEST SUPPLY USE")
			"least_wear":
				pieces.append("LEAST WEAR")
	if String(projection.get("status", "")) == "blocked":
		var reason := String(projection.get("reason", "unreachable"))
		if reason == "season_closed":
			pieces = PackedStringArray(["WINTER CLOSED AT RIDGE PASS"])
		elif reason == "resource_shortfall":
			pieces = PackedStringArray([_shortfall_copy(plan)])
		else:
			pieces = PackedStringArray(["ROAD NETWORK UNREACHABLE"])
	return "  /  ".join(pieces)


func _shortfall_copy(plan: Dictionary) -> String:
	var totals: Dictionary = plan.get("totals", {}) as Dictionary
	var supply_short := _supplies_milli < int(totals.get("supply_milli", 0))
	var rig_short := _condition_milli < int(totals.get("condition_milli", 0))
	if supply_short and rig_short:
		return "SUPPLY + RIG SHORT"
	if rig_short:
		return "RIG SHORT"
	return "SUPPLY SHORT"


func _draw_selected_detail() -> void:
	var detail_rect := Rect2(880.0, 555.0, 360.0, 107.0)
	draw_rect(detail_rect, Color("#171914"))
	draw_rect(Rect2(detail_rect.position, Vector2(5.0, detail_rect.size.y)), _phase_color())
	if _journey.is_empty():
		var detail_title := "WHY THIS ROUTE"
		var decision := String(_board.get("decision_status", "no_plan"))
		if decision == "fallback_only":
			detail_title = "WHY THIS FALLBACK"
		elif decision == "no_plan":
			detail_title = "WHY NO PLAN"
		_text(detail_title, Vector2(894.0, 577.0), 10, C_MUTED)
		var detail_copy := _selected_detail_copy()
		_wrapped(detail_copy, Vector2(894.0, 598.0), 332.0, 10, C_TEXT, 2)
		_primary_rect = Rect2(892.0, 623.0, 336.0, 35.0)
		_fallback_rect = Rect2()
		_button(_primary_rect, _primary_label(), _primary_enabled(), _primary_color())
	else:
		_text("JOURNEY STATE", Vector2(894.0, 577.0), 10, C_MUTED)
		var state_copy := "SUPPLY %s  /  RIG %s  /  ELAPSED %s" % [
			_format_milli(int(_journey.get("supplies_milli", 0))),
			_format_milli(int(_journey.get("condition_milli", 0))),
			_format_minutes(int(_journey.get("elapsed_minutes", 0)))
		]
		_text(state_copy, Vector2(894.0, 601.0), 11, C_TEXT, 332.0)
		_primary_rect = Rect2(892.0, 623.0, 228.0, 35.0)
		_fallback_rect = Rect2(1128.0, 623.0, 100.0, 35.0)
		_button(_primary_rect, _primary_label(), _primary_enabled(), _primary_color())
		_button(_fallback_rect, "F  DIVERT", _can_divert(), C_TEAL)


func _selected_detail_copy() -> String:
	var decision := String(_board.get("decision_status", "no_plan"))
	if decision == "fallback_only":
		var fallback_offer: Dictionary = _board.get("fallback_offer", {}) as Dictionary
		var plan: Dictionary = fallback_offer.get("plan", {}) as Dictionary
		var projection: Dictionary = fallback_offer.get("projection", {}) as Dictionary
		return "FALLBACK READY: %s / ARRIVE %s / minimum reserve 0.500." % [
			_label_for_id(String(plan.get("destination", ""))),
			_format_milli(int(projection.get("arrival_supply_milli", 0)))
		]
	if decision == "no_plan":
		return "No destination or fallback route meets its reserve gate. Add supply or repair the rig."
	var offer := _selected_offer()
	return String(offer.get("promise", "Choose a route whose arrival reserve survives the road."))


func _primary_label() -> String:
	if not _journey.is_empty():
		var phase := String(_journey.get("phase", ""))
		if phase == "traveling":
			return "ENTER / SPACE  ADVANCE ONE LEG"
		if phase == "arrived":
			return "ARRIVED  /  R RESET"
		return "STRANDED  /  R RESET"
	var decision := String(_board.get("decision_status", "no_plan"))
	if decision == "fallback_only":
		var fallback_offer: Dictionary = _board.get("fallback_offer", {}) as Dictionary
		var plan: Dictionary = fallback_offer.get("plan", {}) as Dictionary
		return "ENTER / SPACE  TAKE F/B -> " + _label_for_id(String(plan.get("destination", "")))
	if decision == "no_plan":
		return "NO ROUTE CAN START"
	var projection: Dictionary = _selected_offer().get("projection", {}) as Dictionary
	var status := String(projection.get("status", "blocked"))
	if status == "safe":
		return "ENTER / SPACE  BEGIN SAFE ROUTE"
	if status == "tight":
		return "ENTER / SPACE  BEGIN TIGHT ROUTE"
	return "ROUTE BLOCKED"


func _primary_enabled() -> bool:
	if not _journey.is_empty():
		return String(_journey.get("phase", "")) == "traveling"
	var decision := String(_board.get("decision_status", "no_plan"))
	if decision == "fallback_only":
		return not (_board.get("fallback_offer", {}) as Dictionary).is_empty()
	if decision == "no_plan":
		return false
	var projection: Dictionary = _selected_offer().get("projection", {}) as Dictionary
	return bool(projection.get("reachable", false))


func _primary_color() -> Color:
	if not _journey.is_empty():
		return C_TEAL if _active_is_fallback else C_GOLD
	var decision := String(_board.get("decision_status", "no_plan"))
	if decision == "fallback_only":
		return C_TEAL
	var projection: Dictionary = _selected_offer().get("projection", {}) as Dictionary
	return _status_color(String(projection.get("status", "blocked")))


func _button(button_rect: Rect2, copy: String, enabled: bool, accent: Color) -> void:
	var hovered := enabled and button_rect.has_point(_mouse)
	var fill := Color("#34352c") if enabled else Color("#272923")
	if hovered:
		fill = Color("#414237")
	draw_rect(Rect2(button_rect.position + Vector2(3.0, 4.0), button_rect.size), Color(0.0, 0.0, 0.0, 0.34))
	draw_rect(button_rect, fill)
	draw_rect(button_rect, C_EDGE, false, 1.0)
	draw_rect(Rect2(button_rect.position, Vector2(5.0, button_rect.size.y)), accent if enabled else C_EDGE)
	_text(copy, button_rect.position + Vector2(12.0, 23.0), 11, C_TEXT if enabled else C_MUTED,
		button_rect.size.x - 24.0, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_fixture_footer() -> void:
	draw_rect(Rect2(0.0, 704.0, 1280.0, 64.0), C_HEADER)
	draw_line(Vector2(0.0, 704.0), Vector2(1280.0, 704.0), C_EDGE, 1.0)
	_text("LAB FIXTURE", Vector2(24.0, 741.0), 11, C_MUTED)
	_fixture_rects.clear()
	for i in range(FIXTURE_LABELS.size()):
		var tab_rect := Rect2(166.0 + float(i) * 166.0, 719.0, 154.0, 33.0)
		_fixture_rects.append(tab_rect)
		var selected := i == _fixture_index
		var fill := Color("#35362d") if selected else Color("#22241e")
		if tab_rect.has_point(_mouse) and not selected:
			fill = Color("#292b24")
		draw_rect(tab_rect, fill)
		draw_rect(tab_rect, C_GOLD if selected else C_EDGE, false, 1.0)
		_text(String(FIXTURE_LABELS[i]), tab_rect.position + Vector2(12.0, 22.0), 11,
			C_TEXT if selected else C_MUTED, tab_rect.size.x - 24.0, HORIZONTAL_ALIGNMENT_CENTER)
	_text("1-3 ROUTE / ENTER STEP / F DIVERT / R RESET", Vector2(998.0, 741.0), 10, C_MUTED, 258.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _selected_offer() -> Dictionary:
	var offers: Array = _board.get("offers", []) as Array
	if _selected_route < 0 or _selected_route >= offers.size():
		return {}
	return offers[_selected_route] as Dictionary


func _selected_fallback_id() -> String:
	var fallback_offer: Dictionary = _board.get("fallback_offer", {}) as Dictionary
	if not fallback_offer.is_empty():
		var fallback_plan: Dictionary = fallback_offer.get("plan", {}) as Dictionary
		return String(fallback_plan.get("destination", ""))
	var plan: Dictionary = _selected_offer().get("plan", {}) as Dictionary
	return String(plan.get("fallback", ""))


func _label_for_id(tile_id: String) -> String:
	if tile_id == "" or not _tile_by_id.has(tile_id):
		return "UNKNOWN"
	var tile: Dictionary = _tile_by_id[tile_id] as Dictionary
	var label := String(tile.get("label", ""))
	if label != "":
		return label
	return "TILE %d,%d" % [int(tile.get("q", 0)), int(tile.get("r", 0))]


func _status_color(status: String) -> Color:
	if status == "safe":
		return C_GOOD
	if status == "tight":
		return C_TIGHT
	return C_DANGER


func _phase_color() -> Color:
	if not _journey.is_empty():
		var phase := String(_journey.get("phase", ""))
		if phase == "arrived":
			return C_GOOD
		if phase == "stranded":
			return C_DANGER
		return C_TEAL if _active_is_fallback else C_GOLD
	var decision := String(_board.get("decision_status", "no_plan"))
	if decision == "routes_available":
		return C_GOOD
	if decision == "fallback_only":
		return C_TEAL
	return C_DANGER


func _display_supply() -> int:
	return int(_journey.get("supplies_milli", _supplies_milli)) if not _journey.is_empty() else _supplies_milli


func _display_condition() -> int:
	return int(_journey.get("condition_milli", _condition_milli)) if not _journey.is_empty() else _condition_milli


func _format_milli(value: int) -> String:
	var whole := floori(float(value) / 1000.0)
	var fraction := absi(value % 1000)
	return "%d.%03d" % [whole, fraction]


func _format_minutes(minutes: int) -> String:
	return "%02d:%02d" % [floori(float(minutes) / 60.0), minutes % 60]


func _stranded_copy() -> String:
	if _last_leg_result == "insufficient_supply":
		return "STRANDED  /  SUPPLY EXHAUSTED"
	if _last_leg_result == "insufficient_condition":
		return "STRANDED  /  RIG FAILED"
	return "STRANDED  /  RESERVE EXHAUSTED"


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


func _begin_primary() -> void:
	if not _journey.is_empty() or _board.is_empty():
		return
	var plan: Dictionary = {}
	var decision := String(_board.get("decision_status", "no_plan"))
	if decision == "fallback_only":
		var fallback_offer: Dictionary = _board.get("fallback_offer", {}) as Dictionary
		plan = fallback_offer.get("plan", {}) as Dictionary
		_active_is_fallback = true
	elif decision == "routes_available":
		var offer := _selected_offer()
		var projection: Dictionary = offer.get("projection", {}) as Dictionary
		if not bool(projection.get("reachable", false)):
			return
		plan = offer.get("plan", {}) as Dictionary
		_active_is_fallback = false
	else:
		return
	if plan.is_empty():
		return
	var created: Dictionary = RegionRouteModel.begin_journey(
		_atlas, _atlas_state, plan, "region_lab", _supplies_milli, _condition_milli
	)
	if created.is_empty():
		push_error("RegionRouteLab could not begin the selected journey")
		return
	_active_plan = plan
	_journey = created
	_refresh_diversion_preview()
	queue_redraw()


func _advance_leg() -> void:
	if _journey.is_empty() or String(_journey.get("phase", "")) != "traveling":
		return
	var transition: Dictionary = RegionRouteModel.advance_one_leg(
		_atlas, _atlas_state, _active_plan, _journey
	)
	if transition.is_empty():
		push_error("RegionRouteLab could not settle the next route leg")
		return
	var leg_receipt: Dictionary = transition.get("leg_receipt", {}) as Dictionary
	_last_leg_result = String(leg_receipt.get("result", ""))
	_journey = transition.get("journey", {}) as Dictionary
	_atlas_state = transition.get("atlas_state", {}) as Dictionary
	_refresh_diversion_preview()
	queue_redraw()


func _can_divert() -> bool:
	return not _diversion_preview.is_empty()


func _refresh_diversion_preview() -> void:
	_diversion_preview = {}
	if _journey.is_empty() or String(_journey.get("phase", "")) != "traveling" \
			or String(_active_plan.get("fallback", "")) == "":
		return
	_diversion_preview = RegionRouteModel.divert_to_fallback(
		_atlas, _atlas_state, _active_plan, _journey
	)


func _divert() -> void:
	if not _can_divert():
		return
	var transition: Dictionary = _diversion_preview
	if transition.is_empty():
		push_error("RegionRouteLab could not divert the active journey")
		return
	_active_plan = transition.get("child_plan", {}) as Dictionary
	_journey = transition.get("journey", {}) as Dictionary
	_atlas_state = transition.get("atlas_state", {}) as Dictionary
	_active_is_fallback = true
	_last_leg_result = "diverted"
	_refresh_diversion_preview()
	queue_redraw()


func _activate_primary() -> void:
	if not _primary_enabled():
		return
	if _journey.is_empty():
		_begin_primary()
	else:
		_advance_leg()


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
		KEY_1, KEY_2, KEY_3:
			if _journey.is_empty():
				_selected_route = int(key_event.keycode) - int(KEY_1)
				queue_redraw()
		KEY_A, KEY_B, KEY_C, KEY_D, KEY_E:
			_apply_fixture(int(key_event.keycode) - int(KEY_A))
		KEY_ENTER, KEY_SPACE:
			_activate_primary()
		KEY_F:
			_divert()
		KEY_R:
			_apply_fixture(_fixture_index)


func _handle_click(click_position: Vector2) -> void:
	if _journey.is_empty():
		for i in range(_route_rects.size()):
			if _route_rects[i].has_point(click_position):
				_selected_route = i
				queue_redraw()
				return
	for i in range(_fixture_rects.size()):
		if _fixture_rects[i].has_point(click_position):
			_apply_fixture(i)
			return
	if _primary_rect.has_point(click_position):
		_activate_primary()
	elif _fallback_rect.has_point(click_position):
		_divert()


func _save_shot() -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("RegionRouteLab could not capture the viewport")
		get_tree().quit(1)
		return
	var save_error := image.save_png(_shot_path)
	if save_error != OK:
		push_error("RegionRouteLab could not save screenshot: %s" % error_string(save_error))
		get_tree().quit(1)
		return
	get_tree().quit()
