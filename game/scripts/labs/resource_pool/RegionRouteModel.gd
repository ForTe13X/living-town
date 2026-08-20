extends RefCounted

## RP-0003: owner-independent region atlas, route plan, journey, and discovery
## contracts. All authority is JSON-safe data. ScaleAddress names places; this
## file owns an authored multi-region window and integer, one-leg settlement.
## It never loads or mutates Sim, Main, WorldView, or MapTileLabModel.

const ScaleAddress = preload("res://scripts/labs/resource_pool/ScaleAddress.gd")

const ATLAS_SCHEMA := "living-town.region-atlas/v1"
const ATLAS_STATE_SCHEMA := "living-town.region-atlas-state/v1"
const PLAN_SCHEMA := "living-town.region-route-plan/v1"
const OFFER_BOARD_SCHEMA := "living-town.region-route-board/v1"
const JOURNEY_SCHEMA := "living-town.region-journey-state/v1"
const LEG_SCHEMA := "living-town.region-leg-receipt/v1"
const TRANSITION_SCHEMA := "living-town.region-leg-transition/v1"
const DIVERSION_SCHEMA := "living-town.region-diversion-transition/v1"
const RECEIPT_SCHEMA := "living-town.region-route-receipt/v1"

const NETWORK_REVISION := "ashfall-south-window-v1"
const COST_PROFILE := "region-travel-integer-v1"
const DEFAULT_ROOT_SEED := 260814
const PLAN_ID_PREFIX := "rrp1:"
const JOURNEY_ID_PREFIX := "rrj1:"

const PLANET_ID := "ashfall"
const FACE := 0
const Q_MIN := 0
const Q_MAX := 15
const R_MIN := -4
const R_MAX := 7
const SAFE_RESERVE_MILLI := 2000
const FALLBACK_RESERVE_MILLI := 500
const MAX_ROUTE_KEY_WITH_FALLBACK := 55
const MAX_RESOURCE_MILLI := 1000000
const MAX_SAFE_JSON_INT := 9007199254740991

const SEASONS := ["spring", "autumn", "winter"]
const POLICIES := ["fast", "safe", "frugal"]
const PHASES := ["traveling", "arrived", "stranded"]

const ASH_MARKET := Vector2i(7, -1)
const CINDER_CROSSING := Vector2i(2, 3)
const ORRA_RELAY := Vector2i(5, -1)
const RIDGE_PASS := Vector2i(5, 0)
const REDGLASS_QUARRY := Vector2i(9, 0)
const SAINT_VEY_CLINIC := Vector2i(5, 3)
const DUNLIN_HOMESTEAD := Vector2i(1, 1)
const DUNLIN_BEND := Vector2i(0, 4)

const SITE_SPECS := [
	{"coord": [7, -1], "key": "ash_market", "label": "ASH MARKET", "kind": "ruins", "safe_stop": false},
	{"coord": [2, 3], "key": "cinder_crossing", "label": "CINDER CROSSING", "kind": "haven", "safe_stop": true},
	{"coord": [5, -1], "key": "orra_relay", "label": "ORRA RELAY", "kind": "relay", "safe_stop": true},
	{"coord": [9, 0], "key": "redglass_quarry", "label": "REDGLASS QUARRY", "kind": "quarry", "safe_stop": false},
	{"coord": [5, 3], "key": "saint_vey_clinic", "label": "SAINT VEY CLINIC", "kind": "clinic", "safe_stop": true},
	{"coord": [1, 1], "key": "dunlin_homestead", "label": "DUNLIN HOMESTEAD", "kind": "farm", "safe_stop": true},
]

const ROUTE_SPECS := [
	{
		"route_key": "orra_ridge_cut", "label": "ORRA RIDGE CUT", "policy": "fast",
		"waypoints": [[5, 0]], "fallback": [5, -1],
		"promise": "Fastest line; the ridge closes in winter.",
	},
	{
		"route_key": "old_market_road", "label": "OLD MARKET ROAD", "policy": "safe",
		"waypoints": [[9, 0], [5, 3]], "fallback": [5, 3],
		"promise": "Long road miles trade time for lower exposure.",
	},
	{
		"route_key": "dunlin_supply_arc", "label": "DUNLIN SUPPLY ARC", "policy": "frugal",
		"waypoints": [[1, 1], [0, 4]], "fallback": [1, 1],
		"promise": "Longest arc; tracks preserve the largest arrival reserve.",
	},
]

const TERRAIN_COST := {
	"steppe": {"minutes": 170, "supply_milli": 1050, "condition_milli": 420},
	"pine": {"minutes": 185, "supply_milli": 1100, "condition_milli": 500},
	"scrub": {"minutes": 195, "supply_milli": 1150, "condition_milli": 620},
	"marsh": {"minutes": 230, "supply_milli": 1350, "condition_milli": 900},
	"highland": {"minutes": 210, "supply_milli": 1250, "condition_milli": 1100},
	"ash": {"minutes": 200, "supply_milli": 1200, "condition_milli": 760},
}

const AXIAL_DIRS := [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


static func make_atlas(root_seed: int = DEFAULT_ROOT_SEED) -> Dictionary:
	var corridor_edges := _authored_corridor_edges()
	var corridor_tiles := _corridor_tiles(corridor_edges)
	var tiles: Array[Dictionary] = []
	var region_seen := {}
	for r in range(R_MIN, R_MAX + 1):
		for q in range(Q_MIN, Q_MAX + 1):
			var coord := Vector2i(q, r)
			var address: Dictionary = ScaleAddress.tile_address(PLANET_ID, FACE, coord)
			var tile_id := ScaleAddress.canonical_id(address)
			var region_id := ScaleAddress.canonical_id(ScaleAddress.parent(address))
			region_seen[region_id] = true
			var seed_value := ScaleAddress.seed_for(root_seed, address, "region-terrain")
			var terrain := _terrain_at(coord, seed_value)
			var site := _site_at(coord)
			var base_risk := _terrain_risk(terrain) + int(seed_value % 3)
			if not site.is_empty() and bool(site["safe_stop"]):
				base_risk = maxi(1, base_risk - 2)
			var site_id := ""
			var site_key := ""
			var label := ""
			var site_kind := ""
			var safe_stop := false
			if not site.is_empty():
				site_key = String(site["key"])
				label = String(site["label"])
				site_kind = String(site["kind"])
				safe_stop = bool(site["safe_stop"])
				site_id = ScaleAddress.canonical_id(ScaleAddress.with_site(address, site_key))
			tiles.append({
				"id": tile_id,
				"q": q,
				"r": r,
				"terrain": terrain,
				"risk": clampi(base_risk, 1, 8),
				"forage": 1 + int(seed_value % 4),
				"corridor": String(corridor_tiles.get(_coord_key(coord), "none")),
				"site_id": site_id,
				"site_key": site_key,
				"site_kind": site_kind,
				"safe_stop": safe_stop,
				"label": label,
			})

	var tile_by_coord := {}
	for tile in tiles:
		tile_by_coord[Vector2i(int(tile["q"]), int(tile["r"]))] = tile
	var edges: Array[Dictionary] = []
	for tile in tiles:
		var coord := Vector2i(int(tile["q"]), int(tile["r"]))
		var a := String(tile["id"])
		for delta in AXIAL_DIRS:
			var neighbor_coord: Vector2i = coord + delta
			if not tile_by_coord.has(neighbor_coord):
				continue
			var neighbor: Dictionary = tile_by_coord[neighbor_coord]
			var b := String(neighbor["id"])
			if a >= b:
				continue
			var pair := _pair_key(a, b)
			var corridor := String(corridor_edges.get(pair, "none"))
			var road_class := "none"
			if corridor == "market":
				road_class = "road"
			elif corridor in ["ridge", "dunlin"]:
				road_class = "track"
			edges.append({
				"id": "rge1:" + _sha256_hex(_canonical_json([a, b, road_class, corridor])).substr(0, 16),
				"a": a,
				"b": b,
				"road_class": road_class,
				"corridor": corridor,
				"blocked": false,
			})
	edges.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return String(left["id"]) < String(right["id"]))
	var region_ids: Array[String] = []
	for raw_region_id in region_seen:
		region_ids.append(String(raw_region_id))
	region_ids.sort()
	var region_receipts: Array[Dictionary] = []
	for region_id in region_ids:
		region_receipts.append(ScaleAddress.receipt(root_seed, ScaleAddress.parse_id(region_id), "region-atlas"))

	var authority := {
		"schema": ATLAS_SCHEMA,
		"scope": "window",
		"network_revision": NETWORK_REVISION,
		"cost_profile": COST_PROFILE,
		"root_seed": "i64:%d" % root_seed,
		"window": {"q_min": Q_MIN, "q_max": Q_MAX, "r_min": R_MIN, "r_max": R_MAX},
		"region_ids": region_ids,
		"region_seed_receipts": region_receipts,
		"tiles": _atlas_authority_tiles(tiles),
		"edges": edges,
	}
	var digest := _sha256_hex(_canonical_json(authority))
	if digest == "":
		return {}
	return {
		"schema": ATLAS_SCHEMA,
		"scope": "window",
		"atlas_id": "rga1:" + digest.substr(0, 16),
		"network_revision": NETWORK_REVISION,
		"cost_profile": COST_PROFILE,
		"root_seed": "i64:%d" % root_seed,
		"window": {"q_min": Q_MIN, "q_max": Q_MAX, "r_min": R_MIN, "r_max": R_MAX},
		"region_ids": region_ids,
		"region_seed_receipts": region_receipts,
		"tiles": tiles,
		"edges": edges,
		"atlas_receipt": "sha256:" + digest,
	}


