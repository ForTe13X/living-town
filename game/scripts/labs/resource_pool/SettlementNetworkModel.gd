extends RefCounted

## RP-0006: deterministic, owner-independent aggregate settlement network.
## This model owns only coarse network campaign state and pure proposals. It
## never mutates caravan cargo, Sim economy/social state, RegionRoute roads, or
## detailed site state.

const ScaleAddress = preload("res://scripts/labs/resource_pool/ScaleAddress.gd")
const RegionRouteModel = preload("res://scripts/labs/resource_pool/RegionRouteModel.gd")

const CATALOG_SCHEMA := "living-town.settlement-network-catalog/v1"
const STATE_SCHEMA := "living-town.settlement-network-state/v1"
const CARGO_SCHEMA := "living-town.settlement-cargo-anchor/v1"
const BOARD_SCHEMA := "living-town.settlement-offer-board/v1"
const CHOICE_SCHEMA := "living-town.settlement-choice/v1"
const ARRIVAL_SCHEMA := "living-town.settlement-arrival/v1"
const TRANSITION_SCHEMA := "living-town.settlement-transition/v1"
const INTEL_PROJECTION_SCHEMA := "living-town.settlement-intel-projection/v1"
const INTEL_RECORD_SCHEMA := "living-town.settlement-intel-record/v1"
const SOURCE_REF_SCHEMA := "living-town.settlement-cargo-source-ref/v1"
const TERMS_REVISION := "ashfall-settlement-network-v1"

const CATALOG_ID_PREFIX := "snc1:"
const OFFER_ID_PREFIX := "sno1:"
const ANCHOR_ID_PREFIX := "sca1:"
const BOARD_ID_PREFIX := "snb1:"
const CHOICE_ID_PREFIX := "snd1:"
const ARRIVAL_ID_PREFIX := "sna1:"
const TRANSITION_ID_PREFIX := "snt1:"
const INTEL_ID_PREFIX := "sni1:"
const PROJECTION_ID_PREFIX := "snp1:"

const MAX_SAFE_JSON_INT := 9007199254740991
const MAX_CARGO_PER_KIND := 64
const MAX_TOTAL_CARGO := 128
const MAX_SUPPLY_TENTHS := 240
const MAX_NETWORK_TRANSITIONS := 32
const MAX_SOURCE_REFS := 8
const MAX_INTEL_RECORDS := 16
const MAX_TRACK := 3


## Static authored profiles are returned fresh on every call. No Dictionary or
## Array is retained as mutable process-wide state.
static func _profile_specs() -> Dictionary:
	return {
		"cinder_crossing": {
			"site_kind": "haven", "need_pressure": 2,
			"security_pressure": 1, "reciprocity": 0,
		},
		"orra_relay": {
			"site_kind": "relay", "need_pressure": 1,
			"security_pressure": 3, "reciprocity": 0,
		},
		"saint_vey_clinic": {
			"site_kind": "clinic", "need_pressure": 3,
			"security_pressure": 1, "reciprocity": 0,
		},
		"dunlin_homestead": {
			"site_kind": "farm", "need_pressure": 1,
			"security_pressure": 1, "reciprocity": 0,
		},
	}


static func _offer_specs() -> Array[Dictionary]:
	return [
		{
			"offer_key": "cinder_food_aid", "site_key": "cinder_crossing",
			"action": "aid", "good": "food", "quantity": 2,
			"need_delta": -1, "security_delta": 0, "reciprocity_delta": 1,
			"supply_gain_tenths": 0, "intel_key": "ash_market_survivors",
			"intel_subject_key": "ash_market", "intel_topic": "survivor_rumor",
		},
		{
			"offer_key": "saint_vey_generator_aid", "site_key": "saint_vey_clinic",
			"action": "aid", "good": "parts", "quantity": 2,
			"need_delta": -2, "security_delta": 0, "reciprocity_delta": 2,
			"supply_gain_tenths": 0, "intel_key": "ash_market_medical_window",
			"intel_subject_key": "ash_market", "intel_topic": "medical_salvage_window",
		},
		{
			"offer_key": "dunlin_parts_trade", "site_key": "dunlin_homestead",
			"action": "trade", "good": "parts", "quantity": 2,
			"need_delta": 0, "security_delta": 0, "reciprocity_delta": 0,
			"supply_gain_tenths": 30, "intel_key": "",
			"intel_subject_key": "", "intel_topic": "",
		},
		{
			"offer_key": "orra_relay_fortification", "site_key": "orra_relay",
			"action": "fortify", "good": "parts", "quantity": 2,
			"need_delta": 0, "security_delta": -2, "reciprocity_delta": 1,
			"supply_gain_tenths": 0, "intel_key": "redglass_route_watch",
			"intel_subject_key": "redglass_quarry", "intel_topic": "quarry_route_activity",
		},
	]


