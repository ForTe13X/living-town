extends "res://scripts/player_journey_test.gd"
## Canonical new-game route probe for LT-08. All movement, portal, service, and
## social actions are dispatched as viewport input; queries only inspect state.

const KEY_FOR_DELTA := {
	Vector2i(1, 0): KEY_D, Vector2i(-1, 0): KEY_A,
	Vector2i(0, 1): KEY_S, Vector2i(0, -1): KEY_W,
}
var pid := ""

func _run() -> void:
	_pin_settings()
	_scenario_id = "canonical_home_to_town_venue_service_social"
	_evidence_dir = OS.get_environment("LT_JOURNEY_EVIDENCE_DIR")
	if _evidence_dir.is_empty():
		_evidence_dir = ProjectSettings.globalize_path("user://player_first_session_evidence")
	DirAccess.make_dir_recursive_absolute(_evidence_dir)
	_main = MAIN_SCENE.instantiate() as Node2D
	add_child(_main)
	await _wait_frames(5)
	_life = _main.get("_life") as Node
	_check("canonical new game opens resident selection", _life != null and bool(_life.get("selecting")))
	if _life == null:
		_finish()
		return
	var ids: Array = _life.get("_sel_ids")
	# Aria's authored cafe start exercises a known reachable route to town.
	var selected_index := 0
	var card: Control = (_life.get("_sel_cards") as Array)[selected_index]
	await _click(card)
	await _send_key(KEY_ENTER)
	await _wait_frames(3)
	pid = String(_life.get("pid"))
	var actor := Sim.get_agent(pid)
	_check("ordinary controls enter the selected resident", bool(_life.get("active")) and pid == String(ids[selected_index]), pid)
	if actor.is_empty():
		_finish()
		return
	await _save_checkpoint("01_new_game_started")
	# Request cancellation through the normal key. Some social interactions are
	# intentionally non-cancelable, so let those resolve on ordinary sim ticks.
	if actor.get("option") != null:
		await _send_key(KEY_Q)
		for _settle_frame in 240:
			if Sim.get_agent(pid).get("option") == null:
				break
			await get_tree().create_timer(0.125).timeout
	actor = Sim.get_agent(pid)
	_check("startup resident action resolves or cancels through ordinary play", actor.get("option") == null,
		str(actor.get("option", {})))
	if actor.get("option") != null:
		_finish()
		return
	var town_arrived := false
	var portal_hops := 0
	for _route_leg in 6:
		actor = Sim.get_agent(pid)
		var hop: Dictionary = Sim._route_next_hop(String(actor.get("space", "")),
			String(actor.get("floor", "")), "town", "outdoor", actor)
		if hop.is_empty():
			break
		portal_hops += 1
		var exit_pos: Vector2i = hop["from_pos"]
		var walked_to_exit := await _walk_by_controls(exit_pos, 100)
		var actor_after_walk: Dictionary = Sim.get_agent(pid)
		var actor_grid: Dictionary = Sim._grid_for(String(actor_after_walk.get("space", "")),
			String(actor_after_walk.get("floor", "")))
		var remaining_path: Array = Sim._astar_path(actor_grid,
			actor_after_walk.get("pos", Vector2i(-99, -99)), exit_pos)
		_check("resident reaches the next authored portal using movement keys", walked_to_exit,
			"hop=%s pos=%s goal=%s plane=%s/%s remaining_path=%d" % [String(hop.get("portal_id", "")),
			str(actor_after_walk.get("pos")), str(exit_pos), String(actor_after_walk.get("space", "")),
			String(actor_after_walk.get("floor", "")), remaining_path.size()])
		if not walked_to_exit:
			break
		await _save_checkpoint("02_portal_%02d_reached" % portal_hops)
		await _click_world_cell(exit_pos)
		var exit_button_text := "出门" if String(hop.get("to_space", "")) == "town" else "走进去"
		var exit_button := _button_containing(exit_button_text) if bool(_life.get("_modal_open")) else null
		_check("portal menu labels its real next destination", exit_button != null,
			"portal=%s destination=%s" % [String(hop.get("portal_id", "")), String(hop.get("to_space", ""))])
		if exit_button == null:
			break
		var prior_space := String(actor.get("space", ""))
		await _click(exit_button)
		await _wait_frames(4)
		var after_actor := Sim.get_agent(pid)
		var traversed := String(after_actor.get("space", "")) == String(hop.get("to_space", "")) \
			and String(after_actor.get("floor", "")) == String(hop.get("to_floor", ""))
		_check("portal click follows the authored route", traversed,
			"%s/%s -> %s/%s" % [prior_space, String(actor.get("floor", "")),
			String(after_actor.get("space", "")), String(after_actor.get("floor", ""))])
		if not traversed:
			break
		if String(after_actor.get("space", "")) == "town":
			town_arrived = true
			break
	_check("resident reaches the town through permitted portals", town_arrived, "hops=%d" % portal_hops)
	if not town_arrived:
		_finish()
		return
	await _save_checkpoint("03_town_arrival")
	var social_ok := await _run_social_leg()
	if not social_ok:
		_finish()
		return
	var post_social_option = Sim.get_agent(pid).get("option")
	if post_social_option != null:
		await _send_key(KEY_Q)
		for _manual_control_wait in 240:
			if Sim.get_agent(pid).get("option") == null:
				break
			await get_tree().create_timer(0.125).timeout
	_check("normal cancel control returns the resident to manual travel after social", Sim.get_agent(pid).get("option") == null,
		str(Sim.get_agent(pid).get("option")))
	if Sim.get_agent(pid).get("option") != null:
		_finish()
		return
	var town_actor := Sim.get_agent(pid)
	var cafe_door: Dictionary = Sim._route_next_hop("town", "outdoor", "cafe", "1f", town_actor)
	_check("public cafe appears in authored town routes", not cafe_door.is_empty())
	if cafe_door.is_empty():
		_finish()
		return
	var cafe_pos: Vector2i = cafe_door["from_pos"]
	var cafe_stand := _nearest_walkable_stand_pos(cafe_pos)
	var reached_cafe_door := cafe_stand.x >= 0 and await _walk_by_controls(cafe_stand, 160)
	var cafe_actor: Dictionary = Sim.get_agent(pid)
	var cafe_grid: Dictionary = Sim._grid_for(String(cafe_actor.get("space", "town")), String(cafe_actor.get("floor", "outdoor")))
	var cafe_static_path: Array = Sim._astar_path(cafe_grid, cafe_actor.get("pos", Vector2i(-99, -99)), cafe_pos)
	var cafe_dynamic_path: Array = _player_path(cafe_grid, cafe_actor.get("pos", Vector2i(-99, -99)), cafe_pos)
	var cafe_blockers: Array[String] = []
	for resident: Dictionary in Sim.agents:
		if String(resident.get("id", "")) != pid and Sim._same_plane(cafe_actor, resident) \
				and Sim._manh(resident.get("pos", Vector2i(-99, -99)), cafe_pos) <= 2:
			cafe_blockers.append("%s@%s" % [String(resident.get("id", "")), str(resident.get("pos", Vector2i(-99, -99)))])
	_check("keyboard movement reaches a walkable cafe entrance stand", reached_cafe_door,
		"%s -> %s stand=%s portal=%s static_path=%d portal_path=%d nearby=%s" % [str(town_actor.get("pos")),
		str(cafe_actor.get("pos")), str(cafe_stand), str(cafe_pos), cafe_static_path.size(), cafe_dynamic_path.size(), ";".join(cafe_blockers)])
	if not reached_cafe_door:
		_finish()
		return
	await _click_world_cell(cafe_pos)
	var cafe_open := bool(_life.get("_modal_open"))
	var enter_button := _button_containing("走进去") if cafe_open else null
	_check("reachable cafe entrance opens a truthful entry option", enter_button != null)
	if enter_button == null:
		_finish()
		return
	await _click(enter_button)
	await _wait_frames(5)
	_check("entry option reaches the cafe interior", String(Sim.get_agent(pid).get("space", "")) == "cafe",
		"space=%s floor=%s" % [String(Sim.get_agent(pid).get("space", "")), String(Sim.get_agent(pid).get("floor", ""))])
	await _save_checkpoint("04_cafe_arrival")
	# Keep the simulator's clock moving through the ordinary speed control while
	# the venue is closed. We never force its schedule, stock, wallet, or seat state.
	var paid := _find_paid_service(pid, "cafe", "1f")
	if paid.is_empty():
		var unavailable := _service_status(pid, "cafe", "1f")
		_check("closed or unavailable venue returns a specific service reason", not unavailable.is_empty(), unavailable)
		await _send_key(KEY_3)
		await _send_key(KEY_3, false)
		for _wait_tick in 160:
			if not _find_paid_service(pid, "cafe", "1f").is_empty():
				break
			await get_tree().create_timer(0.125).timeout
		paid = _find_paid_service(pid, "cafe", "1f")
	_check("cafe offers an affordable paid action through its authored schedule", not paid.is_empty(),
		_service_status(pid, "cafe", "1f"))
	if paid.is_empty():
		_finish()
		return
	var before_coin := Sim._coin_of(pid)
	var paid_target: String = paid["target"]
	var paid_action: String = paid["action"]
	var paid_amount: int = int(paid["price"])
	var need_before := float(Sim.get_agent(pid).get("needs", {}).get(String(paid["need"]), 0.0))
	var obj: Dictionary = Sim.world.get("objects", {}).get(paid_target, {})
	await _click_world_cell(obj.get("pos", Vector2i(-99, -99)))
	var service_menu := bool(_life.get("_modal_open"))
	_check("clicking the reachable cafe service opens its product menu", service_menu, paid_target)
	if not service_menu:
		_finish()
		return
	var service_button := _button_containing(paid_action)
	_check("service menu displays the exact affordable price", service_button != null and not service_button.disabled
		and String(service_button.text).contains("%d 币" % paid_amount),
		"action=%s price=%d button=%s" % [paid_action, paid_amount, str(service_button.text if service_button != null else "")])
	if service_button == null or service_button.disabled:
		_finish()
		return
	var event_mark := Sim.event_log.size()
	await _click(service_button)
	await _save_checkpoint("05_paid_service_selected")
	await _send_key(KEY_3)
	await _send_key(KEY_3, false)
	var observed_option := false
	var service_completed := false
	for _frame in 480:
		var current_option = Sim.get_agent(pid).get("option")
		if current_option is Dictionary and String(current_option.get("target", "")) == paid_target:
			observed_option = true
		elif observed_option and not bool(_life.get("_walk_on")):
			service_completed = true
			break
		await get_tree().create_timer(0.125).timeout
	var pay_events: Array[Dictionary] = []
	for event in Sim.event_log.slice(event_mark):
		if String(event.get("type", "")) == "pay" and String(event.get("actor", "")) == pid:
			pay_events.append(event)
	var after_coin := Sim._coin_of(pid)
	var need_after := float(Sim.get_agent(pid).get("needs", {}).get(String(paid["need"]), 0.0))
	_check("paid service completes through normal movement and simulation ticks", observed_option and service_completed,
		"seen=%s complete=%s tick=%d" % [str(observed_option), str(service_completed), Sim.tick_no])
	_check("wallet change matches a recorded payment receipt", before_coin - after_coin == paid_amount and not pay_events.is_empty(),
		"wallet=%d -> %d price=%d receipts=%s" % [before_coin, after_coin, paid_amount, JSON.stringify(pay_events)])
	_check("service outcome changes its advertised need", need_after > need_before,
		"%s %.1f -> %.1f" % [String(paid["need"]), need_before, need_after])
	await _save_checkpoint("06_paid_service_receipt")
	_finish()

