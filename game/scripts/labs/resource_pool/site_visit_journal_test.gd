extends Node

const Model = preload("res://scripts/labs/resource_pool/SiteVisitJournalModel.gd")
const Site = preload("res://scripts/labs/resource_pool/SiteBlueprintModel.gd")
const Routes = preload("res://scripts/labs/resource_pool/RegionRouteModel.gd")
const Address = preload("res://scripts/labs/resource_pool/ScaleAddress.gd")

const ROOT_SEED := 260814
const AMPLE_RESOURCE := 1000000
const SITE_KEYS := [
	"ash_market", "cinder_crossing", "orra_relay", "redglass_quarry",
	"saint_vey_clinic", "dunlin_homestead",
]
const WALK_STEPS: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP,
]
const SCAR_FIELDS := [
	"depleted_loot_ids", "neutralized_threat_ids", "revealed_building_ids",
	"destroyed_prop_ids",
]
const ZERO_RECEIPT := "sha256:0000000000000000000000000000000000000000000000000000000000000000"

var _fails: int = 0
var _checks: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	print("  %s %s%s" % [
		"PASS" if condition else "FAIL", label,
		("  " + detail if detail != "" else ""),
	])
	if not condition:
		_fails += 1


func _ready() -> void:
	print("=== RP-0005 trusted site visit journal contract ===")
	var atlas: Dictionary = Routes.make_atlas(ROOT_SEED)
	_check("source atlas validates", Routes.validate_atlas(atlas).is_empty())

	var promises: Dictionary = {}
	var blueprints: Dictionary = {}
	var all_compile: bool = true
	var all_revisit: bool = true
	var all_json_safe: bool = true
	var all_blueprints_immutable: bool = true
	for raw_key in SITE_KEYS:
		var site_key: String = String(raw_key)
		var promise: Dictionary = Site.make_site_promise(atlas, site_key)
		var blueprint: Dictionary = Site.compile_site(promise)
		promises[site_key] = promise
		blueprints[site_key] = blueprint
		var valid: bool = not promise.is_empty() and not blueprint.is_empty() \
			and Site.validate_site_promise(promise).is_empty() \
			and Site.validate_blueprint(promise, blueprint).is_empty()
		all_compile = all_compile and valid
		if not valid:
			continue
		var before_bytes: String = Site.canonical_json(blueprint)
		var idle: Dictionary = Site.make_initial_state(promise, blueprint)
		var idle_receipt: String = String(idle.get("state_receipt", ""))
		var revisit: Dictionary = Model.materialize_revisit(
			promise, blueprint, idle, idle_receipt
		)
		all_revisit = all_revisit \
			and Model.validate_revisit(
				promise, blueprint, idle, idle_receipt, revisit).is_empty() \
			and _revisit_partition_exact(blueprint, idle, revisit)
		all_json_safe = all_json_safe and _json_authority_safe(revisit)
		var mutated: Dictionary = revisit.duplicate(true)
		(mutated.get("cells", []) as Array)[0] = 999
		(mutated.get("props", []) as Array).clear()
		all_blueprints_immutable = all_blueprints_immutable \
			and Site.canonical_json(blueprint) == before_bytes \
			and not Model.validate_revisit(
				promise, blueprint, idle, idle_receipt, mutated).is_empty()
		print("REVISIT_FIXTURE=%s kind=%s loot=%d threats=%d props=%d reachable=%d" % [
			site_key, String(blueprint.get("site_kind", "")),
			(revisit.get("loot", []) as Array).size(),
			(revisit.get("threats", []) as Array).size(),
			(revisit.get("props", []) as Array).size(),
			int((revisit.get("navigation", {}) as Dictionary).get("reachable_cells", 0)),
		])
	_check("all six archetypes compile and validate", all_compile
		and promises.size() == 6 and blueprints.size() == 6)
	_check("all six revisit projections exactly partition authored entities", all_revisit)
	_check("all revisit authority is recursively JSON-native and integer-only", all_json_safe)
	_check("projection mutation never aliases or mutates immutable blueprints",
		all_blueprints_immutable)

	var cinder_promise: Dictionary = promises.get("cinder_crossing", {})
	var cinder_blueprint: Dictionary = blueprints.get("cinder_crossing", {})
	var ash_blueprint: Dictionary = blueprints.get("ash_market", {})
	var context: Dictionary = _make_visit_context(
		atlas, cinder_promise, cinder_blueprint,
		"ash_market", "cinder_crossing", "rp5-main", "visit-rp5-main"
	)
	_check("RP-0004 admission fixture validates and begins an exact journal",
		_context_valid(context))
	var base_journal: Dictionary = context.get("journal", {})
	var repeated_begin: Dictionary = Model.begin_journal(
		cinder_promise, cinder_blueprint, context.get("active_state", {}),
		String(context.get("active_state_receipt", ""))
	)
	_check("same accepted active checkpoint begins exact journal bytes",
		not base_journal.is_empty()
		and Model.canonical_json(base_journal) == Model.canonical_json(repeated_begin))
	_check("idle, wrong checkpoint, mixed blueprint, and self-rehashed candidate fail begin",
		_begin_authority_hostiles(context, ash_blueprint))

	_check("teleport, remote targets, invalid terminal, schema, and numeric intents fail closed",
		_intent_hostiles(context, ash_blueprint))
	_check("journal chain rejects stale checkpoints, mix, reorder, drop, and self-rehash",
		_journal_chain_hostiles(context))

	var legal: Dictionary = _run_legal_visit(context)
	_check("independent BFS walks through a canonical door and reveals its building",
		bool(legal.get("door_and_reveal_ok", false)))
	_check("adjacent loot, destroy, and runtime blocker removal are exact",
		bool(legal.get("loot_destroy_ok", false)))
	_check("threat ID order, independent tick oracle, combat, and auto collapse are exact",
		bool(legal.get("threat_oracle_ok", false)))
	_check("extraction terminal and collapsed branch derive exact cargo dispositions",
		bool(legal.get("terminals_ok", false)))

	var extracted_journal: Dictionary = legal.get("extracted_journal", {})
	var terminal: Dictionary = legal.get("terminal", {})
	var settlement: Dictionary = legal.get("settlement", {})
	_check("terminal settlement binds full journal and exact RP-0004 causality",
		_terminal_settlement_exact(context, extracted_journal, terminal, settlement))
	_check("terminal tamper, mix, replay, stale active, and stale journal checkpoints reject",
		_terminal_hostiles(context, legal))
	_check("JSON and Variant mid-visit continuation replay exact normalized output",
		_roundtrip_continuation_exact(context, legal))

	var revisit_result: Dictionary = _revisit_after_settlement(context, legal)
	_check("settled revisit has no loot, threat, or destroyed-blocker respawn",
		bool(revisit_result.get("partition_ok", false)))
	_check("checked structural walkability changes only after the blocker scar",
		bool(revisit_result.get("walkability_ok", false)))
	_check("second visit inherits scars and rejects depleted or neutralized targets",
		bool(revisit_result.get("second_visit_ok", false)))
	_check("revisit and second admission leave blueprint bytes unchanged",
		bool(revisit_result.get("blueprint_immutable", false)))

	var cap_result: Dictionary = _max_action_exhaustion(context)
	_check("MAX_ACTIONS ends in reducer-owned exhaustion collapse without active dead-end",
		bool(cap_result.get("ok", false)), String(cap_result.get("detail", "")))

	var terminal_receipt: String = String(terminal.get("terminal_receipt", ""))
	var revisit_receipt: String = String(
		(revisit_result.get("projection", {}) as Dictionary).get("projection_receipt", ""))
	print("SITE_VISIT_JOURNAL_RECEIPT=%s" % String(
		extracted_journal.get("journal_receipt", "")))
	print("SITE_VISIT_TERMINAL_RECEIPT=%s" % terminal_receipt)
	print("SITE_REVISIT_RECEIPT=%s" % revisit_receipt)
	print("site_visit_journal_test: %s (%d fail, %d checks)" % [
		"PASS" if _fails == 0 else "FAIL", _fails, _checks,
	])
	get_tree().quit(0 if _fails == 0 else 1)


