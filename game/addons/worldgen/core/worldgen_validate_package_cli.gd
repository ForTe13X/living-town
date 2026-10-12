extends SceneTree
## Validate a frozen WorldPackage and emit a digest-bound validation receipt.

const VALIDATOR := preload("res://addons/worldgen/core/worldgen_package_validator.gd")
const CANONICAL := preload("res://addons/worldgen/core/worldgen_canonical.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("WORLDGEN_VALIDATE_USAGE: expected <package.json> <validation-report.json>")
		quit(2)
		return
	var package_path := String(args[0])
	var report_path := String(args[1])
	var file := FileAccess.open(package_path, FileAccess.READ)
	if file == null:
		push_error("WORLDGEN_VALIDATE_INPUT: cannot read %s" % package_path)
		quit(2)
		return
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not parser.data is Dictionary:
		push_error("WORLDGEN_VALIDATE_JSON: %s" % package_path)
		quit(2)
		return
	var package: Dictionary = parser.data
	var result: Dictionary = VALIDATOR.validate(package)
	if not bool(result.get("ok", false)):
		for error: String in result.get("errors", []): push_error(error)
		quit(1)
		return
	var candidate_sha256 := CANONICAL.sha256(package)
	var report := {
		"schema": "worldgen.validation/1",
		"status": "passed",
		"world_id": String(package.get("world_id", "")),
		"candidate_sha256": candidate_sha256,
		"checker": {"id": "WorldGenPackageValidator", "version": "1"},
		"evidence": [{"id": "worldpackage-validation", "sha256": candidate_sha256, "source": package_path}]
	}
	var output := FileAccess.open(report_path, FileAccess.WRITE)
	if output == null:
		push_error("WORLDGEN_VALIDATE_OUTPUT: cannot write %s" % report_path)
		quit(2)
		return
	output.store_string(CANONICAL.canonical_json(report) + "\n")
	output.flush()
	output.close()
	print("WORLDGEN_VALIDATION_OK world=%s candidate=%s report=%s" % [report["world_id"], candidate_sha256, report_path])
	quit(0)