func _run_social_leg() -> bool:
	var social_target := _find_social_target()
	if social_target.is_empty():
		var returned := await _traverse_to_town()
		if returned:
			for _town_availability_wait in 160:
				social_target = _find_social_target()
				if not social_target.is_empty():
					break
				await get_tree().create_timer(0.125).timeout
		if social_target.is_empty() and returned:
			var actor: Dictionary = Sim.get_agent(pid)
			var neighborhood_hop: Dictionary = Sim._route_next_hop(String(actor.get("space", "")),
				String(actor.get("floor", "")), "home", "1f", actor)
			if not neighborhood_hop.is_empty():
				var reached_neighborhood := await _walk_by_controls(neighborhood_hop["from_pos"], 160)
				if reached_neighborhood:
					await _save_checkpoint("03_town_neighborhood")
					for _neighborhood_wait in 160:
						social_target = _find_social_target()
						if not social_target.is_empty():
							break
						await get_tree().create_timer(0.125).timeout
	_check("nearby resident offers at least one legal social action", not social_target.is_empty(),
		"plane=%s/%s actor_area=%s candidate=%s" % [String(Sim.get_agent(pid).get("space", "")),
			String(Sim.get_agent(pid).get("floor", "")), String(Sim._area_at(Sim.get_agent(pid).get("pos", Vector2i(-99, -99)))),
			JSON.stringify(social_target)])
	if social_target.is_empty():
		return false
	var social_id := String(social_target["id"])
	var social_action := String(social_target["action"])
	var approached := await _approach_resident(social_id, 160)
	_check("ordinary movement brings the resident within social reach", approached,
		"target=%s %s" % [social_id, _social_routing_diagnostic(social_id)])
	if not approached:
		return false
	var local_candidate := {}
	for _local_availability_wait in 160:
		local_candidate = _find_social_target(true)
		if not local_candidate.is_empty():
			break
		await get_tree().create_timer(0.125).timeout
	if local_candidate.is_empty():
		var activity_stand := _nearest_active_object_stand_pos()
		if activity_stand.x >= 0:
			var followed_resident_activity := await _walk_by_controls(activity_stand, 160)
			_check("ordinary movement reaches a resident's advertised activity", followed_resident_activity,
				"goal=%s pos=%s" % [str(activity_stand), str(Sim.get_agent(pid).get("pos"))])
			if followed_resident_activity:
				await _save_checkpoint("03_resident_activity_location")
				for _activity_wait in 160:
					local_candidate = _find_social_target(true)
					if not local_candidate.is_empty():
						break
					await get_tree().create_timer(0.125).timeout
	if not local_candidate.is_empty():
		social_target = local_candidate
		social_id = String(social_target["id"])
		social_action = String(social_target["action"])
	_check("available nearby resident is selected again at the interaction point", not local_candidate.is_empty(),
		JSON.stringify(social_target))
	if local_candidate.is_empty():
		return false
	await _wait_frames(3)
	var nearby: Array = Sim.life_interactions()
	var target_in_list := false
	for entry: Dictionary in nearby:
		if String(entry.get("kind", "")) == "agent" and String(entry.get("id", "")) == social_id:
			target_in_list = true
	_check("resident appears in the ordinary nearby interaction list", target_in_list, social_id)
	if not target_in_list:
		return false
	for _focus_step in nearby.size() + 1:
		if String(_life.get("_focus_id")) == social_id:
			break
		await _send_key(KEY_TAB)
		await _wait_frames()
	await _send_key(KEY_E)
	await _wait_frames(2)
	var social_menu := bool(_life.get("_modal_open")) and String(_life.get("_focus_id")) == social_id
	_check("E opens the focused resident's social interaction menu", social_menu, social_id)
	if not social_menu:
		return false
	var action_label := String(SOCIAL_LABELS.get(social_action, social_action))
	var social_button := _button_containing(action_label)
	_check("social menu exposes the legal action selected from its read-only options", social_button != null and not social_button.disabled,
		"action=%s label=%s" % [social_action, action_label])
	if social_button == null or social_button.disabled:
		return false
	var relation_before := _affinity(pid, social_id)
	var social_event_mark := Sim.event_log.size()
	await _click(social_button)
	var immediate_option = Sim.get_agent(pid).get("option")
	var toast_node: Label = _life.get("_toast") as Label
	_check("social button submits its selected action", immediate_option is Dictionary
		and String(immediate_option.get("partner", "")) == social_id,
		"option=%s toast=%s" % [str(immediate_option), String(toast_node.text if toast_node != null else "")])
	await _save_checkpoint("07_social_action_started")
	var social_started := false
	for _frame in 160:
		var option = Sim.get_agent(pid).get("option")
		if option is Dictionary and String(option.get("partner", "")) == social_id:
			social_started = true
		elif social_started and option == null:
			break
		await get_tree().create_timer(0.125).timeout
	var social_receipts: Array[Dictionary] = []
	for event in Sim.event_log.slice(social_event_mark):
		if String(event.get("actor", "")) == pid and String(event.get("target", "")) == social_id \
				and String(event.get("type", "")) == social_action:
			social_receipts.append(event)
	var accepted := not social_receipts.is_empty() and bool(social_receipts[-1].get("accepted", false))
	var relation_after := _affinity(pid, social_id)
	_check("social action resolves to an accepted event receipt", social_started and accepted,
		"action=%s target=%s same_area=%s started=%s final_option=%s receipts=%s" % [social_action, social_id,
		str(social_target.get("same_area", false)), str(social_started), str(Sim.get_agent(pid).get("option")), JSON.stringify(social_receipts)])
	_check("social outcome matches the relationship readout", not social_receipts.is_empty() and relation_after >= relation_before,
		"affinity %.1f -> %.1f" % [relation_before, relation_after])
	await _save_checkpoint("08_social_receipt")
	return accepted

