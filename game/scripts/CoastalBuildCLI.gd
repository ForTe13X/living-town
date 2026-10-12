extends SceneTree
## Build a Godot-ready frozen package from an authored coastal town.spec.json.

const DEFAULT_INPUT := "res://coastal/warm_bay_s1/town.spec.json"
const DEFAULT_OUTPUT := "res://coastal/warm_bay_s1/export/package.json"
const COMPILER := preload("res://scripts/CoastalPackageCompiler.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var input_path := DEFAULT_INPUT if args.is_empty() else args[0]
	var output_path := DEFAULT_OUTPUT if args.size() < 2 else args[1]
	var input_file := FileAccess.open(input_path, FileAccess.READ)
	if input_file == null:
		push_error("E_INPUT: cannot open %s" % input_path)
		quit(2)
		return
	var parsed := JSON.new()
	var parse_error := parsed.parse(input_file.get_as_text())
	if parse_error != OK or not parsed.data is Dictionary:
		push_error("E_JSON: %s at line %d" % [parsed.get_error_message(), parsed.get_error_line()])
		quit(2)
		return
	var result: Dictionary = COMPILER.compile_spec(parsed.data)
	if not bool(result.get("ok", false)):
		for error: String in result.get("errors", []):
			push_error(error)
		quit(1)
		return
	var output_dir := output_path.get_base_dir()
	var absolute_dir := ProjectSettings.globalize_path(output_dir)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		push_error("E_OUTPUT_DIR: could not create %s" % output_dir)
		quit(2)
		return
	var output_file := FileAccess.open(output_path, FileAccess.WRITE)
	if output_file == null:
		push_error("E_OUTPUT: cannot write %s" % output_path)
		quit(2)
		return
	output_file.store_string(JSON.stringify(result["package"], "\t", true, true) + "\n")
	output_file.close()
	var manifest: Dictionary = result["package"]["manifest"]
	print("COAST_BUILD_OK town=%s topology=%s render=%s output=%s" % [result["package"]["town_id"], manifest["topology_sha256"], manifest["render_sha256"], output_path])
	quit(0)
