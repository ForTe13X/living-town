extends RefCounted
class_name WorldGenLocalRepair
## Finite deterministic rectangle repair. It never changes placements outside dirty_ids.

const REQUEST_SCHEMA := "worldgen.local_repair_request/1"
const RESULT_SCHEMA := "worldgen.local_repair_candidate/1"

static func repair(request: Variant, global_validator := Callable()) -> Dictionary:
	if not request is Dictionary or String(request.get("schema", "")) != REQUEST_SCHEMA:
		return _failure("INVALID_REQUEST", "E_REPAIR_SCHEMA: expected %s" % REQUEST_SCHEMA, "world")
	for key: String in request:
		if key not in ["schema", "scope_id", "base_revision", "extent", "boundary", "boundary_interfaces", "placements", "dirty_ids", "hard_pins", "protected_ids", "candidate_assignments", "operation_budget"]:
			return _failure("INVALID_REQUEST", "E_REPAIR_FIELD: unsupported request field %s" % key, String(request.get("scope_id", "world")))
	var canonical_errors := WorldGenCanonical.validate_value(request)
	if not canonical_errors.is_empty(): return {"ok": false, "status": "INVALID_REQUEST", "errors": canonical_errors}
	var scope_id := String(request.get("scope_id", ""))
	if scope_id.is_empty(): return _failure("INVALID_REQUEST", "E_REPAIR_SCOPE: scope_id is required", "world")
	var extent: Variant = request.get("extent")
	var boundary: Variant = request.get("boundary")
	if not _valid_rect(extent) or not _valid_rect(boundary) or not _inside(boundary, extent):
		return _failure("INVALID_REQUEST", "E_REPAIR_BOUNDS: extent and boundary must be positive contained rectangles", scope_id)
	var raw_placements: Variant = request.get("placements")
	var raw_dirty: Variant = request.get("dirty_ids")
	var raw_pins: Variant = request.get("hard_pins", [])
	var protected: Variant = request.get("protected_ids", [])
	var assignments: Variant = request.get("candidate_assignments")
	var boundary_interfaces: Variant = request.get("boundary_interfaces", {})
	if not raw_placements is Array or raw_placements.is_empty() or not raw_dirty is Array or raw_dirty.is_empty() or not raw_pins is Array or not protected is Array or not assignments is Dictionary or not boundary_interfaces is Dictionary:
		return _failure("INVALID_REQUEST", "E_REPAIR_INPUT: placements, dirty_ids, hard_pins, protected_ids, boundary_interfaces and candidate_assignments have invalid shapes", scope_id)
	var placements := {}
	for raw: Variant in raw_placements:
		if not raw is Dictionary:
			return _failure("INVALID_REQUEST", "E_REPAIR_PLACEMENT: each placement must be an object", scope_id)
		var id := String(raw.get("id", ""))
		var box: Variant = raw.get("box")
		if id.is_empty() or placements.has(id) or not _valid_rect(box) or not _inside(box, extent):
			return _failure("INVALID_REQUEST", "E_REPAIR_PLACEMENT: duplicate id or invalid box for %s" % id, scope_id)
		placements[id] = box.duplicate()
	var dirty := _unique_strings(raw_dirty)
	var pins := _unique_strings(raw_pins)
	var protected_ids := _unique_strings(protected)
	if dirty.size() != raw_dirty.size() or pins.size() != raw_pins.size() or protected_ids.size() != protected.size():
		return _failure("INVALID_REQUEST", "E_REPAIR_IDS: IDs must be unique non-empty strings", scope_id)
	dirty.sort(); pins.sort(); protected_ids.sort()
	for id: String in dirty:
		if not placements.has(id): return _failure("INVALID_REQUEST", "E_REPAIR_DIRTY_ID: unknown dirty id %s" % id, scope_id)
	for id: String in pins + protected_ids:
		if not placements.has(id): return _failure("INVALID_REQUEST", "E_REPAIR_ANCHOR: unknown protected or pinned id %s" % id, scope_id)
	for assignment_id: Variant in assignments:
		if not dirty.has(String(assignment_id)):
			return _failure("INVALID_REQUEST", "E_REPAIR_SCOPE: candidate assignment for non-dirty id %s would widen the repair region" % assignment_id, scope_id, [String(assignment_id)])
	var movable_dirty: Array[String] = []
	for id: String in dirty:
		if not pins.has(id) and not protected_ids.has(id): movable_dirty.append(id)
	var fixed_ids: Array[String] = []
	for id: String in placements:
		if not movable_dirty.has(id): fixed_ids.append(id)
	fixed_ids.sort()
	var domains := {}
	for id: String in movable_dirty:
		var raw_domain: Variant = assignments.get(id, [])
		if not raw_domain is Array or raw_domain.is_empty():
			return _failure("INVALID_REQUEST", "E_REPAIR_DOMAIN: no finite candidate set for %s" % id, scope_id, [id])
		var domain: Array = []
		for candidate: Variant in raw_domain:
			if not _valid_rect(candidate) or not _inside(candidate, extent):
				return _failure("INVALID_REQUEST", "E_REPAIR_DOMAIN: candidate box for %s is invalid" % id, scope_id, [id])
			if _inside(candidate, boundary) and not domain.has(candidate): domain.append(candidate.duplicate())
		var old_box: Array = placements[id]
		domain.sort_custom(func(a: Array, b: Array) -> bool:
			var old_a := a == old_box
			var old_b := b == old_box
			if old_a != old_b: return old_a
			return WorldGenCanonical.canonical_json(a) < WorldGenCanonical.canonical_json(b))
		domains[id] = domain
	# Deterministic MRV order with stable ID tie-breaking.
	movable_dirty.sort_custom(func(a: String, b: String) -> bool:
		var domain_a: Array = domains[a]
		var domain_b: Array = domains[b]
		return domain_a.size() < domain_b.size() if domain_a.size() != domain_b.size() else a < b)
	var budget := int(request.get("operation_budget", 10000))
	if budget < 1: return _budget_failure(scope_id, 0, budget, dirty)
	var fixed_boxes: Array = []
	for id: String in fixed_ids: fixed_boxes.append(placements[id])
	var chosen := {}
	var search_state := {"operations": 0, "exhausted": false}
	var solved := _search(0, movable_dirty, domains, fixed_boxes, chosen, budget, search_state)
	var operation_count := int(search_state["operations"])
	if not solved:
		if bool(search_state["exhausted"]): return _budget_failure(scope_id, operation_count, budget, dirty)
		return {"ok": false, "status": "UNSAT_WITH_FIXED_BOUNDARY", "errors": ["E_REPAIR_UNSAT_FIXED_BOUNDARY: bounded region has no placement assignment"],
			"diagnostic": {"code": "UNSAT_WITH_FIXED_BOUNDARY", "scope_id": scope_id, "object_ids": dirty, "constraint_refs": ["fixed_boundary", "hard_pins", "non_overlap"],
			"searched_budget": operation_count, "global_unsat_claimed": false, "permitted_next_actions": ["request_scope_expansion"]}}
	var final_map := placements.duplicate(true)
	for id: String in chosen: final_map[id] = chosen[id].duplicate()
	var result_placements: Array = []
	var changed_ids: Array[String] = []
	var edit_count := 0
	var all_ids: Array = final_map.keys()
	all_ids.sort()
	for id_variant: Variant in all_ids:
		var id := String(id_variant)
		result_placements.append({"id": id, "box": final_map[id].duplicate()})
		if placements[id] != final_map[id]:
			changed_ids.append(id)
			edit_count += 1
	for id: String in pins + protected_ids:
		if not final_map.has(id) or final_map[id] != placements[id]:
			return _failure("GLOBAL_VALIDATION_FAILED", "E_REPAIR_ANCHOR_CHANGED: protected placement changed for %s" % id, scope_id, [id])
	var candidate := {"schema": RESULT_SCHEMA, "scope_id": scope_id, "base_revision": int(request.get("base_revision", 0)), "candidate_revision": int(request.get("base_revision", 0)) + 1,
		"extent": extent.duplicate(), "boundary": boundary.duplicate(), "boundary_interfaces": boundary_interfaces.duplicate(true),
		"placements": result_placements}
	var candidate_digest := WorldGenCanonical.sha256(candidate)
	var result := {"ok": true, "status": "CANDIDATE_REQUIRES_GLOBAL_VALIDATION", "candidate": candidate, "candidate_sha256": candidate_digest,
		"changed_ids": changed_ids, "edit_count": edit_count, "minimality_proven": false, "operation_count": operation_count,
		"boundary_sha256": WorldGenCanonical.sha256({"boundary": boundary, "interfaces": boundary_interfaces}), "global_unsat_claimed": false}
	if not global_validator.is_valid():
		result["permitted_next_actions"] = ["run_global_validation"]
		return result
	var validation: Variant = global_validator.call(candidate.duplicate(true), candidate_digest)
	if not validation is Dictionary or not bool(validation.get("ok", false)) or String(validation.get("candidate_sha256", "")) != candidate_digest:
		return {"ok": false, "status": "GLOBAL_VALIDATION_FAILED", "errors": validation.get("errors", ["E_REPAIR_GLOBAL_VALIDATION: independent global evidence is missing or bound to another candidate"]) if validation is Dictionary else ["E_REPAIR_GLOBAL_VALIDATION: validator did not return an object"],
			"candidate": candidate, "candidate_sha256": candidate_digest, "changed_ids": changed_ids, "operation_count": operation_count}
	result["status"] = "ACCEPTED"
	result["global_validation_evidence"] = validation
	return result

