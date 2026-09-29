extends RefCounted
## Authored circulation and PixelLab material kit. Navigation lives in map.json;
## coastal_plan.json is the checked surface/entrance projection of that map.
const TILE := 48.0
const DIR := "res://assets/art/coastal/"
var data: Dictionary = {}
var surface_cells: Dictionary = {}
var _textures: Dictionary = {}
var _regions: Dictionary = {}
var _polygons: Dictionary = {}
var _projection_extents: Dictionary = {}
var lamps: Array[Vector2] = []

func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/coastal_plan.json"))
	if parsed is Dictionary: data = parsed
	for material in data.get("surfaces", {}):
		for raw in data.surfaces[material]:
			surface_cells[Vector2i(int(raw[0]), int(raw[1]))] = String(material)
	for cell: Vector2i in surface_cells:
		_polygons[cell] = _cell_polygon(cell)
		if String(surface_cells[cell]) == "paving" and (cell.x * 7 + cell.y * 13) % 29 == 0:
			if not surface_cells.has(cell + Vector2i.LEFT):
				lamps.append((Vector2(cell) + Vector2(0.18, 0.75)) * TILE)

func texture(name: String) -> Texture2D:
	if not _textures.has(name):
		var file := name
		if name in ["terrace_east", "theater", "workshop_south"]: file = "typologies"
		if name == "terrace_south": file = "row_front_aligned"
		if name == "terrace_north": file = "row_rear_aligned"
		if name == "library": file = "library_aligned"
		if name == "bathhouse_north": file = "bathhouse_aligned"
		if name == "shop": file = "shop_aligned"
		if name.begins_with("flower_"): file = "flowerbeds"
		_textures[name] = Art.tex("res://assets/art/houses/" + name.trim_prefix("house:") + ".png" if name.begins_with("house:") else DIR + file + ".png")
	return _textures[name]

func region(name: String) -> Rect2:
	if not _regions.has(name):
		var tex := texture(name)
		if tex == null: return Rect2()
		var img := tex.get_image()
		if img.is_compressed(): img.decompress()
		var cell := Rect2i(0, 0, img.get_width(), img.get_height())
		if name == "terrace_east": cell = Rect2i(485, 0, 203, 199)
		elif name == "theater": cell = Rect2i(230, 200, 243, 184)
		elif name == "workshop_south": cell = Rect2i(478, 200, 210, 184)
		elif name.begins_with("flower_"):
			var index := int(name.trim_prefix("flower_"))
			cell = [Rect2i(0,0,187,185), Rect2i(190,0,153,185), Rect2i(345,0,167,185), Rect2i(0,185,260,170), Rect2i(290,185,222,165), Rect2i(253,350,259,162)][index]
		var used := img.get_region(cell).get_used_rect()
		_regions[name] = Rect2(used.position + cell.position, used.size)
	return _regions[name]

func _cell_polygon(cell: Vector2i) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var origin := Vector2(cell) * TILE
	var corners := [Vector2(0, 0), Vector2(TILE, 0), Vector2(TILE, TILE), Vector2(0, TILE)]
	var sides := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for i in 4:
		var corner: Vector2 = corners[i]
		if not surface_cells.has(cell + sides[i]) and not surface_cells.has(cell + sides[(i + 3) % 4]):
			var center := corner + Vector2(8.0 if i in [0,3] else -8.0, 8.0 if i < 2 else -8.0)
			for k in 5:
				var angle := PI + i * PI * 0.5 + k * PI * 0.125
				pts.append(origin + center + Vector2(cos(angle), sin(angle)) * 8.0)
		else: pts.append(origin + corner)
	return pts

func draw_meadow(c: CanvasItem, vis: Rect2, size: Vector2, season: Color) -> void:
	var tex := texture("meadow")
	if tex == null: return
	var bounds := vis.intersection(Rect2(Vector2.ZERO, size))
	for y in range(int(floor(bounds.position.y / 256.0)), int(ceil(bounds.end.y / 256.0))):
		for x in range(int(floor(bounds.position.x / 256.0)), int(ceil(bounds.end.x / 256.0))):
			var r := Rect2(x * 256, y * 256, 256, 256).intersection(Rect2(Vector2.ZERO, size))
			c.draw_texture_rect_region(tex, r, Rect2(Vector2.ZERO, r.size), season)
	# A restrained coastal colour wash keeps fine grass grain from competing with architecture.
	c.draw_rect(bounds, Color(Color("#8e9e78") * season, 0.40))

