extends Node2D
## Read-only preview of a frozen coastal package. No access to Sim or live town state.

const PACKAGE_PATH := "res://coastal/warm_bay_s1/export/package.json"
const TILE := 48.0
const GRASS := Color("#78933f")
const DUNE := Color("#c8ae78")
const SAND := Color("#d7bd8b")
const WET_SAND := Color("#9eaa92")
const SEA := Color("#2e8b96")
const ROAD := Color("#a8916c")
const ROAD_EDGE := Color("#766b55")
const OUTLINE := Color("#343b32")
const MODULE_IMPORTER := preload("res://scripts/CoastalModuleKitImporter.gd")
const PACKAGE_COMPILER := preload("res://scripts/CoastalPackageCompiler.gd")
const MODULE_KIT_PATH := "res://coastal/kit"

var package: Dictionary = {}
var topology: Dictionary = {}
var render_data: Dictionary = {}
var preview_camera: Camera2D
var title_label: Label
var module_kit: Dictionary = {}
var kit_status := "procedural roof preview"
var show_floorplans := false
var _style_colors := {
	"D1_sheltered_living": Color("#b89365"),
	"D2_civic_frontage": Color("#9ca9aa"),
	"D3_working_yards": Color("#827b6c"),
	"D4_beach_approach": Color("#b6a273")
}


func _ready() -> void:
	var file := FileAccess.open(PACKAGE_PATH, FileAccess.READ)
	if file == null:
		push_error("Coastal preview package is missing. Run CoastalBuildCLI.gd first.")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var validation: Dictionary = PACKAGE_COMPILER.validate_package(parsed)
	if not bool(validation.get("ok", false)):
		push_error("Coastal preview package failed integrity checks: %s" % "; ".join(validation.get("errors", [])))
		return
	package = parsed
	topology = package.get("topology", {})
	render_data = package.get("render", {})
	var kit_result: Dictionary = MODULE_IMPORTER.load_bundle(MODULE_KIT_PATH)
	if bool(kit_result.get("ok", false)):
		module_kit = kit_result
		kit_status = "%d Blender modules" % module_kit["modules"].size()
	else:
		kit_status = "procedural placeholder · Blender kit not exported"
	var extent: Array = topology.get("extent_cells", [128, 128])
	preview_camera = Camera2D.new()
	add_child(preview_camera)
	preview_camera.make_current()
	get_viewport().size_changed.connect(_fit_camera)
	_fit_camera()
	var overlay_layer := CanvasLayer.new()
	add_child(overlay_layer)
	title_label = Label.new()
	title_label.position = Vector2(22, 16)
	title_label.add_theme_color_override("font_color", Color("#f4e8cc"))
	title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	title_label.add_theme_constant_override("shadow_offset_x", 2)
	title_label.add_theme_constant_override("shadow_offset_y", 2)
	overlay_layer.add_child(title_label)
	_refresh_title()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		show_floorplans = not show_floorplans
		_refresh_title()
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and preview_camera != null:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			var zoom_in := clampf(preview_camera.zoom.x * 1.12, 0.04, 0.8)
			preview_camera.zoom = Vector2.ONE * zoom_in
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var zoom_out := clampf(preview_camera.zoom.x / 1.12, 0.04, 0.8)
			preview_camera.zoom = Vector2.ONE * zoom_out
			get_viewport().set_input_as_handled()


func _fit_camera() -> void:
	if preview_camera == null or topology.is_empty():
		return
	var extent: Array = topology.get("extent_cells", [128, 128])
	var world_size := Vector2(float(extent[0]), float(extent[1])) * TILE
	var view_size := get_viewport_rect().size
	var fit := minf(view_size.x / world_size.x, view_size.y / world_size.y) * 0.86
	preview_camera.position = world_size * 0.5
	preview_camera.zoom = Vector2(fit, fit)


func _refresh_title() -> void:
	if title_label == null:
		return
	var view_mode := "room/slot overlay ON" if show_floorplans else "F2 room/slot overlay"
	title_label.text = "Warm Bay S1  ·  F0 frozen coast  ·  %d buildings  ·  %d road edges\n%s  ·  %s  ·  wheel zoom" % [topology.get("buildings", []).size(), topology.get("roads", []).size(), kit_status, view_mode]


