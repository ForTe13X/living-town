extends Node2D

const ReconModel = preload(
	"res://scripts/labs/resource_pool/PlanetReconPortfolioModel.gd"
)
const CampaignModel = preload(
	"res://scripts/labs/resource_pool/PlanetCampaignModel.gd"
)
const CovenantModel = preload(
	"res://scripts/labs/resource_pool/CampaignCovenantModel.gd"
)
const RouteModel = preload(
	"res://scripts/labs/resource_pool/RegionRouteModel.gd"
)
const NetworkModel = preload(
	"res://scripts/labs/resource_pool/SettlementNetworkModel.gd"
)
const ScaleAddress = preload("res://scripts/labs/resource_pool/ScaleAddress.gd")

const DESIGN := Vector2(1280.0, 768.0)
const HEADER_RECT := Rect2(0.0, 0.0, 1280.0, 72.0)
const MAIN_PANEL := Rect2(24.0, 170.0, 824.0, 512.0)
const SIDE_PANEL := Rect2(864.0, 170.0, 392.0, 512.0)

const FIXTURE_PRIORS := 0
const FIXTURE_BOARD := 1
const FIXTURE_DUTY_SPILLOVER := 2
const FIXTURE_DUTY_FALLBACK := 3
const FIXTURE_SPILLOVER_FALLBACK := 4
const FIXTURE_STALE := 5

const STAGE_PRIOR := 0
const STAGE_COMMITTED := 1
const STAGE_TERMINAL := 2

const ROOT_SEED := 260814
const CAMPAIGN_SCOPE := "ashfall_planet_campaign"
const GLOBAL_SCOPE := "ashfall_settlement_network"
const RECON_SCOPE := "ashfall_recon_capacity"
const CARGO_SCOPE := "ashfall_caravan"
const AMPLE_ROUTE_RESOURCE := 100000
const WINDOW_KEYS := ["basin_relief", "meridian_trade", "nightward_fortify"]
const ROLES := ["duty", "spillover", "fallback"]
const PAIR_KEYS := ["duty_spillover", "duty_fallback", "spillover_fallback"]
const PAIR_ROLES := {
	"duty_spillover": ["duty", "spillover"],
	"duty_fallback": ["duty", "fallback"],
	"spillover_fallback": ["spillover", "fallback"],
}
const CANONICAL_SIGNALS := {
	"duty": "favorable",
	"spillover": "adverse",
	"fallback": "mixed",
}
const INVERSE_SIGNALS := {
	"duty": "adverse",
	"spillover": "favorable",
	"fallback": "mixed",
}
const BASE_SIGNALS := {
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
const C_TRACK := Color("#10130e")
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
	"A  PRIORS", "B  2 OF 3", "C  DUTY + SPILL", "D  DUTY + FALLBACK",
	"E  SPILL + FALLBACK", "F  STALE",
]
const FIXTURE_SUBTITLES := [
	"active covenant", "three non-dominated", "meridian + nightward",
	"meridian + basin", "nightward + basin", "spent / no refund",
]
const PAIR_LABELS := ["DUTY + SPILLOVER", "DUTY + FALLBACK", "SPILLOVER + FALLBACK"]

var _font: Font
var _fixture := FIXTURE_PRIORS
var _selected_pair := 1
var _view_stage := STAGE_PRIOR
var _signal_set := "canonical"
var _capacity_points := 2
var _shot_path := ""
var _load_ok := false

var _root_fixture: Dictionary = {}
var _catalog: Dictionary = {}
var _evidence: Dictionary = {}
var _state0: Dictionary = {}
var _recon_checkpoint := ""
var _anchors: Dictionary = {}
var _boards: Dictionary = {}
var _branches: Dictionary = {}
var _inverse_branches: Dictionary = {}
var _stale_proposal: Dictionary = {}
var _stale_projection: Dictionary = {}
var _initial_projection: Dictionary = {}

var _fixture_rects: Array[Rect2] = []
var _pair_rects: Array[Rect2] = []
var _stage_rect := Rect2()
var _variant_rect := Rect2()
var _reset_rect := Rect2()


func _ready() -> void:
	_font = ThemeDB.fallback_font
	var requested_fixture := FIXTURE_PRIORS
	var requested_pair := 1
	var requested_stage := ""
	var requested_signal_set := "canonical"
	var requested_capacity := 2
	var args := OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		var argument := String(args[index])
		if argument == "--recon-fixture" and index + 1 < args.size():
			index += 1
			requested_fixture = _fixture_from_argument(String(args[index]))
		elif argument.begins_with("--recon-fixture="):
			requested_fixture = _fixture_from_argument(
				argument.trim_prefix("--recon-fixture=")
			)
		elif argument == "--recon-portfolio" and index + 1 < args.size():
			index += 1
			requested_pair = _pair_from_argument(String(args[index]))
		elif argument.begins_with("--recon-portfolio="):
			requested_pair = _pair_from_argument(
				argument.trim_prefix("--recon-portfolio=")
			)
		elif argument == "--recon-stage" and index + 1 < args.size():
			index += 1
			requested_stage = String(args[index])
		elif argument.begins_with("--recon-stage="):
			requested_stage = argument.trim_prefix("--recon-stage=")
		elif argument == "--recon-signal-set" and index + 1 < args.size():
			index += 1
			requested_signal_set = String(args[index])
		elif argument.begins_with("--recon-signal-set="):
			requested_signal_set = argument.trim_prefix("--recon-signal-set=")
		elif argument == "--recon-capacity" and index + 1 < args.size():
			index += 1
			requested_capacity = int(String(args[index]))
		elif argument.begins_with("--recon-capacity="):
			requested_capacity = int(argument.trim_prefix("--recon-capacity="))
		elif argument == "--lab-shot" and index + 1 < args.size():
			index += 1
			_shot_path = String(args[index])
		elif argument.begins_with("--lab-shot="):
			_shot_path = argument.trim_prefix("--lab-shot=")
		index += 1
	_fixture = requested_fixture
	_selected_pair = requested_pair
	match _fixture:
		FIXTURE_DUTY_SPILLOVER:
			_selected_pair = 0
		FIXTURE_DUTY_FALLBACK, FIXTURE_STALE:
			_selected_pair = 1
		FIXTURE_SPILLOVER_FALLBACK:
			_selected_pair = 2
	_signal_set = "inverse" if requested_signal_set.strip_edges().to_lower() \
		== "inverse" else "canonical"
	_capacity_points = clampi(requested_capacity, 0, ReconModel.MAX_RECON_POINTS)
	_view_stage = _default_stage_for_fixture(_fixture)
	if requested_stage != "":
		_view_stage = _stage_from_argument(requested_stage)
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
		"a", "0", "priors", "active-priors":
			return FIXTURE_PRIORS
		"b", "1", "board", "2-of-3", "portfolio-board":
			return FIXTURE_BOARD
		"c", "2", "duty-spillover", "duty_spillover":
			return FIXTURE_DUTY_SPILLOVER
		"d", "3", "duty-fallback", "duty_fallback":
			return FIXTURE_DUTY_FALLBACK
		"e", "4", "spillover-fallback", "spillover_fallback":
			return FIXTURE_SPILLOVER_FALLBACK
		"f", "5", "stale", "cycle-stale":
			return FIXTURE_STALE
	return FIXTURE_PRIORS


func _pair_from_argument(value: String) -> int:
	match value.strip_edges().to_lower().replace("-", "_"):
		"1", "duty_spillover", "duty+spillover":
			return 0
		"2", "duty_fallback", "duty+fallback":
			return 1
		"3", "spillover_fallback", "spillover+fallback":
			return 2
	return 1


func _stage_from_argument(value: String) -> int:
	match value.strip_edges().to_lower():
		"prior", "open", "board", "0":
			return STAGE_PRIOR
		"commit", "committed", "1":
			return STAGE_COMMITTED
		"resolved", "terminal", "stale", "2":
			return STAGE_TERMINAL
	return _default_stage_for_fixture(_fixture)


func _default_stage_for_fixture(value: int) -> int:
	return STAGE_PRIOR if value in [FIXTURE_PRIORS, FIXTURE_BOARD] \
		else STAGE_TERMINAL


