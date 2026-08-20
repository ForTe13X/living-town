extends Node2D

const ScaleAddress = preload("res://scripts/labs/resource_pool/ScaleAddress.gd")
const Contract = preload("res://scripts/labs/resource_pool/ExpeditionContract.gd")

const DESIGN := Vector2(1280.0, 768.0)
const MISSIONS := ["field_medicine", "winter_rations", "relay_parts"]
const RESULTS := ["success", "strained", "partial", "retreat", "collapse"]

const C_BG := Color("#11140f")
const C_PANEL := Color("#1c1e19")
const C_PANEL_2 := Color("#24251f")
const C_EDGE := Color("#565846")
const C_TEXT := Color("#ded8c4")
const C_MUTED := Color("#929382")
const C_GOLD := Color("#d2a85c")
const C_TEAL := Color("#78a999")
const C_MED := Color("#8fa6c9")
const C_GOOD := Color("#8fb56d")
const C_DANGER := Color("#c45b50")

var _font: Font
var _mission := "relay_parts"
var _result := "partial"
var _brief: Dictionary = {}
var _outcome: Dictionary = {}
var _shot_path := ""
var _mission_rects: Array[Rect2] = []
var _result_rects: Array[Rect2] = []


func _ready() -> void:
	_font = ThemeDB.fallback_font
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--expedition-mission" and i + 1 < args.size() and args[i + 1] in MISSIONS:
			_mission = args[i + 1]
		elif args[i] == "--expedition-result" and i + 1 < args.size() and args[i + 1] in RESULTS:
			_result = args[i + 1]
		elif args[i] == "--lab-shot" and i + 1 < args.size():
			_shot_path = args[i + 1]
	_rebuild()
	queue_redraw()
	if _shot_path != "":
		get_tree().create_timer(0.6).timeout.connect(_save_shot)


func _rebuild() -> void:
	var destination := ScaleAddress.site_address("ashfall", 0, Vector2i(7, -1), "ash_market")
	_brief = Contract.make_brief(260814, ScaleAddress.canonical_id(destination), _mission, "day12-board-a")
	_outcome = Contract.evaluate(_brief, _scenario_snapshot(_mission, _result))
	queue_redraw()


func _scenario_snapshot(mission: String, result: String) -> Dictionary:
	var objective: Dictionary = _brief["objective"]
	var profile: Dictionary = _brief["profile"]
	var inventory := {"food": 0, "meds": 0, "parts": 0, "scrap": 0}
	var kind := String(objective["kind"])
	if result in ["success", "strained", "collapse"]:
		inventory[kind] = 2
	elif result == "partial":
		inventory[kind] = 1
	else:
		inventory["scrap"] = 1
	var value := int(profile["value"])
	var weight := int(profile["weight_grams"])
	var noise := int(profile["noise"])
	if result == "partial":
		var partials := {
			"field_medicine": [42, 800, 5],
			"winter_rations": [18, 1200, 4],
			"relay_parts": [55, 1100, 7],
		}
		var partial: Array = partials[mission]
		value = int(partial[0])
		weight = int(partial[1])
		noise = int(partial[2])
	elif result == "retreat":
		value = 24
		weight = 2000
		noise = 3
	elif result == "collapse":
		value += 8
		weight += 400
		noise = 10
	elif result == "strained":
		if mission == "relay_parts":
			weight = 4500
		elif mission == "winter_rations":
			noise = 6
	var health := 0 if result == "collapse" else (60 if result == "strained" and mission == "field_medicine" \
		else (93 if result == "partial" else 100))
	var turns := 41 if result == "collapse" else (45 if result == "strained" and mission == "winter_rations" \
		else (34 if result == "partial" else (12 if result == "retreat" else 35)))
	var threats := 2 if result == "collapse" else (1 if result in ["success", "partial"] else 0)
	return Contract.make_snapshot("collapsed" if result == "collapse" else "extracted",
		inventory, value, weight, health, turns, noise, threats)