func _make_visit_context(atlas: Dictionary, promise: Dictionary, blueprint: Dictionary,
		origin_key: String, destination_key: String, route_slot: String,
		visit_id: String, idle_override: Dictionary = {}) -> Dictionary:
	var idle_state: Dictionary = idle_override.duplicate(true) \
		if not idle_override.is_empty() else Site.make_initial_state(promise, blueprint)
	var idle_receipt: String = String(idle_state.get("state_receipt", ""))
	var route: Dictionary = _route_fixture(
		atlas, origin_key, destination_key, route_slot, true
	)
	if idle_state.is_empty() or route.is_empty():
		return {}
	var enter: Dictionary = Site.enter_site(
		promise, blueprint, idle_state, idle_receipt, atlas,
		route.get("atlas_state", {}), route.get("plan", {}),
		route.get("journey", {}), route.get("route_receipt", {}),
		String(route.get("accepted_journey_state_receipt", "")), visit_id
	)
	var active: Dictionary = enter.get("after_state", {})
	var active_receipt: String = String(active.get("state_receipt", ""))
	var journal: Dictionary = Model.begin_journal(
		promise, blueprint, active, active_receipt
	)
	return {
		"atlas": atlas, "promise": promise, "blueprint": blueprint,
		"idle_state": idle_state, "idle_state_receipt": idle_receipt,
		"route": route, "enter_transition": enter,
		"active_state": active, "active_state_receipt": active_receipt,
		"journal": journal,
	}


func _route_fixture(atlas: Dictionary, origin_key: String, destination_key: String,
		slot: String, complete: bool) -> Dictionary:
	var atlas_state: Dictionary = Routes.make_initial_atlas_state(atlas)
	var origin: String = Routes.site_tile_id(atlas, origin_key)
	var destination: String = Routes.site_tile_id(atlas, destination_key)
	var plan: Dictionary = Routes.make_route_plan(
		atlas, atlas_state, origin, destination, "autumn", "safe", [], "",
		"site_%s" % slot
	)
	var journey: Dictionary = Routes.begin_journey(
		atlas, atlas_state, plan, slot, AMPLE_RESOURCE, AMPLE_RESOURCE
	)
	if plan.is_empty() or journey.is_empty():
		return {}
	if complete:
		var guard: int = (plan.get("path", []) as Array).size() + 1
		for _step in guard:
			if String(journey.get("phase", "")) != "traveling":
				break
			var transition: Dictionary = Routes.advance_one_leg(
				atlas, atlas_state, plan, journey
			)
			if transition.is_empty():
				return {}
			journey = transition.get("journey", {})
			atlas_state = transition.get("atlas_state", {})
	var route_receipt: Dictionary = Routes.route_receipt(
		atlas, atlas_state, plan, journey
	)
	return {
		"atlas_state": atlas_state, "plan": plan, "journey": journey,
		"route_receipt": route_receipt,
		"accepted_journey_state_receipt": String(journey.get("state_receipt", "")),
	}


func _context_valid(context: Dictionary) -> bool:
	if context.is_empty():
		return false
	var promise: Dictionary = context.get("promise", {})
	var blueprint: Dictionary = context.get("blueprint", {})
	var active: Dictionary = context.get("active_state", {})
	var receipt: String = String(context.get("active_state_receipt", ""))
	var journal: Dictionary = context.get("journal", {})
	return not active.is_empty() and not journal.is_empty() \
		and Site.accept_state_checkpoint(promise, blueprint, active, receipt) == active \
		and Model.validate_journal(
			promise, blueprint, active, receipt, journal).is_empty() \
		and String((journal.get("current", {}) as Dictionary).get("phase", "")) == "active" \
		and int((journal.get("current", {}) as Dictionary).get("sequence", -1)) == 0


func _revisit_partition_exact(blueprint: Dictionary, idle_state: Dictionary,
		projection: Dictionary) -> bool:
	if projection.is_empty():
		return false
	if Model.canonical_json(projection.get("cells", [])) \
			!= Model.canonical_json(blueprint.get("cells", [])) \
			or Model.canonical_json(projection.get("entry", {})) \
			!= Model.canonical_json(blueprint.get("entry", {})) \
			or Model.canonical_json(projection.get("extraction", {})) \
			!= Model.canonical_json(blueprint.get("extraction", {})):
		return false
	var depleted: Dictionary = _string_set(idle_state.get("depleted_loot_ids", []))
	var neutralized: Dictionary = _string_set(idle_state.get("neutralized_threat_ids", []))
	var destroyed: Dictionary = _string_set(idle_state.get("destroyed_prop_ids", []))
	var revealed: Dictionary = _string_set(idle_state.get("revealed_building_ids", []))
	var remaining_loot: Dictionary = _entity_id_set(projection.get("loot", []))
	var remaining_threats: Dictionary = _entity_id_set(projection.get("threats", []))
	var remaining_props: Dictionary = _entity_id_set(projection.get("props", []))
	for raw_loot in blueprint.get("loot", []) as Array:
		var loot_id: String = String((raw_loot as Dictionary).get("id", ""))
		if remaining_loot.has(loot_id) == depleted.has(loot_id):
			return false
	for raw_threat in blueprint.get("threats", []) as Array:
		var threat_id: String = String((raw_threat as Dictionary).get("id", ""))
		if remaining_threats.has(threat_id) == neutralized.has(threat_id):
			return false
	for raw_prop in blueprint.get("props", []) as Array:
		var prop: Dictionary = raw_prop
		var prop_id: String = String(prop.get("id", ""))
		if bool(prop.get("destructible", false)):
			if remaining_props.has(prop_id) == destroyed.has(prop_id):
				return false
		elif not remaining_props.has(prop_id) or destroyed.has(prop_id):
			return false
	if (projection.get("buildings", []) as Array).size() \
			!= (blueprint.get("buildings", []) as Array).size():
		return false
	for raw_building in projection.get("buildings", []) as Array:
		var building: Dictionary = raw_building
		if bool(building.get("roof_revealed", false)) \
				!= revealed.has(String(building.get("id", ""))):
			return false
	var entry_cell: String = String(
		(blueprint.get("entry", {}) as Dictionary).get("cell_id", ""))
	return bool((projection.get("navigation", {}) as Dictionary).get(
		"extraction_reachable", false)) \
		and Model.revisit_is_walkable(
			{}, {}, {}, "", {}, "") == false \
		and entry_cell != ""


