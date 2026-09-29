extends RefCounted
class_name CoastalPackageCompiler
## Deterministic authoring compiler for static coastal environment packages.
## It owns spatial definitions only; it never reads or mutates Sim.

const COMPILER_VERSION := "coast-compiler/1"
const REQUIRED_SCHEMA := "living-town.coastal/1"
const SHAPES := ["rectangle", "row", "L", "U", "bar", "shallow_bar", "open"]
const NAVIGATOR := preload("res://scripts/CoastalInteriorNavigation.gd")


static func compile_spec(spec: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	_reject_unknown_keys(spec, ["schema", "id", "title", "generator_version", "seed", "extent_cells", "pixels_per_cell", "resident_preview_count", "profiles", "shoreline", "district_styles", "road_nodes", "roads", "buildings"], "town", errors)
	if str(spec.get("schema", "")) != REQUIRED_SCHEMA:
		errors.append("E_SCHEMA: expected %s" % REQUIRED_SCHEMA)
	var extent: Array = spec.get("extent_cells", [])
	if extent.size() != 2 or int(extent[0]) <= 0 or int(extent[1]) <= 0:
		errors.append("E_EXTENT: extent_cells must contain two positive integers")
		return {"ok": false, "errors": errors}
	if int(spec.get("pixels_per_cell", 0)) != 48:
		errors.append("E_SCALE: this project package uses 48 pixels per cell")
	var profile: Dictionary = spec.get("profiles", {})
	_reject_unknown_keys(profile, ["physical_geo_ref", "architecture_style_ref", "lighting_climate_ref", "water_policy_ref", "water_mode"], "profiles", errors)
	for required_profile: String in ["physical_geo_ref", "architecture_style_ref", "lighting_climate_ref", "water_policy_ref", "water_mode"]:
		if not profile.has(required_profile) or str(profile.get(required_profile, "")).is_empty():
			errors.append("E_PROFILE: missing required profile reference '%s'" % required_profile)
	if str(profile.get("water_policy_ref", "")) != "F0_frozen_walkability/1":
		errors.append("E_WATER_POLICY: coastal S1 requires frozen F0 walkability")
	if str(profile.get("water_mode", "")) != "decorative_frozen_envelope":
		errors.append("E_WATER_MODE: water rendering cannot own passability")
	_validate_shoreline(spec.get("shoreline", {}), int(extent[0]), int(extent[1]), errors)
	var node_by_id := _index_by_id(spec.get("road_nodes", []), "road_nodes", errors)
	var road_by_id := _index_by_id(spec.get("roads", []), "roads", errors)
	_validate_roads(spec.get("roads", []), node_by_id, spec.get("shoreline", {}), errors)
	_validate_buildings(spec.get("buildings", []), spec.get("district_styles", []), road_by_id, spec.get("shoreline", {}), int(extent[0]), int(extent[1]), errors)
	_validate_road_corridors(spec.get("roads", []), spec.get("road_nodes", []), spec.get("buildings", []), errors)
	_validate_access_paths(spec.get("buildings", []), road_by_id, node_by_id, spec.get("roads", []), spec.get("road_nodes", []), spec.get("shoreline", {}), int(extent[0]), int(extent[1]), errors)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}

	var topology := {
		"extent_cells": extent.duplicate(),
		"pixels_per_cell": int(spec["pixels_per_cell"]),
		"physical_geo_ref": str(profile["physical_geo_ref"]),
		"water_policy_ref": str(profile["water_policy_ref"]),
		"interior_navigation": {"model": "rectangular_room_cell_bfs/1", "cell_q": 48, "provisional_actor_radius_q": 20, "access_profile": ["resident", "staff"], "furniture_obstacles_included": false, "bound_to_sim": false},
		"shoreline": spec["shoreline"],
		"road_nodes": spec["road_nodes"],
		"roads": spec["roads"],
		"buildings": _semantic_buildings(spec["buildings"])
	}
	var building_appearance := {}
	for building: Dictionary in spec.get("buildings", []):
		if building.has("appearance"):
			building_appearance[str(building.get("id", ""))] = building["appearance"]
	var render := {
		"architecture_style_ref": str(profile.get("architecture_style_ref", "")),
		"lighting_climate_ref": str(profile.get("lighting_climate_ref", "")),
		"district_styles": spec.get("district_styles", []),
		"building_appearance": building_appearance,
		"visual_seed": int(spec.get("seed", 0)),
		"render_profile": "code_only_2d"
	}
	var semantic_hash := _sha256(canonical_json(topology))
	var render_hash := _sha256(canonical_json(render))
	var source_hash := _sha256(canonical_json(spec))
	var package := {
		"package_schema": "living-town.coastal-package/1",
		"town_id": str(spec.get("id", "")),
		"title": str(spec.get("title", spec.get("id", "Coastal neighborhood"))),
		"manifest": {
			"compiler": COMPILER_VERSION,
			"source_sha256": source_hash,
			"topology_sha256": semantic_hash,
			"render_sha256": render_hash,
			"blender_required_at_runtime": false,
			"simulation_state_embedded": false
		},
		"topology": topology,
		"render": render
	}
	return {"ok": true, "errors": [], "package": package}


