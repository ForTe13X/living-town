extends Node
## C1 contract probe: projection state is ephemeral while all player effects go
## through the existing public Sim boundaries.

const Inv = preload("res://bench/Invariants.gd")
var fails := 0

func ck(ok: bool, label: String, detail := "") -> void:
	print("  %s  %s%s" % [("OK" if ok else "FAIL"), label, (" — " + detail if detail != "" else "")])
	if not ok:
		fails += 1

func tickn(n: int) -> void:
	for _i in range(n):
		Sim.tick()

func state() -> Dictionary:
	var pl: Dictionary = Sim.get_agent("player")
	return {"tick": Sim.tick_no, "digest": Inv.digest(Sim), "event_digest": Sim.event_digest,
		"events": Sim.event_log.duplicate(true), "trace": Sim.get_player_trace(),
		"space": pl.get("space", ""), "floor": pl.get("floor", ""), "pos": pl.get("pos", Vector2i.ZERO),
		"memory": (pl.get("memory").items as Array).duplicate(true) if pl.get("memory") != null else [],
		"relationships": (pl.get("relationships", {}) as Dictionary).duplicate(true)}

func stable_main_snapshot(main: Node, include_status_refresh := true) -> Dictionary:
	var sim_state := state()
	# A failed replay records a diagnostic in its transient trace error field;
	# compare canonical world/receipt contents separately from that diagnosis.
	# Inv.digest also includes the diagnostic field, so it is excluded here.
	sim_state.erase("trace")
	sim_state.erase("digest")
	var result := {"sim": sim_state, "running": Sim.running, "auto_run": Sim.auto_run, "replaying": Sim.replaying, "space": main._probe.active_space, "floor": main._probe.active_floor,
		"pos": main._probe.cam.position, "zoom": main._probe.cam.zoom, "selected": main._selected_id,
		"obs": main._obs.text, "status": main._status.text, "feedback": main._locked_ortho_c1.feedback_text()}
	if include_status_refresh:
		result["status_refreshes"] = main._status_refresh_count
	return result

func snapshot_diff(before: Dictionary, after: Dictionary) -> String:
	var changed := []
	for key in before:
		if before[key] != after.get(key):
			changed.append(str(key))
	return ",".join(changed)

func find_cafe_guest() -> Dictionary:
	var pl: Dictionary = Sim.get_agent("player")
	for raw in Sim.agents:
		var ag: Dictionary = raw
		if not bool(ag.get("is_player", false)) and int(pl.get("talking", 0)) == 0 and int(ag.get("talking", 0)) == 0 and ag.get("option") == null and String(ag.get("space", "")) == "cafe" and String(ag.get("floor", "")) == "1f":
			var pp: Vector2i = pl.get("pos", Vector2i.ZERO)
			var ap: Vector2i = ag.get("pos", Vector2i(99, 99))
			if absi(pp.x - ap.x) + absi(pp.y - ap.y) <= 2:
				return ag
	return {}

func find_cafe_resident() -> Dictionary:
	for raw in Sim.agents:
		var ag: Dictionary = raw
		if not bool(ag.get("is_player", false)) and String(ag.get("space", "")) == "cafe" and String(ag.get("floor", "")) == "1f":
			return ag
	return {}

func wait_cafe_resident() -> Dictionary:
	var resident := find_cafe_resident()
	# The authored cafe schedule produces a resident well before one day.  Keeping
	# this below TICKS_PER_DAY lets the real bracket jump still land before entry.
	for _i in range(240):
		if not resident.is_empty():
			break
		Sim.tick()
		resident = find_cafe_resident()
	return resident

func deny_owner_stair(main: Node) -> void:
	# Public player movement plus the connected Main/Probe left-tap route: no
	# coordinates, topology, or permission result is injected by this helper.
	for direction in [Vector2i.LEFT, Vector2i.UP, Vector2i.UP, Vector2i.UP, Vector2i.LEFT, Vector2i.UP, Vector2i.LEFT]:
		Sim.player_move(direction)
	main._probe.emit_signal("tapped", Vector2(1 * 48 + 24, 1 * 48 + 24))

