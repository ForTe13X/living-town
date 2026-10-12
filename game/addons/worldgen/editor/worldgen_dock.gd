@tool
extends VBoxContainer
class_name WorldGenEditorDock
## Small native authoring surface for semantic patches, candidate builds and undo.

signal candidate_applied(build_id: String, changed_ids: Array)

const EDIT_SCRIPT := preload("res://addons/worldgen/core/edit_command.gd")
const BUILD_SCRIPT := preload("res://addons/worldgen/core/worldgen_build_service.gd")
const STORE_SCRIPT := preload("res://addons/worldgen/core/worldgen_artifact_store.gd")
const VALIDATOR_SCRIPT := preload("res://addons/worldgen/core/worldgen_package_validator.gd")
const SESSION_SCRIPT := preload("res://addons/worldgen/editor/semantic_edit_session.gd")
const CANONICAL_SCRIPT := preload("res://addons/worldgen/core/worldgen_canonical.gd")
const BUILD_JOB_SCRIPT := preload("res://addons/worldgen/editor/worldgen_build_job.gd")
const SCENE_BUILDER := preload("res://addons/worldgen/core/world_package_scene_builder.gd")
const PREVIEW_PIXELS_PER_CELL := 16.0

var session: RefCounted
var undo_adapter: RefCounted
var undo_manager: Object
var undo_context_provider: Callable
var _sessions_by_snapshot: Dictionary = {}
var _base_recipe: Dictionary = {}
var _base_package: Dictionary = {}
var _prepared: Dictionary = {}
var _job_ticket: Dictionary = {}
var _pending_patch_id := ""
var _worker: Thread
var _worker_object: RefCounted
var _status: Label
var _recipe_status: Label
var _stage_field: LineEdit
var _parameter_field: LineEdit
var _edit_class: OptionButton
var _value_json: TextEdit
var _recipe_dialog: FileDialog
var _package_dialog: FileDialog
var _preview: SubViewport
var _preview_container: SubViewportContainer
var _preview_tree: Tree
var _preview_selection_status: Label
var _preview_frame: Node2D
var _preview_world_root: Node2D
var _preview_nodes_by_id: Dictionary = {}
var _preview_tree_items_by_id: Dictionary = {}

func configure(adapter: RefCounted, manager: Object, context_provider: Callable) -> void:
	undo_adapter = adapter
	undo_manager = manager
	undo_context_provider = context_provider

func _ready() -> void:
	name = "WorldGen Authoring"
	_build_controls()
	set_process(true)

func _exit_tree() -> void:
	if _worker != null and _worker.is_started():
		_worker.wait_to_finish()
	_worker = null
	_worker_object = null

func _process(_delta: float) -> void:
	if _worker == null or _worker.is_alive(): return
	var build: Variant = _worker.wait_to_finish()
	_worker = null
	_worker_object = null
	_finish_candidate(build)

func _build_controls() -> void:
	var heading := Label.new()
	heading.text = "WorldGen Authoring"
	add_child(heading)
	_recipe_status = Label.new()
	_recipe_status.text = "Load a recipe and its current WorldPackage."
	_recipe_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_recipe_status)
	var file_row := HBoxContainer.new()
	var recipe_button := Button.new(); recipe_button.text = "Load Recipe"
	recipe_button.pressed.connect(func(): _recipe_dialog.popup_centered_ratio(0.75))
	var package_button := Button.new(); package_button.text = "Load Package"
	package_button.pressed.connect(func(): _package_dialog.popup_centered_ratio(0.75))
	file_row.add_child(recipe_button); file_row.add_child(package_button); add_child(file_row)
	_stage_field = LineEdit.new(); _stage_field.placeholder_text = "Stage ID (for example layout)"; add_child(_stage_field)
	_parameter_field = LineEdit.new(); _parameter_field.placeholder_text = "Allowlisted parameter (for example style_ref)"; add_child(_parameter_field)
	_edit_class = OptionButton.new(); _edit_class.add_item("Visual edit"); _edit_class.set_item_metadata(0, "visual"); _edit_class.add_item("Semantic edit"); _edit_class.set_item_metadata(1, "semantic"); add_child(_edit_class)
	_value_json = TextEdit.new(); _value_json.custom_minimum_size = Vector2(0, 72); _value_json.placeholder_text = "New value as JSON, such as \"winter\" or 1729"; add_child(_value_json)
	var preview_row := HBoxContainer.new()
	preview_row.custom_minimum_size = Vector2(0, 220)
	_preview_container = SubViewportContainer.new()
	_preview_container.custom_minimum_size = Vector2(260, 220)
	_preview_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_container.stretch = true
	_preview_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_container.gui_input.connect(_on_preview_input)
	_preview = SubViewport.new()
	_preview.size = Vector2i(480, 320)
	_preview.transparent_bg = false
	_preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_container.add_child(_preview)
	preview_row.add_child(_preview_container)
	_preview_tree = Tree.new()
	_preview_tree.custom_minimum_size = Vector2(150, 220)
	_preview_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_tree.hide_root = true
	_preview_tree.item_selected.connect(_on_preview_item_selected)
	preview_row.add_child(_preview_tree)
	add_child(preview_row)
	_preview_selection_status = Label.new()
	_preview_selection_status.text = "Package preview · select an ID to inspect its generated node."
	_preview_selection_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_preview_selection_status)
	var apply_button := Button.new(); apply_button.text = "Build, Validate and Apply One Undoable Edit"
	apply_button.pressed.connect(_apply_patch); add_child(apply_button)
	_status = Label.new(); _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(_status)
	_recipe_dialog = _new_json_dialog("Open WorldGen Recipe"); _recipe_dialog.file_selected.connect(_load_recipe)
	_package_dialog = _new_json_dialog("Open WorldPackage"); _package_dialog.file_selected.connect(_load_package)
	add_child(_recipe_dialog); add_child(_package_dialog)

