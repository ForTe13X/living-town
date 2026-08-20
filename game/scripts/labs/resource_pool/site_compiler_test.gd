extends Node

const Model = preload("res://scripts/labs/resource_pool/SiteBlueprintModel.gd")
const Routes = preload("res://scripts/labs/resource_pool/RegionRouteModel.gd")
const Address = preload("res://scripts/labs/resource_pool/ScaleAddress.gd")
const MapTileModel = preload("res://scripts/labs/MapTileLabModel.gd")

const ROOT_SEED := 260814
const AMPLE_RESOURCE := 1000000
const SITE_KEYS := [
	"ash_market", "cinder_crossing", "orra_relay", "redglass_quarry",
	"saint_vey_clinic", "dunlin_homestead",
]
const EXPECTED_KINDS := {
	"ash_market": "ruins",
	"cinder_crossing": "haven",
	"orra_relay": "relay",
	"redglass_quarry": "quarry",
	"saint_vey_clinic": "clinic",
	"dunlin_homestead": "farm",
}
const ORACLE_WALKABLE := [0, 1, 2, 4, 6, 8, 11]
const SCAR_FIELDS := [
	"depleted_loot_ids", "neutralized_threat_ids", "revealed_building_ids",
	"destroyed_prop_ids",
]

var _fails: int = 0
var _checks: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	print("  %s %s%s" % [
		"PASS" if condition else "FAIL", label,
		("  " + detail if detail != "" else ""),
	])
	if not condition:
		_fails += 1


