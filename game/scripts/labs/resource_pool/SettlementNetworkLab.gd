extends Node2D

const RegionRouteModel = preload("res://scripts/labs/resource_pool/RegionRouteModel.gd")
const SettlementNetworkModel = preload("res://scripts/labs/resource_pool/SettlementNetworkModel.gd")

const DESIGN := Vector2(1280.0, 768.0)
const HEADER_RECT := Rect2(0.0, 0.0, 1280.0, 72.0)
const MAP_PANEL := Rect2(24.0, 170.0, 824.0, 512.0)
const SIDE_PANEL := Rect2(864.0, 170.0, 392.0, 512.0)
const NETWORK_VIEW := Rect2(48.0, 210.0, 776.0, 443.0)

const OWNER_SCOPE := "caravan_ash_market"
const OWNER_CHECKPOINT_ONE := "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const OWNER_CHECKPOINT_TWO := "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const SUPPLY_BEFORE_TENTHS := 80

const FIXTURE_BEFORE := 0
const FIXTURE_OPTIONS := 1
const FIXTURE_AID := 2
const FIXTURE_TRADE := 3
const FIXTURE_FORTIFY := 4
const FIXTURE_INTEL := 5

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
const C_AID := Color("#78a999")
const C_TRADE := Color("#d2a85c")
const C_FORTIFY := Color("#84aebe")

const FIXTURE_TITLES := [
	"A  BEFORE", "B  OPTIONS", "C  AID", "D  TRADE", "E  FORTIFY", "F  INTEL",
]
const FIXTURE_SUBTITLES := [
	"accepted anchor", "three choices", "Saint Vey", "Dunlin", "Orra", "release at rev 2",
]
const CHOICE_KEYS := ["aid", "trade", "fortify"]
const CHOICE_LABELS := ["1  AID SAINT VEY", "2  TRADE DUNLIN", "3  FORTIFY ORRA"]
const CHOICE_SITE_KEYS := ["saint_vey_clinic", "dunlin_homestead", "orra_relay"]

const SITE_LABELS := {
	"ash_market": "ASH MARKET",
	"cinder_crossing": "CINDER CROSSING",
	"orra_relay": "ORRA RELAY",
	"redglass_quarry": "REDGLASS QUARRY",
	"saint_vey_clinic": "SAINT VEY CLINIC",
	"dunlin_homestead": "DUNLIN HOMESTEAD",
}

var _font: Font
var _atlas: Dictionary = {}
var _atlas_state: Dictionary = {}
var _catalog: Dictionary = {}
var _initial_state: Dictionary = {}
var _cargo_anchor: Dictionary = {}
var _board: Dictionary = {}
var _branches: Dictionary = {}
var _release_fixture: Dictionary = {}
var _site_points: Dictionary = {}
var _fixture := FIXTURE_BEFORE
var _selected_choice := 0
var _shot_path := ""
var _load_ok := false
var _mouse := Vector2(-1000.0, -1000.0)
var _fixture_rects: Array[Rect2] = []
var _choice_rects: Array[Rect2] = []


func _ready() -> void:
	_font = ThemeDB.fallback_font
	var requested_fixture := FIXTURE_BEFORE
	var requested_choice := 0
	var requested_step := ""
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		var argument := String(args[index])
		if argument == "--network-fixture" and index + 1 < args.size():
			index += 1
			requested_fixture = _fixture_from_argument(String(args[index]))
		elif argument.begins_with("--network-fixture="):
			requested_fixture = _fixture_from_argument(argument.trim_prefix("--network-fixture="))
		elif argument == "--network-choice" and index + 1 < args.size():
			index += 1
			requested_choice = _choice_from_argument(String(args[index]))
		elif argument.begins_with("--network-choice="):
			requested_choice = _choice_from_argument(argument.trim_prefix("--network-choice="))
		elif argument == "--network-step" and index + 1 < args.size():
			index += 1
			requested_step = String(args[index])
		elif argument.begins_with("--network-step="):
			requested_step = argument.trim_prefix("--network-step=")
		elif argument == "--lab-shot" and index + 1 < args.size():
			index += 1
			_shot_path = String(args[index])
		elif argument.begins_with("--lab-shot="):
			_shot_path = argument.trim_prefix("--lab-shot=")
		index += 1
	_selected_choice = clampi(requested_choice, 0, CHOICE_KEYS.size() - 1)
	_fixture = _fixture_for_step(requested_step, requested_fixture, _selected_choice)
	_sync_choice_to_fixture()
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
		"a", "1", "before", "anchor":
			return FIXTURE_BEFORE
		"b", "2", "options", "board":
			return FIXTURE_OPTIONS
		"c", "3", "aid", "saint_vey", "saint-vey":
			return FIXTURE_AID
		"d", "4", "trade", "dunlin":
			return FIXTURE_TRADE
		"e", "5", "fortify", "orra":
			return FIXTURE_FORTIFY
		"f", "6", "intel", "release":
			return FIXTURE_INTEL
	return FIXTURE_BEFORE


func _choice_from_argument(value: String) -> int:
	match value.strip_edges().to_lower():
		"1", "aid", "saint_vey", "saint-vey", "clinic":
			return 0
		"2", "trade", "dunlin", "farm":
			return 1
		"3", "fortify", "orra", "relay":
			return 2
	return 0


func _fixture_for_step(step_value: String, fallback: int, choice_index: int) -> int:
	match step_value.strip_edges().to_lower():
		"before", "anchor":
			return FIXTURE_BEFORE
		"options", "board", "choice":
			return FIXTURE_OPTIONS
		"arrival", "settlement", "settled", "result":
			return FIXTURE_AID + clampi(choice_index, 0, 2)
		"intel", "release", "available":
			return FIXTURE_INTEL
	return fallback


func _sync_choice_to_fixture() -> void:
	if _fixture in [FIXTURE_AID, FIXTURE_TRADE, FIXTURE_FORTIFY]:
		_selected_choice = _fixture - FIXTURE_AID
	elif _fixture == FIXTURE_INTEL:
		_selected_choice = 0