func _build_real_fixtures() -> bool:
	_root_fixture = _build_authority_fixture()
	if _root_fixture.is_empty():
		push_error("PlanetReconPortfolioLab could not build accepted RP3/RP6/RP7/RP8 authority")
		return false
	_catalog = _root_fixture["catalog"]
	_evidence = _root_fixture["evidence"]
	_state0 = ReconModel.make_initial_state(_catalog, _evidence)
	_recon_checkpoint = _external_receipt("rp9-recon-owner")
	if _state0.is_empty() or _recon_checkpoint == "":
		push_error("PlanetReconPortfolioLab could not build initial belief state")
		return false
	_anchors.clear()
	_boards.clear()
	var capacity_values: Array[int] = [0, 1, 2]
	if _capacity_points not in capacity_values:
		capacity_values.append(_capacity_points)
	capacity_values.sort()
	for points in capacity_values:
		var anchor: Dictionary = ReconModel.make_recon_anchor(
			RECON_SCOPE, _recon_checkpoint,
			String(_evidence.get("evidence_receipt", "")), points
		)
		var board: Dictionary = _make_board(_state0, _evidence, anchor)
		if anchor.is_empty() or board.is_empty():
			push_error("PlanetReconPortfolioLab could not build capacity board %d" % points)
			return false
		_anchors[points] = anchor
		_boards[points] = board
	_branches.clear()
	_inverse_branches.clear()
	for pair_key in PAIR_KEYS:
		var canonical: Dictionary = _build_branch(
			String(pair_key), CANONICAL_SIGNALS, "canonical"
		)
		var inverse: Dictionary = _build_branch(
			String(pair_key), INVERSE_SIGNALS, "inverse"
		)
		if canonical.is_empty() or inverse.is_empty():
			push_error("PlanetReconPortfolioLab could not build real branch %s" % pair_key)
			return false
		_branches[String(pair_key)] = canonical
		_inverse_branches[String(pair_key)] = inverse
	var stale_source: Dictionary = _branches["duty_fallback"]
	var committed: Dictionary = stale_source["committed"]
	var campaign1: Dictionary = _root_fixture["campaign1"]
	var covenant_state: Dictionary = _root_fixture["covenant_state"]
	_stale_proposal = ReconModel.close_stale(
		_root_fixture["campaign_catalog"], _root_fixture["covenant_catalog"],
		_catalog, committed, String(committed.get("state_receipt", "")),
		campaign1, String(campaign1.get("state_receipt", "")), CAMPAIGN_SCOPE,
		covenant_state, String(covenant_state.get("state_receipt", "")),
		GLOBAL_SCOPE
	)
	var stale_state: Dictionary = _stale_proposal.get("after_state", {})
	_stale_projection = ReconModel.project_beliefs(
		_catalog, stale_state, String(stale_state.get("state_receipt", ""))
	)
	_initial_projection = ReconModel.project_beliefs(
		_catalog, _state0, String(_state0.get("state_receipt", ""))
	)
	if _stale_proposal.is_empty() or _stale_projection.is_empty() \
			or _initial_projection.is_empty():
		push_error("PlanetReconPortfolioLab could not build terminal projections")
		return false
	return _validate_real_fixtures()


func _build_authority_fixture() -> Dictionary:
	var atlas: Dictionary = RouteModel.make_atlas(ROOT_SEED)
	var network_fixture: Dictionary = _make_network_fixture(atlas)
	if atlas.is_empty() or network_fixture.is_empty():
		push_error("PlanetReconPortfolioLab authority stage failed: atlas/network")
		return {}
	var campaign_catalog: Dictionary = CampaignModel.make_catalog(ROOT_SEED)
	var campaign0: Dictionary = CampaignModel.make_initial_state(campaign_catalog)
	var advance1: Dictionary = CampaignModel.advance_epoch(
		campaign_catalog, campaign0, String(campaign0.get("state_receipt", ""))
	)
	var campaign1: Dictionary = advance1.get("after_state", {})
	var covenant_catalog: Dictionary = CovenantModel.make_catalog(campaign_catalog)
	var covenant0: Dictionary = CovenantModel.make_initial_state(covenant_catalog)
	if campaign_catalog.is_empty() or campaign0.is_empty() or campaign1.is_empty() \
			or covenant_catalog.is_empty() or covenant0.is_empty():
		push_error("PlanetReconPortfolioLab authority stage failed: campaign/covenant roots")
		return {}
	var covenant_evidence: Dictionary = _make_window_evidence(
		campaign_catalog, String(network_fixture["network0"]["state_receipt"]),
		"rp9-bind"
	)
	var covenant_board: Dictionary = CovenantModel.make_covenant_board(
		covenant_catalog, covenant0, String(covenant0.get("state_receipt", "")),
		campaign_catalog, campaign0, String(campaign0.get("state_receipt", "")),
		CAMPAIGN_SCOPE, covenant_evidence.get("adapters", []),
		covenant_evidence.get("acceptances", []), GLOBAL_SCOPE,
		String(network_fixture["network0"]["state_receipt"])
	)
	if covenant_evidence.is_empty() or covenant_board.is_empty():
		push_error("PlanetReconPortfolioLab authority stage failed: covenant board")
		return {}
	var exchange_option: Dictionary = _covenant_option(covenant_board, "trade")
	var covenant_choice: Dictionary = CovenantModel.make_covenant_choice(
		covenant_board, String(exchange_option.get("option_id", ""))
	)
	var covenant_bind: Dictionary = CovenantModel.bind_covenant(
		covenant_catalog, covenant0, String(covenant0.get("state_receipt", "")),
		campaign_catalog, campaign0, String(campaign0.get("state_receipt", "")),
		CAMPAIGN_SCOPE, covenant_evidence.get("adapters", []),
		covenant_evidence.get("acceptances", []), GLOBAL_SCOPE,
		String(network_fixture["network0"]["state_receipt"]), covenant_board,
		covenant_choice
	)
	var covenant_state: Dictionary = covenant_bind.get("after_state", {})
	var obligation: Dictionary = CovenantModel.project_obligation(
		covenant_catalog, covenant_state,
		String(covenant_state.get("state_receipt", "")), campaign_catalog,
		campaign0, String(campaign0.get("state_receipt", "")), CAMPAIGN_SCOPE
	)
	var redglass_tile := _site_tile(atlas, "redglass_quarry")
	var atlas_state: Dictionary = RouteModel.make_atlas_state(
		atlas, [redglass_tile], []
	)
	var catalog: Dictionary = ReconModel.make_catalog(
		campaign_catalog, covenant_catalog
	)
	if exchange_option.is_empty() or covenant_choice.is_empty() \
			or covenant_bind.is_empty() or covenant_state.is_empty() \
			or obligation.is_empty() or redglass_tile == "" or atlas_state.is_empty() \
			or catalog.is_empty():
		push_error("PlanetReconPortfolioLab authority stage failed: bind/projection/catalog")
		return {}
	var result := {
		"atlas": atlas,
		"atlas_state": atlas_state,
		"network_catalog": network_fixture["catalog"],
		"network_state": network_fixture["network2"],
		"network0": network_fixture["network0"],
		"intel": network_fixture["intel"],
		"campaign_catalog": campaign_catalog,
		"campaign0": campaign0,
		"campaign1": campaign1,
		"covenant_catalog": covenant_catalog,
		"covenant_state": covenant_state,
		"obligation": obligation,
		"catalog": catalog,
	}
	var evidence: Dictionary = _make_evidence(result)
	if evidence.is_empty():
		push_error("PlanetReconPortfolioLab authority stage failed: recon evidence")
		return {}
	result["evidence"] = evidence
	for key in ["atlas", "atlas_state", "network_catalog", "network_state",
			"intel", "campaign_catalog", "campaign0", "campaign1",
			"covenant_catalog", "covenant_state", "obligation", "catalog",
			"evidence"]:
		if not result.has(key) or not (result[key] is Dictionary) \
				or (result[key] as Dictionary).is_empty():
			return {}
	return result


func _make_network_fixture(atlas: Dictionary) -> Dictionary:
	var catalog: Dictionary = NetworkModel.make_catalog(atlas)
	var network0: Dictionary = NetworkModel.make_initial_state(catalog)
	var source_refs: Array = _source_refs(catalog)
	if catalog.is_empty() or network0.is_empty() or source_refs.is_empty():
		push_error("PlanetReconPortfolioLab network stage failed: roots")
		return {}
	var first: Dictionary = _settle_network_offer(
		atlas, catalog, network0, "orra_relay_fortification", "rp9-net-a",
		source_refs
	)
	var network1: Dictionary = first.get("after_state", {})
	if first.is_empty() or network1.is_empty():
		push_error("PlanetReconPortfolioLab network stage failed: Orra settlement")
		return {}
	var second: Dictionary = _settle_network_offer(
		atlas, catalog, network1, "dunlin_parts_trade", "rp9-net-b",
		source_refs
	)
	var network2: Dictionary = second.get("after_state", {})
	if second.is_empty() or network2.is_empty():
		push_error("PlanetReconPortfolioLab network stage failed: Dunlin settlement")
		return {}
	var intel: Dictionary = NetworkModel.project_intel(
		catalog, network2, String(network2.get("state_receipt", ""))
	)
	if catalog.is_empty() or network0.is_empty() or first.is_empty() \
			or second.is_empty() or intel.is_empty():
		return {}
	return {
		"catalog": catalog,
		"network0": network0,
		"network1": network1,
		"network2": network2,
		"first": first,
		"second": second,
		"intel": intel,
	}


