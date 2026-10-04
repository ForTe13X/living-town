@tool
extends EditorPlugin
## Editor-side draft workflow. A candidate is fully compiled before its source is committed.

const SPEC_PATH := "res://coastal/warm_bay_s1/town.spec.json"
const PACKAGE_PATH := "res://coastal/warm_bay_s1/export/package.json"
const PREVIEW_PATH := "res://scenes/coastal_neighborhood_preview.tscn"
const COMPILER := preload("res://scripts/CoastalPackageCompiler.gd")

var dock: VBoxContainer
var building_tree: Tree
var selected_label: Label
var x_input: SpinBox
var y_input: SpinBox
var status_label: RichTextLabel
var spec: Dictionary = {}
var selected_building_id := ""


func _enter_tree() -> void:
	_build_dock()
	_reload_spec()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, dock)


func _exit_tree() -> void:
	if dock != null:
		remove_control_from_docks(dock)
		dock.queue_free()


func _build_dock() -> void:
	dock = VBoxContainer.new()
	dock.name = "CoastalAuthoring"
	dock.custom_minimum_size = Vector2(330, 0)
	var heading := Label.new()
	heading.text = "Warm Bay S1 · static environment"
	heading.add_theme_font_size_override("font_size", 16)
	dock.add_child(heading)
	var intro := Label.new()
	intro.text = "Select a building to draft a checked move. Undo/Redo applies to the source spec."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(intro)
	building_tree = Tree.new()
	building_tree.columns = 3
	building_tree.set_column_title(0, "Building")
	building_tree.set_column_title(1, "Type")
	building_tree.set_column_title(2, "Shape")
	building_tree.set_column_titles_visible(true)
	building_tree.hide_root = true
	building_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	building_tree.item_selected.connect(_on_building_selected)
	dock.add_child(building_tree)
	selected_label = Label.new()
	selected_label.text = "No building selected"
	dock.add_child(selected_label)
	var position_row := HBoxContainer.new()
	x_input = _make_spin_box("X")
	y_input = _make_spin_box("Y")
	position_row.add_child(_labeled_input("X", x_input))
	position_row.add_child(_labeled_input("Y", y_input))
	dock.add_child(position_row)
	var move_button := Button.new()
	move_button.text = "Validate and apply move"
	move_button.pressed.connect(_apply_move)
	dock.add_child(move_button)
	var button_row := HBoxContainer.new()
	var reload_button := Button.new()
	reload_button.text = "Reload spec"
	reload_button.pressed.connect(_reload_spec)
	button_row.add_child(reload_button)
	var build_button := Button.new()
	build_button.text = "Build package"
	build_button.pressed.connect(_build_package)
	button_row.add_child(build_button)
	dock.add_child(button_row)
	var preview_button := Button.new()
	preview_button.text = "Open neighborhood preview"
	preview_button.pressed.connect(_open_preview)
	dock.add_child(preview_button)
	status_label = RichTextLabel.new()
	status_label.fit_content = true
	status_label.scroll_active = true
	status_label.custom_minimum_size.y = 88
	dock.add_child(status_label)


func _make_spin_box(label: String) -> SpinBox:
	var spin := SpinBox.new()
	spin.name = label
	spin.min_value = 0
	spin.max_value = 127
	spin.step = 1
	spin.rounded = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


func _labeled_input(label: String, input: SpinBox) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = label
	box.add_child(title)
	box.add_child(input)
	return box


func _reload_spec() -> void:
	var file := FileAccess.open(SPEC_PATH, FileAccess.READ)
	if file == null:
		_set_status("Could not read %s" % SPEC_PATH, true)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_set_status("Town spec is not a JSON object.", true)
		return
	spec = parsed
	selected_building_id = ""
	_refresh_tree()
	_set_status("Loaded %d building drafts." % spec.get("buildings", []).size())


func _refresh_tree() -> void:
	building_tree.clear()
	var root := building_tree.create_item()
	for building: Dictionary in spec.get("buildings", []):
		var item := building_tree.create_item(root)
		item.set_text(0, str(building.get("id", "")))
		item.set_text(1, str(building.get("type", "")))
		item.set_text(2, str(building.get("shape", "")))
		item.set_metadata(0, str(building.get("id", "")))
	if selected_label != null:
		selected_label.text = "No building selected"


func _on_building_selected() -> void:
	var item := building_tree.get_selected()
	if item == null:
		return
	selected_building_id = str(item.get_metadata(0))
	var building := _find_building(selected_building_id)
	if building.is_empty():
		return
	var box: Array = building.get("box", [0, 0, 1, 1])
	x_input.value = int(box[0])
	y_input.value = int(box[1])
	selected_label.text = "%s · %s · %s × %s cells" % [selected_building_id, str(building.get("type", "")), str(box[2]), str(box[3])]


