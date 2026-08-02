extends Node
## S13 dedicated visual/contract gate.  It projects one synthetic authority state
## through S06, renders only the ten-field snapshots, and measures real pixels.

const HIDDEN_NODE := "sealed_cellar_DO_NOT_RENDER"
const HIDDEN_CLAIM_PROSE := "AUTHOR_ONLY_CLAIM_PROSE_7F3E_DO_NOT_RENDER"
const HIDDEN_FRAGMENT_PROSE := "AUTHOR_ONLY_FRAGMENT_BODY_91A2_DO_NOT_RENDER"
const DEFAULT_OUT := "res://../analysis/narrative_visual/s13"
const REVIEW_WATERMARK_TEXT := "SYNTHETIC COMPONENT REVIEW · NOT GAMEPLAY"
const REVIEW_WATERMARK_HEIGHT := 38
const REVIEW_WATERMARK_ACCENT := Color("d88b57")
const REVIEW_WATERMARK_INK := Color("f5e7c5")

var _failures: Array[String] = []
var _checks := 0
var _metrics := {}
var _negative_control := false
var _write_outputs := true
var _run_completed := false
var _logic_only := false


class Backdrop:
	extends Control

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("11131a"))
		for y in range(0, int(size.y), 32):
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.20, 0.20, 0.27, 0.18), 1.0)


class GlyphSwatch:
	extends Control
	var glyph_kind := NarrativeGlyphs.UNKNOWN
	var collapse := false

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("20212b"))
		draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), Color("494758"), false, 1.0)
		var rendered_kind := NarrativeGlyphs.UNKNOWN if collapse else glyph_kind
		var inset := maxf(2.0, size.x * 0.10)
		NarrativeGlyphs.draw_glyph(self, rendered_kind, Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0))


func _ready() -> void:
	call_deferred("_start")


func _start() -> void:
	var args := OS.get_cmdline_user_args()
	_negative_control = "--negative-control" in args
	_write_outputs = not "--no-output" in args
	_logic_only = "--logic-only" in args
	var out_dir := ProjectSettings.globalize_path(DEFAULT_OUT)
	var out_index := args.find("--out")
	if out_index >= 0 and out_index + 1 < args.size():
		out_dir = String(args[out_index + 1])
	if _write_outputs:
		DirAccess.make_dir_recursive_absolute(out_dir)
	await _run(out_dir)
	if not _run_completed:
		_failures.append("test coroutine aborted before completing its gates")
	if _negative_control:
		if _failures.is_empty():
			push_error("S13 NEGATIVE CONTROL: FALSE GREEN")
			get_tree().quit(9)
		else:
			print("S13 NEGATIVE CONTROL: RED as expected (%d gate failures)" % _failures.size())
			get_tree().quit(7)
		return
	if _failures.is_empty():
		print("S13 VISUAL: PASS (%d checks, 0 fail)" % _checks)
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("S13 VISUAL: FAIL (%d checks, %d fail)" % [_checks, _failures.size()])
		get_tree().quit(1)


