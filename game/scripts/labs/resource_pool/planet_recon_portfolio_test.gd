extends Node

const Model = preload("res://scripts/labs/resource_pool/PlanetReconPortfolioModel.gd")
const Campaign = preload("res://scripts/labs/resource_pool/PlanetCampaignModel.gd")
const Covenant = preload("res://scripts/labs/resource_pool/CampaignCovenantModel.gd")
const Routes = preload("res://scripts/labs/resource_pool/RegionRouteModel.gd")
const Network = preload("res://scripts/labs/resource_pool/SettlementNetworkModel.gd")
const Address = preload("res://scripts/labs/resource_pool/ScaleAddress.gd")

const ROOT_SEED := 260814
const CAMPAIGN_SCOPE := "ashfall_planet_campaign"
const GLOBAL_SCOPE := "ashfall_settlement_network"
const RECON_SCOPE := "ashfall_recon_capacity"
const CARGO_SCOPE := "ashfall_caravan"
const COMMAND_SCOPE := "ashfall_campaign_command"
const AMPLE_ROUTE_RESOURCE := 100000
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

var _checks: int = 0
var _fails: int = 0


func _ready() -> void:
	print("=== RP-0009 accepted planet recon portfolio contract ===")
	var fixture: Dictionary = _make_fixture()
	_check("fixture composes accepted RP3/RP6/RP7/RP8 authority", not fixture.is_empty())
	if fixture.is_empty():
		_finish({})
		return
	var catalog: Dictionary = fixture["catalog"]
	var evidence: Dictionary = fixture["evidence"]
	var state0: Dictionary = fixture["state0"]
	var anchor: Dictionary = fixture["anchor"]
	var board: Dictionary = fixture["board"]
	var choice: Dictionary = fixture["choice"]
	var commit: Dictionary = fixture["commit"]
	var committed: Dictionary = fixture["committed"]
	var bundle: Dictionary = fixture["bundle"]
	var resolution: Dictionary = fixture["resolution"]
	var resolved: Dictionary = fixture["resolved"]
	var stale: Dictionary = fixture["stale"]
	var stale_state: Dictionary = fixture["stale_state"]

	_group(1, "catalog identity and deterministic questions")
	var rebuilt_catalog: Dictionary = Model.make_catalog(
		fixture["campaign_catalog"], fixture["covenant_catalog"])
	_check("catalog recompiles byte-identically", _canonical_json(catalog) == _canonical_json(rebuilt_catalog))
	_check("catalog validates only against exact RP7/RP8 catalogs",
		Model.validate_catalog(fixture["campaign_catalog"], fixture["covenant_catalog"], catalog).is_empty())
	_check("catalog exposes exactly three canonical region questions", _catalog_oracle(catalog))

	_group(2, "exact evidence envelope")
	_check("evidence validator recomputes all accepted inputs", _validate_evidence(fixture, evidence).is_empty())
	_check("evidence stores exact external checkpoints and owner scopes", _evidence_anchor_oracle(fixture))
	_check("same inputs reproduce exact evidence receipt", String(evidence["evidence_receipt"]) == String(_make_evidence(fixture)["evidence_receipt"]))

	_group(3, "grounding and canonical planet identity")
	_check("only Basin is grounded by available discovered Redglass intel", _prior_oracle(evidence))
	_check("Redglass site canonically parents to the discovered face-0 tile and Basin region", _redglass_parent_oracle(fixture))
	_check("same-coordinate wrong-face discovery does not replace the canonical subject", _wrong_face_rejected(fixture))

	_group(4, "active covenant roles and initial state")
	_check("Exchange assigns duty, spillover, fallback to three distinct windows", _role_oracle(evidence))
	_check("initial state is exact open revision zero", String(state0["phase"]) == "open" and int(state0["revision"]) == 0 and Model.validate_state(catalog, state0).is_empty())
	_check("state checkpoint requires the independently accepted receipt", Model.accept_state_checkpoint(catalog, state0, String(state0["state_receipt"])) == state0 and Model.accept_state_checkpoint(catalog, state0, _external_receipt("wrong-state")).is_empty())

	_group(5, "independent 2-of-3 Pareto oracle")
	_check("capacity two yields all three non-dominated role pairs in strict ID order", _board_oracle(state0, board))
	_check("fallback pair is selected without scalar recommendation", _choice_oracle(board, choice, ["duty", "fallback"]))
	_check("board and choice independently validate", _validate_board(fixture, board).is_empty() and Model.validate_portfolio_choice(catalog, board, choice).is_empty())

	_group(6, "recon capacity owner CAS and replay")
	_check("anchor binds scope, checkpoint, snapshot and exact capacity", _anchor_oracle(evidence, anchor))
	_check("capacity below two produces no eligible portfolio", _capacity_one_oracle(fixture))
	_check("scope aliases and a re-anchored payload are rejected", _anchor_alias_hostiles(fixture))

	_group(7, "board and choice fail closed")
	_check("stale evidence, sibling board and mixed choice are rejected", _board_choice_mix_hostiles(fixture))
	_check("unknown and cyclic board candidates fail without mutation", _board_shape_hostiles(fixture))

	_group(8, "commit joint proposal and durable provenance")
	_check("commit validates and conserves belief plus recon owners", _commit_oracle(fixture, commit))
	_check("committed state exact-reconstructs selected probes and replay key", _committed_oracle(catalog, committed, board, choice, anchor))
	_check("self-rehashed probe, option, anchor and replay substitutions reject", _commit_record_hostiles(fixture))

	_group(9, "two-report bundle owner checkpoint")
	_check("bundle contains exactly the two selected probes and fresh report checkpoint", _bundle_oracle(committed, bundle, fixture["report_checkpoint"]))
	_check("bundle validates only with its external accepted receipt", _validate_bundle(fixture, bundle).is_empty() and not _validate_bundle(fixture, bundle, _external_receipt("wrong-bundle")).is_empty())
	_check("duplicate, unselected, stale-checkpoint and mixed-report candidates reject", _bundle_hostiles(fixture))

	_group(10, "terminal resolution and belief conservation")
	_check("resolution validates as a belief-only joint proposal", _resolution_oracle(fixture, resolution))
	_check("favorable/mixed reports produce exact posterior intervals; unselected prior stays exact", _posterior_oracle(resolved))
	_check("terminal self-rehash attacks cannot forge observations or beliefs", _resolved_state_hostiles(fixture))

	_group(11, "changed-snapshot stale close")
	_check("unchanged accepted snapshots cannot stale-close", _unchanged_stale_rejected(fixture))
	_check("changed RP7 snapshot closes stale with priors unchanged and no refund", _stale_oracle(fixture, stale, stale_state))
	_check("changed snapshot rejects resolution and stale siblings cannot both settle", _stale_resolution_cas_oracle(fixture))

	_group(12, "JSON, numeric and hostile structure")
	_check("JSON/Variant continuation normalizes integral numerics to TYPE_INT", _json_continuation_oracle(fixture))
	_check("fraction, NaN, infinity, huge number, string number and unknown fields reject", _numeric_hostiles(fixture))
	_check("deep, oversized and cyclic candidates fail closed", _canonical_budget_hostiles(fixture))

	_group(13, "observation independence and stable receipts")
	_check("projection is pure and does not advance campaign, covenant, atlas, or network owners", _projection_independence(fixture))
	_check("inputs remain deeply unchanged across commit, resolve, and stale branches", _input_immutability_oracle(fixture))
	_check("all authority receipts independently recompute and remain deterministic", _receipt_suite_oracle(fixture))

	_finish(fixture)


