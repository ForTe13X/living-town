extends Node2D

const ScaleAddress = preload("res://scripts/labs/resource_pool/ScaleAddress.gd")
const RegionRouteModel = preload("res://scripts/labs/resource_pool/RegionRouteModel.gd")
const SiteBlueprintModel = preload("res://scripts/labs/resource_pool/SiteBlueprintModel.gd")
const SiteVisitJournalModel = preload("res://scripts/labs/resource_pool/SiteVisitJournalModel.gd")

const DESIGN := Vector2(1280.0, 768.0)
const HEADER_RECT := Rect2(0.0, 0.0, 1280.0, 72.0)
const MAP_PANEL := Rect2(24.0, 170.0, 824.0, 512.0)
const SIDE_PANEL := Rect2(864.0, 170.0, 392.0, 512.0)
const GRID_RECT := Rect2(100.0, 209.0, 672.0, 462.0)
const CELL_SIZE := 21.0

const STAGE_FRESH := 1
const STAGE_JOURNAL := 2
const STAGE_SCARS := 3
const STAGE_REVISIT := 4

const C_BG := Color("#11140f")
const C_HEADER := Color("#171a14")
const C_PANEL := Color("#1c1e19")
const C_PANEL_2 := Color("#24251f")
const C_CARD := Color("#181a16")
const C_CARD_HI := Color("#22241e")
const C_EDGE := Color("#565846")
const C_EDGE_HI := Color("#89866d")
const C_TEXT := Color("#ded8c4")
const C_MUTED := Color("#929382")
const C_GOLD := Color("#d2a85c")
const C_TEAL := Color("#78a999")
const C_GOOD := Color("#8fb56d")
const C_DANGER := Color("#c45b50")
const C_DIRT := Color("#35372d")
const C_ROAD := Color("#756549")
const C_FLOOR := Color("#59564a")
const C_WALL := Color("#33342d")
const C_WINDOW := Color("#6a9991")
const C_TREE := Color("#496348")
const C_RUBBLE := Color("#6d6558")
const C_WATER := Color("#355b5b")
const C_FENCE := Color("#77735e")
const C_CROP := Color("#687341")
const C_PIT := Color("#292521")

const FIXTURE_SITE_KEYS := [
	"ash_market",
	"saint_vey_clinic",
	"orra_relay",
	"redglass_quarry",
	"dunlin_homestead",
	"cinder_crossing",
]
const FIXTURE_KINDS := ["ruins", "clinic", "relay", "quarry", "farm", "haven"]
const FIXTURE_LABELS := [
	"A  RUINS", "B  CLINIC", "C  RELAY", "D  QUARRY", "E  FARM", "F  HAVEN",
]
const DEFAULT_STAGES := [STAGE_FRESH, STAGE_JOURNAL, STAGE_SCARS,
	STAGE_REVISIT, STAGE_REVISIT, STAGE_SCARS]
const STAGE_TITLES := ["FRESH BLUEPRINT", "TYPED JOURNAL", "DURABLE SCARS", "REVISIT PROJECTION"]
const STAGE_SUBTITLES := ["immutable promise", "intent -> effects", "terminal -> idle", "no respawn read"]
const KIND_TITLES := {
	"ruins": "RUINED MARKET BLOCK",
	"clinic": "FIELD CLINIC CAMPUS",
	"relay": "ORRA RELAY COMPOUND",
	"quarry": "REDGLASS QUARRY WORKS",
	"farm": "DUNLIN HOMESTEAD",
	"haven": "CROSSING HAVEN",
}
const RETURN_READS := {
	"ruins": "RETURN FOR THE FAR STOREFRONTS",
	"clinic": "RETURN IF MEDS OUTWEIGH CONTACT",
	"relay": "SKIP UNTIL A QUIETER APPROACH",
	"quarry": "RETURN THROUGH THE OPENED CHOKE",
	"farm": "RETURN FOR THE LONG YARD CIRCUIT",
	"haven": "SKIP: ABORT LEFT THE SITE UNCHANGED",
}

var _font: Font
var _atlas: Dictionary = {}
var _atlas_state: Dictionary = {}
var _promise: Dictionary = {}
var _blueprint: Dictionary = {}
var _fresh_state: Dictionary = {}
var _fresh_projection: Dictionary = {}
var _arrival_plan: Dictionary = {}
var _arrival_journey: Dictionary = {}
var _arrival_receipt: Dictionary = {}
var _enter_transition: Dictionary = {}
var _active_state: Dictionary = {}
var _journal: Dictionary = {}
var _journal_prefixes: Array[Dictionary] = []
var _journal_events: Array[Dictionary] = []
var _terminal: Dictionary = {}
var _settlement: Dictionary = {}
var _scarred_state: Dictionary = {}
var _projection: Dictionary = {}
var _opened_prop_cells: Array[String] = []
var _focus_step := 0
var _fixture_index := 0
var _stage := STAGE_FRESH
var _journal_step := 0
var _shot_path := ""
var _load_ok := false
var _mouse := Vector2(-1000.0, -1000.0)
var _fixture_rects: Array[Rect2] = []
var _stage_rects: Array[Rect2] = []


func _ready() -> void:
	_font = ThemeDB.fallback_font
	var requested_fixture := 0
	var requested_stage := 0
	var requested_step := -1
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		var argument := String(args[index])
		if argument == "--revisit-fixture" and index + 1 < args.size():
			index += 1
			requested_fixture = _fixture_from_argument(String(args[index]))
		elif argument.begins_with("--revisit-fixture="):
			requested_fixture = _fixture_from_argument(argument.trim_prefix("--revisit-fixture="))
		elif argument == "--revisit-stage" and index + 1 < args.size():
			index += 1
			requested_stage = _stage_from_argument(String(args[index]))
		elif argument.begins_with("--revisit-stage="):
			requested_stage = _stage_from_argument(argument.trim_prefix("--revisit-stage="))
		elif argument == "--revisit-step" and index + 1 < args.size():
			index += 1
			requested_step = maxi(-1, String(args[index]).to_int())
		elif argument.begins_with("--revisit-step="):
			requested_step = maxi(-1, argument.trim_prefix("--revisit-step=").to_int())
		elif argument == "--lab-shot" and index + 1 < args.size():
			index += 1
			_shot_path = String(args[index])
		elif argument.begins_with("--lab-shot="):
			_shot_path = argument.trim_prefix("--lab-shot=")
		index += 1
	_load_ok = _apply_fixture(requested_fixture, requested_stage, requested_step)
	set_process(true)
	queue_redraw()
	if _shot_path != "":
		if not _load_ok:
			get_tree().quit(1)
			return
		get_tree().create_timer(0.8).timeout.connect(_save_shot)


func _process(_delta: float) -> void:
	if _shot_path == "":
		queue_redraw()


func _fixture_from_argument(value: String) -> int:
	match value.strip_edges().to_lower():
		"a", "1", "ruins", "ash_market", "ash-market":
			return 0
		"b", "2", "clinic", "saint_vey_clinic", "saint-vey-clinic":
			return 1
		"c", "3", "relay", "orra_relay", "orra-relay":
			return 2
		"d", "4", "quarry", "redglass_quarry", "redglass-quarry":
			return 3
		"e", "5", "farm", "dunlin_homestead", "dunlin-homestead":
			return 4
		"f", "6", "haven", "cinder_crossing", "cinder-crossing":
			return 5
	return 0


func _stage_from_argument(value: String) -> int:
	match value.strip_edges().to_lower():
		"1", "fresh", "blueprint":
			return STAGE_FRESH
		"2", "journal", "visit":
			return STAGE_JOURNAL
		"3", "scars", "scarred", "settlement":
			return STAGE_SCARS
		"4", "revisit", "projection":
			return STAGE_REVISIT
	return 0


func _apply_fixture(index: int, requested_stage: int = 0, requested_step: int = -1) -> bool:
	_fixture_index = clampi(index, 0, FIXTURE_SITE_KEYS.size() - 1)
	_stage = requested_stage if requested_stage in [STAGE_FRESH, STAGE_JOURNAL,
		STAGE_SCARS, STAGE_REVISIT] else int(DEFAULT_STAGES[_fixture_index])
	if not _build_fixture_chain():
		return false
	var default_step := _focus_step if _focus_step > 0 else mini(1, _journal_prefixes.size() - 1)
	_journal_step = clampi(requested_step if requested_step >= 0 else default_step,
		0, maxi(0, _journal_prefixes.size() - 1))
	queue_redraw()
	return true


