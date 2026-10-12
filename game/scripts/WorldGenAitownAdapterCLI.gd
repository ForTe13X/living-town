extends SceneTree
## Compile a WorldPackage through the game adapter without activating it in Sim.

const ADAPTER := preload("res://addons/worldgen/consumers/ai_town_adapter/space_queries.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("WORLDGEN_AITOWN_USAGE: expected <package.json> <output-directory>")
		quit(2)
		return
	var package: Variant = _read_json(String(args[0]))
	if not package is Dictionary:
		push_error("WORLDGEN_AITOWN_PACKAGE: cannot read package")
		quit(2)
	var graph: Dictionary = _read_json("res://data/spaces.json")
	var interiors: Dictionary = _read_json("res://data/interiors.json")
	var bindings: Dictionary = _read_json("res://addons/worldgen/consumers/ai_town_adapter/action_bindings.json")
	var map_data: Dictionary = _read_json("res://data/map.json")
	var jobs: Dictionary = _read_json("res://data/jobs.json").get("jobs", {})
	var adapter: RefCounted = ADAPTER.new()
	var merged: Dictionary = adapter.merge_package(package, graph, interiors, bindings.get("bindings", {}),
		bindings.get("staff_titles_by_building", {}), map_data.get("objects", []), jobs)
	if not bool(merged.get("ok", false)):
		for error: String in merged.get("errors", []): push_error(String(error))
		quit(1)
		return
	var authored_agents: Dictionary = _read_json("res://data/agents.json")
	var activation: Dictionary = _read_json("res://worldgen_activation.json")
	var residents: Dictionary = adapter.prepare_resident_assignments(authored_agents, activation.get("resident_assignments", []),
		merged.get("home_anchors", []), int(activation.get("capacity_per_home", 4)))
	if not bool(residents.get("ok", false)):
		for error: String in residents.get("errors", []): push_error(String(error))
		quit(1)
		return
	var output_dir := String(args[1]).simplify_path()
	var directory_error := DirAccess.make_dir_recursive_absolute(output_dir)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("WORLDGEN_AITOWN_OUTPUT: cannot create output directory")
		quit(2)
	var report := {"schema": "worldgen.aitown-adapter-report/1", "status": "prepared_nonactivating",
		"world_id": merged["world_id"], "semantic_sha256": merged["semantic_sha256"],
		"space_count": merged["spaces"]["spaces"].size(), "portal_count": merged["spaces"]["portals"].size(),
		"room_count": merged.get("rooms", []).size(), "affordance_count": merged.get("affordances", []).size(),
		"home_anchor_count": merged.get("home_anchors", []).size(), "assigned_resident_count": residents["assigned_count"],
		"runtime_bindings": _binding_summary(merged.get("affordances", [])), "activation_enabled": bool(activation.get("enabled", false))}
	if not _write_json(output_dir.path_join("spaces.json"), merged["spaces"]) \
			or not _write_json(output_dir.path_join("interiors.json"), merged["interiors"]) \
			or not _write_json(output_dir.path_join("affordances.json"), {"rooms": merged.get("rooms", []),
				"affordances": merged.get("affordances", []), "home_anchors": merged.get("home_anchors", [])}) \
			or not _write_json(output_dir.path_join("agents.preview.json"), residents["agent_document"]) \
			or not _write_json(output_dir.path_join("report.json"), report):
		push_error("WORLDGEN_AITOWN_OUTPUT: failed writing adapter artifacts")
		quit(2)
		return
	print("WORLDGEN_AITOWN_ADAPTER_OK world=%s spaces=%d portals=%d rooms=%d slots=%d residents=%d activation=%s output=%s" % [
		merged["world_id"], report["space_count"], report["portal_count"], report["room_count"],
		report["affordance_count"], report["assigned_resident_count"], str(report["activation_enabled"]), output_dir])
	quit(0)

func _binding_summary(items: Array) -> Dictionary:
	var bound := 0
	var unbound: Array[String] = []
	for item: Dictionary in items:
		if String(item.get("runtime_binding", "")).begins_with("existing_action:"):
			bound += 1
		else:
			unbound.append(String(item.get("worldgen_id", item.get("id", ""))))
	return {"bound_count": bound, "unbound_ids": unbound}

func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	return parser.data if error == OK else {}

func _write_json(path: String, value: Variant) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(value, "\t") + "\n")
	file.flush()
	file.close()
	return true
