extends RefCounted
class_name WorldGenSemanticEditSession
## Owns detached canonical recipe snapshots; generated scene nodes are never undo state.

signal snapshot_changed(snapshot: Dictionary)

const SNAPSHOT_SCHEMA := "worldgen.semantic_edit_snapshot/1"
const RECIPE_SCHEMA := "worldgen.recipe/1"

var _snapshot: Dictionary = {}
var _state_epoch := 0
var _latest_job_id := 0

func initialize(recipe: Variant, build_id := "", package_sha256 := "") -> Dictionary:
	if not _valid_recipe(recipe): return {"ok": false, "errors": ["E_EDIT_SESSION_RECIPE: invalid recipe snapshot"]}
	if not String(package_sha256).is_empty() and not _is_digest(String(package_sha256)):
		return {"ok": false, "errors": ["E_EDIT_SESSION_PACKAGE: package digest is malformed"]}
	_snapshot = _make_snapshot(recipe, String(build_id), String(package_sha256))
	_state_epoch += 1
	emit_signal("snapshot_changed", capture_snapshot())
	return {"ok": true, "snapshot": capture_snapshot()}

func capture_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)

func restore_snapshot(snapshot: Variant) -> Dictionary:
	var verified := _verify_snapshot(snapshot)
	if not verified.get("ok", false): return verified
	_snapshot = snapshot.duplicate(true)
	_state_epoch += 1
	emit_signal("snapshot_changed", capture_snapshot())
	return {"ok": true, "snapshot": capture_snapshot()}

func current_recipe_sha256() -> String:
	return String(_snapshot.get("recipe_sha256", ""))

func begin_job() -> Dictionary:
	_latest_job_id += 1
	return {"job_id": _latest_job_id, "state_epoch": _state_epoch,
		"source_revision": int(_snapshot.get("source_revision", -1)), "recipe_sha256": current_recipe_sha256()}

func check_job_ticket(ticket: Variant) -> Dictionary:
	if not ticket is Dictionary:
		return {"ok": false, "status": "STALE_RESULT", "errors": ["E_EDIT_JOB_TICKET: malformed job ticket"]}
	var current := int(ticket.get("job_id", -1)) == _latest_job_id and int(ticket.get("state_epoch", -2)) == _state_epoch and int(ticket.get("source_revision", -3)) == int(_snapshot.get("source_revision", -4)) and String(ticket.get("recipe_sha256", "")) == current_recipe_sha256()
	if not current:
		return {"ok": false, "status": "STALE_RESULT", "errors": ["E_EDIT_STALE_RESULT: the recipe changed while this worker was running"]}
	return {"ok": true, "status": "CURRENT"}

func prepare_result_snapshot(ticket: Variant, candidate_recipe: Variant, build_id: String, package_sha256: String) -> Dictionary:
	var ticket_check := check_job_ticket(ticket)
	if not ticket_check.get("ok", false): return ticket_check
	if not _valid_recipe(candidate_recipe): return {"ok": false, "status": "GLOBAL_VALIDATION_FAILED", "errors": ["E_EDIT_RESULT_RECIPE: worker returned an invalid recipe"]}
	if int(candidate_recipe.get("source_revision", -1)) != int(_snapshot.get("source_revision", -2)) + 1:
		return {"ok": false, "status": "STALE_RESULT", "errors": ["E_EDIT_RESULT_REVISION: worker candidate is not the next source revision"]}
	if not _is_digest(package_sha256): return {"ok": false, "status": "GLOBAL_VALIDATION_FAILED", "errors": ["E_EDIT_RESULT_PACKAGE: package digest is malformed"]}
	return {"ok": true, "snapshot": _make_snapshot(candidate_recipe, build_id, package_sha256)}

func _make_snapshot(recipe: Dictionary, build_id: String, package_sha256: String) -> Dictionary:
	var payload := {"schema": SNAPSHOT_SCHEMA, "recipe": recipe.duplicate(true), "recipe_sha256": WorldGenCanonical.sha256(recipe),
		"source_revision": int(recipe.get("source_revision", 0)), "build_id": build_id, "package_sha256": package_sha256}
	payload["snapshot_sha256"] = WorldGenCanonical.sha256(payload)
	return payload

func _verify_snapshot(snapshot: Variant) -> Dictionary:
	if not snapshot is Dictionary or String(snapshot.get("schema", "")) != SNAPSHOT_SCHEMA or not _valid_recipe(snapshot.get("recipe")):
		return {"ok": false, "errors": ["E_EDIT_SNAPSHOT_SCHEMA: invalid semantic edit snapshot"]}
	if int(snapshot.get("source_revision", -1)) != int(snapshot["recipe"].get("source_revision", -2)) or String(snapshot.get("recipe_sha256", "")) != WorldGenCanonical.sha256(snapshot["recipe"]):
		return {"ok": false, "errors": ["E_EDIT_SNAPSHOT_BINDING: recipe digest or revision mismatch"]}
	var content: Dictionary = snapshot.duplicate(true)
	var stated_digest := String(content.get("snapshot_sha256", ""))
	content.erase("snapshot_sha256")
	if stated_digest != WorldGenCanonical.sha256(content):
		return {"ok": false, "errors": ["E_EDIT_SNAPSHOT_DIGEST: snapshot digest mismatch"]}
	if not String(snapshot.get("package_sha256", "")).is_empty() and not _is_digest(String(snapshot["package_sha256"])):
		return {"ok": false, "errors": ["E_EDIT_SNAPSHOT_PACKAGE: package digest is malformed"]}
	return {"ok": true}

func _valid_recipe(recipe: Variant) -> bool:
	if not recipe is Dictionary or String(recipe.get("schema", "")) != RECIPE_SCHEMA or String(recipe.get("id", "")).is_empty(): return false
	var revision: Variant = recipe.get("source_revision", null)
	if typeof(revision) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(revision)) or float(revision) != float(int(revision)) or int(revision) < 0: return false
	if not recipe.get("stages", []) is Array or recipe["stages"].is_empty(): return false
	return WorldGenCanonical.validate_value(recipe).is_empty()

func _is_digest(value: String) -> bool:
	if value.length() != 64: return false
	for character: String in value:
		if not "0123456789abcdef".contains(character): return false
	return true
