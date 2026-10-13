extends Node3D
## Isolated visual asset consumer; it supplies no game navigation or physics.
## Runtime GLTFDocument loading avoids copying/importing a second large GLB.
const SOURCE_INDEX_META: StringName = &"_reserve_consumer_source_index"
const SOURCE_MESH_META: StringName = &"_reserve_consumer_source_mesh_index"

var report: Dictionary = {"schema": "living_town.reserve_consumer.v1", "checks": [], "images": []}
var asset_dir: String = "res://assets"
var native_manifest_path: String = "res://assets/town_manifest.json"
var report_path: String = "res://evidence/logical_report.json"
var capture_dir: String = ""
var manifest: Dictionary = {}
var native_manifest: Dictionary = {}
var document: Dictionary = {}
var imported: Node3D
var imported_state: GLTFState
var nodes_by_index: Dictionary = {}
var raw_by_name: Dictionary = {}
var raw_globals: Dictionary = {}
var meshes: Array[MeshInstance3D] = []
var failures: int = 0
var viewport: SubViewport
var camera: Camera3D
var started_msec: int = 0


func _ready() -> void:
	call_deferred("run_checks")


func check_that(label: String, passed: bool, detail: Variant = null) -> void:
	report["checks"].append({"name": label, "passed": passed, "detail": detail})
	if not passed:
		failures += 1
		push_error("RESERVE CONSUMER CHECK FAILED: " + label + " " + str(detail))


func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func file_record(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"path": path, "exists": false}
	var size_bytes: int = file.get_length()
	file.close()
	return {"path": path, "bytes": size_bytes, "sha256": FileAccess.get_sha256(path)}


