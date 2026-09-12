extends Node
## LifeMode — 生活模式（docs/190）：开局挑一位镇上居民，附身过日子。
##
## 纯 View / 输入层。对 Sim 只调 life_* 这组公开动词（possess / life_move / life_use / life_social /
## life_portal / life_cancel）与只读快照（life_status / life_interactions / life_verb_options），
## 不直接改任何 agent 字段。三件事在这里被"改造"：
##   ① 相机：不再是观察者探针，而是跟着被附身者走（贴身缩放、室内外随人切换平面）；
##   ② 时钟：tick 从 0.08s 放慢到 LIFE_TICK（一天≈2 分钟 @1×），睡觉等长动作自动快进；
##   ③ 操控：Sims 式——WASD 走近 → E 打开互动菜单 → 选一个动作；点击物件/居民也能直接开菜单。
## 对居民的菜单里有「说法」：引擎圈定合法动词，模型（或规则地板）把它说成几种不同语气/情绪的台词供挑。

const DESIGN := Vector2(1280.0, 768.0)
const INK := Color(0.075, 0.085, 0.11, 0.93)
const INK_HI := Color(0.17, 0.18, 0.22, 0.97)
const GOLD := Color(0.80, 0.64, 0.36, 0.95)
const GOLD_DIM := Color(0.55, 0.44, 0.26, 0.85)
const PARCH := Color(0.95, 0.87, 0.66)
const MUTED := Color(0.66, 0.64, 0.58)
const BAD := Color(0.95, 0.55, 0.48)
const LIFE_TICK := 0.5              # 秒/tick @1×：TICKS_PER_DAY=240 ⇒ 一天 2 分钟
const SPEEDS := [1.0, 2.0, 4.0]
const FF_SPEED := 8.0               # 睡觉等长动作的自动快进档
const FF_MIN_DUR := 30              # dur_total ≥ 它的动作在"使用中"时自动快进
const MOVE_STEP := 0.13             # 秒/格（与 WorldView.CTL_STEP 同值）
const ZOOM_DEFAULT := 2.0
const ZOOM_MIN := 1.1
const ZOOM_MAX := 3.2
const CAM_LERP := 9.0
const NEED_ORDER := ["hunger", "energy", "social", "fun", "hygiene"]
const NEED_ZH := {"hunger": "饱腹", "energy": "精力", "social": "社交", "fun": "趣味", "hygiene": "卫生"}
const VERB_ZH := {"greet": "打招呼", "give": "送礼", "gossip": "说八卦", "invite": "约见", "confront": "理论", "apologize": "道歉"}
const MIN_PER_TICK := 6             # 1 tick = 24h/240 = 6 游戏分钟

class Marker extends Node2D:
	var lm: Node
	func _draw() -> void:
		lm._draw_marker(self)

var main: Node2D
var pid := ""
var active := false
var selecting := false
var free_will := false

var _fnt: Font
var _layer: CanvasLayer
var _marker: Marker
# 选人
var _sel: Control
var _sel_ids: Array = []
var _sel_cards: Array = []
var _sel_idx := 0
var _sel_detail: RichTextLabel
# HUD
var _hud: Control
var _portrait: TextureRect
var _name_l: Label
var _sub_l: Label
var _doing_l: Label
var _doing_fill: ColorRect
var _need_fill := {}
var _need_val := {}
var _speed_btns: Array = []
var _will_btn: Button
var _prompt: Label
var _toast: Label
var _toast_t := 0.0
# 菜单
var _modal: Panel
var _modal_open := false
var _modal_was_running := false
var _modal_entry: Dictionary = {}
var _modal_opts: Array = []         # [{enabled, fn}]，顺序 = 数字键
var _approaches: Array = []
var _ai_pending := false
var _approach_token := 0
# 状态
var _inter: Array = []
var _focus_id := ""
var _inter_t := 0.0
var _move_cd := 0.0
var _user_speed := 1.0
var _ff := false
var _zoom := ZOOM_DEFAULT
var _prev_interval := 0.08
var _press_pos := Vector2.ZERO
var _pressing := false
var _t := 0.0
# 点地走路 / 远处下单先走过去（与 WASD 同步频，由 Sim.life_step_toward 逐格 A*）
var _walk_on := false
var _walk_dest := Vector2i.ZERO
var _walk_goal: Dictionary = {}     # {kind: none|use|say|portal, …}；到了就执行
var _walk_steps := 0
const WALK_MAX_STEPS := 160
# 每日愿望（Sims 的 wants）：纯 View 状态，从 Sim 信号与快照判定完成，不写 Sim
var _wants: Array = []              # [{type, text, pts, done, …}]
var _wants_day := -1
var _score := 0
var _wants_panel: Panel
var _wants_l: RichTextLabel
# 志向（Sims 的 aspiration）：选人时挑一个一辈子的目标；进度只读 Sim 快照
const ASPIRATIONS := [
	{"id": "friends", "name": "广结善缘", "desc": "交到 5 个好朋友", "goal": 5},
	{"id": "wealth", "name": "发家致富", "desc": "攒到 60 币", "goal": 60},
	{"id": "craft", "name": "手艺人", "desc": "本职手艺升 2 级", "goal": 2},
	{"id": "popular", "name": "镇上红人", "desc": "让 8 个人觉得你靠谱", "goal": 8},
]
const ASP_PTS := 300
var _asp_idx := 0
var _asp: Dictionary = {}
var _asp_base := 0
var _asp_done := false
var _asp_btns: Array = []
# 人际面板（R）
var _rel_panel: Panel
var _rel_open := false

func setup(m: Node2D) -> void:
	main = m
	_fnt = Art.font()
	_layer = CanvasLayer.new()
	_layer.layer = 25
	add_child(_layer)
	_marker = Marker.new()
	_marker.lm = self
	_marker.z_index = 200
	main.add_child(_marker)
	_build_hud()
	_build_modal()
	_toast = _mk_label(_layer, 17, Vector2(340, 50), Vector2(600, 30), PARCH)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.visible = false
	Sim.world_reset.connect(func(): call_deferred("_after_reset"))
	Sim.social_event.connect(_on_social_event)
	Sim.life_action_done.connect(_on_action_done)
	Sim.day_changed.connect(_on_day)

# ── 选人 ─────────────────────────────────────────────────────────────────────
func begin_select() -> void:
	if active:
		_leave_life()
	selecting = true
	_close_modal()
	_hud.visible = false
	_prompt.visible = false
	if _sel != null:
		_sel.queue_free()
	_sel_ids = []
	for ag in Sim.agents:
		if ag.get("is_player", false) or ag.get("affiliate", false):
			continue
		if Art.char_sheet(String(ag["id"])) == null:
			continue                              # 扩 N 的克隆(npc_*)没有自己的立绘与人设卡：只让具名居民上选人台
		_sel_ids.append(String(ag["id"]))
		if _sel_ids.size() >= 24:
			break                                 # 6×4 网格即满屏
	_build_select()
	var keep := _sel_ids.find(pid)
	_select_card(keep if keep >= 0 else 0)

