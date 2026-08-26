extends SceneTree
## Runner-only negative control: Godot exits zero while the standard final verdict is red.
## A trustworthy local receipt must classify this as a logical test failure.

func _initialize() -> void:
	print("supervisor_logic_failure_test: FAIL (1 fail)")
	quit(0)
