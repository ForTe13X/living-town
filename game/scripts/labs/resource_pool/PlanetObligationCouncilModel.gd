extends RefCounted

## RP-0010: owner-independent arbitration across simultaneously accepted
## campaign obligations.
##
## The council owns only its plan and replay ledger.  It never creates a
## campaign directive, amends or resolves a covenant, changes faction access,
## refunds capacity, advances an epoch, or writes a save.  An external
## obligation-set coordinator must attest that three distinct campaign-owner
## lanes coexist.  A second external owner attests the single fulfillment slot.
## Downstream settlement is factual only after independently accepted RP-0007
## and RP-0008 successor checkpoints form the exact four-transition plan.

const PlanetCampaignModel = preload(
	"res://scripts/labs/resource_pool/PlanetCampaignModel.gd"
)
const CampaignCovenantModel = preload(
	"res://scripts/labs/resource_pool/CampaignCovenantModel.gd"
)

const CATALOG_SCHEMA := "living-town.planet-obligation-council-catalog/v1"
const STATE_SCHEMA := "living-town.planet-obligation-council-state/v1"
const SET_ANCHOR_SCHEMA := "living-town.planet-obligation-set-anchor/v1"
const CAPACITY_ANCHOR_SCHEMA := "living-town.fulfillment-capacity-anchor/v1"
const BOARD_SCHEMA := "living-town.planet-obligation-council-board/v1"
const CHOICE_SCHEMA := "living-town.planet-obligation-council-choice/v1"
const PLAN_RECORD_SCHEMA := "living-town.planet-obligation-plan-record/v1"
const COMMIT_SCHEMA := "living-town.planet-obligation-plan-proposal/v1"
const CURRENT_SNAPSHOT_SCHEMA := "living-town.planet-obligation-current-snapshot/v1"
const OUTCOME_ANCHOR_SCHEMA := "living-town.planet-obligation-outcome-anchor/v1"
const SETTLEMENT_RECORD_SCHEMA := "living-town.planet-obligation-settlement-record/v1"
const SETTLEMENT_SCHEMA := "living-town.planet-obligation-settlement-proposal/v1"
const STALE_RECORD_SCHEMA := "living-town.planet-obligation-stale-record/v1"
const STALE_SCHEMA := "living-town.planet-obligation-stale-proposal/v1"
const PROJECTION_SCHEMA := "living-town.planet-obligation-council-projection/v1"

const TERMS_REVISION := "ashfall-planet-obligation-council-v1"
const COUNCIL_EPOCH := 1
const COUNCIL_SEASON := "autumn"
const REQUIRED_LANES := 3
const REQUIRED_PLANS := 6
const FULFILLMENT_COST := 1
const MAX_FULFILLMENT_SLOTS := 1
const MAX_STATE_REVISION := 2
const PHASES := ["open", "committed", "terminal"]
const OUTCOMES := ["", "settled", "stale"]
const DISPOSITIONS := ["amend", "sponsor", "withdraw"]
const SNAPSHOT_STATUSES := ["unchanged", "exact_settlement", "changed"]

const MAX_SAFE_JSON_INT := 9007199254740991
const MAX_CANONICAL_DEPTH := 32
const MAX_CANONICAL_NODES := 4096
const MAX_CANONICAL_CONTAINER := 256
const MAX_CANONICAL_STRING := 1024

const CATALOG_ID_PREFIX := "poc1:"
const PLAN_ID_PREFIX := "pop1:"
const SET_ANCHOR_ID_PREFIX := "poa1:"
const CAPACITY_ANCHOR_ID_PREFIX := "pof1:"
const BOARD_ID_PREFIX := "pob1:"
const CHOICE_ID_PREFIX := "pok1:"
const PLAN_RECORD_ID_PREFIX := "por1:"
const COMMIT_ID_PREFIX := "pot1:"
const SNAPSHOT_ID_PREFIX := "pos1:"
const OUTCOME_ANCHOR_ID_PREFIX := "poo1:"
const SETTLEMENT_RECORD_ID_PREFIX := "pox1:"
const SETTLEMENT_ID_PREFIX := "pol1:"
const STALE_RECORD_ID_PREFIX := "poz1:"
const STALE_ID_PREFIX := "pou1:"
const PROJECTION_ID_PREFIX := "poj1:"


