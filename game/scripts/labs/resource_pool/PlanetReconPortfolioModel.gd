extends RefCounted

## RP-0009: owner-independent reconnaissance portfolios and epistemic envelopes.
##
## This model never owns or changes world truth, discovery, settlement intel,
## campaign epoch, covenant state, production beliefs, or a save. It records one
## accepted evidence snapshot, one 2-of-3 reconnaissance allocation, and the
## resulting bounded belief bands. External owners remain authoritative for
## reconnaissance capacity and observation reports.

const ScaleAddress = preload("res://scripts/labs/resource_pool/ScaleAddress.gd")
const RegionRouteModel = preload("res://scripts/labs/resource_pool/RegionRouteModel.gd")
const SettlementNetworkModel = preload(
	"res://scripts/labs/resource_pool/SettlementNetworkModel.gd"
)
const PlanetCampaignModel = preload(
	"res://scripts/labs/resource_pool/PlanetCampaignModel.gd"
)
const CampaignCovenantModel = preload(
	"res://scripts/labs/resource_pool/CampaignCovenantModel.gd"
)

const CATALOG_SCHEMA := "living-town.planet-recon-catalog/v1"
const EVIDENCE_SCHEMA := "living-town.planet-recon-evidence/v1"
const STATE_SCHEMA := "living-town.planet-recon-state/v1"
const RECON_ANCHOR_SCHEMA := "living-town.planet-recon-capacity-anchor/v1"
const BOARD_SCHEMA := "living-town.planet-recon-board/v1"
const CHOICE_SCHEMA := "living-town.planet-recon-choice/v1"
const COMMIT_RECORD_SCHEMA := "living-town.planet-recon-commit-record/v1"
const COMMIT_SCHEMA := "living-town.planet-recon-commit-proposal/v1"
const OBSERVATION_SCHEMA := "living-town.planet-recon-observation-bundle/v1"
const RESOLUTION_RECORD_SCHEMA := "living-town.planet-recon-resolution-record/v1"
const RESOLUTION_SCHEMA := "living-town.planet-recon-resolution-proposal/v1"
const STALE_RECORD_SCHEMA := "living-town.planet-recon-stale-record/v1"
const STALE_SCHEMA := "living-town.planet-recon-stale-proposal/v1"
const PROJECTION_SCHEMA := "living-town.planet-recon-belief-projection/v1"

const TERMS_REVISION := "ashfall-planet-recon-portfolio-v1"
const PHASES := ["open", "committed", "terminal"]
const OUTCOMES := ["", "resolved", "stale"]
const ROLES := ["duty", "spillover", "fallback"]
const SIGNALS := ["adverse", "favorable", "mixed"]

const PORTFOLIO_COST := 2
const REQUIRED_PROBES := 2
const MAX_RECON_POINTS := 8
const MAX_STATE_REVISION := 2
const MIN_BP := 0
const MAX_BP := 10000
const BROAD_PRIOR_MIN_BP := 2000
const BROAD_PRIOR_MAX_BP := 8000
const GROUNDED_PRIOR_MIN_BP := 3000
const GROUNDED_PRIOR_MAX_BP := 7000
const POSTERIOR_WIDTH_BP := 2000
const MAX_SAFE_JSON_INT := 9007199254740991
const MAX_CANONICAL_DEPTH := 32
const MAX_CANONICAL_NODES := 4096
const MAX_CANONICAL_CONTAINER := 256
const MAX_CANONICAL_STRING := 1024

const CATALOG_ID_PREFIX := "prc1:"
const QUESTION_ID_PREFIX := "prq1:"
const EVIDENCE_ID_PREFIX := "pre1:"
const ANCHOR_ID_PREFIX := "pra1:"
const BOARD_ID_PREFIX := "prb1:"
const CHOICE_ID_PREFIX := "prk1:"
const PROBE_ID_PREFIX := "prg1:"
const PORTFOLIO_ID_PREFIX := "prf1:"
const COMMIT_RECORD_ID_PREFIX := "prr1:"
const COMMIT_ID_PREFIX := "prt1:"
const OBSERVATION_ID_PREFIX := "pro1:"
const RESOLUTION_RECORD_ID_PREFIX := "prv1:"
const RESOLUTION_ID_PREFIX := "prx1:"
const STALE_RECORD_ID_PREFIX := "prl1:"
const STALE_ID_PREFIX := "prz1:"
const PROJECTION_ID_PREFIX := "prp1:"