const SOCIAL_LABELS := {"greet": "打招呼", "give": "送礼", "gossip": "说八卦", "invite": "约见",
	"confront": "理论", "apologize": "道歉", "discuss": "讨论", "confide": "倾诉",
	"endorse": "支持", "leak": "泄露", "rally_oust": "施压", "aid": "帮助", "gossip_rep": "说八卦"}

func _find_social_target(require_nearby := false) -> Dictionary:
	var actor: Dictionary = Sim.get_agent(String(_life.get("pid")))
	var own_area := String(Sim._area_at(actor.get("pos", Vector2i(-99, -99))))
	var best := {}
	var best_score := 0x7fffffff
	for entry: Dictionary in Sim.life_interactions(999):
		if String(entry.get("kind", "")) != "agent":
			continue
		if require_nearby and int(entry.get("dist", 999)) > 2:
			continue
		var options := Sim.life_verb_options(String(entry.get("id", "")), true)
		for option: Dictionary in options:
			if bool(option.get("ok", false)):
				var target_area := String(Sim._area_at(entry.get("pos", Vector2i(-99, -99))))
				var same_area := own_area != "" and own_area == target_area
				var target: Dictionary = Sim.get_agent(String(entry.get("id", "")))
				var option_value = target.get("option")
				var option_dictionary: Dictionary = option_value if option_value is Dictionary else {}
				var stable_use := String(option_dictionary.get("kind", "")) == "object" \
					and String(option_dictionary.get("phase", "")) == "use" \
					and int(option_dictionary.get("remaining", 0)) >= 12
				var remaining := int(option_dictionary.get("remaining", 0)) if stable_use else 0
				var moving := option_value is Dictionary and not stable_use
				if require_nearby and moving:
					continue
				var score := int(entry.get("dist", 999)) * 100 + (0 if same_area else 20) \
					+ (50 if moving else 0) - mini(remaining, 20) * 3
				if score < best_score:
					best_score = score
					best = {"id": String(entry["id"]), "action": String(option["action"]),
						"dist": int(entry.get("dist", 999)), "same_area": same_area, "area": target_area, "moving": moving,
						"stable_use": stable_use, "remaining": remaining, "option": option_dictionary,
						"pos": entry.get("pos", Vector2i(-99, -99)), "space": actor.get("space", ""), "floor": actor.get("floor", "")}
				break
	return best