static func make_catalog(campaign_catalog: Dictionary,
		covenant_catalog: Dictionary) -> Dictionary:
	if not PlanetCampaignModel.validate_catalog(campaign_catalog).is_empty() \
			or not CampaignCovenantModel.validate_catalog(
				campaign_catalog, covenant_catalog
			).is_empty():
		return {}
	var covenants_value: Variant = covenant_catalog.get("covenants")
	if not (covenants_value is Array) or (covenants_value as Array).size() != REQUIRED_LANES:
		return {}
	var covenant_summaries: Array[Dictionary] = []
	for raw_covenant: Variant in covenants_value:
		if not (raw_covenant is Dictionary):
			return {}
		var covenant: Dictionary = raw_covenant
		var summary := {
			"covenant_id": String(covenant.get("covenant_id", "")),
			"covenant_receipt": String(covenant.get("covenant_receipt", "")),
			"required_action": String(covenant.get("required_action", "")),
			"window_id": String(covenant.get("window_id", "")),
			"region_id": String(covenant.get("region_id", "")),
			"faction_id": String(covenant.get("faction_id", "")),
			"benefit": (covenant.get("benefit", {}) as Dictionary).duplicate(true),
		}
		if not _covenant_summary_valid(summary):
			return {}
		covenant_summaries.append(summary)
	covenant_summaries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["covenant_id"]) < String(right["covenant_id"]))
	var plans: Array[Dictionary] = []
	for sponsor: Dictionary in covenant_summaries:
		for amend: Dictionary in covenant_summaries:
			if amend["covenant_id"] == sponsor["covenant_id"]:
				continue
			var withdraw: Dictionary = {}
			for candidate: Dictionary in covenant_summaries:
				if candidate["covenant_id"] != sponsor["covenant_id"] \
						and candidate["covenant_id"] != amend["covenant_id"]:
					withdraw = candidate
					break
			var plan := _make_catalog_plan(sponsor, amend, withdraw)
			if plan.is_empty():
				return {}
			plans.append(plan)
	plans.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["plan_id"]) < String(right["plan_id"]))
	if plans.size() != REQUIRED_PLANS:
		return {}
	var authority := {
		"schema": CATALOG_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"campaign_catalog_id": String(campaign_catalog["catalog_id"]),
		"campaign_catalog_receipt": String(campaign_catalog["catalog_receipt"]),
		"covenant_catalog_id": String(covenant_catalog["catalog_id"]),
		"covenant_catalog_receipt": String(covenant_catalog["catalog_receipt"]),
		"planet_id": String(campaign_catalog["planet_id"]),
		"council_epoch": COUNCIL_EPOCH,
		"council_season": COUNCIL_SEASON,
		"required_lanes": REQUIRED_LANES,
		"fulfillment_cost": FULFILLMENT_COST,
		"covenants": covenant_summaries,
		"plans": plans,
	}
	var digest := _sha256_hex(_canonical_json(authority))
	if digest == "":
		return {}
	var result := authority.duplicate(true)
	result["catalog_id"] = CATALOG_ID_PREFIX + digest.substr(0, 16)
	result["catalog_receipt"] = "sha256:" + digest
	return result


static func validate_catalog(campaign_catalog: Dictionary,
		covenant_catalog: Dictionary, value: Variant) -> Array[String]:
	var normalized := _normalized_dictionary(value)
	var expected := make_catalog(campaign_catalog, covenant_catalog)
	if normalized.is_empty() or expected.is_empty() \
			or _canonical_json(normalized) != _canonical_json(expected):
		return ["council catalog does not match exact RP-0007/RP-0008 terms"]
	return []


static func normalize_catalog(campaign_catalog: Dictionary,
		covenant_catalog: Dictionary, value: Variant) -> Dictionary:
	var expected := make_catalog(campaign_catalog, covenant_catalog)
	var normalized := _normalized_dictionary(value)
	return expected if not expected.is_empty() and not normalized.is_empty() \
		and _canonical_json(expected) == _canonical_json(normalized) else {}


static func _make_catalog_plan(sponsor: Dictionary, amend: Dictionary,
		withdraw: Dictionary) -> Dictionary:
	if sponsor.is_empty() or amend.is_empty() or withdraw.is_empty():
		return {}
	var ids := {
		String(sponsor["covenant_id"]): true,
		String(amend["covenant_id"]): true,
		String(withdraw["covenant_id"]): true,
	}
	if ids.size() != REQUIRED_LANES:
		return {}
	var dispositions: Array[Dictionary] = [
		{"covenant_id": String(sponsor["covenant_id"]), "disposition": "sponsor"},
		{"covenant_id": String(amend["covenant_id"]), "disposition": "amend"},
		{"covenant_id": String(withdraw["covenant_id"]), "disposition": "withdraw"},
	]
	dispositions.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["covenant_id"]) < String(right["covenant_id"]))
	var authority := {
		"sponsor_covenant_id": String(sponsor["covenant_id"]),
		"sponsor_action": String(sponsor["required_action"]),
		"sponsor_benefit": (sponsor["benefit"] as Dictionary).duplicate(true),
		"amend_covenant_id": String(amend["covenant_id"]),
		"withdraw_covenant_id": String(withdraw["covenant_id"]),
		"dispositions": dispositions,
	}
	var digest := _sha256_hex(_canonical_json(authority))
	if digest == "":
		return {}
	var plan := authority.duplicate(true)
	plan["plan_id"] = PLAN_ID_PREFIX + digest.substr(0, 16)
	plan["plan_receipt"] = _receipt_for(plan)
	return plan if String(plan["plan_receipt"]) != "" else {}


static func _covenant_summary_valid(value: Dictionary) -> bool:
	var required := ["covenant_id", "covenant_receipt", "required_action",
		"window_id", "region_id", "faction_id", "benefit"]
	if not _exact_keys(value, required) \
			or not _short_id_valid(String(value.get("covenant_id", "")), "ccv1:") \
			or not _receipt_token_valid(String(value.get("covenant_receipt", ""))) \
			or String(value.get("required_action", "")) not in ["aid", "trade", "fortify"] \
			or not _short_id_valid(String(value.get("window_id", "")), "pcw1:") \
			or not _slug_valid(String(value.get("faction_id", ""))) \
			or not (value.get("benefit") is Dictionary):
		return false
	var benefit: Dictionary = value["benefit"]
	if not _exact_keys(benefit, ["relief", "commerce", "defense"]):
		return false
	var total := 0
	var axes := 0
	for key: String in ["relief", "commerce", "defense"]:
		var amount: Variant = _json_int(benefit.get(key), 0, 3)
		if amount == null or int(amount) not in [0, 3]:
			return false
		total += int(amount)
		axes += 1 if int(amount) == 3 else 0
	return total == 3 and axes == 1 and String(value.get("region_id", "")).begins_with("psa1|")


