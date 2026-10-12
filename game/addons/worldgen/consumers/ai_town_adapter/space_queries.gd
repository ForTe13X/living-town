extends RefCounted
class_name WorldPackageAitownSpaceQueries
## Converts immutable package spaces and slots to detached Living Town spatial records.
## It never receives Sim state and never grants actions: action values come from a host allowlist.

const VALIDATOR := preload("res://addons/worldgen/core/worldgen_package_validator.gd")
const SPACE_GRAPH := preload("res://scripts/SpaceGraph.gd")

var _world_id := ""

func merge_package(package: Dictionary, base_graph: Dictionary, base_interiors: Dictionary,
		action_bindings: Dictionary, staff_titles_by_building: Dictionary = {},
		base_objects: Array = [], jobs_by_agent: Dictionary = {}) -> Dictionary:
	_world_id = ""
	var checked: Dictionary = VALIDATOR.validate(package)
	if not bool(checked.get("ok", false)):
		return _failure("E_AITOWN_PACKAGE: " + ";".join(checked.get("errors", [])))
	if not base_graph.get("spaces", {}) is Dictionary or not base_graph.get("portals", []) is Array:
		return _failure("E_AITOWN_BASE_GRAPH: expected spaces and portals")
	var semantic: Dictionary = package.get("semantic", {})
	var buildings: Array = semantic.get("buildings", [])
	var rooms: Array = semantic.get("rooms", [])
	var portals: Array = semantic.get("portals", [])
	var affordances: Array = semantic.get("affordances", [])
	if buildings.is_empty():
		return _failure("E_AITOWN_BUILDINGS: package contains no buildings")
	var graph: Dictionary = base_graph.duplicate(true)
	graph["spaces"] = graph["spaces"].duplicate(true)
	graph["portals"] = graph["portals"].duplicate(true)
	var interiors := base_interiors.duplicate(true)
	var building_by_id := {}
	var output_affordances: Array = []
	var output_rooms: Array = []
	var home_anchors: Array = []
	var world_id := String(package.get("world_id", ""))
	var prefix := "wp_%s_" % _safe_name(world_id)
	for building: Dictionary in buildings:
		var building_id := String(building.get("id", ""))
		var box: Array = building.get("box", [])
		if building_id.is_empty() or box.size() != 4 or int(box[2]) < 3 or int(box[3]) < 3:
			return _failure("E_AITOWN_BUILDING: invalid identity or interior bounds")
		if building_by_id.has(building_id):
			return _failure("E_AITOWN_BUILDING_ID: duplicate %s" % building_id)
		var space_id := prefix + _safe_name(building_id)
		if graph["spaces"].has(space_id) or interiors.has(space_id):
			return _failure("E_AITOWN_ID_CONFLICT: %s" % space_id)
		var program := String(building.get("program", ""))
		var home := program in ["home", "residence", "house"]
		graph["spaces"][space_id] = {"kind": "interior", "label": program.capitalize() + " · " + building_id,
			"bounds": [0, 0, int(box[2]), int(box[3])], "floors": ["1f"], "default_floor": "1f",
			"home_space": space_id, "public_venue": not home}
		interiors[space_id] = {"1f": {"label": program.capitalize() + " · " + building_id, "floor": "wood", "furniture": []}}
		building_by_id[building_id] = {"space_id": space_id, "origin": [int(box[0]), int(box[1])],
			"bounds": box.duplicate(true), "home": home, "program": program}
	for portal: Dictionary in portals:
		var building_id := String(portal.get("building_id", ""))
		if not building_by_id.has(building_id):
			return _failure("E_AITOWN_PORTAL_BUILDING: %s" % String(portal.get("id", "")))
		var owner: Dictionary = building_by_id[building_id]
		var origin: Array = owner["origin"]
		var ext := String(portal.get("from_room", "")) == "exterior" or String(portal.get("kind", "")) == "exterior"
		var from_world: Array = portal.get("from", [])
		var to_world: Array = portal.get("to", [])
		if from_world.size() != 2 or to_world.size() != 2:
			return _failure("E_AITOWN_PORTAL_ENDPOINT: %s" % String(portal.get("id", "")))
		var access := String(portal.get("access", ""))
		if not access in ["public", "owner", "staff"]:
			return _failure("E_AITOWN_PORTAL_ACCESS: unsupported policy on %s" % String(portal.get("id", "")))
		if ext and bool(owner["home"]):
			access = "owner" # A residence entrance is private even if its lobby room is public.
		var from_endpoint := _endpoint("town", "outdoor", from_world) if ext else _endpoint(String(owner["space_id"]), "1f", _local(from_world, origin))
		var to_endpoint := _endpoint(String(owner["space_id"]), "1f", _local(to_world, origin)) if ext else _endpoint(String(owner["space_id"]), "1f", _local(to_world, origin))
		var compiled := {"id": prefix + _safe_name(String(portal.get("id", ""))), "kind": "door",
			"from": from_endpoint, "to": to_endpoint, "bidirectional": true, "access": access,
			"traversal_cost": 1}
		if access == "owner": compiled["owner_space"] = String(owner["space_id"])
		if access == "staff":
			compiled["staff_titles"] = _string_array(staff_titles_by_building.get(building_id, []))
		graph["portals"].append(compiled)
		if ext and bool(owner["home"]):
			var spawn_positions := _home_spawn_positions(building_id, String(portal.get("to_room", "")), rooms, affordances, origin)
			if spawn_positions.is_empty(): return _failure("E_AITOWN_HOME_SPAWN: %s has no interior start positions" % building_id)
			home_anchors.append({"building_id": building_id, "space_id": String(owner["space_id"]),
				"home_space_id": String(owner["space_id"]), "floor_id": "1f",
				"position": spawn_positions[0].duplicate(true), "spawn_positions": spawn_positions,
				"entry_portal_id": String(compiled["id"])})
	for affordance: Dictionary in affordances:
		var building_id := String(affordance.get("building_id", ""))
		if not building_by_id.has(building_id):
			return _failure("E_AITOWN_AFFORDANCE_BUILDING: %s" % String(affordance.get("id", "")))
		var owner: Dictionary = building_by_id[building_id]
		var origin: Array = owner["origin"]
		var action_type := String(affordance.get("action_type", ""))
		var slot_id := String(affordance.get("id", ""))
		var access := String(affordance.get("access", ""))
		if not access in ["public", "owner", "staff"]:
			return _failure("E_AITOWN_AFFORDANCE_ACCESS: %s" % slot_id)
		var mapped_value: Variant = action_bindings.get(action_type, {})
		if not mapped_value is Dictionary: return _failure("E_AITOWN_BINDING: %s must map to an object" % action_type)
		var mapped: Dictionary = mapped_value
		var required_job := String(mapped.get("job_title", ""))
		var source_action := String(mapped.get("action", ""))
		if bool(mapped.get("action_from_staff_job", false)):
			var candidates: Array[String] = _string_array(staff_titles_by_building.get(building_id, []))
			if candidates.size() == 1:
				required_job = candidates[0]
				var job_ids: Array = jobs_by_agent.keys(); job_ids.sort()
				for job_id: String in job_ids:
					var job_record: Variant = jobs_by_agent[job_id]
					if job_record is Dictionary and String(job_record.get("title", "")) == required_job:
						source_action = String(job_record.get("action", "")); break
		var advert := _find_action_profile(base_interiors, source_action, base_objects) if source_action != "" else {}
		var binding_status := "unbound: host action is not allowlisted"
		if not advert.is_empty():
			binding_status = "existing_action:" + source_action
			var cell: Array = _local(affordance.get("position", []), origin)
			var furniture := {"slot": _furniture_slot(action_type), "pos": cell,
				"label": slot_id, "size": [1, 1], "worldgen_affordance_id": slot_id,
				"worldgen_action_type": action_type, "worldgen_capacity": int(affordance.get("capacity", 0)),
				"worldgen_access": access, "advertises": []}
			var runtime_advert: Dictionary = advert.duplicate(true)
			runtime_advert["seated"] = true
			runtime_advert["seats"] = maxi(1, int(affordance.get("capacity", 1)))
			if not required_job.is_empty(): runtime_advert["job"] = required_job
			furniture["advertises"].append(runtime_advert)
			(interiors[String(owner["space_id"])]["1f"]["furniture"] as Array).append(furniture)
		var local_position: Array = _local(affordance.get("position", []), origin)
		var local_approach: Array = _local(affordance.get("approach", []), origin)
		var local_route: Array = []
		for point: Variant in affordance.get("route", []): local_route.append(_local(point, origin))
		var local_path: Array = []
		for portal_id: String in affordance.get("portal_path", []): local_path.append(prefix + _safe_name(portal_id))
		output_affordances.append({"id": prefix + _safe_name(slot_id), "worldgen_id": slot_id,
			"action_type": action_type, "runtime_binding": binding_status, "capacity": int(affordance.get("capacity", 0)),
			"access": access, "address": {"space_id": String(owner["space_id"]), "floor_id": "1f", "position": local_position},
			"approach": local_approach, "route": {"path": local_route}, "portal_path": local_path})
	for room: Dictionary in rooms:
		var building_id := String(room.get("building_id", ""))
		if not building_by_id.has(building_id): return _failure("E_AITOWN_ROOM_BUILDING: %s" % String(room.get("id", "")))
		var owner: Dictionary = building_by_id[building_id]
		var rect: Array = room.get("bounds", [])
		if rect.size() != 4: return _failure("E_AITOWN_ROOM_BOUNDS: %s" % String(room.get("id", "")))
		var local_rect := [int(rect[0]) - int(owner["origin"][0]), int(rect[1]) - int(owner["origin"][1]), int(rect[2]), int(rect[3])]
		output_rooms.append({"id": String(room.get("id", "")), "building_id": building_id,
			"space_id": String(owner["space_id"]), "floor_id": "1f", "bounds": local_rect,
			"role": String(room.get("role", "")), "access": String(room.get("access", ""))})
		# Retain the source room IDs in detached metadata for editor and migration consumers.
		interiors[String(owner["space_id"])]["1f"]["furniture"].append({"slot": "rug", "pos": [local_rect[0], local_rect[1]],
			"size": [1, 1], "label": String(room.get("role", "room")), "worldgen_room_id": String(room.get("id", "")),
			"worldgen_room_bounds": local_rect, "worldgen_access": String(room.get("access", ""))})
	# A shared line of room rectangles becomes two blocked wall rows/columns, except at declared door cells.
	var wall_result := _append_partition_walls(rooms, portals, building_by_id, interiors, prefix)
	if not bool(wall_result.get("ok", false)): return wall_result
	var space_graph: RefCounted = SPACE_GRAPH.new()
	space_graph.spaces = graph["spaces"]
	space_graph.portals = graph["portals"]
	var graph_errors: Array = space_graph.validate()
	if not graph_errors.is_empty(): return _failure("E_AITOWN_SPACE_GRAPH: " + ";".join(graph_errors))
	_world_id = world_id
	return {"ok": true, "world_id": world_id, "semantic_sha256": String(package.get("digests", {}).get("semantic_sha256", "")),
		"spaces": graph, "interiors": interiors, "affordances": output_affordances,
		"rooms": output_rooms, "home_anchors": home_anchors}

