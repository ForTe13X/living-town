class_name NarrativeGlyphs
extends RefCounted
## Code-native marks for the narrative maze.  The marks use only filled shapes
## and strokes so they remain legible without an icon font or bitmap asset.

const FRAGMENT := "fragment"
const RECEIPT := "receipt"
const REQUEST := "request"
const BLOCKED := "blocked"
const TRAVERSED := "traversed"
const UNKNOWN := "unknown"

const KINDS := [FRAGMENT, RECEIPT, REQUEST, BLOCKED, TRAVERSED, UNKNOWN]


static func draw_glyph(canvas: CanvasItem, kind: String, bounds: Rect2, ink := Color("e6d6ad"), accent := Color("d88b57")) -> void:
	var side := minf(bounds.size.x, bounds.size.y)
	var origin := bounds.position + (bounds.size - Vector2(side, side)) * 0.5
	var unit := side / 16.0
	var line := maxf(1.0, floorf(unit * 1.35))
	var r := Rect2(origin, Vector2(side, side))
	match kind:
		FRAGMENT:
			_fragment(canvas, r, unit, line, ink, accent)
		RECEIPT:
			_receipt(canvas, r, unit, line, ink, accent)
		REQUEST:
			_request(canvas, r, unit, line, ink, accent)
		BLOCKED:
			_blocked(canvas, r, unit, line, ink, accent)
		TRAVERSED:
			_traversed(canvas, r, unit, line, ink, accent)
		_:
			_unknown(canvas, r, unit, line, ink, accent)


static func _fragment(canvas: CanvasItem, r: Rect2, u: float, line: float, ink: Color, accent: Color) -> void:
	var p := r.position
	var shard_a := PackedVector2Array([
		p + Vector2(3, 3) * u,
		p + Vector2(8, 2) * u,
		p + Vector2(6, 8) * u,
		p + Vector2(2, 11) * u,
	])
	var shard_b := PackedVector2Array([
		p + Vector2(9, 4) * u,
		p + Vector2(14, 6) * u,
		p + Vector2(12, 13) * u,
		p + Vector2(7, 10) * u,
	])
	canvas.draw_colored_polygon(shard_a, ink)
	canvas.draw_colored_polygon(shard_b, accent)
	canvas.draw_polyline(PackedVector2Array([p + Vector2(8, 2) * u, p + Vector2(6, 8) * u, p + Vector2(7, 10) * u]), Color("342f35"), line, false)


static func _receipt(canvas: CanvasItem, r: Rect2, u: float, line: float, ink: Color, accent: Color) -> void:
	var p := r.position
	var paper := PackedVector2Array([
		p + Vector2(3, 2) * u,
		p + Vector2(13, 2) * u,
		p + Vector2(13, 14) * u,
		p + Vector2(11, 12) * u,
		p + Vector2(9, 14) * u,
		p + Vector2(7, 12) * u,
		p + Vector2(5, 14) * u,
		p + Vector2(3, 12) * u,
	])
	canvas.draw_colored_polygon(paper, ink)
	canvas.draw_line(p + Vector2(5, 6) * u, p + Vector2(11, 6) * u, accent, line, false)
	canvas.draw_line(p + Vector2(5, 9) * u, p + Vector2(10, 9) * u, accent, line, false)


static func _request(canvas: CanvasItem, r: Rect2, u: float, line: float, ink: Color, accent: Color) -> void:
	var p := r.position
	canvas.draw_circle(p + Vector2(8, 6) * u, 4.5 * u, ink)
	canvas.draw_colored_polygon(PackedVector2Array([
		p + Vector2(5, 9) * u,
		p + Vector2(4, 13) * u,
		p + Vector2(8, 10) * u,
	]), ink)
	canvas.draw_line(p + Vector2(6.5, 5) * u, p + Vector2(8, 3.8) * u, accent, line, false)
	canvas.draw_line(p + Vector2(8, 3.8) * u, p + Vector2(10, 5.2) * u, accent, line, false)
	canvas.draw_line(p + Vector2(10, 5.2) * u, p + Vector2(8, 7.5) * u, accent, line, false)
	canvas.draw_circle(p + Vector2(8, 9) * u, maxf(1.0, 0.75 * u), accent)


static func _blocked(canvas: CanvasItem, r: Rect2, u: float, line: float, ink: Color, accent: Color) -> void:
	var p := r.position
	var c := p + Vector2(8, 8) * u
	canvas.draw_circle(c, 5.5 * u, Color(accent, 0.24))
	canvas.draw_circle(c, 5.5 * u, accent, false, line, false)
	canvas.draw_line(p + Vector2(4, 12) * u, p + Vector2(12, 4) * u, ink, line * 1.45, false)


static func _traversed(canvas: CanvasItem, r: Rect2, u: float, line: float, ink: Color, accent: Color) -> void:
	var p := r.position
	canvas.draw_circle(p + Vector2(3, 12) * u, 1.6 * u, ink)
	canvas.draw_line(p + Vector2(4.2, 10.8) * u, p + Vector2(10.5, 4.5) * u, accent, line * 1.35, false)
	canvas.draw_colored_polygon(PackedVector2Array([
		p + Vector2(9, 3) * u,
		p + Vector2(14, 2) * u,
		p + Vector2(13, 7) * u,
	]), ink)


static func _unknown(canvas: CanvasItem, r: Rect2, u: float, line: float, ink: Color, accent: Color) -> void:
	var p := r.position
	var c := p + Vector2(8, 8) * u
	var diamond := PackedVector2Array([
		p + Vector2(8, 2) * u,
		p + Vector2(14, 8) * u,
		p + Vector2(8, 14) * u,
		p + Vector2(2, 8) * u,
		p + Vector2(8, 2) * u,
	])
	canvas.draw_polyline(diamond, ink, line, false)
	canvas.draw_circle(c, 1.8 * u, accent)
