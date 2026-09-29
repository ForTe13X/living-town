extends Node3D
## Loads the optional Blender semantic GLB in an editable Godot 3D scene.

const PACKAGE_PATH := "res://world.world.json"
const GLB_PATH := "res://assets/worldgen_proxy.glb"

func _ready() -> void:
	var file := FileAccess.open(PACKAGE_PATH, FileAccess.READ)
	if file == null:
		push_error("WORLDGEN_3D_VIEWER: missing package")
		return
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		push_error("WORLDGEN_3D_VIEWER: malformed package JSON")
		return
	var semantic: Dictionary = parser.data.get("semantic", {})
	var topology: Dictionary = semantic.get("topology", {})
	var extent: Array = semantic.get("extent_cells", topology.get("extent_cells", [32, 32]))
	var width := float(extent[0]); var depth := float(extent[1])
	var glb_scene: PackedScene = load(GLB_PATH)
	if glb_scene == null:
		push_error("WORLDGEN_3D_VIEWER: could not import " + GLB_PATH)
		return
	var proxy := glb_scene.instantiate()
	proxy.name = "WorldPackageProxy"
	proxy.set_meta("worldgen_semantic_sha256", String(parser.data.get("digests", {}).get("semantic_sha256", "")))
	add_child(proxy)
	var bounds := _geometry_bounds(proxy)
	var target := bounds.get_center() if not bounds.size.is_zero_approx() else Vector3(width * 0.5, 0.0, depth * 0.5)
	var span := maxf(1.0, maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)))
	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = span * 1.95
	camera.position = target + Vector3(span * 0.62, span * 1.10, span * 0.68)
	add_child(camera)
	camera.look_at(target, Vector3.UP)
	var light := DirectionalLight3D.new()
	light.name = "PreviewKeyLight"
	light.rotation_degrees = Vector3(-48, -28, 0)
	light.light_energy = 0.34
	light.shadow_enabled = true
	add_child(light)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("e6ebe5")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d0d7cf")
	environment.ambient_light_energy = 0.20
	var world := WorldEnvironment.new()
	world.name = "PreviewEnvironment"
	world.environment = environment
	add_child(world)
	print("WORLDGEN_3D_PROXY_READY world=%s semantic=%s nodes=%d bounds=%s" % [String(parser.data.get("world_id", "")), String(parser.data.get("digests", {}).get("semantic_sha256", "")), _count_nodes(proxy), bounds])

func _count_nodes(node: Node) -> int:
	var count := 1
	for child: Node in node.get_children(): count += _count_nodes(child)
	return count

func _geometry_bounds(root: Node) -> AABB:
	var result := AABB()
	var found := false
	for node: Node in root.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		var bounds := geometry.global_transform * geometry.get_aabb()
		if not found:
			result = bounds
			found = true
		else:
			result = result.merge(bounds)
	return result