func _approach_resident(target_id: String, max_steps: int) -> bool:
	for _step in max_steps:
		var actor: Dictionary = Sim.get_agent(String(_life.get("pid")))
		var target: Dictionary = Sim.get_agent(target_id)
		if actor.is_empty() or target.is_empty() or not Sim._same_plane(actor, target):
			return false
		if Sim._socially_reachable(actor, target):
			return true
		var from: Vector2i = actor.get("pos", Vector2i(-99, -99))
		var goal: Vector2i = target.get("pos", Vector2i(-99, -99))
		var grid: Dictionary = Sim._grid_for(String(actor["space"]), String(actor["floor"]))
		var path: Array = Sim._astar_path(grid, from, goal)
		if path.size() < 2:
			return false
		var direction: Vector2i = path[1] - from
		var keycode := int(KEY_FOR_DELTA.get(direction, 0))
		if keycode == 0:
			return false
		await _send_key(keycode)
		await get_tree().create_timer(0.18).timeout
		await _send_key(keycode, false)
	return false

func _traverse_to_town() -> bool:
	var pid := String(_life.get("pid"))
	for _route_leg in 6:
		var actor: Dictionary = Sim.get_agent(pid)
		if String(actor.get("space", "")) == "town":
			return true
		var hop: Dictionary = Sim._route_next_hop(String(actor.get("space", "")),
			String(actor.get("floor", "")), "town", "outdoor", actor)
		if hop.is_empty():
			return false
		var at_hop := await _walk_by_controls(hop["from_pos"], 100)
		if not at_hop:
			return false
		await _click_world_cell(hop["from_pos"])
		var label := "出门" if String(hop.get("to_space", "")) == "town" else "走进去"
		var button := _button_containing(label) if bool(_life.get("_modal_open")) else null
		if button == null:
			return false
		await _click(button)
		await _wait_frames(3)
	return String(Sim.get_agent(pid).get("space", "")) == "town"

