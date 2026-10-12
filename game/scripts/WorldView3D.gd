extends "res://scripts/WorldView.gd"
## A presentation adapter only. Canonical positions remain 48 px per Sim cell.
## The supplied projection maps those cells onto the delivered meter-scale town.
## No movement, clock, access or interaction decisions are made here.

const PROJECTION_PATH_3D := "res://data/town3d/projection.json"
const ACTOR_HEIGHT_M_3D := 1.7
const CAMERA_PITCH_3D := 56.0
const CAMERA_HEIGHT_SCALE_3D := ACTOR_HEIGHT_M_3D / 48.0

class ScreenOverlay3D extends Node2D:
	var view_3d: Node
	func _draw() -> void:
		if is_instance_valid(view_3d):
			view_3d.draw_screen_overlay_3d(self)

var projection_3d: Dictionary = {}
var viewport_3d: SubViewport
var camera_3d: Camera3D
var town_model_3d: Node3D
var scene_3d: Node3D
var _container_3d: SubViewportContainer
var _world_layer_3d: CanvasLayer
var _screen_layer_3d: CanvasLayer
var _screen_overlay_3d: Node2D
var _sun_3d: DirectionalLight3D
var _environment_3d: Environment
var _actors_3d: Dictionary = {}
var _sheet_metrics_3d: Dictionary = {}
var _asset_bounds_3d: Dictionary = {}
var _occlusion_ghost_3d: Sprite3D
var _ghost_textures_3d: Dictionary = {}
var _occlusion_clock_3d := 0.0
var _occlusion_subject_3d := ""
var _occlusion_info_3d: Dictionary = {"blocked": false, "ray_count": 0}
var _plane_key_3d := ""
var _overlay_time_3d := 0.0
var _load_error_3d := ""

func _ready() -> void:
	# Deliberately skip the base ready: its old 2D void/light children draw separately.
	process_priority = 50 # LifeMode first updates canonical camera and prompt state.
	load_projection_3d()
	_world_layer_3d = CanvasLayer.new()
	_world_layer_3d.layer = -10
	add_child(_world_layer_3d)
	_container_3d = SubViewportContainer.new()
	_container_3d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container_3d.stretch = true
	_world_layer_3d.add_child(_container_3d)
	viewport_3d = SubViewport.new()
	viewport_3d.own_world_3d = true
	viewport_3d.transparent_bg = false
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_3d.msaa_3d = Viewport.MSAA_2X
	_container_3d.add_child(viewport_3d)
	scene_3d = Node3D.new()
	viewport_3d.add_child(scene_3d)
	_build_environment_3d()
	camera_3d = Camera3D.new()
	camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera_3d.near = 0.05
	camera_3d.far = 600.0
	camera_3d.current = true
	scene_3d.add_child(camera_3d)
	var model_script: Script = load("res://scripts/TownModel3D.gd")
	if model_script != null:
		town_model_3d = model_script.new()
		scene_3d.add_child(town_model_3d)
		if not town_model_3d.call("load_town"):
			_load_error_3d = "3D town could not be loaded."
	else:
		_load_error_3d = "TownModel3D.gd is unavailable."
	_screen_layer_3d = CanvasLayer.new()
	_screen_layer_3d.layer = 9
	add_child(_screen_layer_3d)
	var overlay := ScreenOverlay3D.new()
	overlay.view_3d = self
	_screen_overlay_3d = overlay
	_screen_layer_3d.add_child(overlay)
	Sim.social_event.connect(_on_social)
	Sim.world_reset.connect(_reset_3d)
	get_viewport().size_changed.connect(_resize_3d)
	_resize_3d()

func _draw() -> void:
	pass # The inherited immediate-mode 2D world is intentionally not rendered.

func _redraw_all() -> void:
	if is_instance_valid(_screen_overlay_3d):
		_screen_overlay_3d.queue_redraw()

func load_projection_3d() -> bool:
	var f := FileAccess.open(PROJECTION_PATH_3D, FileAccess.READ)
	if f == null:
		_load_error_3d = "Missing 3D projection profile."
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not data is Dictionary:
		_load_error_3d = "Invalid 3D projection profile."
		return false
	projection_3d = data
	return true