func _begin_authority_hostiles(context: Dictionary, other_blueprint: Dictionary) -> bool:
	var promise: Dictionary = context.get("promise", {})
	var blueprint: Dictionary = context.get("blueprint", {})
	var active: Dictionary = context.get("active_state", {})
	var active_receipt: String = String(context.get("active_state_receipt", ""))
	var idle: Dictionary = context.get("idle_state", {})
	var forged: Dictionary = active.duplicate(true)
	forged["active_arrival_receipt"] = ZERO_RECEIPT
	forged.erase("state_receipt")
	forged["state_receipt"] = _site_receipt_for(forged)
	return Model.begin_journal(promise, blueprint, idle,
		String(idle.get("state_receipt", ""))).is_empty() \
		and Model.begin_journal(promise, blueprint, active, ZERO_RECEIPT).is_empty() \
		and Model.begin_journal(promise, other_blueprint, active, active_receipt).is_empty() \
		and Site.validate_state_snapshot(promise, blueprint, forged).is_empty() \
		and Model.begin_journal(promise, blueprint, forged, active_receipt).is_empty()


func _intent_hostiles(context: Dictionary, other_blueprint: Dictionary) -> bool:
	var journal: Dictionary = context.get("journal", {})
	var blueprint: Dictionary = context.get("blueprint", {})
	var current: Dictionary = journal.get("current", {})
	var player_cell: String = String(current.get("player_cell_id", ""))
	var player_pos: Vector2i = _cell_pos(player_cell)
	var teleport_cell: String = _cell_id_at(blueprint, player_pos + Vector2i(2, 0))
	var diagonal_cell: String = _cell_id_at(blueprint, player_pos + Vector2i(1, 1))
	var other_site_cell: String = String(
		(other_blueprint.get("entry", {}) as Dictionary).get("cell_id", ""))
	var loot_id: String = _first_entity_id(blueprint, "loot")
	var threat_id: String = _first_entity_id(blueprint, "threats")
	var prop_id: String = _first_entity_id(blueprint, "props")
	var bad_kind: Dictionary = Model.make_intent(journal, "wait")
	bad_kind["kind"] = "collapse"
	var extra_field: Dictionary = Model.make_intent(journal, "wait")
	extra_field["damage"] = 99
	var fractional: Dictionary = Model.make_intent(journal, "wait")
	fractional["sequence"] = 0.5
	var huge: Dictionary = Model.make_intent(journal, "wait")
	huge["sequence"] = 1.0e100
	var nan_value: Dictionary = Model.make_intent(journal, "wait")
	nan_value["sequence"] = NAN
	var infinity: Dictionary = Model.make_intent(journal, "wait")
	infinity["sequence"] = INF
	var numeric_string: Dictionary = Model.make_intent(journal, "wait")
	numeric_string["sequence"] = "0"
	var abort_transition: Dictionary = _append(context, journal, "abort")
	var aborted: Dictionary = abort_transition.get("journal", {})
	return _append(context, journal, "move", teleport_cell).is_empty() \
		and _append(context, journal, "move", diagonal_cell).is_empty() \
		and _append(context, journal, "move", player_cell).is_empty() \
		and _append(context, journal, "move", other_site_cell).is_empty() \
		and _append(context, journal, "take_loot", loot_id).is_empty() \
		and _append(context, journal, "attack_threat", threat_id).is_empty() \
		and _append(context, journal, "destroy_prop", prop_id).is_empty() \
		and _append(context, journal, "extract").is_empty() \
		and _append_raw(context, journal, bad_kind).is_empty() \
		and _append_raw(context, journal, extra_field).is_empty() \
		and _append_raw(context, journal, fractional).is_empty() \
		and _append_raw(context, journal, huge).is_empty() \
		and _append_raw(context, journal, nan_value).is_empty() \
		and _append_raw(context, journal, infinity).is_empty() \
		and _append_raw(context, journal, numeric_string).is_empty() \
		and not abort_transition.is_empty() \
		and String((aborted.get("current", {}) as Dictionary).get("phase", "")) == "retreated" \
		and _append(context, aborted, "wait").is_empty()


func _journal_chain_hostiles(context: Dictionary) -> bool:
	var base: Dictionary = context.get("journal", {})
	var first_transition: Dictionary = _append(context, base, "wait")
	var first: Dictionary = first_transition.get("journal", {})
	var second_transition: Dictionary = _append(context, first, "wait")
	var second: Dictionary = second_transition.get("journal", {})
	if first.is_empty() or second.is_empty():
		return false
	var stale_candidate_current_anchor: Dictionary = _append_raw(
		context, base, Model.make_intent(base, "wait"),
		String(first.get("journal_receipt", "")))
	var current_candidate_stale_anchor: Dictionary = _append_raw(
		context, first, Model.make_intent(first, "wait"),
		String(base.get("journal_receipt", "")))
	var dropped: Dictionary = second.duplicate(true)
	(dropped["events"] as Array).pop_front()
	_rehash_journal_shell(dropped)
	var reordered: Dictionary = second.duplicate(true)
	var reordered_events: Array = reordered["events"]
	reordered_events.reverse()
	reordered["events"] = reordered_events
	_rehash_journal_shell(reordered)
	var duplicated: Dictionary = first.duplicate(true)
	(duplicated["events"] as Array).append(
		(duplicated["events"] as Array)[0].duplicate(true))
	_rehash_journal_shell(duplicated)
	var forged: Dictionary = first.duplicate(true)
	var forged_event: Dictionary = (forged["events"] as Array)[0]
	var forged_effects: Array = forged_event["effects"]
	(forged_effects[0] as Dictionary)["amount"] = 1
	forged_event["effects"] = forged_effects
	forged_event.erase("event_receipt")
	forged_event["event_receipt"] = _model_receipt_for(forged_event)
	forged["events"] = [forged_event]
	forged["head_event_receipt"] = String(forged_event["event_receipt"])
	_rehash_journal_shell(forged)
	var promise: Dictionary = context.get("promise", {})
	var blueprint: Dictionary = context.get("blueprint", {})
	var active: Dictionary = context.get("active_state", {})
	var active_receipt: String = String(context.get("active_state_receipt", ""))
	return stale_candidate_current_anchor.is_empty() \
		and current_candidate_stale_anchor.is_empty() \
		and Model.replay_journal(promise, blueprint, active, active_receipt, dropped).is_empty() \
		and Model.replay_journal(promise, blueprint, active, active_receipt, reordered).is_empty() \
		and Model.replay_journal(promise, blueprint, active, active_receipt, duplicated).is_empty() \
		and Model.replay_journal(promise, blueprint, active, active_receipt, forged).is_empty() \
		and Model.canonical_json(Model.replay_journal(
			promise, blueprint, active, active_receipt, second)) == Model.canonical_json(second)


func _append(context: Dictionary, journal: Dictionary, kind: String,
		target_id: String = "") -> Dictionary:
	var intent: Dictionary = Model.make_intent(journal, kind, target_id)
	return _append_raw(context, journal, intent)


func _append_raw(context: Dictionary, journal: Dictionary, intent: Dictionary,
		expected_receipt_override: String = "") -> Dictionary:
	var expected_receipt: String = expected_receipt_override \
		if expected_receipt_override != "" else String(journal.get("journal_receipt", ""))
	return Model.append_action(
		context.get("promise", {}), context.get("blueprint", {}),
		context.get("active_state", {}), String(context.get("active_state_receipt", "")),
		journal, expected_receipt, intent
	)


