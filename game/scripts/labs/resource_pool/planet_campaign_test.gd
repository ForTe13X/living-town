extends Node

const Model = preload("res://scripts/labs/resource_pool/PlanetCampaignModel.gd")
const Address = preload("res://scripts/labs/resource_pool/ScaleAddress.gd")
const Routes = preload("res://scripts/labs/resource_pool/RegionRouteModel.gd")
const Network = preload("res://scripts/labs/resource_pool/SettlementNetworkModel.gd")

const ROOT_SEED := 260814
const GLOBAL_SCOPE := "ashfall_settlement_network"
const COMMAND_SCOPE := "ashfall_campaign_command"
const WINDOW_KEYS := ["basin_relief", "meridian_trade", "nightward_fortify"]
const EXPECTED_REGIONS := {
	"basin_relief": "psa1|p:ashfall|f:0|r:0,0",
	"meridian_trade": "psa1|p:ashfall|f:2|r:0,0",
	"nightward_fortify": "psa1|p:ashfall|f:5|r:0,0",
}
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
const ORACLE := {
	"aid": {
		"origin": "basin_relief", "target": "meridian_trade",
		"favored": "spring", "track": "need_pressure",
		"target_track": "logistics_pressure", "kind": "relief_corridor",
	},
	"trade": {
		"origin": "meridian_trade", "target": "nightward_fortify",
		"favored": "autumn", "track": "logistics_pressure",
		"target_track": "logistics_pressure", "kind": "exchange_backflow",
	},
	"fortify": {
		"origin": "nightward_fortify", "target": "basin_relief",
		"favored": "winter", "track": "security_pressure",
		"target_track": "security_pressure", "kind": "watch_shelter",
	},
}
const SEASONS := ["spring", "autumn", "winter"]
const ZERO_RECEIPT := "sha256:0000000000000000000000000000000000000000000000000000000000000000"

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
	print("=== RP-0007 accepted planet campaign directive contract ===")
	var atlas: Dictionary = Routes.make_atlas(ROOT_SEED)
	var network_catalog: Dictionary = Network.make_catalog(atlas)
	var network_state: Dictionary = Network.make_initial_state(network_catalog)
	var global_receipt: String = String(network_state.get("state_receipt", ""))
	var catalog: Dictionary = Model.make_catalog(ROOT_SEED)
	var catalog_again: Dictionary = Model.make_catalog(ROOT_SEED)
	var state0: Dictionary = Model.make_initial_state(catalog)
	var state0_receipt: String = String(state0.get("state_receipt", ""))
	var evidence0: Dictionary = _make_evidence(
		catalog, global_receipt, "epoch0", {}
	)
	var board_fixture0: Dictionary = _make_board_fixture(
		catalog, state0, evidence0, global_receipt, 1, 3, "spring-flex"
	)
	var command0: Dictionary = board_fixture0.get("command", {})
	var board0: Dictionary = board_fixture0.get("board", {})

	_group_header(1, "catalog identity and deterministic authority")
	_check("catalog and initial state deterministically validate",
		not catalog.is_empty() and not state0.is_empty()
		and Model.validate_catalog(catalog).is_empty()
		and Model.validate_state(catalog, state0).is_empty()
		and _canonical_json(catalog) == _canonical_json(catalog_again))
	_check("three authored windows are canonical REGION identities under Ashfall",
		_catalog_identity_exact(catalog))
	_check("negative canonical region roundtrips while noncanonical grammar and SITE levels reject",
		_address_boundary_exact(catalog))
	_check("catalog is recursively JSON-native, deeply independent, and full-receipt exact",
		_json_authority_safe(catalog) and _catalog_deep_copy_exact(catalog)
		and _catalog_receipt_exact(catalog))

	_group_header(2, "accepted window adapters and one shared RP6 authority")
	_check("fixture uses a real accepted RP6 checkpoint exactly once at board level",
		not network_catalog.is_empty() and not network_state.is_empty()
		and Network.accept_state_checkpoint(
			network_catalog, network_state, global_receipt) == network_state
		and _evidence_exact(catalog, evidence0, global_receipt))
	_check("adapter input permutation is byte-independent",
		_adapter_permutation_exact(
			catalog, state0, evidence0, global_receipt, command0, board0))
	_check("changed/self-rehashed adapter, stale global checkpoint, duplicate owner, and mix reject",
		_adapter_hostiles(catalog, state0, evidence0, global_receipt, command0))

	_group_header(3, "command anchor trust, replay identity, and numeric boundary")
	_check("command anchor binds external scope, checkpoint, epoch, slot, and capacity",
		not command0.is_empty() and Model.validate_command_anchor(
			command0, COMMAND_SCOPE,
			String(board_fixture0.get("command_checkpoint", "")),
			String(command0.get("anchor_receipt", ""))).is_empty())
	_check("replay key is payload-independent but exact anchor receipt blocks capacity inflation",
		_command_anchor_hostiles(catalog, state0, evidence0, global_receipt,
			board_fixture0))
	_check("integral JSON floats normalize; fraction, nonfinite, huge, bool, and String reject",
		_command_numeric_hostiles(command0,
			String(board_fixture0.get("command_checkpoint", ""))))

	_group_header(4, "independent spring flex board oracle")
	_check("spring cap3 exposes three sorted non-dominated semantic options",
		_oracle_board_exact(catalog, board0, evidence0, 3, 1))
	_check("board and choices recompute from exact accepted owners",
		_board_choice_exact(catalog, state0, evidence0, global_receipt,
			board_fixture0))
	_check("no scalar score or presentation/map observation enters directive authority",
		not _contains_forbidden_authority(board0, ["score", "zoom", "camera", "map_size"]))

	var advance_defer0: Dictionary = Model.advance_epoch(catalog, state0, state0_receipt)
	var state1_open: Dictionary = advance_defer0.get("after_state", {})
	var advance_defer1: Dictionary = Model.advance_epoch(
		catalog, state1_open, String(state1_open.get("state_receipt", "")))
	var state2_open: Dictionary = advance_defer1.get("after_state", {})
	var season_matrix: Dictionary = _season_matrix(
		catalog, [state0, state1_open, state2_open], global_receipt
	)
	_group_header(5, "season, deadline, and finite commitment reshape feasibility")
	_check("flex cap3 retains all three options through spring/autumn/winter",
		bool(season_matrix.get("flex_ok", false)))
	_check("tight cap2 rotates the sole option aid/trade/fortify by season",
		bool(season_matrix.get("tight_ok", false)))
	_check("slot0 or capacity below two yields typed no-option while explicit defer remains legal",
		bool(season_matrix.get("no_option_ok", false)))
	_check("winter epoch2 consequence fits exact terminal-epoch3 deadline",
		int(catalog.get("terminal_epoch", -1)) == 3
		and bool(season_matrix.get("deadline_ok", false)))

	_group_header(6, "campaign state checkpoint and hostile durable ledgers")
	_check("initial checkpoint rejects wrong receipt, phase/season tamper, and unknown fields",
		_state_checkpoint_hostiles(catalog, state0, state0_receipt))
	_check("state revision and season derive only from exact transition ledgers",
		_state_derived_fields_exact(catalog, state0, advance_defer0, advance_defer1))

	var aid_option: Dictionary = _option_by_action(board0, "aid")
	var aid_choice: Dictionary = Model.make_choice(
		board0, String(aid_option.get("option_id", "")))
	var commit_aid: Dictionary = _commit(
		catalog, state0, evidence0, global_receipt, board_fixture0,
		board0, aid_choice
	)
	var committed: Dictionary = commit_aid.get("after_state", {})
	var committed_receipt: String = String(committed.get("state_receipt", ""))
	_group_header(7, "stage-one three-owner joint proposal")
	_check("Aid commit validates as campaign + command-owner + origin-region proposal",
		_commit_three_owner_exact(catalog, state0, evidence0, global_receipt,
			board_fixture0, board0, aid_choice, commit_aid))
	_check("spring Aid applies Basin need3->0, faction2->3 and conserves command resources",
		_commit_effect_conserved(commit_aid, "need_pressure", 3, 0, 2, 3, 3, 1))
	_check("global RP6 input and source adapters remain read-only bytes",
		_commit_inputs_immutable(network_state, evidence0, commit_aid))
	_check("already-satisfied source suppresses an all-noop directive",
		_source_noop_suppressed(catalog, state0, evidence0, global_receipt))

	_group_header(8, "global replay, sibling CAS, stale and mixed commitment")
	_check("three choices are distinct valid sibling proposals from one accepted checkpoint",
		_commit_siblings_exact(catalog, state0, evidence0, global_receipt,
			board_fixture0, board0))
	_check("accepted sibling blocks same/different directive and stale board at the next state",
		_replay_and_stale_rejected(catalog, committed, evidence0, global_receipt,
			board_fixture0, board0, aid_choice))
	_check("sparse self-hashed board and tampered/mixed commit proposal fail closed",
		_commit_candidate_hostiles(catalog, state0, evidence0, global_receipt,
			board_fixture0, board0, aid_choice, commit_aid))
	_check("epoch-link, all-noop, arbitrary replay-key, and durable scope forgeries reject",
		_committed_ledger_hostiles(catalog, committed))

	var pending_projection: Dictionary = Model.project_consequences(
		catalog, committed, committed_receipt)
	var pre_release_target: Dictionary = _fresh_target(
		catalog, "meridian_trade", global_receipt, "pre-release",
		BASE_SIGNALS["meridian_trade"]
	)
	var pre_release_delivery: Dictionary = _deliver(
		catalog, committed, String(commit_aid.get("consequence_record", {}).get(
			"consequence_id", "")), pre_release_target, global_receipt
	)
	var advance_after_commit: Dictionary = Model.advance_epoch(
		catalog, committed, committed_receipt)
	var advanced: Dictionary = advance_after_commit.get("after_state", {})
	var advanced_receipt: String = String(advanced.get("state_receipt", ""))
	var due_projection: Dictionary = Model.project_consequences(
		catalog, advanced, advanced_receipt)
	var terminal_chain: Dictionary = _winter_terminal_chain(
		catalog, state0, global_receipt
	)
	_group_header(9, "explicit epoch advance, delay, observation, and terminal deadline")
	_check("consequence is pending at commit and pre-release delivery rejects",
		_projection_counts(pending_projection, 1, 0, 0)
		and pre_release_delivery.is_empty())
	_check("one accepted positive advance makes it deliverable without mutating observation",
		_advance_projection_exact(catalog, committed, pending_projection,
			advance_after_commit, due_projection))
	_check("open defer advances exactly one epoch and avoids no-option dead-end",
		_defer_exact(catalog, state0, advance_defer0))
	_check("terminal forbids commit/advance but retains due winter delivery",
		bool(terminal_chain.get("ok", false)), String(terminal_chain.get("detail", "")))

	var fresh_meridian: Dictionary = _fresh_target(
		catalog, "meridian_trade", global_receipt, "applied",
		BASE_SIGNALS["meridian_trade"]
	)
	var aid_consequence_id: String = String(
		(commit_aid.get("consequence_record", {}) as Dictionary).get("consequence_id", ""))
	var delivery_applied: Dictionary = _deliver(
		catalog, advanced, aid_consequence_id, fresh_meridian, global_receipt
	)
	var applied_state: Dictionary = delivery_applied.get("after_state", {})
	_group_header(10, "stage-two fresh different-target applied delivery")
	_check("fresh Meridian target applies exact logistics3->2 after release",
		_delivery_applied_exact(catalog, advanced, fresh_meridian,
			aid_consequence_id, global_receipt, delivery_applied))
	_check("scheduled target, same-origin, wrong scope/global, stale state, and mixed ID reject",
		_delivery_hostiles(catalog, committed, advanced, evidence0, fresh_meridian,
			global_receipt, commit_aid, delivery_applied))
	_check("delivery preserves one-way provenance and never mutates global RP6 authority",
		_delivery_provenance_exact(commit_aid, delivery_applied, network_state))

	var superseded_chain: Dictionary = _superseded_chain(
		catalog, state0, global_receipt
	)
	_group_header(11, "superseded delivery, replay, and durable receipt chain")
	_check("at-bound target settles pending as superseded with requested-1/applied0",
		bool(superseded_chain.get("exact", false)))
	_check("delivered consequence replay and stale sibling proposals reject",
		bool(superseded_chain.get("replay_rejected", false)))
	_check("future delivery epoch and rewritten durable target scope reject after self-rehash",
		bool(superseded_chain.get("durable_hostiles", false)))

	_group_header(12, "JSON/Variant continuation and hostile numeric inputs")
	_check("catalog, adapters, board, commit, advance, delivery survive JSON normalization",
		_roundtrip_validates(catalog, state0, evidence0, global_receipt,
			board_fixture0, board0, aid_choice, commit_aid,
			advance_after_commit, fresh_meridian, delivery_applied))
	_check("mid-committed and terminal-pending JSON continuations produce exact next receipts",
		_roundtrip_continuation_exact(catalog, committed, advance_after_commit,
			terminal_chain, global_receipt))
	_check("all final DTOs remain recursive JSON-native integers after Variant deep copy",
		_json_authority_safe(commit_aid) and _json_authority_safe(delivery_applied)
		and _canonical_json(delivery_applied) \
		== _canonical_json(delivery_applied.duplicate(true)))

	_group_header(13, "canonical receipts, anti-physical boundary, and golden output")
	_check("independent canonical SHA verifies catalog, board, commit, advance, delivery, and state",
		_receipt_suite_exact(catalog, board0, commit_aid,
			advance_after_commit, delivery_applied, applied_state))
	_check("RP7 schemas/authority never claim launch, arrival, or success",
		not _contains_forbidden_authority(
			[catalog, board0, commit_aid, delivery_applied],
			["launch", "arrival", "success"]))
	_check("RP7 proposals cannot substitute for RP3 route or RP6 physical-arrival evidence",
		_anti_physical_validators(atlas, commit_aid, delivery_applied))

	print("PLANET_CAMPAIGN_CATALOG_RECEIPT=%s" % String(catalog.get("catalog_receipt", "")))
	print("PLANET_CAMPAIGN_BOARD_RECEIPT=%s" % String(board0.get("board_receipt", "")))
	print("PLANET_CAMPAIGN_COMMIT_RECEIPT=%s" % String(commit_aid.get("proposal_receipt", "")))
	print("PLANET_CAMPAIGN_ADVANCE_RECEIPT=%s" % String(
		advance_after_commit.get("transition_receipt", "")))
	print("PLANET_CAMPAIGN_DELIVERY_RECEIPT=%s" % String(
		delivery_applied.get("proposal_receipt", "")))
	print("PLANET_CAMPAIGN_STATE_RECEIPT=%s" % String(
		applied_state.get("state_receipt", "")))
	print("PLANET_CAMPAIGN_METRICS=windows:%d flex:%d terminal:%d" % [
		(catalog.get("windows", []) as Array).size(),
		(board0.get("options", []) as Array).size(),
		int(catalog.get("terminal_epoch", -1)),
	])
	print("planet_campaign_test: %s (%d fail, %d checks)" % [
		"PASS" if _fails == 0 else "FAIL", _fails, _checks,
	])
	get_tree().quit(0 if _fails == 0 else 1)