static func validate_atlas(value: Variant) -> Array[String]:
	if not (value is Dictionary):
		return ["atlas must be a Dictionary"]
	var data: Dictionary = value
	var required := ["schema", "scope", "atlas_id", "network_revision", "cost_profile", "root_seed",
		"window", "region_ids", "region_seed_receipts", "tiles", "edges", "atlas_receipt"]
	if not _exact_keys(data, required):
		return ["atlas fields must match V1 exactly"]
	var root_seed := _root_seed_from_token(_string_if(data.get("root_seed")))
	if root_seed.is_empty():
		return ["atlas root_seed must be canonical i64"]
	var expected := make_atlas(int(root_seed[0]))
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(data):
		return ["atlas does not match its deterministic window contract"]
	return []


static func normalize_atlas(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var root_seed := _root_seed_from_token(_string_if((value as Dictionary).get("root_seed")))
	if root_seed.is_empty():
		return {}
	var expected := make_atlas(int(root_seed[0]))
	return expected if _canonical_json(expected) == _canonical_json(value) else {}


static func make_initial_atlas_state(atlas: Dictionary) -> Dictionary:
	var normalized := normalize_atlas(atlas)
	if normalized.is_empty():
		return {}
	var discovered: Array[String] = []
	for tile in normalized["tiles"]:
		var coord := Vector2i(int(tile["q"]), int(tile["r"]))
		if axial_distance(coord, ASH_MARKET) <= 2:
			discovered.append(String(tile["id"]))
	return _make_atlas_state_normalized(normalized, discovered, [])


static func make_atlas_state(atlas: Dictionary, discovered_ids: Array, road_deltas: Array) -> Dictionary:
	var normalized := normalize_atlas(atlas)
	if normalized.is_empty():
		return {}
	return _make_atlas_state_normalized(normalized, discovered_ids, road_deltas)


static func _make_atlas_state_normalized(normalized: Dictionary, discovered_ids: Array,
		road_deltas: Array) -> Dictionary:
	var tile_ids := _tile_id_set(normalized)
	var discovered: Array[String] = []
	var discovered_seen := {}
	for raw_id in discovered_ids:
		if typeof(raw_id) != TYPE_STRING or not tile_ids.has(String(raw_id)) or discovered_seen.has(String(raw_id)):
			return {}
		discovered_seen[String(raw_id)] = true
		discovered.append(String(raw_id))
	discovered.sort()
	var edge_ids := _edge_id_set(normalized)
	var deltas: Array[Dictionary] = []
	var delta_seen := {}
	for raw_delta in road_deltas:
		if not (raw_delta is Dictionary):
			return {}
		var delta: Dictionary = raw_delta
		if not _exact_keys(delta, ["edge_id", "state"]) or typeof(delta.get("edge_id")) != TYPE_STRING \
				or typeof(delta.get("state")) != TYPE_STRING:
			return {}
		var edge_id := String(delta["edge_id"])
		var state := String(delta["state"])
		# Every V1 authored edge is open. Recording an explicit "open" override would
		# fork road_revision without changing the graph, so no-op deltas fail closed.
		if not edge_ids.has(edge_id) or state != "closed" or delta_seen.has(edge_id):
			return {}
		delta_seen[edge_id] = true
		deltas.append({"edge_id": edge_id, "state": state})
	deltas.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return String(left["edge_id"]) < String(right["edge_id"]))
	var road_revision := "sha256:" + _sha256_hex(_canonical_json(deltas))
	var base := {
		"schema": ATLAS_STATE_SCHEMA,
		"atlas_id": String(normalized["atlas_id"]),
		"network_revision": String(normalized["network_revision"]),
		"road_revision": road_revision,
		"discovered_tile_ids": discovered,
		"road_deltas": deltas,
	}
	base["state_receipt"] = _receipt_for(base)
	if String(base["state_receipt"]) == "":
		return {}
	return base


static func validate_atlas_state(atlas: Dictionary, value: Variant) -> Array[String]:
	if not (value is Dictionary):
		return ["atlas state must be a Dictionary"]
	var data: Dictionary = value
	var required := ["schema", "atlas_id", "network_revision", "road_revision",
		"discovered_tile_ids", "road_deltas", "state_receipt"]
	if not _exact_keys(data, required) or not (data.get("discovered_tile_ids") is Array) \
			or not (data.get("road_deltas") is Array):
		return ["atlas state fields must match V1 exactly"]
	var expected := make_atlas_state(atlas, data["discovered_tile_ids"], data["road_deltas"])
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(data):
		return ["atlas state receipt or typed deltas do not match"]
	return []


static func normalize_atlas_state(atlas: Dictionary, value: Variant) -> Dictionary:
	var normalized_atlas := normalize_atlas(atlas)
	if normalized_atlas.is_empty():
		return {}
	return _normalize_atlas_state_normalized(normalized_atlas, value)


