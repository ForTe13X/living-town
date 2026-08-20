extends Node

const Model = preload("res://scripts/labs/resource_pool/SettlementNetworkModel.gd")
const Routes = preload("res://scripts/labs/resource_pool/RegionRouteModel.gd")
const Address = preload("res://scripts/labs/resource_pool/ScaleAddress.gd")

const ROOT_SEED := 260814
const OWNER_SCOPE := "ashfall_caravan"
const OTHER_OWNER_SCOPE := "ashfall_relief"
const AMPLE_ROUTE_RESOURCE := 100000
const ZERO_RECEIPT := "sha256:0000000000000000000000000000000000000000000000000000000000000000"
const SAFE_KEYS := [
	"cinder_crossing", "orra_relay", "saint_vey_clinic", "dunlin_homestead",
]
const CONTEXT_KEYS := ["ash_market", "redglass_quarry"]
const GOODS := ["food", "meds", "parts", "scrap"]

var _checks: int = 0
var _fails: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	print("  %s %s%s" % [
		"PASS" if condition else "FAIL", label,
		("  " + detail) if detail != "" else "",
	])
	if not condition:
		_fails += 1


func _ready() -> void:
	print("=== RP-0006 accepted settlement network contract ===")
	var atlas: Dictionary = Routes.make_atlas(ROOT_SEED)
	var catalog: Dictionary = Model.make_catalog(atlas)
	var catalog_again: Dictionary = Model.make_catalog(Routes.make_atlas(ROOT_SEED))
	_check("catalog deterministically derives from the fixed RP-0003 atlas",
		not catalog.is_empty() and Model.validate_catalog(atlas, catalog).is_empty()
		and _canonical_json(catalog) == _canonical_json(catalog_again))
	_check("catalog contains exactly four safe-stop nodes and two context-only sites",
		_catalog_identity_exact(atlas, catalog))
	_check("catalog authority is recursively JSON-native, integral, and deeply independent",
		_json_authority_safe(catalog) and _catalog_deep_copy_exact(atlas, catalog))

	var state0: Dictionary = Model.make_initial_state(catalog)
	var state0_receipt: String = String(state0.get("state_receipt", ""))
	_check("initial network is one exact revision-zero owner checkpoint",
		not state0.is_empty() and Model.validate_state(catalog, state0).is_empty()
		and Model.accept_state_checkpoint(catalog, state0, state0_receipt) == state0
		and int(state0.get("revision", -1)) == 0
		and (state0.get("settled_offer_ids", []) as Array).is_empty()
		and (state0.get("consumed_cargo_anchor_keys", []) as Array).is_empty())
	_check("network checkpoint rejects wrong receipt, derived-field tamper, and unknown fields",
		_state_checkpoint_hostiles(catalog, state0, state0_receipt))

	var owner_a: String = _external_receipt("owner-cargo-checkpoint-a")
	var owner_b: String = _external_receipt("owner-cargo-checkpoint-b")
	var owner_cap: String = _external_receipt("owner-cargo-checkpoint-cap")
	var source_refs: Array = _source_refs(catalog)
	var anchor_a: Dictionary = Model.make_cargo_anchor(
		OWNER_SCOPE, owner_a, _cargo(0, 0, 2, 0), 80, source_refs
	)
	var anchor_a_again: Dictionary = Model.make_cargo_anchor(
		OWNER_SCOPE, owner_a, _cargo(0, 0, 2, 0), 80, source_refs.duplicate(true)
	)
	_check("cargo anchor binds exact external scope/checkpoint and normalizes provenance",
		not anchor_a.is_empty()
		and Model.validate_cargo_anchor(anchor_a, OWNER_SCOPE, owner_a).is_empty()
		and _canonical_json(anchor_a) == _canonical_json(anchor_a_again)
		and _strictly_sorted_json(anchor_a.get("source_refs", [])))
	_check("cargo replay key is global to owner scope and checkpoint, not payload or offer",
		_cargo_replay_key_exact(anchor_a, owner_a, source_refs))
	_check("changed owner scope cannot re-anchor the same external cargo checkpoint",
		_owner_scope_hostile(catalog, state0, state0_receipt, owner_a, source_refs))
	_check("cargo and checkpoint grammar reject hostile numeric and unknown-field input",
		_cargo_numeric_hostiles(anchor_a, owner_a))

	var board_a: Dictionary = _make_board(catalog, state0, state0_receipt, anchor_a, owner_a)
	var aid_option: Dictionary = _option_for_key(catalog, board_a, "saint_vey_generator_aid")
	var trade_option: Dictionary = _option_for_key(catalog, board_a, "dunlin_parts_trade")
	var fortify_option: Dictionary = _option_for_key(catalog, board_a, "orra_relay_fortification")
	_check("parts x2 exposes exactly three sorted non-dominated safe-stop options",
		_board_three_way_exact(board_a, aid_option, trade_option, fortify_option))
	_print_option("aid", aid_option)
	_print_option("trade", trade_option)
	_print_option("fortify", fortify_option)
	_check("Cinder food aid is ineligible under parts cargo and context sites never become options",
		_option_for_key(catalog, board_a, "cinder_food_aid").is_empty()
		and _board_has_only_safe_nodes(catalog, board_a))
	_check("short cargo, full supply, and alternate food cargo suppress only ineligible/no-op offers",
		_board_suppression_exact(catalog, state0, state0_receipt, source_refs))
	_check("offer board and choice reject stale/mixed/self-rehashed and unknown candidates",
		_board_choice_hostiles(catalog, state0, state0_receipt, anchor_a,
			owner_a, board_a, aid_option))
	_check("raw RP-0002/RP-0005 provenance never substitutes for owner cargo quantities",
		_provenance_is_not_spend_authority(catalog, state0, state0_receipt,
			owner_a, source_refs))

	var aid_choice: Dictionary = Model.make_choice(board_a, String(aid_option.get("offer_id", "")))
	var trade_choice: Dictionary = Model.make_choice(board_a, String(trade_option.get("offer_id", "")))
	var fortify_choice: Dictionary = Model.make_choice(board_a, String(fortify_option.get("offer_id", "")))
	var aid_route: Dictionary = _arrived_route(atlas,
		_node_tile(catalog, "saint_vey_clinic"), "rp6-aid")
	var trade_route: Dictionary = _arrived_route(atlas,
		_node_tile(catalog, "dunlin_homestead"), "rp6-trade")
	var fortify_route: Dictionary = _arrived_route(atlas,
		_node_tile(catalog, "orra_relay"), "rp6-fortify")
	var aid_arrival: Dictionary = _arrival(catalog, aid_option, aid_route)
	var trade_arrival: Dictionary = _arrival(catalog, trade_option, trade_route)
	var fortify_arrival: Dictionary = _arrival(catalog, fortify_option, fortify_route)
	_check("all three choices require exact arrived RP-0003 routes plus external journey checkpoints",
		_arrivals_valid(catalog, [
			[aid_option, aid_route, aid_arrival],
			[trade_option, trade_route, trade_arrival],
			[fortify_option, fortify_route, fortify_arrival],
		]))
	_check("traveling, wrong-node, mixed-route, forged-journey, and stale journey anchors reject",
		_arrival_hostiles(catalog, atlas, aid_option, aid_route, aid_arrival, trade_route))

	var aid_transition: Dictionary = _propose(catalog, state0, state0_receipt,
		anchor_a, owner_a, board_a, aid_choice, aid_route, aid_arrival)
	var trade_sibling: Dictionary = _propose(catalog, state0, state0_receipt,
		anchor_a, owner_a, board_a, trade_choice, trade_route, trade_arrival)
	var fortify_sibling: Dictionary = _propose(catalog, state0, state0_receipt,
		anchor_a, owner_a, board_a, fortify_choice, fortify_route, fortify_arrival)
	_check("aid, trade, and fortify are distinct valid sibling proposals from one checkpoint",
		_three_transitions_exact(catalog, state0, state0_receipt, anchor_a,
			owner_a, board_a, [aid_choice, trade_choice, fortify_choice],
			[aid_route, trade_route, fortify_route],
			[aid_arrival, trade_arrival, fortify_arrival],
			[aid_transition, trade_sibling, fortify_sibling]))
	_check("Saint Vey aid applies exact 3 to 1 need and 0 to 2 reciprocity",
		_transition_node_exact(aid_transition, 3, 1, 1, 1, 0, 2))
	_check("Dunlin trade is the unique immediate 80 to 110 supply gain",
		_transition_owner_exact(trade_sibling, 80, 30, 30, 110))
	_check("Orra fortification applies exact 3 to 1 security and 0 to 1 reciprocity",
		_transition_node_exact(fortify_sibling, 1, 1, 3, 1, 0, 1))
	_check("every owner delta conserves cargo and caps supply without hidden mutation",
		_owner_delta_conserved(aid_transition)
		and _owner_delta_conserved(trade_sibling)
		and _owner_delta_conserved(fortify_sibling)
		and _capped_trade_exact(catalog, state0, state0_receipt, source_refs,
			owner_cap, trade_option, trade_route, trade_arrival))

	var state1: Dictionary = aid_transition.get("after_state", {})
	var state1_receipt: String = String(state1.get("state_receipt", ""))
	_check("accepted aid consumes its cargo key and advances one exact network revision",
		not state1.is_empty() and Model.validate_state(catalog, state1).is_empty()
		and int(state1.get("revision", -1)) == 1
		and String(anchor_a.get("replay_key", "")) in (state1.get("consumed_cargo_anchor_keys", []) as Array)
		and String(aid_option.get("offer_id", "")) in (state1.get("settled_offer_ids", []) as Array))
	_check("global cargo replay blocks the same anchor across same or different node",
		_global_replay_rejected(catalog, state1, state1_receipt, anchor_a,
			owner_a, board_a, aid_choice, trade_choice, aid_route, aid_arrival,
			trade_route, trade_arrival))
	_check("after owner CAS, stale sibling state/board/choice/arrival cannot settle",
		_sibling_and_mix_rejected(catalog, state1, state1_receipt, anchor_a,
			owner_a, board_a, trade_choice, aid_choice, trade_route,
			trade_arrival, aid_arrival))
	_check("transition tamper, self-rehash, mix, unknown fields, and old checkpoints reject",
		_transition_hostiles(catalog, state0, state0_receipt, anchor_a, owner_a,
			board_a, aid_choice, aid_route, aid_arrival, aid_transition))

	var projection0: Dictionary = Model.project_intel(catalog, state0, state0_receipt)
	var state1_before_observe: String = _canonical_json(state1)
	var projection1: Dictionary = Model.project_intel(catalog, state1, state1_receipt)
	var projection1_again: Dictionary = Model.project_intel(catalog, state1, state1_receipt)
	_check("new intel remains opaque and pending at revision one",
		_projection_pending_exact(projection0, projection1)
		and _canonical_json(projection1) == _canonical_json(projection1_again))
	_check("observation is pure and cannot advance revision or release delayed intel",
		_canonical_json(state1) == state1_before_observe
		and int(state1.get("revision", -1)) == 1
		and Model.project_intel(catalog, state1, ZERO_RECEIPT).is_empty())

	var anchor_b: Dictionary = Model.make_cargo_anchor(
		OWNER_SCOPE, owner_b, _cargo(0, 0, 2, 0), 80, source_refs)
	var board_b: Dictionary = _make_board(catalog, state1, state1_receipt, anchor_b, owner_b)
	var trade_option_b: Dictionary = _option_for_key(catalog, board_b, "dunlin_parts_trade")
	var trade_choice_b: Dictionary = Model.make_choice(board_b,
		String(trade_option_b.get("offer_id", "")))
	var transition2: Dictionary = _propose(catalog, state1, state1_receipt,
		anchor_b, owner_b, board_b, trade_choice_b, trade_route, trade_arrival)
	var state2: Dictionary = transition2.get("after_state", {})
	var state2_receipt: String = String(state2.get("state_receipt", ""))
	var projection2: Dictionary = Model.project_intel(catalog, state2, state2_receipt)
	_check("only a distinct positive settlement advances to revision two and releases aid intel",
		_second_settlement_releases_exact(catalog, state2, projection2,
			"ash_market", "medical_salvage_window"))
	_check("fortify intel independently targets Redglass and follows the same delayed-release rule",
		_fortify_release_exact(catalog, fortify_sibling, anchor_b, owner_b,
			trade_route, trade_arrival))
	_check("intel created by the final catalog settlement remains pending; exhaustion never flushes it",
		_final_intel_stays_pending(catalog, atlas, source_refs))

	_check("JSON and Variant roundtrips preserve validation and mid-chain continuation",
		_roundtrip_continuation_exact(atlas, catalog, state0, state0_receipt,
			anchor_a, owner_a, board_a, aid_choice, aid_route, aid_arrival,
			aid_transition, anchor_b, owner_b))
	_check("integral JSON floats normalize to ints; fraction, nonfinite, huge, bool, and String reject",
		_numeric_boundary_exact(catalog, state0, anchor_a, owner_a))
	_check("all final authority DTOs remain recursively JSON-native and integer-only",
		_json_authority_safe(aid_transition) and _json_authority_safe(transition2)
		and _json_authority_safe(projection2))

	print("SETTLEMENT_CATALOG_RECEIPT=%s" % String(catalog.get("catalog_receipt", "")))
	print("SETTLEMENT_BOARD_RECEIPT=%s" % String(board_a.get("board_receipt", "")))
	print("SETTLEMENT_TRANSITION_RECEIPT=%s" % String(aid_transition.get("transition_receipt", "")))
	print("SETTLEMENT_STATE_RECEIPT=%s" % state2_receipt)
	print("settlement_network_test: %s (%d fail, %d checks)" % [
		"PASS" if _fails == 0 else "FAIL", _fails, _checks,
	])
	get_tree().quit(0 if _fails == 0 else 1)


