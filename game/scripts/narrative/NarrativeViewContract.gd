class_name NarrativeViewContract
extends RefCounted
## S06 · Role-filtered snapshot v0.
##
## This boundary turns an authoritative narrative pre-state into the only data a
## visual component may receive.  It deliberately returns IDs, clock numbers,
## and a small status enum: claim prose, receipt bodies, fragment bodies, and
## the global ledger never cross the boundary.

const SNAPSHOT_KEYS := [
	"role_id",
	"now_node",
	"visible_nodes",
	"visible_edges",
	"carried_fragment_ids",
	"receipt_ids",
	"open_request_ids",
	"route_hint",
	"clock",
	"status",
]

const CLOCK_KEYS := ["day", "watch", "tick"]
const STATUS_IDS := ["active", "blocked", "complete"]


static func project(pre_state: Dictionary, role_id: String) -> Dictionary:
	var errors: Array[String] = []
	var roles := _dict_field(pre_state, "roles", errors)
	var nodes := _dict_field(pre_state, "nodes", errors)
	var edges := _dict_field(pre_state, "edges", errors)
	var fragments := _dict_field(pre_state, "fragments", errors)
	var receipts := _dict_field(pre_state, "receipts", errors)
	var claims := _dict_field(pre_state, "claims", errors)
	var requests := _dict_field(pre_state, "requests", errors)
	if role_id.is_empty():
		errors.append("role.empty")
	if not roles.has(role_id):
		errors.append("role.unknown:%s" % role_id)
		return _result({}, errors)
	if not roles[role_id] is Dictionary:
		errors.append("role.type:%s" % role_id)
		return _result({}, errors)

	var role: Dictionary = roles[role_id]
	var now_node := _string_field(role, "now_node", errors)
	var visible_nodes := _sorted_ids(role.get("visible_node_ids"), "visible_node_ids", errors)
	var visible_node_set := _set_of(visible_nodes)
	if not nodes.has(now_node):
		errors.append("node.unknown:%s" % now_node)
	elif not visible_node_set.has(now_node):
		errors.append("node.current_not_visible:%s" % now_node)
	for node_id in visible_nodes:
		if not nodes.has(node_id):
			errors.append("node.unknown:%s" % node_id)

	var visible_edges := _sorted_ids(role.get("visible_edge_ids"), "visible_edge_ids", errors)
	for edge_id in visible_edges:
		if not edges.has(edge_id):
			errors.append("edge.unknown:%s" % edge_id)
			continue
		if not edges[edge_id] is Dictionary:
			errors.append("edge.type:%s" % edge_id)
			continue
		var edge: Dictionary = edges[edge_id]
		var from_node := String(edge.get("from_node", ""))
		var to_node := String(edge.get("to_node", ""))
		if not nodes.has(from_node):
			errors.append("edge.endpoint_unknown:%s:from:%s" % [edge_id, from_node])
		if not nodes.has(to_node):
			errors.append("edge.endpoint_unknown:%s:to:%s" % [edge_id, to_node])
		if not visible_node_set.has(from_node) or not visible_node_set.has(to_node):
			errors.append("edge.endpoint_hidden:%s" % edge_id)

	var carried_fragment_ids := _sorted_ids(role.get("carried_fragment_ids"), "carried_fragment_ids", errors)
	for fragment_id in carried_fragment_ids:
		if not fragments.has(fragment_id):
			errors.append("fragment.unknown:%s" % fragment_id)
			continue
		if not fragments[fragment_id] is Dictionary:
			errors.append("fragment.type:%s" % fragment_id)
			continue
		var custodian := String((fragments[fragment_id] as Dictionary).get("custodian_role_id", ""))
		if custodian != role_id:
			errors.append("fragment.foreign_custody:%s:%s" % [fragment_id, custodian])

	var receipt_ids := _sorted_ids(role.get("receipt_ids"), "receipt_ids", errors)
	for receipt_id in receipt_ids:
		_validate_receipt(receipts, claims, receipt_id, role_id, errors)

	var open_request_ids := _sorted_ids(role.get("open_request_ids"), "open_request_ids", errors)
	for request_id in open_request_ids:
		if not requests.has(request_id):
			errors.append("request.unknown:%s" % request_id)
			continue
		if not requests[request_id] is Dictionary:
			errors.append("request.type:%s" % request_id)
			continue
		var audience := _sorted_ids((requests[request_id] as Dictionary).get("role_ids"), "request.role_ids", errors)
		if not role_id in audience:
			errors.append("request.foreign:%s" % request_id)

	var route_hint := _id_sequence(role.get("route_hint"), "route_hint", errors)
	for node_id in route_hint:
		if not nodes.has(node_id):
			errors.append("route.node_unknown:%s" % node_id)
		elif not visible_node_set.has(node_id):
			errors.append("route.node_hidden:%s" % node_id)

	var clock := _clock(role.get("clock"), errors)
	var status := _string_field(role, "status", errors)
	if not status in STATUS_IDS:
		errors.append("status.unknown:%s" % status)

	var snapshot := {
		"role_id": role_id,
		"now_node": now_node,
		"visible_nodes": visible_nodes,
		"visible_edges": visible_edges,
		"carried_fragment_ids": carried_fragment_ids,
		"receipt_ids": receipt_ids,
		"open_request_ids": open_request_ids,
		"route_hint": route_hint,
		"clock": clock,
		"status": status,
	}
	return _result(snapshot, errors)


