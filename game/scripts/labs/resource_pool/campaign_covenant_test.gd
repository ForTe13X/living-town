extends Node

const Model = preload("res://scripts/labs/resource_pool/CampaignCovenantModel.gd")
const Campaign = preload("res://scripts/labs/resource_pool/PlanetCampaignModel.gd")
const Routes = preload("res://scripts/labs/resource_pool/RegionRouteModel.gd")
const Network = preload("res://scripts/labs/resource_pool/SettlementNetworkModel.gd")

const ROOT_SEED := 260814
const CAMPAIGN_SCOPE := "ashfall_planet_campaign"
const ALT_CAMPAIGN_SCOPE := "ashfall_planet_campaign_alt"
const GLOBAL_SCOPE := "ashfall_settlement_network"
const ALT_GLOBAL_SCOPE := "ashfall_settlement_network_alt"
const COMMAND_SCOPE := "ashfall_campaign_command"
const WINDOW_KEYS := ["basin_relief", "meridian_trade", "nightward_fortify"]
const BASE_SIGNALS := {
	"basin_relief": {
		"need_pressure": 3, "security_pressure": 1,
		"logistics_pressure": 2, "faction_access": 2,
	},
	"meridian_trade": {
		"need_pressure": 1, "security_pressure": 1,
		"logistics_pressure": 3, "faction_access": 2,
	},
	"nightward_fortify": {
		"need_pressure": 1, "security_pressure": 3,
		"logistics_pressure": 2, "faction_access": 2,
	},
}
const COVENANT_ORACLE := {
	"aid": {
		"key": "relief_guarantee", "window": "basin_relief",
		"benefit": {"relief": 3, "commerce": 0, "defense": 0},
		"due_cost": 3,
	},
	"trade": {
		"key": "exchange_charter", "window": "meridian_trade",
		"benefit": {"relief": 0, "commerce": 3, "defense": 0},
		"due_cost": 2,
	},
	"fortify": {
		"key": "watch_compact", "window": "nightward_fortify",
		"benefit": {"relief": 0, "commerce": 0, "defense": 3},
		"due_cost": 3,
	},
}
const MAX_SAFE_JSON_INT := 9007199254740991

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


func _group_header(index: int, label: String) -> void:
	print("-- %02d %s --" % [index, label])


func _ready() -> void:
	print("=== RP-0008 accepted campaign covenant contract ===")
	var base: Dictionary = _make_base_fixture()
	var atlas: Dictionary = base.get("atlas", {})
	var network_catalog: Dictionary = base.get("network_catalog", {})
	var network_state: Dictionary = base.get("network_state", {})
	var global_receipt: String = String(base.get("global_receipt", ""))
	var campaign_catalog: Dictionary = base.get("campaign_catalog", {})
	var campaign0: Dictionary = base.get("campaign0", {})
	var campaign1_open: Dictionary = base.get("campaign1_open", {})
	var campaign2_open: Dictionary = base.get("campaign2_open", {})
	var catalog: Dictionary = base.get("catalog", {})
	var state0: Dictionary = base.get("state0", {})
	var evidence0: Dictionary = base.get("evidence0", {})
	var board0: Dictionary = base.get("board0", {})

	_group_header(1, "catalog determinism and exact RP-0007 identity")
	var catalog_again: Dictionary = Model.make_catalog(
		Campaign.make_catalog(ROOT_SEED))
	_check("catalog deterministically recompiles from the accepted RP-0007 catalog",
		not catalog.is_empty()
		and Model.validate_catalog(campaign_catalog, catalog).is_empty()
		and _canonical_json(catalog) == _canonical_json(catalog_again))
	_check("three covenants map exactly to authored window, directive, faction, and benefit",
		_catalog_oracle_exact(campaign_catalog, catalog))
	_check("catalog IDs and full receipts use independent canonical recomputation",
		_catalog_receipts_exact(catalog))
	_check("catalog is recursively JSON-native, integral, and deeply independent",
		_json_authority_safe(catalog) and _catalog_deep_copy_exact(
			campaign_catalog, catalog))

	_group_header(2, "state checkpoint, JSON normalization, and forged terms")
	var state0_receipt: String = String(state0.get("state_receipt", ""))
	_check("initial state is one exact open revision-zero owner checkpoint",
		not state0.is_empty() and int(state0.get("revision", -1)) == 0
		and String(state0.get("phase", "")) == "open"
		and Model.validate_state(catalog, state0).is_empty()
		and Model.accept_state_checkpoint(catalog, state0, state0_receipt) == state0)
	_check("checkpoint rejects wrong receipt, derived ledger tamper, and unknown fields",
		_state_checkpoint_hostiles(catalog, state0, state0_receipt))
	_check("integral JSON catalog normalizes to authored TYPE_INT bytes and continues",
		_catalog_json_continuation_exact(
			campaign_catalog, campaign0, catalog, state0, evidence0,
			global_receipt, board0))
	var forged_catalog: Dictionary = _forge_catalog_benefit(catalog)
	_check("self-rehashed benefit terms cannot replace the exact RP-0007-derived catalog",
		not forged_catalog.is_empty()
		and not Model.validate_catalog(campaign_catalog, forged_catalog).is_empty()
		and Model.make_covenant_board(
			forged_catalog, state0, state0_receipt, campaign_catalog, campaign0,
			String(campaign0.get("state_receipt", "")), CAMPAIGN_SCOPE,
			evidence0.get("adapters", []), evidence0.get("acceptances", []),
			GLOBAL_SCOPE, global_receipt).is_empty())

	_group_header(3, "accepted campaign, region, and one global network authority")
	_check("fixture carries a real accepted RP-0006 checkpoint as read-only evidence",
		not atlas.is_empty() and not network_catalog.is_empty()
		and Network.accept_state_checkpoint(
			network_catalog, network_state, global_receipt) == network_state)
	_check("all three region adapters normalize against external scope/checkpoint receipts",
		_evidence_exact(campaign_catalog, evidence0, global_receipt))
	_check("adapter and acceptance permutation is byte-independent",
		_board_permutation_exact(
			catalog, state0, campaign_catalog, campaign0, evidence0,
			global_receipt, board0))
	_check("changed adapter with original acceptance, stale global, and duplicate owner reject",
		_adapter_anchor_hostiles(
			catalog, state0, campaign_catalog, campaign0, evidence0,
			global_receipt))

	_group_header(4, "independent spring board and cap suppression oracle")
	_check("spring access2 exposes exactly three sorted semantic options",
		_board_oracle_exact(campaign_catalog, catalog, board0, evidence0))
	_check("due costs are Relief3, Exchange2, Watch3 without scalar ranking",
		_board_costs_exact(board0)
		and not _contains_forbidden_authority(
			board0, ["score", "rank", "camera", "zoom", "map_size"]))
	_check("an access3 region suppresses only its covenant",
		_cap_suppression_exact(
			catalog, state0, campaign_catalog, campaign0, global_receipt, false))
	_check("all access3 regions produce typed no-eligible rather than an invented fallback",
		_cap_suppression_exact(
			catalog, state0, campaign_catalog, campaign0, global_receipt, true))

	var exchange_bind: Dictionary = _bind_from_board(
		"trade", catalog, state0, campaign_catalog, campaign0,
		evidence0, global_receipt, board0)
	var relief_bind: Dictionary = _bind_from_board(
		"aid", catalog, state0, campaign_catalog, campaign0,
		evidence0, global_receipt, board0)
	var watch_bind: Dictionary = _bind_from_board(
		"fortify", catalog, state0, campaign_catalog, campaign0,
		evidence0, global_receipt, board0)

	_group_header(5, "three bind siblings and two-owner proposal conservation")
	_check("all three sibling choices validate from the same accepted covenant checkpoint",
		_bind_proposal_exact(
			catalog, state0, campaign_catalog, campaign0, evidence0,
			global_receipt, board0, exchange_bind)
		and _bind_proposal_exact(
			catalog, state0, campaign_catalog, campaign0, evidence0,
			global_receipt, board0, relief_bind)
		and _bind_proposal_exact(
			catalog, state0, campaign_catalog, campaign0, evidence0,
			global_receipt, board0, watch_bind))
	_check("bind is open->active revision+1 and faction access2->3 exactly",
		_bind_effect_exact(exchange_bind)
		and _bind_effect_exact(relief_bind) and _bind_effect_exact(watch_bind))
	_check("binding replay identity is payload-independent while proposals remain distinct",
		_bind_replay_identity_exact(exchange_bind, relief_bind, watch_bind))
	_check("bind proposals do not mutate covenant, RP-0007, RP-0006, or adapter inputs",
		_bind_inputs_immutable(
			catalog, state0, campaign_catalog, campaign0, network_state,
			evidence0, exchange_bind))

	_group_header(6, "sibling CAS, stale board, replay, and mixed candidate rejection")
	var exchange_active: Dictionary = exchange_bind.get("after_state", {})
	_check("accepting one sibling makes the old board and every second bind stale",
		_stale_bind_rejected(
			catalog, exchange_active, campaign_catalog, campaign0,
			evidence0, global_receipt, board0))
	_check("choice from a fresh sibling board cannot be mixed with the original board",
		_mixed_board_choice_rejected(
			catalog, state0, campaign_catalog, campaign0, evidence0,
			global_receipt, board0))
	_check("tampered bind proposal, after-state, and unknown fields fail exact recomputation",
		_bind_candidate_hostiles(
			catalog, state0, campaign_catalog, campaign0, evidence0,
			global_receipt, board0, exchange_bind))
	_check("accepted active checkpoint rejects self-rehashed phase and record replay forgeries",
		_active_state_hostiles(catalog, exchange_active))

	_group_header(7, "obligation projection is pure time evidence, not a clock")
	var unbound_projection: Dictionary = Model.project_obligation(
		catalog, state0, state0_receipt, campaign_catalog, campaign0,
		String(campaign0.get("state_receipt", "")), CAMPAIGN_SCOPE)
	var before_due_projection: Dictionary = Model.project_obligation(
		catalog, exchange_active, String(exchange_active.get("state_receipt", "")),
		campaign_catalog, campaign0, String(campaign0.get("state_receipt", "")),
		CAMPAIGN_SCOPE)
	var watch_active: Dictionary = watch_bind.get("after_state", {})
	var watch_due_projection: Dictionary = Model.project_obligation(
		catalog, watch_active, String(watch_active.get("state_receipt", "")),
		campaign_catalog, campaign1_open,
		String(campaign1_open.get("state_receipt", "")), CAMPAIGN_SCOPE)
	_check("unbound and before-due projections expose no terminal action",
		String(unbound_projection.get("timing_status", "")) == "unbound"
		and (unbound_projection.get("available_actions", []) as Array).is_empty()
		and String(before_due_projection.get("timing_status", "")) == "not_due"
		and (before_due_projection.get("available_actions", []) as Array).is_empty())
	_check("unmatched autumn Watch exposes exactly amend and withdraw",
		String(watch_due_projection.get("timing_status", "")) == "due"
		and watch_due_projection.get("available_actions", []) == ["amend", "withdraw"])
	_check("repeated observation is byte-identical and mutates neither owner state",
		_projection_observation_independent(
			catalog, watch_active, campaign_catalog, campaign1_open,
			watch_due_projection))
	_check("post-bind campaign owner scope substitution rejects projection and mutations",
		_campaign_scope_hostile(
			catalog, exchange_active, watch_active, campaign_catalog,
			campaign1_open, evidence0, global_receipt))

	var exchange: Dictionary = _make_exchange_chain(base, exchange_bind)
	_group_header(8, "Exchange exact autumn Trade and honored-superseded settlement")
	_check("autumn cap2 creates one real accepted Trade directive record",
		_rp7_commit_exact(exchange.get("rp7", {}), campaign_catalog, "trade", 1))
	_check("independent due-record oracle finds exactly that Trade evidence",
		_due_record_oracle_exact(
			catalog, exchange_active, exchange.get("campaign", {}), "trade"))
	_check("projection offers honor alone and binds the exact record receipt",
		_projection_exact_honor(
			exchange.get("projection", {}), exchange.get("rp7", {})))
	_check("bind2->3, Trade origin3->3, honor3->3 superseded still settles terminal",
		_exchange_chain_exact(catalog, exchange))

	var relief: Dictionary = _make_relief_chain(base, relief_bind)
	_group_header(9, "Relief cannot consume autumn Trade and must withdraw")
	_check("tight autumn Trade is not Aid proof and committed phase exposes withdraw only",
		String((relief.get("projection", {}) as Dictionary).get(
			"timing_status", "")) == "due"
		and (relief.get("projection", {}) as Dictionary).get(
			"available_actions", []) == ["withdraw"])
	_check("Relief withdraw applies exact access3->1 and records withdrawn terminal",
		_resolution_exact(relief.get("withdraw", {}), "withdrawn", 3, 1,
			-2, -2, "applied"))
	_check("independent tight-cap oracle proves amended winter Aid remains infeasible",
		_relief_future_infeasible(base, relief))

	var watch: Dictionary = _make_watch_chain(base, watch_bind)
	_group_header(10, "Watch one-time amendment and winter Fortify continuity")
	_check("amend proposal validates access3->2 and moves due autumn->winter once",
		_watch_amend_exact(catalog, campaign_catalog, campaign1_open,
			global_receipt, watch))
	_check("amended state is not due in autumn and cannot amend twice",
		_watch_amend_limit_exact(catalog, campaign_catalog, campaign1_open,
			global_receipt, watch))
	_check("winter cap2 creates exact Fortify origin transition access2->3",
		_rp7_commit_exact(watch.get("rp7", {}), campaign_catalog, "fortify", 2)
		and _origin_access(
			(watch.get("rp7", {}) as Dictionary).get("origin_region_delta", {}),
			2, 3))
	_check("honor uses a third checkpoint and settles superseded access3->3",
		_watch_honor_exact(catalog, campaign_catalog, global_receipt, watch))

	_group_header(11, "exact due proof, owner scopes, and three-link freshness")
	var due_hostiles: Dictionary = _make_due_hostiles(base, exchange_bind, exchange)
	_check("real due record from another region owner blocks honor but preserves withdraw",
		_due_owner_hostile_exact(due_hostiles.get("alt_region", {})))
	_check("real due record from another global owner blocks honor but preserves withdraw",
		_due_owner_hostile_exact(due_hostiles.get("alt_global", {})))
	_check("wrong action, epoch, and self-rehashed RP-0007 candidate never prove honor",
		bool(due_hostiles.get("semantic_ok", false)))
	_check("link1 rejects RP-0007 origin checkpoint or adapter reused from bind/amend",
		bool(due_hostiles.get("link1_ok", false)))
	_check("link2 rejects resolution checkpoint or adapter reused from RP-0007 origin",
		bool(due_hostiles.get("link2_ok", false)))

	_group_header(12, "terminal escape, bounded no-op, and lifecycle replay")
	var terminal: Dictionary = _make_terminal_variants(base, exchange_bind, relief_bind,
		exchange, relief, due_hostiles)
	_check("terminal RP-0007 state retains exact earlier Trade honor proof",
		_resolution_exact(terminal.get("exchange_honor", {}), "honored", 3, 3,
			1, 0, "superseded"))
	_check("terminal floor access permits withdrawn superseded0->0 rather than dead-end",
		_resolution_exact(terminal.get("relief_withdraw", {}), "withdrawn", 0, 0,
			-2, 0, "superseded"))
	_check("terminal wrong-owner semantic candidate remains withdrawable but not honorable",
		_resolution_exact(terminal.get("mismatch_withdraw", {}), "withdrawn", 3, 1,
			-2, -2, "applied")
		and (terminal.get("mismatch_honor", {}) as Dictionary).is_empty())
	_check("terminal covenant state rejects repeated honor, withdraw, amend, or bind",
		_terminal_replay_rejected(base, terminal.get("exchange_honor", {}), exchange))

	_group_header(13, "JSON continuation, hostile numerics, canonical budgets, receipts")
	_check("JSON/Variant roundtrip validates and continues from mid-amend active state",
		_roundtrip_continuation_exact(base, watch))
	_check("fraction, nonfinite, huge, bool, String numeric, and unknown fields reject",
		_numeric_and_unknown_hostiles(catalog, state0))
	_check("oversize/deep/node-heavy/cyclic authority and sparse cyclic board fail closed",
		_canonical_budget_hostiles(board0))
	_check("all golden DTO receipts independently recompute and contain no forbidden authority",
		_receipt_suite_exact(catalog, board0, exchange_bind,
			watch.get("amend", {}), watch.get("honor", {})))

	print("CAMPAIGN_COVENANT_CATALOG_RECEIPT=%s" % String(
		catalog.get("catalog_receipt", "")))
	print("CAMPAIGN_COVENANT_BOARD_RECEIPT=%s" % String(
		board0.get("board_receipt", "")))
	print("CAMPAIGN_COVENANT_BIND_RECEIPT=%s" % String(
		exchange_bind.get("proposal_receipt", "")))
	print("CAMPAIGN_COVENANT_AMEND_RECEIPT=%s" % String(
		(watch.get("amend", {}) as Dictionary).get("proposal_receipt", "")))
	print("CAMPAIGN_COVENANT_RESOLUTION_RECEIPT=%s" % String(
		(watch.get("honor", {}) as Dictionary).get("proposal_receipt", "")))
	print("CAMPAIGN_COVENANT_STATE_RECEIPT=%s" % String(
		((watch.get("honor", {}) as Dictionary).get(
			"after_state", {}) as Dictionary).get("state_receipt", "")))
	print("CAMPAIGN_COVENANT_METRICS=covenants:3 checks:%d terminal:3" % _checks)
	print("campaign_covenant_test: %s (%d fail, %d checks)" % [
		"PASS" if _fails == 0 else "FAIL", _fails, _checks])
	get_tree().quit(0 if _fails == 0 else 1)