func read_glb(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	if file.get_length() < 20:
		file.close()
		return {}
	var valid: bool = file.get_buffer(4).get_string_from_ascii() == "glTF"
	valid = valid and file.get_32() == 2 and file.get_32() == file.get_length()
	var chunk_length: int = file.get_32()
	valid = valid and file.get_32() == 0x4E4F534A and chunk_length > 1 and chunk_length <= file.get_length()-20
	if not valid:
		file.close()
		return {}
	var parsed: Variant = JSON.parse_string(file.get_buffer(chunk_length).get_string_from_utf8())
	file.close()
	return parsed if parsed is Dictionary else {}


func load_glb(path: String, retain_identity: bool = false) -> Node3D:
	var loader: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	var error: Error = loader.append_from_file(path, state)
	if error != OK:
		check_that("runtime_gltf_loader_" + path.get_file(), false, error)
		return null
	if retain_identity:
		# Explicit consumer-only stamps, not assumed automatic glTF extras.
		# Godot merges GLTFNode metadata into generated nodes and preserves it
		# when its runtime importer replaces ImporterMeshInstance3D nodes.
		var source_nodes: Array[GLTFNode] = state.get_nodes()
		for index: int in range(source_nodes.size()):
			source_nodes[index].set_meta(SOURCE_INDEX_META, index)
			source_nodes[index].set_meta(SOURCE_MESH_META, source_nodes[index].mesh)
	var scene: Node3D = loader.generate_scene(state) as Node3D
	if retain_identity:
		imported_state = state
	return scene


func all_meshes(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if root is MeshInstance3D and root.mesh != null:
		result.append(root)
	for child: Node in root.get_children():
		result.append_array(all_meshes(child))
	return result


func index_stamped_nodes(root: Node, errors: Array[String]) -> void:
	if root is Node3D and root.has_meta(SOURCE_INDEX_META):
		var index: int = int(root.get_meta(SOURCE_INDEX_META))
		if index < 0 or index >= document.get("nodes", []).size():
			errors.append("actual_node:source_index_outside_document")
		elif nodes_by_index.has(index):
			errors.append(str(index) + ":duplicate_source_index")
		else:
			nodes_by_index[index] = root
	elif root is MeshInstance3D:
		errors.append("actual_mesh:missing_source_index_stamp")
	for child: Node in root.get_children():
		index_stamped_nodes(child, errors)


func index_imported_identity() -> void:
	# Runtime conversion frees the original state mesh pointers. The explicit
	# pre-generation metadata stamps survive on the actual converted meshes.
	# No imported display name or stale get_scene_node pointer establishes ID.
	nodes_by_index.clear()
	var errors: Array[String] = []
	index_stamped_nodes(imported, errors)
	var renamed: Array[Dictionary] = []
	var seen_mesh_nodes: Dictionary = {}
	var mapped_mesh_count: int = 0
	var raw_mesh_count: int = 0
	var transform_max_error: float = 0.0
	for index: int in range(document.get("nodes", []).size()):
		var raw: Dictionary = document["nodes"][index]
		var node: Node3D = scene_node(index)
		if node == null:
			errors.append(str(index) + ":missing_actual_node")
			continue
		if not raw.has("mesh"):
			continue
		raw_mesh_count += 1
		if not node is MeshInstance3D or node.mesh == null:
			errors.append(str(index) + ":missing_mesh")
			continue
		mapped_mesh_count += 1
		var identity: int = node.get_instance_id()
		if seen_mesh_nodes.has(identity):
			errors.append(str(index) + ":duplicate_scene_identity")
		seen_mesh_nodes[identity] = true
		if int(node.get_meta(SOURCE_MESH_META, -1)) != int(raw["mesh"]):
			errors.append(str(index) + ":source_mesh_index_mismatch")
		if not raw_globals.has(index):
			errors.append(str(index) + ":missing_source_world_transform")
		else:
			transform_max_error = maxf(transform_max_error, transform_error(node.global_transform, raw_globals[index]))
		if node != imported and not imported.is_ancestor_of(node):
			errors.append(str(index) + ":outside_imported_scene")
		if str(node.name) != str(raw.get("name", "")) and renamed.size() < 12:
			renamed.append({"gltf_index": index, "source_name": raw.get("name", ""), "scene_name": str(node.name)})
	var info: Dictionary = {"method": "Explicit GLTFNode source-index metadata before generate_scene, preserved through runtime mesh conversion",
		"source_nodes": document.get("nodes", []).size(), "mapped_nodes": nodes_by_index.size(),
		"source_mesh_nodes": raw_mesh_count, "mapped_mesh_nodes": mapped_mesh_count,
		"unique_actual_mesh_nodes": seen_mesh_nodes.size(), "sanitized_name_examples": renamed,
		"maximum_mesh_world_transform_error": transform_max_error,
		"error_count": errors.size(), "errors": errors.slice(0, 12)}
	report["node_identity"] = info
	check_that("all_glb_mesh_indices_resolve_to_unique_actual_nodes", imported_state.get_nodes().size() == document.get("nodes", []).size()
		and nodes_by_index.size() == document.get("nodes", []).size() and raw_mesh_count > 0 and errors.is_empty()
		and mapped_mesh_count == raw_mesh_count and seen_mesh_nodes.size() == raw_mesh_count and transform_max_error < .025, info)


func scene_node(index: int) -> Node3D:
	return nodes_by_index.get(index) as Node3D


func find_node(label: String) -> Node3D:
	# A source collection name is only a convenience for its authoritative index.
	return scene_node(int(raw_by_name[label])) if raw_by_name.has(label) else null


func collection_node(source_name: String) -> Node3D:
	return find_node(source_name + "__Group")


func local_transform(raw: Dictionary) -> Transform3D:
	if raw.has("matrix"):
		var a: Array = raw["matrix"]
		return Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[4], a[5], a[6]),
			Vector3(a[8], a[9], a[10])), Vector3(a[12], a[13], a[14]))
	var t: Array = raw.get("translation", [0, 0, 0])
	var q: Array = raw.get("rotation", [0, 0, 0, 1])
	var s: Array = raw.get("scale", [1, 1, 1])
	var basis: Basis = Basis(Quaternion(q[0], q[1], q[2], q[3])) * Basis.from_scale(Vector3(s[0], s[1], s[2]))
	return Transform3D(basis, Vector3(t[0], t[1], t[2]))


func index_raw_transforms() -> void:
	var scenes: Array = document.get("scenes", [])
	if scenes.is_empty():
		return
	var scene_record: Dictionary = scenes[int(document.get("scene", 0))]
	var stack: Array = []
	for index: int in scene_record.get("nodes", []):
		stack.append({"index": index, "parent": Transform3D.IDENTITY})
	while not stack.is_empty():
		var item: Dictionary = stack.pop_back()
		var index: int = int(item["index"])
		var raw: Dictionary = document["nodes"][index]
		var parent: Transform3D = item["parent"]
		var transform: Transform3D = parent * local_transform(raw)
		raw_globals[index] = transform
		raw_by_name[str(raw.get("name", ""))] = index
		for child: int in raw.get("children", []):
			stack.append({"index": child, "parent": transform})


func transform_error(actual: Transform3D, expected: Transform3D) -> float:
	var error: float = actual.origin.distance_to(expected.origin)
	for axis: int in range(3):
		error = maxf(error, actual.basis[axis].distance_to(expected.basis[axis]))
	return error