func _affinity(actor_id: String, target_id: String) -> float:
	var actor: Dictionary = Sim.get_agent(actor_id)
	var relations: Dictionary = actor.get("relationships", {})
	var relation: Dictionary = relations.get(target_id, {})
	return float(relation.get("affinity", 0.0))

func _nearest_active_object_stand_pos() -> Vector2i:
	var actor: Dictionary = Sim.get_agent(pid)
	var grid: Dictionary = Sim._grid_for(String(actor.get("space", "town")), String(actor.get("floor", "outdoor")))
	var start: Vector2i = actor.get("pos", Vector2i(-99, -99))
	var objects: Dictionary = Sim.world.get("objects", {})
	var best := Vector2i(-99, -99)
	var best_cost := 0x7fffffff
	for resident: Dictionary in Sim.agents:
		if String(resident.get("id", "")) == pid or not Sim._same_plane(actor, resident):
			continue
		var option_value = resident.get("option")
		if not option_value is Dictionary or String(option_value.get("kind", "")) != "object":
			continue
		var object_id := String(option_value.get("target", ""))
		var obj: Dictionary = objects.get(object_id, {})
		if obj.is_empty() or String(obj.get("space", "town")) != String(actor.get("space", "town")) \
				or String(obj.get("floor", "outdoor")) != String(actor.get("floor", "outdoor")):
			continue
		var object_pos: Vector2i = obj.get("pos", Vector2i(-99, -99))
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var stand_pos := object_pos + direction
			if not Sim._cell_walkable(grid, stand_pos):
				continue
			var occupied := false
			for other: Dictionary in Sim.agents:
				if String(other.get("id", "")) != pid and Sim._same_plane(actor, other) \
						and other.get("pos", Vector2i(-99, -99)) == stand_pos:
					occupied = true
					break
			if occupied:
				continue
			var path: Array = Sim._astar_path(grid, start, stand_pos)
			if path.is_empty():
				continue
			if path.size() < best_cost:
				best_cost = path.size()
				best = stand_pos
	return best

