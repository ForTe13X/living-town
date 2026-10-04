extends Node2D
## Displays a frozen package and builds its native, inspectable Godot node tree.

const LOADER := preload("res://addons/worldgen/core/worldgen_package_loader.gd")
const SCENE_BUILDER := preload("res://addons/worldgen/core/world_package_scene_builder.gd")
const SPATIAL_QUERIES := preload("res://addons/worldgen/core/world_package_spatial_queries.gd")
const VIEW_SIZE := Vector2(960, 640)
const PAD := 64.0
const BUILDER_PIXELS_PER_CELL := 16.0

var _package: Dictionary = {}
var _extent := Vector2i.ONE
var _origin := Vector2.ZERO
var _cell_px := 1.0
var _world_root: Node2D
var _query_summary := ""

func _ready() -> void:
	var result: Dictionary = LOADER.new().load_package("res://world.world.json",
		{"flat_ground": true, "portals": true, "presentation_profiles": ["code_only_2d"]})
	if not result.get("ok", false):
		push_error("WORLD_VIEWER: " + "; ".join(result.get("errors", [])))
		return
	_package = result["package"]
	var spatial_queries = SPATIAL_QUERIES.new()
	var query_result: Dictionary = spatial_queries.configure(_package)
	if not bool(query_result.get("ok", false)):
		push_error("WORLD_QUERY_API: " + "; ".join(query_result.get("errors", [])))
		return
	_query_summary = "Read-only queries  ·  %d rooms  ·  %d portals  ·  %d public affordances" % [
		spatial_queries.query_rooms("public").size(),
		spatial_queries.query_portals("public").size(),
		spatial_queries.query_affordances("public").size()]
	print("WORLD_PACKAGE_QUERIES_READY world=%s public_rooms=%d staff_rooms=%d public_portals=%d public_affordances=%d staff_affordances=%d" % [
		String(_package.get("world_id", "")),
		spatial_queries.query_rooms("public").size(), spatial_queries.query_rooms("staff").size(),
		spatial_queries.query_portals("public").size(),
		spatial_queries.query_affordances("public").size(), spatial_queries.query_affordances("staff").size()])
	var semantic: Dictionary = _package.get("semantic", {})
	var topology: Dictionary = semantic.get("topology", {})
	var extent: Array = semantic.get("extent_cells", topology.get("extent_cells", [1, 1]))
	_extent = Vector2i(maxi(1, int(extent[0])), maxi(1, int(extent[1])))
	_cell_px = minf((VIEW_SIZE.x - PAD * 2.0) / _extent.x, (VIEW_SIZE.y - PAD * 2.0) / _extent.y)
	_origin = (VIEW_SIZE - Vector2(_extent) * _cell_px) * 0.5 + Vector2(0, 14)
	_world_root = SCENE_BUILDER.build(_package)
	_world_root.position = _origin
	_world_root.scale = Vector2.ONE * (_cell_px / BUILDER_PIXELS_PER_CELL)
	_normalize_package_labels(_world_root, 1.0 / maxf(0.001, _world_root.scale.x))
	add_child(_world_root)
	print("WORLD_PACKAGE_SCENE_READY world=%s native_nodes=%d semantic=%s" % [String(_package.get("world_id", "")), _count_nodes(_world_root), String(_package.get("digests", {}).get("semantic_sha256", ""))])
	queue_redraw()

func _draw() -> void:
	if _package.is_empty(): return
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color("e9f0e8"), true)
	draw_string(ThemeDB.fallback_font, Vector2(24, 34), "%s  ·  %s" % [String(_package.get("world_id", "")), String(_package.get("semantic", {}).get("kind", "world"))], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("203239"))
	draw_string(ThemeDB.fallback_font, Vector2(24, 56), "%d × %d cells  ·  native Godot semantic nodes  ·  %s" % [_extent.x, _extent.y, String(_package.get("digests", {}).get("semantic_sha256", "")).left(16)], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("56696a"))
	draw_string(ThemeDB.fallback_font, Vector2(24, 76), _query_summary, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("56696a"))
	var bounds := Rect2(_origin, Vector2(_extent) * _cell_px)
	draw_rect(bounds, Color("d8e2d2"), true)
	for x in range(_extent.x + 1):
		var px := _origin.x + float(x) * _cell_px
		draw_line(Vector2(px, bounds.position.y), Vector2(px, bounds.end.y), Color(0.27, 0.37, 0.33, 0.10), 1.0)
	for y in range(_extent.y + 1):
		var py := _origin.y + float(y) * _cell_px
		draw_line(Vector2(bounds.position.x, py), Vector2(bounds.end.x, py), Color(0.27, 0.37, 0.33, 0.10), 1.0)
	draw_rect(bounds, Color("52665d"), false, 2.0)

func _count_nodes(node: Node) -> int:
	var count := 1
	for child: Node in node.get_children(): count += _count_nodes(child)
	return count

func _normalize_package_labels(node: Node, inverse_world_scale: float) -> void:
	if node is Label and node.name != "ActionLabel": node.scale = Vector2.ONE * inverse_world_scale
	for child: Node in node.get_children(): _normalize_package_labels(child, inverse_world_scale)