func _build_real_fixtures() -> bool:
	_atlas = RegionRouteModel.make_atlas(RegionRouteModel.DEFAULT_ROOT_SEED)
	_atlas_state = RegionRouteModel.make_initial_atlas_state(_atlas)
	_catalog = SettlementNetworkModel.make_catalog(_atlas)
	_initial_state = SettlementNetworkModel.make_initial_state(_catalog)
	_cargo_anchor = SettlementNetworkModel.make_cargo_anchor(
		OWNER_SCOPE, OWNER_CHECKPOINT_ONE, _parts_cargo(), SUPPLY_BEFORE_TENTHS, []
	)
	_board = SettlementNetworkModel.make_offer_board(
		_catalog, _initial_state, String(_initial_state.get("state_receipt", "")),
		_cargo_anchor, OWNER_SCOPE, OWNER_CHECKPOINT_ONE
	)
	if _atlas.is_empty() or _atlas_state.is_empty() or _catalog.is_empty() \
			or _initial_state.is_empty() or _cargo_anchor.is_empty() or _board.is_empty():
		push_error("SettlementNetworkLab could not build catalog, state, anchor, and board")
		return false
	if (_board.get("options", []) as Array).size() != 3:
		push_error("SettlementNetworkLab expected exactly three parts-funded options")
		return false
	_branches.clear()
	for choice_index in range(CHOICE_KEYS.size()):
		var key := String(CHOICE_KEYS[choice_index])
		var site_key := String(CHOICE_SITE_KEYS[choice_index])
		var branch := _build_branch(
			_initial_state, _cargo_anchor, OWNER_CHECKPOINT_ONE, _board,
			key, site_key, "network_lab_%s" % key
		)
		if branch.is_empty():
			push_error("SettlementNetworkLab could not build real %s branch" % key)
			return false
		_branches[key] = branch
	if not _build_release_fixture():
		return false
	_build_site_points()
	return _validate_real_fixtures()


func _build_branch(before_state: Dictionary, anchor: Dictionary,
		owner_checkpoint: String, board: Dictionary, action: String,
		site_key: String, route_key: String) -> Dictionary:
	var option := _option_for_site(board, site_key, action)
	if option.is_empty():
		return {}
	var choice: Dictionary = SettlementNetworkModel.make_choice(
		board, String(option.get("offer_id", ""))
	)
	var arrival_bundle := _build_arrival_bundle(
		String(option.get("node_id", "")), route_key
	)
	if choice.is_empty() or arrival_bundle.is_empty():
		return {}
	var plan: Dictionary = arrival_bundle.get("plan", {}) as Dictionary
	var journey: Dictionary = arrival_bundle.get("journey", {}) as Dictionary
	var route_receipt: Dictionary = arrival_bundle.get("route_receipt", {}) as Dictionary
	var arrival: Dictionary = arrival_bundle.get("arrival", {}) as Dictionary
	var transition: Dictionary = SettlementNetworkModel.propose_settlement(
		_catalog, before_state, String(before_state.get("state_receipt", "")),
		anchor, OWNER_SCOPE, owner_checkpoint, board, choice,
		_atlas, _atlas_state, plan, journey, route_receipt,
		String(journey.get("state_receipt", "")), arrival
	)
	var after_state: Dictionary = transition.get("after_state", {}) as Dictionary
	var intel: Dictionary = SettlementNetworkModel.project_intel(
		_catalog, after_state, String(after_state.get("state_receipt", ""))
	)
	if transition.is_empty() or after_state.is_empty() or intel.is_empty():
		return {}
	return {
		"key": action,
		"site_key": site_key,
		"option": option,
		"choice": choice,
		"plan": plan,
		"journey": journey,
		"route_receipt": route_receipt,
		"arrival": arrival,
		"transition": transition,
		"state": after_state,
		"intel": intel,
	}


func _build_arrival_bundle(node_id: String, route_key: String) -> Dictionary:
	var node := _catalog_node_for_id(node_id)
	if node.is_empty():
		return {}
	var tile_id := String(node.get("tile_id", ""))
	var plan: Dictionary = RegionRouteModel.make_route_plan(
		_atlas, _atlas_state, tile_id, tile_id, "autumn", "safe", [], "", route_key
	)
	var journey: Dictionary = RegionRouteModel.begin_journey(
		_atlas, _atlas_state, plan, route_key + "_slot", 8500, 92000
	)
	var route_receipt: Dictionary = RegionRouteModel.route_receipt(
		_atlas, _atlas_state, plan, journey
	)
	var arrival: Dictionary = SettlementNetworkModel.make_arrival_evidence(
		_catalog, node_id, _atlas, _atlas_state, plan, journey, route_receipt,
		String(journey.get("state_receipt", ""))
	)
	if plan.is_empty() or journey.is_empty() or route_receipt.is_empty() or arrival.is_empty():
		return {}
	return {
		"plan": plan,
		"journey": journey,
		"route_receipt": route_receipt,
		"arrival": arrival,
	}


func _build_release_fixture() -> bool:
	var aid_branch: Dictionary = _branches.get("aid", {}) as Dictionary
	var after_aid: Dictionary = aid_branch.get("state", {}) as Dictionary
	var second_anchor: Dictionary = SettlementNetworkModel.make_cargo_anchor(
		OWNER_SCOPE, OWNER_CHECKPOINT_TWO, _parts_cargo(), SUPPLY_BEFORE_TENTHS, []
	)
	var second_board: Dictionary = SettlementNetworkModel.make_offer_board(
		_catalog, after_aid, String(after_aid.get("state_receipt", "")),
		second_anchor, OWNER_SCOPE, OWNER_CHECKPOINT_TWO
	)
	var second_branch := _build_branch(
		after_aid, second_anchor, OWNER_CHECKPOINT_TWO, second_board,
		"trade", "dunlin_homestead", "network_lab_release_trade"
	)
	if after_aid.is_empty() or second_anchor.is_empty() or second_board.is_empty() \
			or second_branch.is_empty():
		push_error("SettlementNetworkLab could not advance the real delayed-intel fixture")
		return false
	var released_state: Dictionary = second_branch.get("state", {}) as Dictionary
	var released_intel: Dictionary = SettlementNetworkModel.project_intel(
		_catalog, released_state, String(released_state.get("state_receipt", ""))
	)
	if released_intel.is_empty() or (released_intel.get("available", []) as Array).size() != 1:
		push_error("SettlementNetworkLab delayed Ash intel did not release at revision two")
		return false
	_release_fixture = {
		"first": aid_branch,
		"second_anchor": second_anchor,
		"second_board": second_board,
		"second": second_branch,
		"state": released_state,
		"intel": released_intel,
	}
	return true


