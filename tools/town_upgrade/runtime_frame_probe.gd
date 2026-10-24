extends SceneTree
## Real Main, real time, no MovieWriter or simulation state writes.
class CameraKeeper extends Node:
	var main: Node
	var view: Node
	var probe: Node
	var shot: Dictionary = {}
	func _process(_delta: float) -> void:
		if shot.is_empty(): return
		probe.set("mode",0)
		probe.set("follow_id","")
		probe.set("demo_cam",false)
		if str(probe.get("active_space"))!=shot["space"] or str(probe.get("active_floor"))!=shot["floor"]:
			probe.call("set_space",shot["space"],shot["floor"],main.get("_sg").bounds_px(shot["space"]))
		var cam: Camera2D = probe.get("cam") as Camera2D
		cam.position=shot["center"]
		cam.zoom=Vector2.ONE*maxf(0.025,float(view.get("viewport_3d").size.y)*(1.7/48.0)/float(shot["size_m"]))
		view.call("sync_camera")

var sim: Node
var main: Node
var view: Node
var output: String
var report: Dictionary = {"schema":"living_town.normal_runtime_frame_probe.v1","status":"RUNNING","movie_writer":false,"phases":[],"ray_samples":[],"checks":[]}

func _initialize() -> void: call_deferred("run_probe")
func wait_frames(n: int) -> void:
	for i: int in range(n): await process_frame
func key(code: Key) -> void:
	for pressed: bool in [true,false]:
		var event:=InputEventKey.new()
		event.keycode=code
		event.physical_keycode=code
		event.pressed=pressed
		root.push_input(event,true)
		await wait_frames(1)
