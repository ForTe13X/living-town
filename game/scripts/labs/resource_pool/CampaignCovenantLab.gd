extends Node2D

const PlanetCampaignModel = preload(
	"res://scripts/labs/resource_pool/PlanetCampaignModel.gd"
)
const CampaignCovenantModel = preload(
	"res://scripts/labs/resource_pool/CampaignCovenantModel.gd"
)

const DESIGN := Vector2(1280.0, 768.0)
const HEADER_RECT := Rect2(0.0, 0.0, 1280.0, 72.0)
const MAIN_PANEL := Rect2(24.0, 170.0, 824.0, 512.0)
const SIDE_PANEL := Rect2(864.0, 170.0, 392.0, 512.0)

const FIXTURE_BOARD := 0
const FIXTURE_DUE := 1
const FIXTURE_AMENDED := 2
const FIXTURE_WATCH_HONORED := 3
const FIXTURE_WITHDRAWN := 4
const FIXTURE_EXCHANGE_HONORED := 5

const VIEW_BEFORE := 0
const VIEW_PROPOSAL := 1
const VIEW_AFTER := 2

const GLOBAL_NETWORK_SCOPE := "ashfall_settlement_network"
const CAMPAIGN_OWNER_SCOPE := "ashfall_planet_campaign"
const COMMAND_OWNER_SCOPE := "ashfall_campaign_command"
const WINDOW_KEYS := ["basin_relief", "meridian_trade", "nightward_fortify"]
const COVENANT_KEYS := ["relief_guarantee", "exchange_charter", "watch_compact"]
const ACTIONS := ["aid", "trade", "fortify"]
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
	"A  SPRING", "B  DUE", "C  AMENDED", "D  WATCH",
	"E  WITHDRAW", "F  EXCHANGE",
]
const FIXTURE_SUBTITLES := [
	"choose one", "autumn / cap 2", "due -> winter", "honored / bounded",
	"cost -2", "honored / bounded",
]
const COVENANT_SHORT := ["RELIEF", "EXCHANGE", "WATCH"]

var _font: Font
var _campaign_catalog: Dictionary = {}
var _covenant_catalog: Dictionary = {}
var _campaign_initial: Dictionary = {}
var _covenant_initial: Dictionary = {}
var _global_checkpoint := ""
var _bind_evidence: Dictionary = {}
var _spring_board: Dictionary = {}
var _binds: Dictionary = {}
var _spring_advance: Dictionary = {}
var _autumn_campaign: Dictionary = {}
var _autumn_advance: Dictionary = {}
var _winter_campaign: Dictionary = {}
var _watch_chain: Dictionary = {}
var _relief_chain: Dictionary = {}
var _exchange_chain: Dictionary = {}
var _low_access_chain: Dictionary = {}
var _fixture := FIXTURE_BOARD
var _selected_covenant := 2
var _view_stage := VIEW_AFTER
var _show_low_access := false
var _shot_path := ""
var _load_ok := false
var _fixture_rects: Array[Rect2] = []
var _covenant_rects: Array[Rect2] = []


func _ready() -> void:
	_font = ThemeDB.fallback_font
	var requested_fixture := FIXTURE_BOARD
	var requested_key := "watch_compact"
	var requested_epoch := ""
	var requested_capacity := 0
	var requested_action := ""
	var requested_view := "after"
	var requested_delta := "superseded"
	var args := OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		var argument := String(args[index])
		if argument == "--covenant-fixture" and index + 1 < args.size():
			index += 1
			requested_fixture = _fixture_from_argument(String(args[index]))
		elif argument.begins_with("--covenant-fixture="):
			requested_fixture = _fixture_from_argument(
				argument.trim_prefix("--covenant-fixture=")
			)
		elif argument == "--covenant-key" and index + 1 < args.size():
			index += 1
			requested_key = String(args[index])
		elif argument.begins_with("--covenant-key="):
			requested_key = argument.trim_prefix("--covenant-key=")
		elif argument == "--covenant-epoch" and index + 1 < args.size():
			index += 1
			requested_epoch = String(args[index])
		elif argument.begins_with("--covenant-epoch="):
			requested_epoch = argument.trim_prefix("--covenant-epoch=")
		elif argument == "--covenant-capacity" and index + 1 < args.size():
			index += 1
			requested_capacity = int(String(args[index]))
		elif argument.begins_with("--covenant-capacity="):
			requested_capacity = int(argument.trim_prefix("--covenant-capacity="))
		elif argument == "--covenant-action" and index + 1 < args.size():
			index += 1
			requested_action = String(args[index])
		elif argument.begins_with("--covenant-action="):
			requested_action = argument.trim_prefix("--covenant-action=")
		elif argument == "--covenant-view" and index + 1 < args.size():
			index += 1
			requested_view = String(args[index])
		elif argument.begins_with("--covenant-view="):
			requested_view = argument.trim_prefix("--covenant-view=")
		elif argument == "--covenant-region-delta" and index + 1 < args.size():
			index += 1
			requested_delta = String(args[index])
		elif argument.begins_with("--covenant-region-delta="):
			requested_delta = argument.trim_prefix("--covenant-region-delta=")
		elif argument == "--lab-shot" and index + 1 < args.size():
			index += 1
			_shot_path = String(args[index])
		elif argument.begins_with("--lab-shot="):
			_shot_path = argument.trim_prefix("--lab-shot=")
		index += 1
	_fixture = _fixture_from_overrides(
		requested_fixture, requested_epoch, requested_capacity, requested_action
	)
	_selected_covenant = _key_index(requested_key)
	_view_stage = _view_from_argument(requested_view)
	_show_low_access = requested_delta.strip_edges().to_lower() == "applied"
	_load_ok = _build_real_fixtures()
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
		"a", "1", "spring", "board", "bind":
			return FIXTURE_BOARD
		"b", "2", "due", "tight":
			return FIXTURE_DUE
		"c", "3", "amended", "amend":
			return FIXTURE_AMENDED
		"d", "4", "watch", "watch_honored":
			return FIXTURE_WATCH_HONORED
		"e", "5", "withdraw", "withdrawn", "relief":
			return FIXTURE_WITHDRAWN
		"f", "6", "exchange", "terminal", "superseded":
			return FIXTURE_EXCHANGE_HONORED
	return FIXTURE_BOARD


func _fixture_from_overrides(base_fixture: int, epoch: String, capacity: int,
		action: String) -> int:
	var normalized_epoch := epoch.strip_edges().to_lower()
	var normalized_action := action.strip_edges().to_lower()
	if normalized_action == "amend":
		return FIXTURE_AMENDED
	if normalized_action == "withdraw":
		return FIXTURE_WITHDRAWN
	if normalized_action == "honor" and normalized_epoch == "winter":
		return FIXTURE_WATCH_HONORED
	if normalized_action == "honor":
		return FIXTURE_EXCHANGE_HONORED
	if normalized_epoch in ["autumn", "1"] and capacity == 2:
		return FIXTURE_DUE
	if normalized_epoch in ["spring", "0"]:
		return FIXTURE_BOARD
	return base_fixture


func _key_index(value: String) -> int:
	match value.strip_edges().to_lower():
		"relief", "relief_guarantee", "aid", "basin", "basin_relief":
			return 0
		"exchange", "exchange_charter", "trade", "meridian", "meridian_trade":
			return 1
		"watch", "watch_compact", "fortify", "nightward", "nightward_fortify":
			return 2
	return 2


func _view_from_argument(value: String) -> int:
	match value.strip_edges().to_lower():
		"before", "0":
			return VIEW_BEFORE
		"proposal", "1":
			return VIEW_PROPOSAL
	return VIEW_AFTER


