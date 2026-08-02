class_name S16Compositor
extends Control
## Fail-closed, read-only compositor for the committed S16P narrative trace.
## It never owns simulation state and never writes trace data back to disk.

signal action_dispatched(action_id: String, payload: Dictionary)

const BANNER_TEXT := "NARRATIVE LAB · NOT SIM · READ-ONLY COMMITTED TRACE"
const FIXTURE_PATH := "res://narrative_lab/s16/fixtures/s16_compositor_projection.json"
const FIXTURE_SHA256 := "90ddd379d67b3e251ac0113a548706c95f840ae6c5aea0ee50a587a2ab3e8198"
const FIXTURE_LAB_COMMIT := "1a195e06f1dd6b6aef2668906d6a816b8799e67b"
const FIXTURE_LAB_PATH := "artifacts/integration/s16_compositor_projection.json"

const ACTION_FOCUS_ROLE := "focus_role"
const ACTION_SELECT_NODE := "select_node"
const ACTION_VIEW_TRAVERSE := "view_traverse"
const ACTION_COMPARE_HANDOFF := "compare_handoff"
const ACTION_SCRUB_REPLAY := "scrub_replay"
const ACTIONS := [
	ACTION_FOCUS_ROLE,
	ACTION_SELECT_NODE,
	ACTION_VIEW_TRAVERSE,
	ACTION_COMPARE_HANDOFF,
	ACTION_SCRUB_REPLAY,
]
const SNAPSHOT_KEYS := [
	"role_id",
	"now_node",
	"visible_nodes",
	"visible_edges",
	"carried_fragment_ids",
	"receipt_ids",
	"open_request_ids",
	"route_hint",
	"clock",
	"status",
]
const TRANSITION_ID_KEYS := [
	"actor_role_id",
	"recipient_role_id",
	"requested_action_id",
	"resolved_action_id",
	"target_id",
	"fragment_id",
]
const FRAME_HASH_KEYS := ["state_sha256", "ledger_sha256", "chain_hash"]
const SIDECAR_KEYS := [
	"actor_role_id",
	"recipient_role_id",
	"requested_action_id",
	"resolved_action_id",
	"target_id",
	"fragment_id",
	"state_sha256",
	"ledger_sha256",
	"chain_hash",
]
const MIN_TARGET_PX := 44.0
const MAX_CONTENT_WIDTH := 1560.0
const SINGLE_PANE_BREAKPOINT := 1200.0

const BG := Color("101219")
const PANEL := Color("191b25")
const BANNER_BG := Color("090b10")
const ACCENT := Color("d88b57")
const INK := Color("f2e5c5")
const MUTED := Color("aaa5b5")
const EDGE := Color("4d495d")

var fatal_errors: Array[String] = []
var _trace: Dictionary = {}
var _frames: Array = []
var _loaded := false
var _offset := 0
var _focus_role_id := ""
var _selected_node_id := ""
var _view_mode := "role"
var _single_tab := "graph"
var _source_trace_fingerprint := ""
var _dispatch_total := 0
var _dispatch_counts := {}
var _last_component_snapshot_keys: Array[String] = []
var _last_sidecar_keys: Array[String] = []
var _touch_suppressed_action := ""

var _background: ColorRect
var _banner: ColorRect
var _banner_label: Label
var _content: Control
var _toolbar: Control
var _graph: WebMazeGraph
var _card: RolePOVCard
var _sidecar_panel: ColorRect
var _sidecar_label: Label
var _status_label: Label
var _context_label: Label
var _tab_graph: Button
var _tab_card: Button
var _buttons: Dictionary = {}
var _all_action_buttons: Array[Button] = []


func _ready() -> void:
	set_process_input(true)
	set_process_unhandled_key_input(true)
	_build_ui()
	resized.connect(_layout_ui)
	_layout_ui()
	if load_committed_trace():
		_update_view()
	else:
		_render_failure()


