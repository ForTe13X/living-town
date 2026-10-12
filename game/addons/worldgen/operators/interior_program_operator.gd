extends RefCounted
## Bounded single-storey room/program compiler with explicit portals, policy routes and affordance capacity.

const TYPE_NAME := "worldgen.interior_program/1"

func register_into(registry: WorldGenOperatorRegistry) -> Dictionary:
	return registry.register_operator({"id": TYPE_NAME, "schema_revision": "1", "side_effect_class": "pure", "input_ports": {},
		"output_ports": {"semantic": "SemanticWorld/1", "presentation": "PresentationWorld/1"}}, Callable(self, "compile_program"))

func compile_program(request: Dictionary) -> Dictionary:
	var p: Dictionary = request.get("parameters", {})
	var extent: Array = p.get("extent_cells", [])
	var width := int(extent[0]) if extent.size() == 2 else 0
	var depth := int(extent[1]) if extent.size() == 2 else 0
	var building_id := String(p.get("building_id", "cafe"))
	var seat_count := int(p.get("seat_count", 4))
	var staff_count := int(p.get("staff_station_count", 1))
	var budget := int(request.get("operation_budget", 100000))
	if width < 10 or depth < 12 or building_id.is_empty() or seat_count < 1 or staff_count < 1:
		return _fail("E_INTERIOR_PROGRAM: cafe envelope, identity or required capacity is invalid")
	var hall_depth := int(floor(float(depth) / 2.0))
	var lower_depth := depth - hall_depth
	var service_width := int(floor(float(width) / 2.0))
	var storage_width := width - service_width
	var rooms := [
		{"id": "public", "role": "public_hall", "bounds": [0, 0, width, hall_depth], "access": "public"},
		{"id": "prep", "role": "prep", "bounds": [0, hall_depth, service_width, lower_depth], "access": "staff"},
		{"id": "storage", "role": "storage", "bounds": [service_width, hall_depth, storage_width, lower_depth], "access": "staff"}
	]
	var center_x := int(floor(float(width) / 2.0))
	var lower_mid_y := hall_depth + int(floor(float(lower_depth) / 2.0))
	var prep_door_x := int(floor(float(service_width) / 2.0))
	var doors := [
		{"id": building_id + "/entry", "kind": "exterior", "from_room": "exterior", "to_room": "public", "from": [center_x, -1], "to": [center_x, 0], "access": "public", "width_q": 72},
		{"id": building_id + "/staff_entry", "kind": "exterior", "from_room": "exterior", "to_room": "prep", "from": [-1, lower_mid_y], "to": [0, lower_mid_y], "access": "staff", "width_q": 72},
		{"id": building_id + "/public_to_prep", "kind": "internal", "from_room": "public", "to_room": "prep", "from": [prep_door_x, hall_depth - 1], "to": [prep_door_x, hall_depth], "access": "staff", "width_q": 72},
		{"id": building_id + "/prep_to_storage", "kind": "internal", "from_room": "prep", "to_room": "storage", "from": [service_width - 1, lower_mid_y], "to": [service_width, lower_mid_y], "access": "staff", "width_q": 72}
	]
	var slots: Array = []
	var occupied_approaches := {}
	var seat_positions := _seat_positions(width, hall_depth, seat_count)
	if seat_positions.size() != seat_count: return _fail("E_INTERIOR_CAPACITY: declared seating does not fit the public hall")
	for i in range(seat_positions.size()):
		var position: Array = seat_positions[i]
		var approach := [int(position[0]), int(position[1]) + 1]
		if approach[1] >= hall_depth or occupied_approaches.has(_cell_key(approach)): return _fail("E_INTERIOR_APPROACH: seating approaches overlap or leave the hall")
		occupied_approaches[_cell_key(approach)] = true
		var route := _cell_route([center_x, 0], approach, [0, 0, width, hall_depth])
		if route.is_empty(): return _fail("E_INTERIOR_ROUTE: seat %d is unreachable" % (i + 1))
		slots.append({"id": "%s/seat_%02d" % [building_id, i + 1], "action_type": "sit", "room_id": "public", "position": position,
			"approach": approach, "capacity": 1, "access": "public", "route": route, "portal_path": [building_id + "/entry"]})
	var counter_pos := [width - 2, hall_depth - 2]
	var counter_approach := [width - 2, hall_depth - 3]
	if occupied_approaches.has(_cell_key(counter_approach)): return _fail("E_INTERIOR_APPROACH: counter approach collides with seating")
	var counter_route := _cell_route([center_x, 0], counter_approach, [0, 0, width, hall_depth])
	if counter_route.is_empty(): return _fail("E_INTERIOR_ROUTE: counter is unreachable")
	slots.append({"id": building_id + "/counter", "action_type": "buy_food", "room_id": "public", "position": counter_pos,
		"approach": counter_approach, "capacity": 1, "access": "public", "route": counter_route, "portal_path": [building_id + "/entry"]})
	for i in range(staff_count):
		var station_pos := [mini(service_width - 2, 2 + i * 2), hall_depth + mini(lower_depth - 2, 2 + i * 2)]
		var staff_approach := [station_pos[0], station_pos[1] - 1]
		if staff_approach[1] < hall_depth or occupied_approaches.has(_cell_key(staff_approach)): return _fail("E_INTERIOR_STAFF_SLOT: staff station does not fit clear space")
		occupied_approaches[_cell_key(staff_approach)] = true
		var staff_route := _cell_route([0, lower_mid_y], staff_approach, [0, hall_depth, service_width, lower_depth])
		if staff_route.is_empty(): return _fail("E_INTERIOR_ROUTE: staff station is unreachable")
		slots.append({"id": "%s/staff_%02d" % [building_id, i + 1], "action_type": "work", "room_id": "prep", "position": station_pos,
			"approach": staff_approach, "capacity": 1, "access": "staff", "route": staff_route, "portal_path": [building_id + "/staff_entry"]})
	var operations := rooms.size() + doors.size() + slots.size()
	if operations > budget: return {"ok": false, "status": "BUDGET_EXCEEDED", "errors": ["E_INTERIOR_BUDGET: program compile exceeded operation budget"]}
	var room_routes := {"public": _room_routes("exterior", "public", doors), "staff": _room_routes("exterior", "staff", doors)}
	for required_room: String in ["public"]:
		if not room_routes["public"].has(required_room): return _fail("E_INTERIOR_ROOM_ACCESS: public program room is disconnected")
	for required_room: String in ["prep", "storage"]:
		if not room_routes["staff"].has(required_room): return _fail("E_INTERIOR_ROOM_ACCESS: staff program room %s is disconnected" % required_room)
	var semantic := {"kind": "standalone_interior", "building_id": building_id, "extent_cells": [width, depth], "q_per_cell": 48,
		"rooms": rooms, "portals": doors, "room_routes": room_routes, "affordances": slots,
		"capacity": {"seating": seat_count, "service": 1, "staff_stations": staff_count},
		"access_profiles": {"public": ["public"], "staff": ["public", "prep", "storage"]}, "search_operations": operations}
	var presentation := {"profile": "code_only_2d", "style_ref": String(p.get("style_ref", "promenade_cafe/1")),
		"roof_profile": String(p.get("roof_profile", "flat_parapet/1")), "pixels_per_cell": 48}
	return {"ok": true, "operation_count": operations, "outputs": {"semantic": {"type": "SemanticWorld/1", "data": semantic},
		"presentation": {"type": "PresentationWorld/1", "data": presentation}}}