static func _normalize_atlas_state_normalized(normalized_atlas: Dictionary,
		value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var data: Dictionary = value
	if not (data.get("discovered_tile_ids") is Array) or not (data.get("road_deltas") is Array):
		return {}
	var expected := _make_atlas_state_normalized(normalized_atlas,
		data["discovered_tile_ids"], data["road_deltas"])
	return expected if _canonical_json(expected) == _canonical_json(data) else {}


static func tile_id(atlas: Dictionary, coord: Vector2i) -> String:
	var normalized := normalize_atlas(atlas)
	if normalized.is_empty() or not _in_window(coord):
		return ""
	return _tile_id_for_coord(coord)


static func site_tile_id(atlas: Dictionary, site_key: String) -> String:
	var normalized := normalize_atlas(atlas)
	if normalized.is_empty():
		return ""
	for tile in normalized["tiles"]:
		if String(tile["site_key"]) == site_key:
			return String(tile["id"])
	return ""


static func axial_neighbors(atlas: Dictionary, source_id: String) -> Array[String]:
	var normalized := normalize_atlas(atlas)
	var result: Array[String] = []
	if normalized.is_empty():
		return result
	var coord := _coord_for_id(normalized, source_id)
	if coord == Vector2i(999999, 999999):
		return result
	for delta in AXIAL_DIRS:
		var neighbor: Vector2i = coord + delta
		if _in_window(neighbor):
			result.append(_tile_id_for_coord(neighbor))
	result.sort()
	return result


static func axial_distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


static func make_route_plan(atlas: Dictionary, atlas_state: Dictionary, start_id: String,
		destination_id: String, season: String, policy: String, waypoints: Array,
		fallback_id: String, route_key: String) -> Dictionary:
	var normalized_atlas := normalize_atlas(atlas)
	var normalized_state := {} if normalized_atlas.is_empty() \
		else _normalize_atlas_state_normalized(normalized_atlas, atlas_state)
	return _make_route_plan_normalized(normalized_atlas, normalized_state, start_id,
		destination_id, season, policy, waypoints, fallback_id, route_key)


static func _make_route_plan_normalized(normalized_atlas: Dictionary,
		normalized_state: Dictionary, start_id: String, destination_id: String, season: String,
		policy: String, waypoints: Array, fallback_id: String, route_key: String) -> Dictionary:
	if normalized_atlas.is_empty() or normalized_state.is_empty() or season not in SEASONS \
			or policy not in POLICIES or not _slug_valid(route_key) \
			or not _tile_id_set(normalized_atlas).has(start_id) \
			or not _tile_id_set(normalized_atlas).has(destination_id):
		return {}
	if fallback_id != "" and not _tile_id_set(normalized_atlas).has(fallback_id):
		return {}
	if fallback_id != "" and route_key.length() > MAX_ROUTE_KEY_WITH_FALLBACK:
		return {}
	var waypoint_ids: Array[String] = []
	for raw_waypoint in waypoints:
		if typeof(raw_waypoint) != TYPE_STRING or not _tile_id_set(normalized_atlas).has(String(raw_waypoint)):
			return {}
		waypoint_ids.append(String(raw_waypoint))
	var stops: Array[String] = [start_id]
	stops.append_array(waypoint_ids)
	stops.append(destination_id)
	var path: Array[String] = []
	var available := true
	for i in range(stops.size() - 1):
		var segment := _dijkstra(normalized_atlas, normalized_state, stops[i], stops[i + 1], season, policy)
		if segment.is_empty():
			available = false
			path.clear()
			break
		if path.is_empty():
			path.append_array(segment)
		else:
			for j in range(1, segment.size()):
				path.append(String(segment[j]))
	var leg_ids: Array[String] = []
	var totals := _empty_totals()
	if available:
		var path_metrics := _path_metrics(normalized_atlas, normalized_state, path, season)
		if path_metrics.is_empty():
			available = false
			path.clear()
		else:
			totals = path_metrics["totals"]
			leg_ids = path_metrics["leg_ids"]
	var block_reason := ""
	if not available:
		block_reason = "season_closed" if season == "winter" and route_key == "orra_ridge_cut" else "unreachable"
	var authority := {
		"schema": PLAN_SCHEMA,
		"atlas_id": String(normalized_atlas["atlas_id"]),
		"network_revision": String(normalized_atlas["network_revision"]),
		"road_revision": String(normalized_state["road_revision"]),
		"cost_profile": COST_PROFILE,
		"season": season,
		"policy": policy,
		"route_key": route_key,
		"origin": start_id,
		"destination": destination_id,
		"fallback": fallback_id,
		"waypoints": waypoint_ids,
		"path": path,
		"leg_ids": leg_ids,
		"totals": totals,
		"available": available,
		"block_reason": block_reason,
	}
	var digest := _sha256_hex(_canonical_json(authority))
	if digest == "":
		return {}
	var result := authority.duplicate(true)
	result["plan_id"] = PLAN_ID_PREFIX + digest.substr(0, 16)
	result["plan_receipt"] = "sha256:" + digest
	return _ordered_plan(result)


static func validate_plan(atlas: Dictionary, atlas_state: Dictionary, value: Variant) -> Array[String]:
	var normalized_atlas := normalize_atlas(atlas)
	var normalized_state := {} if normalized_atlas.is_empty() \
		else _normalize_atlas_state_normalized(normalized_atlas, atlas_state)
	if not _plan_matches_normalized(normalized_atlas, normalized_state, value):
		return ["route plan does not recompute from atlas + state"]
	return []


static func _plan_matches_normalized(normalized_atlas: Dictionary, normalized_state: Dictionary,
		value: Variant) -> bool:
	if normalized_atlas.is_empty() or normalized_state.is_empty() or not (value is Dictionary):
		return false
	var data: Dictionary = value
	var required := ["schema", "plan_id", "atlas_id", "network_revision", "road_revision",
		"cost_profile", "season", "policy", "route_key", "origin", "destination", "fallback",
		"waypoints", "path", "leg_ids", "totals", "available", "block_reason", "plan_receipt"]
	if not _exact_keys(data, required) or not (data.get("waypoints") is Array) \
			or not (data.get("path") is Array) or not (data.get("leg_ids") is Array) \
			or not (data.get("totals") is Dictionary) or typeof(data.get("available")) != TYPE_BOOL:
		return false
	for key in ["season", "policy", "route_key", "origin", "destination", "fallback"]:
		if typeof(data.get(key)) != TYPE_STRING:
			return false
	var expected := _make_route_plan_normalized(normalized_atlas, normalized_state, String(data["origin"]),
		String(data["destination"]), String(data["season"]), String(data["policy"]),
		data["waypoints"], String(data["fallback"]), String(data["route_key"]))
	return not expected.is_empty() and _canonical_json(expected) == _canonical_json(data)


static func route_board(atlas: Dictionary, atlas_state: Dictionary, start_id: String,
		destination_id: String, season: String, supplies_milli: int,
		condition_milli: int) -> Dictionary:
	var normalized_atlas := normalize_atlas(atlas)
	var normalized_state := {} if normalized_atlas.is_empty() \
		else _normalize_atlas_state_normalized(normalized_atlas, atlas_state)
	if normalized_atlas.is_empty() or normalized_state.is_empty() or season not in SEASONS \
			or not _bounded_int(supplies_milli, 0, MAX_RESOURCE_MILLI) \
			or not _bounded_int(condition_milli, 0, MAX_RESOURCE_MILLI):
		return {}
	var offers: Array[Dictionary] = []
	for spec in ROUTE_SPECS:
		var waypoint_ids: Array[String] = []
		for raw_coord in spec["waypoints"]:
			waypoint_ids.append(_tile_id_for_coord(
				Vector2i(int((raw_coord as Array)[0]), int((raw_coord as Array)[1]))))
		var fallback_coord: Array = spec["fallback"]
		var fallback_id := _tile_id_for_coord(Vector2i(int(fallback_coord[0]), int(fallback_coord[1])))
		var plan := _make_route_plan_normalized(normalized_atlas, normalized_state, start_id, destination_id,
			season, String(spec["policy"]), waypoint_ids, fallback_id, String(spec["route_key"]))
		var projection := _project_plan(plan, supplies_milli, condition_milli)
		offers.append({
			"route_key": String(spec["route_key"]),
			"label": String(spec["label"]),
			"promise": String(spec["promise"]),
			"plan": plan,
			"projection": projection,
			"advantages": [],
		})
	_annotate_advantages(offers)
	var has_safe := false
	for offer in offers:
		has_safe = has_safe or String((offer["projection"] as Dictionary)["status"]) == "safe"
	var fallback_offer := {}
	if not has_safe:
		fallback_offer = _best_fallback(normalized_atlas, normalized_state, offers,
			start_id, season, supplies_milli, condition_milli)
	var decision_status := "routes_available" if has_safe else ("fallback_only" if not fallback_offer.is_empty() else "no_plan")
	return {
		"schema": OFFER_BOARD_SCHEMA,
		"atlas_id": String(normalized_atlas["atlas_id"]),
		"atlas_state_receipt": String(normalized_state["state_receipt"]),
		"season": season,
		"origin": start_id,
		"destination": destination_id,
		"supplies_milli": supplies_milli,
		"condition_milli": condition_milli,
		"safe_reserve_milli": SAFE_RESERVE_MILLI,
		"decision_status": decision_status,
		"offers": offers,
		"fallback_offer": fallback_offer,
	}


static func begin_journey(atlas: Dictionary, atlas_state: Dictionary, plan: Dictionary,
		journey_slot: String, supplies_milli: int, condition_milli: int) -> Dictionary:
	if not validate_plan(atlas, atlas_state, plan).is_empty() or not bool(plan.get("available", false)) \
			or not _slug_valid(journey_slot) or not _bounded_int(supplies_milli, 0, MAX_RESOURCE_MILLI) \
			or not _bounded_int(condition_milli, 0, MAX_RESOURCE_MILLI):
		return {}
	var path: Array = plan["path"]
	if path.is_empty():
		return {}
	var material := _canonical_json([String(plan["plan_id"]), journey_slot,
		supplies_milli, condition_milli])
	var journey_id := JOURNEY_ID_PREFIX + _sha256_hex(material).substr(0, 16)
	var base := {
		"schema": JOURNEY_SCHEMA,
		"journey_id": journey_id,
		"journey_slot": journey_slot,
		"active_plan_id": String(plan["plan_id"]),
		"phase": "arrived" if path.size() == 1 else "traveling",
		"leg_index": 0,
		"current_tile": String(plan["origin"]),
		"initial_supply_milli": supplies_milli,
		"supplies_milli": supplies_milli,
		"spent_supply_milli": 0,
		"initial_condition_milli": condition_milli,
		"condition_milli": condition_milli,
		"condition_loss_milli": 0,
		"elapsed_minutes": 0,
		"committed_leg_ids": [],
		"segment_plan_ids": [String(plan["plan_id"])],
		"segment_start_leg_count": 0,
		"segment_start_elapsed_minutes": 0,
		"segment_start_spent_supply_milli": 0,
		"segment_start_condition_loss_milli": 0,
		"previous_leg_receipt": "",
	}
	base["state_receipt"] = _receipt_for(base)
	if String(base["state_receipt"]) == "":
		return {}
	return base


static func validate_journey(atlas: Dictionary, atlas_state: Dictionary, plan: Dictionary,
		value: Variant) -> Array[String]:
	var normalized_atlas := normalize_atlas(atlas)
	var normalized_state := {} if normalized_atlas.is_empty() \
		else _normalize_atlas_state_normalized(normalized_atlas, atlas_state)
	return _validate_journey_normalized(normalized_atlas, normalized_state, plan, value)


static func _validate_journey_normalized(normalized_atlas: Dictionary,
		normalized_state: Dictionary, plan: Dictionary, value: Variant) -> Array[String]:
	if not _plan_matches_normalized(normalized_atlas, normalized_state, plan) \
			or not bool(plan.get("available", false)):
		return ["journey requires a valid available plan"]
	if not (value is Dictionary):
		return ["journey must be a Dictionary"]
	var data: Dictionary = value
	var required := ["schema", "journey_id", "journey_slot", "active_plan_id", "phase", "leg_index",
		"current_tile", "initial_supply_milli", "supplies_milli", "spent_supply_milli",
		"initial_condition_milli", "condition_milli", "condition_loss_milli", "elapsed_minutes",
		"committed_leg_ids", "segment_plan_ids", "segment_start_leg_count",
		"segment_start_elapsed_minutes", "segment_start_spent_supply_milli",
		"segment_start_condition_loss_milli", "previous_leg_receipt", "state_receipt"]
	if not _exact_keys(data, required) or not (data.get("committed_leg_ids") is Array) \
			or not (data.get("segment_plan_ids") is Array):
		return ["journey fields must match V1 exactly"]
	for key in ["schema", "journey_id", "journey_slot", "active_plan_id", "phase",
			"current_tile", "previous_leg_receipt", "state_receipt"]:
		if typeof(data.get(key)) != TYPE_STRING:
			return ["journey field '%s' must be String" % key]
	if String(data["schema"]) != JOURNEY_SCHEMA or String(data["phase"]) not in PHASES \
			or String(data["active_plan_id"]) != String(plan.get("plan_id", "")) \
			or not _short_id_valid(String(data["journey_id"]), JOURNEY_ID_PREFIX) \
			or not _slug_valid(String(data["journey_slot"])):
		return ["journey schema, phase, or active plan mismatch"]
	for key in ["leg_index", "elapsed_minutes", "segment_start_leg_count",
			"segment_start_elapsed_minutes"]:
		if not _bounded_int(data.get(key), 0, MAX_SAFE_JSON_INT):
			return ["journey field '%s' must be a bounded integer" % key]
	for key in ["initial_supply_milli", "supplies_milli", "spent_supply_milli",
			"initial_condition_milli", "condition_milli", "condition_loss_milli",
			"segment_start_spent_supply_milli", "segment_start_condition_loss_milli"]:
		if not _bounded_int(data.get(key), 0, MAX_RESOURCE_MILLI):
			return ["journey resource field '%s' must be bounded" % key]
	var committed: Array = data["committed_leg_ids"]
	for raw_edge_id in committed:
		if typeof(raw_edge_id) != TYPE_STRING or not _short_id_valid(String(raw_edge_id), "rge1:"):
			return ["journey committed legs must be typed edge IDs"]
	var segments: Array = data["segment_plan_ids"]
	if segments.is_empty() or segments.size() > 2:
		return ["journey must retain one root plan and at most one diversion plan"]
	var segment_seen := {}
	for raw_plan_id in segments:
		if typeof(raw_plan_id) != TYPE_STRING or not _short_id_valid(String(raw_plan_id), PLAN_ID_PREFIX) \
				or segment_seen.has(String(raw_plan_id)):
			return ["journey segment plan IDs must be unique typed IDs"]
		segment_seen[String(raw_plan_id)] = true
	if String(segments[-1]) != String(data["active_plan_id"]):
		return ["journey active plan must be its last segment"]
	var expected_journey_id := JOURNEY_ID_PREFIX + _sha256_hex(_canonical_json([
		String(segments[0]), String(data["journey_slot"]), int(data["initial_supply_milli"]),
		int(data["initial_condition_milli"]),
	])).substr(0, 16)
	if String(data["journey_id"]) != expected_journey_id:
		return ["journey ID does not derive from its root plan and initial resources"]
	var leg_index := int(data["leg_index"])
	var path_value: Variant = plan.get("path")
	if not (path_value is Array) or leg_index < 0 or leg_index >= (path_value as Array).size() \
			or String(data["current_tile"]) != String((path_value as Array)[leg_index]):
		return ["journey current tile is not its active path index"]
	var segment_start_leg_count := int(data["segment_start_leg_count"])
	if segment_start_leg_count + leg_index != committed.size() \
			or leg_index > (plan["leg_ids"] as Array).size():
		return ["journey committed leg count does not match its segment checkpoint"]
	for i in range(leg_index):
		if String(committed[segment_start_leg_count + i]) != String((plan["leg_ids"] as Array)[i]):
			return ["journey committed legs are not the active plan prefix"]
	if segments.size() == 1 and (segment_start_leg_count != 0 \
			or int(data["segment_start_elapsed_minutes"]) != 0 \
			or int(data["segment_start_spent_supply_milli"]) != 0 \
			or int(data["segment_start_condition_loss_milli"]) != 0):
		return ["root journey segment checkpoints must start at zero"]
	if int(data["initial_supply_milli"]) != int(data["supplies_milli"]) + int(data["spent_supply_milli"]):
		return ["journey supply conservation failed"]
	if int(data["initial_condition_milli"]) != int(data["condition_milli"]) + int(data["condition_loss_milli"]):
		return ["journey condition conservation failed"]
	var prefix_totals := _plan_prefix_totals(normalized_atlas, normalized_state, plan, leg_index)
	if prefix_totals.is_empty() or int(data["elapsed_minutes"]) \
			!= int(data["segment_start_elapsed_minutes"]) + int(prefix_totals["minutes"]) \
			or int(data["spent_supply_milli"]) \
			!= int(data["segment_start_spent_supply_milli"]) + int(prefix_totals["supply_milli"]) \
			or int(data["condition_loss_milli"]) \
			!= int(data["segment_start_condition_loss_milli"]) + int(prefix_totals["condition_milli"]):
		return ["journey elapsed time or resource ledger does not match its active path prefix"]
	var at_destination := leg_index == (path_value as Array).size() - 1
	if at_destination != (String(data["phase"]) == "arrived"):
		return ["journey arrived phase must match the destination index"]
	if String(data["phase"]) == "stranded":
		var next_cost := _next_leg_cost(normalized_atlas, normalized_state, plan, leg_index)
		if next_cost.is_empty() or (int(data["supplies_milli"]) >= int(next_cost["supply_milli"]) \
				and int(data["condition_milli"]) >= int(next_cost["condition_milli"])):
			return ["journey stranded phase requires an unaffordable next leg"]
	var previous_receipt := String(data["previous_leg_receipt"])
	if previous_receipt != "" and not _receipt_token_valid(previous_receipt):
		return ["journey previous leg receipt must be empty or a SHA-256 receipt"]
	if leg_index > 0 and previous_receipt == "":
		return ["journey after a committed leg must retain its receipt chain"]
	var base := data.duplicate(true)
	base.erase("state_receipt")
	var expected_state_receipt := _receipt_for(base)
	if expected_state_receipt == "" or String(data["state_receipt"]) != expected_state_receipt:
		return ["journey state receipt mismatch"]
	return []


static func normalize_journey(atlas: Dictionary, atlas_state: Dictionary, plan: Dictionary,
		value: Variant) -> Dictionary:
	var normalized_atlas := normalize_atlas(atlas)
	var normalized_state := {} if normalized_atlas.is_empty() \
		else _normalize_atlas_state_normalized(normalized_atlas, atlas_state)
	return _normalize_journey_normalized(normalized_atlas, normalized_state, plan, value)


static func _normalize_journey_normalized(normalized_atlas: Dictionary,
		normalized_state: Dictionary, plan: Dictionary, value: Variant) -> Dictionary:
	if not _validate_journey_normalized(normalized_atlas, normalized_state, plan, value).is_empty():
		return {}
	var data: Dictionary = value
	var normalized := data.duplicate(true)
	for key in ["leg_index", "initial_supply_milli", "supplies_milli", "spent_supply_milli",
			"initial_condition_milli", "condition_milli", "condition_loss_milli", "elapsed_minutes",
			"segment_start_leg_count", "segment_start_elapsed_minutes",
			"segment_start_spent_supply_milli", "segment_start_condition_loss_milli"]:
		normalized[key] = int(data[key])
	return normalized


static func advance_one_leg(atlas: Dictionary, atlas_state: Dictionary, plan: Dictionary,
		journey: Dictionary) -> Dictionary:
	var normalized_atlas := normalize_atlas(atlas)
	var normalized_state := {} if normalized_atlas.is_empty() \
		else _normalize_atlas_state_normalized(normalized_atlas, atlas_state)
	if normalized_atlas.is_empty() or normalized_state.is_empty() \
			or not _plan_matches_normalized(normalized_atlas, normalized_state, plan):
		return {}
	var current := _normalize_journey_normalized(normalized_atlas, normalized_state, plan, journey)
	if current.is_empty() or String(current["phase"]) != "traveling":
		return {}
	var path: Array = plan["path"]
	var index := int(current["leg_index"])
	if index >= path.size() - 1:
		return {}
	var from_id := String(path[index])
	var to_id := String(path[index + 1])
	var edge := _edge_between(normalized_atlas, from_id, to_id)
	var cost := _edge_metrics(normalized_atlas, normalized_state, edge, String(plan["season"]))
	if edge.is_empty() or cost.is_empty():
		return {}
	var supply_before := int(current["supplies_milli"])
	var condition_before := int(current["condition_milli"])
	var enough_supply := supply_before >= int(cost["supply_milli"])
	var enough_condition := condition_before >= int(cost["condition_milli"])
	var result := "settled"
	var next := current.duplicate(true)
	var next_atlas_state := normalized_state.duplicate(true)
	var discovered_add: Array[String] = []
	if not enough_supply or not enough_condition:
		result = "insufficient_supply" if not enough_supply else "insufficient_condition"
		next["phase"] = "stranded"
	else:
		next["leg_index"] = index + 1
		next["current_tile"] = to_id
		next["supplies_milli"] = supply_before - int(cost["supply_milli"])
		next["spent_supply_milli"] = int(next["spent_supply_milli"]) + int(cost["supply_milli"])
		next["condition_milli"] = condition_before - int(cost["condition_milli"])
		next["condition_loss_milli"] = int(next["condition_loss_milli"]) + int(cost["condition_milli"])
		next["elapsed_minutes"] = int(next["elapsed_minutes"]) + int(cost["minutes"])
		(next["committed_leg_ids"] as Array).append(String(edge["id"]))
		discovered_add = _discovery_add(normalized_atlas, normalized_state, to_id)
		next_atlas_state = _state_with_discovery(normalized_atlas, normalized_state, discovered_add)
		if index + 1 == path.size() - 1:
			next["phase"] = "arrived"
		elif int(next["supplies_milli"]) == 0 or int(next["condition_milli"]) == 0:
			next["phase"] = "stranded"
			result = "settled_stranded"
	var before_resources := {"supplies_milli": supply_before, "condition_milli": condition_before}
	var after_resources := {
		"supplies_milli": int(next["supplies_milli"]),
		"condition_milli": int(next["condition_milli"]),
	}
	var leg_base := {
		"schema": LEG_SCHEMA,
		"journey_id": String(current["journey_id"]),
		"plan_id": String(plan["plan_id"]),
		"result": result,
		"leg_index": index + 1,
		"edge_id": String(edge["id"]),
		"from": from_id,
		"to": to_id,
		"cost": cost,
		"resources_before": before_resources,
		"resources_after": after_resources,
		"discovered_add": discovered_add,
		"previous_receipt": String(current["previous_leg_receipt"]),
	}
	var leg_receipt := leg_base.duplicate(true)
	leg_receipt["receipt"] = _receipt_for(leg_base)
	if String(leg_receipt["receipt"]) == "":
		return {}
	next["previous_leg_receipt"] = String(leg_receipt["receipt"])
	var next_base := next.duplicate(true)
	next_base.erase("state_receipt")
	next["state_receipt"] = _receipt_for(next_base)
	if String(next["state_receipt"]) == "" \
			or not _validate_journey_normalized(normalized_atlas, next_atlas_state, plan, next).is_empty():
		return {}
	var transition_base := {
		"schema": TRANSITION_SCHEMA,
		"plan_id": String(plan["plan_id"]),
		"before_journey_state_receipt": String(current["state_receipt"]),
		"before_atlas_state_receipt": String(normalized_state["state_receipt"]),
		"journey": next,
		"atlas_state": next_atlas_state,
		"leg_receipt": leg_receipt,
	}
	var transition := transition_base.duplicate(true)
	transition["transition_receipt"] = _receipt_for(transition_base)
	return transition if String(transition["transition_receipt"]) != "" else {}


static func validate_leg_receipt(atlas: Dictionary, atlas_state: Dictionary, plan: Dictionary,
		before_journey: Dictionary, value: Variant) -> Array[String]:
	var expected := advance_one_leg(atlas, atlas_state, plan, before_journey)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected["leg_receipt"]) != _canonical_json(value):
		return ["leg receipt does not recompute from its exact before-state"]
	return []


