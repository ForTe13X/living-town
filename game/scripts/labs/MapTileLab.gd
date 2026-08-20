extends Node2D

const ModelScript = preload("res://scripts/labs/MapTileLabModel.gd")

const DESIGN := Vector2(1280.0, 768.0)
const HEX_R := 50.0
const HEX_ORIGIN := Vector2(78.0, 118.0)
const HEX_X := HEX_R * 1.5
const HEX_Y := HEX_R * 1.7320508
const LOCAL_ORIGIN := Vector2(34.0, 91.0)
const LOCAL_CELL := 27.0
const SIDE_X := 920.0

const C_BG := Color("#11140f")
const C_BG_2 := Color("#171a14")
const C_PANEL := Color("#1c1e19")
const C_PANEL_2 := Color("#24251f")
const C_EDGE := Color("#555746")
const C_EDGE_HI := Color("#89866d")
const C_TEXT := Color("#ded8c4")
const C_MUTED := Color("#8f917f")
const C_ACCENT := Color("#d2a85c")
const C_ACCENT_2 := Color("#78a999")
const C_DANGER := Color("#c45b50")
const C_GOOD := Color("#8fb56d")

const BIOME_COLORS := {
	"pine": Color("#4d674b"),
	"steppe": Color("#80805a"),
	"scrub": Color("#6f6846"),
	"marsh": Color("#496765"),
	"highland": Color("#726f67"),
	"ash": Color("#675b55"),
}
const BIOME_LABELS := {
	"pine": "PINE BELT",
	"steppe": "DRY STEPPE",
	"scrub": "THORN SCRUB",
	"marsh": "BLACK MARSH",
	"highland": "HIGHLAND",
	"ash": "ASH WASTE",
}

var model
var _font: Font
var _hover_world := Vector2i(-1, -1)
var _hover_local := Vector2i(-1, -1)
var _pulse := 0.0
var _shot_path := ""
var _mouse := Vector2.ZERO
var _world_action_rect := Rect2(SIDE_X + 22.0, 596.0, 316.0, 48.0)
var _local_action_rect := Rect2(SIDE_X + 22.0, 569.0, 151.0, 42.0)
var _local_attack_rect := Rect2(SIDE_X + 187.0, 569.0, 151.0, 42.0)
var _local_extract_rect := Rect2(SIDE_X + 22.0, 623.0, 316.0, 42.0)


func _ready() -> void:
	_font = Art.font()
	var lab_seed := 260814
	var start_local := false
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--lab-seed" and i + 1 < args.size():
			lab_seed = int(args[i + 1])
		elif args[i] == "--lab-local":
			start_local = true
		elif args[i] == "--lab-shot" and i + 1 < args.size():
			_shot_path = args[i + 1]
	model = ModelScript.new(lab_seed)
	if start_local:
		model.caravan_tile = Vector2i(7, 2)
		model.selected_tile = model.caravan_tile
		model.plan_route(model.caravan_tile)
		model.enter_local()
		# The screenshot/demo starts one step inside: one shell is cut away while
		# the other roofs still explain the exploration rule at a glance.
		model.player = Vector2i(8, 8)
		model._reveal_current_building()
	set_process(true)
	queue_redraw()
	if _shot_path != "":
		get_tree().create_timer(0.8).timeout.connect(_save_shot)


func _process(delta: float) -> void:
	# Product play animates. Evidence frames deliberately do not: a wall-clock
	# pulse would make the same seed produce a different PNG depending on which
	# render frame happened to meet the 0.8 s timer.
	if _shot_path == "":
		_pulse = fmod(_pulse + delta, 1000.0)
		if model != null and model.mode == ModelScript.Mode.WORLD:
			model.tick_travel(delta)
		queue_redraw()


func _save_shot() -> void:
	var image := get_viewport().get_texture().get_image()
	if image != null:
		image.save_png(_shot_path)
	get_tree().quit()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, DESIGN), C_BG)
	_draw_noise_field()
	if model.mode == ModelScript.Mode.WORLD:
		_draw_world()
	else:
		_draw_local()


func _draw_noise_field() -> void:
	for i in 38:
		var x := float((i * 149 + model.seed * 3) % 1280)
		var y := float((i * 83 + model.seed * 7) % 768)
		draw_rect(Rect2(x, y, 2.0, 2.0), Color(0.62, 0.61, 0.48, 0.045))


func _panel(rect: Rect2, title: String = "") -> void:
	draw_rect(Rect2(rect.position + Vector2(4, 5), rect.size), Color(0.0, 0.0, 0.0, 0.34))
	draw_rect(rect, C_PANEL)
	draw_rect(Rect2(rect.position + Vector2(5, 5), rect.size - Vector2(10, 10)), C_PANEL_2, false, 1.0)
	draw_rect(rect, C_EDGE, false, 2.0)
	if title != "":
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 31)), Color("#28281f"))
		draw_line(rect.position + Vector2(0, 31), rect.position + Vector2(rect.size.x, 31), C_EDGE, 1.0)
		_text(title, rect.position + Vector2(12, 22), 14, C_ACCENT)


