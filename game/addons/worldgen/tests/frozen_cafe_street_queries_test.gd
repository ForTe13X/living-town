extends SceneTree
## Native read-only parity against the current Sim build. No package is activated.

const SIM := preload("res://scripts/Sim.gd")
const INVARIANTS := preload("res://bench/Invariants.gd")
const QUERY := preload("res://addons/worldgen/consumers/ai_town_adapter/frozen_cafe_street_queries.gd")
const CANONICAL := preload("res://addons/worldgen/core/worldgen_canonical.gd")
const WORLDGEN_VALIDATOR := preload("res://addons/worldgen/core/worldgen_package_validator.gd")
const FIXTURE := "res://addons/worldgen/consumers/ai_town_adapter/fixtures/lt22_cafe_street.world.json"
const BINDINGS := "res://addons/worldgen/consumers/ai_town_adapter/fixtures/host_action_bindings.json"

var errors: Array[String] = []
var checked_cells := 0

func _require(ok: bool, label: String) -> void:
	if not ok: errors.append(label)

func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _cell(point_q: Array) -> Vector2i:
	return Vector2i(int(point_q[0]) / 48, int(point_q[1]) / 48)

func _expect_rejected(candidate: Dictionary, label: String) -> void:
	var query := QUERY.new()
	var result: Dictionary = query.configure(candidate)
	_require(not result.get("ok", false) and not query.valid, label)
	_require(not query.walkable("cafe", "1f", Vector2i(3, 3)) and query.slot_by_id("cafe.dining_table").is_empty(),
		label + " failed closed")

func _same_unique_ids(expected: Array, actual: Array) -> bool:
	if expected.size() != actual.size(): return false
	var expected_set := {}
	var actual_set := {}
	for id: Variant in expected:
		if typeof(id) != TYPE_STRING or String(id).is_empty() or expected_set.has(id): return false
		expected_set[id] = true
	for id: Variant in actual:
		if typeof(id) != TYPE_STRING or String(id).is_empty() or actual_set.has(id): return false
		actual_set[id] = true
	return expected_set == actual_set

## Compare the complete authored and compiled café sets, including IDs absent
## from the frozen package. This is an observation gate, not an activation path.
func _cafe_sets_match(topology: Dictionary, spaces: Dictionary, interiors: Dictionary,
		nav_grids: Dictionary, portals: Array) -> bool:
	var expected_floors := []
	for plane: Dictionary in topology.get("planes", []):
		if plane.get("space") == "cafe": expected_floors.append(plane.get("floor"))
	var cafe_space: Variant = spaces.get("cafe")
	var cafe_interior: Variant = interiors.get("cafe")
	var cafe_grids: Variant = nav_grids.get("cafe")
	if not cafe_space is Dictionary or not cafe_interior is Dictionary or not cafe_grids is Dictionary:
		return false
	var source_floors: Variant = cafe_space.get("floors")
	if not source_floors is Array or not _same_unique_ids(expected_floors, source_floors) \
			or not _same_unique_ids(expected_floors, cafe_interior.keys()) \
			or not _same_unique_ids(expected_floors, cafe_grids.keys()): return false
	var expected_portals := []
	for portal: Dictionary in topology.get("portals", []):
		expected_portals.append(portal.get("source_id"))
	var actual_portals := []
	for raw: Variant in portals:
		if not raw is Dictionary: return false
		var portal: Dictionary = raw
		var from: Variant = portal.get("from")
		var to: Variant = portal.get("to")
		if not from is Dictionary or not to is Dictionary: return false
		if from.get("space") == "cafe" or to.get("space") == "cafe":
			actual_portals.append(portal.get("id"))
	return _same_unique_ids(expected_portals, actual_portals)

