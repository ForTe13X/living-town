extends SceneTree
## Deterministic acceptance checks for the successful stage cache.

const REGISTRY_SCRIPT := preload("res://addons/worldgen/core/worldgen_operator_registry.gd")
const COMPILER_SCRIPT := preload("res://addons/worldgen/core/worldgen_recipe_compiler.gd")
const EXECUTOR_SCRIPT := preload("res://addons/worldgen/core/worldgen_stage_executor.gd")
const CACHE_SCRIPT := preload("res://addons/worldgen/core/build_cache.gd")
const CANONICAL_SCRIPT := preload("res://addons/worldgen/core/worldgen_canonical.gd")

func _initialize() -> void:
	var registry = REGISTRY_SCRIPT.new()
	var topology_spec := {"id": "test.topology/1", "schema_revision": "1", "side_effect_class": "pure", "input_ports": {}, "output_ports": {"semantic": "Topology/1"}}
	var presentation_spec := {"id": "test.presentation/1", "schema_revision": "1", "side_effect_class": "pure", "input_ports": {"topology": "Topology/1"}, "output_ports": {"presentation": "Visual/1"}}
	_assert(registry.register_operator(topology_spec, Callable(self, "_build_topology")).get("ok", false), "topology operator registration")
	_assert(registry.register_operator(presentation_spec, Callable(self, "_build_presentation")).get("ok", false), "presentation operator registration")
	var recipe := _recipe()
	var cache = CACHE_SCRIPT.new("user://worldgen/cache_acceptance_%d" % Time.get_ticks_usec())
	var first := _execute(recipe, registry, cache)
	_assert(first.get("ok", false), "cold build succeeds")
	_assert(_hit_count(first) == 0, "cold build has no cache hits")
	var first_build_evidence: Array = first.get("evidence", []).duplicate(true)
	var warm := _execute(recipe, registry, cache)
	_assert(warm.get("ok", false), "warm build succeeds")
	_assert(_hit_count(warm) == 2, "warm build reuses both stages")
	_assert(warm.get("evidence", []) == first_build_evidence, "cache metrics do not poison deterministic provenance")
	var first_topology_key := ""
	for metric: Dictionary in first.get("execution_metrics", []):
		if String(metric.get("stage_id", "")) == "topology": first_topology_key = String(metric.get("cache_key", ""))
	var corrupt_path: String = cache._entry_path(first_topology_key)
	var corrupt_file := FileAccess.open(corrupt_path, FileAccess.WRITE)
	corrupt_file.store_string("{")
	corrupt_file.close()
	var after_corruption := _execute(recipe, registry, cache)
	_assert(after_corruption.get("ok", false), "corrupt cache entry falls back to a fresh stage")
	_assert(not _stage_hit(after_corruption, "topology"), "corrupt cached output is rejected and rebuilt")
	var palette_edit := _recipe()
	palette_edit["stages"][1]["parameters"]["palette_id"] = "summer"
	var palette_result := _execute(palette_edit, registry, cache)
	_assert(palette_result.get("ok", false), "palette edit build succeeds")
	_assert(_stage_hit(palette_result, "topology"), "palette-only edit reuses topology")
	_assert(not _stage_hit(palette_result, "presentation"), "palette edit rebuilds presentation")
	var door_edit := _recipe()
	door_edit["stages"][0]["parameters"]["door_revision"] = 2
	var door_result := _execute(door_edit, registry, cache)
	_assert(door_result.get("ok", false), "door edit build succeeds")
	_assert(not _stage_hit(door_result, "topology"), "door edit invalidates topology/access stage")
	var candidate_edit := _recipe()
	candidate_edit["stages"][0]["allowed_candidates"] = ["wall_A", "wall_B"]
	var candidate_result := _execute(candidate_edit, registry, cache)
	_assert(candidate_result.get("ok", false), "candidate-set edit build succeeds")
	_assert(not _stage_hit(candidate_result, "topology"), "new allowed candidate invalidates prior solve")
	var cancelled_recipe := _recipe()
	cancelled_recipe["id"] = "cancelled_cache_acceptance"
	_cancel_after_topology = true
	var cancelled := _execute(cancelled_recipe, registry, cache, Callable(self, "_cancel_requested"))
	_cancel_after_topology = false
	_assert(not cancelled.get("ok", false) and String(cancelled.get("status", "")) == "CANCELLED", "mid-stage cancellation aborts the candidate")
	var retry := _execute(cancelled_recipe, registry, cache)
	_assert(retry.get("ok", false), "retry after cancellation succeeds")
	_assert(not _stage_hit(retry, "topology"), "cancelled stage output was not cached")
	if _failures.is_empty():
		print("WORLDGEN_CACHE_TESTS_OK cold=2 warm=2 palette=topology_reused door=invalidated candidates=invalidated corruption=rebuilt cancellation=not_cached provenance=stable")
		registry = null
		cache = null
		quit(0)
	else:
		for failure: String in _failures: push_error(failure)
		registry = null
		cache = null
		quit(1)

var _failures: Array[String] = []
var _cancel_after_topology := false

func _recipe() -> Dictionary:
	return {"schema": "worldgen.recipe/1", "id": "cache_acceptance", "source_revision": 1, "coordinate_frame": {}, "capabilities": {},
		"stages": [
			{"id": "topology", "operator": "test.topology/1", "inputs": {}, "parameters": {"door_revision": 1}, "operation_budget": 20, "allowed_candidates": ["wall_A"]},
			{"id": "presentation", "operator": "test.presentation/1", "inputs": {"topology": "topology.semantic"}, "parameters": {"palette_id": "spring"}, "operation_budget": 10}
		], "outputs": {"semantic": "topology.semantic", "presentation": "presentation.presentation"}}

func _execute(recipe: Dictionary, registry: RefCounted, cache: RefCounted, cancel := Callable()) -> Dictionary:
	var compiled: Dictionary = COMPILER_SCRIPT.compile_recipe(recipe, registry)
	if not compiled.get("ok", false):
		return {"ok": false, "errors": compiled.get("errors", [])}
	return EXECUTOR_SCRIPT.execute(compiled, registry, cancel, cache)

func _build_topology(request: Dictionary) -> Dictionary:
	var revision := int(request.get("parameters", {}).get("door_revision", 1))
	if String(request.get("scope_id", "")) == "cancelled_cache_acceptance": _cancel_after_topology = true
	return {"ok": true, "outputs": {"semantic": {"type": "Topology/1", "data": {"door_revision": revision, "chosen_asset": "wall_A"}}}, "operation_count": 4}

func _cancel_requested() -> bool:
	return _cancel_after_topology

func _build_presentation(request: Dictionary) -> Dictionary:
	var topology: Dictionary = request.get("inputs", {}).get("topology", {})
	var palette := String(request.get("parameters", {}).get("palette_id", "spring"))
	return {"ok": true, "outputs": {"presentation": {"type": "Visual/1", "data": {"topology_digest": CANONICAL_SCRIPT.sha256(topology), "palette_id": palette}}}, "operation_count": 2}

func _hit_count(result: Dictionary) -> int:
	var count := 0
	for metric: Dictionary in result.get("execution_metrics", []):
		if bool(metric.get("cache_hit", false)): count += 1
	return count

func _stage_hit(result: Dictionary, stage_id: String) -> bool:
	for metric: Dictionary in result.get("execution_metrics", []):
		if String(metric.get("stage_id", "")) == stage_id: return bool(metric.get("cache_hit", false))
	return false

func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("E_CACHE_TEST: %s" % message)
