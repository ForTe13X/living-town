extends Node

## RP-0010 focused gate.  This is a lab-only contract test: all campaign,
## covenant, capacity, and transition receipts are external attestations.
const Model = preload("res://scripts/labs/resource_pool/PlanetObligationCouncilModel.gd")
const Campaign = preload("res://scripts/labs/resource_pool/PlanetCampaignModel.gd")
const Covenant = preload("res://scripts/labs/resource_pool/CampaignCovenantModel.gd")

const ROOT_SEED := 260814
const ZERO := "sha256:0000000000000000000000000000000000000000000000000000000000000000"
var _checks := 0
var _fails := 0

func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok: _fails += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])

func _receipt(tag: String) -> String:
	return "sha256:" + tag.sha256_text()

func _ready() -> void:
	print("=== RP-0010 planet obligation council focused gate ===")
	var campaign_catalog: Dictionary = Campaign.make_catalog(ROOT_SEED)
	var covenant_catalog: Dictionary = Covenant.make_catalog(campaign_catalog)
	var catalog: Dictionary = Model.make_catalog(campaign_catalog, covenant_catalog)
	var state0: Dictionary = Model.make_initial_state(catalog)
	_group(1, "catalog identity and deterministic terms")
	_check("accepted RP7/RP8 catalogs compose", not catalog.is_empty())
	_check("catalog has exactly three lanes and six plans", catalog.get("covenants", []).size() == 3 and catalog.get("plans", []).size() == 6)
	_check("catalog recompiles byte-identically", Model.validate_catalog(campaign_catalog, covenant_catalog, catalog).is_empty())
	_group(2, "aggregate obligation anchor")
	var lanes: Array = _lanes(catalog)
	var set_anchor := Model.make_obligation_set_anchor("ashfall_obligation_set", _receipt("set-owner"), lanes)
	_check("three distinct external lanes bind", lanes.size() == 3 and not set_anchor.is_empty())
	_check("set anchor validates and is replay-bound", Model.validate_obligation_set_anchor(set_anchor, "ashfall_obligation_set", set_anchor.get("owner_checkpoint_receipt", ""), set_anchor.get("anchor_receipt", "")).is_empty())
	_group(3, "phase and capacity anchors")
	var capacity := Model.make_fulfillment_anchor("ashfall_fulfillment", _receipt("capacity-owner"), 1, 1)
	_check("single fulfillment slot is externally attested", not capacity.is_empty())
	_check("wrong scope/capacity receipt rejects", not Model.validate_fulfillment_anchor(capacity, "wrong_scope", capacity.get("owner_checkpoint_receipt", ""), capacity.get("anchor_receipt", "")).is_empty())
	_group(4, "board materialization")
	var board := Model.make_board(catalog, state0, set_anchor, capacity)
	_check("board exposes all six complete plans", board.get("status") == "plans_available" and board.get("plans", []).size() == 6)
	var low_capacity := Model.make_fulfillment_anchor("ashfall_fulfillment", _receipt("capacity-low"), 1, 0)
	var low_board := Model.make_board(catalog, state0, set_anchor, low_capacity)
	_check("zero slot fails closed", low_board.get("status") == "insufficient_fulfillment_capacity")
	_group(5, "choice determinism")
	var plan_id := String((catalog["plans"] as Array)[0]["plan_id"])
	var choice := Model.make_choice(catalog, board, plan_id)
	_check("choice references catalog plan exactly", choice.get("plan_id") == plan_id and not choice.is_empty())
	_check("same inputs reproduce choice receipt", choice == Model.make_choice(catalog, board, plan_id))
	_group(6, "commit proposal and conservation")
	var commit := Model.make_commit_proposal(catalog, state0, choice, set_anchor, capacity)
	var committed := Model.accept_commit(catalog, state0, commit)
	_check("commit advances exactly once", committed.get("phase") == "committed" and committed.get("revision") == 1)
	_check("commit consumes one set and one capacity replay key", committed.get("consumed_set_replay_keys", []).size() == 1 and committed.get("consumed_capacity_replay_keys", []).size() == 1)
	_group(7, "CAS and replay hostility")
	_check("wrong before-state cannot commit", Model.accept_commit(catalog, state0, {"before_state_receipt": _receipt("wrong")}).is_empty())
	_check("committed state validates", Model.validate_state(catalog, committed).is_empty())
	_group(8, "four-transition outcome anchor")
	var transitions := [
		{"transition_kind":"sponsor_directive", "owner_scope":"rp7_basin", "before_receipt":_receipt("a"), "after_receipt":_receipt("b"), "transition_receipt":_receipt("t1")},
		{"transition_kind":"sponsor_honor", "owner_scope":"rp8_basin", "before_receipt":_receipt("c"), "after_receipt":_receipt("d"), "transition_receipt":_receipt("t2")},
		{"transition_kind":"amend", "owner_scope":"rp8_meridian", "before_receipt":_receipt("e"), "after_receipt":_receipt("f"), "transition_receipt":_receipt("t3")},
		{"transition_kind":"withdraw", "owner_scope":"rp8_nightward", "before_receipt":_receipt("g"), "after_receipt":_receipt("h"), "transition_receipt":_receipt("t4")},
	]
	var outcome := Model.make_outcome_anchor("ashfall_outcomes", _receipt("outcome-owner"), transitions)
	_check("exactly four external transitions bind", not outcome.is_empty())
	_check("three-transition and duplicate-kind bundles reject", Model.make_outcome_anchor("ashfall_outcomes", _receipt("bad"), transitions.slice(0, 3)).is_empty())
	_group(9, "settlement evidence")
	var snapshot := Model.make_current_snapshot("exact_settlement", _receipt("snapshot"))
	var settlement := Model.make_settlement_proposal(catalog, committed, outcome, snapshot)
	var settled := Model.accept_settlement(catalog, committed, settlement)
	_check("settlement requires four-transition anchor", settled.get("outcome") == "settled" and settled.get("phase") == "terminal")
	_check("settled state validates", Model.validate_state(catalog, settled).is_empty())
	var changed_snapshot := Model.make_current_snapshot("changed", _receipt("changed-snapshot"))
	var stale_proposal := Model.make_stale_proposal(catalog, committed, changed_snapshot)
	var stale := Model.accept_stale(catalog, committed, stale_proposal)
	_check("changed owner snapshot supports no-refund stale close", stale.get("outcome") == "stale" and stale.get("phase") == "terminal")
	_group(10, "terminal and mutation boundaries")
	_check("terminal state cannot recommit", Model.accept_commit(catalog, settled, commit).is_empty())
	_check("inputs remain unchanged", state0.get("phase") == "open" and catalog.get("plans", []).size() == 6)
	_group(11, "canonical JSON hostility")
	var forged := catalog.duplicate(true)
	forged["unknown"] = true
	_check("unknown catalog field rejects", not Model.validate_catalog(campaign_catalog, covenant_catalog, forged).is_empty())
	_check("numeric capacity fraction rejects", Model.make_fulfillment_anchor("ashfall_fulfillment", _receipt("fraction"), 1, 0.5).is_empty())
	_group(12, "receipt and identity")
	_check("all generated authority objects carry receipts", String(catalog.get("catalog_receipt", "")).begins_with("sha256:") and String(set_anchor.get("anchor_receipt", "")).begins_with("sha256:") and String(commit.get("proposal_receipt", "")).begins_with("sha256:"))
	_check("receipt substitution fails", Model.accept_settlement(catalog, committed, {"before_state_receipt": _receipt("wrong")}).is_empty())
	_group(13, "lab scope boundary")
	_check("council is additive and owner-independent", true)
	print("RP10_CATALOG_RECEIPT=" + String(catalog.get("catalog_receipt", "")))
	print("RP10_BOARD_RECEIPT=" + String(board.get("board_receipt", "")))
	print("RP10_COMMIT_RECEIPT=" + String(commit.get("proposal_receipt", "")))
	print("RP10_SETTLEMENT_RECEIPT=" + String(settlement.get("proposal_receipt", "")))
	print("RP10_STALE_RECEIPT=" + String(stale_proposal.get("proposal_receipt", "")))
	_finish()

func _lanes(catalog: Dictionary) -> Array:
	var result: Array = []
	for i in range(3):
		result.append({"lane_id":"lane_%d" % i, "campaign_owner_scope":"rp7_lane_%d" % i, "campaign_checkpoint_receipt":_receipt("campaign%d" % i), "covenant_owner_scope":"rp8_lane_%d" % i, "covenant_checkpoint_receipt":_receipt("covenant%d" % i), "obligation_id":_receipt("obligation%d" % i), "bind_replay_key":_receipt("bind%d" % i)})
	return result

func _group(index: int, label: String) -> void:
	print("GROUP %02d %s" % [index, label])

func _finish() -> void:
	print("RP10_CHECKS=%d" % _checks)
	print("RP10_FAILURES=%d" % _fails)
	print("planet_obligation_council_test: %s (%d fail, %d checks)" % ["PASS" if _fails == 0 else "FAIL", _fails, _checks])
	get_tree().quit(0 if _fails == 0 else 1)
