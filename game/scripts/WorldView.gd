extends Node2D
## WorldView.gd — 纯订阅者像素渲染（不持有权威状态，全部读 Sim）。
## 范式同《小鱼岛》GameScreen：监听 Sim 信号 → queue_redraw；占位用程序化色块，M5 换正式像素美术。
## M1 增量：把「看不见的社交戏剧」画出来——关系连线 / 对话连线 / 冲突⚡ / 约见标记 / 台词气泡。

const T := 48  # 与 Art.TILE 一致
const EMOTE_TICKS := 24  # 头顶 emote 显示时长

# ── 整数像素尺（TEXTURE_FILTER_NEAREST 下的"不融化"前提）────────────────────────
# 地面/装饰一直是 T/16 = 3x 整数倍，可角色曾按 32→46(1.4375x)、物件 16→40(2.5x)、emote 20→26(1.3x) 画：
# nearest 采样下这些非整数倍让一部分源像素占 1 个屏幕像素、另一部分占 2 个 → 精灵在清晰的地形上读作"融化的"。
# 全部改成整数倍后，一个源像素恒等于 N 个屏幕像素。
const AGENT_PX := 64.0   # 32px 源帧 × 2
const EMOTE_PX := 40.0   # 20px 源帧 × 2
const OBJ_PX := 48.0     # 16px 源帧 × 3（= T，与地面/装饰同一个像素尺）
# 角色源帧 32x32 里人物实际占的行区间（用 alpha bbox 实测：y 5..24，x 9..23）。
# 用它把【脚】对齐落脚线、把【头顶】算出来给名字/emote 让位——不然放大后人会"浮"在影子上方。
const CHAR_FEET_ROW := 24.0
const CHAR_HEAD_ROW := 5.0

# ── 画面 LOD / 裁剪（纯 DRAW 侧）────────────────────────────────────────────────
# ★红线：本节的一切【只决定画什么】，绝不回喂 Sim——不写 Sim.lod_focus、不改 Sim 任何字段。
#   机器门：game/bench/lod_verify.gd（tools/ci.sh 步骤 4b）拿 5 个不同 lod_focus 跑，digest 必须逐字节相同。
const LABEL_MIN_ZOOM := 0.45   # 低于此缩放：名字/气泡/emote/需求条一律不画（那时它们只是几像素糊斑，白烧填充率）
var _vis := Rect2()            # 本帧可见世界矩形（每帧 _draw 开头刷新）
var _zoom := 1.0               # 本帧 世界→屏幕 缩放

# ── 关系连线（S1 起最贵也最乱的一层）──────────────────────────────────────────
enum RelMode { ALL, SELECTED, OFF }
const REL_TOP_K := 3           # 每人只保留最强的 K 条（一条边在任一端的 top-K 里就留 → 强关系不会被单侧挤掉）
const REL_MIN_AFF := 20.0
const REL_FADE_PX := 520.0     # 屏幕长度超过它开始变淡：横穿全镇的长线信息密度最低，却最挡视线
var rel_mode: int = RelMode.ALL   # Main 可直接改这个属性（本 baton 不动 Main，故不加键位）

var _prev_pos := {}      # id -> Vector2i（推断朝向/行走）

# ── 居民插值（渲染时钟，不是 tick 时钟）────────────────────────────────────────
# Sim 的位置是【格】，而 tick_interval=0.08 ⇒ 居民每秒瞬移 12.5 次、每次整整 T=48 像素。
# 这里在 View 内维护一份【渲染坐标】，在 _process(delta) 里向格心 lerp；Sim 一个字节都不碰。
# ★红线（本文件 :22）：_render_pos 只喂【绘制】。所有裁剪/LOD 判定一律仍按 Sim 的精确格心 _center()
#   算——否则"画什么"就会依赖上一帧的渲染残余，观察无关性从纯函数退化成有状态的。
# ★冻结 tick 的 --shot 必须与未插值版逐字节相同（docs/43 C1 验收）：靠 SNAP_PX 硬吸附保证，
#   不靠"指数收敛到浮点精度以下"这种概率性论证。
const LERP_FRACTION := 0.60    # 在一格【实际耗时】的 60% 内走完 → 跟得上 x8 加速，也不拖影
const SNAP_PX := 0.05          # 收敛阈值：小于它直接吸附到精确格心
const TELEPORT_TILES := 3.0    # 超过它视为瞬移（换 Space / 时间轴跳转 / 读档 / 换 N）→ 直接吸附，不横穿全镇滑行
var _render_pos := {}          # id -> Vector2（纯渲染坐标）
var _moving := {}              # id -> bool（是否仍在追格心；行走帧靠它）
var _walk_row := {}            # id -> int（行走帧行号，进入移动时锁定）
var _emote := {}         # id -> {tex, until}
var _say := {}           # id -> {text, until}（对话罐头台词；M2 换 LLM 生成）
const SAY_TICKS := 40

# L6 调色板变体（docs/12）：扩 N 的克隆(id=npc_*)复用 6 张 CC0 精灵，用确定性色相旋转让每个各不相同
# → 视觉数量线性增长、零新增 PNG、零版权、完全可复现。命名 6 人(aria..fei)零位移保留正典外观；6 人小镇本层休眠。
# 实现：首次用到时把精灵 CPU 色相旋转成一张 ImageTexture 变体并缓存（Godot 4 immediate-mode 无法 per-draw 换 material）。
const HUE_BUCKETS := 24   # 色相分桶数（bucket0=原图）
var _hued := {}          # "sprite#bucket" -> ImageTexture（懒建缓存）

## 实际被采样的表区域：_agent_frame 只取 col 0-3 / row 0-3（idle+行走三向），即左上角 128x128。
## 整张表是 768x256 = 196,608 像素，而用到的只有 16,384——旧实现每建一个色相变体都要 GDScript 逐像素扫全表
## （12x 空转 + 每变体多留 ~720 KB），且变体是扩 N 时【边玩边建】的，卡顿正好落在最需要帧时间的时候。
## 裁到用到的区域即可：变体纹理与原图共用左上角坐标系，src Rect2(col*32,row*32,32,32) 两边通用，取帧代码一行不用改。
const CHAR_USED := Vector2i(128, 128)

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
	var rw := mini(CHAR_USED.x, img.get_width())
	var rh := mini(CHAR_USED.y, img.get_height())
	img = img.get_region(Rect2i(0, 0, rw, rh))     # 只留被采样的左上角帧区（12x 少扫、~12x 少留内存）
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
var _path_set := {}      # idx(y*W+x) -> true（土路格：广场↔各家门口；渲染 + 装饰避让）
var _paths_built := false
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
## 分类型【地板】：与 BLD_PAL 的墙色同族但更亮（屋顶被切掉，地面才是受光面）。
## 旧版只有广场有真地板，其余七个区只压一层 0.10 alpha 的淡色罩 —— 于是每栋建筑读作"围了圈墙的草坪院子"，
## 床和灶台直接摆在草上。这是整镇"灰盒原型感"的头号来源，而它整个在 View 层。
const FLOOR_PAL := {
	"residential": {"base": Color("#c8a273"), "line": Color("#9c7748"), "mode": "plank"},   # 暖木地板
	"commercial":  {"base": Color("#bf9257"), "line": Color("#8c6533"), "mode": "plank"},   # 深一档的店面木地板
	"public":      {"base": Color("#96a5ab"), "line": Color("#6c7b83"), "mode": "slab"},    # 冷灰石板（澡堂/图书馆）
	"workshop":    {"base": Color("#9b968d"), "line": Color("#6d6a61"), "mode": "slab"},    # 暖灰石板（工坊）
	"plaza":       {"base": Color("#c3a97a"), "line": Color("#9a8253"), "mode": "paving"},  # 中央广场铺装
}

# ── 四季与天气（Wave C）──────────────────────────────────────────────────────
# Sim.season_today / Sim.weather_today 每天边界都在算并进效用乘子（Sim.gd:1076-1078、:2305、:2322），
# 而本文件里这两个词此前【零命中】—— 也就是说仿真里换了季，屏幕上逐像素相同。
# 这里只【读】它们，纯 View：veg = 植被（草地/花草/树）的乘算色偏；wash = 压在地形与建筑之上、
# 居民之下的大气罩（乘算做不出"冬天发白"，必须靠叠加）。缺数据文件时两者都是恒等，画面回到今天。
const SEASON_VEG := {
	"春": Color(1.00, 1.06, 0.90),   # 新绿，略偏黄
	"夏": Color(0.88, 1.00, 0.72),   # 深浓
	"秋": Color(1.22, 0.98, 0.60),   # 金黄（第一版 1.32/0.52 眼验偏芥末，压了一档）
	"冬": Color(0.84, 0.92, 1.00),   # 冷、褪色
}
const SEASON_WASH := {
	"春": Color(0.62, 0.90, 0.48, 0.05),
	"夏": Color(1.00, 0.90, 0.42, 0.06),
	"秋": Color(0.95, 0.58, 0.22, 0.10),
	"冬": Color(0.80, 0.89, 1.00, 0.24),   # 霜白：多亏了它，冬天才不是"绿得冷一点"
}
const WEATHER_WASH := {
	"阴": Color(0.52, 0.57, 0.64, 0.16),
	"雨": Color(0.34, 0.45, 0.62, 0.24),
}

