extends RefCounted
class_name WorldGenEditCommand
## Allowlisted immutable recipe patch preparation with source and anchor provenance.

const PATCH_SCHEMA := "worldgen.edit_patch/1"
const DIFF_SCRIPT := preload("res://addons/worldgen/core/diff_classifier.gd")
const VISUAL_FIELDS := ["palette_id", "visual_seed", "style_ref", "district_ref", "roof_profile", "texture_manifest"]
const SEMANTIC_FIELDS := ["door", "door_position", "entry", "doors", "allowed_candidates", "pins", "boundary", "extent_cells", "size_cells", "buildings", "roads", "parcels", "rooms", "crossings"]

static func prepare_patch(base_recipe: Variant, patch: Variant, base_package: Variant) -> Dictionary:
	if not base_recipe is Dictionary or String(base_recipe.get("schema", "")) != "worldgen.recipe/1":
		return _fail("E_EDIT_RECIPE: base recipe schema is invalid")
	if not patch is Dictionary or String(patch.get("schema", "")) != PATCH_SCHEMA:
		return _fail("E_EDIT_PATCH_SCHEMA: expected %s" % PATCH_SCHEMA)
	for key: String in patch:
		if key not in ["schema", "patch_id", "base_revision", "declared_class", "changes"]:
			return _fail("E_EDIT_PATCH_FIELD: unsupported field %s" % key)
	if not base_package is Dictionary or String(base_package.get("world_id", "")) != String(base_recipe.get("id", "")):
		return _fail("E_EDIT_BASE_PACKAGE: package does not belong to this recipe")
	var base_revision := int(base_recipe.get("source_revision", 0))
	if not base_recipe.get("stages", []) is Array or base_recipe["stages"].is_empty():
		return _fail("E_EDIT_RECIPE_STAGES: base recipe must contain stages")
	if int(patch.get("base_revision", -1)) != base_revision:
		return _fail("E_EDIT_STALE: patch base revision does not match recipe")
	var declared_class := String(patch.get("declared_class", ""))
	if declared_class not in ["visual", "semantic"]:
		return _fail("E_EDIT_CLASS: declared_class must be visual or semantic")
	var changes: Variant = patch.get("changes", [])
	if not changes is Array or changes.is_empty() or changes.size() > 64:
		return _fail("E_EDIT_CHANGES: changes must contain 1..64 entries")
	var candidate: Dictionary = base_recipe.duplicate(true)
	var seen_paths := {}
	var changed_classes: Array[String] = []
	for raw_change: Variant in changes:
		if not raw_change is Dictionary or raw_change.size() != 2 or not raw_change.has("path") or not raw_change.has("value"):
			return _fail("E_EDIT_CHANGE: each change requires only path and value")
		var path := String(raw_change.get("path", ""))
		if seen_paths.has(path): return _fail("E_EDIT_DUPLICATE: duplicate patch path %s" % path)
		seen_paths[path] = true
		var parts := path.split("/", false)
		if parts.size() != 4 or parts[0] != "stages" or parts[2] != "parameters":
			return _fail("E_EDIT_PATH: only stage parameter paths are patchable")
		var field := parts[3]
		var field_class := "visual" if VISUAL_FIELDS.has(field) else "semantic" if SEMANTIC_FIELDS.has(field) else ""
		if field_class.is_empty(): return _fail("E_EDIT_FIELD: field %s is not allowlisted" % field)
		if field_class != declared_class:
			return _fail("E_EDIT_CLASS_BYPASS: %s belongs to %s edits, not %s" % [field, field_class, declared_class])
		var stage_index := _find_stage_index(candidate, parts[1])
		if stage_index < 0: return _fail("E_EDIT_STAGE: stage %s does not exist" % parts[1])
		var stage: Dictionary = candidate["stages"][stage_index]
		var parameters: Dictionary = stage.get("parameters", {}).duplicate(true)
		parameters[field] = raw_change["value"].duplicate(true) if raw_change["value"] is Dictionary or raw_change["value"] is Array else raw_change["value"]
		stage["parameters"] = parameters
		candidate["stages"][stage_index] = stage
		if not changed_classes.has(field_class): changed_classes.append(field_class)
	var validation_errors := WorldGenCanonical.validate_value(candidate)
	if not validation_errors.is_empty(): return {"ok": false, "errors": validation_errors}
	candidate["source_revision"] = base_revision + 1
	var protected_ids := _collect_anchors(base_package.get("semantic", {}))
	var dependency_closure: Array[String] = []
	if declared_class == "visual": dependency_closure.assign(["presentation"])
	else: dependency_closure.assign(["topology", "access", "capacity", "anchors", "global_validation"])
	return {"ok": true, "candidate_recipe": candidate, "patch_id": String(patch.get("patch_id", "")), "source_revision_before": base_revision,
		"source_revision_after": base_revision + 1, "declared_class": declared_class, "changed_classes": changed_classes,
		"dirty_scope": "presentation_only" if declared_class == "visual" else "global_semantic_closure",
		"dependency_closure": dependency_closure, "protected_ids": protected_ids,
		"base_recipe_sha256": WorldGenCanonical.sha256(base_recipe), "base_package_sha256": WorldGenCanonical.sha256(base_package)}

