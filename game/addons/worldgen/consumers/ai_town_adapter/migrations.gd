extends RefCounted
class_name WorldPackageAitownMigrations
## Fail-closed save/package compatibility preflight.
## Structural remapping remains offline and requires a reviewed ID map.

func validate_save_reference(save_schema: int, saved_ref: Dictionary, state: Dictionary,
		current_ref: Dictionary, authored_spaces: Dictionary, authored_portals: Array,
		authored_interiors: Dictionary) -> Dictionary:
	if save_schema == 1:
		if not current_ref.is_empty() or not saved_ref.is_empty():
			return _failure("E_MIGRATION_TOPOLOGY_MISSING: schema 1 has no package/topology reference")
		return {"ok": true, "world_package_ref": {}, "migration": "schema1_legacy"}
	var has_topology_snapshot := state.has("_spaces") and state.has("_portals") and state.has("_interiors_data")
	if not has_topology_snapshot:
		return _failure("E_MIGRATION_TOPOLOGY_MISSING: save lacks receiver-owned topology snapshots")
	if state.get("_spaces") != authored_spaces or state.get("_portals") != authored_portals \
			or state.get("_interiors_data") != authored_interiors:
		return _failure("E_MIGRATION_TOPOLOGY_CHANGED: identity migration cannot move occupants or active actions")
	if save_schema == 2:
		# Schema 2 did not record a package digest. Its exact embedded spatial snapshots are
		# sufficient for a reference-only upgrade, but never for structural regeneration.
		if not saved_ref.is_empty() and saved_ref != current_ref:
			return _failure("E_MIGRATION_PACKAGE_ID: saved package identity does not match this world")
		return {"ok": true, "world_package_ref": current_ref.duplicate(true), "migration": "schema2_reference_backfill"}
	return _failure("E_MIGRATION_SCHEMA: no topology migration path for schema %d" % save_schema)

