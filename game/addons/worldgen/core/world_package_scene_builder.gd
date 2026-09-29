extends RefCounted
class_name WorldPackageSceneBuilder
## Builds editable native 2D Godot nodes from a frozen semantic package.
## The package stays authoritative; this consumer does not alter simulation state.

const PIXELS_PER_CELL := 16.0

static func build(package: Dictionary) -> Node2D:
	var semantic: Dictionary = package.get("semantic", {})
	var root := Node2D.new()
	root.name = "WorldPackage_" + _safe_name(String(package.get("world_id", "world")))
	root.set_meta("worldgen_world_id", String(package.get("world_id", "")))
	root.set_meta("worldgen_semantic_sha256", String(package.get("digests", {}).get("semantic_sha256", "")))
	root.set_meta("worldgen_package_schema", String(package.get("schema", "")))
	_add_water(root, semantic)
	var roads := _folder(root, "Roads")
	var parcels := _folder(root, "Parcels")
	var buildings := _folder(root, "Buildings")
	var rooms := _folder(root, "Rooms")
	var portals := _folder(root, "Portals")
	var affordances := _folder(root, "Affordances")
	var kind := String(semantic.get("kind", ""))
	if semantic.has("street_graph"):
		_add_street_graph(roads, semantic.get("street_graph", {}))
		_add_parcels(parcels, semantic.get("parcels", []))
		_add_buildings(buildings, semantic.get("buildings", []))
	if semantic.has("rooms"):
		_add_rooms(rooms, semantic.get("rooms", []))
		_add_portals(portals, semantic.get("portals", []))
		_add_affordances(affordances, semantic.get("affordances", []))
	if kind == "coastal_neighborhood":
		var topology: Dictionary = semantic.get("topology", {})
		_add_coastal_roads(roads, topology)
		_add_buildings(buildings, topology.get("buildings", []))
	return root

static func _folder(parent: Node, folder_name: String) -> Node2D:
	var node := Node2D.new()
	node.name = folder_name
	parent.add_child(node)
	return node

static func _add_water(root: Node2D, semantic: Dictionary) -> void:
	if String(semantic.get("kind", "")) != "coastal_neighborhood": return
	var topology: Dictionary = semantic.get("topology", {})
	var shoreline: Dictionary = topology.get("shoreline", {})
	var bands: Array = shoreline.get("bands", [])
	var extent: Array = semantic.get("extent_cells", [0, 0])
	if bands.is_empty() or extent.size() != 2: return
	var water := Polygon2D.new()
	water.name = "CoastalWater"
	var x := float(bands[0].get("dune_edge_x", int(extent[0]) - 24))
	var y := float(extent[1])
	water.polygon = PackedVector2Array([Vector2(x * PIXELS_PER_CELL, 0), Vector2(float(extent[0]) * PIXELS_PER_CELL, 0), Vector2(float(extent[0]) * PIXELS_PER_CELL, y * PIXELS_PER_CELL), Vector2(x * PIXELS_PER_CELL, y * PIXELS_PER_CELL)])
	water.color = Color(0.66, 0.84, 0.86, 0.78)
	water.set_meta("worldgen_kind", "water")
	root.add_child(water)
	for band: Dictionary in bands:
		var dune := Marker2D.new()
		dune.name = "DuneEdge_%03d" % int(band.get("z", 0))
		dune.position = Vector2(float(band.get("dune_edge_x", x)), float(band.get("z", 0))) * PIXELS_PER_CELL
		dune.set_meta("worldgen_kind", "shoreline_control")
		root.add_child(dune)