func files() -> Dictionary:
	var result: Dictionary={}
	for path: String in ["user://settings.cfg","user://quicksave.dat","user://town3d_quicksave.dat"]:
		result[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "ABSENT"
	return result
func save_report() -> void:
	var stream:=FileAccess.open(output.path_join("frame_report.json"),FileAccess.WRITE)
	stream.store_string(JSON.stringify(report,"\t")+"\n")
	stream.close()
func statistics(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var sorted:=values.duplicate()
	sorted.sort()
	var total: float=0
	for value: float in values: total+=value
	return {"samples":values.size(),"mean":total/values.size(),"p50":sorted[int((sorted.size()-1)*0.5)],"p95":sorted[int((sorted.size()-1)*0.95)],"p99":sorted[int((sorted.size()-1)*0.99)],"max":sorted[-1]}
func phase(label: String,code: Key,seconds: float) -> void:
	await key(code)
	var controlled: Dictionary=sim.call("controlled")
	var actual_plane: String=str(controlled.get("space","town"))+"/"+str(controlled.get("floor","outdoor"))
	if str(main.get("_life").get("pid"))!=str(sim.get("controlled_id")) or actual_plane!=str(view.get("_plane_key_3d")):
		report["status"]="FAIL_CONTROLLED_CAMERA_PLANE_MISMATCH"
		save_report()
		quit(1)
		return
	# Two seconds of ordinary rendered frames; no fixed timestep.
	var warmup: int=Time.get_ticks_usec()
	while Time.get_ticks_usec()-warmup<2000000: await process_frame
	var intervals: Array[float]=[]
	var cpu: Array[float]=[]
	var physics: Array[float]=[]
	var calls: Array[float]=[]
	var primitives: Array[float]=[]
	var ticks_per_frame: Array[float]=[]
	var start_tick: int=int(sim.get("tick_no"))
	var previous_tick: int=start_tick
	var started: int=Time.get_ticks_usec()
	var previous: int=started
	print("FRAME_PROBE_START ",label," tick=",start_tick," speed=",sim.get("speed"))
	while Time.get_ticks_usec()-started<int(seconds*1000000):
		await process_frame
		var now: int=Time.get_ticks_usec()
		var frame_us: int=now-previous
		intervals.append(float(frame_us)/1000.0)
		previous=now
		cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		ticks_per_frame.append(float(int(sim.get("tick_no"))-previous_tick))
		previous_tick=int(sim.get("tick_no"))
		if frame_us>5000000: break
	var elapsed: float=float(Time.get_ticks_usec()-started)/1000000.0
	var data: Dictionary={"name":label,"wall_seconds":elapsed,"frame_count":intervals.size(),"mean_fps":float(intervals.size())/elapsed,"frame_ms":statistics(intervals),"held_process_peak_monitor_ms":statistics(cpu),"held_physics_peak_monitor_ms":statistics(physics),"monitor_caveat":"Godot publishes a held preceding approximately one-second maximum; these are not per-frame CPU timing distributions.","draw_calls":statistics(calls),"render_primitives":statistics(primitives),"ticks_per_frame":statistics(ticks_per_frame),"start_tick":start_tick,"end_tick":sim.get("tick_no"),"speed":sim.get("speed"),"running":sim.get("running"),"accumulator":sim.get("_accum"),"controlled_id":sim.get("controlled_id"),"controlled_plane":actual_plane,"controlled_cell":str(controlled.get("pos")),"life_pid":main.get("_life").get("pid"),"camera_size_m":view.get("camera_3d").size,"camera_position":str(view.get("camera_3d").global_position),"visible_plane":view.get("_plane_key_3d"),"viewport_size":str(view.get("viewport_3d").size)}
	report["phases"].append(data)
	print("FRAME_PROBE_DONE ",JSON.stringify(data))
	save_report()
func time_ray(label: String) -> void:
	await key(KEY_0)
	var id: String=str(sim.get("controlled_id"))
	var item: Dictionary=view.get("_actors_3d").get(id,{})
	if item.is_empty(): return
	var actor: Node3D=item["node"] as Node3D
	var camera: Camera3D=view.get("camera_3d") as Camera3D
	var body: Vector3=actor.global_position+Vector3.UP*float(item.get("height_m",1.7))*0.55
	var origin: Vector3=camera.project_ray_origin(camera.unproject_position(body))
	var distance: float=origin.distance_to(body)
	var samples: Array[float]=[]
	var hits: Array=[]
	for i: int in range(5):
		var start: int=Time.get_ticks_usec()
		var hit: Dictionary=view.get("town_model_3d").call("raycast_geometry",origin,(body-origin).normalized(),maxf(0,distance-0.12),"all")
		samples.append(float(Time.get_ticks_usec()-start)/1000.0)
		hits.append({"node":str(hit["node"].get_path()),"distance":hit["distance"]} if not hit.is_empty() else {})
	report["ray_samples"].append({"name":label,"milliseconds":samples,"hits":hits,"origin":str(origin),"body":str(body),"scope":"all","mesh_candidates_total":view.get("town_model_3d").get("meshes").size()})
	save_report()
func click(point: Vector2) -> void:
	for pressed: bool in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT
		event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position=point
		event.global_position=point
		event.pressed=pressed
		root.push_input(event,true)
		await wait_frames(2)
func walk_portal(ident: String) -> bool:
	var life: Node=main.get("_life")
	var actor: Dictionary=sim.call("controlled")
	var endpoint: Dictionary={}
	for portal: Dictionary in sim.get("_portals"):
		if str(portal.get("id",""))==ident:
			for side: String in ["from","to"]:
				var address: Dictionary=portal.get(side,{})
				if address.get("space")==actor.get("space") and address.get("floor")==actor.get("floor"): endpoint=address
	if endpoint.is_empty(): return false
	var previous: String=str(actor.get("space"))+"/"+str(actor.get("floor"))
	var until: int=Time.get_ticks_usec()+60000000
	for attempt: int in range(3):
		var cell: Vector2=Vector2(float(endpoint["pos"][0]),float(endpoint["pos"][1]))*48+Vector2(24,24)
		await click(view.call("canonical_to_screen",cell))
		if bool(life.get("_modal_open")):
			if life.get("_modal_entry").get("id")==ident: await key(KEY_1)
			else: await key(KEY_ESCAPE)
		while bool(life.get("_walk_on")) and Time.get_ticks_usec()<until: await process_frame
		await wait_frames(8)
		actor=sim.call("controlled")
		if str(actor.get("space"))+"/"+str(actor.get("floor"))!=previous:
			report["checks"].append({"name":"actual_input_portal_"+ident,"passed":true,"destination":str(actor.get("space"))+"/"+str(actor.get("floor")),"tick":sim.get("tick_no")})
			return true
		if Time.get_ticks_usec()>=until: break
	return false
func run_probe() -> void:
	var args:=OS.get_cmdline_user_args()
	var at: int=args.find("--frame-probe-dir")
	if at<0 or at+1>=args.size(): quit(2); return
	output=args[at+1]
	if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var source_snapshot:=FileAccess.open(output.path_join("probe_source.gd"),FileAccess.WRITE)
	source_snapshot.store_string(FileAccess.get_file_as_string(get_script().resource_path))
	source_snapshot.close()
	report["user_files_before"]=files()
	report["arguments"]=Array(args)
	report["probe_sha256"]=FileAccess.get_sha256(get_script().resource_path)
	report["source_hashes"]={}
	for path: String in ["res://scripts/Main.gd","res://scripts/Sim.gd","res://scripts/LifeMode.gd","res://scripts/WorldView3D.gd","res://scripts/TownModel3D.gd","res://data/town3d/profile.json","res://assets/town3d/stage_manifest.json"]:
		report["source_hashes"][path]=FileAccess.get_sha256(path)
	report["vsync_original"]=DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	report["measurement_settings"]={"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"renderer":RenderingServer.get_current_rendering_method(),"display":DisplayServer.get_name(),"launcher_used":false,"normal_processing_preserved":true,"camera_override_only":true}
	sim=root.get_node("Sim")
	main=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene=main
	await wait_frames(20)
	DisplayServer.window_set_size(Vector2i(1280,768))
	view=main.get("_view")
	main.get("_life").call("start_life","aria")
	await wait_frames(2)
	await key(KEY_0)
	report["bridge"]=view.call("get_bridge_info")
	report["actor_count"]=sim.get("agents").size()
	var keeper:=CameraKeeper.new()
	keeper.main=main
	keeper.view=view
	keeper.probe=main.get("_probe")
	keeper.process_priority=49
	root.add_child(keeper)
	var plane: Dictionary=view.get("projection_3d").get("planes",{}).get("cafe/2f",{})
	var size: Array=plane.get("grid_size",[40,36])
	var shots: Array[Dictionary]=[{"name":"home","space":"cafe","floor":"2f","center":Vector2(float(size[0]),float(size[1]))*24,"size_m":13.0},{"name":"town","space":"town","floor":"outdoor","center":view.call("world_to_canonical",Vector3(4,0,5),"town","outdoor"),"size_m":75.0}]
	for shot: Dictionary in shots:
		if shot["name"]=="home" and "--outdoor-only" in args: continue
		if shot["space"]=="town":
			await key(KEY_0)
			var selected: String=""
			for actor: Dictionary in sim.get("agents"):
				if not bool(actor.get("is_player",false)) and not bool(actor.get("affiliate",false)) and str(actor.get("space","town"))=="town" and str(actor.get("floor","outdoor"))=="outdoor":
					selected=str(actor["id"])
					shot["center"]=Vector2(actor["pos"])*48+Vector2(24,24)
					break
			if selected.is_empty():
				# Keep the actual resident and walk through the same screen input
				# stairs/door as the successful gameplay preview. No address writes.
				keeper.shot={}
				await key(KEY_1)
				await wait_frames(8)
				if not await walk_portal("p_cafe_stairs") or not await walk_portal("p_cafe_door"):
					report["status"]="FAIL_LEGAL_OUTDOOR_APPROACH"
					save_report()
					quit(1)
					return
				selected=str(sim.get("controlled_id"))
				shot["center"]=Vector2(sim.call("controlled")["pos"])*48+Vector2(24,24)
			main.get("_life").call("start_life",selected)
			await key(KEY_0)
			var possessed: bool=str(sim.get("controlled_id"))==selected and str(main.get("_life").get("pid"))==selected
			report["outdoor_resident_selection"]={"id":selected,"public_api":"LifeMode.start_life","actor_relocated":false,"camera_center":str(shot["center"]),"actual_controlled_id":sim.get("controlled_id"),"actual_life_pid":main.get("_life").get("pid"),"possession_succeeded":possessed}
			if not possessed:
				report["status"]="FAIL_PUBLIC_OUTDOOR_POSSESSION"
				save_report()
				quit(1)
				return
		keeper.shot=shot
		await wait_frames(3)
		await phase(shot["name"]+"_paused",KEY_0,12.0)
		await time_ray(shot["name"])
		await phase(shot["name"]+"_1x",KEY_1,12.0)
		await phase(shot["name"]+"_4x",KEY_3,8.0)
	await key(KEY_0)
	report["user_files_after"]=files()
	report["user_files_unchanged"]=report["user_files_before"]==report["user_files_after"]
	report["status"]="DIAGNOSTIC_COMPLETE" if report["user_files_unchanged"] else "FAIL"
	save_report()
	print("NORMAL_FRAME_PROBE: ",report["status"])
	quit(0 if report["user_files_unchanged"] else 1)
