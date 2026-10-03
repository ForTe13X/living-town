extends RefCounted
class_name FrozenCafeStreetQueries
## Read-only LT-22 reference query. Its receiver-owned reference is embedded in this
## project. Returned records are detached; Sim alone owns access, actions and state.
## This local snapshot envelope is not the existing worldgen runtime package schema.

const CANONICAL := preload("res://addons/worldgen/core/worldgen_canonical.gd")
const REFERENCE_PATH := "res://addons/worldgen/consumers/ai_town_adapter/fixtures/lt22_cafe_street.world.json"
const FROZEN_TOPOLOGY_SHA256 := "508cebb8815419f4e0db4e6389825c49090a9bc103037b53595ce5b904ce7620"
const Q_PER_CELL := 48

var valid := false
var error := ""
var _topology: Dictionary = {}
var _compatibility: Dictionary = {}
var _presentation: Dictionary = {}

func configure(package: Dictionary) -> Dictionary:
	valid = false
	error = ""
	_topology.clear()
	_compatibility.clear()
	_presentation.clear()
	var reference_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(REFERENCE_PATH))
	if not reference_value is Dictionary:
		return _reject("E_REFERENCE_MISSING")
	var reference: Dictionary = reference_value
	var checked := _check(package, reference)
	if not checked.is_empty(): return _reject(checked)
	var payload: Dictionary = package["payload"]
	_topology = (payload["topology"] as Dictionary).duplicate(true)
	_compatibility = (payload["compatibility"] as Dictionary).duplicate(true)
	_presentation = (payload["presentation"] as Dictionary).duplicate(true)
	valid = true
	return {"ok": true, "topology_sha256": semantic_fingerprint(),
		"presentation_sha256": presentation_fingerprint()}

func _reject(reason: String) -> Dictionary:
	error = reason
	return {"ok": false, "errors": [reason]}

func _check(package: Dictionary, reference: Dictionary) -> String:
	var root_keys := ["schema_id", "schema_version", "logical_scope", "coordinate_frame",
		"producer_ref", "input_refs", "payload", "capabilities", "validation_ref"]
	if not _same_keys(package, root_keys): return "E_ENVELOPE"
	# Godot JSON decodes integral tokens as floats; the Python interchange check
	# enforces lexical integer tokens before a candidate reaches this query.
	if not CANONICAL.validate_value(package).is_empty(): return "E_CANONICAL_VALUE"
	if package.get("schema_id") != "WorldPackage" or not _whole_positive(package.get("schema_version")) \
			or int(package["schema_version"]) != 1: return "E_VERSION"
	for key: String in ["logical_scope", "producer_ref", "input_refs", "capabilities", "validation_ref"]:
		if package.get(key) != reference.get(key): return "E_REFERENCE_" + key.to_upper()
	var frame: Variant = package.get("coordinate_frame")
	if not frame is Dictionary or frame != reference.get("coordinate_frame") \
			or frame.get("id") != "plan_xz_q48/1" or not _whole_positive(frame.get("q_per_cell")) \
			or int(frame["q_per_cell"]) != Q_PER_CELL: return "E_UNITS"
	var payload: Variant = package.get("payload")
	var trusted_payload: Variant = reference.get("payload")
	if not payload is Dictionary or not trusted_payload is Dictionary \
			or not _same_keys(payload, ["topology", "compatibility", "presentation"]): return "E_PAYLOAD"
	var topology: Variant = payload.get("topology")
	if not topology is Dictionary or not _same_keys(topology,
			["planes", "portals", "slots", "affordances", "streets"]): return "E_TOPOLOGY"
	if topology != trusted_payload.get("topology"): return "E_TOPOLOGY_CHANGED"
	var compatibility: Variant = payload.get("compatibility")
	if not compatibility is Dictionary or compatibility != trusted_payload.get("compatibility"):
		return "E_STATE_COMPATIBILITY"
	if compatibility.get("topology_sha256") != FROZEN_TOPOLOGY_SHA256 \
			or CANONICAL.sha256(topology) != FROZEN_TOPOLOGY_SHA256: return "E_TOPOLOGY_HASH"
	var presentation: Variant = payload.get("presentation")
	if not presentation is Dictionary or not _same_keys(presentation,
			["profile", "pixels_per_cell", "digest_sha256"]): return "E_PRESENTATION"
	if typeof(presentation.get("profile")) != TYPE_STRING or String(presentation["profile"]).is_empty() \
			or not _whole_positive(presentation.get("pixels_per_cell")): return "E_PRESENTATION"
	var body := {"profile": presentation["profile"], "pixels_per_cell": presentation["pixels_per_cell"]}
	if CANONICAL.sha256(body) != presentation.get("digest_sha256"): return "E_PRESENTATION_HASH"
	return ""