func _build_fixture_chain() -> bool:
	_journal_prefixes.clear()
	_journal_events.clear()
	_opened_prop_cells.clear()
	_focus_step = 0
	_atlas = RegionRouteModel.make_atlas(RegionRouteModel.DEFAULT_ROOT_SEED)
	_atlas_state = RegionRouteModel.make_initial_atlas_state(_atlas)
	_promise = SiteBlueprintModel.make_site_promise(_atlas, String(FIXTURE_SITE_KEYS[_fixture_index]))
	_blueprint = SiteBlueprintModel.compile_site(_promise)
	_fresh_state = SiteBlueprintModel.make_initial_state(_promise, _blueprint)
	if _atlas.is_empty() or _atlas_state.is_empty() or _promise.is_empty() \
			or _blueprint.is_empty() or _fresh_state.is_empty():
		push_error("ScarredRevisitLab could not compile fixture %s" % String(FIXTURE_LABELS[_fixture_index]))
		return false
	_fresh_projection = SiteVisitJournalModel.materialize_revisit(
		_promise, _blueprint, _fresh_state, String(_fresh_state.get("state_receipt", ""))
	)
	var tile_id := RegionRouteModel.site_tile_id(_atlas, String(FIXTURE_SITE_KEYS[_fixture_index]))
	_arrival_plan = RegionRouteModel.make_route_plan(
		_atlas, _atlas_state, tile_id, tile_id, "autumn", "safe", [], "", "revisit_lab_arrival"
	)
	_arrival_journey = RegionRouteModel.begin_journey(
		_atlas, _atlas_state, _arrival_plan, "revisit_lab_slot", 8500, 92000
	)
	_arrival_receipt = RegionRouteModel.route_receipt(
		_atlas, _atlas_state, _arrival_plan, _arrival_journey
	)
	_enter_transition = SiteBlueprintModel.enter_site(
		_promise, _blueprint, _fresh_state, String(_fresh_state.get("state_receipt", "")),
		_atlas, _atlas_state, _arrival_plan, _arrival_journey, _arrival_receipt,
		String(_arrival_journey.get("state_receipt", "")), "revisit_lab_visit"
	)
	_active_state = _enter_transition.get("after_state", {}) as Dictionary
	if _fresh_projection.is_empty() or _arrival_plan.is_empty() or _arrival_journey.is_empty() \
			or _arrival_receipt.is_empty() or _enter_transition.is_empty() or _active_state.is_empty():
		push_error("ScarredRevisitLab could not produce arrived admission evidence")
		return false
	_journal = SiteVisitJournalModel.begin_journal(
		_promise, _blueprint, _active_state, String(_active_state.get("state_receipt", ""))
	)
	if _journal.is_empty():
		push_error("ScarredRevisitLab could not begin the trusted journal")
		return false
	_journal_prefixes.append(_journal.duplicate(true))
	if _fixture_index == 5:
		if not _append_intent("abort"):
			push_error("ScarredRevisitLab could not produce the sequence-0 abort control")
			return false
	else:
		_run_real_visit()
	if _current_phase() == "active":
		if not _extract_visit():
			_force_collapse()
	if _current_phase() == "active":
		push_error("ScarredRevisitLab fixture did not reach a reducer-owned terminal")
		return false
	_terminal = SiteVisitJournalModel.finalize_terminal(
		_promise, _blueprint, _active_state, String(_active_state.get("state_receipt", "")),
		_journal, String(_journal.get("journal_receipt", ""))
	)
	_settlement = SiteVisitJournalModel.derive_site_settlement(
		_promise, _blueprint, _active_state, String(_active_state.get("state_receipt", "")),
		_journal, String(_journal.get("journal_receipt", "")), _enter_transition,
		String(_fresh_state.get("state_receipt", "")), _atlas, _atlas_state,
		_arrival_plan, _arrival_journey, _arrival_receipt,
		String(_arrival_journey.get("state_receipt", ""))
	)
	var site_transition: Dictionary = _settlement.get("site_transition", {}) as Dictionary
	_scarred_state = site_transition.get("after_state", {}) as Dictionary
	_projection = SiteVisitJournalModel.materialize_revisit(
		_promise, _blueprint, _scarred_state, String(_scarred_state.get("state_receipt", ""))
	)
	if _terminal.is_empty() or _settlement.is_empty() or _scarred_state.is_empty() \
			or _projection.is_empty():
		push_error("ScarredRevisitLab could not derive terminal, settlement, and revisit")
		return false
	if not SiteVisitJournalModel.validate_revisit(
		_promise, _blueprint, _scarred_state,
		String(_scarred_state.get("state_receipt", "")), _projection
	).is_empty():
		push_error("ScarredRevisitLab revisit failed exact recomputation")
		return false
	_collect_opened_prop_cells()
	_focus_step = _preferred_focus_step()
	return true


func _run_real_visit() -> void:
	# Each deterministic fixture proves one product claim with the shortest legal
	# journal that carries it. This keeps exact replay affordable after authority
	# caches were removed from the model.
	match _fixture_index:
		0:
			# Fresh-baseline screenshot; the committed chain is a clean extraction.
			return
		1:
			# The nearest clinic loot is inside a roof: movement reveals, then take scars it.
			var clinic_loot := _nearest_available_blueprint_entity(
				_blueprint.get("loot", []) as Array, "taken_loot_ids", false
			)
			if not clinic_loot.is_empty():
				_act_on_entity("take_loot", clinic_loot)
		2:
			# One interior relay take produces loot + roof memory before contact collapses.
			var relay_loot := _nearest_available_blueprint_entity(
				_blueprint.get("loot", []) as Array, "taken_loot_ids", false
			)
			if not relay_loot.is_empty():
				_act_on_entity("take_loot", relay_loot)
			if _current_phase() == "active":
				_force_collapse()
		3:
			# A destroyed blocking prop is enough to prove changed revisit traversal.
			var quarry_prop := _nearest_destructible_prop()
			if not quarry_prop.is_empty():
				_act_on_entity("destroy_prop", quarry_prop)
		4:
			# One farm take leaves a visibly meaningful remainder for return/skip.
			var farm_loot := _nearest_available_blueprint_entity(
				_blueprint.get("loot", []) as Array, "taken_loot_ids", false
			)
			if not farm_loot.is_empty():
				_act_on_entity("take_loot", farm_loot)


func _reveal_nearest_building() -> bool:
	var goals: Array[String] = []
	for raw_building in _blueprint.get("buildings", []) as Array:
		var building: Dictionary = raw_building as Dictionary
		var values: Array = building.get("rect", []) as Array
		if values.size() != 4:
			continue
		for y in range(int(values[1]) + 1, int(values[1]) + int(values[3]) - 1):
			for x in range(int(values[0]) + 1, int(values[0]) + int(values[2]) - 1):
				var pos := Vector2i(x, y)
				if SiteBlueprintModel.cell_at(_blueprint, pos) in SiteBlueprintModel.WALKABLE_CELLS:
					goals.append(_cell_id_at(pos))
	if goals.is_empty():
		return false
	return _navigate_to_any(goals, 96)


func _act_on_entity(kind: String, entity: Dictionary) -> bool:
	var target_cell := String(entity.get("cell_id", ""))
	var target_id := String(entity.get("id", ""))
	if target_cell == "" or target_id == "":
		return false
	if not _approach_cell(target_cell, "", 96):
		return false
	return _append_intent(kind, target_id)


func _neutralize_threat(threat_id: String) -> bool:
	var guard := 0
	while _current_phase() == "active" and _threat_is_live(threat_id) and guard < 96:
		guard += 1
		var threat_state := _live_threat_state(threat_id)
		if threat_state.is_empty():
			return true
		var player_cell := String(_current_runtime().get("player_cell_id", ""))
		var threat_cell := String(threat_state.get("cell_id", ""))
		if _cell_distance(player_cell, threat_cell) <= 1:
			if not _append_intent("attack_threat", threat_id):
				return false
			continue
		var adjacent: Dictionary = _adjacent_live_threat("")
		if not adjacent.is_empty() and String(adjacent.get("id", "")) != threat_id:
			if not _attack_adjacent_threat(String(adjacent.get("id", ""))):
				return false
			continue
		var goals := _adjacent_cell_ids(threat_cell)
		var path := _path_to_any(goals)
		if path.size() < 2 or not _append_intent("move", String(path[1])):
			return false
	return not _threat_is_live(threat_id)


func _attack_adjacent_threat(threat_id: String) -> bool:
	var guard := 0
	while _current_phase() == "active" and _threat_is_live(threat_id) and guard < 16:
		guard += 1
		var state := _live_threat_state(threat_id)
		if state.is_empty() or _cell_distance(
			String(_current_runtime().get("player_cell_id", "")), String(state.get("cell_id", ""))
		) > 1:
			return false
		if not _append_intent("attack_threat", threat_id):
			return false
	return not _threat_is_live(threat_id)