func _build_real_fixtures() -> bool:
	_campaign_catalog = PlanetCampaignModel.make_catalog(
		PlanetCampaignModel.DEFAULT_ROOT_SEED
	)
	_covenant_catalog = CampaignCovenantModel.make_catalog(_campaign_catalog)
	_campaign_initial = PlanetCampaignModel.make_initial_state(_campaign_catalog)
	_covenant_initial = CampaignCovenantModel.make_initial_state(_covenant_catalog)
	_global_checkpoint = _external_receipt("global-rp6-network")
	if _campaign_catalog.is_empty() or _covenant_catalog.is_empty() \
			or _campaign_initial.is_empty() or _covenant_initial.is_empty() \
			or _global_checkpoint == "":
		push_error("CampaignCovenantLab could not build accepted catalogs and anchors")
		return false
	_bind_evidence = _make_evidence_bundle(BASELINE_SIGNALS, "rp8-bind")
	_spring_board = _make_covenant_board(
		_covenant_initial, _campaign_initial, _bind_evidence
	)
	if _bind_evidence.is_empty() or _spring_board.is_empty() \
			or String(_spring_board.get("decision_status", "")) \
			!= "covenants_available" \
			or (_spring_board.get("options", []) as Array).size() != 3:
		push_error("CampaignCovenantLab could not build the spring covenant board")
		return false
	_binds.clear()
	for key_value in COVENANT_KEYS:
		var key := String(key_value)
		var branch := _make_bind_branch(
			key, _covenant_initial, _spring_board, _bind_evidence
		)
		if branch.is_empty():
			push_error("CampaignCovenantLab could not bind %s" % key)
			return false
		_binds[key] = branch
	_spring_advance = PlanetCampaignModel.advance_epoch(
		_campaign_catalog, _campaign_initial,
		String(_campaign_initial.get("state_receipt", ""))
	)
	_autumn_campaign = _spring_advance.get("after_state", {}) as Dictionary
	_autumn_advance = PlanetCampaignModel.advance_epoch(
		_campaign_catalog, _autumn_campaign,
		String(_autumn_campaign.get("state_receipt", ""))
	)
	_winter_campaign = _autumn_advance.get("after_state", {}) as Dictionary
	if _spring_advance.is_empty() or _autumn_campaign.is_empty() \
			or _autumn_advance.is_empty() or _winter_campaign.is_empty():
		push_error("CampaignCovenantLab could not build accepted epoch evidence")
		return false
	_watch_chain = _build_watch_chain()
	_relief_chain = _build_relief_chain()
	_exchange_chain = _build_exchange_chain(false)
	_low_access_chain = _build_exchange_chain(true)
	if _watch_chain.is_empty() or _relief_chain.is_empty() \
			or _exchange_chain.is_empty() or _low_access_chain.is_empty():
		push_error("CampaignCovenantLab could not build all covenant fixture chains")
		return false
	return _validate_real_fixtures()


func _make_covenant_board(covenant_state: Dictionary,
		campaign_state: Dictionary, evidence: Dictionary) -> Dictionary:
	return CampaignCovenantModel.make_covenant_board(
		_covenant_catalog, covenant_state,
		String(covenant_state.get("state_receipt", "")), _campaign_catalog,
		campaign_state, String(campaign_state.get("state_receipt", "")),
		CAMPAIGN_OWNER_SCOPE, evidence.get("adapters", []) as Array,
		evidence.get("acceptances", []) as Array, GLOBAL_NETWORK_SCOPE,
		_global_checkpoint
	)


func _make_bind_branch(key: String, covenant_state: Dictionary,
		board: Dictionary, evidence: Dictionary) -> Dictionary:
	var option := _covenant_option_for_key(board, key)
	var choice := CampaignCovenantModel.make_covenant_choice(
		board, String(option.get("option_id", ""))
	)
	var proposal := CampaignCovenantModel.bind_covenant(
		_covenant_catalog, covenant_state,
		String(covenant_state.get("state_receipt", "")), _campaign_catalog,
		_campaign_initial, String(_campaign_initial.get("state_receipt", "")),
		CAMPAIGN_OWNER_SCOPE, evidence.get("adapters", []) as Array,
		evidence.get("acceptances", []) as Array, GLOBAL_NETWORK_SCOPE,
		_global_checkpoint, board, choice
	)
	if option.is_empty() or choice.is_empty() or proposal.is_empty():
		return {}
	return {
		"key": key, "state": covenant_state, "board": board,
		"evidence": evidence, "option": option, "choice": choice,
		"proposal": proposal, "after_state": proposal.get("after_state", {}),
	}


func _build_watch_chain() -> Dictionary:
	var bind_branch: Dictionary = _binds.get("watch_compact", {}) as Dictionary
	var bind_proposal: Dictionary = bind_branch.get("proposal", {}) as Dictionary
	var bound_state: Dictionary = bind_proposal.get("after_state", {}) as Dictionary
	var due_projection := _project(bound_state, _autumn_campaign)
	var bind_delta: Dictionary = bind_proposal.get(
		"faction_region_delta", {}
	) as Dictionary
	var amend_evidence := _make_single_evidence(
		"nightward_fortify",
		(bind_delta.get("after_signals", {}) as Dictionary).duplicate(true),
		"fresh-watch-amend-nightward_fortify"
	)
	var amend_proposal := CampaignCovenantModel.amend_covenant(
		_covenant_catalog, bound_state, String(bound_state.get("state_receipt", "")),
		_campaign_catalog, _autumn_campaign,
		String(_autumn_campaign.get("state_receipt", "")), CAMPAIGN_OWNER_SCOPE,
		amend_evidence.get("adapter", {}) as Dictionary,
		amend_evidence.get("acceptance", {}) as Dictionary, GLOBAL_NETWORK_SCOPE,
		_global_checkpoint
	)
	var amended_state: Dictionary = amend_proposal.get("after_state", {}) as Dictionary
	var amended_projection := _project(amended_state, _autumn_campaign)
	var amend_delta: Dictionary = amend_proposal.get(
		"faction_region_delta", {}
	) as Dictionary
	var watch_signals := _signals_with_replacement(
		BASELINE_SIGNALS, "nightward_fortify",
		amend_delta.get("after_signals", {}) as Dictionary
	)
	var campaign_evidence := _make_evidence_bundle(watch_signals, "watch-rp7")
	var rp7_commit := _make_campaign_commit(
		_winter_campaign, 2, "fortify", campaign_evidence,
		"rp8-command-watch-fortify"
	)
	var committed_campaign: Dictionary = (
		rp7_commit.get("proposal", {}) as Dictionary
	).get("after_state", {}) as Dictionary
	var origin_delta: Dictionary = (
		rp7_commit.get("proposal", {}) as Dictionary
	).get("origin_region_delta", {}) as Dictionary
	var honor_evidence := _make_single_evidence(
		"nightward_fortify",
		(origin_delta.get("after_signals", {}) as Dictionary).duplicate(true),
		"fresh-watch-honor-nightward_fortify"
	)
	var honor_projection := _project(amended_state, committed_campaign)
	var honor_proposal := CampaignCovenantModel.resolve_covenant(
		_covenant_catalog, amended_state,
		String(amended_state.get("state_receipt", "")), _campaign_catalog,
		committed_campaign, String(committed_campaign.get("state_receipt", "")),
		CAMPAIGN_OWNER_SCOPE, honor_evidence.get("adapter", {}) as Dictionary,
		honor_evidence.get("acceptance", {}) as Dictionary, GLOBAL_NETWORK_SCOPE,
		_global_checkpoint, "honor"
	)
	var terminal_state: Dictionary = honor_proposal.get("after_state", {}) as Dictionary
	var terminal_projection := _project(terminal_state, committed_campaign)
	if bound_state.is_empty() or due_projection.is_empty() \
			or amend_evidence.is_empty() or amend_proposal.is_empty() \
			or amended_projection.is_empty() or campaign_evidence.is_empty() \
			or rp7_commit.is_empty() or committed_campaign.is_empty() \
			or honor_evidence.is_empty() or honor_projection.is_empty() \
			or honor_proposal.is_empty() or terminal_projection.is_empty():
		return {}
	return {
		"bind": bind_branch, "bound_state": bound_state,
		"due_projection": due_projection, "amend_evidence": amend_evidence,
		"amend": amend_proposal, "amended_state": amended_state,
		"amended_projection": amended_projection, "campaign_evidence": campaign_evidence,
		"rp7_commit": rp7_commit, "committed_campaign": committed_campaign,
		"honor_evidence": honor_evidence, "honor_projection": honor_projection,
		"honor": honor_proposal, "terminal_state": terminal_state,
		"terminal_projection": terminal_projection,
	}