func _run(out_dir: String) -> void:
	_check(REVIEW_WATERMARK_TEXT == "SYNTHETIC COMPONENT REVIEW · NOT GAMEPLAY", "review watermark text drifted")
	var projected_a := NarrativeViewContract.project(_authority_fixture(), "role_lan")
	var projected_b := NarrativeViewContract.project(_authority_fixture(), "role_qiao")
	_check(bool(projected_a["ok"]), "S06 projection failed for role_lan: %s" % [projected_a["errors"]])
	_check(bool(projected_b["ok"]), "S06 projection failed for role_qiao: %s" % [projected_b["errors"]])
	if not bool(projected_a["ok"]) or not bool(projected_b["ok"]):
		return
	var snapshot_a: Dictionary = projected_a["snapshot"]
	var snapshot_b: Dictionary = projected_b["snapshot"]
	_check(_exact_ten_fields(snapshot_a), "role_lan snapshot is not the S06 ten-field shape")
	_check(_exact_ten_fields(snapshot_b), "role_qiao snapshot is not the S06 ten-field shape")
	_check(snapshot_a["now_node"] == snapshot_b["now_node"], "role pair must share the same current node")
	_check(snapshot_a["visible_nodes"] != snapshot_b["visible_nodes"], "role pair visible subgraphs unexpectedly match")
	_check(snapshot_a["receipt_ids"] != snapshot_b["receipt_ids"], "role pair receipt IDs unexpectedly match")
	var snapshot_dump := JSON.stringify([snapshot_a, snapshot_b])
	_check(not HIDDEN_NODE in snapshot_dump, "hidden node leaked into S06 snapshot")
	_check(not HIDDEN_CLAIM_PROSE in snapshot_dump, "hidden claim prose leaked into S06 snapshot")
	_check(not HIDDEN_FRAGMENT_PROSE in snapshot_dump, "hidden fragment prose leaked into S06 snapshot")

	var role_pair := _make_role_pair(snapshot_a, snapshot_b)
	_check(_tree_is_clean(role_pair), "hidden node/claim prose entered role-pair node tree")
	var maze_pair := _make_maze_pair(snapshot_a, snapshot_b)
	_check(_tree_is_clean(maze_pair), "hidden node/claim prose entered maze node tree")

	var bad_snapshot := snapshot_a.duplicate(true)
	bad_snapshot["claim_prose"] = HIDDEN_CLAIM_PROSE
	var reject_graph := WebMazeGraph.new()
	var reject_card := RolePOVCard.new()
	_check(not reject_graph.set_snapshot(bad_snapshot), "WebMazeGraph accepted an eleventh prose field")
	_check(not reject_card.set_snapshot(bad_snapshot), "RolePOVCard accepted an eleventh prose field")
	reject_graph.free()
	reject_card.free()
	if _logic_only:
		role_pair.free()
		maze_pair.free()
		_run_completed = true
		return

	var role_pair_image: Image = await _render_control(role_pair, Vector2i(1200, 650), true)
	_check(role_pair_image != null and not role_pair_image.is_empty(), "role-pair render is empty")
	var role_watermark := _watermark_stats(role_pair_image)
	_check(bool(role_watermark["present"]), "role-pair review watermark is missing from rendered pixels")
	if _write_outputs and role_pair_image != null:
		_check(role_pair_image.save_png(out_dir.path_join("role_pair.png")) == OK, "could not save role_pair.png")

	var maze_image: Image = await _render_control(maze_pair, Vector2i(1200, 620), true)
	_check(maze_image != null and not maze_image.is_empty(), "maze render is empty")
	var maze_watermark := _watermark_stats(maze_image)
	_check(bool(maze_watermark["present"]), "maze review watermark is missing from rendered pixels")
	if _write_outputs and maze_image != null:
		_check(maze_image.save_png(out_dir.path_join("maze.png")) == OK, "could not save maze.png")

	var glyph_sheet := _make_glyph_sheet(_negative_control)
	var glyph_sheet_image: Image = await _render_control(glyph_sheet, Vector2i(1000, 360), true)
	_check(not glyph_sheet_image.is_empty(), "glyph-sheet render is empty")
	var glyph_watermark := _watermark_stats(glyph_sheet_image)
	_check(bool(glyph_watermark["present"]), "glyph-sheet review watermark is missing from rendered pixels")
	if _write_outputs:
		_check(glyph_sheet_image.save_png(out_dir.path_join("glyph_sheet.png")) == OK, "could not save glyph_sheet.png")

	var card_a_image: Image = await _render_control(_make_card_only(snapshot_a), Vector2i(520, 560))
	var card_b_image: Image = await _render_control(_make_card_only(snapshot_b), Vector2i(520, 560))
	var role_card_diff := _pixel_diff_count(card_a_image, card_b_image)
	_metrics["role_card_pair_rgb_diff_pixels"] = role_card_diff
	_check(role_card_diff > 400, "same-node role cards are not visibly different: %d pixels" % role_card_diff)

	var graph_a_image: Image = await _render_control(_make_graph_only(snapshot_a), Vector2i(560, 460))
	var graph_b_image: Image = await _render_control(_make_graph_only(snapshot_b), Vector2i(560, 460))
	var maze_diff := _pixel_diff_count(graph_a_image, graph_b_image)
	_metrics["maze_pair_rgb_diff_pixels"] = maze_diff
	_check(maze_diff > 400, "same-node visible subgraphs are not visibly different: %d pixels" % maze_diff)

	var pair_metrics := {}
	for side in [64, 32]:
		var glyph_images := {}
		for kind in NarrativeGlyphs.KINDS:
			glyph_images[kind] = await _render_glyph(String(kind), side, _negative_control)
		var scale_metrics := {}
		var min_diff := 2147483647
		for left_index in range(NarrativeGlyphs.KINDS.size()):
			for right_index in range(left_index + 1, NarrativeGlyphs.KINDS.size()):
				var left := String(NarrativeGlyphs.KINDS[left_index])
				var right := String(NarrativeGlyphs.KINDS[right_index])
				var diff := _pixel_diff_count(glyph_images[left], glyph_images[right])
				scale_metrics["%s__%s" % [left, right]] = diff
				min_diff = mini(min_diff, diff)
				_check(diff > 0, "glyphs collapse at %dpx: %s vs %s" % [side, left, right])
		pair_metrics["%dpx" % side] = scale_metrics
		_metrics["glyph_%dpx_min_pair_diff" % side] = min_diff
	_metrics["glyph_pair_rgb_diff_pixels"] = pair_metrics

	_metrics["role_pair_png_size"] = [role_pair_image.get_width(), role_pair_image.get_height()]
	_metrics["maze_png_size"] = [maze_image.get_width(), maze_image.get_height()]
	_metrics["glyph_sheet_png_size"] = [glyph_sheet_image.get_width(), glyph_sheet_image.get_height()]
	_metrics["review_watermark_text"] = REVIEW_WATERMARK_TEXT
	_metrics["review_watermark_height"] = REVIEW_WATERMARK_HEIGHT
	_metrics["review_watermark_applied_to"] = ["role_pair.png", "maze.png", "glyph_sheet.png"]
	_metrics["review_watermark_pixel_stats"] = {
		"role_pair.png": role_watermark,
		"maze.png": maze_watermark,
		"glyph_sheet.png": glyph_watermark,
	}
	if _write_outputs and not _negative_control:
		var metrics_file := FileAccess.open(out_dir.path_join("metrics.json"), FileAccess.WRITE)
		_check(metrics_file != null, "could not create metrics.json")
		_metrics["checks"] = _checks
		_metrics["failures"] = _failures
		if metrics_file != null:
			metrics_file.store_string(JSON.stringify(_metrics, "  "))
			metrics_file.close()
	_run_completed = true


