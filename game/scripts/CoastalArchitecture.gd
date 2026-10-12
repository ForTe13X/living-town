extends RefCounted
## Reference-led exterior kit. All geometry stays inside the authored footprint.
## Uses CanvasItem drawing so roofs, windows and arcades remain crisp at any zoom.

static func volume(c: CanvasItem, r: Rect2, seed: int, shop := false, night := 0.0) -> void:
	if r.size.x < 8.0 or r.size.y < 8.0: return
	var wall := Color(["#eee8d7", "#e0d6ba", "#f5efdf", "#d4c8a9"][posmod(seed, 4)])
	var tile := Color(["#b87550", "#c1835a", "#aa6549", "#cc8b60"][posmod(seed, 4)])
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var roof_h := h * 0.40
	var eave := y + roof_h
	var side := minf(12.0, w * 0.09)
	c.draw_rect(Rect2(x + 5, y + 8, w, h), Color(0.17, 0.20, 0.16, 0.20))
	c.draw_rect(Rect2(x, eave, w, h - roof_h), wall)
	c.draw_rect(Rect2(r.end.x - side, eave, side, h - roof_h), wall.darkened(0.18))
	c.draw_rect(Rect2(x, r.end.y - 6, w, 6), Color("#b7ae97"))
	var floors := 2 if h < 170.0 else 3
	var spacing := (h - roof_h - 12.0) / float(floors)
	var cols := maxi(2, int(w / 27.0))
	var step := (w - side) / float(cols)
	for floor_i in floors:
		var wy := eave + 10.0 + spacing * floor_i
		c.draw_line(Vector2(x, wy - 4), Vector2(r.end.x - side, wy - 4), wall.lightened(0.18), 2)
		for col in cols:
			var wx := x + step * (col + 0.5)
			var wh := maxf(7.0, spacing * 0.53)
			var ww := minf(10.0, step * 0.34)
			var glass := Color("#364d50").lerp(Color("#edc982"), night * (0.7 if (col + seed + floor_i) % 3 else 0.0))
			if shop and floor_i == floors - 1:
				ww = minf(15.0, step * 0.60)
				c.draw_circle(Vector2(wx, wy + 4), ww * 0.5, Color("#716c5e"))
			c.draw_rect(Rect2(wx - ww * 0.5 - 2, wy - 2, ww + 4, wh + 4), wall.lightened(0.14))
			c.draw_rect(Rect2(wx - ww * 0.5, wy, ww, wh), glass)
			c.draw_line(Vector2(wx, wy), Vector2(wx, wy + wh), Color("#c7c8b7"), 1)
			if not shop or floor_i < floors - 1:
				for s in [-1.0, 1.0]:
					c.draw_rect(Rect2(wx + s * (ww * 0.5 + 3) - 1.5, wy, 3, wh), Color("#738071"))
			if floor_i == 0 and col % 2 == 0:
				c.draw_rect(Rect2(wx - ww, wy + wh - 2, ww * 2, 5), Color("#77766a"), false, 1)
				for rail in 4:
					c.draw_line(Vector2(wx - ww + rail * ww * 0.66, wy + wh - 2), Vector2(wx - ww + rail * ww * 0.66, wy + wh + 3), Color("#666c62"), 1)
	# A recessed entrance keeps the ground-floor street front legible.
	var door_w := minf(14.0, w * 0.15)
	c.draw_rect(Rect2(x + w * 0.5 - door_w * 0.5, r.end.y - spacing * 0.67, door_w, spacing * 0.67), Color("#525d55"))
	c.draw_rect(Rect2(x + w * 0.5 - door_w, r.end.y - 2, door_w * 2, 3), Color("#dfd9c8"))
	# Hipped roof: continuous long ridges, lighter north slope, dark end hips.
	var hip := minf(w * 0.19, roof_h * 0.7)
	var ridge_y := y + roof_h * 0.27
	c.draw_colored_polygon(PackedVector2Array([Vector2(x, y + roof_h), Vector2(x + hip, ridge_y), Vector2(r.end.x - hip, ridge_y), Vector2(r.end.x, eave)]), tile)
	c.draw_colored_polygon(PackedVector2Array([Vector2(x, y), Vector2(r.end.x, y), Vector2(r.end.x - hip, ridge_y), Vector2(x + hip, ridge_y)]), tile.lightened(0.17))
	c.draw_colored_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + hip, ridge_y), Vector2(x, eave)]), tile.lightened(0.04))
	c.draw_colored_polygon(PackedVector2Array([Vector2(r.end.x, y), Vector2(r.end.x, eave), Vector2(r.end.x - hip, ridge_y)]), tile.darkened(0.18))
	for row in range(1, int(roof_h / 5.0)):
		var yy := y + row * 5.0
		c.draw_line(Vector2(x + 2, yy), Vector2(r.end.x - 2, yy), Color(tile.darkened(0.24), 0.28), 1)
	for col in range(1, int(w / 6.0)):
		var xx := x + col * 6.0
		c.draw_line(Vector2(xx, ridge_y + 3), Vector2(xx, eave - 2), Color(tile.lightened(0.4), 0.24), 1)
	c.draw_line(Vector2(x + hip, ridge_y), Vector2(r.end.x - hip, ridge_y), tile.lightened(0.35), 3)
	c.draw_line(Vector2(x, eave), Vector2(r.end.x, eave), Color("#f0e7d3"), 3)
	c.draw_line(Vector2(x, eave + 3), Vector2(r.end.x, eave + 3), Color(0.2, 0.18, 0.15, 0.28), 2)
	for cx in [x + w * 0.20, x + w * 0.78]:
		c.draw_rect(Rect2(cx, y + 2, 7, roof_h * 0.35), wall)
		c.draw_rect(Rect2(cx - 1, y, 9, 3), Color("#f6f0df"))
	if shop:
		var ay := r.end.y - spacing * 0.83
		c.draw_rect(Rect2(x + 3, ay, w - side - 6, 6), Color("#74867e"))
		for stripe in range(int((w - side - 6) / 10.0)):
			c.draw_rect(Rect2(x + 3 + stripe * 10, ay, 4, 6), Color("#e8ddbf"))