func _make_base_fixture() -> Dictionary:
	var atlas: Dictionary = Routes.make_atlas(ROOT_SEED)
	var network_catalog: Dictionary = Network.make_catalog(atlas)
	var network_state: Dictionary = Network.make_initial_state(network_catalog)
	var global_receipt: String = String(network_state.get("state_receipt", ""))
	var campaign_catalog: Dictionary = Campaign.make_catalog(ROOT_SEED)
	var campaign0: Dictionary = Campaign.make_initial_state(campaign_catalog)
	var advance1: Dictionary = Campaign.advance_epoch(
		campaign_catalog, campaign0, String(campaign0.get("state_receipt", "")))
	var campaign1_open: Dictionary = advance1.get("after_state", {})
	var advance2: Dictionary = Campaign.advance_epoch(
		campaign_catalog, campaign1_open,
		String(campaign1_open.get("state_receipt", "")))
	var campaign2_open: Dictionary = advance2.get("after_state", {})
	var catalog: Dictionary = Model.make_catalog(campaign_catalog)
	var state0: Dictionary = Model.make_initial_state(catalog)
	var evidence0: Dictionary = _make_evidence(
		campaign_catalog, GLOBAL_SCOPE, global_receipt, "rp8-bind", {}, {})
	var board0: Dictionary = Model.make_covenant_board(
		catalog, state0, String(state0.get("state_receipt", "")),
		campaign_catalog, campaign0, String(campaign0.get("state_receipt", "")),
		CAMPAIGN_SCOPE, evidence0.get("adapters", []),
		evidence0.get("acceptances", []), GLOBAL_SCOPE, global_receipt)
	return {
		"atlas": atlas, "network_catalog": network_catalog,
		"network_state": network_state, "global_receipt": global_receipt,
		"campaign_catalog": campaign_catalog, "campaign0": campaign0,
		"campaign1_open": campaign1_open, "campaign2_open": campaign2_open,
		"catalog": catalog, "state0": state0, "evidence0": evidence0,
		"board0": board0,
	}


func _catalog_oracle_exact(campaign_catalog: Dictionary,
		catalog: Dictionary) -> bool:
	var covenants: Array = catalog.get("covenants", [])
	if covenants.size() != 3:
		return false
	var seen := {}
	for raw_covenant in covenants:
		if not (raw_covenant is Dictionary):
			return false
		var covenant: Dictionary = raw_covenant
		var action: String = String(covenant.get("required_action", ""))
		if not COVENANT_ORACLE.has(action) or seen.has(action):
			return false
		var oracle: Dictionary = COVENANT_ORACLE[action]
		var window: Dictionary = _window_by_key(
			campaign_catalog, String(oracle["window"]))
		var directive: Dictionary = _directive_by_action(campaign_catalog, action)
		if window.is_empty() or directive.is_empty() \
				or String(covenant.get("covenant_key", "")) != String(oracle["key"]) \
				or covenant.get("benefit", {}) != oracle.get("benefit", {}) \
				or covenant.get("window_id") != window.get("window_id") \
				or covenant.get("region_id") != window.get("region_id") \
				or covenant.get("faction_id") != window.get("faction_id") \
				or covenant.get("directive_id") != directive.get("directive_id") \
				or covenant.get("directive_receipt") != directive.get("directive_receipt"):
			return false
		for pair in [["due_delay_epochs", 1], ["amend_delay_epochs", 1],
				["max_amendments", 1], ["bind_access_delta", 1],
				["amend_access_delta", -1], ["honor_access_delta", 1],
				["withdraw_access_delta", -2]]:
			if int(covenant.get(String(pair[0]), 99)) != int(pair[1]):
				return false
		seen[action] = true
	return seen.size() == 3


func _catalog_receipts_exact(catalog: Dictionary) -> bool:
	var previous := ""
	for raw_covenant in catalog.get("covenants", []) as Array:
		if not (raw_covenant is Dictionary):
			return false
		var covenant: Dictionary = raw_covenant
		var covenant_id: String = String(covenant.get("covenant_id", ""))
		var receipt_base: Dictionary = covenant.duplicate(true)
		receipt_base.erase("covenant_receipt")
		if covenant_id <= previous \
				or String(covenant.get("covenant_receipt", "")) \
				!= _receipt_for(receipt_base):
			return false
		previous = covenant_id
	var id_base: Dictionary = catalog.duplicate(true)
	id_base.erase("catalog_id")
	id_base.erase("catalog_receipt")
	var digest: String = _sha256_hex(_canonical_json(id_base))
	return digest != "" \
		and String(catalog.get("catalog_id", "")) == "ccc1:" + digest.substr(0, 16) \
		and String(catalog.get("catalog_receipt", "")) == "sha256:" + digest


func _catalog_deep_copy_exact(campaign_catalog: Dictionary,
		catalog: Dictionary) -> bool:
	var original: String = _canonical_json(catalog)
	var duplicate: Dictionary = catalog.duplicate(true)
	var covenants: Array = duplicate.get("covenants", [])
	if covenants.is_empty() or not (covenants[0] is Dictionary):
		return false
	var first: Dictionary = covenants[0]
	var benefit: Dictionary = first.get("benefit", {})
	benefit["relief"] = 99
	var rebuilt: Dictionary = Model.make_catalog(campaign_catalog)
	return _canonical_json(catalog) == original \
		and _canonical_json(rebuilt) == original


func _state_checkpoint_hostiles(catalog: Dictionary, state0: Dictionary,
		accepted_receipt: String) -> bool:
	if not Model.accept_state_checkpoint(
		catalog, state0, _external_receipt("wrong-state-anchor")).is_empty():
		return false
	var phase: Dictionary = state0.duplicate(true)
	phase["phase"] = "terminal"
	_rehash_state(phase)
	if Model.validate_state(catalog, phase).is_empty() \
			or not Model.accept_state_checkpoint(
				catalog, phase, accepted_receipt).is_empty():
		return false
	var revision: Dictionary = state0.duplicate(true)
	revision["revision"] = 1
	_rehash_state(revision)
	if Model.validate_state(catalog, revision).is_empty():
		return false
	var unknown: Dictionary = state0.duplicate(true)
	unknown["owner"] = "forbidden"
	return not Model.validate_state(catalog, unknown).is_empty()


