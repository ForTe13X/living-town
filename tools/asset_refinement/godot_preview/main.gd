extends Node3D
## Runtime GLB consumer. A PASS proves visual import and a real capture, not
## collision, navigation, gameplay integration, performance or artistic approval.
const WIDTH: int = 1440
const HEIGHT: int = 1000
const CAPTURE_TIMEOUT_SECONDS: float = 10.0

var report: Dictionary = {"schema": "living_town.asset_refinement_preview.v1", "status": "RUNNING", "checks": [], "scope": "Runtime GLB visual import and framebuffer capture only; no physics, navigation or performance claim."}
var asset_path: String = ""
var capture_path: String = ""
var report_path: String = ""
var failures: int = 0
var finished: bool = false
var capture_frames: int = 0
var meshes: Array[MeshInstance3D] = []
var texture_cache: Dictionary = {}
var texture_mipmap_records: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("run_preview")


func check(label: String, passed: bool, detail: Variant = null) -> void:
	report["checks"].append({"name": label, "passed": passed, "detail": detail})
	if not passed:
		failures += 1
		push_error("ASSET PREVIEW: " + label + " " + str(detail))


func vector_values(v: Vector3) -> Array[float]:
	return [v.x, v.y, v.z]


func file_record(path: String) -> Dictionary:
	return {"path": path, "sha256": FileAccess.get_sha256(path)}


