extends Node3D
## A metric visual projection of the frozen town; never a second simulation.
## Cameras, lighting, actors, canonical navigation and input belong to the caller.
## Run tools/stage_town_assets.py before opening the game or exporting it.

const RayIndex = preload("res://scripts/TownRayIndex3D.gd")
const StaticBatch = preload("TownStaticBatch3D.gd")

const ASSET_ROOT: String = "res://assets/town3d/"
const MODEL_PATH: String = ASSET_ROOT + "living_town_game.glb"

var imported: Node3D
var manifest: Dictionary = {}
var catalog: Dictionary = {}
var stage_manifest: Dictionary = {}
var nodes_by_name: Dictionary = {}
var building_nodes: Dictionary = {}
var room_nodes: Dictionary = {}
var asset_nodes: Dictionary = {}
var floor_nodes: Dictionary = {}
var source_nodes: Dictionary = {}
var meshes: Array[MeshInstance3D] = []
var node_count: int = 0
var last_error: String = ""
var selected_building_id: String = ""
var selected_floor_index: int = -1

var _catalog_names: Dictionary = {}
var _default_visibility: Dictionary = {}
var _ground_meshes: Array[MeshInstance3D] = []
var _triangle_cache: Dictionary = {}
var _material_info: Dictionary = {}
var _load_msec: int = 0
var _load_method: String = ""
var _opened_doors: Array[String] = []
var _door_piece_count: int = 0
var _loaded: bool = false
var _raw_source_verified: bool = false
var _chunked: bool = false
var _building_meshes: Dictionary = {}
var _vegetation_batches: Array[MultiMeshInstance3D] = []
var _vegetation_info: Dictionary = {}
var _texture_cache: Dictionary = {}
var _shared_materials: Dictionary = {}
var _botanical_proxy_batches: Dictionary = {}
var _vegetation_overview: bool = false
var _ray_index: RefCounted
var _static_batches: RefCounted
var _static_batch_info: Dictionary = {"status": "NOT_PREPARED"}
# Explicit presentation request; never derives or changes a Sim address.
var _static_exterior_requested: bool = true
var _static_world: Node3D
var _static_sun: DirectionalLight3D
var _static_world_environment: WorldEnvironment
var _static_environment: Environment
var _static_watch_tree: SceneTree


func load_town() -> bool:
	if _loaded and is_instance_valid(imported):
		return true
	# Restore rendering proxies before their canonical source nodes are freed.
	_drop_static_batches("town_reload")
	# Release cached node references before freeing or replacing source geometry.
	_ray_index = null
	if is_instance_valid(imported):
		imported.free()
	imported = null
	nodes_by_name.clear()
	building_nodes.clear()
	room_nodes.clear()
	asset_nodes.clear()
	floor_nodes.clear()
	source_nodes.clear()
	meshes.clear()
	_building_meshes.clear()
	_vegetation_batches.clear()
	_texture_cache.clear()
	_shared_materials.clear()
	_botanical_proxy_batches.clear()
	_catalog_names.clear()
	_default_visibility.clear()
	_ground_meshes.clear()
	_triangle_cache.clear()
	_opened_doors.clear()
	_door_piece_count = 0
	node_count = 0
	last_error = ""
	var started: int = Time.get_ticks_msec()
	manifest = _read_json(ASSET_ROOT + "export_manifest.json")
	catalog = _read_json(ASSET_ROOT + "node_catalog.json")
	stage_manifest = _read_json(ASSET_ROOT + "stage_manifest.json")
	_chunked = stage_manifest.get("schema", "") == "living_town.game_stage.v2"
	if _chunked:
		return _load_chunked_town(started)
	if manifest.get("status", "") != "PASS" or catalog.is_empty() or stage_manifest.get("status", "") != "PASS":
		return _fail("Town assets are missing or invalid. Run tools/stage_town_assets.py.")
	var town: Dictionary = manifest.get("town", {})
	var expected_hash: String = str(town.get("sha256", ""))
	if expected_hash.is_empty() or catalog.get("source_glb_sha256", "") != expected_hash or stage_manifest.get("source_glb_sha256", "") != expected_hash:
		return _fail("Town GLB/catalog/stage provenance does not agree.")
	_raw_source_verified = FileAccess.file_exists(MODEL_PATH)
	if _raw_source_verified:
		if FileAccess.get_sha256(MODEL_PATH) != expected_hash:
			return _fail("Staged town GLB failed its SHA256 check.")
	elif not ResourceLoader.exists(MODEL_PATH, "PackedScene"):
		return _fail("Neither raw town GLB nor its imported scene is available.")
	for record: Dictionary in catalog.get("nodes", []):
		var label: String = str(record.get("name", ""))
		_catalog_names[label] = record
		_catalog_names[label.validate_node_name()] = record
	# Imported PackedScene is the fast path in a packaged/editor-imported game.
	# GLTFDocument makes a freshly staged source tree runnable before editor import.
	if ResourceLoader.exists(MODEL_PATH, "PackedScene"):
		var packed: PackedScene = ResourceLoader.load(MODEL_PATH, "PackedScene") as PackedScene
		if packed != null:
			imported = packed.instantiate() as Node3D
			_load_method = "imported PackedScene"
	if imported == null:
		var document: GLTFDocument = GLTFDocument.new()
		var state: GLTFState = GLTFState.new()
		var error: Error = document.append_from_file(MODEL_PATH, state)
		if error != OK:
			return _fail("Runtime GLTFDocument import failed: " + str(error))
		imported = document.generate_scene(state) as Node3D
		_load_method = "runtime GLTFDocument"
	if imported == null:
		return _fail("Town GLB did not create a Node3D scene.")
	add_child(imported)
	_index_tree(imported)
	_apply_portable_material_rules()
	_open_front_doors()
	_snapshot_visibility(imported)
	_load_msec = Time.get_ticks_msec() - started
	var expected: Dictionary = manifest.get("interior_inventory", {})
	if building_nodes.size() != int(manifest.get("building_count", 49)) or room_nodes.size() != int(expected.get("room_count", -1)) or asset_nodes.size() != int(expected.get("furnishing_count", -1)):
		return _fail("Imported town semantic inventory differs from the frozen export.")
	_loaded = true
	_ray_index = RayIndex.new()
	_ray_index.call("bind_model", self)
	_prepare_static_batches()
	return true