func _season_veg() -> Color:
	return SEASON_VEG.get(Sim.season_today, Color.WHITE)

## 季节 + 天气的大气罩，画在地形/建筑之上、居民之下。只覆盖【地图矩形 ∩ 视口】——
## 界外暗林不跟着变季，否则夜林会被冬天的霜白刷成灰板。
func _draw_climate_wash(w: int, h: int) -> void:
	var area := Rect2(0.0, 0.0, float(w) * T, float(h) * T).intersection(_vis)
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return
	var sw: Color = SEASON_WASH.get(Sim.season_today, Color(0, 0, 0, 0))
	if sw.a > 0.0:
		draw_rect(area, sw, true)
	var ww: Color = WEATHER_WASH.get(Sim.weather_today, Color(0, 0, 0, 0))
	if ww.a > 0.0:
		draw_rect(area, ww, true)

## 雨丝。确定性：位置来自 _hash(gx,gy)，下落相位来自 Sim.tick_no —— 不抽 RNG、不读墙钟，
## 于是【同一 tick 重拍逐像素相同】（--shot 冻结 tick，将来做视觉 CI 断言时才有可比性）。
func _draw_rain() -> void:
	var cell := T * 1.5
	var gx0 := int(floor(_vis.position.x / cell)); var gx1 := int(ceil(_vis.end.x / cell))
	var gy0 := int(floor(_vis.position.y / cell)); var gy1 := int(ceil(_vis.end.y / cell))
	if (gx1 - gx0) * (gy1 - gy0) > VOID_DECOR_MAX_CELLS:
		return                                    # 极端缩放：雨丝细到看不见，白烧填充率（红线#3 手机）
	var phase := float(Sim.tick_no % 6) / 6.0
	var col := Color(0.80, 0.89, 1.00, 0.30)
	for gy in range(gy0, gy1):
		for gx in range(gx0, gx1):
			var hsh := _hash(gx, gy, 57)
			if hsh % 100 >= 36:
				continue
			var p := Vector2((float(gx) + float(hsh % 61) / 61.0) * cell,
				(float(gy) + float(hsh / 61 % 61) / 61.0 + phase) * cell)
			draw_line(p, p + Vector2(-T * 0.15, T * 0.40), col, 1.5)

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
	if not _paths_built:
		_build_paths()                    # 先有路，散装饰时才能避开它
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
			if _in_area(x, y) or _is_object(x, y) or _is_blocked(x, y) or _path_set.has(y * w + x):
				continue                      # 区域/家具/阻挡/土路 上都不散装饰（路面保持干净）
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

## P3 打磨：土路网——每家门口通到中央广场。L 形（先垂直离开建筑、再拐向广场），只铺在可走格上。
## 纯渲染（map.json 的 doors 层是渲染用、不进导航/digest）；装饰会避开土路，路面才干净。
func _build_paths() -> void:
	_paths_built = true
	_path_set.clear()
	var areas: Dictionary = Sim.world.get("areas", {})
	if not areas.has("plaza"):
		return
	var pr: Array = (areas["plaza"] as Dictionary).get("rect", [0, 0, 0, 0])
	var px0 := int(pr[0]); var py0 := int(pr[1])
	var px1 := px0 + int(pr[2]) - 1; var py1 := py0 + int(pr[3]) - 1
	var wd: int = int(Sim.world.get("width", 24))
	var outdir := {"S": Vector2i(0, 1), "N": Vector2i(0, -1), "W": Vector2i(-1, 0), "E": Vector2i(1, 0)}
	for d in Sim.world.get("doors", []):
		var dp: Array = (d as Dictionary).get("pos", [0, 0])
		var od: Vector2i = outdir.get(String((d as Dictionary).get("face", "S")), Vector2i(0, 1))
		var cur := Vector2i(int(dp[0]), int(dp[1])) + od           # 门外第一格（不铺在门格本身）
		var gx: int = clampi(cur.x, px0, px1)                      # 广场最近的 x/y 带
		var gy: int = clampi(cur.y, py0, py1)
		while cur.y != gy:                                         # 竖腿：先离开建筑
			if not _is_blocked(cur.x, cur.y): _path_set[cur.y * wd + cur.x] = true
			cur.y += signi(gy - cur.y)
		while cur.x != gx:                                         # 横腿：再拐向广场
			if not _is_blocked(cur.x, cur.y): _path_set[cur.x + cur.y * wd] = true
			cur.x += signi(gx - cur.x)
		if not _is_blocked(cur.x, cur.y): _path_set[cur.y * wd + cur.x] = true

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

## P3 打磨：外墙细节——沿上/下墙等距开窗（跳过转角与门口），住宅/工坊再加一根冒烟的烟囱。
## 夜里窗透暖光（tod 判昼夜）→ 一眼看出"屋里有人住"。纯渲染、无 RNG（位置由 rect 等距推出）。
func _draw_facades() -> void:
	var doorset := {}
	for d in Sim.world.get("doors", []):
		var dp: Array = (d as Dictionary).get("pos", [0, 0])
		doorset[Vector2i(int(dp[0]), int(dp[1]))] = true
	var tod := Sim.time_of_day()
	var night := tod < 0.24 or tod > 0.78
	for aid in Sim.world.get("areas", {}):
		var a: Dictionary = Sim.world["areas"][aid]
		var typ := String(a.get("type", ""))
		if typ == "" or typ == "plaza":
			continue
		var pal: Dictionary = BLD_PAL.get(typ, BLD_PAL["workshop"])
		var r: Array = a.get("rect", [0, 0, 0, 0])
		var x0 := int(r[0]); var y0 := int(r[1]); var bw := int(r[2]); var bh := int(r[3])
		for i in range(1, bw - 1):                       # 跳过两端转角
			if i % 2 == 0:
				continue                                 # 等距（隔一格）开窗
			for wy in [y0, y0 + bh - 1]:                 # 上墙 + 下墙
				if doorset.has(Vector2i(x0 + i, wy)):
					continue                             # 门口不开窗
				_draw_window((x0 + i) * T, wy * T, pal, night)
		for j in range(1, bh - 1):                       # 左墙 + 右墙（四面都开，别只有正背面有细节）
			if j % 2 == 0:
				continue
			for wx in [x0, x0 + bw - 1]:
				if doorset.has(Vector2i(wx, y0 + j)):
					continue
				_draw_window(wx * T, (y0 + j) * T, pal, night)
		if typ == "residential" or typ == "workshop":    # 烟囱：坐在顶墙右段，飘两团烟
			var chx := float(x0 + bw - 2) * T
			var chy := float(y0) * T
			draw_rect(Rect2(chx + T * 0.28, chy - T * 0.52, T * 0.4, T * 0.5), Color("#6b4a2b"), true)
			draw_rect(Rect2(chx + T * 0.24, chy - T * 0.58, T * 0.48, T * 0.13), Color("#4c3a28"), true)
			draw_circle(Vector2(chx + T * 0.5, chy - T * 0.8), T * 0.11, Color(0.86, 0.86, 0.86, 0.40))
			draw_circle(Vector2(chx + T * 0.63, chy - T * 1.02), T * 0.085, Color(0.86, 0.86, 0.86, 0.26))

func _draw_window(x: float, y: float, pal: Dictionary, night: bool) -> void:
	var glass: Color = Color("#f2d489") if night else Color("#5d7f96")   # 夜=透暖光 / 昼=映天色
	draw_rect(Rect2(x + T * 0.22, y + T * 0.24, T * 0.56, T * 0.44), pal["foot"], true)            # 窗洞（深）
	draw_rect(Rect2(x + T * 0.26, y + T * 0.28, T * 0.48, T * 0.36), glass, true)                  # 玻璃
	if night:
		draw_rect(Rect2(x + T * 0.16, y + T * 0.18, T * 0.68, T * 0.56), Color(0.98, 0.85, 0.55, 0.15), true)  # 外溢暖光
	draw_line(Vector2(x + T * 0.5, y + T * 0.28), Vector2(x + T * 0.5, y + T * 0.64), pal["foot"], 1.5)        # 竖棂
	draw_line(Vector2(x + T * 0.26, y + T * 0.46), Vector2(x + T * 0.74, y + T * 0.46), pal["foot"], 1.5)      # 横棂
	draw_rect(Rect2(x + T * 0.22, y + T * 0.24, T * 0.56, T * 0.44), (pal["top"] as Color).lightened(0.18), false, 1.5)  # 窗框