func _catalog_identity_exact(atlas: Dictionary, catalog: Dictionary) -> bool:
	if (catalog.get("nodes", []) as Array).size() != 4 \
			or (catalog.get("context_sites", []) as Array).size() != 2:
		return false
	var node_keys: Array[String] = []
	var node_ids: Dictionary = {}
	var previous_node_id: String = ""
	for raw_node in catalog.get("nodes", []) as Array:
		var node: Dictionary = raw_node
		var node_id: String = String(node.get("node_id", ""))
		var tile_id: String = String(node.get("tile_id", ""))
		var site_key: String = String(node.get("site_key", ""))
		var address: Dictionary = Address.parse_id(node_id)
		var receipts: Dictionary = node.get("seed_receipts", {})
		var receipt_values: Array[String] = [
			String((receipts.get("profile", {}) as Dictionary).get("seed_token", "")),
			String((receipts.get("offers", {}) as Dictionary).get("seed_token", "")),
			String((receipts.get("intel", {}) as Dictionary).get("seed_token", "")),
		]
		if node_id == "" or (previous_node_id != "" and node_id <= previous_node_id) \
				or node_ids.has(node_id) or site_key not in SAFE_KEYS \
				or Address.level_of(address) != Address.LEVEL_SITE \
				or Address.canonical_id(Address.parent(address)) != tile_id \
				or not _atlas_site_matches(atlas, site_key, tile_id, node_id, true) \
				or not _seed_receipts_exact(receipts, node_id) \
				or _string_set(receipt_values).size() != 3:
			return false
		previous_node_id = node_id
		node_ids[node_id] = true
		node_keys.append(site_key)
	node_keys.sort()
	var expected_nodes: Array[String] = []
	for key in SAFE_KEYS:
		expected_nodes.append(String(key))
	expected_nodes.sort()
	if node_keys != expected_nodes:
		return false
	var context_keys: Array[String] = []
	var previous_context_id: String = ""
	for raw_context in catalog.get("context_sites", []) as Array:
		var context: Dictionary = raw_context
		var context_id: String = String(context.get("site_id", ""))
		var context_key: String = String(context.get("site_key", ""))
		if context_key not in CONTEXT_KEYS or node_ids.has(context_id) \
				or (previous_context_id != "" and context_id <= previous_context_id) \
				or not _atlas_site_matches(atlas, context_key,
					String(context.get("tile_id", "")), context_id, false):
			return false
		previous_context_id = context_id
		context_keys.append(context_key)
	context_keys.sort()
	var expected_context: Array[String] = []
	for key in CONTEXT_KEYS:
		expected_context.append(String(key))
	expected_context.sort()
	return context_keys == expected_context