func bounds_of(items: Array[MeshInstance3D]) -> Dictionary:
	if items.is_empty():
		return {}
	var low: Vector3 = Vector3(INF, INF, INF)
	var high: Vector3 = Vector3(-INF, -INF, -INF)
	for item: MeshInstance3D in items:
		var box: AABB = item.mesh.get_aabb()
		for corner: int in range(8):
			var p: Vector3 = item.global_transform * box.get_endpoint(corner)
			low = low.min(p)
			high = high.max(p)
	return {"min": [low.x, low.y, low.z], "max": [high.x, high.y, high.z], "size": [high.x-low.x, high.y-low.y, high.z-low.z]}


func bounds_error(actual: Dictionary, expected: Dictionary) -> float:
	if actual.is_empty() or expected.is_empty():
		return INF
	var error: float = 0
	for side: String in ["min", "max"]:
		for axis: int in range(3):
			error = maxf(error, absf(float(actual[side][axis])-float(expected[side][axis])))
	return error


func same_ids(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size():
		return false
	for key: String in expected:
		if not actual.has(key):
			return false
	return true


func check_portable_pbr(doc: Dictionary, label: String) -> void:
	var embedded: bool = true
	for image: Dictionary in doc.get("images", []):
		embedded = embedded and not image.has("uri") and image.has("bufferView")
	for buffer: Dictionary in doc.get("buffers", []):
		embedded = embedded and not buffer.has("uri")
	var core_pbr: bool = true
	for material: Dictionary in doc.get("materials", []):
		core_pbr = core_pbr and material.has("pbrMetallicRoughness")
	check_that(label + "_self_contained_pbr", embedded and core_pbr and doc.get("extensionsRequired", []).is_empty(),
		{"embedded_images": doc.get("images", []).size(), "materials": doc.get("materials", []).size(), "required_extensions": doc.get("extensionsRequired", [])})


func portable_material_rules(items: Array[MeshInstance3D], doc: Dictionary) -> Dictionary:
	# Same portable rules as TownModel3D: COLOR_0 multiplies albedo; core BLEND alpha stays transparent.
	var rules: Dictionary = {}
	for raw: Dictionary in doc.get("materials", []):
		rules[str(raw.get("name", ""))] = raw
	var unique: Dictionary = {}
	var normals: int = 0
	var textured: int = 0
	var alpha: int = 0
	var colored: int = 0
	var valid: bool = true
	for item: MeshInstance3D in items:
		for surface: int in range(item.mesh.get_surface_count()):
			var material: Material = item.get_active_material(surface)
			if not material is BaseMaterial3D:
				valid = false
				continue
			var pbr: BaseMaterial3D = material as BaseMaterial3D
			var arrays: Array = item.mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_COLOR] != null and not arrays[Mesh.ARRAY_COLOR].is_empty():
				pbr.vertex_color_use_as_albedo = true
				colored += 1
			var rule: Dictionary = rules.get(pbr.resource_name, {})
			if rule.get("alphaMode", "") == "BLEND":
				pbr.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				var factor: Array = rule.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])
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
	return {"all_base_material_3d": valid, "unique_materials": unique.size(), "normal_materials": normals,
		"textured_materials": textured, "alpha_blend_materials": alpha, "vertex_color_surfaces": colored,
		"consumer_rules": ["COLOR_0 multiplies source albedo", "Source alphaMode BLEND preserved"]}


func check_inventory() -> void:
	var expected_buildings: Dictionary = {}
	var expected_rooms: Dictionary = {}
	var expected_assets: Dictionary = {}
	var amenities: Dictionary = native_manifest.get("reserve_amenities", {})
	for building: Dictionary in amenities.get("buildings", []):
		expected_buildings[str(building["id"])] = true
		for room: Dictionary in building.get("rooms", []):
			expected_rooms[str(room["id"])] = true
		for asset: Dictionary in building.get("assets", []):
			expected_assets[str(asset["id"])] = true
	var actual_buildings: Dictionary = {}
	var actual_rooms: Dictionary = {}
	var actual_assets: Dictionary = {}
	var namespace_clean: bool = true
	for raw: Dictionary in document.get("nodes", []):
		var extras: Dictionary = raw.get("extras", {})
		if extras.get("reserve_role", "") == "building":
			actual_buildings[str(extras.get("reserve_building_id", ""))] = true
		if extras.has("reserve_room_id"):
			actual_rooms[str(extras["reserve_room_id"])] = true
		if extras.get("reserve_role", "") == "furnishing":
			actual_assets[str(extras.get("reserve_asset_id", ""))] = true
		if extras.has("reserve_building_id"):
			for forbidden: String in ["room_id", "floor_index", "interior_asset_id", "interior_room_id", "interior_building_id"]:
				namespace_clean = namespace_clean and not extras.has(forbidden)
	check_that("native_reserve_inventory_is_explicit", not expected_buildings.is_empty() and not expected_rooms.is_empty() and not expected_assets.is_empty(),
		{"buildings": expected_buildings.size(), "rooms": expected_rooms.size(), "furnishings": expected_assets.size()})
	check_that("reserve_building_ids_match_native", same_ids(actual_buildings, expected_buildings), {"actual": actual_buildings.size(), "native": expected_buildings.size()})
	check_that("reserve_room_ids_match_native", same_ids(actual_rooms, expected_rooms), {"actual": actual_rooms.size(), "native": expected_rooms.size()})
	check_that("reserve_furnishing_ids_match_native", same_ids(actual_assets, expected_assets), {"actual": actual_assets.size(), "native": expected_assets.size()})
	check_that("reserve_metadata_does_not_pollute_core_inventory", namespace_clean)
	report["reserve_inventory"] = {"buildings": actual_buildings.size(), "rooms": actual_rooms.size(), "furnishings": actual_assets.size()}