func _build_environment_3d() -> void:
	var we := WorldEnvironment.new()
	_environment_3d = Environment.new()
	_environment_3d.background_mode = Environment.BG_COLOR
	_environment_3d.background_color = Color("bed2d6")
	_environment_3d.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment_3d.ambient_light_color = Color("d8e3e8")
	_environment_3d.ambient_light_energy = 0.24
	_environment_3d.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = _environment_3d
	scene_3d.add_child(we)
	_sun_3d = DirectionalLight3D.new()
	_sun_3d.rotation_degrees = Vector3(-52, -28, 0)
	_sun_3d.light_color = Color("fff1d8")
	_sun_3d.light_energy = 0.72
	_sun_3d.shadow_enabled = true
	scene_3d.add_child(_sun_3d)

func _resize_3d() -> void:
	if not is_instance_valid(viewport_3d):
		return
	var sz := get_viewport().get_visible_rect().size
	_container_3d.position = Vector2.ZERO
	_container_3d.size = sz

func _probe_3d() -> Node:
	return get_parent().get("_probe") if get_parent() != null else null

func active_plane_3d() -> Dictionary:
	var pb := _probe_3d()
	return plane_3d(String(pb.active_space), String(pb.active_floor)) if pb != null else plane_3d("town", "outdoor")

func plane_3d(space_id: String, floor_id: String) -> Dictionary:
	var planes: Dictionary = projection_3d.get("planes", {})
	var key := space_id + "/" + floor_id
	return planes.get(key, {})

func _v2_3d(value: Variant, fallback := Vector2.ZERO) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback

func canonical_to_world(px: Vector2, space_id := "", floor_id := "") -> Vector3:
	var p := active_plane_3d() if space_id == "" else plane_3d(space_id, floor_id)
	if p.is_empty():
		return Vector3.ZERO
	var s := float(p.get("cell_size_m", 0.5))
	var c := px / 48.0
	var xy := Vector2.ZERO
	var z := float(p.get("finished_floor_z_m", 0.0))
	if p.has("origin_world_m"):
		var origin := _v2_3d(p["origin_world_m"])
		xy = origin + Vector2(c.x * s, -c.y * s)
		z = terrain_height_3d(c, p)
	else:
		var local := _v2_3d(p.get("origin_local_m", [])) + Vector2(c.x * s, -c.y * s)
		local = local.rotated(deg_to_rad(float(p.get("yaw_degrees", 0.0))))
		xy = _v2_3d(p.get("center_world_m", [])) + local
	return Vector3(xy.x, z, -xy.y)

func world_to_canonical(world_pos: Vector3, space_id := "", floor_id := "") -> Vector2:
	var p := active_plane_3d() if space_id == "" else plane_3d(space_id, floor_id)
	if p.is_empty():
		return Vector2.ZERO
	var s := maxf(0.001, float(p.get("cell_size_m", 0.5)))
	var xy := Vector2(world_pos.x, -world_pos.z)
	var local := Vector2.ZERO
	if p.has("origin_world_m"):
		local = xy - _v2_3d(p["origin_world_m"])
	else:
		local = (xy - _v2_3d(p.get("center_world_m", []))).rotated(-deg_to_rad(float(p.get("yaw_degrees", 0.0))))
		local -= _v2_3d(p.get("origin_local_m", []))
	return Vector2(local.x, -local.y) / s * 48.0

func terrain_height_3d(cell: Vector2, p: Dictionary = {}) -> float:
	if p.is_empty():
		p = plane_3d("town", "outdoor")
	var size := _v2_3d(p.get("grid_size", []), Vector2.ONE)
	var w := maxi(1, int(size.x))
	var h := maxi(1, int(size.y))
	var heights: Array = p.get("terrain_heights_m", [])
	if heights.size() < w * h:
		return float(p.get("finished_floor_z_m", 0.0))
	# Height samples are cell centers. Interpolate between them; never extrapolate.
	var q := (cell - Vector2(0.5, 0.5)).clamp(Vector2.ZERO, Vector2(w - 1, h - 1))
	var x := int(floor(q.x))
	var y := int(floor(q.y))
	var nx := mini(x + 1, w - 1)
	var ny := mini(y + 1, h - 1)
	var a := lerpf(float(heights[y * w + x]), float(heights[y * w + nx]), q.x - x)
	var b := lerpf(float(heights[ny * w + x]), float(heights[ny * w + nx]), q.x - x)
	return lerpf(a, b, q.y - y)