func _initialize() -> void:
	var sim = SIM.new()
	get_root().add_child(sim)
	sim._load_data()
	sim.auto_run = false
	sim.backend = null
	sim.start_new(1)
	var state_before := str(INVARIANTS.digest(sim))
	var events_before := str(sim.event_digest)
	var before := "user://lt22_frozen_query_before.save"
	var after := "user://lt22_frozen_query_after.save"
	_require(sim.save_game(before), "save before")
	var package := _read_json(FIXTURE)
	_require(not bool(WORLDGEN_VALIDATOR.validate(package).get("ok", false)),
		"separate worldgen runtime contract does not accept local LT-22 envelope")
	var bindings := _read_json(BINDINGS)
	var query := QUERY.new()
	_require(bool(query.configure(package).get("ok", false)), "frozen reference accepted: " + query.error)
	if query.valid:
		var topology: Dictionary = package["payload"]["topology"]
		var source_spaces := _read_json("res://data/spaces.json")
		var source_interiors := _read_json("res://data/interiors.json")
		_require(_cafe_sets_match(topology, source_spaces.get("spaces", {}), source_interiors,
			sim._nav_grids, source_spaces.get("portals", [])), "complete authored cafe floor and portal sets")
		_require(_cafe_sets_match(topology, sim._authored_spaces, sim._authored_interiors_data,
			sim._nav_grids, sim._authored_portals), "complete receiver cafe floor and portal sets")
		var added_floor: Dictionary = source_spaces.duplicate(true)
		added_floor["spaces"]["cafe"]["floors"].append("3f")
		_require(not _cafe_sets_match(topology, added_floor["spaces"], source_interiors,
			sim._nav_grids, source_spaces["portals"]), "added authored cafe floor rejected")
		var added_interior: Dictionary = source_interiors.duplicate(true)
		added_interior["cafe"]["3f"] = {"floor": "wood", "furniture": []}
		_require(not _cafe_sets_match(topology, source_spaces["spaces"], added_interior,
			sim._nav_grids, source_spaces["portals"]), "added cafe interior floor rejected")
		var added_portal: Dictionary = source_spaces.duplicate(true)
		var extra: Dictionary = added_portal["portals"][0].duplicate(true)
		extra["id"] = "p_cafe_extra"
		extra["to"]["space"] = "cafe"
		added_portal["portals"].append(extra)
		_require(not _cafe_sets_match(topology, added_portal["spaces"], source_interiors,
			sim._nav_grids, added_portal["portals"]), "added authored cafe portal rejected")
		for plane: Dictionary in topology["planes"]:
			var bounds: Array = plane["bounds_q"]
			var origin := _cell(bounds.slice(0, 2))
			var size := _cell(bounds.slice(2, 4))
			var grid: Dictionary = sim._nav_grids[plane["space"]][plane["floor"]]
			for y in range(origin.y, origin.y + size.y):
				for x in range(origin.x, origin.x + size.x):
					var at := Vector2i(x, y)
					_require(query.walkable(plane["space"], plane["floor"], at) == sim._cell_walkable(grid, at),
						"walkability %s/%s/%s" % [plane["space"], plane["floor"], str(at)])
					checked_cells += 1
			_require(not query.walkable(plane["space"], plane["floor"], origin - Vector2i.ONE), "clip bounds")
		var seen_affordances := {}
		var expected_object_ids := {}
		for slot: Dictionary in topology["slots"]:
			var source_id := String(slot["source_id"])
			expected_object_ids[source_id] = true
			var native: Dictionary = sim.world.objects.get(source_id, {})
			_require(not native.is_empty() and native.get("pos") == _cell(slot["position_q"]), "native slot " + source_id)
			_require(native.get("space") == slot.get("space") and native.get("floor") == slot.get("floor")
				and native.get("home_space", native.get("space")) == slot.get("home_space")
				and bool(native.get("staff", false)) == bool(slot.get("staff_only", false)), "native slot policy " + source_id)
			_require(query.slot_by_source_id(source_id) == slot and query.slot_by_id(slot["id"]) == slot,
				"bidirectional slot identity " + source_id)
			var detached: Dictionary = query.slot_by_id(slot["id"])
			detached["id"] = "mutated_copy"
			_require(query.slot_by_id(slot["id"]) == slot, "slot query returns a copy")
			var remaining_ads: Array = native.get("advertises", []).duplicate(true)
			for affordance: Dictionary in query.affordances_for(slot["id"]):
				var aid := String(affordance["id"])
				_require(query.affordance_by_id(aid) == affordance, "affordance identity " + aid)
				var binding: Dictionary = bindings.get(aid, {})
				_require(remaining_ads.has(binding), "host action parity " + aid)
				remaining_ads.erase(binding)
				_require(int(affordance.get("seats", -1)) == int(binding.get("seats", 0)), "host capacity parity " + aid)
				seen_affordances[aid] = true
			_require(remaining_ads.is_empty(), "no extra host action on " + source_id)
		var live_object_ids := {}
		var street_clip := Rect2i(37, 19, 9, 4)
		for object_id: Variant in sim.world.objects:
			var object: Dictionary = sim.world.objects[object_id]
			var object_space := String(object.get("space", "town"))
			if object_space == "cafe" or (object_space == "town" and street_clip.has_point(object.get("pos", Vector2i(-1, -1)))):
				live_object_ids[String(object_id)] = true
		_require(live_object_ids == expected_object_ids, "complete cafe and street object set")
		_require(seen_affordances.size() == 8, "eight mapped host affordances")
		for portal: Dictionary in topology["portals"]:
			var source_id := String(portal["source_id"])
			_require(query.portal_by_source_id(source_id) == portal and query.portal_by_id(portal["id"]) == portal,
				"bidirectional portal identity " + source_id)
			var native_portal: Dictionary = {}
			for candidate: Dictionary in sim._authored_portals:
				if candidate.get("id") == source_id: native_portal = candidate
			_require(not native_portal.is_empty(), "native portal exists " + source_id)
			for key: String in ["kind", "access", "bidirectional"]:
				_require(native_portal.get(key) == portal.get(key), "native portal " + source_id + "/" + key)
			_require(native_portal.get("owner_space", "") == portal.get("owner_space", "")
				and native_portal.get("staff_titles", []) == portal.get("staff_titles", [])
				and int(native_portal.get("traversal_cost", -1)) == int(portal.get("cost", -2)),
				"native portal policy and cost " + source_id)
			for side: String in ["from", "to"]:
				var endpoint: Dictionary = portal[side]
				var native_endpoint: Dictionary = native_portal.get(side, {})
				_require(native_endpoint.get("space") == endpoint.get("space")
					and native_endpoint.get("floor") == endpoint.get("floor")
					and Vector2i(int(native_endpoint.get("pos", [0, 0])[0]), int(native_endpoint.get("pos", [0, 0])[1])) == _cell(endpoint["position_q"]),
					"native portal endpoint " + source_id + "/" + side)
				_require(query.portals_from(endpoint["space"], endpoint["floor"]).any(
					func(p: Dictionary) -> bool: return p["id"] == portal["id"]), "portal endpoint " + source_id + "/" + side)
				var other_side := "to" if side == "from" else "from"
				var other: Dictionary = portal[other_side]
				var matched_hop := false
				for hop: Dictionary in sim._portals_from(endpoint["space"], endpoint["floor"]):
					if hop.get("portal_id") != source_id: continue
					matched_hop = hop.get("from_pos") == _cell(endpoint["position_q"]) \
						and hop.get("to_space") == other.get("space") and hop.get("to_floor") == other.get("floor") \
						and hop.get("to_pos") == _cell(other["position_q"]) \
						and int(hop.get("cost", -1)) == int(portal["cost"])
				_require(matched_hop, "native portal hop " + source_id + "/" + side)
		var stairs: Dictionary = query.portal_by_id("p_cafe_stairs")
		_require(stairs.get("access") == "owner" and stairs.get("owner_space") == "cafe", "private stairs metadata")
		var owner_portals := []
		var visitor_portals := []
		for item: Dictionary in sim._portals_from("cafe", "1f", {"id": "aria"}): owner_portals.append(item["portal_id"])
		for item: Dictionary in sim._portals_from("cafe", "1f", {"id": "ben"}): visitor_portals.append(item["portal_id"])
		_require("p_cafe_stairs" in owner_portals and "p_cafe_stairs" not in visitor_portals,
			"Sim retains owner policy")
		_require("p_cafe_door" in visitor_portals, "Sim retains public cafe door")
		var street: Dictionary = query.street_by_source_id("market_walk")
		var plan := _read_json("res://data/coastal_plan.json")
		var source: Dictionary = {}
		for candidate: Dictionary in plan.get("streets", []):
			if candidate.get("id") == "market_walk": source = candidate
		_require(street.get("id") == "market_walk/cafe_frontage" and street.get("portal_id") == "p_cafe_door",
			"street and door identity")
		var segment := int(street.get("segment_index", -1))
		if not source.is_empty() and segment >= 0 and segment + 1 < source["points"].size():
			for index in range(2):
				_require(_cell(street["path_q"][index]) == Vector2i(source["points"][segment + index][0],
					source["points"][segment + index][1]), "street path parity")
		var link_found := false
		for link: Dictionary in plan.get("links", []):
			var entrance: Array = link.get("entrance", [])
			if entrance.size() != 2 or int(entrance[0]) != 41 or int(entrance[1]) != 19: continue
			link_found = true
			_require(street["entrance_link_q"].size() == link["cells"].size(), "street entrance link length")
			for index in range(link["cells"].size()):
				_require(_cell(street["entrance_link_q"][index]) == Vector2i(link["cells"][index][0],
						link["cells"][index][1]), "street entrance link parity")
		_require(link_found, "authored cafe entrance link exists")
		street["id"] = "mutated_copy"
		_require(query.street_by_source_id("market_walk")["id"] == "market_walk/cafe_frontage", "street query returns a copy")
		_require(query.semantic_fingerprint() == package["payload"]["compatibility"]["topology_sha256"], "semantic fingerprint")
		var alternate: Dictionary = package.duplicate(true)
		var alt_presentation := {"profile": "alternate", "pixels_per_cell": 96}
		alt_presentation["digest_sha256"] = CANONICAL.sha256(alt_presentation)
		alternate["payload"]["presentation"] = alt_presentation
		var alt_query := QUERY.new()
		_require(bool(alt_query.configure(alternate).get("ok", false)), "presentation-only accepted")
		_require(alt_query.semantic_fingerprint() == query.semantic_fingerprint() \
				and alt_query.presentation_fingerprint() != query.presentation_fingerprint(), "separate fingerprints")
	var renamed: Dictionary = package.duplicate(true)
	renamed["payload"]["topology"]["portals"][0]["id"] = "renamed_occupied_portal"
	renamed["payload"]["compatibility"]["topology_sha256"] = CANONICAL.sha256(renamed["payload"]["topology"])
	_expect_rejected(renamed, "occupied portal rename")
	var removed: Dictionary = package.duplicate(true)
	removed["payload"]["topology"]["affordances"].pop_back()
	removed["payload"]["compatibility"]["topology_sha256"] = CANONICAL.sha256(removed["payload"]["topology"])
	_expect_rejected(removed, "affordance removal")
	var units: Dictionary = package.duplicate(true)
	units["coordinate_frame"]["q_per_cell"] = 32
	_expect_rejected(units, "unit mismatch")
	var street_drift: Dictionary = package.duplicate(true)
	street_drift["payload"]["topology"]["streets"][0]["path_q"][0][0] += 48
	_expect_rejected(street_drift, "street path mutation")
	var version_spoof: Dictionary = package.duplicate(true)
	version_spoof["schema_version"] = "1"
	_expect_rejected(version_spoof, "string version")
	var fractional: Dictionary = package.duplicate(true)
	fractional["payload"]["presentation"]["pixels_per_cell"] = 96.5
	_expect_rejected(fractional, "fractional presentation scale")
	var fractional_units: Dictionary = package.duplicate(true)
	fractional_units["coordinate_frame"]["q_per_cell"] = 48.5
	_expect_rejected(fractional_units, "fractional coordinate unit")
	var unknown: Dictionary = package.duplicate(true)
	unknown["extra"] = true
	_expect_rejected(unknown, "unknown envelope field")
	_require(str(INVARIANTS.digest(sim)) == state_before and str(sim.event_digest) == events_before,
		"state and event digest unchanged")
	_require(sim.save_game(after), "save after")
	var same_save := FileAccess.get_sha256(before) == FileAccess.get_sha256(after)
	_require(same_save, "save bytes unchanged")
	print("LT22_FROZEN_QUERY " + JSON.stringify({"errors": errors, "cells": checked_cells,
		"slots": 6, "portals": 2, "affordances": 8, "streets": 1,
		"hostile_cases": 8, "stale_source_cases": 3, "save_bytes_identical": same_save,
		"external_v5_qualified": false, "runtime_activation": false}))
	sim.free()
	quit(0 if errors.is_empty() else 1)
