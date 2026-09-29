extends SceneTree
## Positive controls: explicit paths remain valid, including spaces and res://.

func _init() -> void:
	var parser = preload("res://bench/BenchArgs.gd")
	var flags := ["--golden", "--bake-golden", "--anchor", "--bake-anchor", "--shadow-dump", "--chain-dump", "--chain-ref"]
	var failures := 0
	for flag in flags:
		for path in ["game/bench/output.json", "res://bench/output.json", "user://output.json", "C:/test directory/output.json"]:
			if parser.path_error(PackedStringArray([flag, path, "--days", "1"]), flags) != "":
				print("BenchArgsTest: FAIL: valid path rejected: %s %s" % [flag, path])
				failures += 1
	if parser.path_error(PackedStringArray(["--days", "1"]), flags) != "":
		failures += 1
	print("BenchArgsTest: %s (29 valid argument controls)" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