func _text(text: String, pos: Vector2, size: int = 16, color: Color = C_TEXT, width: float = -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(_font, pos, text, align, width, size, color)


func _small_caps(text: String, pos: Vector2, color: Color = C_MUTED) -> void:
	_text(text, pos, 12, color)


func _wrapped_text(text: String, pos: Vector2, width: float, size: int, color: Color, max_lines: int = 2) -> void:
	var words := text.split(" ", false)
	var lines: Array[String] = []
	var current := ""
	for word in words:
		var candidate := String(word) if current == "" else current + " " + String(word)
		if current != "" and _font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x > width:
			lines.append(current)
			current = String(word)
		else:
			current = candidate
	if current != "" and lines.size() < max_lines:
		lines.append(current)
	if lines.size() > max_lines:
		lines.resize(max_lines)
	for i in mini(lines.size(), max_lines):
		_text(lines[i], pos + Vector2(0, i * (size + 4)), size, color, width)


func _draw_header(section: String, subtitle: String) -> void:
	draw_rect(Rect2(0, 0, 1280, 66), Color("#151711"))
	draw_line(Vector2(0, 65), Vector2(1280, 65), C_EDGE, 2.0)
	draw_rect(Rect2(24, 15, 5, 35), C_ACCENT)
	_text("MAP TILE LAB", Vector2(42, 37), 25, C_TEXT)
	_small_caps(section, Vector2(229, 36), C_ACCENT_2)
	_text(subtitle, Vector2(42, 54), 12, C_MUTED)
	_text(model.world_clock(), Vector2(1060, 36), 15, C_TEXT, 188, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_world() -> void:
	_draw_header("WORLD / CARAVAN", "RimWorld-scale decisions · roads remember distance · every tile can become a place")
	_draw_world_hexes()
	_draw_world_panel()
	_draw_footer("MOUSE select · RIGHT CLICK / ENTER travel · DOUBLE CLICK current tile · WASD move cursor")


func _hex_center(pos: Vector2i) -> Vector2:
	return HEX_ORIGIN + Vector2(float(pos.x) * HEX_X, float(pos.y) * HEX_Y + (HEX_Y * 0.5 if pos.x % 2 == 1 else 0.0))


func _hex_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(float(i) * 60.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	if not result.is_empty():
		result.append(result[0])
	return result


func _draw_world_hexes() -> void:
	# Ground first: neighboring outlines remain thin and the route can sit over them.
	for tile: Dictionary in model.world_tiles:
		var pos: Vector2i = tile["pos"]
		var center := _hex_center(pos)
		var points := _hex_points(center, HEX_R - 1.0)
		var base: Color = BIOME_COLORS[String(tile["biome"])]
		if not bool(tile["discovered"]):
			base = base.lerp(Color("#252922"), 0.62)
		draw_colored_polygon(points, base)
		_draw_hex_texture(tile, center)
		draw_polyline(_closed(points), Color("#282c24"), 2.0, true)

	# Existing road network is deliberately quieter than a planned caravan route.
	for tile: Dictionary in model.world_tiles:
		if not bool(tile["road"]):
			continue
		var a: Vector2i = tile["pos"]
		for b in model.world_neighbors(a):
			if b.y * ModelScript.WORLD_W + b.x <= a.y * ModelScript.WORLD_W + a.x:
				continue
			if bool(model.tile_at(b)["road"]):
				draw_line(_hex_center(a), _hex_center(b), Color("#3d3528"), 7.0, true)
				draw_line(_hex_center(a), _hex_center(b), Color("#a58d61"), 2.0, true)

	if model.route.size() > 1:
		var route_points := PackedVector2Array()
		for i in range(model.route_step, model.route.size()):
			route_points.append(_hex_center(model.route[i]))
		draw_polyline(route_points, Color(0.05, 0.06, 0.05, 0.72), 9.0, true)
		draw_polyline(route_points, C_ACCENT, 3.0, true)
		for i in range(model.route_step, model.route.size()):
			draw_circle(_hex_center(model.route[i]), 4.0, C_ACCENT)

	for tile: Dictionary in model.world_tiles:
		var pos: Vector2i = tile["pos"]
		var center := _hex_center(pos)
		if String(tile["site"]) != "":
			_draw_site_icon(center, String(tile["site_kind"]), bool(tile["discovered"]))
		if pos == _hover_world and pos != model.selected_tile:
			draw_polyline(_closed(_hex_points(center, HEX_R - 4.0)), Color(0.88, 0.84, 0.66, 0.48), 2.0, true)
		if pos == model.selected_tile:
			draw_polyline(_closed(_hex_points(center, HEX_R - 3.0)), C_ACCENT, 4.0, true)
			draw_line(center + Vector2(-13, -35), center + Vector2(13, -35), C_ACCENT, 2.0)

	_draw_caravan()


func _draw_hex_texture(tile: Dictionary, center: Vector2) -> void:
	var pos: Vector2i = tile["pos"]
	var biome := String(tile["biome"])
	var ink := Color(0.12, 0.14, 0.11, 0.22)
	var inner := _hex_points(center, HEX_R * 0.67)
	draw_polyline(_closed(inner), ink, 1.0, true)
	if biome == "highland":
		var peak := PackedVector2Array([center + Vector2(-22, 15), center + Vector2(-4, -16), center + Vector2(8, 3), center + Vector2(20, -10), center + Vector2(30, 16)])
		draw_polyline(peak, Color(0.84, 0.82, 0.73, 0.32), 2.0, true)
	elif biome == "pine":
		for i in 3:
			var ox := float((model._hash2(pos.x, pos.y, 151 + i) % 47) - 23)
			var oy := float((model._hash2(pos.x, pos.y, 161 + i) % 35) - 17)
			var p := center + Vector2(ox, oy)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -8), p + Vector2(-6, 5), p + Vector2(6, 5)]), Color(0.11, 0.20, 0.12, 0.42))
	elif biome == "marsh":
		for i in 3:
			var yy := -14.0 + i * 13.0
			draw_line(center + Vector2(-23 + i * 4, yy), center + Vector2(19 + i * 2, yy), Color(0.46, 0.70, 0.67, 0.25), 2.0)
	elif biome == "ash":
		for i in 5:
			var px := float((model._hash2(pos.x, pos.y, 181 + i) % 52) - 26)
			var py := float((model._hash2(pos.x, pos.y, 191 + i) % 38) - 19)
			draw_rect(Rect2(center + Vector2(px, py), Vector2(3, 3)), Color(0.16, 0.13, 0.12, 0.35))
	if not bool(tile["discovered"]):
		_text("?", center + Vector2(-5, 7), 20, Color(0.78, 0.78, 0.67, 0.38))