func _run_legal_visit(context: Dictionary) -> Dictionary:
	var blueprint: Dictionary = context.get("blueprint", {})
	var journal: Dictionary = context.get("journal", {})
	var blueprint_before: String = Site.canonical_json(blueprint)
	var loot: Dictionary = _first_entity(blueprint, "loot")
	var prop: Dictionary = _first_destructible_blocker(blueprint)
	var nondestructible: Dictionary = _first_nondestructible_prop(blueprint)
	var threat_id: String = _first_entity_id(blueprint, "threats")
	if loot.is_empty() or prop.is_empty() or threat_id == "":
		return {}
	var door_cells: Dictionary = _door_cell_set(blueprint)
	var door_crossed: bool = false
	var path: Array[String] = _path_to_target(
		blueprint, journal.get("start", {}), journal.get("current", {}),
		String(loot.get("cell_id", "")), true
	)
	if path.is_empty():
		return {}
	for cell_id in path:
		var transition: Dictionary = _append(context, journal, "move", cell_id)
		if transition.is_empty():
			return {}
		journal = transition.get("journal", {})
		door_crossed = door_crossed or door_cells.has(cell_id)
	var current: Dictionary = journal.get("current", {})
	var revealed_after_entry: bool = not (current.get("revealed_building_ids", []) as Array).is_empty()
	var take_transition: Dictionary = _append(
		context, journal, "take_loot", String(loot["id"])
	)
	if take_transition.is_empty():
		return {}
	journal = take_transition.get("journal", {})
	var duplicate_loot_rejected: bool = _append(
		context, journal, "take_loot", String(loot["id"])).is_empty()

	path = _path_to_target(
		blueprint, journal.get("start", {}), journal.get("current", {}),
		String(prop.get("cell_id", "")), true
	)
	for cell_id in path:
		var transition: Dictionary = _append(context, journal, "move", cell_id)
		if transition.is_empty():
			return {}
		journal = transition.get("journal", {})
	var blocked_before_destroy: bool = not _oracle_structural_walkable(
		blueprint, journal.get("start", {}), journal.get("current", {}),
		String(prop["cell_id"]), true
	)
	var destroy_transition: Dictionary = _append(
		context, journal, "destroy_prop", String(prop["id"])
	)
	if destroy_transition.is_empty():
		return {}
	journal = destroy_transition.get("journal", {})
	var duplicate_prop_rejected: bool = _append(
		context, journal, "destroy_prop", String(prop["id"])).is_empty()
	var walk_destroyed_transition: Dictionary = _append(
		context, journal, "move", String(prop["cell_id"])
	)
	var runtime_unblocked: bool = not walk_destroyed_transition.is_empty()
	if runtime_unblocked:
		journal = walk_destroyed_transition.get("journal", {})

	var approach_guard: int = 96
	while approach_guard > 0 and String(
		(journal.get("current", {}) as Dictionary).get("phase", "")) == "active":
		approach_guard -= 1
		current = journal.get("current", {})
		var threat_state: Dictionary = _runtime_threat(current, threat_id)
		if threat_state.is_empty() or int(threat_state.get("hp", 0)) <= 0:
			break
		if _cell_distance(String(current["player_cell_id"]),
				String(threat_state["cell_id"])) <= 1:
			break
		path = _path_to_target(
			blueprint, journal.get("start", {}), current,
			String(threat_state["cell_id"]), true
		)
		if path.is_empty():
			return {}
		var step_transition: Dictionary = _append(context, journal, "move", path[0])
		if step_transition.is_empty():
			return {}
		journal = step_transition.get("journal", {})
	var combat_ready: Dictionary = journal.duplicate(true)
	current = combat_ready.get("current", {})
	var ready_threat: Dictionary = _runtime_threat(current, threat_id)
	var adjacent_ready: bool = not ready_threat.is_empty() \
		and _cell_distance(String(current.get("player_cell_id", "")),
			String(ready_threat.get("cell_id", ""))) <= 1

	var collapse_branch: Dictionary = _collapse_branch_with_oracle(context, combat_ready)
	var oracle_ok: bool = adjacent_ready and bool(collapse_branch.get("oracle_ok", false))
	var collapse_journal: Dictionary = collapse_branch.get("journal", {})
	var collapse_terminal: Dictionary = collapse_branch.get("terminal", {})

	var attacks: int = 0
	while attacks < 8:
		current = journal.get("current", {})
		var threat_state: Dictionary = _runtime_threat(current, threat_id)
		if threat_state.is_empty() or int(threat_state.get("hp", 0)) <= 0:
			break
		if _cell_distance(String(current["player_cell_id"]),
				String(threat_state["cell_id"])) > 1:
			return {}
		var attack_transition: Dictionary = _append(
			context, journal, "attack_threat", threat_id
		)
		if attack_transition.is_empty():
			return {}
		journal = attack_transition.get("journal", {})
		attacks += 1
	var killed: bool = threat_id in (
		(journal.get("current", {}) as Dictionary).get("neutralized_threat_ids", []) as Array)
	var dead_rekill_rejected: bool = _append(
		context, journal, "attack_threat", threat_id).is_empty()

	var nondestructible_rejected: bool = true
	if not nondestructible.is_empty():
		path = _path_to_target(
			blueprint, journal.get("start", {}), journal.get("current", {}),
			String(nondestructible.get("cell_id", "")), true
		)
		for cell_id in path:
			var transition: Dictionary = _append(context, journal, "move", cell_id)
			if transition.is_empty():
				return {}
			journal = transition.get("journal", {})
		nondestructible_rejected = _append(
			context, journal, "destroy_prop", String(nondestructible["id"])).is_empty()

	var extraction_cell: String = String(
		(blueprint.get("extraction", {}) as Dictionary).get("cell_id", ""))
	path = _path_to_target(
		blueprint, journal.get("start", {}), journal.get("current", {}),
		extraction_cell, false
	)
	for cell_id in path:
		var transition: Dictionary = _append(context, journal, "move", cell_id)
		if transition.is_empty():
			return {}
		journal = transition.get("journal", {})
	var turns_before_extract: int = int(
		(journal.get("current", {}) as Dictionary).get("turns", -1))
	var extract_transition: Dictionary = _append(context, journal, "extract")
	if extract_transition.is_empty():
		return {}
	var extracted: Dictionary = extract_transition.get("journal", {})
	var extracted_current: Dictionary = extracted.get("current", {})
	var terminal: Dictionary = _finalize(context, extracted)
	var settlement: Dictionary = _settle(context, extracted)
	var collapse_disposition_ok: bool = not collapse_terminal.is_empty() \
		and String(collapse_terminal.get("cargo_disposition", "")) == "lost" \
		and String(collapse_terminal.get("resolution", "")) == "collapsed" \
		and String(collapse_terminal.get("journal_receipt", "")) \
			== String(collapse_journal.get("journal_receipt", ""))
	return {
		"door_and_reveal_ok": door_crossed and revealed_after_entry,
		"loot_destroy_ok": duplicate_loot_rejected and blocked_before_destroy \
			and duplicate_prop_rejected and runtime_unblocked and nondestructible_rejected,
		"threat_oracle_ok": oracle_ok and killed and dead_rekill_rejected \
			and attacks == int(_entity_by_id(
				blueprint.get("threats", []), threat_id).get("hp", -1)),
		"terminals_ok": not terminal.is_empty() and not settlement.is_empty() \
			and String(terminal.get("resolution", "")) == "extracted" \
			and String(terminal.get("cargo_disposition", "")) == "banked" \
			and int(extracted_current.get("turns", -1)) == turns_before_extract \
			and collapse_disposition_ok \
			and Site.canonical_json(blueprint) == blueprint_before,
		"mid_journal": combat_ready,
		"extracted_journal": extracted,
		"terminal": terminal,
		"settlement": settlement,
		"collapse_journal": collapse_journal,
		"collapse_terminal": collapse_terminal,
		"loot_id": String(loot["id"]), "threat_id": threat_id,
		"prop_id": String(prop["id"]), "prop_cell_id": String(prop["cell_id"]),
	}


