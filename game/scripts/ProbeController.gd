extends Node
## ProbeController — 观察者「探针」。拥有 Camera2D + 全部观察状态（模式/焦点/跟随/返回栈/active space+floor）。
##
## ★红线（docs/19 §3 · analysis §4.1/§5.2）：Probe 是【纯 View】。
##   - 只【读】Sim（跟随要知道 agent 在哪），**绝不写 Sim**、绝不喂 lod_focus。
##   - ProbeState 不进 digest / event_log / RNG / actor 存档。硬门：tools/probe_digest_test.sh
##     （同 seed 同 tick，狂拖狂缩 vs 不碰相机 → digest 必须逐字节相同）。
##   - Probe inspect ≠ Agent traverse：观察者可以直接看任意 Space/Floor；角色必须走合法 Portal（Sim 的事）。
##
## 与 Main 的分工：Main 先吃 HUD/面板/时间轴输入，剩下的世界输入才交给 Probe.handle_input()。

enum Mode { FREE, FOCUS, FOLLOW }

## ZOOM_MIN = 【硬地板】(绝不越过)；真正生效的下限由 min_zoom() 按 active Space 的 bounds vs 视口动态算：
## 64x48 格镇 = 3072x2304 px，塞进 1280x768 需 ~0.33（老的 0.6 只看得到 ~14% 的镇，"回到全镇"名不副实）；
## 而 6x5 格的室内塞进同一视口只需 ~1.6 → 室内不该被允许缩到 0.18 变成灰底里的小方块。故下限 = f(bounds)。
const ZOOM_MIN := Vector2(0.18, 0.18)
const ZOOM_MAX := Vector2(3.0, 3.0)
const ZOOM_MIN_CEIL := 1.0      # 动态下限的上限：再小的 Space 也允许缩到 1:1，不强迫贴脸
const FIT_SLACK := 0.85         # 允许比"刚好装下"再退一点，边缘留白（手感：能看到镇外草地）
const HOME_PAD := Vector2(120, 240)  # 顶部状态栏 + 底部聊天/时间轴 + 右侧观察台的 HUD 余量（与 Main 的 --shot-fit 同款常量）
const CAM_MARGIN := 96          # 相机边界余量(px)：靠边仍留一点镇外草地
const DRAG_THRESH := 8.0        # 点选 vs 拖拽阈值：手机 emulate_mouse_from_touch → 单指拖=左键拖，一套逻辑通吃
const FOLLOW_LERP := 7.0
const FOCUS_ZOOM := Vector2(1.8, 1.8)

signal tapped(world_pos: Vector2)          # 真·点选（未越阈值）→ Main 做角色 hit-test
signal double_tapped(world_pos: Vector2)   # 双击 → Main 决定聚焦到哪栋建筑/房间

