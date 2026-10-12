extends RefCounted
## Deterministic bounded shelf packer for small inland neighborhoods.
## Produces integer-cell parcels, building envelopes, a connected public road spine and entry links.

const TYPE_NAME := "worldgen.inland_layout/1"

func register_into(registry: WorldGenOperatorRegistry) -> Dictionary:
	return registry.register_operator({"id": TYPE_NAME, "schema_revision": "1", "side_effect_class": "pure", "input_ports": {},
		"output_ports": {"semantic": "SemanticWorld/1", "presentation": "PresentationWorld/1"}}, Callable(self, "compile_layout"))

func compile_layout(request: Dictionary) -> Dictionary:
	var p: Dictionary = request.get("parameters", {})
	var extent: Array = p.get("extent_cells", [])
	var buildings: Array = p.get("buildings", [])
	var width := int(extent[0]) if extent.size() == 2 else 0
	var height := int(extent[1]) if extent.size() == 2 else 0
	var road_y := int(p.get("main_road_y", height / 2))
	var road_width := int(p.get("road_width_cells", 4))
	var margin := int(p.get("edge_margin_cells", 2))
	var side_setback := int(p.get("side_setback_cells", 2))
	var front_setback := int(p.get("front_setback_cells", 2))
	var back_setback := int(p.get("back_setback_cells", 2))
	var budget := int(request.get("operation_budget", 100000))
	if width < 16 or height < 20 or buildings.is_empty() or road_width < 2:
		return _fail("E_INLAND_EXTENT: extent, road width or building program is too small")
	if road_y - road_width / 2 < margin or road_y + road_width / 2 > height - margin:
		return _fail("E_INLAND_ROAD_BOUNDS: main road leaves no bounded development rows")
	if buildings.size() > budget:
		return {"ok": false, "status": "BUDGET_EXCEEDED", "errors": ["E_INLAND_BUDGET: building placements exceed operation budget"]}
	var ordered := buildings.duplicate(true)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("id", "")) < String(b.get("id", "")))
	var seen := {}
	var rows := [{"y": margin, "limit_y": road_y - int(ceil(float(road_width) / 2.0)), "used_x": margin},
		{"y": road_y + int(ceil(float(road_width) / 2.0)), "limit_y": height - margin, "used_x": margin}]
	var parcels: Array = []
	var compiled_buildings: Array = []
	var rooms: Array = []
	var portals: Array = []
	var affordances: Array = []
	var access_profiles := {"public": ["public"], "staff": ["public", "staff"], "owner": ["public", "owner"]}
	var road_nodes := [{"id": "street/west", "at": [0, road_y]}, {"id": "street/east", "at": [width, road_y]}]
	var road_edges: Array = []
	var junction_nodes: Array = []
	var junction_by_x := {}
	var operations := 1
	for raw: Variant in ordered:
		if not raw is Dictionary: return _fail("E_INLAND_BUILDING: entries must be objects")
		var b: Dictionary = raw
		var id := String(b.get("id", ""))
		var size: Array = b.get("size_cells", [])
		if id.is_empty() or seen.has(id): return _fail("E_INLAND_ID: empty or duplicate building id %s" % id)
		if size.size() != 2: return _fail("E_INLAND_SIZE: %s needs size_cells [width,depth]" % id)
		var bw := int(size[0]); var bd := int(size[1])
		if bw < 4 or bd < 4: return _fail("E_INLAND_SIZE: %s footprint must be at least 4x4 cells" % id)
		var lot_w := bw + side_setback * 2
		var lot_d := bd + front_setback + back_setback
		var row_index := -1
		for r in range(rows.size()):
			var row: Dictionary = rows[r]
			if int(row["used_x"]) + lot_w <= width - margin and int(row["y"]) + lot_d <= int(row["limit_y"]):
				if row_index < 0 or int(row["used_x"]) < int(rows[row_index]["used_x"]): row_index = r
		if row_index < 0: return _fail("E_INLAND_NO_FIT: no bounded parcel remains for %s" % id)
		var row: Dictionary = rows[row_index]
		var lot_x := int(row["used_x"]); var lot_y := int(row["y"])
		var building_x := lot_x + side_setback
		var building_y := lot_y + back_setback if row_index == 0 else lot_y + front_setback
		var required_room_specs: Variant = b.get("rooms_required", [])
		var room_count: int = required_room_specs.size() if required_room_specs is Array and not required_room_specs.is_empty() else 1
		var first_room_width := int(floor(float(bw) / float(room_count))) + (1 if bw % room_count > 0 else 0)
		var entry_pos := [building_x + int(floor(float(first_room_width) / 2.0)), building_y + bd if row_index == 0 else building_y - 1]
		if row_index == 0 and building_y + bd >= road_y - int(ceil(float(road_width) / 2.0)):
			return _fail("E_INLAND_SETBACK: %s intersects the street corridor" % id)
		if row_index == 1 and building_y <= road_y + int(floor(float(road_width) / 2.0)):
			return _fail("E_INLAND_SETBACK: %s intersects the street corridor" % id)
		var parcel_id := "parcel/" + id
		parcels.append({"id": parcel_id, "bounds": [lot_x, lot_y, lot_w, lot_d], "building_id": id, "street_id": "street/main"})
		var building_box := [building_x, building_y, bw, bd]
		var interior := _compile_building_program(id, building_box, entry_pos, row_index == 0, b)
		if not bool(interior.get("ok", false)):
			return _fail("E_INLAND_PROGRAM: %s: %s" % [id, "; ".join(interior.get("errors", []))])
		rooms.append_array(interior["rooms"])
		portals.append_array(interior["portals"])
		affordances.append_array(interior["affordances"])
		operations += int(interior.get("operation_count", 0))
		if operations > budget: return {"ok": false, "status": "BUDGET_EXCEEDED", "errors": ["E_INLAND_BUDGET: building program compilation exceeded operation budget"]}
		compiled_buildings.append({"id": id, "program": String(b.get("program", "residential")), "shape": "rectangle",
			"box": building_box, "entry": {"position": entry_pos, "portal_id": id + "/entry", "street_id": "street/main", "access": String(interior["entry_access"])},
			"parcel_id": parcel_id, "rooms_required": b.get("rooms_required", []).duplicate(true)})
		var connector_id := "street/entry/" + id
		road_nodes.append({"id": "entry/" + id, "at": entry_pos.duplicate()})
		var junction_id := "junction/x_%03d" % int(entry_pos[0])
		if not junction_by_x.has(int(entry_pos[0])):
			var junction := {"id": junction_id, "at": [entry_pos[0], road_y]}
			junction_by_x[int(entry_pos[0])] = junction
			junction_nodes.append(junction)
			road_nodes.append(junction)
		road_edges.append({"id": connector_id, "from": "entry/" + id, "to": junction_id,
			"role": "public_access", "width_cells": int(b.get("access_width_cells", 2))})
		row["used_x"] = lot_x + lot_w
		rows[row_index] = row
		seen[id] = true
		operations += 1
		if operations > budget: return {"ok": false, "status": "BUDGET_EXCEEDED", "errors": ["E_INLAND_BUDGET: deterministic placement budget exhausted"]}
	junction_nodes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["at"][0]) < int(b["at"][0]))
	var spine_ids: Array[String] = ["street/west"]
	var previous_x := -1
	for junction: Dictionary in junction_nodes:
		var junction_x := int(junction["at"][0])
		if junction_x == previous_x: return _fail("E_INLAND_JUNCTION: duplicate junction survived coordinate merge")
		spine_ids.append(String(junction["id"]))
		previous_x = junction_x
	spine_ids.append("street/east")
	for index in range(spine_ids.size() - 1):
		road_edges.append({"id": "street/main/%02d" % index, "from": spine_ids[index], "to": spine_ids[index + 1],
			"role": "public_street", "width_cells": road_width})
	var semantic := {"kind": "inland_neighborhood", "extent_cells": [width, height], "q_per_cell": 48,
		"street_graph": {"nodes": road_nodes, "edges": road_edges}, "parcels": parcels, "buildings": compiled_buildings,
		"rooms": rooms, "portals": portals, "affordances": affordances, "access_profiles": access_profiles,
		"validation": {"bounds_checked": true, "overlap_policy": "separated_by_declared_side_setbacks", "search_operations": operations}}
	var presentation := {"profile": "code_only_2d", "style_ref": String(p.get("style_ref", "inland_village/1")),
		"district_ref": String(p.get("district_ref", "inland_residential/1")), "pixels_per_cell": 48, "visual_seed": int(p.get("visual_seed", 1))}
	return {"ok": true, "operation_count": operations, "outputs": {"semantic": {"type": "SemanticWorld/1", "data": semantic},
		"presentation": {"type": "PresentationWorld/1", "data": presentation}}}