## Prepare an explicit offline topology migration. The caller must persist the returned state as a
## separate candidate save and run the host Sim's full save validator before replacing any source.
## Every old space/floor is mapped; coordinates use authored offsets and active options are cleared
## so saved residents cannot resume actions against furniture IDs from the old package.
func prepare_offline_migration(state: Dictionary, migration: Dictionary, saved_ref: Dictionary,
		current_ref: Dictionary, authored_spaces: Dictionary, authored_portals: Array,
		authored_interiors: Dictionary, current_interior_objects: Array) -> Dictionary:
	if String(migration.get("schema", "")) != "worldgen.aitown-migration/1":
		return _failure("E_MIGRATION_MANIFEST: unsupported schema")
	if migration.get("from", {}) != saved_ref or migration.get("to", {}) != current_ref:
		return _failure("E_MIGRATION_PACKAGE_ID: manifest source/target identity mismatch")
	if saved_ref.is_empty() or current_ref.is_empty():
		return _failure("E_MIGRATION_PACKAGE_ID: structural migration requires package identities")
	if String(migration.get("active_action_policy", "")) != "cancel_all_agent_options":
		return _failure("E_MIGRATION_ACTION_POLICY: explicit cancel_all_agent_options policy required")
	var old_spaces: Variant = state.get("_spaces")
	var old_interiors: Variant = state.get("_interiors_data")
	var old_portals: Variant = state.get("_portals")
	if not old_spaces is Dictionary or not old_interiors is Dictionary or not old_portals is Array:
		return _failure("E_MIGRATION_TOPOLOGY_MISSING: save lacks spatial snapshots")
	var source_world: Variant = state.get("world")
	if not source_world is Dictionary or not source_world.get("objects") is Dictionary:
		return _failure("E_MIGRATION_WORLD: saved world object index is invalid")
	var space_map: Variant = migration.get("spaces")
	var floor_map: Variant = migration.get("floors")
	var position_offsets: Variant = migration.get("position_offsets")
	if not space_map is Dictionary or not floor_map is Dictionary or not position_offsets is Dictionary:
		return _failure("E_MIGRATION_MAP: spaces, floors, and position_offsets must be objects")
	if space_map.size() != old_spaces.size() or floor_map.size() != old_spaces.size() or position_offsets.size() != old_spaces.size():
		return _failure("E_MIGRATION_MAP: mappings must cover exactly the saved spaces")
	for old_space_value: Variant in old_spaces:
		var old_space := String(old_space_value)
		if not space_map.has(old_space) or not floor_map.has(old_space) or not position_offsets.has(old_space):
			return _failure("E_MIGRATION_MAP: missing explicit mapping for space %s" % old_space)
		if typeof(space_map[old_space]) != TYPE_STRING:
			return _failure("E_MIGRATION_MAP: destination space ID must be a string: %s" % old_space)
		if not old_spaces[old_space] is Dictionary:
			return _failure("E_MIGRATION_TOPOLOGY_MISSING: saved space definition is invalid: %s" % old_space)
		var new_space := String(space_map[old_space])
		if new_space.is_empty() or (new_space != "town" and not authored_spaces.has(new_space)):
			return _failure("E_MIGRATION_MAP: destination space is absent: %s" % new_space)
		var old_space_data: Dictionary = old_spaces[old_space]
		var target_floors: Array = ["outdoor"] if new_space == "town" else _string_array(authored_spaces[new_space].get("floors", []))
		var old_floors: Array = _string_array(old_space_data.get("floors", []))
		var per_space_floors: Variant = floor_map[old_space]
		var per_space_offsets: Variant = position_offsets[old_space]
		if not per_space_floors is Dictionary or not per_space_offsets is Dictionary:
			return _failure("E_MIGRATION_MAP: floor and offset maps must be objects for %s" % old_space)
		if per_space_floors.size() != old_floors.size() or per_space_offsets.size() != old_floors.size():
			return _failure("E_MIGRATION_MAP: every source floor needs one floor and coordinate mapping: %s" % old_space)
		for old_floor_value: Variant in old_floors:
			var old_floor := String(old_floor_value)
			if typeof(per_space_floors.get(old_floor)) != TYPE_STRING:
				return _failure("E_MIGRATION_MAP: destination floor ID must be a string: %s:%s" % [old_space, old_floor])
			var new_floor := String(per_space_floors.get(old_floor, ""))
			var offset: Variant = per_space_offsets.get(old_floor)
			if new_floor.is_empty() or not target_floors.has(new_floor) or not offset is Array or offset.size() != 2:
				return _failure("E_MIGRATION_MAP: invalid floor/offset mapping for %s:%s" % [old_space, old_floor])
			if typeof(offset[0]) != TYPE_INT or typeof(offset[1]) != TYPE_INT:
				return _failure("E_MIGRATION_MAP: offsets must be integer cells for %s:%s" % [old_space, old_floor])
	var prepared: Dictionary = state.duplicate(true)
	var agents: Variant = prepared.get("agents")
	if not agents is Array:
		return _failure("E_MIGRATION_AGENT: saved agents must be an array")
	var cancelled_options := 0
	for raw_agent: Variant in agents:
		if not raw_agent is Dictionary:
			return _failure("E_MIGRATION_AGENT: saved agent entry is not an object")
		var agent: Dictionary = raw_agent
		for prefix: String in ["", "home_"]:
			var space_key := prefix + "space"
			var floor_key := prefix + "floor"
			var old_space := String(agent.get(space_key, ""))
			var old_floor := String(agent.get(floor_key, ""))
			if old_space.is_empty() or not space_map.has(old_space) \
					or not floor_map.has(old_space) or not floor_map[old_space].has(old_floor):
				return _failure("E_MIGRATION_AGENT: unmapped resident address for %s" % String(agent.get("id", "<unknown>")))
			var offset: Array = position_offsets[old_space][old_floor]
			agent[space_key] = String(space_map[old_space])
			agent[floor_key] = String(floor_map[old_space][old_floor])
			if prefix.is_empty():
				if not (agent.get("pos") is Vector2i):
					return _failure("E_MIGRATION_AGENT: position is invalid for %s" % String(agent.get("id", "<unknown>")))
				agent["pos"] = agent["pos"] + Vector2i(int(offset[0]), int(offset[1]))
				if agent.get("option") != null: cancelled_options += 1
				agent["option"] = null
				var mapped_space := String(agent[space_key]); var mapped_floor := String(agent[floor_key])
				agent["area"] = mapped_space + ":" + mapped_floor if mapped_space != "town" or mapped_floor != "outdoor" else _outdoor_area(prepared.get("world", {}), agent["pos"])
				agent["room"] = _outdoor_room(prepared.get("world", {}), agent["pos"]) if mapped_space == "town" and mapped_floor == "outdoor" else ""
	var saved_world: Dictionary = prepared["world"]
	var rebuilt_objects: Dictionary = saved_world["objects"].duplicate(true)
	var old_interior_object_ids := _interior_object_ids(old_interiors)
	for object_id: Variant in rebuilt_objects.keys():
		if old_interior_object_ids.has(String(object_id)):
			rebuilt_objects.erase(object_id)
	for definition_value: Variant in current_interior_objects:
		if not definition_value is Dictionary:
			return _failure("E_MIGRATION_WORLD: replacement interior object is invalid")
		var definition: Dictionary = definition_value.duplicate(true)
		var object_id := String(definition.get("id", ""))
		var object_space := String(definition.get("space", ""))
		if object_id.is_empty() or object_space.is_empty() or object_space == "town" or not authored_spaces.has(object_space):
			return _failure("E_MIGRATION_WORLD: replacement object has invalid spatial authority")
		if rebuilt_objects.has(object_id):
			return _failure("E_MIGRATION_WORLD: replacement object ID collision: %s" % object_id)
		var point: Variant = definition.get("pos")
		if not point is Array or point.size() != 2:
			return _failure("E_MIGRATION_WORLD: replacement object position is invalid: %s" % object_id)
		definition["pos"] = Vector2i(int(point[0]), int(point[1]))
		rebuilt_objects[object_id] = definition
	saved_world["objects"] = rebuilt_objects
	prepared["_spaces"] = authored_spaces.duplicate(true)
	prepared["_portals"] = authored_portals.duplicate(true)
	prepared["_interiors_data"] = authored_interiors.duplicate(true)
	return {"ok": true, "state": prepared, "world_package_ref": current_ref.duplicate(true),
		"cancelled_options": cancelled_options, "migration": "explicit_offline_topology_map"}

