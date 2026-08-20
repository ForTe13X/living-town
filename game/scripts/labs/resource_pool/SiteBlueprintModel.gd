extends RefCounted

## RP-0004: deterministic tile-promise -> local-site compiler.
##
## The immutable blueprint and the durable scar state are deliberately separate.
## A blueprint is rebuilt from a canonical RegionRoute site promise. A site state
## stores only stable entity IDs and a receipt chain; it never serializes a second
## copy of the local grid. This file is pure data and never loads Main, Sim,
## WorldView, MapTileLabModel, or any scene.

const ScaleAddress = preload("res://scripts/labs/resource_pool/ScaleAddress.gd")
const RegionRouteModel = preload("res://scripts/labs/resource_pool/RegionRouteModel.gd")

const PROMISE_SCHEMA := "living-town.site-promise/v1"
const BLUEPRINT_SCHEMA := "living-town.site-blueprint/v1"
const STATE_SCHEMA := "living-town.site-state/v1"
const ARRIVAL_SCHEMA := "living-town.site-arrival-evidence/v1"
const ENTER_SCHEMA := "living-town.site-enter-transition/v1"
const DELTA_SCHEMA := "living-town.site-visit-delta/v1"
const TRANSITION_SCHEMA := "living-town.site-state-transition/v1"
const RECEIPT_SCHEMA := "living-town.site-blueprint-receipt/v1"

const COMPILER_REVISION := "tile-local-compiler-v1"
const CONTENT_REVISION := "ashfall-sites-v1"
const GRID_W := 32
const GRID_H := 22
const FLOOR_ID := "surface"
const MAX_SAFE_JSON_INT := 9007199254740991
const MAX_VISITS := 64

const CELL_GROUND := 0
const CELL_ROAD := 1
const CELL_FLOOR := 2
const CELL_WALL := 3
const CELL_DOOR := 4
const CELL_WINDOW := 5
## Codes 0..9 intentionally match MapTileLabModel.Cell for zero-copy opt-in
## materialization. RP-0004 only appends new terrain codes at 10+.
const CELL_RUBBLE := 6
const CELL_WATER := 7
const CELL_EXIT := 8
const CELL_TREE := 9
const CELL_FENCE := 10
const CELL_CROP := 11
const CELL_PIT := 12
const CELL_TYPES := [
	CELL_GROUND, CELL_ROAD, CELL_FLOOR, CELL_WALL, CELL_DOOR, CELL_WINDOW,
	CELL_RUBBLE, CELL_WATER, CELL_EXIT, CELL_TREE, CELL_FENCE, CELL_CROP, CELL_PIT,
]
const WALKABLE_CELLS := [
	CELL_GROUND, CELL_ROAD, CELL_FLOOR, CELL_DOOR, CELL_RUBBLE, CELL_EXIT, CELL_CROP,
]

const SITE_KINDS := ["ruins", "haven", "relay", "quarry", "clinic", "farm"]
const RESOLUTIONS := ["extracted", "collapsed", "retreated"]
const STATE_PHASES := ["idle", "active"]

const LAYOUT_KEYS := {
	"ruins": "ruined_market_block",
	"haven": "crossing_haven",
	"relay": "orra_relay_compound",
	"quarry": "redglass_quarry_works",
	"clinic": "field_clinic_campus",
	"farm": "dunlin_homestead",
}

## Builds the only authoritative V1 promise form from the deterministic RP-0003
## atlas. Callers cannot rename a site or change its kind/risk and retain a valid
## promise by merely recomputing a checksum.
static func make_site_promise(atlas: Dictionary, site_key: String) -> Dictionary:
	var normalized_atlas := RegionRouteModel.normalize_atlas(atlas)
	if normalized_atlas.is_empty() or not _slug_valid(site_key):
		return {}
	var selected: Dictionary = {}
	for raw_tile in normalized_atlas["tiles"] as Array:
		var tile: Dictionary = raw_tile
		if String(tile.get("site_key", "")) == site_key:
			selected = tile
			break
	if selected.is_empty() or String(selected.get("site_kind", "")) not in SITE_KINDS:
		return {}
	var root_seed_token := String(normalized_atlas["root_seed"])
	var root_seed_values := _root_seed_from_token(root_seed_token)
	if root_seed_values.is_empty():
		return {}
	var site_address := ScaleAddress.parse_id(String(selected["site_id"]))
	if site_address.is_empty() or ScaleAddress.level_of(site_address) != ScaleAddress.LEVEL_SITE:
		return {}
	var seed_receipt := ScaleAddress.receipt(
		int(root_seed_values[0]), site_address, "site-blueprint"
	)
	if seed_receipt.is_empty():
		return {}
	var base := {
		"schema": PROMISE_SCHEMA,
		"compiler_revision": COMPILER_REVISION,
		"content_revision": CONTENT_REVISION,
		"source_atlas_id": String(normalized_atlas["atlas_id"]),
		"source_atlas_receipt": String(normalized_atlas["atlas_receipt"]),
		"root_seed": root_seed_token,
		"tile_id": String(selected["id"]),
		"site_id": String(selected["site_id"]),
		"site_key": String(selected["site_key"]),
		"site_kind": String(selected["site_kind"]),
		"label": String(selected["label"]),
		"terrain": String(selected["terrain"]),
		"risk": int(selected["risk"]),
		"seed_receipt": seed_receipt,
	}
	base["promise_receipt"] = _receipt_for(base)
	if String(base["promise_receipt"]) == "":
		return {}
	return base


static func validate_site_promise(value: Variant) -> Array[String]:
	if not (value is Dictionary):
		return ["site promise must be a Dictionary"]
	var data: Dictionary = value
	var required := [
		"schema", "compiler_revision", "content_revision", "source_atlas_id",
		"source_atlas_receipt", "root_seed", "tile_id", "site_id", "site_key",
		"site_kind", "label", "terrain", "risk", "seed_receipt", "promise_receipt",
	]
	if not _exact_keys(data, required) or not (data.get("seed_receipt") is Dictionary):
		return ["site promise fields must match V1 exactly"]
	for key in required:
		if key not in ["risk", "seed_receipt"] and typeof(data.get(key)) != TYPE_STRING:
			return ["site promise field '%s' must be String" % key]
	if data.get("schema") != PROMISE_SCHEMA or data.get("compiler_revision") != COMPILER_REVISION \
			or data.get("content_revision") != CONTENT_REVISION:
		return ["site promise schema or revision mismatch"]
	if not _bounded_int(data.get("risk"), 1, 8) or String(data.get("site_kind")) not in SITE_KINDS \
			or not _slug_valid(String(data.get("site_key"))):
		return ["site promise kind, key, or risk is invalid"]
	var root_seed_values := _root_seed_from_token(String(data.get("root_seed")))
	if root_seed_values.is_empty():
		return ["site promise root_seed must be canonical i64"]
	var site_address := ScaleAddress.parse_id(String(data.get("site_id")))
	var tile_address := ScaleAddress.parse_id(String(data.get("tile_id")))
	if site_address.is_empty() or tile_address.is_empty() \
			or ScaleAddress.level_of(site_address) != ScaleAddress.LEVEL_SITE \
			or ScaleAddress.level_of(tile_address) != ScaleAddress.LEVEL_TILE \
			or ScaleAddress.canonical_id(ScaleAddress.parent(site_address)) != String(data.get("tile_id")):
		return ["site promise site/tile hierarchy is invalid"]
	if not ScaleAddress.validate_receipt(data.get("seed_receipt")).is_empty():
		return ["site promise seed receipt is invalid"]
	var atlas := RegionRouteModel.make_atlas(int(root_seed_values[0]))
	var expected := make_site_promise(atlas, String(data.get("site_key")))
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(data):
		return ["site promise does not match its deterministic atlas source"]
	return []


static func normalize_site_promise(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var data: Dictionary = value
	var root_seed_values := _root_seed_from_token(_string_if(data.get("root_seed")))
	if root_seed_values.is_empty():
		return {}
	var atlas := RegionRouteModel.make_atlas(int(root_seed_values[0]))
	var expected := make_site_promise(atlas, _string_if(data.get("site_key")))
	return expected if not expected.is_empty() \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func compile_site(promise: Dictionary) -> Dictionary:
	var normalized := normalize_site_promise(promise)
	if normalized.is_empty():
		return {}
	return _compile_normalized(normalized)


static func _compile_normalized(promise: Dictionary) -> Dictionary:
	var root_seed_values := _root_seed_from_token(String(promise["root_seed"]))
	var site_address := ScaleAddress.parse_id(String(promise["site_id"]))
	if root_seed_values.is_empty() or site_address.is_empty():
		return {}
	var root_seed := int(root_seed_values[0])
	var layout_seed := ScaleAddress.seed_for(root_seed, site_address, "site-layout")
	var population_seed := ScaleAddress.seed_for(root_seed, site_address, "site-population")
	var clutter_seed := ScaleAddress.seed_for(root_seed, site_address, "site-clutter")
	var seed_token := ScaleAddress.seed_token_for(root_seed, site_address, "site-blueprint")
	var seed_receipts := {
		"layout": ScaleAddress.receipt(root_seed, site_address, "site-layout"),
		"population": ScaleAddress.receipt(root_seed, site_address, "site-population"),
		"clutter": ScaleAddress.receipt(root_seed, site_address, "site-clutter"),
	}
	if layout_seed < 0 or population_seed < 0 or clutter_seed < 0 or seed_token == "" \
			or (seed_receipts["layout"] as Dictionary).is_empty() \
			or (seed_receipts["population"] as Dictionary).is_empty() \
			or (seed_receipts["clutter"] as Dictionary).is_empty():
		return {}
	var cells: Array = []
	cells.resize(GRID_W * GRID_H)
	cells.fill(CELL_GROUND)
	var work := {
		"site_id": String(promise["site_id"]),
		"site_address": site_address,
		"cells": cells,
		"buildings": [],
		"props": [],
		"loot": [],
		"threats": [],
		"occupied": {},
		"protected": {},
		"entry": [1, 13],
		"extraction": [0, 13],
	}
	match String(promise["site_kind"]):
		"ruins":
			_layout_ruined_market(work, layout_seed, population_seed)
		"clinic":
			_layout_clinic(work, layout_seed, population_seed)
		"farm":
			_layout_farm(work, layout_seed, population_seed)
		"quarry":
			_layout_quarry(work, layout_seed, population_seed)
		"relay":
			_layout_relay(work, layout_seed, population_seed)
		"haven":
			_layout_haven(work, layout_seed, population_seed)
		_:
			return {}
	_add_exterior_clutter(work, clutter_seed)
	for collection_name in ["buildings", "props", "loot", "threats"]:
		(work[collection_name] as Array).sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return String(left["id"]) < String(right["id"])
		)
	for raw_building in work["buildings"] as Array:
		var building: Dictionary = raw_building
		(building["doors"] as Array).sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return String(left["cell_id"]) < String(right["cell_id"])
		)
	var entry_pos := _array_pos(work["entry"])
	var extraction_pos := _array_pos(work["extraction"])
	_set_cell(work["cells"], extraction_pos, CELL_EXIT)
	var layout_key := String(LAYOUT_KEYS[String(promise["site_kind"])])
	var blueprint_id_material := [
		String(promise["promise_receipt"]), COMPILER_REVISION, CONTENT_REVISION, layout_key,
	]
	var blueprint_id_digest := _sha256_hex(_canonical_json(blueprint_id_material))
	if blueprint_id_digest == "":
		return {}
	var base := {
		"schema": BLUEPRINT_SCHEMA,
		"compiler_revision": COMPILER_REVISION,
		"content_revision": CONTENT_REVISION,
		"blueprint_id": "sbp1:" + blueprint_id_digest.substr(0, 16),
		"promise_receipt": String(promise["promise_receipt"]),
		"site_id": String(promise["site_id"]),
		"site_kind": String(promise["site_kind"]),
		"layout_key": layout_key,
		"seed_token": seed_token,
		"seed_receipts": seed_receipts,
		"floor": FLOOR_ID,
		"width": GRID_W,
		"height": GRID_H,
		"entry": _anchor_dto(site_address, entry_pos),
		"extraction": _anchor_dto(site_address, extraction_pos),
		"cells": work["cells"],
		"buildings": work["buildings"],
		"props": work["props"],
		"loot": work["loot"],
		"threats": work["threats"],
	}
	var topology := _topology_report_unchecked(base)
	if not bool(topology.get("all_reachable", false)):
		return {}
	base["topology"] = topology
	base["blueprint_receipt"] = _receipt_for(base)
	if String(base["blueprint_receipt"]) == "":
		return {}
	return base


