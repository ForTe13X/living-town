extends SceneTree
## Allowlist, patch provenance and output-diff classification acceptance checks.

const EDIT_SCRIPT := preload("res://addons/worldgen/core/edit_command.gd")
const DIFF_SCRIPT := preload("res://addons/worldgen/core/diff_classifier.gd")

func _initialize() -> void:
	var recipe := {"schema": "worldgen.recipe/1", "id": "test_town", "source_revision": 4,
		"stages": [{"id": "layout", "operator": "test.layout/1", "inputs": {}, "parameters": {"style_ref": "summer"}}],
		"outputs": {"semantic": "layout.semantic", "presentation": "layout.presentation"}}
	var package := _package(0, "summer")
	var visual_patch := {"schema": "worldgen.edit_patch/1", "patch_id": "palette-1", "base_revision": 4, "declared_class": "visual",
		"changes": [{"path": "stages/layout/parameters/style_ref", "value": "winter"}]}
	var prepared: Dictionary = EDIT_SCRIPT.prepare_patch(recipe, visual_patch, package)
	_assert(prepared.get("ok", false), "allowlisted visual patch prepares")
	_assert(int(prepared.get("source_revision_after", -1)) == 5, "draft increments source revision")
	_assert(prepared.get("dirty_scope") == "presentation_only", "visual edit has presentation scope")
	_assert(prepared.get("protected_ids", []) == ["house_a", "node_a", "road_main"], "nested anchors are captured and sorted")
	_assert(recipe["stages"][0]["parameters"]["style_ref"] == "summer", "base recipe remains isolated")
	var palette_candidate := _package(0, "winter")
	var visual_validation: Dictionary = EDIT_SCRIPT.validate_candidate(prepared, prepared.get("candidate_recipe", {}), package, palette_candidate)
	_assert(visual_validation.get("ok", false) and visual_validation.get("actual_class") == "visual", "prepared edit binds to actual visual output diff")
	var misclassified := visual_patch.duplicate(true)
	misclassified["changes"] = [{"path": "stages/layout/parameters/door_position", "value": [3, 4]}]
	_assert(not EDIT_SCRIPT.prepare_patch(recipe, misclassified, package).get("ok", false), "semantic door patch cannot claim visual class")
	var stale := visual_patch.duplicate(true)
	stale["base_revision"] = 3
	_assert(not EDIT_SCRIPT.prepare_patch(recipe, stale, package).get("ok", false), "stale base revision rejected")
	var semantic_after := _package(1, "summer")
	var semantic_diff: Dictionary = DIFF_SCRIPT.classify_packages(package, semantic_after, "semantic")
	_assert(semantic_diff.get("ok", false), "actual door relocation classified semantic")
	_assert(semantic_diff.get("changed_ids", []) == ["house_a"], "diff reports changed building ID")
	_assert(bool(semantic_diff.get("requires_global_validation", false)), "semantic diff requires global validation")
	var nested_after := _package(0, "summer")
	nested_after["semantic"]["topology"]["road_nodes"][0]["at"] = [3, 3]
	var nested_diff: Dictionary = DIFF_SCRIPT.classify_packages(package, nested_after, "semantic")
	_assert(nested_diff.get("changed_ids", []) == ["node_a"], "nested coastal road IDs are diffed")
	_assert(not DIFF_SCRIPT.classify_packages(package, semantic_after, "visual").get("ok", false), "actual semantic diff cannot be downgraded to visual")
	var door_patch := {"schema": "worldgen.edit_patch/1", "patch_id": "door-1", "base_revision": 4, "declared_class": "semantic",
		"changes": [{"path": "stages/layout/parameters/door_position", "value": [1, 2]}]}
	var door_prepared: Dictionary = EDIT_SCRIPT.prepare_patch(recipe, door_patch, package)
	_assert(door_prepared.get("ok", false), "semantic door patch prepares")
	var door_validation: Dictionary = EDIT_SCRIPT.validate_candidate(door_prepared, door_prepared.get("candidate_recipe", {}), package, semantic_after)
	_assert(door_validation.get("ok", false) and door_validation.get("actual_class") == "semantic", "door patch requires semantic output validation")
	var spoofed_package := _package(1, "winter")
	var spoofed_visual: Dictionary = EDIT_SCRIPT.validate_candidate(prepared, prepared.get("candidate_recipe", {}), package, spoofed_package)
	_assert(not spoofed_visual.get("ok", false), "visual edit cannot bypass access checks after structural output changes")
	var visual_after := _package(0, "winter")
	var visual_diff: Dictionary = DIFF_SCRIPT.classify_packages(package, visual_after, "visual")
	_assert(visual_diff.get("ok", false) and visual_diff.get("actual_class") == "visual", "palette output diff stays presentation-only")
	_assert(not bool(visual_diff.get("requires_global_validation", true)), "visual-only diff does not trigger semantic global validation")
	if _failures.is_empty():
		print("WORLDGEN_EDIT_TESTS_OK patch_allowlist=accepted misclassification=blocked stale_revision=blocked anchors=captured semantic_diff=global visual_diff=presentation_only")
		quit(0)
	else:
		for failure: String in _failures: push_error(failure)
		quit(1)

var _failures: Array[String] = []

func _package(entry_x: int, palette: String) -> Dictionary:
	return {"schema": "WorldPackage/1", "world_id": "test_town",
		"semantic": {"buildings": [{"id": "house_a", "entry": {"position": [entry_x, 2]}}], "roads": [{"id": "road_main"}],
			"topology": {"road_nodes": [{"id": "node_a", "at": [2, 3]}]}},
		"presentation": {"palette_id": palette}}

func _assert(condition: bool, message: String) -> void:
	if not condition: _failures.append("E_EDIT_TEST: %s" % message)
