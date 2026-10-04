extends SceneTree
## Strict, path-free JSON command boundary used by human and agent adapters.

const EDIT := preload("res://addons/worldgen/core/edit_command.gd")
const REPAIR := preload("res://addons/worldgen/operators/local_repair.gd")
const VALIDATOR := preload("res://addons/worldgen/core/worldgen_package_validator.gd")
const CANONICAL := preload("res://addons/worldgen/core/worldgen_canonical.gd")
const OBJECT_ROOT := "res://addons/worldgen/builds/objects"
const RECIPE_ROOT := "res://addons/worldgen/recipes"
const PACKAGE_ROOT := "res://addons/worldgen/builds"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(2)
		return
	var request := _normalize_json_numbers(_read_json(String(args[0])))
	var response := _dispatch(request)
	var file := FileAccess.open(String(args[1]), FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(CANONICAL.canonical_json(response) + "\n")
	file.flush()
	file.close()
	quit(0 if bool(response.get("ok", false)) else 1)

func _dispatch(request: Dictionary) -> Dictionary:
	var request_id := String(request.get("request_id", ""))
	var command := String(request.get("command", ""))
	var request_sha := CANONICAL.sha256(request)
	var errors := _validate_envelope(request)
	if not errors.is_empty():
		return _result(request_id, command, request_sha, false, "INVALID_REQUEST", {"errors": errors})
	var result: Dictionary
	match command:
		"inspect": result = _inspect(String(request["world_id"]))
		"validate": result = _validate_candidate(String(request["candidate_sha256"]))
		"propose": result = _propose(request)
		"repair": result = _repair(request["repair_request"])
		"publish-request": result = _publish_request(request)
		_: result = {"ok": false, "status": "UNSUPPORTED_COMMAND", "errors": ["E_COMMAND_UNKNOWN"]}
	return _result(request_id, command, request_sha, bool(result.get("ok", false)), String(result.get("status", "FAILED")), result)

func _validate_envelope(request: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key: String in request:
		if key not in ["schema", "request_id", "command", "world_id", "candidate_sha256", "base_recipe_sha256", "base_package_sha256", "base_revision", "patch_id", "declared_class", "changes", "repair_request", "expected_revision"]:
			errors.append("E_REQUEST_FIELD: unsupported field %s" % key)
	if String(request.get("schema", "")) != "worldgen.authoring_command/1": errors.append("E_REQUEST_SCHEMA")
	if not _valid_identifier(String(request.get("request_id", ""))): errors.append("E_REQUEST_ID")
	var command := String(request.get("command", ""))
	if command not in ["inspect", "validate", "propose", "repair", "publish-request"]:
		errors.append("E_COMMAND_UNKNOWN")
	var command_fields: Array[String] = ["schema", "request_id", "command"]
	match command:
		"inspect": command_fields.append_array(["world_id"])
		"validate": command_fields.append_array(["candidate_sha256"])
		"propose": command_fields.append_array(["world_id", "base_recipe_sha256", "base_package_sha256", "base_revision", "patch_id", "declared_class", "changes"])
		"repair": command_fields.append_array(["repair_request"])
		"publish-request": command_fields.append_array(["world_id", "candidate_sha256", "expected_revision"])
	for field: String in command_fields:
		if not request.has(field): errors.append("E_REQUEST_REQUIRED: %s" % field)
	for key: String in request:
		if key not in command_fields: errors.append("E_REQUEST_COMMAND_FIELD: %s" % key)
	if request.has("world_id") and not _valid_identifier(String(request["world_id"])): errors.append("E_WORLD_ID")
	if request.has("candidate_sha256") and not _valid_digest(String(request["candidate_sha256"])): errors.append("E_CANDIDATE_DIGEST")
	if request.has("base_recipe_sha256") and not _valid_digest(String(request["base_recipe_sha256"])): errors.append("E_RECIPE_DIGEST")
	if request.has("base_package_sha256") and not _valid_digest(String(request["base_package_sha256"])): errors.append("E_PACKAGE_DIGEST")
	if request.has("base_revision") and not _valid_revision(request["base_revision"]): errors.append("E_BASE_REVISION")
	if request.has("expected_revision") and not _valid_revision(request["expected_revision"]): errors.append("E_EXPECTED_REVISION")
	if request.has("patch_id") and not _valid_identifier(String(request["patch_id"])): errors.append("E_PATCH_ID")
	if request.has("declared_class") and String(request["declared_class"]) not in ["visual", "semantic"]: errors.append("E_DECLARED_CLASS")
	if request.has("changes") and (not request["changes"] is Array or request["changes"].is_empty() or request["changes"].size() > 64): errors.append("E_CHANGES_BOUNDS")
	if request.has("repair_request") and not request["repair_request"] is Dictionary: errors.append("E_REPAIR_REQUEST")
	return errors

func _inspect(world_id: String) -> Dictionary:
	var recipe := _load_recipe(world_id)
	if recipe.is_empty(): return {"ok": false, "status": "NOT_FOUND", "errors": ["E_RECIPE_NOT_FOUND"]}
	var package := _load_package(world_id)
	var info := {"world_id": world_id, "source_revision": int(recipe.get("source_revision", -1)), "recipe_sha256": CANONICAL.sha256(recipe), "stage_ids": _stage_ids(recipe)}
	if package.is_empty():
		info["package_available"] = false
	else:
		info["package_available"] = true
		info["candidate_sha256"] = CANONICAL.sha256(package)
		info["semantic_sha256"] = String(package.get("digests", {}).get("semantic_sha256", ""))
		info["presentation_sha256"] = String(package.get("digests", {}).get("presentation_sha256", ""))
	return {"ok": true, "status": "INSPECTED", "result": info}

func _validate_candidate(candidate_sha256: String) -> Dictionary:
	var object_path := OBJECT_ROOT.path_join(candidate_sha256.left(2)).path_join(candidate_sha256 + ".json")
	var package := _read_json(object_path)
	if package.is_empty(): return {"ok": false, "status": "NOT_FOUND", "errors": ["E_CANDIDATE_NOT_FOUND"]}
	if CANONICAL.sha256(package) != candidate_sha256: return {"ok": false, "status": "INVALID", "errors": ["E_CANDIDATE_OBJECT_DIGEST"]}
	var validation: Dictionary = VALIDATOR.validate(package)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "status": "INVALID", "candidate_sha256": candidate_sha256, "errors": validation.get("errors", [])}
	return {"ok": true, "status": "VALIDATED", "world_id": String(package.get("world_id", "")), "candidate_sha256": candidate_sha256, "semantic_sha256": package["digests"]["semantic_sha256"], "presentation_sha256": package["digests"]["presentation_sha256"], "validation": validation}

func _propose(request: Dictionary) -> Dictionary:
	var world_id := String(request["world_id"])
	var recipe := _load_recipe(world_id)
	var package := _load_package(world_id)
	if recipe.is_empty() or package.is_empty(): return {"ok": false, "status": "NOT_FOUND", "errors": ["E_PROPOSAL_BASE_NOT_FOUND"]}
	if CANONICAL.sha256(recipe) != String(request["base_recipe_sha256"]): return {"ok": false, "status": "STALE", "errors": ["E_PROPOSAL_RECIPE_STALE"]}
	if CANONICAL.sha256(package) != String(request["base_package_sha256"]): return {"ok": false, "status": "STALE", "errors": ["E_PROPOSAL_PACKAGE_STALE"]}
	if int(recipe.get("source_revision", -1)) != int(request["base_revision"]): return {"ok": false, "status": "STALE", "errors": ["E_PROPOSAL_REVISION_STALE"]}
	var patch := {"schema": "worldgen.edit_patch/1", "patch_id": request["patch_id"], "base_revision": request["base_revision"], "declared_class": request["declared_class"], "changes": request["changes"]}
	var prepared: Dictionary = EDIT.prepare_patch(recipe, patch, package)
	if not bool(prepared.get("ok", false)): return {"ok": false, "status": "REJECTED", "errors": prepared.get("errors", [])}
	return {"ok": true, "status": "PROPOSED", "candidate_recipe": prepared["candidate_recipe"], "candidate_recipe_sha256": CANONICAL.sha256(prepared["candidate_recipe"]), "base_recipe_sha256": prepared["base_recipe_sha256"], "base_package_sha256": prepared["base_package_sha256"], "source_revision_after": prepared["source_revision_after"], "declared_class": prepared["declared_class"], "dirty_scope": prepared["dirty_scope"], "dependency_closure": prepared["dependency_closure"], "protected_ids": prepared["protected_ids"], "activation": "not_requested"}

func _repair(repair_request: Dictionary) -> Dictionary:
	return REPAIR.repair(repair_request)

func _publish_request(request: Dictionary) -> Dictionary:
	var checked := _validate_candidate(String(request["candidate_sha256"]))
	if not bool(checked.get("ok", false)):
		return {"ok": false, "status": "REJECTED", "errors": checked.get("errors", [])}
	if String(checked.get("world_id", "")) != String(request["world_id"]):
		return {"ok": false, "status": "REJECTED", "errors": ["E_PUBLISH_WORLD_BINDING"]}
	return {"ok": true, "status": "AWAITING_EXTERNAL_APPROVAL", "approval_request": {"schema": "worldgen.publish_request/1", "world_id": request["world_id"], "candidate_sha256": request["candidate_sha256"], "expected_revision": request["expected_revision"], "approval_token_required": true}, "activation": "not_performed"}

func _load_recipe(world_id: String) -> Dictionary:
	var directory := DirAccess.open(RECIPE_ROOT)
	if directory == null: return {}
	for file_name: String in directory.get_files():
		if file_name.get_extension() != "json": continue
		var recipe := _read_json(RECIPE_ROOT.path_join(file_name))
		if String(recipe.get("id", "")) == world_id: return recipe
	return {}

func _load_package(world_id: String) -> Dictionary:
	var directory := DirAccess.open(PACKAGE_ROOT)
	if directory == null: return {}
	for file_name: String in directory.get_files():
		if not file_name.ends_with(".world.json"): continue
		var package := _read_json(PACKAGE_ROOT.path_join(file_name))
		if String(package.get("world_id", "")) == world_id: return package
	return {}

func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	return parser.data if parse_error == OK and parser.data is Dictionary else {}

func _normalize_json_numbers(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT:
		var number := float(value)
		if is_finite(number) and floor(number) == number and number >= -2147483648.0 and number <= 2147483647.0:
			return int(number)
		return value
	if value is Array:
		var normalized: Array = []
		for item: Variant in value: normalized.append(_normalize_json_numbers(item))
		return normalized
	if value is Dictionary:
		var normalized: Dictionary = {}
		for key: Variant in value: normalized[key] = _normalize_json_numbers(value[key])
		return normalized
	return value

func _stage_ids(recipe: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for stage: Dictionary in recipe.get("stages", []): ids.append(String(stage.get("id", "")))
	return ids

func _valid_identifier(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$")
	return regex.search(value) != null

func _valid_digest(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[a-f0-9]{64}$")
	return regex.search(value) != null

func _valid_revision(value: Variant) -> bool:
	if typeof(value) == TYPE_INT: return int(value) >= 0
	if typeof(value) != TYPE_FLOAT: return false
	var numeric := float(value)
	return numeric >= 0.0 and numeric <= 2147483647.0 and floor(numeric) == numeric

func _result(request_id: String, command: String, request_sha: String, ok: bool, status: String, detail: Dictionary) -> Dictionary:
	return {"schema": "worldgen.authoring_result/1", "request_id": request_id, "command": command, "request_sha256": request_sha, "ok": ok, "status": status, "detail": detail}
