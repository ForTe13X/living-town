extends SceneTree
## Reusable presentation calibration. Never gameplay evidence.
## One actual Main; public LifeMode selection + key pause, then cameras/lights only.
const Inv = preload("res://bench/Invariants.gd")

class CameraKeeper extends Node:
	var main: Node
	var view: Node
	var probe: Node
	var shot: Dictionary = {}
	func _process(_delta: float) -> void:
		if shot.is_empty(): return
		probe.set("mode", 0)
		probe.set("follow_id", "")
		probe.set("demo_cam", false)
		var space: String = shot["space"]
		var floor_id: String = shot["floor"]
		if str(probe.get("active_space")) != space or str(probe.get("active_floor")) != floor_id:
			probe.call("set_space", space, floor_id, main.get("_sg").bounds_px(space))
		var cam: Camera2D = probe.get("cam") as Camera2D
		cam.position = shot["center"]
		var viewport: SubViewport = view.get("viewport_3d") as SubViewport
		cam.zoom = Vector2.ONE * maxf(0.025, float(viewport.size.y) * (1.7 / 48.0) / float(shot["size_m"]))
		view.call("sync_camera")

class LateLightOverride extends Node:
	var sun: DirectionalLight3D
	var environment: Environment
	var values: Dictionary = {}
	func _process(_delta: float) -> void:
		if values.is_empty(): return
		# Actual WorldView priority50 retains actor updates, visibility, prompt
		# placement and overlay redraw. Only these light parameters apply later.
		sun.light_energy = float(values["sun"])
		environment.ambient_light_energy = float(values["ambient"])
		environment.tonemap_exposure = float(values["exposure"])

var sim: Node
var main: Node
var view: Node
var life: Node
var keeper: CameraKeeper
var late_lights: LateLightOverride
var output: String = ""
var report: Dictionary = {"schema":"living_town.runtime_presentation_calibration.v1", "status":"DIAGNOSTIC", "gameplay_evidence":false, "captures":[], "checks":[], "hud_input_events":[], "hud_captures":[], "hud_safe_skips":[]}
var failure: bool = false
var frozen_state: Dictionary = {}
var user_files_before: Dictionary = {}

func _initialize() -> void:
	call_deferred("run_probe")

func wait_frames(count: int) -> void:
	for _index: int in range(count): await process_frame

func check(label: String, passed: bool, detail: Variant = null) -> void:
	report["checks"].append({"name":label,"passed":passed,"detail":detail})
	if not passed: failure = true
	print(("PASS " if passed else "FAIL ") + "PRESENTATION_CALIBRATION " + label)