func _group_header(index: int, label: String) -> void:
	print("--- %02d %s ---" % [index, label])


func _external_receipt(label: String) -> String:
	return _receipt_for(["rp7-external-owner-checkpoint", label])


func _window_by_key(catalog: Dictionary, key: String) -> Dictionary:
	for raw_window in catalog.get("windows", []) as Array:
		var window: Dictionary = raw_window
		if String(window.get("window_key", "")) == key:
			return window
	return {}


func _directive_by_action(catalog: Dictionary, action: String) -> Dictionary:
	for raw_directive in catalog.get("directives", []) as Array:
		var directive: Dictionary = raw_directive
		if String(directive.get("action", "")) == action:
			return directive
	return {}


func _adapter_by_key(catalog: Dictionary, adapters: Array, key: String) -> Dictionary:
	var window: Dictionary = _window_by_key(catalog, key)
	var window_id: String = String(window.get("window_id", ""))
	for raw_adapter in adapters:
		if raw_adapter is Dictionary:
			var adapter: Dictionary = raw_adapter
			if String(adapter.get("window_id", "")) == window_id:
				return adapter
	return {}


func _acceptance_for(acceptances: Array, window_id: String) -> Dictionary:
	for raw_acceptance in acceptances:
		if raw_acceptance is Dictionary:
			var acceptance: Dictionary = raw_acceptance
			if String(acceptance.get("window_id", "")) == window_id:
				return acceptance
	return {}


func _option_by_action(board: Dictionary, action: String) -> Dictionary:
	for raw_option in board.get("options", []) as Array:
		if raw_option is Dictionary:
			var option: Dictionary = raw_option
			if String(option.get("action", "")) == action:
				return option
	return {}


func _make_evidence(catalog: Dictionary, global_receipt: String, tag: String,
		signal_overrides: Dictionary) -> Dictionary:
	var adapters: Array[Dictionary] = []
	var acceptances: Array[Dictionary] = []
	for raw_key in WINDOW_KEYS:
		var key: String = String(raw_key)
		var window: Dictionary = _window_by_key(catalog, key)
		var signals: Dictionary = (BASE_SIGNALS[key] as Dictionary).duplicate(true)
		if signal_overrides.has(key):
			signals = (signal_overrides[key] as Dictionary).duplicate(true)
		var region_scope := "rp7_region_%s" % key
		var region_receipt := _external_receipt("%s-%s" % [tag, key])
		var adapter: Dictionary = Model.make_window_adapter(
			catalog, key, region_scope, region_receipt,
			GLOBAL_SCOPE, global_receipt, signals
		)
		if window.is_empty() or adapter.is_empty():
			return {}
		var acceptance: Dictionary = Model.make_window_acceptance(
			String(window["window_id"]), region_scope, region_receipt,
			String(adapter["adapter_receipt"])
		)
		if acceptance.is_empty():
			return {}
		adapters.append(adapter)
		acceptances.append(acceptance)
	return {
		"adapters": adapters,
		"acceptances": acceptances,
		"global_scope": GLOBAL_SCOPE,
		"global_receipt": global_receipt,
	}


func _fresh_target(catalog: Dictionary, key: String, global_receipt: String,
		tag: String, signals_value: Variant) -> Dictionary:
	if not (signals_value is Dictionary):
		return {}
	var window: Dictionary = _window_by_key(catalog, key)
	var region_scope := "rp7_region_%s" % key
	var checkpoint := _external_receipt("fresh-%s-%s" % [tag, key])
	var adapter: Dictionary = Model.make_window_adapter(
		catalog, key, region_scope, checkpoint, GLOBAL_SCOPE, global_receipt,
		(signals_value as Dictionary).duplicate(true)
	)
	if window.is_empty() or adapter.is_empty():
		return {}
	var acceptance: Dictionary = Model.make_window_acceptance(
		String(window["window_id"]), region_scope, checkpoint,
		String(adapter["adapter_receipt"])
	)
	return {
		"adapter": adapter,
		"acceptance": acceptance,
	}


