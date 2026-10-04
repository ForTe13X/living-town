extends RefCounted
class_name WorldGenRecipeCompiler
## Type-check and topologically order declarative recipes without evaluating code.

static func compile_recipe(recipe: Variant, registry: WorldGenOperatorRegistry) -> Dictionary:
	var errors: Array[String] = []
	if not recipe is Dictionary or String(recipe.get("schema", "")) != "worldgen.recipe/1":
		return {"ok": false, "errors": ["E_RECIPE_SCHEMA: expected worldgen.recipe/1"]}
	for key: String in recipe:
		if key not in ["schema", "id", "source_revision", "coordinate_frame", "capabilities", "stages", "outputs"]:
			errors.append("E_RECIPE_FIELD: unsupported recipe field %s" % key)
	var stages: Variant = recipe.get("stages", [])
	if not stages is Array or stages.is_empty() or stages.size() > 256:
		return {"ok": false, "errors": ["E_RECIPE_STAGES: stages must be a non-empty array"]}
	var by_id := {}
	for raw: Variant in stages:
		if not raw is Dictionary:
			errors.append("E_RECIPE_STAGE: stage must be an object")
			continue
		var id := String(raw.get("id", ""))
		var operator_id := String(raw.get("operator", ""))
		for key: String in raw:
			if key not in ["id", "operator", "inputs", "parameters", "operation_budget", "seed_policy", "pins_digest", "boundary_digest", "allowed_candidates", "structural_pack_manifest", "visual_pack_manifest", "validator_policy"]:
				errors.append("E_RECIPE_STAGE_FIELD: %s has unsupported field %s" % [id, key])
		if id.is_empty() or id.contains(".") or by_id.has(id):
			errors.append("E_RECIPE_ID: empty or duplicate stage id '%s'" % id)
			continue
		if not registry.has_operator(operator_id):
			errors.append("E_RECIPE_OPERATOR: %s is not registered" % operator_id)
			continue
		by_id[id] = raw.duplicate(true)
	var deps := {}
	for id: String in by_id:
		deps[id] = []
	for id: String in by_id:
		var stage: Dictionary = by_id[id]
		var spec := registry.get_spec(String(stage["operator"]))
		var input_ports: Dictionary = spec.get("input_ports", {})
		var output_ports: Dictionary = spec.get("output_ports", {})
		var bindings: Dictionary = stage.get("inputs", {})
		for port: String in input_ports:
			if not bindings.has(port):
				errors.append("E_RECIPE_INPUT: %s missing port %s" % [id, port])
		for port: String in bindings:
			if not input_ports.has(port):
				errors.append("E_RECIPE_PORT: %s has unknown input %s" % [id, port])
				continue
			var ref := String(bindings[port])
			var separator := ref.find(".")
			if separator < 1:
				errors.append("E_RECIPE_REF: %s.%s must reference stage.output" % [id, port])
				continue
			var source_id := ref.left(separator)
			var source_port := ref.substr(separator + 1)
			if not by_id.has(source_id):
				errors.append("E_RECIPE_REF: %s.%s references missing stage %s" % [id, port, source_id])
				continue
			var source_spec := registry.get_spec(String(by_id[source_id]["operator"]))
			var source_outputs: Dictionary = source_spec.get("output_ports", {})
			if not source_outputs.has(source_port):
				errors.append("E_RECIPE_REF: %s.%s is not an output on %s" % [ref, source_port, source_id])
			elif String(source_outputs[source_port]) != String(input_ports[port]):
				errors.append("E_RECIPE_TYPE: %s.%s expects %s, got %s" % [id, port, input_ports[port], source_outputs[source_port]])
			else:
				deps[id].append(source_id)
		for output_port: String in output_ports:
			if output_port.is_empty():
				errors.append("E_RECIPE_OUTPUT: %s declares an empty output port" % id)
	var declared_outputs: Dictionary = recipe.get("outputs", {})
	if declared_outputs.is_empty(): errors.append("E_RECIPE_OUTPUTS: at least one named package output is required")
	for output_name: String in declared_outputs:
		var output_ref := String(declared_outputs[output_name])
		var separator := output_ref.find(".")
		if separator < 1 or not by_id.has(output_ref.left(separator)):
			errors.append("E_RECIPE_OUTPUT_REF: output %s points to missing stage/output" % output_name)
			continue
		var output_spec := registry.get_spec(String(by_id[output_ref.left(separator)]["operator"]))
		if not output_spec.get("output_ports", {}).has(output_ref.substr(separator + 1)):
			errors.append("E_RECIPE_OUTPUT_REF: output %s points to missing port %s" % [output_name, output_ref])
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var pending := by_id.keys()
	pending.sort()
	var ordered: Array = []
	while not pending.is_empty():
		var ready: Array[String] = []
		for id: String in pending:
			var blocked := false
			for dep: String in deps[id]:
				if pending.has(dep):
					blocked = true
					break
			if not blocked:
				ready.append(id)
		if ready.is_empty():
			return {"ok": false, "errors": ["E_RECIPE_CYCLE: stage graph contains a cycle"]}
		ready.sort()
		for id: String in ready:
			ordered.append(by_id[id])
			pending.erase(id)
	return {"ok": true, "recipe": recipe.duplicate(true), "ordered_stages": ordered}