func _outdoor_area(world: Dictionary, pos: Vector2i) -> String:
	for area_id: Variant in world.get("areas", {}):
		var area: Variant = world["areas"][area_id]
		if not area is Dictionary: continue
		var rect: Variant = area.get("rect", [])
		if rect is Array and rect.size() == 4 and pos.x >= int(rect[0]) and pos.x < int(rect[0]) + int(rect[2]) \
				and pos.y >= int(rect[1]) and pos.y < int(rect[1]) + int(rect[3]):
			return String(area_id)
	return ""

func _outdoor_room(world: Dictionary, pos: Vector2i) -> String:
	for room_id: Variant in world.get("rooms", {}):
		var room: Variant = world["rooms"][room_id]
		if not room is Dictionary: continue
		var rect: Variant = room.get("rect", [])
		if rect is Array and rect.size() == 4 and pos.x >= int(rect[0]) and pos.x < int(rect[0]) + int(rect[2]) \
				and pos.y >= int(rect[1]) and pos.y < int(rect[1]) + int(rect[3]):
			return String(room_id)
	return ""

func _string_array(value: Variant) -> Array:
	var out: Array = []
	if value is Array:
		for item: Variant in value: out.append(String(item))
	return out

func _interior_object_ids(data: Dictionary) -> Dictionary:
	var ids := {}
	for space_value: Variant in data:
		var space := String(space_value)
		if space.begins_with("_") or not data[space] is Dictionary: continue
		for floor_value: Variant in data[space]:
			var floor := String(floor_value)
			var floor_data: Variant = data[space][floor]
			if not floor_data is Dictionary: continue
			var furniture_list: Variant = floor_data.get("furniture", [])
			if not furniture_list is Array: continue
			var used := {}
			for furniture_value: Variant in furniture_list:
				if not furniture_value is Dictionary: continue
				var advertisements: Variant = furniture_value.get("advertises", [])
				if not advertisements is Array or advertisements.is_empty(): continue
				var furniture: Dictionary = furniture_value
				var position: Variant = furniture.get("pos", [0, 0])
				if not position is Array or position.size() < 2: continue
				var slot := String(furniture.get("slot", "obj"))
				var object_id := "%s%s_%s" % [space, floor, slot]
				if used.has(object_id):
					used[object_id] = int(used[object_id]) + 1
					object_id += "_%d" % int(used[object_id])
				else:
					used[object_id] = 0
				ids[object_id] = true
	return ids

func _failure(code: String) -> Dictionary:
	return {"ok": false, "errors": [code]}