static func make_catalog(campaign_catalog: Dictionary,
		covenant_catalog: Dictionary) -> Dictionary:
	if not PlanetCampaignModel.validate_catalog(campaign_catalog).is_empty() \
			or not CampaignCovenantModel.validate_catalog(
				campaign_catalog, covenant_catalog
			).is_empty():
		return {}
	var questions: Array[Dictionary] = []
	var seen_ids := {}
	for raw_window in campaign_catalog["windows"]:
		var window: Dictionary = raw_window
		var authority := {
			"terms_revision": TERMS_REVISION,
			"campaign_catalog_receipt": String(campaign_catalog["catalog_receipt"]),
			"covenant_catalog_receipt": String(covenant_catalog["catalog_receipt"]),
			"window_id": String(window["window_id"]),
			"window_key": String(window["window_key"]),
			"region_id": String(window["region_id"]),
			"faction_id": String(window["faction_id"]),
			"window_seed_receipt": (window["seed_receipt"] as Dictionary).duplicate(true),
			"question_kind": "future_support_evidence",
			"broad_prior_min_bp": BROAD_PRIOR_MIN_BP,
			"broad_prior_max_bp": BROAD_PRIOR_MAX_BP,
			"grounded_prior_min_bp": GROUNDED_PRIOR_MIN_BP,
			"grounded_prior_max_bp": GROUNDED_PRIOR_MAX_BP,
			"posterior_width_bp": POSTERIOR_WIDTH_BP,
		}
		var digest := _sha256_hex(_canonical_json(authority))
		if digest == "":
			return {}
		var question := authority.duplicate(true)
		question["question_id"] = QUESTION_ID_PREFIX + digest.substr(0, 16)
		question["question_receipt"] = _receipt_for(question)
		if String(question["question_receipt"]) == "" \
				or seen_ids.has(String(question["question_id"])):
			return {}
		seen_ids[String(question["question_id"])] = true
		questions.append(question)
	questions.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["question_id"]) < String(right["question_id"]))
	if questions.size() != 3:
		return {}
	var base := {
		"schema": CATALOG_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"campaign_catalog_id": String(campaign_catalog["catalog_id"]),
		"campaign_catalog_receipt": String(campaign_catalog["catalog_receipt"]),
		"covenant_catalog_id": String(covenant_catalog["catalog_id"]),
		"covenant_catalog_receipt": String(covenant_catalog["catalog_receipt"]),
		"planet_id": String(campaign_catalog["planet_id"]),
		"portfolio_cost": PORTFOLIO_COST,
		"required_probes": REQUIRED_PROBES,
		"questions": questions,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["catalog_id"] = CATALOG_ID_PREFIX + digest.substr(0, 16)
	base["catalog_receipt"] = "sha256:" + digest
	return base


static func validate_catalog(campaign_catalog: Dictionary,
		covenant_catalog: Dictionary, value: Variant) -> Array[String]:
	if not (value is Dictionary):
		return ["planet recon catalog must be a Dictionary"]
	var expected := make_catalog(campaign_catalog, covenant_catalog)
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(value):
		return ["planet recon catalog does not match exact RP7/RP8 terms"]
	return []


static func normalize_catalog(campaign_catalog: Dictionary,
		covenant_catalog: Dictionary, value: Variant) -> Dictionary:
	var expected := make_catalog(campaign_catalog, covenant_catalog)
	return expected if not expected.is_empty() and value is Dictionary \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func make_evidence_envelope(catalog: Dictionary, atlas: Dictionary,
		atlas_state: Dictionary, accepted_atlas_state_receipt: String,
		network_catalog: Dictionary, network_state: Dictionary,
		accepted_network_state_receipt: String, intel_projection: Dictionary,
		campaign_catalog: Dictionary, campaign_state: Dictionary,
		accepted_campaign_state_receipt: String, campaign_owner_scope: String,
		covenant_catalog: Dictionary, covenant_state: Dictionary,
		accepted_covenant_state_receipt: String,
		obligation_projection: Dictionary, global_network_scope: String) -> Dictionary:
	var normalized_catalog := normalize_catalog(
		campaign_catalog, covenant_catalog, catalog
	)
	if normalized_catalog.is_empty() or not _slug_valid(campaign_owner_scope) \
			or not _slug_valid(global_network_scope) \
			or campaign_owner_scope == global_network_scope:
		return {}
	var normalized_atlas := RegionRouteModel.normalize_atlas(atlas)
	var normalized_atlas_state := RegionRouteModel.normalize_atlas_state(
		normalized_atlas, atlas_state
	) if not normalized_atlas.is_empty() else {}
	if normalized_atlas.is_empty() or normalized_atlas_state.is_empty() \
			or normalized_atlas.get("root_seed") != campaign_catalog.get("root_seed") \
			or not _atlas_matches_planet(
				normalized_atlas, String(campaign_catalog.get("planet_id", ""))
			) \
			or not _receipt_token_valid(accepted_atlas_state_receipt) \
			or String(normalized_atlas_state["state_receipt"]) \
			!= accepted_atlas_state_receipt:
		return {}
	var normalized_network_catalog := SettlementNetworkModel.normalize_catalog(
		normalized_atlas, network_catalog
	)
	var normalized_network_state := SettlementNetworkModel.accept_state_checkpoint(
		normalized_network_catalog, network_state, accepted_network_state_receipt
	) if not normalized_network_catalog.is_empty() else {}
	if normalized_network_catalog.is_empty() or normalized_network_state.is_empty() \
			or not SettlementNetworkModel.validate_intel_projection(
				normalized_network_catalog, normalized_network_state,
				accepted_network_state_receipt, intel_projection
			).is_empty():
		return {}
	var expected_intel := SettlementNetworkModel.project_intel(
		normalized_network_catalog, normalized_network_state,
		accepted_network_state_receipt
	)
	var normalized_campaign := PlanetCampaignModel.accept_state_checkpoint(
		campaign_catalog, campaign_state, accepted_campaign_state_receipt
	)
	var normalized_covenant_catalog := CampaignCovenantModel.normalize_catalog(
		campaign_catalog, covenant_catalog
	)
	var normalized_covenant_state := CampaignCovenantModel.accept_state_checkpoint(
		normalized_covenant_catalog, covenant_state,
		accepted_covenant_state_receipt
	) if not normalized_covenant_catalog.is_empty() else {}
	if expected_intel.is_empty() or normalized_campaign.is_empty() \
			or normalized_covenant_catalog.is_empty() \
			or normalized_covenant_state.is_empty() \
			or String(normalized_covenant_state["phase"]) != "active" \
			or not CampaignCovenantModel.validate_obligation_projection(
				normalized_covenant_catalog, normalized_covenant_state,
				accepted_covenant_state_receipt, campaign_catalog,
				normalized_campaign, accepted_campaign_state_receipt,
				campaign_owner_scope, obligation_projection
			).is_empty():
		return {}
	var expected_obligation := CampaignCovenantModel.project_obligation(
		normalized_covenant_catalog, normalized_covenant_state,
		accepted_covenant_state_receipt, campaign_catalog, normalized_campaign,
		accepted_campaign_state_receipt, campaign_owner_scope
	)
	if expected_obligation.is_empty() \
			or String(expected_obligation["timing_status"]) != "not_due" \
			or int(normalized_campaign["epoch_index"]) \
			>= int(expected_obligation["effective_due_epoch"]):
		return {}
	var covenant_record: Dictionary = normalized_covenant_state["covenant_record"]
	if String(covenant_record["campaign_owner_scope"]) != campaign_owner_scope \
			or String(covenant_record["global_network_scope"]) \
			!= global_network_scope:
		return {}
	var priors := _make_priors(
		normalized_catalog, normalized_atlas, normalized_atlas_state,
		normalized_network_catalog, expected_intel
	)
	var roles := _make_role_assignments(
		normalized_catalog, campaign_catalog, normalized_covenant_catalog,
		covenant_record
	)
	if priors.size() != 3 or roles.size() != 3:
		return {}
	var base := {
		"schema": EVIDENCE_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(normalized_catalog["catalog_id"]),
		"catalog_receipt": String(normalized_catalog["catalog_receipt"]),
		"atlas_id": String(normalized_atlas["atlas_id"]),
		"atlas_receipt": String(normalized_atlas["atlas_receipt"]),
		"accepted_atlas_state_receipt": accepted_atlas_state_receipt,
		"network_catalog_id": String(normalized_network_catalog["catalog_id"]),
		"network_catalog_receipt": String(normalized_network_catalog["catalog_receipt"]),
		"global_network_scope": global_network_scope,
		"accepted_network_state_receipt": accepted_network_state_receipt,
		"intel_projection_id": String(expected_intel["projection_id"]),
		"intel_projection_receipt": String(expected_intel["projection_receipt"]),
		"campaign_catalog_id": String(campaign_catalog["catalog_id"]),
		"campaign_catalog_receipt": String(campaign_catalog["catalog_receipt"]),
		"campaign_owner_scope": campaign_owner_scope,
		"accepted_campaign_state_receipt": accepted_campaign_state_receipt,
		"campaign_epoch": int(normalized_campaign["epoch_index"]),
		"campaign_season": String(normalized_campaign["season"]),
		"campaign_phase": String(normalized_campaign["phase"]),
		"covenant_catalog_id": String(normalized_covenant_catalog["catalog_id"]),
		"covenant_catalog_receipt": String(normalized_covenant_catalog["catalog_receipt"]),
		"accepted_covenant_state_receipt": accepted_covenant_state_receipt,
		"covenant_record_id": String(covenant_record["record_id"]),
		"covenant_record_receipt": String(covenant_record["record_receipt"]),
		"required_action": String(covenant_record["required_action"]),
		"effective_due_epoch": int(expected_obligation["effective_due_epoch"]),
		"obligation_projection_id": String(expected_obligation["projection_id"]),
		"obligation_projection_receipt": String(
			expected_obligation["projection_receipt"]
		),
		"priors": priors,
		"role_assignments": roles,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["evidence_id"] = EVIDENCE_ID_PREFIX + digest.substr(0, 16)
	base["evidence_receipt"] = _receipt_for(base)
	return base if String(base["evidence_receipt"]) != "" else {}


static func validate_evidence_envelope(catalog: Dictionary, atlas: Dictionary,
		atlas_state: Dictionary, accepted_atlas_state_receipt: String,
		network_catalog: Dictionary, network_state: Dictionary,
		accepted_network_state_receipt: String, intel_projection: Dictionary,
		campaign_catalog: Dictionary, campaign_state: Dictionary,
		accepted_campaign_state_receipt: String, campaign_owner_scope: String,
		covenant_catalog: Dictionary, covenant_state: Dictionary,
		accepted_covenant_state_receipt: String,
		obligation_projection: Dictionary, global_network_scope: String,
		value: Variant) -> Array[String]:
	var expected := make_evidence_envelope(
		catalog, atlas, atlas_state, accepted_atlas_state_receipt,
		network_catalog, network_state, accepted_network_state_receipt,
		intel_projection, campaign_catalog, campaign_state,
		accepted_campaign_state_receipt, campaign_owner_scope,
		covenant_catalog, covenant_state, accepted_covenant_state_receipt,
		obligation_projection, global_network_scope
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["recon evidence does not derive from exact accepted RP3/RP6/RP7/RP8 inputs"]
	return []


static func normalize_evidence_envelope(catalog: Dictionary, atlas: Dictionary,
		atlas_state: Dictionary, accepted_atlas_state_receipt: String,
		network_catalog: Dictionary, network_state: Dictionary,
		accepted_network_state_receipt: String, intel_projection: Dictionary,
		campaign_catalog: Dictionary, campaign_state: Dictionary,
		accepted_campaign_state_receipt: String, campaign_owner_scope: String,
		covenant_catalog: Dictionary, covenant_state: Dictionary,
		accepted_covenant_state_receipt: String,
		obligation_projection: Dictionary, global_network_scope: String,
		value: Variant) -> Dictionary:
	var expected := make_evidence_envelope(
		catalog, atlas, atlas_state, accepted_atlas_state_receipt,
		network_catalog, network_state, accepted_network_state_receipt,
		intel_projection, campaign_catalog, campaign_state,
		accepted_campaign_state_receipt, campaign_owner_scope,
		covenant_catalog, covenant_state, accepted_covenant_state_receipt,
		obligation_projection, global_network_scope
	)
	return expected if not expected.is_empty() and value is Dictionary \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func _make_priors(catalog: Dictionary, atlas: Dictionary,
		atlas_state: Dictionary, network_catalog: Dictionary,
		intel_projection: Dictionary) -> Array[Dictionary]:
	var discovered := {}
	for raw_tile_id in atlas_state["discovered_tile_ids"]:
		discovered[String(raw_tile_id)] = true
	var atlas_tiles := {}
	for raw_tile in atlas["tiles"]:
		var tile: Dictionary = raw_tile
		atlas_tiles[String(tile["id"])] = true
	var redglass_site_id := ""
	for raw_context in network_catalog.get("context_sites", []):
		if raw_context is Dictionary and String((raw_context as Dictionary).get(
				"site_key", "")) == "redglass_quarry":
			redglass_site_id = String((raw_context as Dictionary).get("site_id", ""))
	if redglass_site_id == "":
		return []
	var redglass_offer_id := ""
	for raw_offer in network_catalog.get("offers", []):
		if not (raw_offer is Dictionary):
			return []
		var template: Dictionary = (raw_offer as Dictionary).get("intel_template", {})
		if String(template.get("intel_key", "")) == "redglass_route_watch":
			if redglass_offer_id != "" or template.get("subject_site_id") \
					!= redglass_site_id or template.get("topic") \
					!= "quarry_route_activity":
				return []
			redglass_offer_id = String((raw_offer as Dictionary).get("offer_id", ""))
	if redglass_offer_id == "":
		return []
	var evidence_by_region := {}
	for raw_available in intel_projection["available"]:
		var available: Dictionary = raw_available
		if String(available.get("subject_site_id", "")) != redglass_site_id \
				or String(available.get("topic", "")) != "quarry_route_activity" \
				or String(available.get("offer_id", "")) != redglass_offer_id:
			continue
		var subject := ScaleAddress.parse_id(String(available["subject_site_id"]))
		if ScaleAddress.level_of(subject) != ScaleAddress.LEVEL_SITE:
			return []
		var tile := ScaleAddress.parent(subject)
		var region := ScaleAddress.parent(tile)
		var tile_id := ScaleAddress.canonical_id(tile)
		var region_id := ScaleAddress.canonical_id(region)
		if int(subject.get("face", -1)) != 0 or not atlas_tiles.has(tile_id) \
				or not discovered.has(tile_id):
			continue
		if not evidence_by_region.has(region_id):
			evidence_by_region[region_id] = []
		(evidence_by_region[region_id] as Array).append(String(
			available["intel_receipt"]
		))
	var priors: Array[Dictionary] = []
	for raw_question in catalog["questions"]:
		var question: Dictionary = raw_question
		var region_id := String(question["region_id"])
		var evidence: Array[String] = []
		for raw_receipt in evidence_by_region.get(region_id, []):
			evidence.append(String(raw_receipt))
		evidence.sort()
		var address := ScaleAddress.parse_id(region_id)
		var face := int(address.get("face", -1))
		var grounded := not evidence.is_empty()
		var minimum := GROUNDED_PRIOR_MIN_BP if grounded else BROAD_PRIOR_MIN_BP
		var maximum := GROUNDED_PRIOR_MAX_BP if grounded else BROAD_PRIOR_MAX_BP
		priors.append({
			"question_id": String(question["question_id"]),
			"question_receipt": String(question["question_receipt"]),
			"window_id": String(question["window_id"]),
			"region_id": region_id,
			"grounding_status": "grounded" if grounded \
				else ("unscouted" if face == 0 else "external_only"),
			"minimum_bp": minimum,
			"maximum_bp": maximum,
			"width_bp": maximum - minimum,
			"grounding_evidence_receipts": evidence,
		})
	priors.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["question_id"]) < String(right["question_id"]))
	return priors


static func _atlas_matches_planet(atlas: Dictionary, planet_id: String) -> bool:
	var planet := ScaleAddress.parse_id(planet_id)
	if ScaleAddress.level_of(planet) != ScaleAddress.LEVEL_PLANET \
			or ScaleAddress.canonical_id(planet) != planet_id:
		return false
	var planet_key := String(planet.get("planet", ""))
	for raw_tile in atlas.get("tiles", []):
		if not (raw_tile is Dictionary):
			return false
		var tile := ScaleAddress.parse_id(String((raw_tile as Dictionary).get("id", "")))
		if ScaleAddress.level_of(tile) != ScaleAddress.LEVEL_TILE \
				or String(tile.get("planet", "")) != planet_key:
			return false
	return true


static func _make_role_assignments(catalog: Dictionary,
		campaign_catalog: Dictionary, covenant_catalog: Dictionary,
		covenant_record: Dictionary) -> Array[Dictionary]:
	var covenant := _covenant_by_id(
		covenant_catalog, String(covenant_record["covenant_id"])
	)
	if covenant.is_empty():
		return []
	var directive := _directive_by_id(
		campaign_catalog, String(covenant["directive_id"])
	)
	if directive.is_empty():
		return []
	var origin_id := String(directive["origin_window_id"])
	var target_id := String(directive["target_window_id"])
	var fallback_id := ""
	for raw_question in catalog["questions"]:
		var question: Dictionary = raw_question
		var window_id := String(question["window_id"])
		if window_id not in [origin_id, target_id]:
			if fallback_id != "":
				return []
			fallback_id = window_id
	if fallback_id == "" or origin_id == target_id:
		return []
	var window_by_role := {
		"duty": origin_id,
		"spillover": target_id,
		"fallback": fallback_id,
	}
	var result: Array[Dictionary] = []
	for role in ROLES:
		var question := _question_by_window(catalog, String(window_by_role[role]))
		if question.is_empty():
			return []
		result.append({
			"role": role,
			"question_id": String(question["question_id"]),
			"question_receipt": String(question["question_receipt"]),
			"window_id": String(question["window_id"]),
			"region_id": String(question["region_id"]),
		})
	return result


static func make_initial_state(catalog: Dictionary,
		evidence: Dictionary) -> Dictionary:
	if not _catalog_self_valid(catalog) or not _evidence_self_valid(catalog, evidence):
		return {}
	var beliefs := _make_initial_beliefs(catalog, evidence)
	if beliefs.size() != 3:
		return {}
	return _make_state(
		catalog, evidence, 0, "open", "", beliefs, {}, {}, {}, [], [], "", ""
	)


static func validate_state(catalog: Dictionary, value: Variant) -> Array[String]:
	if not _catalog_self_valid(catalog):
		return ["planet recon state requires a valid catalog"]
	if not (value is Dictionary):
		return ["planet recon state must be a Dictionary"]
	var data: Dictionary = value
	var required := ["schema", "terms_revision", "catalog_id", "catalog_receipt",
		"revision", "phase", "outcome", "evidence_snapshot_receipt",
		"campaign_state_receipt", "covenant_state_receipt", "covenant_record_id",
		"covenant_record_receipt", "effective_due_epoch", "beliefs",
		"commitment_record", "observation_bundle_record", "stale_record",
		"consumed_recon_keys", "consumed_observation_keys",
		"parent_state_receipt", "last_action_receipt", "state_receipt"]
	if not _exact_keys(data, required) or not (data.get("beliefs") is Array) \
			or not (data.get("commitment_record") is Dictionary) \
			or not (data.get("observation_bundle_record") is Dictionary) \
			or not (data.get("stale_record") is Dictionary) \
			or not (data.get("consumed_recon_keys") is Array) \
			or not (data.get("consumed_observation_keys") is Array):
		return ["planet recon state fields must match V1 exactly"]
	if data.get("schema") != STATE_SCHEMA or data.get("terms_revision") != TERMS_REVISION \
			or data.get("catalog_id") != catalog.get("catalog_id") \
			or data.get("catalog_receipt") != catalog.get("catalog_receipt") \
			or not _bounded_int(data.get("revision"), 0, MAX_STATE_REVISION) \
			or _string_if(data.get("phase")) not in PHASES \
			or _string_if(data.get("outcome")) not in OUTCOMES \
			or not _receipt_token_valid(_string_if(
				data.get("evidence_snapshot_receipt")
			)) or not _receipt_token_valid(_string_if(
				data.get("campaign_state_receipt")
			)) or not _receipt_token_valid(_string_if(
				data.get("covenant_state_receipt")
			)) or not _short_id_valid(_string_if(
				data.get("covenant_record_id")
			), "ccr1:") or not _receipt_token_valid(_string_if(
				data.get("covenant_record_receipt")
			)) or not _bounded_int(data.get("effective_due_epoch"), 1, 3):
		return ["planet recon state identity or lifecycle scalar is invalid"]
	var beliefs: Array = data["beliefs"]
	if not _beliefs_valid(catalog, beliefs):
		return ["planet recon state belief ledger is invalid"]
	var commitment: Dictionary = data["commitment_record"]
	var observation: Dictionary = data["observation_bundle_record"]
	var stale: Dictionary = data["stale_record"]
	var phase := String(data["phase"])
	var outcome := String(data["outcome"])
	var revision := int(data["revision"])
	if revision == 0:
		if phase != "open" or outcome != "" or not commitment.is_empty() \
				or not observation.is_empty() or not stale.is_empty() \
				or not _beliefs_all_unobserved(beliefs):
			return ["open planet recon state cannot contain lifecycle effects"]
	elif revision == 1:
		if phase != "committed" or outcome != "" \
				or not _commit_record_valid(catalog, data, commitment) \
				or not observation.is_empty() or not stale.is_empty() \
				or not _beliefs_all_unobserved(beliefs):
			return ["committed planet recon state ledger is invalid"]
	elif phase != "terminal" or outcome not in ["resolved", "stale"] \
			or not _commit_record_valid(catalog, data, commitment):
		return ["terminal planet recon state ledger is invalid"]
	elif outcome == "resolved":
		if not stale.is_empty() or not _resolution_record_valid(
				catalog, data, commitment, observation, beliefs
			):
			return ["resolved planet recon state evidence is invalid"]
	else:
		if not observation.is_empty() or not _stale_record_valid(
				data, commitment, stale
			) or not _beliefs_all_unobserved(beliefs) \
				or String(commitment.get("before_beliefs_receipt", "")) \
				!= _receipt_for(beliefs):
			return ["stale planet recon state evidence is invalid"]
	var expected_recon_keys: Array[String] = []
	if not commitment.is_empty():
		expected_recon_keys.append(String(commitment["recon_replay_key"]))
	var expected_observation_keys: Array[String] = []
	if not observation.is_empty():
		expected_observation_keys.append(String(observation["observation_replay_key"]))
	if _canonical_json(expected_recon_keys) != _canonical_json(
		data["consumed_recon_keys"]
	) or _canonical_json(expected_observation_keys) != _canonical_json(
		data["consumed_observation_keys"]
	) or not _sorted_unique_receipts(data["consumed_recon_keys"]) \
			or not _sorted_unique_receipts(data["consumed_observation_keys"]):
		return ["planet recon replay ledgers are invalid"]
	for key in ["parent_state_receipt", "last_action_receipt", "state_receipt"]:
		if typeof(data.get(key)) != TYPE_STRING:
			return ["planet recon state chain receipts must be Strings"]
	if revision == 0:
		if String(data["parent_state_receipt"]) != "" \
				or String(data["last_action_receipt"]) != "":
			return ["initial planet recon state cannot have a parent action"]
	elif not _receipt_token_valid(String(data["parent_state_receipt"])) \
			or not _receipt_token_valid(String(data["last_action_receipt"])):
		return ["planet recon state chain receipts are invalid"]
	if revision > 0:
		var prior_beliefs := _make_unobserved_beliefs_from_state(data)
		var expected_open := _make_state(
			catalog, _state_anchor_evidence(data), 0, "open", "", prior_beliefs,
			{}, {}, {}, [], [], "", ""
		)
		if expected_open.is_empty():
			return ["planet recon state cannot reconstruct its open checkpoint"]
		if revision == 1:
			if data.get("parent_state_receipt") != expected_open.get("state_receipt") \
					or data.get("last_action_receipt") \
					!= commitment.get("record_receipt"):
				return ["committed planet recon state parent chain is invalid"]
		else:
			var expected_committed := _make_state(
				catalog, _state_anchor_evidence(data), 1, "committed", "",
				prior_beliefs, commitment, {}, {},
				[String(commitment["recon_replay_key"])], [],
				String(expected_open["state_receipt"]),
				String(commitment["record_receipt"])
			)
			var expected_action_receipt := String(
				observation.get("record_receipt", "") if outcome == "resolved" \
				else stale.get("record_receipt", "")
			)
			if expected_committed.is_empty() or data.get("parent_state_receipt") \
					!= expected_committed.get("state_receipt") \
					or data.get("last_action_receipt") != expected_action_receipt:
				return ["terminal planet recon state parent chain is invalid"]
	var base := data.duplicate(true)
	base.erase("state_receipt")
	if String(data["state_receipt"]) != _receipt_for(base):
		return ["planet recon state receipt mismatch"]
	return []


static func normalize_state(catalog: Dictionary, value: Variant) -> Dictionary:
	if not (value is Dictionary) or not validate_state(catalog, value).is_empty():
		return {}
	var result: Dictionary = (value as Dictionary).duplicate(true)
	result["revision"] = int(result["revision"])
	result["effective_due_epoch"] = int(result["effective_due_epoch"])
	var normalized_beliefs: Array[Dictionary] = []
	for raw_belief in result["beliefs"]:
		var belief: Dictionary = (raw_belief as Dictionary).duplicate(true)
		for key in ["minimum_bp", "maximum_bp", "width_bp"]:
			belief[key] = int(belief[key])
		normalized_beliefs.append(belief)
	result["beliefs"] = normalized_beliefs
	var commit: Dictionary = result["commitment_record"]
	if not commit.is_empty():
		for key in ["effective_due_epoch", "point_cost", "points_before",
				"points_applied", "points_after"]:
			commit[key] = int(commit[key])
		var normalized_probes: Array[Dictionary] = []
		for raw_probe in commit["selected_probes"]:
			var probe: Dictionary = (raw_probe as Dictionary).duplicate(true)
			for key in ["prior_width_bp", "posterior_width_bp", "reduction_bp"]:
				probe[key] = int(probe[key])
			normalized_probes.append(probe)
		commit["selected_probes"] = normalized_probes
	var stale: Dictionary = result["stale_record"]
	if not stale.is_empty():
		stale["recon_points_refunded"] = int(stale["recon_points_refunded"])
	return result


static func accept_state_checkpoint(catalog: Dictionary, value: Variant,
		expected_state_receipt: String) -> Dictionary:
	if not _receipt_token_valid(expected_state_receipt):
		return {}
	var normalized := normalize_state(catalog, value)
	return normalized if not normalized.is_empty() \
		and String(normalized["state_receipt"]) == expected_state_receipt else {}


static func _make_state(catalog: Dictionary, evidence: Dictionary, revision: int,
		phase: String, outcome: String, beliefs: Array, commitment: Dictionary,
		observation: Dictionary, stale: Dictionary, recon_keys: Array,
		observation_keys: Array, parent_receipt: String,
		last_action_receipt: String) -> Dictionary:
	var base := {
		"schema": STATE_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(catalog["catalog_id"]),
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"revision": revision,
		"phase": phase,
		"outcome": outcome,
		"evidence_snapshot_receipt": String(evidence["evidence_receipt"]),
		"campaign_state_receipt": String(evidence["accepted_campaign_state_receipt"]),
		"covenant_state_receipt": String(evidence["accepted_covenant_state_receipt"]),
		"covenant_record_id": String(evidence["covenant_record_id"]),
		"covenant_record_receipt": String(evidence["covenant_record_receipt"]),
		"effective_due_epoch": int(evidence["effective_due_epoch"]),
		"beliefs": beliefs.duplicate(true),
		"commitment_record": commitment.duplicate(true),
		"observation_bundle_record": observation.duplicate(true),
		"stale_record": stale.duplicate(true),
		"consumed_recon_keys": recon_keys.duplicate(true),
		"consumed_observation_keys": observation_keys.duplicate(true),
		"parent_state_receipt": parent_receipt,
		"last_action_receipt": last_action_receipt,
	}
	base["state_receipt"] = _receipt_for(base)
	return base if String(base["state_receipt"]) != "" else {}


static func _make_initial_beliefs(catalog: Dictionary,
		evidence: Dictionary) -> Array[Dictionary]:
	var roles_by_question := {}
	for raw_role in evidence["role_assignments"]:
		var assignment: Dictionary = raw_role
		roles_by_question[String(assignment["question_id"])] = String(
			assignment["role"]
		)
	var beliefs: Array[Dictionary] = []
	for raw_prior in evidence["priors"]:
		var prior: Dictionary = raw_prior
		var question := _question_by_id(catalog, String(prior["question_id"]))
		var role := String(roles_by_question.get(String(prior["question_id"]), ""))
		if question.is_empty() or role not in ROLES:
			return []
		beliefs.append({
			"question_id": String(prior["question_id"]),
			"question_receipt": String(prior["question_receipt"]),
			"window_id": String(prior["window_id"]),
			"region_id": String(prior["region_id"]),
			"role": role,
			"minimum_bp": int(prior["minimum_bp"]),
			"maximum_bp": int(prior["maximum_bp"]),
			"width_bp": int(prior["width_bp"]),
			"status": "unobserved",
			"grounding_status": String(prior["grounding_status"]),
			"grounding_evidence_receipts": prior[
				"grounding_evidence_receipts"
			].duplicate(),
			"observed_signal": "",
			"observation_receipt": "",
		})
	beliefs.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["question_id"]) < String(right["question_id"]))
	return beliefs