func draw_surfaces(c: CanvasItem, vis: Rect2) -> void:
	for material in ["paving", "gravel", "asphalt"]:
		var tex := texture("asphalt" if material == "asphalt" else "paving")
		if tex == null: continue
		var tint := Color("#d3c7a6") if material == "gravel" else Color.WHITE
		for raw in data.get("surfaces", {}).get(material, []):
			var cell := Vector2i(int(raw[0]), int(raw[1]))
			var r := Rect2(Vector2(cell) * TILE, Vector2.ONE * TILE)
			if not vis.intersects(r): continue
			var pts: PackedVector2Array = _polygons[cell]
			var uv := PackedVector2Array()
			# Each five-cell patch covers one source texture. UVs stay inside [0,1]
			# so later CanvasItem repeat-state changes cannot clamp the whole road.
			var patch := Vector2(posmod(cell.x, 5), posmod(cell.y, 5)) * 0.2
			for p in pts: uv.append(patch + (p - r.position) / 240.0)
			c.draw_polygon(pts, PackedColorArray([tint]), uv, tex)
			# Continuous pale kerbs and recessed gutters delineate the roadway.
			for side in 4:
				var d: Vector2i = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT][side]
				var neighbor := String(surface_cells.get(cell + d, ""))
				if neighbor == material or (material != "asphalt" and neighbor != ""): continue
				var a := r.position
				var b := a + Vector2(TILE, 0)
				if side == 1: a = Vector2(r.end.x, r.position.y); b = r.end
				elif side == 2: a = Vector2(r.position.x, r.end.y); b = r.end
				elif side == 3: b = Vector2(r.position.x, r.end.y)
				c.draw_line(a, b, Color("#e1dac6") if material == "asphalt" else Color("#92947b"), 2.0)
	# Circular stone inlays echo the reference's linked civic squares.
	for center in [Vector2(28.5,21), Vector2(35.5,21), Vector2(28.5,27), Vector2(35.5,27), Vector2(33,33.5)]:
		var p: Vector2 = center * TILE
		if not vis.has_point(p): continue
		c.draw_arc(p, 23, 0, TAU, 48, Color("#a7a99c"), 7, true)
		c.draw_arc(p, 16, 0, TAU, 48, Color("#eee6d4"), 2, true)

func draw_pad(c: CanvasItem, r: Rect2) -> void:
	var tex := texture("paving")
	if tex == null: return
	for y in range(int(r.position.y / TILE), int(r.end.y / TILE)):
		for x in range(int(r.position.x / TILE), int(r.end.x / TILE)):
			c.draw_texture_rect_region(tex, Rect2(x * TILE, y * TILE, TILE, TILE), Rect2(posmod(x, 5) * 48, posmod(y, 5) * 48, 48, 48), Color("#d1d0bb"))
	c.draw_rect(r.grow(-2), Color("#a6ab96"), false, 3)

func sprite(c: CanvasItem, name: String, foot: Vector2, width: float, max_height: float, tint := Color.WHITE, shadow := true) -> Rect2:
	var tex := texture(name)
	if tex == null: return Rect2()
	var src := region(name)
	var scale := minf(width / src.size.x, max_height / src.size.y)
	var sz := src.size * scale
	var r := Rect2(foot - Vector2(sz.x * 0.5, sz.y), sz)
	if shadow:
		# Project the alpha silhouette toward the southeast. Same sun for every asset.
		c.draw_set_transform_matrix(Transform2D(Vector2(1, 0.0), Vector2(-0.60, 0.28), foot))
		c.draw_texture_rect_region(tex, Rect2(-sz.x * 0.5, -sz.y, sz.x, sz.y), src, Color(0.17, 0.20, 0.22, 0.24))
		c.draw_set_transform_matrix(Transform2D.IDENTITY)
	c.draw_texture_rect_region(tex, r, src, tint)
	return r

# Source-frontage slopes are rectified as a projection, never by rotating the
# whole bitmap (which tips vertical walls and reverses the roof perspective).
const FRONTAGE_SLOPE := {"block": 0.22, "civic": 0.22, "market": 0.22,
	"workshop_north": 0.40, "workshop_south": 0.38}