func _draw_site_icon(center: Vector2, kind: String, known: bool) -> void:
	var color := C_TEXT if known else Color(C_MUTED, 0.46)
	var p := center + Vector2(0, -2)
	if kind == "haven" or kind == "farm":
		draw_rect(Rect2(p + Vector2(-10, -1), Vector2(20, 14)), Color("#302b21"))
		draw_colored_polygon(PackedVector2Array([p + Vector2(-13, 0), p + Vector2(0, -12), p + Vector2(13, 0)]), color)
		draw_rect(Rect2(p + Vector2(-3, 5), Vector2(6, 8)), C_ACCENT_2)
	elif kind == "ruins":
		draw_rect(Rect2(p + Vector2(-11, -8), Vector2(8, 18)), color)
		draw_rect(Rect2(p + Vector2(2, -3), Vector2(9, 13)), color.darkened(0.18))
		draw_line(p + Vector2(-14, 13), p + Vector2(14, -13), C_DANGER, 3.0)
	elif kind == "tower":
		draw_line(p + Vector2(-8, 13), p + Vector2(0, -13), color, 3.0)
		draw_line(p + Vector2(8, 13), p + Vector2(0, -13), color, 3.0)
		draw_line(p + Vector2(-7, 6), p + Vector2(7, 6), color, 2.0)
		draw_circle(p + Vector2(0, -13), 4.0, C_ACCENT)
	elif kind == "clinic":
		draw_rect(Rect2(p + Vector2(-10, -10), Vector2(20, 20)), Color("#ddd2b7"))
		draw_rect(Rect2(p + Vector2(-3, -8), Vector2(6, 16)), C_DANGER)
		draw_rect(Rect2(p + Vector2(-8, -3), Vector2(16, 6)), C_DANGER)
	else:
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -12), p + Vector2(11, 0), p + Vector2(0, 12), p + Vector2(-11, 0)]), color)


func _draw_caravan() -> void:
	var center := _hex_center(model.caravan_tile)
	if model.traveling and model.route_step + 1 < model.route.size():
		center = center.lerp(_hex_center(model.route[model.route_step + 1]), model.travel_progress)
	var bob := sin(_pulse * 7.0) * 1.4 if model.traveling else 0.0
	center.y += bob
	draw_circle(center + Vector2(-10, 12), 6.0, Color("#171813"))
	draw_circle(center + Vector2(10, 12), 6.0, Color("#171813"))
	draw_circle(center + Vector2(-10, 12), 2.0, C_ACCENT)
	draw_circle(center + Vector2(10, 12), 2.0, C_ACCENT)
	draw_rect(Rect2(center + Vector2(-15, -4), Vector2(30, 16)), Color("#5b4933"))
	draw_colored_polygon(PackedVector2Array([center + Vector2(-16, -4), center + Vector2(-10, -15), center + Vector2(10, -15), center + Vector2(16, -4)]), Color("#d7c79f"))
	draw_line(center + Vector2(-10, -13), center + Vector2(10, -13), C_DANGER, 2.0)
	draw_circle(center, 26.0 + sin(_pulse * 3.0) * 2.0, Color(0.84, 0.68, 0.33, 0.18), false, 2.0)