static func _search(index: int, ids: Array[String], domains: Dictionary, fixed_boxes: Array, chosen: Dictionary, budget: int, state: Dictionary) -> bool:
	if index >= ids.size(): return true
	var id := ids[index]
	for candidate: Array in domains[id]:
		state["operations"] = int(state["operations"]) + 1
		if int(state["operations"]) > budget:
			state["exhausted"] = true
			return false
		var blocked := false
		for fixed_box: Array in fixed_boxes:
			if _overlaps(candidate, fixed_box): blocked = true; break
		if not blocked:
			for selected: Array in chosen.values():
				if _overlaps(candidate, selected): blocked = true; break
		if blocked: continue
		chosen[id] = candidate
		if _search(index + 1, ids, domains, fixed_boxes, chosen, budget, state): return true
		chosen.erase(id)
		if bool(state["exhausted"]): return false
	return false

static func _valid_rect(value: Variant) -> bool:
	if not value is Array or value.size() != 4: return false
	for component: Variant in value:
		if typeof(component) != TYPE_INT: return false
	return int(value[2]) > 0 and int(value[3]) > 0

static func _inside(inner: Array, outer: Array) -> bool:
	return int(inner[0]) >= int(outer[0]) and int(inner[1]) >= int(outer[1]) and int(inner[0]) + int(inner[2]) <= int(outer[0]) + int(outer[2]) and int(inner[1]) + int(inner[3]) <= int(outer[1]) + int(outer[3])