static func validate_leg_transition(atlas: Dictionary, atlas_state: Dictionary, plan: Dictionary,
		before_journey: Dictionary, value: Variant) -> Array[String]:
	var expected := advance_one_leg(atlas, atlas_state, plan, before_journey)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["leg transition does not recompute from its exact before-state"]
	return []


static func divert_to_fallback(atlas: Dictionary, atlas_state: Dictionary, parent_plan: Dictionary,
		journey: Dictionary) -> Dictionary:
	var normalized_atlas := normalize_atlas(atlas)
	var normalized_state := {} if normalized_atlas.is_empty() \
		else _normalize_atlas_state_normalized(normalized_atlas, atlas_state)
	if normalized_atlas.is_empty() or normalized_state.is_empty() \
			or not _plan_matches_normalized(normalized_atlas, normalized_state, parent_plan):
		return {}
	var current := _normalize_journey_normalized(normalized_atlas, normalized_state, parent_plan, journey)
	if current.is_empty() or String(current["phase"]) != "traveling" \
			or String(parent_plan.get("fallback", "")) == "" \
			or String(current["current_tile"]) == String(parent_plan["fallback"]):
		return {}
	var child := _make_route_plan_normalized(normalized_atlas, normalized_state, String(current["current_tile"]),
		String(parent_plan["fallback"]), String(parent_plan["season"]), "safe", [],
		"", "fallback_%s" % String(parent_plan["route_key"]))
	if child.is_empty() or not bool(child["available"]):
		return {}
	var projection := _project_plan(child, int(current["supplies_milli"]),
		int(current["condition_milli"]))
	if not bool(projection["reachable"]) \
			or int(projection["arrival_supply_milli"]) < FALLBACK_RESERVE_MILLI:
		return {}
	var diverted := current.duplicate(true)
	diverted["active_plan_id"] = String(child["plan_id"])
	diverted["leg_index"] = 0
	(diverted["segment_plan_ids"] as Array).append(String(child["plan_id"]))
	diverted["segment_start_leg_count"] = (current["committed_leg_ids"] as Array).size()
	diverted["segment_start_elapsed_minutes"] = int(current["elapsed_minutes"])
	diverted["segment_start_spent_supply_milli"] = int(current["spent_supply_milli"])
	diverted["segment_start_condition_loss_milli"] = int(current["condition_loss_milli"])
	var diverted_base := diverted.duplicate(true)
	diverted_base.erase("state_receipt")
	diverted["state_receipt"] = _receipt_for(diverted_base)
	if String(diverted["state_receipt"]) == "" \
			or not _validate_journey_normalized(normalized_atlas, normalized_state, child, diverted).is_empty():
		return {}
	var transition_base := {
		"schema": DIVERSION_SCHEMA,
		"parent_plan_id": String(parent_plan["plan_id"]),
		"before_journey_state_receipt": String(current["state_receipt"]),
		"before_atlas_state_receipt": String(normalized_state["state_receipt"]),
		"child_plan": child,
		"journey": diverted,
		"atlas_state": normalized_state.duplicate(true),
	}
	var transition := transition_base.duplicate(true)
	transition["transition_receipt"] = _receipt_for(transition_base)
	return transition if String(transition["transition_receipt"]) != "" else {}