func building_geometry(name: String, r: Rect2, facing: String) -> Dictionary:
	var asset := name
	if name.begins_with("terrace_"):
		asset = "terrace_north" if facing == "north" else "terrace_south"
	var src := region(asset)
	var tex := texture(asset)
	if tex == null or src.size.x <= 0 or src.size.y <= 0: return {}
	if asset in ["terrace_north", "terrace_south"]:
		# Use actual facade bays in narrow plots, rather than squeezing four houses.
		var bays := clampi(int(round(r.size.x / (TILE * 1.6))), 1, 4)
		src.size.x *= float(bays) / 4.0
	var slope := float(FRONTAGE_SLOPE.get(asset, 0.0))
	var corners := PackedVector2Array([Vector2.ZERO, Vector2(src.size.x, 0), src.size, Vector2(0, src.size.y)])
	var span := Vector2(0, src.size.y)
	if slope != 0.0:
		if not _projection_extents.has(asset):
			var img := tex.get_image()
			if img.is_compressed(): img.decompress()
			var low := INF
			var high := -INF
			for y in range(int(src.size.y)):
				for x in range(int(src.size.x)):
					if img.get_pixel(int(src.position.x)+x, int(src.position.y)+y).a <= 0.0: continue
					var py := float(y) - slope * x
					low = minf(low, py)
					high = maxf(high, py + 1.0)
			_projection_extents[asset] = Vector2(low, high)
		span = _projection_extents[asset]
	var min_y := span.x
	var extent := Vector2(src.size.x, span.y - span.x)
	var size := extent * minf(r.size.x / extent.x, r.size.y / extent.y)
	if asset.begins_with("terrace_"): size.x = r.size.x
	# Match the blueprint footprint instead of leaving wide empty side lots.
	# The facade always stays upright; the source perspective is flattened in Y.
	var origin := Vector2(r.get_center().x-size.x*0.5, r.end.y - size.y)
	if facing == "north": origin.y = r.position.y
	elif facing == "east": origin.x = r.end.x - size.x
	var pts := PackedVector2Array()
	var uv := PackedVector2Array()
	for p in corners:
		pts.append(origin + Vector2(p.x / extent.x, (p.y - slope * p.x - min_y) / extent.y) * size)
		uv.append((src.position + p) / Vector2(tex.get_size()))
	var backing: Array = []
	if asset in ["terrace_north", "terrace_south"]:
		# PixelLab supplied rear windows/roof with transparent plaster. Restore the
		# four opaque wall planes below those details, not the exterior background.
		var planes := [Rect2(24,134,161,227), Rect2(185,136,158,224), Rect2(343,134,162,226), Rect2(505,134,158,227)] if asset == "terrace_north" else [Rect2(49,84,149,286), Rect2(198,84,148,286), Rect2(346,84,150,286), Rect2(496,84,144,286)]
		for raw: Rect2 in planes:
			var face: Rect2 = raw.intersection(src)
			if not face.has_area(): continue
			backing.append(Rect2(origin + (face.position-src.position)/src.size*size, face.size/src.size*size))
	return {"asset": asset, "points": pts, "uv": uv, "bounds": Rect2(origin, size), "slope": slope, "backing": backing}

func building(c: CanvasItem, name: String, r: Rect2, facing := "south") -> void:
	var geo := building_geometry(name, r, facing)
	if geo.is_empty(): return
	var tex := texture(String(geo.asset))
	var pts: PackedVector2Array = geo.points
	var shade := PackedVector2Array()
	for p in pts: shade.append(p + Vector2(13, 9))
	for face: Rect2 in geo.backing:
		c.draw_rect(Rect2(face.position + Vector2(13,9), face.size), Color(0.17,0.20,0.22,0.23))
	c.draw_polygon(shade, PackedColorArray([Color(0.17,0.20,0.22,0.23)]), geo.uv, tex)
	var palette := [Color("#d5c7a8"), Color("#c2c7b3"), Color("#d2b9ab"), Color("#e0d8c5")]
	for i in geo.backing.size(): c.draw_rect(geo.backing[i], palette[i % palette.size()])
	c.draw_polygon(pts, PackedColorArray([Color.WHITE]), geo.uv, tex)

func draw_landscape(c: CanvasItem, vis: Rect2, trees: Array, season: Color) -> void:
	for bed in data.get("flowerbeds", []):
		var p := (Vector2(float(bed.pos[0]), float(bed.pos[1])) + Vector2(0.5, 0.85)) * TILE
		if vis.grow(70).has_point(p):
			sprite(c, "flower_" + str(int(bed.variant)), p, 45.0, 42.0, season, false)
	for raw in trees:
		var p := (Vector2(float(raw[0]), float(raw[1])) + Vector2(0.5, 1.0)) * TILE
		if vis.grow(150).has_point(p):
			sprite(c, "tree", p, 128.0, 146.0, season)
	for raw in data.get("planting", []):
		var p := (Vector2(float(raw[0]), float(raw[1])) + Vector2(0.5, 1.0)) * TILE
		if vis.grow(130).has_point(p): sprite(c, "garden", p, 126.0, 76.0, season)
	for passage in data.get("passages", []):
		var p := Vector2(float(passage.pos[0]) + float(passage.footprint[0]) * 0.5, float(passage.pos[1]) + float(passage.footprint[1])) * TILE
		if vis.grow(200).has_point(p): sprite(c, "passage", p, float(passage.footprint[0]) * TILE, 180.0)
	for p in lamps:
		if not vis.grow(50).has_point(p): continue
		c.draw_line(p, p + Vector2(18, 6), Color(0.17, 0.19, 0.16, 0.25), 3)
		c.draw_line(p, p - Vector2(0, 27), Color("#59655d"), 2.5)
		c.draw_rect(Rect2(p - Vector2(5, 32), Vector2(10, 8)), Color("#526159"))
		c.draw_rect(Rect2(p - Vector2(3, 30), Vector2(6, 5)), Color("#f0dab0"))