func _social_routing_diagnostic(focus_id: String) -> String:
	var actor: Dictionary = Sim.get_agent(String(_life.get("pid")))
	var rows: Array[String] = []
	for candidate: Dictionary in Sim.life_interactions(999):
		if String(candidate.get("kind", "")) != "agent":
			continue
		var other: Dictionary = Sim.get_agent(String(candidate.get("id", "")))
		var option = other.get("option")
		rows.append("%s@%s area=%s busy=%s option=%s/%s rem=%d" % [String(candidate.get("id", "")),
			str(other.get("pos", Vector2i(-99, -99))), String(Sim._area_at(other.get("pos", Vector2i(-99, -99)))),
			str(int(other.get("talking", 0)) > 0), String(option.get("kind", "") if option is Dictionary else "idle"),
			String(option.get("phase", "") if option is Dictionary else ""), int(option.get("remaining", 0) if option is Dictionary else 0)])
	return "actor=%s area=%s target=%s candidates=%s" % [str(actor.get("pos", Vector2i(-99, -99))),
		String(Sim._area_at(actor.get("pos", Vector2i(-99, -99)))), focus_id, ";".join(rows)]

func _find_paid_service(pid: String, space: String, floor: String) -> Dictionary:
	var actor: Dictionary = Sim.get_agent(pid)
	for target_id in Sim.world.get("objects", {}).keys():
		var obj: Dictionary = Sim.world["objects"][target_id]
		if String(obj.get("space", "town")) != space or String(obj.get("floor", "outdoor")) != floor:
			continue
		for service: Dictionary in Sim._life_object_actions(actor, obj):
			var cost := int(service.get("price", 0))
			if bool(service.get("ok", false)) and cost > 0 and Sim._coin_of(pid) >= cost:
				return {"target": String(target_id), "action": String(service.get("action", "")),
					"price": cost, "need": String(service.get("need", "")), "duration": int(service.get("duration", 0))}
	return {}

