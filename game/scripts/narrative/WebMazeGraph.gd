class_name WebMazeGraph
extends Control
## Read-only web-maze projection.  This component accepts exactly the S06
## ten-field snapshot and never receives edge endpoints or narrative prose.

const BG := Color("171821")
const WEB := Color("56536c")
const ROUTE := Color("d88b57")
const NODE := Color("302f42")
const CURRENT := Color("75634d")
const INK := Color("e6d6ad")
const MUTED := Color("9d99aa")

var last_errors: Array[String] = []
var _snapshot: Dictionary = {}
var _node_positions := {}
var _labels: Array[Label] = []


func _ready() -> void:
	custom_minimum_size = Vector2(520, 410)
	clip_contents = true
	queue_redraw()


func set_snapshot(snapshot: Dictionary) -> bool:
	last_errors = _shape_errors(snapshot)
	_snapshot = snapshot.duplicate(true) if last_errors.is_empty() else {}
	_rebuild_labels()
	queue_redraw()
	return last_errors.is_empty()


func snapshot_fingerprint() -> String:
	if _snapshot.is_empty():
		return ""
	return "%s|%s|%s|%s" % [
		String(_snapshot["role_id"]),
		",".join(_snapshot["visible_nodes"]),
		",".join(_snapshot["visible_edges"]),
		",".join(_snapshot["route_hint"]),
	]


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout_nodes()
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), Color("444155"), false, 2.0)
	if _snapshot.is_empty():
		return
	_layout_nodes()
	var visible: Array = _snapshot["visible_nodes"]
	if visible.size() > 1:
		for index in range((_snapshot["visible_edges"] as Array).size()):
			var a_id := String(visible[index % visible.size()])
			var b_id := String(visible[(index + 1) % visible.size()])
			draw_line(_node_positions[a_id], _node_positions[b_id], WEB, 2.0, true)
	var route: Array = _snapshot["route_hint"]
	for index in range(route.size() - 1):
		var a_id := String(route[index])
		var b_id := String(route[index + 1])
		if _node_positions.has(a_id) and _node_positions.has(b_id):
			draw_line(_node_positions[a_id], _node_positions[b_id], ROUTE, 5.0, true)
	for node_id_value in visible:
		var node_id := String(node_id_value)
		var center: Vector2 = _node_positions[node_id]
		var is_current := node_id == String(_snapshot["now_node"])
		var is_route := node_id in route
		draw_circle(center, 27.0 if is_current else 22.0, CURRENT if is_current else NODE)
		draw_circle(center, 27.0 if is_current else 22.0, ROUTE if is_route else WEB, false, 3.0, true)
		var glyph_kind := NarrativeGlyphs.TRAVERSED if is_route else NarrativeGlyphs.UNKNOWN
		if String(_snapshot["status"]) == "blocked" and is_current:
			glyph_kind = NarrativeGlyphs.BLOCKED
		NarrativeGlyphs.draw_glyph(self, glyph_kind, Rect2(center - Vector2(10, 10), Vector2(20, 20)), INK, ROUTE)


func _layout_nodes() -> void:
	_node_positions.clear()
	if _snapshot.is_empty():
		return
	var visible: Array = _snapshot["visible_nodes"]
	var current_id := String(_snapshot["now_node"])
	var center := Vector2(size.x * 0.5, size.y * 0.50)
	var radius := Vector2(maxf(90.0, size.x * 0.33), maxf(70.0, size.y * 0.31))
	_node_positions[current_id] = center
	var others: Array[String] = []
	for node_id_value in visible:
		var node_id := String(node_id_value)
		if node_id != current_id:
			others.append(node_id)
	for index in range(others.size()):
		var angle := -PI * 0.5 + TAU * float(index) / maxf(1.0, float(others.size()))
		_node_positions[others[index]] = center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)
	for label in _labels:
		var node_id := String(label.get_meta("node_id", ""))
		if _node_positions.has(node_id):
			label.position = (_node_positions[node_id] as Vector2) + Vector2(-72, 31)


func _rebuild_labels() -> void:
	for label in _labels:
		remove_child(label)
		label.free()
	_labels.clear()
	if _snapshot.is_empty():
		return
	var visible: Array = _snapshot["visible_nodes"]
	for index in range(visible.size()):
		var node_id := String(visible[index])
		var label := Label.new()
		label.name = "visible_node_%02d" % index
		label.text = node_id
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size = Vector2(144, 28)
		label.add_theme_color_override("font_color", INK if node_id == String(_snapshot["now_node"]) else MUTED)
		label.add_theme_font_size_override("font_size", 16)
		label.set_meta("node_id", node_id)
		add_child(label)
		_labels.append(label)
	_layout_nodes()


func _shape_errors(snapshot: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key in snapshot.keys():
		if not String(key) in NarrativeViewContract.SNAPSHOT_KEYS:
			errors.append("snapshot.extra:%s" % String(key))
	for key in NarrativeViewContract.SNAPSHOT_KEYS:
		if not snapshot.has(key):
			errors.append("snapshot.missing:%s" % key)
	if not errors.is_empty():
		errors.sort()
		return errors
	for key in ["visible_nodes", "visible_edges", "carried_fragment_ids", "receipt_ids", "open_request_ids", "route_hint"]:
		if not snapshot[key] is Array:
			errors.append("snapshot.type:%s" % key)
	for key in ["role_id", "now_node", "status"]:
		if not snapshot[key] is String:
			errors.append("snapshot.type:%s" % key)
	if not snapshot["clock"] is Dictionary:
		errors.append("snapshot.type:clock")
	errors.sort()
	return errors