static func make_initial_state(catalog: Dictionary) -> Dictionary:
	if not _catalog_self_valid(catalog):
		return {}
	return _make_state(catalog, 0, "open", "", {}, {}, {}, [], [], "", "")


static func validate_state(catalog: Dictionary, value: Variant) -> Array[String]:
	if not _catalog_self_valid(catalog):
		return ["council state requires a valid catalog"]
	var data := _normalized_dictionary(value)
	if data.is_empty():
		return ["council state must be a bounded JSON Dictionary"]
	var required := ["schema", "terms_revision", "catalog_id", "catalog_receipt",
		"revision", "phase", "outcome", "plan_record", "settlement_record",
		"stale_record", "consumed_set_replay_keys", "consumed_capacity_replay_keys",
		"parent_state_receipt", "last_action_receipt", "state_receipt"]
	if not _exact_keys(data, required) or data.get("schema") != STATE_SCHEMA \
			or data.get("terms_revision") != TERMS_REVISION \
			or data.get("catalog_id") != catalog.get("catalog_id") \
			or data.get("catalog_receipt") != catalog.get("catalog_receipt") \
			or not (data.get("plan_record") is Dictionary) \
			or not (data.get("settlement_record") is Dictionary) \
			or not (data.get("stale_record") is Dictionary) \
			or not (data.get("consumed_set_replay_keys") is Array) \
			or not (data.get("consumed_capacity_replay_keys") is Array):
		return ["council state fields do not match V1"]
	var revision_value: Variant = _json_int(data.get("revision"), 0, MAX_STATE_REVISION)
	var phase := String(data.get("phase", ""))
	var outcome := String(data.get("outcome", ""))
	if revision_value == null or phase not in PHASES or outcome not in OUTCOMES:
		return ["council state lifecycle fields are invalid"]
	var revision := int(revision_value)
	var plan_record: Dictionary = data["plan_record"]
	var settlement_record: Dictionary = data["settlement_record"]
	var stale_record: Dictionary = data["stale_record"]
	if revision == 0:
		if phase != "open" or outcome != "" or not plan_record.is_empty() \
				or not settlement_record.is_empty() or not stale_record.is_empty():
			return ["initial council state ledger is inconsistent"]
	elif revision == 1:
		if phase != "committed" or outcome != "" \
				or not _plan_record_valid(catalog, plan_record) \
				or not settlement_record.is_empty() or not stale_record.is_empty():
			return ["committed council state ledger is inconsistent"]
	elif revision == 2:
		if phase != "terminal" or not _plan_record_valid(catalog, plan_record):
			return ["terminal council state is missing its plan"]
		if outcome == "settled":
			if not _settlement_record_valid(catalog, plan_record, settlement_record) \
					or not stale_record.is_empty():
				return ["settled council ledger is inconsistent"]
		elif outcome == "stale":
			if not _stale_record_valid(catalog, plan_record, stale_record) \
					or not settlement_record.is_empty():
				return ["stale council ledger is inconsistent"]
		else:
			return ["terminal council state requires a typed outcome"]
	var set_keys: Array = data["consumed_set_replay_keys"]
	var capacity_keys: Array = data["consumed_capacity_replay_keys"]
	var expected_keys := 0 if revision == 0 else 1
	if set_keys.size() != expected_keys or capacity_keys.size() != expected_keys \
			or not _sorted_unique_receipts(set_keys) \
			or not _sorted_unique_receipts(capacity_keys):
		return ["council replay ledgers are invalid"]
	if revision > 0:
		if String(set_keys[0]) != String(plan_record.get("set_replay_key", "")) \
				or String(capacity_keys[0]) \
				!= String(plan_record.get("capacity_replay_key", "")):
			return ["council replay ledgers do not match the committed plan"]
	for key: String in ["parent_state_receipt", "last_action_receipt", "state_receipt"]:
		if key == "state_receipt" or revision > 0:
			if not _receipt_token_valid(String(data.get(key, ""))):
				return ["council state receipt chain is invalid"]
		elif String(data.get(key, "")) != "":
			return ["initial council state cannot have a parent receipt"]
	var receipt_base := data.duplicate(true)
	receipt_base.erase("state_receipt")
	if String(data["state_receipt"]) != _receipt_for(receipt_base):
		return ["council state receipt does not recompute"]
	return []


static func accept_state_checkpoint(catalog: Dictionary, value: Variant,
		expected_state_receipt: String) -> Dictionary:
	if not _receipt_token_valid(expected_state_receipt):
		return {}
	var normalized := _normalized_dictionary(value)
	return normalized if not normalized.is_empty() \
		and validate_state(catalog, normalized).is_empty() \
		and String(normalized["state_receipt"]) == expected_state_receipt else {}


static func _make_state(catalog: Dictionary, revision: int, phase: String,
		outcome: String, plan_record: Dictionary, settlement_record: Dictionary,
		stale_record: Dictionary, set_keys: Array, capacity_keys: Array,
		parent_state_receipt: String, last_action_receipt: String) -> Dictionary:
	var base := {
		"schema": STATE_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(catalog["catalog_id"]),
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"revision": revision,
		"phase": phase,
		"outcome": outcome,
		"plan_record": plan_record.duplicate(true),
		"settlement_record": settlement_record.duplicate(true),
		"stale_record": stale_record.duplicate(true),
		"consumed_set_replay_keys": set_keys.duplicate(true),
		"consumed_capacity_replay_keys": capacity_keys.duplicate(true),
		"parent_state_receipt": parent_state_receipt,
		"last_action_receipt": last_action_receipt,
	}
	base["state_receipt"] = _receipt_for(base)
	return base if String(base["state_receipt"]) != "" else {}