func _draw() -> void:
	if topology.is_empty():
		return
	var extent: Array = topology.get("extent_cells", [128, 128])
	var width := int(extent[0])
	var height := int(extent[1])
	draw_rect(Rect2(0, 0, width * TILE, height * TILE), GRASS)
	_draw_coast(height)
	_draw_ground_detail(width, height)
	_draw_vegetation(width, height)
	_draw_access_paths()
	_draw_roads()
	_draw_buildings()


func _draw_coast(height: int) -> void:
	var shore: Dictionary = topology.get("shoreline", {})
	var controls: Array = shore.get("bands", [])
	var offsets: Dictionary = shore.get("offsets_cells", {})
	var toe := float(offsets.get("dune_toe", 7))
	var high_water := float(offsets.get("high_water", 16))
	var outer := float(offsets.get("outer_intertidal", 22))
	var width := int(topology.get("extent_cells", [128, height])[0])
	for z in range(height):
		var edge := _shore_x(float(z) + 0.5, controls)
		var row_y := float(z) * TILE
		draw_rect(Rect2(edge * TILE, row_y, toe * TILE, TILE), DUNE)
		draw_rect(Rect2((edge + toe) * TILE, row_y, (high_water - toe) * TILE, TILE), SAND)
		draw_rect(Rect2((edge + high_water) * TILE, row_y, (outer - high_water) * TILE, TILE), WET_SAND)
		draw_rect(Rect2((edge + outer) * TILE, row_y, maxf(0.0, float(width) - edge - outer) * TILE, TILE), SEA)
		var phase := float(z) * 0.73
		var foam_x := (edge + high_water - 0.9 + sin(phase) * 0.22) * TILE
		draw_line(Vector2(foam_x, row_y + 5.0), Vector2(foam_x, row_y + TILE - 5.0), Color("#d7e4d2", 0.64), 3.0, true)


func _shore_x(z: float, controls: Array) -> float:
	if controls.is_empty():
		return 94.0
	for i in range(controls.size() - 1):
		var a: Dictionary = controls[i]
		var b: Dictionary = controls[i + 1]
		var az := float(a["z"])
		var bz := float(b["z"])
		if z <= bz:
			var t := inverse_lerp(az, bz, z)
			return lerpf(float(a["dune_edge_x"]), float(b["dune_edge_x"]), t)
	return float(controls[-1]["dune_edge_x"])


func _draw_roads() -> void:
	var nodes: Dictionary = {}
	for node: Dictionary in topology.get("road_nodes", []):
		nodes[str(node["id"])] = Vector2(node["at"][0], node["at"][1])
	for road: Dictionary in topology.get("roads", []):
		var points: Array = road.get("via", [nodes[str(road["from"])], nodes[str(road["to"])]] )
		if not road.has("via"):
			points = [nodes[str(road["from"])], nodes[str(road["to"])]]
		var pixel_points := PackedVector2Array()
		for point: Variant in points:
			pixel_points.append((Vector2(point[0], point[1]) + Vector2(0.5, 0.5)) * TILE)
		var road_width := float(road.get("width_cells", 4)) * TILE
		draw_polyline(pixel_points, ROAD_EDGE, road_width + 5.0, true)
		draw_polyline(pixel_points, ROAD, road_width, true)
		if str(road.get("class", "")) == "beach_crossing":
			for i in range(1, pixel_points.size() - 1):
				draw_line(pixel_points[i] + Vector2(0, -road_width * 0.28), pixel_points[i] + Vector2(0, road_width * 0.28), Color("#6f6045"), 3.0, true)


func _draw_access_paths() -> void:
	for building: Dictionary in topology.get("buildings", []):
		var entry: Dictionary = building.get("entry", {})
		var path: Array = entry.get("access_path", [])
		if path.size() < 2:
			continue
		var pixel_points := PackedVector2Array()
		for point: Variant in path:
			pixel_points.append(Vector2(float(point[0]), float(point[1])) * TILE)
		var path_width := float(entry.get("access_width_cells", 1.5)) * TILE
		draw_polyline(pixel_points, Color("#71684f"), path_width + 4.0, true)
		draw_polyline(pixel_points, Color("#c3ad7d"), path_width, true)
		for i in range(1, pixel_points.size() - 1):
			draw_line(pixel_points[i] + Vector2(-2, -path_width * 0.32), pixel_points[i] + Vector2(2, path_width * 0.32), Color("#8d7b5a", 0.7), 2.0, true)


