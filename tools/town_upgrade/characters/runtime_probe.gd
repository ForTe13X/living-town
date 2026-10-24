extends SceneTree
## Run under the root engine supervisor after character staging:
## godot --headless --path game --script ../tools/town_upgrade/characters/runtime_probe.gd

var failures: Array[String] = []
var checked: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, reason: String) -> void:
	if not condition:
		failures.append(reason)


func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/town3d/characters.json"))
	var character_script: Script = load("res://scripts/TownCharacter3D.gd")
	var cases := {"Idle": {}, "Walk": {}, "Sit": {"kind": "sit_on", "seat_height_m": 0.462}, "Lie": {"kind": "lie", "bed_height_m": 0.57}, "Work": {"kind": "face"}, "Talk": {}, "Soak": {"kind": "soak", "water_height_m": 0.36}}
	for key: String in manifest.get("characters", {}):
		var character: Variant = character_script.new()
		root.add_child(character)
		var actor := {"id": key, "persona_key": key, "is_player": key == "player", "render_motion_phase": 0.25}
		if not character.setup(actor):
			failures.append(key + ": " + String(character.last_error))
			character.free()
			continue
		character.set_occlusion_visible(true)
		for clip: String in cases:
			actor["speaking"] = clip == "Talk"
			character.update_pose(actor, clip == "Walk", Vector2(0, 1), cases[clip], 0.0, 3)
			var info: Dictionary = character.get_visual_info()
			_check(info.get("clip") == clip, key + ": wrong clip " + clip)
			_check(bool(info.get("seat_kinematics_loaded", false)), key + ": missing metric seat data")
			var correctives: Array = character.get("_seat_correctives")
			var ghost_correctives: Array = character.get("_ghost_seat_correctives")
			_check(not correctives.is_empty(), key + ": missing SeatContact morph")
			_check(correctives.size() == ghost_correctives.size(), key + ": ghost morph coverage differs")
			var expected_weight := 1.0 if clip in ["Sit", "Soak"] else 0.0
			for corrective: Dictionary in correctives + ghost_correctives:
				var value := (corrective["node"] as MeshInstance3D).get_blend_shape_value(int(corrective["index"]))
				_check(absf(value - expected_weight) < 0.00001, key + ": incorrect morph weight " + clip)
			var table: Dictionary = character.get("_skin_bones")
			_check(table.size() >= 15, key + ": incomplete skin")
			for joint: String in table:
				var bone: Dictionary = table[joint]
				var skeleton: Skeleton3D = bone["skeleton"]
				var index := int(bone["index"])
				var rest: Transform3D = skeleton.get_bone_rest(index)
				var position := skeleton.get_bone_pose_position(index)
				var rotation := skeleton.get_bone_pose_rotation(index)
				_check(position.is_finite() and rotation.is_finite(), key + ": nonfinite " + clip + "/" + joint)
				_check(absf(rotation.length() - 1.0) < 0.0001, key + ": nonunit rotation")
				if joint != "PelvisRoot":
					_check(position.distance_to(rest.origin) < 0.0001, key + ": collapsed local rest offset " + clip + "/" + joint)
				if joint == "PelvisRoot" and clip == "Idle":
					_check(position.distance_to(rest.origin) < 0.0001, key + ": idle pelvis loses its rest origin")
					_check(absf(rotation.dot(rest.basis.get_rotation_quaternion())) > 0.99999, key + ": idle pelvis loses its rest basis")
			checked.append({"persona": key, "clip": clip, "skin_joints": table.size(), "meshes": info.get("meshes"), "seat_correctives": correctives.size(), "corrective_weight": expected_weight, "seat_pitch_radians": info.get("seat_pitch_radians")})
		character.free()
	var result := {"success": failures.is_empty(), "checked": checked, "failures": failures}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var file := FileAccess.open(argument.trim_prefix("--report="), FileAccess.WRITE)
			if file != null:
				file.store_string(JSON.stringify(result, "  ") + "\n")
	print("CHARACTER_RUNTIME_PROBE " + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