func _seed_receipts_exact(receipts: Dictionary, node_id: String) -> bool:
	if receipts.size() != 3:
		return false
	for stream in ["profile", "offers", "intel"]:
		var receipt_value: Variant = receipts.get(stream)
		if not (receipt_value is Dictionary) \
				or not Address.validate_receipt(receipt_value).is_empty() \
				or String((receipt_value as Dictionary).get("address", "")) != node_id:
			return false
	return true


func _atlas_site_matches(atlas: Dictionary, site_key: String, tile_id: String,
		site_id: String, expected_safe: bool) -> bool:
	for raw_tile in atlas.get("tiles", []) as Array:
		var tile: Dictionary = raw_tile
		if String(tile.get("site_key", "")) == site_key:
			return String(tile.get("id", "")) == tile_id \
				and String(tile.get("site_id", "")) == site_id \
				and bool(tile.get("safe_stop", false)) == expected_safe
	return false


func _catalog_deep_copy_exact(atlas: Dictionary, catalog: Dictionary) -> bool:
	var mutated: Dictionary = catalog.duplicate(true)
	var nodes: Array = mutated.get("nodes", [])
	if nodes.is_empty():
		return false
	(nodes[0] as Dictionary)["site_key"] = "poisoned"
	var fresh: Dictionary = Model.make_catalog(atlas)
	return String(((fresh.get("nodes", []) as Array)[0] as Dictionary).get(
		"site_key", "")) != "poisoned" and _canonical_json(fresh) == _canonical_json(catalog)


func _state_checkpoint_hostiles(catalog: Dictionary, state: Dictionary,
		accepted_receipt: String) -> bool:
	var derived_tamper: Dictionary = state.duplicate(true)
	var nodes: Array = derived_tamper.get("nodes", [])
	(nodes[0] as Dictionary)["need_pressure"] = 0
	_rehash_receipt_only(derived_tamper, "state_receipt")
	var unknown: Dictionary = state.duplicate(true)
	unknown["owner"] = "caller"
	_rehash_receipt_only(unknown, "state_receipt")
	return Model.accept_state_checkpoint(catalog, state, ZERO_RECEIPT).is_empty() \
		and not Model.validate_state(catalog, derived_tamper).is_empty() \
		and Model.accept_state_checkpoint(catalog, derived_tamper, accepted_receipt).is_empty() \
		and not Model.validate_state(catalog, unknown).is_empty()


func _cargo(food: Variant, meds: Variant, parts: Variant, scrap: Variant) -> Dictionary:
	return {"food": food, "meds": meds, "parts": parts, "scrap": scrap}


func _source_refs(catalog: Dictionary) -> Array:
	return [{
		"schema": Model.SOURCE_REF_SCHEMA,
		"kind": "site_visit",
		"source_id": "svt1:rp6-provenance",
		"source_address": _context_site_id(catalog, "ash_market"),
		"source_receipt": _external_receipt("site-visit-provenance"),
	}, {
		"schema": Model.SOURCE_REF_SCHEMA,
		"kind": "expedition_outcome",
		"source_id": "outcome-rp6-provenance",
		"source_address": "",
		"source_receipt": _external_receipt("expedition-provenance"),
	}]


func _cargo_replay_key_exact(anchor: Dictionary, owner_receipt: String,
		source_refs: Array) -> bool:
	var changed_payload: Dictionary = Model.make_cargo_anchor(
		OWNER_SCOPE, owner_receipt, _cargo(1, 0, 3, 0), 230, source_refs)
	var changed_checkpoint: Dictionary = Model.make_cargo_anchor(
		OWNER_SCOPE, _external_receipt("owner-cargo-other"),
		_cargo(0, 0, 2, 0), 80, source_refs)
	return not changed_payload.is_empty() and not changed_checkpoint.is_empty() \
		and String(changed_payload.get("replay_key", "")) == String(anchor.get("replay_key", "")) \
		and String(changed_payload.get("anchor_receipt", "")) != String(anchor.get("anchor_receipt", "")) \
		and String(changed_checkpoint.get("replay_key", "")) != String(anchor.get("replay_key", ""))


func _owner_scope_hostile(catalog: Dictionary, state: Dictionary,
		state_receipt: String, owner_receipt: String, source_refs: Array) -> bool:
	var rebound: Dictionary = Model.make_cargo_anchor(
		OTHER_OWNER_SCOPE, owner_receipt, _cargo(0, 0, 2, 0), 80, source_refs)
	return not rebound.is_empty() \
		and not Model.validate_cargo_anchor(rebound, OWNER_SCOPE, owner_receipt).is_empty() \
		and Model.normalize_cargo_anchor(rebound, OWNER_SCOPE, owner_receipt).is_empty() \
		and Model.make_offer_board(catalog, state, state_receipt, rebound,
			OWNER_SCOPE, owner_receipt).is_empty()


func _cargo_numeric_hostiles(anchor: Dictionary, owner_receipt: String) -> bool:
	var invalid_values: Array = [2.5, NAN, INF, 1e100, "2", true, -1, 65]
	for invalid in invalid_values:
		if not Model.make_cargo_anchor(OWNER_SCOPE, owner_receipt,
			_cargo(0, 0, invalid, 0), 80, []).is_empty():
			return false
	var total_overflow: Dictionary = Model.make_cargo_anchor(
		OWNER_SCOPE, owner_receipt, _cargo(64, 1, 64, 0), 80, [])
	var unknown: Dictionary = anchor.duplicate(true)
	unknown["inventory"] = _cargo(0, 0, 99, 0)
	_rehash_id_receipt(unknown, "anchor_id", Model.ANCHOR_ID_PREFIX, "anchor_receipt")
	return total_overflow.is_empty() \
		and not Model.validate_cargo_anchor(anchor, OWNER_SCOPE, ZERO_RECEIPT).is_empty() \
		and not Model.validate_cargo_anchor(unknown, OWNER_SCOPE, owner_receipt).is_empty()


func _make_board(catalog: Dictionary, state: Dictionary, state_receipt: String,
		anchor: Dictionary, owner_receipt: String) -> Dictionary:
	return Model.make_offer_board(catalog, state, state_receipt, anchor,
		OWNER_SCOPE, owner_receipt)