func _seat_positions(width: int, hall_depth: int, count: int) -> Array:
	var candidates: Array = []
	var y := 2
	while y < hall_depth - 2:
		for x in [2, 5, 8, 11, 14, 17, 20]:
			if x < width - 1: candidates.append([x, y])
		y += 2
	return candidates.slice(0, mini(count, candidates.size()))

func _cell_route(start: Array, goal: Array, rect: Array) -> Array:
	if start.size() != 2 or goal.size() != 2: return []
	var x0 := int(rect[0]); var y0 := int(rect[1]); var w := int(rect[2]); var h := int(rect[3])
	for point: Array in [start, goal]:
		if int(point[0]) < x0 or int(point[0]) >= x0 + w or int(point[1]) < y0 or int(point[1]) >= y0 + h: return []
	var bend := [int(goal[0]), int(start[1])]
	if bend == start or bend == goal: return [start.duplicate(), goal.duplicate()]
	return [start.duplicate(), bend, goal.duplicate()]

func _room_routes(start_room: String, profile: String, doors: Array) -> Dictionary:
	var routes := {start_room: []}
	var queue: Array[String] = [start_room]
	while not queue.is_empty():
		var current := queue.pop_front()
		for door: Dictionary in doors:
			var access := String(door.get("access", ""))
			if access != "public" and access != profile: continue
			var next := ""
			if String(door.get("from_room", "")) == current:
				next = String(door.get("to_room", ""))
			elif String(door.get("to_room", "")) == current:
				next = String(door.get("from_room", ""))
			if next.is_empty() or routes.has(next): continue
			var route: Array = routes[current].duplicate()
			route.append(String(door.get("id", "")))
			routes[next] = route
			queue.append(next)
	return routes

func _cell_key(point: Array) -> String:
	return "%d,%d" % [int(point[0]), int(point[1])]

func _fail(message: String) -> Dictionary:
	return {"ok": false, "status": "GLOBAL_VALIDATION_FAILED", "errors": [message]}