func mouse_button(main: Node, pressed: bool, position: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.pressed = pressed
	event.button_index = button
	event.position = position
	main._unhandled_input(event)

func mouse_motion(main: Node, position: Vector2, button_mask := MOUSE_BUTTON_MASK_LEFT) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.button_mask = button_mask
	main._unhandled_input(event)

func scrub_input_boundaries(main: Node) -> void:
	# All inputs are routed through Main.  No-mask, foreign-mask, outside motion,
	# repeated press, and uncaptured release must never reach the timeline helper.
	Sim.running = true
	var trace_available := Sim.player_trace_available
	Sim.player_trace_available = false
	var initial := stable_main_snapshot(main)
	var attempts: int = main._timeline_attempt_count
	var in_rect := Vector2(main._sx0 + 1.0, main._sy)
	var outside := Vector2(main._sx1 + 80.0, main._sy + 80.0)
	mouse_button(main, false, in_rect)
	mouse_motion(main, in_rect, 0)
	mouse_motion(main, in_rect, MOUSE_BUTTON_MASK_RIGHT)
	mouse_motion(main, in_rect, MOUSE_BUTTON_MASK_MIDDLE)
	ck(stable_main_snapshot(main) == initial and main._timeline_attempt_count == attempts and not main._scrubbing and main._scrub_pending < 0, "uncaptured release and non-left motion are exact C1 timeline no-ops")
	mouse_button(main, true, in_rect)
	var after_press: int = main._timeline_attempt_count
	mouse_motion(main, outside)
	mouse_button(main, true, in_rect)
	ck(main._scrubbing and main._scrub_pending < 0 and main._timeline_attempt_count == after_press, "outside motion and repeated press cannot queue or repeat a C1 scrub attempt")
	mouse_button(main, false, outside)
	var after_outside_release: int = main._timeline_attempt_count
	mouse_button(main, false, outside)
	main._process(0.0)
	ck(not main._scrubbing and main._scrub_pending < 0 and main._timeline_attempt_count == after_outside_release, "outside-only capture, double release, and next-frame flush cannot create a deferred attempt")
	# Positive control: a distinct in-range masked drag queues one target and its
	# release consumes exactly one deferred attempt, then leaves no stale capture.
	mouse_button(main, true, in_rect)
	var before_release: int = main._timeline_attempt_count
	var target := Vector2(main._sx1 - 1.0, main._sy)
	mouse_motion(main, target)
	ck(main._scrub_pending == main._tick_at_x(target.x), "in-range masked motion queues the distinct deferred target")
	mouse_button(main, false, target)
	var after_release: int = main._timeline_attempt_count
	mouse_button(main, false, target)
	main._process(0.0)
	ck(after_release == before_release + 1 and main._timeline_attempt_count == after_release and not main._scrubbing and main._scrub_pending < 0, "release single-consumes exactly one deferred C1 scrub attempt")
	Sim.player_trace_available = trace_available

func failed_timeline_route(main: Node, name: String) -> void:
	Sim.running = true
	main._update_status()
	var before := stable_main_snapshot(main)
	var trace_available := Sim.player_trace_available
	Sim.player_trace_available = false
	match name:
		"comma":
			var comma := InputEventKey.new(); comma.pressed = true; comma.keycode = KEY_COMMA
			main._unhandled_input(comma)
		"left":
			var left := InputEventKey.new(); left.pressed = true; left.keycode = KEY_BRACKETLEFT
			main._unhandled_input(left)
		"right":
			var right := InputEventKey.new(); right.pressed = true; right.keycode = KEY_BRACKETRIGHT
			main._unhandled_input(right)
		"scrub":
			# Public press hits the live timeline and exercises Main's hit-test plus
			# immediate scrub attempt; no private scrub helper is invoked.
			var immediate := Vector2(main._sx0 + 1.0, main._sy)
			mouse_button(main, true, immediate)
			ck(Sim.player_trace_last_error == "player_trace_unavailable", "public timeline press executes immediate scrub attempt")
			mouse_button(main, false, immediate)
		"flush":
			# Press starts Main._scrubbing, motion coalesces _scrub_pending, and the
			# public release executes the deferred flush path.
			var press := Vector2(main._sx0 + 1.0, main._sy)
			var deferred := Vector2(main._sx1 - 1.0, main._sy)
			mouse_button(main, true, press)
			mouse_motion(main, deferred)
			ck(main._scrubbing and main._scrub_pending == main._tick_at_x(deferred.x), "public left-drag motion coalesces the deferred scrub target")
			Sim.player_trace_last_error = ""
			mouse_button(main, false, deferred)
			ck(main._scrub_pending < 0 and Sim.player_trace_last_error == "player_trace_unavailable", "public release flushes the deferred scrub attempt")
	Sim.player_trace_available = trace_available
	var after := stable_main_snapshot(main)
	ck(after == before and Sim.running and not main._scrubbing and main._scrub_pending < 0, "failed autoplay %s timeline route restores running and complete C1 snapshot" % name, snapshot_diff(before, after))

func partial_replay_failure(main: Node, via_mouse: bool) -> void:
	# Build a real player portal receipt, then coherently reseal a forged result so
	# replay gets past structural validation and fails at the replay boundary.
	Sim.backend = null; Sim.auto_run = false; Sim.start_new(20260825)
	main._player_mode = true; Sim.add_player(Vector2i(41, 19))
	main._probe.set_space("town", "outdoor", main._sg.bounds_px("town")); main._locked_ortho_c1.apply_fixed_frame(main._vp(), main._probe.HOME_PAD)
	tickn(2)
	main._probe.emit_signal("tapped", Vector2(41 * 48 + 24, 19 * 48 + 24))
	tickn(1)
	var forged := Sim.get_player_trace()
	var entries: Array = forged.get("entries", [])
	if entries.is_empty():
		ck(false, "partial replay setup records a real public portal trace")
		return
	var entry: Dictionary = entries[0]
	entry["receipt"]["event_digest"] = int(entry["receipt"].get("event_digest", 0)) + 1
	var unsigned := entry.duplicate(true); unsigned.erase("seal")
	entry["seal"] = Sim._player_trace_entry_seal(unsigned)
	entries[0] = entry; forged["entries"] = entries
	ck(Sim.set_player_trace_for_replay(forged), "coherently resealed partial replay fixture imports")
	Sim.running = true
	main._max_tick = maxi(main._max_tick, Sim.tick_no)
	var before := stable_main_snapshot(main)
	var trace_before := Sim.get_player_trace()
	var trace_status_before := Sim.player_trace_status(); trace_status_before.erase("error")
	if via_mouse:
		var press_x: float = main._sx1 - 1.0
		var deferred_x: float = main._sx0 + (main._sx1 - main._sx0) * (float(Sim.tick_no - 1) / float(maxi(1, main._max_tick)))
		mouse_button(main, true, Vector2(press_x, main._sy))
		Sim.player_trace_last_error = ""
		mouse_motion(main, Vector2(deferred_x, main._sy))
		ck(main._scrubbing and main._scrub_pending == main._tick_at_x(deferred_x), "partial replay left-drag queues real deferred target")
		mouse_button(main, false, Vector2(deferred_x, main._sy))
	else:
		var comma := InputEventKey.new(); comma.pressed = true; comma.keycode = KEY_COMMA
		main._unhandled_input(comma)
	var after := stable_main_snapshot(main)
	var trace_status_after := Sim.player_trace_status(); trace_status_after.erase("error")
	ck(Sim.player_trace_last_error == "recomputed_receipt_mismatch" and after == before and Sim.running and Sim.get_player_trace() == trace_before and trace_status_after == trace_status_before, "partial replay %s failure preserves live C1 authority and runtime" % ("mouse" if via_mouse else "keyboard"), snapshot_diff(before, after))

func find_button(root: Node, caption: String) -> Button:
	if root is Button and (root as Button).text == caption:
		return root as Button
	for child in root.get_children():
		var found := find_button(child, caption)
		if found != null:
			return found
	return null

func _ready() -> void:
	print("=== C1 locked-orthographic cafe contract ===")
	Sim.backend = null
	Sim.auto_run = false
	Sim.start_new(20260825)
	var stage := Node2D.new()
	add_child(stage)
	var probe = preload("res://scripts/ProbeController.gd").new()
	add_child(probe)
	probe.setup(stage, Rect2(0, 0, 64 * 48, 48 * 48))
	var view = preload("res://scripts/LockedOrthoC1.gd").new()
	add_child(view)
	view.setup(probe)
	var before_view := {"digest": Inv.digest(Sim), "event": Sim.event_digest, "trace": Sim.get_player_trace()}
	probe.active_space = "cafe"; probe.active_floor = "2f"
	ck(not bool(view.state().get("interactive", true)) and "仅供查看" in String(view.state().get("label", "")), "2F view context has zero interaction targets")
	probe.active_floor = "1f"
	ck(bool(view.state().get("interactive", false)), "1F public plane is selectable")
	probe.active_space = "town"; probe.active_floor = "outdoor"
	ck(before_view == {"digest": Inv.digest(Sim), "event": Sim.event_digest, "trace": Sim.get_player_trace()}, "frame/floor projection toggles add no authority trace")

	var player: Dictionary = Sim.add_player(Vector2i(41, 19))
	var enter: Dictionary = Sim.player_portal_intent({"source_space": "town", "source_floor": "outdoor", "portal_pos": Vector2i(41, 19)})
	ck(bool(enter.get("ok", false)) and String(enter.get("portal_id", "")) == "p_cafe_door" and String(player.get("space", "")) == "cafe" and String(player.get("floor", "")) == "1f", "public cafe door uses real player_portal_intent")

	# The player waits at the actual public door; no agent is injected or moved by
	# the test. A resident must arrive on the active plane before greet is allowed.
	var target: Dictionary = find_cafe_guest()
	for _i in range(900):
		if not target.is_empty():
			break
		Sim.tick()
		target = find_cafe_guest()
	ck(not target.is_empty(), "real resident arrives on active cafe 1F plane")
	if not target.is_empty():
		var target_id := String(target.get("id", ""))
		var greet := Sim.player_act("greet", target_id)
		tickn(32)
		var social_event := {}
		for raw in Sim.event_log:
			var ev: Dictionary = raw
			if String(ev.get("type", "")) == "greet" and String(ev.get("actor", "")) == "player" and String(ev.get("target", "")) == target_id:
				social_event = ev
		var after_greet := state()
		ck(greet == "" and not social_event.is_empty() and (after_greet["memory"] as Array).size() > 0 and (after_greet["relationships"] as Dictionary).has(target_id), "greet commits visible event, memory, relationship and digest consequence", "%s / %s" % [greet, str(social_event)])
		var save_path := "user://c1_locked_ortho.save"
		ck(Sim.save_game(save_path, {"test": "c1_locked_ortho"}), "save after real social consequence")
		var saved := state()
		Sim.start_new(9)
		ck(Sim.load_game(save_path) and state() == saved, "save/load restores C1 consequence and PlayerTrace")
		ck(Sim.goto_tick(int(saved["tick"])) and state() == saved, "goto_tick reproduces consequence without live AI")

	# Walk the actual 1F grid from the public door to the stair's adjacent cell.
	# This is intentionally player_move-only: no coordinates, topology, or nav
	# state is injected by the projection test.
	for direction in [Vector2i.LEFT, Vector2i.UP, Vector2i.UP, Vector2i.UP, Vector2i.LEFT, Vector2i.UP, Vector2i.LEFT]:
		Sim.player_move(direction)
	var pl: Dictionary = Sim.get_agent("player")
	ck(pl.get("pos", Vector2i.ZERO) == Vector2i(2, 1), "player movement reaches owner stair on canonical 48px grid", str(pl.get("pos", Vector2i.ZERO)))
	var before_denial := state()
	var denied: Dictionary = Sim.player_portal_intent({"source_space": "cafe", "source_floor": "1f", "portal_pos": Vector2i(1, 1)})
	var after_denial := state()
	ck(not bool(denied.get("ok", true)) and String(denied.get("reason", "")) == "portal_not_permitted" and String(after_denial["space"]) == "cafe" and String(after_denial["floor"]) == "1f" and after_denial["pos"] == before_denial["pos"], "owner-only stair denial retains 1F and player focus anchor")
	probe.active_space = "cafe"; probe.active_floor = "2f"
	ck(not bool(view.state().get("interactive", true)), "denied stair recovery may show only zero-target 2F context")
	probe.active_floor = "1f"; probe.active_space = "town"; probe.active_floor = "outdoor"
	for direction in [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.DOWN, Vector2i.DOWN, Vector2i.RIGHT]:
		Sim.player_move(direction)
	var return_receipt: Dictionary = Sim.player_portal_intent({"source_space": "cafe", "source_floor": "1f", "portal_pos": Vector2i(4, 5)})
	ck(bool(return_receipt.get("ok", false)) and String(Sim.get_agent("player").get("space", "")) == "town", "public cafe return restores town through real door")

	# Compose the actual Main router (rather than a duplicate input implementation)
	# and prove the C1 hook suppresses every exposed free-camera path while the
	# same Probe remains available to the feature-off product.
	var main = preload("res://scripts/Main.gd").new()
	add_child(main)
	await get_tree().process_frame
	main._activate_locked_ortho_c1()
	var locked_pos: Vector2 = main._probe.cam.position
	var locked_zoom: Vector2 = main._probe.cam.zoom
	var plus := InputEventKey.new(); plus.pressed = true; plus.keycode = KEY_EQUAL
	main._unhandled_input(plus)
	var right := InputEventMouseButton.new(); right.pressed = true; right.button_index = MOUSE_BUTTON_RIGHT; right.position = Vector2(100, 100)
	main._unhandled_input(right)
	var drag := InputEventMouseMotion.new(); drag.position = Vector2(300, 300); drag.relative = Vector2(200, 200)
	main._unhandled_input(drag)
	ck(main._probe.cam.position == locked_pos and main._probe.cam.zoom == locked_zoom, "actual Main C1 router rejects keyboard zoom and mouse pan")
	Sim.backend = null; Sim.auto_run = false; Sim.start_new(20260825)
	main._player_mode = true; Sim.add_player(Vector2i(41, 19))
	main._probe.set_space("town", "outdoor", main._sg.bounds_px("town")); main._locked_ortho_c1.apply_fixed_frame(main._vp(), main._probe.HOME_PAD)
	# Emit the Probe's real tap signal rather than calling the portal helper:
	# this is the same left-tap callback connected by Main._ready.
	main._probe.emit_signal("tapped", Vector2(41 * 48 + 24, 19 * 48 + 24))
	var entered: Dictionary = Sim.get_agent("player")
	var cafe_size := Vector2(8 * 48, 6 * 48)
	var cafe_zoom := minf((main._vp() - main._probe.HOME_PAD).x / cafe_size.x, (main._vp() - main._probe.HOME_PAD).y / cafe_size.y)
	ck(String(entered.get("space", "")) == "cafe" and String(main._probe.active_space) == "cafe" and String(main._probe.active_floor) == "1f" and main._probe.cam.position == cafe_size * 0.5 and main._probe.cam.zoom == Vector2.ONE * cafe_zoom, "real Main left-tap door follows public receipt then locks exact 1F frame")
	for code in [KEY_LEFT, KEY_UP, KEY_UP, KEY_UP, KEY_LEFT, KEY_UP, KEY_LEFT]:
		var move := InputEventKey.new(); move.pressed = true; move.keycode = code; main._unhandled_input(move)
	var stair_frame := {"space": main._probe.active_space, "floor": main._probe.active_floor, "pos": main._probe.cam.position, "zoom": main._probe.cam.zoom}
	var stair_player: Dictionary = Sim.get_agent("player")
	main._probe.emit_signal("tapped", Vector2(1 * 48 + 24, 1 * 48 + 24))
	var denied_player: Dictionary = Sim.get_agent("player")
	ck(String(main._probe.active_floor) == "1f" and {"space": main._probe.active_space, "floor": main._probe.active_floor, "pos": main._probe.cam.position, "zoom": main._probe.cam.zoom} == stair_frame and denied_player.get("pos") == stair_player.get("pos") and "portal_not_permitted" in main._locked_ortho_c1.feedback_text(), "real Main left-tap owner stair cannot inspect 2F or move C1 frame")
	main._update_obs()
	await get_tree().process_frame
	ck("portal_not_permitted" in main._locked_ortho_c1.feedback_text(), "ordinary same-world UI processing preserves visible owner denial")
	# A real NPC settings button resets the canonical world. The old denial is
	# strictly transient, so public cafe re-entry in the new world cannot redraw it.
	main._player_spawn_override = Vector2i(41, 19)
	var reset_npc_plus := find_button(main._settings_panel, "+")
	ck(reset_npc_plus != null, "settings reset control exists for denial lifetime path")
	if reset_npc_plus != null:
		reset_npc_plus.emit_signal("pressed")
	ck(main._locked_ortho_c1.feedback_text() == "" and String(main._probe.active_space) == "town" and String(Sim.get_agent("player").get("space", "")) == "town", "successful settings reset clears prior-world stair denial feedback")
	main._probe.emit_signal("tapped", Vector2(41 * 48 + 24, 19 * 48 + 24))
	ck(String(Sim.get_agent("player").get("space", "")) == "cafe" and main._locked_ortho_c1.feedback_text() == "", "fresh public cafe entry never displays prior-world portal denial")
	# Use real left-button press/release through Main -> Probe.handle_input. The
	# adjacent home door is public in the world but deliberately outside C1's
	# presentation allowlist, so it must not emit a Sim portal intent at all.
	Sim.backend = null; Sim.auto_run = false; Sim.start_new(20260825)
	main._player_mode = true; Sim.add_player(Vector2i(22, 19))
	main._probe.set_space("town", "outdoor", main._sg.bounds_px("town")); main._locked_ortho_c1.apply_fixed_frame(main._vp(), main._probe.HOME_PAD)
	var unsupported_before := {"sim": state(), "space": main._probe.active_space, "floor": main._probe.active_floor, "pos": main._probe.cam.position, "zoom": main._probe.cam.zoom}
	var home_world := Vector2(22 * 48 + 24, 19 * 48 + 24)
	var home_screen: Vector2 = main._vp() * 0.5 + (home_world - main._probe.cam.position) * main._probe.cam.zoom
	var left_down := InputEventMouseButton.new(); left_down.pressed = true; left_down.button_index = MOUSE_BUTTON_LEFT; left_down.position = home_screen
	var left_up := InputEventMouseButton.new(); left_up.pressed = false; left_up.button_index = MOUSE_BUTTON_LEFT; left_up.position = home_screen
	main._unhandled_input(left_down); main._unhandled_input(left_up)
	var unsupported_after := {"sim": state(), "space": main._probe.active_space, "floor": main._probe.active_floor, "pos": main._probe.cam.position, "zoom": main._probe.cam.zoom}
	ck(unsupported_after == unsupported_before and "路线外" in main._locked_ortho_c1.feedback_text(), "real left input rejects adjacent public non-cafe door before Sim intent with exact C1 immutability")
	# All five real Main timeline entrances attempt a rejected replay while live
	# autoplay is on. They must restore the running bit and every View observable.
	Sim.tick()
	# The real tick signal normally advances this presentation-only range.  This
	# composed test drives Sim directly, so seed the same observed range here.
	main._max_tick = maxi(main._max_tick, Sim.tick_no)
	main._update_scrubber()
	scrub_input_boundaries(main)
	for route in ["comma", "left", "right", "scrub", "flush"]:
		failed_timeline_route(main, route)
	partial_replay_failure(main, false)
	partial_replay_failure(main, true)
	# The rejected replay diagnostic is expected and explicitly excluded above;
	# clear it before the following independent real-player scenario.
	Sim.player_trace_last_error = ""
	# F8 must use Main's public router too. Preserve any test-runtime quicksave,
	# temporarily remove it to make the product path fail, then restore its bytes.
	var quick_path: String = main.QUICKSAVE
	var quick_existed := FileAccess.file_exists(quick_path)
	var quick_bytes := FileAccess.get_file_as_bytes(quick_path) if quick_existed else PackedByteArray()
	if quick_existed:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(quick_path))
	Sim.running = true
	main._update_status()
	var failed_load_before := stable_main_snapshot(main, false)
	var f8 := InputEventKey.new(); f8.pressed = true; f8.keycode = KEY_F8
	main._unhandled_input(f8)
	var failed_load_after := stable_main_snapshot(main, false)
	ck(failed_load_after == failed_load_before, "failed public Main F8 quick-load preserves complete C1 snapshot", snapshot_diff(failed_load_before, failed_load_after))
	if quick_existed:
		var restore := FileAccess.open(quick_path, FileAccess.WRITE)
		if restore != null:
			restore.store_buffer(quick_bytes)
	# Save through Main's public quick-save/load route, then enter through the
	# connected Probe tap.  Loading must read Sim's restored plane back into the
	# Probe before the per-frame fixed-frame pass can preserve stale cafe state.
	Sim.backend = null; Sim.auto_run = false; Sim.start_new(20260825)
	main._player_mode = true; Sim.add_player(Vector2i(41, 19))
	main._probe.set_space("town", "outdoor", main._sg.bounds_px("town")); main._locked_ortho_c1.apply_fixed_frame(main._vp(), main._probe.HOME_PAD)
	main._quick_save()
	var saved_town := state()
	main._probe.emit_signal("tapped", Vector2(41 * 48 + 24, 19 * 48 + 24))
	ck(String(Sim.get_agent("player").get("space", "")) == "cafe", "save/load setup enters cafe through connected public door")
	deny_owner_stair(main)
	ck("portal_not_permitted" in main._locked_ortho_c1.feedback_text(), "real stair denial seeds transient feedback before successful quick-load")
	var load_resident := wait_cafe_resident()
	var load_name := str(load_resident.get("persona", {}).get("name", ""))
	if not load_resident.is_empty():
		main._focus_agent(String(load_resident.get("id", "")))
		ck(main._obs.text.contains(load_name), "cafe resident is visibly selected before cross-plane quick-load")
	main._quick_load()
	var town_size := Vector2(64 * 48, 48 * 48)
	var town_zoom := minf((main._vp() - main._probe.HOME_PAD).x / town_size.x, (main._vp() - main._probe.HOME_PAD).y / town_size.y)
	ck(not load_name.is_empty() and state() == saved_town and String(main._probe.active_space) == "town" and String(main._probe.active_floor) == "outdoor" and main._probe.cam.position == town_size * 0.5 and main._probe.cam.zoom == Vector2.ONE * town_zoom and main._selected_id == "" and not main._obs.text.contains(load_name) and main._locked_ortho_c1.feedback_text() == "", "Main quick-load reconciles canonical town, Probe plane, selection, observation panel, transient feedback and fixed town frame")
	# Make a fresh real café denial part of a later timeline, then use the actual
	# bracket key route to jump before it. No adapter receipt is fabricated here.
	Sim.backend = null; Sim.auto_run = false; Sim.start_new(20260825)
	tickn(2) # establish a town timeline before the player enters it
	main._player_mode = true; Sim.add_player(Vector2i(41, 19))
	main._probe.set_space("town", "outdoor", main._sg.bounds_px("town")); main._locked_ortho_c1.apply_fixed_frame(main._vp(), main._probe.HOME_PAD)
	tickn(1)
	Sim.running = false
	main._probe.emit_signal("tapped", Vector2(41 * 48 + 24, 19 * 48 + 24))
	ck(String(Sim.get_agent("player").get("space", "")) == "cafe", "timeline setup re-enters cafe through public door", str(Sim.get_agent("player").get("pos", Vector2i.ZERO)))
	deny_owner_stair(main)
	ck("portal_not_permitted" in main._locked_ortho_c1.feedback_text(), "real owner-stair denial is visible before successful timeline jump", "%s / %s" % [main._locked_ortho_c1.feedback_text(), str(Sim.get_agent("player").get("pos", Vector2i.ZERO))])
	var jump_resident := wait_cafe_resident()
	var jump_name := str(jump_resident.get("persona", {}).get("name", ""))
	if not jump_resident.is_empty():
		main._focus_agent(String(jump_resident.get("id", "")))
		ck(main._obs.text.contains(jump_name), "cafe resident is visibly selected before real timeline jump")
	# One real bracket jump is one simulated day. Advance far enough that it
	# lands at the player-spawn town tick, before the café door receipt.
	tickn(maxi(0, int(Sim.TICKS_PER_DAY) + 2 - Sim.tick_no))
	var before_timeline_trace := Sim.get_player_trace().duplicate(true)
	var rewind := InputEventKey.new(); rewind.pressed = true; rewind.keycode = KEY_BRACKETLEFT
	main._unhandled_input(rewind)
	ck(not jump_name.is_empty() and Sim.tick_no == 2 and String(Sim.get_agent("player").get("space", "")) == "town" and String(main._probe.active_space) == "town" and String(main._probe.active_floor) == "outdoor" and main._probe.cam.position == town_size * 0.5 and main._probe.cam.zoom == Vector2.ONE * town_zoom and main._selected_id == "" and not main._obs.text.contains(jump_name) and "点一个居民" in main._obs.text and main._locked_ortho_c1.feedback_text() == "" and Sim.get_player_trace() == before_timeline_trace, "actual timeline jump clears stale cafe observation and transient feedback in the same reconciled town frame")
	# Exercise the actual settings controls from a cafe frame.  Turning player
	# mode off is a successful Sim.start_new with no canonical player, so C1 must
	# choose its deterministic town observer frame rather than retain cafe/1F.
	main._probe.emit_signal("tapped", Vector2(41 * 48 + 24, 19 * 48 + 24))
	# The test enabled player mode through the product setup, so synchronize the
	# existing settings label before finding and pressing that real control.
	main._sync_player_btn()
	var player_button := find_button(main._settings_panel, "开（你已入镇）")
	ck(player_button != null, "settings player-mode control is composed in real Main")
	if player_button != null:
		player_button.emit_signal("pressed")
	ck(Sim.get_agent("player").is_empty() and not main._player_mode and String(main._probe.active_space) == "town" and String(main._probe.active_floor) == "outdoor" and main._probe.cam.position == town_size * 0.5 and main._probe.cam.zoom == Vector2.ONE * town_zoom and main._selected_id == "", "settings player-mode reset clears stale cafe plane into deterministic no-player town frame")
	player_button = find_button(main._settings_panel, "关（只观察）")
	if player_button != null:
		player_button.emit_signal("pressed")
	main._probe.emit_signal("tapped", Vector2(41 * 48 + 24, 19 * 48 + 24))
	var npc_plus := find_button(main._settings_panel, "+")
	ck(npc_plus != null, "settings NPC increment control is composed in real Main")
	if npc_plus != null:
		npc_plus.emit_signal("pressed")
	ck(main._player_mode and String(Sim.get_agent("player").get("space", "")) == "town" and String(main._probe.active_space) == "town" and String(main._probe.active_floor) == "outdoor" and main._probe.cam.position == town_size * 0.5 and main._probe.cam.zoom == Vector2.ONE * town_zoom, "settings NPC reset reconciles canonical player town and C1 frame")
	# A no-op settings request is not a reset and must leave every View field
	# untouched; this is the guard against unconditional reconciliation.
	main._npc_target = 6
	main._probe.emit_signal("tapped", Vector2(41 * 48 + 24, 19 * 48 + 24))
	var no_reset_before := {"sim": state(), "space": main._probe.active_space, "floor": main._probe.active_floor, "pos": main._probe.cam.position, "zoom": main._probe.cam.zoom}
	main._apply_npc(0)
	var no_reset_after := {"sim": state(), "space": main._probe.active_space, "floor": main._probe.active_floor, "pos": main._probe.cam.position, "zoom": main._probe.cam.zoom}
	ck(no_reset_after == no_reset_before, "non-reset NPC input fabricates no C1 View change")
	main._locked_ortho_c1 = null
	main._unhandled_input(plus)
	ck(main._probe.cam.zoom != locked_zoom, "feature-off Main router preserves Probe zoom behavior")

	print("c1_locked_ortho_test: %s (%d fail)" % [("PASS" if fails == 0 else "FAIL"), fails])
	get_tree().quit(0 if fails == 0 else 1)