func _option_for_key(catalog: Dictionary, board: Dictionary,
		offer_key: String) -> Dictionary:
	var offer_id: String = ""
	for raw_offer in catalog.get("offers", []) as Array:
		var offer: Dictionary = raw_offer
		if String(offer.get("offer_key", "")) == offer_key:
			offer_id = String(offer.get("offer_id", ""))
			break
	for raw_option in board.get("options", []) as Array:
		var option: Dictionary = raw_option
		if String(option.get("offer_id", "")) == offer_id:
			return option.duplicate(true)
	return {}


func _board_three_way_exact(board: Dictionary, aid: Dictionary,
		trade: Dictionary, fortify: Dictionary) -> bool:
	if String(board.get("decision_status", "")) != "options_available" \
			or (board.get("options", []) as Array).size() != 3 \
			or aid.is_empty() or trade.is_empty() or fortify.is_empty() \
			or not _strictly_sorted_ids(board.get("options", []), "offer_id"):
		return false
	for option in [aid, trade, fortify]:
		var cost: Dictionary = (option as Dictionary).get("cost", {})
		if String(cost.get("good", "")) != "parts" or int(cost.get("quantity", 0)) != 2:
			return false
	var aid_effect: Dictionary = aid.get("effect", {})
	var aid_reward: Dictionary = aid.get("owner_reward", {})
	var trade_effect: Dictionary = trade.get("effect", {})
	var trade_reward: Dictionary = trade.get("owner_reward", {})
	var fortify_effect: Dictionary = fortify.get("effect", {})
	var fortify_reward: Dictionary = fortify.get("owner_reward", {})
	return String(aid.get("action", "")) == "aid" \
		and int(aid_effect.get("need_delta", 0)) == -2 \
		and int(aid_effect.get("reciprocity_delta", 0)) == 2 \
		and int(aid_reward.get("applied_supply_gain_tenths", -1)) == 0 \
		and String(trade.get("action", "")) == "trade" \
		and int(trade_effect.get("need_delta", -1)) == 0 \
		and int(trade_effect.get("security_delta", -1)) == 0 \
		and int(trade_effect.get("reciprocity_delta", -1)) == 0 \
		and int(trade_reward.get("applied_supply_gain_tenths", -1)) == 30 \
		and String(fortify.get("action", "")) == "fortify" \
		and int(fortify_effect.get("security_delta", 0)) == -2 \
		and int(fortify_effect.get("reciprocity_delta", 0)) == 1 \
		and int(fortify_reward.get("applied_supply_gain_tenths", -1)) == 0


func _print_option(label: String, option: Dictionary) -> void:
	var cost: Dictionary = option.get("cost", {})
	var effect: Dictionary = option.get("effect", {})
	var reward: Dictionary = option.get("owner_reward", {})
	print("SETTLEMENT_OPTION=%s node=%s cost=%s:%d need=%d security=%d reciprocity=%d supply=%d" % [
		label, String(option.get("node_id", "")), String(cost.get("good", "")),
		int(cost.get("quantity", 0)), int(effect.get("need_delta", 0)),
		int(effect.get("security_delta", 0)), int(effect.get("reciprocity_delta", 0)),
		int(reward.get("applied_supply_gain_tenths", 0)),
	])


func _board_has_only_safe_nodes(catalog: Dictionary, board: Dictionary) -> bool:
	var safe_ids: Dictionary = {}
	for raw_node in catalog.get("nodes", []) as Array:
		safe_ids[String((raw_node as Dictionary).get("node_id", ""))] = true
	for raw_option in board.get("options", []) as Array:
		if not safe_ids.has(String((raw_option as Dictionary).get("node_id", ""))):
			return false
	return true


func _board_suppression_exact(catalog: Dictionary, state: Dictionary,
		state_receipt: String, source_refs: Array) -> bool:
	var short_receipt: String = _external_receipt("owner-short")
	var short_anchor: Dictionary = Model.make_cargo_anchor(
		OWNER_SCOPE, short_receipt, _cargo(0, 0, 1, 0), 80, source_refs)
	var short_board: Dictionary = _make_board(catalog, state, state_receipt,
		short_anchor, short_receipt)
	var full_receipt: String = _external_receipt("owner-full-supply")
	var full_anchor: Dictionary = Model.make_cargo_anchor(
		OWNER_SCOPE, full_receipt, _cargo(0, 0, 2, 0), 240, source_refs)
	var full_board: Dictionary = _make_board(catalog, state, state_receipt,
		full_anchor, full_receipt)
	var food_receipt: String = _external_receipt("owner-food")
	var food_anchor: Dictionary = Model.make_cargo_anchor(
		OWNER_SCOPE, food_receipt, _cargo(2, 0, 0, 0), 80, source_refs)
	var food_board: Dictionary = _make_board(catalog, state, state_receipt,
		food_anchor, food_receipt)
	return String(short_board.get("decision_status", "")) == "no_option" \
		and (short_board.get("options", []) as Array).is_empty() \
		and _option_for_key(catalog, full_board, "dunlin_parts_trade").is_empty() \
		and not _option_for_key(catalog, full_board, "saint_vey_generator_aid").is_empty() \
		and not _option_for_key(catalog, full_board, "orra_relay_fortification").is_empty() \
		and (food_board.get("options", []) as Array).size() == 1 \
		and not _option_for_key(catalog, food_board, "cinder_food_aid").is_empty()


func _board_choice_hostiles(catalog: Dictionary, state: Dictionary,
		state_receipt: String, anchor: Dictionary, owner_receipt: String,
		board: Dictionary, option: Dictionary) -> bool:
	var choice: Dictionary = Model.make_choice(board, String(option.get("offer_id", "")))
	var forged_board: Dictionary = board.duplicate(true)
	forged_board["decision_status"] = "no_option"
	_rehash_id_receipt(forged_board, "board_id", Model.BOARD_ID_PREFIX, "board_receipt")
	var forged_choice: Dictionary = choice.duplicate(true)
	forged_choice["action"] = "trade"
	_rehash_id_receipt(forged_choice, "choice_id", Model.CHOICE_ID_PREFIX, "choice_receipt")
	var unknown_board: Dictionary = board.duplicate(true)
	unknown_board["camera"] = "north"
	_rehash_id_receipt(unknown_board, "board_id", Model.BOARD_ID_PREFIX, "board_receipt")
	var unknown_choice: Dictionary = choice.duplicate(true)
	unknown_choice["display_label"] = "Aid"
	_rehash_id_receipt(unknown_choice, "choice_id", Model.CHOICE_ID_PREFIX, "choice_receipt")
	return not choice.is_empty() and Model.validate_choice(board, choice).is_empty() \
		and not Model.validate_offer_board(catalog, state, state_receipt, anchor,
			OWNER_SCOPE, owner_receipt, forged_board).is_empty() \
		and Model.make_choice(forged_board, String(option.get("offer_id", ""))).is_empty() \
		and not Model.validate_choice(board, forged_choice).is_empty() \
		and not Model.validate_offer_board(catalog, state, state_receipt, anchor,
			OWNER_SCOPE, owner_receipt, unknown_board).is_empty() \
		and not Model.validate_choice(board, unknown_choice).is_empty()


