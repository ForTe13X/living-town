extends Node
## Reproducible rendered tour. Movement and doors use the player APIs; observer
## chapters are explicitly labelled. Frames stay outside the checkout.
var main
var caption: Label
var output := ""
var frame := 0
var chapters: Array = []
var failures := 0

func chapter(title: String) -> void:
	caption.text = title
	chapters.append({"frame": frame, "seconds": frame / 10.0, "title": title})

func capture(count: int) -> void:
	for i in count:
		await get_tree().create_timer(0.1).timeout
		await RenderingServer.frame_post_draw
		var err := get_viewport().get_texture().get_image().save_png(output.path_join("frame_%05d.png" % frame))
		assert(err == OK)
		frame += 1

func walk(dest: Vector2i) -> void:
	for i in 180:
		var ag: Dictionary = Sim.controlled()
		if Vector2i(ag.pos) == dest: return
		var result: String = Sim.life_step_toward(dest)
		if result == "arrived": return
		if result != "":
			failures += 1
			push_error("Tour route blocked: %s -> %s" % [ag.pos, dest])
			return
		await capture(2)
	if Vector2i(Sim.controlled().pos) != dest: failures += 1

func door(pos: Vector2i) -> void:
	await walk(pos)
	var receipt: Dictionary = Sim.life_portal(pos)
	if not bool(receipt.get("ok", false)):
		failures += 1
		push_error("Tour portal failed: " + str(receipt))
	await capture(15)

func inspect_space(sid: String, floor_id := "1f") -> void:
	var bounds: Rect2 = main._sg.bounds_px(sid)
	main._probe.set_space(sid, floor_id, bounds)
	main._probe.cam.limit_left = -100000
	main._probe.cam.limit_top = -100000
	main._probe.cam.limit_right = 100000
	main._probe.cam.limit_bottom = 100000
	main._probe.cam.position = bounds.get_center()
	main._probe.cam.zoom = Vector2.ONE * minf(1.4, 560.0 / (bounds.size.y + 60))
	main._view._redraw_all()

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--tour-out" and i + 1 < args.size(): output = args[i + 1]
	assert(output != "" and DisplayServer.get_name() != "headless")
	DirAccess.make_dir_recursive_absolute(output)
	main = preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	add_child(overlay)
	caption = Label.new()
	caption.position = Vector2(24, 42)
	caption.add_theme_font_size_override("font_size", 17)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 8)
	overlay.add_child(caption)
	# Advance through the actual simulation to morning; no world-state shortcut.
	for i in 600: Sim.tick()
	chapter("01 / SCRIPTED PLAY · Ben · movement and character-follow camera")
	main._life.start_life("ben")
	await capture(25)
	# Start from the resident's actual spawn, without relocating the character.
	var ag: Dictionary = Sim.controlled()
	if String(ag.space) != "town":
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/spaces.json"))
		for portal in data.portals:
			if String(portal.to.space) == String(ag.space) and String(portal.from.space) == "town":
				await door(Vector2i(portal.to.pos[0], portal.to.pos[1]))
				break
	await walk(Vector2i(32, 23))
	chapter("02 / PLAY · market street → cafe · legal entrance and interaction menu")
	await door(Vector2i(41, 19))
	main._life.debug_open_menu()
	await capture(35)
	main._life._close_modal()
	await door(Vector2i(4, 5))
	chapter("03 / PLAY · terrace passage → residence · public staircase")
	await door(Vector2i(14, 18))
	await door(Vector2i(9, 6))
	await capture(25)
	await door(Vector2i(9, 6))
	await door(Vector2i(5, 7))
	chapter("04 / PLAY · relationships and personal needs")
	main._life._toggle_rel()
	await capture(35)
	main._life._toggle_rel()
	main._life._leave_life()
	main._life._hud.visible = false
	main._life._set_main_chrome(true)
	main._probe.unfollow()
	for sid in ["library", "wash", "work", "hotel", "port_warehouse", "mairie"]:
		chapter("05 / OBSERVER INSPECTION · " + sid + " · room layout and furniture")
		inspect_space(sid)
		await capture(30)
	chapter("06 / OBSERVER · civic policies and impact receipts")
	main._open_civic_panel()
	await capture(45)
	main._close_civic_panel()
	chapter("07 / OBSERVER · cooperative bank and impact receipts")
	main._open_bank_panel()
	await capture(45)
	main._close_bank_panel()
	chapter("08 / OBSERVER · persistent story and transaction ledger")
	main._toggle_story()
	await capture(30)
	main._close_story()
	main._toggle_ledger()
	await capture(30)
	main._close_ledger()
	main._probe.set_space("town", "outdoor", main._sg.bounds_px("town"))
	for shot in [["garden belts and street-facing terraces", 24, 7, 0.75], ["coastal promenade", 51, 38, 0.85], ["town overview", 32, 24, 0.30]]:
		chapter("09 / OBSERVER · " + String(shot[0]))
		main._probe.cam.position = Vector2(shot[1], shot[2]) * 48
		main._probe.cam.zoom = Vector2.ONE * float(shot[3])
		main._view._redraw_all()
		await capture(40)
	var file := FileAccess.open(output.path_join("chapters.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"fps": 10, "frames": frame, "failures": failures, "chapters": chapters}, "  "))
	print("GAMEPLAY_TOUR: %d failures; %d captured frames" % [failures, frame])
	get_tree().quit(0 if failures == 0 else 1)
