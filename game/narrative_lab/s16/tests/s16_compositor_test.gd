extends Node
## S16 main-repo gate for the fail-closed committed-trace compositor.

const DEFAULT_OUT := "res://../analysis/narrative_visual/s16"
const SCREENSHOTS := {
	"compositor_1024x768.png": Vector2i(1024, 768),
	"compositor_1280x768.png": Vector2i(1280, 768),
	"compositor_2688x1216.png": Vector2i(2688, 1216),
}

var _checks := 0
var _failures: Array[String] = []
var _logic_only := false
var _negative_control := false
var _write_outputs := true
var _run_completed := false
var _layout_receipts := {}
var _screenshot_receipts := {}


func _ready() -> void:
	call_deferred("_start")


func _start() -> void:
	var args := OS.get_cmdline_user_args()
	_logic_only = "--logic-only" in args
	_negative_control = "--negative-control" in args
	_write_outputs = not "--no-output" in args
	var out_dir := ProjectSettings.globalize_path(DEFAULT_OUT)
	var out_index := args.find("--out")
	if out_index >= 0 and out_index + 1 < args.size():
		out_dir = String(args[out_index + 1])
	if _write_outputs:
		DirAccess.make_dir_recursive_absolute(out_dir)
	await _run(out_dir)
	if _negative_control:
		return
	if not _run_completed:
		_failures.append("test coroutine aborted before completion")
	if _failures.is_empty():
		print("S16 COMPOSITOR: PASS (%d checks, 0 fail)" % _checks)
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("S16 COMPOSITOR: FAIL (%d checks, %d fail)" % [_checks, _failures.size()])
		get_tree().quit(1)