func _provenance_is_not_spend_authority(catalog: Dictionary, state: Dictionary,
		state_receipt: String, owner_receipt: String, source_refs: Array) -> bool:
	var provenance_only: Dictionary = Model.make_cargo_anchor(
		OWNER_SCOPE, owner_receipt, _cargo(0, 0, 0, 0), 80, source_refs)
	var board: Dictionary = _make_board(catalog, state, state_receipt,
		provenance_only, owner_receipt)
	return not provenance_only.is_empty() \
		and (provenance_only.get("source_refs", []) as Array).size() == 2 \
		and String(board.get("decision_status", "")) == "no_option" \
		and (board.get("options", []) as Array).is_empty()


func _node_tile(catalog: Dictionary, site_key: String) -> String:
	for raw_node in catalog.get("nodes", []) as Array:
		var node: Dictionary = raw_node
		if String(node.get("site_key", "")) == site_key:
			return String(node.get("tile_id", ""))
	return ""


func _node_id(catalog: Dictionary, site_key: String) -> String:
	for raw_node in catalog.get("nodes", []) as Array:
		var node: Dictionary = raw_node
		if String(node.get("site_key", "")) == site_key:
			return String(node.get("node_id", ""))
	return ""


func _context_site_id(catalog: Dictionary, site_key: String) -> String:
	for raw_site in catalog.get("context_sites", []) as Array:
		var site: Dictionary = raw_site
		if String(site.get("site_key", "")) == site_key:
			return String(site.get("site_id", ""))
	return ""


func _arrived_route(atlas: Dictionary, destination: String, slot: String) -> Dictionary:
	return _route_context(atlas, destination, destination, slot, true)


func _route_context(atlas: Dictionary, origin: String, destination: String,
		slot: String, complete: bool) -> Dictionary:
	var atlas_state: Dictionary = Routes.make_initial_atlas_state(atlas)
	var route_board: Dictionary = Routes.route_board(atlas, atlas_state, origin,
		destination, "autumn", AMPLE_ROUTE_RESOURCE, AMPLE_ROUTE_RESOURCE)
	var plan: Dictionary = {}
	for raw_offer in route_board.get("offers", []) as Array:
		var candidate: Dictionary = (raw_offer as Dictionary).get("plan", {})
		if bool(candidate.get("available", false)) \
				and (plan.is_empty() or (candidate.get("path", []) as Array).size() \
				< (plan.get("path", []) as Array).size()):
			plan = candidate
	if plan.is_empty():
		return {}
	var journey: Dictionary = Routes.begin_journey(atlas, atlas_state, plan,
		slot, AMPLE_ROUTE_RESOURCE, AMPLE_ROUTE_RESOURCE)
	if journey.is_empty():
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
			atlas_state = transition.get("atlas_state", {})
			journey = transition.get("journey", {})
	var route_receipt: Dictionary = Routes.route_receipt(
		atlas, atlas_state, plan, journey)
	if route_receipt.is_empty():
		return {}
	return {
		"atlas": atlas,
		"atlas_state": atlas_state,
		"plan": plan,
		"journey": journey,
		"route_receipt": route_receipt,
		"accepted_journey_state_receipt": String(journey.get("state_receipt", "")),
	}


func _arrival(catalog: Dictionary, option: Dictionary, route: Dictionary) -> Dictionary:
	return Model.make_arrival_evidence(catalog, String(option.get("node_id", "")),
		route.get("atlas", {}), route.get("atlas_state", {}), route.get("plan", {}),
		route.get("journey", {}), route.get("route_receipt", {}),
		String(route.get("accepted_journey_state_receipt", "")))


func _arrivals_valid(catalog: Dictionary, fixtures: Array) -> bool:
	for raw_fixture in fixtures:
		var fixture: Array = raw_fixture
		var option: Dictionary = fixture[0]
		var route: Dictionary = fixture[1]
		var arrival: Dictionary = fixture[2]
		if route.is_empty() or arrival.is_empty() \
				or String((route.get("journey", {}) as Dictionary).get("phase", "")) != "arrived" \
				or not Model.validate_arrival_evidence(catalog,
					String(option.get("node_id", "")), route.get("atlas", {}),
					route.get("atlas_state", {}), route.get("plan", {}),
					route.get("journey", {}), route.get("route_receipt", {}),
					String(route.get("accepted_journey_state_receipt", "")), arrival).is_empty():
			return false
	return true


func _arrival_hostiles(catalog: Dictionary, atlas: Dictionary,
		aid_option: Dictionary, aid_route: Dictionary, aid_arrival: Dictionary,
		trade_route: Dictionary) -> bool:
	var wrong_node: String = _node_id(catalog, "orra_relay")
	var wrong_node_result: Dictionary = Model.make_arrival_evidence(catalog,
		wrong_node, aid_route.get("atlas", {}), aid_route.get("atlas_state", {}),
		aid_route.get("plan", {}), aid_route.get("journey", {}),
		aid_route.get("route_receipt", {}),
		String(aid_route.get("accepted_journey_state_receipt", "")))
	var traveling_route: Dictionary = _route_context(atlas,
		Routes.site_tile_id(atlas, "ash_market"),
		_node_tile(catalog, "saint_vey_clinic"), "rp6-traveling", false)
	var traveling_result: Dictionary = _arrival(catalog, aid_option, traveling_route)
	var plan: Dictionary = aid_route.get("plan", {})
	var forged_journey: Dictionary = Routes.begin_journey(atlas,
		aid_route.get("atlas_state", {}), plan, "rp6-forged-arrival",
		AMPLE_ROUTE_RESOURCE - 1, AMPLE_ROUTE_RESOURCE)
	var forged_route_receipt: Dictionary = Routes.route_receipt(atlas,
		aid_route.get("atlas_state", {}), plan, forged_journey)
	var forged_result: Dictionary = Model.make_arrival_evidence(catalog,
		String(aid_option.get("node_id", "")), atlas,
		aid_route.get("atlas_state", {}), plan, forged_journey,
		forged_route_receipt,
		String(aid_route.get("accepted_journey_state_receipt", "")))
	var stale_result: Dictionary = Model.make_arrival_evidence(catalog,
		String(aid_option.get("node_id", "")), atlas,
		aid_route.get("atlas_state", {}), plan, aid_route.get("journey", {}),
		aid_route.get("route_receipt", {}), ZERO_RECEIPT)
	var mixed_receipt_result: Dictionary = Model.make_arrival_evidence(catalog,
		String(aid_option.get("node_id", "")), atlas,
		aid_route.get("atlas_state", {}), plan, aid_route.get("journey", {}),
		trade_route.get("route_receipt", {}),
		String(aid_route.get("accepted_journey_state_receipt", "")))
	var self_rehashed: Dictionary = aid_arrival.duplicate(true)
	self_rehashed["node_id"] = wrong_node
	_rehash_id_receipt(self_rehashed, "arrival_id",
		Model.ARRIVAL_ID_PREFIX, "arrival_receipt")
	return wrong_node_result.is_empty() and not traveling_route.is_empty() \
		and String((traveling_route.get("journey", {}) as Dictionary).get("phase", "")) == "traveling" \
		and traveling_result.is_empty() and not forged_journey.is_empty() \
		and not forged_route_receipt.is_empty() and forged_result.is_empty() \
		and stale_result.is_empty() and mixed_receipt_result.is_empty() \
		and not Model.validate_arrival_evidence(catalog,
			String(aid_option.get("node_id", "")), atlas,
			aid_route.get("atlas_state", {}), plan, aid_route.get("journey", {}),
			aid_route.get("route_receipt", {}),
			String(aid_route.get("accepted_journey_state_receipt", "")),
			self_rehashed).is_empty()


