extends RefCounted
## Project-owned coastal adapter. The shared WorldGen core never imports coastal rules.

const COASTAL_COMPILER := preload("res://scripts/CoastalPackageCompiler.gd")
const CANONICAL := preload("res://addons/worldgen/core/worldgen_canonical.gd")

func register_into(registry: WorldGenOperatorRegistry) -> Dictionary:
	return registry.register_operator({"id": "worldgen.coastal_compile/1", "schema_revision": "1", "side_effect_class": "pure", "input_ports": {}, "output_ports": {"semantic": "SemanticWorld/1", "presentation": "PresentationWorld/1"}}, Callable(self, "compile_source"))

func compile_source(request: Dictionary) -> Dictionary:
	var source_path := String(request.get("parameters", {}).get("source_spec", ""))
	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null: return {"ok": false, "errors": ["E_COAST_SOURCE: cannot open %s" % source_path]}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not parser.data is Dictionary: return {"ok": false, "errors": ["E_COAST_SOURCE_JSON: %s" % source_path]}
	var compiled: Dictionary = COASTAL_COMPILER.compile_spec(parser.data)
	if not bool(compiled.get("ok", false)): return {"ok": false, "errors": compiled.get("errors", [])}
	var coast_package: Dictionary = compiled["package"]
	var topology: Dictionary = coast_package.get("topology", {})
	var semantic := {"kind": "coastal_neighborhood", "extent_cells": topology.get("extent_cells", []),
		"q_per_cell": 48, "town_id": coast_package.get("town_id", ""), "topology": _normalize_coastal_data(topology),
		"source_topology_sha256": coast_package.get("manifest", {}).get("topology_sha256", "")}
	var presentation: Dictionary = coast_package.get("render", {}).duplicate(true)
	var errors := CANONICAL.validate_value(semantic)
	errors.append_array(CANONICAL.validate_value(presentation))
	if not errors.is_empty(): return {"ok": false, "errors": errors}
	return {"ok": true, "outputs": {"semantic": {"type": "SemanticWorld/1", "data": semantic}, "presentation": {"type": "PresentationWorld/1", "data": presentation}}}

func _normalize_coastal_data(value: Variant, key := "") -> Variant:
	if value is float:
		if key == "access_width_cells": return int(round(float(value) * 48.0))
		if is_equal_approx(float(value), round(float(value))): return int(round(float(value)))
		push_error("E_COAST_QUANTIZE: unsupported fractional field %s" % key)
		return value
	if value is Dictionary:
		var result := {}
		for child_key: Variant in value:
			var normalized_key := "access_width_q" if String(child_key) == "access_width_cells" else String(child_key)
			result[normalized_key] = _normalize_coastal_data(value[child_key], String(child_key))
		return result
	if value is Array:
		var result: Array = []
		if key == "access_path":
			for point: Variant in value:
				if not point is Array: return value
				var q_point: Array = []
				for coordinate: Variant in point: q_point.append(int(round(float(coordinate) * 48.0)))
				result.append(q_point)
			return result
		for item: Variant in value: result.append(_normalize_coastal_data(item, key))
		return result
	return value