func _validate_real_fixtures() -> bool:
	if not SettlementNetworkModel.validate_catalog(_atlas, _catalog).is_empty() \
			or not SettlementNetworkModel.validate_state(_catalog, _initial_state).is_empty() \
			or not SettlementNetworkModel.validate_cargo_anchor(
				_cargo_anchor, OWNER_SCOPE, OWNER_CHECKPOINT_ONE
			).is_empty() \
			or not SettlementNetworkModel.validate_offer_board(
				_catalog, _initial_state, String(_initial_state.get("state_receipt", "")),
				_cargo_anchor, OWNER_SCOPE, OWNER_CHECKPOINT_ONE, _board
			).is_empty():
		push_error("SettlementNetworkLab base fixture failed exact validation")
		return false
	for key in CHOICE_KEYS:
		var branch: Dictionary = _branches.get(String(key), {}) as Dictionary
		var plan: Dictionary = branch.get("plan", {}) as Dictionary
		var journey: Dictionary = branch.get("journey", {}) as Dictionary
		var route_receipt: Dictionary = branch.get("route_receipt", {}) as Dictionary
		var arrival: Dictionary = branch.get("arrival", {}) as Dictionary
		if not SettlementNetworkModel.validate_choice(
			_board, branch.get("choice", {})
		).is_empty() or not SettlementNetworkModel.validate_arrival_evidence(
			_catalog, String((branch.get("option", {}) as Dictionary).get("node_id", "")),
			_atlas, _atlas_state, plan, journey, route_receipt,
			String(journey.get("state_receipt", "")), arrival
		).is_empty() or not SettlementNetworkModel.validate_settlement(
			_catalog, _initial_state, String(_initial_state.get("state_receipt", "")),
			_cargo_anchor, OWNER_SCOPE, OWNER_CHECKPOINT_ONE, _board,
			branch.get("choice", {}), _atlas, _atlas_state, plan, journey,
			route_receipt, String(journey.get("state_receipt", "")), arrival,
			branch.get("transition", {})
		).is_empty():
			push_error("SettlementNetworkLab %s fixture failed exact validation" % String(key))
			return false
	return _validate_release_fixture()


func _validate_release_fixture() -> bool:
	var aid_branch: Dictionary = _release_fixture.get("first", {}) as Dictionary
	var before_state: Dictionary = aid_branch.get("state", {}) as Dictionary
	var anchor: Dictionary = _release_fixture.get("second_anchor", {}) as Dictionary
	var board: Dictionary = _release_fixture.get("second_board", {}) as Dictionary
	var branch: Dictionary = _release_fixture.get("second", {}) as Dictionary
	var plan: Dictionary = branch.get("plan", {}) as Dictionary
	var journey: Dictionary = branch.get("journey", {}) as Dictionary
	var route_receipt: Dictionary = branch.get("route_receipt", {}) as Dictionary
	var arrival: Dictionary = branch.get("arrival", {}) as Dictionary
	if not SettlementNetworkModel.validate_cargo_anchor(
		anchor, OWNER_SCOPE, OWNER_CHECKPOINT_TWO
	).is_empty() or not SettlementNetworkModel.validate_offer_board(
		_catalog, before_state, String(before_state.get("state_receipt", "")),
		anchor, OWNER_SCOPE, OWNER_CHECKPOINT_TWO, board
	).is_empty() or not SettlementNetworkModel.validate_choice(
		board, branch.get("choice", {})
	).is_empty() or not SettlementNetworkModel.validate_arrival_evidence(
		_catalog, String((branch.get("option", {}) as Dictionary).get("node_id", "")),
		_atlas, _atlas_state, plan, journey, route_receipt,
		String(journey.get("state_receipt", "")), arrival
	).is_empty() or not SettlementNetworkModel.validate_settlement(
		_catalog, before_state, String(before_state.get("state_receipt", "")),
		anchor, OWNER_SCOPE, OWNER_CHECKPOINT_TWO, board,
		branch.get("choice", {}), _atlas, _atlas_state, plan, journey,
		route_receipt, String(journey.get("state_receipt", "")), arrival,
		branch.get("transition", {})
	).is_empty():
		push_error("SettlementNetworkLab release fixture failed exact validation")
		return false
	return true


func _parts_cargo() -> Dictionary:
	return {"food": 0, "meds": 0, "parts": 2, "scrap": 0}


func _option_for_site(board: Dictionary, site_key: String, action: String = "") -> Dictionary:
	var node := _catalog_node_for_site(site_key)
	if node.is_empty():
		return {}
	for raw_option in board.get("options", []) as Array:
		var option: Dictionary = raw_option as Dictionary
		if String(option.get("node_id", "")) == String(node.get("node_id", "")) \
				and (action == "" or String(option.get("action", "")) == action):
			return option
	return {}


func _catalog_node_for_site(site_key: String) -> Dictionary:
	for raw_node in _catalog.get("nodes", []) as Array:
		var node: Dictionary = raw_node as Dictionary
		if String(node.get("site_key", "")) == site_key:
			return node
	return {}


func _catalog_node_for_id(node_id: String) -> Dictionary:
	for raw_node in _catalog.get("nodes", []) as Array:
		var node: Dictionary = raw_node as Dictionary
		if String(node.get("node_id", "")) == node_id:
			return node
	return {}


func _state_node_for_site(state: Dictionary, site_key: String) -> Dictionary:
	var catalog_node := _catalog_node_for_site(site_key)
	var node_id := String(catalog_node.get("node_id", ""))
	for raw_node in state.get("nodes", []) as Array:
		var state_node: Dictionary = raw_node as Dictionary
		if String(state_node.get("node_id", "")) == node_id:
			return state_node
	return {}


func _catalog_offer_for_site(site_key: String) -> Dictionary:
	var node := _catalog_node_for_site(site_key)
	var node_id := String(node.get("node_id", ""))
	for raw_offer in _catalog.get("offers", []) as Array:
		var offer: Dictionary = raw_offer as Dictionary
		if String(offer.get("node_id", "")) == node_id:
			return offer
	return {}


func _build_site_points() -> void:
	_site_points.clear()
	var raw_points: Dictionary = {}
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for raw_tile in _atlas.get("tiles", []) as Array:
		var tile: Dictionary = raw_tile as Dictionary
		var site_key := String(tile.get("site_key", ""))
		if site_key not in SITE_LABELS:
			continue
		var q := float(int(tile.get("q", 0)))
		var r := float(int(tile.get("r", 0)))
		var point := Vector2(q + r * 0.5, r * 0.86)
		raw_points[site_key] = point
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	var inner := NETWORK_VIEW.grow(-54.0)
	for site_key_value in raw_points:
		var site_key := String(site_key_value)
		var raw: Vector2 = raw_points[site_key] as Vector2
		var nx := 0.5 if is_equal_approx(maximum.x, minimum.x) \
			else (raw.x - minimum.x) / (maximum.x - minimum.x)
		var ny := 0.5 if is_equal_approx(maximum.y, minimum.y) \
			else (raw.y - minimum.y) / (maximum.y - minimum.y)
		_site_points[site_key] = Vector2(
			lerpf(inner.position.x, inner.end.x, nx),
			lerpf(inner.position.y, inner.end.y, ny)
		)