func check_building_hierarchy() -> void:
	var root: Node3D = find_node("NaturalReserve")
	var top: Node3D = collection_node("07_Reserve_Amenities")
	check_that("reserve_top_level_hierarchy_present", root != null and top != null and root.is_ancestor_of(top))
	var names_ok: bool = true
	var placement_error: float = 0
	var ownership_ok: bool = true
	var floor_surface_error: float = 0
	var missing_floor_surfaces: Array[String] = []
	for item: Dictionary in native_manifest.get("reserve_amenities", {}).get("buildings", []):
		var building: Node3D = collection_node(str(item["root_collection"]))
		var roof: Node3D = collection_node(str(item["roof_collection"]))
		var front: Node3D = collection_node(str(item["front_cover_collection"]))
		var interior: Node3D = collection_node(str(item["interior_collection"]))
		names_ok = names_ok and building != null and roof != null and front != null and interior != null
		if building == null or roof == null or front == null or interior == null:
			continue
		ownership_ok = ownership_ok and building.is_ancestor_of(roof) and building.is_ancestor_of(front) and building.is_ancestor_of(interior)
		ownership_ok = ownership_ok and not all_meshes(roof).is_empty() and not all_meshes(front).is_empty() and not all_meshes(interior).is_empty()
		var center: Array = item["center"]
		var expected: Transform3D = Transform3D(Basis(Vector3.UP, deg_to_rad(float(item["yaw_degrees"]))),
			Vector3(float(center[0]), float(item["pad_level_m"]), -float(center[1])))
		placement_error = maxf(placement_error, transform_error(building.global_transform, expected))
		for room: Dictionary in item["rooms"]:
			var room_node: Node3D = collection_node(str(room["id"]))
			ownership_ok = ownership_ok and room_node != null and interior.is_ancestor_of(room_node)
			if room_node != null:
				var floor_items: Array[MeshInstance3D] = []
				for mesh: MeshInstance3D in all_meshes(room_node):
					if "_FloorFinish_" in str(mesh.name):
						floor_items.append(mesh)
				var floor_bounds: Dictionary = bounds_of(floor_items)
				if floor_bounds.is_empty():
					missing_floor_surfaces.append(str(room["id"]))
				else:
					floor_surface_error = maxf(floor_surface_error, absf(float(floor_bounds["max"][1])-float(item["finished_floor_z_m"])))
	check_that("all_reserve_cover_and_interior_nodes_present", names_ok)
	check_that("reserve_rooms_and_covers_owned_by_correct_building", ownership_ok)
	check_that("all_reserve_metric_placements_and_yaws_preserved", placement_error < 0.025, {"maximum_transform_error": placement_error})
	check_that("all_actual_room_floor_tops_match_finished_floor_datum", missing_floor_surfaces.is_empty() and floor_surface_error < .006,
		{"maximum_height_error_metres": floor_surface_error, "missing_room_floor_surfaces": missing_floor_surfaces})
	var fixture_errors: Array[String] = []
	var mapped_fixture_count: int = 0
	var raw_fixture_count: int = 0
	for index: int in range(document.get("nodes", []).size()):
		var raw: Dictionary = document["nodes"][index]
		var extras: Dictionary = raw.get("extras", {})
		if extras.get("reserve_role", "") != "furnishing":
			continue
		raw_fixture_count += 1
		var fixture: Node3D = scene_node(index)
		var owner_room: Node3D = collection_node(str(extras.get("reserve_room_id", "")))
		if not fixture is MeshInstance3D or owner_room == null or not owner_room.is_ancestor_of(fixture):
			fixture_errors.append(str(extras.get("reserve_asset_id", "")))
		else:
			mapped_fixture_count += 1
	check_that("actual_imported_furnishings_remain_under_owner_room_nodes", raw_fixture_count > 0 and fixture_errors.is_empty() and mapped_fixture_count == raw_fixture_count,
		{"errors": fixture_errors.slice(0, 16), "error_count": fixture_errors.size(), "source_mesh_components": raw_fixture_count, "mapped_owner_mesh_components": mapped_fixture_count})
	var core: Node3D = find_node("Buildings")
	check_that("existing_town_buildings_remain_separate", core != null and core.get_child_count() == int(manifest.get("building_count", -1)))


