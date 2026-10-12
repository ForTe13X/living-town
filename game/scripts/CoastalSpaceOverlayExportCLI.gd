extends SceneTree
## Export an optional coastal overlay for manual integration with Living Town data.

const EXPORTER := preload("res://scripts/CoastalSpaceGraphExporter.gd")
const PACKAGE_COMPILER := preload("res://scripts/CoastalPackageCompiler.gd")
const DEFAULT_INPUT := "res://coastal/warm_bay_s1/export/package.json"
const DEFAULT_OUTPUT_DIR := "res://coastal/warm_bay_s1/export/sim_adapter"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var input_path := DEFAULT_INPUT if args.is_empty() else args[0]
	var output_dir := DEFAULT_OUTPUT_DIR if args.size() < 2 else args[1]
	var input_file := FileAccess.open(input_path, FileAccess.READ)
	if input_file == null:
		push_error("E_INPUT: cannot open %s" % input_path)
		quit(2)
		return
	var parsed := JSON.new()
	var parse_error := parsed.parse(input_file.get_as_text())
	input_file.close()
	if parse_error != OK or not parsed.data is Dictionary:
		push_error("E_JSON: %s at line %d" % [parsed.get_error_message(), parsed.get_error_line()])
		quit(2)
		return
	var result: Dictionary = EXPORTER.compile_overlay(parsed.data)
	if not bool(result.get("ok", false)):
		for error: String in result.get("errors", []):
			push_error(error)
		quit(1)
		return
	var absolute_dir := ProjectSettings.globalize_path(output_dir)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		push_error("E_OUTPUT_DIR: could not create %s" % output_dir)
		quit(2)
		return
	var artifact_values := {
		"spaces.overlay.json": result["spaces"],
		"interiors.overlay.json": result["interiors"],
		"affordances.overlay.json": result["affordances"]
	}
	var artifact_hashes := {}
	for filename: String in artifact_values:
		artifact_hashes[filename] = _sha256(PACKAGE_COMPILER.canonical_json(artifact_values[filename]))
	var manifest: Dictionary = result["metadata"].duplicate(true)
	manifest["schema"] = "living-town.coastal-sim-overlay/1"
	manifest["compiler"] = "coast-sim-overlay/1"
	manifest["artifacts"] = artifact_hashes
	for filename: String in artifact_values:
		if not _write_json(output_dir.path_join(filename), artifact_values[filename]):
			quit(2)
			return
	if not _write_json(output_dir.path_join("manifest.json"), manifest):
		quit(2)
		return
	print("COAST_OVERLAY_OK spaces=%d portals=%d affordances=%d blocked=%d output=%s" % [result["metadata"]["space_count"], result["metadata"]["portal_count"], result["metadata"]["affordance_count"], result["metadata"]["blocked_outdoor_cells"], output_dir])
	quit(0)


func _write_json(path: String, value: Variant) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("E_OUTPUT: cannot write %s" % path)
		return false
	file.store_string(JSON.stringify(value, "\t", true, true) + "\n")
	file.close()
	return true


func _sha256(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()
