extends Node
## A recording director around the actual Main, never a substitute simulation.
## Use a real renderer with --fixed-fps 18 --write-movie <capture.avi>.
## User args: --town3d --backend logic --agents 12 --no-player --seed 7
##            --walkthrough-dir <absolute> [--walkthrough-preview]
## Architectural inspection changes only Probe/visibility/UI presentation.
const MainScene = preload("res://scenes/Main.tscn")
const FPS: int = 18
const FULL_SECONDS: int = 840
const FULL_STARTS: Array[float] = [0, 45, 100, 155, 215, 285, 355, 455, 555, 665, 735, 805, 840]
const PREVIEW_STARTS: Array[float] = [0, 6, 13, 26, 43, 58, 66, 73, 78, 82, 85, 88, 90]
const CHAPTERS: Array[String] = ["Town, woodland and coast", "Meet Aria in her upper home", "Rooms, stairs and needs", "The actual cafe and street", "Walk into the expanded town", "Use a new venue and its upper floor", "Walk to the reserve bathhouse", "Visit a detailed camping trailer", "Walk back from the reserve to town", "Inspection: forest, bridges and horticulture", "Save, resume and resident agency", "Complete town and scope"]

var main: Node
var view: Node
var life: Node
var model: Node
var probe: Node
var preview: bool = false
var output_dir: String = ""
var frame_no: int = 0
var total_frames: int = 15120
var tour_active: bool = false
var finishing: bool = false
var camera_override: bool = false
var camera_space: String = "town"
var camera_floor: String = "outdoor"
var camera_center: Vector2 = Vector2.ZERO
var camera_zoom: float = 0.3
var inspection_active: bool = false
var chapter_card: Label
var checks_failed: int = 0
var chapter_index: int = -1
var social_events: Array[Dictionary] = []
var action_events: Array[Dictionary] = []
var reset_events: Array[Dictionary] = []
var report: Dictionary = {"schema": "living_town.walkthrough.v1", "checks": [], "chapters": [], "input_events": [], "captures": [], "snapshots": [], "camera_keyframes": [], "direct_agent_writes": false, "route_complete": false}


func seconds() -> float:
	return float(frame_no) / FPS


func chapter_time(index: int) -> float:
	return PREVIEW_STARTS[index] if preview else FULL_STARTS[index]


func at(full_second: float) -> float:
	if not preview:
		return full_second
	for index: int in range(FULL_STARTS.size() - 1):
		if full_second <= FULL_STARTS[index + 1]:
			var u: float = inverse_lerp(FULL_STARTS[index], FULL_STARTS[index + 1], full_second)
			return lerpf(PREVIEW_STARTS[index], PREVIEW_STARTS[index + 1], u)
	return PREVIEW_STARTS[-1]


func wait_to(target: float) -> void:
	while seconds() < target and not finishing:
		await get_tree().process_frame


func wait_frames(count: int) -> void:
	for index: int in range(count):
		if finishing:
			return
		await get_tree().process_frame


func ck(label: String, passed: bool, detail: Variant = null) -> void:
	report["checks"].append({"name": label, "passed": passed, "tour_frame": frame_no, "tour_seconds": seconds(), "detail": detail})
	if not passed:
		checks_failed += 1
	print(("PASS " if passed else "FAIL ") + "WALKTHROUGH " + label)


func skipped_preview_check(label: String, reason: String) -> void:
	# Kept separate from passing booleans: an omitted journey proves no action.
	if not report.has("skipped_checks"):
		report["skipped_checks"] = []
	report["skipped_checks"].append({"name": label, "status": "SKIP", "reason": reason, "tour_frame": frame_no, "tour_seconds": seconds()})
	print("SKIP WALKTHROUGH " + label + ": " + reason)


func snapshot(label: String) -> Dictionary:
	var resident: Dictionary = Sim.get_agent("aria")
	var state: Dictionary = {"label": label, "tour_frame": frame_no, "tour_seconds": seconds(), "tick": Sim.tick_no, "day": Sim.day,
		"controlled_id": Sim.controlled_id, "resident_plane": str(resident.get("space", "")) + "/" + str(resident.get("floor", "")),
		"resident_position": str(resident.get("pos", Vector2i.ZERO)), "needs": resident.get("needs", {}).duplicate(true), "coin": Sim._coin_of("aria"),
		"option": resident.get("option").duplicate(true) if resident.get("option") is Dictionary else {},
		"active_view_plane": str(probe.get("active_space")) + "/" + str(probe.get("active_floor")), "free_will": bool(life.get("free_will")),
		"world_running": Sim.running, "world_speed": Sim.speed, "social_events_observed": social_events.size()}
	report["snapshots"].append(state)
	return state


func start_chapter(index: int, architectural: bool = false) -> void:
	chapter_index = index
	var title: String = CHAPTERS[index]
	var omitted_preview_journey: bool = preview and index >= 4 and index <= 8
	if omitted_preview_journey:
		title = ["Expanded-town walk omitted", "New venue/upper floor omitted", "Reserve bathhouse walk/use omitted", "Trailer visit/use omitted", "Reserve-to-core return omitted"][index - 4]
	var record: Dictionary = {"index": index + 1, "title": title, "planned_start_seconds": chapter_time(index), "actual_start_seconds": seconds(), "tour_frame": frame_no, "architectural_inspection": architectural}
	if omitted_preview_journey:
		record["preview_journey_skipped"] = true
	report["chapters"].append(record)
	chapter_card.text = ("PREVIEW: JOURNEY SKIPPED  |  " if omitted_preview_journey else ("CAMERA INSPECTION  |  " if architectural else "ACTUAL GAMEPLAY  |  ")) + title
	snapshot(title)
	print("WALKTHROUGH CHAPTER ", index + 1, " frame=", frame_no, " tick=", Sim.tick_no)