func _make_role_pair(snapshot_a: Dictionary, snapshot_b: Dictionary) -> Control:
	var root := _board(Vector2(1200, 650), "ROLE POV / SAME NODE, DIFFERENT EVIDENCE")
	var card_a := RolePOVCard.new()
	card_a.name = "role_lan_card"
	card_a.position = Vector2(80, 82)
	card_a.size = Vector2(500, 520)
	root.add_child(card_a)
	_check(card_a.set_snapshot(snapshot_a), "role_lan card rejected S06 snapshot")
	var card_b := RolePOVCard.new()
	card_b.name = "role_qiao_card"
	card_b.position = Vector2(620, 82)
	card_b.size = Vector2(500, 520)
	root.add_child(card_b)
	_check(card_b.set_snapshot(snapshot_b), "role_qiao card rejected S06 snapshot")
	_check(card_a.snapshot_fingerprint() != card_b.snapshot_fingerprint(), "role-card fingerprints unexpectedly match")
	return root


func _make_maze_pair(snapshot_a: Dictionary, snapshot_b: Dictionary) -> Control:
	var root := _board(Vector2(1200, 620), "WEB MAZE / ROLE-FILTERED VISIBLE SUBGRAPHS")
	var graph_a := WebMazeGraph.new()
	graph_a.name = "role_lan_maze"
	graph_a.position = Vector2(40, 92)
	graph_a.size = Vector2(540, 470)
	root.add_child(graph_a)
	_check(graph_a.set_snapshot(snapshot_a), "role_lan maze rejected S06 snapshot")
	var graph_b := WebMazeGraph.new()
	graph_b.name = "role_qiao_maze"
	graph_b.position = Vector2(620, 92)
	graph_b.size = Vector2(540, 470)
	root.add_child(graph_b)
	_check(graph_b.set_snapshot(snapshot_b), "role_qiao maze rejected S06 snapshot")
	_check(graph_a.snapshot_fingerprint() != graph_b.snapshot_fingerprint(), "maze fingerprints unexpectedly match")
	_add_label(root, "role_lan", Vector2(40, 57), Vector2(540, 28), 16, Color("d88b57"), HORIZONTAL_ALIGNMENT_CENTER)
	_add_label(root, "role_qiao", Vector2(620, 57), Vector2(540, 28), 16, Color("d88b57"), HORIZONTAL_ALIGNMENT_CENTER)
	return root