func _build_relief_chain() -> Dictionary:
	var bind_branch: Dictionary = _binds.get("relief_guarantee", {}) as Dictionary
	var bind_proposal: Dictionary = bind_branch.get("proposal", {}) as Dictionary
	var bound_state: Dictionary = bind_proposal.get("after_state", {}) as Dictionary
	var due_projection := _project(bound_state, _autumn_campaign)
	var bind_delta: Dictionary = bind_proposal.get(
		"faction_region_delta", {}
	) as Dictionary
	var relief_signals := _signals_with_replacement(
		BASELINE_SIGNALS, "basin_relief",
		bind_delta.get("after_signals", {}) as Dictionary
	)
	var campaign_evidence := _make_evidence_bundle(relief_signals, "relief-rp7")
	var withdraw_evidence := _make_single_evidence(
		"basin_relief",
		(bind_delta.get("after_signals", {}) as Dictionary).duplicate(true),
		"fresh-relief-withdraw-basin_relief"
	)
	var withdraw_proposal := CampaignCovenantModel.resolve_covenant(
		_covenant_catalog, bound_state, String(bound_state.get("state_receipt", "")),
		_campaign_catalog, _autumn_campaign,
		String(_autumn_campaign.get("state_receipt", "")), CAMPAIGN_OWNER_SCOPE,
		withdraw_evidence.get("adapter", {}) as Dictionary,
		withdraw_evidence.get("acceptance", {}) as Dictionary, GLOBAL_NETWORK_SCOPE,
		_global_checkpoint, "withdraw"
	)
	var terminal_state: Dictionary = withdraw_proposal.get("after_state", {}) as Dictionary
	var terminal_projection := _project(terminal_state, _autumn_campaign)
	if bound_state.is_empty() or due_projection.is_empty() \
			or campaign_evidence.is_empty() or withdraw_evidence.is_empty() \
			or withdraw_proposal.is_empty() or terminal_projection.is_empty():
		return {}
	return {
		"bind": bind_branch, "bound_state": bound_state,
		"due_projection": due_projection, "campaign_evidence": campaign_evidence,
		"withdraw_evidence": withdraw_evidence, "withdraw": withdraw_proposal,
		"terminal_state": terminal_state, "terminal_projection": terminal_projection,
	}


func _build_exchange_chain(low_access: bool) -> Dictionary:
	var bind_branch: Dictionary
	if low_access:
		var low_signals: Dictionary = BASELINE_SIGNALS.duplicate(true)
		for key_value in WINDOW_KEYS:
			var key := String(key_value)
			var signals: Dictionary = (low_signals.get(key, {}) as Dictionary).duplicate(true)
			signals["faction_access"] = 0
			low_signals[key] = signals
		var low_bind_evidence := _make_evidence_bundle(low_signals, "rp8-low-bind")
		var low_board := _make_covenant_board(
			_covenant_initial, _campaign_initial, low_bind_evidence
		)
		bind_branch = _make_bind_branch(
			"exchange_charter", _covenant_initial, low_board, low_bind_evidence
		)
	else:
		bind_branch = _binds.get("exchange_charter", {}) as Dictionary
	var bind_proposal: Dictionary = bind_branch.get("proposal", {}) as Dictionary
	var bound_state: Dictionary = bind_proposal.get("after_state", {}) as Dictionary
	var bind_delta: Dictionary = bind_proposal.get(
		"faction_region_delta", {}
	) as Dictionary
	var base_signals: Dictionary = BASELINE_SIGNALS.duplicate(true)
	if low_access:
		for key_value in WINDOW_KEYS:
			var low_key := String(key_value)
			var low_region: Dictionary = (
				base_signals.get(low_key, {}) as Dictionary
			).duplicate(true)
			low_region["faction_access"] = 0
			base_signals[low_key] = low_region
	var exchange_signals := _signals_with_replacement(
		base_signals, "meridian_trade",
		bind_delta.get("after_signals", {}) as Dictionary
	)
	var evidence_prefix := "low-exchange-rp7" if low_access else "exchange-rp7"
	var campaign_evidence := _make_evidence_bundle(exchange_signals, evidence_prefix)
	var command_label := "rp8-command-low-exchange-trade" \
		if low_access else "rp8-command-exchange-trade"
	var rp7_commit := _make_campaign_commit(
		_autumn_campaign, 2, "trade", campaign_evidence, command_label
	)
	var committed_campaign: Dictionary = (
		rp7_commit.get("proposal", {}) as Dictionary
	).get("after_state", {}) as Dictionary
	var origin_delta: Dictionary = (
		rp7_commit.get("proposal", {}) as Dictionary
	).get("origin_region_delta", {}) as Dictionary
	var honor_label := "fresh-low-exchange-honor-meridian_trade" \
		if low_access else "fresh-exchange-honor-meridian_trade"
	var honor_evidence := _make_single_evidence(
		"meridian_trade",
		(origin_delta.get("after_signals", {}) as Dictionary).duplicate(true),
		honor_label
	)
	var honor_projection := _project(bound_state, committed_campaign)
	var honor_proposal := CampaignCovenantModel.resolve_covenant(
		_covenant_catalog, bound_state, String(bound_state.get("state_receipt", "")),
		_campaign_catalog, committed_campaign,
		String(committed_campaign.get("state_receipt", "")), CAMPAIGN_OWNER_SCOPE,
		honor_evidence.get("adapter", {}) as Dictionary,
		honor_evidence.get("acceptance", {}) as Dictionary, GLOBAL_NETWORK_SCOPE,
		_global_checkpoint, "honor"
	)
	var terminal_state: Dictionary = honor_proposal.get("after_state", {}) as Dictionary
	var terminal_projection := _project(terminal_state, committed_campaign)
	if bind_branch.is_empty() or bound_state.is_empty() or campaign_evidence.is_empty() \
			or rp7_commit.is_empty() or committed_campaign.is_empty() \
			or honor_evidence.is_empty() or honor_projection.is_empty() \
			or honor_proposal.is_empty() or terminal_projection.is_empty():
		return {}
	return {
		"low_access": low_access, "bind": bind_branch, "bound_state": bound_state,
		"campaign_evidence": campaign_evidence, "rp7_commit": rp7_commit,
		"committed_campaign": committed_campaign, "honor_evidence": honor_evidence,
		"honor_projection": honor_projection, "honor": honor_proposal,
		"terminal_state": terminal_state, "terminal_projection": terminal_projection,
	}


func _make_campaign_commit(campaign_state: Dictionary, capacity: int,
		action: String, evidence: Dictionary, command_label: String) -> Dictionary:
	var owner_checkpoint := _external_receipt(command_label)
	var command_anchor := PlanetCampaignModel.make_command_anchor(
		COMMAND_OWNER_SCOPE, owner_checkpoint,
		int(campaign_state.get("epoch_index", -1)), 1, capacity
	)
	var board := PlanetCampaignModel.make_directive_board(
		_campaign_catalog, campaign_state,
		String(campaign_state.get("state_receipt", "")),
		evidence.get("adapters", []) as Array,
		evidence.get("acceptances", []) as Array, GLOBAL_NETWORK_SCOPE,
		_global_checkpoint, command_anchor, COMMAND_OWNER_SCOPE, owner_checkpoint,
		String(command_anchor.get("anchor_receipt", ""))
	)
	var option := _campaign_option_for_action(board, action)
	var choice := PlanetCampaignModel.make_choice(
		board, String(option.get("option_id", ""))
	)
	var proposal := PlanetCampaignModel.commit_directive(
		_campaign_catalog, campaign_state,
		String(campaign_state.get("state_receipt", "")),
		evidence.get("adapters", []) as Array,
		evidence.get("acceptances", []) as Array, GLOBAL_NETWORK_SCOPE,
		_global_checkpoint, command_anchor, COMMAND_OWNER_SCOPE, owner_checkpoint,
		String(command_anchor.get("anchor_receipt", "")), board, choice
	)
	if owner_checkpoint == "" or command_anchor.is_empty() or board.is_empty() \
			or option.is_empty() or choice.is_empty() or proposal.is_empty():
		return {}
	if not PlanetCampaignModel.validate_commit_proposal(
		_campaign_catalog, campaign_state,
		String(campaign_state.get("state_receipt", "")),
		evidence.get("adapters", []) as Array,
		evidence.get("acceptances", []) as Array, GLOBAL_NETWORK_SCOPE,
		_global_checkpoint, command_anchor, COMMAND_OWNER_SCOPE, owner_checkpoint,
		String(command_anchor.get("anchor_receipt", "")), board, choice, proposal
	).is_empty():
		return {}
	return {
		"state": campaign_state, "capacity": capacity, "action": action,
		"evidence": evidence, "owner_checkpoint": owner_checkpoint,
		"command_anchor": command_anchor, "board": board, "choice": choice,
		"proposal": proposal,
	}