static func block(c: CanvasItem, r: Rect2, seed: int, shop: bool, night: float) -> void:
	var wing := minf(r.size.x * 0.23, 86.0)
	var rear := r.size.y * 0.31
	var front := r.size.y * 0.35
	c.draw_rect(r, Color("#d0c6ae"))
	var court := Rect2(r.position + Vector2(wing, rear), r.size - Vector2(wing * 2, rear + front))
	c.draw_rect(court.grow(-5), Color("#a2ae7d"))
	c.draw_line(Vector2(court.get_center().x, court.position.y), Vector2(court.get_center().x, r.end.y), Color("#e4dbc5"), 13)
	volume(c, Rect2(r.position, Vector2(r.size.x, rear)), seed, false, night)
	volume(c, Rect2(r.position + Vector2(0, rear * 0.72), Vector2(wing, r.size.y - rear * 0.72)), seed + 1, shop, night)
	volume(c, Rect2(r.end.x - wing, r.position.y + rear * 0.72, wing, r.size.y - rear * 0.72), seed + 2, shop, night)
	for px in [court.position.x + 12, court.end.x - 12]:
		var p := Vector2(px, court.get_center().y)
		c.draw_circle(p + Vector2(3, 4), 11, Color(0.2, 0.25, 0.18, 0.2))
		c.draw_circle(p, 10, Color("#728766"))
		c.draw_circle(p - Vector2(3, 3), 7, Color("#aab68a"))
	# Two street wings leave a visible central passage to the courtyard.
	var half := r.size.x * 0.5 - 12
	volume(c, Rect2(r.position.x, r.end.y - front, half, front), seed, shop, night)
	volume(c, Rect2(r.get_center().x + 12, r.end.y - front, half, front), seed + 1, shop, night)

static func landmark(c: CanvasItem, r: Rect2, kind: String, night: float) -> void:
	volume(c, r, 2, true, night)
	if kind == "chapel" or kind == "district_civic_facade":
		var tower := Rect2(r.position.x + r.size.x * 0.10, r.position.y, r.size.x * 0.24, r.size.y * 0.86)
		c.draw_rect(tower, Color("#f5eddb"))
		c.draw_rect(Rect2(tower.end.x - 5, tower.position.y, 5, tower.size.y), Color("#c7bea8"))
		c.draw_rect(Rect2(tower.position.x - 2, tower.position.y + 6, tower.size.x + 4, 4), Color("#d2c5ad"))
		var cp := tower.position + Vector2(tower.size.x * 0.5, tower.size.x * 0.8)
		c.draw_circle(cp, tower.size.x * 0.29, Color("#a5997d"))
		c.draw_circle(cp, tower.size.x * 0.23, Color("#fff3cf"))
		c.draw_line(cp, cp + Vector2(0, -5), Color("#596357"), 1.5)
		c.draw_line(cp, cp + Vector2(4, 2), Color("#596357"), 1.5)
	elif kind == "halles":
		var skylight := Rect2(r.position + Vector2(r.size.x * 0.16, 5), Vector2(r.size.x * 0.68, r.size.y * 0.14))
		c.draw_rect(skylight, Color("#869e9b"))
		for i in 9:
			var x := skylight.position.x + skylight.size.x * i / 8.0
			c.draw_line(Vector2(x, skylight.position.y), Vector2(x, skylight.end.y), Color("#d7dbce"), 2)