static func validate_candidate(prepared_edit: Variant, candidate_recipe: Variant, before_package: Variant, after_package: Variant) -> Dictionary:
	if not prepared_edit is Dictionary or not bool(prepared_edit.get("ok", false)):
		return _fail("E_EDIT_DRAFT: a prepared edit is required")
	if not candidate_recipe is Dictionary or WorldGenCanonical.sha256(candidate_recipe) != WorldGenCanonical.sha256(prepared_edit.get("candidate_recipe", {})):
		return _fail("E_EDIT_RECIPE_BINDING: candidate recipe differs from the prepared draft")
	if int(candidate_recipe.get("source_revision", -1)) != int(prepared_edit.get("source_revision_after", -2)):
		return _fail("E_EDIT_REVISION: candidate recipe revision differs from prepared draft")
	if not before_package is Dictionary or WorldGenCanonical.sha256(before_package) != String(prepared_edit.get("base_package_sha256", "")):
		return _fail("E_EDIT_BASE_BINDING: validation base differs from prepared package")
	if not after_package is Dictionary or String(after_package.get("world_id", "")) != String(before_package.get("world_id", "")):
		return _fail("E_EDIT_OUTPUT_WORLD: candidate package belongs to a different world")
	var classified: Dictionary = DIFF_SCRIPT.classify_packages(before_package, after_package, String(prepared_edit.get("declared_class", "")))
	if not classified.get("ok", false): return classified
	classified["candidate_recipe_sha256"] = WorldGenCanonical.sha256(candidate_recipe)
	classified["protected_ids"] = prepared_edit.get("protected_ids", []).duplicate()
	classified["source_revision"] = int(candidate_recipe["source_revision"])
	return classified

static func _find_stage_index(recipe: Dictionary, stage_id: String) -> int:
	for index in range(recipe.get("stages", []).size()):
		var stage: Variant = recipe["stages"][index]
		if stage is Dictionary and String(stage.get("id", "")) == stage_id: return index
	return -1

static func _collect_anchors(semantic: Variant) -> Array[String]:
	var anchor_set := {}
	var anchors: Array[String] = []
	_collect_anchor_ids(semantic, anchor_set)
	for anchor: Variant in anchor_set.keys(): anchors.append(String(anchor))
	anchors.sort()
	return anchors

static func _collect_anchor_ids(value: Variant, anchors: Dictionary) -> void:
	if value is Dictionary:
		var id := String(value.get("id", ""))
		if not id.is_empty(): anchors[id] = true
		for key: Variant in value: _collect_anchor_ids(value[key], anchors)
	elif value is Array:
		for item: Variant in value: _collect_anchor_ids(item, anchors)

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "errors": [message]}