static func validate_blueprint(promise: Dictionary, value: Variant) -> Array[String]:
	var normalized_promise := normalize_site_promise(promise)
	if normalized_promise.is_empty():
		return ["blueprint requires a valid site promise"]
	if not (value is Dictionary):
		return ["blueprint must be a Dictionary"]
	var data: Dictionary = value
	var required := [
		"schema", "compiler_revision", "content_revision", "blueprint_id",
		"promise_receipt", "site_id", "site_kind", "layout_key", "seed_token", "seed_receipts", "floor",
		"width", "height", "entry", "extraction", "cells", "buildings", "props",
		"loot", "threats", "topology", "blueprint_receipt",
	]
	if not _exact_keys(data, required):
		return ["blueprint fields must match V1 exactly"]
	for key in ["entry", "extraction", "topology", "seed_receipts"]:
		if not (data.get(key) is Dictionary):
			return ["blueprint field '%s' must be a Dictionary" % key]
	for key in ["cells", "buildings", "props", "loot", "threats"]:
		if not (data.get(key) is Array):
			return ["blueprint field '%s' must be an Array" % key]
	var structural_errors := _blueprint_structure_errors(data)
	if not structural_errors.is_empty():
		return structural_errors
	var expected := _compile_normalized(normalized_promise)
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(data):
		return ["blueprint does not exactly recompute from its site promise"]
	return []


static func normalize_blueprint(promise: Dictionary, value: Variant) -> Dictionary:
	var normalized_promise := normalize_site_promise(promise)
	if normalized_promise.is_empty():
		return {}
	var expected := _compile_normalized(normalized_promise)
	return expected if not expected.is_empty() \
		and _canonical_json(expected) == _canonical_json(value) else {}


## Observation-only navigation report. Threats are tactical occupants, not
## permanent walls; blocking props are structural blockers.
static func topology_report(promise: Dictionary, blueprint: Dictionary) -> Dictionary:
	var normalized := normalize_blueprint(promise, blueprint)
	return {} if normalized.is_empty() else _topology_report_unchecked(normalized)


## Binds a blueprint promise to a fully validated arrived RegionRoute journey.
## Route season, resources, and path provenance are evidence for admission only;
## they never participate in blueprint entropy. The accepted journey receipt
## must come from the owner's already committed journey CAS record; passing the
## candidate journey's own receipt does not turn a self-hash into authorization.
static func make_arrival_evidence(promise: Dictionary, atlas: Dictionary,
		atlas_state: Dictionary, plan: Dictionary, journey: Dictionary,
		route_receipt: Dictionary, accepted_journey_state_receipt: String) -> Dictionary:
	var normalized_promise := normalize_site_promise(promise)
	if normalized_promise.is_empty() \
			or not RegionRouteModel.validate_atlas(atlas).is_empty() \
			or not RegionRouteModel.validate_atlas_state(atlas, atlas_state).is_empty() \
			or not RegionRouteModel.validate_plan(atlas, atlas_state, plan).is_empty() \
			or not RegionRouteModel.validate_journey(atlas, atlas_state, plan, journey).is_empty() \
			or not RegionRouteModel.validate_route_receipt(
				atlas, atlas_state, plan, journey, route_receipt
			).is_empty():
		return {}
	if String(normalized_promise["source_atlas_id"]) != String(atlas.get("atlas_id", "")) \
			or String(normalized_promise["source_atlas_receipt"]) != String(atlas.get("atlas_receipt", "")) \
			or String(normalized_promise["root_seed"]) != String(atlas.get("root_seed", "")):
		return {}
	if not _receipt_token_valid(accepted_journey_state_receipt) \
			or String(journey.get("state_receipt", "")) != accepted_journey_state_receipt:
		return {}
	if String(journey.get("phase", "")) != "arrived" \
			or String(journey.get("current_tile", "")) != String(normalized_promise["tile_id"]):
		return {}
	var base := {
		"schema": ARRIVAL_SCHEMA,
		"atlas_id": String(atlas["atlas_id"]),
		"atlas_receipt": String(atlas["atlas_receipt"]),
		"atlas_state_receipt": String(atlas_state["state_receipt"]),
		"plan_id": String(plan["plan_id"]),
		"plan_receipt": String(plan["plan_receipt"]),
		"journey_id": String(journey["journey_id"]),
		"journey_state_receipt": String(journey["state_receipt"]),
		"accepted_journey_state_receipt": accepted_journey_state_receipt,
		"route_receipt": String(route_receipt["route_receipt"]),
		"current_tile": String(journey["current_tile"]),
		"site_id": String(normalized_promise["site_id"]),
		"site_kind": String(normalized_promise["site_kind"]),
		"promise_receipt": String(normalized_promise["promise_receipt"]),
	}
	base["arrival_receipt"] = _receipt_for(base)
	return base if String(base["arrival_receipt"]) != "" else {}