func _load_chunked_town(started: int) -> bool:
	if stage_manifest.get("status", "") != "PASS":
		return _fail("Upgraded town stage did not pass verification.")
	manifest = {"source_blend_sha256": stage_manifest.get("source_blend_sha256", ""), "building_count": stage_manifest.get("building_count", 0), "interior_inventory": stage_manifest.get("inventory", {})}
	catalog = {"source_glb_sha256": stage_manifest.get("source_asset_set_sha256", ""), "nodes": [], "material_rules": [], "front_doors": []}
	imported = Node3D.new()
	imported.name = "CompletePlayableTown"
	add_child(imported)
	var excluded: Dictionary = {}
	for original: String in stage_manifest.get("removed_baseline_object_names", []):
		excluded[original] = true
	_raw_source_verified = true
	for asset: Dictionary in stage_manifest.get("assets", []):
		var model_path: String = ASSET_ROOT + str(asset["file"])
		var catalog_path: String = ASSET_ROOT + str(asset["catalog"])
		if FileAccess.get_sha256(catalog_path) != str(asset["catalog_sha256"]):
			return _fail("Upgraded chunk catalog checksum differs: " + catalog_path)
		var chunk_catalog: Dictionary = _read_json(catalog_path)
		if chunk_catalog.get("source_glb_sha256", "") != asset.get("sha256", ""):
			return _fail("Upgraded chunk and semantic catalog disagree.")
		var raw: bool = FileAccess.file_exists(model_path)
		if raw and FileAccess.get_sha256(model_path) != str(asset["sha256"]):
			return _fail("Upgraded chunk checksum differs: " + model_path)
		_raw_source_verified = _raw_source_verified and raw
		var chunk: Node3D = null
		if ResourceLoader.exists(model_path, "PackedScene"):
			var packed: PackedScene = ResourceLoader.load(model_path, "PackedScene") as PackedScene
			if packed != null:
				chunk = packed.instantiate() as Node3D
		if chunk == null and raw:
			var document: GLTFDocument = GLTFDocument.new()
			var state: GLTFState = GLTFState.new()
			var error: Error = document.append_from_file(model_path, state)
			if error != OK:
				return _fail("Upgraded glTF import failed: " + str(error))
			chunk = document.generate_scene(state) as Node3D
		if chunk == null:
			return _fail("Upgraded town chunk is unavailable: " + model_path)
		_catalog_names.clear()
		for record: Dictionary in chunk_catalog.get("nodes", []):
			var label: String = str(record.get("name", ""))
			_catalog_names[label] = record
			_catalog_names[label.validate_node_name()] = record
		catalog["nodes"].append_array(chunk_catalog.get("nodes", []))
		catalog["material_rules"].append_array(chunk_catalog.get("material_rules", []))
		# Bind cache paths to the asset, independent of process-global duplicate-name counters.
		chunk.name = str(asset["file"]).get_file().get_basename().validate_node_name()
		imported.add_child(chunk)
		_index_tree(chunk)
		if bool(asset.get("baseline", false)):
			_hide_removed_sources(chunk, excluded)
	_apply_portable_material_rules()
	_batch_botanical_instances()
	_snapshot_visibility(imported)
	_load_msec = Time.get_ticks_msec() - started
	_load_method = "verified metric chunks in actual Main gameplay"
	var expected: Dictionary = stage_manifest.get("inventory", {})
	if building_nodes.size() != int(stage_manifest.get("building_count", 0)) or room_nodes.size() != int(expected.get("room_count", -1)) or asset_nodes.size() != int(expected.get("furnishing_count", -1)):
		return _fail("Upgraded town semantic inventory differs: " + str({"buildings": building_nodes.size(), "rooms": room_nodes.size(), "furnishings": asset_nodes.size(), "expected": expected}))
	_loaded = true
	_ray_index = RayIndex.new()
	_ray_index.call("bind_model", self)
	_prepare_static_batches()
	return true


func _hide_removed_sources(node: Node, excluded: Dictionary) -> void:
	if node is Node3D and excluded.has(str(node.get_meta("source_object", node.name))):
		(node as Node3D).visible = false
	for child: Node in node.get_children():
		_hide_removed_sources(child, excluded)