func _collapse_branch_with_oracle(context: Dictionary,
		combat_ready: Dictionary) -> Dictionary:
	var journal: Dictionary = combat_ready.duplicate(true)
	var oracle_ok: bool = true
	var guard: int = 32
	while guard > 0 and String(
		(journal.get("current", {}) as Dictionary).get("phase", "")) == "active":
		guard -= 1
		var before: Dictionary = journal.get("current", {})
		var oracle: Dictionary = _oracle_wait(
			context.get("blueprint", {}), journal.get("start", {}), before
		)
		var transition: Dictionary = _append(context, journal, "wait")
		if oracle.is_empty() or transition.is_empty():
			return {"oracle_ok": false}
		var event: Dictionary = transition.get("event", {})
		var after: Dictionary = (transition.get("journal", {}) as Dictionary).get("current", {})
		oracle_ok = oracle_ok \
			and Model.canonical_json(oracle.get("runtime", {})) == Model.canonical_json(after) \
			and Model.canonical_json(oracle.get("effects", [])) \
				== Model.canonical_json(event.get("effects", []))
		journal = transition.get("journal", {})
	var terminal: Dictionary = _finalize(context, journal)
	return {
		"oracle_ok": oracle_ok and guard > 0 \
			and String((journal.get("current", {}) as Dictionary).get("phase", "")) == "collapsed",
		"journal": journal, "terminal": terminal,
	}


func _finalize(context: Dictionary, journal: Dictionary) -> Dictionary:
	return Model.finalize_terminal(
		context.get("promise", {}), context.get("blueprint", {}),
		context.get("active_state", {}), String(context.get("active_state_receipt", "")),
		journal, String(journal.get("journal_receipt", ""))
	)


func _settle(context: Dictionary, journal: Dictionary) -> Dictionary:
	var route: Dictionary = context.get("route", {})
	return Model.derive_site_settlement(
		context.get("promise", {}), context.get("blueprint", {}),
		context.get("active_state", {}), String(context.get("active_state_receipt", "")),
		journal, String(journal.get("journal_receipt", "")),
		context.get("enter_transition", {}), String(context.get("idle_state_receipt", "")),
		context.get("atlas", {}), route.get("atlas_state", {}), route.get("plan", {}),
		route.get("journey", {}), route.get("route_receipt", {}),
		String(route.get("accepted_journey_state_receipt", ""))
	)


func _path_to_target(blueprint: Dictionary, start: Dictionary, runtime: Dictionary,
		target_cell: String, adjacent: bool) -> Array[String]:
	var origin: String = String(runtime.get("player_cell_id", ""))
	if origin == "" or target_cell == "":
		return []
	if (adjacent and _cell_distance(origin, target_cell) <= 1) \
			or (not adjacent and origin == target_cell):
		return []
	var queue: Array[String] = [origin]
	var parents: Dictionary = {origin: ""}
	var head: int = 0
	var found: String = ""
	while head < queue.size():
		var current: String = queue[head]
		head += 1
		var pos: Vector2i = _cell_pos(current)
		for step in WALK_STEPS:
			var next_cell: String = _cell_id_at(blueprint, pos + step)
			if next_cell == "" or parents.has(next_cell) \
					or not _oracle_structural_walkable(
						blueprint, start, runtime, next_cell, false):
				continue
			parents[next_cell] = current
			queue.append(next_cell)
			if (adjacent and _cell_distance(next_cell, target_cell) <= 1) \
					or (not adjacent and next_cell == target_cell):
				found = next_cell
				break
		if found != "":
			break
	if found == "":
		return []
	var reversed: Array[String] = []
	var cursor: String = found
	while cursor != origin and cursor != "":
		reversed.append(cursor)
		cursor = String(parents.get(cursor, ""))
	reversed.reverse()
	return reversed


func _oracle_structural_walkable(blueprint: Dictionary, start: Dictionary,
		runtime: Dictionary, cell_id: String, ignore_threats: bool) -> bool:
	if not _cell_valid_for_blueprint(blueprint, cell_id):
		return false
	var pos: Vector2i = _cell_pos(cell_id)
	if Site.cell_at(blueprint, pos) not in Site.WALKABLE_CELLS:
		return false
	for raw_prop in blueprint.get("props", []) as Array:
		var prop: Dictionary = raw_prop
		if bool(prop.get("blocking", false)) \
				and String(prop.get("cell_id", "")) == cell_id \
				and String(prop.get("id", "")) \
					not in (start.get("baseline_destroyed_prop_ids", []) as Array) \
				and String(prop.get("id", "")) \
					not in (runtime.get("destroyed_prop_ids", []) as Array):
			return false
	if not ignore_threats:
		for raw_state in runtime.get("threat_states", []) as Array:
			var state: Dictionary = raw_state
			if int(state.get("hp", 0)) > 0 \
					and String(state.get("cell_id", "")) == cell_id:
				return false
	return true


func _oracle_wait(blueprint: Dictionary, start: Dictionary,
		before: Dictionary) -> Dictionary:
	if String(before.get("phase", "")) != "active" \
			or int(before.get("sequence", -1)) >= Model.MAX_ACTIONS:
		return {}
	var after: Dictionary = before.duplicate(true)
	var effects: Array = [_effect("wait", "player", "", "", 0)]
	after["turns"] = int(before["turns"]) + 1
	after["noise"] = clampi(int(before["noise"]) - 1, 0, 10)
	after["peak_noise"] = maxi(int(before["peak_noise"]), int(after["noise"]))
	var states: Array = (after.get("threat_states", []) as Array).duplicate(true)
	for index in states.size():
		var state: Dictionary = states[index]
		if int(state.get("hp", 0)) <= 0:
			continue
		var threat: Dictionary = _entity_by_id(
			blueprint.get("threats", []), String(state.get("id", "")))
		if threat.is_empty():
			return {}
		var player_cell: String = String(after["player_cell_id"])
		var distance: int = _cell_distance(String(state["cell_id"]), player_cell)
		if not bool(state["alerted"]) \
				and distance <= int(threat["alert_radius"]) + int(after["noise"]):
			state["alerted"] = true
			effects.append(_effect("alert_threat", String(state["id"]), "", "", 0))
		if bool(state["alerted"]) and int(after["turns"]) % 2 == 0:
			var from_cell: String = String(state["cell_id"])
			var next_cell: String = _oracle_threat_step(
				blueprint, start, after, states, index, from_cell, player_cell
			)
			if next_cell != "" and next_cell != from_cell:
				state["cell_id"] = next_cell
				effects.append(_effect(
					"move_threat", String(state["id"]), from_cell, next_cell, 0))
		states[index] = state
		distance = _cell_distance(String(state["cell_id"]), player_cell)
		if distance <= 1 and bool(state["alerted"]):
			var applied_damage: int = mini(Model.CONTACT_DAMAGE, int(after["health"]))
			after["health"] = int(after["health"]) - applied_damage
			effects.append(_effect(
				"damage_player", String(state["id"]), "", "", applied_damage))
			if int(after["health"]) <= 0:
				after["phase"] = "collapsed"
				effects.append(_effect("terminal", "collapsed", "", "", 0))
				break
	after["threat_states"] = states
	if String(after["phase"]) == "active" \
			and int(before["sequence"]) + 1 >= Model.MAX_ACTIONS:
		var remaining_health: int = int(after["health"])
		after["health"] = 0
		after["phase"] = "collapsed"
		effects.append(_effect("exhaustion", "player", "", "", remaining_health))
		effects.append(_effect("terminal", "collapsed", "", "", 0))
	if String(after["phase"]) == "active":
		effects.append_array(_oracle_reveal(blueprint, start, after))
	after["sequence"] = int(before["sequence"]) + 1
	after["parent_runtime_receipt"] = String(before["runtime_receipt"])
	after.erase("runtime_receipt")
	after["runtime_receipt"] = _model_receipt_for(after)
	return {"runtime": after, "effects": effects}


