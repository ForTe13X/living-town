extends RefCounted
## Fixed packaged checks for release templates without --scene support.
## No flag means no routing or mutation. Never accepts an arbitrary script path.

const CHECKS := {
	"journey": "res://scenes/player_first_session_test.tscn",
	"save-resume": "res://scenes/save_resume_test.tscn",
	"resume-write": "res://scenes/desktop_resume_test.tscn",
	"resume-read": "res://scenes/desktop_resume_test.tscn",
	"save-denied": "res://scenes/desktop_resume_test.tscn",
}
const STARTED := "living_town_desktop_check_started"

static func game_args() -> PackedStringArray:
	var args := OS.get_cmdline_user_args()
	var clean := PackedStringArray()
	var i := 0
	while i < args.size():
		if args[i] == "--desktop-check":
			i += 2
		else:
			clean.append(args[i])
			i += 1
	return clean

static func route(main: Node) -> bool:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--desktop-check")
	if index < 0 or main.get_tree().has_meta(STARTED):
		return false
	main.set_process(false)
	main.set_physics_process(false)
	main.set_process_input(false)
	main.set_process_unhandled_input(false)
	var name := args[index + 1] if index + 1 < args.size() else ""
	if not OS.has_feature("desktop_logic") or not CHECKS.has(name) or args.count("--desktop-check") != 1:
		push_error("Invalid --desktop-check; expected a registered packaged check")
		main.get_tree().quit(2)
		return true
	var path: String = CHECKS[name]
	if not ResourceLoader.exists(path):
		push_error("Packaged desktop check is missing: " + path)
		main.get_tree().quit(2)
		return true
	main.get_tree().set_meta(STARTED, true)
	print("DESKTOP_CHECK " + JSON.stringify({"check": name, "user_dir": OS.get_user_data_dir(),
		"executable": OS.get_executable_path(), "embedded_model_available": ClassDB.class_exists("NobodyWhoModel")}))
	main.get_tree().call_deferred("change_scene_to_file", path)
	return true
