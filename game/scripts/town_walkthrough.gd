extends Node
## A recording director around the actual Main, never a substitute simulation.
## Use a real renderer with --fixed-fps 24 --write-movie <capture.ogv>.
## User args: --town3d --backend logic --agents 12 --no-player --seed 7
##            --walkthrough-dir <absolute> [--walkthrough-preview]
## Architectural inspection changes only Probe/visibility/UI presentation.
const MainScene = preload("res://scenes/Main.tscn")
const FPS: int = 24
const FULL_SECONDS: int = 600
const FULL_STARTS: Array[float] = [0, 45, 100, 155, 215, 270, 330, 390, 450, 505, 560, 600]
const PREVIEW_STARTS: Array[float] = [0, 6, 13, 26, 43, 58, 66, 73, 80, 84, 88, 90]
const CHAPTERS: Array[String] = ["Town and coast", "Choose an existing resident", "Stairs, walking and needs", "The actual cafe counter", "Street, thresholds and visibility", "Architectural inspection: rooms", "Architectural inspection: streets", "Architectural inspection: pond", "Resident agency and autonomous life", "Save, resume and restore", "Town, scope and next steps"]

var main: Node
var view: Node
var life: Node
var model: Node
var probe: Node
var preview: bool = false
var output_dir: String = ""
var frame_no: int = 0
var total_frames: int = 14400
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
	var record: Dictionary = {"index": index + 1, "title": CHAPTERS[index], "planned_start_seconds": chapter_time(index), "actual_start_seconds": seconds(), "tour_frame": frame_no, "architectural_inspection": architectural}
	report["chapters"].append(record)
	chapter_card.text = ("CAMERA INSPECTION  |  " if architectural else "ACTUAL GAMEPLAY  |  ") + CHAPTERS[index]
	snapshot(CHAPTERS[index])
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
	ck("actual_Main_verified_town_loaded", bool(info.get("model", {}).get("loaded", false)) and int(info.get("model", {}).get("building_count", 0)) == 49, info)
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
	report["fps"] = FPS
	report["expected_tour_frames"] = total_frames
	report["expected_tour_seconds"] = float(total_frames) / FPS
	report["movie_boot_frames_to_trim"] = Engine.get_frames_drawn()
	report["tour_start_engine_frame"] = Engine.get_process_frames()
	report["source_blend_sha256"] = info["model"].get("source_blend_sha256")
	report["source_glb_sha256"] = info["model"].get("source_glb_sha256")
	report["projection_sha256"] = FileAccess.get_sha256("res://data/town3d/projection.json")
	report["harness_sha256"] = FileAccess.get_sha256("res://scripts/town_walkthrough.gd")
	report["route_plan_sha256"] = FileAccess.get_sha256(ProjectSettings.globalize_path("res://").path_join("../docs/town_walkthrough/route_plan.json").simplify_path())
	report["input_path"] = "Viewport mouse/key events -> existing Main/LifeMode -> authoritative Sim transactions; one public LifeMode.start_life selection. Camera inspection changes presentation only."
	tour_active = true
	await run_route()