func read_glb(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	if file.get_length() < 20:
		file.close()
		return {}
	var valid: bool = file.get_buffer(4).get_string_from_ascii() == "glTF"
	valid = valid and file.get_32() == 2 and file.get_32() == file.get_length()
	var length: int = file.get_32()
	valid = valid and file.get_32() == 0x4E4F534A and length > 1 and length <= file.get_length()-20
	if not valid:
		file.close()
		return {}
	var parsed: Variant = JSON.parse_string(file.get_buffer(length).get_string_from_utf8())
	file.close()
	return parsed if parsed is Dictionary else {}


func collect_meshes(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		meshes.append(node)
	for child: Node in node.get_children():
		collect_meshes(child)


func bounds_of_meshes() -> AABB:
	var bounds: AABB = AABB()
	var first: bool = true
	for item: MeshInstance3D in meshes:
		var local: AABB = item.mesh.get_aabb()
		for corner: int in range(8):
			var point: Vector3 = item.global_transform * local.get_endpoint(corner)
			if first:
				bounds = AABB(point, Vector3.ZERO)
				first = false
			else:
				bounds = bounds.expand(point)
	return bounds


func mipmapped_texture(texture: Texture2D, normal_map: bool, use_label: String) -> Texture2D:
	if texture == null:
		return null
	# Reuse each imported texture instance. A source used as both a normal and
	# a color/scalar image needs separate chains because normal mips normalize vectors.
	var key: String = str(texture.get_instance_id()) + (":normal" if normal_map else ":color_scalar")
	if texture_cache.has(key):
		var cached: Dictionary = texture_cache[key]
		texture_mipmap_records[int(cached["record_index"])]["uses"].append(use_label)
		return cached["texture"] as Texture2D
	var decoded: Image = texture.get_image()
	check("texture_decoded_" + use_label, decoded != null and not decoded.is_empty())
	if decoded == null or decoded.is_empty():
		return texture
	var before_levels: int = decoded.get_mipmap_count()
	var generated: bool = not decoded.has_mipmaps()
	var replacement: Texture2D = texture
	if generated:
		# Work on an independent decoded copy, never the source GLB or PNG bytes.
		var working: Image = Image.new()
		working.copy_from(decoded)
		if working.is_compressed():
			var decompression_error: Error = working.decompress()
			check("texture_decompressed_" + use_label, decompression_error == OK, decompression_error)
			if decompression_error != OK:
				return texture
		var mip_error: Error = working.generate_mipmaps(normal_map)
		check("texture_mip_generation_" + use_label, mip_error == OK, mip_error)
		if mip_error != OK:
			return texture
		replacement = ImageTexture.create_from_image(working)
	var actual: Image = replacement.get_image() if replacement != null else null
	var valid: bool = actual != null and not actual.is_empty()
	valid = valid and (actual.has_mipmaps() or actual.get_size() == Vector2i.ONE)
	valid = valid and actual.get_size() == decoded.get_size()
	check("texture_mips_uploaded_" + use_label, valid)
	var row: Dictionary = {"source_texture_instance_id": texture.get_instance_id(),
		"source_texture_class": texture.get_class(), "dimensions": [decoded.get_width(), decoded.get_height()],
		"source_mipmap_count": before_levels, "actual_mipmap_count": actual.get_mipmap_count() if actual != null else 0,
		"generated_missing_mipmaps": generated, "normal_vectors_renormalized": generated and normal_map,
		"replacement_texture_class": replacement.get_class() if replacement != null else "null", "uses": [use_label]}
	texture_mipmap_records.append(row)
	texture_cache[key] = {"texture": replacement, "record_index": texture_mipmap_records.size() - 1}
	return replacement


func adapt_material_sampling(pbr: BaseMaterial3D) -> void:
	var slots: Array[Dictionary] = [
		{"slot": BaseMaterial3D.TEXTURE_ALBEDO, "name": "albedo"},
		{"slot": BaseMaterial3D.TEXTURE_NORMAL, "name": "normal"},
		{"slot": BaseMaterial3D.TEXTURE_ROUGHNESS, "name": "roughness"},
		{"slot": BaseMaterial3D.TEXTURE_METALLIC, "name": "metallic"},
		{"slot": BaseMaterial3D.TEXTURE_ORM, "name": "orm"}]
	for entry: Dictionary in slots:
		var slot: int = int(entry["slot"])
		var texture: Texture2D = pbr.get_texture(slot)
		if texture != null:
			pbr.set_texture(slot, mipmapped_texture(texture, str(entry["name"]) == "normal", pbr.resource_name + ":" + str(entry["name"])))
	pbr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


func inspect_materials(document: Dictionary) -> void:
	var raw_rules: Dictionary = {}
	for material: Dictionary in document.get("materials", []):
		raw_rules[str(material.get("name", ""))] = material
	var seen: Dictionary = {}
	var records: Array[Dictionary] = []
	var colored_surfaces: int = 0
	for item: MeshInstance3D in meshes:
		for surface: int in range(item.mesh.get_surface_count()):
			var material: Material = item.get_active_material(surface)
			if not material is BaseMaterial3D:
				check("surface_has_imported_pbr_material", false, str(item.name) + ":" + str(surface))
				continue
			var pbr: BaseMaterial3D = material as BaseMaterial3D
			var arrays: Array = item.mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_COLOR] != null and not arrays[Mesh.ARRAY_COLOR].is_empty():
				pbr.vertex_color_use_as_albedo = true
				colored_surfaces += 1
			if pbr.normal_enabled:
				check("normal_surface_vectors_" + str(item.name) + "_" + str(surface),
					arrays[Mesh.ARRAY_NORMAL] != null and not arrays[Mesh.ARRAY_NORMAL].is_empty()
					and arrays[Mesh.ARRAY_TANGENT] != null and not arrays[Mesh.ARRAY_TANGENT].is_empty())
			if seen.has(pbr.get_instance_id()):
				continue
			seen[pbr.get_instance_id()] = true
			adapt_material_sampling(pbr)
			var rule: Dictionary = raw_rules.get(pbr.resource_name, {})
			check("material_source_identity_" + pbr.resource_name, not rule.is_empty())
			var raw_pbr: Dictionary = rule.get("pbrMetallicRoughness", {})
			var transform_rule: Dictionary = raw_pbr.get("baseColorTexture", {}).get("extensions", {}).get("KHR_texture_transform", {})
			if not transform_rule.is_empty():
				var expected_scale: Array = transform_rule.get("scale", [1, 1])
				var expected_offset: Array = transform_rule.get("offset", [0, 0])
				check("physical_texture_transform_retained_" + pbr.resource_name,
					absf(pbr.uv1_scale.x - float(expected_scale[0])) < .00001 and absf(pbr.uv1_scale.y - float(expected_scale[1])) < .00001
					and absf(pbr.uv1_offset.x - float(expected_offset[0])) < .00001 and absf(pbr.uv1_offset.y - float(expected_offset[1])) < .00001,
					{"source_scale": expected_scale, "godot_scale": vector_values(pbr.uv1_scale), "source_offset": expected_offset, "godot_offset": vector_values(pbr.uv1_offset)})
			var source_alpha: String = str(rule.get("alphaMode", "OPAQUE"))
			# Explicit consumer adaptation, also recorded below. No native asset is saved.
			if source_alpha == "BLEND":
				pbr.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				var factor: Array = raw_pbr.get("baseColorFactor", [1, 1, 1, 1])
				pbr.albedo_color.a = float(factor[3])
			var has_albedo: bool = pbr.get_texture(BaseMaterial3D.TEXTURE_ALBEDO) != null
			var has_normal: bool = pbr.normal_enabled and pbr.get_texture(BaseMaterial3D.TEXTURE_NORMAL) != null
			var has_orm: bool = pbr.get_texture(BaseMaterial3D.TEXTURE_ORM) != null
			var has_roughness: bool = has_orm or pbr.get_texture(BaseMaterial3D.TEXTURE_ROUGHNESS) != null
			check("pbr_metallic_roughness_source_" + pbr.resource_name, rule.has("pbrMetallicRoughness"))
			check("albedo_texture_retained_" + pbr.resource_name, not raw_pbr.has("baseColorTexture") or has_albedo)
			check("normal_texture_retained_" + pbr.resource_name, not rule.has("normalTexture") or has_normal)
			check("roughness_texture_retained_" + pbr.resource_name, not raw_pbr.has("metallicRoughnessTexture") or has_roughness)
			check("alpha_mode_retained_" + pbr.resource_name,
				(source_alpha != "BLEND" or pbr.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA)
				and (source_alpha != "MASK" or pbr.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR))
			records.append({"name": pbr.resource_name, "albedo_texture": has_albedo, "normal_texture": has_normal,
				"roughness_texture": has_roughness, "source_alpha_mode": source_alpha,
				"godot_transparency": pbr.transparency, "roughness": pbr.roughness, "metallic": pbr.metallic})
	report["materials"] = records
	report["material_adapter"] = {"rules": ["COLOR_0 multiplies albedo", "Source BLEND alpha explicitly retained",
		"Generate missing decoded-image mipmaps; renormalize normal-map mip vectors", "Cache uploaded textures per source texture instance and normal/color role",
		"Use LINEAR_WITH_MIPMAPS_ANISOTROPIC sampling"], "vertex_color_surfaces": colored_surfaces,
		"texture_filter": "LINEAR_WITH_MIPMAPS_ANISOTROPIC", "texture_mipmap_records": texture_mipmap_records,
		"cached_texture_variants": texture_cache.size(), "source_glb_and_png_files_modified": false,
		"presentation_limit": "Runtime sampling adaptation only; no matching-Blender presentation claim."}
	check("at_least_one_pbr_material", not records.is_empty())


func add_presentation(bounds: AABB) -> void:
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(.38, .59, .79)
	sky_material.sky_horizon_color = Color(.83, .87, .86)
	sky_material.ground_bottom_color = Color(.48, .47, .41)
	sky_material.ground_horizon_color = Color(.83, .87, .86)
	var sky: Sky = Sky.new()
	sky.sky_material = sky_material
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = .2
	# Keep the compatibility consumer comfortably exposed without claiming that
	# its Filmic response has been calibrated to the Blender AgX presentation.
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1, .95, .84)
	sun.light_energy = .55
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = maxf(50, bounds.size.length() * 4)
	add_child(sun)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = .05
	camera.far = maxf(100, bounds.size.length() * 20)
	add_child(camera)
	var target: Vector3 = bounds.get_center()
	var direction: Vector3 = Vector3(1.1, .8, 1.6).normalized()
	camera.position = target + direction * maxf(10, bounds.size.length() * 3)
	camera.look_at(target)
	var inverse: Transform3D = camera.global_transform.affine_inverse()
	var half_x: float = 0
	var half_y: float = 0
	for index: int in range(8):
		var corner: Vector3 = inverse * bounds.get_endpoint(index)
		half_x = maxf(half_x, absf(corner.x))
		half_y = maxf(half_y, absf(corner.y))
	camera.size = maxf(.1, maxf(half_y * 2, half_x * 2 / (float(WIDTH) / HEIGHT)) * 1.13)
	camera.current = true
	get_viewport().msaa_3d = Viewport.MSAA_4X
	report["presentation"] = {"viewport": [WIDTH, HEIGHT], "camera_position_metres": vector_values(camera.position),
		"camera_target_metres": vector_values(target), "camera_projection": "orthographic", "camera_vertical_span_metres": camera.size,
		"view": "Three-quarter front; Blender front -Y exports to Godot +Z", "sky": "Original procedural daylight sky",
		"tone_mapper_requested": "LINEAR", "ambient_sky_energy": .2,
		"tone_mapping_limit": "This GL Compatibility consumer does not validate Filmic response or Blender AgX parity; lighting is independently exposed for the actual captured frame.",
		"msaa_3d": "4x", "directional_shadow_mode": "ORTHOGONAL",
		"sun_rotation_degrees": [-48, -35, 0], "sun_energy": .55}


