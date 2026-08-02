extends Node
## Captures five deterministic S16 compositor states through the real dispatcher.
## The output is component-review media, never simulation or gameplay footage.

const DEFAULT_OUT := "res://../analysis/narrative_visual/s17"
const SOURCE_S16_COMMIT := "af72cfb55b191f28f97cd59ea8fcd2376f5e1f46"
const REVIEW_BANNER := "NARRATIVE LAB · NOT SIM · READ-ONLY COMMITTED TRACE · NOT GAMEPLAY"
const CAPTURE_SIZE := Vector2i(1280, 768)
const STEPS := [
	{"action_id": "focus_role", "payload": {}, "file": "state_01_focus_role.png"},
	{"action_id": "select_node", "payload": {}, "file": "state_02_select_node.png"},
	{"action_id": "view_traverse", "payload": {}, "file": "state_03_view_traverse.png"},
	{"action_id": "compare_handoff", "payload": {}, "file": "state_04_compare_handoff.png"},
	{"action_id": "scrub_replay", "payload": {"offset": 12}, "file": "state_05_scrub_replay.png"},
]

var _failures: Array[String] = []
var _checks := 0
var _logic_only := false
var _write_outputs := true
var _captures: Array[Dictionary] = []
var _run_completed := false


func _ready() -> void:
	call_deferred("_start")


func _start() -> void:
	var args := OS.get_cmdline_user_args()
	_logic_only = "--logic-only" in args
	_write_outputs = not "--no-output" in args
	var out_dir := ProjectSettings.globalize_path(DEFAULT_OUT)
	var out_index := args.find("--out")
	if out_index >= 0 and out_index + 1 < args.size():
		out_dir = String(args[out_index + 1])
	if _write_outputs:
		DirAccess.make_dir_recursive_absolute(out_dir)
	await _run(out_dir)
	if not _run_completed:
		_failures.append("capture coroutine aborted before completion")
	if _failures.is_empty():
		print("S17 CAPTURE: PASS (%d checks, 0 fail)" % _checks)
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("S17 CAPTURE: FAIL (%d checks, %d fail)" % [_checks, _failures.size()])
		get_tree().quit(1)


