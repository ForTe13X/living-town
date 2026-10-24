extends Node
## Run with --headless. This tests the real authored Sim topology, not a viewer.
const SimScript = preload("res://scripts/Sim.gd")
const ProfileScript = preload("res://scripts/TownWorldProfile.gd")
const LifeScript = preload("res://scripts/LifeMode.gd")
const Inv = preload("res://bench/Invariants.gd")
var checks: Array = []
var failures: int = 0
var report_path: String = "res://data/town3d/upgrade_runtime_report.json"

func ck(label: String, passed: bool, details: Variant = null) -> void:
	checks.append({"name": label, "passed": passed, "details": details})
	if not passed:
		failures += 1
	print(("PASS " if passed else "FAIL ") + "UPGRADED GAME " + label)

func read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func fresh(use_global: bool = false) -> Node:
	var sim: Node = Sim if use_global else SimScript.new()
	sim.auto_run = false
	sim.running = false
	if not use_global:
		add_child(sim)
	var profile: RefCounted = ProfileScript.new()
	ck("exact_profile_and_visual_asset_set_load", profile.load_profile(), profile.error_message)
	ck("authored_profile_installed_before_world_start", sim.install_world_profile(profile))
	sim.start_new(7)
	return sim

func _ready() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(arguments.size()):
		if arguments[index].begins_with("--report="):
			report_path = arguments[index].substr(9)
		elif arguments[index] == "--report" and index+1 < arguments.size():
			report_path = arguments[index+1]
	if report_path != "res://data/town3d/upgrade_runtime_report.json" and not report_path.is_absolute_path():
		print("town_upgrade_integration_test: FAIL --report must be absolute")
		get_tree().quit(1)
		return
	var sim: Node = fresh(true)
	var projection: Dictionary = read_json("res://data/town3d/projection.json")
	var stage: Dictionary = read_json("res://assets/town3d/stage_manifest.json")
	var planes: Dictionary = projection.get("planes", {})
	var buildings: Dictionary = projection.get("building_spaces", {})
	ck("all151physical_buildings_have_real_game_spaces", buildings.size() == 151, buildings.size())
	ck("all_authored_floor_planes_compiled", planes.size() == int(stage.get("inventory", {}).get("floor_count", 0)) + 1, planes.size())
	ck("expanded_profile_exactly_matches_visual_chunk_set", stage.get("schema", "") == "living_town.game_stage.v2" and projection.get("source_asset_set_sha256", "") == stage.get("source_asset_set_sha256", ""))
	var entrances: Dictionary = {}
	var invalid: Array = []
	for portal: Dictionary in sim._portals:
		if portal["from"].get("space") == "town":
			entrances[str(portal["to"]["space"])] = true
		for side: String in ["from", "to"]:
			var address: Dictionary = portal[side]
			var pos: Vector2i = Vector2i(int(address["pos"][0]), int(address["pos"][1]))
			if not sim._cell_walkable(sim._grid_for(str(address["space"]), str(address["floor"])), pos):
				invalid.append({"portal":portal["id"],"side":side})
	ck("every_building_has_an_actual_exterior_portal", entrances.size() == buildings.size(), entrances.size())
	ck("every_door_and_stair_endpoint_is_canonically_walkable", invalid.is_empty(), invalid)
	var absent: Array = []
	var blocked: Array = []
	var new_count: int = 0
	for object_id: String in projection.get("interaction_bindings", {}):
		var binding: Dictionary = projection["interaction_bindings"][object_id]
		if bool(binding.get("anchor_only", false)):
			continue
		if not sim.world.get("objects", {}).has(object_id):
			absent.append(object_id)
		var plane: PackedStringArray = str(binding["plane"]).split("/")
		var pos: Vector2i = Vector2i(int(binding["cell"][0]), int(binding["cell"][1]))
		if not sim._cell_walkable(sim._grid_for(plane[0], plane[1]), pos):
			blocked.append(object_id)
		if object_id.begins_with("upgrade_"):
			new_count += 1
	ck("every_bound_legacy_and_new_fixture_is_a_real_Sim_object", absent.is_empty(), absent)
	ck("every_fixture_has_an_open_standing_approach", blocked.is_empty(), blocked)
	ck("new_territory_offers_meaningful_existing_actions", new_count > 100, new_count)
	ck("existing_core_action_and_resident_ids_preserved", sim.world.get("objects", {}).has("cafe1f_counter") and sim.world.get("objects", {}).has("home1f_bed") and not sim.get_agent("aria").is_empty() and not sim.get_agent("ben").is_empty())
	var reserve: int = 0
	var expansion: int = 0
	for bid: String in buildings:
		reserve += int(bid.begins_with("Reserve_"))
		expansion += int(bid.begins_with("Expansion_"))
	ck("reserve_and_five_expansion_districts_are_playable", reserve == 21 and expansion == 81, {"reserve":reserve,"expansion":expansion})
	var heights: Array = planes.get("town/outdoor", {}).get("terrain_heights_m", [])
	var low: float = 10000.0
	var high: float = -10000.0
	for value: float in heights:
		low = minf(low, value)
		high = maxf(high, value)
	ck("actual_elevated_terrain_profile_is_retained", high-low > 30, {"minimum_m":low,"maximum_m":high})
	var original_portals: Array = read_json("res://data/spaces.json").get("portals", [])
	var permissions_preserved: bool = true
	for old: Dictionary in original_portals:
		var found: bool = false
		for current: Dictionary in sim._portals:
			if current["id"] == old["id"]:
				found = current.get("access") == old.get("access")
		permissions_preserved = permissions_preserved and found
	ck("original_private_and_staff_access_rules_preserved", permissions_preserved)
	check_long_actual_walk()
	var save_path: String = "user://upgrade_test_" + str(Time.get_ticks_msec()) + ".dat"
	var saved: bool = sim.save_game(save_path, {"test":"upgraded_town"})
	ck("complete_territory_save_succeeds", saved)
	var save_sizes: Dictionary = {"base_limit_bytes":SimScript.PLAYER_TRACE_MAX_SAVE_BYTES,"receiver_topology_allowance_bytes":sim.ext.save_topology_allowance_bytes(),"effective_limit_bytes":sim.save_byte_limit()}
	if saved:
		var measured: FileAccess = FileAccess.open(save_path, FileAccess.READ)
		save_sizes["actual_file_bytes"] = measured.get_length()
		measured.get_32()
		var envelope: Dictionary = measured.get_var()
		measured.close()
		save_sizes["variant_payload_bytes"] = var_to_bytes(envelope).size()
		save_sizes["encoded_file_bytes"] = sim.save_encoded_file_bytes(envelope)
		ck("whole_town_actual_encoded_file_matches_measured_bounded_size", int(save_sizes["actual_file_bytes"]) == int(save_sizes["encoded_file_bytes"]) and int(save_sizes["actual_file_bytes"]) > SimScript.PLAYER_TRACE_MAX_SAVE_BYTES and int(save_sizes["actual_file_bytes"]) <= sim.save_byte_limit() and sim.save_byte_limit() <= 64*1024*1024, save_sizes)
	var peer: Node = fresh()
	var loaded: bool = saved and peer.load_game(save_path)
	ck("complete_territory_load_succeeds", loaded)
	var sim_chain: int = Inv.chain_step(Inv.CHAIN_INIT, sim, 0)
	var peer_chain: int = Inv.chain_step(Inv.CHAIN_INIT, peer, 0)
	var deterministic: bool = loaded and sim_chain == peer_chain and Inv.digest(sim) == Inv.digest(peer) and sim.event_digest == peer.event_digest
	for index: int in range(12):
		var sim_events: int = sim.event_log.size()
		var peer_events: int = peer.event_log.size()
		sim.tick()
		peer.tick()
		sim_chain = Inv.chain_step(sim_chain, sim, sim_events)
		peer_chain = Inv.chain_step(peer_chain, peer, peer_events)
		deterministic = deterministic and sim_chain == peer_chain and Inv.digest(sim) == Inv.digest(peer) and sim.event_digest == peer.event_digest
	ck("save_load_future_resident_state_is_deterministic", deterministic)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	var report: Dictionary = {"schema":"living_town.upgrade_gameplay_integration.v1","status":"PASS" if failures == 0 else "FAIL","failures":failures,"checks":checks,
		"source_asset_set_sha256":stage.get("source_asset_set_sha256"),"projection_sha256":FileAccess.get_sha256("res://data/town3d/projection.json"),"profile_sha256":FileAccess.get_sha256("res://data/town3d/profile.json"),"save_budget":save_sizes,
		"limitations":["This logical arm instantiates authoritative Sim, not graphics. The Main/LifeMode walkthrough is separate GPU/input evidence."]}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_path).get_base_dir())
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	else:
		ck("integration_report_written", false, report_path)
	print("town_upgrade_integration_test: %s (%d failures) report=%s" % ["PASS" if failures == 0 else "FAIL", failures, report_path])
	get_tree().quit(0 if failures == 0 else 1)

