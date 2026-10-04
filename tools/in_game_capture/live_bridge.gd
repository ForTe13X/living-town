extends SceneTree
## External observation/action harness. Keep this script outside game/ so capture
## instrumentation cannot enter the exported product package.
## Product input passes through the Godot viewport; no Sim fields are set here.

const COMMAND_SCHEMA := "living-town.agent-command/1"
const OBSERVATION_SCHEMA := "living-town.agent-observation/1"
const RECEIPT_SCHEMA := "living-town.agent-receipt/1"
const KEY_CODES := {
	"LEFT": KEY_LEFT, "RIGHT": KEY_RIGHT, "UP": KEY_UP, "DOWN": KEY_DOWN,
	"ENTER": KEY_ENTER, "ESCAPE": KEY_ESCAPE, "TAB": KEY_TAB,
	"E": KEY_E, "W": KEY_W, "A": KEY_A, "S": KEY_S, "D": KEY_D,
	"Q": KEY_Q, "SPACE": KEY_SPACE, "1": KEY_1, "2": KEY_2,
	"3": KEY_3, "4": KEY_4, "F5": KEY_F5, "F8": KEY_F8,
}

var out_dir := ""
var commands_dir := ""
var observations_dir := ""
var receipts_dir := ""
var processed_dir := ""
var rejected_dir := ""
var idle_timeout_sec := 90
var expected_user_dir_name := ""
var main: Node2D
var life: Node
var sim: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--bridge-dir" and i + 1 < args.size():
			out_dir = args[i + 1]
		elif args[i] == "--idle-timeout-sec" and i + 1 < args.size():
			idle_timeout_sec = clampi(int(args[i + 1]), 10, 900)
		elif args[i] == "--expected-user-dir-name" and i + 1 < args.size():
			expected_user_dir_name = args[i + 1]
	if out_dir.is_empty() or not out_dir.is_absolute_path() or DisplayServer.get_name() == "headless":
		push_error("BRIDGE requires an absolute --bridge-dir and a rendered display")
		quit(2)
		return
	var user_dir := OS.get_user_data_dir().replace("\\", "/")
	if not expected_user_dir_name.begins_with("LivingTownCapture_") or \
			user_dir.get_file() != expected_user_dir_name:
		push_error("BRIDGE refused a non-isolated user:// directory: " + OS.get_user_data_dir())
		quit(2)
		return
	commands_dir = out_dir.path_join("commands")
	observations_dir = out_dir.path_join("observations")
	receipts_dir = out_dir.path_join("receipts")
	processed_dir = out_dir.path_join("processed")
	rejected_dir = out_dir.path_join("rejected")
	for path in [commands_dir, observations_dir, receipts_dir, processed_dir, rejected_dir]:
		if DirAccess.make_dir_recursive_absolute(path) != OK:
			push_error("BRIDGE cannot create " + path)
			quit(2)
			return
	main = load("res://scenes/Main.tscn").instantiate() as Node2D
	if main == null:
		push_error("BRIDGE cannot instantiate Main")
		quit(2)
		return
	root.add_child(main)
	for i in 5:
		await process_frame
	sim = root.get_node_or_null("Sim")
	life = main.get("_life") as Node
	if sim == null or life == null or not await _capture_observation(0):
		_write_json(out_dir.path_join("terminal.json"), {"status": "startup_failed"})
		quit(2)
		return
	print("BRIDGE_READY " + out_dir)
	print("BRIDGE_USER_DIR " + OS.get_user_data_dir())
	var expected := 1
	var idle_since := Time.get_ticks_msec()
	while true:
		_reject_stale(expected)
		var command_path := commands_dir.path_join("%06d.json" % expected)
		if not FileAccess.file_exists(command_path):
			if Time.get_ticks_msec() - idle_since >= idle_timeout_sec * 1000:
				_write_json(out_dir.path_join("terminal.json"), {
					"status": "idle_timeout", "expected_seq": expected,
					"idle_timeout_sec": idle_timeout_sec})
				print("BRIDGE_TIMEOUT expected=" + str(expected))
				quit(124)
				return
			await create_timer(0.1).timeout
			continue
		var raw := FileAccess.get_file_as_string(command_path)
		var parsed = JSON.parse_string(raw)
		if not parsed is Dictionary:
			_reject(command_path, "invalid_json", expected)
			continue
		var command: Dictionary = parsed
		if String(command.get("schema", "")) != COMMAND_SCHEMA or \
				not _bounded_integer(command.get("seq", -1), expected, expected):
			_reject(command_path, "schema_or_sequence_mismatch", expected)
			continue
		var validation := _validate_command(command)
		if validation != "":
			_reject(command_path, validation, expected)
			continue
		if DirAccess.rename_absolute(command_path, processed_dir.path_join("%06d.json" % expected)) != OK:
			_reject(command_path, "cannot_claim_command", expected)
			continue
		var result: Dictionary = await _dispatch(command)
		var captured := await _capture_observation(expected)
		var receipt := {
			"schema": RECEIPT_SCHEMA, "seq": expected, "accepted": true,
			"action": String(command["action"]), "result": result,
			"command_sha256": raw.sha256_text(),
			"before_observation": expected - 1, "after_observation": expected,
			"rendered_capture_ok": captured,
		}
		_write_json(receipts_dir.path_join("%06d.json" % expected), receipt)
		print("BRIDGE_STEP " + str(expected) + " " + String(command["action"]))
		if not captured:
			_write_json(out_dir.path_join("terminal.json"), {"status": "capture_failed", "seq": expected})
			quit(2)
			return
		if String(command["action"]) == "quit":
			_write_json(out_dir.path_join("terminal.json"), {"status": "quit", "seq": expected})
			quit(0)
			return
		expected += 1
		idle_since = Time.get_ticks_msec()