static func make_catalog(atlas: Dictionary) -> Dictionary:
	var normalized_atlas: Dictionary = RegionRouteModel.normalize_atlas(atlas)
	if normalized_atlas.is_empty():
		return {}
	var root_seed_values := _root_seed_from_token(String(normalized_atlas["root_seed"]))
	if root_seed_values.is_empty():
		return {}
	var root_seed := int(root_seed_values[0])
	var profiles := _profile_specs()
	var site_by_key := {}
	var nodes: Array[Dictionary] = []
	var context_sites: Array[Dictionary] = []
	for raw_tile in normalized_atlas["tiles"]:
		var tile: Dictionary = raw_tile
		var site_key := String(tile["site_key"])
		if site_key == "":
			continue
		site_by_key[site_key] = tile
		if bool(tile["safe_stop"]) and profiles.has(site_key):
			var profile: Dictionary = profiles[site_key]
			if String(tile["site_kind"]) != String(profile["site_kind"]):
				return {}
			var site_address := ScaleAddress.parse_id(String(tile["site_id"]))
			if ScaleAddress.level_of(site_address) != ScaleAddress.LEVEL_SITE:
				return {}
			var seed_receipts := {
				"profile": ScaleAddress.receipt(root_seed, site_address,
					"settlement-profile-%s" % TERMS_REVISION),
				"offers": ScaleAddress.receipt(root_seed, site_address,
					"settlement-offers-%s" % TERMS_REVISION),
				"intel": ScaleAddress.receipt(root_seed, site_address,
					"settlement-intel-%s" % TERMS_REVISION),
			}
			if (seed_receipts["profile"] as Dictionary).is_empty() \
					or (seed_receipts["offers"] as Dictionary).is_empty() \
					or (seed_receipts["intel"] as Dictionary).is_empty():
				return {}
			nodes.append({
				"node_id": String(tile["site_id"]),
				"tile_id": String(tile["id"]),
				"site_key": site_key,
				"site_kind": String(tile["site_kind"]),
				"seed_receipts": seed_receipts,
				"initial_need_pressure": int(profile["need_pressure"]),
				"initial_security_pressure": int(profile["security_pressure"]),
				"initial_reciprocity": int(profile["reciprocity"]),
				"offer_ids": [],
			})
		elif not bool(tile["safe_stop"]) and String(tile["site_kind"]) in ["ruins", "quarry"]:
			context_sites.append({
				"site_id": String(tile["site_id"]),
				"tile_id": String(tile["id"]),
				"site_key": site_key,
				"site_kind": String(tile["site_kind"]),
				"role": "source" if String(tile["site_kind"]) == "ruins" else "source_target",
			})
	if nodes.size() != profiles.size() or context_sites.size() != 2:
		return {}
	nodes.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["node_id"]) < String(right["node_id"]))
	context_sites.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["site_id"]) < String(right["site_id"]))
	var node_by_key := {}
	var node_index_by_id := {}
	for index in nodes.size():
		var node: Dictionary = nodes[index]
		node_by_key[String(node["site_key"])] = node
		node_index_by_id[String(node["node_id"])] = index
	var context_by_key := {}
	for raw_context in context_sites:
		var context: Dictionary = raw_context
		context_by_key[String(context["site_key"])] = context
	var offers: Array[Dictionary] = []
	var offer_ids_seen := {}
	var offer_receipts_seen := {}
	for spec in _offer_specs():
		var node_key := String(spec["site_key"])
		if not node_by_key.has(node_key):
			return {}
		var node: Dictionary = node_by_key[node_key]
		var intel_subject_key := String(spec["intel_subject_key"])
		if intel_subject_key != "" and not context_by_key.has(intel_subject_key):
			return {}
		var subject_id := "" if intel_subject_key == "" \
			else String((context_by_key[intel_subject_key] as Dictionary)["site_id"])
		var offer_base := {
			"offer_key": String(spec["offer_key"]),
			"node_id": String(node["node_id"]),
			"action": String(spec["action"]),
			"cost": {"good": String(spec["good"]), "quantity": int(spec["quantity"])},
			"effect": {
				"need_delta": int(spec["need_delta"]),
				"security_delta": int(spec["security_delta"]),
				"reciprocity_delta": int(spec["reciprocity_delta"]),
			},
			"owner_reward": {"supply_gain_tenths": int(spec["supply_gain_tenths"])},
			"intel_template": {
				"intel_key": String(spec["intel_key"]),
				"subject_site_id": subject_id,
				"topic": String(spec["intel_topic"]),
				"delay_revisions": 1 if String(spec["intel_key"]) != "" else 0,
			},
		}
		var digest := _sha256_hex(_canonical_json([
			TERMS_REVISION, String(normalized_atlas["atlas_receipt"]), offer_base,
		]))
		if digest == "":
			return {}
		var offer := offer_base.duplicate(true)
		offer["offer_id"] = OFFER_ID_PREFIX + digest.substr(0, 16)
		offer["offer_receipt"] = _receipt_for({
			"terms_revision": TERMS_REVISION,
			"atlas_receipt": String(normalized_atlas["atlas_receipt"]),
			"offer": offer_base,
		})
		if String(offer["offer_receipt"]) == "":
			return {}
		if offer_ids_seen.has(String(offer["offer_id"])) \
				or offer_receipts_seen.has(String(offer["offer_receipt"])):
			return {}
		offer_ids_seen[String(offer["offer_id"])] = true
		offer_receipts_seen[String(offer["offer_receipt"])] = true
		offers.append(offer)
		var node_index := int(node_index_by_id[String(node["node_id"])])
		(nodes[node_index]["offer_ids"] as Array).append(String(offer["offer_id"]))
	offers.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["offer_id"]) < String(right["offer_id"]))
	for node in nodes:
		(node["offer_ids"] as Array).sort()
	var base := {
		"schema": CATALOG_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"atlas_id": String(normalized_atlas["atlas_id"]),
		"atlas_receipt": String(normalized_atlas["atlas_receipt"]),
		"network_revision": String(normalized_atlas["network_revision"]),
		"root_seed": String(normalized_atlas["root_seed"]),
		"nodes": nodes,
		"offers": offers,
		"context_sites": context_sites,
	}
	var catalog_digest := _sha256_hex(_canonical_json(base))
	if catalog_digest == "":
		return {}
	base["catalog_id"] = CATALOG_ID_PREFIX + catalog_digest.substr(0, 16)
	base["catalog_receipt"] = "sha256:" + catalog_digest
	return base


static func validate_catalog(atlas: Dictionary, value: Variant) -> Array[String]:
	if not (value is Dictionary):
		return ["settlement catalog must be a Dictionary"]
	var data: Dictionary = value
	var required := ["schema", "terms_revision", "atlas_id", "atlas_receipt",
		"network_revision", "root_seed", "nodes", "offers", "context_sites",
		"catalog_id", "catalog_receipt"]
	if not _exact_keys(data, required) or not (data.get("nodes") is Array) \
			or not (data.get("offers") is Array) or not (data.get("context_sites") is Array):
		return ["settlement catalog fields must match V1 exactly"]
	var expected := make_catalog(atlas)
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(data):
		return ["settlement catalog does not match its deterministic atlas contract"]
	return []


static func normalize_catalog(atlas: Dictionary, value: Variant) -> Dictionary:
	var expected := make_catalog(atlas)
	return expected if not expected.is_empty() and _canonical_json(expected) == _canonical_json(value) else {}


static func make_initial_state(catalog: Dictionary) -> Dictionary:
	if not _catalog_self_valid(catalog):
		return {}
	var nodes: Array[Dictionary] = []
	for raw_node in catalog["nodes"]:
		var node: Dictionary = raw_node
		nodes.append({
			"node_id": String(node["node_id"]),
			"need_pressure": int(node["initial_need_pressure"]),
			"security_pressure": int(node["initial_security_pressure"]),
			"reciprocity": int(node["initial_reciprocity"]),
		})
	return _make_state(
		catalog, 0, nodes, [], [], [], "", ""
	)


static func validate_state(catalog: Dictionary, value: Variant) -> Array[String]:
	if not _catalog_self_valid(catalog):
		return ["settlement state requires a valid catalog"]
	if not (value is Dictionary):
		return ["settlement state must be a Dictionary"]
	var data: Dictionary = value
	var required := ["schema", "terms_revision", "catalog_id", "catalog_receipt",
		"revision", "nodes", "settled_offer_ids", "consumed_cargo_anchor_keys",
		"intel_records", "parent_state_receipt", "last_choice_receipt", "state_receipt"]
	if not _exact_keys(data, required) or not (data.get("nodes") is Array) \
			or not (data.get("settled_offer_ids") is Array) \
			or not (data.get("consumed_cargo_anchor_keys") is Array) \
			or not (data.get("intel_records") is Array):
		return ["settlement state fields must match V1 exactly"]
	if data.get("schema") != STATE_SCHEMA or data.get("terms_revision") != TERMS_REVISION \
			or data.get("catalog_id") != catalog.get("catalog_id") \
			or data.get("catalog_receipt") != catalog.get("catalog_receipt"):
		return ["settlement state catalog identity mismatch"]
	if not _bounded_int(data.get("revision"), 0, MAX_NETWORK_TRANSITIONS):
		return ["settlement state revision must be bounded"]
	var revision := int(data["revision"])
	var settled: Array = data["settled_offer_ids"]
	var consumed: Array = data["consumed_cargo_anchor_keys"]
	if settled.size() != revision or consumed.size() != revision \
			or not _sorted_unique_offer_ids(catalog, settled) \
			or not _sorted_unique_receipts(consumed):
		return ["settlement state replay ledgers must be sorted, unique, and revision-sized"]
	var expected_nodes := _expected_nodes_for_settled(catalog, settled)
	if expected_nodes.is_empty() or _canonical_json(expected_nodes) != _canonical_json(data["nodes"]):
		return ["settlement node tracks do not derive from settled offers"]
	var intel_records: Array = data["intel_records"]
	if intel_records.size() > MAX_INTEL_RECORDS or not _intel_records_valid(catalog, settled, intel_records, revision):
		return ["settlement intel records are invalid"]
	if typeof(data.get("parent_state_receipt")) != TYPE_STRING \
			or typeof(data.get("last_choice_receipt")) != TYPE_STRING \
			or typeof(data.get("state_receipt")) != TYPE_STRING:
		return ["settlement state receipt fields must be Strings"]
	if revision == 0:
		if String(data["parent_state_receipt"]) != "" or String(data["last_choice_receipt"]) != "":
			return ["initial settlement state cannot have a parent or choice"]
	else:
		if not _receipt_token_valid(String(data["parent_state_receipt"])) \
				or not _receipt_token_valid(String(data["last_choice_receipt"])):
			return ["settlement state chain receipts are invalid"]
	var base := data.duplicate(true)
	base.erase("state_receipt")
	if String(data["state_receipt"]) != _receipt_for(base):
		return ["settlement state receipt mismatch"]
	return []


