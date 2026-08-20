extends RefCounted

## RP-0008: owner-independent, multi-epoch campaign covenants.
##
## This model records an abstract allocation promise. It never mutates the
## RP-0007 campaign, a region owner, the shared network, production factions,
## or a save. Every mutation API returns a joint proposal for external CAS.
## The owner must maintain exactly one accepted covenant-state checkpoint per
## campaign. Structural state validation is not catalog authority: mutation and
## observation APIs recompile the catalog from the full accepted RP-0007 catalog.
## Applying a proposed region delta and accepting its successor checkpoint stay
## outside this model.

const PlanetCampaignModel = preload(
	"res://scripts/labs/resource_pool/PlanetCampaignModel.gd"
)

const CATALOG_SCHEMA := "living-town.campaign-covenant-catalog/v1"
const STATE_SCHEMA := "living-town.campaign-covenant-state/v1"
const BOARD_SCHEMA := "living-town.campaign-covenant-board/v1"
const CHOICE_SCHEMA := "living-town.campaign-covenant-choice/v1"
const BIND_RECORD_SCHEMA := "living-town.campaign-covenant-bind-record/v1"
const AMEND_RECORD_SCHEMA := "living-town.campaign-covenant-amend-record/v1"
const RESOLUTION_RECORD_SCHEMA := "living-town.campaign-covenant-resolution-record/v1"
const BIND_SCHEMA := "living-town.campaign-covenant-bind-proposal/v1"
const PROJECTION_SCHEMA := "living-town.campaign-covenant-obligation-projection/v1"
const AMEND_SCHEMA := "living-town.campaign-covenant-amend-proposal/v1"
const RESOLUTION_SCHEMA := "living-town.campaign-covenant-resolution-proposal/v1"
const REGION_DELTA_SCHEMA := "living-town.campaign-covenant-region-delta/v1"

const TERMS_REVISION := "ashfall-campaign-covenant-v1"
const PHASES := ["open", "active", "terminal"]
const BIND_EPOCH := 0
const LAST_DECISION_EPOCH := 2
const TERMINAL_EPOCH := 3
const MAX_TRACK := 3
const MAX_AMENDMENTS := 1
const MAX_TRANSITIONS := 3
const MAX_SAFE_JSON_INT := 9007199254740991
const MAX_CANONICAL_DEPTH := 32
const MAX_CANONICAL_NODES := 2048
const MAX_CANONICAL_CONTAINER := 256
const MAX_CANONICAL_STRING := 1024

const CATALOG_ID_PREFIX := "ccc1:"
const COVENANT_ID_PREFIX := "ccv1:"
const BOARD_ID_PREFIX := "ccb1:"
const CHOICE_ID_PREFIX := "cck1:"
const BIND_RECORD_ID_PREFIX := "ccr1:"
const AMEND_RECORD_ID_PREFIX := "cca1:"
const RESOLUTION_RECORD_ID_PREFIX := "ccs1:"
const BIND_ID_PREFIX := "cct1:"
const PROJECTION_ID_PREFIX := "ccp1:"
const AMEND_ID_PREFIX := "ccm1:"
const RESOLUTION_ID_PREFIX := "ccx1:"


static func _covenant_specs() -> Array[Dictionary]:
	return [
		{
			"covenant_key": "relief_guarantee",
			"window_key": "basin_relief",
			"required_action": "aid",
			"label": "RELIEF GUARANTEE",
			"benefit": {"relief": 3, "commerce": 0, "defense": 0},
		},
		{
			"covenant_key": "exchange_charter",
			"window_key": "meridian_trade",
			"required_action": "trade",
			"label": "EXCHANGE CHARTER",
			"benefit": {"relief": 0, "commerce": 3, "defense": 0},
		},
		{
			"covenant_key": "watch_compact",
			"window_key": "nightward_fortify",
			"required_action": "fortify",
			"label": "WATCH COMPACT",
			"benefit": {"relief": 0, "commerce": 0, "defense": 3},
		},
	]


static func make_catalog(campaign_catalog: Dictionary) -> Dictionary:
	if not PlanetCampaignModel.validate_catalog(campaign_catalog).is_empty():
		return {}
	var covenants: Array[Dictionary] = []
	var seen_ids := {}
	for spec in _covenant_specs():
		var window := _campaign_window_by_key(
			campaign_catalog, String(spec["window_key"])
		)
		var directive := _campaign_directive_by_action(
			campaign_catalog, String(spec["required_action"])
		)
		if window.is_empty() or directive.is_empty() \
				or String(directive["origin_window_id"]) != String(window["window_id"]):
			return {}
		var authority := {
			"terms_revision": TERMS_REVISION,
			"campaign_catalog_receipt": String(campaign_catalog["catalog_receipt"]),
			"covenant_key": String(spec["covenant_key"]),
			"window_id": String(window["window_id"]),
			"region_id": String(window["region_id"]),
			"faction_id": String(window["faction_id"]),
			"required_action": String(spec["required_action"]),
			"directive_id": String(directive["directive_id"]),
			"directive_receipt": String(directive["directive_receipt"]),
			"due_delay_epochs": 1,
			"amend_delay_epochs": 1,
			"max_amendments": MAX_AMENDMENTS,
			"bind_access_delta": 1,
			"amend_access_delta": -1,
			"honor_access_delta": 1,
			"withdraw_access_delta": -2,
			"benefit": (spec["benefit"] as Dictionary).duplicate(true),
		}
		var digest := _sha256_hex(_canonical_json(authority))
		if digest == "":
			return {}
		var covenant := authority.duplicate(true)
		covenant["label"] = String(spec["label"])
		covenant["covenant_id"] = COVENANT_ID_PREFIX + digest.substr(0, 16)
		covenant["covenant_receipt"] = _receipt_for(covenant)
		if String(covenant["covenant_receipt"]) == "" \
				or seen_ids.has(String(covenant["covenant_id"])):
			return {}
		seen_ids[String(covenant["covenant_id"])] = true
		covenants.append(covenant)
	covenants.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["covenant_id"]) < String(right["covenant_id"]))
	var authority := {
		"schema": CATALOG_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"campaign_catalog_id": String(campaign_catalog["catalog_id"]),
		"campaign_catalog_receipt": String(campaign_catalog["catalog_receipt"]),
		"planet_id": String(campaign_catalog["planet_id"]),
		"binding_epoch": BIND_EPOCH,
		"last_decision_epoch": LAST_DECISION_EPOCH,
		"terminal_epoch": TERMINAL_EPOCH,
		"covenants": covenants,
	}
	var digest := _sha256_hex(_canonical_json(authority))
	if digest == "":
		return {}
	var result := authority.duplicate(true)
	result["catalog_id"] = CATALOG_ID_PREFIX + digest.substr(0, 16)
	result["catalog_receipt"] = "sha256:" + digest
	return result


static func validate_catalog(campaign_catalog: Dictionary,
		value: Variant) -> Array[String]:
	if not (value is Dictionary):
		return ["campaign covenant catalog must be a Dictionary"]
	var expected := make_catalog(campaign_catalog)
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(value):
		return ["campaign covenant catalog does not match accepted RP-0007 terms"]
	return []


static func normalize_catalog(campaign_catalog: Dictionary,
		value: Variant) -> Dictionary:
	var expected := make_catalog(campaign_catalog)
	return expected if not expected.is_empty() and value is Dictionary \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func make_initial_state(catalog: Dictionary) -> Dictionary:
	if not _catalog_self_valid(catalog):
		return {}
	return _make_state(catalog, 0, "open", {}, [], {}, [], "", "")


static func validate_state(catalog: Dictionary, value: Variant) -> Array[String]:
	if not _catalog_self_valid(catalog):
		return ["campaign covenant state requires a valid catalog"]
	if not (value is Dictionary):
		return ["campaign covenant state must be a Dictionary"]
	var data: Dictionary = value
	var required := ["schema", "terms_revision", "catalog_id", "catalog_receipt",
		"campaign_catalog_id", "campaign_catalog_receipt", "revision", "phase",
		"covenant_record", "amendment_records", "resolution_record",
		"consumed_campaign_action_keys", "parent_state_receipt",
		"last_action_receipt", "state_receipt"]
	if not _exact_keys(data, required) or not (data.get("covenant_record") is Dictionary) \
			or not (data.get("amendment_records") is Array) \
			or not (data.get("resolution_record") is Dictionary) \
			or not (data.get("consumed_campaign_action_keys") is Array):
		return ["campaign covenant state fields must match V1 exactly"]
	if data.get("schema") != STATE_SCHEMA or data.get("terms_revision") != TERMS_REVISION \
			or data.get("catalog_id") != catalog.get("catalog_id") \
			or data.get("catalog_receipt") != catalog.get("catalog_receipt") \
			or data.get("campaign_catalog_id") != catalog.get("campaign_catalog_id") \
			or data.get("campaign_catalog_receipt") != catalog.get("campaign_catalog_receipt"):
		return ["campaign covenant state catalog identity mismatch"]
	if not _bounded_int(data.get("revision"), 0, MAX_TRANSITIONS) \
			or _string_if(data.get("phase")) not in PHASES:
		return ["campaign covenant revision or phase is invalid"]
	var covenant_record: Dictionary = data["covenant_record"]
	var amendments: Array = data["amendment_records"]
	var resolution_record: Dictionary = data["resolution_record"]
	var phase := String(data["phase"])
	if covenant_record.is_empty():
		if phase != "open" or not amendments.is_empty() or not resolution_record.is_empty():
			return ["open covenant state cannot contain lifecycle records"]
	else:
		if not _bind_record_valid(catalog, covenant_record) \
				or not _amendment_records_valid(catalog, covenant_record, amendments) \
				or not _resolution_record_valid(
					catalog, covenant_record, amendments, resolution_record
				):
			return ["campaign covenant lifecycle ledger is invalid"]
		if (phase == "active") != resolution_record.is_empty() \
				or phase == "open":
			return ["campaign covenant phase does not match lifecycle ledger"]
	var expected_revision := (0 if covenant_record.is_empty() else 1) \
		+ amendments.size() + (0 if resolution_record.is_empty() else 1)
	if int(data["revision"]) != expected_revision:
		return ["campaign covenant revision does not derive from transition ledger"]
	var expected_keys: Array[String] = []
	if not resolution_record.is_empty() \
			and String(resolution_record.get("resolution", "")) == "honored":
		expected_keys.append(String(resolution_record["campaign_action_replay_key"]))
	if _canonical_json(expected_keys) != _canonical_json(
		data["consumed_campaign_action_keys"]
	) or not _sorted_unique_receipts(data["consumed_campaign_action_keys"]):
		return ["campaign covenant action replay ledger is invalid"]
	for key in ["parent_state_receipt", "last_action_receipt", "state_receipt"]:
		if typeof(data.get(key)) != TYPE_STRING:
			return ["campaign covenant receipt fields must be Strings"]
	if int(data["revision"]) == 0:
		if String(data["parent_state_receipt"]) != "" \
				or String(data["last_action_receipt"]) != "":
			return ["initial campaign covenant state cannot have a parent action"]
	elif not _receipt_token_valid(String(data["parent_state_receipt"])) \
			or not _receipt_token_valid(String(data["last_action_receipt"])):
		return ["campaign covenant state chain receipts are invalid"]
	var base := data.duplicate(true)
	base.erase("state_receipt")
	if String(data["state_receipt"]) != _receipt_for(base):
		return ["campaign covenant state receipt mismatch"]
	return []