func _run(out_dir: String) -> void:
	var viewport := SubViewport.new()
	viewport.name = "s17_dispatcher_capture"
	viewport.size = CAPTURE_SIZE
	viewport.transparent_bg = false
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var compositor := S16Compositor.new()
	compositor.size = Vector2(CAPTURE_SIZE)
	viewport.add_child(compositor)
	var banner := _review_banner()
	viewport.add_child(banner)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(compositor.is_loaded(), "S16 compositor fixture did not load")
	_check(compositor.source_trace_unchanged(), "S16 trace changed before review dispatch")
	_check(REVIEW_BANNER.contains("NOT SIM"), "review banner lost NOT SIM")
	_check(REVIEW_BANNER.contains("READ-ONLY COMMITTED TRACE"), "review banner lost READ-ONLY COMMITTED TRACE")
	_check(REVIEW_BANNER.contains("NOT GAMEPLAY"), "review banner lost NOT GAMEPLAY")

	var trace_fingerprint_before := compositor.trace_fingerprint()
	for index in range(STEPS.size()):
		var step: Dictionary = STEPS[index]
		var action_id := String(step["action_id"])
		var count_before := compositor.dispatch_count(action_id)
		_check(compositor.dispatch_for_test(action_id, (step["payload"] as Dictionary).duplicate(true)), "dispatcher rejected %s" % action_id)
		_check(compositor.dispatch_count(action_id) == count_before + 1, "%s bypassed or double-fired dispatcher" % action_id)
		_check(compositor.source_trace_unchanged(), "%s mutated the committed trace" % action_id)
		await get_tree().process_frame
		await get_tree().process_frame
		if _logic_only:
			_captures.append({
				"ordinal": index + 1,
				"action_id": action_id,
				"committed_trace_offset": compositor.current_offset(),
				"frame_fingerprint": compositor.frame_fingerprint(),
			})
			continue
		var image := viewport.get_texture().get_image()
		var output := out_dir.path_join(String(step["file"]))
		var saved := not image.is_empty() and (not _write_outputs or image.save_png(output) == OK)
		_check(saved, "could not save %s" % step["file"])
		var banner_pixels := _accent_pixels(image)
		_check(banner_pixels >= int(CAPTURE_SIZE.x * 0.90), "permanent review banner missing in %s" % step["file"])
		_captures.append({
			"ordinal": index + 1,
			"action_id": action_id,
			"payload": (step["payload"] as Dictionary).duplicate(true),
			"committed_trace_offset": compositor.current_offset(),
			"frame_fingerprint": compositor.frame_fingerprint(),
			"dispatch_total": compositor.dispatch_total(),
			"file": String(step["file"]),
			"size": [image.get_width(), image.get_height()],
			"banner_accent_pixels": banner_pixels,
			"sha256": FileAccess.get_sha256(output) if saved and _write_outputs else null,
		})

	_check(compositor.trace_fingerprint() == trace_fingerprint_before, "review sequence changed source trace fingerprint")
	_check(compositor.dispatch_total() == STEPS.size(), "review sequence did not dispatch exactly five actions")
	_check([_captures[0]["committed_trace_offset"], _captures[1]["committed_trace_offset"], _captures[2]["committed_trace_offset"], _captures[3]["committed_trace_offset"], _captures[4]["committed_trace_offset"]] == [0, 0, 1, 2, 12], "capture offsets are not the expected committed frames")

	if _write_outputs and not _logic_only:
		var receipt := {
			"schema": "living-town-s17-dispatcher-capture/v1",
			"result": "PASS" if _failures.is_empty() else "FAIL",
			"production_gate": false,
			"source_s16_commit": SOURCE_S16_COMMIT,
			"fixture_sha256": S16Compositor.FIXTURE_SHA256,
			"banner": REVIEW_BANNER,
			"mode": "READ_ONLY_COMMITTED_TRACE",
			"simulation": "NOT_SIM",
			"media_kind": "component_review_not_sim_not_gameplay",
			"source_trace_fingerprint_before": trace_fingerprint_before,
			"source_trace_fingerprint_after": compositor.trace_fingerprint(),
			"source_trace_unchanged": compositor.source_trace_unchanged(),
			"captures": _captures,
			"checks": _checks,
			"failures": _failures,
		}
		var handle := FileAccess.open(out_dir.path_join("capture_receipt.json"), FileAccess.WRITE)
		_check(handle != null, "could not create capture_receipt.json")
		if handle != null:
			handle.store_string(JSON.stringify(receipt, "  ") + "\n")
			handle.close()

	viewport.remove_child(banner)
	banner.free()
	viewport.remove_child(compositor)
	compositor.free()
	remove_child(viewport)
	viewport.free()
	_run_completed = true


func _review_banner() -> Control:
	var root := Control.new()
	root.name = "s17_permanent_review_banner"
	root.position = Vector2.ZERO
	root.size = Vector2(CAPTURE_SIZE.x, 54)
	root.z_index = 1000
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := ColorRect.new()
	background.color = S16Compositor.BANNER_BG
	background.size = root.size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	var accent := ColorRect.new()
	accent.color = S16Compositor.ACCENT
	accent.position = Vector2(0, 52)
	accent.size = Vector2(CAPTURE_SIZE.x, 2)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(accent)
	var label := Label.new()
	label.text = REVIEW_BANNER
	label.position = Vector2(12, 3)
	label.size = Vector2(CAPTURE_SIZE.x - 24, 46)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", S16Compositor.INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(label)
	return root


func _accent_pixels(image: Image) -> int:
	if image == null or image.is_empty():
		return 0
	var count := 0
	for x in range(image.get_width()):
		var pixel := image.get_pixel(x, 52)
		if absf(pixel.r - S16Compositor.ACCENT.r) <= 0.08 and absf(pixel.g - S16Compositor.ACCENT.g) <= 0.08 and absf(pixel.b - S16Compositor.ACCENT.b) <= 0.08:
			count += 1
	return count


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
