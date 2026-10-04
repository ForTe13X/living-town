extends Node
## Exercise the product input route instead of calling LifeMode callbacks directly.
## Run with: godot --headless --path game res://scenes/player_journey_test.tscn

const CFG := "user://settings.cfg"
const MAIN_SCENE := preload("res://scenes/Main.tscn")

var _fails := 0
var _main: Node2D
var _life: Node
var _transcript: Array[Dictionary] = []
var _inputs: Array[Dictionary] = []
var _evidence_dir := ""
var _frame_count := 0
var _scenario_id := "selection_move_service_cancel_modal"
var _cfg_existed := false
var _cfg_backup := PackedByteArray()

func _ready() -> void:
	call_deferred("_run")

func _pin_settings() -> void:
	_cfg_existed = FileAccess.file_exists(CFG)
	if _cfg_existed:
		_cfg_backup = FileAccess.get_file_as_bytes(CFG)
	var cfg := ConfigFile.new()
	cfg.set_value("backend", "mode", "logic")
	cfg.set_value("sim", "player", false)
	cfg.set_value("sim", "speed", 1.0)
	cfg.save(CFG)

func _restore_settings() -> void:
	if _cfg_existed:
		var f := FileAccess.open(CFG, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_cfg_backup)
			f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))

func _check(name: String, ok: bool, detail: String = "") -> void:
	print("  %s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		_fails += 1
	_record(name, detail, ok)

func _record(name: String, detail: String, ok: bool) -> void:
	_transcript.append({"checkpoint": name, "detail": detail, "pass": ok,
		"tick": Sim.tick_no if Sim != null else -1})

func _wait_frames(count: int = 2) -> void:
	for _i in count:
		await get_tree().process_frame

func _send_key(keycode: int, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	_inputs.append({"kind": "key", "keycode": keycode, "pressed": pressed})
	Input.parse_input_event(event)
	await get_tree().process_frame

func _click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	for is_pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = is_pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if is_pressed else 0
		_inputs.append({"kind": "mouse_left", "position": [point.x, point.y], "pressed": is_pressed,
			"target": control.name})
		get_viewport().push_input(event, true)
		await get_tree().process_frame

func _save_checkpoint(name: String) -> void:
	if _evidence_dir.is_empty():
		return
	var vp := get_viewport()
	if DisplayServer.get_name() != "headless" and vp != null and vp.get_texture() != null:
		var image := vp.get_texture().get_image()
		if image != null and not image.is_empty():
			if image.save_png(_evidence_dir.path_join(name + ".png")) == OK:
				_frame_count += 1
	var tree := _main.get_tree_string_pretty() if _main != null else ""
	var f := FileAccess.open(_evidence_dir.path_join(name + ".tree.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string(tree)
		f.close()

func _find_moves() -> Array[Dictionary]:
	var directions: Array[Dictionary] = [
		{"key": KEY_D, "dir": Vector2i(1, 0)}, {"key": KEY_A, "dir": Vector2i(-1, 0)},
		{"key": KEY_S, "dir": Vector2i(0, 1)}, {"key": KEY_W, "dir": Vector2i(0, -1)}]
	return directions

func _find_service() -> Dictionary:
	for oid: String in Sim.world.get("objects", {}).keys():
		var obj: Dictionary = Sim.world["objects"][oid]
		for action: Dictionary in Sim._life_object_actions(Sim.get_agent(_life.pid), obj):
			if not bool(action.get("ok", false)) or int(action.get("duration", 0)) <= 0:
				continue
			var space := String(obj.get("space", "town"))
			var floor := String(obj.get("floor", "outdoor"))
			var grid: Dictionary = Sim._grid_for(space, floor)
			var pos: Vector2i = obj["pos"]
			for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var cell := pos + dir
				if Sim._cell_walkable(grid, cell):
					return {"id": oid, "space": space, "floor": floor, "pos": cell, "action": action}
	return {}

func _open_focus_menu() -> void:
	await _send_key(KEY_E)
	await _wait_frames(2)

func _run() -> void:
	_pin_settings()
	_evidence_dir = OS.get_environment("LT_JOURNEY_EVIDENCE_DIR")
	if _evidence_dir.is_empty():
		_evidence_dir = ProjectSettings.globalize_path("user://player_journey_evidence")
	DirAccess.make_dir_recursive_absolute(_evidence_dir)
	_main = MAIN_SCENE.instantiate() as Node2D
	add_child(_main)
	await _wait_frames(5)
	_life = _main.get("_life") as Node
	_check("life selection starts in the real Main scene", _life != null and bool(_life.get("selecting")))
	if _life == null:
		_finish()
		return
	_check("resident selection starts on a paused first day", not Sim.running and Sim.tick_no == 0 and Sim.day == 1,
		"running=%s tick=%d day=%d" % [str(Sim.running), Sim.tick_no, Sim.day])
	await get_tree().create_timer(0.25).timeout # Longer than the observer's 0.08-second tick interval.
	_check("resident selection holds the first day while the player thinks", not Sim.running and Sim.tick_no == 0 and Sim.day == 1)
	await _send_key(KEY_4)
	await get_tree().create_timer(0.25).timeout
	_check("observer speed shortcut cannot advance the resident picker", not Sim.running and Sim.tick_no == 0 and Sim.day == 1)
	# Reproduce a bank card opened before selection (the --bank-panel CLI order).
	Sim.running = true
	_main.call("_open_bank_panel")
	var bank_panel: Panel = _main.get("_bank_panel") as Panel
	_check("preselection bank card opens", bank_panel != null and bank_panel.visible)
	_life.begin_select()
	await _wait_frames(2)
	_check("resident selection closes earlier bank card and pauses", bank_panel != null and not bank_panel.visible
		and not Sim.running and Sim.tick_no == 0 and Sim.day == 1)
	var cards: Array = _life.get("_sel_cards")
	var selected_before := String(_life.get("_sel_ids")[0])
	var selected_after := String(_life.get("_sel_ids")[1])
	await _click(cards[1] as Control)
	await _wait_frames()
	_check("mouse click selects a resident card", int(_life.get("_sel_idx")) == 1,
		"%s -> %s" % [selected_before, String(_life.get("_sel_ids")[int(_life.get("_sel_idx"))])])
	await _save_checkpoint("01_selection")
	await _send_key(KEY_ENTER)
	await _wait_frames(3)
	_check("Enter starts the selected resident", bool(_life.get("active")) and String(_life.get("pid")) == selected_after,
		"resident=%s active=%s controlled=%s" % [String(_life.get("pid")), str(_life.get("active")), Sim.controlled_id])
	_check("starting a resident resumes the slower life clock", Sim.running and is_equal_approx(Sim.tick_interval, 0.5))
	await _save_checkpoint("02_started")

	# Keep the journey's controlled actor independent from autonomous dialogue
	# at startup; the movement interaction itself remains fully input driven.
	var journey_actor: Dictionary = Sim.get_agent(String(_life.get("pid")))
	journey_actor["talking"] = 0
	var current_option = journey_actor.get("option")
	if current_option is Dictionary and String(current_option.get("kind", "")) == "social":
		journey_actor["option"] = null
	var moves: Array[Dictionary] = _find_moves()
	var before: Vector2i = Sim.get_agent(String(_life.get("pid")))["pos"]
	var movement_event_reached := false
	var move: Dictionary = {}
	for candidate: Dictionary in moves:
		await _send_key(int(candidate["key"]))
		movement_event_reached = movement_event_reached or (_life.get("_move_keys") as Dictionary).has(int(candidate["key"]))
		# Movement is throttled by MOVE_STEP in process time; headless frame
		# callbacks can complete faster than that interval, so hold past one step.
		await get_tree().create_timer(0.3).timeout
		await _send_key(int(candidate["key"]), false)
		await _wait_frames(2)
		var current: Vector2i = Sim.get_agent(String(_life.get("pid")))["pos"]
		if current != before:
			move = candidate
			break
	var after: Vector2i = Sim.get_agent(String(_life.get("pid")))["pos"]
	_check("movement keydown reaches the LifeMode input route", movement_event_reached)
	var displacement := after - before
	var moved_in_requested_direction := not move.is_empty() and displacement != Vector2i.ZERO \
		and signi(displacement.x) == int(move["dir"].x) and signi(displacement.y) == int(move["dir"].y)
	_check("held movement key moves the controlled resident", moved_in_requested_direction,
		"%s -> %s via %s; running=%s cd=%.3f t=%.3f held=%s" % [str(before), str(after),
		str(move.get("key", "none")), str(Sim.running), float(_life.get("_move_cd")),
		float(_life.get("_t")), str((_life.get("_move_keys") as Dictionary).keys())])
	await _save_checkpoint("03_moved")

	var service := _find_service()
	_check("journey fixture finds a usable authored service", not service.is_empty())
	if service.is_empty():
		_finish()
		return
	# Fixture setup places the controlled actor beside an authored service. All
	# journey actions after this setup are dispatched through Input.parse_input_event.
	var actor: Dictionary = Sim.get_agent(String(_life.get("pid")))
	actor["space"] = service["space"]
	actor["floor"] = service["floor"]
	actor["option"] = null
	actor["talking"] = 0
	Sim._move_agent(actor, service["pos"])
	await _wait_frames(5)
	_life.call("_refresh_inter")
	var interactions: Array = Sim.life_interactions()
	var target_visible := false
	for entry: Dictionary in interactions:
		if String(entry.get("id", "")) == String(service["id"]):
			target_visible = true
	_check("nearby service is discoverable through the interaction list", target_visible,
		"target=%s interactions=%d" % [String(service["id"]), interactions.size()])
	if not target_visible:
		_finish()
		return
	for _focus_step in range(interactions.size() + 1):
		if String(_life.get("_focus_id")) == String(service["id"]):
			break
		await _send_key(KEY_TAB)
	await _open_focus_menu()
	_check("E opens the focused service modal and pauses the world", bool(_life.get("_modal_open"))
		and not Sim.running and String(_life.get("_modal_entry").get("id", "")) == String(service["id"]))
	await _save_checkpoint("04_modal_open")
	await _send_key(KEY_ESCAPE)
	await _wait_frames()
	_check("Escape closes the modal and restores simulation state", not bool(_life.get("_modal_open")) and Sim.running)
	await _open_focus_menu()
	var action_button: Button
	for child: Node in _life.get("_modal").get_children():
		if child is Button and not (child as Button).disabled:
			action_button = child as Button
			break
	var chosen_action := String(service["action"].get("action", ""))
	_check("service modal exposes its authored action", action_button != null, chosen_action)
	if action_button == null:
		_finish()
		return
	await _click(action_button)
	await _wait_frames(3)
	_check("mouse click starts the selected service action", Sim.get_agent(String(_life.get("pid"))).get("option") is Dictionary,
		"action=%s" % chosen_action)
	await _save_checkpoint("05_interaction_started")
	await _send_key(KEY_Q)
	await _wait_frames(2)
	_check("Q cancels the service through the routed input path", Sim.get_agent(String(_life.get("pid"))).get("option") == null)
	await _save_checkpoint("06_action_cancelled")
	await _send_key(KEY_C)
	var change_tick := Sim.tick_no
	_check("changing residents pauses the world", bool(_life.get("selecting")) and not Sim.running)
	await get_tree().create_timer(0.65).timeout # Longer than the life mode's 0.5-second tick interval.
	_check("resident picker holds the current time", Sim.tick_no == change_tick and not Sim.running)
	await _send_key(KEY_ESCAPE)
	_check("leaving the picker resumes the previous resident", bool(_life.get("active")) and Sim.running
		and String(_life.get("pid")) == selected_after)
	_finish()

func _finish() -> void:
	if not _evidence_dir.is_empty():
		var evidence := {"schema": "living-town.player-journey-evidence/1", "scenario": _scenario_id,
			"input_route": "Input.parse_input_event -> Godot viewport -> Main/LifeMode handlers",
			"host_os_input_covered": false, "frame_count": _frame_count, "failures": _fails,
			"inputs": _inputs, "transcript": _transcript}
		var file := FileAccess.open(_evidence_dir.path_join("journey.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(evidence, "  "))
			file.close()
	_restore_settings()
	print("=== PLAYER JOURNEY: %s (%d failures) ===" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)
