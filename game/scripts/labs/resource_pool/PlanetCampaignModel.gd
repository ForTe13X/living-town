extends RefCounted

## RP-0007: owner-independent, abstract planet campaign directives.
##
## A directive is an abstract allocation, not a physical-operation claim.
## Stage one returns a pure three-owner proposal (campaign + command owner + selected
## origin-region adapter). Stage two can later return a pure campaign + fresh
## target-region proposal for the authored cross-region consequence. The shared
## RP-0006 checkpoint is a read-only, whole-window precondition and is never
## sliced into per-region authority here.

const ScaleAddress = preload("res://scripts/labs/resource_pool/ScaleAddress.gd")

const CATALOG_SCHEMA := "living-town.planet-campaign-catalog/v1"
const STATE_SCHEMA := "living-town.planet-campaign-state/v1"
const ADAPTER_SCHEMA := "living-town.planet-window-adapter/v1"
const COMMAND_SCHEMA := "living-town.planet-command-anchor/v1"
const BOARD_SCHEMA := "living-town.planet-directive-board/v1"
const CHOICE_SCHEMA := "living-town.planet-directive-choice/v1"
const EPOCH_RECORD_SCHEMA := "living-town.planet-epoch-record/v1"
const DIRECTIVE_RECORD_SCHEMA := "living-town.planet-directive-record/v1"
const CONSEQUENCE_SCHEMA := "living-town.planet-consequence-record/v1"
const DELIVERY_RECORD_SCHEMA := "living-town.planet-delivery-record/v1"
const COMMIT_SCHEMA := "living-town.planet-directive-commit-proposal/v1"
const ADVANCE_SCHEMA := "living-town.planet-epoch-advance/v1"
const PROJECTION_SCHEMA := "living-town.planet-consequence-projection/v1"
const DELIVERY_SCHEMA := "living-town.planet-consequence-delivery-proposal/v1"

const TERMS_REVISION := "ashfall-planet-directive-v1"
const DEFAULT_ROOT_SEED := 260814
const PLANET_KEY := "ashfall"
const SEASONS := ["spring", "autumn", "winter"]
const PHASES := ["open", "committed", "terminal"]
const TERMINAL_EPOCH := 3
const MAX_TRANSITIONS := 9
const MAX_TRACK := 3
const MAX_CAPACITY_UNITS := 6
const MAX_COMMAND_SLOTS := 1
const MAX_SAFE_JSON_INT := 9007199254740991

const CATALOG_ID_PREFIX := "pcc1:"
const WINDOW_ID_PREFIX := "pcw1:"
const DIRECTIVE_ID_PREFIX := "pcd1:"
const ADAPTER_ID_PREFIX := "pca1:"
const COMMAND_ID_PREFIX := "pcm1:"
const BOARD_ID_PREFIX := "pcb1:"
const CHOICE_ID_PREFIX := "pck1:"
const EPOCH_RECORD_ID_PREFIX := "pce1:"
const DIRECTIVE_RECORD_ID_PREFIX := "pcr1:"
const CONSEQUENCE_ID_PREFIX := "pcq1:"
const DELIVERY_RECORD_ID_PREFIX := "pcv1:"
const COMMIT_ID_PREFIX := "pct1:"
const ADVANCE_ID_PREFIX := "pcn1:"
const PROJECTION_ID_PREFIX := "pcp1:"
const DELIVERY_ID_PREFIX := "pcy1:"


## Authored faces are stable atlas slots only. No adjacency, distance, globe
## projection, or RP-0003 route is inferred between them.
static func _window_specs() -> Array[Dictionary]:
	return [
		{
			"window_key": "basin_relief", "face": 0, "region": [0, 0],
			"label": "BASIN RELIEF", "faction_id": "basin_compact",
			"action": "aid", "primary_track": "need_pressure",
			"favored_season": "spring", "benefit": {"relief": 3, "commerce": 0, "defense": 0},
			"target_key": "meridian_trade", "target_track": "logistics_pressure",
			"consequence_kind": "relief_corridor",
		},
		{
			"window_key": "meridian_trade", "face": 2, "region": [0, 0],
			"label": "MERIDIAN TRADE", "faction_id": "meridian_exchange",
			"action": "trade", "primary_track": "logistics_pressure",
			"favored_season": "autumn", "benefit": {"relief": 0, "commerce": 3, "defense": 0},
			"target_key": "nightward_fortify", "target_track": "logistics_pressure",
			"consequence_kind": "exchange_backflow",
		},
		{
			"window_key": "nightward_fortify", "face": 5, "region": [0, 0],
			"label": "NIGHTWARD FORTIFY", "faction_id": "nightward_watch",
			"action": "fortify", "primary_track": "security_pressure",
			"favored_season": "winter", "benefit": {"relief": 0, "commerce": 0, "defense": 3},
			"target_key": "basin_relief", "target_track": "security_pressure",
			"consequence_kind": "watch_shelter",
		},
	]


static func make_catalog(root_seed: int = DEFAULT_ROOT_SEED) -> Dictionary:
	var planet_address := ScaleAddress.planet_address(PLANET_KEY)
	var planet_id := ScaleAddress.canonical_id(planet_address)
	if planet_id == "":
		return {}
	var windows: Array[Dictionary] = []
	var window_by_key := {}
	var ids_seen := {}
	for spec in _window_specs():
		var coords: Array = spec["region"]
		var address := ScaleAddress.region_address(
			PLANET_KEY, int(spec["face"]), Vector2i(int(coords[0]), int(coords[1]))
		)
		var region_id := ScaleAddress.canonical_id(address)
		var parent_id := ScaleAddress.canonical_id(ScaleAddress.parent(address))
		var seed_receipt := ScaleAddress.receipt(
			root_seed, address, "planet-campaign-window-%s" % TERMS_REVISION
		)
		if region_id == "" or parent_id != planet_id or seed_receipt.is_empty():
			return {}
		var digest := _sha256_hex(_canonical_json([
			TERMS_REVISION, "window", region_id, String(spec["window_key"]), seed_receipt,
		]))
		if digest == "":
			return {}
		var window := {
			"window_id": WINDOW_ID_PREFIX + digest.substr(0, 16),
			"window_key": String(spec["window_key"]),
			"label": String(spec["label"]),
			"region_id": region_id,
			"faction_id": String(spec["faction_id"]),
			"seed_receipt": seed_receipt,
		}
		if ids_seen.has(String(window["window_id"])) or window_by_key.has(String(spec["window_key"])):
			return {}
		ids_seen[String(window["window_id"])] = true
		window_by_key[String(spec["window_key"])] = window
		windows.append(window)
	windows.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["window_id"]) < String(right["window_id"]))
	var directives: Array[Dictionary] = []
	var directive_ids_seen := {}
	for spec in _window_specs():
		var origin: Dictionary = window_by_key[String(spec["window_key"])]
		var target: Dictionary = window_by_key[String(spec["target_key"])]
		var base := {
			"directive_key": String(spec["window_key"]),
			"action": String(spec["action"]),
			"origin_window_id": String(origin["window_id"]),
			"origin_region_id": String(origin["region_id"]),
			"target_window_id": String(target["window_id"]),
			"target_region_id": String(target["region_id"]),
			"faction_id": String(origin["faction_id"]),
			"favored_season": String(spec["favored_season"]),
			"favored_capacity_cost": 2,
			"offseason_capacity_cost": 3,
			"primary_track": String(spec["primary_track"]),
			"benefit": (spec["benefit"] as Dictionary).duplicate(true),
			"consequence_kind": String(spec["consequence_kind"]),
			"consequence_track": String(spec["target_track"]),
			"consequence_delta": -1,
			"consequence_delay_epochs": 1,
		}
		var digest := _sha256_hex(_canonical_json([TERMS_REVISION, "directive", base]))
		if digest == "":
			return {}
		var directive := base.duplicate(true)
		directive["directive_id"] = DIRECTIVE_ID_PREFIX + digest.substr(0, 16)
		directive["directive_receipt"] = _receipt_for({
			"terms_revision": TERMS_REVISION, "directive": base,
		})
		if String(directive["directive_receipt"]) == "" \
				or directive_ids_seen.has(String(directive["directive_id"])):
			return {}
		directive_ids_seen[String(directive["directive_id"])] = true
		directives.append(directive)
	directives.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["directive_id"]) < String(right["directive_id"]))
	var authority := {
		"schema": CATALOG_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"root_seed": "i64:%d" % root_seed,
		"planet_id": planet_id,
		"season_order": SEASONS.duplicate(),
		"terminal_epoch": TERMINAL_EPOCH,
		"windows": windows,
		"directives": directives,
	}
	var digest := _sha256_hex(_canonical_json(authority))
	if digest == "":
		return {}
	var result := authority.duplicate(true)
	result["catalog_id"] = CATALOG_ID_PREFIX + digest.substr(0, 16)
	result["catalog_receipt"] = "sha256:" + digest
	return result


static func validate_catalog(value: Variant) -> Array[String]:
	if not (value is Dictionary):
		return ["planet campaign catalog must be a Dictionary"]
	var data: Dictionary = value
	var required := ["schema", "terms_revision", "root_seed", "planet_id", "season_order",
		"terminal_epoch", "windows", "directives", "catalog_id", "catalog_receipt"]
	if not _exact_keys(data, required) or not (data.get("season_order") is Array) \
			or not (data.get("windows") is Array) or not (data.get("directives") is Array):
		return ["planet campaign catalog fields must match V1 exactly"]
	var seed_values := _root_seed_from_token(_string_if(data.get("root_seed")))
	if seed_values.is_empty():
		return ["planet campaign root seed must be canonical i64"]
	var expected := make_catalog(int(seed_values[0]))
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(data):
		return ["planet campaign catalog does not match deterministic terms"]
	return []