static func make_fulfillment_anchor(owner_scope: String,
		owner_checkpoint_receipt: String, epoch_index: Variant,
		available_slots: Variant) -> Dictionary:
	var epoch_value: Variant = _json_int(epoch_index, COUNCIL_EPOCH, COUNCIL_EPOCH)
	var slots_value: Variant = _json_int(
		available_slots, 0, MAX_FULFILLMENT_SLOTS
	)
	if not _slug_valid(owner_scope) \
			or not _receipt_token_valid(owner_checkpoint_receipt) \
			or epoch_value == null or slots_value == null:
		return {}
	var replay_key := _receipt_for([owner_scope, owner_checkpoint_receipt])
	if replay_key == "":
		return {}
	var base := {
		"schema": CAPACITY_ANCHOR_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"owner_scope": owner_scope,
		"owner_checkpoint_receipt": owner_checkpoint_receipt,
		"epoch_index": int(epoch_value),
		"available_slots": int(slots_value),
		"capacity_replay_key": replay_key,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["anchor_id"] = CAPACITY_ANCHOR_ID_PREFIX + digest.substr(0, 16)
	base["anchor_receipt"] = _receipt_for(base)
	return base if String(base["anchor_receipt"]) != "" else {}


static func validate_fulfillment_anchor(value: Variant,
		expected_owner_scope: String, expected_owner_checkpoint_receipt: String,
		expected_anchor_receipt: String) -> Array[String]:
	if not _slug_valid(expected_owner_scope) \
			or not _receipt_token_valid(expected_owner_checkpoint_receipt) \
			or not _receipt_token_valid(expected_anchor_receipt):
		return ["fulfillment anchor requires external owner evidence"]
	var data := _normalized_dictionary(value)
	if data.is_empty():
		return ["fulfillment anchor must be bounded JSON"]
	var required := ["schema", "terms_revision", "owner_scope",
		"owner_checkpoint_receipt", "epoch_index", "available_slots",
		"capacity_replay_key", "anchor_id", "anchor_receipt"]
	if not _exact_keys(data, required) or data.get("schema") != CAPACITY_ANCHOR_SCHEMA \
			or data.get("terms_revision") != TERMS_REVISION \
			or String(data.get("owner_scope", "")) != expected_owner_scope \
			or String(data.get("owner_checkpoint_receipt", "")) \
			!= expected_owner_checkpoint_receipt \
			or String(data.get("anchor_receipt", "")) != expected_anchor_receipt:
		return ["fulfillment anchor does not match external owner evidence"]
	var expected := make_fulfillment_anchor(
		expected_owner_scope, expected_owner_checkpoint_receipt,
		data.get("epoch_index"), data.get("available_slots")
	)
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(data):
		return ["fulfillment anchor does not exactly recompute"]
	return []


static func normalize_fulfillment_anchor(value: Variant,
		expected_owner_scope: String, expected_owner_checkpoint_receipt: String,
		expected_anchor_receipt: String) -> Dictionary:
	if not validate_fulfillment_anchor(
		value, expected_owner_scope, expected_owner_checkpoint_receipt,
		expected_anchor_receipt
	).is_empty():
		return {}
	var data := _normalized_dictionary(value)
	return make_fulfillment_anchor(
		expected_owner_scope, expected_owner_checkpoint_receipt,
		data["epoch_index"], data["available_slots"]
	)


## The set anchor is an attestation, not a query.  The external campaign and
## covenant owners must provide the three accepted lanes and their replay keys.
static func make_obligation_set_anchor(owner_scope: String,
		owner_checkpoint_receipt: String, lanes: Array) -> Dictionary:
	if not _slug_valid(owner_scope) or not _receipt_token_valid(owner_checkpoint_receipt) \
			or lanes.size() != REQUIRED_LANES:
		return {}
	var normalized: Array[Dictionary] = []
	var seen := {}
	var seen_campaign := {}
	var seen_covenant := {}
	var seen_obligation := {}
	var seen_bind := {}
	for raw in lanes:
		if not (raw is Dictionary): return {}
		var lane: Dictionary = raw.duplicate(true)
		var required := ["lane_id", "campaign_owner_scope", "campaign_checkpoint_receipt",
			"covenant_owner_scope", "covenant_checkpoint_receipt", "obligation_id",
			"bind_replay_key"]
		if not _exact_keys(lane, required) or not _slug_valid(String(lane["lane_id"])) \
				or seen.has(String(lane["lane_id"])) \
				or seen_campaign.has(String(lane["campaign_owner_scope"])) \
				or seen_covenant.has(String(lane["covenant_owner_scope"])) \
				or seen_obligation.has(String(lane["obligation_id"])) \
				or seen_bind.has(String(lane["bind_replay_key"])) \
				or not _slug_valid(String(lane["campaign_owner_scope"])) \
				or not _slug_valid(String(lane["covenant_owner_scope"])) \
				or not _receipt_token_valid(String(lane["campaign_checkpoint_receipt"])) \
				or not _receipt_token_valid(String(lane["covenant_checkpoint_receipt"])) \
				or not _receipt_token_valid(String(lane["obligation_id"])) \
				or not _receipt_token_valid(String(lane["bind_replay_key"])):
			return {}
		seen[String(lane["lane_id"])] = true
		seen_campaign[String(lane["campaign_owner_scope"])] = true
		seen_covenant[String(lane["covenant_owner_scope"])] = true
		seen_obligation[String(lane["obligation_id"])] = true
		seen_bind[String(lane["bind_replay_key"])] = true
		normalized.append(lane)
	normalized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["lane_id"]) < String(b["lane_id"])
	)
	var base := {"schema": SET_ANCHOR_SCHEMA, "terms_revision": TERMS_REVISION,
		"owner_scope": owner_scope, "owner_checkpoint_receipt": owner_checkpoint_receipt,
		"epoch_index": COUNCIL_EPOCH, "lanes": normalized}
	base["anchor_id"] = SET_ANCHOR_ID_PREFIX + _sha256_hex(_canonical_json(base)).substr(0, 16)
	base["anchor_receipt"] = _receipt_for(base)
	return base if String(base["anchor_receipt"]) != "" else {}