static func validate_package(package: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not package is Dictionary or str(package.get("package_schema", "")) != "living-town.coastal-package/1":
		return {"ok": false, "errors": ["E_PACKAGE_SCHEMA: unsupported coastal package"]}
	for key: String in ["manifest", "topology", "render"]:
		if not package.get(key, {}) is Dictionary:
			errors.append("E_PACKAGE_SECTION: %s must be an object" % key)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var manifest: Dictionary = package["manifest"]
	var topology_hash := _sha256(canonical_json(package["topology"]))
	var render_hash := _sha256(canonical_json(package["render"]))
	if topology_hash != str(manifest.get("topology_sha256", "")):
		errors.append("E_PACKAGE_TOPOLOGY_HASH: topology does not match its manifest")
	if render_hash != str(manifest.get("render_sha256", "")):
		errors.append("E_PACKAGE_RENDER_HASH: render profile does not match its manifest")
	if str(manifest.get("compiler", "")) != COMPILER_VERSION:
		errors.append("E_PACKAGE_COMPILER: unsupported package compiler version")
	return {"ok": errors.is_empty(), "errors": errors}


static func canonical_json(value: Variant) -> String:
	return JSON.stringify(_canonical(value), "", false, true)


static func _canonical(value: Variant) -> Variant:
	if value is float:
		var nearest_integer: float = round(value)
		if is_equal_approx(value, nearest_integer):
			return int(nearest_integer)
		return float(round(value * 1000000.0)) / 1000000.0
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var result := {}
		for key: Variant in keys:
			result[str(key)] = _canonical(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_canonical(item))
		return result
	return value


static func _semantic_buildings(buildings: Array) -> Array:
	var result: Array = []
	for building: Dictionary in buildings:
		var semantic := building.duplicate(true)
		semantic.erase("appearance")
		var interior: Dictionary = semantic.get("interior", {})
		var compiled_routes := {}
		for slot: Dictionary in interior.get("slots", []):
			var route: Dictionary = NAVIGATOR.route_to_slot(interior, slot)
			if bool(route.get("ok", false)):
				compiled_routes[str(slot.get("id", ""))] = {"path_q": route["path_q"], "room_path": route["room_path"], "portal_path": route["portal_path"], "provisional_actor_radius_q": route["provisional_actor_radius_q"]}
		interior["compiled_routes"] = compiled_routes
		semantic["interior"] = interior
		result.append(semantic)
	return result


static func _sha256(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()


static func _index_by_id(items: Variant, label: String, errors: Array[String]) -> Dictionary:
	var indexed := {}
	if not items is Array:
		errors.append("E_%s: expected an array" % label.to_upper())
		return indexed
	for item: Variant in items:
		if not item is Dictionary:
			errors.append("E_%s: entries must be objects" % label.to_upper())
			continue
		var item_id := str(item.get("id", ""))
		if item_id.is_empty() or indexed.has(item_id):
			errors.append("E_ID: missing or duplicate %s id '%s'" % [label, item_id])
			continue
		indexed[item_id] = item
	return indexed


static func _reject_unknown_keys(value: Variant, allowed_keys: Array, label: String, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("E_SCHEMA_TYPE: %s must be an object" % label)
		return
	for key: Variant in value.keys():
		if not allowed_keys.has(str(key)):
			errors.append("E_SCHEMA_UNKNOWN: unsupported %s field '%s'" % [label, str(key)])


static func _validate_shoreline(shoreline: Variant, width: int, height: int, errors: Array[String]) -> void:
	if not shoreline is Dictionary:
		errors.append("E_SHORELINE: expected an object")
		return
	_reject_unknown_keys(shoreline, ["sea_side", "control_spacing_cells", "bands", "offsets_cells", "walkable_bands", "crossing_ids"], "shoreline", errors)
	var bands: Array = shoreline.get("bands", [])
	var offsets: Dictionary = shoreline.get("offsets_cells", {})
	_reject_unknown_keys(offsets, ["dune_toe", "high_water", "outer_intertidal"], "shoreline.offsets_cells", errors)
	if bands.size() < 2:
		errors.append("E_SHORELINE: at least two control points are required")
		return
	var previous_z := -1
	var previous_edge := -1
	for point: Variant in bands:
		if not point is Dictionary:
			errors.append("E_SHORELINE: control point must be an object")
			continue
		_reject_unknown_keys(point, ["z", "dune_edge_x"], "shoreline.band", errors)
		var z := int(point.get("z", -1))
		var edge := int(point.get("dune_edge_x", -1))
		if z <= previous_z or z < 0 or z > height or edge <= 0 or edge >= width:
			errors.append("E_SHORELINE_ORDER: invalid or unordered shoreline control at z=%d" % z)
		if previous_edge >= 0 and absi(edge - previous_edge) > 8:
			errors.append("E_SHORELINE_SLOPE: adjacent control points exceed the authored bend limit")
		previous_z = z
		previous_edge = edge
	var toe := int(offsets.get("dune_toe", 0))
	var high_water := int(offsets.get("high_water", 0))
	var outer := int(offsets.get("outer_intertidal", 0))
	if toe <= 0 or high_water <= toe or outer <= high_water:
		errors.append("E_SHORELINE_BANDS: require 0 < dune toe < high water < outer intertidal")
	for point: Variant in bands:
		var edge := int(point.get("dune_edge_x", -1))
		if edge + outer >= width:
			errors.append("E_SHORELINE_BOUNDS: intertidal band exceeds the map at z=%d" % int(point.get("z", -1)))
			break


static func _validate_roads(roads: Variant, nodes: Dictionary, shoreline: Variant, errors: Array[String]) -> void:
	var indexed := _index_by_id(roads, "roads", errors)
	if indexed.size() != 21:
		errors.append("E_ROAD_COUNT: S1 fixture requires 21 authored road edges, got %d" % indexed.size())
	var adjacency := {}
	for node_id: Variant in nodes.keys():
		adjacency[str(node_id)] = []
	var declared_crossings: Array = shoreline.get("crossing_ids", []) if shoreline is Dictionary else []
	var used_crossings := {}
	for road: Variant in roads:
		_reject_unknown_keys(road, ["id", "from", "to", "class", "width_cells", "crossing_id", "via"], "road", errors)
		var from_id := str(road.get("from", ""))
		var to_id := str(road.get("to", ""))
		if not nodes.has(from_id) or not nodes.has(to_id):
			errors.append("E_ROAD_SOCKET: %s references a missing endpoint" % str(road.get("id", "?")))
			continue
		var road_class := str(road.get("class", ""))
		if not ["main", "local", "promenade", "beach_crossing"].has(road_class):
			errors.append("E_ROAD_CLASS: %s has unsupported class '%s'" % [str(road.get("id", "?")), road_class])
		if float(road.get("width_cells", 0)) <= 0.0:
			errors.append("E_ROAD_WIDTH: %s must have positive corridor width" % str(road.get("id", "?")))
		adjacency[from_id].append(to_id)
		adjacency[to_id].append(from_id)
		if str(road.get("class", "")) == "beach_crossing":
			var crossing_id := str(road.get("crossing_id", ""))
			if crossing_id.is_empty() or crossing_id != str(road.get("id", "")) or not declared_crossings.has(crossing_id):
				errors.append("E_CROSSING_SCOPE: %s is not a declared crossing exception" % str(road.get("id", "?")))
			else:
				used_crossings[crossing_id] = true
		_validate_road_shore_clearance(road, nodes, shoreline, errors)
	for crossing_id: Variant in declared_crossings:
		if not used_crossings.has(str(crossing_id)):
			errors.append("E_CROSSING_UNUSED: declared crossing %s has no public route" % str(crossing_id))
	if nodes.size() > 0:
		var start := str(nodes.keys()[0])
		var seen := {start: true}
		var queue: Array[String] = [start]
		while not queue.is_empty():
			var current: String = queue.pop_front()
			for neighbor: String in adjacency.get(current, []):
				if not seen.has(neighbor):
					seen[neighbor] = true
					queue.append(neighbor)
		if seen.size() != nodes.size():
			errors.append("E_ROAD_CONNECTIVITY: %d of %d road nodes are connected" % [seen.size(), nodes.size()])


static func _validate_road_shore_clearance(road: Dictionary, nodes: Dictionary, shoreline: Variant, errors: Array[String]) -> void:
	if not shoreline is Dictionary:
		return
	var point_values: Array = road.get("via", [nodes[str(road["from"])]["at"], nodes[str(road["to"])]["at"]])
	if not road.has("via"):
		point_values = [nodes[str(road["from"])]["at"], nodes[str(road["to"])]["at"]]
	var bands: Array = shoreline.get("bands", [])
	var radius := float(road.get("width_cells", 0)) * 0.5
	var crosses := str(road.get("class", "")) == "beach_crossing"
	var penetrated := false
	for index in range(point_values.size() - 1):
		var a: Vector2 = Vector2(point_values[index][0], point_values[index][1])
		var b: Vector2 = Vector2(point_values[index + 1][0], point_values[index + 1][1])
		var steps := maxi(1, ceili(a.distance_to(b) * 2.0))
		for step in range(steps + 1):
			var sample := a.lerp(b, float(step) / float(steps))
			if sample.x + radius > _shoreline_edge_x(sample.y, bands):
				penetrated = true
				break
		if penetrated:
			break
	if penetrated and not crosses:
		errors.append("E_ROAD_COAST_EXCLUSION: %s reaches the dune exclusion without a crossing template" % str(road.get("id", "?")))
	if crosses and not penetrated:
		errors.append("E_CROSSING_NOT_CROSSING: %s does not reach across the authored dune edge" % str(road.get("id", "?")))
	if crosses and point_values.size() >= 2:
		var a: Vector2 = Vector2(point_values.front()[0], point_values.front()[1])
		var b: Vector2 = Vector2(point_values.back()[0], point_values.back()[1])
		if a.x + radius >= _shoreline_edge_x(a.y, bands) or b.x + radius < _shoreline_edge_x(b.y, bands) + float(shoreline.get("offsets_cells", {}).get("dune_toe", 0)):
			errors.append("E_CROSSING_LANDINGS: %s must start inland and reach the dry-beach side" % str(road.get("id", "?")))


static func _shoreline_edge_x(z: float, bands: Array) -> float:
	if bands.is_empty():
		return 1.0e9
	for index in range(bands.size() - 1):
		var a: Dictionary = bands[index]
		var b: Dictionary = bands[index + 1]
		if z <= float(b["z"]):
			return lerpf(float(a["dune_edge_x"]), float(b["dune_edge_x"]), inverse_lerp(float(a["z"]), float(b["z"]), z))
	return float(bands.back()["dune_edge_x"])


static func _validate_buildings(buildings: Variant, styles: Variant, roads: Dictionary, shoreline: Variant, width: int, height: int, errors: Array[String]) -> void:
	var style_ids := {}
	if styles is Array:
		for style: Variant in styles:
			_reject_unknown_keys(style, ["id", "palette", "roof_family", "exposure"], "district_style", errors)
			style_ids[str(style.get("id", ""))] = true
	var building_ids := {}
	var occupied := {}
	if not buildings is Array:
		errors.append("E_BUILDINGS: expected an array")
		return
	for building: Variant in buildings:
		_reject_unknown_keys(building, ["id", "type", "shape", "district", "box", "segments", "entry", "rooms", "slots", "readiness", "appearance", "interior"], "building", errors)
		if not building is Dictionary:
			errors.append("E_BUILDING: entry must be an object")
			continue
		var building_id := str(building.get("id", ""))
		if building_id.is_empty() or building_ids.has(building_id):
			errors.append("E_ID: missing or duplicate building id '%s'" % building_id)
			continue
		building_ids[building_id] = true
		if not SHAPES.has(str(building.get("shape", ""))):
			errors.append("E_SHAPE: %s uses an unsupported shape" % building_id)
		if not style_ids.has(str(building.get("district", ""))):
			errors.append("E_STYLE: %s references an unknown district style" % building_id)
		var box: Array = building.get("box", [])
		if box.size() != 4:
			errors.append("E_BUILDING_BOX: %s needs x, y, width, height" % building_id)
			continue
		var bx := int(box[0]); var by := int(box[1]); var bw := int(box[2]); var bh := int(box[3])
		if bx < 0 or by < 0 or bw <= 0 or bh <= 0 or bx + bw > width or by + bh > height:
			errors.append("E_BUILDING_BOUNDS: %s is outside the authored extent" % building_id)
		var entry: Dictionary = building.get("entry", {})
		_reject_unknown_keys(entry, ["at", "facing", "road", "access_path", "access_width_cells"], "building.entry", errors)
		var entry_point: Array = entry.get("at", [])
		if entry_point.size() != 2 or not roads.has(str(entry.get("road", ""))):
			errors.append("E_ENTRANCE: %s needs a two-coordinate entrance and a public road edge id" % building_id)
		var segments: Array = building.get("segments", [])
		if building.has("appearance"):
			var appearance: Dictionary = building["appearance"]
			_reject_unknown_keys(appearance, ["family", "segments"], "building.appearance", errors)
			var appearance_ids := {}
			for visual_segment: Variant in appearance.get("segments", []):
				_reject_unknown_keys(visual_segment, ["id", "module_id", "rotation"], "building.appearance.segment", errors)
				var visual_id := str(visual_segment.get("id", ""))
				if visual_id.is_empty() or appearance_ids.has(visual_id):
					errors.append("E_APPEARANCE_ID: %s has missing or duplicate visual segment id '%s'" % [building_id, visual_id])
				appearance_ids[visual_id] = true
				if not [0, 1, 2, 3].has(int(visual_segment.get("rotation", 0))):
					errors.append("E_APPEARANCE_ROTATION: %s/%s rotation must be cardinal" % [building_id, visual_id])
			for segment: Dictionary in segments:
				if not appearance_ids.has(str(segment.get("id", ""))):
					errors.append("E_APPEARANCE_MISSING: %s/%s has no visual module assignment" % [building_id, str(segment.get("id", "?"))])
		var local_cells := {}
		for segment: Variant in segments:
			_reject_unknown_keys(segment, ["id", "rect"], "building.segment", errors)
			var rect: Array = segment.get("rect", [])
			if rect.size() != 4:
				errors.append("E_SEGMENT: %s/%s needs x, y, width, height" % [building_id, str(segment.get("id", "?"))])
				continue
			var sx := int(rect[0]); var sy := int(rect[1]); var sw := int(rect[2]); var sh := int(rect[3])
			if sx < bx or sy < by or sw <= 0 or sh <= 0 or sx + sw > bx + bw or sy + sh > by + bh:
				errors.append("E_SEGMENT_BOUNDS: %s/%s escapes its building box" % [building_id, str(segment.get("id", "?"))])
			for y in range(sy, sy + sh):
				for x in range(sx, sx + sw):
					var cell := Vector2i(x, y)
					if x + 1.0 > _shoreline_edge_x(float(y) + 0.5, shoreline.get("bands", [])) - 0.001:
						errors.append("E_BUILDING_COAST_EXCLUSION: %s/%s reaches the landward dune boundary" % [building_id, str(segment.get("id", "?"))])
					if local_cells.has(cell):
						errors.append("E_SEGMENT_OVERLAP: %s segments overlap at %s" % [building_id, str(cell)])
						continue
					local_cells[cell] = true
					if occupied.has(cell):
						errors.append("E_BUILDING_OVERLAP: %s overlaps %s at %s" % [building_id, str(occupied[cell]), str(cell)])
					else:
						occupied[cell] = building_id
		if local_cells.is_empty():
			errors.append("E_EMPTY_BUILDING: %s has no occupied segments" % building_id)
		elif str(building.get("shape", "")) != "open" and not _cells_connected(local_cells):
			errors.append("E_DISCONNECTED_MASSING: %s has detached structural segments" % building_id)
		if str(building.get("shape", "")) == "U" and not _has_open_courtyard(local_cells, bx, by, bw, bh):
			errors.append("E_COURTYARD_FILLED: %s U-shaped massing must retain a court open to the exterior" % building_id)
		_validate_interior(building.get("interior", {}), building_id, local_cells, bx, by, bw, bh, str(building.get("shape", "")), building.get("rooms", []), building.get("slots", {}), errors)
		if entry_point.size() == 2 and (int(entry_point[0]) < 0 or int(entry_point[0]) > width or int(entry_point[1]) < 0 or int(entry_point[1]) > height):
			errors.append("E_ENTRANCE_BOUNDS: %s entry is outside the map" % building_id)
	if building_ids.size() != 14:
		errors.append("E_BUILDING_COUNT: S1 authored fixture requires 14 buildings, got %d" % building_ids.size())


static func _validate_interior(interior: Variant, building_id: String, structural_cells: Dictionary, box_x: int, box_y: int, box_width: int, box_height: int, shape: String, declared_rooms: Variant, declared_slots: Variant, errors: Array[String]) -> void:
	if not interior is Dictionary:
		errors.append("E_INTERIOR: %s needs an explicit interior graph" % building_id)
		return
	_reject_unknown_keys(interior, ["entry_room", "entry_at_q", "entry_clear_width_q", "rooms", "doors", "slots"], "building.interior", errors)
	if int(interior.get("entry_clear_width_q", 0)) < 40:
		errors.append("E_ENTRY_CLEARANCE: %s exterior portal is narrower than the provisional 40q actor diameter" % building_id)
	var room_values: Array = interior.get("rooms", []) if interior.get("rooms", []) is Array else []
	var door_values: Array = interior.get("doors", []) if interior.get("doors", []) is Array else []
	var slot_values: Array = interior.get("slots", []) if interior.get("slots", []) is Array else []
	if not interior.get("rooms", []) is Array or not interior.get("doors", []) is Array or not interior.get("slots", []) is Array:
		errors.append("E_INTERIOR_COLLECTION: %s rooms, doors and slots must be arrays" % building_id)
	var declared_room_values: Array = declared_rooms if declared_rooms is Array else []
	var declared_slot_values: Dictionary = declared_slots if declared_slots is Dictionary else {}
	if not declared_rooms is Array or not declared_slots is Dictionary:
		errors.append("E_INTERIOR_DECLARATION: %s room and slot declarations have invalid types" % building_id)
	var room_by_id := {}
	var declared_role_set := {}
	for role: Variant in declared_room_values:
		declared_role_set[str(role)] = true
	var represented_role_set := {}
	var floor_cells := {}
	for room: Variant in room_values:
		if not room is Dictionary:
			errors.append("E_ROOM: %s room records must be objects" % building_id)
			continue
		_reject_unknown_keys(room, ["id", "role", "bounds_q", "access_policy", "kind"], "building.interior.room", errors)
		var room_id := str(room.get("id", ""))
		var bounds: Array = room.get("bounds_q", [])
		if room_id.is_empty() or room_by_id.has(room_id) or bounds.size() != 4:
			errors.append("E_ROOM_ID: %s has a duplicate/empty room or invalid bounds" % building_id)
			continue
		var rx := int(bounds[0]); var ry := int(bounds[1]); var rw := int(bounds[2]); var rh := int(bounds[3])
		if rx < 0 or ry < 0 or rw <= 0 or rh <= 0 or rx + rw > box_width * 48 or ry + rh > box_height * 48:
			errors.append("E_ROOM_BOUNDS: %s/%s leaves its building-local extent" % [building_id, room_id])
		room_by_id[room_id] = room
		represented_role_set[str(room.get("role", ""))] = true
		var is_court := str(room.get("kind", "")) == "court"
		if str(room.get("access_policy", "")) not in ["public", "authorized"]:
			errors.append("E_ROOM_ACCESS: %s/%s has an unsupported access policy" % [building_id, room_id])
		if is_court and shape != "U":
			errors.append("E_ROOM_COURT: %s declares a court without U-shaped massing" % building_id)
		for cy in range(floori(float(ry) / 48.0), ceili(float(ry + rh) / 48.0)):
			for cx in range(floori(float(rx) / 48.0), ceili(float(rx + rw) / 48.0)):
				var cell := Vector2i(cx, cy)
				if not is_court and not structural_cells.has(cell + Vector2i(box_x, box_y)):
					errors.append("E_ROOM_FLOOR: %s/%s extends beyond its structural floor" % [building_id, room_id])
					break
				if floor_cells.has(cell):
					errors.append("E_ROOM_OVERLAP: %s rooms overlap at local cell %s" % [building_id, str(cell)])
					break
				floor_cells[cell] = room_id
	for role: Variant in declared_role_set.keys():
		if not represented_role_set.has(str(role)):
			errors.append("E_ROOM_ROLE: %s does not resolve declared room role '%s'" % [building_id, str(role)])
	for global_cell: Variant in structural_cells.keys():
		var local_cell: Vector2i = global_cell - Vector2i(box_x, box_y)
		if not floor_cells.has(local_cell):
			errors.append("E_FLOOR_COVERAGE: %s structural floor cell %s has no room assignment" % [building_id, str(local_cell)])
	for room: Dictionary in room_by_id.values():
		if str(room.get("kind", "")) == "court":
			var bounds: Array = room.get("bounds_q", [])
			for cy in range(floori(float(bounds[1]) / 48.0), ceili(float(bounds[1] + bounds[3]) / 48.0)):
				for cx in range(floori(float(bounds[0]) / 48.0), ceili(float(bounds[0] + bounds[2]) / 48.0)):
					if structural_cells.has(Vector2i(box_x + cx, box_y + cy)):
						errors.append("E_COURT_OCCUPIED: %s court overlaps building floor" % building_id)
	var entry_room := str(interior.get("entry_room", ""))
	if not room_by_id.has(entry_room):
		errors.append("E_ROOM_ENTRY: %s entry references a missing interior room" % building_id)
	var entry_anchor: Array = interior.get("entry_at_q", [])
	if entry_anchor.size() != 2 or not room_by_id.has(entry_room):
		errors.append("E_ENTRY_ANCHOR: %s needs a local interior entry anchor and valid entry room" % building_id)
	elif not _point_inside_room(entry_anchor, room_by_id[entry_room].get("bounds_q", [])) or not _clearance_fits_room(entry_anchor, [48, 48], room_by_id[entry_room].get("bounds_q", [])):
		errors.append("E_ENTRY_ANCHOR: %s exterior entrance does not resolve to a clear point in its entry room" % building_id)
	var adjacency := {}
	for room_id: Variant in room_by_id.keys():
		adjacency[str(room_id)] = []
	var door_ids := {}
	for door: Variant in door_values:
		if not door is Dictionary:
			errors.append("E_DOOR: %s door records must be objects" % building_id)
			continue
		_reject_unknown_keys(door, ["id", "from_room", "to_room", "at_q", "clear_width_q", "access_policy"], "building.interior.door", errors)
		var door_id := str(door.get("id", ""))
		var from_room := str(door.get("from_room", ""))
		var to_room := str(door.get("to_room", ""))
		var point: Array = door.get("at_q", [])
		if door_id.is_empty() or door_ids.has(door_id) or from_room == to_room or not room_by_id.has(from_room) or not room_by_id.has(to_room) or point.size() != 2 or int(door.get("clear_width_q", 0)) < 40:
			errors.append("E_DOOR_REFERENCE: %s has an invalid/duplicate portal" % building_id)
			continue
		if str(door.get("access_policy", "")) not in ["public", "resident_or_staff"]:
			errors.append("E_DOOR_ACCESS: %s/%s has an unsupported access policy" % [building_id, door_id])
		door_ids[door_id] = true
		adjacency[from_room].append(to_room)
		adjacency[to_room].append(from_room)
		if not _point_on_room_bounds(point, room_by_id[from_room].get("bounds_q", [])) or not _point_on_room_bounds(point, room_by_id[to_room].get("bounds_q", [])):
			errors.append("E_DOOR_LOCATION: %s/%s is not on both connected room boundaries" % [building_id, door_id])
		elif int(door.get("clear_width_q", 0)) > _shared_room_edge_length(room_by_id[from_room].get("bounds_q", []), room_by_id[to_room].get("bounds_q", []), point):
			errors.append("E_DOOR_WIDTH: %s/%s exceeds the shared wall opening" % [building_id, door_id])
	if room_by_id.has(entry_room):
		var reached := {entry_room: true}
		var queue: Array[String] = [entry_room]
		while not queue.is_empty():
			var current: String = queue.pop_front()
			for neighbor: String in adjacency.get(current, []):
				if not reached.has(neighbor):
					reached[neighbor] = true
					queue.append(neighbor)
		if reached.size() != room_by_id.size():
			errors.append("E_ROOM_CONNECTIVITY: %s reaches %d of %d rooms from its entrance" % [building_id, reached.size(), room_by_id.size()])
	var slot_ids := {}
	var capacity_by_action := {}
	for slot: Variant in slot_values:
		if not slot is Dictionary:
			errors.append("E_SLOT: %s slot records must be objects" % building_id)
			continue
		_reject_unknown_keys(slot, ["id", "action", "room", "at_q", "approach_q", "facing", "capacity", "clearance_q", "access_policy", "duration_policy"], "building.interior.slot", errors)
		var slot_id := str(slot.get("id", ""))
		var room_id := str(slot.get("room", ""))
		var site: Array = slot.get("at_q", [])
		var approach: Array = slot.get("approach_q", [])
		var capacity := int(slot.get("capacity", 0))
		var clearance: Array = slot.get("clearance_q", [])
		if slot_id.is_empty() or slot_ids.has(slot_id) or not room_by_id.has(room_id) or site.size() != 2 or approach.size() != 2 or capacity <= 0:
			errors.append("E_SLOT_REFERENCE: %s has an invalid/duplicate affordance" % building_id)
			continue
		if str(slot.get("access_policy", "")) not in ["public", "authorized"]:
			errors.append("E_SLOT_ACCESS: %s/%s has an unsupported access policy" % [building_id, slot_id])
		slot_ids[slot_id] = true
		capacity_by_action[str(slot.get("action", ""))] = int(capacity_by_action.get(str(slot.get("action", "")), 0)) + capacity
		var room_bounds: Array = room_by_id[room_id].get("bounds_q", [])
		if not _point_inside_room(site, room_bounds) or not _point_inside_room(approach, room_bounds):
			errors.append("E_SLOT_LOCATION: %s/%s site and approach must lie inside their assigned room" % [building_id, slot_id])
		if clearance.size() != 2 or int(clearance[0]) < 40 or int(clearance[1]) < 40:
			errors.append("E_SLOT_CLEARANCE: %s/%s must reserve at least 40q × 40q for the provisional actor" % [building_id, slot_id])
		elif not _clearance_fits_room(approach, clearance, room_bounds):
			errors.append("E_SLOT_CLEARANCE: %s/%s approach clearance leaves its assigned room" % [building_id, slot_id])
		if str(slot.get("duration_policy", "")).is_empty():
			errors.append("E_SLOT_DURATION: %s/%s needs a duration-policy reference" % [building_id, slot_id])
		var route: Dictionary = NAVIGATOR.route_to_slot(interior, slot)
		if not bool(route.get("ok", false)):
			errors.append("E_SLOT_UNREACHABLE: %s/%s %s" % [building_id, slot_id, str(route.get("error", "no route"))])
	for action: Variant in declared_slot_values.keys():
		if int(capacity_by_action.get(str(action), 0)) != int(declared_slot_values[action]):
			errors.append("E_SLOT_CAPACITY: %s action '%s' declares %d but publishes %d" % [building_id, str(action), int(declared_slot_values[action]), int(capacity_by_action.get(str(action), 0))])
	for action: Variant in capacity_by_action.keys():
		if not declared_slot_values.has(str(action)):
			errors.append("E_SLOT_CAPACITY: %s publishes undeclared action '%s'" % [building_id, str(action)])


static func _point_on_room_bounds(point: Array, bounds: Array) -> bool:
	if point.size() != 2 or bounds.size() != 4:
		return false
	var x := int(point[0]); var y := int(point[1])
	var bx := int(bounds[0]); var by := int(bounds[1]); var ex := bx + int(bounds[2]); var ey := by + int(bounds[3])
	return x >= bx and x <= ex and y >= by and y <= ey and (x == bx or x == ex or y == by or y == ey)


static func _point_inside_room(point: Array, bounds: Array) -> bool:
	if point.size() != 2 or bounds.size() != 4:
		return false
	return int(point[0]) > int(bounds[0]) and int(point[0]) < int(bounds[0]) + int(bounds[2]) and int(point[1]) > int(bounds[1]) and int(point[1]) < int(bounds[1]) + int(bounds[3])


static func _shared_room_edge_length(a: Array, b: Array, point: Array) -> int:
	if a.size() != 4 or b.size() != 4 or point.size() != 2:
		return 0
	var a_right := int(a[0]) + int(a[2]); var a_bottom := int(a[1]) + int(a[3])
	var b_right := int(b[0]) + int(b[2]); var b_bottom := int(b[1]) + int(b[3])
	if int(point[1]) == a_bottom and int(point[1]) == int(b[1]) or int(point[1]) == b_bottom and int(point[1]) == int(a[1]):
		return maxi(0, mini(a_right, b_right) - maxi(int(a[0]), int(b[0])))
	if int(point[0]) == a_right and int(point[0]) == int(b[0]) or int(point[0]) == b_right and int(point[0]) == int(a[0]):
		return maxi(0, mini(a_bottom, b_bottom) - maxi(int(a[1]), int(b[1])))
	return 0


static func _clearance_fits_room(point: Array, clearance: Array, bounds: Array) -> bool:
	if point.size() != 2 or clearance.size() != 2 or bounds.size() != 4:
		return false
	var half_width := int(clearance[0]) / 2
	var half_height := int(clearance[1]) / 2
	return int(point[0]) - half_width >= int(bounds[0]) and int(point[0]) + half_width <= int(bounds[0]) + int(bounds[2]) and int(point[1]) - half_height >= int(bounds[1]) and int(point[1]) + half_height <= int(bounds[1]) + int(bounds[3])


static func _has_open_courtyard(cells: Dictionary, x: int, y: int, width: int, height: int) -> bool:
	var start := Vector2i(x + width / 2, y + height / 2)
	if cells.has(start):
		return false
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		if cell.x <= x or cell.y <= y or cell.x >= x + width - 1 or cell.y >= y + height - 1:
			return true
		for neighbor in [cell + Vector2i.LEFT, cell + Vector2i.RIGHT, cell + Vector2i.UP, cell + Vector2i.DOWN]:
			if neighbor.x >= x and neighbor.x < x + width and neighbor.y >= y and neighbor.y < y + height and not cells.has(neighbor) and not seen.has(neighbor):
				seen[neighbor] = true
				queue.append(neighbor)
	return false


static func _validate_road_corridors(roads: Variant, nodes_list: Variant, buildings: Variant, errors: Array[String]) -> void:
	var nodes := _index_by_id(nodes_list, "road_nodes", errors)
	if not roads is Array or not buildings is Array:
		return
	for road: Dictionary in roads:
		var points := _road_points(road, nodes)
		var half_width := float(road.get("width_cells", 0)) * 0.5
		for index in range(points.size() - 1):
			var a: Vector2 = points[index]
			var b: Vector2 = points[index + 1]
			var steps := maxi(1, ceili(a.distance_to(b) * 2.0))
			for step in range(steps + 1):
				var sample := a.lerp(b, float(step) / float(steps))
				for building: Dictionary in buildings:
					if str(building.get("shape", "")) == "open":
						continue
					for segment: Dictionary in building.get("segments", []):
						var rect: Array = segment["rect"]
						var distance := _point_rect_distance(sample, Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3])))
						if distance < half_width - 0.001:
							errors.append("E_ROAD_BUILDING_CLEARANCE: %s corridor clips %s/%s" % [str(road.get("id", "?")), str(building.get("id", "?")), str(segment.get("id", "?"))])
							return