func check_trees_and_bridges() -> void:
	var tree_meshes: Dictionary = {}
	var imported_tree_meshes: Dictionary = {}
	var tree_groups: Dictionary = {}
	var tree_components: int = 0
	var mapped_tree_components: int = 0
	var resource_by_raw_mesh: Dictionary = {}
	var raw_mesh_by_resource: Dictionary = {}
	var sharing_errors: Array[String] = []
	var transform_max_error: float = 0
	var missing: Array[String] = []
	var bridge_meshes: Dictionary = {}
	for index: int in range(document.get("nodes", []).size()):
		var raw: Dictionary = document["nodes"][index]
		var extras: Dictionary = raw.get("extras", {})
		var item: Node3D = scene_node(index)
		if extras.get("reserve_role", "") == "tree":
			tree_components += 1
			tree_meshes[int(raw.get("mesh", -1))] = true
			var name_parts: PackedStringArray = str(raw.get("name", "")).split("_")
			if name_parts.size() >= 3:
				tree_groups[name_parts[2]] = true
			var tree: MeshInstance3D = item as MeshInstance3D
			if tree == null or tree.mesh == null:
				missing.append(str(raw.get("name", "")))
			else:
				mapped_tree_components += 1
				var raw_mesh: int = int(raw.get("mesh", -1))
				var resource_id: int = tree.mesh.get_rid().get_id()
				if resource_by_raw_mesh.has(raw_mesh) and resource_by_raw_mesh[raw_mesh] != resource_id:
					sharing_errors.append(str(index) + ":source_mesh_no_longer_shared")
				if raw_mesh_by_resource.has(resource_id) and raw_mesh_by_resource[resource_id] != raw_mesh:
					sharing_errors.append(str(index) + ":distinct_source_meshes_conflated")
				resource_by_raw_mesh[raw_mesh] = resource_id
				raw_mesh_by_resource[resource_id] = raw_mesh
				imported_tree_meshes[resource_id] = true
				transform_max_error = maxf(transform_max_error, transform_error(tree.global_transform, raw_globals.get(index, Transform3D.IDENTITY)))
		elif extras.get("reserve_role", "") == "bridge" and item is MeshInstance3D:
			var ident: String = str(extras.get("reserve_bridge_id", ""))
			if not bridge_meshes.has(ident):
				bridge_meshes[ident] = []
			bridge_meshes[ident].append(item)
	var expected_tree_count: int = int(native_manifest.get("reserve_environment", {}).get("tree_instances", -1))
	check_that("all_native_tree_instances_imported", missing.is_empty() and tree_groups.size() == expected_tree_count,
		{"native_tree_groups": expected_tree_count, "imported_tree_groups": tree_groups.size(), "mesh_components": tree_components, "missing": missing.slice(0, 12)})
	check_that("woodland_mesh_resources_remain_shared", mapped_tree_components == tree_components and tree_components > tree_meshes.size()
		and imported_tree_meshes.size() == tree_meshes.size() and sharing_errors.is_empty(),
		{"glb_unique_tree_meshes": tree_meshes.size(), "runtime_unique_tree_meshes": imported_tree_meshes.size(), "component_instances": tree_components, "sharing_errors": sharing_errors.slice(0, 12)})
	check_that("actual_tree_world_transforms_preserved", mapped_tree_components > 0 and mapped_tree_components == tree_components and transform_max_error < 0.025,
		{"maximum_transform_error": transform_max_error, "mapped_components": mapped_tree_components, "expected_components": tree_components})
	var bridge_errors: Array[String] = []
	for crossing: Dictionary in native_manifest.get("reserve_environment", {}).get("crossings", []):
		var ident: String = str(crossing["id"])
		var items: Array[MeshInstance3D] = []
		for entry: MeshInstance3D in bridge_meshes.get(ident, []):
			items.append(entry)
		var actual: Dictionary = bounds_of(items)
		if actual.is_empty():
			bridge_errors.append(ident + ":missing")
			continue
		for endpoint: Array in crossing["endpoints_m"]:
			var p: Vector3 = Vector3(endpoint[0], endpoint[2], -float(endpoint[1]))
			for axis: int in range(3):
				if p[axis] < float(actual["min"][axis])-.05 or p[axis] > float(actual["max"][axis])+.05:
					bridge_errors.append(ident + ":endpoint_outside_geometry")
	check_that("bridge_geometry_contains_authored_endpoints", bridge_errors.is_empty() and not bridge_meshes.is_empty(), bridge_errors)
	report["woodland"] = {"tree_instances": tree_groups.size(), "mesh_components": tree_components, "shared_mesh_resources": imported_tree_meshes.size()}


