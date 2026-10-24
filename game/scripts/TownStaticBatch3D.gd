extends RefCounted
## Diagnostic derivative: compressed or uncompressed source -> uncompressed target.
## XYZ/UV/color/topology remain exact to actual decoded source; N/T is a
## declared pinned oct16 representation conversion, NOT source bit identity.
## Original nodes/meshes/transforms stay authoritative for semantics and rays.

var town: Node3D
var groups: Array[Dictionary] = []
var proxies: Dictionary = {}
var enabled := false
var prepared := false
var error := ""
var skipped: Dictionary = {}
var info: Dictionary = {}
var _lod_cache: Dictionary = {}
var _animated_roots: Array[Node] = []
var _mesh_registry_hash := ""
var _ground_registry_hash := ""

const FLAGS := ["layers", "cast_shadow", "gi_mode", "ignore_occlusion_culling", "transparency", "extra_cull_margin", "lod_bias", "sorting_offset", "sorting_use_aabb_center"]
const IDENTITY_KEYS := ["building_id", "interior_building_id", "reserve_building_id", "shared_building_ids", "model_floor_index", "floor_index", "presentation_layer", "reserve_cover_role", "asset_role", "semantic_role", "reserve_role", "landscape_role"]

func _skip(reason: String) -> void:
	skipped[reason] = int(skipped.get(reason, 0)) + 1

func _digest(value: Variant) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(var_to_bytes(value))
	return h.finish().hex_encode()