func _build_select() -> void:
	_sel = Control.new()
	_sel.size = DESIGN
	_sel.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_sel)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.80)
	dim.size = DESIGN
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sel.add_child(dim)
	var title := _mk_label(_sel, 30, Vector2(0, 22), Vector2(DESIGN.x, 40), PARCH)
	title.text = "选择你要过的人生"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := _mk_label(_sel, 15, Vector2(0, 62), Vector2(DESIGN.x, 24), MUTED)
	sub.text = "每个人都有自己的家、工作、钱包和人情账。选中后，TA 的日子由你来过。"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var cols := 6
	var cw := 196.0
	var ch := 118.0
	var gap := 8.0
	var x0 := (DESIGN.x - (cw + gap) * cols + gap) * 0.5
	_sel_cards = []
	for i in _sel_ids.size():
		var id := String(_sel_ids[i])
		var ag := Sim.get_agent(id)
		var p: Dictionary = ag.get("persona", {})
		var card := Panel.new()
		card.position = Vector2(x0 + (i % cols) * (cw + gap), 96.0 + (i / cols) * (ch + gap))
		card.size = Vector2(cw, ch)
		card.add_theme_stylebox_override("panel", _style(INK, GOLD_DIM, 6, 3))
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(_on_card_input.bind(i))
		card.mouse_entered.connect(_select_card.bind(i))
		_sel.add_child(card)
		var tr := TextureRect.new()
		tr.texture = _portrait_tex(id)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.position = Vector2(2, 12)
		tr.size = Vector2(88, 88)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(tr)
		var nm := _mk_label(card, 20, Vector2(90, 10), Vector2(cw - 94, 26), Color(p.get("color", "#f2dca8")).lightened(0.25))
		nm.text = String(p.get("name", id))
		var job := String(Sim._job_of(id).get("title", ""))
		var jl := _mk_label(card, 14, Vector2(90, 38), Vector2(cw - 94, 20), PARCH)
		jl.text = job if job != "" else "无业"
		var tl := _mk_label(card, 13, Vector2(90, 60), Vector2(cw - 94, 48), MUTED)
		tl.text = "·".join(p.get("traits", []))
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_sel_cards.append(card)
	var dp := Panel.new()
	dp.position = Vector2(40, 610)
	dp.size = Vector2(DESIGN.x - 80, 118)
	dp.add_theme_stylebox_override("panel", _style(INK, GOLD, 7, 5))
	dp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sel.add_child(dp)
	_sel_detail = RichTextLabel.new()
	_sel_detail.bbcode_enabled = true
	_sel_detail.add_theme_font_override("normal_font", _fnt)
	_sel_detail.add_theme_font_size_override("normal_font_size", 16)
	_sel_detail.position = Vector2(56, 620)
	_sel_detail.size = Vector2(900, 100)
	_sel_detail.scroll_active = false
	_sel_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sel.add_child(_sel_detail)
	var al := _mk_label(_sel, 15, Vector2(56, 694), Vector2(60, 24), GOLD)
	al.text = "志向"
	_asp_btns = []
	for i in ASPIRATIONS.size():
		var ab := Button.new()
		ab.text = String(ASPIRATIONS[i]["name"])
		ab.tooltip_text = String(ASPIRATIONS[i]["desc"])
		ab.position = Vector2(100 + i * 118, 688)
		ab.size = Vector2(110, 32)
		ab.focus_mode = Control.FOCUS_NONE
		_style_btn(ab, 15)
		ab.pressed.connect(_pick_asp.bind(i))
		_sel.add_child(ab)
		_asp_btns.append(ab)
	var go := Button.new()
	go.text = "开始这段人生"
	go.position = Vector2(DESIGN.x - 260, 646)
	go.size = Vector2(196, 46)
	_style_btn(go, 20)
	go.pressed.connect(func(): start_life(String(_sel_ids[_sel_idx])))
	_sel.add_child(go)
	var keys := _mk_label(_sel, 13, Vector2(0, 738), Vector2(DESIGN.x, 20), MUTED)
	keys.text = "方向键/鼠标 挑人 · Tab 换志向 · Enter 或双击 开始" + (" · Esc 回到原来的人生" if pid != "" and Sim.get_agent(pid).size() > 0 else "")
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _on_card_input(e: InputEvent, i: int) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_select_card(i)
		if e.double_click:
			start_life(String(_sel_ids[i]))

func _select_card(i: int) -> void:
	if _sel_ids.is_empty():
		return
	_sel_idx = clampi(i, 0, _sel_ids.size() - 1)
	for k in _sel_cards.size():
		(_sel_cards[k] as Panel).add_theme_stylebox_override("panel",
			_style(INK_HI if k == _sel_idx else INK, GOLD if k == _sel_idx else GOLD_DIM, 6, 5 if k == _sel_idx else 3))
	var id := String(_sel_ids[_sel_idx])
	var ag := Sim.get_agent(id)
	var p: Dictionary = ag.get("persona", {})
	var job: Dictionary = Sim._job_of(id)
	var home := Sim._area_label(ag.get("home", ag["pos"]))
	var jtxt := "无业" if job.is_empty() else "%s（日薪 %d）" % [String(job.get("title", "")), int(job.get("wage", 0))]
	_sel_detail.text = "[color=#f2dca8][font_size=22]%s[/font_size][/color]   [color=#a8a393]%s · 家在%s · 身上 %d 币[/color]\n%s\n[color=#a8a393]说话：%s[/color]" % [
		String(p.get("name", id)), jtxt, home, Sim._coin_of(id), String(p.get("bio", "")), String(p.get("style", ""))]
	_pick_asp(_asp_idx)

func _pick_asp(i: int) -> void:
	if _sel_ids.is_empty():
		return
	var has_job := not Sim._job_of(String(_sel_ids[_sel_idx])).is_empty()
	if String(ASPIRATIONS[i]["id"]) == "craft" and not has_job:
		i = 0                                     # 无业的人没有本职手艺可升
	_asp_idx = i
	for k in _asp_btns.size():
		var b: Button = _asp_btns[k]
		b.disabled = String(ASPIRATIONS[k]["id"]) == "craft" and not has_job
		b.add_theme_stylebox_override("normal", _style(INK_HI if k == _asp_idx else INK, GOLD if k == _asp_idx else GOLD_DIM, 5, 0))

# ── 开始 / 离开 ──────────────────────────────────────────────────────────────
func start_life(id: String) -> void:
	if not Sim.possess(id):
		_show_toast("没法附身到这个人")
		return
	pid = id
	selecting = false
	active = true
	free_will = false
	if _sel != null:
		_sel.queue_free()
		_sel = null
	if not is_equal_approx(Sim.tick_interval, LIFE_TICK):
		_prev_interval = Sim.tick_interval
	Sim.tick_interval = LIFE_TICK
	_user_speed = 1.0
	_ff = false
	Sim.speed = _user_speed
	Sim.running = true
	_zoom = ZOOM_DEFAULT
	_set_main_chrome(false)
	main.set("_selected_id", id)
	_hud.visible = true
	var ag := Sim.get_agent(id)
	_portrait.texture = _portrait_tex(id)
	_name_l.text = Sim._name(ag)
	_sync_space(ag)
	var pb: Node = main.get("_probe")
	pb.cam.position = _agent_px(ag)
	pb.cam.zoom = Vector2(_zoom, _zoom)
	_walk_stop()
	_score = 0
	_asp = (ASPIRATIONS[_asp_idx] as Dictionary).duplicate()
	if String(_asp["id"]) == "craft" and Sim._job_of(id).is_empty():
		_asp = (ASPIRATIONS[0] as Dictionary).duplicate()
	_asp_done = false
	_asp_base = 0
	_asp_base = _asp_progress()                   # 手艺人按"从现在起升几级"算；其它是绝对量
	if String(_asp["id"]) != "craft":
		_asp_base = 0
	_roll_wants()
	_refresh_hud()
	_show_toast("你现在是 %s。WASD 或点地面走动，走近东西或人按 E。" % Sim._name(ag), 4.0)
	main.call("_push", "[color=#ffd166]——— 你成为了 %s ———[/color]" % Sim._name(ag))

## 出图/眼验用（--life-menu）：立刻按一次 E。定格 tick 下 _process 还没刷过身边列表，这里先刷一次。
func debug_open_menu() -> void:
	if not active:
		return
	_refresh_inter()
	_open_modal(_focused())

func _leave_life() -> void:
	active = false
	Sim.possess("")
	_close_modal()
	if _ff:
		_ff = false
	Sim.speed = _user_speed

func _after_reset() -> void:
	if not active:
		return
	if Sim.get_agent(pid).is_empty():
		active = false
		begin_select()
		return
	if not free_will:
		Sim.possess(pid)
	_close_modal()

## Main 的观察者 chrome（观察台/时间轴/聊天框）在生活模式里让位：时间轴回放不含玩家指令，拖它会"改写"你的人生。
func _set_main_chrome(on: bool) -> void:
	for n in ["_obs", "_obs_pan", "_obs_card", "_obs_btn", "_scrub_pan", "_scrub_card", "_scrub_track", "_scrub_fill", "_scrub_handle", "_scrub_hint", "_chat_in"]:
		var c: Variant = main.get(n)
		if c is CanvasItem:
			(c as CanvasItem).visible = on and n != "_chat_in"

# ── 帧循环 ───────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_t += delta
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.6, 0.0, 1.0)
		if _toast_t <= 0.0:
			_toast.visible = false
	if not active:
		return
	var ag := Sim.get_agent(pid)
	if ag.is_empty():
		active = false
		begin_select()
		return
	_sync_space(ag)
	_camera(delta, ag)
	_poll_move(delta)
	_inter_t -= delta
	if _inter_t <= 0.0:
		_inter_t = 0.1
		_refresh_inter()
		_refresh_hud()
		_auto_ff()
	_place_prompt(ag)
	_marker.queue_redraw()