func _draw_ground_detail(width: int, height: int) -> void:
	for y in range(3, height, 5):
		for x in range(3, width, 5):
			var phase := sin(float(x * 127 + y * 311) * 0.071)
			if phase > 0.42 and not _near_road(Vector2(x + 0.5, y + 0.5), 1.0) and not _near_building(Vector2(x + 0.5, y + 0.5), 0.7):
				var tint := Color("#a2b55a", 0.22) if phase > 0.82 else Color("#d1bd79", 0.13)
				draw_circle(Vector2((x + 0.5) * TILE, (y + 0.5) * TILE), 4.5 if phase > 0.82 else 2.5, tint)


func _draw_vegetation(width: int, height: int) -> void:
	for y in range(7, height - 4, 7):
		for x in range(6, width - 18, 7):
			var variation := sin(float(x * 193 + y * 71) * 0.037 + float(render_data.get("visual_seed", 0)) * 0.011)
			if variation < 0.28 or _near_road(Vector2(x, y), 2.6) or _near_building(Vector2(x, y), 2.0):
				continue
			_draw_tree(Vector2((x + 0.5) * TILE, (y + 0.5) * TILE), 0.72 + (variation - 0.28) * 0.45, x + y)
	# A low dune-grass belt visually follows the authored physical boundary.
	var shore: Dictionary = topology.get("shoreline", {})
	var controls: Array = shore.get("bands", [])
	for z in range(2, height, 3):
		var edge := _shore_x(float(z), controls)
		for tuft in range(3):
			var px := (edge + 2.0 + float(tuft) * 1.45 + sin(float(z * 29 + tuft * 7)) * 0.55) * TILE
			var py := (float(z) + sin(float(z * 11 + tuft)) * 0.36) * TILE
			_draw_grass_tuft(Vector2(px, py), 0.42 + float(tuft) * 0.07)


func _draw_tree(center: Vector2, scale: float, seed_value: int) -> void:
	var radius := TILE * scale
	_draw_ellipse(center + Vector2(8, 12), Vector2(radius * 1.1, radius * 0.65), Color(0.17, 0.20, 0.14, 0.30))
	draw_circle(center + Vector2(2, 4), radius * 0.19, Color("#6e5234"))
	var greens := [Color("#476a35"), Color("#54783a"), Color("#658543")]
	var canopy: Color = greens[posmod(seed_value, greens.size())]
	draw_circle(center - Vector2(radius * 0.10, radius * 0.17), radius, OUTLINE)
	draw_circle(center - Vector2(radius * 0.10, radius * 0.17), radius * 0.90, canopy)
	draw_circle(center - Vector2(radius * 0.30, radius * 0.40), radius * 0.30, Color("#8ba654", 0.80))
	_draw_ellipse(center + Vector2(radius * 0.38, radius * 0.34), Vector2(radius * 0.33, radius * 0.21), Color("#394f2c", 0.7))


func _draw_grass_tuft(center: Vector2, scale: float) -> void:
	var color := Color("#748849", 0.9)
	for blade in range(3):
		var offset := Vector2(float(blade - 1) * 4.5, 0)
		draw_line(center + offset + Vector2(0, 6), center + offset + Vector2(float(blade - 1) * 6.0, -12.0 * scale), color, 3.0, true)


func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(12):
		var angle := TAU * float(index) / 12.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)


func _near_road(point: Vector2, margin: float) -> bool:
	var nodes: Dictionary = {}
	for node: Dictionary in topology.get("road_nodes", []):
		nodes[str(node["id"])] = Vector2(float(node["at"][0]), float(node["at"][1]))
	for road: Dictionary in topology.get("roads", []):
		var points := _road_cell_points(road, nodes)
		for i in range(points.size() - 1):
			if _distance_to_segment(point, points[i], points[i + 1]) <= float(road.get("width_cells", 0)) * 0.5 + margin:
				return true
	return false


func _near_building(point: Vector2, margin: float) -> bool:
	for building: Dictionary in topology.get("buildings", []):
		for segment: Dictionary in building.get("segments", []):
			var rect: Array = segment["rect"]
			if point.x >= float(rect[0]) - margin and point.x <= float(rect[0] + rect[2]) + margin and point.y >= float(rect[1]) - margin and point.y <= float(rect[1] + rect[3]) + margin:
				return true
	return false