func load_committed_trace(path := FIXTURE_PATH, expected_sha256 := FIXTURE_SHA256) -> bool:
	_clear_trace()
	if not FileAccess.file_exists(path):
		fatal_errors.append("FIXTURE_MISSING:%s" % path)
		_render_failure_if_ready()
		return false
	var observed_sha256 := FileAccess.get_sha256(path)
	if observed_sha256 != expected_sha256:
		fatal_errors.append(
			"FIXTURE_HASH_MISMATCH:expected=%s observed=%s" % [expected_sha256, observed_sha256]
		)
		_render_failure_if_ready()
		return false
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		fatal_errors.append("FIXTURE_UNREADABLE:%s" % path)
		_render_failure_if_ready()
		return false
	var parsed = JSON.parse_string(handle.get_as_text())
	handle.close()
	if not parsed is Dictionary:
		fatal_errors.append("FIXTURE_JSON_ROOT_INVALID")
		_render_failure_if_ready()
		return false
	var document: Dictionary = parsed
	var errors := validate_document(document)
	if not errors.is_empty():
		fatal_errors.assign(errors)
		_render_failure_if_ready()
		return false
	_trace = document.duplicate(true)
	_frames = (_trace["frames"] as Array).duplicate(true)
	_source_trace_fingerprint = JSON.stringify(_trace).sha256_text()
	_loaded = true
	_offset = 0
	_focus_role_id = String((_frames[0]["roles"] as Array)[0]["role_id"])
	_selected_node_id = String((_frames[0]["roles"] as Array)[0]["now_node"])
	_view_mode = "role"
	_update_view_if_ready()
	return true