# ── 演示镜头编排（--demo-cam，docs/46 §三-D4）───────────────────────────────
## 起因是一句判决：已发布的 70 秒录屏里**相机从不推近、从不选人**，而 WorldView.gd:24 的
## `LABEL_MIN_ZOOM=0.45` 在全镇取景（go_home 实测 zoom≈0.229）下把名字/表情/气泡/需求条整段关掉
## ⇒ 那部片子在结构上拍不到这个项目真正在做的事。
##
## ★红线（与本类抬头同一条）：这是【表演】，不是仿真。本段对 Sim **只有读**，
##   尤其**不喂 lod_focus**；"选中某位居民"是 Main 的 View 状态，不进 digest / event_log / 存档。
##
## ★为什么镜头框的是【地方】而不是【人】——这是本棒最实质的一个设计决定：
##   轨迹必须是 tick 的**闭式函数**（不读墙钟、不吃 delta、不累积帧间状态），否则
##   ①录屏不可复现；②`--shot` 在 tick T 定格拍到的画面与录屏在 tick T 的画面对不上，
##     于是这一棒就没有任何可复现的量具（goto_tick 暖机发生在信号接线之前，重放不出滤波器状态）。
##   而"跟着某个居民"做不到闭式：agent 每 tick 整格跳，相机要么跟着抖（0.85 档一格=41 屏幕像素），
##   要么得上低通滤波器——那就变回有状态。**所以镜头停在广场/咖啡馆/工坊这些固定的社交场所，
##   谁在那儿就拍到谁。** 这同时是"不让仿真配合镜头"的那条边界：镜头制造机会，不点名要人。
const DEMO_FIT := -1.0                     # z0/z1 取此值 = 用 go_home 同款 fit_zoom（全镇入画）
const DEMO_ANCHOR_TILE := {                # 固定世界锚点（格坐标；取自 data/map.json 的 areas 中心）
	"plaza": Vector2(32.0, 24.0),          # 广场 rect[28,21,8,6]——也正是 64×48 镇子的正中
	"cafe": Vector2(41.5, 16.5),           # 咖啡馆 rect[37,13,9,7]
	"work": Vector2(41.5, 31.5),           # 工坊 rect[37,28,9,7]
	"home": Vector2(22.5, 16.5),           # 住宅区 rect[18,13,9,7]
}
## 分镜表。`len` 单位是 **tick**（不是秒）——tick 是仿真的时基，秒不是；
## 换 --speed 只改片长，不改构图。TICKS_PER_DAY=240 ⇒ 任何 ≥240 tick 的定场镜头
## 必然跨过一整个昼夜，所以"夜里有灯的近景"是排出来的，不需要去拨仿真的钟。
## ★片长与循环长度的关系是【量出来后改过一次】的，别照直觉调：
##   第一版总长 2380 tick。容器软渲染下实测约 34 tick/s（--speed 3），70 秒正好走完一圈 ⇒
##   收尾的 pull(170)+wide2(260)=430 tick **连续 12.6 秒全景**，加开场 6 秒 = 全片 27% 停在
##   名牌门之下的那一档——正是这一棒要修的那个毛病，被 R10 整片翻一遍才看出来
##   （逐帧抽样与任何单帧指标都不会报它：每一帧单独看都没问题）。
##   现在总长 2510 tick ⇒ 70 秒**走不完一圈**（不会绕回开头的全景），收尾只剩约 6 秒。
##   注意 tick/s 随机器负载浮动（并行录制时更慢）：跑得快就在片尾多绕进 3 秒开场全景，
##   跑得慢就停在近景不拉开——两侧都可接受，这正是把总长定得比片长【略长】的理由。
const DEMO_SHOTS := [
	{"n": "wide", "len": 200, "a": "town", "b": "town", "z0": DEMO_FIT, "z1": DEMO_FIT},
	{"n": "push", "len": 160, "a": "town", "b": "plaza", "z0": DEMO_FIT, "z1": 0.85},
	{"n": "plaza", "len": 300, "a": "plaza", "b": "plaza", "z0": 0.85, "z1": 0.85},
	{"n": "closeup", "len": 120, "a": "plaza", "b": "plaza", "z0": 0.85, "z1": 1.25},
	{"n": "portrait", "len": 240, "a": "plaza", "b": "plaza", "z0": 1.25, "z1": 1.25},
	{"n": "to_cafe", "len": 180, "a": "plaza", "b": "cafe", "z0": 1.25, "z1": 0.85},
	{"n": "cafe", "len": 420, "a": "cafe", "b": "cafe", "z0": 0.85, "z1": 0.85},
	{"n": "to_work", "len": 180, "a": "cafe", "b": "work", "z0": 0.85, "z1": 0.85},
	{"n": "work", "len": 380, "a": "work", "b": "work", "z0": 0.85, "z1": 0.85},
	{"n": "pull", "len": 150, "a": "work", "b": "town", "z0": 0.85, "z1": DEMO_FIT},
	{"n": "wide2", "len": 180, "a": "town", "b": "town", "z0": DEMO_FIT, "z1": DEMO_FIT},
]
var demo_cam := false                      # --demo-cam：由 Main 置位；关闭时本文件逐字节无行为变化

var cam: Camera2D
var mode: int = Mode.FREE
var follow_id := ""
var focus_id := ""
var active_space := "town"                 # P1：当前观察的 Space（兼容期恒为 town）
var active_floor := "outdoor"              # P1：当前观察的 Floor（兼容期恒为 outdoor）
var _bounds := Rect2()                     # active Space 的世界边界（P1 起由 SpaceGraph 提供，不再直读 Sim.GRID）
var _home := Rect2()
var _history: Array = []                   # 返回栈：[{pos,zoom,space,floor,mode,focus}]
var _panning := false
var _pan_last := Vector2.ZERO
var _press_pos := Vector2.ZERO
var _maybe_tap := false
var _last_vp := Vector2(1280, 768)         # 最近一次输入带来的视口尺寸（go_home 等无 vp 参数的路径用；纯 View）

func setup(parent: Node, bounds: Rect2) -> void:
	_bounds = bounds
	_home = bounds
	cam = Camera2D.new()
	cam.position = bounds.get_center()
	parent.add_child(cam)
	cam.make_current()
	_apply_limits()

func _apply_limits() -> void:
	cam.limit_left = int(_bounds.position.x) - CAM_MARGIN
	cam.limit_top = int(_bounds.position.y) - CAM_MARGIN
	cam.limit_right = int(_bounds.end.x) + CAM_MARGIN
	cam.limit_bottom = int(_bounds.end.y) + CAM_MARGIN