func _make_board_fixture(catalog: Dictionary, state: Dictionary,
		evidence: Dictionary, global_receipt: String, slots: int, capacity: int,
		tag: String) -> Dictionary:
	var checkpoint := _external_receipt("command-%s" % tag)
	var command: Dictionary = Model.make_command_anchor(
		COMMAND_SCOPE, checkpoint, int(state.get("epoch_index", -1)), slots, capacity
	)
	if command.is_empty():
		return {}
	var board: Dictionary = Model.make_directive_board(
		catalog, state, String(state.get("state_receipt", "")),
		evidence.get("adapters", []), evidence.get("acceptances", []),
		GLOBAL_SCOPE, global_receipt, command, COMMAND_SCOPE, checkpoint,
		String(command.get("anchor_receipt", ""))
	)
	return {
		"command_checkpoint": checkpoint,
		"command": command,
		"board": board,
	}


func _commit(catalog: Dictionary, state: Dictionary, evidence: Dictionary,
		global_receipt: String, board_fixture: Dictionary, board: Dictionary,
		choice: Dictionary) -> Dictionary:
	var command: Dictionary = board_fixture.get("command", {})
	return Model.commit_directive(
		catalog, state, String(state.get("state_receipt", "")),
		evidence.get("adapters", []), evidence.get("acceptances", []),
		GLOBAL_SCOPE, global_receipt, command, COMMAND_SCOPE,
		String(board_fixture.get("command_checkpoint", "")),
		String(command.get("anchor_receipt", "")), board, choice
	)


func _deliver(catalog: Dictionary, state: Dictionary, consequence_id: String,
		target: Dictionary, global_receipt: String) -> Dictionary:
	return Model.deliver_consequence(
		catalog, state, String(state.get("state_receipt", "")), consequence_id,
		target.get("adapter", {}), target.get("acceptance", {}),
		GLOBAL_SCOPE, global_receipt
	)


func _catalog_identity_exact(catalog: Dictionary) -> bool:
	if String(catalog.get("planet_id", "")) != "psa1|p:ashfall" \
			or (catalog.get("windows", []) as Array).size() != 3 \
			or (catalog.get("directives", []) as Array).size() != 3:
		return false
	var window_keys := {}
	var previous_id := ""
	for raw_window in catalog.get("windows", []) as Array:
		var window: Dictionary = raw_window
		var key: String = String(window.get("window_key", ""))
		var region_id: String = String(window.get("region_id", ""))
		var address: Dictionary = Address.parse_id(region_id)
		if key not in WINDOW_KEYS or region_id != String(EXPECTED_REGIONS[key]) \
				or Address.level_of(address) != Address.LEVEL_REGION \
				or Address.canonical_id(Address.parent(address)) != "psa1|p:ashfall" \
				or window_keys.has(key) \
				or (previous_id != "" and String(window.get("window_id", "")) <= previous_id):
			return false
		window_keys[key] = true
		previous_id = String(window["window_id"])
	return window_keys.size() == 3


func _address_boundary_exact(catalog: Dictionary) -> bool:
	var negative: Dictionary = Address.region_address("ashfall", 2, Vector2i(-3, 2))
	var negative_id: String = Address.canonical_id(negative)
	if negative_id != "psa1|p:ashfall|f:2|r:-3,2" \
			or Address.canonical_id(Address.parse_id(negative_id)) != negative_id \
			or Address.level_of(negative) != Address.LEVEL_REGION:
		return false
	for bad_id in [
		"psa1|p:ashfall|f:2|r:+1,2",
		"psa1|p:ashfall|f:2|r:01,2",
		"psa1|p:ashfall|f:2|r:-0,2",
	]:
		if not Address.parse_id(String(bad_id)).is_empty():
			return false
	var atlas: Dictionary = Routes.make_atlas(ROOT_SEED)
	var site_tile: String = Routes.site_tile_id(atlas, "cinder_crossing")
	var site: Dictionary = Address.with_site(
		Address.parse_id(site_tile), "cinder_crossing"
	)
	if Address.level_of(site) != Address.LEVEL_SITE:
		return false
	var forged: Dictionary = catalog.duplicate(true)
	(forged["windows"] as Array)[0]["region_id"] = Address.canonical_id(site)
	_rehash_catalog(forged)
	return not Model.validate_catalog(forged).is_empty()


func _catalog_deep_copy_exact(catalog: Dictionary) -> bool:
	var before := _canonical_json(catalog)
	var duplicate: Dictionary = catalog.duplicate(true)
	(duplicate["windows"] as Array)[0]["label"] = "MUTATED"
	(duplicate["directives"] as Array).clear()
	return _canonical_json(catalog) == before \
		and not Model.validate_catalog(duplicate).is_empty()


func _catalog_receipt_exact(catalog: Dictionary) -> bool:
	var authority: Dictionary = catalog.duplicate(true)
	authority.erase("catalog_id")
	authority.erase("catalog_receipt")
	var digest := _sha256_hex(_canonical_json(authority))
	return String(catalog.get("catalog_id", "")) == "pcc1:" + digest.substr(0, 16) \
		and String(catalog.get("catalog_receipt", "")) == "sha256:" + digest


func _evidence_exact(catalog: Dictionary, evidence: Dictionary,
		global_receipt: String) -> bool:
	var adapters: Array = evidence.get("adapters", [])
	var acceptances: Array = evidence.get("acceptances", [])
	if adapters.size() != 3 or acceptances.size() != 3:
		return false
	var scopes := {}
	var checkpoints := {}
	for raw_adapter in adapters:
		var adapter: Dictionary = raw_adapter
		var acceptance: Dictionary = _acceptance_for(
			acceptances, String(adapter.get("window_id", "")))
		if acceptance.is_empty() or not Model.validate_window_adapter(
			catalog, adapter, String(acceptance["expected_region_scope"]),
			String(acceptance["accepted_region_checkpoint_receipt"]),
			GLOBAL_SCOPE, global_receipt,
			String(acceptance["expected_adapter_receipt"])
		).is_empty():
			return false
		scopes[String(acceptance["expected_region_scope"])] = true
		checkpoints[String(acceptance["accepted_region_checkpoint_receipt"])] = true
	return scopes.size() == 3 and checkpoints.size() == 3 \
		and not scopes.has(GLOBAL_SCOPE) and not scopes.has(COMMAND_SCOPE)


func _oracle_board_exact(catalog: Dictionary, board: Dictionary,
		evidence: Dictionary, capacity: int, slots: int) -> bool:
	if board.is_empty():
		return false
	var season: String = String(board.get("season", ""))
	var expected_ids: Array[String] = []
	var expected_actions := {}
	for raw_action in ORACLE:
		var action: String = String(raw_action)
		var spec: Dictionary = ORACLE[action]
		var origin: Dictionary = _adapter_by_key(
			catalog, evidence.get("adapters", []), String(spec["origin"])
		)
		if origin.is_empty():
			return false
		var before: Dictionary = origin["signals"]
		var cost := 2 if season == String(spec["favored"]) else 3
		var magnitude := 3 if season == String(spec["favored"]) else 2
		var primary_applied := -mini(int(before[String(spec["track"])]), magnitude)
		var faction_applied := mini(1, 3 - int(before["faction_access"]))
		if slots < 1 or capacity < cost or (primary_applied == 0 and faction_applied == 0):
			continue
		var directive: Dictionary = _directive_by_action(catalog, action)
		expected_ids.append(String(directive.get("directive_id", "")))
		expected_actions[action] = {
			"cost": cost,
			"primary_applied": primary_applied,
			"faction_applied": faction_applied,
		}
	expected_ids.sort()
	var actual_ids: Array[String] = []
	for raw_option in board.get("options", []) as Array:
		if not (raw_option is Dictionary):
			return false
		var option: Dictionary = raw_option
		var action: String = String(option.get("action", ""))
		if not expected_actions.has(action):
			return false
		var spec: Dictionary = ORACLE[action]
		var expected: Dictionary = expected_actions[action]
		var effect: Dictionary = option.get("origin_effect", {})
		var consequence: Dictionary = option.get("consequence", {})
		if String(option.get("origin_window_id", "")) \
				!= String(_window_by_key(catalog, String(spec["origin"])).get("window_id", "")) \
				or String(option.get("target_window_id", "")) \
				!= String(_window_by_key(catalog, String(spec["target"])).get("window_id", "")) \
				or int(option.get("capacity_cost", -1)) != int(expected["cost"]) \
				or int(option.get("command_slots_cost", -1)) != 1 \
				or String(effect.get("primary_track", "")) != String(spec["track"]) \
				or int(effect.get("primary_applied", 99)) != int(expected["primary_applied"]) \
				or int(effect.get("faction_applied", 99)) != int(expected["faction_applied"]) \
				or String(consequence.get("kind", "")) != String(spec["kind"]) \
				or String(consequence.get("track", "")) != String(spec["target_track"]) \
				or int(consequence.get("requested_delta", 0)) != -1 \
				or int(consequence.get("release_epoch", -1)) \
				!= int(board.get("epoch_index", -1)) + 1:
			return false
		actual_ids.append(String(option.get("option_id", "")))
	return actual_ids == expected_ids \
		and String(board.get("decision_status", "")) \
		== ("options_available" if not expected_ids.is_empty() else "no_eligible_directive")