func exercise_local_controls() -> void:
	var buildings: Array = native_manifest.get("reserve_amenities", {}).get("buildings", [])
	var okay: bool = true
	for item: Dictionary in buildings:
		var roof: Node3D = collection_node(str(item["roof_collection"]))
		var front: Node3D = collection_node(str(item["front_cover_collection"]))
		var interior: Node3D = collection_node(str(item["interior_collection"]))
		if roof == null or front == null or interior == null:
			okay = false
			continue
		roof.visible = false
		front.visible = false
		await get_tree().process_frame
		okay = okay and not roof.is_visible_in_tree() and not front.is_visible_in_tree() and interior.is_visible_in_tree()
		for other: Dictionary in buildings:
			if other["id"] == item["id"]:
				continue
			var neighbor_roof: Node3D = collection_node(str(other["roof_collection"]))
			okay = okay and neighbor_roof != null and neighbor_roof.is_visible_in_tree()
		roof.visible = true
		front.visible = true
		await get_tree().process_frame
		okay = okay and roof.is_visible_in_tree() and front.is_visible_in_tree()
	check_that("multi_frame_all_amenity_local_covers_restore_and_preserve_neighbors", okay,
		{"buildings_exercised": buildings.size(), "process_frames": buildings.size()*2})


func check_prefabs() -> void:
	var requested: Array[String] = ["trailer", "convenience_store", "bathhouse", "food_truck"]
	var selected: Dictionary = {}
	for item: Dictionary in manifest.get("reserve_buildings", []):
		var kind: String = str(item.get("kind", ""))
		if kind in requested and not selected.has(kind):
			selected[kind] = item
	check_that("representative_prefab_kinds_listed", selected.size() == requested.size(), selected.keys())
	for kind: String in requested:
		if not selected.has(kind):
			continue
		var item: Dictionary = selected[kind]
		var record: Dictionary = item.get("standalone", {})
		var path: String = asset_dir.path_join(str(record.get("file", "")))
		var valid_hash: bool = FileAccess.file_exists(path) and FileAccess.get_sha256(path) == str(record.get("sha256", ""))
		check_that("prefab_"+kind+"_file_hash", valid_hash, file_record(path))
		if not valid_hash:
			continue
		var doc: Dictionary = read_glb(path)
		check_portable_pbr(doc, "prefab_"+kind)
		var instance: Node3D = load_glb(path)
		check_that("prefab_"+kind+"_loads", instance != null)
		if instance == null:
			continue
		add_child(instance)
		var actual: Dictionary = bounds_of(all_meshes(instance))
		var root: Node3D = instance.find_child(str(item["id"])+"__Group", true, false) as Node3D
		if str(instance.name) == str(item["id"])+"__Group":
			root = instance
		check_that("prefab_"+kind+"_local_origin_and_bounds", root != null and root.global_transform.is_equal_approx(Transform3D.IDENTITY)
			and bounds_error(actual, record.get("local_bounds_gltf_metres", {})) < 0.025,
			{"actual_bounds": actual, "tolerance_metres": 0.025})
		instance.queue_free()
		await get_tree().process_frame
	report["representative_prefabs"] = selected


func frame_scene() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1440, 1000)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	imported.reparent(viewport)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(.72, .80, .82)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(.85, .89, 1)
	environment.ambient_light_energy = .30
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1, .94, .83)
	sun.light_energy = .72
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 450
	viewport.add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = .05
	camera.far = 3000
	viewport.add_child(camera)
	camera.current = true


func capture(name: String) -> void:
	for frame: int in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var texture: ViewportTexture = viewport.get_texture()
	var image: Image = texture.get_image() if texture != null else null
	if image == null or image.is_empty():
		check_that("framebuffer_"+name, false, DisplayServer.get_name())
		return
	var sum_luma: float = 0
	var sum_square: float = 0
	var count: int = 0
	for y: int in range(0, image.get_height(), 16):
		for x: int in range(0, image.get_width(), 16):
			var color: Color = image.get_pixel(x, y)
			var luma: float = .2126*color.r+.7152*color.g+.0722*color.b
			sum_luma += luma
			sum_square += luma*luma
			count += 1
	var mean: float = sum_luma/count
	var deviation: float = sqrt(maxf(0, sum_square/count-mean*mean))
	check_that("framebuffer_"+name+"_not_blank", mean > .035 and mean < .95 and deviation > .025,
		{"mean_luminance": mean, "luminance_stddev": deviation})
	var path: String = capture_dir.path_join(name+".png")
	var error: Error = image.save_png(path)
	check_that("capture_"+name+"_written", error == OK, path)
	if error == OK:
		var record: Dictionary = file_record(path)
		record["name"] = name
		record["camera_transform"] = str(camera.global_transform)
		record["camera_orthographic_size_m"] = camera.size
		report["images"].append(record)