func _save_shot() -> void:
	var image := get_viewport().get_texture().get_image()
	if image != null:
		image.save_png(_shot_path)
	get_tree().quit()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, DESIGN), C_BG)
	for i in 44:
		var x := float((i * 173 + 47) % 1280)
		var y := float((i * 97 + 31) % 768)
		draw_rect(Rect2(x, y, 2, 2), Color(0.72, 0.67, 0.48, 0.045))
	_draw_header()
	_draw_mission_column()
	_draw_brief_panel()
	_draw_debrief_panel()
	_draw_result_tabs()


func _draw_header() -> void:
	draw_rect(Rect2(0, 0, 1280, 72), Color("#171a14"))
	draw_line(Vector2(0, 71), Vector2(1280, 71), C_EDGE, 1)
	_text("EXPEDITION BOARD // RP-0002", Vector2(24, 31), 22, C_TEXT)
	_text("Choose a reason to leave. Extraction—not pickup—settles the promise.", Vector2(24, 55), 13, C_MUTED)
	_text("ASH MARKET", Vector2(1070, 31), 13, C_GOLD, 180, HORIZONTAL_ALIGNMENT_RIGHT)
	_text("DAY 12  ·  SITE CONTRACT", Vector2(1010, 54), 11, C_MUTED, 240, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_mission_column() -> void:
	_panel(Rect2(24, 92, 300, 590), "CHOOSE ONE BRIEF")
	_mission_rects.clear()
	for i in MISSIONS.size():
		var mission := String(MISSIONS[i])
		var rect := Rect2(40, 137 + i * 164, 268, 146)
		_mission_rects.append(rect)
		var selected := mission == _mission
		var candidate := Contract.make_brief(260814, String(_brief["destination"]), mission, "day12-board-a")
		var objective: Dictionary = candidate["objective"]
		var constraint: Dictionary = candidate["constraint"]
		var profile: Dictionary = candidate["profile"]
		draw_rect(rect, Color("#303128") if selected else Color("#22241e"))
		draw_rect(Rect2(rect.position, Vector2(6, rect.size.y)), _mission_color(mission) if selected else C_EDGE)
		draw_rect(rect, _mission_color(mission) if selected else C_EDGE, false, 2 if selected else 1)
		_text("%d" % (i + 1), rect.position + Vector2(15, 24), 12, C_MUTED)
		_text(String(candidate["title"]), rect.position + Vector2(39, 25), 13, C_TEXT, 216)
		_text("PROMISE  EXTRACT %d %s" % [int(objective["required"]), String(objective["kind"]).to_upper()],
			rect.position + Vector2(15, 54), 12, _mission_color(mission))
		_text("VALUE %d" % int(profile["value"]), rect.position + Vector2(15, 82), 11, C_MUTED)
		_text("%.1f KG" % (float(int(profile["weight_grams"])) / 1000.0), rect.position + Vector2(99, 82), 11, C_MUTED)
		_text("NOISE %d" % int(profile["noise"]), rect.position + Vector2(184, 82), 11, C_MUTED)
		_text("LIMIT  " + String(constraint["label"]).to_upper(), rect.position + Vector2(15, 106),
			10, C_GOLD, 238)
		_wrapped(String(candidate["choice_hint"]), rect.position + Vector2(15, 128), 238, 10, C_MUTED, 1)


func _draw_brief_panel() -> void:
	_panel(Rect2(340, 92, 424, 590), "SELECTED DEPARTURE BRIEF")
	var objective: Dictionary = _brief["objective"]
	var constraint: Dictionary = _brief["constraint"]
	var profile: Dictionary = _brief["profile"]
	_text(String(_brief["title"]), Vector2(362, 151), 21, C_TEXT, 380)
	_text(String(_brief["contract_id"]), Vector2(362, 177), 11, C_MUTED)
	draw_line(Vector2(362, 193), Vector2(742, 193), C_EDGE, 1)
	_small_caps("PRIMARY PROMISE", Vector2(362, 222), C_MUTED)
	_text("EXTRACT %d × %s" % [int(objective["required"]), String(objective["kind"]).to_upper()],
		Vector2(362, 253), 19, _mission_color(_mission))
	_text(String(objective["label"]), Vector2(362, 276), 12, C_MUTED)
	_small_caps("EXPECTED FULL BUNDLE", Vector2(362, 316), C_MUTED)
	_metric_bar("VALUE", int(profile["value"]), 100, Vector2(362, 343), C_GOLD)
	_metric_bar("WEIGHT", int(profile["weight_grams"]), 5000, Vector2(362, 382), C_TEAL)
	_metric_bar("NOISE", int(profile["noise"]), 10, Vector2(362, 421), C_DANGER)
	_text("LOCATION  %s" % String(profile["location"]).to_upper(), Vector2(362, 464), 12, C_TEXT)
	_small_caps("WHY IT MATTERS", Vector2(362, 501), C_MUTED)
	_wrapped(String(_brief["stakes"]), Vector2(362, 525), 376, 13, C_TEXT, 3)
	draw_rect(Rect2(362, 598, 378, 55), Color("#171914"))
	draw_rect(Rect2(362, 598, 5, 55), C_GOLD)
	_text("CONSTRAINT", Vector2(377, 619), 10, C_MUTED)
	_wrapped(String(constraint["label"]), Vector2(377, 641), 345, 12, C_TEXT, 1)


func _draw_debrief_panel() -> void:
	_panel(Rect2(780, 92, 476, 590), "CAUSAL DEBRIEF")
	var status := String(_outcome["status"])
	var grade := String(_outcome["grade"])
	var result_color := _result_color(status, grade)
	_text(String(_outcome["headline"]), Vector2(802, 151), 22, result_color, 432)
	_text("%s  ·  %s" % [status.to_upper(), grade.to_upper()], Vector2(802, 178), 12, C_MUTED)
	var objective: Dictionary = _outcome["objective"]
	_text("TARGET", Vector2(802, 217), 11, C_MUTED)
	_text("%d / %d DELIVERED" % [int(objective["delivered"]), int(objective["required"])],
		Vector2(1080, 217), 13, C_TEXT, 150, HORIZONTAL_ALIGNMENT_RIGHT)
	_bar(Rect2(802, 230, 430, 13), float(int(objective["delivered"])) / float(int(objective["required"])), result_color)
	var settlement: Dictionary = _outcome["settlement"]
	var banked := int(settlement["banked_value"])
	var lost := int(settlement["lost_value"])
	_text("BANKED  %d" % banked, Vector2(802, 277), 13, C_GOOD if banked > 0 else C_MUTED)
	_text("LOST  %d" % lost, Vector2(1080, 277), 13, C_DANGER if lost > 0 else C_MUTED,
		150, HORIZONTAL_ALIGNMENT_RIGHT)
	draw_line(Vector2(802, 298), Vector2(1232, 298), C_EDGE, 1)
	_small_caps("WHY THIS RESULT", Vector2(802, 326), C_MUTED)
	var lines: Array = _outcome["lines"]
	var y := 358.0
	for i in lines.size():
		draw_circle(Vector2(809, y - 5), 3.0, result_color)
		var used := _wrapped(String(lines[i]), Vector2(822, y), 397, 12, C_TEXT, 2)
		y += maxf(42.0, used + 10.0)
	var metrics: Dictionary = _outcome["metrics"]
	draw_rect(Rect2(802, 602, 430, 50), Color("#171914"))
	_text("%d MIN" % int(metrics["minutes_elapsed"]), Vector2(818, 630), 12, C_MUTED)
	_text("HEALTH LOST %d" % int(metrics["health_lost"]), Vector2(938, 630), 12, C_MUTED)
	_text("PEAK NOISE %d" % int(metrics["peak_noise"]), Vector2(1092, 630), 12, C_MUTED)
	_text(String(_outcome["outcome_id"]), Vector2(802, 672), 10, C_MUTED)


func _draw_result_tabs() -> void:
	draw_rect(Rect2(0, 704, 1280, 64), Color("#171a14"))
	draw_line(Vector2(0, 704), Vector2(1280, 704), C_EDGE, 1)
	_text("LAB OUTCOME FIXTURE", Vector2(24, 741), 11, C_MUTED)
	_result_rects.clear()
	for i in RESULTS.size():
		var result := String(RESULTS[i])
		var rect := Rect2(166 + i * 166, 719, 154, 33)
		_result_rects.append(rect)
		var selected := result == _result
		draw_rect(rect, Color("#35362d") if selected else Color("#22241e"))
		draw_rect(rect, _result_color(result, "") if selected else C_EDGE, false, 2 if selected else 1)
		_text("%s  %s" % [String.chr(65 + i), result.to_upper()], rect.position + Vector2(12, 22), 12,
			C_TEXT if selected else C_MUTED, rect.size.x - 24, HORIZONTAL_ALIGNMENT_CENTER)
	_text("1–3 mission  ·  A–E fixture only", Vector2(1020, 741), 11, C_MUTED, 230, HORIZONTAL_ALIGNMENT_RIGHT)


func _panel(rect: Rect2, title: String) -> void:
	draw_rect(Rect2(rect.position + Vector2(4, 5), rect.size), Color(0, 0, 0, 0.32))
	draw_rect(rect, C_PANEL)
	draw_rect(rect, C_EDGE, false, 2)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 31)), C_PANEL_2)
	draw_line(rect.position + Vector2(0, 31), rect.position + Vector2(rect.size.x, 31), C_EDGE, 1)
	_text(title, rect.position + Vector2(12, 22), 13, C_GOLD)


