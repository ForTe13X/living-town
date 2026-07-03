extends Node
## Art.gd — autoload "Art"：主题/调色板/像素资产解析（范式同《小鱼岛》Art.gd）。
## 资产三级回退（M5 接入）：pro/<f>.png > <f>.png > <f>.svg + assets/art/manifest.json，零代码替换。

const TILE := 48

var area_palette := {
	"home":  Color("#3a4663"),
	"cafe":  Color("#5a4636"),
	"plaza": Color("#3a5a44"),
	"wash":  Color("#36505a"),
	"work":  Color("#4a4636"),
}
var ground := Color("#22232f")
var grid_line := Color("#2c2e3c")

func area_color(area: String) -> Color:
	return area_palette.get(area, ground)

var _font: Font = null
## 加载自带中文字体（运行时直接喂字节，绕过「项目未导入则无 .ttf 资源」的 headless 坑）。
## 缺字体时回退 ThemeDB（中文会变豆腐块，仅占位）。
func font() -> Font:
	if _font != null:
		return _font
	var path := "res://assets/fonts/cjk.ttf"
	if FileAccess.file_exists(path):
		var f := FontFile.new()
		f.data = FileAccess.get_file_as_bytes(path)
		_font = f
	else:
		_font = ThemeDB.fallback_font
	return _font

## ── CC0 像素资产（Puny World / Puny Characters，见 assets/art/library/*/LICENSE.txt）──
## 运行时直接解码 PNG（项目未导入也能用，同字体加载思路）。三级回退留作后续 pro/ 覆盖。
const CHAR_DIR := "res://assets/art/library/puny-characters/Puny-Characters/"
const GRASS := CHAR_DIR + "Environment/Grass1.png"
const CHAR_FRAME := Vector2i(32, 32)   # 角色表帧尺寸；(0,0) 为正面站立帧

var _tex_cache := {}
func tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(path) == OK:
			t = ImageTexture.create_from_image(img)
	_tex_cache[path] = t
	return t

func ground_tex() -> Texture2D:
	return tex(GRASS)

## 角色精灵（按 persona.sprite 名，如 "Mage-Red"）；渲染层取其 (0,0,32,32) 帧。
func agent_tex(sprite_name: String) -> Texture2D:
	if sprite_name == "":
		return null
	# 三级回退：pro/ 覆盖 > 自带 png
	var pro := "res://assets/art/pro/%s.png" % sprite_name
	if FileAccess.file_exists(pro):
		return tex(pro)
	return tex(CHAR_DIR + sprite_name + ".png")

## 社交事件 emote 图标（greet/give/gossip/invite/meet_fulfilled/meet_broken/conflict/confront/apologize_ok/apologize_no）
func emote_tex(event_key: String) -> Texture2D:
	var p := "res://assets/art/emote/%s.png" % event_key
	return tex(p) if FileAccess.file_exists(p) else null

## 物件精灵（slot 取自 object id 前缀，如 bench/bath/counter/desk/arcade）；缺则 null → 渲染层程序化兜底。
func object_tex(slot: String) -> Texture2D:
	var pro := "res://assets/art/pro/obj_%s.png" % slot
	if FileAccess.file_exists(pro):
		return tex(pro)
	var p := "res://assets/art/obj/%s.png" % slot
	return tex(p) if FileAccess.file_exists(p) else null

## 地形/装饰/建筑瓦片（来自 overworld tileset 切片，视觉大改用）。缺则 null。
func terrain_tex(name: String) -> Texture2D:
	var p := "res://assets/art/terrain/%s.png" % name
	return tex(p) if FileAccess.file_exists(p) else null

func decor_tex(name: String) -> Texture2D:
	var p := "res://assets/art/decor/%s.png" % name
	return tex(p) if FileAccess.file_exists(p) else null

func building_tex(name: String) -> Texture2D:
	var p := "res://assets/art/building/%s.png" % name
	return tex(p) if FileAccess.file_exists(p) else null