func sync_camera() -> void:
	var pb := _probe_3d()
	if pb == null or pb.cam == null or camera_3d == null:
		return
	var p := active_plane_3d()
	if p.is_empty():
		return
	var key := String(pb.active_space) + "/" + String(pb.active_floor)
	if key != _plane_key_3d:
		_plane_key_3d = key
		if town_model_3d != null:
			if String(pb.active_space) == "town":
				town_model_3d.call("restore_exterior")
			else:
				town_model_3d.call("reveal", String(pb.active_space), String(pb.active_floor), projection_3d)
	var center: Vector3 = canonical_to_world(pb.cam.position)
	var south: Vector3 = canonical_to_world(pb.cam.position + Vector2(0, 48)) - center
	south.y = 0.0
	if south.length_squared() < 0.0001:
		south = Vector3(0, 0, 1)
	south = south.normalized()
	var pitch := deg_to_rad(CAMERA_PITCH_3D)
	camera_3d.position = center + south * (cos(pitch) * 100.0) + Vector3.UP * (sin(pitch) * 100.0)
	camera_3d.look_at(center, Vector3.UP)
	camera_3d.size = float(viewport_3d.size.y) * CAMERA_HEIGHT_SCALE_3D / maxf(0.025, pb.cam.zoom.x)

func fit_zoom_3d(bounds: Rect2, vp: Vector2, pad: Vector2) -> float:
	var p := active_plane_3d()
	if p.is_empty():
		return 0.5
	var meters := bounds.size / 48.0 * float(p.get("cell_size_m", 0.5))
	var avail := Vector2(maxf(64, vp.x - pad.x), maxf(64, vp.y - pad.y))
	var required := maxf(meters.x * vp.y / avail.x, meters.y * sin(deg_to_rad(CAMERA_PITCH_3D)) * vp.y / avail.y)
	return float(vp.y) * CAMERA_HEIGHT_SCALE_3D / maxf(1.0, required + 2.2)

func screen_to_canonical(screen: Vector2, space_id := "", floor_id := "") -> Vector2:
	sync_camera() # Zoom-to-cursor must see the new dummy-camera zoom immediately.
	if camera_3d == null:
		return Vector2.ZERO
	var p := active_plane_3d() if space_id == "" else plane_3d(space_id, floor_id)
	var origin := camera_3d.project_ray_origin(screen)
	var direction := camera_3d.project_ray_normal(screen)
	if absf(direction.y) < 0.00001:
		return Vector2.ZERO
	var height := float(p.get("finished_floor_z_m", 0.0))
	var t := (height - origin.y) / direction.y
	var point := origin + direction * t
	if p.has("origin_world_m"):
		# Fixed-point terrain intersection is stable for the authored shallow site.
		for i in 12:
			var cell := world_to_canonical(point, space_id, floor_id) / 48.0
			var next_height := terrain_height_3d(cell, p)
			var next_t := (next_height - origin.y) / direction.y
			if absf(next_t - t) < 0.00005:
				break
			t = next_t
			point = origin + direction * t
	return world_to_canonical(point, space_id, floor_id)

func pick_to_canonical(screen: Vector2, space_id := "", floor_id := "") -> Vector2:
	# The sprite's head is above its navigation cell. A body tap selects that cell;
	# zoom and pan deliberately use the raw floor ray instead of this hit test.
	sync_camera()
	var pb := _probe_3d()
	var best := INF
	var picked := Vector2.ZERO
	for ag in Sim.agents:
		var id := String(ag["id"])
		if pb == null or String(ag.get("space", "town")) != String(pb.active_space) or String(ag.get("floor", "outdoor")) != String(pb.active_floor):
			continue
		var feet := canonical_to_screen(_rpos(ag), "", "", 0.03)
		var head := canonical_to_screen(_rpos(ag), "", "", ACTOR_HEIGHT_M_3D)
		var body_h := maxf(12, feet.y - head.y)
		var box := Rect2(Vector2(feet.x - maxf(9, body_h * 0.27), head.y), Vector2(maxf(18, body_h * 0.54), body_h + 5))
		if box.has_point(screen):
			var distance := screen.distance_to((feet + head) * 0.5)
			if distance < best:
				best = distance
				picked = _center(ag)
	if best < INF:
		return picked
	# Mesh AABBs are view-only proxies; the returned point is the original
	# reachable interaction cell. Mesh collision never decides legal movement.
	var bindings: Dictionary = projection_3d.get("interaction_bindings", {})
	var active_key := String(pb.active_space) + "/" + String(pb.active_floor) if pb != null else ""
	for object_id in bindings:
		var binding: Dictionary = bindings[object_id]
		if String(binding.get("plane", "")) != active_key:
			continue
		if not Sim.world.get("objects", {}).has(object_id):
			var valid_ui_marker := false
			for entry: Dictionary in Sim.life_interactions(999):
				if String(entry.get("id", "")) == String(object_id) and String(entry.get("kind", "")) in ["bank", "civic"]:
					valid_ui_marker = true
					break
			if not valid_ui_marker:
				continue
		var asset_id := _binding_asset_id_3d(binding)
		if asset_id.is_empty():
			continue # Outdoor activity anchors intentionally have no mesh proxy.
		var box := _asset_screen_rect_3d(asset_id)
		if box.size == Vector2.ZERO or not box.grow(4).has_point(screen):
			continue
		var canonical := _v2_3d(binding.get("cell", [])) * 48 + Vector2(24,24)
		var distance := screen.distance_to(canonical_to_screen(canonical, "", "", 0.5))
		if distance < best:
			best = distance
			picked = canonical
	if best < INF:
		return picked
	return screen_to_canonical(screen, space_id, floor_id)