func _settle_network_offer(atlas: Dictionary, catalog: Dictionary,
		state: Dictionary, offer_key: String, tag: String,
		source_refs: Array) -> Dictionary:
	var owner_checkpoint := _external_receipt("cargo-" + tag)
	var anchor: Dictionary = NetworkModel.make_cargo_anchor(
		CARGO_SCOPE, owner_checkpoint, _cargo(0, 0, 2, 0), 80, source_refs
	)
	if anchor.is_empty():
		push_error("PlanetReconPortfolioLab settlement stage failed: cargo anchor " + tag)
		return {}
	var board: Dictionary = NetworkModel.make_offer_board(
		catalog, state, String(state.get("state_receipt", "")), anchor,
		CARGO_SCOPE, owner_checkpoint
	)
	if board.is_empty():
		push_error("PlanetReconPortfolioLab settlement stage failed: offer board " + tag)
		return {}
	var option: Dictionary = _network_option(catalog, board, offer_key)
	if option.is_empty():
		push_error("PlanetReconPortfolioLab settlement stage failed: option " + offer_key)
		return {}
	var choice: Dictionary = NetworkModel.make_choice(
		board, String(option.get("offer_id", ""))
	)
	var destination := _network_node_tile(
		catalog, String(option.get("node_id", ""))
	)
	var route: Dictionary = _arrived_route(atlas, destination, tag)
	if destination == "" or route.is_empty() or (route.get("plan", {}) as Dictionary).is_empty():
		push_error("PlanetReconPortfolioLab settlement stage failed: arrived route " + tag)
		return {}
	var arrival: Dictionary = NetworkModel.make_arrival_evidence(
		catalog, String(option.get("node_id", "")), route.get("atlas", {}),
		route.get("atlas_state", {}), route.get("plan", {}),
		route.get("journey", {}), route.get("route_receipt", {}),
		String(route.get("accepted_journey_state_receipt", ""))
	)
	if arrival.is_empty():
		push_error(
			"PlanetReconPortfolioLab settlement stage failed: arrival %s / phase=%s / current=%s / destination=%s / atlas=%s / state=%s / plan=%s / journey=%s / receipt=%s" % [
				tag, String((route.get("journey", {}) as Dictionary).get("phase", "")),
				String((route.get("journey", {}) as Dictionary).get("current_tile", "")),
				destination,
				str(RouteModel.validate_atlas(route.get("atlas", {}))),
				str(RouteModel.validate_atlas_state(route.get("atlas", {}), route.get("atlas_state", {}))),
				str(RouteModel.validate_plan(route.get("atlas", {}), route.get("atlas_state", {}), route.get("plan", {}))),
				str(RouteModel.validate_journey(route.get("atlas", {}), route.get("atlas_state", {}), route.get("plan", {}), route.get("journey", {}))),
				str(RouteModel.validate_route_receipt(route.get("atlas", {}), route.get("atlas_state", {}), route.get("plan", {}), route.get("journey", {}), route.get("route_receipt", {}))),
			]
		)
		return {}
	return NetworkModel.propose_settlement(
		catalog, state, String(state.get("state_receipt", "")), anchor,
		CARGO_SCOPE, owner_checkpoint, board, choice, route.get("atlas", {}),
		route.get("atlas_state", {}), route.get("plan", {}),
		route.get("journey", {}), route.get("route_receipt", {}),
		String(route.get("accepted_journey_state_receipt", "")), arrival
	)


func _arrived_route(atlas: Dictionary, destination: String,
		slot: String) -> Dictionary:
	var atlas_state: Dictionary = RouteModel.make_initial_atlas_state(atlas)
	var route_board: Dictionary = RouteModel.route_board(
		atlas, atlas_state, destination, destination, "autumn",
		AMPLE_ROUTE_RESOURCE, AMPLE_ROUTE_RESOURCE
	)
	var plan: Dictionary = {}
	for raw_offer in route_board.get("offers", []) as Array:
		if raw_offer is Dictionary:
			var candidate: Dictionary = (raw_offer as Dictionary).get("plan", {})
			if bool(candidate.get("available", false)) and (candidate.get(
					"path", []) as Array).size() == 1:
				plan = candidate
				break
	if plan.is_empty():
		for raw_offer in route_board.get("offers", []) as Array:
			if raw_offer is Dictionary:
				var candidate: Dictionary = (raw_offer as Dictionary).get("plan", {})
				if bool(candidate.get("available", false)):
					plan = candidate
					break
	var journey: Dictionary = RouteModel.begin_journey(
		atlas, atlas_state, plan, slot, AMPLE_ROUTE_RESOURCE,
		AMPLE_ROUTE_RESOURCE
	)
	var guard := 0
	while String(journey.get("phase", "")) == "traveling" and guard < 128:
		var transition: Dictionary = RouteModel.advance_one_leg(
			atlas, atlas_state, plan, journey
		)
		if transition.is_empty():
			return {}
		atlas_state = transition.get("atlas_state", {})
		journey = transition.get("journey", {})
		guard += 1
	if String(journey.get("phase", "")) != "arrived":
		return {}
	var route_receipt: Dictionary = RouteModel.route_receipt(
		atlas, atlas_state, plan, journey
	)
	return {
		"atlas": atlas,
		"atlas_state": atlas_state,
		"plan": plan,
		"journey": journey,
		"route_receipt": route_receipt,
		"accepted_journey_state_receipt": String(
			journey.get("state_receipt", "")
		),
	}


func _make_window_evidence(catalog: Dictionary, global_receipt: String,
		tag: String) -> Dictionary:
	var adapters: Array[Dictionary] = []
	var acceptances: Array[Dictionary] = []
	for raw_key in WINDOW_KEYS:
		var key := String(raw_key)
		var window := _campaign_window(catalog, key)
		var scope := "rp7_region_%s" % key
		var checkpoint := _external_receipt("%s-%s" % [tag, key])
		var signals: Dictionary = (BASE_SIGNALS[key] as Dictionary).duplicate(true)
		var adapter: Dictionary = CampaignModel.make_window_adapter(
			catalog, key, scope, checkpoint, GLOBAL_SCOPE, global_receipt, signals
		)
		var acceptance: Dictionary = CampaignModel.make_window_acceptance(
			String(window.get("window_id", "")), scope, checkpoint,
			String(adapter.get("adapter_receipt", ""))
		)
		adapters.append(adapter)
		acceptances.append(acceptance)
	return {"adapters": adapters, "acceptances": acceptances}


func _make_evidence(fixture: Dictionary) -> Dictionary:
	return ReconModel.make_evidence_envelope(
		fixture["catalog"], fixture["atlas"], fixture["atlas_state"],
		String(fixture["atlas_state"].get("state_receipt", "")),
		fixture["network_catalog"], fixture["network_state"],
		String(fixture["network_state"].get("state_receipt", "")),
		fixture["intel"], fixture["campaign_catalog"], fixture["campaign0"],
		String(fixture["campaign0"].get("state_receipt", "")),
		CAMPAIGN_SCOPE, fixture["covenant_catalog"], fixture["covenant_state"],
		String(fixture["covenant_state"].get("state_receipt", "")),
		fixture["obligation"], GLOBAL_SCOPE
	)


func _make_board(state: Dictionary, evidence: Dictionary,
		anchor: Dictionary) -> Dictionary:
	return ReconModel.make_portfolio_board(
		_root_fixture["campaign_catalog"], _root_fixture["covenant_catalog"],
		_catalog, state, String(state.get("state_receipt", "")), evidence,
		String(evidence.get("evidence_receipt", "")), anchor, RECON_SCOPE,
		_recon_checkpoint, String(anchor.get("anchor_receipt", ""))
	)


func _commit(state: Dictionary, evidence: Dictionary, anchor: Dictionary,
		board: Dictionary, choice: Dictionary) -> Dictionary:
	return ReconModel.commit_portfolio(
		_root_fixture["campaign_catalog"], _root_fixture["covenant_catalog"],
		_catalog, state, String(state.get("state_receipt", "")), evidence,
		String(evidence.get("evidence_receipt", "")), anchor, RECON_SCOPE,
		_recon_checkpoint, String(anchor.get("anchor_receipt", "")), board,
		choice
	)