func _oracle_threat_step(blueprint: Dictionary, start: Dictionary,
		runtime: Dictionary, states: Array, self_index: int,
		from_cell: String, player_cell: String) -> String:
	var from_pos: Vector2i = _cell_pos(from_cell)
	var player_pos: Vector2i = _cell_pos(player_cell)
	var dx: int = signi(player_pos.x - from_pos.x)
	var dy: int = signi(player_pos.y - from_pos.y)
	var steps: Array[Vector2i] = []
	if absi(player_pos.x - from_pos.x) >= absi(player_pos.y - from_pos.y):
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
		var candidate: String = _cell_id_at(blueprint, from_pos + step)
		if candidate == "" or candidate == player_cell \
				or not _oracle_structural_walkable(
					blueprint, start, runtime, candidate, true):
			continue
		var occupied: bool = false
		for index in states.size():
			if index == self_index:
				continue
			var other: Dictionary = states[index]
			if int(other.get("hp", 0)) > 0 \
					and String(other.get("cell_id", "")) == candidate:
				occupied = true
				break
		if not occupied:
			return candidate
	return from_cell


func _oracle_reveal(blueprint: Dictionary, start: Dictionary,
		runtime: Dictionary) -> Array:
	var effects: Array = []
	var pos: Vector2i = _cell_pos(String(runtime["player_cell_id"]))
	for raw_building in blueprint.get("buildings", []) as Array:
		var building: Dictionary = raw_building
		var rect: Array = building.get("rect", [])
		var inside: bool = pos.x > int(rect[0]) and pos.y > int(rect[1]) \
			and pos.x < int(rect[0]) + int(rect[2]) - 1 \
			and pos.y < int(rect[1]) + int(rect[3]) - 1
		var building_id: String = String(building.get("id", ""))
		if inside and building_id \
				not in (start.get("baseline_revealed_building_ids", []) as Array) \
				and building_id not in (runtime.get("revealed_building_ids", []) as Array):
			var revealed: Array = (runtime["revealed_building_ids"] as Array).duplicate(true)
			revealed.append(building_id)
			revealed.sort()
			runtime["revealed_building_ids"] = revealed
			effects.append(_effect("reveal_building", building_id, "", "", 0))
			break
	return effects


func _effect(kind: String, subject_id: String, from_cell: String,
		to_cell: String, amount: int) -> Dictionary:
	return {
		"kind": kind, "subject_id": subject_id,
		"from_cell_id": from_cell, "to_cell_id": to_cell, "amount": amount,
	}


func _terminal_settlement_exact(context: Dictionary, journal: Dictionary,
		terminal: Dictionary, settlement: Dictionary) -> bool:
	if journal.is_empty() or terminal.is_empty() or settlement.is_empty():
		return false
	var route: Dictionary = context.get("route", {})
	return Model.validate_terminal(
		context.get("promise", {}), context.get("blueprint", {}),
		context.get("active_state", {}), String(context.get("active_state_receipt", "")),
		journal, String(journal.get("journal_receipt", "")), terminal).is_empty() \
		and Model.validate_site_settlement(
			context.get("promise", {}), context.get("blueprint", {}),
			context.get("active_state", {}), String(context.get("active_state_receipt", "")),
			journal, String(journal.get("journal_receipt", "")),
			context.get("enter_transition", {}), String(context.get("idle_state_receipt", "")),
			context.get("atlas", {}), route.get("atlas_state", {}), route.get("plan", {}),
			route.get("journey", {}), route.get("route_receipt", {}),
			String(route.get("accepted_journey_state_receipt", "")), settlement).is_empty() \
		and String(settlement.get("terminal_receipt", "")) \
			== String(terminal.get("terminal_receipt", "")) \
		and String((settlement.get("site_transition", {}) as Dictionary).get(
			"after_state_receipt", "")) == String(settlement.get("idle_site_state_receipt", ""))


func _terminal_hostiles(context: Dictionary, legal: Dictionary) -> bool:
	var journal: Dictionary = legal.get("extracted_journal", {})
	var terminal: Dictionary = legal.get("terminal", {})
	var settlement: Dictionary = legal.get("settlement", {})
	var nonterminal: Dictionary = legal.get("mid_journal", {})
	if journal.is_empty() or terminal.is_empty() or settlement.is_empty() \
			or nonterminal.is_empty():
		return false
	var tampered: Dictionary = terminal.duplicate(true)
	tampered["elapsed_turns"] = int(tampered.get("elapsed_turns", 0)) + 1
	tampered.erase("terminal_receipt")
	tampered["terminal_receipt"] = _model_receipt_for(tampered)
	var stale_active_context: Dictionary = context.duplicate(true)
	stale_active_context["active_state"] = (
		settlement.get("site_transition", {}) as Dictionary).get("after_state", {})
	stale_active_context["active_state_receipt"] = String(
		(stale_active_context["active_state"] as Dictionary).get("state_receipt", ""))
	var route: Dictionary = context.get("route", {})
	var wrong_enter: Dictionary = context.get("enter_transition", {}).duplicate(true)
	wrong_enter["visit_id"] = "visit-mixed"
	wrong_enter.erase("transition_receipt")
	wrong_enter["transition_receipt"] = _site_receipt_for(wrong_enter)
	var mixed_settlement: Dictionary = Model.derive_site_settlement(
		context.get("promise", {}), context.get("blueprint", {}),
		context.get("active_state", {}), String(context.get("active_state_receipt", "")),
		journal, String(journal.get("journal_receipt", "")), wrong_enter,
		String(context.get("idle_state_receipt", "")), context.get("atlas", {}),
		route.get("atlas_state", {}), route.get("plan", {}), route.get("journey", {}),
		route.get("route_receipt", {}),
		String(route.get("accepted_journey_state_receipt", ""))
	)
	return _finalize(context, nonterminal).is_empty() \
		and Model.finalize_terminal(
			context.get("promise", {}), context.get("blueprint", {}),
			context.get("active_state", {}), String(context.get("active_state_receipt", "")),
			journal, ZERO_RECEIPT).is_empty() \
		and not Model.validate_terminal(
			context.get("promise", {}), context.get("blueprint", {}),
			context.get("active_state", {}), String(context.get("active_state_receipt", "")),
			journal, String(journal.get("journal_receipt", "")), tampered).is_empty() \
		and _append(context, journal, "wait").is_empty() \
		and mixed_settlement.is_empty() \
		and _settle(stale_active_context, journal).is_empty() \
		and Model.canonical_json(_settle(context, journal)) == Model.canonical_json(settlement)