func walk_public_to(endpoint: Vector2i) -> Dictionary:
	var actor: Dictionary = Sim.controlled()
	var space: String = str(actor.get("space", "town"))
	var floor: String = str(actor.get("floor", "outdoor"))
	var budget: int = Sim.ext.travel_step_budget(space, floor)
	var steps: int = 0
	while steps <= budget:
		var before: Vector2i = Sim.controlled()["pos"]
		if absi(before.x-endpoint.x)+absi(before.y-endpoint.y) <= 1:
			return {"ok":true,"steps":steps,"every_step_adjacent":true}
		var result: String = Sim.life_step_toward(endpoint, 1)
		var after: Vector2i = Sim.controlled()["pos"]
		if result == "blocked" or absi(before.x-after.x)+absi(before.y-after.y) > 1 or Sim.controlled().get("space") != space or Sim.controlled().get("floor") != floor:
			return {"ok":false,"steps":steps,"result":result}
		steps += 1
	return {"ok":false,"steps":steps,"result":"budget"}

func cross_public_portal(ident: String) -> Dictionary:
	var actor: Dictionary = Sim.controlled()
	for portal: Dictionary in Sim._portals:
		if str(portal.get("id", "")) != ident:
			continue
		for side: String in ["from", "to"]:
			var endpoint: Dictionary = portal[side]
			if endpoint.get("space") != actor.get("space") or endpoint.get("floor") != actor.get("floor"):
				continue
			var point: Vector2i = Vector2i(int(endpoint["pos"][0]), int(endpoint["pos"][1]))
			var walked: Dictionary = walk_public_to(point)
			if not walked["ok"]:
				return {"ok":false,"portal":ident,"walk":walked}
			return {"ok":bool(Sim.life_portal(point).get("ok", false)),"portal":ident,"walk":walked,"new_space":Sim.controlled().get("space"),"new_floor":Sim.controlled().get("floor")}
	return {"ok":false,"portal":ident,"reason":"No matching current-plane endpoint"}

