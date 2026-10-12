extends Node
## Isolated fixture checks for LT-08 failure paths. State setup here is test-only;
## player_first_session_test.gd remains the unmodified canonical end-to-end arm.

var _fails := 0

func _check(label: String, ok: bool, detail := "") -> void:
	print("  %s %s %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		_fails += 1

func _fixture(seed: int = 41) -> Dictionary:
	Sim.backend = null
	Sim.auto_run = false
	Sim.start_new(seed)
	Sim.possess("ben")
	for resident: Dictionary in Sim.agents:
		resident["option"] = null
		resident["talking"] = 0
	return Sim.get_agent("ben")

func _free_neighbor(obj: Dictionary) -> Vector2i:
	var grid: Dictionary = Sim._grid_for(String(obj.get("space", "town")), String(obj.get("floor", "outdoor")))
	var pos: Vector2i = obj.get("pos", Vector2i(-99, -99))
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if Sim._cell_walkable(grid, pos + direction):
			return pos + direction
	return Vector2i(-99, -99)

func _place(agent: Dictionary, space: String, floor: String, pos: Vector2i) -> void:
	agent["option"] = null
	agent["talking"] = 0
	agent["space"] = space
	agent["floor"] = floor
	Sim._move_agent(agent, pos)

func _find_live_action(action_name: String, seated_only := false) -> Dictionary:
	var actor: Dictionary = Sim.get_agent("ben")
	for object_id in Sim.world.get("objects", {}).keys():
		var obj: Dictionary = Sim.world["objects"][object_id]
		for action: Dictionary in Sim._life_object_actions(actor, obj):
			if String(action.get("action", "")) != action_name or not bool(action.get("ok", false)):
				continue
			for advert: Dictionary in obj.get("advertises", []):
				if String(advert.get("action", "")) != action_name:
					continue
				if seated_only and (not bool(advert.get("seated", false)) or int(advert.get("seats", 0)) <= 0):
					continue
				return {"id": String(object_id), "object": obj, "action": action, "advert": advert}
	return {}

func _ready() -> void:
	_test_closed_vendor()
	_test_insufficient_pantry_funds()
	_test_unpaid_meal_policy()
	_test_occupied_table()
	_test_unavailable_partner()
	_test_decorative_object()
	print("=== LT-08 ADVERSARIAL: %s (%d failures) ===" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)

func _test_closed_vendor() -> void:
	var actor := _fixture()
	var closed_case := {}
	for probe_tick in Sim.TICKS_PER_DAY:
		Sim.tick_no = probe_tick
		for object_id in Sim.world.get("objects", {}).keys():
			var obj: Dictionary = Sim.world["objects"][object_id]
			for action: Dictionary in Sim._life_object_actions(actor, obj):
				var name := String(action.get("action", ""))
				if int(action.get("price", 0)) <= 0 or Sim._vendor_for(name).is_empty():
					continue
				if not bool(action.get("ok", false)) and String(action.get("why", "")) == "现在不开":
					closed_case = {"tick": probe_tick, "id": String(object_id), "obj": obj, "action": name, "result": action}
					break
			if not closed_case.is_empty():
				break
		if not closed_case.is_empty():
			break
	var closed := not closed_case.is_empty()
	if closed:
		var obj: Dictionary = closed_case["obj"]
		var stand := _free_neighbor(obj)
		Sim.tick_no = int(closed_case["tick"])
		_place(actor, String(obj.get("space", "town")), String(obj.get("floor", "outdoor")), stand)
		var result := Sim.life_use(String(closed_case["id"]), String(closed_case["action"]))
		_check("closed shop shows an explicit disabled reason", String(closed_case["result"].get("why", "")) == "现在不开"
			and not bool(closed_case["result"].get("ok", true)), "tick=%d action=%s" % [int(closed_case["tick"]), String(closed_case["action"])])
		_check("closed shop rejects without leaving a pending action", result == "现在不开" and actor.get("option") == null, result)
	else:
		_check("fixture contains a scheduled paid vendor action that can be closed", false)

func _test_insufficient_pantry_funds() -> void:
	var actor := _fixture(42)
	var candidate := _find_live_action("采买")
	if candidate.is_empty():
		candidate = _find_live_action("买干粮")
	var found := not candidate.is_empty()
	if found:
		var obj: Dictionary = candidate["object"]
		Sim._set_coin("ben", 0)
		_place(actor, String(obj.get("space", "town")), String(obj.get("floor", "outdoor")), _free_neighbor(obj))
		var action_name := String(candidate["action"].get("action", ""))
		var options: Array = Sim._life_object_actions(actor, obj)
		var status := {}
		for option: Dictionary in options:
			if String(option.get("action", "")) == action_name:
				status = option
				break
		var result := Sim.life_use(String(candidate["id"]), action_name)
		_check("unaffordable pantry purchase explains why it is disabled", not status.is_empty()
			and not bool(status.get("ok", true)) and String(status.get("why", "")) == "钱不够"
			and not bool(status.get("affordable", true)), action_name)
		_check("unaffordable purchase does not start a silent trip", result == "钱不够" and actor.get("option") == null
			and Sim._coin_of("ben") == 0, result)
	else:
		_check("fixture contains a pantry purchase", false)
		_check("unaffordable purchase does not start a silent trip", false)

func _test_unpaid_meal_policy() -> void:
	var actor := _fixture(43)
	var candidate := _find_live_action("吃饭")
	var found := not candidate.is_empty() and int(candidate.get("action", {}).get("price", 0)) > 0
	if found:
		var obj: Dictionary = candidate["object"]
		var action: Dictionary = candidate["action"]
		Sim._set_coin("ben", 0)
		_place(actor, String(obj.get("space", "town")), String(obj.get("floor", "outdoor")), _free_neighbor(obj))
		actor["needs"]["hunger"] = 10.0
		var current_action := {}
		for option: Dictionary in Sim._life_object_actions(actor, obj):
			if String(option.get("action", "")) == "吃饭":
				current_action = option
				break
		var before := float(actor["needs"]["hunger"])
		var mark := Sim.event_log.size()
		var result := Sim.life_use(String(candidate["id"]), "吃饭")
		for _tick in 200:
			if actor.get("option") == null:
				break
			Sim.tick()
		var paid := false
		for event in Sim.event_log.slice(mark):
			if String(event.get("type", "")) == "pay" and String(event.get("actor", "")) == "ben":
				paid = true
		_check("life-preserving meal remains available when funds are short", result == ""
			and not bool(current_action.get("affordable", true)), "result=%s menu=%s" % [result, str(current_action)])
		_check("unpaid meal resolves without fake payment or deadlock", actor.get("option") == null and not paid
			and Sim._coin_of("ben") == 0 and float(actor["needs"]["hunger"]) > before,
			"wallet=%d hunger %.1f→%.1f" % [Sim._coin_of("ben"), before, float(actor["needs"]["hunger"])])
	else:
		_check("fixture contains a paid survival meal", false)
		_check("unpaid meal resolves without fake payment or deadlock", false)

func _test_occupied_table() -> void:
	var actor := _fixture(44)
	var candidate := _find_live_action("吃饭", true)
	if candidate.is_empty():
		_check("fixture contains a one-or-more-seat meal service", false)
		_check("occupied table releases into service without deadlock", false)
		return
	var obj: Dictionary = candidate["object"]
	var advert: Dictionary = candidate["advert"]
	var occupants: Array[Dictionary] = []
	var stand := _free_neighbor(obj)
	_place(actor, String(obj.get("space", "town")), String(obj.get("floor", "outdoor")), stand)
	for resident: Dictionary in Sim.agents:
		if String(resident.get("id", "")) == "ben":
			continue
		resident["option"] = {
			"kind": "object",
			"target": String(candidate["id"]),
			"action": "吃饭",
			"need": "hunger",
			"amount": int(candidate["action"].get("amount", 50)),
			"dur_total": int(candidate["action"].get("duration", 18)),
			"phase": "use",
			"remaining": 100,
		}
		occupants.append(resident)
		if occupants.size() >= int(advert.get("seats", 1)):
			break
	var result := Sim.life_use(String(candidate["id"]), "吃饭")
	if result == "":
		Sim.tick()
	var queued_option = actor.get("option")
	var queued: bool = queued_option is Dictionary and String(queued_option.get("phase", "")) == "travel" \
		and queued_option.has("queued_at")
	_check("occupied table waits without entering service", queued and not Sim._seat_free(obj, advert, "ben", queued_option if queued_option is Dictionary else {}),
		"result=%s option=%s" % [result, str(queued_option)])
	for occupant: Dictionary in occupants:
		occupant["option"] = null
	var completed := false
	for _tick in 200:
		Sim.tick()
		if actor.get("option") == null:
			completed = true
			break
	_check("occupied table releases into service without deadlock", result == "" and completed,
		"option=%s seat_count=%d" % [str(actor.get("option")), int(advert.get("seats", 0))])

func _test_unavailable_partner() -> void:
	var actor := _fixture(45)
	var partner: Dictionary = Sim.get_agent("aria")
	var pos := Sim._area_centroid("plaza")
	_place(actor, "town", "outdoor", pos)
	_place(partner, "town", "outdoor", pos + Vector2i(1, 0))
	partner["talking"] = 10
	partner["talk_with"] = "coco"
	var greet: Dictionary = {}
	for option: Dictionary in Sim.life_verb_options("aria"):
		if String(option.get("action", "")) == "greet":
			greet = option
			break
	var result := Sim.life_social("greet", "aria")
	_check("busy partner exposes an understandable social reason", not greet.is_empty()
		and not bool(greet.get("ok", true)) and String(greet.get("why", "")).contains("正忙"), String(greet.get("why", "")))
	_check("unavailable partner leaves no pending conversation", result.contains("正忙") and actor.get("option") == null, result)

func _test_decorative_object() -> void:
	var actor := _fixture(46)
	var map_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/map.json"))
	var home: Dictionary = map_data.get("areas", {}).get("home", {})
	var rect: Array = home.get("rect", [])
	var facade := Vector2i(-99, -99)
	if rect.size() >= 4:
		for raw_cell: Array in map_data.get("walls", []):
			var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
			var on_home_wall := cell.x == int(rect[0]) or cell.x == int(rect[0]) + int(rect[2]) - 1 \
				or cell.y == int(rect[1]) or cell.y == int(rect[1]) + int(rect[3]) - 1
			var has_object := false
			for obj: Dictionary in Sim.world.get("objects", {}).values():
				if obj.get("pos", Vector2i(-99, -99)) == cell:
					has_object = true
					break
			if not on_home_wall or has_object or not Sim._portals_from("town", "outdoor", actor).filter(func(h): return h.get("from_pos") == cell).is_empty():
				continue
			facade = cell
			break
	var nearby_service := false
	for entry: Dictionary in Sim.life_interactions(999):
		if entry.get("kind", "") == "object" and entry.get("pos") == facade:
			nearby_service = true
	var result := Sim.life_use("home_facade_%d_%d" % [facade.x, facade.y], "使用") if facade.x >= 0 else "fixture_missing"
	_check("authored home facade has no service or portal target", facade.x >= 0 and not nearby_service
		and not Sim._cell_walkable(Sim._grid_for("town", "outdoor"), facade), str(facade))
	_check("decorative facade click target cannot start a phantom service", result == "够不着" and actor.get("option") == null, result)