func _ready() -> void:
	print("=== RP-0004 tile-to-local site compiler contract ===")
	var atlas: Dictionary = Routes.make_atlas(ROOT_SEED)
	var other_atlas: Dictionary = Routes.make_atlas(ROOT_SEED + 1)
	_check("source atlases validate", Routes.validate_atlas(atlas).is_empty()
		and Routes.validate_atlas(other_atlas).is_empty())
	_check("model declares no mutable static cache fields",
		_model_declares_no_static_cache())
	_check("site cell codes 0 through 9 remain MapTileLab.Cell compatible",
		_cell_code_compatibility_exact())

	var promises: Dictionary = {}
	var blueprints: Dictionary = {}
	var kinds_seen: Dictionary = {}
	var layouts_seen: Dictionary = {}
	var blueprint_ids: Dictionary = {}
	var all_compile: bool = true
	var all_json_safe: bool = true
	var all_geometry: bool = true
	var all_identity: bool = true
	var all_seed_receipts: bool = true
	var all_stable_ids: bool = true
	for raw_site_key in SITE_KEYS:
		var site_key: String = String(raw_site_key)
		var promise: Dictionary = Model.make_site_promise(atlas, site_key)
		var blueprint: Dictionary = Model.compile_site(promise)
		promises[site_key] = promise
		blueprints[site_key] = blueprint
		var valid: bool = not promise.is_empty() and not blueprint.is_empty() \
			and Model.validate_site_promise(promise).is_empty() \
			and Model.validate_blueprint(promise, blueprint).is_empty()
		all_compile = all_compile and valid
		if not valid:
			print("SITE_FIXTURE=%s INVALID" % site_key)
			continue
		var kind: String = String(blueprint.get("site_kind", ""))
		var layout_key: String = String(blueprint.get("layout_key", ""))
		var blueprint_id: String = String(blueprint.get("blueprint_id", ""))
		kinds_seen[kind] = true
		layouts_seen[layout_key] = true
		blueprint_ids[blueprint_id] = true
		all_json_safe = all_json_safe and _json_authority_safe(promise) \
			and _json_authority_safe(blueprint)
		var geometry: Dictionary = _independent_geometry_report(blueprint)
		all_geometry = all_geometry and bool(geometry.get("ok", false))
		all_identity = all_identity and _blueprint_identity_exact(promise, blueprint)
		all_seed_receipts = all_seed_receipts and _seed_receipts_exact(promise, blueprint)
		all_stable_ids = all_stable_ids and _stable_entity_ids_exact(blueprint)
		print("SITE_FIXTURE=%s kind=%s buildings=%d loot=%d threats=%d reachable=%d" % [
			site_key, kind, (blueprint.get("buildings", []) as Array).size(),
			(blueprint.get("loot", []) as Array).size(),
			(blueprint.get("threats", []) as Array).size(),
			int(geometry.get("reachable", 0)),
		])
	_check("all six authored archetypes compile and validate", all_compile
		and kinds_seen.size() == 6 and layouts_seen.size() == 6
		and blueprint_ids.size() == 6)
	_check("all blueprint authority is recursively JSON-native and integer-only", all_json_safe)
	_check("independent BFS, inferred rooms, doors, and entity legality pass every archetype",
		all_geometry)
	_check("site, cell, and stable entity identities bind to the canonical address tree",
		all_identity)
	_check("every blueprint carries three exact, distinct ScaleAddress stream receipts",
		all_seed_receipts)
	_check("entity IDs derive from semantic material, not array ordinals, and serialize sorted",
		all_stable_ids)

	var ash_promise: Dictionary = promises.get("ash_market", {})
	var ash_blueprint: Dictionary = blueprints.get("ash_market", {})
	var ash_again: Dictionary = Model.compile_site(Model.make_site_promise(atlas, "ash_market"))
	var other_promise: Dictionary = Model.make_site_promise(other_atlas, "ash_market")
	var other_blueprint: Dictionary = Model.compile_site(other_promise)
	_check("same root, site, and compiler recompute exact blueprint bytes",
		Model.canonical_json(ash_blueprint) == Model.canonical_json(ash_again))
	_check("different root seed separates promise and blueprint receipts without renaming the site",
		String(ash_promise.get("site_id", "")) == String(other_promise.get("site_id", ""))
		and String(ash_promise.get("promise_receipt", ""))
			!= String(other_promise.get("promise_receipt", ""))
		and String(ash_blueprint.get("blueprint_receipt", ""))
			!= String(other_blueprint.get("blueprint_receipt", "")))
	_check("layout, population, and clutter seed streams are domain-separated",
		_streams_are_separate(ash_promise))
	_check("negative axial tile and local-cell parent chains roundtrip canonically",
		_negative_address_chain_exact(ash_promise, ash_blueprint))

	var cinder_promise: Dictionary = promises.get("cinder_crossing", {})
	var cinder_blueprint: Dictionary = blueprints.get("cinder_crossing", {})
	var cinder_again_bytes: String = Model.canonical_json(cinder_blueprint)
	var initial_state: Dictionary = Model.make_initial_state(cinder_promise, cinder_blueprint)
	var initial_checkpoint: String = String(initial_state.get("state_receipt", ""))
	_check("initial durable state is valid, idle, and blueprint-free",
		Model.validate_state_snapshot(cinder_promise, cinder_blueprint, initial_state).is_empty()
		and _blueprint_state_separated(cinder_blueprint, initial_state))

	var arrived: Dictionary = _route_fixture(atlas, "ash_market", "cinder_crossing",
		"arrival-valid", true)
	var arrival_evidence: Dictionary = _arrival_from_fixture(cinder_promise, atlas, arrived)
	var arrival_again: Dictionary = _arrival_from_fixture(cinder_promise, atlas, arrived)
	_check("same arrived route and site recompute exact arrival evidence",
		not arrival_evidence.is_empty()
		and Model.canonical_json(arrival_evidence) == Model.canonical_json(arrival_again)
		and Model.validate_arrival_evidence(
			cinder_promise, atlas, arrived.get("atlas_state", {}), arrived.get("plan", {}),
			arrived.get("journey", {}), arrived.get("route_receipt", {}),
			String(arrived.get("accepted_journey_state_receipt", "")),
			arrival_evidence).is_empty())

	var traveling: Dictionary = _route_fixture(atlas, "ash_market", "cinder_crossing",
		"arrival-traveling", false)
	var wrong_tile: Dictionary = _route_fixture(atlas, "ash_market", "orra_relay",
		"arrival-wrong-tile", true)
	_check("traveling and wrong-tile routes cannot admit the site",
		_arrival_from_fixture(cinder_promise, atlas, traveling).is_empty()
		and _arrival_from_fixture(cinder_promise, atlas, wrong_tile).is_empty())

	var other_root_arrived: Dictionary = _route_fixture(
		other_atlas, "ash_market", "cinder_crossing", "arrival-wrong-root", true)
	_check("arrival evidence binds the promise to the exact root atlas receipt",
		_arrival_from_fixture(cinder_promise, other_atlas, other_root_arrived).is_empty())
	_check("self-rehashed forged arrival cannot outrun the owner journey checkpoint",
		_forged_arrived_rejected(
			cinder_promise, cinder_blueprint, initial_state, initial_checkpoint,
			atlas, arrived))

	var enter_a: Dictionary = _enter_from_fixture(
		cinder_promise, cinder_blueprint, initial_state, initial_checkpoint,
		atlas, arrived, "visit-a")
	var active_a: Dictionary = enter_a.get("after_state", {})
	var enter_b: Dictionary = _enter_from_fixture(
		cinder_promise, cinder_blueprint, initial_state, initial_checkpoint,
		atlas, arrived, "visit-b")
	_check("enter is an exact idle-to-active transition that preserves all scars",
		not enter_a.is_empty()
		and Model.validate_enter_transition(
			cinder_promise, cinder_blueprint, initial_state,
			initial_checkpoint, atlas,
			arrived.get("atlas_state", {}), arrived.get("plan", {}),
			arrived.get("journey", {}), arrived.get("route_receipt", {}),
			String(arrived.get("accepted_journey_state_receipt", "")),
			"visit-a", enter_a).is_empty()
		and Model.validate_state_snapshot(
			cinder_promise, cinder_blueprint, active_a).is_empty()
		and String(active_a.get("phase", "")) == "active"
		and _same_scars(initial_state, active_a))
	_check("different visit slots isolate admission receipts but never change the blueprint",
		not enter_b.is_empty()
		and String(enter_a.get("admission_receipt", ""))
			!= String(enter_b.get("admission_receipt", ""))
		and Model.canonical_json(cinder_blueprint) == cinder_again_bytes)
	_check("active-state re-entry and mixed visit admission both fail closed",
		_enter_from_fixture(
			cinder_promise, cinder_blueprint, active_a, initial_checkpoint,
			atlas, arrived, "visit-a").is_empty()
		and not Model.validate_enter_transition(
			cinder_promise, cinder_blueprint, initial_state,
			initial_checkpoint, atlas,
			arrived.get("atlas_state", {}), arrived.get("plan", {}),
			arrived.get("journey", {}), arrived.get("route_receipt", {}),
			String(arrived.get("accepted_journey_state_receipt", "")),
			"visit-b", enter_a).is_empty())

	var empty_delta: Dictionary = _make_delta(
		cinder_promise, cinder_blueprint, active_a, enter_a, initial_checkpoint,
		atlas, arrived,
		"visit-a", "retreated", 1,
		[], [], [], [])
	var empty_transition: Dictionary = _apply_delta(
		cinder_promise, cinder_blueprint, active_a, enter_a, initial_checkpoint,
		atlas, arrived,
		empty_delta)
	var after_empty: Dictionary = empty_transition.get("after_state", {})
	_check("empty-handed terminal resolve is a legal active-to-idle event",
		not empty_delta.is_empty() and not empty_transition.is_empty()
		and _validate_delta(cinder_promise, cinder_blueprint, active_a,
			enter_a, initial_checkpoint, atlas, arrived, empty_delta).is_empty()
		and _validate_resolve(cinder_promise, cinder_blueprint, active_a,
			enter_a, initial_checkpoint, atlas, arrived,
			empty_delta, empty_transition).is_empty()
		and String(after_empty.get("phase", "")) == "idle"
		and int(after_empty.get("revision", -1)) == 1
		and _same_scars(active_a, after_empty))
	_check("owner checkpoint rejects a valid but stale rollback candidate at enter and resolve",
		_checkpoint_rollback_rejected(
			cinder_promise, cinder_blueprint, initial_state, active_a, enter_a,
			after_empty, atlas, arrived, empty_delta))

	var enter_scar: Dictionary = _enter_from_fixture(
		cinder_promise, cinder_blueprint, after_empty,
		String(after_empty.get("state_receipt", "")), atlas, arrived, "visit-scar")
	var active_scar: Dictionary = enter_scar.get("after_state", {})
	var loot_id: String = _first_entity_id(cinder_blueprint, "loot")
	var threat_id: String = _first_entity_id(cinder_blueprint, "threats")
	var building_id: String = _first_entity_id(cinder_blueprint, "buildings")
	var prop_id: String = _first_destructible_prop_id(cinder_blueprint)
	var scar_delta: Dictionary = _make_delta(
		cinder_promise, cinder_blueprint, active_scar, enter_scar,
		String(after_empty.get("state_receipt", "")), atlas, arrived,
		"visit-scar", "collapsed", 7,
		[loot_id], [threat_id], [building_id], [prop_id])
	var scar_transition: Dictionary = _apply_delta(
		cinder_promise, cinder_blueprint, active_scar, enter_scar,
		String(after_empty.get("state_receipt", "")), atlas, arrived,
		scar_delta)
	var scar_state: Dictionary = scar_transition.get("after_state", {})
	_check("a typed collapse delta commits monotonic loot, threat, reveal, and destruction scars",
		not scar_transition.is_empty()
		and _scar_transition_exact(active_scar, scar_state,
			loot_id, threat_id, building_id, prop_id)
		and Model.canonical_json(cinder_blueprint) == cinder_again_bytes)
	_check("resolved delta replay cannot mutate the committed after-state",
		_apply_delta(cinder_promise, cinder_blueprint, scar_state,
			enter_scar, String(after_empty.get("state_receipt", "")),
			atlas, arrived, scar_delta).is_empty()
		and not _validate_resolve(cinder_promise, cinder_blueprint, scar_state,
			enter_scar, String(after_empty.get("state_receipt", "")), atlas,
			arrived, scar_delta, scar_transition).is_empty())

	var enter_repeat: Dictionary = _enter_from_fixture(
		cinder_promise, cinder_blueprint, scar_state,
		String(scar_state.get("state_receipt", "")), atlas, arrived, "visit-repeat")
	var repeat_active: Dictionary = enter_repeat.get("after_state", {})
	_check("a later visit cannot deplete an already committed scar again",
		_make_delta(cinder_promise, cinder_blueprint, repeat_active,
			enter_repeat, String(scar_state.get("state_receipt", "")), atlas,
			arrived, "visit-repeat", "extracted", 2,
			[loot_id], [threat_id], [building_id], [prop_id]).is_empty())

	var other_state: Dictionary = Model.make_initial_state(ash_promise, ash_blueprint)
	var mixed_after: Dictionary = enter_a.duplicate(true)
	mixed_after["after_state"] = enter_b.get("after_state", {})
	mixed_after["after_state_receipt"] = String(
		(enter_b.get("after_state", {}) as Dictionary).get("state_receipt", ""))
	mixed_after.erase("transition_receipt")
	mixed_after["transition_receipt"] = _receipt_for(mixed_after)
	_check("blueprint/state and enter-transition mix-and-match fail closed",
		not Model.validate_state_snapshot(cinder_promise, cinder_blueprint, other_state).is_empty()
		and not Model.validate_enter_transition(
			cinder_promise, cinder_blueprint, initial_state,
			initial_checkpoint, atlas,
			arrived.get("atlas_state", {}), arrived.get("plan", {}),
			arrived.get("journey", {}), arrived.get("route_receipt", {}),
			String(arrived.get("accepted_journey_state_receipt", "")),
			"visit-a", mixed_after).is_empty()
		and not _validate_delta(cinder_promise, cinder_blueprint,
			enter_b.get("after_state", {}), enter_b, initial_checkpoint,
			atlas, arrived,
			empty_delta).is_empty())

	_check("promise, blueprint, state, and transition rehash tampering is rejected",
		_semantic_tamper_rejected(
			cinder_promise, cinder_blueprint, initial_state, empty_delta,
			active_a, enter_a, initial_checkpoint, atlas, arrived, empty_transition))
	_check("a self-rehashed forged active snapshot cannot authorize resolve",
		_forged_active_rejected(
			cinder_promise, cinder_blueprint, active_a, enter_a,
			initial_checkpoint, atlas, arrived))
	_check("visit grammar, bounds, admission cancel, and MAX_VISITS cap are exact",
		_limits_and_grammar_rejected(
			cinder_promise, cinder_blueprint, initial_state, active_a, enter_a,
			scar_state, atlas, arrived))
	_check("delta validator rejects NaN, infinity, huge, fractional, and string numerics",
		_hostile_delta_numerics_rejected(
			cinder_promise, cinder_blueprint, active_a, enter_a, initial_checkpoint,
			atlas, arrived, empty_delta))

	_check("JSON and Variant roundtrips resume an active visit with exact output",
		_roundtrip_continuation_exact(
			cinder_promise, cinder_blueprint, active_scar, enter_scar,
			String(after_empty.get("state_receipt", "")), atlas, arrived,
			scar_delta, scar_transition))

	var receipt: Dictionary = Model.blueprint_receipt(cinder_promise, cinder_blueprint)
	var receipt_text: String = Model.canonical_receipt_json(
		cinder_promise, cinder_blueprint, receipt)
	_check("canonical blueprint receipt roundtrips and rejects a self-hashed false summary",
		_receipt_contract_exact(cinder_promise, cinder_blueprint, receipt, receipt_text))

	print("SITE_BLUEPRINT_RECEIPT=%s" % receipt_text)
	print("SITE_STATE_RECEIPT=%s" % String(scar_state.get("state_receipt", "")))
	print("SITE_TRANSITION_RECEIPT=%s" % String(
		scar_transition.get("transition_receipt", "")))
	print("site_compiler_test: %s (%d fail, %d checks)" % [
		"PASS" if _fails == 0 else "FAIL", _fails, _checks,
	])
	get_tree().quit(0 if _fails == 0 else 1)