static func _add_street_graph(parent: Node2D, graph: Dictionary) -> void:
	var points_by_id := {}
	for node: Dictionary in graph.get("nodes", []):
		var id := String(node.get("id", "")); var at: Array = node.get("at", [0, 0])
		points_by_id[id] = at
		var marker := Marker2D.new(); marker.name = _safe_name(id)
		marker.position = _cell_point(at); marker.set_meta("worldgen_id", id); marker.set_meta("worldgen_kind", "road_node")
		parent.add_child(marker)
	for edge: Dictionary in graph.get("edges", []):
		var from_id := String(edge.get("from", "")); var to_id := String(edge.get("to", ""))
		if not points_by_id.has(from_id) or not points_by_id.has(to_id): continue
		_add_road(parent, String(edge.get("id", "road")), points_by_id[from_id], points_by_id[to_id], float(edge.get("width_cells", 1)), String(edge.get("role", "road")))

static func _add_coastal_roads(parent: Node2D, topology: Dictionary) -> void:
	var points_by_id := {}
	for node: Dictionary in topology.get("road_nodes", []): points_by_id[String(node.get("id", ""))] = node.get("at", [0, 0])
	for road: Dictionary in topology.get("roads", []):
		var from_id := String(road.get("from", "")); var to_id := String(road.get("to", ""))
		if points_by_id.has(from_id) and points_by_id.has(to_id):
			var path: Array = road.get("via", [])
			if path.size() < 2:
				path = [points_by_id[from_id], points_by_id[to_id]]
			_add_road_path(parent, String(road.get("id", "road")), path, float(road.get("width_cells", 1)), String(road.get("class", "road")))

static func _add_road(parent: Node2D, id: String, from: Array, to: Array, width_cells: float, role: String) -> void:
	_add_road_path(parent, id, [from, to], width_cells, role)

static func _add_road_path(parent: Node2D, id: String, points: Array, width_cells: float, role: String) -> void:
	var line := Line2D.new(); line.name = _safe_name(id)
	for point: Array in points:
		if point.size() == 2: line.add_point(_cell_point(point))
	if line.get_point_count() < 2:
		line.free()
		return
	line.width = maxf(2.0, width_cells * PIXELS_PER_CELL * 0.68)
	line.default_color = Color("b5aa93") if role in ["public_street", "main"] else Color("c6bca8")
	line.z_index = 2
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND; line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.set_meta("worldgen_id", id); line.set_meta("worldgen_kind", "road"); line.set_meta("worldgen_role", role); line.set_meta("worldgen_points", points.duplicate(true)); line.set_meta("worldgen_width_cells", width_cells)
	parent.add_child(line)

static func _add_parcels(parent: Node2D, items: Array) -> void:
	for parcel: Dictionary in items:
		var rect: Array = parcel.get("bounds", [0, 0, 0, 0])
		var polygon := Polygon2D.new(); polygon.name = _safe_name(String(parcel.get("id", "parcel")))
		polygon.position = _cell_point([rect[0], rect[1]])
		polygon.polygon = _local_rect(float(rect[2]) * PIXELS_PER_CELL, float(rect[3]) * PIXELS_PER_CELL)
		polygon.color = Color(0.70, 0.78, 0.65, 0.24); polygon.z_index = 1
		polygon.set_meta("worldgen_id", String(parcel.get("id", ""))); polygon.set_meta("worldgen_kind", "parcel")
		parent.add_child(polygon)
		var outline := Line2D.new(); outline.name = "ParcelEdge"
		for point: Vector2 in polygon.polygon: outline.add_point(polygon.position + point)
		outline.add_point(polygon.position + polygon.polygon[0]); outline.width = 1.0; outline.default_color = Color("789079"); outline.z_index = 2
		parent.add_child(outline)