func _binding_asset_id_3d(binding: Dictionary) -> String:
	# JSON null denotes an authored activity anchor without a dedicated mesh.
	# String(null) throws; preserve the canonical anchor and terrain-ray fallback.
	var asset_id: Variant = binding.get("model_asset_id", "")
	return asset_id if asset_id is String else ""

func _asset_world_bounds_3d(asset_id: String) -> AABB:
	if asset_id.is_empty():
		return AABB()
	if asset_id == "" or town_model_3d == null:
		return AABB()
	if _asset_bounds_3d.has(asset_id):
		return _asset_bounds_3d[asset_id]
	var pending: Array = town_model_3d.call("get_asset_nodes", asset_id)
	var bounds := AABB()
	var found := false
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D and node.mesh != null:
			var box: AABB = node.global_transform * node.get_aabb()
			bounds = bounds.merge(box) if found else box
			found = true
		pending.append_array(node.get_children())
	_asset_bounds_3d[asset_id] = bounds
	return bounds

func _asset_screen_rect_3d(asset_id: String) -> Rect2:
	var bounds := _asset_world_bounds_3d(asset_id)
	if bounds.size == Vector3.ZERO:
		return Rect2()
	var rect := Rect2(camera_3d.unproject_position(bounds.position), Vector2.ZERO)
	for i in 8:
		rect = rect.expand(camera_3d.unproject_position(bounds.get_endpoint(i)))
	return rect

func object_screen_position(object_id: String) -> Vector2:
	var binding: Dictionary = projection_3d.get("interaction_bindings", {}).get(object_id, {})
	var bounds := _asset_world_bounds_3d(_binding_asset_id_3d(binding))
	if bounds.size != Vector3.ZERO:
		return camera_3d.unproject_position(bounds.get_center())
	var object: Dictionary = Sim.world.get("objects", {}).get(object_id, {})
	if object.is_empty():
		return Vector2(-10000,-10000)
	return canonical_to_screen(Vector2(object["pos"]) * 48 + Vector2(24,24), String(object.get("space", "town")), String(object.get("floor", "outdoor")), 0.6)

func _interaction_anchor_3d(entry: Dictionary) -> Vector2:
	if String(entry.get("kind", "")) == "object":
		return object_screen_position(String(entry.get("id", "")))
	var cell: Vector2i = entry["pos"]
	return canonical_to_screen(Vector2(cell) * 48 + Vector2(24,24), "", "", 1.95 if String(entry.get("kind", "")) == "agent" else 0.7)

func canonical_to_screen(px: Vector2, space_id := "", floor_id := "", height_m := 0.0) -> Vector2:
	if camera_3d == null:
		return Vector2(-10000, -10000)
	var world := canonical_to_world(px, space_id, floor_id) + Vector3.UP * height_m
	if camera_3d.is_position_behind(world):
		return Vector2(-10000, -10000)
	return camera_3d.unproject_position(world)

func _char8_key(ag: Dictionary) -> String:
	var key := String(ag.get("persona_key", ""))
	if key != "" and Art.char_sheet(key) != null:
		return key
	return super._char8_key(ag)