func _route_fixture(atlas: Dictionary, origin_key: String, destination_key: String,
		slot: String, complete: bool) -> Dictionary:
	var atlas_state: Dictionary = Routes.make_initial_atlas_state(atlas)
	var origin: String = Routes.site_tile_id(atlas, origin_key)
	var destination: String = Routes.site_tile_id(atlas, destination_key)
	var plan: Dictionary = Routes.make_route_plan(
		atlas, atlas_state, origin, destination, "autumn", "safe", [], "",
		"site_%s" % slot)
	var journey: Dictionary = Routes.begin_journey(
		atlas, atlas_state, plan, slot, AMPLE_RESOURCE, AMPLE_RESOURCE)
	if plan.is_empty() or journey.is_empty():
		return {}
	if complete:
		var guard: int = (plan.get("path", []) as Array).size() + 1
		for _step in guard:
			if String(journey.get("phase", "")) != "traveling":
				break
			var transition: Dictionary = Routes.advance_one_leg(
				atlas, atlas_state, plan, journey)
			if transition.is_empty():
				return {}
			journey = transition.get("journey", {})
			atlas_state = transition.get("atlas_state", {})
	var route_receipt: Dictionary = Routes.route_receipt(atlas, atlas_state, plan, journey)
	return {
		"atlas_state": atlas_state,
		"plan": plan,
		"journey": journey,
		"route_receipt": route_receipt,
		"accepted_journey_state_receipt": String(journey.get("state_receipt", "")),
	}


func _arrival_from_fixture(promise: Dictionary, atlas: Dictionary,
		fixture: Dictionary) -> Dictionary:
	if fixture.is_empty():
		return {}
	return Model.make_arrival_evidence(
		promise, atlas, fixture.get("atlas_state", {}), fixture.get("plan", {}),
		fixture.get("journey", {}), fixture.get("route_receipt", {}),
		String(fixture.get("accepted_journey_state_receipt", "")))


func _forged_arrived_rejected(promise: Dictionary, blueprint: Dictionary,
		idle_state: Dictionary, accepted_idle_state_receipt: String,
		atlas: Dictionary, arrived_fixture: Dictionary) -> bool:
	if arrived_fixture.is_empty():
		return false
	var plan: Dictionary = arrived_fixture.get("plan", {})
	var real_arrived: Dictionary = arrived_fixture.get("journey", {})
	var initial_atlas_state: Dictionary = Routes.make_initial_atlas_state(atlas)
	var owner_traveling: Dictionary = Routes.begin_journey(
		atlas, initial_atlas_state, plan,
		String(real_arrived.get("journey_slot", "")),
		int(real_arrived.get("initial_supply_milli", -1)),
		int(real_arrived.get("initial_condition_milli", -1)))
	if owner_traveling.is_empty() or String(owner_traveling.get("phase", "")) != "traveling":
		return false
	var forged_journey: Dictionary = real_arrived.duplicate(true)
	forged_journey["previous_leg_receipt"] = "sha256:" + "ab".repeat(32)
	forged_journey.erase("state_receipt")
	forged_journey["state_receipt"] = _route_receipt_for(forged_journey)
	var final_atlas_state: Dictionary = arrived_fixture.get("atlas_state", {})
	var forged_route_receipt: Dictionary = Routes.route_receipt(
		atlas, final_atlas_state, plan, forged_journey)
	var forged_fixture: Dictionary = arrived_fixture.duplicate(true)
	forged_fixture["journey"] = forged_journey
	forged_fixture["route_receipt"] = forged_route_receipt
	forged_fixture["accepted_journey_state_receipt"] = String(
		owner_traveling.get("state_receipt", ""))
	return String(real_arrived.get("phase", "")) == "arrived" \
		and String(forged_journey.get("state_receipt", "")) \
			!= String(owner_traveling.get("state_receipt", "")) \
		and Routes.validate_journey(
			atlas, final_atlas_state, plan, forged_journey).is_empty() \
		and Routes.validate_route_receipt(
			atlas, final_atlas_state, plan, forged_journey,
			forged_route_receipt).is_empty() \
		and _arrival_from_fixture(promise, atlas, forged_fixture).is_empty() \
		and _enter_from_fixture(
			promise, blueprint, idle_state, accepted_idle_state_receipt,
			atlas, forged_fixture, "visit-forged-route").is_empty()