func _adapter_permutation_exact(catalog: Dictionary, state: Dictionary,
		evidence: Dictionary, global_receipt: String, command: Dictionary,
		board: Dictionary) -> bool:
	var adapters: Array = (evidence.get("adapters", []) as Array).duplicate(true)
	var acceptances: Array = (evidence.get("acceptances", []) as Array).duplicate(true)
	adapters.reverse()
	acceptances.reverse()
	var permuted: Dictionary = Model.make_directive_board(
		catalog, state, String(state.get("state_receipt", "")), adapters, acceptances,
		GLOBAL_SCOPE, global_receipt, command, COMMAND_SCOPE,
		String(command.get("owner_checkpoint_receipt", "")),
		String(command.get("anchor_receipt", ""))
	)
	return not permuted.is_empty() and _canonical_json(permuted) == _canonical_json(board)


func _adapter_hostiles(catalog: Dictionary, state: Dictionary,
		evidence: Dictionary, global_receipt: String, command: Dictionary) -> bool:
	var adapters: Array = (evidence.get("adapters", []) as Array).duplicate(true)
	var acceptances: Array = (evidence.get("acceptances", []) as Array).duplicate(true)
	var basin: Dictionary = _adapter_by_key(catalog, adapters, "basin_relief")
	var basin_acceptance: Dictionary = _acceptance_for(
		acceptances, String(basin.get("window_id", "")))
	var signals: Dictionary = (basin.get("signals", {}) as Dictionary).duplicate(true)
	signals["need_pressure"] = 2
	var changed: Dictionary = Model.make_window_adapter(
		catalog, "basin_relief", String(basin.get("region_scope", "")),
		String(basin.get("region_checkpoint_receipt", "")), GLOBAL_SCOPE,
		global_receipt, signals
	)
	if changed.is_empty() or Model.validate_window_adapter(
		catalog, changed, String(basin_acceptance.get("expected_region_scope", "")),
		String(basin_acceptance.get("accepted_region_checkpoint_receipt", "")),
		GLOBAL_SCOPE, global_receipt,
		String(basin_acceptance.get("expected_adapter_receipt", ""))
	).is_empty():
		return false
	var changed_adapters: Array[Dictionary] = []
	for raw_adapter in adapters:
		var adapter: Dictionary = raw_adapter
		changed_adapters.append(changed if String(adapter.get("window_id", "")) \
			== String(changed.get("window_id", "")) else adapter)
	var command_checkpoint: String = String(command.get("owner_checkpoint_receipt", ""))
	if not Model.make_directive_board(
		catalog, state, String(state.get("state_receipt", "")), changed_adapters,
		acceptances, GLOBAL_SCOPE, global_receipt, command, COMMAND_SCOPE,
		command_checkpoint, String(command.get("anchor_receipt", ""))
	).is_empty():
		return false
	if not Model.make_directive_board(
		catalog, state, String(state.get("state_receipt", "")), adapters,
		acceptances, GLOBAL_SCOPE, ZERO_RECEIPT, command, COMMAND_SCOPE,
		command_checkpoint, String(command.get("anchor_receipt", ""))
	).is_empty():
		return false
	var duplicate_acceptances: Array = acceptances.duplicate(true)
	var first: Dictionary = duplicate_acceptances[0]
	var second: Dictionary = (duplicate_acceptances[1] as Dictionary).duplicate(true)
	second["expected_region_scope"] = String(first["expected_region_scope"])
	duplicate_acceptances[1] = second
	return Model.make_directive_board(
		catalog, state, String(state.get("state_receipt", "")), adapters,
		duplicate_acceptances, GLOBAL_SCOPE, global_receipt, command, COMMAND_SCOPE,
		command_checkpoint, String(command.get("anchor_receipt", ""))
	).is_empty()


func _command_anchor_hostiles(catalog: Dictionary, state: Dictionary,
		evidence: Dictionary, global_receipt: String, fixture: Dictionary) -> bool:
	var command: Dictionary = fixture.get("command", {})
	var checkpoint: String = String(fixture.get("command_checkpoint", ""))
	var tight: Dictionary = Model.make_command_anchor(
		COMMAND_SCOPE, checkpoint, int(state.get("epoch_index", -1)), 1, 2
	)
	var inflated: Dictionary = Model.make_command_anchor(
		COMMAND_SCOPE, checkpoint, int(state.get("epoch_index", -1)), 1, 6
	)
	if tight.is_empty() or inflated.is_empty() \
			or String(tight.get("commitment_replay_key", "")) \
			!= String(command.get("commitment_replay_key", "")) \
			or String(inflated.get("commitment_replay_key", "")) \
			!= String(command.get("commitment_replay_key", "")):
		return false
	if Model.validate_command_anchor(
		inflated, COMMAND_SCOPE, checkpoint,
		String(command.get("anchor_receipt", ""))
	).is_empty():
		return false
	if not Model.make_directive_board(
		catalog, state, String(state.get("state_receipt", "")),
		evidence.get("adapters", []), evidence.get("acceptances", []),
		GLOBAL_SCOPE, global_receipt, inflated, COMMAND_SCOPE, checkpoint,
		String(command.get("anchor_receipt", ""))
	).is_empty():
		return false
	return not Model.validate_command_anchor(
		command, "different_command_owner", checkpoint,
		String(command.get("anchor_receipt", ""))
	).is_empty()


func _command_numeric_hostiles(command: Dictionary, checkpoint: String) -> bool:
	var json_value: Variant = JSON.parse_string(JSON.stringify(command))
	if not (json_value is Dictionary):
		return false
	var parsed: Dictionary = json_value
	var normalized: Dictionary = Model.normalize_command_anchor(
		parsed, COMMAND_SCOPE, checkpoint, String(command.get("anchor_receipt", ""))
	)
	if normalized.is_empty() or typeof(normalized.get("capacity_units_before")) != TYPE_INT:
		return false
	for hostile in [1.5, NAN, INF, 1.0e100, true, "3"]:
		var candidate: Dictionary = command.duplicate(true)
		candidate["capacity_units_before"] = hostile
		if Model.validate_command_anchor(
			candidate, COMMAND_SCOPE, checkpoint,
			String(command.get("anchor_receipt", ""))
		).is_empty():
			return false
	var unknown: Dictionary = command.duplicate(true)
	unknown["bonus_capacity"] = 1
	return not Model.validate_command_anchor(
		unknown, COMMAND_SCOPE, checkpoint,
		String(command.get("anchor_receipt", ""))
	).is_empty()


func _board_choice_exact(catalog: Dictionary, state: Dictionary,
		evidence: Dictionary, global_receipt: String, fixture: Dictionary) -> bool:
	var board: Dictionary = fixture.get("board", {})
	var command: Dictionary = fixture.get("command", {})
	if board.is_empty() or not Model.validate_directive_board(
		catalog, state, String(state.get("state_receipt", "")),
		evidence.get("adapters", []), evidence.get("acceptances", []),
		GLOBAL_SCOPE, global_receipt, command, COMMAND_SCOPE,
		String(fixture.get("command_checkpoint", "")),
		String(command.get("anchor_receipt", "")), board
	).is_empty():
		return false
	for raw_option in board.get("options", []) as Array:
		var option: Dictionary = raw_option
		var choice: Dictionary = Model.make_choice(board, String(option.get("option_id", "")))
		if choice.is_empty() or not Model.validate_choice(board, choice).is_empty():
			return false
	return true


func _season_matrix(catalog: Dictionary, states: Array,
		global_receipt: String) -> Dictionary:
	var flex_ok := true
	var tight_ok := true
	var no_option_ok := true
	var deadline_ok := true
	var expected_tight := ["aid", "trade", "fortify"]
	for index in states.size():
		var state: Dictionary = states[index]
		var evidence: Dictionary = _make_evidence(
			catalog, global_receipt, "season-%d" % index, {}
		)
		var flex: Dictionary = _make_board_fixture(
			catalog, state, evidence, global_receipt, 1, 3,
			"flex-%d" % index
		)
		var tight: Dictionary = _make_board_fixture(
			catalog, state, evidence, global_receipt, 1, 2,
			"tight-%d" % index
		)
		var slot0: Dictionary = _make_board_fixture(
			catalog, state, evidence, global_receipt, 0, 3,
			"slot0-%d" % index
		)
		var cap1: Dictionary = _make_board_fixture(
			catalog, state, evidence, global_receipt, 1, 1,
			"cap1-%d" % index
		)
		var flex_board: Dictionary = flex.get("board", {})
		var tight_board: Dictionary = tight.get("board", {})
		var slot0_board: Dictionary = slot0.get("board", {})
		var cap1_board: Dictionary = cap1.get("board", {})
		flex_ok = flex_ok and String(flex_board.get("season", "")) == SEASONS[index] \
			and _oracle_board_exact(catalog, flex_board, evidence, 3, 1)
		tight_ok = tight_ok and _oracle_board_exact(catalog, tight_board, evidence, 2, 1) \
			and (tight_board.get("options", []) as Array).size() == 1 \
			and String((tight_board.get("options", []) as Array)[0].get("action", "")) \
			== String(expected_tight[index])
		no_option_ok = no_option_ok \
			and String(slot0_board.get("decision_status", "")) == "no_eligible_directive" \
			and String(cap1_board.get("decision_status", "")) == "no_eligible_directive" \
			and not Model.advance_epoch(
				catalog, state, String(state.get("state_receipt", ""))).is_empty()
		for raw_option in flex_board.get("options", []) as Array:
			var option: Dictionary = raw_option
			deadline_ok = deadline_ok and int(option.get("consequence", {}).get(
				"release_epoch", -1)) <= int(catalog.get("terminal_epoch", -1))
	return {
		"flex_ok": flex_ok,
		"tight_ok": tight_ok,
		"no_option_ok": no_option_ok,
		"deadline_ok": deadline_ok,
	}


