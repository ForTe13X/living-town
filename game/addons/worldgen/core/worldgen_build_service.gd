extends RefCounted
class_name WorldGenBuildService
## Main-thread-neutral package compiler shared by the CLI and editor authoring UI.

const REGISTRY_SCRIPT := preload("res://addons/worldgen/core/worldgen_operator_registry.gd")
const COMPILER_SCRIPT := preload("res://addons/worldgen/core/worldgen_recipe_compiler.gd")
const EXECUTOR_SCRIPT := preload("res://addons/worldgen/core/worldgen_stage_executor.gd")
const VALIDATOR_SCRIPT := preload("res://addons/worldgen/core/worldgen_package_validator.gd")
const CANONICAL_SCRIPT := preload("res://addons/worldgen/core/worldgen_canonical.gd")
const COASTAL_ADAPTER := preload("res://addons/worldgen/adapters/coastal/coastal_world_operator.gd")
const INLAND_OPERATOR := preload("res://addons/worldgen/operators/inland_layout_operator.gd")
const INTERIOR_OPERATOR := preload("res://addons/worldgen/operators/interior_program_operator.gd")

static func build_package(recipe: Variant, cache: RefCounted = null, cancel := Callable()) -> Dictionary:
	if not recipe is Dictionary:
		return {"ok": false, "status": "INVALID_RECIPE", "errors": ["E_BUILD_RECIPE: recipe must be an object"]}
	var registry = REGISTRY_SCRIPT.new()
	var owners: Array[RefCounted] = [COASTAL_ADAPTER.new(), INLAND_OPERATOR.new(), INTERIOR_OPERATOR.new()]
	for owner: RefCounted in owners:
		var registration: Dictionary = owner.register_into(registry)
		if not registration.get("ok", false): return {"ok": false, "status": "INVALID_RECIPE", "errors": [registration.get("error", "E_BUILD_REGISTER: operator registration failed")]}
	var compiled: Dictionary = COMPILER_SCRIPT.compile_recipe(recipe, registry)
	if not compiled.get("ok", false): return {"ok": false, "status": "INVALID_RECIPE", "errors": compiled.get("errors", [])}
	var result: Dictionary = EXECUTOR_SCRIPT.execute(compiled, registry, cancel, cache)
	if not result.get("ok", false): return result
	var semantic: Dictionary = result["outputs"].get("semantic", {}).get("data", {})
	var presentation: Dictionary = result["outputs"].get("presentation", {}).get("data", {})
	var package := {"schema": "WorldPackage/1", "world_id": String(recipe.get("id", "")),
		"coordinate_frame": recipe.get("coordinate_frame", {}), "capabilities": recipe.get("capabilities", {}),
		"semantic": semantic, "presentation": presentation,
		"provenance": {"recipe_sha256": CANONICAL_SCRIPT.sha256(recipe), "recipe_schema": String(recipe.get("schema", "")),
			"source_revision": int(recipe.get("source_revision", 0)), "build_stages": result["evidence"]},
		"digests": {"semantic_sha256": CANONICAL_SCRIPT.sha256(semantic), "presentation_sha256": CANONICAL_SCRIPT.sha256(presentation)}}
	var validation: Dictionary = VALIDATOR_SCRIPT.validate(package)
	if not validation.get("ok", false): return {"ok": false, "status": "GLOBAL_VALIDATION_FAILED", "errors": validation.get("errors", []), "validation": validation}
	return {"ok": true, "status": "VALIDATED_CANDIDATE", "package": package, "package_sha256": CANONICAL_SCRIPT.sha256(package),
		"build_id": CANONICAL_SCRIPT.sha256(package), "validation": validation, "evidence": result.get("evidence", []), "execution_metrics": result.get("execution_metrics", [])}