func _enter_from_fixture(promise: Dictionary, blueprint: Dictionary,
		before_state: Dictionary, expected_before_state_receipt: String,
		atlas: Dictionary, fixture: Dictionary, visit_id: String) -> Dictionary:
	if fixture.is_empty():
		return {}
	return Model.enter_site(
		promise, blueprint, before_state, expected_before_state_receipt, atlas,
		fixture.get("atlas_state", {}),
		fixture.get("plan", {}), fixture.get("journey", {}),
		fixture.get("route_receipt", {}),
		String(fixture.get("accepted_journey_state_receipt", "")), visit_id)


func _make_delta(promise: Dictionary, blueprint: Dictionary,
		active_state: Dictionary, enter_transition: Dictionary,
		accepted_idle_state_receipt: String, atlas: Dictionary,
		fixture: Dictionary, visit_id: String, resolution: String, elapsed_turns: int,
		depleted_loot_ids: Array, neutralized_threat_ids: Array,
		revealed_building_ids: Array, destroyed_prop_ids: Array) -> Dictionary:
	return Model.make_visit_delta(
		promise, blueprint, active_state, enter_transition,
		accepted_idle_state_receipt, atlas,
		fixture.get("atlas_state", {}), fixture.get("plan", {}),
		fixture.get("journey", {}), fixture.get("route_receipt", {}),
		String(fixture.get("accepted_journey_state_receipt", "")),
		visit_id, resolution, elapsed_turns, depleted_loot_ids,
		neutralized_threat_ids, revealed_building_ids, destroyed_prop_ids)


func _apply_delta(promise: Dictionary, blueprint: Dictionary,
		active_state: Dictionary, enter_transition: Dictionary,
		accepted_idle_state_receipt: String, atlas: Dictionary,
		fixture: Dictionary, delta: Dictionary) -> Dictionary:
	return Model.apply_visit_delta(
		promise, blueprint, active_state, enter_transition,
		accepted_idle_state_receipt, atlas,
		fixture.get("atlas_state", {}), fixture.get("plan", {}),
		fixture.get("journey", {}), fixture.get("route_receipt", {}),
		String(fixture.get("accepted_journey_state_receipt", "")), delta)


func _validate_delta(promise: Dictionary, blueprint: Dictionary,
		active_state: Dictionary, enter_transition: Dictionary,
		accepted_idle_state_receipt: String, atlas: Dictionary,
		fixture: Dictionary, delta: Dictionary) -> Array[String]:
	return Model.validate_visit_delta(
		promise, blueprint, active_state, enter_transition,
		accepted_idle_state_receipt, atlas,
		fixture.get("atlas_state", {}), fixture.get("plan", {}),
		fixture.get("journey", {}), fixture.get("route_receipt", {}),
		String(fixture.get("accepted_journey_state_receipt", "")), delta)


func _validate_resolve(promise: Dictionary, blueprint: Dictionary,
		active_state: Dictionary, enter_transition: Dictionary,
		accepted_idle_state_receipt: String, atlas: Dictionary,
		fixture: Dictionary, delta: Dictionary, transition: Dictionary) -> Array[String]:
	return Model.validate_state_transition(
		promise, blueprint, active_state, enter_transition,
		accepted_idle_state_receipt, atlas,
		fixture.get("atlas_state", {}), fixture.get("plan", {}),
		fixture.get("journey", {}), fixture.get("route_receipt", {}),
		String(fixture.get("accepted_journey_state_receipt", "")),
		delta, transition)


func _model_declares_no_static_cache() -> bool:
	var model_script: Script = Model
	var source: String = model_script.source_code
	for raw_line in source.split("\n"):
		var line: String = String(raw_line).strip_edges().to_lower()
		if line.begins_with("static var") and "cache" in line:
			return false
	return true


func _cell_code_compatibility_exact() -> bool:
	return Model.CELL_GROUND == MapTileModel.Cell.GROUND \
		and Model.CELL_ROAD == MapTileModel.Cell.ROAD \
		and Model.CELL_FLOOR == MapTileModel.Cell.FLOOR \
		and Model.CELL_WALL == MapTileModel.Cell.WALL \
		and Model.CELL_DOOR == MapTileModel.Cell.DOOR \
		and Model.CELL_WINDOW == MapTileModel.Cell.WINDOW \
		and Model.CELL_RUBBLE == MapTileModel.Cell.RUBBLE \
		and Model.CELL_WATER == MapTileModel.Cell.WATER \
		and Model.CELL_EXIT == MapTileModel.Cell.EXIT \
		and Model.CELL_TREE == MapTileModel.Cell.TREE \
		and Model.CELL_FENCE == 10 and Model.CELL_CROP == 11 \
		and Model.CELL_PIT == 12


func _streams_are_separate(promise: Dictionary) -> bool:
	var root_text: String = String(promise.get("root_seed", ""))
	if not root_text.begins_with("i64:"):
		return false
	var site: Dictionary = Address.parse_id(String(promise.get("site_id", "")))
	var root_seed: int = int(root_text.substr(4))
	var tokens: Dictionary = {}
	for purpose in ["site-layout", "site-population", "site-clutter"]:
		var token: String = Address.seed_token_for(root_seed, site, String(purpose))
		if token == "" or tokens.has(token):
			return false
		tokens[token] = true
	return tokens.size() == 3


func _seed_receipts_exact(promise: Dictionary, blueprint: Dictionary) -> bool:
	var receipts_value: Variant = blueprint.get("seed_receipts")
	if not (receipts_value is Dictionary):
		return false
	var receipts: Dictionary = receipts_value
	if receipts.size() != 3:
		return false
	var purposes: Dictionary = {
		"layout": "site-layout",
		"population": "site-population",
		"clutter": "site-clutter",
	}
	var tokens: Dictionary = {}
	for raw_stream in purposes:
		var stream: String = String(raw_stream)
		var receipt_value: Variant = receipts.get(stream)
		if not (receipt_value is Dictionary) \
				or not Address.validate_receipt(receipt_value).is_empty():
			return false
		var receipt: Dictionary = receipt_value
		if String(receipt.get("address", "")) != String(promise.get("site_id", "")) \
				or String(receipt.get("root_seed", "")) != String(promise.get("root_seed", "")) \
				or String(receipt.get("purpose", "")) != String(purposes[stream]):
			return false
		var token: String = String(receipt.get("seed_token", ""))
		if token == "" or tokens.has(token):
			return false
		tokens[token] = true
	return tokens.size() == 3


func _stable_entity_ids_exact(blueprint: Dictionary) -> bool:
	var site_id: String = String(blueprint.get("site_id", ""))
	for raw_section in ["buildings", "props", "loot", "threats"]:
		var section: String = String(raw_section)
		var prior_id: String = ""
		for raw_entity in blueprint.get(section, []) as Array:
			if not (raw_entity is Dictionary):
				return false
			var entity: Dictionary = raw_entity
			var entity_id: String = String(entity.get("id", ""))
			if prior_id != "" and entity_id <= prior_id:
				return false
			prior_id = entity_id
			var material: Array = []
			var prefix: String = ""
			if section == "buildings":
				prefix = "sbld1:"
				material = [site_id, "building", String(entity.get("label", "")),
					String(entity.get("kind", "")), entity.get("rect", []),
					String(entity.get("entrance_side", ""))]
				var prior_door: String = ""
				for raw_door in entity.get("doors", []) as Array:
					var door: Dictionary = raw_door
					var cell_id: String = String(door.get("cell_id", ""))
					if prior_door != "" and cell_id <= prior_door:
						return false
					prior_door = cell_id
			elif section == "props":
				prefix = "sprp1:"
				material = [site_id, "prop", String(entity.get("kind", "")),
					String(entity.get("label", "")), entity.get("pos", [])]
			elif section == "loot":
				prefix = "sloot1:"
				material = [site_id, "loot", String(entity.get("kind", "")),
					String(entity.get("label", "")), entity.get("pos", []),
					Model.CONTENT_REVISION]
			else:
				prefix = "sthr1:"
				material = [site_id, "threat", String(entity.get("kind", "")),
					entity.get("pos", []), Model.CONTENT_REVISION]
			var expected_id: String = prefix \
				+ _sha256_hex(Model.canonical_json(material)).substr(0, 16)
			if entity_id != expected_id:
				return false
	return true