## Apply explicit home assignments to a detached resident document. No residents are moved
## until the caller elects to use this returned candidate during world initialization.
func prepare_resident_assignments(agent_document: Dictionary, assignments: Array, home_anchors: Array,
		capacity_per_home := 4) -> Dictionary:
	if capacity_per_home < 1: return _failure("E_AITOWN_HOME_CAPACITY: capacity must be positive")
	var candidate := agent_document.duplicate(true)
	var definitions := {}
	for section: String in ["agents", "affiliates"]:
		for index in range(candidate.get(section, []).size()):
			var definition: Dictionary = candidate[section][index]
			var id := String(definition.get("id", ""))
			if id.is_empty() or definitions.has(id): return _failure("E_AITOWN_RESIDENT_ID: duplicate or empty %s" % id)
			definitions[id] = {"section": section, "index": index}
	var anchors := {}
	for anchor: Dictionary in home_anchors: anchors[String(anchor.get("building_id", ""))] = anchor
	var assigned := {}; var assigned_order: Array[String] = []; var occupants := {}; var occupant_indices := {}
	for raw_assignment: Variant in assignments:
		if not raw_assignment is Dictionary: return _failure("E_AITOWN_ASSIGNMENT: entries must be objects")
		var assignment: Dictionary = raw_assignment
		var agent_id := String(assignment.get("agent_id", "")); var building_id := String(assignment.get("building_id", ""))
		if not definitions.has(agent_id): return _failure("E_AITOWN_UNKNOWN_RESIDENT: %s" % agent_id)
		if assigned.has(agent_id): return _failure("E_AITOWN_DUPLICATE_RESIDENT: %s" % agent_id)
		if not anchors.has(building_id): return _failure("E_AITOWN_UNKNOWN_HOME: %s" % building_id)
		occupants[building_id] = int(occupants.get(building_id, 0)) + 1
		if int(occupants[building_id]) > capacity_per_home: return _failure("E_AITOWN_HOME_FULL: %s" % building_id)
		var valid_spawns: Variant = anchors[building_id].get("spawn_positions", [])
		if not valid_spawns is Array or valid_spawns.is_empty():
			return _failure("E_AITOWN_HOME_SPAWN: %s has no interior start positions" % building_id)
		assigned[agent_id] = building_id
		assigned_order.append(agent_id)
	for agent_id: String in assigned_order:
		var ref: Dictionary = definitions[agent_id]; var anchor: Dictionary = anchors[String(assigned[agent_id])]
		var definition: Dictionary = candidate[ref["section"]][int(ref["index"])]
		var building_id := String(assigned[agent_id]); var slot := int(occupant_indices.get(building_id, 0))
		var spawn_positions: Array = anchor.get("spawn_positions", [])
		if slot >= spawn_positions.size(): return _failure("E_AITOWN_HOME_SPAWN_CAPACITY: %s" % building_id)
		occupant_indices[building_id] = slot + 1
		definition["spatial_address"] = {"space_id": String(anchor["space_id"]), "floor_id": String(anchor["floor_id"]), "position": spawn_positions[slot].duplicate(true)}
		definition["home_space_id"] = String(anchor["home_space_id"])
		definition["home_floor_id"] = String(anchor["floor_id"])
		if not definition.has("home_needs") or not definition["home_needs"] is Array or definition["home_needs"].is_empty():
			definition["home_needs"] = ["energy"]
	return {"ok": true, "agent_document": candidate, "assigned_count": assigned.size(), "occupants_by_home": occupants}