static func normalize_state(catalog: Dictionary, value: Variant) -> Dictionary:
	if not (value is Dictionary) or not validate_state(catalog, value).is_empty():
		return {}
	var data: Dictionary = value
	var result := data.duplicate(true)
	result["revision"] = int(data["revision"])
	var covenant: Dictionary = result["covenant_record"]
	if not covenant.is_empty():
		for key in ["bound_epoch", "due_epoch", "bind_access_requested",
				"bind_access_applied"]:
			covenant[key] = int(covenant[key])
	var amendments: Array[Dictionary] = []
	for raw_record in result["amendment_records"]:
		var record: Dictionary = (raw_record as Dictionary).duplicate(true)
		for key in ["amended_epoch", "old_due_epoch", "new_due_epoch",
				"access_requested", "access_applied"]:
			record[key] = int(record[key])
		amendments.append(record)
	result["amendment_records"] = amendments
	var resolution: Dictionary = result["resolution_record"]
	if not resolution.is_empty():
		for key in ["resolved_epoch", "due_epoch", "access_requested",
				"access_applied"]:
			resolution[key] = int(resolution[key])
	return result


static func accept_state_checkpoint(catalog: Dictionary, value: Variant,
		expected_state_receipt: String) -> Dictionary:
	if not _receipt_token_valid(expected_state_receipt):
		return {}
	var normalized := normalize_state(catalog, value)
	return normalized if not normalized.is_empty() \
		and String(normalized["state_receipt"]) == expected_state_receipt else {}


static func _make_state(catalog: Dictionary, revision: int, phase: String,
		covenant_record: Dictionary, amendment_records: Array,
		resolution_record: Dictionary, consumed_keys: Array,
		parent_state_receipt: String, last_action_receipt: String) -> Dictionary:
	var base := {
		"schema": STATE_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(catalog["catalog_id"]),
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"campaign_catalog_id": String(catalog["campaign_catalog_id"]),
		"campaign_catalog_receipt": String(catalog["campaign_catalog_receipt"]),
		"revision": revision,
		"phase": phase,
		"covenant_record": covenant_record.duplicate(true),
		"amendment_records": amendment_records.duplicate(true),
		"resolution_record": resolution_record.duplicate(true),
		"consumed_campaign_action_keys": consumed_keys.duplicate(true),
		"parent_state_receipt": parent_state_receipt,
		"last_action_receipt": last_action_receipt,
	}
	base["state_receipt"] = _receipt_for(base)
	return base if String(base["state_receipt"]) != "" else {}


static func _catalog_self_valid(catalog: Dictionary) -> bool:
	var required := ["schema", "terms_revision", "campaign_catalog_id",
		"campaign_catalog_receipt", "planet_id", "binding_epoch",
		"last_decision_epoch", "terminal_epoch", "covenants", "catalog_id",
		"catalog_receipt"]
	if not _exact_keys(catalog, required) or catalog.get("schema") != CATALOG_SCHEMA \
			or catalog.get("terms_revision") != TERMS_REVISION \
			or not (catalog.get("covenants") is Array) \
			or not _short_id_valid(_string_if(catalog.get("catalog_id")), CATALOG_ID_PREFIX) \
			or not _receipt_token_valid(_string_if(catalog.get("catalog_receipt"))) \
			or not _short_id_valid(_string_if(
				catalog.get("campaign_catalog_id")
			), "pcc1:") \
			or not _receipt_token_valid(_string_if(
				catalog.get("campaign_catalog_receipt")
			)) or not _bounded_int(catalog.get("binding_epoch"), BIND_EPOCH, BIND_EPOCH) \
			or not _bounded_int(catalog.get("last_decision_epoch"),
				LAST_DECISION_EPOCH, LAST_DECISION_EPOCH) \
			or not _bounded_int(catalog.get("terminal_epoch"), TERMINAL_EPOCH, TERMINAL_EPOCH):
		return false
	var covenants: Array = catalog["covenants"]
	if covenants.size() != _covenant_specs().size():
		return false
	var previous := ""
	var seen_keys := {}
	var seen_windows := {}
	for raw_covenant in covenants:
		if not (raw_covenant is Dictionary) \
				or not _catalog_covenant_valid(raw_covenant as Dictionary):
			return false
		var covenant: Dictionary = raw_covenant
		var covenant_id := String(covenant["covenant_id"])
		var covenant_key := String(covenant["covenant_key"])
		var window_id := String(covenant["window_id"])
		if covenant_id <= previous or seen_keys.has(covenant_key) \
				or seen_windows.has(window_id) \
				or covenant.get("campaign_catalog_receipt") \
				!= catalog.get("campaign_catalog_receipt"):
			return false
		previous = covenant_id
		seen_keys[covenant_key] = true
		seen_windows[window_id] = true
	var id_base := catalog.duplicate(true)
	id_base.erase("catalog_id")
	id_base.erase("catalog_receipt")
	var digest := _sha256_hex(_canonical_json(id_base))
	if digest == "" or String(catalog["catalog_id"]) \
			!= CATALOG_ID_PREFIX + digest.substr(0, 16) \
			or String(catalog["catalog_receipt"]) != "sha256:" + digest:
		return false
	return true


static func _catalog_covenant_valid(covenant: Dictionary) -> bool:
	var required := ["terms_revision", "campaign_catalog_receipt", "covenant_key",
		"window_id", "region_id", "faction_id", "required_action", "directive_id",
		"directive_receipt", "due_delay_epochs", "amend_delay_epochs",
		"max_amendments", "bind_access_delta", "amend_access_delta",
		"honor_access_delta", "withdraw_access_delta", "benefit", "label",
		"covenant_id", "covenant_receipt"]
	if not _exact_keys(covenant, required) or covenant.get("terms_revision") != TERMS_REVISION \
			or not (covenant.get("benefit") is Dictionary) \
			or not _receipt_token_valid(_string_if(
				covenant.get("campaign_catalog_receipt")
			)) \
			or not _slug_valid(_string_if(covenant.get("covenant_key"))) \
			or not _short_id_valid(_string_if(covenant.get("window_id")), "pcw1:") \
			or not _slug_valid(_string_if(covenant.get("faction_id"))) \
			or _string_if(covenant.get("required_action")) not in ["aid", "trade", "fortify"] \
			or not _short_id_valid(_string_if(covenant.get("directive_id")), "pcd1:") \
			or not _receipt_token_valid(_string_if(covenant.get("directive_receipt"))) \
			or not _short_id_valid(_string_if(covenant.get("covenant_id")), COVENANT_ID_PREFIX) \
			or not _receipt_token_valid(_string_if(covenant.get("covenant_receipt"))) \
			or typeof(covenant.get("label")) != TYPE_STRING \
			or String(covenant.get("label", "")).is_empty() \
			or typeof(covenant.get("region_id")) != TYPE_STRING \
			or String(covenant.get("region_id", "")).is_empty() \
			or String(covenant.get("region_id", "")).length() > 256:
		return false
	for pair in [["due_delay_epochs", 1], ["amend_delay_epochs", 1],
			["max_amendments", 1], ["bind_access_delta", 1],
			["amend_access_delta", -1], ["honor_access_delta", 1],
			["withdraw_access_delta", -2]]:
		if not _bounded_int(covenant.get(pair[0]), int(pair[1]), int(pair[1])):
			return false
	var benefit: Dictionary = covenant["benefit"]
	if not _exact_keys(benefit, ["relief", "commerce", "defense"]):
		return false
	var benefit_total := 0
	for key in ["relief", "commerce", "defense"]:
		if not _bounded_int(benefit.get(key), 0, 3):
			return false
		benefit_total += int(benefit[key])
	if benefit_total != 3:
		return false
	var id_authority := covenant.duplicate(true)
	id_authority.erase("label")
	id_authority.erase("covenant_id")
	id_authority.erase("covenant_receipt")
	var id_digest := _sha256_hex(_canonical_json(id_authority))
	if id_digest == "" or String(covenant["covenant_id"]) \
			!= COVENANT_ID_PREFIX + id_digest.substr(0, 16):
		return false
	var receipt_base := covenant.duplicate(true)
	receipt_base.erase("covenant_receipt")
	return String(covenant["covenant_receipt"]) == _receipt_for(receipt_base)


static func _catalog_covenant_by_id(catalog: Dictionary,
		covenant_id: String) -> Dictionary:
	for raw_covenant in catalog.get("covenants", []):
		if raw_covenant is Dictionary and String((raw_covenant as Dictionary).get(
				"covenant_id", "")) == covenant_id:
			return (raw_covenant as Dictionary).duplicate(true)
	return {}


static func _campaign_window_by_key(campaign_catalog: Dictionary,
		window_key: String) -> Dictionary:
	for raw_window in campaign_catalog.get("windows", []):
		if raw_window is Dictionary and String((raw_window as Dictionary).get(
				"window_key", "")) == window_key:
			return (raw_window as Dictionary).duplicate(true)
	return {}


static func _campaign_directive_by_action(campaign_catalog: Dictionary,
		action: String) -> Dictionary:
	for raw_directive in campaign_catalog.get("directives", []):
		if raw_directive is Dictionary and String((raw_directive as Dictionary).get(
				"action", "")) == action:
			return (raw_directive as Dictionary).duplicate(true)
	return {}


static func _bind_record_valid(catalog: Dictionary, record: Dictionary) -> bool:
	var required := ["schema", "terms_revision", "catalog_receipt", "covenant_id",
		"covenant_receipt", "campaign_owner_scope", "binding_campaign_state_receipt",
		"binding_replay_key", "bound_epoch", "bound_season", "due_epoch",
		"due_season", "required_action", "faction_id", "window_id", "region_id",
		"global_network_scope", "global_network_checkpoint_receipt",
		"binding_region_scope", "binding_region_checkpoint_receipt",
		"binding_adapter_receipt", "bind_access_requested", "bind_access_applied",
		"region_delta_receipt", "choice_receipt", "record_id", "record_receipt"]
	if not _exact_keys(record, required) or record.get("schema") != BIND_RECORD_SCHEMA \
			or record.get("terms_revision") != TERMS_REVISION \
			or record.get("catalog_receipt") != catalog.get("catalog_receipt") \
			or not _bounded_int(record.get("bound_epoch"), BIND_EPOCH, BIND_EPOCH) \
			or not _bounded_int(record.get("due_epoch"), 1, 1) \
			or String(record.get("bound_season", "")) != "spring" \
			or String(record.get("due_season", "")) != "autumn" \
			or not _bounded_int(record.get("bind_access_requested"), 1, 1) \
			or not _bounded_int(record.get("bind_access_applied"), 1, 1):
		return false
	var covenant := _catalog_covenant_by_id(catalog, _string_if(record.get("covenant_id")))
	if covenant.is_empty() or record.get("covenant_receipt") != covenant.get("covenant_receipt") \
			or record.get("required_action") != covenant.get("required_action") \
			or record.get("faction_id") != covenant.get("faction_id") \
			or record.get("window_id") != covenant.get("window_id") \
			or record.get("region_id") != covenant.get("region_id"):
		return false
	for key in ["campaign_owner_scope", "global_network_scope", "binding_region_scope"]:
		if not _slug_valid(_string_if(record.get(key))):
			return false
	var scopes := {
		String(record["campaign_owner_scope"]): true,
		String(record["global_network_scope"]): true,
		String(record["binding_region_scope"]): true,
	}
	if scopes.size() != 3:
		return false
	for key in ["binding_campaign_state_receipt", "binding_replay_key",
			"global_network_checkpoint_receipt", "binding_region_checkpoint_receipt",
			"binding_adapter_receipt", "region_delta_receipt", "choice_receipt",
			"record_receipt"]:
		if not _receipt_token_valid(_string_if(record.get(key))):
			return false
	if String(record["binding_replay_key"]) != _receipt_for([
		String(record["campaign_owner_scope"]),
		String(record["binding_campaign_state_receipt"]), "bind",
	]):
		return false
	return _record_id_and_receipt_valid(record, "record_id", "record_receipt",
		BIND_RECORD_ID_PREFIX)