func _validate_command(command: Dictionary) -> String:
	var action := String(command.get("action", ""))
	if action not in ["key", "click", "wait", "quit"]:
		return "unsupported_action"
	var settle = command.get("settle_ms", 160)
	if not _bounded_integer(settle, 0, 2000):
		return "settle_ms_out_of_range"
	if action == "key":
		var code := String(command.get("code", ""))
		if not KEY_CODES.has(code):
			return "key_not_allowed"
		var hold = command.get("hold_ms", 80)
		if not _bounded_integer(hold, 0, 500):
			return "hold_ms_out_of_range"
	elif action == "click":
		var x = command.get("x", -1)
		var y = command.get("y", -1)
		var size: Vector2 = root.get_visible_rect().size
		if not (typeof(x) in [TYPE_INT, TYPE_FLOAT] and typeof(y) in [TYPE_INT, TYPE_FLOAT]):
			return "click_coordinates_invalid"
		if float(x) < 0 or float(y) < 0 or float(x) >= size.x or float(y) >= size.y:
			return "click_outside_viewport"
	elif action == "wait":
		var duration = command.get("duration_ms", -1)
		if not _bounded_integer(duration, 0, 2000):
			return "duration_ms_out_of_range"
	return ""

func _bounded_integer(value: Variant, minimum: int, maximum: int) -> bool:
	if not (typeof(value) in [TYPE_INT, TYPE_FLOAT]):
		return false
	var number := float(value)
	return number >= minimum and number <= maximum and floorf(number) == number

func _dispatch(command: Dictionary) -> Dictionary:
	var action := String(command["action"])
	if action == "key":
		var code := String(command["code"])
		await _key(KEY_CODES[code], int(command.get("hold_ms", 80)))
		await _settle(int(command.get("settle_ms", 160)))
		return {"code": code, "route": "Input.parse_input_event"}
	if action == "click":
		var point := Vector2(float(command["x"]), float(command["y"]))
		await _click(point)
		await _settle(int(command.get("settle_ms", 160)))
		return {"point": [point.x, point.y], "route": "Viewport.push_input"}
	if action == "wait":
		await _settle(int(command["duration_ms"]))
		return {"duration_ms": int(command["duration_ms"])}
	return {"reason": "requested_quit"}

func _key(code: int, hold_ms: int) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.physical_keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	await _settle(hold_ms)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame

func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame

func _settle(milliseconds: int) -> void:
	if milliseconds > 0:
		await create_timer(float(milliseconds) / 1000.0).timeout
	else:
		await process_frame

