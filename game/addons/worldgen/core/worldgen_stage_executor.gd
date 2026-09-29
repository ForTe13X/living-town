extends RefCounted
class_name WorldGenStageExecutor
## Stable sequential execution. The executor owns no scene nodes or simulation state.

const CACHE_SCRIPT := preload("res://addons/worldgen/core/build_cache.gd")
const VALIDATOR_SOURCE_PATH := "res://addons/worldgen/core/worldgen_package_validator.gd"

static func execute(compiled_recipe: Dictionary, registry: WorldGenOperatorRegistry, cancel: Callable = Callable(), cache: RefCounted = null) -> Dictionary:
	if not bool(compiled_recipe.get("ok", false)):
		return {"ok": false, "status": "INVALID_RECIPE", "errors": compiled_recipe.get("errors", [])}
	var artifacts := {}
	var evidence: Array = []
	var execution_metrics: Array = []
	var recipe: Dictionary = compiled_recipe["recipe"]
	var validator_source := FileAccess.get_file_as_string(VALIDATOR_SOURCE_PATH)
	var validator_digest := WorldGenCanonical.sha256(validator_source) if not validator_source.is_empty() else ""
	for stage: Dictionary in compiled_recipe["ordered_stages"]:
		if cancel.is_valid() and bool(cancel.call()):
			return {"ok": false, "status": "CANCELLED", "errors": ["E_JOB_CANCELLED: candidate was cancelled"], "evidence": evidence}
		var operator_id := String(stage["operator"])
		var spec := registry.get_spec(operator_id)
		var input_values := {}
		var input_digests := {}
		for port: String in stage.get("inputs", {}):
			var ref := String(stage["inputs"][port])
			var dot := ref.find(".")
			var source_id := ref.left(dot)
			var output_port := ref.substr(dot + 1)
			var artifact: Dictionary = artifacts.get(source_id, {}).get(output_port, {})
			if artifact.is_empty():
				return {"ok": false, "status": "FAILED", "errors": ["E_EXEC_ARTIFACT: unresolved %s" % ref], "evidence": evidence}
			input_values[port] = artifact["data"].duplicate(true)
			input_digests[port] = String(artifact["sha256"])
		var budget := int(stage.get("operation_budget", 100000))
		var parameters: Dictionary = stage.get("parameters", {}).duplicate(true)
		var identity := {"recipe_id": String(recipe.get("id", "")), "source_revision": int(recipe.get("source_revision", 0)),
			"operator_id": operator_id, "operator_spec_sha256": WorldGenCanonical.sha256(spec), "operator_schema": String(spec.get("schema_revision", "")),
			"validator_policy": String(stage.get("validator_policy", "worldgen.validator/1")),
			"validator_implementation_sha256": validator_digest, "input_digests_by_port": input_digests,
			"effective_parameters": parameters, "seed_policy": stage.get("seed_policy", {"mode": "none"}), "deterministic_budget": budget,
			"pins_digest": String(stage.get("pins_digest", WorldGenCanonical.sha256([]))), "boundary_digest": String(stage.get("boundary_digest", WorldGenCanonical.sha256([]))),
			"allowed_candidates": stage.get("allowed_candidates", []), "structural_pack_manifest": stage.get("structural_pack_manifest", {}),
			"visual_pack_manifest": stage.get("visual_pack_manifest", {})}
		var cache_key := ""
		var stage_result: Dictionary = {}
		var cache_hit := false
		# A cache hit is sound only when the registry could fingerprint the actual
		# implementation source. A missing source fingerprint disables caching.
		if cache != null and String(spec.get("implementation_sha256", "")).length() == 64 and validator_digest.length() == 64:
			cache_key = CACHE_SCRIPT.make_key(identity)
			var cached: Dictionary = cache.get_entry(cache_key)
			if cached.get("ok", false) and cached.get("hit", false):
				stage_result = {"ok": true, "outputs": cached["outputs"], "operation_count": int(cached.get("operation_count", 0))}
				cache_hit = true
		if stage_result.is_empty():
			stage_result = registry.run(operator_id, {"scope_id": String(recipe.get("id", "")), "stage_id": String(stage["id"]),
				"inputs": input_values, "parameters": parameters.duplicate(true), "source_revision": int(recipe.get("source_revision", 0)), "operation_budget": budget})
		if cancel.is_valid() and bool(cancel.call()):
			return {"ok": false, "status": "CANCELLED", "errors": ["E_JOB_CANCELLED: candidate was cancelled"], "evidence": evidence, "execution_metrics": execution_metrics}
		if not bool(stage_result.get("ok", false)):
			return {"ok": false, "status": "FAILED", "errors": stage_result.get("errors", ["E_STAGE_FAILED: %s" % stage["id"]]), "evidence": evidence}
		var outputs: Dictionary = stage_result.get("outputs", {})
		var expected: Dictionary = spec.get("output_ports", {})
		if outputs.size() != expected.size():
			return {"ok": false, "status": "FAILED", "errors": ["E_STAGE_OUTPUTS: %s output count mismatch" % stage["id"]], "evidence": evidence}
		artifacts[String(stage["id"])] = {}
		var normalized_outputs := {}
		for port: String in expected:
			if not outputs.has(port) or not outputs[port] is Dictionary:
				return {"ok": false, "status": "FAILED", "errors": ["E_STAGE_OUTPUT: %s missing typed output %s" % [stage["id"], port]], "evidence": evidence}
			var produced: Dictionary = outputs[port]
			if String(produced.get("type", "")) != String(expected[port]):
				return {"ok": false, "status": "FAILED", "errors": ["E_STAGE_OUTPUT_TYPE: %s.%s expected %s" % [stage["id"], port, expected[port]]], "evidence": evidence}
			var payload: Variant = produced.get("data")
			var value_errors := WorldGenCanonical.validate_value(payload)
			if not value_errors.is_empty():
				return {"ok": false, "status": "FAILED", "errors": value_errors, "evidence": evidence}
			var digest := WorldGenCanonical.sha256(payload)
			artifacts[String(stage["id"])][port] = {"type": String(expected[port]), "data": payload.duplicate(true), "sha256": digest}
			normalized_outputs[port] = {"type": String(expected[port]), "data": payload.duplicate(true)}
			evidence.append({"stage_id": String(stage["id"]), "operator_id": operator_id, "output_port": port, "sha256": digest,
				"operation_count": int(stage_result.get("operation_count", 0))})
		if cache != null and not cache_hit and not cache_key.is_empty() and bool(stage_result.get("ok", false)):
			cache.put_entry(cache_key, normalized_outputs, input_digests.values(), int(stage_result.get("operation_count", 0)))
		if not cache_key.is_empty():
			execution_metrics.append({"stage_id": String(stage["id"]), "cache_hit": cache_hit, "cache_key": cache_key})
	var emitted := {}
	for name: String in recipe.get("outputs", {}):
		var ref := String(recipe["outputs"][name])
		var dot := ref.find(".")
		if dot < 1 or not artifacts.has(ref.left(dot)) or not artifacts[ref.left(dot)].has(ref.substr(dot + 1)):
			return {"ok": false, "status": "FAILED", "errors": ["E_RECIPE_OUTPUT_REF: %s is unresolved" % ref], "evidence": evidence}
		emitted[name] = artifacts[ref.left(dot)][ref.substr(dot + 1)].duplicate(true)
	return {"ok": true, "status": "CANDIDATE", "outputs": emitted, "evidence": evidence, "execution_metrics": execution_metrics, "source_revision": int(recipe.get("source_revision", 0))}
