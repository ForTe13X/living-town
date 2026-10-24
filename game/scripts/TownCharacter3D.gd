extends Node3D
## Adapted CC0 glTF resident with named mesh joints. Presentation only: movement,
## furniture access, needs, time and identity continue to belong to Sim.
## Character origin is between the grounded feet; model front is negative Z.

const MANIFEST_PATH := "res://data/town3d/characters.json"
const CLIPS := ["Idle", "Walk", "Sit", "Lie", "Work", "Talk", "Soak"]
const REQUIRED_JOINTS := ["PelvisRoot", "BodyPivot", "HeadPivot", "UpperArm_L", "Forearm_L", "Hand_L", "UpperArm_R", "Forearm_R", "Hand_R", "Thigh_L", "Shin_L", "Foot_L", "Thigh_R", "Shin_R", "Foot_R"]
const OPTIONAL_JOINTS := ["ApronDrape", "ApronHem"]

static var _manifest_cache: Dictionary = {}
static var _scene_cache: Dictionary = {}

var body_height_m: float = 1.7
var persona_key: String = ""
var visual_loaded: bool = false
var last_error: String = ""

var _model: Node3D
var _ghost: Node3D
var _heading: Node3D
var _joints: Dictionary = {}
var _ghost_joints: Dictionary = {}
var _rest_rotations: Dictionary = {}
var _rest_positions: Dictionary = {}
var _current_clip: String = "Idle"
var _mesh_count: int = 0
var _ghost_visible: bool = false
var _skin_bones: Dictionary = {}
var _ghost_skin_bones: Dictionary = {}
var _walk_phase: float = 0.0
var _last_world_position: Vector3 = Vector3.INF
var _seat_metrics: Dictionary = {}
var _seat_pitch: Dictionary = {}
var _seat_correctives: Array[Dictionary] = []
var _ghost_seat_correctives: Array[Dictionary] = []


