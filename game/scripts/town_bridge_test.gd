extends Node
## Core/geometry integration gate. No 3D scene is instantiated in this logical arm.
## Navigation and actions below run through the existing Sim, not GLB collisions.
const SimScript = preload("res://scripts/Sim.gd")
const ProfileScript = preload("res://scripts/TownWorldProfile.gd")
const Inv = preload("res://bench/Invariants.gd")
const MAX_NATURAL_TICKS: int = 2400
const REPORT_PATH: String = "res://../docs/town_bridge/logical_test_report.json"

var report: Dictionary = {"schema": "living_town.bridge.logical.v1", "checks": []}
var failures: int = 0
var instances: Array[Node] = []


func ck(label: String, passed: bool, detail: Variant = null) -> void:
	report["checks"].append({"name": label, "passed": passed, "detail": detail})
	print(("PASS " if passed else "FAIL ") + label)
	if not passed:
		failures += 1


func read_json(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}


func fresh(profile_on: bool = true) -> Node:
	var sim: Node = SimScript.new()
	sim.auto_run = false
	sim.running = false
	sim.backend = null
	add_child(sim)
	instances.append(sim)
	if profile_on:
		var provider: RefCounted = ProfileScript.new()
		var valid: bool = provider.load_profile()
		ck("profile_load_" + str(instances.size()), valid, provider.error_message)
		if valid:
			ck("profile_install_before_start_" + str(instances.size()), sim.install_world_profile(provider))
	return sim


