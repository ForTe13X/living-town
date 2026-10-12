extends "res://scripts/SimExtensions.gd"
## Immutable authored geometry input. Simulation rules remain in Sim; this adapter
## substitutes spatial data before a run starts and is excluded from save state.

var profile: Dictionary = {}
var projection: Dictionary = {}
var error_message: String = ""
var _files: Dictionary = {}
var _blocked_cells: Dictionary = {}

func load_profile(path: String = "res://data/town3d/profile.json") -> bool:
	profile = {}
	projection = {}
	_files = {}
	_blocked_cells = {}
	error_message = ""
	var parsed: Variant = _dictionary_file(path)
	if not (parsed is Dictionary):
		return false
	if String(parsed.get("schema", "")) != "living_town.world_profile.v1":
		error_message = "Unsupported town profile schema: " + path
		return false
	# Enabled procedural packages install a different authored topology. Retain
	# those adapters, but refuse competing authorities for this frozen model.
	for activation_path in ["res://worldgen_activation.json", "res://coastal/warm_bay_s1/export/sim_adapter/activation.json"]:
		if FileAccess.file_exists(activation_path):
			var activation: Variant = JSON.parse_string(FileAccess.get_file_as_string(activation_path))
			if activation is Dictionary and bool(activation.get("enabled", false)):
				error_message = "Disable the competing spatial activation before using Town3D: " + activation_path
				return false
	var paths: Variant = parsed.get("files", {})
	if not (paths is Dictionary) or paths.is_empty():
		error_message = "Town profile contains no spatial files"
		return false
	for key in paths:
		var expected: String = String((parsed.get("file_hashes", {}) as Dictionary).get(String(key).get_file(), ""))
		if not expected.is_empty() and FileAccess.get_sha256(String(paths[key])) != expected:
			error_message = "Town profile checksum mismatch: " + String(key)
			return false
		var data: Variant = _dictionary_file(String(paths[key]))
		if not (data is Dictionary):
			return false
		_files[String(key).get_file()] = data.duplicate(true)
	for required in ["map.json", "spaces.json", "interiors.json", "agents.json", "buildings.json"]:
		if not _files.has(required):
			error_message = "Town profile is missing " + required
			return false
	var projected: Variant = _dictionary_file(String(parsed.get("projection_path", "")))
	if not (projected is Dictionary) or String(projected.get("schema", "")) != "living_town.projection3d.v1":
		error_message = "Town projection data is missing or incompatible"
		return false
	var projection_hash := String(parsed.get("projection_sha256", ""))
	if not projection_hash.is_empty() and FileAccess.get_sha256(String(parsed["projection_path"])) != projection_hash:
		error_message = "Town projection checksum mismatch"
		return false
	profile = parsed.duplicate(true)
	projection = projected.duplicate(true)
	var stage: Variant = _dictionary_file("res://assets/town3d/stage_manifest.json")
	if not (stage is Dictionary) or stage.get("source_blend_sha256") != profile.get("model_source_blend_sha256"):
		error_message = "Town spatial profile and staged model have different sources"
		return false
	var interiors: Dictionary = _files["interiors.json"]
	for key in projection.get("planes", {}):
		var plane: Dictionary = projection["planes"][key]
		var content: Dictionary = _files["map.json"] if key == "town/outdoor" else interiors.get(plane["space"], {}).get(plane["floor"], {})
		var blocked := {}
		var size: Array = plane["grid_size"]
		for cell in content.get("nav_blockers", []):
			blocked[int(cell[1]) * int(size[0]) + int(cell[0])] = true
		_blocked_cells[key] = blocked
	return true

func is_valid() -> bool:
	return not profile.is_empty() and error_message.is_empty()

func world_data_for(path: String) -> Variant:
	var key := path.get_file()
	return _files[key].duplicate(true) if _files.has(key) else null

func save_identity() -> Dictionary:
	return {"id": String(profile.get("id", "")),
		"projection_sha256": String(profile.get("projection_sha256", ""))}

func position_allowed(space: String, floor: String, pos: Vector2i) -> bool:
	var key := space + "/" + floor
	var plane: Dictionary = projection.get("planes", {}).get(key, {})
	if plane.is_empty():
		return false
	var size: Array = plane["grid_size"]
	return pos.x >= 0 and pos.y >= 0 and pos.x < int(size[0]) and pos.y < int(size[1]) and not _blocked_cells[key].has(pos.y * int(size[0]) + pos.x)

func validate_saved_world(world: Dictionary) -> String:
	var authored: Dictionary = _files["map.json"]
	for key in ["width", "height", "nav_blockers", "rooms", "areas"]:
		if world.get(key) != authored.get(key):
			return "Town profile authored geometry differs: " + key
	for object_id in projection.get("interaction_bindings", {}):
		var binding: Dictionary = projection["interaction_bindings"][object_id]
		if bool(binding.get("anchor_only", false)):
			# Bank/civic markers live in authored interiors, never world.objects.
			continue
		var object: Dictionary = world.get("objects", {}).get(object_id, {})
		var plane := String(binding["plane"]).split("/")
		var cell: Array = binding["cell"]
		if object.is_empty() or String(object.get("space", "town")) != plane[0] or String(object.get("floor", "outdoor")) != plane[1] or object.get("pos") != Vector2i(int(cell[0]), int(cell[1])):
			return "Town profile interaction address differs: " + String(object_id)
	return ""

func _dictionary_file(path: String) -> Variant:
	if path.is_empty() or not FileAccess.file_exists(path):
		error_message = "Missing town profile file: " + path
		return null
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (value is Dictionary):
		error_message = "Invalid town profile JSON: " + path
		return null
	return value