func _make_actor_3d(ag: Dictionary) -> Dictionary:
	var key := _char8_key(ag)
	var sheet: Texture2D = Art.char_sheet(key) if key != "" else _fallback_tex(ag)
	var frame_px := 48
	var cols := 7
	var rows := 8
	if key == "":
		frame_px = 32
		cols = maxi(1, int(sheet.get_width() / 32)) if sheet != null else 1
		rows = maxi(1, int(sheet.get_height() / 32)) if sheet != null else 1
	var metric_key := key if key != "" else String(ag["id"])
	var metrics: Dictionary = _sheet_metrics_3d.get(metric_key, {})
	if metrics.is_empty():
		var used := Rect2i(0, 0, frame_px, frame_px)
		if sheet != null:
			var image := sheet.get_image()
			if image != null:
				used = image.get_region(Rect2i(0, 0, frame_px, frame_px)).get_used_rect()
		metrics = {"feet": used.end.y, "height": maxi(1, used.size.y)}
		_sheet_metrics_3d[metric_key] = metrics
	var sprite := Sprite3D.new()
	sprite.name = "Actor_" + String(ag["id"])
	sprite.texture = sheet
	sprite.hframes = cols
	sprite.vframes = rows
	sprite.pixel_size = ACTOR_HEIGHT_M_3D / float(metrics["height"])
	sprite.offset = Vector2(0, float(metrics["feet"]) - frame_px * 0.5)
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.25
	sprite.shaded = false
	sprite.double_sided = true
	scene_3d.add_child(sprite)
	return {"node": sprite, "key": key, "cols": cols, "rows": rows}

func _screen_row_3d(ag: Dictionary) -> int:
	var id := String(ag["id"])
	var canonical_row := int(_dir8.get(id, 0))
	var step := Vector2(0, 1)
	for direction in DIR8_ROW:
		if int(DIR8_ROW[direction]) == canonical_row:
			step = Vector2(direction)
			break
	var px := _rpos(ag)
	var space_id := String(ag.get("space", "town"))
	var floor_id := String(ag.get("floor", "outdoor"))
	var d := canonical_to_world(px + step * 48, space_id, floor_id) - canonical_to_world(px, space_id, floor_id)
	d.y = 0
	var screen := Vector2(d.dot(camera_3d.global_transform.basis.x), -d.dot(camera_3d.global_transform.basis.y))
	var octant := posmod(int(round(atan2(screen.y, screen.x) / (PI / 4.0))), 8)
	return [2, 1, 0, 7, 6, 5, 4, 3][octant]

func _update_actor_3d(ag: Dictionary) -> void:
	var id := String(ag["id"])
	if not _actors_3d.has(id):
		_actors_3d[id] = _make_actor_3d(ag)
	var item: Dictionary = _actors_3d[id]
	var sprite: Sprite3D = item["node"]
	var pb := _probe_3d()
	var space_id := String(ag.get("space", "town"))
	var floor_id := String(ag.get("floor", "outdoor"))
	sprite.visible = pb != null and space_id == String(pb.active_space) and floor_id == String(pb.active_floor)
	if not sprite.visible:
		return
	sprite.position = canonical_to_world(_rpos(ag), space_id, floor_id) + Vector3.UP * 0.025
	var moving := bool(_moving.get(id, false))
	var col := 1 + posmod(Sim.tick_no, maxi(1, int(item["cols"]) - 1)) if moving else 0
	var row := _screen_row_3d(ag) if String(item["key"]) != "" else mini(1, int(item["rows"]) - 1)
	sprite.frame_coords = Vector2i(col, row)

func _ghost_texture_3d(source: Texture2D) -> Texture2D:
	if source == null:
		return null
	var key := source.get_instance_id()
	if _ghost_textures_3d.has(key):
		return _ghost_textures_3d[key]
	var image := source.get_image()
	if image == null:
		return source
	if image.is_compressed():
		image.decompress()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	var bytes := image.get_data()
	# Keep the original atlas alpha/poses; uniform RGB makes a legible silhouette.
	for i in range(0, bytes.size(), 4):
		bytes[i] = 255
		bytes[i + 1] = 255
		bytes[i + 2] = 255
	var white := Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, bytes)
	var texture := ImageTexture.create_from_image(white)
	_ghost_textures_3d[key] = texture
	return texture