static func validate_obligation_set_anchor(value: Variant, expected_owner_scope: String,
		expected_owner_checkpoint_receipt: String, expected_anchor_receipt: String) -> Array[String]:
	if not _slug_valid(expected_owner_scope) or not _receipt_token_valid(expected_owner_checkpoint_receipt) \
			or not _receipt_token_valid(expected_anchor_receipt): return ["set anchor requires external evidence"]
	var data := _normalized_dictionary(value)
	if data.is_empty() or not _exact_keys(data, ["schema", "terms_revision", "owner_scope", "owner_checkpoint_receipt", "epoch_index", "lanes", "anchor_id", "anchor_receipt"]): return ["set anchor shape is invalid"]
	if data["schema"] != SET_ANCHOR_SCHEMA or data["terms_revision"] != TERMS_REVISION \
			or data["owner_scope"] != expected_owner_scope or data["owner_checkpoint_receipt"] != expected_owner_checkpoint_receipt \
			or data["anchor_receipt"] != expected_anchor_receipt: return ["set anchor does not match external evidence"]
	var expected := make_obligation_set_anchor(expected_owner_scope, expected_owner_checkpoint_receipt, data["lanes"])
	var errors: Array[String] = []
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(data): errors.append("set anchor does not recompute")
	return errors


static func normalize_obligation_set_anchor(value: Variant, owner_scope: String,
		checkpoint_receipt: String, anchor_receipt: String) -> Dictionary:
	return value.duplicate(true) if validate_obligation_set_anchor(value, owner_scope, checkpoint_receipt, anchor_receipt).is_empty() else {}


static func make_board(catalog: Dictionary, state: Dictionary,
		set_anchor: Dictionary, capacity_anchor: Dictionary) -> Dictionary:
	if not _catalog_self_valid(catalog) or not validate_state(catalog, state).is_empty() \
			or state["phase"] != "open" or not _set_anchor_self_valid(set_anchor) \
			or not _capacity_anchor_self_valid(capacity_anchor): return {}
	var plans: Array = catalog["plans"].duplicate(true)
	var available := int(capacity_anchor.get("available_slots", 0)) >= FULFILLMENT_COST
	var status := "plans_available" if available else "insufficient_fulfillment_capacity"
	var base := {"schema": BOARD_SCHEMA, "terms_revision": TERMS_REVISION,
		"catalog_id": catalog["catalog_id"], "catalog_receipt": catalog["catalog_receipt"],
		"state_receipt": state["state_receipt"], "set_anchor_receipt": set_anchor.get("anchor_receipt", ""),
		"capacity_anchor_receipt": capacity_anchor.get("anchor_receipt", ""),
		"status": status, "plans": plans}
	base["board_id"] = BOARD_ID_PREFIX + _sha256_hex(_canonical_json(base)).substr(0, 16)
	base["board_receipt"] = _receipt_for(base)
	return base if String(base["board_receipt"]) != "" else {}


static func make_choice(catalog: Dictionary, board: Dictionary, plan_id: String) -> Dictionary:
	if not _catalog_self_valid(catalog) or board.is_empty() or board.get("status") != "plans_available" \
			or not _matches_receipt(board, "board_receipt") \
			or board.get("catalog_id") != catalog.get("catalog_id") \
			or board.get("catalog_receipt") != catalog.get("catalog_receipt"): return {}
	var plan := _plan_by_id(catalog, plan_id)
	if plan.is_empty(): return {}
	var base := {"schema": CHOICE_SCHEMA, "terms_revision": TERMS_REVISION,
		"catalog_id": catalog["catalog_id"], "board_id": board.get("board_id", ""),
		"board_receipt": board.get("board_receipt", ""), "plan_id": plan_id,
		"plan_receipt": plan["plan_receipt"]}
	base["choice_id"] = CHOICE_ID_PREFIX + _sha256_hex(_canonical_json(base)).substr(0, 16)
	base["choice_receipt"] = _receipt_for(base)
	return base if String(base["choice_receipt"]) != "" else {}