func capture_views() -> void:
	frame_scene()
	var outer: Array = native_manifest.get("reserve_environment", {}).get("bounds_xyxy_m", [-250, -190, 80, 150])
	var center: Vector3 = Vector3((float(outer[0])+float(outer[2]))/2, 5, -(float(outer[1])+float(outer[3]))/2)
	camera.position = center+Vector3(230, 260, 280)
	camera.size = maxf(float(outer[2])-float(outer[0]), float(outer[3])-float(outer[1]))*1.08
	camera.look_at(center)
	await capture("01_reserve_overview")
	var camp: Array[MeshInstance3D] = []
	var trailer_record: Dictionary = {}
	for item: Dictionary in native_manifest["reserve_amenities"]["buildings"]:
		if item["kind"] == "trailer":
			var node: Node3D = collection_node(str(item["root_collection"]))
			if node != null:
				camp.append_array(all_meshes(node))
			if trailer_record.is_empty():
				trailer_record = item
	var b: Dictionary = bounds_of(camp)
	if not b.is_empty():
		center = Vector3((float(b["min"][0])+float(b["max"][0]))/2, (float(b["min"][1])+float(b["max"][1]))/2,
			(float(b["min"][2])+float(b["max"][2]))/2)
		camera.position = center+Vector3(30, 52, 65)
		camera.size = maxf(float(b["size"][0])*1.25, 58)
		camera.look_at(center)
		await capture("02_trailer_park")
	if not trailer_record.is_empty():
		var trailer: Node3D = collection_node(str(trailer_record["root_collection"]))
		var roof: Node3D = collection_node(str(trailer_record["roof_collection"]))
		var front: Node3D = collection_node(str(trailer_record["front_cover_collection"]))
		roof.visible = false
		front.visible = false
		camera.position = trailer.to_global(Vector3(7, 10, 12))
		camera.size = 12.5
		camera.look_at(trailer.to_global(Vector3(0, 1.3, 0)))
		await capture("03_trailer_local_cutaway")
		roof.visible = true
		front.visible = true
	var crossings: Array = native_manifest.get("reserve_environment", {}).get("crossings", [])
	if not crossings.is_empty():
		var crossing: Dictionary = crossings[0]
		var a: Array = crossing["endpoints_m"][0]
		var z: Array = crossing["endpoints_m"][1]
		center = Vector3((float(a[0])+float(z[0]))/2, (float(a[2])+float(z[2]))/2,
			-(float(a[1])+float(z[1]))/2)
		camera.position = center+Vector3(30, 24, 34)
		camera.size = maxf(30, float(crossing["length_m"])*1.35)
		camera.look_at(center+Vector3(0, .8, 0))
		await capture("04_woodland_bridge")
	check_that("four_requested_capture_views_written", report["images"].size() == 4, report["images"].size())


func finish() -> void:
	report["status"] = "PASS" if failures == 0 else "FAIL"
	report["failure_count"] = failures
	report["check_count"] = report["checks"].size()
	report["engine_version"] = Engine.get_version_info()
	report["display_server"] = DisplayServer.get_name()
	report["rendering_method"] = RenderingServer.get_current_rendering_method()
	report["elapsed_msec"] = Time.get_ticks_msec()-started_msec
	report["generated_utc"] = Time.get_datetime_string_from_system(true)+"Z"
	report["visually_reviewed"] = false
	report["limitations"] = ["Visual mesh consumer only; no navigation or collision test", "No measured frame-rate or streaming claim",
		"Near/far trees are authored static mesh choices; no runtime LOD switch", "Screenshots need separate actual-image review"]
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write report: "+report_path)
		failures += 1
	else:
		file.store_string(JSON.stringify(report, "\t")+"\n")
		file.close()
	print("RESERVE_CONSUMER "+str(report["status"])+" checks="+str(report["check_count"])+" "+report_path)
	call_deferred("shutdown")


func shutdown() -> void:
	if is_instance_valid(imported):
		imported.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)