func capture_timeout() -> void:
	if finished:
		return
	check("capture_before_timeout", false, {"timeout_seconds_after_import": CAPTURE_TIMEOUT_SECONDS, "render_wait_frames": capture_frames})
	finish()


func finish() -> void:
	if finished:
		return
	if report.has("asset") and FileAccess.file_exists(asset_path):
		check("source_glb_unchanged_after_preview", FileAccess.get_sha256(asset_path) == str(report["asset"]["sha256"]))
	finished = true
	report["status"] = "PASS" if failures == 0 else "FAIL"
	report["failure_count"] = failures
	report["render_wait_frames"] = capture_frames
	if not report_path.is_empty():
		DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
		var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
		if file == null:
			push_error("ASSET PREVIEW: cannot write report " + report_path)
			failures += 1
			report["status"] = "FAIL"
		else:
			file.store_string(JSON.stringify(report, "\t") + "\n")
			file.flush()
			file.close()
	print("ASSET_REFINEMENT_PREVIEW " + report["status"] + " " + report_path)
	get_tree().quit(0 if failures == 0 else 1)


func run_preview() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--asset="):
			asset_path = argument.trim_prefix("--asset=")
		elif argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		elif argument.begins_with("--report="):
			report_path = argument.trim_prefix("--report=")
	report["engine_version"] = Engine.get_version_info()
	report["display_server"] = DisplayServer.get_name()
	report["video_adapter"] = RenderingServer.get_video_adapter_name()
	report["script"] = file_record("res://main.gd")
	report["project"] = file_record("res://project.godot")
	check("absolute_cli_paths", asset_path.is_absolute_path() and capture_path.is_absolute_path() and report_path.is_absolute_path())
	check("real_display_driver", DisplayServer.get_name() != "headless")
	check("asset_exists", FileAccess.file_exists(asset_path), asset_path)
	if failures > 0:
		finish()
		return
	report["asset"] = file_record(asset_path)
	var document: Dictionary = read_glb(asset_path)
	check("glb_2_document", not document.is_empty())
	if document.is_empty():
		finish()
		return
	var embedded: bool = true
	for image: Dictionary in document.get("images", []):
		embedded = embedded and image.has("bufferView") and not image.has("uri")
	for buffer: Dictionary in document.get("buffers", []):
		embedded = embedded and not buffer.has("uri")
	check("embedded_resources", embedded, {"images": document.get("images", []).size()})
	var required_extensions: Array = document.get("extensionsRequired", [])
	var required_supported: bool = true
	for extension: String in required_extensions:
		required_supported = required_supported and extension == "KHR_texture_transform"
	check("required_gltf_extensions_supported", required_supported, required_extensions)
	var state: GLTFState = GLTFState.new()
	var loader: GLTFDocument = GLTFDocument.new()
	var error: Error = loader.append_from_file(asset_path, state)
	check("runtime_gltf_append", error == OK, error)
	if error != OK:
		finish()
		return
	var scene: Node3D = loader.generate_scene(state) as Node3D
	check("runtime_scene_generated", scene != null)
	if scene == null:
		finish()
		return
	add_child(scene)
	collect_meshes(scene)
	var source_mesh_instances: int = 0
	for node: Dictionary in document.get("nodes", []):
		if node.has("mesh"):
			source_mesh_instances += 1
	check("all_mesh_instances_imported", source_mesh_instances > 0 and meshes.size() == source_mesh_instances,
		{"source": source_mesh_instances, "actual": meshes.size()})
	var bounds: AABB = bounds_of_meshes()
	report["bounds_metres"] = {"min": vector_values(bounds.position), "max": vector_values(bounds.end), "size": vector_values(bounds.size)}
	check("finite_nonzero_bounds_metres", bounds.position.is_finite() and bounds.size.is_finite() and bounds.size.x > .001 and bounds.size.y > .001 and bounds.size.z > .001)
	inspect_materials(document)
	add_presentation(bounds)
	# This watchdog covers the asynchronous render wait. A parent process must
	# separately bound synchronous GLB loading or a stalled native driver.
	get_tree().create_timer(CAPTURE_TIMEOUT_SECONDS).timeout.connect(capture_timeout)
	for index: int in range(10):
		await get_tree().process_frame
		capture_frames += 1
		if finished:
			return
	await RenderingServer.frame_post_draw
	if finished:
		return
	var texture: ViewportTexture = get_viewport().get_texture()
	var image: Image = texture.get_image() if texture != null else null
	check("real_framebuffer", image != null and not image.is_empty())
	if image != null and not image.is_empty():
		check("capture_dimensions", image.get_width() == WIDTH and image.get_height() == HEIGHT, [image.get_width(), image.get_height()])
		DirAccess.make_dir_recursive_absolute(capture_path.get_base_dir())
		var save_error: Error = image.save_png(capture_path)
		check("png_saved", save_error == OK, save_error)
		if save_error == OK:
			report["capture"] = file_record(capture_path)
	finish()