func _batch_botanical_instances() -> void:
	var groups: Dictionary = {}
	var instance_count: int = 0
	for item: MeshInstance3D in meshes:
		if item.mesh == null or not item.is_visible_in_tree() or not item.has_meta("botanical_instance_id"):
			continue
		var centre: Vector3 = item.global_position
		var cell: Vector2i = Vector2i(floori(centre.x / 64.0), floori(centre.z / 64.0))
		var key: String = str(item.mesh.get_instance_id()) + ":" + str(item.material_override.get_instance_id() if item.material_override != null else 0) + ":" + str(cell)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(item)
		instance_count += 1
	for key: String in groups:
		var members: Array = groups[key]
		var source: MeshInstance3D = members[0] as MeshInstance3D
		var batch: MultiMeshInstance3D = MultiMeshInstance3D.new()
		batch.name = "BotanicalCell_" + str(_vegetation_batches.size())
		batch.multimesh = MultiMesh.new()
		batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		batch.multimesh.mesh = source.mesh
		batch.material_override = source.material_override
		batch.multimesh.instance_count = members.size()
		batch.cast_shadow = source.cast_shadow
		batch.visibility_range_end = 420.0 if str(source.get_meta("vegetation_role", "tree")) == "tree" else 150.0
		batch.set_meta("base_visibility_end_m", batch.visibility_range_end)
		batch.set_meta("canopy", str(source.get_meta("vegetation_role", "tree")) == "tree")
		batch.visibility_range_end_margin = 30.0
		# Instances use world transforms under this identity root. Stable botanical
		# IDs remain in the source catalog and original hidden semantic nodes.
		imported.add_child(batch)
		batch.global_position = Vector3(floor(source.global_position.x / 64.0) * 64.0 + 32.0, 0, floor(source.global_position.z / 64.0) * 64.0 + 32.0)
		for index: int in range(members.size()):
			var member: MeshInstance3D = members[index] as MeshInstance3D
			batch.multimesh.set_instance_transform(index, batch.global_transform.affine_inverse() * member.global_transform)
			_botanical_proxy_batches[member] = batch
			member.visible = false
		_vegetation_batches.append(batch)
	_vegetation_info = {"source_mesh_instances": instance_count, "spatial_multimesh_batches": _vegetation_batches.size(), "spatial_cell_m": 64, "tree_visibility_distance_m": 420, "understory_visibility_distance_m": 150, "stable_ids_preserved_in_catalog": true}


func set_view_scope(orthographic_size_m: float) -> void:
	var overview: bool = orthographic_size_m > 190.0
	if overview == _vegetation_overview:
		return
	_vegetation_overview = overview
	for batch: MultiMeshInstance3D in _vegetation_batches:
		batch.visibility_range_end = 0.0 if overview and bool(batch.get_meta("canopy", true)) else float(batch.get_meta("base_visibility_end_m", 420.0))
	_vegetation_info["overview_canopy_visible"] = overview


func _fail(message: String) -> bool:
	last_error = message
	push_error("TownModel3D: " + message)
	return false


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}


func _index_tree(node: Node) -> void:
	if node is Node3D:
		var spatial: Node3D = node as Node3D
		var label: String = str(node.name)
		nodes_by_name[label] = spatial
		node_count += 1
		var record: Dictionary = _catalog_names.get(label, {})
		var extras: Dictionary = record.get("extras", {})
		spatial.set_meta("town_extras", extras)
		spatial.set_meta("town_vertex_color", bool(record.get("vertex_color", false)))
		for key: String in extras:
			spatial.set_meta(key, extras[key])
		var building_id: String = str(extras.get("building_id", extras.get("interior_building_id", extras.get("reserve_building_id", ""))))
		if not building_id.is_empty() and (label == building_id or (_chunked and not building_nodes.has(building_id))):
			building_nodes[building_id] = spatial
		if extras.has("room_id"):
			room_nodes[str(extras["room_id"])] = spatial
		if extras.has("floor_index") or extras.has("model_floor_index"):
			if not floor_nodes.has(building_id):
				floor_nodes[building_id] = {}
			floor_nodes[building_id][int(extras.get("model_floor_index", extras.get("floor_index", 0)))] = spatial
		var assembly_id: String = str(extras.get("interior_asset_id", ""))
		if not assembly_id.is_empty():
			if not asset_nodes.has(assembly_id):
				asset_nodes[assembly_id] = []
			asset_nodes[assembly_id].append(spatial)
		var source: String = str(extras.get("source_object", ""))
		if not source.is_empty():
			source_nodes[source] = spatial
		if node is MeshInstance3D:
			var mesh_node: MeshInstance3D = node as MeshInstance3D
			meshes.append(mesh_node)
			if not building_id.is_empty():
				if not _building_meshes.has(building_id):
					_building_meshes[building_id] = []
				_building_meshes[building_id].append(mesh_node)
			var role: String = str(extras.get("semantic_role", extras.get("reserve_role", "")))
			if _is_ground_source(source) or role in ["replacement_terrain", "terrain", "graded_street", "graded_road_surface", "road_paving", "trail_surface", "stair_tread", "bridge_deck"] or str(extras.get("landscape_role", "")) == "ground":
				_ground_meshes.append(mesh_node)
	for child: Node in node.get_children():
		_index_tree(child)


func _is_ground_source(source: String) -> bool:
	if source.begins_with("Atlantic_Terrain_"):
		return not (source.ends_with("Sea") or source.ends_with("Foam") or source.ends_with("PondWater"))
	return source.begins_with("Connected_Streets_and_Pavements_") or source.begins_with("Reference_Garden_Paths_") or source.begins_with("Graded_Threshold_Approach_Steps_")


