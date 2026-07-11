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
	for nm in ["tree_big", "tree_small", "bush", "flower_red", "flower_yellow", "flower_white", "rock", "stump", "mushroom"]:
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
			if _in_area(x, y) or _is_object(x, y):
				continue
			if _hash(x, y, 7) % 100 >= 22:   # ~22% 密度
				continue
			var r := _hash(x, y, 13) % total_w
			for p in pool:
				r -= int(p["w"])
				if r < 0:
					_decor_items.append({"tex": p["t"], "cell": Vector2i(x, y), "h": int(p["h"])})
					break

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

func _draw() -> void:
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

	# 区域块（半透明，让草地透出）+ 标签
	for area in Sim.world.get("areas", {}):
		var a: Dictionary = Sim.world["areas"][area]
		var r: Array = a.get("rect", [0, 0, 0, 0])
		var rect := Rect2(r[0] * T, r[1] * T, r[2] * T, r[3] * T)
		var ac := Art.area_color(area); ac.a = 0.32
		draw_rect(rect, ac, true)
		draw_string(Art.font(), Vector2(rect.position.x + 6, rect.position.y + 20), str(a.get("label", area)), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.55))
	# 室内房间（docs/16 / docs/19 §9 呈现）：画成"切开屋顶的俯视室内"——按房型上色的地板+木纹、立体墙(内暗影+亮墙沿)、
	# 屋檐暗边、有人在内时暖光（"此刻有人住着"）。纯渲染，台词/占用不进 digest，红线不动。
	for rid in Sim.world.get("rooms", {}):
		var rm: Dictionary = Sim.world["rooms"][rid]
		var rr: Array = rm.get("rect", [0, 0, 0, 0])
		var rrect := Rect2(rr[0] * T, rr[1] * T, rr[2] * T, rr[3] * T)
		var rtype := str(rm.get("type", rid))
		var enclosed := bool(rm.get("enclosed", false))
		# 地板：按房型上色，比开阔地实 → 读作"室内地面"
		var floor := Color("#6b4a2f", 0.52)
		if "bed" in rtype: floor = Color("#7a5230", 0.60)
		elif "parlor" in rtype or "cafe" in rtype: floor = Color("#7a5838", 0.58)
		elif "work" in rtype: floor = Color("#565248", 0.60)
		elif "quiet" in rtype: floor = Color("#544a66", 0.56)
		elif "wash" in rtype or "bath" in rtype: floor = Color("#3a5a5f", 0.56)
		elif "shop" in rtype: floor = Color("#6f5528", 0.58)
		draw_rect(rrect, floor, true)
		# 木纹：几条横向暗线（地板质感）
		var py := rrect.position.y + T
		while py < rrect.end.y - 1.0:
			draw_line(Vector2(rrect.position.x + 1, py), Vector2(rrect.end.x - 1, py), Color(0, 0, 0, 0.09), 1.0)
			py += T
		# 立体墙：内暗影(墙厚) + 亮墙沿(enclosed 更亮)
		draw_rect(rrect.grow(-2.0), Color(0, 0, 0, 0.22), false, 3.0)
		var edge := Color("#e0bc82") if enclosed else Color(0.9, 0.9, 0.9, 0.42)
		draw_rect(rrect, edge, false, 2.5)
		# 屋檐：顶边暗檐（暗示屋顶被切开=这是室内）
		draw_rect(Rect2(rrect.position, Vector2(rrect.size.x, 5.0)), Color(0, 0, 0, 0.28), true)
		# 有人在内 → 暖光（人越多越暖）
		var occ := 0
		for ag in Sim.agents:
			if rrect.has_point(Vector2(ag["pos"].x * T + T * 0.5, ag["pos"].y * T + T * 0.5)):
				occ += 1
		if occ > 0:
			draw_rect(rrect, Color("#ffdca0", 0.05 + minf(0.11, occ * 0.045)), true)
		draw_string(Art.font(), rrect.position + Vector2(6, 16), ("🚪 " if enclosed else "") + rtype, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffe6c2"))
	# 网格线
	for x in range(w + 1):
		draw_line(Vector2(x * T, 0), Vector2(x * T, h * T), Art.grid_line, 1.0)
	for y in range(h + 1):
		draw_line(Vector2(0, y * T), Vector2(w * T, y * T), Art.grid_line, 1.0)
	# 区域地标：每个区角放一座小屋（让分区像"街区"）
	var hut := Art.building_tex("hut")
	if hut != null:
		var hw := float(hut.get_width()) * (float(T) / 16.0)
		var hh := float(hut.get_height()) * (float(T) / 16.0)
		for area in Sim.world.get("areas", {}):
			var rr: Array = Sim.world["areas"][area].get("rect", [0, 0, 1, 1])
			var bx := int(rr[0])
			var by := int(rr[1])
			draw_texture_rect_region(hut, Rect2(bx * T + 3, (by + 1) * T - hh, hw, hh), Rect2(0, 0, hut.get_width(), hut.get_height()))

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
		_draw_agent(ag)

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