## 本帧的可见世界矩形 + 世界→屏幕缩放（纯读画布变换）。裁剪与标签 LOD 都吃它。
## ★这是【画】的裁剪，不是【算】的裁剪：Sim 看不到它，lod_verify 的相机无关门因此不受影响。
func _refresh_view_metrics() -> void:
	var ct := get_global_transform_with_canvas()
	var sc := ct.get_scale()
	_zoom = maxf(0.0001, (absf(sc.x) + absf(sc.y)) * 0.5)
	var inv := ct.affine_inverse()
	var vs: Vector2 = get_viewport_rect().size
	var r := Rect2(inv * Vector2.ZERO, Vector2.ZERO)
	r = r.expand(inv * Vector2(vs.x, 0.0)).expand(inv * Vector2(0.0, vs.y)).expand(inv * vs)
	_vis = r.grow(T * 2.0)          # 留两格余量：贴边的精灵/连线不会在边缘闪掉

## 每个 district 铺【真地板】：dirt 瓦片打底（保住 3x 像素颗粒，纯色地板在像素游戏里读作"没画完"）
## → 类型底色半透盖上 → 类型纹样（木条 / 石板 / 铺装）→ 内缘压暗让地板"沉"进墙里。
## 只读 Sim.world['areas']，不改 game/data/**、不造房间。
func _draw_area_floors(dirt: Texture2D) -> void:
	for aid in Sim.world.get("areas", {}):
		var a: Dictionary = Sim.world["areas"][aid]
		var r: Array = a.get("rect", [0, 0, 0, 0])
		var x0 := int(r[0]); var y0 := int(r[1]); var bw := int(r[2]); var bh := int(r[3])
		if bw <= 0 or bh <= 0:
			continue
		var rect := Rect2(x0 * T, y0 * T, bw * T, bh * T)
		if not _vis.intersects(rect):
			continue
		var pal: Dictionary = FLOOR_PAL.get(String(a.get("type", "")), FLOOR_PAL["workshop"])
		var base: Color = pal["base"]
		var line: Color = pal["line"]
		if dirt != null:
			for yy in range(y0, y0 + bh):
				for xx in range(x0, x0 + bw):
					draw_texture_rect(dirt, Rect2(xx * T, yy * T, T, T), false)
			draw_rect(rect, Color(base.r, base.g, base.b, 0.80), true)
		else:
			draw_rect(rect, base, true)
		match String(pal["mode"]):
			"plank":                                   # 木地板：半格宽长板 + 错缝短接头
				var py := rect.position.y
				var row := 0
				while py < rect.end.y - 1.0:
					draw_rect(Rect2(rect.position.x, py, rect.size.x, 1.0), Color(line.r, line.g, line.b, 0.50), true)
					var sx := rect.position.x + (T * 0.5 if row % 2 == 1 else 0.0) + T
					while sx < rect.end.x - 1.0:
						draw_rect(Rect2(sx, py, 1.0, T * 0.5), Color(line.r, line.g, line.b, 0.34), true)
						sx += T * 1.5
					py += T * 0.5
					row += 1
			"slab":                                    # 石板：交错明暗方砖 + 横竖石缝
				for yy in range(bh):
					for xx in range(bw):
						if (xx + yy) % 2 == 0:
							draw_rect(Rect2(rect.position.x + xx * T, rect.position.y + yy * T, T, T), Color(1, 1, 1, 0.08), true)
					draw_rect(Rect2(rect.position.x, rect.position.y + yy * T, rect.size.x, 1.0), Color(line.r, line.g, line.b, 0.42), true)
				for xx in range(bw):
					draw_rect(Rect2(rect.position.x + xx * T, rect.position.y, 1.0, rect.size.y), Color(line.r, line.g, line.b, 0.32), true)
			_:                                         # 广场：大方砖十字缝（比土路"踩实"，两者可区分）
				for yy in range(bh):
					draw_rect(Rect2(rect.position.x, rect.position.y + yy * T, rect.size.x, 1.0), Color(line.r, line.g, line.b, 0.28), true)
				for xx in range(bw):
					draw_rect(Rect2(rect.position.x + xx * T, rect.position.y, 1.0, rect.size.y), Color(line.r, line.g, line.b, 0.28), true)
		draw_rect(rect, Color(0, 0, 0, 0.20), false, 3.0)

## 区名：旧版画在 rect 左上角、字号 12、alpha 0.28 —— 那格正好是顶墙，墙随后盖上去，于是【一个字也看不见】。
## 现在画在墙之后、地板第一行上，并把字号按缩放反比放大 → 缩到全镇俯瞰时区名仍读得出来（这才是"地图可读"）。
func _draw_area_labels() -> void:
	var fnt := Art.font()
	var fs := int(clampf(13.0 / _zoom, 13.0, 52.0))
	for aid in Sim.world.get("areas", {}):
		var a: Dictionary = Sim.world["areas"][aid]
		var r: Array = a.get("rect", [0, 0, 0, 0])
		if int(r[2]) <= 0 or int(r[3]) <= 0:
			continue
		var rect := Rect2(int(r[0]) * T, int(r[1]) * T, int(r[2]) * T, int(r[3]) * T)
		if not _vis.intersects(rect):
			continue
		var txt := str(a.get("label", aid))
		var sz := fnt.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var p := Vector2(rect.get_center().x - sz.x * 0.5, rect.position.y + T * 1.10 + sz.y * 0.5)
		draw_rect(Rect2(p.x - 6.0, p.y - sz.y + 2.0, sz.x + 12.0, sz.y + 3.0), Color(0, 0, 0, 0.42), true)
		draw_string(fnt, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.82))

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
## 行走帧/朝向。★这里【不再有副作用】——朝向与 _prev_pos 的推进整体搬到了 _process()。
## 原因：加插值后 _draw 从"每 tick 一次"变成"每帧一次"，而旧实现是在 _draw 里做 pos 差分并
## 就地更新 _prev_pos，于是移动后的第 2 帧起差分恒为零 → 居民一边滑行一边播 idle（动画反而更糟）。
## 现在"是否在走"= 渲染坐标是否还在追格心（_moving），动画与插值同寿。
func _agent_frame(ag: Dictionary) -> Dictionary:
	var id := String(ag["id"])
	var flip := bool(_facing_left.get(id, false))
	if not bool(_moving.get(id, false)):
		return {"col": int(Sim.tick_no / 16.0) % 4, "row": 0, "flip": flip}  # idle 微动，保留上次朝向
	return {"col": Sim.tick_no % 4, "row": int(_walk_row.get(id, 1)), "flip": flip}

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

