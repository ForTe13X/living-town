class_name RolePOVCard
extends Control
## Compact role evidence card built exclusively from the S06 snapshot IDs.

const BG := Color("22222d")
const EDGE := Color("555064")
const INK := Color("eadfc4")
const MUTED := Color("aaa4b4")
const ACCENT := Color("d88b57")

var last_errors: Array[String] = []
var _snapshot: Dictionary = {}
var _labels: Array[Label] = []


func _ready() -> void:
	custom_minimum_size = Vector2(470, 520)
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
	return "%s|%s|%s|%s|%s" % [
		String(_snapshot["role_id"]),
		String(_snapshot["now_node"]),
		",".join(_snapshot["receipt_ids"]),
		",".join(_snapshot["carried_fragment_ids"]),
		",".join(_snapshot["open_request_ids"]),
	]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), EDGE, false, 2.0)
	draw_rect(Rect2(Vector2(0, 0), Vector2(size.x, 7)), ACCENT)
	if _snapshot.is_empty():
		return
	var status := String(_snapshot["status"])
	NarrativeGlyphs.draw_glyph(self, NarrativeGlyphs.BLOCKED if status == "blocked" else NarrativeGlyphs.TRAVERSED, Rect2(size.x - 58, 25, 34, 34), INK, ACCENT)
	var marks := [
		[NarrativeGlyphs.RECEIPT, 194.0],
		[NarrativeGlyphs.FRAGMENT, 302.0],
		[NarrativeGlyphs.REQUEST, 410.0],
	]
	for mark in marks:
		NarrativeGlyphs.draw_glyph(self, String(mark[0]), Rect2(24, float(mark[1]), 26, 26), INK, ACCENT)


func _rebuild_labels() -> void:
	for label in _labels:
		remove_child(label)
		label.free()
	_labels.clear()
	if _snapshot.is_empty():
		return
	_add_label("role", "ROLE  %s" % String(_snapshot["role_id"]), Vector2(24, 24), 22, INK)
	_add_label("place", "NOW   %s" % String(_snapshot["now_node"]), Vector2(24, 66), 17, MUTED)
	var clock: Dictionary = _snapshot["clock"]
	_add_label("clock", "WATCH %s   TICK %s   %s" % [clock.get("watch", "?"), clock.get("tick", "?"), String(_snapshot["status"]).to_upper()], Vector2(24, 96), 15, ACCENT)
	_add_label("visible", "VISIBLE WEB  %d nodes / %d links" % [(_snapshot["visible_nodes"] as Array).size(), (_snapshot["visible_edges"] as Array).size()], Vector2(24, 134), 15, MUTED)
	_add_section("receipt", "RECEIPTS", _snapshot["receipt_ids"], 190.0)
	_add_section("fragment", "FRAGMENTS", _snapshot["carried_fragment_ids"], 298.0)
	_add_section("request", "REQUESTS", _snapshot["open_request_ids"], 406.0)


func _add_section(prefix: String, title: String, ids: Array, y: float) -> void:
	_add_label("%s_title" % prefix, title, Vector2(60, y), 15, INK)
	var display := "none" if ids.is_empty() else "  /  ".join(ids)
	_add_label("%s_ids" % prefix, display, Vector2(60, y + 31), 15, MUTED)


func _add_label(label_name: String, value: String, pos: Vector2, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.name = label_name
	label.text = value
	label.position = pos
	label.size = Vector2(size.x - pos.x - 18, 28)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	_labels.append(label)


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