func _sync_space(ag: Dictionary) -> void:
	var pb: Node = main.get("_probe")
	var sp := String(ag.get("space", "town"))
	var fl := String(ag.get("floor", "outdoor"))
	if String(pb.active_space) != sp or String(pb.active_floor) != fl:
		pb.set_space(sp, fl, main.get("_sg").bounds_px(sp))
		pb._history.clear()
		pb.cam.position = _agent_px(ag)
		if sp != "town":                          # 室内比视口小：取消边界，镜头才能把人放在正中
			pb.cam.limit_left = -100000; pb.cam.limit_top = -100000
			pb.cam.limit_right = 100000; pb.cam.limit_bottom = 100000
		main.call("_update_obs")
		main.call("_update_status")

func _agent_px(ag: Dictionary) -> Vector2:
	var v: Node = main.get("_view")
	if v != null and v.has_method("_rpos"):
		return v._rpos(ag)
	return Vector2(ag["pos"].x * 48 + 24, ag["pos"].y * 48 + 24)

func _camera(delta: float, ag: Dictionary) -> void:
	var pb: Node = main.get("_probe")
	pb.mode = 0
	pb.follow_id = ""
	pb.demo_cam = false
	var k := clampf(CAM_LERP * delta, 0.0, 1.0)
	pb.cam.position = pb.cam.position.lerp(_agent_px(ag) + Vector2(0, -12), k)
	pb.cam.zoom = pb.cam.zoom.lerp(Vector2(_zoom, _zoom), k)

func _poll_move(delta: float) -> void:
	_move_cd -= delta
	if _modal_open or not Sim.running or (_chat_box != null and _chat_box.visible):
		return                                    # 打字时 WASD 是字，不是方向
	var dx := int(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - int(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))
	var dy := int(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - int(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	if dx == 0 and dy == 0:
		if _walk_on:
			_walk_tick()
		else:
			_move_cd = 0.0
		return
	_walk_stop()                                  # 一碰方向键就接管，放弃点地路线
	if _move_cd > 0.0:
		return
	_move_cd = MOVE_STEP
	if free_will:
		_set_free_will(false)                     # 一碰方向键就收回控制
	var tries: Array = []
	if dx != 0 and dy != 0:                       # 斜向：交替走两轴，被挡就换另一轴
		tries = [Vector2i(dx, 0), Vector2i(0, dy)] if int(_t / MOVE_STEP) % 2 == 0 else [Vector2i(0, dy), Vector2i(dx, 0)]
	elif dx != 0:
		tries = [Vector2i(dx, 0)]
	else:
		tries = [Vector2i(0, dy)]
	for d in tries:
		var r := Sim.life_move(d)
		if r == "":
			return
		if r != "blocked":
			_show_toast(r)
			return

## ── 走路（点地 / 先走过去再做）──────────────────────────────────────────────
func _walk_to(dest: Vector2i, goal: Dictionary = {}) -> void:
	if free_will:
		_set_free_will(false)
	_walk_on = true
	_walk_dest = dest
	_walk_goal = goal
	_walk_steps = 0
	_move_cd = 0.0

func _walk_stop() -> void:
	_walk_on = false
	_walk_goal = {}

func _walk_tick() -> void:
	if _move_cd > 0.0:
		return
	_move_cd = MOVE_STEP
	var kind := String(_walk_goal.get("kind", "none"))
	var stop := 0 if kind == "none" else 1
	if kind == "say" or kind == "talk":           # 人会走动：每步重取目标位置
		var tgt := Sim.get_agent(String(_walk_goal["id"]))
		var me := Sim.get_agent(pid)
		if tgt.is_empty() or not Sim._same_plane(me, tgt):
			_show_toast("对方走远了")
			_walk_stop()
			return
		_walk_dest = tgt["pos"]
		if Sim._socially_reachable(me, tgt):
			_arrive()
			return
	var r := Sim.life_step_toward(_walk_dest, stop)
	_walk_steps += 1
	if r == "arrived":
		_arrive()
	elif r == "blocked" or _walk_steps > WALK_MAX_STEPS:
		_show_toast("走不过去")
		_walk_stop()

func _arrive() -> void:
	var g := _walk_goal
	_walk_stop()
	match String(g.get("kind", "none")):
		"use": _use_now(String(g["id"]), String(g["action"]))
		"say": _say_now(String(g["id"]), g["ap"])
		"portal": _do_portal(g["pos"])
		"talk": _open_agent_menu(String(g["id"]))

func _open_agent_menu(tid: String) -> void:
	var tgt := Sim.get_agent(tid)
	if tgt.is_empty():
		return
	_focus_id = tid
	_open_modal({"kind": "agent", "id": tid, "label": Sim._name(tgt), "pos": tgt["pos"],
		"dist": Sim._manh(Sim.get_agent(pid)["pos"], tgt["pos"]), "busy": int(tgt["talking"]) > 0})

# ── 存读档（Main 在 F5/F8 调）──────────────────────────────────────────────────
func save_state() -> Dictionary:
	return {"pid": pid, "score": _score, "wants": _wants.duplicate(true), "wants_day": _wants_day,
		"asp": _asp.duplicate(), "asp_base": _asp_base, "asp_done": _asp_done}

func load_state(d: Dictionary) -> void:
	if d.is_empty() or Sim.get_agent(String(d.get("pid", ""))).is_empty():
		return
	if not active or pid != String(d["pid"]):
		start_life(String(d["pid"]))
	Sim.running = false
	_score = int(d.get("score", 0))
	_wants = (d.get("wants", []) as Array).duplicate(true)
	_wants_day = int(d.get("wants_day", Sim.day))
	_asp = (d.get("asp", {}) as Dictionary).duplicate()
	_asp_base = int(d.get("asp_base", 0))
	_asp_done = bool(d.get("asp_done", false))
	_refresh_wants()
	_sync_speed_btns()
	_show_toast("读档完成 · 空格继续", 3.0)

# ── 人际面板（R）：你认识谁、交情几何；点一行走过去开菜单 ─────────────────────────
func _toggle_rel() -> void:
	if _rel_open:
		_rel_open = false
		if _rel_panel != null:
			_rel_panel.visible = false
		return
	_rel_open = true
	if _rel_panel != null:
		_rel_panel.queue_free()
	_rel_panel = Panel.new()
	_rel_panel.add_theme_stylebox_override("panel", _style(INK, GOLD, 7, 5))
	_rel_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_rel_panel)
	var me := Sim.get_agent(pid)
	var rels: Dictionary = me.get("relationships", {})
	var rows: Array = []
	for oid in rels:
		var o := Sim.get_agent(String(oid))
		if o.is_empty() or o.get("affiliate", false):
			continue
		var r: Dictionary = rels[oid]
		rows.append({"id": String(oid), "fam": float(r.get("familiarity", 0.0)), "aff": float(r.get("affinity", 0.0))})
	rows.sort_custom(func(a, b): return a["fam"] > b["fam"] if a["fam"] != b["fam"] else String(a["id"]) < String(b["id"]))
	rows = rows.slice(0, 12)
	var t := _mk_label(_rel_panel, 18, Vector2(14, 8), Vector2(320, 26), PARCH)
	t.text = "人际 · %s 认识的人" % Sim._name(me)
	var y := 40.0
	if rows.is_empty():
		var nl := _mk_label(_rel_panel, 14, Vector2(14, y), Vector2(320, 22), MUTED)
		nl.text = "还谁都不熟。走近别人按 E 打个招呼吧。"
		y += 28.0
	for rw in rows:
		var o2 := Sim.get_agent(String(rw["id"]))
		var here := Sim._same_plane(me, o2)
		var b := Button.new()
		b.text = "%s   %s   好感 %+d · 熟 %d%s" % [Sim._name(o2), AIBackend._rel_hint(me, String(rw["id"])), int(rw["aff"]), int(rw["fam"]), "" if here else "   （不在这儿）"]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.position = Vector2(10, y)
		b.size = Vector2(330, 28)
		b.disabled = not here
		b.focus_mode = Control.FOCUS_NONE
		_style_btn(b, 14)
		b.pressed.connect(_rel_go.bind(String(rw["id"])))
		_rel_panel.add_child(b)
		var bar := ColorRect.new()                # 好感条：中线为 0，绿右红左
		var w := clampf(absf(rw["aff"]) / 100.0, 0.0, 1.0) * 60.0
		bar.color = Color(0.49, 0.80, 0.42, 0.85) if rw["aff"] >= 0 else Color(0.92, 0.38, 0.32, 0.85)
		bar.position = Vector2(270 + (0.0 if rw["aff"] >= 0 else -w), 22)
		bar.size = Vector2(maxf(w, 1.0), 3)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(bar)
		y += 31.0
	var foot := _mk_label(_rel_panel, 12, Vector2(14, y + 2), Vector2(320, 18), MUTED)
	foot.text = "点一个人：走过去并打开互动菜单 · R 关闭"
	_rel_panel.position = Vector2(8, 186)
	_rel_panel.size = Vector2(350, y + 26)

func _rel_go(tid: String) -> void:
	_toggle_rel()
	var me := Sim.get_agent(pid)
	var tgt := Sim.get_agent(tid)
	if tgt.is_empty():
		return
	if Sim._socially_reachable(me, tgt):
		_open_agent_menu(tid)
	else:
		_walk_to(tgt["pos"], {"kind": "talk", "id": tid})

func _refresh_inter() -> void:
	_inter = Sim.life_interactions()
	if _inter.is_empty():
		_focus_id = ""
		return
	for e in _inter:
		if String(e["id"]) == _focus_id:
			return
	_focus_id = String(_inter[0]["id"])
	for e in _inter:                              # 默认焦点跳过正忙的人（有别的可选时）
		if not bool(e.get("busy", false)):
			_focus_id = String(e["id"])
			break

func _focused() -> Dictionary:
	for e in _inter:
		if String(e["id"]) == _focus_id:
			return e
	return {}

func _cycle_focus(dir: int) -> void:
	if _inter.is_empty():
		return
	var i := 0
	for k in _inter.size():
		if String(_inter[k]["id"]) == _focus_id:
			i = k
	_focus_id = String(_inter[(i + dir + _inter.size()) % _inter.size()]["id"])
	if _modal_open:
		_open_modal(_focused())

func _auto_ff() -> void:
	var st := Sim.life_status()
	var d: Dictionary = st.get("doing", {})
	var long_use := String(d.get("phase", "")) == "use" and int(d.get("total", 0)) >= FF_MIN_DUR
	if long_use and not _ff and Sim.running:
		_ff = true
		Sim.speed = FF_SPEED
		_show_toast("%s中……时间快进" % String(d.get("action", "")))
	elif _ff and not long_use:
		_ff = false
		Sim.speed = _user_speed
	_sync_speed_btns()

func _set_speed(s: float) -> void:
	if s <= 0.0:
		Sim.running = false
	else:
		_user_speed = s
		Sim.running = true
		Sim.speed = FF_SPEED if _ff else s
	_sync_speed_btns()
	main.call("_update_status")

func _set_free_will(on: bool) -> void:
	free_will = on
	Sim.possess("" if on else pid)
	_will_btn.text = "自主：开" if on else "自主：关"
	_show_toast("让 %s 自己过一会儿（按方向键收回）" % Sim._name(Sim.get_agent(pid)) if on else "收回控制")

# ── 输入 ─────────────────────────────────────────────────────────────────────
func _unhandled_input(e: InputEvent) -> void:
	if selecting:
		_select_input(e)
		return
	if not active:
		return
	if _chat_box != null and _chat_box.visible:
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			_close_chat()
			get_viewport().set_input_as_handled()
		return
	if e is InputEventKey and e.pressed:
		var used := true
		if _modal_open:
			match e.keycode:
				KEY_ESCAPE, KEY_E: _close_modal()
				KEY_TAB: _cycle_focus(-1 if e.shift_pressed else 1)
				KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
					_pick(int(e.keycode - KEY_1))
				KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5, KEY_KP_6, KEY_KP_7, KEY_KP_8, KEY_KP_9:
					_pick(int(e.keycode - KEY_KP_1))
				_: used = e.keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SPACE, KEY_C, KEY_Q]
		elif e.echo:
			used = e.keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_TAB]
		else:
			match e.keycode:
				KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT: pass   # _poll_move 读按住状态
				KEY_E, KEY_ENTER, KEY_KP_ENTER: _open_modal(_focused())
				KEY_TAB: _cycle_focus(-1 if e.shift_pressed else 1)
				KEY_Q: _show_toast("放下了手头的事" if Sim.life_cancel() else "现在没在做什么")
				KEY_SPACE: _set_speed(0.0 if Sim.running else _user_speed)
				KEY_0, KEY_KP_0: _set_speed(0.0)
				KEY_1, KEY_KP_1: _set_speed(SPEEDS[0])
				KEY_2, KEY_KP_2: _set_speed(SPEEDS[1])
				KEY_3, KEY_KP_3: _set_speed(SPEEDS[2])
				KEY_4, KEY_KP_4: _set_speed(FF_SPEED)
				KEY_F: _set_free_will(not free_will)
				KEY_C: begin_select()
				KEY_R: _toggle_rel()
				KEY_EQUAL, KEY_KP_ADD: _zoom = clampf(_zoom * 1.15, ZOOM_MIN, ZOOM_MAX)
				KEY_MINUS, KEY_KP_SUBTRACT: _zoom = clampf(_zoom / 1.15, ZOOM_MIN, ZOOM_MAX)
				KEY_G, KEY_B, KEY_Y, KEY_T, KEY_P, KEY_M, KEY_L, KEY_HOME, KEY_I, KEY_PAGEUP, KEY_PAGEDOWN, KEY_PERIOD, KEY_COMMA, KEY_BRACKETLEFT, KEY_BRACKETRIGHT, KEY_N: pass   # 观察者/M1 键位在生活模式里静音
				_: used = false
		if used:
			get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom = clampf(_zoom * 1.1, ZOOM_MIN, ZOOM_MAX)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom = clampf(_zoom / 1.1, ZOOM_MIN, ZOOM_MAX)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressing = true
				_press_pos = mb.position
			elif _pressing:
				_pressing = false
				if mb.position.distance_to(_press_pos) <= 8.0:
					if _modal_open:
						_close_modal()
					else:
						_tap(mb.position)
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion or e is InputEventPanGesture or e is InputEventMagnifyGesture:
		get_viewport().set_input_as_handled()   # 镜头跟人：不许拖走

