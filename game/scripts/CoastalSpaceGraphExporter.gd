extends RefCounted
class_name CoastalSpaceGraphExporter
## Emit an opt-in overlay compatible with Living Town's SpaceGraph and interior nav grids.
## This does not modify data/spaces.json, data/interiors.json, Sim, or authored agents.

const NAVIGATOR := preload("res://scripts/CoastalInteriorNavigation.gd")
const SPACE_GRAPH := preload("res://scripts/SpaceGraph.gd")
const PACKAGE_COMPILER := preload("res://scripts/CoastalPackageCompiler.gd")
const OUTDOOR_SPACE_ID := "coastal_s1"
const FLOOR_ID := "ground"


static func compile_overlay(package: Dictionary) -> Dictionary:
	var package_validation: Dictionary = PACKAGE_COMPILER.validate_package(package)
	if not bool(package_validation.get("ok", false)):
		return {"ok": false, "errors": package_validation.get("errors", [])}
	var topology: Dictionary = package.get("topology", {})
	if topology.is_empty():
		return {"ok": false, "errors": ["E_COAST_OVERLAY: package topology is missing"]}
	var extent: Array = topology.get("extent_cells", [])
	if extent.size() != 2 or int(extent[0]) <= 0 or int(extent[1]) <= 0:
		return {"ok": false, "errors": ["E_COAST_OVERLAY: invalid map extent"]}
	var width := int(extent[0]); var height := int(extent[1])
	var spaces := {
		OUTDOOR_SPACE_ID: {"kind": "outdoor", "label": str(package.get("title", "Warm Bay S1")), "bounds": [0, 0, width, height], "floors": ["outdoor"], "default_floor": "outdoor"}
	}
	var interiors := {}
	var portals: Array = []
	var affordances: Array = []
	var home_anchors: Array = []
	var room_locations := {}
	var blocked_cells := {}
	var nodes := {}
	for node: Dictionary in topology.get("road_nodes", []):
		nodes[str(node.get("id", ""))] = Vector2(float(node["at"][0]), float(node["at"][1]))
	var crossing_clear := _crossing_cells(topology, width, height)
	_block_coast(topology.get("shoreline", {}), width, height, crossing_clear, blocked_cells)
	for building: Dictionary in topology.get("buildings", []):
		var building_id := str(building.get("id", ""))
		var building_space_id := OUTDOOR_SPACE_ID + "/" + building_id
		var building_box: Array = building.get("box", [])
		if building_box.size() != 4:
			return {"ok": false, "errors": ["E_COAST_OVERLAY: %s has no bounds" % building_id]}
		spaces[building_space_id] = {"kind": "interior", "label": building_id + " access domain", "bounds": [0, 0, int(building_box[2]), int(building_box[3])], "floors": [FLOOR_ID], "default_floor": FLOOR_ID}
		for segment: Dictionary in building.get("segments", []):
			var rect: Array = segment.get("rect", [])
			if rect.size() != 4:
				continue
			for y in range(int(rect[1]), int(rect[1]) + int(rect[3])):
				for x in range(int(rect[0]), int(rect[0]) + int(rect[2])):
					blocked_cells[Vector2i(x, y)] = true
		var interior: Dictionary = building.get("interior", {})
		for room: Dictionary in interior.get("rooms", []):
			var room_id := str(room.get("id", ""))
			var room_space_id := building_space_id + "/" + room_id
			var bounds: Array = room.get("bounds_q", [])
			if bounds.size() != 4 or not _bounds_are_cell_aligned(bounds):
				return {"ok": false, "errors": ["E_COAST_OVERLAY_ROOM: %s/%s is not q-grid aligned" % [building_id, room_id]]}
			var cell_origin := Vector2i(int(bounds[0]) / 48, int(bounds[1]) / 48)
			var room_width := int(bounds[2]) / 48; var room_height := int(bounds[3]) / 48
			spaces[room_space_id] = {"kind": "interior", "label": "%s · %s" % [building_id, str(room.get("role", room_id))], "bounds": [0, 0, room_width, room_height], "floors": [FLOOR_ID], "default_floor": FLOOR_ID, "home_space": building_space_id}
			interiors[room_space_id] = {FLOOR_ID: {"label": str(room.get("role", room_id)), "floor": "stone", "furniture": []}}
			room_locations[building_id + "/" + room_id] = {"space_id": room_space_id, "bounds_q": bounds, "cell_origin": cell_origin, "building_space_id": building_space_id, "access_policy": str(room.get("access_policy", "public"))}
		var entry: Dictionary = building.get("entry", {})
		var entry_at: Array = entry.get("at", [])
		var entry_anchor: Array = interior.get("entry_at_q", [])
		var entry_room_id := str(interior.get("entry_room", ""))
		if entry_at.size() != 2 or entry_anchor.size() != 2 or not room_locations.has(building_id + "/" + entry_room_id):
			return {"ok": false, "errors": ["E_COAST_OVERLAY_ENTRY: %s has no resolvable exterior/interior anchor" % building_id]}
		var entry_room: Dictionary = room_locations[building_id + "/" + entry_room_id]
		var home_private := str(building.get("type", "")) in ["veranda_home", "courtyard_home"]
		var external_access := "owner" if home_private else "public"
		var owner_access_space_id := building_space_id
		var exterior_portal := {"id": OUTDOOR_SPACE_ID + "/" + building_id + "/entry", "kind": "door",
			"from": {"space": OUTDOOR_SPACE_ID, "floor": "outdoor", "pos": entry_at.duplicate()},
			"to": {"space": entry_room["space_id"], "floor": FLOOR_ID,
				"pos": _q_point_to_room_cell(entry_anchor, entry_room["cell_origin"])},
			"bidirectional": true, "access": external_access, "traversal_cost": 1}
		if home_private:
			# Sim home identity is a dwelling domain, while spatial_address may
			# begin in any room within that domain.
			exterior_portal["owner_space"] = owner_access_space_id
		portals.append(exterior_portal)
		if home_private:
			home_anchors.append({"building_id": building_id, "space_id": str(entry_room["space_id"]), "home_space_id": owner_access_space_id, "floor_id": FLOOR_ID,
				"position": _q_point_to_room_cell(entry_anchor, entry_room["cell_origin"]), "entry_portal_id": str(exterior_portal["id"])})
		for door: Dictionary in interior.get("doors", []):
			var from_room_id := str(door.get("from_room", "")); var to_room_id := str(door.get("to_room", ""))
			if not room_locations.has(building_id + "/" + from_room_id) or not room_locations.has(building_id + "/" + to_room_id):
				return {"ok": false, "errors": ["E_COAST_OVERLAY_DOOR: %s has a dangling room reference" % building_id]}
			var from_room: Dictionary = room_locations[building_id + "/" + from_room_id]; var to_room: Dictionary = room_locations[building_id + "/" + to_room_id]
			var endpoints := NAVIGATOR.portal_cells(door.get("at_q", []), from_room["bounds_q"], to_room["bounds_q"])
			if endpoints.size() != 2:
				return {"ok": false, "errors": ["E_COAST_OVERLAY_DOOR: %s/%s cannot resolve portal endpoints" % [building_id, str(door.get("id", "?"))]]}
			var access := "owner" if str(door.get("access_policy", "public")) == "resident_or_staff" else "public"
			var portal := {"id": OUTDOOR_SPACE_ID + "/" + str(door.get("id", "")), "kind": "door",
				"from": {"space": from_room["space_id"], "floor": FLOOR_ID, "pos": _room_cell_to_local(endpoints[0], from_room["cell_origin"])},
				"to": {"space": to_room["space_id"], "floor": FLOOR_ID, "pos": _room_cell_to_local(endpoints[1], to_room["cell_origin"])},
				"bidirectional": true, "access": access, "traversal_cost": 1}
			if access == "owner":
				portal["owner_space"] = owner_access_space_id
			portals.append(portal)
		var compiled_routes: Dictionary = interior.get("compiled_routes", {})
		for slot: Dictionary in interior.get("slots", []):
			var slot_room_id := str(slot.get("room", ""))
			var slot_room_key := building_id + "/" + slot_room_id
			if not room_locations.has(slot_room_key):
				return {"ok": false, "errors": ["E_COAST_OVERLAY_SLOT: %s/%s has no room" % [building_id, str(slot.get("id", "?"))]]}
			var slot_room: Dictionary = room_locations[slot_room_key]
			var slot_id := str(slot.get("id", ""))
			var slot_route: Dictionary = compiled_routes.get(slot_id, {})
			affordances.append({"id": slot_id, "building_id": building_id, "action": str(slot.get("action", "")),
				"address": {"space_id": slot_room["space_id"], "floor_id": FLOOR_ID, "room_id": slot_room_id,
					"position": _q_point_to_room_cell(slot.get("at_q", []), slot_room["cell_origin"])},
				"approach": _q_point_to_room_cell(slot.get("approach_q", []), slot_room["cell_origin"]),
				"facing": str(slot.get("facing", "")), "capacity": int(slot.get("capacity", 1)),
				"clearance_q": slot.get("clearance_q", []), "access_policy": str(slot.get("access_policy", "public")),
				"duration_policy": str(slot.get("duration_policy", "")), "route": slot_route.duplicate(true)})
	interiors[OUTDOOR_SPACE_ID] = {"outdoor": {"label": "Warm Bay ground", "floor": "coastal_ground", "furniture": _blocked_records(blocked_cells, width, height)}}
	var graph: RefCounted = SPACE_GRAPH.new()
	graph.spaces = spaces
	graph.portals = portals
	var graph_errors: Array = graph.validate()
	if not graph_errors.is_empty():
		return {"ok": false, "errors": graph_errors}
	return {"ok": true, "errors": [], "spaces": {"spaces": spaces, "portals": portals}, "interiors": interiors,
		"affordances": {"schema_version": 1, "affordances": affordances, "home_anchors": home_anchors},
		"metadata": {"space_count": spaces.size(), "portal_count": portals.size(), "affordance_count": affordances.size(), "blocked_outdoor_cells": blocked_cells.size(),
			"town_id": str(package.get("town_id", "")),
			"source_sha256": str(package.get("manifest", {}).get("source_sha256", "")),
			"source_topology_sha256": str(package.get("manifest", {}).get("topology_sha256", "")),
			"owner_access_mapping": "owner portals target the resident spatial_address space; staff policy still requires a Sim access extension",
			"home_anchor_count": home_anchors.size(), "effects_and_reservations_wired": false, "changes_live_sim": false}}