static func _catalog_self_valid(catalog: Dictionary) -> bool:
	var required := ["schema", "terms_revision", "campaign_catalog_id",
		"campaign_catalog_receipt", "covenant_catalog_id",
		"covenant_catalog_receipt", "planet_id", "portfolio_cost",
		"required_probes", "questions", "catalog_id", "catalog_receipt"]
	if not _exact_keys(catalog, required) or catalog.get("schema") != CATALOG_SCHEMA \
			or catalog.get("terms_revision") != TERMS_REVISION \
			or not _short_id_valid(_string_if(catalog.get("catalog_id")), CATALOG_ID_PREFIX) \
			or not _receipt_token_valid(_string_if(catalog.get("catalog_receipt"))) \
			or not _short_id_valid(_string_if(
				catalog.get("campaign_catalog_id")
			), "pcc1:") or not _receipt_token_valid(_string_if(
				catalog.get("campaign_catalog_receipt")
			)) or not _short_id_valid(_string_if(
				catalog.get("covenant_catalog_id")
			), "ccc1:") or not _receipt_token_valid(_string_if(
				catalog.get("covenant_catalog_receipt")
			)) or not _bounded_int(catalog.get("portfolio_cost"), 2, 2) \
			or not _bounded_int(catalog.get("required_probes"), 2, 2) \
			or not (catalog.get("questions") is Array):
		return false
	var questions: Array = catalog["questions"]
	if questions.size() != 3:
		return false
	var previous := ""
	var windows := {}
	var regions := {}
	for raw_question in questions:
		if not (raw_question is Dictionary) \
				or not _question_valid(catalog, raw_question as Dictionary):
			return false
		var question: Dictionary = raw_question
		var question_id := String(question["question_id"])
		if question_id <= previous or windows.has(String(question["window_id"])) \
				or regions.has(String(question["region_id"])):
			return false
		previous = question_id
		windows[String(question["window_id"])] = true
		regions[String(question["region_id"])] = true
	var id_base := catalog.duplicate(true)
	id_base.erase("catalog_id")
	id_base.erase("catalog_receipt")
	var digest := _sha256_hex(_canonical_json(id_base))
	return digest != "" and String(catalog["catalog_id"]) \
		== CATALOG_ID_PREFIX + digest.substr(0, 16) \
		and String(catalog["catalog_receipt"]) == "sha256:" + digest


static func _question_valid(catalog: Dictionary, question: Dictionary) -> bool:
	var required := ["terms_revision", "campaign_catalog_receipt",
		"covenant_catalog_receipt", "window_id", "window_key", "region_id",
		"faction_id", "window_seed_receipt", "question_kind",
		"broad_prior_min_bp", "broad_prior_max_bp", "grounded_prior_min_bp",
		"grounded_prior_max_bp", "posterior_width_bp", "question_id",
		"question_receipt"]
	if not _exact_keys(question, required) \
			or question.get("terms_revision") != TERMS_REVISION \
			or question.get("campaign_catalog_receipt") \
			!= catalog.get("campaign_catalog_receipt") \
			or question.get("covenant_catalog_receipt") \
			!= catalog.get("covenant_catalog_receipt") \
			or not _short_id_valid(_string_if(
				question.get("question_id")
			), QUESTION_ID_PREFIX) \
			or not _receipt_token_valid(_string_if(question.get("question_receipt"))) \
			or not (question.get("window_seed_receipt") is Dictionary) \
			or not ScaleAddress.validate_receipt(
				question.get("window_seed_receipt")
			).is_empty() or (question.get("window_seed_receipt") as Dictionary).get(
				"address"
			) != question.get("region_id") \
			or question.get("question_kind") != "future_support_evidence" \
			or not _bounded_int(question.get("broad_prior_min_bp"), 2000, 2000) \
			or not _bounded_int(question.get("broad_prior_max_bp"), 8000, 8000) \
			or not _bounded_int(question.get("grounded_prior_min_bp"), 3000, 3000) \
			or not _bounded_int(question.get("grounded_prior_max_bp"), 7000, 7000) \
			or not _bounded_int(question.get("posterior_width_bp"), 2000, 2000):
		return false
	if not _short_id_valid(_string_if(question.get("window_id")), "pcw1:"):
		return false
	for key in ["window_key", "faction_id"]:
		if not _slug_valid(_string_if(question.get(key))):
			return false
	var region := ScaleAddress.parse_id(_string_if(question.get("region_id")))
	if ScaleAddress.level_of(region) != ScaleAddress.LEVEL_REGION:
		return false
	var id_base := question.duplicate(true)
	id_base.erase("question_id")
	id_base.erase("question_receipt")
	var digest := _sha256_hex(_canonical_json(id_base))
	var receipt_base := question.duplicate(true)
	receipt_base.erase("question_receipt")
	return digest != "" and String(question["question_id"]) \
		== QUESTION_ID_PREFIX + digest.substr(0, 16) \
		and String(question["question_receipt"]) == _receipt_for(receipt_base)


static func _evidence_self_valid(catalog: Dictionary, evidence: Dictionary) -> bool:
	var required := ["schema", "terms_revision", "catalog_id", "catalog_receipt",
		"atlas_id", "atlas_receipt", "accepted_atlas_state_receipt",
		"network_catalog_id", "network_catalog_receipt", "global_network_scope",
		"accepted_network_state_receipt", "intel_projection_id",
		"intel_projection_receipt", "campaign_catalog_id",
		"campaign_catalog_receipt", "campaign_owner_scope",
		"accepted_campaign_state_receipt", "campaign_epoch", "campaign_season",
		"campaign_phase", "covenant_catalog_id", "covenant_catalog_receipt",
		"accepted_covenant_state_receipt", "covenant_record_id",
		"covenant_record_receipt", "required_action", "effective_due_epoch",
		"obligation_projection_id", "obligation_projection_receipt", "priors",
		"role_assignments", "evidence_id", "evidence_receipt"]
	if not _exact_keys(evidence, required) or evidence.get("schema") != EVIDENCE_SCHEMA \
			or evidence.get("terms_revision") != TERMS_REVISION \
			or evidence.get("catalog_id") != catalog.get("catalog_id") \
			or evidence.get("catalog_receipt") != catalog.get("catalog_receipt") \
			or not (evidence.get("priors") is Array) \
			or not (evidence.get("role_assignments") is Array) \
			or not _short_id_valid(_string_if(evidence.get("evidence_id")), EVIDENCE_ID_PREFIX) \
			or not _receipt_token_valid(_string_if(evidence.get("evidence_receipt"))) \
			or not _slug_valid(_string_if(evidence.get("campaign_owner_scope"))) \
			or not _slug_valid(_string_if(evidence.get("global_network_scope"))) \
			or evidence.get("campaign_owner_scope") == evidence.get("global_network_scope") \
			or not _bounded_int(evidence.get("campaign_epoch"), 0, 2) \
			or not _bounded_int(evidence.get("effective_due_epoch"), 1, 3) \
			or int(evidence.get("campaign_epoch")) >= int(evidence.get("effective_due_epoch")):
		return false
	for key in ["atlas_receipt", "accepted_atlas_state_receipt",
			"network_catalog_receipt", "accepted_network_state_receipt",
			"intel_projection_receipt", "campaign_catalog_receipt",
			"accepted_campaign_state_receipt", "covenant_catalog_receipt",
			"accepted_covenant_state_receipt", "covenant_record_receipt",
			"obligation_projection_receipt"]:
		if not _receipt_token_valid(_string_if(evidence.get(key))):
			return false
	if not _short_id_valid(_string_if(evidence.get("covenant_record_id")), "ccr1:") \
			or _string_if(evidence.get("required_action")) not in [
				"aid", "fortify", "trade"
			] or _string_if(evidence.get("campaign_season")) not in [
				"spring", "autumn", "winter"
			] or _string_if(evidence.get("campaign_phase")) not in [
				"open", "committed", "terminal"
			]:
		return false
	if not _priors_valid(catalog, evidence["priors"]) \
			or not _roles_valid(catalog, evidence["role_assignments"]):
		return false
	var id_base := evidence.duplicate(true)
	id_base.erase("evidence_id")
	id_base.erase("evidence_receipt")
	var digest := _sha256_hex(_canonical_json(id_base))
	var receipt_base := evidence.duplicate(true)
	receipt_base.erase("evidence_receipt")
	return digest != "" and String(evidence["evidence_id"]) \
		== EVIDENCE_ID_PREFIX + digest.substr(0, 16) \
		and String(evidence["evidence_receipt"]) == _receipt_for(receipt_base)


static func _priors_valid(catalog: Dictionary, priors: Array) -> bool:
	if priors.size() != 3:
		return false
	var previous := ""
	for raw_prior in priors:
		if not (raw_prior is Dictionary):
			return false
		var prior: Dictionary = raw_prior
		var required := ["question_id", "question_receipt", "window_id", "region_id",
			"grounding_status", "minimum_bp", "maximum_bp", "width_bp",
			"grounding_evidence_receipts"]
		var question := _question_by_id(catalog, _string_if(prior.get("question_id")))
		if not _exact_keys(prior, required) or question.is_empty() \
				or prior.get("question_receipt") != question.get("question_receipt") \
				or prior.get("window_id") != question.get("window_id") \
				or prior.get("region_id") != question.get("region_id") \
				or _string_if(prior.get("grounding_status")) not in [
					"external_only", "grounded", "unscouted"
				] or not _bounded_int(prior.get("minimum_bp"), MIN_BP, MAX_BP) \
				or not _bounded_int(prior.get("maximum_bp"), MIN_BP, MAX_BP) \
				or not _bounded_int(prior.get("width_bp"), 0, MAX_BP) \
				or not (prior.get("grounding_evidence_receipts") is Array):
			return false
		var minimum := int(prior["minimum_bp"])
		var maximum := int(prior["maximum_bp"])
		var grounded := String(prior["grounding_status"]) == "grounded"
		var region := ScaleAddress.parse_id(String(prior["region_id"]))
		if maximum - minimum != int(prior["width_bp"]) \
				or (grounded and [minimum, maximum, int(prior["width_bp"])] \
				!= [GROUNDED_PRIOR_MIN_BP, GROUNDED_PRIOR_MAX_BP, 4000]) \
				or (not grounded and [minimum, maximum, int(prior["width_bp"])] \
				!= [BROAD_PRIOR_MIN_BP, BROAD_PRIOR_MAX_BP, 6000]) \
				or not _sorted_unique_receipts(prior["grounding_evidence_receipts"]):
			return false
		if grounded != not (prior["grounding_evidence_receipts"] as Array).is_empty() \
				or int(region.get("face", -1)) == 0 and String(
					prior["grounding_status"]
				) == "external_only" \
				or int(region.get("face", -1)) != 0 and String(
					prior["grounding_status"]
				) != "external_only":
			return false
		var question_id := String(prior["question_id"])
		if question_id <= previous:
			return false
		previous = question_id
	return true


static func _roles_valid(catalog: Dictionary, roles: Array) -> bool:
	if roles.size() != 3:
		return false
	var seen_questions := {}
	for index in roles.size():
		if not (roles[index] is Dictionary):
			return false
		var assignment: Dictionary = roles[index]
		var required := ["role", "question_id", "question_receipt", "window_id",
			"region_id"]
		var question := _question_by_id(catalog, _string_if(
			assignment.get("question_id")
		))
		if not _exact_keys(assignment, required) or assignment.get("role") != ROLES[index] \
				or question.is_empty() \
				or assignment.get("question_receipt") != question.get("question_receipt") \
				or assignment.get("window_id") != question.get("window_id") \
				or assignment.get("region_id") != question.get("region_id") \
				or seen_questions.has(String(assignment["question_id"])):
			return false
		seen_questions[String(assignment["question_id"])] = true
	return true


static func _beliefs_valid(catalog: Dictionary, beliefs: Array) -> bool:
	if beliefs.size() != 3:
		return false
	var previous := ""
	var seen_roles := {}
	for raw_belief in beliefs:
		if not (raw_belief is Dictionary):
			return false
		var belief: Dictionary = raw_belief
		var required := ["question_id", "question_receipt", "window_id", "region_id",
			"role", "minimum_bp", "maximum_bp", "width_bp", "status",
			"grounding_status", "grounding_evidence_receipts", "observed_signal",
			"observation_receipt"]
		var question := _question_by_id(catalog, _string_if(belief.get("question_id")))
		if not _exact_keys(belief, required) or question.is_empty() \
				or belief.get("question_receipt") != question.get("question_receipt") \
				or belief.get("window_id") != question.get("window_id") \
				or belief.get("region_id") != question.get("region_id") \
				or _string_if(belief.get("role")) not in ROLES \
				or seen_roles.has(String(belief["role"])) \
				or _string_if(belief.get("status")) not in ["observed", "unobserved"] \
				or _string_if(belief.get("grounding_status")) not in [
					"external_only", "grounded", "unscouted"
				] or not (belief.get("grounding_evidence_receipts") is Array) \
				or not _sorted_unique_receipts(belief["grounding_evidence_receipts"]) \
				or not _bounded_int(belief.get("minimum_bp"), MIN_BP, MAX_BP) \
				or not _bounded_int(belief.get("maximum_bp"), MIN_BP, MAX_BP) \
				or not _bounded_int(belief.get("width_bp"), 0, MAX_BP):
			return false
		var minimum := int(belief["minimum_bp"])
		var maximum := int(belief["maximum_bp"])
		var observed := String(belief["status"]) == "observed"
		if maximum - minimum != int(belief["width_bp"]) \
				or (observed and int(belief["width_bp"]) != POSTERIOR_WIDTH_BP) \
				or (not observed and int(belief["width_bp"]) not in [4000, 6000]):
			return false
		if observed:
			if _string_if(belief.get("observed_signal")) not in SIGNALS \
					or not _receipt_token_valid(_string_if(
						belief.get("observation_receipt")
					)):
				return false
			var expected_bounds := _posterior_bounds(String(belief["observed_signal"]))
			if expected_bounds.is_empty() or minimum != int(expected_bounds[0]) \
					or maximum != int(expected_bounds[1]):
				return false
		elif String(belief.get("observed_signal", "")) != "" \
				or String(belief.get("observation_receipt", "")) != "":
			return false
		else:
			var grounded := String(belief["grounding_status"]) == "grounded"
			var expected_minimum := GROUNDED_PRIOR_MIN_BP \
				if grounded else BROAD_PRIOR_MIN_BP
			var expected_maximum := GROUNDED_PRIOR_MAX_BP \
				if grounded else BROAD_PRIOR_MAX_BP
			if minimum != expected_minimum or maximum != expected_maximum:
				return false
		if (String(belief["grounding_status"]) == "grounded") \
				!= not (belief["grounding_evidence_receipts"] as Array).is_empty():
			return false
		var region := ScaleAddress.parse_id(String(belief["region_id"]))
		if int(region.get("face", -1)) == 0 and String(
				belief["grounding_status"]
			) == "external_only" or int(region.get("face", -1)) != 0 \
				and String(belief["grounding_status"]) != "external_only":
			return false
		var question_id := String(belief["question_id"])
		if question_id <= previous:
			return false
		previous = question_id
		seen_roles[String(belief["role"])] = true
	return seen_roles.size() == 3