static func _amendment_records_valid(catalog: Dictionary, covenant_record: Dictionary,
		records: Array) -> bool:
	if records.size() > MAX_AMENDMENTS:
		return false
	if records.is_empty():
		return true
	if not (records[0] is Dictionary):
		return false
	var record: Dictionary = records[0]
	var required := ["schema", "terms_revision", "catalog_receipt", "covenant_id",
		"covenant_record_id", "covenant_record_receipt", "campaign_owner_scope",
		"campaign_state_receipt", "amended_epoch", "old_due_epoch", "new_due_epoch",
		"new_due_season", "global_network_scope", "global_network_checkpoint_receipt",
		"region_scope", "region_checkpoint_receipt", "adapter_receipt",
		"access_requested", "access_applied", "region_delta_receipt",
		"record_id", "record_receipt"]
	if not _exact_keys(record, required) or record.get("schema") != AMEND_RECORD_SCHEMA \
			or record.get("terms_revision") != TERMS_REVISION \
			or record.get("catalog_receipt") != catalog.get("catalog_receipt") \
			or record.get("covenant_id") != covenant_record.get("covenant_id") \
			or record.get("covenant_record_id") != covenant_record.get("record_id") \
			or record.get("covenant_record_receipt") != covenant_record.get("record_receipt") \
			or record.get("campaign_owner_scope") != covenant_record.get("campaign_owner_scope") \
			or record.get("global_network_scope") != covenant_record.get("global_network_scope") \
			or record.get("region_scope") != covenant_record.get("binding_region_scope") \
			or not _bounded_int(record.get("amended_epoch"), 1, 1) \
			or not _bounded_int(record.get("old_due_epoch"), 1, 1) \
			or not _bounded_int(record.get("new_due_epoch"), 2, 2) \
			or String(record.get("new_due_season", "")) != "winter" \
			or not _bounded_int(record.get("access_requested"), -1, -1) \
			or not _bounded_int(record.get("access_applied"), -1, -1):
		return false
	for key in ["campaign_state_receipt", "global_network_checkpoint_receipt",
			"region_checkpoint_receipt", "adapter_receipt", "region_delta_receipt",
			"record_receipt"]:
		if not _receipt_token_valid(_string_if(record.get(key))):
			return false
	if String(record["campaign_state_receipt"]) \
			== String(covenant_record["binding_campaign_state_receipt"]) \
			or String(record["region_checkpoint_receipt"]) \
			== String(covenant_record["binding_region_checkpoint_receipt"]) \
			or String(record["adapter_receipt"]) \
			== String(covenant_record["binding_adapter_receipt"]):
		return false
	return _record_id_and_receipt_valid(record, "record_id", "record_receipt",
		AMEND_RECORD_ID_PREFIX)


static func _resolution_record_valid(catalog: Dictionary, covenant_record: Dictionary,
		amendments: Array, record: Dictionary) -> bool:
	if record.is_empty():
		return true
	var required := ["schema", "terms_revision", "catalog_receipt", "covenant_id",
		"covenant_record_id", "covenant_record_receipt", "resolution",
		"resolved_epoch", "due_epoch", "campaign_owner_scope", "campaign_state_receipt",
		"directive_record_id", "directive_record_receipt", "campaign_action_replay_key",
		"global_network_scope", "global_network_checkpoint_receipt", "region_scope",
		"region_checkpoint_receipt", "adapter_receipt", "access_requested",
		"access_applied", "region_delta_status", "region_delta_receipt",
		"record_id", "record_receipt"]
	if not _exact_keys(record, required) or record.get("schema") != RESOLUTION_RECORD_SCHEMA \
			or record.get("terms_revision") != TERMS_REVISION \
			or record.get("catalog_receipt") != catalog.get("catalog_receipt") \
			or record.get("covenant_id") != covenant_record.get("covenant_id") \
			or record.get("covenant_record_id") != covenant_record.get("record_id") \
			or record.get("covenant_record_receipt") != covenant_record.get("record_receipt") \
			or _string_if(record.get("resolution")) not in ["honored", "withdrawn"] \
			or record.get("campaign_owner_scope") != covenant_record.get("campaign_owner_scope") \
			or record.get("global_network_scope") != covenant_record.get("global_network_scope") \
			or record.get("region_scope") != covenant_record.get("binding_region_scope"):
		return false
	var due_epoch := _effective_due_epoch(covenant_record, amendments)
	if not _bounded_int(record.get("due_epoch"), due_epoch, due_epoch) \
			or not _bounded_int(record.get("resolved_epoch"), due_epoch, TERMINAL_EPOCH) \
			or _string_if(record.get("region_delta_status")) not in ["applied", "superseded"]:
		return false
	var honored := String(record["resolution"]) == "honored"
	if honored:
		if not _short_id_valid(_string_if(record.get("directive_record_id")), "pcr1:") \
				or not _receipt_token_valid(_string_if(record.get("directive_record_receipt"))) \
				or not _receipt_token_valid(_string_if(record.get("campaign_action_replay_key"))) \
				or String(record["campaign_action_replay_key"]) != _receipt_for([
					String(record["campaign_owner_scope"]),
					String(record["directive_record_receipt"]),
				]) or not _bounded_int(record.get("access_requested"), 1, 1) \
				or not _bounded_int(record.get("access_applied"), 0, 1):
			return false
	else:
		if String(record.get("directive_record_id", "")) != "" \
				or String(record.get("directive_record_receipt", "")) != "" \
				or String(record.get("campaign_action_replay_key", "")) != "" \
				or not _bounded_int(record.get("access_requested"), -2, -2) \
				or not _bounded_int(record.get("access_applied"), -2, 0):
			return false
	if (String(record["region_delta_status"]) == "applied") \
			!= (int(record["access_applied"]) != 0):
		return false
	for key in ["campaign_state_receipt", "global_network_checkpoint_receipt",
			"region_checkpoint_receipt", "adapter_receipt", "region_delta_receipt",
			"record_receipt"]:
		if not _receipt_token_valid(_string_if(record.get(key))):
			return false
	var previous_region_checkpoint := String(covenant_record[
		"binding_region_checkpoint_receipt"
	])
	var previous_adapter := String(covenant_record["binding_adapter_receipt"])
	var previous_campaign_state := String(covenant_record[
		"binding_campaign_state_receipt"
	])
	if not amendments.is_empty():
		previous_region_checkpoint = String((amendments[0] as Dictionary)[
			"region_checkpoint_receipt"
		])
		previous_adapter = String((amendments[0] as Dictionary)["adapter_receipt"])
		previous_campaign_state = String((amendments[0] as Dictionary)[
			"campaign_state_receipt"
		])
	if String(record["region_checkpoint_receipt"]) == previous_region_checkpoint \
			or String(record["adapter_receipt"]) == previous_adapter:
		return false
	if String(record["campaign_state_receipt"]) == previous_campaign_state:
		return false
	return _record_id_and_receipt_valid(record, "record_id", "record_receipt",
		RESOLUTION_RECORD_ID_PREFIX)


static func _effective_due_epoch(covenant_record: Dictionary,
		amendments: Array) -> int:
	return int((amendments[0] as Dictionary)["new_due_epoch"]) \
		if not amendments.is_empty() else int(covenant_record.get("due_epoch", -1))


static func _record_id_and_receipt_valid(record: Dictionary, id_key: String,
		receipt_key: String, prefix: String) -> bool:
	if not _short_id_valid(_string_if(record.get(id_key)), prefix) \
			or not _receipt_token_valid(_string_if(record.get(receipt_key))):
		return false
	var id_base := record.duplicate(true)
	id_base.erase(id_key)
	id_base.erase(receipt_key)
	var digest := _sha256_hex(_canonical_json(id_base))
	if digest == "" or String(record[id_key]) != prefix + digest.substr(0, 16):
		return false
	var receipt_base := record.duplicate(true)
	receipt_base.erase(receipt_key)
	return String(record[receipt_key]) == _receipt_for(receipt_base)


static func _sorted_unique_receipts(value: Array) -> bool:
	var previous := ""
	for index in value.size():
		if typeof(value[index]) != TYPE_STRING \
				or not _receipt_token_valid(String(value[index])) \
				or (index > 0 and String(value[index]) <= previous):
			return false
		previous = String(value[index])
	return true


