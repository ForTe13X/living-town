extends SceneTree
## Compile a declarative WorldPackage recipe to an immutable JSON file.

const SERVICE_SCRIPT := preload("res://addons/worldgen/core/worldgen_build_service.gd")
const STORE_SCRIPT := preload("res://addons/worldgen/core/worldgen_artifact_store.gd")
const CANONICAL_SCRIPT := preload("res://addons/worldgen/core/worldgen_canonical.gd")
const CACHE_SCRIPT := preload("res://addons/worldgen/core/build_cache.gd")
const DEFAULT_RECIPE := "res://addons/worldgen/recipes/coastal_neighborhood.json"
const DEFAULT_OUTPUT := "res://addons/worldgen/builds/coastal_neighborhood.world.json"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var recipe_path := DEFAULT_RECIPE if args.is_empty() else String(args[0])
	var output_path := DEFAULT_OUTPUT if args.size() < 2 else String(args[1])
	var recipe := _read_json(recipe_path)
	if recipe.is_empty():
		push_error("WORLDGEN_RECIPE: cannot parse %s" % recipe_path)
		quit(2)
		return
	var result: Dictionary = SERVICE_SCRIPT.build_package(recipe, CACHE_SCRIPT.new())
	if not result.get("ok", false):
		for error: String in result.get("errors", []): push_error(error)
		quit(1)
		return
	var package: Dictionary = result["package"]
	var stored: Dictionary = STORE_SCRIPT.new().put_json("res://addons/worldgen/builds/objects", package)
	if not stored.get("ok", false):
		for error: String in stored.get("errors", []): push_error(error)
		quit(2)
		return
	var absolute_dir := ProjectSettings.globalize_path(output_path.get_base_dir())
	var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		push_error("WORLDGEN_OUTPUT_DIR: %s" % output_path.get_base_dir())
		quit(2)
		return
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("WORLDGEN_OUTPUT: cannot write %s" % output_path)
		quit(2)
		return
	file.store_string(CANONICAL_SCRIPT.canonical_json(package) + "\n")
	file.close()
	var cache_hits := 0
	for event: Dictionary in result.get("execution_metrics", []):
		if bool(event.get("cache_hit", false)): cache_hits += 1
	print("WORLDGEN_BUILD_OK world=%s semantic=%s presentation=%s object=%s cache_hits=%d output=%s" % [package["world_id"], package["digests"]["semantic_sha256"], package["digests"]["presentation_sha256"], stored["path"], cache_hits, output_path])
	quit(0)

func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	return parser.data if error == OK and parser.data is Dictionary else {}