func _approach_cell(target_cell: String, kept_threat_id: String, max_actions: int) -> bool:
	var guard := 0
	while _current_phase() == "active" and guard < max_actions:
		guard += 1
		var player_cell := String(_current_runtime().get("player_cell_id", ""))
		if _cell_distance(player_cell, target_cell) <= 1:
			return true
		var adjacent := _adjacent_live_threat(kept_threat_id)
		if not adjacent.is_empty():
			if not _attack_adjacent_threat(String(adjacent.get("id", ""))):
				return false
			continue
		var path := _path_to_any(_adjacent_cell_ids(target_cell))
		if path.size() < 2:
			return false
		if not _append_intent("move", String(path[1])):
			return false
	return false


func _navigate_to_any(goal_cells: Array[String], max_actions: int) -> bool:
	var guard := 0
	var goal_set := _id_set(goal_cells)
	while _current_phase() == "active" and guard < max_actions:
		guard += 1
		var player_cell := String(_current_runtime().get("player_cell_id", ""))
		if goal_set.has(player_cell):
			return true
		var adjacent := _adjacent_live_threat("")
		if not adjacent.is_empty():
			if not _attack_adjacent_threat(String(adjacent.get("id", ""))):
				return false
			continue
		var path := _path_to_any(goal_cells)
		if path.size() < 2:
			var nearest := _nearest_live_threat()
			if nearest.is_empty() or not _neutralize_threat(String(nearest.get("id", ""))):
				return false
			continue
		if not _append_intent("move", String(path[1])):
			return false
	return false


func _extract_visit() -> bool:
	if _current_phase() != "active":
		return true
	var extraction: Dictionary = _blueprint.get("extraction", {}) as Dictionary
	var extraction_cell := String(extraction.get("cell_id", ""))
	if extraction_cell == "" or not _navigate_to_any([extraction_cell], 128):
		return false
	return _append_intent("extract")


func _force_collapse() -> void:
	if _current_phase() != "active":
		return
	var target := _nearest_live_threat()
	if not target.is_empty():
		var target_id := String(target.get("id", ""))
		var target_state := _live_threat_state(target_id)
		if not target_state.is_empty():
			_approach_cell(String(target_state.get("cell_id", "")), target_id, 96)
		var waits := 0
		while _current_phase() == "active" and waits < 24:
			waits += 1
			if not _append_intent("wait"):
				break
	if _current_phase() == "active":
		_extract_visit()


func _append_intent(kind: String, target_id: String = "") -> bool:
	if _current_phase() != "active":
		return false
	var intent: Dictionary = SiteVisitJournalModel.make_intent(_journal, kind, target_id)
	if intent.is_empty():
		return false
	var transition: Dictionary = SiteVisitJournalModel.append_action(
		_promise, _blueprint, _active_state, String(_active_state.get("state_receipt", "")),
		_journal, String(_journal.get("journal_receipt", "")), intent
	)
	if transition.is_empty():
		return false
	var event: Dictionary = transition.get("event", {}) as Dictionary
	_journal = transition.get("journal", {}) as Dictionary
	if event.is_empty() or _journal.is_empty():
		return false
	_journal_events.append(event.duplicate(true))
	_journal_prefixes.append(_journal.duplicate(true))
	print_verbose("ScarredRevisitLab %s action %d %s" % [
		String(FIXTURE_LABELS[_fixture_index]), _journal_events.size(), kind,
	])
	if _focus_step == 0:
		for raw_effect in event.get("effects", []) as Array:
			var effect: Dictionary = raw_effect as Dictionary
			if String(effect.get("kind", "")) in [
				"take_loot", "neutralize_threat", "destroy_prop", "reveal_building",
			]:
				_focus_step = _journal_prefixes.size() - 1
				break
	return true


func _path_to_any(goal_cells: Array[String]) -> Array[String]:
	var empty: Array[String] = []
	var runtime := _current_runtime()
	var start_cell := String(runtime.get("player_cell_id", ""))
	if start_cell == "" or goal_cells.is_empty():
		return empty
	var goals := _id_set(goal_cells)
	var reached := {start_cell: true}
	var parent: Dictionary = {}
	var queue: Array[String] = [start_cell]
	var head := 0
	var found := ""
	while head < queue.size():
		var current := String(queue[head])
		head += 1
		if goals.has(current):
			found = current
			break
		var pos := _cell_pos(current)
		for step in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var next_cell := _cell_id_at(pos + step)
			if next_cell != "" and not reached.has(next_cell) and _runtime_cell_walkable(next_cell):
				reached[next_cell] = true
				parent[next_cell] = current
				queue.append(next_cell)
	if found == "":
		return empty
	var reverse_path: Array[String] = [found]
	while String(reverse_path[reverse_path.size() - 1]) != start_cell:
		var child := String(reverse_path[reverse_path.size() - 1])
		if not parent.has(child):
			return empty
		reverse_path.append(String(parent[child]))
	reverse_path.reverse()
	return reverse_path


func _runtime_cell_walkable(cell_id: String) -> bool:
	var pos := _cell_pos(cell_id)
	if pos.x < 0 or pos.y < 0 or pos.x >= int(_blueprint.get("width", 0)) \
			or pos.y >= int(_blueprint.get("height", 0)):
		return false
	if SiteBlueprintModel.cell_at(_blueprint, pos) not in SiteBlueprintModel.WALKABLE_CELLS:
		return false
	var runtime := _current_runtime()
	var destroyed := _id_set(runtime.get("destroyed_prop_ids", []) as Array)
	for raw_prop in _blueprint.get("props", []) as Array:
		var prop: Dictionary = raw_prop as Dictionary
		if bool(prop.get("blocking", false)) and not destroyed.has(String(prop.get("id", ""))) \
				and String(prop.get("cell_id", "")) == cell_id:
			return false
	for raw_state in runtime.get("threat_states", []) as Array:
		var state: Dictionary = raw_state as Dictionary
		if int(state.get("hp", 0)) > 0 and String(state.get("cell_id", "")) == cell_id:
			return false
	return true


func _current_runtime() -> Dictionary:
	return _journal.get("current", {}) as Dictionary


func _current_phase() -> String:
	return String(_current_runtime().get("phase", ""))


func _live_threat_state(threat_id: String) -> Dictionary:
	for raw_state in _current_runtime().get("threat_states", []) as Array:
		var state: Dictionary = raw_state as Dictionary
		if String(state.get("id", "")) == threat_id and int(state.get("hp", 0)) > 0:
			return state
	return {}


func _threat_is_live(threat_id: String) -> bool:
	return not _live_threat_state(threat_id).is_empty()


func _adjacent_live_threat(excluded_id: String) -> Dictionary:
	var player_cell := String(_current_runtime().get("player_cell_id", ""))
	var candidates: Array[Dictionary] = []
	for raw_state in _current_runtime().get("threat_states", []) as Array:
		var state: Dictionary = raw_state as Dictionary
		if int(state.get("hp", 0)) > 0 and String(state.get("id", "")) != excluded_id \
				and _cell_distance(player_cell, String(state.get("cell_id", ""))) <= 1:
			candidates.append(state)
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("id", "")) < String(right.get("id", ""))
	)
	return candidates[0] if not candidates.is_empty() else {}


func _nearest_live_threat() -> Dictionary:
	var player_cell := String(_current_runtime().get("player_cell_id", ""))
	var best: Dictionary = {}
	var best_distance := 1000000
	for raw_state in _current_runtime().get("threat_states", []) as Array:
		var state: Dictionary = raw_state as Dictionary
		if int(state.get("hp", 0)) <= 0:
			continue
		var distance := _cell_distance(player_cell, String(state.get("cell_id", "")))
		if distance < best_distance or (distance == best_distance and String(state.get("id", "")) < String(best.get("id", "~"))):
			best = state
			best_distance = distance
	return best


func _nearest_available_blueprint_entity(entities: Array, scar_field: String,
		destructible_only: bool) -> Dictionary:
	var scarred := _id_set(_current_runtime().get(scar_field, []) as Array)
	var player_cell := String(_current_runtime().get("player_cell_id", ""))
	var best: Dictionary = {}
	var best_distance := 1000000
	for raw_entity in entities:
		var entity: Dictionary = raw_entity as Dictionary
		if scarred.has(String(entity.get("id", ""))) \
				or (destructible_only and not bool(entity.get("destructible", false))):
			continue
		var distance := _cell_distance(player_cell, String(entity.get("cell_id", "")))
		if distance < best_distance or (distance == best_distance and String(entity.get("id", "")) < String(best.get("id", "~"))):
			best = entity
			best_distance = distance
	return best