static func validate_diversion_transition(atlas: Dictionary, atlas_state: Dictionary,
		parent_plan: Dictionary, before_journey: Dictionary, value: Variant) -> Array[String]:
	var expected := divert_to_fallback(atlas, atlas_state, parent_plan, before_journey)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["diversion transition does not recompute from its exact parent state"]
	return []


static func route_receipt(atlas: Dictionary, atlas_state: Dictionary, plan: Dictionary,
		journey: Dictionary) -> Dictionary:
	if not validate_atlas(atlas).is_empty() or not validate_atlas_state(atlas, atlas_state).is_empty() \
			or not validate_plan(atlas, atlas_state, plan).is_empty() \
			or not validate_journey(atlas, atlas_state, plan, journey).is_empty():
		return {}
	var base := {
		"schema": RECEIPT_SCHEMA,
		"atlas_id": String(atlas["atlas_id"]),
		"atlas_receipt": String(atlas["atlas_receipt"]),
		"network_revision": String(atlas["network_revision"]),
		"road_revision": String(atlas_state["road_revision"]),
		"atlas_state_receipt": String(atlas_state["state_receipt"]),
		"journey_id": String(journey["journey_id"]),
		"origin_plan_id": String((journey["segment_plan_ids"] as Array)[0]),
		"plan_id": String(plan["plan_id"]),
		"plan_receipt": String(plan["plan_receipt"]),
		"season": String(plan["season"]),
		"policy": String(plan["policy"]),
		"phase": String(journey["phase"]),
		"current_tile": String(journey["current_tile"]),
		"leg_index": "u32:%d" % int(journey["leg_index"]),
		"elapsed_minutes": "u32:%d" % int(journey["elapsed_minutes"]),
		"supplies_milli": "u32:%d" % int(journey["supplies_milli"]),
		"condition_milli": "u32:%d" % int(journey["condition_milli"]),
		"segment_count": "u32:%d" % (journey["segment_plan_ids"] as Array).size(),
		"last_leg_receipt": String(journey["previous_leg_receipt"]),
		"journey_state_receipt": String(journey["state_receipt"]),
	}
	var receipt := base.duplicate(true)
	receipt["route_receipt"] = _receipt_for(base)
	return receipt if String(receipt["route_receipt"]) != "" else {}


static func validate_route_receipt(atlas: Dictionary, atlas_state: Dictionary, plan: Dictionary,
		journey: Dictionary, value: Variant) -> Array[String]:
	var expected := route_receipt(atlas, atlas_state, plan, journey)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["route receipt does not recompute from atlas, plan, and journey"]
	return []


