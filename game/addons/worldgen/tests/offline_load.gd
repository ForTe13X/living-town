extends SceneTree
## Exported, renderer-free consumer gate for the three frozen local WorldPackage/1
## builds. This does not read Living Town state or qualify the LT-22 snapshot as v5.

const LOADER := preload("res://addons/worldgen/core/worldgen_package_loader.gd")
const VALIDATOR := preload("res://addons/worldgen/core/worldgen_package_validator.gd")
const SPATIAL := preload("res://addons/worldgen/core/world_package_spatial_queries.gd")
const CANONICAL := preload("res://addons/worldgen/core/worldgen_canonical.gd")
const PACKAGE_PATH := "res://world.world.json"
const EXPECTATIONS_PATH := "res://tests/offline_load_expectations.json"
const REQUIRED_CAPABILITIES := {"flat_ground": true, "portals": true,
	"presentation_profiles": ["code_only_2d"]}

var errors: Array[String] = []

func _initialize() -> void:
	var fixture_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPECTATIONS_PATH))
	if not fixture_value is Dictionary:
		_finish("", {}, {}, "E_EXPECTATIONS")
		return
	var fixture: Dictionary = fixture_value
	if fixture.get("schema") != "worldgen.offline-consumer-expectations/1" \
			or not fixture.get("worlds") is Dictionary:
		_finish("", {}, {}, "E_EXPECTATIONS")
		return
	var loaded: Dictionary = LOADER.new().load_package(PACKAGE_PATH, REQUIRED_CAPABILITIES)
	if not bool(loaded.get("ok", false)):
		_finish("", {}, {}, "E_LOAD: " + str(loaded.get("errors", [])))
		return
	var package: Dictionary = loaded["package"]
	var world_id := String(package.get("world_id", ""))
	var expected_value: Variant = fixture["worlds"].get(world_id)
	if not expected_value is Dictionary:
		_finish(world_id, package, {}, "E_UNPINNED_WORLD")
		return
	var expected: Dictionary = expected_value
	_require(String(package.get("semantic", {}).get("kind", "")) == String(expected.get("kind", "")), "kind")
	_require(CANONICAL.sha256(package) == expected.get("package_sha256"), "whole package digest")
	_require(package.get("digests", {}).get("semantic_sha256") == expected.get("semantic_sha256"), "semantic digest")
	_require(package.get("digests", {}).get("presentation_sha256") == expected.get("presentation_sha256"), "presentation digest")
	_require(not FileAccess.file_exists("res://scripts/Sim.gd") and not FileAccess.file_exists("res://data/map.json")
		and not FileAccess.file_exists("res://addons/worldgen/core/worldgen_build_service.gd")
		and not FileAccess.file_exists("res://assets/worldgen_proxy.glb"), "clean code-only consumer closure")
	var spatial = SPATIAL.new()
	var configured: Dictionary = spatial.configure(package)
	if not bool(configured.get("ok", false)):
		_finish(world_id, package, {}, "E_QUERY_CONFIGURE: " + str(configured.get("errors", [])))
		return
	var observed := _query_ids(spatial)
	_require(observed.get("buildings") == expected.get("buildings"), "building IDs")
	_require(observed.get("roads") == expected.get("roads"), "road IDs")
	for profile: String in ["public", "staff", "owner"]:
		for group: String in ["rooms", "portals", "affordances"]:
			_require(observed["profiles"][profile][group] == expected["profiles"][profile][group],
				"%s %s IDs" % [profile, group])
	_require(spatial.world_id() == world_id and spatial.semantic_digest() == expected.get("semantic_sha256"),
		"query identity")
	var detached: Array[Dictionary] = spatial.query_buildings()
	if detached.is_empty(): detached = spatial.query_rooms("public")
	if not detached.is_empty():
		detached[0]["id"] = "mutated_return_value"
		_require(_query_ids(spatial) == observed, "query results are detached")
	var altered_presentation: Dictionary = package.duplicate(true)
	altered_presentation["presentation"]["offline_test_variant"] = 1
	altered_presentation["digests"]["presentation_sha256"] = CANONICAL.sha256(altered_presentation["presentation"])
	_require(bool(VALIDATOR.validate(altered_presentation).get("ok", false)), "presentation-only package validates")
	var alternate = SPATIAL.new()
	if bool(alternate.configure(altered_presentation).get("ok", false)):
		_require(_query_ids(alternate) == observed and alternate.semantic_digest() == spatial.semantic_digest(),
			"presentation-only query parity")
	else:
		_require(false, "presentation-only query configures")
	_run_hostile_cases(package)
	_finish(world_id, package, observed, "")