static func _q_point_to_room_cell(point: Array, cell_origin: Vector2i) -> Array:
	return [floori(float(point[0]) / 48.0) - cell_origin.x, floori(float(point[1]) / 48.0) - cell_origin.y]


static func _room_cell_to_local(cell: Vector2i, cell_origin: Vector2i) -> Array:
	return [cell.x - cell_origin.x, cell.y - cell_origin.y]


static func _bounds_are_cell_aligned(bounds: Array) -> bool:
	for value: Variant in bounds:
		if int(value) % 48 != 0:
			return false
	return true


static func _block_coast(shoreline: Dictionary, width: int, height: int, crossings: Dictionary, blocked: Dictionary) -> void:
	var controls: Array = shoreline.get("bands", [])
	var offsets: Dictionary = shoreline.get("offsets_cells", {})
	var toe := int(offsets.get("dune_toe", 0))
	var high_water := int(offsets.get("high_water", 0))
	for y in range(height):
		var edge := _shore_x(float(y) + 0.5, controls)
		for x in range(width):
			var is_dune := float(x) + 0.5 >= edge and float(x) + 0.5 < edge + float(toe)
			var is_water_or_intertidal := float(x) + 0.5 >= edge + float(high_water)
			# Public crossing corridors may cut through dune cells, never through
			# high-water/intertidal exclusions, even if their geometry overshoots.
			if (is_water_or_intertidal or (is_dune and not crossings.has(Vector2i(x, y)))):
				blocked[Vector2i(x, y)] = true


