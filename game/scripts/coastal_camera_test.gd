extends Node
## Camera tracks interpolated characters and follows plane transitions without
## affecting simulation. Optional --camera-proof-out records a moving sequence.
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	var main = preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	Sim.running = false
	Sim.auto_run = false
	var probe = main._probe
	probe.set_process(false)
	main._view.set_process(false)
	var ag: Dictionary = Sim.get_agent("ben")
	var original := ag.duplicate(true)
	ag.space = "town"; ag.floor = "outdoor"; ag.pos = Vector2i(32, 23)
	main._view._render_pos["ben"] = Vector2(1560, 1128)
	probe.follow("ben")
	probe.cam.position = Vector2(1300, 1100)
	for i in 120: probe._process(1.0 / 60.0)
	check(probe.cam.position.distance_to(Vector2(1560, 1116)) < 1.0, "Follow converges to rendered character, not grid ticks")
	var start: Vector2 = probe.cam.position
	main._view._render_pos["ben"] = Vector2(1656, 1128)
	probe._process(1.0 / 60.0)
	check(probe.cam.position.x > start.x and probe.cam.position.x < 1656, "Moving target eases without snapping")
	var once: Vector2 = probe.cam.position
	probe.cam.position = start
	probe._process(1.0 / 120.0); probe._process(1.0 / 120.0)
	check(probe.cam.position.distance_to(once) < 0.01, "Follow easing is frame-rate independent")
	ag.space = "cafe"; ag.floor = "1f"; ag.pos = Vector2i(3, 3)
	main._view._render_pos["ben"] = Vector2(168, 168)
	probe._process(1.0 / 60.0)
	check(probe.active_space == "cafe" and probe.active_floor == "1f", "Follow enters the character's interior plane")
	check(probe.cam.limit_left < -1000, "Small interiors allow character-centred framing")
	ag.space = "town"; ag.floor = "outdoor"; ag.pos = Vector2i(32, 23)
	main._view._render_pos["ben"] = Vector2(1560, 1128)
	probe._process(1.0 / 60.0)
	check(probe.active_space == "town" and probe.cam.limit_left == -probe.CAM_MARGIN, "Returning outdoors restores map limits")
	probe.unfollow()
	var stopped: Vector2 = probe.cam.position
	main._view._render_pos["ben"] = Vector2(2000, 1000)
	probe._process(1.0)
	check(probe.cam.position == stopped, "Unfollow leaves the camera still")
	# Life mode uses the same visual position, with a bounded look-ahead.
	var life = preload("res://scripts/LifeMode.gd").new()
	life.main = main
	life._camera_last_target = Vector2(1560, 1128)
	life._zoom = 1.35
	main._view._render_pos["ben"] = Vector2(1560, 1128)
	probe.cam.position = Vector2(1400, 1100)
	for i in 120: life._camera(1.0 / 60.0, ag)
	check(probe.cam.position.distance_to(Vector2(1560, 1116)) < 1, "Possessed character stays framed")
	main._view._render_pos["ben"] = Vector2(1700, 1128)
	life._camera(1.0 / 60.0, ag)
	check(life._camera_look.length() <= 24.0, "Life camera look-ahead remains bounded")
	life.free()
	var output := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--camera-proof-out" and i + 1 < args.size(): output = args[i + 1]
	if output != "" and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(output)
		for child in main.get_children():
			if child is CanvasLayer: child.visible = false
		ag.space = "town"; ag.floor = "outdoor"; ag.pos = Vector2i(32, 13)
		ag.option = null; ag.talking = 0
		Sim.possess("ben")
		main._selected_id = "ben"
		main._view._render_pos["ben"] = Vector2(1560, 648)
		main._view.set_process(true)
		probe.follow("ben")
		probe.cam.position = Vector2(1560, 636)
		probe.set_process(true)
		var first_camera: Vector2 = probe.cam.position
		for frame in 40:
			if frame % 4 == 0:
				var path: Array = Sim._astar_path(Sim._grid_for("town", "outdoor"), ag.pos, Vector2i(32, 25))
				check(path.size() > 1, "Civic spine has a legal route past market furniture")
				if path.size() > 1:
					check(Sim.life_move(Vector2i(path[1]) - Vector2i(ag.pos)) == "", "Character walks through civic spine")
			await get_tree().create_timer(0.10).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(output.path_join("walk_%03d.png" % frame))
		check(probe.cam.position.distance_to(first_camera) > 300, "Camera travels with the walking character")
	ag.clear(); ag.merge(original)
	print("COASTAL_CAMERA_TEST: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