func _roundtrip_continuation_exact(context: Dictionary, legal: Dictionary) -> bool:
	var journal: Dictionary = legal.get("mid_journal", {})
	if journal.is_empty() or String(
		(journal.get("current", {}) as Dictionary).get("phase", "")) != "active":
		return false
	var original_transition: Dictionary = _append(context, journal, "wait")
	var promise_json: Variant = JSON.parse_string(JSON.stringify(context.get("promise", {})))
	var blueprint_json: Variant = JSON.parse_string(JSON.stringify(context.get("blueprint", {})))
	var active_json: Variant = JSON.parse_string(JSON.stringify(context.get("active_state", {})))
	var journal_json: Variant = JSON.parse_string(JSON.stringify(journal))
	var promise_binary: Variant = bytes_to_var(var_to_bytes(context.get("promise", {})))
	var blueprint_binary: Variant = bytes_to_var(var_to_bytes(context.get("blueprint", {})))
	var active_binary: Variant = bytes_to_var(var_to_bytes(context.get("active_state", {})))
	var journal_binary: Variant = bytes_to_var(var_to_bytes(journal))
	if not (promise_json is Dictionary) or not (blueprint_json is Dictionary) \
			or not (active_json is Dictionary) or not (journal_json is Dictionary) \
			or not (promise_binary is Dictionary) or not (blueprint_binary is Dictionary) \
			or not (active_binary is Dictionary) or not (journal_binary is Dictionary):
		return false
	var json_context: Dictionary = context.duplicate(true)
	json_context["promise"] = promise_json
	json_context["blueprint"] = blueprint_json
	json_context["active_state"] = active_json
	var binary_context: Dictionary = context.duplicate(true)
	binary_context["promise"] = promise_binary
	binary_context["blueprint"] = blueprint_binary
	binary_context["active_state"] = active_binary
	var json_transition: Dictionary = _append(
		json_context, journal_json as Dictionary, "wait")
	var binary_transition: Dictionary = _append(
		binary_context, journal_binary as Dictionary, "wait")
	return not original_transition.is_empty() and not json_transition.is_empty() \
		and not binary_transition.is_empty() \
		and Model.canonical_json(original_transition) == Model.canonical_json(json_transition) \
		and Model.canonical_json(original_transition) == Model.canonical_json(binary_transition) \
		and _json_authority_safe(json_transition) and _json_authority_safe(binary_transition)


func _revisit_after_settlement(context: Dictionary, legal: Dictionary) -> Dictionary:
	var settlement: Dictionary = legal.get("settlement", {})
	var transition: Dictionary = settlement.get("site_transition", {})
	var idle_after: Dictionary = transition.get("after_state", {})
	var idle_receipt: String = String(idle_after.get("state_receipt", ""))
	var promise: Dictionary = context.get("promise", {})
	var blueprint: Dictionary = context.get("blueprint", {})
	var blueprint_before: String = Site.canonical_json(blueprint)
	var projection_before: Dictionary = Model.materialize_revisit(
		promise, blueprint, context.get("idle_state", {}),
		String(context.get("idle_state_receipt", ""))
	)
	var projection: Dictionary = Model.materialize_revisit(
		promise, blueprint, idle_after, idle_receipt
	)
	var prop_cell: String = String(legal.get("prop_cell_id", ""))
	var before_walkable: bool = Model.revisit_is_walkable(
		promise, blueprint, context.get("idle_state", {}),
		String(context.get("idle_state_receipt", "")), projection_before, prop_cell
	)
	var after_walkable: bool = Model.revisit_is_walkable(
		promise, blueprint, idle_after, idle_receipt, projection, prop_cell
	)
	var partition_ok: bool = _revisit_partition_exact(blueprint, idle_after, projection) \
		and not _entity_id_set(projection.get("loot", [])).has(String(legal.get("loot_id", ""))) \
		and not _entity_id_set(projection.get("threats", [])).has(String(legal.get("threat_id", ""))) \
		and not _entity_id_set(projection.get("props", [])).has(String(legal.get("prop_id", "")))

	var second_context: Dictionary = _make_visit_context(
		context.get("atlas", {}), promise, blueprint,
		"ash_market", "cinder_crossing", "rp5-second", "visit-rp5-second", idle_after
	)
	var second_journal: Dictionary = second_context.get("journal", {})
	var second_current: Dictionary = second_journal.get("current", {})
	var second_start: Dictionary = second_journal.get("start", {})
	var second_visit_ok: bool = _context_valid(second_context) \
		and String(legal.get("loot_id", "")) \
			in (second_start.get("baseline_depleted_loot_ids", []) as Array) \
		and String(legal.get("threat_id", "")) \
			in (second_start.get("baseline_neutralized_threat_ids", []) as Array) \
		and _runtime_threat(second_current, String(legal.get("threat_id", ""))).is_empty() \
		and _append(second_context, second_journal, "take_loot",
			String(legal.get("loot_id", ""))).is_empty() \
		and _append(second_context, second_journal, "attack_threat",
			String(legal.get("threat_id", ""))).is_empty() \
		and _append(second_context, second_journal, "destroy_prop",
			String(legal.get("prop_id", ""))).is_empty()
	var tampered: Dictionary = projection.duplicate(true)
	(tampered.get("loot", []) as Array).append(
		_entity_by_id(blueprint.get("loot", []), String(legal.get("loot_id", ""))))
	tampered.erase("projection_receipt")
	tampered["projection_receipt"] = _model_receipt_for(tampered)
	return {
		"partition_ok": partition_ok \
			and not Model.validate_revisit(
				promise, blueprint, idle_after, idle_receipt, tampered).is_empty(),
		"walkability_ok": not before_walkable and after_walkable,
		"second_visit_ok": second_visit_ok,
		"blueprint_immutable": Site.canonical_json(blueprint) == blueprint_before,
		"projection": projection,
	}