func _compile_building_program(building_id: String, box: Array, exterior_entry: Array, entry_from_south: bool, spec: Dictionary) -> Dictionary:
	var required_rooms: Variant = spec.get("rooms_required", [])
	var required_slots: Variant = spec.get("affordances_required", [])
	if not required_rooms is Array or required_rooms.is_empty() or required_rooms.size() > 8:
		return {"ok": false, "errors": ["rooms_required must contain 1..8 explicit room records"]}
	if not required_slots is Array or required_slots.size() > 16:
		return {"ok": false, "errors": ["affordances_required must contain at most 16 records"]}
	var bx := int(box[0]); var by := int(box[1]); var bw := int(box[2]); var bh := int(box[3])
	if bw < required_rooms.size() * 3 or bh < 3:
		return {"ok": false, "errors": ["room program does not fit minimum 3-cell-wide partitions"]}
	var seen_rooms := {}; var seen_slots := {}
	var room_records: Array = []; var portal_records: Array = []; var affordance_records: Array = []
	var room_index_by_id := {}; var room_widths: Array[int] = []
	var base_width := int(floor(float(bw) / float(required_rooms.size())))
	var remainder: int = bw - base_width * required_rooms.size()
	var cursor_x := bx
	for index in range(required_rooms.size()):
		var raw_room: Variant = required_rooms[index]
		if not raw_room is Dictionary: return {"ok": false, "errors": ["room entries must be objects with id, role and access"]}
		var room_spec: Dictionary = raw_room
		var local_id := String(room_spec.get("id", "")); var role := String(room_spec.get("role", "")); var access := String(room_spec.get("access", ""))
		if not _valid_local_id(local_id) or seen_rooms.has(local_id): return {"ok": false, "errors": ["room IDs must be unique stable identifiers"]}
		if role.is_empty() or access not in ["public", "staff", "owner"]: return {"ok": false, "errors": ["room role or access policy is invalid for %s" % local_id]}
		var room_width := base_width + (1 if index < remainder else 0)
		var room_id := building_id + "/" + local_id
		var room := {"id": room_id, "building_id": building_id, "role": role, "access": access,
			"bounds": [cursor_x, by, room_width, bh]}
		room_records.append(room); room_index_by_id[local_id] = room_records.size() - 1
		room_widths.append(room_width); seen_rooms[local_id] = true; cursor_x += room_width
	var exterior_room_local := ""
	var center_x := int(exterior_entry[0]); var local_center_x := center_x - bx
	var split_cursor := 0
	for index in range(required_rooms.size()):
		if local_center_x >= split_cursor and local_center_x < split_cursor + room_widths[index]: exterior_room_local = String((required_rooms[index] as Dictionary)["id"]); break
		split_cursor += room_widths[index]
	if exterior_room_local.is_empty(): return {"ok": false, "errors": ["exterior entry does not land on a declared room"]}
	var entry_room: Dictionary = room_records[room_index_by_id[exterior_room_local]]
	var entry_inside := [center_x, by + bh - 1 if entry_from_south else by]
	var entry_access := String(entry_room["access"])
	var entry_portal_id := building_id + "/entry"
	portal_records.append({"id": entry_portal_id, "kind": "exterior", "from_room": "exterior", "to_room": String(entry_room["id"]),
		"from": exterior_entry.duplicate(), "to": entry_inside, "access": entry_access, "building_id": building_id, "width_q": 72})
	var internal_portal_ids: Array[String] = []
	for index in range(required_rooms.size() - 1):
		var left_room: Dictionary = room_records[index]; var right_room: Dictionary = room_records[index + 1]
		var left_box: Array = left_room["bounds"]; var right_box: Array = right_room["bounds"]
		var boundary_x := int(right_box[0])
		# Keep the shared doorway clear of the room-centre affordance that is
		# authored below. A centre rest slot on the approach cell otherwise
		# seals the only opening between adjacent rooms at runtime.
		var centre_y := by + int(floor(float(bh) / 2.0))
		var door_y := centre_y + 1
		if door_y >= by + bh - 1:
			door_y = centre_y - 1
		if door_y < by + 1:
			door_y = centre_y
		var door_access := "public" if String(left_room["access"]) == "public" and String(right_room["access"]) == "public" else "staff" if String(left_room["access"]) == "staff" or String(right_room["access"]) == "staff" else "owner"
		var door_id := "%s/door/%s-%s" % [building_id, String(left_room["id"]).get_slice("/", 1), String(right_room["id"]).get_slice("/", 1)]
		portal_records.append({"id": door_id, "kind": "internal", "from_room": String(left_room["id"]), "to_room": String(right_room["id"]),
			"from": [boundary_x - 1, door_y], "to": [boundary_x, door_y], "access": door_access, "building_id": building_id, "width_q": 72})
		internal_portal_ids.append(door_id)
	for raw_slot: Variant in required_slots:
		if not raw_slot is Dictionary: return {"ok": false, "errors": ["affordance entries must be objects"]}
		var slot: Dictionary = raw_slot
		var local_slot_id := String(slot.get("id", "")); var room_ref := String(slot.get("room_id", ""))
		var action := String(slot.get("action_type", "")); var access := String(slot.get("access", "")); var capacity := int(slot.get("capacity", 0))
		if not _valid_local_id(local_slot_id) or seen_slots.has(local_slot_id): return {"ok": false, "errors": ["affordance IDs must be unique stable identifiers"]}
		if not room_index_by_id.has(room_ref) or action.is_empty() or capacity < 1 or access not in ["public", "staff", "owner"]:
			return {"ok": false, "errors": ["affordance %s has an invalid room, action, access or capacity" % local_slot_id]}
		var room: Dictionary = room_records[room_index_by_id[room_ref]]
		if access == "public" and String(room["access"]) != "public": return {"ok": false, "errors": ["public affordance %s is in a restricted room" % local_slot_id]}
		var room_box: Array = room["bounds"]
		var position := [int(room_box[0]) + int(floor(float(room_box[2]) / 2.0)), int(room_box[1]) + int(floor(float(room_box[3]) / 2.0))]
		var approach := [position[0] - 1, position[1]]
		if approach[0] < int(room_box[0]): approach = [position[0] + 1, position[1]]
		if approach[0] >= int(room_box[0]) + int(room_box[2]): return {"ok": false, "errors": ["affordance %s has no room-local approach cell" % local_slot_id]}
		var room_id := String(room["id"])
		var path_result := _room_portal_path(room_id, access, portal_records)
		if path_result.is_empty(): return {"ok": false, "errors": ["affordance %s has no access-compatible portal route" % local_slot_id]}
		var portal_path: Array = path_result["portal_ids"]
		var route_start: Array = path_result["arrival"]
		var route := _orthogonal_route(route_start, approach)
		var affordance_id := building_id + "/" + local_slot_id
		affordance_records.append({"id": affordance_id, "building_id": building_id, "action_type": action, "room_id": room_id,
			"position": position, "approach": approach, "capacity": capacity, "access": access,
			"route": route, "portal_path": portal_path})
		seen_slots[local_slot_id] = true
	return {"ok": true, "rooms": room_records, "portals": portal_records, "affordances": affordance_records,
		"entry_access": entry_access, "operation_count": room_records.size() + portal_records.size() + affordance_records.size()}