func _make_glyph_sheet(collapse: bool) -> Control:
	var root := _board(Vector2(1000, 360), "NARRATIVE GLYPHS / 1x + 0.5x")
	_add_label(root, "1x / 64 px", Vector2(24, 86), Vector2(110, 24), 15, Color("d88b57"))
	_add_label(root, "0.5x / 32 px", Vector2(24, 246), Vector2(110, 24), 15, Color("d88b57"))
	for index in range(NarrativeGlyphs.KINDS.size()):
		var kind := String(NarrativeGlyphs.KINDS[index])
		var x := 145.0 + index * 136.0
		var large := GlyphSwatch.new()
		large.name = "%s_1x" % kind
		large.glyph_kind = kind
		large.collapse = collapse
		large.position = Vector2(x + 26, 78)
		large.size = Vector2(64, 64)
		root.add_child(large)
		_add_label(root, kind, Vector2(x, 150), Vector2(116, 24), 14, Color("e6d6ad"), HORIZONTAL_ALIGNMENT_CENTER)
		var small := GlyphSwatch.new()
		small.name = "%s_half" % kind
		small.glyph_kind = kind
		small.collapse = collapse
		small.position = Vector2(x + 42, 234)
		small.size = Vector2(32, 32)
		root.add_child(small)
		_add_label(root, kind, Vector2(x, 276), Vector2(116, 24), 13, Color("aaa4b4"), HORIZONTAL_ALIGNMENT_CENTER)
	return root


func _make_card_only(snapshot: Dictionary) -> Control:
	var root := Backdrop.new()
	root.size = Vector2(520, 560)
	var card := RolePOVCard.new()
	card.position = Vector2(25, 20)
	card.size = Vector2(470, 520)
	root.add_child(card)
	card.set_snapshot(snapshot)
	return root


func _make_graph_only(snapshot: Dictionary) -> Control:
	var root := Backdrop.new()
	root.size = Vector2(560, 460)
	var graph := WebMazeGraph.new()
	graph.position = Vector2(20, 20)
	graph.size = Vector2(520, 420)
	root.add_child(graph)
	graph.set_snapshot(snapshot)
	return root


func _board(board_size: Vector2, title: String) -> Control:
	var root := Backdrop.new()
	root.size = board_size
	_add_label(root, title, Vector2(24, 20), Vector2(board_size.x - 48, 34), 22, Color("eadfc4"), HORIZONTAL_ALIGNMENT_CENTER)
	return root