func read_json(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func file_evidence(path: String) -> Dictionary:
	var stream: FileAccess = FileAccess.open(path, FileAccess.READ)
	return {"path":path,"sha256":FileAccess.get_sha256(path),"bytes":stream.get_length() if stream != null else -1}

func checked_source(path: String, found: Dictionary) -> void:
	var evidence: Dictionary = file_evidence(path)
	check("source_available_"+path,int(evidence["bytes"])>0 and str(evidence["sha256"]).length()==64,evidence)
	found[path] = evidence

func source_tree(directory: String, found: Dictionary) -> void:
	for name: String in DirAccess.get_files_at(directory):
		if name.ends_with(".gd") or name.ends_with(".gd.uid") or name.ends_with(".tscn"):
			checked_source(directory.path_join(name),found)
	for child: String in DirAccess.get_directories_at(directory):
		source_tree(directory.path_join(child),found)

func user_file_evidence() -> Dictionary:
	# Observe only. Never save, load, restore or copy a player's private data.
	var found: Dictionary = {}
	for path: String in ["user://settings.cfg","user://quicksave.dat","user://town3d_quicksave.dat"]:
		if FileAccess.file_exists(path):
			var evidence: Dictionary = file_evidence(path)
			check("existing_user_file_readable_"+path,int(evidence["bytes"])>=0 and str(evidence["sha256"]).length()==64,evidence)
			found[path] = evidence
		else:
			found[path] = {"path":path,"exists":false}
	return found

func bindings() -> Dictionary:
	var found: Dictionary = {}
	for path: String in ["res://project.godot", "res://scenes/Main.tscn", "res://scripts/Main.gd", "res://scripts/WorldView3D.gd", "res://scripts/TownModel3D.gd", "res://scripts/TownCharacter3D.gd", "res://scripts/LifeMode.gd", "res://scripts/ui/TownHud.gd", "res://scripts/ui/TownHudStyle.gd", "res://scripts/Probe3D.gd", "res://scripts/ProbeController.gd", "res://scripts/Sim.gd", "res://scripts/TownWorldProfile.gd", "res://data/town3d/projection.json", "res://data/town3d/profile.json", "res://data/town3d/characters.json", "res://assets/town3d/stage_manifest.json", get_script().resource_path]:
		checked_source(path,found)
	source_tree("res://scripts",found)
	source_tree("res://scenes",found)
	var stage: Dictionary = read_json("res://assets/town3d/stage_manifest.json")
	checked_source("res://bench/Invariants.gd",found)
	check("staged_raw_inventory_present",stage.get("status","")=="PASS" and not stage.get("files",[]).is_empty())
	var names: Dictionary = {}
	for entry: Dictionary in stage.get("files", []):
		var name: String = str(entry.get("file", ""))
		if name.is_empty() or name.get_file() != name or names.has(name):
			check("safe_raw_town_binding", false, name)
			continue
		names[name] = true
		var path: String = "res://assets/town3d/" + name
		var evidence: Dictionary = file_evidence(path)
		check("raw_town_" + name, str(evidence["sha256"]).length()==64 and int(evidence["bytes"])>0 and evidence["sha256"] == entry.get("sha256", "") and evidence["bytes"] == int(entry.get("bytes", -2)), evidence)
		found[path] = evidence
	var characters: Dictionary = read_json("res://data/town3d/characters.json").get("characters", {})
	check("character_raw_inventory_present",not characters.is_empty())
	for ident: String in characters:
		var entry: Dictionary = characters[ident]
		var path: String = str(entry.get("model", ""))
		if not path.begins_with("res://assets/characters3d/") or path.get_file().is_empty() or path.contains(".."):
			check("safe_raw_character_binding_"+ident,false,path)
			continue
		var evidence: Dictionary = file_evidence(path)
		check("raw_character_" + ident, str(evidence["sha256"]).length()==64 and int(evidence["bytes"])>0 and evidence["sha256"] == entry.get("model_sha256", "") and evidence["bytes"] == int(entry.get("model_bytes", -2)), evidence)
		found[path] = evidence
	return found

func state() -> Dictionary:
	var agents: Array = []
	for agent: Dictionary in sim.get("agents"):
		agents.append({"id":agent.get("id"),"space":agent.get("space"),"floor":agent.get("floor"),"pos":str(agent.get("pos")),"needs":agent.get("needs",{}).duplicate(true),"option":agent.get("option").duplicate(true) if agent.get("option") is Dictionary else null,"coin":sim.call("_coin_of",str(agent.get("id",""))),"job":sim.call("_job_of",str(agent.get("id",""))).duplicate(true),"inventory":agent.get("inventory",{}).duplicate(true)})
	return {"tick":sim.get("tick_no"),"day":sim.get("day"),"time_of_day":sim.call("time_of_day"),"event_digest":sim.get("event_digest"),"semantic_digest":Inv.digest(sim),"semantic_state_chain":Inv.chain_step(Inv.CHAIN_INIT,sim,0),"money_total":sim.call("money_total"),"speed":sim.get("speed"),"controlled_id":sim.get("controlled_id"),"running":sim.get("running"),"agents":agents}

func key(code: Key, shift: bool = false) -> void:
	var receipt: Dictionary = {"kind":"actual_viewport_key","keycode":int(code),"physical_keycode":int(code),"shift_pressed":shift,"press_tick":sim.get("tick_no")}
	report["hud_input_events"].append(receipt)
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.shift_pressed = shift
	root.push_input(event, true)
	await wait_frames(1)
	var release: InputEventKey = InputEventKey.new()
	release.keycode = code
	release.physical_keycode = code
	release.shift_pressed = shift
	root.push_input(release, true)
	await wait_frames(2)
	receipt["release_tick"] = sim.get("tick_no")
	receipt["press_and_release_sent"] = true

func click_control(control: Control, label: String) -> void:
	var point: Vector2 = control.get_global_rect().get_center()
	report["hud_input_events"].append({"kind":"actual_viewport_mouse","label":label,"point":[point.x,point.y],"control":str(control.get_path()),"disabled":control.disabled if control is Button else false,"tick":sim.get("tick_no")})
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.position = point
	press.global_position = point
	press.pressed = true
	root.push_input(press,true)
	await wait_frames(1)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = point
	release.global_position = point
	root.push_input(release,true)
	await wait_frames(2)

func hud_capture(label: String) -> void:
	await wait_frames(3)
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	if pixels == null:
		check("hud_actual_framebuffer_"+label,false)
		return
	var path: String = output.path_join("hud__"+label+".png")
	check("hud_png_"+label,pixels.save_png(path)==OK)
	report["hud_captures"].append({"label":label,"file":file_evidence(path),"image_size":[pixels.get_width(),pixels.get_height()],"logical_viewport_size":str(root.get_visible_rect().size),"window_size":str(root.size),"content_scale_size":str(root.content_scale_size),"tick":sim.get("tick_no"),"paused":not bool(sim.get("running")),"observed_semantic_state_unchanged":state()==frozen_state,"calibration_only":true})
	check("hud_core_unchanged_"+label,state()==frozen_state)

func hud_geometry(label: String) -> void:
	var hud: Node = main.get("_town_hud")
	var viewport: Rect2 = Rect2(Vector2.ZERO,root.get_visible_rect().size)
	var controls: Dictionary = {"clock":main.get("_status_pan"),"toolbar":hud.get("toolbar"),"activity":main.get("_log_card"),"resident":life.get("_town_resident_card"),"wishes":life.get("_wants_panel")}
	var bounds: Dictionary = {}
	for name: String in controls:
		var control: Control = controls[name] as Control
		var rect: Rect2 = control.get_global_rect()
		bounds[name] = str(rect)
		check("hud_visible_in_bounds_"+label+"_"+name,control.is_visible_in_tree() and viewport.encloses(rect),bounds[name])
	var activity_rect: Rect2 = (controls["activity"] as Control).get_global_rect()
	var wishes_rect: Rect2 = (controls["wishes"] as Control).get_global_rect()
	check("hud_activity_wishes_clear_"+label,not activity_rect.intersects(wishes_rect),bounds)
	var fills: Dictionary = life.get("_need_fill")
	var values: Dictionary = life.get("_need_val")
	var all_five: bool = fills.size()==5 and values.size()==5
	for nid: String in ["hunger","energy","social","fun","hygiene"]:
		all_five = all_five and fills.has(nid) and values.has(nid) and (fills[nid] as Control).is_visible_in_tree() and (values[nid] as Control).is_visible_in_tree()
	check("hud_all_five_needs_visible_"+label,all_five)
	check("hud_pause_disclosed_"+label,not bool(sim.get("running")) and "Paused" in (main.get("_status") as RichTextLabel).get_parsed_text())

func exercise_hud(label: Label, home_shot: Dictionary) -> void:
	var hud: Node = main.get("_town_hud")
	check("actual_refined_hud_present",hud!=null and life.get("_town_wants_toggle")!=null)
	if hud == null or life.get("_town_wants_toggle")==null: return
	keeper.shot = home_shot
	# Allow presentation frames to settle. This is frame based and does not claim
	# that a four-second toast has elapsed. No clock/actor assignment occurs here.
	await wait_frames(24)
	for resolution: Vector2i in [Vector2i(1280,768),Vector2i(960,540)]:
		# Deliberately inspect the actual logical canvas at both target sizes, rather
		# than merely downscaling a fixed1280 canvas into a smaller native window.
		root.content_scale_size = resolution
		DisplayServer.window_set_size(resolution)
		await wait_frames(6)
		var tag: String = "%dx%d" % [resolution.x,resolution.y]
		check("hud_requested_logical_resolution_"+tag,root.get_visible_rect().size==Vector2(resolution),str(root.get_visible_rect().size))
		label.text = "HUD CALIBRATION | Paused actual Main | GUI input | Not gameplay evidence"
		label.add_theme_font_size_override("font_size",12)
		label.position = Vector2(300,82 if resolution.x<1000 else 50)
		var activity: Button = hud.get("activity") as Button
		var wishes: Button = life.get("_town_wants_toggle") as Button
		var speeds: Array = hud.get("buttons")
		var controls_available: bool = activity!=null and wishes!=null and speeds.size()==4
		for button: Variant in speeds: controls_available = controls_available and button is Button
		check("hud_actual_gui_controls_available_"+tag,controls_available)
		if not controls_available: return
		if bool(hud.get("expanded")): await click_control(activity,"initial_activity_close_"+tag)
		if bool(life.get("_town_wants_expanded")): await click_control(wishes,"initial_wishes_close_"+tag)
		await click_control(speeds[0] as Button,"public_pause_button_"+tag)
		hud_geometry(tag+"_compact")
		await hud_capture(tag+"_compact")
		await click_control(activity,"activity_open_"+tag)
		check("hud_activity_click_opens_"+tag,bool(hud.get("expanded")) and (main.get("_logbox") as RichTextLabel).text==str(hud.get("full_feed")))
		await click_control(wishes,"wishes_open_"+tag)
		check("hud_wishes_click_opens_"+tag,bool(life.get("_town_wants_expanded")))
		hud_geometry(tag+"_expanded")
		await hud_capture(tag+"_expanded")
		await click_control(activity,"activity_close_"+tag)
		await click_control(wishes,"wishes_close_"+tag)
		check("hud_expansion_click_closes_"+tag,not bool(hud.get("expanded")) and not bool(life.get("_town_wants_expanded")))
		await key(KEY_H)
		check("hud_activity_keyboard_opens_"+tag,bool(hud.get("expanded")))
		await key(KEY_H)
		await key(KEY_H,true)
		check("hud_wishes_keyboard_opens_"+tag,bool(life.get("_town_wants_expanded")))
		await key(KEY_H,true)
		check("hud_keyboard_closes_"+tag,not bool(hud.get("expanded")) and not bool(life.get("_town_wants_expanded")))
		# E opens the real nearby authored home fixture menu. Never select an
		# action, move a resident, or fabricate an interest if none is safe nearby.
		var focus: Dictionary = life.call("_focused")
		var objects: Dictionary = sim.get("world").get("objects",{})
		if str(focus.get("kind",""))=="object" and objects.has(str(focus.get("id",""))):
			await key(KEY_E)
			check("hud_real_home_fixture_menu_"+tag,bool(life.get("_modal_open")) and str(life.get("_modal_entry").get("kind",""))=="object",life.get("_modal_entry").get("id"))
			check("hud_modal_disables_clock_"+tag,(speeds[1] as Button).disabled and bool(hud.call("clock_blocked")))
			await click_control(speeds[1] as Button,"disabled_clock_during_real_menu_"+tag)
			check("hud_disabled_clock_click_keeps_pause_"+tag,state()==frozen_state and bool(life.get("_modal_open")))
			await hud_capture(tag+"_real_home_menu")
			await key(KEY_ESCAPE)
			check("hud_escape_restores_paused_menu_state_"+tag,not bool(life.get("_modal_open")) and state()==frozen_state)
		else:
			report["hud_safe_skips"].append({"resolution":tag,"test":"real_home_fixture_menu","reason":"No safe already-nearby object focus; no actor or interest relocation invented.","focus":focus})
		check("hud_resolution_all_core_state_unchanged_"+tag,state()==frozen_state)

func capture(variant: Dictionary, shot: Dictionary) -> void:
	keeper.shot = shot
	await wait_frames(3)
	await RenderingServer.frame_post_draw
	var raw: Image = (view.get("viewport_3d") as SubViewport).get_texture().get_image()
	var frame: Image = root.get_texture().get_image()
	if raw == null or frame == null:
		check("actual_framebuffer_non_null", false, shot["name"])
		return
	var base: String = str(variant["name"]) + "__" + str(shot["name"])
	var raw_path: String = output.path_join(base + "__actual_subviewport.png")
	var frame_path: String = output.path_join(base + "__labeled_main.png")
	check("write_" + base, raw.save_png(raw_path) == OK and frame.save_png(frame_path) == OK)
	var camera: Camera3D = view.get("camera_3d") as Camera3D
	report["captures"].append({"variant":variant,"shot":{"name":shot["name"],"space":shot["space"],"floor":shot["floor"],"canonical_center_px":[shot["center"].x,shot["center"].y],"size_m":shot["size_m"]},"camera_transform":str(camera.global_transform),"actual_camera_size_m":camera.size,"tick":sim.get("tick_no"),"raw_subviewport":file_evidence(raw_path),"labeled_main":file_evidence(frame_path),"dimensions":[raw.get_width(),raw.get_height()]})
	check("frozen_authoritative_state_" + base, state() == frozen_state)

func finish_probe() -> void:
	if not user_files_before.is_empty():
		report["user_files_after"] = user_file_evidence()
		check("existing_user_files_unchanged",report["user_files_after"]==user_files_before)
	report["status"] = "FAIL" if failure else "DIAGNOSTIC_COMPLETE"
	if not output.is_empty():
		var path: String = output.path_join("calibration_report.json")
		var stream: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if stream == null:
			push_error("Cannot write fresh calibration report")
			quit(1)
			return
		stream.store_string(JSON.stringify(report,"\t") + "\n")
		stream.close()
		print("PRESENTATION_CALIBRATION_REPORT=" + path + " SHA256=" + FileAccess.get_sha256(path))
	quit(1 if failure else 0)

func safe_arguments(args: PackedStringArray) -> bool:
	var values: Dictionary = {}
	var index: int = 0
	while index < args.size():
		var flag: String = args[index]
		if flag in ["--town3d","--life"] and not values.has(flag):
			values[flag] = true
			index += 1
		elif flag in ["--backend","--seed","--agents","--speed","--presentation-probe-dir","--lighting-probe-dir"] and not values.has(flag) and index+1<args.size():
			values[flag] = args[index+1]
			index += 2
		else:
			return false
	if not values.has("--town3d") or not values.has("--life") or values.get("--backend","")!="logic" or values.get("--speed","")!="0": return false
	if not str(values.get("--seed","")).is_valid_int() or not str(values.get("--agents","")).is_valid_int(): return false
	if values.has("--presentation-probe-dir")==values.has("--lighting-probe-dir"): return false
	output = str(values.get("--presentation-probe-dir",values.get("--lighting-probe-dir","")))
	return true

func run_probe() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not safe_arguments(args):
		push_error("Require explicit --town3d --life --backend logic --seed N --agents N --speed 0 and exactly one probe directory; other flags are unsupported")
		quit(2)
		return
	if not output.is_absolute_path() or (DirAccess.dir_exists_absolute(output) and (not DirAccess.get_files_at(output).is_empty() or not DirAccess.get_directories_at(output).is_empty())):
		push_error("Require a fresh absolute --presentation-probe-dir directory")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(output)!=OK:
		push_error("Cannot create fresh presentation evidence directory")
		quit(1)
		return
	user_files_before = user_file_evidence()
	report["user_files_before"] = user_files_before
	report["arguments"] = Array(args)
	report["sources_before"] = bindings()
	check("actual_gpu_display", DisplayServer.get_name() != "headless", DisplayServer.get_name())
	if failure:
		finish_probe()
		return
	sim = root.get_node("Sim")
	main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await wait_frames(20)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280,768))
	await wait_frames(4)
	view = main.get("_view")
	life = main.get("_life")
	check("actual_main_lifemode_view", view != null and life != null and view.has_method("get_bridge_info"))
	if failure:
		finish_probe()
		return
	report["bridge_before"] = view.call("get_bridge_info")
	check("actual_whole_town_and_mesh_residents", int(report["bridge_before"].get("model",{}).get("building_count",0)) >= 151 and int(report["bridge_before"].get("mesh_actor_count",0)) >= 12, report["bridge_before"])
	if failure:
		finish_probe()
		return
	life.call("start_life", "aria")
	await wait_frames(2)
	await key(KEY_0)
	check("public_pause_input_applied", not bool(sim.get("running")) and str(sim.get("controlled_id")) == "aria")
	if failure:
		finish_probe()
		return
	var sun: DirectionalLight3D = view.get("_sun_3d") as DirectionalLight3D
	var environment: Environment = view.get("_environment_3d") as Environment
	var original: Dictionary = {"name":"00_actual_paused_lighting","sun":sun.light_energy,"ambient":environment.ambient_light_energy,"exposure":environment.tonemap_exposure}
	report["actual_render_settings"] = {"rendering_method":RenderingServer.call("get_current_rendering_method") if RenderingServer.has_method("get_current_rendering_method") else ProjectSettings.get_setting("rendering/renderer/rendering_method"),"rendering_driver":RenderingServer.call("get_current_rendering_driver_name") if RenderingServer.has_method("get_current_rendering_driver_name") else "unavailable","display_driver":DisplayServer.get_name(),"tonemap_mode_requested":environment.tonemap_mode,"sun_color":sun.light_color.to_html(),"ambient_color":environment.ambient_light_color.to_html(),"sun_rotation_degrees":str(sun.rotation_degrees),"original":original,"compatibility_note":"gl_compatibility is LDR; a requested AGX enum does not establish an HDR tone-map response."}
	# Preserve the normal actual presentation pipeline: camera49 -> actualview50
	# -> presentation lighting51. Never freeze cached actor/overlay presentation.
	keeper = CameraKeeper.new()
	keeper.main = main
	keeper.view = view
	keeper.probe = main.get("_probe")
	keeper.process_priority = 49
	root.add_child(keeper)
	late_lights = LateLightOverride.new()
	late_lights.sun = sun
	late_lights.environment = environment
	late_lights.values = original
	late_lights.process_priority = 51
	root.add_child(late_lights)
	report["normal_view_pipeline"] = {"view_process_enabled":view.is_processing(),"view_process_priority":view.process_priority,"camera_keeper_priority":keeper.process_priority,"late_light_override_priority":late_lights.process_priority,"lighting_override_presentation_only":true}
	check("actual_normal_view_presentation_pipeline",view.is_processing() and view.process_priority==50 and keeper.process_priority==49 and late_lights.process_priority==51,report["normal_view_pipeline"])
	var label_layer: CanvasLayer = CanvasLayer.new()
	label_layer.layer = 100
	root.add_child(label_layer)
	var label: Label = Label.new()
	label.position = Vector2(8,39)
	label.add_theme_color_override("font_color", Color.YELLOW)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_outline_size", 4)
	label.text = "PRESENTATION CALIBRATION | Actual paused Main | Lighting/camera overrides | Not gameplay evidence"
	label_layer.add_child(label)
	await wait_frames(2)
	frozen_state = state()
	report["frozen_state"] = frozen_state
	report["scope"] = "One actual Main, public LifeMode.start_life(aria) and Viewport KEY_0. No direct clock/address writes, teleport, save/load, asset/material changes or renderer switch. Four presentation light states, with identical observed semantic Sim state and camera per comparison. Actual WorldView3D remains processing at priority50, with cameraKeeper49 and light-only override51; actors, per-plane visibility, prompts and overlay redraw retain the normal product pipeline. LifeMode and Main continue processing. Raw subviewport images exclude UI and are intended for offline clipping histograms. HUD clicks/keyboard and logical-window resizing are presentation/input checks. All frames are calibration, not gameplay proof."
	var plane: Dictionary = view.get("projection_3d").get("planes",{}).get("cafe/2f",{})
	var size: Array = plane.get("grid_size",[40,36])
	var shots: Array[Dictionary] = [
		{"name":"upper_home","space":"cafe","floor":"2f","center":Vector2(float(size[0]),float(size[1]))*24,"size_m":13.0},
		{"name":"street_plaster_paving","space":"town","floor":"outdoor","center":view.call("world_to_canonical",Vector3(4,0,5),"town","outdoor"),"size_m":23.0},
		{"name":"pocket_garden_soil","space":"town","floor":"outdoor","center":view.call("world_to_canonical",Vector3(22,0,-3),"town","outdoor"),"size_m":13.0}]
	var variants: Array[Dictionary] = [original,
		{"name":"01_morning_equivalent_baseline","sun":1.5,"ambient":0.40,"exposure":1.0},
		{"name":"02_candidate_A","sun":0.85,"ambient":0.28,"exposure":1.0},
		{"name":"03_candidate_B","sun":1.0,"ambient":0.25,"exposure":1.0}]
	for variant: Dictionary in variants:
		late_lights.values = variant
		label.text = "PRESENTATION CALIBRATION | %s | sun %.2f ambient %.2f exposure %.2f | Not gameplay" % [variant["name"],variant["sun"],variant["ambient"],variant["exposure"]]
		for shot: Dictionary in shots: await capture(variant, shot)
	await exercise_hud(label,shots[0])
	report["state_after"] = state()
	report["sources_after"] = bindings()
	check("all_source_bindings_stable", report["sources_before"] == report["sources_after"])
	check("all_observed_semantic_state_stable", report["state_after"] == frozen_state)
	finish_probe()
