extends "res://scripts/ProbeController.gd"
## Canonical Camera2D state remains compatible with Main and LifeMode.
## It is disabled: WorldView3D projects this state through its real Camera3D.

func setup(parent: Node, bounds: Rect2) -> void:
	_bounds = bounds
	_home = bounds
	cam = Camera2D.new()
	cam.name = "CanonicalCameraState3D"
	cam.enabled = false
	cam.position = bounds.get_center()
	parent.add_child(cam)
	_apply_limits()

func _view_3d() -> Node:
	return get_parent().get("_view") if get_parent() != null else null

func screen_to_world(sp: Vector2, _vp: Vector2) -> Vector2:
	var view := _view_3d()
	if view != null and view.has_method("pick_to_canonical"):
		return view.call("pick_to_canonical", sp, active_space, active_floor)
	# No 2D linear substitute: returning focus is an explicit unloaded-view fallback.
	return cam.position if cam != null else Vector2.ZERO

func _floor_ray_3d(sp: Vector2) -> Vector2:
	var view := _view_3d()
	return view.call("screen_to_canonical", sp, active_space, active_floor) if view != null else cam.position

func fit_zoom(vp := Vector2.ZERO, pad := HOME_PAD) -> float:
	var size := vp if vp.x > 1 and vp.y > 1 else _vp_size()
	var view := _view_3d()
	if view != null and view.has_method("fit_zoom_3d"):
		return float(view.call("fit_zoom_3d", _bounds, size, pad))
	return 0.5

func min_zoom(vp := Vector2.ZERO) -> Vector2:
	return Vector2.ONE * clampf(fit_zoom(vp) * FIT_SLACK, 0.025, 0.9)

func go_home() -> void:
	push_history()
	mode = Mode.FREE
	follow_id = ""
	focus_id = ""
	active_space = "town"
	active_floor = "outdoor"
	_bounds = _home
	_apply_limits()
	cam.position = _home.get_center()
	cam.zoom = Vector2.ONE * clampf(fit_zoom(), 0.025, 3.2)

func zoom_at(factor: float, screen_pos: Vector2, vp: Vector2) -> void:
	if vp.x > 1 and vp.y > 1:
		_last_vp = vp
	var before := _floor_ray_3d(screen_pos)
	cam.zoom = (cam.zoom * factor).clamp(min_zoom(vp), Vector2(3.2,3.2))
	var after := _floor_ray_3d(screen_pos)
	cam.position += before - after
	var view := _view_3d()
	if view != null:
		view.call("sync_camera")

func _pan_3d(from_screen: Vector2, to_screen: Vector2, vp: Vector2) -> void:
	var before := _floor_ray_3d(from_screen)
	var after := _floor_ray_3d(to_screen)
	cam.position += before - after

func handle_input(e: InputEvent, vp: Vector2) -> bool:
	if vp.x > 1 and vp.y > 1:
		_last_vp = vp
	if e is InputEventMouseButton:
		demo_cam = false
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			zoom_at(1.12, e.position, vp)
			return true
		if e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			zoom_at(1.0 / 1.12, e.position, vp)
			return true
		if e.button_index == MOUSE_BUTTON_MIDDLE or e.button_index == MOUSE_BUTTON_RIGHT:
			_panning = e.pressed
			_pan_last = e.position
			if _panning:
				unfollow()
			return true
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press_pos = e.position
				_pan_last = e.position
				_maybe_tap = true
			else:
				var was_tap: bool = _maybe_tap and e.position.distance_to(_press_pos) <= DRAG_THRESH
				_maybe_tap = false
				_panning = false
				if was_tap:
					if e.double_click:
						double_tapped.emit(screen_to_world(e.position, vp))
					else:
						tapped.emit(screen_to_world(e.position, vp))
			return true
	elif e is InputEventMouseMotion:
		if _panning or (_maybe_tap and e.position.distance_to(_press_pos) > DRAG_THRESH):
			_panning = true
			demo_cam = false
			unfollow()
			_pan_3d(_pan_last, e.position, vp)
			_pan_last = e.position
			return true
	elif e is InputEventMagnifyGesture:
		demo_cam = false
		zoom_at(e.factor, e.position, vp)
		return true
	elif e is InputEventPanGesture:
		demo_cam = false
		unfollow()
		_pan_3d(e.position, e.position + e.delta * 12, vp)
		return true
	return false