## 室内背景。一层至多 432x336 px，塞进 1280x768 后四周是一大片【默认 clear color 的死灰】
## （docs/media/shot-p3-patrons-cafe.png 里那条灰带就是它）。铺暗底 + 四周暗角 + 房子外圈落影 + 极淡暖边，
## 读法变成"镜头在屋外的暗处往里看"，而不是"一个方块浮在空白画布上"。纯 View。
func _draw_interior_backdrop(main: Node, probe) -> void:
	draw_rect(_vis, Color("#0e1017"), true)
	# 暗角：由外向内 6 圈，越外越沉（随后室内地板会不透明地盖回中间，暗角只作用在虚空上）
	var bw := minf(_vis.size.x, _vis.size.y) * 0.05
	for k in 6:
		var inset := float(k) * bw
		var vg := Color(0, 0, 0, 0.10 * (1.0 - float(k) / 6.0))
		var iw := _vis.size.x - inset * 2.0
		var ih := _vis.size.y - inset * 2.0
		if iw <= 0.0 or ih <= 0.0:
			break
		draw_rect(Rect2(_vis.position.x + inset, _vis.position.y + inset, iw, bw), vg, true)
		draw_rect(Rect2(_vis.position.x + inset, _vis.end.y - inset - bw, iw, bw), vg, true)
		draw_rect(Rect2(_vis.position.x + inset, _vis.position.y + inset, bw, ih), vg, true)
		draw_rect(Rect2(_vis.end.x - inset - bw, _vis.position.y + inset, bw, ih), vg, true)
	var sg = main.get("_sg") if main != null else null
	if sg == null:
		return
	var b: Rect2 = sg.bounds_px(String(probe.active_space))
	for k in range(8, 0, -1):                       # 外圈落影：由外向内叠，越贴墙越暗 → 房子"坐"在暗处
		draw_rect(b.grow(float(k) * 9.0), Color(0, 0, 0, 0.06), true)
	draw_rect(b.grow(4.0), Color("#f2dca8", 0.07), true)   # 极淡暖边：屋里透出来的一点光

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
	# 地板：按 interiors.json 的 floor 材质画（wood=暖木条纹 / stone=冷灰石板缝）→ 澡堂/工坊/图书馆一进门就和木屋不同
	if String(content.get("floor", "wood")) == "stone":
		draw_rect(b, Color("#9a9490"), true)
		for gy in range(hc):
			for gx in range(wc):
				if (gx + gy) % 2 == 0:
					draw_rect(Rect2(ox + gx * T, oy + gy * T, T, T), Color("#a8a29c", 0.55), true)   # 交错石板
		for gy in range(hc):
			draw_rect(Rect2(ox, oy + gy * T, b.size.x, 2), Color("#6f6a66", 0.45), true)             # 横缝
	else:
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
	# P3 打磨：夜间氛围（暖底光 + 每盏灯源暖池，占用的床更旺）——画在家具之上、居民之下，居民自身仍清晰
	_draw_interior_night(b, content, sid, fid)
	# P3 Tier-B：画【此刻真在这层】的居民（阿丽在自家咖啡馆睡觉/看摊）。Space bounds 从原点起 → _draw_agent 用
	# ag.pos*T 的室内局部坐标即落在本层画面里。纯 View、只读 ag 平面字段。
	for ag in Sim.agents:
		if String(ag.get("space", "town")) == sid and String(ag.get("floor", "outdoor")) == fid:
			_draw_agent(ag)
	# 楼层标签
	draw_string(Art.font(), b.position + Vector2(T + 8, 22), "%s · %s" % [sg.label_of(sid), content.get("label", fid)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#3a2a1a"))

## P3 打磨：室内夜间氛围。CanvasModulate 把整幅世界画布乘暗（室内也不例外）→ 夜里进屋本是【冷灰洞】：
## 暖木地板被夜蓝乘平。这里靠【相对暖光】把屋子从冷夜拉出来：整层压一层暖底光 + 每件光源家具
## （床/桌/吧台/咖啡机/书桌/灶）落一盏径向暖池；被人【占着】的（如睡在床上）那盏更旺 = 床头灯。
## 于是深夜点开住宅，一眼看出"这屋有人、亮着灯"。白昼无人 → 一笔不画（日间室内原样）。纯 View、只读、digest 不变。
func _draw_interior_night(b: Rect2, content: Dictionary, sid: String, fid: String) -> void:
	var night := _night_amt()
	var occ := 0
	var occ_cells := {}
	for ag in Sim.agents:
		if String(ag.get("space", "town")) == sid and String(ag.get("floor", "outdoor")) == fid:
			occ += 1
			occ_cells[Vector2i(ag["pos"])] = true
	var lit := 0.20 * night + minf(0.12, occ * 0.04) * (0.5 + 0.5 * night)
	if lit <= 0.001:
		return                                        # 白昼无人：日间室内保持原样
	draw_rect(b, Color("#ffbe63", lit), true)         # 暖底光：偏橙、被夜蓝乘过后仍咬得住暖调
	var ox := b.position.x; var oy := b.position.y
	var light_slots := {"bed": true, "table": true, "counter": true, "coffee": true, "desk": true, "stove": true}
	for fr in content.get("furniture", []):
		var slot := String((fr as Dictionary).get("slot", ""))
		if not light_slots.has(slot):
			continue
		var fp: Array = (fr as Dictionary).get("pos", [0, 0])
		var cell := Vector2i(int(fp[0]), int(fp[1]))
		# 有人占着这盏灯（同格或紧邻上下——睡在床上/坐在桌前）→ 更旺
		var occupied := occ_cells.has(cell) or occ_cells.has(cell + Vector2i(0, 1)) or occ_cells.has(cell + Vector2i(0, -1))
		var pool := 0.20 * night + (0.16 if occupied else 0.0)
		if pool <= 0.01:
			continue
		var cen := Vector2(ox + float(cell.x) * T + T * 0.5, oy + float(cell.y) * T + T * 0.5)
		for k in 4:                                   # 四层同心：内亮外淡，叠出"光源在这"的衰减
			var f := 1.0 - float(k) / 4.0
			draw_circle(cen, T * (0.55 + 0.5 * float(k)), Color("#ffd27a", pool * 0.14 * f))

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
		"bath":                                      # 浴池：石沿 + 水面 + 蒸汽
			draw_rect(Rect2(base.x + T * 0.1, base.y + T * 0.2, T * 0.8, T * 0.66), Color("#8b93a0"), true)
			draw_rect(Rect2(base.x + T * 0.17, base.y + T * 0.27, T * 0.66, T * 0.52), Color("#4f9dc4"), true)
			draw_rect(Rect2(base.x + T * 0.17, base.y + T * 0.27, T * 0.66, T * 0.12), Color("#8fd0e8", 0.8), true)
			draw_circle(Vector2(base.x + T * 0.36, base.y + T * 0.14), T * 0.07, Color(1, 1, 1, 0.35))
			draw_circle(Vector2(base.x + T * 0.6, base.y + T * 0.07), T * 0.055, Color(1, 1, 1, 0.22))
		"bench":                                     # 条凳：长座板 + 两腿
			draw_rect(Rect2(base.x + T * 0.08, base.y + T * 0.42, T * 0.84, T * 0.17), Color("#8a6238"), true)
			draw_rect(Rect2(base.x + T * 0.08, base.y + T * 0.42, T * 0.84, T * 0.05), Color("#a67f4e"), true)
			draw_rect(Rect2(base.x + T * 0.16, base.y + T * 0.59, T * 0.1, T * 0.24), Color("#5a3f28"), true)
			draw_rect(Rect2(base.x + T * 0.74, base.y + T * 0.59, T * 0.1, T * 0.24), Color("#5a3f28"), true)
		"crate":                                     # 木箱：板条 + 对角加固
			draw_rect(Rect2(base.x + T * 0.16, base.y + T * 0.3, T * 0.68, T * 0.56), Color("#9a7042"), true)
			draw_rect(Rect2(base.x + T * 0.16, base.y + T * 0.3, T * 0.68, T * 0.56), Color("#5a3f28"), false, 2.0)
			draw_line(Vector2(base.x + T * 0.16, base.y + T * 0.86), Vector2(base.x + T * 0.84, base.y + T * 0.3), Color("#5a3f28"), 2.0)
			draw_rect(Rect2(base.x + T * 0.16, base.y + T * 0.3, T * 0.68, T * 0.08), Color("#b5854e"), true)
		"stool":                                     # 圆凳
			draw_circle(Vector2(base.x + T * 0.5, base.y + T * 0.5), T * 0.22, Color("#8a6238"))
			draw_circle(Vector2(base.x + T * 0.5, base.y + T * 0.47), T * 0.18, Color("#a67f4e"))
			draw_rect(Rect2(base.x + T * 0.44, base.y + T * 0.62, T * 0.12, T * 0.22), Color("#5a3f28"), true)
		"stairs":                                    # 楼梯：斜阶
			for k in range(4):
				draw_rect(Rect2(base.x + T * 0.12 + k * T * 0.17, base.y + T * 0.62 - k * T * 0.13, T * 0.2, T * 0.15), Color("#7a6a52"), true)
				draw_rect(Rect2(base.x + T * 0.12 + k * T * 0.17, base.y + T * 0.62 - k * T * 0.13, T * 0.2, T * 0.04), Color("#9a8a70"), true)
		_:
			draw_rect(Rect2(base.x + 9, base.y + 12, T - 18, T - 18), Color("#8a6a45"), true)

var _rc_conflict_ids := {}   # 每帧预建：卷入活跃冲突的 agent 端点集（渲染缓存，_draw_agent 用 O(1) 查）
var _rc_meet_ids := {}       # 每帧预建：有活跃约会的 agent 端点集

## ── 界外虚空 ───────────────────────────────────────────────────────────────
## 全镇视角下地图矩形只占画面的一小半，其余是 Godot 未改的默认 clear color(#4d4d4d)：
## 小镇读作"灰色虚空里的一座孤岛"。室内早有解（_draw_interior_backdrop），小镇分支一直没有对应物——
## 草地被钳在 [0,w)x[0,h)（下面的 tx0..tx1/ty0..ty1），界外一个像素都没人画。
##
## ★这一层只画【地图矩形之外】：把 _vis 减去 map 得到上/下/左/右四条带，只在带里绘制。
##   R5 双向断言就靠这条 —— 界内必须逐像素不变（ImageChops bbox 完全落在地图矩形外）。
const VOID_BASE := Color("#0b1209")     # 深林底（与 project.godot 的 default_clear_color 同色）
const VOID_SPILL := Color("#8fb36a")    # 镇子漏进林子的那点光（贴着地图外缘最亮，向外熄灭）
const VOID_CANOPY_A := Color("#16301a")
const VOID_CANOPY_B := Color("#1e3d22")
const VOID_CANOPY_C := Color("#0f2413")
const VOID_SPILL_TILES := 6.0           # 光晕带宽（格）
const VOID_FADE_TILES := 22.0           # 从地图外缘到"全黑深林"的距离（格）
const VOID_DECOR_MAX_CELLS := 4096      # 装饰上限：极端缩放下只铺底色，不烧填充率（红线#3 手机）

## 点到矩形的最短距离（点在矩形内=0）。界外暗林用它做"离镇越远越黑越稀"的衰减。
func _rect_dist(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dy := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return sqrt(dx * dx + dy * dy)

func _draw_town_backdrop(w: int, h: int) -> void:
	var map := Rect2(0.0, 0.0, float(w) * T, float(h) * T)
	var v := _vis
	var bands: Array = []
	if v.position.y < map.position.y:
		bands.append(Rect2(v.position.x, v.position.y, v.size.x, map.position.y - v.position.y))
	if v.end.y > map.end.y:
		bands.append(Rect2(v.position.x, map.end.y, v.size.x, v.end.y - map.end.y))
	var my0 := maxf(v.position.y, map.position.y)
	var my1 := minf(v.end.y, map.end.y)
	if my1 > my0:
		if v.position.x < map.position.x:
			bands.append(Rect2(v.position.x, my0, map.position.x - v.position.x, my1 - my0))
		if v.end.x > map.end.x:
			bands.append(Rect2(map.end.x, my0, v.end.x - map.end.x, my1 - my0))
	if bands.is_empty():
		return                                  # 镜头完全在界内（跟随相机的常态）：一笔都不画
	for b in bands:
		draw_rect(b, VOID_BASE, true)
	# 镇子漏进林子的光：贴着地图外缘最亮、向外 8 圈熄灭。旧稿在这里放过一条【矩形青色岸带】，
	# 眼验读作"给地图加了个装饰边框"——硬边框是原型感的来源，换成柔性光晕就消失了。
	for k in range(8, 0, -1):
		var ring := map.grow(VOID_SPILL_TILES * T * (float(k) / 8.0))
		var a := 0.030 * (1.0 - float(k - 1) / 8.0)
		for b in bands:
			var seg := ring.intersection(b)
			if seg.size.x > 0.0 and seg.size.y > 0.0:
				draw_rect(seg, Color(VOID_SPILL.r, VOID_SPILL.g, VOID_SPILL.b, a), true)
	# 界外暗林：2 格粗粒度的确定性树冠（_hash，不抽 RNG、与相机无关）。太远的镜头只留底色。
	# 每格画【两丛】并给足抖动，否则规则网格会读成波点墙纸（第一版实测就是这个毛病）。
	var cell := T * 2.0
	var gx0 := int(floor(v.position.x / cell))
	var gy0 := int(floor(v.position.y / cell))
	var gx1 := int(ceil(v.end.x / cell))
	var gy1 := int(ceil(v.end.y / cell))
	var fade_px := VOID_FADE_TILES * T
	if _zoom >= 0.18 and (gx1 - gx0) * (gy1 - gy0) <= VOID_DECOR_MAX_CELLS:
		for gy in range(gy0, gy1):
			for gx in range(gx0, gx1):
				for sub in 2:
					var hsh := _hash(gx, gy, 91 + sub * 37)
					var c := Vector2(gx * cell, gy * cell) \
						+ Vector2(float(hsh % 97), float(hsh / 97 % 97)) * (cell / 97.0)
					if map.has_point(c):
						continue                # 界内不长树（R5：界内必须逐像素不变）
					# 离镇越远越黑越稀：林子要"退进夜里"，不是铺一层等密度的点
					var dist := _rect_dist(map, c)
					var lit := clampf(1.0 - dist / fade_px, 0.0, 1.0)
					if hsh / 9409 % 100 >= int(26.0 + 52.0 * lit):
						continue
					var r := cell * (0.30 + float(hsh / 11 % 9) * 0.030)
					var cc := VOID_CANOPY_A if hsh % 3 == 0 else (VOID_CANOPY_B if hsh % 3 == 1 else VOID_CANOPY_C)
					cc = cc.lerp(VOID_BASE, 1.0 - lit)      # 远处的树冠融进底色
					draw_circle(c, r, cc)
					if lit > 0.25:
						draw_circle(c + Vector2(-r * 0.28, -r * 0.32), r * 0.44,
							Color(cc.r, cc.g, cc.b, 0.50 * lit))   # 受光叶簇
	# 暗角：由地图外缘向外 6 圈加深 → 视线自然被收回镇子里
	for k in 6:
		var vg := Rect2(map).grow(VOID_SPILL_TILES * T + float(k + 1) * T * 2.6)
		var a := 0.050 + float(k) * 0.034
		# 逐圈压暗：只压 band 里落在这一圈【之外】的部分（四条外带），避免整片重复叠加
		for b in bands:
			var out_top := Rect2(b.position.x, b.position.y, b.size.x, maxf(0.0, vg.position.y - b.position.y))
			var out_bot := Rect2(b.position.x, maxf(b.position.y, vg.end.y), b.size.x, maxf(0.0, b.end.y - maxf(b.position.y, vg.end.y)))
			var iy0 := maxf(b.position.y, vg.position.y)
			var iy1 := minf(b.end.y, vg.end.y)
			var out_lft := Rect2(b.position.x, iy0, maxf(0.0, vg.position.x - b.position.x), maxf(0.0, iy1 - iy0))
			var out_rgt := Rect2(maxf(b.position.x, vg.end.x), iy0, maxf(0.0, b.end.x - maxf(b.position.x, vg.end.x)), maxf(0.0, iy1 - iy0))
			for o in [out_top, out_bot, out_lft, out_rgt]:
				if o.size.x > 0.0 and o.size.y > 0.0:
					draw_rect(o, Color(0, 0, 0, a), true)

func _draw() -> void:
	_refresh_view_metrics()
	var _main := get_parent()
	var _pb = _main.get("_probe") if _main != null else null
	if _pb != null and String(_pb.active_space) != "town":
		_draw_interior_backdrop(_main, _pb)        # 先铺暗底/暗角/外圈落影，室内不再泡在一片死灰里
		_draw_space_placeholder()                 # 非 town：只画该 Space/Floor（active-space 渲染）
		return
	if Sim.world.is_empty():
		return
	var w: int = int(Sim.world.get("width", 24))
	var h: int = int(Sim.world.get("height", 16))
	_draw_town_backdrop(w, h)   # 界外虚空：暗林/水环/暗角。必须在草地循环【之前】，且只碰地图矩形之外
	var veg := _season_veg()    # 四季：植被的乘算色偏（春新绿 / 夏深浓 / 秋金黄 / 冬冷褪）
	# 地面：逐格选草地变体（有切片时）→ 否则平铺单图 → 否则色块
	if not _grass.is_empty():
		var tw := 0
		for g in _grass:
			tw += int(g["w"])
		# 只画【看得见的】格子。旧版每帧无条件铺满 64x48 = 3072 个 draw_texture_rect，
		# 而 1280x768 视口在 zoom=1 时只装得下约 27x16 ≈ 430 格 —— 其余 85% 是纯浪费的填充率，
		# 这是手机上最便宜的一笔回收。变体仍由 _hash(tx,ty) 决定，与看哪儿无关 → 画面逐像素不变。
		var tx0 := maxi(0, int(floor(_vis.position.x / float(T))))
		var ty0 := maxi(0, int(floor(_vis.position.y / float(T))))
		var tx1 := mini(w, int(ceil(_vis.end.x / float(T))))
		var ty1 := mini(h, int(ceil(_vis.end.y / float(T))))
		for ty in range(ty0, ty1):
			for tx in range(tx0, tx1):
				var r := _hash(tx, ty, 3) % tw
				var chosen: Texture2D = _grass[0]["t"]
				for g in _grass:
					r -= int(g["w"])
					if r < 0:
						chosen = g["t"]
						break
				draw_texture_rect(chosen, Rect2(tx * T, ty * T, T, T), false, veg)
	else:
		var grass := Art.ground_tex()
		if grass != null:
			draw_texture_rect(grass, Rect2(0, 0, w * T, h * T), true, veg)
		else:
			draw_rect(Rect2(0, 0, w * T, h * T), Art.ground * veg, true)
	var dirt := Art.terrain_tex("dirt")
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

	# 土路网（广场↔各家门口）：铺在草地之上、区域/建筑之下 → 一眼读出"路"。装饰会避开它，路面才干净。
	if not _paths_built:
		_build_paths()
	if dirt != null:
		for idx in _path_set:
			var rx: int = idx % w
			var ry: int = idx / w
			draw_texture_rect(dirt, Rect2(rx * T, ry * T, T, T), false)
			draw_rect(Rect2(rx * T, ry * T, T, T), Color("#6b5a3e", 0.16), true)   # 压一层暖褐：比广场更"踩实"，两者可区分

	# 区域【真地板】：每个 district 按 type 铺木/石/铺装地板（旧版只有广场有地板，其余七个区只有一层
	# 0.10 alpha 的淡色罩 —— 那层淡到什么也读不出来，于是墙里全是草，房子读作"围了圈墙的院子"）。
	_draw_area_floors(dirt)
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
	_draw_facades()            # P3 打磨：开窗（夜透暖光）+ 住宅/工坊烟囱——先画在墙面上
	_draw_building_dressing(w) # 再压屋檐/招牌（自然遮住顶墙窗上沿，像真的屋檐）
	_draw_area_labels()        # 区名画在墙【之后】（旧版画在顶墙格上，被墙盖掉，等于没画）

	# 装饰散布（区域外草地上的树/花/草丛，确定性布局；在物件与居民之下）
	if not _decor_built:
		_build_decor()
	for it in _decor_items:
		var dtex: Texture2D = it["tex"]
		var c: Vector2i = it["cell"]
		if not _vis.has_point(Vector2(c.x * T, c.y * T)):
			continue                       # 视口外的花草石不画（布局仍由 _build_decor 一次性确定，与相机无关）
		var th: int = int(it["h"])
		var dw := float(dtex.get_width()) * (float(T) / 16.0)
		var dh := float(dtex.get_height()) * (float(T) / 16.0)
		# 底对齐格子（高物件如树向上伸出）；四季色偏与草地同源
		draw_texture_rect_region(dtex, Rect2(c.x * T + (T - dw) * 0.5, (c.y + 1) * T - dh, dw, dh), Rect2(0, 0, dtex.get_width(), dtex.get_height()), veg)

	# authored 阻挡树（map.json trees 层）：这些是【会挡路】的真树（与上面可踩的程序化花草区分开）。
	# 用 tree_big 切图底对齐画；缺切图则程序化画树冠+树干。占满格 → 玩家一眼读出"这里过不去"。
	var ttex := Art.decor_tex("tree_big")
	for tc in _tree_cells:
		if ttex != null:
			var tdw := float(ttex.get_width()) * (float(T) / 16.0)
			var tdh := float(ttex.get_height()) * (float(T) / 16.0)
			draw_texture_rect_region(ttex, Rect2(tc.x * T + (T - tdw) * 0.5, (tc.y + 1) * T - tdh, tdw, tdh), Rect2(0, 0, ttex.get_width(), ttex.get_height()), veg)
		else:
			var cx: float = tc.x * T + T * 0.5
			draw_rect(Rect2(tc.x * T + T * 0.30, tc.y * T + T * 0.55, T * 0.40, T * 0.45), Color("#6b4a2b"), true)  # 树干
			draw_circle(Vector2(cx, tc.y * T + T * 0.42), T * 0.42, Color("#2f6d3a") * veg)                          # 树冠
			draw_circle(Vector2(cx - T * 0.18, tc.y * T + T * 0.30), T * 0.24, Color("#3c8a4a") * veg)                # 高光叶

	_draw_town_doors()         # P3 UX：给能进的建筑画醒目木门 + 招牌（点门进店）
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
					var s := OBJ_PX          # 16px 源 × 3（= 整格）：与地面/装饰同一个像素尺，不再 2.5x 融化
					draw_texture_rect_region(otex, Rect2(base.x + (T - s) * 0.5, base.y + (T - s) * 0.5, s, s), Rect2(0, 0, otex.get_width(), otex.get_height()))
				else:
					draw_rect(Rect2(base.x + 9, base.y + 12, T - 18, T - 18), Color("#8a6a45"), true)
					draw_rect(Rect2(base.x + 9, base.y + 12, T - 18, T - 18), Color(0, 0, 0, 0.35), false, 2.0)
					draw_string(Art.font(), Vector2(base.x + 4, base.y + T - 3), str(o.get("type", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.7))

	# 四季 / 天气的大气罩：压在地形与建筑之上、居民之下（居民不该被刷成一片霜白）
	_draw_climate_wash(w, h)

	# ── 社交层（在 Agent 之下先画连线，再画 Agent 与标记）──────────────────
	# 每帧预建冲突/约会端点集 → _draw_agent 用 O(1) 查代替 per-agent 线性扫 Sim.conflicts/commitments（N 大时省 O(N×|conflicts|)）。
	_rc_conflict_ids = {}
	for _c in Sim.conflicts:
		var _s := String(_c["status"])
		if _s == "simmering" or _s == "escalated" or _s == "confronted" or _s == "lingering":
			_rc_conflict_ids[_c["a"]] = true; _rc_conflict_ids[_c["b"]] = true
	_rc_meet_ids = {}
	for _c in Sim.commitments:
		if String(_c["status"]) == "active":
			_rc_meet_ids[_c["a"]] = true; _rc_meet_ids[_c["b"]] = true
	_draw_faction_rings()      # S3a：派系归属（同色脚环）
	_draw_pact_links()         # S3b：互助盟约（青色双线 + 🤝）
	_draw_relationship_lines()
	_draw_talking_links()
	for ag in Sim.agents:
		if String(ag.get("space", "town")) != "town":
			continue            # P3 Tier-B：非-town 平面的居民(在咖啡馆室内的阿丽)不画在镇上——否则会用室内格坐标在镇上"鬼影"
		_draw_agent(ag)

	if Sim.weather_today == "雨":
		_draw_rain()            # 雨丝画在【居民之上】：雨在人前面落，才读作下雨而不是地面贴图

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
## P3 UX：镇上给每个【能进的建筑】画一扇醒目木门 + 悬挂招牌（portal from=town/outdoor 的 door）→ 玩家一眼看出可点进入。
func _draw_town_doors() -> void:
	var main := get_parent()
	var sg = main.get("_sg") if main != null else null
	if sg == null:
		return
	for p in sg.portals:
		var fr: Dictionary = p.get("from", {})
		if String(fr.get("space", "")) != "town" or String(fr.get("floor", "")) != "outdoor" or String(p.get("kind", "")) != "door":
			continue
		var pos: Array = fr.get("pos", [0, 0])
		var x := int(pos[0]) * T; var y := int(pos[1]) * T
		draw_rect(Rect2(x + 2, y + T * 0.5, T - 4, T * 0.5), Color(0, 0, 0, 0.25), true)          # 落地阴影
		draw_rect(Rect2(x + T * 0.1, y + T * 0.06, T * 0.8, T * 0.9), Color("#3a291a"), true)      # 门框
		draw_rect(Rect2(x + T * 0.16, y + T * 0.12, T * 0.68, T * 0.82), Color("#7a5230"), true)   # 门板
		draw_rect(Rect2(x + T * 0.16, y + T * 0.12, T * 0.68, T * 0.1), Color("#f0d68a", 0.5), true)  # 门楣暖光
		draw_rect(Rect2(x + T * 0.48, y + T * 0.12, T * 0.03, T * 0.82), Color("#3a291a"), true)   # 门缝
		draw_circle(Vector2(x + T * 0.72, y + T * 0.55), T * 0.055, Color("#f0d060"))              # 门把
		var to: Dictionary = p.get("to", {})
		var label := String(sg.label_of(String(to.get("space", ""))))
		var sw: float = 8.0 + Art.font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var sx := x + T * 0.5 - sw * 0.5
		draw_rect(Rect2(sx, y - T * 0.52, sw, T * 0.36), Color("#5a3f28"), true)                   # 招牌木板
		draw_rect(Rect2(sx, y - T * 0.52, sw, T * 0.36), Color("#e0c060", 0.8), false, 1.5)        # 金边
		draw_string(Art.font(), Vector2(sx + 5, y - T * 0.52 + 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#f0e0b0"))

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

## Sim 的【精确格心】。裁剪/LOD 判定只许用它（见 _render_pos 一节的红线）。
func _center(ag: Dictionary) -> Vector2:
	var p: Vector2i = ag["pos"]
	return Vector2(p.x * T + T * 0.5, p.y * T + T * 0.5)

## 【绘制】坐标 = 插值后的渲染坐标；没有记录（首帧 / 非 town / 刚进场）时回落到精确格心。
func _rpos(ag: Dictionary) -> Vector2:
	return _render_pos.get(String(ag["id"]), _center(ag))

## 渲染时钟：把渲染坐标向格心推进。只读 Sim.agents，绝不写 Sim。
func _process(delta: float) -> void:
	if Sim.world.is_empty():
		return
	# 一格实际占多少实时秒：tick_interval / speed（x8 加速时只有 0.01s）。
	# 下限 0.008 防除零/抖动，上限 0.16 防 --speed 0 时把收敛拖成"永远在爬"。
	var step := clampf(Sim.tick_interval / maxf(Sim.speed, 0.25), 0.008, 0.16)
	var k := clampf(delta / maxf(step * LERP_FRACTION, 0.001), 0.0, 1.0)
	var tele := TELEPORT_TILES * T
	var dirty := false
	var alive := {}
	for ag in Sim.agents:
		var id := String(ag["id"])
		alive[id] = true
		var target := _center(ag)
		# 朝向/行走帧按【格】的变化判定（Sim 的离散移动），与插值进度解耦。
		# 旧版把这段差分做在 _draw 里，而 _draw 从"每 tick 一次"变成"每帧一次"之后，
		# 差分会在移动后的第一帧就归零 → 人一边滑行一边播 idle。
		var gp: Vector2i = ag["pos"]
		var prev: Vector2i = _prev_pos.get(id, gp)
		if gp != prev:
			var d := gp - prev
			if absi(d.x) >= absi(d.y) and d.x != 0:
				_walk_row[id] = 1
				_facing_left[id] = d.x < 0
			elif d.y < 0:
				_walk_row[id] = 3
			else:
				_walk_row[id] = 1
			_prev_pos[id] = gp
		var cur: Vector2 = _render_pos.get(id, target)
		if cur.distance_to(target) > tele:
			cur = target
		else:
			cur = cur.lerp(target, k)
		var moving := cur.distance_to(target) > SNAP_PX
		if not moving:
			cur = target        # ★硬吸附：冻结 tick 下渲染坐标 ≡ 格心，--shot 前后 bbox 必须是 None
		if not _render_pos.has(id) or _render_pos[id] != cur or bool(_moving.get(id, false)) != moving:
			dirty = true
		_render_pos[id] = cur
		_moving[id] = moving
	if _render_pos.size() != alive.size():      # 换 N / 读档：清掉已不存在的 id，别留幽灵
		for id in _render_pos.keys():
			if not alive.has(id):
				_render_pos.erase(id); _moving.erase(id); _walk_row.erase(id)
				_prev_pos.erase(id); _facing_left.erase(id)
				dirty = true
	if dirty:
		queue_redraw()

## 关系连线：|affinity|>20 才画；绿=亲密、红=敌意，粗细/透明度随强度。
## 是否在镇上平面（非咖啡馆等室内）——室内居民用室内局部坐标，画在镇上会"鬼影"，与 agent 主循环(:752)同款过滤。
func _in_town(ag: Dictionary) -> bool:
	return String(ag.get("space", "town")) == "town"

## Main 当前选中的居民（只读，View→View）。没有选中或拿不到 → 空串。
func _selected_id() -> String:
	var m := get_parent()
	if m == null:
		return ""
	var v = m.get("_selected_id")
	return String(v) if v != null else ""

## 关系连线。旧版：|affinity|>20 的【每一对】都画，无上限、无衰减、无裁剪 —— N=12 时最多 66 条，
## N=60 时上千条，第 48 天变成一张横穿全镇的洋红蛛网；真机实测这一趟吃掉 166.7ms 帧里的 59.5ms。
## 现在四道闸：每人只留最强 K 条 → 屏幕长度衰减 → 视口裁剪 → 选中某人时其余线退到背景。
## 全是 DRAW 侧取舍，Sim 读不到任何一个（相机无关红线：game/bench/lod_verify.gd）。
func _draw_relationship_lines() -> void:
	if rel_mode == RelMode.OFF:
		return
	var sel := _selected_id()
	if rel_mode == RelMode.SELECTED and sel == "":
		return
	# 1) 每人取 top-K：一条边只要落在任一端的 top-K 里就保留（否则单侧的强关系会被对方的更强关系挤掉）
	var keep := {}
	for ag in Sim.agents:
		if not _in_town(ag):
			continue   # 室内居民不在镇上画关系线（否则室内局部坐标鬼影）
		var aid := String(ag["id"])
		if rel_mode == RelMode.SELECTED and aid != sel:
			continue
		var top := []      # ≤K 条，按 |affinity| 降序；同强度先到先得（relationships 是有序字典 → 确定，画面不闪）
		for oid in ag["relationships"]:
			var aff := float(ag["relationships"][oid].get("affinity", 0.0))
			var mag := absf(aff)
			if mag <= REL_MIN_AFF:
				continue
			if top.size() >= REL_TOP_K and mag <= float(top[top.size() - 1]["mag"]):
				continue
			var ins := top.size()
			for i in top.size():
				if mag > float(top[i]["mag"]):
					ins = i
					break
			top.insert(ins, {"id": String(oid), "aff": aff, "mag": mag})
			if top.size() > REL_TOP_K:
				top.resize(REL_TOP_K)
		for e in top:
			var oid2 := String(e["id"])
			var k := (aid + ">" + oid2) if aid < oid2 else (oid2 + ">" + aid)
			keep[k] = e["aff"]
	# 2) 画：视口裁剪 + 屏幕长度衰减 + 选中聚焦
	for k in keep:
		var ids := String(k).split(">")
		var a: Dictionary = Sim.get_agent(ids[0])
		var b: Dictionary = Sim.get_agent(ids[1])
		if a.is_empty() or b.is_empty() or not _in_town(a) or not _in_town(b):
			continue
		# 裁剪按【格心】（_center），绘制按【渲染坐标】（_rpos）：剔除不许依赖插值残余。
		var c1 := _center(a)
		var c2 := _center(b)
		if not _vis.intersects(Rect2(c1, Vector2.ZERO).expand(c2)):
			continue                                   # 整段在视口外 → 一笔不画
		var p1 := _rpos(a)
		var p2 := _rpos(b)
		var aff2 := float(keep[k])
		var t := clampf(absf(aff2) / 100.0, 0.0, 1.0)
		var screen_len := c1.distance_to(c2) * _zoom   # 长度衰减也走格心：否则每帧微抖，长线会轻微闪
		var fade := clampf(1.0 - (screen_len - REL_FADE_PX) / REL_FADE_PX, 0.25, 1.0)
		var focus := 1.0
		var width := 1.2 + t * 2.4
		if sel != "" and rel_mode == RelMode.ALL and ids[0] != sel and ids[1] != sel:
			focus = 0.55                               # 选了人 → 别人的线退半档背景，ta 的关系站出来（不是抹掉：全镇结构仍要看得见）
		elif sel != "":
			width += 1.2                               # 选中当事人的线加粗一档
		var col := (Color("#7ed957") if aff2 > 0.0 else Color("#e85a5a"))
		col.a = (0.26 + t * 0.52) * fade * focus
		draw_line(p1, p2, col, width)

## S3a 派系：同派系成员脚下画同色环（颜色由派系 medoid id 确定性派生）。
func _draw_faction_rings() -> void:
	for ag in Sim.agents:
		if not _in_town(ag):
			continue   # 室内居民不在镇上画派系环
		var fac := String(ag.get("faction", ""))
		if fac == "":
			continue
		var col := _faction_color(fac)
		col.a = 0.85
		if not _vis.has_point(_center(ag) + Vector2(0, T * 0.30)):
			continue                                  # 裁剪走格心
		var c := _rpos(ag) + Vector2(0, T * 0.30)     # 落脚线（与影子/精灵底边同一条）
		draw_arc(c, T * 0.20, 0.0, TAU, 16, col, 2.5)  # 收小到 0.20 格：不再穿过头顶名牌与脚下气泡

func _faction_color(fac: String) -> Color:
	var h := absi(fac.hash())
	return Color.from_hsv(float(h % 360) / 360.0, 0.65, 0.95)

## S3b 互助盟约：active pact 双方画青色双线 + 中点握手标记。
func _draw_pact_links() -> void:
	var drawn := {}
	for ag in Sim.agents:
		if not _in_town(ag):
			continue   # 室内居民不在镇上画盟约连线
		for oid in ag.get("pacts", {}):
			var p: Dictionary = ag["pacts"][oid]
			if String(p.get("status", "")) != "active":
				continue
			var key := String(p.get("key", ""))
			if drawn.has(key):
				continue
			drawn[key] = true
			var other: Dictionary = Sim.get_agent(oid)
			if other.is_empty() or not _in_town(other):
				continue
			if not _vis.intersects(Rect2(_center(ag), Vector2.ZERO).expand(_center(other))):
				continue                              # 裁剪走格心
			var a := _rpos(ag)
			var b := _rpos(other)
			var perp := (b - a).orthogonal().normalized() * 2.0
			var cyan := Color("#39d4c8", 0.7)
			draw_line(a + perp, b + perp, cyan, 1.6)
			draw_line(a - perp, b - perp, cyan, 1.6)
			# 中点标记：原本是 🤝，但它走 ThemeDB.fallback_font 而那张表【没有 emoji】→ 每条盟约中点都是一个豆腐框。
			# 换成自带中文字体一定有的「盟」，零新增资源、手机上同样成立。
			if _zoom >= LABEL_MIN_ZOOM:
				_draw_plate_text((a + b) * 0.5 + Vector2(0, 5), "盟", 13, cyan, Color(0, 0, 0, 0.5))

## 对话连线：正在一次社交事务里的两人之间画一条暖黄线。
func _draw_talking_links() -> void:
	for ag in Sim.agents:
		if not _in_town(ag):
			continue   # 室内居民不在镇上画对话连线
		var opt = ag.get("option")
		if opt != null and String(opt.get("kind", "")) == "social":
			var other: Dictionary = Sim.get_agent(String(opt.get("partner", "")))
			if not other.is_empty() and _in_town(other):
				if _vis.intersects(Rect2(_center(ag), Vector2.ZERO).expand(_center(other))):
					draw_line(_rpos(ag), _rpos(other), Color("#ffd166", 0.85), 2.5)   # 裁剪走格心、绘制走渲染坐标

## 居中的「深色底板 + 文字」。anchor = 文字基线中点；返回底板矩形，供旁边的标记贴边摆放。
## 旧版的名字是【无描边无底板的纯白 draw_string】——在草地上勉强能读，一压到这次新铺的木/石地板就糊没了。
func _draw_plate_text(anchor: Vector2, txt: String, fs: int, fg: Color, bg: Color) -> Rect2:
	var fnt := Art.font()
	var sz := fnt.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var plate := Rect2(anchor.x - sz.x * 0.5 - 4.0, anchor.y - sz.y + 2.0, sz.x + 8.0, sz.y + 3.0)
	draw_rect(plate, bg, true)
	draw_string(fnt, Vector2(anchor.x - sz.x * 0.5, anchor.y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fg)
	return plate

## 头顶气泡的动作文案：社交动作在 Sim 里是英文 id（greet/give/gossip_rep/…），直接 str() 出来就是生英文。
## 走 Sim._verb（只读 Sim.gd，不改它）转中文；物件/行程动作本来就是中文，_verb 对未匹配项原样返回 → 不受影响。
func _action_label(opt: Dictionary) -> String:
	var act := str(opt.get("action", ""))
	if act == "":
		return ""
	return Sim._verb(act) if String(opt.get("kind", "")) == "social" else act

func _draw_agent(ag: Dictionary) -> void:
	var center := _rpos(ag)                   # 绘制坐标（插值后）；本函数不做裁剪判定
	var feet := center.y + T * 0.30          # 落脚线：影子 / 派系环 / 精灵底边都对齐它
	var col := Color(str(ag.get("persona", {}).get("color", "#ffffff")))
	var spr := _hued_tex(str(ag.get("persona", {}).get("sprite", "")), String(ag["id"]))  # L6：克隆取确定性色相变体，命名 6 人=正典
	var head := center.y - T * 0.32          # 头顶（fallback 圆的情形）
	if spr != null:
		# 软阴影 + 按移动选行走帧（cols0-3 循环，左向水平翻转）。整数 2x 缩放，且把源帧里人物的【脚】压在落脚线上
		var fr := _agent_frame(ag)
		# 脚下阴影：旧版是 draw_circle(feet, T*0.22, α=.25) —— 直径 0.44 格几乎和精灵一样宽、边缘还是硬的，
		# 读起来像"人浮在一个圆盘上"。改成压扁的椭圆（y 轴 0.40）+ 3 圈由外向内变实的 alpha 衰减，
		# 核心宽度收到 0.15 格；叠加后中心不透明度 ≈0.27，与旧值同档，但边缘化开、不再抢精灵的轮廓。
		draw_set_transform(Vector2(center.x, feet), 0.0, Vector2(1.0, 0.40))
		for si in 3:
			draw_circle(Vector2.ZERO, T * 0.15 * (1.0 + float(2 - si) * 0.34), Color(0, 0, 0, 0.07 + float(si) * 0.030))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var sz := AGENT_PX
		var top := feet - sz * (CHAR_FEET_ROW / 32.0)
		head = top + sz * (CHAR_HEAD_ROW / 32.0)
		var src := Rect2(int(fr["col"]) * Art.CHAR_FRAME.x, int(fr["row"]) * Art.CHAR_FRAME.y, Art.CHAR_FRAME.x, Art.CHAR_FRAME.y)
		if bool(fr["flip"]):
			draw_set_transform(Vector2(center.x, top), 0.0, Vector2(-1, 1))
			draw_texture_rect_region(spr, Rect2(-sz * 0.5, 0.0, sz, sz), src)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect_region(spr, Rect2(center.x - sz * 0.5, top, sz, sz), src)
	else:
		draw_circle(center, T * 0.32, col)
		draw_circle(center, T * 0.32, Color(0, 0, 0, 0.4), false, 2.0)
	# 玩家标识：金色外环（--player 模式一眼可辨"这是我"）
	if ag.get("is_player", false):
		draw_circle(center, T * 0.42, Color("#ffd700"), false, 2.5)
	if _zoom < LABEL_MIN_ZOOM:
		return          # 全镇俯瞰档：名字/emote/气泡/需求条缩到几像素只剩糊斑 —— 不画，画面更干净、填充率也省下来
	# 最紧迫需求条（落脚线正下方）
	_draw_urgent_need(Vector2(center.x, feet + T * 0.20), ag)
	# 头顶 emote（社交事件触发，短暂显示）：20px 源 × 2 整数倍
	var name_y := head - T * 0.12            # 名字基线：紧贴头顶上方
	var em = _emote.get(ag["id"])
	if em != null and Sim.tick_no < int(em["until"]):
		var et: Texture2D = em["tex"]
		draw_texture_rect_region(et, Rect2(center.x - EMOTE_PX * 0.5, name_y - T * 0.50 - EMOTE_PX, EMOTE_PX, EMOTE_PX), Rect2(0, 0, et.get_width(), et.get_height()))
	# 名牌：名字 + 冲突「!」+ 约见「约」画进【同一块底板】。
	# 旧版把两个标记按固定像素偏移丢在名字外面，人挨着站时标记落在【邻居的名字】旁边，读不出是谁在闹。
	var nm := str(ag.get("persona", {}).get("name", ag["id"]))
	var fnt := Art.font()
	var nsz := fnt.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	var has_cf := _in_conflict(ag["id"])
	var has_mt := _has_meet(ag["id"])
	var lw := 11.0 if has_cf else 0.0
	var rw := 18.0 if has_mt else 0.0
	var total := nsz.x + lw + rw
	draw_rect(Rect2(center.x - total * 0.5 - 4.0, name_y - nsz.y + 2.0, total + 8.0, nsz.y + 3.0), Color(0, 0, 0, 0.62), true)
	var tx := center.x - total * 0.5
	if has_cf:
		draw_string(fnt, Vector2(tx, name_y), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#ff6b6b"))
		tx += lw
	draw_string(fnt, Vector2(tx, name_y), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.97))
	if has_mt:
		draw_string(fnt, Vector2(tx + nsz.x + 4.0, name_y), "约", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ffd166"))
	# 气泡：交谈台词（短暂）优先，其次当前动作。放在需求条下方 → 与派系环/需求条不再互相穿插
	var bubble := ""
	var sy = _say.get(ag["id"])
	if sy != null and Sim.tick_no < int(sy["until"]):
		bubble = String(sy["text"])
	else:
		var opt = ag.get("option")
		if opt != null:
			bubble = _action_label(opt)
	if bubble != "":
		_draw_plate_text(Vector2(center.x, feet + T * 0.64), bubble, 12, Color(1, 1, 1, 0.95), Color(0, 0, 0, 0.72))

## 程序化像素床（顶视角）：木框 + 床单 + 枕头 + 被子。base=格左上像素。
## ── 建筑（切顶俯视）────────────────────────────────────────────────────────
const WALL := 13.0     # 外墙厚(px)≈0.27 格：够读出体积，又不吃室内——室内可走面积仍是房间 rect 本身（墙向外长）

## 房型显示名：buildings.json 的 room.type 是【英文键】（_mat_wall/_mat_floor 靠子串匹配它选材质），
## 但屏幕上其余全是中文——直接把键画上去会突兀。这里只做「键→显示名」，缺表则原样回落（旧的
## parlor/workshop/quietroom 三个模板名也在表里）。纯渲染：不进 digest、不回喂 Sim。
const ROOM_NAME := {
	"bedroom": "卧房", "parlor": "茶座", "quietroom": "静室", "workshop": "工坊",
	"workroom": "工位", "storeroom": "库房", "cafe_bar": "后厨", "bathroom": "浴池",
	"washroom": "盥洗", "shopfloor": "货架",
}

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
	# 房型标签：压低存在感（不再是主视觉）。房间小于 ~2 格宽时不画——11px 字会横穿整间，读作乱码而非标签。
	if inner.size.x >= T * 1.9:
		draw_string(Art.font(), inner.position + Vector2(6, 15), String(ROOM_NAME.get(rtype, rtype)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#ffe6c2", 0.45))

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

## at = 需求条的【上边中点】（由 _draw_agent 按落脚线给，不再是"格心 +30px"的硬编码）。
func _draw_urgent_need(at: Vector2, ag: Dictionary) -> void:
	var worst := 100.0
	var worst_id := ""
	for nid in ag["needs"]:
		var v := float(ag["needs"][nid])
		if v < worst:
			worst = v
			worst_id = nid
	if worst_id == "":
		return
	var bar := Rect2(at.x - 16, at.y, 32, 4)
	draw_rect(bar, Color(0, 0, 0, 0.5), true)
	var frac := clampf(worst / 100.0, 0.0, 1.0)
	var c := Color("#7ed957") if worst > 35.0 else Color("#e85a5a")
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), c, true)

func _in_conflict(id: String) -> bool:
	return _rc_conflict_ids.has(id)   # 集在 _draw 每帧预建（语义同旧的线性扫，O(1) 查）

func _has_meet(id: String) -> bool:
	return _rc_meet_ids.has(id)
