extends RefCounted
class_name WorldGenDependencyIndex
## Conservative reverse index for immutable stage-cache entries.

const INDEX_SCHEMA := "worldgen.dependency_index/1"

var _artifact_to_keys: Dictionary = {}
var _key_to_artifacts: Dictionary = {}

func register(cache_key: String, artifact_digests: Array) -> void:
	var unique: Array[String] = []
	for raw_digest: Variant in artifact_digests:
		var digest := String(raw_digest)
		if digest.is_empty() or unique.has(digest):
			continue
		unique.append(digest)
		var keys: Array = _artifact_to_keys.get(digest, [])
		if not keys.has(cache_key):
			keys.append(cache_key)
			keys.sort()
		_artifact_to_keys[digest] = keys
	unique.sort()
	_key_to_artifacts[cache_key] = unique

func dependents(artifact_digest: String) -> Array[String]:
	var result: Array[String] = []
	for raw_key: Variant in _artifact_to_keys.get(artifact_digest, []):
		result.append(String(raw_key))
	result.sort()
	return result

func remove_key(cache_key: String) -> void:
	var digests: Array = _key_to_artifacts.get(cache_key, [])
	for raw_digest: Variant in digests:
		var digest := String(raw_digest)
		var keys: Array = _artifact_to_keys.get(digest, [])
		keys.erase(cache_key)
		if keys.is_empty():
			_artifact_to_keys.erase(digest)
		else:
			_artifact_to_keys[digest] = keys
	_key_to_artifacts.erase(cache_key)

func save(path: String) -> Dictionary:
	var payload := {"schema": INDEX_SCHEMA, "artifact_to_keys": _artifact_to_keys, "key_to_artifacts": _key_to_artifacts}
	var errors := WorldGenCanonical.validate_value(payload)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var absolute := ProjectSettings.globalize_path(path)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "errors": ["E_DEP_INDEX_DIR: cannot create dependency index directory"]}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "errors": ["E_DEP_INDEX_WRITE: cannot write dependency index"]}
	file.store_string(WorldGenCanonical.canonical_json(payload) + "\n")
	file.flush()
	file.close()
	return {"ok": true}

func load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": true, "missing": true}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		return {"ok": false, "errors": ["E_DEP_INDEX_JSON: dependency index is corrupt"]}
	var payload: Dictionary = parser.data
	if String(payload.get("schema", "")) != INDEX_SCHEMA or not payload.get("artifact_to_keys", {}) is Dictionary or not payload.get("key_to_artifacts", {}) is Dictionary:
		return {"ok": false, "errors": ["E_DEP_INDEX_SCHEMA: unsupported dependency index"]}
	_artifact_to_keys = payload["artifact_to_keys"].duplicate(true)
	_key_to_artifacts = payload["key_to_artifacts"].duplicate(true)
	return {"ok": true}
