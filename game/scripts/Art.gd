extends Node
## Art.gd — autoload "Art"：主题/调色板/像素资产解析（范式同《小鱼岛》Art.gd）。
## 资产三级回退（M5 接入）：pro/<f>.png > <f>.png > <f>.svg + assets/art/manifest.json，零代码替换。

const TILE := 48

## ── D6：本文件曾持有 7 个硬编码色值，其中 6 个是死代码 ───────────────────────
## `area_palette`(5) + `grid_line`(1) + `area_color()`：**全仓零调用**
## （`grep -rn 'area_color\|grid_line\|area_palette'` 除本文件自身外零命中，实测 2026-07-28）。
## docs/44 §三 的缺口表把「分区叠色 area_palette + ground + grid_line = 7」列成
## 「40 色覆盖不到的一组」——**实际上它不需要被覆盖，它需要被删掉**。
## 最后一个活着的 `ground` 只在「缺 grass_a.png 切片时铺满地图」这一条兜底路径上被读
## （`WorldView.gd:_draw_body`），而它是一个**深蓝灰** `#22232f`——给"地面"兜底却兜出一块夜空色。
## 已改为由 `WorldView.GRASS_FALLBACK` 兜底（同一文件、同一族），于是 Art.gd 不再持有任何色值：
## 调色板只有一个家。

var _font: Font = null
## 加载自带中文字体（运行时直接喂字节，绕过「项目未导入则无 .ttf 资源」的 headless 坑）。
## 缺字体时回退 ThemeDB（中文会变豆腐块，仅占位）。
func font() -> Font:
	if _font != null:
		return _font
	var path := "res://assets/fonts/smiley-sans.ttf"   # 得意黑 Smiley Sans（OFL-1.1，可嵌入再发行；换掉无授权的 SimHei）
	if ResourceLoader.exists(path):                 # 导入的 FontFile：导出 PCK 里裸 .ttf 被剥离，只剩它；load() 走 .import 重映射取到
		_font = load(path) as Font
	elif FileAccess.file_exists(path):              # 未导入的裸 .ttf（编辑器/未导入工程）
		var f := FontFile.new()
		f.data = FileAccess.get_file_as_bytes(path)
		_font = f
	if _font == null:
		_font = ThemeDB.fallback_font               # 都没有 → 豆腐块占位
	_install_fallbacks()
	return _font

## 字体回退链：得意黑是【中文显示体】，没有 emoji、也不保证覆盖生僻拉丁/符号——不挂回退时这些字直接画成豆腐块
## （截图里的 🤝/🤖/💾 就是这么来的）。挂上引擎自带 fallback_font 后，缺字自动向下找，不用换字体、不新增资源。
func _install_fallbacks() -> void:
	if not (_font is FontFile):
		return                                      # ThemeDB.fallback_font 本身是共享资源，别往它身上挂（会自指）
	var ff := _font as FontFile
	if not ff.fallbacks.is_empty():
		return                                      # 已挂过
	var fb := ThemeDB.fallback_font
	if fb == null or fb == _font:
		return
	var chain: Array[Font] = [fb]
	ff.fallbacks = chain

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
	if ResourceLoader.exists(path):                 # 导入的 .ctex：导出 PCK 里裸 png 被剥离、只剩它；load() 走 .import 重映射取到（编辑器同理）
		t = load(path) as Texture2D
	elif FileAccess.file_exists(path):              # 未导入的裸 png（pro/ 运行时覆盖等）→ 直接解码
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
	# 三级回退：pro/ 覆盖 > 自带 png（tex() 内部判存在，缺则返回 null）
	var pro := tex("res://assets/art/pro/%s.png" % sprite_name)
	return pro if pro != null else tex(CHAR_DIR + sprite_name + ".png")

## 社交事件 emote 图标（greet/give/gossip/invite/meet_fulfilled/meet_broken/conflict/confront/apologize_ok/apologize_no）
func emote_tex(event_key: String) -> Texture2D:
	return tex("res://assets/art/emote/%s.png" % event_key)

## 物件精灵（slot 取自 `WorldView.OBJ_SLOT_BY_TYPE`——数据的 `type` 字段，**不是** id 前缀；
## H3 2026-07-30 把那条隐式约定换成了显式表）；缺则 null → 渲染层走醒目占位（不再静默兜底）。
func object_tex(slot: String) -> Texture2D:
	var pro := tex("res://assets/art/pro/obj_%s.png" % slot)
	return pro if pro != null else tex("res://assets/art/obj/%s.png" % slot)

## 地形/装饰瓦片（来自 overworld tileset 切片，视觉大改用）。缺则 null。
func terrain_tex(name: String) -> Texture2D:
	return tex("res://assets/art/terrain/%s.png" % name)

func decor_tex(name: String) -> Texture2D:
	return tex("res://assets/art/decor/%s.png" % name)

## ── I2 2026-07-30：`building_tex()` 与 `assets/art/building/{house,hut,shop}.png` 已删除 ────────
## 它不是"还没接线"，是**接过线、又被当成 bug 拆掉的**。拆它的是 `841d4c4`（2026-07-15），
## 那条 commit 把它列为用户报的「比例失调」的**头号成因**，原话：
##   "a decorative 1-tile `hut` icon was drawn at each area corner (hut.png is 16x16 -> 48px =
##    exactly ONE tile), i.e. a whole house the size of a person. ... Removed the hut lie and
##    made rooms render as actual buildings"
## 替代品今天在出货：`WorldView._draw_facades / _draw_building_dressing / _draw_sign` 把每个 district
## 画成有屋檐、山墙、窗（夜里分点灯/熄灯两档）、烟囱、分类型招牌的**真建筑**——而且**按 4 种 type 各画一款**，
## 严格宽于"每个角落同一张 hut"。docs/09 §1 那句承诺同批删掉。
## ⚠️ 想再加建筑贴图的人请先读 `841d4c4`：1 格贴图 = 1 格居民，这是尺度谎言，不是素材问题。
