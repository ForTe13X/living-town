extends Node2D

const ScaleAddress = preload("res://scripts/labs/resource_pool/ScaleAddress.gd")
const PlanetCampaignModel = preload("res://scripts/labs/resource_pool/PlanetCampaignModel.gd")

const DESIGN := Vector2(1280.0, 768.0)
const HEADER_RECT := Rect2(0.0, 0.0, 1280.0, 72.0)
const MAIN_PANEL := Rect2(24.0, 170.0, 824.0, 512.0)
const SIDE_PANEL := Rect2(864.0, 170.0, 392.0, 512.0)
const BOARD_VIEW := Rect2(48.0, 210.0, 776.0, 443.0)

const FIXTURE_SCOPE := 0
const FIXTURE_FLEX := 1
const FIXTURE_SPRING := 2
const FIXTURE_AUTUMN := 3
const FIXTURE_WINTER := 4
const FIXTURE_DELIVERY := 5

const STAGE_COMMIT := 0
const STAGE_ADVANCE := 1
const STAGE_PROJECTION := 2
const STAGE_DELIVERY := 3

const GLOBAL_NETWORK_SCOPE := "ashfall_settlement_network"
const COMMAND_OWNER_SCOPE := "ashfall_campaign_command"
const WINDOW_KEYS := ["basin_relief", "meridian_trade", "nightward_fortify"]
const ACTIONS := ["aid", "trade", "fortify"]
const SEASONS := ["spring", "autumn", "winter"]
const REGION_SCOPES := {
	"basin_relief": "rp7_region_basin_relief",
	"meridian_trade": "rp7_region_meridian_trade",
	"nightward_fortify": "rp7_region_nightward_fortify",
}
const BASELINE_SIGNALS := {
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
const C_BLUE := Color("#84aebe")
const C_GOOD := Color("#8fb56d")
const C_DANGER := Color("#c45b50")

const FIXTURE_TITLES := [
	"A  SCOPE", "B  FLEX", "C  SPRING", "D  AUTUMN", "E  WINTER", "F  STAGE 2",
]
const FIXTURE_SUBTITLES := [
	"owners", "cap 3 / three", "cap 2 / aid", "cap 2 / trade",
	"cap 2 / fortify", "fresh delivery",
]
const ACTION_LABELS := ["1  AID", "2  TRADE", "3  FORTIFY"]

var _font: Font
var _catalog: Dictionary = {}
var _initial_state: Dictionary = {}
var _global_network_checkpoint_receipt := ""
var _epoch_states: Dictionary = {}
var _deferred_advances: Dictionary = {}
var _baseline_evidence: Dictionary = {}
var _superseded_evidence: Dictionary = {}
var _flex_fixtures: Dictionary = {}
var _tight_fixtures: Dictionary = {}
var _delivery_chains: Dictionary = {}
var _fixture := FIXTURE_SCOPE
var _epoch_index := 0
var _selected_action := 0
var _chain_step := STAGE_DELIVERY
var _show_superseded := false
var _flex_commit_view := false
var _flex_proposal: Dictionary = {}
var _shot_path := ""
var _load_ok := false
var _fixture_rects: Array[Rect2] = []
var _action_rects: Array[Rect2] = []


func _ready() -> void:
	_font = ThemeDB.fallback_font
	var requested_fixture := FIXTURE_SCOPE
	var explicit_fixture := false
	var requested_epoch := -1
	var requested_capacity := 0
	var requested_action := 0
	var requested_stage := ""
	var requested_delivery := "applied"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		var argument := String(args[index])
		if argument == "--campaign-fixture" and index + 1 < args.size():
			index += 1
			requested_fixture = _fixture_from_argument(String(args[index]))
			explicit_fixture = true
		elif argument.begins_with("--campaign-fixture="):
			requested_fixture = _fixture_from_argument(argument.trim_prefix("--campaign-fixture="))
			explicit_fixture = true
		elif argument == "--campaign-epoch" and index + 1 < args.size():
			index += 1
			requested_epoch = _epoch_from_argument(String(args[index]))
		elif argument.begins_with("--campaign-epoch="):
			requested_epoch = _epoch_from_argument(argument.trim_prefix("--campaign-epoch="))
		elif argument == "--campaign-capacity" and index + 1 < args.size():
			index += 1
			requested_capacity = clampi(int(String(args[index])), 2, 3)
		elif argument.begins_with("--campaign-capacity="):
			requested_capacity = clampi(int(argument.trim_prefix("--campaign-capacity=")), 2, 3)
		elif argument == "--campaign-directive" and index + 1 < args.size():
			index += 1
			requested_action = _action_from_argument(String(args[index]))
		elif argument.begins_with("--campaign-directive="):
			requested_action = _action_from_argument(argument.trim_prefix("--campaign-directive="))
		elif argument == "--campaign-stage" and index + 1 < args.size():
			index += 1
			requested_stage = String(args[index])
		elif argument.begins_with("--campaign-stage="):
			requested_stage = argument.trim_prefix("--campaign-stage=")
		elif argument == "--campaign-delivery" and index + 1 < args.size():
			index += 1
			requested_delivery = String(args[index])
		elif argument.begins_with("--campaign-delivery="):
			requested_delivery = argument.trim_prefix("--campaign-delivery=")
		elif argument == "--lab-shot" and index + 1 < args.size():
			index += 1
			_shot_path = String(args[index])
		elif argument.begins_with("--lab-shot="):
			_shot_path = argument.trim_prefix("--lab-shot=")
		index += 1
	_epoch_index = requested_epoch if requested_epoch >= 0 else _epoch_for_fixture(requested_fixture)
	_selected_action = clampi(requested_action, 0, ACTIONS.size() - 1)
	_fixture = requested_fixture
	if not explicit_fixture and requested_capacity == 3:
		_fixture = FIXTURE_FLEX
	elif not explicit_fixture and requested_capacity == 2:
		_fixture = FIXTURE_SPRING + _epoch_index
	_apply_stage_argument(requested_stage, explicit_fixture)
	_show_superseded = requested_delivery.strip_edges().to_lower() == "superseded"
	_sync_selection_to_fixture()
	_load_ok = _build_real_fixtures()
	if _load_ok and _fixture == FIXTURE_FLEX \
			and requested_stage.strip_edges().to_lower() in ["commit", "proposal"]:
		_flex_commit_view = _build_selected_flex_proposal()
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
		"a", "1", "scope", "owners":
			return FIXTURE_SCOPE
		"b", "2", "flex", "board":
			return FIXTURE_FLEX
		"c", "3", "spring", "aid":
			return FIXTURE_SPRING
		"d", "4", "autumn", "trade":
			return FIXTURE_AUTUMN
		"e", "5", "winter", "fortify":
			return FIXTURE_WINTER
		"f", "6", "delivery", "stage2", "stage_2":
			return FIXTURE_DELIVERY
	return FIXTURE_SCOPE


func _epoch_from_argument(value: String) -> int:
	match value.strip_edges().to_lower():
		"0", "spring":
			return 0
		"1", "autumn", "fall":
			return 1
		"2", "winter":
			return 2
	return -1


func _action_from_argument(value: String) -> int:
	match value.strip_edges().to_lower():
		"1", "aid", "basin", "basin_relief":
			return 0
		"2", "trade", "meridian", "meridian_trade":
			return 1
		"3", "fortify", "nightward", "nightward_fortify":
			return 2
	return 0


func _apply_stage_argument(value: String, explicit_fixture: bool) -> void:
	match value.strip_edges().to_lower():
		"scope", "owners":
			if not explicit_fixture:
				_fixture = FIXTURE_SCOPE
		"board", "options":
			if not explicit_fixture:
				_fixture = FIXTURE_FLEX
		"commit", "proposal":
			_chain_step = STAGE_COMMIT
			if not explicit_fixture:
				_fixture = FIXTURE_SPRING + _epoch_index
		"advance":
			_fixture = FIXTURE_DELIVERY
			_chain_step = STAGE_ADVANCE
		"projection", "deliverable":
			_fixture = FIXTURE_DELIVERY
			_chain_step = STAGE_PROJECTION
		"delivery", "applied", "superseded":
			_fixture = FIXTURE_DELIVERY
			_chain_step = STAGE_DELIVERY


func _epoch_for_fixture(value: int) -> int:
	if value in [FIXTURE_SPRING, FIXTURE_AUTUMN, FIXTURE_WINTER]:
		return value - FIXTURE_SPRING
	return 0


func _sync_selection_to_fixture() -> void:
	if _fixture in [FIXTURE_SPRING, FIXTURE_AUTUMN, FIXTURE_WINTER]:
		_epoch_index = _fixture - FIXTURE_SPRING
		_selected_action = _epoch_index
	elif _fixture == FIXTURE_DELIVERY:
		_epoch_index = 1
		_selected_action = 0


func _build_real_fixtures() -> bool:
	_catalog = PlanetCampaignModel.make_catalog(PlanetCampaignModel.DEFAULT_ROOT_SEED)
	_initial_state = PlanetCampaignModel.make_initial_state(_catalog)
	_global_network_checkpoint_receipt = _external_receipt("global-rp6-network")
	if _catalog.is_empty() or _initial_state.is_empty() \
			or _global_network_checkpoint_receipt == "":
		push_error("PlanetCampaignLab could not build the catalog and accepted campaign anchor")
		return false
	_baseline_evidence = _make_evidence_bundle(BASELINE_SIGNALS, "epoch0")
	var superseded_signals: Dictionary = BASELINE_SIGNALS.duplicate(true)
	var superseded_meridian: Dictionary = (
		superseded_signals.get("meridian_trade", {}) as Dictionary
	).duplicate(true)
	superseded_meridian["logistics_pressure"] = 0
	superseded_signals["meridian_trade"] = superseded_meridian
	_superseded_evidence = _make_evidence_bundle(superseded_signals, "superseded-scheduled")
	if _baseline_evidence.is_empty() or _superseded_evidence.is_empty():
		push_error("PlanetCampaignLab could not build accepted region adapter evidence")
		return false
	if not _build_epoch_states():
		return false
	_flex_fixtures.clear()
	_tight_fixtures.clear()
	for epoch in range(SEASONS.size()):
		var season := String(SEASONS[epoch])
		var state: Dictionary = _epoch_states.get(season, {}) as Dictionary
		var flex := _build_board_fixture(
			state, 3, "%s-flex" % season, _baseline_evidence, false
		)
		var tight := _build_board_fixture(
			state, 2, "%s-tight" % season, _baseline_evidence, true
		)
		if flex.is_empty() or tight.is_empty():
			push_error("PlanetCampaignLab could not build %s flex/tight boards" % season)
			return false
		_flex_fixtures[season] = flex
		_tight_fixtures[season] = tight
	if not _build_delivery_fixtures():
		return false
	return _validate_real_fixtures()


func _build_epoch_states() -> bool:
	_epoch_states.clear()
	_deferred_advances.clear()
	_epoch_states["spring"] = _initial_state
	var spring_advance: Dictionary = PlanetCampaignModel.advance_epoch(
		_catalog, _initial_state, String(_initial_state.get("state_receipt", ""))
	)
	var autumn_state: Dictionary = spring_advance.get("after_state", {}) as Dictionary
	var autumn_advance: Dictionary = PlanetCampaignModel.advance_epoch(
		_catalog, autumn_state, String(autumn_state.get("state_receipt", ""))
	)
	var winter_state: Dictionary = autumn_advance.get("after_state", {}) as Dictionary
	if spring_advance.is_empty() or autumn_state.is_empty() \
			or autumn_advance.is_empty() or winter_state.is_empty():
		push_error("PlanetCampaignLab could not advance the accepted epoch fixtures")
		return false
	_epoch_states["autumn"] = autumn_state
	_epoch_states["winter"] = winter_state
	_deferred_advances["spring"] = spring_advance
	_deferred_advances["autumn"] = autumn_advance
	return true


func _make_evidence_bundle(signals_by_key: Dictionary, tag: String) -> Dictionary:
	var adapters: Array[Dictionary] = []
	var acceptances: Array[Dictionary] = []
	var by_key := {}
	for key_value in WINDOW_KEYS:
		var key := String(key_value)
		var window := _window_for_key(key)
		var signals: Dictionary = (
			signals_by_key.get(key, {}) as Dictionary
		).duplicate(true)
		var region_scope := String(REGION_SCOPES.get(key, ""))
		var region_receipt := _external_receipt("%s-%s" % [tag, key])
		var adapter: Dictionary = PlanetCampaignModel.make_window_adapter(
			_catalog, key, region_scope, region_receipt, GLOBAL_NETWORK_SCOPE,
			_global_network_checkpoint_receipt, signals
		)
		var acceptance: Dictionary = PlanetCampaignModel.make_window_acceptance(
			String(window.get("window_id", "")), region_scope, region_receipt,
			String(adapter.get("adapter_receipt", ""))
		)
		if window.is_empty() or adapter.is_empty() or acceptance.is_empty():
			return {}
		adapters.append(adapter)
		acceptances.append(acceptance)
		by_key[key] = adapter
	return {"adapters": adapters, "acceptances": acceptances, "by_key": by_key}


func _build_board_fixture(state: Dictionary, capacity: int, tag: String,
		evidence: Dictionary, make_proposal: bool) -> Dictionary:
	var owner_checkpoint := _external_receipt("command-%s" % tag)
	var command_anchor: Dictionary = PlanetCampaignModel.make_command_anchor(
		COMMAND_OWNER_SCOPE, owner_checkpoint, int(state.get("epoch_index", -1)), 1, capacity
	)
	var anchor_receipt := String(command_anchor.get("anchor_receipt", ""))
	var adapters: Array = evidence.get("adapters", []) as Array
	var acceptances: Array = evidence.get("acceptances", []) as Array
	var board: Dictionary = PlanetCampaignModel.make_directive_board(
		_catalog, state, String(state.get("state_receipt", "")), adapters, acceptances,
		GLOBAL_NETWORK_SCOPE, _global_network_checkpoint_receipt, command_anchor,
		COMMAND_OWNER_SCOPE, owner_checkpoint, anchor_receipt
	)
	if command_anchor.is_empty() or board.is_empty():
		return {}
	var expected_count := 3 if capacity == 3 else 1
	if (board.get("options", []) as Array).size() != expected_count \
			or String(board.get("decision_status", "")) != "options_available":
		return {}
	var choices := {}
	for raw_option in board.get("options", []) as Array:
		var option: Dictionary = raw_option as Dictionary
		var choice: Dictionary = PlanetCampaignModel.make_choice(
			board, String(option.get("option_id", ""))
		)
		if choice.is_empty():
			return {}
		choices[String(option.get("action", ""))] = choice
	var result := {
		"state": state,
		"capacity": capacity,
		"owner_checkpoint": owner_checkpoint,
		"command_anchor": command_anchor,
		"board": board,
		"choices": choices,
		"evidence": evidence,
	}
	if make_proposal:
		var action := _favored_action(String(state.get("season", "")))
		var choice: Dictionary = choices.get(action, {}) as Dictionary
		var proposal := _commit_from_fixture(result, choice)
		if proposal.is_empty():
			return {}
		result["proposal"] = proposal
	return result


func _commit_from_fixture(fixture: Dictionary, choice: Dictionary) -> Dictionary:
	var state: Dictionary = fixture.get("state", {}) as Dictionary
	var evidence: Dictionary = fixture.get("evidence", {}) as Dictionary
	var command_anchor: Dictionary = fixture.get("command_anchor", {}) as Dictionary
	var board: Dictionary = fixture.get("board", {}) as Dictionary
	return PlanetCampaignModel.commit_directive(
		_catalog, state, String(state.get("state_receipt", "")),
		evidence.get("adapters", []) as Array, evidence.get("acceptances", []) as Array,
		GLOBAL_NETWORK_SCOPE, _global_network_checkpoint_receipt, command_anchor,
		COMMAND_OWNER_SCOPE, String(fixture.get("owner_checkpoint", "")),
		String(command_anchor.get("anchor_receipt", "")), board, choice
	)


func _build_delivery_fixtures() -> bool:
	var applied_branch: Dictionary = _tight_fixtures.get("spring", {}) as Dictionary
	var applied_chain := _build_delivery_chain(
		applied_branch, BASELINE_SIGNALS.get("meridian_trade", {}) as Dictionary, "applied"
	)
	var spring_state: Dictionary = _epoch_states.get("spring", {}) as Dictionary
	var superseded_branch := _build_board_fixture(
		spring_state, 2, "spring-superseded", _superseded_evidence, true
	)
	var superseded_signals: Dictionary = (
		BASELINE_SIGNALS.get("meridian_trade", {}) as Dictionary
	).duplicate(true)
	superseded_signals["logistics_pressure"] = 0
	var superseded_chain := _build_delivery_chain(
		superseded_branch, superseded_signals, "superseded"
	)
	if applied_chain.is_empty() or superseded_chain.is_empty() \
			or String(applied_chain.get("status", "")) != "applied" \
			or String(superseded_chain.get("status", "")) != "superseded":
		push_error("PlanetCampaignLab could not build applied and superseded deliveries")
		return false
	_delivery_chains = {"applied": applied_chain, "superseded": superseded_chain}
	return true


func _build_delivery_chain(branch: Dictionary, target_signals: Dictionary,
		tag: String) -> Dictionary:
	var commit: Dictionary = branch.get("proposal", {}) as Dictionary
	var committed_state: Dictionary = commit.get("after_state", {}) as Dictionary
	var pending_projection: Dictionary = PlanetCampaignModel.project_consequences(
		_catalog, committed_state, String(committed_state.get("state_receipt", ""))
	)
	var advance: Dictionary = PlanetCampaignModel.advance_epoch(
		_catalog, committed_state, String(committed_state.get("state_receipt", ""))
	)
	var advanced_state: Dictionary = advance.get("after_state", {}) as Dictionary
	var deliverable_projection: Dictionary = PlanetCampaignModel.project_consequences(
		_catalog, advanced_state, String(advanced_state.get("state_receipt", ""))
	)
	var consequence: Dictionary = commit.get("consequence_record", {}) as Dictionary
	var window := _window_for_key("meridian_trade")
	var region_scope := String(REGION_SCOPES["meridian_trade"])
	var region_receipt := _external_receipt("delivery-%s-meridian" % tag)
	var target_adapter: Dictionary = PlanetCampaignModel.make_window_adapter(
		_catalog, "meridian_trade", region_scope, region_receipt,
		GLOBAL_NETWORK_SCOPE, _global_network_checkpoint_receipt,
		target_signals.duplicate(true)
	)
	var target_acceptance: Dictionary = PlanetCampaignModel.make_window_acceptance(
		String(window.get("window_id", "")), region_scope, region_receipt,
		String(target_adapter.get("adapter_receipt", ""))
	)
	var delivery: Dictionary = PlanetCampaignModel.deliver_consequence(
		_catalog, advanced_state, String(advanced_state.get("state_receipt", "")),
		String(consequence.get("consequence_id", "")), target_adapter,
		target_acceptance, GLOBAL_NETWORK_SCOPE, _global_network_checkpoint_receipt
	)
	var delivered_state: Dictionary = delivery.get("after_state", {}) as Dictionary
	var delivered_projection: Dictionary = PlanetCampaignModel.project_consequences(
		_catalog, delivered_state, String(delivered_state.get("state_receipt", ""))
	)
	if commit.is_empty() or pending_projection.is_empty() or advance.is_empty() \
			or advanced_state.is_empty() or deliverable_projection.is_empty() \
			or consequence.is_empty() or target_adapter.is_empty() \
			or target_acceptance.is_empty() or delivery.is_empty() \
			or delivered_projection.is_empty():
		return {}
	return {
		"branch": branch,
		"commit": commit,
		"pending_projection": pending_projection,
		"advance": advance,
		"advanced_state": advanced_state,
		"deliverable_projection": deliverable_projection,
		"consequence": consequence,
		"target_adapter": target_adapter,
		"target_acceptance": target_acceptance,
		"delivery": delivery,
		"delivered_projection": delivered_projection,
		"status": String(delivery.get("delivery_status", "")),
	}


func _validate_real_fixtures() -> bool:
	if not PlanetCampaignModel.validate_catalog(_catalog).is_empty() \
			or not PlanetCampaignModel.validate_state(_catalog, _initial_state).is_empty():
		push_error("PlanetCampaignLab catalog or initial state failed exact validation")
		return false
	if not _validate_evidence(_baseline_evidence) \
			or not _validate_evidence(_superseded_evidence):
		push_error("PlanetCampaignLab adapter evidence failed exact validation")
		return false
	for season_value in SEASONS:
		var season := String(season_value)
		if not _validate_board_fixture(_flex_fixtures.get(season, {}) as Dictionary, 3, false) \
				or not _validate_board_fixture(_tight_fixtures.get(season, {}) as Dictionary, 1, true):
			push_error("PlanetCampaignLab %s boards failed exact validation" % season)
			return false
	for advance_value in _deferred_advances.values():
		var advance: Dictionary = advance_value as Dictionary
		var before_state: Dictionary = _epoch_states.get(
			String(advance.get("from_season", "")), {}
		) as Dictionary
		if not PlanetCampaignModel.validate_epoch_advance(
			_catalog, before_state, String(before_state.get("state_receipt", "")), advance
		).is_empty():
			push_error("PlanetCampaignLab deferred epoch fixture failed exact validation")
			return false
	if not _validate_delivery_chain(_delivery_chains.get("applied", {}) as Dictionary, "applied") \
			or not _validate_delivery_chain(
				_delivery_chains.get("superseded", {}) as Dictionary, "superseded"
			):
		push_error("PlanetCampaignLab delivery fixtures failed exact validation")
		return false
	return true


func _validate_evidence(evidence: Dictionary) -> bool:
	var adapters: Array = evidence.get("adapters", []) as Array
	var acceptances: Array = evidence.get("acceptances", []) as Array
	if adapters.size() != 3 or acceptances.size() != 3:
		return false
	for index in range(adapters.size()):
		var adapter: Dictionary = adapters[index] as Dictionary
		var acceptance: Dictionary = acceptances[index] as Dictionary
		if not PlanetCampaignModel.validate_window_adapter(
			_catalog, adapter, String(acceptance.get("expected_region_scope", "")),
			String(acceptance.get("accepted_region_checkpoint_receipt", "")),
			GLOBAL_NETWORK_SCOPE, _global_network_checkpoint_receipt,
			String(acceptance.get("expected_adapter_receipt", ""))
		).is_empty():
			return false
	return true


func _validate_board_fixture(fixture: Dictionary, expected_options: int,
		expect_proposal: bool) -> bool:
	var state: Dictionary = fixture.get("state", {}) as Dictionary
	var evidence: Dictionary = fixture.get("evidence", {}) as Dictionary
	var command_anchor: Dictionary = fixture.get("command_anchor", {}) as Dictionary
	var owner_checkpoint := String(fixture.get("owner_checkpoint", ""))
	var board: Dictionary = fixture.get("board", {}) as Dictionary
	if (board.get("options", []) as Array).size() != expected_options \
			or not PlanetCampaignModel.validate_command_anchor(
				command_anchor, COMMAND_OWNER_SCOPE, owner_checkpoint,
				String(command_anchor.get("anchor_receipt", ""))
			).is_empty() or not PlanetCampaignModel.validate_directive_board(
				_catalog, state, String(state.get("state_receipt", "")),
				evidence.get("adapters", []) as Array,
				evidence.get("acceptances", []) as Array,
				GLOBAL_NETWORK_SCOPE, _global_network_checkpoint_receipt,
				command_anchor, COMMAND_OWNER_SCOPE, owner_checkpoint,
				String(command_anchor.get("anchor_receipt", "")), board
			).is_empty():
		return false
	for choice_value in (fixture.get("choices", {}) as Dictionary).values():
		if not PlanetCampaignModel.validate_choice(board, choice_value).is_empty():
			return false
	if expect_proposal:
		var proposal: Dictionary = fixture.get("proposal", {}) as Dictionary
		var action := _favored_action(String(state.get("season", "")))
		var choice: Dictionary = (fixture.get("choices", {}) as Dictionary).get(action, {}) as Dictionary
		if proposal.get("owner_order", []) != ["campaign", "command_owner", "origin_region"] \
				or not PlanetCampaignModel.validate_commit_proposal(
					_catalog, state, String(state.get("state_receipt", "")),
					evidence.get("adapters", []) as Array,
					evidence.get("acceptances", []) as Array,
					GLOBAL_NETWORK_SCOPE, _global_network_checkpoint_receipt,
					command_anchor, COMMAND_OWNER_SCOPE, owner_checkpoint,
					String(command_anchor.get("anchor_receipt", "")), board,
					choice, proposal
				).is_empty():
			return false
	return true


func _validate_delivery_chain(chain: Dictionary, expected_status: String) -> bool:
	var commit: Dictionary = chain.get("commit", {}) as Dictionary
	var committed_state: Dictionary = commit.get("after_state", {}) as Dictionary
	var advance: Dictionary = chain.get("advance", {}) as Dictionary
	var advanced_state: Dictionary = chain.get("advanced_state", {}) as Dictionary
	var consequence: Dictionary = chain.get("consequence", {}) as Dictionary
	var target_adapter: Dictionary = chain.get("target_adapter", {}) as Dictionary
	var target_acceptance: Dictionary = chain.get("target_acceptance", {}) as Dictionary
	var delivery: Dictionary = chain.get("delivery", {}) as Dictionary
	var target_delta: Dictionary = delivery.get("target_region_delta", {}) as Dictionary
	var delivered_projection: Dictionary = chain.get("delivered_projection", {}) as Dictionary
	if String(advance.get("resolution", "")) != "directive" \
			or String(delivery.get("delivery_status", "")) != expected_status \
			or delivery.get("owner_order", []) != ["campaign", "target_region"] \
			or (delivered_projection.get("delivered", []) as Array).size() != 1 \
			or not (delivered_projection.get("pending", []) as Array).is_empty() \
			or not (delivered_projection.get("deliverable", []) as Array).is_empty():
		return false
	if expected_status == "applied" and int(target_delta.get("applied_delta", 0)) != -1:
		return false
	if expected_status == "superseded" and int(target_delta.get("applied_delta", -1)) != 0:
		return false
	return PlanetCampaignModel.validate_epoch_advance(
		_catalog, committed_state, String(committed_state.get("state_receipt", "")), advance
	).is_empty() and PlanetCampaignModel.validate_consequence_projection(
		_catalog, advanced_state, String(advanced_state.get("state_receipt", "")),
		chain.get("deliverable_projection", {})
	).is_empty() and PlanetCampaignModel.validate_consequence_delivery(
		_catalog, advanced_state, String(advanced_state.get("state_receipt", "")),
		String(consequence.get("consequence_id", "")), target_adapter,
		target_acceptance, GLOBAL_NETWORK_SCOPE, _global_network_checkpoint_receipt,
		delivery
	).is_empty()


func _build_selected_flex_proposal() -> bool:
	var fixture: Dictionary = _display_flex_fixture()
	var choices: Dictionary = fixture.get("choices", {}) as Dictionary
	var choice: Dictionary = choices.get(String(ACTIONS[_selected_action]), {}) as Dictionary
	_flex_proposal = _commit_from_fixture(fixture, choice)
	if _flex_proposal.is_empty():
		return false
	return not PlanetCampaignModel.validate_commit_proposal(
		_catalog, fixture.get("state", {}) as Dictionary,
		String((fixture.get("state", {}) as Dictionary).get("state_receipt", "")),
		(fixture.get("evidence", {}) as Dictionary).get("adapters", []) as Array,
		(fixture.get("evidence", {}) as Dictionary).get("acceptances", []) as Array,
		GLOBAL_NETWORK_SCOPE, _global_network_checkpoint_receipt,
		fixture.get("command_anchor", {}) as Dictionary, COMMAND_OWNER_SCOPE,
		String(fixture.get("owner_checkpoint", "")),
		String((fixture.get("command_anchor", {}) as Dictionary).get("anchor_receipt", "")),
		fixture.get("board", {}) as Dictionary, choice, _flex_proposal
	).is_empty()


func _display_flex_fixture() -> Dictionary:
	return _flex_fixtures.get(String(SEASONS[_epoch_index]), {}) as Dictionary


func _display_tight_fixture() -> Dictionary:
	var epoch := clampi(_fixture - FIXTURE_SPRING, 0, 2)
	return _tight_fixtures.get(String(SEASONS[epoch]), {}) as Dictionary


func _display_chain() -> Dictionary:
	return _delivery_chains.get(
		"superseded" if _show_superseded else "applied", {}
	) as Dictionary


func _display_board() -> Dictionary:
	if _fixture == FIXTURE_FLEX:
		return _display_flex_fixture().get("board", {}) as Dictionary
	if _fixture in [FIXTURE_SPRING, FIXTURE_AUTUMN, FIXTURE_WINTER]:
		return _display_tight_fixture().get("board", {}) as Dictionary
	if _fixture == FIXTURE_DELIVERY:
		return ((_display_chain().get("branch", {}) as Dictionary).get(
			"board", {}
		) as Dictionary)
	return {}


func _display_proposal() -> Dictionary:
	if _fixture == FIXTURE_FLEX and _flex_commit_view:
		return _flex_proposal
	if _fixture in [FIXTURE_SPRING, FIXTURE_AUTUMN, FIXTURE_WINTER]:
		return _display_tight_fixture().get("proposal", {}) as Dictionary
	if _fixture == FIXTURE_DELIVERY:
		return _display_chain().get("commit", {}) as Dictionary
	return {}


func _window_for_key(window_key: String) -> Dictionary:
	for raw_window in _catalog.get("windows", []) as Array:
		var window: Dictionary = raw_window as Dictionary
		var region := ScaleAddress.parse_id(String(window.get("region_id", "")))
		var face := int(region.get("face", -1))
		if (window_key == "basin_relief" and face == 0) \
				or (window_key == "meridian_trade" and face == 2) \
				or (window_key == "nightward_fortify" and face == 5):
			return window
	return {}


func _window_for_id(window_id: String) -> Dictionary:
	for raw_window in _catalog.get("windows", []) as Array:
		var window: Dictionary = raw_window as Dictionary
		if String(window.get("window_id", "")) == window_id:
			return window
	return {}


func _directive_for_action(action: String) -> Dictionary:
	for raw_directive in _catalog.get("directives", []) as Array:
		var directive: Dictionary = raw_directive as Dictionary
		if String(directive.get("action", "")) == action:
			return directive
	return {}


func _option_for_action(board: Dictionary, action: String) -> Dictionary:
	for raw_option in board.get("options", []) as Array:
		var option: Dictionary = raw_option as Dictionary
		if String(option.get("action", "")) == action:
			return option
	return {}


func _favored_action(season: String) -> String:
	match season:
		"spring":
			return "aid"
		"autumn":
			return "trade"
		"winter":
			return "fortify"
	return ""


func _external_receipt(label: String) -> String:
	var encoded := "[\"rp7-external-owner-checkpoint\",\"%s\"]" % label
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK \
			or context.update(encoded.to_utf8_buffer()) != OK:
		return ""
	return "sha256:" + context.finish().hex_encode()


func _receipt_suffix(receipt: String) -> String:
	return receipt.right(8).to_upper() if receipt.length() >= 8 else "--------"


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, DESIGN), C_BG)
	_draw_noise_field()
	_draw_header()
	_draw_fixture_rail()
	_panel(MAIN_PANEL, "PLANET SCOPE / DISCRETE FACE REGISTERS", "NO TOPOLOGY CLAIM")
	_panel(SIDE_PANEL, "DIRECTIVE / AUTHORITY")
	if _load_ok:
		_draw_decision_board()
		_draw_side_panel()
	else:
		_text("PLANET CAMPAIGN CONTRACT FAILED", Vector2(70.0, 240.0), 20, C_DANGER)
	_draw_footer()