func _append_partition_walls(rooms: Array, portals: Array, buildings: Dictionary, interiors: Dictionary, prefix: String) -> Dictionary:
	var door_cells := {}
	for portal: Dictionary in portals:
		if String(portal.get("kind", "")) != "internal": continue
		var building_id := String(portal.get("building_id", ""))
		if not buildings.has(building_id): continue
		var origin: Array = buildings[building_id]["origin"]
		for endpoint in [portal.get("from", []), portal.get("to", [])]:
			var local: Array = _local(endpoint, origin)
			door_cells[building_id + ":" + str(local[0]) + "," + str(local[1])] = true
	for i in range(rooms.size()):
		var a: Dictionary = rooms[i]
		for j in range(i + 1, rooms.size()):
			var b: Dictionary = rooms[j]
			if String(a.get("building_id", "")) != String(b.get("building_id", "")): continue
			var building_id := String(a.get("building_id", "")); var owner: Dictionary = buildings[building_id]
			var ar: Array = a.get("bounds", []); var br: Array = b.get("bounds", [])
			var cells: Array = _shared_wall_cells(ar, br)
			for cell: Array in cells:
				var local := [int(cell[0]) - int(owner["origin"][0]), int(cell[1]) - int(owner["origin"][1])]
				var coord := str(local[0]) + "," + str(local[1])
				if door_cells.has(building_id + ":" + coord): continue
				var floor_content: Dictionary = interiors[String(owner["space_id"])]["1f"]
				var dedupe := "wall:" + coord
				var seen: Dictionary = floor_content.get("_worldgen_wall_cells", {})
				if seen.has(dedupe): continue
				seen[dedupe] = true
				floor_content["_worldgen_wall_cells"] = seen
				floor_content["furniture"].append({"slot": "wall", "pos": local, "worldgen_wall_id": prefix + _safe_name(building_id) + "/" + dedupe})
	for space_id: String in interiors:
		if interiors[space_id] is Dictionary and (interiors[space_id] as Dictionary).has("1f"):
			(interiors[space_id]["1f"] as Dictionary).erase("_worldgen_wall_cells")
	return {"ok": true}

