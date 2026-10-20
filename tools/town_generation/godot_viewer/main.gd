extends Node3D
## Actual runtime glTF import and framebuffer evidence; no game physics claim.
const SOURCE_NAME: StringName = &"_territory_source_name"
const SOURCE_BUILDING: StringName = &"_territory_building"
const SOURCE_LAYER: StringName = &"_territory_layer"
var config: Dictionary = {}
var report: Dictionary = {"schema": "living_town.territory_consumer.v1", "checks": [], "captures": [], "status": "RUNNING"}
var failures: int = 0
var imported_meshes: int = 0
var input_bindings: Array[Dictionary] = []
var all_meshes: Array[MeshInstance3D] = []
var camera: Camera3D
var caption: Label
var active: bool = false
var tour_frame: int = 0
var chapter_index: int = -1
var camera_rows: Array = []
var temporary_hidden: Array[Node3D] = []
var capture_directory: String = ""
var report_path: String = ""
var movie_mode: bool = false
var texture_cache: Dictionary = {}
var seen_materials: Dictionary = {}


func _ready() -> void:
	call_deferred("begin")


func check(label: String, passed: bool, detail: Variant = null) -> void:
	report["checks"].append({"name": label, "passed": passed, "detail": detail})
	if not passed:
		failures += 1
		push_error("TERRITORY CONSUMER: " + label + " " + str(detail))


func read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func read_glb(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 28:
		return {}
	var valid: bool = file.get_buffer(4).get_string_from_ascii() == "glTF"
	valid = valid and file.get_32() == 2 and file.get_32() == file.get_length()
	var count: int = file.get_32()
	valid = valid and file.get_32() == 0x4E4F534A and count <= file.get_length()-20
	if not valid:
		file.close()
		return {}
	var parsed: Variant = JSON.parse_string(file.get_buffer(count).get_string_from_utf8())
	file.close()
	return parsed if parsed is Dictionary else {}


func collect(node: Node, excluded: Dictionary) -> int:
	var count: int = 0
	var original_name: String = str(node.get_meta(SOURCE_NAME, node.name))
	if node is Node3D and excluded.has(original_name):
		node.visible = false
		report["hidden_baseline_nodes"].append(original_name)
	if node is MeshInstance3D:
		all_meshes.append(node)
		count += 1
	for child: Node in node.get_children():
		count += collect(child, excluded)
	return count


func import_asset(row: Dictionary, excluded: Dictionary) -> void:
	var path: String = str(row["path"])
	check("asset_exists_" + path.get_file(), FileAccess.file_exists(path))
	if not FileAccess.file_exists(path):
		return
	var before: String = FileAccess.get_sha256(path)
	check("asset_sha_" + path.get_file(), before == str(row["sha256"]))
	input_bindings.append({"path": path, "sha256": before})
	var raw: Dictionary = read_glb(path)
	check("valid_glb_" + path.get_file(), not raw.is_empty())
	if raw.is_empty():
		return
	var state: GLTFState = GLTFState.new()
	var document: GLTFDocument = GLTFDocument.new()
	var error: Error = document.append_from_file(path, state)
	check("gltf_import_" + path.get_file(), error == OK, error)
	if error != OK:
		return
	var nodes: Array[GLTFNode] = state.get_nodes()
	for i: int in range(nodes.size()):
		var extras: Dictionary = raw["nodes"][i].get("extras", {})
		# The optimized baseline appends mesh suffixes to glTF node names.
		# Source-object extras retain the exact native identity used by clearing.
		nodes[i].set_meta(SOURCE_NAME, str(extras.get("source_object", raw["nodes"][i].get("name", ""))))
		nodes[i].set_meta(SOURCE_BUILDING, str(extras.get("building_id", extras.get("interior_building_id", ""))))
		nodes[i].set_meta(SOURCE_LAYER, str(extras.get("presentation_layer", "")))
	var scene: Node3D = document.generate_scene(state) as Node3D
	check("scene_generated_" + path.get_file(), scene != null)
	if scene == null:
		return
	add_child(scene)
	var actual: int = collect(scene, excluded if bool(row.get("baseline", false)) else {})
	var expected: int = 0
	for node: Dictionary in raw.get("nodes", []):
		if node.has("mesh"):
			expected += 1
	check("mesh_count_" + path.get_file(), actual == expected and actual > 0, {"actual": actual, "expected": expected})
	imported_meshes += actual
	for mesh: MeshInstance3D in all_meshes:
		for surface: int in range(mesh.mesh.get_surface_count()):
			var material: BaseMaterial3D = mesh.get_active_material(surface) as BaseMaterial3D
			if material == null or seen_materials.has(material.get_instance_id()):
				continue
			seen_materials[material.get_instance_id()] = true
			for slot: int in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_ORM]:
				var texture: Texture2D = material.get_texture(slot)
				if texture == null:
					continue
				var key: String = str(texture.get_instance_id()) + (":normal" if slot == BaseMaterial3D.TEXTURE_NORMAL else ":color")
				if not texture_cache.has(key):
					var decoded: Image = texture.get_image()
					if decoded != null and not decoded.is_empty() and not decoded.has_mipmaps():
						var working: Image = Image.new()
						working.copy_from(decoded)
						if working.is_compressed():
							working.decompress()
						var mip_error: Error = working.generate_mipmaps(slot == BaseMaterial3D.TEXTURE_NORMAL)
						check("texture_mipmaps_" + key, mip_error == OK)
						texture_cache[key] = ImageTexture.create_from_image(working)
					else:
						texture_cache[key] = texture
				material.set_texture(slot, texture_cache[key])
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