static func _add_buildings(parent: Node2D, items: Array) -> void:
	for building: Dictionary in items:
		var rect: Array = building.get("box", [0, 0, 0, 0])
		var id := String(building.get("id", "building")); var node := Node2D.new(); node.name = _safe_name(id)
		node.position = _cell_point([rect[0], rect[1]])
		node.set_meta("worldgen_id", id); node.set_meta("worldgen_kind", "building")
		node.set_meta("worldgen_program", String(building.get("program", building.get("type", ""))))
		node.set_meta("worldgen_shape", String(building.get("shape", "rectangle")))
		node.set_meta("worldgen_bounds_cells", rect.duplicate())
		node.set_meta("worldgen_district", String(building.get("district", "")))
		var segments: Array = building.get("segments", [])
		if segments.is_empty():
			segments = [{"id": "main", "rect": rect}]
		for segment: Dictionary in segments:
			var segment_rect: Array = segment.get("rect", rect)
			if segment_rect.size() != 4: continue
			var local_rect := [int(segment_rect[0]) - int(rect[0]), int(segment_rect[1]) - int(rect[1]), int(segment_rect[2]), int(segment_rect[3])]
			var shape := _local_rect(float(local_rect[2]) * PIXELS_PER_CELL, float(local_rect[3]) * PIXELS_PER_CELL)
			var fill := Polygon2D.new(); fill.name = _safe_name(String(segment.get("id", "Footprint"))); fill.position = _cell_point([local_rect[0], local_rect[1]])
			fill.polygon = shape; fill.color = Color("d38f61"); fill.z_index = 3
			fill.set_meta("worldgen_id", id); fill.set_meta("worldgen_segment_id", String(segment.get("id", ""))); fill.set_meta("worldgen_kind", "building_footprint")
			node.add_child(fill)
			if String(building.get("shape", "")) != "open":
				var body := StaticBody2D.new(); body.name = _safe_name(String(segment.get("id", "BuildingCollision"))) + "Collision"; body.set_meta("worldgen_id", id); body.set_meta("worldgen_segment_id", String(segment.get("id", "")))
				var collider := CollisionPolygon2D.new(); collider.name = "FootprintCollision"; collider.polygon = shape; body.add_child(collider); body.position = fill.position; body.z_index = 3; node.add_child(body)
		var label := Label.new(); label.name = "BuildingLabel"; label.text = id; label.position = Vector2(4, 2); label.z_index = 4; label.add_theme_font_size_override("font_size", 14); label.add_theme_color_override("font_color", Color("322e2b")); node.add_child(label)
		var entry: Dictionary = building.get("entry", {}); var entry_at: Array = entry.get("position", entry.get("at", []))
		if not entry_at.is_empty():
			var marker := Marker2D.new(); marker.name = "Entry"; marker.position = _cell_point(entry_at) - node.position
			marker.z_index = 4; marker.set_meta("worldgen_id", id); marker.set_meta("worldgen_kind", "entry"); marker.set_meta("worldgen_access", String(entry.get("access", "public"))); marker.set_meta("worldgen_road_id", String(entry.get("road", "")))
			_add_circle(marker, "DoorMarker", 2.3, Color("fff1bd")); node.add_child(marker)
		var access_path: Array = entry.get("access_path", [])
		if access_path.size() >= 2:
			var path := Line2D.new(); path.name = "AccessPath"; path.width = maxf(2.0, float(entry.get("access_width_q", 48)) / 3.0 * 0.45); path.default_color = Color("7e9a87", 0.82); path.z_index = 2
			for q_point: Array in access_path:
				if q_point.size() == 2:
					path.add_point(Vector2(float(q_point[0]) / 3.0, float(q_point[1]) / 3.0) - node.position)
			path.set_meta("worldgen_id", id); path.set_meta("worldgen_kind", "building_access_path"); node.add_child(path)
		parent.add_child(node)

static func _add_rooms(parent: Node2D, items: Array) -> void:
	for room: Dictionary in items:
		var rect: Array = room.get("bounds", [0, 0, 0, 0]); var id := String(room.get("id", "room"))
		var polygon := Polygon2D.new(); polygon.name = _safe_name(id); polygon.position = _cell_point([rect[0], rect[1]])
		polygon.polygon = _local_rect(float(rect[2]) * PIXELS_PER_CELL, float(rect[3]) * PIXELS_PER_CELL)
		polygon.color = {"public": Color("ddaa75"), "prep": Color("94b6a1"), "storage": Color("9ca9bd")}.get(id, Color("c9c2a9"))
		polygon.z_index = 3
		polygon.set_meta("worldgen_id", id); polygon.set_meta("worldgen_kind", "room"); polygon.set_meta("worldgen_access", String(room.get("access", "")))
		parent.add_child(polygon)
		var label := Label.new(); label.name = "RoomLabel"; label.text = id; label.position = polygon.position + Vector2(4, 2); label.z_index = 4; label.add_theme_font_size_override("font_size", 15); label.add_theme_color_override("font_color", Color("263638")); parent.add_child(label)

