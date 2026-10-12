extends Node
## Runs the actual Main/LifeMode, using mouse/key events for travel and use.
## Invoke this scene with -- --town3d --backend logic --life-as aria.
## This GPU arm must have a real framebuffer; it never treats headless as visual PASS.
const MainScene = preload("res://scenes/Main.tscn")
const MAX_WAIT_FRAMES: int = 900

var main: Node
var view: Node
var life: Node
var model: Node
var report: Dictionary = {"schema": "living_town.bridge.visual.v1", "checks": [], "screenshots": [], "input_events": []}
var failures: int = 0
var output_dir: String = ""


func ck(label: String, passed: bool, detail: Variant = null) -> void:
	report["checks"].append({"name": label, "passed": passed, "detail": detail})
	print(("PASS " if passed else "FAIL ") + label)
	if not passed:
		failures += 1


func frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame


func click(point: Vector2) -> void:
	report["input_events"].append({"kind": "mouse_click", "screen": [point.x, point.y], "tick": Sim.tick_no})
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = point
	event.global_position = point
	event.pressed = true
	get_viewport().push_input(event, true)
	await frames(1)
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = point
	release.global_position = point
	release.pressed = false
	get_viewport().push_input(release, true)
	await frames(2)


func key(code: Key) -> void:
	report["input_events"].append({"kind": "key", "keycode": int(code), "tick": Sim.tick_no})
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	get_viewport().push_input(event, true)
	await frames(1)
	var release: InputEventKey = InputEventKey.new()
	release.keycode = code
	release.physical_keycode = code
	release.pressed = false
	get_viewport().push_input(release, true)
	await frames(2)


func cell_center(point: Vector2i) -> Vector2:
	return Vector2(point) * 48.0 + Vector2(24, 24)


func wait_walk() -> bool:
	for frame: int in range(MAX_WAIT_FRAMES):
		if not bool(life.get("_walk_on")):
			return true
		await frames(1)
	return false


func portal_by_id(ident: String) -> Dictionary:
	for portal: Dictionary in Sim._portals:
		if portal["id"] == ident:
			return portal
	return {}


func click_portal(ident: String) -> bool:
	var portal: Dictionary = portal_by_id(ident)
	var me: Dictionary = Sim.controlled()
	var endpoint: Dictionary = {}
	for side: String in ["from", "to"]:
		if portal[side]["space"] == me.get("space") and portal[side]["floor"] == me.get("floor"):
			endpoint = portal[side]
	if endpoint.is_empty():
		return false
	var point: Vector2i = Vector2i(int(endpoint["pos"][0]), int(endpoint["pos"][1]))
	var previous_plane: String = str(me["space"]) + "/" + str(me["floor"])
	await click(view.canonical_to_screen(cell_center(point)))
	if bool(life.get("_modal_open")):
		if str((life.get("_modal_entry") as Dictionary).get("id", "")) != ident:
			await key(KEY_ESCAPE)
		else:
			await key(KEY_1)
	if not await wait_walk():
		return false
	await frames(6)
	me = Sim.controlled()
	if str(me["space"]) + "/" + str(me["floor"]) != previous_plane:
		return true
	# A distant doorway first receives a walk intent; click again at arrival.
	await click(view.canonical_to_screen(cell_center(point)))
	var selected: Dictionary = life.get("_modal_entry")
	if not bool(life.get("_modal_open")) or selected.get("id") != ident:
		return false
	await key(KEY_1)
	await wait_walk()
	await frames(8)
	me = Sim.controlled()
	return str(me["space"]) + "/" + str(me["floor"]) != previous_plane


func capture(label: String) -> bool:
	await frames(4)
	await RenderingServer.frame_post_draw
	var texture: ViewportTexture = get_viewport().get_texture()
	var image: Image = texture.get_image() if texture != null else null
	if image == null or image.is_empty():
		ck("framebuffer_" + label, false, DisplayServer.get_name())
		return false
	var mean: float = 0
	var square: float = 0
	var count: int = 0
	for y: int in range(0, image.get_height(), 16):
		for x: int in range(0, image.get_width(), 16):
			var color: Color = image.get_pixel(x, y)
			var luminance: float = color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			mean += luminance
			square += luminance * luminance
			count += 1
	mean /= maxf(1, count)
	var deviation: float = sqrt(maxf(0, square / maxf(1, count) - mean * mean))
	var path: String = output_dir.path_join(label + ".png")
	var error: Error = image.save_png(path)
	ck("actual_main_framebuffer_" + label, error == OK and mean > 0.025 and mean < 0.95 and deviation > 0.035, {"mean_luminance": mean, "luminance_stddev": deviation})
	if error == OK:
		report["screenshots"].append({"file": path, "sha256": FileAccess.get_sha256(path), "tick": Sim.tick_no,
			"controlled": life.get("pid"), "space": Sim.controlled().get("space"), "floor": Sim.controlled().get("floor"),
			"model_source_blend_sha256": report.get("source_blend_sha256"), "size": [image.get_width(), image.get_height()]})
	return error == OK