func _road_cell_points(road: Dictionary, nodes: Dictionary) -> PackedVector2Array:
	var values: Array = road.get("via", [])
	if values.is_empty():
		values = [nodes[str(road["from"])], nodes[str(road["to"])]]
	var result := PackedVector2Array()
	for value: Variant in values:
		result.append(Vector2(float(value[0]), float(value[1])))
	return result


func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var delta := b - a
	var denominator := delta.length_squared()
	var t := 0.0 if denominator <= 0.0 else clampf((point - a).dot(delta) / denominator, 0.0, 1.0)
	return point.distance_to(a + delta * t)


func _draw_buildings() -> void:
	var appearances: Dictionary = render_data.get("building_appearance", {})
	for building: Dictionary in topology.get("buildings", []):
		var color: Color = _style_colors.get(str(building.get("district", "")), Color("#a38a63"))
		var appearance: Dictionary = appearances.get(str(building.get("id", "")), {})
		var visual_segments := {}
		for visual_segment: Dictionary in appearance.get("segments", []):
			visual_segments[str(visual_segment.get("id", ""))] = visual_segment
		for segment: Dictionary in building.get("segments", []):
			var rect: Array = segment["rect"]
			var pixel_rect := Rect2(float(rect[0]) * TILE, float(rect[1]) * TILE, float(rect[2]) * TILE, float(rect[3]) * TILE)
			draw_rect(Rect2(pixel_rect.position + Vector2(9, 11), pixel_rect.size), Color(0.12, 0.15, 0.13, 0.27))
			var roof_color := color.lightened(0.08) if str(segment.get("id", "")) in ["main", "roof"] else color.darkened(0.08)
			var visual: Dictionary = visual_segments.get(str(segment.get("id", "")), {})
			var drawn_module := _draw_module(str(visual.get("module_id", "")), pixel_rect, int(visual.get("rotation", 0)), roof_color)
			if not drawn_module:
				draw_rect(pixel_rect, roof_color)
			draw_rect(pixel_rect, OUTLINE, false, 5.0, true)
			if str(building.get("shape", "")) != "open" and not drawn_module:
				_draw_roof_detail(pixel_rect, str(building.get("district", "")), str(building.get("type", "")))
			else:
				for post_x in [pixel_rect.position.x + 10, pixel_rect.end.x - 10]:
					for post_y in [pixel_rect.position.y + 10, pixel_rect.end.y - 10]:
						draw_circle(Vector2(post_x, post_y), 6.0, Color("#65553d"))
		_draw_entry(building)
		if show_floorplans:
			_draw_floorplan(building)


func _draw_floorplan(building: Dictionary) -> void:
	var building_box: Array = building.get("box", [0, 0, 0, 0])
	var origin := Vector2(float(building_box[0]), float(building_box[1]))
	var interior: Dictionary = building.get("interior", {})
	var room_colors := {
		"public": Color("#b9d8bd", 0.92),
		"authorized": Color("#d7c8a2", 0.92),
		"court": Color("#82bcb2", 0.92)
	}
	for room: Dictionary in interior.get("rooms", []):
		var bounds: Array = room.get("bounds_q", [0, 0, 0, 0])
		var room_rect := Rect2(
			(origin + Vector2(float(bounds[0]), float(bounds[1])) / 48.0) * TILE,
			Vector2(float(bounds[2]), float(bounds[3])) / 48.0 * TILE)
		var role := "court" if str(room.get("kind", "")) == "court" else str(room.get("access_policy", "public"))
		draw_rect(room_rect, room_colors.get(role, Color("#bec4bb", 0.9)))
		draw_rect(room_rect, Color("#45534b"), false, 3.0, true)
	for door: Dictionary in interior.get("doors", []):
		var point: Array = door.get("at_q", [0, 0])
		var position := (origin + Vector2(float(point[0]), float(point[1])) / 48.0) * TILE
		draw_circle(position, 7.0, Color("#e0f2c5"))
	for slot: Dictionary in interior.get("slots", []):
		var point: Array = slot.get("approach_q", [0, 0])
		var position := (origin + Vector2(float(point[0]), float(point[1])) / 48.0) * TILE
		draw_circle(position, 8.0, Color("#d96855"))
	var entry_anchor: Array = interior.get("entry_at_q", [])
	if entry_anchor.size() == 2:
		var entry_position := (origin + Vector2(float(entry_anchor[0]), float(entry_anchor[1])) / 48.0) * TILE
		draw_circle(entry_position, 10.0, Color("#73c97c"))