func _update_controlled_occlusion_3d(delta: float) -> void:
	# Only the controlled resident receives a ghost; ordinary actors retain depth.
	var id := String(Sim.controlled_id)
	if id == "" and bool(Sim.get_agent("player").get("is_player", false)):
		id = "player"
	var item: Dictionary = _actors_3d.get(id, {})
	if item.is_empty() or not bool(item["node"].visible):
		if _occlusion_ghost_3d != null:
			_occlusion_ghost_3d.visible = false
		_occlusion_subject_3d = ""
		_occlusion_info_3d["blocked"] = false
		return
	var primary: Sprite3D = item["node"]
	if _occlusion_ghost_3d == null:
		_occlusion_ghost_3d = Sprite3D.new()
		_occlusion_ghost_3d.name = "ControlledOcclusionSilhouette"
		_occlusion_ghost_3d.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		_occlusion_ghost_3d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_occlusion_ghost_3d.shaded = false
		_occlusion_ghost_3d.no_depth_test = true
		_occlusion_ghost_3d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_occlusion_ghost_3d.modulate = Color(1.0, 0.78, 0.24, 0.72)
		_occlusion_ghost_3d.visible = false
		scene_3d.add_child(_occlusion_ghost_3d)
	_occlusion_ghost_3d.texture = _ghost_texture_3d(primary.texture)
	_occlusion_ghost_3d.hframes = primary.hframes
	_occlusion_ghost_3d.vframes = primary.vframes
	_occlusion_ghost_3d.pixel_size = primary.pixel_size
	_occlusion_ghost_3d.offset = primary.offset
	_occlusion_ghost_3d.frame_coords = primary.frame_coords
	_occlusion_ghost_3d.global_transform = primary.global_transform
	var subject := id + "/" + _plane_key_3d
	if subject != _occlusion_subject_3d:
		_occlusion_subject_3d = subject
		_occlusion_clock_3d = 0.0
	_occlusion_clock_3d -= delta
	if _occlusion_clock_3d <= 0.0 and town_model_3d != null:
		_occlusion_clock_3d = 0.2
		var body := primary.global_position + Vector3.UP * 0.95
		var screen := camera_3d.unproject_position(body)
		# Orthographic rays originate at the projected pixel, not camera's center.
		var origin := camera_3d.project_ray_origin(screen)
		var direction := (body - origin).normalized()
		var distance := origin.distance_to(body)
		var hit: Dictionary = town_model_3d.call("raycast_geometry", origin, direction, maxf(0.0, distance - 0.12), "all")
		var blocked := not hit.is_empty()
		if blocked:
			var point: Vector3 = hit["position"]
			# Ignore a contact-level numerical hit; roof/tree/wall blockers are above it.
			blocked = point.y > primary.global_position.y + 0.10
		_occlusion_info_3d = {"blocked": blocked, "actor_id": id,
			"ray_count": int(_occlusion_info_3d.get("ray_count", 0)) + 1,
			"occluder": String(hit["node"].name) if blocked else "",
			"max_query_hz": 5, "normal_depth_preserved": not primary.no_depth_test}
		_occlusion_ghost_3d.visible = blocked

func _reset_3d() -> void:
	_render_pos.clear()
	_prev_pos.clear()
	_plane_of.clear()
	_moving.clear()
	_emote.clear()
	_say.clear()
	for item in _actors_3d.values():
		var node: Node = item["node"]
		node.queue_free()
	_actors_3d.clear()
	_plane_key_3d = ""
	_occlusion_subject_3d = ""
	_occlusion_clock_3d = 0.0
	_occlusion_info_3d = {"blocked": false, "ray_count": 0}
	if _occlusion_ghost_3d != null:
		_occlusion_ghost_3d.visible = false