func _process(_delta: float) -> void:
	if not tour_active or finishing:
		return
	# Camera studies retain their label while observer cards stay out of the model.
	if inspection_active:
		hide_observer_chrome()
	if camera_override and probe != null and view != null:
		# LifeMode has priority 0; this director is 49; the actual view is 50.
		# Set only presentation state, leaving canonical actor address untouched.
		probe.set("mode", 0)
		probe.set("follow_id", "")
		probe.set("demo_cam", false)
		if str(probe.get("active_space")) != camera_space or str(probe.get("active_floor")) != camera_floor:
			probe.call("set_space", camera_space, camera_floor, main.get("_sg").bounds_px(camera_space))
		var camera: Camera2D = probe.get("cam") as Camera2D
		camera.position = camera_center
		camera.zoom = Vector2.ONE * camera_zoom
		view.call("sync_camera")
	frame_no += 1
	if frame_no >= total_frames:
		call_deferred("finish")


func key(code: Key) -> void:
	report["input_events"].append({"kind": "key", "keycode": int(code), "tour_frame": frame_no, "tick": Sim.tick_no})
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	get_viewport().push_input(event, true)
	await wait_frames(1)
	var release: InputEventKey = InputEventKey.new()
	release.keycode = code
	release.physical_keycode = code
	get_viewport().push_input(release, true)
	await wait_frames(2)


func click(point: Vector2) -> void:
	report["input_events"].append({"kind": "mouse_click", "screen": [point.x, point.y], "tour_frame": frame_no, "tick": Sim.tick_no})
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = point
	event.global_position = point
	event.pressed = true
	get_viewport().push_input(event, true)
	await wait_frames(1)
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = point
	release.global_position = point
	get_viewport().push_input(release, true)
	await wait_frames(2)


func wait_walk(deadline: float) -> bool:
	while bool(life.get("_walk_on")) and seconds() < deadline and not finishing:
		await wait_frames(1)
	return not bool(life.get("_walk_on"))


func close_menu() -> void:
	if bool(life.get("_modal_open")):
		await key(KEY_ESCAPE)


func click_portal(ident: String, deadline: float) -> bool:
	await close_menu()
	var portal: Dictionary = {}
	for candidate: Dictionary in Sim._portals:
		if candidate.get("id") == ident:
			portal = candidate
	var resident: Dictionary = Sim.get_agent("aria")
	var endpoint: Dictionary = {}
	for side: String in ["from", "to"]:
		var address: Dictionary = portal.get(side, {})
		if address.get("space") == resident.get("space") and address.get("floor") == resident.get("floor"):
			endpoint = address
	if endpoint.is_empty():
		return false
	var previous: String = str(resident["space"]) + "/" + str(resident["floor"])
	var cell: Vector2 = Vector2(float(endpoint["pos"][0]), float(endpoint["pos"][1])) * 48.0 + Vector2(24, 24)
	for attempt: int in range(3):
		if seconds() >= deadline:
			return false
		await click(view.canonical_to_screen(cell))
		if bool(life.get("_modal_open")):
			var selected: Dictionary = life.get("_modal_entry")
			if selected.get("id") == ident:
				await key(KEY_1)
			else:
				await close_menu()
		await wait_walk(deadline)
		await wait_frames(8)
		resident = Sim.get_agent("aria")
		if str(resident["space"]) + "/" + str(resident["floor"]) != previous:
			return true
	return false


