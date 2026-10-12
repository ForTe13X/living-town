extends RefCounted
class_name WorldGenBuildCache
## Persistent cache for successful, deterministic operator stage outputs.

const CACHE_SCHEMA := "worldgen.stage_cache/2"
const DEFAULT_ROOT := "user://worldgen/stage_cache"
const INDEX_SCRIPT := preload("res://addons/worldgen/core/dependency_index.gd")

var root_path := DEFAULT_ROOT
var index_path := ""
var dependency_index: RefCounted

func _init(cache_root := DEFAULT_ROOT) -> void:
	root_path = String(cache_root).trim_suffix("/")
	index_path = root_path.path_join("dependency_index.json")
	dependency_index = INDEX_SCRIPT.new()
	var loaded: Dictionary = dependency_index.load(index_path)
	if not loaded.get("ok", false):
		# A corrupt reverse index cannot create a false hit: rebuild lazily from
		# entry manifests and leave cache reads available by exact key.
		dependency_index = INDEX_SCRIPT.new()

static func make_key(identity: Dictionary) -> String:
	return WorldGenCanonical.sha256({"schema": CACHE_SCHEMA, "identity": identity})

func get_entry(cache_key: String) -> Dictionary:
	if cache_key.length() != 64 or not _is_digest(cache_key):
		return {"ok": false, "errors": ["E_CACHE_KEY: malformed stage key"]}
	var path := _entry_path(cache_key)
	if not FileAccess.file_exists(path):
		return {"ok": true, "hit": false}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		return _reject_entry(cache_key, path, "E_CACHE_CORRUPT: cached stage is invalid JSON")
	var entry: Dictionary = parser.data
	if String(entry.get("schema", "")) != CACHE_SCHEMA or String(entry.get("cache_key", "")) != cache_key:
		return _reject_entry(cache_key, path, "E_CACHE_BINDING: cached stage key mismatch")
	var outputs: Variant = entry.get("outputs")
	if not outputs is Dictionary or WorldGenCanonical.sha256(outputs) != String(entry.get("outputs_sha256", "")):
		return _reject_entry(cache_key, path, "E_CACHE_DIGEST: cached outputs failed verification")
	return {"ok": true, "hit": true, "outputs": outputs.duplicate(true), "operation_count": int(entry.get("operation_count", 0)), "dependency_digests": entry.get("dependency_digests", []).duplicate()}

func put_entry(cache_key: String, outputs: Dictionary, dependency_digests: Array, operation_count := 0) -> Dictionary:
	if cache_key.length() != 64 or not _is_digest(cache_key):
		return {"ok": false, "errors": ["E_CACHE_KEY: malformed stage key"]}
	var errors := WorldGenCanonical.validate_value(outputs)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var unique: Array[String] = []
	for raw_digest: Variant in dependency_digests:
		var digest := String(raw_digest)
		if _is_digest(digest) and not unique.has(digest):
			unique.append(digest)
	unique.sort()
	var entry := {"schema": CACHE_SCHEMA, "cache_key": cache_key, "outputs": outputs, "outputs_sha256": WorldGenCanonical.sha256(outputs), "dependency_digests": unique, "operation_count": int(operation_count)}
	var path := _entry_path(cache_key)
	var absolute := ProjectSettings.globalize_path(path)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "errors": ["E_CACHE_DIR: cannot create stage cache"]}
	var bytes := WorldGenCanonical.canonical_json(entry) + "\n"
	if FileAccess.file_exists(path):
		var existing := JSON.new()
		if existing.parse(FileAccess.get_file_as_string(path)) != OK or not existing.data is Dictionary or String(existing.data.get("cache_key", "")) != cache_key or WorldGenCanonical.sha256(existing.data.get("outputs", {})) != entry["outputs_sha256"]:
			return {"ok": false, "errors": ["E_CACHE_COLLISION: existing cache key has different content"]}
	else:
		var temporary := absolute + ".pending.%d.%d" % [OS.get_process_id(), Time.get_ticks_usec()]
		var file := FileAccess.open(ProjectSettings.localize_path(temporary), FileAccess.WRITE)
		if file == null:
			return {"ok": false, "errors": ["E_CACHE_WRITE: cannot stage cache entry"]}
		file.store_string(bytes)
		file.flush()
		file.close()
		if FileAccess.get_file_as_string(ProjectSettings.localize_path(temporary)) != bytes:
			DirAccess.remove_absolute(temporary)
			return {"ok": false, "errors": ["E_CACHE_VERIFY: staged cache bytes differ"]}
		var rename_error := DirAccess.rename_absolute(temporary, absolute)
		if rename_error != OK:
			DirAccess.remove_absolute(temporary)
			var raced := JSON.new()
			if not FileAccess.file_exists(path) or raced.parse(FileAccess.get_file_as_string(path)) != OK or not raced.data is Dictionary or String(raced.data.get("cache_key", "")) != cache_key or WorldGenCanonical.sha256(raced.data.get("outputs", {})) != entry["outputs_sha256"]:
				return {"ok": false, "errors": ["E_CACHE_PROMOTE: atomic cache promotion failed (%d)" % rename_error]}
	dependency_index.register(cache_key, unique)
	var index_result: Dictionary = dependency_index.save(index_path)
	return {"ok": true, "cache_key": cache_key, "index_saved": bool(index_result.get("ok", false))}

func invalidate_dependency(artifact_digest: String) -> Dictionary:
	var invalidated: Array[String] = dependency_index.dependents(artifact_digest)
	for cache_key: String in invalidated:
		var path := _entry_path(cache_key)
		if FileAccess.file_exists(path):
			var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			if error != OK:
				return {"ok": false, "errors": ["E_CACHE_INVALIDATE: cannot remove %s" % cache_key], "invalidated": invalidated}
		dependency_index.remove_key(cache_key)
	var saved: Dictionary = dependency_index.save(index_path)
	return {"ok": bool(saved.get("ok", false)), "invalidated": invalidated, "errors": saved.get("errors", [])}

func _entry_path(cache_key: String) -> String:
	return root_path.path_join(cache_key.left(2)).path_join(cache_key + ".json")

func _reject_entry(cache_key: String, path: String, reason: String) -> Dictionary:
	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if remove_error != OK:
		return {"ok": false, "hit": false, "errors": [reason, "E_CACHE_REJECT_REMOVE: cannot remove rejected cache entry"]}
	dependency_index.remove_key(cache_key)
	dependency_index.save(index_path)
	return {"ok": true, "hit": false, "cache_rejected": reason}

static func _is_digest(value: String) -> bool:
	if value.length() != 64:
		return false
	for character: String in value:
		if not "0123456789abcdef".contains(character):
			return false
	return true
