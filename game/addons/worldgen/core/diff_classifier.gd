extends RefCounted
class_name WorldGenDiffClassifier
## Classifies actual package changes from canonical payload digests, not user labels.

static func classify_packages(before_package: Variant, after_package: Variant, declared_class := "") -> Dictionary:
	if not before_package is Dictionary or not after_package is Dictionary:
		return {"ok": false, "errors": ["E_DIFF_PACKAGE: both package snapshots must be objects"]}
	var before_semantic: Variant = before_package.get("semantic")
	var after_semantic: Variant = after_package.get("semantic")
	var before_visual: Variant = before_package.get("presentation")
	var after_visual: Variant = after_package.get("presentation")
	if not before_semantic is Dictionary or not after_semantic is Dictionary or not before_visual is Dictionary or not after_visual is Dictionary:
		return {"ok": false, "errors": ["E_DIFF_SECTIONS: semantic and presentation sections are required"]}
	var semantic_changed := WorldGenCanonical.sha256(before_semantic) != WorldGenCanonical.sha256(after_semantic)
	var visual_changed := WorldGenCanonical.sha256(before_visual) != WorldGenCanonical.sha256(after_visual)
	var actual_class := "mixed" if semantic_changed and visual_changed else "semantic" if semantic_changed else "visual" if visual_changed else "none"
	var declaration_matches := declared_class.is_empty() or (declared_class == "visual" and actual_class == "visual") or (declared_class == "semantic" and actual_class in ["semantic", "mixed"])
	if not declaration_matches:
		return {"ok": false, "errors": ["E_DIFF_CLASS_MISMATCH: declared %s but actual package change is %s" % [declared_class, actual_class]], "actual_class": actual_class}
	var changed_ids: Array[String] = []
	if semantic_changed: changed_ids.assign(_changed_ids(before_semantic, after_semantic))
	var dependencies: Array[String] = []
	match actual_class:
		"visual": dependencies.assign(["presentation"])
		"semantic": dependencies.assign(["topology", "access", "capacity", "anchors", "global_validation"])
		"mixed": dependencies.assign(["topology", "access", "capacity", "anchors", "presentation", "global_validation"])
		_: dependencies.clear()
	return {"ok": true, "actual_class": actual_class, "semantic_changed": semantic_changed, "presentation_changed": visual_changed,
		"semantic_sha256_before": WorldGenCanonical.sha256(before_semantic), "semantic_sha256_after": WorldGenCanonical.sha256(after_semantic),
		"presentation_sha256_before": WorldGenCanonical.sha256(before_visual), "presentation_sha256_after": WorldGenCanonical.sha256(after_visual),
		"changed_ids": changed_ids, "dependency_closure": dependencies, "requires_global_validation": semantic_changed}

static func _changed_ids(before_semantic: Dictionary, after_semantic: Dictionary) -> Array[String]:
	var before_by_id := {}
	var after_by_id := {}
	_collect_id_digests(before_semantic, before_by_id)
	_collect_id_digests(after_semantic, after_by_id)
	var changed := {}
	for id: String in before_by_id:
		if not after_by_id.has(id) or WorldGenCanonical.sha256(before_by_id[id]) != WorldGenCanonical.sha256(after_by_id[id]): changed[id] = true
	for id: String in after_by_id:
		if not before_by_id.has(id): changed[id] = true
	var result: Array[String] = []
	for id: Variant in changed.keys(): result.append(String(id))
	result.sort()
	return result

static func _collect_id_digests(value: Variant, result: Dictionary) -> void:
	if value is Dictionary:
		var id := String(value.get("id", ""))
		if not id.is_empty():
			var digests: Array = result.get(id, [])
			digests.append(WorldGenCanonical.sha256(value))
			digests.sort()
			result[id] = digests
		for key: Variant in value: _collect_id_digests(value[key], result)
	elif value is Array:
		for item: Variant in value: _collect_id_digests(item, result)
