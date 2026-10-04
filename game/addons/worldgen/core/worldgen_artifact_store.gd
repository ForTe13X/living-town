extends RefCounted
class_name WorldGenArtifactStore
## Write-once JSON object store. Paths are derived from content hashes, never caller IDs.

func put_json(root_path: String, value: Variant) -> Dictionary:
	var errors := WorldGenCanonical.validate_value(value)
	if not errors.is_empty(): return {"ok": false, "errors": errors}
	var bytes := WorldGenCanonical.canonical_json(value)
	var digest := WorldGenCanonical.sha256(value)
	var root := root_path.trim_suffix("/")
	var destination := root.path_join(digest.left(2)).path_join(digest + ".json")
	var absolute := ProjectSettings.globalize_path(destination)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "errors": ["E_STORE_DIR: cannot create object prefix"]}
	if FileAccess.file_exists(destination):
		var existing := FileAccess.get_file_as_string(destination)
		if existing != bytes: return {"ok": false, "errors": ["E_STORE_CORRUPT: existing object differs at its digest path"]}
		return {"ok": true, "sha256": digest, "path": destination, "reused": true}
	var temporary := absolute + ".pending"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return {"ok": false, "errors": ["E_STORE_WRITE: cannot stage immutable object"]}
	file.store_string(bytes)
	file.flush()
	file.close()
	var staged := FileAccess.get_file_as_string(ProjectSettings.localize_path(temporary))
	if staged != bytes:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "errors": ["E_STORE_VERIFY: staged object bytes differ"]}
	var rename_error := DirAccess.rename_absolute(temporary, absolute)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary)
		if FileAccess.file_exists(destination) and FileAccess.get_file_as_string(destination) == bytes:
			return {"ok": true, "sha256": digest, "path": destination, "reused": true}
		return {"ok": false, "errors": ["E_STORE_PROMOTE: atomic promotion failed (%d)" % rename_error]}
	return {"ok": true, "sha256": digest, "path": destination, "reused": false}

func read_json(path: String, expected_sha256: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() or not FileAccess.file_exists(path): return {"ok": false, "errors": ["E_STORE_MISSING: object is missing"]}
	var parsed := JSON.new()
	if parsed.parse(text) != OK: return {"ok": false, "errors": ["E_STORE_JSON: object is invalid JSON"]}
	if WorldGenCanonical.sha256(parsed.data) != expected_sha256:
		return {"ok": false, "errors": ["E_STORE_DIGEST: immutable object failed digest verification"]}
	return {"ok": true, "data": parsed.data}