func use_fixture(requested: String, preferred_action: String, deadline: float, hold_menu: float = 0.0) -> bool:
	await close_menu()
	await click(view.object_screen_position(requested))
	var selected: Dictionary = life.get("_modal_entry")
	var selected_id: String = str(selected.get("id", ""))
	var bindings: Dictionary = view.get("projection_3d").get("interaction_bindings", {})
	var wanted: Dictionary = bindings.get(requested, {})
	var picked: Dictionary = bindings.get(selected_id, {})
	var same_mesh: bool = not str(wanted.get("model_asset_id", "")).is_empty() and wanted.get("model_asset_id") == picked.get("model_asset_id") and wanted.get("plane") == picked.get("plane")
	ck("actual_mesh_menu_" + requested, bool(life.get("_modal_open")) and selected.get("kind") == "object" and same_mesh, {"requested_id": requested, "selected_id": selected_id, "same_imported_mesh_and_plane": same_mesh, "requested_binding": wanted, "selected_binding": picked})
	if not same_mesh:
		await close_menu()
		return false
	if requested in ["cafe1f_table", "cafe1f_counter"]:
		# Exercise the visible toolbar through the GUI while a genuine fixture
		# menu owns input. A disabled clock must neither resume nor dismiss it.
		var status: RichTextLabel = main.get("_status") as RichTextLabel
		ck("real_fixture_menu_status_reports_pause", status != null and status.text.contains("已暂停"), status.text if status != null else "missing status label")
		var town_hud: Node = main.get("_town_hud")
		var clock_buttons: Array = town_hud.get("buttons") if town_hud != null else []
		var guarded: Button = clock_buttons[3] as Button if clock_buttons.size() == 4 else null
		var available: bool = guarded != null and guarded.is_visible_in_tree() and guarded.disabled
		ck("real_fixture_menu_clock_disabled", available)
		if not available:
			return false
		var menu_tick: int = Sim.tick_no
		var menu_speed: float = Sim.speed
		await click(guarded.get_global_rect().get_center())
		var menu_kept: bool = bool(life.get("_modal_open")) and (life.get("_modal_entry") as Dictionary).get("id") == selected_id
		ck("disabled_clock_click_preserves_real_menu_and_pause", menu_kept and not Sim.running and Sim.tick_no == menu_tick and is_equal_approx(Sim.speed, menu_speed))
		if not menu_kept:
			return false
	var actions: Array = selected.get("actions", [])
	var choice: int = -1
	for index: int in range(mini(9, actions.size())):
		var advertisement: Dictionary = actions[index]
		if bool(advertisement.get("ok", false)) and (preferred_action == "" or advertisement.get("action") == preferred_action):
			choice = index
			break
	if choice < 0 and preferred_action != "":
		for index: int in range(mini(9, actions.size())):
			if bool((actions[index] as Dictionary).get("ok", false)):
				choice = index
				break
	if choice < 0:
		ck("fixture_legal_action_" + requested, false, actions)
		await close_menu()
		return false
	var advertisement: Dictionary = actions[choice]
	var action: String = str(advertisement.get("action", ""))
	var need: String = str(advertisement.get("need", ""))
	var before: float = float(Sim.get_agent("aria")["needs"].get(need, 0))
	var coin_before: int = Sim._coin_of("aria")
	var event_start: int = action_events.size()
	await capture("fixture_menu_" + requested)
	await wait_to(minf(deadline - 0.5, seconds() + hold_menu))
	await key(KEY_1 + choice)
	var saw_use: bool = false
	var completion: Dictionary = {}
	var previous_need: float = before
	var largest_step: float = 0
	while seconds() < deadline and not finishing:
		await wait_frames(1)
		var resident: Dictionary = Sim.get_agent("aria")
		var option: Dictionary = resident.get("option") if resident.get("option") is Dictionary else {}
		var using: bool = option.get("target") == selected_id and option.get("action") == action and option.get("phase") == "use"
		saw_use = saw_use or using
		var value: float = float(resident["needs"].get(need, 0))
		if using:
			largest_step = maxf(largest_step, value - previous_need)
		previous_need = value
		for index: int in range(event_start, action_events.size()):
			if action_events[index].get("target") == selected_id and action_events[index].get("action") == action:
				completion = action_events[index]
		if not completion.is_empty():
			break
	var after: float = float(Sim.get_agent("aria")["needs"].get(need, 0))
	var coins: int = Sim._coin_of("aria") - coin_before
	var success: bool = saw_use and not completion.is_empty() and (after - before > 0.1 or largest_step > 0.1 or coins > 0)
	ck("real_fixture_action_" + requested, success, {"selected_target": selected_id, "advertised_action": advertisement, "use_phase_observed": saw_use, "need_before": before, "need_after": after, "largest_observed_use_need_step": largest_step, "coin_change": coins, "completion": completion})
	snapshot("after_" + requested)
	return success


func capture(label: String) -> void:
	if finishing:
		return
	await wait_frames(2)
	await RenderingServer.frame_post_draw
	var texture: ViewportTexture = get_viewport().get_texture()
	var image: Image = texture.get_image() if texture != null else null
	if image == null or image.is_empty():
		ck("actual_framebuffer_" + label, false, DisplayServer.get_name())
		return
	var path: String = output_dir.path_join(label + ".png")
	var result: Error = image.save_png(path)
	ck("actual_framebuffer_" + label, result == OK, {"size": [image.get_width(), image.get_height()]})
	if result == OK:
		report["captures"].append({"file": path, "sha256": FileAccess.get_sha256(path), "tour_frame": frame_no, "tour_seconds": seconds(), "tick": Sim.tick_no, "chapter": chapter_index + 1})


func set_camera(space_id: String, floor_id: String, center: Vector2, size_m: float) -> void:
	camera_override = true
	camera_space = space_id
	camera_floor = floor_id
	camera_center = center
	var viewport: SubViewport = view.get("viewport_3d") as SubViewport
	camera_zoom = maxf(0.025, float(viewport.size.y) * (1.7 / 48.0) / size_m)


func glide(space_id: String, floor_id: String, from: Vector2, to: Vector2, size_from: float, size_to: float, end: float) -> void:
	var start: float = seconds()
	report["camera_keyframes"].append({"space": space_id, "floor": floor_id, "start_seconds": start, "end_seconds": end, "from_canonical_px": [from.x, from.y], "to_canonical_px": [to.x, to.y], "from_height_m": size_from, "to_height_m": size_to, "presentation_only": true})
	while seconds() < end and not finishing:
		var u: float = clampf(inverse_lerp(start, maxf(start + 0.001, end), seconds()), 0, 1)
		u = u * u * (3.0 - 2.0 * u)
		set_camera(space_id, floor_id, from.lerp(to, u), lerpf(size_from, size_to, u))
		await wait_frames(1)


func town_point(x: float, y: float) -> Vector2:
	return view.world_to_canonical(Vector3(x, 0, -y), "town", "outdoor")


func room_center(space_id: String, floor_id: String) -> Vector2:
	var plane: Dictionary = view.get("projection_3d").get("planes", {}).get(space_id + "/" + floor_id, {})
	var size: Array = plane.get("grid_size", [1, 1])
	return Vector2(float(size[0]), float(size[1])) * 24.0


func inspection(on: bool) -> void:
	# These are presentation nodes/controls only; no actor/clock/address mutation.
	life.set_process(not on)
	inspection_active = on
	# A mid-chapter study must carry the same explicit label as a whole chapter.
	if chapter_card != null and chapter_index >= 0 and not (preview and chapter_index >= 4 and chapter_index <= 8):
		chapter_card.text = ("CAMERA INSPECTION  |  " if on else "ACTUAL GAMEPLAY  |  ") + CHAPTERS[chapter_index]
	var hud: Control = life.get("_hud") as Control
	if hud != null:
		hud.visible = not on
	if life.has_method("_set_main_chrome"):
		life.call("_set_main_chrome", false)
	hide_observer_chrome()
	var prompt: Control = life.get("_prompt") as Control
	if prompt != null and on:
		prompt.hide()
	var toast: Control = life.get("_toast") as Control
	if toast != null and on:
		toast.hide()
	if not on:
		camera_override = false
		# The compact activity feed is part of the ordinary town HUD. Architectural
		# inspection hides it; restore it with the resident controls for gameplay.
		if main.get("_town_hud") != null:
			for property: String in ["_log_card", "_logbox"]:
				var item: Control = main.get(property) as Control
				if item != null:
					item.show()