func _project(covenant_state: Dictionary, campaign_state: Dictionary) -> Dictionary:
	return CampaignCovenantModel.project_obligation(
		_covenant_catalog, covenant_state,
		String(covenant_state.get("state_receipt", "")), _campaign_catalog,
		campaign_state, String(campaign_state.get("state_receipt", "")),
		CAMPAIGN_OWNER_SCOPE
	)


func _make_evidence_bundle(signals_by_key: Dictionary, prefix: String) -> Dictionary:
	var adapters: Array[Dictionary] = []
	var acceptances: Array[Dictionary] = []
	var by_key := {}
	for key_value in WINDOW_KEYS:
		var key := String(key_value)
		var evidence := _make_single_evidence(
			key, (signals_by_key.get(key, {}) as Dictionary).duplicate(true),
			"%s-%s" % [prefix, key]
		)
		if evidence.is_empty():
			return {}
		adapters.append(evidence.get("adapter", {}) as Dictionary)
		acceptances.append(evidence.get("acceptance", {}) as Dictionary)
		by_key[key] = evidence
	return {"adapters": adapters, "acceptances": acceptances, "by_key": by_key}


func _make_single_evidence(key: String, signals: Dictionary,
		checkpoint_label: String) -> Dictionary:
	var window := _window_for_key(key)
	var region_scope := String(REGION_SCOPES.get(key, ""))
	var checkpoint := _external_receipt(checkpoint_label)
	var adapter := PlanetCampaignModel.make_window_adapter(
		_campaign_catalog, key, region_scope, checkpoint, GLOBAL_NETWORK_SCOPE,
		_global_checkpoint, signals
	)
	var acceptance := PlanetCampaignModel.make_window_acceptance(
		String(window.get("window_id", "")), region_scope, checkpoint,
		String(adapter.get("adapter_receipt", ""))
	)
	if window.is_empty() or checkpoint == "" or adapter.is_empty() \
			or acceptance.is_empty():
		return {}
	return {"adapter": adapter, "acceptance": acceptance}


func _signals_with_replacement(base: Dictionary, key: String,
		replacement: Dictionary) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	result[key] = replacement.duplicate(true)
	return result


func _window_for_key(key: String) -> Dictionary:
	for raw_window in _campaign_catalog.get("windows", []) as Array:
		var window: Dictionary = raw_window as Dictionary
		if String(window.get("window_key", "")) == key:
			return window
	return {}


func _covenant_for_key(key: String) -> Dictionary:
	for raw_covenant in _covenant_catalog.get("covenants", []) as Array:
		var covenant: Dictionary = raw_covenant as Dictionary
		if String(covenant.get("covenant_key", "")) == key:
			return covenant
	return {}


func _covenant_option_for_key(board: Dictionary, key: String) -> Dictionary:
	var covenant := _covenant_for_key(key)
	for raw_option in board.get("options", []) as Array:
		var option: Dictionary = raw_option as Dictionary
		if String(option.get("covenant_id", "")) \
				== String(covenant.get("covenant_id", "")):
			return option
	return {}


func _campaign_option_for_action(board: Dictionary, action: String) -> Dictionary:
	for raw_option in board.get("options", []) as Array:
		var option: Dictionary = raw_option as Dictionary
		if String(option.get("action", "")) == action:
			return option
	return {}


func _validate_real_fixtures() -> bool:
	if not PlanetCampaignModel.validate_catalog(_campaign_catalog).is_empty() \
			or not PlanetCampaignModel.validate_state(
				_campaign_catalog, _campaign_initial
			).is_empty() or not CampaignCovenantModel.validate_catalog(
				_campaign_catalog, _covenant_catalog
			).is_empty() or not CampaignCovenantModel.validate_state(
				_covenant_catalog, _covenant_initial
			).is_empty():
		push_error("CampaignCovenantLab catalog or initial state validation failed")
		return false
	if not CampaignCovenantModel.validate_covenant_board(
		_covenant_catalog, _covenant_initial,
		String(_covenant_initial.get("state_receipt", "")), _campaign_catalog,
		_campaign_initial, String(_campaign_initial.get("state_receipt", "")),
		CAMPAIGN_OWNER_SCOPE, _bind_evidence.get("adapters", []) as Array,
		_bind_evidence.get("acceptances", []) as Array, GLOBAL_NETWORK_SCOPE,
		_global_checkpoint, _spring_board
	).is_empty():
		push_error("CampaignCovenantLab spring board validation failed")
		return false
	for branch_value in _binds.values():
		if not _validate_bind_branch(branch_value as Dictionary):
			push_error("CampaignCovenantLab bind branch validation failed")
			return false
	if not PlanetCampaignModel.validate_epoch_advance(
		_campaign_catalog, _campaign_initial,
		String(_campaign_initial.get("state_receipt", "")), _spring_advance
	).is_empty() or not PlanetCampaignModel.validate_epoch_advance(
		_campaign_catalog, _autumn_campaign,
		String(_autumn_campaign.get("state_receipt", "")), _autumn_advance
	).is_empty():
		push_error("CampaignCovenantLab epoch validation failed")
		return false
	if not _projection_valid(
		_watch_chain.get("bound_state", {}) as Dictionary, _autumn_campaign,
		_watch_chain.get("due_projection", {}) as Dictionary
	) or not _projection_valid(
		_watch_chain.get("amended_state", {}) as Dictionary, _autumn_campaign,
		_watch_chain.get("amended_projection", {}) as Dictionary
	):
		push_error("CampaignCovenantLab watch projection validation failed")
		return false
	if not _validate_watch_amend() or not _validate_resolution_chain(
		_watch_chain, "honor"
	) or not _validate_resolution_chain(
		_relief_chain, "withdraw"
	) or not _validate_resolution_chain(
		_exchange_chain, "honor"
	) or not _validate_resolution_chain(
		_low_access_chain, "honor"
	):
		push_error("CampaignCovenantLab lifecycle proposal validation failed")
		return false
	var watch_delta: Dictionary = (
		_watch_chain.get("honor", {}) as Dictionary
	).get("faction_region_delta", {}) as Dictionary
	var exchange_delta: Dictionary = (
		_exchange_chain.get("honor", {}) as Dictionary
	).get("faction_region_delta", {}) as Dictionary
	var low_delta: Dictionary = (
		_low_access_chain.get("honor", {}) as Dictionary
	).get("faction_region_delta", {}) as Dictionary
	var withdraw_delta: Dictionary = (
		_relief_chain.get("withdraw", {}) as Dictionary
	).get("faction_region_delta", {}) as Dictionary
	if int(watch_delta.get("access_requested", 0)) != 1 \
			or int(watch_delta.get("access_applied", 1)) != 0 \
			or int(exchange_delta.get("access_requested", 0)) != 1 \
			or int(exchange_delta.get("access_applied", 1)) != 0 \
			or int(low_delta.get("access_applied", 0)) != 1 \
			or int(withdraw_delta.get("access_applied", 0)) != -2:
		push_error("CampaignCovenantLab owner continuity deltas do not match the golden chain")
		return false
	return true


func _validate_bind_branch(branch: Dictionary) -> bool:
	var state: Dictionary = branch.get("state", {}) as Dictionary
	var evidence: Dictionary = branch.get("evidence", {}) as Dictionary
	var board: Dictionary = branch.get("board", {}) as Dictionary
	var choice: Dictionary = branch.get("choice", {}) as Dictionary
	var proposal: Dictionary = branch.get("proposal", {}) as Dictionary
	return proposal.get("owner_order", []) == ["covenant", "faction_region"] \
		and CampaignCovenantModel.validate_covenant_choice(
			board, choice
		).is_empty() and CampaignCovenantModel.validate_bind_proposal(
			_covenant_catalog, state, String(state.get("state_receipt", "")),
			_campaign_catalog, _campaign_initial,
			String(_campaign_initial.get("state_receipt", "")), CAMPAIGN_OWNER_SCOPE,
			evidence.get("adapters", []) as Array,
			evidence.get("acceptances", []) as Array, GLOBAL_NETWORK_SCOPE,
			_global_checkpoint, board, choice, proposal
		).is_empty()


func _projection_valid(covenant_state: Dictionary, campaign_state: Dictionary,
		projection: Dictionary) -> bool:
	return CampaignCovenantModel.validate_obligation_projection(
		_covenant_catalog, covenant_state,
		String(covenant_state.get("state_receipt", "")), _campaign_catalog,
		campaign_state, String(campaign_state.get("state_receipt", "")),
		CAMPAIGN_OWNER_SCOPE, projection
	).is_empty()