func _nearest_destructible_prop() -> Dictionary:
	return _nearest_available_blueprint_entity(
		_blueprint.get("props", []) as Array, "destroyed_prop_ids", true
	)


func _adjacent_cell_ids(cell_id: String) -> Array[String]:
	var result: Array[String] = []
	var pos := _cell_pos(cell_id)
	for step in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		var candidate := _cell_id_at(pos + step)
		if candidate != "":
			result.append(candidate)
	return result


func _cell_id_at(pos: Vector2i) -> String:
	if pos.x < 0 or pos.y < 0 or pos.x >= int(_blueprint.get("width", 0)) \
			or pos.y >= int(_blueprint.get("height", 0)):
		return ""
	var site_address: Dictionary = ScaleAddress.parse_id(String(_blueprint.get("site_id", "")))
	return ScaleAddress.canonical_id(ScaleAddress.with_cell(site_address, pos, SiteBlueprintModel.FLOOR_ID))


func _cell_pos(cell_id: String) -> Vector2i:
	var address: Dictionary = ScaleAddress.parse_id(cell_id)
	return ScaleAddress.coordinate(address, "cell") if not address.is_empty() else Vector2i(-9999, -9999)


func _cell_distance(first: String, second: String) -> int:
	var first_pos := _cell_pos(first)
	var second_pos := _cell_pos(second)
	if first_pos.x < 0 or second_pos.x < 0:
		return 1000000
	return absi(first_pos.x - second_pos.x) + absi(first_pos.y - second_pos.y)


func _collect_opened_prop_cells() -> void:
	_opened_prop_cells.clear()
	var destroyed := _id_set(_terminal.get("destroyed_prop_ids", []) as Array)
	for raw_prop in _blueprint.get("props", []) as Array:
		var prop: Dictionary = raw_prop as Dictionary
		var prop_id := String(prop.get("id", ""))
		if not destroyed.has(prop_id) or not bool(prop.get("blocking", false)):
			continue
		var pos := _entity_pos(prop)
		var cell_id := String(prop.get("cell_id", ""))
		if not SiteBlueprintModel.is_walkable(_blueprint, pos) \
				and SiteVisitJournalModel.revisit_is_walkable(
					_promise, _blueprint, _scarred_state,
					String(_scarred_state.get("state_receipt", "")), _projection, cell_id
				):
			_opened_prop_cells.append(cell_id)


func _preferred_focus_step() -> int:
	var first_scar_step := 0
	for index in range(_journal_events.size()):
		var event: Dictionary = _journal_events[index]
		for raw_effect in event.get("effects", []) as Array:
			var effect: Dictionary = raw_effect as Dictionary
			var kind := String(effect.get("kind", ""))
			if kind in ["reveal_building", "take_loot", "destroy_prop"]:
				return index + 1
			if first_scar_step == 0 and kind == "neutralize_threat":
				first_scar_step = index + 1
	return first_scar_step if first_scar_step > 0 else mini(1, _journal_events.size())


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, DESIGN), C_BG)
	_draw_noise_field()
	_draw_header()
	_draw_stage_rail()
	_panel(MAP_PANEL, "LOCAL SITE / 32 x 22", "ENTRY ^  EXIT X  LOOT <>  THREAT !  SCAR /X/")
	_panel(SIDE_PANEL, "PROOF / DECISION")
	if _load_ok:
		_draw_site_map()
		_draw_side_panel()
	else:
		_text("SCARRED REVISIT CONTRACT FAILED", Vector2(70.0, 230.0), 20, C_DANGER)
	_draw_footer()


func _draw_noise_field() -> void:
	for index in range(190):
		var x := float((index * 97 + 31) % 1280)
		var y := float((index * 53 + 17) % 768)
		draw_rect(Rect2(x, y, 2.0, 2.0), Color(0.72, 0.67, 0.48, 0.035))


