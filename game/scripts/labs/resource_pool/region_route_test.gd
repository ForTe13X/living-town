extends Node

const Model = preload("res://scripts/labs/resource_pool/RegionRouteModel.gd")
const Address = preload("res://scripts/labs/resource_pool/ScaleAddress.gd")

const ROOT_SEED := 260814
const BOARD_SUPPLY := 8500
const BOARD_CONDITION := 92000
const AMPLE_SUPPLY := 100000
const AMPLE_CONDITION := 100000

const ORACLE_TERRAIN_COST := {
	"steppe": {"minutes": 170, "supply_milli": 1050, "condition_milli": 420},
	"pine": {"minutes": 185, "supply_milli": 1100, "condition_milli": 500},
	"scrub": {"minutes": 195, "supply_milli": 1150, "condition_milli": 620},
	"marsh": {"minutes": 230, "supply_milli": 1350, "condition_milli": 900},
	"highland": {"minutes": 210, "supply_milli": 1250, "condition_milli": 1100},
	"ash": {"minutes": 200, "supply_milli": 1200, "condition_milli": 760},
}

const ORACLE_DIRS := [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

var _fails: int = 0
var _checks: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	print("  %s %s%s" % ["PASS" if condition else "FAIL", label,
		("  " + detail if detail != "" else "")])
	if not condition:
		_fails += 1


func _ready() -> void:
	print("=== region atlas + persistent caravan route contract ===")
	var atlas: Dictionary = Model.make_atlas(ROOT_SEED)
	var atlas_again: Dictionary = Model.make_atlas(ROOT_SEED)
	var other_atlas: Dictionary = Model.make_atlas(ROOT_SEED + 1)
	_check("fixed seed atlas validates", not atlas.is_empty() and Model.validate_atlas(atlas).is_empty())
	_check("same root seed reproduces the complete atlas byte for byte",
		Model.canonical_json(atlas) == Model.canonical_json(atlas_again))
	_check("different root seed changes terrain authority but not topology identity",
		String(atlas.get("atlas_id", "")) != String(other_atlas.get("atlas_id", ""))
		and _tile_id_list(atlas) == _tile_id_list(other_atlas)
		and _edge_pair_list(atlas) == _edge_pair_list(other_atlas))
	_check("atlas has the exact authored window metrics",
		(atlas.get("tiles", []) as Array).size() == 192
		and (atlas.get("edges", []) as Array).size() == 521
		and (atlas.get("region_ids", []) as Array).size() == 2,
		"tiles=%d edges=%d regions=%d" % [
			(atlas.get("tiles", []) as Array).size(),
			(atlas.get("edges", []) as Array).size(),
			(atlas.get("region_ids", []) as Array).size(),
		])
	_check("tile identities, region parents, and undirected edges are exact", _atlas_identity_exact(atlas))

	var atlas_state: Dictionary = Model.make_initial_atlas_state(atlas)
	_check("initial discovery is valid, sorted, and unique",
		Model.validate_atlas_state(atlas, atlas_state).is_empty()
		and _strictly_sorted_strings(atlas_state.get("discovered_tile_ids", [])))
	_check("an explicit open road delta is a rejected no-op",
		_open_noop_delta_rejected(atlas, atlas_state))
	var origin: String = Model.site_tile_id(atlas, "ash_market")
	var destination: String = Model.site_tile_id(atlas, "cinder_crossing")
	_check("route endpoints are stable ScaleAddress tile identities",
		origin != "" and destination != "" and origin != destination
		and Address.level_of(Address.parse_id(origin)) == Address.LEVEL_TILE
		and Address.level_of(Address.parse_id(destination)) == Address.LEVEL_TILE)

	var autumn_board: Dictionary = Model.route_board(
		atlas, atlas_state, origin, destination, "autumn", BOARD_SUPPLY, BOARD_CONDITION)
	var winter_board: Dictionary = Model.route_board(
		atlas, atlas_state, origin, destination, "winter", BOARD_SUPPLY, BOARD_CONDITION)
	var no_plan_board: Dictionary = Model.route_board(
		atlas, atlas_state, origin, destination, "winter", 0, BOARD_CONDITION)
	_print_board("autumn", autumn_board)
	_print_board("winter", winter_board)
	_check("autumn offers three valid and distinct immutable plans",
		_board_plans_valid(atlas, atlas_state, autumn_board)
		and _distinct_offer_plan_ids(autumn_board) == 3)
	_check("independent Dijkstra matches every autumn authored route",
		_board_matches_oracle(atlas, atlas_state, autumn_board))
	_check("autumn presents a real fast / safe / frugal tradeoff",
		_autumn_tradeoff_exact(autumn_board))
	_check("winter closes the ridge and exposes fallback-only planning",
		_winter_fallback_exact(winter_board))
	_check("zero supply reports no viable plan without hiding route previews",
		String(no_plan_board.get("decision_status", "")) == "no_plan"
		and (no_plan_board.get("offers", []) as Array).size() == 3)
	_check("season is locked into plan identity and changes route facts",
		_season_identity_changes(autumn_board, winter_board))

	var before_observation: String = _authority_snapshot(atlas, atlas_state)
	_observe_everything(atlas, atlas_state, origin, destination)
	var after_observation: String = _authority_snapshot(atlas, atlas_state)
	_check("route previews, validators, and neighbor queries are observation-independent",
		before_observation == after_observation)

	var market_offer: Dictionary = _offer_by_key(autumn_board, "old_market_road")
	var market_plan: Dictionary = market_offer.get("plan", {})
	var same_tile_plan: Dictionary = Model.make_route_plan(
		atlas, atlas_state, origin, origin, "autumn", "safe", [], "", "same_tile")
	var same_tile_journey: Dictionary = Model.begin_journey(
		atlas, atlas_state, same_tile_plan, "focused-gate-arrived", 0, AMPLE_CONDITION)
	_check("a start-equals-destination journey is immediately arrived and cannot advance",
		not same_tile_plan.is_empty() and not same_tile_journey.is_empty()
		and String(same_tile_journey.get("phase", "")) == "arrived"
		and int(same_tile_journey.get("leg_index", -1)) == 0
		and Model.validate_journey(atlas, atlas_state, same_tile_plan, same_tile_journey).is_empty()
		and Model.advance_one_leg(atlas, atlas_state, same_tile_plan, same_tile_journey).is_empty())
	var journey: Dictionary = Model.begin_journey(
		atlas, atlas_state, market_plan, "focused-gate-a", AMPLE_SUPPLY, AMPLE_CONDITION)
	_check("a valid plan begins at path index zero with conserved resources",
		not journey.is_empty()
		and Model.validate_journey(atlas, atlas_state, market_plan, journey).is_empty()
		and int(journey.get("leg_index", -1)) == 0
		and String(journey.get("current_tile", "")) == String((market_plan.get("path", []) as Array)[0]))
	_check("a stale plan cannot advance after the road revision changes",
		_stale_road_revision_rejected(atlas, atlas_state, market_plan, journey))

	var first_transition: Dictionary = Model.advance_one_leg(atlas, atlas_state, market_plan, journey)
	_check("one leg settles exact position, resources, clock, and receipt",
		_transition_exact(atlas, atlas_state, market_plan, journey, first_transition))
	var first_journey: Dictionary = first_transition.get("journey", {})
	var first_state: Dictionary = first_transition.get("atlas_state", {})
	_check("the first transition preserves journey and atlas-state validity",
		Model.validate_journey(atlas, first_state, market_plan, first_journey).is_empty()
		and Model.validate_atlas_state(atlas, first_state).is_empty())
	_check("rehashing cannot hide journey phase, identity, or ledger tampering",
		_journey_tamper_rejected(
			atlas, atlas_state, market_plan, journey, first_state, first_journey))

	var first_receipt: Dictionary = first_transition.get("leg_receipt", {})
	var first_cost: Dictionary = first_receipt.get("cost", {})
	var short_supply: int = maxi(0, int(first_cost.get("supply_milli", 0)) - 1)
	var short_journey: Dictionary = Model.begin_journey(
		atlas, atlas_state, market_plan, "focused-gate-short", short_supply, AMPLE_CONDITION)
	var short_transition: Dictionary = Model.advance_one_leg(atlas, atlas_state, market_plan, short_journey)
	_check("one-unit supply shortfall strands in place without resource debt",
		_short_resource_exact(
			atlas, atlas_state, market_plan, short_journey, short_transition))
	var exact_journey: Dictionary = Model.begin_journey(
		atlas, atlas_state, market_plan, "focused-gate-exact",
		int(first_cost.get("supply_milli", 0)), AMPLE_CONDITION)
	var exact_transition: Dictionary = Model.advance_one_leg(
		atlas, atlas_state, market_plan, exact_journey)
	_check("an exact supply boundary settles one whole leg, then strands at zero",
		_exact_resource_boundary(
			atlas, atlas_state, market_plan, exact_journey, exact_transition))

	var discovery_result: Dictionary = _advance_until_discovery(
		atlas, atlas_state, market_plan, journey)
	_check("settled travel discovers a sorted, monotonic axial radius-one delta",
		bool(discovery_result.get("ok", false)), String(discovery_result.get("detail", "")))

	var fallback: Dictionary = Model.divert_to_fallback(atlas, atlas_state, market_plan, journey)
	_check("fallback is a new causal plan rooted at the current settled tile",
		_fallback_exact(atlas, atlas_state, market_plan, journey, fallback))
	_check("leg and diversion envelopes reject mix-and-match before-states",
		_causality_mix_and_match_rejected(atlas, atlas_state, market_plan))

	_check("atlas and atlas-state survive JSON and Variant roundtrips",
		_atlas_roundtrip_exact(atlas, atlas_state))
	_check("plan and journey survive JSON and Variant roundtrips",
		_plan_journey_roundtrip_exact(atlas, first_state, market_plan, first_journey))
	_check("unknown atlas, state, plan, and journey fields fail closed",
		_envelope_tamper_rejected(atlas, first_state, market_plan, first_journey))

	var paired_a: Dictionary = Model.begin_journey(
		atlas, atlas_state, market_plan, "paired-observation", AMPLE_SUPPLY, AMPLE_CONDITION)
	var paired_b: Dictionary = paired_a.duplicate(true)
	var paired_a_transition: Dictionary = Model.advance_one_leg(
		atlas, atlas_state, market_plan, paired_a)
	_observe_everything(atlas, atlas_state, origin, destination)
	var paired_b_transition: Dictionary = Model.advance_one_leg(
		atlas, atlas_state, market_plan, paired_b)
	_check("observed and unobserved journey arms settle identically",
		Model.canonical_json(paired_a_transition) == Model.canonical_json(paired_b_transition))

	var completed: Dictionary = _complete_journey(
		atlas, atlas_state, market_plan,
		Model.begin_journey(atlas, atlas_state, market_plan, "golden-route", AMPLE_SUPPLY, AMPLE_CONDITION))
	var completed_journey: Dictionary = completed.get("journey", {})
	var completed_state: Dictionary = completed.get("atlas_state", {})
	var receipt: Dictionary = Model.route_receipt(atlas, completed_state, market_plan, completed_journey)
	_check("ample journey reaches the destination with a canonical final receipt",
		String(completed_journey.get("phase", "")) == "arrived" and not receipt.is_empty()
		and Model.validate_route_receipt(
			atlas, completed_state, market_plan, completed_journey, receipt).is_empty())
	_check("the route receipt survives JSON/Variant roundtrip",
		_receipt_roundtrip_exact(
			atlas, completed_state, market_plan, completed_journey, receipt))
	_check("canonical receipt output rejects arbitrary and self-hashed bad grammar",
		_receipt_grammar_tamper_rejected(receipt))

	print("REGION_ROUTE_FIXTURE=tiles:%d edges:%d discovered:%d autumn:%s winter:%s" % [
		(atlas.get("tiles", []) as Array).size(),
		(atlas.get("edges", []) as Array).size(),
		(atlas_state.get("discovered_tile_ids", []) as Array).size(),
		String(autumn_board.get("decision_status", "")),
		String(winter_board.get("decision_status", "")),
	])
	print("REGION_ROUTE_RECEIPT=%s" % Model.canonical_receipt_json(receipt))
	print("region_route_test: %s (%d fail, %d checks)" % [
		"PASS" if _fails == 0 else "FAIL", _fails, _checks])
	get_tree().quit(0 if _fails == 0 else 1)


func _tile_id_list(atlas: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var tiles: Array = atlas.get("tiles", [])
	for raw_tile in tiles:
		var tile: Dictionary = raw_tile
		result.append(String(tile.get("id", "")))
	result.sort()
	return result


func _edge_pair_list(atlas: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var edges: Array = atlas.get("edges", [])
	for raw_edge in edges:
		var edge: Dictionary = raw_edge
		result.append("%s\u001e%s" % [String(edge.get("a", "")), String(edge.get("b", ""))])
	result.sort()
	return result


func _atlas_identity_exact(atlas: Dictionary) -> bool:
	var region_set: Dictionary = {}
	var region_ids: Array = atlas.get("region_ids", [])
	for raw_region_id in region_ids:
		region_set[String(raw_region_id)] = true
	var tile_set: Dictionary = {}
	var coord_by_id: Dictionary = {}
	var tiles: Array = atlas.get("tiles", [])
	for raw_tile in tiles:
		if not (raw_tile is Dictionary):
			return false
		var tile: Dictionary = raw_tile
		var tile_id: String = String(tile.get("id", ""))
		if tile_set.has(tile_id):
			return false
		var address: Dictionary = Address.parse_id(tile_id)
		var coord: Vector2i = Vector2i(int(tile.get("q", 0)), int(tile.get("r", 0)))
		var parent_id: String = Address.canonical_id(Address.parent(address))
		if Address.level_of(address) != Address.LEVEL_TILE \
				or Address.coordinate(address, "tile") != coord or not region_set.has(parent_id):
			return false
		tile_set[tile_id] = true
		coord_by_id[tile_id] = coord
	var edge_ids: Dictionary = {}
	var pairs: Dictionary = {}
	var edges: Array = atlas.get("edges", [])
	for raw_edge in edges:
		if not (raw_edge is Dictionary):
			return false
		var edge: Dictionary = raw_edge
		var edge_id: String = String(edge.get("id", ""))
		var a: String = String(edge.get("a", ""))
		var b: String = String(edge.get("b", ""))
		var pair: String = a + "\u001e" + b
		if edge_ids.has(edge_id) or pairs.has(pair) or a >= b \
				or not tile_set.has(a) or not tile_set.has(b) \
				or _oracle_distance(coord_by_id[a], coord_by_id[b]) != 1:
			return false
		edge_ids[edge_id] = true
		pairs[pair] = true
	return tile_set.size() == 192 and edge_ids.size() == 521


func _strictly_sorted_strings(value: Variant) -> bool:
	if not (value is Array):
		return false
	var values: Array = value
	for i in range(1, values.size()):
		if typeof(values[i - 1]) != TYPE_STRING or typeof(values[i]) != TYPE_STRING \
				or String(values[i - 1]) >= String(values[i]):
			return false
	return true


func _offer_by_key(board: Dictionary, route_key: String) -> Dictionary:
	var offers: Array = board.get("offers", [])
	for raw_offer in offers:
		if raw_offer is Dictionary and String((raw_offer as Dictionary).get("route_key", "")) == route_key:
			return raw_offer
	return {}


func _print_board(label: String, board: Dictionary) -> void:
	var offers: Array = board.get("offers", [])
	for raw_offer in offers:
		var offer: Dictionary = raw_offer
		var plan: Dictionary = offer.get("plan", {})
		var projection: Dictionary = offer.get("projection", {})
		var totals: Dictionary = plan.get("totals", {})
		print("REGION_ROUTE_OFFER=%s/%s available=%s status=%s minutes=%d supply=%d condition=%d hops=%d advantages=%s" % [
			label, String(offer.get("route_key", "")), str(plan.get("available", false)),
			String(projection.get("status", "")), int(totals.get("minutes", 0)),
			int(totals.get("supply_milli", 0)), int(totals.get("condition_milli", 0)),
			int(totals.get("hops", 0)), str(offer.get("advantages", [])),
		])


func _board_plans_valid(atlas: Dictionary, atlas_state: Dictionary, board: Dictionary) -> bool:
	var offers: Array = board.get("offers", [])
	if offers.size() != 3:
		return false
	for raw_offer in offers:
		var offer: Dictionary = raw_offer
		var plan: Dictionary = offer.get("plan", {})
		if plan.is_empty() or not Model.validate_plan(atlas, atlas_state, plan).is_empty():
			return false
	return true


func _distinct_offer_plan_ids(board: Dictionary) -> int:
	var ids: Dictionary = {}
	var offers: Array = board.get("offers", [])
	for raw_offer in offers:
		var offer: Dictionary = raw_offer
		var plan: Dictionary = offer.get("plan", {})
		ids[String(plan.get("plan_id", ""))] = true
	return ids.size()


func _autumn_tradeoff_exact(board: Dictionary) -> bool:
	if String(board.get("decision_status", "")) != "routes_available":
		return false
	var ridge: Dictionary = _offer_by_key(board, "orra_ridge_cut")
	var market: Dictionary = _offer_by_key(board, "old_market_road")
	var dunlin: Dictionary = _offer_by_key(board, "dunlin_supply_arc")
	return String((ridge.get("projection", {}) as Dictionary).get("status", "")) == "tight" \
		and "fastest" in (ridge.get("advantages", []) as Array) \
		and String((market.get("projection", {}) as Dictionary).get("status", "")) == "safe" \
		and String((dunlin.get("projection", {}) as Dictionary).get("status", "")) == "safe" \
		and "least_wear" in (market.get("advantages", []) as Array) \
		and "most_supply" in (dunlin.get("advantages", []) as Array)


func _winter_fallback_exact(board: Dictionary) -> bool:
	var ridge: Dictionary = _offer_by_key(board, "orra_ridge_cut")
	var ridge_plan: Dictionary = ridge.get("plan", {})
	var fallback: Dictionary = board.get("fallback_offer", {})
	return String(board.get("decision_status", "")) == "fallback_only" \
		and not bool(ridge_plan.get("available", true)) \
		and String(ridge_plan.get("block_reason", "")) == "season_closed" \
		and not fallback.is_empty()


func _season_identity_changes(autumn: Dictionary, winter: Dictionary) -> bool:
	var changed: int = 0
	for route_key in ["orra_ridge_cut", "old_market_road", "dunlin_supply_arc"]:
		var autumn_offer: Dictionary = _offer_by_key(autumn, String(route_key))
		var winter_offer: Dictionary = _offer_by_key(winter, String(route_key))
		var autumn_plan: Dictionary = autumn_offer.get("plan", {})
		var winter_plan: Dictionary = winter_offer.get("plan", {})
		if String(autumn_plan.get("plan_id", "")) != String(winter_plan.get("plan_id", "")):
			changed += 1
		if String(autumn_plan.get("season", "")) != "autumn" \
				or String(winter_plan.get("season", "")) != "winter":
			return false
	return changed == 3


func _authority_snapshot(atlas: Dictionary, atlas_state: Dictionary) -> String:
	return Model.canonical_json({"atlas": atlas, "atlas_state": atlas_state})


func _observe_everything(atlas: Dictionary, atlas_state: Dictionary,
		origin: String, destination: String) -> void:
	Model.validate_atlas(atlas)
	Model.validate_atlas_state(atlas, atlas_state)
	var tiles: Array = atlas.get("tiles", [])
	var sample_indices: Array[int] = [0, tiles.size() / 2, tiles.size() - 1]
	for sample_index in sample_indices:
		if sample_index >= 0 and sample_index < tiles.size():
			var tile: Dictionary = tiles[sample_index]
			Model.axial_neighbors(atlas, String(tile.get("id", "")))
	for season in Model.SEASONS:
		Model.route_board(atlas, atlas_state, origin, destination, String(season),
			BOARD_SUPPLY, BOARD_CONDITION)
	Model.canonical_json(atlas)
	JSON.stringify(atlas_state)


func _transition_exact(atlas: Dictionary, atlas_state: Dictionary, plan: Dictionary,
		before: Dictionary, transition: Dictionary) -> bool:
	if transition.is_empty() or String(transition.get("schema", "")) != Model.TRANSITION_SCHEMA:
		return false
	var after: Dictionary = transition.get("journey", {})
	var next_state: Dictionary = transition.get("atlas_state", {})
	var leg: Dictionary = transition.get("leg_receipt", {})
	var cost: Dictionary = leg.get("cost", {})
	var path: Array = plan.get("path", [])
	return String(leg.get("result", "")) in ["settled", "settled_stranded"] \
		and int(after.get("leg_index", -1)) == 1 \
		and String(after.get("current_tile", "")) == String(path[1]) \
		and int(after.get("supplies_milli", -1)) \
			== int(before.get("supplies_milli", 0)) - int(cost.get("supply_milli", 0)) \
		and int(after.get("condition_milli", -1)) \
			== int(before.get("condition_milli", 0)) - int(cost.get("condition_milli", 0)) \
		and int(after.get("elapsed_minutes", -1)) == int(cost.get("minutes", 0)) \
		and String(transition.get("before_journey_state_receipt", "")) \
			== String(before.get("state_receipt", "")) \
		and String(transition.get("before_atlas_state_receipt", "")) \
			== String(atlas_state.get("state_receipt", "")) \
		and Model.validate_leg_receipt(atlas, atlas_state, plan, before, leg).is_empty() \
		and Model.validate_leg_transition(
			atlas, atlas_state, plan, before, transition).is_empty() \
		and Model.validate_atlas_state(atlas, next_state).is_empty() \
		and Model.validate_journey(atlas, next_state, plan, after).is_empty()


func _short_resource_exact(atlas: Dictionary, atlas_state: Dictionary, plan: Dictionary,
		before: Dictionary, transition: Dictionary) -> bool:
	if transition.is_empty():
		return false
	var after: Dictionary = transition.get("journey", {})
	var leg: Dictionary = transition.get("leg_receipt", {})
	var next_state: Dictionary = transition.get("atlas_state", {})
	return String(leg.get("result", "")) == "insufficient_supply" \
		and String(after.get("phase", "")) == "stranded" \
		and int(after.get("leg_index", -1)) == int(before.get("leg_index", -2)) \
		and String(after.get("current_tile", "")) == String(before.get("current_tile", "")) \
		and int(after.get("supplies_milli", -1)) == int(before.get("supplies_milli", -2)) \
		and int(after.get("condition_milli", -1)) == int(before.get("condition_milli", -2)) \
		and Model.validate_leg_transition(
			atlas, atlas_state, plan, before, transition).is_empty() \
		and Model.validate_journey(atlas, next_state, plan, after).is_empty()


func _exact_resource_boundary(atlas: Dictionary, atlas_state: Dictionary, plan: Dictionary,
		before: Dictionary, transition: Dictionary) -> bool:
	if transition.is_empty():
		return false
	var after: Dictionary = transition.get("journey", {})
	var leg: Dictionary = transition.get("leg_receipt", {})
	var next_state: Dictionary = transition.get("atlas_state", {})
	return String(leg.get("result", "")) == "settled_stranded" \
		and String(after.get("phase", "")) == "stranded" \
		and int(after.get("leg_index", -1)) == int(before.get("leg_index", -1)) + 1 \
		and int(after.get("supplies_milli", -1)) == 0 \
		and Model.validate_leg_transition(
			atlas, atlas_state, plan, before, transition).is_empty() \
		and Model.validate_journey(atlas, next_state, plan, after).is_empty()


func _advance_until_discovery(atlas: Dictionary, initial_state: Dictionary,
		plan: Dictionary, initial_journey: Dictionary) -> Dictionary:
	var state: Dictionary = initial_state.duplicate(true)
	var journey: Dictionary = initial_journey.duplicate(true)
	var guard: int = (plan.get("path", []) as Array).size() + 1
	for _step in guard:
		var transition: Dictionary = Model.advance_one_leg(atlas, state, plan, journey)
		if transition.is_empty():
			return {"ok": false, "detail": "advance returned empty"}
		var leg: Dictionary = transition.get("leg_receipt", {})
		var added: Array = leg.get("discovered_add", [])
		var next_state: Dictionary = transition.get("atlas_state", {})
		if not added.is_empty():
			var prior_ids: Array = state.get("discovered_tile_ids", [])
			var next_ids: Array = next_state.get("discovered_tile_ids", [])
			return {
				"ok": _strictly_sorted_strings(added)
					and next_ids.size() == prior_ids.size() + added.size()
					and _discovery_is_radius_one(atlas, String(leg.get("to", "")), added),
				"detail": "added=%d at leg=%d" % [added.size(), int(leg.get("leg_index", -1))],
			}
		journey = transition.get("journey", {})
		state = next_state
		if String(journey.get("phase", "")) != "traveling":
			break
	return {"ok": false, "detail": "route never emitted discovery"}


func _discovery_is_radius_one(atlas: Dictionary, center_id: String, added: Array) -> bool:
	var coords: Dictionary = _coord_by_id(atlas)
	if not coords.has(center_id):
		return false
	var center: Vector2i = coords[center_id]
	for raw_id in added:
		var tile_id: String = String(raw_id)
		if not coords.has(tile_id) or _oracle_distance(center, coords[tile_id]) > 1:
			return false
	return true


func _fallback_exact(atlas: Dictionary, atlas_state: Dictionary, parent_plan: Dictionary,
		before: Dictionary, fallback: Dictionary) -> bool:
	if fallback.is_empty():
		return false
	var child: Dictionary = fallback.get("child_plan", {})
	var diverted: Dictionary = fallback.get("journey", {})
	var next_state: Dictionary = fallback.get("atlas_state", {})
	var path: Array = child.get("path", [])
	return String(fallback.get("schema", "")) == Model.DIVERSION_SCHEMA \
		and not child.is_empty() and not path.is_empty() \
		and String(fallback.get("parent_plan_id", "")) == String(parent_plan.get("plan_id", "")) \
		and String(fallback.get("before_journey_state_receipt", "")) \
			== String(before.get("state_receipt", "")) \
		and String(fallback.get("before_atlas_state_receipt", "")) \
			== String(atlas_state.get("state_receipt", "")) \
		and String(path[0]) == String(before.get("current_tile", "")) \
		and String(child.get("destination", "")) == String(parent_plan.get("fallback", "")) \
		and String(diverted.get("active_plan_id", "")) == String(child.get("plan_id", "")) \
		and int(diverted.get("leg_index", -1)) == 0 \
		and Model.validate_plan(atlas, next_state, child).is_empty() \
		and Model.validate_journey(atlas, next_state, child, diverted).is_empty() \
		and Model.validate_diversion_transition(
			atlas, atlas_state, parent_plan, before, fallback).is_empty()


func _atlas_roundtrip_exact(atlas: Dictionary, atlas_state: Dictionary) -> bool:
	var atlas_json: Variant = JSON.parse_string(JSON.stringify(atlas))
	var state_json: Variant = JSON.parse_string(JSON.stringify(atlas_state))
	var atlas_binary: Variant = bytes_to_var(var_to_bytes(atlas))
	var state_binary: Variant = bytes_to_var(var_to_bytes(atlas_state))
	return atlas_json is Dictionary and state_json is Dictionary \
		and atlas_binary is Dictionary and state_binary is Dictionary \
		and Model.validate_atlas(atlas_json).is_empty() \
		and Model.validate_atlas(atlas_binary).is_empty() \
		and Model.validate_atlas_state(atlas, state_json).is_empty() \
		and Model.validate_atlas_state(atlas, state_binary).is_empty()


func _plan_journey_roundtrip_exact(atlas: Dictionary, atlas_state: Dictionary,
		plan: Dictionary, journey: Dictionary) -> bool:
	var plan_json: Variant = JSON.parse_string(JSON.stringify(plan))
	var journey_json: Variant = JSON.parse_string(JSON.stringify(journey))
	var plan_binary: Variant = bytes_to_var(var_to_bytes(plan))
	var journey_binary: Variant = bytes_to_var(var_to_bytes(journey))
	var uninterrupted: Dictionary = Model.advance_one_leg(atlas, atlas_state, plan, journey)
	var resumed_json: Dictionary = Model.advance_one_leg(
		atlas, atlas_state, plan_json, journey_json) if plan_json is Dictionary \
		and journey_json is Dictionary else {}
	var resumed_binary: Dictionary = Model.advance_one_leg(
		atlas, atlas_state, plan_binary, journey_binary) if plan_binary is Dictionary \
		and journey_binary is Dictionary else {}
	return plan_json is Dictionary and journey_json is Dictionary \
		and plan_binary is Dictionary and journey_binary is Dictionary \
		and Model.validate_plan(atlas, atlas_state, plan_json).is_empty() \
		and Model.validate_plan(atlas, atlas_state, plan_binary).is_empty() \
		and Model.validate_journey(atlas, atlas_state, plan, journey_json).is_empty() \
		and Model.validate_journey(atlas, atlas_state, plan, journey_binary).is_empty() \
		and not uninterrupted.is_empty() \
		and Model.canonical_json(uninterrupted) == Model.canonical_json(resumed_json) \
		and Model.canonical_json(uninterrupted) == Model.canonical_json(resumed_binary)


func _envelope_tamper_rejected(atlas: Dictionary, atlas_state: Dictionary,
		plan: Dictionary, journey: Dictionary) -> bool:
	var bad_atlas: Dictionary = atlas.duplicate(true)
	bad_atlas["camera"] = true
	var bad_state: Dictionary = atlas_state.duplicate(true)
	bad_state["selected_route"] = "fast"
	var bad_plan: Dictionary = plan.duplicate(true)
	bad_plan["hovered"] = true
	var bad_journey: Dictionary = journey.duplicate(true)
	bad_journey["panel_open"] = true
	return not Model.validate_atlas(bad_atlas).is_empty() \
		and not Model.validate_atlas_state(atlas, bad_state).is_empty() \
		and not Model.validate_plan(atlas, atlas_state, bad_plan).is_empty() \
		and not Model.validate_journey(atlas, atlas_state, plan, bad_journey).is_empty()


func _open_noop_delta_rejected(atlas: Dictionary, atlas_state: Dictionary) -> bool:
	var edges: Array = atlas.get("edges", [])
	var discovered: Array = atlas_state.get("discovered_tile_ids", [])
	if edges.is_empty():
		return false
	var first_edge: Dictionary = edges[0]
	var invalid_state: Dictionary = Model.make_atlas_state(atlas, discovered, [{
		"edge_id": String(first_edge.get("id", "")),
		"state": "open",
	}])
	return invalid_state.is_empty()


func _stale_road_revision_rejected(atlas: Dictionary, atlas_state: Dictionary,
		plan: Dictionary, journey: Dictionary) -> bool:
	var leg_ids: Array = plan.get("leg_ids", [])
	var discovered: Array = atlas_state.get("discovered_tile_ids", [])
	if leg_ids.is_empty():
		return false
	var changed_state: Dictionary = Model.make_atlas_state(atlas, discovered, [{
		"edge_id": String(leg_ids[0]),
		"state": "closed",
	}])
	return not changed_state.is_empty() \
		and Model.validate_atlas_state(atlas, changed_state).is_empty() \
		and String(changed_state.get("road_revision", "")) \
			!= String(atlas_state.get("road_revision", "")) \
		and not Model.validate_plan(atlas, changed_state, plan).is_empty() \
		and Model.advance_one_leg(atlas, changed_state, plan, journey).is_empty()


func _journey_tamper_rejected(atlas: Dictionary, root_state: Dictionary,
		plan: Dictionary, root_journey: Dictionary, settled_state: Dictionary,
		settled_journey: Dictionary) -> bool:
	var bad_phase: Dictionary = root_journey.duplicate(true)
	bad_phase["phase"] = "arrived"
	bad_phase = _rehash_journey(bad_phase)
	var bad_identity: Dictionary = root_journey.duplicate(true)
	var original_id: String = String(bad_identity.get("journey_id", ""))
	if original_id.is_empty():
		return false
	var replacement: String = "0" if original_id[-1] != "0" else "1"
	bad_identity["journey_id"] = original_id.substr(0, original_id.length() - 1) + replacement
	bad_identity = _rehash_journey(bad_identity)
	var bad_clock: Dictionary = root_journey.duplicate(true)
	bad_clock["elapsed_minutes"] = int(bad_clock.get("elapsed_minutes", 0)) + 1
	bad_clock = _rehash_journey(bad_clock)
	var bad_prefix: Dictionary = settled_journey.duplicate(true)
	bad_prefix["committed_leg_ids"] = []
	bad_prefix = _rehash_journey(bad_prefix)
	return not Model.validate_journey(atlas, root_state, plan, bad_phase).is_empty() \
		and not Model.validate_journey(atlas, root_state, plan, bad_identity).is_empty() \
		and not Model.validate_journey(atlas, root_state, plan, bad_clock).is_empty() \
		and not Model.validate_journey(atlas, settled_state, plan, bad_prefix).is_empty()


func _causality_mix_and_match_rejected(atlas: Dictionary, atlas_state: Dictionary,
		plan: Dictionary) -> bool:
	var journey_a: Dictionary = Model.begin_journey(
		atlas, atlas_state, plan, "mix-a", AMPLE_SUPPLY, AMPLE_CONDITION)
	var journey_b: Dictionary = Model.begin_journey(
		atlas, atlas_state, plan, "mix-b", AMPLE_SUPPLY, AMPLE_CONDITION)
	var transition_a: Dictionary = Model.advance_one_leg(
		atlas, atlas_state, plan, journey_a)
	var transition_b: Dictionary = Model.advance_one_leg(
		atlas, atlas_state, plan, journey_b)
	if transition_a.is_empty() or transition_b.is_empty():
		return false
	var spliced_transition: Dictionary = transition_a.duplicate(true)
	spliced_transition["leg_receipt"] = (transition_b.get("leg_receipt", {}) as Dictionary).duplicate(true)
	var leg_a: Dictionary = transition_a.get("leg_receipt", {})
	var leg_exact: bool = Model.validate_leg_transition(
		atlas, atlas_state, plan, journey_a, transition_a).is_empty() \
		and Model.validate_leg_receipt(atlas, atlas_state, plan, journey_a, leg_a).is_empty()
	var leg_mixed_rejected: bool = not Model.validate_leg_transition(
		atlas, atlas_state, plan, journey_b, transition_a).is_empty() \
		and not Model.validate_leg_receipt(
			atlas, atlas_state, plan, journey_b, leg_a).is_empty() \
		and not Model.validate_leg_transition(
			atlas, atlas_state, plan, journey_a, spliced_transition).is_empty()
	var diversion_a: Dictionary = Model.divert_to_fallback(
		atlas, atlas_state, plan, journey_a)
	var diversion_b: Dictionary = Model.divert_to_fallback(
		atlas, atlas_state, plan, journey_b)
	if diversion_a.is_empty() or diversion_b.is_empty():
		return false
	var spliced_diversion: Dictionary = diversion_a.duplicate(true)
	spliced_diversion["journey"] = (diversion_b.get("journey", {}) as Dictionary).duplicate(true)
	var diversion_exact: bool = Model.validate_diversion_transition(
		atlas, atlas_state, plan, journey_a, diversion_a).is_empty()
	var diversion_mixed_rejected: bool = not Model.validate_diversion_transition(
		atlas, atlas_state, plan, journey_b, diversion_a).is_empty() \
		and not Model.validate_diversion_transition(
			atlas, atlas_state, plan, journey_a, spliced_diversion).is_empty()
	return leg_exact and leg_mixed_rejected and diversion_exact and diversion_mixed_rejected


func _receipt_roundtrip_exact(atlas: Dictionary, atlas_state: Dictionary,
		plan: Dictionary, journey: Dictionary, receipt: Dictionary) -> bool:
	var json_value: Variant = JSON.parse_string(JSON.stringify(receipt))
	var binary_value: Variant = bytes_to_var(var_to_bytes(receipt))
	return json_value is Dictionary and binary_value is Dictionary \
		and Model.validate_route_receipt(
			atlas, atlas_state, plan, journey, json_value).is_empty() \
		and Model.validate_route_receipt(
			atlas, atlas_state, plan, journey, binary_value).is_empty() \
		and Model.canonical_receipt_json(json_value) \
			== Model.canonical_receipt_json(binary_value)


func _receipt_grammar_tamper_rejected(receipt: Dictionary) -> bool:
	var arbitrary: Dictionary = {
		"schema": Model.RECEIPT_SCHEMA,
		"route_receipt": "sha256:" + "0".repeat(64),
	}
	var bad_grammar: Dictionary = receipt.duplicate(true)
	bad_grammar["leg_index"] = "u32:+1"
	bad_grammar.erase("route_receipt")
	bad_grammar["route_receipt"] = _receipt_for_dict(bad_grammar)
	return Model.canonical_receipt_json(arbitrary) == "" \
		and String(bad_grammar.get("route_receipt", "")) != "" \
		and Model.canonical_receipt_json(bad_grammar) == ""


func _rehash_journey(journey: Dictionary) -> Dictionary:
	var result: Dictionary = journey.duplicate(true)
	result.erase("state_receipt")
	result["state_receipt"] = _receipt_for_dict(result)
	return result


func _receipt_for_dict(value: Dictionary) -> String:
	var digest: String = _sha256_hex(Model.canonical_json(value))
	return "sha256:" + digest if digest != "" else ""


func _sha256_hex(value: String) -> String:
	var context: HashingContext = HashingContext.new()
	var start_error: Error = context.start(HashingContext.HASH_SHA256)
	if start_error != OK:
		return ""
	var update_error: Error = context.update(value.to_utf8_buffer())
	if update_error != OK:
		return ""
	var digest: PackedByteArray = context.finish()
	return digest.hex_encode()


func _complete_journey(atlas: Dictionary, initial_state: Dictionary,
		plan: Dictionary, initial_journey: Dictionary) -> Dictionary:
	var state: Dictionary = initial_state.duplicate(true)
	var journey: Dictionary = initial_journey.duplicate(true)
	var guard: int = (plan.get("path", []) as Array).size() + 1
	for _step in guard:
		if String(journey.get("phase", "")) != "traveling":
			break
		var transition: Dictionary = Model.advance_one_leg(atlas, state, plan, journey)
		if transition.is_empty():
			return {}
		journey = transition.get("journey", {})
		state = transition.get("atlas_state", {})
	return {"journey": journey, "atlas_state": state}


func _board_matches_oracle(atlas: Dictionary, atlas_state: Dictionary, board: Dictionary) -> bool:
	var offers: Array = board.get("offers", [])
	for raw_offer in offers:
		var offer: Dictionary = raw_offer
		var plan: Dictionary = offer.get("plan", {})
		var oracle_path: Array[String] = _oracle_plan_path(atlas, atlas_state, plan)
		var actual_path: Array[String] = []
		for raw_id in plan.get("path", []):
			actual_path.append(String(raw_id))
		if oracle_path != actual_path:
			return false
		if bool(plan.get("available", false)):
			var oracle_totals: Dictionary = _oracle_path_totals(
				atlas, atlas_state, actual_path, String(plan.get("season", "")))
			if Model.canonical_json(oracle_totals) != Model.canonical_json(plan.get("totals", {})):
				return false
	return true


func _oracle_plan_path(atlas: Dictionary, atlas_state: Dictionary, plan: Dictionary) -> Array[String]:
	var stops: Array[String] = [String(plan.get("origin", ""))]
	var waypoints: Array = plan.get("waypoints", [])
	for raw_waypoint in waypoints:
		stops.append(String(raw_waypoint))
	stops.append(String(plan.get("destination", "")))
	var path: Array[String] = []
	for i in range(stops.size() - 1):
		var segment: Array[String] = _oracle_dijkstra(atlas, atlas_state, stops[i], stops[i + 1],
			String(plan.get("season", "")), String(plan.get("policy", "")))
		if segment.is_empty():
			return []
		if path.is_empty():
			path.append_array(segment)
		else:
			for j in range(1, segment.size()):
				path.append(segment[j])
	return path


func _oracle_dijkstra(atlas: Dictionary, atlas_state: Dictionary, start_id: String,
		destination_id: String, season: String, policy: String) -> Array[String]:
	if start_id == destination_id:
		return [start_id]
	var adjacency: Dictionary = _oracle_adjacency(atlas)
	var edge_by_id: Dictionary = _edge_by_id(atlas)
	var open: Array[String] = [start_id]
	var best: Dictionary = {}
	best[start_id] = {
		"policy": policy, "supply_milli": 0, "minutes": 0, "condition_milli": 0,
		"risk_points": 0, "hops": 0, "path": [start_id],
	}
	while not open.is_empty():
		var best_index: int = 0
		for i in range(1, open.size()):
			if _oracle_candidate_less(best[open[i]], best[open[best_index]]):
				best_index = i
		var current: String = open.pop_at(best_index)
		if current == destination_id:
			var result: Array[String] = []
			var found: Array = (best[current] as Dictionary).get("path", [])
			for raw_id in found:
				result.append(String(raw_id))
			return result
		var neighbor_edges: Array = adjacency.get(current, [])
		for raw_edge_id in neighbor_edges:
			var edge: Dictionary = edge_by_id[String(raw_edge_id)]
			var next_id: String = String(edge["b"]) if String(edge["a"]) == current else String(edge["a"])
			var cost: Dictionary = _oracle_edge_metrics(atlas, atlas_state, edge, season)
			if cost.is_empty():
				continue
			var prior: Dictionary = best[current]
			var next_path: Array = (prior.get("path", []) as Array).duplicate()
			next_path.append(next_id)
			var candidate: Dictionary = {
				"policy": policy,
				"supply_milli": int(prior["supply_milli"]) + int(cost["supply_milli"]),
				"minutes": int(prior["minutes"]) + int(cost["minutes"]),
				"condition_milli": int(prior["condition_milli"]) + int(cost["condition_milli"]),
				"risk_points": int(prior["risk_points"]) + int(cost["risk_points"]),
				"hops": int(prior["hops"]) + 1,
				"path": next_path,
			}
			if not best.has(next_id) or _oracle_candidate_less(candidate, best[next_id]):
				best[next_id] = candidate
				if next_id not in open:
					open.append(next_id)
	return []


func _oracle_candidate_less(left: Dictionary, right: Dictionary) -> bool:
	var policy: String = String(left.get("policy", ""))
	if policy != String(right.get("policy", "")):
		return policy < String(right.get("policy", ""))
	var keys: Array[String] = [
		"supply_milli", "minutes", "condition_milli", "risk_points", "hops"]
	if policy == "fast":
		keys = ["minutes", "supply_milli", "condition_milli", "risk_points", "hops"]
	elif policy == "safe":
		keys = ["condition_milli", "risk_points", "minutes", "supply_milli", "hops"]
	for key in keys:
		if int(left[key]) != int(right[key]):
			return int(left[key]) < int(right[key])
	return "\u001f".join(left["path"] as Array) < "\u001f".join(right["path"] as Array)


func _oracle_path_totals(atlas: Dictionary, atlas_state: Dictionary,
		path: Array[String], season: String) -> Dictionary:
	var totals: Dictionary = {
		"minutes": 0, "supply_milli": 0, "condition_milli": 0,
		"risk_points": 0, "road_legs": 0, "track_legs": 0, "hops": 0,
	}
	for i in range(path.size() - 1):
		var edge: Dictionary = _edge_between(atlas, path[i], path[i + 1])
		var cost: Dictionary = _oracle_edge_metrics(atlas, atlas_state, edge, season)
		if edge.is_empty() or cost.is_empty():
			return {}
		totals["minutes"] = int(totals["minutes"]) + int(cost["minutes"])
		totals["supply_milli"] = int(totals["supply_milli"]) + int(cost["supply_milli"])
		totals["condition_milli"] = int(totals["condition_milli"]) + int(cost["condition_milli"])
		totals["risk_points"] = int(totals["risk_points"]) + int(cost["risk_points"])
		totals["road_legs"] = int(totals["road_legs"]) + (1 if String(edge["road_class"]) == "road" else 0)
		totals["track_legs"] = int(totals["track_legs"]) + (1 if String(edge["road_class"]) == "track" else 0)
		totals["hops"] = int(totals["hops"]) + 1
	return totals


func _oracle_edge_metrics(atlas: Dictionary, atlas_state: Dictionary,
		edge: Dictionary, season: String) -> Dictionary:
	if edge.is_empty() or season not in Model.SEASONS or bool(edge.get("blocked", false)):
		return {}
	var road_deltas: Array = atlas_state.get("road_deltas", [])
	for raw_delta in road_deltas:
		var delta: Dictionary = raw_delta
		if String(delta.get("edge_id", "")) == String(edge.get("id", "")) \
				and String(delta.get("state", "")) == "closed":
			return {}
	if season == "winter" and String(edge.get("corridor", "")) == "ridge":
		return {}
	var tile_by_id: Dictionary = _tile_by_id(atlas)
	var a: Dictionary = tile_by_id[String(edge["a"])]
	var b: Dictionary = tile_by_id[String(edge["b"])]
	var cost_a: Dictionary = ORACLE_TERRAIN_COST[String(a["terrain"])]
	var cost_b: Dictionary = ORACLE_TERRAIN_COST[String(b["terrain"])]
	var minutes: int = _oracle_ceil_div(int(cost_a["minutes"]) + int(cost_b["minutes"]), 2)
	var supply: int = _oracle_ceil_div(int(cost_a["supply_milli"]) + int(cost_b["supply_milli"]), 2)
	var condition: int = _oracle_ceil_div(int(cost_a["condition_milli"]) + int(cost_b["condition_milli"]), 2)
	var risk: int = maxi(int(a["risk"]), int(b["risk"]))
	var corridor: String = String(edge.get("corridor", ""))
	if corridor == "ridge":
		minutes = _oracle_apply_bp(minutes, 7000)
		supply = _oracle_apply_bp(supply, 12500)
		condition = _oracle_apply_bp(condition, 14000)
		risk += 2
	elif corridor == "market":
		minutes = _oracle_apply_bp(minutes, 7000)
		supply = _oracle_apply_bp(supply, 5500)
		condition = _oracle_apply_bp(condition, 5000)
		risk = maxi(1, risk - 2)
	elif corridor == "dunlin":
		minutes = _oracle_apply_bp(minutes, 8500)
		supply = _oracle_apply_bp(supply, 3500)
		condition = _oracle_apply_bp(condition, 9000)
	elif String(edge.get("road_class", "")) == "road":
		minutes = _oracle_apply_bp(minutes, 8000)
		supply = _oracle_apply_bp(supply, 6500)
		condition = _oracle_apply_bp(condition, 6500)
		risk = maxi(1, risk - 1)
	if season == "spring":
		var wet: bool = String(a["terrain"]) == "marsh" or String(b["terrain"]) == "marsh"
		minutes = _oracle_apply_bp(minutes, 13500 if wet else 11000)
		supply = _oracle_apply_bp(supply, 12000 if wet else 10800)
		condition = _oracle_apply_bp(condition, 13500 if wet else 11200)
		risk += 2 if wet else 1
	elif season == "winter":
		if String(edge.get("road_class", "")) == "road":
			minutes = _oracle_apply_bp(minutes, 11000)
			supply = _oracle_apply_bp(supply, 10500)
			condition = _oracle_apply_bp(condition, 11500)
		else:
			minutes = _oracle_apply_bp(minutes, 13000)
			supply = _oracle_apply_bp(supply, 12000)
			condition = _oracle_apply_bp(condition, 13500)
			risk += 2
	return {"minutes": minutes, "supply_milli": supply,
		"condition_milli": condition, "risk_points": risk}


func _oracle_adjacency(atlas: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var tiles: Array = atlas.get("tiles", [])
	for raw_tile in tiles:
		var tile: Dictionary = raw_tile
		result[String(tile["id"])] = []
	var edges: Array = atlas.get("edges", [])
	for raw_edge in edges:
		var edge: Dictionary = raw_edge
		(result[String(edge["a"])] as Array).append(String(edge["id"]))
		(result[String(edge["b"])] as Array).append(String(edge["id"]))
	for raw_id in result:
		(result[raw_id] as Array).sort()
	return result


func _tile_by_id(atlas: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var tiles: Array = atlas.get("tiles", [])
	for raw_tile in tiles:
		var tile: Dictionary = raw_tile
		result[String(tile["id"])] = tile
	return result


func _edge_by_id(atlas: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var edges: Array = atlas.get("edges", [])
	for raw_edge in edges:
		var edge: Dictionary = raw_edge
		result[String(edge["id"])] = edge
	return result


func _edge_between(atlas: Dictionary, a: String, b: String) -> Dictionary:
	var left: String = a if a < b else b
	var right: String = b if a < b else a
	var edges: Array = atlas.get("edges", [])
	for raw_edge in edges:
		var edge: Dictionary = raw_edge
		if String(edge.get("a", "")) == left and String(edge.get("b", "")) == right:
			return edge
	return {}


func _coord_by_id(atlas: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var tiles: Array = atlas.get("tiles", [])
	for raw_tile in tiles:
		var tile: Dictionary = raw_tile
		result[String(tile["id"])] = Vector2i(int(tile["q"]), int(tile["r"]))
	return result


func _oracle_distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = a.x - b.x
	var dr: int = a.y - b.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


func _oracle_apply_bp(value: int, basis_points: int) -> int:
	return _oracle_ceil_div(value * basis_points, 10000)


func _oracle_ceil_div(value: int, divisor: int) -> int:
	return (value + divisor - 1) / divisor