func cell(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	return Vector2i(int(value[0]), int(value[1]))


func flood(sim: Node, space: String, floor_id: String, seed: Vector2i) -> Dictionary:
	var grid: Dictionary = sim._grid_for(space, floor_id)
	var width: int = int(grid.get("w", 0))
	var seen: Dictionary = {}
	if width <= 0 or not sim._cell_walkable(grid, seed):
		return seen
	var queue: Array[Vector2i] = [seed]
	seen[seed.y * width + seed.x] = seed
	var head: int = 0
	while head < queue.size():
		var here: Vector2i = queue[head]
		head += 1
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = here + step
			var index: int = next.y * width + next.x
			if not seen.has(index) and sim._cell_walkable(grid, next):
				seen[index] = here
				queue.append(next)
	return seen


func walk_player(sim: Node, destination: Vector2i) -> bool:
	var player: Dictionary = sim.get_agent("player")
	var start: Vector2i = player["pos"]
	var space: String = str(player.get("space", "town"))
	var floor_id: String = str(player.get("floor", "outdoor"))
	var grid: Dictionary = sim._grid_for(space, floor_id)
	var width: int = int(grid["w"])
	var parents: Dictionary = flood(sim, space, floor_id, start)
	if not parents.has(destination.y * width + destination.x):
		return false
	var path: Array[Vector2i] = []
	var cursor: Vector2i = destination
	while cursor != start:
		path.push_front(cursor)
		cursor = parents[cursor.y * width + cursor.x]
	for next: Vector2i in path:
		var before: Vector2i = player["pos"]
		sim.player_move(next - before)
		if player["pos"] != next:
			return false
	return player["pos"] == destination


func walk_controlled(sim: Node, destination: Vector2i) -> bool:
	var actor: Dictionary = sim.controlled()
	if actor.is_empty():
		return false
	var start: Vector2i = actor["pos"]
	var space: String = str(actor.get("space", "town"))
	var floor_id: String = str(actor.get("floor", "outdoor"))
	var grid: Dictionary = sim._grid_for(space, floor_id)
	var width: int = int(grid["w"])
	var parents: Dictionary = flood(sim, space, floor_id, start)
	if not parents.has(destination.y * width + destination.x):
		return false
	var path: Array[Vector2i] = []
	var cursor: Vector2i = destination
	while cursor != start:
		path.push_front(cursor)
		cursor = parents[cursor.y * width + cursor.x]
	for next: Vector2i in path:
		var before: Vector2i = actor["pos"]
		if str(sim.life_move(next - before)) != "" or actor["pos"] != next:
			return false
	return actor["pos"] == destination


func visit_controlled(sim: Node, space: String, floor_id: String, destination: Vector2i) -> bool:
	for _hop_index in range(8):
		var actor: Dictionary = sim.controlled()
		if actor.is_empty():
			return false
		var from_space: String = str(actor.get("space", "town"))
		var from_floor: String = str(actor.get("floor", "outdoor"))
		if from_space == space and from_floor == floor_id:
			return walk_controlled(sim, destination)
		var hop: Dictionary = sim._route_next_hop(from_space, from_floor, space, floor_id, actor)
		if hop.is_empty() or not walk_controlled(sim, cell(hop["from_pos"])):
			return false
		if not bool(sim.life_portal(cell(hop["from_pos"])).get("ok", false)):
			return false
	return false


func agent_state(ag: Dictionary) -> Dictionary:
	var result: Dictionary = ag.duplicate(true)
	var memory: Variant = ag.get("memory")
	result["memory"] = memory.items.duplicate(true) if memory is Object and "items" in memory else []
	return result


func core_state(sim: Node) -> Dictionary:
	var people: Array = []
	for ag: Dictionary in sim.agents:
		people.append(agent_state(ag))
	return {"agents": people, "tick": sim.tick_no, "events": sim.event_log.duplicate(true),
		"digest": sim.event_digest, "world": sim.world.duplicate(true), "loaded_meta": sim.loaded_meta.duplicate(true),
		"path_cache": sim._path_cache.duplicate(true)}


func tamper_geometry_save(source: String, target: String, arm: String) -> bool:
	var input: FileAccess = FileAccess.open(source, FileAccess.READ)
	if input == null or input.get_length() < 8:
		return false
	var header: int = input.get_32()
	var blob: Variant = input.get_var()
	input.close()
	if not blob is Dictionary or not blob.get("state") is Dictionary:
		return false
	var world: Dictionary = blob["state"]["world"]
	if arm == "nav_blockers":
		if (world.get("nav_blockers", []) as Array).is_empty():
			return false
		world["nav_blockers"].pop_back()
	elif arm == "map_width":
		world["width"] = int(world["width"]) + 1
	else:
		return false
	var output: FileAccess = FileAccess.open(target, FileAccess.WRITE)
	if output == null:
		return false
	output.store_32(header)
	output.store_var(blob)
	output.close()
	return true


func _ready() -> void:
	var sim: Node = fresh()
	sim.start_new(7)
	var legacy: Node = fresh(false)
	legacy.start_new(7)
	var projection: Dictionary = read_json("res://data/town3d/projection.json")
	var profile: Dictionary = read_json("res://data/town3d/profile.json")
	var catalog: Dictionary = read_json("res://assets/town3d/node_catalog.json")
	var planes: Dictionary = projection.get("planes", {})
	var assets: Dictionary = {}
	var semantic_nodes: Dictionary = {}
	for node: Dictionary in catalog.get("nodes", []):
		var extras: Dictionary = node.get("extras", {})
		semantic_nodes[str(node.get("name", ""))] = true
		if extras.has("source_object"):
			semantic_nodes[str(extras["source_object"])] = true
		if extras.has("interior_asset_id"):
			assets[str(extras["interior_asset_id"])] = true
	report["source_blend_sha256"] = profile.get("model_source_blend_sha256", "")
	report["projection_sha256"] = FileAccess.get_sha256("res://data/town3d/projection.json")
	report["profile_sha256"] = FileAccess.get_sha256("res://data/town3d/profile.json")
	report["source_hashes"] = {}
	for script_path: String in ["Main.gd", "Sim.gd", "SpaceGraph.gd", "TownWorldProfile.gd", "WorldView3D.gd", "town_bridge_test.gd"]:
		report["source_hashes"]["game/scripts/" + script_path] = FileAccess.get_sha256("res://scripts/" + script_path)
	ck("49_buildings_89_interior_planes_and_outdoor", (projection.get("building_spaces", {}) as Dictionary).size() == 49 and planes.size() == 90, {"building_spaces": (projection.get("building_spaces", {}) as Dictionary).size(), "planes": planes.size()})
	ck("projection_matches_frozen_model", projection.get("model_source_blend_sha256") == catalog.get("source_blend_sha256"))
	ck("profile_cannot_replace_live_run", not sim.install_world_profile(ProfileScript.new()))

	var endpoints: Dictionary = {}
	var reachable: Dictionary = {}
	var invalid: Array = []
	var duplicate: Array = []
	for portal: Dictionary in sim._portals:
		for side: String in ["from", "to"]:
			var endpoint: Dictionary = portal[side]
			var key: String = str(endpoint["space"]) + "/" + str(endpoint["floor"])
			var point: Vector2i = cell(endpoint["pos"])
			var address: String = key + ":" + str(point.x) + "," + str(point.y)
			if endpoints.has(address):
				duplicate.append(address)
			endpoints[address] = str(portal["id"])
			if not planes.has(key) or not sim._cell_walkable(sim._grid_for(str(endpoint["space"]), str(endpoint["floor"])), point):
				invalid.append(address)
			if not reachable.has(key):
				reachable[key] = flood(sim, str(endpoint["space"]), str(endpoint["floor"]), point)
	ck("89_real_portals_have_178_unique_walkable_endpoints", sim._portals.size() == 89 and endpoints.size() == 178 and duplicate.is_empty() and invalid.is_empty(), {"portals": sim._portals.size(), "duplicate": duplicate, "invalid": invalid})
	var disconnected_endpoints: Array = []
	for address: String in endpoints:
		var parts: PackedStringArray = address.split(":")
		var xy: PackedStringArray = parts[1].split(",")
		var point: Vector2i = Vector2i(int(xy[0]), int(xy[1]))
		var plane: Dictionary = planes[parts[0]]
		var width: int = int(plane["grid_size"][0])
		if not (reachable[parts[0]] as Dictionary).has(point.y * width + point.x):
			disconnected_endpoints.append(address)
	ck("each_plane_connects_its_real_door_and_stair_cells", disconnected_endpoints.is_empty(), disconnected_endpoints)

	var broken_fixtures: Array = []
	var bindings: Dictionary = projection.get("interaction_bindings", {})
	for id: String in sim.world["objects"]:
		var object: Dictionary = sim.world["objects"][id]
		var key: String = str(object.get("space", "town")) + "/" + str(object.get("floor", "outdoor"))
		var point: Vector2i = object["pos"]
		var grid: Dictionary = sim._grid_for(str(object.get("space", "town")), str(object.get("floor", "outdoor")))
		var binding: Dictionary = bindings.get(id, {})
		var dynamic: bool = id.begins_with("fest_") or id.begins_with("civic_")
		if not sim._cell_walkable(grid, point) or not reachable.get(key, {}).has(point.y * int(grid["w"]) + point.x):
			broken_fixtures.append(id)
		if not dynamic and (binding.is_empty() or binding.get("plane") != key or cell(binding.get("cell", [-99, -99])) != point):
			broken_fixtures.append(id + ":unbound_static_fixture")
		var raw_asset: Variant = binding.get("model_asset_id")
		var asset_id: String = "" if raw_asset == null else str(raw_asset)
		if not asset_id.is_empty() and not assets.has(asset_id) and not semantic_nodes.has(asset_id):
			broken_fixtures.append(id + ":missing_model_asset")
	ck("every_functional_fixture_reachable_and_bound_to_real_model", broken_fixtures.is_empty(), {"fixture_count": sim.world["objects"].size(), "broken": broken_fixtures})

	var interior_plan: Dictionary = read_json("res://assets/town3d/interior_plan.json")
	var building_spaces: Dictionary = projection.get("building_spaces", {})
	var inaccessible_rooms: Array = []
	var activity_count: int = 0
	for building: Dictionary in interior_plan.get("buildings", []):
		var space_id: String = str(building_spaces.get(building["id"], ""))
		for level: Dictionary in building.get("levels", building.get("floors", [])):
			# The authored plan uses a list under levels in current delivery.
			var key: String = space_id + "/" + str(int(level["level"]) + 1) + "f"
			var plane: Dictionary = planes.get(key, {})
			for room: Dictionary in level.get("rooms", []):
				if (room.get("assets", []) as Array).is_empty():
					continue
				activity_count += 1
				var reached: bool = false
				if not plane.is_empty():
					var bounds: Array = room["bounds_m"]
					var origin: Array = plane["origin_local_m"]
					var step: float = float(plane["cell_size_m"])
					var width: int = int(plane["grid_size"][0])
					var x0: int = int(ceil((float(bounds[0]) - float(origin[0])) / step - 0.5))
					var x1: int = int(floor((float(bounds[2]) - float(origin[0])) / step - 0.5))
					var y0: int = int(ceil((float(origin[1]) - float(bounds[3])) / step - 0.5))
					var y1: int = int(floor((float(origin[1]) - float(bounds[1])) / step - 0.5))
					for y: int in range(y0, y1 + 1):
						for x: int in range(x0, x1 + 1):
							reached = reached or reachable.get(key, {}).has(y * width + x)
				if not reached:
					inaccessible_rooms.append(room["id"])
	ck("223_modeled_activity_rooms_have_actual_reachable_cells", activity_count == 223 and inaccessible_rooms.is_empty(), {"activity_rooms": activity_count, "unreachable": inaccessible_rooms})

	var changed_rules: Array = []
	for id: String in legacy.world["objects"]:
		if not sim.world["objects"].has(id):
			changed_rules.append(id + ":missing")
			continue
		for field: String in ["type", "staff", "advertises"]:
			if legacy.world["objects"][id].get(field) != sim.world["objects"][id].get(field):
				changed_rules.append(id + ":" + field)
	ck("existing_functional_object_ids_and_action_rules_preserved", changed_rules.is_empty(), changed_rules)
	var changed_portals: Array = []
	for original: Dictionary in legacy._portals:
		var found: Dictionary = {}
		for current: Dictionary in sim._portals:
			if current["id"] == original["id"]:
				found = current
		for field: String in ["kind", "access", "owner_space", "bidirectional", "traversal_cost"]:
			if found.is_empty() or original.get(field) != found.get(field):
				changed_portals.append(str(original["id"]) + ":" + field)
	ck("19_current_original_portal_ids_owner_access_and_costs_preserved", legacy._portals.size() == 19 and changed_portals.is_empty(), {"original_count": legacy._portals.size(), "changes": changed_portals})
	var ui_failures: Array = []
	for marker_id: String in ["bank_counter", "civic_observatory"]:
		var marker_binding: Dictionary = bindings.get(marker_id, {})
		var marker_plane: PackedStringArray = String(marker_binding.get("plane", "/")).split("/")
		var marker_cell: Vector2i = cell(marker_binding.get("cell", [-99, -99]))
		var marker_grid: Dictionary = sim._grid_for(marker_plane[0], marker_plane[1])
		if not bool(marker_binding.get("anchor_only", false)) or sim.world["objects"].has(marker_id) \
				or not assets.has(String(marker_binding.get("model_asset_id", ""))) \
				or not sim._cell_walkable(marker_grid, marker_cell) \
				or not reachable.get(String(marker_binding.get("plane", "")), {}).has(marker_cell.y * int(marker_grid.get("w", 0)) + marker_cell.x):
			ui_failures.append(marker_id)
	ck("bank_civic_UI_markers_bind_real_reachable_fixtures_without_NPC_advertisements", ui_failures.is_empty(), ui_failures)
	ck("home2_two_current_bed_IDs_bind_distinct_real_beds_and_real_floors", \
		bindings.get("home22f_bed", {}).get("model_asset_id", "") != bindings.get("home22f_bed_1", {}).get("model_asset_id", "") \
		and assets.has(String(bindings.get("home22f_bed", {}).get("model_asset_id", ""))) \
		and assets.has(String(bindings.get("home22f_bed_1", {}).get("model_asset_id", ""))) \
		and planes.has("home2/2f") and planes.has("home2/3f"))

	# Reach the current bank through genuine authored portals/cells and execute
	# the unchanged transaction API. Neither test rewrites an actor dictionary.
	var bank_sim: Node = fresh()
	bank_sim.start_new(7)
	var bank_opened: bool = bool(bank_sim.possess("ben"))
	if bank_opened:
		bank_opened = visit_controlled(bank_sim, "halles", "1f", bank_sim.bank_counter_cell())
	var bank_menu_found: bool = false
	if bank_opened:
		for entry: Dictionary in bank_sim.life_interactions(1):
			bank_menu_found = bank_menu_found or entry.get("kind") == "bank"
	var bank_total: int = int(bank_sim.money_total())
	var wallet_before: int = int(bank_sim._coin_of("ben"))
	var deposit_ok: bool = bank_menu_found and bool(bank_sim.player_bank_action("deposit", "ben", 1).get("ok", false))
	var deposit_amount: int = int(bank_sim.bank_deposits.get("ben", 0))
	var withdraw_ok: bool = deposit_ok and bool(bank_sim.player_bank_action("withdraw", "ben", 1).get("ok", false))
	ck("real_halles_bank_entry_deposit_withdraw_preserves_money", withdraw_ok and deposit_amount == 1 \
		and int(bank_sim._coin_of("ben")) == wallet_before and int(bank_sim.money_total()) == bank_total, \
		{"entry": bank_opened, "bank_menu": bank_menu_found, "deposit": deposit_ok, "withdraw": withdraw_ok})
	var civic_sim: Node = fresh()
	civic_sim.start_new(7)
	var civic_opened: bool = bool(civic_sim.possess("ben"))
	if civic_opened:
		civic_opened = visit_controlled(civic_sim, "mairie", "1f", civic_sim.civic_observatory_cell())
	var civic_before: Dictionary = core_state(civic_sim)
	var civic_menu_found: bool = false
	if civic_opened:
		for entry: Dictionary in civic_sim.life_interactions(1):
			civic_menu_found = civic_menu_found or entry.get("kind") == "civic"
	var civic_projection: Dictionary = civic_sim.civic_observatory_projection()
	ck("real_mairie_civic_board_remains_read_only", civic_menu_found and civic_projection.get("mode") == "read_only" and core_state(civic_sim) == civic_before, {"entry": civic_opened, "civic_menu": civic_menu_found})
	var jobs_changed: Array = []
	for ag: Dictionary in legacy.agents:
		var id: String = str(ag["id"])
		if sim.get_agent(id).is_empty() or sim.get_agent(id).get("persona_key") != ag.get("persona_key"):
			jobs_changed.append(id + ":identity")
		for field: String in ["title", "action", "wage", "shift", "on_site", "affiliate"]:
			if legacy._job_of(id).get(field) != sim._job_of(id).get(field):
				jobs_changed.append(id + ":" + field)
	ck("residents_personas_and_jobs_retained", jobs_changed.is_empty(), jobs_changed)

	var seen: Dictionary = {}
	for ag: Dictionary in sim.agents:
		seen[str(ag["id"])] = {"home": str(ag.get("space", "town")), "street": false, "cafe": false}
	var cafe_use: Dictionary = {}
	var social_count: int = 0
	var cross_plane_social: Array = []
	for tick_index: int in range(MAX_NATURAL_TICKS):
		var before: Dictionary = {}
		for ag: Dictionary in sim.agents:
			before[str(ag["id"])] = {"needs": ag["needs"].duplicate(true), "option": ag.get("option").duplicate(true) if ag.get("option") is Dictionary else {}}
		sim.tick()
		for ag: Dictionary in sim.agents:
			var id: String = str(ag["id"])
			var state: Dictionary = seen[id]
			state["street"] = state["street"] or ag.get("space") == "town"
			state["cafe"] = state["cafe"] or (bool(state["street"]) and ag.get("space") == "cafe")
			var old_option: Dictionary = before[id]["option"]
			var target: String = str(old_option.get("target", ""))
			var need: String = str(old_option.get("need", ""))
			if state["home"] != "town" and state["home"] != "cafe" and bool(state["cafe"]) and old_option.get("phase") == "use" and not need.is_empty() and float(ag["needs"].get(need, 0)) > float(before[id]["needs"].get(need, 0)) + 0.1 and bindings.get(target, {}).get("plane", "") == "cafe/1f":
				cafe_use = {"agent": id, "home": state["home"], "target": target, "model_asset_id": bindings[target].get("model_asset_id"), "action": old_option.get("action"), "need": need, "before": before[id]["needs"][need], "after": ag["needs"][need], "tick": sim.tick_no}
			var partner: String = str(ag.get("talk_with", ""))
			if int(ag.get("talking", 0)) > 0 and not partner.is_empty() and not sim.get_agent(partner).is_empty():
				social_count += 1
				if not sim._same_plane(ag, sim.get_agent(partner)):
					cross_plane_social.append({"actor": id, "partner": partner, "tick": sim.tick_no})
		if not cafe_use.is_empty() and social_count > 0 and sim.tick_no >= 480:
			break
	ck("natural_home_to_street_to_cafe_fixture_use_changes_need", not cafe_use.is_empty(), {"observed": cafe_use, "ticks": sim.tick_no, "seed": 7, "direct_agent_writes": false})
	ck("natural_social_activity_stays_on_same_canonical_plane", social_count > 0 and cross_plane_social.is_empty(), {"observed_actor_ticks": social_count, "violations": cross_plane_social})

	var gate: Node = fresh()
	gate.start_new(7)
	gate.add_player()
	var cafe_door: Dictionary = {}
	var cafe_stair: Dictionary = {}
	for portal: Dictionary in gate._portals:
		if portal["id"] == "p_cafe_door": cafe_door = portal
		if portal["id"] == "p_cafe_stairs": cafe_stair = portal
	var door_walk: bool = walk_player(gate, cell(cafe_door["from"]["pos"]))
	var entered: Dictionary = gate.player_portal_intent({"source_space": "town", "source_floor": "outdoor", "portal_pos": cell(cafe_door["from"]["pos"])})
	ck("player_walks_real_street_and_enters_public_cafe", door_walk and bool(entered.get("ok", false)), entered)
	var stair_walk: bool = walk_player(gate, cell(cafe_stair["from"]["pos"]))
	var before_denial: Dictionary = core_state(gate)
	var denied: Dictionary = gate.player_portal_intent({"source_space": "cafe", "source_floor": "1f", "portal_pos": cell(cafe_stair["from"]["pos"])})
	ck("private_cafe_stair_denial_is_atomic", stair_walk and not bool(denied.get("ok", true)) and core_state(gate) == before_denial, denied)

	var save_path: String = "user://town_bridge_test_profile.dat"
	ck("profile_save_succeeds", sim.save_game(save_path, {"test": "town_bridge"}))
	var peer: Node = fresh()
	peer.start_new(7)
	ck("same_profile_load_succeeds", peer.load_game(save_path))
	var deterministic: bool = true
	var first_drift: int = -1
	var left_chain: int = Inv.CHAIN_INIT
	var right_chain: int = Inv.CHAIN_INIT
	for future: int in range(48):
		var left_events: int = sim.event_log.size()
		var right_events: int = peer.event_log.size()
		sim.tick()
		peer.tick()
		left_chain = Inv.chain_step(left_chain, sim, left_events)
		right_chain = Inv.chain_step(right_chain, peer, right_events)
		if left_chain != right_chain or sim.event_digest != peer.event_digest:
			deterministic = false
			if first_drift < 0: first_drift = future
	ck("save_load_then_48_future_ticks_are_deterministic", deterministic, {"first_drift": first_drift, "left_chain": left_chain, "right_chain": right_chain})
	for arm: String in ["nav_blockers", "map_width"]:
		var bad_path: String = "user://town_bridge_tampered_" + arm + ".dat"
		var before_bad: Dictionary = core_state(peer)
		var written: bool = tamper_geometry_save(save_path, bad_path, arm)
		ck("profile_rejects_tampered_" + arm + "_atomically", written and not peer.load_game(bad_path) and core_state(peer) == before_bad)
	var legacy_save: String = "user://town_bridge_test_legacy.dat"
	ck("legacy_control_save_succeeds", legacy.save_game(legacy_save))
	var profile_before: Dictionary = core_state(peer)
	ck("profile_rejects_legacy_archive_without_mutation", not peer.load_game(legacy_save) and core_state(peer) == profile_before)
	var legacy_before: Dictionary = core_state(legacy)
	ck("legacy_rejects_profile_archive_without_mutation", not legacy.load_game(save_path) and core_state(legacy) == legacy_before)
	finish()


func finish() -> void:
	var path: String = ProjectSettings.globalize_path("res://").path_join("../docs/town_bridge/logical_test_report.json").simplify_path()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--town-test-report":
			if i + 1 >= args.size() or not String(args[i + 1]).is_absolute_path():
				push_error("--town-test-report requires an absolute output file path")
				get_tree().quit(1)
				return
			path = String(args[i + 1]).simplify_path()
	report["status"] = "PASS" if failures == 0 else "FAIL"
	report["failure_count"] = failures
	report["engine_version"] = Engine.get_version_info()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	for sim: Node in instances:
		sim.queue_free()
	print("TOWN_BRIDGE_LOGICAL ", report["status"], " checks=", report["checks"].size(), " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
