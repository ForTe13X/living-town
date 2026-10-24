extends RefCounted
## Ignored experiment: exact old filters/triangles after a conservative static
## XZ-cell broadphase. No visibility, distance or owner verdict is cached.

var _model: Node
var _source_all: Array = []
var _source_ground: Array = []
var _all_size := -1
var _ground_size := -1
var _valid := false
var _cells: Dictionary = {}
var _records: Array[Dictionary] = []
var _overflow: Array[int] = []
var cell_size_m := 32.0
var stats: Dictionary = {"builds":0,"build_usec":0,"queries":0,"candidate_records":0,"source_records":0,"cell_count":0,"overflow_records":0,"invalidations":[]}

func bind_model(model: Node, size_m: float = 32.0) -> void:
	assert(size_m >= 8.0 and size_m <= 128.0)
	_model = model
	cell_size_m = size_m
	invalidate("bind_model")
	rebuild()

func invalidate(reason: String) -> void:
	_valid = false
	stats["invalidations"].append(reason)

func rebuild() -> void:
	var started := Time.get_ticks_usec()
	_cells.clear()
	_records.clear()
	_overflow.clear()
	_source_all = _model.get("meshes")
	_source_ground = _model.get("_ground_meshes")
	_all_size = _source_all.size()
	_ground_size = _source_ground.size()
	var bounds_by_node: Dictionary = {}
	# Separate records preserve each scope's exact array order, including an
	# intentionally repeated reference or ground-only candidate in a fixture.
	for scope: String in ["all","ground"]:
		var source: Array = _source_ground if scope == "ground" else _source_all
		for item: MeshInstance3D in source:
			if item.mesh == null:
				continue
			var ident := item.get_instance_id()
			if not bounds_by_node.has(ident):
				bounds_by_node[ident] = item.global_transform * item.mesh.get_aabb()
			var bounds: AABB = bounds_by_node[ident]
			var number := _records.size()
			_records.append({"item":item,"bounds":bounds,"scope":scope})
			var first := Vector2i(floori(bounds.position.x / cell_size_m), floori(bounds.position.z / cell_size_m))
			var last := Vector2i(floori(bounds.end.x / cell_size_m), floori(bounds.end.z / cell_size_m))
			if (last.x-first.x+1)*(last.y-first.y+1) > 4096:
				_overflow.append(number)
				continue
			for x in range(first.x,last.x+1):
				for z in range(first.y,last.y+1):
					var key := Vector2i(x,z)
					if not _cells.has(key): _cells[key] = []
					_cells[key].append(number)
	_valid = true
	stats["builds"] += 1
	stats["build_usec"] += Time.get_ticks_usec()-started
	stats["source_records"] = _records.size()
	stats["cell_count"] = _cells.size()
	stats["overflow_records"] = _overflow.size()

func _ensure_current() -> void:
	var all_now: Array = _model.get("meshes")
	var ground_now: Array = _model.get("_ground_meshes")
	if not _valid or not is_same(all_now,_source_all) or not is_same(ground_now,_source_ground) or all_now.size()!=_all_size or ground_now.size()!=_ground_size:
		rebuild()

func candidate_indices(origin: Vector3, end: Vector3, scope: String) -> Array[int]:
	_ensure_current()
	var wanted := "ground" if scope == "ground" else "all"
	var first := Vector2i(floori(minf(origin.x,end.x)/cell_size_m),floori(minf(origin.z,end.z)/cell_size_m))
	var last := Vector2i(floori(maxf(origin.x,end.x)/cell_size_m),floori(maxf(origin.z,end.z)/cell_size_m))
	var found: Dictionary = {}
	# Giant diagonal queries may conservatively use the full source scope.
	# This changes cost only; exact old AABB/triangle tests remain downstream.
	if (last.x-first.x+1)*(last.y-first.y+1) > 16384:
		for number: int in range(_records.size()):
			if _records[number]["scope"] == wanted: found[number] = true
	else:
		for x in range(first.x,last.x+1):
			for z in range(first.y,last.y+1):
				for number: int in _cells.get(Vector2i(x,z),[]):
					if _records[number]["scope"] == wanted: found[number] = true
		for number: int in _overflow:
			if _records[number]["scope"] == wanted: found[number] = true
	var result: Array[int] = []
	for number: int in found: result.append(number)
	result.sort() # Original per-scope array order, including nearest-hit ties.
	stats["queries"] += 1
	stats["candidate_records"] += result.size()
	return result

func raycast_geometry(origin: Vector3, direction: Vector3, max_distance: float = 1000.0, scope: String = "ground", building_id: String = "") -> Dictionary:
	var end: Vector3 = origin + direction.normalized() * max_distance
	var selected := candidate_indices(origin,end,scope)
	var _triangle_cache: Dictionary = _model.get("_triangle_cache")
	var _botanical_proxy_batches: Dictionary = _model.get("_botanical_proxy_batches")
	var best: Dictionary = {}
	var nearest: float = max_distance
	for number: int in selected:
		var item: MeshInstance3D = _records[number]["item"]
		if item.mesh == null:
			continue
		if not item.is_visible_in_tree():
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
		var bounds: AABB = _records[number]["bounds"]
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
	return str(_model.call("_owner_id",node,key))