func _apply_portable_material_rules() -> void:
	var rules: Dictionary = {}
	for rule: Dictionary in catalog.get("material_rules", []):
		rules[str(rule.get("name", ""))] = rule
	var unique: Dictionary = {}
	var normals: int = 0
	var textured: int = 0
	var alpha: int = 0
	for item: MeshInstance3D in meshes:
		if item.mesh == null:
			continue
		for surface: int in range(item.mesh.get_surface_count()):
			var material: Material = item.get_active_material(surface)
			if not material is BaseMaterial3D:
				continue
			var pbr: BaseMaterial3D = material as BaseMaterial3D
			if _chunked:
				# All chunks are exported from one native Blender material namespace.
				# Reuse the exact authored material identity so embedded copies do not
				# multiply the same PBR texture set across every district on the GPU.
				if not pbr.resource_name.is_empty() and _shared_materials.has(pbr.resource_name):
					pbr = _shared_materials[pbr.resource_name] as BaseMaterial3D
					if item.mesh is ArrayMesh:
						(item.mesh as ArrayMesh).surface_set_material(surface, pbr)
					else:
						item.set_surface_override_material(surface, pbr)
				elif not pbr.resource_name.is_empty():
					_shared_materials[pbr.resource_name] = pbr
				pbr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				pbr.albedo_texture = _mipmapped_texture(pbr.albedo_texture)
				pbr.normal_texture = _mipmapped_texture(pbr.normal_texture)
				pbr.roughness_texture = _mipmapped_texture(pbr.roughness_texture)
				pbr.metallic_texture = _mipmapped_texture(pbr.metallic_texture)
			# Preserve COLOR_0's original multiplication with textured grass albedo.
			if bool(item.get_meta("town_vertex_color", false)):
				pbr.vertex_color_use_as_albedo = true
			var rule: Dictionary = rules.get(pbr.resource_name, {})
			if rule.get("alpha_mode", "") == "BLEND":
				pbr.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				var factor: Array = rule.get("base_color_factor", [1, 1, 1, 1])
				pbr.albedo_color.a = float(factor[3])
			if unique.has(pbr.get_instance_id()):
				continue
			unique[pbr.get_instance_id()] = true
			if pbr.normal_enabled and pbr.normal_texture != null:
				normals += 1
			if pbr.albedo_texture != null:
				textured += 1
			if pbr.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
				alpha += 1
	_material_info = {"unique_materials": unique.size(), "normal_materials": normals, "textured_materials": textured, "alpha_blend_materials": alpha}