func _capture_observation(seq: int) -> bool:
	await RenderingServer.frame_post_draw
	var texture := root.get_texture()
	if texture == null:
		return false
	var image := texture.get_image()
	if image == null or image.is_empty():
		return false
	var stem := "%06d" % seq
	var png_path := observations_dir.path_join(stem + ".png")
	if image.save_png(png_path) != OK:
		return false
	var save_path := ProjectSettings.globalize_path("user://quicksave.dat")
	var save_exists := FileAccess.file_exists(save_path)
	var actor: Dictionary = sim.call("controlled")
	var position: Vector2i = actor.get("pos", Vector2i(-1, -1))
	var selected_cards: Array = []
	if life != null and bool(life.get("selecting")):
		var ids: Array = life.get("_sel_ids")
		var cards: Array = life.get("_sel_cards")
		for i in mini(ids.size(), cards.size()):
			var card: Control = cards[i] as Control
			var center := card.get_global_rect().get_center()
			selected_cards.append({"index": i, "id": String(ids[i]),
				"center": [center.x, center.y], "selected": i == int(life.get("_sel_idx"))})
	var modal_buttons: Array = []
	var modal: Control = life.get("_modal") as Control if life != null else null
	if modal != null and modal.visible:
		for child in modal.get_children():
			if child is Button:
				var button: Button = child
				var center := button.get_global_rect().get_center()
				modal_buttons.append({"text": button.text, "disabled": button.disabled,
					"center": [center.x, center.y]})
	var nearby: Array = []
	if life != null and bool(life.get("active")):
		for item in sim.call("life_interactions"):
			var entry: Dictionary = item
			nearby.append({"kind": String(entry.get("kind", "")),
				"id": String(entry.get("id", "")), "dist": int(entry.get("dist", -1))})
	# Read-only gameplay witnesses help an agent distinguish a queued service or
	# completed social event from a menu that merely closed. Never write Sim here.
	var events: Array = sim.get("event_log")
	var recent_events: Array = []
	for i in range(maxi(0, events.size() - 12), events.size()):
		if events[i] is Dictionary:
			recent_events.append((events[i] as Dictionary).duplicate(true))
	var size: Vector2 = root.get_visible_rect().size
	var observation := {
		"schema": OBSERVATION_SCHEMA, "seq": seq,
		"png": "observations/" + stem + ".png",
		"png_sha256": FileAccess.get_sha256(png_path),
		"user_data_dir": OS.get_user_data_dir(),
		"viewport": [int(size.x), int(size.y)],
		"day": sim.get("day"), "tick": sim.get("tick_no"), "running": sim.get("running"),
		"save": {"exists": save_exists,
			"sha256": FileAccess.get_sha256(save_path) if save_exists else ""},
		"life": {"selecting": bool(life.get("selecting")) if life != null else false,
			"selected_index": int(life.get("_sel_idx")) if life != null else -1,
			"active": bool(life.get("active")) if life != null else false,
			"resident": String(life.get("pid")) if life != null else "",
			"space": String(actor.get("space", "")), "floor": String(actor.get("floor", "")),
			"position": [position.x, position.y],
			"focus": String(life.get("_focus_id")) if life != null else "",
			"modal_open": bool(life.get("_modal_open")) if life != null else false},
		"selection_cards": selected_cards, "modal_buttons": modal_buttons,
		"nearby_interactions": nearby,
		"controlled_status": sim.call("life_status"),
		"event_count": events.size(), "event_digest": sim.get("event_digest"),
		"recent_events": recent_events,
	}
	return _write_json(observations_dir.path_join(stem + ".json"), observation)

func _reject_stale(expected: int) -> void:
	var directory := DirAccess.open(commands_dir)
	if directory == null:
		return
	for filename in directory.get_files():
		if not filename.ends_with(".json"):
			continue
		var stem := filename.trim_suffix(".json")
		if not stem.is_valid_int():
			_reject(commands_dir.path_join(filename), "invalid_filename", expected)
		elif int(stem) < expected:
			_reject(commands_dir.path_join(filename), "stale_sequence", expected)

func _reject(path: String, reason: String, expected: int) -> void:
	var filename := path.get_file()
	var destination := rejected_dir.path_join(filename)
	var moved := DirAccess.rename_absolute(path, destination) == OK
	_write_json(rejected_dir.path_join(filename + ".reason.json"), {
		"accepted": false, "reason": reason, "expected_seq": expected,
		"source": path, "command_preserved": moved})
	print("BRIDGE_REJECT " + filename + " " + reason)

func _write_json(path: String, data: Dictionary) -> bool:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_error("BRIDGE cannot write " + temporary)
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	if DirAccess.rename_absolute(temporary, path) != OK:
		push_error("BRIDGE cannot publish " + path)
		return false
	return true