func run_route() -> void:
	start_chapter(0, true)
	set_camera("town", "outdoor", town_point(1, 2), 148)
	await glide("town", "outdoor", town_point(1, 2), town_point(1, 10), 148, 136, at(36))
	await capture("01_town_overview")
	await wait_to(chapter_time(1))
	start_chapter(1)
	inspection(false)
	camera_override = false
	var selection: Control = life.get("_sel") as Control
	if selection != null:
		selection.show()
	await wait_to(at(50))
	life.start_life("aria") # Same public entry invoked by the resident selection button.
	await wait_frames(8)
	ck("existing_Aria_selected_at_real_upper_home", Sim.controlled_id == "aria" and Sim.get_agent("aria").get("space") == "cafe" and Sim.get_agent("aria").get("floor") == "2f")
	await key(KEY_0)
	var upper: Vector2 = room_center("cafe", "2f")
	await glide("cafe", "2f", upper + Vector2(-24, 12), upper + Vector2(24, -12), 14, 12, at(92))
	await capture("02_owner_upper_home")
	await wait_to(chapter_time(2))
	start_chapter(2)
	camera_override = false
	await key(KEY_1)
	await wait_frames(8)
	var descended: bool = await click_portal("p_cafe_stairs", at(126) if not preview else at(151))
	ck("actual_input_stair_traversal", descended and Sim.get_agent("aria").get("floor") == "1f")
	await capture("03_actual_stair_arrival")
	if descended and not preview:
		await use_fixture("cafe1f_table", "吃饭", at(151), 4)
		await key(KEY_0)
	await close_menu()
	await wait_to(chapter_time(3))
	start_chapter(3)
	await key(KEY_1)
	if descended:
		await use_fixture("cafe1f_counter", "", at(210), 0.5 if preview else 8.0)
	await close_menu()
	await key(KEY_0)
	await capture("04_counter_action_complete")
	await wait_to(chapter_time(4))
	start_chapter(4)
	await key(KEY_1)
	var exited: bool = await click_portal("p_cafe_door", at(247))
	ck("actual_input_exterior_door_traversal", exited and Sim.get_agent("aria").get("space") == "town")
	await wait_frames(8)
	await capture("05_exterior_threshold_visibility")
	report["exterior_controlled_occlusion"] = view.get_bridge_info().get("controlled_occlusion", {})
	if exited and not preview:
		# Pick a real reachable dry street cell through the same input path.
		var resident: Dictionary = Sim.get_agent("aria")
		var origin: Vector2i = resident["pos"]
		var chosen: Vector2i = origin
		for offset: Vector2i in [Vector2i(-6, 0), Vector2i(-4, 2), Vector2i(0, 5)]:
			var candidate: Vector2i = origin + offset
			if not Sim._astar_path(Sim._grid_for("town", "outdoor"), origin, candidate).is_empty():
				chosen = candidate
				break
		await click(view.canonical_to_screen(Vector2(chosen) * 48 + Vector2(24, 24)))
		await close_menu()
		await wait_walk(at(267))
		ck("actual_screen_input_street_walk", chosen != origin and Sim.get_agent("aria")["pos"] == chosen, {"start": str(origin), "requested": str(chosen), "end": str(Sim.get_agent("aria")["pos"])})
	await close_menu()
	await key(KEY_0)
	await wait_to(chapter_time(5))
	start_chapter(5, true)
	inspection(true)
	var library: Vector2 = room_center("library", "1f")
	await glide("library", "1f", library + Vector2(-20, 0), library + Vector2(20, 0), 17, 15, at(286))
	await capture("06_inspection_library")
	var home: Vector2 = room_center("home", "1f")
	await glide("home", "1f", home + Vector2(-16, 0), home + Vector2(16, 0), 13, 11, at(307))
	await capture("07_inspection_home")
	var hotel: Vector2 = room_center("hotel", "2f")
	await glide("hotel", "2f", hotel + Vector2(-18, 0), hotel + Vector2(18, 0), 18, 16, at(327))
	await capture("08_inspection_hotel")
	await wait_to(chapter_time(6))
	start_chapter(6, true)
	await glide("town", "outdoor", town_point(-44, 18), town_point(-22, 18), 42, 36, at(350))
	await capture("09_irregular_inland_streets")
	await glide("town", "outdoor", town_point(-22, 18), town_point(8, 15), 36, 38, at(366))
	await glide("town", "outdoor", town_point(8, 15), town_point(41, 43), 38, 35, at(386))
	await capture("10_working_harbor")
	await wait_to(chapter_time(7))
	start_chapter(7, true)
	await glide("town", "outdoor", town_point(30, -34), town_point(26, -42), 32, 23, at(419))
	await capture("11_pond_and_planting")
	await glide("town", "outdoor", town_point(26, -42), town_point(15, -31), 23, 35, at(446))
	await wait_to(chapter_time(8))
	start_chapter(8)
	inspection(false)
	await wait_frames(8)
	await key(KEY_1)
	if not preview:
		await social_attempt(at(473))
	await close_menu()
	if not bool(life.get("free_will")):
		await key(KEY_F)
	var autonomy_start: Dictionary = snapshot("autonomy_start")
	await wait_to(at(500))
	var autonomy_end: Dictionary = snapshot("autonomy_end")
	ck("existing_free_will_runs_live_core_clock", bool(life.get("free_will")) and int(autonomy_end["tick"]) > int(autonomy_start["tick"]), {"before": autonomy_start, "after": autonomy_end})
	await capture("12_autonomous_resident")
	await wait_to(chapter_time(9))
	start_chapter(9)
	if bool(life.get("free_will")):
		await key(KEY_F)
	await close_menu()
	await key(KEY_0)
	var saved: Dictionary = snapshot("before_F5")
	await key(KEY_F5)
	var save_path: String = str(main.call("_quicksave_path"))
	ck("actual_Main_F5_writes_profile_save", FileAccess.file_exists(save_path), {"file": save_path, "sha256": FileAccess.get_sha256(save_path)})
	await wait_to(at(520))
	await key(KEY_1)
	await wait_to(at(532))
	await key(KEY_0)
	var reset_start: int = reset_events.size()
	await key(KEY_F8)
	await wait_frames(8)
	var restored: Dictionary = reset_events[-1] if reset_events.size() > reset_start else {}
	ck("actual_Main_F8_restores_saved_profile_and_resident", not restored.is_empty() and restored.get("tick") == saved["tick"] and str(restored.get("pos")) == saved["resident_position"] and (restored.get("profile", {}) as Dictionary).get("id") == "town3d", {"saved": saved, "world_reset": restored})
	await key(KEY_1)
	await capture("13_save_restored_gameplay")
	await wait_to(at(557))
	await key(KEY_0)
	await wait_to(chapter_time(10))
	start_chapter(10, true)
	inspection(true)
	set_camera("town", "outdoor", town_point(7, -2), 45)
	if not preview:
		# Show the real following morning after the social/save chapter, using
		# normal speed controls. The camera never changes canonical actor state.
		var morning_tick: int = int(Sim.tick_no / Sim.TICKS_PER_DAY) * Sim.TICKS_PER_DAY + 90
		if morning_tick <= Sim.tick_no:
			morning_tick += Sim.TICKS_PER_DAY
		await key(KEY_4)
		while Sim.tick_no < morning_tick and seconds() < at(578):
			await wait_frames(1)
		await key(KEY_0)
		report["closing_real_clock_wait"] = {"target_tick": morning_tick, "actual_tick": Sim.tick_no, "public_speed_keys": [4, 0]}
		ck("closing_morning_reached_through_actual_clock_wait", Sim.tick_no >= morning_tick, report["closing_real_clock_wait"])
	await glide("town", "outdoor", town_point(7, -2), town_point(1, 4), 45, 148, at(590))
	await capture("14_final_whole_town")
	report["director_mutation_policy"] = {"agent_nav_room_and_Sim_assignments": false, "input_commands": report["input_events"].size(), "social_events_observed": social_events.size(), "fixture_completions_observed": action_events.size(), "inspection_changes_actor_address": false}
	report["route_complete"] = true
	await wait_to(float(total_frames) / FPS)
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