func _draw_world_panel() -> void:
	_panel(Rect2(SIDE_X, 66, 360, 666), "CARAVAN LEDGER")
	var tile: Dictionary = model.tile_at(model.selected_tile)
	_small_caps("SELECTED TILE", Vector2(SIDE_X + 22, 118), C_MUTED)
	_text(model.display_name(tile).to_upper(), Vector2(SIDE_X + 22, 147), 22, C_TEXT, 316)
	_text(String(BIOME_LABELS[String(tile["biome"])]), Vector2(SIDE_X + 22, 171), 13, C_ACCENT_2)
	_text("RISK", Vector2(SIDE_X + 22, 205), 12, C_MUTED)
	_draw_pips(Vector2(SIDE_X + 82, 195), int(tile["risk"]), 5, C_DANGER)
	_text("FORAGE", Vector2(SIDE_X + 22, 231), 12, C_MUTED)
	_draw_pips(Vector2(SIDE_X + 82, 221), int(tile["forage"]), 4, C_GOOD)
	var site := String(tile["site"])
	if site == "":
		_wrapped_text("No fixed site. A local map will grow from terrain and risk.", Vector2(SIDE_X + 22, 267), 310, 13, C_MUTED)
	else:
		_text("SITE  %s" % String(tile["site_kind"]).to_upper(), Vector2(SIDE_X + 22, 267), 13, C_ACCENT)

	draw_line(Vector2(SIDE_X + 22, 292), Vector2(1258, 292), C_EDGE, 1.0)
	_small_caps("ROUTE", Vector2(SIDE_X + 22, 318), C_MUTED)
	var legs := maxi(0, model.route.size() - 1 - model.route_step)
	_text("%d LEGS" % legs, Vector2(SIDE_X + 270, 318), 13, C_TEXT, 68, HORIZONTAL_ALIGNMENT_RIGHT)
	_bar(Rect2(SIDE_X + 22, 332, 316, 12), model.route_cost() / 12.0, C_ACCENT)
	_text("Projected use  %.1f supply" % (model.route_cost() * 0.72), Vector2(SIDE_X + 22, 367), 13, C_MUTED)

	_small_caps("SUPPLY", Vector2(SIDE_X + 22, 407), C_MUTED)
	_bar(Rect2(SIDE_X + 100, 398, 238, 11), model.supplies / 24.0, C_GOOD)
	_text("%.1f / 24" % model.supplies, Vector2(SIDE_X + 100, 430), 13, C_TEXT)
	_small_caps("RIG", Vector2(SIDE_X + 22, 459), C_MUTED)
	_bar(Rect2(SIDE_X + 100, 450, 238, 11), model.condition / 100.0, C_ACCENT_2)
	_small_caps("MORALE", Vector2(SIDE_X + 22, 491), C_MUTED)
	_bar(Rect2(SIDE_X + 100, 482, 238, 11), model.morale / 100.0, C_ACCENT)
	_text("STASH  %d" % model.stash_value, Vector2(SIDE_X + 22, 530), 14, C_TEXT)

	var at_destination: bool = model.selected_tile == model.caravan_tile
	var action := "ENTER LOCAL MAP" if at_destination else ("TRAVELLING…" if model.traveling else "TRAVEL ROUTE")
	_button(_world_action_rect, action, not model.traveling, C_ACCENT if at_destination else C_ACCENT_2)
	_text("Double-click current tile to enter.", Vector2(SIDE_X + 22, 681), 12, C_MUTED)
	_text("Travel preserves supply and carried salvage.", Vector2(SIDE_X + 22, 699), 12, C_MUTED)


func _draw_pips(pos: Vector2, value: int, maximum: int, color: Color) -> void:
	for i in maximum:
		var rect := Rect2(pos + Vector2(i * 18.0, 0), Vector2(13, 9))
		draw_rect(rect, color if i < value else Color("#33362e"))
		draw_rect(rect, C_EDGE, false, 1.0)


func _bar(rect: Rect2, fraction: float, color: Color) -> void:
	draw_rect(rect, Color("#11130f"))
	draw_rect(Rect2(rect.position + Vector2(2, 2), Vector2(maxf(0.0, (rect.size.x - 4.0) * clampf(fraction, 0.0, 1.0)), rect.size.y - 4.0)), color)
	draw_rect(rect, C_EDGE, false, 1.0)