func _service_status(pid: String, space: String, floor: String) -> String:
	var actor: Dictionary = Sim.get_agent(pid)
	var rows: Array[String] = []
	for target_id in Sim.world.get("objects", {}).keys():
		var obj: Dictionary = Sim.world["objects"][target_id]
		if String(obj.get("space", "town")) != space or String(obj.get("floor", "outdoor")) != floor:
			continue
		for service: Dictionary in Sim._life_object_actions(actor, obj):
			if int(service.get("price", 0)) > 0:
				rows.append("%s/%s price=%d ok=%s why=%s" % [String(target_id), String(service.get("action", "")),
					int(service.get("price", 0)), str(service.get("ok", false)), String(service.get("why", ""))])
	return "; ".join(rows)

func _walk_by_controls(goal: Vector2i, max_steps: int) -> bool:
	var blocked_retries := 0
	for _step in max_steps:
		var actor: Dictionary = Sim.get_agent(String(_life.get("pid")))
		if actor.get("option") != null:
			await _send_key(KEY_Q)
			for _idle_wait in 240:
				if Sim.get_agent(String(_life.get("pid"))).get("option") == null:
					break
				await get_tree().create_timer(0.125).timeout
			if Sim.get_agent(String(_life.get("pid"))).get("option") != null:
				blocked_retries += 1
				if blocked_retries > 60:
					return false
				continue
		var from: Vector2i = actor.get("pos", Vector2i(-99, -99))
		if from == goal:
			return true
		var space := String(actor.get("space", "town"))
		var floor := String(actor.get("floor", "outdoor"))
		var grid: Dictionary = Sim._grid_for(space, floor)
		var path: Array = _player_path(grid, from, goal)
		if path.size() < 2:
			blocked_retries += 1
			if blocked_retries > 60:
				return false
			await get_tree().create_timer(0.5).timeout
			continue
		var next: Vector2i = path[1]
		var direction := next - from
		var keycode := int(KEY_FOR_DELTA.get(direction, 0))
		if keycode == 0:
			return false
		await _send_key(keycode)
		await get_tree().create_timer(0.18).timeout
		await _send_key(keycode, false)
		var moved := false
		for _poll in 16:
			await get_tree().process_frame
			var now: Vector2i = Sim.get_agent(String(_life.get("pid"))).get("pos", from)
			if now != from:
				moved = true
				break
		if not moved:
			blocked_retries += 1
			if blocked_retries > 60:
				return false
			await get_tree().create_timer(0.5).timeout
			continue
		blocked_retries = 0
	return Sim.get_agent(String(_life.get("pid"))).get("pos", Vector2i(-99, -99)) == goal