func _run(out_dir: String) -> void:
	var fixture_absolute := ProjectSettings.globalize_path(S16Compositor.FIXTURE_PATH)
	var fixture_hash_before := FileAccess.get_sha256(S16Compositor.FIXTURE_PATH)
	var compositor := S16Compositor.new()
	compositor.name = "s16_logic_compositor"
	compositor.size = Vector2(1280, 768)
	add_child(compositor)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(compositor.is_loaded(), "canonical fixture did not load")
	_check(compositor.fatal_errors.is_empty(), "canonical fixture raised fatal errors: %s" % [compositor.fatal_errors])
	_check(S16Compositor.BANNER_TEXT == "NARRATIVE LAB · NOT SIM · READ-ONLY COMMITTED TRACE", "banner drifted")
	_check(fixture_hash_before == S16Compositor.FIXTURE_SHA256, "fixture hash is not source-bound")
	_check(FileAccess.file_exists(fixture_absolute), "fixture path did not globalize to a file")
	var receipt := compositor.source_receipt()
	_check(receipt["lab_commit"] == S16Compositor.FIXTURE_LAB_COMMIT, "lab commit receipt drifted")
	_check(receipt["lab_path"] == S16Compositor.FIXTURE_LAB_PATH, "lab path receipt drifted")

	var missing := S16Compositor.new()
	_check(not missing.load_committed_trace("res://narrative_lab/s16/fixtures/missing.json"), "missing fixture did not fail closed")
	_check(not missing.fatal_errors.is_empty(), "missing fixture did not preserve an error")
	missing.free()
	var wrong_hash := S16Compositor.new()
	_check(not wrong_hash.load_committed_trace(S16Compositor.FIXTURE_PATH, "0".repeat(64)), "wrong fixture hash did not fail closed")
	_check("FIXTURE_HASH_MISMATCH" in wrong_hash.fatal_errors[0], "wrong hash error was not explicit")
	wrong_hash.free()

	var mutated := compositor.trace_document_for_test()
	var handoff: Dictionary = mutated["handoff_gate"]
	var after_frame: Dictionary = mutated["frames"][int(handoff["to_offset"])]
	var after_source := _role(after_frame, String(handoff["source_role_id"]))
	(after_source["carried_fragment_ids"] as Array).append(String(handoff["fragment_id"]))
	var mutation_errors := compositor.validate_document(mutated)
	if _negative_control:
		if "HANDOFF_NOT_ATOMIC" in mutation_errors:
			print("S16 NEGATIVE CONTROL: RED as expected (HANDOFF_NOT_ATOMIC)")
			compositor.queue_free()
			get_tree().quit(7)
		else:
			push_error("S16 NEGATIVE CONTROL: FALSE GREEN")
			compositor.queue_free()
			get_tree().quit(9)
		return
	_check("HANDOFF_NOT_ATOMIC" in mutation_errors, "half-handoff mutation was not rejected")

	var expected_snapshot_keys: Array[String] = []
	for key in S16Compositor.SNAPSHOT_KEYS:
		expected_snapshot_keys.append(String(key))
	expected_snapshot_keys.sort()
	_check(compositor.component_snapshot_keys() == expected_snapshot_keys, "Graph/Card did not receive exactly the S06 ten fields")
	_check(compositor.component_snapshot_keys().size() == 10, "component snapshot field count is not ten")
	for key in compositor.sidecar_keys():
		_check(key in S16Compositor.SIDECAR_KEYS, "transition sidecar leaked non-whitelisted field: %s" % key)
	for key in S16Compositor.SIDECAR_KEYS:
		_check(String(key).ends_with("_id") or String(key).ends_with("_sha256") or key == "chain_hash", "sidecar whitelist contains a non-ID/hash field: %s" % key)

	var button_before := compositor.dispatch_count(S16Compositor.ACTION_FOCUS_ROLE)
	compositor.input_button_press_for_test(S16Compositor.ACTION_FOCUS_ROLE)
	var button_via_dispatcher := compositor.dispatch_count(S16Compositor.ACTION_FOCUS_ROLE) == button_before + 1
	_check(button_via_dispatcher, "button did not use dispatcher")
	var key_before := compositor.dispatch_count(S16Compositor.ACTION_SELECT_NODE)
	compositor.input_key_for_test(KEY_N)
	var key_via_dispatcher := compositor.dispatch_count(S16Compositor.ACTION_SELECT_NODE) == key_before + 1
	_check(key_via_dispatcher, "keyboard did not use dispatcher")
	var touch_before := compositor.dispatch_count(S16Compositor.ACTION_VIEW_TRAVERSE)
	compositor.input_screen_touch_for_test(S16Compositor.ACTION_VIEW_TRAVERSE)
	var touch_single_dispatch := compositor.dispatch_count(S16Compositor.ACTION_VIEW_TRAVERSE) == touch_before + 1
	_check(touch_single_dispatch, "ScreenTouch and emulated press double-fired or missed dispatcher")
	_check(compositor.dispatch_for_test(S16Compositor.ACTION_COMPARE_HANDOFF), "compare_handoff dispatch failed")
	_check(compositor.dispatch_for_test(S16Compositor.ACTION_SCRUB_REPLAY, {"offset": 0}), "scrub_replay dispatch failed")
	for action_id in S16Compositor.ACTIONS:
		_check(compositor.dispatch_count(String(action_id)) > 0, "dispatcher action was not exercised: %s" % action_id)
	_check(not compositor.dispatch_for_test("writeback_trace"), "unknown writeback action was accepted")

	compositor.dispatch_for_test(S16Compositor.ACTION_SCRUB_REPLAY, {"offset": 0})
	var fingerprint_0_a := compositor.frame_fingerprint()
	compositor.dispatch_for_test(S16Compositor.ACTION_SCRUB_REPLAY, {"offset": 12})
	var fingerprint_12_a := compositor.frame_fingerprint()
	compositor.dispatch_for_test(S16Compositor.ACTION_SCRUB_REPLAY, {"offset": 0})
	var fingerprint_0_b := compositor.frame_fingerprint()
	compositor.dispatch_for_test(S16Compositor.ACTION_SCRUB_REPLAY, {"offset": 12})
	var fingerprint_12_b := compositor.frame_fingerprint()
	_check(fingerprint_0_a == fingerprint_0_b, "0→12→0 replay changed offset-0 fingerprint")
	_check(fingerprint_12_a == fingerprint_12_b, "0→12→0→12 replay changed offset-12 fingerprint")
	_check(fingerprint_0_a != fingerprint_12_a, "offset 0 and 12 fingerprints unexpectedly match")
	_check(compositor.source_trace_unchanged(), "view actions mutated the committed trace")
	_check(FileAccess.get_sha256(S16Compositor.FIXTURE_PATH) == fixture_hash_before, "view actions wrote back to fixture")

	for dimensions in [Vector2(1024, 768), Vector2(1280, 768), Vector2(2688, 1216)]:
		compositor.size = dimensions
		compositor._layout_ui()
		var layout := compositor.layout_receipt()
		_layout_receipts["%dx%d" % [int(dimensions.x), int(dimensions.y)]] = layout
		_check(bool(layout["targets_at_least_44px"]), "%dx%d has a target below 44px" % [int(dimensions.x), int(dimensions.y)])
	_check(_layout_receipts["1024x768"]["mode"] == "single_pane_tabs", "1024 layout is not single-pane tabs")
	_check(_layout_receipts["1280x768"]["mode"] == "dual_pane", "1280 layout is not dual-pane")
	_check(_layout_receipts["2688x1216"]["content_width"] == 1560, "2688 layout did not clamp max width")
	_check(_layout_receipts["2688x1216"]["content_x"] == 564, "2688 layout is not centered")

	if _logic_only:
		compositor.queue_free()
		_run_completed = true
		return

	for name in SCREENSHOTS:
		var dimensions: Vector2i = SCREENSHOTS[name]
		var receipt_row: Dictionary = await _render_screenshot(dimensions, String(name), out_dir)
		_screenshot_receipts[name] = receipt_row
		_check(bool(receipt_row["saved"]), "could not save %s" % name)
		_check(bool(receipt_row["banner_present"]), "permanent NOT SIM banner missing in %s" % name)
		_check(receipt_row["size"] == [dimensions.x, dimensions.y], "screenshot dimensions drifted: %s" % name)

	var audit := {
		"schema": "living-town-s16-main-compositor-audit/v1",
		"result": "PASS_WITH_BLOCKERS" if _failures.is_empty() else "FAIL",
		"production_gate": false,
		"banner": S16Compositor.BANNER_TEXT,
		"mode": "READ_ONLY_COMMITTED_TRACE",
		"simulation": "NOT_SIM",
		"source_receipt": compositor.source_receipt(),
		"metrics": {
			"frames": 13,
			"snapshot_fields": 10,
			"dispatcher_actions": S16Compositor.ACTIONS.size(),
			"responsive_layouts": SCREENSHOTS.size(),
			"checks": _checks,
		},
		"checks": {
			"fixture_hash_bound": fixture_hash_before == S16Compositor.FIXTURE_SHA256,
			"handoff_half_mutation_rejected": "HANDOFF_NOT_ATOMIC" in mutation_errors,
			"replay_fingerprints_stable": fingerprint_0_a == fingerprint_0_b and fingerprint_12_a == fingerprint_12_b,
			"source_trace_unchanged": compositor.source_trace_unchanged(),
			"fixture_bytes_unchanged": FileAccess.get_sha256(S16Compositor.FIXTURE_PATH) == fixture_hash_before,
			"component_boundary_exact_ten_fields": compositor.component_snapshot_keys() == expected_snapshot_keys,
			"transition_sidecar_whitelisted": _sidecar_keys_allowed(compositor.sidecar_keys()),
			"button_uses_dispatcher": button_via_dispatcher,
			"keyboard_uses_dispatcher": key_via_dispatcher,
			"screen_touch_single_dispatch": touch_single_dispatch,
			"responsive_targets_at_least_44px": _all_layout_targets_pass(),
		},
		"layouts": _layout_receipts,
		"screenshots": _screenshot_receipts,
		"blockers": [
			{"id": "STATIC_COMMITTED_FIXTURE_ONLY", "reason": "the compositor reads a source-bound committed trace fixture; it is not connected to the live runtime"},
			{"id": "NO_SIMULATION_OWNERSHIP", "reason": "focus, compare, and replay actions are view-only and intentionally cannot mutate Sim"},
			{"id": "NO_GAMEPLAY_OR_WALKABILITY_CLAIM", "reason": "framebuffer captures demonstrate component layout only, not gameplay or traversability"},
		],
		"failures": _failures,
	}
	if _write_outputs:
		var audit_path := out_dir.path_join("audit.json")
		var handle := FileAccess.open(audit_path, FileAccess.WRITE)
		_check(handle != null, "could not create audit.json")
		if handle != null:
			handle.store_string(JSON.stringify(audit, "  ") + "\n")
			handle.close()
	compositor.queue_free()
	_run_completed = true