func _validate_watch_amend() -> bool:
	var bound_state: Dictionary = _watch_chain.get("bound_state", {}) as Dictionary
	var evidence: Dictionary = _watch_chain.get("amend_evidence", {}) as Dictionary
	var proposal: Dictionary = _watch_chain.get("amend", {}) as Dictionary
	return proposal.get("owner_order", []) == ["covenant", "faction_region"] \
		and CampaignCovenantModel.validate_amend_proposal(
			_covenant_catalog, bound_state,
			String(bound_state.get("state_receipt", "")), _campaign_catalog,
			_autumn_campaign, String(_autumn_campaign.get("state_receipt", "")),
			CAMPAIGN_OWNER_SCOPE, evidence.get("adapter", {}) as Dictionary,
			evidence.get("acceptance", {}) as Dictionary, GLOBAL_NETWORK_SCOPE,
			_global_checkpoint, proposal
		).is_empty()


func _validate_resolution_chain(chain: Dictionary, resolution: String) -> bool:
	var before_state: Dictionary
	if chain == _watch_chain:
		before_state = chain.get("amended_state", {}) as Dictionary
	else:
		before_state = chain.get("bound_state", {}) as Dictionary
	var campaign_state: Dictionary
	if resolution == "withdraw":
		campaign_state = _autumn_campaign
	else:
		campaign_state = chain.get("committed_campaign", {}) as Dictionary
	var evidence_key := "withdraw_evidence" if resolution == "withdraw" \
		else "honor_evidence"
	var proposal_key := "withdraw" if resolution == "withdraw" else "honor"
	var evidence: Dictionary = chain.get(evidence_key, {}) as Dictionary
	var proposal: Dictionary = chain.get(proposal_key, {}) as Dictionary
	var terminal_state: Dictionary = chain.get("terminal_state", {}) as Dictionary
	var terminal_projection: Dictionary = chain.get(
		"terminal_projection", {}
	) as Dictionary
	return proposal.get("owner_order", []) == ["covenant", "faction_region"] \
		and CampaignCovenantModel.validate_resolution_proposal(
			_covenant_catalog, before_state,
			String(before_state.get("state_receipt", "")), _campaign_catalog,
			campaign_state, String(campaign_state.get("state_receipt", "")),
			CAMPAIGN_OWNER_SCOPE, evidence.get("adapter", {}) as Dictionary,
			evidence.get("acceptance", {}) as Dictionary, GLOBAL_NETWORK_SCOPE,
			_global_checkpoint, resolution, proposal
		).is_empty() and _projection_valid(
			terminal_state, campaign_state, terminal_projection
		)


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
	_panel(MAIN_PANEL, "COVENANT / TIME-BOUND ALLOCATION", "TIME / NOT GEOGRAPHY")
	_panel(SIDE_PANEL, "OBLIGATION / AUTHORITY")
	if _load_ok:
		_draw_time_rail()
		_draw_obligation_area()
		_draw_faction_registers()
		_draw_side_panel()
	else:
		_text("CAMPAIGN COVENANT CONTRACT FAILED", Vector2(70.0, 240.0), 20, C_DANGER)
	_draw_footer()


func _draw_noise_field() -> void:
	for index in range(190):
		var x := float((index * 97 + 31) % 1280)
		var y := float((index * 53 + 17) % 768)
		draw_rect(Rect2(x, y, 2.0, 2.0), Color(0.72, 0.67, 0.48, 0.035))


func _draw_header() -> void:
	draw_rect(HEADER_RECT, C_HEADER)
	draw_line(Vector2(0.0, 71.0), Vector2(1280.0, 71.0), C_EDGE, 1.0)
	_text("CAMPAIGN COVENANT LAB // RP-0008", Vector2(24.0, 31.0), 22, C_TEXT)
	_text("Today's accepted promise narrows a later allocation decision.",
		Vector2(24.0, 55.0), 13, C_MUTED)
	_text("ASHFALL / MULTI-EPOCH", Vector2(930.0, 31.0), 13, C_GOLD, 326.0,
		HORIZONTAL_ALIGNMENT_RIGHT)
	var status := _header_status()
	_text(status, Vector2(900.0, 55.0), 10,
		C_DANGER if "SUPERSEDED" in status else C_MUTED, 356.0,
		HORIZONTAL_ALIGNMENT_RIGHT)


func _header_status() -> String:
	match _fixture:
		FIXTURE_BOARD:
			return "ABSTRACT COVENANT / CHOOSE ONE"
		FIXTURE_DUE:
			return "DUE / AMEND OR WITHDRAW"
		FIXTURE_AMENDED:
			return "ACTIVE / DUE WINTER"
		FIXTURE_WITHDRAWN:
			return "WITHDRAWN / SETTLED"
		FIXTURE_WATCH_HONORED:
			return "HONORED / REGION DELTA SUPERSEDED"
	return "HONORED / %s" % (
		"APPLIED LOW-ACCESS FIXTURE" if _show_low_access else "REGION DELTA SUPERSEDED"
	)


func _draw_fixture_rail() -> void:
	_fixture_rects.clear()
	for index in range(6):
		var card_rect := Rect2(24.0 + float(index) * 204.0, 88.0, 196.0, 66.0)
		_fixture_rects.append(card_rect)
		var selected := index == _fixture
		var accent := _fixture_color(index)
		draw_rect(Rect2(card_rect.position + Vector2(3.0, 4.0), card_rect.size),
			Color(0.0, 0.0, 0.0, 0.22))
		draw_rect(card_rect, C_CARD_HI if selected else C_CARD)
		draw_rect(card_rect, accent if selected else C_EDGE, false, 2.0 if selected else 1.0)
		draw_rect(Rect2(card_rect.position, Vector2(5.0, card_rect.size.y)), accent)
		_text(String(FIXTURE_TITLES[index]), card_rect.position + Vector2(14.0, 27.0),
			12, C_TEXT if selected else C_MUTED)
		_text(String(FIXTURE_SUBTITLES[index]).to_upper(),
			card_rect.position + Vector2(14.0, 48.0), 8, accent if selected else C_MUTED)


func _fixture_color(index: int) -> Color:
	match index:
		FIXTURE_AMENDED:
			return C_BLUE
		FIXTURE_WATCH_HONORED, FIXTURE_EXCHANGE_HONORED:
			return C_TEAL
		FIXTURE_WITHDRAWN:
			return C_DANGER
	return C_GOLD


