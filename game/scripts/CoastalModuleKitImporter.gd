extends RefCounted
class_name CoastalModuleKitImporter
## Loads only the explicit, frozen JSON module bundle from Blender. No .blend import.

const KIT_SCHEMA := "living-town.coastal-kit/1"
const MANIFEST_SCHEMA := "living-town.coastal-kit-manifest/1"


static func load_bundle(directory_path: String) -> Dictionary:
	var module_path := directory_path.path_join("coastal_modules.json")
	var manifest_path := directory_path.path_join("manifest.json")
	var module_file := FileAccess.open(module_path, FileAccess.READ)
	var manifest_file := FileAccess.open(manifest_path, FileAccess.READ)
	if module_file == null or manifest_file == null:
		return {"ok": false, "errors": ["E_KIT_MISSING: no exported Blender coastal kit at %s" % directory_path]}
	var kit_value: Variant = JSON.parse_string(module_file.get_as_text())
	var manifest_value: Variant = JSON.parse_string(manifest_file.get_as_text())
	if not kit_value is Dictionary or not manifest_value is Dictionary:
		return {"ok": false, "errors": ["E_KIT_JSON: kit and manifest must be JSON objects"]}
	if str(kit_value.get("schema", "")) != KIT_SCHEMA or str(manifest_value.get("schema", "")) != MANIFEST_SCHEMA:
		return {"ok": false, "errors": ["E_KIT_SCHEMA: unsupported Blender module bundle version"]}
	var actual_hash := _sha256(canonical_json(kit_value))
	if actual_hash != str(manifest_value.get("kit_sha256", "")):
		return {"ok": false, "errors": ["E_KIT_HASH: manifest does not match module bundle bytes"]}
	if int(kit_value.get("q_per_cell", 0)) != 48:
		return {"ok": false, "errors": ["E_KIT_SCALE: expected 48 q units per cell"]}
	var errors: Array[String] = []
	var module_index := {}
	for module: Variant in kit_value.get("modules", []):
		if not module is Dictionary:
			errors.append("E_KIT_MODULE: entries must be objects")
			continue
		var module_id := str(module.get("module_id", ""))
		if module_id.is_empty() or module_index.has(module_id):
			errors.append("E_KIT_ID: missing or duplicate module id '%s'" % module_id)
			continue
		if str(module.get("license_ref", "")).is_empty():
			errors.append("E_KIT_PROVENANCE: %s has no license/provenance reference" % module_id)
		var dimensions: Array = module.get("dimensions_q", [])
		if dimensions.size() != 2 or int(dimensions[0]) <= 0 or int(dimensions[1]) <= 0:
			errors.append("E_KIT_DIMENSIONS: %s needs positive dimensions_q" % module_id)
		var polygons: Array = module.get("polygons", [])
		if polygons.is_empty():
			errors.append("E_KIT_POLYGONS: %s exports no 2D shapes" % module_id)
		var shape_ids := {}
		for polygon: Variant in polygons:
			var shape_id := str(polygon.get("shape_id", ""))
			var points: Array = polygon.get("points_q", [])
			if shape_id.is_empty() or shape_ids.has(shape_id) or points.size() < 3:
				errors.append("E_KIT_SHAPE: %s has duplicate/empty shape or fewer than 3 points" % module_id)
			shape_ids[shape_id] = true
		module_index[module_id] = module
	var socket_ids := {}
	for socket: Variant in kit_value.get("sockets", []):
		var socket_id := str(socket.get("socket_id", ""))
		if socket_id.is_empty() or socket_ids.has(socket_id) or not module_index.has(str(socket.get("module_id", ""))):
			errors.append("E_KIT_SOCKET: duplicate socket or socket references a missing module")
		socket_ids[socket_id] = true
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return {"ok": true, "errors": [], "modules": module_index, "sockets": kit_value.get("sockets", []), "manifest": manifest_value, "kit_sha256": actual_hash}


static func canonical_json(value: Variant) -> String:
	return JSON.stringify(_canonical(value), "", false, true)


static func _canonical(value: Variant) -> Variant:
	# JSON.parse_string materializes JSON integer tokens as floats. Restore exact
	# integral values before hashing so the Godot digest matches Blender's
	# canonical integer JSON instead of serializing e.g. 48 as 48.0.
	if typeof(value) == TYPE_FLOAT and absf(value - roundf(value)) <= 0.000000001:
		return int(roundf(value))
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var sorted := {}
		for key: Variant in keys:
			sorted[str(key)] = _canonical(value[key])
		return sorted
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_canonical(item))
		return result
	return value


static func _sha256(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()