func _new_json_dialog(title_text: String) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.title = title_text
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.add_filter("*.json ; JSON")
	return dialog

func _load_recipe(path: String) -> void:
	if _worker != null: _set_status("Wait for the current candidate build to finish before switching recipes."); return
	var value := _read_json(path)
	if value.is_empty() or String(value.get("schema", "")) != "worldgen.recipe/1":
		_set_status("Recipe load failed: invalid worldgen.recipe/1 JSON.")
		return
	_base_recipe = value
	_try_initialize_session()

func _load_package(path: String) -> void:
	if _worker != null: _set_status("Wait for the current candidate build to finish before switching packages."); return
	var value := _read_json(path)
	var validation: Dictionary = VALIDATOR_SCRIPT.validate(value)
	if not validation.get("ok", false):
		_set_status("Package load failed: " + "; ".join(validation.get("errors", [])))
		return
	_base_package = value
	_refresh_preview()
	_try_initialize_session()

func _try_initialize_session() -> void:
	if _base_recipe.is_empty() or _base_package.is_empty(): return
	if String(_base_recipe.get("id", "")) != String(_base_package.get("world_id", "")):
		_set_status("Recipe and package world IDs do not match.")
		return
	var stored: Dictionary = STORE_SCRIPT.new().put_json("res://addons/worldgen/builds/objects", _base_package)
	if not stored.get("ok", false):
		_set_status("Could not preserve the immutable base package: " + "; ".join(stored.get("errors", [])))
		return
	var session_key := _snapshot_key(_base_recipe, String(stored["sha256"]))
	if _sessions_by_snapshot.has(session_key):
		session = _sessions_by_snapshot[session_key]
	else:
		var new_session: RefCounted = SESSION_SCRIPT.new()
		var initialized: Dictionary = new_session.initialize(_base_recipe, String(stored["sha256"]), String(stored["sha256"]))
		if not initialized.get("ok", false):
			_set_status("Session initialization failed: " + "; ".join(initialized.get("errors", [])))
			return
		session = new_session
		session.snapshot_changed.connect(_on_snapshot_changed)
		_sessions_by_snapshot[session_key] = session
	_on_snapshot_changed(session.capture_snapshot())
	_set_status("Ready. Draft edits build a full candidate and run package validation before one undoable apply.")

func _apply_patch() -> void:
	if _worker != null:
		_set_status("A candidate build is already running.")
		return
	if _base_recipe.is_empty() or _base_package.is_empty():
		_set_status("Load a matching recipe and validated package first.")
		return
	var parser := JSON.new()
	if parser.parse(_value_json.text) != OK:
		_set_status("Edit value is not valid JSON.")
		return
	var declared := String(_edit_class.get_item_metadata(_edit_class.selected))
	var patch := {"schema": "worldgen.edit_patch/1", "patch_id": "editor-%d" % Time.get_ticks_usec(),
		"base_revision": int(_base_recipe.get("source_revision", -1)), "declared_class": declared,
		"changes": [{"path": "stages/%s/parameters/%s" % [_stage_field.text.strip_edges(), _parameter_field.text.strip_edges()], "value": parser.data}]}
	var prepared: Dictionary = EDIT_SCRIPT.prepare_patch(_base_recipe, patch, _base_package)
	if not prepared.get("ok", false):
		_set_status("Patch rejected: " + "; ".join(prepared.get("errors", [])))
		return
	_prepared = prepared
	_job_ticket = session.begin_job()
	_pending_patch_id = String(patch["patch_id"])
	_set_status("Building bounded recipe candidate…")
	_worker = Thread.new()
	_worker_object = BUILD_JOB_SCRIPT.new()
	var thread_error := _worker.start(Callable(_worker_object, "build_candidate").bind(prepared["candidate_recipe"].duplicate(true)))
	if thread_error != OK:
		_worker = null
		_worker_object = null
		_prepared = {}
		_job_ticket = {}
		_pending_patch_id = ""
		_set_status("Candidate worker could not start (%d)." % thread_error)