func _shared_wall_cells(a: Array, b: Array) -> Array:
	var out: Array = []
	if a.size() != 4 or b.size() != 4: return out
	var ax := int(a[0]); var ay := int(a[1]); var aw := int(a[2]); var ah := int(a[3])
	var bx := int(b[0]); var by := int(b[1]); var bw := int(b[2]); var bh := int(b[3])
	if ax + aw == bx or bx + bw == ax:
		var edge_x := bx if ax + aw == bx else ax
		var lo := maxi(ay, by); var hi := mini(ay + ah, by + bh)
		for y in range(lo, hi):
			out.append([edge_x - 1, y]); out.append([edge_x, y])
	elif ay + ah == by or by + bh == ay:
		var edge_y := by if ay + ah == by else ay
		var lo := maxi(ax, bx); var hi := mini(ax + aw, bx + bw)
		for x in range(lo, hi):
			out.append([x, edge_y - 1]); out.append([x, edge_y])
	return out

func _home_spawn_positions(building_id: String, room_id: String, rooms: Array, affordances: Array, origin: Array) -> Array:
	var room_rect: Array = []
	for room: Dictionary in rooms:
		if String(room.get("id", "")) == room_id and String(room.get("building_id", "")) == building_id:
			room_rect = room.get("bounds", []); break
	if room_rect.size() != 4: return []
	var x0 := int(room_rect[0]) - int(origin[0]); var y0 := int(room_rect[1]) - int(origin[1])
	var width := int(room_rect[2]); var height := int(room_rect[3])
	var reserved := {}
	for affordance: Dictionary in affordances:
		if String(affordance.get("building_id", "")) != building_id: continue
		for field: String in ["position", "approach"]:
			var point: Array = affordance.get(field, [])
			if point.size() == 2: reserved["%d,%d" % [int(point[0]) - int(origin[0]), int(point[1]) - int(origin[1])]] = true
	var out: Array = []
	for y in range(y0 + 1, y0 + height - 1):
		for x in range(x0 + 1, x0 + width - 1):
			if not reserved.has("%d,%d" % [x, y]): out.append([x, y])
	return out