static func canonical_receipt_json(receipt: Dictionary) -> String:
	var required := ["schema", "atlas_id", "atlas_receipt", "network_revision", "road_revision",
		"atlas_state_receipt", "journey_id", "origin_plan_id", "plan_id", "plan_receipt", "season", "policy",
		"phase", "current_tile", "leg_index", "elapsed_minutes", "supplies_milli",
		"condition_milli", "segment_count", "last_leg_receipt", "journey_state_receipt",
		"route_receipt"]
	if not _exact_keys(receipt, required) or receipt.get("schema") != RECEIPT_SCHEMA:
		return ""
	for key in required:
		if typeof(receipt.get(key)) != TYPE_STRING:
			return ""
	if not _short_id_valid(String(receipt["atlas_id"]), "rga1:") \
			or not _short_id_valid(String(receipt["journey_id"]), JOURNEY_ID_PREFIX) \
			or not _short_id_valid(String(receipt["origin_plan_id"]), PLAN_ID_PREFIX) \
			or not _short_id_valid(String(receipt["plan_id"]), PLAN_ID_PREFIX) \
			or String(receipt["network_revision"]) != NETWORK_REVISION \
			or String(receipt["season"]) not in SEASONS or String(receipt["policy"]) not in POLICIES \
			or String(receipt["phase"]) not in PHASES:
		return ""
	for key in ["atlas_receipt", "road_revision", "atlas_state_receipt", "plan_receipt",
			"journey_state_receipt", "route_receipt"]:
		if not _receipt_token_valid(String(receipt[key])):
			return ""
	if String(receipt["last_leg_receipt"]) != "" \
			and not _receipt_token_valid(String(receipt["last_leg_receipt"])):
		return ""
	for key in ["leg_index", "elapsed_minutes", "supplies_milli", "condition_milli", "segment_count"]:
		if not _u32_token_valid(String(receipt[key])):
			return ""
	var segment_count := int(String(receipt["segment_count"]).substr(4))
	if segment_count < 1 or segment_count > 2:
		return ""
	var current_address := ScaleAddress.parse_id(String(receipt["current_tile"]))
	if current_address.is_empty() or ScaleAddress.canonical_id(current_address) != String(receipt["current_tile"]) \
			or ScaleAddress.level_of(current_address) != "tile":
		return ""
	var base := receipt.duplicate(true)
	base.erase("route_receipt")
	var expected := _receipt_for(base)
	if expected == "" or _string_if(receipt.get("route_receipt")) != expected:
		return ""
	return _canonical_json(receipt)


static func canonical_json(value: Variant) -> String:
	return _canonical_json(value)


static func _project_plan(plan: Dictionary, supplies_milli: int, condition_milli: int) -> Dictionary:
	if plan.is_empty() or not bool(plan.get("available", false)):
		return {
			"status": "blocked", "reachable": false, "arrival_supply_milli": supplies_milli,
			"arrival_condition_milli": condition_milli, "reason": String(plan.get("block_reason", "unavailable")),
		}
	var totals: Dictionary = plan["totals"]
	var reachable := supplies_milli >= int(totals["supply_milli"]) \
		and condition_milli >= int(totals["condition_milli"])
	var arrival_supply := supplies_milli - int(totals["supply_milli"]) if reachable else supplies_milli
	var arrival_condition := condition_milli - int(totals["condition_milli"]) if reachable else condition_milli
	var status := "blocked"
	if reachable:
		status = "safe" if arrival_supply >= SAFE_RESERVE_MILLI else "tight"
	return {
		"status": status,
		"reachable": reachable,
		"arrival_supply_milli": arrival_supply,
		"arrival_condition_milli": arrival_condition,
		"reason": "" if reachable else "resource_shortfall",
	}


static func _best_fallback(atlas: Dictionary, atlas_state: Dictionary, offers: Array[Dictionary],
		start_id: String, season: String, supplies_milli: int, condition_milli: int) -> Dictionary:
	var best := {}
	for offer in offers:
		var parent: Dictionary = offer["plan"]
		var fallback_id := String(parent.get("fallback", ""))
		if fallback_id == "":
			continue
		var plan := _make_route_plan_normalized(atlas, atlas_state, start_id, fallback_id, season, "safe", [],
			"", "fallback_%s" % String(parent["route_key"]))
		var projection := _project_plan(plan, supplies_milli, condition_milli)
		if not bool(projection["reachable"]) or int(projection["arrival_supply_milli"]) < FALLBACK_RESERVE_MILLI:
			continue
		var candidate := {"parent_plan_id": String(parent["plan_id"]), "plan": plan, "projection": projection}
		if best.is_empty() or int(projection["arrival_supply_milli"]) > int((best["projection"] as Dictionary)["arrival_supply_milli"]):
			best = candidate
	return best


static func _annotate_advantages(offers: Array[Dictionary]) -> void:
	var minimum_minutes := 2147483647
	var minimum_supply := 2147483647
	var minimum_condition := 2147483647
	for offer in offers:
		var plan: Dictionary = offer["plan"]
		if not bool(plan.get("available", false)):
			continue
		var totals: Dictionary = plan["totals"]
		minimum_minutes = mini(minimum_minutes, int(totals["minutes"]))
		minimum_supply = mini(minimum_supply, int(totals["supply_milli"]))
		minimum_condition = mini(minimum_condition, int(totals["condition_milli"]))
	for offer in offers:
		var advantages: Array[String] = []
		var plan: Dictionary = offer["plan"]
		if bool(plan.get("available", false)):
			var totals: Dictionary = plan["totals"]
			if int(totals["minutes"]) == minimum_minutes:
				advantages.append("fastest")
			if int(totals["supply_milli"]) == minimum_supply:
				advantages.append("most_supply")
			if int(totals["condition_milli"]) == minimum_condition:
				advantages.append("least_wear")
		offer["advantages"] = advantages


static func _dijkstra(atlas: Dictionary, atlas_state: Dictionary, start_id: String,
		destination_id: String, season: String, policy: String) -> Array[String]:
	if start_id == destination_id:
		return [start_id]
	var adjacency := _adjacency(atlas)
	var edge_by_id := _edge_by_id(atlas)
	var open: Array[String] = [start_id]
	var best := {
		start_id: {
			"policy": policy, "supply_milli": 0, "minutes": 0, "condition_milli": 0,
			"risk_points": 0, "hops": 0, "path": [start_id],
		}
	}
	while not open.is_empty():
		var best_index := 0
		for i in range(1, open.size()):
			if _candidate_less(best[open[i]], best[open[best_index]]):
				best_index = i
		var current: String = open.pop_at(best_index)
		if current == destination_id:
			var found: Array = best[current]["path"]
			var result: Array[String] = []
			for raw_id in found:
				result.append(String(raw_id))
			return result
		var neighbor_edges: Array = adjacency.get(current, [])
		for edge_id_value in neighbor_edges:
			var edge: Dictionary = edge_by_id[String(edge_id_value)]
			var next_id := String(edge["b"]) if String(edge["a"]) == current else String(edge["a"])
			var cost := _edge_metrics(atlas, atlas_state, edge, season)
			if cost.is_empty():
				continue
			var prior: Dictionary = best[current]
			var next_path: Array = (prior["path"] as Array).duplicate()
			next_path.append(next_id)
			var candidate := {
				"policy": policy,
				"supply_milli": int(prior["supply_milli"]) + int(cost["supply_milli"]),
				"minutes": int(prior["minutes"]) + int(cost["minutes"]),
				"condition_milli": int(prior["condition_milli"]) + int(cost["condition_milli"]),
				"risk_points": int(prior["risk_points"]) + int(cost["risk_points"]),
				"hops": int(prior["hops"]) + 1,
				"path": next_path,
			}
			if not best.has(next_id) or _candidate_less(candidate, best[next_id]):
				best[next_id] = candidate
				if next_id not in open:
					open.append(next_id)
	return []


static func _candidate_less(left: Dictionary, right: Dictionary) -> bool:
	var policy := String(left.get("policy", ""))
	if policy != String(right.get("policy", "")):
		return policy < String(right.get("policy", ""))
	var keys := ["supply_milli", "minutes", "condition_milli", "risk_points", "hops"]
	if policy == "fast":
		keys = ["minutes", "supply_milli", "condition_milli", "risk_points", "hops"]
	elif policy == "safe":
		keys = ["condition_milli", "risk_points", "minutes", "supply_milli", "hops"]
	for key in keys:
		if int(left[key]) != int(right[key]):
			return int(left[key]) < int(right[key])
	return _path_lexical_less(left["path"], right["path"])


static func _path_lexical_less(left_value: Variant, right_value: Variant) -> bool:
	if not (left_value is Array) or not (right_value is Array):
		return false
	var left: Array = left_value
	var right: Array = right_value
	for i in range(mini(left.size(), right.size())):
		var left_id := String(left[i])
		var right_id := String(right[i])
		if left_id != right_id:
			return left_id < right_id
	return left.size() < right.size()


