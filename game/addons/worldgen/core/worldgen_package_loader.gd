extends RefCounted
class_name WorldGenPackageLoader
## Read-only runtime boundary. No authoring, model, Blender, or simulation dependency.

const VALIDATOR := preload("res://addons/worldgen/core/worldgen_package_validator.gd")

func load_package(path: String, required_capabilities: Dictionary = {}) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok": false, "errors": ["E_PACKAGE_MISSING: cannot read %s" % path]}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK: return {"ok": false, "errors": ["E_PACKAGE_JSON: %s" % parser.get_error_message()]}
	var valid: Dictionary = VALIDATOR.validate(parser.data)
	if not bool(valid.get("ok", false)): return valid
	var package: Dictionary = parser.data
	var available: Dictionary = package.get("capabilities", {})
	for capability: String in required_capabilities:
		if available.get(capability) != required_capabilities[capability]:
			return {"ok": false, "errors": ["E_PACKAGE_CAPABILITY: required capability '%s' is not satisfied" % capability]}
	return {"ok": true, "package": package.duplicate(true), "mutable_world_state": false}