func setup(ag: Dictionary) -> bool:
	if visual_loaded:
		return true
	if _manifest_cache.is_empty() and FileAccess.file_exists(MANIFEST_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if parsed is Dictionary:
			_manifest_cache = parsed
	var entries: Dictionary = _manifest_cache.get("characters", {})
	persona_key = String(ag.get("persona_key", ""))
	if bool(ag.get("is_player", false)) or String(ag.get("id", "")) == "player":
		persona_key = "player"
	elif not entries.has(persona_key):
		persona_key = String(ag.get("id", ""))
	if not entries.has(persona_key):
		var persona: Dictionary = ag.get("persona", {})
		var persona_name := String(persona.get("name", ""))
		for key: String in entries:
			if not persona_name.is_empty() and String(entries[key].get("name", "")) == persona_name:
				persona_key = key
				break
	if not entries.has(persona_key):
		last_error = "No authored character for persona: " + persona_key
		return false
	var entry: Dictionary = entries[persona_key]
	body_height_m = float(entry.get("body_height_m", 1.7))
	_seat_metrics = entry.get("seat_kinematics", {})
	var model_path := String(entry.get("model", ""))
	var packed: PackedScene = _load_scene(model_path)
	if packed == null:
		return false
	_heading = Node3D.new()
	_heading.name = "CharacterHeading"
	add_child(_heading)
	_model = packed.instantiate() as Node3D
	if _model == null:
		last_error = "Character glTF root is not Node3D: " + model_path
		_heading.queue_free()
		return false
	_heading.add_child(_model)
	_index_nodes(_model, _joints)
	if _seat_metrics.is_empty() and _joints.has("CharacterRoot"):
		_seat_metrics = (_joints["CharacterRoot"] as Node3D).get_meta("seat_kinematics", {})
	for joint_name: String in REQUIRED_JOINTS:
		if not _joints.has(joint_name):
			last_error = "Character is missing joint " + joint_name + ": " + model_path
			_heading.queue_free()
			_joints.clear()
			return false
	var complete_skin := true
	for joint_name: String in REQUIRED_JOINTS:
		complete_skin = complete_skin and _skin_bones.has(joint_name)
	if not complete_skin:
		last_error = "Character continuous skin is incomplete: " + model_path
		_heading.queue_free()
		_joints.clear()
		_skin_bones.clear()
		return false
	for joint_name: String in _joints:
		var joint: Node3D = _joints[joint_name]
		_rest_rotations[joint_name] = joint.rotation
		_rest_positions[joint_name] = joint.position
	visual_loaded = true
	return true


func _load_scene(path: String) -> PackedScene:
	if _scene_cache.has(path):
		return _scene_cache[path]
	var packed: PackedScene
	# Fresh source staging is runnable before an editor import; PCK exports use
	# ResourceLoader, which resolves the engine's imported glTF resource.
	if ResourceLoader.exists(path):
		packed = load(path) as PackedScene
	if packed == null and FileAccess.file_exists(path):
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var error := document.append_from_file(path, state)
		if error == OK:
			var source: Node = document.generate_scene(state)
			if source != null:
				packed = PackedScene.new()
				_assign_owner(source, source)
				if packed.pack(source) != OK:
					packed = null
				source.free()
	if packed == null:
		last_error = "Cannot load character: " + path
		return null
	_scene_cache[path] = packed
	return packed


func _assign_owner(node: Node, root: Node) -> void:
	for child: Node in node.get_children():
		child.owner = root
		_assign_owner(child, root)


func _index_nodes(node: Node, destination: Dictionary, ghost: bool = false) -> void:
	if node is AnimationPlayer:
		# Exported clips remain available to other engines; this adapter uses
		# explicit joint poses so replay capture can seek an exact tick.
		(node as AnimationPlayer).active = false
	if node is Node3D and (REQUIRED_JOINTS.has(String(node.name)) or OPTIONAL_JOINTS.has(String(node.name)) or String(node.name) == "CharacterRoot"):
		destination[String(node.name)] = node
	if node is MeshInstance3D and destination == _joints:
		_mesh_count += 1
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		var shape_index := instance.find_blend_shape_by_name("SeatContact")
		if shape_index >= 0:
			var correctives: Array[Dictionary] = _ghost_seat_correctives if ghost else _seat_correctives
			correctives.append({"node": instance, "index": shape_index})
	if node is Skeleton3D:
		var skeleton: Skeleton3D = node
		var table: Dictionary = _ghost_skin_bones if ghost else _skin_bones
		for joint_name: String in REQUIRED_JOINTS + OPTIONAL_JOINTS:
			var index := skeleton.find_bone("Skin_" + joint_name)
			if index >= 0:
				var parent_index := skeleton.get_bone_parent(index)
				var parent_basis := Basis.IDENTITY
				if parent_index >= 0:
					parent_basis = skeleton.get_bone_global_rest(parent_index).basis
				table[joint_name] = {"skeleton": skeleton, "index": index,
					"local_rest": skeleton.get_bone_rest(index), "parent_rest_basis": parent_basis}
	for child: Node in node.get_children():
		_index_nodes(child, destination, ghost)


func update_pose(ag: Dictionary, moving: bool, direction: Vector2, pose: Dictionary, delta: float, tick_no: int = -1) -> void:
	if not visual_loaded:
		return
	# direction is a world XZ vector, not a camera-relative screen octant.
	if direction.length_squared() > 0.000001:
		_heading.rotation.y = atan2(-direction.x, -direction.y)
	var tick := tick_no if tick_no >= 0 else int(ag.get("render_tick", 0))
	var phase := fposmod(float(tick) / 12.0, 1.0)
	if _last_world_position.is_finite() and global_position.distance_to(_last_world_position) > body_height_m * 5.0:
		_walk_phase = 0.0
	_last_world_position = global_position
	if moving:
		# A 2 Hz simulation tick is far slower than a human stride. This clock
		# affects only the visual gait; exact capture can supply an explicit phase.
		_walk_phase = fposmod(_walk_phase + maxf(0.0, delta) / 0.78, 1.0)
		phase = fposmod(float(ag.get("render_motion_phase", _walk_phase)), 1.0)
	var swing := sin(phase * TAU)
	var kind := String(pose.get("kind", ""))
	_current_clip = "Walk" if moving else "Idle"
	match kind:
		"sit_on", "sit_at":
			_current_clip = "Sit"
		"lie":
			_current_clip = "Lie"
		"soak":
			_current_clip = "Soak"
		"face":
			_current_clip = "Work"
	if kind.is_empty() and not moving and (bool(ag.get("speaking", false)) or bool(ag.get("talking", false))):
		_current_clip = "Talk"
	for joint_name: String in _joints:
		var joint: Node3D = _joints[joint_name]
		joint.rotation = _rest_rotations[joint_name]
		joint.position = _rest_positions[joint_name]
	for bone: Dictionary in _skin_bones.values():
		var skeleton: Skeleton3D = bone["skeleton"]
		# Godot 4 bone poses are absolute local transforms. Preserve each rest
		# offset/basis before applying this frame's world-axis presentation pose.
		skeleton.reset_bone_pose(int(bone["index"]))
	# Source mesh dimensions are normalized to the authored 1.665 m body.
	var scale_ratio := body_height_m / 1.665
	if kind in ["sit_on", "lie", "soak"] and pose.has("fixture_rotation_degrees"):
		_heading.rotation.y = deg_to_rad(float(pose["fixture_rotation_degrees"]))
	_seat_pitch.clear()
	match _current_clip:
		"Walk":
			for side: String in ["L", "R"]:
				var sign_value := 1.0 if side == "L" else -1.0
				var step := swing * sign_value
				_rotate("Thigh_" + side, Vector3(step * 0.47, 0, 0))
				_rotate("Shin_" + side, Vector3(-maxf(0, -step) * 0.66, 0, 0))
				_rotate("Foot_" + side, Vector3(-step * 0.47 + maxf(0, -step) * 0.66, 0, 0))
				_rotate("UpperArm_" + side, Vector3(-step * 0.33, 0, 0))
				_rotate("Forearm_" + side, Vector3(0.13 + maxf(0, step) * 0.12, 0, 0))
			_rotate("ApronDrape", Vector3(absf(swing) * 0.50, 0, 0))
			var pelvis: Node3D = _joints["PelvisRoot"]
			var shin_offset: Vector3 = _rest_positions["Shin_L"]
			var foot_offset: Vector3 = _rest_positions["Foot_L"]
			pelvis.position.y -= (shin_offset.length() + foot_offset.length()) * (1.0 - cos(swing * 0.47))
		"Sit", "Soak":
			var seat_height := float(pose.get("seat_height_m", 0.462))
			var floor_offset := float(pose.get("root_floor_offset_m", 0.025))
			var drape_pitch := 0.0
			for side: String in ["L", "R"]:
				var pitch := _seated_pitch(side, seat_height, scale_ratio, floor_offset) if _current_clip == "Sit" else PI * 0.5
				_seat_pitch[side] = pitch
				drape_pitch += pitch * 0.5
				_rotate("Thigh_" + side, Vector3(pitch, 0, 0))
				_rotate("Shin_" + side, Vector3(-pitch, 0, 0))
				_rotate("Forearm_" + side, Vector3(0.63, 0, 0))
			_rotate("ApronDrape", Vector3(drape_pitch, 0, 0))
			_rotate("ApronHem", Vector3(-drape_pitch, 0, 0))
			var pelvis: Node3D = _joints["PelvisRoot"]
			# The caller places the feet-origin at the view-only furniture anchor.
			# Seat height is metric and can be supplied by the interior adapter.
			var seat := seat_height / scale_ratio
			var contact_allowance := float(_seat_metrics.get("pelvis_contact_allowance_m", 0.0))
			pelvis.position.y = seat + 0.06 + (0.025 - floor_offset + contact_allowance) / scale_ratio
			if _current_clip == "Soak":
				pelvis.position.y = (float(pose.get("water_height_m", 0.36)) + 0.025 - floor_offset) / scale_ratio
		"Lie":
			_rotate("PelvisRoot", Vector3(PI * 0.5, 0, 0))
			var pelvis: Node3D = _joints["PelvisRoot"]
			pelvis.position.y = (float(pose.get("bed_height_m", 0.57)) + 0.08) / scale_ratio
		"Work":
			for side: String in ["L", "R"]:
				var sign_value := 1.0 if side == "L" else -1.0
				_rotate("UpperArm_" + side, Vector3(0.32 + sign_value * swing * 0.06, 0, 0))
				_rotate("Forearm_" + side, Vector3(0.75 + sign_value * swing * 0.12, 0, 0))
		"Talk":
			_rotate("UpperArm_R", Vector3(0.2 + swing * 0.10, 0, -0.12))
			_rotate("Forearm_R", Vector3(0.75 + swing * 0.12, 0, 0))
	_rotate("HeadPivot", Vector3(0.008 * swing, 0, 0.008 * cos(phase * TAU)))
	# Idle breathing is subtle geometric motion, with a stable replay phase.
	if _current_clip == "Idle":
		_rotate("BodyPivot", Vector3(0.004 * swing, 0, 0))
	if _skin_bones.has("PelvisRoot"):
		var bone: Dictionary = _skin_bones["PelvisRoot"]
		var pelvis: Node3D = _joints["PelvisRoot"]
		var difference: Vector3 = pelvis.position - (_rest_positions["PelvisRoot"] as Vector3)
		var local_rest: Transform3D = bone["local_rest"]
		(bone["skeleton"] as Skeleton3D).set_bone_pose_position(int(bone["index"]), local_rest.origin + (bone["parent_rest_basis"] as Basis).inverse() * difference)
	var seated_weight := 1.0 if _current_clip in ["Sit", "Soak"] else 0.0
	for corrective: Dictionary in _seat_correctives:
		(corrective["node"] as MeshInstance3D).set_blend_shape_value(int(corrective["index"]), seated_weight)
	if is_instance_valid(_ghost):
		for joint_name: String in _ghost_joints:
			if _joints.has(joint_name):
				(_ghost_joints[joint_name] as Node3D).transform = (_joints[joint_name] as Node3D).transform
		for joint_name: String in _ghost_skin_bones:
			if _skin_bones.has(joint_name):
				var source: Dictionary = _skin_bones[joint_name]
				var target: Dictionary = _ghost_skin_bones[joint_name]
				var source_skeleton: Skeleton3D = source["skeleton"]
				var target_skeleton: Skeleton3D = target["skeleton"]
				target_skeleton.set_bone_pose_rotation(int(target["index"]), source_skeleton.get_bone_pose_rotation(int(source["index"])))
				target_skeleton.set_bone_pose_position(int(target["index"]), source_skeleton.get_bone_pose_position(int(source["index"])))
		for corrective: Dictionary in _ghost_seat_correctives:
			(corrective["node"] as MeshInstance3D).set_blend_shape_value(int(corrective["index"]), seated_weight)


func _seated_pitch(side: String, seat: float, scale_ratio: float, root_offset: float) -> float:
	# Same analytic projection as source seating.py: source knee offsets are
	# not vertical, so a fixed90 degree turn raises the knees and floats soles.
	var legs: Dictionary = _seat_metrics.get("legs", {})
	if not legs.has(side):
		return PI * 0.5
	var leg: Dictionary = legs[side]
	var a := float(leg["knee_from_hip_y_m"])
	var b := float(leg["knee_from_hip_z_m"])
	if _seat_metrics.get("seating_policy", "adult_grounded") == "child_natural_dangling":
		return clampf(atan2(-b, a), 0.0, PI * 0.5)
	var constant_height := seat / scale_ratio + 0.06 + (0.025 - root_offset + float(_seat_metrics.get("pelvis_contact_allowance_m", 0.0))) / scale_ratio + float(leg["hip_from_pelvis_z_m"]) + float(leg["ankle_from_knee_z_m"]) + float(leg["sole_from_ankle_z_m"])
	var target := -root_offset / scale_ratio - constant_height
	var radius := sqrt(a * a + b * b)
	if radius <= 0.000001:
		return PI * 0.5
	var alpha := acos(clampf(target / radius, -1.0, 1.0))
	var phase := atan2(a, b)
	var result := -1.0
	for sign_value: float in [-1.0, 1.0]:
		for turn: int in [-1, 0, 1]:
			var angle := phase + sign_value * alpha + float(turn) * TAU
			if angle >= -0.0000001 and angle <= PI * 0.5 + 0.0000001:
				result = maxf(result, clampf(angle, 0.0, PI * 0.5))
	if result >= 0.0:
		return result
	var gap0 := absf(root_offset + scale_ratio * (constant_height + b))
	var gap90 := absf(root_offset + scale_ratio * (constant_height + a))
	return 0.0 if gap0 < gap90 else PI * 0.5


func _rotate(joint_name: String, amount: Vector3) -> void:
	var delta_rotation := _xyz_rotation(amount)
	if _joints.has(joint_name):
		(_joints[joint_name] as Node3D).quaternion = delta_rotation * Quaternion.from_euler(_rest_rotations[joint_name] as Vector3)
	if _skin_bones.has(joint_name):
		var bone: Dictionary = _skin_bones[joint_name]
		var parent_rest_rotation := (bone["parent_rest_basis"] as Basis).get_rotation_quaternion()
		var local_rest: Transform3D = bone["local_rest"]
		(bone["skeleton"] as Skeleton3D).set_bone_pose_rotation(int(bone["index"]), parent_rest_rotation.inverse() * delta_rotation * parent_rest_rotation * local_rest.basis.get_rotation_quaternion())


func _xyz_rotation(amount: Vector3) -> Quaternion:
	# Match the exported native glTF XYZ channels. Godot's from_euler uses YXZ,
	# which otherwise produces a different Talk gesture with simultaneous X/Z.
	return Quaternion(Vector3(0, 0, 1), amount.z) * Quaternion(Vector3.UP, amount.y) * Quaternion(Vector3.RIGHT, amount.x)


func set_occlusion_visible(enabled: bool) -> void:
	_ghost_visible = enabled and visual_loaded
	if enabled and visual_loaded and not is_instance_valid(_ghost):
		_ghost = _model.duplicate() as Node3D
		_ghost.name = "ControlledOcclusionSilhouette"
		_heading.add_child(_ghost)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1.0, 0.78, 0.24, 0.56)
		material.no_depth_test = true
		material.render_priority = 10
		_style_ghost(_ghost, material)
		_index_nodes(_ghost, _ghost_joints, true)
	if is_instance_valid(_ghost):
		_ghost.visible = _ghost_visible


func _style_ghost(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child: Node in node.get_children():
		_style_ghost(child, material)


func get_visual_info() -> Dictionary:
	return {"loaded": visual_loaded, "persona_key": persona_key, "body_height_m": body_height_m,
		"clip": _current_clip, "clips": CLIPS, "walk_phase": _walk_phase, "meshes": _mesh_count,
		"animation": "named_joint_continuous_skin_v2", "skin_joints": _skin_bones.size(), "origin": "ground_between_feet",
		"forward": "-Z", "normal_depth_preserved": true,
		"ghost_visible": _ghost_visible, "seat_kinematics_loaded": not _seat_metrics.is_empty(),
		"seat_pitch_radians": _seat_pitch.duplicate(), "seat_correctives": _seat_correctives.size(),
		"seat_corrective_weight": 1.0 if _current_clip in ["Sit", "Soak"] else 0.0, "last_error": last_error}