func actual_body_los(sprite: Sprite3D) -> Dictionary:
	var camera: Camera3D = view.get("camera_3d") as Camera3D
	var body: Vector3 = sprite.global_position + Vector3.UP * 0.95
	var screen: Vector2 = camera.unproject_position(body)
	var origin: Vector3 = camera.project_ray_origin(screen)
	var direction: Vector3 = (body - origin).normalized()
	var distance: float = origin.distance_to(body)
	var hit: Dictionary = model.raycast_geometry(origin, direction, maxf(0, distance - 0.12), "all")
	var blocked: bool = not hit.is_empty() and Vector3(hit.get("position", Vector3.ZERO)).y > sprite.global_position.y + 0.10
	return {"blocked": blocked, "occluder": str(hit["node"].name) if blocked else "", "distance": hit.get("distance", 0)}


func _ready() -> void:
	output_dir = ProjectSettings.globalize_path("res://").path_join("../docs/town_bridge/captures").simplify_path()
	DirAccess.make_dir_recursive_absolute(output_dir)
	if not OS.get_cmdline_user_args().has("--town3d"):
		ck("explicit_actual_main_town3d_mode", false, "Pass -- --town3d --backend logic --life-as aria")
		finish()
		return
	main = MainScene.instantiate()
	add_child(main)
	await frames(20)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 768))
	await frames(6)
	view = main.get("_view")
	life = main.get("_life")
	ck("actual_main_uses_existing_life_mode_and_3d_view", view != null and life != null and view.has_method("get_bridge_info") and bool(main.get("_town3d")))
	if view == null or life == null or not view.has_method("get_bridge_info"):
		finish()
		return
	model = view.get("town_model_3d")
	var info: Dictionary = view.get_bridge_info()
	ck("actual_game_loads_verified_49_building_model", model != null and bool(info.get("model", {}).get("loaded", false)) and int(info.get("model", {}).get("building_count", 0)) == 49, info)
	if model == null or not bool(info.get("model", {}).get("loaded", false)):
		finish()
		return
	report["source_blend_sha256"] = info["model"]["source_blend_sha256"]
	report["source_glb_sha256"] = info["model"]["source_glb_sha256"]
	report["projection_sha256"] = FileAccess.get_sha256("res://data/town3d/projection.json")
	if not bool(life.get("active")) or str(life.get("pid")) != "aria":
		# Same public UI entry used by the resident selection button, no placement.
		life.start_life("aria")
	await frames(12)
	ck("existing_resident_possessed_without_new_actor", Sim.controlled_id == "aria" and Sim.get_agent("player").is_empty())
	ck("owner_starts_in_real_upper_home", Sim.controlled().get("space") == "cafe" and Sim.controlled().get("floor") == "2f")
	var upper: Node3D = model.get("floor_nodes").get("Main_cafe", {}).get(1) as Node3D
	var neighbor: Node3D = model.get("nodes_by_name").get("Main_shop__Roof") as Node3D
	var roof: Node3D = model.get("nodes_by_name").get("Main_cafe__Roof") as Node3D
	ck("upper_floor_reveal_preserves_active_rooms_and_neighbor", upper != null and upper.is_visible_in_tree() and roof != null and not roof.is_visible_in_tree() and neighbor != null and neighbor.is_visible_in_tree())
	await capture("01_owner_upper")

	var me: Dictionary = Sim.controlled()
	var px: Vector2 = cell_center(me["pos"])
	var world: Vector3 = view.canonical_to_world(px)
	var screen: Vector2 = view.canonical_to_screen(px)
	var recovered: Vector2 = view.screen_to_canonical(screen)
	ck("actual_camera_floor_ray_roundtrip_under_0_02_cell", recovered.distance_to(px) / 48.0 < 0.02, {"cell_error": recovered.distance_to(px) / 48.0})
	var actor: Dictionary = view.get("_actors_3d").get("aria", {})
	var sprite: Sprite3D = actor.get("node") as Sprite3D
	ck("retained_character_sheet_has_metric_3d_body", sprite != null and sprite.texture != null and sprite.hframes == 7 and sprite.vframes == 8 and sprite.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y, {"texture": sprite.texture.resource_path if sprite != null and sprite.texture != null else "", "pixel_size": sprite.pixel_size if sprite != null else 0})
	ck("actor_feet_follow_projected_metric_floor", sprite != null and sprite.position.distance_to(world + Vector3.UP * 0.025) < 0.08, {"expected": str(world), "actual": str(sprite.position) if sprite != null else "missing"})
	var descended: bool = await click_portal("p_cafe_stairs")
	ck("screen_input_owner_uses_actual_stair_portal", descended and Sim.controlled().get("space") == "cafe" and Sim.controlled().get("floor") == "1f")
	if not descended:
		finish()
		return
	var ground: Node3D = model.get("floor_nodes").get("Main_cafe", {}).get(0) as Node3D
	ck("ground_floor_reveal_hides_upper_floor_only_locally", ground != null and ground.is_visible_in_tree() and not upper.is_visible_in_tree() and neighbor.is_visible_in_tree())
	me = Sim.controlled()
	world = view.canonical_to_world(cell_center(me["pos"]))
	var hit: Dictionary = model.raycast_geometry(world + Vector3.UP * 0.12, Vector3.DOWN, 0.30, "all", "Main_cafe")
	ck("selected_floor_height_meets_real_imported_floor", not hit.is_empty() and absf(float(hit.get("position", Vector3.ZERO).y) - world.y) < 0.08, {"projected_y": world.y, "hit_y": hit.get("position", Vector3.ZERO).y})

	var counter_id: String = "cafe1f_counter"
	var before_position: Vector2i = me["pos"]
	var before_sprite: Vector3 = sprite.position
	await click(view.object_screen_position(counter_id))
	var selected: Dictionary = life.get("_modal_entry")
	var selected_id: String = str(selected.get("id", ""))
	var bindings: Dictionary = view.get("projection_3d").get("interaction_bindings", {})
	var requested_binding: Dictionary = bindings.get(counter_id, {})
	var selected_binding: Dictionary = bindings.get(selected_id, {})
	var same_fixture: bool = not str(requested_binding.get("model_asset_id", "")).is_empty() and selected_binding.get("model_asset_id") == requested_binding.get("model_asset_id") and selected_binding.get("plane") == requested_binding.get("plane")
	var fixture_proof: Dictionary = {"requested_id": counter_id, "selected_id": selected_id, "requested_binding": requested_binding, "selected_binding": selected_binding, "same_imported_mesh_and_plane": same_fixture}
	ck("actual_fixture_mesh_click_opens_existing_action_menu", bool(life.get("_modal_open")) and selected.get("kind") == "object" and same_fixture, fixture_proof)
	report["selected_fixture_mesh_proof"] = fixture_proof
	var menu_actions: Array = selected.get("actions", [])
	if not same_fixture or menu_actions.is_empty():
		finish()
		return
	var advertised: Dictionary = menu_actions[0]
	var selected_action: String = str(advertised.get("action", ""))
	var advertised_need: String = str(advertised.get("need", ""))
	await capture("02_fixture_menu")
	var needs_before: Dictionary = Sim.controlled()["needs"].duplicate(true)
	var coin_before: int = Sim._coin_of("aria")
	var completions: Array[Dictionary] = []
	var done_callback: Callable = func(action: String, target: String, paid: int) -> void:
		if target == selected_id and action == selected_action:
			completions.append({"action": action, "target": target, "wage": paid, "tick": Sim.tick_no})
	Sim.life_action_done.connect(done_callback)
	await key(KEY_1)
	var moved: bool = false
	var animated: bool = false
	var saw_use: bool = false
	var issued: bool = false
	var captured_motion: bool = false
	var previous_need: float = float(needs_before.get(advertised_need, 0))
	var largest_use_need_step: float = 0.0
	for frame: int in range(MAX_WAIT_FRAMES):
		await frames(1)
		me = Sim.controlled()
		var option: Dictionary = me.get("option") if me.get("option") is Dictionary else {}
		moved = moved or (me["pos"] != before_position and sprite.position.distance_to(before_sprite) > 0.05)
		animated = animated or (sprite.frame % sprite.hframes != 0)
		var matching_intent: bool = option.get("target") == selected_id and option.get("action") == selected_action
		issued = issued or matching_intent
		var using_fixture: bool = matching_intent and option.get("phase") == "use"
		saw_use = saw_use or using_fixture
		var current_need: float = float(me["needs"].get(advertised_need, 0))
		if using_fixture or not completions.is_empty():
			largest_use_need_step = maxf(largest_use_need_step, current_need - previous_need)
		previous_need = current_need
		if moved and animated and not captured_motion:
			await capture("03_character_walking")
			captured_motion = true
		if not completions.is_empty() and option.is_empty() and not bool(life.get("_walk_on")):
			break
	Sim.life_action_done.disconnect(done_callback)
	ck("mouse_menu_keyboard_action_moves_retained_sprite_over_frames", moved and animated and issued, {"moved": moved, "sheet_walk_frames": animated, "core_object_intent": issued, "selected_target": selected_id, "selected_action": selected_action})
	var gain: float = float(Sim.controlled()["needs"].get(advertised_need, 0)) - float(needs_before.get(advertised_need, 0))
	var wage: int = Sim._coin_of("aria") - coin_before
	ck("existing_fixture_action_executes_with_measurable_effect", saw_use and not completions.is_empty() and (gain > 0.1 or largest_use_need_step > 0.1 or wage > 0), {"advertised_action": advertised, "need": advertised_need, "need_change": gain, "largest_observed_use_need_step": largest_use_need_step, "coin_change": wage, "use_phase_observed": saw_use, "completion_events": completions})
	# Settled standing pose lets the bounded 5Hz LOS sampler catch up naturally.
	await frames(8)
	var clear_los: Dictionary = actual_body_los(sprite)
	var clear_info: Dictionary = view.get_bridge_info().get("controlled_occlusion", {})
	var ghost: Sprite3D = view.get("_occlusion_ghost_3d") as Sprite3D
	ck("unblocked_controlled_resident_hides_occlusion_ghost", not bool(clear_los["blocked"]) and not bool(clear_info.get("blocked", true)) and ghost != null and not ghost.visible and not sprite.no_depth_test, {"actual_geometry_ray": clear_los, "view_state": clear_info})
	await capture("04_fixture_use_complete")

	var exited: bool = await click_portal("p_cafe_door")
	ck("screen_input_returns_resident_to_real_town", exited and Sim.controlled().get("space") == "town")
	await frames(12)
	await frames(8) # More than one 5Hz query interval at the capped 30fps renderer.
	ck("exterior_restore_reveals_cafe_and_neighbor_roofs", roof.is_visible_in_tree() and upper.is_visible_in_tree() and neighbor.is_visible_in_tree())
	var blocked_los: Dictionary = actual_body_los(sprite)
	var blocked_info: Dictionary = view.get_bridge_info().get("controlled_occlusion", {})
	ghost = view.get("_occlusion_ghost_3d") as Sprite3D
	ck("roof_occluded_controlled_resident_has_actual_los_and_visible_ghost", bool(blocked_los["blocked"]) and bool(blocked_info.get("blocked", false)) and blocked_info.get("actor_id") == "aria" and int(blocked_info.get("ray_count", 0)) > 0 and ghost != null and ghost.is_visible_in_tree(), {"actual_geometry_ray": blocked_los, "view_state": blocked_info})
	ck("only_matching_silhouette_bypasses_depth_with_primary_preserved", ghost != null and ghost.no_depth_test and not sprite.no_depth_test and bool(blocked_info.get("normal_depth_preserved", false)) and int(blocked_info.get("max_query_hz", 0)) == 5 and ghost.frame_coords == sprite.frame_coords and is_equal_approx(ghost.pixel_size, sprite.pixel_size) and ghost.global_position.distance_to(sprite.global_position) < 0.01, {"normal_primary_depth": not sprite.no_depth_test, "silhouette_frame_matches": ghost != null and ghost.frame_coords == sprite.frame_coords})
	me = Sim.controlled()
	px = cell_center(me["pos"])
	world = view.canonical_to_world(px)
	screen = view.canonical_to_screen(px)
	recovered = view.screen_to_canonical(screen)
	ck("actual_terrain_camera_ray_roundtrip_under_0_03_cell", recovered.distance_to(px) / 48.0 < 0.03, {"cell_error": recovered.distance_to(px) / 48.0, "terrain_y": world.y})
	ck("outdoor_actor_grounded_on_terrain_profile", absf(sprite.position.y - world.y - 0.025) < 0.08)
	await capture("05_town_exterior")
	var hashes: Dictionary = {}
	for shot: Dictionary in report["screenshots"]:
		hashes[shot["sha256"]] = true
	ck("five_distinct_actual_game_frames_captured", report["screenshots"].size() == 5 and hashes.size() == 5)
	report["direct_agent_writes"] = false
	report["input_path"] = "Viewport mouse/key events -> existing LifeMode -> Sim life_* and portal transactions"
	finish()


func finish() -> void:
	Sim.auto_run = false
	Sim.running = false
	report["status"] = "PASS" if failures == 0 else "FAIL"
	report["failure_count"] = failures
	report["engine_version"] = Engine.get_version_info()
	report["display_server"] = DisplayServer.get_name()
	var path: String = ProjectSettings.globalize_path("res://").path_join("../docs/town_bridge/visual_test_report.json").simplify_path()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	print("TOWN_BRIDGE_VISUAL ", report["status"], " checks=", report["checks"].size(), " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