func _finish_candidate(build: Variant) -> void:
	if not build is Dictionary:
		_set_status("Candidate worker returned invalid data.")
		_clear_pending_candidate()
		return
	if not build.get("ok", false):
		_set_status("Candidate rejected (%s): %s" % [build.get("status", "FAILED"), "; ".join(build.get("errors", []))])
		_clear_pending_candidate()
		return
	var candidate_package: Dictionary = build["package"]
	var diff: Dictionary = EDIT_SCRIPT.validate_candidate(_prepared, _prepared["candidate_recipe"], _base_package, candidate_package)
	if not diff.get("ok", false):
		_set_status("Candidate diff rejected: " + "; ".join(diff.get("errors", [])))
		_clear_pending_candidate()
		return
	var stored: Dictionary = STORE_SCRIPT.new().put_json("res://addons/worldgen/builds/objects", candidate_package)
	if not stored.get("ok", false):
		_set_status("Candidate artifact could not be preserved: " + "; ".join(stored.get("errors", [])))
		_clear_pending_candidate()
		return
	var next_snapshot: Dictionary = session.prepare_result_snapshot(_job_ticket, _prepared["candidate_recipe"], String(stored["sha256"]), String(stored["sha256"]))
	if not next_snapshot.get("ok", false):
		_set_status("Candidate became stale before apply: " + "; ".join(next_snapshot.get("errors", [])))
		_clear_pending_candidate()
		return
	var context: Object = undo_context_provider.call() if undo_context_provider.is_valid() else null
	var committed: Dictionary = undo_adapter.record_transition(undo_manager, session, session.capture_snapshot(), next_snapshot["snapshot"], "WorldGen: %s" % _pending_patch_id, context)
	if not committed.get("ok", false):
		_set_status("Undo transaction rejected: " + "; ".join(committed.get("errors", [])))
		_clear_pending_candidate()
		return
	_clear_pending_candidate()
	var changed: Array = diff.get("changed_ids", [])
	_set_status("Applied %s edit. Changed IDs: %s. Build: %s" % [diff.get("actual_class", "unknown"), ", ".join(changed), String(stored["sha256"]).left(12)])
	emit_signal("candidate_applied", String(stored["sha256"]), changed)

func _clear_pending_candidate() -> void:
	_prepared = {}
	_job_ticket = {}
	_pending_patch_id = ""

func _on_snapshot_changed(snapshot: Dictionary) -> void:
	if snapshot.is_empty(): return
	_base_recipe = snapshot.get("recipe", {}).duplicate(true)
	var package_digest := String(snapshot.get("package_sha256", ""))
	if not package_digest.is_empty(): _sessions_by_snapshot[_snapshot_key(_base_recipe, package_digest)] = session
	if package_digest.length() == 64:
		var object_path := "res://addons/worldgen/builds/objects".path_join(package_digest.left(2)).path_join(package_digest + ".json")
		var loaded: Dictionary = STORE_SCRIPT.new().read_json(object_path, package_digest)
		if loaded.get("ok", false): _base_package = loaded["data"].duplicate(true)
	_refresh_preview()
	if _recipe_status != null:
		_recipe_status.text = "%s · revision %d · build %s" % [String(_base_recipe.get("id", "")), int(_base_recipe.get("source_revision", -1)), String(snapshot.get("build_id", "")).left(12)]