func _propose(catalog: Dictionary, state: Dictionary, state_receipt: String,
		anchor: Dictionary, owner_receipt: String, board: Dictionary,
		choice: Dictionary, route: Dictionary, arrival: Dictionary) -> Dictionary:
	return Model.propose_settlement(catalog, state, state_receipt, anchor,
		OWNER_SCOPE, owner_receipt, board, choice, route.get("atlas", {}),
		route.get("atlas_state", {}), route.get("plan", {}),
		route.get("journey", {}), route.get("route_receipt", {}),
		String(route.get("accepted_journey_state_receipt", "")), arrival)


func _validate_transition(catalog: Dictionary, state: Dictionary,
		state_receipt: String, anchor: Dictionary, owner_receipt: String,
		board: Dictionary, choice: Dictionary, route: Dictionary,
		arrival: Dictionary, value: Variant) -> Array[String]:
	return Model.validate_settlement(catalog, state, state_receipt, anchor,
		OWNER_SCOPE, owner_receipt, board, choice, route.get("atlas", {}),
		route.get("atlas_state", {}), route.get("plan", {}),
		route.get("journey", {}), route.get("route_receipt", {}),
		String(route.get("accepted_journey_state_receipt", "")), arrival, value)


func _three_transitions_exact(catalog: Dictionary, state: Dictionary,
		state_receipt: String, anchor: Dictionary, owner_receipt: String,
		board: Dictionary, choices: Array, routes: Array, arrivals: Array,
		transitions: Array) -> bool:
	var receipts: Dictionary = {}
	for index in transitions.size():
		var transition: Dictionary = transitions[index]
		if transition.is_empty() or not _validate_transition(catalog, state,
			state_receipt, anchor, owner_receipt, board, choices[index],
			routes[index], arrivals[index], transition).is_empty():
			return false
		receipts[String(transition.get("transition_receipt", ""))] = true
	return receipts.size() == 3


func _transition_node_exact(transition: Dictionary, need_before: int,
		need_after: int, security_before: int, security_after: int,
		reciprocity_before: int, reciprocity_after: int) -> bool:
	var delta: Dictionary = transition.get("network_delta", {})
	var before: Dictionary = delta.get("node_before", {})
	var after: Dictionary = delta.get("node_after", {})
	return int(before.get("need_pressure", -1)) == need_before \
		and int(after.get("need_pressure", -1)) == need_after \
		and int(before.get("security_pressure", -1)) == security_before \
		and int(after.get("security_pressure", -1)) == security_after \
		and int(before.get("reciprocity", -1)) == reciprocity_before \
		and int(after.get("reciprocity", -1)) == reciprocity_after


func _transition_owner_exact(transition: Dictionary, supply_before: int,
		requested: int, applied: int, supply_after: int) -> bool:
	var delta: Dictionary = transition.get("owner_delta", {})
	return int(delta.get("supply_before_tenths", -1)) == supply_before \
		and int(delta.get("requested_supply_gain_tenths", -1)) == requested \
		and int(delta.get("applied_supply_gain_tenths", -1)) == applied \
		and int(delta.get("supply_after_tenths", -1)) == supply_after


func _owner_delta_conserved(transition: Dictionary) -> bool:
	var delta: Dictionary = transition.get("owner_delta", {})
	var before: Dictionary = delta.get("cargo_before", {})
	var delivered: Dictionary = delta.get("delivered", {})
	var after: Dictionary = delta.get("cargo_after", {})
	for good in GOODS:
		if int(before.get(good, -1)) != int(delivered.get(good, -2)) \
				+ int(after.get(good, -3)) or int(after.get(good, -1)) < 0:
			return false
	var supply_before: int = int(delta.get("supply_before_tenths", -1))
	var requested: int = int(delta.get("requested_supply_gain_tenths", -1))
	var applied: int = int(delta.get("applied_supply_gain_tenths", -1))
	return applied == mini(requested, Model.MAX_SUPPLY_TENTHS - supply_before) \
		and int(delta.get("supply_after_tenths", -1)) == supply_before + applied \
		and int(delta.get("supply_after_tenths", -1)) <= Model.MAX_SUPPLY_TENTHS


func _capped_trade_exact(catalog: Dictionary, state: Dictionary,
		state_receipt: String, source_refs: Array, owner_receipt: String,
		trade_option: Dictionary, route: Dictionary, arrival: Dictionary) -> bool:
	var anchor: Dictionary = Model.make_cargo_anchor(OWNER_SCOPE, owner_receipt,
		_cargo(0, 0, 2, 0), 230, source_refs)
	var board: Dictionary = _make_board(catalog, state, state_receipt,
		anchor, owner_receipt)
	var option: Dictionary = _option_for_key(catalog, board, "dunlin_parts_trade")
	var choice: Dictionary = Model.make_choice(board, String(option.get("offer_id", "")))
	var transition: Dictionary = _propose(catalog, state, state_receipt,
		anchor, owner_receipt, board, choice, route, arrival)
	return not trade_option.is_empty() and not transition.is_empty() \
		and _transition_owner_exact(transition, 230, 30, 10, 240) \
		and _owner_delta_conserved(transition)


func _global_replay_rejected(catalog: Dictionary, state: Dictionary,
		state_receipt: String, anchor: Dictionary, owner_receipt: String,
		old_board: Dictionary, aid_choice: Dictionary, trade_choice: Dictionary,
		aid_route: Dictionary, aid_arrival: Dictionary, trade_route: Dictionary,
		trade_arrival: Dictionary) -> bool:
	var replay_board: Dictionary = _make_board(catalog, state, state_receipt,
		anchor, owner_receipt)
	return not replay_board.is_empty() \
		and String(replay_board.get("decision_status", "")) == "no_option" \
		and (replay_board.get("options", []) as Array).is_empty() \
		and Model.make_choice(replay_board,
			String(aid_choice.get("offer_id", ""))).is_empty() \
		and _propose(catalog, state, state_receipt, anchor, owner_receipt,
			old_board, aid_choice, aid_route, aid_arrival).is_empty() \
		and _propose(catalog, state, state_receipt, anchor, owner_receipt,
			old_board, trade_choice, trade_route, trade_arrival).is_empty()


func _sibling_and_mix_rejected(catalog: Dictionary, state: Dictionary,
		state_receipt: String, anchor: Dictionary, owner_receipt: String,
		old_board: Dictionary, trade_choice: Dictionary, aid_choice: Dictionary,
		trade_route: Dictionary, trade_arrival: Dictionary,
		aid_arrival: Dictionary) -> bool:
	return _propose(catalog, state, state_receipt, anchor, owner_receipt,
		old_board, trade_choice, trade_route, trade_arrival).is_empty() \
		and _propose(catalog, state, state_receipt, anchor, owner_receipt,
			old_board, aid_choice, trade_route, trade_arrival).is_empty() \
		and _propose(catalog, state, state_receipt, anchor, owner_receipt,
			old_board, trade_choice, trade_route, aid_arrival).is_empty()