static func _validate_access_paths(buildings: Variant, road_index: Dictionary, node_index: Dictionary, roads: Variant, nodes: Variant, shoreline: Variant, width: int, height: int, errors: Array[String]) -> void:
	if not buildings is Array or not roads is Array:
		return
	var node_by_id := _index_by_id(nodes, "road_nodes", errors)
	var road_by_id := _index_by_id(roads, "roads", errors)
	var actor_radius := 20.0 / 48.0
	for building: Dictionary in buildings:
		var building_id := str(building.get("id", "?"))
		var entry: Dictionary = building.get("entry", {})
		var path: Array = entry.get("access_path", [])
		var road_id := str(entry.get("road", ""))
		if path.size() < 2 or not road_index.has(road_id):
			errors.append("E_ACCESS_PATH: %s needs a polyline and public road edge" % building_id)
			continue
		var path_width := float(entry.get("access_width_cells", 0))
		if path_width < actor_radius * 2.0:
			errors.append("E_ACCESS_WIDTH: %s path is narrower than the target actor diameter" % building_id)
		var at: Array = entry.get("at", [])
		if at.size() == 2:
			var expected := Vector2(float(at[0]) + 0.5, float(at[1]) + 0.5)
			match str(entry.get("facing", "")):
				"north": expected.y -= 0.5
				"south": expected.y += 0.5
				"east": expected.x += 0.5
				"west": expected.x -= 0.5
			if Vector2(path[0][0], path[0][1]).distance_to(expected) > 0.01:
				errors.append("E_ACCESS_DOOR_ANCHOR: %s path does not begin at its declared doorway" % building_id)
		var target_road: Dictionary = road_by_id[road_id]
		var target_points := _road_points(target_road, node_by_id)
		var end_point := Vector2(path[-1][0], path[-1][1])
		if _distance_to_polyline(end_point, target_points) > float(target_road.get("width_cells", 0)) * 0.5 + 0.02:
			errors.append("E_ACCESS_ROAD_LINK: %s access path does not reach road %s" % [building_id, road_id])
		var for_step := 0
		for index in range(path.size() - 1):
			var a := Vector2(path[index][0], path[index][1])
			var b := Vector2(path[index + 1][0], path[index + 1][1])
			var steps := maxi(1, ceili(a.distance_to(b) * 4.0))
			for step in range(steps + 1):
				var point := a.lerp(b, float(step) / float(steps))
				if point.x < 0 or point.y < 0 or point.x > width or point.y > height:
					errors.append("E_ACCESS_BOUNDS: %s path leaves the map" % building_id)
					break
				if _shoreline_edge_x(point.y, shoreline.get("bands", [])) - point.x < actor_radius:
					errors.append("E_ACCESS_COAST_EXCLUSION: %s connector enters the dune band" % building_id)
					break
				for other: Dictionary in buildings:
					if str(other.get("id", "")) == building_id or str(other.get("shape", "")) == "open":
						continue
					for segment: Dictionary in other.get("segments", []):
						var rect: Array = segment["rect"]
						if _point_rect_distance(point, Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))) < actor_radius - 0.001:
							errors.append("E_ACCESS_BLOCKED: %s path is blocked by %s" % [building_id, str(other.get("id", "?"))])
							break
				for_step += 1
			if errors.size() > 0 and str(errors.back()).begins_with("E_ACCESS_"):
				break
		if for_step == 0:
			errors.append("E_ACCESS_EMPTY: %s has no swept path samples" % building_id)


