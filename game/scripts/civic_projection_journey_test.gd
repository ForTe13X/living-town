extends Node
## LT-18: exercise the existing Main/Probe/WorldView seams at a completed project tick.

const MainScene = preload("res://scenes/Main.tscn")
const CivicPresentation = preload("res://scripts/CivicPresentation.gd")
const Inv = preload("res://bench/Invariants.gd")

var failures := 0

func ck(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
	print(("  OK   " if ok else "  FAIL ") + message)

func _ready() -> void:
	call_deferred("_run")

func _evidence_dir() -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--evidence-dir":
			return args[i + 1]
	return ""

func _capture(name: String) -> void:
	var dir := _evidence_dir()
	if dir == "":
		return
	DirAccess.make_dir_recursive_absolute(dir)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	ck(image != null and image.get_width() == 1280 and image.get_height() == 768
		and image.save_png(dir.path_join(name + ".png")) == OK,
		"%s framebuffer capture writes at native resolution" % name)

func _capture_without_civic(view, name: String) -> void:
	var digest := Inv.digest(Sim)
	var event_digest := Sim.event_digest
	view.civic_projection_enabled = false
	view.queue_redraw()
	for i in range(3):
		await get_tree().process_frame
	await _capture(name)
	ck(Inv.digest(Sim) == digest and Sim.event_digest == event_digest,
		"disabling only the civic renderer leaves canonical state unchanged at %s" % name)
	view.civic_projection_enabled = true
	view.queue_redraw()

func _run() -> void:
	var main = MainScene.instantiate()
	add_child(main)
	Sim.auto_run = false
	Sim.running = false
	var probe = main.get("_probe")
	var view = main.get("_view")
	ck(probe != null and view != null, "Main owns the live Probe and WorldView")
	if probe == null or view == null:
		get_tree().quit(1)
		return
	var state: Dictionary = Sim.civic_project_state()
	var receipt := CivicPresentation.receipt(state)
	var digest := Inv.digest(Sim)
	var event_digest := Sim.event_digest
	ck(Sim.tick_no == 7202 and CivicPresentation.phase(state) == "complete" and receipt.contains("收据"),
		"live Main begins at a receipted completion")
	probe.cam.position = Vector2(32 * 48, 24 * 48)
	probe.cam.zoom = Vector2(1.25, 1.25)
	view.queue_redraw()
	for i in range(3):
		await get_tree().process_frame
	await _capture("town-before")
	await _capture_without_civic(view, "town-complete-render-off")
	var vis: Rect2 = view.get("_vis")
	ck(vis.intersects(Rect2(29 * 48, 22 * 48, 48, 48))
		and vis.intersects(Rect2(35 * 48, 22 * 48, 48, 48)),
		"both completed display cells are inside the live camera view")
	main._demo_enter("cafe", "1f")
	main._frame_active_space(false)
	view.queue_redraw()
	for i in range(3):
		await get_tree().process_frame
	await _capture("cafe-interior")
	ck(String(probe.active_space) == "cafe" and CivicPresentation.phase(Sim.civic_project_state()) == "complete",
		"entering the cafe hides the town plane without changing project authority")
	main._demo_enter("town", "outdoor")
	probe.cam.position = Vector2(32 * 48, 24 * 48)
	probe.cam.zoom = Vector2(1.25, 1.25)
	view.queue_redraw()
	for i in range(3):
		await get_tree().process_frame
	await _capture("town-return")
	vis = view.get("_vis")
	ck(String(probe.active_space) == "town" and vis.intersects(Rect2(29 * 48, 22 * 48, 48, 48))
		and vis.intersects(Rect2(35 * 48, 22 * 48, 48, 48))
		and CivicPresentation.phase(Sim.civic_project_state()) == "complete",
		"returning to the town projects the completed displays again")
	ck(Sim.tick_no == 7202 and Inv.digest(Sim) == digest and Sim.event_digest == event_digest,
		"camera and space transitions do not change canonical simulation")
	var saved_selection := String(main.get("_selected_id"))
	var save_path := "user://civic_projection_journey.dat"
	ck(Sim.save_game(save_path, {"fixture": "civic_projection_journey"}),
		"completed town frame saves through the normal save API")
	Sim.start_new(2)
	ck(CivicPresentation.phase(Sim.civic_project_state()) == "",
		"a different world clears the completed display")
	ck(Sim.load_game(save_path), "completed project reloads through the normal load API")
	main._after_load()
	main.set("_selected_id", saved_selection)
	main._update_obs()
	Sim.auto_run = false
	Sim.running = false
	probe.cam.position = Vector2(32 * 48, 24 * 48)
	probe.cam.zoom = Vector2(1.25, 1.25)
	view.queue_redraw()
	for i in range(3):
		await get_tree().process_frame
	await _capture("town-resume")
	vis = view.get("_vis")
	ck(CivicPresentation.phase(Sim.civic_project_state()) == "complete"
		and vis.intersects(Rect2(29 * 48, 22 * 48, 48, 48))
		and vis.intersects(Rect2(35 * 48, 22 * 48, 48, 48))
		and Sim.tick_no == 7202 and Inv.digest(Sim) == digest and Sim.event_digest == event_digest,
		"save/load restores project authority and both visible plaza sites")
	ck(Sim.goto_tick(6481), "timeline scrub reaches the open proposal")
	main._after_jump()
	view.queue_redraw()
	for i in range(3):
		await get_tree().process_frame
	await _capture("town-planned")
	await _capture_without_civic(view, "town-planned-render-off")
	ck(CivicPresentation.phase(Sim.civic_project_state()) == "planned"
		and CivicPresentation.receipt(Sim.civic_project_state()).contains("尚未动用镇库"),
		"timeline scrub projects the unpaid planned phase in the live town view")
	ck(Sim.goto_tick(6482), "timeline scrub reaches the paid construction start")
	main._after_jump()
	view.queue_redraw()
	for i in range(3):
		await get_tree().process_frame
	await _capture("town-underway")
	await _capture_without_civic(view, "town-underway-render-off")
	ck(CivicPresentation.phase(Sim.civic_project_state()) == "underway"
		and CivicPresentation.receipt(Sim.civic_project_state()).contains("镇库已支付"),
		"timeline scrub projects the paid construction phase in the live town view")
	ck(Sim.goto_tick(6480), "timeline scrub reaches the tick before the civic proposal")
	main._after_jump()
	view.queue_redraw()
	for i in range(3):
		await get_tree().process_frame
	await _capture("town-preproposal")
	ck(CivicPresentation.phase(Sim.civic_project_state()) == "",
		"timeline scrub removes the unbuilt project from the live town view")
	ck(Sim.goto_tick(7202), "timeline scrub returns to the completed tick")
	main._after_jump()
	view.queue_redraw()
	for i in range(3):
		await get_tree().process_frame
	await _capture("town-replayed")
	print("LT18 replay result phase=%s tick=%d digest=%d expected_digest=%d event_digest=%d expected_event_digest=%d" % [
		CivicPresentation.phase(Sim.civic_project_state()), Sim.tick_no, Inv.digest(Sim), digest,
		Sim.event_digest, event_digest])
	ck(CivicPresentation.phase(Sim.civic_project_state()) == "complete"
		and Sim.tick_no == 7202 and Inv.digest(Sim) == digest and Sim.event_digest == event_digest,
		"timeline replay restores the exact completed town authority")
	main.queue_free()
	print("civic_projection_journey_test: %s (%d fail)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
