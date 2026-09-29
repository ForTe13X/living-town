extends RefCounted
class_name WorldPackageSpatialQueries
## Read-only semantic query facade for game adapters and standalone consumers.
## Package definitions never grant actions, mutate state, or create reservations.

const VALIDATOR := preload("res://addons/worldgen/core/worldgen_package_validator.gd")

var _package: Dictionary = {}
var _semantic: Dictionary = {}

func configure(package: Dictionary) -> Dictionary:
	var validation: Dictionary = VALIDATOR.validate(package)
	if not bool(validation.get("ok", false)):
		_package.clear()
		_semantic.clear()
		return {"ok": false, "errors": validation.get("errors", ["E_PACKAGE_INVALID"])}
	_package = package.duplicate(true)
	_semantic = _package.get("semantic", {}).duplicate(true)
	return {"ok": true, "world_id": String(_package.get("world_id", "")), "semantic_sha256": String(_package.get("digests", {}).get("semantic_sha256", ""))}

func is_configured() -> bool:
	return not _package.is_empty()

func world_id() -> String:
	return String(_package.get("world_id", ""))

func semantic_digest() -> String:
	return String(_package.get("digests", {}).get("semantic_sha256", ""))

func query_rooms(access_profile := "public") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_configured(): return result
	for raw: Variant in _semantic.get("rooms", []):
		if not raw is Dictionary: continue
		var room: Dictionary = raw
		if _can_access(String(room.get("id", "")), String(room.get("access", "public")), access_profile):
			result.append(room.duplicate(true))
	return result

func query_portals(access_profile := "public") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_configured(): return result
	for raw: Variant in _semantic.get("portals", []):
		if not raw is Dictionary: continue
		var portal: Dictionary = raw
		var target_room := String(portal.get("to_room", ""))
		if _can_access(target_room, String(portal.get("access", "public")), access_profile):
			result.append(portal.duplicate(true))
	return result

func query_affordances(access_profile := "public", action_type := "", room_id := "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_configured(): return result
	for raw: Variant in _semantic.get("affordances", []):
		if not raw is Dictionary: continue
		var affordance: Dictionary = raw
		var target_room := String(affordance.get("room_id", ""))
		if room_id != "" and target_room != room_id: continue
		if action_type != "" and String(affordance.get("action_type", "")) != action_type: continue
		if _can_access(target_room, String(affordance.get("access", "public")), access_profile):
			result.append(affordance.duplicate(true))
	return result

## Position and radius use package-local cell units. Results sort by Manhattan distance then stable ID.
func query_affordances_near(position: Vector2i, radius_cells: int, access_profile := "public", action_type := "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if radius_cells < 0: return result
	for affordance: Dictionary in query_affordances(access_profile, action_type):
		var at: Array = affordance.get("position", [])
		if at.size() != 2: continue
		var distance := absi(position.x - int(at[0])) + absi(position.y - int(at[1]))
		if distance > radius_cells: continue
		affordance["query_distance_cells"] = distance
		result.append(affordance)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["query_distance_cells"]) != int(b["query_distance_cells"]):
			return int(a["query_distance_cells"]) < int(b["query_distance_cells"])
		return String(a.get("id", "")) < String(b.get("id", "")))
	return result

func query_buildings(program := "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_configured(): return result
	var candidates: Array = _semantic.get("buildings", [])
	if String(_semantic.get("kind", "")) == "coastal_neighborhood":
		candidates = _semantic.get("topology", {}).get("buildings", [])
	for raw: Variant in candidates:
		if not raw is Dictionary: continue
		var building: Dictionary = raw
		var building_program := String(building.get("program", building.get("type", "")))
		if program == "" or building_program == program:
			result.append(building.duplicate(true))
	return result

func query_roads() -> Array[Dictionary]:
	if not is_configured(): return []
	var graph: Dictionary = _semantic.get("street_graph", {})
	if not graph.is_empty(): return graph.get("edges", []).duplicate(true)
	if String(_semantic.get("kind", "")) == "coastal_neighborhood":
		return _semantic.get("topology", {}).get("roads", []).duplicate(true)
	return []

func _can_access(room_id: String, access: String, access_profile: String) -> bool:
	if access_profile == "": return false
	var profiles: Dictionary = _semantic.get("access_profiles", {})
	if not profiles.has(access_profile): return access == "public" and access_profile == "public"
	var allowed: Array = profiles[access_profile]
	if access_profile == "public" and access != "public": return false
	return access == "public" or access == access_profile or allowed.has(room_id) or allowed.has(access)
