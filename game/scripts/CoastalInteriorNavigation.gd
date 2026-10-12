extends RefCounted
class_name CoastalInteriorNavigation
## Deterministic room/cell route compiler for the authored S1 floor plans.
## This is a package-level geometry check, not a binding to the live Sim actor.

const CELL_Q := 48


static func route_to_slot(interior: Dictionary, slot: Dictionary, radius_q: int = 20, access_tags: Array[String] = ["resident", "staff"]) -> Dictionary:
	if radius_q < 0 or radius_q * 2 > CELL_Q:
		return {"ok": false, "error": "E_NAV_RADIUS: actor diameter exceeds the authored cell width"}
	var rooms: Dictionary = {}
	var room_cells: Dictionary = {}
	for room: Dictionary in interior.get("rooms", []):
		var room_id := str(room.get("id", ""))
		if not _has_access(str(room.get("access_policy", "public")), access_tags):
			continue
		var bounds: Array = room.get("bounds_q", [])
		if bounds.size() != 4:
			continue
		rooms[room_id] = room
		room_cells[room_id] = {}
		var left := floori(float(bounds[0]) / CELL_Q)
		var top := floori(float(bounds[1]) / CELL_Q)
		var right := ceili(float(bounds[0] + bounds[2]) / CELL_Q)
		var bottom := ceili(float(bounds[1] + bounds[3]) / CELL_Q)
		for y in range(top, bottom):
			for x in range(left, right):
				var center := Vector2i(x * CELL_Q + CELL_Q / 2, y * CELL_Q + CELL_Q / 2)
				if _clearance_fits(center, radius_q, bounds):
					room_cells[room_id][Vector2i(x, y)] = true
	var entry_room := str(interior.get("entry_room", ""))
	var entry_anchor: Array = interior.get("entry_at_q", [])
	if not rooms.has(entry_room) or entry_anchor.size() != 2:
		return {"ok": false, "error": "E_NAV_ENTRY: missing or unauthorized entry room/anchor"}
	var start_cell := _q_to_cell(entry_anchor)
	if not room_cells[entry_room].has(start_cell):
		return {"ok": false, "error": "E_NAV_ENTRY: entry anchor has no radius-clear floor cell"}
	var target_room := str(slot.get("room", ""))
	var target: Array = slot.get("approach_q", [])
	if not _has_access(str(slot.get("access_policy", "public")), access_tags):
		return {"ok": false, "error": "E_NAV_ACCESS: actor profile cannot use this affordance"}
	if not rooms.has(target_room) or target.size() != 2:
		return {"ok": false, "error": "E_NAV_SLOT: missing or unauthorized slot room/approach"}
	var target_cell := _q_to_cell(target)
	if not room_cells[target_room].has(target_cell):
		return {"ok": false, "error": "E_NAV_SLOT: approach has no radius-clear floor cell"}
	var links := {}
	for door: Dictionary in interior.get("doors", []):
		if not _has_access(str(door.get("access_policy", "public")), access_tags):
			continue
		var from_room := str(door.get("from_room", ""))
		var to_room := str(door.get("to_room", ""))
		if not room_cells.has(from_room) or not room_cells.has(to_room) or int(door.get("clear_width_q", 0)) < radius_q * 2:
			continue
		var cells := portal_cells(door.get("at_q", []), rooms[from_room].get("bounds_q", []), rooms[to_room].get("bounds_q", []))
		if cells.size() != 2 or not room_cells[from_room].has(cells[0]) or not room_cells[to_room].has(cells[1]):
			continue
		_add_link(links, _state_key(from_room, cells[0]), {"room": to_room, "cell": cells[1], "portal": str(door.get("id", ""))})
		_add_link(links, _state_key(to_room, cells[1]), {"room": from_room, "cell": cells[0], "portal": str(door.get("id", ""))})
	var start := {"room": entry_room, "cell": start_cell}
	var start_key := _state_key(entry_room, start_cell)
	var target_key := _state_key(target_room, target_cell)
	var queue: Array[Dictionary] = [start]
	var head := 0
	var previous := {start_key: ""}
	var via_portal := {}
	while head < queue.size() and not previous.has(target_key):
		var current: Dictionary = queue[head]
		head += 1
		var current_room := str(current["room"])
		var current_cell: Vector2i = current["cell"]
		var next_states: Array[Dictionary] = []
		for delta: Vector2i in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			var next_cell := current_cell + delta
			if room_cells[current_room].has(next_cell):
				next_states.append({"room": current_room, "cell": next_cell, "portal": ""})
		for link: Dictionary in links.get(_state_key(current_room, current_cell), []):
			next_states.append(link)
		for next_state: Dictionary in next_states:
			var next_key := _state_key(str(next_state["room"]), next_state["cell"])
			if previous.has(next_key):
				continue
			previous[next_key] = _state_key(current_room, current_cell)
			via_portal[next_key] = str(next_state.get("portal", ""))
			queue.append({"room": next_state["room"], "cell": next_state["cell"]})
	if not previous.has(target_key):
		return {"ok": false, "error": "E_NAV_UNREACHABLE: no radius-clear route from entry to slot approach"}
	var reversed_states: Array[Dictionary] = []
	var cursor := target_key
	while not cursor.is_empty():
		var parts := cursor.split("|")
		var coordinates := parts[1].split(",")
		reversed_states.append({"room": parts[0], "cell": Vector2i(int(coordinates[0]), int(coordinates[1])), "key": cursor})
		cursor = str(previous.get(cursor, ""))
	reversed_states.reverse()
	var path_q: Array = []
	var room_path: Array[String] = []
	var portal_path: Array[String] = []
	for state: Dictionary in reversed_states:
		var cell: Vector2i = state["cell"]
		var point := [cell.x * CELL_Q + CELL_Q / 2, cell.y * CELL_Q + CELL_Q / 2]
		if path_q.is_empty() or path_q[-1] != point:
			path_q.append(point)
		var room_id := str(state["room"])
		if room_path.is_empty() or room_path[-1] != room_id:
			room_path.append(room_id)
		var portal_id := str(via_portal.get(str(state["key"]), ""))
		if not portal_id.is_empty():
			portal_path.append(portal_id)
	return {"ok": true, "path_q": path_q, "room_path": room_path, "portal_path": portal_path, "provisional_actor_radius_q": radius_q}


