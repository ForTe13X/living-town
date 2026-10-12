extends SceneTree
## Confirms detached recipe compilation returns data without accessing scene state.

const JOB_SCRIPT := preload("res://addons/worldgen/editor/worldgen_build_job.gd")

func _initialize() -> void:
	var recipe := _read_json("res://addons/worldgen/recipes/inland_neighborhood.json")
	var worker: RefCounted = JOB_SCRIPT.new()
	var thread := Thread.new()
	var start_error := thread.start(Callable(worker, "build_candidate").bind(recipe.duplicate(true)))
	_assert(start_error == OK, "worker thread starts")
	while thread.is_alive(): OS.delay_msec(10)
	var result: Variant = thread.wait_to_finish()
	_assert(result is Dictionary and result.get("ok", false), "detached worker builds and validates a candidate")
	if result is Dictionary and result.get("ok", false):
		_assert(String(result.get("build_id", "")).length() == 64, "worker returns a content-addressed build identity")
		_assert(result.get("package", {}).get("world_id", "") == "inland_neighborhood_s0", "worker preserves recipe identity")
	if _failures.is_empty():
		print("WORLDGEN_BUILD_JOB_TESTS_OK detached=true candidate=validated snapshot=identified")
		worker = null
		thread = null
		quit(0)
	else:
		for failure: String in _failures: push_error(failure)
		worker = null
		thread = null
		quit(1)

var _failures: Array[String] = []

func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	return parser.data if error == OK and parser.data is Dictionary else {}

func _assert(condition: bool, message: String) -> void:
	if not condition: _failures.append("E_BUILD_JOB_TEST: %s" % message)