func _transition_hostiles(catalog: Dictionary, state: Dictionary,
		state_receipt: String, anchor: Dictionary, owner_receipt: String,
		board: Dictionary, choice: Dictionary, route: Dictionary,
		arrival: Dictionary, transition: Dictionary) -> bool:
	var tampered: Dictionary = transition.duplicate(true)
	var owner_delta: Dictionary = tampered.get("owner_delta", {})
	var cargo_after: Dictionary = owner_delta.get("cargo_after", {})
	cargo_after["parts"] = 1
	_rehash_id_receipt(tampered, "transition_id",
		Model.TRANSITION_ID_PREFIX, "transition_receipt")
	var unknown: Dictionary = transition.duplicate(true)
	unknown["localized_summary"] = "helped"
	_rehash_id_receipt(unknown, "transition_id",
		Model.TRANSITION_ID_PREFIX, "transition_receipt")
	return not transition.is_empty() \
		and _validate_transition(catalog, state, state_receipt, anchor,
			owner_receipt, board, choice, route, arrival, transition).is_empty() \
		and not _validate_transition(catalog, state, state_receipt, anchor,
			owner_receipt, board, choice, route, arrival, tampered).is_empty() \
		and not _validate_transition(catalog, state, state_receipt, anchor,
			owner_receipt, board, choice, route, arrival, unknown).is_empty() \
		and not Model.validate_settlement(catalog, state, ZERO_RECEIPT,
			anchor, OWNER_SCOPE, owner_receipt, board, choice,
			route.get("atlas", {}), route.get("atlas_state", {}),
			route.get("plan", {}), route.get("journey", {}),
			route.get("route_receipt", {}),
			String(route.get("accepted_journey_state_receipt", "")),
			arrival, transition).is_empty() \
		and not Model.validate_settlement(catalog, state, state_receipt,
			anchor, OWNER_SCOPE, ZERO_RECEIPT, board, choice,
			route.get("atlas", {}), route.get("atlas_state", {}),
			route.get("plan", {}), route.get("journey", {}),
			route.get("route_receipt", {}),
			String(route.get("accepted_journey_state_receipt", "")),
			arrival, transition).is_empty()


func _projection_pending_exact(empty_projection: Dictionary,
		pending_projection: Dictionary) -> bool:
	var initial_pending: Array = empty_projection.get("pending", [])
	var initial_available: Array = empty_projection.get("available", [])
	var pending: Array = pending_projection.get("pending", [])
	var available: Array = pending_projection.get("available", [])
	if not initial_pending.is_empty() or not initial_available.is_empty() \
			or pending.size() != 1 or not available.is_empty():
		return false
	var row: Dictionary = pending[0]
	return _exact_keys(row, ["intel_id", "intel_receipt", "release_revision"]) \
		and int(row.get("release_revision", -1)) == 2 \
		and not row.has("subject_site_id") and not row.has("topic")


func _second_settlement_releases_exact(catalog: Dictionary, state: Dictionary,
		projection: Dictionary, subject_key: String, topic: String) -> bool:
	var available: Array = projection.get("available", [])
	return not state.is_empty() and Model.validate_state(catalog, state).is_empty() \
		and int(state.get("revision", -1)) == 2 \
		and (projection.get("pending", []) as Array).is_empty() \
		and available.size() == 1 \
		and String((available[0] as Dictionary).get("subject_site_id", "")) \
			== _context_site_id(catalog, subject_key) \
		and String((available[0] as Dictionary).get("topic", "")) == topic \
		and int((available[0] as Dictionary).get("release_revision", -1)) == 2


func _fortify_release_exact(catalog: Dictionary, fortify_transition: Dictionary,
		anchor_b: Dictionary, owner_b: String, trade_route: Dictionary,
		trade_arrival: Dictionary) -> bool:
	var state1: Dictionary = fortify_transition.get("after_state", {})
	var receipt1: String = String(state1.get("state_receipt", ""))
	var pending: Dictionary = Model.project_intel(catalog, state1, receipt1)
	var board: Dictionary = _make_board(catalog, state1, receipt1, anchor_b, owner_b)
	var option: Dictionary = _option_for_key(catalog, board, "dunlin_parts_trade")
	var choice: Dictionary = Model.make_choice(board, String(option.get("offer_id", "")))
	var transition2: Dictionary = _propose(catalog, state1, receipt1,
		anchor_b, owner_b, board, choice, trade_route, trade_arrival)
	var state2: Dictionary = transition2.get("after_state", {})
	var available: Dictionary = Model.project_intel(catalog, state2,
		String(state2.get("state_receipt", "")))
	var initial: Dictionary = Model.make_initial_state(catalog)
	var empty_projection: Dictionary = Model.project_intel(catalog, initial,
		String(initial.get("state_receipt", "")))
	return _projection_pending_exact(empty_projection, pending) \
		and _second_settlement_releases_exact(catalog, state2, available,
			"redglass_quarry", "quarry_route_activity")


func _final_intel_stays_pending(catalog: Dictionary, atlas: Dictionary,
		source_refs: Array) -> bool:
	var state: Dictionary = Model.make_initial_state(catalog)
	var sequence: Array[String] = [
		"dunlin_parts_trade", "saint_vey_generator_aid",
		"orra_relay_fortification", "cinder_food_aid",
	]
	for index in sequence.size():
		var offer_key: String = sequence[index]
		var good: String = "food" if offer_key == "cinder_food_aid" else "parts"
		var owner_receipt: String = _external_receipt("owner-final-%d" % index)
		var cargo: Dictionary = _cargo(2 if good == "food" else 0, 0,
			2 if good == "parts" else 0, 0)
		var anchor: Dictionary = Model.make_cargo_anchor(OWNER_SCOPE,
			owner_receipt, cargo, 80, source_refs)
		var state_receipt: String = String(state.get("state_receipt", ""))
		var board: Dictionary = _make_board(catalog, state, state_receipt,
			anchor, owner_receipt)
		var option: Dictionary = _option_for_key(catalog, board, offer_key)
		if option.is_empty():
			return false
		var choice: Dictionary = Model.make_choice(board,
			String(option.get("offer_id", "")))
		var node_id: String = String(option.get("node_id", ""))
		var tile_id: String = ""
		for raw_node in catalog.get("nodes", []) as Array:
			var node: Dictionary = raw_node
			if String(node.get("node_id", "")) == node_id:
				tile_id = String(node.get("tile_id", ""))
				break
		var route: Dictionary = _arrived_route(atlas, tile_id,
			"rp6-final-%d" % index)
		var arrival: Dictionary = _arrival(catalog, option, route)
		var transition: Dictionary = _propose(catalog, state, state_receipt,
			anchor, owner_receipt, board, choice, route, arrival)
		if transition.is_empty():
			return false
		state = transition.get("after_state", {})
	var projection: Dictionary = Model.project_intel(catalog, state,
		String(state.get("state_receipt", "")))
	var pending: Array = projection.get("pending", [])
	var available: Array = projection.get("available", [])
	return int(state.get("revision", -1)) == 4 and pending.size() == 1 \
		and int((pending[0] as Dictionary).get("release_revision", -1)) == 5 \
		and available.size() == 2 \
		and String((pending[0] as Dictionary).get("intel_receipt", "")) != ""