func _query_ids(spatial) -> Dictionary:
	var profiles := {}
	for profile: String in ["public", "staff", "owner"]:
		profiles[profile] = {"rooms": _ids(spatial.query_rooms(profile)),
			"portals": _ids(spatial.query_portals(profile)),
			"affordances": _ids(spatial.query_affordances(profile))}
	return {"buildings": _ids(spatial.query_buildings()), "roads": _ids(spatial.query_roads()),
		"profiles": profiles}

func _ids(records: Array) -> Array[String]:
	var ids: Array[String] = []
	for record: Dictionary in records: ids.append(String(record.get("id", "")))
	ids.sort()
	return ids

func _run_hostile_cases(package: Dictionary) -> void:
	_expect_error(LOADER.new().load_package("res://missing.world.json", REQUIRED_CAPABILITIES),
		"E_PACKAGE_MISSING", "missing package")
	_expect_error(LOADER.new().load_package(PACKAGE_PATH, {"presentation_profiles": ["unsupported_profile"]}),
		"E_PACKAGE_CAPABILITY", "unsupported presentation capability")
	var semantic_tamper: Dictionary = package.duplicate(true)
	semantic_tamper["semantic"]["offline_tamper"] = true
	_expect_error(VALIDATOR.validate(semantic_tamper), "E_PACKAGE_SEMANTIC_HASH", "semantic tamper")
	var presentation_tamper: Dictionary = package.duplicate(true)
	presentation_tamper["presentation"]["offline_tamper"] = true
	_expect_error(VALIDATOR.validate(presentation_tamper), "E_PACKAGE_PRESENTATION_HASH", "presentation tamper")
	var missing_presentation: Dictionary = package.duplicate(true)
	missing_presentation.erase("presentation")
	_expect_error(VALIDATOR.validate(missing_presentation), "E_PACKAGE_FIELD: missing presentation",
		"missing presentation root")
	var unknown_root: Dictionary = package.duplicate(true)
	unknown_root["unreviewed_root"] = true
	_expect_error(VALIDATOR.validate(unknown_root), "E_PACKAGE_FIELD: unknown", "unknown root field")
	var unknown_kind: Dictionary = package.duplicate(true)
	unknown_kind["semantic"]["kind"] = "unreviewed_kind"
	unknown_kind["digests"]["semantic_sha256"] = CANONICAL.sha256(unknown_kind["semantic"])
	_expect_error(VALIDATOR.validate(unknown_kind), "E_PACKAGE_SEMANTIC_KIND", "unknown semantic kind")
	var missing_topology: Dictionary = package.duplicate(true)
	var prefix := ""
	match String(package["semantic"]["kind"]):
		"coastal_neighborhood":
			missing_topology["semantic"].erase("topology")
			prefix = "E_COAST_ORACLE_"
		"inland_neighborhood":
			missing_topology["semantic"].erase("street_graph")
			prefix = "E_INLAND_ORACLE_GRAPH"
		"standalone_interior":
			missing_topology["semantic"].erase("rooms")
			prefix = "E_INTERIOR_ORACLE_ROOM_COVERAGE"
	missing_topology["digests"]["semantic_sha256"] = CANONICAL.sha256(missing_topology["semantic"])
	_expect_error(VALIDATOR.validate(missing_topology), prefix, "missing semantic topology")
	if String(package["semantic"]["kind"]) == "inland_neighborhood":
		for group: String in ["nodes", "edges"]:
			var malformed_graph: Dictionary = package.duplicate(true)
			malformed_graph["semantic"]["street_graph"][group][0] = null
			malformed_graph["digests"]["semantic_sha256"] = CANONICAL.sha256(malformed_graph["semantic"])
			var error_prefix := "E_INLAND_ORACLE_NODE" if group == "nodes" else "E_INLAND_ORACLE_EDGE"
			_expect_error(VALIDATOR.validate(malformed_graph), error_prefix,
				"non-object road %s" % group)

func _expect_error(result: Dictionary, prefix: String, label: String) -> void:
	var matched := false
	for error: Variant in result.get("errors", []):
		if String(error).begins_with(prefix): matched = true
	_require(not bool(result.get("ok", false)) and matched, label)

func _require(condition: bool, label: String) -> void:
	if not condition: errors.append(label)

func _finish(world_id: String, package: Dictionary, observed: Dictionary, fatal: String) -> void:
	if not fatal.is_empty(): errors.append(fatal)
	print("WORLDGEN_OFFLINE_LOAD " + JSON.stringify({
		"schema": "worldgen.offline-consumer-receipt/1", "world_id": world_id,
		"package_sha256": CANONICAL.sha256(package) if not package.is_empty() else "",
		"semantic_sha256": package.get("digests", {}).get("semantic_sha256", ""),
		"presentation_sha256": package.get("digests", {}).get("presentation_sha256", ""),
		"query_ids": observed, "renderer_constructed": false,
		"external_v5_qualified": false, "errors": errors}))
	quit(0 if errors.is_empty() else 1)