## 屏幕→世界（Camera2D 默认 drag-center 锚点）。zoom-to-cursor 与点选 hit-test 都靠它。
func screen_to_world(sp: Vector2, vp: Vector2) -> Vector2:
	return cam.position + (sp - vp * 0.5) / cam.zoom

## 视口尺寸：优先问引擎（Probe 在场景树里），否则用最近一次输入记下的（headless / 未入树时兜底）。
func _vp_size() -> Vector2:
	var v := get_viewport()
	if v != null:
		var s: Vector2 = v.get_visible_rect().size
		if s.x > 1.0 and s.y > 1.0:
			return s
	return _last_vp

## active Space 的 bounds 在【扣掉 HUD 余量后】刚好塞进视口所需的缩放。纯几何、只读 _bounds，不碰 Sim。
func fit_zoom(vp := Vector2.ZERO, pad := HOME_PAD) -> float:
	var v := vp if vp.x > 1.0 and vp.y > 1.0 else _vp_size()
	var sz := _bounds.size
	if sz.x <= 1.0 or sz.y <= 1.0:
		return 1.0
	var avail := Vector2(maxf(v.x - pad.x, 64.0), maxf(v.y - pad.y, 64.0))
	return minf(avail.x / sz.x, avail.y / sz.y)

## 生效的缩放下限：以"整个 active Space 入画"为基准再放一点余量，夹在 [ZOOM_MIN, ZOOM_MIN_CEIL]。
## → 小镇能一路缩到全景，室内不会缩成灰底里的邮票。
func min_zoom(vp := Vector2.ZERO) -> Vector2:
	var z := clampf(fit_zoom(vp) * FIT_SLACK, ZOOM_MIN.x, ZOOM_MIN_CEIL)
	return Vector2(z, z)

## zoom-to-cursor：缩放前后【光标下的 world point 不动】（analysis §10.1 要求漂移 ≤1 screen px）。
func zoom_at(factor: float, screen_pos: Vector2, vp: Vector2) -> void:
	if vp.x > 1.0 and vp.y > 1.0:
		_last_vp = vp
	var before := screen_to_world(screen_pos, vp)
	cam.zoom = (cam.zoom * factor).clamp(min_zoom(vp), ZOOM_MAX)
	var after := screen_to_world(screen_pos, vp)
	cam.position += before - after          # 把漂移补回去

func push_history() -> void:
	_history.append({"pos": cam.position, "zoom": cam.zoom, "space": active_space,
		"floor": active_floor, "mode": mode, "focus": focus_id})
	if _history.size() > 32:
		_history.pop_front()

func go_back() -> bool:
	if _history.is_empty():
		return false
	var h: Dictionary = _history.pop_back()
	active_space = String(h["space"]); active_floor = String(h["floor"])
	cam.position = h["pos"]; cam.zoom = h["zoom"]
	mode = int(h["mode"]); focus_id = String(h["focus"])
	if mode != Mode.FOLLOW:
		follow_id = ""
	return true

## 「回到全镇」：真的把整镇装进视口（旧版硬置 zoom=1.0 → 3072x2304 的镇只露 ~14%，名不副实）。
func go_home() -> void:
	push_history()
	mode = Mode.FREE; follow_id = ""; focus_id = ""
	_bounds = _home
	_apply_limits()
	cam.position = _home.get_center()
	cam.zoom = Vector2.ONE * clampf(fit_zoom(), ZOOM_MIN.x, ZOOM_MAX.x)

func focus_on(world_pos: Vector2, id := "") -> void:
	push_history()
	mode = Mode.FOCUS; focus_id = id
	cam.position = world_pos
	cam.zoom = FOCUS_ZOOM.clamp(ZOOM_MIN, ZOOM_MAX)

func follow(agent_id: String) -> void:
	if agent_id == "":
		return
	push_history()
	mode = Mode.FOLLOW; follow_id = agent_id

## 解除跟随：Probe【留在当前视点】，不把 Agent 拉回（analysis §10.1）。
func unfollow() -> void:
	if mode == Mode.FOLLOW:
		mode = Mode.FREE
	follow_id = ""

## P1：切 active Space/Floor（换边界 + 复位）。Probe 直接 inspect，不移动任何 Agent。
func set_space(space_id: String, floor_id: String, bounds: Rect2) -> void:
	push_history()
	active_space = space_id
	active_floor = floor_id
	_bounds = bounds
	_apply_limits()
	cam.position = bounds.get_center()