static func _overlaps(a: Array, b: Array) -> bool:
	return int(a[0]) < int(b[0]) + int(b[2]) and int(b[0]) < int(a[0]) + int(a[2]) and int(a[1]) < int(b[1]) + int(b[3]) and int(b[1]) < int(a[1]) + int(a[3])

static func _unique_strings(value: Array) -> Array[String]:
	var result: Array[String] = []
	for item: Variant in value:
		if not item is String or String(item).is_empty() or result.has(String(item)): continue
		result.append(String(item))
	return result

static func _budget_failure(scope_id: String, operations: int, budget: int, ids: Array[String]) -> Dictionary:
	return {"ok": false, "status": "BUDGET_EXCEEDED", "errors": ["E_REPAIR_BUDGET: bounded repair exhausted its deterministic operation budget"],
		"diagnostic": {"code": "BUDGET_EXCEEDED", "scope_id": scope_id, "object_ids": ids, "constraint_refs": ["operation_budget"], "searched_budget": operations,
		"budget": budget, "global_unsat_claimed": false, "permitted_next_actions": ["retry_with_declared_budget", "request_scope_expansion"]}}

static func _failure(status: String, message: String, scope_id: String, ids: Array = []) -> Dictionary:
	return {"ok": false, "status": status, "errors": [message], "diagnostic": {"code": status, "scope_id": scope_id, "object_ids": ids, "constraint_refs": [], "searched_budget": 0, "global_unsat_claimed": false, "permitted_next_actions": []}}