func _find_action_profile(interiors: Dictionary, action: String, objects: Array) -> Dictionary:
	for object: Variant in objects:
		if not object is Dictionary: continue
		for raw: Variant in object.get("advertises", []):
			if raw is Dictionary and String(raw.get("action", "")) == action: return raw.duplicate(true)
	for space_id: String in interiors:
		if space_id.begins_with("_") or not interiors[space_id] is Dictionary: continue
		for floor_id: String in interiors[space_id]:
			var content: Variant = interiors[space_id][floor_id]
			if not content is Dictionary: continue
			for item: Variant in content.get("furniture", []):
				if not item is Dictionary: continue
				for raw: Variant in item.get("advertises", []):
					if raw is Dictionary and String(raw.get("action", "")) == action: return raw.duplicate(true)
	return {}

func _endpoint(space: String, floor: String, pos: Array) -> Dictionary:
	return {"space": space, "floor": floor, "pos": pos.duplicate(true)}

func _local(position: Variant, origin: Array) -> Array:
	if not position is Array or position.size() != 2 or origin.size() != 2: return []
	return [int(position[0]) - int(origin[0]), int(position[1]) - int(origin[1])]

func _furniture_slot(action_type: String) -> String:
	return {"sleep": "bed", "rest": "seat", "bathe": "bathtub", "bath": "bathtub",
		"read": "bookshelf", "buy_food": "counter", "work": "workbench"}.get(action_type, "worldgen_slot")

func _string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item: Variant in value:
			if item is String and not String(item).is_empty(): out.append(String(item))
	return out

func _safe_name(value: String) -> String:
	var out := value.to_lower().replace("/", "_").replace("\\", "_").replace(" ", "_").replace(":", "_")
	return out if not out.is_empty() else "unnamed"

func _failure(code: String) -> Dictionary:
	return {"ok": false, "errors": [code]}