## 演示镜头：把相机置到 tick 对应的位姿。**纯函数式**——只读 tick 与本类自己的几何，
## 不读 Sim、不读墙钟、不用 delta。返回一份给 Main 的只读描述（Main 据此决定选中谁）。
func demo_apply(tick: int, vp := Vector2.ZERO) -> Dictionary:
	if cam == null:
		return {}
	var total := 0
	for s in DEMO_SHOTS:
		total += int(s["len"])
	var t := ((tick % total) + total) % total      # 片子循环播放：录多久都不会"演完"
	var acc := 0
	var shot: Dictionary = DEMO_SHOTS[DEMO_SHOTS.size() - 1]
	var u := 0.0
	for s in DEMO_SHOTS:
		var l := int(s["len"])
		if t < acc + l:
			shot = s
			u = float(t - acc) / float(l)
			break
		acc += l
	var e := u * u * (3.0 - 2.0 * u)               # smoothstep：推近/拉开两端都无突起
	var pa := _demo_anchor_px(String(shot["a"]))
	var pb := _demo_anchor_px(String(shot["b"]))
	var za := _demo_zoom(float(shot["z0"]), vp)
	var zb := _demo_zoom(float(shot["z1"]), vp)
	var z := za + (zb - za) * e
	mode = Mode.FREE                               # 绝不用 Mode.FOLLOW：它的 lerp 吃 delta（帧率相关 ⇒ 不可复现）
	follow_id = ""
	cam.position = pa.lerp(pb, e)
	cam.zoom = Vector2(z, z)
	return {"shot": String(shot["n"]), "u": u, "zoom": z, "t": t,
		"anchor": pb, "pos": cam.position}

## 锚点 → 像素。"town" = 整镇（与 go_home 同一真源）；其余取 DEMO_ANCHOR_TILE 的格心。
func _demo_anchor_px(name: String) -> Vector2:
	if name == "town" or not DEMO_ANCHOR_TILE.has(name):
		return _home.get_center()
	var tl: Vector2 = DEMO_ANCHOR_TILE[name]
	return Vector2(tl.x * 48.0, tl.y * 48.0)

## DEMO_FIT → 与 go_home 逐字一致的全镇缩放；否则原值。**不夹 min_zoom()**：
## min_zoom 是给人手操作用的地板，演示轨迹的两端都在它之内，夹一次只会让推近档被静默改写。
func _demo_zoom(v: float, vp: Vector2) -> float:
	if v > 0.0:
		return v
	return clampf(fit_zoom(vp), ZOOM_MIN.x, ZOOM_MAX.x)

## 世界输入。返回 true=已消费（Main 先吃 HUD/时间轴，再喂这里）。
func handle_input(e: InputEvent, vp: Vector2) -> bool:
	# 人一碰相机，演示轨迹就让位——它是演示，不是笼子。（demo_cam=false 时本行短路，行为逐字节不变。）
	if demo_cam and (e is InputEventMouseButton or e is InputEventMouseMotion \
			or e is InputEventMagnifyGesture or e is InputEventPanGesture):
		demo_cam = false
	if vp.x > 1.0 and vp.y > 1.0:
		_last_vp = vp                        # 记下视口（go_home/min_zoom 无 vp 参数时用）
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			zoom_at(1.12, e.position, vp); return true
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			zoom_at(1.0 / 1.12, e.position, vp); return true
		elif e.button_index == MOUSE_BUTTON_MIDDLE or e.button_index == MOUSE_BUTTON_RIGHT:
			_panning = e.pressed
			_pan_last = e.position
			if _panning:
				unfollow()                       # 手动拖 → 解除跟随（符合直觉）
			return true
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press_pos = e.position
				_pan_last = e.position
				_maybe_tap = true
				return true
			else:
				var was_tap: bool = _maybe_tap and e.position.distance_to(_press_pos) <= DRAG_THRESH
				_maybe_tap = false
				_panning = false
				if was_tap:
					var wp := screen_to_world(e.position, vp)
					if e.double_click:
						emit_signal("double_tapped", wp)
					else:
						emit_signal("tapped", wp)
				return true
	elif e is InputEventMouseMotion:
		if _panning or (_maybe_tap and e.position.distance_to(_press_pos) > DRAG_THRESH):
			_panning = true
			unfollow()
			cam.position -= (e.position - _pan_last) / cam.zoom
			_pan_last = e.position
			return true
	elif e is InputEventMagnifyGesture:
		zoom_at(e.factor, e.position, vp); return true
	elif e is InputEventPanGesture:
		unfollow()
		cam.position -= e.delta * 12.0 / cam.zoom; return true
	return false

## 跟随：只【读】Sim 的位置把镜头挪过去——不写任何 Sim 状态。
func _process(delta: float) -> void:
	if mode != Mode.FOLLOW or follow_id == "" or cam == null:
		return
	var ag: Dictionary = Sim.get_agent(follow_id)
	if ag.is_empty():
		unfollow()
		return
	var t := Vector2(float(ag["pos"].x) * 48.0 + 24.0, float(ag["pos"].y) * 48.0 + 24.0)
	cam.position = cam.position.lerp(t, clampf(FOLLOW_LERP * delta, 0.0, 1.0))
