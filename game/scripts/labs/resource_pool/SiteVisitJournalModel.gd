extends RefCounted

## RP-0005: trusted local action reduction and scarred-site materialization.
##
## The model starts only from an owner-accepted active RP-0004 site state. Raw
## callers supply intents, never effects, scars, damage, noise, or resolution.
## Every journal is replayed from its accepted start before it can advance or
## settle. Receipts are integrity checks, not signatures or client authority.

const SiteBlueprintModel = preload("res://scripts/labs/resource_pool/SiteBlueprintModel.gd")
const ScaleAddress = preload("res://scripts/labs/resource_pool/ScaleAddress.gd")

const RULES_REVISION := "site-visit-rules-v1"
const START_SCHEMA := "living-town.site-visit-start/v1"
const RUNTIME_SCHEMA := "living-town.site-visit-runtime/v1"
const INTENT_SCHEMA := "living-town.site-action-intent/v1"
const EVENT_SCHEMA := "living-town.site-action-event/v1"
const JOURNAL_SCHEMA := "living-town.site-visit-journal/v1"
const ACTION_TRANSITION_SCHEMA := "living-town.site-action-transition/v1"
const TERMINAL_SCHEMA := "living-town.site-visit-terminal/v1"
const SETTLEMENT_SCHEMA := "living-town.site-visit-settlement/v1"
const REVISIT_SCHEMA := "living-town.site-revisit-snapshot/v1"

const MAX_SAFE_JSON_INT := 9007199254740991
const MAX_ACTIONS := 512
const MAX_CARGO_VALUE := 100000000
const MAX_CARGO_GRAMS := 100000000
const START_HEALTH := 100
const CONTACT_DAMAGE := 7
const CARGO_KINDS := ["food", "meds", "parts", "scrap"]
const ACTIVE_PHASE := "active"
const TERMINAL_PHASES := ["extracted", "collapsed", "retreated"]
const RUNTIME_PHASES := ["active", "extracted", "collapsed", "retreated"]
const INTENT_KINDS := [
	"move", "take_loot", "attack_threat", "destroy_prop", "wait", "extract", "abort",
]
const EFFECT_KINDS := [
	"move_player", "take_loot", "damage_threat", "neutralize_threat",
	"destroy_prop", "wait", "alert_threat", "move_threat", "damage_player",
	"reveal_building", "exhaustion", "terminal",
]


## An active site checkpoint is the only admission authority required here. The
## owner must have obtained it by accepting the RP-0004 enter transition and
## atomically moving the site from idle to active.
static func begin_journal(promise: Dictionary, blueprint: Dictionary,
		active_site_state: Dictionary, expected_active_state_receipt: String) -> Dictionary:
	var normalized_blueprint: Dictionary = SiteBlueprintModel.normalize_blueprint(
		promise, blueprint
	)
	var normalized_state: Dictionary = SiteBlueprintModel.accept_state_checkpoint(
		promise, normalized_blueprint, active_site_state, expected_active_state_receipt
	) if not normalized_blueprint.is_empty() else {}
	if normalized_blueprint.is_empty() or normalized_state.is_empty() \
			or String(normalized_state.get("phase", "")) != ACTIVE_PHASE:
		return {}
	var visit_id: String = String(normalized_state["active_visit_id"])
	var journal_material: Array = [
		RULES_REVISION, String(normalized_blueprint["blueprint_receipt"]), visit_id,
		expected_active_state_receipt, String(normalized_state["active_enter_receipt"]),
	]
	var digest: String = _sha256_hex(_canonical_json(journal_material))
	if digest == "":
		return {}
	var journal_id: String = "svj1:" + digest.substr(0, 16)
	var start_base: Dictionary = {
		"schema": START_SCHEMA,
		"rules_revision": RULES_REVISION,
		"journal_id": journal_id,
		"blueprint_id": String(normalized_blueprint["blueprint_id"]),
		"blueprint_receipt": String(normalized_blueprint["blueprint_receipt"]),
		"site_id": String(normalized_blueprint["site_id"]),
		"visit_id": visit_id,
		"active_site_state_receipt": expected_active_state_receipt,
		"active_enter_receipt": String(normalized_state["active_enter_receipt"]),
		"active_arrival_receipt": String(normalized_state["active_arrival_receipt"]),
		"baseline_depleted_loot_ids": (normalized_state["depleted_loot_ids"] as Array).duplicate(true),
		"baseline_neutralized_threat_ids": (normalized_state["neutralized_threat_ids"] as Array).duplicate(true),
		"baseline_revealed_building_ids": (normalized_state["revealed_building_ids"] as Array).duplicate(true),
		"baseline_destroyed_prop_ids": (normalized_state["destroyed_prop_ids"] as Array).duplicate(true),
	}
	start_base["start_receipt"] = _receipt_for(start_base)
	if String(start_base["start_receipt"]) == "":
		return {}
	var runtime: Dictionary = _initial_runtime(normalized_blueprint, start_base)
	if runtime.is_empty():
		return {}
	var journal: Dictionary = {
		"schema": JOURNAL_SCHEMA,
		"start": start_base,
		"events": [],
		"current": runtime,
		"head_event_receipt": "",
	}
	journal["journal_receipt"] = _receipt_for(journal)
	return journal if String(journal["journal_receipt"]) != "" else {}


static func make_intent(journal: Dictionary, kind: String,
		target_id: String = "") -> Dictionary:
	if kind not in INTENT_KINDS or not (journal.get("current") is Dictionary):
		return {}
	var current: Dictionary = journal["current"]
	var start: Dictionary = journal.get("start", {}) as Dictionary
	var payload: Dictionary = {}
	match kind:
		"move":
			payload = {"to_cell_id": target_id}
		"take_loot":
			payload = {"loot_id": target_id}
		"attack_threat":
			payload = {"threat_id": target_id}
		"destroy_prop":
			payload = {"prop_id": target_id}
		"wait", "extract", "abort":
			if target_id != "":
				return {}
			payload = {}
	if target_id == "" and kind in ["move", "take_loot", "attack_threat", "destroy_prop"]:
		return {}
	return {
		"schema": INTENT_SCHEMA,
		"journal_id": String(start.get("journal_id", "")),
		"sequence": int(current.get("sequence", -1)),
		"kind": kind,
		"payload": payload,
	}