func demonstrate_compact_hud(deadline: float) -> void:
	var town_hud: Node = main.get("_town_hud")
	var history: Button = town_hud.get("activity") as Button if town_hud != null else null
	var wishes: Button = life.get("_town_wants_toggle") as Button
	var available: bool = history != null and wishes != null and history.is_visible_in_tree() and wishes.is_visible_in_tree()
	ck("compact_hud_real_buttons_available", available)
	if not available:
		return
	var original_tick: int = Sim.tick_no
	if bool(town_hud.get("expanded")):
		await click(history.get_global_rect().get_center())
	if bool(life.get("_town_wants_expanded")):
		await click(wishes.get_global_rect().get_center())
	await click(history.get_global_rect().get_center())
	await click(wishes.get_global_rect().get_center())
	ck("actual_hud_history_and_wishes_expand", bool(town_hud.get("expanded")) and bool(life.get("_town_wants_expanded")))
	await capture("02b_expandable_activity_and_wishes")
	await wait_to(deadline)
	await click(history.get_global_rect().get_center())
	await click(wishes.get_global_rect().get_center())
	ck("actual_hud_collapses_without_advancing_paused_clock", not bool(town_hud.get("expanded")) and not bool(life.get("_town_wants_expanded")) and Sim.tick_no == original_tick)


func hide_observer_chrome() -> void:
	for property: String in ["_obs", "_obs_pan", "_obs_card", "_obs_btn", "_scrub_pan", "_scrub_card", "_scrub_track", "_scrub_fill", "_scrub_handle", "_scrub_hint", "_chat_in", "_log_pan", "_log_card", "_logbox", "_goals_pan", "_story_pan", "_ledger_pan"]:
		var item: Variant = main.get(property)
		if item is CanvasItem:
			(item as CanvasItem).hide()


func _on_action(action: String, target: String, wage: int) -> void:
	action_events.append({"action": action, "target": target, "wage": wage, "tour_frame": frame_no, "tick": Sim.tick_no})


func _on_social(event: Dictionary) -> void:
	if social_events.size() < 500:
		var observed: Dictionary = event.duplicate(true)
		observed["tour_frame"] = frame_no
		social_events.append(observed)


func _on_reset() -> void:
	var resident: Dictionary = Sim.get_agent("aria")
	reset_events.append({"tour_frame": frame_no, "tick": Sim.tick_no, "space": resident.get("space"), "floor": resident.get("floor"), "pos": str(resident.get("pos")), "profile": Sim.loaded_meta.get("world_profile", {})})


func social_attempt(deadline: float) -> void:
	await close_menu()
	var resident: Dictionary = Sim.get_agent("aria")
	var candidates: Array[Dictionary] = []
	for agent: Dictionary in Sim.agents:
		if agent.get("id") != "aria" and agent.get("space") == resident.get("space") and agent.get("floor") == resident.get("floor"):
			candidates.append(agent)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Vector2(a["pos"]).distance_squared_to(Vector2(resident["pos"])) < Vector2(b["pos"]).distance_squared_to(Vector2(resident["pos"])))
	if candidates.is_empty():
		report["social_attempt"] = {"result": "No other resident on current plane; no actor was relocated.", "tour_frame": frame_no}
		return
	var target: String = str(candidates[0]["id"])
	var point: Vector2 = view.canonical_to_screen(view._rpos(candidates[0]), "", "", 0.8)
	await click(point)
	var selected: Dictionary = life.get("_modal_entry")
	if not bool(life.get("_modal_open")) or selected.get("kind") != "agent":
		report["social_attempt"] = {"target": target, "result": "Screen click did not resolve to an agent; no synthetic interaction inserted."}
		await close_menu()
		return
	await capture("resident_social_menu")
	await wait_to(minf(deadline - 0.5, seconds() + (0.3 if preview else 4.0)))
	var options: Array = life.get("_modal_opts")
	var choice: int = -1
	for index: int in range(mini(9, options.size())):
		if bool((options[index] as Dictionary).get("enabled", false)):
			choice = index
			break
	report["social_attempt"] = {"target": selected.get("id"), "menu_options": options.size(), "choice": choice, "tour_frame": frame_no, "result": "Actual LifeMode menu; core decides legality and response."}
	if choice >= 0:
		await key(KEY_1 + choice)
		await wait_walk(deadline)
	else:
		await close_menu()


