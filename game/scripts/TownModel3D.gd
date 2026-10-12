extends Node3D
## A metric visual projection of the frozen town; never a second simulation.
## Cameras, lighting, actors, canonical navigation and input belong to the caller.
## Run tools/stage_town_assets.py before opening the game or exporting it.

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


func load_town() -> bool:
	if _loaded and is_instance_valid(imported):
		return true
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
	return true


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
		var building_id: String = str(extras.get("building_id", ""))
		if not building_id.is_empty() and label == building_id:
			building_nodes[building_id] = spatial
		if extras.has("room_id"):
			room_nodes[str(extras["room_id"])] = spatial
		if extras.has("floor_index"):
			if not floor_nodes.has(building_id):
				floor_nodes[building_id] = {}
			floor_nodes[building_id][int(extras["floor_index"])] = spatial
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
			if _is_ground_source(source):
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
		"selected_floor_index": selected_floor_index, "navigation_authority": "Sim canonical grid and portals"}


func _snapshot_visibility(node: Node) -> void:
	if node is Node3D:
		_default_visibility[node] = (node as Node3D).visible
	for child: Node in node.get_children():
		_snapshot_visibility(child)


func restore_exterior() -> void:
	for node: Node3D in _default_visibility:
		if is_instance_valid(node):
			node.visible = bool(_default_visibility[node])
	selected_building_id = ""
	selected_floor_index = -1


func reveal(space_id: String, floor_id: String, projection: Dictionary) -> void:
	restore_exterior()
	if space_id == "town" or floor_id == "outdoor":
		return
	var entry: Dictionary = _projection_entry(space_id, floor_id, projection)
	var ident: String = str(entry.get("building_id", entry.get("model_building_id", "")))
	var level: int = int(entry.get("level", entry.get("floor_index", entry.get("model_floor_index", 0))))
	if not building_nodes.has(ident) or not floor_nodes.get(ident, {}).has(level):
		return
	selected_building_id = ident
	selected_floor_index = level
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
	return true


func intersect_height_plane(origin: Vector3, direction: Vector3, height_y: float) -> Dictionary:
	if absf(direction.y) < 0.000001:
		return {}
	var distance: float = (height_y - origin.y) / direction.y
	if distance < 0:
		return {}
	return {"position": origin + direction * distance, "distance": distance}


func raycast_geometry(origin: Vector3, direction: Vector3, max_distance: float = 1000.0, scope: String = "ground", building_id: String = "") -> Dictionary:
	# Lazy TriangleMesh queries avoid thousands of physics bodies. Results are
	# visual picking evidence; Sim still decides whether a destination is legal.
	var candidates: Array[MeshInstance3D] = _ground_meshes if scope == "ground" else meshes
	var end: Vector3 = origin + direction.normalized() * max_distance
	var best: Dictionary = {}
	var nearest: float = max_distance
	for item: MeshInstance3D in candidates:
		if item.mesh == null or not item.is_visible_in_tree():
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