func _select_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed):
		return
	match e.keycode:
		KEY_LEFT, KEY_A: _select_card(_sel_idx - 1)
		KEY_RIGHT, KEY_D: _select_card(_sel_idx + 1)
		KEY_UP, KEY_W: _select_card(_sel_idx - 6)
		KEY_DOWN, KEY_S: _select_card(_sel_idx + 6)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E: start_life(String(_sel_ids[_sel_idx]))
		KEY_TAB:
			var ni := (_asp_idx + 1) % ASPIRATIONS.size()
			if String(ASPIRATIONS[ni]["id"]) == "craft" and Sim._job_of(String(_sel_ids[_sel_idx])).is_empty():
				ni = (ni + 1) % ASPIRATIONS.size()
			_pick_asp(ni)
		KEY_ESCAPE:
			if pid != "" and not Sim.get_agent(pid).is_empty():
				start_life(pid)
		_: return
	get_viewport().set_input_as_handled()

## 点击世界：点到人/物件/门 → 直接开它的菜单（物件可远程下单，人会自己走过去）。
func _tap(screen: Vector2) -> void:
	var pb: Node = main.get("_probe")
	var w: Vector2 = pb.screen_to_world(screen, main.call("_vp"))
	var cell := Vector2i(int(floor(w.x / 48.0)), int(floor(w.y / 48.0)))
	var all := Sim.life_interactions(999)
	var best: Dictionary = {}
	var bestd := 1.0e9
	for e in all:
		var p: Vector2i = e["pos"]
		var d := Vector2(p.x * 48 + 24, p.y * 48 + 24).distance_to(w)
		var r := 34.0 if String(e["kind"]) == "agent" else 30.0
		if d <= r and d < bestd:
			bestd = d
			best = e
	if best.is_empty():
		var me := Sim.get_agent(pid)
		if me.get("pos", Vector2i(-99, -99)) == cell:
			_open_modal({})                        # 点自己 → 自己的菜单
		else:
			for e in Sim.life_interactions(999):   # 点到远处的门：走过去再进
				if String(e["kind"]) == "portal" and e["pos"] == cell:
					_walk_to(cell, {"kind": "portal", "pos": cell})
					return
			_walk_to(cell)                         # 点地面：走过去（Sims 的点地走路）
		return
	_focus_id = String(best["id"])
	_open_modal(best)

# ── 互动菜单 ─────────────────────────────────────────────────────────────────
func _build_modal() -> void:
	_modal = Panel.new()
	_modal.add_theme_stylebox_override("panel", _style(INK, GOLD, 8, 8))
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.visible = false
	_layer.add_child(_modal)

func _open_modal(entry: Dictionary) -> void:
	if not _modal_open:
		_modal_was_running = Sim.running
		Sim.running = false                       # 菜单打开时世界暂停（Sims 同款：想清楚再动）
	_modal_open = true
	_modal_entry = entry
	_prompt.visible = false
	if String(entry.get("kind", "")) == "agent":
		_request_approaches(String(entry["id"]))
	_rebuild_modal()