func _catalog_json_continuation_exact(campaign_catalog: Dictionary,
		campaign0: Dictionary, catalog: Dictionary, state0: Dictionary,
		evidence0: Dictionary, global_receipt: String, board0: Dictionary) -> bool:
	var parsed_value: Variant = JSON.parse_string(JSON.stringify(catalog))
	if not (parsed_value is Dictionary):
		return false
	var parsed: Dictionary = parsed_value
	parsed["binding_epoch"] = 0.0
	parsed["last_decision_epoch"] = 2.0
	parsed["terminal_epoch"] = 3.0
	var covenants: Array = parsed.get("covenants", [])
	if covenants.is_empty() or not (covenants[0] is Dictionary):
		return false
	var first: Dictionary = covenants[0]
	first["due_delay_epochs"] = 1.0
	first["amend_delay_epochs"] = 1.0
	first["max_amendments"] = 1.0
	var normalized: Dictionary = Model.normalize_catalog(campaign_catalog, parsed)
	if normalized.is_empty() or typeof(normalized.get("binding_epoch")) != TYPE_INT:
		return false
	var normalized_state: Dictionary = Model.make_initial_state(normalized)
	var board: Dictionary = Model.make_covenant_board(
		normalized, normalized_state,
		String(normalized_state.get("state_receipt", "")), campaign_catalog,
		campaign0, String(campaign0.get("state_receipt", "")), CAMPAIGN_SCOPE,
		evidence0.get("adapters", []), evidence0.get("acceptances", []),
		GLOBAL_SCOPE, global_receipt)
	return _canonical_json(normalized) == _canonical_json(catalog) \
		and _canonical_json(normalized_state) == _canonical_json(state0) \
		and String(board.get("board_receipt", "")) \
		== String(board0.get("board_receipt", ""))


func _forge_catalog_benefit(source: Dictionary) -> Dictionary:
	var forged: Dictionary = source.duplicate(true)
	var covenants: Array = forged.get("covenants", [])
	if covenants.is_empty() or not (covenants[0] is Dictionary):
		return {}
	var covenant: Dictionary = covenants[0]
	var benefit: Dictionary = covenant.get("benefit", {})
	benefit["relief"] = int(benefit.get("relief", 0)) + 1
	var authority: Dictionary = covenant.duplicate(true)
	authority.erase("label")
	authority.erase("covenant_id")
	authority.erase("covenant_receipt")
	var covenant_digest: String = _sha256_hex(_canonical_json(authority))
	covenant["covenant_id"] = "ccv1:" + covenant_digest.substr(0, 16)
	var covenant_receipt_base: Dictionary = covenant.duplicate(true)
	covenant_receipt_base.erase("covenant_receipt")
	covenant["covenant_receipt"] = _receipt_for(covenant_receipt_base)
	covenants.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("covenant_id", "")) \
			< String(right.get("covenant_id", "")))
	var catalog_base: Dictionary = forged.duplicate(true)
	catalog_base.erase("catalog_id")
	catalog_base.erase("catalog_receipt")
	var digest: String = _sha256_hex(_canonical_json(catalog_base))
	forged["catalog_id"] = "ccc1:" + digest.substr(0, 16)
	forged["catalog_receipt"] = "sha256:" + digest
	return forged


func _evidence_exact(campaign_catalog: Dictionary, evidence: Dictionary,
		global_receipt: String) -> bool:
	var adapters: Array = evidence.get("adapters", [])
	var acceptances: Array = evidence.get("acceptances", [])
	if adapters.size() != 3 or acceptances.size() != 3:
		return false
	var scopes := {CAMPAIGN_SCOPE: true, GLOBAL_SCOPE: true,
		COMMAND_SCOPE: true}
	for raw_adapter in adapters:
		if not (raw_adapter is Dictionary):
			return false
		var adapter: Dictionary = raw_adapter
		var acceptance: Dictionary = _acceptance_for(
			acceptances, String(adapter.get("window_id", "")))
		if acceptance.is_empty():
			return false
		var scope: String = String(acceptance.get("expected_region_scope", ""))
		if scopes.has(scope):
			return false
		var normalized: Dictionary = Campaign.normalize_window_adapter(
			campaign_catalog, adapter, scope,
			String(acceptance.get("accepted_region_checkpoint_receipt", "")),
			GLOBAL_SCOPE, global_receipt,
			String(acceptance.get("expected_adapter_receipt", "")))
		if normalized.is_empty() or _canonical_json(normalized) \
				!= _canonical_json(adapter):
			return false
		scopes[scope] = true
	return scopes.size() == 6


func _board_permutation_exact(catalog: Dictionary, state0: Dictionary,
		campaign_catalog: Dictionary, campaign0: Dictionary,
		evidence0: Dictionary, global_receipt: String, board0: Dictionary) -> bool:
	var adapters: Array = (evidence0.get("adapters", []) as Array).duplicate(true)
	var acceptances: Array = (evidence0.get(
		"acceptances", []) as Array).duplicate(true)
	adapters.reverse()
	acceptances.reverse()
	var board: Dictionary = Model.make_covenant_board(
		catalog, state0, String(state0.get("state_receipt", "")),
		campaign_catalog, campaign0, String(campaign0.get("state_receipt", "")),
		CAMPAIGN_SCOPE, adapters, acceptances, GLOBAL_SCOPE, global_receipt)
	return _canonical_json(board) == _canonical_json(board0)


func _adapter_anchor_hostiles(catalog: Dictionary, state0: Dictionary,
		campaign_catalog: Dictionary, campaign0: Dictionary,
		evidence0: Dictionary, global_receipt: String) -> bool:
	var adapters: Array = (evidence0.get("adapters", []) as Array).duplicate(true)
	var acceptances: Array = (evidence0.get(
		"acceptances", []) as Array).duplicate(true)
	var basin: Dictionary = _adapter_for_key(
		campaign_catalog, adapters, "basin_relief")
	var changed_signals: Dictionary = (basin.get("signals", {}) as Dictionary).duplicate(true)
	changed_signals["need_pressure"] = 2
	var changed: Dictionary = Campaign.make_window_adapter(
		campaign_catalog, "basin_relief", String(basin.get("region_scope", "")),
		String(basin.get("region_checkpoint_receipt", "")), GLOBAL_SCOPE,
		global_receipt, changed_signals)
	for index in adapters.size():
		if String((adapters[index] as Dictionary).get("window_id", "")) \
				== String(basin.get("window_id", "")):
			adapters[index] = changed
	if not Model.make_covenant_board(
		catalog, state0, String(state0.get("state_receipt", "")),
		campaign_catalog, campaign0, String(campaign0.get("state_receipt", "")),
		CAMPAIGN_SCOPE, adapters, acceptances, GLOBAL_SCOPE,
		global_receipt).is_empty():
		return false
	if not Model.make_covenant_board(
		catalog, state0, String(state0.get("state_receipt", "")),
		campaign_catalog, campaign0, String(campaign0.get("state_receipt", "")),
		CAMPAIGN_SCOPE, evidence0.get("adapters", []), acceptances,
		GLOBAL_SCOPE, _external_receipt("stale-global")).is_empty():
		return false
	return Model.make_covenant_board(
		catalog, state0, String(state0.get("state_receipt", "")),
		campaign_catalog, campaign0, String(campaign0.get("state_receipt", "")),
		GLOBAL_SCOPE, evidence0.get("adapters", []), acceptances,
		GLOBAL_SCOPE, global_receipt).is_empty()


func _board_oracle_exact(campaign_catalog: Dictionary, catalog: Dictionary,
		board: Dictionary, evidence: Dictionary) -> bool:
	if String(board.get("decision_status", "")) != "covenants_available" \
			or (board.get("options", []) as Array).size() != 3:
		return false
	var previous := ""
	var seen := {}
	for raw_option in board.get("options", []) as Array:
		if not (raw_option is Dictionary):
			return false
		var option: Dictionary = raw_option
		var action: String = String(option.get("required_action", ""))
		var option_id: String = String(option.get("option_id", ""))
		if not COVENANT_ORACLE.has(action) or seen.has(action) \
				or option_id <= previous:
			return false
		var oracle: Dictionary = COVENANT_ORACLE[action]
		var covenant: Dictionary = _covenant_by_action(catalog, action)
		var adapter: Dictionary = _adapter_for_key(
			campaign_catalog, evidence.get("adapters", []), String(oracle["window"]))
		var before: Dictionary = option.get("region_effect", {}).get(
			"before_signals", {})
		var after: Dictionary = option.get("region_effect", {}).get(
			"after_signals", {})
		if option_id != String(covenant.get("covenant_id", "")) \
				or option.get("benefit", {}) != oracle.get("benefit", {}) \
				or int(option.get("expected_due_capacity_cost", -1)) \
				!= int(oracle["due_cost"]) \
				or before != adapter.get("signals", {}) \
				or int(before.get("faction_access", -1)) != 2 \
				or int(after.get("faction_access", -1)) != 3:
			return false
		previous = option_id
		seen[action] = true
	return seen.size() == 3


func _board_costs_exact(board: Dictionary) -> bool:
	var costs := {}
	for raw_option in board.get("options", []) as Array:
		if not (raw_option is Dictionary):
			return false
		var option: Dictionary = raw_option
		costs[String(option.get("required_action", ""))] = int(
			option.get("expected_due_capacity_cost", -1))
	return costs == {"aid": 3, "trade": 2, "fortify": 3}


func _cap_suppression_exact(catalog: Dictionary, state0: Dictionary,
		campaign_catalog: Dictionary, campaign0: Dictionary,
		global_receipt: String, all_at_cap: bool) -> bool:
	var overrides := {}
	for raw_key in WINDOW_KEYS:
		var key: String = String(raw_key)
		var signals: Dictionary = (BASE_SIGNALS[key] as Dictionary).duplicate(true)
		if all_at_cap or key == "meridian_trade":
			signals["faction_access"] = 3
		overrides[key] = signals
	var evidence: Dictionary = _make_evidence(
		campaign_catalog, GLOBAL_SCOPE, global_receipt,
		"cap-all" if all_at_cap else "cap-one", {}, overrides)
	var board: Dictionary = Model.make_covenant_board(
		catalog, state0, String(state0.get("state_receipt", "")),
		campaign_catalog, campaign0, String(campaign0.get("state_receipt", "")),
		CAMPAIGN_SCOPE, evidence.get("adapters", []),
		evidence.get("acceptances", []), GLOBAL_SCOPE, global_receipt)
	if all_at_cap:
		return String(board.get("decision_status", "")) == "no_eligible_covenant" \
			and (board.get("options", []) as Array).is_empty()
	return String(board.get("decision_status", "")) == "covenants_available" \
		and (board.get("options", []) as Array).size() == 2 \
		and _covenant_option(board, "trade").is_empty()


func _bind_from_board(action: String, catalog: Dictionary, state: Dictionary,
		campaign_catalog: Dictionary, campaign_state: Dictionary,
		evidence: Dictionary, global_receipt: String, board: Dictionary) -> Dictionary:
	var option: Dictionary = _covenant_option(board, action)
	var choice: Dictionary = Model.make_covenant_choice(
		board, String(option.get("option_id", "")))
	return Model.bind_covenant(
		catalog, state, String(state.get("state_receipt", "")), campaign_catalog,
		campaign_state, String(campaign_state.get("state_receipt", "")),
		CAMPAIGN_SCOPE, evidence.get("adapters", []),
		evidence.get("acceptances", []), GLOBAL_SCOPE, global_receipt, board, choice)


func _bind_proposal_exact(catalog: Dictionary, state: Dictionary,
		campaign_catalog: Dictionary, campaign_state: Dictionary,
		evidence: Dictionary, global_receipt: String, board: Dictionary,
		proposal: Dictionary) -> bool:
	if proposal.is_empty() or proposal.get("owner_order", []) \
			!= ["covenant", "faction_region"]:
		return false
	var record: Dictionary = proposal.get("covenant_record", {})
	var choice: Dictionary = Model.make_covenant_choice(
		board, String(record.get("covenant_id", "")))
	var after_state: Dictionary = proposal.get("after_state", {})
	return not choice.is_empty() \
		and Model.validate_bind_proposal(
			catalog, state, String(state.get("state_receipt", "")),
			campaign_catalog, campaign_state,
			String(campaign_state.get("state_receipt", "")), CAMPAIGN_SCOPE,
			evidence.get("adapters", []), evidence.get("acceptances", []),
			GLOBAL_SCOPE, global_receipt, board, choice, proposal).is_empty() \
		and Model.validate_state(catalog, after_state).is_empty() \
		and Model.accept_state_checkpoint(
			catalog, after_state,
			String(after_state.get("state_receipt", ""))) == after_state \
		and _receipt_field_exact(proposal, "proposal_receipt")