func _state_checkpoint_hostiles(catalog: Dictionary, state: Dictionary,
		receipt: String) -> bool:
	if Model.accept_state_checkpoint(catalog, state, receipt) != state \
			or not Model.accept_state_checkpoint(catalog, state, ZERO_RECEIPT).is_empty():
		return false
	var phase: Dictionary = state.duplicate(true)
	phase["phase"] = "terminal"
	phase["season"] = "terminal"
	_rehash_state(phase)
	if Model.validate_state(catalog, phase).is_empty():
		return false
	var unknown: Dictionary = state.duplicate(true)
	unknown["owner_name"] = "forged"
	_rehash_state(unknown)
	return not Model.validate_state(catalog, unknown).is_empty()


func _state_derived_fields_exact(catalog: Dictionary, state0: Dictionary,
		advance0: Dictionary, advance1: Dictionary) -> bool:
	var state1: Dictionary = advance0.get("after_state", {})
	var state2: Dictionary = advance1.get("after_state", {})
	return int(state0.get("revision", -1)) == 0 \
		and int(state1.get("revision", -1)) == 1 \
		and int(state2.get("revision", -1)) == 2 \
		and String(state1.get("season", "")) == "autumn" \
		and String(state2.get("season", "")) == "winter" \
		and Model.validate_state(catalog, state1).is_empty() \
		and Model.validate_state(catalog, state2).is_empty()


func _commit_three_owner_exact(catalog: Dictionary, state: Dictionary,
		evidence: Dictionary, global_receipt: String, fixture: Dictionary,
		board: Dictionary, choice: Dictionary, proposal: Dictionary) -> bool:
	if proposal.is_empty() or proposal.get("owner_order", []) \
			!= ["campaign", "command_owner", "origin_region"]:
		return false
	var command: Dictionary = fixture.get("command", {})
	if not Model.validate_commit_proposal(
		catalog, state, String(state.get("state_receipt", "")),
		evidence.get("adapters", []), evidence.get("acceptances", []),
		GLOBAL_SCOPE, global_receipt, command, COMMAND_SCOPE,
		String(fixture.get("command_checkpoint", "")),
		String(command.get("anchor_receipt", "")), board, choice, proposal
	).is_empty():
		return false
	var campaign_delta: Dictionary = proposal.get("campaign_delta", {})
	var after_state: Dictionary = proposal.get("after_state", {})
	return String(campaign_delta.get("before_state_receipt", "")) \
		== String(state.get("state_receipt", "")) \
		and String(campaign_delta.get("after_state_receipt", "")) \
		== String(after_state.get("state_receipt", "")) \
		and int(campaign_delta.get("before_revision", -1)) + 1 \
		== int(campaign_delta.get("after_revision", -1)) \
		and String(after_state.get("phase", "")) == "committed" \
		and Model.validate_state(catalog, after_state).is_empty()


func _commit_effect_conserved(proposal: Dictionary, track: String,
		primary_before: int, primary_after: int, faction_before: int,
		faction_after: int, capacity_before: int, capacity_after: int) -> bool:
	var command: Dictionary = proposal.get("command_owner_delta", {})
	var origin: Dictionary = proposal.get("origin_region_delta", {})
	var before: Dictionary = origin.get("before_signals", {})
	var after: Dictionary = origin.get("after_signals", {})
	return int(command.get("command_slots_before", -1)) == 1 \
		and int(command.get("command_slots_committed", -1)) == 1 \
		and int(command.get("command_slots_after", -1)) == 0 \
		and int(command.get("capacity_units_before", -1)) == capacity_before \
		and int(command.get("capacity_units_committed", -1)) \
		== capacity_before - capacity_after \
		and int(command.get("capacity_units_after", -1)) == capacity_after \
		and String(origin.get("action", "")) == "aid" \
		and String(origin.get("primary_track", "")) == track \
		and int(before.get(track, -1)) == primary_before \
		and int(after.get(track, -1)) == primary_after \
		and int(before.get("faction_access", -1)) == faction_before \
		and int(after.get("faction_access", -1)) == faction_after \
		and int(origin.get("primary_applied", 99)) \
		== primary_after - primary_before \
		and int(origin.get("faction_applied", 99)) \
		== faction_after - faction_before


func _commit_inputs_immutable(network_state: Dictionary, evidence: Dictionary,
		proposal: Dictionary) -> bool:
	var network_before := _canonical_json(network_state)
	var evidence_before := _canonical_json(evidence)
	var mutated: Dictionary = proposal.duplicate(true)
	(mutated.get("origin_region_delta", {}) as Dictionary)["action"] = "trade"
	(mutated.get("after_state", {}) as Dictionary)["phase"] = "open"
	return _canonical_json(network_state) == network_before \
		and _canonical_json(evidence) == evidence_before \
		and not proposal.has("network_delta") \
		and _canonical_json(mutated) != _canonical_json(proposal)


func _source_noop_suppressed(catalog: Dictionary, state: Dictionary,
		evidence: Dictionary, global_receipt: String) -> bool:
	var overrides: Dictionary = {}
	for raw_key in WINDOW_KEYS:
		var key: String = String(raw_key)
		overrides[key] = (BASE_SIGNALS[key] as Dictionary).duplicate(true)
	var basin: Dictionary = overrides["basin_relief"]
	basin["need_pressure"] = 0
	basin["faction_access"] = 3
	var noop_evidence: Dictionary = _make_evidence(
		catalog, global_receipt, "noop-source", overrides
	)
	var fixture: Dictionary = _make_board_fixture(
		catalog, state, noop_evidence, global_receipt, 1, 3, "noop-source"
	)
	var board: Dictionary = fixture.get("board", {})
	return not board.is_empty() and _option_by_action(board, "aid").is_empty() \
		and not _option_by_action(board, "trade").is_empty() \
		and not _option_by_action(board, "fortify").is_empty()


func _commit_siblings_exact(catalog: Dictionary, state: Dictionary,
		evidence: Dictionary, global_receipt: String, fixture: Dictionary,
		board: Dictionary) -> bool:
	var receipts := {}
	for raw_action in ["aid", "trade", "fortify"]:
		var action: String = String(raw_action)
		var option: Dictionary = _option_by_action(board, action)
		var choice: Dictionary = Model.make_choice(board, String(option.get("option_id", "")))
		var proposal: Dictionary = _commit(
			catalog, state, evidence, global_receipt, fixture, board, choice
		)
		if proposal.is_empty() or String(proposal.get("proposal_receipt", "")) == "":
			return false
		receipts[String(proposal["proposal_receipt"])] = true
	return receipts.size() == 3


func _replay_and_stale_rejected(catalog: Dictionary, committed: Dictionary,
		evidence: Dictionary, global_receipt: String, fixture: Dictionary,
		old_board: Dictionary, old_choice: Dictionary) -> bool:
	var command: Dictionary = fixture.get("command", {})
	var committed_board: Dictionary = Model.make_directive_board(
		catalog, committed, String(committed.get("state_receipt", "")),
		evidence.get("adapters", []), evidence.get("acceptances", []),
		GLOBAL_SCOPE, global_receipt, command, COMMAND_SCOPE,
		String(fixture.get("command_checkpoint", "")),
		String(command.get("anchor_receipt", ""))
	)
	if committed_board.is_empty() \
			or String(committed_board.get("decision_status", "")) != "epoch_committed" \
			or not (committed_board.get("options", []) as Array).is_empty():
		return false
	if not _commit(
		catalog, committed, evidence, global_receipt, fixture,
		old_board, old_choice
	).is_empty():
		return false
	var next: Dictionary = Model.advance_epoch(
		catalog, committed, String(committed.get("state_receipt", "")))
	var next_state: Dictionary = next.get("after_state", {})
	return _commit(
		catalog, next_state, evidence, global_receipt, fixture,
		old_board, old_choice
	).is_empty()


func _commit_candidate_hostiles(catalog: Dictionary, state: Dictionary,
		evidence: Dictionary, global_receipt: String, fixture: Dictionary,
		board: Dictionary, choice: Dictionary, proposal: Dictionary) -> bool:
	var sparse: Dictionary = _rehash_board_with_sparse_option(board)
	if sparse.is_empty() or not Model.make_choice(
		sparse, String((sparse.get("options", []) as Array)[0].get("option_id", ""))
	).is_empty():
		return false
	var command: Dictionary = fixture.get("command", {})
	var tampered: Dictionary = proposal.duplicate(true)
	(tampered.get("command_owner_delta", {}) as Dictionary)["capacity_units_after"] = 2
	_rehash_proposal(tampered, "proposal_id", "pct1:", "proposal_receipt")
	if Model.validate_commit_proposal(
		catalog, state, String(state.get("state_receipt", "")),
		evidence.get("adapters", []), evidence.get("acceptances", []),
		GLOBAL_SCOPE, global_receipt, command, COMMAND_SCOPE,
		String(fixture.get("command_checkpoint", "")),
		String(command.get("anchor_receipt", "")), board, choice, tampered
	).is_empty():
		return false
	var unknown: Dictionary = proposal.duplicate(true)
	unknown["authorized"] = true
	_rehash_proposal(unknown, "proposal_id", "pct1:", "proposal_receipt")
	return not Model.validate_commit_proposal(
		catalog, state, String(state.get("state_receipt", "")),
		evidence.get("adapters", []), evidence.get("acceptances", []),
		GLOBAL_SCOPE, global_receipt, command, COMMAND_SCOPE,
		String(fixture.get("command_checkpoint", "")),
		String(command.get("anchor_receipt", "")), board, choice, unknown
	).is_empty()


func _committed_ledger_hostiles(catalog: Dictionary, committed: Dictionary) -> bool:
	for raw_mode in ["epoch_link", "all_noop", "replay_key", "scope_collision"]:
		var mode: String = String(raw_mode)
		var forged: Dictionary = _forge_committed_state(committed, mode)
		if forged.is_empty() or Model.validate_state(catalog, forged).is_empty():
			return false
	return true