static func _road_points(road: Dictionary, nodes: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var point_values: Array = road.get("via", [])
	if point_values.is_empty():
		if not nodes.has(str(road.get("from", ""))) or not nodes.has(str(road.get("to", ""))):
			return result
		point_values = [nodes[str(road["from"])]["at"], nodes[str(road["to"])]["at"]]
	for point: Variant in point_values:
		result.append(Vector2(float(point[0]), float(point[1])))
	return result


static func _point_rect_distance(point: Vector2, rect: Rect2) -> float:
	var dx := maxf(maxf(rect.position.x - point.x, 0.0), point.x - rect.end.x)
	var dy := maxf(maxf(rect.position.y - point.y, 0.0), point.y - rect.end.y)
	return Vector2(dx, dy).length()


static func _distance_to_polyline(point: Vector2, points: Array[Vector2]) -> float:
	var closest := INF
	for index in range(points.size() - 1):
		var a: Vector2 = points[index]
		var b: Vector2 = points[index + 1]
		var delta := b - a
		var length_sq := delta.length_squared()
		var t := 0.0 if length_sq <= 0.0 else clampf((point - a).dot(delta) / length_sq, 0.0, 1.0)
		closest = minf(closest, point.distance_to(a + delta * t))
	return closest


static func _cells_connected(cells: Dictionary) -> bool:
	var keys: Array = cells.keys()
	if keys.is_empty():
		return false
	var seen := {keys[0]: true}
	var queue: Array[Vector2i] = [keys[0]]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for neighbor in [cell + Vector2i.LEFT, cell + Vector2i.RIGHT, cell + Vector2i.UP, cell + Vector2i.DOWN]:
			if cells.has(neighbor) and not seen.has(neighbor):
				seen[neighbor] = true
				queue.append(neighbor)
	return seen.size() == cells.size()