func _make_fixture() -> Dictionary:
	var atlas: Dictionary = Routes.make_atlas(ROOT_SEED)
	var network_fixture: Dictionary = _make_network_fixture(atlas)
	if atlas.is_empty() or network_fixture.is_empty():
		print("FIXTURE_BLOCK=network atlas:", atlas.size(), " network:", network_fixture.size())
		return {}
	var campaign_catalog: Dictionary = Campaign.make_catalog(ROOT_SEED)
	var campaign0: Dictionary = Campaign.make_initial_state(campaign_catalog)
	var advance1: Dictionary = Campaign.advance_epoch(
		campaign_catalog, campaign0, String(campaign0.get("state_receipt", "")))
	var campaign1: Dictionary = advance1.get("after_state", {})
	var covenant_catalog: Dictionary = Covenant.make_catalog(campaign_catalog)
	var covenant0: Dictionary = Covenant.make_initial_state(covenant_catalog)
	var covenant_evidence: Dictionary = _make_window_evidence(
		campaign_catalog, String(network_fixture["network0"]["state_receipt"]), "rp9-bind")
	var covenant_board: Dictionary = Covenant.make_covenant_board(
		covenant_catalog, covenant0, String(covenant0.get("state_receipt", "")),
		campaign_catalog, campaign0, String(campaign0.get("state_receipt", "")),
		CAMPAIGN_SCOPE, covenant_evidence.get("adapters", []),
		covenant_evidence.get("acceptances", []), GLOBAL_SCOPE,
		String(network_fixture["network0"]["state_receipt"]))
	var exchange_option: Dictionary = _covenant_option(covenant_board, "trade")
	var covenant_choice: Dictionary = Covenant.make_covenant_choice(
		covenant_board, String(exchange_option.get("option_id", "")))
	var covenant_bind: Dictionary = Covenant.bind_covenant(
		covenant_catalog, covenant0, String(covenant0.get("state_receipt", "")),
		campaign_catalog, campaign0, String(campaign0.get("state_receipt", "")),
		CAMPAIGN_SCOPE, covenant_evidence.get("adapters", []),
		covenant_evidence.get("acceptances", []), GLOBAL_SCOPE,
		String(network_fixture["network0"]["state_receipt"]), covenant_board,
		covenant_choice)
	var covenant_state: Dictionary = covenant_bind.get("after_state", {})
	var obligation: Dictionary = Covenant.project_obligation(
		covenant_catalog, covenant_state,
		String(covenant_state.get("state_receipt", "")), campaign_catalog,
		campaign0, String(campaign0.get("state_receipt", "")), CAMPAIGN_SCOPE)
	var redglass_tile: String = _site_tile(atlas, "redglass_quarry")
	var atlas_state: Dictionary = Routes.make_atlas_state(atlas, [redglass_tile], [])
	var catalog: Dictionary = Model.make_catalog(campaign_catalog, covenant_catalog)
	var shell := {
		"atlas": atlas, "atlas_state": atlas_state,
		"network_catalog": network_fixture["catalog"],
		"network_state": network_fixture["network2"],
		"intel": network_fixture["intel"],
		"campaign_catalog": campaign_catalog, "campaign0": campaign0,
		"campaign1": campaign1, "covenant_catalog": covenant_catalog,
		"covenant_state": covenant_state, "obligation": obligation,
		"catalog": catalog,
	}
	var evidence: Dictionary = _make_evidence(shell)
	var state0: Dictionary = Model.make_initial_state(catalog, evidence)
	if covenant_bind.is_empty() or covenant_state.is_empty() or obligation.is_empty() \
			or catalog.is_empty() or evidence.is_empty() or state0.is_empty():
		print("FIXTURE_BLOCK=authority covenant_bind:", covenant_bind.size(),
			" covenant_state:", covenant_state.size(), " obligation:", obligation.size(),
			" catalog:", catalog.size(), " evidence:", evidence.size(),
			" state0:", state0.size())
		return {}
	var recon_checkpoint: String = _external_receipt("rp9-recon-owner")
	var anchor: Dictionary = Model.make_recon_anchor(
		RECON_SCOPE, recon_checkpoint, String(evidence.get("evidence_receipt", "")), 2)
	var shell2: Dictionary = shell.duplicate(true)
	shell2.merge({
		"evidence": evidence, "state0": state0, "anchor": anchor,
		"recon_checkpoint": recon_checkpoint,
	}, true)
	var board: Dictionary = _make_board(shell2, state0, evidence, anchor)
	var option: Dictionary = _portfolio_option(board, ["duty", "fallback"])
	var choice: Dictionary = Model.make_portfolio_choice(
		catalog, board, String(option.get("portfolio_id", "")))
	var commit: Dictionary = _commit(shell2, state0, evidence, anchor, board, choice)
	var committed: Dictionary = commit.get("after_state", {})
	var report_checkpoint: String = _external_receipt("rp9-report-owner")
	var sparse: Array[Dictionary] = _sparse_reports(committed)
	var bundle: Dictionary = Model.make_observation_bundle(
		catalog, committed, String(committed.get("state_receipt", "")),
		RECON_SCOPE, report_checkpoint, sparse)
	var resolution: Dictionary = Model.resolve_portfolio(
		campaign_catalog, covenant_catalog, catalog, committed,
		String(committed.get("state_receipt", "")), campaign0,
		String(campaign0.get("state_receipt", "")), CAMPAIGN_SCOPE,
		covenant_state, String(covenant_state.get("state_receipt", "")),
		GLOBAL_SCOPE, bundle, RECON_SCOPE, report_checkpoint,
		String(bundle.get("bundle_receipt", "")))
	var stale: Dictionary = Model.close_stale(
		campaign_catalog, covenant_catalog, catalog, committed,
		String(committed.get("state_receipt", "")), campaign1,
		String(campaign1.get("state_receipt", "")), CAMPAIGN_SCOPE,
		covenant_state, String(covenant_state.get("state_receipt", "")),
		GLOBAL_SCOPE)
	shell2.merge({
		"board": board, "choice": choice, "commit": commit,
		"committed": committed, "report_checkpoint": report_checkpoint,
		"sparse_reports": sparse, "bundle": bundle,
		"resolution": resolution, "resolved": resolution.get("after_state", {}),
		"stale": stale, "stale_state": stale.get("after_state", {}),
		"network0": network_fixture["network0"],
	}, true)
	for key in ["catalog", "evidence", "state0", "board", "choice", "commit",
			"committed", "bundle", "resolution", "resolved", "stale", "stale_state"]:
		if not shell2.has(key) or not (shell2[key] is Dictionary) \
				or (shell2[key] as Dictionary).is_empty():
			print("FIXTURE_BLOCK=rp9 key:", key, " sizes:", [board.size(), choice.size(),
				commit.size(), committed.size(), bundle.size(), resolution.size(), stale.size()])
			return {}
	return shell2


func _make_network_fixture(atlas: Dictionary) -> Dictionary:
	var catalog: Dictionary = Network.make_catalog(atlas)
	var network0: Dictionary = Network.make_initial_state(catalog)
	var source_refs: Array = _source_refs(catalog)
	var first: Dictionary = _settle_network_offer(
		atlas, catalog, network0, "orra_relay_fortification", "rp9-net-a", source_refs)
	var network1: Dictionary = first.get("after_state", {})
	var second: Dictionary = _settle_network_offer(
		atlas, catalog, network1, "dunlin_parts_trade", "rp9-net-b", source_refs)
	var network2: Dictionary = second.get("after_state", {})
	var intel: Dictionary = Network.project_intel(
		catalog, network2, String(network2.get("state_receipt", "")))
	if catalog.is_empty() or network0.is_empty() or first.is_empty() \
			or second.is_empty() or intel.is_empty():
		print("NETWORK_BLOCK=", [catalog.size(), network0.size(), first.size(),
			network1.size(), second.size(), network2.size(), intel.size()])
		return {}
	return {"catalog": catalog, "network0": network0, "network1": network1,
		"network2": network2, "first": first, "second": second, "intel": intel}


func _settle_network_offer(atlas: Dictionary, catalog: Dictionary,
		state: Dictionary, offer_key: String, tag: String, source_refs: Array) -> Dictionary:
	var owner_checkpoint: String = _external_receipt("cargo-" + tag)
	var anchor: Dictionary = Network.make_cargo_anchor(
		CARGO_SCOPE, owner_checkpoint, _cargo(0, 0, 2, 0), 80, source_refs)
	var board: Dictionary = Network.make_offer_board(
		catalog, state, String(state.get("state_receipt", "")), anchor,
		CARGO_SCOPE, owner_checkpoint)
	var option: Dictionary = _network_option(catalog, board, offer_key)
	var choice: Dictionary = Network.make_choice(board, String(option.get("offer_id", "")))
	var destination: String = _network_node_tile(catalog, String(option.get("node_id", "")))
	var route: Dictionary = _arrived_route(atlas, destination, tag)
	var arrival: Dictionary = Network.make_arrival_evidence(
		catalog, String(option.get("node_id", "")), route.get("atlas", {}),
		route.get("atlas_state", {}), route.get("plan", {}),
		route.get("journey", {}), route.get("route_receipt", {}),
		String(route.get("accepted_journey_state_receipt", "")))
	var result: Dictionary = Network.propose_settlement(
		catalog, state, String(state.get("state_receipt", "")), anchor,
		CARGO_SCOPE, owner_checkpoint, board, choice, route.get("atlas", {}),
		route.get("atlas_state", {}), route.get("plan", {}),
		route.get("journey", {}), route.get("route_receipt", {}),
		String(route.get("accepted_journey_state_receipt", "")), arrival)
	if result.is_empty():
		print("SETTLE_BLOCK=", offer_key, " sizes:", [anchor.size(), board.size(),
			option.size(), choice.size(), route.size(), arrival.size()], " status:",
			board.get("decision_status", ""), " destination:", destination,
			" route_phase:", route.get("journey", {}).get("phase", ""))
	return result


func _arrived_route(atlas: Dictionary, destination: String, slot: String) -> Dictionary:
	var atlas_state: Dictionary = Routes.make_initial_atlas_state(atlas)
	var route_board: Dictionary = Routes.route_board(
		atlas, atlas_state, destination, destination, "autumn",
		AMPLE_ROUTE_RESOURCE, AMPLE_ROUTE_RESOURCE)
	var plan: Dictionary = {}
	for raw_offer in route_board.get("offers", []) as Array:
		if raw_offer is Dictionary:
			var candidate: Dictionary = (raw_offer as Dictionary).get("plan", {})
			if bool(candidate.get("available", false)) \
					and (plan.is_empty() or (candidate.get("path", []) as Array).size() \
					< (plan.get("path", []) as Array).size()):
				plan = candidate
	var journey: Dictionary = Routes.begin_journey(
		atlas, atlas_state, plan, slot, AMPLE_ROUTE_RESOURCE, AMPLE_ROUTE_RESOURCE)
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
	var route_receipt: Dictionary = Routes.route_receipt(atlas, atlas_state, plan, journey)
	return {"atlas": atlas, "atlas_state": atlas_state, "plan": plan,
		"journey": journey, "route_receipt": route_receipt,
		"accepted_journey_state_receipt": String(journey.get("state_receipt", ""))}