## Appends one legal intent. The owner-held expected journal receipt is a CAS
## checkpoint; taking it from the candidate journal is not authorization.
static func append_action(promise: Dictionary, blueprint: Dictionary,
		active_site_state: Dictionary, expected_active_state_receipt: String,
		before_journal: Dictionary, expected_before_journal_receipt: String,
		intent: Dictionary) -> Dictionary:
	var normalized_blueprint: Dictionary = SiteBlueprintModel.normalize_blueprint(
		promise, blueprint
	)
	var normalized_journal: Dictionary = accept_journal_checkpoint(
		promise, normalized_blueprint, active_site_state, expected_active_state_receipt,
		before_journal, expected_before_journal_receipt
	) if not normalized_blueprint.is_empty() else {}
	if normalized_journal.is_empty():
		return {}
	var before_runtime: Dictionary = normalized_journal["current"]
	if String(before_runtime["phase"]) != ACTIVE_PHASE:
		return {}
	var normalized_intent: Dictionary = _normalize_intent(
		intent, String((normalized_journal["start"] as Dictionary)["journal_id"]),
		int(before_runtime["sequence"])
	)
	if normalized_intent.is_empty():
		return {}
	var reduced: Dictionary = _reduce_intent(
		normalized_blueprint, normalized_journal["start"], before_runtime,
		normalized_intent
	)
	if reduced.is_empty():
		return {}
	var events: Array = (normalized_journal["events"] as Array).duplicate(true)
	var previous_event_receipt: String = String(normalized_journal["head_event_receipt"])
	var after_runtime: Dictionary = reduced["runtime"]
	var event: Dictionary = {
		"schema": EVENT_SCHEMA,
		"rules_revision": RULES_REVISION,
		"journal_id": String((normalized_journal["start"] as Dictionary)["journal_id"]),
		"sequence": int(before_runtime["sequence"]),
		"previous_event_receipt": previous_event_receipt,
		"before_runtime_receipt": String(before_runtime["runtime_receipt"]),
		"intent": normalized_intent,
		"turn_delta": int(reduced["turn_delta"]),
		"loudness": int(reduced["loudness"]),
		"effects": (reduced["effects"] as Array).duplicate(true),
		"after_runtime_receipt": String(after_runtime["runtime_receipt"]),
	}
	event["event_receipt"] = _receipt_for(event)
	if String(event["event_receipt"]) == "":
		return {}
	events.append(event)
	var after_journal: Dictionary = {
		"schema": JOURNAL_SCHEMA,
		"start": (normalized_journal["start"] as Dictionary).duplicate(true),
		"events": events,
		"current": after_runtime,
		"head_event_receipt": String(event["event_receipt"]),
	}
	after_journal["journal_receipt"] = _receipt_for(after_journal)
	if String(after_journal["journal_receipt"]) == "":
		return {}
	var transition: Dictionary = {
		"schema": ACTION_TRANSITION_SCHEMA,
		"journal_id": String((normalized_journal["start"] as Dictionary)["journal_id"]),
		"sequence": int(event["sequence"]),
		"before_journal_receipt": String(normalized_journal["journal_receipt"]),
		"expected_checkpoint_receipt": expected_before_journal_receipt,
		"event": event,
		"after_journal_receipt": String(after_journal["journal_receipt"]),
		"journal": after_journal,
	}
	transition["transition_receipt"] = _receipt_for(transition)
	return transition if String(transition["transition_receipt"]) != "" else {}