func _ready() -> void:
	process_priority = 49
	var args: PackedStringArray = OS.get_cmdline_user_args()
	preview = args.has("--walkthrough-preview")
	output_dir = ProjectSettings.globalize_path("res://").path_join("../docs/town_walkthrough/preview" if preview else "../docs/town_walkthrough/final").simplify_path()
	for index: int in range(args.size() - 1):
		if args[index] == "--walkthrough-dir":
			output_dir = args[index + 1]
	if not output_dir.is_absolute_path():
		push_error("--walkthrough-dir must be absolute")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	total_frames = int(PREVIEW_STARTS[-1] * FPS) if preview else FULL_SECONDS * FPS
	main = MainScene.instantiate()
	add_child(main)
	await wait_frames(20)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 768))
	await wait_frames(6)
	view = main.get("_view")
	life = main.get("_life")
	probe = main.get("_probe")
	if view == null or life == null or probe == null or not view.has_method("get_bridge_info"):
		ck("actual_Main_LifeMode_town3d_loaded", false, "Use --town3d --backend logic --agents 12 --no-player (without --no-life or --life-as).")
		finish()
		return
	model = view.get("town_model_3d")
	var info: Dictionary = view.get_bridge_info()
	ck("actual_Main_verified_town_loaded", bool(info.get("model", {}).get("loaded", false)) and int(info.get("model", {}).get("building_count", 0)) == (view.get("projection_3d").get("building_spaces", {}) as Dictionary).size() and int(info.get("model", {}).get("building_count", 0)) >= 151, info)
	ck("real_framebuffer_driver", DisplayServer.get_name() != "headless", DisplayServer.get_name())
	if model == null or checks_failed > 0:
		finish()
		return
	# A real pre-roll wait establishes morning light without editing the clock or
	# an actor's address. Public possession keeps Aria idle in her original home.
	# All other residents, needs and transactions advance through the live core.
	var original_address: Dictionary = Sim.get_agent("aria").duplicate(true)
	life.start_life("aria")
	await wait_frames(3)
	await key(KEY_3)
	var pre_roll_frames: int = 0
	while Sim.tick_no < 90 and pre_roll_frames < 3600:
		await wait_frames(1)
		pre_roll_frames += 1
	await key(KEY_0)
	var morning_address: Dictionary = Sim.get_agent("aria")
	ck("morning_established_by_real_clock_wait_without_relocation", Sim.tick_no >= 90 and morning_address.get("pos") == original_address.get("pos") and morning_address.get("space") == original_address.get("space") and morning_address.get("floor") == original_address.get("floor"), {"tick": Sim.tick_no, "pre_roll_frames": pre_roll_frames})
	report["pre_roll_setup"] = {"public_calls": ["LifeMode.start_life(aria)", "speed key 3", "pause key 0", "LifeMode.begin_select()"], "actual_tick": Sim.tick_no, "real_clock_advanced": true, "actor_relocated": false, "purpose": "Morning light through actual waiting; boot frames are trimmed from the final movie."}
	life.begin_select()
	await wait_frames(3)
	# Hide only the initial selection panel during the architectural establishing shot.
	var selection: Control = life.get("_sel") as Control
	if selection != null:
		selection.hide()
	inspection(true)
	await key(KEY_0) # Existing Main/LifeMode clock command, never a Sim assignment.
	Sim.life_action_done.connect(_on_action)
	Sim.social_event.connect(_on_social)
	Sim.world_reset.connect(_on_reset)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	chapter_card = Label.new()
	chapter_card.position = Vector2(360, 44)
	chapter_card.size = Vector2(560, 26)
	chapter_card.add_theme_font_size_override("font_size", 14)
	chapter_card.add_theme_color_override("font_color", Color("f3deb0"))
	chapter_card.add_theme_color_override("font_shadow_color", Color.BLACK)
	chapter_card.add_theme_constant_override("shadow_offset_x", 1)
	chapter_card.add_theme_constant_override("shadow_offset_y", 1)
	chapter_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(chapter_card)
	report["preview"] = preview
	report["acceptance_scope"] = "PREVIEW_FRAMING_AND_COMPRESSED_CORE_ACTIONS_ONLY" if preview else "FULL_ROUTE_ACTUAL_ACTION_CHECKS_REQUIRED"
	if preview:
		report["preview_omissions"] = ["compact HUD expanded-panel input demonstration", "full cafe table meal", "core-to-expanded-town walk", "new venue use and upper-floor traversal", "reserve bathhouse walk and hygiene use", "detailed trailer entry and fixture use", "walked return from reserve to core"]
	report["fps"] = FPS
	report["expected_tour_frames"] = total_frames
	report["expected_tour_seconds"] = float(total_frames) / FPS
	report["movie_boot_frames_to_trim"] = Engine.get_frames_drawn()
	report["tour_start_engine_frame"] = Engine.get_process_frames()
	report["source_blend_sha256"] = info["model"].get("source_blend_sha256")
	report["source_glb_sha256"] = info["model"].get("source_glb_sha256")
	report["projection_sha256"] = FileAccess.get_sha256("res://data/town3d/projection.json")
	report["profile_sha256"] = FileAccess.get_sha256("res://data/town3d/profile.json")
	report["stage_manifest_sha256"] = FileAccess.get_sha256("res://assets/town3d/stage_manifest.json")
	report["characters_manifest_sha256"] = FileAccess.get_sha256("res://data/town3d/characters.json")
	report["harness_sha256"] = FileAccess.get_sha256("res://scripts/town_walkthrough.gd")
	report["route_plan_sha256"] = FileAccess.get_sha256(ProjectSettings.globalize_path("res://").path_join("../docs/town_walkthrough/route_plan.json").simplify_path())
	report["input_path"] = "Viewport mouse/key events -> existing Main/LifeMode -> authoritative Sim transactions; one public LifeMode.start_life selection. Camera inspection changes presentation only."
	tour_active = true
	await run_route()


func _entrance_for(space_id: String) -> String:
	for portal: Dictionary in Sim._portals:
		if str(portal.get("from", {}).get("space", "")) == "town" and str(portal.get("to", {}).get("space", "")) == space_id:
			return str(portal["id"])
	return ""


