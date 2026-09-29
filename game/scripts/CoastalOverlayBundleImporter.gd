extends RefCounted
class_name CoastalOverlayBundleImporter
## Verify a coastal overlay bundle and merge it into detached caller-owned dictionaries.
## Nothing is written to Sim or the project's live data files.

const MANIFEST_SCHEMA := "living-town.coastal-sim-overlay/1"
const SPACES_GRAPH := preload("res://scripts/SpaceGraph.gd")
const PACKAGE_COMPILER := preload("res://scripts/CoastalPackageCompiler.gd")
const ACTION_BINDINGS := {"sleep": "睡觉", "seat": "歇着", "rest": "歇着", "bath": "泡澡"}


static func load_and_merge(directory_path: String, base_space_graph: Dictionary, base_interiors: Dictionary, base_affordances: Array = []) -> Dictionary:
	var manifest_value: Variant = _read_json(directory_path.path_join("manifest.json"))
	if not manifest_value is Dictionary:
		return _failure("E_COAST_BUNDLE_MANIFEST: manifest is missing or invalid JSON")
	var manifest: Dictionary = manifest_value
	if str(manifest.get("schema", "")) != MANIFEST_SCHEMA:
		return _failure("E_COAST_BUNDLE_SCHEMA: unsupported coastal overlay manifest")
	var artifact_names := ["spaces.overlay.json", "interiors.overlay.json", "affordances.overlay.json"]
	var artifacts := {}
	for filename: String in artifact_names:
		var value: Variant = _read_json(directory_path.path_join(filename))
		if not value is Dictionary:
			return _failure("E_COAST_BUNDLE_ARTIFACT: %s is missing or invalid JSON" % filename)
		var expected_hash := str(manifest.get("artifacts", {}).get(filename, ""))
		var actual_hash := _sha256(PACKAGE_COMPILER.canonical_json(value))
		if expected_hash.is_empty() or expected_hash != actual_hash:
			return _failure("E_COAST_BUNDLE_HASH: %s does not match the manifest" % filename)
		artifacts[filename] = value
	var overlay_graph: Dictionary = artifacts["spaces.overlay.json"]
	var overlay_interiors: Dictionary = artifacts["interiors.overlay.json"]
	var overlay_affordances: Dictionary = artifacts["affordances.overlay.json"]
	if not overlay_graph.get("spaces") is Dictionary or not overlay_graph.get("portals") is Array:
		return _failure("E_COAST_BUNDLE_GRAPH: spaces artifact needs spaces and portals")
	if not overlay_affordances.get("affordances") is Array:
		return _failure("E_COAST_BUNDLE_AFFORDANCES: affordances artifact needs an affordances array")
	if not overlay_affordances.get("home_anchors", []) is Array:
		return _failure("E_COAST_BUNDLE_HOMES: home_anchors must be an array")
	var merged_spaces: Dictionary = base_space_graph.get("spaces", {}).duplicate(true)
	var merged_portals: Array = base_space_graph.get("portals", []).duplicate(true)
	var merged_interiors := base_interiors.duplicate(true)
	for space_id: String in overlay_graph["spaces"]:
		if merged_spaces.has(space_id):
			return _failure("E_COAST_BUNDLE_CONFLICT: space '%s' already exists" % space_id)
		merged_spaces[space_id] = overlay_graph["spaces"][space_id].duplicate(true)
	var portal_ids := {}
	for portal: Dictionary in merged_portals:
		portal_ids[str(portal.get("id", ""))] = true
	for portal: Dictionary in overlay_graph["portals"]:
		var portal_id := str(portal.get("id", ""))
		if portal_id.is_empty() or portal_ids.has(portal_id):
			return _failure("E_COAST_BUNDLE_CONFLICT: portal '%s' is empty or already exists" % portal_id)
		portal_ids[portal_id] = true
		merged_portals.append(portal.duplicate(true))
	for space_id: String in overlay_interiors:
		if merged_interiors.has(space_id):
			return _failure("E_COAST_BUNDLE_CONFLICT: interior content for '%s' already exists" % space_id)
		merged_interiors[space_id] = overlay_interiors[space_id].duplicate(true)
	var graph: RefCounted = SPACES_GRAPH.new()
	graph.spaces = merged_spaces
	graph.portals = merged_portals
	var graph_errors: Array = graph.validate()
	if not graph_errors.is_empty():
		return {"ok": false, "errors": graph_errors}
	var home_spaces := {}
	for home_anchor: Dictionary in overlay_affordances.get("home_anchors", []):
		var building_id := str(home_anchor.get("building_id", ""))
		var start_space_id := str(home_anchor.get("space_id", ""))
		var home_space_id := str(home_anchor.get("home_space_id", ""))
		if building_id.is_empty() or home_spaces.has(building_id):
			return _failure("E_COAST_BUNDLE_HOME: duplicate or empty building home anchor '%s'" % building_id)
		home_spaces[building_id] = home_space_id
		if not graph.has_floor(start_space_id, str(home_anchor.get("floor_id", ""))) or not graph.has_space(home_space_id):
			return _failure("E_COAST_BUNDLE_HOME: %s start or dwelling space is not authored" % building_id)
		var entry_portal_id := str(home_anchor.get("entry_portal_id", ""))
		var found_entry := false
		for portal: Dictionary in overlay_graph["portals"]:
			if str(portal.get("id", "")) != entry_portal_id:
				continue
			found_entry = true
			var portal_to: Dictionary = portal.get("to", {})
			if str(portal.get("access", "")) != "owner" or str(portal.get("owner_space", "")) != home_space_id \
					or str(portal_to.get("space", "")) != start_space_id:
				return _failure("E_COAST_BUNDLE_HOME_ACCESS: %s entry does not match its resident home space" % building_id)
		if not found_entry:
			return _failure("E_COAST_BUNDLE_HOME_PORTAL: %s entry portal is missing" % building_id)
	for portal: Dictionary in overlay_graph["portals"]:
		var portal_id := str(portal.get("id", ""))
		for building_id: String in home_spaces:
			if portal_id.begins_with("coastal_s1/" + building_id + ".") and str(portal.get("access", "")) == "owner" \
					and str(portal.get("owner_space", "")) != str(home_spaces[building_id]):
				return _failure("E_COAST_BUNDLE_HOME_ACCESS: %s private door does not use the resident home space" % portal_id)
	var affordances: Array = base_affordances.duplicate(true)
	var affordance_ids := {}
	var action_profiles := _existing_action_profiles(base_interiors)
	var bound_affordance_count := 0
	var unbound_affordance_ids: Array[String] = []
	for affordance: Dictionary in affordances:
		affordance_ids[str(affordance.get("id", ""))] = true
	for affordance: Dictionary in overlay_affordances["affordances"]:
		var affordance_id := str(affordance.get("id", ""))
		var address: Dictionary = affordance.get("address", {})
		var space_id := str(address.get("space_id", ""))
		var floor_id := str(address.get("floor_id", ""))
		if affordance_id.is_empty() or affordance_ids.has(affordance_id):
			return _failure("E_COAST_BUNDLE_CONFLICT: affordance '%s' is empty or already exists" % affordance_id)
		if not graph.has_floor(space_id, floor_id):
			return _failure("E_COAST_BUNDLE_ADDRESS: %s points to an unknown space/floor" % affordance_id)
		var route: Dictionary = affordance.get("route", {})
		if route.get("path_q", []).is_empty():
			return _failure("E_COAST_BUNDLE_ROUTE: %s has no compiled entry route" % affordance_id)
		var binding_action := str(ACTION_BINDINGS.get(str(affordance.get("action", "")), ""))
		if binding_action.is_empty():
			affordance["runtime_binding"] = "unbound: no existing action mapping"
			unbound_affordance_ids.append(affordance_id)
		else:
			var advertisement: Dictionary = action_profiles.get(binding_action, {})
			if advertisement.is_empty():
				return _failure("E_COAST_BUNDLE_ACTION: %s maps to missing project action '%s'" % [affordance_id, binding_action])
			var floor_content: Dictionary = (merged_interiors[space_id] as Dictionary).get(floor_id, {})
			var furniture: Array = floor_content.get("furniture", [])
			furniture.append({"slot": "coastal_affordance", "label": affordance_id, "pos": address.get("position", []),
				"size": [1, 1], "coastal_affordance_id": affordance_id, "advertises": [advertisement.duplicate(true)]})
			floor_content["furniture"] = furniture
			(merged_interiors[space_id] as Dictionary)[floor_id] = floor_content
			affordance["runtime_binding"] = "existing_action:" + binding_action
			bound_affordance_count += 1
		affordance_ids[affordance_id] = true
		affordances.append(affordance.duplicate(true))
	for home_anchor: Dictionary in overlay_affordances.get("home_anchors", []):
		if not graph.has_floor(str(home_anchor.get("space_id", "")), str(home_anchor.get("floor_id", ""))) \
				or not graph.has_space(str(home_anchor.get("home_space_id", ""))):
			return _failure("E_COAST_BUNDLE_HOME: %s points to an unknown start or dwelling space" % str(home_anchor.get("building_id", "?")))
	return {"ok": true, "errors": [], "spaces": {"spaces": merged_spaces, "portals": merged_portals},
		"interiors": merged_interiors, "affordances": affordances, "manifest": manifest.duplicate(true),
		"home_anchors": overlay_affordances.get("home_anchors", []).duplicate(true),
		"runtime_binding": {"bound_count": bound_affordance_count, "unbound_ids": unbound_affordance_ids}}


static func _existing_action_profiles(interiors: Dictionary) -> Dictionary:
	var profiles := {}
	for space_id: String in interiors:
		if space_id.begins_with("_") or not (interiors[space_id] is Dictionary):
			continue
		for floor_id: String in (interiors[space_id] as Dictionary):
			var floor_content: Variant = (interiors[space_id] as Dictionary)[floor_id]
			if not floor_content is Dictionary:
				continue
			for furniture: Variant in (floor_content as Dictionary).get("furniture", []):
				if not furniture is Dictionary:
					continue
				for advertisement: Variant in (furniture as Dictionary).get("advertises", []):
					if not advertisement is Dictionary:
						continue
					var action := str(advertisement.get("action", ""))
					if not action.is_empty() and not profiles.has(action):
						profiles[action] = advertisement.duplicate(true)
	return profiles


static func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed := JSON.new()
	var error := parsed.parse(file.get_as_text())
	file.close()
	return parsed.data if error == OK else null


static func _sha256(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "errors": [error]}