static func make_commit_proposal(catalog: Dictionary, state: Dictionary, choice: Dictionary,
		set_anchor: Dictionary, capacity_anchor: Dictionary) -> Dictionary:
	if not _catalog_self_valid(catalog) or validate_state(catalog, state).size() > 0 \
			or state.get("phase") != "open" or choice.is_empty() \
			or not _set_anchor_self_valid(set_anchor) or not _capacity_anchor_self_valid(capacity_anchor) \
			or not _matches_receipt(choice, "choice_receipt"): return {}
	var plan := _plan_by_id(catalog, String(choice.get("plan_id", "")))
	if plan.is_empty() or choice.get("plan_receipt") != plan["plan_receipt"]: return {}
	var record_base := {"schema": PLAN_RECORD_SCHEMA, "terms_revision": TERMS_REVISION,
		"catalog_receipt": catalog["catalog_receipt"], "plan_id": plan["plan_id"],
		"plan_receipt": plan["plan_receipt"], "choice_receipt": choice.get("choice_receipt", ""),
		"set_anchor_receipt": set_anchor.get("anchor_receipt", ""), "capacity_anchor_receipt": capacity_anchor.get("anchor_receipt", ""),
		"set_replay_key": set_anchor.get("owner_checkpoint_receipt", ""), "capacity_replay_key": capacity_anchor.get("capacity_replay_key", ""),
		"dispositions": plan["dispositions"]}
	record_base["record_id"] = PLAN_RECORD_ID_PREFIX + _sha256_hex(_canonical_json(record_base)).substr(0, 16)
	record_base["record_receipt"] = _receipt_for(record_base)
	if String(record_base["record_receipt"]) == "": return {}
	var base := {"schema": COMMIT_SCHEMA, "terms_revision": TERMS_REVISION,
		"before_state_receipt": state["state_receipt"], "plan_record": record_base,
		"set_anchor_receipt": set_anchor.get("anchor_receipt", ""), "capacity_anchor_receipt": capacity_anchor.get("anchor_receipt", "")}
	base["proposal_id"] = COMMIT_ID_PREFIX + _sha256_hex(_canonical_json(base)).substr(0, 16)
	base["proposal_receipt"] = _receipt_for(base)
	return base if String(base["proposal_receipt"]) != "" else {}


static func accept_commit(catalog: Dictionary, state: Dictionary, proposal: Dictionary) -> Dictionary:
	if not _catalog_self_valid(catalog) or not validate_state(catalog, state).is_empty() \
			or state.get("phase") != "open" or proposal.is_empty(): return {}
	var record: Dictionary = proposal.get("plan_record", {})
	if record.is_empty() or proposal.get("before_state_receipt") != state.get("state_receipt") \
			or not _matches_receipt(proposal, "proposal_receipt") or not _plan_record_valid(catalog, record): return {}
	var next := _make_state(catalog, 1, "committed", "", record, {}, {},
		[record.get("set_replay_key", "")], [record.get("capacity_replay_key", "")],
		state["state_receipt"], proposal.get("proposal_receipt", ""))
	return next if not next.is_empty() else {}


## Settlement consumes an externally accepted four-transition outcome bundle.
## It deliberately does not inspect or mutate those owners' state.
static func make_outcome_anchor(owner_scope: String, owner_checkpoint_receipt: String,
		transitions: Array) -> Dictionary:
	if not _slug_valid(owner_scope) or not _receipt_token_valid(owner_checkpoint_receipt) \
			or transitions.size() != 4: return {}
	var normalized: Array[Dictionary] = []
	for raw in transitions:
		if not (raw is Dictionary): return {}
		var item: Dictionary = raw.duplicate(true)
		if not _exact_keys(item, ["transition_kind", "owner_scope", "before_receipt", "after_receipt", "transition_receipt"]): return {}
		if String(item["transition_kind"]) not in ["sponsor_directive", "sponsor_honor", "amend", "withdraw"] \
				or not _slug_valid(String(item["owner_scope"])) \
				or not _receipt_token_valid(String(item["before_receipt"])) \
				or not _receipt_token_valid(String(item["after_receipt"])) \
				or not _receipt_token_valid(String(item["transition_receipt"])): return {}
		normalized.append(item)
	normalized.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		return String(a["transition_kind"]) < String(b["transition_kind"])
	)
	var kinds := []
	for item in normalized: kinds.append(item["transition_kind"])
	if kinds != ["amend", "sponsor_directive", "sponsor_honor", "withdraw"]: return {}
	var base := {"schema": OUTCOME_ANCHOR_SCHEMA, "terms_revision": TERMS_REVISION,
		"owner_scope": owner_scope, "owner_checkpoint_receipt": owner_checkpoint_receipt,
		"transitions": normalized}
	base["anchor_id"] = OUTCOME_ANCHOR_ID_PREFIX + _sha256_hex(_canonical_json(base)).substr(0,16)
	base["anchor_receipt"] = _receipt_for(base)
	return base if String(base["anchor_receipt"]) != "" else {}


static func validate_outcome_anchor(value: Variant, expected_owner_scope: String,
		expected_owner_checkpoint_receipt: String, expected_anchor_receipt: String) -> Array[String]:
	if not _slug_valid(expected_owner_scope) or not _receipt_token_valid(expected_owner_checkpoint_receipt) \
			or not _receipt_token_valid(expected_anchor_receipt): return ["outcome anchor requires external evidence"]
	var data := _normalized_dictionary(value)
	if data.is_empty() or data.get("schema") != OUTCOME_ANCHOR_SCHEMA \
			or data.get("owner_scope") != expected_owner_scope \
			or data.get("owner_checkpoint_receipt") != expected_owner_checkpoint_receipt \
			or data.get("anchor_receipt") != expected_anchor_receipt: return ["outcome anchor identity mismatch"]
	var expected := make_outcome_anchor(expected_owner_scope, expected_owner_checkpoint_receipt, data.get("transitions", []))
	var errors: Array[String] = []
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(data): errors.append("outcome anchor does not recompute")
	return errors


static func make_current_snapshot(status: String, snapshot_receipt: String) -> Dictionary:
	if status not in SNAPSHOT_STATUSES or not _receipt_token_valid(snapshot_receipt): return {}
	return {"schema": CURRENT_SNAPSHOT_SCHEMA, "snapshot_receipt": snapshot_receipt, "status": status}


static func validate_current_snapshot(value: Variant) -> Array[String]:
	var data := _normalized_dictionary(value)
	if data.is_empty() or not _exact_keys(data, ["schema", "snapshot_receipt", "status"]) \
			or data.get("schema") != CURRENT_SNAPSHOT_SCHEMA \
			or data.get("status") not in SNAPSHOT_STATUSES \
			or not _receipt_token_valid(String(data.get("snapshot_receipt", ""))): return ["current snapshot is invalid"]
	return []


