extends Node
## Regression: exterior zoom must not remove roofs; sprites must fit authored lots.
## Optional --proof-out <absolute directory> writes HUD-free rendered evidence.
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	var main = preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	Sim.running = false
	Sim.auto_run = false
	await get_tree().process_frame
	var view = main._view
	view._ensure_houses()
	for asset in ["paving", "asphalt", "meadow", "tree", "garden", "passage", "block", "market", "civic", "terrace_south", "terrace_north", "library", "bathhouse_north", "workshop_north", "flowerbeds", "shop"]:
		var tex: Texture2D = view._coastal_plan.texture(asset)
		check(tex != null and tex.get_width() >= 256, "High-resolution PixelLab asset failed: " + asset)
	var interiors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/interiors.json"))
	for sid in ["cafe", "library", "wash", "work"]:
		var grid: Dictionary = Sim._grid_for(sid, "1f")
		for cut: Array in interiors[sid]["1f"].get("cutouts", []):
			for y in range(int(cut[1]), int(cut[1] + cut[3])):
				for x in range(int(cut[0]), int(cut[0] + cut[2])):
					check(grid.blocked.has(y * int(grid.w) + x), "Interior recess must block movement: " + sid)
	check(view._roof_areas().size() == 7, "All seven functional buildings have roof coverage")
	for zoom in [0.30, 0.73, 0.75, 1.0, 1.5]:
		view._zoom = zoom
		check(view._roof_alpha() == 1.0, "Exterior roofs disappear at zoom %s" % zoom)
	var lots: Array = view._lots_data().get("lots", [])
	for lot in lots:
		if String(lot.get("architecture", "")) == "": continue
		var footprint := Rect2(float(lot.x)*48, float(lot.y)*48, float(lot.w)*48, float(lot.h)*48)
		var facing := String(lot.get("facing", "south"))
		var geo: Dictionary = view._coastal_plan.building_geometry(String(lot.get("coastal_asset", "block")), footprint, facing)
		check(not geo.is_empty(), "Blueprint lot has drawable geometry")
		if geo.is_empty(): continue
		check(footprint.grow(0.1).encloses(geo.bounds), "Visible building silhouette spills across its lot")
		check(not bool(lot.get("flip", false)), "Building orientation must not mirror sunlight / lettering")
		if String(lot.get("coastal_asset", "")).begins_with("terrace_"):
			check(String(geo.asset) == "terrace_" + facing, "Front/rear terrace art must follow blueprint direction")
		if facing == "north": check(absf(geo.bounds.position.y-footprint.position.y)<0.1, "North frontage attaches to north edge")
		elif facing == "south": check(absf(geo.bounds.end.y-footprint.end.y)<0.1, "South frontage attaches to south edge")
	for asset in ["market", "block", "library", "bathhouse_north", "workshop_north", "shop"]:
		var geo: Dictionary = view._coastal_plan.building_geometry(asset, Rect2(0,0,432,336), "south")
		var src: Rect2 = view._coastal_plan.region(asset)
		var pts: PackedVector2Array = geo.points
		var ex := (pts[1]-pts[0])/src.size.x
		var ey := (pts[3]-pts[0])/src.size.y
		check(absf((ex + ey * float(geo.slope)).y)<0.001, "Frontage is parallel to street: " + asset)
		check(absf(ey.x)<0.001 and ey.y>0, "Walls remain upright: " + asset)
	var expected := 0
	for lot in lots:
		expected += int(lot.get("bays", 1))
	check(view._houses.size() == expected, "A lot asset failed to load")
	for house in view._houses:
		if String(house.get("architecture", "")) != "":
			var footprint: Rect2 = house.lot_rect
			check(footprint.size.x > 0 and footprint.size.y > 0, "Coastal building must have a positive footprint")
		for lot in lots:
			if int(lot.x) != int(house.x) or int(lot.y) != int(house.y): continue
			var r: Rect2 = house.rect
			check(r.position.x >= float(lot.x) * 48.0 - 1.0 and r.end.x <= float(lot.x + lot.w) * 48.0 + 1.0,
				"Sprite spills outside its lot: %s" % house.sprite)
			check(r.size.y <= (float(lot.h) + (0.6 if lot.get("landmark", false) else 0.08)) * 48.0 + 0.1,
				"Building exceeds block height budget: %s" % house.sprite)
	var output := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--proof-out" and i + 1 < args.size(): output = args[i + 1]
	if output != "" and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(output)
		for child in main.get_children():
			if child is CanvasLayer: child.visible = false
		for shot in [["town", 32.0, 24.0, 0.31], ["market", 31.5, 17.0, 0.78], ["coast", 51.0, 38.5, 0.88], ["passage", 6.5, 25.0, 1.15], ["north_frontages", 24.0, 5.0, 0.70], ["south_frontages", 21.0, 39.5, 0.80]]:
			main._probe.cam.position = Vector2(shot[1], shot[2]) * 48.0
			main._probe.cam.zoom = Vector2.ONE * float(shot[3])
			view._redraw_all()
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			check(get_viewport().get_texture().get_image().save_png(output.path_join(String(shot[0]) + ".png")) == OK, "Capture failed")
		for sid in ["cafe", "library", "wash"]:
			var bounds: Rect2 = main._sg.bounds_px(sid)
			main._probe.set_space(sid, "1f", bounds)
			main._probe.cam.limit_left = -100000
			main._probe.cam.limit_top = -100000
			main._probe.cam.limit_right = 100000
			main._probe.cam.limit_bottom = 100000
			main._probe.cam.position = bounds.get_center()
			main._probe.cam.zoom = Vector2.ONE * minf(1.7, 620.0 / (bounds.size.y + 60.0))
			view._redraw_all()
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			check(get_viewport().get_texture().get_image().save_png(output.path_join("interior_" + sid + ".png")) == OK, "Interior capture failed")
	print("EXTERIOR_VISUAL_TEST: %d failures; %d facade instances, 7 roofed buildings" % [failures, expected])
	get_tree().quit(0 if failures == 0 else 1)