func _panel(panel_rect: Rect2, title: String, legend: String = "") -> void:
	draw_rect(Rect2(panel_rect.position + Vector2(4.0, 5.0), panel_rect.size),
		Color(0.0, 0.0, 0.0, 0.25))
	draw_rect(panel_rect, C_PANEL)
	draw_rect(panel_rect, C_EDGE, false, 1.0)
	draw_rect(Rect2(panel_rect.position, Vector2(panel_rect.size.x, 31.0)), C_PANEL_2)
	_text(title, panel_rect.position + Vector2(13.0, 22.0), 13, C_GOLD)
	if legend != "":
		_text(legend, panel_rect.position + Vector2(panel_rect.size.x - 208.0, 22.0),
			8, C_MUTED, 194.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_time_rail() -> void:
	var rail := Rect2(60.0, 218.0, 752.0, 76.0)
	draw_rect(rail, Color("#10130e"))
	draw_rect(rail, C_EDGE, false, 1.0)
	_text("ACCEPTED OWNER TIME / NO ROUTE CLAIM", rail.position + Vector2(13.0, 18.0),
		9, C_MUTED)
	var labels := _time_labels()
	var centers := [151.0, 392.0, 633.0]
	draw_line(Vector2(118.0, 262.0), Vector2(666.0, 262.0), C_EDGE_HI, 2.0)
	for index in range(3):
		var center := float(centers[index])
		var color := _time_color(index)
		draw_circle(Vector2(center, 262.0), 7.0, color)
		draw_circle(Vector2(center, 262.0), 11.0, color, false, 1.0)
		_text(String(["SPRING / E0", "AUTUMN / E1", "WINTER / E2"][index]),
			Vector2(center - 74.0, 246.0), 9, C_TEXT, 148.0,
			HORIZONTAL_ALIGNMENT_CENTER)
		_text(String(labels[index]), Vector2(center - 82.0, 287.0), 8, color, 164.0,
			HORIZONTAL_ALIGNMENT_CENTER)


func _time_labels() -> Array[String]:
	match _fixture:
		FIXTURE_BOARD:
			return ["BIND WINDOW", "ALL DUE", "UNBOUND"]
		FIXTURE_DUE:
			return ["WATCH BOUND / R1", "DUE / CAP 2", "UNCOMMITTED"]
		FIXTURE_AMENDED:
			return ["WATCH BOUND / R1", "AMENDED / R2", "NEW DUE"]
		FIXTURE_WATCH_HONORED:
			return ["BOUND / R1", "AMENDED / R2", "HONORED / R3"]
		FIXTURE_WITHDRAWN:
			return ["RELIEF BOUND / R1", "WITHDRAWN / R2", "SETTLED"]
	return ["EXCHANGE BOUND / R1", "HONORED / R2", "SETTLED"]


func _time_color(index: int) -> Color:
	if _fixture == FIXTURE_WITHDRAWN and index >= 1:
		return C_DANGER
	if _fixture == FIXTURE_AMENDED and index >= 1:
		return C_BLUE
	if _fixture in [FIXTURE_WATCH_HONORED, FIXTURE_EXCHANGE_HONORED] \
			and index == (2 if _fixture == FIXTURE_WATCH_HONORED else 1):
		return C_TEAL
	if _fixture == FIXTURE_DUE and index == 1:
		return C_DANGER
	return C_GOLD if index <= 1 else C_MUTED


func _draw_obligation_area() -> void:
	if _fixture == FIXTURE_BOARD:
		_draw_spring_options()
		return
	var key := _display_covenant_key()
	var covenant := _covenant_for_key(key)
	var contract_rect := Rect2(60.0, 307.0, 492.0, 193.0)
	var decision_rect := Rect2(565.0, 307.0, 247.0, 193.0)
	_card(contract_rect, _fixture_color(_fixture))
	_card(decision_rect, _fixture_color(_fixture))
	_text("ACTIVE COVENANT", contract_rect.position + Vector2(14.0, 22.0), 9,
		C_MUTED)
	_text(String(covenant.get("label", "")),
		contract_rect.position + Vector2(14.0, 52.0), 18, C_TEXT)
	_text("REQUIRED / %s" % String(covenant.get("required_action", "")).to_upper(),
		contract_rect.position + Vector2(14.0, 76.0), 11, _fixture_color(_fixture))
	_text(_contract_due_copy(), contract_rect.position + Vector2(14.0, 101.0), 10,
		C_TEXT)
	_text("TERMS / BIND +1  AMEND -1  HONOR +1  WITHDRAW -2",
		contract_rect.position + Vector2(14.0, 129.0), 9, C_MUTED)
	var state := _display_covenant_state()
	_text("LIFECYCLE / %s   REVISION / %d" % [
		String(state.get("phase", "")).to_upper(), int(state.get("revision", -1))
	], contract_rect.position + Vector2(14.0, 154.0), 9, C_TEXT)
	_text("STATE / %s" % _receipt_suffix(String(state.get("state_receipt", ""))),
		contract_rect.position + Vector2(14.0, 178.0), 8, C_MUTED)
	_draw_decision_card(decision_rect)


func _draw_spring_options() -> void:
	for index in range(3):
		var key := String(COVENANT_KEYS[index])
		var option := _covenant_option_for_key(_spring_board, key)
		var card_rect := Rect2(60.0 + float(index) * 255.0, 307.0, 242.0, 193.0)
		var selected := index == _selected_covenant
		var accent := [C_TEAL, C_GOLD, C_BLUE][index] as Color
		_card(card_rect, accent if selected else C_EDGE)
		_text(String(option.get("label", "")), card_rect.position + Vector2(13.0, 26.0),
			12, C_TEXT)
		_text("CHOOSE %d / %s" % [index + 1,
			String(option.get("required_action", "")).to_upper()],
			card_rect.position + Vector2(13.0, 52.0), 10, accent)
		_text("BOUND / SPRING", card_rect.position + Vector2(13.0, 78.0), 9, C_MUTED)
		_text("DUE / AUTUMN", card_rect.position + Vector2(13.0, 100.0), 9, C_TEXT)
		_text("EXPECTED DUE COST / %d" % int(option.get(
			"expected_due_capacity_cost", -1
		)), card_rect.position + Vector2(13.0, 126.0), 10,
			C_DANGER if int(option.get("expected_due_capacity_cost", 0)) == 3 else C_GOLD)
		var effect: Dictionary = option.get("region_effect", {}) as Dictionary
		var before: Dictionary = effect.get("before_signals", {}) as Dictionary
		var after: Dictionary = effect.get("after_signals", {}) as Dictionary
		_text("FACTION ACCESS / %d -> %d" % [
			int(before.get("faction_access", -1)), int(after.get("faction_access", -1))
		], card_rect.position + Vector2(13.0, 153.0), 9, C_TEXT)
		_text("ONE COVENANT ONLY" if selected else "AVAILABLE",
			card_rect.position + Vector2(13.0, 178.0), 8, accent if selected else C_MUTED)


func _contract_due_copy() -> String:
	if _fixture in [FIXTURE_AMENDED, FIXTURE_WATCH_HONORED]:
		return "BOUND / SPRING   OLD DUE / AUTUMN   EFFECTIVE DUE / WINTER"
	return "BOUND / SPRING   EFFECTIVE DUE / AUTUMN"


func _draw_decision_card(card_rect: Rect2) -> void:
	var title := ""
	var lines: Array[String] = []
	var accent := _fixture_color(_fixture)
	match _fixture:
		FIXTURE_DUE:
			title = "PROMISE CONSTRAINS NOW"
			lines = ["AUTUMN CAP / 2", "PROMISED FORTIFY / COST 3",
				"TIGHT BOARD / TRADE ONLY", "ACTIONS / AMEND + WITHDRAW"]
		FIXTURE_AMENDED:
			title = "AMENDMENT / ONE OF ONE"
			lines = ["DUE / AUTUMN -> WINTER", "ACCESS / 3 -> 2",
				"REQUEST / APPLIED  -1 / -1", "TIMING / NOT_DUE"]
		FIXTURE_WATCH_HONORED:
			title = "LEDGER HONORED"
			lines = ["REGION DELTA / SUPERSEDED", "ACCESS / 3 -> 3",
				"REQUEST / APPLIED  +1 / 0", "TIMING / SETTLED"]
		FIXTURE_WITHDRAWN:
			title = "LEDGER WITHDRAWN"
			lines = ["REGION DELTA / APPLIED", "ACCESS / 3 -> 1",
				"REQUEST / APPLIED  -2 / -2", "TIMING / SETTLED"]
		_:
			if _show_low_access:
				title = "INDEPENDENT LOW-ACCESS"
				lines = ["REGION DELTA / APPLIED", "ACCESS / 2 -> 3",
					"REQUEST / APPLIED  +1 / +1", "TIMING / SETTLED"]
			else:
				title = "LEDGER HONORED"
				lines = ["REGION DELTA / SUPERSEDED", "ACCESS / 3 -> 3",
					"REQUEST / APPLIED  +1 / 0", "TIMING / SETTLED"]
	_text(title, card_rect.position + Vector2(13.0, 24.0), 11, accent)
	for index in range(lines.size()):
		_text(lines[index], card_rect.position + Vector2(13.0, 56.0 + 29.0 * index),
			9, C_TEXT if index != 1 else accent)


func _draw_faction_registers() -> void:
	var signals_by_key := _display_signals()
	var active_key := _display_window_key()
	for index in range(3):
		var key := String(WINDOW_KEYS[index])
		var signals: Dictionary = signals_by_key.get(key, {}) as Dictionary
		var card_rect := Rect2(60.0 + float(index) * 255.0, 513.0, 242.0, 128.0)
		var active := key == active_key or _fixture == FIXTURE_BOARD
		var accent := [C_TEAL, C_GOLD, C_BLUE][index] as Color
		_card(card_rect, accent if active else C_EDGE)
		_text(String(["BASIN COMPACT", "MERIDIAN EXCHANGE", "NIGHTWARD WATCH"][index]),
			card_rect.position + Vector2(13.0, 23.0), 10, C_TEXT)
		_text("DISCRETE FACTION REGISTER", card_rect.position + Vector2(13.0, 43.0),
			8, C_MUTED)
		var track := String(["need_pressure", "logistics_pressure", "security_pressure"][index])
		_text("%s / %d" % [track.trim_suffix("_pressure").to_upper(),
			int(signals.get(track, -1))], card_rect.position + Vector2(13.0, 72.0),
			10, accent)
		_text("FACTION ACCESS / %d" % int(signals.get("faction_access", -1)),
			card_rect.position + Vector2(13.0, 96.0), 10, C_TEXT)
		_text(_register_note(key), card_rect.position + Vector2(13.0, 117.0),
			8, accent if active else C_MUTED)


func _display_signals() -> Dictionary:
	var result: Dictionary = BASELINE_SIGNALS.duplicate(true)
	var proposal: Dictionary = {}
	var key := _display_window_key()
	match _fixture:
		FIXTURE_DUE:
			proposal = ((_watch_chain.get("bind", {}) as Dictionary).get(
				"proposal", {}
			) as Dictionary)
		FIXTURE_AMENDED:
			proposal = _watch_chain.get("amend", {}) as Dictionary
		FIXTURE_WATCH_HONORED:
			proposal = ((_watch_chain.get("rp7_commit", {}) as Dictionary).get(
				"proposal", {}
			) as Dictionary)
		FIXTURE_WITHDRAWN:
			proposal = _relief_chain.get("withdraw", {}) as Dictionary
		FIXTURE_EXCHANGE_HONORED:
			var chain := _low_access_chain if _show_low_access else _exchange_chain
			proposal = chain.get("honor", {}) as Dictionary
	if not proposal.is_empty():
		var delta: Dictionary = proposal.get("faction_region_delta", {}) as Dictionary
		if delta.is_empty():
			delta = proposal.get("origin_region_delta", {}) as Dictionary
		if not delta.is_empty():
			result[key] = (delta.get("after_signals", {}) as Dictionary).duplicate(true)
	if _fixture == FIXTURE_EXCHANGE_HONORED and _show_low_access:
		for key_value in WINDOW_KEYS:
			var low_key := String(key_value)
			if low_key != key:
				var low_signals: Dictionary = (
					result.get(low_key, {}) as Dictionary
				).duplicate(true)
				low_signals["faction_access"] = 0
				result[low_key] = low_signals
	return result


func _register_note(key: String) -> String:
	if key != _display_window_key() and _fixture != FIXTURE_BOARD:
		return "READ-ONLY / UNCHANGED"
	match _fixture:
		FIXTURE_BOARD:
			return "BIND CANDIDATE / ACCESS 2"
		FIXTURE_DUE:
			return "BIND ACCEPTED / ACCESS 3"
		FIXTURE_AMENDED:
			return "AMEND APPLIED / ACCESS 2"
		FIXTURE_WATCH_HONORED:
			return "RP7 FORTIFY APPLIED BEFORE HONOR"
		FIXTURE_WITHDRAWN:
			return "WITHDRAW APPLIED / ACCESS 1"
	return "LOW-ACCESS APPLIED" if _show_low_access else "TRADE + HONOR BOUNDED AT 3"


func _display_covenant_key() -> String:
	match _fixture:
		FIXTURE_WITHDRAWN:
			return "relief_guarantee"
		FIXTURE_EXCHANGE_HONORED:
			return "exchange_charter"
	return "watch_compact"


func _display_window_key() -> String:
	match _display_covenant_key():
		"relief_guarantee":
			return "basin_relief"
		"exchange_charter":
			return "meridian_trade"
	return "nightward_fortify"


func _display_covenant_state() -> Dictionary:
	match _fixture:
		FIXTURE_DUE:
			return _watch_chain.get("bound_state", {}) as Dictionary
		FIXTURE_AMENDED:
			return _watch_chain.get("amended_state", {}) as Dictionary
		FIXTURE_WATCH_HONORED:
			return _watch_chain.get("terminal_state", {}) as Dictionary
		FIXTURE_WITHDRAWN:
			return _relief_chain.get("terminal_state", {}) as Dictionary
		FIXTURE_EXCHANGE_HONORED:
			var chain := _low_access_chain if _show_low_access else _exchange_chain
			return chain.get("terminal_state", {}) as Dictionary
	return _covenant_initial


func _display_projection() -> Dictionary:
	match _fixture:
		FIXTURE_DUE:
			return _watch_chain.get("due_projection", {}) as Dictionary
		FIXTURE_AMENDED:
			return _watch_chain.get("amended_projection", {}) as Dictionary
		FIXTURE_WATCH_HONORED:
			return _watch_chain.get("terminal_projection", {}) as Dictionary
		FIXTURE_WITHDRAWN:
			return _relief_chain.get("terminal_projection", {}) as Dictionary
		FIXTURE_EXCHANGE_HONORED:
			var chain := _low_access_chain if _show_low_access else _exchange_chain
			return chain.get("terminal_projection", {}) as Dictionary
	return _project(_covenant_initial, _campaign_initial)


func _draw_side_panel() -> void:
	_draw_read_only_card()
	_draw_current_decision_card()
	_draw_authority_card()


func _draw_read_only_card() -> void:
	var card_rect := Rect2(880.0, 209.0, 360.0, 74.0)
	_card(card_rect, C_GOLD)
	_text("READ-ONLY EVIDENCE / NO DELTA", card_rect.position + Vector2(14.0, 22.0),
		10, C_GOLD)
	_text("RP7 CAMPAIGN / %s" % _receipt_suffix(_display_campaign_receipt()),
		card_rect.position + Vector2(14.0, 45.0), 9, C_TEXT)
	_text("RP6 GLOBAL / %s" % _receipt_suffix(_global_checkpoint),
		card_rect.position + Vector2(14.0, 63.0), 8, C_MUTED)


func _display_campaign_receipt() -> String:
	match _fixture:
		FIXTURE_DUE, FIXTURE_AMENDED, FIXTURE_WITHDRAWN:
			return String(_autumn_campaign.get("state_receipt", ""))
		FIXTURE_WATCH_HONORED:
			return String((_watch_chain.get(
				"committed_campaign", {}
			) as Dictionary).get("state_receipt", ""))
		FIXTURE_EXCHANGE_HONORED:
			var chain := _low_access_chain if _show_low_access else _exchange_chain
			return String((chain.get("committed_campaign", {}) as Dictionary).get(
				"state_receipt", ""
			))
	return String(_campaign_initial.get("state_receipt", ""))


func _draw_current_decision_card() -> void:
	var card_rect := Rect2(880.0, 295.0, 360.0, 286.0)
	_card(card_rect, _fixture_color(_fixture))
	var projection := _display_projection()
	_text("OBLIGATION / CURRENT ACCEPTED VIEW", card_rect.position + Vector2(14.0, 23.0),
		10, _fixture_color(_fixture))
	if _fixture == FIXTURE_BOARD:
		_text("COVENANTS_AVAILABLE", card_rect.position + Vector2(14.0, 54.0),
			16, C_TEXT)
		_text("CHOOSE ONE / THREE NON-SCALAR TERMS", card_rect.position + Vector2(14.0, 79.0),
			9, C_MUTED)
		for index in range(3):
			var option := _covenant_option_for_key(
				_spring_board, String(COVENANT_KEYS[index])
			)
			var row := Rect2(card_rect.position + Vector2(14.0, 96.0 + 48.0 * index),
				Vector2(332.0, 40.0))
			draw_rect(row, C_CARD_HI if index == _selected_covenant else C_CARD)
			draw_rect(row, C_EDGE, false, 1.0)
			_text("%d  %s" % [index + 1, COVENANT_SHORT[index]],
				row.position + Vector2(10.0, 16.0), 9, C_TEXT)
			_text("DUE COST %d" % int(option.get("expected_due_capacity_cost", -1)),
				row.position + Vector2(205.0, 16.0), 8, C_GOLD, 115.0,
				HORIZONTAL_ALIGNMENT_RIGHT)
			_text(String(option.get("required_action", "")).to_upper(),
				row.position + Vector2(10.0, 33.0), 8, C_MUTED)
		_text("CURSOR / %s" % COVENANT_SHORT[_selected_covenant],
			card_rect.position + Vector2(14.0, 263.0), 9, C_GOLD)
		return
	var timing := String(projection.get("timing_status", "")).to_upper()
	var actions: Array = projection.get("available_actions", []) as Array
	_text("TIMING / %s" % timing, card_rect.position + Vector2(14.0, 54.0), 16,
		C_DANGER if timing == "DUE" and _fixture == FIXTURE_DUE else C_TEXT)
	_text("AVAILABLE / %s" % (" + ".join(actions).to_upper() if not actions.is_empty() else "NONE"),
		card_rect.position + Vector2(14.0, 81.0), 9, C_MUTED)
	_text(_side_primary_status(), card_rect.position + Vector2(14.0, 113.0), 11,
		_fixture_color(_fixture))
	_draw_owner_order(card_rect.position + Vector2(14.0, 139.0))
	var state := _display_covenant_state()
	_text("COVENANT STATE / %s" % _receipt_suffix(String(state.get(
		"state_receipt", ""
	))), card_rect.position + Vector2(14.0, 214.0), 8, C_MUTED)
	_text("VIEW / %s" % String(["BEFORE", "PROPOSAL", "RECEIVER-ACCEPTED FIXTURE"][
		_view_stage
	]), card_rect.position + Vector2(14.0, 239.0), 8, C_TEXT)
	_text(_side_chain_copy(), card_rect.position + Vector2(14.0, 263.0), 8,
		C_DANGER if "SUPERSEDED" in _side_chain_copy() else C_MUTED)


func _side_primary_status() -> String:
	match _fixture:
		FIXTURE_DUE:
			return "WATCH / FORTIFY 3 > CAP 2"
		FIXTURE_AMENDED:
			return "DUE AUTUMN -> WINTER / ACCESS -1"
		FIXTURE_WATCH_HONORED:
			return "HONORED LEDGER / SUPERSEDED DELTA"
		FIXTURE_WITHDRAWN:
			return "WITHDRAWN LEDGER / APPLIED -2"
	return "HONORED / APPLIED LOW-ACCESS" if _show_low_access \
		else "HONORED LEDGER / SUPERSEDED DELTA"


func _side_chain_copy() -> String:
	match _fixture:
		FIXTURE_DUE:
			return "NO MATCHED FORTIFY RECORD"
		FIXTURE_AMENDED:
			return "FRESH NIGHTWARD CHECKPOINT / AMENDMENT 1 OF 1"
		FIXTURE_WATCH_HONORED:
			return "AMEND R1 -> RP7 FORTIFY R2 -> HONOR R3"
		FIXTURE_WITHDRAWN:
			return "RELIEF REMAINS ABSTRACT / LEDGER CLOSED"
	return "INDEPENDENT OWNER CHAIN / 0 -> 1 -> 2 -> 3" if _show_low_access \
		else "BIND R1 -> RP7 TRADE R2 -> HONOR SUPERSEDED"


func _draw_owner_order(origin: Vector2) -> void:
	_text("MUTATION OWNER ORDER", origin, 8, C_MUTED)
	var first := Rect2(origin + Vector2(0.0, 11.0), Vector2(145.0, 45.0))
	var second := Rect2(origin + Vector2(175.0, 11.0), Vector2(145.0, 45.0))
	_card(first, C_GOLD)
	_card(second, C_BLUE)
	_text("COVENANT", first.position + Vector2(10.0, 19.0), 9, C_TEXT)
	_text("CAS DELTA", first.position + Vector2(10.0, 37.0), 8, C_MUTED)
	_text("+", origin + Vector2(158.0, 40.0), 13, C_MUTED)
	_text("FACTION_REGION", second.position + Vector2(10.0, 19.0), 9, C_TEXT)
	_text("CAS DELTA", second.position + Vector2(10.0, 37.0), 8, C_MUTED)


func _draw_authority_card() -> void:
	var card_rect := Rect2(880.0, 593.0, 360.0, 72.0)
	_card(card_rect, _fixture_color(_fixture))
	_text("AUTHORITY BOUNDARY", card_rect.position + Vector2(14.0, 22.0), 9, C_MUTED)
	_text("PROPOSAL ONLY / RECEIVER CAS BOTH OWNERS",
		card_rect.position + Vector2(14.0, 48.0), 9, _fixture_color(_fixture))
	_text("ABSTRACT ALLOCATION LEDGER ONLY", card_rect.position + Vector2(14.0, 65.0),
		8, C_MUTED)


func _card(card_rect: Rect2, accent: Color) -> void:
	draw_rect(Rect2(card_rect.position + Vector2(3.0, 4.0), card_rect.size),
		Color(0.0, 0.0, 0.0, 0.22))
	draw_rect(card_rect, C_CARD)
	draw_rect(card_rect, accent, false, 1.0)
	draw_rect(Rect2(card_rect.position, Vector2(5.0, card_rect.size.y)), accent)


func _draw_footer() -> void:
	draw_rect(Rect2(0.0, 704.0, 1280.0, 64.0), C_HEADER)
	_fixture_rects.clear()
	_covenant_rects.clear()
	for index in range(6):
		var tab_rect := Rect2(24.0 + float(index) * 108.0, 719.0, 102.0, 33.0)
		_fixture_rects.append(tab_rect)
		var selected := index == _fixture
		draw_rect(tab_rect, C_CARD_HI if selected else C_CARD)
		draw_rect(tab_rect, _fixture_color(index) if selected else C_EDGE, false, 1.0)
		_text(String(FIXTURE_TITLES[index]).split("  ")[0],
			tab_rect.position + Vector2(8.0, 21.0), 8,
			_fixture_color(index) if selected else C_MUTED, tab_rect.size.x - 16.0,
			HORIZONTAL_ALIGNMENT_CENTER)
	for index in range(3):
		var covenant_rect := Rect2(684.0 + float(index) * 132.0, 719.0, 124.0, 33.0)
		_covenant_rects.append(covenant_rect)
		var selected := _fixture == FIXTURE_BOARD and index == _selected_covenant
		draw_rect(covenant_rect, C_CARD_HI if selected else C_CARD)
		draw_rect(covenant_rect, C_TEAL if selected else C_EDGE, false, 1.0)
		_text("%d  %s" % [index + 1, COVENANT_SHORT[index]],
			covenant_rect.position + Vector2(7.0, 21.0), 8,
			C_TEAL if selected else C_MUTED, covenant_rect.size.x - 14.0,
			HORIZONTAL_ALIGNMENT_CENTER)
	var v_rect := Rect2(1080.0, 719.0, 76.0, 33.0)
	var r_rect := Rect2(1164.0, 719.0, 76.0, 33.0)
	for pair in [[v_rect, "V  DELTA"], [r_rect, "R  RESET"]]:
		var rect: Rect2 = pair[0] as Rect2
		draw_rect(rect, C_CARD)
		draw_rect(rect, C_EDGE, false, 1.0)
		_text(String(pair[1]), rect.position + Vector2(6.0, 21.0), 8, C_MUTED,
			rect.size.x - 12.0, HORIZONTAL_ALIGNMENT_CENTER)


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
			_selected_covenant = int(key_event.keycode) - int(KEY_1)
			_fixture = FIXTURE_BOARD
			queue_redraw()
		KEY_H:
			_set_fixture(FIXTURE_WATCH_HONORED)
		KEY_M:
			_set_fixture(FIXTURE_AMENDED)
		KEY_W:
			_set_fixture(FIXTURE_WITHDRAWN)
		KEY_BRACKETLEFT:
			_set_fixture(posmod(_fixture - 1, 6))
		KEY_BRACKETRIGHT, KEY_TAB:
			_set_fixture((_fixture + 1) % 6)
		KEY_ENTER, KEY_SPACE:
			_view_stage = (_view_stage + 1) % 3
			queue_redraw()
		KEY_V:
			if _fixture in [FIXTURE_WATCH_HONORED, FIXTURE_EXCHANGE_HONORED]:
				_show_low_access = not _show_low_access
				_fixture = FIXTURE_EXCHANGE_HONORED
				queue_redraw()
		KEY_R:
			_load_ok = _build_real_fixtures()
			queue_redraw()


func _set_fixture(value: int) -> void:
	_fixture = clampi(value, FIXTURE_BOARD, FIXTURE_EXCHANGE_HONORED)
	if _fixture != FIXTURE_EXCHANGE_HONORED:
		_show_low_access = false
	_view_stage = VIEW_AFTER
	queue_redraw()


func _handle_click(click_position: Vector2) -> void:
	for index in range(_fixture_rects.size()):
		if _fixture_rects[index].has_point(click_position):
			_set_fixture(index)
			return
	for index in range(_covenant_rects.size()):
		if _covenant_rects[index].has_point(click_position):
			_selected_covenant = index
			_fixture = FIXTURE_BOARD
			queue_redraw()
			return


func _save_shot() -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("CampaignCovenantLab could not capture the viewport")
		get_tree().quit(1)
		return
	var save_error := image.save_png(_shot_path)
	if save_error != OK:
		push_error("CampaignCovenantLab could not save screenshot: %s" % error_string(save_error))
		get_tree().quit(1)
		return
	get_tree().quit()
