extends Node
## LT-11 focused product-UI check: readable service decisions, real doors, and inert presentation.

const MainScene = preload("res://scenes/Main.tscn")
const Inv = preload("res://bench/Invariants.gd")
const NEED_LABELS := {"hunger": "饱腹", "energy": "精力", "social": "社交", "fun": "趣味", "hygiene": "卫生"}

var fails := 0

func ck(ok: bool, label: String, detail := "") -> void:
	print("  %s %s%s" % ["OK  " if ok else "FAIL", label, " — " + detail if detail != "" else ""])
	if not ok:
		fails += 1

func _noop() -> void:
	pass

func _ui_state() -> Dictionary:
	return {"digest": Inv.digest(Sim), "event_digest": Sim.event_digest,
		"money_total": Sim.money_total(), "trace": Sim.get_player_trace(),
		"deposits": Sim.bank_deposits.duplicate(true), "loans": Sim.bank_loans.duplicate(true)}

func _find_service(actor: Dictionary) -> Dictionary:
	var fallback := {}
	for object_id in Sim.world.get("objects", {}).keys():
		var obj: Dictionary = Sim.world["objects"][object_id]
		for offer: Dictionary in Sim._life_object_actions(actor, obj):
			if not bool(offer.get("ok", false)):
				continue
			var candidate := {"id": String(object_id), "object": obj, "offer": offer}
			if int(offer.get("price", 0)) > 0:
				return candidate
			if fallback.is_empty():
				fallback = candidate
	return fallback

func _tap_cell(life: Node, main: Node, cell: Vector2i) -> void:
	var probe: Node = main.get("_probe")
	var viewport_size: Vector2 = main.call("_vp")
	var world_point: Vector2 = Vector2(cell.x * 48 + 24, cell.y * 48 + 24)
	var cam: Camera2D = probe.get("cam")
	var screen_point: Vector2 = viewport_size * 0.5 + (world_point - cam.position) * cam.zoom
	life.call("_tap", screen_point)

func _find_wall_target(life: Node, main: Node, actor: Dictionary) -> Vector2i:
	var sp := String(actor.get("space", "town")); var fl := String(actor.get("floor", "outdoor"))
	var grid: Dictionary = Sim._grid_for(sp, fl)
	var interests: Array = Sim.life_interactions(999)
	for radius in range(2, 10):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var cell: Vector2i = actor["pos"] + Vector2i(x, y)
				if Sim._cell_walkable(grid, cell):
					continue
				var is_portal := false
				for hop: Dictionary in Sim._portals_from(sp, fl, actor):
					if hop.get("from_pos", Vector2i(-99, -99)) == cell:
						is_portal = true
						break
				if is_portal:
					continue
				var center := Vector2(cell.x * 48 + 24, cell.y * 48 + 24)
				var overlaps := false
				for entry: Dictionary in interests:
					var ep: Vector2i = entry.get("pos", Vector2i(-99, -99))
					if Vector2(ep.x * 48 + 24, ep.y * 48 + 24).distance_to(center) <= 30.0:
						overlaps = true
						break
				if overlaps:
					continue
				_tap_cell(life, main, cell)
				return cell
	return Vector2i(-99, -99)