static func _add_portals(parent: Node2D, items: Array) -> void:
	for portal: Dictionary in items:
		var points: Array = [portal.get("from", [0, 0]), portal.get("to", [0, 0])]
		var line := Line2D.new(); line.name = _safe_name(String(portal.get("id", "portal")))
		for point: Array in points: line.add_point(_cell_point(point))
		line.width = 4.0; line.default_color = Color("fff1bd"); line.z_index = 4
		line.set_meta("worldgen_id", String(portal.get("id", ""))); line.set_meta("worldgen_kind", "portal"); line.set_meta("worldgen_access", String(portal.get("access", "")))
		parent.add_child(line)

static func _add_affordances(parent: Node2D, items: Array) -> void:
	for affordance: Dictionary in items:
		var id := String(affordance.get("id", "slot")); var node := Marker2D.new(); node.name = _safe_name(id)
		node.position = _cell_point(affordance.get("position", [0, 0])); node.set_meta("worldgen_id", id)
		node.set_meta("worldgen_kind", "affordance"); node.set_meta("worldgen_action", String(affordance.get("action_type", "")))
		node.set_meta("worldgen_access", String(affordance.get("access", ""))); node.set_meta("worldgen_capacity", int(affordance.get("capacity", 0)))
		var approach: Array = affordance.get("approach", [0, 0]); var approach_marker := Marker2D.new()
		approach_marker.name = "Approach"; approach_marker.position = _cell_point(approach) - node.position
		_add_circle(approach_marker, "ApproachMarker", 1.5, Color("536eaf")); node.add_child(approach_marker)
		var route: Array = affordance.get("route", []); var path := Line2D.new(); path.name = "DeclaredRoute"; path.width = 2.0; path.default_color = Color("536eaf")
		for point: Array in route: path.add_point(_cell_point(point))
		path.z_index = 5
		parent.add_child(path)
		var approach_link := Line2D.new(); approach_link.name = _safe_name(id) + "_ApproachLink"
		approach_link.add_point(_cell_point(approach)); approach_link.add_point(node.position)
		approach_link.width = 1.5; approach_link.default_color = Color("536eaf"); approach_link.z_index = 5
		approach_link.set_meta("worldgen_id", id); approach_link.set_meta("worldgen_kind", "affordance_approach")
		parent.add_child(approach_link)
		_add_circle(node, "CapacityMarker", 2.7, Color("f7e7a3") if affordance.get("access") == "public" else Color("f7f7f2"))
		var label := Label.new(); label.name = "ActionLabel"; label.text = String(affordance.get("action_type", ""))
		label.position = Vector2(3, -7); label.scale = Vector2(0.45, 0.45); label.z_index = 6; label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color("263638")); node.add_child(label)
		parent.add_child(node)

static func _add_circle(parent: Node2D, node_name: String, radius: float, color: Color) -> void:
	var circle := Polygon2D.new(); circle.name = node_name; circle.color = color
	var points := PackedVector2Array()
	for index in range(12):
		var angle := TAU * float(index) / 12.0
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	circle.polygon = points; parent.add_child(circle)

static func _local_rect(width: float, height: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2.ZERO, Vector2(width, 0), Vector2(width, height), Vector2(0, height)])

static func _cell_point(cell: Array) -> Vector2:
	return Vector2(float(cell[0]) * PIXELS_PER_CELL, float(cell[1]) * PIXELS_PER_CELL)

static func _safe_name(value: String) -> String:
	var output := value.replace("/", "_").replace(" ", "_").replace(":", "_")
	return output if not output.is_empty() else "unnamed"