static func validate_action_transition(promise: Dictionary, blueprint: Dictionary,
		active_site_state: Dictionary, expected_active_state_receipt: String,
		before_journal: Dictionary, expected_before_journal_receipt: String,
		intent: Dictionary, value: Variant) -> Array[String]:
	var expected: Dictionary = append_action(
		promise, blueprint, active_site_state, expected_active_state_receipt,
		before_journal, expected_before_journal_receipt, intent
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["site action transition does not exactly recompute"]
	return _no_string_errors()


## Replays the complete chain. Current runtime snapshots and caller-supplied
## effects are never trusted independently of the accepted start and intents.
static func replay_journal(promise: Dictionary, blueprint: Dictionary,
		active_site_state: Dictionary, expected_active_state_receipt: String,
		value: Variant) -> Dictionary:
	var normalized_blueprint: Dictionary = SiteBlueprintModel.normalize_blueprint(
		promise, blueprint
	)
	var expected_start_journal: Dictionary = begin_journal(
		promise, normalized_blueprint, active_site_state, expected_active_state_receipt
	) if not normalized_blueprint.is_empty() else {}
	if expected_start_journal.is_empty() or not (value is Dictionary):
		return {}
	var data: Dictionary = value
	var required: Array = [
		"schema", "start", "events", "current", "head_event_receipt", "journal_receipt",
	]
	if not _exact_keys(data, required) or data.get("schema") != JOURNAL_SCHEMA \
			or not (data.get("start") is Dictionary) or not (data.get("events") is Array) \
			or not (data.get("current") is Dictionary) \
			or typeof(data.get("head_event_receipt")) != TYPE_STRING \
			or typeof(data.get("journal_receipt")) != TYPE_STRING:
		return {}
	var expected_start: Dictionary = expected_start_journal["start"]
	if _canonical_json(expected_start) != _canonical_json(data["start"]):
		return {}
	var raw_events: Array = data["events"]
	if raw_events.size() > MAX_ACTIONS:
		return {}
	var current: Dictionary = expected_start_journal["current"]
	var expected_events: Array = []
	var previous_event_receipt := ""
	for index in raw_events.size():
		var raw_event_value: Variant = raw_events[index]
		if not (raw_event_value is Dictionary):
			return {}
		var raw_event: Dictionary = raw_event_value
		var normalized_event: Dictionary = _normalize_event_input(raw_event)
		if normalized_event.is_empty():
			return {}
		var normalized_intent: Dictionary = _normalize_intent(
			normalized_event["intent"], String(expected_start["journal_id"]), index
		)
		if normalized_intent.is_empty():
			return {}
		var reduced: Dictionary = _reduce_intent(
			normalized_blueprint, expected_start, current, normalized_intent
		)
		if reduced.is_empty():
			return {}
		var next_runtime: Dictionary = reduced["runtime"]
		var expected_event: Dictionary = {
			"schema": EVENT_SCHEMA,
			"rules_revision": RULES_REVISION,
			"journal_id": String(expected_start["journal_id"]),
			"sequence": index,
			"previous_event_receipt": previous_event_receipt,
			"before_runtime_receipt": String(current["runtime_receipt"]),
			"intent": normalized_intent,
			"turn_delta": int(reduced["turn_delta"]),
			"loudness": int(reduced["loudness"]),
			"effects": (reduced["effects"] as Array).duplicate(true),
			"after_runtime_receipt": String(next_runtime["runtime_receipt"]),
		}
		expected_event["event_receipt"] = _receipt_for(expected_event)
		if _canonical_json(expected_event) != _canonical_json(normalized_event):
			return {}
		expected_events.append(expected_event)
		previous_event_receipt = String(expected_event["event_receipt"])
		current = next_runtime
	var normalized_current: Dictionary = _normalize_runtime_input(data["current"])
	if normalized_current.is_empty() \
			or _canonical_json(normalized_current) != _canonical_json(current) \
			or String(data["head_event_receipt"]) != previous_event_receipt:
		return {}
	var expected_journal: Dictionary = {
		"schema": JOURNAL_SCHEMA,
		"start": expected_start,
		"events": expected_events,
		"current": current,
		"head_event_receipt": previous_event_receipt,
	}
	expected_journal["journal_receipt"] = _receipt_for(expected_journal)
	if String(data["journal_receipt"]) != String(expected_journal["journal_receipt"]):
		return {}
	return expected_journal


static func validate_journal(promise: Dictionary, blueprint: Dictionary,
		active_site_state: Dictionary, expected_active_state_receipt: String,
		value: Variant) -> Array[String]:
	if not replay_journal(
		promise, blueprint, active_site_state, expected_active_state_receipt, value
	).is_empty():
		return _no_string_errors()
	return ["site visit journal does not replay from its accepted start"]


static func accept_journal_checkpoint(promise: Dictionary, blueprint: Dictionary,
		active_site_state: Dictionary, expected_active_state_receipt: String,
		value: Variant, expected_journal_receipt: String) -> Dictionary:
	if not _receipt_token_valid(expected_journal_receipt):
		return {}
	var normalized: Dictionary = replay_journal(
		promise, blueprint, active_site_state, expected_active_state_receipt, value
	)
	return normalized if not normalized.is_empty() \
		and String(normalized["journal_receipt"]) == expected_journal_receipt else {}


static func finalize_terminal(promise: Dictionary, blueprint: Dictionary,
		active_site_state: Dictionary, expected_active_state_receipt: String,
		journal: Dictionary, expected_journal_receipt: String) -> Dictionary:
	var normalized_blueprint: Dictionary = SiteBlueprintModel.normalize_blueprint(
		promise, blueprint
	)
	var normalized_journal: Dictionary = accept_journal_checkpoint(
		promise, normalized_blueprint, active_site_state, expected_active_state_receipt,
		journal, expected_journal_receipt
	) if not normalized_blueprint.is_empty() else {}
	if normalized_journal.is_empty():
		return {}
	var current: Dictionary = normalized_journal["current"]
	var resolution: String = String(current["phase"])
	if resolution not in TERMINAL_PHASES:
		return {}
	var disposition := "banked" if resolution == "extracted" else (
		"lost" if resolution == "collapsed" else "none"
	)
	var base: Dictionary = {
		"schema": TERMINAL_SCHEMA,
		"rules_revision": RULES_REVISION,
		"journal_id": String((normalized_journal["start"] as Dictionary)["journal_id"]),
		"blueprint_id": String(normalized_blueprint["blueprint_id"]),
		"blueprint_receipt": String(normalized_blueprint["blueprint_receipt"]),
		"visit_id": String((normalized_journal["start"] as Dictionary)["visit_id"]),
		"active_site_state_receipt": expected_active_state_receipt,
		"journal_receipt": String(normalized_journal["journal_receipt"]),
		"head_event_receipt": String(normalized_journal["head_event_receipt"]),
		"resolution": resolution,
		"action_count": (normalized_journal["events"] as Array).size(),
		"elapsed_turns": int(current["turns"]),
		"player_cell_id": String(current["player_cell_id"]),
		"health": int(current["health"]),
		"peak_noise": int(current["peak_noise"]),
		"inventory": (current["inventory"] as Array).duplicate(true),
		"cargo_value": int(current["cargo_value"]),
		"cargo_weight_grams": int(current["cargo_weight_grams"]),
		"cargo_disposition": disposition,
		"depleted_loot_ids": (current["taken_loot_ids"] as Array).duplicate(true),
		"neutralized_threat_ids": (current["neutralized_threat_ids"] as Array).duplicate(true),
		"revealed_building_ids": (current["revealed_building_ids"] as Array).duplicate(true),
		"destroyed_prop_ids": (current["destroyed_prop_ids"] as Array).duplicate(true),
	}
	var digest: String = _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["terminal_id"] = "svt1:" + digest.substr(0, 16)
	base["terminal_receipt"] = _receipt_for(base)
	return base if String(base["terminal_receipt"]) != "" else {}


static func validate_terminal(promise: Dictionary, blueprint: Dictionary,
		active_site_state: Dictionary, expected_active_state_receipt: String,
		journal: Dictionary, expected_journal_receipt: String,
		value: Variant) -> Array[String]:
	var expected: Dictionary = finalize_terminal(
		promise, blueprint, active_site_state, expected_active_state_receipt,
		journal, expected_journal_receipt
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["site visit terminal does not derive from the accepted journal"]
	return _no_string_errors()


## The only RP-0005 path that proposes RP-0004 scars. It validates the complete
## journal, derives the terminal witness, then calls the RP-0004 constructor with
## reducer-owned ID lists. The owner still commits active->idle with an atomic CAS.
static func derive_site_settlement(promise: Dictionary, blueprint: Dictionary,
		active_site_state: Dictionary, expected_active_state_receipt: String,
		journal: Dictionary, expected_journal_receipt: String,
		enter_transition: Dictionary, accepted_idle_state_receipt: String,
		atlas: Dictionary, atlas_state: Dictionary, plan: Dictionary,
		journey: Dictionary, route_receipt: Dictionary,
		accepted_journey_state_receipt: String) -> Dictionary:
	var terminal: Dictionary = finalize_terminal(
		promise, blueprint, active_site_state, expected_active_state_receipt,
		journal, expected_journal_receipt
	)
	if terminal.is_empty() or not (enter_transition.get("after_state") is Dictionary) \
			or _canonical_json(active_site_state) \
				!= _canonical_json(enter_transition.get("after_state", {})) \
			or String(enter_transition.get("after_state_receipt", "")) \
				!= expected_active_state_receipt:
		return {}
	var visit_delta: Dictionary = SiteBlueprintModel.make_visit_delta(
		promise, blueprint, active_site_state, enter_transition,
		accepted_idle_state_receipt, atlas, atlas_state, plan, journey,
		route_receipt, accepted_journey_state_receipt,
		String(terminal["visit_id"]), String(terminal["resolution"]),
		int(terminal["elapsed_turns"]), terminal["depleted_loot_ids"],
		terminal["neutralized_threat_ids"], terminal["revealed_building_ids"],
		terminal["destroyed_prop_ids"]
	)
	if visit_delta.is_empty():
		return {}
	var state_transition: Dictionary = SiteBlueprintModel.apply_visit_delta(
		promise, blueprint, active_site_state, enter_transition,
		accepted_idle_state_receipt, atlas, atlas_state, plan, journey,
		route_receipt, accepted_journey_state_receipt, visit_delta
	)
	if state_transition.is_empty():
		return {}
	var base: Dictionary = {
		"schema": SETTLEMENT_SCHEMA,
		"journal_id": String(terminal["journal_id"]),
		"visit_id": String(terminal["visit_id"]),
		"blueprint_id": String(terminal["blueprint_id"]),
		"active_site_state_receipt": expected_active_state_receipt,
		"expected_journal_receipt": expected_journal_receipt,
		"terminal": terminal,
		"terminal_receipt": String(terminal["terminal_receipt"]),
		"visit_delta": visit_delta,
		"visit_delta_receipt": String(visit_delta["delta_receipt"]),
		"site_transition": state_transition,
		"idle_site_state_receipt": String(state_transition["after_state_receipt"]),
	}
	var digest: String = _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["settlement_id"] = "svs1:" + digest.substr(0, 16)
	base["settlement_receipt"] = _receipt_for(base)
	return base if String(base["settlement_receipt"]) != "" else {}


static func validate_site_settlement(promise: Dictionary, blueprint: Dictionary,
		active_site_state: Dictionary, expected_active_state_receipt: String,
		journal: Dictionary, expected_journal_receipt: String,
		enter_transition: Dictionary, accepted_idle_state_receipt: String,
		atlas: Dictionary, atlas_state: Dictionary, plan: Dictionary,
		journey: Dictionary, route_receipt: Dictionary,
		accepted_journey_state_receipt: String, value: Variant) -> Array[String]:
	var expected: Dictionary = derive_site_settlement(
		promise, blueprint, active_site_state, expected_active_state_receipt,
		journal, expected_journal_receipt, enter_transition,
		accepted_idle_state_receipt, atlas, atlas_state, plan, journey,
		route_receipt, accepted_journey_state_receipt
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["site settlement does not derive from the accepted terminal journal"]
	return _no_string_errors()


## Revisit snapshots are disposable observation DTOs. Durable authority remains
## the immutable blueprint plus the owner-accepted idle scar state.
static func materialize_revisit(promise: Dictionary, blueprint: Dictionary,
		idle_site_state: Dictionary, expected_idle_state_receipt: String) -> Dictionary:
	var normalized_blueprint: Dictionary = SiteBlueprintModel.normalize_blueprint(
		promise, blueprint
	)
	var normalized_state: Dictionary = SiteBlueprintModel.accept_state_checkpoint(
		promise, normalized_blueprint, idle_site_state, expected_idle_state_receipt
	) if not normalized_blueprint.is_empty() else {}
	if normalized_blueprint.is_empty() or normalized_state.is_empty() \
			or String(normalized_state["phase"]) != "idle":
		return {}
	var depleted: Dictionary = _array_set(normalized_state["depleted_loot_ids"] as Array)
	var neutralized: Dictionary = _array_set(normalized_state["neutralized_threat_ids"] as Array)
	var destroyed: Dictionary = _array_set(normalized_state["destroyed_prop_ids"] as Array)
	var projected_buildings: Array = []
	var revealed: Dictionary = _array_set(normalized_state["revealed_building_ids"] as Array)
	for raw_building in normalized_blueprint["buildings"] as Array:
		var building: Dictionary = (raw_building as Dictionary).duplicate(true)
		building["roof_revealed"] = revealed.has(String(building["id"]))
		projected_buildings.append(building)
	var projected_props: Array = []
	for raw_prop in normalized_blueprint["props"] as Array:
		var prop: Dictionary = raw_prop
		if not destroyed.has(String(prop["id"])):
			projected_props.append(prop.duplicate(true))
	var projected_loot: Array = []
	for raw_loot in normalized_blueprint["loot"] as Array:
		var loot: Dictionary = raw_loot
		if not depleted.has(String(loot["id"])):
			projected_loot.append(loot.duplicate(true))
	var projected_threats: Array = []
	for raw_threat in normalized_blueprint["threats"] as Array:
		var threat: Dictionary = raw_threat
		if not neutralized.has(String(threat["id"])):
			projected_threats.append(threat.duplicate(true))
	var navigation: Dictionary = _projection_navigation(
		normalized_blueprint, projected_props
	)
	if navigation.is_empty():
		return {}
	var base: Dictionary = {
		"schema": REVISIT_SCHEMA,
		"rules_revision": RULES_REVISION,
		"blueprint_id": String(normalized_blueprint["blueprint_id"]),
		"blueprint_receipt": String(normalized_blueprint["blueprint_receipt"]),
		"site_id": String(normalized_blueprint["site_id"]),
		"site_kind": String(normalized_blueprint["site_kind"]),
		"layout_key": String(normalized_blueprint["layout_key"]),
		"site_state_receipt": expected_idle_state_receipt,
		"revision": int(normalized_state["revision"]),
		"width": int(normalized_blueprint["width"]),
		"height": int(normalized_blueprint["height"]),
		"cells": (normalized_blueprint["cells"] as Array).duplicate(true),
		"entry": (normalized_blueprint["entry"] as Dictionary).duplicate(true),
		"extraction": (normalized_blueprint["extraction"] as Dictionary).duplicate(true),
		"buildings": projected_buildings,
		"props": projected_props,
		"loot": projected_loot,
		"threats": projected_threats,
		"depleted_loot_ids": (normalized_state["depleted_loot_ids"] as Array).duplicate(true),
		"neutralized_threat_ids": (normalized_state["neutralized_threat_ids"] as Array).duplicate(true),
		"revealed_building_ids": (normalized_state["revealed_building_ids"] as Array).duplicate(true),
		"destroyed_prop_ids": (normalized_state["destroyed_prop_ids"] as Array).duplicate(true),
		"navigation": navigation,
	}
	var digest: String = _sha256_hex(_canonical_json(base))
	if digest == "":
		return {}
	base["projection_id"] = "srv1:" + digest.substr(0, 16)
	base["projection_receipt"] = _receipt_for(base)
	return base if String(base["projection_receipt"]) != "" else {}


static func validate_revisit(promise: Dictionary, blueprint: Dictionary,
		idle_site_state: Dictionary, expected_idle_state_receipt: String,
		value: Variant) -> Array[String]:
	var expected: Dictionary = materialize_revisit(
		promise, blueprint, idle_site_state, expected_idle_state_receipt
	)
	if expected.is_empty() or not (value is Dictionary) \
			or _canonical_json(expected) != _canonical_json(value):
		return ["site revisit projection does not derive from blueprint plus accepted scars"]
	return _no_string_errors()


## Checked gameplay query. A projection alone is disposable observation data;
## the immutable blueprint and owner-held idle receipt remain the authority.
static func revisit_is_walkable(promise: Dictionary, blueprint: Dictionary,
		idle_site_state: Dictionary, expected_idle_state_receipt: String,
		projection: Dictionary, cell_id: String) -> bool:
	var expected: Dictionary = materialize_revisit(
		promise, blueprint, idle_site_state, expected_idle_state_receipt
	)
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(projection):
		return false
	return _projection_is_walkable_unchecked(expected, cell_id)


static func _projection_is_walkable_unchecked(projection: Dictionary,
		cell_id: String) -> bool:
	if not _cell_id_valid_for_site(
		cell_id, String(projection["site_id"]),
		int(projection["width"]), int(projection["height"])
	):
		return false
	var pos: Vector2i = _cell_pos(cell_id)
	var width: int = int(projection["width"])
	var cells: Array = projection.get("cells", []) as Array
	if cells.size() != width * int(projection["height"]):
		return false
	if int(cells[pos.y * width + pos.x]) not in SiteBlueprintModel.WALKABLE_CELLS:
		return false
	for raw_prop in projection.get("props", []) as Array:
		var prop: Dictionary = raw_prop
		if bool(prop.get("blocking", false)) and String(prop.get("cell_id", "")) == cell_id:
			return false
	return true


static func canonical_json(value: Variant) -> String:
	return _canonical_json(value)


static func _initial_runtime(blueprint: Dictionary, start: Dictionary) -> Dictionary:
	var baseline_neutralized: Dictionary = _array_set(
		start["baseline_neutralized_threat_ids"] as Array
	)
	var threat_states: Array = []
	for raw_threat in blueprint["threats"] as Array:
		var threat: Dictionary = raw_threat
		if not baseline_neutralized.has(String(threat["id"])):
			threat_states.append({
				"id": String(threat["id"]),
				"cell_id": String(threat["cell_id"]),
				"hp": int(threat["hp"]),
				"alerted": false,
			})
	threat_states.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["id"]) < String(right["id"])
	)
	var base: Dictionary = {
		"schema": RUNTIME_SCHEMA,
		"rules_revision": RULES_REVISION,
		"journal_id": String(start["journal_id"]),
		"sequence": 0,
		"turns": 0,
		"phase": ACTIVE_PHASE,
		"player_cell_id": String((blueprint["entry"] as Dictionary)["cell_id"]),
		"health": START_HEALTH,
		"noise": 0,
		"peak_noise": 0,
		"inventory": _empty_inventory(),
		"cargo_value": 0,
		"cargo_weight_grams": 0,
		"taken_loot_ids": [],
		"neutralized_threat_ids": [],
		"revealed_building_ids": [],
		"destroyed_prop_ids": [],
		"threat_states": threat_states,
		"parent_runtime_receipt": String(start["active_site_state_receipt"]),
	}
	base["runtime_receipt"] = _receipt_for(base)
	return base if String(base["runtime_receipt"]) != "" else {}


static func _reduce_intent(blueprint: Dictionary, start: Dictionary,
		before: Dictionary, intent: Dictionary) -> Dictionary:
	if String(before.get("phase", "")) != ACTIVE_PHASE \
			or int(before.get("sequence", -1)) >= MAX_ACTIONS:
		return {}
	var kind: String = String(intent["kind"])
	var payload: Dictionary = intent["payload"]
	var after: Dictionary = before.duplicate(true)
	var effects: Array = []
	var loudness := 0
	var turn_delta := 0
	if kind == "abort":
		if int(before["sequence"]) != 0 or int(before["turns"]) != 0 \
				or not _runtime_scars_empty(before):
			return {}
		after["phase"] = "retreated"
		effects.append(_effect("terminal", "retreated", "", "", 0))
	elif kind == "extract":
		if int(before["health"]) <= 0 or String(before["player_cell_id"]) \
				!= String((blueprint["extraction"] as Dictionary)["cell_id"]):
			return {}
		after["phase"] = "extracted"
		effects.append(_effect("terminal", "extracted", "", "", 0))
	else:
		turn_delta = 1
		match kind:
			"move":
				var target_cell: String = String(payload["to_cell_id"])
				var from_cell: String = String(before["player_cell_id"])
				if not _cardinal_neighbor(from_cell, target_cell) \
						or not _runtime_walkable(blueprint, start, before, target_cell, ""):
					return {}
				after["player_cell_id"] = target_cell
				loudness = 1
				effects.append(_effect("move_player", "player", from_cell, target_cell, 0))
			"take_loot":
				var loot_id: String = String(payload["loot_id"])
				var loot: Dictionary = _entity_by_id(blueprint["loot"] as Array, loot_id)
				if loot.is_empty() or not _adjacent_or_same(
					String(before["player_cell_id"]), String(loot["cell_id"])
				) or loot_id in (start["baseline_depleted_loot_ids"] as Array) \
						or loot_id in (before["taken_loot_ids"] as Array):
					return {}
				var taken: Array = (after["taken_loot_ids"] as Array).duplicate(true)
				taken.append(loot_id)
				taken.sort()
				after["taken_loot_ids"] = taken
				after["inventory"] = _inventory_add(
					after["inventory"] as Array, String(loot["kind"]), 1
				)
				after["cargo_value"] = int(after["cargo_value"]) + int(loot["value"])
				after["cargo_weight_grams"] = int(after["cargo_weight_grams"]) \
					+ int(loot["weight_grams"])
				loudness = int(loot["noise"])
				effects.append(_effect("take_loot", loot_id, "", "", int(loot["value"])))
			"attack_threat":
				var threat_id: String = String(payload["threat_id"])
				var states: Array = (after["threat_states"] as Array).duplicate(true)
				var threat_index: int = _threat_state_index(states, threat_id)
				if threat_index < 0:
					return {}
				var threat_state: Dictionary = states[threat_index]
				if int(threat_state["hp"]) <= 0 or not _adjacent_or_same(
					String(before["player_cell_id"]), String(threat_state["cell_id"])
				):
					return {}
				var was_alerted: bool = bool(threat_state["alerted"])
				threat_state["hp"] = int(threat_state["hp"]) - 1
				threat_state["alerted"] = true
				states[threat_index] = threat_state
				after["threat_states"] = states
				loudness = 4
				effects.append(_effect("damage_threat", threat_id, "", "", 1))
				if not was_alerted:
					effects.append(_effect("alert_threat", threat_id, "", "", 0))
				if int(threat_state["hp"]) == 0:
					var neutralized: Array = (after["neutralized_threat_ids"] as Array).duplicate(true)
					neutralized.append(threat_id)
					neutralized.sort()
					after["neutralized_threat_ids"] = neutralized
					effects.append(_effect("neutralize_threat", threat_id, "", "", 0))
			"destroy_prop":
				var prop_id: String = String(payload["prop_id"])
				var prop: Dictionary = _entity_by_id(blueprint["props"] as Array, prop_id)
				if prop.is_empty() or not bool(prop.get("destructible", false)) \
						or not _adjacent_or_same(
							String(before["player_cell_id"]), String(prop["cell_id"])
						) or prop_id in (start["baseline_destroyed_prop_ids"] as Array) \
						or prop_id in (before["destroyed_prop_ids"] as Array):
					return {}
				var destroyed: Array = (after["destroyed_prop_ids"] as Array).duplicate(true)
				destroyed.append(prop_id)
				destroyed.sort()
				after["destroyed_prop_ids"] = destroyed
				loudness = 3
				effects.append(_effect("destroy_prop", prop_id, "", "", 0))
			"wait":
				loudness = 0
				effects.append(_effect("wait", "player", "", "", 0))
			_:
				return {}
		after["turns"] = int(before["turns"]) + 1
		after["noise"] = clampi(int(before["noise"]) - 1 + loudness, 0, 10)
		after["peak_noise"] = maxi(int(before["peak_noise"]), int(after["noise"]))
		var tick_effects: Array = _tick_threats(blueprint, start, after)
		if tick_effects.is_empty() and bool(after.get("_tick_failed", false)):
			return {}
		after.erase("_tick_failed")
		effects.append_array(tick_effects)
		# The journal has a hard replay bound. Reaching it is a reducer-owned
		# exhaustion collapse so no accepted active state can become unresolvable.
		if String(after["phase"]) == ACTIVE_PHASE \
				and int(before["sequence"]) + 1 >= MAX_ACTIONS:
			var remaining_health: int = int(after["health"])
			after["health"] = 0
			after["phase"] = "collapsed"
			effects.append(_effect("exhaustion", "player", "", "", remaining_health))
			effects.append(_effect("terminal", "collapsed", "", "", 0))
		if String(after["phase"]) == ACTIVE_PHASE:
			var reveal_effects: Array = _derive_reveal(blueprint, start, after)
			effects.append_array(reveal_effects)
	after["sequence"] = int(before["sequence"]) + 1
	after["parent_runtime_receipt"] = String(before["runtime_receipt"])
	after.erase("runtime_receipt")
	after["runtime_receipt"] = _receipt_for(after)
	if String(after["runtime_receipt"]) == "":
		return {}
	return {
		"runtime": after,
		"turn_delta": turn_delta,
		"loudness": loudness,
		"effects": effects,
	}


static func _tick_threats(blueprint: Dictionary, start: Dictionary,
		runtime: Dictionary) -> Array:
	var effects: Array = []
	var states: Array = (runtime["threat_states"] as Array).duplicate(true)
	for index in states.size():
		var state: Dictionary = states[index]
		if int(state["hp"]) <= 0:
			continue
		var threat: Dictionary = _entity_by_id(
			blueprint["threats"] as Array, String(state["id"])
		)
		if threat.is_empty():
			runtime["_tick_failed"] = true
			return []
		var player_cell: String = String(runtime["player_cell_id"])
		var distance: int = _cell_distance(String(state["cell_id"]), player_cell)
		if not bool(state["alerted"]) \
				and distance <= int(threat["alert_radius"]) + int(runtime["noise"]):
			state["alerted"] = true
			effects.append(_effect("alert_threat", String(state["id"]), "", "", 0))
		if bool(state["alerted"]) and int(runtime["turns"]) % 2 == 0:
			var from_cell: String = String(state["cell_id"])
			var next_cell: String = _threat_step(
				blueprint, start, runtime, states, index, from_cell, player_cell
			)
			if next_cell != "" and next_cell != from_cell:
				state["cell_id"] = next_cell
				effects.append(_effect(
					"move_threat", String(state["id"]), from_cell, next_cell, 0
				))
		states[index] = state
		distance = _cell_distance(String(state["cell_id"]), player_cell)
		if distance <= 1 and bool(state["alerted"]):
			var applied_damage: int = mini(CONTACT_DAMAGE, int(runtime["health"]))
			runtime["health"] = int(runtime["health"]) - applied_damage
			effects.append(_effect(
				"damage_player", String(state["id"]), "", "", applied_damage
			))
			if int(runtime["health"]) <= 0:
				runtime["phase"] = "collapsed"
				effects.append(_effect("terminal", "collapsed", "", "", 0))
				break
	runtime["threat_states"] = states
	return effects


static func _threat_step(blueprint: Dictionary, start: Dictionary,
		runtime: Dictionary, states: Array, self_index: int,
		from_cell: String, player_cell: String) -> String:
	var from_pos: Vector2i = _cell_pos(from_cell)
	var player_pos: Vector2i = _cell_pos(player_cell)
	var dx: int = signi(player_pos.x - from_pos.x)
	var dy: int = signi(player_pos.y - from_pos.y)
	var x_distance: int = absi(player_pos.x - from_pos.x)
	var y_distance: int = absi(player_pos.y - from_pos.y)
	var steps: Array[Vector2i] = []
	if x_distance >= y_distance:
		if dx != 0:
			steps.append(Vector2i(dx, 0))
		if dy != 0:
			steps.append(Vector2i(0, dy))
	else:
		if dy != 0:
			steps.append(Vector2i(0, dy))
		if dx != 0:
			steps.append(Vector2i(dx, 0))
	for step in steps:
		var target_pos: Vector2i = from_pos + step
		var target_cell: String = _cell_id_at(blueprint, target_pos)
		if target_cell == "" or target_cell == player_cell:
			continue
		if _terrain_and_prop_walkable(blueprint, start, runtime, target_cell) \
				and not _other_live_threat_at(states, self_index, target_cell):
			return target_cell
	return from_cell


static func _derive_reveal(blueprint: Dictionary, start: Dictionary,
		runtime: Dictionary) -> Array:
	var effects: Array = []
	var pos: Vector2i = _cell_pos(String(runtime["player_cell_id"]))
	for raw_building in blueprint["buildings"] as Array:
		var building: Dictionary = raw_building
		var rect: Array = building["rect"]
		var inside: bool = pos.x > int(rect[0]) and pos.y > int(rect[1]) \
			and pos.x < int(rect[0]) + int(rect[2]) - 1 \
			and pos.y < int(rect[1]) + int(rect[3]) - 1
		var building_id: String = String(building["id"])
		if inside and building_id not in (start["baseline_revealed_building_ids"] as Array) \
				and building_id not in (runtime["revealed_building_ids"] as Array):
			var revealed: Array = (runtime["revealed_building_ids"] as Array).duplicate(true)
			revealed.append(building_id)
			revealed.sort()
			runtime["revealed_building_ids"] = revealed
			effects.append(_effect("reveal_building", building_id, "", "", 0))
			break
	return effects


static func _runtime_walkable(blueprint: Dictionary, start: Dictionary,
		runtime: Dictionary, cell_id: String, ignored_threat_id: String) -> bool:
	if not _terrain_and_prop_walkable(blueprint, start, runtime, cell_id):
		return false
	for raw_state in runtime["threat_states"] as Array:
		var state: Dictionary = raw_state
		if int(state["hp"]) > 0 and String(state["id"]) != ignored_threat_id \
				and String(state["cell_id"]) == cell_id:
			return false
	return true


static func _terrain_and_prop_walkable(blueprint: Dictionary, start: Dictionary,
		runtime: Dictionary, cell_id: String) -> bool:
	if not _cell_id_valid_for_site(
		cell_id, String(blueprint["site_id"]), int(blueprint["width"]), int(blueprint["height"])
	):
		return false
	var pos: Vector2i = _cell_pos(cell_id)
	if SiteBlueprintModel.cell_at(blueprint, pos) not in SiteBlueprintModel.WALKABLE_CELLS:
		return false
	for raw_prop in blueprint["props"] as Array:
		var prop: Dictionary = raw_prop
		if bool(prop["blocking"]) and String(prop["cell_id"]) == cell_id \
				and String(prop["id"]) not in (start["baseline_destroyed_prop_ids"] as Array) \
				and String(prop["id"]) not in (runtime["destroyed_prop_ids"] as Array):
			return false
	return true


static func _projection_navigation(blueprint: Dictionary, projected_props: Array) -> Dictionary:
	var entry: String = String((blueprint["entry"] as Dictionary)["cell_id"])
	var extraction: String = String((blueprint["extraction"] as Dictionary)["cell_id"])
	var reached: Dictionary = {}
	var queue: Array[String] = []
	if _projection_cell_walkable(blueprint, projected_props, entry):
		reached[entry] = true
		queue.append(entry)
	var head := 0
	while head < queue.size():
		var current: String = queue[head]
		head += 1
		var pos: Vector2i = _cell_pos(current)
		for step in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var next_cell: String = _cell_id_at(blueprint, pos + step)
			if next_cell != "" and not reached.has(next_cell) \
					and _projection_cell_walkable(blueprint, projected_props, next_cell):
				reached[next_cell] = true
				queue.append(next_cell)
	var blocking_ids: Array = []
	for raw_prop in projected_props:
		var prop: Dictionary = raw_prop
		if bool(prop["blocking"]):
			blocking_ids.append(String(prop["id"]))
	blocking_ids.sort()
	var base: Dictionary = {
		"blocking_prop_ids": blocking_ids,
		"reachable_cells": reached.size(),
		"extraction_reachable": reached.has(extraction),
	}
	base["navigation_receipt"] = _receipt_for(base)
	return base if String(base["navigation_receipt"]) != "" else {}


static func _projection_cell_walkable(blueprint: Dictionary,
		projected_props: Array, cell_id: String) -> bool:
	if not _cell_id_valid_for_site(
		cell_id, String(blueprint["site_id"]), int(blueprint["width"]), int(blueprint["height"])
	):
		return false
	if SiteBlueprintModel.cell_at(blueprint, _cell_pos(cell_id)) \
			not in SiteBlueprintModel.WALKABLE_CELLS:
		return false
	for raw_prop in projected_props:
		var prop: Dictionary = raw_prop
		if bool(prop["blocking"]) and String(prop["cell_id"]) == cell_id:
			return false
	return true


static func _normalize_intent(value: Variant, journal_id: String,
		expected_sequence: int) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var data: Dictionary = value
	var required: Array = ["schema", "journal_id", "sequence", "kind", "payload"]
	if not _exact_keys(data, required) or data.get("schema") != INTENT_SCHEMA \
			or typeof(data.get("journal_id")) != TYPE_STRING \
			or String(data["journal_id"]) != journal_id \
			or not _bounded_int(data.get("sequence"), expected_sequence, expected_sequence) \
			or typeof(data.get("kind")) != TYPE_STRING \
			or String(data["kind"]) not in INTENT_KINDS \
			or not (data.get("payload") is Dictionary):
		return {}
	var kind: String = String(data["kind"])
	var payload: Dictionary = data["payload"]
	var normalized_payload: Dictionary = {}
	match kind:
		"move":
			if not _exact_string_payload(payload, "to_cell_id"):
				return {}
			normalized_payload = {"to_cell_id": String(payload["to_cell_id"])}
		"take_loot":
			if not _exact_string_payload(payload, "loot_id"):
				return {}
			normalized_payload = {"loot_id": String(payload["loot_id"])}
		"attack_threat":
			if not _exact_string_payload(payload, "threat_id"):
				return {}
			normalized_payload = {"threat_id": String(payload["threat_id"])}
		"destroy_prop":
			if not _exact_string_payload(payload, "prop_id"):
				return {}
			normalized_payload = {"prop_id": String(payload["prop_id"])}
		"wait", "extract", "abort":
			if not payload.is_empty():
				return {}
			normalized_payload = {}
	return {
		"schema": INTENT_SCHEMA,
		"journal_id": journal_id,
		"sequence": expected_sequence,
		"kind": kind,
		"payload": normalized_payload,
	}


static func _normalize_event_input(value: Dictionary) -> Dictionary:
	var required: Array = [
		"schema", "rules_revision", "journal_id", "sequence",
		"previous_event_receipt", "before_runtime_receipt", "intent",
		"turn_delta", "loudness", "effects", "after_runtime_receipt", "event_receipt",
	]
	if not _exact_keys(value, required) or value.get("schema") != EVENT_SCHEMA \
			or value.get("rules_revision") != RULES_REVISION \
			or typeof(value.get("journal_id")) != TYPE_STRING \
			or not _bounded_int(value.get("sequence"), 0, MAX_ACTIONS - 1) \
			or typeof(value.get("previous_event_receipt")) != TYPE_STRING \
			or typeof(value.get("before_runtime_receipt")) != TYPE_STRING \
			or not (value.get("intent") is Dictionary) \
			or not _bounded_int(value.get("turn_delta"), 0, 1) \
			or not _bounded_int(value.get("loudness"), 0, 10) \
			or not (value.get("effects") is Array) \
			or typeof(value.get("after_runtime_receipt")) != TYPE_STRING \
			or typeof(value.get("event_receipt")) != TYPE_STRING:
		return {}
	var effects: Array = []
	for raw_effect in value["effects"] as Array:
		var normalized_effect: Dictionary = _normalize_effect(raw_effect)
		if normalized_effect.is_empty():
			return {}
		effects.append(normalized_effect)
	return {
		"schema": EVENT_SCHEMA,
		"rules_revision": RULES_REVISION,
		"journal_id": String(value["journal_id"]),
		"sequence": int(value["sequence"]),
		"previous_event_receipt": String(value["previous_event_receipt"]),
		"before_runtime_receipt": String(value["before_runtime_receipt"]),
		"intent": (value["intent"] as Dictionary).duplicate(true),
		"turn_delta": int(value["turn_delta"]),
		"loudness": int(value["loudness"]),
		"effects": effects,
		"after_runtime_receipt": String(value["after_runtime_receipt"]),
		"event_receipt": String(value["event_receipt"]),
	}


static func _normalize_runtime_input(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var data: Dictionary = value
	var required: Array = [
		"schema", "rules_revision", "journal_id", "sequence", "turns", "phase",
		"player_cell_id", "health", "noise", "peak_noise", "inventory",
		"cargo_value", "cargo_weight_grams", "taken_loot_ids",
		"neutralized_threat_ids", "revealed_building_ids", "destroyed_prop_ids",
		"threat_states", "parent_runtime_receipt", "runtime_receipt",
	]
	if not _exact_keys(data, required) or data.get("schema") != RUNTIME_SCHEMA \
			or data.get("rules_revision") != RULES_REVISION \
			or typeof(data.get("journal_id")) != TYPE_STRING \
			or not _bounded_int(data.get("sequence"), 0, MAX_ACTIONS) \
			or not _bounded_int(data.get("turns"), 0, MAX_ACTIONS) \
			or typeof(data.get("phase")) != TYPE_STRING \
			or String(data["phase"]) not in RUNTIME_PHASES \
			or typeof(data.get("player_cell_id")) != TYPE_STRING \
			or not _bounded_int(data.get("health"), 0, START_HEALTH) \
			or not _bounded_int(data.get("noise"), 0, 10) \
			or not _bounded_int(data.get("peak_noise"), 0, 10) \
			or not _bounded_int(data.get("cargo_value"), 0, MAX_CARGO_VALUE) \
			or not _bounded_int(data.get("cargo_weight_grams"), 0, MAX_CARGO_GRAMS) \
			or not (data.get("inventory") is Array) or not (data.get("threat_states") is Array) \
			or typeof(data.get("parent_runtime_receipt")) != TYPE_STRING \
			or typeof(data.get("runtime_receipt")) != TYPE_STRING:
		return {}
	for key in ["taken_loot_ids", "neutralized_threat_ids", "revealed_building_ids",
			"destroyed_prop_ids"]:
		if not (data.get(key) is Array) or not _sorted_unique_strings(data[key] as Array):
			return {}
	var inventory: Array = _normalize_inventory(data["inventory"] as Array)
	if inventory.is_empty():
		return {}
	var threat_states: Array = []
	var prior_id := ""
	for raw_state in data["threat_states"] as Array:
		if not (raw_state is Dictionary):
			return {}
		var state: Dictionary = raw_state
		var state_required: Array = ["id", "cell_id", "hp", "alerted"]
		if not _exact_keys(state, state_required) or typeof(state.get("id")) != TYPE_STRING \
				or typeof(state.get("cell_id")) != TYPE_STRING \
				or not _bounded_int(state.get("hp"), 0, 100) \
				or typeof(state.get("alerted")) != TYPE_BOOL \
				or (prior_id != "" and String(state["id"]) <= prior_id):
			return {}
		prior_id = String(state["id"])
		threat_states.append({
			"id": String(state["id"]), "cell_id": String(state["cell_id"]),
			"hp": int(state["hp"]), "alerted": bool(state["alerted"]),
		})
	var normalized: Dictionary = {
		"schema": RUNTIME_SCHEMA,
		"rules_revision": RULES_REVISION,
		"journal_id": String(data["journal_id"]),
		"sequence": int(data["sequence"]),
		"turns": int(data["turns"]),
		"phase": String(data["phase"]),
		"player_cell_id": String(data["player_cell_id"]),
		"health": int(data["health"]),
		"noise": int(data["noise"]),
		"peak_noise": int(data["peak_noise"]),
		"inventory": inventory,
		"cargo_value": int(data["cargo_value"]),
		"cargo_weight_grams": int(data["cargo_weight_grams"]),
		"taken_loot_ids": (data["taken_loot_ids"] as Array).duplicate(true),
		"neutralized_threat_ids": (data["neutralized_threat_ids"] as Array).duplicate(true),
		"revealed_building_ids": (data["revealed_building_ids"] as Array).duplicate(true),
		"destroyed_prop_ids": (data["destroyed_prop_ids"] as Array).duplicate(true),
		"threat_states": threat_states,
		"parent_runtime_receipt": String(data["parent_runtime_receipt"]),
		"runtime_receipt": String(data["runtime_receipt"]),
	}
	return normalized


static func _normalize_effect(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var data: Dictionary = value
	var required: Array = ["kind", "subject_id", "from_cell_id", "to_cell_id", "amount"]
	if not _exact_keys(data, required) or typeof(data.get("kind")) != TYPE_STRING \
			or String(data["kind"]) not in EFFECT_KINDS \
			or typeof(data.get("subject_id")) != TYPE_STRING \
			or typeof(data.get("from_cell_id")) != TYPE_STRING \
			or typeof(data.get("to_cell_id")) != TYPE_STRING \
			or not _bounded_int(data.get("amount"), 0, MAX_CARGO_VALUE):
		return {}
	return {
		"kind": String(data["kind"]),
		"subject_id": String(data["subject_id"]),
		"from_cell_id": String(data["from_cell_id"]),
		"to_cell_id": String(data["to_cell_id"]),
		"amount": int(data["amount"]),
	}


static func _effect(kind: String, subject_id: String, from_cell_id: String,
		to_cell_id: String, amount: int) -> Dictionary:
	return {
		"kind": kind, "subject_id": subject_id, "from_cell_id": from_cell_id,
		"to_cell_id": to_cell_id, "amount": amount,
	}


static func _empty_inventory() -> Array:
	var result: Array = []
	for kind in CARGO_KINDS:
		result.append({"kind": String(kind), "count": 0})
	return result


static func _normalize_inventory(value: Array) -> Array:
	if value.size() != CARGO_KINDS.size():
		return []
	var result: Array = []
	for index in CARGO_KINDS.size():
		if not (value[index] is Dictionary):
			return []
		var row: Dictionary = value[index]
		if not _exact_keys(row, ["kind", "count"]) \
				or row.get("kind") != CARGO_KINDS[index] \
				or not _bounded_int(row.get("count"), 0, MAX_ACTIONS):
			return []
		result.append({"kind": String(row["kind"]), "count": int(row["count"])})
	return result


static func _inventory_add(value: Array, kind: String, amount: int) -> Array:
	var normalized: Array = _normalize_inventory(value)
	if normalized.is_empty() or kind not in CARGO_KINDS:
		return []
	for index in normalized.size():
		var row: Dictionary = normalized[index]
		if String(row["kind"]) == kind:
			row["count"] = int(row["count"]) + amount
			normalized[index] = row
			break
	return normalized


static func _runtime_scars_empty(runtime: Dictionary) -> bool:
	for key in ["taken_loot_ids", "neutralized_threat_ids", "revealed_building_ids",
			"destroyed_prop_ids"]:
		if not (runtime[key] as Array).is_empty():
			return false
	return true


static func _entity_by_id(entities: Array, entity_id: String) -> Dictionary:
	for raw_entity in entities:
		var entity: Dictionary = raw_entity
		if String(entity.get("id", "")) == entity_id:
			return entity
	return {}


static func _threat_state_index(states: Array, threat_id: String) -> int:
	for index in states.size():
		var state: Dictionary = states[index]
		if String(state.get("id", "")) == threat_id:
			return index
	return -1


static func _other_live_threat_at(states: Array, self_index: int, cell_id: String) -> bool:
	for index in states.size():
		if index == self_index:
			continue
		var state: Dictionary = states[index]
		if int(state["hp"]) > 0 and String(state["cell_id"]) == cell_id:
			return true
	return false


static func _cardinal_neighbor(from_cell: String, to_cell: String) -> bool:
	return _cell_distance(from_cell, to_cell) == 1


static func _adjacent_or_same(from_cell: String, to_cell: String) -> bool:
	var distance: int = _cell_distance(from_cell, to_cell)
	return distance >= 0 and distance <= 1


static func _cell_distance(first: String, second: String) -> int:
	var first_address: Dictionary = ScaleAddress.parse_id(first)
	var second_address: Dictionary = ScaleAddress.parse_id(second)
	if first_address.is_empty() or second_address.is_empty() \
			or ScaleAddress.level_of(first_address) != ScaleAddress.LEVEL_CELL \
			or ScaleAddress.level_of(second_address) != ScaleAddress.LEVEL_CELL \
			or String(first_address.get("floor", "")) \
				!= String(second_address.get("floor", "")) \
			or ScaleAddress.canonical_id(ScaleAddress.parent(first_address)) \
				!= ScaleAddress.canonical_id(ScaleAddress.parent(second_address)):
		return -1
	var first_pos: Vector2i = ScaleAddress.coordinate(first_address, "cell")
	var second_pos: Vector2i = ScaleAddress.coordinate(second_address, "cell")
	return absi(first_pos.x - second_pos.x) + absi(first_pos.y - second_pos.y)


static func _cell_pos(cell_id: String) -> Vector2i:
	var address: Dictionary = ScaleAddress.parse_id(cell_id)
	return ScaleAddress.coordinate(address, "cell") if not address.is_empty() \
		else Vector2i(-999999, -999999)


static func _cell_id_at(blueprint: Dictionary, pos: Vector2i) -> String:
	if pos.x < 0 or pos.y < 0 or pos.x >= int(blueprint["width"]) \
			or pos.y >= int(blueprint["height"]):
		return ""
	var site_address: Dictionary = ScaleAddress.parse_id(String(blueprint["site_id"]))
	return ScaleAddress.canonical_id(ScaleAddress.with_cell(
		site_address, pos, SiteBlueprintModel.FLOOR_ID
	)) if not site_address.is_empty() else ""


static func _cell_id_valid_for_site(cell_id: String, site_id: String,
		width: int, height: int) -> bool:
	var address: Dictionary = ScaleAddress.parse_id(cell_id)
	if address.is_empty() or ScaleAddress.level_of(address) != ScaleAddress.LEVEL_CELL \
			or ScaleAddress.canonical_id(ScaleAddress.parent(address)) != site_id \
			or String(address.get("floor", "")) != SiteBlueprintModel.FLOOR_ID:
		return false
	var pos: Vector2i = ScaleAddress.coordinate(address, "cell")
	return pos.x >= 0 and pos.y >= 0 and pos.x < width and pos.y < height


static func _array_set(value: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_item in value:
		result[String(raw_item)] = true
	return result


static func _sorted_unique_strings(value: Array) -> bool:
	var previous := ""
	for index in value.size():
		if typeof(value[index]) != TYPE_STRING \
				or (index > 0 and String(value[index]) <= previous):
			return false
		previous = String(value[index])
	return true


static func _exact_string_payload(payload: Dictionary, key: String) -> bool:
	return _exact_keys(payload, [key]) and typeof(payload.get(key)) == TYPE_STRING \
		and String(payload[key]) != ""


static func _no_string_errors() -> Array[String]:
	var result: Array[String] = []
	return result


static func _exact_keys(data: Dictionary, required: Array) -> bool:
	if data.size() != required.size():
		return false
	for raw_key in data:
		if typeof(raw_key) != TYPE_STRING or String(raw_key) not in required:
			return false
	return true


static func _bounded_int(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		var integer: int = int(value)
		return integer >= minimum and integer <= maximum
	if typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number == floor(number) \
		and number >= float(minimum) and number <= float(maximum) \
		and absf(number) <= float(MAX_SAFE_JSON_INT)


static func _receipt_token_valid(value: String) -> bool:
	return value.begins_with("sha256:") and _lower_hex_valid(value.substr(7), 64)


static func _lower_hex_valid(value: String, width: int) -> bool:
	if value.length() != width:
		return false
	for index in value.length():
		var code: int = value.unicode_at(index)
		if not (code >= 48 and code <= 57 or code >= 97 and code <= 102):
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
	var encoded: String = _canonical_json(value)
	if encoded == "":
		return ""
	var digest: String = _sha256_hex(encoded)
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