func _bind_effect_exact(proposal: Dictionary) -> bool:
	var delta: Dictionary = proposal.get("covenant_delta", {})
	var region: Dictionary = proposal.get("faction_region_delta", {})
	var record: Dictionary = proposal.get("covenant_record", {})
	var after_state: Dictionary = proposal.get("after_state", {})
	return int(delta.get("before_revision", -1)) == 0 \
		and int(delta.get("after_revision", -1)) == 1 \
		and String(delta.get("before_phase", "")) == "open" \
		and String(delta.get("after_phase", "")) == "active" \
		and _delta_access(region, 2, 3, 1, 1) \
		and int(record.get("bound_epoch", -1)) == 0 \
		and int(record.get("due_epoch", -1)) == 1 \
		and String(record.get("bound_season", "")) == "spring" \
		and String(record.get("due_season", "")) == "autumn" \
		and String(after_state.get("phase", "")) == "active"


func _bind_replay_identity_exact(exchange: Dictionary, relief: Dictionary,
		watch: Dictionary) -> bool:
	var exchange_record: Dictionary = exchange.get("covenant_record", {})
	var relief_record: Dictionary = relief.get("covenant_record", {})
	var watch_record: Dictionary = watch.get("covenant_record", {})
	var replay: String = String(exchange_record.get("binding_replay_key", ""))
	return replay != "" \
		and replay == String(relief_record.get("binding_replay_key", "")) \
		and replay == String(watch_record.get("binding_replay_key", "")) \
		and replay == _receipt_for([
			CAMPAIGN_SCOPE,
			String(exchange_record.get("binding_campaign_state_receipt", "")),
			"bind",
		]) \
		and String(exchange.get("proposal_receipt", "")) \
		!= String(relief.get("proposal_receipt", "")) \
		and String(exchange.get("proposal_receipt", "")) \
		!= String(watch.get("proposal_receipt", ""))


func _bind_inputs_immutable(catalog: Dictionary, state0: Dictionary,
		campaign_catalog: Dictionary, campaign0: Dictionary,
		network_state: Dictionary, evidence0: Dictionary,
		exchange_bind: Dictionary) -> bool:
	var catalog_bytes: String = _canonical_json(catalog)
	var state_bytes: String = _canonical_json(state0)
	var campaign_catalog_bytes: String = _canonical_json(campaign_catalog)
	var campaign_bytes: String = _canonical_json(campaign0)
	var network_bytes: String = _canonical_json(network_state)
	var evidence_bytes: String = _canonical_json(evidence0)
	var mutated: Dictionary = exchange_bind.duplicate(true)
	var after: Dictionary = mutated.get("after_state", {})
	after["phase"] = "forged"
	return _canonical_json(catalog) == catalog_bytes \
		and _canonical_json(state0) == state_bytes \
		and _canonical_json(campaign_catalog) == campaign_catalog_bytes \
		and _canonical_json(campaign0) == campaign_bytes \
		and _canonical_json(network_state) == network_bytes \
		and _canonical_json(evidence0) == evidence_bytes


func _stale_bind_rejected(catalog: Dictionary, active_state: Dictionary,
		campaign_catalog: Dictionary, campaign0: Dictionary,
		evidence0: Dictionary, global_receipt: String, old_board: Dictionary) -> bool:
	var choice: Dictionary = Model.make_covenant_choice(
		old_board, String(_covenant_option(old_board, "aid").get("option_id", "")))
	return Model.bind_covenant(
		catalog, active_state, String(active_state.get("state_receipt", "")),
		campaign_catalog, campaign0, String(campaign0.get("state_receipt", "")),
		CAMPAIGN_SCOPE, evidence0.get("adapters", []),
		evidence0.get("acceptances", []), GLOBAL_SCOPE, global_receipt,
		old_board, choice).is_empty()


func _mixed_board_choice_rejected(catalog: Dictionary, state0: Dictionary,
		campaign_catalog: Dictionary, campaign0: Dictionary,
		evidence0: Dictionary, global_receipt: String, board0: Dictionary) -> bool:
	var fresh_evidence: Dictionary = _make_evidence(
		campaign_catalog, GLOBAL_SCOPE, global_receipt, "mixed-board", {}, {})
	var fresh_board: Dictionary = Model.make_covenant_board(
		catalog, state0, String(state0.get("state_receipt", "")),
		campaign_catalog, campaign0, String(campaign0.get("state_receipt", "")),
		CAMPAIGN_SCOPE, fresh_evidence.get("adapters", []),
		fresh_evidence.get("acceptances", []), GLOBAL_SCOPE, global_receipt)
	var fresh_choice: Dictionary = Model.make_covenant_choice(
		fresh_board, String(_covenant_option(
			fresh_board, "trade").get("option_id", "")))
	return not fresh_board.is_empty() and not fresh_choice.is_empty() \
		and Model.bind_covenant(
			catalog, state0, String(state0.get("state_receipt", "")),
			campaign_catalog, campaign0, String(campaign0.get("state_receipt", "")),
			CAMPAIGN_SCOPE, evidence0.get("adapters", []),
			evidence0.get("acceptances", []), GLOBAL_SCOPE, global_receipt,
			board0, fresh_choice).is_empty()


func _bind_candidate_hostiles(catalog: Dictionary, state0: Dictionary,
		campaign_catalog: Dictionary, campaign0: Dictionary,
		evidence0: Dictionary, global_receipt: String, board0: Dictionary,
		proposal: Dictionary) -> bool:
	var choice: Dictionary = Model.make_covenant_choice(
		board0, String(_covenant_option(board0, "trade").get("option_id", "")))
	var tampered: Dictionary = proposal.duplicate(true)
	var record: Dictionary = tampered.get("covenant_record", {})
	record["due_epoch"] = 2
	_rehash_typed_record(record, "record_id", "ccr1:", "record_receipt")
	_rehash_proposal(tampered, "proposal_id", "cct1:", "proposal_receipt")
	if Model.validate_bind_proposal(
		catalog, state0, String(state0.get("state_receipt", "")),
		campaign_catalog, campaign0, String(campaign0.get("state_receipt", "")),
		CAMPAIGN_SCOPE, evidence0.get("adapters", []),
		evidence0.get("acceptances", []), GLOBAL_SCOPE, global_receipt,
		board0, choice, tampered).is_empty():
		return false
	var after_tamper: Dictionary = proposal.duplicate(true)
	var after_state: Dictionary = after_tamper.get("after_state", {})
	after_state["phase"] = "terminal"
	_rehash_state(after_state)
	_rehash_proposal(after_tamper, "proposal_id", "cct1:", "proposal_receipt")
	if Model.validate_bind_proposal(
		catalog, state0, String(state0.get("state_receipt", "")),
		campaign_catalog, campaign0, String(campaign0.get("state_receipt", "")),
		CAMPAIGN_SCOPE, evidence0.get("adapters", []),
		evidence0.get("acceptances", []), GLOBAL_SCOPE, global_receipt,
		board0, choice, after_tamper).is_empty():
		return false
	var unknown: Dictionary = proposal.duplicate(true)
	unknown["success"] = true
	return not Model.validate_bind_proposal(
		catalog, state0, String(state0.get("state_receipt", "")),
		campaign_catalog, campaign0, String(campaign0.get("state_receipt", "")),
		CAMPAIGN_SCOPE, evidence0.get("adapters", []),
		evidence0.get("acceptances", []), GLOBAL_SCOPE, global_receipt,
		board0, choice, unknown).is_empty()


func _active_state_hostiles(catalog: Dictionary, active: Dictionary) -> bool:
	var accepted: String = String(active.get("state_receipt", ""))
	var phase: Dictionary = active.duplicate(true)
	phase["phase"] = "terminal"
	_rehash_state(phase)
	if Model.validate_state(catalog, phase).is_empty() \
			or not Model.accept_state_checkpoint(catalog, phase, accepted).is_empty():
		return false
	var replay: Dictionary = active.duplicate(true)
	var record: Dictionary = replay.get("covenant_record", {})
	record["binding_replay_key"] = _external_receipt("forged-replay-key")
	_rehash_typed_record(record, "record_id", "ccr1:", "record_receipt")
	_rehash_state(replay)
	return not Model.validate_state(catalog, replay).is_empty() \
		and Model.accept_state_checkpoint(catalog, replay, accepted).is_empty()


func _projection_observation_independent(catalog: Dictionary,
		active: Dictionary, campaign_catalog: Dictionary,
		campaign_state: Dictionary, projection: Dictionary) -> bool:
	var active_bytes: String = _canonical_json(active)
	var campaign_bytes: String = _canonical_json(campaign_state)
	for _index in 5:
		var observed: Dictionary = Model.project_obligation(
			catalog, active, String(active.get("state_receipt", "")),
			campaign_catalog, campaign_state,
			String(campaign_state.get("state_receipt", "")), CAMPAIGN_SCOPE)
		if _canonical_json(observed) != _canonical_json(projection):
			return false
	return _canonical_json(active) == active_bytes \
		and _canonical_json(campaign_state) == campaign_bytes


func _campaign_scope_hostile(catalog: Dictionary, exchange_active: Dictionary,
		watch_active: Dictionary, campaign_catalog: Dictionary,
		campaign1_open: Dictionary, evidence0: Dictionary,
		global_receipt: String) -> bool:
	var projection: Dictionary = Model.project_obligation(
		catalog, exchange_active, String(exchange_active.get("state_receipt", "")),
		campaign_catalog, campaign1_open,
		String(campaign1_open.get("state_receipt", "")), ALT_CAMPAIGN_SCOPE)
	var original_watch: Dictionary = _adapter_for_key(
		campaign_catalog, evidence0.get("adapters", []), "nightward_fortify")
	var original_acceptance: Dictionary = _acceptance_for(
		evidence0.get("acceptances", []),
		String(original_watch.get("window_id", "")))
	var fresh_signals: Dictionary = (BASE_SIGNALS[
		"nightward_fortify"] as Dictionary).duplicate(true)
	fresh_signals["faction_access"] = 3
	var resolve_target: Dictionary = _fresh_target(
		campaign_catalog, "nightward_fortify", GLOBAL_SCOPE, global_receipt,
		"wrong-campaign-scope-resolve", fresh_signals, {})
	return projection.is_empty() \
		and Model.amend_covenant(
			catalog, watch_active, String(watch_active.get("state_receipt", "")),
			campaign_catalog, campaign1_open,
			String(campaign1_open.get("state_receipt", "")), ALT_CAMPAIGN_SCOPE,
			original_watch, original_acceptance, GLOBAL_SCOPE,
			global_receipt).is_empty() \
		and Model.resolve_covenant(
			catalog, watch_active, String(watch_active.get("state_receipt", "")),
			campaign_catalog, campaign1_open,
			String(campaign1_open.get("state_receipt", "")), ALT_CAMPAIGN_SCOPE,
			resolve_target.get("adapter", {}), resolve_target.get("acceptance", {}),
			GLOBAL_SCOPE, global_receipt, "withdraw").is_empty()