func _draw_module(module_id: String, target: Rect2, rotation: int, fallback: Color) -> bool:
	if module_id.is_empty() or module_kit.is_empty() or not module_kit["modules"].has(module_id):
		return false
	var module: Dictionary = module_kit["modules"][module_id]
	var dimensions: Array = module["dimensions_q"]
	var minimum: Array = module.get("bounds_min_q", [0, 0])
	var source_width_q := float(dimensions[0])
	var source_height_q := float(dimensions[1])
	var width_q := source_width_q
	var height_q := source_height_q
	if rotation % 2 == 1:
		var swap := width_q
		width_q = height_q
		height_q = swap
	var scale := Vector2(target.size.x / width_q, target.size.y / height_q)
	var palette := {
		"roof/limewash_clay": Color("#b89365"),
		"roof/civic_slate": Color("#91a4a9"),
		"roof/workshop_seam": Color("#777c7e"),
		"roof/beach_canopy": Color("#c7b17c"),
		"wall_base": Color("#d1c5a8"),
		"roof": fallback,
		"trim": Color("#e3d6b8"),
		"wood": Color("#8c6544"),
		"shadow": Color("#343b32")
	}
	var module_palette_id := str(module.get("palette_id", ""))
	var module_fill: Color = palette.get(module_palette_id, fallback)
	for polygon: Dictionary in module.get("polygons", []):
		var points := PackedVector2Array()
		for point: Array in polygon.get("points_q", []):
			var local := Vector2(float(point[0]) - float(minimum[0]), float(point[1]) - float(minimum[1]))
			match posmod(rotation, 4):
				1: local = Vector2(source_height_q - local.y, local.x)
				2: local = Vector2(source_width_q - local.x, source_height_q - local.y)
				3: local = Vector2(local.y, source_width_q - local.x)
			points.append(target.position + Vector2(local.x * scale.x, local.y * scale.y))
		if points.size() >= 3:
			var polygon_palette_id := str(polygon.get("palette_id", module_palette_id))
			var polygon_fill: Color = palette.get(polygon_palette_id, module_fill)
			draw_colored_polygon(points, polygon_fill)
	return true


func _draw_roof_detail(rect: Rect2, district: String, building_type: String) -> void:
	var detail_color := Color("#5e5548", 0.58)
	if district == "D3_working_yards":
		for x in range(18, int(rect.size.x), 18):
			draw_line(Vector2(rect.position.x + x, rect.position.y + 6), Vector2(rect.position.x + x, rect.end.y - 6), detail_color, 2.0, true)
	else:
		for y in range(16, int(rect.size.y), 20):
			draw_line(Vector2(rect.position.x + 6, rect.position.y + y), Vector2(rect.end.x - 6, rect.position.y + y), detail_color, 2.0, true)
	var ridge_y := rect.position.y + rect.size.y * 0.45
	draw_line(Vector2(rect.position.x + 12, ridge_y), Vector2(rect.end.x - 12, ridge_y), Color("#524b40"), 5.0, true)
	if building_type in ["veranda_home", "courtyard_home", "promenade_cafe", "community_room"]:
		for x in range(24, int(rect.size.x) - 12, 32):
			draw_rect(Rect2(rect.position.x + x, rect.position.y + 8, 12, 6), Color("#d4c39e"))


func _draw_entry(building: Dictionary) -> void:
	var entry: Dictionary = building.get("entry", {})
	var at: Array = entry.get("at", [0, 0])
	var center := Vector2((float(at[0]) + 0.5) * TILE, (float(at[1]) + 0.5) * TILE)
	var door_size := Vector2(14, 22)
	match str(entry.get("facing", "south")):
		"north": center.y -= TILE * 0.5
		"south": center.y += TILE * 0.5
		"east": center.x += TILE * 0.5
		"west": center.x -= TILE * 0.5
	draw_rect(Rect2(center - door_size * 0.5, door_size), Color("#544735"))
	var step_size := Vector2(38, 13) if str(entry.get("facing", "south")) in ["north", "south"] else Vector2(13, 38)
	var step_center := center
	match str(entry.get("facing", "south")):
		"north": step_center.y -= 13
		"south": step_center.y += 13
		"east": step_center.x += 13
		"west": step_center.x -= 13
	draw_rect(Rect2(step_center - step_size * 0.5, step_size), Color("#d4c393"))