static func _beliefs_all_unobserved(beliefs: Array) -> bool:
	for raw_belief in beliefs:
		if not (raw_belief is Dictionary) \
				or (raw_belief as Dictionary).get("status") != "unobserved":
			return false
	return true


static func _probe_valid(catalog: Dictionary, probe: Dictionary) -> bool:
	var required := ["terms_revision", "catalog_receipt", "question_id",
		"question_receipt", "role", "window_id", "region_id", "prior_width_bp",
		"posterior_width_bp", "reduction_bp", "probe_id", "probe_receipt"]
	var question := _question_by_id(catalog, _string_if(probe.get("question_id")))
	if not _exact_keys(probe, required) or probe.get("terms_revision") != TERMS_REVISION \
			or probe.get("catalog_receipt") != catalog.get("catalog_receipt") \
			or question.is_empty() or probe.get("question_receipt") \
			!= question.get("question_receipt") or probe.get("window_id") \
			!= question.get("window_id") or probe.get("region_id") \
			!= question.get("region_id") or _string_if(probe.get("role")) not in ROLES \
			or not _bounded_int(probe.get("prior_width_bp"), 4000, 6000) \
			or not _bounded_int(probe.get("posterior_width_bp"), 2000, 2000) \
			or not _bounded_int(probe.get("reduction_bp"), 2000, 4000) \
			or int(probe.get("prior_width_bp")) - POSTERIOR_WIDTH_BP \
			!= int(probe.get("reduction_bp")) \
			or not _short_id_valid(_string_if(probe.get("probe_id")), PROBE_ID_PREFIX) \
			or not _receipt_token_valid(_string_if(probe.get("probe_receipt"))):
		return false
	var id_base := probe.duplicate(true)
	id_base.erase("probe_id")
	id_base.erase("probe_receipt")
	var digest := _sha256_hex(_canonical_json(id_base))
	if digest == "" or String(probe["probe_id"]) \
			!= PROBE_ID_PREFIX + digest.substr(0, 16):
		return false
	var receipt_base := probe.duplicate(true)
	receipt_base.erase("probe_receipt")
	return String(probe["probe_receipt"]) == _receipt_for(receipt_base)


static func _commit_record_valid(catalog: Dictionary, state: Dictionary,
		record: Dictionary) -> bool:
	var required := ["schema", "terms_revision", "catalog_receipt",
		"evidence_snapshot_receipt", "campaign_state_receipt",
		"covenant_state_receipt", "campaign_owner_scope", "global_network_scope",
		"covenant_record_id", "covenant_record_receipt",
		"effective_due_epoch", "portfolio_id", "option_receipt", "choice_id",
		"choice_receipt", "selected_roles", "selected_probes", "point_cost",
		"recon_owner_scope", "recon_owner_checkpoint_receipt", "recon_anchor_id",
		"recon_anchor_receipt", "recon_replay_key", "points_before",
		"points_applied", "points_after", "before_beliefs_receipt", "record_id",
		"record_receipt"]
	if not _exact_keys(record, required) or record.get("schema") \
			!= COMMIT_RECORD_SCHEMA or record.get("terms_revision") != TERMS_REVISION \
			or record.get("catalog_receipt") != catalog.get("catalog_receipt") \
			or record.get("evidence_snapshot_receipt") \
			!= state.get("evidence_snapshot_receipt") \
			or record.get("campaign_state_receipt") \
			!= state.get("campaign_state_receipt") \
			or record.get("covenant_state_receipt") \
			!= state.get("covenant_state_receipt") \
			or not _slug_valid(_string_if(record.get("campaign_owner_scope"))) \
			or not _slug_valid(_string_if(record.get("global_network_scope"))) \
			or record.get("campaign_owner_scope") == record.get("global_network_scope") \
			or record.get("covenant_record_id") != state.get("covenant_record_id") \
			or record.get("covenant_record_receipt") \
			!= state.get("covenant_record_receipt") \
			or not _bounded_int(record.get("effective_due_epoch"), 1, 3) \
			or int(record.get("effective_due_epoch")) \
			!= int(state.get("effective_due_epoch")) \
			or not _short_id_valid(_string_if(record.get("portfolio_id")), PORTFOLIO_ID_PREFIX) \
			or not _receipt_token_valid(_string_if(record.get("option_receipt"))) \
			or not _short_id_valid(_string_if(record.get("choice_id")), CHOICE_ID_PREFIX) \
			or not _receipt_token_valid(_string_if(record.get("choice_receipt"))) \
			or not (record.get("selected_roles") is Array) \
			or not (record.get("selected_probes") is Array) \
			or not _bounded_int(record.get("point_cost"), 2, 2) \
			or not _slug_valid(_string_if(record.get("recon_owner_scope"))) \
			or record.get("recon_owner_scope") == record.get("campaign_owner_scope") \
			or record.get("recon_owner_scope") == record.get("global_network_scope") \
			or not _receipt_token_valid(_string_if(
				record.get("recon_owner_checkpoint_receipt")
			)) or not _short_id_valid(_string_if(
				record.get("recon_anchor_id")
			), ANCHOR_ID_PREFIX) or not _receipt_token_valid(_string_if(
				record.get("recon_anchor_receipt")
			)) or not _receipt_token_valid(_string_if(record.get("recon_replay_key"))) \
			or not _bounded_int(record.get("points_before"), 2, MAX_RECON_POINTS) \
			or not _bounded_int(record.get("points_applied"), -2, -2) \
			or not _bounded_int(record.get("points_after"), 0, MAX_RECON_POINTS) \
			or int(record.get("points_after")) \
			!= int(record.get("points_before")) - PORTFOLIO_COST \
			or not _receipt_token_valid(_string_if(
				record.get("before_beliefs_receipt")
			)) or not _short_id_valid(_string_if(
				record.get("record_id")
			), COMMIT_RECORD_ID_PREFIX) or not _receipt_token_valid(_string_if(
				record.get("record_receipt")
			)):
		return false
	if String(record["recon_replay_key"]) != _receipt_for([
		String(record["recon_owner_scope"]),
		String(record["recon_owner_checkpoint_receipt"]),
	]):
		return false
	var expected_anchor := make_recon_anchor(
		String(record["recon_owner_scope"]),
		String(record["recon_owner_checkpoint_receipt"]),
		String(state["evidence_snapshot_receipt"]), int(record["points_before"])
	)
	if expected_anchor.is_empty() or record.get("recon_anchor_id") \
			!= expected_anchor.get("anchor_id") or record.get("recon_anchor_receipt") \
			!= expected_anchor.get("anchor_receipt") or record.get("recon_replay_key") \
			!= expected_anchor.get("commitment_replay_key"):
		return false
	var roles: Array = record["selected_roles"]
	var probes: Array = record["selected_probes"]
	if roles.size() != REQUIRED_PROBES or probes.size() != REQUIRED_PROBES:
		return false
	var prior_beliefs := _make_unobserved_beliefs_from_state(state)
	if prior_beliefs.size() != 3:
		return false
	var seen_questions := {}
	var seen_roles := {}
	var previous_probe := ""
	for raw_probe in probes:
		if not (raw_probe is Dictionary) \
				or not _probe_valid(catalog, raw_probe as Dictionary):
			return false
		var probe: Dictionary = raw_probe
		var expected_probe := _make_probe(
			catalog, _belief_by_role(prior_beliefs, String(probe["role"]))
		)
		var probe_id := String(probe["probe_id"])
		if expected_probe.is_empty() or _canonical_json(expected_probe) \
				!= _canonical_json(probe) or probe_id <= previous_probe \
				or seen_questions.has(String(probe["question_id"])) \
				or seen_roles.has(String(probe["role"])):
			return false
		previous_probe = probe_id
		seen_questions[String(probe["question_id"])] = true
		seen_roles[String(probe["role"])] = true
	var expected_roles: Array[String] = []
	for role in ROLES:
		if seen_roles.has(role):
			expected_roles.append(role)
	var expected_open_state := _make_state(
		catalog, _state_anchor_evidence(state), 0, "open", "", prior_beliefs,
		{}, {}, {}, [], [], "", ""
	)
	var expected_option := _make_portfolio_option(
		catalog, expected_open_state, expected_roles
	) if not expected_open_state.is_empty() else {}
	var expected_board := _rebuild_commit_board(
		catalog, expected_open_state, expected_anchor
	) if not expected_open_state.is_empty() else {}
	var expected_choice := make_portfolio_choice(
		catalog, expected_board, String(record["portfolio_id"])
	) if not expected_board.is_empty() else {}
	if expected_option.is_empty() \
			or expected_choice.is_empty() \
			or record.get("portfolio_id") != expected_option.get("portfolio_id") \
			or record.get("option_receipt") != expected_option.get("option_receipt") \
			or record.get("choice_id") != expected_choice.get("choice_id") \
			or record.get("choice_receipt") != expected_choice.get("choice_receipt") \
			or _canonical_json(probes) != _canonical_json(expected_option.get(
				"probes", []
			)) or _canonical_json(expected_roles) != _canonical_json(roles) \
			or String(record["before_beliefs_receipt"]) != _receipt_for(
				_make_unobserved_beliefs_from_state(state)
			):
		return false
	var id_base := record.duplicate(true)
	id_base.erase("record_id")
	id_base.erase("record_receipt")
	var digest := _sha256_hex(_canonical_json(id_base))
	if digest == "" or String(record["record_id"]) \
			!= COMMIT_RECORD_ID_PREFIX + digest.substr(0, 16):
		return false
	var receipt_base := record.duplicate(true)
	receipt_base.erase("record_receipt")
	return String(record["record_receipt"]) == _receipt_for(receipt_base)


static func _resolution_record_valid(catalog: Dictionary, state: Dictionary,
		commitment: Dictionary, record: Dictionary, beliefs: Array) -> bool:
	var required := ["schema", "terms_revision", "catalog_receipt",
		"evidence_snapshot_receipt", "commitment_record_id",
		"commitment_record_receipt", "observation_bundle_id",
		"observation_bundle_receipt", "observation_owner_scope",
		"observation_owner_checkpoint_receipt", "observation_replay_key",
		"selected_probe_ids", "observation_receipts", "before_beliefs_receipt",
		"after_beliefs_receipt", "record_id", "record_receipt"]
	if not _exact_keys(record, required) or record.get("schema") \
			!= RESOLUTION_RECORD_SCHEMA or record.get("terms_revision") != TERMS_REVISION \
			or record.get("catalog_receipt") != catalog.get("catalog_receipt") \
			or record.get("evidence_snapshot_receipt") \
			!= state.get("evidence_snapshot_receipt") \
			or record.get("commitment_record_id") != commitment.get("record_id") \
			or record.get("commitment_record_receipt") \
			!= commitment.get("record_receipt") \
			or not _short_id_valid(_string_if(
				record.get("observation_bundle_id")
			), OBSERVATION_ID_PREFIX) or not _receipt_token_valid(_string_if(
				record.get("observation_bundle_receipt")
			)) or record.get("observation_owner_scope") \
			!= commitment.get("recon_owner_scope") \
			or not _receipt_token_valid(_string_if(
				record.get("observation_owner_checkpoint_receipt")
			)) or record.get("observation_owner_checkpoint_receipt") \
			== commitment.get("recon_owner_checkpoint_receipt") \
			or not _receipt_token_valid(_string_if(
				record.get("observation_replay_key")
			)) or not (record.get("selected_probe_ids") is Array) \
			or not (record.get("observation_receipts") is Array) \
			or record.get("before_beliefs_receipt") \
			!= commitment.get("before_beliefs_receipt") \
			or record.get("after_beliefs_receipt") != _receipt_for(beliefs) \
			or not _short_id_valid(_string_if(
				record.get("record_id")
			), RESOLUTION_RECORD_ID_PREFIX) \
			or not _receipt_token_valid(_string_if(record.get("record_receipt"))):
		return false
	var selected_ids: Array[String] = []
	var selected_questions := {}
	for raw_probe in commitment["selected_probes"]:
		var probe: Dictionary = raw_probe
		selected_ids.append(String(probe["probe_id"]))
		selected_questions[String(probe["question_id"])] = true
	selected_ids.sort()
	if _canonical_json(selected_ids) != _canonical_json(record["selected_probe_ids"]) \
			or not _sorted_unique_receipts(record["observation_receipts"]) \
			or String(record["observation_replay_key"]) != _receipt_for([
				String(record["observation_owner_scope"]),
				String(record["observation_owner_checkpoint_receipt"]),
				String(commitment["record_receipt"]),
			]):
		return false
	var prior_beliefs := _make_unobserved_beliefs_from_state(state)
	if prior_beliefs.size() != 3:
		return false
	var expected_observation_receipts: Array[String] = []
	for raw_belief in beliefs:
		var belief: Dictionary = raw_belief
		var selected := selected_questions.has(String(belief["question_id"]))
		if selected:
			if String(belief["status"]) != "observed":
				return false
			expected_observation_receipts.append(String(
				belief["observation_receipt"]
			))
		else:
			var prior := _belief_by_role(prior_beliefs, String(belief["role"]))
			if prior.is_empty() or _canonical_json(prior) != _canonical_json(belief):
				return false
	expected_observation_receipts.sort()
	if _canonical_json(expected_observation_receipts) \
			!= _canonical_json(record["observation_receipts"]):
		return false
	var id_base := record.duplicate(true)
	id_base.erase("record_id")
	id_base.erase("record_receipt")
	var digest := _sha256_hex(_canonical_json(id_base))
	if digest == "" or String(record["record_id"]) \
			!= RESOLUTION_RECORD_ID_PREFIX + digest.substr(0, 16):
		return false
	var receipt_base := record.duplicate(true)
	receipt_base.erase("record_receipt")
	return String(record["record_receipt"]) == _receipt_for(receipt_base)


