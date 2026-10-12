extends RefCounted
class_name WorldGenOperatorRegistry
## Registry binds versioned, typed operator declarations to trusted project code.

var _operators: Dictionary = {}

func register_operator(spec: Dictionary, implementation: Callable) -> Dictionary:
	var operator_id := String(spec.get("id", ""))
	if operator_id.is_empty() or _operators.has(operator_id):
		return {"ok": false, "error": "E_OPERATOR_ID: operator id is empty or already registered"}
	if implementation.is_null() or not implementation.is_valid():
		return {"ok": false, "error": "E_OPERATOR_IMPL: %s has no callable implementation" % operator_id}
	if String(spec.get("schema_revision", "")) != "1":
		return {"ok": false, "error": "E_OPERATOR_SCHEMA: %s requires schema_revision 1" % operator_id}
	if String(spec.get("side_effect_class", "")) != "pure":
		return {"ok": false, "error": "E_OPERATOR_EFFECT: release kernel only executes pure operators"}
	var stable_spec := spec.duplicate(true)
	var target: Object = implementation.get_object()
	var script: Script = target.get_script() if target != null else null
	var source := script.source_code if script != null else ""
	if source.is_empty() and script != null and not script.resource_path.is_empty() and FileAccess.file_exists(script.resource_path):
		source = FileAccess.get_file_as_string(script.resource_path)
	stable_spec["implementation_sha256"] = WorldGenCanonical.sha256(source) if not source.is_empty() else ""
	_operators[operator_id] = {"spec": stable_spec, "callable": implementation}
	return {"ok": true}

func has_operator(operator_id: String) -> bool:
	return _operators.has(operator_id)

func get_spec(operator_id: String) -> Dictionary:
	return (_operators.get(operator_id, {}).get("spec", {}) as Dictionary).duplicate(true)

func run(operator_id: String, request: Dictionary) -> Dictionary:
	if not _operators.has(operator_id):
		return {"ok": false, "errors": ["E_OPERATOR_MISSING: %s" % operator_id]}
	var entry: Dictionary = _operators[operator_id]
	var callback: Callable = entry["callable"]
	var result: Variant = callback.call(request.duplicate(true))
	if not result is Dictionary or not bool(result.get("ok", false)):
		return result if result is Dictionary else {"ok": false, "errors": ["E_OPERATOR_RESULT: %s did not return an object" % operator_id]}
	return result
