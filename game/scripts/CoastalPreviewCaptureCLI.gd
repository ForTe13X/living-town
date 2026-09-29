extends SceneTree
## Render a deterministic still of the coastal neighborhood into a fixed viewport.

const PREVIEW_SCENE := "res://scenes/coastal_neighborhood_preview.tscn"
const CAPTURE_SIZE := Vector2i(1600, 1600)


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var output_path := "res://../docs/media/coastal-s1-floorplan.png" if args.is_empty() else args[0]
	var absolute_path := ProjectSettings.globalize_path(output_path)
	var make_dir_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if make_dir_error != OK and make_dir_error != ERR_ALREADY_EXISTS:
		push_error("COAST_CAPTURE_OUTPUT_DIR: could not create %s" % absolute_path.get_base_dir())
		quit(2)
		return
	var viewport := SubViewport.new()
	viewport.size = CAPTURE_SIZE
	viewport.world_2d = World2D.new()
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)
	var packed_scene := load(PREVIEW_SCENE) as PackedScene
	if packed_scene == null:
		push_error("COAST_CAPTURE_SCENE: could not load %s" % PREVIEW_SCENE)
		quit(2)
		return
	var preview := packed_scene.instantiate()
	preview.set("show_floorplans", true)
	viewport.add_child(preview)
	await process_frame
	preview.call("_fit_camera")
	preview.call("_refresh_title")
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("COAST_CAPTURE_RENDER: fixed viewport returned no image")
		quit(1)
		return
	var save_error := image.save_png(absolute_path)
	if save_error != OK:
		push_error("COAST_CAPTURE_SAVE: image.save_png returned %d" % save_error)
		quit(1)
		return
	print("COAST_CAPTURE_OK size=%dx%d output=%s" % [CAPTURE_SIZE.x, CAPTURE_SIZE.y, absolute_path])
	quit(0)