func _upgraded_venue(prefix: String, kinds: Array[String]) -> Dictionary:
	var projection: Dictionary = view.get("projection_3d")
	var spaces: Dictionary = projection.get("building_spaces", {})
	var bindings: Dictionary = projection.get("interaction_bindings", {})
	var choices: Array[Dictionary] = []
	var actor: Dictionary = Sim.get_agent("aria")
	var here: Vector3 = view.canonical_to_world(Vector2(actor["pos"]) * 48 + Vector2(24,24), str(actor.get("space", "town")), str(actor.get("floor", "outdoor")))
	for bid: String in spaces:
		if not bid.begins_with(prefix):
			continue
		var space_id: String = str(spaces[bid])
		for object_id: String in bindings:
			var binding: Dictionary = bindings[object_id]
			if str(binding.get("plane", "")) != space_id + "/1f" or str(binding.get("model_asset_kind", "")) not in kinds or not Sim.world.get("objects", {}).has(object_id):
				continue
			var world: Vector3 = view.canonical_to_world(Vector2(float(binding["cell"][0]), float(binding["cell"][1])) * 48 + Vector2(24,24), space_id, "1f")
			choices.append({"space": space_id, "building_id": bid, "object_id": object_id, "portal_id": _entrance_for(space_id), "distance": here.distance_to(world)})
	choices.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) < float(b["distance"]))
	return choices[0] if not choices.is_empty() else {}


func _travel_portal(ident: String, deadline: float) -> bool:
	# Pan to a distant legal destination, then issue the SAME screen click as a
	# player. LifeMode finds the route and moves the resident one real step at a
	# time. The director never writes an agent address or calls a teleport.
	var actor: Dictionary = Sim.get_agent("aria")
	var endpoint: Dictionary = {}
	for portal: Dictionary in Sim._portals:
		if str(portal.get("id", "")) != ident:
			continue
		for side: String in ["from", "to"]:
			var candidate: Dictionary = portal[side]
			if candidate.get("space") == actor.get("space") and candidate.get("floor") == actor.get("floor"):
				endpoint = candidate
	if endpoint.is_empty():
		return false
	var center: Vector2 = Vector2(float(endpoint["pos"][0]), float(endpoint["pos"][1])) * 48 + Vector2(24,24)
	set_camera(str(actor.get("space", "town")), str(actor.get("floor", "outdoor")), center, 28)
	await wait_frames(3)
	var previous: String = str(actor.get("space")) + "/" + str(actor.get("floor"))
	await click(view.canonical_to_screen(center))
	if bool(life.get("_modal_open")):
		var selected: Dictionary = life.get("_modal_entry")
		if str(selected.get("id", "")) == ident:
			await key(KEY_1)
		else:
			await close_menu()
	# Immediately return to the resident-follow camera, so the actual journey is
	# visible throughout rather than holding a distant destination shot.
	camera_override = false
	await wait_walk(deadline)
	await wait_frames(8)
	actor = Sim.get_agent("aria")
	if str(actor.get("space")) + "/" + str(actor.get("floor")) != previous:
		return true
	return await click_portal(ident, deadline)


func inspect_room_until(space_id: String, floor_id: String, from: Vector2, to: Vector2, size_from: float, size_to: float, end: float, tag: String) -> void:
	await close_menu()
	if Sim.running:
		await key(KEY_0)
	inspection(true)
	var before: Dictionary = snapshot(tag + "_inspection_before")
	await glide(space_id, floor_id, from, to, size_from, size_to, end)
	# Return to resident-follow while the camera cut still bears its inspection
	# label and the public clock remains paused; only then restore gameplay UI.
	camera_override = false
	life.set_process(true)
	await wait_frames(12)
	var after: Dictionary = snapshot(tag + "_inspection_after")
	var unchanged: bool = not Sim.running and not bool(before["world_running"])
	for field: String in ["tick", "day", "controlled_id", "resident_plane", "resident_position", "needs", "coin", "option"]:
		unchanged = unchanged and before[field] == after[field]
	ck(tag + "_labelled_inspection_preserves_paused_resident_and_clock", unchanged and chapter_card.text.begins_with("CAMERA INSPECTION"), {"before":before,"after":after,"label":chapter_card.text})
	inspection(false)
	await key(KEY_1)


