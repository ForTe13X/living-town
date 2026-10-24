@tool
extends EditorPlugin

const RawSourcesExport = preload("res://addons/town_raw_sources/raw_sources_export.gd")
var _raw_sources_export: EditorExportPlugin


func _enter_tree() -> void:
	_raw_sources_export = RawSourcesExport.new()
	add_export_plugin(_raw_sources_export)


func _exit_tree() -> void:
	if _raw_sources_export != null:
		remove_export_plugin(_raw_sources_export)
		_raw_sources_export = null