func _button(rect: Rect2, label: String, enabled: bool, accent: Color) -> void:
	var hover := rect.has_point(_mouse)
	var fill := Color("#34352c") if enabled else Color("#272923")
	if hover and enabled:
		fill = Color("#414237")
	draw_rect(Rect2(rect.position + Vector2(3, 4), rect.size), Color(0, 0, 0, 0.34))
	draw_rect(rect, fill)
	draw_rect(Rect2(rect.position, Vector2(5, rect.size.y)), accent if enabled else C_EDGE)
	draw_rect(rect, accent if enabled else C_EDGE, false, 2.0)
	_text(label, rect.position + Vector2(14, 30), 15, C_TEXT if enabled else C_MUTED, rect.size.x - 28, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_local() -> void:
	_draw_header("LOCAL / SCAVENGE", "Project Zomboid shells · Zero Sievert pressure · Stoneshard-readable turns")
	_draw_local_map()
	_draw_local_panel()
	_draw_footer("WASD / ARROWS step · E loot / interact · F strike · X extract at west marker")


func _cell_rect(pos: Vector2i) -> Rect2:
	return Rect2(LOCAL_ORIGIN + Vector2(pos) * LOCAL_CELL, Vector2(LOCAL_CELL, LOCAL_CELL))


func _draw_local_map() -> void:
	draw_rect(Rect2(LOCAL_ORIGIN - Vector2(7, 7), Vector2(ModelScript.LOCAL_W, ModelScript.LOCAL_H) * LOCAL_CELL + Vector2(14, 14)), Color("#090b09"))
	for y in ModelScript.LOCAL_H:
		for x in ModelScript.LOCAL_W:
			_draw_local_cell(Vector2i(x, y), model.cell_at(Vector2i(x, y)))

	for building: Dictionary in model.buildings:
		if not bool(building["revealed"]):
			_draw_roof(building)

	for prop: Dictionary in model.props:
		if _local_object_visible(prop["pos"]):
			_draw_prop(prop)
	for item: Dictionary in model.loot:
		if not bool(item["taken"]) and _local_object_visible(item["pos"]):
			_draw_loot(item)
	for threat: Dictionary in model.threats:
		if not bool(threat["dead"]) and _local_object_visible(threat["pos"]):
			_draw_threat(threat)
	_draw_player()
	if _hover_local.x >= 0:
		draw_rect(_cell_rect(_hover_local).grow(-2), Color(0.88, 0.83, 0.63, 0.35), false, 2.0)


func _draw_local_cell(pos: Vector2i, cell: int) -> void:
	var rect := _cell_rect(pos)
	var h: int = int(model._hash2(pos.x, pos.y, 211))
	if cell == ModelScript.Cell.GROUND:
		var col := Color("#4b5841") if h % 3 else Color("#46513c")
		draw_rect(rect, col)
		if h % 5 == 0:
			var p := rect.position + Vector2(5 + h % 13, 9 + (h / 7) % 10)
			draw_line(p, p + Vector2(2, -5), Color(0.47, 0.57, 0.35, 0.72), 1.0)
	elif cell == ModelScript.Cell.ROAD or cell == ModelScript.Cell.EXIT:
		draw_rect(rect, Color("#56534b") if h % 2 else Color("#514f48"))
		draw_line(rect.position + Vector2(0, rect.size.y - 2), rect.end - Vector2(0, 2), Color(0.17, 0.16, 0.14, 0.42), 1.0)
		if h % 7 == 0:
			draw_line(rect.position + Vector2(6, 7), rect.position + Vector2(19, 12), Color("#36342f"), 1.0)
		if cell == ModelScript.Cell.EXIT:
			for i in 4:
				draw_line(rect.position + Vector2(i * 9 - 4, 27), rect.position + Vector2(i * 9 + 10, 0), C_ACCENT, 3.0)
	elif cell == ModelScript.Cell.FLOOR:
		draw_rect(rect, Color("#79684f") if h % 2 else Color("#725f49"))
		draw_line(rect.position + Vector2(0, 8 + h % 9), rect.position + Vector2(27, 8 + h % 9), Color(0.24, 0.18, 0.13, 0.35), 1.0)
		draw_line(rect.position + Vector2(13, 0), rect.position + Vector2(13, 27), Color(0.75, 0.65, 0.47, 0.12), 1.0)
	elif cell == ModelScript.Cell.WALL:
		draw_rect(rect, Color("#3e3c36"))
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 7)), Color("#8c8879"))
		draw_rect(Rect2(rect.position + Vector2(0, 7), Vector2(5, 20)), Color("#292925"))
		draw_line(rect.position + Vector2(0, 7), rect.position + Vector2(27, 7), Color("#b0a993"), 1.0)
	elif cell == ModelScript.Cell.DOOR:
		draw_rect(rect, Color("#5c4631"))
		draw_rect(rect.grow(-4), Color("#785b3b"))
		draw_circle(rect.position + Vector2(20, 14), 2.0, C_ACCENT)
	elif cell == ModelScript.Cell.WINDOW:
		draw_rect(rect, Color("#343631"))
		draw_rect(Rect2(rect.position + Vector2(2, 4), Vector2(23, 9)), Color("#7fa3a0"))
		draw_line(rect.position + Vector2(13, 4), rect.position + Vector2(13, 13), Color("#d2ddca"), 1.0)
		draw_rect(Rect2(rect.position + Vector2(0, 13), Vector2(27, 5)), Color("#9b927b"))
	elif cell == ModelScript.Cell.RUBBLE:
		draw_rect(rect, Color("#4a5141"))
		draw_colored_polygon(PackedVector2Array([rect.position + Vector2(3, 21), rect.position + Vector2(9, 8), rect.position + Vector2(17, 14), rect.position + Vector2(24, 22)]), Color("#797568"))
		draw_line(rect.position + Vector2(7, 20), rect.position + Vector2(20, 15), Color("#33332e"), 2.0)
	elif cell == ModelScript.Cell.TREE:
		draw_rect(rect, Color("#46513c"))
		draw_rect(Rect2(rect.position + Vector2(12, 14), Vector2(5, 12)), Color("#483724"))
		draw_circle(rect.position + Vector2(14, 10), 11.0, Color("#2f4a32"))
		draw_circle(rect.position + Vector2(9, 9), 6.0, Color("#3d5d3b"))
	else:
		draw_rect(rect, Color("#334b4b"))
	draw_rect(rect, Color(0.05, 0.06, 0.05, 0.20), false, 1.0)