func _add_label(parent: Node, value: String, pos: Vector2, label_size: Vector2, font_size: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var label := Label.new()
	label.text = value
	label.position = pos
	label.size = label_size
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


func _render_control(control: Control, dimensions: Vector2i, add_review_watermark := false) -> Image:
	var viewport := SubViewport.new()
	viewport.name = "s13_capture_%dx%d" % [dimensions.x, dimensions.y]
	viewport.size = dimensions
	viewport.transparent_bg = false
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	control.position = Vector2.ZERO
	control.size = Vector2(dimensions)
	viewport.add_child(control)
	var watermark: Control = null
	if add_review_watermark:
		watermark = _make_review_watermark(dimensions)
		viewport.add_child(watermark)
	await get_tree().process_frame
	# RenderingServer.frame_post_draw is never emitted by this project's
	# --headless path (docs/41); settling regular frames keeps the gate finite.
	await get_tree().process_frame
	await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	if watermark != null:
		viewport.remove_child(watermark)
		watermark.free()
	viewport.remove_child(control)
	control.free()
	remove_child(viewport)
	viewport.free()
	return image


func _make_review_watermark(dimensions: Vector2i) -> Control:
	var root := Control.new()
	root.name = "s13_review_watermark"
	root.position = Vector2(0, dimensions.y - REVIEW_WATERMARK_HEIGHT)
	root.size = Vector2(dimensions.x, REVIEW_WATERMARK_HEIGHT)
	root.z_index = 1000
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := ColorRect.new()
	background.color = Color("0b0d12")
	background.size = root.size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	var accent := ColorRect.new()
	accent.color = REVIEW_WATERMARK_ACCENT
	accent.size = Vector2(dimensions.x, 2)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(accent)
	var label := Label.new()
	label.name = "not_gameplay_label"
	label.text = REVIEW_WATERMARK_TEXT
	label.position = Vector2(12, 3)
	label.size = Vector2(dimensions.x - 24, REVIEW_WATERMARK_HEIGHT - 5)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", REVIEW_WATERMARK_INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(label)
	return root


func _watermark_stats(image: Image) -> Dictionary:
	if image == null or image.is_empty():
		return {"present": false, "max_accent_row_pixels": 0, "text_ink_pixels": 0}
	var start_y := maxi(0, image.get_height() - REVIEW_WATERMARK_HEIGHT)
	var max_accent_row_pixels := 0
	var text_ink_pixels := 0
	for y in range(start_y, image.get_height()):
		var accent_pixels := 0
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if absf(pixel.r - REVIEW_WATERMARK_ACCENT.r) <= 0.08 and absf(pixel.g - REVIEW_WATERMARK_ACCENT.g) <= 0.08 and absf(pixel.b - REVIEW_WATERMARK_ACCENT.b) <= 0.08:
				accent_pixels += 1
			if pixel.r >= 0.80 and pixel.g >= 0.72 and pixel.b >= 0.56:
				text_ink_pixels += 1
		max_accent_row_pixels = maxi(max_accent_row_pixels, accent_pixels)
	return {
		"max_accent_row_pixels": max_accent_row_pixels,
		"text_ink_pixels": text_ink_pixels,
		"present": max_accent_row_pixels >= int(image.get_width() * 0.90) and text_ink_pixels >= 220,
	}


func _render_glyph(kind: String, side: int, collapse: bool) -> Image:
	var swatch := GlyphSwatch.new()
	swatch.glyph_kind = kind
	swatch.collapse = collapse
	swatch.size = Vector2(side, side)
	return await _render_control(swatch, Vector2i(side, side))


func _pixel_diff_count(left: Image, right: Image) -> int:
	if left.is_empty() or right.is_empty() or left.get_size() != right.get_size():
		return -1
	var diff := 0
	for y in range(left.get_height()):
		for x in range(left.get_width()):
			if left.get_pixel(x, y).to_rgba32() != right.get_pixel(x, y).to_rgba32():
				diff += 1
	return diff


func _tree_is_clean(root: Node) -> bool:
	var tree_text := _collect_tree_text(root)
	return not HIDDEN_NODE in tree_text and not HIDDEN_CLAIM_PROSE in tree_text and not HIDDEN_FRAGMENT_PROSE in tree_text


func _collect_tree_text(node: Node) -> String:
	var parts: Array[String] = [node.name]
	if node is Label:
		parts.append((node as Label).text)
	for child in node.get_children():
		parts.append(_collect_tree_text(child))
	return "\n".join(parts)


func _exact_ten_fields(snapshot: Dictionary) -> bool:
	if snapshot.size() != NarrativeViewContract.SNAPSHOT_KEYS.size():
		return false
	for key in NarrativeViewContract.SNAPSHOT_KEYS:
		if not snapshot.has(key):
			return false
	return true


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)