func _build_branch(pair_key: String, signal_map: Dictionary,
		variant: String) -> Dictionary:
	var board: Dictionary = _boards[2]
	var anchor: Dictionary = _anchors[2]
	var roles: Array = PAIR_ROLES[pair_key]
	var option := _portfolio_option(board, roles)
	var choice: Dictionary = ReconModel.make_portfolio_choice(
		_catalog, board, String(option.get("portfolio_id", ""))
	)
	var commit := _commit(_state0, _evidence, anchor, board, choice)
	var committed: Dictionary = commit.get("after_state", {})
	var report_checkpoint := _external_receipt(
		"rp9-report-owner-%s-%s" % [pair_key, variant]
	)
	var reports: Array[Dictionary] = []
	for raw_probe in committed.get("commitment_record", {}).get(
			"selected_probes", []) as Array:
		if raw_probe is Dictionary:
			var probe: Dictionary = raw_probe
			var role := String(probe.get("role", ""))
			reports.append({
				"probe_id": String(probe.get("probe_id", "")),
				"signal": String(signal_map.get(role, "mixed")),
				"source_receipt": _external_receipt(
					"rp9-report-source-%s-%s-%s" % [pair_key, variant, role]
				),
			})
	var bundle: Dictionary = ReconModel.make_observation_bundle(
		_catalog, committed, String(committed.get("state_receipt", "")),
		RECON_SCOPE, report_checkpoint, reports
	)
	var resolution: Dictionary = ReconModel.resolve_portfolio(
		_root_fixture["campaign_catalog"], _root_fixture["covenant_catalog"],
		_catalog, committed, String(committed.get("state_receipt", "")),
		_root_fixture["campaign0"],
		String(_root_fixture["campaign0"].get("state_receipt", "")),
		CAMPAIGN_SCOPE, _root_fixture["covenant_state"],
		String(_root_fixture["covenant_state"].get("state_receipt", "")),
		GLOBAL_SCOPE, bundle, RECON_SCOPE, report_checkpoint,
		String(bundle.get("bundle_receipt", ""))
	)
	var resolved: Dictionary = resolution.get("after_state", {})
	var committed_projection := ReconModel.project_beliefs(
		_catalog, committed, String(committed.get("state_receipt", ""))
	)
	var resolved_projection := ReconModel.project_beliefs(
		_catalog, resolved, String(resolved.get("state_receipt", ""))
	)
	for value in [option, choice, commit, committed, bundle, resolution, resolved,
			committed_projection, resolved_projection]:
		if not (value is Dictionary) or (value as Dictionary).is_empty():
			return {}
	return {
		"pair_key": pair_key,
		"roles": roles.duplicate(),
		"option": option,
		"choice": choice,
		"commit": commit,
		"committed": committed,
		"report_checkpoint": report_checkpoint,
		"reports": reports,
		"bundle": bundle,
		"resolution": resolution,
		"resolved": resolved,
		"committed_projection": committed_projection,
		"resolved_projection": resolved_projection,
	}


func _validate_real_fixtures() -> bool:
	if not ReconModel.validate_catalog(
			_root_fixture["campaign_catalog"], _root_fixture["covenant_catalog"],
			_catalog
		).is_empty():
		return _fixture_error("catalog validator rejected exact catalog")
	if not ReconModel.validate_evidence_envelope(
			_catalog, _root_fixture["atlas"], _root_fixture["atlas_state"],
			String(_root_fixture["atlas_state"].get("state_receipt", "")),
			_root_fixture["network_catalog"], _root_fixture["network_state"],
			String(_root_fixture["network_state"].get("state_receipt", "")),
			_root_fixture["intel"], _root_fixture["campaign_catalog"],
			_root_fixture["campaign0"],
			String(_root_fixture["campaign0"].get("state_receipt", "")),
			CAMPAIGN_SCOPE, _root_fixture["covenant_catalog"],
			_root_fixture["covenant_state"],
			String(_root_fixture["covenant_state"].get("state_receipt", "")),
			_root_fixture["obligation"], GLOBAL_SCOPE, _evidence
		).is_empty():
		return _fixture_error("evidence validator rejected exact evidence")
	if not ReconModel.validate_state(_catalog, _state0).is_empty():
		return _fixture_error("initial state validator rejected state")
	var capacity_values: Array = _anchors.keys()
	capacity_values.sort()
	for raw_points in capacity_values:
		var points := int(raw_points)
		var anchor: Dictionary = _anchors[points]
		var board: Dictionary = _boards[points]
		if not ReconModel.validate_recon_anchor(
				anchor, RECON_SCOPE, _recon_checkpoint,
				String(anchor.get("anchor_receipt", ""))
			).is_empty():
			return _fixture_error("capacity anchor validator rejected %d" % points)
		if not ReconModel.validate_portfolio_board(
				_root_fixture["campaign_catalog"], _root_fixture["covenant_catalog"],
				_catalog, _state0, String(_state0.get("state_receipt", "")),
				_evidence, String(_evidence.get("evidence_receipt", "")),
				anchor, RECON_SCOPE, _recon_checkpoint,
				String(anchor.get("anchor_receipt", "")), board
			).is_empty():
			return _fixture_error("portfolio board validator rejected %d" % points)
	for collection in [_branches, _inverse_branches]:
		for pair_key in PAIR_KEYS:
			var branch: Dictionary = collection[String(pair_key)]
			if not _validate_branch(branch):
				return false
	var stale_source: Dictionary = _branches["duty_fallback"]
	var committed: Dictionary = stale_source["committed"]
	if not ReconModel.validate_stale_proposal(
			_root_fixture["campaign_catalog"], _root_fixture["covenant_catalog"],
			_catalog, committed, String(committed.get("state_receipt", "")),
			_root_fixture["campaign1"],
			String(_root_fixture["campaign1"].get("state_receipt", "")),
			CAMPAIGN_SCOPE, _root_fixture["covenant_state"],
			String(_root_fixture["covenant_state"].get("state_receipt", "")),
			GLOBAL_SCOPE, _stale_proposal
		).is_empty():
		return _fixture_error("stale validator rejected changed campaign snapshot")
	if String(_stale_projection.get("lifecycle_status", "")) != "stale" \
			or String(_stale_proposal.get("stale_record", {}).get(
				"stale_reason", "")) != "campaign_changed" \
			or int(_stale_proposal.get("recon_points_refunded", -1)) != 0:
		return _fixture_error("stale fixture violated no-refund causal contract")
	return true


func _validate_branch(branch: Dictionary) -> bool:
	var board: Dictionary = _boards[2]
	var anchor: Dictionary = _anchors[2]
	var choice: Dictionary = branch["choice"]
	var commit: Dictionary = branch["commit"]
	var committed: Dictionary = branch["committed"]
	var bundle: Dictionary = branch["bundle"]
	var resolution: Dictionary = branch["resolution"]
	var resolved: Dictionary = branch["resolved"]
	if not ReconModel.validate_portfolio_choice(_catalog, board, choice).is_empty():
		return _fixture_error("choice validator rejected %s" % branch["pair_key"])
	if not ReconModel.validate_commit_proposal(
			_root_fixture["campaign_catalog"], _root_fixture["covenant_catalog"],
			_catalog, _state0, String(_state0.get("state_receipt", "")),
			_evidence, String(_evidence.get("evidence_receipt", "")), anchor,
			RECON_SCOPE, _recon_checkpoint, String(anchor.get("anchor_receipt", "")),
			board, choice, commit
		).is_empty():
		return _fixture_error("commit validator rejected %s" % branch["pair_key"])
	if not ReconModel.validate_observation_bundle(
			_catalog, committed, String(committed.get("state_receipt", "")),
			RECON_SCOPE, String(branch["report_checkpoint"]),
			String(bundle.get("bundle_receipt", "")), bundle
		).is_empty():
		return _fixture_error("observation validator rejected %s" % branch["pair_key"])
	if not ReconModel.validate_resolution_proposal(
			_root_fixture["campaign_catalog"], _root_fixture["covenant_catalog"],
			_catalog, committed, String(committed.get("state_receipt", "")),
			_root_fixture["campaign0"],
			String(_root_fixture["campaign0"].get("state_receipt", "")),
			CAMPAIGN_SCOPE, _root_fixture["covenant_state"],
			String(_root_fixture["covenant_state"].get("state_receipt", "")),
			GLOBAL_SCOPE, bundle, RECON_SCOPE, String(branch["report_checkpoint"]),
			String(bundle.get("bundle_receipt", "")), resolution
		).is_empty():
		return _fixture_error("resolution validator rejected %s" % branch["pair_key"])
	if not ReconModel.validate_state(_catalog, resolved).is_empty() \
			or String(branch["resolved_projection"].get("semantics", "")) \
			!= "epistemic_support_band_not_truth_or_probability" \
			or not bool(branch["resolved_projection"].get("observation_pure", false)):
		return _fixture_error("belief projection violated pure epistemic contract")
	return true


func _fixture_error(message: String) -> bool:
	push_error("PlanetReconPortfolioLab: " + message)
	return false


func _cargo(food: Variant, meds: Variant, parts: Variant,
		scrap: Variant) -> Dictionary:
	return {"food": food, "meds": meds, "parts": parts, "scrap": scrap}


func _source_refs(catalog: Dictionary) -> Array:
	return [{
		"schema": NetworkModel.SOURCE_REF_SCHEMA,
		"kind": "site_visit",
		"source_id": "svt1:rp9-provenance",
		"source_address": _context_site(catalog, "ash_market"),
		"source_receipt": _external_receipt("site-visit-provenance"),
	}, {
		"schema": NetworkModel.SOURCE_REF_SCHEMA,
		"kind": "expedition_outcome",
		"source_id": "outcome-rp9-provenance",
		"source_address": "",
		"source_receipt": _external_receipt("expedition-provenance"),
	}]