func _mipmapped_texture(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var key: int = texture.get_instance_id()
	if _texture_cache.has(key):
		return _texture_cache[key] as Texture2D
	var pixels: Image = texture.get_image()
	if pixels == null or pixels.has_mipmaps():
		_texture_cache[key] = texture
		return texture
	pixels = pixels.duplicate() as Image
	if pixels.is_compressed():
		pixels.decompress()
	pixels.generate_mipmaps()
	var result: ImageTexture = ImageTexture.create_from_image(pixels)
	_texture_cache[key] = result
	return result


func get_building(building_id: String) -> Node3D:
	return building_nodes.get(building_id) as Node3D


func get_room(room_id: String) -> Node3D:
	return room_nodes.get(room_id) as Node3D


func get_asset_nodes(asset_id: String) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node: Node3D in asset_nodes.get(asset_id, []):
		result.append(node)
	return result


func get_info() -> Dictionary:
	var floor_count: int = 0
	for building: String in floor_nodes:
		floor_count += (floor_nodes[building] as Dictionary).size()
	return {"loaded": _loaded, "last_error": last_error, "node_count": node_count,
		"source_catalog_node_count": (catalog.get("nodes", []) as Array).size(), "mesh_count": meshes.size(),
		"building_count": building_nodes.size(), "floor_count": floor_count, "room_count": room_nodes.size(),
		"furnishing_count": asset_nodes.size(), "materials": _material_info, "load_msec": _load_msec,
		"load_method": _load_method, "raw_source_sha256_verified": _raw_source_verified,
		"source_verification": "raw GLB SHA256" if _raw_source_verified else "imported PCK scene; externally hash-bound export",
		"source_blend_sha256": manifest.get("source_blend_sha256", ""),
		"source_glb_sha256": catalog.get("source_glb_sha256", ""), "opened_front_doors": _opened_doors,
		"runtime_door_mesh_pieces": _door_piece_count, "selected_building_id": selected_building_id,
		"selected_floor_index": selected_floor_index, "chunked_whole_town": _chunked,
		"source_asset_set_sha256": stage_manifest.get("source_asset_set_sha256", ""), "vegetation": _vegetation_info,
		"static_render_batches": _static_batch_info,
		"navigation_authority": "Sim canonical grid and portals"}


func _snapshot_visibility(node: Node) -> void:
	if node is Node3D:
		_default_visibility[node] = (node as Node3D).visible
	for child: Node in node.get_children():
		_snapshot_visibility(child)


func restore_exterior() -> void:
	_suspend_static_batches("before_restore_exterior")
	_static_exterior_requested = true
	_restore_source_visibility()
	_sync_static_batch_visibility("restore_exterior")


func _restore_source_visibility() -> void:
	for candidate: Variant in _default_visibility:
		if is_instance_valid(candidate):
			var node: Node3D = candidate as Node3D
			node.visible = bool(_default_visibility[node])
	selected_building_id = ""
	selected_floor_index = -1


func reveal(space_id: String, floor_id: String, projection: Dictionary) -> void:
	# Disable BEFORE changing any canonical source flag, including early returns.
	_suspend_static_batches("before_reveal")
	_static_exterior_requested = space_id == "town" and floor_id == "outdoor"
	_apply_source_reveal(space_id, floor_id, projection)
	_sync_static_batch_visibility("reveal")


func _apply_source_reveal(space_id: String, floor_id: String, projection: Dictionary) -> void:
	_restore_source_visibility()
	if space_id == "town" or floor_id == "outdoor":
		return
	var entry: Dictionary = _projection_entry(space_id, floor_id, projection)
	var ident: String = str(entry.get("building_id", entry.get("model_building_id", "")))
	var level: int = int(entry.get("level", entry.get("floor_index", entry.get("model_floor_index", 0))))
	if not building_nodes.has(ident) or not floor_nodes.get(ident, {}).has(level):
		return
	selected_building_id = ident
	selected_floor_index = level
	if _chunked:
		for mesh: MeshInstance3D in _building_meshes.get(ident, []):
			var shared: Variant = mesh.get_meta("shared_building_ids", [])
			if shared is Array and shared.size() > 1:
				# One native party-wall mesh can enclose two real buildings. Keep
				# that shared shell when revealing either owner's active interior.
				mesh.visible = bool(_default_visibility.get(mesh, true))
				continue
			var role: String = str(mesh.get_meta("presentation_layer", mesh.get_meta("reserve_cover_role", "structure")))
			var mesh_level: int = int(mesh.get_meta("model_floor_index", mesh.get_meta("floor_index", -1)))
			if role in ["roof", "front", "Roof", "FrontCover"] or (mesh_level > level) or (role in ["upper", "UpperCover"] and mesh_level < 0):
				mesh.visible = false
			elif mesh_level >= 0:
				mesh.visible = true
		return
	_set_cover(ident, "Roof", false)
	_set_cover(ident, "FrontCover", false)
	var upper: Node3D = nodes_by_name.get(ident + "__UpperCover") as Node3D
	if upper != null:
		# UpperCover owns the upper rooms themselves. Hide its envelope children,
		# rather than its ancestor, whenever an upper floor is the active plane.
		upper.visible = level > 0
		if level > 0:
			for child: Node in upper.get_children():
				if child is Node3D:
					(child as Node3D).visible = child.has_meta("floor_index") and int(child.get_meta("floor_index")) <= level
	var levels: Dictionary = floor_nodes.get(ident, {})
	for index: int in levels:
		var floor_node: Node3D = levels[index] as Node3D
		floor_node.visible = index <= level
		if index == level:
			var ancestor: Node = floor_node.get_parent()
			while ancestor != null and ancestor != get_building(ident):
				if ancestor is Node3D:
					(ancestor as Node3D).visible = true
				ancestor = ancestor.get_parent()


func _projection_entry(space_id: String, floor_id: String, projection: Dictionary) -> Dictionary:
	if projection.has("building_id") or projection.has("model_building_id"):
		return projection
	var planes: Dictionary = projection.get("planes", projection)
	for key: String in [space_id + "/" + floor_id, space_id + ":" + floor_id]:
		if planes.get(key) is Dictionary:
			return planes[key]
	var spaces: Dictionary = projection.get("spaces", {})
	var space: Dictionary = spaces.get(space_id, projection.get(space_id, {}))
	var floors: Dictionary = space.get("floors", space)
	var floor: Dictionary = floors.get(floor_id, {})
	if not floor.is_empty() and not floor.has("building_id") and space.has("building_id"):
		floor = floor.duplicate()
		floor["building_id"] = space["building_id"]
	return floor


func _set_cover(ident: String, role: String, state: bool) -> void:
	var cover: Node3D = nodes_by_name.get(ident + "__" + role) as Node3D
	if cover != null:
		cover.visible = state


func _open_front_doors() -> void:
	# The original leaf is batched by material with shutters and other facade
	# details. Split only its exact bounded triangles; retain all PBR attributes.
	# This creates a disposable open leaf in memory, without changing the GLB.
	for spec: Dictionary in catalog.get("front_doors", []):
		var ident: String = str(spec["building_id"])
		var building: Node3D = get_building(ident)
		if building == null:
			continue
		var pieces: int = 0
		for suffix: String in spec["material_suffixes"]:
			var source: String = str(spec["source_prefix"]) + suffix
			var mesh_node: MeshInstance3D = source_nodes.get(source) as MeshInstance3D
			if mesh_node != null and _split_open_leaf(mesh_node, building, spec):
				pieces += 1
		if pieces > 0:
			_opened_doors.append(ident)
			_door_piece_count += pieces


func _split_open_leaf(item: MeshInstance3D, building: Node3D, spec: Dictionary) -> bool:
	if item.mesh == null:
		return false
	var keep_mesh: ArrayMesh = ArrayMesh.new()
	var leaf_mesh: ArrayMesh = ArrayMesh.new()
	var half: float = float(spec["body_width_m"]) / 2.0 + 0.002
	var center_x: float = float(spec["center_x_m"])
	var front_z: float = float(spec["front_z_m"])
	var clip: AABB = AABB(Vector3(center_x - half, -0.002, front_z - 0.071), Vector3(half * 2, float(spec["body_height_m"]) + 0.004, 0.285))
	var local_transform: Transform3D = building.global_transform.affine_inverse() * item.global_transform
	for surface: int in range(item.mesh.get_surface_count()):
		var arrays: Array = item.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for vertex: int in range(vertices.size()):
				indices.append(vertex)
		var kept: PackedInt32Array = PackedInt32Array()
		var moved: PackedInt32Array = PackedInt32Array()
		for triangle: int in range(0, indices.size(), 3):
			var is_leaf: bool = true
			for corner: int in range(3):
				is_leaf = is_leaf and clip.has_point(local_transform * vertices[indices[triangle + corner]])
			for corner: int in range(3):
				if is_leaf:
					moved.append(indices[triangle + corner])
				else:
					kept.append(indices[triangle + corner])
		if not kept.is_empty():
			var kept_arrays: Array = arrays.duplicate()
			kept_arrays[Mesh.ARRAY_INDEX] = kept
			keep_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, kept_arrays)
			keep_mesh.surface_set_material(keep_mesh.get_surface_count() - 1, item.get_active_material(surface))
		if not moved.is_empty():
			var moved_arrays: Array = arrays.duplicate()
			moved_arrays[Mesh.ARRAY_INDEX] = moved
			leaf_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, moved_arrays)
			leaf_mesh.surface_set_material(leaf_mesh.get_surface_count() - 1, item.get_active_material(surface))
	if leaf_mesh.get_surface_count() == 0:
		return false
	# Invalidate BEFORE the first canonical geometry write, without yielding.
	invalidate_geometry_queries("front_door_geometry_will_change")
	if keep_mesh.get_surface_count() > 0:
		item.mesh = keep_mesh
	else:
		item.visible = false
		item.mesh = null
	var leaf: MeshInstance3D = MeshInstance3D.new()
	leaf.name = str(item.name) + "__RuntimeOpenDoor"
	leaf.mesh = leaf_mesh
	var hinge: Vector3 = Vector3(center_x - 0.48, 0, front_z + 0.015)
	var rotation: Basis = Basis(Vector3.UP, deg_to_rad(float(spec["open_degrees"])))
	var turn: Transform3D = Transform3D(rotation, hinge - rotation * hinge)
	item.get_parent().add_child(leaf)
	leaf.global_transform = building.global_transform * turn * local_transform
	leaf.set_meta("building_id", str(spec["building_id"]))
	leaf.set_meta("asset_role", "runtime_open_front_door")
	leaf.set_meta("visual_only", true)
	meshes.append(leaf)
	node_count += 1
	invalidate_geometry_queries("front_door_geometry_changed")
	return true