func _draw_header() -> void:
	draw_rect(HEADER_RECT, C_HEADER)
	draw_line(Vector2(0.0, 71.0), Vector2(1280.0, 71.0), C_EDGE, 1.0)
	_text("SCARRED REVISIT LAB // RP-0005", Vector2(24.0, 31.0), 22, C_TEXT)
	_text("Fresh blueprint -> trusted journal -> derived scars -> no-respawn revisit.",
		Vector2(24.0, 55.0), 13, C_MUTED)
	var kind := String(_blueprint.get("site_kind", FIXTURE_KINDS[_fixture_index]))
	_text(String(FIXTURE_LABELS[_fixture_index]) + "  /  " + String(KIND_TITLES.get(kind, kind.to_upper())),
		Vector2(790.0, 31.0), 13, _kind_color(kind), 466.0, HORIZONTAL_ALIGNMENT_RIGHT)
	var resolution := String(_terminal.get("resolution", "pending")).to_upper()
	_text("ACTUAL CHAIN  /  %s  /  REV %d" % [resolution, int(_scarred_state.get("revision", 0))],
		Vector2(790.0, 54.0), 10, C_MUTED, 466.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_stage_rail() -> void:
	for index in range(4):
		var stage_number := index + 1
		var card_rect := Rect2(24.0 + float(index) * 310.0, 88.0, 302.0, 66.0)
		var selected := stage_number == _stage
		var accent := _stage_color(stage_number)
		draw_rect(Rect2(card_rect.position + Vector2(3.0, 4.0), card_rect.size), Color(0.0, 0.0, 0.0, 0.25))
		draw_rect(card_rect, C_CARD_HI if selected else C_CARD)
		draw_rect(card_rect, accent if selected else C_EDGE, false, 2.0 if selected else 1.0)
		draw_rect(Rect2(card_rect.position, Vector2(5.0, card_rect.size.y)), accent)
		_text("%d" % stage_number, card_rect.position + Vector2(16.0, 29.0), 21, accent)
		_text(String(STAGE_TITLES[index]), card_rect.position + Vector2(48.0, 25.0), 12,
			C_TEXT if selected else C_MUTED, 238.0)
		_text(String(STAGE_SUBTITLES[index]).to_upper(), card_rect.position + Vector2(48.0, 47.0),
			9, accent if selected else C_MUTED, 238.0)


func _panel(panel_rect: Rect2, title: String, legend: String = "") -> void:
	draw_rect(Rect2(panel_rect.position + Vector2(4.0, 5.0), panel_rect.size), Color(0.0, 0.0, 0.0, 0.32))
	draw_rect(panel_rect, C_PANEL)
	draw_rect(panel_rect, C_EDGE, false, 2.0)
	draw_rect(Rect2(panel_rect.position, Vector2(panel_rect.size.x, 31.0)), C_PANEL_2)
	draw_line(panel_rect.position + Vector2(0.0, 31.0),
		panel_rect.position + Vector2(panel_rect.size.x, 31.0), C_EDGE, 1.0)
	_text(title, panel_rect.position + Vector2(12.0, 22.0), 13, C_GOLD)
	if legend != "":
		_text(legend, panel_rect.position + Vector2(250.0, 21.0), 8, C_MUTED,
			panel_rect.size.x - 262.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_site_map() -> void:
	draw_rect(Rect2(GRID_RECT.position + Vector2(4.0, 5.0), GRID_RECT.size), Color(0.0, 0.0, 0.0, 0.42))
	for y in range(int(_blueprint.get("height", 0))):
		for x in range(int(_blueprint.get("width", 0))):
			_draw_cell(Vector2i(x, y), SiteBlueprintModel.cell_at(_blueprint, Vector2i(x, y)))
	_draw_grid_guides()
	_draw_traversal_changes()
	if _stage == STAGE_JOURNAL:
		_draw_journal_path()
	_draw_props()
	_draw_loot()
	_draw_threats()
	_draw_building_roofs()
	if _stage in [STAGE_SCARS, STAGE_REVISIT]:
		_draw_scar_ghosts()
	_draw_building_doors()
	_draw_entry_and_extraction()
	if _stage == STAGE_JOURNAL:
		_draw_player()


func _draw_cell(cell: Vector2i, cell_type: int) -> void:
	var cell_rect := _cell_rect(cell)
	var inset := Rect2(cell_rect.position + Vector2.ONE * 0.5, cell_rect.size - Vector2.ONE)
	match cell_type:
		SiteBlueprintModel.CELL_ROAD:
			draw_rect(inset, C_ROAD.darkened(0.20))
			draw_line(cell_rect.position + Vector2(0.0, 10.5),
				cell_rect.position + Vector2(21.0, 10.5), Color(0.72, 0.62, 0.42, 0.12), 1.0)
		SiteBlueprintModel.CELL_FLOOR:
			draw_rect(inset, C_FLOOR)
			draw_line(cell_rect.position + Vector2(3.0, 17.0),
				cell_rect.position + Vector2(18.0, 17.0), Color(0.9, 0.85, 0.7, 0.08), 1.0)
		SiteBlueprintModel.CELL_WALL:
			draw_rect(inset, C_WALL)
			draw_rect(Rect2(cell_rect.position + Vector2(3.0, 3.0), cell_rect.size - Vector2(6.0, 6.0)), C_EDGE)
		SiteBlueprintModel.CELL_DOOR:
			draw_rect(inset, C_FLOOR)
			draw_rect(Rect2(cell_rect.position + Vector2(4.0, 8.0), Vector2(13.0, 5.0)), C_GOLD.darkened(0.16))
		SiteBlueprintModel.CELL_WINDOW:
			draw_rect(inset, C_WALL)
			draw_rect(Rect2(cell_rect.position + Vector2(4.0, 7.0), Vector2(13.0, 7.0)), C_WINDOW)
		SiteBlueprintModel.CELL_TREE:
			draw_rect(inset, C_DIRT)
			draw_circle(cell_rect.get_center(), 7.0, C_TREE)
		SiteBlueprintModel.CELL_RUBBLE:
			draw_rect(inset, C_DIRT)
			draw_rect(Rect2(cell_rect.position + Vector2(4.0, 5.0), Vector2(7.0, 6.0)), C_RUBBLE)
			draw_rect(Rect2(cell_rect.position + Vector2(11.0, 11.0), Vector2(6.0, 5.0)), C_RUBBLE.darkened(0.12))
		SiteBlueprintModel.CELL_WATER:
			draw_rect(inset, C_WATER.darkened(0.24))
			draw_line(cell_rect.position + Vector2(3.0, 7.0),
				cell_rect.position + Vector2(18.0, 7.0), C_TEAL.darkened(0.2), 1.0)
			draw_line(cell_rect.position + Vector2(6.0, 15.0),
				cell_rect.position + Vector2(20.0, 15.0), C_TEAL.darkened(0.3), 1.0)
		SiteBlueprintModel.CELL_EXIT:
			draw_rect(inset, C_ROAD.darkened(0.18))
		SiteBlueprintModel.CELL_FENCE:
			draw_rect(inset, C_DIRT)
			draw_line(cell_rect.position + Vector2(4.0, 4.0),
				cell_rect.position + Vector2(17.0, 17.0), C_FENCE, 2.0)
			draw_line(cell_rect.position + Vector2(17.0, 4.0),
				cell_rect.position + Vector2(4.0, 17.0), C_FENCE, 2.0)
		SiteBlueprintModel.CELL_CROP:
			draw_rect(inset, C_DIRT.lightened(0.04))
			for row in [5.0, 10.0, 15.0]:
				draw_line(cell_rect.position + Vector2(3.0, row),
					cell_rect.position + Vector2(18.0, row), C_CROP, 2.0)
		SiteBlueprintModel.CELL_PIT:
			draw_rect(inset, C_PIT)
			draw_line(cell_rect.position + Vector2(3.0, 4.0),
				cell_rect.position + Vector2(18.0, 17.0), Color(0.65, 0.45, 0.34, 0.22), 1.0)
		_:
			draw_rect(inset, C_DIRT)
	if (cell.x + cell.y) % 2 != 0:
		draw_rect(inset, Color(0.035, 0.035, 0.025, 0.05))


func _draw_grid_guides() -> void:
	for x in range(0, 33, 4):
		var px := GRID_RECT.position.x + float(x) * CELL_SIZE
		draw_line(Vector2(px, GRID_RECT.position.y), Vector2(px, GRID_RECT.end.y),
			Color(0.78, 0.74, 0.59, 0.055), 1.0)
	for y in range(0, 23, 4):
		var py := GRID_RECT.position.y + float(y) * CELL_SIZE
		draw_line(Vector2(GRID_RECT.position.x, py), Vector2(GRID_RECT.end.x, py),
			Color(0.78, 0.74, 0.59, 0.055), 1.0)
	draw_rect(GRID_RECT, C_EDGE_HI, false, 1.0)


func _draw_traversal_changes() -> void:
	if _stage != STAGE_REVISIT:
		return
	for cell_id in _opened_prop_cells:
		var cell_rect := _cell_rect(_cell_pos(cell_id))
		draw_rect(cell_rect.grow(-2.0), Color(C_TEAL, 0.22))
		draw_rect(cell_rect.grow(-2.0), C_TEAL, false, 2.0)
		draw_line(cell_rect.position + Vector2(4.0, 10.5),
			cell_rect.end - Vector2(4.0, 10.5), C_TEAL, 2.0)


func _draw_journal_path() -> void:
	var limit := mini(_journal_step, _journal_events.size())
	var points := PackedVector2Array()
	var entry: Dictionary = _blueprint.get("entry", {}) as Dictionary
	points.append(_cell_center(_entity_pos(entry)))
	for index in range(limit):
		var event: Dictionary = _journal_events[index]
		for raw_effect in event.get("effects", []) as Array:
			var effect: Dictionary = raw_effect as Dictionary
			if String(effect.get("kind", "")) == "move_player":
				points.append(_cell_center(_cell_pos(String(effect.get("to_cell_id", "")))))
	if points.size() >= 2:
		draw_polyline(points, Color(C_TEAL, 0.75), 2.0, true)


func _draw_props() -> void:
	var removed := _stage_id_set("destroyed_prop_ids")
	var entities: Array = _projection.get("props", []) as Array if _stage == STAGE_REVISIT \
		else _blueprint.get("props", []) as Array
	var revealed := _stage_id_set("revealed_building_ids")
	for raw_prop in entities:
		var prop: Dictionary = raw_prop as Dictionary
		if removed.has(String(prop.get("id", ""))) or _inside_closed_roof(_entity_pos(prop), revealed):
			continue
		var center := _cell_center(_entity_pos(prop))
		if String(prop.get("kind", "")) == "tower":
			draw_line(center + Vector2(0.0, 7.0), center + Vector2(0.0, -8.0), C_TEAL, 2.0)
			draw_line(center + Vector2(-5.0, -3.0), center + Vector2(5.0, -3.0), C_TEAL, 2.0)
			draw_circle(center + Vector2(0.0, -8.0), 2.5, C_GOLD)
		else:
			draw_rect(Rect2(center - Vector2(5.0, 4.0), Vector2(10.0, 8.0)), C_EDGE_HI)
			draw_rect(Rect2(center - Vector2(3.0, 2.0), Vector2(6.0, 4.0)), C_CARD)


func _draw_loot() -> void:
	var removed := _stage_id_set("taken_loot_ids")
	var entities: Array = _projection.get("loot", []) as Array if _stage == STAGE_REVISIT \
		else _blueprint.get("loot", []) as Array
	var revealed := _stage_id_set("revealed_building_ids")
	for raw_loot in entities:
		var loot: Dictionary = raw_loot as Dictionary
		if removed.has(String(loot.get("id", ""))) or _inside_closed_roof(_entity_pos(loot), revealed):
			continue
		var center := _cell_center(_entity_pos(loot))
		var diamond := PackedVector2Array([
			center + Vector2(0.0, -6.0), center + Vector2(6.0, 0.0),
			center + Vector2(0.0, 6.0), center + Vector2(-6.0, 0.0),
		])
		draw_colored_polygon(diamond, C_GOLD)
		draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), C_TEXT, 1.0)


func _draw_threats() -> void:
	var revealed := _stage_id_set("revealed_building_ids")
	if _stage == STAGE_JOURNAL:
		var runtime := _display_journal_runtime()
		for raw_state in runtime.get("threat_states", []) as Array:
			var state: Dictionary = raw_state as Dictionary
			if int(state.get("hp", 0)) <= 0:
				continue
			var pos := _cell_pos(String(state.get("cell_id", "")))
			if _inside_closed_roof(pos, revealed):
				continue
			_draw_threat_mark(pos, bool(state.get("alerted", false)))
		return
	var removed := _stage_id_set("neutralized_threat_ids")
	var entities: Array = _projection.get("threats", []) as Array if _stage == STAGE_REVISIT \
		else _blueprint.get("threats", []) as Array
	for raw_threat in entities:
		var threat: Dictionary = raw_threat as Dictionary
		if removed.has(String(threat.get("id", ""))) or _inside_closed_roof(_entity_pos(threat), revealed):
			continue
		_draw_threat_mark(_entity_pos(threat), false)


