extends Node
## LT-19: input-driven inspection of the authored mairie notice board.

const MainScene = preload("res://scenes/Main.tscn")
const CivicPresentation = preload("res://scripts/CivicPresentation.gd")
const CivicProject = preload("res://scripts/CivicProject.gd")
const Inv = preload("res://bench/Invariants.gd")

var failures := 0
var main: Node
var life: Node
var capture_index := 0

func ck(ok: bool, label: String) -> void:
	print(("  OK   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1

func _ready() -> void:
	call_deferred("_run")

func _key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame

func _modal_text() -> String:
	var parts: Array[String] = []
	for child in life.get("_modal").get_children():
		if child is Label:
			parts.append((child as Label).text)
		elif child is RichTextLabel:
			parts.append((child as RichTextLabel).text)
		elif child is Button:
			parts.append((child as Button).text)
	return "\n".join(parts)

func _capture(phase: String) -> void:
	var args := OS.get_cmdline_user_args()
	var dir := ""
	for i in range(args.size() - 1):
		if args[i] == "--evidence-dir":
			dir = args[i + 1]
	if dir == "":
		return
	capture_index += 1
	DirAccess.make_dir_recursive_absolute(dir)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := dir.path_join("%02d-%s-civic-board.png" % [capture_index, phase])
	ck(image != null and image.get_width() == 1280 and image.get_height() == 768
		and image.save_png(path) == OK, "player civic modal capture writes at native resolution")

func _board_neighbor() -> Vector2i:
	var board := Sim.civic_observatory_cell()
	var grid: Dictionary = Sim._grid_for("mairie", "1f")
	for delta in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var cell: Vector2i = board + delta
		if Sim._cell_walkable(grid, cell):
			return cell
	return Vector2i(-1, -1)

func _inspect(tick: int, phase: String, receipt_part: String, scrub: bool = true) -> void:
	if scrub:
		ck(Sim.goto_tick(tick), "timeline reaches civic inspection tick %d" % tick)
	else:
		ck(Sim.tick_no == tick, "live civic inspection remains at tick %d" % tick)
	main._after_jump()
	var state: Dictionary = Sim.civic_project_state()
	ck(CivicPresentation.phase(state) == phase, "project authority is %s at tick %d" % [phase, tick])
	var neighbor := _board_neighbor()
	ck(neighbor.x >= 0, "authored notice board has a walkable neighboring cell")
	if neighbor.x < 0:
		return
	var actor: Dictionary = Sim.get_agent("ben")
	actor["space"] = "mairie"
	actor["floor"] = "1f"
	actor["option"] = null
	actor["talking"] = 0
	Sim._move_agent(actor, neighbor)
	life.start_life("ben")
	Sim.auto_run = false
	Sim.running = false
	life.call("_refresh_inter")
	var nearby: Array = Sim.life_interactions()
	var has_board := false
	for entry: Dictionary in nearby:
		if String(entry.get("id", "")) == "civic_observatory":
			has_board = String(entry.get("kind", "")) == "civic"
	ck(has_board, "mairie notice board is discoverable as a civic interaction")
	if not has_board:
		return
	for i in range(nearby.size() + 1):
		if String(life.get("_focus_id")) == "civic_observatory":
			break
		await _key(KEY_TAB)
	ck(String(life.get("_focus_id")) == "civic_observatory", "Tab focuses the authored notice board")
	var digest := Inv.digest(Sim)
	var event_digest := Sim.event_digest
	var money := Sim.money_total()
	var trace := Sim.get_player_trace()
	await _key(KEY_E)
	var modal_entry: Dictionary = life.get("_modal_entry")
	var content := _modal_text()
	ck(bool(life.get("_modal_open")) and String(modal_entry.get("kind", "")) == "civic"
		and content.contains("只读公示"), "E opens the read-only civic board modal")
	ck(content.contains(receipt_part) if receipt_part != "" else not content.contains("广场绣球花圃"),
		"board text matches the authoritative %s receipt" % phase)
	var buttons: Array[String] = []
	for child in life.get("_modal").get_children():
		if child is Button:
			buttons.append((child as Button).text)
	ck(buttons.size() == 1 and buttons[0].trim_prefix("1  ") == "收起公示",
		"inspection exposes no approval, payment, or construction action: %s" % str(buttons))
	await _capture(phase if phase != "" else String(state.get("status", "unknown")))
	ck(not Sim.running and Inv.digest(Sim) == digest and Sim.event_digest == event_digest
		and Sim.money_total() == money and Sim.get_player_trace() == trace,
		"opening the board pauses play without changing state, money, events, or trace")
	await _key(KEY_E)
	ck(not bool(life.get("_modal_open")) and Inv.digest(Sim) == digest
		and Sim.event_digest == event_digest and Sim.money_total() == money,
		"E closes the civic board without changing project authority")
	Sim.running = false

func _run() -> void:
	main = MainScene.instantiate()
	add_child(main)
	life = main.get("_life")
	ck(life != null, "Main provides the player Life Mode")
	if life == null:
		get_tree().quit(1)
		return
	ck(Sim.core_population == 12 and Sim.seed_base == 7,
		"civic player journey starts from the authored 12-core seed-7 fixture")
	Sim.auto_run = false
	Sim.running = false
	await _inspect(6481, "planned", "尚未动用镇库")
	await _inspect(6482, "underway", "镇库已支付 5 币")
	var paid: Dictionary = Sim.civic_project_state()
	var saved_digest := Sim.event_digest
	var save_path := "user://civic_player_paid_journey.dat"
	ck(Sim.save_game(save_path, {"fixture": "civic_player_paid_journey"}),
		"player inspection journey saves after the one legitimate payment")
	Sim.start_new(11)
	ck(Sim.load_game(save_path), "normal load restores the paid project after a different world")
	main._after_load()
	ck(Sim.civic_project_state() == paid and Sim.event_digest == saved_digest,
		"paid receipt and event digest survive fresh-world load")
	await _inspect(6482, "underway", "镇库已支付 5 币")
	await _inspect(7202, "complete", "收据 #")
	var completed: Dictionary = Sim.civic_project_state()
	ck(String(completed.get("status", "")) == "complete"
		and int(completed.get("pay_event_id", -1)) >= 0
		and int(completed.get("complete_tick", -1)) == int(completed.get("due_tick", -2)),
		"completed player-visible display has an exact paid due-tick receipt")
	var causal_kinds: Array[String] = []
	for raw in Sim.event_log:
		var e: Dictionary = raw
		var kind := String(e.get("type", ""))
		if String(e.get("subject", "")) == CivicProject.PROJECT_ID and kind in [
				"civic_proposal", "civic_vote", "civic_decision", "civic_start", "civic_complete"]:
			causal_kinds.append(kind)
		elif kind == "pay" and String(e.get("note", "")).begins_with("civic_project:"):
			causal_kinds.append("pay")
	ck(causal_kinds == ["civic_proposal", "civic_vote", "civic_vote", "civic_vote",
		"civic_decision", "pay", "civic_start", "civic_complete"]
		and CivicProject.authority_error(Sim.event_log, Sim.mayor_log, Sim.economy) == "",
		"player-visible completion joins one proposal, quorum, approval, payment, start, and completion")
	Sim.start_new(1)
	main._after_jump()
	await _inspect(6482, "", "议事未通过 · 镇库未支付")
	var refused := CivicProject.fold(Sim.event_log)
	ck(bool(refused.get("ok", false)) and String((refused.get("state", {}) as Dictionary).get("status", "")) == "rejected",
		"insufficient council approval leaves the project rejected")
	var project_payments := 0
	for raw in Sim.event_log:
		var e: Dictionary = raw
		if String(e.get("type", "")) == "pay" and String(e.get("note", "")).begins_with("civic_project:"):
			project_payments += 1
	ck(project_payments == 0, "rejected project never charges the town")
	Sim.start_new(7)
	ck(Sim.goto_tick(6481), "unfunded journey reaches a legitimate open proposal")
	var open: Dictionary = Sim.civic_project_state()
	var drain: int = int(Sim.town_coin) - int(open.get("reserve_snapshot", 0)) - int(open.get("cost", 0)) + 1
	ck(String(open.get("status", "")) == "proposed" and drain > 0
		and Sim.transfer("town", "external", drain, "civic_player_fixture_post_proposal_expense"),
		"separate conserved expense leaves the open proposal unfunded")
	Sim.tick()
	await _inspect(6482, "", "镇库拨款未成功 · 尚未施工", false)
	var unfunded: Dictionary = Sim.civic_project_state()
	ck(String(unfunded.get("status", "")) == "unfunded"
		and int(unfunded.get("pay_event_id", -1)) < 0
		and CivicProject.authority_error(Sim.event_log, Sim.mayor_log, Sim.economy) == "",
		"input-visible unfunded refusal has no project payment or forged authority")
	main.queue_free()
	print("civic_player_journey_test: %s (%d fail)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