func _bytes_digest(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()

# Compressed source bytes remain immutable. This representation conversion is
# not a raw N/T copy: only target N/T uses the pinned normal oct16 codec.
func _f32(value: float) -> float:
	return float(PackedFloat32Array([value])[0])

func _u16(value: float) -> int:
	return clampi(int(_f32(value * 65535.0)), 0, 65535)

func _raw_surface(mesh: ArrayMesh) -> Dictionary:
	var surfaces: Variant = mesh.get("_surfaces")
	if not surfaces is Array or surfaces.size() != 1 or not surfaces[0] is Dictionary:
		return {"skip": "unknown_serialized_surface"}
	var surface: Dictionary = surfaces[0]
	if typeof(surface.get("format")) != TYPE_INT or typeof(surface.get("vertex_count")) != TYPE_INT or not surface.get("vertex_data") is PackedByteArray:
		return {"skip": "unknown_surface_fields"}
	var format: int = int(surface.format)
	var count: int = int(surface.vertex_count)
	var attrs: int = Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TEX_UV2 | Mesh.ARRAY_FORMAT_INDEX
	var version_mask: int = RenderingServer.ARRAY_FLAG_FORMAT_VERSION_MASK << RenderingServer.ARRAY_FLAG_FORMAT_VERSION_SHIFT
	var allowed: int = attrs | version_mask | Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE | Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
	var required: int = Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_INDEX
	if (format & ~allowed) != 0 or (format & required) != required or (format & version_mask) != RenderingServer.ARRAY_FLAG_FORMAT_CURRENT_VERSION:
		return {"skip": "unknown_flags_version_or_missing_NT"}
	if count <= 0 or count != mesh.surface_get_array_len(0) or format != mesh.surface_get_format(0) or int(surface.get("primitive", -1)) != Mesh.PRIMITIVE_TRIANGLES:
		return {"skip": "surface_identity_mismatch"}
	for key in ["lods", "bone_aabbs", "blend_shapes", "skin_data"]:
		if surface.has(key) and not surface[key].is_empty():
			return {"skip": "unsupported_auxiliary_data"}
	var compressed: bool = (format & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0
	var v_stride: int = RenderingServer.mesh_surface_get_format_vertex_stride(format, count)
	var nt_stride: int = RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, count)
	var normal_offset: int = RenderingServer.mesh_surface_get_format_offset(format, count, Mesh.ARRAY_NORMAL)
	var tangent_offset: int = RenderingServer.mesh_surface_get_format_offset(format, count, Mesh.ARRAY_TANGENT)
	var bytes: PackedByteArray = surface.vertex_data
	if v_stride != (8 if compressed else 12) or nt_stride != (4 if compressed else 8) or normal_offset != v_stride * count or bytes.size() != (v_stride + nt_stride) * count:
		return {"skip": "unknown_current3D_layout"}
	if not compressed and tangent_offset != normal_offset + 4:
		return {"skip": "unknown_target_NT_layout"}
	var raw: Dictionary = {"format":format,"vertex_count":count,"index_count":surface.get("index_count",-1),"aabb":surface.get("aabb"),"uv_scale":surface.get("uv_scale"),"vertex_data":bytes,"attribute_data":surface.get("attribute_data",PackedByteArray()),"index_data":surface.get("index_data",PackedByteArray())}
	return {"ok":true,"sha256":_digest(raw),"bytes":bytes,"compressed":compressed,"format":format,"count":count,"normal_offset":normal_offset,"NT_stride":nt_stride,"aabb":str(surface.get("aabb")),"uv_scale":str(surface.get("uv_scale"))}

func _codec_model(normal: Vector3, tangent: Vector3, sign_value: float) -> Dictionary:
	if not normal.is_finite() or not tangent.is_finite() or normal.length_squared() <= 0.0 or tangent.length_squared() <= 0.0 or (sign_value != 1.0 and sign_value != -1.0):
		return {"error":"Nonfinite/zero frame or unknown handedness"}
	var n: Vector2 = normal.octahedron_encode()
	var t: Vector2 = tangent.octahedron_encode()
	# Vector2 component assignments model real_t(float32) exactly. The tangent
	# method itself is C++ only, so reproduce its documented pinned source.
	t.y = maxf(t.y, _f32(1.0 / 32767.0))
	t.y = _f32(_f32(t.y * 0.5) + 0.5)
	if sign_value < 0.0:
		t.y = _f32(1.0 - t.y)
	var q: PackedInt32Array = PackedInt32Array([_u16(n.x),_u16(n.y),_u16(t.x),_u16(t.y)])
	if q[2] == 0 and q[3] == 65535:
		q[2] = 65535 # Exact RenderingServer compressed-format sentinel sanitation.
	var decoded_normal: Vector3 = Vector3.octahedron_decode(Vector2(float(q[0])/65535.0,float(q[1])/65535.0))
	var decoded_tangent_oct: Vector2 = Vector2(float(q[2])/65535.0,float(q[3])/65535.0)
	decoded_tangent_oct.y = _f32(_f32(decoded_tangent_oct.y * 2.0) - 1.0)
	var decoded_sign: float = 1.0 if decoded_tangent_oct.y >= 0.0 else -1.0
	decoded_tangent_oct.y = absf(decoded_tangent_oct.y)
	var decoded_tangent: Vector3 = Vector3.octahedron_decode(decoded_tangent_oct)
	if decoded_sign != sign_value:
		return {"error":"Pinned tangent codec changed handedness"}
	return {"ok":true,"q":q,"normal":decoded_normal,"tangent":decoded_tangent,"sign":decoded_sign}

func _verify_model(rows: Array, mesh: ArrayMesh) -> Dictionary:
	var raw: Dictionary = _raw_surface(mesh)
	if not raw.get("ok",false) or raw.get("compressed",true):
		return {"error":"Target must use known uncompressed3D storage","detail":raw.get("skip","")}
	var actual: Array = mesh.surface_get_arrays(0)
	var bytes: PackedByteArray = raw.bytes
	var per_source: Array = []
	var expected_bytes := PackedByteArray()
	expected_bytes.resize(int(raw.count)*8)
	var max_normal: float = 0.0
	var max_tangent: float = 0.0
	var max_binormal: float = 0.0
	var changed_frames: int = 0
	for row in rows:
		var source: Array = row.arrays
		var nmax: float = 0.0
		var tmax: float = 0.0
		var bmax: float = 0.0
		var changed: int = 0
		for i: int in range(int(row.vertices)):
			var normal: Vector3 = source[Mesh.ARRAY_NORMAL][i]
			var tangent: Vector3 = Vector3(source[Mesh.ARRAY_TANGENT][i*4],source[Mesh.ARRAY_TANGENT][i*4+1],source[Mesh.ARRAY_TANGENT][i*4+2])
			var sign_value: float = source[Mesh.ARRAY_TANGENT][i*4+3]
			var model: Dictionary = _codec_model(normal,tangent,sign_value)
			if not model.get("ok",false):
				return {"error":"Source frame cannot be modeled","source":row.source_path,"vertex":i,"detail":model}
			var j: int = int(row.offset)+i
			var at: int = int(raw.normal_offset)+j*8
			for component: int in range(4):
				var observed: int = bytes.decode_u16(at+component*2)
				if observed != int(model.q[component]):
					return {"error":"Target N/T integer payload differs from pinned codec","source":row.source_path,"vertex":i,"component":component,"expected":model.q[component],"actual":observed}
				expected_bytes.encode_u16(j*8+component*2,observed)
			var actual_tangent: Vector3 = Vector3(actual[Mesh.ARRAY_TANGENT][j*4],actual[Mesh.ARRAY_TANGENT][j*4+1],actual[Mesh.ARRAY_TANGENT][j*4+2])
			if actual[Mesh.ARRAY_NORMAL][j] != model.normal or actual_tangent != model.tangent or actual[Mesh.ARRAY_TANGENT][j*4+3] != model.sign:
				return {"error":"Decoded target N/T differs from exact codec model","source":row.source_path,"vertex":i}
			var nangle: float = rad_to_deg(normal.angle_to(model.normal))
			var tangle: float = rad_to_deg(tangent.angle_to(model.tangent))
			var bangle: float = rad_to_deg(normal.cross(tangent).angle_to(model.normal.cross(model.tangent)))
			nmax=maxf(nmax,nangle);tmax=maxf(tmax,tangle);bmax=maxf(bmax,bangle)
			if normal != model.normal or tangent != model.tangent:
				changed+=1
		max_normal=maxf(max_normal,nmax);max_tangent=maxf(max_tangent,tmax);max_binormal=maxf(max_binormal,bmax)
		changed_frames+=changed
		per_source.append({"source_path":row.source_path,"vertices":row.vertices,"nonzero_error_frames":changed,"max_normal_angular_degrees":nmax,"max_tangent_angular_degrees":tmax,"max_binormal_angular_degrees":bmax})
	return {"ok":true,"codec":"GODOT4_6_2_UNCOMPRESSED_OCT16_TRUNCATION_FLOAT32_TANGENT_SIGN_BIAS_SENTINEL","raw_payload_sha256":_bytes_digest(expected_bytes),"raw_surface_sha256":raw.sha256,"frames":raw.count,"nonzero_error_frames":changed_frames,"max_normal_angular_degrees":max_normal,"max_tangent_angular_degrees":max_tangent,"max_binormal_angular_degrees":max_binormal,"error_bound_policy":"EXACT_PINNED_INTEGER_PAYLOAD_AND_DECODED_MODEL_EQUALITY; per-vector modeled error is the accepted bound, no blanket epsilon","source_NT_bit_identity_claim":false,"per_source":per_source}

func _fail(message: String) -> Dictionary:
	error = message
	set_enabled(false)
	return {"ok": false, "error": message}

func _metadata(item: Node, key: String) -> Variant:
	var at := item
	while at != null:
		if at.has_meta(key):
			return at.get_meta(key)
		if at == town:
			break
		at = at.get_parent()
	return null

func _animation_targets(node: Node) -> void:
	if node is AnimationTree:
		# A live graph can retarget tracks; do not infer static membership.
		_animated_roots.append(town)
	if node is AnimationPlayer:
		var player := node as AnimationPlayer
		var root_node := player.get_node_or_null(player.root_node)
		if root_node == null:
			_animated_roots.append(town)
		else:
			for name in player.get_animation_list():
				var animation := player.get_animation(name)
				for track in animation.get_track_count():
					var target_path := animation.track_get_path(track).get_concatenated_names()
					var target := root_node if target_path.is_empty() else root_node.get_node_or_null(NodePath(target_path))
					_animated_roots.append(target if target != null else town)
	for child in node.get_children():
		_animation_targets(child)

func _no_lods(mesh: ArrayMesh) -> bool:
	var id := mesh.get_instance_id()
	if _lod_cache.has(id):
		return _lod_cache[id]
	# Pinned Godot4.6.2 internal serialization reads native SurfaceData.lods.
	# Avoid RenderingServer.mesh_get_surface's public Dictionary LOD issue.
	var serialized: Variant = mesh.get("_surfaces")
	var safe: bool = serialized is Array and serialized.size() == mesh.get_surface_count()
	if safe:
		for row in serialized:
			if not row is Dictionary or not row.get("lods", []) is Array or not row.get("lods", []).is_empty():
				safe = false
				break
	_lod_cache[id] = safe
	return safe

func _eligible(item: MeshInstance3D, defaults: Dictionary, botanical: Dictionary) -> String:
	if item.mesh == null or not item.mesh is ArrayMesh:
		return "not_ArrayMesh"
	var mesh := item.mesh as ArrayMesh
	if mesh.get_surface_count() != 1:
		return "multiple_or_no_surfaces"
	if botanical.has(item) or item.has_meta("botanical_instance_id"):
		return "existing_botanical_proxy"
	if not bool(defaults.get(item, item.visible)):
		return "default_hidden_source"
	if item.skin != null or item.get_node_or_null(item.skeleton) is Skeleton3D:
		return "skinned"
	if mesh.get_blend_shape_count() != 0:
		return "blend_shapes"
	var ancestor: Node = item
	while ancestor != null and ancestor != town:
		if ancestor.get_script() != null:
			return "scripted_source_or_ancestor"
		ancestor = ancestor.get_parent()
	for target in _animated_roots:
		if target == item or target.is_ancestor_of(item):
			return "animated_target_or_ancestor"
	if item.global_transform != Transform3D.IDENTITY:
		return "nonidentity_world_transform_first_pilot"
	if not _no_lods(mesh):
		return "LOD_or_unknown_serialization"
	if mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES:
		return "not_triangles"
	if item.material_overlay != null:
		return "material_overlay"
	var material := item.get_active_material(0) as BaseMaterial3D
	if material == null:
		return "custom_or_missing_shader"
	if material.next_pass != null:
		return "multipass_material"
	if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
		return "transparent_or_billboard"
	if item.visibility_range_begin != 0.0 or item.visibility_range_end != 0.0 or not item.visibility_parent.is_empty():
		return "range_or_visibility_parent"
	if item.ignore_occlusion_culling or item.transparency != 0.0 or item.custom_aabb != AABB():
		return "nondefault_culling_or_transparency"
	if str(_metadata(item, "asset_role")) == "runtime_open_front_door":
		return "runtime_door"
	var arrays := mesh.surface_get_arrays(0)
	var n: int = arrays[Mesh.ARRAY_VERTEX].size()
	if n < 3 or n > 100000 or arrays[Mesh.ARRAY_INDEX] == null or arrays[Mesh.ARRAY_INDEX].is_empty():
		return "unindexed_or_pilot_vertex_limit"
	for slot in [Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		if arrays[slot] != null and not arrays[slot].is_empty():
			return "skin_or_custom_vertex_attributes"
	return ""

func _key(item: MeshInstance3D, defaults: Dictionary, cell_m: float) -> String:
	var identity := {}
	for key in IDENTITY_KEYS:
		identity[key] = _metadata(item, key)
	var chain := []
	var node := item.get_parent()
	while node != null:
		chain.append(node.get_instance_id())
		if node == town:
			break
		node = node.get_parent()
	var flags := {}
	for flag in FLAGS:
		flags[flag] = item.get(flag)
	var centre := item.mesh.get_aabb().get_center()
	return _digest({"material_instance_id": item.get_active_material(0).get_instance_id(), "parent_chain": chain, "default_visibility": defaults.get(item, item.visible), "cell": Vector2i(floori(centre.x / cell_m), floori(centre.z / cell_m)), "render_flags": flags, "source_format": (item.mesh as ArrayMesh).surface_get_format(0)})

func _color_for_exact_rgba8(value: Color) -> Color:
	# RenderingServer truncates c*255. Submit byte-centres, then strictly verify
	# the actual output readback equals the original source RGBA8 values.
	var bytes := [roundi(value.r * 255.0), roundi(value.g * 255.0), roundi(value.b * 255.0), roundi(value.a * 255.0)]
	return Color(minf(1., (bytes[0] + .25) / 255.), minf(1., (bytes[1] + .25) / 255.), minf(1., (bytes[2] + .25) / 255.), minf(1., (bytes[3] + .25) / 255.))

func _verify_group_arrays(rows: Array, actual: Array) -> Dictionary:
	var index_offset: int = 0
	for row in rows:
		var arrays: Array = row.arrays
		for slot: int in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:
			if arrays[slot] == null or arrays[slot].is_empty():
				if actual[slot] != null and not actual[slot].is_empty():
					return {"error":"Unexpected output attribute "+str(slot)}
				continue
			if actual[slot] == null or actual[slot].size() < int(row.offset)+arrays[slot].size():
				return {"error":"Missing/shortened strict output attribute "+str(slot)}
			for i: int in arrays[slot].size():
				if actual[slot][int(row.offset)+i] != arrays[slot][i]:
					return {"error":"Strict decoded XYZ/UV/color changed","source":row.source_path,"slot":slot,"index":i}
		if actual[Mesh.ARRAY_INDEX] == null or actual[Mesh.ARRAY_INDEX].size() < index_offset+arrays[Mesh.ARRAY_INDEX].size():
			return {"error":"Missing/shortened output indices"}
		for index: int in arrays[Mesh.ARRAY_INDEX]:
			if actual[Mesh.ARRAY_INDEX][index_offset] != index+int(row.offset):
				return {"error":"Triangle index/winding changed"}
			index_offset+=1
	for slot: int in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:
		var expected_count: int=0
		for row in rows:
			if row.arrays[slot] != null:
				expected_count+=row.arrays[slot].size()
		if (0 if actual[slot] == null else actual[slot].size()) != expected_count:
			return {"error":"Output attribute count changed","slot":slot}
	if actual[Mesh.ARRAY_INDEX].size() != index_offset:
		return {"error":"Unexpected output indices"}
	return {"ok":true}

func _make_group(key: String, members: Array) -> Dictionary:
	var source := members[0] as MeshInstance3D
	var combined := []
	combined.resize(Mesh.ARRAY_MAX)
	var rows := []
	var vertex_offset := 0
	for item: MeshInstance3D in members:
		var arrays := item.mesh.surface_get_arrays(0)
		var packed: Dictionary = _raw_surface(item.mesh as ArrayMesh)
		if not packed.get("ok", false):
			return packed
		var n: int = arrays[Mesh.ARRAY_VERTEX].size()
		if vertex_offset + n > 200000:
			return {"skip": "group_pilot_vertex_limit"}
		rows.append({"item": item, "source_path": str(item.get_path()), "original_layers": item.layers, "original_cast_shadow": item.cast_shadow, "arrays": arrays, "offset": vertex_offset, "vertices": n, "source_hash": _digest(arrays), "mesh_id": item.mesh.get_instance_id(), "global_transform": item.global_transform, "source_raw_sha256": packed.sha256, "source_compressed": packed.compressed, "source_format": packed.format})
		for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
			if arrays[slot] == null or arrays[slot].is_empty():
				continue
			if combined[slot] == null:
				combined[slot] = arrays[slot].duplicate()
				if slot == Mesh.ARRAY_COLOR:
					for i in combined[slot].size():
						combined[slot][i] = _color_for_exact_rgba8(combined[slot][i])
			elif slot == Mesh.ARRAY_COLOR:
				for color in arrays[slot]:
					combined[slot].append(_color_for_exact_rgba8(color))
			else:
				combined[slot].append_array(arrays[slot])
		if combined[Mesh.ARRAY_INDEX] == null:
			combined[Mesh.ARRAY_INDEX] = PackedInt32Array()
		for index in arrays[Mesh.ARRAY_INDEX]:
			combined[Mesh.ARRAY_INDEX].append(index + vertex_offset)
		vertex_offset += n
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, combined, [], {}, 0)
	if mesh.get_surface_count() != 1:
		return {"error":"Uncompressed derivative construction failed"}
	mesh.surface_set_material(0, source.get_active_material(0))
	var copied: Dictionary = _verify_model(rows, mesh)
	if not copied.get("ok", false):
		return copied
	var actual := mesh.surface_get_arrays(0)
	var verified: Dictionary = _verify_group_arrays(rows, actual)
	if verified.has("error"):
		return verified
	if verified.has("skip"):
		return {"error": "Strict source reconstruction failed", "detail": verified}
	var batch := MeshInstance3D.new()
	batch.name = "DiagnosticStaticBatch_" + key.substr(0, 12)
	batch.visible = false
	batch.mesh = mesh
	for flag in FLAGS:
		batch.set(flag, source.get(flag))
	source.get_parent().add_child(batch)
	batch.global_transform = Transform3D.IDENTITY
	if batch.global_transform != Transform3D.IDENTITY:
		batch.free()
		return {"error": "Batch world transform is not exact identity"}
	return {"key": key, "node": batch, "members": members, "rows": rows, "source_surface_count": members.size(), "vertices": vertex_offset, "triangles": actual[Mesh.ARRAY_INDEX].size() / 3, "output_arrays_sha256": _digest(actual), "strict_XYZ_UV_color_topology_equal": true, "NT_quantization": copied}

func prepare(model: Node3D, cell_m := 16.0) -> Dictionary:
	if prepared or model == null or cell_m <= 0.0:
		return _fail("Fresh helper, actual town model, positive spatial cell required")
	town = model
	_mesh_registry_hash = _digest(_registry_ids(town.get("meshes")))
	_ground_registry_hash = _digest(_registry_ids(town.get("_ground_meshes")))
	_animation_targets(town)
	var defaults: Dictionary = town.get("_default_visibility")
	var botanical: Dictionary = town.get("_botanical_proxy_batches")
	var candidates := {}
	for item: MeshInstance3D in town.get("meshes"):
		var reason := _eligible(item, defaults, botanical)
		if not reason.is_empty():
			_skip(reason)
			continue
		var key := _key(item, defaults, cell_m)
		if not candidates.has(key):
			candidates[key] = []
		candidates[key].append(item)
	for key in candidates:
		var members: Array = candidates[key]
		if members.size() < 2:
			_skip("singleton_group")
			continue
		var group := _make_group(str(key), members)
		if group.has("error"):
			return _fail(JSON.stringify(group))
		if group.has("skip"):
			_skip(group.skip)
			continue
		groups.append(group)
		for item: MeshInstance3D in members:
			proxies[item] = {"layers": item.layers, "cast_shadow": item.cast_shadow, "group": group.key, "mesh_id": item.mesh.get_instance_id(), "transform": item.global_transform}
	prepared = true
	var source_compressed_count: int=0
	var max_normal: float=0.0
	var max_tangent: float=0.0
	var max_binormal: float=0.0
	var error_frames: int=0
	for group in groups:
		for row in group.rows:
			if row.source_compressed:
				source_compressed_count+=1
		max_normal=maxf(max_normal,float(group.NT_quantization.max_normal_angular_degrees))
		max_tangent=maxf(max_tangent,float(group.NT_quantization.max_tangent_angular_degrees))
		max_binormal=maxf(max_binormal,float(group.NT_quantization.max_binormal_angular_degrees))
		error_frames+=int(group.NT_quantization.nonzero_error_frames)
	info={"groups":groups.size(),"source_mesh_proxies":proxies.size(),"source_compressed_count":source_compressed_count,"cell_m":cell_m,"skipped":skipped,"nonzero_NT_error_frames":error_frames,"max_normal_angular_degrees":max_normal,"max_tangent_angular_degrees":max_tangent,"max_binormal_angular_degrees":max_binormal,"world_transform_policy":"EXACT_IDENTITY_ONLY","buffer_policy":"DECODED_XYZ_UV_COLOR_INDICES_EXACT; NT_KNOWN_OCT16_REPRESENTATION_CONVERSION_MODELED_PER_VERTEX_NO_BLANKET_EPSILON","NT_bit_identity_claim":false,"sources_remain_canonical_ray_nodes":true,"new_nodes_registered_in_town_mesh_arrays":false,"art_and_shadow_acceptance":"ACTUAL_BEFORE_AFTER_REVIEW_REQUIRED"}
	return {"ok": not groups.is_empty(), "info": info, "error": "No eligible groups" if groups.is_empty() else ""}

func _hide_all_batches() -> void:
	for group in groups:
		if is_instance_valid(group.node):
			group.node.visible = false

func _disable_invalid(reason: String) -> Dictionary:
	# Suppression/restoration must finish before any diagnostic can return.
	set_enabled(false)
	error = reason
	return {"ok": false, "error": reason, "fallback": "ALL_BATCHES_HIDDEN_EVERY_LIVE_SOURCE_RENDER_FLAGS_RESTORED"}

func set_enabled(value: bool) -> Dictionary:
	if value and not prepared:
		return {"ok": false, "error": "Not prepared"}
	enabled = value
	if not value:
		_hide_all_batches()
	var missing := false
	for candidate: Variant in proxies:
		if not is_instance_valid(candidate):
			missing = true
			continue
		var item: MeshInstance3D = candidate as MeshInstance3D
		item.layers = 0 if value else int(proxies[item].layers)
		item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if value else int(proxies[item].cast_shadow)
	if missing:
		# Restore every surviving source, even when an earlier member vanished.
		enabled = false
		_hide_all_batches()
		for candidate: Variant in proxies:
			if is_instance_valid(candidate):
				var item: MeshInstance3D = candidate as MeshInstance3D
				item.layers = int(proxies[item].layers)
				item.cast_shadow = int(proxies[item].cast_shadow)
		return {"ok": false, "error": "Original source node was removed; all surviving proxies restored"}
	# Disable is unconditional; do not re-enter validation and leave later
	# render batches visible after the first invalid group.
	return reconcile() if value else {"ok": true, "enabled": false, "groups": groups.size()}

func reconcile() -> Dictionary:
	for group in groups:
		if not is_instance_valid(group.node):
			return _disable_invalid("Render batch was removed; surviving proxies restored")
		var first_candidate: Variant = group.members[0]
		if not is_instance_valid(first_candidate):
			return _disable_invalid("First source member was removed; surviving proxies restored")
		var first: MeshInstance3D = first_candidate as MeshInstance3D
		for candidate: Variant in group.members:
			if not is_instance_valid(candidate):
				return _disable_invalid("Source member was removed; surviving proxies restored")
			var item: MeshInstance3D = candidate as MeshInstance3D
			if item.visible != first.visible or item.get_parent() != first.get_parent():
				return _disable_invalid("Visibility/parent state is not uniform within exact semantic group")
			if item.mesh == null or item.mesh.get_instance_id() != int(proxies[item].mesh_id) or item.global_transform != proxies[item].transform:
				return _disable_invalid("Source mesh identity or world transform changed")
		group.node.visible = enabled and first.visible
	return {"ok": true, "enabled": enabled, "groups": groups.size()}

func evidence() -> Dictionary:
	var records := []
	for group in groups:
		var members := []
		for row in group.rows:
			var candidate: Variant = row.item
			var member: Dictionary = {"path": row.source_path, "source_arrays_sha256": row.source_hash, "vertices": row.vertices, "offset": row.offset, "original_layers": row.original_layers, "original_cast_shadow": row.original_cast_shadow, "source_available": is_instance_valid(candidate)}
			if is_instance_valid(candidate):
				var item: MeshInstance3D = candidate as MeshInstance3D
				member["visible"] = item.visible
				member["visible_in_tree"] = item.is_visible_in_tree()
			members.append(member)
		var batch_path: String = str(group.node.get_path()) if is_instance_valid(group.node) else "FREED_RENDER_BATCH"
		records.append({"key": group.key, "batch_path": batch_path, "vertices": group.vertices, "triangles": group.triangles, "strict_XYZ_UV_color_topology_equal": group.strict_XYZ_UV_color_topology_equal, "output_arrays_sha256": group.output_arrays_sha256, "NT_quantization": group.NT_quantization, "members": members})
	return {"info": info, "enabled": enabled, "groups": records}

func _registry_ids(items: Array) -> Array:
	var result := []
	for candidate: Variant in items:
		result.append(candidate.get_instance_id() if is_instance_valid(candidate) else "FREED_SOURCE")
	return result

func validate_sources() -> Dictionary:
	if _digest(_registry_ids(town.get("meshes"))) != _mesh_registry_hash or _digest(_registry_ids(town.get("_ground_meshes"))) != _ground_registry_hash:
		return _disable_invalid("Canonical semantic/ray registry membership or order changed")
	for group in groups:
		var batch_candidate: Variant = group.node
		if not is_instance_valid(batch_candidate):
			return _disable_invalid("Render batch was removed")
		var batch: MeshInstance3D = batch_candidate as MeshInstance3D
		if batch.mesh == null or batch.global_transform != Transform3D.IDENTITY or _digest(batch.mesh.surface_get_arrays(0)) != group.output_arrays_sha256:
			return _disable_invalid("Actual batch mesh buffers or world transform changed after construction")
		var raw_batch: Dictionary = _raw_surface(batch.mesh as ArrayMesh)
		if not raw_batch.get("ok",false) or raw_batch.sha256 != group.NT_quantization.raw_surface_sha256:
			return _disable_invalid("Actual derivative raw buffers changed after codec verification")
		for row in group.rows:
			var candidate: Variant = row.item
			if not is_instance_valid(candidate):
				return _disable_invalid("Original canonical source node was removed")
			var item: MeshInstance3D = candidate as MeshInstance3D
			if item.mesh == null or item.mesh.get_instance_id() != int(row.mesh_id) or item.global_transform != row.global_transform:
				return _disable_invalid("Original canonical node/mesh/world transform changed")
			if _digest(item.mesh.surface_get_arrays(0)) != row.source_hash:
				return _disable_invalid("Original canonical source mesh buffers changed")
			var packed: Dictionary = _raw_surface(item.mesh as ArrayMesh)
			if not packed.get("ok", false) or packed.sha256 != row.source_raw_sha256:
				return _disable_invalid("Original canonical source packed bytes changed")
			if item.layers != (0 if enabled else int(proxies[item].layers)) or item.cast_shadow != (GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if enabled else int(proxies[item].cast_shadow)):
				return _disable_invalid("Proxy render flags differ from the declared enabled state")
			if item.get_active_material(0) != group.node.mesh.surface_get_material(0):
				return _disable_invalid("Exact shared material identity changed")
	return {"ok": true, "original_mesh_buffers_unchanged": true, "batch_buffers_unchanged": true, "semantic_ray_registry_unchanged": true, "original_nodes": proxies.size()}

func dispose() -> void:
	set_enabled(false)
	for group in groups:
		if is_instance_valid(group.node):
			group.node.free()
	groups.clear()
	proxies.clear()
	prepared = false


# Optional Godot-specific artifact. Canonical nodes and the original builder,
# codec proof, validators and live invalidation methods above remain unchanged.
const CACHE_SCHEMA: String = "living_town.static_render_cache.v1"
var _cache_material_digests: Dictionary = {}
var _cache_texture_digests: Dictionary = {}

func cache_binding(model: Node3D, cell_m: float = 16.0) -> Dictionary:
	var stage: Dictionary = model.get("stage_manifest")
	var stage_path: String = "res://assets/town3d/stage_manifest.json"
	var model_path: String = model.get_script().resource_path
	var helper_path: String = get_script().resource_path
	# Source-project prototype: a compiled-only PCK must use the safe builder
	# until a separately verified exported-policy binding is implemented/proven.
	if not bool(model.get("_raw_source_verified")) or not FileAccess.file_exists(stage_path) or not FileAccess.file_exists(model_path) or not FileAccess.file_exists(helper_path):
		return {"ok": false, "error": "Raw-source/policy byte identity unavailable; use original builder"}
	if stage.get("schema", "") != "living_town.game_stage.v2" or stage.get("status", "") != "PASS" or str(stage.get("source_asset_set_sha256", "")).length() != 64:
		return {"ok": false, "error": "Exact current staged asset identity unavailable"}
	var catalogs: Array = []
	for asset: Dictionary in stage.get("assets", []):
		var path: String = "res://assets/town3d/" + str(asset.get("catalog", ""))
		var actual: String = FileAccess.get_sha256(path)
		if actual.is_empty() or actual != str(asset.get("catalog_sha256", "")):
			return {"ok": false, "error": "Current staged catalog bytes differ"}
		catalogs.append({"file": asset.get("catalog"), "sha256": actual, "source_glb_sha256": asset.get("sha256")})
	if catalogs.is_empty(): return {"ok": false, "error": "No staged catalogs"}
	return {"ok": true, "binding": {"schema": CACHE_SCHEMA, "engine": Engine.get_version_info(), "cell_m": cell_m, "stage_sha256": FileAccess.get_sha256(stage_path), "source_asset_set_sha256": stage.get("source_asset_set_sha256"), "catalogs": catalogs, "model_policy_sha256": FileAccess.get_sha256(model_path), "batcher_policy_sha256": FileAccess.get_sha256(helper_path)}}

func _cache_paths(items: Array) -> Array:
	var paths: Array = []
	for value: Variant in items:
		if not is_instance_valid(value) or not town.is_ancestor_of(value): return ["INVALID_SOURCE"]
		paths.append(str(town.get_path_to(value)))
	return paths

func _cache_material_digest(material: Material) -> String:
	if material == null or not material is BaseMaterial3D: return ""
	var ident: int = material.get_instance_id()
	if _cache_material_digests.has(ident): return str(_cache_material_digests[ident])
	var values: Dictionary = {"class": material.get_class()}
	for prop: Dictionary in material.get_property_list():
		if (int(prop.usage) & PROPERTY_USAGE_STORAGE) == 0: continue
		var name: String = str(prop.name)
		var value: Variant = material.get(name)
		if value is Texture2D:
			var texture: Texture2D = value as Texture2D
			var texture_id: int = texture.get_instance_id()
			if not _cache_texture_digests.has(texture_id):
				var pixels: Image = texture.get_image()
				if pixels == null: return ""
				_cache_texture_digests[texture_id] = _digest({"class": texture.get_class(), "width": pixels.get_width(), "height": pixels.get_height(), "format": pixels.get_format(), "mipmaps": pixels.has_mipmaps(), "bytes": pixels.get_data()})
			values[name] = {"texture_content_sha256": _cache_texture_digests[texture_id]}
		elif typeof(value) in [TYPE_OBJECT, TYPE_RID, TYPE_CALLABLE, TYPE_SIGNAL] and value != null:
			return "" # Unknown resource/shader graphs fall back; never guess equality.
		else:
			values[name] = value
	var result: String = _digest(values)
	_cache_material_digests[ident] = result
	return result

func _cache_source_state(item: MeshInstance3D) -> String:
	var flags: Dictionary = {}
	for flag: String in FLAGS: flags[flag] = item.get(flag)
	var metadata: Dictionary = {}
	var names: Array = []
	for name: StringName in item.get_meta_list(): names.append(str(name))
	names.sort()
	for name: String in names: metadata[name] = item.get_meta(name)
	return _digest({"path": str(town.get_path_to(item)), "parent": str(town.get_path_to(item.get_parent())), "visible": item.visible, "flags": flags, "metadata": metadata, "transform": item.global_transform, "lightmap_hint": (item.mesh as ArrayMesh).lightmap_size_hint})

func _cache_miss(message: String) -> Dictionary:
	return {"ok": false, "cache_miss": true, "error": message}

func save_cache(resource_path: String, manifest_path: String, binding: Dictionary) -> Dictionary:
	if not prepared or enabled or binding.is_empty(): return _cache_miss("Fresh verified disabled batches and exact binding required")
	var verified: Dictionary = validate_sources()
	if not verified.get("ok", false): return verified
	_cache_material_digests.clear(); _cache_texture_digests.clear()
	var records: Array = []
	for group: Dictionary in groups:
		var members: Array = []
		for row: Dictionary in group.rows:
			var item: MeshInstance3D = row.item as MeshInstance3D
			var material_sha: String = _cache_material_digest(item.get_active_material(0))
			if material_sha.is_empty(): return _cache_miss("Unsupported material content in cache producer")
			members.append({"relative_path": str(town.get_path_to(item)), "source_hash": row.source_hash, "source_raw_sha256": row.source_raw_sha256, "source_compressed": row.source_compressed, "source_format": row.source_format, "vertices": row.vertices, "offset": row.offset, "original_layers": row.original_layers, "original_cast_shadow": row.original_cast_shadow, "source_state_sha256": _cache_source_state(item), "material_sha256": material_sha})
		var mesh: ArrayMesh = group.node.mesh.duplicate() as ArrayMesh
		mesh.surface_set_material(0, null) # No current-model materials enter the shared artifact.
		records.append({"mesh": mesh, "members": members, "vertices": group.vertices, "triangles": group.triangles, "source_surface_count": group.source_surface_count, "output_arrays_sha256": group.output_arrays_sha256, "strict_XYZ_UV_color_topology_equal": group.strict_XYZ_UV_color_topology_equal, "NT_quantization": group.NT_quantization})
	var payload: Dictionary = {"schema": CACHE_SCHEMA, "binding": binding, "mesh_registry": _cache_paths(town.get("meshes")), "ground_registry": _cache_paths(town.get("_ground_meshes")), "groups": records, "info": info.duplicate(true), "full_build_validation": verified}
	var container: Resource = Resource.new()
	container.set_meta("payload", payload)
	var error_code: Error = ResourceSaver.save(container, resource_path, ResourceSaver.FLAG_COMPRESS)
	if error_code != OK: return _cache_miss("Compressed binary Resource save failed: " + str(error_code))
	if not ResourceLoader.get_dependencies(resource_path).is_empty(): return _cache_miss("Cache must be self-contained, without external material/script resources")
	# Actual serialized readback, using independent Resource/subresource objects.
	var reopened: Resource = ResourceLoader.load(resource_path, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
	if reopened == null or not reopened.has_meta("payload"): return _cache_miss("Saved cache failed independent resource readback")
	var back: Dictionary = reopened.get_meta("payload")
	if _digest(back.get("binding")) != _digest(binding) or back.get("groups", []).size() != groups.size(): return _cache_miss("Saved cache header changed")
	for i: int in groups.size():
		var saved_mesh: ArrayMesh = back.groups[i].mesh as ArrayMesh
		var packed: Dictionary = _raw_surface(saved_mesh)
		if not packed.get("ok", false) or packed.sha256 != groups[i].NT_quantization.raw_surface_sha256 or _digest(saved_mesh.surface_get_arrays(0)) != groups[i].output_arrays_sha256 or saved_mesh.surface_get_material(0) != null:
			return _cache_miss("Saved cache target buffers/material isolation changed")
	var stream: FileAccess = FileAccess.open(resource_path, FileAccess.READ)
	var byte_count: int = stream.get_length(); stream.close()
	var manifest: Dictionary = {"schema": CACHE_SCHEMA, "status": "PASS_FULL_BUILDER_CODEC_VALIDATION_AND_RESOURCE_READBACK", "resource_file": resource_path.get_file(), "resource_bytes": byte_count, "resource_sha256": FileAccess.get_sha256(resource_path), "binding_sha256": _digest(binding), "groups": groups.size(), "source_members": proxies.size(), "full_build_validation": verified, "engine_specific": true, "portable_asset_authority": false}
	stream = FileAccess.open(manifest_path, FileAccess.WRITE)
	if stream == null: return _cache_miss("Cannot write cache manifest")
	stream.store_string(JSON.stringify(manifest, "\t") + "\n"); stream.close()
	return {"ok": true, "manifest": manifest, "resource": resource_path, "manifest_path": manifest_path}

func load_cache(model: Node3D, resource_path: String, manifest_path: String, binding: Dictionary) -> Dictionary:
	if prepared or model == null or binding.is_empty(): return _cache_miss("Fresh helper/model/binding required")
	if not FileAccess.file_exists(resource_path) or not FileAccess.file_exists(manifest_path): return _cache_miss("Cache files absent")
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not value is Dictionary: return _cache_miss("Invalid cache manifest JSON")
	var manifest: Dictionary = value
	if manifest.get("schema") != CACHE_SCHEMA or manifest.get("status") != "PASS_FULL_BUILDER_CODEC_VALIDATION_AND_RESOURCE_READBACK" or manifest.get("binding_sha256") != _digest(binding) or manifest.get("resource_file") != resource_path.get_file(): return _cache_miss("Cache schema/policy/stage/engine binding differs")
	var stream: FileAccess = FileAccess.open(resource_path, FileAccess.READ)
	if stream == null: return _cache_miss("Cache resource unreadable")
	var byte_count: int = stream.get_length(); stream.close()
	if int(manifest.get("resource_bytes", -1)) != byte_count or FileAccess.get_sha256(resource_path) != manifest.get("resource_sha256"): return _cache_miss("Cache resource bytes differ; no cached object loaded")
	if not ResourceLoader.get_dependencies(resource_path).is_empty(): return _cache_miss("Unexpected external cache dependency")
	var container: Resource = ResourceLoader.load(resource_path, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
	if container == null or container.get_script() != null or not container.has_meta("payload"): return _cache_miss("Invalid self-contained cache resource")
	value = container.get_meta("payload")
	if not value is Dictionary: return _cache_miss("Invalid cache payload")
	var payload: Dictionary = value
	if not payload.get("full_build_validation") is Dictionary or not payload.get("info") is Dictionary or not payload.get("groups") is Array: return _cache_miss("Cache payload field types differ")
	if payload.get("schema") != CACHE_SCHEMA or _digest(payload.get("binding")) != _digest(binding) or not payload.full_build_validation.get("ok", false): return _cache_miss("Cache producer proof/binding differs")
	town = model
	if _cache_paths(town.get("meshes")) != payload.get("mesh_registry") or _cache_paths(town.get("_ground_meshes")) != payload.get("ground_registry"): return _cache_miss("Current canonical semantic/ray registry membership/order differs")
	var records: Array = payload.get("groups", [])
	if records.is_empty() or records.size() != int(manifest.get("groups", -1)): return _cache_miss("Cache group inventory differs")
	_cache_material_digests.clear(); _cache_texture_digests.clear()
	_animation_targets(town)
	var defaults: Dictionary = town.get("_default_visibility")
	var botanical: Dictionary = town.get("_botanical_proxy_batches")
	var plans: Array = []
	var seen_members: Dictionary = {}; var seen_keys: Dictionary = {}; var raw_by_mesh: Dictionary = {}
	for record_value: Variant in records:
		if not record_value is Dictionary: return _cache_miss("Cache group is not a record")
		var record: Dictionary = record_value
		if not record.get("members") is Array or not record.get("NT_quantization") is Dictionary: return _cache_miss("Cache group fields differ")
		for field: String in ["mesh", "vertices", "triangles", "source_surface_count", "output_arrays_sha256", "strict_XYZ_UV_color_topology_equal"]:
			if not record.has(field): return _cache_miss("Cache group field absent: " + field)
		var cached_mesh: ArrayMesh = record.get("mesh") as ArrayMesh
		if cached_mesh == null or cached_mesh.get_surface_count() != 1 or cached_mesh.surface_get_material(0) != null: return _cache_miss("Cache mesh/material isolation differs")
		var target: Dictionary = _raw_surface(cached_mesh)
		if not target.get("ok", false) or target.sha256 != record.get("NT_quantization", {}).get("raw_surface_sha256") or _digest(cached_mesh.surface_get_arrays(0)) != record.get("output_arrays_sha256"): return _cache_miss("Actual cached derivative buffers differ from full producer proof")
		var members: Array = []; var rows: Array = []; var group_key: String = ""
		var vertex_offset: int = 0
		for saved_value: Variant in record.get("members", []):
			if not saved_value is Dictionary: return _cache_miss("Cache source is not a record")
			var saved: Dictionary = saved_value
			for field: String in ["relative_path", "source_hash", "source_raw_sha256", "source_compressed", "source_format", "vertices", "offset", "original_layers", "original_cast_shadow", "source_state_sha256", "material_sha256"]:
				if not saved.has(field): return _cache_miss("Cache source field absent: " + field)
			var relative: String = str(saved.get("relative_path", ""))
			var item: MeshInstance3D = town.get_node_or_null(NodePath(relative)) as MeshInstance3D
			if item == null or seen_members.has(relative) or not town.is_ancestor_of(item): return _cache_miss("Missing/duplicate/foreign cached source identity")
			seen_members[relative] = true
			if not _eligible(item, defaults, botanical).is_empty() or _cache_source_state(item) != saved.get("source_state_sha256") or _cache_material_digest(item.get_active_material(0)) != saved.get("material_sha256"): return _cache_miss("Current source eligibility/metadata/material/render state differs")
			var key: String = _key(item, defaults, float(binding.cell_m))
			if group_key.is_empty(): group_key = key
			elif key != group_key: return _cache_miss("Current source group no longer has exact common parent/material/flags")
			var mesh_id: int = item.mesh.get_instance_id()
			if not raw_by_mesh.has(mesh_id): raw_by_mesh[mesh_id] = _raw_surface(item.mesh as ArrayMesh)
			var packed: Dictionary = raw_by_mesh[mesh_id]
			if not packed.get("ok", false) or packed.sha256 != saved.get("source_raw_sha256") or int(packed.count) != int(saved.get("vertices", -1)) or int(saved.get("offset", -1)) != vertex_offset: return _cache_miss("Current imported mesh packed content/offset differs")
			var row: Dictionary = saved.duplicate(true)
			row.merge({"item": item, "source_path": str(item.get_path()), "mesh_id": mesh_id, "global_transform": item.global_transform}, true)
			rows.append(row); members.append(item); vertex_offset += int(saved.vertices)
		if members.size() < 2 or seen_keys.has(group_key) or vertex_offset != int(record.get("vertices", -1)) or int(target.count) != vertex_offset: return _cache_miss("Cached group partition/count differs")
		seen_keys[group_key] = true
		plans.append({"record": record, "key": group_key, "members": members, "rows": rows})
	if seen_members.size() != int(manifest.get("source_members", -1)) or seen_members.size() != int(payload.info.get("source_mesh_proxies", -1)): return _cache_miss("Cached source member inventory differs")
	# Every group/source was checked before any rendering node or source flag write.
	_mesh_registry_hash = _digest(_registry_ids(town.get("meshes")))
	_ground_registry_hash = _digest(_registry_ids(town.get("_ground_meshes")))
	for plan: Dictionary in plans:
		var record: Dictionary = plan.record
		var first: MeshInstance3D = plan.members[0] as MeshInstance3D
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = "DiagnosticStaticBatch_" + str(plan.key).substr(0, 12)
		node.visible = false
		# Each model owns its material slot/RID. The cached resource stays material-free.
		node.mesh = (record.mesh as ArrayMesh).duplicate() as ArrayMesh
		node.mesh.surface_set_material(0, first.get_active_material(0))
		for flag: String in FLAGS: node.set(flag, first.get(flag))
		first.get_parent().add_child(node); node.global_transform = Transform3D.IDENTITY
		var group: Dictionary = {"key": plan.key, "node": node, "members": plan.members, "rows": plan.rows, "source_surface_count": record.source_surface_count, "vertices": record.vertices, "triangles": record.triangles, "output_arrays_sha256": record.output_arrays_sha256, "strict_XYZ_UV_color_topology_equal": record.strict_XYZ_UV_color_topology_equal, "NT_quantization": record.NT_quantization}
		groups.append(group)
		for row: Dictionary in plan.rows:
			proxies[row.item] = {"layers": row.original_layers, "cast_shadow": row.original_cast_shadow, "group": plan.key, "mesh_id": row.mesh_id, "transform": row.global_transform}
	prepared = true
	info = payload.info.duplicate(true)
	info["cache"] = {"status": "HIT", "resource_sha256": manifest.resource_sha256, "binding_sha256": manifest.binding_sha256, "current_imported_source_packed_buffers_verified": true, "current_target_packed_and_decoded_buffers_verified": true, "NT_codec_replayed_this_load": false, "NT_codec_proof_scope": "Exact producer full-codec proof bound to these serialized target bytes and current imported source bytes", "material_slots_owned_per_model": true, "portable_asset_authority": false}
	return {"ok": true, "cache_hit": true, "info": info}