func _close_modal() -> void:
	if not _modal_open:
		return
	_modal_open = false
	_modal.visible = false
	_approach_token += 1                          # 迟到的模型回包作废
	_ai_pending = false
	Sim.running = _modal_was_running
	_sync_speed_btns()

func _request_approaches(tid: String) -> void:
	var me := Sim.get_agent(pid)
	var tgt := Sim.get_agent(tid)
	var legal: Array = []
	for v in Sim.life_verb_options(tid, true):   # 距离不算门：远了就先走过去
		if bool(v["ok"]):
			legal.append(String(v["action"]))
	_approaches = AIBackend.approach_floor(me, tgt, legal)
	_approach_token += 1
	var tok := _approach_token
	_ai_pending = not legal.is_empty() and not (AIBackend.backend in ["logic", "random"])
	if not _ai_pending:
		return
	AIBackend.suggest_approaches(me, tgt, legal, {"tick": Sim.tick_no, "tod": Sim.time_of_day()}, func(list: Array):
		if tok != _approach_token or not _modal_open:
			return
		var merged: Array = list.duplicate()
		for a in _approaches:                     # 模型没覆盖到的合法动词，用地板补上
			var has := false
			for b in merged:
				if String(b["verb"]) == String(a["verb"]):
					has = true
			if not has and merged.size() < AIBackend.APPROACH_MAX:
				merged.append(a)
		_approaches = merged
		_ai_pending = false
		_rebuild_modal())

func _rebuild_modal() -> void:
	for c in _modal.get_children():
		c.queue_free()
	_modal_opts = []
	var e := _modal_entry
	var kind := String(e.get("kind", "self"))
	var y := 14.0
	var w := 520.0
	var title := _mk_label(_modal, 22, Vector2(18, y), Vector2(w - 36, 30), PARCH)
	var sub := _mk_label(_modal, 14, Vector2(18, y + 32), Vector2(w - 36, 20), MUTED)
	y += 60.0
	var n_near := _inter.size()
	var tab_hint := ("   Tab 换目标 (%d)" % n_near) if n_near > 1 else ""
	match kind:
		"object":
			title.text = String(e["label"])
			sub.text = ("就在身边" if int(e["dist"]) <= 1 else "离你 %d 步 · 选了会自己走过去" % int(e["dist"])) + tab_hint
			for a in e["actions"]:
				var ad: Dictionary = a
				var extra := ""
				if int(ad.get("price", 0)) > 0: extra += " · %d 币" % int(ad["price"])
				if int(ad.get("wage", 0)) > 0: extra += " · 挣 %d 币" % int(ad["wage"])
				var txt := "%s    %s +%d · %s%s" % [String(ad["action"]), String(NEED_ZH.get(String(ad["need"]), ad["need"])), int(ad["amount"]), _dur_text(int(ad["duration"])), extra]
				if not bool(ad["ok"]):
					txt += "   （%s）" % String(ad["why"])
				y = _mk_opt(txt, bool(ad["ok"]), _do_use.bind(String(e["id"]), String(ad["action"])), y, w)
		"agent":
			var tgt := Sim.get_agent(String(e["id"]))
			var me := Sim.get_agent(pid)
			title.text = String(e["label"])
			var far := not Sim._socially_reachable(me, tgt)
			sub.text = "%s · 看起来%s%s%s" % [AIBackend._rel_hint(me, String(e["id"])), String(AIBackend._mood(tgt)[0]),
				" · 选了会先走过去" if far else "", tab_hint]
			y = _mk_header("怎么开口" + ("   [模型构思中…]" if _ai_pending else ("   [模型]" if _has_ai() else "")), y, w)
			if _approaches.is_empty():
				y = _mk_note(_why_no_talk(String(e["id"])), y, w)
			for ap in _approaches:
				var apd: Dictionary = ap
				var hint := Sim.life_tone_hint(String(e["id"]), String(apd["tone"]))
				var txt := "【%s·%s】%s   · %s%s" % [String(apd["tone"]), String(apd["emotion"]), String(apd["line"]),
					String(VERB_ZH.get(String(apd["verb"]), apd["verb"])), ("  〔投其所好〕" if hint > 0 else ("  〔怕不对味〕" if hint < 0 else ""))]
				y = _mk_opt(txt, true, _do_say.bind(String(e["id"]), apd), y, w)
			if not far:
				y = _mk_opt("自己说点什么…（输入一句话）", true, _open_chat.bind(String(e["id"])), y, w)
			y = _mk_header("直接做", y + 4.0, w)
			for v in Sim.life_verb_options(String(e["id"]), true):
				var vd: Dictionary = v
				var txt := String(VERB_ZH.get(String(vd["action"]), vd["action"])) + ("" if bool(vd["ok"]) else "   （%s）" % String(vd["why"]))
				y = _mk_opt(txt, bool(vd["ok"]), _do_say.bind(String(e["id"]), {"verb": String(vd["action"]), "line": ""}), y, w)
		"portal":
			var to_floor := String(e.get("to_floor", ""))
			title.text = ("上下楼" if bool(e.get("stairs", false)) else "门") + " → " + String(e["label"])
			sub.text = ("%s 层" % to_floor if to_floor != "outdoor" else "室外") + tab_hint
			y = _mk_opt("走进去" if String(e.get("to_space", "")) != "town" else "出门", true, _do_portal.bind(e["pos"]), y, w)
		_:
			var st := Sim.life_status()
			title.text = String(st.get("name", "你自己"))
			sub.text = "身边没有能互动的东西 · 走近物件或居民再按 E" if _inter.is_empty() else "自己"
			var d: Dictionary = st.get("doing", {})
			var cancel_txt := ("放下手头的事（%s）" % String(d.get("action", ""))) if not d.is_empty() else "放下手头的事"
			y = _mk_opt(cancel_txt, not d.is_empty() and String(d.get("kind", "")) != "social", _self_cancel, y, w)
			y = _mk_opt("让 TA 自己过一会儿（自主）" if not free_will else "收回控制", true, _self_will, y, w)
			y = _mk_opt("换一个人生", true, _self_switch, y, w)
	var foot := _mk_label(_modal, 13, Vector2(18, y + 6.0), Vector2(w - 36, 18), MUTED)
	foot.text = "数字键选择 · Esc/E 关闭 · 菜单打开时世界暂停"
	y += 30.0
	_modal.size = Vector2(w, y)
	_modal.position = Vector2((DESIGN.x - w) * 0.5, clampf(DESIGN.y * 0.46 - y * 0.5, 44.0, DESIGN.y - y - 8.0))
	_modal.visible = true

func _self_cancel() -> void:
	_close_modal()
	Sim.life_cancel()

func _self_will() -> void:
	_close_modal()
	_set_free_will(not free_will)

func _self_switch() -> void:
	_close_modal()
	begin_select()

func _has_ai() -> bool:
	for a in _approaches:
		if String(a.get("src", "")) == "ai":
			return true
	return false

func _why_no_talk(tid: String) -> String:
	for v in Sim.life_verb_options(tid):
		return String(v["why"]) if String(v["why"]) != "" else "现在没什么好说的"
	return "现在说不上话"

func _mk_header(text: String, y: float, w: float) -> float:
	var l := _mk_label(_modal, 14, Vector2(18, y), Vector2(w - 36, 20), GOLD)
	l.text = text
	return y + 22.0

func _mk_note(text: String, y: float, w: float) -> float:
	var l := _mk_label(_modal, 14, Vector2(28, y), Vector2(w - 46, 20), BAD)
	l.text = text
	return y + 24.0

func _mk_opt(text: String, enabled: bool, fn: Callable, y: float, w: float) -> float:
	var idx := _modal_opts.size()
	_modal_opts.append({"enabled": enabled, "fn": fn})
	var b := Button.new()
	b.text = ("%d  " % (idx + 1) if idx < 9 else "    ") + text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.position = Vector2(14, y)
	b.size = Vector2(w - 28, 30)
	b.disabled = not enabled
	_style_btn(b, 15)
	b.pressed.connect(func(): _pick(idx))
	_modal.add_child(b)
	return y + 33.0

func _pick(i: int) -> void:
	if i < 0 or i >= _modal_opts.size():
		return
	var o: Dictionary = _modal_opts[i]
	if not bool(o["enabled"]):
		return
	(o["fn"] as Callable).call()

func _do_use(oid: String, action: String) -> void:
	_close_modal()
	var o: Dictionary = Sim.world.get("objects", {}).get(oid, {})
	var me := Sim.get_agent(pid)
	if not o.is_empty() and Sim._manh(me["pos"], o["pos"]) > 1:
		_walk_to(o["pos"], {"kind": "use", "id": oid, "action": action})   # 先按步频走过去，到了再下单
		return
	_use_now(oid, action)