func presentation() -> void:
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("bbd3d8")
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.environment.tonemap_agx_white = 16.29
	environment.environment.tonemap_exposure = .9
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d7e3e4")
	environment.environment.ambient_light_energy = .45
	add_child(environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.light_energy = .8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 600
	add_child(sun)
	# The native summer sun Euler(.55,-.65,-.65), converted from Z-up.
	sun.look_at(Vector3(.7270517,-.67868096,-.10386523),Vector3.UP)
	camera = Camera3D.new()
	camera.near = .07
	camera.far = 2200
	camera.fov = 55
	add_child(camera)
	camera.current = true
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var panel: ColorRect = ColorRect.new()
	panel.position = Vector2(20, 18)
	panel.size = Vector2(880, 72)
	panel.color = Color(.06, .11, .11, .82)
	layer.add_child(panel)
	caption = Label.new()
	caption.position = Vector2(38, 26)
	caption.add_theme_font_size_override("font_size", 22)
	layer.add_child(caption)
	var footer: Label = Label.new()
	footer.text = "Architectural asset inspection / engine-agnostic glTF / Godot Compatibility renderer"
	footer.position = Vector2(26, 768)
	footer.add_theme_font_size_override("font_size", 16)
	footer.add_theme_color_override("font_shadow_color", Color.BLACK)
	footer.add_theme_constant_override("shadow_outline_size", 5)
	layer.add_child(footer)


func vector(value: Array) -> Vector3:
	# Config camera poses use Blender Z-up metres.
	return Vector3(float(value[0]), float(value[2]), -float(value[1]))


func set_chapter(index: int) -> void:
	for node: Node3D in temporary_hidden:
		node.visible = true
	temporary_hidden.clear()
	var row: Dictionary = camera_rows[index]
	var patterns: Array = row.get("hide_contains", [])
	var cutaway: Dictionary = row.get("cutaway", {})
	var cutaway_counts: Dictionary = {}
	for mesh: MeshInstance3D in all_meshes:
		var source: String = str(mesh.get_meta(SOURCE_NAME, mesh.name))
		if not cutaway.is_empty() and str(mesh.get_meta(SOURCE_BUILDING, "")) == str(cutaway["building_id"]):
			# Exported native collection roles preserve the exact cutaway;
			# ground stairs stay visible even when they reach the next storey.
			var hide: bool = str(mesh.get_meta(SOURCE_LAYER,"")) in ["front","roof","upper"]
			if hide and mesh.visible:
				var role: String = str(mesh.get_meta(SOURCE_LAYER,""))
				cutaway_counts[role] = int(cutaway_counts.get(role,0))+1
				mesh.visible = false
				temporary_hidden.append(mesh)
				continue
		for pattern: String in patterns:
			if pattern in source and mesh.visible:
				mesh.visible = false
				temporary_hidden.append(mesh)
				break
	if not cutaway.is_empty():
		for mesh: MeshInstance3D in all_meshes:
			if (str(mesh.get_meta(SOURCE_BUILDING,"")) == str(cutaway["building_id"])
				and str(mesh.get_meta(SOURCE_LAYER,"")) == "structure" and mesh.is_visible_in_tree()):
				cutaway_counts["structure"] = int(cutaway_counts.get("structure",0))+1
		var expected_layers: Dictionary = cutaway.get("expected_layer_counts",{})
		for role: String in ["front","roof","upper","structure"]:
			check("native_cutaway_"+role,int(cutaway_counts.get(role,0))==int(expected_layers.get(role,-1)),
				{"actual":cutaway_counts.get(role,0),"expected":expected_layers.get(role,-1)})
		report["cutaway_layers"] = cutaway_counts
	caption.text = str(row["title"]) + "\n" + str(row.get("subtitle", "Actual imported asset geometry"))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if row.get("projection", "perspective") == "orthographic" else Camera3D.PROJECTION_PERSPECTIVE
	camera.size = float(row.get("size", 240))
	camera.fov = float(row.get("fov_degrees",55))
	chapter_index = index


func pose(index: int, t: float) -> void:
	var row: Dictionary = camera_rows[index]
	var eased: float = t*t*(3.0-2.0*t)
	camera.position = vector(row["from"]).lerp(vector(row.get("to", row["from"])), eased)
	camera.look_at(vector(row["target"]).lerp(vector(row.get("target_to", row["target"])), eased), Vector3.UP)


func take_capture(index: int) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	check("framebuffer_" + str(index), image != null and not image.is_empty())
	if image == null or image.is_empty():
		return
	var path: String = capture_directory.path_join("%02d_%s.png" % [index+1, str(camera_rows[index]["id"])])
	var error: Error = image.save_png(path)
	check("capture_saved_" + str(index), error == OK, error)
	if error == OK:
		report["captures"].append({"path": path, "sha256": FileAccess.get_sha256(path), "chapter": camera_rows[index]})


func finish() -> void:
	active = false
	for row: Dictionary in input_bindings:
		check("input_unchanged_" + str(row["path"]).get_file(), FileAccess.get_sha256(row["path"]) == str(row["sha256"]))
	report["status"] = "PASS" if failures == 0 else "FAIL"
	report["failure_count"] = failures
	report["imported_meshes"] = imported_meshes
	report["tour_frames"] = tour_frame
	report["movie_mode"] = movie_mode
	report["scope"] = "Runtime imports, explicit baseline clearing and actual framebuffer capture. MovieWriter is offline capture; no real-time performance, game physics or navigation claim."
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	else:
		failures += 1
	print("TERRITORY_CONSUMER " + report["status"] + " " + report_path)
	get_tree().quit(0 if failures == 0 else 1)


func _process(_delta: float) -> void:
	if not active or not movie_mode:
		return
	var fps: int = int(config.get("fps", 18))
	var seconds: float = float(tour_frame) / fps
	var total: float = float(config.get("duration_seconds", 360))
	if seconds >= total:
		finish()
		return
	var slot: float = total / camera_rows.size()
	var index: int = mini(camera_rows.size()-1, int(seconds/slot))
	if chapter_index != index:
		set_chapter(index)
	pose(index, fmod(seconds,slot)/slot)
	tour_frame += 1


func begin() -> void:
	report["consumer_source_sha256"] = FileAccess.get_sha256("res://main.gd")
	report["project_sha256"] = FileAccess.get_sha256("res://project.godot")
	var config_path: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--config="):
			config_path = argument.trim_prefix("--config=")
		elif argument == "--movie":
			movie_mode = true
	config = read_json(config_path)
	if config.is_empty():
		push_error("Missing territory inspection config")
		get_tree().quit(1)
		return
	report_path = str(config["report"])
	capture_directory = str(config["capture_directory"])
	DirAccess.make_dir_recursive_absolute(capture_directory)
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	report["engine_version"] = Engine.get_version_info()
	report["display_server"] = DisplayServer.get_name()
	report["hidden_baseline_nodes"] = []
	report["config_sha256"] = FileAccess.get_sha256(config_path)
	report["script_sha256"] = FileAccess.get_sha256("res://main.gd")
	report["project_sha256"] = FileAccess.get_sha256("res://project.godot")
	check("real_render_driver", DisplayServer.get_name() != "headless")
	var excluded: Dictionary = {}
	for source: String in config.get("removed_baseline_object_names", []):
		excluded[source] = true
	for row: Dictionary in config["assets"]:
		import_asset(row,excluded)
	check("all_requested_baseline_clearings_found", report["hidden_baseline_nodes"].size() == excluded.size(), {"requested": excluded.size(), "found": report["hidden_baseline_nodes"].size()})
	if failures > 0:
		finish()
		return
	presentation()
	camera_rows = config["cameras"]
	if movie_mode:
		set_chapter(0)
		pose(0,0)
		for _warmup: int in range(12):
			await get_tree().process_frame
		report["movie_warmup_engine_frames"] = Engine.get_process_frames()
		active = true
		return
	for i: int in range(camera_rows.size()):
		set_chapter(i)
		pose(i,.5)
		for _wait: int in range(12):
			await get_tree().process_frame
		await take_capture(i)
	finish()