static func _path_metrics(atlas: Dictionary, atlas_state: Dictionary, path: Array[String],
		season: String) -> Dictionary:
	var totals := _empty_totals()
	var leg_ids: Array[String] = []
	for i in range(path.size() - 1):
		var edge := _edge_between(atlas, path[i], path[i + 1])
		var cost := _edge_metrics(atlas, atlas_state, edge, season)
		if edge.is_empty() or cost.is_empty():
			return {}
		leg_ids.append(String(edge["id"]))
		totals["minutes"] = int(totals["minutes"]) + int(cost["minutes"])
		totals["supply_milli"] = int(totals["supply_milli"]) + int(cost["supply_milli"])
		totals["condition_milli"] = int(totals["condition_milli"]) + int(cost["condition_milli"])
		totals["risk_points"] = int(totals["risk_points"]) + int(cost["risk_points"])
		totals["road_legs"] = int(totals["road_legs"]) + (1 if String(edge["road_class"]) == "road" else 0)
		totals["track_legs"] = int(totals["track_legs"]) + (1 if String(edge["road_class"]) == "track" else 0)
		totals["hops"] = int(totals["hops"]) + 1
	return {"totals": totals, "leg_ids": leg_ids}


static func _plan_prefix_totals(atlas: Dictionary, atlas_state: Dictionary, plan: Dictionary,
		leg_count: int) -> Dictionary:
	var path: Array = plan.get("path", [])
	if leg_count < 0 or leg_count >= path.size():
		return {}
	var prefix: Array[String] = []
	for i in range(leg_count + 1):
		prefix.append(String(path[i]))
	var metrics := _path_metrics(atlas, atlas_state, prefix, String(plan.get("season", "")))
	return metrics.get("totals", {}) if not metrics.is_empty() else {}


static func _next_leg_cost(atlas: Dictionary, atlas_state: Dictionary, plan: Dictionary,
		leg_index: int) -> Dictionary:
	var path: Array = plan.get("path", [])
	if leg_index < 0 or leg_index >= path.size() - 1:
		return {}
	var edge := _edge_between(atlas, String(path[leg_index]), String(path[leg_index + 1]))
	return _edge_metrics(atlas, atlas_state, edge, String(plan.get("season", "")))


static func _edge_metrics(atlas: Dictionary, atlas_state: Dictionary, edge: Dictionary,
		season: String) -> Dictionary:
	if edge.is_empty() or season not in SEASONS or bool(edge.get("blocked", false)):
		return {}
	for delta in atlas_state.get("road_deltas", []):
		if String(delta.get("edge_id", "")) == String(edge["id"]) and String(delta.get("state", "")) == "closed":
			return {}
	var tile_by_id := _tile_by_id(atlas)
	var a: Dictionary = tile_by_id[String(edge["a"])]
	var b: Dictionary = tile_by_id[String(edge["b"])]
	if season == "winter":
		var a_coord := Vector2i(int(a["q"]), int(a["r"]))
		var b_coord := Vector2i(int(b["q"]), int(b["r"]))
		if a_coord == RIDGE_PASS or b_coord == RIDGE_PASS \
				or String(edge["corridor"]) == "ridge":
			return {}
	var cost_a: Dictionary = TERRAIN_COST[String(a["terrain"])]
	var cost_b: Dictionary = TERRAIN_COST[String(b["terrain"])]
	var minutes := _ceil_div(int(cost_a["minutes"]) + int(cost_b["minutes"]), 2)
	var supply := _ceil_div(int(cost_a["supply_milli"]) + int(cost_b["supply_milli"]), 2)
	var condition := _ceil_div(int(cost_a["condition_milli"]) + int(cost_b["condition_milli"]), 2)
	var risk := maxi(int(a["risk"]), int(b["risk"]))
	var corridor := String(edge["corridor"])
	if corridor == "ridge":
		minutes = _apply_bp(minutes, 7000)
		supply = _apply_bp(supply, 12500)
		condition = _apply_bp(condition, 14000)
		risk += 2
	elif corridor == "market":
		minutes = _apply_bp(minutes, 7000)
		supply = _apply_bp(supply, 5500)
		condition = _apply_bp(condition, 5000)
		risk = maxi(1, risk - 2)
	elif corridor == "dunlin":
		minutes = _apply_bp(minutes, 8500)
		supply = _apply_bp(supply, 3500)
		condition = _apply_bp(condition, 9000)
	elif String(edge["road_class"]) == "road":
		minutes = _apply_bp(minutes, 8000)
		supply = _apply_bp(supply, 6500)
		condition = _apply_bp(condition, 6500)
		risk = maxi(1, risk - 1)
	if season == "spring":
		var wet := String(a["terrain"]) == "marsh" or String(b["terrain"]) == "marsh"
		minutes = _apply_bp(minutes, 13500 if wet else 11000)
		supply = _apply_bp(supply, 12000 if wet else 10800)
		condition = _apply_bp(condition, 13500 if wet else 11200)
		risk += 2 if wet else 1
	elif season == "winter":
		if String(edge["road_class"]) == "road":
			minutes = _apply_bp(minutes, 11000)
			supply = _apply_bp(supply, 10500)
			condition = _apply_bp(condition, 11500)
		else:
			minutes = _apply_bp(minutes, 13000)
			supply = _apply_bp(supply, 12000)
			condition = _apply_bp(condition, 13500)
			risk += 2
	return {"minutes": minutes, "supply_milli": supply, "condition_milli": condition, "risk_points": risk}


static func _empty_totals() -> Dictionary:
	return {
		"minutes": 0, "supply_milli": 0, "condition_milli": 0,
		"risk_points": 0, "road_legs": 0, "track_legs": 0, "hops": 0,
	}


static func _discovery_add(atlas: Dictionary, atlas_state: Dictionary, arrived_id: String) -> Array[String]:
	var discovered := {}
	for raw_id in atlas_state["discovered_tile_ids"]:
		discovered[String(raw_id)] = true
	var center := _coord_for_id(atlas, arrived_id)
	var added: Array[String] = []
	for tile in atlas["tiles"]:
		var coord := Vector2i(int(tile["q"]), int(tile["r"]))
		var candidate := String(tile["id"])
		if axial_distance(center, coord) <= 1 and not discovered.has(candidate):
			added.append(candidate)
	added.sort()
	return added


static func _state_with_discovery(atlas: Dictionary, atlas_state: Dictionary,
		added: Array[String]) -> Dictionary:
	var discovered: Array = (atlas_state["discovered_tile_ids"] as Array).duplicate()
	discovered.append_array(added)
	return _make_atlas_state_normalized(atlas, discovered, atlas_state["road_deltas"])


static func _adjacency(atlas: Dictionary) -> Dictionary:
	var result := {}
	for tile in atlas["tiles"]:
		result[String(tile["id"])] = []
	for edge in atlas["edges"]:
		(result[String(edge["a"])] as Array).append(String(edge["id"]))
		(result[String(edge["b"])] as Array).append(String(edge["id"]))
	for tile_id_value in result:
		(result[tile_id_value] as Array).sort()
	return result


static func _edge_between(atlas: Dictionary, a: String, b: String) -> Dictionary:
	var left := a if a < b else b
	var right := b if a < b else a
	for edge in atlas.get("edges", []):
		if String(edge.get("a", "")) == left and String(edge.get("b", "")) == right:
			return edge
	return {}


static func _edge_by_id(atlas: Dictionary) -> Dictionary:
	var result := {}
	for edge in atlas["edges"]:
		result[String(edge["id"])] = edge
	return result


static func _tile_by_id(atlas: Dictionary) -> Dictionary:
	var result := {}
	for tile in atlas["tiles"]:
		result[String(tile["id"])] = tile
	return result


static func _tile_id_set(atlas: Dictionary) -> Dictionary:
	var result := {}
	for tile in atlas.get("tiles", []):
		result[String(tile.get("id", ""))] = true
	return result


static func _edge_id_set(atlas: Dictionary) -> Dictionary:
	var result := {}
	for edge in atlas.get("edges", []):
		result[String(edge.get("id", ""))] = true
	return result


static func _coord_for_id(atlas: Dictionary, source_id: String) -> Vector2i:
	for tile in atlas.get("tiles", []):
		if String(tile.get("id", "")) == source_id:
			return Vector2i(int(tile["q"]), int(tile["r"]))
	return Vector2i(999999, 999999)