func _display_state() -> Dictionary:
	if _fixture in [FIXTURE_AID, FIXTURE_TRADE, FIXTURE_FORTIFY]:
		return (_branches.get(String(CHOICE_KEYS[_fixture - FIXTURE_AID]), {}) as Dictionary).get(
			"state", {}
		) as Dictionary
	if _fixture == FIXTURE_INTEL:
		return _release_fixture.get("state", {}) as Dictionary
	return _initial_state


func _display_branch() -> Dictionary:
	if _fixture in [FIXTURE_AID, FIXTURE_TRADE, FIXTURE_FORTIFY]:
		return _branches.get(String(CHOICE_KEYS[_fixture - FIXTURE_AID]), {}) as Dictionary
	return _branches.get(String(CHOICE_KEYS[_selected_choice]), {}) as Dictionary


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, DESIGN), C_BG)
	_draw_noise_field()
	_draw_header()
	_draw_fixture_rail()
	_panel(MAP_PANEL, "SETTLEMENT NETWORK / FOUR SAFE STOPS", "SOLID = ELIGIBLE   DASH = INTEL / REJECT")
	_panel(SIDE_PANEL, "ANCHOR / CAUSAL RESULT")
	if _load_ok:
		_draw_network_map()
		_draw_side_panel()
	else:
		_text("SETTLEMENT NETWORK CONTRACT FAILED", Vector2(70.0, 230.0), 20, C_DANGER)
	_draw_footer()


func _draw_noise_field() -> void:
	for index in range(190):
		var x := float((index * 97 + 31) % 1280)
		var y := float((index * 53 + 17) % 768)
		draw_rect(Rect2(x, y, 2.0, 2.0), Color(0.72, 0.67, 0.48, 0.035))


func _draw_header() -> void:
	draw_rect(HEADER_RECT, C_HEADER)
	draw_line(Vector2(0.0, 71.0), Vector2(1280.0, 71.0), C_EDGE, 1.0)
	_text("SETTLEMENT NETWORK LAB // RP-0006", Vector2(24.0, 31.0), 22, C_TEXT)
	_text("Spend one accepted cargo anchor on aid, trade, or protection.", Vector2(24.0, 55.0), 13, C_MUTED)
	_text("CARAVAN / ASH MARKET", Vector2(930.0, 31.0), 13, C_GOLD, 326.0, HORIZONTAL_ALIGNMENT_RIGHT)
	var header_state := "PARTS 2  /  SUPPLY 80  /  OWNER ACCEPTED"
	if _fixture == FIXTURE_INTEL:
		header_state = "REV 2  /  TWO DISTINCT OWNER CHECKPOINTS"
	_text(header_state, Vector2(850.0, 54.0), 10, C_MUTED, 406.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_fixture_rail() -> void:
	for index in range(FIXTURE_TITLES.size()):
		var card_rect := Rect2(24.0 + float(index) * 204.0, 88.0, 196.0, 66.0)
		var selected := index == _fixture
		var accent := _fixture_color(index)
		draw_rect(Rect2(card_rect.position + Vector2(3.0, 4.0), card_rect.size), Color(0.0, 0.0, 0.0, 0.25))
		draw_rect(card_rect, C_CARD_HI if selected else C_CARD)
		draw_rect(card_rect, accent if selected else C_EDGE, false, 2.0 if selected else 1.0)
		draw_rect(Rect2(card_rect.position, Vector2(5.0, card_rect.size.y)), accent)
		_text(String(FIXTURE_TITLES[index]), card_rect.position + Vector2(14.0, 27.0), 12,
			C_TEXT if selected else C_MUTED, 168.0)
		_text(String(FIXTURE_SUBTITLES[index]).to_upper(), card_rect.position + Vector2(14.0, 48.0),
			8, accent if selected else C_MUTED, 168.0)


func _panel(panel_rect: Rect2, title: String, legend: String = "") -> void:
	draw_rect(Rect2(panel_rect.position + Vector2(4.0, 5.0), panel_rect.size), Color(0.0, 0.0, 0.0, 0.32))
	draw_rect(panel_rect, C_PANEL)
	draw_rect(panel_rect, C_EDGE, false, 2.0)
	draw_rect(Rect2(panel_rect.position, Vector2(panel_rect.size.x, 31.0)), C_PANEL_2)
	draw_line(panel_rect.position + Vector2(0.0, 31.0), panel_rect.position + Vector2(panel_rect.size.x, 31.0), C_EDGE, 1.0)
	_text(title, panel_rect.position + Vector2(12.0, 22.0), 13, C_GOLD)
	if legend != "":
		_text(legend, panel_rect.position + Vector2(390.0, 21.0), 8, C_MUTED,
			panel_rect.size.x - 402.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_network_map() -> void:
	draw_rect(NETWORK_VIEW, Color("#171914"))
	_draw_network_grid()
	_draw_option_spokes()
	if _fixture == FIXTURE_INTEL:
		_draw_released_intel()
	_draw_context_site("ash_market")
	_draw_context_site("redglass_quarry")
	for site_key in ["orra_relay", "saint_vey_clinic", "dunlin_homestead", "cinder_crossing"]:
		_draw_settlement_node(String(site_key))
	_draw_cargo_anchor()


func _draw_network_grid() -> void:
	for row in range(7):
		var y := NETWORK_VIEW.position.y + 28.0 + float(row) * 63.0
		var offset := 28.0 if row % 2 != 0 else 0.0
		for column in range(13):
			var center := Vector2(NETWORK_VIEW.position.x + 29.0 + offset + float(column) * 57.0, y)
			if NETWORK_VIEW.grow(-12.0).has_point(center):
				var points := _hex_points(center, 18.0)
				draw_polyline(_closed(points), Color(0.36, 0.40, 0.31, 0.12), 1.0, true)


func _draw_option_spokes() -> void:
	var anchor := _site_point("ash_market")
	for index in range(CHOICE_KEYS.size()):
		var key := String(CHOICE_KEYS[index])
		var target := _site_point(String(CHOICE_SITE_KEYS[index]))
		var color := _choice_color(index)
		var selected := _choice_is_selected(index)
		var visible := _fixture != FIXTURE_BEFORE
		if not visible:
			color = Color(C_EDGE, 0.28)
		elif not selected and _fixture not in [FIXTURE_OPTIONS]:
			color = Color(color, 0.20)
		draw_line(anchor, target, color, 4.0 if selected else 2.0, true)
		if visible:
			var midpoint := anchor.lerp(target, 0.52)
			_draw_spoke_label(midpoint, key.to_upper(), color)
	var cinder_target := _site_point("cinder_crossing")
	_draw_dashed_segment(anchor, cinder_target, Color(C_DANGER, 0.46), 2.0, 8.0, 6.0)


func _draw_spoke_label(center: Vector2, copy: String, color: Color) -> void:
	var width := maxf(58.0, float(copy.length()) * 6.2 + 14.0)
	var label_rect := Rect2(center - Vector2(width * 0.5, 11.0), Vector2(width, 22.0))
	draw_rect(label_rect, Color(0.055, 0.065, 0.052, 0.92))
	draw_rect(label_rect, color, false, 1.0)
	_text(copy, label_rect.position + Vector2(7.0, 15.0), 8, color,
		label_rect.size.x - 14.0, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_context_site(site_key: String) -> void:
	var center := _site_point(site_key)
	var color := C_GOLD if site_key == "ash_market" else C_DANGER
	draw_circle(center, 13.0, Color(0.04, 0.05, 0.04, 0.92))
	draw_circle(center, 13.0, color, false, 2.0)
	var diamond := PackedVector2Array([
		center + Vector2(0.0, -7.0), center + Vector2(7.0, 0.0),
		center + Vector2(0.0, 7.0), center + Vector2(-7.0, 0.0), center + Vector2(0.0, -7.0),
	])
	draw_polyline(diamond, color, 1.0)
	var label_pos := center + Vector2(25.0, -33.0) if site_key == "ash_market" \
		else center + Vector2(-156.0, -23.0)
	_draw_site_label(label_pos, String(SITE_LABELS[site_key]) + " / INTEL SUBJECT", color, 174.0)


func _draw_settlement_node(site_key: String) -> void:
	var center := _site_point(site_key)
	var state := _display_state()
	var node := _state_node_for_site(state, site_key)
	var eligible := not _option_for_site(_board, site_key).is_empty()
	var choice_index := CHOICE_SITE_KEYS.find(site_key)
	var selected := choice_index >= 0 and _choice_is_selected(choice_index)
	var color := _choice_color(choice_index) if choice_index >= 0 else C_DANGER
	if not eligible:
		color = C_DANGER
	draw_circle(center, 20.0, Color(0.055, 0.065, 0.052, 0.96))
	draw_circle(center, 20.0, color, false, 4.0 if selected else 2.0)
	if not eligible:
		draw_line(center + Vector2(-8.0, -8.0), center + Vector2(8.0, 8.0), C_DANGER, 2.0)
		draw_line(center + Vector2(8.0, -8.0), center + Vector2(-8.0, 8.0), C_DANGER, 2.0)
	else:
		_draw_node_icon(center, site_key, color)
	var label_position := _node_label_position(site_key, center)
	var label_width := 176.0
	var label_rect := Rect2(label_position, Vector2(label_width, 72.0))
	_draw_node_leader(site_key, center, label_rect, color)
	draw_rect(label_rect, Color(0.055, 0.065, 0.052, 0.94))
	draw_rect(label_rect, color if selected or not eligible else C_EDGE, false, 1.0)
	_text(String(SITE_LABELS[site_key]), label_rect.position + Vector2(10.0, 19.0), 10,
		C_TEXT if eligible else C_MUTED, label_width - 20.0)
	var status := "ELIGIBLE" if eligible else "INELIGIBLE / FOOD 2"
	_text(status, label_rect.position + Vector2(10.0, 37.0), 8, color, label_width - 20.0)
	_draw_track_triplet(label_rect.position + Vector2(10.0, 57.0), node)


func _draw_node_icon(center: Vector2, site_key: String, color: Color) -> void:
	if site_key == "saint_vey_clinic":
		draw_rect(Rect2(center - Vector2(2.0, 9.0), Vector2(4.0, 18.0)), color)
		draw_rect(Rect2(center - Vector2(9.0, 2.0), Vector2(18.0, 4.0)), color)
	elif site_key == "dunlin_homestead":
		draw_rect(Rect2(center - Vector2(9.0, 1.0), Vector2(18.0, 9.0)), color)
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(-10.0, -1.0), center + Vector2(0.0, -10.0), center + Vector2(10.0, -1.0),
		]), color.darkened(0.2))
	elif site_key == "orra_relay":
		draw_line(center + Vector2(0.0, 9.0), center + Vector2(0.0, -10.0), color, 2.0)
		draw_line(center + Vector2(-7.0, -3.0), center + Vector2(0.0, -10.0), color, 2.0)
		draw_line(center + Vector2(7.0, -3.0), center + Vector2(0.0, -10.0), color, 2.0)
	else:
		_draw_diamond(center, 8.0, color)