func _use_now(oid: String, action: String) -> void:
	var r := Sim.life_use(oid, action)
	_show_toast(r if r != "" else action)

func _do_say(tid: String, ap: Dictionary) -> void:
	_close_modal()
	var me := Sim.get_agent(pid)
	var tgt := Sim.get_agent(tid)
	if not tgt.is_empty() and Sim._same_plane(me, tgt) and not Sim._socially_reachable(me, tgt):
		_walk_to(tgt["pos"], {"kind": "say", "id": tid, "ap": ap})
		return
	_say_now(tid, ap)

func _say_now(tid: String, ap: Dictionary) -> void:
	var line := String(ap.get("line", ""))
	var r := Sim.life_social(String(ap["verb"]), tid, line, String(ap.get("tone", "")))
	if r != "":
		_show_toast(r)
		return
	var v: Node = main.get("_view")
	var said := String(Sim.get_agent(pid).get("last_say", line))
	if v != null and said != "":
		v.show_say(pid, said, 24)
	if line != "" and AIBackend.backend in ["llm", "slm", "mock"]:
		var tgt := Sim.get_agent(tid)
		AIBackend.chat(tgt, line, {"tick": Sim.tick_no, "day": Sim.day, "tod": Sim.time_of_day()}, func(reply: String):
			if reply != "" and active and v != null and not Sim.get_agent(tid).is_empty():
				v.show_say(tid, reply, 40)
				main.call("_push", "[color=#c9b8ff]%s：%s[/color]" % [Sim._name(Sim.get_agent(tid)), reply.replace("[", "［")]))

## ── 自由对话：输入一句 → 对方用模型（或罐头）回一句 → 双方记忆落账 ─────────────
var _chat_box: LineEdit
var _chat_tid := ""

func _open_chat(tid: String) -> void:
	_close_modal()
	_chat_tid = tid
	if _chat_box == null:
		_chat_box = LineEdit.new()
		_chat_box.add_theme_font_override("font", _fnt)
		_chat_box.add_theme_font_size_override("font_size", 16)
		_chat_box.add_theme_stylebox_override("normal", _style(INK, GOLD, 6, 4))
		_chat_box.add_theme_stylebox_override("focus", _style(INK_HI, GOLD, 6, 4))
		_chat_box.add_theme_color_override("font_color", PARCH)
		_chat_box.position = Vector2((DESIGN.x - 520.0) * 0.5, DESIGN.y * 0.62)
		_chat_box.size = Vector2(520, 38)
		_chat_box.max_length = 40
		_chat_box.text_submitted.connect(_on_chat_submit)
		_layer.add_child(_chat_box)
	_chat_box.placeholder_text = "对%s说…（Enter 发送 · Esc 取消）" % Sim._name(Sim.get_agent(tid))
	_chat_box.text = ""
	_chat_box.visible = true
	_chat_box.grab_focus()
	_modal_was_running = Sim.running
	Sim.running = false                           # 打字时世界暂停

func _close_chat() -> void:
	if _chat_box == null or not _chat_box.visible:
		return
	_chat_box.visible = false
	_chat_box.release_focus()
	Sim.running = _modal_was_running

func _on_chat_submit(text: String) -> void:
	text = text.strip_edges()
	var tid := _chat_tid
	_close_chat()
	if text == "":
		return
	var v: Node = main.get("_view")
	if v != null:
		v.show_say(pid, text, 30)
	main.call("_push", "[color=#9ad0ff]%s → %s：%s[/color]" % [Sim._name(Sim.get_agent(pid)), Sim._name(Sim.get_agent(tid)), text.replace("[", "［")])
	var tgt := Sim.get_agent(tid)
	if tgt.is_empty():
		return
	tgt["thinking"] = true
	AIBackend.chat(tgt, text, {"tick": Sim.tick_no, "day": Sim.day, "tod": Sim.time_of_day()}, func(reply: String):
		var t2 := Sim.get_agent(tid)
		if t2.is_empty() or not active:
			return
		t2["thinking"] = false
		if reply == "":
			return
		if v != null:
			v.show_say(tid, reply, 45)
		main.call("_push", "[color=#c9b8ff]%s：%s[/color]" % [Sim._name(t2), reply.replace("[", "［")])
		var r := Sim.life_chat_commit(tid, text, reply)
		if not bool(r.get("ok", false)) and String(r.get("reason", "")) == "target_distance":
			_show_toast("%s走远了，没听完" % Sim._name(t2)))

func _do_portal(pos: Vector2i) -> void:
	_close_modal()
	var r := Sim.life_portal(pos)
	if not bool(r.get("ok", false)):
		_show_toast("进不去：私人区域" if String(r.get("reason", "")) == "portal_not_permitted" else "进不去（%s）" % String(r.get("reason", "")))

func _dur_text(ticks: int) -> String:
	var m := ticks * MIN_PER_TICK
	return "%d 分钟" % m if m < 60 else ("%d 小时" % (m / 60) if m % 60 == 0 else "%d 小时 %d 分" % [m / 60, m % 60])

# ── HUD ──────────────────────────────────────────────────────────────────────
func _build_hud() -> void:
	_hud = Control.new()
	_hud.size = DESIGN
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.visible = false
	_layer.add_child(_hud)
	var cw := 372.0
	var chh := 250.0
	var card := Panel.new()
	card.position = Vector2(DESIGN.x - cw - 8.0, DESIGN.y - chh - 8.0)
	card.size = Vector2(cw, chh)
	card.add_theme_stylebox_override("panel", _style(INK, GOLD, 7, 5))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	_hud.add_child(card)
	var pf := Panel.new()
	pf.position = Vector2(10, 10)
	pf.size = Vector2(68, 68)
	pf.add_theme_stylebox_override("panel", _style(Color(0.12, 0.13, 0.16, 1.0), GOLD_DIM, 5, 0))
	pf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(pf)
	_portrait = TextureRect.new()
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.position = Vector2(12, 12)
	_portrait.size = Vector2(64, 64)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(_portrait)
	_name_l = _mk_label(card, 21, Vector2(88, 8), Vector2(cw - 96, 28), PARCH)
	_sub_l = _mk_label(card, 13, Vector2(88, 36), Vector2(cw - 96, 18), MUTED)
	_doing_l = _mk_label(card, 14, Vector2(88, 56), Vector2(cw - 96, 20), PARCH)
	_doing_l.clip_text = true
	var db := ColorRect.new()
	db.color = Color(1, 1, 1, 0.10)
	db.position = Vector2(88, 80)
	db.size = Vector2(cw - 100, 4)
	db.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(db)
	_doing_fill = ColorRect.new()
	_doing_fill.color = GOLD
	_doing_fill.position = db.position
	_doing_fill.size = Vector2(0, 4)
	_doing_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(_doing_fill)
	var y := 94.0
	for nid in NEED_ORDER:
		var l := _mk_label(card, 14, Vector2(12, y - 3), Vector2(44, 20), MUTED)
		l.text = String(NEED_ZH[nid])
		var bg := ColorRect.new()
		bg.color = Color(1, 1, 1, 0.09)
		bg.position = Vector2(58, y + 2)
		bg.size = Vector2(252, 10)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(bg)
		var f := ColorRect.new()
		f.position = bg.position
		f.size = Vector2(0, 10)
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(f)
		_need_fill[nid] = f
		var vl := _mk_label(card, 13, Vector2(318, y - 3), Vector2(44, 20), MUTED)
		_need_val[nid] = vl
		y += 21.0
	var labels := ["停", "1×", "2×", "4×"]
	var vals := [0.0, SPEEDS[0], SPEEDS[1], SPEEDS[2]]
	_speed_btns = []
	for i in labels.size():
		var b := Button.new()
		b.text = labels[i]
		b.position = Vector2(12 + i * 50, chh - 42)
		b.size = Vector2(44, 30)
		b.focus_mode = Control.FOCUS_NONE
		_style_btn(b, 15)
		b.pressed.connect(_set_speed.bind(vals[i]))
		card.add_child(b)
		_speed_btns.append(b)
	_will_btn = Button.new()
	_will_btn.text = "自主：关"
	_will_btn.position = Vector2(cw - 150, chh - 42)
	_will_btn.size = Vector2(138, 30)
	_will_btn.focus_mode = Control.FOCUS_NONE
	_style_btn(_will_btn, 15)
	_will_btn.pressed.connect(func(): _set_free_will(not free_will))
	card.add_child(_will_btn)
	var keys := _mk_label(_hud, 13, Vector2(10, DESIGN.y - 26), Vector2(880, 20), MUTED)
	keys.text = "WASD/点地 走动 · E 互动 · 点物件/居民 开菜单 · Tab 换目标 · R 人际 · Q 放下 · 空格 暂停 · 1-3 速度 · F 自主 · C 换人 · F5/F8 存读"
	_wants_panel = Panel.new()
	_wants_panel.position = Vector2(8, 48)
	_wants_panel.size = Vector2(340, 130)
	_wants_panel.add_theme_stylebox_override("panel", _style(INK, GOLD, 7, 5))
	_wants_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_wants_panel)
	_wants_l = RichTextLabel.new()
	_wants_l.bbcode_enabled = true
	_wants_l.add_theme_font_override("normal_font", _fnt)
	_wants_l.add_theme_font_size_override("normal_font_size", 15)
	_wants_l.position = Vector2(12, 8)
	_wants_l.size = Vector2(320, 118)
	_wants_l.scroll_active = false
	_wants_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wants_panel.add_child(_wants_l)
	_prompt = _mk_label(_layer, 16, Vector2.ZERO, Vector2(260, 26), PARCH)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ps := _style(INK, GOLD, 5, 2)
	ps.content_margin_left = 8; ps.content_margin_right = 8
	_prompt.add_theme_stylebox_override("normal", ps)
	_prompt.visible = false