func _ready() -> void:
	Sim.backend = null
	Sim.auto_run = false
	Sim.start_new(20260930)
	var main: Node = MainScene.instantiate()
	main.set("_player_mode", false)
	add_child(main)
	await get_tree().process_frame
	var life: Node = main.get("_life")
	life.call("start_life", "ben")
	Sim.running = false
	var actor := Sim.get_agent("ben")
	var baseline := _ui_state()
	var service_need_text := ""
	var service_offer: Dictionary = {}
	life.call("_use_now", "__missing_object__", "吃饭")
	var toast: Label = life.get("_toast")
	ck(String(toast.text).begins_with("未能开始：") and _ui_state() == baseline,
		"rejected service explains why it did not start without changing authority", String(toast.text))

	var service := _find_service(actor)
	ck(not service.is_empty(), "live world exposes at least one available service")
	if not service.is_empty():
		var offer: Dictionary = service["offer"]
		service_offer = offer
		var object_id := String(service["id"])
		var obj_for_menu: Dictionary = service["object"]
		var entry := {"kind": "object", "id": object_id,
			"label": String(obj_for_menu.get("type", object_id)), "dist": Sim._manh(actor["pos"], obj_for_menu["pos"]),
			"actions": Sim._life_object_actions(actor, obj_for_menu)}
		life.call("_open_modal", entry)
		await get_tree().process_frame
		var action_button: Button = null
		var button_texts: Array[String] = []
		for child: Node in life.get("_modal").get_children():
			if child is Button:
				button_texts.append((child as Button).text)
				if String((child as Button).tooltip_text).contains(String(offer.get("action", ""))) or String((child as Button).text).contains(String(offer.get("action", ""))):
					action_button = child as Button
					break
		var price_text := "%d 币" % int(offer.get("price", 0)) if int(offer.get("price", 0)) > 0 else ""
		service_need_text = String(NEED_LABELS.get(String(offer.get("need", "")), String(offer.get("need", ""))))
		ck(action_button != null and action_button.text.contains(service_need_text)
			and action_button.text.contains("+%d" % int(offer.get("amount", 0)))
			and (price_text == "" or action_button.text.contains(price_text)),
			"service row shows effect and current price at the decision point", "action=%s row=%s options=%s" % [String(offer.get("action", "")), action_button.text if action_button != null else "missing", str(button_texts)])
		if action_button != null:
			ck(action_button.tooltip_text == action_button.text.trim_prefix("1  ")
				and action_button.size.y >= 30.0, "service row preserves full text and a usable hit target")
		life.call("_close_modal")
		life.set("touch", true)
		life.call("_open_modal", entry)
		await get_tree().process_frame
		var touch_button: Button = null
		for child: Node in life.get("_modal").get_children():
			if child is Button:
				touch_button = child as Button
				break
		ck(touch_button != null and touch_button.size.y >= 54.0,
			"touch interaction row keeps the 54 px minimum hit target")
		life.call("_close_modal")
		life.set("touch", false)

	for _repeat in 3:
		life.call("_open_modal", {})
		life.call("_close_modal")
	main.call("_probe_toggle_space")
	main.call("_probe_toggle_space")
	ck(_ui_state() == baseline, "repeated panel open/close and camera focus do not change simulation or trace")
	main.set("_reduced_motion", true)
	var probe: Node = main.get("_probe")
	probe.get("cam").position = Vector2(0, 0)
	life.call("_camera", 0.05, actor)
	var expected_camera: Vector2 = life.call("_agent_px", actor) + Vector2(0, -12)
	ck(probe.get("cam").position.is_equal_approx(expected_camera) and _ui_state() == baseline,
		"reduced-motion camera snaps without changing authority")

	var hops: Array = Sim._portals_from(String(actor.get("space", "town")), String(actor.get("floor", "outdoor")), actor)
	var far_hop := {}
	for hop: Dictionary in hops:
		if Sim._manh(actor["pos"], hop.get("from_pos", Vector2i(-99, -99))) > 2:
			far_hop = hop
			break
	if not far_hop.is_empty():
		_tap_cell(life, main, far_hop["from_pos"])
		var goal: Dictionary = life.get("_walk_goal")
		ck(bool(life.get("_walk_on")) and String(goal.get("kind", "")) == "portal"
			and _ui_state() == baseline, "clicking a distant authored door starts travel to that entrance", str(far_hop.get("portal_id", "")))
		life.call("_walk_stop")
	else:
		ck(false, "fixture contains a distant authorized authored entrance")
	var wall_cell := _find_wall_target(life, main, actor)
	ck(wall_cell.x >= 0 and String(toast.text).contains("没有入口或互动目标")
		and _ui_state() == baseline, "clicking solid scenery gives an entry hint without changing authority", str(wall_cell))

	if not service.is_empty():
		var obj: Dictionary = service["object"]
		var stand := Vector2i(-99, -99)
		var grid: Dictionary = Sim._grid_for(String(obj.get("space", "town")), String(obj.get("floor", "outdoor")))
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if Sim._cell_walkable(grid, obj["pos"] + direction):
				stand = obj["pos"] + direction
				break
		actor["space"] = String(obj.get("space", "town")); actor["floor"] = String(obj.get("floor", "outdoor"))
		Sim._move_agent(actor, stand)
		life.call("_use_now", String(service["id"]), String(service_offer.get("action", "")))
		ck(String(toast.text).begins_with("已安排：") or String(toast.text).begins_with("已排队："),
			"accepted service gives an immediate pending-action receipt", String(toast.text))
		for _tick in 120:
			if actor.get("option") == null:
				break
			Sim.tick()
		ck(String(toast.text).begins_with("完成：") and String(toast.text).contains(service_need_text),
			"completed service reports the resolved need effect", String(toast.text))

	main.free()
	print("interaction_legibility_test: %s (%d fail)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)