func _same_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size(): return false
	for key: String in keys:
		if not value.has(key): return false
	return true

func _whole_positive(value: Variant) -> bool:
	if typeof(value) == TYPE_INT: return int(value) > 0 and int(value) <= 2147483647
	if typeof(value) != TYPE_FLOAT: return false
	var number := float(value)
	return is_finite(number) and number > 0 and number <= 2147483647 and number == floor(number)

func semantic_fingerprint() -> String:
	return String(_compatibility.get("topology_sha256", "")) if valid else ""

func presentation_fingerprint() -> String:
	return String(_presentation.get("digest_sha256", "")) if valid else ""

func compatibility_fingerprints() -> Dictionary:
	return _compatibility.duplicate(true) if valid else {}

func _cell(point_q: Array) -> Vector2i:
	return Vector2i(int(point_q[0]) / Q_PER_CELL, int(point_q[1]) / Q_PER_CELL)

func plane_by_address(space: String, floor: String) -> Dictionary:
	if valid:
		for plane: Dictionary in _topology.get("planes", []):
			if plane.get("space") == space and plane.get("floor") == floor:
				return plane.duplicate(true)
	return {}

## False means either blocked or outside this deliberately clipped snapshot.
func walkable(space: String, floor: String, cell: Vector2i) -> bool:
	var plane := plane_by_address(space, floor)
	if plane.is_empty(): return false
	var bounds: Array = plane["bounds_q"]
	var origin := _cell(bounds.slice(0, 2))
	var size := _cell(bounds.slice(2, 4))
	if cell.x < origin.x or cell.y < origin.y or cell.x >= origin.x + size.x or cell.y >= origin.y + size.y:
		return false
	for blocked: Array in plane["blocked_cells_q"]:
		if _cell(blocked) == cell: return false
	return true

func slot_by_id(logical_id: String) -> Dictionary:
	return _record_by("slots", "id", logical_id)

func slot_by_source_id(source_id: String) -> Dictionary:
	return _record_by("slots", "source_id", source_id)

func portal_by_id(logical_id: String) -> Dictionary:
	return _record_by("portals", "id", logical_id)

func portal_by_source_id(source_id: String) -> Dictionary:
	return _record_by("portals", "source_id", source_id)

func affordance_by_id(logical_id: String) -> Dictionary:
	return _record_by("affordances", "id", logical_id)

func street_by_source_id(source_id: String) -> Dictionary:
	return _record_by("streets", "source_id", source_id)

func _record_by(group: String, field: String, wanted: String) -> Dictionary:
	if valid:
		for item: Dictionary in _topology.get(group, []):
			if item.get(field) == wanted: return item.duplicate(true)
	return {}

## These are static candidates with policy metadata, not host authorization.
func portals_from(space: String, floor: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not valid: return result
	for portal: Dictionary in _topology.get("portals", []):
		if (portal["from"].space == space and portal["from"].floor == floor) \
				or (bool(portal.get("bidirectional", false)) and portal["to"].space == space \
				and portal["to"].floor == floor):
			result.append(portal.duplicate(true))
	return result

func affordances_for(slot_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if valid:
		for affordance: Dictionary in _topology.get("affordances", []):
			if affordance.get("slot_id") == slot_id: result.append(affordance.duplicate(true))
	return result