func _draw_roof(building: Dictionary) -> void:
	var rect_i: Rect2i = building["rect"]
	var rect := Rect2(LOCAL_ORIGIN + Vector2(rect_i.position) * LOCAL_CELL, Vector2(rect_i.size) * LOCAL_CELL)
	var tones := [Color("#735b4f"), Color("#596365"), Color("#675948")]
	var roof: Color = tones[int(building["roof_tone"])]
	draw_rect(Rect2(rect.position + Vector2(7, 10), rect.size), Color(0.0, 0.0, 0.0, 0.40))
	draw_rect(rect, roof)
	for y in range(9, int(rect.size.y), 13):
		draw_line(rect.position + Vector2(0, y), rect.position + Vector2(rect.size.x, y), roof.lightened(0.11) if y % 2 else roof.darkened(0.10), 2.0)
	var ridge_x := rect.position.x + rect.size.x * 0.5
	draw_line(Vector2(ridge_x, rect.position.y + 4), Vector2(ridge_x, rect.end.y - 4), roof.lightened(0.25), 3.0)
	draw_rect(rect, Color("#25251f"), false, 3.0)
	_text(String(building["label"]), rect.position + Vector2(10, 25), 12, Color(0.93, 0.89, 0.76, 0.78), rect.size.x - 20)
	_small_caps("ROOF / UNSCOUTED", rect.position + Vector2(10, 43), Color(0.86, 0.72, 0.48, 0.68))


func _local_object_visible(pos: Vector2i) -> bool:
	for building: Dictionary in model.buildings:
		var rect: Rect2i = building["rect"]
		if rect.grow(-1).has_point(pos):
			return bool(building["revealed"])
	return true


func _draw_loot(item: Dictionary) -> void:
	var rect := _cell_rect(item["pos"])
	var center := rect.get_center()
	var kind := String(item["kind"])
	var color := {"meds": C_DANGER, "food": C_GOOD, "parts": C_ACCENT_2, "scrap": C_ACCENT}.get(kind, C_TEXT) as Color
	draw_rect(Rect2(center - Vector2(7, 6), Vector2(14, 12)), Color("#25251f"))
	draw_rect(Rect2(center - Vector2(5, 4), Vector2(10, 8)), color)
	draw_line(center + Vector2(-5, -6), center + Vector2(5, -6), Color(0.95, 0.90, 0.72, 0.82), 2.0)
	draw_circle(center, 12.0 + sin(_pulse * 4.0) * 1.5, Color(color, 0.28), false, 1.5)


func _draw_prop(prop: Dictionary) -> void:
	var rect := _cell_rect(prop["pos"]).grow(-3.0)
	var kind := String(prop["kind"])
	if kind == "shelf":
		draw_rect(rect, Color("#332b22"))
		draw_rect(Rect2(rect.position + Vector2(2, 2), rect.size - Vector2(4, 4)), Color("#665039"))
		for y in [6.0, 12.0, 18.0]:
			draw_line(rect.position + Vector2(2, y), rect.position + Vector2(rect.size.x - 2, y), Color("#2a241d"), 2.0)
		draw_rect(Rect2(rect.position + Vector2(5, 4), Vector2(4, 3)), C_GOOD)
		draw_rect(Rect2(rect.position + Vector2(12, 10), Vector2(5, 3)), C_ACCENT)
	elif kind == "counter" or kind == "desk" or kind == "workbench":
		var wood := Color("#79583a") if kind != "workbench" else Color("#5f5545")
		draw_rect(Rect2(rect.position + Vector2(0, 5), Vector2(rect.size.x, 13)), Color("#32271d"))
		draw_rect(Rect2(rect.position + Vector2(1, 2), Vector2(rect.size.x - 2, 9)), wood)
		draw_line(rect.position + Vector2(2, 4), rect.position + Vector2(rect.size.x - 2, 4), wood.lightened(0.25), 2.0)
		if kind == "workbench":
			draw_line(rect.position + Vector2(5, 1), rect.position + Vector2(16, 11), C_ACCENT_2, 2.0)
		elif kind == "desk":
			draw_rect(Rect2(rect.position + Vector2(12, 1), Vector2(6, 5)), Color("#b6aa88"))
	elif kind == "bed":
		draw_rect(rect, Color("#49392b"))
		draw_rect(rect.grow(-2), Color("#75807a"))
		draw_rect(Rect2(rect.position + Vector2(3, 3), Vector2(rect.size.x - 6, 5)), Color("#d0c7ad"))
		draw_line(rect.position + Vector2(2, 11), rect.position + Vector2(rect.size.x - 2, 11), Color("#536765"), 2.0)
	elif kind == "cabinet" or kind == "wardrobe":
		var face := Color("#6b7069") if kind == "cabinet" else Color("#755637")
		draw_rect(rect, Color("#2d2d29"))
		draw_rect(rect.grow(-2), face)
		draw_line(rect.get_center() + Vector2(0, -8), rect.get_center() + Vector2(0, 8), face.darkened(0.30), 1.0)
		draw_circle(rect.get_center() + Vector2(3, 0), 1.5, C_ACCENT)
	elif kind == "anvil":
		draw_rect(Rect2(rect.position + Vector2(8, 9), Vector2(8, 11)), Color("#3a3935"))
		draw_colored_polygon(PackedVector2Array([rect.position + Vector2(1, 5), rect.position + Vector2(17, 5), rect.position + Vector2(22, 9), rect.position + Vector2(17, 13), rect.position + Vector2(4, 13)]), Color("#85847d"))
		draw_line(rect.position + Vector2(3, 6), rect.position + Vector2(17, 6), Color("#b7b19d"), 2.0)
	elif kind == "crate":
		draw_rect(rect, Color("#75583a"))
		draw_rect(rect, Color("#33271d"), false, 2.0)
		draw_line(rect.position + Vector2(2, 2), rect.end - Vector2(2, 2), Color("#4c3927"), 2.0)
		draw_line(rect.position + Vector2(rect.size.x - 2, 2), rect.position + Vector2(2, rect.size.y - 2), Color("#4c3927"), 2.0)
	elif kind == "stove":
		draw_rect(rect, Color("#323532"))
		draw_circle(rect.position + Vector2(7, 7), 4.0, Color("#11130f"))
		draw_circle(rect.position + Vector2(16, 7), 4.0, Color("#11130f"))
		draw_rect(Rect2(rect.position + Vector2(5, 14), Vector2(13, 6)), Color("#1b1d1a"))
	elif kind == "table":
		draw_circle(rect.get_center() + Vector2(2, 2), 9.0, Color(0, 0, 0, 0.28))
		draw_circle(rect.get_center(), 9.0, Color("#76573a"))
		draw_circle(rect.get_center(), 9.0, Color("#a47a4c"), false, 2.0)
	else:
		draw_rect(rect, Color("#6b6252"))