func _player_path(grid: Dictionary, from: Vector2i, goal: Vector2i) -> Array:
	var nav_grid: Dictionary = grid.duplicate(true)
	var blocked: Dictionary = nav_grid.get("blocked", {}).duplicate()
	var width := int(nav_grid.get("w", 0))
	for resident: Dictionary in Sim.agents:
		if String(resident.get("id", "")) == String(_life.get("pid")) \
				or not Sim._same_plane(Sim.get_agent(String(_life.get("pid"))), resident):
			continue
		var cell: Vector2i = resident.get("pos", Vector2i(-99, -99))
		if cell == goal:
			return []
		blocked[cell.y * width + cell.x] = true
	nav_grid["blocked"] = blocked
	return Sim._astar_path(nav_grid, from, goal)

func _nearest_walkable_stand_pos(target_pos: Vector2i) -> Vector2i:
	var actor: Dictionary = Sim.get_agent(String(_life.get("pid")))
	var grid: Dictionary = Sim._grid_for(String(actor.get("space", "town")), String(actor.get("floor", "outdoor")))
	var start: Vector2i = actor.get("pos", Vector2i(-99, -99))
	var best := Vector2i(-99, -99)
	var best_cost := 0x7fffffff
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var stand_pos := target_pos + direction
		if not Sim._cell_walkable(grid, stand_pos):
			continue
		var path: Array = _player_path(grid, start, stand_pos)
		if not path.is_empty() and path.size() < best_cost:
			best_cost = path.size()
			best = stand_pos
	return best

func _click_world_cell(cell: Vector2i) -> void:
	var probe: Node = _main.get("_probe")
	var vp: Vector2 = _main.call("_vp")
	var world := Vector2(cell.x * 48 + 24, cell.y * 48 + 24)
	var screen: Vector2 = (world - probe.cam.position) * probe.cam.zoom + vp * 0.5
	for is_pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = screen
		event.global_position = screen
		event.pressed = is_pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if is_pressed else 0
		_inputs.append({"kind": "map_cell_click", "cell": [cell.x, cell.y], "position": [screen.x, screen.y], "pressed": is_pressed})
		get_viewport().push_input(event, true)
		await get_tree().process_frame

func _button_containing(text_part: String) -> Button:
	var modal: Node = _life.get("_modal")
	if modal == null:
		return null
	for child: Node in modal.get_children():
		if child is Button and String((child as Button).text).contains(text_part):
			return child as Button
	return null