static func _stale_record_valid(state: Dictionary, commitment: Dictionary,
		record: Dictionary) -> bool:
	var required := ["schema", "terms_revision", "catalog_receipt",
		"evidence_snapshot_receipt", "commitment_record_id",
		"commitment_record_receipt", "original_campaign_state_receipt",
		"current_campaign_state_receipt", "original_covenant_state_receipt",
		"current_covenant_state_receipt", "current_evidence_receipt",
		"stale_reason", "recon_points_refunded", "record_id", "record_receipt"]
	if not _exact_keys(record, required) or record.get("schema") != STALE_RECORD_SCHEMA \
			or record.get("terms_revision") != TERMS_REVISION \
			or record.get("catalog_receipt") != state.get("catalog_receipt") \
			or record.get("evidence_snapshot_receipt") \
			!= state.get("evidence_snapshot_receipt") \
			or record.get("commitment_record_id") != commitment.get("record_id") \
			or record.get("commitment_record_receipt") \
			!= commitment.get("record_receipt") \
			or record.get("original_campaign_state_receipt") \
			!= state.get("campaign_state_receipt") \
			or record.get("original_covenant_state_receipt") \
			!= state.get("covenant_state_receipt") \
			or not _receipt_token_valid(_string_if(
				record.get("current_campaign_state_receipt")
			)) or not _receipt_token_valid(_string_if(
				record.get("current_covenant_state_receipt")
			)) or not _receipt_token_valid(_string_if(
				record.get("current_evidence_receipt")
			)) or _string_if(record.get("stale_reason")) not in [
				"campaign_changed", "obligation_changed", "both_changed"
			] or not _bounded_int(record.get("recon_points_refunded"), 0, 0) \
			or not _short_id_valid(_string_if(
				record.get("record_id")
			), STALE_RECORD_ID_PREFIX) \
			or not _receipt_token_valid(_string_if(record.get("record_receipt"))):
		return false
	var campaign_changed: bool = record.get("current_campaign_state_receipt") \
		!= record.get("original_campaign_state_receipt")
	var covenant_changed: bool = record.get("current_covenant_state_receipt") \
		!= record.get("original_covenant_state_receipt")
	var reason := "both_changed" if campaign_changed and covenant_changed \
		else ("campaign_changed" if campaign_changed else "obligation_changed")
	if not campaign_changed and not covenant_changed \
			or String(record["stale_reason"]) != reason \
			or String(record["current_evidence_receipt"]) != _receipt_for({
				"terms_revision": TERMS_REVISION,
				"catalog_receipt": String(state["catalog_receipt"]),
				"campaign_owner_scope": String(commitment["campaign_owner_scope"]),
				"accepted_campaign_state_receipt": String(
					record["current_campaign_state_receipt"]
				),
				"global_network_scope": String(commitment["global_network_scope"]),
				"accepted_covenant_state_receipt": String(
					record["current_covenant_state_receipt"]
				),
			}):
		return false
	var id_base := record.duplicate(true)
	id_base.erase("record_id")
	id_base.erase("record_receipt")
	var digest := _sha256_hex(_canonical_json(id_base))
	if digest == "" or String(record["record_id"]) \
			!= STALE_RECORD_ID_PREFIX + digest.substr(0, 16):
		return false
	var receipt_base := record.duplicate(true)
	receipt_base.erase("record_receipt")
	return String(record["record_receipt"]) == _receipt_for(receipt_base)


static func _make_unobserved_beliefs_from_state(state: Dictionary) -> Array:
	var beliefs: Array = state.get("beliefs", [])
	var result: Array = []
	for raw_belief in beliefs:
		if not (raw_belief is Dictionary):
			return []
		var belief: Dictionary = (raw_belief as Dictionary).duplicate(true)
		if belief.get("status") == "observed":
			# A resolved state retains enough durable prior width to reverse only the
			# epistemic band; authority validation never treats this as world truth.
			var prior_width := GROUNDED_PRIOR_MAX_BP - GROUNDED_PRIOR_MIN_BP \
				if belief.get("grounding_status") == "grounded" \
				else BROAD_PRIOR_MAX_BP - BROAD_PRIOR_MIN_BP
			belief["minimum_bp"] = GROUNDED_PRIOR_MIN_BP \
				if belief.get("grounding_status") == "grounded" else BROAD_PRIOR_MIN_BP
			belief["maximum_bp"] = GROUNDED_PRIOR_MAX_BP \
				if belief.get("grounding_status") == "grounded" else BROAD_PRIOR_MAX_BP
			belief["width_bp"] = prior_width
			belief["status"] = "unobserved"
			belief["observed_signal"] = ""
			belief["observation_receipt"] = ""
		result.append(belief)
	return result


static func make_recon_anchor(owner_scope: String, owner_checkpoint_receipt: String,
		cycle_key: String, points_before: int) -> Dictionary:
	if not _slug_valid(owner_scope) \
			or not _receipt_token_valid(owner_checkpoint_receipt) \
			or not _receipt_token_valid(cycle_key) \
			or points_before < 0 or points_before > MAX_RECON_POINTS:
		return {}
	var base := {
		"schema": RECON_ANCHOR_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"owner_scope": owner_scope,
		"owner_checkpoint_receipt": owner_checkpoint_receipt,
		"cycle_key": cycle_key,
		"points_before": points_before,
		"commitment_replay_key": _receipt_for([
			owner_scope, owner_checkpoint_receipt,
		]),
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "" or String(base["commitment_replay_key"]) == "":
		return {}
	base["anchor_id"] = ANCHOR_ID_PREFIX + digest.substr(0, 16)
	base["anchor_receipt"] = _receipt_for(base)
	return base if String(base["anchor_receipt"]) != "" else {}


static func validate_recon_anchor(value: Variant, expected_owner_scope: String,
		accepted_owner_checkpoint_receipt: String,
		expected_anchor_receipt: String) -> Array[String]:
	if not (value is Dictionary):
		return ["recon capacity anchor must be a Dictionary"]
	var data: Dictionary = value
	var required := ["schema", "terms_revision", "owner_scope",
		"owner_checkpoint_receipt", "cycle_key", "points_before",
		"commitment_replay_key", "anchor_id", "anchor_receipt"]
	if not _exact_keys(data, required) or data.get("schema") != RECON_ANCHOR_SCHEMA \
			or data.get("terms_revision") != TERMS_REVISION \
			or not _slug_valid(expected_owner_scope) \
			or data.get("owner_scope") != expected_owner_scope \
			or not _receipt_token_valid(accepted_owner_checkpoint_receipt) \
			or data.get("owner_checkpoint_receipt") \
			!= accepted_owner_checkpoint_receipt \
			or not _receipt_token_valid(expected_anchor_receipt) \
			or data.get("anchor_receipt") != expected_anchor_receipt \
			or not _receipt_token_valid(_string_if(data.get("cycle_key"))) \
			or not _bounded_int(data.get("points_before"), 0, MAX_RECON_POINTS) \
			or not _receipt_token_valid(_string_if(
				data.get("commitment_replay_key")
			)) or data.get("commitment_replay_key") != _receipt_for([
			expected_owner_scope, accepted_owner_checkpoint_receipt,
		]) or not _short_id_valid(_string_if(data.get("anchor_id")), ANCHOR_ID_PREFIX):
		return ["recon capacity anchor does not match accepted owner checkpoint"]
	var id_base := data.duplicate(true)
	id_base.erase("anchor_id")
	id_base.erase("anchor_receipt")
	var digest := _sha256_hex(_canonical_json(id_base))
	if digest == "" or String(data["anchor_id"]) \
			!= ANCHOR_ID_PREFIX + digest.substr(0, 16):
		return ["recon capacity anchor id mismatch"]
	var receipt_base := data.duplicate(true)
	receipt_base.erase("anchor_receipt")
	if String(data["anchor_receipt"]) != _receipt_for(receipt_base):
		return ["recon capacity anchor receipt mismatch"]
	return []


static func normalize_recon_anchor(value: Variant, expected_owner_scope: String,
		accepted_owner_checkpoint_receipt: String,
		expected_anchor_receipt: String) -> Dictionary:
	if not (value is Dictionary) or not validate_recon_anchor(
		value, expected_owner_scope, accepted_owner_checkpoint_receipt,
		expected_anchor_receipt
	).is_empty():
		return {}
	var result: Dictionary = (value as Dictionary).duplicate(true)
	result["points_before"] = int(result["points_before"])
	return result


static func make_portfolio_board(campaign_catalog: Dictionary,
		covenant_catalog: Dictionary, catalog: Dictionary, state: Dictionary,
		accepted_state_receipt: String, evidence: Dictionary,
		accepted_evidence_receipt: String, recon_anchor: Dictionary,
		accepted_recon_owner_scope: String,
		accepted_recon_owner_checkpoint_receipt: String,
		expected_recon_anchor_receipt: String) -> Dictionary:
	var normalized_catalog := normalize_catalog(
		campaign_catalog, covenant_catalog, catalog
	)
	if normalized_catalog.is_empty() \
			or not _receipt_token_valid(accepted_evidence_receipt) \
			or not _evidence_self_valid(normalized_catalog, evidence) \
			or String(evidence["evidence_receipt"]) != accepted_evidence_receipt \
			or accepted_recon_owner_scope == String(evidence["campaign_owner_scope"]) \
			or accepted_recon_owner_scope == String(evidence["global_network_scope"]):
		return {}
	var normalized_state := accept_state_checkpoint(
		normalized_catalog, state, accepted_state_receipt
	)
	var anchor := normalize_recon_anchor(
		recon_anchor, accepted_recon_owner_scope,
		accepted_recon_owner_checkpoint_receipt, expected_recon_anchor_receipt
	)
	if normalized_state.is_empty() or anchor.is_empty() \
			or String(normalized_state["evidence_snapshot_receipt"]) \
			!= accepted_evidence_receipt \
			or String(anchor["cycle_key"]) != accepted_evidence_receipt:
		return {}
	var status := "cycle_terminal"
	var options: Array[Dictionary] = []
	if String(normalized_state["phase"]) == "open":
		if int(anchor["points_before"]) < PORTFOLIO_COST:
			status = "insufficient_recon_capacity"
		else:
			status = "portfolios_available"
			for pair in [["duty", "spillover"], ["duty", "fallback"],
					["spillover", "fallback"]]:
				var option := _make_portfolio_option(
					normalized_catalog, normalized_state, pair
				)
				if option.is_empty():
					return {}
				options.append(option)
			options.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
				return String(left["portfolio_id"]) < String(right["portfolio_id"]))
	elif String(normalized_state["phase"]) == "committed":
		status = "already_committed"
	var base := {
		"schema": BOARD_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(normalized_catalog["catalog_id"]),
		"catalog_receipt": String(normalized_catalog["catalog_receipt"]),
		"state_receipt": String(normalized_state["state_receipt"]),
		"accepted_state_receipt": accepted_state_receipt,
		"revision": int(normalized_state["revision"]),
		"evidence_snapshot_receipt": accepted_evidence_receipt,
		"recon_owner_scope": accepted_recon_owner_scope,
		"recon_owner_checkpoint_receipt":
			accepted_recon_owner_checkpoint_receipt,
		"recon_anchor_id": String(anchor["anchor_id"]),
		"recon_anchor_receipt": String(anchor["anchor_receipt"]),
		"recon_replay_key": String(anchor["commitment_replay_key"]),
		"cycle_key": String(anchor["cycle_key"]),
		"points_available": int(anchor["points_before"]),
		"decision_status": status,
		"options": options,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["board_id"] = BOARD_ID_PREFIX + digest.substr(0, 16)
	base["board_receipt"] = _receipt_for(base)
	return base if String(base["board_receipt"]) != "" else {}


static func validate_portfolio_board(campaign_catalog: Dictionary,
		covenant_catalog: Dictionary, catalog: Dictionary, state: Dictionary,
		accepted_state_receipt: String, evidence: Dictionary,
		accepted_evidence_receipt: String, recon_anchor: Dictionary,
		accepted_recon_owner_scope: String,
		accepted_recon_owner_checkpoint_receipt: String,
		expected_recon_anchor_receipt: String, value: Variant) -> Array[String]:
	var expected := make_portfolio_board(
		campaign_catalog, covenant_catalog, catalog, state, accepted_state_receipt,
		evidence, accepted_evidence_receipt, recon_anchor,
		accepted_recon_owner_scope, accepted_recon_owner_checkpoint_receipt,
		expected_recon_anchor_receipt
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["recon portfolio board does not derive from exact accepted anchors"]
	return []


static func normalize_portfolio_board(campaign_catalog: Dictionary,
		covenant_catalog: Dictionary, catalog: Dictionary, state: Dictionary,
		accepted_state_receipt: String, evidence: Dictionary,
		accepted_evidence_receipt: String, recon_anchor: Dictionary,
		accepted_recon_owner_scope: String,
		accepted_recon_owner_checkpoint_receipt: String,
		expected_recon_anchor_receipt: String, value: Variant) -> Dictionary:
	var expected := make_portfolio_board(
		campaign_catalog, covenant_catalog, catalog, state, accepted_state_receipt,
		evidence, accepted_evidence_receipt, recon_anchor,
		accepted_recon_owner_scope, accepted_recon_owner_checkpoint_receipt,
		expected_recon_anchor_receipt
	)
	return expected if not expected.is_empty() and value is Dictionary \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func _make_portfolio_option(catalog: Dictionary, state: Dictionary,
		role_pair: Array) -> Dictionary:
	if role_pair.size() != REQUIRED_PROBES:
		return {}
	var probes: Array[Dictionary] = []
	var selected := {}
	for raw_role in role_pair:
		var role := String(raw_role)
		if role not in ROLES or selected.has(role):
			return {}
		selected[role] = true
		var belief := _belief_by_role(state["beliefs"], role)
		var probe := _make_probe(catalog, belief)
		if belief.is_empty() or probe.is_empty():
			return {}
		probes.append(probe)
	probes.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["probe_id"]) < String(right["probe_id"]))
	var canonical_roles: Array[String] = []
	var reduction_vector: Array[Dictionary] = []
	for role in ROLES:
		if selected.has(role):
			canonical_roles.append(role)
		var belief := _belief_by_role(state["beliefs"], role)
		if belief.is_empty():
			return {}
		reduction_vector.append({
			"role": role,
			"reduction_bp": int(belief["width_bp"]) - POSTERIOR_WIDTH_BP \
				if selected.has(role) else 0,
		})
	var authority := {
		"terms_revision": TERMS_REVISION,
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"state_receipt": String(state["state_receipt"]),
		"evidence_snapshot_receipt": String(state["evidence_snapshot_receipt"]),
		"role_pair": canonical_roles,
		"probes": probes,
		"point_cost": PORTFOLIO_COST,
		"reduction_vector": reduction_vector,
	}
	var digest := _sha256_hex(_canonical_json(authority))
	if digest == "":
		return {}
	var option := authority.duplicate(true)
	option["portfolio_id"] = PORTFOLIO_ID_PREFIX + digest.substr(0, 16)
	option["option_receipt"] = _receipt_for(option)
	return option if String(option["option_receipt"]) != "" else {}