func intersect_height_plane(origin: Vector3, direction: Vector3, height_y: float) -> Dictionary:
	if absf(direction.y) < 0.000001:
		return {}
	var distance: float = (height_y - origin.y) / direction.y
	if distance < 0:
		return {}
	return {"position": origin + direction * distance, "distance": distance}


## Call BEFORE a static mesh/ancestor transform, geometry, source membership,
## material or grouping-flag edit, and again after it. No await between the pair.
## The first call restores original rendering; the second invalidates final bounds.
## Visibility wrappers synchronize separately; botanical range gates remain live.
func invalidate_geometry_queries(reason: String = "static_geometry_changed") -> void:
	_drop_static_batches("source_invalidated: " + reason)
	_triangle_cache.clear()
	if _ray_index != null:
		_ray_index.call("invalidate", reason)


func raycast_geometry(origin: Vector3, direction: Vector3, max_distance: float = 1000.0, scope: String = "ground", building_id: String = "") -> Dictionary:
	if _ray_index != null:
		return _ray_index.call("raycast_geometry", origin, direction, max_distance, scope, building_id)
	return _raycast_geometry_scan(origin, direction, max_distance, scope, building_id)


func _raycast_geometry_scan(origin: Vector3, direction: Vector3, max_distance: float = 1000.0, scope: String = "ground", building_id: String = "") -> Dictionary:
	# Lazy TriangleMesh queries avoid thousands of physics bodies. Results are
	# visual picking evidence; Sim still decides whether a destination is legal.
	var candidates: Array[MeshInstance3D] = _ground_meshes if scope == "ground" else meshes
	var end: Vector3 = origin + direction.normalized() * max_distance
	var best: Dictionary = {}
	var nearest: float = max_distance
	for item: MeshInstance3D in candidates:
		if item.mesh == null:
			continue
		if not item.is_visible_in_tree():
			# Hidden source nodes remain exact static ray proxies for the visible
			# MultiMesh canopy, so batching cannot remove resident occlusion cues.
			var batch: MultiMeshInstance3D = _botanical_proxy_batches.get(item) as MultiMeshInstance3D
			if batch == null or not batch.is_visible_in_tree():
				continue
			if batch.visibility_range_end > 0.0 and origin.distance_to(batch.global_position) > batch.visibility_range_end + batch.visibility_range_end_margin:
				continue
		if not building_id.is_empty():
			var owner: String = _owner_id(item, "building_id")
			if owner.is_empty():
				owner = _owner_id(item, "interior_building_id")
			if owner != building_id:
				continue
		var bounds: AABB = item.global_transform * item.mesh.get_aabb()
		if bounds.intersects_segment(origin, end) == null:
			continue
		var key: int = item.mesh.get_instance_id()
		if not _triangle_cache.has(key):
			_triangle_cache[key] = item.mesh.generate_triangle_mesh()
		var triangles: TriangleMesh = _triangle_cache[key] as TriangleMesh
		if triangles == null:
			continue
		var hit: Dictionary = triangles.intersect_segment(item.to_local(origin), item.to_local(end))
		if hit.is_empty():
			continue
		var point: Vector3 = item.global_transform * Vector3(hit["position"])
		var distance: float = origin.distance_to(point)
		if distance < nearest:
			nearest = distance
			best = {"position": point, "distance": distance, "node": item,
				"normal": (item.global_transform.basis.inverse().transposed() * Vector3(hit["normal"])).normalized(),
				"building_id": _owner_id(item, "building_id"), "room_id": _owner_id(item, "room_id"),
				"interior_asset_id": _owner_id(item, "interior_asset_id")}
	return best