func _projection_counts(projection: Dictionary, pending: int,
		deliverable: int, delivered: int) -> bool:
	return not projection.is_empty() \
		and (projection.get("pending", []) as Array).size() == pending \
		and (projection.get("deliverable", []) as Array).size() == deliverable \
		and (projection.get("delivered", []) as Array).size() == delivered


func _advance_projection_exact(catalog: Dictionary, committed: Dictionary,
		before_projection: Dictionary, advance: Dictionary,
		after_projection: Dictionary) -> bool:
	var before_bytes := _canonical_json(committed)
	var repeated: Dictionary = Model.project_consequences(
		catalog, committed, String(committed.get("state_receipt", ""))
	)
	var after_state: Dictionary = advance.get("after_state", {})
	return _canonical_json(before_projection) == _canonical_json(repeated) \
		and _canonical_json(committed) == before_bytes \
		and _projection_counts(after_projection, 0, 1, 0) \
		and int(after_state.get("epoch_index", -1)) \
		== int(committed.get("epoch_index", -1)) + 1 \
		and String(after_state.get("season", "")) == "autumn"


func _defer_exact(catalog: Dictionary, before: Dictionary,
		advance: Dictionary) -> bool:
	var after: Dictionary = advance.get("after_state", {})
	var epoch_records: Array = after.get("epoch_records", [])
	return not advance.is_empty() and String(advance.get("resolution", "")) == "deferred" \
		and int(advance.get("from_epoch", -1)) == 0 \
		and int(advance.get("to_epoch", -1)) == 1 \
		and epoch_records.size() == 1 \
		and String((epoch_records[0] as Dictionary).get("resolution", "")) == "deferred" \
		and Model.validate_epoch_advance(
			catalog, before, String(before.get("state_receipt", "")), advance).is_empty()


func _winter_terminal_chain(catalog: Dictionary, state0: Dictionary,
		global_receipt: String) -> Dictionary:
	var advance0: Dictionary = Model.advance_epoch(
		catalog, state0, String(state0.get("state_receipt", "")))
	var state1: Dictionary = advance0.get("after_state", {})
	var advance1: Dictionary = Model.advance_epoch(
		catalog, state1, String(state1.get("state_receipt", "")))
	var winter: Dictionary = advance1.get("after_state", {})
	var evidence: Dictionary = _make_evidence(
		catalog, global_receipt, "winter-terminal", {}
	)
	var fixture: Dictionary = _make_board_fixture(
		catalog, winter, evidence, global_receipt, 1, 2, "winter-terminal"
	)
	var board: Dictionary = fixture.get("board", {})
	var fortify: Dictionary = _option_by_action(board, "fortify")
	var choice: Dictionary = Model.make_choice(
		board, String(fortify.get("option_id", "")))
	var commit: Dictionary = _commit(
		catalog, winter, evidence, global_receipt, fixture, board, choice
	)
	var committed: Dictionary = commit.get("after_state", {})
	var advance_terminal: Dictionary = Model.advance_epoch(
		catalog, committed, String(committed.get("state_receipt", "")))
	var terminal: Dictionary = advance_terminal.get("after_state", {})
	if terminal.is_empty():
		return {"ok": false, "detail": "terminal state missing"}
	var terminal_board: Dictionary = Model.make_directive_board(
		catalog, terminal, String(terminal.get("state_receipt", "")),
		evidence.get("adapters", []), evidence.get("acceptances", []),
		GLOBAL_SCOPE, global_receipt, fixture.get("command", {}), COMMAND_SCOPE,
		String(fixture.get("command_checkpoint", "")),
		String((fixture.get("command", {}) as Dictionary).get("anchor_receipt", ""))
	)
	var consequence_id: String = String(
		(commit.get("consequence_record", {}) as Dictionary).get("consequence_id", ""))
	var scheduled_adapter: Dictionary = _adapter_by_key(
		catalog, evidence.get("adapters", []), "basin_relief"
	)
	var scheduled_acceptance: Dictionary = _acceptance_for(
		evidence.get("acceptances", []), String(scheduled_adapter.get("window_id", ""))
	)
	var scheduled_target := {
		"adapter": scheduled_adapter,
		"acceptance": scheduled_acceptance,
	}
	var scheduled_rejected: bool = _deliver(
		catalog, terminal, consequence_id, scheduled_target, global_receipt
	).is_empty()
	var fresh: Dictionary = _fresh_target(
		catalog, "basin_relief", global_receipt, "winter-terminal",
		BASE_SIGNALS["basin_relief"]
	)
	var delivery: Dictionary = _deliver(
		catalog, terminal, consequence_id, fresh, global_receipt
	)
	var projection: Dictionary = Model.project_consequences(
		catalog, terminal, String(terminal.get("state_receipt", "")))
	var terminal_commit: Dictionary = _commit(
		catalog, terminal, evidence, global_receipt, fixture, terminal_board, choice
	)
	var ok: bool = String(terminal.get("phase", "")) == "terminal" \
		and int(terminal.get("epoch_index", -1)) == 3 \
		and String(terminal_board.get("decision_status", "")) == "campaign_terminal" \
		and Model.make_choice(
			terminal_board, String(fortify.get("option_id", ""))).is_empty() \
		and terminal_commit.is_empty() \
		and Model.advance_epoch(
			catalog, terminal, String(terminal.get("state_receipt", ""))).is_empty() \
		and _projection_counts(projection, 0, 1, 0) \
		and scheduled_rejected and not delivery.is_empty() \
		and String(delivery.get("delivery_status", "")) == "applied"
	return {
		"ok": ok,
		"detail": "phase=%s projection=%d delivery=%s" % [
			String(terminal.get("phase", "")),
			(projection.get("deliverable", []) as Array).size(),
			String(delivery.get("delivery_status", "")),
		],
		"terminal": terminal,
		"commit": commit,
		"advance": advance_terminal,
		"delivery": delivery,
		"evidence": evidence,
		"fixture": fixture,
		"board": board,
		"choice": choice,
		"fresh_target": fresh,
	}


func _delivery_applied_exact(catalog: Dictionary, before: Dictionary,
		target: Dictionary, consequence_id: String, global_receipt: String,
		delivery: Dictionary) -> bool:
	if delivery.is_empty() or delivery.get("owner_order", []) \
			!= ["campaign", "target_region"]:
		return false
	if not Model.validate_consequence_delivery(
		catalog, before, String(before.get("state_receipt", "")), consequence_id,
		target.get("adapter", {}), target.get("acceptance", {}),
		GLOBAL_SCOPE, global_receipt, delivery
	).is_empty():
		return false
	var delta: Dictionary = delivery.get("target_region_delta", {})
	var before_signals: Dictionary = delta.get("before_signals", {})
	var after_signals: Dictionary = delta.get("after_signals", {})
	var after_state: Dictionary = delivery.get("after_state", {})
	return String(delivery.get("delivery_status", "")) == "applied" \
		and String(delta.get("status", "")) == "applied" \
		and String(delta.get("track", "")) == "logistics_pressure" \
		and int(delta.get("requested_delta", 0)) == -1 \
		and int(delta.get("applied_delta", 0)) == -1 \
		and int(before_signals.get("logistics_pressure", -1)) == 3 \
		and int(after_signals.get("logistics_pressure", -1)) == 2 \
		and int(after_state.get("revision", -1)) == int(before.get("revision", -1)) + 1 \
		and consequence_id in (after_state.get("delivered_consequence_ids", []) as Array) \
		and Model.validate_state(catalog, after_state).is_empty()


func _delivery_hostiles(catalog: Dictionary, committed: Dictionary,
		advanced: Dictionary, scheduled_evidence: Dictionary,
		fresh_target: Dictionary, global_receipt: String, commit: Dictionary,
		delivery: Dictionary) -> bool:
	var consequence_id: String = String(
		(commit.get("consequence_record", {}) as Dictionary).get("consequence_id", ""))
	var scheduled_adapter: Dictionary = _adapter_by_key(
		catalog, scheduled_evidence.get("adapters", []), "meridian_trade"
	)
	var scheduled_acceptance: Dictionary = _acceptance_for(
		scheduled_evidence.get("acceptances", []),
		String(scheduled_adapter.get("window_id", ""))
	)
	if not _deliver(catalog, advanced, consequence_id, {
		"adapter": scheduled_adapter, "acceptance": scheduled_acceptance,
	}, global_receipt).is_empty():
		return false
	var wrong_target: Dictionary = _fresh_target(
		catalog, "basin_relief", global_receipt, "wrong-target",
		BASE_SIGNALS["basin_relief"]
	)
	if not _deliver(
		catalog, advanced, consequence_id, wrong_target, global_receipt).is_empty():
		return false
	if not Model.deliver_consequence(
		catalog, advanced, String(advanced.get("state_receipt", "")), consequence_id,
		fresh_target.get("adapter", {}), fresh_target.get("acceptance", {}),
		"wrong_global_owner", global_receipt
	).is_empty():
		return false
	if not Model.deliver_consequence(
		catalog, advanced, ZERO_RECEIPT, consequence_id,
		fresh_target.get("adapter", {}), fresh_target.get("acceptance", {}),
		GLOBAL_SCOPE, global_receipt
	).is_empty():
		return false
	var different: Dictionary = (commit.get("consequence_record", {}) as Dictionary).duplicate(true)
	different["consequence_id"] = "pcq1:0000000000000000"
	if not _deliver(
		catalog, advanced, String(different["consequence_id"]),
		fresh_target, global_receipt).is_empty():
		return false
	var tampered: Dictionary = delivery.duplicate(true)
	(tampered.get("target_region_delta", {}) as Dictionary)["applied_delta"] = 0
	_rehash_proposal(tampered, "proposal_id", "pcy1:", "proposal_receipt")
	return not Model.validate_consequence_delivery(
		catalog, advanced, String(advanced.get("state_receipt", "")), consequence_id,
		fresh_target.get("adapter", {}), fresh_target.get("acceptance", {}),
		GLOBAL_SCOPE, global_receipt, tampered
	).is_empty() and not committed.is_empty()