static func _has_access(policy: String, tags: Array[String]) -> bool:
	if policy == "public":
		return true
	if policy in ["authorized", "resident_or_staff"]:
		return tags.has("resident") or tags.has("staff") or tags.has("authorized")
	return false


static func _clearance_fits(center: Vector2i, radius_q: int, bounds: Array) -> bool:
	return center.x - radius_q >= int(bounds[0]) and center.x + radius_q <= int(bounds[0]) + int(bounds[2]) and center.y - radius_q >= int(bounds[1]) and center.y + radius_q <= int(bounds[1]) + int(bounds[3])


static func _q_to_cell(point: Array) -> Vector2i:
	return Vector2i(floori(float(point[0]) / CELL_Q), floori(float(point[1]) / CELL_Q))


static func portal_cells(point: Array, from_bounds: Array, to_bounds: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if point.size() != 2 or from_bounds.size() != 4 or to_bounds.size() != 4:
		return result
	var x := int(point[0]); var y := int(point[1])
	var candidates: Array[Vector2i] = []
	var from_right := int(from_bounds[0]) + int(from_bounds[2])
	var from_bottom := int(from_bounds[1]) + int(from_bounds[3])
	var to_right := int(to_bounds[0]) + int(to_bounds[2])
	var to_bottom := int(to_bounds[1]) + int(to_bounds[3])
	var horizontal_interface := (from_bottom == int(to_bounds[1]) or to_bottom == int(from_bounds[1])) and y in [from_bottom, to_bottom]
	var vertical_interface := (from_right == int(to_bounds[0]) or to_right == int(from_bounds[0])) and x in [from_right, to_right]
	if horizontal_interface:
		candidates = [Vector2i(floori(float(x) / CELL_Q), floori(float(y - 1) / CELL_Q)), Vector2i(floori(float(x) / CELL_Q), floori(float(y) / CELL_Q))]
	elif vertical_interface:
		candidates = [Vector2i(floori(float(x - 1) / CELL_Q), floori(float(y) / CELL_Q)), Vector2i(floori(float(x) / CELL_Q), floori(float(y) / CELL_Q))]
	else:
		return result
	var from_cell := Vector2i(2147483647, 2147483647)
	var to_cell := Vector2i(2147483647, 2147483647)
	for candidate: Vector2i in candidates:
		if _cell_inside(candidate, from_bounds):
			from_cell = candidate
		if _cell_inside(candidate, to_bounds):
			to_cell = candidate
	if from_cell.x == 2147483647 or to_cell.x == 2147483647:
		return result
	result.append(from_cell)
	result.append(to_cell)
	return result


static func _cell_inside(cell: Vector2i, bounds: Array) -> bool:
	return cell.x >= floori(float(bounds[0]) / CELL_Q) and cell.x < ceili(float(bounds[0] + bounds[2]) / CELL_Q) and cell.y >= floori(float(bounds[1]) / CELL_Q) and cell.y < ceili(float(bounds[1] + bounds[3]) / CELL_Q)


static func _state_key(room_id: String, cell: Vector2i) -> String:
	return "%s|%d,%d" % [room_id, cell.x, cell.y]


static func _add_link(links: Dictionary, key: String, link: Dictionary) -> void:
	if not links.has(key):
		links[key] = []
	links[key].append(link)
