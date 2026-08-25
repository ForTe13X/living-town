extends Node2D
## C1 locked-orthographic cafe frame.  This is deliberately projection-only:
## it reads the existing Probe plane and receives human-readable receipts, but
## never receives input and never writes Sim, navigation, saves, or replay.

var _probe: Node
var _feedback := ""

const CELL := 48.0
const INK := Color("#f6e7c1")
const MUTED := Color("#786f72")
const ACCENT := Color("#d88c62")
const PRESENTATION_PORTALS := ["p_cafe_door", "p_cafe_stairs"]

func setup(probe: Node) -> void:
	_probe = probe
	queue_redraw()

func show_receipt(text: String) -> void:
	_feedback = text
	queue_redraw()

func feedback_text() -> String:
	return _feedback

## This is a presentation-route filter, not a permission rule. Main asks it
## before emitting any Sim intent; admitted routes still use Sim's canonical
## topology/access validation and receipts.
func allows_portal(portal_id: String) -> bool:
	return portal_id in PRESENTATION_PORTALS

## Fixed C1 framing is View-only. It reads only the active Probe plane and
## writes only the camera transform; no simulation or portal state is touched.
func apply_fixed_frame(viewport: Vector2, pad: Vector2) -> void:
	if _probe == null or viewport.x <= 1.0 or viewport.y <= 1.0:
		return
	var size := Vector2(64.0, 48.0) * CELL if String(_probe.active_space) == "town" else Vector2(8.0, 6.0) * CELL
	var fit := (viewport - pad) / size
	_probe.cam.zoom = Vector2.ONE * minf(fit.x, fit.y)
	_probe.cam.position = Rect2(Vector2.ZERO, size).get_center()

func state() -> Dictionary:
	if _probe == null:
		return {"space": "", "floor": "", "interactive": false, "label": ""}
	var space := String(_probe.active_space)
	var floor := String(_probe.active_floor)
	if space != "cafe":
		return {"space": space, "floor": floor, "interactive": true, "label": "镇外景"}
	if floor == "2f":
		return {"space": space, "floor": floor, "interactive": false, "label": "咖啡馆 2F · 仅供查看"}
	return {"space": space, "floor": floor, "interactive": true, "label": "咖啡馆 1F · 公共厅"}

func _process(_delta: float) -> void:
	# Probe is the sole active-plane authority. A redraw is ephemeral and cannot
	# affect any simulation observable.
	queue_redraw()

func _draw() -> void:
	var s := state()
	var space := String(s["space"])
	var floor := String(s["floor"])
	if space == "":
		return
	if space == "town":
		_draw_town_frame()
	elif space == "cafe":
		_draw_cafe_frame(floor, bool(s["interactive"]))

func _draw_town_frame() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(64.0, 48.0) * CELL)
	draw_rect(rect, MUTED, false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(24, 42), "C1 · 镇外景 / 咖啡馆入口", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)

func _draw_cafe_frame(floor: String, interactive: bool) -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(8.0, 6.0) * CELL)
	draw_rect(rect, INK if interactive else MUTED, false, 3.0)
	# Architectural-model shell: static, unlit primitives only.  It has no
	# collision or hit-test role; Main keeps its canonical active-plane input.
	for x in range(1, 8):
		draw_line(Vector2(x * CELL, rect.position.y), Vector2(x * CELL, rect.end.y), MUTED, 1.0)
	for y in range(1, 6):
		draw_line(Vector2(rect.position.x, y * CELL), Vector2(rect.end.x, y * CELL), MUTED, 1.0)
	var title := "咖啡馆 1F · 公共厅" if floor == "1f" else "咖啡馆 2F · 仅供查看"
	draw_string(ThemeDB.fallback_font, Vector2(12, 28), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK if interactive else MUTED)
	if floor == "1f":
		draw_rect(Rect2(Vector2(CELL, CELL), Vector2(CELL, CELL)), ACCENT, false, 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(CELL + 4, CELL + 28), "私人楼梯", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ACCENT)
	if _feedback != "":
		draw_string(ThemeDB.fallback_font, Vector2(12, rect.end.y - 12), _feedback, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ACCENT)