static func validate_snapshot(pre_state: Dictionary, snapshot: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var allowed := _set_of(Array(SNAPSHOT_KEYS))
	for key in snapshot.keys():
		var field := String(key)
		if not allowed.has(field):
			errors.append("snapshot.extra:%s" % field)
	for field in SNAPSHOT_KEYS:
		if not snapshot.has(field):
			errors.append("snapshot.missing:%s" % field)
	if not errors.is_empty():
		errors.sort()
		return errors
	if not snapshot["role_id"] is String:
		return ["snapshot.type:role_id"]

	var expected := project(pre_state, String(snapshot["role_id"]))
	if not bool(expected["ok"]):
		for error in expected["errors"]:
			errors.append("authority.%s" % String(error))
		errors.sort()
		return errors
	var canonical: Dictionary = expected["snapshot"]
	for field in SNAPSHOT_KEYS:
		if snapshot[field] != canonical[field]:
			errors.append("snapshot.mismatch:%s" % field)
	errors.sort()
	return errors


static func claim_access(pre_state: Dictionary, role_id: String, claim_id: String) -> Dictionary:
	var errors: Array[String] = []
	var roles := _dict_field(pre_state, "roles", errors)
	var receipts := _dict_field(pre_state, "receipts", errors)
	var claims := _dict_field(pre_state, "claims", errors)
	if not roles.has(role_id) or not roles[role_id] is Dictionary:
		errors.append("role.unknown:%s" % role_id)
		return _access_result(false, errors)
	if not claims.has(claim_id):
		errors.append("claim.unknown:%s" % claim_id)
		return _access_result(false, errors)
	var role: Dictionary = roles[role_id]
	var receipt_ids := _sorted_ids(role.get("receipt_ids"), "receipt_ids", errors)
	for receipt_id in receipt_ids:
		if not receipts.has(receipt_id) or not receipts[receipt_id] is Dictionary:
			continue
		var receipt: Dictionary = receipts[receipt_id]
		if String(receipt.get("role_id", "")) == role_id and String(receipt.get("claim_id", "")) == claim_id:
			return _access_result(errors.is_empty(), errors)
	errors.append("claim.unauthorized:%s:%s" % [role_id, claim_id])
	return _access_result(false, errors)


static func _validate_receipt(receipts: Dictionary, claims: Dictionary, receipt_id: String, role_id: String, errors: Array[String]) -> void:
	if not receipts.has(receipt_id):
		errors.append("receipt.unknown:%s" % receipt_id)
		return
	if not receipts[receipt_id] is Dictionary:
		errors.append("receipt.type:%s" % receipt_id)
		return
	var receipt: Dictionary = receipts[receipt_id]
	var owner := String(receipt.get("role_id", ""))
	if owner != role_id:
		errors.append("receipt.foreign:%s:%s" % [receipt_id, owner])
	var claim_id := String(receipt.get("claim_id", ""))
	if claim_id.is_empty() or not claims.has(claim_id):
		errors.append("receipt.claim_unknown:%s:%s" % [receipt_id, claim_id])


static func _dict_field(source: Dictionary, field: String, errors: Array[String]) -> Dictionary:
	if not source.has(field):
		errors.append("state.missing:%s" % field)
		return {}
	if not source[field] is Dictionary:
		errors.append("state.type:%s" % field)
		return {}
	return source[field]


static func _string_field(source: Dictionary, field: String, errors: Array[String]) -> String:
	if not source.has(field):
		errors.append("field.missing:%s" % field)
		return ""
	if not source[field] is String or String(source[field]).is_empty():
		errors.append("field.type:%s" % field)
		return ""
	return String(source[field])


static func _sorted_ids(raw, field: String, errors: Array[String]) -> Array[String]:
	var out: Array[String] = []
	if not raw is Array:
		errors.append("field.type:%s" % field)
		return out
	var seen := {}
	for value in raw:
		if not value is String or String(value).is_empty():
			errors.append("id.type:%s" % field)
			continue
		var item := String(value)
		if seen.has(item):
			errors.append("id.duplicate:%s:%s" % [field, item])
			continue
		seen[item] = true
		out.append(item)
	out.sort()
	return out


static func _id_sequence(raw, field: String, errors: Array[String]) -> Array[String]:
	var out: Array[String] = []
	if not raw is Array:
		errors.append("field.type:%s" % field)
		return out
	for value in raw:
		if not value is String or String(value).is_empty():
			errors.append("id.type:%s" % field)
			continue
		out.append(String(value))
	return out


static func _clock(raw, errors: Array[String]) -> Dictionary:
	if not raw is Dictionary:
		errors.append("field.type:clock")
		return {}
	var clock: Dictionary = raw
	var out := {}
	var allowed := _set_of(Array(CLOCK_KEYS))
	for key in clock.keys():
		if not allowed.has(String(key)):
			errors.append("clock.extra:%s" % String(key))
	for key in CLOCK_KEYS:
		if not clock.has(key):
			continue
		if not clock[key] is int or int(clock[key]) < 0:
			errors.append("clock.type:%s" % key)
		else:
			out[key] = int(clock[key])
	if not clock.has("watch"):
		errors.append("clock.missing:watch")
	return out


static func _set_of(values: Array) -> Dictionary:
	var out := {}
	for value in values:
		out[String(value)] = true
	return out


static func _result(snapshot: Dictionary, errors: Array[String]) -> Dictionary:
	errors.sort()
	return {"ok": errors.is_empty(), "snapshot": snapshot if errors.is_empty() else {}, "errors": errors}


static func _access_result(ok: bool, errors: Array[String]) -> Dictionary:
	errors.sort()
	return {"ok": ok and errors.is_empty(), "errors": errors}
