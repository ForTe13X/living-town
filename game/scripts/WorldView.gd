extends Node2D
## WorldView.gd — 纯订阅者像素渲染（不持有权威状态，全部读 Sim）。
## 范式同《小鱼岛》GameScreen：监听 Sim 信号 → queue_redraw；占位用程序化色块，M5 换正式像素美术。
## M1 增量：把「看不见的社交戏剧」画出来——关系连线 / 对话连线 / 冲突⚡ / 约见标记 / 台词气泡。

const T := 48  # 与 Art.TILE 一致
const EMOTE_TICKS := 24  # 头顶 emote 显示时长

var _prev_pos := {}      # id -> Vector2i（推断朝向/行走）
var _emote := {}         # id -> {tex, until}
var _say := {}           # id -> {text, until}（对话罐头台词；M2 换 LLM 生成）
const SAY_TICKS := 40

# L6 调色板变体（docs/12）：扩 N 的克隆(id=npc_*)复用 6 张 CC0 精灵，用确定性色相旋转让每个各不相同
# → 视觉数量线性增长、零新增 PNG、零版权、完全可复现。命名 6 人(aria..fei)零位移保留正典外观；6 人小镇本层休眠。
# 实现：首次用到时把精灵 CPU 色相旋转成一张 ImageTexture 变体并缓存（Godot 4 immediate-mode 无法 per-draw 换 material）。
const HUE_BUCKETS := 24   # 色相分桶数（bucket0=原图）
var _hued := {}          # "sprite#bucket" -> ImageTexture（懒建缓存）

## 克隆按 id 取确定性色相变体；命名原型(非 npc_)或 bucket0 直接返回原图。绕 HSV 色相环旋转→保亮度=真换色，非压暗 modulate。
func _hued_tex(spr_name: String, id: String) -> Texture2D:
	var base := Art.agent_tex(spr_name)
	if base == null or not id.begins_with("npc_"):
		return base
	var bucket := absi(id.hash()) % HUE_BUCKETS
	if bucket == 0:
		return base
	var key := spr_name + "#" + str(bucket)
	if _hued.has(key):
		return _hued[key]
	var img := base.get_image()
	if img == null:
		return base
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	var shift := float(bucket) / float(HUE_BUCKETS)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.02:
				continue
			c.h = fmod(c.h + shift, 1.0)
			img.set_pixel(x, y, c)
	var t := ImageTexture.create_from_image(img)
	_hued[key] = t
	return t

# 罐头对话库（发起方 init / 接受方 yes / 拒绝方 no）；M2 由 LLM 按人设生成替换
const DIALOG := {
	"greet": {"init": ["嘿，最近怎么样？", "今天天气真好呀！", "好久不见！"], "yes": ["挺好的，你呢？", "正想找你聊聊～"], "no": ["现在有点忙…", "下次再聊吧。"]},
	"gossip": {"init": ["偷偷跟你说个事儿……", "你听说了吗？", "我跟你讲哦……"], "yes": ["真的假的？！", "快说快说～"], "no": ["这种话我不爱听。", "算了吧。"]},
	"give": {"init": ["这个送你～", "一点小心意，收下。"], "yes": ["谢谢你！", "太客气啦～"], "no": ["这我不能要…", "心领了。"]},
	"invite": {"init": ["回头一起去广场？", "改天约一个？"], "yes": ["好呀，说定了！", "行，到时见！"], "no": ["最近没空…", "下次吧。"]},
	"confront": {"init": ["咱们得谈谈。", "你这样让我很难受。"], "yes": ["……你说得对。", "我听着呢。"], "no": ["我不知道你在说什么。", "这跟我没关系。"]},
	"apologize": {"init": ["对不起，是我不好。", "上次的事，我道歉。"], "yes": ["……没事了。", "我原谅你。"], "no": ["我还没法释怀。", "给我点时间。"]},
	"meet": {"init": ["你来啦！", "等你好久～"], "yes": ["来咯～", "走，一起！"], "no": [], "fail": ["怎么没来呢…", "白等一场。"]},
	# S3 社交深化
	"confide": {"init": ["有件事…我只告诉你", "我心里藏着个秘密…"], "yes": ["我替你保密。", "尽管说，我听着～"], "no": []},
	"leak": {"init": ["其实啊，ta 跟我说过……", "偷偷告诉你个秘密哦……"], "yes": ["不会吧？！", "快讲快讲～"], "no": []},
	"betray": {"init": ["（一时口快说漏了嘴…）"], "yes": ["你怎么能这样！我信错人了！", "你竟把我的秘密说出去！"], "no": []},
	"endorse": {"init": ["ta 那种人，咱们看在眼里", "这事咱们口径一致"], "yes": ["没错，我也这么想。", "算我一个。"], "no": []},
	"rally_oust": {"init": ["大家都对你有意见！", "我们不欢迎这样的人。"], "yes": ["凭什么针对我…", "你们……"], "no": ["凭什么针对我…"]},
	"aid": {"init": ["别担心，有我呢～", "来，我帮你！"], "yes": ["太谢谢你了！", "有你真好。"], "no": []},
	"pact": {"init": ["以后咱们互相帮衬！", "结个伴吧～"], "yes": ["一言为定！", "好，说定了！"], "no": ["你总只索取，这盟约到头了。"]},
}

# 视觉大改：地面分层 + 装饰散布（切图前自动回退）
var _grass: Array = []   # 草地变体纹理（带权）
var _decor_items: Array = []  # [{tex, cell:Vector2i, h_tiles}]
var _decor_built := false
# P2-2 地形层：map.json 的 walls/water/trees（纯渲染；导航走 blockers 并集，与此无关）。start_new 时重建。
var _wall_set := {}      # idx(y*W+x) -> true（墙格，用于画石墙 + 装饰避让）
var _water_set := {}     # idx -> true（水格）
var _tree_cells: Array = []  # [Vector2i]（authored 阻挡树，替代程序化装饰树）
var _wall_type := {}     # P2-4 idx -> 建筑类型（住宅/商业/公共/工坊）→ 墙面按类型上色
var _terrain_built := false
var dbg_nav := false     # P2-4 导航开发叠层开关（Main 的 N 键切换）：阻挡格 + 交互格可视化
var _interiors := {}     # P3 室内内容 interiors.json：space -> floor -> {label,floor,furniture[]}
var _interiors_loaded := false
# P2-4 分类型建筑外观：墙面(face/top/foot 三段做体积)+屋檐(roof)+招牌图标，让"住宅/商业/公共/工坊"一眼可辨。
const BLD_PAL := {
	"residential": {"face": Color("#c2a071"), "top": Color("#d8bd93"), "foot": Color("#836a48"), "roof": Color("#a8443a"), "icon": Color("#c85a4e")},  # 暖木墙+红瓦顶
	"commercial":  {"face": Color("#8a6238"), "top": Color("#a67f4e"), "foot": Color("#5e4326"), "roof": Color("#b5484a"), "icon": Color("#efe4cc")},  # 棕木店面+红白条纹遮阳+咖啡招牌
	"public":      {"face": Color("#7c8a92"), "top": Color("#9fabb2"), "foot": Color("#556169"), "roof": Color("#5a86b0"), "icon": Color("#eaf3f8")},  # 灰蓝石+蓝瓦+♨蒸汽
	"workshop":    {"face": Color("#82868f"), "top": Color("#a0a4ac"), "foot": Color("#585c64"), "roof": Color("#3e4a5a"), "icon": Color("#cfcfcf")},  # 灰石+深蓝灰顶+烟囱黑烟
}

func _ready() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST  # 像素清晰，不糊
	_grass = [
		{"t": Art.terrain_tex("grass_a"), "w": 70},
		{"t": Art.terrain_tex("grass_b"), "w": 24},
		{"t": Art.terrain_tex("grass_flowers"), "w": 6},
	].filter(func(g): return g["t"] != null)
	Sim.ticked.connect(func(_t): queue_redraw())
	Sim.agent_changed.connect(func(_id): queue_redraw())
	Sim.social_event.connect(_on_social)

