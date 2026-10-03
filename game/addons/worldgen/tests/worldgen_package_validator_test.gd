extends SceneTree
## Mutation checks for package-level coastal boundary invariants.

const VALIDATOR := preload("res://addons/worldgen/core/worldgen_package_validator.gd")
const CANONICAL := preload("res://addons/worldgen/core/worldgen_canonical.gd")

func _initialize() -> void:
	var file := FileAccess.open("res://world.world.json", FileAccess.READ)
	if file == null:
		push_error("E_TEST_FIXTURE: world.world.json is missing")
		quit(2)
		return
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not parser.data is Dictionary:
		push_error("E_TEST_FIXTURE: world.world.json is invalid")
		quit(2)
		return
	var package: Dictionary = parser.data
	var baseline: Dictionary = VALIDATOR.validate(package)
	if not bool(baseline.get("ok", false)):
		push_error("E_TEST_BASELINE: valid coastal package was rejected: %s" % str(baseline.get("errors", [])))
		quit(1)
		return
	if String(package.get("semantic", {}).get("kind", "")) != "coastal_neighborhood":
		print("WORLDGEN_COASTAL_ORACLE_TESTS_SKIPPED reason=non_coastal_package")
		quit(0)
		return
	var failures := 0
	var filled_court := package.duplicate(true)
	var bathhouse: Dictionary = _building(filled_court, "B08")
	bathhouse["segments"].append({"id": "hostile_court_fill", "rect": [38, 104, 5, 11]})
	_refresh_semantic_digest(filled_court)
	failures += _expect_error("filled U court", filled_court, "E_COAST_ORACLE_COURT")
	var borrowed_permit := package.duplicate(true)
	var bathhouse_with_permit := _building(borrowed_permit, "B08")
	bathhouse_with_permit["crossing_id"] = "P56_A56"
	_refresh_semantic_digest(borrowed_permit)
	failures += _expect_error("building borrows beach crossing", borrowed_permit, "E_COAST_ORACLE_BUILDING_CROSSING_PERMIT")
	var missing_crossing := package.duplicate(true)
	var roads: Array = missing_crossing["semantic"]["topology"]["roads"]
	for index in range(roads.size() - 1, -1, -1):
		if String(roads[index].get("id", "")) == "P56_A56": roads.remove_at(index)
	_refresh_semantic_digest(missing_crossing)
	failures += _expect_error("unused beach crossing permit", missing_crossing, "E_COAST_ORACLE_CROSSING_UNUSED")
	var intruding_road := package.duplicate(true)
	var topology: Dictionary = intruding_road["semantic"]["topology"]
	var nodes := {}
	for node: Dictionary in topology["road_nodes"]: nodes[String(node["id"])] = node["at"]
	var altered := false
	for road: Dictionary in topology["roads"]:
		if String(road.get("class", "")) != "promenade": continue
		var from: Array = nodes[String(road["from"])]
		var to: Array = nodes[String(road["to"])]
		var z := int((int(from[1]) + int(to[1])) / 2)
		var edge_x := 94
		var bands: Array = topology["shoreline"]["bands"]
		for band: Dictionary in bands:
			if int(band["z"]) <= z: edge_x = int(band["dune_edge_x"])
		road["via"] = [from, [mini(edge_x + 10, 119), z], to]
		altered = true
		break
	if not altered:
		push_error("E_TEST_FIXTURE: no promenade edge available for intrusion mutation")
		failures += 1
	else:
		_refresh_semantic_digest(intruding_road)
		failures += _expect_error("non-crossing road enters dune band", intruding_road, "E_COAST_ORACLE_EXCLUSION")
	var malformed_road := package.duplicate(true)
	var malformed_roads: Array = malformed_road["semantic"]["topology"]["roads"]
	for road: Dictionary in malformed_roads:
		if String(road.get("id", "")) == "P56_A56":
			var via: Array = road["via"]
			via[1] = "not-a-coordinate"
			break
	_refresh_semantic_digest(malformed_road)
	failures += _expect_error("malformed crossing point", malformed_road, "E_COAST_ORACLE_ROAD_POINT")
	if failures > 0:
		push_error("WORLDGEN_COASTAL_ORACLE_TESTS_FAILED count=%d" % failures)
		quit(1)
		return
	print("WORLDGEN_COASTAL_ORACLE_TESTS_OK cases=6 baseline=accepted mutations=5_rejected")
	quit(0)

func _building(package: Dictionary, building_id: String) -> Dictionary:
	for building: Dictionary in package["semantic"]["topology"]["buildings"]:
		if String(building.get("id", "")) == building_id: return building
	return {}

func _refresh_semantic_digest(package: Dictionary) -> void:
	package["digests"]["semantic_sha256"] = CANONICAL.sha256(package["semantic"])

func _expect_error(label: String, package: Dictionary, expected: String) -> int:
	var result: Dictionary = VALIDATOR.validate(package)
	if bool(result.get("ok", false)):
		push_error("E_TEST_MUTATION_ACCEPTED: %s" % label)
		return 1
	for error: String in result.get("errors", []):
		if error.begins_with(expected): return 0
	push_error("E_TEST_WRONG_REJECTION: %s expected=%s got=%s" % [label, expected, str(result.get("errors", []))])
	return 1