func _valid_local_id(value: String) -> bool:
	if value.is_empty() or value.length() > 48: return false
	var regex := RegEx.new(); regex.compile("^[A-Za-z0-9][A-Za-z0-9_.-]*$")
	return regex.search(value) != null

func _orthogonal_route(start: Array, goal: Array) -> Array:
	var bend := [int(goal[0]), int(start[1])]
	if bend == start or bend == goal: return [start.duplicate(), goal.duplicate()]
	return [start.duplicate(), bend, goal.duplicate()]

func _room_portal_path(target_room: String, profile: String, building_portals: Array) -> Dictionary:
	var queue: Array[String] = ["exterior"]
	var parent := {"exterior": ""}
	var via := {}
	var arrivals := {"exterior": []}
	while not queue.is_empty():
		var current := queue.pop_front()
		if current == target_room: break
		for portal: Dictionary in building_portals:
			var access := String(portal.get("access", ""))
			if access != "public" and access != profile: continue
			var next := ""; var arrival: Array = []
			if String(portal.get("from_room", "")) == current:
				next = String(portal.get("to_room", "")); arrival = portal.get("to", []).duplicate()
			elif String(portal.get("to_room", "")) == current:
				next = String(portal.get("from_room", "")); arrival = portal.get("from", []).duplicate()
			if next.is_empty() or parent.has(next): continue
			parent[next] = current; via[next] = String(portal.get("id", "")); arrivals[next] = arrival; queue.append(next)
	if not parent.has(target_room): return {}
	var portal_ids: Array[String] = []; var cursor := target_room
	while String(parent.get(cursor, "")) != "":
		portal_ids.push_front(String(via[cursor])); cursor = String(parent[cursor])
	return {"portal_ids": portal_ids, "arrival": arrivals.get(target_room, [])}

func _fail(message: String) -> Dictionary:
	return {"ok": false, "status": "GLOBAL_VALIDATION_FAILED", "errors": [message]}