func _make_exchange_chain(base: Dictionary, bind: Dictionary) -> Dictionary:
	var campaign_catalog: Dictionary = base.get("campaign_catalog", {})
	var campaign1_open: Dictionary = base.get("campaign1_open", {})
	var catalog: Dictionary = base.get("catalog", {})
	var global_receipt: String = String(base.get("global_receipt", ""))
	var active: Dictionary = bind.get("after_state", {})
	var after_bind: Dictionary = bind.get(
		"faction_region_delta", {}).get("after_signals", {})
	var evidence: Dictionary = _make_evidence(
		campaign_catalog, GLOBAL_SCOPE, global_receipt, "exchange-rp7", {},
		{"meridian_trade": after_bind})
	var rp7: Dictionary = _rp7_commit_fixture(
		campaign_catalog, campaign1_open, evidence, GLOBAL_SCOPE,
		global_receipt, "trade", 2, "exchange-trade")
	var campaign: Dictionary = (rp7.get("proposal", {}) as Dictionary).get(
		"after_state", {})
	var origin: Dictionary = (rp7.get("proposal", {}) as Dictionary).get(
		"origin_region_delta", {})
	var target: Dictionary = _fresh_target(
		campaign_catalog, "meridian_trade", GLOBAL_SCOPE, global_receipt,
		"exchange-honor", origin.get("after_signals", {}), {})
	var projection: Dictionary = Model.project_obligation(
		catalog, active, String(active.get("state_receipt", "")),
		campaign_catalog, campaign, String(campaign.get("state_receipt", "")),
		CAMPAIGN_SCOPE)
	var honor: Dictionary = Model.resolve_covenant(
		catalog, active, String(active.get("state_receipt", "")),
		campaign_catalog, campaign, String(campaign.get("state_receipt", "")),
		CAMPAIGN_SCOPE, target.get("adapter", {}), target.get("acceptance", {}),
		GLOBAL_SCOPE, global_receipt, "honor")
	return {
		"active": active, "after_bind": after_bind, "evidence": evidence,
		"rp7": rp7, "campaign": campaign, "origin": origin,
		"target": target, "projection": projection, "honor": honor,
	}


func _make_relief_chain(base: Dictionary, bind: Dictionary) -> Dictionary:
	var campaign_catalog: Dictionary = base.get("campaign_catalog", {})
	var campaign1_open: Dictionary = base.get("campaign1_open", {})
	var catalog: Dictionary = base.get("catalog", {})
	var global_receipt: String = String(base.get("global_receipt", ""))
	var active: Dictionary = bind.get("after_state", {})
	var after_bind: Dictionary = bind.get(
		"faction_region_delta", {}).get("after_signals", {})
	var evidence: Dictionary = _make_evidence(
		campaign_catalog, GLOBAL_SCOPE, global_receipt, "relief-rp7", {},
		{"basin_relief": after_bind})
	var rp7: Dictionary = _rp7_commit_fixture(
		campaign_catalog, campaign1_open, evidence, GLOBAL_SCOPE,
		global_receipt, "trade", 2, "relief-trade")
	var campaign: Dictionary = (rp7.get("proposal", {}) as Dictionary).get(
		"after_state", {})
	var projection: Dictionary = Model.project_obligation(
		catalog, active, String(active.get("state_receipt", "")),
		campaign_catalog, campaign, String(campaign.get("state_receipt", "")),
		CAMPAIGN_SCOPE)
	var target: Dictionary = _fresh_target(
		campaign_catalog, "basin_relief", GLOBAL_SCOPE, global_receipt,
		"relief-withdraw", after_bind, {})
	var withdraw: Dictionary = Model.resolve_covenant(
		catalog, active, String(active.get("state_receipt", "")),
		campaign_catalog, campaign, String(campaign.get("state_receipt", "")),
		CAMPAIGN_SCOPE, target.get("adapter", {}), target.get("acceptance", {}),
		GLOBAL_SCOPE, global_receipt, "withdraw")
	return {
		"active": active, "after_bind": after_bind, "evidence": evidence,
		"rp7": rp7, "campaign": campaign, "projection": projection,
		"target": target, "withdraw": withdraw,
	}


func _make_watch_chain(base: Dictionary, bind: Dictionary) -> Dictionary:
	var campaign_catalog: Dictionary = base.get("campaign_catalog", {})
	var campaign1_open: Dictionary = base.get("campaign1_open", {})
	var campaign2_open: Dictionary = base.get("campaign2_open", {})
	var catalog: Dictionary = base.get("catalog", {})
	var global_receipt: String = String(base.get("global_receipt", ""))
	var active: Dictionary = bind.get("after_state", {})
	var after_bind: Dictionary = bind.get(
		"faction_region_delta", {}).get("after_signals", {})
	var due_projection: Dictionary = Model.project_obligation(
		catalog, active, String(active.get("state_receipt", "")),
		campaign_catalog, campaign1_open,
		String(campaign1_open.get("state_receipt", "")), CAMPAIGN_SCOPE)
	var amend_target: Dictionary = _fresh_target(
		campaign_catalog, "nightward_fortify", GLOBAL_SCOPE, global_receipt,
		"watch-amend", after_bind, {})
	var amend: Dictionary = Model.amend_covenant(
		catalog, active, String(active.get("state_receipt", "")),
		campaign_catalog, campaign1_open,
		String(campaign1_open.get("state_receipt", "")), CAMPAIGN_SCOPE,
		amend_target.get("adapter", {}), amend_target.get("acceptance", {}),
		GLOBAL_SCOPE, global_receipt)
	var amended: Dictionary = amend.get("after_state", {})
	var after_amend: Dictionary = amend.get(
		"faction_region_delta", {}).get("after_signals", {})
	var evidence: Dictionary = _make_evidence(
		campaign_catalog, GLOBAL_SCOPE, global_receipt, "watch-rp7", {},
		{"nightward_fortify": after_amend})
	var rp7: Dictionary = _rp7_commit_fixture(
		campaign_catalog, campaign2_open, evidence, GLOBAL_SCOPE,
		global_receipt, "fortify", 2, "watch-fortify")
	var campaign: Dictionary = (rp7.get("proposal", {}) as Dictionary).get(
		"after_state", {})
	var origin: Dictionary = (rp7.get("proposal", {}) as Dictionary).get(
		"origin_region_delta", {})
	var honor_target: Dictionary = _fresh_target(
		campaign_catalog, "nightward_fortify", GLOBAL_SCOPE, global_receipt,
		"watch-honor", origin.get("after_signals", {}), {})
	var honor_projection: Dictionary = Model.project_obligation(
		catalog, amended, String(amended.get("state_receipt", "")),
		campaign_catalog, campaign, String(campaign.get("state_receipt", "")),
		CAMPAIGN_SCOPE)
	var honor: Dictionary = Model.resolve_covenant(
		catalog, amended, String(amended.get("state_receipt", "")),
		campaign_catalog, campaign, String(campaign.get("state_receipt", "")),
		CAMPAIGN_SCOPE, honor_target.get("adapter", {}),
		honor_target.get("acceptance", {}), GLOBAL_SCOPE, global_receipt, "honor")
	return {
		"active": active, "after_bind": after_bind,
		"due_projection": due_projection, "amend_target": amend_target,
		"amend": amend, "amended": amended, "after_amend": after_amend,
		"evidence": evidence, "rp7": rp7, "campaign": campaign,
		"origin": origin, "honor_target": honor_target,
		"honor_projection": honor_projection, "honor": honor,
	}


func _rp7_commit_fixture(catalog: Dictionary, state: Dictionary,
		evidence: Dictionary, global_scope: String, global_receipt: String,
		action: String, capacity: int, tag: String) -> Dictionary:
	var command_checkpoint: String = _external_receipt("rp8-command-%s" % tag)
	var command: Dictionary = Campaign.make_command_anchor(
		COMMAND_SCOPE, command_checkpoint, int(state.get("epoch_index", -1)),
		1, capacity)
	var board: Dictionary = Campaign.make_directive_board(
		catalog, state, String(state.get("state_receipt", "")),
		evidence.get("adapters", []), evidence.get("acceptances", []),
		global_scope, global_receipt, command, COMMAND_SCOPE, command_checkpoint,
		String(command.get("anchor_receipt", "")))
	var option: Dictionary = _rp7_option(board, action)
	var choice: Dictionary = Campaign.make_choice(
		board, String(option.get("option_id", "")))
	var proposal: Dictionary = Campaign.commit_directive(
		catalog, state, String(state.get("state_receipt", "")),
		evidence.get("adapters", []), evidence.get("acceptances", []),
		global_scope, global_receipt, command, COMMAND_SCOPE, command_checkpoint,
		String(command.get("anchor_receipt", "")), board, choice)
	return {
		"state": state, "evidence": evidence, "global_scope": global_scope,
		"global_receipt": global_receipt, "command": command,
		"command_checkpoint": command_checkpoint, "board": board,
		"option": option, "choice": choice, "proposal": proposal,
		"after_state": proposal.get("after_state", {}),
		"origin_region_delta": proposal.get("origin_region_delta", {}),
	}


func _rp7_commit_exact(fixture: Dictionary, catalog: Dictionary,
		action: String, epoch: int) -> bool:
	var state: Dictionary = fixture.get("state", {})
	var evidence: Dictionary = fixture.get("evidence", {})
	var command: Dictionary = fixture.get("command", {})
	var board: Dictionary = fixture.get("board", {})
	var choice: Dictionary = fixture.get("choice", {})
	var proposal: Dictionary = fixture.get("proposal", {})
	var after_state: Dictionary = proposal.get("after_state", {})
	var records: Array = after_state.get("directive_records", [])
	if proposal.is_empty() or records.is_empty() or not (records[-1] is Dictionary):
		return false
	var record: Dictionary = records[-1]
	return int(record.get("epoch_index", -1)) == epoch \
		and String(record.get("action", "")) == action \
		and Campaign.validate_commit_proposal(
			catalog, state, String(state.get("state_receipt", "")),
			evidence.get("adapters", []), evidence.get("acceptances", []),
			String(fixture.get("global_scope", "")),
			String(fixture.get("global_receipt", "")), command, COMMAND_SCOPE,
			String(fixture.get("command_checkpoint", "")),
			String(command.get("anchor_receipt", "")), board, choice,
			proposal).is_empty() \
		and Campaign.accept_state_checkpoint(
			catalog, after_state,
			String(after_state.get("state_receipt", ""))) == after_state


func _due_record_oracle_exact(catalog: Dictionary, active: Dictionary,
		campaign_state: Dictionary, action: String) -> bool:
	var covenant_record: Dictionary = active.get("covenant_record", {})
	var covenant: Dictionary = _covenant_by_action(catalog, action)
	var amendments: Array = active.get("amendment_records", [])
	var due_epoch: int = int(covenant_record.get("due_epoch", -1))
	if not amendments.is_empty() and amendments[0] is Dictionary:
		due_epoch = int((amendments[0] as Dictionary).get("new_due_epoch", -1))
	var matches: int = 0
	for raw_record in campaign_state.get("directive_records", []) as Array:
		if not (raw_record is Dictionary):
			return false
		var record: Dictionary = raw_record
		if int(record.get("epoch_index", -1)) == due_epoch \
				and record.get("directive_id") == covenant.get("directive_id") \
				and record.get("directive_receipt") == covenant.get("directive_receipt") \
				and String(record.get("action", "")) == action \
				and record.get("origin_window_id") == covenant.get("window_id") \
				and record.get("origin_region_id") == covenant.get("region_id") \
				and record.get("faction_id") == covenant.get("faction_id") \
				and record.get("origin_region_scope") \
				== covenant_record.get("binding_region_scope") \
				and record.get("global_network_scope") \
				== covenant_record.get("global_network_scope"):
			matches += 1
	return matches == 1


func _projection_exact_honor(projection: Dictionary, rp7: Dictionary) -> bool:
	var proposal: Dictionary = rp7.get("proposal", {})
	var after_state: Dictionary = proposal.get("after_state", {})
	var records: Array = after_state.get("directive_records", [])
	if records.is_empty() or not (records[-1] is Dictionary):
		return false
	var record: Dictionary = records[-1]
	return String(projection.get("timing_status", "")) == "due" \
		and projection.get("available_actions", []) == ["honor"] \
		and projection.get("matched_directive_record_id") == record.get("record_id") \
		and projection.get("matched_directive_record_receipt") \
		== record.get("record_receipt")