func run_checks() -> void:
	started_msec = Time.get_ticks_msec()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--asset-dir="):
			asset_dir = arg.trim_prefix("--asset-dir=")
		elif arg.begins_with("--native-manifest="):
			native_manifest_path = arg.trim_prefix("--native-manifest=")
		elif arg.begins_with("--report="):
			report_path = arg.trim_prefix("--report=")
		elif arg.begins_with("--capture="):
			capture_dir = arg.trim_prefix("--capture=")
	var export_path: String = asset_dir.path_join("export_manifest.json")
	manifest = read_json(export_path)
	native_manifest = read_json(native_manifest_path)
	report["inputs"] = {"export_manifest": file_record(export_path), "native_manifest": file_record(native_manifest_path),
		"consumer_script": file_record("res://smoke.gd"), "capture_requested": not capture_dir.is_empty()}
	check_that("export_manifest_complete", manifest.get("status", "") == "PASS" and manifest.get("reserve_building_count", 0) > 0)
	check_that("native_manifest_binding", FileAccess.file_exists(native_manifest_path) and FileAccess.get_sha256(native_manifest_path) == str(manifest.get("source_manifest_sha256", "")))
	check_that("native_and_export_amenity_reports_agree", not native_manifest.get("reserve_amenities", {}).is_empty()
		and native_manifest.get("reserve_amenities", {}) == manifest.get("reserve_amenities", {}))
	if failures > 0:
		finish()
		return
	var town: Dictionary = manifest.get("town_game", {})
	if town.is_empty():
		town = manifest.get("town", {})
	var path: String = asset_dir.path_join(str(town.get("file", "living_town_game.glb")))
	report["inputs"]["glb"] = file_record(path)
	report["source_blend_sha256"] = manifest.get("source_blend_sha256")
	check_that("full_glb_hash_matches_export", FileAccess.file_exists(path) and FileAccess.get_sha256(path) == str(town.get("sha256", "")))
	document = read_glb(path)
	check_that("glb_2_document_readable", not document.is_empty())
	if failures > 0:
		finish()
		return
	check_portable_pbr(document, "full_town")
	index_raw_transforms()
	var root_extras: Dictionary = {}
	if raw_by_name.has("LivingTown"):
		root_extras = document["nodes"][int(raw_by_name["LivingTown"])].get("extras", {})
	for field: String in manifest.get("portable_binding_fields", []):
		var expected: String = str(manifest.get("source_"+field, ""))
		report["source_"+field] = expected
		check_that("source_binding_"+field, expected.length() == 64 and str(root_extras.get(field, "")) == expected)
	check_inventory()
	var load_start: int = Time.get_ticks_msec()
	imported = load_glb(path, true)
	check_that("full_glb_creates_node3d_scene", imported != null)
	if imported == null:
		finish()
		return
	add_child(imported)
	await get_tree().process_frame
	report["runtime_load_msec"] = Time.get_ticks_msec()-load_start
	index_imported_identity()
	meshes = all_meshes(imported)
	var raw_mesh_instances: int = 0
	for node: Dictionary in document.get("nodes", []):
		if node.has("mesh"):
			raw_mesh_instances += 1
	check_that("all_glb_mesh_instances_present", meshes.size() == raw_mesh_instances,
		{"runtime_mesh_instances": meshes.size(), "glb_mesh_instances": raw_mesh_instances, "glb_unique_meshes": document.get("meshes", []).size()})
	check_that("full_world_metres_and_bounds_preserved", bounds_error(bounds_of(meshes), manifest.get("source_world_bounds_gltf_metres", {})) < .035,
		{"actual": bounds_of(meshes), "tolerance_metres": .035})
	var material_info: Dictionary = portable_material_rules(meshes, document)
	report["materials"] = material_info
	check_that("runtime_portable_materials_present", material_info["all_base_material_3d"] and int(material_info["unique_materials"]) == int(town.get("materials", -1)), material_info)
	check_that("runtime_pbr_normal_maps_present", int(material_info["normal_materials"]) >= int(town.get("normal_mapped_materials", 0)))
	check_that("runtime_alpha_blend_preserved", int(material_info["alpha_blend_materials"]) >= int(town.get("alpha_blend_materials", 0)))
	check_that("runtime_vertex_color_albedo_preserved", int(material_info["vertex_color_surfaces"]) >= int(town.get("vertex_color_primitives", 0)))
	check_building_hierarchy()
	check_trees_and_bridges()
	await exercise_local_controls()
	await check_prefabs()
	if not capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(capture_dir)
		if DisplayServer.get_name() == "headless":
			check_that("capture_requires_real_renderer", false, "Run without --headless for actual PNG captures")
		elif failures == 0:
			await capture_views()
	finish()