func _max_action_exhaustion(context: Dictionary) -> Dictionary:
	var blueprint: Dictionary = context.get("blueprint", {})
	var all_threat_ids: Array = []
	for raw_threat in blueprint.get("threats", []) as Array:
		all_threat_ids.append(String((raw_threat as Dictionary).get("id", "")))
	all_threat_ids.sort()
	var route: Dictionary = context.get("route", {})
	var baseline_delta: Dictionary = Site.make_visit_delta(
		context.get("promise", {}), blueprint, context.get("active_state", {}),
		context.get("enter_transition", {}), String(context.get("idle_state_receipt", "")),
		context.get("atlas", {}), route.get("atlas_state", {}), route.get("plan", {}),
		route.get("journey", {}), route.get("route_receipt", {}),
		String(route.get("accepted_journey_state_receipt", "")), "visit-rp5-main",
		"extracted", 1, [], all_threat_ids, [], []
	)
	var baseline_transition: Dictionary = Site.apply_visit_delta(
		context.get("promise", {}), blueprint, context.get("active_state", {}),
		context.get("enter_transition", {}), String(context.get("idle_state_receipt", "")),
		context.get("atlas", {}), route.get("atlas_state", {}), route.get("plan", {}),
		route.get("journey", {}), route.get("route_receipt", {}),
		String(route.get("accepted_journey_state_receipt", "")), baseline_delta
	)
	var scarred_idle: Dictionary = baseline_transition.get("after_state", {})
	var cap_context: Dictionary = _make_visit_context(
		context.get("atlas", {}), context.get("promise", {}), blueprint,
		"ash_market", "cinder_crossing", "rp5-cap", "visit-rp5-cap", scarred_idle
	)
	if not _context_valid(cap_context):
		return {"ok": false, "detail": "cap fixture invalid"}
	var initial_journal: Dictionary = cap_context.get("journal", {})
	var start: Dictionary = (initial_journal.get("start", {}) as Dictionary).duplicate(true)
	var current: Dictionary = (initial_journal.get("current", {}) as Dictionary).duplicate(true)
	var events: Array = []
	var previous_event_receipt: String = ""
	var before_last_active: bool = false
	for index in Model.MAX_ACTIONS:
		if index == Model.MAX_ACTIONS - 1:
			before_last_active = String(current.get("phase", "")) == "active" \
				and int(current.get("sequence", -1)) == Model.MAX_ACTIONS - 1
		var intent: Dictionary = Model.make_intent(
			{"start": start, "current": current}, "wait"
		)
		var oracle: Dictionary = _oracle_wait(blueprint, start, current)
		if intent.is_empty() or oracle.is_empty():
			return {"ok": false, "detail": "linear oracle failed at %d" % index}
		var next_runtime: Dictionary = oracle.get("runtime", {})
		var event: Dictionary = {
			"schema": Model.EVENT_SCHEMA,
			"rules_revision": Model.RULES_REVISION,
			"journal_id": String(start.get("journal_id", "")),
			"sequence": index,
			"previous_event_receipt": previous_event_receipt,
			"before_runtime_receipt": String(current.get("runtime_receipt", "")),
			"intent": intent,
			"turn_delta": 1,
			"loudness": 0,
			"effects": (oracle.get("effects", []) as Array).duplicate(true),
			"after_runtime_receipt": String(next_runtime.get("runtime_receipt", "")),
		}
		event["event_receipt"] = _model_receipt_for(event)
		if String(event["event_receipt"]) == "":
			return {"ok": false, "detail": "event receipt failed at %d" % index}
		events.append(event)
		previous_event_receipt = String(event["event_receipt"])
		current = next_runtime
	var journal: Dictionary = {
		"schema": Model.JOURNAL_SCHEMA,
		"start": start,
		"events": events,
		"current": current,
		"head_event_receipt": previous_event_receipt,
	}
	journal["journal_receipt"] = _model_receipt_for(journal)
	var replayed: Dictionary = Model.replay_journal(
		cap_context.get("promise", {}), blueprint,
		cap_context.get("active_state", {}),
		String(cap_context.get("active_state_receipt", "")), journal
	)
	var last_event: Dictionary = events[-1] if not events.is_empty() else {}
	var effect_kinds: Array[String] = []
	for raw_effect in last_event.get("effects", []) as Array:
		effect_kinds.append(String((raw_effect as Dictionary).get("kind", "")))
	var terminal: Dictionary = _finalize(cap_context, replayed)
	var ok: bool = not replayed.is_empty() \
		and Model.canonical_json(replayed) == Model.canonical_json(journal) \
		and before_last_active \
		and int(current.get("sequence", -1)) == Model.MAX_ACTIONS \
		and int(current.get("turns", -1)) == Model.MAX_ACTIONS \
		and String(current.get("phase", "")) == "collapsed" \
		and int(current.get("health", -1)) == 0 \
		and "exhaustion" in effect_kinds and "terminal" in effect_kinds \
		and _append(cap_context, replayed, "extract").is_empty() \
		and _append(cap_context, replayed, "wait").is_empty() \
		and not terminal.is_empty()
	return {"ok": ok, "detail": "sequence=%d phase=%s" % [
		int(current.get("sequence", -1)), String(current.get("phase", "")),
	]}


func _first_entity(blueprint: Dictionary, section: String) -> Dictionary:
	var entities: Array = blueprint.get(section, [])
	return (entities[0] as Dictionary) if not entities.is_empty() else {}


func _first_entity_id(blueprint: Dictionary, section: String) -> String:
	return String(_first_entity(blueprint, section).get("id", ""))


func _first_destructible_blocker(blueprint: Dictionary) -> Dictionary:
	for raw_prop in blueprint.get("props", []) as Array:
		var prop: Dictionary = raw_prop
		if bool(prop.get("destructible", false)) and bool(prop.get("blocking", false)):
			return prop
	return {}


func _first_nondestructible_prop(blueprint: Dictionary) -> Dictionary:
	for raw_prop in blueprint.get("props", []) as Array:
		var prop: Dictionary = raw_prop
		if not bool(prop.get("destructible", false)):
			return prop
	return {}


func _entity_by_id(entities_value: Variant, entity_id: String) -> Dictionary:
	if not (entities_value is Array):
		return {}
	for raw_entity in entities_value as Array:
		var entity: Dictionary = raw_entity
		if String(entity.get("id", "")) == entity_id:
			return entity
	return {}


func _runtime_threat(runtime: Dictionary, threat_id: String) -> Dictionary:
	return _entity_by_id(runtime.get("threat_states", []), threat_id)


func _door_cell_set(blueprint: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw_building in blueprint.get("buildings", []) as Array:
		for raw_door in (raw_building as Dictionary).get("doors", []) as Array:
			result[String((raw_door as Dictionary).get("cell_id", ""))] = true
	return result


func _entity_id_set(entities_value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if entities_value is Array:
		for raw_entity in entities_value as Array:
			if raw_entity is Dictionary:
				result[String((raw_entity as Dictionary).get("id", ""))] = true
	return result


func _string_set(values_value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if values_value is Array:
		for raw_value in values_value as Array:
			result[String(raw_value)] = true
	return result


func _cell_id_at(blueprint: Dictionary, pos: Vector2i) -> String:
	if pos.x < 0 or pos.y < 0 or pos.x >= int(blueprint.get("width", 0)) \
			or pos.y >= int(blueprint.get("height", 0)):
		return ""
	var site_address: Dictionary = Address.parse_id(String(blueprint.get("site_id", "")))
	return Address.canonical_id(Address.with_cell(
		site_address, pos, Site.FLOOR_ID
	)) if not site_address.is_empty() else ""


func _cell_pos(cell_id: String) -> Vector2i:
	var address: Dictionary = Address.parse_id(cell_id)
	return Address.coordinate(address, "cell") if not address.is_empty() \
		else Vector2i(-999999, -999999)


func _cell_distance(first: String, second: String) -> int:
	var left: Dictionary = Address.parse_id(first)
	var right: Dictionary = Address.parse_id(second)
	if left.is_empty() or right.is_empty() \
			or Address.level_of(left) != Address.LEVEL_CELL \
			or Address.level_of(right) != Address.LEVEL_CELL \
			or Address.canonical_id(Address.parent(left)) \
				!= Address.canonical_id(Address.parent(right)):
		return -1
	var left_pos: Vector2i = Address.coordinate(left, "cell")
	var right_pos: Vector2i = Address.coordinate(right, "cell")
	return absi(left_pos.x - right_pos.x) + absi(left_pos.y - right_pos.y)


func _cell_valid_for_blueprint(blueprint: Dictionary, cell_id: String) -> bool:
	var address: Dictionary = Address.parse_id(cell_id)
	if address.is_empty() or Address.level_of(address) != Address.LEVEL_CELL \
			or Address.canonical_id(Address.parent(address)) \
				!= String(blueprint.get("site_id", "")) \
			or String(address.get("floor", "")) != Site.FLOOR_ID:
		return false
	var pos: Vector2i = Address.coordinate(address, "cell")
	return pos.x >= 0 and pos.y >= 0 and pos.x < int(blueprint.get("width", 0)) \
		and pos.y < int(blueprint.get("height", 0))


func _rehash_journal_shell(journal: Dictionary) -> void:
	journal.erase("journal_receipt")
	journal["journal_receipt"] = _model_receipt_for(journal)


func _site_receipt_for(value: Variant) -> String:
	return _receipt_from_encoded(Site.canonical_json(value))


func _model_receipt_for(value: Variant) -> String:
	return _receipt_from_encoded(Model.canonical_json(value))


func _receipt_from_encoded(encoded: String) -> String:
	if encoded == "":
		return ""
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK \
			or context.update(encoded.to_utf8_buffer()) != OK:
		return ""
	return "sha256:" + context.finish().hex_encode()


func _json_authority_safe(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
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