func _owner_id(node: Node, key: String) -> String:
	var current: Node = node
	while current != null and current != self:
		if current.has_meta(key):
			return str(current.get_meta(key))
		current = current.get_parent()
	return ""


func _prepare_static_batches() -> void:
	# Once after inventory/material/botanical/snapshot/ray setup. No per-frame
	# proxy scans, raw buffer readbacks, hashing or automatic rebuilding.
	_drop_static_batches("prepare")
	if not _chunked:
		_static_batch_info = {"status": "ORIGINAL_RENDERING", "reason": "legacy_model_not_in_proven_scope"}
		return
	if RenderingServer.get_current_rendering_method() != "mobile" or DisplayServer.get_name() == "headless":
		_static_batch_info = {"status": "ORIGINAL_RENDERING", "reason": "renderer_not_in_proven_scope"}
		return
	var started: int = Time.get_ticks_usec()
	_static_batches = StaticBatch.new()
	var cache_dir: String = ASSET_ROOT
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in range(arguments.size() - 1):
		if arguments[i] == "--town-static-cache-dir" and arguments[i + 1].is_absolute_path(): cache_dir = arguments[i + 1]
	var bound: Dictionary = _static_batches.call("cache_binding", self, 16.0)
	var prepared_result: Dictionary = {"ok": false, "error": bound.get("error", "Cache producer requested original builder")}
	if bound.get("ok", false) and not bool(get_meta("static_cache_build_only", false)):
		prepared_result = _static_batches.call("load_cache", self, cache_dir.path_join("static_render_cache.res"), cache_dir.path_join("static_render_cache.json"), bound.binding)
	var cache_attempt: Dictionary = {"hit": prepared_result.get("cache_hit", false), "reason": prepared_result.get("error", ""), "path": cache_dir}
	if not prepared_result.get("ok", false):
		_static_batches.call("dispose")
		_static_batches = StaticBatch.new()
		prepared_result = _static_batches.call("prepare", self, 16.0)
	_static_batch_info = {"status": "PREPARING", "preparation": prepared_result.get("info", {})}
	if not prepared_result.get("ok", false):
		_drop_static_batches("prepare_failed: " + str(prepared_result.get("error", "")))
		return
	var verified: Dictionary = _static_batches.call("validate_sources")
	if not verified.get("ok", false) and bool(cache_attempt.hit):
		cache_attempt = {"hit": false, "reason": "Cached full source validation failed; rebuilt: " + str(verified.get("error", "")), "path": cache_dir}
		_static_batches.call("dispose")
		_static_batches = StaticBatch.new()
		prepared_result = _static_batches.call("prepare", self, 16.0)
		verified = _static_batches.call("validate_sources") if prepared_result.get("ok", false) else {"ok": false, "error": prepared_result.get("error", "Builder fallback failed")}
	if not verified.get("ok", false):
		_drop_static_batches("source_validation_failed: " + str(verified.get("error", "")))
		return
	_static_batch_info = {"status": "PREPARED_ORIGINAL_RENDERING", "preparation": prepared_result.get("info", {}), "prepare_usec": Time.get_ticks_usec() - started, "source_buffers_and_registry_verified": true, "cache_attempt": cache_attempt, "source_verification_scope": "Current source/target decoded AND packed arrays plus registry validated by unchanged validate_sources; NT codec replay on full builder only, or exact producer proof bound to cached target/source bytes"}
	_sync_static_batch_visibility("load")


func _suspend_static_batches(reason: String) -> void:
	set_process(false)
	if _static_batches == null:
		return
	# Always hides every batch and restores every surviving source before return.
	var restored: Dictionary = _static_batches.call("set_enabled", false)
	if not restored.get("ok", false):
		_drop_static_batches("suspend_failed: " + reason + ": " + str(restored.get("error", "")))
		return
	_static_batch_info["status"] = "PREPARED_ORIGINAL_RENDERING"
	_static_batch_info["last_visibility_sync"] = reason


func _drop_static_batches(reason: String) -> void:
	set_process(false)
	if is_instance_valid(_static_watch_tree) and _static_watch_tree.node_added.is_connected(_on_static_context_node_added):
		_static_watch_tree.node_added.disconnect(_on_static_context_node_added)
	_static_watch_tree = null
	_static_world = null
	_static_sun = null
	_static_world_environment = null
	_static_environment = null
	if _static_batches == null:
		return
	var previous: Dictionary = _static_batch_info
	# Dispose remains unconditional even if a stale source reports an error.
	var restored: Dictionary = _static_batches.call("set_enabled", false)
	_static_batches.call("dispose")
	_static_batches = null
	_static_batch_info = {"status": "ORIGINAL_RENDERING", "reason": reason, "restore_result": restored, "last_preparation": previous.get("preparation", {})}
	# Remain original until a fresh load; no automatic rebuild on each frame.


func _collect_static_lighting_context(node: Node, rows: Dictionary) -> void:
	if node is Light3D:
		rows.lights.append(node)
	if node is WorldEnvironment:
		rows.environments.append(node)
	if node is LightmapGI or node is VoxelGI or node is ReflectionProbe or node.is_class("LightmapProbe"):
		rows.unsupported.append({"path": str(node.get_path()), "class": node.get_class()})
	for child: Node in node.get_children():
		_collect_static_lighting_context(child, rows)