func _refresh_preview() -> void:
	if _preview == null or _preview_tree == null: return
	for child: Node in _preview.get_children():
		_preview.remove_child(child)
		child.queue_free()
	_preview_world_root = null
	_preview_frame = null
	_preview_nodes_by_id.clear()
	_preview_tree_items_by_id.clear()
	_preview_tree.clear()
	var tree_root := _preview_tree.create_item()
	if _base_package.is_empty():
		_preview_selection_status.text = "Package preview · load a matching recipe and package."
		return
	var semantic: Dictionary = _base_package.get("semantic", {})
	var topology: Dictionary = semantic.get("topology", {})
	var extent: Array = semantic.get("extent_cells", topology.get("extent_cells", [1, 1]))
	if extent.size() != 2:
		_preview_selection_status.text = "Package preview unavailable · package extent is malformed."
		return
	var world_width := maxf(1.0, float(extent[0]) * PREVIEW_PIXELS_PER_CELL)
	var world_height := maxf(1.0, float(extent[1]) * PREVIEW_PIXELS_PER_CELL)
	var view_size := Vector2(_preview.size)
	var fit := minf((view_size.x - 24.0) / world_width, (view_size.y - 24.0) / world_height)
	_preview_frame = Node2D.new()
	_preview_frame.name = "PackagePreviewFrame"
	_preview_frame.position = (view_size - Vector2(world_width, world_height) * fit) * 0.5
	_preview_frame.scale = Vector2.ONE * fit
	_preview.add_child(_preview_frame)
	_preview_world_root = SCENE_BUILDER.build(_base_package)
	_preview_frame.add_child(_preview_world_root)
	var world_item := _preview_tree.create_item(tree_root)
	world_item.set_text(0, String(_base_package.get("world_id", "world")))
	world_item.set_metadata(0, "")
	var ids: Array[String] = []
	_collect_preview_ids(semantic, ids)
	ids.sort()
	for stable_id: String in ids:
		var item := _preview_tree.create_item(world_item)
		item.set_text(0, stable_id)
		item.set_metadata(0, stable_id)
		_preview_tree_items_by_id[stable_id] = item
	_index_preview_nodes(_preview_world_root)
	_preview_selection_status.text = "%s · %d inspectable IDs · semantic %s" % [String(_base_package.get("world_id", "world")), ids.size(), String(_base_package.get("digests", {}).get("semantic_sha256", "")).left(12)]

func _collect_preview_ids(value: Variant, ids: Array[String]) -> void:
	if value is Dictionary:
		var id := String(value.get("id", ""))
		if not id.is_empty() and not ids.has(id): ids.append(id)
		for key: Variant in value: _collect_preview_ids(value[key], ids)
	elif value is Array:
		for item: Variant in value: _collect_preview_ids(item, ids)

func _index_preview_nodes(node: Node) -> void:
	if node.has_meta("worldgen_id"):
		var id := String(node.get_meta("worldgen_id"))
		var nodes: Array = _preview_nodes_by_id.get(id, [])
		nodes.append(node)
		_preview_nodes_by_id[id] = nodes
	for child: Node in node.get_children(): _index_preview_nodes(child)

func _on_preview_item_selected() -> void:
	if _preview_tree == null: return
	var selected := _preview_tree.get_selected()
	if selected == null: return
	var stable_id := String(selected.get_metadata(0))
	if stable_id.is_empty(): return
	for id: Variant in _preview_nodes_by_id:
		for node: Node in _preview_nodes_by_id[id]:
			if node is CanvasItem:
				node.modulate = Color(1.0, 1.0, 1.0, 1.0) if String(id) == stable_id else Color(0.50, 0.58, 0.54, 0.55)
	_preview_selection_status.text = "Selected %s · %d generated nodes share this stable ID." % [stable_id, _preview_nodes_by_id.get(stable_id, []).size()]

func _on_preview_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	if _preview_frame == null or _preview_world_root == null or _preview_container.size.x <= 0.0 or _preview_container.size.y <= 0.0:
		return
	var mouse_event := event as InputEventMouseButton
	var viewport_position := mouse_event.position * Vector2(_preview.size) / _preview_container.size
	var package_position := (viewport_position - _preview_frame.position) / _preview_frame.scale
	var canvas_point := _preview_world_root.to_global(package_position)
	var picked := _pick_preview_id(_preview_world_root, canvas_point)
	var stable_id := String(picked.get("id", ""))
	if stable_id.is_empty(): return
	_select_preview_tree_id(_preview_tree.get_root(), stable_id)

func _pick_preview_id(node: Node, canvas_point: Vector2) -> Dictionary:
	var best := {"id": "", "priority": -1}
	if node is Polygon2D and node.has_meta("worldgen_id"):
		var polygon := node as Polygon2D
		if Geometry2D.is_point_in_polygon(polygon.to_local(canvas_point), polygon.polygon):
			var kind := String(node.get_meta("worldgen_kind", ""))
			best = {"id": String(node.get_meta("worldgen_id")), "priority": 3 if kind == "building_footprint" else 1}
	for child: Node in node.get_children():
		var candidate := _pick_preview_id(child, canvas_point)
		if int(candidate.get("priority", -1)) > int(best.get("priority", -1)):
			best = candidate
	return best

func _select_preview_tree_id(_root_item: TreeItem, stable_id: String) -> bool:
	if not _preview_tree_items_by_id.has(stable_id): return false
	var item: TreeItem = _preview_tree_items_by_id[stable_id]
	item.select(0)
	_preview_tree.scroll_to_item(item)
	return true

func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	return parser.data if parse_error == OK and parser.data is Dictionary else {}

func _snapshot_key(recipe: Dictionary, package_digest: String) -> String:
	return String(recipe.get("id", "")) + ":" + CANONICAL_SCRIPT.sha256(recipe) + ":" + package_digest

func _set_status(message: String) -> void:
	if _status != null: _status.text = message