func _delivery_provenance_exact(commit: Dictionary, delivery: Dictionary,
		network_state: Dictionary) -> bool:
	var consequence: Dictionary = delivery.get("consequence", {})
	var origin: Dictionary = commit.get("directive_record", {})
	var target_delta: Dictionary = delivery.get("target_region_delta", {})
	return String(consequence.get("origin_directive_record_id", "")) \
		== String(origin.get("record_id", "")) \
		and String(consequence.get("origin_directive_record_receipt", "")) \
		== String(origin.get("record_receipt", "")) \
		and String(target_delta.get("region_scope", "")) \
		== String(consequence.get("scheduled_target_region_scope", "")) \
		and String(delivery.get("global_network_scope", "")) \
		== String(origin.get("global_network_scope", "")) \
		and String(delivery.get("accepted_global_network_checkpoint_receipt", "")) != "" \
		and not delivery.has("network_delta") and _json_authority_safe(network_state)


func _superseded_chain(catalog: Dictionary, state0: Dictionary,
		global_receipt: String) -> Dictionary:
	var overrides: Dictionary = {}
	for raw_key in WINDOW_KEYS:
		var key: String = String(raw_key)
		overrides[key] = (BASE_SIGNALS[key] as Dictionary).duplicate(true)
	(overrides["meridian_trade"] as Dictionary)["logistics_pressure"] = 0
	var evidence: Dictionary = _make_evidence(
		catalog, global_receipt, "superseded-scheduled", overrides
	)
	var fixture: Dictionary = _make_board_fixture(
		catalog, state0, evidence, global_receipt, 1, 3, "superseded"
	)
	var board: Dictionary = fixture.get("board", {})
	var aid: Dictionary = _option_by_action(board, "aid")
	var choice: Dictionary = Model.make_choice(board, String(aid.get("option_id", "")))
	var commit: Dictionary = _commit(
		catalog, state0, evidence, global_receipt, fixture, board, choice
	)
	var committed: Dictionary = commit.get("after_state", {})
	var advance: Dictionary = Model.advance_epoch(
		catalog, committed, String(committed.get("state_receipt", "")))
	var advanced: Dictionary = advance.get("after_state", {})
	var at_bound: Dictionary = (BASE_SIGNALS["meridian_trade"] as Dictionary).duplicate(true)
	at_bound["logistics_pressure"] = 0
	var target_a: Dictionary = _fresh_target(
		catalog, "meridian_trade", global_receipt, "superseded-a", at_bound
	)
	var target_b: Dictionary = _fresh_target(
		catalog, "meridian_trade", global_receipt, "superseded-b", at_bound
	)
	var consequence_id: String = String(
		(commit.get("consequence_record", {}) as Dictionary).get("consequence_id", ""))
	var sibling_a: Dictionary = _deliver(
		catalog, advanced, consequence_id, target_a, global_receipt
	)
	var sibling_b: Dictionary = _deliver(
		catalog, advanced, consequence_id, target_b, global_receipt
	)
	var after: Dictionary = sibling_a.get("after_state", {})
	var delta: Dictionary = sibling_a.get("target_region_delta", {})
	var exact: bool = not sibling_a.is_empty() and not sibling_b.is_empty() \
		and String(sibling_a.get("delivery_status", "")) == "superseded" \
		and int(delta.get("requested_delta", 0)) == -1 \
		and int(delta.get("applied_delta", 1)) == 0 \
		and _canonical_json(delta.get("before_signals", {})) \
		== _canonical_json(delta.get("after_signals", {})) \
		and int(after.get("revision", -1)) == int(advanced.get("revision", -1)) + 1 \
		and consequence_id in (after.get("delivered_consequence_ids", []) as Array)
	var replay_rejected: bool = _deliver(
		catalog, after, consequence_id, target_a, global_receipt
	).is_empty() and _deliver(
		catalog, after, consequence_id, target_b, global_receipt
	).is_empty()
	var future: Dictionary = _forge_delivery_state(after, "future_epoch")
	var scope: Dictionary = _forge_delivery_state(after, "target_scope")
	return {
		"exact": exact,
		"replay_rejected": replay_rejected,
		"durable_hostiles": not future.is_empty() and not scope.is_empty()
			and not Model.validate_state(catalog, future).is_empty()
			and not Model.validate_state(catalog, scope).is_empty(),
		"commit": commit,
		"advance": advance,
		"delivery": sibling_a,
		"state": after,
	}


func _roundtrip_validates(catalog: Dictionary, state0: Dictionary,
		evidence: Dictionary, global_receipt: String, fixture: Dictionary,
		board: Dictionary, choice: Dictionary, commit: Dictionary,
		advance: Dictionary, target: Dictionary, delivery: Dictionary) -> bool:
	var catalog_json: Dictionary = _json_dictionary(catalog)
	var state_json: Dictionary = _json_dictionary(state0)
	var adapters_json: Array = _json_array(evidence.get("adapters", []))
	var acceptances_json: Array = _json_array(evidence.get("acceptances", []))
	var command_json: Dictionary = _json_dictionary(fixture.get("command", {}))
	var board_json: Dictionary = _json_dictionary(board)
	var choice_json: Dictionary = _json_dictionary(choice)
	var commit_json: Dictionary = _json_dictionary(commit)
	var advance_json: Dictionary = _json_dictionary(advance)
	var target_adapter_json: Dictionary = _json_dictionary(target.get("adapter", {}))
	var target_acceptance_json: Dictionary = _json_dictionary(target.get("acceptance", {}))
	var delivery_json: Dictionary = _json_dictionary(delivery)
	if catalog_json.is_empty() or state_json.is_empty() or adapters_json.is_empty() \
			or command_json.is_empty() or board_json.is_empty() or choice_json.is_empty() \
			or commit_json.is_empty() or advance_json.is_empty() \
			or target_adapter_json.is_empty() or target_acceptance_json.is_empty() \
			or delivery_json.is_empty():
		return false
	var normalized_catalog: Dictionary = Model.normalize_catalog(catalog_json)
	var normalized_state: Dictionary = Model.normalize_state(catalog, state_json)
	var normalized_command: Dictionary = Model.normalize_command_anchor(
		command_json, COMMAND_SCOPE, String(fixture.get("command_checkpoint", "")),
		String((fixture.get("command", {}) as Dictionary).get("anchor_receipt", ""))
	)
	if normalized_catalog.is_empty() or normalized_state.is_empty() \
			or normalized_command.is_empty():
		return false
	var normalized_board: Dictionary = Model.normalize_directive_board(
		catalog, state_json, String(state0.get("state_receipt", "")),
		adapters_json, acceptances_json, GLOBAL_SCOPE, global_receipt, command_json,
		COMMAND_SCOPE, String(fixture.get("command_checkpoint", "")),
		String((fixture.get("command", {}) as Dictionary).get("anchor_receipt", "")),
		board_json
	)
	if normalized_board.is_empty() \
			or Model.normalize_choice(board, choice_json).is_empty():
		return false
	var normalized_commit: Dictionary = Model.normalize_commit_proposal(
		catalog, state_json, String(state0.get("state_receipt", "")),
		adapters_json, acceptances_json, GLOBAL_SCOPE, global_receipt, command_json,
		COMMAND_SCOPE, String(fixture.get("command_checkpoint", "")),
		String((fixture.get("command", {}) as Dictionary).get("anchor_receipt", "")),
		board_json, choice_json, commit_json
	)
	if normalized_commit.is_empty():
		return false
	var committed: Dictionary = commit.get("after_state", {})
	if Model.normalize_epoch_advance(
		catalog, _json_dictionary(committed),
		String(committed.get("state_receipt", "")), advance_json
	).is_empty():
		return false
	var advanced: Dictionary = advance.get("after_state", {})
	var consequence_id: String = String(
		(commit.get("consequence_record", {}) as Dictionary).get("consequence_id", ""))
	return not Model.normalize_consequence_delivery(
		catalog, _json_dictionary(advanced), String(advanced.get("state_receipt", "")),
		consequence_id, target_adapter_json, target_acceptance_json,
		GLOBAL_SCOPE, global_receipt, delivery_json
	).is_empty()


func _roundtrip_continuation_exact(catalog: Dictionary, committed: Dictionary,
		advance: Dictionary, terminal_chain: Dictionary,
		global_receipt: String) -> bool:
	var committed_json: Dictionary = _json_dictionary(committed)
	var continued: Dictionary = Model.advance_epoch(
		catalog, committed_json, String(committed.get("state_receipt", ""))
	)
	if _canonical_json(continued) != _canonical_json(advance):
		return false
	var terminal: Dictionary = terminal_chain.get("terminal", {})
	var winter_commit: Dictionary = terminal_chain.get("commit", {})
	var consequence_id: String = String(
		(winter_commit.get("consequence_record", {}) as Dictionary).get("consequence_id", ""))
	var fresh: Dictionary = terminal_chain.get("fresh_target", {})
	var expected: Dictionary = terminal_chain.get("delivery", {})
	var terminal_json: Dictionary = _json_dictionary(terminal)
	var target_json := {
		"adapter": _json_dictionary(fresh.get("adapter", {})),
		"acceptance": _json_dictionary(fresh.get("acceptance", {})),
	}
	var delivery: Dictionary = _deliver(
		catalog, terminal_json, consequence_id, target_json, global_receipt
	)
	return not delivery.is_empty() and _canonical_json(delivery) == _canonical_json(expected)