func validate_document(document: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if document.get("schema") != "living-town-s16-compositor-projection/v1":
		errors.append("SCHEMA_INVALID")
	if document.get("authority") != "projection_only":
		errors.append("AUTHORITY_INVALID")
	if document.get("mode") != "READ_ONLY_COMMITTED_TRACE":
		errors.append("MODE_INVALID")
	if document.get("simulation") != "NOT_SIM":
		errors.append("SIMULATION_BOUNDARY_INVALID")
	if document.get("production_gate") is not bool or bool(document.get("production_gate")):
		errors.append("PRODUCTION_GATE_INVALID")
	if document.get("result") != "PASS":
		errors.append("PROJECTION_RESULT_INVALID")
	var frames = document.get("frames")
	if not frames is Array or frames.size() != 13:
		errors.append("FRAME_COUNT_INVALID")
		return errors
	for index in range(frames.size()):
		var frame = frames[index]
		if not frame is Dictionary:
			errors.append("FRAME_SHAPE_INVALID:%d" % index)
			continue
		if frame.get("offset") != index:
			errors.append("FRAME_OFFSET_INVALID:%d" % index)
		for hash_key in FRAME_HASH_KEYS:
			if not _is_sha256(frame.get(hash_key)):
				errors.append("FRAME_HASH_INVALID:%d:%s" % [index, hash_key])
		var roles = frame.get("roles")
		if not roles is Array or roles.size() != 2:
			errors.append("FRAME_ROLES_INVALID:%d" % index)
		else:
			for role in roles:
				errors.append_array(_snapshot_errors(role, index))
		var transition = frame.get("transition")
		if index == 0:
			if transition != null:
				errors.append("GENESIS_TRANSITION_NOT_NULL")
		elif not transition is Dictionary:
			errors.append("TRANSITION_MISSING:%d" % index)
		else:
			if transition.get("outcome") != "committed":
				errors.append("TRANSITION_NOT_COMMITTED:%d" % index)
			for key in TRANSITION_ID_KEYS:
				if transition.has(key) and transition[key] != null and not transition[key] is String:
					errors.append("TRANSITION_ID_INVALID:%d:%s" % [index, key])
	errors.append_array(_handoff_errors(document))
	errors.sort()
	return errors


func _snapshot_errors(value, offset: int) -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary:
		return ["SNAPSHOT_SHAPE_INVALID:%d" % offset]
	var snapshot: Dictionary = value
	if snapshot.size() != SNAPSHOT_KEYS.size():
		errors.append("SNAPSHOT_FIELD_COUNT_INVALID:%d" % offset)
	for key in snapshot.keys():
		if not String(key) in SNAPSHOT_KEYS:
			errors.append("SNAPSHOT_FIELD_NOT_ALLOWED:%d:%s" % [offset, String(key)])
	for key in SNAPSHOT_KEYS:
		if not snapshot.has(key):
			errors.append("SNAPSHOT_FIELD_MISSING:%d:%s" % [offset, key])
	if not errors.is_empty():
		return errors
	for key in ["visible_nodes", "visible_edges", "carried_fragment_ids", "receipt_ids", "open_request_ids", "route_hint"]:
		if not snapshot[key] is Array:
			errors.append("SNAPSHOT_FIELD_TYPE:%d:%s" % [offset, key])
	for key in ["role_id", "now_node", "status"]:
		if not snapshot[key] is String:
			errors.append("SNAPSHOT_FIELD_TYPE:%d:%s" % [offset, key])
	if not snapshot["clock"] is Dictionary:
		errors.append("SNAPSHOT_FIELD_TYPE:%d:clock" % offset)
	return errors


func _handoff_errors(document: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var gate = document.get("handoff_gate")
	if not gate is Dictionary or gate.get("atomic_same_frame") is not bool or not bool(gate.get("atomic_same_frame")):
		return ["HANDOFF_GATE_INVALID"]
	var from_offset := int(gate.get("from_offset", -1))
	var to_offset := int(gate.get("to_offset", -1))
	var frames: Array = document["frames"]
	if from_offset < 0 or to_offset != from_offset + 1 or to_offset >= frames.size():
		return ["HANDOFF_OFFSETS_INVALID"]
	var source_id := String(gate.get("source_role_id", ""))
	var recipient_id := String(gate.get("recipient_role_id", ""))
	var fragment_id := String(gate.get("fragment_id", ""))
	var before_source := _find_role(frames[from_offset], source_id)
	var after_source := _find_role(frames[to_offset], source_id)
	var before_recipient := _find_role(frames[from_offset], recipient_id)
	var after_recipient := _find_role(frames[to_offset], recipient_id)
	if before_source.is_empty() or after_source.is_empty() or before_recipient.is_empty() or after_recipient.is_empty():
		return ["HANDOFF_ROLE_MISSING"]
	var atomic := (
		fragment_id in (before_source["carried_fragment_ids"] as Array)
		and fragment_id not in (after_source["carried_fragment_ids"] as Array)
		and fragment_id not in (before_recipient["carried_fragment_ids"] as Array)
		and fragment_id in (after_recipient["carried_fragment_ids"] as Array)
	)
	var transition = frames[to_offset].get("transition")
	atomic = atomic and transition is Dictionary
	if transition is Dictionary:
		atomic = (
			atomic
			and transition.get("outcome") == "committed"
			and transition.get("actor_role_id") == source_id
			and transition.get("recipient_role_id") == recipient_id
			and transition.get("fragment_id") == fragment_id
		)
	if not atomic:
		errors.append("HANDOFF_NOT_ATOMIC")
	return errors


func _dispatch(action_id: String, payload := {}) -> bool:
	if not _loaded or not action_id in ACTIONS or not payload is Dictionary:
		return false
	var accepted := false
	match action_id:
		ACTION_FOCUS_ROLE:
			accepted = _dispatch_focus_role(payload)
		ACTION_SELECT_NODE:
			accepted = _dispatch_select_node(payload)
		ACTION_VIEW_TRAVERSE:
			accepted = _dispatch_view_traverse()
		ACTION_COMPARE_HANDOFF:
			accepted = _dispatch_compare_handoff()
		ACTION_SCRUB_REPLAY:
			accepted = _dispatch_scrub_replay(payload)
	if not accepted:
		return false
	_dispatch_total += 1
	_dispatch_counts[action_id] = int(_dispatch_counts.get(action_id, 0)) + 1
	_update_view_if_ready()
	action_dispatched.emit(action_id, payload.duplicate(true))
	return true


func _dispatch_focus_role(payload: Dictionary) -> bool:
	var roles: Array = _frame_at(_offset)["roles"]
	var requested := String(payload.get("role_id", ""))
	if requested.is_empty():
		var current_index := 0
		for index in range(roles.size()):
			if roles[index]["role_id"] == _focus_role_id:
				current_index = index
		requested = String(roles[(current_index + 1) % roles.size()]["role_id"])
	if _find_role(_frame_at(_offset), requested).is_empty():
		return false
	_focus_role_id = requested
	_selected_node_id = String(_find_role(_frame_at(_offset), requested)["now_node"])
	_view_mode = "role"
	return true


func _dispatch_select_node(payload: Dictionary) -> bool:
	if payload.has("pane"):
		var pane := String(payload["pane"])
		if not pane in ["graph", "card"]:
			return false
		_single_tab = pane
		return true
	var role := _find_role(_frame_at(_offset), _focus_role_id)
	if role.is_empty():
		return false
	var visible: Array = role["visible_nodes"]
	var requested := String(payload.get("node_id", ""))
	if requested.is_empty():
		var current_index := visible.find(_selected_node_id)
		requested = String(visible[(current_index + 1) % visible.size()])
	if not requested in visible:
		return false
	_selected_node_id = requested
	_view_mode = "node"
	return true


func _dispatch_view_traverse() -> bool:
	for frame in _frames:
		var transition = frame.get("transition")
		if transition is Dictionary and transition.get("resolved_action_id") == "action.traverse":
			_offset = int(frame["offset"])
			_focus_role_id = String(transition.get("actor_role_id"))
			_selected_node_id = String(_find_role(frame, _focus_role_id).get("now_node", ""))
			_view_mode = "traverse"
			return true
	return false


func _dispatch_compare_handoff() -> bool:
	var gate: Dictionary = _trace["handoff_gate"]
	_offset = int(gate["to_offset"])
	_focus_role_id = String(gate["recipient_role_id"])
	_selected_node_id = String(_find_role(_frame_at(_offset), _focus_role_id)["now_node"])
	_view_mode = "handoff"
	return true


func _dispatch_scrub_replay(payload: Dictionary) -> bool:
	var requested := int(payload.get("offset", (_offset + int(payload.get("delta", 1))) % _frames.size()))
	if requested < 0 or requested >= _frames.size():
		return false
	_offset = requested
	var roles: Array = _frame_at(_offset)["roles"]
	if _find_role(_frame_at(_offset), _focus_role_id).is_empty():
		_focus_role_id = String(roles[0]["role_id"])
	_selected_node_id = String(_find_role(_frame_at(_offset), _focus_role_id)["now_node"])
	_view_mode = "replay"
	return true


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		for button in _all_action_buttons:
			if button.visible and button.get_global_rect().has_point(event.position):
				var action_id := String(button.get_meta("action_id", ""))
				var payload: Dictionary = button.get_meta("payload", {}).duplicate(true)
				_touch_suppressed_action = action_id
				_dispatch(action_id, payload)
				get_viewport().set_input_as_handled()
				call_deferred("_clear_touch_suppression", action_id)
				break


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var action_id := ""
	match event.keycode:
		KEY_F, KEY_1:
			action_id = ACTION_FOCUS_ROLE
		KEY_N, KEY_2:
			action_id = ACTION_SELECT_NODE
		KEY_T, KEY_3:
			action_id = ACTION_VIEW_TRAVERSE
		KEY_H, KEY_4:
			action_id = ACTION_COMPARE_HANDOFF
		KEY_R, KEY_5:
			action_id = ACTION_SCRUB_REPLAY
	if not action_id.is_empty() and _dispatch(action_id):
		get_viewport().set_input_as_handled()


func _on_button_pressed(action_id: String, payload: Dictionary) -> void:
	if _touch_suppressed_action == action_id:
		_touch_suppressed_action = ""
		return
	_dispatch(action_id, payload)


func _clear_touch_suppression(action_id: String) -> void:
	if _touch_suppressed_action == action_id:
		_touch_suppressed_action = ""


func _build_ui() -> void:
	_background = ColorRect.new()
	_background.color = BG
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	_banner = ColorRect.new()
	_banner.color = BANNER_BG
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)
	var accent := ColorRect.new()
	accent.name = "permanent_not_sim_accent"
	accent.color = ACCENT
	accent.position = Vector2(0, 52)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(accent)
	_banner_label = _label(BANNER_TEXT, 18, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_banner_label.name = "permanent_not_sim_banner"
	_banner_label.position = Vector2(12, 3)
	_banner.add_child(_banner_label)

	_toolbar = Control.new()
	_toolbar.name = "five_action_toolbar"
	add_child(_toolbar)
	var labels := {
		ACTION_FOCUS_ROLE: "1  FOCUS ROLE",
		ACTION_SELECT_NODE: "2  SELECT NODE",
		ACTION_VIEW_TRAVERSE: "3  VIEW TRAVERSE",
		ACTION_COMPARE_HANDOFF: "4  COMPARE HANDOFF",
		ACTION_SCRUB_REPLAY: "5  SCRUB REPLAY",
	}
	for action_id in ACTIONS:
		var button := _action_button(String(labels[action_id]), action_id)
		button.name = "action_%s" % action_id
		_toolbar.add_child(button)
		_buttons[action_id] = button

	_context_label = _label("", 16, MUTED)
	_context_label.name = "committed_trace_context"
	add_child(_context_label)

	_content = Control.new()
	_content.name = "responsive_content"
	add_child(_content)
	_tab_graph = _action_button("WEB MAZE", ACTION_SELECT_NODE, {"pane": "graph"})
	_tab_graph.name = "single_tab_graph"
	_content.add_child(_tab_graph)
	_tab_card = _action_button("ROLE POV", ACTION_SELECT_NODE, {"pane": "card"})
	_tab_card.name = "single_tab_card"
	_content.add_child(_tab_card)
	_graph = WebMazeGraph.new()
	_graph.name = "s06_web_maze_graph"
	_content.add_child(_graph)
	_card = RolePOVCard.new()
	_card.name = "s06_role_pov_card"
	_content.add_child(_card)
	_sidecar_panel = ColorRect.new()
	_sidecar_panel.name = "transition_id_hash_sidecar"
	_sidecar_panel.color = PANEL
	_sidecar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_sidecar_panel)
	_sidecar_label = _label("", 13, MUTED)
	_sidecar_label.position = Vector2(14, 8)
	_sidecar_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sidecar_panel.add_child(_sidecar_label)

	_status_label = _label("", 14, ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	_status_label.name = "read_only_status"
	add_child(_status_label)


func _layout_ui() -> void:
	if _background == null:
		return
	_background.position = Vector2.ZERO
	_background.size = size
	_banner.position = Vector2.ZERO
	_banner.size = Vector2(size.x, 54)
	_banner_label.size = Vector2(size.x - 24, 46)
	(_banner.get_node("permanent_not_sim_accent") as ColorRect).size = Vector2(size.x, 2)
	var content_width := minf(MAX_CONTENT_WIDTH, maxf(0.0, size.x - 32.0))
	var center_x := floorf((size.x - content_width) * 0.5)
	_toolbar.position = Vector2(center_x, 64)
	_toolbar.size = Vector2(content_width, 48)
	var gap := 8.0
	var button_width := floorf((content_width - gap * 4.0) / 5.0)
	for index in range(ACTIONS.size()):
		var button: Button = _buttons[ACTIONS[index]]
		button.position = Vector2(index * (button_width + gap), 0)
		button.size = Vector2(button_width, 48)
	_context_label.position = Vector2(center_x, 116)
	_context_label.size = Vector2(content_width * 0.72, 26)
	_status_label.position = Vector2(center_x + content_width * 0.70, 116)
	_status_label.size = Vector2(content_width * 0.30, 26)
	_content.position = Vector2(center_x, 146)
	_content.size = Vector2(content_width, maxf(300.0, size.y - 162.0))
	var single_pane := size.x < SINGLE_PANE_BREAKPOINT
	var sidecar_height := 112.0
	if single_pane:
		_tab_graph.visible = true
		_tab_card.visible = true
		_tab_graph.position = Vector2(0, 0)
		_tab_graph.size = Vector2((content_width - gap) * 0.5, MIN_TARGET_PX)
		_tab_card.position = Vector2(_tab_graph.size.x + gap, 0)
		_tab_card.size = _tab_graph.size
		var pane_rect := Rect2(0, MIN_TARGET_PX + 8.0, content_width, _content.size.y - MIN_TARGET_PX - sidecar_height - 16.0)
		_graph.position = pane_rect.position
		_graph.size = pane_rect.size
		_card.position = pane_rect.position
		_card.size = pane_rect.size
		_graph.visible = _single_tab == "graph"
		_card.visible = _single_tab == "card"
	else:
		_tab_graph.visible = false
		_tab_card.visible = false
		var pane_width := floorf((content_width - gap) * 0.5)
		var pane_height := _content.size.y - sidecar_height - 8.0
		_graph.visible = true
		_card.visible = true
		_graph.position = Vector2.ZERO
		_graph.size = Vector2(pane_width, pane_height)
		_card.position = Vector2(pane_width + gap, 0)
		_card.size = Vector2(content_width - pane_width - gap, pane_height)
	_sidecar_panel.position = Vector2(0, _content.size.y - sidecar_height)
	_sidecar_panel.size = Vector2(content_width, sidecar_height)
	_sidecar_label.size = Vector2(content_width - 28, sidecar_height - 16)
	queue_redraw()


func _update_view() -> void:
	if not _loaded:
		_render_failure()
		return
	var frame := _frame_at(_offset)
	var role := _find_role(frame, _focus_role_id)
	if role.is_empty():
		fatal_errors.append("FOCUS_ROLE_MISSING:%s" % _focus_role_id)
		_render_failure()
		return
	var snapshot := _project_snapshot(role)
	if not _graph.set_snapshot(snapshot.duplicate(true)) or not _card.set_snapshot(snapshot.duplicate(true)):
		fatal_errors.append("S06_COMPONENT_REJECTED_SNAPSHOT")
		_render_failure()
		return
	_last_component_snapshot_keys.clear()
	for key in snapshot.keys():
		_last_component_snapshot_keys.append(String(key))
	_last_component_snapshot_keys.sort()
	var sidecar := _transition_sidecar(frame)
	_last_sidecar_keys.clear()
	for key in sidecar.keys():
		_last_sidecar_keys.append(String(key))
	_last_sidecar_keys.sort()
	_context_label.text = "OFFSET %02d / 12   ROLE %s   NODE %s   VIEW %s" % [
		_offset,
		_focus_role_id,
		_selected_node_id,
		_view_mode.to_upper(),
	]
	_status_label.text = "COMMITTED TRACE · NO WRITEBACK"
	var lines: Array[String] = ["TRANSITION SIDECAR · WHITELISTED IDs / HASHES ONLY"]
	for key in SIDECAR_KEYS:
		if sidecar.has(key) and sidecar[key] != null:
			var value := String(sidecar[key])
			if key.ends_with("sha256") or key == "chain_hash":
				value = value.left(18) + "…"
			lines.append("%s=%s" % [key, value])
	_sidecar_label.text = "    ".join(lines)
	_layout_ui()


func _render_failure() -> void:
	if _context_label == null:
		return
	_context_label.text = "FAIL CLOSED · SOURCE TRACE UNAVAILABLE"
	_status_label.text = "%d ERROR(S) · NO FALLBACK" % fatal_errors.size()
	_sidecar_label.text = "\n".join(fatal_errors)
	_graph.visible = false
	_card.visible = false


func _render_failure_if_ready() -> void:
	if is_node_ready():
		_render_failure()


func _update_view_if_ready() -> void:
	if is_node_ready():
		_update_view()


func _clear_trace() -> void:
	fatal_errors.clear()
	_trace.clear()
	_frames.clear()
	_loaded = false
	_offset = 0
	_focus_role_id = ""
	_selected_node_id = ""
	_source_trace_fingerprint = ""


func _project_snapshot(role: Dictionary) -> Dictionary:
	var snapshot := {}
	for key in SNAPSHOT_KEYS:
		var value = role[key]
		snapshot[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	return snapshot


func _transition_sidecar(frame: Dictionary) -> Dictionary:
	var sidecar := {}
	var transition = frame.get("transition")
	if transition is Dictionary:
		for key in TRANSITION_ID_KEYS:
			if transition.has(key):
				sidecar[key] = transition[key]
	for key in FRAME_HASH_KEYS:
		sidecar[key] = frame[key]
	return sidecar


func _frame_at(offset: int) -> Dictionary:
	return _frames[offset]


func _find_role(frame: Dictionary, role_id: String) -> Dictionary:
	var roles = frame.get("roles", [])
	if roles is Array:
		for role in roles:
			if role is Dictionary and role.get("role_id") == role_id:
				return role
	return {}


func _is_sha256(value) -> bool:
	if not value is String or value.length() != 64:
		return false
	for index in range(value.length()):
		var character: String = value.substr(index, 1).to_lower()
		if not character in "0123456789abcdef":
			return false
	return true


func _action_button(text_value: String, action_id: String, payload := {}) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(MIN_TARGET_PX, MIN_TARGET_PX)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.set_meta("action_id", action_id)
	button.set_meta("payload", payload.duplicate(true))
	button.pressed.connect(_on_button_pressed.bind(action_id, payload.duplicate(true)))
	_all_action_buttons.append(button)
	return button


func _label(text_value: String, font_size: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func source_receipt() -> Dictionary:
	return {
		"lab_commit": FIXTURE_LAB_COMMIT,
		"lab_path": FIXTURE_LAB_PATH,
		"sha256": FIXTURE_SHA256,
	}


func is_loaded() -> bool:
	return _loaded


func trace_fingerprint() -> String:
	return JSON.stringify(_trace).sha256_text() if _loaded else ""


func trace_document_for_test() -> Dictionary:
	return _trace.duplicate(true)


func source_trace_unchanged() -> bool:
	return _loaded and trace_fingerprint() == _source_trace_fingerprint


func frame_fingerprint() -> String:
	if not _loaded:
		return ""
	return "%02d|%s|%s|%s|%s" % [
		_offset,
		_focus_role_id,
		_graph.snapshot_fingerprint(),
		_card.snapshot_fingerprint(),
		JSON.stringify(_transition_sidecar(_frame_at(_offset))).sha256_text(),
	]


func dispatch_for_test(action_id: String, payload := {}) -> bool:
	return _dispatch(action_id, payload)


func current_offset() -> int:
	return _offset


func dispatch_total() -> int:
	return _dispatch_total


func dispatch_count(action_id: String) -> int:
	return int(_dispatch_counts.get(action_id, 0))


func component_snapshot_keys() -> Array[String]:
	return _last_component_snapshot_keys.duplicate()


func sidecar_keys() -> Array[String]:
	return _last_sidecar_keys.duplicate()


func action_button(action_id: String) -> Button:
	return _buttons.get(action_id)


func input_button_press_for_test(action_id: String) -> void:
	var button := action_button(action_id)
	if button != null:
		button.pressed.emit()


func input_key_for_test(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_unhandled_key_input(event)


func input_screen_touch_for_test(action_id: String) -> void:
	var button := action_button(action_id)
	if button == null:
		return
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = button.get_global_rect().get_center()
	event.pressed = true
	_input(event)
	# Model the mouse event that a touch-emulation layer may synthesize.  The
	# button callback must consume the guard instead of dispatching twice.
	button.pressed.emit()


func layout_receipt() -> Dictionary:
	var center_width := minf(MAX_CONTENT_WIDTH, maxf(0.0, size.x - 32.0))
	return {
		"viewport": [int(size.x), int(size.y)],
		"mode": "single_pane_tabs" if size.x < SINGLE_PANE_BREAKPOINT else "dual_pane",
		"content_width": int(center_width),
		"content_x": int(floorf((size.x - center_width) * 0.5)),
		"max_content_width": int(MAX_CONTENT_WIDTH),
		"targets_at_least_44px": all_targets_at_least_44px(),
	}


func all_targets_at_least_44px() -> bool:
	for button in _all_action_buttons:
		if button.visible and (button.size.x < MIN_TARGET_PX or button.size.y < MIN_TARGET_PX):
			return false
	return true