func _draw_track_triplet(origin: Vector2, node: Dictionary) -> void:
	var labels := ["N", "S", "R"]
	var fields := ["need_pressure", "security_pressure", "reciprocity"]
	for index in range(3):
		var x := origin.x + float(index) * 52.0
		_text(String(labels[index]), Vector2(x, origin.y), 8, C_MUTED)
		var value := int(node.get(String(fields[index]), 0))
		for tick in range(3):
			var tick_rect := Rect2(x + 13.0 + float(tick) * 9.0, origin.y - 7.0, 6.0, 6.0)
			draw_rect(tick_rect, C_TEAL if tick < value else Color("#30332b"))


func _draw_cargo_anchor() -> void:
	var center := _site_point("ash_market") + Vector2(0.0, 31.0)
	var anchor_rect := Rect2(center - Vector2(77.0, 20.0), Vector2(154.0, 40.0))
	draw_rect(Rect2(anchor_rect.position + Vector2(3.0, 4.0), anchor_rect.size), Color(0.0, 0.0, 0.0, 0.30))
	draw_rect(anchor_rect, C_CARD_HI)
	draw_rect(anchor_rect, C_GOLD, false, 2.0)
	draw_rect(Rect2(anchor_rect.position, Vector2(5.0, anchor_rect.size.y)), C_GOLD)
	_text("ACCEPTED CARGO", anchor_rect.position + Vector2(13.0, 16.0), 8, C_MUTED)
	_text("PARTS 2  /  SUPPLY 80", anchor_rect.position + Vector2(13.0, 33.0), 10, C_TEXT)