func _negative_address_chain_exact(promise: Dictionary, blueprint: Dictionary) -> bool:
	var site_id: String = String(promise.get("site_id", ""))
	var site: Dictionary = Address.parse_id(site_id)
	var tile: Dictionary = Address.parent(site)
	var region: Dictionary = Address.parent(tile)
	var entry: Dictionary = blueprint.get("entry", {})
	var cell: Dictionary = Address.parse_id(String(entry.get("cell_id", "")))
	return Address.coordinate(tile, "tile") == Vector2i(7, -1) \
		and Address.region_of(tile) == Vector2i(0, -1) \
		and Address.local_tile_of(tile) == Vector2i(7, 15) \
		and Address.canonical_id(tile) == String(promise.get("tile_id", "")) \
		and Address.canonical_id(Address.parent(cell)) == site_id \
		and Address.level_of(region) == Address.LEVEL_REGION \
		and Address.level_of(Address.parent(region)) == Address.LEVEL_PLANET \
		and Address.canonical_id(Address.parse_id(site_id)) == site_id


func _independent_geometry_report(blueprint: Dictionary) -> Dictionary:
	if not _grid_shape_valid(blueprint):
		return {"ok": false, "reachable": 0}
	var blocked: Dictionary = _blocking_cells(blueprint)
	var entry: Vector2i = _dto_pos(blueprint.get("entry", {}))
	var reached: Dictionary = _oracle_reachable(blueprint, entry, blocked)
	var ok: bool = not reached.is_empty()
	var extraction: Vector2i = _dto_pos(blueprint.get("extraction", {}))
	ok = ok and reached.has(_coord_key(extraction))
	var occupied: Dictionary = {}
	ok = ok and _claim_position(occupied, entry, "entry")
	ok = ok and _claim_position(occupied, extraction, "extraction")
	var building_rects: Array = []
	for raw_building in blueprint.get("buildings", []) as Array:
		if not (raw_building is Dictionary):
			return {"ok": false, "reachable": reached.size()}
		var building: Dictionary = raw_building
		ok = ok and _building_rooms_exact(blueprint, building, blocked, reached)
		var rect: Array = building.get("rect", [])
		for raw_other in building_rects:
			ok = ok and not _rects_overlap(rect, raw_other as Array)
		building_rects.append(rect)
	for section in ["props", "loot", "threats"]:
		for raw_entity in blueprint.get(String(section), []) as Array:
			if not (raw_entity is Dictionary):
				return {"ok": false, "reachable": reached.size()}
			var entity: Dictionary = raw_entity
			var pos: Vector2i = _dto_pos(entity)
			ok = ok and _in_blueprint(blueprint, pos)
			if String(section) == "props" and bool(entity.get("blocking", false)):
				ok = ok and _oracle_cell(blueprint, pos) in ORACLE_WALKABLE
				ok = ok and blocked.has(_coord_key(pos))
				ok = ok and _has_reachable_neighbor(pos, reached)
			else:
				ok = ok and _oracle_walkable(blueprint, pos, blocked)
				ok = ok and reached.has(_coord_key(pos))
			ok = ok and _claim_position(occupied, pos, String(section))
	var topology: Dictionary = blueprint.get("topology", {})
	ok = ok and int(topology.get("reachable_cells", -1)) == reached.size()
	ok = ok and bool(topology.get("all_reachable", false))
	return {"ok": ok, "reachable": reached.size()}


func _building_rooms_exact(blueprint: Dictionary, building: Dictionary,
		blocked: Dictionary, reached: Dictionary) -> bool:
	var rect: Array = building.get("rect", [])
	if rect.size() != 4:
		return false
	var x: int = int(rect[0])
	var y: int = int(rect[1])
	var width: int = int(rect[2])
	var height: int = int(rect[3])
	var door_cells: Dictionary = {}
	var exterior_count: int = 0
	for raw_door in building.get("doors", []) as Array:
		if not (raw_door is Dictionary):
			return false
		var door: Dictionary = raw_door
		var pos: Vector2i = _dto_pos(door)
		if _oracle_cell(blueprint, pos) != 4 or not reached.has(_coord_key(pos)):
			return false
		var on_boundary: bool = pos.x == x or pos.x == x + width - 1 \
			or pos.y == y or pos.y == y + height - 1
		if String(door.get("role", "")) == "exterior":
			exterior_count += 1
			if not on_boundary:
				return false
		elif String(door.get("role", "")) == "interior":
			if on_boundary:
				return false
		else:
			return false
		door_cells[_coord_key(pos)] = true
	if exterior_count != 1:
		return false
	var room_cells: Dictionary = {}
	for py in range(y + 1, y + height - 1):
		for px in range(x + 1, x + width - 1):
			var pos: Vector2i = Vector2i(px, py)
			if _oracle_walkable(blueprint, pos, blocked) and not door_cells.has(_coord_key(pos)):
				room_cells[_coord_key(pos)] = pos
	if room_cells.is_empty():
		return false
	var remaining: Dictionary = room_cells.duplicate(true)
	var room_count: int = 0
	while not remaining.is_empty():
		var first_key: String = String(remaining.keys()[0])
		var start: Vector2i = remaining[first_key]
		var queue: Array[Vector2i] = [start]
		remaining.erase(first_key)
		var head: int = 0
		var touches_door: bool = false
		while head < queue.size():
			var current: Vector2i = queue[head]
			head += 1
			if not reached.has(_coord_key(current)):
				return false
			for direction in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
				var next: Vector2i = current + direction
				var key: String = _coord_key(next)
				if door_cells.has(key):
					touches_door = true
				elif remaining.has(key):
					queue.append(next)
					remaining.erase(key)
		if not touches_door:
			return false
		room_count += 1
	return room_count >= 1


func _blueprint_identity_exact(promise: Dictionary, blueprint: Dictionary) -> bool:
	var site_id: String = String(promise.get("site_id", ""))
	var site: Dictionary = Address.parse_id(site_id)
	if site.is_empty() or Address.level_of(site) != Address.LEVEL_SITE \
			or Address.canonical_id(Address.parent(site)) != String(promise.get("tile_id", "")):
		return false
	var ids: Dictionary = {}
	for section in ["buildings", "props", "loot", "threats"]:
		for raw_entity in blueprint.get(String(section), []) as Array:
			var entity: Dictionary = raw_entity
			var entity_id: String = String(entity.get("id", ""))
			if entity_id == "" or ids.has(entity_id):
				return false
			ids[entity_id] = true
	for anchor_key in ["entry", "extraction"]:
		if not _cell_binding_exact(site_id, blueprint.get(String(anchor_key), {})):
			return false
	for section in ["props", "loot", "threats"]:
		for raw_entity in blueprint.get(String(section), []) as Array:
			if not _cell_binding_exact(site_id, raw_entity as Dictionary):
				return false
	for raw_building in blueprint.get("buildings", []) as Array:
		var building: Dictionary = raw_building
		for raw_door in building.get("doors", []) as Array:
			if not _cell_binding_exact(site_id, raw_door as Dictionary):
				return false
	return true