func _process(delta: float) -> void:
	if not is_instance_valid(camera_3d) or Sim.world.is_empty():
		return
	_overlay_time_3d += delta
	var step := clampf(Sim.tick_interval / maxf(Sim.speed, 0.25), 0.008, maxf(0.16, Sim.tick_interval / maxf(Sim.speed, 0.25)))
	var k := clampf(delta / maxf(step * LERP_FRACTION, 0.001), 0, 1)
	var k_ctl := clampf(delta / (CTL_STEP * LERP_FRACTION), 0, 1)
	var alive := {}
	for ag in Sim.agents:
		var id := String(ag["id"])
		alive[id] = true
		var target := _center(ag)
		var gp: Vector2i = ag["pos"]
		var prev: Vector2i = _prev_pos.get(id, gp)
		var plane := String(ag.get("space", "town")) + "/" + String(ag.get("floor", "outdoor"))
		var changed_plane := plane != String(_plane_of.get(id, plane))
		if changed_plane:
			prev = gp
		_plane_of[id] = plane
		if gp != prev:
			var d := gp - prev
			if maxi(absi(d.x), absi(d.y)) <= 2:
				_face_step(id, Vector2i(signi(d.x), signi(d.y)), ag)
		_prev_pos[id] = gp
		var cur: Vector2 = _render_pos.get(id, target)
		if changed_plane or cur.distance_to(target) > TELEPORT_TILES * T:
			cur = target
		else:
			cur = cur.lerp(target, k_ctl if id == Sim.controlled_id else k)
		_moving[id] = cur.distance_to(target) > SNAP_PX
		_render_pos[id] = cur if bool(_moving[id]) else target
	sync_camera()
	for ag in Sim.agents:
		_update_actor_3d(ag)
	_update_controlled_occlusion_3d(delta)
	for id in _actors_3d.keys():
		if not alive.has(id):
			_actors_3d[id]["node"].queue_free()
			_actors_3d.erase(id)
			_render_pos.erase(id)
	var daylight := clampf(sin((Sim.time_of_day() - 0.23) * TAU) * 0.5 + 0.5, 0.0, 1.0)
	_sun_3d.light_energy = lerpf(0.08, 0.72, daylight)
	_environment_3d.ambient_light_energy = lerpf(0.10, 0.24, daylight)
	_refresh_social_markers_3d()
	_sync_life_prompt_3d()
	_screen_overlay_3d.queue_redraw()

func _refresh_social_markers_3d() -> void:
	# The base renderer built these caches in its skipped _draw_body.
	_rc_conflict_ids.clear()
	for conflict in Sim.conflicts:
		if String(conflict.get("status", "")) in ["simmering", "escalated", "confronted", "lingering"]:
			_rc_conflict_ids[conflict["a"]] = true
			_rc_conflict_ids[conflict["b"]] = true
	_rc_meet_ids.clear()
	for commitment in Sim.commitments:
		if String(commitment.get("status", "")) == "active":
			_rc_meet_ids[commitment["a"]] = true
			_rc_meet_ids[commitment["b"]] = true
	_rc_social_ids.clear()
	for ag in Sim.agents:
		var option: Variant = ag.get("option")
		if option is Dictionary and String(option.get("kind", "")) == "social":
			_rc_social_ids[String(ag["id"])] = true
			var partner := String(option.get("partner", ""))
			if partner != "":
				_rc_social_ids[partner] = true

func _sync_life_prompt_3d() -> void:
	var life: Node = get_parent().get("_life")
	if life == null:
		return
	var old_marker: Node2D = life.get("_marker")
	if old_marker != null:
		old_marker.visible = false
	if not bool(life.get("active")):
		return
	var prompt: Label = life.get("_prompt")
	if prompt == null or not prompt.visible:
		return
	var e: Dictionary = life.call("_focused")
	if e.is_empty():
		return
	var p: Vector2i = e["pos"]
	var anchor := _interaction_anchor_3d(e)
	var size := get_viewport().get_visible_rect().size
	prompt.position = Vector2(clampf(anchor.x - prompt.size.x * 0.5, 4, maxf(4, size.x - prompt.size.x - 4)), clampf(anchor.y - 36, 44, maxf(44, size.y - 80)))

func _plate_3d(n: Node2D, center: Vector2, text: String, color := Color.WHITE, fs := 14) -> void:
	var font := Art.font()
	var width := minf(300, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	n.draw_rect(Rect2(center + Vector2(-width * 0.5 - 5, -fs - 3), Vector2(width + 10, fs + 8)), Color(0.08, 0.10, 0.12, 0.83))
	n.draw_string(font, center + Vector2(-width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, width, fs, color)

func _ground_ring_3d(n: Node2D, px: Vector2, radius_m: float, color: Color) -> void:
	var p := active_plane_3d()
	var radius_px := radius_m / maxf(0.001, float(p.get("cell_size_m", 0.5))) * 48
	var points := PackedVector2Array()
	for i in 33:
		var angle := float(i) / 32 * TAU
		points.append(canonical_to_screen(px + Vector2(cos(angle), sin(angle)) * radius_px, "", "", 0.035))
	n.draw_polyline(points, color, 2.0, true)

func _fixture_outline_3d(n: Node2D, entry: Dictionary) -> bool:
	if String(entry.get("kind", "")) not in ["object", "bank", "civic"]:
		return false
	var binding: Dictionary = projection_3d.get("interaction_bindings", {}).get(String(entry.get("id", "")), {})
	var bounds := _asset_world_bounds_3d(_binding_asset_id_3d(binding))
	if bounds.size == Vector3.ZERO:
		return false
	var points := PackedVector2Array()
	for uv in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1),Vector2(0,0)]:
		var world := bounds.position + Vector3(uv.x * bounds.size.x, 0.025, uv.y * bounds.size.z)
		points.append(camera_3d.unproject_position(world))
	n.draw_polyline(points, Color(0.95,0.80,0.40,0.8), 2.0, true)
	return true