static func _atlas_authority_tiles(tiles: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for tile in tiles:
		result.append({
			"id": tile["id"], "q": tile["q"], "r": tile["r"], "terrain": tile["terrain"],
			"risk": tile["risk"], "forage": tile["forage"], "corridor": tile["corridor"],
			"site_id": tile["site_id"], "site_key": tile["site_key"],
			"site_kind": tile["site_kind"], "safe_stop": tile["safe_stop"],
		})
	return result


static func _ordered_plan(data: Dictionary) -> Dictionary:
	return {
		"schema": data["schema"], "plan_id": data["plan_id"], "atlas_id": data["atlas_id"],
		"network_revision": data["network_revision"], "road_revision": data["road_revision"],
		"cost_profile": data["cost_profile"], "season": data["season"], "policy": data["policy"],
		"route_key": data["route_key"], "origin": data["origin"], "destination": data["destination"],
		"fallback": data["fallback"], "waypoints": data["waypoints"],
		"path": data["path"], "leg_ids": data["leg_ids"], "totals": data["totals"],
		"available": data["available"], "block_reason": data["block_reason"],
		"plan_receipt": data["plan_receipt"],
	}


static func _authored_corridor_edges() -> Dictionary:
	var result := {}
	_add_corridor(result, _greedy_path(ASH_MARKET, RIDGE_PASS), "ridge")
	_add_corridor(result, _greedy_path(RIDGE_PASS, CINDER_CROSSING), "ridge")
	_add_corridor(result, _greedy_path(ASH_MARKET, REDGLASS_QUARRY), "market")
	_add_corridor(result, _greedy_path(REDGLASS_QUARRY, SAINT_VEY_CLINIC), "market")
	_add_corridor(result, _greedy_path(SAINT_VEY_CLINIC, CINDER_CROSSING), "market")
	_add_corridor(result, _greedy_path(ASH_MARKET, DUNLIN_HOMESTEAD), "dunlin")
	_add_corridor(result, _greedy_path(DUNLIN_HOMESTEAD, DUNLIN_BEND), "dunlin")
	_add_corridor(result, _greedy_path(DUNLIN_BEND, CINDER_CROSSING), "dunlin")
	return result


static func _add_corridor(target: Dictionary, path: Array[Vector2i], corridor: String) -> void:
	for i in range(path.size() - 1):
		var a := ScaleAddress.canonical_id(ScaleAddress.tile_address(PLANET_ID, FACE, path[i]))
		var b := ScaleAddress.canonical_id(ScaleAddress.tile_address(PLANET_ID, FACE, path[i + 1]))
		var pair := _pair_key(a, b)
		if not target.has(pair) or corridor == "market":
			target[pair] = corridor


static func _corridor_tiles(edges: Dictionary) -> Dictionary:
	var result := {}
	for pair in edges:
		var ids := String(pair).split("~", false)
		for raw_id in ids:
			var address := ScaleAddress.parse_id(String(raw_id))
			var coord := ScaleAddress.coordinate(address, "tile")
			var key := _coord_key(coord)
			if not result.has(key) or String(edges[pair]) == "market":
				result[key] = String(edges[pair])
	return result


static func _greedy_path(start: Vector2i, destination: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = [start]
	var current := start
	while current != destination:
		var choices: Array[Vector2i] = []
		var best_distance := axial_distance(current, destination)
		for delta in AXIAL_DIRS:
			var candidate: Vector2i = current + delta
			var distance := axial_distance(candidate, destination)
			if distance < best_distance:
				choices.append(candidate)
		choices.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
			return left.x < right.x or (left.x == right.x and left.y < right.y))
		if choices.is_empty():
			return []
		current = choices[0]
		result.append(current)
	return result


static func _terrain_at(coord: Vector2i, seed_value: int) -> String:
	if coord.x >= 4 and coord.x <= 7 and coord.y >= -1 and coord.y <= 2:
		return "highland"
	if coord.x >= 9 and coord.y >= 0 and coord.y <= 5:
		return "marsh"
	if coord.y <= -2:
		return "pine"
	if coord.x <= 2 and coord.y >= 0:
		return "scrub"
	if coord.x >= 11 and coord.y < 0:
		return "ash"
	return ["steppe", "steppe", "pine", "scrub"][int(seed_value % 4)]


static func _terrain_risk(terrain: String) -> int:
	return {"steppe": 2, "pine": 2, "scrub": 3, "marsh": 4, "highland": 5, "ash": 4}.get(terrain, 3)


static func _site_at(coord: Vector2i) -> Dictionary:
	for raw_site in SITE_SPECS:
		var values: Array = raw_site["coord"]
		if coord == Vector2i(int(values[0]), int(values[1])):
			return (raw_site as Dictionary).duplicate(true)
	return {}


static func _pair_key(a: String, b: String) -> String:
	return (a + "~" + b) if a < b else (b + "~" + a)


static func _coord_key(coord: Vector2i) -> String:
	return "%d,%d" % [coord.x, coord.y]


static func _tile_id_for_coord(coord: Vector2i) -> String:
	if not _in_window(coord):
		return ""
	return ScaleAddress.canonical_id(ScaleAddress.tile_address(PLANET_ID, FACE, coord))


static func _in_window(coord: Vector2i) -> bool:
	return coord.x >= Q_MIN and coord.x <= Q_MAX and coord.y >= R_MIN and coord.y <= R_MAX


static func _apply_bp(value: int, basis_points: int) -> int:
	return _ceil_div(value * basis_points, 10000)


static func _ceil_div(value: int, divisor: int) -> int:
	return (value + divisor - 1) / divisor


static func _bounded_int(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		var integer := int(value)
		return integer >= minimum and integer <= maximum
	if typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number == floor(number) \
		and number >= float(minimum) and number <= float(maximum)


static func _root_seed_from_token(token: String) -> Array:
	if not token.begins_with("i64:"):
		return []
	var number := token.substr(4)
	if not _canonical_i64(number):
		return []
	return [int(number)]


static func _canonical_i64(value: String) -> bool:
	if value == "0":
		return true
	if value.is_empty() or value.length() > 20:
		return false
	var first_digit := 0
	if value[0] == "-":
		if value.length() == 1 or value[1] == "0":
			return false
		first_digit = 1
	elif value[0] == "0":
		return false
	for i in range(first_digit, value.length()):
		var code := value.unicode_at(i)
		if code < 48 or code > 57:
			return false
	var magnitude := value.substr(first_digit)
	var limit := "9223372036854775808" if first_digit == 1 else "9223372036854775807"
	if magnitude.length() != limit.length():
		return magnitude.length() < limit.length()
	for i in magnitude.length():
		var digit := magnitude.unicode_at(i)
		var limit_digit := limit.unicode_at(i)
		if digit != limit_digit:
			return digit < limit_digit
	return true


static func _slug_valid(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for i in value.length():
		var code := value.unicode_at(i)
		var lower := code >= 97 and code <= 122
		var digit := code >= 48 and code <= 57
		if not (lower or digit or (i > 0 and (code == 45 or code == 95))):
			return false
	return true


static func _receipt_token_valid(value: String) -> bool:
	return value.begins_with("sha256:") and value.length() == 71 \
		and _lower_hex_valid(value.substr(7), 64)


static func _short_id_valid(value: String, prefix: String) -> bool:
	return value.begins_with(prefix) and value.length() == prefix.length() + 16 \
		and _lower_hex_valid(value.substr(prefix.length()), 16)


static func _u32_token_valid(value: String) -> bool:
	if not value.begins_with("u32:"):
		return false
	var number := value.substr(4)
	return _canonical_i64(number) and int(number) >= 0 and int(number) <= 4294967295


static func _lower_hex_valid(value: String, width: int) -> bool:
	if value.length() != width:
		return false
	for i in value.length():
		var code := value.unicode_at(i)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


static func _string_if(value: Variant) -> String:
	return String(value) if typeof(value) == TYPE_STRING else ""


static func _exact_keys(data: Dictionary, required: Array) -> bool:
	if data.size() != required.size():
		return false
	for key in required:
		if not data.has(key):
			return false
	return true


static func _sha256_hex(text: String) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK \
			or context.update(text.to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()


static func _receipt_for(value: Variant) -> String:
	var encoded := _canonical_json(value)
	if encoded == "":
		return ""
	var digest := _sha256_hex(encoded)
	return "sha256:" + digest if digest != "" else ""


static func _canonical_json(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		TYPE_INT:
			return str(int(value))
		TYPE_FLOAT:
			var number := float(value)
			if not is_finite(number) or number != floor(number) or absf(number) > float(MAX_SAFE_JSON_INT):
				return ""
			return str(int(number))
		TYPE_STRING:
			return JSON.stringify(String(value))
		TYPE_ARRAY:
			var items: Array[String] = []
			for item in value as Array:
				var encoded := _canonical_json(item)
				if encoded == "":
					return ""
				items.append(encoded)
			return "[" + ",".join(items) + "]"
		TYPE_DICTIONARY:
			var data: Dictionary = value
			var keys: Array[String] = []
			for raw_key in data:
				if typeof(raw_key) != TYPE_STRING:
					return ""
				keys.append(String(raw_key))
			keys.sort()
			var fields: Array[String] = []
			for key in keys:
				var encoded := _canonical_json(data[key])
				if encoded == "":
					return ""
				fields.append("%s:%s" % [JSON.stringify(key), encoded])
			return "{" + ",".join(fields) + "}"
	return ""