func _draw_threat_mark(pos: Vector2i, alerted: bool) -> void:
	var center := _cell_center(pos)
	draw_circle(center, 7.0, C_DANGER.darkened(0.18))
	draw_circle(center, 7.0, C_GOLD if alerted else C_DANGER, false, 2.0)
	_text("!", center + Vector2(-3.2, 4.0), 10, C_TEXT)


func _draw_building_roofs() -> void:
	var revealed := _stage_id_set("revealed_building_ids")
	for raw_building in _blueprint.get("buildings", []) as Array:
		var building: Dictionary = raw_building as Dictionary
		var roof_rect := _building_rect(building)
		if revealed.has(String(building.get("id", ""))):
			draw_rect(roof_rect.grow(-2.0), C_TEAL, false, 2.0)
			var copy := "CUTAWAY / " + String(building.get("label", "BUILDING"))
			var copy_width := _font.get_string_size(copy, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8).x
			var tag_width := minf(roof_rect.size.x - 8.0, maxf(96.0, copy_width + 14.0))
			var tag_position := roof_rect.position + Vector2(4.0, 4.0)
			if String(building.get("entrance_side", "")) == "north":
				tag_position.x = roof_rect.end.x - tag_width - 4.0
			var tag_rect := Rect2(tag_position, Vector2(tag_width, 17.0))
			draw_rect(tag_rect, Color(0.08, 0.10, 0.08, 0.88))
			_text(copy, tag_rect.position + Vector2(5.0, 12.0), 8, C_TEAL, tag_rect.size.x - 10.0)
			continue
		var roof_color := Color("#4b493f")
		var tone := int(building.get("roof_tone", 0))
		if tone == 1:
			roof_color = Color("#535044")
		elif tone == 2:
			roof_color = Color("#41453d")
		draw_rect(Rect2(roof_rect.position + Vector2(3.0, 4.0), roof_rect.size), Color(0.0, 0.0, 0.0, 0.38))
		draw_rect(roof_rect, roof_color)
		draw_rect(roof_rect, C_EDGE_HI, false, 2.0)
		var seam_y := roof_rect.position.y + roof_rect.size.y * 0.5
		draw_line(Vector2(roof_rect.position.x + 5.0, seam_y),
			Vector2(roof_rect.end.x - 5.0, seam_y), roof_color.lightened(0.14), 2.0)
		_text(String(building.get("label", "BUILDING")), roof_rect.position + Vector2(7.0, 21.0),
			9, C_TEXT, roof_rect.size.x - 14.0)
		_text("ROOF CLOSED", roof_rect.position + Vector2(7.0, 37.0), 8, C_MUTED,
			roof_rect.size.x - 14.0)


func _draw_scar_ghosts() -> void:
	var revealed := _stage_id_set("revealed_building_ids")
	for tuple in [
		["depleted_loot_ids", "loot", C_GOLD],
		["neutralized_threat_ids", "threats", C_DANGER],
		["destroyed_prop_ids", "props", C_EDGE_HI],
	]:
		var ids := _id_set(_terminal.get(String(tuple[0]), []) as Array)
		for raw_entity in _blueprint.get(String(tuple[1]), []) as Array:
			var entity: Dictionary = raw_entity as Dictionary
			if not ids.has(String(entity.get("id", ""))) or _inside_closed_roof(_entity_pos(entity), revealed):
				continue
			var center := _cell_center(_entity_pos(entity))
			var color: Color = tuple[2] as Color
			draw_circle(center, 7.0, Color(color, 0.12))
			draw_line(center + Vector2(-5.0, -5.0), center + Vector2(5.0, 5.0), color, 2.0)
			draw_line(center + Vector2(5.0, -5.0), center + Vector2(-5.0, 5.0), color, 2.0)


func _draw_building_doors() -> void:
	var revealed := _stage_id_set("revealed_building_ids")
	for raw_building in _blueprint.get("buildings", []) as Array:
		var building: Dictionary = raw_building as Dictionary
		var open := revealed.has(String(building.get("id", "")))
		for raw_door in building.get("doors", []) as Array:
			var door: Dictionary = raw_door as Dictionary
			var role := String(door.get("role", ""))
			if role != "exterior" and not open:
				continue
			var center := _cell_center(_entity_pos(door))
			var marker_color := C_GOLD if role == "exterior" else C_TEAL
			draw_rect(Rect2(center - Vector2(6.0, 3.0), Vector2(12.0, 6.0)), Color(0.05, 0.06, 0.05, 0.92))
			draw_rect(Rect2(center - Vector2(6.0, 3.0), Vector2(12.0, 6.0)), marker_color, false, 2.0)


func _draw_entry_and_extraction() -> void:
	var entry: Dictionary = _blueprint.get("entry", {}) as Dictionary
	var extraction: Dictionary = _blueprint.get("extraction", {}) as Dictionary
	var entry_center := _cell_center(_entity_pos(entry))
	var exit_center := _cell_center(_entity_pos(extraction))
	var arrow := PackedVector2Array([
		entry_center + Vector2(-7.0, 5.0), entry_center + Vector2(0.0, -7.0),
		entry_center + Vector2(7.0, 5.0),
	])
	draw_colored_polygon(arrow, C_TEAL)
	draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[0]]), C_TEXT, 1.0)
	draw_circle(exit_center, 8.0, Color(0.05, 0.06, 0.05, 0.92))
	draw_circle(exit_center, 8.0, C_GOOD, false, 2.0)
	_text("X", exit_center + Vector2(-3.8, 3.8), 9, C_GOOD)


func _draw_player() -> void:
	var runtime := _display_journal_runtime()
	var pos := _cell_pos(String(runtime.get("player_cell_id", "")))
	var center := _cell_center(pos)
	draw_circle(center, 8.0, Color(0.04, 0.06, 0.05, 0.92))
	draw_circle(center, 8.0, C_TEAL, false, 2.0)
	_text("P", center + Vector2(-3.7, 4.0), 9, C_TEXT)


func _draw_side_panel() -> void:
	var kind := String(_blueprint.get("site_kind", ""))
	var accent := _kind_color(kind)
	var identity := Rect2(880.0, 209.0, 360.0, 60.0)
	_card(identity, accent)
	_text(String(KIND_TITLES.get(kind, kind.to_upper())), Vector2(894.0, 232.0), 15, C_TEXT, 330.0)
	_text("%s / %s" % [String(_blueprint.get("layout_key", "")), String(STAGE_TITLES[_stage - 1])],
		Vector2(894.0, 254.0), 9, accent, 330.0)
	var evidence := Rect2(880.0, 281.0, 360.0, 205.0)
	_card(evidence, _stage_color(_stage))
	match _stage:
		STAGE_FRESH:
			_draw_fresh_evidence()
		STAGE_JOURNAL:
			_draw_journal_evidence()
		STAGE_SCARS:
			_draw_scar_evidence()
		STAGE_REVISIT:
			_draw_revisit_evidence()
	var decision := Rect2(880.0, 498.0, 360.0, 167.0)
	_card(decision, C_TEAL if _stage == STAGE_REVISIT else C_EDGE_HI)
	_draw_decision_card(kind)