func _draw_threat(threat: Dictionary) -> void:
	var rect := _cell_rect(threat["pos"])
	var center := rect.get_center()
	var alert := bool(threat["alerted"])
	draw_circle(center + Vector2(0, 3), 8.0, Color("#322523"))
	draw_rect(Rect2(center + Vector2(-5, -9), Vector2(10, 15)), C_DANGER if alert else Color("#7b6159"))
	draw_rect(Rect2(center + Vector2(-4, -7), Vector2(2, 2)), Color("#f2c99a"))
	draw_rect(Rect2(center + Vector2(2, -7), Vector2(2, 2)), Color("#f2c99a"))
	if alert:
		draw_circle(center, 13.0 + sin(_pulse * 8.0) * 2.0, Color(0.85, 0.28, 0.22, 0.34), false, 2.0)


func _draw_player() -> void:
	var rect := _cell_rect(model.player)
	var center := rect.get_center()
	draw_circle(center + Vector2(2, 5), 9.0, Color(0, 0, 0, 0.35))
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -12), center + Vector2(9, -2), center + Vector2(6, 11), center + Vector2(-6, 11), center + Vector2(-9, -2)]), C_ACCENT)
	draw_rect(Rect2(center + Vector2(-4, -8), Vector2(8, 5)), Color("#e0d6b7"))
	draw_circle(center, 17.0 + sin(_pulse * 3.0), Color(0.90, 0.75, 0.39, 0.30), false, 2.0)


func _draw_local_panel() -> void:
	_panel(Rect2(SIDE_X, 66, 360, 666), "RAID CARD")
	_small_caps("MAP TILE", Vector2(SIDE_X + 22, 116), C_MUTED)
	_text(model.site_title, Vector2(SIDE_X + 22, 144), 21, C_TEXT, 316)
	_text(model.current_building, Vector2(SIDE_X + 22, 168), 13, C_ACCENT_2)

	_text("LOCAL TIME", Vector2(SIDE_X + 22, 207), 12, C_MUTED)
	_text(model.local_clock(), Vector2(SIDE_X + 260, 208), 20, C_TEXT, 78, HORIZONTAL_ALIGNMENT_RIGHT)
	_text("TURNS", Vector2(SIDE_X + 22, 234), 12, C_MUTED)
	_text(str(model.local_turns), Vector2(SIDE_X + 280, 234), 14, C_TEXT, 58, HORIZONTAL_ALIGNMENT_RIGHT)

	_small_caps("HEALTH", Vector2(SIDE_X + 22, 278), C_MUTED)
	_bar(Rect2(SIDE_X + 99, 268, 239, 12), float(model.health) / 100.0, C_DANGER if model.health < 45 else C_GOOD)
	_small_caps("NOISE", Vector2(SIDE_X + 22, 310), C_MUTED)
	_bar(Rect2(SIDE_X + 99, 300, 239, 12), float(model.noise) / 10.0, C_DANGER)

	draw_line(Vector2(SIDE_X + 22, 336), Vector2(1258, 336), C_EDGE, 1.0)
	_small_caps("PACK", Vector2(SIDE_X + 22, 362), C_MUTED)
	var kinds := [
		["food", "RATION", C_GOOD],
		["meds", "MED", C_DANGER],
		["parts", "PARTS", C_ACCENT_2],
		["scrap", "SCRAP", C_ACCENT],
	]
	for i in kinds.size():
		var row: Array = kinds[i]
		var y := 388.0 + i * 28.0
		draw_rect(Rect2(SIDE_X + 22, y - 13, 10, 10), row[2])
		_text(String(row[1]), Vector2(SIDE_X + 42, y - 3), 13, C_MUTED)
		_text(str(model.inventory[String(row[0])]), Vector2(SIDE_X + 282, y - 3), 14, C_TEXT, 56, HORIZONTAL_ALIGNMENT_RIGHT)
	_text("%.1f kg   ·   value %d" % [model.cargo_weight, model.cargo_value], Vector2(SIDE_X + 22, 510), 14, C_TEXT)

	_button(_local_action_rect, "E  LOOT", true, C_ACCENT_2)
	_button(_local_attack_rect, "F  STRIKE", true, C_DANGER)
	_button(_local_extract_rect, "X  EXTRACT" if model.can_extract() else "EXTRACTION: WEST EDGE", model.can_extract(), C_ACCENT)
	_wrapped_text(model.latest_message(), Vector2(SIDE_X + 22, 693), 312, 12, C_MUTED, 2)