func _authority_fixture() -> Dictionary:
	return {
		"nodes": {
			"square": {"title": "Public square"},
			"cafe": {"title": "Cafe"},
			"archive": {"title": "Archive"},
			"river": {"title": "River stairs"},
			"workshop": {"title": "Workshop"},
			HIDDEN_NODE: {"title": "Author-only chamber"},
		},
		"edges": {
			"edge_square_cafe": {"from_node": "square", "to_node": "cafe"},
			"edge_cafe_archive": {"from_node": "cafe", "to_node": "archive"},
			"edge_square_river": {"from_node": "square", "to_node": "river"},
			"edge_river_workshop": {"from_node": "river", "to_node": "workshop"},
			"edge_workshop_cafe": {"from_node": "workshop", "to_node": "cafe"},
			"edge_hidden": {"from_node": "square", "to_node": HIDDEN_NODE},
		},
		"fragments": {
			"fragment_red_thread": {"custodian_role_id": "role_lan", "body": "public-safe-id, secret body omitted"},
			"fragment_river_mark": {"custodian_role_id": "role_qiao", "body": "second secret body omitted"},
			"fragment_author_only": {"custodian_role_id": "role_author", "body": HIDDEN_FRAGMENT_PROSE},
		},
		"receipts": {
			"receipt_lan_ink": {"role_id": "role_lan", "claim_id": "claim_ink"},
			"receipt_qiao_bell": {"role_id": "role_qiao", "claim_id": "claim_bell"},
			"receipt_qiao_river": {"role_id": "role_qiao", "claim_id": "claim_river"},
		},
		"claims": {
			"claim_ink": {"prose": "Lan may read this claim, but the view still gets only its receipt ID."},
			"claim_bell": {"prose": "Qiao may read this claim, but the view still gets only its receipt ID."},
			"claim_river": {"prose": "A second Qiao receipt proves the card differs."},
			"claim_author_only": {"prose": HIDDEN_CLAIM_PROSE},
		},
		"requests": {
			"request_archive_key": {"role_ids": ["role_lan"]},
			"request_river_witness": {"role_ids": ["role_qiao"]},
		},
		"roles": {
			"role_lan": {
				"now_node": "square",
				"visible_node_ids": ["square", "cafe", "archive"],
				"visible_edge_ids": ["edge_square_cafe", "edge_cafe_archive"],
				"carried_fragment_ids": ["fragment_red_thread"],
				"receipt_ids": ["receipt_lan_ink"],
				"open_request_ids": ["request_archive_key"],
				"route_hint": ["square", "cafe", "archive"],
				"clock": {"day": 2, "watch": 5, "tick": 3},
				"status": "active",
			},
			"role_qiao": {
				"now_node": "square",
				"visible_node_ids": ["square", "river", "workshop", "cafe"],
				"visible_edge_ids": ["edge_square_river", "edge_river_workshop", "edge_workshop_cafe"],
				"carried_fragment_ids": ["fragment_river_mark"],
				"receipt_ids": ["receipt_qiao_bell", "receipt_qiao_river"],
				"open_request_ids": ["request_river_witness"],
				"route_hint": ["square", "river"],
				"clock": {"day": 2, "watch": 5, "tick": 3},
				"status": "blocked",
			},
		},
	}