func _metric_bar(label: String, value: int, maximum: int, pos: Vector2, color: Color) -> void:
	_text(label, pos, 11, C_MUTED)
	_bar(Rect2(pos + Vector2(72, -10), Vector2(238, 11)), float(value) / float(maximum), color)
	var label_value := str(value)
	if label == "WEIGHT":
		label_value = "%.1f kg" % (float(value) / 1000.0)
	_text(label_value, pos + Vector2(320, 0), 11, C_TEXT, 58, HORIZONTAL_ALIGNMENT_RIGHT)


func _bar(rect: Rect2, fraction: float, color: Color) -> void:
	draw_rect(rect, Color("#10120f"))
	draw_rect(Rect2(rect.position + Vector2(2, 2), Vector2((rect.size.x - 4) * clampf(fraction, 0, 1), rect.size.y - 4)), color)
	draw_rect(rect, C_EDGE, false, 1)


func _small_caps(text: String, pos: Vector2, color: Color) -> void:
	_text(text, pos, 11, color)


func _text(text: String, pos: Vector2, size: int, color: Color,
		width: float = -1, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(_font, pos, text, align, width, size, color)


func _wrapped(text: String, pos: Vector2, width: float, size: int, color: Color, max_lines: int) -> float:
	var words := text.split(" ", false)
	var lines: Array[String] = []
	var current := ""
	for word in words:
		var candidate := String(word) if current == "" else current + " " + String(word)
		if _font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
			current = candidate
		else:
			if current != "":
				lines.append(current)
			current = String(word)
	if current != "":
		lines.append(current)
	if lines.size() > max_lines:
		lines.resize(max_lines)
		lines[-1] = lines[-1].trim_suffix(".") + "…"
	var y := pos.y
	for line in lines:
		_text(line, Vector2(pos.x, y), size, color, width)
		y += size + 5
	return y - pos.y


func _mission_color(mission: String) -> Color:
	if mission == "field_medicine":
		return C_MED
	if mission == "winter_rations":
		return C_GOOD
	return C_TEAL


func _result_color(status: String, grade: String) -> Color:
	if status == "collapse":
		return C_DANGER
	if status == "retreat":
		return C_GOLD
	if status in ["partial", "strained"] or grade == "strained":
		return Color("#d39a55")
	return C_GOOD


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in _mission_rects.size():
			if _mission_rects[i].has_point(event.position):
				_mission = String(MISSIONS[i])
				_rebuild()
				return
		for i in _result_rects.size():
			if _result_rects[i].has_point(event.position):
				_result = String(RESULTS[i])
				_rebuild()
				return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1, KEY_2, KEY_3:
			_mission = String(MISSIONS[int(event.keycode) - int(KEY_1)])
			_rebuild()
		KEY_A, KEY_B, KEY_C, KEY_D, KEY_E:
			_result = String(RESULTS[int(event.keycode) - int(KEY_A)])
			_rebuild()