func run_route() -> void:
	start_chapter(0, true)
	set_camera("town", "outdoor", town_point(-220, 70), 670)
	await glide("town", "outdoor", town_point(-220, 70), town_point(-65, 25), 670, 295, at(36))
	await capture("01_complete_town_and_woodland")
	var bridge: Dictionary = view.get_bridge_info()
	ck("complete_town_chunks_and_all_buildings_in_actual_Main", int(bridge.get("model", {}).get("building_count", 0)) >= 151 and bool(bridge.get("model", {}).get("chunked_whole_town", false)), bridge)
	ck("refined_mesh_residents_replace_pixel_billboards", int(bridge.get("mesh_actor_count", 0)) == int(bridge.get("actor_count", 0)) and int(bridge.get("mesh_actor_count", 0)) >= 12, bridge.get("character_visuals", []))
	await wait_to(chapter_time(1))
	start_chapter(1)
	inspection(false)
	var selection: Control = life.get("_sel") as Control
	if selection != null:
		selection.show()
	await wait_to(at(50))
	life.start_life("aria")
	await wait_frames(8)
	ck("existing_Aria_selected_at_real_upper_home", Sim.controlled_id == "aria" and Sim.get_agent("aria").get("space") == "cafe" and Sim.get_agent("aria").get("floor") == "2f")
	await key(KEY_0)
	var upper: Vector2 = room_center("cafe", "2f")
	# The measured 02b voice describes opening the panels at 81.25–85.96s.
	# Finish the camera study first so the real GUI clicks accompany those words.
	await glide("cafe", "2f", upper + Vector2(-24,12), upper + Vector2(24,-12), 14, 12, at(92) if preview else at(80.5))
	await capture("02_Aria_refined_character_upper_home")
	if not preview:
		await demonstrate_compact_hud(at(87.5))
	await wait_to(chapter_time(2))
	start_chapter(2)
	camera_override = false
	await key(KEY_1)
	var descended: bool = await click_portal("p_cafe_stairs", at(126) if not preview else at(151))
	ck("actual_input_stair_traversal", descended and Sim.get_agent("aria").get("floor") == "1f")
	await capture("03_actual_stair_arrival")
	if descended and not preview:
		var cafe_center: Vector2 = room_center("cafe", "1f")
		await inspect_room_until("cafe", "1f", cafe_center + Vector2(-72,0), cafe_center + Vector2(72,0), 18, 14, at(128), "03_cafe_ground_floor")
		await use_fixture("cafe1f_table", "吃饭", at(148), 4)
	await close_menu()
	await wait_to(chapter_time(3))
	start_chapter(3)
	# The measured preview also needs the walked approach before its 24-tick use.
	# Use the existing public 8x shortcut inside this compressed chapter.
	await key(KEY_4 if preview else KEY_1)
	if preview:
		ck("preview_public_eight_times_clock", Sim.running and is_equal_approx(Sim.speed, 8.0))
	if descended:
		await use_fixture("cafe1f_counter", "", at(189), 1.0 if preview else 2.0)
	await close_menu()
	if preview:
		await key(KEY_1)
	var exited: bool = await click_portal("p_cafe_door", at(211))
	ck("actual_input_exterior_door_traversal", exited and Sim.get_agent("aria").get("space") == "town")
	await capture("04_cafe_action_and_street_threshold")
	await wait_to(chapter_time(4))
	start_chapter(4)
	var venue: Dictionary = _upgraded_venue("Expansion_", ["cafe_table_set", "retail_counter", "dining_table"])
	ck("new_expansion_has_actual_reachable_activity_binding", not venue.is_empty(), venue)
	var visited: bool = false
	if exited and not venue.is_empty() and not preview:
		visited = await _travel_portal(str(venue["portal_id"]), at(279))
	if preview:
		skipped_preview_check("actual_screen_input_walks_from_core_to_new_expansion", "90-second preview omits the actual expanded-town journey; current resident remains at the core street.")
	else:
		ck("actual_screen_input_walks_from_core_to_new_expansion", (visited and str(Sim.get_agent("aria").get("space")) == str(venue.get("space", ""))), snapshot("expanded_venue_arrival"))
	await capture("05_preview_core_street_expansion_walk_skipped" if preview else "05_actual_expansion_venue_arrival")
	await wait_to(chapter_time(5))
	start_chapter(5)
	if visited and not preview:
		await use_fixture(str(venue["object_id"]), "", at(308), 3)
		var upstairs: String = ""
		for portal: Dictionary in Sim._portals:
			if portal["from"].get("space") == venue["space"] and portal["to"].get("space") == venue["space"] and portal["from"].get("floor") == "1f":
				upstairs = str(portal["id"])
				break
		if not upstairs.is_empty():
			var ascended: bool = await click_portal(upstairs, at(325))
			ck("actual_new_building_upper_floor_traversal", ascended, snapshot("new_venue_upper_floor"))
			await capture("06_actual_expansion_upper_interior")
			if ascended:
				var venue_floor: String = str(Sim.get_agent("aria").get("floor", "2f"))
				var venue_upper: Vector2 = room_center(str(venue["space"]), venue_floor)
				await inspect_room_until(str(venue["space"]), venue_floor, venue_upper + Vector2(0,-96), venue_upper + Vector2(0,96), 16, 13, at(342), "06_expansion_upper_floor")
			await click_portal(upstairs, at(351))
		await click_portal(str(venue["portal_id"]), at(354))
	await wait_to(chapter_time(6))
	start_chapter(6)
	var bath: Dictionary = _upgraded_venue("Reserve_Bathhouse", ["shower", "basin", "toilet"])
	var bathed: bool = false
	if not bath.is_empty() and not preview:
		var arrived: bool = await _travel_portal(str(bath["portal_id"]), at(415))
		ck("actual_reserve_path_and_bathhouse_entrance", arrived and str(Sim.get_agent("aria").get("space")) == str(bath["space"]), snapshot("reserve_bathhouse_arrival"))
		if arrived:
			var bath_center: Vector2 = room_center(str(bath["space"]), "1f")
			await inspect_room_until(str(bath["space"]), "1f", bath_center + Vector2(-96,0), bath_center + Vector2(96,0), 18, 14, at(405), "07_bathhouse_before_use")
			bathed = await use_fixture(str(bath["object_id"]), "", at(443), 1)
			await capture("07_actual_reserve_bathhouse_action")
			await inspect_room_until(str(bath["space"]), "1f", bath_center + Vector2(96,0), bath_center + Vector2(-96,0), 14, 18, at(443), "07_bathhouse_after_use")
			await click_portal(str(bath["portal_id"]), at(453))
	if preview:
		skipped_preview_check("reserve_hygiene_uses_existing_Sim_verbs", "90-second preview omits reserve travel and hygiene fixture use.")
	else:
		ck("reserve_hygiene_uses_existing_Sim_verbs", bathed)
	await wait_to(chapter_time(7))
	start_chapter(7)
	var trailer: Dictionary = _upgraded_venue("Reserve_Trailer_", ["basin", "toilet"])
	var trailer_visit: bool = false
	if not trailer.is_empty() and not preview:
		trailer_visit = await _travel_portal(str(trailer["portal_id"]), at(495))
		ck("actual_path_and_detailed_trailer_entry", trailer_visit, snapshot("trailer_arrival"))
		if trailer_visit:
			var trailer_center: Vector2 = room_center(str(trailer["space"]), "1f")
			await inspect_room_until(str(trailer["space"]), "1f", trailer_center + Vector2(0,-144), trailer_center + Vector2(0,144), 11.5, 9.5, at(506), "08_trailer_before_use")
			await use_fixture(str(trailer["object_id"]), "", at(540), 2)
			await capture("08_actual_trailer_interior_and_use")
			await inspect_room_until(str(trailer["space"]), "1f", trailer_center + Vector2(0,144), trailer_center + Vector2(0,-144), 9.5, 11.5, at(540), "08_trailer_after_use")
			await click_portal(str(trailer["portal_id"]), at(553))
	await wait_to(chapter_time(8))
	start_chapter(8)
	var returned: bool = false
	if trailer_visit and not preview:
		returned = await _travel_portal("p_cafe_door", at(640))
		ck("actual_walk_returns_from_reserve_across_expansion_to_core", returned and Sim.get_agent("aria").get("space") == "cafe", snapshot("core_return_arrival"))
		await capture("09_actual_return_from_reserve_to_core")
		if returned:
			await click_portal("p_cafe_door", at(660))
	if preview:
		skipped_preview_check("complete_outward_and_return_walk_is_actual_gameplay", "90-second preview omits the outward and return journeys; expanded_gameplay_scope remains false.")
	else:
		ck("complete_outward_and_return_walk_is_actual_gameplay", returned)
	await wait_to(chapter_time(9))
	start_chapter(9, true)
	await key(KEY_0)
	inspection(true)
	await glide("town", "outdoor", town_point(-245,45), town_point(-275,65), 78, 56, at(687))
	await capture("10_inspection_ravine_bridge_forest")
	await glide("town", "outdoor", town_point(-345,140), town_point(-380,150), 85, 65, at(709))
	await capture("11_inspection_stone_stair_topography")
	await glide("town", "outdoor", town_point(26,-42), town_point(15,-31), 24, 37, at(730))
	await capture("12_inspection_pond_horticulture")
	await wait_to(chapter_time(10))
	start_chapter(10)
	inspection(false)
	await close_menu()
	await key(KEY_0)
	var saved: Dictionary = snapshot("before_F5")
	await key(KEY_F5)
	var save_path: String = str(main.call("_quicksave_path"))
	ck("actual_Main_F5_writes_upgraded_profile_save", FileAccess.file_exists(save_path), {"file":save_path,"sha256":FileAccess.get_sha256(save_path)})
	await key(KEY_1)
	await wait_to(at(753))
	await key(KEY_0)
	var resets: int = reset_events.size()
	await key(KEY_F8)
	await wait_frames(8)
	var restored: Dictionary = reset_events[-1] if reset_events.size() > resets else {}
	ck("actual_Main_F8_restores_complete_town_and_resident", not restored.is_empty() and restored.get("tick") == saved["tick"] and str(restored.get("pos")) == saved["resident_position"], {"saved":saved,"restored":restored})
	await key(KEY_1)
	if not bool(life.get("free_will")):
		await key(KEY_F)
	var before: Dictionary = snapshot("autonomy_start")
	await wait_to(at(800))
	var after: Dictionary = snapshot("autonomy_end")
	ck("existing_free_will_advances_live_core", bool(life.get("free_will")) and int(after["tick"]) > int(before["tick"]), {"before":before,"after":after})
	await capture("13_restored_actual_resident_life")
	await wait_to(chapter_time(11))
	start_chapter(11, true)
	if bool(life.get("free_will")):
		await key(KEY_F)
	await key(KEY_0)
	inspection(true)
	await glide("town", "outdoor", town_point(-100,-65), town_point(-220,70), 120, 670, at(835))
	await capture("14_complete_upgraded_playable_town")
	report["expanded_gameplay_scope"] = {"core_stairs":descended,"core_to_expansion_walk":visited,"reserve_bath_action":bathed,"detailed_trailer_visit":trailer_visit,"walked_return_to_core":returned,"inspection_does_not_relocate_actors":true}
	report["director_mutation_policy"] = {"agent_nav_room_and_Sim_assignments":false,"input_commands":report["input_events"].size(),"fixture_completions_observed":action_events.size(),"inspection_changes_actor_address":false}
	report["route_complete"] = true
	await wait_to(float(total_frames)/FPS)
	finish()


