extends SceneTree
## Local repair scope, pin, boundary, budget, determinism and oracle checks.

const REPAIR := preload("res://addons/worldgen/operators/local_repair.gd")

func _initialize() -> void:
	var base := _request()
	var result: Dictionary = REPAIR.repair(base, Callable(self, "_validate_candidate"))
	_assert(result.get("ok", false) and result.get("status") == "ACCEPTED", "independent global oracle accepts feasible repair")
	_assert(result.get("changed_ids", []) == ["lot_a"], "only the dirty assignment changes")
	_assert(int(result.get("edit_count", -1)) == 1 and not bool(result.get("minimality_proven", true)), "reports actual edits without an optimality claim")
	_assert(int(result.get("candidate", {}).get("candidate_revision", -1)) == 10, "candidate revision advances from the frozen base")
	_assert(_box_for(result.get("candidate", {}), "lot_fixed") == [5, 1, 2, 2], "hard pinned placement stays fixed")
	_assert(_box_for(result.get("candidate", {}), "lot_untouched") == [0, 5, 2, 2], "unaffected placement stays fixed")
	_assert(result.get("candidate", {}).get("boundary_interfaces", {}) == base["boundary_interfaces"], "boundary interfaces remain frozen")
	var repeat: Dictionary = REPAIR.repair(base, Callable(self, "_validate_candidate"))
	_assert(repeat.get("candidate_sha256") == result.get("candidate_sha256"), "search result is deterministic")
	var old_preferred := _request()
	old_preferred["placements"][0]["box"] = [1, 1, 2, 2]
	old_preferred["candidate_assignments"]["lot_a"] = [[2, 1, 2, 2], [1, 1, 2, 2]]
	var preference_result: Dictionary = REPAIR.repair(old_preferred, Callable(self, "_validate_candidate"))
	_assert(preference_result.get("ok", false) and _box_for(preference_result.get("candidate", {}), "lot_a") == [1, 1, 2, 2], "old feasible assignment is preferred")
	var without_oracle: Dictionary = REPAIR.repair(base)
	_assert(without_oracle.get("status") == "CANDIDATE_REQUIRES_GLOBAL_VALIDATION", "local solve alone is not accepted")
	var fixed_boundary := _request()
	fixed_boundary["candidate_assignments"]["lot_a"] = [[4, 1, 2, 2]]
	var unsat: Dictionary = REPAIR.repair(fixed_boundary)
	_assert(unsat.get("status") == "UNSAT_WITH_FIXED_BOUNDARY", "local exhaustion is scoped unsat")
	_assert(not bool(unsat.get("diagnostic", {}).get("global_unsat_claimed", true)), "fixed-boundary failure does not claim global impossibility")
	var exhausted := _request()
	exhausted["operation_budget"] = 1
	exhausted["candidate_assignments"]["lot_a"] = [[4, 1, 2, 2], [2, 1, 2, 2], [1, 1, 2, 2]]
	_assert(REPAIR.repair(exhausted).get("status") == "BUDGET_EXCEEDED", "search budget exhaustion is distinct from unsat")
	var hidden_reroll := _request()
	hidden_reroll["candidate_assignments"]["lot_untouched"] = [[1, 5, 2, 2]]
	_assert(REPAIR.repair(hidden_reroll).get("status") == "INVALID_REQUEST", "candidate assignment cannot widen declared scope")
	var forged_validator := REPAIR.repair(base, Callable(self, "_wrong_digest_validator"))
	_assert(forged_validator.get("status") == "GLOBAL_VALIDATION_FAILED", "oracle evidence must bind the candidate digest")
	var pinned_dirty := _request()
	pinned_dirty["dirty_ids"] = ["lot_fixed"]
	pinned_dirty["candidate_assignments"] = {}
	var pin_result: Dictionary = REPAIR.repair(pinned_dirty, Callable(self, "_validate_candidate"))
	_assert(pin_result.get("status") == "GLOBAL_VALIDATION_FAILED" and _box_for(pin_result.get("candidate", {}), "lot_fixed") == [5, 1, 2, 2], "a hard pin is never dropped to manufacture a solution")
	if _failures.is_empty():
		print("WORLDGEN_REPAIR_TESTS_OK locality=preserved pins=preserved boundary=preserved deterministic=yes global_oracle=required unsat_scope=local budget=distinct hidden_reroll=rejected")
		quit(0)
	else:
		for failure: String in _failures: push_error(failure)
		quit(1)

var _failures: Array[String] = []

func _request() -> Dictionary:
	return {"schema": "worldgen.local_repair_request/1", "scope_id": "east_parcels", "base_revision": 9,
		"extent": [0, 0, 10, 10], "boundary": [0, 0, 8, 8], "boundary_interfaces": {"west_road": [0, 4], "north_path": [4, 0]},
		"placements": [{"id": "lot_a", "box": [4, 1, 2, 2]}, {"id": "lot_fixed", "box": [5, 1, 2, 2]}, {"id": "lot_untouched", "box": [0, 5, 2, 2]}],
		"dirty_ids": ["lot_a"], "hard_pins": ["lot_fixed"], "protected_ids": ["lot_untouched"],
		"candidate_assignments": {"lot_a": [[4, 1, 2, 2], [2, 1, 2, 2]]}, "operation_budget": 100}

func _validate_candidate(candidate: Dictionary, digest: String) -> Dictionary:
	var placements: Array = candidate.get("placements", [])
	for i in range(placements.size()):
		for j in range(i + 1, placements.size()):
			if _overlaps(placements[i]["box"], placements[j]["box"]):
				return {"ok": false, "candidate_sha256": digest, "errors": ["E_ORACLE_OVERLAP"]}
	return {"ok": true, "candidate_sha256": digest, "evidence_id": "test_global_geometry_oracle"}

func _wrong_digest_validator(_candidate: Dictionary, _digest: String) -> Dictionary:
	return {"ok": true, "candidate_sha256": "bad", "evidence_id": "forged"}

func _box_for(candidate: Dictionary, id: String) -> Array:
	for placement: Dictionary in candidate.get("placements", []):
		if String(placement.get("id", "")) == id: return placement.get("box", [])
	return []

func _overlaps(a: Array, b: Array) -> bool:
	return int(a[0]) < int(b[0]) + int(b[2]) and int(b[0]) < int(a[0]) + int(a[2]) and int(a[1]) < int(b[1]) + int(b[3]) and int(b[1]) < int(a[1]) + int(a[3])

func _assert(condition: bool, message: String) -> void:
	if not condition: _failures.append("E_REPAIR_TEST: %s" % message)