func _make_window_evidence(catalog: Dictionary, global_receipt: String,
		tag: String) -> Dictionary:
	var adapters: Array[Dictionary] = []
	var acceptances: Array[Dictionary] = []
	for raw_key in WINDOW_KEYS:
		var key: String = String(raw_key)
		var window: Dictionary = _campaign_window(catalog, key)
		var scope: String = "rp7_region_%s" % key
		var checkpoint: String = _external_receipt("%s-%s" % [tag, key])
		var signals: Dictionary = (BASE_SIGNALS[key] as Dictionary).duplicate(true)
		var adapter: Dictionary = Campaign.make_window_adapter(
			catalog, key, scope, checkpoint, GLOBAL_SCOPE, global_receipt, signals)
		var acceptance: Dictionary = Campaign.make_window_acceptance(
			String(window.get("window_id", "")), scope, checkpoint,
			String(adapter.get("adapter_receipt", "")))
		adapters.append(adapter)
		acceptances.append(acceptance)
	return {"adapters": adapters, "acceptances": acceptances}


func _make_evidence(fixture: Dictionary) -> Dictionary:
	return Model.make_evidence_envelope(
		fixture["catalog"], fixture["atlas"], fixture["atlas_state"],
		String(fixture["atlas_state"].get("state_receipt", "")),
		fixture["network_catalog"], fixture["network_state"],
		String(fixture["network_state"].get("state_receipt", "")), fixture["intel"],
		fixture["campaign_catalog"], fixture["campaign0"],
		String(fixture["campaign0"].get("state_receipt", "")), CAMPAIGN_SCOPE,
		fixture["covenant_catalog"], fixture["covenant_state"],
		String(fixture["covenant_state"].get("state_receipt", "")),
		fixture["obligation"], GLOBAL_SCOPE)


func _validate_evidence(fixture: Dictionary, value: Variant) -> Array[String]:
	return Model.validate_evidence_envelope(
		fixture["catalog"], fixture["atlas"], fixture["atlas_state"],
		String(fixture["atlas_state"].get("state_receipt", "")),
		fixture["network_catalog"], fixture["network_state"],
		String(fixture["network_state"].get("state_receipt", "")), fixture["intel"],
		fixture["campaign_catalog"], fixture["campaign0"],
		String(fixture["campaign0"].get("state_receipt", "")), CAMPAIGN_SCOPE,
		fixture["covenant_catalog"], fixture["covenant_state"],
		String(fixture["covenant_state"].get("state_receipt", "")),
		fixture["obligation"], GLOBAL_SCOPE, value)


func _make_board(fixture: Dictionary, state: Dictionary, evidence: Dictionary,
		anchor: Dictionary) -> Dictionary:
	return Model.make_portfolio_board(
		fixture["campaign_catalog"], fixture["covenant_catalog"], fixture["catalog"],
		state, String(state.get("state_receipt", "")), evidence,
		String(evidence.get("evidence_receipt", "")), anchor, RECON_SCOPE,
		String(fixture["recon_checkpoint"]), String(anchor.get("anchor_receipt", "")))


func _validate_board(fixture: Dictionary, value: Variant) -> Array[String]:
	return Model.validate_portfolio_board(
		fixture["campaign_catalog"], fixture["covenant_catalog"], fixture["catalog"],
		fixture["state0"], String(fixture["state0"].get("state_receipt", "")),
		fixture["evidence"], String(fixture["evidence"].get("evidence_receipt", "")),
		fixture["anchor"], RECON_SCOPE, String(fixture["recon_checkpoint"]),
		String(fixture["anchor"].get("anchor_receipt", "")), value)


func _commit(fixture: Dictionary, state: Dictionary, evidence: Dictionary,
		anchor: Dictionary, board: Dictionary, choice: Dictionary) -> Dictionary:
	return Model.commit_portfolio(
		fixture["campaign_catalog"], fixture["covenant_catalog"], fixture["catalog"],
		state, String(state.get("state_receipt", "")), evidence,
		String(evidence.get("evidence_receipt", "")), anchor, RECON_SCOPE,
		String(fixture["recon_checkpoint"]), String(anchor.get("anchor_receipt", "")),
		board, choice)