func _render_screenshot(dimensions: Vector2i, name: String, out_dir: String) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = "s16_capture_%dx%d" % [dimensions.x, dimensions.y]
	viewport.size = dimensions
	viewport.transparent_bg = false
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var compositor := S16Compositor.new()
	compositor.size = Vector2(dimensions)
	viewport.add_child(compositor)
	await get_tree().process_frame
	await get_tree().process_frame
	if dimensions.x == 1024:
		compositor.dispatch_for_test(S16Compositor.ACTION_VIEW_TRAVERSE)
	elif dimensions.x == 1280:
		compositor.dispatch_for_test(S16Compositor.ACTION_COMPARE_HANDOFF)
	else:
		compositor.dispatch_for_test(S16Compositor.ACTION_SCRUB_REPLAY, {"offset": 12})
	await get_tree().process_frame
	await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	var output := out_dir.path_join(name)
	var saved := not image.is_empty() and (not _write_outputs or image.save_png(output) == OK)
	var banner_pixels := _accent_row_pixels(image, 52)
	var receipt := {
		"size": [image.get_width(), image.get_height()] if not image.is_empty() else [0, 0],
		"layout": compositor.layout_receipt(),
		"banner_accent_pixels": banner_pixels,
		"banner_present": banner_pixels >= int(dimensions.x * 0.90),
		"saved": saved,
		"sha256": FileAccess.get_sha256(output) if saved and _write_outputs else null,
		"media_kind": "component_layout_review_not_sim_not_gameplay",
	}
	viewport.remove_child(compositor)
	compositor.free()
	remove_child(viewport)
	viewport.free()
	return receipt


func _accent_row_pixels(image: Image, y: int) -> int:
	if image == null or image.is_empty() or y < 0 or y >= image.get_height():
		return 0
	var count := 0
	for x in range(image.get_width()):
		var pixel := image.get_pixel(x, y)
		if absf(pixel.r - S16Compositor.ACCENT.r) <= 0.08 and absf(pixel.g - S16Compositor.ACCENT.g) <= 0.08 and absf(pixel.b - S16Compositor.ACCENT.b) <= 0.08:
			count += 1
	return count


func _sidecar_keys_allowed(keys: Array[String]) -> bool:
	for key in keys:
		if not key in S16Compositor.SIDECAR_KEYS:
			return false
	return true


func _all_layout_targets_pass() -> bool:
	for layout in _layout_receipts.values():
		if not bool(layout["targets_at_least_44px"]):
			return false
	return true


func _role(frame: Dictionary, role_id: String) -> Dictionary:
	for role in frame["roles"]:
		if role["role_id"] == role_id:
			return role
	return {}


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