func _apply_move() -> void:
	if selected_building_id.is_empty():
		_set_status("Select a building first.", true)
		return
	var current := _find_building(selected_building_id)
	if current.is_empty():
		_set_status("Selected building no longer exists in the source spec.", true)
		return
	var box: Array = current.get("box", [])
	var dx := int(x_input.value) - int(box[0])
	var dy := int(y_input.value) - int(box[1])
	if dx == 0 and dy == 0:
		_set_status("No position change to apply.")
		return
	var candidate := spec.duplicate(true)
	var building := _find_building_in(candidate, selected_building_id)
	building["box"][0] = int(building["box"][0]) + dx
	building["box"][1] = int(building["box"][1]) + dy
	for segment: Dictionary in building.get("segments", []):
		segment["rect"][0] = int(segment["rect"][0]) + dx
		segment["rect"][1] = int(segment["rect"][1]) + dy
	var entry: Dictionary = building.get("entry", {})
	entry["at"][0] = int(entry["at"][0]) + dx
	entry["at"][1] = int(entry["at"][1]) + dy
	var path: Array = entry.get("access_path", [])
	for index in range(path.size() - 1):
		path[index][0] = float(path[index][0]) + dx
		path[index][1] = float(path[index][1]) + dy
	entry["access_path"] = path
	var compiled: Dictionary = COMPILER.compile_spec(candidate)
	if not bool(compiled.get("ok", false)):
		_set_status("Candidate rejected; source was not changed:\n" + "\n".join(compiled.get("errors", [])), true)
		return
	var before_text := JSON.stringify(spec, "\t", true, true) + "\n"
	var after_text := JSON.stringify(candidate, "\t", true, true) + "\n"
	var undo_redo := get_undo_redo()
	undo_redo.create_action("Move %s in Warm Bay S1" % selected_building_id)
	undo_redo.add_do_method(self, "_store_spec_text", after_text)
	undo_redo.add_undo_method(self, "_store_spec_text", before_text)
	undo_redo.commit_action()
	_set_status("Applied %s move (Δ %d, %d cells). Topology is dirty; rebuild package to publish." % [selected_building_id, dx, dy])


func _store_spec_text(text: String) -> void:
	if not _atomic_replace(SPEC_PATH, text):
		_set_status("Could not commit town spec to disk; recoverable staging file may remain.", true)
		return
	var moving_id := selected_building_id
	_reload_spec()
	selected_building_id = moving_id
	var item := _find_tree_item(moving_id)
	if item != null:
		item.select(0)
		_on_building_selected()


func _build_package() -> void:
	var compiled: Dictionary = COMPILER.compile_spec(spec)
	if not bool(compiled.get("ok", false)):
		_set_status("Build rejected:\n" + "\n".join(compiled.get("errors", [])), true)
		return
	var package_text := JSON.stringify(compiled["package"], "\t", true, true) + "\n"
	if not _atomic_replace(PACKAGE_PATH, package_text):
		_set_status("Could not publish the validated package.", true)
		return
	var manifest: Dictionary = compiled["package"]["manifest"]
	_set_status("Package built.\nTopology %s\nRender %s" % [str(manifest["topology_sha256"]).substr(0, 16), str(manifest["render_sha256"]).substr(0, 16)])
	EditorInterface.get_resource_filesystem().scan()


func _open_preview() -> void:
	EditorInterface.open_scene_from_path(PREVIEW_PATH)


func _atomic_replace(path: String, text: String) -> bool:
	var absolute_path := ProjectSettings.globalize_path(path)
	var suffix := str(Time.get_ticks_usec())
	var staging_path := absolute_path + ".coast-stage-" + suffix
	var backup_path := absolute_path + ".coast-backup-" + suffix
	var staging_res := ProjectSettings.localize_path(staging_path)
	var staged := FileAccess.open(staging_res, FileAccess.WRITE)
	if staged == null:
		return false
	staged.store_string(text)
	staged.flush()
	staged.close()
	var had_original := FileAccess.file_exists(absolute_path)
	if had_original and DirAccess.rename_absolute(absolute_path, backup_path) != OK:
		DirAccess.remove_absolute(staging_path)
		return false
	if DirAccess.rename_absolute(staging_path, absolute_path) != OK:
		if had_original:
			DirAccess.rename_absolute(backup_path, absolute_path)
		DirAccess.remove_absolute(staging_path)
		return false
	if had_original:
		DirAccess.remove_absolute(backup_path)
	return true


func _find_building(building_id: String) -> Dictionary:
	return _find_building_in(spec, building_id)


func _find_building_in(source: Dictionary, building_id: String) -> Dictionary:
	for building: Dictionary in source.get("buildings", []):
		if str(building.get("id", "")) == building_id:
			return building
	return {}


func _find_tree_item(building_id: String) -> TreeItem:
	var root := building_tree.get_root()
	if root == null:
		return null
	var item := root.get_first_child()
	while item != null:
		if str(item.get_metadata(0)) == building_id:
			return item
		item = item.get_next()
	return null


func _set_status(message: String, is_error: bool = false) -> void:
	if status_label == null:
		return
	status_label.clear()
	status_label.push_color(Color("#e68b71") if is_error else Color("#b7d39b"))
	status_label.append_text(message.replace("\n", "[br]"))
	status_label.pop()