func _exchange_chain_exact(catalog: Dictionary, chain: Dictionary) -> bool:
	var rp7: Dictionary = chain.get("rp7", {})
	var origin: Dictionary = chain.get("origin", {})
	var honor: Dictionary = chain.get("honor", {})
	var target: Dictionary = chain.get("target", {})
	var evidence: Dictionary = chain.get("evidence", {})
	var origin_adapter: Dictionary = _adapter_for_key(
		Campaign.make_catalog(ROOT_SEED), evidence.get("adapters", []),
		"meridian_trade")
	var honor_adapter: Dictionary = target.get("adapter", {})
	var after_state: Dictionary = honor.get("after_state", {})
	return _origin_access(origin, 3, 3) \
		and _resolution_exact(honor, "honored", 3, 3, 1, 0, "superseded") \
		and String(origin_adapter.get("region_checkpoint_receipt", "")) \
		!= String(honor_adapter.get("region_checkpoint_receipt", "")) \
		and String(origin_adapter.get("adapter_receipt", "")) \
		!= String(honor_adapter.get("adapter_receipt", "")) \
		and Model.validate_state(catalog, after_state).is_empty() \
		and not rp7.is_empty()


func _relief_future_infeasible(base: Dictionary, relief: Dictionary) -> bool:
	var campaign_catalog: Dictionary = base.get("campaign_catalog", {})
	var campaign2_open: Dictionary = base.get("campaign2_open", {})
	var global_receipt: String = String(base.get("global_receipt", ""))
	var evidence: Dictionary = _make_evidence(
		campaign_catalog, GLOBAL_SCOPE, global_receipt, "relief-winter", {}, {})
	var fixture: Dictionary = _rp7_board_fixture(
		campaign_catalog, campaign2_open, evidence, GLOBAL_SCOPE,
		global_receipt, 2, "relief-winter")
	var board: Dictionary = fixture.get("board", {})
	var active: Dictionary = relief.get("active", {})
	var target: Dictionary = relief.get("target", {})
	var committed: Dictionary = relief.get("campaign", {})
	return (board.get("options", []) as Array).size() == 1 \
		and not _rp7_option(board, "fortify").is_empty() \
		and _rp7_option(board, "aid").is_empty() \
		and Model.amend_covenant(
			base.get("catalog", {}), active, String(active.get("state_receipt", "")),
			campaign_catalog, committed, String(committed.get("state_receipt", "")),
			CAMPAIGN_SCOPE, target.get("adapter", {}), target.get("acceptance", {}),
			GLOBAL_SCOPE, global_receipt).is_empty()


func _watch_amend_exact(catalog: Dictionary, campaign_catalog: Dictionary,
		campaign1_open: Dictionary, global_receipt: String,
		watch: Dictionary) -> bool:
	var active: Dictionary = watch.get("active", {})
	var target: Dictionary = watch.get("amend_target", {})
	var amend: Dictionary = watch.get("amend", {})
	var record: Dictionary = amend.get("amendment_record", {})
	return not amend.is_empty() \
		and Model.validate_amend_proposal(
			catalog, active, String(active.get("state_receipt", "")),
			campaign_catalog, campaign1_open,
			String(campaign1_open.get("state_receipt", "")), CAMPAIGN_SCOPE,
			target.get("adapter", {}), target.get("acceptance", {}),
			GLOBAL_SCOPE, global_receipt, amend).is_empty() \
		and _delta_access(amend.get("faction_region_delta", {}), 3, 2, -1, -1) \
		and int(record.get("old_due_epoch", -1)) == 1 \
		and int(record.get("new_due_epoch", -1)) == 2 \
		and String(record.get("new_due_season", "")) == "winter"


func _watch_amend_limit_exact(catalog: Dictionary,
		campaign_catalog: Dictionary, campaign1_open: Dictionary,
		global_receipt: String, watch: Dictionary) -> bool:
	var amended: Dictionary = watch.get("amended", {})
	var target: Dictionary = watch.get("amend_target", {})
	var projection: Dictionary = Model.project_obligation(
		catalog, amended, String(amended.get("state_receipt", "")),
		campaign_catalog, campaign1_open,
		String(campaign1_open.get("state_receipt", "")), CAMPAIGN_SCOPE)
	return String(projection.get("timing_status", "")) == "not_due" \
		and (projection.get("available_actions", []) as Array).is_empty() \
		and Model.amend_covenant(
			catalog, amended, String(amended.get("state_receipt", "")),
			campaign_catalog, campaign1_open,
			String(campaign1_open.get("state_receipt", "")), CAMPAIGN_SCOPE,
			target.get("adapter", {}), target.get("acceptance", {}),
			GLOBAL_SCOPE, global_receipt).is_empty()


func _watch_honor_exact(catalog: Dictionary, campaign_catalog: Dictionary,
		global_receipt: String, watch: Dictionary) -> bool:
	var amended: Dictionary = watch.get("amended", {})
	var campaign: Dictionary = watch.get("campaign", {})
	var target: Dictionary = watch.get("honor_target", {})
	var honor: Dictionary = watch.get("honor", {})
	var projection: Dictionary = watch.get("honor_projection", {})
	return _projection_exact_honor(projection, watch.get("rp7", {})) \
		and _resolution_exact(honor, "honored", 3, 3, 1, 0, "superseded") \
		and Model.validate_resolution_proposal(
			catalog, amended, String(amended.get("state_receipt", "")),
			campaign_catalog, campaign, String(campaign.get("state_receipt", "")),
			CAMPAIGN_SCOPE, target.get("adapter", {}), target.get("acceptance", {}),
			GLOBAL_SCOPE, global_receipt, "honor", honor).is_empty()


func _make_due_hostiles(base: Dictionary, exchange_bind: Dictionary,
		exchange: Dictionary) -> Dictionary:
	var campaign_catalog: Dictionary = base.get("campaign_catalog", {})
	var campaign0: Dictionary = base.get("campaign0", {})
	var campaign1_open: Dictionary = base.get("campaign1_open", {})
	var catalog: Dictionary = base.get("catalog", {})
	var global_receipt: String = String(base.get("global_receipt", ""))
	var active: Dictionary = exchange_bind.get("after_state", {})
	var after_bind: Dictionary = exchange_bind.get(
		"faction_region_delta", {}).get("after_signals", {})
	var correct_target: Dictionary = exchange.get("target", {})

	var alt_region_evidence: Dictionary = _make_evidence(
		campaign_catalog, GLOBAL_SCOPE, global_receipt, "alt-region",
		{"meridian_trade": "rp7_region_meridian_trade_alt"},
		{"meridian_trade": after_bind})
	var alt_region_rp7: Dictionary = _rp7_commit_fixture(
		campaign_catalog, campaign1_open, alt_region_evidence, GLOBAL_SCOPE,
		global_receipt, "trade", 2, "alt-region-trade")
	var alt_region_campaign: Dictionary = alt_region_rp7.get("after_state", {})
	var alt_region: Dictionary = _due_hostile_result(
		catalog, active, campaign_catalog, alt_region_campaign,
		correct_target, global_receipt)

	var alt_global_receipt: String = _external_receipt("rp8-alt-global")
	var alt_global_evidence: Dictionary = _make_evidence(
		campaign_catalog, ALT_GLOBAL_SCOPE, alt_global_receipt, "alt-global", {},
		{"meridian_trade": after_bind})
	var alt_global_rp7: Dictionary = _rp7_commit_fixture(
		campaign_catalog, campaign1_open, alt_global_evidence, ALT_GLOBAL_SCOPE,
		alt_global_receipt, "trade", 2, "alt-global-trade")
	var alt_global_campaign: Dictionary = alt_global_rp7.get("after_state", {})
	var alt_global: Dictionary = _due_hostile_result(
		catalog, active, campaign_catalog, alt_global_campaign,
		correct_target, global_receipt)

	var bind_adapter: Dictionary = _adapter_for_key(
		campaign_catalog, (base.get("evidence0", {}) as Dictionary).get(
			"adapters", []), "meridian_trade")
	var checkpoint_overrides := {
		"meridian_trade": String(bind_adapter.get("region_checkpoint_receipt", "")),
	}
	var stale_checkpoint_evidence: Dictionary = _make_evidence(
		campaign_catalog, GLOBAL_SCOPE, global_receipt, "stale-link1-checkpoint", {},
		{"meridian_trade": after_bind}, checkpoint_overrides)
	var stale_checkpoint_rp7: Dictionary = _rp7_commit_fixture(
		campaign_catalog, campaign1_open, stale_checkpoint_evidence, GLOBAL_SCOPE,
		global_receipt, "trade", 2, "stale-link1-checkpoint")
	var stale_checkpoint_campaign: Dictionary = stale_checkpoint_rp7.get(
		"after_state", {})
	var stale_checkpoint_result: Dictionary = _due_hostile_result(
		catalog, active, campaign_catalog, stale_checkpoint_campaign,
		correct_target, global_receipt)
	var stale_adapter_rp7: Dictionary = _rp7_commit_fixture(
		campaign_catalog, campaign1_open, base.get("evidence0", {}), GLOBAL_SCOPE,
		global_receipt, "trade", 2, "stale-link1-adapter")
	var stale_adapter_campaign: Dictionary = stale_adapter_rp7.get("after_state", {})
	var stale_adapter_result: Dictionary = _due_hostile_result(
		catalog, active, campaign_catalog, stale_adapter_campaign,
		correct_target, global_receipt)

	var correct_evidence: Dictionary = exchange.get("evidence", {})
	var origin_adapter: Dictionary = _adapter_for_key(
		campaign_catalog, correct_evidence.get("adapters", []), "meridian_trade")
	var origin_acceptance: Dictionary = _acceptance_for(
		correct_evidence.get("acceptances", []),
		String(origin_adapter.get("window_id", "")))
	var campaign: Dictionary = exchange.get("campaign", {})
	var link2_adapter_reuse: Dictionary = Model.resolve_covenant(
		catalog, active, String(active.get("state_receipt", "")),
		campaign_catalog, campaign, String(campaign.get("state_receipt", "")),
		CAMPAIGN_SCOPE, origin_adapter, origin_acceptance, GLOBAL_SCOPE,
		global_receipt, "honor")
	var origin_after: Dictionary = (exchange.get("origin", {}) as Dictionary).get(
		"after_signals", {})
	var link2_checkpoint_target: Dictionary = _fresh_target(
		campaign_catalog, "meridian_trade", GLOBAL_SCOPE, global_receipt,
		"link2-checkpoint", origin_after, {},
		String(origin_adapter.get("region_checkpoint_receipt", "")))
	var link2_checkpoint_reuse: Dictionary = Model.resolve_covenant(
		catalog, active, String(active.get("state_receipt", "")),
		campaign_catalog, campaign, String(campaign.get("state_receipt", "")),
		CAMPAIGN_SCOPE, link2_checkpoint_target.get("adapter", {}),
		link2_checkpoint_target.get("acceptance", {}), GLOBAL_SCOPE,
		global_receipt, "honor")

	var wrong_action_evidence: Dictionary = _make_evidence(
		campaign_catalog, GLOBAL_SCOPE, global_receipt, "wrong-action", {}, {})
	var wrong_action_rp7: Dictionary = _rp7_commit_fixture(
		campaign_catalog, campaign1_open, wrong_action_evidence, GLOBAL_SCOPE,
		global_receipt, "aid", 3, "wrong-action-aid")
	var wrong_action_campaign: Dictionary = wrong_action_rp7.get("after_state", {})
	var wrong_action_result: Dictionary = _due_hostile_result(
		catalog, active, campaign_catalog, wrong_action_campaign,
		correct_target, global_receipt)
	var wrong_epoch_rp7: Dictionary = _rp7_commit_fixture(
		campaign_catalog, campaign0, base.get("evidence0", {}), GLOBAL_SCOPE,
		global_receipt, "trade", 3, "wrong-epoch-trade")
	var wrong_epoch_campaign: Dictionary = wrong_epoch_rp7.get("after_state", {})
	var wrong_epoch_projection: Dictionary = Model.project_obligation(
		catalog, active, String(active.get("state_receipt", "")),
		campaign_catalog, wrong_epoch_campaign,
		String(wrong_epoch_campaign.get("state_receipt", "")), CAMPAIGN_SCOPE)
	var forged_campaign: Dictionary = (exchange.get(
		"campaign", {}) as Dictionary).duplicate(true)
	var forged_records: Array = forged_campaign.get("directive_records", [])
	if not forged_records.is_empty() and forged_records[0] is Dictionary:
		var forged_record: Dictionary = forged_records[0]
		forged_record["directive_receipt"] = _external_receipt(
			"forged-due-directive")
	_rehash_state(forged_campaign)
	var original_campaign: Dictionary = exchange.get("campaign", {})
	var forged_checkpoint_reject: bool = Campaign.accept_state_checkpoint(
		campaign_catalog, forged_campaign,
		String(original_campaign.get("state_receipt", ""))).is_empty()

	return {
		"alt_region": alt_region, "alt_global": alt_global,
		"alt_region_campaign": alt_region_campaign,
		"link1_ok": _due_owner_hostile_exact(stale_checkpoint_result)
			and _due_owner_hostile_exact(stale_adapter_result),
		"link2_ok": link2_adapter_reuse.is_empty()
			and link2_checkpoint_reuse.is_empty(),
		"semantic_ok": _due_owner_hostile_exact(wrong_action_result)
			and String(wrong_epoch_projection.get("timing_status", "")) == "not_due"
			and (wrong_epoch_projection.get("available_actions", []) as Array).is_empty()
			and forged_checkpoint_reject,
	}