func _receipt_suite_exact(catalog: Dictionary, board: Dictionary,
		commit: Dictionary, advance: Dictionary, delivery: Dictionary,
		state: Dictionary) -> bool:
	if not _catalog_receipt_exact(catalog):
		return false
	for pair in [
		[board, "board_receipt"],
		[commit, "proposal_receipt"],
		[advance, "transition_receipt"],
		[delivery, "proposal_receipt"],
		[state, "state_receipt"],
	]:
		var data: Dictionary = pair[0]
		var key: String = String(pair[1])
		if data.is_empty() or not _receipt_field_exact(data, key):
			return false
	return true


func _anti_physical_validators(atlas: Dictionary, commit: Dictionary,
		delivery: Dictionary) -> bool:
	var atlas_state: Dictionary = Routes.make_initial_atlas_state(atlas)
	var origin: String = Routes.site_tile_id(atlas, "ash_market")
	var destination: String = Routes.site_tile_id(atlas, "cinder_crossing")
	var plan: Dictionary = Routes.make_route_plan(
		atlas, atlas_state, origin, destination, "autumn", "safe", [], "",
		"rp7-anti-physical"
	)
	var journey: Dictionary = Routes.begin_journey(
		atlas, atlas_state, plan, "rp7-anti-physical", 100000, 100000
	)
	var route_receipt: Dictionary = Routes.route_receipt(
		atlas, atlas_state, plan, journey
	)
	if plan.is_empty() or journey.is_empty() or route_receipt.is_empty() \
			or not Routes.validate_route_receipt(
				atlas, atlas_state, plan, journey, route_receipt).is_empty():
		return false
	if Routes.validate_route_receipt(
		atlas, atlas_state, plan, journey, commit).is_empty() \
			or Routes.validate_route_receipt(
				atlas, atlas_state, plan, journey, delivery).is_empty():
		return false
	var network_catalog: Dictionary = Network.make_catalog(atlas)
	if network_catalog.is_empty():
		return false
	var first_node: Dictionary = (network_catalog.get("nodes", []) as Array)[0]
	return Network.make_arrival_evidence(
		network_catalog, String(first_node.get("node_id", "")), atlas, atlas_state,
		plan, journey, commit, String(journey.get("state_receipt", ""))
	).is_empty()


func _contains_forbidden_authority(value: Variant, forbidden: Array) -> bool:
	match typeof(value):
		TYPE_STRING:
			var text: String = String(value).to_lower()
			for raw_word in forbidden:
				if text.contains(String(raw_word).to_lower()):
					return true
		TYPE_ARRAY:
			for item in value as Array:
				if _contains_forbidden_authority(item, forbidden):
					return true
		TYPE_DICTIONARY:
			var data: Dictionary = value
			for raw_key in data:
				if _contains_forbidden_authority(String(raw_key), forbidden) \
						or _contains_forbidden_authority(data[raw_key], forbidden):
					return true
	return false


func _json_dictionary(value: Variant) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed if parsed is Dictionary else {}


func _json_array(value: Variant) -> Array:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed if parsed is Array else []


func _json_authority_safe(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_INT:
			return abs(int(value)) <= 9007199254740991
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


func _forge_committed_state(source: Dictionary, mode: String) -> Dictionary:
	var state: Dictionary = source.duplicate(true)
	var directives: Array = state.get("directive_records", [])
	if directives.size() != 1:
		return {}
	var directive: Dictionary = (directives[0] as Dictionary).duplicate(true)
	match mode:
		"epoch_link":
			directive["epoch_index"] = 1
			directive["season"] = "autumn"
			directive["capacity_cost"] = 3
			directive["primary_requested"] = -2
			directive["primary_applied"] = -2
			directive["consequence_release_epoch"] = 2
		"all_noop":
			directive["primary_applied"] = 0
			directive["faction_applied"] = 0
		"replay_key":
			directive["commitment_replay_key"] = \
				"sha256:9999999999999999999999999999999999999999999999999999999999999999"
			state["consumed_commitment_keys"] = [directive["commitment_replay_key"]]
		"scope_collision":
			directive["origin_region_scope"] = String(directive["command_owner_scope"])
		_:
			return {}
	_rehash_typed_record(directive, "record_id", "pcr1:", "record_receipt")
	state["directive_records"] = [directive]
	var rebuilt_epochs: Array[Dictionary] = []
	for raw_epoch in state.get("epoch_records", []) as Array:
		var epoch: Dictionary = (raw_epoch as Dictionary).duplicate(true)
		if String(epoch.get("resolution", "")) == "directive":
			epoch["directive_record_id"] = String(directive["record_id"])
			epoch["directive_record_receipt"] = String(directive["record_receipt"])
			_rehash_typed_record(epoch, "record_id", "pce1:", "record_receipt")
		rebuilt_epochs.append(epoch)
	state["epoch_records"] = rebuilt_epochs
	var consequences: Array = state.get("consequence_records", [])
	if consequences.size() != 1:
		return {}
	var consequence: Dictionary = (consequences[0] as Dictionary).duplicate(true)
	consequence["origin_directive_record_id"] = String(directive["record_id"])
	consequence["origin_directive_record_receipt"] = String(directive["record_receipt"])
	if mode == "epoch_link":
		consequence["origin_epoch"] = 1
		consequence["release_epoch"] = 2
	_rehash_typed_record(
		consequence, "consequence_id", "pcq1:", "consequence_receipt"
	)
	state["consequence_records"] = [consequence]
	state["last_action_receipt"] = String(directive["record_receipt"])
	_rehash_state(state)
	return state


func _forge_delivery_state(source: Dictionary, mode: String) -> Dictionary:
	var state: Dictionary = source.duplicate(true)
	var records: Array = state.get("delivery_records", [])
	if records.size() != 1:
		return {}
	var record: Dictionary = (records[0] as Dictionary).duplicate(true)
	if mode == "future_epoch":
		record["delivered_epoch"] = 4
	elif mode == "target_scope":
		record["target_region_scope"] = "forged_target_region"
	else:
		return {}
	_rehash_typed_record(record, "record_id", "pcv1:", "record_receipt")
	state["delivery_records"] = [record]
	state["last_action_receipt"] = String(record["record_receipt"])
	_rehash_state(state)
	return state


func _rehash_board_with_sparse_option(source: Dictionary) -> Dictionary:
	if source.is_empty() or (source.get("options", []) as Array).is_empty():
		return {}
	var board: Dictionary = source.duplicate(true)
	var original: Dictionary = (board.get("options", []) as Array)[0]
	board["options"] = [{"option_id": String(original.get("option_id", ""))}]
	var id_base: Dictionary = board.duplicate(true)
	id_base.erase("board_id")
	id_base.erase("board_receipt")
	var digest := _sha256_hex(_canonical_json(id_base))
	board["board_id"] = "pcb1:" + digest.substr(0, 16)
	var receipt_base: Dictionary = board.duplicate(true)
	receipt_base.erase("board_receipt")
	board["board_receipt"] = _receipt_for(receipt_base)
	return board


func _rehash_typed_record(record: Dictionary, id_key: String, prefix: String,
		receipt_key: String) -> void:
	var id_base: Dictionary = record.duplicate(true)
	id_base.erase(id_key)
	id_base.erase(receipt_key)
	var digest := _sha256_hex(_canonical_json(id_base))
	record[id_key] = prefix + digest.substr(0, 16)
	var receipt_base: Dictionary = record.duplicate(true)
	receipt_base.erase(receipt_key)
	record[receipt_key] = _receipt_for(receipt_base)


func _rehash_state(state: Dictionary) -> void:
	var base: Dictionary = state.duplicate(true)
	base.erase("state_receipt")
	state["state_receipt"] = _receipt_for(base)


func _rehash_catalog(catalog: Dictionary) -> void:
	var authority: Dictionary = catalog.duplicate(true)
	authority.erase("catalog_id")
	authority.erase("catalog_receipt")
	var digest := _sha256_hex(_canonical_json(authority))
	catalog["catalog_id"] = "pcc1:" + digest.substr(0, 16)
	catalog["catalog_receipt"] = "sha256:" + digest


func _rehash_proposal(proposal: Dictionary, id_key: String, prefix: String,
		receipt_key: String) -> void:
	var id_base: Dictionary = proposal.duplicate(true)
	id_base.erase(id_key)
	id_base.erase(receipt_key)
	var digest := _sha256_hex(_canonical_json(id_base))
	proposal[id_key] = prefix + digest.substr(0, 16)
	var receipt_base: Dictionary = proposal.duplicate(true)
	receipt_base.erase(receipt_key)
	proposal[receipt_key] = _receipt_for(receipt_base)


func _receipt_field_exact(data: Dictionary, receipt_key: String) -> bool:
	var base: Dictionary = data.duplicate(true)
	base.erase(receipt_key)
	return String(data.get(receipt_key, "")) == _receipt_for(base)


func _receipt_for(value: Variant) -> String:
	var encoded := _canonical_json(value)
	return "sha256:" + _sha256_hex(encoded) if encoded != "" else ""


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
			var integer := int(value)
			return str(integer) if abs(integer) <= 9007199254740991 else ""
		TYPE_FLOAT:
			var number := float(value)
			return str(int(number)) if is_finite(number) and number == floor(number) \
				and absf(number) <= 9007199254740991.0 else ""
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