func _draw_footer(hint: String) -> void:
	draw_rect(Rect2(0, 733, 1280, 35), Color("#151711"))
	draw_line(Vector2(0, 733), Vector2(1280, 733), C_EDGE, 1.0)
	_text(hint, Vector2(24, 756), 13, C_MUTED)


func _world_pick(point: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := HEX_R * 0.92
	for tile: Dictionary in model.world_tiles:
		var pos: Vector2i = tile["pos"]
		var distance := point.distance_to(_hex_center(pos))
		if distance < best_distance:
			best_distance = distance
			best = pos
	return best


func _local_pick(point: Vector2) -> Vector2i:
	var local := (point - LOCAL_ORIGIN) / LOCAL_CELL
	var pos := Vector2i(floori(local.x), floori(local.y))
	return pos if model.local_in_bounds(pos) else Vector2i(-1, -1)


func _move_world_cursor(delta: Vector2i) -> void:
	if model.traveling:
		return
	var target: Vector2i = model.selected_tile + delta
	if model.world_in_bounds(target):
		model.plan_route(target)


func _world_action() -> void:
	if model.traveling:
		return
	if model.selected_tile == model.caravan_tile:
		model.enter_local()
	else:
		model.begin_travel()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		if model.mode == ModelScript.Mode.WORLD:
			_hover_world = _world_pick(_mouse)
		else:
			_hover_local = _local_pick(_mouse)
		queue_redraw()
		return
	if event is InputEventMouseButton and event.pressed:
		_mouse = event.position
		if model.mode == ModelScript.Mode.WORLD:
			if _world_action_rect.has_point(_mouse):
				if event.button_index == MOUSE_BUTTON_LEFT:
					_world_action()
				return
			if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
				return
			var picked := _world_pick(_mouse)
			if picked.x >= 0 and not model.traveling:
				model.plan_route(picked)
				if event.button_index == MOUSE_BUTTON_LEFT and event.double_click and picked == model.caravan_tile:
					model.enter_local()
				elif event.button_index == MOUSE_BUTTON_RIGHT:
					model.begin_travel()
		else:
			if event.button_index != MOUSE_BUTTON_LEFT:
				return
			if _local_action_rect.has_point(_mouse):
				model.interact()
			elif _local_attack_rect.has_point(_mouse):
				model.attack()
			elif _local_extract_rect.has_point(_mouse):
				model.extract_local()
			else:
				var picked := _local_pick(_mouse)
				var delta: Vector2i = picked - model.player
				if absi(delta.x) + absi(delta.y) == 1:
					model.move_player(delta)
		queue_redraw()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: Key = event.keycode
	if model.mode == ModelScript.Mode.WORLD:
		match key:
			KEY_W, KEY_UP:
				_move_world_cursor(Vector2i(0, -1))
			KEY_S, KEY_DOWN:
				_move_world_cursor(Vector2i(0, 1))
			KEY_A, KEY_LEFT:
				_move_world_cursor(Vector2i(-1, 0))
			KEY_D, KEY_RIGHT:
				_move_world_cursor(Vector2i(1, 0))
			KEY_ENTER, KEY_SPACE:
				_world_action()
	else:
		match key:
			KEY_W, KEY_UP:
				model.move_player(Vector2i(0, -1))
			KEY_S, KEY_DOWN:
				model.move_player(Vector2i(0, 1))
			KEY_A, KEY_LEFT:
				model.move_player(Vector2i(-1, 0))
			KEY_D, KEY_RIGHT:
				model.move_player(Vector2i(1, 0))
			KEY_E, KEY_SPACE:
				model.interact()
			KEY_F:
				model.attack()
			KEY_X, KEY_ESCAPE:
				model.extract_local()
	queue_redraw()