func _due_hostile_result(catalog: Dictionary, active: Dictionary,
		campaign_catalog: Dictionary, campaign_state: Dictionary,
		correct_target: Dictionary, global_receipt: String) -> Dictionary:
	var accepted: Dictionary = Campaign.accept_state_checkpoint(
		campaign_catalog, campaign_state,
		String(campaign_state.get("state_receipt", "")))
	var projection: Dictionary = Model.project_obligation(
		catalog, active, String(active.get("state_receipt", "")),
		campaign_catalog, campaign_state,
		String(campaign_state.get("state_receipt", "")), CAMPAIGN_SCOPE)
	var honor: Dictionary = Model.resolve_covenant(
		catalog, active, String(active.get("state_receipt", "")),
		campaign_catalog, campaign_state,
		String(campaign_state.get("state_receipt", "")), CAMPAIGN_SCOPE,
		correct_target.get("adapter", {}), correct_target.get("acceptance", {}),
		GLOBAL_SCOPE, global_receipt, "honor")
	return {
		"campaign": campaign_state, "accepted": accepted,
		"projection": projection, "honor": honor,
	}


func _due_owner_hostile_exact(result: Dictionary) -> bool:
	var campaign: Dictionary = result.get("campaign", {})
	var accepted: Dictionary = result.get("accepted", {})
	var projection: Dictionary = result.get("projection", {})
	return not campaign.is_empty() and accepted == campaign \
		and projection.get("available_actions", []) == ["withdraw"] \
		and (result.get("honor", {}) as Dictionary).is_empty()


func _make_terminal_variants(base: Dictionary, exchange_bind: Dictionary,
		relief_bind: Dictionary, exchange: Dictionary, relief: Dictionary,
		due_hostiles: Dictionary) -> Dictionary:
	var campaign_catalog: Dictionary = base.get("campaign_catalog", {})
	var catalog: Dictionary = base.get("catalog", {})
	var global_receipt: String = String(base.get("global_receipt", ""))
	var exchange_active: Dictionary = exchange_bind.get("after_state", {})
	var exchange_terminal: Dictionary = _advance_campaign_to_terminal(
		campaign_catalog, exchange.get("campaign", {}))
	var exchange_target: Dictionary = _fresh_target(
		campaign_catalog, "meridian_trade", GLOBAL_SCOPE, global_receipt,
		"terminal-exchange", (exchange.get("origin", {}) as Dictionary).get(
			"after_signals", {}), {})
	var exchange_honor: Dictionary = Model.resolve_covenant(
		catalog, exchange_active, String(exchange_active.get("state_receipt", "")),
		campaign_catalog, exchange_terminal,
		String(exchange_terminal.get("state_receipt", "")), CAMPAIGN_SCOPE,
		exchange_target.get("adapter", {}), exchange_target.get("acceptance", {}),
		GLOBAL_SCOPE, global_receipt, "honor")

	var relief_active: Dictionary = relief_bind.get("after_state", {})
	var relief_terminal: Dictionary = _advance_campaign_to_terminal(
		campaign_catalog, relief.get("campaign", {}))
	var floor_signals: Dictionary = (relief.get(
		"after_bind", {}) as Dictionary).duplicate(true)
	floor_signals["faction_access"] = 0
	var relief_target: Dictionary = _fresh_target(
		campaign_catalog, "basin_relief", GLOBAL_SCOPE, global_receipt,
		"terminal-relief", floor_signals, {})
	var relief_withdraw: Dictionary = Model.resolve_covenant(
		catalog, relief_active, String(relief_active.get("state_receipt", "")),
		campaign_catalog, relief_terminal,
		String(relief_terminal.get("state_receipt", "")), CAMPAIGN_SCOPE,
		relief_target.get("adapter", {}), relief_target.get("acceptance", {}),
		GLOBAL_SCOPE, global_receipt, "withdraw")

	var mismatch_campaign: Dictionary = due_hostiles.get("alt_region_campaign", {})
	var mismatch_terminal: Dictionary = _advance_campaign_to_terminal(
		campaign_catalog, mismatch_campaign)
	var mismatch_target: Dictionary = _fresh_target(
		campaign_catalog, "meridian_trade", GLOBAL_SCOPE, global_receipt,
		"terminal-owner-mismatch", (exchange.get(
			"origin", {}) as Dictionary).get("after_signals", {}), {})
	var mismatch_withdraw: Dictionary = Model.resolve_covenant(
		catalog, exchange_active, String(exchange_active.get("state_receipt", "")),
		campaign_catalog, mismatch_terminal,
		String(mismatch_terminal.get("state_receipt", "")), CAMPAIGN_SCOPE,
		mismatch_target.get("adapter", {}), mismatch_target.get("acceptance", {}),
		GLOBAL_SCOPE, global_receipt, "withdraw")
	var mismatch_honor: Dictionary = Model.resolve_covenant(
		catalog, exchange_active, String(exchange_active.get("state_receipt", "")),
		campaign_catalog, mismatch_terminal,
		String(mismatch_terminal.get("state_receipt", "")), CAMPAIGN_SCOPE,
		mismatch_target.get("adapter", {}), mismatch_target.get("acceptance", {}),
		GLOBAL_SCOPE, global_receipt, "honor")
	return {
		"exchange_campaign": exchange_terminal, "exchange_target": exchange_target,
		"exchange_honor": exchange_honor,
		"relief_campaign": relief_terminal, "relief_target": relief_target,
		"relief_withdraw": relief_withdraw,
		"mismatch_campaign": mismatch_terminal,
		"mismatch_target": mismatch_target,
		"mismatch_withdraw": mismatch_withdraw,
		"mismatch_honor": mismatch_honor,
	}


func _advance_campaign_to_terminal(catalog: Dictionary,
		start: Dictionary) -> Dictionary:
	var current: Dictionary = start.duplicate(true)
	while not current.is_empty() and int(current.get("epoch_index", -1)) < 3:
		var transition: Dictionary = Campaign.advance_epoch(
			catalog, current, String(current.get("state_receipt", "")))
		current = transition.get("after_state", {})
	return current


func _terminal_replay_rejected(base: Dictionary, terminal_proposal: Dictionary,
		exchange: Dictionary) -> bool:
	var catalog: Dictionary = base.get("catalog", {})
	var campaign_catalog: Dictionary = base.get("campaign_catalog", {})
	var global_receipt: String = String(base.get("global_receipt", ""))
	var terminal_state: Dictionary = terminal_proposal.get("after_state", {})
	var campaign: Dictionary = exchange.get("campaign", {})
	var target: Dictionary = exchange.get("target", {})
	if terminal_state.is_empty():
		return false
	return Model.resolve_covenant(
		catalog, terminal_state, String(terminal_state.get("state_receipt", "")),
		campaign_catalog, campaign, String(campaign.get("state_receipt", "")),
		CAMPAIGN_SCOPE, target.get("adapter", {}), target.get("acceptance", {}),
		GLOBAL_SCOPE, global_receipt, "honor").is_empty() \
		and Model.resolve_covenant(
			catalog, terminal_state, String(terminal_state.get("state_receipt", "")),
			campaign_catalog, campaign, String(campaign.get("state_receipt", "")),
			CAMPAIGN_SCOPE, target.get("adapter", {}), target.get("acceptance", {}),
			GLOBAL_SCOPE, global_receipt, "withdraw").is_empty() \
		and Model.amend_covenant(
			catalog, terminal_state, String(terminal_state.get("state_receipt", "")),
			campaign_catalog, campaign, String(campaign.get("state_receipt", "")),
			CAMPAIGN_SCOPE, target.get("adapter", {}), target.get("acceptance", {}),
			GLOBAL_SCOPE, global_receipt).is_empty()


func _roundtrip_continuation_exact(base: Dictionary, watch: Dictionary) -> bool:
	var catalog: Dictionary = base.get("catalog", {})
	var campaign_catalog: Dictionary = base.get("campaign_catalog", {})
	var global_receipt: String = String(base.get("global_receipt", ""))
	var amended_value: Variant = JSON.parse_string(JSON.stringify(
		watch.get("amended", {})))
	var campaign_value: Variant = JSON.parse_string(JSON.stringify(
		watch.get("campaign", {})))
	var target_value: Variant = JSON.parse_string(JSON.stringify(
		watch.get("honor_target", {})))
	var honor_value: Variant = JSON.parse_string(JSON.stringify(
		watch.get("honor", {})))
	if not (amended_value is Dictionary) or not (campaign_value is Dictionary) \
			or not (target_value is Dictionary) or not (honor_value is Dictionary):
		return false
	var amended_json: Dictionary = amended_value
	amended_json["revision"] = 2.0
	var amendment_records: Array = amended_json.get("amendment_records", [])
	if amendment_records.is_empty() or not (amendment_records[0] is Dictionary):
		return false
	var amendment: Dictionary = amendment_records[0]
	amendment["amended_epoch"] = 1.0
	amendment["new_due_epoch"] = 2.0
	var normalized_amended: Dictionary = Model.normalize_state(catalog, amended_json)
	var campaign_json: Dictionary = campaign_value
	var normalized_campaign: Dictionary = Campaign.normalize_state(
		campaign_catalog, campaign_json)
	var target_json: Dictionary = target_value
	var adapter: Dictionary = target_json.get("adapter", {})
	var acceptance: Dictionary = target_json.get("acceptance", {})
	if normalized_amended.is_empty() or normalized_campaign.is_empty() \
			or adapter.is_empty() or acceptance.is_empty():
		return false
	var continued: Dictionary = Model.resolve_covenant(
		catalog, normalized_amended,
		String(normalized_amended.get("state_receipt", "")), campaign_catalog,
		normalized_campaign, String(normalized_campaign.get("state_receipt", "")),
		CAMPAIGN_SCOPE, adapter, acceptance, GLOBAL_SCOPE, global_receipt, "honor")
	var honor_json: Dictionary = honor_value
	return typeof(normalized_amended.get("revision")) == TYPE_INT \
		and typeof((normalized_amended.get(
			"amendment_records", []) as Array)[0].get("new_due_epoch")) == TYPE_INT \
		and String(continued.get("proposal_receipt", "")) \
		== String((watch.get("honor", {}) as Dictionary).get(
			"proposal_receipt", "")) \
		and Model.validate_resolution_proposal(
			catalog, normalized_amended,
			String(normalized_amended.get("state_receipt", "")), campaign_catalog,
			normalized_campaign, String(normalized_campaign.get("state_receipt", "")),
			CAMPAIGN_SCOPE, adapter, acceptance, GLOBAL_SCOPE, global_receipt,
			"honor", honor_json).is_empty()


func _numeric_and_unknown_hostiles(catalog: Dictionary,
		state0: Dictionary) -> bool:
	var integral: Dictionary = state0.duplicate(true)
	integral["revision"] = 0.0
	var normalized: Dictionary = Model.normalize_state(catalog, integral)
	if normalized.is_empty() or typeof(normalized.get("revision")) != TYPE_INT:
		return false
	var hostile_values: Array = [0.5, NAN, INF, -INF, 1.0e100, true, "0"]
	for hostile in hostile_values:
		var candidate: Dictionary = state0.duplicate(true)
		candidate["revision"] = hostile
		if Model.validate_state(catalog, candidate).is_empty() \
				or not Model.normalize_state(catalog, candidate).is_empty():
			return false
	var unknown: Dictionary = state0.duplicate(true)
	unknown["display_name"] = "forbidden"
	return not Model.validate_state(catalog, unknown).is_empty() \
		and Model.normalize_state(catalog, unknown).is_empty()