func _draw_fresh_evidence() -> void:
	_text("BASELINE PROMISE", Vector2(894.0, 304.0), 10, C_GOLD)
	_text("IMMUTABLE / UNVISITED", Vector2(1025.0, 304.0), 9, C_TEXT, 199.0, HORIZONTAL_ALIGNMENT_RIGHT)
	_text("ROOFS CLOSED", Vector2(894.0, 335.0), 18, C_GOLD)
	_text("Interior loot and threats remain unread.", Vector2(894.0, 356.0), 10, C_MUTED, 330.0)
	_count_line(384.0, "LOOT AUTHORED", (_blueprint.get("loot", []) as Array).size(), C_GOLD)
	_count_line(410.0, "THREATS AUTHORED", (_blueprint.get("threats", []) as Array).size(), C_DANGER)
	_count_line(436.0, "BUILDINGS UNKNOWN", (_blueprint.get("buildings", []) as Array).size(), C_TEAL)
	_text("BLUEPRINT RECEIPT", Vector2(894.0, 466.0), 8, C_MUTED)
	_text(_short_receipt(String(_blueprint.get("blueprint_receipt", ""))), Vector2(1000.0, 466.0),
		8, C_TEXT, 224.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_journal_evidence() -> void:
	var runtime := _display_journal_runtime()
	var event_count := _journal_prefix_event_count()
	_text("TRUSTED JOURNAL PREFIX", Vector2(894.0, 304.0), 10, C_TEAL)
	_text("ACTION %d / %d" % [event_count, _journal_events.size()], Vector2(1060.0, 304.0),
		9, C_TEXT, 164.0, HORIZONTAL_ALIGNMENT_RIGHT)
	_text("%s  /  HP %d  /  NOISE %d" % [String(runtime.get("phase", "")).to_upper(),
		int(runtime.get("health", 0)), int(runtime.get("noise", 0))], Vector2(894.0, 334.0), 14, C_TEXT, 330.0)
	_text("CARGO %d  /  TURN %d" % [int(runtime.get("cargo_value", 0)), int(runtime.get("turns", 0))],
		Vector2(894.0, 356.0), 10, C_GOLD, 330.0)
	var last_event := _display_journal_event()
	var intent: Dictionary = last_event.get("intent", {}) as Dictionary
	_text("INTENT  " + String(intent.get("kind", "BEGIN")).to_upper(), Vector2(894.0, 385.0), 9, C_MUTED)
	var y := 406.0
	var shown := 0
	for raw_effect in last_event.get("effects", []) as Array:
		if shown >= 3:
			break
		var effect: Dictionary = raw_effect as Dictionary
		_text("-> " + _effect_copy(effect), Vector2(908.0, y), 9, _effect_color(String(effect.get("kind", ""))), 316.0)
		y += 19.0
		shown += 1
	if shown == 0:
		_text("-> ACCEPTED ACTIVE CHECKPOINT", Vector2(908.0, y), 9, C_MUTED, 316.0)
	_text("PREFIX RECEIPTED / EFFECTS REDUCER-OWNED", Vector2(894.0, 468.0), 8, C_TEAL, 330.0)


func _draw_scar_evidence() -> void:
	var resolution := String(_terminal.get("resolution", "")).to_upper()
	_text("CAUSAL SETTLEMENT", Vector2(894.0, 304.0), 10, C_TEAL)
	_text("DERIVED, NOT CLAIMED", Vector2(1048.0, 304.0), 9, C_TEXT, 176.0, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(resolution, Vector2(894.0, 336.0), 19, C_DANGER if resolution == "COLLAPSED" else C_GOOD)
	_text("%d ACTIONS / %d TURNS / CARGO %s" % [int(_terminal.get("action_count", 0)),
		int(_terminal.get("elapsed_turns", 0)), String(_terminal.get("cargo_disposition", "")).to_upper()],
		Vector2(894.0, 358.0), 9, C_MUTED, 330.0)
	_scar_count_line(386.0, "LOOT DEPLETED", "depleted_loot_ids", "loot", C_GOLD)
	_scar_count_line(409.0, "THREATS CLEARED", "neutralized_threat_ids", "threats", C_DANGER)
	_scar_count_line(432.0, "ROOFS REMEMBERED", "revealed_building_ids", "buildings", C_TEAL)
	_scar_count_line(455.0, "PROPS DESTROYED", "destroyed_prop_ids", "props", C_EDGE_HI)
	if _fixture_index == 5:
		_text("SEQUENCE-0 ABORT / ZERO DURABLE SCARS", Vector2(894.0, 476.0), 8, C_GOOD, 330.0)


func _draw_revisit_evidence() -> void:
	_text("REVISIT PROJECTION", Vector2(894.0, 304.0), 10, C_TEAL)
	_text("OWNER IDLE REV %d" % int(_scarred_state.get("revision", 0)), Vector2(1054.0, 304.0),
		9, C_TEXT, 170.0, HORIZONTAL_ALIGNMENT_RIGHT)
	_text("NO RESPAWN", Vector2(894.0, 336.0), 20, C_TEAL)
	_text("Removed entities stay absent; roof memory persists.", Vector2(894.0, 357.0), 9, C_MUTED, 330.0)
	_before_after_line(386.0, "LOOT", (_blueprint.get("loot", []) as Array).size(),
		(_projection.get("loot", []) as Array).size(), C_GOLD)
	_before_after_line(411.0, "THREATS", (_blueprint.get("threats", []) as Array).size(),
		(_projection.get("threats", []) as Array).size(), C_DANGER)
	_before_after_line(436.0, "BLOCKING PROPS", _fresh_blocking_count(),
		(_projection.get("navigation", {}) as Dictionary).get("blocking_prop_ids", []).size(), C_EDGE_HI)
	_text("OPENED WALKABLE CELLS  +%d" % _opened_prop_cells.size(), Vector2(894.0, 463.0),
		9, C_TEAL, 210.0)
	_text("EXIT %s" % ("OPEN" if bool((_projection.get("navigation", {}) as Dictionary).get("extraction_reachable", false)) else "BLOCKED"),
		Vector2(1100.0, 463.0), 9, C_GOOD, 124.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_decision_card(kind: String) -> void:
	_text("PLAYER DECISION", Vector2(894.0, 521.0), 10, C_MUTED)
	if _stage == STAGE_FRESH:
		_text("ENTER OR PASS?", Vector2(894.0, 551.0), 17, C_GOLD)
		_wrapped("The authored promise shows shape, not interior certainty.",
			Vector2(894.0, 577.0), 330.0, 10, C_TEXT, 2)
		_text("NEXT: COMMIT AN OWNER-ACCEPTED VISIT", Vector2(894.0, 644.0), 8, C_MUTED)
	elif _stage == STAGE_JOURNAL:
		var runtime := _display_journal_runtime()
		_text("PRESS ON OR EXTRACT?", Vector2(894.0, 551.0), 17, C_TEAL)
		_wrapped("Health %d, cargo %d, and the visible path are all from this exact prefix." % [
			int(runtime.get("health", 0)), int(runtime.get("cargo_value", 0))],
			Vector2(894.0, 577.0), 330.0, 10, C_TEXT, 3)
		_text("ENTER / SPACE  ADVANCES STORED PREFIX", Vector2(894.0, 644.0), 8, C_TEAL)
	elif _stage == STAGE_SCARS:
		_text("WHAT ACTUALLY PERSISTS?", Vector2(894.0, 551.0), 16, C_TEAL)
		_wrapped("Only reducer-owned terminal lists cross the active -> idle boundary.",
			Vector2(894.0, 577.0), 330.0, 10, C_TEXT, 3)
		_text("SETTLEMENT " + _short_receipt(String(_settlement.get("settlement_receipt", ""))),
			Vector2(894.0, 644.0), 8, C_MUTED, 330.0)
	else:
		_text(String(RETURN_READS.get(kind, "RETURN OR SKIP")), Vector2(894.0, 551.0), 15,
			C_TEAL if kind != "relay" and kind != "haven" else C_GOLD, 330.0)
		var roofs := (_terminal.get("revealed_building_ids", []) as Array).size()
		_wrapped("%d loot and %d threats remain; %d roof cutaways are remembered." % [
			(_projection.get("loot", []) as Array).size(), (_projection.get("threats", []) as Array).size(), roofs],
			Vector2(894.0, 579.0), 330.0, 10, C_TEXT, 3)
		_text("PROJECTION " + _short_receipt(String(_projection.get("projection_receipt", ""))),
			Vector2(894.0, 644.0), 8, C_MUTED, 330.0)


func _count_line(y: float, label: String, count: int, color: Color) -> void:
	_text(label, Vector2(894.0, y), 9, C_MUTED, 230.0)
	_text(str(count), Vector2(1124.0, y), 11, color, 100.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _scar_count_line(y: float, label: String, scar_field: String,
		source_field: String, color: Color) -> void:
	var scar_count := (_terminal.get(scar_field, []) as Array).size()
	var total := (_blueprint.get(source_field, []) as Array).size()
	if source_field == "props":
		total = 0
		for raw_prop in _blueprint.get("props", []) as Array:
			var prop: Dictionary = raw_prop as Dictionary
			if bool(prop.get("destructible", false)):
				total += 1
	_text(label, Vector2(894.0, y), 9, C_MUTED, 230.0)
	_text("%d / %d" % [scar_count, total], Vector2(1124.0, y), 10, color, 100.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _before_after_line(y: float, label: String, before: int, after: int, color: Color) -> void:
	_text(label, Vector2(894.0, y), 9, C_MUTED, 210.0)
	_text("%d  ->  %d" % [before, after], Vector2(1104.0, y), 10, color, 120.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _fresh_blocking_count() -> int:
	var count := 0
	for raw_prop in _blueprint.get("props", []) as Array:
		var prop: Dictionary = raw_prop as Dictionary
		if bool(prop.get("blocking", false)):
			count += 1
	return count


func _draw_footer() -> void:
	draw_rect(Rect2(0.0, 704.0, 1280.0, 64.0), C_HEADER)
	draw_line(Vector2(0.0, 704.0), Vector2(1280.0, 704.0), C_EDGE, 1.0)
	_fixture_rects.clear()
	for index in range(FIXTURE_LABELS.size()):
		var tab_rect := Rect2(24.0 + float(index) * 108.0, 719.0, 102.0, 33.0)
		_fixture_rects.append(tab_rect)
		var selected := index == _fixture_index
		var fill := Color("#35362d") if selected else Color("#22241e")
		if tab_rect.has_point(_mouse) and not selected:
			fill = Color("#292b24")
		draw_rect(tab_rect, fill)
		draw_rect(tab_rect, C_GOLD if selected else C_EDGE, false, 1.0)
		_text(String(FIXTURE_LABELS[index]), tab_rect.position + Vector2(6.0, 22.0), 9,
			C_TEXT if selected else C_MUTED, tab_rect.size.x - 12.0, HORIZONTAL_ALIGNMENT_CENTER)
	_stage_rects.clear()
	for index in range(4):
		var stage_number := index + 1
		var stage_rect := Rect2(682.0 + float(index) * 142.0, 719.0, 136.0, 33.0)
		_stage_rects.append(stage_rect)
		var selected := stage_number == _stage
		draw_rect(stage_rect, _stage_color(stage_number).darkened(0.58) if selected else C_CARD_HI)
		draw_rect(stage_rect, _stage_color(stage_number) if selected else C_EDGE, false, 1.0)
		_text("%d  %s" % [stage_number, String(STAGE_TITLES[index]).get_slice(" ", 0)],
			stage_rect.position + Vector2(8.0, 22.0), 9, C_TEXT if selected else C_MUTED,
			stage_rect.size.x - 16.0, HORIZONTAL_ALIGNMENT_CENTER)


func _display_journal() -> Dictionary:
	if _journal_prefixes.is_empty():
		return {}
	return _journal_prefixes[clampi(_journal_step, 0, _journal_prefixes.size() - 1)]


func _display_journal_runtime() -> Dictionary:
	return _display_journal().get("current", {}) as Dictionary


func _display_journal_event() -> Dictionary:
	var events: Array = _display_journal().get("events", []) as Array
	return events[events.size() - 1] as Dictionary if not events.is_empty() else {}


func _journal_prefix_event_count() -> int:
	return (_display_journal().get("events", []) as Array).size()


func _stage_id_set(field: String) -> Dictionary:
	match _stage:
		STAGE_JOURNAL:
			return _id_set(_display_journal_runtime().get(field, []) as Array)
		STAGE_SCARS:
			return _id_set(_terminal.get(_terminal_field(field), []) as Array)
		STAGE_REVISIT:
			return _id_set(_projection.get(_projection_field(field), []) as Array)
	return {}


func _terminal_field(runtime_field: String) -> String:
	match runtime_field:
		"taken_loot_ids":
			return "depleted_loot_ids"
		"neutralized_threat_ids":
			return "neutralized_threat_ids"
		"revealed_building_ids":
			return "revealed_building_ids"
		"destroyed_prop_ids":
			return "destroyed_prop_ids"
	return runtime_field


func _projection_field(runtime_field: String) -> String:
	return _terminal_field(runtime_field)


func _effect_copy(effect: Dictionary) -> String:
	var kind := String(effect.get("kind", "")).replace("_", " ").to_upper()
	var amount := int(effect.get("amount", 0))
	return kind + ("  %d" % amount if amount > 0 else "")


func _effect_color(kind: String) -> Color:
	if kind in ["damage_player", "terminal", "exhaustion"]:
		return C_DANGER
	if kind in ["take_loot", "destroy_prop", "neutralize_threat", "reveal_building"]:
		return C_TEAL
	return C_MUTED


func _building_rect(building: Dictionary) -> Rect2:
	var values: Array = building.get("rect", []) as Array
	if values.size() != 4:
		return Rect2()
	return Rect2(
		GRID_RECT.position + Vector2(float(values[0]), float(values[1])) * CELL_SIZE,
		Vector2(float(values[2]), float(values[3])) * CELL_SIZE
	)


func _entity_pos(entity: Dictionary) -> Vector2i:
	var values: Array = entity.get("pos", []) as Array
	return Vector2i(int(values[0]), int(values[1])) if values.size() == 2 else Vector2i(-1000, -1000)


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(GRID_RECT.position + Vector2(float(cell.x), float(cell.y)) * CELL_SIZE,
		Vector2(CELL_SIZE, CELL_SIZE))


func _cell_center(cell: Vector2i) -> Vector2:
	return _cell_rect(cell).get_center()


func _inside_closed_roof(cell: Vector2i, revealed: Dictionary) -> bool:
	for raw_building in _blueprint.get("buildings", []) as Array:
		var building: Dictionary = raw_building as Dictionary
		if revealed.has(String(building.get("id", ""))):
			continue
		var values: Array = building.get("rect", []) as Array
		if values.size() == 4 and cell.x >= int(values[0]) and cell.y >= int(values[1]) \
				and cell.x < int(values[0]) + int(values[2]) \
				and cell.y < int(values[1]) + int(values[3]):
			return true
	return false


func _id_set(ids: Array) -> Dictionary:
	var result := {}
	for raw_id in ids:
		result[String(raw_id)] = true
	return result


func _stage_color(stage_number: int) -> Color:
	match stage_number:
		STAGE_FRESH:
			return C_GOLD
		STAGE_JOURNAL:
			return Color("#84aebe")
		STAGE_SCARS:
			return C_DANGER
	return C_TEAL


func _kind_color(kind: String) -> Color:
	match kind:
		"clinic":
			return C_TEAL
		"relay":
			return Color("#84aebe")
		"quarry":
			return C_DANGER
		"farm":
			return C_GOOD
		"haven":
			return Color("#b1b17a")
	return C_GOLD


func _short_receipt(value: String) -> String:
	if value.length() <= 24:
		return value
	return value.substr(0, 11) + "..." + value.substr(value.length() - 8)


func _card(card_rect: Rect2, accent: Color) -> void:
	draw_rect(Rect2(card_rect.position + Vector2(3.0, 4.0), card_rect.size), Color(0.0, 0.0, 0.0, 0.28))
	draw_rect(card_rect, C_CARD)
	draw_rect(card_rect, C_EDGE, false, 1.0)
	draw_rect(Rect2(card_rect.position, Vector2(5.0, card_rect.size.y)), accent)


func _text(copy: String, baseline: Vector2, size: int, color: Color,
		width: float = -1.0, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(_font, baseline, copy, alignment, width, size, color)


func _wrapped(copy: String, baseline: Vector2, width: float, size: int,
		color: Color, max_lines: int) -> float:
	var words := copy.split(" ", false)
	var line := ""
	var y := baseline.y
	var line_count := 0
	for raw_word in words:
		var word := String(raw_word)
		var candidate := word if line == "" else line + " " + word
		if _font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x > width and line != "":
			_text(line, Vector2(baseline.x, y), size, color, width)
			y += float(size + 4)
			line_count += 1
			line = word
			if line_count >= max_lines:
				return y
		else:
			line = candidate
	if line != "" and line_count < max_lines:
		_text(line, Vector2(baseline.x, y), size, color, width)
		y += float(size + 4)
	return y


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_mouse = motion.position
		queue_redraw()
		return
	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_LEFT and button_event.pressed:
			_handle_click(button_event.position)
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F:
			_apply_fixture(int(key_event.keycode) - int(KEY_A), _stage)
		KEY_1, KEY_2, KEY_3, KEY_4:
			_stage = int(key_event.keycode) - int(KEY_1) + 1
			queue_redraw()
		KEY_TAB:
			_stage = (_stage % 4) + 1
			queue_redraw()
		KEY_V:
			_stage = STAGE_REVISIT if _stage == STAGE_FRESH else STAGE_FRESH
			queue_redraw()
		KEY_ENTER, KEY_SPACE:
			if _stage == STAGE_JOURNAL:
				_journal_step = mini(_journal_step + 1, _journal_prefixes.size() - 1)
				queue_redraw()
		KEY_R:
			_apply_fixture(_fixture_index, _stage, _journal_step)


func _handle_click(click_position: Vector2) -> void:
	for index in range(_fixture_rects.size()):
		if _fixture_rects[index].has_point(click_position):
			_apply_fixture(index, _stage)
			return
	for index in range(_stage_rects.size()):
		if _stage_rects[index].has_point(click_position):
			_stage = index + 1
			queue_redraw()
			return


func _save_shot() -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("ScarredRevisitLab could not capture the viewport")
		get_tree().quit(1)
		return
	var save_error := image.save_png(_shot_path)
	if save_error != OK:
		push_error("ScarredRevisitLab could not save screenshot: %s" % error_string(save_error))
		get_tree().quit(1)
		return
	get_tree().quit()