func _sparse_reports(committed: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_probe in committed.get("commitment_record", {}).get("selected_probes", []) as Array:
		if raw_probe is Dictionary:
			var probe: Dictionary = raw_probe
			var role: String = String(probe.get("role", ""))
			result.append({
				"probe_id": String(probe.get("probe_id", "")),
				"signal": "favorable" if role == "duty" else "mixed",
				"source_receipt": _external_receipt("report-source-" + role),
			})
	return result


func _finish(fixture: Dictionary) -> void:
	if not fixture.is_empty():
		print("PLANET_RECON_CATALOG_RECEIPT=", fixture["catalog"].get("catalog_receipt", ""))
		print("PLANET_RECON_EVIDENCE_RECEIPT=", fixture["evidence"].get("evidence_receipt", ""))
		print("PLANET_RECON_COMMIT_RECEIPT=", fixture["commit"].get("proposal_receipt", ""))
		print("PLANET_RECON_OBSERVATION_RECEIPT=", fixture["bundle"].get("bundle_receipt", ""))
		print("PLANET_RECON_RESOLUTION_RECEIPT=", fixture["resolution"].get("proposal_receipt", ""))
		print("PLANET_RECON_STALE_RECEIPT=", fixture["stale"].get("proposal_receipt", ""))
	if _fails == 0:
		print("planet_recon_portfolio_test: PASS (0 fail, %d checks)" % _checks)
	else:
		print("planet_recon_portfolio_test: FAIL (%d fail, %d checks)" % [_fails, _checks])
	get_tree().quit(0 if _fails == 0 else 1)


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	print("  %s %s%s" % ["PASS" if condition else "FAIL", label,
		("  " + detail) if detail != "" else ""])
	if not condition:
		_fails += 1


func _group(index: int, label: String) -> void:
	print("-- %02d %s --" % [index, label])


func _cargo(food: Variant, meds: Variant, parts: Variant, scrap: Variant) -> Dictionary:
	return {"food": food, "meds": meds, "parts": parts, "scrap": scrap}


func _source_refs(catalog: Dictionary) -> Array:
	return [{"schema": Network.SOURCE_REF_SCHEMA, "kind": "site_visit",
		"source_id": "svt1:rp9-provenance",
		"source_address": _context_site(catalog, "ash_market"),
		"source_receipt": _external_receipt("site-visit-provenance")},
		{"schema": Network.SOURCE_REF_SCHEMA, "kind": "expedition_outcome",
		"source_id": "outcome-rp9-provenance", "source_address": "",
		"source_receipt": _external_receipt("expedition-provenance")}]


func _network_option(catalog: Dictionary, board: Dictionary, key: String) -> Dictionary:
	var offer_id: String = ""
	for raw_offer in catalog.get("offers", []) as Array:
		if raw_offer is Dictionary and String((raw_offer as Dictionary).get("offer_key", "")) == key:
			offer_id = String((raw_offer as Dictionary).get("offer_id", ""))
	for raw_option in board.get("options", []) as Array:
		if raw_option is Dictionary and String((raw_option as Dictionary).get("offer_id", "")) == offer_id:
			return (raw_option as Dictionary).duplicate(true)
	return {}


func _network_node_tile(catalog: Dictionary, node_id: String) -> String:
	for raw_node in catalog.get("nodes", []) as Array:
		if raw_node is Dictionary and String((raw_node as Dictionary).get("node_id", "")) == node_id:
			return String((raw_node as Dictionary).get("tile_id", ""))
	return ""


func _context_site(catalog: Dictionary, key: String) -> String:
	for raw_site in catalog.get("context_sites", []) as Array:
		if raw_site is Dictionary and String((raw_site as Dictionary).get("site_key", "")) == key:
			return String((raw_site as Dictionary).get("site_id", ""))
	return ""


func _site_tile(atlas: Dictionary, key: String) -> String:
	for raw_tile in atlas.get("tiles", []) as Array:
		if raw_tile is Dictionary and String((raw_tile as Dictionary).get("site_key", "")) == key:
			return String((raw_tile as Dictionary).get("id", ""))
	return ""


func _campaign_window(catalog: Dictionary, key: String) -> Dictionary:
	for raw_window in catalog.get("windows", []) as Array:
		if raw_window is Dictionary and String((raw_window as Dictionary).get("window_key", "")) == key:
			return raw_window
	return {}


func _covenant_option(board: Dictionary, action: String) -> Dictionary:
	for raw_option in board.get("options", []) as Array:
		if raw_option is Dictionary and String((raw_option as Dictionary).get("required_action", "")) == action:
			return raw_option
	return {}


func _portfolio_option(board: Dictionary, roles: Array) -> Dictionary:
	var wanted: Array[String] = []
	for role in roles:
		wanted.append(String(role))
	wanted.sort()
	for raw_option in board.get("options", []) as Array:
		if raw_option is Dictionary:
			var actual: Array[String] = []
			for role in (raw_option as Dictionary).get("role_pair", []) as Array:
				actual.append(String(role))
			actual.sort()
			if actual == wanted:
				return raw_option
	return {}


func _external_receipt(label: String) -> String:
	return _receipt_for(["rp9-external-owner-checkpoint", label])


func _receipt_for(value: Variant) -> String:
	var encoded: String = _canonical_json(value)
	if encoded == "":
		return ""
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK \
			or context.update(encoded.to_utf8_buffer()) != OK:
		return ""
	return "sha256:" + context.finish().hex_encode()


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
			var fields: Array[String] = []
			for key in keys:
				var encoded: String = _canonical_json(data[key])
				if encoded == "":
					return ""
				fields.append(JSON.stringify(key) + ":" + encoded)
			return "{" + ",".join(fields) + "}"
	return ""


# Hostile/oracle helpers are appended below so the parser probe can run first.


func _catalog_oracle(catalog: Dictionary) -> bool:
	var questions: Array = catalog.get("questions", [])
	if questions.size() != 3 or not _catalog_receipt_exact(catalog):
		return false
	var previous: String = ""
	var faces := {}
	for raw_question in questions:
		if not (raw_question is Dictionary):
			return false
		var question: Dictionary = raw_question
		var question_id: String = String(question.get("question_id", ""))
		var address: Dictionary = Address.parse_id(String(question.get("region_id", "")))
		if question_id <= previous or Address.level_of(address) != Address.LEVEL_REGION \
				or String(address.get("planet", "")) != "ashfall" \
				or not _receipt_field_exact(question, "question_receipt"):
			return false
		faces[int(address.get("face", -1))] = true
		previous = question_id
	return faces.size() == 3 and faces.has(0) and faces.has(2) and faces.has(5)


func _evidence_anchor_oracle(fixture: Dictionary) -> bool:
	var evidence: Dictionary = fixture["evidence"]
	if String(evidence.get("accepted_atlas_state_receipt", "")) \
			!= String(fixture["atlas_state"].get("state_receipt", "")) \
			or String(evidence.get("accepted_network_state_receipt", "")) \
			!= String(fixture["network_state"].get("state_receipt", "")) \
			or String(evidence.get("accepted_campaign_state_receipt", "")) \
			!= String(fixture["campaign0"].get("state_receipt", "")) \
			or String(evidence.get("accepted_covenant_state_receipt", "")) \
			!= String(fixture["covenant_state"].get("state_receipt", "")) \
			or String(evidence.get("campaign_owner_scope", "")) != CAMPAIGN_SCOPE \
			or String(evidence.get("global_network_scope", "")) != GLOBAL_SCOPE:
		return false
	var stale_network: Dictionary = Model.make_evidence_envelope(
		fixture["catalog"], fixture["atlas"], fixture["atlas_state"],
		String(fixture["atlas_state"].get("state_receipt", "")),
		fixture["network_catalog"], fixture["network_state"],
		_external_receipt("wrong-network-state"), fixture["intel"],
		fixture["campaign_catalog"], fixture["campaign0"],
		String(fixture["campaign0"].get("state_receipt", "")), CAMPAIGN_SCOPE,
		fixture["covenant_catalog"], fixture["covenant_state"],
		String(fixture["covenant_state"].get("state_receipt", "")),
		fixture["obligation"], GLOBAL_SCOPE)
	var mixed_campaign: Dictionary = Model.make_evidence_envelope(
		fixture["catalog"], fixture["atlas"], fixture["atlas_state"],
		String(fixture["atlas_state"].get("state_receipt", "")),
		fixture["network_catalog"], fixture["network_state"],
		String(fixture["network_state"].get("state_receipt", "")), fixture["intel"],
		fixture["campaign_catalog"], fixture["campaign1"],
		String(fixture["campaign1"].get("state_receipt", "")), CAMPAIGN_SCOPE,
		fixture["covenant_catalog"], fixture["covenant_state"],
		String(fixture["covenant_state"].get("state_receipt", "")),
		fixture["obligation"], GLOBAL_SCOPE)
	return stale_network.is_empty() and mixed_campaign.is_empty()


func _prior_oracle(evidence: Dictionary) -> bool:
	var priors: Array = evidence.get("priors", [])
	if priors.size() != 3:
		return false
	var by_face := {}
	for raw_prior in priors:
		if not (raw_prior is Dictionary):
			return false
		var prior: Dictionary = raw_prior
		var address: Dictionary = Address.parse_id(String(prior.get("region_id", "")))
		by_face[int(address.get("face", -1))] = prior
	if not by_face.has(0) or not by_face.has(2) or not by_face.has(5):
		return false
	var basin: Dictionary = by_face[0]
	var meridian: Dictionary = by_face[2]
	var nightward: Dictionary = by_face[5]
	return String(basin.get("grounding_status", "")) == "grounded" \
		and int(basin.get("minimum_bp", -1)) == 3000 \
		and int(basin.get("maximum_bp", -1)) == 7000 \
		and int(basin.get("width_bp", -1)) == 4000 \
		and (basin.get("grounding_evidence_receipts", []) as Array).size() == 1 \
		and String(meridian.get("grounding_status", "")) == "external_only" \
		and int(meridian.get("minimum_bp", -1)) == 2000 \
		and int(meridian.get("maximum_bp", -1)) == 8000 \
		and (meridian.get("grounding_evidence_receipts", []) as Array).is_empty() \
		and String(nightward.get("grounding_status", "")) == "external_only" \
		and int(nightward.get("minimum_bp", -1)) == 2000 \
		and int(nightward.get("maximum_bp", -1)) == 8000 \
		and (nightward.get("grounding_evidence_receipts", []) as Array).is_empty()


func _redglass_parent_oracle(fixture: Dictionary) -> bool:
	var site_id: String = _context_site(fixture["network_catalog"], "redglass_quarry")
	var site: Dictionary = Address.parse_id(site_id)
	var tile: Dictionary = Address.parent(site)
	var region: Dictionary = Address.parent(tile)
	var basin: Dictionary = _campaign_window(fixture["campaign_catalog"], "basin_relief")
	return Address.level_of(site) == Address.LEVEL_SITE \
		and String(site.get("planet", "")) == "ashfall" \
		and int(site.get("face", -1)) == 0 \
		and Address.canonical_id(tile) in fixture["atlas_state"].get("discovered_tile_ids", []) \
		and Address.canonical_id(region) == String(basin.get("region_id", ""))


func _wrong_face_rejected(fixture: Dictionary) -> bool:
	var site: Dictionary = Address.parse_id(
		_context_site(fixture["network_catalog"], "redglass_quarry"))
	var tile: Dictionary = Address.parent(site)
	var coordinate: Vector2i = Address.coordinate(tile, "global_tile")
	var wrong_face: Dictionary = Address.tile_address("ashfall", 2, coordinate)
	var wrong_state: Dictionary = Routes.make_atlas_state(
		fixture["atlas"], [Address.canonical_id(wrong_face)], [])
	var other_atlas: Dictionary = Routes.make_atlas(ROOT_SEED + 1)
	var other_atlas_state: Dictionary = Routes.make_initial_atlas_state(other_atlas)
	var other_network_catalog: Dictionary = Network.make_catalog(other_atlas)
	var other_network_state: Dictionary = Network.make_initial_state(other_network_catalog)
	var other_intel: Dictionary = Network.project_intel(
		other_network_catalog, other_network_state,
		String(other_network_state.get("state_receipt", "")))
	var cross_root: Dictionary = Model.make_evidence_envelope(
		fixture["catalog"], other_atlas, other_atlas_state,
		String(other_atlas_state.get("state_receipt", "")), other_network_catalog,
		other_network_state, String(other_network_state.get("state_receipt", "")),
		other_intel, fixture["campaign_catalog"], fixture["campaign0"],
		String(fixture["campaign0"].get("state_receipt", "")), CAMPAIGN_SCOPE,
		fixture["covenant_catalog"], fixture["covenant_state"],
		String(fixture["covenant_state"].get("state_receipt", "")),
		fixture["obligation"], GLOBAL_SCOPE)
	return wrong_state.is_empty() and cross_root.is_empty()


func _role_oracle(evidence: Dictionary) -> bool:
	var assignments: Array = evidence.get("role_assignments", [])
	if assignments.size() != 3:
		return false
	var by_role := {}
	for raw_assignment in assignments:
		if not (raw_assignment is Dictionary):
			return false
		var assignment: Dictionary = raw_assignment
		by_role[String(assignment.get("role", ""))] = assignment
	if by_role.size() != 3:
		return false
	var duty_face: int = int(Address.parse_id(String(by_role["duty"].get(
		"region_id", ""))).get("face", -1))
	var spillover_face: int = int(Address.parse_id(String(by_role["spillover"].get(
		"region_id", ""))).get("face", -1))
	var fallback_face: int = int(Address.parse_id(String(by_role["fallback"].get(
		"region_id", ""))).get("face", -1))
	return duty_face == 2 and spillover_face == 5 and fallback_face == 0


func _board_oracle(state: Dictionary, board: Dictionary) -> bool:
	var options: Array = board.get("options", [])
	if String(board.get("decision_status", "")) != "portfolios_available" \
			or options.size() != 3:
		return false
	var belief_widths := {}
	for raw_belief in state.get("beliefs", []) as Array:
		if raw_belief is Dictionary:
			belief_widths[String((raw_belief as Dictionary).get("role", ""))] = int(
				(raw_belief as Dictionary).get("width_bp", -1))
	var seen_pairs := {}
	var previous: String = ""
	var vectors: Array[Dictionary] = []
	for raw_option in options:
		if not (raw_option is Dictionary):
			return false
		var option: Dictionary = raw_option
		var option_id: String = String(option.get("portfolio_id", ""))
		var roles: Array = option.get("role_pair", [])
		if option_id <= previous or roles.size() != 2 \
				or int(option.get("point_cost", -1)) != 2:
			return false
		var key: String = "%s+%s" % [String(roles[0]), String(roles[1])]
		seen_pairs[key] = true
		var vector := {}
		for raw_row in option.get("reduction_vector", []) as Array:
			if not (raw_row is Dictionary):
				return false
			var row: Dictionary = raw_row
			var role: String = String(row.get("role", ""))
			var expected: int = int(belief_widths.get(role, -1)) - 2000 \
				if role in roles else 0
			if int(row.get("reduction_bp", -1)) != expected:
				return false
			vector[role] = expected
		vectors.append(vector)
		previous = option_id
	if seen_pairs.size() != 3 or not seen_pairs.has("duty+spillover") \
			or not seen_pairs.has("duty+fallback") \
			or not seen_pairs.has("spillover+fallback"):
		return false
	for left in vectors:
		for right in vectors:
			if left == right:
				continue
			var dominates: bool = true
			var strict: bool = false
			for role in ["duty", "spillover", "fallback"]:
				if int((left as Dictionary)[role]) < int((right as Dictionary)[role]):
					dominates = false
				if int((left as Dictionary)[role]) > int((right as Dictionary)[role]):
					strict = true
			if dominates and strict:
				return false
	return true


func _choice_oracle(board: Dictionary, choice: Dictionary, expected_roles: Array) -> bool:
	var selected: Array[String] = []
	for role in choice.get("selected_roles", []) as Array:
		selected.append(String(role))
	var expected: Array[String] = []
	for role in expected_roles:
		expected.append(String(role))
	selected.sort()
	expected.sort()
	var option: Dictionary = _portfolio_option(board, expected)
	return selected == expected and String(choice.get("portfolio_id", "")) \
		== String(option.get("portfolio_id", "")) \
		and String(choice.get("option_receipt", "")) \
		== String(option.get("option_receipt", ""))


func _anchor_oracle(evidence: Dictionary, anchor: Dictionary) -> bool:
	return String(anchor.get("owner_scope", "")) == RECON_SCOPE \
		and String(anchor.get("cycle_key", "")) == String(evidence.get("evidence_receipt", "")) \
		and int(anchor.get("points_before", -1)) == 2 \
		and String(anchor.get("commitment_replay_key", "")) == _receipt_for([
			RECON_SCOPE, String(anchor.get("owner_checkpoint_receipt", ""))]) \
		and _receipt_field_exact(anchor, "anchor_receipt")


func _capacity_one_oracle(fixture: Dictionary) -> bool:
	var checkpoint: String = _external_receipt("one-point-owner")
	var anchor: Dictionary = Model.make_recon_anchor(
		RECON_SCOPE, checkpoint, String(fixture["evidence"].get("evidence_receipt", "")), 1)
	var board: Dictionary = Model.make_portfolio_board(
		fixture["campaign_catalog"], fixture["covenant_catalog"], fixture["catalog"],
		fixture["state0"], String(fixture["state0"].get("state_receipt", "")),
		fixture["evidence"], String(fixture["evidence"].get("evidence_receipt", "")),
		anchor, RECON_SCOPE, checkpoint, String(anchor.get("anchor_receipt", "")))
	return String(board.get("decision_status", "")) == "insufficient_recon_capacity" \
		and (board.get("options", []) as Array).is_empty()


func _anchor_alias_hostiles(fixture: Dictionary) -> bool:
	var checkpoint: String = String(fixture["recon_checkpoint"])
	var rebound: Dictionary = Model.make_recon_anchor(
		"ashfall_recon_alt", checkpoint,
		String(fixture["evidence"].get("evidence_receipt", "")), 2)
	var inflated: Dictionary = Model.make_recon_anchor(
		RECON_SCOPE, checkpoint, String(fixture["evidence"].get("evidence_receipt", "")), 8)
	var alias_campaign: Dictionary = Model.make_portfolio_board(
		fixture["campaign_catalog"], fixture["covenant_catalog"], fixture["catalog"],
		fixture["state0"], String(fixture["state0"].get("state_receipt", "")),
		fixture["evidence"], String(fixture["evidence"].get("evidence_receipt", "")),
		fixture["anchor"], CAMPAIGN_SCOPE, checkpoint,
		String(fixture["anchor"].get("anchor_receipt", "")))
	var alias_global: Dictionary = Model.make_portfolio_board(
		fixture["campaign_catalog"], fixture["covenant_catalog"], fixture["catalog"],
		fixture["state0"], String(fixture["state0"].get("state_receipt", "")),
		fixture["evidence"], String(fixture["evidence"].get("evidence_receipt", "")),
		fixture["anchor"], GLOBAL_SCOPE, checkpoint,
		String(fixture["anchor"].get("anchor_receipt", "")))
	var inflated_board: Dictionary = Model.make_portfolio_board(
		fixture["campaign_catalog"], fixture["covenant_catalog"], fixture["catalog"],
		fixture["state0"], String(fixture["state0"].get("state_receipt", "")),
		fixture["evidence"], String(fixture["evidence"].get("evidence_receipt", "")),
		inflated, RECON_SCOPE, checkpoint,
		String(fixture["anchor"].get("anchor_receipt", "")))
	return not rebound.is_empty() \
		and not Model.validate_recon_anchor(rebound, RECON_SCOPE, checkpoint,
			String(rebound.get("anchor_receipt", ""))).is_empty() \
		and not inflated.is_empty() and inflated_board.is_empty() \
		and alias_campaign.is_empty() and alias_global.is_empty()


func _board_choice_mix_hostiles(fixture: Dictionary) -> bool:
	var fresh_checkpoint: String = _external_receipt("sibling-recon-owner")
	var sibling_anchor: Dictionary = Model.make_recon_anchor(
		RECON_SCOPE, fresh_checkpoint, String(fixture["evidence"].get(
			"evidence_receipt", "")), 2)
	var sibling_board: Dictionary = Model.make_portfolio_board(
		fixture["campaign_catalog"], fixture["covenant_catalog"], fixture["catalog"],
		fixture["state0"], String(fixture["state0"].get("state_receipt", "")),
		fixture["evidence"], String(fixture["evidence"].get("evidence_receipt", "")),
		sibling_anchor, RECON_SCOPE, fresh_checkpoint,
		String(sibling_anchor.get("anchor_receipt", "")))
	var sibling_option: Dictionary = _portfolio_option(
		sibling_board, ["duty", "spillover"])
	var sibling_choice: Dictionary = Model.make_portfolio_choice(
		fixture["catalog"], sibling_board,
		String(sibling_option.get("portfolio_id", "")))
	var mixed_commit: Dictionary = Model.commit_portfolio(
		fixture["campaign_catalog"], fixture["covenant_catalog"], fixture["catalog"],
		fixture["state0"], String(fixture["state0"].get("state_receipt", "")),
		fixture["evidence"], String(fixture["evidence"].get("evidence_receipt", "")),
		fixture["anchor"], RECON_SCOPE, String(fixture["recon_checkpoint"]),
		String(fixture["anchor"].get("anchor_receipt", "")), fixture["board"],
		sibling_choice)
	var stale_board: Dictionary = Model.make_portfolio_board(
		fixture["campaign_catalog"], fixture["covenant_catalog"], fixture["catalog"],
		fixture["state0"], String(fixture["state0"].get("state_receipt", "")),
		fixture["evidence"], _external_receipt("stale-evidence"), fixture["anchor"],
		RECON_SCOPE, String(fixture["recon_checkpoint"]),
		String(fixture["anchor"].get("anchor_receipt", "")))
	return not sibling_board.is_empty() and not sibling_choice.is_empty() \
		and mixed_commit.is_empty() and stale_board.is_empty() \
		and not Model.validate_portfolio_choice(
			fixture["catalog"], fixture["board"], sibling_choice).is_empty()


func _board_shape_hostiles(fixture: Dictionary) -> bool:
	var unknown: Dictionary = fixture["board"].duplicate(true)
	unknown["caller_score"] = 999
	_rehash_id_receipt(unknown, "board_id", Model.BOARD_ID_PREFIX, "board_receipt")
	var unknown_choice: Dictionary = Model.make_portfolio_choice(
		fixture["catalog"], unknown,
		String(fixture["choice"].get("portfolio_id", "")))
	var sparse: Dictionary = fixture["board"].duplicate(true)
	sparse.erase("options")
	var sparse_choice: Dictionary = Model.make_portfolio_choice(
		fixture["catalog"], sparse,
		String(fixture["choice"].get("portfolio_id", "")))
	var cyclic: Dictionary = {}
	cyclic["self"] = cyclic
	var cyclic_choice: Dictionary = Model.make_portfolio_choice(
		fixture["catalog"], cyclic, String(fixture["choice"].get("portfolio_id", "")))
	return unknown_choice.is_empty() and sparse_choice.is_empty() \
		and cyclic_choice.is_empty()


func _commit_oracle(fixture: Dictionary, commit: Dictionary) -> bool:
	var errors: Array[String] = Model.validate_commit_proposal(
		fixture["campaign_catalog"], fixture["covenant_catalog"], fixture["catalog"],
		fixture["state0"], String(fixture["state0"].get("state_receipt", "")),
		fixture["evidence"], String(fixture["evidence"].get("evidence_receipt", "")),
		fixture["anchor"], RECON_SCOPE, String(fixture["recon_checkpoint"]),
		String(fixture["anchor"].get("anchor_receipt", "")), fixture["board"],
		fixture["choice"], commit)
	var capacity: Dictionary = commit.get("recon_capacity_delta", {})
	var belief: Dictionary = commit.get("belief_delta", {})
	return errors.is_empty() and commit.get("owner_order", []) \
		== ["belief", "recon_capacity"] \
		and int(capacity.get("points_before", -1)) == 2 \
		and int(capacity.get("points_requested", 0)) == -2 \
		and int(capacity.get("points_applied", 0)) == -2 \
		and int(capacity.get("points_after", -1)) == 0 \
		and int(belief.get("before_revision", -1)) == 0 \
		and int(belief.get("after_revision", -1)) == 1 \
		and _receipt_field_exact(commit, "proposal_receipt")


func _committed_oracle(catalog: Dictionary, committed: Dictionary,
		board: Dictionary, choice: Dictionary, anchor: Dictionary) -> bool:
	var record: Dictionary = committed.get("commitment_record", {})
	var option: Dictionary = _portfolio_option(board, ["duty", "fallback"])
	return Model.validate_state(catalog, committed).is_empty() \
		and String(committed.get("phase", "")) == "committed" \
		and int(committed.get("revision", -1)) == 1 \
		and record.get("selected_roles", []) == ["duty", "fallback"] \
		and String(record.get("portfolio_id", "")) == String(option.get("portfolio_id", "")) \
		and String(record.get("option_receipt", "")) == String(option.get("option_receipt", "")) \
		and String(record.get("choice_id", "")) == String(choice.get("choice_id", "")) \
		and String(record.get("recon_anchor_id", "")) == String(anchor.get("anchor_id", "")) \
		and record.get("recon_replay_key") in committed.get("consumed_recon_keys", []) \
		and (record.get("selected_probes", []) as Array).size() == 2


func _commit_record_hostiles(fixture: Dictionary) -> bool:
	var committed: Dictionary = fixture["committed"]
	var probe_swap: Dictionary = committed.duplicate(true)
	var probe_record: Dictionary = probe_swap["commitment_record"]
	var probes: Array = probe_record["selected_probes"]
	var first_probe: Dictionary = probes[0]
	first_probe["role"] = "spillover"
	_rehash_id_receipt(first_probe, "probe_id", Model.PROBE_ID_PREFIX, "probe_receipt")
	_rehash_id_receipt(probe_record, "record_id", Model.COMMIT_RECORD_ID_PREFIX,
		"record_receipt")
	probe_swap["last_action_receipt"] = probe_record["record_receipt"]
	_rehash_state(probe_swap)
	var forged_anchor: Dictionary = committed.duplicate(true)
	var anchor_record: Dictionary = forged_anchor["commitment_record"]
	anchor_record["points_before"] = 8
	anchor_record["points_after"] = 6
	var rebuilt_anchor: Dictionary = Model.make_recon_anchor(
		String(anchor_record["recon_owner_scope"]),
		String(anchor_record["recon_owner_checkpoint_receipt"]),
		String(anchor_record["evidence_snapshot_receipt"]), 8)
	anchor_record["recon_anchor_id"] = rebuilt_anchor.get("anchor_id", "")
	anchor_record["recon_anchor_receipt"] = rebuilt_anchor.get("anchor_receipt", "")
	_rehash_id_receipt(anchor_record, "record_id", Model.COMMIT_RECORD_ID_PREFIX,
		"record_receipt")
	forged_anchor["last_action_receipt"] = anchor_record["record_receipt"]
	_rehash_state(forged_anchor)
	var arbitrary_replay: Dictionary = committed.duplicate(true)
	var replay_record: Dictionary = arbitrary_replay["commitment_record"]
	replay_record["recon_replay_key"] = _external_receipt("arbitrary-replay")
	arbitrary_replay["consumed_recon_keys"] = [replay_record["recon_replay_key"]]
	_rehash_id_receipt(replay_record, "record_id", Model.COMMIT_RECORD_ID_PREFIX,
		"record_receipt")
	arbitrary_replay["last_action_receipt"] = replay_record["record_receipt"]
	_rehash_state(arbitrary_replay)
	var fake_option: Dictionary = committed.duplicate(true)
	var option_record: Dictionary = fake_option["commitment_record"]
	option_record["portfolio_id"] = "prf1:0000000000000000"
	option_record["option_receipt"] = _external_receipt("fake-option")
	option_record["choice_id"] = "prk1:0000000000000000"
	option_record["choice_receipt"] = _external_receipt("fake-choice")
	_rehash_id_receipt(option_record, "record_id", Model.COMMIT_RECORD_ID_PREFIX,
		"record_receipt")
	fake_option["last_action_receipt"] = option_record["record_receipt"]
	_rehash_state(fake_option)
	return not Model.validate_state(fixture["catalog"], probe_swap).is_empty() \
		and not Model.validate_state(fixture["catalog"], forged_anchor).is_empty() \
		and not Model.validate_state(fixture["catalog"], arbitrary_replay).is_empty() \
		and not Model.validate_state(fixture["catalog"], fake_option).is_empty()


func _bundle_oracle(committed: Dictionary, bundle: Dictionary,
		report_checkpoint: String) -> bool:
	var selected := {}
	for raw_probe in committed.get("commitment_record", {}).get(
			"selected_probes", []) as Array:
		if raw_probe is Dictionary:
			selected[String((raw_probe as Dictionary).get("probe_id", ""))] = true
	var observed := {}
	var sources := {}
	for raw_observation in bundle.get("observations", []) as Array:
		if not (raw_observation is Dictionary):
			return false
		var observation: Dictionary = raw_observation
		if not selected.has(String(observation.get("probe_id", ""))) \
				or sources.has(String(observation.get("source_receipt", ""))) \
				or not _receipt_field_exact(observation, "observation_receipt"):
			return false
		observed[String(observation.get("probe_id", ""))] = true
		sources[String(observation.get("source_receipt", ""))] = true
	return observed.size() == 2 and sources.size() == 2 \
		and String(bundle.get("observation_owner_scope", "")) == RECON_SCOPE \
		and String(bundle.get("observation_owner_checkpoint_receipt", "")) \
		== report_checkpoint \
		and report_checkpoint != String(committed.get("commitment_record", {}).get(
			"recon_owner_checkpoint_receipt", "")) \
		and _receipt_field_exact(bundle, "bundle_receipt")


func _validate_bundle(fixture: Dictionary, value: Variant,
		expected_receipt: String = "") -> Array[String]:
	var receipt: String = expected_receipt if expected_receipt != "" \
		else String(fixture["bundle"].get("bundle_receipt", ""))
	return Model.validate_observation_bundle(
		fixture["catalog"], fixture["committed"],
		String(fixture["committed"].get("state_receipt", "")), RECON_SCOPE,
		String(fixture["report_checkpoint"]), receipt, value)


func _bundle_hostiles(fixture: Dictionary) -> bool:
	var sparse: Array[Dictionary] = fixture["sparse_reports"].duplicate(true)
	var duplicate_probe: Array[Dictionary] = sparse.duplicate(true)
	duplicate_probe[1]["probe_id"] = duplicate_probe[0]["probe_id"]
	var duplicate_source: Array[Dictionary] = sparse.duplicate(true)
	duplicate_source[1]["source_receipt"] = duplicate_source[0]["source_receipt"]
	var unselected_probe: Dictionary = {}
	for raw_option in fixture["board"].get("options", []) as Array:
		if raw_option is Dictionary:
			for raw_probe in (raw_option as Dictionary).get("probes", []) as Array:
				if raw_probe is Dictionary and String((raw_probe as Dictionary).get(
						"role", "")) == "spillover":
					unselected_probe = raw_probe
	var unselected: Array[Dictionary] = sparse.duplicate(true)
	unselected[0]["probe_id"] = String(unselected_probe.get("probe_id", ""))
	var stale_checkpoint: Dictionary = Model.make_observation_bundle(
		fixture["catalog"], fixture["committed"],
		String(fixture["committed"].get("state_receipt", "")), RECON_SCOPE,
		String(fixture["recon_checkpoint"]), sparse)
	return Model.make_observation_bundle(
		fixture["catalog"], fixture["committed"],
		String(fixture["committed"].get("state_receipt", "")), RECON_SCOPE,
		String(fixture["report_checkpoint"]), duplicate_probe).is_empty() \
		and Model.make_observation_bundle(
			fixture["catalog"], fixture["committed"],
			String(fixture["committed"].get("state_receipt", "")), RECON_SCOPE,
			String(fixture["report_checkpoint"]), duplicate_source).is_empty() \
		and Model.make_observation_bundle(
			fixture["catalog"], fixture["committed"],
			String(fixture["committed"].get("state_receipt", "")), RECON_SCOPE,
			String(fixture["report_checkpoint"]), unselected).is_empty() \
		and stale_checkpoint.is_empty()


func _resolution_oracle(fixture: Dictionary, resolution: Dictionary) -> bool:
	var errors: Array[String] = Model.validate_resolution_proposal(
		fixture["campaign_catalog"], fixture["covenant_catalog"], fixture["catalog"],
		fixture["committed"], String(fixture["committed"].get("state_receipt", "")),
		fixture["campaign0"], String(fixture["campaign0"].get("state_receipt", "")),
		CAMPAIGN_SCOPE, fixture["covenant_state"],
		String(fixture["covenant_state"].get("state_receipt", "")), GLOBAL_SCOPE,
		fixture["bundle"], RECON_SCOPE, String(fixture["report_checkpoint"]),
		String(fixture["bundle"].get("bundle_receipt", "")), resolution)
	var after: Dictionary = resolution.get("after_state", {})
	return errors.is_empty() and resolution.get("owner_order", []) == ["belief"] \
		and String(after.get("phase", "")) == "terminal" \
		and String(after.get("outcome", "")) == "resolved" \
		and int(after.get("revision", -1)) == 2 \
		and _receipt_field_exact(resolution, "proposal_receipt")


func _posterior_oracle(resolved: Dictionary) -> bool:
	var by_role := {}
	for raw_belief in resolved.get("beliefs", []) as Array:
		if raw_belief is Dictionary:
			by_role[String((raw_belief as Dictionary).get("role", ""))] = raw_belief
	if by_role.size() != 3:
		return false
	var duty: Dictionary = by_role["duty"]
	var spillover: Dictionary = by_role["spillover"]
	var fallback: Dictionary = by_role["fallback"]
	return _belief_exact(duty, "observed", "favorable", 7000, 9000, 2000) \
		and _belief_exact(fallback, "observed", "mixed", 4000, 6000, 2000) \
		and _belief_exact(spillover, "unobserved", "", 2000, 8000, 6000)


func _belief_exact(belief: Dictionary, status: String, observed_signal: String,
		minimum: int, maximum: int, width: int) -> bool:
	return String(belief.get("status", "")) == status \
		and String(belief.get("observed_signal", "")) == observed_signal \
		and int(belief.get("minimum_bp", -1)) == minimum \
		and int(belief.get("maximum_bp", -1)) == maximum \
		and int(belief.get("width_bp", -1)) == width


func _resolved_state_hostiles(fixture: Dictionary) -> bool:
	var changed_band: Dictionary = fixture["resolved"].duplicate(true)
	var beliefs: Array = changed_band["beliefs"]
	for raw_belief in beliefs:
		if raw_belief is Dictionary and String((raw_belief as Dictionary).get(
				"role", "")) == "duty":
			(raw_belief as Dictionary)["minimum_bp"] = 6000
			(raw_belief as Dictionary)["maximum_bp"] = 8000
	var resolution_record: Dictionary = changed_band["observation_bundle_record"]
	resolution_record["after_beliefs_receipt"] = _receipt_for(beliefs)
	_rehash_id_receipt(resolution_record, "record_id",
		Model.RESOLUTION_RECORD_ID_PREFIX, "record_receipt")
	changed_band["last_action_receipt"] = resolution_record["record_receipt"]
	_rehash_state(changed_band)
	var forged_unselected: Dictionary = fixture["resolved"].duplicate(true)
	var forged_beliefs: Array = forged_unselected["beliefs"]
	for raw_belief in forged_beliefs:
		if raw_belief is Dictionary and String((raw_belief as Dictionary).get(
				"role", "")) == "spillover":
			var belief: Dictionary = raw_belief
			belief["status"] = "observed"
			belief["minimum_bp"] = 4000
			belief["maximum_bp"] = 6000
			belief["width_bp"] = 2000
			belief["observed_signal"] = "mixed"
			belief["observation_receipt"] = _external_receipt("forged-unselected")
	var forged_record: Dictionary = forged_unselected["observation_bundle_record"]
	forged_record["after_beliefs_receipt"] = _receipt_for(forged_beliefs)
	var observation_receipts: Array = forged_record["observation_receipts"]
	observation_receipts.append(_external_receipt("forged-unselected"))
	observation_receipts.sort()
	_rehash_id_receipt(forged_record, "record_id",
		Model.RESOLUTION_RECORD_ID_PREFIX, "record_receipt")
	forged_unselected["last_action_receipt"] = forged_record["record_receipt"]
	_rehash_state(forged_unselected)
	return not Model.validate_state(fixture["catalog"], changed_band).is_empty() \
		and not Model.validate_state(fixture["catalog"], forged_unselected).is_empty()


func _unchanged_stale_rejected(fixture: Dictionary) -> bool:
	return Model.close_stale(
		fixture["campaign_catalog"], fixture["covenant_catalog"], fixture["catalog"],
		fixture["committed"], String(fixture["committed"].get("state_receipt", "")),
		fixture["campaign0"], String(fixture["campaign0"].get("state_receipt", "")),
		CAMPAIGN_SCOPE, fixture["covenant_state"],
		String(fixture["covenant_state"].get("state_receipt", "")),
		GLOBAL_SCOPE).is_empty()


func _stale_oracle(fixture: Dictionary, stale: Dictionary,
		stale_state: Dictionary) -> bool:
	var errors: Array[String] = Model.validate_stale_proposal(
		fixture["campaign_catalog"], fixture["covenant_catalog"], fixture["catalog"],
		fixture["committed"], String(fixture["committed"].get("state_receipt", "")),
		fixture["campaign1"], String(fixture["campaign1"].get("state_receipt", "")),
		CAMPAIGN_SCOPE, fixture["covenant_state"],
		String(fixture["covenant_state"].get("state_receipt", "")), GLOBAL_SCOPE,
		stale)
	return errors.is_empty() and stale.get("owner_order", []) == ["belief"] \
		and int(stale.get("recon_points_refunded", -1)) == 0 \
		and String(stale_state.get("phase", "")) == "terminal" \
		and String(stale_state.get("outcome", "")) == "stale" \
		and stale_state.get("beliefs", []) == fixture["committed"].get("beliefs", []) \
		and String(stale_state.get("stale_record", {}).get("stale_reason", "")) \
		== "campaign_changed" \
		and Model.validate_state(fixture["catalog"], stale_state).is_empty()


func _stale_resolution_cas_oracle(fixture: Dictionary) -> bool:
	var changed_resolution: Dictionary = Model.resolve_portfolio(
		fixture["campaign_catalog"], fixture["covenant_catalog"], fixture["catalog"],
		fixture["committed"], String(fixture["committed"].get("state_receipt", "")),
		fixture["campaign1"], String(fixture["campaign1"].get("state_receipt", "")),
		CAMPAIGN_SCOPE, fixture["covenant_state"],
		String(fixture["covenant_state"].get("state_receipt", "")), GLOBAL_SCOPE,
		fixture["bundle"], RECON_SCOPE, String(fixture["report_checkpoint"]),
		String(fixture["bundle"].get("bundle_receipt", "")))
	var replay_stale: Dictionary = Model.close_stale(
		fixture["campaign_catalog"], fixture["covenant_catalog"], fixture["catalog"],
		fixture["stale_state"], String(fixture["stale_state"].get("state_receipt", "")),
		fixture["campaign1"], String(fixture["campaign1"].get("state_receipt", "")),
		CAMPAIGN_SCOPE, fixture["covenant_state"],
		String(fixture["covenant_state"].get("state_receipt", "")), GLOBAL_SCOPE)
	return changed_resolution.is_empty() and replay_stale.is_empty()


func _json_continuation_oracle(fixture: Dictionary) -> bool:
	var parsed_catalog_value: Variant = JSON.parse_string(JSON.stringify(fixture["catalog"]))
	var parsed_state_value: Variant = JSON.parse_string(JSON.stringify(fixture["stale_state"]))
	var parsed_board_value: Variant = JSON.parse_string(JSON.stringify(fixture["board"]))
	if not (parsed_catalog_value is Dictionary) or not (parsed_state_value is Dictionary) \
			or not (parsed_board_value is Dictionary):
		return false
	var parsed_catalog: Dictionary = parsed_catalog_value
	for raw_question in parsed_catalog.get("questions", []) as Array:
		if raw_question is Dictionary:
			var question: Dictionary = raw_question
			for key in ["broad_prior_min_bp", "broad_prior_max_bp",
					"grounded_prior_min_bp", "grounded_prior_max_bp"]:
				question[key] = float(question[key])
	var normalized_catalog: Dictionary = Model.normalize_catalog(
		fixture["campaign_catalog"], fixture["covenant_catalog"], parsed_catalog)
	var parsed_state: Dictionary = parsed_state_value
	parsed_state["revision"] = float(parsed_state["revision"])
	parsed_state["effective_due_epoch"] = float(parsed_state["effective_due_epoch"])
	for raw_belief in parsed_state.get("beliefs", []) as Array:
		if raw_belief is Dictionary:
			var belief: Dictionary = raw_belief
			for key in ["minimum_bp", "maximum_bp", "width_bp"]:
				belief[key] = float(belief[key])
	var commit_record: Dictionary = parsed_state.get("commitment_record", {})
	for key in ["effective_due_epoch", "point_cost", "points_before",
			"points_applied", "points_after"]:
		commit_record[key] = float(commit_record[key])
	for raw_probe in commit_record.get("selected_probes", []) as Array:
		if raw_probe is Dictionary:
			var probe: Dictionary = raw_probe
			for key in ["prior_width_bp", "posterior_width_bp", "reduction_bp"]:
				probe[key] = float(probe[key])
	var stale_record: Dictionary = parsed_state.get("stale_record", {})
	stale_record["recon_points_refunded"] = 0.0
	var normalized_state: Dictionary = Model.normalize_state(fixture["catalog"], parsed_state)
	var parsed_board: Dictionary = parsed_board_value
	parsed_board["revision"] = float(parsed_board["revision"])
	parsed_board["points_available"] = float(parsed_board["points_available"])
	for raw_option in parsed_board.get("options", []) as Array:
		if raw_option is Dictionary:
			var option: Dictionary = raw_option
			option["point_cost"] = float(option["point_cost"])
			for raw_probe in option.get("probes", []) as Array:
				if raw_probe is Dictionary:
					var probe: Dictionary = raw_probe
					for key in ["prior_width_bp", "posterior_width_bp", "reduction_bp"]:
						probe[key] = float(probe[key])
			for raw_reduction in option.get("reduction_vector", []) as Array:
				if raw_reduction is Dictionary:
					(raw_reduction as Dictionary)["reduction_bp"] = float(
						(raw_reduction as Dictionary)["reduction_bp"])
	var normalized_board: Dictionary = Model.normalize_portfolio_board(
		fixture["campaign_catalog"], fixture["covenant_catalog"], fixture["catalog"],
		fixture["state0"], String(fixture["state0"].get("state_receipt", "")),
		fixture["evidence"], String(fixture["evidence"].get("evidence_receipt", "")),
		fixture["anchor"], RECON_SCOPE, String(fixture["recon_checkpoint"]),
		String(fixture["anchor"].get("anchor_receipt", "")), parsed_board)
	if normalized_catalog.is_empty() or normalized_state.is_empty() \
			or normalized_board.is_empty():
		return false
	var normalized_stale: Dictionary = normalized_state.get("stale_record", {})
	var projection: Dictionary = Model.project_beliefs(
		fixture["catalog"], parsed_state,
		String(fixture["stale_state"].get("state_receipt", "")))
	return typeof(normalized_state.get("revision")) == TYPE_INT \
		and typeof(normalized_state.get("effective_due_epoch")) == TYPE_INT \
		and typeof(normalized_stale.get("recon_points_refunded")) == TYPE_INT \
		and typeof((normalized_state.get("beliefs", []) as Array)[0].get(
			"minimum_bp")) == TYPE_INT \
		and typeof(normalized_board.get("points_available")) == TYPE_INT \
		and _canonical_json(normalized_catalog) == _canonical_json(fixture["catalog"]) \
		and _canonical_json(normalized_state) == _canonical_json(fixture["stale_state"]) \
		and _canonical_json(normalized_board) == _canonical_json(fixture["board"]) \
		and not projection.is_empty()


func _numeric_hostiles(fixture: Dictionary) -> bool:
	var invalid_values: Array = [2.5, NAN, INF, 1e100, "2", true, -1, 9]
	for invalid in invalid_values:
		var anchor: Dictionary = fixture["anchor"].duplicate(true)
		anchor["points_before"] = invalid
		_rehash_id_receipt(anchor, "anchor_id", Model.ANCHOR_ID_PREFIX,
			"anchor_receipt")
		if Model.validate_recon_anchor(
			anchor, RECON_SCOPE, String(fixture["recon_checkpoint"]),
			String(anchor.get("anchor_receipt", ""))).is_empty():
			return false
	var unknown: Dictionary = fixture["state0"].duplicate(true)
	unknown["owner_score"] = 1
	_rehash_state(unknown)
	var fractional: Dictionary = fixture["state0"].duplicate(true)
	fractional["effective_due_epoch"] = 1.5
	_rehash_state(fractional)
	return not Model.validate_state(fixture["catalog"], unknown).is_empty() \
		and not Model.validate_state(fixture["catalog"], fractional).is_empty()


func _canonical_budget_hostiles(fixture: Dictionary) -> bool:
	var deep: Variant = "leaf"
	for _index in 34:
		deep = {"next": deep}
	var oversized: Array = []
	for index in 257:
		oversized.append(index)
	var long_string: String = "x".repeat(1025)
	var cyclic: Dictionary = {}
	cyclic["self"] = cyclic
	var cyclic_board: Dictionary = Model.make_portfolio_choice(
		fixture["catalog"], cyclic, String(fixture["choice"].get("portfolio_id", "")))
	return String(Model._canonical_json(deep)) == "" \
		and String(Model._canonical_json(oversized)) == "" \
		and String(Model._canonical_json(long_string)) == "" \
		and String(Model._canonical_json(cyclic)) == "" \
		and cyclic_board.is_empty()


func _projection_independence(fixture: Dictionary) -> bool:
	var before_bytes: String = _canonical_json({
		"atlas": fixture["atlas"], "atlas_state": fixture["atlas_state"],
		"network": fixture["network_state"], "campaign": fixture["campaign0"],
		"covenant": fixture["covenant_state"], "state": fixture["resolved"],
	})
	var open_projection: Dictionary = Model.project_beliefs(
		fixture["catalog"], fixture["state0"],
		String(fixture["state0"].get("state_receipt", "")))
	var committed_projection: Dictionary = Model.project_beliefs(
		fixture["catalog"], fixture["committed"],
		String(fixture["committed"].get("state_receipt", "")))
	var resolved_projection: Dictionary = Model.project_beliefs(
		fixture["catalog"], fixture["resolved"],
		String(fixture["resolved"].get("state_receipt", "")))
	var resolved_again: Dictionary = Model.project_beliefs(
		fixture["catalog"], fixture["resolved"],
		String(fixture["resolved"].get("state_receipt", "")))
	var after_bytes: String = _canonical_json({
		"atlas": fixture["atlas"], "atlas_state": fixture["atlas_state"],
		"network": fixture["network_state"], "campaign": fixture["campaign0"],
		"covenant": fixture["covenant_state"], "state": fixture["resolved"],
	})
	return not open_projection.is_empty() and not committed_projection.is_empty() \
		and not resolved_projection.is_empty() \
		and _canonical_json(resolved_projection) == _canonical_json(resolved_again) \
		and bool(resolved_projection.get("observation_pure", false)) \
		and String(resolved_projection.get("semantics", "")) \
		== "epistemic_support_band_not_truth_or_probability" \
		and Model.validate_belief_projection(
			fixture["catalog"], fixture["resolved"],
			String(fixture["resolved"].get("state_receipt", "")),
			resolved_projection).is_empty() \
		and before_bytes == after_bytes


func _input_immutability_oracle(fixture: Dictionary) -> bool:
	var input_bytes: String = _canonical_json({
		"catalog": fixture["catalog"], "evidence": fixture["evidence"],
		"state0": fixture["state0"], "anchor": fixture["anchor"],
		"board": fixture["board"], "choice": fixture["choice"],
		"campaign": fixture["campaign0"], "covenant": fixture["covenant_state"],
	})
	var mutated: Dictionary = fixture["resolution"].duplicate(true)
	var after: Dictionary = mutated.get("after_state", {})
	after["phase"] = "forged"
	var rebuilt_commit: Dictionary = _commit(
		fixture, fixture["state0"], fixture["evidence"], fixture["anchor"],
		fixture["board"], fixture["choice"])
	var after_bytes: String = _canonical_json({
		"catalog": fixture["catalog"], "evidence": fixture["evidence"],
		"state0": fixture["state0"], "anchor": fixture["anchor"],
		"board": fixture["board"], "choice": fixture["choice"],
		"campaign": fixture["campaign0"], "covenant": fixture["covenant_state"],
	})
	return input_bytes == after_bytes \
		and _canonical_json(rebuilt_commit) == _canonical_json(fixture["commit"])


func _receipt_suite_oracle(fixture: Dictionary) -> bool:
	if not _catalog_receipt_exact(fixture["catalog"]):
		return false
	for pair in [["evidence", "evidence_receipt"],
			["state0", "state_receipt"], ["anchor", "anchor_receipt"],
			["board", "board_receipt"], ["choice", "choice_receipt"],
			["commit", "proposal_receipt"], ["committed", "state_receipt"],
			["bundle", "bundle_receipt"], ["resolution", "proposal_receipt"],
			["resolved", "state_receipt"], ["stale", "proposal_receipt"],
			["stale_state", "state_receipt"]]:
		var key: String = String(pair[0])
		var receipt_key: String = String(pair[1])
		if not fixture.has(key) or not (fixture[key] is Dictionary) \
				or not _receipt_field_exact(fixture[key], receipt_key):
			return false
	return true


func _catalog_receipt_exact(catalog: Dictionary) -> bool:
	var base: Dictionary = catalog.duplicate(true)
	base.erase("catalog_id")
	base.erase("catalog_receipt")
	var receipt: String = _receipt_for(base)
	return receipt != "" and String(catalog.get("catalog_receipt", "")) == receipt \
		and String(catalog.get("catalog_id", "")) \
		== Model.CATALOG_ID_PREFIX + receipt.trim_prefix("sha256:").substr(0, 16)


func _receipt_field_exact(data: Dictionary, receipt_key: String) -> bool:
	var base: Dictionary = data.duplicate(true)
	base.erase(receipt_key)
	return String(data.get(receipt_key, "")) == _receipt_for(base)


func _rehash_state(state: Dictionary) -> void:
	state.erase("state_receipt")
	state["state_receipt"] = _receipt_for(state)


func _rehash_id_receipt(value: Dictionary, id_field: String, prefix: String,
		receipt_field: String) -> void:
	value.erase(id_field)
	value.erase(receipt_field)
	var encoded: String = _canonical_json(value)
	var digest: String = ""
	if encoded != "":
		var context: HashingContext = HashingContext.new()
		if context.start(HashingContext.HASH_SHA256) == OK \
				and context.update(encoded.to_utf8_buffer()) == OK:
			digest = context.finish().hex_encode()
	value[id_field] = prefix + digest.substr(0, 16) if digest != "" else ""
	value[receipt_field] = _receipt_for(value)