func _network_option(catalog: Dictionary, board: Dictionary,
		key: String) -> Dictionary:
	var offer_id := ""
	for raw_offer in catalog.get("offers", []) as Array:
		if raw_offer is Dictionary and String((raw_offer as Dictionary).get(
				"offer_key", "")) == key:
			offer_id = String((raw_offer as Dictionary).get("offer_id", ""))
	for raw_option in board.get("options", []) as Array:
		if raw_option is Dictionary and String((raw_option as Dictionary).get(
				"offer_id", "")) == offer_id:
			return (raw_option as Dictionary).duplicate(true)
	return {}


func _network_node_tile(catalog: Dictionary, node_id: String) -> String:
	for raw_node in catalog.get("nodes", []) as Array:
		if raw_node is Dictionary and String((raw_node as Dictionary).get(
				"node_id", "")) == node_id:
			return String((raw_node as Dictionary).get("tile_id", ""))
	return ""


func _context_site(catalog: Dictionary, key: String) -> String:
	for raw_site in catalog.get("context_sites", []) as Array:
		if raw_site is Dictionary and String((raw_site as Dictionary).get(
				"site_key", "")) == key:
			return String((raw_site as Dictionary).get("site_id", ""))
	return ""


func _site_tile(atlas: Dictionary, key: String) -> String:
	for raw_tile in atlas.get("tiles", []) as Array:
		if raw_tile is Dictionary and String((raw_tile as Dictionary).get(
				"site_key", "")) == key:
			return String((raw_tile as Dictionary).get("id", ""))
	return ""


func _campaign_window(catalog: Dictionary, key: String) -> Dictionary:
	for raw_window in catalog.get("windows", []) as Array:
		if raw_window is Dictionary and String((raw_window as Dictionary).get(
				"window_key", "")) == key:
			return (raw_window as Dictionary).duplicate(true)
	return {}


func _window_by_id(window_id: String) -> Dictionary:
	for raw_window in _root_fixture["campaign_catalog"].get("windows", []) as Array:
		if raw_window is Dictionary and String((raw_window as Dictionary).get(
				"window_id", "")) == window_id:
			return (raw_window as Dictionary).duplicate(true)
	return {}


func _covenant_option(board: Dictionary, action: String) -> Dictionary:
	for raw_option in board.get("options", []) as Array:
		if raw_option is Dictionary and String((raw_option as Dictionary).get(
				"required_action", "")) == action:
			return (raw_option as Dictionary).duplicate(true)
	return {}


func _portfolio_option(board: Dictionary, roles: Array) -> Dictionary:
	var wanted: Array[String] = []
	for role in roles:
		wanted.append(String(role))
	wanted.sort()
	for raw_option in board.get("options", []) as Array:
		if raw_option is Dictionary:
			var actual: Array[String] = []
			for role in (raw_option as Dictionary).get("role_pair", []) as Array:
				actual.append(String(role))
			actual.sort()
			if actual == wanted:
				return (raw_option as Dictionary).duplicate(true)
	return {}


func _external_receipt(label: String) -> String:
	return _receipt_for(["rp9-external-owner-checkpoint", label])


func _receipt_for(value: Variant) -> String:
	var encoded := _canonical_json(value)
	if encoded == "":
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK \
			or context.update(encoded.to_utf8_buffer()) != OK:
		return ""
	return "sha256:" + context.finish().hex_encode()


func _canonical_json(value: Variant) -> String:
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
					or absf(number) > float(ReconModel.MAX_SAFE_JSON_INT):
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
				fields.append(JSON.stringify(key) + ":" + encoded)
			return "{" + ",".join(fields) + "}"
	return ""


func _display_branch() -> Dictionary:
	var pair_index := _selected_pair
	match _fixture:
		FIXTURE_DUTY_SPILLOVER:
			pair_index = 0
		FIXTURE_DUTY_FALLBACK, FIXTURE_STALE:
			pair_index = 1
		FIXTURE_SPILLOVER_FALLBACK:
			pair_index = 2
	var collection := _inverse_branches if _signal_set == "inverse" else _branches
	return collection.get(String(PAIR_KEYS[pair_index]), {})


func _display_state() -> Dictionary:
	if _view_stage == STAGE_PRIOR:
		return _state0
	var branch := _display_branch()
	if branch.is_empty():
		return {}
	if _view_stage == STAGE_COMMITTED:
		return branch["committed"]
	if _fixture == FIXTURE_STALE:
		return _stale_proposal.get("after_state", {})
	return branch["resolved"]


func _display_projection() -> Dictionary:
	if _view_stage == STAGE_PRIOR:
		return _initial_projection
	var branch := _display_branch()
	if branch.is_empty():
		return {}
	if _view_stage == STAGE_COMMITTED:
		return branch["committed_projection"]
	if _fixture == FIXTURE_STALE:
		return _stale_projection
	return branch["resolved_projection"]


func _display_board() -> Dictionary:
	return _boards.get(_capacity_points, {})


func _selected_roles() -> Array:
	if _fixture == FIXTURE_PRIORS and _view_stage == STAGE_PRIOR:
		return []
	var branch := _display_branch()
	if branch.is_empty():
		return []
	return (branch["roles"] as Array).duplicate()


func _belief_by_role(state: Dictionary, role: String) -> Dictionary:
	for raw_belief in state.get("beliefs", []) as Array:
		if raw_belief is Dictionary and String((raw_belief as Dictionary).get(
				"role", "")) == role:
			return (raw_belief as Dictionary).duplicate(true)
	return {}


func _assignment_by_role(role: String) -> Dictionary:
	for raw_assignment in _evidence.get("role_assignments", []) as Array:
		if raw_assignment is Dictionary and String((raw_assignment as Dictionary).get(
				"role", "")) == role:
			return (raw_assignment as Dictionary).duplicate(true)
	return {}


func _window_key_for_role(role: String) -> String:
	var assignment := _assignment_by_role(role)
	var window := _window_by_id(String(assignment.get("window_id", "")))
	return String(window.get("window_key", ""))


func _window_label(key: String) -> String:
	match key:
		"basin_relief":
			return "BASIN RELIEF"
		"meridian_trade":
			return "MERIDIAN TRADE"
		"nightward_fortify":
			return "NIGHTWARD FORTIFY"
	return key.replace("_", " ").to_upper()


func _face_for_role(role: String) -> int:
	var assignment := _assignment_by_role(role)
	var address: Dictionary = ScaleAddress.parse_id(
		String(assignment.get("region_id", ""))
	)
	return int(address.get("face", -1))


func _role_color(role: String) -> Color:
	match role:
		"duty":
			return C_TEAL
		"spillover":
			return C_BLUE
	return C_GOLD


func _role_short(role: String) -> String:
	match role:
		"duty":
			return "D"
		"spillover":
			return "S"
	return "F"


func _pair_label(pair_key: String) -> String:
	var index := PAIR_KEYS.find(pair_key)
	return String(PAIR_LABELS[index]) if index >= 0 else pair_key.to_upper()


func _receipt_suffix(receipt: String) -> String:
	return receipt.right(8) if receipt.length() >= 8 else receipt


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, DESIGN), C_BG)
	_draw_noise_field()
	_draw_header()
	_draw_fixture_rail()
	_panel(
		MAIN_PANEL, "BELIEF PORTFOLIO / 2 OF 3",
		"SUPPORT BAND BP / NOT PROBABILITY"
	)
	_panel(SIDE_PANEL, "CAPACITY / CAUSAL AUTHORITY")
	if _load_ok:
		_draw_covenant_strip()
		_draw_interval_register()
		_draw_bottom_strip()
		_draw_side_panel()
	else:
		_text(
			"PLANET RECON PORTFOLIO CONTRACT FAILED",
			Vector2(70.0, 240.0), 20, C_DANGER
		)
	_draw_footer()


func _draw_noise_field() -> void:
	for index in range(190):
		var x := float((index * 97 + 31) % 1280)
		var y := float((index * 53 + 17) % 768)
		draw_rect(Rect2(x, y, 2.0, 2.0), Color(0.72, 0.67, 0.48, 0.035))