func _inspect_static_batch_context() -> Dictionary:
	var world: Node3D = get_parent() as Node3D
	if world == null or not world.get_parent() is SubViewport or not (world.get_parent() as SubViewport).own_world_3d:
		return {"supported": false, "error": "Expected owned SubViewport world"}
	var rows: Dictionary = {"lights": [], "environments": [], "unsupported": []}
	_collect_static_lighting_context(world, rows)
	if rows.lights.size() != 1 or not rows.lights[0] is DirectionalLight3D or rows.environments.size() != 1 or not rows.unsupported.is_empty():
		return {"supported": false, "error": "Only one directional sun and one environment, without local lights or GI/probe nodes, are in proven scope", "light_count": rows.lights.size(), "environment_count": rows.environments.size(), "unsupported_nodes": rows.unsupported}
	var world_environment: WorldEnvironment = rows.environments[0] as WorldEnvironment
	var environment: Environment = world_environment.environment
	if environment == null or environment.sdfgi_enabled:
		return {"supported": false, "error": "Missing environment or unsupported SDFGI"}
	var flag_counts: Dictionary = {}
	var source_count: int = 0
	for group: Dictionary in _static_batches.get("groups"):
		for source: Dictionary in group.rows:
			var value: Variant = source.item
			if not is_instance_valid(value) or not value is MeshInstance3D:
				return {"supported": false, "error": "Original source unavailable"}
			var item: MeshInstance3D = value as MeshInstance3D
			if item.mesh == null or not item.mesh is ArrayMesh:
				return {"supported": false, "error": "Original source ArrayMesh unavailable"}
			var hint: Vector2i = (item.mesh as ArrayMesh).lightmap_size_hint
			var values: Array = [item.gi_mode, item.gi_lightmap_scale, item.gi_lightmap_texel_scale, str(hint)]
			var key: String = str(values)
			flag_counts[key] = int(flag_counts.get(key, 0)) + 1
			if item.gi_mode not in [GeometryInstance3D.GI_MODE_DISABLED, GeometryInstance3D.GI_MODE_STATIC] or item.gi_lightmap_scale != GeometryInstance3D.LIGHTMAP_SCALE_1X or item.gi_lightmap_texel_scale != 1.0 or hint != Vector2i.ZERO:
				return {"supported": false, "error": "Unsupported original source GI/lightmap flags", "source": str(item.get_path()), "flags": values}
			source_count += 1
	_static_world = world
	_static_sun = rows.lights[0] as DirectionalLight3D
	_static_world_environment = world_environment
	_static_environment = environment
	return {"supported": true, "light_count": 1, "non_directional_light_count": 0, "GI_or_probe_count": 0, "source_count": source_count, "source_GI_lightmap_flag_counts": flag_counts, "policy": "No local lights, GI/probes/SDFGI or nondefault lightmap flags; default STATIC alone is not a bake; direct RenderingServer lightmap assignment is outside this contract"}


func _sync_static_batch_visibility(reason: String) -> void:
	if _static_batches == null:
		return
	if not _static_exterior_requested:
		_static_batch_info["status"] = "PREPARED_ORIGINAL_RENDERING"
		_static_batch_info["last_visibility_sync"] = reason + ": interior_or_unknown_request"
		return
	for value: Variant in _default_visibility:
		if not is_instance_valid(value) or not value is Node3D or bool(value.visible) != bool(_default_visibility[value]):
			_drop_static_batches("nondefault_visibility: " + reason)
			return
	var context: Dictionary = _inspect_static_batch_context()
	if not context.get("supported", false):
		_drop_static_batches("unsupported_context: " + reason + ": " + str(context.get("error", "")))
		return
	var result: Dictionary = _static_batches.call("set_enabled", true)
	if not result.get("ok", false):
		_drop_static_batches("visibility_sync_failed: " + reason + ": " + str(result.get("error", "")))
		return
	_static_batch_info["status"] = "ACTIVE_EXTERIOR"
	_static_batch_info["last_visibility_sync"] = reason
	_static_batch_info["lighting_context"] = context
	_static_watch_tree = get_tree()
	if not _static_watch_tree.node_added.is_connected(_on_static_context_node_added):
		_static_watch_tree.node_added.connect(_on_static_context_node_added)
	process_priority = 40
	set_process(true)


func _on_static_context_node_added(node: Node) -> void:
	if not is_instance_valid(_static_world) or not _static_world.is_ancestor_of(node):
		return
	if node is Light3D or node is WorldEnvironment or node is LightmapGI or node is VoxelGI or node is ReflectionProbe or node.is_class("LightmapProbe"):
		_drop_static_batches("new_unsupported_lighting_context: " + str(node.get_class()))


func _process(_delta: float) -> void:
	# Constant-size guard only. Source transform/material/GI/grouping edits must
	# use invalidate_geometry_queries BEFORE/after the write, without yielding.
	if _static_batches == null or not bool(_static_batches.get("enabled")):
		return
	if not _static_exterior_requested or not selected_building_id.is_empty() or not is_instance_valid(_static_world) or get_parent() != _static_world or not _static_world.get_parent() is SubViewport or not (_static_world.get_parent() as SubViewport).own_world_3d or not is_instance_valid(_static_sun) or not _static_world.is_ancestor_of(_static_sun) or not is_instance_valid(_static_world_environment) or not _static_world.is_ancestor_of(_static_world_environment) or _static_world_environment.environment != _static_environment or _static_environment == null or _static_environment.sdfgi_enabled:
		_drop_static_batches("runtime_context_changed")


func _exit_tree() -> void:
	_drop_static_batches("model_exit_tree")