static func make_stale_proposal(catalog: Dictionary, state: Dictionary,
		current_snapshot: Dictionary) -> Dictionary:
	if not _catalog_self_valid(catalog) or validate_state(catalog, state).size() > 0 \
			or state.get("phase") != "committed" or current_snapshot.is_empty() \
			or current_snapshot.get("status") != "changed": return {}
	var base := {"schema": STALE_SCHEMA, "terms_revision": TERMS_REVISION,
		"before_state_receipt": state["state_receipt"],
		"plan_record_id": state["plan_record"]["record_id"],
		"current_snapshot_receipt": current_snapshot.get("snapshot_receipt", ""),
		"stale_reason": "external_owner_changed"}
	base["proposal_id"] = STALE_ID_PREFIX + _sha256_hex(_canonical_json(base)).substr(0,16)
	base["proposal_receipt"] = _receipt_for(base)
	return base if String(base["proposal_receipt"]) != "" else {}


static func accept_stale(catalog: Dictionary, state: Dictionary, proposal: Dictionary) -> Dictionary:
	if not _catalog_self_valid(catalog) or validate_state(catalog, state).size() > 0 \
			or state.get("phase") != "committed" or proposal.is_empty() \
			or proposal.get("before_state_receipt") != state.get("state_receipt") \
			or not _matches_receipt(proposal, "proposal_receipt"): return {}
	var base := {"schema": STALE_RECORD_SCHEMA, "terms_revision": TERMS_REVISION,
		"catalog_receipt": catalog["catalog_receipt"], "plan_record_id": state["plan_record"]["record_id"],
		"proposal_receipt": proposal.get("proposal_receipt", ""), "stale_reason": proposal.get("stale_reason", "external_owner_changed")}
	base["record_id"] = STALE_RECORD_ID_PREFIX + _sha256_hex(_canonical_json(base)).substr(0,16)
	base["record_receipt"] = _receipt_for(base)
	return _make_state(catalog, 2, "terminal", "stale", state["plan_record"], {}, base,
		state["consumed_set_replay_keys"], state["consumed_capacity_replay_keys"],
		state["state_receipt"], proposal.get("proposal_receipt", ""))


static func make_settlement_proposal(catalog: Dictionary, state: Dictionary,
		outcome_anchor: Dictionary, current_snapshot: Dictionary) -> Dictionary:
	if not _catalog_self_valid(catalog) or validate_state(catalog, state).size() > 0 \
			or state.get("phase") != "committed" or outcome_anchor.is_empty() \
			or not _outcome_anchor_self_valid(outcome_anchor) \
			or not validate_current_snapshot(current_snapshot).is_empty(): return {}
	var record_base := {"schema": SETTLEMENT_RECORD_SCHEMA, "terms_revision": TERMS_REVISION,
		"catalog_receipt": catalog["catalog_receipt"], "plan_record_id": state["plan_record"]["record_id"],
		"plan_record_receipt": state["plan_record"]["record_receipt"],
		"outcome_anchor_receipt": outcome_anchor.get("anchor_receipt", ""),
		"current_snapshot_receipt": current_snapshot.get("snapshot_receipt", ""),
		"transition_count": 4}
	record_base["record_id"] = SETTLEMENT_RECORD_ID_PREFIX + _sha256_hex(_canonical_json(record_base)).substr(0,16)
	record_base["record_receipt"] = _receipt_for(record_base)
	var base := {"schema": SETTLEMENT_SCHEMA, "terms_revision": TERMS_REVISION,
		"before_state_receipt": state["state_receipt"], "settlement_record": record_base}
	base["proposal_id"] = SETTLEMENT_ID_PREFIX + _sha256_hex(_canonical_json(base)).substr(0,16)
	base["proposal_receipt"] = _receipt_for(base)
	return base if String(base["proposal_receipt"]) != "" else {}


static func accept_settlement(catalog: Dictionary, state: Dictionary,
		proposal: Dictionary) -> Dictionary:
	if not _catalog_self_valid(catalog) or validate_state(catalog, state).size() > 0 \
			or state.get("phase") != "committed" or proposal.is_empty() \
			or proposal.get("before_state_receipt") != state.get("state_receipt"): return {}
	var record: Dictionary = proposal.get("settlement_record", {})
	if record.is_empty() or int(record.get("transition_count", 0)) != 4 \
			or not _matches_receipt(proposal, "proposal_receipt") \
			or not _settlement_record_valid(catalog, state.get("plan_record", {}), record): return {}
	return _make_state(catalog, 2, "terminal", "settled", state["plan_record"], record, {},
		state["consumed_set_replay_keys"], state["consumed_capacity_replay_keys"],
		state["state_receipt"], proposal.get("proposal_receipt", ""))


static func _plan_by_id(catalog: Dictionary, plan_id: String) -> Dictionary:
	for raw in catalog.get("plans", []):
		if raw is Dictionary and String((raw as Dictionary).get("plan_id", "")) == plan_id:
			return (raw as Dictionary).duplicate(true)
	return {}


static func _catalog_self_valid(catalog: Dictionary) -> bool:
	if catalog.is_empty() or catalog.get("schema") != CATALOG_SCHEMA or catalog.get("terms_revision") != TERMS_REVISION \
			or int(catalog.get("required_lanes", 0)) != REQUIRED_LANES or catalog.get("plans", []).size() != REQUIRED_PLANS: return false
	return _receipt_token_valid(String(catalog.get("catalog_receipt", "")))