func _draw_header() -> void:
	draw_rect(HEADER_RECT, C_HEADER)
	draw_line(Vector2(0.0, 71.0), Vector2(1280.0, 71.0), C_EDGE, 1.0)
	_text("PLANET RECON PORTFOLIO LAB // RP-0009", Vector2(24.0, 31.0), 22, C_TEXT)
	_text(
		"Spend two recon points to narrow two support bands before the covenant is due.",
		Vector2(24.0, 55.0), 13, C_MUTED
	)
	_text(
		"EXCHANGE CHARTER / ACTIVE",
		Vector2(930.0, 31.0), 13, C_GOLD, 326.0,
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	_text(
		_header_status(), Vector2(880.0, 55.0), 9,
		C_DANGER if _fixture == FIXTURE_STALE else C_MUTED, 376.0,
		HORIZONTAL_ALIGNMENT_RIGHT
	)


func _header_status() -> String:
	if not _load_ok:
		return "MODEL CONTRACT FAILED"
	var lifecycle := String(_display_projection().get("lifecycle_status", ""))
	if _fixture == FIXTURE_BOARD and _view_stage == STAGE_PRIOR:
		return String(_display_board().get("decision_status", "")).to_upper()
	if _fixture == FIXTURE_STALE and _view_stage == STAGE_TERMINAL:
		return "STALE / CAMPAIGN SNAPSHOT CHANGED / REFUND 0"
	return "%s / EPISTEMIC BAND ONLY" % lifecycle.to_upper()


func _draw_fixture_rail() -> void:
	_fixture_rects.clear()
	for index in range(6):
		var card_rect := Rect2(24.0 + float(index) * 204.0, 88.0, 196.0, 66.0)
		_fixture_rects.append(card_rect)
		var selected := index == _fixture
		var accent := _fixture_color(index)
		draw_rect(
			Rect2(card_rect.position + Vector2(3.0, 4.0), card_rect.size),
			Color(0.0, 0.0, 0.0, 0.22)
		)
		draw_rect(card_rect, C_CARD_HI if selected else C_CARD)
		draw_rect(
			card_rect, accent if selected else C_EDGE, false,
			2.0 if selected else 1.0
		)
		draw_rect(Rect2(card_rect.position, Vector2(5.0, card_rect.size.y)), accent)
		_text(
			String(FIXTURE_TITLES[index]), card_rect.position + Vector2(14.0, 27.0),
			11, C_TEXT if selected else C_MUTED
		)
		_text(
			String(FIXTURE_SUBTITLES[index]).to_upper(),
			card_rect.position + Vector2(14.0, 48.0), 8,
			accent if selected else C_MUTED
		)


func _fixture_color(index: int) -> Color:
	match index:
		FIXTURE_DUTY_SPILLOVER:
			return C_BLUE
		FIXTURE_DUTY_FALLBACK, FIXTURE_SPILLOVER_FALLBACK:
			return C_TEAL
		FIXTURE_STALE:
			return C_DANGER
	return C_GOLD


func _panel(panel_rect: Rect2, title: String, legend: String = "") -> void:
	draw_rect(
		Rect2(panel_rect.position + Vector2(4.0, 5.0), panel_rect.size),
		Color(0.0, 0.0, 0.0, 0.25)
	)
	draw_rect(panel_rect, C_PANEL)
	draw_rect(panel_rect, C_EDGE, false, 1.0)
	draw_rect(
		Rect2(panel_rect.position, Vector2(panel_rect.size.x, 31.0)), C_PANEL_2
	)
	_text(title, panel_rect.position + Vector2(13.0, 22.0), 13, C_GOLD)
	if legend != "":
		_text(
			legend,
			panel_rect.position + Vector2(panel_rect.size.x - 278.0, 22.0),
			8, C_MUTED, 264.0, HORIZONTAL_ALIGNMENT_RIGHT
		)


func _draw_covenant_strip() -> void:
	var strip := Rect2(48.0, 214.0, 776.0, 72.0)
	draw_rect(strip, C_TRACK)
	draw_rect(strip, C_EDGE, false, 1.0)
	draw_rect(Rect2(strip.position, Vector2(5.0, strip.size.y)), C_GOLD)
	_text("ACTIVE COVENANT", strip.position + Vector2(16.0, 20.0), 8, C_MUTED)
	_text("EXCHANGE CHARTER", strip.position + Vector2(16.0, 45.0), 16, C_TEXT)
	_text("TRADE / SPRING", strip.position + Vector2(206.0, 28.0), 10, C_GOLD)
	_text("DUE AUTUMN", strip.position + Vector2(206.0, 50.0), 10, C_TEXT)
	var mapping_x := 344.0
	for index in range(3):
		var role := String(ROLES[index])
		var key := _window_key_for_role(role)
		var face := _face_for_role(role)
		var x := strip.position.x + mapping_x + float(index) * 139.0
		_text(role.to_upper(), Vector2(x, strip.position.y + 22.0), 8, _role_color(role))
		_text(
			"%s / F%d" % [_window_label(key).split(" ")[0], face],
			Vector2(x, strip.position.y + 45.0), 9, C_TEXT, 128.0
		)
	_text(
		"ROLE ASSIGNMENT / NOT GEOGRAPHY", strip.position + Vector2(344.0, 63.0),
		7, C_MUTED, 410.0, HORIZONTAL_ALIGNMENT_RIGHT
	)


func _draw_interval_register() -> void:
	var register := Rect2(48.0, 298.0, 776.0, 266.0)
	draw_rect(register, C_CARD)
	draw_rect(register, C_EDGE, false, 1.0)
	_text("EPISTEMIC SUPPORT BAND", register.position + Vector2(13.0, 21.0), 10, C_TEXT)
	_text(
		"0", Vector2(260.0, register.position.y + 22.0), 8, C_MUTED,
		40.0, HORIZONTAL_ALIGNMENT_CENTER
	)
	for index in range(1, 5):
		var value := index * 2500
		var x := 260.0 + 520.0 * float(index) / 4.0
		_text(
			str(value), Vector2(x - 30.0, register.position.y + 22.0),
			8, C_MUTED, 60.0, HORIZONTAL_ALIGNMENT_CENTER
		)
	var state := _display_state()
	var selected := _selected_roles()
	for index in range(3):
		var role := String(ROLES[index])
		var row := Rect2(60.0, 330.0 + float(index) * 74.0, 752.0, 66.0)
		_draw_belief_row(row, role, state, role in selected)


func _draw_belief_row(row: Rect2, role: String, state: Dictionary,
		selected: bool) -> void:
	var belief := _belief_by_role(state, role)
	var prior := _belief_by_role(_state0, role)
	var key := _window_key_for_role(role)
	var accent := _role_color(role)
	var observed := String(belief.get("status", "")) == "observed"
	draw_rect(row, C_CARD_HI if selected else C_TRACK)
	draw_rect(row, accent if selected else C_EDGE, false, 1.0)
	draw_rect(Rect2(row.position, Vector2(4.0, row.size.y)), accent if selected else C_EDGE)
	_text(
		"%s / %s" % [role.to_upper(), _window_label(key)],
		row.position + Vector2(12.0, 20.0), 10, C_TEXT
	)
	var grounding := String(prior.get("grounding_status", "")).replace("_", " ")
	_text(
		"%s / PRIOR WIDTH %d" % [grounding.to_upper(), int(prior.get("width_bp", 0))],
		row.position + Vector2(12.0, 43.0), 8,
		C_GOLD if grounding == "grounded" else C_MUTED
	)
	var axis_x := 260.0
	var axis_width := 520.0
	var track_y := row.position.y + 37.0
	draw_rect(Rect2(axis_x, track_y, axis_width, 10.0), Color(0.05, 0.06, 0.05, 0.9))
	for tick in range(5):
		var tick_x := axis_x + axis_width * float(tick) / 4.0
		draw_line(
			Vector2(tick_x, track_y - 4.0), Vector2(tick_x, track_y + 14.0),
			Color(C_EDGE, 0.55), 1.0
		)
	var prior_min := int(prior.get("minimum_bp", 0))
	var prior_max := int(prior.get("maximum_bp", 0))
	var prior_x := axis_x + axis_width * float(prior_min) / 10000.0
	var prior_w := axis_width * float(prior_max - prior_min) / 10000.0
	draw_rect(Rect2(prior_x, track_y - 4.0, prior_w, 18.0), Color(accent, 0.12))
	draw_rect(Rect2(prior_x, track_y - 4.0, prior_w, 18.0), Color(accent, 0.55), false, 1.0)
	if observed:
		var after_min := int(belief.get("minimum_bp", 0))
		var after_max := int(belief.get("maximum_bp", 0))
		var after_x := axis_x + axis_width * float(after_min) / 10000.0
		var after_w := axis_width * float(after_max - after_min) / 10000.0
		draw_rect(Rect2(after_x, track_y, after_w, 10.0), accent)
		draw_rect(Rect2(after_x, track_y - 4.0, after_w, 18.0), accent, false, 2.0)
		_text(
			"%s / [%d—%d] / WIDTH %d" % [
				String(belief.get("observed_signal", "")).to_upper(), after_min,
				after_max, int(belief.get("width_bp", 0)),
			], Vector2(axis_x, row.position.y + 22.0), 8, accent, axis_width,
			HORIZONTAL_ALIGNMENT_RIGHT
		)
	else:
		var status := "SELECTED / AWAITING REPORT" if selected \
			and _view_stage == STAGE_COMMITTED else (
				"FOCUS / NO RANK" if selected and _fixture == FIXTURE_BOARD \
				else "UNOBSERVED / PRIOR RETAINED"
			)
		_text(
			"%s / [%d—%d]" % [status, prior_min, prior_max],
			Vector2(axis_x, row.position.y + 22.0), 8,
			accent if selected else C_MUTED, axis_width,
			HORIZONTAL_ALIGNMENT_RIGHT
		)


func _draw_bottom_strip() -> void:
	var strip := Rect2(48.0, 576.0, 776.0, 82.0)
	draw_rect(strip, C_TRACK)
	draw_rect(strip, C_EDGE, false, 1.0)
	if _fixture == FIXTURE_BOARD and _view_stage == STAGE_PRIOR:
		_draw_portfolio_cards(strip)
	elif _fixture == FIXTURE_PRIORS and _view_stage == STAGE_PRIOR:
		_draw_prior_contract(strip)
	elif _fixture == FIXTURE_STALE and _view_stage == STAGE_TERMINAL:
		_draw_stale_chain(strip)
	else:
		_draw_resolution_chain(strip)


func _draw_prior_contract(strip: Rect2) -> void:
	_text("CAPACITY CONTRACT", strip.position + Vector2(14.0, 21.0), 9, C_GOLD)
	_text("2 RECON POINTS", strip.position + Vector2(14.0, 49.0), 14, C_TEXT)
	_text("EXACTLY TWO PROBES", strip.position + Vector2(176.0, 49.0), 11, C_TEAL)
	_text(
		"Choose which role stays wide; no scalar recommendation.",
		strip.position + Vector2(380.0, 49.0), 9, C_MUTED, 380.0,
		HORIZONTAL_ALIGNMENT_RIGHT
	)


func _draw_portfolio_cards(strip: Rect2) -> void:
	var board := _display_board()
	if String(board.get("decision_status", "")) != "portfolios_available":
		_text(
			String(board.get("decision_status", "")).replace("_", " ").to_upper(),
			strip.position + Vector2(14.0, 33.0), 13, C_DANGER
		)
		_text(
			"%d POINTS / COST 2 / NO ELIGIBLE PAIR" % _capacity_points,
			strip.position + Vector2(14.0, 58.0), 9, C_MUTED
		)
		return
	for index in range(3):
		var pair_key := String(PAIR_KEYS[index])
		var roles: Array = PAIR_ROLES[pair_key]
		var option := _portfolio_option(board, roles)
		var card := Rect2(
			strip.position + Vector2(10.0 + float(index) * 255.0, 9.0),
			Vector2(245.0, 64.0)
		)
		var focused := index == _selected_pair
		draw_rect(card, C_CARD_HI if focused else C_CARD)
		draw_rect(card, C_TEAL if focused else C_EDGE, false, 1.0)
		_text(
			"%d  %s" % [index + 1, _pair_label(pair_key)],
			card.position + Vector2(10.0, 20.0), 8, C_TEXT
		)
		var vector_copy := ""
		for raw_delta in option.get("reduction_vector", []) as Array:
			if raw_delta is Dictionary:
				var delta: Dictionary = raw_delta
				vector_copy += "%s -%d   " % [
					_role_short(String(delta.get("role", ""))),
					int(delta.get("reduction_bp", 0)),
				]
		_text(
			vector_copy.strip_edges(), card.position + Vector2(10.0, 43.0),
			8, C_TEAL if focused else C_MUTED
		)
		_text(
			"ROLE VECTOR / NO TOTAL", card.position + Vector2(10.0, 57.0),
			7, C_MUTED
		)


func _draw_resolution_chain(strip: Rect2) -> void:
	var branch := _display_branch()
	var pair_copy := _pair_label(String(branch.get("pair_key", "")))
	var stages := [
		["COMMIT", "BELIEF + CAPACITY", C_GOLD],
		["TYPED REPORTS", pair_copy, C_BLUE],
		["RESOLVE", "BELIEF ONLY", C_TEAL],
	]
	for index in range(3):
		var block := Rect2(
			strip.position + Vector2(12.0 + float(index) * 252.0, 10.0),
			Vector2(228.0, 60.0)
		)
		var data: Array = stages[index]
		draw_rect(block, C_CARD)
		draw_rect(block, data[2] as Color, false, 1.0)
		_text(String(data[0]), block.position + Vector2(10.0, 23.0), 9, data[2] as Color)
		_text(String(data[1]), block.position + Vector2(10.0, 45.0), 8, C_TEXT)
		if index < 2:
			draw_line(
				Vector2(block.end.x + 4.0, block.get_center().y),
				Vector2(block.end.x + 18.0, block.get_center().y), C_EDGE_HI, 2.0
			)
	_text(
		"COMMIT DOES NOT CHANGE BANDS / WORLD OWNERS READ ONLY",
		strip.position + Vector2(474.0, 76.0), 7, C_MUTED, 286.0,
		HORIZONTAL_ALIGNMENT_RIGHT
	)


func _draw_stale_chain(strip: Rect2) -> void:
	var stages := [
		["COMMIT D + F", "CAPACITY 2 → 0", C_GOLD],
		["RP7 SNAPSHOT", "ACCEPTED RECEIPT CHANGED", C_DANGER],
		["CLOSE STALE", "REFUND 0 / BANDS UNCHANGED", C_DANGER],
	]
	for index in range(3):
		var block := Rect2(
			strip.position + Vector2(12.0 + float(index) * 252.0, 10.0),
			Vector2(228.0, 60.0)
		)
		var data: Array = stages[index]
		draw_rect(block, C_CARD)
		draw_rect(block, data[2] as Color, false, 1.0)
		_text(String(data[0]), block.position + Vector2(10.0, 23.0), 9, data[2] as Color)
		_text(String(data[1]), block.position + Vector2(10.0, 45.0), 8, C_TEXT)
		if index < 2:
			draw_line(
				Vector2(block.end.x + 4.0, block.get_center().y),
				Vector2(block.end.x + 18.0, block.get_center().y), C_EDGE_HI, 2.0
			)


func _draw_side_panel() -> void:
	_draw_capacity_card()
	_draw_decision_card()
	_draw_authority_card()


func _draw_capacity_card() -> void:
	var card := Rect2(888.0, 214.0, 344.0, 88.0)
	_card(card, C_DANGER if _fixture == FIXTURE_STALE else C_GOLD)
	_text("RECON CAPACITY ANCHOR", card.position + Vector2(14.0, 20.0), 8, C_MUTED)
	var spent := _view_stage != STAGE_PRIOR
	var value_copy := "%d → 0" % _capacity_points if spent else "%d AVAILABLE" % _capacity_points
	_text(value_copy, card.position + Vector2(14.0, 50.0), 19, C_TEXT)
	_text(
		"COST 2 / TWO PROBES", card.position + Vector2(164.0, 48.0), 9,
		C_GOLD, 162.0, HORIZONTAL_ALIGNMENT_RIGHT
	)
	_text(
		"OWNER %s" % _receipt_suffix(_recon_checkpoint),
		card.position + Vector2(14.0, 73.0), 8, C_MUTED
	)


func _draw_decision_card() -> void:
	var card := Rect2(888.0, 314.0, 344.0, 218.0)
	var accent := C_DANGER if _fixture == FIXTURE_STALE \
		and _view_stage == STAGE_TERMINAL else C_TEAL
	_card(card, accent)
	var projection := _display_projection()
	_text("CURRENT BELIEF DECISION", card.position + Vector2(14.0, 20.0), 8, C_MUTED)
	_text(
		String(projection.get("lifecycle_status", "")).replace("_", " ").to_upper(),
		card.position + Vector2(14.0, 47.0), 15, accent
	)
	var branch := _display_branch()
	var pair_copy := "NONE / PRIORS ONLY" if _fixture == FIXTURE_PRIORS \
		and _view_stage == STAGE_PRIOR else _pair_label(String(branch.get("pair_key", "")))
	var pair_field := "FOCUS" if _fixture == FIXTURE_BOARD \
		and _view_stage == STAGE_PRIOR else "PAIR"
	if pair_field == "FOCUS":
		pair_copy += " / NO RANK"
	_text(pair_field, card.position + Vector2(14.0, 72.0), 8, C_MUTED)
	_text(pair_copy, card.position + Vector2(74.0, 72.0), 9, C_TEXT, 250.0)
	if _fixture == FIXTURE_STALE and _view_stage == STAGE_TERMINAL:
		var stale_record: Dictionary = _stale_proposal.get("stale_record", {})
		_text("CAUSE", card.position + Vector2(14.0, 100.0), 8, C_MUTED)
		_text(
			String(stale_record.get("stale_reason", "")).replace("_", " ").to_upper(),
			card.position + Vector2(74.0, 100.0), 9, C_DANGER
		)
		_text("REPORTS", card.position + Vector2(14.0, 128.0), 8, C_MUTED)
		_text("NONE APPLIED", card.position + Vector2(74.0, 128.0), 9, C_TEXT)
		_text("REFUND", card.position + Vector2(14.0, 156.0), 8, C_MUTED)
		_text("0", card.position + Vector2(74.0, 156.0), 10, C_DANGER)
		_text(
			"PRIORS RETAINED / CYCLE TERMINAL",
			card.position + Vector2(14.0, 193.0), 8, C_MUTED
		)
		return
	var state := _display_state()
	var y := 101.0
	for role in ROLES:
		var belief := _belief_by_role(state, String(role))
		var status := String(belief.get("status", ""))
		var detail := "PRIOR RETAINED"
		if status == "observed":
			detail = "%s / %d—%d" % [
				String(belief.get("observed_signal", "")).to_upper(),
				int(belief.get("minimum_bp", 0)), int(belief.get("maximum_bp", 0)),
			]
		elif String(role) in _selected_roles() and _view_stage == STAGE_COMMITTED:
			detail = "AWAITING REPORT"
		_text(String(role).to_upper(), card.position + Vector2(14.0, y), 8, _role_color(String(role)))
		_text(detail, card.position + Vector2(100.0, y), 8, C_TEXT, 225.0)
		y += 27.0
	_text(
		"OWNER ORDER  %s" % (
			"BELIEF + RECON CAPACITY" if _view_stage == STAGE_COMMITTED \
			else ("BELIEF ONLY" if _view_stage == STAGE_TERMINAL else "NONE")
		), card.position + Vector2(14.0, 201.0), 8, C_MUTED
	)


func _draw_authority_card() -> void:
	var card := Rect2(888.0, 544.0, 344.0, 114.0)
	var stale_view := _fixture == FIXTURE_STALE and _view_stage == STAGE_TERMINAL
	_card(card, C_DANGER if stale_view else C_BLUE)
	if stale_view:
		_text("CHANGED ACCEPTED SNAPSHOT", card.position + Vector2(14.0, 20.0), 8, C_DANGER)
		_text(
			"RP7  %s → %s" % [
				_receipt_suffix(String(_evidence.get("accepted_campaign_state_receipt", ""))),
				_receipt_suffix(String(_root_fixture["campaign1"].get("state_receipt", ""))),
			], card.position + Vector2(14.0, 43.0), 8, C_TEXT
		)
		_text(
			"RP8  %s / UNCHANGED" % _receipt_suffix(String(
				_evidence.get("accepted_covenant_state_receipt", "")
			)), card.position + Vector2(178.0, 43.0), 8, C_MUTED
		)
		_text(
			"ORIGINAL EVIDENCE SNAPSHOT RETAINED / NO REPORTS APPLIED",
			card.position + Vector2(14.0, 66.0), 8, C_MUTED
		)
		_text(
			"EPISTEMIC SUPPORT BAND / NOT TRUTH OR PROBABILITY",
			card.position + Vector2(14.0, 88.0), 8, C_TEXT
		)
		_text(
			"STALE CLOSE / BELIEF OWNER ONLY / REFUND 0",
			card.position + Vector2(14.0, 105.0), 8, C_DANGER
		)
		return
	_text("ACCEPTED EVIDENCE / READ ONLY", card.position + Vector2(14.0, 20.0), 8, C_BLUE)
	_text(
		"RP3 ATLAS     %s" % _receipt_suffix(String(
			_evidence.get("accepted_atlas_state_receipt", "")
		)), card.position + Vector2(14.0, 42.0), 8, C_MUTED
	)
	_text(
		"RP6 NETWORK   %s" % _receipt_suffix(String(
			_evidence.get("accepted_network_state_receipt", "")
		)), card.position + Vector2(178.0, 42.0), 8, C_MUTED
	)
	_text(
		"RP7 CAMPAIGN  %s" % _receipt_suffix(String(
			_evidence.get("accepted_campaign_state_receipt", "")
		)), card.position + Vector2(14.0, 63.0), 8, C_MUTED
	)
	_text(
		"RP8 COVENANT  %s" % _receipt_suffix(String(
			_evidence.get("accepted_covenant_state_receipt", "")
		)), card.position + Vector2(178.0, 63.0), 8, C_MUTED
	)
	_text(
		"EPISTEMIC SUPPORT BAND / NOT TRUTH OR PROBABILITY",
		card.position + Vector2(14.0, 88.0), 8, C_TEXT
	)
	_text(
		"OBSERVATION PURE / NO WORLD DELTA",
		card.position + Vector2(14.0, 105.0), 8, C_TEAL
	)


func _card(card_rect: Rect2, accent: Color) -> void:
	draw_rect(
		Rect2(card_rect.position + Vector2(3.0, 4.0), card_rect.size),
		Color(0.0, 0.0, 0.0, 0.22)
	)
	draw_rect(card_rect, C_CARD)
	draw_rect(card_rect, accent, false, 1.0)
	draw_rect(Rect2(card_rect.position, Vector2(5.0, card_rect.size.y)), accent)


func _draw_footer() -> void:
	draw_rect(Rect2(0.0, 704.0, 1280.0, 64.0), C_HEADER)
	_pair_rects.clear()
	for index in range(3):
		var rect := Rect2(24.0 + float(index) * 170.0, 719.0, 162.0, 33.0)
		_pair_rects.append(rect)
		var focused := index == _selected_pair and _fixture != FIXTURE_PRIORS
		draw_rect(rect, C_CARD_HI if focused else C_CARD)
		draw_rect(rect, C_TEAL if focused else C_EDGE, false, 1.0)
		_text(
			"%d  %s" % [index + 1, String(PAIR_LABELS[index])],
			rect.position + Vector2(7.0, 21.0), 8,
			C_TEAL if focused else C_MUTED, rect.size.x - 14.0,
			HORIZONTAL_ALIGNMENT_CENTER
		)
	_stage_rect = Rect2(552.0, 719.0, 190.0, 33.0)
	_variant_rect = Rect2(750.0, 719.0, 190.0, 33.0)
	_reset_rect = Rect2(948.0, 719.0, 92.0, 33.0)
	var variant_copy := "V  REPORTS / LOCKED" if _fixture == FIXTURE_STALE \
		else "V  REPORTS / %s" % _signal_set.to_upper()
	var controls := [
		[_stage_rect, "ENTER  PRIOR → COMMIT → END"],
		[_variant_rect, variant_copy],
		[_reset_rect, "R  RESET"],
	]
	for control in controls:
		var rect: Rect2 = control[0] as Rect2
		draw_rect(rect, C_CARD)
		draw_rect(rect, C_EDGE, false, 1.0)
		_text(
			String(control[1]), rect.position + Vector2(6.0, 21.0), 8, C_MUTED,
			rect.size.x - 12.0, HORIZONTAL_ALIGNMENT_CENTER
		)
	_text(
		"A–F FIXTURES / TAB NEXT", Vector2(1052.0, 741.0), 8, C_GOLD,
		204.0, HORIZONTAL_ALIGNMENT_RIGHT
	)


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
			_set_pair(int(key_event.keycode) - int(KEY_1))
		KEY_BRACKETLEFT:
			_set_fixture(posmod(_fixture - 1, 6))
		KEY_BRACKETRIGHT, KEY_TAB:
			_set_fixture((_fixture + 1) % 6)
		KEY_ENTER, KEY_SPACE:
			_advance_stage()
		KEY_V:
			if _fixture != FIXTURE_STALE:
				_signal_set = "inverse" if _signal_set == "canonical" else "canonical"
				queue_redraw()
		KEY_R:
			_signal_set = "canonical"
			_capacity_points = 2
			_view_stage = _default_stage_for_fixture(_fixture)
			_load_ok = _build_real_fixtures()
			queue_redraw()


func _set_fixture(value: int) -> void:
	_fixture = clampi(value, FIXTURE_PRIORS, FIXTURE_STALE)
	match _fixture:
		FIXTURE_DUTY_SPILLOVER:
			_selected_pair = 0
		FIXTURE_DUTY_FALLBACK, FIXTURE_STALE:
			_selected_pair = 1
		FIXTURE_SPILLOVER_FALLBACK:
			_selected_pair = 2
	_view_stage = _default_stage_for_fixture(_fixture)
	queue_redraw()


func _set_pair(value: int) -> void:
	_selected_pair = clampi(value, 0, 2)
	if _fixture in [FIXTURE_DUTY_SPILLOVER, FIXTURE_DUTY_FALLBACK,
			FIXTURE_SPILLOVER_FALLBACK]:
		_fixture = FIXTURE_DUTY_SPILLOVER + _selected_pair
	queue_redraw()


func _advance_stage() -> void:
	_view_stage = (_view_stage + 1) % 3
	queue_redraw()


func _handle_click(click_position: Vector2) -> void:
	for index in range(_fixture_rects.size()):
		if _fixture_rects[index].has_point(click_position):
			_set_fixture(index)
			return
	for index in range(_pair_rects.size()):
		if _pair_rects[index].has_point(click_position):
			_set_pair(index)
			return
	if _stage_rect.has_point(click_position):
		_advance_stage()
	elif _variant_rect.has_point(click_position):
		if _fixture != FIXTURE_STALE:
			_signal_set = "inverse" if _signal_set == "canonical" else "canonical"
			queue_redraw()
	elif _reset_rect.has_point(click_position):
		_signal_set = "canonical"
		_capacity_points = 2
		_view_stage = _default_stage_for_fixture(_fixture)
		_load_ok = _build_real_fixtures()
		queue_redraw()


func _save_shot() -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("PlanetReconPortfolioLab could not capture the viewport")
		get_tree().quit(1)
		return
	var save_error := image.save_png(_shot_path)
	if save_error != OK:
		push_error(
			"PlanetReconPortfolioLab could not save screenshot: %s" \
			% error_string(save_error)
		)
		get_tree().quit(1)
		return
	get_tree().quit()