func _refresh_hud() -> void:
	var st := Sim.life_status()
	if st.is_empty():
		return
	var needs: Dictionary = st["needs"]
	for nid in NEED_ORDER:
		var v := float(needs.get(nid, 100.0))
		var f: ColorRect = _need_fill[nid]
		f.size.x = 252.0 * clampf(v / 100.0, 0.0, 1.0)
		f.color = Color(0.49, 0.80, 0.42) if v >= 55.0 else (Color(0.93, 0.76, 0.33) if v >= 28.0 else Color(0.92, 0.38, 0.32))
		(_need_val[nid] as Label).text = "%d" % int(round(v))
	var job := String(st.get("job", ""))
	_sub_l.text = "%s · %d 币 · %s" % [(job + (" · 在班" if bool(st.get("in_shift", false)) else "")) if job != "" else "无业", int(st.get("coin", 0)),
		String(st.get("area", "")) if String(st.get("space", "town")) == "town" else String(main.get("_sg").label_of(String(st["space"])))]
	var d: Dictionary = st.get("doing", {})
	var txt := ""
	var frac := 0.0
	if free_will:
		txt = "自主中 · " + (_doing_text(d) if not d.is_empty() else "在想接下来干嘛")
	elif int(st.get("talking", 0)) > 0 and (d.is_empty() or String(d.get("kind", "")) != "social"):
		txt = "有人在跟你说话"
	elif d.is_empty():
		txt = "空闲 — 走近东西或人按 E"
	else:
		txt = _doing_text(d)
		if String(d.get("phase", "")) == "use" and int(d.get("total", 0)) > 0:
			frac = 1.0 - float(d["remaining"]) / float(d["total"])
	if _walk_on and d.is_empty():
		txt = "走过去…" if String(_walk_goal.get("kind", "none")) == "none" else "走过去，然后%s" % String(_walk_goal.get("action", VERB_ZH.get(String((_walk_goal.get("ap", {}) as Dictionary).get("verb", "")), "进门")))
	_doing_l.text = txt
	_doing_fill.size.x = (372.0 - 100.0) * clampf(frac, 0.0, 1.0)
	_check_state_wants(st)
	if _wants_day != Sim.day:
		_roll_wants()
	_sync_speed_btns()

func _doing_text(d: Dictionary) -> String:
	var act := String(d.get("action", ""))
	match String(d.get("kind", "")):
		"social": return "正在和%s%s" % [String(d.get("target_label", "")), String(VERB_ZH.get(act, act))]
		"attend": return "赶去赴约"
		"journey": return "动身去%s" % act
	if String(d.get("phase", "")) == "travel":
		return "走去%s · %s" % [String(d.get("target_label", "")), act]
	return "正在%s · %s（还剩 %s）" % [act, String(d.get("target_label", "")), _dur_text(int(d.get("remaining", 0)))]

func _sync_speed_btns() -> void:
	var cur := -1
	if not Sim.running and not _modal_open:
		cur = 0
	elif Sim.running:
		cur = SPEEDS.find(_user_speed) + 1
	for i in _speed_btns.size():
		var b: Button = _speed_btns[i]
		b.add_theme_stylebox_override("normal", _style(INK_HI if i == cur else INK, GOLD if i == cur else GOLD_DIM, 5, 0))

func _place_prompt(ag: Dictionary) -> void:
	var e := _focused()
	if _modal_open or e.is_empty():
		_prompt.visible = false
		return
	var pb: Node = main.get("_probe")
	var p: Vector2i = e["pos"]
	var wpos := Vector2(p.x * 48 + 24, p.y * 48 - 20)
	var vp: Vector2 = main.call("_vp")
	var sp: Vector2 = (wpos - pb.cam.position) * pb.cam.zoom + vp * 0.5
	var verb := "说话" if String(e["kind"]) == "agent" else ("进门" if String(e["kind"]) == "portal" else "使用")
	_prompt.text = "E  %s · %s%s" % [verb, String(e["label"]), ("  (Tab %d)" % _inter.size()) if _inter.size() > 1 else ""]
	_prompt.size = Vector2(maxf(120.0, _fnt.get_string_size(_prompt.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 22.0), 26)
	_prompt.position = Vector2(clampf(sp.x - _prompt.size.x * 0.5, 4.0, DESIGN.x - _prompt.size.x - 4.0), clampf(sp.y - 34.0, 44.0, DESIGN.y - 60.0))
	_prompt.visible = true
	var _unused := ag

## 世界层：头顶「生命水晶」（颜色=最缺的需求）+ 当前目标的金色描框。
func _draw_marker(n: Node2D) -> void:
	if not active:
		return
	var ag := Sim.get_agent(pid)
	if ag.is_empty():
		return
	var low := 100.0
	for nid in ag["needs"]:
		low = minf(low, float(ag["needs"][nid]))
	var col := Color(0.42, 0.90, 0.45) if low >= 45.0 else (Color(0.98, 0.80, 0.30) if low >= 22.0 else Color(0.98, 0.35, 0.30))
	var c := _agent_px(ag) + Vector2(0, -62 + sin(_t * 3.0) * 2.5)
	var dia := PackedVector2Array([c + Vector2(0, -11), c + Vector2(7, 0), c + Vector2(0, 11), c + Vector2(-7, 0)])
	n.draw_colored_polygon(dia, col)
	n.draw_polyline(PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]]), col.darkened(0.45), 1.5)
	n.draw_line(c + Vector2(-2, -6), c + Vector2(2, -2), Color(1, 1, 1, 0.7), 1.5)
	var e := _focused()
	if not e.is_empty() and not _modal_open:
		var p: Vector2i = e["pos"]
		var a := 0.55 + 0.35 * sin(_t * 5.0)
		n.draw_rect(Rect2(p.x * 48 + 2, p.y * 48 + 2, 44, 44), Color(GOLD.r, GOLD.g, GOLD.b, a), false, 2.0)
	if _walk_on and String(_walk_goal.get("kind", "none")) == "none":   # 点地的落脚点：一圈会呼吸的金环
		var dc := Vector2(_walk_dest.x * 48 + 24, _walk_dest.y * 48 + 30)
		var rr := 10.0 + 3.0 * sin(_t * 6.0)
		n.draw_arc(dc, rr, 0.0, TAU, 24, Color(GOLD.r, GOLD.g, GOLD.b, 0.85), 2.0)
		n.draw_arc(dc, rr * 0.45, 0.0, TAU, 16, Color(GOLD.r, GOLD.g, GOLD.b, 0.6), 1.5)