static func _bounded_int(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= minimum and int(value) <= maximum
	if typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number == floor(number) \
		and number >= float(minimum) and number <= float(maximum) \
		and absf(number) <= float(MAX_SAFE_JSON_INT)


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
	return value.begins_with(prefix) and value.length() == prefix.length() + 16 \
		and _lower_hex_valid(value.substr(prefix.length()), 16)


static func _receipt_token_valid(value: String) -> bool:
	return value.begins_with("sha256:") and value.length() == 71 \
		and _lower_hex_valid(value.substr(7), 64)


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
	var node_budget: Array[int] = [0]
	return _canonical_json_bounded(value, 0, node_budget)


static func _canonical_json_bounded(value: Variant, depth: int,
		node_budget: Array[int]) -> String:
	if depth > MAX_CANONICAL_DEPTH or node_budget.is_empty() \
			or node_budget[0] >= MAX_CANONICAL_NODES:
		return ""
	node_budget[0] += 1
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		TYPE_INT:
			var integer := int(value)
			if integer < -MAX_SAFE_JSON_INT or integer > MAX_SAFE_JSON_INT:
				return ""
			return str(integer)
		TYPE_FLOAT:
			var number := float(value)
			if not is_finite(number) or number != floor(number) \
					or absf(number) > float(MAX_SAFE_JSON_INT):
				return ""
			return str(int(number))
		TYPE_STRING:
			if String(value).length() > MAX_CANONICAL_STRING:
				return ""
			return JSON.stringify(String(value))
		TYPE_ARRAY:
			if (value as Array).size() > MAX_CANONICAL_CONTAINER:
				return ""
			var items: Array[String] = []
			for item in value as Array:
				var encoded := _canonical_json_bounded(
					item, depth + 1, node_budget
				)
				if encoded == "":
					return ""
				items.append(encoded)
			return "[" + ",".join(items) + "]"
		TYPE_DICTIONARY:
			var data: Dictionary = value
			if data.size() > MAX_CANONICAL_CONTAINER:
				return ""
			var keys: Array[String] = []
			for raw_key in data:
				if typeof(raw_key) != TYPE_STRING \
						or String(raw_key).length() > MAX_CANONICAL_STRING:
					return ""
				keys.append(String(raw_key))
			keys.sort()
			var fields: Array[String] = []
			for key in keys:
				var encoded := _canonical_json_bounded(
					data[key], depth + 1, node_budget
				)
				if encoded == "":
					return ""
				fields.append("%s:%s" % [JSON.stringify(key), encoded])
			return "{" + ",".join(fields) + "}"
	return ""


static func make_covenant_board(catalog: Dictionary, state: Dictionary,
		accepted_state_receipt: String, campaign_catalog: Dictionary,
		campaign_state: Dictionary, accepted_campaign_state_receipt: String,
		campaign_owner_scope: String, adapters: Array, adapter_acceptances: Array,
		global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String) -> Dictionary:
	var normalized_catalog := normalize_catalog(campaign_catalog, catalog)
	if normalized_catalog.is_empty() \
			or not _slug_valid(campaign_owner_scope) \
			or not _slug_valid(global_network_scope) \
			or campaign_owner_scope == global_network_scope \
			or not _receipt_token_valid(accepted_global_network_checkpoint_receipt):
		return {}
	var normalized_state := accept_state_checkpoint(
		normalized_catalog, state, accepted_state_receipt
	)
	var normalized_campaign := PlanetCampaignModel.accept_state_checkpoint(
		campaign_catalog, campaign_state, accepted_campaign_state_receipt
	)
	var evidence := _normalize_adapter_set(
		campaign_catalog, adapters, adapter_acceptances, campaign_owner_scope,
		global_network_scope, accepted_global_network_checkpoint_receipt
	)
	if normalized_state.is_empty() or normalized_campaign.is_empty() or evidence.is_empty():
		return {}
	if String(normalized_state["phase"]) != "open":
		var durable_record: Dictionary = normalized_state["covenant_record"]
		var durable_adapter: Dictionary = _adapter_by_window(evidence["adapters"]).get(
			String(durable_record["window_id"]), {}
		)
		if campaign_owner_scope != String(durable_record["campaign_owner_scope"]) \
				or global_network_scope \
				!= String(durable_record["global_network_scope"]) \
				or durable_adapter.is_empty() \
				or String(durable_adapter["region_scope"]) \
				!= String(durable_record["binding_region_scope"]):
			return {}
	var status := "binding_window_closed"
	var options: Array[Dictionary] = []
	if String(normalized_state["phase"]) == "active":
		status = "already_active"
	elif String(normalized_state["phase"]) == "terminal":
		status = "cycle_terminal"
	elif int(normalized_campaign["epoch_index"]) == BIND_EPOCH \
			and String(normalized_campaign["season"]) == "spring" \
			and String(normalized_campaign["phase"]) == "open":
		status = "no_eligible_covenant"
		var adapter_by_window := _adapter_by_window(evidence["adapters"])
		for raw_covenant in normalized_catalog["covenants"]:
			var covenant: Dictionary = raw_covenant
			var adapter: Dictionary = adapter_by_window.get(
				String(covenant["window_id"]), {}
			)
			var option := _make_board_option(campaign_catalog, covenant, adapter)
			if not option.is_empty():
				options.append(option)
		options.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return String(left["option_id"]) < String(right["option_id"]))
		if not options.is_empty():
			status = "covenants_available"
	var base := {
		"schema": BOARD_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(normalized_catalog["catalog_id"]),
		"catalog_receipt": String(normalized_catalog["catalog_receipt"]),
		"state_receipt": String(normalized_state["state_receipt"]),
		"accepted_state_receipt": accepted_state_receipt,
		"revision": int(normalized_state["revision"]),
		"campaign_catalog_id": String(campaign_catalog["catalog_id"]),
		"campaign_catalog_receipt": String(campaign_catalog["catalog_receipt"]),
		"campaign_owner_scope": campaign_owner_scope,
		"campaign_state_receipt": String(normalized_campaign["state_receipt"]),
		"accepted_campaign_state_receipt": accepted_campaign_state_receipt,
		"campaign_epoch": int(normalized_campaign["epoch_index"]),
		"campaign_season": String(normalized_campaign["season"]),
		"campaign_phase": String(normalized_campaign["phase"]),
		"global_network_scope": global_network_scope,
		"accepted_global_network_checkpoint_receipt":
			accepted_global_network_checkpoint_receipt,
		"adapter_acceptances": evidence["acceptances"],
		"decision_status": status,
		"options": options,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["board_id"] = BOARD_ID_PREFIX + digest.substr(0, 16)
	base["board_receipt"] = _receipt_for(base)
	return base if String(base["board_receipt"]) != "" else {}


static func validate_covenant_board(catalog: Dictionary, state: Dictionary,
		accepted_state_receipt: String, campaign_catalog: Dictionary,
		campaign_state: Dictionary, accepted_campaign_state_receipt: String,
		campaign_owner_scope: String, adapters: Array, adapter_acceptances: Array,
		global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String,
		value: Variant) -> Array[String]:
	var expected := make_covenant_board(
		catalog, state, accepted_state_receipt, campaign_catalog, campaign_state,
		accepted_campaign_state_receipt, campaign_owner_scope, adapters,
		adapter_acceptances, global_network_scope,
		accepted_global_network_checkpoint_receipt
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["covenant board does not derive from accepted campaign and region owners"]
	return []


static func normalize_covenant_board(catalog: Dictionary, state: Dictionary,
		accepted_state_receipt: String, campaign_catalog: Dictionary,
		campaign_state: Dictionary, accepted_campaign_state_receipt: String,
		campaign_owner_scope: String, adapters: Array, adapter_acceptances: Array,
		global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String,
		value: Variant) -> Dictionary:
	var expected := make_covenant_board(
		catalog, state, accepted_state_receipt, campaign_catalog, campaign_state,
		accepted_campaign_state_receipt, campaign_owner_scope, adapters,
		adapter_acceptances, global_network_scope,
		accepted_global_network_checkpoint_receipt
	)
	return expected if not expected.is_empty() and value is Dictionary \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func make_covenant_choice(board: Dictionary, covenant_id: String) -> Dictionary:
	if not _board_self_valid(board) \
			or not _short_id_valid(covenant_id, COVENANT_ID_PREFIX):
		return {}
	var option := _board_option_by_id(board, covenant_id)
	if option.is_empty():
		return {}
	var base := {
		"schema": CHOICE_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"board_id": String(board["board_id"]),
		"board_receipt": String(board["board_receipt"]),
		"state_receipt": String(board["state_receipt"]),
		"campaign_state_receipt": String(board["campaign_state_receipt"]),
		"option_id": covenant_id,
		"covenant_id": String(option["covenant_id"]),
		"covenant_receipt": String(option["covenant_receipt"]),
		"faction_id": String(option["faction_id"]),
		"window_id": String(option["window_id"]),
		"required_action": String(option["required_action"]),
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["choice_id"] = CHOICE_ID_PREFIX + digest.substr(0, 16)
	base["choice_receipt"] = _receipt_for(base)
	return base if String(base["choice_receipt"]) != "" else {}


static func validate_covenant_choice(board: Dictionary,
		value: Variant) -> Array[String]:
	if not (value is Dictionary):
		return ["campaign covenant choice must be a Dictionary"]
	var expected := make_covenant_choice(
		board, _string_if((value as Dictionary).get("option_id"))
	)
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(value):
		return ["campaign covenant choice does not derive from its exact board"]
	return []


static func normalize_covenant_choice(board: Dictionary,
		value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var expected := make_covenant_choice(
		board, _string_if((value as Dictionary).get("option_id"))
	)
	return expected if not expected.is_empty() \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func _make_board_option(campaign_catalog: Dictionary, covenant: Dictionary,
		adapter: Dictionary) -> Dictionary:
	if adapter.is_empty() or String(adapter.get("window_id", "")) \
			!= String(covenant["window_id"]):
		return {}
	var before := _normalize_signals(adapter.get("signals"))
	if before.is_empty() or int(before["faction_access"]) >= MAX_TRACK:
		return {}
	var after := before.duplicate(true)
	after["faction_access"] = int(before["faction_access"]) + 1
	var directive := _campaign_directive_by_action(
		campaign_catalog, String(covenant["required_action"])
	)
	if directive.is_empty() or String(directive["directive_id"]) \
			!= String(covenant["directive_id"]):
		return {}
	var due_season := "autumn"
	var expected_cost := int(directive["favored_capacity_cost"]) \
		if String(directive["favored_season"]) == due_season \
		else int(directive["offseason_capacity_cost"])
	return {
		"option_id": String(covenant["covenant_id"]),
		"covenant_id": String(covenant["covenant_id"]),
		"covenant_receipt": String(covenant["covenant_receipt"]),
		"label": String(covenant["label"]),
		"faction_id": String(covenant["faction_id"]),
		"window_id": String(covenant["window_id"]),
		"region_id": String(covenant["region_id"]),
		"required_action": String(covenant["required_action"]),
		"benefit": (covenant["benefit"] as Dictionary).duplicate(true),
		"bound_epoch": BIND_EPOCH,
		"due_epoch": BIND_EPOCH + int(covenant["due_delay_epochs"]),
		"due_season": due_season,
		"expected_due_capacity_cost": expected_cost,
		"region_scope": String(adapter["region_scope"]),
		"region_checkpoint_receipt": String(adapter["region_checkpoint_receipt"]),
		"adapter_receipt": String(adapter["adapter_receipt"]),
		"region_effect": {
			"before_signals": before,
			"access_requested": 1,
			"access_applied": 1,
			"after_signals": after,
		},
	}


static func _normalize_adapter_set(campaign_catalog: Dictionary, adapters: Array,
		acceptances: Array, campaign_owner_scope: String, global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String) -> Dictionary:
	if adapters.size() != (campaign_catalog["windows"] as Array).size() \
			or acceptances.size() != adapters.size():
		return {}
	var acceptance_by_window := {}
	for raw_acceptance in acceptances:
		if not (raw_acceptance is Dictionary):
			return {}
		var acceptance: Dictionary = raw_acceptance
		var required := ["window_id", "expected_region_scope",
			"accepted_region_checkpoint_receipt", "expected_adapter_receipt"]
		var window_id := _string_if(acceptance.get("window_id"))
		if not _exact_keys(acceptance, required) \
				or not _short_id_valid(window_id, "pcw1:") \
				or acceptance_by_window.has(window_id) \
				or not _slug_valid(_string_if(acceptance.get("expected_region_scope"))) \
				or not _receipt_token_valid(_string_if(
					acceptance.get("accepted_region_checkpoint_receipt")
				)) or not _receipt_token_valid(_string_if(
					acceptance.get("expected_adapter_receipt")
				)):
			return {}
		acceptance_by_window[window_id] = acceptance
	var normalized_adapters: Array[Dictionary] = []
	var seen_windows := {}
	var seen_region_scopes := {}
	for raw_adapter in adapters:
		if not (raw_adapter is Dictionary):
			return {}
		var adapter: Dictionary = raw_adapter
		var window_id := _string_if(adapter.get("window_id"))
		if not acceptance_by_window.has(window_id) or seen_windows.has(window_id):
			return {}
		var acceptance: Dictionary = acceptance_by_window[window_id]
		var region_scope := String(acceptance["expected_region_scope"])
		if region_scope in [campaign_owner_scope, global_network_scope] \
				or seen_region_scopes.has(region_scope):
			return {}
		var normalized := PlanetCampaignModel.normalize_window_adapter(
			campaign_catalog, adapter, region_scope,
			String(acceptance["accepted_region_checkpoint_receipt"]),
			global_network_scope, accepted_global_network_checkpoint_receipt,
			String(acceptance["expected_adapter_receipt"])
		)
		if normalized.is_empty():
			return {}
		seen_windows[window_id] = true
		seen_region_scopes[region_scope] = true
		normalized_adapters.append(normalized)
	if seen_windows.size() != (campaign_catalog["windows"] as Array).size():
		return {}
	normalized_adapters.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["window_id"]) < String(right["window_id"]))
	var normalized_acceptances: Array[Dictionary] = []
	for adapter in normalized_adapters:
		normalized_acceptances.append(
			(acceptance_by_window[String(adapter["window_id"])] as Dictionary).duplicate(true)
		)
	return {"adapters": normalized_adapters, "acceptances": normalized_acceptances}


static func _normalize_one_adapter(campaign_catalog: Dictionary, adapter: Dictionary,
		acceptance: Dictionary, campaign_owner_scope: String,
		global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String) -> Dictionary:
	var required := ["window_id", "expected_region_scope",
		"accepted_region_checkpoint_receipt", "expected_adapter_receipt"]
	if not _exact_keys(acceptance, required) \
			or not _short_id_valid(_string_if(acceptance.get("window_id")), "pcw1:") \
			or _string_if(acceptance.get("window_id")) \
			!= _string_if(adapter.get("window_id")):
		return {}
	var region_scope := _string_if(acceptance.get("expected_region_scope"))
	if region_scope in [campaign_owner_scope, global_network_scope]:
		return {}
	return PlanetCampaignModel.normalize_window_adapter(
		campaign_catalog, adapter, region_scope,
		_string_if(acceptance.get("accepted_region_checkpoint_receipt")),
		global_network_scope, accepted_global_network_checkpoint_receipt,
		_string_if(acceptance.get("expected_adapter_receipt"))
	)


static func _adapter_by_window(adapters: Array) -> Dictionary:
	var result := {}
	for raw_adapter in adapters:
		var adapter: Dictionary = raw_adapter
		result[String(adapter["window_id"])] = adapter
	return result


static func _normalize_signals(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var data: Dictionary = value
	var keys := ["need_pressure", "security_pressure", "logistics_pressure",
		"faction_access"]
	if not _exact_keys(data, keys):
		return {}
	var result := {}
	for key in keys:
		if not _bounded_int(data.get(key), 0, MAX_TRACK):
			return {}
		result[key] = int(data[key])
	return result


static func _board_option_by_id(board: Dictionary, covenant_id: String) -> Dictionary:
	for raw_option in board.get("options", []):
		if raw_option is Dictionary and String((raw_option as Dictionary).get(
				"option_id", "")) == covenant_id:
			return (raw_option as Dictionary).duplicate(true)
	return {}


static func _board_self_valid(board: Dictionary) -> bool:
	var required := ["schema", "terms_revision", "catalog_id", "catalog_receipt",
		"state_receipt", "accepted_state_receipt", "revision", "campaign_catalog_id",
		"campaign_catalog_receipt", "campaign_owner_scope", "campaign_state_receipt",
		"accepted_campaign_state_receipt", "campaign_epoch", "campaign_season",
		"campaign_phase", "global_network_scope",
		"accepted_global_network_checkpoint_receipt", "adapter_acceptances",
		"decision_status", "options", "board_id", "board_receipt"]
	if not _exact_keys(board, required) or board.get("schema") != BOARD_SCHEMA \
			or board.get("terms_revision") != TERMS_REVISION \
			or not (board.get("adapter_acceptances") is Array) \
			or not (board.get("options") is Array) \
			or not _short_id_valid(_string_if(board.get("catalog_id")), CATALOG_ID_PREFIX) \
			or not _receipt_token_valid(_string_if(board.get("catalog_receipt"))) \
			or not _receipt_token_valid(_string_if(board.get("state_receipt"))) \
			or not _receipt_token_valid(_string_if(board.get("accepted_state_receipt"))) \
			or not _bounded_int(board.get("revision"), 0, MAX_TRANSITIONS) \
			or not _short_id_valid(_string_if(
				board.get("campaign_catalog_id")
			), "pcc1:") \
			or not _receipt_token_valid(_string_if(
				board.get("campaign_catalog_receipt")
			)) \
			or not _slug_valid(_string_if(board.get("campaign_owner_scope"))) \
			or not _receipt_token_valid(_string_if(board.get("campaign_state_receipt"))) \
			or not _receipt_token_valid(_string_if(
				board.get("accepted_campaign_state_receipt")
			)) \
			or not _bounded_int(board.get("campaign_epoch"), 0, TERMINAL_EPOCH) \
			or _string_if(board.get("campaign_season")) not in [
				"spring", "autumn", "winter", "terminal"
			] \
			or _string_if(board.get("campaign_phase")) not in [
				"open", "committed", "terminal"
			] \
			or not _slug_valid(_string_if(board.get("global_network_scope"))) \
			or not _receipt_token_valid(_string_if(
				board.get("accepted_global_network_checkpoint_receipt")
			)) \
			or not _short_id_valid(_string_if(board.get("board_id")), BOARD_ID_PREFIX) \
			or not _receipt_token_valid(_string_if(board.get("board_receipt"))) \
			or _string_if(board.get("decision_status")) not in [
				"covenants_available", "no_eligible_covenant", "binding_window_closed",
				"already_active", "cycle_terminal"
			]:
		return false
	if not _adapter_acceptances_self_valid(
		board["adapter_acceptances"], String(board["campaign_owner_scope"]),
		String(board["global_network_scope"])
	):
		return false
	var options: Array = board["options"]
	if (String(board["decision_status"]) == "covenants_available") \
			!= not options.is_empty() or options.size() > _covenant_specs().size():
		return false
	var previous := ""
	for raw_option in options:
		if not (raw_option is Dictionary) or not _board_option_valid(raw_option as Dictionary):
			return false
		var option_id := String((raw_option as Dictionary)["option_id"])
		if option_id <= previous:
			return false
		previous = option_id
	var id_base := board.duplicate(true)
	id_base.erase("board_id")
	id_base.erase("board_receipt")
	var digest := _sha256_hex(_canonical_json(id_base))
	if digest == "" or String(board["board_id"]) \
			!= BOARD_ID_PREFIX + digest.substr(0, 16):
		return false
	var receipt_base := board.duplicate(true)
	receipt_base.erase("board_receipt")
	return String(board["board_receipt"]) == _receipt_for(receipt_base)


static func _board_option_valid(option: Dictionary) -> bool:
	var required := ["option_id", "covenant_id", "covenant_receipt", "label",
		"faction_id", "window_id", "region_id", "required_action", "benefit",
		"bound_epoch", "due_epoch", "due_season", "expected_due_capacity_cost",
		"region_scope", "region_checkpoint_receipt", "adapter_receipt", "region_effect"]
	if not _exact_keys(option, required) or not (option.get("benefit") is Dictionary) \
			or not (option.get("region_effect") is Dictionary) \
			or not _short_id_valid(_string_if(option.get("option_id")), COVENANT_ID_PREFIX) \
			or option.get("option_id") != option.get("covenant_id") \
			or not _receipt_token_valid(_string_if(option.get("covenant_receipt"))) \
			or typeof(option.get("label")) != TYPE_STRING \
			or String(option.get("label", "")).is_empty() \
			or String(option.get("label", "")).length() > 128 \
			or not _slug_valid(_string_if(option.get("faction_id"))) \
			or not _short_id_valid(_string_if(option.get("window_id")), "pcw1:") \
			or typeof(option.get("region_id")) != TYPE_STRING \
			or String(option.get("region_id", "")).is_empty() \
			or String(option.get("region_id", "")).length() > 256 \
			or _string_if(option.get("required_action")) not in ["aid", "trade", "fortify"] \
			or not _bounded_int(option.get("bound_epoch"), 0, 0) \
			or not _bounded_int(option.get("due_epoch"), 1, 1) \
			or option.get("due_season") != "autumn" \
			or not _bounded_int(option.get("expected_due_capacity_cost"), 2, 3) \
			or not _slug_valid(_string_if(option.get("region_scope"))) \
			or not _receipt_token_valid(_string_if(option.get("region_checkpoint_receipt"))) \
			or not _receipt_token_valid(_string_if(option.get("adapter_receipt"))):
		return false
	var benefit: Dictionary = option["benefit"]
	if not _exact_keys(benefit, ["relief", "commerce", "defense"]):
		return false
	var benefit_total := 0
	for key in ["relief", "commerce", "defense"]:
		if not _bounded_int(benefit.get(key), 0, 3):
			return false
		benefit_total += int(benefit[key])
	if benefit_total != 3:
		return false
	var effect: Dictionary = option["region_effect"]
	var effect_keys := ["before_signals", "access_requested", "access_applied",
		"after_signals"]
	if not _exact_keys(effect, effect_keys) \
			or not (effect.get("before_signals") is Dictionary) \
			or not (effect.get("after_signals") is Dictionary) \
			or not _bounded_int(effect.get("access_requested"), 1, 1) \
			or not _bounded_int(effect.get("access_applied"), 1, 1):
		return false
	var before := _normalize_signals(effect["before_signals"])
	var after := _normalize_signals(effect["after_signals"])
	if before.is_empty() or after.is_empty():
		return false
	var expected_after := before.duplicate(true)
	expected_after["faction_access"] = int(before["faction_access"]) + 1
	return _canonical_json(expected_after) == _canonical_json(after)


static func _adapter_acceptances_self_valid(acceptances: Array,
		campaign_owner_scope: String, global_network_scope: String) -> bool:
	if acceptances.size() != _covenant_specs().size():
		return false
	var previous_window := ""
	var seen_scopes := {}
	for raw_acceptance in acceptances:
		if not (raw_acceptance is Dictionary):
			return false
		var acceptance: Dictionary = raw_acceptance
		var required := ["window_id", "expected_region_scope",
			"accepted_region_checkpoint_receipt", "expected_adapter_receipt"]
		var window_id := _string_if(acceptance.get("window_id"))
		var region_scope := _string_if(acceptance.get("expected_region_scope"))
		if not _exact_keys(acceptance, required) \
				or not _short_id_valid(window_id, "pcw1:") \
				or (previous_window != "" and window_id <= previous_window) \
				or not _slug_valid(region_scope) \
				or region_scope in [campaign_owner_scope, global_network_scope] \
				or seen_scopes.has(region_scope) \
				or not _receipt_token_valid(_string_if(
					acceptance.get("accepted_region_checkpoint_receipt")
				)) \
				or not _receipt_token_valid(_string_if(
					acceptance.get("expected_adapter_receipt")
				)):
			return false
		previous_window = window_id
		seen_scopes[region_scope] = true
	return true


static func _catalog_matches_campaign(catalog: Dictionary,
		campaign_catalog: Dictionary) -> bool:
	return validate_catalog(campaign_catalog, catalog).is_empty()


static func bind_covenant(catalog: Dictionary, before_state: Dictionary,
		accepted_before_state_receipt: String, campaign_catalog: Dictionary,
		campaign_state: Dictionary, accepted_campaign_state_receipt: String,
		campaign_owner_scope: String, adapters: Array, adapter_acceptances: Array,
		global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String, board: Dictionary,
		choice: Dictionary) -> Dictionary:
	var normalized_catalog := normalize_catalog(campaign_catalog, catalog)
	if normalized_catalog.is_empty():
		return {}
	var normalized_state := accept_state_checkpoint(
		normalized_catalog, before_state, accepted_before_state_receipt
	)
	if normalized_state.is_empty() or String(normalized_state["phase"]) != "open":
		return {}
	var expected_board := make_covenant_board(
		normalized_catalog, normalized_state, accepted_before_state_receipt,
		campaign_catalog,
		campaign_state, accepted_campaign_state_receipt, campaign_owner_scope,
		adapters, adapter_acceptances, global_network_scope,
		accepted_global_network_checkpoint_receipt
	)
	if expected_board.is_empty() \
			or _canonical_json(expected_board) != _canonical_json(board) \
			or String(expected_board["decision_status"]) != "covenants_available":
		return {}
	var normalized_choice := normalize_covenant_choice(expected_board, choice)
	if normalized_choice.is_empty():
		return {}
	var normalized_campaign := PlanetCampaignModel.accept_state_checkpoint(
		campaign_catalog, campaign_state, accepted_campaign_state_receipt
	)
	var evidence := _normalize_adapter_set(
		campaign_catalog, adapters, adapter_acceptances, campaign_owner_scope,
		global_network_scope, accepted_global_network_checkpoint_receipt
	)
	var covenant := _catalog_covenant_by_id(
		normalized_catalog, String(normalized_choice["covenant_id"])
	)
	if normalized_campaign.is_empty() or evidence.is_empty() or covenant.is_empty():
		return {}
	var adapter: Dictionary = _adapter_by_window(evidence["adapters"]).get(
		String(covenant["window_id"]), {}
	)
	if adapter.is_empty():
		return {}
	var region_delta := _make_region_delta(
		"bind_access", covenant, adapter, int(covenant["bind_access_delta"])
	)
	if region_delta.is_empty() or int(region_delta["access_applied"]) != 1:
		return {}
	var covenant_record := _make_bind_record(
		normalized_catalog, covenant, normalized_choice, normalized_campaign,
		campaign_owner_scope, global_network_scope,
		accepted_global_network_checkpoint_receipt, adapter, region_delta
	)
	if covenant_record.is_empty():
		return {}
	var after_state := _make_state(
		normalized_catalog, int(normalized_state["revision"]) + 1, "active",
		covenant_record, [], {}, [], String(normalized_state["state_receipt"]),
		String(covenant_record["record_receipt"])
	)
	if after_state.is_empty() \
			or not validate_state(normalized_catalog, after_state).is_empty():
		return {}
	var covenant_delta := _make_covenant_state_delta(
		normalized_state, after_state, "bind", String(covenant["covenant_id"])
	)
	if covenant_delta.is_empty():
		return {}
	var base := {
		"schema": BIND_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(normalized_catalog["catalog_id"]),
		"catalog_receipt": String(normalized_catalog["catalog_receipt"]),
		"owner_order": ["covenant", "faction_region"],
		"accepted_before_state_receipt": accepted_before_state_receipt,
		"accepted_campaign_state_receipt": accepted_campaign_state_receipt,
		"campaign_owner_scope": campaign_owner_scope,
		"campaign_state_receipt": String(normalized_campaign["state_receipt"]),
		"global_network_scope": global_network_scope,
		"accepted_global_network_checkpoint_receipt":
			accepted_global_network_checkpoint_receipt,
		"board_id": String(expected_board["board_id"]),
		"board_receipt": String(expected_board["board_receipt"]),
		"choice_id": String(normalized_choice["choice_id"]),
		"choice_receipt": String(normalized_choice["choice_receipt"]),
		"covenant_delta": covenant_delta,
		"faction_region_delta": region_delta,
		"covenant_record": covenant_record,
		"after_state": after_state,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["proposal_id"] = BIND_ID_PREFIX + digest.substr(0, 16)
	base["proposal_receipt"] = _receipt_for(base)
	return base if String(base["proposal_receipt"]) != "" else {}


static func validate_bind_proposal(catalog: Dictionary, before_state: Dictionary,
		accepted_before_state_receipt: String, campaign_catalog: Dictionary,
		campaign_state: Dictionary, accepted_campaign_state_receipt: String,
		campaign_owner_scope: String, adapters: Array, adapter_acceptances: Array,
		global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String, board: Dictionary,
		choice: Dictionary, value: Variant) -> Array[String]:
	var expected := bind_covenant(
		catalog, before_state, accepted_before_state_receipt, campaign_catalog,
		campaign_state, accepted_campaign_state_receipt, campaign_owner_scope,
		adapters, adapter_acceptances, global_network_scope,
		accepted_global_network_checkpoint_receipt, board, choice
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["bind proposal does not derive from exact covenant and owner anchors"]
	return []


static func normalize_bind_proposal(catalog: Dictionary, before_state: Dictionary,
		accepted_before_state_receipt: String, campaign_catalog: Dictionary,
		campaign_state: Dictionary, accepted_campaign_state_receipt: String,
		campaign_owner_scope: String, adapters: Array, adapter_acceptances: Array,
		global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String, board: Dictionary,
		choice: Dictionary, value: Variant) -> Dictionary:
	var expected := bind_covenant(
		catalog, before_state, accepted_before_state_receipt, campaign_catalog,
		campaign_state, accepted_campaign_state_receipt, campaign_owner_scope,
		adapters, adapter_acceptances, global_network_scope,
		accepted_global_network_checkpoint_receipt, board, choice
	)
	return expected if not expected.is_empty() and value is Dictionary \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func _make_region_delta(action: String, covenant: Dictionary,
		adapter: Dictionary, access_requested: int) -> Dictionary:
	if action not in ["bind_access", "amend_access", "honor_access",
			"withdraw_access"] or access_requested < -2 or access_requested > 1:
		return {}
	var before := _normalize_signals(adapter.get("signals"))
	if before.is_empty():
		return {}
	var access_before := int(before["faction_access"])
	var access_after := clampi(access_before + access_requested, 0, MAX_TRACK)
	var access_applied := access_after - access_before
	var after := before.duplicate(true)
	after["faction_access"] = access_after
	var base := {
		"schema": REGION_DELTA_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"action": action,
		"covenant_id": String(covenant["covenant_id"]),
		"window_id": String(covenant["window_id"]),
		"region_id": String(covenant["region_id"]),
		"region_scope": String(adapter["region_scope"]),
		"before_region_checkpoint_receipt": String(
			adapter["region_checkpoint_receipt"]
		),
		"before_adapter_receipt": String(adapter["adapter_receipt"]),
		"before_signals": before,
		"access_requested": access_requested,
		"access_applied": access_applied,
		"after_signals": after,
	}
	base["delta_receipt"] = _receipt_for(base)
	return base if String(base["delta_receipt"]) != "" else {}


static func _make_bind_record(catalog: Dictionary, covenant: Dictionary,
		choice: Dictionary, campaign_state: Dictionary, campaign_owner_scope: String,
		global_network_scope: String, global_network_checkpoint_receipt: String,
		adapter: Dictionary, region_delta: Dictionary) -> Dictionary:
	var base := {
		"schema": BIND_RECORD_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"covenant_id": String(covenant["covenant_id"]),
		"covenant_receipt": String(covenant["covenant_receipt"]),
		"campaign_owner_scope": campaign_owner_scope,
		"binding_campaign_state_receipt": String(campaign_state["state_receipt"]),
		"binding_replay_key": _receipt_for([
			campaign_owner_scope, String(campaign_state["state_receipt"]), "bind",
		]),
		"bound_epoch": BIND_EPOCH,
		"bound_season": "spring",
		"due_epoch": 1,
		"due_season": "autumn",
		"required_action": String(covenant["required_action"]),
		"faction_id": String(covenant["faction_id"]),
		"window_id": String(covenant["window_id"]),
		"region_id": String(covenant["region_id"]),
		"global_network_scope": global_network_scope,
		"global_network_checkpoint_receipt": global_network_checkpoint_receipt,
		"binding_region_scope": String(adapter["region_scope"]),
		"binding_region_checkpoint_receipt": String(
			adapter["region_checkpoint_receipt"]
		),
		"binding_adapter_receipt": String(adapter["adapter_receipt"]),
		"bind_access_requested": int(region_delta["access_requested"]),
		"bind_access_applied": int(region_delta["access_applied"]),
		"region_delta_receipt": String(region_delta["delta_receipt"]),
		"choice_receipt": String(choice["choice_receipt"]),
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["record_id"] = BIND_RECORD_ID_PREFIX + digest.substr(0, 16)
	base["record_receipt"] = _receipt_for(base)
	return base if String(base["record_receipt"]) != "" else {}


static func _make_covenant_state_delta(before_state: Dictionary,
		after_state: Dictionary, action: String, covenant_id: String) -> Dictionary:
	var base := {
		"before_state_receipt": String(before_state["state_receipt"]),
		"after_state_receipt": String(after_state["state_receipt"]),
		"before_revision": int(before_state["revision"]),
		"after_revision": int(after_state["revision"]),
		"before_phase": String(before_state["phase"]),
		"after_phase": String(after_state["phase"]),
		"action": action,
		"covenant_id": covenant_id,
	}
	base["delta_receipt"] = _receipt_for(base)
	return base if String(base["delta_receipt"]) != "" else {}


static func project_obligation(catalog: Dictionary, state: Dictionary,
		accepted_state_receipt: String, campaign_catalog: Dictionary,
		campaign_state: Dictionary, accepted_campaign_state_receipt: String,
		campaign_owner_scope: String) -> Dictionary:
	var normalized_catalog := normalize_catalog(campaign_catalog, catalog)
	if normalized_catalog.is_empty() or not _slug_valid(campaign_owner_scope):
		return {}
	var normalized_state := accept_state_checkpoint(
		normalized_catalog, state, accepted_state_receipt
	)
	var normalized_campaign := PlanetCampaignModel.accept_state_checkpoint(
		campaign_catalog, campaign_state, accepted_campaign_state_receipt
	)
	if normalized_state.is_empty() or normalized_campaign.is_empty():
		return {}
	if String(normalized_state["phase"]) != "open" \
			and String((normalized_state["covenant_record"] as Dictionary).get(
				"campaign_owner_scope", ""
			)) != campaign_owner_scope:
		return {}
	var covenant_id := ""
	var required_action := ""
	var due_epoch := -1
	var due_season := ""
	var timing_status := "unbound"
	var matched_record := {}
	var available_actions: Array[String] = []
	var amendments_used := 0
	if String(normalized_state["phase"]) == "terminal":
		var terminal_record: Dictionary = normalized_state["covenant_record"]
		covenant_id = String(terminal_record["covenant_id"])
		required_action = String(terminal_record["required_action"])
		amendments_used = (normalized_state["amendment_records"] as Array).size()
		due_epoch = _effective_due_epoch(
			terminal_record, normalized_state["amendment_records"]
		)
		due_season = _season_for_epoch(due_epoch)
		timing_status = "settled"
	elif String(normalized_state["phase"]) == "active":
		var covenant_record: Dictionary = normalized_state["covenant_record"]
		covenant_id = String(covenant_record["covenant_id"])
		required_action = String(covenant_record["required_action"])
		amendments_used = (normalized_state["amendment_records"] as Array).size()
		due_epoch = _effective_due_epoch(
			covenant_record, normalized_state["amendment_records"]
		)
		due_season = _season_for_epoch(due_epoch)
		var due_evidence := _due_directive_evidence(
			normalized_catalog, normalized_state, normalized_campaign
		)
		if due_evidence.is_empty():
			return {}
		if String(due_evidence["status"]) == "matched":
			matched_record = (due_evidence["record"] as Dictionary).duplicate(true)
		var campaign_epoch := int(normalized_campaign["epoch_index"])
		if campaign_epoch < due_epoch:
			timing_status = "not_due"
		elif campaign_epoch == due_epoch:
			timing_status = "due"
		else:
			timing_status = "overdue"
		if campaign_epoch >= due_epoch:
			if matched_record.is_empty():
				available_actions.append("withdraw")
				if campaign_epoch == due_epoch \
						and String(normalized_campaign["phase"]) == "open" \
						and amendments_used == 0 \
						and due_epoch + 1 <= LAST_DECISION_EPOCH:
					available_actions.append("amend")
			else:
				available_actions.append("honor")
	available_actions.sort()
	var base := {
		"schema": PROJECTION_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(normalized_catalog["catalog_id"]),
		"catalog_receipt": String(normalized_catalog["catalog_receipt"]),
		"state_receipt": String(normalized_state["state_receipt"]),
		"accepted_state_receipt": accepted_state_receipt,
		"revision": int(normalized_state["revision"]),
		"state_phase": String(normalized_state["phase"]),
		"covenant_id": covenant_id,
		"required_action": required_action,
		"amendments_used": amendments_used,
		"campaign_catalog_id": String(campaign_catalog["catalog_id"]),
		"campaign_catalog_receipt": String(campaign_catalog["catalog_receipt"]),
		"campaign_owner_scope": campaign_owner_scope,
		"campaign_state_receipt": String(normalized_campaign["state_receipt"]),
		"accepted_campaign_state_receipt": accepted_campaign_state_receipt,
		"campaign_epoch": int(normalized_campaign["epoch_index"]),
		"campaign_season": String(normalized_campaign["season"]),
		"campaign_phase": String(normalized_campaign["phase"]),
		"effective_due_epoch": due_epoch,
		"effective_due_season": due_season,
		"timing_status": timing_status,
		"matched_directive_record_id": String(matched_record.get("record_id", "")),
		"matched_directive_record_receipt": String(
			matched_record.get("record_receipt", "")
		),
		"available_actions": available_actions,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["projection_id"] = PROJECTION_ID_PREFIX + digest.substr(0, 16)
	base["projection_receipt"] = _receipt_for(base)
	return base if String(base["projection_receipt"]) != "" else {}


static func validate_obligation_projection(catalog: Dictionary, state: Dictionary,
		accepted_state_receipt: String, campaign_catalog: Dictionary,
		campaign_state: Dictionary, accepted_campaign_state_receipt: String,
		campaign_owner_scope: String, value: Variant) -> Array[String]:
	var expected := project_obligation(
		catalog, state, accepted_state_receipt, campaign_catalog, campaign_state,
		accepted_campaign_state_receipt, campaign_owner_scope
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["obligation projection does not derive from accepted owner checkpoints"]
	return []


static func normalize_obligation_projection(catalog: Dictionary,
		state: Dictionary, accepted_state_receipt: String,
		campaign_catalog: Dictionary, campaign_state: Dictionary,
		accepted_campaign_state_receipt: String, campaign_owner_scope: String,
		value: Variant) -> Dictionary:
	var expected := project_obligation(
		catalog, state, accepted_state_receipt, campaign_catalog, campaign_state,
		accepted_campaign_state_receipt, campaign_owner_scope
	)
	return expected if not expected.is_empty() and value is Dictionary \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func _due_directive_evidence(catalog: Dictionary,
		covenant_state: Dictionary, campaign_state: Dictionary) -> Dictionary:
	if String(covenant_state.get("phase", "")) != "active":
		return {}
	var covenant_record: Dictionary = covenant_state["covenant_record"]
	var covenant := _catalog_covenant_by_id(
		catalog, String(covenant_record["covenant_id"])
	)
	if covenant.is_empty():
		return {}
	var due_epoch := _effective_due_epoch(
		covenant_record, covenant_state["amendment_records"]
	)
	var semantic_matches: Array[Dictionary] = []
	for raw_record in campaign_state.get("directive_records", []):
		if not (raw_record is Dictionary):
			return {}
		var record: Dictionary = raw_record
		if int(record.get("epoch_index", -1)) == due_epoch \
				and String(record.get("directive_id", "")) \
				== String(covenant["directive_id"]) \
				and String(record.get("directive_receipt", "")) \
				== String(covenant["directive_receipt"]) \
				and String(record.get("action", "")) \
				== String(covenant["required_action"]) \
				and String(record.get("origin_window_id", "")) \
				== String(covenant["window_id"]) \
				and String(record.get("origin_region_id", "")) \
				== String(covenant["region_id"]) \
				and String(record.get("faction_id", "")) \
				== String(covenant["faction_id"]):
			semantic_matches.append(record.duplicate(true))
	if semantic_matches.is_empty():
		return {"status": "none", "record": {}}
	if semantic_matches.size() != 1:
		return {"status": "conflict", "record": {}}
	var matched: Dictionary = semantic_matches[0]
	if String(matched.get("origin_region_scope", "")) \
			!= String(covenant_record["binding_region_scope"]) \
			or String(matched.get("global_network_scope", "")) \
			!= String(covenant_record["global_network_scope"]) \
			or not _directive_fresh_after_covenant(covenant_state, matched):
		return {"status": "conflict", "record": {}}
	return {"status": "matched", "record": matched}


static func _directive_fresh_after_covenant(covenant_state: Dictionary,
		directive_record: Dictionary) -> bool:
	var covenant_record: Dictionary = covenant_state["covenant_record"]
	var previous_checkpoint := String(covenant_record[
		"binding_region_checkpoint_receipt"
	])
	var previous_adapter := String(covenant_record["binding_adapter_receipt"])
	var amendments: Array = covenant_state["amendment_records"]
	if not amendments.is_empty():
		previous_checkpoint = String((amendments[0] as Dictionary)[
			"region_checkpoint_receipt"
		])
		previous_adapter = String((amendments[0] as Dictionary)["adapter_receipt"])
	return String(directive_record.get("origin_region_checkpoint_receipt", "")) \
		!= previous_checkpoint and String(directive_record.get(
			"origin_adapter_receipt", ""
		)) != previous_adapter


static func _season_for_epoch(epoch_index: int) -> String:
	match epoch_index:
		0:
			return "spring"
		1:
			return "autumn"
		2:
			return "winter"
	return "terminal" if epoch_index == TERMINAL_EPOCH else ""


static func amend_covenant(catalog: Dictionary, before_state: Dictionary,
		accepted_before_state_receipt: String, campaign_catalog: Dictionary,
		campaign_state: Dictionary, accepted_campaign_state_receipt: String,
		campaign_owner_scope: String, region_adapter: Dictionary,
		region_acceptance: Dictionary, global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String) -> Dictionary:
	var normalized_catalog := normalize_catalog(campaign_catalog, catalog)
	if normalized_catalog.is_empty() \
			or not _slug_valid(campaign_owner_scope) \
			or not _slug_valid(global_network_scope) \
			or campaign_owner_scope == global_network_scope \
			or not _receipt_token_valid(
				accepted_global_network_checkpoint_receipt
			):
		return {}
	var normalized_state := accept_state_checkpoint(
		normalized_catalog, before_state, accepted_before_state_receipt
	)
	var normalized_campaign := PlanetCampaignModel.accept_state_checkpoint(
		campaign_catalog, campaign_state, accepted_campaign_state_receipt
	)
	if normalized_state.is_empty() or normalized_campaign.is_empty() \
			or String(normalized_state["phase"]) != "active" \
			or not (normalized_state["amendment_records"] as Array).is_empty():
		return {}
	var projection := project_obligation(
		normalized_catalog, normalized_state, accepted_before_state_receipt,
		campaign_catalog,
		normalized_campaign, accepted_campaign_state_receipt, campaign_owner_scope
	)
	if projection.is_empty() or "amend" not in projection["available_actions"]:
		return {}
	var covenant_record: Dictionary = normalized_state["covenant_record"]
	var covenant := _catalog_covenant_by_id(
		normalized_catalog, String(covenant_record["covenant_id"])
	)
	var normalized_adapter := _normalize_one_adapter(
		campaign_catalog, region_adapter, region_acceptance, campaign_owner_scope,
		global_network_scope, accepted_global_network_checkpoint_receipt
	)
	if covenant.is_empty() or normalized_adapter.is_empty() \
			or String(global_network_scope) \
			!= String(covenant_record["global_network_scope"]) \
			or String(normalized_adapter["window_id"]) != String(covenant["window_id"]) \
			or String(normalized_adapter["region_id"]) != String(covenant["region_id"]) \
			or String(normalized_adapter["region_scope"]) \
			!= String(covenant_record["binding_region_scope"]):
		return {}
	var region_delta := _make_region_delta(
		"amend_access", covenant, normalized_adapter,
		int(covenant["amend_access_delta"])
	)
	if region_delta.is_empty() or int(region_delta["access_applied"]) != -1:
		return {}
	var amendment_record := _make_amendment_record(
		normalized_catalog, covenant_record, normalized_campaign,
		global_network_scope,
		accepted_global_network_checkpoint_receipt, normalized_adapter, region_delta
	)
	if amendment_record.is_empty():
		return {}
	var amendments: Array[Dictionary] = [amendment_record]
	var after_state := _make_state(
		normalized_catalog, int(normalized_state["revision"]) + 1, "active",
		covenant_record, amendments, {}, [], String(normalized_state["state_receipt"]),
		String(amendment_record["record_receipt"])
	)
	if after_state.is_empty() \
			or not validate_state(normalized_catalog, after_state).is_empty():
		return {}
	var covenant_delta := _make_covenant_state_delta(
		normalized_state, after_state, "amend", String(covenant["covenant_id"])
	)
	if covenant_delta.is_empty():
		return {}
	var base := {
		"schema": AMEND_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(normalized_catalog["catalog_id"]),
		"catalog_receipt": String(normalized_catalog["catalog_receipt"]),
		"owner_order": ["covenant", "faction_region"],
		"accepted_before_state_receipt": accepted_before_state_receipt,
		"accepted_campaign_state_receipt": accepted_campaign_state_receipt,
		"campaign_owner_scope": campaign_owner_scope,
		"campaign_state_receipt": String(normalized_campaign["state_receipt"]),
		"global_network_scope": global_network_scope,
		"accepted_global_network_checkpoint_receipt":
			accepted_global_network_checkpoint_receipt,
		"projection_id": String(projection["projection_id"]),
		"projection_receipt": String(projection["projection_receipt"]),
		"covenant_delta": covenant_delta,
		"faction_region_delta": region_delta,
		"amendment_record": amendment_record,
		"after_state": after_state,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["proposal_id"] = AMEND_ID_PREFIX + digest.substr(0, 16)
	base["proposal_receipt"] = _receipt_for(base)
	return base if String(base["proposal_receipt"]) != "" else {}


static func validate_amend_proposal(catalog: Dictionary,
		before_state: Dictionary, accepted_before_state_receipt: String,
		campaign_catalog: Dictionary, campaign_state: Dictionary,
		accepted_campaign_state_receipt: String, campaign_owner_scope: String,
		region_adapter: Dictionary, region_acceptance: Dictionary,
		global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String,
		value: Variant) -> Array[String]:
	var expected := amend_covenant(
		catalog, before_state, accepted_before_state_receipt, campaign_catalog,
		campaign_state, accepted_campaign_state_receipt, campaign_owner_scope,
		region_adapter, region_acceptance, global_network_scope,
		accepted_global_network_checkpoint_receipt
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["amend proposal does not derive from exact covenant and owner anchors"]
	return []


static func normalize_amend_proposal(catalog: Dictionary,
		before_state: Dictionary, accepted_before_state_receipt: String,
		campaign_catalog: Dictionary, campaign_state: Dictionary,
		accepted_campaign_state_receipt: String, campaign_owner_scope: String,
		region_adapter: Dictionary, region_acceptance: Dictionary,
		global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String, value: Variant) -> Dictionary:
	var expected := amend_covenant(
		catalog, before_state, accepted_before_state_receipt, campaign_catalog,
		campaign_state, accepted_campaign_state_receipt, campaign_owner_scope,
		region_adapter, region_acceptance, global_network_scope,
		accepted_global_network_checkpoint_receipt
	)
	return expected if not expected.is_empty() and value is Dictionary \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func _make_amendment_record(catalog: Dictionary,
		covenant_record: Dictionary, campaign_state: Dictionary,
		global_network_scope: String, global_network_checkpoint_receipt: String,
		adapter: Dictionary, region_delta: Dictionary) -> Dictionary:
	var base := {
		"schema": AMEND_RECORD_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"covenant_id": String(covenant_record["covenant_id"]),
		"covenant_record_id": String(covenant_record["record_id"]),
		"covenant_record_receipt": String(covenant_record["record_receipt"]),
		"campaign_owner_scope": String(covenant_record["campaign_owner_scope"]),
		"campaign_state_receipt": String(campaign_state["state_receipt"]),
		"amended_epoch": 1,
		"old_due_epoch": 1,
		"new_due_epoch": 2,
		"new_due_season": "winter",
		"global_network_scope": global_network_scope,
		"global_network_checkpoint_receipt": global_network_checkpoint_receipt,
		"region_scope": String(adapter["region_scope"]),
		"region_checkpoint_receipt": String(adapter["region_checkpoint_receipt"]),
		"adapter_receipt": String(adapter["adapter_receipt"]),
		"access_requested": int(region_delta["access_requested"]),
		"access_applied": int(region_delta["access_applied"]),
		"region_delta_receipt": String(region_delta["delta_receipt"]),
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["record_id"] = AMEND_RECORD_ID_PREFIX + digest.substr(0, 16)
	base["record_receipt"] = _receipt_for(base)
	return base if String(base["record_receipt"]) != "" else {}


static func resolve_covenant(catalog: Dictionary, before_state: Dictionary,
		accepted_before_state_receipt: String, campaign_catalog: Dictionary,
		campaign_state: Dictionary, accepted_campaign_state_receipt: String,
		campaign_owner_scope: String, region_adapter: Dictionary,
		region_acceptance: Dictionary, global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String,
		resolution: String) -> Dictionary:
	var normalized_catalog := normalize_catalog(campaign_catalog, catalog)
	if resolution not in ["honor", "withdraw"] \
			or normalized_catalog.is_empty() \
			or not _slug_valid(campaign_owner_scope) \
			or not _slug_valid(global_network_scope) \
			or campaign_owner_scope == global_network_scope \
			or not _receipt_token_valid(
				accepted_global_network_checkpoint_receipt
			):
		return {}
	var normalized_state := accept_state_checkpoint(
		normalized_catalog, before_state, accepted_before_state_receipt
	)
	var normalized_campaign := PlanetCampaignModel.accept_state_checkpoint(
		campaign_catalog, campaign_state, accepted_campaign_state_receipt
	)
	if normalized_state.is_empty() or normalized_campaign.is_empty() \
			or String(normalized_state["phase"]) != "active":
		return {}
	var projection := project_obligation(
		normalized_catalog, normalized_state, accepted_before_state_receipt,
		campaign_catalog,
		normalized_campaign, accepted_campaign_state_receipt, campaign_owner_scope
	)
	if projection.is_empty() or resolution not in projection["available_actions"]:
		return {}
	var covenant_record: Dictionary = normalized_state["covenant_record"]
	var covenant := _catalog_covenant_by_id(
		normalized_catalog, String(covenant_record["covenant_id"])
	)
	var normalized_adapter := _normalize_one_adapter(
		campaign_catalog, region_adapter, region_acceptance, campaign_owner_scope,
		global_network_scope, accepted_global_network_checkpoint_receipt
	)
	if covenant.is_empty() or normalized_adapter.is_empty() \
			or global_network_scope != String(covenant_record["global_network_scope"]) \
			or String(normalized_adapter["window_id"]) != String(covenant["window_id"]) \
			or String(normalized_adapter["region_id"]) != String(covenant["region_id"]) \
			or String(normalized_adapter["region_scope"]) \
			!= String(covenant_record["binding_region_scope"]):
		return {}
	var requested := int(covenant["honor_access_delta"]) \
		if resolution == "honor" else int(covenant["withdraw_access_delta"])
	var region_delta := _make_region_delta(
		"honor_access" if resolution == "honor" else "withdraw_access",
		covenant, normalized_adapter, requested
	)
	if region_delta.is_empty():
		return {}
	var due_evidence := _due_directive_evidence(
		normalized_catalog, normalized_state, normalized_campaign
	)
	if due_evidence.is_empty():
		return {}
	var matched_record: Dictionary = {}
	if String(due_evidence["status"]) == "matched":
		matched_record = (due_evidence["record"] as Dictionary).duplicate(true)
	if (resolution == "honor") != not matched_record.is_empty():
		return {}
	if resolution == "honor" \
			and (String(normalized_adapter["region_checkpoint_receipt"]) \
			== String(matched_record["origin_region_checkpoint_receipt"]) \
			or String(normalized_adapter["adapter_receipt"]) \
			== String(matched_record["origin_adapter_receipt"])):
		return {}
	var resolution_record := _make_resolution_record(
		normalized_catalog, normalized_state, normalized_campaign, matched_record,
		resolution,
		global_network_scope, accepted_global_network_checkpoint_receipt,
		normalized_adapter, region_delta
	)
	if resolution_record.is_empty():
		return {}
	var consumed_keys: Array[String] = []
	if resolution == "honor":
		consumed_keys.append(String(
			resolution_record["campaign_action_replay_key"]
		))
	var after_state := _make_state(
		normalized_catalog, int(normalized_state["revision"]) + 1, "terminal",
		covenant_record, normalized_state["amendment_records"], resolution_record,
		consumed_keys, String(normalized_state["state_receipt"]),
		String(resolution_record["record_receipt"])
	)
	if after_state.is_empty() \
			or not validate_state(normalized_catalog, after_state).is_empty():
		return {}
	var covenant_delta := _make_covenant_state_delta(
		normalized_state, after_state, resolution, String(covenant["covenant_id"])
	)
	if covenant_delta.is_empty():
		return {}
	var base := {
		"schema": RESOLUTION_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(normalized_catalog["catalog_id"]),
		"catalog_receipt": String(normalized_catalog["catalog_receipt"]),
		"owner_order": ["covenant", "faction_region"],
		"resolution": resolution,
		"accepted_before_state_receipt": accepted_before_state_receipt,
		"accepted_campaign_state_receipt": accepted_campaign_state_receipt,
		"campaign_owner_scope": campaign_owner_scope,
		"campaign_state_receipt": String(normalized_campaign["state_receipt"]),
		"global_network_scope": global_network_scope,
		"accepted_global_network_checkpoint_receipt":
			accepted_global_network_checkpoint_receipt,
		"projection_id": String(projection["projection_id"]),
		"projection_receipt": String(projection["projection_receipt"]),
		"covenant_delta": covenant_delta,
		"faction_region_delta": region_delta,
		"resolution_record": resolution_record,
		"after_state": after_state,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["proposal_id"] = RESOLUTION_ID_PREFIX + digest.substr(0, 16)
	base["proposal_receipt"] = _receipt_for(base)
	return base if String(base["proposal_receipt"]) != "" else {}


static func validate_resolution_proposal(catalog: Dictionary,
		before_state: Dictionary, accepted_before_state_receipt: String,
		campaign_catalog: Dictionary, campaign_state: Dictionary,
		accepted_campaign_state_receipt: String, campaign_owner_scope: String,
		region_adapter: Dictionary, region_acceptance: Dictionary,
		global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String, resolution: String,
		value: Variant) -> Array[String]:
	var expected := resolve_covenant(
		catalog, before_state, accepted_before_state_receipt, campaign_catalog,
		campaign_state, accepted_campaign_state_receipt, campaign_owner_scope,
		region_adapter, region_acceptance, global_network_scope,
		accepted_global_network_checkpoint_receipt, resolution
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["resolution proposal does not derive from exact covenant and owner anchors"]
	return []


static func normalize_resolution_proposal(catalog: Dictionary,
		before_state: Dictionary, accepted_before_state_receipt: String,
		campaign_catalog: Dictionary, campaign_state: Dictionary,
		accepted_campaign_state_receipt: String, campaign_owner_scope: String,
		region_adapter: Dictionary, region_acceptance: Dictionary,
		global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String, resolution: String,
		value: Variant) -> Dictionary:
	var expected := resolve_covenant(
		catalog, before_state, accepted_before_state_receipt, campaign_catalog,
		campaign_state, accepted_campaign_state_receipt, campaign_owner_scope,
		region_adapter, region_acceptance, global_network_scope,
		accepted_global_network_checkpoint_receipt, resolution
	)
	return expected if not expected.is_empty() and value is Dictionary \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func _make_resolution_record(catalog: Dictionary,
		covenant_state: Dictionary, campaign_state: Dictionary,
		directive_record: Dictionary, resolution: String,
		global_network_scope: String, global_network_checkpoint_receipt: String,
		adapter: Dictionary, region_delta: Dictionary) -> Dictionary:
	var covenant_record: Dictionary = covenant_state["covenant_record"]
	var amendments: Array = covenant_state["amendment_records"]
	var honored := resolution == "honor"
	var directive_receipt := String(directive_record.get("record_receipt", ""))
	var replay_key := _receipt_for([
		String(covenant_record["campaign_owner_scope"]), directive_receipt,
	]) if honored else ""
	var base := {
		"schema": RESOLUTION_RECORD_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"covenant_id": String(covenant_record["covenant_id"]),
		"covenant_record_id": String(covenant_record["record_id"]),
		"covenant_record_receipt": String(covenant_record["record_receipt"]),
		"resolution": "honored" if honored else "withdrawn",
		"resolved_epoch": int(campaign_state["epoch_index"]),
		"due_epoch": _effective_due_epoch(covenant_record, amendments),
		"campaign_owner_scope": String(covenant_record["campaign_owner_scope"]),
		"campaign_state_receipt": String(campaign_state["state_receipt"]),
		"directive_record_id": String(directive_record.get("record_id", "")),
		"directive_record_receipt": directive_receipt,
		"campaign_action_replay_key": replay_key,
		"global_network_scope": global_network_scope,
		"global_network_checkpoint_receipt": global_network_checkpoint_receipt,
		"region_scope": String(adapter["region_scope"]),
		"region_checkpoint_receipt": String(adapter["region_checkpoint_receipt"]),
		"adapter_receipt": String(adapter["adapter_receipt"]),
		"access_requested": int(region_delta["access_requested"]),
		"access_applied": int(region_delta["access_applied"]),
		"region_delta_status": "applied" \
			if int(region_delta["access_applied"]) != 0 else "superseded",
		"region_delta_receipt": String(region_delta["delta_receipt"]),
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["record_id"] = RESOLUTION_RECORD_ID_PREFIX + digest.substr(0, 16)
	base["record_receipt"] = _receipt_for(base)
	return base if String(base["record_receipt"]) != "" else {}