static func _crossing_cells(topology: Dictionary, width: int, height: int) -> Dictionary:
	var nodes := {}
	for node: Dictionary in topology.get("road_nodes", []):
		nodes[str(node.get("id", ""))] = Vector2(float(node["at"][0]), float(node["at"][1]))
	var crossing_roads: Array = []
	for road: Dictionary in topology.get("roads", []):
		if str(road.get("class", "")) != "beach_crossing":
			continue
		var points: Array = []
		if road.has("via"):
			for raw_point: Variant in road.get("via", []):
				if raw_point is Array and raw_point.size() == 2:
					points.append(Vector2(float(raw_point[0]), float(raw_point[1])))
				elif raw_point is Vector2:
					points.append(raw_point)
		else:
			points = [nodes.get(str(road.get("from", "")), Vector2.ZERO), nodes.get(str(road.get("to", "")), Vector2.ZERO)]
		crossing_roads.append({"points": points, "half_width": float(road.get("width_cells", 0)) * 0.5})
	var result := {}
	for y in range(height):
		for x in range(width):
			var center := Vector2(float(x) + 0.5, float(y) + 0.5)
			for crossing: Dictionary in crossing_roads:
				var points: Array = crossing["points"]
				for i in range(points.size() - 1):
					if _distance_to_segment(center, points[i], points[i + 1]) <= float(crossing["half_width"]):
						result[Vector2i(x, y)] = true
						break
				if result.has(Vector2i(x, y)):
					break
	return result


static func _shore_x(z: float, controls: Array) -> float:
	if controls.is_empty():
		return 0.0
	for index in range(controls.size() - 1):
		var a: Dictionary = controls[index]; var b: Dictionary = controls[index + 1]
		if z <= float(b["z"]):
			var t := inverse_lerp(float(a["z"]), float(b["z"]), z)
			return lerpf(float(a["dune_edge_x"]), float(b["dune_edge_x"]), t)
	return float(controls[-1]["dune_edge_x"])


static func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var delta := b - a
	var t := 0.0 if delta.length_squared() <= 0.0 else clampf((point - a).dot(delta) / delta.length_squared(), 0.0, 1.0)
	return point.distance_to(a + delta * t)


static func _blocked_records(blocked: Dictionary, width: int, height: int) -> Array:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in blocked.keys():
		if cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height:
			cells.append(cell)
	cells.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y if a.y != b.y else a.x < b.x)
	var furniture: Array = []
	for cell: Vector2i in cells:
		furniture.append({"slot": "wall", "pos": [cell.x, cell.y], "size": [1, 1]})
	return furniture\n