static func validate_arrival_evidence(promise: Dictionary, atlas: Dictionary,
		atlas_state: Dictionary, plan: Dictionary, journey: Dictionary,
		route_receipt: Dictionary, accepted_journey_state_receipt: String,
		value: Variant) -> Array[String]:
	var expected := make_arrival_evidence(
		promise, atlas, atlas_state, plan, journey, route_receipt,
		accepted_journey_state_receipt
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["site arrival evidence does not recompute from an arrived route"]
	return []


static func make_initial_state(promise: Dictionary, blueprint: Dictionary) -> Dictionary:
	var normalized := normalize_blueprint(promise, blueprint)
	if normalized.is_empty():
		return {}
	var base := {
		"schema": STATE_SCHEMA,
		"blueprint_id": String(normalized["blueprint_id"]),
		"blueprint_receipt": String(normalized["blueprint_receipt"]),
		"revision": 0,
		"phase": "idle",
		"active_visit_id": "",
		"active_arrival_receipt": "",
		"active_enter_receipt": "",
		"committed_visit_ids": [],
		"depleted_loot_ids": [],
		"neutralized_threat_ids": [],
		"revealed_building_ids": [],
		"destroyed_prop_ids": [],
		"last_resolution": "unvisited",
		"parent_state_receipt": "",
		"last_delta_receipt": "",
	}
	base["state_receipt"] = _receipt_for(base)
	return base if String(base["state_receipt"]) != "" else {}


## Admission is an idle -> active state transition. It does not increment the
## completed-visit revision and does not mutate scars. Two callers can compute
## competing transitions from the same before state; the owner must atomically
## CAS before_state_receipt so only one becomes authoritative. Arrival and site
## state use independent owner-held checkpoint receipts.
static func enter_site(promise: Dictionary, blueprint: Dictionary, before_state: Dictionary,
		expected_before_state_receipt: String, atlas: Dictionary, atlas_state: Dictionary,
		plan: Dictionary, journey: Dictionary, route_receipt: Dictionary,
		accepted_journey_state_receipt: String,
		visit_id: String) -> Dictionary:
	var normalized_blueprint := normalize_blueprint(promise, blueprint)
	var normalized_state := accept_state_checkpoint(
		promise, normalized_blueprint, before_state, expected_before_state_receipt
	) \
		if not normalized_blueprint.is_empty() else {}
	var arrival := make_arrival_evidence(
		promise, atlas, atlas_state, plan, journey, route_receipt,
		accepted_journey_state_receipt
	)
	if normalized_blueprint.is_empty() or normalized_state.is_empty() or arrival.is_empty() \
			or String(normalized_state["phase"]) != "idle" or not _slug_valid(visit_id) \
			or int(normalized_state["revision"]) >= MAX_VISITS \
			or visit_id in (normalized_state["committed_visit_ids"] as Array):
		return {}
	var admission_base := {
		"schema": ENTER_SCHEMA,
		"blueprint_id": String(normalized_blueprint["blueprint_id"]),
		"blueprint_receipt": String(normalized_blueprint["blueprint_receipt"]),
		"before_state_receipt": String(normalized_state["state_receipt"]),
		"accepted_checkpoint_receipt": expected_before_state_receipt,
		"arrival_receipt": String(arrival["arrival_receipt"]),
		"visit_id": visit_id,
		"revision": int(normalized_state["revision"]),
	}
	var admission_receipt := _receipt_for(admission_base)
	if admission_receipt == "":
		return {}
	var after := normalized_state.duplicate(true)
	after["phase"] = "active"
	after["active_visit_id"] = visit_id
	after["active_arrival_receipt"] = String(arrival["arrival_receipt"])
	after["active_enter_receipt"] = admission_receipt
	after["parent_state_receipt"] = String(normalized_state["state_receipt"])
	after.erase("state_receipt")
	after["state_receipt"] = _receipt_for(after)
	if String(after["state_receipt"]) == "":
		return {}
	var transition := {
		"schema": ENTER_SCHEMA,
		"blueprint_id": String(normalized_blueprint["blueprint_id"]),
		"visit_id": visit_id,
		"revision": int(normalized_state["revision"]),
		"before_state_receipt": String(normalized_state["state_receipt"]),
		"accepted_checkpoint_receipt": expected_before_state_receipt,
		"before_state": normalized_state,
		"arrival_evidence": arrival,
		"arrival_receipt": String(arrival["arrival_receipt"]),
		"admission_receipt": admission_receipt,
		"after_state_receipt": String(after["state_receipt"]),
		"after_state": after,
	}
	transition["transition_receipt"] = _receipt_for(transition)
	return transition if String(transition["transition_receipt"]) != "" else {}


static func validate_enter_transition(promise: Dictionary, blueprint: Dictionary,
		before_state: Dictionary, expected_before_state_receipt: String,
		atlas: Dictionary, atlas_state: Dictionary,
		plan: Dictionary, journey: Dictionary, route_receipt: Dictionary,
		accepted_journey_state_receipt: String,
		visit_id: String, value: Variant) -> Array[String]:
	var expected := enter_site(
		promise, blueprint, before_state, expected_before_state_receipt, atlas,
		atlas_state, plan, journey, route_receipt, accepted_journey_state_receipt,
		visit_id
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["site enter transition does not recompute from arrival and before state"]
	return []


## Structural snapshot validation is intentionally not event authorization.
## Production acceptance must validate a transition against its exact stored
## before_state and atomically CAS before_state_receipt.
static func validate_state_snapshot(promise: Dictionary, blueprint: Dictionary,
		value: Variant) -> Array[String]:
	var normalized_blueprint := normalize_blueprint(promise, blueprint)
	if normalized_blueprint.is_empty():
		return ["site state requires a valid blueprint"]
	if not (value is Dictionary):
		return ["site state must be a Dictionary"]
	var data: Dictionary = value
	var required := [
		"schema", "blueprint_id", "blueprint_receipt", "revision", "phase",
		"active_visit_id", "active_arrival_receipt", "active_enter_receipt",
		"committed_visit_ids",
		"depleted_loot_ids", "neutralized_threat_ids", "revealed_building_ids",
		"destroyed_prop_ids", "last_resolution", "parent_state_receipt",
		"last_delta_receipt", "state_receipt",
	]
	if not _exact_keys(data, required):
		return ["site state fields must match V1 exactly"]
	for key in ["committed_visit_ids", "depleted_loot_ids", "neutralized_threat_ids",
			"revealed_building_ids", "destroyed_prop_ids"]:
		if not (data.get(key) is Array):
			return ["site state field '%s' must be an Array" % key]
	for key in ["schema", "blueprint_id", "blueprint_receipt", "phase",
			"active_visit_id", "active_arrival_receipt", "active_enter_receipt", "last_resolution",
			"parent_state_receipt", "last_delta_receipt", "state_receipt"]:
		if typeof(data.get(key)) != TYPE_STRING:
			return ["site state field '%s' must be String" % key]
	if data.get("schema") != STATE_SCHEMA \
			or data.get("blueprint_id") != normalized_blueprint.get("blueprint_id") \
			or data.get("blueprint_receipt") != normalized_blueprint.get("blueprint_receipt") \
			or not _bounded_int(data.get("revision"), 0, MAX_VISITS) \
			or String(data.get("phase")) not in STATE_PHASES:
		return ["site state schema, blueprint, or revision mismatch"]
	var revision := int(data["revision"])
	if (data["committed_visit_ids"] as Array).size() != revision:
		return ["site state revision must equal committed visit count"]
	if revision == 0 and String(data["phase"]) == "idle":
		var expected_initial := make_initial_state(promise, normalized_blueprint)
		if expected_initial.is_empty() or _canonical_json(expected_initial) != _canonical_json(data):
			return ["revision-zero site state must be the exact initial state"]
		return []
	if String(data["phase"]) == "idle":
		if String(data["active_visit_id"]) != "" \
				or String(data["active_arrival_receipt"]) != "" \
				or String(data["active_enter_receipt"]) != "":
			return ["idle site state cannot retain active admission fields"]
	else:
		if not _slug_valid(String(data["active_visit_id"])) \
				or String(data["active_visit_id"]) in (data["committed_visit_ids"] as Array) \
				or not _receipt_token_valid(String(data["active_arrival_receipt"])) \
				or not _receipt_token_valid(String(data["active_enter_receipt"])) \
				or not _receipt_token_valid(String(data["parent_state_receipt"])):
			return ["active site state requires an uncommitted typed admission"]
	if revision == 0:
		if String(data["last_resolution"]) != "unvisited" \
				or String(data["last_delta_receipt"]) != "":
			return ["pre-first-visit state cannot claim a terminal result"]
	elif String(data["last_resolution"]) not in RESOLUTIONS \
			or not _receipt_token_valid(String(data["parent_state_receipt"])) \
			or not _receipt_token_valid(String(data["last_delta_receipt"])):
		return ["visited site state requires typed chain receipts and resolution"]
	if not _sorted_unique_slugs(data["committed_visit_ids"] as Array):
		return ["site state visit IDs must be sorted unique slugs"]
	var entity_sets := _entity_id_sets(normalized_blueprint)
	for pair in [
		["depleted_loot_ids", "loot"], ["neutralized_threat_ids", "threats"],
		["revealed_building_ids", "buildings"], ["destroyed_prop_ids", "destructible_props"],
	]:
		var field := String(pair[0])
		var entity_kind := String(pair[1])
		if not _sorted_unique_subset(data[field] as Array, entity_sets[entity_kind] as Dictionary):
			return ["site state field '%s' must be a sorted unique entity subset" % field]
	var base := data.duplicate(true)
	base.erase("state_receipt")
	var expected_receipt := _receipt_for(base)
	if expected_receipt == "" or String(data["state_receipt"]) != expected_receipt:
		return ["site state receipt mismatch"]
	return []


static func normalize_state_snapshot(promise: Dictionary, blueprint: Dictionary,
		value: Variant) -> Dictionary:
	if not validate_state_snapshot(promise, blueprint, value).is_empty():
		return {}
	var data: Dictionary = value
	var normalized := data.duplicate(true)
	normalized["revision"] = int(data["revision"])
	return normalized


## Explicit owner-bound acceptance boundary. The expected receipt must come from
## the owner's already accepted save/CAS record, never from the candidate DTO.
## This is integrity checking, not a cryptographic signature.
static func accept_state_checkpoint(promise: Dictionary, blueprint: Dictionary,
		value: Variant, expected_state_receipt: String) -> Dictionary:
	if not _receipt_token_valid(expected_state_receipt):
		return {}
	var normalized := normalize_state_snapshot(promise, blueprint, value)
	if normalized.is_empty() \
			or String(normalized["state_receipt"]) != expected_state_receipt:
		return {}
	return normalized


## Owner-side constructor for terminal facts emitted by a trusted action reducer
## or two-phase gameplay adapter. Exact recomputation proves provenance/order and
## monotonic scars; it does not prove that the player actually reached, looted,
## fought, or extracted. Raw client claims must never call this as authorization.
static func make_visit_delta(promise: Dictionary, blueprint: Dictionary, before_state: Dictionary,
		enter_transition: Dictionary, accepted_idle_state_receipt: String,
		atlas: Dictionary, atlas_state: Dictionary,
		plan: Dictionary, journey: Dictionary, route_receipt: Dictionary,
		accepted_journey_state_receipt: String,
		visit_id: String, resolution: String, elapsed_turns: int,
		depleted_loot_ids: Array, neutralized_threat_ids: Array,
		revealed_building_ids: Array, destroyed_prop_ids: Array) -> Dictionary:
	var normalized_blueprint := normalize_blueprint(promise, blueprint)
	var normalized_state := normalize_state_snapshot(promise, normalized_blueprint, before_state) \
		if not normalized_blueprint.is_empty() else {}
	var enter_before: Dictionary = enter_transition.get("before_state", {}) \
		if enter_transition is Dictionary else {}
	if normalized_blueprint.is_empty() or normalized_state.is_empty() \
			or not _slug_valid(visit_id) or resolution not in RESOLUTIONS \
			or not _bounded_int(elapsed_turns, 0, 100000) \
			or int(normalized_state["revision"]) >= MAX_VISITS \
			or String(normalized_state["phase"]) != "active" \
			or String(normalized_state["active_visit_id"]) != visit_id \
			or enter_before.is_empty() \
			or not validate_enter_transition(
				promise, normalized_blueprint, enter_before, accepted_idle_state_receipt,
				atlas, atlas_state, plan, journey, route_receipt,
				accepted_journey_state_receipt, visit_id, enter_transition
			).is_empty() \
			or _canonical_json(normalized_state) \
				!= _canonical_json(enter_transition.get("after_state", {})):
		return {}
	if visit_id in (normalized_state["committed_visit_ids"] as Array):
		return {}
	var lists := {
		"depleted_loot_ids": _normalized_id_list(depleted_loot_ids),
		"neutralized_threat_ids": _normalized_id_list(neutralized_threat_ids),
		"revealed_building_ids": _normalized_id_list(revealed_building_ids),
		"destroyed_prop_ids": _normalized_id_list(destroyed_prop_ids),
	}
	var originals := {
		"depleted_loot_ids": depleted_loot_ids,
		"neutralized_threat_ids": neutralized_threat_ids,
		"revealed_building_ids": revealed_building_ids,
		"destroyed_prop_ids": destroyed_prop_ids,
	}
	for key in lists:
		if (lists[key] as Array).size() != (originals[key] as Array).size():
			return {}
	if elapsed_turns == 0:
		if resolution != "retreated":
			return {}
		for key in lists:
			if not (lists[key] as Array).is_empty():
				return {}
	var entity_sets := _entity_id_sets(normalized_blueprint)
	var before_fields := {
		"depleted_loot_ids": _array_set(normalized_state["depleted_loot_ids"] as Array),
		"neutralized_threat_ids": _array_set(normalized_state["neutralized_threat_ids"] as Array),
		"revealed_building_ids": _array_set(normalized_state["revealed_building_ids"] as Array),
		"destroyed_prop_ids": _array_set(normalized_state["destroyed_prop_ids"] as Array),
	}
	var entity_kind_for_field := {
		"depleted_loot_ids": "loot",
		"neutralized_threat_ids": "threats",
		"revealed_building_ids": "buildings",
		"destroyed_prop_ids": "destructible_props",
	}
	for key in lists:
		var ids: Array = lists[key]
		var allowed: Dictionary = entity_sets[String(entity_kind_for_field[key])]
		var existing: Dictionary = before_fields[key]
		for raw_id in ids:
			var entity_id := String(raw_id)
			if not allowed.has(entity_id) or existing.has(entity_id):
				return {}
	var base := {
		"schema": DELTA_SCHEMA,
		"blueprint_id": String(normalized_blueprint["blueprint_id"]),
		"blueprint_receipt": String(normalized_blueprint["blueprint_receipt"]),
		"before_state_receipt": String(normalized_state["state_receipt"]),
		"active_enter_receipt": String(normalized_state["active_enter_receipt"]),
		"expected_revision": int(normalized_state["revision"]),
		"visit_id": visit_id,
		"resolution": resolution,
		"elapsed_turns": elapsed_turns,
		"depleted_loot_ids": lists["depleted_loot_ids"],
		"neutralized_threat_ids": lists["neutralized_threat_ids"],
		"revealed_building_ids": lists["revealed_building_ids"],
		"destroyed_prop_ids": lists["destroyed_prop_ids"],
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["delta_id"] = "svd1:" + digest.substr(0, 16)
	base["delta_receipt"] = _receipt_for(base)
	return base if String(base["delta_receipt"]) != "" else {}


static func validate_visit_delta(promise: Dictionary, blueprint: Dictionary,
		before_state: Dictionary, enter_transition: Dictionary,
		accepted_idle_state_receipt: String, atlas: Dictionary,
		atlas_state: Dictionary, plan: Dictionary, journey: Dictionary,
		route_receipt: Dictionary, accepted_journey_state_receipt: String,
		value: Variant) -> Array[String]:
	if not (value is Dictionary):
		return ["site visit delta must be a Dictionary"]
	var data: Dictionary = value
	var required := [
		"schema", "blueprint_id", "blueprint_receipt", "before_state_receipt",
		"active_enter_receipt", "expected_revision", "visit_id", "resolution", "elapsed_turns",
		"depleted_loot_ids", "neutralized_threat_ids", "revealed_building_ids",
		"destroyed_prop_ids", "delta_id", "delta_receipt",
	]
	if not _exact_keys(data, required):
		return ["site visit delta fields must match V1 exactly"]
	for key in ["depleted_loot_ids", "neutralized_threat_ids", "revealed_building_ids",
			"destroyed_prop_ids"]:
		if not (data.get(key) is Array):
			return ["site visit delta field '%s' must be an Array" % key]
	if not _bounded_int(data.get("elapsed_turns"), 0, 100000) \
			or not _bounded_int(data.get("expected_revision"), 0, MAX_VISITS):
		return ["site visit delta numeric fields must be bounded integers"]
	var expected := make_visit_delta(
		promise, blueprint, before_state, enter_transition, accepted_idle_state_receipt,
		atlas, atlas_state, plan, journey, route_receipt,
		accepted_journey_state_receipt, _string_if(data.get("visit_id")),
		_string_if(data.get("resolution")), int(data.get("elapsed_turns", 0)),
		data["depleted_loot_ids"], data["neutralized_threat_ids"],
		data["revealed_building_ids"], data["destroyed_prop_ids"]
	)
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(data):
		return ["site visit delta does not recompute from its exact before state"]
	return []


static func apply_visit_delta(promise: Dictionary, blueprint: Dictionary,
		before_state: Dictionary, enter_transition: Dictionary,
		accepted_idle_state_receipt: String, atlas: Dictionary,
		atlas_state: Dictionary, plan: Dictionary, journey: Dictionary,
		route_receipt: Dictionary, accepted_journey_state_receipt: String,
		delta: Dictionary) -> Dictionary:
	var normalized_blueprint := normalize_blueprint(promise, blueprint)
	var normalized_state := normalize_state_snapshot(promise, normalized_blueprint, before_state) \
		if not normalized_blueprint.is_empty() else {}
	if normalized_state.is_empty() \
			or not validate_visit_delta(
				promise, normalized_blueprint, normalized_state, enter_transition,
				accepted_idle_state_receipt, atlas, atlas_state, plan, journey,
				route_receipt, accepted_journey_state_receipt, delta
			).is_empty():
		return {}
	var after := normalized_state.duplicate(true)
	after["revision"] = int(normalized_state["revision"]) + 1
	after["phase"] = "idle"
	after["active_visit_id"] = ""
	after["active_arrival_receipt"] = ""
	after["active_enter_receipt"] = ""
	after["committed_visit_ids"] = _union_sorted(
		normalized_state["committed_visit_ids"] as Array, [String(delta["visit_id"])]
	)
	for field in ["depleted_loot_ids", "neutralized_threat_ids", "revealed_building_ids",
			"destroyed_prop_ids"]:
		after[field] = _union_sorted(normalized_state[field] as Array, delta[field] as Array)
	after["last_resolution"] = String(delta["resolution"])
	after["parent_state_receipt"] = String(normalized_state["state_receipt"])
	after["last_delta_receipt"] = String(delta["delta_receipt"])
	after.erase("state_receipt")
	after["state_receipt"] = _receipt_for(after)
	if String(after["state_receipt"]) == "":
		return {}
	var transition_base := {
		"schema": TRANSITION_SCHEMA,
		"blueprint_id": String(normalized_blueprint["blueprint_id"]),
		"visit_id": String(delta["visit_id"]),
		"resolution": String(delta["resolution"]),
		"from_revision": int(normalized_state["revision"]),
		"to_revision": int(after["revision"]),
		"before_state_receipt": String(normalized_state["state_receipt"]),
		"delta_receipt": String(delta["delta_receipt"]),
		"after_state_receipt": String(after["state_receipt"]),
		"after_state": after,
	}
	transition_base["transition_receipt"] = _receipt_for(transition_base)
	return transition_base if String(transition_base["transition_receipt"]) != "" else {}


static func validate_state_transition(promise: Dictionary, blueprint: Dictionary,
		before_state: Dictionary, enter_transition: Dictionary,
		accepted_idle_state_receipt: String, atlas: Dictionary,
		atlas_state: Dictionary, plan: Dictionary, journey: Dictionary,
		route_receipt: Dictionary, accepted_journey_state_receipt: String,
		delta: Dictionary, value: Variant) -> Array[String]:
	var expected := apply_visit_delta(
		promise, blueprint, before_state, enter_transition, accepted_idle_state_receipt,
		atlas, atlas_state, plan, journey, route_receipt,
		accepted_journey_state_receipt, delta
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["site state transition does not recompute from before state and delta"]
	return []


static func blueprint_receipt(promise: Dictionary, blueprint: Dictionary) -> Dictionary:
	var normalized := normalize_blueprint(promise, blueprint)
	if normalized.is_empty():
		return {}
	var topology: Dictionary = normalized["topology"]
	var base := {
		"schema": RECEIPT_SCHEMA,
		"blueprint_id": String(normalized["blueprint_id"]),
		"blueprint_receipt": String(normalized["blueprint_receipt"]),
		"promise_receipt": String(normalized["promise_receipt"]),
		"site_id": String(normalized["site_id"]),
		"site_kind": String(normalized["site_kind"]),
		"layout_key": String(normalized["layout_key"]),
		"compiler_revision": String(normalized["compiler_revision"]),
		"content_revision": String(normalized["content_revision"]),
		"seed_token": String(normalized["seed_token"]),
		"grid": "%dx%d" % [int(normalized["width"]), int(normalized["height"])],
		"buildings": "u32:%d" % (normalized["buildings"] as Array).size(),
		"loot": "u32:%d" % (normalized["loot"] as Array).size(),
		"threats": "u32:%d" % (normalized["threats"] as Array).size(),
		"reachable_cells": "u32:%d" % int(topology["reachable_cells"]),
		"topology_receipt": String(topology["topology_receipt"]),
	}
	base["receipt"] = _receipt_for(base)
	return base if String(base["receipt"]) != "" else {}


static func validate_blueprint_receipt(promise: Dictionary, blueprint: Dictionary,
		value: Variant) -> Array[String]:
	var expected := blueprint_receipt(promise, blueprint)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["blueprint receipt does not recompute from promise and blueprint"]
	return []


static func canonical_receipt_json(promise: Dictionary, blueprint: Dictionary,
		receipt: Dictionary) -> String:
	if not validate_blueprint_receipt(promise, blueprint, receipt).is_empty():
		return ""
	return "{\"schema\":%s,\"blueprint_id\":%s,\"blueprint_receipt\":%s,\"promise_receipt\":%s,\"site_id\":%s,\"site_kind\":%s,\"layout_key\":%s,\"compiler_revision\":%s,\"content_revision\":%s,\"seed_token\":%s,\"grid\":%s,\"buildings\":%s,\"loot\":%s,\"threats\":%s,\"reachable_cells\":%s,\"topology_receipt\":%s,\"receipt\":%s}" % [
		JSON.stringify(String(receipt["schema"])),
		JSON.stringify(String(receipt["blueprint_id"])),
		JSON.stringify(String(receipt["blueprint_receipt"])),
		JSON.stringify(String(receipt["promise_receipt"])),
		JSON.stringify(String(receipt["site_id"])),
		JSON.stringify(String(receipt["site_kind"])),
		JSON.stringify(String(receipt["layout_key"])),
		JSON.stringify(String(receipt["compiler_revision"])),
		JSON.stringify(String(receipt["content_revision"])),
		JSON.stringify(String(receipt["seed_token"])),
		JSON.stringify(String(receipt["grid"])),
		JSON.stringify(String(receipt["buildings"])),
		JSON.stringify(String(receipt["loot"])),
		JSON.stringify(String(receipt["threats"])),
		JSON.stringify(String(receipt["reachable_cells"])),
		JSON.stringify(String(receipt["topology_receipt"])),
		JSON.stringify(String(receipt["receipt"])),
	]


static func canonical_json(value: Variant) -> String:
	return _canonical_json(value)


static func cell_at(blueprint: Dictionary, pos: Vector2i) -> int:
	if not _in_bounds(pos) or not (blueprint.get("cells") is Array) \
			or (blueprint["cells"] as Array).size() != GRID_W * GRID_H:
		return CELL_WALL
	return int((blueprint["cells"] as Array)[pos.y * GRID_W + pos.x])


static func is_walkable(blueprint: Dictionary, pos: Vector2i) -> bool:
	if cell_at(blueprint, pos) not in WALKABLE_CELLS:
		return false
	for raw_prop in blueprint.get("props", []) as Array:
		var prop: Dictionary = raw_prop
		if bool(prop.get("blocking", false)) and _array_pos(prop.get("pos", [])) == pos:
			return false
	return true


static func _layout_ruined_market(work: Dictionary, layout_seed: int,
		population_seed: int) -> void:
	work["entry"] = [1, 13]
	work["extraction"] = [0, 13]
	_fill_rect(work["cells"], [0, 13, GRID_W, 1], CELL_ROAD)
	_fill_rect(work["cells"], [15, 8, 3, GRID_H - 8], CELL_ROAD)
	_add_building(work, [4, 2, 11, 9], "ROADSIDE STORE", "store", "south", 0, layout_seed)
	_add_building(work, [19, 2, 11, 10], "FIELD CLINIC", "clinic", "south", 1, layout_seed)
	_add_building(work, [3, 15, 11, 6], "LOCKSMITH", "workshop", "north", 2, layout_seed)
	_add_building(work, [18, 15, 12, 6], "TENEMENT", "home", "north", 3, layout_seed)
	_add_prop(work, [5, 4], "shelf", "dry goods", true, true, 0)
	_add_prop(work, [5, 7], "shelf", "dry goods", true, true, 1)
	_add_prop(work, [8, 8], "counter", "till counter", true, true, 2)
	_add_prop(work, [20, 3], "bed", "exam cot", true, false, 3)
	_add_prop(work, [23, 9], "cabinet", "medical cabinet", true, true, 4)
	_add_prop(work, [4, 19], "workbench", "vice bench", true, true, 5)
	_add_prop(work, [12, 16], "crate", "parts crate", true, true, 6)
	_add_prop(work, [23, 19], "stove", "iron stove", true, true, 7)
	_add_prop(work, [28, 16], "wardrobe", "wardrobe", true, true, 8)
	_add_loot(work, [7, 5], "food", "sealed rations", 18, 1200, 2, 0, population_seed)
	_add_loot(work, [12, 7], "scrap", "cashbox scrap", 24, 2000, 3, 1, population_seed)
	_add_loot(work, [22, 5], "meds", "trauma pouch", 42, 800, 2, 2, population_seed)
	_add_loot(work, [27, 8], "meds", "antiseptic", 28, 600, 1, 3, population_seed)
	_add_loot(work, [6, 18], "parts", "machined parts", 36, 2400, 4, 4, population_seed)
	_add_loot(work, [11, 17], "scrap", "copper coil", 31, 1700, 3, 5, population_seed)
	_add_loot(work, [21, 18], "food", "cellar preserves", 20, 1400, 2, 6, population_seed)
	_add_loot(work, [27, 17], "parts", "radio valves", 55, 1100, 4, 7, population_seed)
	_add_threat(work, [16, 9], "drifter", 2, 0, population_seed)
	_add_threat(work, [30, 13], "drifter", 2, 1, population_seed)
	_add_threat(work, [16, 19], "drifter", 2, 2, population_seed)


static func _layout_clinic(work: Dictionary, layout_seed: int,
		population_seed: int) -> void:
	work["entry"] = [16, 20]
	work["extraction"] = [16, 21]
	_fill_rect(work["cells"], [15, 0, 3, GRID_H], CELL_ROAD)
	_fill_rect(work["cells"], [0, 11, GRID_W, 2], CELL_ROAD)
	_add_building(work, [3, 2, 15, 8], "TREATMENT WING", "clinic", "south", 0, layout_seed)
	_add_building(work, [21, 2, 9, 9], "PHARMACY", "pharmacy", "south", 1, layout_seed)
	_add_building(work, [3, 14, 10, 7], "AMBULANCE BAY", "garage", "north", 2, layout_seed)
	_add_building(work, [20, 14, 10, 7], "RECOVERY WARD", "ward", "north", 3, layout_seed)
	_add_prop(work, [5, 4], "bed", "exam cot", true, false, 0)
	_add_prop(work, [7, 7], "cabinet", "surgical cabinet", true, true, 1)
	_add_prop(work, [14, 7], "desk", "nurse station", true, true, 2)
	_add_prop(work, [22, 4], "shelf", "medicine shelf", true, true, 3)
	_add_prop(work, [28, 8], "counter", "dispensary counter", true, true, 4)
	_add_prop(work, [4, 18], "crate", "ambulance kit", true, true, 5)
	_add_prop(work, [28, 16], "bed", "recovery cot", true, false, 6)
	_add_loot(work, [6, 5], "meds", "suture roll", 31, 400, 1, 0, population_seed)
	_add_loot(work, [12, 7], "meds", "trauma pouch", 48, 900, 2, 1, population_seed)
	_add_loot(work, [23, 5], "meds", "antibiotics", 52, 500, 2, 2, population_seed)
	_add_loot(work, [27, 7], "meds", "antiseptic crate", 39, 1200, 3, 3, population_seed)
	_add_loot(work, [6, 17], "parts", "ambulance alternator", 34, 2200, 4, 4, population_seed)
	_add_loot(work, [22, 17], "food", "ward rations", 18, 900, 1, 5, population_seed)
	_add_loot(work, [27, 18], "meds", "sealed bandages", 27, 700, 1, 6, population_seed)
	_add_threat(work, [16, 6], "orderly", 2, 0, population_seed)
	_add_threat(work, [18, 11], "lurker", 2, 1, population_seed)


static func _layout_farm(work: Dictionary, layout_seed: int,
		population_seed: int) -> void:
	work["entry"] = [1, 18]
	work["extraction"] = [0, 18]
	_fill_rect(work["cells"], [0, 18, GRID_W, 2], CELL_ROAD)
	_fill_rect(work["cells"], [7, 8, 3, 11], CELL_ROAD)
	_fill_rect(work["cells"], [7, 12, 18, 2], CELL_ROAD)
	_fill_rect(work["cells"], [21, 8, 3, 11], CELL_ROAD)
	_fill_rect(work["cells"], [1, 13, 5, 4], CELL_CROP)
	_fill_rect(work["cells"], [11, 14, 5, 4], CELL_CROP)
	_add_building(work, [3, 2, 11, 9], "FARMHOUSE", "home", "south", 0, layout_seed)
	_add_building(work, [17, 2, 13, 10], "BARN", "barn", "south", 1, layout_seed)
	_add_building(work, [18, 15, 10, 6], "CELLAR SHED", "shed", "north", 2, layout_seed)
	_add_prop(work, [4, 4], "stove", "farm stove", true, true, 0)
	_add_prop(work, [12, 8], "wardrobe", "pantry", true, true, 1)
	_add_prop(work, [18, 4], "crate", "grain bin", true, true, 2)
	_add_prop(work, [28, 9], "workbench", "tack bench", true, true, 3)
	_add_prop(work, [19, 17], "shelf", "cellar shelf", true, true, 4)
	_add_loot(work, [5, 5], "food", "smoked roots", 17, 1000, 1, 0, population_seed)
	_add_loot(work, [11, 7], "meds", "farm first aid", 24, 500, 1, 1, population_seed)
	_add_loot(work, [19, 6], "food", "grain sack", 22, 2400, 3, 2, population_seed)
	_add_loot(work, [26, 8], "parts", "thresher belt", 31, 1700, 3, 3, population_seed)
	_add_loot(work, [20, 18], "food", "cellar preserves", 28, 1800, 2, 4, population_seed)
	_add_loot(work, [25, 17], "food", "seed potatoes", 19, 2100, 2, 5, population_seed)
	_add_loot(work, [13, 16], "food", "field basket", 13, 1300, 1, 6, population_seed)
	_add_threat(work, [15, 13], "feral", 2, 0, population_seed)
	_add_threat(work, [30, 18], "feral", 2, 1, population_seed)


static func _layout_quarry(work: Dictionary, layout_seed: int,
		population_seed: int) -> void:
	work["entry"] = [1, 11]
	work["extraction"] = [0, 11]
	_fill_rect(work["cells"], [0, 10, GRID_W, 3], CELL_ROAD)
	_fill_rect(work["cells"], [4, 7, 3, 12], CELL_ROAD)
	_fill_rect(work["cells"], [18, 7, 3, 6], CELL_ROAD)
	_fill_rect(work["cells"], [20, 14, 12, 8], CELL_PIT)
	_fill_rect(work["cells"], [24, 17, 8, 5], CELL_WATER)
	_add_building(work, [3, 2, 9, 7], "WEIGH STATION", "office", "south", 0, layout_seed)
	_add_building(work, [14, 2, 15, 8], "CRUSHER SHOP", "workshop", "south", 1, layout_seed)
	_add_building(work, [3, 15, 9, 6], "TOOL SHED", "shed", "north", 2, layout_seed)
	_add_prop(work, [4, 4], "desk", "weigh ledger", true, true, 0)
	_add_prop(work, [10, 7], "cabinet", "lock cabinet", true, true, 1)
	_add_prop(work, [15, 4], "workbench", "crusher bench", true, true, 2)
	_add_prop(work, [27, 8], "crate", "bearing crate", true, true, 3)
	_add_prop(work, [4, 18], "workbench", "tool bench", true, true, 4)
	_add_loot(work, [5, 5], "scrap", "weigh brass", 29, 1700, 2, 0, population_seed)
	_add_loot(work, [9, 6], "parts", "survey gear", 38, 2200, 3, 1, population_seed)
	_add_loot(work, [17, 5], "parts", "crusher bearing", 61, 2400, 5, 2, population_seed)
	_add_loot(work, [22, 6], "scrap", "redglass plate", 43, 2300, 4, 3, population_seed)
	_add_loot(work, [27, 7], "parts", "drive coupling", 58, 2100, 5, 4, population_seed)
	_add_loot(work, [6, 18], "parts", "hardened tools", 45, 1900, 4, 5, population_seed)
	_add_loot(work, [10, 17], "scrap", "copper detonator", 36, 800, 3, 6, population_seed)
	_add_threat(work, [13, 11], "quarry_guard", 3, 0, population_seed)
	_add_threat(work, [30, 11], "quarry_guard", 2, 1, population_seed)
	_add_threat(work, [15, 16], "quarry_guard", 2, 2, population_seed)
	_add_threat(work, [17, 19], "quarry_guard", 2, 3, population_seed)


static func _layout_relay(work: Dictionary, layout_seed: int,
		population_seed: int) -> void:
	work["entry"] = [16, 20]
	work["extraction"] = [16, 21]
	_fill_rect(work["cells"], [15, 0, 3, GRID_H], CELL_ROAD)
	_fill_rect(work["cells"], [2, 11, 28, 2], CELL_ROAD)
	_fill_rect(work["cells"], [2, 14, 28, 2], CELL_ROAD)
	_stamp_fence(work["cells"], [2, 2, 28, 18], [16, 19])
	_add_building(work, [8, 4, 14, 7], "RELAY CONTROL", "relay", "south", 0, layout_seed)
	_add_building(work, [23, 4, 6, 7], "GENERATOR SHED", "generator", "south", 1, layout_seed)
	_add_building(work, [4, 13, 7, 6], "WATCH BUNK", "bunk", "east", 2, layout_seed)
	_add_prop(work, [18, 3], "tower", "relay mast", true, false, 0)
	_add_prop(work, [9, 6], "desk", "radio desk", true, true, 1)
	_add_prop(work, [20, 8], "cabinet", "signal cabinet", true, true, 2)
	_add_prop(work, [24, 6], "workbench", "generator bench", true, true, 3)
	_add_prop(work, [5, 15], "bed", "watch cot", true, false, 4)
	_add_loot(work, [10, 7], "parts", "relay crystals", 57, 700, 4, 0, population_seed)
	_add_loot(work, [19, 8], "parts", "radio valves", 52, 1100, 4, 1, population_seed)
	_add_loot(work, [25, 7], "parts", "generator brushes", 41, 1800, 5, 2, population_seed)
	_add_loot(work, [27, 8], "scrap", "copper winding", 34, 1600, 4, 3, population_seed)
	_add_loot(work, [6, 16], "meds", "watch kit", 27, 600, 2, 4, population_seed)
	_add_loot(work, [9, 17], "food", "relay ration", 16, 900, 1, 5, population_seed)
	_add_threat(work, [18, 11], "relay_guard", 3, 0, population_seed)
	_add_threat(work, [16, 15], "relay_guard", 2, 1, population_seed)
	_add_threat(work, [12, 11], "relay_guard", 2, 2, population_seed)


static func _layout_haven(work: Dictionary, layout_seed: int,
		population_seed: int) -> void:
	work["entry"] = [1, 12]
	work["extraction"] = [0, 12]
	_fill_rect(work["cells"], [0, 11, GRID_W, 3], CELL_ROAD)
	_fill_rect(work["cells"], [6, 8, 3, 10], CELL_ROAD)
	_fill_rect(work["cells"], [21, 8, 3, 10], CELL_ROAD)
	_fill_rect(work["cells"], [10, 8, 10, 8], CELL_ROAD)
	_add_building(work, [3, 2, 12, 8], "CROSSING INN", "inn", "south", 0, layout_seed)
	_add_building(work, [18, 2, 12, 8], "CARAVAN DEPOT", "depot", "south", 1, layout_seed)
	_add_building(work, [3, 15, 11, 6], "COOKHOUSE", "kitchen", "north", 2, layout_seed)
	_add_building(work, [19, 15, 10, 6], "BUNKHOUSE", "bunk", "north", 3, layout_seed)
	_add_prop(work, [4, 4], "table", "inn table", true, true, 0)
	_add_prop(work, [13, 7], "counter", "inn counter", true, true, 1)
	_add_prop(work, [19, 4], "crate", "depot crate", true, true, 2)
	_add_prop(work, [28, 7], "workbench", "wagon bench", true, true, 3)
	_add_prop(work, [4, 18], "stove", "cook stove", true, true, 4)
	_add_prop(work, [27, 18], "bed", "bunk cot", true, false, 5)
	_add_loot(work, [6, 5], "food", "inn stores", 17, 1300, 1, 0, population_seed)
	_add_loot(work, [12, 7], "meds", "traveler salve", 23, 400, 1, 1, population_seed)
	_add_loot(work, [20, 5], "parts", "wagon pins", 28, 1500, 2, 2, population_seed)
	_add_loot(work, [27, 7], "scrap", "trade tin", 19, 900, 1, 3, population_seed)
	_add_loot(work, [7, 18], "food", "stew pot", 15, 1600, 1, 4, population_seed)
	_add_threat(work, [30, 12], "straggler", 2, 0, population_seed)


static func _add_building(work: Dictionary, rect: Array, label: String, kind: String,
		entrance_side: String, ordinal: int, seed_value: int) -> void:
	var x := int(rect[0])
	var y := int(rect[1])
	var width := int(rect[2])
	var height := int(rect[3])
	for py in range(y, y + height):
		for px in range(x, x + width):
			var edge := px == x or py == y or px == x + width - 1 or py == y + height - 1
			_set_cell(work["cells"], Vector2i(px, py), CELL_WALL if edge else CELL_FLOOR)
	var outer_door := Vector2i(x + width / 2 - 2, y + height - 1)
	if entrance_side == "north":
		outer_door.y = y
	elif entrance_side == "east":
		outer_door = Vector2i(x + width - 1, y + height / 2 - 1)
	elif entrance_side == "west":
		outer_door = Vector2i(x, y + height / 2 - 1)
	_set_cell(work["cells"], outer_door, CELL_DOOR)
	var doors: Array = [_door_dto(work["site_address"], outer_door, "exterior")]
	var facade_y := y + height - 1 if entrance_side == "south" else y
	if entrance_side in ["north", "south"]:
		for window_pos in [Vector2i(x + 2, facade_y), Vector2i(x + width - 3, facade_y)]:
			if window_pos != outer_door:
				_set_cell(work["cells"], window_pos, CELL_WINDOW)
	elif entrance_side in ["east", "west"]:
		var facade_x := x + width - 1 if entrance_side == "east" else x
		_set_cell(work["cells"], Vector2i(facade_x, y + 1), CELL_WINDOW)
		_set_cell(work["cells"], Vector2i(facade_x, y + height - 2), CELL_WINDOW)
	if width >= 11:
		var divider_x := x + width / 2
		for py in range(y + 1, y + height - 1):
			_set_cell(work["cells"], Vector2i(divider_x, py), CELL_WALL)
		var inner_door := Vector2i(divider_x, y + 2)
		_set_cell(work["cells"], inner_door, CELL_DOOR)
		doors.append(_door_dto(work["site_address"], inner_door, "interior"))
	var id_material := [String(work["site_id"]), "building", label, kind, rect, entrance_side]
	var building_id := "sbld1:" + _sha256_hex(_canonical_json(id_material)).substr(0, 16)
	var interior_anchor := outer_door
	match entrance_side:
		"south":
			interior_anchor.y -= 1
		"north":
			interior_anchor.y += 1
		"east":
			interior_anchor.x -= 1
		"west":
			interior_anchor.x += 1
	(work["buildings"] as Array).append({
		"id": building_id,
		"label": label,
		"kind": kind,
		"rect": rect.duplicate(true),
		"entrance_side": entrance_side,
		"doors": doors,
		"interior_anchor": [interior_anchor.x, interior_anchor.y],
		"roof_tone": int(_mix(seed_value, ordinal + 31) % 3),
	})
	_protect_manhattan(work["protected"], _array_pos(work["entry"]), outer_door)


static func _add_prop(work: Dictionary, pos_values: Array, kind: String, label: String,
		blocking: bool, destructible: bool, ordinal: int) -> void:
	var pos := _array_pos(pos_values)
	var id_material := [String(work["site_id"]), "prop", kind, label, pos_values]
	var prop_id := "sprp1:" + _sha256_hex(_canonical_json(id_material)).substr(0, 16)
	(work["props"] as Array).append({
		"id": prop_id,
		"cell_id": _cell_id(work["site_address"], pos),
		"pos": pos_values.duplicate(true),
		"kind": kind,
		"label": label,
		"blocking": blocking,
		"destructible": destructible,
	})
	if blocking:
		(work["occupied"] as Dictionary)[_coord_key(pos)] = true


static func _add_loot(work: Dictionary, pos_values: Array, kind: String, label: String,
		value: int, weight_grams: int, noise: int, ordinal: int, seed_value: int) -> void:
	var pos := _array_pos(pos_values)
	var id_material := [String(work["site_id"]), "loot", kind, label, pos_values, CONTENT_REVISION]
	var loot_id := "sloot1:" + _sha256_hex(_canonical_json(id_material)).substr(0, 16)
	(work["loot"] as Array).append({
		"id": loot_id,
		"cell_id": _cell_id(work["site_address"], pos),
		"pos": pos_values.duplicate(true),
		"kind": kind,
		"label": label,
		"value": value,
		"weight_grams": weight_grams,
		"noise": noise,
		"glint": int(_mix(seed_value, ordinal + 71) % 3),
	})
	(work["occupied"] as Dictionary)[_coord_key(pos)] = true
	(work["protected"] as Dictionary)[_coord_key(pos)] = true


static func _add_threat(work: Dictionary, pos_values: Array, kind: String, hp: int,
		ordinal: int, seed_value: int) -> void:
	var pos := _array_pos(pos_values)
	var id_material := [String(work["site_id"]), "threat", kind, pos_values, CONTENT_REVISION]
	var threat_id := "sthr1:" + _sha256_hex(_canonical_json(id_material)).substr(0, 16)
	(work["threats"] as Array).append({
		"id": threat_id,
		"cell_id": _cell_id(work["site_address"], pos),
		"pos": pos_values.duplicate(true),
		"kind": kind,
		"hp": hp,
		"alert_radius": 3 + int(_mix(seed_value, ordinal + 101) % 3),
	})
	(work["occupied"] as Dictionary)[_coord_key(pos)] = true
	(work["protected"] as Dictionary)[_coord_key(pos)] = true


static func _add_exterior_clutter(work: Dictionary, seed_value: int) -> void:
	var cells: Array = work["cells"]
	var protected: Dictionary = work["protected"]
	var occupied: Dictionary = work["occupied"]
	for y in GRID_H:
		for x in GRID_W:
			var pos := Vector2i(x, y)
			var key := _coord_key(pos)
			if _cell(cells, pos) != CELL_GROUND or protected.has(key) or occupied.has(key):
				continue
			var roll := int(_mix(seed_value, x + y * GRID_W + 211) % 100)
			if roll < 5:
				_set_cell(cells, pos, CELL_TREE)
			elif roll < 10:
				_set_cell(cells, pos, CELL_RUBBLE)


static func _stamp_fence(cells: Array, rect: Array, gate: Array) -> void:
	var x := int(rect[0])
	var y := int(rect[1])
	var width := int(rect[2])
	var height := int(rect[3])
	for px in range(x, x + width):
		_set_cell(cells, Vector2i(px, y), CELL_FENCE)
		_set_cell(cells, Vector2i(px, y + height - 1), CELL_FENCE)
	for py in range(y, y + height):
		_set_cell(cells, Vector2i(x, py), CELL_FENCE)
		_set_cell(cells, Vector2i(x + width - 1, py), CELL_FENCE)
	_set_cell(cells, _array_pos(gate), CELL_DOOR)


static func _fill_rect(cells: Array, rect: Array, cell_type: int) -> void:
	for y in range(int(rect[1]), int(rect[1]) + int(rect[3])):
		for x in range(int(rect[0]), int(rect[0]) + int(rect[2])):
			_set_cell(cells, Vector2i(x, y), cell_type)


static func _topology_report_unchecked(blueprint: Dictionary) -> Dictionary:
	var entry: Dictionary = blueprint.get("entry", {})
	var start := _array_pos(entry.get("pos", []))
	var reachable := _reachable_cells(blueprint, start)
	var walkable_count := 0
	for y in GRID_H:
		for x in GRID_W:
			if is_walkable(blueprint, Vector2i(x, y)):
				walkable_count += 1
	var door_total := 0
	var door_reachable := 0
	var building_reachable := 0
	for raw_building in blueprint.get("buildings", []) as Array:
		var building: Dictionary = raw_building
		var building_ok := reachable.has(_coord_key(_array_pos(building.get("interior_anchor", []))))
		if building_ok:
			building_reachable += 1
		for raw_door in building.get("doors", []) as Array:
			var door: Dictionary = raw_door
			door_total += 1
			if reachable.has(_coord_key(_array_pos(door.get("pos", [])))):
				door_reachable += 1
	var loot_reachable := _reachable_entity_count(blueprint.get("loot", []) as Array, reachable)
	var threat_reachable := _reachable_entity_count(blueprint.get("threats", []) as Array, reachable)
	var extraction_pos := _array_pos((blueprint.get("extraction", {}) as Dictionary).get("pos", []))
	var all_reachable := reachable.has(_coord_key(extraction_pos)) \
		and door_reachable == door_total \
		and building_reachable == (blueprint.get("buildings", []) as Array).size() \
		and loot_reachable == (blueprint.get("loot", []) as Array).size() \
		and threat_reachable == (blueprint.get("threats", []) as Array).size()
	var base := {
		"walkable_cells": walkable_count,
		"reachable_cells": reachable.size(),
		"doors_total": door_total,
		"doors_reachable": door_reachable,
		"buildings_total": (blueprint.get("buildings", []) as Array).size(),
		"buildings_reachable": building_reachable,
		"loot_total": (blueprint.get("loot", []) as Array).size(),
		"loot_reachable": loot_reachable,
		"threats_total": (blueprint.get("threats", []) as Array).size(),
		"threats_reachable": threat_reachable,
		"extraction_reachable": reachable.has(_coord_key(extraction_pos)),
		"all_reachable": all_reachable,
	}
	base["topology_receipt"] = _receipt_for(base)
	return base


static func _reachable_cells(blueprint: Dictionary, start: Vector2i) -> Dictionary:
	var reached := {}
	if not _in_bounds(start) or not is_walkable(blueprint, start):
		return reached
	var queue: Array[Vector2i] = [start]
	reached[_coord_key(start)] = true
	var head := 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		for delta in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var next: Vector2i = current + delta
			var key := _coord_key(next)
			if _in_bounds(next) and not reached.has(key) and is_walkable(blueprint, next):
				reached[key] = true
				queue.append(next)
	return reached


static func _reachable_entity_count(entities: Array, reachable: Dictionary) -> int:
	var count := 0
	for raw_entity in entities:
		var entity: Dictionary = raw_entity
		if reachable.has(_coord_key(_array_pos(entity.get("pos", [])))):
			count += 1
	return count


static func _blueprint_structure_errors(data: Dictionary) -> Array[String]:
	if data.get("schema") != BLUEPRINT_SCHEMA \
			or data.get("compiler_revision") != COMPILER_REVISION \
			or data.get("content_revision") != CONTENT_REVISION \
			or data.get("floor") != FLOOR_ID \
			or data.get("site_kind") not in SITE_KINDS:
		return ["blueprint schema, revision, floor, or kind mismatch"]
	if not _bounded_int(data.get("width"), GRID_W, GRID_W) \
			or not _bounded_int(data.get("height"), GRID_H, GRID_H) \
			or (data["cells"] as Array).size() != GRID_W * GRID_H:
		return ["blueprint grid dimensions are invalid"]
	for raw_cell in data["cells"] as Array:
		if not _bounded_int(raw_cell, CELL_GROUND, CELL_PIT) or int(raw_cell) not in CELL_TYPES:
			return ["blueprint contains an invalid cell type"]
	for key in ["blueprint_id", "promise_receipt", "site_id", "layout_key", "seed_token",
			"blueprint_receipt"]:
		if typeof(data.get(key)) != TYPE_STRING:
			return ["blueprint field '%s' must be String" % key]
	if not _short_id_valid(String(data["blueprint_id"]), "sbp1:") \
			or not _receipt_token_valid(String(data["promise_receipt"])) \
			or not _receipt_token_valid(String(data["blueprint_receipt"])) \
			or not _seed_token_valid(String(data["seed_token"])):
		return ["blueprint identity or receipt token is invalid"]
	var site_address := ScaleAddress.parse_id(String(data["site_id"]))
	if site_address.is_empty() or ScaleAddress.level_of(site_address) != ScaleAddress.LEVEL_SITE:
		return ["blueprint site_id must be a canonical site address"]
	var seed_receipts: Dictionary = data["seed_receipts"]
	if not _exact_keys(seed_receipts, ["layout", "population", "clutter"]):
		return ["blueprint seed receipt streams must match V1 exactly"]
	var expected_purposes := {
		"layout": "site-layout", "population": "site-population", "clutter": "site-clutter",
	}
	var seen_seed_tokens := {}
	for stream in ["layout", "population", "clutter"]:
		var raw_receipt: Variant = seed_receipts.get(stream)
		if not (raw_receipt is Dictionary) \
				or not ScaleAddress.validate_receipt(raw_receipt).is_empty():
			return ["blueprint %s seed receipt is invalid" % stream]
		var seed_receipt: Dictionary = raw_receipt
		if String(seed_receipt.get("address")) != String(data["site_id"]) \
				or String(seed_receipt.get("purpose")) != String(expected_purposes[stream]) \
				or seen_seed_tokens.has(String(seed_receipt.get("seed_token"))):
			return ["blueprint seed streams must bind site, purpose, and distinct tokens"]
		seen_seed_tokens[String(seed_receipt["seed_token"])] = true
	for key in ["entry", "extraction"]:
		var anchor: Dictionary = data[key]
		if not _anchor_valid(site_address, anchor):
			return ["blueprint %s anchor is invalid" % key]
	var entity_errors := _entity_structure_errors(site_address, data)
	if not entity_errors.is_empty():
		return entity_errors
	var topology: Dictionary = data["topology"]
	var expected_topology := _topology_report_unchecked(data)
	if _canonical_json(topology) != _canonical_json(expected_topology) \
			or not bool(expected_topology.get("all_reachable", false)):
		return ["blueprint topology report or reachability gate failed"]
	var base := data.duplicate(true)
	base.erase("blueprint_receipt")
	if String(data["blueprint_receipt"]) != _receipt_for(base):
		return ["blueprint receipt mismatch"]
	return []


static func _entity_structure_errors(site_address: Dictionary, data: Dictionary) -> Array[String]:
	var all_ids := {}
	var occupied := {}
	var building_rects: Array = []
	for raw_building in data["buildings"] as Array:
		if not (raw_building is Dictionary):
			return ["blueprint building must be a Dictionary"]
		var building: Dictionary = raw_building
		var required := ["id", "label", "kind", "rect", "entrance_side", "doors",
			"interior_anchor", "roof_tone"]
		if not _exact_keys(building, required) or not (building.get("rect") is Array) \
				or not (building.get("doors") is Array) or not (building.get("interior_anchor") is Array) \
				or not _short_id_valid(_string_if(building.get("id")), "sbld1:") \
				or all_ids.has(String(building.get("id"))):
			return ["blueprint building fields or ID are invalid"]
		all_ids[String(building["id"])] = true
		if not _rect_valid(building["rect"] as Array) \
				or not _pos_array_valid(building["interior_anchor"]) \
				or not _bounded_int(building.get("roof_tone"), 0, 2) \
				or String(building.get("entrance_side")) not in ["north", "south", "east", "west"]:
			return ["blueprint building geometry is invalid"]
		for other_rect in building_rects:
			if _rects_overlap(building["rect"] as Array, other_rect as Array):
				return ["blueprint building footprints overlap"]
		building_rects.append((building["rect"] as Array).duplicate(true))
		var exterior_count := 0
		for raw_door in building["doors"] as Array:
			if not (raw_door is Dictionary) or not _door_valid(site_address, raw_door as Dictionary):
				return ["blueprint building door is invalid"]
			if String((raw_door as Dictionary)["role"]) == "exterior":
				exterior_count += 1
		if exterior_count != 1:
			return ["blueprint building requires exactly one exterior door"]
	for section in ["props", "loot", "threats"]:
		for raw_entity in data[section] as Array:
			if not (raw_entity is Dictionary):
				return ["blueprint %s entity must be a Dictionary" % section]
			var entity: Dictionary = raw_entity
			var id_prefix := "sprp1:" if section == "props" else ("sloot1:" if section == "loot" else "sthr1:")
			if not _short_id_valid(_string_if(entity.get("id")), id_prefix) \
					or all_ids.has(String(entity.get("id"))) \
					or not _entity_cell_valid(site_address, entity):
				return ["blueprint %s entity identity or position is invalid" % section]
			all_ids[String(entity["id"])] = true
			var key := _coord_key(_array_pos(entity["pos"]))
			if occupied.has(key):
				return ["blueprint entities overlap at %s" % key]
			occupied[key] = true
			if section == "props":
				var prop_required := ["id", "cell_id", "pos", "kind", "label", "blocking", "destructible"]
				if not _exact_keys(entity, prop_required) or typeof(entity.get("blocking")) != TYPE_BOOL \
						or typeof(entity.get("destructible")) != TYPE_BOOL:
					return ["blueprint prop fields are invalid"]
			elif section == "loot":
				var loot_required := ["id", "cell_id", "pos", "kind", "label", "value",
					"weight_grams", "noise", "glint"]
				if not _exact_keys(entity, loot_required) \
						or not _bounded_int(entity.get("value"), 1, 100000) \
						or not _bounded_int(entity.get("weight_grams"), 1, 100000) \
						or not _bounded_int(entity.get("noise"), 0, 10) \
						or not _bounded_int(entity.get("glint"), 0, 2):
					return ["blueprint loot fields are invalid"]
			else:
				var threat_required := ["id", "cell_id", "pos", "kind", "hp", "alert_radius"]
				if not _exact_keys(entity, threat_required) \
						or not _bounded_int(entity.get("hp"), 1, 100) \
						or not _bounded_int(entity.get("alert_radius"), 1, 20):
					return ["blueprint threat fields are invalid"]
	return []


static func _entity_id_sets(blueprint: Dictionary) -> Dictionary:
	var result := {"loot": {}, "threats": {}, "buildings": {}, "destructible_props": {}}
	for raw_entity in blueprint["loot"] as Array:
		(result["loot"] as Dictionary)[String((raw_entity as Dictionary)["id"])] = true
	for raw_entity in blueprint["threats"] as Array:
		(result["threats"] as Dictionary)[String((raw_entity as Dictionary)["id"])] = true
	for raw_entity in blueprint["buildings"] as Array:
		(result["buildings"] as Dictionary)[String((raw_entity as Dictionary)["id"])] = true
	for raw_entity in blueprint["props"] as Array:
		var prop: Dictionary = raw_entity
		if bool(prop["destructible"]):
			(result["destructible_props"] as Dictionary)[String(prop["id"])] = true
	return result


static func _anchor_dto(site_address: Dictionary, pos: Vector2i) -> Dictionary:
	return {"cell_id": _cell_id(site_address, pos), "pos": [pos.x, pos.y]}


static func _anchor_valid(site_address: Dictionary, anchor: Dictionary) -> bool:
	return _exact_keys(anchor, ["cell_id", "pos"]) and _entity_cell_valid(site_address, anchor)


static func _door_dto(site_address: Dictionary, pos: Vector2i, role: String) -> Dictionary:
	return {"cell_id": _cell_id(site_address, pos), "pos": [pos.x, pos.y], "role": role}


static func _door_valid(site_address: Dictionary, door: Dictionary) -> bool:
	return _exact_keys(door, ["cell_id", "pos", "role"]) \
		and String(door.get("role")) in ["exterior", "interior"] \
		and _entity_cell_valid(site_address, door)


static func _entity_cell_valid(site_address: Dictionary, entity: Dictionary) -> bool:
	if not (entity.get("pos") is Array) or typeof(entity.get("cell_id")) != TYPE_STRING \
			or not _pos_array_valid(entity["pos"]):
		return false
	var pos := _array_pos(entity["pos"])
	return String(entity["cell_id"]) == _cell_id(site_address, pos)


static func _cell_id(site_address: Dictionary, pos: Vector2i) -> String:
	return ScaleAddress.canonical_id(ScaleAddress.with_cell(site_address, pos, FLOOR_ID))


static func _cell(cells: Array, pos: Vector2i) -> int:
	return CELL_WALL if not _in_bounds(pos) else int(cells[pos.y * GRID_W + pos.x])


static func _set_cell(cells: Array, pos: Vector2i, value: int) -> void:
	if _in_bounds(pos):
		cells[pos.y * GRID_W + pos.x] = value


static func _in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < GRID_W and pos.y < GRID_H


static func _array_pos(value: Variant) -> Vector2i:
	if not (value is Array) or (value as Array).size() != 2:
		return Vector2i(-999999, -999999)
	return Vector2i(int((value as Array)[0]), int((value as Array)[1]))


static func _pos_array_valid(value: Variant) -> bool:
	if not (value is Array) or (value as Array).size() != 2 \
			or not _bounded_int((value as Array)[0], 0, GRID_W - 1) \
			or not _bounded_int((value as Array)[1], 0, GRID_H - 1):
		return false
	return true


static func _rect_valid(rect: Array) -> bool:
	if rect.size() != 4:
		return false
	for raw_value in rect:
		if not _bounded_int(raw_value, 0, maxi(GRID_W, GRID_H)):
			return false
	var x := int(rect[0])
	var y := int(rect[1])
	var width := int(rect[2])
	var height := int(rect[3])
	return width >= 3 and height >= 3 and x >= 0 and y >= 0 \
		and x + width <= GRID_W and y + height <= GRID_H


static func _rects_overlap(a: Array, b: Array) -> bool:
	return int(a[0]) < int(b[0]) + int(b[2]) and int(a[0]) + int(a[2]) > int(b[0]) \
		and int(a[1]) < int(b[1]) + int(b[3]) and int(a[1]) + int(a[3]) > int(b[1])


static func _protect_manhattan(protected: Dictionary, start: Vector2i, destination: Vector2i) -> void:
	var current := start
	protected[_coord_key(current)] = true
	while current.x != destination.x:
		current.x += signi(destination.x - current.x)
		protected[_coord_key(current)] = true
	while current.y != destination.y:
		current.y += signi(destination.y - current.y)
		protected[_coord_key(current)] = true


static func _coord_key(pos: Vector2i) -> String:
	return "%d,%d" % [pos.x, pos.y]


static func _mix(seed_value: int, salt: int) -> int:
	var value := seed_value ^ (salt * 1103515245 + 12345)
	value = value ^ (value >> 16)
	value = value * 2246822519
	value = value ^ (value >> 13)
	return value & 0x7fffffffffffffff


static func _normalized_id_list(value: Array) -> Array[String]:
	var result: Array[String] = []
	var seen := {}
	for raw_id in value:
		if typeof(raw_id) != TYPE_STRING or seen.has(String(raw_id)):
			return []
		seen[String(raw_id)] = true
		result.append(String(raw_id))
	result.sort()
	return result


static func _union_sorted(left: Array, right: Array) -> Array[String]:
	var seen := {}
	for raw_id in left:
		seen[String(raw_id)] = true
	for raw_id in right:
		seen[String(raw_id)] = true
	var result: Array[String] = []
	for raw_id in seen:
		result.append(String(raw_id))
	result.sort()
	return result


static func _array_set(value: Array) -> Dictionary:
	var result := {}
	for raw_value in value:
		result[String(raw_value)] = true
	return result


static func _sorted_unique_slugs(value: Array) -> bool:
	var previous := ""
	for i in value.size():
		if typeof(value[i]) != TYPE_STRING or not _slug_valid(String(value[i])) \
				or (i > 0 and String(value[i]) <= previous):
			return false
		previous = String(value[i])
	return true


static func _sorted_unique_subset(value: Array, allowed: Dictionary) -> bool:
	var previous := ""
	for i in value.size():
		if typeof(value[i]) != TYPE_STRING or not allowed.has(String(value[i])) \
				or (i > 0 and String(value[i]) <= previous):
			return false
		previous = String(value[i])
	return true


static func _bounded_int(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		var integer := int(value)
		return integer >= minimum and integer <= maximum
	if typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number == floor(number) \
		and number >= float(minimum) and number <= float(maximum) \
		and absf(number) <= float(MAX_SAFE_JSON_INT)


static func _root_seed_from_token(token: String) -> Array:
	if not token.begins_with("i64:"):
		return []
	var number_text := token.substr(4)
	if not _canonical_i64(number_text):
		return []
	return [int(number_text)]


static func _canonical_i64(value: String) -> bool:
	if value == "0":
		return true
	if value.is_empty() or value == "-0" or value.begins_with("+") \
			or (value.begins_with("0") and value.length() > 1):
		return false
	var negative := value.begins_with("-")
	var digits := value.substr(1) if negative else value
	if digits.is_empty() or (digits.begins_with("0") and digits.length() > 1):
		return false
	for index in digits.length():
		var code := digits.unicode_at(index)
		if code < 48 or code > 57:
			return false
	var limit := "9223372036854775808" if negative else "9223372036854775807"
	return digits.length() < limit.length() or (digits.length() == limit.length() and digits <= limit)


static func _slug_valid(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		var valid := code >= 97 and code <= 122 or code >= 48 and code <= 57 \
			or (index > 0 and (code == 45 or code == 95))
		if not valid:
			return false
	return true


static func _short_id_valid(value: String, prefix: String) -> bool:
	return value.begins_with(prefix) and _lower_hex_valid(value.substr(prefix.length()), 16)


static func _seed_token_valid(value: String) -> bool:
	return value.begins_with("s63:") and _lower_hex_valid(value.substr(4), 16) \
		and value.substr(4, 1).hex_to_int() <= 7


static func _receipt_token_valid(value: String) -> bool:
	return value.begins_with("sha256:") and _lower_hex_valid(value.substr(7), 64)


static func _lower_hex_valid(value: String, width: int) -> bool:
	if value.length() != width:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57 or code >= 97 and code <= 102):
			return false
	return true


static func _string_if(value: Variant) -> String:
	return String(value) if typeof(value) == TYPE_STRING else ""


static func _exact_keys(data: Dictionary, required: Array) -> bool:
	if data.size() != required.size():
		return false
	for raw_key in data:
		if typeof(raw_key) != TYPE_STRING or String(raw_key) not in required:
			return false
	return true


static func _sha256_hex(text: String) -> String:
	if text == "":
		return ""
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
			if not is_finite(number) or number != floor(number) \
					or absf(number) > float(MAX_SAFE_JSON_INT):
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
