extends RefCounted
class_name WorldGenPackageValidator
## Minimal strict root checks for immutable runtime packages.

const CANONICAL := preload("res://addons/worldgen/core/worldgen_canonical.gd")

static func validate(package: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not package is Dictionary or String(package.get("schema", "")) != "WorldPackage/1":
		return {"ok": false, "errors": ["E_PACKAGE_SCHEMA: expected WorldPackage/1"]}
	var root_fields: Array[String] = ["schema", "world_id", "coordinate_frame", "capabilities",
		"semantic", "presentation", "provenance", "digests"]
	for field: String in root_fields:
		if not package.has(field): errors.append("E_PACKAGE_FIELD: missing %s" % field)
		if package.has(field) and typeof(package[field]) != TYPE_DICTIONARY and field not in ["schema", "world_id"]:
			errors.append("E_PACKAGE_TYPE: %s must be an object" % field)
	for field: Variant in package.keys():
		if not root_fields.has(field): errors.append("E_PACKAGE_FIELD: unknown %s" % String(field))
	var semantic_value: Variant = package.get("semantic", {})
	var digests_value: Variant = package.get("digests", {})
	var semantic: Dictionary = semantic_value if semantic_value is Dictionary else {}
	var digests: Dictionary = digests_value if digests_value is Dictionary else {}
	if not semantic_value is Dictionary: errors.append("E_PACKAGE_TYPE: semantic must be an object")
	if not digests_value is Dictionary: errors.append("E_PACKAGE_TYPE: digests must be an object")
	if typeof(package.get("world_id")) != TYPE_STRING or String(package.get("world_id", "")).is_empty():
		errors.append("E_PACKAGE_ID: world_id must be a non-empty string")
	var frame_value: Variant = package.get("coordinate_frame", {})
	var coordinate_frame: Dictionary = frame_value if frame_value is Dictionary else {}
	if not frame_value is Dictionary: errors.append("E_PACKAGE_TYPE: coordinate_frame must be an object")
	if String(coordinate_frame.get("id", "")) != "plan_xz_q48/1" or int(coordinate_frame.get("q_per_cell", 0)) != 48:
		errors.append("E_PACKAGE_COORDINATE: unsupported or missing coordinate frame")
	if String(semantic.get("kind", "")).is_empty(): errors.append("E_PACKAGE_SEMANTIC: semantic.kind is required")
	if typeof(digests.get("semantic_sha256", "")) != TYPE_STRING or typeof(digests.get("presentation_sha256", "")) != TYPE_STRING:
		errors.append("E_PACKAGE_DIGESTS: semantic and presentation SHA-256 values are required")
	if semantic_value is Dictionary and String(digests.get("semantic_sha256", "")) != CANONICAL.sha256(semantic):
		errors.append("E_PACKAGE_SEMANTIC_HASH: semantic digest mismatch")
	var presentation_value: Variant = package.get("presentation", {})
	var presentation: Dictionary = presentation_value if presentation_value is Dictionary else {}
	if not presentation_value is Dictionary: errors.append("E_PACKAGE_TYPE: presentation must be an object")
	if presentation_value is Dictionary and String(digests.get("presentation_sha256", "")) != CANONICAL.sha256(presentation):
		errors.append("E_PACKAGE_PRESENTATION_HASH: presentation digest mismatch")
	var value_errors := CANONICAL.validate_value(semantic)
	errors.append_array(value_errors)
	match String(semantic.get("kind", "")):
		"inland_neighborhood": errors.append_array(_validate_inland(semantic))
		"standalone_interior": errors.append_array(_validate_interior(semantic))
		"coastal_neighborhood": errors.append_array(_validate_coastal(semantic))
		"": pass # Already reported as a missing semantic.kind above.
		_: errors.append("E_PACKAGE_SEMANTIC_KIND: unsupported semantic.kind")
	return {"ok": errors.is_empty(), "errors": errors}

## Independent package-level coastal oracle. Recomputes bounds, segment voids,
## road connectivity and the narrow beach-crossing exception from frozen data.
static func _validate_coastal(semantic: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var extent_value: Variant = semantic.get("extent_cells", [])
	if not extent_value is Array:
		return ["E_COAST_ORACLE_EXTENT: extent_cells must be an array"]
	var extent: Array = extent_value
	if extent.size() != 2:
		return ["E_COAST_ORACLE_EXTENT: extent_cells must contain width and height"]
	var width := int(extent[0]); var height := int(extent[1])
	if width <= 0 or height <= 0:
		errors.append("E_COAST_ORACLE_EXTENT: width and height must be positive")
	var topology_value: Variant = semantic.get("topology", {})
	if not topology_value is Dictionary:
		return ["E_COAST_ORACLE_TOPOLOGY: topology must be an object"]
	var topology: Dictionary = topology_value
	var shoreline_value: Variant = topology.get("shoreline", {})
	if not shoreline_value is Dictionary:
		return ["E_COAST_ORACLE_SHORELINE: shoreline must be an object"]
	var shoreline: Dictionary = shoreline_value
	var bands_value: Variant = shoreline.get("bands", [])
	var offsets_value: Variant = shoreline.get("offsets_cells", {})
	if not bands_value is Array: errors.append("E_COAST_ORACLE_BANDS: bands must be an array")
	if not offsets_value is Dictionary: errors.append("E_COAST_ORACLE_OFFSETS: offsets_cells must be an object")
	var bands: Array = bands_value if bands_value is Array else []
	var offsets: Dictionary = offsets_value if offsets_value is Dictionary else {}
	if String(shoreline.get("sea_side", "")) != "east": errors.append("E_COAST_ORACLE_SEA_SIDE: this coastal profile requires east-side water")
	if bands.size() < 2: errors.append("E_COAST_ORACLE_BANDS: at least two shoreline controls are required")
	var previous_z := -1
	for point: Variant in bands:
		if not point is Dictionary:
			errors.append("E_COAST_ORACLE_BAND: controls must be objects"); continue
		var z := int(point.get("z", -1)); var edge := int(point.get("dune_edge_x", -1))
		if z <= previous_z or z < 0 or z > height or edge <= 0 or edge >= width:
			errors.append("E_COAST_ORACLE_BAND_ORDER: invalid control at z=%d" % z)
		previous_z = z
	var dune_toe := int(offsets.get("dune_toe", 0)); var high_water := int(offsets.get("high_water", 0)); var outer_water := int(offsets.get("outer_intertidal", 0))
	if dune_toe <= 0 or high_water <= dune_toe or outer_water <= high_water:
		errors.append("E_COAST_ORACLE_OFFSETS: require 0 < dune toe < high water < outer intertidal")
	for point: Variant in bands:
		if not point is Dictionary: continue
		if int(point.get("dune_edge_x", -1)) + outer_water >= width:
			errors.append("E_COAST_ORACLE_BAND_BOUNDS: intertidal envelope leaves map"); break
	var nodes_by_id := {}
	var adjacency := {}
	var nodes_value: Variant = topology.get("road_nodes", [])
	var roads_value: Variant = topology.get("roads", [])
	var buildings_value: Variant = topology.get("buildings", [])
	if not nodes_value is Array: errors.append("E_COAST_ORACLE_NODES: road_nodes must be an array")
	if not roads_value is Array: errors.append("E_COAST_ORACLE_ROADS: roads must be an array")
	if not buildings_value is Array: errors.append("E_COAST_ORACLE_BUILDINGS: buildings must be an array")
	var road_nodes: Array = nodes_value if nodes_value is Array else []
	var roads: Array = roads_value if roads_value is Array else []
	var buildings: Array = buildings_value if buildings_value is Array else []
	for node: Variant in road_nodes:
		if not node is Dictionary: errors.append("E_COAST_ORACLE_NODE: node must be an object"); continue
		var id := String(node.get("id", "")); var at_value: Variant = node.get("at", [])
		if not at_value is Array: errors.append("E_COAST_ORACLE_NODE: node %s coordinates must be an array" % id); continue
		var at: Array = at_value
		if id.is_empty() or nodes_by_id.has(id) or at.size() != 2:
			errors.append("E_COAST_ORACLE_NODE: invalid or duplicate node %s" % id); continue
		if int(at[0]) < 0 or int(at[0]) > width or int(at[1]) < 0 or int(at[1]) > height:
			errors.append("E_COAST_ORACLE_NODE_BOUNDS: node %s leaves map" % id)
		nodes_by_id[id] = at; adjacency[id] = []
	var road_ids := {}
	var crossing_ids_value: Variant = shoreline.get("crossing_ids", [])
	if not crossing_ids_value is Array: errors.append("E_COAST_ORACLE_CROSSING_IDS: crossing_ids must be an array")
	var crossing_ids: Array = crossing_ids_value if crossing_ids_value is Array else []
	var seen_crossings := {}
	for road: Variant in roads:
		if not road is Dictionary: errors.append("E_COAST_ORACLE_ROAD: road must be an object"); continue
		var id := String(road.get("id", "")); var from_id := String(road.get("from", "")); var to_id := String(road.get("to", ""))
		if id.is_empty() or road_ids.has(id): errors.append("E_COAST_ORACLE_ROAD_ID: invalid or duplicate road %s" % id); continue
		road_ids[id] = road
		if not nodes_by_id.has(from_id) or not nodes_by_id.has(to_id):
			errors.append("E_COAST_ORACLE_ROAD_ENDPOINT: %s references an unknown road node" % id); continue
		var role := String(road.get("class", "")); var line_value: Variant = road.get("via", [])
		if not line_value is Array: errors.append("E_COAST_ORACLE_ROAD_VIA: %s via must be an array" % id)
		var line: Array = line_value if line_value is Array else []
		if not ["main", "local", "promenade", "beach_crossing"].has(role): errors.append("E_COAST_ORACLE_ROAD_CLASS: %s has unknown class %s" % [id, role])
		if float(road.get("width_cells", 0)) <= 0.0: errors.append("E_COAST_ORACLE_ROAD_WIDTH: %s has nonpositive width" % id)
		if line.size() < 2: line = [nodes_by_id[from_id], nodes_by_id[to_id]]
		elif line.front() != nodes_by_id[from_id] or line.back() != nodes_by_id[to_id]: errors.append("E_COAST_ORACLE_ROAD_VIA: %s via endpoints differ from graph sockets" % id)
		var valid_line := line.size() >= 2
		for path_point: Variant in line:
			if not path_point is Array or path_point.size() != 2:
				errors.append("E_COAST_ORACLE_ROAD_POINT: %s has malformed path point" % id)
				valid_line = false
				break
		if not valid_line: continue
		adjacency[from_id].append(to_id); adjacency[to_id].append(from_id)
		var penetrated := false
		var radius := float(road.get("width_cells", 0)) * 0.5
		for segment_index in range(line.size() - 1):
			var a: Variant = line[segment_index]; var b: Variant = line[segment_index + 1]
			var start := Vector2(float(a[0]), float(a[1])); var finish := Vector2(float(b[0]), float(b[1]))
			if minf(start.x, finish.x) < 0.0 or maxf(start.x, finish.x) > width or minf(start.y, finish.y) < 0.0 or maxf(start.y, finish.y) > height:
				errors.append("E_COAST_ORACLE_ROAD_BOUNDS: %s leaves map" % id)
			var samples := maxi(1, ceili(start.distance_to(finish) * 2.0))
			for sample_index in range(samples + 1):
				var sample := start.lerp(finish, float(sample_index) / float(samples))
				if sample.x + radius > _coastal_dune_edge_x(sample.y, bands): penetrated = true
		if role == "beach_crossing":
			var crossing_id := String(road.get("crossing_id", ""))
			if crossing_id != id or not crossing_ids.has(crossing_id) or seen_crossings.has(crossing_id):
				errors.append("E_COAST_ORACLE_CROSSING_SCOPE: %s lacks a unique declared crossing permit" % id)
			else: seen_crossings[crossing_id] = true
			if not penetrated: errors.append("E_COAST_ORACLE_CROSSING_MISSED: %s does not cross the dune edge" % id)
			if line.size() >= 2:
				var first: Array = line.front(); var last: Array = line.back()
				if float(first[0]) + radius >= _coastal_dune_edge_x(float(first[1]), bands) or float(last[0]) + radius < _coastal_dune_edge_x(float(last[1]), bands) + dune_toe or float(last[0]) + radius >= _coastal_dune_edge_x(float(last[1]), bands) + high_water:
					errors.append("E_COAST_ORACLE_CROSSING_LANDING: %s must connect inland to the declared dry beach path" % id)
		elif penetrated:
			errors.append("E_COAST_ORACLE_EXCLUSION: non-crossing road %s enters the dune exclusion" % id)
		elif road.has("crossing_id"):
			errors.append("E_COAST_ORACLE_CROSSING_SCOPE: non-crossing road %s carries a crossing permit" % id)
	for crossing_id: Variant in crossing_ids:
		if not seen_crossings.has(String(crossing_id)): errors.append("E_COAST_ORACLE_CROSSING_UNUSED: %s has no matching route" % String(crossing_id))
	if not nodes_by_id.is_empty():
		var keys: Array = nodes_by_id.keys(); keys.sort()
		var visited := {String(keys[0]): true}; var queue: Array[String] = [String(keys[0])]
		while not queue.is_empty():
			var current := queue.pop_front()
			for neighbor: String in adjacency[current]:
				if not visited.has(neighbor): visited[neighbor] = true; queue.append(neighbor)
		if visited.size() != nodes_by_id.size(): errors.append("E_COAST_ORACLE_DISCONNECTED: only %d of %d road nodes are connected" % [visited.size(), nodes_by_id.size()])
	var building_ids := {}
	var occupied: Array[Array] = []
	for building: Variant in buildings:
		if not building is Dictionary: errors.append("E_COAST_ORACLE_BUILDING: building must be an object"); continue
		var id := String(building.get("id", "")); var box_value: Variant = building.get("box", [])
		if not box_value is Array: errors.append("E_COAST_ORACLE_BUILDING: %s box must be an array" % id); continue
		var box: Array = box_value
		if building.has("crossing_id"): errors.append("E_COAST_ORACLE_BUILDING_CROSSING_PERMIT: beach-crossing permissions cannot be assigned to buildings (%s)" % id)
		if id.is_empty() or building_ids.has(id) or box.size() != 4: errors.append("E_COAST_ORACLE_BUILDING: invalid or duplicate building %s" % id); continue
		building_ids[id] = true
		var bx := int(box[0]); var by := int(box[1]); var bw := int(box[2]); var bh := int(box[3])
		if bw <= 0 or bh <= 0 or bx < 0 or by < 0 or bx + bw > width or by + bh > height:
			errors.append("E_COAST_ORACLE_BUILDING_BOUNDS: %s leaves map" % id); continue
		var shape := String(building.get("shape", "")); var segments_value: Variant = building.get("segments", [])
		if not ["rectangle", "row", "L", "U", "bar", "shallow_bar", "open"].has(shape): errors.append("E_COAST_ORACLE_SHAPE: %s has an unknown footprint shape" % id)
		var segments: Array = segments_value if segments_value is Array else []
		if not segments_value is Array: errors.append("E_COAST_ORACLE_SEGMENTS: %s segments must be an array" % id)
		if segments.is_empty(): errors.append("E_COAST_ORACLE_SEGMENTS: %s has no structural segment" % id); continue
		var segment_ids := {}; var covered_area := 0
		for segment: Variant in segments:
			if not segment is Dictionary: errors.append("E_COAST_ORACLE_SEGMENT: %s has malformed segment" % id); continue
			var segment_id := String(segment.get("id", "")); var rect: Array = segment.get("rect", [])
			if segment_id.is_empty() or segment_ids.has(segment_id) or rect.size() != 4: errors.append("E_COAST_ORACLE_SEGMENT: %s has invalid segment id/rectangle" % id); continue
			segment_ids[segment_id] = true
			var sx := int(rect[0]); var sy := int(rect[1]); var sw := int(rect[2]); var sh := int(rect[3])
			if sw <= 0 or sh <= 0 or sx < bx or sy < by or sx + sw > bx + bw or sy + sh > by + bh:
				errors.append("E_COAST_ORACLE_SEGMENT_BOUNDS: %s/%s leaves its envelope" % [id, segment_id]); continue
			for prior: Array in occupied:
				if String(prior[4]) != id: continue
				if _rect_overlap([sx, sy, sw, sh], prior): errors.append("E_COAST_ORACLE_SEGMENT_OVERLAP: %s/%s overlaps %s/%s" % [id, segment_id, id, String(prior[5])])
			occupied.append([sx, sy, sw, sh, id, segment_id]); covered_area += sw * sh
			for z in range(sy, sy + sh):
				var dune_edge := _coastal_dune_edge_x(float(z), bands)
				if float(sx + sw) > dune_edge:
					errors.append("E_COAST_ORACLE_BUILDING_EXCLUSION: %s reaches the dune band" % id); break
		if ["rectangle", "row", "bar", "shallow_bar", "open"].has(shape) and covered_area != bw * bh:
			errors.append("E_COAST_ORACLE_MASSING_COVERAGE: %s solid shape does not cover its declared envelope" % id)
		if ["L", "U"].has(shape):
			if segments.size() < 2 or covered_area >= bw * bh: errors.append("E_COAST_ORACLE_VOID: %s must have joined segments and a real exterior void" % id)
			if shape == "U" and not _coastal_cell_is_void(bx + bw / 2, by + bh / 2, id, occupied):
				errors.append("E_COAST_ORACLE_COURT: %s courtyard center is structurally occupied" % id)
		var entry_value: Variant = building.get("entry", {})
		if not entry_value is Dictionary: errors.append("E_COAST_ORACLE_ENTRY: %s entry must be an object" % id); continue
		var entry: Dictionary = entry_value
		var entry_at_value: Variant = entry.get("at", [])
		if not entry_at_value is Array: errors.append("E_COAST_ORACLE_ENTRY: %s entrance coordinates must be an array" % id); continue
		var at: Array = entry_at_value
		if at.size() != 2 or not road_ids.has(String(entry.get("road", ""))):
			errors.append("E_COAST_ORACLE_ENTRY: %s has no graph-linked entrance" % id)
		elif int(at[0]) < bx or int(at[0]) > bx + bw or int(at[1]) < by or int(at[1]) > by + bh:
			errors.append("E_COAST_ORACLE_ENTRY_BOUNDS: %s entrance leaves its building envelope" % id)
		if not building.has("interior") or not building["interior"] is Dictionary:
			errors.append("E_COAST_ORACLE_INTERIOR: %s has no compiled spatial program" % id)
	return errors

static func _coastal_dune_edge_x(z: float, bands: Array) -> float:
	if bands.is_empty(): return 1.0e9
	for index in range(bands.size() - 1):
		if not bands[index] is Dictionary or not bands[index + 1] is Dictionary: return 1.0e9
		var a: Dictionary = bands[index]; var b: Dictionary = bands[index + 1]
		if not a.has("z") or not a.has("dune_edge_x") or not b.has("z") or not b.has("dune_edge_x"): return 1.0e9
		if z <= float(b["z"]): return lerpf(float(a["dune_edge_x"]), float(b["dune_edge_x"]), inverse_lerp(float(a["z"]), float(b["z"]), z))
	if not bands.back() is Dictionary or not bands.back().has("dune_edge_x"): return 1.0e9
	return float(bands.back()["dune_edge_x"])

static func _coastal_cell_is_void(x: int, y: int, building_id: String, occupied: Array[Array]) -> bool:
	for rect: Array in occupied:
		if String(rect[4]) == building_id and x >= int(rect[0]) and x < int(rect[0]) + int(rect[2]) and y >= int(rect[1]) and y < int(rect[1]) + int(rect[3]): return false
	return true

## Recompute geometry and connectivity from package facts instead of trusting operator flags.
static func _validate_inland(semantic: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var extent: Array = semantic.get("extent_cells", [])
	if extent.size() != 2: return ["E_INLAND_ORACLE_EXTENT: extent_cells must contain width and height"]
	var width := int(extent[0]); var height := int(extent[1])
	var buildings_by_id := {}
	var occupied: Array[Array] = []
	for building: Dictionary in semantic.get("buildings", []):
		var id := String(building.get("id", "")); var box: Array = building.get("box", [])
		if id.is_empty() or buildings_by_id.has(id): errors.append("E_INLAND_ORACLE_ID: empty or duplicate building id %s" % id); continue
		if box.size() != 4: errors.append("E_INLAND_ORACLE_BOX: building %s has no rectangle" % id); continue
		var x := int(box[0]); var y := int(box[1]); var w := int(box[2]); var h := int(box[3])
		if w <= 0 or h <= 0 or x < 0 or y < 0 or x + w > width or y + h > height: errors.append("E_INLAND_ORACLE_BOUNDS: building %s leaves the map" % id)
		for previous: Array in occupied:
			if _rect_overlap([x, y, w, h], previous): errors.append("E_INLAND_ORACLE_OVERLAP: buildings %s and %s overlap" % [id, previous[4]])
		occupied.append([x, y, w, h, id]); buildings_by_id[id] = building
	var parcels_by_id := {}
	for parcel: Dictionary in semantic.get("parcels", []):
		var id := String(parcel.get("id", "")); var rect: Array = parcel.get("bounds", [])
		if id.is_empty() or parcels_by_id.has(id) or rect.size() != 4: errors.append("E_INLAND_ORACLE_PARCEL: invalid or duplicate parcel %s" % id); continue
		parcels_by_id[id] = rect
	for id: String in buildings_by_id:
		var building: Dictionary = buildings_by_id[id]
		var parcel_id := String(building.get("parcel_id", "")); var box: Array = building.get("box", [])
		if not parcels_by_id.has(parcel_id): errors.append("E_INLAND_ORACLE_PARCEL_LINK: building %s has no parcel" % id); continue
		var rect: Array = parcels_by_id[parcel_id]
		if box.size() == 4 and (int(box[0]) < int(rect[0]) or int(box[1]) < int(rect[1]) or int(box[0]) + int(box[2]) > int(rect[0]) + int(rect[2]) or int(box[1]) + int(box[3]) > int(rect[1]) + int(rect[3])):
			errors.append("E_INLAND_ORACLE_PARCEL_BOUNDS: building %s leaves parcel %s" % [id, parcel_id])
	var graph_value: Variant = semantic.get("street_graph")
	var graph: Dictionary = graph_value if graph_value is Dictionary else {}
	var node_records: Variant = graph.get("nodes")
	var edge_records: Variant = graph.get("edges")
	if not node_records is Array or not edge_records is Array or node_records.is_empty() or edge_records.is_empty():
		errors.append("E_INLAND_ORACLE_GRAPH: street graph needs nodes and edges")
	if not node_records is Array: node_records = []
	if not edge_records is Array: edge_records = []
	var nodes := {}
	for node_value: Variant in node_records:
		if not node_value is Dictionary:
			errors.append("E_INLAND_ORACLE_NODE: road node must be an object")
			continue
		var node: Dictionary = node_value
		var id := String(node.get("id", "")); var at: Array = node.get("at", [])
		if id.is_empty() or nodes.has(id) or at.size() != 2: errors.append("E_INLAND_ORACLE_NODE: invalid road node %s" % id); continue
		if int(at[0]) < 0 or int(at[0]) > width or int(at[1]) < 0 or int(at[1]) > height: errors.append("E_INLAND_ORACLE_NODE_BOUNDS: road node %s leaves map" % id)
		nodes[id] = at
	var adjacency := {}
	for id: String in nodes: adjacency[id] = []
	for edge_value: Variant in edge_records:
		if not edge_value is Dictionary:
			errors.append("E_INLAND_ORACLE_EDGE: road edge must be an object")
			continue
		var edge: Dictionary = edge_value
		var from_id := String(edge.get("from", "")); var to_id := String(edge.get("to", ""))
		if not nodes.has(from_id) or not nodes.has(to_id): errors.append("E_INLAND_ORACLE_EDGE: edge has unknown endpoint"); continue
		adjacency[from_id].append(to_id); adjacency[to_id].append(from_id)
	if not nodes.is_empty():
		var visited := {}; var queue: Array[String] = [String(nodes.keys()[0])]; visited[queue[0]] = true
		while not queue.is_empty():
			var current := queue.pop_front()
			for next: String in adjacency[current]:
				if not visited.has(next): visited[next] = true; queue.append(next)
		if visited.size() != nodes.size(): errors.append("E_INLAND_ORACLE_DISCONNECTED: road graph has unreachable nodes")
	errors.append_array(_validate_inland_programs(semantic, buildings_by_id))
	return errors

static func _validate_inland_programs(semantic: Dictionary, buildings_by_id: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var rooms_by_id := {}; var rooms_by_building := {}; var room_area_by_building := {}
	for raw_room: Variant in semantic.get("rooms", []):
		if not raw_room is Dictionary: errors.append("E_INLAND_PROGRAM_ROOM: room entry is not an object"); continue
		var room: Dictionary = raw_room; var id := String(room.get("id", "")); var building_id := String(room.get("building_id", "")); var rect: Array = room.get("bounds", [])
		if id.is_empty() or rooms_by_id.has(id) or not buildings_by_id.has(building_id) or rect.size() != 4:
			errors.append("E_INLAND_PROGRAM_ROOM: invalid or duplicate room %s" % id); continue
		var building_box: Array = buildings_by_id[building_id].get("box", [])
		var x := int(rect[0]); var y := int(rect[1]); var w := int(rect[2]); var h := int(rect[3])
		if w <= 0 or h <= 0 or x < int(building_box[0]) or y < int(building_box[1]) or x + w > int(building_box[0]) + int(building_box[2]) or y + h > int(building_box[1]) + int(building_box[3]):
			errors.append("E_INLAND_PROGRAM_ROOM_BOUNDS: room %s leaves its building" % id)
		if String(room.get("access", "")) not in ["public", "staff", "owner"]: errors.append("E_INLAND_PROGRAM_ROOM_ACCESS: room %s has unknown access" % id)
		for previous: Dictionary in rooms_by_building.get(building_id, []):
			if _rect_overlap(rect, previous.get("bounds", [])): errors.append("E_INLAND_PROGRAM_ROOM_OVERLAP: rooms %s and %s overlap" % [id, String(previous.get("id", ""))])
		rooms_by_id[id] = room
		if not rooms_by_building.has(building_id): rooms_by_building[building_id] = []
		rooms_by_building[building_id].append(room)
		room_area_by_building[building_id] = int(room_area_by_building.get(building_id, 0)) + w * h
	for building_id: String in buildings_by_id:
		var box: Array = buildings_by_id[building_id].get("box", [])
		if not rooms_by_building.has(building_id) or int(room_area_by_building.get(building_id, 0)) != int(box[2]) * int(box[3]):
			errors.append("E_INLAND_PROGRAM_COVERAGE: rooms do not cover building %s exactly" % building_id)
	var profiles: Dictionary = semantic.get("access_profiles", {})
	var portals_by_id := {}; var building_portals := {}
	for raw_portal: Variant in semantic.get("portals", []):
		if not raw_portal is Dictionary: errors.append("E_INLAND_PROGRAM_PORTAL: portal entry is not an object"); continue
		var portal: Dictionary = raw_portal; var id := String(portal.get("id", "")); var building_id := String(portal.get("building_id", ""))
		var from_room := String(portal.get("from_room", "")); var to_room := String(portal.get("to_room", ""))
		var from: Array = portal.get("from", []); var to: Array = portal.get("to", [])
		var access := String(portal.get("access", ""))
		if id.is_empty() or portals_by_id.has(id) or not buildings_by_id.has(building_id) or from.size() != 2 or to.size() != 2:
			errors.append("E_INLAND_PROGRAM_PORTAL: invalid or duplicate portal %s" % id); continue
		if (from_room != "exterior" and not rooms_by_id.has(from_room)) or (to_room != "exterior" and not rooms_by_id.has(to_room)):
			errors.append("E_INLAND_PROGRAM_PORTAL_ROOM: portal %s references a missing room" % id); continue
		if access not in ["public", "staff", "owner"]: errors.append("E_INLAND_PROGRAM_PORTAL_ACCESS: portal %s has unknown access" % id)
		if absi(int(from[0]) - int(to[0])) + absi(int(from[1]) - int(to[1])) != 1: errors.append("E_INLAND_PROGRAM_PORTAL_GEOMETRY: portal %s endpoints are not adjacent" % id)
		if from_room != "exterior" and not _point_in_room(from, rooms_by_id[from_room]): errors.append("E_INLAND_PROGRAM_PORTAL_GEOMETRY: portal %s source is outside its room" % id)
		if to_room != "exterior" and not _point_in_room(to, rooms_by_id[to_room]): errors.append("E_INLAND_PROGRAM_PORTAL_GEOMETRY: portal %s target is outside its room" % id)
		portals_by_id[id] = portal
		if not building_portals.has(building_id): building_portals[building_id] = []
		building_portals[building_id].append(portal)
	for profile: String in profiles:
		var allowed: Variant = profiles[profile]
		if not allowed is Array: errors.append("E_INLAND_PROGRAM_PROFILE: %s must list room access classes" % profile); continue
		var reached := _inland_room_reachability(profile, building_portals.values())
		for room_id: String in rooms_by_id:
			var room_access := String(rooms_by_id[room_id].get("access", ""))
			if allowed.has(room_access) and not reached.get(room_id, false): errors.append("E_INLAND_PROGRAM_UNREACHABLE: profile %s cannot reach %s" % [profile, room_id])
	var affordance_ids := {}
	for raw_slot: Variant in semantic.get("affordances", []):
		if not raw_slot is Dictionary: errors.append("E_INLAND_PROGRAM_AFFORDANCE: slot entry is not an object"); continue
		var slot: Dictionary = raw_slot; var id := String(slot.get("id", "")); var room_id := String(slot.get("room_id", ""))
		var position: Array = slot.get("position", []); var approach: Array = slot.get("approach", []); var route: Array = slot.get("route", [])
		if id.is_empty() or affordance_ids.has(id) or not rooms_by_id.has(room_id): errors.append("E_INLAND_PROGRAM_AFFORDANCE: invalid or duplicate slot %s" % id); continue
		var room: Dictionary = rooms_by_id[room_id]; var access := String(slot.get("access", "")); var capacity := int(slot.get("capacity", 0))
		if access not in ["public", "staff", "owner"] or capacity < 1 or String(slot.get("action_type", "")).is_empty(): errors.append("E_INLAND_PROGRAM_AFFORDANCE_FIELDS: slot %s has invalid action/access/capacity" % id)
		if access == "public" and String(room.get("access", "")) != "public": errors.append("E_INLAND_PROGRAM_AFFORDANCE_ACCESS: public slot %s is in a restricted room" % id)
		if position.size() != 2 or approach.size() != 2 or not _point_in_room(position, room) or not _point_in_room(approach, room): errors.append("E_INLAND_PROGRAM_AFFORDANCE_BOUNDS: slot %s leaves its room" % id)
		elif absi(int(position[0]) - int(approach[0])) + absi(int(position[1]) - int(approach[1])) != 1: errors.append("E_INLAND_PROGRAM_AFFORDANCE_APPROACH: slot %s approach is not adjacent" % id)
		if route.size() < 2: errors.append("E_INLAND_PROGRAM_ROUTE: slot %s has no declared room route" % id)
		for point: Array in route:
			if point.size() != 2 or not _point_in_room(point, room): errors.append("E_INLAND_PROGRAM_ROUTE_BOUNDS: route for %s leaves its room" % id); break
		for index in range(route.size() - 1):
			var a: Array = route[index]; var b: Array = route[index + 1]
			if a.size() == 2 and b.size() == 2 and int(a[0]) != int(b[0]) and int(a[1]) != int(b[1]): errors.append("E_INLAND_PROGRAM_ROUTE_SHAPE: route for %s is not orthogonal" % id)
		var profile := "public" if access == "public" else access
		if not _inland_room_reachability(profile, building_portals.values()).get(room_id, false): errors.append("E_INLAND_PROGRAM_AFFORDANCE_UNREACHABLE: slot %s is unreachable for %s" % [id, profile])
		affordance_ids[id] = true
	return errors

static func _inland_room_reachability(profile: String, portal_groups: Array) -> Dictionary:
	var portals: Array = []
	for group: Array in portal_groups: portals.append_array(group)
	var reached := {"exterior": true}; var queue: Array[String] = ["exterior"]
	while not queue.is_empty():
		var current := queue.pop_front()
		for portal: Dictionary in portals:
			var access := String(portal.get("access", ""))
			if access != "public" and access != profile: continue
			var next := ""
			if String(portal.get("from_room", "")) == current: next = String(portal.get("to_room", ""))
			elif String(portal.get("to_room", "")) == current: next = String(portal.get("from_room", ""))
			if not next.is_empty() and not reached.has(next): reached[next] = true; queue.append(next)
	return reached

static func _point_in_room(point: Array, room: Dictionary) -> bool:
	var rect: Array = room.get("bounds", [])
	return rect.size() == 4 and point.size() == 2 and int(point[0]) >= int(rect[0]) and int(point[0]) < int(rect[0]) + int(rect[2]) and int(point[1]) >= int(rect[1]) and int(point[1]) < int(rect[1]) + int(rect[3])

static func _validate_interior(semantic: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var extent: Array = semantic.get("extent_cells", [])
	if extent.size() != 2: return ["E_INTERIOR_ORACLE_EXTENT: extent_cells must contain width and depth"]
	var width := int(extent[0]); var depth := int(extent[1]); var room_by_id := {}; var room_area := 0
	var room_rects: Array[Array] = []
	for room: Dictionary in semantic.get("rooms", []):
		var id := String(room.get("id", "")); var rect: Array = room.get("bounds", [])
		if id.is_empty() or room_by_id.has(id) or rect.size() != 4: errors.append("E_INTERIOR_ORACLE_ROOM: invalid or duplicate room %s" % id); continue
		var x := int(rect[0]); var y := int(rect[1]); var w := int(rect[2]); var h := int(rect[3])
		if w <= 0 or h <= 0 or x < 0 or y < 0 or x + w > width or y + h > depth: errors.append("E_INTERIOR_ORACLE_ROOM_BOUNDS: room %s leaves envelope" % id)
		for previous: Array in room_rects:
			if _rect_overlap([x, y, w, h], previous): errors.append("E_INTERIOR_ORACLE_ROOM_OVERLAP: rooms overlap")
		room_rects.append([x, y, w, h]); room_area += w * h; room_by_id[id] = room
	if room_area != width * depth: errors.append("E_INTERIOR_ORACLE_ROOM_COVERAGE: rooms do not cover the envelope exactly")
	for profile: String in ["public", "staff"]:
		var reached := _independent_room_reachability("exterior", profile, semantic.get("portals", []))
		var declared: Dictionary = semantic.get("room_routes", {}).get(profile, {})
		if reached.keys().size() != declared.keys().size(): errors.append("E_INTERIOR_ORACLE_ACCESS: %s route declaration differs from portal graph" % profile)
		for room_id: String in reached:
			if not declared.has(room_id): errors.append("E_INTERIOR_ORACLE_ACCESS: %s cannot reach declared room %s" % [profile, room_id])
	for slot: Dictionary in semantic.get("affordances", []):
		var room_id := String(slot.get("room_id", "")); var access := String(slot.get("access", "")); var route: Array = slot.get("route", [])
		if not room_by_id.has(room_id): errors.append("E_INTERIOR_ORACLE_SLOT_ROOM: slot references missing room %s" % room_id); continue
		if access == "public" and String(room_by_id[room_id].get("access", "")) != "public": errors.append("E_INTERIOR_ORACLE_ACCESS: public slot is placed in restricted room %s" % room_id)
		var rect: Array = room_by_id[room_id].get("bounds", [])
		if route.size() < 2: errors.append("E_INTERIOR_ORACLE_ROUTE: slot %s has no route" % String(slot.get("id", ""))); continue
		for point: Array in route:
			if point.size() != 2 or int(point[0]) < int(rect[0]) or int(point[0]) >= int(rect[0]) + int(rect[2]) or int(point[1]) < int(rect[1]) or int(point[1]) >= int(rect[1]) + int(rect[3]):
				errors.append("E_INTERIOR_ORACLE_ROUTE_BOUNDS: route leaves room %s" % room_id); break
		for index in range(route.size() - 1):
			var a: Array = route[index]; var b: Array = route[index + 1]
			if int(a[0]) != int(b[0]) and int(a[1]) != int(b[1]): errors.append("E_INTERIOR_ORACLE_ROUTE_SHAPE: route segment is not Manhattan aligned")
	return errors

static func _independent_room_reachability(start_room: String, profile: String, portals: Array) -> Dictionary:
	var reached := {start_room: true}; var queue: Array[String] = [start_room]
	while not queue.is_empty():
		var current := queue.pop_front()
		for portal: Dictionary in portals:
			var access := String(portal.get("access", ""))
			if access != "public" and access != profile: continue
			var next := ""
			if String(portal.get("from_room", "")) == current: next = String(portal.get("to_room", ""))
			elif String(portal.get("to_room", "")) == current: next = String(portal.get("from_room", ""))
			if not next.is_empty() and not reached.has(next): reached[next] = true; queue.append(next)
	return reached

static func _rect_overlap(a: Array, b: Array) -> bool:
	return int(a[0]) < int(b[0]) + int(b[2]) and int(b[0]) < int(a[0]) + int(a[2]) and int(a[1]) < int(b[1]) + int(b[3]) and int(b[1]) < int(a[1]) + int(a[3])