static func normalize_catalog(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var seed_values := _root_seed_from_token(_string_if((value as Dictionary).get("root_seed")))
	if seed_values.is_empty():
		return {}
	var expected := make_catalog(int(seed_values[0]))
	return expected if not expected.is_empty() \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func make_initial_state(catalog: Dictionary) -> Dictionary:
	if not _catalog_self_valid(catalog):
		return {}
	return _make_state(catalog, 0, 0, "open", [], [], [], [], [], [], "", "")


static func validate_state(catalog: Dictionary, value: Variant) -> Array[String]:
	if not _catalog_self_valid(catalog):
		return ["planet campaign state requires a valid catalog"]
	if not (value is Dictionary):
		return ["planet campaign state must be a Dictionary"]
	var data: Dictionary = value
	var required := ["schema", "terms_revision", "catalog_id", "catalog_receipt",
		"revision", "epoch_index", "season", "phase", "epoch_records",
		"directive_records", "consumed_commitment_keys", "consequence_records",
		"delivery_records", "delivered_consequence_ids", "parent_state_receipt",
		"last_action_receipt", "state_receipt"]
	if not _exact_keys(data, required):
		return ["planet campaign state fields must match V1 exactly"]
	for key in ["epoch_records", "directive_records", "consumed_commitment_keys",
			"consequence_records", "delivery_records", "delivered_consequence_ids"]:
		if not (data.get(key) is Array):
			return ["planet campaign state ledgers must be Arrays"]
	if data.get("schema") != STATE_SCHEMA or data.get("terms_revision") != TERMS_REVISION \
			or data.get("catalog_id") != catalog.get("catalog_id") \
			or data.get("catalog_receipt") != catalog.get("catalog_receipt"):
		return ["planet campaign state catalog identity mismatch"]
	if not _bounded_int(data.get("revision"), 0, MAX_TRANSITIONS) \
			or not _bounded_int(data.get("epoch_index"), 0, TERMINAL_EPOCH):
		return ["planet campaign revision or epoch is out of range"]
	var revision := int(data["revision"])
	var epoch_index := int(data["epoch_index"])
	var phase := _string_if(data.get("phase"))
	if phase not in PHASES or String(data.get("season", "")) != _season_for(epoch_index, phase):
		return ["planet campaign phase or derived season is invalid"]
	if phase == "terminal" and epoch_index != TERMINAL_EPOCH:
		return ["planet campaign terminal phase requires terminal epoch"]
	if phase != "terminal" and epoch_index >= TERMINAL_EPOCH:
		return ["planet campaign decision phase cannot exist at terminal epoch"]
	var epoch_records: Array = data["epoch_records"]
	var directive_records: Array = data["directive_records"]
	var consequence_records: Array = data["consequence_records"]
	var delivery_records: Array = data["delivery_records"]
	if not _epoch_records_valid(epoch_records, epoch_index, phase):
		return ["planet campaign epoch resolution ledger is invalid"]
	if not _directive_records_valid(catalog, epoch_records, directive_records):
		return ["planet campaign directive ledger is invalid"]
	var expected_keys: Array[String] = []
	for raw_record in directive_records:
		expected_keys.append(String((raw_record as Dictionary)["commitment_replay_key"]))
	expected_keys.sort()
	if _canonical_json(expected_keys) != _canonical_json(data["consumed_commitment_keys"]) \
			or not _sorted_unique_receipts(data["consumed_commitment_keys"]):
		return ["planet campaign commitment replay ledger is invalid"]
	if not _consequence_records_valid(catalog, directive_records, consequence_records):
		return ["planet campaign consequence ledger is invalid"]
	if not _delivery_records_valid(
		consequence_records, directive_records, delivery_records, epoch_index
	):
		return ["planet campaign delivery ledger is invalid"]
	var expected_delivered: Array[String] = []
	for raw_delivery in delivery_records:
		expected_delivered.append(String((raw_delivery as Dictionary)["consequence_id"]))
	expected_delivered.sort()
	if _canonical_json(expected_delivered) != _canonical_json(data["delivered_consequence_ids"]) \
			or not _sorted_unique_short_ids(data["delivered_consequence_ids"], CONSEQUENCE_ID_PREFIX):
		return ["planet campaign delivered consequence IDs are invalid"]
	var expected_revision := epoch_records.size() + directive_records.size() \
		- (1 if phase == "committed" else 0) + delivery_records.size()
	if revision != expected_revision:
		return ["planet campaign revision does not derive from its transition ledgers"]
	for key in ["parent_state_receipt", "last_action_receipt", "state_receipt"]:
		if typeof(data.get(key)) != TYPE_STRING:
			return ["planet campaign receipt fields must be Strings"]
	if revision == 0:
		if String(data["parent_state_receipt"]) != "" or String(data["last_action_receipt"]) != "":
			return ["initial planet campaign state cannot have a parent action"]
	else:
		if not _receipt_token_valid(String(data["parent_state_receipt"])) \
				or not _receipt_token_valid(String(data["last_action_receipt"])):
			return ["planet campaign state chain receipts are invalid"]
	var base := data.duplicate(true)
	base.erase("state_receipt")
	if String(data["state_receipt"]) != _receipt_for(base):
		return ["planet campaign state receipt mismatch"]
	return []


static func normalize_state(catalog: Dictionary, value: Variant) -> Dictionary:
	if not validate_state(catalog, value).is_empty():
		return {}
	var data: Dictionary = value
	var result := data.duplicate(true)
	result["revision"] = int(data["revision"])
	result["epoch_index"] = int(data["epoch_index"])
	result["epoch_records"] = _normalize_record_array(data["epoch_records"], ["epoch_index"])
	result["directive_records"] = _normalize_record_array(data["directive_records"],
		["epoch_index", "capacity_cost", "primary_requested", "primary_applied",
			"faction_requested", "faction_applied", "consequence_release_epoch"])
	result["consequence_records"] = _normalize_record_array(data["consequence_records"],
		["origin_epoch", "release_epoch", "requested_delta"])
	result["delivery_records"] = _normalize_record_array(data["delivery_records"],
		["delivered_epoch", "requested_delta", "applied_delta"])
	return result


static func accept_state_checkpoint(catalog: Dictionary, value: Variant,
		expected_state_receipt: String) -> Dictionary:
	if not _receipt_token_valid(expected_state_receipt):
		return {}
	var normalized := normalize_state(catalog, value)
	return normalized if not normalized.is_empty() \
		and String(normalized["state_receipt"]) == expected_state_receipt else {}


static func _make_state(catalog: Dictionary, revision: int, epoch_index: int,
		phase: String, epoch_records: Array, directive_records: Array,
		consumed_keys: Array, consequence_records: Array, delivery_records: Array,
		delivered_ids: Array, parent_receipt: String, last_action_receipt: String) -> Dictionary:
	var base := {
		"schema": STATE_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(catalog["catalog_id"]),
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"revision": revision,
		"epoch_index": epoch_index,
		"season": _season_for(epoch_index, phase),
		"phase": phase,
		"epoch_records": epoch_records.duplicate(true),
		"directive_records": directive_records.duplicate(true),
		"consumed_commitment_keys": consumed_keys.duplicate(true),
		"consequence_records": consequence_records.duplicate(true),
		"delivery_records": delivery_records.duplicate(true),
		"delivered_consequence_ids": delivered_ids.duplicate(true),
		"parent_state_receipt": parent_receipt,
		"last_action_receipt": last_action_receipt,
	}
	base["state_receipt"] = _receipt_for(base)
	return base if String(base["state_receipt"]) != "" else {}


static func make_window_adapter(catalog: Dictionary, window_key: String,
		region_scope: String, region_checkpoint_receipt: String,
		global_network_scope: String, global_network_checkpoint_receipt: String,
		signals: Dictionary) -> Dictionary:
	if not _catalog_self_valid(catalog) or not _slug_valid(region_scope) \
			or not _receipt_token_valid(region_checkpoint_receipt) \
			or not _slug_valid(global_network_scope) \
			or not _receipt_token_valid(global_network_checkpoint_receipt):
		return {}
	var window := _catalog_window_by_key(catalog, window_key)
	var normalized_signals := _normalize_signals(signals)
	if window.is_empty() or normalized_signals.is_empty():
		return {}
	var authority := {
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(catalog["catalog_id"]),
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"window_id": String(window["window_id"]),
		"region_id": String(window["region_id"]),
		"region_scope": region_scope,
		"region_checkpoint_receipt": region_checkpoint_receipt,
		"global_network_scope": global_network_scope,
		"global_network_checkpoint_receipt": global_network_checkpoint_receipt,
		"signals": normalized_signals,
	}
	var digest := _sha256_hex(_canonical_json(authority))
	if digest == "":
		return {}
	var base := {
		"schema": ADAPTER_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(catalog["catalog_id"]),
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"window_id": String(window["window_id"]),
		"region_id": String(window["region_id"]),
		"region_scope": region_scope,
		"region_checkpoint_receipt": region_checkpoint_receipt,
		"signals": normalized_signals,
		"adapter_id": ADAPTER_ID_PREFIX + digest.substr(0, 16),
	}
	base["adapter_receipt"] = _receipt_for({"authority": authority, "adapter": base})
	return base if String(base["adapter_receipt"]) != "" else {}


static func validate_window_adapter(catalog: Dictionary, value: Variant,
		expected_region_scope: String, accepted_region_checkpoint_receipt: String,
		expected_global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String,
		expected_adapter_receipt: String) -> Array[String]:
	if not _slug_valid(expected_region_scope) \
			or not _receipt_token_valid(accepted_region_checkpoint_receipt) \
			or not _slug_valid(expected_global_network_scope) \
			or not _receipt_token_valid(accepted_global_network_checkpoint_receipt) \
			or not _receipt_token_valid(expected_adapter_receipt):
		return ["window adapter requires external owner-accepted checkpoints"]
	if not (value is Dictionary):
		return ["window adapter must be a Dictionary"]
	var data: Dictionary = value
	var required := ["schema", "terms_revision", "catalog_id", "catalog_receipt",
		"window_id", "region_id", "region_scope", "region_checkpoint_receipt",
		"signals", "adapter_id", "adapter_receipt"]
	if not _exact_keys(data, required) or not (data.get("signals") is Dictionary):
		return ["window adapter fields must match V1 exactly"]
	if String(data.get("region_scope", "")) != expected_region_scope \
			or String(data.get("region_checkpoint_receipt", "")) \
			!= accepted_region_checkpoint_receipt \
			or String(data.get("adapter_receipt", "")) != expected_adapter_receipt:
		return ["window adapter does not match its external accepted anchor"]
	var window := _catalog_window_by_id(catalog, _string_if(data.get("window_id")))
	if window.is_empty() or String(window["region_id"]) != String(data.get("region_id", "")):
		return ["window adapter catalog identity mismatch"]
	var expected := make_window_adapter(
		catalog, String(window["window_key"]), expected_region_scope,
		accepted_region_checkpoint_receipt, expected_global_network_scope,
		accepted_global_network_checkpoint_receipt, data["signals"]
	)
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(data):
		return ["window adapter does not derive from accepted owner evidence"]
	return []


static func normalize_window_adapter(catalog: Dictionary, value: Variant,
		expected_region_scope: String, accepted_region_checkpoint_receipt: String,
		expected_global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String,
		expected_adapter_receipt: String) -> Dictionary:
	if not (value is Dictionary) or not validate_window_adapter(
		catalog, value, expected_region_scope, accepted_region_checkpoint_receipt,
		expected_global_network_scope, accepted_global_network_checkpoint_receipt,
		expected_adapter_receipt
	).is_empty():
		return {}
	var data: Dictionary = value
	var window := _catalog_window_by_id(catalog, String(data["window_id"]))
	return make_window_adapter(
		catalog, String(window["window_key"]), expected_region_scope,
		accepted_region_checkpoint_receipt, expected_global_network_scope,
		accepted_global_network_checkpoint_receipt, data["signals"]
	)


static func make_window_acceptance(window_id: String, expected_region_scope: String,
		accepted_region_checkpoint_receipt: String,
		expected_adapter_receipt: String) -> Dictionary:
	if not _short_id_valid(window_id, WINDOW_ID_PREFIX) \
			or not _slug_valid(expected_region_scope) \
			or not _receipt_token_valid(accepted_region_checkpoint_receipt) \
			or not _receipt_token_valid(expected_adapter_receipt):
		return {}
	return {
		"window_id": window_id,
		"expected_region_scope": expected_region_scope,
		"accepted_region_checkpoint_receipt": accepted_region_checkpoint_receipt,
		"expected_adapter_receipt": expected_adapter_receipt,
	}


static func make_command_anchor(owner_scope: String, owner_checkpoint_receipt: String,
		epoch_index: int, command_slots_before: int,
		capacity_units_before: int) -> Dictionary:
	if not _slug_valid(owner_scope) or not _receipt_token_valid(owner_checkpoint_receipt) \
			or not _bounded_int(epoch_index, 0, TERMINAL_EPOCH - 1) \
			or not _bounded_int(command_slots_before, 0, MAX_COMMAND_SLOTS) \
			or not _bounded_int(capacity_units_before, 0, MAX_CAPACITY_UNITS):
		return {}
	var replay_key := _receipt_for([owner_scope, owner_checkpoint_receipt])
	if replay_key == "":
		return {}
	var base := {
		"schema": COMMAND_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"owner_scope": owner_scope,
		"owner_checkpoint_receipt": owner_checkpoint_receipt,
		"epoch_index": epoch_index,
		"command_slots_before": command_slots_before,
		"capacity_units_before": capacity_units_before,
		"commitment_replay_key": replay_key,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["anchor_id"] = COMMAND_ID_PREFIX + digest.substr(0, 16)
	base["anchor_receipt"] = _receipt_for(base)
	return base if String(base["anchor_receipt"]) != "" else {}


static func validate_command_anchor(value: Variant, expected_owner_scope: String,
		expected_owner_checkpoint_receipt: String,
		expected_command_anchor_receipt: String) -> Array[String]:
	if not _slug_valid(expected_owner_scope) \
			or not _receipt_token_valid(expected_owner_checkpoint_receipt) \
			or not _receipt_token_valid(expected_command_anchor_receipt):
		return ["command anchor requires external owner evidence"]
	if not (value is Dictionary):
		return ["command anchor must be a Dictionary"]
	var data: Dictionary = value
	var required := ["schema", "terms_revision", "owner_scope",
		"owner_checkpoint_receipt", "epoch_index", "command_slots_before",
		"capacity_units_before", "commitment_replay_key", "anchor_id",
		"anchor_receipt"]
	if not _exact_keys(data, required):
		return ["command anchor fields must match V1 exactly"]
	if String(data.get("owner_scope", "")) != expected_owner_scope \
			or String(data.get("owner_checkpoint_receipt", "")) \
			!= expected_owner_checkpoint_receipt \
			or String(data.get("anchor_receipt", "")) != expected_command_anchor_receipt:
		return ["command anchor does not match external owner evidence"]
	if not _bounded_int(data.get("epoch_index"), 0, TERMINAL_EPOCH - 1) \
			or not _bounded_int(data.get("command_slots_before"), 0, MAX_COMMAND_SLOTS) \
			or not _bounded_int(data.get("capacity_units_before"), 0, MAX_CAPACITY_UNITS):
		return ["command anchor numeric fields are out of range"]
	var expected := make_command_anchor(
		expected_owner_scope, expected_owner_checkpoint_receipt,
		int(data["epoch_index"]), int(data["command_slots_before"]),
		int(data["capacity_units_before"])
	)
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(data):
		return ["command anchor does not recompute from external owner evidence"]
	return []


static func normalize_command_anchor(value: Variant, expected_owner_scope: String,
		expected_owner_checkpoint_receipt: String,
		expected_command_anchor_receipt: String) -> Dictionary:
	if not (value is Dictionary) or not validate_command_anchor(
		value, expected_owner_scope, expected_owner_checkpoint_receipt,
		expected_command_anchor_receipt
	).is_empty():
		return {}
	var data: Dictionary = value
	return make_command_anchor(
		expected_owner_scope, expected_owner_checkpoint_receipt,
		int(data["epoch_index"]), int(data["command_slots_before"]),
		int(data["capacity_units_before"])
	)


static func make_directive_board(catalog: Dictionary, state: Dictionary,
		accepted_state_receipt: String, adapters: Array, adapter_acceptances: Array,
		global_network_scope: String, accepted_global_network_checkpoint_receipt: String,
		command_anchor: Dictionary, accepted_command_owner_scope: String,
		accepted_command_owner_checkpoint_receipt: String,
		expected_command_anchor_receipt: String) -> Dictionary:
	if not _catalog_self_valid(catalog) or not _slug_valid(global_network_scope) \
			or not _receipt_token_valid(accepted_global_network_checkpoint_receipt):
		return {}
	var normalized_state := accept_state_checkpoint(catalog, state, accepted_state_receipt)
	var normalized_command := normalize_command_anchor(
		command_anchor, accepted_command_owner_scope,
		accepted_command_owner_checkpoint_receipt, expected_command_anchor_receipt
	)
	var evidence := _normalize_adapter_set(
		catalog, adapters, adapter_acceptances, global_network_scope,
		accepted_global_network_checkpoint_receipt
	)
	if normalized_state.is_empty() or normalized_command.is_empty() or evidence.is_empty():
		return {}
	if accepted_command_owner_scope == global_network_scope:
		return {}
	for raw_acceptance in evidence["acceptances"]:
		var owner_acceptance: Dictionary = raw_acceptance
		if String(owner_acceptance["expected_region_scope"]) \
				== accepted_command_owner_scope:
			return {}
	var normalized_adapters: Array = evidence["adapters"]
	var options: Array[Dictionary] = []
	var status := "no_eligible_directive"
	var phase := String(normalized_state["phase"])
	var epoch_index := int(normalized_state["epoch_index"])
	if phase == "terminal":
		status = "campaign_terminal"
	elif phase == "committed":
		status = "epoch_committed"
	elif int(normalized_command["epoch_index"]) == epoch_index \
			and not String(normalized_command["commitment_replay_key"]) \
			in normalized_state["consumed_commitment_keys"] \
			and int(normalized_command["command_slots_before"]) >= 1:
		var adapter_by_window := _adapter_by_window(normalized_adapters)
		for raw_directive in catalog["directives"]:
			var directive: Dictionary = raw_directive
			var origin_window_id := String(directive["origin_window_id"])
			var target_window_id := String(directive["target_window_id"])
			if not adapter_by_window.has(origin_window_id) \
					or not adapter_by_window.has(target_window_id):
				continue
			var origin_adapter: Dictionary = adapter_by_window[origin_window_id]
			var target_adapter: Dictionary = adapter_by_window[target_window_id]
			var option := _make_board_option(
				directive, origin_adapter, target_adapter, normalized_state,
				normalized_command
			)
			if not option.is_empty():
				options.append(option)
		options.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return String(left["option_id"]) < String(right["option_id"]))
		if not options.is_empty():
			status = "options_available"
	var base := {
		"schema": BOARD_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(catalog["catalog_id"]),
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"state_receipt": String(normalized_state["state_receipt"]),
		"accepted_state_receipt": accepted_state_receipt,
		"revision": int(normalized_state["revision"]),
		"epoch_index": epoch_index,
		"season": String(normalized_state["season"]),
		"phase": phase,
		"global_network_scope": global_network_scope,
		"accepted_global_network_checkpoint_receipt":
			accepted_global_network_checkpoint_receipt,
		"adapter_acceptances": evidence["acceptances"],
		"command_anchor_id": String(normalized_command["anchor_id"]),
		"command_anchor_receipt": String(normalized_command["anchor_receipt"]),
		"commitment_replay_key": String(normalized_command["commitment_replay_key"]),
		"accepted_command_owner_scope": accepted_command_owner_scope,
		"accepted_command_owner_checkpoint_receipt":
			accepted_command_owner_checkpoint_receipt,
		"expected_command_anchor_receipt": expected_command_anchor_receipt,
		"decision_status": status,
		"options": options,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["board_id"] = BOARD_ID_PREFIX + digest.substr(0, 16)
	base["board_receipt"] = _receipt_for(base)
	return base if String(base["board_receipt"]) != "" else {}


static func validate_directive_board(catalog: Dictionary, state: Dictionary,
		accepted_state_receipt: String, adapters: Array, adapter_acceptances: Array,
		global_network_scope: String, accepted_global_network_checkpoint_receipt: String,
		command_anchor: Dictionary, accepted_command_owner_scope: String,
		accepted_command_owner_checkpoint_receipt: String,
		expected_command_anchor_receipt: String, value: Variant) -> Array[String]:
	var expected := make_directive_board(
		catalog, state, accepted_state_receipt, adapters, adapter_acceptances,
		global_network_scope, accepted_global_network_checkpoint_receipt,
		command_anchor, accepted_command_owner_scope,
		accepted_command_owner_checkpoint_receipt, expected_command_anchor_receipt
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["directive board does not derive from all accepted owner checkpoints"]
	return []


static func normalize_directive_board(catalog: Dictionary, state: Dictionary,
		accepted_state_receipt: String, adapters: Array, adapter_acceptances: Array,
		global_network_scope: String, accepted_global_network_checkpoint_receipt: String,
		command_anchor: Dictionary, accepted_command_owner_scope: String,
		accepted_command_owner_checkpoint_receipt: String,
		expected_command_anchor_receipt: String, value: Variant) -> Dictionary:
	var expected := make_directive_board(
		catalog, state, accepted_state_receipt, adapters, adapter_acceptances,
		global_network_scope, accepted_global_network_checkpoint_receipt,
		command_anchor, accepted_command_owner_scope,
		accepted_command_owner_checkpoint_receipt, expected_command_anchor_receipt
	)
	return expected if not expected.is_empty() and value is Dictionary \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func make_choice(board: Dictionary, option_id: String) -> Dictionary:
	if not _board_self_valid(board) or not _short_id_valid(option_id, DIRECTIVE_ID_PREFIX):
		return {}
	var selected := _board_option_by_id(board, option_id)
	if selected.is_empty():
		return {}
	var base := {
		"schema": CHOICE_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"board_id": String(board["board_id"]),
		"board_receipt": String(board["board_receipt"]),
		"state_receipt": String(board["state_receipt"]),
		"commitment_replay_key": String(board["commitment_replay_key"]),
		"option_id": option_id,
		"directive_id": String(selected["directive_id"]),
		"directive_receipt": String(selected["directive_receipt"]),
		"action": String(selected["action"]),
		"origin_window_id": String(selected["origin_window_id"]),
		"target_window_id": String(selected["target_window_id"]),
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["choice_id"] = CHOICE_ID_PREFIX + digest.substr(0, 16)
	base["choice_receipt"] = _receipt_for(base)
	return base if String(base["choice_receipt"]) != "" else {}


static func validate_choice(board: Dictionary, value: Variant) -> Array[String]:
	if not (value is Dictionary):
		return ["directive choice must be a Dictionary"]
	var expected := make_choice(board, _string_if((value as Dictionary).get("option_id")))
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(value):
		return ["directive choice does not derive from its exact accepted board"]
	return []


static func normalize_choice(board: Dictionary, value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var expected := make_choice(board, _string_if((value as Dictionary).get("option_id")))
	return expected if not expected.is_empty() \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func _make_board_option(directive: Dictionary, origin_adapter: Dictionary,
		target_adapter: Dictionary, state: Dictionary, command_anchor: Dictionary) -> Dictionary:
	var season := String(state["season"])
	var favored := season == String(directive["favored_season"])
	var capacity_cost := int(directive[
		"favored_capacity_cost" if favored else "offseason_capacity_cost"
	])
	if int(command_anchor["capacity_units_before"]) < capacity_cost:
		return {}
	var before := _normalize_signals(origin_adapter["signals"])
	if before.is_empty() or int(before["faction_access"]) < 1:
		return {}
	var primary_track := String(directive["primary_track"])
	var primary_requested := -3 if favored else -2
	var primary_applied := -mini(int(before[primary_track]), -primary_requested)
	var faction_requested := 1
	var faction_applied := mini(faction_requested, MAX_TRACK - int(before["faction_access"]))
	if primary_applied == 0 and faction_applied == 0:
		return {}
	var after := before.duplicate(true)
	after[primary_track] = int(before[primary_track]) + primary_applied
	after["faction_access"] = int(before["faction_access"]) + faction_applied
	return {
		"option_id": String(directive["directive_id"]),
		"directive_id": String(directive["directive_id"]),
		"directive_receipt": String(directive["directive_receipt"]),
		"action": String(directive["action"]),
		"faction_id": String(directive["faction_id"]),
		"origin_window_id": String(directive["origin_window_id"]),
		"origin_region_id": String(directive["origin_region_id"]),
		"origin_region_scope": String(origin_adapter["region_scope"]),
		"target_window_id": String(directive["target_window_id"]),
		"target_region_id": String(directive["target_region_id"]),
		"epoch_index": int(state["epoch_index"]),
		"season": season,
		"command_slots_cost": 1,
		"capacity_cost": capacity_cost,
		"benefit": (directive["benefit"] as Dictionary).duplicate(true),
		"origin_adapter_receipt": String(origin_adapter["adapter_receipt"]),
		"origin_region_checkpoint_receipt": String(
			origin_adapter["region_checkpoint_receipt"]
		),
		"origin_effect": {
			"primary_track": primary_track,
			"primary_requested": primary_requested,
			"primary_applied": primary_applied,
			"faction_requested": faction_requested,
			"faction_applied": faction_applied,
			"before_signals": before,
			"after_signals": after,
		},
		"scheduled_target_adapter_receipt": String(target_adapter["adapter_receipt"]),
		"scheduled_target_region_scope": String(target_adapter["region_scope"]),
		"scheduled_target_region_checkpoint_receipt": String(
			target_adapter["region_checkpoint_receipt"]
		),
		"consequence": {
			"kind": String(directive["consequence_kind"]),
			"track": String(directive["consequence_track"]),
			"requested_delta": int(directive["consequence_delta"]),
			"release_epoch": int(state["epoch_index"]) \
				+ int(directive["consequence_delay_epochs"]),
		},
	}


static func _normalize_adapter_set(catalog: Dictionary, adapters: Array,
		acceptances: Array, global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String) -> Dictionary:
	if adapters.size() != (catalog["windows"] as Array).size() \
			or acceptances.size() != adapters.size():
		return {}
	var acceptance_by_window := {}
	for raw_acceptance in acceptances:
		if not (raw_acceptance is Dictionary):
			return {}
		var acceptance: Dictionary = raw_acceptance
		var required := ["window_id", "expected_region_scope",
			"accepted_region_checkpoint_receipt", "expected_adapter_receipt"]
		if not _exact_keys(acceptance, required):
			return {}
		var window_id := _string_if(acceptance.get("window_id"))
		if _catalog_window_by_id(catalog, window_id).is_empty() \
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
	var adapter_windows_seen := {}
	var region_scopes_seen := {}
	for raw_adapter in adapters:
		if not (raw_adapter is Dictionary):
			return {}
		var adapter: Dictionary = raw_adapter
		var window_id := _string_if(adapter.get("window_id"))
		if not acceptance_by_window.has(window_id) or adapter_windows_seen.has(window_id):
			return {}
		adapter_windows_seen[window_id] = true
		var acceptance: Dictionary = acceptance_by_window[window_id]
		var region_scope := String(acceptance["expected_region_scope"])
		if region_scope == global_network_scope \
				or region_scopes_seen.has(region_scope):
			return {}
		region_scopes_seen[region_scope] = true
		var normalized := normalize_window_adapter(
			catalog, adapter, String(acceptance["expected_region_scope"]),
			String(acceptance["accepted_region_checkpoint_receipt"]),
			global_network_scope, accepted_global_network_checkpoint_receipt,
			String(acceptance["expected_adapter_receipt"])
		)
		if normalized.is_empty():
			return {}
		normalized_adapters.append(normalized)
	if adapter_windows_seen.size() != (catalog["windows"] as Array).size():
		return {}
	normalized_adapters.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["window_id"]) < String(right["window_id"]))
	var normalized_acceptances: Array[Dictionary] = []
	for adapter in normalized_adapters:
		normalized_acceptances.append(
			(acceptance_by_window[String(adapter["window_id"])] as Dictionary).duplicate(true)
		)
	return {"adapters": normalized_adapters, "acceptances": normalized_acceptances}


static func _adapter_by_window(adapters: Array) -> Dictionary:
	var result := {}
	for raw_adapter in adapters:
		var adapter: Dictionary = raw_adapter
		result[String(adapter["window_id"])] = adapter
	return result


static func _board_option_by_id(board: Dictionary, option_id: String) -> Dictionary:
	for raw_option in board.get("options", []):
		if raw_option is Dictionary \
				and String((raw_option as Dictionary).get("option_id", "")) == option_id:
			return (raw_option as Dictionary).duplicate(true)
	return {}


static func _board_self_valid(board: Dictionary) -> bool:
	var required := ["schema", "terms_revision", "catalog_id", "catalog_receipt",
		"state_receipt", "accepted_state_receipt", "revision", "epoch_index", "season",
		"phase", "global_network_scope", "accepted_global_network_checkpoint_receipt",
		"adapter_acceptances", "command_anchor_id", "command_anchor_receipt",
		"commitment_replay_key", "accepted_command_owner_scope",
		"accepted_command_owner_checkpoint_receipt", "expected_command_anchor_receipt",
		"decision_status", "options", "board_id", "board_receipt"]
	if not _exact_keys(board, required) or board.get("schema") != BOARD_SCHEMA \
			or board.get("terms_revision") != TERMS_REVISION \
			or not (board.get("adapter_acceptances") is Array) \
			or not (board.get("options") is Array) \
			or not _short_id_valid(_string_if(board.get("board_id")), BOARD_ID_PREFIX) \
			or not _receipt_token_valid(_string_if(board.get("board_receipt"))) \
			or String(board.get("decision_status", "")) not in [
				"options_available", "no_eligible_directive", "epoch_committed",
				"campaign_terminal"
			]:
		return false
	if not _short_id_valid(_string_if(board.get("catalog_id")), CATALOG_ID_PREFIX) \
			or not _receipt_token_valid(_string_if(board.get("catalog_receipt"))) \
			or not _receipt_token_valid(_string_if(board.get("state_receipt"))) \
			or board.get("state_receipt") != board.get("accepted_state_receipt") \
			or not _bounded_int(board.get("revision"), 0, MAX_TRANSITIONS) \
			or not _bounded_int(board.get("epoch_index"), 0, TERMINAL_EPOCH) \
			or _string_if(board.get("phase")) not in PHASES \
			or _string_if(board.get("season")) != _season_for(
				int(board.get("epoch_index")), _string_if(board.get("phase"))
			) or not _slug_valid(_string_if(board.get("global_network_scope"))) \
			or not _receipt_token_valid(_string_if(
				board.get("accepted_global_network_checkpoint_receipt")
			)) or not _short_id_valid(_string_if(board.get("command_anchor_id")),
				COMMAND_ID_PREFIX) \
			or not _receipt_token_valid(_string_if(board.get("command_anchor_receipt"))) \
			or board.get("command_anchor_receipt") != board.get("expected_command_anchor_receipt") \
			or not _receipt_token_valid(_string_if(board.get("commitment_replay_key"))) \
			or not _slug_valid(_string_if(board.get("accepted_command_owner_scope"))) \
			or not _receipt_token_valid(_string_if(
				board.get("accepted_command_owner_checkpoint_receipt")
			)):
		return false
	var acceptances: Array = board["adapter_acceptances"]
	if acceptances.size() != _window_specs().size():
		return false
	var previous_window_id := ""
	var region_scopes := {}
	var region_scope_by_window := {}
	for raw_acceptance in acceptances:
		if not (raw_acceptance is Dictionary):
			return false
		var acceptance: Dictionary = raw_acceptance
		var acceptance_keys := ["window_id", "expected_region_scope",
			"accepted_region_checkpoint_receipt", "expected_adapter_receipt"]
		var window_id := _string_if(acceptance.get("window_id"))
		var region_scope := _string_if(acceptance.get("expected_region_scope"))
		if not _exact_keys(acceptance, acceptance_keys) \
				or not _short_id_valid(window_id, WINDOW_ID_PREFIX) \
				or window_id <= previous_window_id or not _slug_valid(region_scope) \
				or region_scopes.has(region_scope) \
				or not _receipt_token_valid(_string_if(
					acceptance.get("accepted_region_checkpoint_receipt")
				)) or not _receipt_token_valid(_string_if(
					acceptance.get("expected_adapter_receipt")
				)):
			return false
		previous_window_id = window_id
		region_scopes[region_scope] = true
		region_scope_by_window[window_id] = region_scope
	if _string_if(board.get("global_network_scope")) \
			== _string_if(board.get("accepted_command_owner_scope")) \
			or region_scopes.has(_string_if(board.get("global_network_scope"))) \
			or region_scopes.has(_string_if(board.get("accepted_command_owner_scope"))):
		return false
	var options: Array = board["options"]
	var status := String(board["decision_status"])
	var phase := String(board["phase"])
	if options.size() > _window_specs().size() \
			or (status == "options_available") != not options.is_empty() \
			or (phase == "committed") != (status == "epoch_committed") \
			or (phase == "terminal") != (status == "campaign_terminal") \
			or (phase == "open" and options.is_empty() \
				and status != "no_eligible_directive"):
		return false
	var previous_option_id := ""
	for raw_option in options:
		if not (raw_option is Dictionary) \
				or not _board_option_self_valid(raw_option as Dictionary):
			return false
		var option: Dictionary = raw_option
		var option_id := String(option["option_id"])
		if option_id <= previous_option_id \
				or int(option["epoch_index"]) != int(board["epoch_index"]) \
				or String(option["season"]) != String(board["season"]) \
				or not region_scope_by_window.has(String(option["origin_window_id"])) \
				or not region_scope_by_window.has(String(option["target_window_id"])) \
				or String(option["origin_region_scope"]) \
				!= String(region_scope_by_window[String(option["origin_window_id"])]) \
				or String(option["scheduled_target_region_scope"]) \
				!= String(region_scope_by_window[String(option["target_window_id"])]):
			return false
		previous_option_id = option_id
	var id_base := board.duplicate(true)
	id_base.erase("board_id")
	id_base.erase("board_receipt")
	var digest := _sha256_hex(_canonical_json(id_base))
	if digest == "" or String(board["board_id"]) != BOARD_ID_PREFIX + digest.substr(0, 16):
		return false
	var receipt_base := board.duplicate(true)
	receipt_base.erase("board_receipt")
	return String(board["board_receipt"]) == _receipt_for(receipt_base)


static func _board_option_self_valid(option: Dictionary) -> bool:
	var required := ["option_id", "directive_id", "directive_receipt", "action",
		"faction_id", "origin_window_id", "origin_region_id", "origin_region_scope",
		"target_window_id", "target_region_id", "epoch_index", "season",
		"command_slots_cost", "capacity_cost", "benefit", "origin_adapter_receipt",
		"origin_region_checkpoint_receipt", "origin_effect",
		"scheduled_target_adapter_receipt", "scheduled_target_region_scope",
		"scheduled_target_region_checkpoint_receipt", "consequence"]
	if not _exact_keys(option, required) or not (option.get("benefit") is Dictionary) \
			or not (option.get("origin_effect") is Dictionary) \
			or not (option.get("consequence") is Dictionary) \
			or not _short_id_valid(_string_if(option.get("option_id")), DIRECTIVE_ID_PREFIX) \
			or option.get("option_id") != option.get("directive_id") \
			or not _receipt_token_valid(_string_if(option.get("directive_receipt"))) \
			or _string_if(option.get("action")) not in ["aid", "trade", "fortify"] \
			or not _slug_valid(_string_if(option.get("faction_id"))) \
			or not _short_id_valid(_string_if(option.get("origin_window_id")), WINDOW_ID_PREFIX) \
			or not _short_id_valid(_string_if(option.get("target_window_id")), WINDOW_ID_PREFIX) \
			or option.get("origin_window_id") == option.get("target_window_id") \
			or ScaleAddress.level_of(ScaleAddress.parse_id(
				_string_if(option.get("origin_region_id"))
			)) != ScaleAddress.LEVEL_REGION \
			or ScaleAddress.level_of(ScaleAddress.parse_id(
				_string_if(option.get("target_region_id"))
			)) != ScaleAddress.LEVEL_REGION \
			or not _slug_valid(_string_if(option.get("origin_region_scope"))) \
			or not _slug_valid(_string_if(option.get("scheduled_target_region_scope"))) \
			or not _bounded_int(option.get("epoch_index"), 0, TERMINAL_EPOCH - 1) \
			or _string_if(option.get("season")) != String(SEASONS[int(option["epoch_index"])]) \
			or not _bounded_int(option.get("command_slots_cost"), 1, 1) \
			or not _bounded_int(option.get("capacity_cost"), 2, 3):
		return false
	for receipt_key in ["origin_adapter_receipt", "origin_region_checkpoint_receipt",
			"scheduled_target_adapter_receipt",
			"scheduled_target_region_checkpoint_receipt"]:
		if not _receipt_token_valid(_string_if(option.get(receipt_key))):
			return false
	var benefit: Dictionary = option["benefit"]
	var benefit_keys := ["relief", "commerce", "defense"]
	if not _exact_keys(benefit, benefit_keys):
		return false
	var benefit_sum := 0
	var benefit_axes := 0
	for key in benefit_keys:
		if not _bounded_int(benefit.get(key), 0, 3) or int(benefit[key]) not in [0, 3]:
			return false
		benefit_sum += int(benefit[key])
		benefit_axes += 1 if int(benefit[key]) == 3 else 0
	if benefit_sum != 3 or benefit_axes != 1:
		return false
	var effect: Dictionary = option["origin_effect"]
	var effect_keys := ["primary_track", "primary_requested", "primary_applied",
		"faction_requested", "faction_applied", "before_signals", "after_signals"]
	if not _exact_keys(effect, effect_keys) \
			or not (effect.get("before_signals") is Dictionary) \
			or not (effect.get("after_signals") is Dictionary) \
			or _string_if(effect.get("primary_track")) not in [
				"need_pressure", "security_pressure", "logistics_pressure"
			] or not _bounded_int(effect.get("primary_requested"), -3, -2) \
			or not _bounded_int(effect.get("primary_applied"), -3, 0) \
			or int(effect["primary_applied"]) < int(effect["primary_requested"]) \
			or not _bounded_int(effect.get("faction_requested"), 1, 1) \
			or not _bounded_int(effect.get("faction_applied"), 0, 1) \
			or (int(effect["primary_applied"]) == 0 \
				and int(effect["faction_applied"]) == 0):
		return false
	var before := _normalize_signals(effect["before_signals"])
	var after := _normalize_signals(effect["after_signals"])
	if before.is_empty() or after.is_empty() or int(before["faction_access"]) < 1:
		return false
	var expected_after := before.duplicate(true)
	var primary_track := String(effect["primary_track"])
	expected_after[primary_track] = int(before[primary_track]) + int(effect["primary_applied"])
	expected_after["faction_access"] = int(before["faction_access"]) \
		+ int(effect["faction_applied"])
	if _canonical_json(expected_after) != _canonical_json(after):
		return false
	var consequence: Dictionary = option["consequence"]
	var consequence_keys := ["kind", "track", "requested_delta", "release_epoch"]
	return _exact_keys(consequence, consequence_keys) \
		and _slug_valid(_string_if(consequence.get("kind"))) \
		and _string_if(consequence.get("track")) in [
			"need_pressure", "security_pressure", "logistics_pressure"
		] and _bounded_int(consequence.get("requested_delta"), -1, -1) \
		and _bounded_int(consequence.get("release_epoch"), 1, TERMINAL_EPOCH) \
		and int(consequence["release_epoch"]) == int(option["epoch_index"]) + 1


static func commit_directive(catalog: Dictionary, before_state: Dictionary,
		accepted_before_state_receipt: String, adapters: Array,
		adapter_acceptances: Array, global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String,
		command_anchor: Dictionary, accepted_command_owner_scope: String,
		accepted_command_owner_checkpoint_receipt: String,
		expected_command_anchor_receipt: String, board: Dictionary,
		choice: Dictionary) -> Dictionary:
	var normalized_state := accept_state_checkpoint(
		catalog, before_state, accepted_before_state_receipt
	)
	if normalized_state.is_empty() or String(normalized_state["phase"]) != "open":
		return {}
	var expected_board := make_directive_board(
		catalog, normalized_state, accepted_before_state_receipt, adapters,
		adapter_acceptances, global_network_scope,
		accepted_global_network_checkpoint_receipt, command_anchor,
		accepted_command_owner_scope, accepted_command_owner_checkpoint_receipt,
		expected_command_anchor_receipt
	)
	if expected_board.is_empty() or _canonical_json(expected_board) != _canonical_json(board) \
			or String(expected_board["decision_status"]) != "options_available":
		return {}
	var normalized_choice := normalize_choice(expected_board, choice)
	if normalized_choice.is_empty():
		return {}
	var option := _board_option_by_id(expected_board, String(normalized_choice["option_id"]))
	var normalized_command := normalize_command_anchor(
		command_anchor, accepted_command_owner_scope,
		accepted_command_owner_checkpoint_receipt, expected_command_anchor_receipt
	)
	var evidence := _normalize_adapter_set(
		catalog, adapters, adapter_acceptances, global_network_scope,
		accepted_global_network_checkpoint_receipt
	)
	if option.is_empty() or normalized_command.is_empty() or evidence.is_empty():
		return {}
	var adapter_by_window := _adapter_by_window(evidence["adapters"])
	var origin_adapter: Dictionary = adapter_by_window.get(
		String(option["origin_window_id"]), {}
	)
	if origin_adapter.is_empty():
		return {}
	var command_delta := _make_command_owner_delta(
		normalized_command, option, accepted_command_owner_scope,
		accepted_command_owner_checkpoint_receipt
	)
	var origin_delta := _make_origin_region_delta(origin_adapter, option)
	if command_delta.is_empty() or origin_delta.is_empty():
		return {}
	var directive_record := _make_directive_record(
		catalog, option, normalized_choice, normalized_command, origin_delta,
		global_network_scope, accepted_global_network_checkpoint_receipt
	)
	if directive_record.is_empty():
		return {}
	var consequence_record := _make_consequence_record(
		catalog, option, directive_record, normalized_choice
	)
	var epoch_record := _make_epoch_record(
		int(normalized_state["epoch_index"]), "directive", directive_record
	)
	if consequence_record.is_empty() or epoch_record.is_empty():
		return {}
	var epoch_records: Array = (normalized_state["epoch_records"] as Array).duplicate(true)
	epoch_records.append(epoch_record)
	var directive_records: Array = (normalized_state["directive_records"] as Array).duplicate(true)
	directive_records.append(directive_record)
	directive_records.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["record_id"]) < String(right["record_id"]))
	var consumed_keys: Array = (
		normalized_state["consumed_commitment_keys"] as Array
	).duplicate(true)
	consumed_keys.append(String(normalized_command["commitment_replay_key"]))
	consumed_keys.sort()
	var consequence_records: Array = (
		normalized_state["consequence_records"] as Array
	).duplicate(true)
	consequence_records.append(consequence_record)
	consequence_records.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["consequence_id"]) < String(right["consequence_id"]))
	var after_state := _make_state(
		catalog, int(normalized_state["revision"]) + 1,
		int(normalized_state["epoch_index"]), "committed", epoch_records,
		directive_records, consumed_keys, consequence_records,
		normalized_state["delivery_records"], normalized_state["delivered_consequence_ids"],
		String(normalized_state["state_receipt"]), String(directive_record["record_receipt"])
	)
	if after_state.is_empty() or not validate_state(catalog, after_state).is_empty():
		return {}
	var campaign_delta := {
		"before_state_receipt": String(normalized_state["state_receipt"]),
		"after_state_receipt": String(after_state["state_receipt"]),
		"before_revision": int(normalized_state["revision"]),
		"after_revision": int(after_state["revision"]),
		"epoch_index": int(after_state["epoch_index"]),
		"before_phase": "open",
		"after_phase": "committed",
	}
	campaign_delta["delta_receipt"] = _receipt_for(campaign_delta)
	if String(campaign_delta["delta_receipt"]) == "":
		return {}
	var base := {
		"schema": COMMIT_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(catalog["catalog_id"]),
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"owner_order": ["campaign", "command_owner", "origin_region"],
		"accepted_before_state_receipt": accepted_before_state_receipt,
		"board_id": String(expected_board["board_id"]),
		"board_receipt": String(expected_board["board_receipt"]),
		"choice_id": String(normalized_choice["choice_id"]),
		"choice_receipt": String(normalized_choice["choice_receipt"]),
		"global_network_scope": global_network_scope,
		"accepted_global_network_checkpoint_receipt":
			accepted_global_network_checkpoint_receipt,
		"campaign_delta": campaign_delta,
		"command_owner_delta": command_delta,
		"origin_region_delta": origin_delta,
		"directive_record": directive_record,
		"consequence_record": consequence_record,
		"after_state": after_state,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["proposal_id"] = COMMIT_ID_PREFIX + digest.substr(0, 16)
	base["proposal_receipt"] = _receipt_for(base)
	return base if String(base["proposal_receipt"]) != "" else {}


static func validate_commit_proposal(catalog: Dictionary, before_state: Dictionary,
		accepted_before_state_receipt: String, adapters: Array,
		adapter_acceptances: Array, global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String,
		command_anchor: Dictionary, accepted_command_owner_scope: String,
		accepted_command_owner_checkpoint_receipt: String,
		expected_command_anchor_receipt: String, board: Dictionary,
		choice: Dictionary, value: Variant) -> Array[String]:
	var expected := commit_directive(
		catalog, before_state, accepted_before_state_receipt, adapters,
		adapter_acceptances, global_network_scope,
		accepted_global_network_checkpoint_receipt, command_anchor,
		accepted_command_owner_scope, accepted_command_owner_checkpoint_receipt,
		expected_command_anchor_receipt, board, choice
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["commit proposal does not derive from its exact three-owner anchors"]
	return []


static func normalize_commit_proposal(catalog: Dictionary, before_state: Dictionary,
		accepted_before_state_receipt: String, adapters: Array,
		adapter_acceptances: Array, global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String,
		command_anchor: Dictionary, accepted_command_owner_scope: String,
		accepted_command_owner_checkpoint_receipt: String,
		expected_command_anchor_receipt: String, board: Dictionary,
		choice: Dictionary, value: Variant) -> Dictionary:
	var expected := commit_directive(
		catalog, before_state, accepted_before_state_receipt, adapters,
		adapter_acceptances, global_network_scope,
		accepted_global_network_checkpoint_receipt, command_anchor,
		accepted_command_owner_scope, accepted_command_owner_checkpoint_receipt,
		expected_command_anchor_receipt, board, choice
	)
	return expected if not expected.is_empty() and value is Dictionary \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func _make_command_owner_delta(command_anchor: Dictionary, option: Dictionary,
		accepted_owner_scope: String,
		accepted_owner_checkpoint_receipt: String) -> Dictionary:
	var slots_before := int(command_anchor["command_slots_before"])
	var capacity_before := int(command_anchor["capacity_units_before"])
	var slots_committed := int(option["command_slots_cost"])
	var capacity_committed := int(option["capacity_cost"])
	if slots_before < slots_committed or capacity_before < capacity_committed:
		return {}
	var base := {
		"owner_scope": accepted_owner_scope,
		"owner_checkpoint_receipt": accepted_owner_checkpoint_receipt,
		"command_anchor_id": String(command_anchor["anchor_id"]),
		"command_anchor_receipt": String(command_anchor["anchor_receipt"]),
		"commitment_replay_key": String(command_anchor["commitment_replay_key"]),
		"epoch_index": int(command_anchor["epoch_index"]),
		"command_slots_before": slots_before,
		"command_slots_committed": slots_committed,
		"command_slots_after": slots_before - slots_committed,
		"capacity_units_before": capacity_before,
		"capacity_units_committed": capacity_committed,
		"capacity_units_after": capacity_before - capacity_committed,
	}
	base["delta_receipt"] = _receipt_for(base)
	return base if String(base["delta_receipt"]) != "" else {}


static func _make_origin_region_delta(origin_adapter: Dictionary,
		option: Dictionary) -> Dictionary:
	var effect: Dictionary = option["origin_effect"]
	var base := {
		"window_id": String(option["origin_window_id"]),
		"region_id": String(option["origin_region_id"]),
		"region_scope": String(origin_adapter["region_scope"]),
		"before_region_checkpoint_receipt": String(
			origin_adapter["region_checkpoint_receipt"]
		),
		"before_adapter_receipt": String(origin_adapter["adapter_receipt"]),
		"action": String(option["action"]),
		"before_signals": (effect["before_signals"] as Dictionary).duplicate(true),
		"primary_track": String(effect["primary_track"]),
		"primary_requested": int(effect["primary_requested"]),
		"primary_applied": int(effect["primary_applied"]),
		"faction_requested": int(effect["faction_requested"]),
		"faction_applied": int(effect["faction_applied"]),
		"after_signals": (effect["after_signals"] as Dictionary).duplicate(true),
	}
	base["delta_receipt"] = _receipt_for(base)
	return base if String(base["delta_receipt"]) != "" else {}


static func _make_directive_record(catalog: Dictionary, option: Dictionary,
		choice: Dictionary, command_anchor: Dictionary, origin_delta: Dictionary,
		global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String) -> Dictionary:
	var effect: Dictionary = option["origin_effect"]
	var consequence: Dictionary = option["consequence"]
	var base := {
		"schema": DIRECTIVE_RECORD_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"epoch_index": int(option["epoch_index"]),
		"season": String(option["season"]),
		"directive_id": String(option["directive_id"]),
		"directive_receipt": String(option["directive_receipt"]),
		"action": String(option["action"]),
		"origin_window_id": String(option["origin_window_id"]),
		"origin_region_id": String(option["origin_region_id"]),
		"target_window_id": String(option["target_window_id"]),
		"target_region_id": String(option["target_region_id"]),
		"faction_id": String(option["faction_id"]),
		"commitment_replay_key": String(command_anchor["commitment_replay_key"]),
		"command_owner_scope": String(command_anchor["owner_scope"]),
		"command_owner_checkpoint_receipt": String(
			command_anchor["owner_checkpoint_receipt"]
		),
		"command_anchor_receipt": String(command_anchor["anchor_receipt"]),
		"global_network_scope": global_network_scope,
		"global_network_checkpoint_receipt":
			accepted_global_network_checkpoint_receipt,
		"origin_adapter_receipt": String(origin_delta["before_adapter_receipt"]),
		"origin_region_scope": String(origin_delta["region_scope"]),
		"origin_region_checkpoint_receipt": String(
			origin_delta["before_region_checkpoint_receipt"]
		),
		"capacity_cost": int(option["capacity_cost"]),
		"primary_track": String(effect["primary_track"]),
		"primary_requested": int(effect["primary_requested"]),
		"primary_applied": int(effect["primary_applied"]),
		"faction_requested": int(effect["faction_requested"]),
		"faction_applied": int(effect["faction_applied"]),
		"origin_delta_receipt": String(origin_delta["delta_receipt"]),
		"consequence_release_epoch": int(consequence["release_epoch"]),
		"choice_receipt": String(choice["choice_receipt"]),
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["record_id"] = DIRECTIVE_RECORD_ID_PREFIX + digest.substr(0, 16)
	base["record_receipt"] = _receipt_for(base)
	return base if String(base["record_receipt"]) != "" else {}


static func _make_consequence_record(catalog: Dictionary, option: Dictionary,
		directive_record: Dictionary, choice: Dictionary) -> Dictionary:
	var consequence: Dictionary = option["consequence"]
	var base := {
		"schema": CONSEQUENCE_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"origin_epoch": int(option["epoch_index"]),
		"release_epoch": int(consequence["release_epoch"]),
		"origin_directive_record_id": String(directive_record["record_id"]),
		"origin_directive_record_receipt": String(directive_record["record_receipt"]),
		"origin_choice_receipt": String(choice["choice_receipt"]),
		"origin_window_id": String(option["origin_window_id"]),
		"origin_region_id": String(option["origin_region_id"]),
		"target_window_id": String(option["target_window_id"]),
		"target_region_id": String(option["target_region_id"]),
		"scheduled_target_region_scope": String(
			option["scheduled_target_region_scope"]
		),
		"scheduled_target_adapter_receipt": String(
			option["scheduled_target_adapter_receipt"]
		),
		"scheduled_target_region_checkpoint_receipt": String(
			option["scheduled_target_region_checkpoint_receipt"]
		),
		"kind": String(consequence["kind"]),
		"track": String(consequence["track"]),
		"requested_delta": int(consequence["requested_delta"]),
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["consequence_id"] = CONSEQUENCE_ID_PREFIX + digest.substr(0, 16)
	base["consequence_receipt"] = _receipt_for(base)
	return base if String(base["consequence_receipt"]) != "" else {}


static func _make_epoch_record(epoch_index: int, resolution: String,
		directive_record: Dictionary = {}) -> Dictionary:
	if not _bounded_int(epoch_index, 0, TERMINAL_EPOCH - 1) \
			or resolution not in ["directive", "deferred"]:
		return {}
	if resolution == "directive" and directive_record.is_empty():
		return {}
	if resolution == "deferred" and not directive_record.is_empty():
		return {}
	var base := {
		"schema": EPOCH_RECORD_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"epoch_index": epoch_index,
		"season": String(SEASONS[epoch_index]),
		"resolution": resolution,
		"directive_record_id": String(directive_record.get("record_id", "")),
		"directive_record_receipt": String(directive_record.get("record_receipt", "")),
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["record_id"] = EPOCH_RECORD_ID_PREFIX + digest.substr(0, 16)
	base["record_receipt"] = _receipt_for(base)
	return base if String(base["record_receipt"]) != "" else {}


static func advance_epoch(catalog: Dictionary, before_state: Dictionary,
		accepted_before_state_receipt: String) -> Dictionary:
	var normalized_state := accept_state_checkpoint(
		catalog, before_state, accepted_before_state_receipt
	)
	if normalized_state.is_empty() or String(normalized_state["phase"]) == "terminal":
		return {}
	var from_epoch := int(normalized_state["epoch_index"])
	var from_phase := String(normalized_state["phase"])
	var epoch_records: Array = (normalized_state["epoch_records"] as Array).duplicate(true)
	var resolution := "directive"
	var epoch_record := {}
	if from_phase == "open":
		resolution = "deferred"
		epoch_record = _make_epoch_record(from_epoch, resolution)
		if epoch_record.is_empty():
			return {}
		epoch_records.append(epoch_record)
	else:
		if epoch_records.is_empty():
			return {}
		epoch_record = (epoch_records[epoch_records.size() - 1] as Dictionary).duplicate(true)
		if String(epoch_record.get("resolution", "")) != "directive" \
				or int(epoch_record.get("epoch_index", -1)) != from_epoch:
			return {}
	var to_epoch := from_epoch + 1
	var to_phase := "terminal" if to_epoch == TERMINAL_EPOCH else "open"
	var event_base := {
		"schema": ADVANCE_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(catalog["catalog_id"]),
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"accepted_before_state_receipt": accepted_before_state_receipt,
		"from_epoch": from_epoch,
		"from_season": String(normalized_state["season"]),
		"from_phase": from_phase,
		"resolution": resolution,
		"epoch_record_id": String(epoch_record["record_id"]),
		"epoch_record_receipt": String(epoch_record["record_receipt"]),
		"to_epoch": to_epoch,
		"to_season": _season_for(to_epoch, to_phase),
		"to_phase": to_phase,
	}
	var digest := _sha256_hex(_canonical_json(event_base))
	if digest == "":
		return {}
	var advance_id := ADVANCE_ID_PREFIX + digest.substr(0, 16)
	var advance_receipt := _receipt_for({"advance_id": advance_id, "event": event_base})
	if advance_receipt == "":
		return {}
	var after_state := _make_state(
		catalog, int(normalized_state["revision"]) + 1, to_epoch, to_phase,
		epoch_records, normalized_state["directive_records"],
		normalized_state["consumed_commitment_keys"],
		normalized_state["consequence_records"], normalized_state["delivery_records"],
		normalized_state["delivered_consequence_ids"],
		String(normalized_state["state_receipt"]), advance_receipt
	)
	if after_state.is_empty() or not validate_state(catalog, after_state).is_empty():
		return {}
	var campaign_delta := {
		"before_state_receipt": String(normalized_state["state_receipt"]),
		"after_state_receipt": String(after_state["state_receipt"]),
		"before_revision": int(normalized_state["revision"]),
		"after_revision": int(after_state["revision"]),
		"from_epoch": from_epoch,
		"to_epoch": to_epoch,
		"from_phase": from_phase,
		"to_phase": to_phase,
	}
	campaign_delta["delta_receipt"] = _receipt_for(campaign_delta)
	var result := event_base.duplicate(true)
	result["advance_id"] = advance_id
	result["advance_receipt"] = advance_receipt
	result["campaign_delta"] = campaign_delta
	result["after_state"] = after_state
	result["transition_receipt"] = _receipt_for(result)
	return result if String(result["transition_receipt"]) != "" else {}


static func validate_epoch_advance(catalog: Dictionary, before_state: Dictionary,
		accepted_before_state_receipt: String, value: Variant) -> Array[String]:
	var expected := advance_epoch(catalog, before_state, accepted_before_state_receipt)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["epoch advance does not derive from accepted campaign state"]
	return []


static func normalize_epoch_advance(catalog: Dictionary, before_state: Dictionary,
		accepted_before_state_receipt: String, value: Variant) -> Dictionary:
	var expected := advance_epoch(catalog, before_state, accepted_before_state_receipt)
	return expected if not expected.is_empty() and value is Dictionary \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func project_consequences(catalog: Dictionary, state: Dictionary,
		accepted_state_receipt: String) -> Dictionary:
	var normalized_state := accept_state_checkpoint(catalog, state, accepted_state_receipt)
	if normalized_state.is_empty():
		return {}
	var delivered_set := {}
	for raw_id in normalized_state["delivered_consequence_ids"]:
		delivered_set[String(raw_id)] = true
	var delivery_by_consequence := {}
	for raw_delivery in normalized_state["delivery_records"]:
		var delivery: Dictionary = raw_delivery
		delivery_by_consequence[String(delivery["consequence_id"])] = delivery
	var pending: Array[Dictionary] = []
	var deliverable: Array[Dictionary] = []
	var delivered: Array[Dictionary] = []
	for raw_consequence in normalized_state["consequence_records"]:
		var consequence: Dictionary = raw_consequence
		var summary := {
			"consequence_id": String(consequence["consequence_id"]),
			"consequence_receipt": String(consequence["consequence_receipt"]),
			"origin_window_id": String(consequence["origin_window_id"]),
			"target_window_id": String(consequence["target_window_id"]),
			"target_region_id": String(consequence["target_region_id"]),
			"kind": String(consequence["kind"]),
			"track": String(consequence["track"]),
			"requested_delta": int(consequence["requested_delta"]),
			"release_epoch": int(consequence["release_epoch"]),
		}
		var consequence_id := String(consequence["consequence_id"])
		if delivered_set.has(consequence_id):
			var delivery: Dictionary = delivery_by_consequence[consequence_id]
			summary["delivery_status"] = String(delivery["status"])
			summary["delivery_record_receipt"] = String(delivery["record_receipt"])
			delivered.append(summary)
		elif int(consequence["release_epoch"]) <= int(normalized_state["epoch_index"]):
			deliverable.append(summary)
		else:
			pending.append(summary)
	var base := {
		"schema": PROJECTION_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(catalog["catalog_id"]),
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"state_receipt": String(normalized_state["state_receipt"]),
		"accepted_state_receipt": accepted_state_receipt,
		"revision": int(normalized_state["revision"]),
		"epoch_index": int(normalized_state["epoch_index"]),
		"phase": String(normalized_state["phase"]),
		"pending": pending,
		"deliverable": deliverable,
		"delivered": delivered,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["projection_id"] = PROJECTION_ID_PREFIX + digest.substr(0, 16)
	base["projection_receipt"] = _receipt_for(base)
	return base if String(base["projection_receipt"]) != "" else {}


static func validate_consequence_projection(catalog: Dictionary, state: Dictionary,
		accepted_state_receipt: String, value: Variant) -> Array[String]:
	var expected := project_consequences(catalog, state, accepted_state_receipt)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["consequence projection does not derive from accepted campaign state"]
	return []


static func normalize_consequence_projection(catalog: Dictionary, state: Dictionary,
		accepted_state_receipt: String, value: Variant) -> Dictionary:
	var expected := project_consequences(catalog, state, accepted_state_receipt)
	return expected if not expected.is_empty() and value is Dictionary \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func deliver_consequence(catalog: Dictionary, before_state: Dictionary,
		accepted_before_state_receipt: String, consequence_id: String,
		target_adapter: Dictionary, target_acceptance: Dictionary,
		global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String) -> Dictionary:
	var normalized_state := accept_state_checkpoint(
		catalog, before_state, accepted_before_state_receipt
	)
	if normalized_state.is_empty() \
			or not _short_id_valid(consequence_id, CONSEQUENCE_ID_PREFIX) \
			or consequence_id in normalized_state["delivered_consequence_ids"] \
			or not _slug_valid(global_network_scope) \
			or not _receipt_token_valid(accepted_global_network_checkpoint_receipt):
		return {}
	var consequence := _state_consequence_by_id(normalized_state, consequence_id)
	if consequence.is_empty() \
			or int(consequence["release_epoch"]) > int(normalized_state["epoch_index"]) \
			or String(consequence["origin_window_id"]) == String(consequence["target_window_id"]):
		return {}
	var origin_record := _state_directive_record_by_id(
		normalized_state, String(consequence["origin_directive_record_id"])
	)
	if origin_record.is_empty() or String(origin_record["global_network_scope"]) \
			!= global_network_scope:
		return {}
	var required_acceptance := ["window_id", "expected_region_scope",
		"accepted_region_checkpoint_receipt", "expected_adapter_receipt"]
	if not _exact_keys(target_acceptance, required_acceptance) \
			or String(target_acceptance.get("window_id", "")) \
			!= String(consequence["target_window_id"]):
		return {}
	var normalized_adapter := normalize_window_adapter(
		catalog, target_adapter, _string_if(target_acceptance.get("expected_region_scope")),
		_string_if(target_acceptance.get("accepted_region_checkpoint_receipt")),
		global_network_scope, accepted_global_network_checkpoint_receipt,
		_string_if(target_acceptance.get("expected_adapter_receipt"))
	)
	if normalized_adapter.is_empty() \
			or String(normalized_adapter["region_scope"]) == global_network_scope \
			or String(normalized_adapter["region_scope"]) \
			!= String(consequence["scheduled_target_region_scope"]) \
			or String(normalized_adapter["window_id"]) != String(consequence["target_window_id"]) \
			or String(normalized_adapter["region_id"]) != String(consequence["target_region_id"]) \
			or String(normalized_adapter["adapter_receipt"]) \
			== String(consequence["scheduled_target_adapter_receipt"]) \
			or String(normalized_adapter["region_checkpoint_receipt"]) \
			== String(consequence["scheduled_target_region_checkpoint_receipt"]):
		return {}
	var target_delta := _make_target_region_delta(normalized_adapter, consequence)
	if target_delta.is_empty():
		return {}
	var delivery_record := _make_delivery_record(
		consequence, normalized_state, normalized_adapter, target_delta,
		global_network_scope, accepted_global_network_checkpoint_receipt
	)
	if delivery_record.is_empty():
		return {}
	var delivery_records: Array = (
		normalized_state["delivery_records"] as Array
	).duplicate(true)
	delivery_records.append(delivery_record)
	delivery_records.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["consequence_id"]) < String(right["consequence_id"]))
	var delivered_ids: Array = (
		normalized_state["delivered_consequence_ids"] as Array
	).duplicate(true)
	delivered_ids.append(consequence_id)
	delivered_ids.sort()
	var after_state := _make_state(
		catalog, int(normalized_state["revision"]) + 1,
		int(normalized_state["epoch_index"]), String(normalized_state["phase"]),
		normalized_state["epoch_records"], normalized_state["directive_records"],
		normalized_state["consumed_commitment_keys"],
		normalized_state["consequence_records"], delivery_records, delivered_ids,
		String(normalized_state["state_receipt"]), String(delivery_record["record_receipt"])
	)
	if after_state.is_empty() or not validate_state(catalog, after_state).is_empty():
		return {}
	var campaign_delta := {
		"before_state_receipt": String(normalized_state["state_receipt"]),
		"after_state_receipt": String(after_state["state_receipt"]),
		"before_revision": int(normalized_state["revision"]),
		"after_revision": int(after_state["revision"]),
		"delivered_consequence_id": consequence_id,
	}
	campaign_delta["delta_receipt"] = _receipt_for(campaign_delta)
	var base := {
		"schema": DELIVERY_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(catalog["catalog_id"]),
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"owner_order": ["campaign", "target_region"],
		"accepted_before_state_receipt": accepted_before_state_receipt,
		"global_network_scope": global_network_scope,
		"accepted_global_network_checkpoint_receipt":
			accepted_global_network_checkpoint_receipt,
		"target_acceptance": target_acceptance.duplicate(true),
		"consequence": consequence,
		"delivery_status": String(delivery_record["status"]),
		"campaign_delta": campaign_delta,
		"target_region_delta": target_delta,
		"delivery_record": delivery_record,
		"after_state": after_state,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["proposal_id"] = DELIVERY_ID_PREFIX + digest.substr(0, 16)
	base["proposal_receipt"] = _receipt_for(base)
	return base if String(base["proposal_receipt"]) != "" else {}


static func validate_consequence_delivery(catalog: Dictionary,
		before_state: Dictionary, accepted_before_state_receipt: String,
		consequence_id: String, target_adapter: Dictionary,
		target_acceptance: Dictionary, global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String,
		value: Variant) -> Array[String]:
	var expected := deliver_consequence(
		catalog, before_state, accepted_before_state_receipt, consequence_id,
		target_adapter, target_acceptance, global_network_scope,
		accepted_global_network_checkpoint_receipt
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["consequence delivery does not derive from fresh target authority"]
	return []


static func normalize_consequence_delivery(catalog: Dictionary,
		before_state: Dictionary, accepted_before_state_receipt: String,
		consequence_id: String, target_adapter: Dictionary,
		target_acceptance: Dictionary, global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String,
		value: Variant) -> Dictionary:
	var expected := deliver_consequence(
		catalog, before_state, accepted_before_state_receipt, consequence_id,
		target_adapter, target_acceptance, global_network_scope,
		accepted_global_network_checkpoint_receipt
	)
	return expected if not expected.is_empty() and value is Dictionary \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func _make_target_region_delta(target_adapter: Dictionary,
		consequence: Dictionary) -> Dictionary:
	var before := _normalize_signals(target_adapter["signals"])
	var track := String(consequence["track"])
	if before.is_empty() or track not in [
		"need_pressure", "security_pressure", "logistics_pressure"
	]:
		return {}
	var requested := int(consequence["requested_delta"])
	var applied := -1 if int(before[track]) > 0 else 0
	var after := before.duplicate(true)
	after[track] = int(before[track]) + applied
	var base := {
		"window_id": String(target_adapter["window_id"]),
		"region_id": String(target_adapter["region_id"]),
		"region_scope": String(target_adapter["region_scope"]),
		"before_region_checkpoint_receipt": String(
			target_adapter["region_checkpoint_receipt"]
		),
		"before_adapter_receipt": String(target_adapter["adapter_receipt"]),
		"status": "applied" if applied != 0 else "superseded",
		"track": track,
		"requested_delta": requested,
		"applied_delta": applied,
		"before_signals": before,
		"after_signals": after,
	}
	base["delta_receipt"] = _receipt_for(base)
	return base if String(base["delta_receipt"]) != "" else {}


static func _make_delivery_record(consequence: Dictionary, state: Dictionary,
		target_adapter: Dictionary, target_delta: Dictionary,
		global_network_scope: String,
		accepted_global_network_checkpoint_receipt: String) -> Dictionary:
	var base := {
		"schema": DELIVERY_RECORD_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"consequence_id": String(consequence["consequence_id"]),
		"consequence_receipt": String(consequence["consequence_receipt"]),
		"delivered_epoch": int(state["epoch_index"]),
		"status": String(target_delta["status"]),
		"target_window_id": String(consequence["target_window_id"]),
		"target_region_id": String(consequence["target_region_id"]),
		"target_region_scope": String(target_adapter["region_scope"]),
		"target_adapter_receipt": String(target_adapter["adapter_receipt"]),
		"target_region_checkpoint_receipt": String(
			target_adapter["region_checkpoint_receipt"]
		),
		"global_network_scope": global_network_scope,
		"global_network_checkpoint_receipt":
			accepted_global_network_checkpoint_receipt,
		"track": String(consequence["track"]),
		"requested_delta": int(consequence["requested_delta"]),
		"applied_delta": int(target_delta["applied_delta"]),
		"target_delta_receipt": String(target_delta["delta_receipt"]),
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["record_id"] = DELIVERY_RECORD_ID_PREFIX + digest.substr(0, 16)
	base["record_receipt"] = _receipt_for(base)
	return base if String(base["record_receipt"]) != "" else {}


static func _state_consequence_by_id(state: Dictionary,
		consequence_id: String) -> Dictionary:
	for raw_consequence in state.get("consequence_records", []):
		if raw_consequence is Dictionary and String((raw_consequence as Dictionary).get(
				"consequence_id", "")) == consequence_id:
			return (raw_consequence as Dictionary).duplicate(true)
	return {}


static func _state_directive_record_by_id(state: Dictionary,
		record_id: String) -> Dictionary:
	for raw_record in state.get("directive_records", []):
		if raw_record is Dictionary and String((raw_record as Dictionary).get(
				"record_id", "")) == record_id:
			return (raw_record as Dictionary).duplicate(true)
	return {}


static func _catalog_self_valid(catalog: Dictionary) -> bool:
	var root_seed_values := _root_seed_from_token(_string_if(catalog.get("root_seed")))
	if root_seed_values.is_empty():
		return false
	var expected := make_catalog(int(root_seed_values[0]))
	return not expected.is_empty() and _canonical_json(expected) == _canonical_json(catalog)


static func _catalog_window_by_key(catalog: Dictionary, window_key: String) -> Dictionary:
	for raw_window in catalog.get("windows", []):
		if raw_window is Dictionary and String((raw_window as Dictionary).get(
				"window_key", "")) == window_key:
			return (raw_window as Dictionary).duplicate(true)
	return {}


static func _catalog_window_by_id(catalog: Dictionary, window_id: String) -> Dictionary:
	for raw_window in catalog.get("windows", []):
		if raw_window is Dictionary and String((raw_window as Dictionary).get(
				"window_id", "")) == window_id:
			return (raw_window as Dictionary).duplicate(true)
	return {}


static func _catalog_directive_by_id(catalog: Dictionary, directive_id: String) -> Dictionary:
	for raw_directive in catalog.get("directives", []):
		if raw_directive is Dictionary and String((raw_directive as Dictionary).get(
				"directive_id", "")) == directive_id:
			return (raw_directive as Dictionary).duplicate(true)
	return {}


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


static func _season_for(epoch_index: int, phase: String) -> String:
	if phase == "terminal":
		return "closed"
	return String(SEASONS[epoch_index]) if epoch_index >= 0 \
		and epoch_index < SEASONS.size() else ""


static func _normalize_record_array(value: Array, integer_keys: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_record in value:
		if not (raw_record is Dictionary):
			return []
		var record: Dictionary = (raw_record as Dictionary).duplicate(true)
		for raw_key in integer_keys:
			var key := String(raw_key)
			if record.has(key):
				record[key] = int(record[key])
		result.append(record)
	return result


static func _epoch_records_valid(records: Array, epoch_index: int, phase: String) -> bool:
	var expected_count := epoch_index + (1 if phase == "committed" else 0)
	if records.size() != expected_count or records.size() > TERMINAL_EPOCH:
		return false
	var directive_count := 0
	for index in records.size():
		if not (records[index] is Dictionary):
			return false
		var record: Dictionary = records[index]
		var required := ["schema", "terms_revision", "epoch_index", "season",
			"resolution", "directive_record_id", "directive_record_receipt",
			"record_id", "record_receipt"]
		if not _exact_keys(record, required) or record.get("schema") != EPOCH_RECORD_SCHEMA \
				or record.get("terms_revision") != TERMS_REVISION \
				or not _bounded_int(record.get("epoch_index"), 0, TERMINAL_EPOCH - 1) \
				or int(record["epoch_index"]) != index \
				or String(record.get("season", "")) != String(SEASONS[index]) \
				or String(record.get("resolution", "")) not in ["directive", "deferred"] \
				or not _short_id_valid(_string_if(record.get("record_id")), EPOCH_RECORD_ID_PREFIX) \
				or not _receipt_token_valid(_string_if(record.get("record_receipt"))):
			return false
		if String(record["resolution"]) == "directive":
			directive_count += 1
			if not _short_id_valid(_string_if(record.get("directive_record_id")),
					DIRECTIVE_RECORD_ID_PREFIX) \
					or not _receipt_token_valid(_string_if(record.get("directive_record_receipt"))):
				return false
		elif String(record.get("directive_record_id", "")) != "" \
				or String(record.get("directive_record_receipt", "")) != "":
			return false
		var base := record.duplicate(true)
		base.erase("record_id")
		base.erase("record_receipt")
		var digest := _sha256_hex(_canonical_json(base))
		if digest == "" or String(record["record_id"]) \
				!= EPOCH_RECORD_ID_PREFIX + digest.substr(0, 16):
			return false
		var receipt_base := record.duplicate(true)
		receipt_base.erase("record_receipt")
		if String(record["record_receipt"]) != _receipt_for(receipt_base):
			return false
	return directive_count <= records.size()


static func _directive_records_valid(catalog: Dictionary, epoch_records: Array,
		records: Array) -> bool:
	var epoch_links := {}
	for raw_epoch in epoch_records:
		var epoch_record: Dictionary = raw_epoch
		if String(epoch_record["resolution"]) == "directive":
			epoch_links[String(epoch_record["directive_record_id"])] = {
				"record_receipt": String(epoch_record["directive_record_receipt"]),
				"epoch_index": int(epoch_record["epoch_index"]),
			}
	if records.size() != epoch_links.size() or records.size() > TERMINAL_EPOCH:
		return false
	var seen_ids := {}
	var seen_epochs := {}
	var previous := ""
	for raw_record in records:
		if not (raw_record is Dictionary):
			return false
		var record: Dictionary = raw_record
		var required := ["schema", "terms_revision", "catalog_receipt",
			"epoch_index", "season", "directive_id", "directive_receipt", "action",
			"origin_window_id", "origin_region_id", "origin_region_scope", "target_window_id",
			"target_region_id", "faction_id", "commitment_replay_key",
			"command_owner_scope", "command_owner_checkpoint_receipt",
			"command_anchor_receipt", "global_network_scope",
			"global_network_checkpoint_receipt", "origin_adapter_receipt",
			"origin_region_checkpoint_receipt", "capacity_cost",
			"primary_track", "primary_requested", "primary_applied",
			"faction_requested", "faction_applied", "origin_delta_receipt",
			"consequence_release_epoch", "choice_receipt", "record_id", "record_receipt"]
		if not _exact_keys(record, required) or record.get("schema") != DIRECTIVE_RECORD_SCHEMA \
				or record.get("terms_revision") != TERMS_REVISION \
				or record.get("catalog_receipt") != catalog.get("catalog_receipt") \
				or not _bounded_int(record.get("epoch_index"), 0, TERMINAL_EPOCH - 1) \
				or String(record.get("season", "")) != String(SEASONS[int(record["epoch_index"])]) \
				or not _bounded_int(record.get("capacity_cost"), 2, 3) \
				or not _bounded_int(record.get("primary_requested"), -3, -2) \
				or not _bounded_int(record.get("primary_applied"), -3, 0) \
				or not _bounded_int(record.get("faction_requested"), 1, 1) \
				or not _bounded_int(record.get("faction_applied"), 0, 1) \
				or not _bounded_int(record.get("consequence_release_epoch"), 1, TERMINAL_EPOCH) \
				or not _receipt_token_valid(_string_if(record.get("record_receipt"))):
			return false
		var record_id := _string_if(record.get("record_id"))
		if not _short_id_valid(record_id, DIRECTIVE_RECORD_ID_PREFIX) \
				or seen_ids.has(record_id) or (previous != "" and record_id <= previous) \
				or seen_epochs.has(int(record["epoch_index"])):
			return false
		seen_ids[record_id] = true
		seen_epochs[int(record["epoch_index"])] = true
		previous = record_id
		var directive := _catalog_directive_by_id(catalog, _string_if(record.get("directive_id")))
		var favored := String(record.get("season", "")) == String(
			directive.get("favored_season", "")
		)
		var expected_capacity_cost := 2 if favored else 3
		var expected_primary_requested := -3 if favored else -2
		if directive.is_empty() or String(record.get("directive_receipt", "")) \
				!= String(directive["directive_receipt"]) \
				or String(record.get("action", "")) != String(directive["action"]) \
				or String(record.get("origin_window_id", "")) != String(directive["origin_window_id"]) \
				or String(record.get("origin_region_id", "")) != String(directive["origin_region_id"]) \
				or String(record.get("target_window_id", "")) != String(directive["target_window_id"]) \
				or String(record.get("target_region_id", "")) != String(directive["target_region_id"]) \
				or String(record.get("faction_id", "")) != String(directive["faction_id"]) \
				or String(record.get("primary_track", "")) != String(directive["primary_track"]) \
				or int(record["capacity_cost"]) != expected_capacity_cost \
				or int(record["primary_requested"]) != expected_primary_requested \
				or int(record["primary_applied"]) < int(record["primary_requested"]) \
				or int(record["consequence_release_epoch"]) != int(record["epoch_index"]) + 1:
			return false
		for receipt_key in ["commitment_replay_key", "command_owner_checkpoint_receipt",
				"command_anchor_receipt",
				"global_network_checkpoint_receipt", "origin_adapter_receipt",
				"origin_region_checkpoint_receipt", "origin_delta_receipt", "choice_receipt"]:
			if not _receipt_token_valid(_string_if(record.get(receipt_key))):
				return false
		if not _slug_valid(_string_if(record.get("global_network_scope"))) \
				or not _slug_valid(_string_if(record.get("command_owner_scope"))) \
				or not _slug_valid(_string_if(record.get("origin_region_scope"))):
			return false
		var record_scopes := {
			String(record["global_network_scope"]): true,
			String(record["command_owner_scope"]): true,
			String(record["origin_region_scope"]): true,
		}
		if record_scopes.size() != 3 \
				or String(record["commitment_replay_key"]) != _receipt_for([
					String(record["command_owner_scope"]),
					String(record["command_owner_checkpoint_receipt"]),
				]):
			return false
		if int(record["primary_applied"]) == 0 and int(record["faction_applied"]) == 0:
			return false
		var base := record.duplicate(true)
		base.erase("record_id")
		base.erase("record_receipt")
		var digest := _sha256_hex(_canonical_json(base))
		if digest == "" or record_id != DIRECTIVE_RECORD_ID_PREFIX + digest.substr(0, 16):
			return false
		var receipt_base := record.duplicate(true)
		receipt_base.erase("record_receipt")
		if not epoch_links.has(record_id):
			return false
		var epoch_link: Dictionary = epoch_links[record_id]
		if String(record["record_receipt"]) != _receipt_for(receipt_base) \
				or String(epoch_link["record_receipt"]) != String(record["record_receipt"]) \
				or int(epoch_link["epoch_index"]) != int(record["epoch_index"]):
			return false
	return true


static func _consequence_records_valid(catalog: Dictionary, directive_records: Array,
		records: Array) -> bool:
	if records.size() != directive_records.size() or records.size() > TERMINAL_EPOCH:
		return false
	var directives_by_record := {}
	for raw_directive in directive_records:
		var directive_record: Dictionary = raw_directive
		directives_by_record[String(directive_record["record_id"])] = directive_record
	var seen := {}
	var seen_origins := {}
	var previous := ""
	for raw_record in records:
		if not (raw_record is Dictionary):
			return false
		var record: Dictionary = raw_record
		var required := ["schema", "terms_revision", "catalog_receipt", "origin_epoch",
			"release_epoch", "origin_directive_record_id", "origin_directive_record_receipt",
			"origin_choice_receipt", "origin_window_id", "origin_region_id",
			"target_window_id", "target_region_id", "scheduled_target_adapter_receipt",
			"scheduled_target_region_scope", "scheduled_target_region_checkpoint_receipt",
			"kind", "track",
			"requested_delta", "consequence_id", "consequence_receipt"]
		if not _exact_keys(record, required) or record.get("schema") != CONSEQUENCE_SCHEMA \
				or record.get("terms_revision") != TERMS_REVISION \
				or record.get("catalog_receipt") != catalog.get("catalog_receipt") \
				or not _bounded_int(record.get("origin_epoch"), 0, TERMINAL_EPOCH - 1) \
				or not _bounded_int(record.get("release_epoch"), 1, TERMINAL_EPOCH) \
				or int(record["release_epoch"]) != int(record["origin_epoch"]) + 1 \
				or not _bounded_int(record.get("requested_delta"), -1, -1):
			return false
		var consequence_id := _string_if(record.get("consequence_id"))
		if not _short_id_valid(consequence_id, CONSEQUENCE_ID_PREFIX) \
				or seen.has(consequence_id) or (previous != "" and consequence_id <= previous) \
				or not _receipt_token_valid(_string_if(record.get("consequence_receipt"))):
			return false
		seen[consequence_id] = true
		previous = consequence_id
		var origin_record_id := _string_if(record.get("origin_directive_record_id"))
		if not directives_by_record.has(origin_record_id) or seen_origins.has(origin_record_id):
			return false
		seen_origins[origin_record_id] = true
		var origin_record: Dictionary = directives_by_record[origin_record_id]
		var directive := _catalog_directive_by_id(catalog, String(origin_record["directive_id"]))
		if directive.is_empty() or String(record.get("origin_directive_record_receipt", "")) \
				!= String(origin_record["record_receipt"]) \
				or String(record.get("origin_choice_receipt", "")) != String(origin_record["choice_receipt"]) \
				or int(record["origin_epoch"]) != int(origin_record["epoch_index"]) \
				or String(record.get("origin_window_id", "")) != String(directive["origin_window_id"]) \
				or String(record.get("origin_region_id", "")) != String(directive["origin_region_id"]) \
				or String(record.get("target_window_id", "")) != String(directive["target_window_id"]) \
				or String(record.get("target_region_id", "")) != String(directive["target_region_id"]) \
				or String(record.get("kind", "")) != String(directive["consequence_kind"]) \
				or String(record.get("track", "")) != String(directive["consequence_track"]):
			return false
		for receipt_key in ["origin_directive_record_receipt", "origin_choice_receipt",
				"scheduled_target_adapter_receipt",
				"scheduled_target_region_checkpoint_receipt"]:
			if not _receipt_token_valid(_string_if(record.get(receipt_key))):
				return false
		if not _slug_valid(_string_if(record.get("scheduled_target_region_scope"))):
			return false
		var target_scope := String(record["scheduled_target_region_scope"])
		if target_scope in [String(origin_record["global_network_scope"]),
				String(origin_record["command_owner_scope"]),
				String(origin_record["origin_region_scope"])]:
			return false
		var base := record.duplicate(true)
		base.erase("consequence_id")
		base.erase("consequence_receipt")
		var digest := _sha256_hex(_canonical_json(base))
		if digest == "" or consequence_id != CONSEQUENCE_ID_PREFIX + digest.substr(0, 16):
			return false
		var receipt_base := record.duplicate(true)
		receipt_base.erase("consequence_receipt")
		if String(record["consequence_receipt"]) != _receipt_for(receipt_base):
			return false
	return seen_origins.size() == directives_by_record.size()


static func _delivery_records_valid(consequence_records: Array,
		directive_records: Array, records: Array, current_epoch: int) -> bool:
	if records.size() > consequence_records.size() or records.size() > TERMINAL_EPOCH:
		return false
	var consequence_by_id := {}
	for raw_consequence in consequence_records:
		var consequence: Dictionary = raw_consequence
		consequence_by_id[String(consequence["consequence_id"])] = consequence
	var directive_by_id := {}
	for raw_directive in directive_records:
		var directive: Dictionary = raw_directive
		directive_by_id[String(directive["record_id"])] = directive
	var seen := {}
	var previous := ""
	for raw_record in records:
		if not (raw_record is Dictionary):
			return false
		var record: Dictionary = raw_record
		var required := ["schema", "terms_revision", "consequence_id",
			"consequence_receipt", "delivered_epoch", "status", "target_window_id",
			"target_region_id", "target_region_scope", "target_adapter_receipt",
			"target_region_checkpoint_receipt", "global_network_scope",
			"global_network_checkpoint_receipt", "track", "requested_delta",
			"applied_delta", "target_delta_receipt", "record_id", "record_receipt"]
		if not _exact_keys(record, required) or record.get("schema") != DELIVERY_RECORD_SCHEMA \
				or record.get("terms_revision") != TERMS_REVISION \
				or not _bounded_int(record.get("delivered_epoch"), 1, current_epoch) \
				or String(record.get("status", "")) not in ["applied", "superseded"] \
				or not _bounded_int(record.get("requested_delta"), -1, -1) \
				or not _bounded_int(record.get("applied_delta"), -1, 0):
			return false
		if (String(record["status"]) == "applied") != (int(record["applied_delta"]) == -1):
			return false
		var record_id := _string_if(record.get("record_id"))
		var consequence_id := _string_if(record.get("consequence_id"))
		if not _short_id_valid(record_id, DELIVERY_RECORD_ID_PREFIX) \
				or not _short_id_valid(consequence_id, CONSEQUENCE_ID_PREFIX) \
				or not consequence_by_id.has(consequence_id) or seen.has(consequence_id) \
				or (previous != "" and consequence_id <= previous):
			return false
		seen[consequence_id] = true
		previous = consequence_id
		var consequence: Dictionary = consequence_by_id[consequence_id]
		var origin_record_id := String(consequence["origin_directive_record_id"])
		if not directive_by_id.has(origin_record_id):
			return false
		var origin_record: Dictionary = directive_by_id[origin_record_id]
		if String(record.get("consequence_receipt", "")) != String(consequence["consequence_receipt"]) \
				or int(record["delivered_epoch"]) < int(consequence["release_epoch"]) \
				or String(record.get("target_window_id", "")) != String(consequence["target_window_id"]) \
				or String(record.get("target_region_id", "")) != String(consequence["target_region_id"]) \
				or String(record.get("target_region_scope", "")) \
				!= String(consequence["scheduled_target_region_scope"]) \
				or String(record.get("global_network_scope", "")) \
				!= String(origin_record["global_network_scope"]) \
				or String(record.get("track", "")) != String(consequence["track"]) \
				or String(record.get("target_adapter_receipt", "")) \
				== String(consequence["scheduled_target_adapter_receipt"]) \
				or String(record.get("target_region_checkpoint_receipt", "")) \
				== String(consequence["scheduled_target_region_checkpoint_receipt"]):
			return false
		for receipt_key in ["consequence_receipt", "target_adapter_receipt",
				"target_region_checkpoint_receipt", "global_network_checkpoint_receipt",
				"target_delta_receipt", "record_receipt"]:
			if not _receipt_token_valid(_string_if(record.get(receipt_key))):
				return false
		if not _slug_valid(_string_if(record.get("global_network_scope"))) \
				or not _slug_valid(_string_if(record.get("target_region_scope"))):
			return false
		var base := record.duplicate(true)
		base.erase("record_id")
		base.erase("record_receipt")
		var digest := _sha256_hex(_canonical_json(base))
		if digest == "" or record_id != DELIVERY_RECORD_ID_PREFIX + digest.substr(0, 16):
			return false
		var receipt_base := record.duplicate(true)
		receipt_base.erase("record_receipt")
		if String(record["record_receipt"]) != _receipt_for(receipt_base):
			return false
	return true


static func _sorted_unique_receipts(value: Array) -> bool:
	var previous := ""
	for index in value.size():
		if typeof(value[index]) != TYPE_STRING \
				or not _receipt_token_valid(String(value[index])) \
				or (index > 0 and String(value[index]) <= previous):
			return false
		previous = String(value[index])
	return true


static func _sorted_unique_short_ids(value: Array, prefix: String) -> bool:
	var previous := ""
	for index in value.size():
		if typeof(value[index]) != TYPE_STRING \
				or not _short_id_valid(String(value[index]), prefix) \
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


static func _root_seed_from_token(token: String) -> Array:
	if not token.begins_with("i64:"):
		return []
	var number_text := token.substr(4)
	return [int(number_text)] if _canonical_i64(number_text) else []


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
	return digits.length() < limit.length() \
		or (digits.length() == limit.length() and digits <= limit)


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
