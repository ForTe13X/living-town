@tool
extends EditorPlugin
## Adds a small procedural edit dock backed by semantic snapshots and native undo.

const UNDO_ADAPTER_SCRIPT := preload("res://addons/worldgen/editor/undo_adapter.gd")
const DOCK_SCRIPT := preload("res://addons/worldgen/editor/worldgen_dock.gd")

var _undo_adapter: RefCounted
var _dock: Control

func _enter_tree() -> void:
	_undo_adapter = UNDO_ADAPTER_SCRIPT.new()
	_dock = DOCK_SCRIPT.new()
	_dock.configure(_undo_adapter, get_undo_redo(), Callable(self, "_get_undo_context"))
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
	_dock = null
	_undo_adapter = null

func _get_undo_context() -> Object:
	return EditorInterface.get_edited_scene_root()