func _canonical_budget_hostiles(board: Dictionary) -> bool:
	var oversized: Array[String] = []
	for index in 257:
		oversized.append("n%d" % index)
	var deep: Variant = "leaf"
	for _index in 34:
		deep = [deep]
	var node_heavy: Array = []
	for outer in 256:
		var row: Array[int] = []
		for inner in 9:
			row.append(outer * 9 + inner)
		node_heavy.append(row)
	var cyclic := {}
	cyclic["self"] = cyclic
	var hostile_board: Dictionary = board.duplicate(true)
	var cyclic_option := {}
	cyclic_option["self"] = cyclic_option
	hostile_board["options"] = [cyclic_option]
	var trade: Dictionary = _covenant_option(board, "trade")
	return Model._canonical_json(oversized) == "" \
		and Model._canonical_json("x".repeat(1025)) == "" \
		and Model._canonical_json(deep) == "" \
		and Model._canonical_json(node_heavy) == "" \
		and Model._canonical_json(cyclic) == "" \
		and Model.make_covenant_choice(
			hostile_board, String(trade.get("option_id", ""))).is_empty()


func _receipt_suite_exact(catalog: Dictionary, board: Dictionary,
		bind: Dictionary, amend: Dictionary, resolution: Dictionary) -> bool:
	var terminal: Dictionary = resolution.get("after_state", {})
	return _catalog_receipts_exact(catalog) \
		and _receipt_field_exact(board, "board_receipt") \
		and _receipt_field_exact(bind, "proposal_receipt") \
		and _receipt_field_exact(amend, "proposal_receipt") \
		and _receipt_field_exact(resolution, "proposal_receipt") \
		and _receipt_field_exact(terminal, "state_receipt") \
		and _json_authority_safe(board) and _json_authority_safe(bind) \
		and _json_authority_safe(amend) and _json_authority_safe(resolution) \
		and not _contains_forbidden_authority(
			[board, bind, amend, resolution],
			["arrival", "launch", "success", "camera", "zoom", "score",
				"owner_name", "display_name"])


func _make_evidence(catalog: Dictionary, global_scope: String,
		global_receipt: String, tag: String, scope_overrides: Dictionary,
		signal_overrides: Dictionary,
		checkpoint_overrides: Dictionary = {}) -> Dictionary:
	var adapters: Array[Dictionary] = []
	var acceptances: Array[Dictionary] = []
	for raw_key in WINDOW_KEYS:
		var key: String = String(raw_key)
		var window: Dictionary = _window_by_key(catalog, key)
		var scope: String = String(scope_overrides.get(
			key, "rp7_region_%s" % key))
		var checkpoint: String = String(checkpoint_overrides.get(
			key, _external_receipt("%s-%s" % [tag, key])))
		var signals: Dictionary = (BASE_SIGNALS[key] as Dictionary).duplicate(true)
		if signal_overrides.has(key):
			signals = (signal_overrides[key] as Dictionary).duplicate(true)
		var adapter: Dictionary = Campaign.make_window_adapter(
			catalog, key, scope, checkpoint, global_scope, global_receipt, signals)
		var acceptance: Dictionary = Campaign.make_window_acceptance(
			String(window.get("window_id", "")), scope, checkpoint,
			String(adapter.get("adapter_receipt", "")))
		if adapter.is_empty() or acceptance.is_empty():
			return {}
		adapters.append(adapter)
		acceptances.append(acceptance)
	return {"adapters": adapters, "acceptances": acceptances}


func _fresh_target(catalog: Dictionary, key: String, global_scope: String,
		global_receipt: String, tag: String, signals_value: Variant,
		scope_overrides: Dictionary, checkpoint_override: String = "") -> Dictionary:
	if not (signals_value is Dictionary):
		return {}
	var window: Dictionary = _window_by_key(catalog, key)
	var scope: String = String(scope_overrides.get(
		key, "rp7_region_%s" % key))
	var checkpoint: String = checkpoint_override if checkpoint_override != "" \
		else _external_receipt("fresh-%s-%s" % [tag, key])
	var adapter: Dictionary = Campaign.make_window_adapter(
		catalog, key, scope, checkpoint, global_scope, global_receipt,
		(signals_value as Dictionary).duplicate(true))
	var acceptance: Dictionary = Campaign.make_window_acceptance(
		String(window.get("window_id", "")), scope, checkpoint,
		String(adapter.get("adapter_receipt", "")))
	if adapter.is_empty() or acceptance.is_empty():
		return {}
	return {"adapter": adapter, "acceptance": acceptance}


func _rp7_board_fixture(catalog: Dictionary, state: Dictionary,
		evidence: Dictionary, global_scope: String, global_receipt: String,
		capacity: int, tag: String) -> Dictionary:
	var checkpoint: String = _external_receipt("rp8-command-%s" % tag)
	var command: Dictionary = Campaign.make_command_anchor(
		COMMAND_SCOPE, checkpoint, int(state.get("epoch_index", -1)), 1, capacity)
	var board: Dictionary = Campaign.make_directive_board(
		catalog, state, String(state.get("state_receipt", "")),
		evidence.get("adapters", []), evidence.get("acceptances", []),
		global_scope, global_receipt, command, COMMAND_SCOPE, checkpoint,
		String(command.get("anchor_receipt", "")))
	return {"checkpoint": checkpoint, "command": command, "board": board}


func _window_by_key(catalog: Dictionary, key: String) -> Dictionary:
	for raw_window in catalog.get("windows", []) as Array:
		if raw_window is Dictionary:
			var window: Dictionary = raw_window
			if String(window.get("window_key", "")) == key:
				return window
	return {}


func _directive_by_action(catalog: Dictionary, action: String) -> Dictionary:
	for raw_directive in catalog.get("directives", []) as Array:
		if raw_directive is Dictionary:
			var directive: Dictionary = raw_directive
			if String(directive.get("action", "")) == action:
				return directive
	return {}


func _covenant_by_action(catalog: Dictionary, action: String) -> Dictionary:
	for raw_covenant in catalog.get("covenants", []) as Array:
		if raw_covenant is Dictionary:
			var covenant: Dictionary = raw_covenant
			if String(covenant.get("required_action", "")) == action:
				return covenant
	return {}


func _covenant_option(board: Dictionary, action: String) -> Dictionary:
	for raw_option in board.get("options", []) as Array:
		if raw_option is Dictionary:
			var option: Dictionary = raw_option
			if String(option.get("required_action", "")) == action:
				return option
	return {}


func _rp7_option(board: Dictionary, action: String) -> Dictionary:
	for raw_option in board.get("options", []) as Array:
		if raw_option is Dictionary:
			var option: Dictionary = raw_option
			if String(option.get("action", "")) == action:
				return option
	return {}


func _adapter_for_key(catalog: Dictionary, adapters: Array,
		key: String) -> Dictionary:
	var window: Dictionary = _window_by_key(catalog, key)
	for raw_adapter in adapters:
		if raw_adapter is Dictionary:
			var adapter: Dictionary = raw_adapter
			if String(adapter.get("window_id", "")) \
					== String(window.get("window_id", "")):
				return adapter
	return {}


func _acceptance_for(acceptances: Array, window_id: String) -> Dictionary:
	for raw_acceptance in acceptances:
		if raw_acceptance is Dictionary:
			var acceptance: Dictionary = raw_acceptance
			if String(acceptance.get("window_id", "")) == window_id:
				return acceptance
	return {}


func _origin_access(origin: Dictionary, before: int, after: int) -> bool:
	return int((origin.get("before_signals", {}) as Dictionary).get(
		"faction_access", -1)) == before \
		and int((origin.get("after_signals", {}) as Dictionary).get(
			"faction_access", -1)) == after


func _delta_access(delta: Dictionary, before: int, after: int,
		requested: int, applied: int) -> bool:
	return int((delta.get("before_signals", {}) as Dictionary).get(
		"faction_access", -1)) == before \
		and int((delta.get("after_signals", {}) as Dictionary).get(
			"faction_access", -1)) == after \
		and int(delta.get("access_requested", 99)) == requested \
		and int(delta.get("access_applied", 99)) == applied


func _resolution_exact(proposal: Dictionary, resolution: String,
		before: int, after: int, requested: int, applied: int,
		status: String) -> bool:
	if proposal.is_empty():
		return false
	var record: Dictionary = proposal.get("resolution_record", {})
	var after_state: Dictionary = proposal.get("after_state", {})
	return proposal.get("owner_order", []) == ["covenant", "faction_region"] \
		and String(record.get("resolution", "")) == resolution \
		and String(record.get("region_delta_status", "")) == status \
		and _delta_access(proposal.get("faction_region_delta", {}),
			before, after, requested, applied) \
		and String(after_state.get("phase", "")) == "terminal" \
		and _receipt_field_exact(proposal, "proposal_receipt")


func _contains_forbidden_authority(value: Variant, forbidden: Array) -> bool:
	if value is Dictionary:
		for raw_key in value:
			var key: String = String(raw_key).to_lower()
			for raw_forbidden in forbidden:
				if key == String(raw_forbidden).to_lower():
					return true
			if _contains_forbidden_authority((value as Dictionary)[raw_key], forbidden):
				return true
	elif value is Array:
		for item in value:
			if _contains_forbidden_authority(item, forbidden):
				return true
	return false


func _json_authority_safe(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_INT:
			var integer: int = int(value)
			return integer >= -MAX_SAFE_JSON_INT and integer <= MAX_SAFE_JSON_INT
		TYPE_FLOAT:
			var number: float = float(value)
			return is_finite(number) and number == floor(number) \
				and absf(number) <= float(MAX_SAFE_JSON_INT)
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


func _external_receipt(label: String) -> String:
	return _receipt_for(["rp7-external-owner-checkpoint", label])


func _rehash_state(state: Dictionary) -> void:
	state.erase("state_receipt")
	state["state_receipt"] = _receipt_for(state)


func _rehash_typed_record(record: Dictionary, id_key: String,
		prefix: String, receipt_key: String) -> void:
	record.erase(id_key)
	record.erase(receipt_key)
	var digest: String = _sha256_hex(_canonical_json(record))
	record[id_key] = prefix + digest.substr(0, 16)
	record[receipt_key] = _receipt_for(record)


func _rehash_proposal(proposal: Dictionary, id_key: String,
		prefix: String, receipt_key: String) -> void:
	proposal.erase(id_key)
	proposal.erase(receipt_key)
	var digest: String = _sha256_hex(_canonical_json(proposal))
	proposal[id_key] = prefix + digest.substr(0, 16)
	proposal[receipt_key] = _receipt_for(proposal)


func _receipt_field_exact(data: Dictionary, receipt_key: String) -> bool:
	var base: Dictionary = data.duplicate(true)
	base.erase(receipt_key)
	return String(data.get(receipt_key, "")) == _receipt_for(base)


func _receipt_for(value: Variant) -> String:
	var encoded: String = _canonical_json(value)
	var digest: String = _sha256_hex(encoded)
	return "sha256:" + digest if digest != "" else ""


func _sha256_hex(text: String) -> String:
	if text == "":
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK \
			or context.update(text.to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()


func _canonical_json(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		TYPE_INT:
			var integer: int = int(value)
			if integer < -MAX_SAFE_JSON_INT or integer > MAX_SAFE_JSON_INT:
				return ""
			return str(integer)
		TYPE_FLOAT:
			var number: float = float(value)
			if not is_finite(number) or number != floor(number) \
					or absf(number) > float(MAX_SAFE_JSON_INT):
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
			var fields: Array[String] = []
			for key in keys:
				var encoded: String = _canonical_json(data[key])
				if encoded == "":
					return ""
				fields.append("%s:%s" % [JSON.stringify(key), encoded])
			return "{" + ",".join(fields) + "}"
	return ""
