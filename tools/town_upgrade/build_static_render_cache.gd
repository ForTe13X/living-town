extends SceneTree
## Root-only actual artifact production; no Main/Sim/gameplay or source writes.
const Model = preload("res://scripts/TownModel3D.gd")
var output: String = ""
var report: Dictionary = {"schema": "living_town.static_cache_actual_build.v1", "status": "RUNNING", "portable_asset_authority": false}

func _initialize() -> void: call_deferred("run")

func finish(ok: bool, message: String = "") -> void:
	report["status"] = "PASS_ACTUAL_FULL_BUILDER_RESOURCE_READBACK" if ok else "FAIL"
	report["error"] = message
	if not output.is_empty():
		var f: FileAccess = FileAccess.open(output.path_join("cache_build_report.json"), FileAccess.WRITE)
		if f != null: f.store_string(JSON.stringify(report, "\t") + "\n"); f.close()
	print("STATIC_CACHE_BUILD ", report.status, " ", message)
	quit(0 if ok else 1)

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var at: int = args.find("--cache-output")
	if at < 0 or at + 1 >= args.size(): finish(false, "--cache-output required"); return
	output = args[at + 1]
	if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): output = ""; finish(false, "Fresh absolute output required"); return
	DirAccess.make_dir_recursive_absolute(output)
	if RenderingServer.get_current_rendering_method() != "mobile" or DisplayServer.get_name() == "headless": finish(false, "Actual graphical Mobile context required"); return
	var viewport: SubViewport = SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var world: Node3D = Node3D.new()
	viewport.add_child(world)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	world.add_child(sun)
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	world.add_child(env)
	var model: Node3D = Model.new()
	model.set_meta("static_cache_build_only", true)
	world.add_child(model)
	var started: int = Time.get_ticks_usec()
	if not model.call("load_town"): finish(false, str(model.get("last_error"))); return
	var helper: RefCounted = model.get("_static_batches")
	if helper == null: finish(false, "Full original batch builder/context failed"); return
	report["model"] = model.call("get_info").duplicate(true)
	var disabled: Dictionary = helper.call("set_enabled", false)
	if not disabled.get("ok", false): finish(false, "Could not restore original source render flags"); return
	var verified: Dictionary = helper.call("validate_sources")
	if not verified.get("ok", false): finish(false, str(verified)); return
	var bound: Dictionary = helper.call("cache_binding", model, 16.0)
	if not bound.get("ok", false): finish(false, str(bound)); return
	var built: Dictionary = helper.call("save_cache", output.path_join("static_render_cache.res"), output.path_join("static_render_cache.json"), bound.binding)
	report["cache"] = built
	report["binding"] = bound.binding
	report["elapsed_usec"] = Time.get_ticks_usec() - started
	report["source_flags_restored"] = not bool(helper.get("enabled"))
	report["full_current_source_validation"] = verified
	if not built.get("ok", false): finish(false, str(built)); return
	var preparation: Dictionary = report.model.get("static_render_batches", {}).get("preparation", {})
	var expected_groups: int = int(preparation.get("groups", -1))
	var expected_members: int = int(preparation.get("source_mesh_proxies", -1))
	if expected_groups <= 0 or expected_members <= 0 or int(built.manifest.groups) != expected_groups or int(built.manifest.source_members) != expected_members or int(verified.get("original_nodes", -1)) != expected_members: finish(false, "Saved inventory differs from the actual full builder/source validation"); return
	report["required_release_files"] = ["static_render_cache.res", "static_render_cache.json"]
	report["release_inclusion_pending"] = true
	report["engine_specific_source_project_cache"] = true
	report["startup_speedup_or_art_acceptance"] = false
	finish(true)