func _draw_noise_field() -> void:
	for index in range(190):
		var x := float((index * 97 + 31) % 1280)
		var y := float((index * 53 + 17) % 768)
		draw_rect(Rect2(x, y, 2.0, 2.0), Color(0.72, 0.67, 0.48, 0.035))


func _draw_header() -> void:
	draw_rect(HEADER_RECT, C_HEADER)
	draw_line(Vector2(0.0, 71.0), Vector2(1280.0, 71.0), C_EDGE, 1.0)
	_text("PLANET CAMPAIGN LAB // RP-0007", Vector2(24.0, 31.0), 22, C_TEXT)
	_text("Choose one seasonal directive across three discrete strategic registers.",
		Vector2(24.0, 55.0), 13, C_MUTED)
	_text("PLANET / ASHFALL", Vector2(930.0, 31.0), 13, C_GOLD, 326.0,
		HORIZONTAL_ALIGNMENT_RIGHT)
	var status := "ABSTRACT DIRECTIVE / PROPOSAL ONLY"
	if _fixture == FIXTURE_DELIVERY:
		status = "STAGE 2 / %s" % String(
			"SUPERSEDED" if _show_superseded else "APPLIED"
		)
	_text(status, Vector2(850.0, 54.0), 10,
		C_DANGER if _show_superseded else C_MUTED, 406.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_fixture_rail() -> void:
	for index in range(FIXTURE_TITLES.size()):
		var card_rect := Rect2(24.0 + float(index) * 204.0, 88.0, 196.0, 66.0)
		var selected := index == _fixture
		var accent := _fixture_color(index)
		draw_rect(Rect2(card_rect.position + Vector2(3.0, 4.0), card_rect.size),
			Color(0.0, 0.0, 0.0, 0.25))
		draw_rect(card_rect, C_CARD_HI if selected else C_CARD)
		draw_rect(card_rect, accent if selected else C_EDGE, false, 2.0 if selected else 1.0)
		draw_rect(Rect2(card_rect.position, Vector2(5.0, card_rect.size.y)), accent)
		_text(String(FIXTURE_TITLES[index]), card_rect.position + Vector2(14.0, 27.0),
			12, C_TEXT if selected else C_MUTED, 168.0)
		_text(String(FIXTURE_SUBTITLES[index]).to_upper(),
			card_rect.position + Vector2(14.0, 48.0), 8,
			accent if selected else C_MUTED, 168.0)


func _panel(panel_rect: Rect2, title: String, legend: String = "") -> void:
	draw_rect(Rect2(panel_rect.position + Vector2(4.0, 5.0), panel_rect.size),
		Color(0.0, 0.0, 0.0, 0.32))
	draw_rect(panel_rect, C_PANEL)
	draw_rect(panel_rect, C_EDGE, false, 2.0)
	draw_rect(Rect2(panel_rect.position, Vector2(panel_rect.size.x, 31.0)), C_PANEL_2)
	draw_line(panel_rect.position + Vector2(0.0, 31.0),
		panel_rect.position + Vector2(panel_rect.size.x, 31.0), C_EDGE, 1.0)
	_text(title, panel_rect.position + Vector2(12.0, 22.0), 13, C_GOLD)
	if legend != "":
		_text(legend, panel_rect.position + Vector2(530.0, 21.0), 8, C_MUTED,
			panel_rect.size.x - 542.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_decision_board() -> void:
	draw_rect(BOARD_VIEW, Color("#171914"))
	_draw_register_grid()
	_draw_scope_strip()
	_draw_face_registers()
	_draw_bottom_ledger()


func _draw_register_grid() -> void:
	for row in range(7):
		var y := BOARD_VIEW.position.y + 18.0 + float(row) * 67.0
		draw_line(Vector2(BOARD_VIEW.position.x, y), Vector2(BOARD_VIEW.end.x, y),
			Color(0.36, 0.40, 0.31, 0.08), 1.0)
	for column in range(13):
		var x := BOARD_VIEW.position.x + 20.0 + float(column) * 61.0
		draw_line(Vector2(x, BOARD_VIEW.position.y), Vector2(x, BOARD_VIEW.end.y),
			Color(0.36, 0.40, 0.31, 0.055), 1.0)


func _draw_scope_strip() -> void:
	var strip := Rect2(60.0, 220.0, 752.0, 44.0)
	draw_rect(strip, Color(0.055, 0.065, 0.052, 0.94))
	draw_rect(strip, C_EDGE, false, 1.0)
	draw_rect(Rect2(strip.position, Vector2(5.0, strip.size.y)), C_GOLD)
	_text("PSA1 / ASHFALL / THREE AUTHORED FACE SLOTS", strip.position + Vector2(14.0, 19.0),
		10, C_TEXT, 425.0)
	_text("REGION REGISTERS / NO FACE EDGES", strip.position + Vector2(14.0, 36.0),
		8, C_MUTED, 425.0)
	var right_copy := "CATALOG / THREE WINDOWS"
	if _fixture != FIXTURE_SCOPE:
		var state := _display_state()
		var capacity := _display_capacity()
		right_copy = "EPOCH %d / %s  ·  SLOT 1  ·  CAP %d" % [
			int(state.get("epoch_index", 0)), String(state.get("season", "")).to_upper(), capacity]
	if _fixture == FIXTURE_DELIVERY:
		right_copy = "SPRING COMMIT  ·  AUTUMN DELIVERY"
	_text(right_copy, strip.position + Vector2(437.0, 27.0), 9,
		C_TEAL if _fixture == FIXTURE_DELIVERY else C_GOLD, 300.0,
		HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_face_registers() -> void:
	var board := _display_board()
	for index in range(WINDOW_KEYS.size()):
		var key := String(WINDOW_KEYS[index])
		var action := String(ACTIONS[index])
		var card_rect := Rect2(60.0 + float(index) * 255.0, 276.0, 242.0, 238.0)
		_draw_face_register(card_rect, key, action, index, board)


func _draw_face_register(card_rect: Rect2, window_key: String, action: String,
		index: int, board: Dictionary) -> void:
	var window := _window_for_key(window_key)
	var directive := _directive_for_action(action)
	var option := _option_for_action(board, action)
	var accent := _action_color(index)
	var emphasized := _face_is_emphasized(index)
	draw_rect(Rect2(card_rect.position + Vector2(3.0, 4.0), card_rect.size),
		Color(0.0, 0.0, 0.0, 0.28))
	draw_rect(card_rect, C_CARD_HI if emphasized else C_CARD)
	draw_rect(card_rect, accent if emphasized else C_EDGE, false, 2.0 if emphasized else 1.0)
	draw_rect(Rect2(card_rect.position, Vector2(card_rect.size.x, 32.0)), C_PANEL_2)
	draw_rect(Rect2(card_rect.position, Vector2(5.0, card_rect.size.y)), accent)
	var region := ScaleAddress.parse_id(String(window.get("region_id", "")))
	var face := int(region.get("face", -1))
	_text(String(window.get("label", "")), card_rect.position + Vector2(14.0, 21.0),
		10, C_TEXT, 158.0)
	_text("FACE %d" % face, card_rect.position + Vector2(174.0, 21.0), 9, accent,
		54.0, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(action.to_upper() + " DIRECTIVE", card_rect.position + Vector2(14.0, 60.0),
		16, accent, 172.0)
	_draw_action_icon(card_rect.position + Vector2(209.0, 58.0), index, accent)
	_text("FAVORED / " + String(directive.get("favored_season", "")).to_upper(),
		card_rect.position + Vector2(14.0, 82.0), 9, C_MUTED, 200.0)
	var status_rect := Rect2(card_rect.position + Vector2(12.0, 94.0), Vector2(218.0, 30.0))
	var status_color := accent
	var status_copy := "REGISTERED"
	if _fixture == FIXTURE_FLEX:
		status_copy = "OPTION / COST %d" % int(option.get("capacity_cost", 0))
	elif _fixture in [FIXTURE_SPRING, FIXTURE_AUTUMN, FIXTURE_WINTER]:
		if option.is_empty():
			status_copy = "OFFSEASON COST 3 > CAP 2"
			status_color = C_DANGER
		else:
			status_copy = "ONLY ELIGIBLE / COST 2"
	elif _fixture == FIXTURE_DELIVERY:
		if index == 0:
			status_copy = "STAGE 1 / COMMITTED"
		elif index == 1:
			status_copy = "STAGE 2 / %s" % String(
				"SUPERSEDED" if _show_superseded else "APPLIED"
			)
			status_color = C_DANGER if _show_superseded else C_TEAL
		else:
			status_copy = "REGISTERED / NOT SELECTED"
	draw_rect(status_rect, Color(status_color, 0.08))
	draw_rect(status_rect, status_color, false, 1.0)
	_text(status_copy, status_rect.position + Vector2(9.0, 20.0), 9, status_color,
		status_rect.size.x - 18.0)
	var primary_track := _primary_track_label(String(directive.get("primary_track", "")))
	var benefit := _benefit_copy(directive.get("benefit", {}) as Dictionary)
	_text("PRIMARY / " + primary_track, card_rect.position + Vector2(14.0, 148.0),
		8, C_MUTED, 205.0)
	_text(benefit, card_rect.position + Vector2(14.0, 168.0), 12, accent, 205.0)
	_text("COST 2 FAVORED  ·  3 OFF", card_rect.position + Vector2(14.0, 190.0),
		8, C_TEXT, 205.0)
	var target_window := _window_for_id(String(directive.get("target_window_id", "")))
	_text("DELAYED / " + String(target_window.get("label", "")),
		card_rect.position + Vector2(14.0, 213.0), 8, C_MUTED, 205.0)
	_text("%s  %d  /  EPOCH +1" % [
		_primary_track_label(String(directive.get("consequence_track", ""))),
		int(directive.get("consequence_delta", 0))],
		card_rect.position + Vector2(14.0, 229.0), 8, C_MUTED, 205.0)


func _draw_action_icon(center: Vector2, index: int, color: Color) -> void:
	draw_circle(center, 13.0, Color(0.04, 0.05, 0.04, 0.92))
	draw_circle(center, 13.0, color, false, 2.0)
	if index == 0:
		draw_rect(Rect2(center - Vector2(2.0, 8.0), Vector2(4.0, 16.0)), color)
		draw_rect(Rect2(center - Vector2(8.0, 2.0), Vector2(16.0, 4.0)), color)
	elif index == 1:
		draw_line(center + Vector2(-8.0, -4.0), center + Vector2(7.0, -4.0), color, 2.0)
		draw_line(center + Vector2(7.0, -4.0), center + Vector2(3.0, -8.0), color, 2.0)
		draw_line(center + Vector2(-7.0, 4.0), center + Vector2(8.0, 4.0), color, 2.0)
		draw_line(center + Vector2(-7.0, 4.0), center + Vector2(-3.0, 8.0), color, 2.0)
	else:
		var shield := PackedVector2Array([
			center + Vector2(0.0, -8.0), center + Vector2(8.0, -4.0),
			center + Vector2(6.0, 5.0), center + Vector2(0.0, 9.0),
			center + Vector2(-6.0, 5.0), center + Vector2(-8.0, -4.0),
			center + Vector2(0.0, -8.0),
		])
		draw_polyline(shield, color, 2.0, true)


func _draw_bottom_ledger() -> void:
	var ledger := Rect2(60.0, 526.0, 752.0, 115.0)
	draw_rect(ledger, Color(0.045, 0.052, 0.043, 0.96))
	draw_rect(ledger, C_EDGE, false, 1.0)
	if _fixture == FIXTURE_SCOPE:
		_draw_scope_ledger(ledger)
	elif _fixture == FIXTURE_FLEX:
		_draw_flex_ledger(ledger)
	elif _fixture in [FIXTURE_SPRING, FIXTURE_AUTUMN, FIXTURE_WINTER]:
		_draw_commit_ledger(ledger, _display_proposal())
	else:
		_draw_delivery_ledger(ledger)


func _draw_scope_ledger(ledger: Rect2) -> void:
	_text("ONE SHARED GLOBAL CHECKPOINT / THREE INDEPENDENT REGION ADAPTERS",
		ledger.position + Vector2(13.0, 20.0), 9, C_GOLD, 720.0)
	var chip_width := 174.0
	var labels := ["GLOBAL RP6 / READ ONCE", "BASIN REGION", "MERIDIAN REGION", "NIGHTWARD REGION"]
	for index in range(labels.size()):
		var chip := Rect2(ledger.position + Vector2(13.0 + float(index) * 181.0, 34.0),
			Vector2(chip_width, 63.0))
		var color := C_GOLD if index == 0 else _action_color(index - 1)
		draw_rect(chip, C_CARD)
		draw_rect(chip, color, false, 1.0)
		_text(String(labels[index]), chip.position + Vector2(8.0, 19.0), 8, color,
			chip.size.x - 16.0)
		var receipt := _global_network_checkpoint_receipt
		if index > 0:
			var adapter: Dictionary = (_baseline_evidence.get("by_key", {}) as Dictionary).get(
				String(WINDOW_KEYS[index - 1]), {}
			) as Dictionary
			receipt = String(adapter.get("adapter_receipt", ""))
		_text("RECEIPT / " + _receipt_suffix(receipt), chip.position + Vector2(8.0, 40.0),
			8, C_TEXT, chip.size.x - 16.0)
		_text("ACCEPTED INPUT", chip.position + Vector2(8.0, 55.0), 7, C_MUTED,
			chip.size.x - 16.0)


func _draw_flex_ledger(ledger: Rect2) -> void:
	var fixture := _display_flex_fixture()
	var board: Dictionary = fixture.get("board", {}) as Dictionary
	var status := String(board.get("decision_status", "")).to_upper()
	_text("%s / THREE NON-DOMINATED OPTIONS / NO GLOBAL SCORE" % status,
		ledger.position + Vector2(13.0, 21.0), 9, C_TEAL, 720.0)
	for index in range(ACTIONS.size()):
		var action := String(ACTIONS[index])
		var option := _option_for_action(board, action)
		var chip := Rect2(ledger.position + Vector2(13.0 + float(index) * 240.0, 37.0),
			Vector2(227.0, 58.0))
		var color := _action_color(index)
		draw_rect(chip, C_CARD_HI if index == _selected_action else C_CARD)
		draw_rect(chip, color if index == _selected_action else C_EDGE, false, 1.0)
		_text(action.to_upper(), chip.position + Vector2(9.0, 20.0), 9, color, 95.0)
		_text("CAPACITY %d" % int(option.get("capacity_cost", 0)),
			chip.position + Vector2(104.0, 20.0), 8, C_GOLD, 112.0,
			HORIZONTAL_ALIGNMENT_RIGHT)
		_text(_benefit_copy(option.get("benefit", {}) as Dictionary),
			chip.position + Vector2(9.0, 43.0), 9, C_TEXT, 207.0)
	if _flex_commit_view:
		_text("SELECTED REAL THREE-OWNER PROPOSAL / " + String(
			_flex_proposal.get("owner_order", [])
		), ledger.position + Vector2(13.0, 108.0), 8, C_TEAL, 720.0)


func _draw_commit_ledger(ledger: Rect2, proposal: Dictionary) -> void:
	var owner_order: Array = proposal.get("owner_order", []) as Array
	_text("JOINT COMMIT PROPOSAL / RECEIVER CAS REQUIRED / PROPOSAL ONLY",
		ledger.position + Vector2(13.0, 21.0), 9, C_GOLD, 720.0)
	for index in range(owner_order.size()):
		var chip := Rect2(ledger.position + Vector2(31.0 + float(index) * 238.0, 38.0),
			Vector2(206.0, 55.0))
		var color := _action_color(_selected_action) if index == 2 else C_GOLD
		draw_rect(chip, C_CARD)
		draw_rect(chip, color, false, 1.0)
		_text(String(owner_order[index]).to_upper(), chip.position + Vector2(9.0, 21.0),
			9, color, chip.size.x - 18.0)
		_text("DELTA RECEIPT BOUND", chip.position + Vector2(9.0, 42.0), 8, C_MUTED,
			chip.size.x - 18.0)
		if index < owner_order.size() - 1:
			_text("+", chip.position + Vector2(213.0, 34.0), 15, C_EDGE_HI, 18.0,
				HORIZONTAL_ALIGNMENT_CENTER)
	_text("PROPOSAL / " + _receipt_suffix(String(proposal.get("proposal_receipt", ""))),
		ledger.position + Vector2(13.0, 108.0), 8, C_MUTED, 720.0)


func _draw_delivery_ledger(ledger: Rect2) -> void:
	_text("RECEIPT ORDER / NOT FACE GEOGRAPHY", ledger.position + Vector2(13.0, 19.0),
		8, C_MUTED, 720.0)
	var chain := _display_chain()
	var advance: Dictionary = chain.get("advance", {}) as Dictionary
	var projection: Dictionary = chain.get("deliverable_projection", {}) as Dictionary
	var delivery: Dictionary = chain.get("delivery", {}) as Dictionary
	var boxes := [
		["STAGE 1", "AID / THREE OWNERS"],
		["ADVANCE", "%s / %d -> %d" % [String(advance.get("resolution", "")).to_upper(),
			int(advance.get("from_epoch", 0)), int(advance.get("to_epoch", 0))]],
		["PROJECTION", "DELIVERABLE %d" % (projection.get("deliverable", []) as Array).size()],
		["DELIVERY", String(delivery.get("delivery_status", "")).to_upper() + " / TWO OWNERS"],
	]
	for index in range(boxes.size()):
		var box := Rect2(ledger.position + Vector2(13.0 + float(index) * 181.0, 33.0),
			Vector2(166.0, 59.0))
		var active := index <= _chain_step
		var color := C_DANGER if index == 3 and _show_superseded else C_TEAL
		draw_rect(box, C_CARD if active else Color(C_CARD, 0.45))
		draw_rect(box, color if active else C_EDGE, false, 1.0)
		_text(String((boxes[index] as Array)[0]), box.position + Vector2(8.0, 20.0),
			8, color if active else C_MUTED, box.size.x - 16.0)
		_text(String((boxes[index] as Array)[1]), box.position + Vector2(8.0, 43.0),
			8, C_TEXT if active else C_MUTED, box.size.x - 16.0)
		if index < boxes.size() - 1:
			draw_line(box.position + Vector2(box.size.x, 30.0),
				box.position + Vector2(box.size.x + 15.0, 30.0), C_EDGE_HI, 1.0)
	_text("V / APPLIED ↔ SUPERSEDED REAL CHAINS", ledger.position + Vector2(13.0, 108.0),
		8, C_MUTED, 720.0)


func _draw_side_panel() -> void:
	_draw_global_checkpoint_card()
	if _fixture == FIXTURE_SCOPE:
		_draw_scope_side()
	elif _fixture == FIXTURE_FLEX:
		if _flex_commit_view:
			_draw_proposal_side(_flex_proposal)
		else:
			_draw_flex_side()
	elif _fixture in [FIXTURE_SPRING, FIXTURE_AUTUMN, FIXTURE_WINTER]:
		_draw_proposal_side(_display_proposal())
	else:
		_draw_delivery_side()


func _draw_global_checkpoint_card() -> void:
	var card_rect := Rect2(880.0, 209.0, 360.0, 74.0)
	_card(card_rect, C_GOLD)
	_text("GLOBAL RP6 CHECKPOINT / READ ONLY ONCE", Vector2(894.0, 232.0), 10, C_GOLD)
	_text("SHARED / " + GLOBAL_NETWORK_SCOPE.to_upper(), Vector2(894.0, 255.0),
		9, C_TEXT, 330.0)
	_text("RECEIPT / " + _receipt_suffix(_global_network_checkpoint_receipt),
		Vector2(894.0, 274.0), 8, C_MUTED, 330.0)


func _draw_scope_side() -> void:
	var main := Rect2(880.0, 295.0, 360.0, 286.0)
	_card(main, C_GOLD)
	_text("THREE INDEPENDENT REGION OWNERS", Vector2(894.0, 319.0), 10, C_GOLD)
	for index in range(WINDOW_KEYS.size()):
		var key := String(WINDOW_KEYS[index])
		var adapter: Dictionary = (_baseline_evidence.get("by_key", {}) as Dictionary).get(
			key, {}
		) as Dictionary
		var row := Rect2(894.0, 337.0 + float(index) * 68.0, 330.0, 57.0)
		var color := _action_color(index)
		draw_rect(row, C_CARD_HI)
		draw_rect(row, color, false, 1.0)
		_text(String((_window_for_key(key)).get("label", "")), row.position + Vector2(9.0, 19.0),
			9, color, 170.0)
		_text("ADAPTER / " + _receipt_suffix(String(adapter.get("adapter_receipt", ""))),
			row.position + Vector2(180.0, 19.0), 8, C_MUTED, 140.0,
			HORIZONTAL_ALIGNMENT_RIGHT)
		_text(String(REGION_SCOPES[key]).to_upper(), row.position + Vector2(9.0, 41.0),
			8, C_TEXT, 310.0)
	_text("NO WINDOW OWNS A COPY OF GLOBAL NETWORK STATE", Vector2(894.0, 562.0),
		8, C_MUTED, 330.0)
	var proof := Rect2(880.0, 593.0, 360.0, 72.0)
	_card(proof, C_EDGE_HI)
	_text("PRODUCT DECISION", Vector2(894.0, 617.0), 9, C_MUTED)
	_text("ONE COMMAND SLOT / WHICH STRATEGIC AXIS?", Vector2(894.0, 646.0),
		12, C_GOLD, 330.0)


func _draw_flex_side() -> void:
	var fixture := _display_flex_fixture()
	var board: Dictionary = fixture.get("board", {}) as Dictionary
	var command: Dictionary = fixture.get("command_anchor", {}) as Dictionary
	var main := Rect2(880.0, 295.0, 360.0, 286.0)
	_card(main, C_TEAL)
	_text("%s / NO SCALAR SCORE" % String(board.get("decision_status", "")).to_upper(),
		Vector2(894.0, 319.0), 10, C_TEAL)
	_text("SLOT %d  /  CAPACITY %d" % [int(command.get("command_slots_before", 0)),
		int(command.get("capacity_units_before", 0))], Vector2(894.0, 350.0),
		16, C_TEXT, 330.0)
	for index in range(ACTIONS.size()):
		var action := String(ACTIONS[index])
		var option := _option_for_action(board, action)
		var row := Rect2(894.0, 369.0 + float(index) * 57.0, 330.0, 48.0)
		var selected := index == _selected_action
		var color := _action_color(index)
		draw_rect(row, C_CARD_HI if selected else C_CARD)
		draw_rect(row, color if selected else C_EDGE, false, 1.0)
		_text(String(ACTION_LABELS[index]), row.position + Vector2(9.0, 19.0),
			9, color if selected else C_MUTED, 165.0)
		_text("COST %d" % int(option.get("capacity_cost", 0)),
			row.position + Vector2(180.0, 19.0), 9, C_GOLD, 140.0,
			HORIZONTAL_ALIGNMENT_RIGHT)
		_text(_benefit_copy(option.get("benefit", {}) as Dictionary),
			row.position + Vector2(9.0, 39.0), 8, C_TEXT, 311.0)
	_text("FAVORED COST 2 / OFFSEASON COST 3", Vector2(894.0, 561.0),
		8, C_MUTED, 330.0)
	var proof := Rect2(880.0, 593.0, 360.0, 72.0)
	_card(proof, _action_color(_selected_action))
	_text("SELECTED CURSOR / " + String(ACTIONS[_selected_action]).to_upper(),
		Vector2(894.0, 617.0), 9, _action_color(_selected_action), 330.0)
	_text("ENTER / SPACE BUILDS A REAL JOINT PROPOSAL", Vector2(894.0, 646.0),
		9, C_MUTED, 330.0)


func _draw_proposal_side(proposal: Dictionary) -> void:
	var directive: Dictionary = proposal.get("directive_record", {}) as Dictionary
	var command_delta: Dictionary = proposal.get("command_owner_delta", {}) as Dictionary
	var origin_delta: Dictionary = proposal.get("origin_region_delta", {}) as Dictionary
	var consequence: Dictionary = proposal.get("consequence_record", {}) as Dictionary
	var action := String(directive.get("action", ""))
	var action_index := ACTIONS.find(action)
	var color := _action_color(action_index)
	var main := Rect2(880.0, 295.0, 360.0, 286.0)
	_card(main, color)
	_text("JOINT COMMIT PROPOSAL / THREE OWNERS", Vector2(894.0, 319.0), 10, color)
	var origin_window := _window_for_id(String(directive.get("origin_window_id", "")))
	_text(String(origin_window.get("label", "")), Vector2(894.0, 350.0), 17, C_TEXT, 330.0)
	_text(action.to_upper() + " DIRECTIVE / PROPOSAL ONLY", Vector2(894.0, 371.0),
		9, C_MUTED, 330.0)
	_draw_delta_row(405.0, "COMMAND SLOTS", int(command_delta.get("command_slots_before", 0)),
		int(command_delta.get("command_slots_after", 0)), C_GOLD)
	_draw_delta_row(432.0, "CAPACITY", int(command_delta.get("capacity_units_before", 0)),
		int(command_delta.get("capacity_units_after", 0)), C_GOLD)
	var track := String(origin_delta.get("primary_track", ""))
	var before_signals: Dictionary = origin_delta.get("before_signals", {}) as Dictionary
	var after_signals: Dictionary = origin_delta.get("after_signals", {}) as Dictionary
	_draw_delta_row(459.0, _primary_track_label(track), int(before_signals.get(track, 0)),
		int(after_signals.get(track, 0)), color)
	_draw_delta_row(486.0, "FACTION ACCESS", int(before_signals.get("faction_access", 0)),
		int(after_signals.get("faction_access", 0)), C_TEAL)
	var target_window := _window_for_id(String(consequence.get("target_window_id", "")))
	_text("PENDING / %s / EPOCH %d" % [String(target_window.get("label", "")),
		int(consequence.get("release_epoch", 0))], Vector2(894.0, 524.0), 9, C_TEAL, 330.0)
	_text("OWNER ORDER / " + " + ".join(proposal.get("owner_order", []) as Array),
		Vector2(894.0, 551.0), 8, C_MUTED, 330.0)
	var proof := Rect2(880.0, 593.0, 360.0, 72.0)
	_card(proof, color)
	_text("AUTHORITY BOUNDARY", Vector2(894.0, 617.0), 9, C_MUTED)
	_text("RECEIVER MUST CAS ALL THREE OWNER DELTAS", Vector2(894.0, 646.0),
		9, color, 330.0)


func _draw_delivery_side() -> void:
	var chain := _display_chain()
	var delivery: Dictionary = chain.get("delivery", {}) as Dictionary
	var target_delta: Dictionary = delivery.get("target_region_delta", {}) as Dictionary
	var projection: Dictionary = chain.get("delivered_projection", {}) as Dictionary
	var status := String(delivery.get("delivery_status", ""))
	var color := C_DANGER if status == "superseded" else C_TEAL
	var main := Rect2(880.0, 295.0, 360.0, 286.0)
	_card(main, color)
	_text("STAGE 2 CONSEQUENCE DELIVERY", Vector2(894.0, 319.0), 10, color)
	_text(status.to_upper(), Vector2(894.0, 351.0), 18, C_TEXT)
	_text("OWNER ORDER / " + " + ".join(delivery.get("owner_order", []) as Array),
		Vector2(894.0, 377.0), 9, C_MUTED, 330.0)
	_text("FRESH TARGET / MERIDIAN TRADE", Vector2(894.0, 405.0), 10, C_GOLD, 330.0)
	_text("CHECKPOINT / " + _receipt_suffix(String(
		(chain.get("target_acceptance", {}) as Dictionary).get(
			"accepted_region_checkpoint_receipt", ""
		)
	)), Vector2(894.0, 425.0), 8, C_MUTED, 330.0)
	var track := String(target_delta.get("track", ""))
	var before_signals: Dictionary = target_delta.get("before_signals", {}) as Dictionary
	var after_signals: Dictionary = target_delta.get("after_signals", {}) as Dictionary
	_draw_delta_row(459.0, _primary_track_label(track), int(before_signals.get(track, 0)),
		int(after_signals.get(track, 0)), color)
	_draw_delta_row(486.0, "REQUEST / APPLIED", int(target_delta.get("requested_delta", 0)),
		int(target_delta.get("applied_delta", 0)), color)
	_text("PENDING %d  /  DELIVERABLE %d  /  DELIVERED %d" % [
		(projection.get("pending", []) as Array).size(),
		(projection.get("deliverable", []) as Array).size(),
		(projection.get("delivered", []) as Array).size()],
		Vector2(894.0, 525.0), 9, C_TEXT, 330.0)
	var boundary_copy := "TARGET CHANGED / LEDGER CLOSED"
	if status == "superseded":
		boundary_copy = "TARGET UNCHANGED / PENDING STILL CLOSED"
	_text(boundary_copy, Vector2(894.0, 553.0), 9, color, 330.0)
	var proof := Rect2(880.0, 593.0, 360.0, 72.0)
	_card(proof, color)
	_text("ABSTRACT LEDGER DELIVERY", Vector2(894.0, 617.0), 9, C_MUTED)
	_text("PROPOSAL ONLY / V TOGGLE REAL HOSTILE SIBLING", Vector2(894.0, 646.0),
		9, color, 330.0)


func _display_state() -> Dictionary:
	if _fixture == FIXTURE_FLEX:
		return _display_flex_fixture().get("state", {}) as Dictionary
	if _fixture in [FIXTURE_SPRING, FIXTURE_AUTUMN, FIXTURE_WINTER]:
		return _display_tight_fixture().get("state", {}) as Dictionary
	if _fixture == FIXTURE_DELIVERY:
		var chain := _display_chain()
		if _chain_step == STAGE_COMMIT:
			return (chain.get("commit", {}) as Dictionary).get("after_state", {}) as Dictionary
		if _chain_step in [STAGE_ADVANCE, STAGE_PROJECTION]:
			return chain.get("advanced_state", {}) as Dictionary
		return (chain.get("delivery", {}) as Dictionary).get("after_state", {}) as Dictionary
	return _initial_state


func _display_capacity() -> int:
	if _fixture == FIXTURE_FLEX:
		return int((_display_flex_fixture().get("command_anchor", {}) as Dictionary).get(
			"capacity_units_before", 0
		))
	if _fixture in [FIXTURE_SPRING, FIXTURE_AUTUMN, FIXTURE_WINTER]:
		return int((_display_tight_fixture().get("command_anchor", {}) as Dictionary).get(
			"capacity_units_before", 0
		))
	if _fixture == FIXTURE_DELIVERY:
		return 2
	return 0


func _face_is_emphasized(index: int) -> bool:
	if _fixture == FIXTURE_SCOPE:
		return true
	if _fixture == FIXTURE_FLEX:
		return index == _selected_action
	if _fixture in [FIXTURE_SPRING, FIXTURE_AUTUMN, FIXTURE_WINTER]:
		return index == _fixture - FIXTURE_SPRING
	if _fixture == FIXTURE_DELIVERY:
		return index in [0, 1]
	return false


func _benefit_copy(benefit: Dictionary) -> String:
	for key in ["relief", "commerce", "defense"]:
		if int(benefit.get(key, 0)) > 0:
			return String(key).to_upper() + " +%d" % int(benefit.get(key, 0))
	return "NO BENEFIT"


func _primary_track_label(track: String) -> String:
	return track.trim_suffix("_pressure").replace("_", " ").to_upper()


func _draw_delta_row(y: float, label: String, before: int, after: int,
		color: Color) -> void:
	_text(label, Vector2(894.0, y), 9, C_MUTED, 190.0)
	_text("%d  ->  %d" % [before, after], Vector2(1084.0, y), 11,
		color if before != after else C_MUTED, 140.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _card(card_rect: Rect2, accent: Color) -> void:
	draw_rect(Rect2(card_rect.position + Vector2(3.0, 4.0), card_rect.size),
		Color(0.0, 0.0, 0.0, 0.28))
	draw_rect(card_rect, C_CARD)
	draw_rect(card_rect, C_EDGE, false, 1.0)
	draw_rect(Rect2(card_rect.position, Vector2(5.0, card_rect.size.y)), accent)


func _fixture_color(index: int) -> Color:
	match index:
		FIXTURE_SPRING:
			return C_TEAL
		FIXTURE_AUTUMN:
			return C_GOLD
		FIXTURE_WINTER:
			return C_BLUE
		FIXTURE_DELIVERY:
			return C_DANGER if _show_superseded else C_TEAL
	return C_GOLD if index == FIXTURE_SCOPE else C_EDGE_HI


func _action_color(index: int) -> Color:
	match index:
		0:
			return C_TEAL
		1:
			return C_GOLD
		2:
			return C_BLUE
	return C_MUTED


func _draw_footer() -> void:
	draw_rect(Rect2(0.0, 704.0, 1280.0, 64.0), C_HEADER)
	draw_line(Vector2(0.0, 704.0), Vector2(1280.0, 704.0), C_EDGE, 1.0)
	_fixture_rects.clear()
	for index in range(FIXTURE_TITLES.size()):
		var tab_rect := Rect2(24.0 + float(index) * 114.0, 719.0, 108.0, 33.0)
		_fixture_rects.append(tab_rect)
		var selected := index == _fixture
		var color := _fixture_color(index)
		draw_rect(tab_rect, color.darkened(0.58) if selected else C_CARD_HI)
		draw_rect(tab_rect, color if selected else C_EDGE, false, 1.0)
		_text(String(FIXTURE_TITLES[index]), tab_rect.position + Vector2(6.0, 22.0),
			8, C_TEXT if selected else C_MUTED, tab_rect.size.x - 12.0,
			HORIZONTAL_ALIGNMENT_CENTER)
	_action_rects.clear()
	for index in range(ACTION_LABELS.size()):
		var action_rect := Rect2(714.0 + float(index) * 176.0, 719.0, 170.0, 33.0)
		_action_rects.append(action_rect)
		var selected := index == _selected_action
		var color := _action_color(index)
		draw_rect(action_rect, color.darkened(0.62) if selected else C_CARD_HI)
		draw_rect(action_rect, color if selected else C_EDGE, false, 1.0)
		_text(String(ACTION_LABELS[index]), action_rect.position + Vector2(7.0, 22.0),
			8, C_TEXT if selected else C_MUTED, action_rect.size.x - 14.0,
			HORIZONTAL_ALIGNMENT_CENTER)


func _text(copy: String, baseline: Vector2, size: int, color: Color,
		width: float = -1.0,
		alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(_font, baseline, copy, alignment, width, size, color)


func _unhandled_input(event: InputEvent) -> void:
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
			_set_fixture(int(key_event.keycode) - int(KEY_A))
		KEY_1, KEY_2, KEY_3:
			_set_action(int(key_event.keycode) - int(KEY_1))
		KEY_BRACKETLEFT:
			_cycle_epoch(-1)
		KEY_BRACKETRIGHT:
			_cycle_epoch(1)
		KEY_UP:
			_set_capacity(3)
		KEY_DOWN:
			_set_capacity(2)
		KEY_TAB:
			_set_fixture((_fixture + 1) % 6)
		KEY_ENTER, KEY_SPACE:
			_advance_ui()
		KEY_V:
			if _fixture == FIXTURE_DELIVERY:
				_show_superseded = not _show_superseded
				queue_redraw()
		KEY_R:
			_load_ok = _build_real_fixtures()
			queue_redraw()


func _set_fixture(value: int) -> void:
	_fixture = clampi(value, FIXTURE_SCOPE, FIXTURE_DELIVERY)
	_flex_commit_view = false
	_flex_proposal.clear()
	_chain_step = STAGE_DELIVERY
	_sync_selection_to_fixture()
	queue_redraw()


func _set_action(value: int) -> void:
	_selected_action = clampi(value, 0, ACTIONS.size() - 1)
	_flex_commit_view = false
	_flex_proposal.clear()
	if _fixture in [FIXTURE_SPRING, FIXTURE_AUTUMN, FIXTURE_WINTER]:
		_set_fixture(FIXTURE_SPRING + _selected_action)
	else:
		queue_redraw()


func _cycle_epoch(delta: int) -> void:
	_epoch_index = posmod(_epoch_index + delta, SEASONS.size())
	_flex_commit_view = false
	_flex_proposal.clear()
	if _fixture in [FIXTURE_SPRING, FIXTURE_AUTUMN, FIXTURE_WINTER]:
		_fixture = FIXTURE_SPRING + _epoch_index
		_selected_action = _epoch_index
	queue_redraw()


func _set_capacity(value: int) -> void:
	_flex_commit_view = false
	_flex_proposal.clear()
	if value == 3:
		_fixture = FIXTURE_FLEX
	else:
		_fixture = FIXTURE_SPRING + _epoch_index
		_selected_action = _epoch_index
	queue_redraw()


func _advance_ui() -> void:
	if _fixture == FIXTURE_SCOPE:
		_set_fixture(FIXTURE_FLEX)
	elif _fixture == FIXTURE_FLEX:
		if _flex_commit_view:
			_flex_commit_view = false
			_flex_proposal.clear()
		else:
			_flex_commit_view = _build_selected_flex_proposal()
		queue_redraw()
	elif _fixture in [FIXTURE_SPRING, FIXTURE_AUTUMN, FIXTURE_WINTER]:
		_fixture = FIXTURE_DELIVERY
		_chain_step = STAGE_COMMIT
		_sync_selection_to_fixture()
		queue_redraw()
	else:
		_chain_step = (_chain_step + 1) % 4
		queue_redraw()


func _handle_click(click_position: Vector2) -> void:
	for index in range(_fixture_rects.size()):
		if _fixture_rects[index].has_point(click_position):
			_set_fixture(index)
			return
	for index in range(_action_rects.size()):
		if _action_rects[index].has_point(click_position):
			_set_action(index)
			return


func _save_shot() -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("PlanetCampaignLab could not capture the viewport")
		get_tree().quit(1)
		return
	var save_error := image.save_png(_shot_path)
	if save_error != OK:
		push_error("PlanetCampaignLab could not save screenshot: %s" % error_string(save_error))
		get_tree().quit(1)
		return
	get_tree().quit()