func _cell_binding_exact(site_id: String, value: Dictionary) -> bool:
	var cell_id: String = String(value.get("cell_id", ""))
	var cell: Dictionary = Address.parse_id(cell_id)
	var pos: Vector2i = _dto_pos(value)
	return not cell.is_empty() and Address.level_of(cell) == Address.LEVEL_CELL \
		and Address.canonical_id(cell) == cell_id \
		and Address.canonical_id(Address.parent(cell)) == site_id \
		and Address.coordinate(cell, "cell") == pos


func _grid_shape_valid(blueprint: Dictionary) -> bool:
	var width: int = int(blueprint.get("width", -1))
	var height: int = int(blueprint.get("height", -1))
	return width == 32 and height == 22 \
		and (blueprint.get("cells", []) as Array).size() == width * height


func _blocking_cells(blueprint: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw_prop in blueprint.get("props", []) as Array:
		var prop: Dictionary = raw_prop
		if bool(prop.get("blocking", false)):
			result[_coord_key(_dto_pos(prop))] = true
	return result


func _oracle_reachable(blueprint: Dictionary, start: Vector2i,
		blocked: Dictionary) -> Dictionary:
	var reached: Dictionary = {}
	if not _oracle_walkable(blueprint, start, blocked):
		return reached
	var queue: Array[Vector2i] = [start]
	reached[_coord_key(start)] = true
	var head: int = 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		for direction in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var next: Vector2i = current + direction
			var key: String = _coord_key(next)
			if not reached.has(key) and _oracle_walkable(blueprint, next, blocked):
				reached[key] = true
				queue.append(next)
	return reached


func _oracle_walkable(blueprint: Dictionary, pos: Vector2i,
		blocked: Dictionary) -> bool:
	return _in_blueprint(blueprint, pos) \
		and _oracle_cell(blueprint, pos) in ORACLE_WALKABLE \
		and not blocked.has(_coord_key(pos))


func _oracle_cell(blueprint: Dictionary, pos: Vector2i) -> int:
	if not _in_blueprint(blueprint, pos):
		return 3
	var width: int = int(blueprint.get("width", 0))
	return int((blueprint.get("cells", []) as Array)[pos.y * width + pos.x])


func _in_blueprint(blueprint: Dictionary, pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 \
		and pos.x < int(blueprint.get("width", 0)) \
		and pos.y < int(blueprint.get("height", 0))


func _dto_pos(value: Variant) -> Vector2i:
	if not (value is Dictionary) or not ((value as Dictionary).get("pos") is Array):
		return Vector2i(-999999, -999999)
	var values: Array = (value as Dictionary).get("pos", [])
	if values.size() != 2:
		return Vector2i(-999999, -999999)
	return Vector2i(int(values[0]), int(values[1]))


func _claim_position(occupied: Dictionary, pos: Vector2i, label: String) -> bool:
	var key: String = _coord_key(pos)
	if occupied.has(key):
		return false
	occupied[key] = label
	return true


func _has_reachable_neighbor(pos: Vector2i, reached: Dictionary) -> bool:
	for direction in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		if reached.has(_coord_key(pos + direction)):
			return true
	return false


func _coord_key(pos: Vector2i) -> String:
	return "%d,%d" % [pos.x, pos.y]


func _rects_overlap(left: Array, right: Array) -> bool:
	if left.size() != 4 or right.size() != 4:
		return true
	return int(left[0]) < int(right[0]) + int(right[2]) \
		and int(left[0]) + int(left[2]) > int(right[0]) \
		and int(left[1]) < int(right[1]) + int(right[3]) \
		and int(left[1]) + int(left[3]) > int(right[1])


func _blueprint_state_separated(blueprint: Dictionary, state: Dictionary) -> bool:
	var blueprint_forbidden: Dictionary = {
		"taken": true, "dead": true, "revealed": true, "visit_id": true,
		"revision": true, "state_receipt": true,
	}
	for forbidden in ["cells", "buildings", "props", "loot", "threats", "topology",
			"entry", "extraction", "layout_key", "seed_token"]:
		if state.has(String(forbidden)):
			return false
	return not _contains_forbidden_key(blueprint, blueprint_forbidden)


func _contains_forbidden_key(value: Variant, forbidden: Dictionary) -> bool:
	if value is Dictionary:
		for raw_key in value as Dictionary:
			var key: String = String(raw_key)
			if forbidden.has(key) or _contains_forbidden_key((value as Dictionary)[raw_key], forbidden):
				return true
	elif value is Array:
		for item in value as Array:
			if _contains_forbidden_key(item, forbidden):
				return true
	return false


func _json_authority_safe(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_ARRAY:
			for item in value as Array:
				if not _json_authority_safe(item):
					return false
			return true
		TYPE_DICTIONARY:
			for raw_key in value as Dictionary:
				if typeof(raw_key) != TYPE_STRING \
						or not _json_authority_safe((value as Dictionary)[raw_key]):
					return false
			return true
	return false


func _same_scars(left: Dictionary, right: Dictionary) -> bool:
	for raw_field in SCAR_FIELDS:
		var field: String = String(raw_field)
		if Model.canonical_json(left.get(field, [])) != Model.canonical_json(right.get(field, [])):
			return false
	return true


func _scar_transition_exact(before: Dictionary, after: Dictionary, loot_id: String,
		threat_id: String, building_id: String, prop_id: String) -> bool:
	if String(after.get("phase", "")) != "idle" \
			or int(after.get("revision", -1)) != int(before.get("revision", -2)) + 1:
		return false
	var expected: Dictionary = {
		"depleted_loot_ids": loot_id,
		"neutralized_threat_ids": threat_id,
		"revealed_building_ids": building_id,
		"destroyed_prop_ids": prop_id,
	}
	for raw_field in expected:
		var field: String = String(raw_field)
		var before_values: Array = before.get(field, [])
		var after_values: Array = after.get(field, [])
		if after_values.size() != before_values.size() + 1 \
				or String(expected[field]) not in after_values:
			return false
	return String(after.get("last_resolution", "")) == "collapsed"


func _first_entity_id(blueprint: Dictionary, section: String) -> String:
	var entities: Array = blueprint.get(section, [])
	if entities.is_empty() or not (entities[0] is Dictionary):
		return ""
	return String((entities[0] as Dictionary).get("id", ""))


func _first_destructible_prop_id(blueprint: Dictionary) -> String:
	for raw_prop in blueprint.get("props", []) as Array:
		var prop: Dictionary = raw_prop
		if bool(prop.get("destructible", false)):
			return String(prop.get("id", ""))
	return ""


func _checkpoint_rollback_rejected(promise: Dictionary, blueprint: Dictionary,
		rolled_back_idle: Dictionary, rolled_back_active: Dictionary,
		enter_transition: Dictionary, accepted_current_idle: Dictionary,
		atlas: Dictionary, fixture: Dictionary, prior_delta: Dictionary) -> bool:
	var trusted_current_receipt: String = String(
		accepted_current_idle.get("state_receipt", ""))
	var rolled_back_enter: Dictionary = _enter_from_fixture(
		promise, blueprint, rolled_back_idle, trusted_current_receipt,
		atlas, fixture, "visit-a")
	var mismatched_delta: Dictionary = _make_delta(
		promise, blueprint, rolled_back_active, enter_transition,
		trusted_current_receipt, atlas, fixture,
		"visit-a", "retreated", 1, [], [], [], [])
	return trusted_current_receipt != "" and rolled_back_enter.is_empty() \
		and not Model.validate_enter_transition(
			promise, blueprint, rolled_back_idle, trusted_current_receipt, atlas,
			fixture.get("atlas_state", {}), fixture.get("plan", {}),
			fixture.get("journey", {}), fixture.get("route_receipt", {}),
			String(fixture.get("accepted_journey_state_receipt", "")),
			"visit-a", enter_transition).is_empty() \
		and mismatched_delta.is_empty() \
		and not _validate_delta(
			promise, blueprint, rolled_back_active, enter_transition,
			trusted_current_receipt, atlas, fixture, prior_delta).is_empty()


func _hostile_delta_numerics_rejected(promise: Dictionary, blueprint: Dictionary,
		active_state: Dictionary, enter_transition: Dictionary,
		accepted_idle_state_receipt: String, atlas: Dictionary,
		fixture: Dictionary, valid_delta: Dictionary) -> bool:
	if valid_delta.is_empty():
		return false
	var hostile_values: Array = [NAN, INF, -INF, 1.0e100, 0.5, "1"]
	for raw_value in hostile_values:
		var hostile_value: Variant = raw_value
		var bad_elapsed: Dictionary = valid_delta.duplicate(true)
		bad_elapsed["elapsed_turns"] = hostile_value
		if _validate_delta(
				promise, blueprint, active_state, enter_transition,
				accepted_idle_state_receipt, atlas, fixture, bad_elapsed).is_empty():
			return false
		var bad_revision: Dictionary = valid_delta.duplicate(true)
		bad_revision["expected_revision"] = hostile_value
		if _validate_delta(
				promise, blueprint, active_state, enter_transition,
				accepted_idle_state_receipt, atlas, fixture, bad_revision).is_empty():
			return false
	return true


func _semantic_tamper_rejected(promise: Dictionary, blueprint: Dictionary,
		initial_state: Dictionary, delta: Dictionary, active_state: Dictionary,
		enter_transition: Dictionary, accepted_idle_state_receipt: String,
		atlas: Dictionary, fixture: Dictionary, transition: Dictionary) -> bool:
	var bad_promise: Dictionary = promise.duplicate(true)
	bad_promise["label"] = "FORGED SITE"
	bad_promise.erase("promise_receipt")
	bad_promise["promise_receipt"] = _receipt_for(bad_promise)
	var bad_blueprint: Dictionary = blueprint.duplicate(true)
	var bad_loot: Array = bad_blueprint.get("loot", [])
	if bad_loot.is_empty():
		return false
	(bad_loot[0] as Dictionary)["label"] = "forged cache"
	bad_blueprint["loot"] = bad_loot
	bad_blueprint.erase("blueprint_receipt")
	bad_blueprint["blueprint_receipt"] = _receipt_for(bad_blueprint)
	var bad_state: Dictionary = initial_state.duplicate(true)
	bad_state["phase"] = "active"
	bad_state.erase("state_receipt")
	bad_state["state_receipt"] = _receipt_for(bad_state)
	var bad_delta: Dictionary = delta.duplicate(true)
	bad_delta["before_state_receipt"] = String(initial_state.get("state_receipt", ""))
	bad_delta = _rehash_delta(bad_delta)
	var bad_transition: Dictionary = transition.duplicate(true)
	var bad_after: Dictionary = (bad_transition.get("after_state", {}) as Dictionary).duplicate(true)
	bad_after["last_resolution"] = "collapsed"
	bad_after.erase("state_receipt")
	bad_after["state_receipt"] = _receipt_for(bad_after)
	bad_transition["after_state"] = bad_after
	bad_transition["after_state_receipt"] = String(bad_after.get("state_receipt", ""))
	bad_transition.erase("transition_receipt")
	bad_transition["transition_receipt"] = _receipt_for(bad_transition)
	return not Model.validate_site_promise(bad_promise).is_empty() \
		and not Model.validate_blueprint(promise, bad_blueprint).is_empty() \
		and not Model.validate_state_snapshot(promise, blueprint, bad_state).is_empty() \
		and not _validate_delta(promise, blueprint, active_state,
			enter_transition, accepted_idle_state_receipt,
			atlas, fixture, bad_delta).is_empty() \
		and not _validate_resolve(promise, blueprint, active_state,
			enter_transition, accepted_idle_state_receipt,
			atlas, fixture, delta, bad_transition).is_empty()


func _forged_active_rejected(promise: Dictionary, blueprint: Dictionary,
		active_state: Dictionary, enter_transition: Dictionary,
		accepted_idle_state_receipt: String, atlas: Dictionary, fixture: Dictionary) -> bool:
	var forged: Dictionary = active_state.duplicate(true)
	forged["active_arrival_receipt"] = "sha256:" + "0".repeat(64)
	forged.erase("state_receipt")
	forged["state_receipt"] = _receipt_for(forged)
	var forged_delta: Dictionary = _make_delta(
		promise, blueprint, forged, enter_transition, accepted_idle_state_receipt,
		atlas, fixture,
		String(forged.get("active_visit_id", "")), "retreated", 1,
		[], [], [], [])
	return Model.validate_state_snapshot(promise, blueprint, forged).is_empty() \
		and forged_delta.is_empty()


func _limits_and_grammar_rejected(promise: Dictionary, blueprint: Dictionary,
		initial_state: Dictionary, active_state: Dictionary,
		enter_transition: Dictionary, cap_source: Dictionary, atlas: Dictionary,
		arrived: Dictionary) -> bool:
	var fractional: Dictionary = initial_state.duplicate(true)
	fractional["revision"] = 0.5
	fractional.erase("state_receipt")
	fractional["state_receipt"] = _receipt_for(fractional)
	var overflow: Dictionary = initial_state.duplicate(true)
	overflow["revision"] = Model.MAX_VISITS + 1
	overflow.erase("state_receipt")
	overflow["state_receipt"] = _receipt_for(overflow)
	var huge: Dictionary = initial_state.duplicate(true)
	huge["revision"] = 1.0e300
	huge.erase("state_receipt")
	huge["state_receipt"] = "sha256:" + "0".repeat(64)
	var accepted_idle_state_receipt: String = String(initial_state.get("state_receipt", ""))
	var cancel_delta: Dictionary = _make_delta(
		promise, blueprint, active_state, enter_transition,
		accepted_idle_state_receipt, atlas, arrived,
		"visit-a", "retreated", 0, [], [], [], [])
	var bad_zero_extracted: Dictionary = _make_delta(
		promise, blueprint, active_state, enter_transition,
		accepted_idle_state_receipt, atlas, arrived,
		"visit-a", "extracted", 0, [], [], [], [])
	var bad_zero_collapsed: Dictionary = _make_delta(
		promise, blueprint, active_state, enter_transition,
		accepted_idle_state_receipt, atlas, arrived,
		"visit-a", "collapsed", 0, [], [], [], [])
	var bad_zero_scar: Dictionary = _make_delta(
		promise, blueprint, active_state, enter_transition,
		accepted_idle_state_receipt, atlas, arrived,
		"visit-a", "retreated", 0,
		[_first_entity_id(blueprint, "loot")], [], [], [])
	var bad_elapsed_high: Dictionary = _make_delta(
		promise, blueprint, active_state, enter_transition,
		accepted_idle_state_receipt, atlas, arrived,
		"visit-a", "retreated", 100001, [], [], [], [])
	var bad_slug_upper: Dictionary = _enter_from_fixture(
		promise, blueprint, initial_state, accepted_idle_state_receipt,
		atlas, arrived, "Visit-A")
	var bad_slug_separator: Dictionary = _enter_from_fixture(
		promise, blueprint, initial_state, accepted_idle_state_receipt,
		atlas, arrived, "visit/a")
	var cap_state: Dictionary = cap_source.duplicate(true)
	var committed: Array[String] = []
	for index in Model.MAX_VISITS:
		committed.append("cap-%02d" % index)
	cap_state["revision"] = Model.MAX_VISITS
	cap_state["phase"] = "idle"
	cap_state["active_visit_id"] = ""
	cap_state["active_arrival_receipt"] = ""
	cap_state["active_enter_receipt"] = ""
	cap_state["committed_visit_ids"] = committed
	cap_state.erase("state_receipt")
	cap_state["state_receipt"] = _receipt_for(cap_state)
	var cap_valid: bool = Model.validate_state_snapshot(
		promise, blueprint, cap_state).is_empty()
	var cap_enter: Dictionary = _enter_from_fixture(
		promise, blueprint, cap_state, String(cap_state.get("state_receipt", "")),
		atlas, arrived, "visit-cap")
	return not Model.validate_state_snapshot(promise, blueprint, fractional).is_empty() \
		and not Model.validate_state_snapshot(promise, blueprint, overflow).is_empty() \
		and not Model.validate_state_snapshot(promise, blueprint, huge).is_empty() \
		and not cancel_delta.is_empty() \
		and bad_zero_extracted.is_empty() and bad_zero_collapsed.is_empty() \
		and bad_zero_scar.is_empty() and bad_elapsed_high.is_empty() \
		and bad_slug_upper.is_empty() and bad_slug_separator.is_empty() \
		and cap_valid and cap_enter.is_empty()


func _roundtrip_continuation_exact(promise: Dictionary, blueprint: Dictionary,
		active_state: Dictionary, enter_transition: Dictionary,
		accepted_idle_state_receipt: String, atlas: Dictionary, fixture: Dictionary,
		delta: Dictionary, expected_transition: Dictionary) -> bool:
	var promise_json: Variant = JSON.parse_string(JSON.stringify(promise))
	var blueprint_json: Variant = JSON.parse_string(JSON.stringify(blueprint))
	var state_json: Variant = JSON.parse_string(JSON.stringify(active_state))
	var enter_json: Variant = JSON.parse_string(JSON.stringify(enter_transition))
	var atlas_json: Variant = JSON.parse_string(JSON.stringify(atlas))
	var fixture_json: Variant = JSON.parse_string(JSON.stringify(fixture))
	var delta_json: Variant = JSON.parse_string(JSON.stringify(delta))
	var promise_binary: Variant = bytes_to_var(var_to_bytes(promise))
	var blueprint_binary: Variant = bytes_to_var(var_to_bytes(blueprint))
	var state_binary: Variant = bytes_to_var(var_to_bytes(active_state))
	var enter_binary: Variant = bytes_to_var(var_to_bytes(enter_transition))
	var atlas_binary: Variant = bytes_to_var(var_to_bytes(atlas))
	var fixture_binary: Variant = bytes_to_var(var_to_bytes(fixture))
	var delta_binary: Variant = bytes_to_var(var_to_bytes(delta))
	if not (promise_json is Dictionary) or not (blueprint_json is Dictionary) \
			or not (state_json is Dictionary) or not (enter_json is Dictionary) \
			or not (atlas_json is Dictionary) or not (fixture_json is Dictionary) \
			or not (delta_json is Dictionary) \
			or not (promise_binary is Dictionary) or not (blueprint_binary is Dictionary) \
			or not (state_binary is Dictionary) or not (enter_binary is Dictionary) \
			or not (atlas_binary is Dictionary) or not (fixture_binary is Dictionary) \
			or not (delta_binary is Dictionary):
		return false
	var json_transition: Dictionary = _apply_delta(
		promise_json as Dictionary, blueprint_json as Dictionary,
		state_json as Dictionary, enter_json as Dictionary,
		accepted_idle_state_receipt, atlas_json as Dictionary,
		fixture_json as Dictionary, delta_json as Dictionary)
	var binary_transition: Dictionary = _apply_delta(
		promise_binary as Dictionary, blueprint_binary as Dictionary,
		state_binary as Dictionary, enter_binary as Dictionary,
		accepted_idle_state_receipt, atlas_binary as Dictionary,
		fixture_binary as Dictionary, delta_binary as Dictionary)
	return not json_transition.is_empty() and not binary_transition.is_empty() \
		and Model.canonical_json(json_transition) == Model.canonical_json(expected_transition) \
		and Model.canonical_json(binary_transition) == Model.canonical_json(expected_transition) \
		and _json_authority_safe(json_transition) and _json_authority_safe(binary_transition)


func _receipt_contract_exact(promise: Dictionary, blueprint: Dictionary,
		receipt: Dictionary, receipt_text: String) -> bool:
	var json_value: Variant = JSON.parse_string(receipt_text)
	var binary_value: Variant = bytes_to_var(var_to_bytes(receipt))
	if not (json_value is Dictionary) or not (binary_value is Dictionary):
		return false
	var fake: Dictionary = receipt.duplicate(true)
	fake["loot"] = "u32:999"
	fake.erase("receipt")
	fake["receipt"] = _receipt_for(fake)
	return receipt_text != "" \
		and Model.validate_blueprint_receipt(promise, blueprint, json_value).is_empty() \
		and Model.validate_blueprint_receipt(promise, blueprint, binary_value).is_empty() \
		and Model.canonical_receipt_json(promise, blueprint, json_value) == receipt_text \
		and Model.canonical_receipt_json(promise, blueprint, binary_value) == receipt_text \
		and not Model.validate_blueprint_receipt(promise, blueprint, fake).is_empty() \
		and Model.canonical_receipt_json(promise, blueprint, fake) == ""


func _rehash_delta(delta: Dictionary) -> Dictionary:
	var result: Dictionary = delta.duplicate(true)
	result.erase("delta_id")
	result.erase("delta_receipt")
	var digest: String = _sha256_hex(Model.canonical_json(result))
	result["delta_id"] = "svd1:" + digest.substr(0, 16)
	result["delta_receipt"] = _receipt_for(result)
	return result


func _receipt_for(value: Variant) -> String:
	var encoded: String = Model.canonical_json(value)
	if encoded == "":
		return ""
	var digest: String = _sha256_hex(encoded)
	return "sha256:" + digest if digest != "" else ""


func _route_receipt_for(value: Variant) -> String:
	var encoded: String = Routes.canonical_json(value)
	if encoded == "":
		return ""
	var digest: String = _sha256_hex(encoded)
	return "sha256:" + digest if digest != "" else ""


func _sha256_hex(value: String) -> String:
	var context: HashingContext = HashingContext.new()
	var start_error: Error = context.start(HashingContext.HASH_SHA256)
	if start_error != OK:
		return ""
	var update_error: Error = context.update(value.to_utf8_buffer())
	if update_error != OK:
		return ""
	return context.finish().hex_encode()