func _hash(x: int, y: int, salt: int) -> int:
	var h := (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	return absi(h)

## 在区域外的草地上确定性散布装饰（树/花/草丛…），让小镇不再空旷。切图缺失则跳过。
func _build_decor() -> void:
	_decor_built = true
	_decor_items.clear()
	var pool := []
	# 树不再散布：P2-2 的可见树 = authored 阻挡树（_tree_cells）。程序化装饰只留贴地花草石（可踩，纯装饰）。
	for nm in ["bush", "flower_red", "flower_yellow", "flower_white", "rock", "stump", "mushroom"]:
		var t := Art.decor_tex(nm)
		if t != null:
			var tall := 2 if nm == "tree_big" else 1
			var weight := 3 if nm.begins_with("tree") else (10 if nm.begins_with("flower") else 6)
			pool.append({"t": t, "h": tall, "w": weight})
	if pool.is_empty():
		return
	var total_w := 0
	for p in pool:
		total_w += int(p["w"])
	var w: int = int(Sim.world.get("width", 24))
	var h: int = int(Sim.world.get("height", 16))
	for y in range(h):
		for x in range(w):
			if _in_area(x, y) or _is_object(x, y) or _is_blocked(x, y):
				continue
			if _hash(x, y, 7) % 100 >= 22:   # ~22% 密度
				continue
			var r := _hash(x, y, 13) % total_w
			for p in pool:
				r -= int(p["w"])
				if r < 0:
					_decor_items.append({"tex": p["t"], "cell": Vector2i(x, y), "h": int(p["h"])})
					break

## 从 map.json 的 walls/water/trees 建渲染集合（纯渲染；导航仍走 Sim 的 blockers 并集）。世界重载即失效。
func _build_terrain() -> void:
	_terrain_built = true
	_wall_set.clear(); _water_set.clear(); _tree_cells.clear(); _wall_type.clear()
	var wd: int = int(Sim.world.get("width", 24))
	for c in Sim.world.get("walls", []):
		_wall_set[int(c[1]) * wd + int(c[0])] = true
	for c in Sim.world.get("water", []):
		_water_set[int(c[1]) * wd + int(c[0])] = true
	for c in Sim.world.get("trees", []):
		_tree_cells.append(Vector2i(int(c[0]), int(c[1])))
	# 给每个墙格标上所属建筑【类型】（住宅/商业/公共/工坊）→ 墙面按类型上色。用 area.rect 的边框判定归属。
	for aid in Sim.world.get("areas", {}):
		var a: Dictionary = Sim.world["areas"][aid]
		var typ := String(a.get("type", "workshop"))
		if typ == "plaza":
			continue
		var r: Array = a.get("rect", [0, 0, 0, 0])
		var x0 := int(r[0]); var y0 := int(r[1]); var bw := int(r[2]); var bh := int(r[3])
		for i in range(bw):
			_wall_type[(y0) * wd + (x0 + i)] = typ
			_wall_type[(y0 + bh - 1) * wd + (x0 + i)] = typ
		for j in range(bh):
			_wall_type[(y0 + j) * wd + x0] = typ
			_wall_type[(y0 + j) * wd + (x0 + bw - 1)] = typ

func _is_blocked(x: int, y: int) -> bool:
	if not _terrain_built:
		_build_terrain()
	var idx := y * int(Sim.world.get("width", 24)) + x
	if _wall_set.has(idx) or _water_set.has(idx):
		return true
	for c in _tree_cells:
		if c.x == x and c.y == y:
			return true
	return false

## P2-4：每栋（非广场）沿顶墙悬挑一条 roof 色屋檐 + 门顶挂类型招牌图标。不铺满屋顶（否则遮住室内家具/居民）。
func _draw_building_dressing(w: int) -> void:
	for aid in Sim.world.get("areas", {}):
		var a: Dictionary = Sim.world["areas"][aid]
		var typ := String(a.get("type", ""))
		if typ == "" or typ == "plaza":
			continue
		var pal: Dictionary = BLD_PAL.get(typ, BLD_PAL["workshop"])
		var r: Array = a.get("rect", [0, 0, 0, 0])
		var x0 := int(r[0]); var y0 := int(r[1]); var bw := int(r[2])
		var eave := Rect2(x0 * T - T * 0.12, y0 * T - T * 0.16, bw * T + T * 0.24, T * 0.46)  # 悬挑屋檐
		if typ == "commercial":                         # 商业：红白条纹遮阳篷（最醒目的类型信号）
			var stripe := eave.size.x / float(bw * 2)
			for s in range(bw * 2):
				var col: Color = pal["roof"] if s % 2 == 0 else pal["icon"]
				draw_rect(Rect2(eave.position.x + s * stripe, eave.position.y, stripe + 1.0, eave.size.y), col, true)
		else:
			draw_rect(eave, pal["roof"], true)
			draw_rect(Rect2(eave.position.x, eave.position.y, eave.size.x, T * 0.12), (pal["roof"] as Color).lightened(0.28), true)  # 脊线高光
		_draw_sign(typ, pal, (x0 + bw * 0.5) * T, y0 * T - T * 0.5)

func _draw_sign(typ: String, pal: Dictionary, cx: float, cy: float) -> void:
	match typ:
		"commercial":                                   # 咖啡杯 + 蒸汽
			draw_rect(Rect2(cx - T * 0.2, cy - T * 0.14, T * 0.34, T * 0.28), Color("#f4ecd6"), true)
			draw_rect(Rect2(cx - T * 0.2, cy - T * 0.14, T * 0.34, T * 0.07), Color("#7a4a2c"), true)
			draw_circle(Vector2(cx - T * 0.02, cy - T * 0.26), T * 0.045, Color(1, 1, 1, 0.55))
		"public":                                       # ♨ 蓝底温泉标（澡堂）：蓝圆盘 + 三缕上升蒸汽
			draw_circle(Vector2(cx, cy), T * 0.24, pal["roof"])
			draw_circle(Vector2(cx, cy), T * 0.24, (pal["roof"] as Color).lightened(0.3), false, 2.0)
			for k in range(3):
				draw_rect(Rect2(cx - T * 0.14 + k * T * 0.13, cy - T * 0.02, T * 0.05, T * 0.14), pal["icon"], true)
		"workshop":                                     # 烟囱 + 烟
			draw_rect(Rect2(cx - T * 0.1, cy - T * 0.12, T * 0.2, T * 0.34), Color("#4c3a28"), true)
			draw_circle(Vector2(cx, cy - T * 0.24), T * 0.09, Color(0.82, 0.82, 0.82, 0.6))
			draw_circle(Vector2(cx + T * 0.09, cy - T * 0.4), T * 0.07, Color(0.82, 0.82, 0.82, 0.4))
		"residential":                                  # 山墙小屋剪影 + 烟囱
			draw_colored_polygon(PackedVector2Array([Vector2(cx, cy - T * 0.32), Vector2(cx - T * 0.26, cy), Vector2(cx + T * 0.26, cy)]), pal["roof"])
			draw_rect(Rect2(cx - T * 0.06, cy - T * 0.4, T * 0.1, T * 0.18), Color("#6b4a2b"), true)

func _in_area(x: int, y: int) -> bool:
	for a in Sim.world.get("areas", {}).values():
		var r: Array = a.get("rect", [0, 0, 0, 0])
		if x >= int(r[0]) and x < int(r[0]) + int(r[2]) and y >= int(r[1]) and y < int(r[1]) + int(r[3]):
			return true
	return false

func _is_object(x: int, y: int) -> bool:
	for o in Sim.world.get("objects", {}).values():
		if int(o["pos"].x) == x and int(o["pos"].y) == y:
			return true
	return false

func _on_social(e: Dictionary) -> void:
	var key := _emote_key(e)
	var t := Art.emote_tex(key)
	if t != null:
		var until := Sim.tick_no + EMOTE_TICKS
		_emote[e["actor"]] = {"tex": t, "until": until}
		if String(e.get("target", "")) != "":
			_emote[e["target"]] = {"tex": t, "until": until}
	_set_dialogue(e)
	queue_redraw()

## 交谈台词：真模型(llm/slm)下优先显示决策生成的真台词；logic 模式用类型化罐头库（变化更丰富）。
func _set_dialogue(e: Dictionary) -> void:
	var t := String(e["type"])
	var actor := String(e["actor"])
	var target := String(e.get("target", ""))
	var until := Sim.tick_no + SAY_TICKS
	var actor_set := false
	# 发起者决策台词优先顶上气泡：llm/slm=模型实时生成；logic=Sim._canned_say（冻结·70B 语音库→人设台词，缺库回落通用罐头）。
	# 有词就用它、覆盖 DIALOG 类型化罐头；为空才回落 DIALOG。（WorldView 是纯视图，动不了 digest。）
	var ls := String(Sim.get_agent(actor).get("last_say", "")).strip_edges()
	if ls != "":
		_say[actor] = {"text": ls, "until": until}
		actor_set = true
	if not DIALOG.has(t):
		return
	var bank: Dictionary = DIALOG[t]
	var ok := bool(e["accepted"])
	if t == "meet" and not ok:
		if not actor_set:
			var fl := _pick(bank.get("fail", []), actor)
			if fl != "":
				_say[actor] = {"text": fl, "until": until}
		return
	if not actor_set:
		var il := _pick(bank.get("init", []), actor)
		if il != "":
			_say[actor] = {"text": il, "until": until}
	if target != "":
		var rl := _pick(bank.get("yes" if ok else "no", []), target)
		if rl != "":
			_say[target] = {"text": rl, "until": until}

func _pick(arr: Array, who: String) -> String:
	if arr.is_empty():
		return ""
	return String(arr[_hash(who.hash(), Sim.tick_no, 5) % arr.size()])

## 供 Main 在玩家对话时把 NPC 回复显示为头顶气泡（停留更久）。
func show_say(id: String, text: String, ticks: int = 60) -> void:
	_say[id] = {"text": text, "until": Sim.tick_no + ticks}
	queue_redraw()

func _emote_key(e: Dictionary) -> String:
	var t := String(e["type"])
	var ok := bool(e["accepted"])
	match t:
		"meet": return "meet_fulfilled" if ok else "meet_broken"
		"confront": return "confront" if ok else "conflict"
		"apologize": return "apologize_ok" if ok else "apologize_no"
		"conflict": return "conflict"
		_: return t   # greet/give/gossip/invite

## 由移动推断行走帧 {col,row,flip}：横向走用 down 行 + 水平翻转(左)，上走=row3，静止=正面 idle 缓慢呼吸。
var _facing_left := {}
func _agent_frame(ag: Dictionary) -> Dictionary:
	var id: String = ag["id"]
	var cur: Vector2i = ag["pos"]
	var prev: Vector2i = _prev_pos.get(id, cur)
	var d := cur - prev
	_prev_pos[id] = cur
	if d == Vector2i.ZERO:
		return {"col": int(Sim.tick_no / 16.0) % 4, "row": 0, "flip": bool(_facing_left.get(id, false))}  # idle 微动，保留上次朝向
	var row := 1
	var flip := false
	if absi(d.x) >= absi(d.y) and d.x != 0:
		row = 1
		flip = d.x < 0   # 朝左 = 水平翻转 down 帧
	elif d.y < 0:
		row = 3
	_facing_left[id] = flip
	return {"col": Sim.tick_no % 4, "row": row, "flip": flip}

## P1：Probe 切到非 town 的 Space 时，画该 Space/Floor 的占位（bounds + 楼层 + Portal 锚点）。
## 诚实边界：test_loft 没有内容——这里只证明"active Space/Floor 渲染与 hit-test 走得通"，
## 不假装它是一栋建筑。真内容在 P3（阿丽咖啡馆 1F/2F）按同一合同长出来。
func _load_interiors() -> void:
	_interiors_loaded = true
	if not FileAccess.file_exists("res://data/interiors.json"):
		return
	var f := FileAccess.open("res://data/interiors.json", FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if d is Dictionary:
		_interiors = d

## Probe 进入非-town Space：有 interiors.json 内容 → 画【真室内】（地板/墙/家具/门/楼梯）；否则回落占位网格。
func _draw_space_placeholder() -> void:
	var main := get_parent()
	var sg = main.get("_sg")
	var probe = main.get("_probe")
	var sid := String(probe.active_space)
	var fid := String(probe.active_floor)
	var b: Rect2 = sg.bounds_px(sid)
	if not _interiors_loaded:
		_load_interiors()
	var content: Dictionary = (_interiors.get(sid, {}) as Dictionary).get(fid, {})
	if not content.is_empty():
		_draw_interior(sg, sid, fid, b, content)
		return
	draw_rect(b, Color("#1a1d26"), true)
	draw_rect(b, Color("#5a6478"), false, 2.0)
	for gx in range(int(b.size.x / T) + 1):
		draw_line(Vector2(b.position.x + gx * T, b.position.y), Vector2(b.position.x + gx * T, b.end.y), Color(1, 1, 1, 0.05), 1.0)
	for gy in range(int(b.size.y / T) + 1):
		draw_line(Vector2(b.position.x, b.position.y + gy * T), Vector2(b.end.x, b.position.y + gy * T), Color(1, 1, 1, 0.05), 1.0)
	draw_string(Art.font(), b.position + Vector2(10, 26), "%s / %s（Probe inspect · 无内容占位）" % [sg.label_of(sid), fid],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#cfe8ff"))
	for pt in sg.portals_from(sid, fid):          # Portal 锚点：看得见"这层通向哪"
		var to: Dictionary = pt["to"]
		var pos: Array = to.get("pos", [0, 0])
		var c := Vector2(float(pos[0]) * T + T * 0.5, float(pos[1]) * T + T * 0.5)
		draw_circle(c, 10.0, Color("#ffd166", 0.85))
		draw_string(Art.font(), c + Vector2(12, 4), "%s→%s/%s" % [pt["kind"], to.get("space", ""), to.get("floor", "")],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#ffd166"))

## 画一层真室内：木地板 + 外墙(门口留缺) + 家具(程序化) + 门/上下楼提示 + 楼层标签。纯 View、只读数据。
func _draw_interior(sg, sid: String, fid: String, b: Rect2, content: Dictionary) -> void:
	var wc := int(b.size.x / T); var hc := int(b.size.y / T)
	var ox := b.position.x; var oy := b.position.y
	# 门缺口：扫 portal 端点落在本层的门(kind=door)格 → 那格墙留缺
	var door_gap := {}
	for p in sg.portals:
		for side in ["from", "to"]:
			var e: Dictionary = p.get(side, {})
			if String(e.get("space", "")) == sid and String(e.get("floor", "")) == fid and String(p.get("kind", "")) == "door":
				var ep: Array = e.get("pos", [0, 0])
				door_gap[int(ep[1]) * wc + int(ep[0])] = true
	# 木地板
	draw_rect(b, Color("#caa26e"), true)
	for gy in range(hc):
		if gy % 2 == 0:
			draw_rect(Rect2(ox, oy + gy * T, b.size.x, 3), Color("#a6814e", 0.4), true)
	# 外墙（边框），门口那格留缺、画成门
	for gx in range(wc):
		_interior_wall(sg, ox + gx * T, oy, door_gap.has(gx))                          # 上墙
		_interior_wall(sg, ox + gx * T, oy + (hc - 1) * T, door_gap.has((hc - 1) * wc + gx))  # 下墙
	for gy in range(hc):
		_interior_wall(sg, ox, oy + gy * T, door_gap.has(gy * wc))                      # 左墙
		_interior_wall(sg, ox + (wc - 1) * T, oy + gy * T, door_gap.has(gy * wc + wc - 1))  # 右墙
	# 家具（按 slot 程序化）
	for fr in content.get("furniture", []):
		var fp: Array = (fr as Dictionary).get("pos", [0, 0])
		_draw_interior_furniture(String((fr as Dictionary).get("slot", "")), Vector2(ox + int(fp[0]) * T, oy + int(fp[1]) * T))
	# P3 Tier-B：画【此刻真在这层】的居民（阿丽在自家咖啡馆睡觉/看摊）。Space bounds 从原点起 → _draw_agent 用
	# ag.pos*T 的室内局部坐标即落在本层画面里。纯 View、只读 ag 平面字段。
	for ag in Sim.agents:
		if String(ag.get("space", "town")) == sid and String(ag.get("floor", "outdoor")) == fid:
			_draw_agent(ag)
	# 楼层标签
	draw_string(Art.font(), b.position + Vector2(T + 8, 22), "%s · %s" % [sg.label_of(sid), content.get("label", fid)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#3a2a1a"))

func _interior_wall(sg, x: float, y: float, is_door: bool) -> void:
	if is_door:                                    # 门：地板延伸 + 门框 + 木门
		draw_rect(Rect2(x + T * 0.12, y + T * 0.1, T * 0.76, T * 0.8), Color("#6e4d31"), true)
		draw_rect(Rect2(x + T * 0.12, y + T * 0.1, T * 0.76, T * 0.8), Color("#3a291a"), false, 2.0)
		draw_circle(Vector2(x + T * 0.72, y + T * 0.5), T * 0.05, Color("#e0c060"))   # 门把
		return
	draw_rect(Rect2(x, y, T, T), Color("#8a7256"), true)             # 墙主面（暖石灰）
	draw_rect(Rect2(x, y, T, T * 0.24), Color("#a08a6c"), true)      # 顶棱高光
	draw_rect(Rect2(x, y + T * 0.86, T, T * 0.14), Color("#5f4c38"), true)  # 墙脚暗边

func _draw_interior_furniture(slot: String, base: Vector2) -> void:
	match slot:
		"bed": _draw_bed(base)
		"coffee":                                   # 咖啡机：深色金属机身 + 红灯 + 杯
			draw_rect(Rect2(base.x + T * 0.2, base.y + T * 0.15, T * 0.6, T * 0.62), Color("#3a3f47"), true)
			draw_rect(Rect2(base.x + T * 0.2, base.y + T * 0.15, T * 0.6, T * 0.14), Color("#565c66"), true)
			draw_circle(Vector2(base.x + T * 0.68, base.y + T * 0.3), T * 0.05, Color("#e05a4e"))
			draw_rect(Rect2(base.x + T * 0.42, base.y + T * 0.52, T * 0.16, T * 0.14), Color("#efe4cc"), true)
		"counter":                                  # 吧台：长木身 + 台面高光
			draw_rect(Rect2(base.x + 2, base.y + T * 0.6, T - 4, T * 0.35), Color(0, 0, 0, 0.18), true)
			draw_rect(Rect2(base.x + T * 0.03, base.y + T * 0.32, T * 0.94, T * 0.5), Color("#6e4d31"), true)
			draw_rect(Rect2(base.x + T * 0.03, base.y + T * 0.32, T * 0.94, T * 0.1), Color("#8a6238"), true)
		"table":                                    # 餐桌
			draw_rect(Rect2(base.x + T * 0.24, base.y + T * 0.5, T * 0.1, T * 0.34), Color("#5a3f28"), true)
			draw_rect(Rect2(base.x + T * 0.66, base.y + T * 0.5, T * 0.1, T * 0.34), Color("#5a3f28"), true)
			draw_rect(Rect2(base.x + T * 0.15, base.y + T * 0.3, T * 0.7, T * 0.24), Color("#8a6238"), true)
			draw_rect(Rect2(base.x + T * 0.15, base.y + T * 0.3, T * 0.7, T * 0.08), Color("#a67f4e"), true)
		"chair":                                    # 椅子
			draw_rect(Rect2(base.x + T * 0.34, base.y + T * 0.2, T * 0.32, T * 0.5), Color("#6e4d31"), true)
			draw_rect(Rect2(base.x + T * 0.34, base.y + T * 0.44, T * 0.32, T * 0.13), Color("#8a6238"), true)
		"shelf":                                    # 书架/货架
			draw_rect(Rect2(base.x + T * 0.1, base.y + T * 0.05, T * 0.8, T * 0.85), Color("#5a3f28"), true)
			var bookcols := [Color("#a3443a"), Color("#4a7a5a"), Color("#47688a")]
			for k in range(3):
				draw_rect(Rect2(base.x + T * 0.15, base.y + T * 0.24 + k * T * 0.22, T * 0.7, T * 0.04), Color("#3a291a"), true)
				draw_rect(Rect2(base.x + T * 0.18, base.y + T * 0.12 + k * T * 0.22, T * 0.5, T * 0.11), bookcols[k], true)
		"plant":                                    # 盆栽
			draw_rect(Rect2(base.x + T * 0.34, base.y + T * 0.56, T * 0.32, T * 0.28), Color("#8a5a3a"), true)
			draw_circle(Vector2(base.x + T * 0.5, base.y + T * 0.42), T * 0.24, Color("#2f6d3a"))
			draw_circle(Vector2(base.x + T * 0.4, base.y + T * 0.32), T * 0.14, Color("#3c8a4a"))
		"rug":                                       # 地毯
			draw_rect(Rect2(base.x + T * 0.08, base.y + T * 0.15, T * 0.84, T * 0.7), Color("#8a4a4a", 0.75), true)
			draw_rect(Rect2(base.x + T * 0.08, base.y + T * 0.15, T * 0.84, T * 0.7), Color("#e0c060", 0.5), false, 2.0)
		"desk":                                      # 书桌 + 纸
			draw_rect(Rect2(base.x + T * 0.15, base.y + T * 0.35, T * 0.7, T * 0.28), Color("#6e4d31"), true)
			draw_rect(Rect2(base.x + T * 0.15, base.y + T * 0.35, T * 0.7, T * 0.08), Color("#8a6238"), true)
			draw_rect(Rect2(base.x + T * 0.2, base.y + T * 0.55, T * 0.09, T * 0.28), Color("#5a3f28"), true)
			draw_rect(Rect2(base.x + T * 0.71, base.y + T * 0.55, T * 0.09, T * 0.28), Color("#5a3f28"), true)
			draw_rect(Rect2(base.x + T * 0.26, base.y + T * 0.22, T * 0.2, T * 0.14), Color("#efe4cc"), true)
		"window":                                    # 窗（画在墙上）：天光 + 木框 + 十字
			draw_rect(Rect2(base.x + T * 0.15, base.y + T * 0.12, T * 0.7, T * 0.5), Color("#8fc0e0"), true)
			draw_rect(Rect2(base.x + T * 0.15, base.y + T * 0.12, T * 0.7, T * 0.5), Color("#5a3f28"), false, 3.0)
			draw_line(Vector2(base.x + T * 0.5, base.y + T * 0.12), Vector2(base.x + T * 0.5, base.y + T * 0.62), Color("#5a3f28"), 2.0)
		"stairs":                                    # 楼梯：斜阶
			for k in range(4):
				draw_rect(Rect2(base.x + T * 0.12 + k * T * 0.17, base.y + T * 0.62 - k * T * 0.13, T * 0.2, T * 0.15), Color("#7a6a52"), true)
				draw_rect(Rect2(base.x + T * 0.12 + k * T * 0.17, base.y + T * 0.62 - k * T * 0.13, T * 0.2, T * 0.04), Color("#9a8a70"), true)
		_:
			draw_rect(Rect2(base.x + 9, base.y + 12, T - 18, T - 18), Color("#8a6a45"), true)

func _draw() -> void:
	var _main := get_parent()
	var _pb = _main.get("_probe") if _main != null else null
	if _pb != null and String(_pb.active_space) != "town":
		_draw_space_placeholder()                 # 非 town：只画该 Space/Floor（active-space 渲染）
		return
	if Sim.world.is_empty():
		return
	var w: int = int(Sim.world.get("width", 24))
	var h: int = int(Sim.world.get("height", 16))
	# 地面：逐格选草地变体（有切片时）→ 否则平铺单图 → 否则色块
	if not _grass.is_empty():
		var tw := 0
		for g in _grass:
			tw += int(g["w"])
		for ty in range(h):
			for tx in range(w):
				var r := _hash(tx, ty, 3) % tw
				var chosen: Texture2D = _grass[0]["t"]
				for g in _grass:
					r -= int(g["w"])
					if r < 0:
						chosen = g["t"]
						break
				draw_texture_rect(chosen, Rect2(tx * T, ty * T, T, T), false)
	else:
		var grass := Art.ground_tex()
		if grass != null:
			draw_texture_rect(grass, Rect2(0, 0, w * T, h * T), true)
		else:
			draw_rect(Rect2(0, 0, w * T, h * T), Art.ground, true)
	# 广场铺 dirt 地面（中央集市感）
	var dirt := Art.terrain_tex("dirt")
	if dirt != null and Sim.world.get("areas", {}).has("plaza"):
		var pr: Array = Sim.world["areas"]["plaza"].get("rect", [0, 0, 0, 0])
		for yy in range(int(pr[1]), int(pr[1]) + int(pr[3])):
			for xx in range(int(pr[0]), int(pr[0]) + int(pr[2])):
				draw_texture_rect(dirt, Rect2(xx * T, yy * T, T, T), false)

	# 水面（map.json water 层）：铺在草地之上、区域/建筑之下，作为地形读。深蓝底 + 浅蓝格纹岸边微光，
	# 用确定性 _hash 做静态涟漪（不抽 RNG、不进 digest）。
	if not _terrain_built:
		_build_terrain()
	var wtile := Art.terrain_tex("water")
	for idx in _water_set:
		var wx: int = idx % w
		var wy: int = idx / w
		var wr := Rect2(wx * T, wy * T, T, T)
		if wtile != null:
			draw_texture_rect(wtile, wr, false)
		else:
			draw_rect(wr, Color("#2f6d86"), true)
			if _hash(wx, wy, 21) % 100 < 30:   # 静态涟漪高光
				draw_rect(Rect2(wx * T + T * 0.18, wy * T + T * 0.30, T * 0.42, T * 0.12), Color(0.72, 0.86, 0.94, 0.35), true)

	# 区域：只留一层极淡的"街区底色"（0.32→0.10）+ 低调标签。建筑一旦有了体积，空间就该由【房子】定义，
	# 而不是由半透明色块定义——旧的 0.32 色洗盖在建筑上，把砖木都洗成灰紫，是"简陋感"的主因之一。
	for area in Sim.world.get("areas", {}):
		var a: Dictionary = Sim.world["areas"][area]
		var r: Array = a.get("rect", [0, 0, 0, 0])
		var rect := Rect2(r[0] * T, r[1] * T, r[2] * T, r[3] * T)
		var ac := Art.area_color(area); ac.a = 0.10
		draw_rect(rect, ac, true)
		draw_string(Art.font(), Vector2(rect.position.x + 6, rect.position.y + 16), str(a.get("label", area)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.28))
	# 室内房间 → 画成【真·建筑】（docs/16 / docs/19 §9）：外墙有厚度 + 落地阴影 + 屋檐、南墙开门、北墙开窗、
	# 室内按房型铺材质地板，有人时透暖光。参照 Stardew / Stoneshard / ZeroSievert 的"切顶俯视"读法：
	# 建筑必须有体积，人才有比例——旧版把 6x4 的房间画成一块半透明色块 + 文字标签，读作"色区"而非"房子"。
	# 纯渲染：不进 digest、不抽 RNG（门窗变体用 Sim._hash01(room_id) 确定性选）。红线不动。
	for rid in Sim.world.get("rooms", {}):
		var rm: Dictionary = Sim.world["rooms"][rid]
		var rr: Array = rm.get("rect", [0, 0, 0, 0])
		_draw_building(str(rid), Rect2(rr[0] * T, rr[1] * T, rr[2] * T, rr[3] * T),
			str(rm.get("type", rid)), bool(rm.get("enclosed", false)))
	# （网格线已移除：Stardew/Stoneshard/ZeroSievert 都不画格子——硬网格是最大的"原型感"来源。
	#   瓦片结构由草地变体/地板纹理自然读出。需要格子时走 dev overlay，不进玩家视图。）
	# （1 格小屋地标已移除：那正是"房子=人一般大"的比例谎言来源；建筑现由上面的真·建筑体现。）

	# 分类型建筑外墙（map.json walls 层，按所属建筑 type 上色）：buildings.json 清空后，districts 的体积就靠这层墙读出。
	# 切顶俯视：落地阴影 + 三段墙面(顶棱高光/主面/墙脚暗边)让 1 格墙读作有厚度；颜色由类型区分（住宅暖木/商业米黄/公共蓝灰/工坊灰石）。门缺口天然留白。
	for idx in _wall_set:
		var sx: int = idx % w
		var sy: int = idx / w
		var pal: Dictionary = BLD_PAL.get(String(_wall_type.get(idx, "workshop")), BLD_PAL["workshop"])
		draw_rect(Rect2(sx * T + 2, sy * T + T * 0.55, T, T * 0.5), Color(0, 0, 0, 0.22), true)      # 落地阴影
		draw_rect(Rect2(sx * T, sy * T, T, T), pal["face"], true)                                     # 墙主面
		draw_rect(Rect2(sx * T, sy * T, T, T * 0.22), pal["top"], true)                               # 顶棱高光
		draw_rect(Rect2(sx * T, sy * T + T * 0.86, T, T * 0.14), pal["foot"], true)                   # 墙脚暗边
	# 屋檐 + 招牌：每栋（非广场）沿顶墙内侧铺一条屋檐色带 + 门上方挂类型招牌图标 → 类型一眼可辨。
	_draw_building_dressing(w)

	# 装饰散布（区域外草地上的树/花/草丛，确定性布局；在物件与居民之下）
	if not _decor_built:
		_build_decor()
	for it in _decor_items:
		var dtex: Texture2D = it["tex"]
		var c: Vector2i = it["cell"]
		var th: int = int(it["h"])
		var dw := float(dtex.get_width()) * (float(T) / 16.0)
		var dh := float(dtex.get_height()) * (float(T) / 16.0)
		# 底对齐格子（高物件如树向上伸出）
		draw_texture_rect_region(dtex, Rect2(c.x * T + (T - dw) * 0.5, (c.y + 1) * T - dh, dw, dh), Rect2(0, 0, dtex.get_width(), dtex.get_height()))

	# authored 阻挡树（map.json trees 层）：这些是【会挡路】的真树（与上面可踩的程序化花草区分开）。
	# 用 tree_big 切图底对齐画；缺切图则程序化画树冠+树干。占满格 → 玩家一眼读出"这里过不去"。
	var ttex := Art.decor_tex("tree_big")
	for tc in _tree_cells:
		if ttex != null:
			var tdw := float(ttex.get_width()) * (float(T) / 16.0)
			var tdh := float(ttex.get_height()) * (float(T) / 16.0)
			draw_texture_rect_region(ttex, Rect2(tc.x * T + (T - tdw) * 0.5, (tc.y + 1) * T - tdh, tdw, tdh), Rect2(0, 0, ttex.get_width(), ttex.get_height()))
		else:
			var cx: float = tc.x * T + T * 0.5
			draw_rect(Rect2(tc.x * T + T * 0.30, tc.y * T + T * 0.55, T * 0.40, T * 0.45), Color("#6b4a2b"), true)  # 树干
			draw_circle(Vector2(cx, tc.y * T + T * 0.42), T * 0.42, Color("#2f6d3a"))                                # 树冠
			draw_circle(Vector2(cx - T * 0.18, tc.y * T + T * 0.30), T * 0.24, Color("#3c8a4a"))                      # 高光叶

	_draw_landmarks()          # P2-4 公共地标（水井 / 告示板）：程序化画在地形层、居民之下

	# 对象：CC0 物件精灵（slot=id 前缀，如 bench/bath/counter/desk/arcade）；缺则程序化色块兜底
	for id in Sim.world.get("objects", {}):
		var o: Dictionary = Sim.world["objects"][id]
		var p: Vector2i = o["pos"]
		var slot := String(id).split("_")[0]
		var base := Vector2(p.x * T, p.y * T)
		match slot:
			"bed": _draw_bed(base)
			"stove": _draw_stove(base)
			"fest": _draw_festival(base)   # Wave 2b：节日机会地形（灯笼，暖光）
			_:
				var otex := Art.object_tex(slot)
				if otex != null:
					var s := 40.0
					draw_texture_rect_region(otex, Rect2(base.x + (T - s) * 0.5, base.y + (T - s) * 0.5, s, s), Rect2(0, 0, otex.get_width(), otex.get_height()))
				else:
					draw_rect(Rect2(base.x + 9, base.y + 12, T - 18, T - 18), Color("#8a6a45"), true)
					draw_rect(Rect2(base.x + 9, base.y + 12, T - 18, T - 18), Color(0, 0, 0, 0.35), false, 2.0)
					draw_string(Art.font(), Vector2(base.x + 4, base.y + T - 3), str(o.get("type", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.7))

	# ── 社交层（在 Agent 之下先画连线，再画 Agent 与标记）──────────────────
	_draw_faction_rings()      # S3a：派系归属（同色脚环）
	_draw_pact_links()         # S3b：互助盟约（青色双线 + 🤝）
	_draw_relationship_lines()
	_draw_talking_links()
	for ag in Sim.agents:
		if String(ag.get("space", "town")) != "town":
			continue            # P3 Tier-B：非-town 平面的居民(在咖啡馆室内的阿丽)不画在镇上——否则会用室内格坐标在镇上"鬼影"
		_draw_agent(ag)

	if dbg_nav:                 # P2-4 开发叠层（N 键）：可视化导航权威数据——阻挡格 + 交互格
		_draw_nav_overlay(w)

## P2-4 导航开发叠层：红=Sim._blocked 阻挡权威集（墙/水/树/家具），绿点=家具的可走正交邻格（居民站着用的交互格）。
## 纯 View、只读 Sim._blocked/objects，绝不写 Sim；只有 dbg_nav 开时才画（默认关，玩家视图不受影响）。
func _draw_nav_overlay(w: int) -> void:
	for idx in Sim._blocked:
		var bx: int = idx % w; var by: int = idx / w
		draw_rect(Rect2(bx * T, by * T, T, T), Color(0.92, 0.22, 0.22, 0.22), true)
		draw_rect(Rect2(bx * T, by * T, T, T), Color(0.92, 0.22, 0.22, 0.5), false, 1.0)
	for oid in Sim.world.get("objects", {}):
		var op: Vector2i = Sim.world["objects"][oid].get("pos", Vector2i.ZERO)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = op + d
			if n.x >= 0 and n.y >= 0 and n.x < w and not Sim._blocked.has(n.y * w + n.x):
				draw_rect(Rect2(n.x * T + T * 0.3, n.y * T + T * 0.3, T * 0.4, T * 0.4), Color(0.3, 0.95, 0.42, 0.6), true)

## P2-4 公共基础设施地标：程序化画水井（石圈+蓝顶）与告示板（木板+红顶+纸），风格与分类型建筑一致。
func _draw_landmarks() -> void:
	for lm in Sim.world.get("landmarks", []):
		var lp: Array = lm.get("pos", [0, 0])
		var bx := int(lp[0]) * T; var by := int(lp[1]) * T
		match String(lm.get("type", "")):
			"well":
				draw_rect(Rect2(bx + 2, by + T * 0.6, T - 4, T * 0.34), Color(0, 0, 0, 0.2), true)                 # 阴影
				draw_rect(Rect2(bx + T * 0.15, by + T * 0.45, T * 0.7, T * 0.45), Color("#8a8f98"), true)          # 石圈
				draw_rect(Rect2(bx + T * 0.15, by + T * 0.45, T * 0.7, T * 0.1), Color("#a6abb4"), true)           # 井沿高光
				draw_rect(Rect2(bx + T * 0.3, by + T * 0.56, T * 0.4, T * 0.28), Color("#20242c"), true)           # 井口暗
				draw_rect(Rect2(bx + T * 0.2, by + T * 0.1, T * 0.06, T * 0.4), Color("#6b4a2b"), true)            # 立柱
				draw_rect(Rect2(bx + T * 0.74, by + T * 0.1, T * 0.06, T * 0.4), Color("#6b4a2b"), true)
				draw_colored_polygon(PackedVector2Array([Vector2(bx + T * 0.5, by - T * 0.02), Vector2(bx + T * 0.08, by + T * 0.16), Vector2(bx + T * 0.92, by + T * 0.16)]), Color("#5a86b0"))  # 蓝顶
			"board":
				draw_rect(Rect2(bx + 2, by + T * 0.62, T - 4, T * 0.3), Color(0, 0, 0, 0.2), true)                 # 阴影
				draw_rect(Rect2(bx + T * 0.18, by + T * 0.55, T * 0.06, T * 0.4), Color("#5a3f28"), true)          # 支柱
				draw_rect(Rect2(bx + T * 0.76, by + T * 0.55, T * 0.06, T * 0.4), Color("#5a3f28"), true)
				draw_rect(Rect2(bx + T * 0.12, by + T * 0.2, T * 0.76, T * 0.42), Color("#8a6238"), true)          # 木板
				draw_rect(Rect2(bx + T * 0.12, by + T * 0.2, T * 0.76, T * 0.42), Color(0, 0, 0, 0.3), false, 2.0)
				draw_rect(Rect2(bx + T * 0.08, by + T * 0.1, T * 0.84, T * 0.14), Color("#b5484a"), true)          # 红顶
				draw_rect(Rect2(bx + T * 0.2, by + T * 0.28, T * 0.22, T * 0.26), Color("#efe4cc"), true)          # 纸
				draw_rect(Rect2(bx + T * 0.5, by + T * 0.3, T * 0.24, T * 0.2), Color("#dfe8f0"), true)

func _center(ag: Dictionary) -> Vector2:
	var p: Vector2i = ag["pos"]
	return Vector2(p.x * T + T * 0.5, p.y * T + T * 0.5)

## 关系连线：|affinity|>20 才画；绿=亲密、红=敌意，粗细/透明度随强度。
func _draw_relationship_lines() -> void:
	for ag in Sim.agents:
		for oid in ag["relationships"]:
			if String(ag["id"]) >= String(oid):
				continue   # 去重（只画 id 较小一侧）
			var other: Dictionary = Sim.get_agent(oid)
			if other.is_empty():
				continue
			var aff := float(ag["relationships"][oid].get("affinity", 0.0))
			if absf(aff) <= 20.0:
				continue
			var t := clampf(absf(aff) / 100.0, 0.0, 1.0)
			var col := (Color("#7ed957") if aff > 0 else Color("#e85a5a"))
			col.a = 0.18 + t * 0.5
			draw_line(_center(ag), _center(other), col, 1.0 + t * 3.0)

## S3a 派系：同派系成员脚下画同色环（颜色由派系 medoid id 确定性派生）。
func _draw_faction_rings() -> void:
	for ag in Sim.agents:
		var fac := String(ag.get("faction", ""))
		if fac == "":
			continue
		var col := _faction_color(fac)
		col.a = 0.85
		var c := _center(ag) + Vector2(0, T * 0.34)
		draw_arc(c, T * 0.30, 0.0, TAU, 20, col, 2.5)

func _faction_color(fac: String) -> Color:
	var h := absi(fac.hash())
	return Color.from_hsv(float(h % 360) / 360.0, 0.65, 0.95)

## S3b 互助盟约：active pact 双方画青色双线 + 中点握手标记。
func _draw_pact_links() -> void:
	var drawn := {}
	for ag in Sim.agents:
		for oid in ag.get("pacts", {}):
			var p: Dictionary = ag["pacts"][oid]
			if String(p.get("status", "")) != "active":
				continue
			var key := String(p.get("key", ""))
			if drawn.has(key):
				continue
			drawn[key] = true
			var other: Dictionary = Sim.get_agent(oid)
			if other.is_empty():
				continue
			var a := _center(ag)
			var b := _center(other)
			var perp := (b - a).orthogonal().normalized() * 2.0
			var cyan := Color("#39d4c8", 0.7)
			draw_line(a + perp, b + perp, cyan, 1.6)
			draw_line(a - perp, b - perp, cyan, 1.6)
			draw_string(ThemeDB.fallback_font, (a + b) * 0.5 - Vector2(6, -4), "🤝", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, cyan)

## 对话连线：正在一次社交事务里的两人之间画一条暖黄线。
func _draw_talking_links() -> void:
	for ag in Sim.agents:
		var opt = ag.get("option")
		if opt != null and String(opt.get("kind", "")) == "social":
			var other: Dictionary = Sim.get_agent(String(opt.get("partner", "")))
			if not other.is_empty():
				draw_line(_center(ag), _center(other), Color("#ffd166", 0.85), 2.5)

func _draw_agent(ag: Dictionary) -> void:
	var center := _center(ag)
	var col := Color(str(ag.get("persona", {}).get("color", "#ffffff")))
	var spr := _hued_tex(str(ag.get("persona", {}).get("sprite", "")), String(ag["id"]))  # L6：克隆取确定性色相变体，命名 6 人=正典
	if spr != null:
		# 软阴影 + 按移动选行走帧（cols0-3 循环，左向水平翻转）放大居中（脚踩格心）
		var fr := _agent_frame(ag)
		draw_circle(center + Vector2(0, T * 0.30), T * 0.22, Color(0, 0, 0, 0.25))
		var sz := 46.0
		var src := Rect2(int(fr["col"]) * Art.CHAR_FRAME.x, int(fr["row"]) * Art.CHAR_FRAME.y, Art.CHAR_FRAME.x, Art.CHAR_FRAME.y)
		if bool(fr["flip"]):
			draw_set_transform(center, 0.0, Vector2(-1, 1))
			draw_texture_rect_region(spr, Rect2(-sz * 0.5, -sz * 0.72, sz, sz), src)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect_region(spr, Rect2(center.x - sz * 0.5, center.y - sz * 0.72, sz, sz), src)
	else:
		draw_circle(center, T * 0.32, col)
		draw_circle(center, T * 0.32, Color(0, 0, 0, 0.4), false, 2.0)
	# 玩家标识：金色外环（--player 模式一眼可辨"这是我"）
	if ag.get("is_player", false):
		draw_circle(center, T * 0.42, Color("#ffd700"), false, 2.5)
	# 头顶 emote（社交事件触发，短暂显示）
	var em = _emote.get(ag["id"])
	if em != null and Sim.tick_no < int(em["until"]):
		var et: Texture2D = em["tex"]
		var es := 26.0
		draw_texture_rect_region(et, Rect2(center.x - es * 0.5, center.y - T * 1.02, es, es), Rect2(0, 0, et.get_width(), et.get_height()))
	# 名字
	var nm := str(ag.get("persona", {}).get("name", ag["id"]))
	draw_string(Art.font(), center + Vector2(-18, -T * 0.42), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	# 冲突 / 约见 标记（名字上方；用字体里一定有的字形）
	if _in_conflict(ag["id"]):
		draw_string(Art.font(), center + Vector2(-26, -T * 0.66), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#e85a5a"))
	if _has_meet(ag["id"]):
		draw_string(Art.font(), center + Vector2(12, -T * 0.66), "约", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#ffd166"))
	# 气泡：交谈台词（短暂）优先，其次当前动作
	var bubble := ""
	var sy = _say.get(ag["id"])
	if sy != null and Sim.tick_no < int(sy["until"]):
		bubble = String(sy["text"])
	else:
		var opt = ag.get("option")
		if opt != null:
			bubble = str(opt.get("action", ""))
	if bubble != "":
		var fnt := Art.font()
		var sz := fnt.get_string_size(bubble, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		var bpos := center + Vector2(-sz.x * 0.5, T * 0.5)
		draw_rect(Rect2(bpos + Vector2(-4, -12), sz + Vector2(8, 6)), Color(0, 0, 0, 0.55), true)
		draw_string(fnt, bpos, bubble, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.92))
	# 最紧迫需求条
	_draw_urgent_need(center, ag)

## 程序化像素床（顶视角）：木框 + 床单 + 枕头 + 被子。base=格左上像素。
## ── 建筑（切顶俯视）────────────────────────────────────────────────────────
const WALL := 13.0     # 外墙厚(px)≈0.27 格：够读出体积，又不吃室内——室内可走面积仍是房间 rect 本身（墙向外长）

## 墙比地板【暗】一档：屋顶被切掉后墙体仍处在背光面，明度差才让"墙/地"分得开（旧版两者同明度 → 一块板）。
func _mat_wall(rtype: String) -> Color:
	if "work" in rtype or "shop" in rtype: return Color("#4c463d")     # 石/土墙
	if "wash" in rtype or "bath" in rtype: return Color("#3f4b50")
	if "quiet" in rtype: return Color("#484054")
	return Color("#5a4028")                                             # 木墙（居室/茶座）

## 夜量 0..1（夜=1、昼=0，晨昏平滑）。与 Main._daylight 的色停同频——它把整块世界画布乘暗，
## 所以室内要靠【相对】暖度把自己从冷夜里拉出来。
func _night_amt() -> float:
	var tod := Sim.time_of_day()
	if tod < 0.20: return 1.0
	if tod < 0.32: return 1.0 - (tod - 0.20) / 0.12
	if tod < 0.72: return 0.0
	if tod < 0.88: return (tod - 0.72) / 0.16
	return 1.0

func _mat_floor(rtype: String) -> Color:
	if "bed" in rtype: return Color("#8a6038")
	if "parlor" in rtype or "cafe" in rtype: return Color("#8a6440")
	if "work" in rtype: return Color("#6a655a")
	if "quiet" in rtype: return Color("#5f5478")
	if "wash" in rtype or "bath" in rtype: return Color("#46686e")
	if "shop" in rtype: return Color("#7f6030")
	return Color("#7a5230")

## 一栋建筑：落地影 → 外墙(屋檐/受光高光) → 室内地板+材质纹理 → 内墙投影 → 南门 → 北窗 → 有人透暖光。
func _draw_building(rid: String, inner: Rect2, rtype: String, enclosed: bool) -> void:
	var outer := inner.grow(WALL)
	var wc := _mat_wall(rtype)
	var fc := _mat_floor(rtype)
	# 落地阴影（右下偏移）→ 体积感：让房子"坐"在地上而不是浮在草上
	draw_rect(Rect2(outer.position + Vector2(4.0, 5.0), outer.size), Color(0, 0, 0, 0.30), true)
	# 外墙实心 + 屋檐暗带 + 上/左受光高光 + 外缘描边
	draw_rect(outer, wc, true)
	draw_rect(Rect2(outer.position, Vector2(outer.size.x, WALL * 0.55)), Color(0, 0, 0, 0.30), true)
	draw_line(outer.position, Vector2(outer.end.x, outer.position.y), wc.lightened(0.30), 2.0)
	draw_line(outer.position, Vector2(outer.position.x, outer.end.y), wc.lightened(0.16), 2.0)
	draw_rect(outer, Color(0, 0, 0, 0.38), false, 1.5)
	# 室内地板
	draw_rect(inner, fc, true)
	# 地板材质：湿区/铺面走方砖，其余走木纹横板
	if "wash" in rtype or "bath" in rtype or "shop" in rtype:
		var gx := inner.position.x + T * 0.5
		while gx < inner.end.x - 1.0:
			draw_line(Vector2(gx, inner.position.y + 1), Vector2(gx, inner.end.y - 1), Color(0, 0, 0, 0.10), 1.0)
			gx += T * 0.5
		var gy := inner.position.y + T * 0.5
		while gy < inner.end.y - 1.0:
			draw_line(Vector2(inner.position.x + 1, gy), Vector2(inner.end.x - 1, gy), Color(0, 0, 0, 0.10), 1.0)
			gy += T * 0.5
	else:
		var py := inner.position.y + T * 0.5
		while py < inner.end.y - 1.0:
			draw_line(Vector2(inner.position.x + 1, py), Vector2(inner.end.x - 1, py), Color(0, 0, 0, 0.11), 1.0)
			py += T * 0.5
	# 陈设：地毯 + 靠墙杂物（"住着人"的密度——空房间是"简陋"的另一半主因）
	_draw_room_decor(rid, inner, rtype)
	# 内墙投影：墙在室内投下的暗边 → 读出"墙有厚度"
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, 4.0)), Color(0, 0, 0, 0.26), true)
	draw_rect(Rect2(inner.position, Vector2(4.0, inner.size.y)), Color(0, 0, 0, 0.16), true)
	# 南墙开门（确定性位置）：门洞露地板色 + 深色门槛
	var dw := minf(T * 0.85, inner.size.x)
	var dspan := maxf(0.0, inner.size.x - dw)
	var dx := inner.position.x + Sim._hash01(rid + ":door") * dspan
	draw_rect(Rect2(dx, inner.end.y, dw, WALL), fc.darkened(0.12), true)
	draw_rect(Rect2(dx, inner.end.y + WALL - 3.0, dw, 3.0), Color("#3a2a1c"), true)
	# 有人在内？（灯火强度用）
	var occ := 0
	for ag in Sim.agents:
		if inner.has_point(Vector2(ag["pos"].x * T + T * 0.5, ag["pos"].y * T + T * 0.5)):
			occ += 1
	# ── 灯火（Stoneshard/ZeroSievert 的招牌：暖池 vs 冷夜）────────────────────
	# 夜里 enclosed 房间点灯（有人更旺）。CanvasModulate 会把整幅世界乘暗，故这里要下得【重】——
	# 乘暗后剩下的"暖 vs 冷"相对差，才是玩家读到的那盏灯。
	var night := _night_amt()
	# 平铺底光压低（0.52→0.26）：整块均匀刷色会把地毯/杂物/木纹全洗平——光要有【落点】，
	# 所以大头交给中心的径向暖池，底光只负责"这屋是亮的"。
	var lit := 0.0
	if enclosed:
		lit += 0.26 * night
	lit += minf(0.14, occ * 0.05) * (0.45 + 0.55 * night)
	if lit > 0.001:
		draw_rect(inner, Color("#ffbe63", lit), true)         # 偏橙灯火色：被夜蓝乘过后仍咬得住暖调
	# 灯芯：房间中心的径向暖池（"光源在屋里"的层次）——夜里最明显，白天几乎不见
	var pool := (0.30 * night + minf(0.20, occ * 0.07))
	if pool > 0.01:
		var cen := inner.get_center()
		var rad := minf(inner.size.x, inner.size.y) * 0.55
		for k in 4:
			var f := 1.0 - float(k) / 4.0
			draw_circle(cen, rad * (0.30 + 0.24 * float(k)), Color("#ffd27a", pool * 0.13 * f))
	# 北墙开窗（enclosed 才有；1-2 扇，确定性）；夜里从窗口向北洒一片暖光到地上
	if enclosed:
		var n := 1 + int(Sim._hash01(rid + ":win") * 2.0)
		for i in n:
			var ww := minf(T * 0.55, inner.size.x * 0.5)
			var t := (float(i) + 0.5) / float(n)
			var wx := inner.position.x + t * inner.size.x - ww * 0.5
			var wy := outer.position.y + WALL * 0.42
			var glow := 0.30 * night + minf(0.25, occ * 0.08) * night
			if glow > 0.01:                                    # 窗口洒光（越远越淡，三层叠出衰减）
				for k in 3:
					var sp := float(k + 1)
					draw_rect(Rect2(wx - sp * 3.0, outer.position.y - sp * 7.0, ww + sp * 6.0, sp * 7.0),
						Color("#ffc978", glow * (0.30 - 0.07 * float(k))), true)
			# 窗本体：夜里点亮（暖黄），白天冷玻璃
			var wcol := Color("#ffd98f").lerp(Color("#2b3a46"), 1.0 - night) if glow > 0.01 else Color("#2b3a46")
			draw_rect(Rect2(wx, wy, ww, WALL * 0.52), wcol, true)
			draw_rect(Rect2(wx, wy, ww, WALL * 0.52), Color("#9fd4e8", 0.45), false, 1.0)
	# 房型标签：压低存在感（不再是主视觉）
	draw_string(Art.font(), inner.position + Vector2(6, 15), rtype, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#ffe6c2", 0.45))

## 室内陈设（Stardew 的"住着人"密度）：地毯 + 靠墙杂物。全确定性（_hash01(room_id:key)），纯渲染不进 digest。
func _draw_room_decor(rid: String, inner: Rect2, rtype: String) -> void:
	# 地毯：够大的房间才铺；按房型给花色
	if inner.size.x >= T * 2.5 and inner.size.y >= T * 2.0:
		var rw := inner.size.x * (0.42 + 0.16 * Sim._hash01(rid + ":rugw"))
		var rh := inner.size.y * (0.38 + 0.16 * Sim._hash01(rid + ":rugh"))
		var rug := Rect2(inner.get_center() - Vector2(rw, rh) * 0.5, Vector2(rw, rh))
		var rc := Color("#7d3f3f")
		if "quiet" in rtype: rc = Color("#3f4a7d")
		elif "parlor" in rtype or "cafe" in rtype: rc = Color("#6d5a2a")
		elif "work" in rtype or "shop" in rtype: rc = Color("#4f4a40")
		elif "wash" in rtype or "bath" in rtype: rc = Color("#2f5a5f")
		draw_rect(rug, rc.darkened(0.22), true)
		draw_rect(rug.grow(-4.0), rc, true)
		draw_rect(rug.grow(-4.0), rc.lightened(0.28), false, 1.0)
	# 靠墙杂物：2-4 件，沿内墙确定性摆放（小件、贴墙 → 不与床/桌打架）
	var n := 2 + int(Sim._hash01(rid + ":clutn") * 3.0)
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var side := int(Sim._hash01(rid + ":side" + str(i)) * 3.0)
		var p := Vector2.ZERO
		match side:
			0: p = Vector2(inner.position.x + T * 0.34, inner.position.y + t * inner.size.y)
			1: p = Vector2(inner.end.x - T * 0.34, inner.position.y + t * inner.size.y)
			_: p = Vector2(inner.position.x + t * inner.size.x, inner.position.y + T * 0.42)
		_draw_prop(p, int(Sim._hash01(rid + ":prop" + str(i)) * 4.0))

## 程序化小杂物：0=木箱 1=陶罐 2=书堆 3=盆栽（包里没有的就程序化画——docs/13 的老规矩）
func _draw_prop(p: Vector2, kind: int) -> void:
	var s := T * 0.30
	match kind:
		0:
			draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), Color("#6b4a2a"), true)
			draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), Color("#33220f"), false, 1.0)
			draw_line(Vector2(p.x - s * 0.5, p.y), Vector2(p.x + s * 0.5, p.y), Color("#8a6338"), 1.0)
		1:
			draw_circle(p, s * 0.44, Color("#8a5a3c"))
			draw_circle(p, s * 0.44, Color("#4a2c1a"))
			draw_circle(p - Vector2(0, s * 0.06), s * 0.36, Color("#9c6845"))
			draw_rect(Rect2(p.x - s * 0.15, p.y - s * 0.58, s * 0.30, s * 0.22), Color("#6b4028"), true)
		2:
			for k in 3:
				draw_rect(Rect2(p.x - s * 0.40, p.y + s * 0.26 - float(k) * 4.0, s * 0.80, 3.2),
					[Color("#7d3f3f"), Color("#3f5a7d"), Color("#6d6a2a")][k], true)
		_:
			draw_rect(Rect2(p.x - s * 0.26, p.y, s * 0.52, s * 0.34), Color("#8a5a3c"), true)
			draw_circle(p - Vector2(0, s * 0.16), s * 0.32, Color("#3f6b3a"))
			draw_circle(p - Vector2(s * 0.12, s * 0.26), s * 0.16, Color("#4f8048"))

func _draw_bed(base: Vector2) -> void:
	var x := base.x + 8.0
	var y := base.y + 5.0
	var w := float(T) - 16.0
	var h := float(T) - 8.0
	draw_rect(Rect2(x - 2, y - 2, w + 4, h + 4), Color("#6b4f33"), true)        # 木框
	draw_rect(Rect2(x, y, w, h), Color("#efe3c8"), true)                        # 床单
	draw_rect(Rect2(x + 2, y + 2, w - 4, 9), Color("#ffffff"), true)            # 枕头
	draw_rect(Rect2(x, y + 13, w, h - 13), Color("#cf6b6b"), true)              # 被子
	draw_rect(Rect2(x, y + 13, w, 3), Color("#a85050"), true)                   # 被沿
	draw_rect(Rect2(x - 2, y - 2, w + 4, h + 4), Color(0, 0, 0, 0.35), false, 1.5)

## 程序化像素灶台（顶视角）：炉体 + 灶面 + 火眼(一只点火) + 烤箱门。
func _draw_stove(base: Vector2) -> void:
	var x := base.x + 9.0
	var y := base.y + 9.0
	var w := float(T) - 18.0
	var h := float(T) - 16.0
	draw_rect(Rect2(x, y, w, h), Color("#3b3b44"), true)                        # 炉体
	draw_rect(Rect2(x + 2, y + 2, w - 4, h - 11), Color("#55555f"), true)       # 灶面
	draw_circle(Vector2(x + 8, y + 8), 3.5, Color("#23232b"))                   # 火眼1
	draw_circle(Vector2(x + w - 8, y + 8), 3.5, Color("#ff8c3a"))               # 火眼2(点火)
	draw_circle(Vector2(x + w - 8, y + 8), 1.6, Color("#ffd166"))
	draw_rect(Rect2(x + 3, y + h - 7, w - 6, 5), Color("#26262d"), true)        # 烤箱门
	draw_rect(Rect2(x, y, w, h), Color(0, 0, 0, 0.35), false, 1.5)

## Wave 2b 节日灯笼（暖光晕 + 灯身 + 挑杆），一眼可辨"这里在办节日"。纯渲染。
func _draw_festival(base: Vector2) -> void:
	var c := base + Vector2(T * 0.5, T * 0.5)
	# 呼吸光晕（用 tick 相位做确定性明暗，不引 RNG）
	var pulse := 0.35 + 0.12 * sin(float(Sim.tick_no) * 0.15)
	draw_circle(c, T * 0.55, Color(1.0, 0.72, 0.30, pulse * 0.5))
	draw_circle(c, T * 0.34, Color(1.0, 0.80, 0.40, pulse))
	# 挑杆
	draw_line(base + Vector2(T * 0.5, 2), c + Vector2(0, -T * 0.18), Color("#6b4a2a"), 2.0)
	# 灯身（红灯笼）
	var lw := T * 0.30
	var lh := T * 0.34
	draw_rect(Rect2(c.x - lw * 0.5, c.y - lh * 0.35, lw, lh), Color("#d8443a"), true)
	draw_rect(Rect2(c.x - lw * 0.5, c.y - lh * 0.35, lw, lh), Color("#ffd88a"), false, 1.5)
	draw_line(Vector2(c.x, c.y + lh * 0.55), Vector2(c.x, c.y + lh * 0.78), Color("#ffd166"), 2.0)  # 流苏
	draw_string(Art.font(), c + Vector2(-7, -lh * 0.55 - 4), "灯会", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffe08a"))

func _draw_urgent_need(center: Vector2, ag: Dictionary) -> void:
	var worst := 100.0
	var worst_id := ""
	for nid in ag["needs"]:
		var v := float(ag["needs"][nid])
		if v < worst:
			worst = v
			worst_id = nid
	if worst_id == "":
		return
	var bar := Rect2(center.x - 16, center.y + 30, 32, 4)
	draw_rect(bar, Color(0, 0, 0, 0.5), true)
	var frac := clampf(worst / 100.0, 0.0, 1.0)
	var c := Color("#7ed957") if worst > 35.0 else Color("#e85a5a")
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), c, true)

func _in_conflict(id: String) -> bool:
	for c in Sim.conflicts:
		var s := String(c["status"])
		if (s == "simmering" or s == "escalated" or s == "confronted" or s == "lingering") and (c["a"] == id or c["b"] == id):
			return true
	return false

func _has_meet(id: String) -> bool:
	for c in Sim.commitments:
		if String(c["status"]) == "active" and (c["a"] == id or c["b"] == id):
			return true
	return false