func _draw_released_intel() -> void:
	var from := _site_point("saint_vey_clinic")
	var to := _site_point("ash_market")
	_draw_dashed_segment(from, to, C_TEAL, 4.0, 11.0, 5.0)
	var trace_point := from.lerp(to, 0.47)
	var center := trace_point + Vector2(112.0, -40.0)
	var badge := Rect2(center - Vector2(88.0, 14.0), Vector2(176.0, 28.0))
	draw_line(trace_point, Vector2(badge.position.x, badge.get_center().y), Color(C_TEAL, 0.72), 1.0, true)
	draw_rect(badge, Color(0.04, 0.07, 0.06, 0.94))
	draw_rect(badge, C_TEAL, false, 2.0)
	_text("ASH INTEL / AVAILABLE", badge.position + Vector2(8.0, 19.0), 9, C_TEAL,
		badge.size.x - 16.0, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_side_panel() -> void:
	_draw_anchor_card()
	match _fixture:
		FIXTURE_BEFORE:
			_draw_before_card()
		FIXTURE_OPTIONS:
			_draw_options_card()
		FIXTURE_AID, FIXTURE_TRADE, FIXTURE_FORTIFY:
			_draw_outcome_card()
		FIXTURE_INTEL:
			_draw_intel_card()


func _draw_anchor_card() -> void:
	var card_rect := Rect2(880.0, 209.0, 360.0, 74.0)
	_card(card_rect, C_GOLD)
	_text("OWNER-ACCEPTED CARGO ANCHOR", Vector2(894.0, 232.0), 10, C_GOLD)
	_text("PARTS  2", Vector2(894.0, 259.0), 17, C_TEXT)
	_text("SUPPLY  80", Vector2(1035.0, 258.0), 10, C_MUTED, 189.0, HORIZONTAL_ALIGNMENT_RIGHT)
	_text("SCOPE LOCKED / CARAVAN_ASH_MARKET", Vector2(894.0, 274.0), 8, C_MUTED, 330.0)


func _draw_before_card() -> void:
	var main := Rect2(880.0, 295.0, 360.0, 224.0)
	_card(main, C_GOLD)
	_text("ONE SCARCE INPUT", Vector2(894.0, 319.0), 10, C_GOLD)
	_text("THREE DIFFERENT WAYS TO SPEND PARTS 2", Vector2(894.0, 350.0), 14, C_TEXT, 330.0)
	_wrapped("The anchor is accepted owner evidence. It is not remote settlement stock and it can settle once.",
		Vector2(894.0, 377.0), 330.0, 10, C_MUTED, 4)
	_draw_pressure_row(431.0, "SAINT VEY", _state_node_for_site(_initial_state, "saint_vey_clinic"), C_AID)
	_draw_pressure_row(457.0, "DUNLIN", _state_node_for_site(_initial_state, "dunlin_homestead"), C_TRADE)
	_draw_pressure_row(483.0, "ORRA", _state_node_for_site(_initial_state, "orra_relay"), C_FORTIFY)
	var decision := Rect2(880.0, 531.0, 360.0, 134.0)
	_card(decision, C_EDGE_HI)
	_text("PRODUCT DECISION", Vector2(894.0, 554.0), 10, C_MUTED)
	_text("WHERE DOES THIS PARTS CRATE MATTER?", Vector2(894.0, 584.0), 15, C_GOLD, 330.0)
	_wrapped("Open the board to compare need, supply, security, reciprocity, and delayed intel.",
		Vector2(894.0, 610.0), 330.0, 10, C_TEXT, 3)


func _draw_options_card() -> void:
	var main := Rect2(880.0, 295.0, 360.0, 286.0)
	_card(main, _choice_color(_selected_choice))
	_text("THREE OPTIONS / NO GLOBAL SCORE", Vector2(894.0, 319.0), 10, C_TEAL)
	for index in range(3):
		_draw_option_row(339.0 + float(index) * 64.0, index)
	var cinder_offer := _catalog_offer_for_site("cinder_crossing")
	var cost: Dictionary = cinder_offer.get("cost", {}) as Dictionary
	var cargo: Dictionary = _cargo_anchor.get("cargo_before", {}) as Dictionary
	var reject_rect := Rect2(894.0, 537.0, 330.0, 32.0)
	draw_rect(reject_rect, Color(C_DANGER, 0.08))
	draw_rect(reject_rect, C_DANGER, false, 1.0)
	_text("CINDER INELIGIBLE", reject_rect.position + Vector2(9.0, 20.0), 9, C_DANGER)
	_text("NEEDS %s %d / ANCHOR HAS %d" % [String(cost.get("good", "")).to_upper(),
		int(cost.get("quantity", 0)), int(cargo.get(String(cost.get("good", "")), 0))],
		reject_rect.position + Vector2(139.0, 20.0), 8, C_MUTED, 181.0, HORIZONTAL_ALIGNMENT_RIGHT)
	var decision := Rect2(880.0, 593.0, 360.0, 72.0)
	_card(decision, _choice_color(_selected_choice))
	_text("SELECTED / " + String(CHOICE_LABELS[_selected_choice]).substr(3), Vector2(894.0, 617.0),
		10, _choice_color(_selected_choice), 330.0)
	_text("ENTER / SPACE SETTLES THE STORED REAL CHAIN", Vector2(894.0, 646.0), 8, C_MUTED, 330.0)


func _draw_option_row(y: float, index: int) -> void:
	var key := String(CHOICE_KEYS[index])
	var branch: Dictionary = _branches.get(key, {}) as Dictionary
	var option: Dictionary = branch.get("option", {}) as Dictionary
	var selected := index == _selected_choice
	var color := _choice_color(index)
	var row := Rect2(894.0, y, 330.0, 55.0)
	draw_rect(row, C_CARD_HI if selected else Color("#151713"))
	draw_rect(row, color if selected else C_EDGE, false, 1.0)
	draw_rect(Rect2(row.position, Vector2(4.0, row.size.y)), color)
	_text(String(CHOICE_LABELS[index]), row.position + Vector2(11.0, 20.0), 10,
		C_TEXT if selected else C_MUTED, 205.0)
	_text("PARTS 2", row.position + Vector2(220.0, 20.0), 9, C_GOLD, 98.0, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(_option_consequence(option), row.position + Vector2(11.0, 42.0), 9, color, 307.0)


func _draw_outcome_card() -> void:
	var branch := _display_branch()
	var transition: Dictionary = branch.get("transition", {}) as Dictionary
	var owner_delta: Dictionary = transition.get("owner_delta", {}) as Dictionary
	var network_delta: Dictionary = transition.get("network_delta", {}) as Dictionary
	var before_node: Dictionary = network_delta.get("node_before", {}) as Dictionary
	var after_node: Dictionary = network_delta.get("node_after", {}) as Dictionary
	var color := _choice_color(_selected_choice)
	var main := Rect2(880.0, 295.0, 360.0, 286.0)
	_card(main, color)
	_text("CHOICE -> ARRIVAL -> SETTLEMENT", Vector2(894.0, 319.0), 10, color)
	_text(String(SITE_LABELS[String(branch.get("site_key", ""))]), Vector2(894.0, 350.0), 17, C_TEXT, 330.0)
	_text(String(branch.get("key", "")).to_upper() + " / ARRIVED EVIDENCE ACCEPTED", Vector2(894.0, 371.0), 9, C_MUTED, 330.0)
	_draw_delta_row(405.0, "PARTS", 2, int((owner_delta.get("cargo_after", {}) as Dictionary).get("parts", 0)), C_GOLD)
	_draw_delta_row(432.0, "SUPPLY", int(owner_delta.get("supply_before_tenths", 0)),
		int(owner_delta.get("supply_after_tenths", 0)), C_TRADE)
	_draw_delta_row(459.0, "NEED", int(before_node.get("need_pressure", 0)),
		int(after_node.get("need_pressure", 0)), C_AID)
	_draw_delta_row(486.0, "SECURITY", int(before_node.get("security_pressure", 0)),
		int(after_node.get("security_pressure", 0)), C_FORTIFY)
	_draw_delta_row(513.0, "RECIPROCITY", int(before_node.get("reciprocity", 0)),
		int(after_node.get("reciprocity", 0)), C_TEAL)
	var intel_record: Dictionary = network_delta.get("intel_record", {}) as Dictionary
	if intel_record.is_empty():
		_text("INTEL / NONE", Vector2(894.0, 554.0), 9, C_MUTED, 330.0)
	else:
		_text("INTEL PENDING / RELEASE REV %d" % int(intel_record.get("release_revision", 0)),
			Vector2(894.0, 554.0), 9, C_TEAL, 330.0)
	var decision := Rect2(880.0, 593.0, 360.0, 72.0)
	_card(decision, color)
	_text("WHY THIS CHOICE", Vector2(894.0, 617.0), 9, C_MUTED)
	_text(_outcome_decision_copy(String(branch.get("key", ""))), Vector2(894.0, 646.0),
		11, color, 330.0)


func _draw_intel_card() -> void:
	var intel: Dictionary = _release_fixture.get("intel", {}) as Dictionary
	var available: Array = intel.get("available", []) as Array
	var record: Dictionary = available[0] as Dictionary if not available.is_empty() else {}
	var second: Dictionary = _release_fixture.get("second", {}) as Dictionary
	var second_transition: Dictionary = second.get("transition", {}) as Dictionary
	var main := Rect2(880.0, 295.0, 360.0, 286.0)
	_card(main, C_TEAL)
	_text("DELAY IS A REAL NETWORK REVISION", Vector2(894.0, 319.0), 10, C_TEAL)
	_text("ASH INTEL AVAILABLE", Vector2(894.0, 351.0), 18, C_TEXT)
	_text("REV 1 / SAINT VEY AID", Vector2(894.0, 382.0), 10, C_AID)
	_text("MEDICAL WINDOW QUEUED -> RELEASE REV 2", Vector2(908.0, 404.0), 9, C_MUTED, 316.0)
	_text("REV 2 / DUNLIN TRADE", Vector2(894.0, 438.0), 10, C_TRADE)
	_text("FRESH OWNER CHECKPOINT / PARTS 2 / SUPPLY 80 -> 110", Vector2(908.0, 460.0), 9, C_MUTED, 316.0)
	var owner_delta: Dictionary = second_transition.get("owner_delta", {}) as Dictionary
	_text("NETWORK REV %d  /  SUPPLY %d" % [int((_release_fixture.get("state", {}) as Dictionary).get("revision", 0)),
		int(owner_delta.get("supply_after_tenths", 0))], Vector2(894.0, 497.0), 11, C_TEXT, 330.0)
	_text("PENDING %d  /  AVAILABLE %d" % [(intel.get("pending", []) as Array).size(), available.size()],
		Vector2(894.0, 523.0), 10, C_TEAL, 330.0)
	_text(_intel_topic_copy(String(record.get("topic", ""))), Vector2(894.0, 553.0), 9, C_TEAL, 330.0)
	var decision := Rect2(880.0, 593.0, 360.0, 72.0)
	_card(decision, C_TEAL)
	_text("PRODUCT PROOF", Vector2(894.0, 617.0), 9, C_MUTED)
	_text("OBSERVATION DID NOT RELEASE IT; REV 2 DID.", Vector2(894.0, 646.0), 10, C_TEAL, 330.0)


func _draw_pressure_row(y: float, label: String, node: Dictionary, color: Color) -> void:
	_text(label, Vector2(894.0, y), 9, color, 116.0)
	_text("NEED %d  /  SEC %d  /  RECIP %d" % [int(node.get("need_pressure", 0)),
		int(node.get("security_pressure", 0)), int(node.get("reciprocity", 0))],
		Vector2(1010.0, y), 9, C_TEXT, 214.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_delta_row(y: float, label: String, before: int, after: int, color: Color) -> void:
	_text(label, Vector2(894.0, y), 9, C_MUTED, 190.0)
	_text("%d  ->  %d" % [before, after], Vector2(1084.0, y), 11,
		color if before != after else C_MUTED, 140.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _option_consequence(option: Dictionary) -> String:
	var action := String(option.get("action", ""))
	var effect: Dictionary = option.get("effect", {}) as Dictionary
	var reward: Dictionary = option.get("owner_reward", {}) as Dictionary
	if action == "aid":
		return "NEED %d / RECIP +%d / ASH INTEL DELAYED" % [
			int(effect.get("need_delta", 0)), int(effect.get("reciprocity_delta", 0))]
	if action == "trade":
		return "SUPPLY +%d APPLIED / TRACKS UNCHANGED" % int(reward.get("applied_supply_gain_tenths", 0))
	return "SEC %d / RECIP +%d / REDGLASS INTEL DELAYED" % [
		int(effect.get("security_delta", 0)), int(effect.get("reciprocity_delta", 0))]


func _outcome_decision_copy(key: String) -> String:
	match key:
		"aid":
			return "RELIEVE NEED + BUILD RECIPROCITY"
		"trade":
			return "TURN PARTS INTO +30 SUPPLY"
		"fortify":
			return "LOWER SECURITY PRESSURE + EARN TRUST"
	return "NO RESULT"


func _intel_topic_copy(topic: String) -> String:
	return "TOPIC / " + topic.replace("_", " ").to_upper()


func _choice_is_selected(index: int) -> bool:
	if _fixture in [FIXTURE_AID, FIXTURE_TRADE, FIXTURE_FORTIFY]:
		return index == _fixture - FIXTURE_AID
	if _fixture == FIXTURE_INTEL:
		return index in [0, 1]
	return index == _selected_choice


func _node_label_position(site_key: String, center: Vector2) -> Vector2:
	match site_key:
		"orra_relay":
			return center + Vector2(-196.0, -34.0)
		"saint_vey_clinic":
			return center + Vector2(27.0, -112.0)
		"dunlin_homestead":
			return center + Vector2(25.0, -36.0)
		"cinder_crossing":
			return center + Vector2(-202.0, -112.0)
	return center + Vector2(24.0, -34.0)


func _draw_node_leader(site_key: String, center: Vector2, label_rect: Rect2,
		color: Color) -> void:
	if site_key == "cinder_crossing":
		var cinder_corner := Vector2(label_rect.end.x, label_rect.end.y - 10.0)
		draw_line(center + Vector2(-14.0, -14.0), cinder_corner, Color(color, 0.62), 1.0, true)
	elif site_key == "saint_vey_clinic":
		var clinic_corner := Vector2(label_rect.position.x, label_rect.end.y - 10.0)
		draw_line(center + Vector2(14.0, -14.0), clinic_corner, Color(color, 0.62), 1.0, true)


func _site_point(site_key: String) -> Vector2:
	return _site_points.get(site_key, Vector2(-1000.0, -1000.0)) as Vector2


func _draw_site_label(position: Vector2, copy: String, color: Color, width: float) -> void:
	var label_rect := Rect2(position, Vector2(width, 22.0))
	draw_rect(label_rect, Color(0.055, 0.065, 0.052, 0.90))
	draw_rect(label_rect, color, false, 1.0)
	_text(copy, label_rect.position + Vector2(8.0, 15.0), 8, color, width - 16.0)


func _hex_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(6):
		var angle := deg_to_rad(30.0 + float(index) * 60.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	if not result.is_empty():
		result.append(result[0])
	return result


func _draw_diamond(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0.0, -radius), center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius), center + Vector2(-radius, 0.0), center + Vector2(0.0, -radius),
	])
	draw_polyline(points, color, 2.0, true)


func _draw_dashed_segment(from_point: Vector2, to_point: Vector2, color: Color,
		width: float, dash_length: float, gap_length: float) -> void:
	var delta := to_point - from_point
	var length := delta.length()
	if length <= 0.001:
		return
	var direction := delta / length
	var cursor := 0.0
	while cursor < length:
		var end_distance := minf(cursor + dash_length, length)
		draw_line(from_point + direction * cursor, from_point + direction * end_distance,
			color, width, true)
		cursor += dash_length + gap_length


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
		_text(String(FIXTURE_TITLES[index]), tab_rect.position + Vector2(6.0, 22.0), 8,
			C_TEXT if selected else C_MUTED, tab_rect.size.x - 12.0, HORIZONTAL_ALIGNMENT_CENTER)
	_choice_rects.clear()
	for index in range(CHOICE_LABELS.size()):
		var choice_rect := Rect2(714.0 + float(index) * 176.0, 719.0, 170.0, 33.0)
		_choice_rects.append(choice_rect)
		var selected := index == _selected_choice
		var color := _choice_color(index)
		draw_rect(choice_rect, color.darkened(0.62) if selected else C_CARD_HI)
		draw_rect(choice_rect, color if selected else C_EDGE, false, 1.0)
		_text(String(CHOICE_LABELS[index]), choice_rect.position + Vector2(7.0, 22.0), 8,
			C_TEXT if selected else C_MUTED, choice_rect.size.x - 14.0, HORIZONTAL_ALIGNMENT_CENTER)


func _card(card_rect: Rect2, accent: Color) -> void:
	draw_rect(Rect2(card_rect.position + Vector2(3.0, 4.0), card_rect.size), Color(0.0, 0.0, 0.0, 0.28))
	draw_rect(card_rect, C_CARD)
	draw_rect(card_rect, C_EDGE, false, 1.0)
	draw_rect(Rect2(card_rect.position, Vector2(5.0, card_rect.size.y)), accent)


func _fixture_color(index: int) -> Color:
	match index:
		FIXTURE_AID:
			return C_AID
		FIXTURE_TRADE:
			return C_TRADE
		FIXTURE_FORTIFY:
			return C_FORTIFY
		FIXTURE_INTEL:
			return C_TEAL
	return C_GOLD if index == FIXTURE_BEFORE else C_EDGE_HI


func _choice_color(index: int) -> Color:
	match index:
		0:
			return C_AID
		1:
			return C_TRADE
		2:
			return C_FORTIFY
	return C_MUTED


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
			_set_fixture(int(key_event.keycode) - int(KEY_A))
		KEY_1, KEY_2, KEY_3:
			_set_choice(int(key_event.keycode) - int(KEY_1))
		KEY_TAB:
			_set_fixture((_fixture + 1) % 6)
		KEY_V:
			_set_fixture(FIXTURE_BEFORE if _fixture not in [FIXTURE_BEFORE, FIXTURE_OPTIONS] \
				else FIXTURE_AID + _selected_choice)
		KEY_ENTER, KEY_SPACE:
			_advance_fixture()
		KEY_R:
			_load_ok = _build_real_fixtures()
			queue_redraw()


func _set_fixture(value: int) -> void:
	_fixture = clampi(value, FIXTURE_BEFORE, FIXTURE_INTEL)
	_sync_choice_to_fixture()
	queue_redraw()


func _set_choice(value: int) -> void:
	_selected_choice = clampi(value, 0, CHOICE_KEYS.size() - 1)
	if _fixture in [FIXTURE_AID, FIXTURE_TRADE, FIXTURE_FORTIFY]:
		_fixture = FIXTURE_AID + _selected_choice
	queue_redraw()


func _advance_fixture() -> void:
	if _fixture == FIXTURE_BEFORE:
		_fixture = FIXTURE_OPTIONS
	elif _fixture == FIXTURE_OPTIONS:
		_fixture = FIXTURE_AID + _selected_choice
	elif _fixture in [FIXTURE_AID, FIXTURE_FORTIFY]:
		_fixture = FIXTURE_INTEL
	else:
		_fixture = FIXTURE_OPTIONS
	_sync_choice_to_fixture()
	queue_redraw()


func _handle_click(click_position: Vector2) -> void:
	for index in range(_fixture_rects.size()):
		if _fixture_rects[index].has_point(click_position):
			_set_fixture(index)
			return
	for index in range(_choice_rects.size()):
		if _choice_rects[index].has_point(click_position):
			_set_choice(index)
			return


func _save_shot() -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("SettlementNetworkLab could not capture the viewport")
		get_tree().quit(1)
		return
	var save_error := image.save_png(_shot_path)
	if save_error != OK:
		push_error("SettlementNetworkLab could not save screenshot: %s" % error_string(save_error))
		get_tree().quit(1)
		return
	get_tree().quit()