func _roundtrip_continuation_exact(atlas: Dictionary, catalog: Dictionary,
		state: Dictionary, state_receipt: String, anchor: Dictionary,
		owner_receipt: String, board: Dictionary, choice: Dictionary,
		route: Dictionary, arrival: Dictionary, transition: Dictionary,
		anchor_b: Dictionary, owner_b: String) -> bool:
	var json_catalog_value: Variant = JSON.parse_string(JSON.stringify(catalog))
	var json_state_value: Variant = JSON.parse_string(JSON.stringify(state))
	var json_anchor_value: Variant = JSON.parse_string(JSON.stringify(anchor))
	var json_board_value: Variant = JSON.parse_string(JSON.stringify(board))
	var json_choice_value: Variant = JSON.parse_string(JSON.stringify(choice))
	var json_arrival_value: Variant = JSON.parse_string(JSON.stringify(arrival))
	var json_transition_value: Variant = JSON.parse_string(JSON.stringify(transition))
	if not (json_catalog_value is Dictionary) or not (json_state_value is Dictionary) \
			or not (json_anchor_value is Dictionary) or not (json_board_value is Dictionary) \
			or not (json_choice_value is Dictionary) or not (json_arrival_value is Dictionary) \
			or not (json_transition_value is Dictionary):
		return false
	var json_catalog: Dictionary = json_catalog_value
	var json_state: Dictionary = json_state_value
	var json_anchor: Dictionary = json_anchor_value
	var json_board: Dictionary = json_board_value
	var json_choice: Dictionary = json_choice_value
	var json_arrival: Dictionary = json_arrival_value
	var json_transition: Dictionary = json_transition_value
	if not Model.validate_catalog(atlas, json_catalog).is_empty() \
			or Model.normalize_state(catalog, json_state).is_empty() \
			or Model.normalize_cargo_anchor(json_anchor, OWNER_SCOPE, owner_receipt).is_empty() \
			or Model.normalize_offer_board(catalog, state, state_receipt, anchor,
				OWNER_SCOPE, owner_receipt, json_board).is_empty() \
			or not Model.validate_choice(board, json_choice).is_empty() \
			or not Model.validate_arrival_evidence(catalog,
				String(choice.get("node_id", "")), route.get("atlas", {}),
				route.get("atlas_state", {}), route.get("plan", {}),
				route.get("journey", {}), route.get("route_receipt", {}),
				String(route.get("accepted_journey_state_receipt", "")),
				json_arrival).is_empty() \
			or not _validate_transition(catalog, state, state_receipt, anchor,
				owner_receipt, board, choice, route, arrival, json_transition).is_empty():
		return false
	var binary_value: Variant = bytes_to_var(var_to_bytes(transition))
	if not (binary_value is Dictionary) or not _validate_transition(catalog,
		state, state_receipt, anchor, owner_receipt, board, choice,
		route, arrival, binary_value).is_empty():
		return false
	var resumed_state: Dictionary = Model.normalize_state(catalog,
		json_transition.get("after_state", {}))
	var resumed_receipt: String = String(resumed_state.get("state_receipt", ""))
	var resumed_board: Dictionary = _make_board(catalog, resumed_state,
		resumed_receipt, anchor_b, owner_b)
	return not resumed_state.is_empty() and not resumed_board.is_empty() \
		and String(resumed_board.get("decision_status", "")) == "options_available"


func _numeric_boundary_exact(catalog: Dictionary, state: Dictionary,
		anchor: Dictionary, owner_receipt: String) -> bool:
	var integral_state: Dictionary = state.duplicate(true)
	integral_state["revision"] = 0.0
	for raw_node in integral_state.get("nodes", []) as Array:
		var node: Dictionary = raw_node
		node["need_pressure"] = float(int(node["need_pressure"]))
		node["security_pressure"] = float(int(node["security_pressure"]))
		node["reciprocity"] = float(int(node["reciprocity"]))
	var normalized_state: Dictionary = Model.normalize_state(catalog, integral_state)
	var integral_anchor: Dictionary = anchor.duplicate(true)
	(integral_anchor.get("cargo_before", {}) as Dictionary)["parts"] = 2.0
	integral_anchor["supply_before_tenths"] = 80.0
	var normalized_anchor: Dictionary = Model.normalize_cargo_anchor(
		integral_anchor, OWNER_SCOPE, owner_receipt)
	if normalized_state.is_empty() or normalized_anchor.is_empty() \
			or typeof(normalized_state.get("revision")) != TYPE_INT \
			or typeof(normalized_anchor.get("supply_before_tenths")) != TYPE_INT:
		print("NUMERIC_DIAG=integral state_empty=%s anchor_empty=%s state_type=%d anchor_type=%d" % [
			normalized_state.is_empty(), normalized_anchor.is_empty(),
			typeof(normalized_state.get("revision")),
			typeof(normalized_anchor.get("supply_before_tenths")),
		])
		return false
	var hostile_values: Array = [0.5, NAN, INF, 1e100, "0", true]
	for hostile in hostile_values:
		var bad_state: Dictionary = state.duplicate(true)
		bad_state["revision"] = hostile
		_rehash_receipt_only(bad_state, "state_receipt")
		if Model.validate_state(catalog, bad_state).is_empty():
			print("NUMERIC_DIAG=state accepted type=%d value=%s" % [
				typeof(hostile), str(hostile)])
			return false
		var bad_anchor: Dictionary = anchor.duplicate(true)
		(bad_anchor.get("cargo_before", {}) as Dictionary)["parts"] = hostile
		_rehash_id_receipt(bad_anchor, "anchor_id",
			Model.ANCHOR_ID_PREFIX, "anchor_receipt")
		if Model.validate_cargo_anchor(bad_anchor,
			OWNER_SCOPE, owner_receipt).is_empty():
			print("NUMERIC_DIAG=cargo accepted type=%d value=%s" % [
				typeof(hostile), str(hostile)])
			return false
	return true


func _strictly_sorted_ids(value: Variant, key: String) -> bool:
	if not (value is Array):
		return false
	var previous: String = ""
	for raw_row in value as Array:
		if not (raw_row is Dictionary):
			return false
		var current: String = String((raw_row as Dictionary).get(key, ""))
		if current == "" or (previous != "" and current <= previous):
			return false
		previous = current
	return true


func _strictly_sorted_json(value: Variant) -> bool:
	if not (value is Array):
		return false
	var previous: String = ""
	for item in value as Array:
		var current: String = _canonical_json(item)
		if current == "" or (previous != "" and current <= previous):
			return false
		previous = current
	return true


func _string_set(values: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for value in values:
		result[value] = true
	return result


func _exact_keys(data: Dictionary, required: Array) -> bool:
	if data.size() != required.size():
		return false
	for raw_key in data:
		if typeof(raw_key) != TYPE_STRING or String(raw_key) not in required:
			return false
	return true


func _external_receipt(label: String) -> String:
	return _receipt_for(["rp6-external-owner-checkpoint", label])


func _rehash_receipt_only(value: Dictionary, receipt_field: String) -> void:
	value.erase(receipt_field)
	value[receipt_field] = _receipt_for(value)


func _rehash_id_receipt(value: Dictionary, id_field: String, prefix: String,
		receipt_field: String) -> void:
	value.erase(id_field)
	value.erase(receipt_field)
	var digest: String = _sha256_hex(_canonical_json(value))
	value[id_field] = prefix + digest.substr(0, 16) if digest != "" else ""
	value[receipt_field] = _receipt_for(value)


func _receipt_for(value: Variant) -> String:
	var encoded: String = _canonical_json(value)
	var digest: String = _sha256_hex(encoded)
	return "sha256:" + digest if digest != "" else ""


func _sha256_hex(value: String) -> String:
	if value == "":
		return ""
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK \
			or context.update(value.to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()


func _canonical_json(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		TYPE_INT:
			return str(int(value))
		TYPE_FLOAT:
			var number: float = float(value)
			if not is_finite(number) or number != floor(number) \
					or absf(number) > float(Model.MAX_SAFE_JSON_INT):
				return ""
			return str(int(number))
		TYPE_STRING:
			return JSON.stringify(String(value))
		TYPE_ARRAY:
			var items: Array[String] = []
			for item in value as Array:
				var encoded: String = _canonical_json(item)
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
			var pairs: Array[String] = []
			for key in keys:
				var encoded: String = _canonical_json(data[key])
				if encoded == "":
					return ""
				pairs.append(JSON.stringify(key) + ":" + encoded)
			return "{" + ",".join(pairs) + "}"
		_:
			return ""


func _json_authority_safe(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_INT:
			return absi(int(value)) <= Model.MAX_SAFE_JSON_INT
		TYPE_FLOAT:
			return false
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
		_:
			return false