func draw_screen_overlay_3d(n: Node2D) -> void:
	if _load_error_3d != "":
		_plate_3d(n, Vector2(300, 150), _load_error_3d, Color("ffd08c"), 18)
	var pb := _probe_3d()
	if pb == null or camera_3d == null:
		return
	var life: Node = get_parent().get("_life")
	var life_active := life != null and bool(life.get("active"))
	var life_pid := String(life.get("pid")) if life_active else ""
	var selected := _selected_id()
	for ag in Sim.agents:
		var id := String(ag["id"])
		if not _actors_3d.has(id) or not _actors_3d[id]["node"].visible:
			continue
		var px := _rpos(ag)
		var anchor := canonical_to_screen(px, "", "", ACTOR_HEIGHT_M_3D + 0.20)
		var saying: bool = _say.has(id) and Sim.tick_no < int(_say[id]["until"])
		var focus := id == selected or id == life_pid or saying or _in_conflict(id) or _has_meet(id) or _rc_social_ids.has(id)
		if id == selected or id == life_pid:
			_ground_ring_3d(n, px, 0.4, Color("e6c66f"))
		if pb.cam.zoom.x >= 0.55 or focus:
			var name_text := String((ag.get("persona", {}) as Dictionary).get("name", id))
			if _in_conflict(id):
				name_text += " !"
			if _has_meet(id):
				name_text += " 约"
			_plate_3d(n, anchor, name_text, Color("fff7df"))
			var em: Dictionary = _emote.get(id, {})
			if not em.is_empty() and Sim.tick_no < int(em["until"]):
				var tex: Texture2D = em["tex"]
				n.draw_texture_rect(tex, Rect2(anchor + Vector2(-16, -61), Vector2(32, 32)), false)
			if saying:
				_plate_3d(n, anchor + Vector2(0, -44), String(_say[id]["text"]), Color("ffe5a7"), 14)
			elif focus and ag.get("option") != null:
				_plate_3d(n, canonical_to_screen(px, "", "", 0.05) + Vector2(0, 23), _action_label(ag["option"]), Color("cbd9d9"), 12)
		if life_active and id == life_pid:
			var low := _worst_need(ag)
			var col := Color("6be577") if low >= 45 else (Color("fac94e") if low >= 22 else Color("fa6150"))
			var c := anchor + Vector2(0, -47 + sin(_overlay_time_3d * 3) * 2.5)
			var diamond := PackedVector2Array([c + Vector2(0,-10),c + Vector2(6,0),c + Vector2(0,10),c + Vector2(-6,0)])
			n.draw_colored_polygon(diamond, col)
	if life_active:
		var entry: Dictionary = life.call("_focused")
		if not entry.is_empty() and not bool(life.get("_modal_open")):
			var cell: Vector2i = entry["pos"]
			if not _fixture_outline_3d(n, entry):
				_ground_ring_3d(n, Vector2(cell) * 48 + Vector2(24,24), 0.32, Color(0.95,0.80,0.40,0.8))
		if bool(life.get("_walk_on")) and String((life.get("_walk_goal") as Dictionary).get("kind", "none")) == "none":
			var dest: Vector2i = life.get("_walk_dest")
			_ground_ring_3d(n, Vector2(dest) * 48 + Vector2(24,24), 0.22 + sin(_overlay_time_3d * 6) * 0.03, Color("e6c66f"))

func get_bridge_info() -> Dictionary:
	return {"projection_loaded": not projection_3d.is_empty(), "active_plane": _plane_key_3d,
		"actor_count": _actors_3d.size(), "error": _load_error_3d,
		"controlled_occlusion": _occlusion_info_3d.duplicate(),
		"model": town_model_3d.call("get_info") if town_model_3d != null else {}}
