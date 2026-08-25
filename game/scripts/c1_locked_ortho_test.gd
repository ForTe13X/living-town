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
	main._quick_load()
	var town_size := Vector2(64 * 48, 48 * 48)
	var town_zoom := minf((main._vp() - main._probe.HOME_PAD).x / town_size.x, (main._vp() - main._probe.HOME_PAD).y / town_size.y)
	ck(state() == saved_town and String(main._probe.active_space) == "town" and String(main._probe.active_floor) == "outdoor" and main._probe.cam.position == town_size * 0.5 and main._probe.cam.zoom == Vector2.ONE * town_zoom and main._selected_id == "", "Main quick-load reconciles canonical town, Probe plane, selection and fixed town frame")
	# Make the door receipt part of a later timeline, then use the actual bracket
	# key route to jump before it.  Direct Probe assignment here would hide the
	# precise regression this test is intended to catch.
	tickn(3)
	main._probe.emit_signal("tapped", Vector2(41 * 48 + 24, 19 * 48 + 24))
	tickn(2)
	var before_timeline_trace := Sim.get_player_trace().duplicate(true)
	var rewind := InputEventKey.new(); rewind.pressed = true; rewind.keycode = KEY_BRACKETLEFT
	main._unhandled_input(rewind)
	ck(Sim.tick_no == 0 and String(Sim.get_agent("player").get("space", "")) == "town" and String(main._probe.active_space) == "town" and String(main._probe.active_floor) == "outdoor" and main._probe.cam.position == town_size * 0.5 and main._probe.cam.zoom == Vector2.ONE * town_zoom and Sim.get_player_trace() == before_timeline_trace, "actual timeline jump reconciles replayed canonical town with immutable C1 frame")
	main._locked_ortho_c1 = null
	main._unhandled_input(plus)
	ck(main._probe.cam.zoom != locked_zoom, "feature-off Main router preserves Probe zoom behavior")

	print("c1_locked_ortho_test: %s (%d fail)" % [("PASS" if fails == 0 else "FAIL"), fails])
	get_tree().quit(0 if fails == 0 else 1)