static func normalize_state(catalog: Dictionary, value: Variant) -> Dictionary:
	if not validate_state(catalog, value).is_empty():
		return {}
	var data: Dictionary = value
	var result := data.duplicate(true)
	result["revision"] = int(data["revision"])
	var nodes: Array[Dictionary] = []
	for raw_node in data["nodes"]:
		var node: Dictionary = raw_node
		nodes.append({
			"node_id": String(node["node_id"]),
			"need_pressure": int(node["need_pressure"]),
			"security_pressure": int(node["security_pressure"]),
			"reciprocity": int(node["reciprocity"]),
		})
	result["nodes"] = nodes
	var records: Array[Dictionary] = []
	for raw_record in data["intel_records"]:
		records.append(_normalize_intel_record(raw_record as Dictionary))
	result["intel_records"] = records
	return result


static func accept_state_checkpoint(catalog: Dictionary, value: Variant,
		expected_state_receipt: String) -> Dictionary:
	if not _receipt_token_valid(expected_state_receipt):
		return {}
	var normalized := normalize_state(catalog, value)
	return normalized if not normalized.is_empty() \
		and String(normalized["state_receipt"]) == expected_state_receipt else {}


static func make_cargo_anchor(owner_scope: String, owner_checkpoint_receipt: String,
		cargo_before: Dictionary, supply_before_tenths: int, source_refs: Array = []) -> Dictionary:
	if not _slug_valid(owner_scope) or not _receipt_token_valid(owner_checkpoint_receipt) \
			or not _bounded_int(supply_before_tenths, 0, MAX_SUPPLY_TENTHS):
		return {}
	var cargo := _normalize_cargo(cargo_before)
	if cargo.is_empty() or not _source_refs_valid(source_refs):
		return {}
	var refs := _normalize_source_refs(source_refs)
	var replay_key := _receipt_for([owner_scope, owner_checkpoint_receipt])
	if replay_key == "":
		return {}
	var base := {
		"schema": CARGO_SCHEMA,
		"owner_scope": owner_scope,
		"owner_checkpoint_receipt": owner_checkpoint_receipt,
		"cargo_before": cargo,
		"supply_before_tenths": int(supply_before_tenths),
		"source_refs": refs,
		"replay_key": replay_key,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["anchor_id"] = ANCHOR_ID_PREFIX + digest.substr(0, 16)
	base["anchor_receipt"] = _receipt_for(base)
	return base if String(base["anchor_receipt"]) != "" else {}


static func validate_cargo_anchor(value: Variant, expected_owner_scope: String,
		expected_owner_checkpoint_receipt: String) -> Array[String]:
	if not _slug_valid(expected_owner_scope) \
			or not _receipt_token_valid(expected_owner_checkpoint_receipt):
		return ["cargo anchor requires an external owner scope and checkpoint receipt"]
	if not (value is Dictionary):
		return ["cargo anchor must be a Dictionary"]
	var data: Dictionary = value
	var required := ["schema", "owner_scope", "owner_checkpoint_receipt", "cargo_before",
		"supply_before_tenths", "source_refs", "replay_key", "anchor_id", "anchor_receipt"]
	if not _exact_keys(data, required) or not (data.get("cargo_before") is Dictionary) \
			or not (data.get("source_refs") is Array):
		return ["cargo anchor fields must match V1 exactly"]
	if typeof(data.get("owner_scope")) != TYPE_STRING \
			or typeof(data.get("owner_checkpoint_receipt")) != TYPE_STRING:
		return ["cargo anchor owner fields must be Strings"]
	if String(data["owner_scope"]) != expected_owner_scope \
			or String(data["owner_checkpoint_receipt"]) != expected_owner_checkpoint_receipt:
		return ["cargo anchor does not match the accepted owner checkpoint"]
	if not _bounded_int(data.get("supply_before_tenths"), 0, MAX_SUPPLY_TENTHS):
		return ["cargo anchor supply is out of range"]
	var expected := make_cargo_anchor(
		expected_owner_scope, expected_owner_checkpoint_receipt,
		data["cargo_before"], int(data["supply_before_tenths"]), data["source_refs"]
	)
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(data):
		return ["cargo anchor does not recompute from its accepted owner checkpoint"]
	return []


static func normalize_cargo_anchor(value: Variant, expected_owner_scope: String,
		expected_owner_checkpoint_receipt: String) -> Dictionary:
	if not (value is Dictionary) or not validate_cargo_anchor(
		value, expected_owner_scope, expected_owner_checkpoint_receipt
	).is_empty():
		return {}
	var data: Dictionary = value
	return make_cargo_anchor(
		expected_owner_scope, expected_owner_checkpoint_receipt,
		data["cargo_before"], int(data["supply_before_tenths"]), data["source_refs"]
	)


static func _make_state(catalog: Dictionary, revision: int, nodes: Array,
		settled_offer_ids: Array, consumed_keys: Array, intel_records: Array,
		parent_state_receipt: String, last_choice_receipt: String) -> Dictionary:
	var base := {
		"schema": STATE_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(catalog["catalog_id"]),
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"revision": revision,
		"nodes": nodes.duplicate(true),
		"settled_offer_ids": settled_offer_ids.duplicate(true),
		"consumed_cargo_anchor_keys": consumed_keys.duplicate(true),
		"intel_records": intel_records.duplicate(true),
		"parent_state_receipt": parent_state_receipt,
		"last_choice_receipt": last_choice_receipt,
	}
	base["state_receipt"] = _receipt_for(base)
	return base if String(base["state_receipt"]) != "" else {}


static func _catalog_self_valid(catalog: Dictionary) -> bool:
	var required := ["schema", "terms_revision", "atlas_id", "atlas_receipt",
		"network_revision", "root_seed", "nodes", "offers", "context_sites",
		"catalog_id", "catalog_receipt"]
	if not _exact_keys(catalog, required) or catalog.get("schema") != CATALOG_SCHEMA \
			or catalog.get("terms_revision") != TERMS_REVISION \
			or not (catalog.get("nodes") is Array) or not (catalog.get("offers") is Array) \
			or not (catalog.get("context_sites") is Array) \
			or not _short_id_valid(_string_if(catalog.get("catalog_id")), CATALOG_ID_PREFIX) \
			or not _receipt_token_valid(_string_if(catalog.get("catalog_receipt"))):
		return false
	var root_seed_values := _root_seed_from_token(_string_if(catalog.get("root_seed")))
	if root_seed_values.is_empty():
		return false
	var expected_atlas: Dictionary = RegionRouteModel.make_atlas(int(root_seed_values[0]))
	var expected: Dictionary = make_catalog(expected_atlas)
	return not expected.is_empty() and _canonical_json(expected) == _canonical_json(catalog)


static func _expected_nodes_for_settled(catalog: Dictionary, settled: Array) -> Array[Dictionary]:
	var by_id := {}
	for raw_node in catalog["nodes"]:
		var node: Dictionary = raw_node
		by_id[String(node["node_id"])] = {
			"node_id": String(node["node_id"]),
			"need_pressure": int(node["initial_need_pressure"]),
			"security_pressure": int(node["initial_security_pressure"]),
			"reciprocity": int(node["initial_reciprocity"]),
		}
	var offer_by_id := _offer_by_id(catalog)
	for raw_offer_id in settled:
		var offer: Dictionary = offer_by_id.get(String(raw_offer_id), {})
		if offer.is_empty():
			return []
		var node_id := String(offer["node_id"])
		var state_node: Dictionary = by_id[node_id]
		var effect: Dictionary = offer["effect"]
		state_node["need_pressure"] = int(state_node["need_pressure"]) + int(effect["need_delta"])
		state_node["security_pressure"] = int(state_node["security_pressure"]) + int(effect["security_delta"])
		state_node["reciprocity"] = int(state_node["reciprocity"]) + int(effect["reciprocity_delta"])
		for key in ["need_pressure", "security_pressure", "reciprocity"]:
			if int(state_node[key]) < 0 or int(state_node[key]) > MAX_TRACK:
				return []
	var result: Array[Dictionary] = []
	for raw_node in catalog["nodes"]:
		result.append((by_id[String((raw_node as Dictionary)["node_id"])] as Dictionary).duplicate(true))
	return result


static func _intel_records_valid(catalog: Dictionary, settled: Array,
		records: Array, revision: int) -> bool:
	var settled_set := {}
	for raw_id in settled:
		settled_set[String(raw_id)] = true
	var offer_by_id := _offer_by_id(catalog)
	var seen_ids := {}
	var seen_offers := {}
	var previous := ""
	for raw_record in records:
		if not (raw_record is Dictionary):
			return false
		var record: Dictionary = raw_record
		if not _intel_record_valid(record):
			return false
		if String(record["catalog_receipt"]) != String(catalog["catalog_receipt"]):
			return false
		var intel_id := String(record["intel_id"])
		var offer_id := String(record["offer_id"])
		if (previous != "" and intel_id <= previous) or seen_ids.has(intel_id) \
				or seen_offers.has(offer_id) or not settled_set.has(offer_id):
			return false
		previous = intel_id
		seen_ids[intel_id] = true
		seen_offers[offer_id] = true
		var offer: Dictionary = offer_by_id.get(offer_id, {})
		if offer.is_empty():
			return false
		var template: Dictionary = offer["intel_template"]
		if String(template["intel_key"]) == "" \
				or String(record["intel_key"]) != String(template["intel_key"]) \
				or String(record["source_node_id"]) != String(offer["node_id"]) \
				or String(record["subject_site_id"]) != String(template["subject_site_id"]) \
				or String(record["topic"]) != String(template["topic"]) \
				or int(record["release_revision"]) < 2 \
				or int(record["release_revision"]) > revision + 1:
			return false
	var expected_count := 0
	for raw_offer_id in settled:
		var offer: Dictionary = offer_by_id[String(raw_offer_id)]
		if String((offer["intel_template"] as Dictionary)["intel_key"]) != "":
			expected_count += 1
	return records.size() == expected_count


static func _intel_record_valid(record: Dictionary) -> bool:
	var required := ["schema", "terms_revision", "catalog_receipt", "intel_id",
		"intel_key", "offer_id", "source_node_id", "subject_site_id", "topic",
		"origin_choice_receipt", "release_revision", "intel_receipt"]
	if not _exact_keys(record, required) or record.get("schema") != INTEL_RECORD_SCHEMA \
			or record.get("terms_revision") != TERMS_REVISION \
			or not _short_id_valid(_string_if(record.get("intel_id")), INTEL_ID_PREFIX) \
			or not _short_id_valid(_string_if(record.get("offer_id")), OFFER_ID_PREFIX) \
			or not _receipt_token_valid(_string_if(record.get("catalog_receipt"))) \
			or not _receipt_token_valid(_string_if(record.get("origin_choice_receipt"))) \
			or not _receipt_token_valid(_string_if(record.get("intel_receipt"))) \
			or not _bounded_int(record.get("release_revision"), 0, MAX_NETWORK_TRANSITIONS + 1):
		return false
	for key in ["intel_key", "topic"]:
		if not _slug_valid(_string_if(record.get(key))):
			return false
	for key in ["source_node_id", "subject_site_id"]:
		var address := ScaleAddress.parse_id(_string_if(record.get(key)))
		if ScaleAddress.level_of(address) != ScaleAddress.LEVEL_SITE \
				or ScaleAddress.canonical_id(address) != String(record[key]):
			return false
	var base := record.duplicate(true)
	base.erase("intel_id")
	base.erase("intel_receipt")
	var digest := _sha256_hex(_canonical_json(base))
	var receipt_base := record.duplicate(true)
	receipt_base.erase("intel_receipt")
	return digest != "" and String(record["intel_id"]) == INTEL_ID_PREFIX + digest.substr(0, 16) \
		and String(record["intel_receipt"]) == _receipt_for(receipt_base)


static func _normalize_intel_record(record: Dictionary) -> Dictionary:
	var result := record.duplicate(true)
	result["release_revision"] = int(record["release_revision"])
	return result


static func _offer_by_id(catalog: Dictionary) -> Dictionary:
	var result := {}
	for raw_offer in catalog["offers"]:
		var offer: Dictionary = raw_offer
		result[String(offer["offer_id"])] = offer
	return result


static func _sorted_unique_offer_ids(catalog: Dictionary, value: Array) -> bool:
	var allowed := _offer_by_id(catalog)
	var previous := ""
	for index in value.size():
		if typeof(value[index]) != TYPE_STRING or not allowed.has(String(value[index])) \
				or (index > 0 and String(value[index]) <= previous):
			return false
		previous = String(value[index])
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


static func _normalize_cargo(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var data: Dictionary = value
	var goods := ["food", "meds", "parts", "scrap"]
	if not _exact_keys(data, goods):
		return {}
	var total := 0
	var result := {}
	for good in goods:
		if not _bounded_int(data.get(good), 0, MAX_CARGO_PER_KIND):
			return {}
		var quantity := int(data[good])
		total += quantity
		result[good] = quantity
	return result if total <= MAX_TOTAL_CARGO else {}


static func _source_refs_valid(value: Variant) -> bool:
	if not (value is Array) or (value as Array).size() > MAX_SOURCE_REFS:
		return false
	var seen := {}
	for raw_ref in value as Array:
		if not (raw_ref is Dictionary):
			return false
		var ref: Dictionary = raw_ref
		var required := ["schema", "kind", "source_id", "source_address", "source_receipt"]
		if not _exact_keys(ref, required) or ref.get("schema") != SOURCE_REF_SCHEMA \
				or _string_if(ref.get("kind")) not in ["expedition_outcome", "site_visit", "owner_manifest"] \
				or not _opaque_id_valid(_string_if(ref.get("source_id"))) \
				or not _receipt_token_valid(_string_if(ref.get("source_receipt"))):
			return false
		var address_text := _string_if(ref.get("source_address"))
		if address_text != "":
			var address := ScaleAddress.parse_id(address_text)
			if ScaleAddress.level_of(address) != ScaleAddress.LEVEL_SITE \
					or ScaleAddress.canonical_id(address) != address_text:
				return false
		var key := _canonical_json(ref)
		if key == "" or seen.has(key):
			return false
		seen[key] = true
	return true


static func _normalize_source_refs(value: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_ref in value:
		var ref: Dictionary = raw_ref
		result.append({
			"schema": SOURCE_REF_SCHEMA,
			"kind": String(ref["kind"]),
			"source_id": String(ref["source_id"]),
			"source_address": String(ref["source_address"]),
			"source_receipt": String(ref["source_receipt"]),
		})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _canonical_json(left) < _canonical_json(right))
	return result


static func make_offer_board(catalog: Dictionary, state: Dictionary,
		accepted_state_receipt: String, cargo_anchor: Dictionary,
		accepted_owner_scope: String, accepted_owner_checkpoint_receipt: String) -> Dictionary:
	if not _catalog_self_valid(catalog):
		return {}
	var normalized_state := accept_state_checkpoint(
		catalog, state, accepted_state_receipt
	)
	var normalized_cargo := normalize_cargo_anchor(
		cargo_anchor, accepted_owner_scope, accepted_owner_checkpoint_receipt
	)
	if normalized_state.is_empty() or normalized_cargo.is_empty():
		return {}
	var settled_set := {}
	for raw_offer_id in normalized_state["settled_offer_ids"]:
		settled_set[String(raw_offer_id)] = true
	var consumed_set := {}
	for raw_key in normalized_state["consumed_cargo_anchor_keys"]:
		consumed_set[String(raw_key)] = true
	var options: Array[Dictionary] = []
	if not consumed_set.has(String(normalized_cargo["replay_key"])):
		var node_by_id := _state_node_by_id(normalized_state)
		for raw_offer in catalog["offers"]:
			var offer: Dictionary = raw_offer
			if settled_set.has(String(offer["offer_id"])):
				continue
			var option := _board_option(offer, node_by_id, normalized_cargo)
			if not option.is_empty():
				options.append(option)
	options.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["offer_id"]) < String(right["offer_id"]))
	var base := {
		"schema": BOARD_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(catalog["catalog_id"]),
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"state_receipt": String(normalized_state["state_receipt"]),
		"accepted_state_receipt": accepted_state_receipt,
		"revision": int(normalized_state["revision"]),
		"cargo_anchor_id": String(normalized_cargo["anchor_id"]),
		"cargo_anchor_receipt": String(normalized_cargo["anchor_receipt"]),
		"cargo_replay_key": String(normalized_cargo["replay_key"]),
		"accepted_owner_scope": accepted_owner_scope,
		"accepted_owner_checkpoint_receipt": accepted_owner_checkpoint_receipt,
		"decision_status": "options_available" if not options.is_empty() else "no_option",
		"options": options,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["board_id"] = BOARD_ID_PREFIX + digest.substr(0, 16)
	base["board_receipt"] = _receipt_for(base)
	return base if String(base["board_receipt"]) != "" else {}


static func validate_offer_board(catalog: Dictionary, state: Dictionary,
		accepted_state_receipt: String, cargo_anchor: Dictionary,
		accepted_owner_scope: String, accepted_owner_checkpoint_receipt: String,
		value: Variant) -> Array[String]:
	var expected := make_offer_board(
		catalog, state, accepted_state_receipt, cargo_anchor,
		accepted_owner_scope, accepted_owner_checkpoint_receipt
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["settlement offer board does not derive from accepted state and cargo"]
	return []


static func normalize_offer_board(catalog: Dictionary, state: Dictionary,
		accepted_state_receipt: String, cargo_anchor: Dictionary,
		accepted_owner_scope: String, accepted_owner_checkpoint_receipt: String,
		value: Variant) -> Dictionary:
	var expected := make_offer_board(
		catalog, state, accepted_state_receipt, cargo_anchor,
		accepted_owner_scope, accepted_owner_checkpoint_receipt
	)
	return expected if not expected.is_empty() \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func make_choice(board: Dictionary, offer_id: String) -> Dictionary:
	if not _board_self_valid(board) or not _short_id_valid(offer_id, OFFER_ID_PREFIX):
		return {}
	var selected := {}
	for raw_option in board["options"]:
		var option: Dictionary = raw_option
		if String(option.get("offer_id", "")) == offer_id:
			selected = option
			break
	if selected.is_empty():
		return {}
	var base := {
		"schema": CHOICE_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"board_id": String(board["board_id"]),
		"board_receipt": String(board["board_receipt"]),
		"cargo_replay_key": String(board["cargo_replay_key"]),
		"offer_id": offer_id,
		"offer_receipt": String(selected["offer_receipt"]),
		"node_id": String(selected["node_id"]),
		"action": String(selected["action"]),
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["choice_id"] = CHOICE_ID_PREFIX + digest.substr(0, 16)
	base["choice_receipt"] = _receipt_for(base)
	return base if String(base["choice_receipt"]) != "" else {}


static func validate_choice(board: Dictionary, value: Variant) -> Array[String]:
	if not (value is Dictionary):
		return ["settlement choice must be a Dictionary"]
	var data: Dictionary = value
	var expected := make_choice(board, _string_if(data.get("offer_id")))
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(data):
		return ["settlement choice does not derive from its exact offer board"]
	return []


static func normalize_choice(board: Dictionary, value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var expected := make_choice(board, _string_if((value as Dictionary).get("offer_id")))
	return expected if not expected.is_empty() \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func make_arrival_evidence(catalog: Dictionary, node_id: String,
		atlas: Dictionary, atlas_state: Dictionary, plan: Dictionary,
		journey: Dictionary, route_receipt: Dictionary,
		accepted_journey_state_receipt: String) -> Dictionary:
	if not _catalog_self_valid(catalog) \
			or not RegionRouteModel.validate_atlas(atlas).is_empty() \
			or not RegionRouteModel.validate_atlas_state(atlas, atlas_state).is_empty() \
			or not RegionRouteModel.validate_plan(atlas, atlas_state, plan).is_empty() \
			or not RegionRouteModel.validate_journey(atlas, atlas_state, plan, journey).is_empty() \
			or not RegionRouteModel.validate_route_receipt(
				atlas, atlas_state, plan, journey, route_receipt
			).is_empty():
		return {}
	if String(catalog["atlas_id"]) != String(atlas.get("atlas_id", "")) \
			or String(catalog["atlas_receipt"]) != String(atlas.get("atlas_receipt", "")) \
			or String(catalog["root_seed"]) != String(atlas.get("root_seed", "")):
		return {}
	if not _receipt_token_valid(accepted_journey_state_receipt) \
			or String(journey.get("state_receipt", "")) != accepted_journey_state_receipt \
			or String(journey.get("phase", "")) != "arrived":
		return {}
	var node := _catalog_node_by_id(catalog).get(node_id, {}) as Dictionary
	if node.is_empty() or String(journey.get("current_tile", "")) != String(node["tile_id"]):
		return {}
	var base := {
		"schema": ARRIVAL_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(catalog["catalog_id"]),
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"node_id": node_id,
		"tile_id": String(node["tile_id"]),
		"atlas_id": String(atlas["atlas_id"]),
		"atlas_receipt": String(atlas["atlas_receipt"]),
		"atlas_state_receipt": String(atlas_state["state_receipt"]),
		"plan_id": String(plan["plan_id"]),
		"plan_receipt": String(plan["plan_receipt"]),
		"journey_id": String(journey["journey_id"]),
		"journey_state_receipt": String(journey["state_receipt"]),
		"accepted_journey_state_receipt": accepted_journey_state_receipt,
		"route_receipt": String(route_receipt["route_receipt"]),
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["arrival_id"] = ARRIVAL_ID_PREFIX + digest.substr(0, 16)
	base["arrival_receipt"] = _receipt_for(base)
	return base if String(base["arrival_receipt"]) != "" else {}


static func validate_arrival_evidence(catalog: Dictionary, node_id: String,
		atlas: Dictionary, atlas_state: Dictionary, plan: Dictionary,
		journey: Dictionary, route_receipt: Dictionary,
		accepted_journey_state_receipt: String, value: Variant) -> Array[String]:
	var expected := make_arrival_evidence(
		catalog, node_id, atlas, atlas_state, plan, journey, route_receipt,
		accepted_journey_state_receipt
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["settlement arrival does not derive from the accepted arrived journey"]
	return []


static func _board_option(offer: Dictionary, node_by_id: Dictionary,
		cargo_anchor: Dictionary) -> Dictionary:
	var node_id := String(offer["node_id"])
	if not node_by_id.has(node_id):
		return {}
	var node: Dictionary = node_by_id[node_id]
	var cost: Dictionary = offer["cost"]
	var cargo: Dictionary = cargo_anchor["cargo_before"]
	var good := String(cost["good"])
	var quantity := int(cost["quantity"])
	if quantity <= 0 or int(cargo.get(good, 0)) < quantity:
		return {}
	var effect: Dictionary = offer["effect"]
	var after_need := int(node["need_pressure"]) + int(effect["need_delta"])
	var after_security := int(node["security_pressure"]) + int(effect["security_delta"])
	var after_reciprocity := int(node["reciprocity"]) + int(effect["reciprocity_delta"])
	if after_need < 0 or after_need > MAX_TRACK or after_security < 0 \
			or after_security > MAX_TRACK or after_reciprocity < 0 \
			or after_reciprocity > MAX_TRACK:
		return {}
	var requested_gain := int((offer["owner_reward"] as Dictionary)["supply_gain_tenths"])
	var supply_before := int(cargo_anchor["supply_before_tenths"])
	var applied_gain := mini(requested_gain, MAX_SUPPLY_TENTHS - supply_before)
	var changes_node := int(effect["need_delta"]) != 0 \
		or int(effect["security_delta"]) != 0 or int(effect["reciprocity_delta"]) != 0
	if not changes_node and applied_gain <= 0:
		return {}
	return {
		"offer_id": String(offer["offer_id"]),
		"offer_receipt": String(offer["offer_receipt"]),
		"node_id": node_id,
		"action": String(offer["action"]),
		"cost": cost.duplicate(true),
		"effect": effect.duplicate(true),
		"owner_reward": {
			"requested_supply_gain_tenths": requested_gain,
			"applied_supply_gain_tenths": applied_gain,
		},
		"intel_template": (offer["intel_template"] as Dictionary).duplicate(true),
	}


static func _state_node_by_id(state: Dictionary) -> Dictionary:
	var result := {}
	for raw_node in state["nodes"]:
		var node: Dictionary = raw_node
		result[String(node["node_id"])] = node
	return result


static func _catalog_node_by_id(catalog: Dictionary) -> Dictionary:
	var result := {}
	for raw_node in catalog["nodes"]:
		var node: Dictionary = raw_node
		result[String(node["node_id"])] = node
	return result


static func _board_self_valid(board: Dictionary) -> bool:
	var required := ["schema", "terms_revision", "catalog_id", "catalog_receipt",
		"state_receipt", "accepted_state_receipt", "revision", "cargo_anchor_id",
		"cargo_anchor_receipt", "cargo_replay_key", "accepted_owner_scope",
		"accepted_owner_checkpoint_receipt",
		"decision_status", "options", "board_id", "board_receipt"]
	if not _exact_keys(board, required) or board.get("schema") != BOARD_SCHEMA \
			or board.get("terms_revision") != TERMS_REVISION \
			or not (board.get("options") is Array) \
			or not _short_id_valid(_string_if(board.get("board_id")), BOARD_ID_PREFIX) \
			or not _receipt_token_valid(_string_if(board.get("board_receipt"))):
		return false
	for key in ["catalog_receipt", "state_receipt", "accepted_state_receipt",
			"cargo_anchor_receipt", "cargo_replay_key",
			"accepted_owner_checkpoint_receipt"]:
		if not _receipt_token_valid(_string_if(board.get(key))):
			return false
	if not _short_id_valid(_string_if(board.get("catalog_id")), CATALOG_ID_PREFIX) \
			or not _short_id_valid(_string_if(board.get("cargo_anchor_id")), ANCHOR_ID_PREFIX) \
			or not _slug_valid(_string_if(board.get("accepted_owner_scope"))) \
			or not _bounded_int(board.get("revision"), 0, MAX_NETWORK_TRANSITIONS) \
			or _string_if(board.get("decision_status")) not in ["options_available", "no_option"]:
		return false
	var options: Array = board["options"]
	if options.size() > _offer_specs().size() \
			or (options.is_empty() != (String(board["decision_status"]) == "no_option")):
		return false
	var previous := ""
	for index in options.size():
		if not (options[index] is Dictionary) or not _board_option_valid(options[index]):
			return false
		var offer_id := String((options[index] as Dictionary)["offer_id"])
		if index > 0 and offer_id <= previous:
			return false
		previous = offer_id
	var id_base := board.duplicate(true)
	id_base.erase("board_id")
	id_base.erase("board_receipt")
	var digest := _sha256_hex(_canonical_json(id_base))
	if digest == "" or String(board["board_id"]) != BOARD_ID_PREFIX + digest.substr(0, 16):
		return false
	var receipt_base := board.duplicate(true)
	receipt_base.erase("board_receipt")
	return String(board["board_receipt"]) == _receipt_for(receipt_base)


static func _board_option_valid(option: Dictionary) -> bool:
	var required := ["offer_id", "offer_receipt", "node_id", "action", "cost",
		"effect", "owner_reward", "intel_template"]
	if not _exact_keys(option, required) or not (option.get("cost") is Dictionary) \
			or not (option.get("effect") is Dictionary) \
			or not (option.get("owner_reward") is Dictionary) \
			or not (option.get("intel_template") is Dictionary) \
			or not _short_id_valid(_string_if(option.get("offer_id")), OFFER_ID_PREFIX) \
			or not _receipt_token_valid(_string_if(option.get("offer_receipt"))) \
			or _string_if(option.get("action")) not in ["aid", "trade", "fortify"]:
		return false
	var node_address := ScaleAddress.parse_id(_string_if(option.get("node_id")))
	if ScaleAddress.level_of(node_address) != ScaleAddress.LEVEL_SITE \
			or ScaleAddress.canonical_id(node_address) != String(option["node_id"]):
		return false
	var cost: Dictionary = option["cost"]
	if not _exact_keys(cost, ["good", "quantity"]) \
			or _string_if(cost.get("good")) not in ["food", "meds", "parts", "scrap"] \
			or not _bounded_int(cost.get("quantity"), 1, MAX_CARGO_PER_KIND):
		return false
	var effect: Dictionary = option["effect"]
	if not _exact_keys(effect, ["need_delta", "security_delta", "reciprocity_delta"]):
		return false
	for key in ["need_delta", "security_delta", "reciprocity_delta"]:
		if not _bounded_int(effect.get(key), -MAX_TRACK, MAX_TRACK):
			return false
	var reward: Dictionary = option["owner_reward"]
	if not _exact_keys(reward, ["requested_supply_gain_tenths", "applied_supply_gain_tenths"]) \
			or not _bounded_int(reward.get("requested_supply_gain_tenths"), 0, MAX_SUPPLY_TENTHS) \
			or not _bounded_int(reward.get("applied_supply_gain_tenths"), 0, MAX_SUPPLY_TENTHS) \
			or int(reward["applied_supply_gain_tenths"]) > int(reward["requested_supply_gain_tenths"]):
		return false
	var intel: Dictionary = option["intel_template"]
	if not _exact_keys(intel, ["intel_key", "subject_site_id", "topic", "delay_revisions"]):
		return false
	var intel_key := _string_if(intel.get("intel_key"))
	if intel_key == "":
		return _string_if(intel.get("subject_site_id")) == "" \
			and _string_if(intel.get("topic")) == "" \
			and _bounded_int(intel.get("delay_revisions"), 0, 0)
	var subject := ScaleAddress.parse_id(_string_if(intel.get("subject_site_id")))
	return _slug_valid(intel_key) and _slug_valid(_string_if(intel.get("topic"))) \
		and ScaleAddress.level_of(subject) == ScaleAddress.LEVEL_SITE \
		and ScaleAddress.canonical_id(subject) == String(intel["subject_site_id"]) \
		and _bounded_int(intel.get("delay_revisions"), 1, 1)


static func propose_settlement(catalog: Dictionary, before_state: Dictionary,
		accepted_before_state_receipt: String, cargo_anchor: Dictionary,
		accepted_owner_scope: String, accepted_owner_checkpoint_receipt: String,
		board: Dictionary,
		choice: Dictionary, atlas: Dictionary, atlas_state: Dictionary,
		plan: Dictionary, journey: Dictionary, route_receipt: Dictionary,
		accepted_journey_state_receipt: String, arrival: Dictionary) -> Dictionary:
	if not _catalog_self_valid(catalog):
		return {}
	var normalized_state := accept_state_checkpoint(
		catalog, before_state, accepted_before_state_receipt
	)
	var normalized_cargo := normalize_cargo_anchor(
		cargo_anchor, accepted_owner_scope, accepted_owner_checkpoint_receipt
	)
	if normalized_state.is_empty() or normalized_cargo.is_empty():
		return {}
	var expected_board := make_offer_board(
		catalog, normalized_state, accepted_before_state_receipt,
		normalized_cargo, accepted_owner_scope, accepted_owner_checkpoint_receipt
	)
	if expected_board.is_empty() or _canonical_json(expected_board) != _canonical_json(board):
		return {}
	var expected_choice := normalize_choice(expected_board, choice)
	if expected_choice.is_empty():
		return {}
	var expected_arrival := make_arrival_evidence(
		catalog, String(expected_choice["node_id"]), atlas, atlas_state,
		plan, journey, route_receipt, accepted_journey_state_receipt
	)
	if expected_arrival.is_empty() or _canonical_json(expected_arrival) != _canonical_json(arrival):
		return {}
	var replay_key := String(normalized_cargo["replay_key"])
	if replay_key in normalized_state["consumed_cargo_anchor_keys"] \
			or String(expected_choice["offer_id"]) in normalized_state["settled_offer_ids"]:
		return {}
	var selected := _board_option_by_id(expected_board, String(expected_choice["offer_id"]))
	if selected.is_empty() or String(selected["node_id"]) != String(expected_arrival["node_id"]):
		return {}
	var node_before := (_state_node_by_id(normalized_state).get(
		String(selected["node_id"]), {}
	) as Dictionary).duplicate(true)
	if node_before.is_empty():
		return {}
	var effect: Dictionary = selected["effect"]
	var node_after := node_before.duplicate(true)
	node_after["need_pressure"] = int(node_after["need_pressure"]) + int(effect["need_delta"])
	node_after["security_pressure"] = int(node_after["security_pressure"]) + int(effect["security_delta"])
	node_after["reciprocity"] = int(node_after["reciprocity"]) + int(effect["reciprocity_delta"])
	var after_nodes: Array[Dictionary] = []
	for raw_node in normalized_state["nodes"]:
		var state_node: Dictionary = raw_node
		after_nodes.append(node_after.duplicate(true) if String(state_node["node_id"]) \
			== String(node_after["node_id"]) else state_node.duplicate(true))
	var settled: Array[String] = []
	for raw_offer_id in normalized_state["settled_offer_ids"]:
		settled.append(String(raw_offer_id))
	settled.append(String(selected["offer_id"]))
	settled.sort()
	var consumed: Array[String] = []
	for raw_consumed in normalized_state["consumed_cargo_anchor_keys"]:
		consumed.append(String(raw_consumed))
	consumed.append(replay_key)
	consumed.sort()
	var after_revision := int(normalized_state["revision"]) + 1
	var intel_records: Array[Dictionary] = []
	for raw_record in normalized_state["intel_records"]:
		intel_records.append((raw_record as Dictionary).duplicate(true))
	var intel_record := {}
	var intel_template: Dictionary = selected["intel_template"]
	if String(intel_template["intel_key"]) != "":
		intel_record = _make_intel_record(
			catalog, selected, expected_choice,
			after_revision + int(intel_template["delay_revisions"])
		)
		if intel_record.is_empty():
			return {}
		intel_records.append(intel_record)
		intel_records.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return String(left["intel_id"]) < String(right["intel_id"]))
	var after_state := _make_state(
		catalog, after_revision, after_nodes, settled, consumed, intel_records,
		String(normalized_state["state_receipt"]), String(expected_choice["choice_receipt"])
	)
	if after_state.is_empty() or not validate_state(catalog, after_state).is_empty():
		return {}
	var delivered := {"food": 0, "meds": 0, "parts": 0, "scrap": 0}
	var cost: Dictionary = selected["cost"]
	delivered[String(cost["good"])] = int(cost["quantity"])
	var cargo_after: Dictionary = (normalized_cargo["cargo_before"] as Dictionary).duplicate(true)
	cargo_after[String(cost["good"])] = int(cargo_after[String(cost["good"])]) \
		- int(cost["quantity"])
	var reward: Dictionary = selected["owner_reward"]
	var supply_before := int(normalized_cargo["supply_before_tenths"])
	var applied_gain := int(reward["applied_supply_gain_tenths"])
	var owner_delta := {
		"owner_scope": String(normalized_cargo["owner_scope"]),
		"owner_checkpoint_receipt": accepted_owner_checkpoint_receipt,
		"cargo_before": (normalized_cargo["cargo_before"] as Dictionary).duplicate(true),
		"delivered": delivered,
		"cargo_after": cargo_after,
		"supply_before_tenths": supply_before,
		"requested_supply_gain_tenths": int(reward["requested_supply_gain_tenths"]),
		"applied_supply_gain_tenths": applied_gain,
		"supply_after_tenths": supply_before + applied_gain,
	}
	var network_delta := {
		"node_before": node_before,
		"node_after": node_after,
		"settled_offer_id": String(selected["offer_id"]),
		"consumed_cargo_anchor_key": replay_key,
		"intel_record": intel_record.duplicate(true),
	}
	var base := {
		"schema": TRANSITION_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(catalog["catalog_id"]),
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"before_state_receipt": String(normalized_state["state_receipt"]),
		"accepted_before_state_receipt": accepted_before_state_receipt,
		"cargo_anchor_id": String(normalized_cargo["anchor_id"]),
		"cargo_anchor_receipt": String(normalized_cargo["anchor_receipt"]),
		"cargo_replay_key": replay_key,
		"accepted_owner_scope": accepted_owner_scope,
		"accepted_owner_checkpoint_receipt": accepted_owner_checkpoint_receipt,
		"board_id": String(expected_board["board_id"]),
		"board_receipt": String(expected_board["board_receipt"]),
		"choice_id": String(expected_choice["choice_id"]),
		"choice_receipt": String(expected_choice["choice_receipt"]),
		"arrival_id": String(expected_arrival["arrival_id"]),
		"arrival_receipt": String(expected_arrival["arrival_receipt"]),
		"node_id": String(selected["node_id"]),
		"offer_id": String(selected["offer_id"]),
		"action": String(selected["action"]),
		"network_delta": network_delta,
		"owner_delta": owner_delta,
		"after_state": after_state,
		"after_state_receipt": String(after_state["state_receipt"]),
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["transition_id"] = TRANSITION_ID_PREFIX + digest.substr(0, 16)
	base["transition_receipt"] = _receipt_for(base)
	return base if String(base["transition_receipt"]) != "" else {}


static func validate_settlement(catalog: Dictionary, before_state: Dictionary,
		accepted_before_state_receipt: String, cargo_anchor: Dictionary,
		accepted_owner_scope: String, accepted_owner_checkpoint_receipt: String,
		board: Dictionary,
		choice: Dictionary, atlas: Dictionary, atlas_state: Dictionary,
		plan: Dictionary, journey: Dictionary, route_receipt: Dictionary,
		accepted_journey_state_receipt: String, arrival: Dictionary,
		value: Variant) -> Array[String]:
	var expected := propose_settlement(
		catalog, before_state, accepted_before_state_receipt, cargo_anchor,
		accepted_owner_scope, accepted_owner_checkpoint_receipt, board, choice, atlas, atlas_state,
		plan, journey, route_receipt, accepted_journey_state_receipt, arrival
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["settlement transition does not recompute from both accepted owners"]
	return []


static func project_intel(catalog: Dictionary, state: Dictionary,
		accepted_state_receipt: String) -> Dictionary:
	## A finite V1 catalog can end with an intel-bearing choice. Such intel stays
	## pending until a later, distinct positive settlement exists under a future
	## catalog/owner migration; catalog exhaustion never releases it instantly.
	if not _catalog_self_valid(catalog):
		return {}
	var normalized_state := accept_state_checkpoint(
		catalog, state, accepted_state_receipt
	)
	if normalized_state.is_empty():
		return {}
	var pending: Array[Dictionary] = []
	var available: Array[Dictionary] = []
	var revision := int(normalized_state["revision"])
	for raw_record in normalized_state["intel_records"]:
		var record: Dictionary = raw_record
		if int(record["release_revision"]) <= revision:
			available.append({
				"intel_id": String(record["intel_id"]),
				"intel_receipt": String(record["intel_receipt"]),
				"offer_id": String(record["offer_id"]),
				"source_node_id": String(record["source_node_id"]),
				"subject_site_id": String(record["subject_site_id"]),
				"topic": String(record["topic"]),
				"origin_choice_receipt": String(record["origin_choice_receipt"]),
				"release_revision": int(record["release_revision"]),
			})
		else:
			pending.append({
				"intel_id": String(record["intel_id"]),
				"intel_receipt": String(record["intel_receipt"]),
				"release_revision": int(record["release_revision"]),
			})
	var base := {
		"schema": INTEL_PROJECTION_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(catalog["catalog_id"]),
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"state_receipt": String(normalized_state["state_receipt"]),
		"accepted_state_receipt": accepted_state_receipt,
		"revision": revision,
		"pending": pending,
		"available": available,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["projection_id"] = PROJECTION_ID_PREFIX + digest.substr(0, 16)
	base["projection_receipt"] = _receipt_for(base)
	return base if String(base["projection_receipt"]) != "" else {}


static func validate_intel_projection(catalog: Dictionary, state: Dictionary,
		accepted_state_receipt: String, value: Variant) -> Array[String]:
	var expected := project_intel(catalog, state, accepted_state_receipt)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["intel projection does not derive from accepted network state"]
	return []


static func _make_intel_record(catalog: Dictionary, option: Dictionary,
		choice: Dictionary, release_revision: int) -> Dictionary:
	if not _bounded_int(release_revision, 0, MAX_NETWORK_TRANSITIONS + 1):
		return {}
	var template: Dictionary = option["intel_template"]
	var base := {
		"schema": INTEL_RECORD_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"intel_key": String(template["intel_key"]),
		"offer_id": String(option["offer_id"]),
		"source_node_id": String(option["node_id"]),
		"subject_site_id": String(template["subject_site_id"]),
		"topic": String(template["topic"]),
		"origin_choice_receipt": String(choice["choice_receipt"]),
		"release_revision": release_revision,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["intel_id"] = INTEL_ID_PREFIX + digest.substr(0, 16)
	base["intel_receipt"] = _receipt_for(base)
	return base if String(base["intel_receipt"]) != "" else {}


static func _board_option_by_id(board: Dictionary, offer_id: String) -> Dictionary:
	for raw_option in board["options"]:
		var option: Dictionary = raw_option
		if String(option["offer_id"]) == offer_id:
			return option.duplicate(true)
	return {}


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
	if not _canonical_i64(number_text):
		return []
	return [int(number_text)]


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
	return digits.length() < limit.length() or (digits.length() == limit.length() and digits <= limit)


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


static func _opaque_id_valid(value: String) -> bool:
	if value.is_empty() or value.length() > 96:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		if code < 33 or code > 126:
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
			return str(int(value))
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