func solid_probe(grid: Dictionary, point: Vector2i) -> Vector2i:
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var solid: Vector2i = point + direction*2
		var enclosed: bool = not Sim._cell_walkable(grid, point + direction) and not Sim._cell_walkable(grid, solid)
		for edge: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			enclosed = enclosed and not Sim._cell_walkable(grid, solid + edge)
		if enclosed: return solid
	return Vector2i(-1, -1)

func check_long_actual_walk() -> void:
	var resident: Dictionary = Sim.get_agent("aria")
	ck("long_travel_uses_original_resident_at_authored_indoor_start", not resident.is_empty() and resident.get("space") == "cafe" and resident.get("floor") == "2f")
	if resident.is_empty():
		return
	ck("long_travel_uses_public_possession", Sim.possess(str(resident["id"])))
	var stairs: Dictionary = cross_public_portal("p_cafe_stairs")
	ck("original_resident_walks_to_and_descends_real_owner_stairs", stairs.get("ok", false) and Sim.controlled().get("space") == "cafe" and Sim.controlled().get("floor") == "1f", stairs)
	var door: Dictionary = cross_public_portal("p_cafe_door") if stairs.get("ok", false) else {"ok":false}
	ck("original_indoor_resident_reaches_outdoors_by_public_walk_and_portal", door.get("ok", false) and Sim.controlled().get("space") == "town", door)
	if not door.get("ok", false):
		Sim.possess("")
		return
	var start: Vector2i = Sim.controlled()["pos"]
	var goal: Vector2i = start
	var best: int = 100000
	var grid: Dictionary = Sim._grid_for("town", "outdoor")
	for portal: Dictionary in Sim._portals:
		if portal["from"].get("space") != "town":
			continue
		var p: Array = portal["from"]["pos"]
		var point: Vector2i = Vector2i(int(p[0]), int(p[1]))
		var distance: int = absi(point.x-start.x) + absi(point.y-start.y)
		if distance > 180 and distance < best and solid_probe(grid, point) != Vector2i(-1, -1):
			goal = point
			best = distance
	var life: Node = LifeScript.new()
	life.pid = str(resident["id"])
	life._toast = Label.new()
	life._walk_to(goal)
	var budget: int = int(life._walk_step_budget)
	var adjacent_steps: bool = true
	while life._walk_on and life._walk_steps <= budget + 1:
		var before: Vector2i = Sim.controlled()["pos"]
		life._move_cd = 0.0
		life._walk_tick()
		var after: Vector2i = Sim.controlled()["pos"]
		adjacent_steps = adjacent_steps and absi(before.x-after.x)+absi(before.y-after.y) <= 1
	ck("actual_LifeMode_route_beyond160steps_arrives_without_teleport", best < 100000 and life._walk_steps > 160 and Sim.controlled()["pos"] == goal and adjacent_steps,
		{"steps":life._walk_steps,"budget":budget,"start":str(start),"goal":str(goal),"every_step_adjacent":adjacent_steps})
	var unreachable: Vector2i = solid_probe(grid, goal)
	ck("unreachable_route_uses_actual_solid_geometry", unreachable != Vector2i(-1, -1))
	if unreachable != Vector2i(-1, -1):
		life._walk_to(unreachable)
		life._move_cd = 0.0
		life._walk_tick()
		ck("unreachable_route_still_stops_without_arrival_or_relocation", not life._walk_on and Sim.controlled()["pos"] == goal,
			{"solid_goal":str(unreachable),"actual_position":str(Sim.controlled()["pos"])})
	life._toast.free()
	life.free()
	Sim.possess("")