static func _rebuild_commit_board(catalog: Dictionary, open_state: Dictionary,
		anchor: Dictionary) -> Dictionary:
	if open_state.is_empty() or anchor.is_empty() \
			or String(open_state.get("phase", "")) != "open" \
			or int(anchor.get("points_before", -1)) < PORTFOLIO_COST \
			or anchor.get("cycle_key") != open_state.get("evidence_snapshot_receipt"):
		return {}
	var options: Array[Dictionary] = []
	for pair in [["duty", "spillover"], ["duty", "fallback"],
			["spillover", "fallback"]]:
		var option := _make_portfolio_option(catalog, open_state, pair)
		if option.is_empty():
			return {}
		options.append(option)
	options.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["portfolio_id"]) < String(right["portfolio_id"]))
	var base := {
		"schema": BOARD_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(catalog["catalog_id"]),
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"state_receipt": String(open_state["state_receipt"]),
		"accepted_state_receipt": String(open_state["state_receipt"]),
		"revision": 0,
		"evidence_snapshot_receipt": String(open_state["evidence_snapshot_receipt"]),
		"recon_owner_scope": String(anchor["owner_scope"]),
		"recon_owner_checkpoint_receipt": String(anchor["owner_checkpoint_receipt"]),
		"recon_anchor_id": String(anchor["anchor_id"]),
		"recon_anchor_receipt": String(anchor["anchor_receipt"]),
		"recon_replay_key": String(anchor["commitment_replay_key"]),
		"cycle_key": String(anchor["cycle_key"]),
		"points_available": int(anchor["points_before"]),
		"decision_status": "portfolios_available",
		"options": options,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["board_id"] = BOARD_ID_PREFIX + digest.substr(0, 16)
	base["board_receipt"] = _receipt_for(base)
	return base if String(base["board_receipt"]) != "" else {}


static func _make_probe(catalog: Dictionary, belief: Dictionary) -> Dictionary:
	if belief.is_empty() or belief.get("status") != "unobserved":
		return {}
	var base := {
		"terms_revision": TERMS_REVISION,
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"question_id": String(belief["question_id"]),
		"question_receipt": String(belief["question_receipt"]),
		"role": String(belief["role"]),
		"window_id": String(belief["window_id"]),
		"region_id": String(belief["region_id"]),
		"prior_width_bp": int(belief["width_bp"]),
		"posterior_width_bp": POSTERIOR_WIDTH_BP,
		"reduction_bp": int(belief["width_bp"]) - POSTERIOR_WIDTH_BP,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["probe_id"] = PROBE_ID_PREFIX + digest.substr(0, 16)
	base["probe_receipt"] = _receipt_for(base)
	return base if String(base["probe_receipt"]) != "" \
		and _probe_valid(catalog, base) else {}


static func make_portfolio_choice(catalog: Dictionary, board: Dictionary,
		portfolio_id: String) -> Dictionary:
	if not _catalog_self_valid(catalog) or not _board_self_valid(catalog, board) \
			or not _short_id_valid(portfolio_id, PORTFOLIO_ID_PREFIX) \
			or String(board["decision_status"]) != "portfolios_available":
		return {}
	var option := _option_by_id(board, portfolio_id)
	if option.is_empty():
		return {}
	var base := {
		"schema": CHOICE_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"board_id": String(board["board_id"]),
		"board_receipt": String(board["board_receipt"]),
		"state_receipt": String(board["state_receipt"]),
		"evidence_snapshot_receipt": String(board["evidence_snapshot_receipt"]),
		"portfolio_id": portfolio_id,
		"option_receipt": String(option["option_receipt"]),
		"selected_roles": option["role_pair"].duplicate(),
		"selected_probe_ids": _probe_ids(option["probes"]),
		"point_cost": int(option["point_cost"]),
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["choice_id"] = CHOICE_ID_PREFIX + digest.substr(0, 16)
	base["choice_receipt"] = _receipt_for(base)
	return base if String(base["choice_receipt"]) != "" else {}


static func make_choice(catalog: Dictionary, board: Dictionary,
		portfolio_id: String) -> Dictionary:
	return make_portfolio_choice(catalog, board, portfolio_id)


static func validate_portfolio_choice(catalog: Dictionary, board: Dictionary,
		value: Variant) -> Array[String]:
	if not (value is Dictionary):
		return ["recon portfolio choice must be a Dictionary"]
	var expected := make_portfolio_choice(
		catalog, board, _string_if((value as Dictionary).get("portfolio_id"))
	)
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(value):
		return ["recon portfolio choice does not match an exact board option"]
	return []


static func normalize_portfolio_choice(catalog: Dictionary, board: Dictionary,
		value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var expected := make_portfolio_choice(
		catalog, board, _string_if((value as Dictionary).get("portfolio_id"))
	)
	return expected if not expected.is_empty() \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func _board_self_valid(catalog: Dictionary, board: Dictionary) -> bool:
	var required := ["schema", "terms_revision", "catalog_id", "catalog_receipt",
		"state_receipt", "accepted_state_receipt", "revision",
		"evidence_snapshot_receipt", "recon_owner_scope",
		"recon_owner_checkpoint_receipt", "recon_anchor_id",
		"recon_anchor_receipt", "recon_replay_key", "cycle_key",
		"points_available", "decision_status", "options", "board_id",
		"board_receipt"]
	if not _exact_keys(board, required) or board.get("schema") != BOARD_SCHEMA \
			or board.get("terms_revision") != TERMS_REVISION \
			or board.get("catalog_id") != catalog.get("catalog_id") \
			or board.get("catalog_receipt") != catalog.get("catalog_receipt") \
			or not _receipt_token_valid(_string_if(board.get("state_receipt"))) \
			or board.get("accepted_state_receipt") != board.get("state_receipt") \
			or not _bounded_int(board.get("revision"), 0, MAX_STATE_REVISION) \
			or not _receipt_token_valid(_string_if(
				board.get("evidence_snapshot_receipt")
			)) or not _slug_valid(_string_if(board.get("recon_owner_scope"))) \
			or not _receipt_token_valid(_string_if(
				board.get("recon_owner_checkpoint_receipt")
			)) or not _short_id_valid(_string_if(
				board.get("recon_anchor_id")
			), ANCHOR_ID_PREFIX) or not _receipt_token_valid(_string_if(
				board.get("recon_anchor_receipt")
			)) or not _receipt_token_valid(_string_if(board.get("recon_replay_key"))) \
			or not _receipt_token_valid(_string_if(board.get("cycle_key"))) \
			or board.get("cycle_key") != board.get("evidence_snapshot_receipt") \
			or not _bounded_int(board.get("points_available"), 0, MAX_RECON_POINTS) \
			or _string_if(board.get("decision_status")) not in [
				"already_committed", "cycle_terminal", "insufficient_recon_capacity",
				"portfolios_available"
			] or not (board.get("options") is Array) \
			or not _short_id_valid(_string_if(board.get("board_id")), BOARD_ID_PREFIX) \
			or not _receipt_token_valid(_string_if(board.get("board_receipt"))):
		return false
	var options: Array = board["options"]
	var has_options := String(board["decision_status"]) == "portfolios_available"
	if options.size() != (3 if has_options else 0):
		return false
	var previous := ""
	for raw_option in options:
		if not (raw_option is Dictionary) \
				or not _portfolio_option_valid(catalog, board, raw_option as Dictionary):
			return false
		var option_id := String((raw_option as Dictionary)["portfolio_id"])
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


static func _portfolio_option_valid(catalog: Dictionary, board: Dictionary,
		option: Dictionary) -> bool:
	var required := ["terms_revision", "catalog_receipt", "state_receipt",
		"evidence_snapshot_receipt", "role_pair", "probes", "point_cost",
		"reduction_vector", "portfolio_id", "option_receipt"]
	if not _exact_keys(option, required) or option.get("terms_revision") \
			!= TERMS_REVISION or option.get("catalog_receipt") \
			!= catalog.get("catalog_receipt") or option.get("state_receipt") \
			!= board.get("state_receipt") or option.get("evidence_snapshot_receipt") \
			!= board.get("evidence_snapshot_receipt") \
			or not (option.get("role_pair") is Array) \
			or not (option.get("probes") is Array) \
			or not (option.get("reduction_vector") is Array) \
			or not _bounded_int(option.get("point_cost"), 2, 2) \
			or not _short_id_valid(_string_if(
				option.get("portfolio_id")
			), PORTFOLIO_ID_PREFIX) or not _receipt_token_valid(_string_if(
				option.get("option_receipt")
			)):
		return false
	var roles: Array = option["role_pair"]
	var probes: Array = option["probes"]
	var reductions: Array = option["reduction_vector"]
	if roles.size() != 2 or probes.size() != 2 or reductions.size() != 3:
		return false
	var seen_roles := {}
	var previous_probe := ""
	for raw_probe in probes:
		if not (raw_probe is Dictionary) \
				or not _probe_valid(catalog, raw_probe as Dictionary):
			return false
		var probe: Dictionary = raw_probe
		if String(probe["probe_id"]) <= previous_probe \
				or seen_roles.has(String(probe["role"])):
			return false
		previous_probe = String(probe["probe_id"])
		seen_roles[String(probe["role"])] = true
	var expected_roles: Array[String] = []
	for index in ROLES.size():
		var role: String = ROLES[index]
		if seen_roles.has(role):
			expected_roles.append(role)
		if not (reductions[index] is Dictionary) \
				or not _exact_keys(reductions[index], ["role", "reduction_bp"]) \
				or (reductions[index] as Dictionary).get("role") != role \
				or not _bounded_int((reductions[index] as Dictionary).get(
					"reduction_bp"
				), 0, 4000):
			return false
	var expected := _make_portfolio_option(catalog, {
		"beliefs": _beliefs_from_option(catalog, option),
		"state_receipt": board["state_receipt"],
		"evidence_snapshot_receipt": board["evidence_snapshot_receipt"],
	}, expected_roles)
	return not expected.is_empty() \
		and _canonical_json(expected) == _canonical_json(option)


static func _beliefs_from_option(catalog: Dictionary, option: Dictionary) -> Array:
	var probe_by_role := {}
	for raw_probe in option.get("probes", []):
		if raw_probe is Dictionary:
			probe_by_role[String((raw_probe as Dictionary).get("role", ""))] = raw_probe
	var beliefs: Array[Dictionary] = []
	for role in ROLES:
		var probe: Dictionary = probe_by_role.get(role, {})
		if probe.is_empty():
			# The unselected role does not appear in the option. Its exact width is
			# encoded by the zero reduction entry and catalog identity is enough for
			# structural board validation; authority calls recompute the whole board.
			var question := _question_for_unselected_role(catalog, option)
			if question.is_empty():
				return []
			beliefs.append(_synthetic_unobserved_belief(question, role, 6000))
		else:
			beliefs.append(_synthetic_unobserved_belief(
				_question_by_id(catalog, String(probe["question_id"])), role,
				int(probe["prior_width_bp"])
			))
	beliefs.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["question_id"]) < String(right["question_id"]))
	return beliefs


static func _question_for_unselected_role(catalog: Dictionary,
		option: Dictionary) -> Dictionary:
	var used := {}
	for raw_probe in option.get("probes", []):
		if raw_probe is Dictionary:
			used[String((raw_probe as Dictionary).get("question_id", ""))] = true
	for raw_question in catalog.get("questions", []):
		if raw_question is Dictionary \
				and not used.has(String((raw_question as Dictionary)["question_id"])):
			return (raw_question as Dictionary).duplicate(true)
	return {}


static func _synthetic_unobserved_belief(question: Dictionary, role: String,
		width: int) -> Dictionary:
	var grounded := width == 4000
	return {
		"question_id": String(question["question_id"]),
		"question_receipt": String(question["question_receipt"]),
		"window_id": String(question["window_id"]),
		"region_id": String(question["region_id"]),
		"role": role,
		"minimum_bp": 3000 if grounded else 2000,
		"maximum_bp": 7000 if grounded else 8000,
		"width_bp": width,
		"status": "unobserved",
		"grounding_status": "grounded" if grounded else "external_only",
		"grounding_evidence_receipts": [],
		"observed_signal": "",
		"observation_receipt": "",
	}


static func _option_by_id(board: Dictionary, portfolio_id: String) -> Dictionary:
	for raw_option in board.get("options", []):
		if raw_option is Dictionary and String((raw_option as Dictionary).get(
				"portfolio_id", "")) == portfolio_id:
			return (raw_option as Dictionary).duplicate(true)
	return {}


static func _belief_by_role(beliefs: Array, role: String) -> Dictionary:
	for raw_belief in beliefs:
		if raw_belief is Dictionary and String((raw_belief as Dictionary).get(
				"role", "")) == role:
			return (raw_belief as Dictionary).duplicate(true)
	return {}


static func _probe_ids(probes: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_probe in probes:
		if raw_probe is Dictionary:
			result.append(String((raw_probe as Dictionary).get("probe_id", "")))
	result.sort()
	return result


static func commit_portfolio(campaign_catalog: Dictionary,
		covenant_catalog: Dictionary, catalog: Dictionary,
		before_state: Dictionary, accepted_before_state_receipt: String,
		evidence: Dictionary, accepted_evidence_receipt: String,
		recon_anchor: Dictionary, accepted_recon_owner_scope: String,
		accepted_recon_owner_checkpoint_receipt: String,
		expected_recon_anchor_receipt: String, board: Dictionary,
		choice: Dictionary) -> Dictionary:
	var normalized_catalog := normalize_catalog(
		campaign_catalog, covenant_catalog, catalog
	)
	if normalized_catalog.is_empty():
		return {}
	var normalized_state := accept_state_checkpoint(
		normalized_catalog, before_state, accepted_before_state_receipt
	)
	if normalized_state.is_empty() or String(normalized_state["phase"]) != "open":
		return {}
	var expected_board := make_portfolio_board(
		campaign_catalog, covenant_catalog, normalized_catalog, normalized_state,
		accepted_before_state_receipt, evidence, accepted_evidence_receipt,
		recon_anchor, accepted_recon_owner_scope,
		accepted_recon_owner_checkpoint_receipt, expected_recon_anchor_receipt
	)
	if expected_board.is_empty() or _canonical_json(expected_board) \
			!= _canonical_json(board) or String(expected_board["decision_status"]) \
			!= "portfolios_available":
		return {}
	var normalized_choice := normalize_portfolio_choice(
		normalized_catalog, expected_board, choice
	)
	var anchor := normalize_recon_anchor(
		recon_anchor, accepted_recon_owner_scope,
		accepted_recon_owner_checkpoint_receipt, expected_recon_anchor_receipt
	)
	var normalized_evidence: Dictionary = evidence.duplicate(true) \
		if _evidence_self_valid(normalized_catalog, evidence) \
		and String(evidence.get("evidence_receipt", "")) \
		== accepted_evidence_receipt else {}
	if normalized_choice.is_empty() or anchor.is_empty() \
			or normalized_evidence.is_empty() \
			or String(anchor["commitment_replay_key"]) \
			in normalized_state["consumed_recon_keys"]:
		return {}
	var option := _option_by_id(
		expected_board, String(normalized_choice["portfolio_id"])
	)
	if option.is_empty():
		return {}
	var record := _make_commit_record(
		normalized_catalog, normalized_state, normalized_evidence, option,
		normalized_choice, anchor
	)
	if record.is_empty():
		return {}
	var after_state := _make_state(
		normalized_catalog, normalized_evidence, 1, "committed", "",
		normalized_state["beliefs"], record, {}, {},
		[String(record["recon_replay_key"])], [],
		String(normalized_state["state_receipt"]), String(record["record_receipt"])
	)
	if after_state.is_empty() \
			or not validate_state(normalized_catalog, after_state).is_empty():
		return {}
	var belief_delta := _make_belief_state_delta(
		normalized_state, after_state, "commit", String(record["portfolio_id"])
	)
	var capacity_delta := _make_capacity_delta(anchor)
	if belief_delta.is_empty() or capacity_delta.is_empty():
		return {}
	var base := {
		"schema": COMMIT_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(normalized_catalog["catalog_id"]),
		"catalog_receipt": String(normalized_catalog["catalog_receipt"]),
		"owner_order": ["belief", "recon_capacity"],
		"accepted_before_state_receipt": accepted_before_state_receipt,
		"accepted_evidence_receipt": accepted_evidence_receipt,
		"accepted_recon_owner_scope": accepted_recon_owner_scope,
		"accepted_recon_owner_checkpoint_receipt":
			accepted_recon_owner_checkpoint_receipt,
		"expected_recon_anchor_receipt": expected_recon_anchor_receipt,
		"board_id": String(expected_board["board_id"]),
		"board_receipt": String(expected_board["board_receipt"]),
		"choice_id": String(normalized_choice["choice_id"]),
		"choice_receipt": String(normalized_choice["choice_receipt"]),
		"belief_delta": belief_delta,
		"recon_capacity_delta": capacity_delta,
		"commitment_record": record,
		"after_state": after_state,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["proposal_id"] = COMMIT_ID_PREFIX + digest.substr(0, 16)
	base["proposal_receipt"] = _receipt_for(base)
	return base if String(base["proposal_receipt"]) != "" else {}


static func validate_commit_proposal(campaign_catalog: Dictionary,
		covenant_catalog: Dictionary, catalog: Dictionary,
		before_state: Dictionary, accepted_before_state_receipt: String,
		evidence: Dictionary, accepted_evidence_receipt: String,
		recon_anchor: Dictionary, accepted_recon_owner_scope: String,
		accepted_recon_owner_checkpoint_receipt: String,
		expected_recon_anchor_receipt: String, board: Dictionary,
		choice: Dictionary, value: Variant) -> Array[String]:
	var expected := commit_portfolio(
		campaign_catalog, covenant_catalog, catalog, before_state,
		accepted_before_state_receipt, evidence, accepted_evidence_receipt,
		recon_anchor, accepted_recon_owner_scope,
		accepted_recon_owner_checkpoint_receipt, expected_recon_anchor_receipt,
		board, choice
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["recon commitment does not derive from exact state and owner anchors"]
	return []


static func normalize_commit_proposal(campaign_catalog: Dictionary,
		covenant_catalog: Dictionary, catalog: Dictionary,
		before_state: Dictionary, accepted_before_state_receipt: String,
		evidence: Dictionary, accepted_evidence_receipt: String,
		recon_anchor: Dictionary, accepted_recon_owner_scope: String,
		accepted_recon_owner_checkpoint_receipt: String,
		expected_recon_anchor_receipt: String, board: Dictionary,
		choice: Dictionary, value: Variant) -> Dictionary:
	var expected := commit_portfolio(
		campaign_catalog, covenant_catalog, catalog, before_state,
		accepted_before_state_receipt, evidence, accepted_evidence_receipt,
		recon_anchor, accepted_recon_owner_scope,
		accepted_recon_owner_checkpoint_receipt, expected_recon_anchor_receipt,
		board, choice
	)
	return expected if not expected.is_empty() and value is Dictionary \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func _make_commit_record(catalog: Dictionary, state: Dictionary,
		evidence: Dictionary, option: Dictionary, choice: Dictionary,
		anchor: Dictionary) -> Dictionary:
	var base := {
		"schema": COMMIT_RECORD_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"evidence_snapshot_receipt": String(evidence["evidence_receipt"]),
		"campaign_state_receipt": String(evidence["accepted_campaign_state_receipt"]),
		"covenant_state_receipt": String(evidence["accepted_covenant_state_receipt"]),
		"campaign_owner_scope": String(evidence["campaign_owner_scope"]),
		"global_network_scope": String(evidence["global_network_scope"]),
		"covenant_record_id": String(evidence["covenant_record_id"]),
		"covenant_record_receipt": String(evidence["covenant_record_receipt"]),
		"effective_due_epoch": int(evidence["effective_due_epoch"]),
		"portfolio_id": String(option["portfolio_id"]),
		"option_receipt": String(option["option_receipt"]),
		"choice_id": String(choice["choice_id"]),
		"choice_receipt": String(choice["choice_receipt"]),
		"selected_roles": option["role_pair"].duplicate(),
		"selected_probes": option["probes"].duplicate(true),
		"point_cost": PORTFOLIO_COST,
		"recon_owner_scope": String(anchor["owner_scope"]),
		"recon_owner_checkpoint_receipt": String(
			anchor["owner_checkpoint_receipt"]
		),
		"recon_anchor_id": String(anchor["anchor_id"]),
		"recon_anchor_receipt": String(anchor["anchor_receipt"]),
		"recon_replay_key": String(anchor["commitment_replay_key"]),
		"points_before": int(anchor["points_before"]),
		"points_applied": -PORTFOLIO_COST,
		"points_after": int(anchor["points_before"]) - PORTFOLIO_COST,
		"before_beliefs_receipt": _receipt_for(state["beliefs"]),
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "" or String(base["before_beliefs_receipt"]) == "":
		return {}
	base["record_id"] = COMMIT_RECORD_ID_PREFIX + digest.substr(0, 16)
	base["record_receipt"] = _receipt_for(base)
	return base if String(base["record_receipt"]) != "" else {}


static func _make_capacity_delta(anchor: Dictionary) -> Dictionary:
	var base := {
		"owner": "recon_capacity",
		"owner_scope": String(anchor["owner_scope"]),
		"owner_checkpoint_receipt": String(anchor["owner_checkpoint_receipt"]),
		"anchor_id": String(anchor["anchor_id"]),
		"anchor_receipt": String(anchor["anchor_receipt"]),
		"commitment_replay_key": String(anchor["commitment_replay_key"]),
		"points_before": int(anchor["points_before"]),
		"points_requested": -PORTFOLIO_COST,
		"points_applied": -PORTFOLIO_COST,
		"points_after": int(anchor["points_before"]) - PORTFOLIO_COST,
	}
	base["delta_receipt"] = _receipt_for(base)
	return base if String(base["delta_receipt"]) != "" else {}


static func _make_belief_state_delta(before: Dictionary, after: Dictionary,
		action: String, subject_id: String) -> Dictionary:
	if action not in ["commit", "resolve", "stale"] \
			or not _short_id_valid(subject_id, PORTFOLIO_ID_PREFIX):
		return {}
	var base := {
		"owner": "belief",
		"action": action,
		"subject_id": subject_id,
		"before_revision": int(before["revision"]),
		"after_revision": int(after["revision"]),
		"before_state_receipt": String(before["state_receipt"]),
		"after_state_receipt": String(after["state_receipt"]),
	}
	base["delta_receipt"] = _receipt_for(base)
	return base if int(base["after_revision"]) == int(base["before_revision"]) + 1 \
		and String(base["delta_receipt"]) != "" else {}


static func make_observation_bundle(catalog: Dictionary,
		committed_state: Dictionary, accepted_state_receipt: String,
		observation_owner_scope: String,
		observation_owner_checkpoint_receipt: String,
		observations: Array) -> Dictionary:
	if not _catalog_self_valid(catalog):
		return {}
	var state := accept_state_checkpoint(
		catalog, committed_state, accepted_state_receipt
	)
	if state.is_empty() or String(state["phase"]) != "committed" \
			or not _slug_valid(observation_owner_scope) \
			or not _receipt_token_valid(observation_owner_checkpoint_receipt):
		return {}
	var commitment: Dictionary = state["commitment_record"]
	if observation_owner_scope != String(commitment["recon_owner_scope"]) \
			or observation_owner_checkpoint_receipt \
			== String(commitment["recon_owner_checkpoint_receipt"]) \
			or observations.size() != REQUIRED_PROBES:
		return {}
	var selected_by_id := {}
	for raw_probe in commitment["selected_probes"]:
		var probe: Dictionary = raw_probe
		selected_by_id[String(probe["probe_id"])] = probe
	var normalized_observations: Array[Dictionary] = []
	var seen_probes := {}
	var seen_sources := {}
	for raw_observation in observations:
		if not (raw_observation is Dictionary):
			return {}
		var input: Dictionary = raw_observation
		if not _exact_keys(input, ["probe_id", "signal", "source_receipt"]):
			return {}
		var probe_id := _string_if(input.get("probe_id"))
		var observed_signal := _string_if(input.get("signal"))
		var source_receipt := _string_if(input.get("source_receipt"))
		var probe: Dictionary = selected_by_id.get(probe_id, {})
		if probe.is_empty() or observed_signal not in SIGNALS \
				or not _receipt_token_valid(source_receipt) \
				or seen_probes.has(probe_id) or seen_sources.has(source_receipt):
			return {}
		var observation := {
			"probe_id": probe_id,
			"probe_receipt": String(probe["probe_receipt"]),
			"question_id": String(probe["question_id"]),
			"question_receipt": String(probe["question_receipt"]),
			"role": String(probe["role"]),
			"window_id": String(probe["window_id"]),
			"region_id": String(probe["region_id"]),
			"signal": observed_signal,
			"source_receipt": source_receipt,
		}
		observation["observation_receipt"] = _receipt_for(observation)
		if String(observation["observation_receipt"]) == "":
			return {}
		normalized_observations.append(observation)
		seen_probes[probe_id] = true
		seen_sources[source_receipt] = true
	normalized_observations.sort_custom(func(left: Dictionary,
			right: Dictionary) -> bool:
		return String(left["probe_id"]) < String(right["probe_id"]))
	var replay_key := _receipt_for([
		observation_owner_scope, observation_owner_checkpoint_receipt,
		String(commitment["record_receipt"]),
	])
	if replay_key == "":
		return {}
	var base := {
		"schema": OBSERVATION_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(catalog["catalog_id"]),
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"state_receipt": String(state["state_receipt"]),
		"commitment_record_id": String(commitment["record_id"]),
		"commitment_record_receipt": String(commitment["record_receipt"]),
		"observation_owner_scope": observation_owner_scope,
		"observation_owner_checkpoint_receipt":
			observation_owner_checkpoint_receipt,
		"observation_replay_key": replay_key,
		"observations": normalized_observations,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["bundle_id"] = OBSERVATION_ID_PREFIX + digest.substr(0, 16)
	base["bundle_receipt"] = _receipt_for(base)
	return base if String(base["bundle_receipt"]) != "" else {}


static func validate_observation_bundle(catalog: Dictionary,
		committed_state: Dictionary, accepted_state_receipt: String,
		observation_owner_scope: String,
		accepted_observation_owner_checkpoint_receipt: String,
		expected_bundle_receipt: String, value: Variant) -> Array[String]:
	if not (value is Dictionary) or not _receipt_token_valid(expected_bundle_receipt):
		return ["observation bundle requires an externally accepted receipt"]
	var data: Dictionary = value
	if not (data.get("observations") is Array):
		return ["observation bundle observations must be an Array"]
	var sparse: Array[Dictionary] = []
	for raw_observation in data["observations"]:
		if not (raw_observation is Dictionary):
			return ["observation bundle item must be a Dictionary"]
		var observation: Dictionary = raw_observation
		sparse.append({
			"probe_id": _string_if(observation.get("probe_id")),
			"signal": _string_if(observation.get("signal")),
			"source_receipt": _string_if(observation.get("source_receipt")),
		})
	var expected := make_observation_bundle(
		catalog, committed_state, accepted_state_receipt, observation_owner_scope,
		accepted_observation_owner_checkpoint_receipt, sparse
	)
	if expected.is_empty() or String(expected["bundle_receipt"]) \
			!= expected_bundle_receipt or _canonical_json(expected) \
			!= _canonical_json(value):
		return ["observation bundle does not match selected probes and owner anchor"]
	return []


static func normalize_observation_bundle(catalog: Dictionary,
		committed_state: Dictionary, accepted_state_receipt: String,
		observation_owner_scope: String,
		accepted_observation_owner_checkpoint_receipt: String,
		expected_bundle_receipt: String, value: Variant) -> Dictionary:
	if not (value is Dictionary) or not validate_observation_bundle(
		catalog, committed_state, accepted_state_receipt, observation_owner_scope,
		accepted_observation_owner_checkpoint_receipt, expected_bundle_receipt,
		value
	).is_empty():
		return {}
	return (value as Dictionary).duplicate(true)


static func resolve_portfolio(campaign_catalog: Dictionary,
		covenant_catalog: Dictionary, catalog: Dictionary,
		before_state: Dictionary, accepted_before_state_receipt: String,
		current_campaign_state: Dictionary,
		accepted_current_campaign_state_receipt: String,
		campaign_owner_scope: String, current_covenant_state: Dictionary,
		accepted_current_covenant_state_receipt: String,
		global_network_scope: String, observation_bundle: Dictionary,
		observation_owner_scope: String,
		accepted_observation_owner_checkpoint_receipt: String,
		expected_bundle_receipt: String) -> Dictionary:
	var normalized_catalog := normalize_catalog(
		campaign_catalog, covenant_catalog, catalog
	)
	if normalized_catalog.is_empty():
		return {}
	var state := accept_state_checkpoint(
		normalized_catalog, before_state, accepted_before_state_receipt
	)
	if state.is_empty() or String(state["phase"]) != "committed":
		return {}
	var snapshot := _normalize_current_owner_snapshots(
		campaign_catalog, current_campaign_state,
		accepted_current_campaign_state_receipt, campaign_owner_scope,
		covenant_catalog, current_covenant_state,
		accepted_current_covenant_state_receipt, global_network_scope,
		state
	)
	if snapshot.is_empty() or bool(snapshot["changed"]):
		return {}
	var bundle := normalize_observation_bundle(
		normalized_catalog, state, accepted_before_state_receipt,
		observation_owner_scope, accepted_observation_owner_checkpoint_receipt,
		expected_bundle_receipt, observation_bundle
	)
	var commitment: Dictionary = state["commitment_record"]
	if bundle.is_empty() or String(bundle["observation_replay_key"]) \
			in state["consumed_observation_keys"]:
		return {}
	var beliefs := _apply_observations(
		state["beliefs"], commitment, bundle["observations"]
	)
	if beliefs.size() != 3:
		return {}
	var record := _make_resolution_record(
		normalized_catalog, state, commitment, bundle, beliefs
	)
	if record.is_empty():
		return {}
	var after_state := _make_state(
		normalized_catalog, _state_anchor_evidence(state), 2, "terminal",
		"resolved", beliefs, commitment, record, {},
		state["consumed_recon_keys"], [String(bundle["observation_replay_key"])],
		String(state["state_receipt"]), String(record["record_receipt"])
	)
	if after_state.is_empty() \
			or not validate_state(normalized_catalog, after_state).is_empty():
		return {}
	var belief_delta := _make_belief_state_delta(
		state, after_state, "resolve", String(commitment["portfolio_id"])
	)
	if belief_delta.is_empty():
		return {}
	var base := {
		"schema": RESOLUTION_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(normalized_catalog["catalog_id"]),
		"catalog_receipt": String(normalized_catalog["catalog_receipt"]),
		"owner_order": ["belief"],
		"accepted_before_state_receipt": accepted_before_state_receipt,
		"accepted_current_campaign_state_receipt":
			accepted_current_campaign_state_receipt,
		"accepted_current_covenant_state_receipt":
			accepted_current_covenant_state_receipt,
		"campaign_owner_scope": campaign_owner_scope,
		"global_network_scope": global_network_scope,
		"observation_bundle_id": String(bundle["bundle_id"]),
		"observation_bundle_receipt": String(bundle["bundle_receipt"]),
		"belief_delta": belief_delta,
		"resolution_record": record,
		"after_state": after_state,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["proposal_id"] = RESOLUTION_ID_PREFIX + digest.substr(0, 16)
	base["proposal_receipt"] = _receipt_for(base)
	return base if String(base["proposal_receipt"]) != "" else {}


static func validate_resolution_proposal(campaign_catalog: Dictionary,
		covenant_catalog: Dictionary, catalog: Dictionary,
		before_state: Dictionary, accepted_before_state_receipt: String,
		current_campaign_state: Dictionary,
		accepted_current_campaign_state_receipt: String,
		campaign_owner_scope: String, current_covenant_state: Dictionary,
		accepted_current_covenant_state_receipt: String,
		global_network_scope: String, observation_bundle: Dictionary,
		observation_owner_scope: String,
		accepted_observation_owner_checkpoint_receipt: String,
		expected_bundle_receipt: String, value: Variant) -> Array[String]:
	var expected := resolve_portfolio(
		campaign_catalog, covenant_catalog, catalog, before_state,
		accepted_before_state_receipt, current_campaign_state,
		accepted_current_campaign_state_receipt, campaign_owner_scope,
		current_covenant_state, accepted_current_covenant_state_receipt,
		global_network_scope, observation_bundle, observation_owner_scope,
		accepted_observation_owner_checkpoint_receipt, expected_bundle_receipt
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["recon resolution does not derive from exact unchanged owner snapshots"]
	return []


static func normalize_resolution_proposal(campaign_catalog: Dictionary,
		covenant_catalog: Dictionary, catalog: Dictionary,
		before_state: Dictionary, accepted_before_state_receipt: String,
		current_campaign_state: Dictionary,
		accepted_current_campaign_state_receipt: String,
		campaign_owner_scope: String, current_covenant_state: Dictionary,
		accepted_current_covenant_state_receipt: String,
		global_network_scope: String, observation_bundle: Dictionary,
		observation_owner_scope: String,
		accepted_observation_owner_checkpoint_receipt: String,
		expected_bundle_receipt: String, value: Variant) -> Dictionary:
	var expected := resolve_portfolio(
		campaign_catalog, covenant_catalog, catalog, before_state,
		accepted_before_state_receipt, current_campaign_state,
		accepted_current_campaign_state_receipt, campaign_owner_scope,
		current_covenant_state, accepted_current_covenant_state_receipt,
		global_network_scope, observation_bundle, observation_owner_scope,
		accepted_observation_owner_checkpoint_receipt, expected_bundle_receipt
	)
	return expected if not expected.is_empty() and value is Dictionary \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func close_stale(campaign_catalog: Dictionary,
		covenant_catalog: Dictionary, catalog: Dictionary,
		before_state: Dictionary, accepted_before_state_receipt: String,
		current_campaign_state: Dictionary,
		accepted_current_campaign_state_receipt: String,
		campaign_owner_scope: String, current_covenant_state: Dictionary,
		accepted_current_covenant_state_receipt: String,
		global_network_scope: String) -> Dictionary:
	var normalized_catalog := normalize_catalog(
		campaign_catalog, covenant_catalog, catalog
	)
	if normalized_catalog.is_empty():
		return {}
	var state := accept_state_checkpoint(
		normalized_catalog, before_state, accepted_before_state_receipt
	)
	if state.is_empty() or String(state["phase"]) != "committed":
		return {}
	var snapshot := _normalize_current_owner_snapshots(
		campaign_catalog, current_campaign_state,
		accepted_current_campaign_state_receipt, campaign_owner_scope,
		covenant_catalog, current_covenant_state,
		accepted_current_covenant_state_receipt, global_network_scope, state
	)
	if snapshot.is_empty() or not bool(snapshot["changed"]):
		return {}
	var commitment: Dictionary = state["commitment_record"]
	var current_evidence_receipt := _receipt_for({
		"terms_revision": TERMS_REVISION,
		"catalog_receipt": String(normalized_catalog["catalog_receipt"]),
		"campaign_owner_scope": campaign_owner_scope,
		"accepted_campaign_state_receipt":
			accepted_current_campaign_state_receipt,
		"global_network_scope": global_network_scope,
		"accepted_covenant_state_receipt":
			accepted_current_covenant_state_receipt,
	})
	if current_evidence_receipt == "":
		return {}
	var record := _make_stale_record(
		normalized_catalog, state, commitment,
		accepted_current_campaign_state_receipt,
		accepted_current_covenant_state_receipt, current_evidence_receipt
	)
	if record.is_empty():
		return {}
	var after_state := _make_state(
		normalized_catalog, _state_anchor_evidence(state), 2, "terminal", "stale",
		state["beliefs"], commitment, {}, record, state["consumed_recon_keys"],
		[], String(state["state_receipt"]), String(record["record_receipt"])
	)
	if after_state.is_empty() \
			or not validate_state(normalized_catalog, after_state).is_empty():
		return {}
	var belief_delta := _make_belief_state_delta(
		state, after_state, "stale", String(commitment["portfolio_id"])
	)
	if belief_delta.is_empty():
		return {}
	var base := {
		"schema": STALE_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(normalized_catalog["catalog_id"]),
		"catalog_receipt": String(normalized_catalog["catalog_receipt"]),
		"owner_order": ["belief"],
		"accepted_before_state_receipt": accepted_before_state_receipt,
		"accepted_current_campaign_state_receipt":
			accepted_current_campaign_state_receipt,
		"accepted_current_covenant_state_receipt":
			accepted_current_covenant_state_receipt,
		"campaign_owner_scope": campaign_owner_scope,
		"global_network_scope": global_network_scope,
		"recon_points_refunded": 0,
		"belief_delta": belief_delta,
		"stale_record": record,
		"after_state": after_state,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["proposal_id"] = STALE_ID_PREFIX + digest.substr(0, 16)
	base["proposal_receipt"] = _receipt_for(base)
	return base if String(base["proposal_receipt"]) != "" else {}


static func validate_stale_proposal(campaign_catalog: Dictionary,
		covenant_catalog: Dictionary, catalog: Dictionary,
		before_state: Dictionary, accepted_before_state_receipt: String,
		current_campaign_state: Dictionary,
		accepted_current_campaign_state_receipt: String,
		campaign_owner_scope: String, current_covenant_state: Dictionary,
		accepted_current_covenant_state_receipt: String,
		global_network_scope: String, value: Variant) -> Array[String]:
	var expected := close_stale(
		campaign_catalog, covenant_catalog, catalog, before_state,
		accepted_before_state_receipt, current_campaign_state,
		accepted_current_campaign_state_receipt, campaign_owner_scope,
		current_covenant_state, accepted_current_covenant_state_receipt,
		global_network_scope
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["stale closure does not derive from exact changed owner snapshots"]
	return []


static func normalize_stale_proposal(campaign_catalog: Dictionary,
		covenant_catalog: Dictionary, catalog: Dictionary,
		before_state: Dictionary, accepted_before_state_receipt: String,
		current_campaign_state: Dictionary,
		accepted_current_campaign_state_receipt: String,
		campaign_owner_scope: String, current_covenant_state: Dictionary,
		accepted_current_covenant_state_receipt: String,
		global_network_scope: String, value: Variant) -> Dictionary:
	var expected := close_stale(
		campaign_catalog, covenant_catalog, catalog, before_state,
		accepted_before_state_receipt, current_campaign_state,
		accepted_current_campaign_state_receipt, campaign_owner_scope,
		current_covenant_state, accepted_current_covenant_state_receipt,
		global_network_scope
	)
	return expected if not expected.is_empty() and value is Dictionary \
		and _canonical_json(expected) == _canonical_json(value) else {}


static func project_beliefs(catalog: Dictionary, state: Dictionary,
		accepted_state_receipt: String) -> Dictionary:
	if not _catalog_self_valid(catalog):
		return {}
	var normalized_state := accept_state_checkpoint(
		catalog, state, accepted_state_receipt
	)
	if normalized_state.is_empty():
		return {}
	var lifecycle_status := "open"
	if String(normalized_state["phase"]) == "committed":
		lifecycle_status = "awaiting_observations"
	elif String(normalized_state["outcome"]) == "resolved":
		lifecycle_status = "resolved"
	elif String(normalized_state["outcome"]) == "stale":
		lifecycle_status = "stale"
	var base := {
		"schema": PROJECTION_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_id": String(catalog["catalog_id"]),
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"state_receipt": String(normalized_state["state_receipt"]),
		"accepted_state_receipt": accepted_state_receipt,
		"revision": int(normalized_state["revision"]),
		"phase": String(normalized_state["phase"]),
		"outcome": String(normalized_state["outcome"]),
		"lifecycle_status": lifecycle_status,
		"semantics": "epistemic_support_band_not_truth_or_probability",
		"observation_pure": true,
		"beliefs": normalized_state["beliefs"].duplicate(true),
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["projection_id"] = PROJECTION_ID_PREFIX + digest.substr(0, 16)
	base["projection_receipt"] = _receipt_for(base)
	return base if String(base["projection_receipt"]) != "" else {}


static func validate_belief_projection(catalog: Dictionary, state: Dictionary,
		accepted_state_receipt: String, value: Variant) -> Array[String]:
	var expected := project_beliefs(catalog, state, accepted_state_receipt)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["belief projection does not match accepted recon state"]
	return []


static func _normalize_current_owner_snapshots(campaign_catalog: Dictionary,
		campaign_state: Dictionary, accepted_campaign_state_receipt: String,
		campaign_owner_scope: String, covenant_catalog: Dictionary,
		covenant_state: Dictionary, accepted_covenant_state_receipt: String,
		global_network_scope: String, recon_state: Dictionary) -> Dictionary:
	var campaign := PlanetCampaignModel.accept_state_checkpoint(
		campaign_catalog, campaign_state, accepted_campaign_state_receipt
	)
	var normalized_covenant_catalog := CampaignCovenantModel.normalize_catalog(
		campaign_catalog, covenant_catalog
	)
	var covenant := CampaignCovenantModel.accept_state_checkpoint(
		normalized_covenant_catalog, covenant_state, accepted_covenant_state_receipt
	) if not normalized_covenant_catalog.is_empty() else {}
	var commitment: Dictionary = recon_state.get("commitment_record", {})
	if campaign.is_empty() or covenant.is_empty() or commitment.is_empty() \
			or not _slug_valid(campaign_owner_scope) \
			or not _slug_valid(global_network_scope) \
			or campaign_owner_scope != String(commitment["campaign_owner_scope"]) \
			or global_network_scope != String(commitment["global_network_scope"]):
		return {}
	var covenant_record: Dictionary = covenant.get("covenant_record", {})
	if covenant_record.is_empty() or covenant_record.get("record_id") \
			!= commitment.get("covenant_record_id") \
			or covenant_record.get("record_receipt") \
			!= commitment.get("covenant_record_receipt") \
			or covenant_record.get("campaign_owner_scope") != campaign_owner_scope \
			or covenant_record.get("global_network_scope") != global_network_scope:
		return {}
	return {
		"campaign_state": campaign,
		"covenant_state": covenant,
		"changed": accepted_campaign_state_receipt \
			!= String(recon_state["campaign_state_receipt"]) \
			or accepted_covenant_state_receipt \
			!= String(recon_state["covenant_state_receipt"]),
	}


static func _apply_observations(before_beliefs: Array, commitment: Dictionary,
		observations: Array) -> Array[Dictionary]:
	var selected_questions := {}
	for raw_probe in commitment["selected_probes"]:
		var probe: Dictionary = raw_probe
		selected_questions[String(probe["question_id"])] = true
	var observations_by_question := {}
	for raw_observation in observations:
		var observation: Dictionary = raw_observation
		observations_by_question[String(observation["question_id"])] = observation
	if observations_by_question.size() != REQUIRED_PROBES:
		return []
	var result: Array[Dictionary] = []
	for raw_belief in before_beliefs:
		var belief: Dictionary = (raw_belief as Dictionary).duplicate(true)
		var question_id := String(belief["question_id"])
		if selected_questions.has(question_id):
			var observation: Dictionary = observations_by_question.get(question_id, {})
			if observation.is_empty():
				return []
			var observed_signal := String(observation["signal"])
			var bounds := _posterior_bounds(observed_signal)
			if bounds.is_empty() or int(belief["width_bp"]) <= POSTERIOR_WIDTH_BP:
				return []
			belief["minimum_bp"] = bounds[0]
			belief["maximum_bp"] = bounds[1]
			belief["width_bp"] = POSTERIOR_WIDTH_BP
			belief["status"] = "observed"
			belief["observed_signal"] = observed_signal
			belief["observation_receipt"] = String(
				observation["observation_receipt"]
			)
		result.append(belief)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["question_id"]) < String(right["question_id"]))
	return result


static func _posterior_bounds(observed_signal: String) -> Array[int]:
	match observed_signal:
		"adverse":
			return [1000, 3000]
		"favorable":
			return [7000, 9000]
		"mixed":
			return [4000, 6000]
	return []


static func _make_resolution_record(catalog: Dictionary, state: Dictionary,
		commitment: Dictionary, bundle: Dictionary,
		after_beliefs: Array) -> Dictionary:
	var observation_receipts: Array[String] = []
	for raw_observation in bundle["observations"]:
		observation_receipts.append(String(
			(raw_observation as Dictionary)["observation_receipt"]
		))
	observation_receipts.sort()
	var base := {
		"schema": RESOLUTION_RECORD_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"evidence_snapshot_receipt": String(state["evidence_snapshot_receipt"]),
		"commitment_record_id": String(commitment["record_id"]),
		"commitment_record_receipt": String(commitment["record_receipt"]),
		"observation_bundle_id": String(bundle["bundle_id"]),
		"observation_bundle_receipt": String(bundle["bundle_receipt"]),
		"observation_owner_scope": String(bundle["observation_owner_scope"]),
		"observation_owner_checkpoint_receipt": String(
			bundle["observation_owner_checkpoint_receipt"]
		),
		"observation_replay_key": String(bundle["observation_replay_key"]),
		"selected_probe_ids": _probe_ids(commitment["selected_probes"]),
		"observation_receipts": observation_receipts,
		"before_beliefs_receipt": String(commitment["before_beliefs_receipt"]),
		"after_beliefs_receipt": _receipt_for(after_beliefs),
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "" or String(base["after_beliefs_receipt"]) == "":
		return {}
	base["record_id"] = RESOLUTION_RECORD_ID_PREFIX + digest.substr(0, 16)
	base["record_receipt"] = _receipt_for(base)
	return base if String(base["record_receipt"]) != "" else {}


static func _make_stale_record(catalog: Dictionary, state: Dictionary,
		commitment: Dictionary, current_campaign_receipt: String,
		current_covenant_receipt: String,
		current_evidence_receipt: String) -> Dictionary:
	var campaign_changed := current_campaign_receipt \
		!= String(state["campaign_state_receipt"])
	var covenant_changed := current_covenant_receipt \
		!= String(state["covenant_state_receipt"])
	if not campaign_changed and not covenant_changed:
		return {}
	var reason := "both_changed" if campaign_changed and covenant_changed \
		else ("campaign_changed" if campaign_changed else "obligation_changed")
	var base := {
		"schema": STALE_RECORD_SCHEMA,
		"terms_revision": TERMS_REVISION,
		"catalog_receipt": String(catalog["catalog_receipt"]),
		"evidence_snapshot_receipt": String(state["evidence_snapshot_receipt"]),
		"commitment_record_id": String(commitment["record_id"]),
		"commitment_record_receipt": String(commitment["record_receipt"]),
		"original_campaign_state_receipt": String(state["campaign_state_receipt"]),
		"current_campaign_state_receipt": current_campaign_receipt,
		"original_covenant_state_receipt": String(state["covenant_state_receipt"]),
		"current_covenant_state_receipt": current_covenant_receipt,
		"current_evidence_receipt": current_evidence_receipt,
		"stale_reason": reason,
		"recon_points_refunded": 0,
	}
	var digest := _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["record_id"] = STALE_RECORD_ID_PREFIX + digest.substr(0, 16)
	base["record_receipt"] = _receipt_for(base)
	return base if String(base["record_receipt"]) != "" else {}


static func _state_anchor_evidence(state: Dictionary) -> Dictionary:
	return {
		"evidence_receipt": String(state["evidence_snapshot_receipt"]),
		"accepted_campaign_state_receipt": String(state["campaign_state_receipt"]),
		"accepted_covenant_state_receipt": String(state["covenant_state_receipt"]),
		"covenant_record_id": String(state["covenant_record_id"]),
		"covenant_record_receipt": String(state["covenant_record_receipt"]),
		"effective_due_epoch": int(state["effective_due_epoch"]),
	}


static func _sorted_unique_receipts(values: Variant) -> bool:
	if not (values is Array) or (values as Array).size() > MAX_CANONICAL_CONTAINER:
		return false
	var previous := ""
	for raw_value in values as Array:
		if typeof(raw_value) != TYPE_STRING \
				or not _receipt_token_valid(String(raw_value)) \
				or (previous != "" and String(raw_value) <= previous):
			return false
		previous = String(raw_value)
	return true


static func _question_by_id(catalog: Dictionary, question_id: String) -> Dictionary:
	for raw_question in catalog.get("questions", []):
		if raw_question is Dictionary and String((raw_question as Dictionary).get(
				"question_id", "")) == question_id:
			return (raw_question as Dictionary).duplicate(true)
	return {}


static func _question_by_window(catalog: Dictionary, window_id: String) -> Dictionary:
	for raw_question in catalog.get("questions", []):
		if raw_question is Dictionary and String((raw_question as Dictionary).get(
				"window_id", "")) == window_id:
			return (raw_question as Dictionary).duplicate(true)
	return {}


static func _covenant_by_id(catalog: Dictionary, covenant_id: String) -> Dictionary:
	for raw_covenant in catalog.get("covenants", []):
		if raw_covenant is Dictionary and String((raw_covenant as Dictionary).get(
				"covenant_id", "")) == covenant_id:
			return (raw_covenant as Dictionary).duplicate(true)
	return {}


static func _directive_by_id(catalog: Dictionary, directive_id: String) -> Dictionary:
	for raw_directive in catalog.get("directives", []):
		if raw_directive is Dictionary and String((raw_directive as Dictionary).get(
				"directive_id", "")) == directive_id:
			return (raw_directive as Dictionary).duplicate(true)
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
				var encoded := _canonical_json_bounded(item, depth + 1, node_budget)
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