# ── 每日愿望（Sims 的 wants）─────────────────────────────────────────────────
## 每个游戏日按 (人, 天) 确定性地抽 3 条；完成判定只读 Sim 的信号与快照，奖励是 View 侧的「满足感」分，不写 Sim。
func _roll_wants() -> void:
	_wants = []
	_wants_day = Sim.day
	var me := Sim.get_agent(pid)
	if me.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = Sim.fnv1a32("%s#%d" % [pid, Sim.day])
	var pool: Array = []
	var st := Sim.life_status()
	var needs: Dictionary = st.get("needs", {})
	var lowest := "hunger"
	for nid in NEED_ORDER:
		if float(needs.get(nid, 100.0)) < float(needs.get(lowest, 100.0)):
			lowest = nid
	pool.append({"type": "need_use", "need": lowest, "text": {"hunger": "好好吃一顿", "energy": "睡个好觉", "social": "找人热闹一下",
		"fun": "找点乐子", "hygiene": "把自己收拾干净"}.get(lowest, "照顾好自己"), "pts": 30})
	if String(st.get("job", "")) != "":
		pool.append({"type": "work", "text": "上一次工（%s）" % String(st["job"]), "pts": 40})
	pool.append({"type": "social", "verb": "greet", "count": 3, "n": 0, "text": "跟 3 个人打招呼", "pts": 30})
	if int((me.get("inventory", {}) as Dictionary).get("gift", 0)) > 0:
		pool.append({"type": "social", "verb": "give", "count": 1, "n": 0, "text": "送出一份礼物", "pts": 35})
	pool.append({"type": "social", "verb": "invite", "count": 1, "n": 0, "text": "约一个人改天见面", "pts": 35})
	var stranger := ""
	for ag in Sim.agents:
		var oid := String(ag["id"])
		if oid == pid or ag.get("is_player", false) or ag.get("affiliate", false) or Art.char_sheet(oid) == null:
			continue
		if float((me.get("relationships", {}) as Dictionary).get(oid, {}).get("familiarity", 0.0)) < 3.0:
			stranger = oid
			if rng.randi() % 3 == 0:
				break
	if stranger != "":
		pool.append({"type": "meet", "id": stranger, "text": "和%s说上话" % Sim._name(Sim.get_agent(stranger)), "pts": 45})
	pool.append({"type": "coin", "amount": int(st.get("coin", 0)) + 6, "text": "攒到 %d 币" % (int(st.get("coin", 0)) + 6), "pts": 40})
	if float(needs.get("fun", 100.0)) < 70.0:
		pool.append({"type": "need_high", "need": "fun", "text": "让趣味涨到 80", "pts": 25})
	while _wants.size() < 3 and not pool.is_empty():
		var w: Dictionary = pool.pop_at(rng.randi() % pool.size())
		w["done"] = false
		_wants.append(w)
	_refresh_wants()

func _complete(w: Dictionary) -> void:
	if bool(w.get("done", false)):
		return
	w["done"] = true
	_score += int(w["pts"])
	_show_toast("愿望达成：%s  满足感 +%d" % [String(w["text"]), int(w["pts"])], 3.0)
	main.call("_push", "[color=#9be38a]√ %s 完成了愿望：%s[/color]" % [Sim._name(Sim.get_agent(pid)), String(w["text"])])
	_refresh_wants()

func _on_social_event(ev: Dictionary) -> void:
	if not active or String(ev.get("actor", "")) != pid or not bool(ev.get("accepted", false)):
		return
	for w in _wants:
		match String(w["type"]):
			"social":
				if String(ev.get("type", "")) == String(w["verb"]):
					w["n"] = int(w["n"]) + 1
					if int(w["n"]) >= int(w["count"]):
						_complete(w)
					else:
						_refresh_wants()
			"meet":
				if String(ev.get("target", "")) == String(w["id"]):
					_complete(w)

func _on_action_done(action: String, target: String, wage: int) -> void:
	if not active:
		return
	var need := ""
	for adv in Sim.world.get("objects", {}).get(target, {}).get("advertises", []):
		if adv is Dictionary and String(adv.get("action", "")) == action:
			need = String(adv.get("need", ""))
	for w in _wants:
		match String(w["type"]):
			"need_use":
				if need == String(w["need"]): _complete(w)
			"work":
				if wage > 0: _complete(w)

## 志向进度（只读 Sim 快照）。
func _asp_progress() -> int:
	var me := Sim.get_agent(pid)
	if me.is_empty() or _asp.is_empty():
		return 0
	var rels: Dictionary = me.get("relationships", {})
	match String(_asp["id"]):
		"friends":
			var n := 0
			for oid in rels:
				var r: Dictionary = rels[oid]
				if float(r.get("familiarity", 0.0)) >= 8.0 and float(r.get("affinity", 0.0)) >= 25.0:
					n += 1
			return n
		"wealth":
			return Sim._coin_of(pid)
		"craft":
			var jb: Dictionary = Sim._job_of(pid)
			return (Sim._skill_level(me, Sim._job_action(jb)) - _asp_base) if not jb.is_empty() else 0
		"popular":
			var n2 := 0
			for b in Sim.agents:
				if String(b["id"]) == pid:
					continue
				if float((b.get("relationships", {}) as Dictionary).get(pid, {}).get("standing", 0.0)) >= 1.0:
					n2 += 1
			return n2
	return 0

## 周期检查（钱/需求阈值类）：_refresh_hud 每 0.1s 调一次
func _check_state_wants(st: Dictionary) -> void:
	if not _asp_done and not _asp.is_empty() and _asp_progress() >= int(_asp["goal"]):
		_asp_done = true
		_score += ASP_PTS
		_show_toast("志向达成：%s！满足感 +%d" % [String(_asp["name"]), ASP_PTS], 5.0)
		main.call("_push", "[color=#ffd166]★ %s 实现了志向「%s」：%s[/color]" % [Sim._name(Sim.get_agent(pid)), String(_asp["name"]), String(_asp["desc"])])
		_refresh_wants()
	for w in _wants:
		if bool(w["done"]):
			continue
		match String(w["type"]):
			"coin":
				if int(st.get("coin", 0)) >= int(w["amount"]): _complete(w)
			"need_high":
				if float((st.get("needs", {}) as Dictionary).get(String(w["need"]), 0.0)) >= 80.0: _complete(w)

func _on_day(d: int) -> void:
	if not active:
		return
	var n := 0
	for w in _wants:
		if bool(w["done"]): n += 1
	main.call("_push", "[color=#ffd166]%s 的第 %d 天过去了：愿望完成 %d/%d · 满足感 %d[/color]" % [Sim._name(Sim.get_agent(pid)), d - 1, n, _wants.size(), _score])
	_roll_wants()
	_show_toast("新的一天。今天想做的事已更新。", 3.0)

func _refresh_wants() -> void:
	if _wants_l == null:
		return
	var s := "[color=#cda35c]今天的愿望[/color]   [color=#a8a393]满足感 %d[/color]" % _score
	if not _asp.is_empty():
		s += ("\n[color=#ffd166]★ 志向「%s」已实现[/color]" % String(_asp["name"])) if _asp_done else \
			("\n[color=#ffd166]志向「%s」[/color] [color=#a8a393]%s %d/%d[/color]" % [String(_asp["name"]), String(_asp["desc"]), mini(_asp_progress(), int(_asp["goal"])), int(_asp["goal"])])
	for w in _wants:
		var prog := ""
		if String(w["type"]) == "social" and int(w["count"]) > 1:
			prog = " (%d/%d)" % [mini(int(w["n"]), int(w["count"])), int(w["count"])]
		s += ("\n[color=#9be38a]√ %s[/color]" % String(w["text"])) if bool(w["done"]) else ("\n[color=#f2dca8]· %s%s[/color]  [color=#7d786c]+%d[/color]" % [String(w["text"]), prog, int(w["pts"])])
	_wants_l.text = s

# ── 小工具 ───────────────────────────────────────────────────────────────────
func _show_toast(text: String, secs := 2.4) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_t = secs
	_toast.modulate.a = 1.0

func _portrait_tex(id: String) -> Texture2D:
	var sheet := Art.char_sheet(id)
	if sheet == null:
		return Art.agent_tex(String((Sim.get_agent(id).get("persona", {}) as Dictionary).get("sprite", "")))
	var at := AtlasTexture.new()
	at.atlas = sheet
	at.region = Rect2(0, 0, Art.CHAR8_CELL, Art.CHAR8_CELL)
	return at

func _style(bg: Color, border: Color, radius: int, shadow: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = shadow
	sb.shadow_offset = Vector2(2, 3)
	sb.anti_aliasing = false
	return sb

func _style_btn(b: Button, fs: int) -> void:
	b.add_theme_font_override("font", _fnt)
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_stylebox_override("normal", _style(INK, GOLD_DIM, 5, 0))
	b.add_theme_stylebox_override("hover", _style(INK_HI, GOLD, 5, 0))
	b.add_theme_stylebox_override("pressed", _style(INK_HI, GOLD, 5, 0))
	b.add_theme_stylebox_override("disabled", _style(Color(0.06, 0.065, 0.08, 0.85), Color(0.3, 0.28, 0.24, 0.6), 5, 0))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", PARCH)
	b.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.8))
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.48, 0.44))

func _mk_label(parent: Node, fs: int, pos: Vector2, sz: Vector2, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _fnt)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.position = pos
	l.size = sz
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