static func _sorted_unique_receipts(values: Array) -> bool:
	var previous := ""
	for raw in values:
		var token := String(raw)
		if not _receipt_token_valid(token) or (previous != "" and token <= previous): return false
		previous = token
	return true


static func _set_anchor_self_valid(anchor: Dictionary) -> bool:
	if anchor.is_empty(): return false
	var scope := String(anchor.get("owner_scope", ""))
	var checkpoint := String(anchor.get("owner_checkpoint_receipt", ""))
	var receipt := String(anchor.get("anchor_receipt", ""))
	return validate_obligation_set_anchor(anchor, scope, checkpoint, receipt).is_empty()


static func _capacity_anchor_self_valid(anchor: Dictionary) -> bool:
	if anchor.is_empty(): return false
	var scope := String(anchor.get("owner_scope", ""))
	var checkpoint := String(anchor.get("owner_checkpoint_receipt", ""))
	var receipt := String(anchor.get("anchor_receipt", ""))
	return validate_fulfillment_anchor(anchor, scope, checkpoint, receipt).is_empty()


static func _outcome_anchor_self_valid(anchor: Dictionary) -> bool:
	if anchor.is_empty(): return false
	var scope := String(anchor.get("owner_scope", ""))
	var checkpoint := String(anchor.get("owner_checkpoint_receipt", ""))
	var receipt := String(anchor.get("anchor_receipt", ""))
	return validate_outcome_anchor(anchor, scope, checkpoint, receipt).is_empty()


static func _normalized_dictionary(value: Variant) -> Dictionary:
	return value.duplicate(true) if value is Dictionary and _canonical_json(value) != "" else {}


static func _plan_record_valid(catalog: Dictionary, record: Dictionary) -> bool:
	return not record.is_empty() and record.get("schema") == PLAN_RECORD_SCHEMA \
			and _plan_by_id(catalog, String(record.get("plan_id", ""))).get("plan_receipt", "") == record.get("plan_receipt", "") \
			and _matches_receipt(record, "record_receipt")


static func _settlement_record_valid(_catalog: Dictionary, _plan: Dictionary, record: Dictionary) -> bool:
	return not record.is_empty() and record.get("schema") == SETTLEMENT_RECORD_SCHEMA \
			and int(record.get("transition_count", 0)) == 4 and _matches_receipt(record, "record_receipt")


static func _stale_record_valid(_catalog: Dictionary, _plan: Dictionary, record: Dictionary) -> bool:
	return not record.is_empty() and record.get("schema") == STALE_RECORD_SCHEMA \
			and _matches_receipt(record, "record_receipt")


static func _matches_receipt(value: Dictionary, field: String) -> bool:
	if not value.has(field) or not _receipt_token_valid(String(value.get(field, ""))): return false
	var body := value.duplicate(true)
	body.erase(field)
	return String(value[field]) == _receipt_for(body)


static func _exact_keys(data: Dictionary, required: Array) -> bool:
	if data.size() != required.size(): return false
	for key in data:
		if typeof(key) != TYPE_STRING or String(key) not in required: return false
	return true


static func _json_int(value: Variant, minimum: int, maximum: int) -> Variant:
	if typeof(value) == TYPE_INT and int(value) >= minimum and int(value) <= maximum: return int(value)
	if typeof(value) == TYPE_FLOAT and is_finite(float(value)) and float(value) == floor(float(value)) \
			and float(value) >= minimum and float(value) <= maximum: return int(value)
	return null


static func _slug_valid(value: String) -> bool:
	if value.is_empty() or value.length() > 64: return false
	for i in value.length():
		var c := value.unicode_at(i)
		if not (c >= 97 and c <= 122 or c >= 48 and c <= 57 or (i > 0 and (c == 45 or c == 95))): return false
	return true


static func _short_id_valid(value: String, prefix: String) -> bool:
	return value.begins_with(prefix) and value.length() == prefix.length() + 16 and _lower_hex_valid(value.substr(prefix.length()), 16)


static func _receipt_token_valid(value: String) -> bool:
	return value.begins_with("sha256:") and value.length() == 71 and _lower_hex_valid(value.substr(7), 64)


static func _lower_hex_valid(value: String, width: int) -> bool:
	if value.length() != width: return false
	for i in value.length():
		var c := value.unicode_at(i)
		if not (c >= 48 and c <= 57 or c >= 97 and c <= 102): return false
	return true


static func _sha256_hex(value: String) -> String:
	if value.is_empty(): return ""
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK or ctx.update(value.to_utf8_buffer()) != OK: return ""
	return ctx.finish().hex_encode()


static func _receipt_for(value: Variant) -> String:
	var encoded := _canonical_json(value)
	var digest := _sha256_hex(encoded)
	return "sha256:" + digest if digest != "" else ""


static func _canonical_json(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL: return "null"
		TYPE_BOOL: return "true" if value else "false"
		TYPE_INT: return str(value)
		TYPE_FLOAT: return str(int(value)) if is_finite(float(value)) and float(value) == floor(float(value)) else ""
		TYPE_STRING: return JSON.stringify(String(value))
		TYPE_ARRAY:
			var items: Array[String] = []
			for child in value as Array:
				var item := _canonical_json(child)
				if item == "": return ""
				items.append(item)
			return "[" + ",".join(items) + "]"
		TYPE_DICTIONARY:
			var keys: Array[String] = []
			for key in value: keys.append(String(key))
			keys.sort()
			var fields: Array[String] = []
			for key in keys:
				var item := _canonical_json(value[key])
				if item == "": return ""
				fields.append(JSON.stringify(key) + ":" + item)
			return "{" + ",".join(fields) + "}"
	return ""