func finish() -> void:
	if finishing:
		return
	finishing = true
	tour_active = false
	report["status"] = "PASS" if checks_failed == 0 and bool(report.get("route_complete", false)) else "FAIL"
	report["failure_count"] = checks_failed
	report["tour_frames_elapsed"] = frame_no
	report["tour_seconds_elapsed"] = seconds()
	report["movie_end_frames_drawn"] = Engine.get_frames_drawn()
	report["engine_version"] = Engine.get_version_info()
	report["display_server"] = DisplayServer.get_name()
	report["social_events"] = social_events
	report["completed_actions"] = action_events
	report["world_reset_events"] = reset_events
	report["limits"] = ["Architectural inspection uses camera/cover state only; it is not resident traversal.", "The route demonstrates selected rooms and paths, not every modeled room or all simulation outcomes.", "Social responses and autonomous decisions are actual core outcomes; the director does not force them.", "No FPS/VRAM/collision certification is implied by MovieWriter output."]
	var path: String = output_dir.path_join("walkthrough_report.json")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	var cues: FileAccess = FileAccess.open(output_dir.path_join("walkthrough_cues.json"), FileAccess.WRITE)
	if cues != null:
		cues.store_string(JSON.stringify({"schema": "living_town.walkthrough.cues.v1", "fps": FPS, "movie_boot_frames_to_trim": report.get("movie_boot_frames_to_trim", 0), "chapters": report["chapters"], "captures": report["captures"]}, "\t") + "\n")
		cues.close()
	print("WALKTHROUGH ", report["status"], " frames=", frame_no, " checks=", report["checks"].size(), " failed=", checks_failed, " report=", path)
	call_deferred("quit_after_route_unwinds", 0 if report["status"] == "PASS" else 1)


func quit_after_route_unwinds(exit_code: int) -> void:
	# A scheduled frame-limit finish can run before run_route's final await wakes.
	# Let that coroutine and _ready return before the tree releases their scripts.
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(exit_code)
