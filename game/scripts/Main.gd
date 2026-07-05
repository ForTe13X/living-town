extends Node2D
## Main.gd — 入口/屏幕管理器（范式同《小鱼岛》Main.gd）。
## 解析 CLI（--backend / --seed / --speed），启动 Sim，挂上 WorldView 渲染与 HUD（状态 + 滚动事件日志 + 图例）。

var _view: Node2D
var _cam: Camera2D
var _modulate: CanvasModulate
var _status: RichTextLabel
var _logbox: RichTextLabel
var _log_lines: Array = []
const LOG_CAP := 12
const ZOOM_MIN := Vector2(0.6, 0.6)
const ZOOM_MAX := Vector2(3.0, 3.0)

# ── 观察台 / 回放 ──────────────────────────────────────────────────────────
var _obs: RichTextLabel               # 右侧角色明细面板
var _scrub_track: ColorRect           # 时间轴底槽
var _scrub_fill: ColorRect            # 已播放进度
var _scrub_handle: ColorRect          # 拖动手柄
var _selected_id := ""                # 当前观察的角色
var _player_mode := false             # --player：玩家入镇（gameplay M1）
var _demo_mode := false               # --player-demo：脚本化玩家 autopilot（录 demo）
var _demo_steps: Array = []           # [{type:walk_to|select|act|chat|wait, ...}] 顺序执行
var _demo_i := 0
var _chat_in: LineEdit                # 玩家→NPC 对话输入框
var _backend_btn: Button              # 后端切换按钮（手机无 CLI：点按在 logic/slm/… 间轮换；桌面也可点）
var _shot_path := ""                  # --shot <abs.png>：渲一帧存图退出（dev 验证/出图；需真 framebuffer=Xvfb 或带窗口，纯 --headless 得空图）
var _settings_panel: ColorRect        # ⚙ 设置面板（NPC 数量/速度/后端；⚙ 按钮或 O 键开关）
var _npc_val: Label                   # 设置面板里的 NPC 数量数字
var _npc_target := 6                  # 当前目标 NPC 数（改动→同种子重开 sim）
var _seed := 0                        # 记住开局种子，供设置里"改 NPC 数重开"复用
# ── dev 性能 overlay（类 RTSS：FPS/内存/绘制/对象/NPC/tick 率/LLM stats）──
var _perf: RichTextLabel              # 左上角实时资源监控（F3 或设置里开关）
var _perf_on := false
var _perf_dt_acc := 0.0               # 采样窗口累计秒
var _perf_last_tick := 0             # 上个采样窗口的 tick_no（算 tick/s）
var _perf_rate := 0.0                 # 平滑后的 sim tick/s
var _max_tick := 0                    # 见过的最大 tick（scrub 范围上限）
var _scrubbing := false
const SCRUB_X0 := 584.0
const SCRUB_X1 := 1268.0
const SCRUB_Y := 724.0
const SCRUB_H := 16.0

func _ready() -> void:
	var seed := 20260626
	var backend := "logic"
	var spd := 1.0
	var warmup_days := 0                   # --warmup N：开局前静默推进到第 N 天（录 demo 跳到节日日用）
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--backend" and i + 1 < args.size():
			backend = args[i + 1]
		elif args[i] == "--seed" and i + 1 < args.size():
			seed = int(args[i + 1])
		elif args[i] == "--speed" and i + 1 < args.size():
			spd = float(args[i + 1])
		elif args[i] == "--endpoint" and i + 1 < args.size():
			AIBackend.endpoint = args[i + 1]   # 容器内连宿主 LM Studio：http://host.docker.internal:1234/v1/chat/completions
		elif args[i] == "--gpu":
			AIBackend.slm_use_gpu = true       # slm 后端用 GPU(本机原生 Vulkan)
		elif args[i] == "--debug-llm":
			AIBackend.debug_llm = true         # 诊断：打印每次 LLM 返回
		elif args[i] == "--scenario" and i + 1 < args.size():
			Sim.scenario = args[i + 1]         # S3 定向场景（faction/betray/freerider）；空=默认
		elif args[i] == "--agents" and i + 1 < args.size():
			Sim.spawn_count = int(args[i + 1]) # 扩 N：克隆到 N（含 L6 调色板变体演示）
		elif args[i] == "--player":
			_player_mode = true                # 玩家入镇（gameplay M1：WASD 移动 + G/F/B/Y/P/M 社交动作）
		elif args[i] == "--player-demo":
			_player_mode = true                # 录 demo 用：脚本化玩家 autopilot（确定性按 tick 触发动作）
			_demo_mode = true
		elif args[i] == "--warmup" and i + 1 < args.size():
			warmup_days = int(args[i + 1])     # 录 demo：跳到第 N 天开场（确定，goto_tick 同款重演）
		elif args[i] == "--shot" and i + 1 < args.size():
			_shot_path = args[i + 1]           # dev 出图：渲一帧存 png 退出（需真 framebuffer：Xvfb 或带窗口）
	AIBackend.backend = backend
	# 后端优先级：CLI --backend 显式 > user://settings.cfg（手机 UI 存的默认）> 默认 logic。
	# headless CI 不经此路（Harness/soak 直接 Sim.backend=null）→ 确定性逐字节不变。
	if not ("--backend" in args):
		AIBackend._load_user_settings()          # 可能把 AIBackend.backend 改成上次选的 slm/mock
	AIBackend.backend_requested = AIBackend.backend
	backend = AIBackend.backend                  # 让下方 probe 判定用最终值
	_seed = seed
	# NPC 数量 + 速度：同款优先级 CLI > user://settings.cfg > 默认（改 NPC 数会同种子重开小镇，故也存这里）。
	var _scfg := ConfigFile.new()
	_scfg.load("user://settings.cfg")
	if not ("--agents" in args):
		var _n := int(_scfg.get_value("sim", "npc_count", 0))
		if _n > 0:
			Sim.spawn_count = _n
	if not ("--speed" in args):
		spd = float(_scfg.get_value("sim", "speed", spd))

	# L7：--scenario 指向 data/scenarios/<id>.json（含 70B 编剧产出）→ 注册数据驱动场景 provider（窗口里也能演）。
	# 空/内建场景(faction/betray/freerider 无此文件)→ 不注册 → 回落内建 _seed_scenario；默认 ""→ Sim.ext 保持 null 逐字节不变。
	if Sim.scenario != "" and FileAccess.file_exists("res://data/scenarios/%s.json" % Sim.scenario):
		var ext := preload("res://scripts/SimExtensions.gd").new()
		ext.register_scenario(preload("res://scripts/DataScenarioProvider.gd").new(Sim.scenario))
		ext.freeze()
		Sim.ext = ext
	Sim.start_new(seed)
	if warmup_days > 0:
		Sim.goto_tick((warmup_days - 1) * int(Sim.TICKS_PER_DAY) + 8)   # 跳到第 N 天开场（节日已在日界 spawn）
		_selected_id = "ben"                # 录 demo：默认选中木匠(有职业+钱) → 观察台展示经济/职业行
	Sim.backend = AIBackend   # 窗口模式注入可插拔后端；headless/soak 时 Sim.backend=null 走内置 logic
	Sim.speed = spd
	_npc_target = maxi(6, Sim.spawn_count)   # 设置面板 NPC 数量初值（spawn_count 0→基础 6，>6→克隆总数）
	# 启动算力探测：测一发暖决策 → 自适应截止线 + 太慢自动降 logic（docs/11 §12：测 p50→选 路C/logic）
	if backend == "slm" or backend == "llm":
		Sim.auto_run = false
		var pag: Dictionary = Sim.agents[0]
		await AIBackend.probe_capability(pag, Sim.agent_candidates(pag), Sim._context(pag), func(info):
			print("[算力探测] tier=%s p50=%dms deadline=%dms backend=%s" % [info["tier"], int(info["p50_ms"]), int(info["deadline_ms"]), info["backend"]]))
		backend = AIBackend.backend   # 可能已被降级为 logic
	if _player_mode:
		Sim.add_player()              # 玩家入社交图：NPC 会主动搭话/接受规则/账本/记忆全生效
	if _demo_mode:
		_demo_setup()                 # 舞台布置（首帧前，无可见跳变）+ 动作剧本
	Sim.auto_run = true

	_view = preload("res://scripts/WorldView.gd").new()
	add_child(_view)

	_cam = Camera2D.new()
	_cam.position = Vector2(Sim.GRID.x * 48 * 0.5, Sim.GRID.y * 48 * 0.5)
	add_child(_cam)
	_cam.make_current()

	# 昼夜光照：CanvasModulate 只染世界画布，不染 HUD（HUD 在独立 CanvasLayer）
	_modulate = CanvasModulate.new()
	add_child(_modulate)

	_build_hud()
	Sim.ticked.connect(_on_tick)
	Sim.social_event.connect(_on_social)
	Sim.day_changed.connect(func(d): _push("[color=#ffe08a]——— 第 %d 天 ———[/color]" % d))
	_update_status()
	_update_obs()
	_update_scrubber()
	if OS.has_feature("android"):           # 手机上无控制台：把模型是否就位讲出来，缺则玩家知道往哪放 gguf
		var ms := AIBackend.model_status()
		_push("[color=#9ad0ff]端上模型 %s\n%s[/color]" % [("✓ 就位" if ms["exists"] else "未找到 → 用 logic 地板（把 gguf 放进 Documents 后重开）"), ms["path"]])
	if _shot_path != "":                    # dev 出图：等 1.5s 让世界渲染+纹理加载，再存一帧退出
		get_tree().create_timer(1.5).timeout.connect(func():
			var img := get_viewport().get_texture().get_image()
			if img != null:
				img.save_png(_shot_path)
			get_tree().quit())

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var fnt := Art.font()

	_status = _mk_label(layer, fnt, 17, Vector2(52, 6), Vector2(1082, 28))   # 左留 ⚙ 设置钮，右留后端切换钮

	# ⚙ 设置钮（左上角；点开 NPC 数量/速度/后端面板。O 键同款开关）
	var gear := Button.new()
	gear.text = "⚙"
	gear.add_theme_font_override("font", fnt)
	gear.add_theme_font_size_override("font_size", 18)
	gear.position = Vector2(10, 4)
	gear.size = Vector2(36, 30)
	gear.focus_mode = Control.FOCUS_NONE
	gear.pressed.connect(_toggle_settings)
	layer.add_child(gear)

	# 左下角滚动事件日志：把看不见的社交戏剧讲出来
	_mk_panel(layer, Vector2(8, 470), Vector2(560, 246))
	_logbox = _mk_label(layer, fnt, 15, Vector2(16, 476), Vector2(548, 236))

	# 右侧观察台明细面板（点选角色后显示其完整状态）
	_mk_panel(layer, Vector2(978, 36), Vector2(294, 600))
	_obs = _mk_label(layer, fnt, 14, Vector2(986, 42), Vector2(280, 588))

	# 底部时间轴 scrubber
	_scrub_track = ColorRect.new()
	_scrub_track.color = Color(1, 1, 1, 0.14)
	_scrub_track.position = Vector2(SCRUB_X0, SCRUB_Y)
	_scrub_track.size = Vector2(SCRUB_X1 - SCRUB_X0, SCRUB_H)
	_scrub_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_scrub_track)
	_scrub_fill = ColorRect.new()
	_scrub_fill.color = Color("#5ad1c2", 0.55)
	_scrub_fill.position = Vector2(SCRUB_X0, SCRUB_Y)
	_scrub_fill.size = Vector2(0, SCRUB_H)
	_scrub_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_scrub_fill)
	_scrub_handle = ColorRect.new()
	_scrub_handle.color = Color("#ffd166")
	_scrub_handle.size = Vector2(4, SCRUB_H + 8)
	_scrub_handle.position = Vector2(SCRUB_X0, SCRUB_Y - 4)
	_scrub_handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_scrub_handle)
	var hint := _mk_label(layer, fnt, 12, Vector2(SCRUB_X0, SCRUB_Y - 22), Vector2(700, 18))
	hint.text = "[color=#9aa0b5]时间轴：拖动回放（确定性重演）· 空格暂停 · , . 单步 · [ ] 跳天 · Tab 切角色 · 点居民查看[/color]"

	# 玩家 → NPC 对话输入框（选中居民后出现；Enter 发送）。M2：经 AIBackend.chat → LLM/mock/罐头。
	_chat_in = LineEdit.new()
	_chat_in.add_theme_font_override("font", fnt)
	_chat_in.add_theme_font_size_override("font_size", 15)
	_chat_in.position = Vector2(584, 648)
	_chat_in.size = Vector2(684, 30)
	_chat_in.visible = false
	_chat_in.text_submitted.connect(_on_player_say)
	layer.add_child(_chat_in)

	# 后端切换按钮（右上角）。手机上无 CLI → 靠这个在 logic/slm/… 间轮换；emulate_mouse_from_touch 默认开 → 点按即触发。
	# Button 独占自身矩形，不干扰世界点选；FOCUS_NONE 免抢键盘焦点（否则空格/快捷键失灵）。
	_backend_btn = Button.new()
	_backend_btn.add_theme_font_override("font", fnt)
	_backend_btn.add_theme_font_size_override("font_size", 14)
	_backend_btn.position = Vector2(1140, 4)
	_backend_btn.size = Vector2(132, 30)
	_backend_btn.focus_mode = Control.FOCUS_NONE
	_backend_btn.pressed.connect(_on_toggle_backend)
	layer.add_child(_backend_btn)
	_sync_backend_btn()

	_build_settings(layer, fnt)

	# dev 性能 overlay（默认隐藏；F3 或设置面板里开）。label 挂在 panel 下 → 一起显隐。
	var pperf := ColorRect.new()
	pperf.color = Color(0.02, 0.03, 0.05, 0.74)
	pperf.position = Vector2(10, 42)
	pperf.size = Vector2(300, 176)
	pperf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pperf.visible = false
	layer.add_child(pperf)
	_perf = RichTextLabel.new()
	_perf.bbcode_enabled = true
	_perf.scroll_active = false
	_perf.add_theme_font_override("normal_font", fnt)
	_perf.add_theme_font_size_override("normal_font_size", 14)
	_perf.position = Vector2(10, 6)
	_perf.size = Vector2(284, 164)
	_perf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pperf.add_child(_perf)

func _mk_panel(layer: CanvasLayer, pos: Vector2, sz: Vector2) -> void:
	var p := ColorRect.new()
	p.color = Color(0, 0, 0, 0.42)
	p.position = pos
	p.size = sz
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(p)

func _mk_label(layer: CanvasLayer, fnt: Font, fsize: int, pos: Vector2, sz: Vector2) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.scroll_active = false
	l.add_theme_font_override("normal_font", fnt)
	l.add_theme_font_size_override("normal_font_size", fsize)
	l.position = pos
	l.size = sz
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(l)
	return l

func _on_tick(_t: int) -> void:
	if _demo_mode:
		_demo_tick()               # --player-demo：剧本驱动玩家（确定性）
	_modulate.color = _daylight(Sim.time_of_day())
	_max_tick = maxi(_max_tick, Sim.tick_no)
	_update_status()
	_update_scrubber()
	_update_obs()

## 昼夜色调：按一天进度 0..1 在几个色停之间插值（夜蓝→晨暖→白昼→暮橙→夜蓝）。
func _daylight(tod: float) -> Color:
	var stops := [
		[0.0, Color(0.42, 0.47, 0.80)], [0.24, Color(0.45, 0.48, 0.78)],
		[0.30, Color(1.0, 0.86, 0.72)], [0.38, Color(1, 1, 1)],
		[0.68, Color(1, 1, 1)], [0.78, Color(1.0, 0.80, 0.62)],
		[0.86, Color(0.5, 0.52, 0.82)], [1.0, Color(0.42, 0.47, 0.80)],
	]
	for i in range(stops.size() - 1):
		var a: Array = stops[i]
		var b: Array = stops[i + 1]
		if tod >= float(a[0]) and tod <= float(b[0]):
			var f := (tod - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0]))
			return (a[1] as Color).lerp(b[1] as Color, f)
	return Color(1, 1, 1)

## 轮换后端（logic → llm → mock → slm → …，仅含 available_backends()）。记录意图 + 持久化；
## 真正切换发生在 AIBackend.decide() 的安全点（无在飞请求时），本 tick 状态栏即显示「→目标…」排队中。
func _on_toggle_backend() -> void:
	var avail := AIBackend.available_backends()
	var i := avail.find(AIBackend.backend_requested)
	var nxt := String(avail[(i + 1) % avail.size()]) if i >= 0 else "logic"
	AIBackend.request_backend(nxt)               # 意图 + 存 user://settings.cfg；下次启动也记住
	_sync_backend_btn()
	_push("[color=#9ad0ff]后端 → %s（生效于下个安全点；慢则各自超时回落 logic）[/color]" % nxt)

func _sync_backend_btn() -> void:
	if _backend_btn == null:
		return
	_backend_btn.text = "🤖 %s" % AIBackend.backend_requested

# ── ⚙ 设置面板（NPC 数量 / 速度 / 后端；持久化到 user://settings.cfg 的 [sim] 段）───────────
func _build_settings(layer: CanvasLayer, fnt: Font) -> void:
	_settings_panel = ColorRect.new()
	_settings_panel.color = Color(0.05, 0.06, 0.09, 0.96)
	_settings_panel.position = Vector2(430, 168)
	_settings_panel.size = Vector2(420, 424)
	_settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP   # 面板挡住背后世界点选
	_settings_panel.visible = false
	layer.add_child(_settings_panel)
	var vb := VBoxContainer.new()
	vb.position = Vector2(24, 20)
	vb.custom_minimum_size = Vector2(372, 384)
	vb.add_theme_constant_override("separation", 16)
	_settings_panel.add_child(vb)

	var title := Label.new()
	title.text = "⚙ 设置 Settings"
	title.add_theme_font_override("font", fnt)
	title.add_theme_font_size_override("font_size", 20)
	vb.add_child(title)

	# 后端
	var rb := _settings_row(vb, fnt, "后端 Backend")
	var bcyc := _mk_sbtn(fnt, AIBackend.backend_requested, 160)
	bcyc.pressed.connect(func():
		_on_toggle_backend()
		bcyc.text = AIBackend.backend_requested)
	rb.add_child(bcyc)

	# NPC 数量
	var rn := _settings_row(vb, fnt, "NPC 数量")
	var minus := _mk_sbtn(fnt, "−", 46)
	minus.pressed.connect(func(): _apply_npc(-2))
	rn.add_child(minus)
	_npc_val = Label.new()
	_npc_val.add_theme_font_override("font", fnt)
	_npc_val.add_theme_font_size_override("font_size", 18)
	_npc_val.custom_minimum_size = Vector2(60, 0)
	_npc_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rn.add_child(_npc_val)
	var plus := _mk_sbtn(fnt, "+", 46)
	plus.pressed.connect(func(): _apply_npc(2))
	rn.add_child(plus)
	_sync_npc_val()

	# 速度
	var rs := _settings_row(vb, fnt, "速度 Speed")
	for sv in [0.0, 1.0, 2.0, 4.0, 8.0]:
		var b := _mk_sbtn(fnt, ("⏸" if sv == 0.0 else "%d×" % int(sv)), 52)
		b.pressed.connect(func(): _set_speed(sv))
		rs.add_child(b)

	# 性能监控（dev）
	var rp := _settings_row(vb, fnt, "性能监控 Dev")
	var pbtn := _mk_sbtn(fnt, "开/关 (F3)", 150)
	pbtn.pressed.connect(_toggle_perf)
	rp.add_child(pbtn)

	var hint := Label.new()
	hint.text = "改 NPC 数量 → 同种子重开小镇（确定性）"
	hint.add_theme_font_override("font", fnt)
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(0.66, 0.7, 0.82)
	vb.add_child(hint)

	var close := _mk_sbtn(fnt, "关闭 Close", 130)
	close.pressed.connect(func(): _settings_panel.visible = false)
	vb.add_child(close)

func _settings_row(vb: VBoxContainer, fnt: Font, label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label
	l.add_theme_font_override("font", fnt)
	l.add_theme_font_size_override("font_size", 16)
	l.custom_minimum_size = Vector2(148, 0)
	row.add_child(l)
	vb.add_child(row)
	return row

func _mk_sbtn(fnt: Font, txt: String, w: int) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_override("font", fnt)
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size = Vector2(w, 40)
	b.focus_mode = Control.FOCUS_NONE
	return b

func _toggle_settings() -> void:
	if _settings_panel != null:
		_settings_panel.visible = not _settings_panel.visible

func _sync_npc_val() -> void:
	if _npc_val != null:
		_npc_val.text = str(_npc_target)

## 改 NPC 数量 → 用同种子重开小镇（确定性；spawn_count=目标总数，克隆到 N）。
func _apply_npc(delta: int) -> void:
	var n := clampi(_npc_target + delta, 6, 60)
	if n == _npc_target:
		return
	_npc_target = n
	Sim.spawn_count = n
	Sim.start_new(_seed)
	Sim.auto_run = true
	if _player_mode:
		Sim.add_player()
	_selected_id = ""
	_max_tick = 0
	_save_sim_setting("npc_count", n)
	_sync_npc_val()
	_update_status()
	_update_obs()
	_update_scrubber()

func _set_speed(v: float) -> void:
	if v <= 0.0:
		Sim.running = false
	else:
		Sim.running = true
		Sim.speed = v
		_save_sim_setting("speed", v)
	_update_status()

func _save_sim_setting(key: String, val: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")   # 保留其他键（backend 等）
	cfg.set_value("sim", key, val)
	cfg.save("user://settings.cfg")

func _toggle_perf() -> void:
	_perf_on = not _perf_on
	if _perf != null:
		_perf.get_parent().visible = _perf_on     # 连同背景 panel 一起显隐
	_perf_last_tick = Sim.tick_no
	_perf_dt_acc = 0.0

## dev 性能 overlay 每帧刷（FPS 要每帧才平滑；关时早退，零开销）。
func _process(dt: float) -> void:
	if not _perf_on or _perf == null:
		return
	_perf_dt_acc += dt
	if _perf_dt_acc >= 0.5:                        # 每 0.5s 采一次 tick 率
		_perf_rate = float(Sim.tick_no - _perf_last_tick) / _perf_dt_acc
		_perf_last_tick = Sim.tick_no
		_perf_dt_acc = 0.0
	var ft := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var objs := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var st: Dictionary = AIBackend.stats
	_perf.text = "[color=#7ed957]● PERF[/color]  FPS %d [color=#9aa0b5](%.1fms)[/color]\n内存 %.0f MB\n对象 %d  节点 %d  绘制 %d\nNPC %d  tick %d [color=#9aa0b5](%.1f/s ×%.0f)[/color]\n后端 [color=#ffd166]%s[/color]  在飞 %d\nLLM 发起 %d 落地 %d 超时 %d 脏 %d" % [
		Engine.get_frames_per_second(), ft, mem, objs, nodes, draws,
		Sim.agents.size(), Sim.tick_no, _perf_rate, Sim.speed,
		AIBackend.backend, AIBackend._inflight,
		int(st.get("fired", 0)), int(st.get("landed", 0)), int(st.get("timeout", 0)), int(st.get("bad_parse", 0))]

func _update_status() -> void:
	if _status == null:
		return
	var tod := Sim.time_of_day()
	var mins := int(tod * 24.0 * 60.0)
	var clock := "%02d:%02d" % [mins / 60, mins % 60]
	var hh := mins / 60
	var phase := "夜 night"
	if hh >= 5 and hh < 11: phase = "晨 morning"
	elif hh >= 11 and hh < 17: phase = "昼 day"
	elif hh >= 17 and hh < 21: phase = "暮 evening"
	var spd := ("×%.0f" % Sim.speed) if Sim.running else "⏸ 暂停"
	var btxt := "🤖%s" % AIBackend.backend                                          # 当前生效后端（诚实显示：可能已被降级/正在排队切换）
	if AIBackend.backend != AIBackend.backend_requested:
		btxt += "→%s…" % AIBackend.backend_requested                              # 切换排队中（等在飞请求清空）
	var sn := ("%s " % Sim.season_today) if Sim.season_today != "" else ""          # Wave 3b 季节（贴在天气前）
	var wx := ("  ·  %s%s" % [sn, Sim.weather_today]) if (Sim.weather_today != "" or sn != "") else ""   # Wave 1c 天气 + 3b 季节
	var etxt := ""                                                                # Wave 3a 选举：状态栏显示最近一次表决结果
	if not Sim.last_election.is_empty():
		var le: Dictionary = Sim.last_election
		etxt = "  ·  🗳 %s %s %d:%d" % [String(le["topic"]), ("通过" if bool(le["pass"]) else "否决"), int(le["yea"]), int(le["nay"])]
	var meets_active := 0
	for c in Sim.commitments:
		if String(c["status"]) == "active":
			meets_active += 1
	var conf_active := 0
	for c in Sim.conflicts:
		var s := String(c["status"])
		if s == "simmering" or s == "escalated" or s == "confronted" or s == "lingering":
			conf_active += 1
	var ptxt := ""
	if _player_mode:
		var pl: Dictionary = Sim.get_agent("player")
		if not pl.is_empty():
			var pmeets := []
			for c in Sim.commitments:
				if String(c["status"]) == "active" and (String(c["a"]) == "player" or String(c["b"]) == "player"):
					var other := String(c["b"]) if String(c["a"]) == "player" else String(c["a"])
					pmeets.append("和%s约在%s(剩%dt)" % [Sim._name(Sim.get_agent(other)), Sim._area_label_id(String(c["area"])), int(c["deadline"]) - Sim.tick_no])
			ptxt = "\n[color=#ffd700]你：礼物×%d  WASD移动  选中居民后 G打招呼 F送礼 B八卦 Y约见 T理论 P道歉 M调解 C聊天%s[/color]" % [
				int(pl["inventory"].get("gift", 0)), ("  📌 " + "；".join(pmeets)) if not pmeets.is_empty() else ""]
	_status.text = "[color=#e6e9f2]小镇有灵 Living Town  ·  第 %d 天 %s %s%s%s  ·  %s  ·  %s  ·  NPC %d  ｜  事件 %d  约会 %d(活%d)  冲突 %d(活%d)[/color]%s" % [
		Sim.day, clock, phase, wx, etxt, spd, btxt, Sim.agents.size(), Sim.event_log.size(), Sim.commitments.size(), meets_active, Sim.conflicts.size(), conf_active, ptxt]

# ── 观察台 / 时间轴 ────────────────────────────────────────────────────────
func _update_scrubber() -> void:
	if _scrub_fill == null:
		return
	var m := maxi(1, _max_tick)
	var f := clampf(float(Sim.tick_no) / float(m), 0.0, 1.0)
	var w := SCRUB_X1 - SCRUB_X0
	_scrub_fill.size = Vector2(w * f, SCRUB_H)
	_scrub_handle.position = Vector2(SCRUB_X0 + w * f - 2.0, SCRUB_Y - 4.0)

func _update_obs() -> void:
	if _obs != null:
		_obs.text = _panel_text()
	if _chat_in != null:
		if _selected_id == "":
			_chat_in.visible = false
		elif not _chat_in.has_focus():
			_chat_in.visible = true
			_chat_in.placeholder_text = "对 %s 说…（Enter 发送）" % _nm(_selected_id)

## 玩家对选中 NPC 说话 → AIBackend.chat（llm/mock/罐头）→ 头顶回复气泡 + 日志 + 写入 NPC 记忆。
func _on_player_say(text: String) -> void:
	text = text.strip_edges()
	if _selected_id == "" or text == "":
		return
	var id := _selected_id
	var ag := Sim.get_agent(id)
	if ag.is_empty():
		return
	_push("[color=#9ad0ff]你 → %s：%s[/color]" % [_nm(id), text])
	ag["thinking"] = true
	AIBackend.chat(ag, text, {"tick": Sim.tick_no, "day": Sim.day}, func(reply: String):
		ag["thinking"] = false
		if _view != null and _view.has_method("show_say"):
			_view.show_say(id, reply, 90)
		_push("[color=#cfe8ff]%s：%s[/color]" % [_nm(id), reply])
		var mem = ag.get("memory")
		if mem != null:
			mem.add("玩家问『%s』，我答『%s』" % [text.substr(0, 18), reply.substr(0, 18)], 5, Sim.tick_no, [id, "player", "chat"])
	)
	if _chat_in != null:
		_chat_in.text = ""

func _bar(v: float) -> String:
	var n := int(round(clampf(v, 0.0, 100.0) / 10.0))
	return "█".repeat(n) + "·".repeat(10 - n)

func _panel_text() -> String:
	if _selected_id == "":
		return "[color=#cfd3e0]观察台 Observatory[/color]\n\n[color=#9aa0b5]点选一个居民（或按 Tab 轮换），查看其需求 / 关系 / 信念 / 冲突 / 记忆。[/color]"
	var ag := Sim.get_agent(_selected_id)
	if ag.is_empty():
		return "（无此角色）"
	var p: Dictionary = ag.get("persona", {})
	var L := []
	L.append("[color=#ffe08a]%s[/color]  [color=#9aa0b5]%s[/color]" % [str(p.get("name", _selected_id)), " ".join(p.get("traits", []))])
	L.append("[color=#9aa0b5]%s · 在 %s[/color]" % [str(p.get("bio", "")), Sim._area_label(ag["pos"])])
	var opt = ag.get("option")
	var doing := "闲着"
	if opt != null:
		doing = ("%s→%s" % [str(opt.get("action", "")), Sim._name(Sim.get_agent(String(opt.get("partner", ""))))]) if String(opt.get("kind", "")) == "social" else str(opt.get("action", ""))
	L.append("当前：[color=#cfe8ff]%s[/color]" % doing)
	if not Sim.economy.is_empty():
		L.append("钱：[color=#ffd166]%d 币[/color]" % int(ag["inventory"].get("coin", 0)))   # Wave 1b
	var _jb: Dictionary = Sim._job_of(_selected_id)
	if not _jb.is_empty():
		var _lv := Sim._skill_level(ag, String(_jb.get("action", "")))   # Wave 2c
		var _sk := ("  熟练 Lv%d" % _lv) if _lv > 0 else ""
		L.append("职业：[color=#9ad0ff]%s[/color] [color=#9aa0b5](班次 %s · 薪 %d)[/color][color=#ffd166]%s[/color]" % [
			String(_jb.get("title", "")), "/".join(_jb.get("shift", [])), int(_jb.get("wage", 0)), _sk])   # Wave 2a/2c
	L.append("")
	L.append("[color=#cfd3e0]需求[/color]")
	for n in Sim.needs_def:
		var nid: String = n["id"]
		var v := float(ag["needs"].get(nid, 0))
		var c := "#7ed957" if v > 35.0 else "#e85a5a"
		L.append("%s [color=%s]%s[/color] %d" % [str(n["label"]), c, _bar(v), int(v)])
	# 关系 top3
	L.append("")
	L.append("[color=#cfd3e0]关系[/color]")
	var rels: Dictionary = ag["relationships"]
	var arr := []
	for oid in rels:
		arr.append([oid, rels[oid]])
	arr.sort_custom(func(a, b): return absf(float(a[1]["affinity"])) > absf(float(b[1]["affinity"])))
	if arr.is_empty():
		L.append("[color=#9aa0b5]（还没有交集）[/color]")
	for i in mini(3, arr.size()):
		var oid: String = arr[i][0]
		var r: Dictionary = arr[i][1]
		var ac := "#7ed957" if float(r["affinity"]) >= 0 else "#e85a5a"
		var stv := int(r.get("standing", 0))
		var sttag := (" [color=#ffd166]名%+d[/color]" % stv) if stv != 0 else ""
		L.append("%s [color=%s]亲%d[/color] 信%d 怨%d%s" % [Sim._name(Sim.get_agent(oid)), ac, int(r["affinity"]), int(r.get("trust", 0)), int(r.get("resentment", 0)), sttag])
	# 信念
	var bel: Dictionary = ag["beliefs"]
	if not bel.is_empty():
		L.append("")
		L.append("[color=#cfd3e0]知道的事[/color]")
		for cid in bel:
			var b: Dictionary = bel[cid]
			var src := String(b.get("source", ""))
			var src_name := "亲历/听闻" if src == "__seed__" else ("听 %s 说" % Sim._name(Sim.get_agent(src)))
			L.append("[color=#d9c2ff]%s[/color] [color=#9aa0b5](%s)[/color]" % [str(b.get("claim", cid)), src_name])
	# 观点（S2：每话题 attitude，+绿/-红；偏离天生立场=被说动过）
	var att: Dictionary = ag.get("attitudes", {})
	if not att.is_empty():
		L.append("")
		L.append("[color=#cfd3e0]观点[/color]")
		var topic_label := {"cafe_expand": "扩建咖啡馆", "night_market": "办夜市", "old_tales": "老故事"}
		for t in att:
			var v := float(att[t])
			var c2 := "#7ed957" if v >= 0.0 else "#e85a5a"
			L.append("%s [color=%s]%+.2f[/color]" % [str(topic_label.get(t, t)), c2, v])
	# S3 派系 / 盟约 / 秘密
	var fac := String(ag.get("faction", ""))
	if fac != "":
		var fsz := int(ag.get("faction_size", 1))
		L.append("")
		L.append("[color=#cfd3e0]派系[/color] [color=#d9c2ff]%s 派（%d人）[/color]" % [Sim._name(Sim.get_agent(fac)), fsz])
	var pacts: Dictionary = ag.get("pacts", {})
	var pact_names := []
	for oid2 in pacts:
		if String(pacts[oid2].get("status", "")) == "active":
			pact_names.append("%s(给%d/收%d)" % [Sim._name(Sim.get_agent(oid2)), int(pacts[oid2].get("given", 0)), int(pacts[oid2].get("received", 0))])
	if not pact_names.is_empty():
		L.append("[color=#cfd3e0]互助盟约[/color] [color=#39d4c8]%s[/color]" % "  ".join(pact_names))
	var sec_own := 0
	var sec_held := 0
	for cid3 in ag.get("beliefs", {}):
		var bb: Dictionary = ag["beliefs"][cid3]
		if bool(bb.get("secret", false)):
			if String(bb.get("owner", "")) == _selected_id: sec_own += 1
			else: sec_held += 1
	if sec_own + sec_held > 0:
		L.append("[color=#cfd3e0]秘密[/color] [color=#c792ea]自有%d · 被托付%d[/color]" % [sec_own, sec_held])
	# 冲突
	var cf := []
	for c in Sim.conflicts:
		var s := String(c["status"])
		if (s == "simmering" or s == "escalated" or s == "confronted" or s == "lingering") and (c["a"] == _selected_id or c["b"] == _selected_id):
			var other: String = c["b"] if c["a"] == _selected_id else c["a"]
			var role := "怨" if c["a"] == _selected_id else "被怨"
			cf.append("%s %s [color=#ff8c42]%s[/color]" % [role, Sim._name(Sim.get_agent(other)), s])
	if not cf.is_empty():
		L.append("")
		L.append("[color=#cfd3e0]冲突[/color]")
		L.append_array(cf)
	# 近期记忆
	var mem = ag.get("memory")
	if mem != null and not mem.items.is_empty():
		L.append("")
		L.append("[color=#cfd3e0]近期记忆[/color]")
		var items: Array = mem.items
		for i in range(maxi(0, items.size() - 4), items.size()):
			L.append("[color=#b8c0d0]· %s[/color]" % str(items[i]["text"]))
	return "\n".join(L)

# ── --player-demo：脚本化玩家 autopilot（录 demo 用；确定性按 tick 执行剧本）─────────
## 舞台布置：预埋一段 ben-coco 冲突（双方在广场、对玩家有基础好感）→ 剧本=调解→找阿丽 打招呼/送礼/约见/聊天。
func _demo_setup() -> void:
	# 先把世界暖到清晨 ~09:30（首帧前，movie 从白天开场；夜里全镇在睡觉，社交 demo 没戏可拍）
	for i in 95:
		Sim.tick()
	var pl: Dictionary = Sim.get_agent("player")
	Sim.conflicts.append({"a": "ben", "b": "coco", "status": "simmering", "severity": 8.0,
		"escalations": 0, "confronted": 0, "repaired": 0, "triggered": Sim.tick_no, "lastEscalate": Sim.tick_no})
	for id in ["ben", "coco"]:
		var ag: Dictionary = Sim.get_agent(id)
		ag["option"] = null
		ag["talking"] = 0
		Sim._move_agent(ag, pl["pos"] + Vector2i(1 if id == "ben" else -1, 1))
		Sim._rel(ag, "player")["affinity"] = 12.0
	# 把两人钉在"僵持对话"里（互为社交对象 → 原地站定，画面上有对话连线），玩家走进来调解——比赛跑他们的早饭稳
	var _ben: Dictionary = Sim.get_agent("ben")
	var _coco: Dictionary = Sim.get_agent("coco")
	_ben["option"] = {"kind": "social", "action": "greet", "partner": "coco", "subject": "", "remaining": 24}
	_coco["option"] = {"kind": "social", "action": "greet", "partner": "ben", "subject": "", "remaining": 24}
	_ben["talking"] = 24
	_coco["talking"] = 24
	_demo_steps = [
		{"type": "wait", "left": 4},
		{"type": "select", "id": "ben"},
		{"type": "act", "action": "mediate", "target": "ben"},
		{"type": "wait", "left": 30},
		{"type": "select", "id": "aria"},
		{"type": "walk_to", "id": "aria"},
		{"type": "act", "action": "greet", "target": "aria"},
		{"type": "wait", "left": 24},
		{"type": "walk_to", "id": "aria"},
		{"type": "act", "action": "give", "target": "aria"},
		{"type": "wait", "left": 24},
		{"type": "walk_to", "id": "aria"},
		{"type": "act", "action": "invite", "target": "aria"},
		{"type": "wait", "left": 30},
		{"type": "chat", "text": "最近镇上有什么新鲜事吗？"},
	]
	_demo_i = 0

## 每 tick 推进剧本一步：walk_to=朝目标走一格直到可社交距离；act=玩家动作；chat=真模型对话。
func _demo_tick() -> void:
	if _demo_i >= _demo_steps.size():
		return
	var pl: Dictionary = Sim.get_agent("player")
	if pl.is_empty():
		return
	var s: Dictionary = _demo_steps[_demo_i]
	match String(s["type"]):
		"wait":
			s["left"] = int(s["left"]) - 1
			if int(s["left"]) <= 0:
				_demo_i += 1
		"select":
			_selected_id = String(s["id"])
			_update_obs()
			_demo_i += 1
		"walk_to":
			var tgt: Dictionary = Sim.get_agent(String(s["id"]))
			if tgt.is_empty():
				_demo_i += 1
				return
			var here := Sim._area_at(pl["pos"])
			var d: Vector2i = tgt["pos"] - pl["pos"]
			if (here != "" and here == Sim._area_at(tgt["pos"])) or absi(d.x) + absi(d.y) <= 2:
				_demo_i += 1                       # 已到可社交距离
			elif absi(d.x) >= absi(d.y):
				Sim.player_move(Vector2i(signi(d.x), 0))
			else:
				Sim.player_move(Vector2i(0, signi(d.y)))
		"act":
			if int(pl["talking"]) > 0:
				return                             # 等上一段对话结束
			var m := Sim.player_mediate(String(s["target"])) if String(s["action"]) == "mediate" else Sim.player_act(String(s["action"]), String(s["target"]))
			if m != "":
				_push("[color=#f2a3a3]（%s）[/color]" % m)
			_demo_i += 1
		"chat":
			_on_player_say(String(s["text"]))
			_demo_i += 1

## 玩家社交动作分发（--player 模式，目标=当前选中居民）；不可行原因打进事件日志。
func _player_do(action: String) -> void:
	if not _player_mode:
		return
	if _selected_id == "" or _selected_id == "player":
		_push("[color=#f2a3a3]（先用 Tab/点选一位居民，再按动作键）[/color]")
		return
	var msg := Sim.player_mediate(_selected_id) if action == "mediate" else Sim.player_act(action, _selected_id)
	if msg != "":
		_push("[color=#f2a3a3]（%s）[/color]" % msg)

func _cycle_selection(dir: int) -> void:
	if Sim.agents.is_empty():
		return
	var ids := []
	for a in Sim.agents:
		if not a.get("is_player", false):
			ids.append(a["id"])       # 玩家不进观察循环（动作目标只会是居民）
	if ids.is_empty():
		return
	var i := ids.find(_selected_id)
	i = (i + dir + ids.size()) % ids.size()
	_selected_id = String(ids[i])
	_update_obs()

func _select_at_mouse() -> void:
	var w := get_global_mouse_position()
	var best := ""
	var bestd := 1.0e9
	for a in Sim.agents:
		var c := Vector2(a["pos"].x * 48 + 24, a["pos"].y * 48 + 24)
		var d := c.distance_to(w)
		if d < bestd:
			bestd = d
			best = String(a["id"])
	if bestd <= 42.0:
		_selected_id = best
		_update_obs()

func _in_scrub(pos: Vector2) -> bool:
	return pos.x >= SCRUB_X0 - 8 and pos.x <= SCRUB_X1 + 8 and pos.y >= SCRUB_Y - 12 and pos.y <= SCRUB_Y + SCRUB_H + 12

func _scrub_to_x(x: float) -> void:
	var f := clampf((x - SCRUB_X0) / (SCRUB_X1 - SCRUB_X0), 0.0, 1.0)
	Sim.running = false
	Sim.goto_tick(int(round(f * _max_tick)))
	_after_jump()

func _after_jump() -> void:
	_modulate.color = _daylight(Sim.time_of_day())
	_update_status()
	_update_scrubber()
	_update_obs()

func _nm(id: Variant) -> String:
	var a := Sim.get_agent(String(id))
	return str(a.get("persona", {}).get("name", id)) if not a.is_empty() else String(id)

func _on_social(e: Dictionary) -> void:
	var A := _nm(e["actor"])
	var B := _nm(e["target"])
	var ok := bool(e["accepted"])
	var line := ""
	match String(e["type"]):
		"greet": line = "[color=#cfe8ff]%s 找 %s 唠了两句[/color]" % [A, B]
		"give": line = "[color=#cfe8ff]%s 送了 %s 一份小礼物[/color]" % [A, B]
		"gossip": line = "[color=#d9c2ff]%s 悄悄向 %s 传了个八卦[/color]" % [A, B]
		"invite": line = "[color=#bfe6c8]%s 约了 %s 稍后见面[/color]" % [A, B]
		"meet": line = ("[color=#7ed957]%s 与 %s 如约见面，更亲近了[/color]" % [A, B]) if ok else ("[color=#e85a5a]%s 与 %s 的约会泡汤了（有人爽约）[/color]" % [A, B])
		"conflict": line = "[color=#ffb3b3]%s 对 %s 渐渐积起了怨气[/color]" % [A, B]
		"confront": line = ("[color=#ffd166]%s 当面找 %s 把话说开[/color]" % [A, B]) if ok else ("[color=#ff8c42]%s 质问 %s，对方不认（冲突升级）[/color]" % [A, B])
		"apologize": line = ("[color=#7ed957]%s 向 %s 道了歉，两人和解[/color]" % [A, B]) if ok else ("[color=#e85a5a]%s 道歉，%s 一时还无法原谅[/color]" % [A, B])
		_: line = "[color=#aaaaaa]%s · %s · %s[/color]" % [A, String(e["type"]), B]
	_push(line)

func _push(line: String) -> void:
	_log_lines.append(line)
	if _log_lines.size() > LOG_CAP:
		_log_lines = _log_lines.slice(_log_lines.size() - LOG_CAP, _log_lines.size())
	if _logbox != null:
		_logbox.text = "\n".join(_log_lines)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_SPACE: Sim.running = not Sim.running
			KEY_0, KEY_KP_0: Sim.running = false
			KEY_1, KEY_KP_1: Sim.running = true; Sim.speed = 1.0
			KEY_2, KEY_KP_2: Sim.running = true; Sim.speed = 2.0
			KEY_3, KEY_KP_3: Sim.running = true; Sim.speed = 4.0
			KEY_4, KEY_KP_4: Sim.running = true; Sim.speed = 8.0
			KEY_EQUAL, KEY_KP_ADD: _cam.zoom = (_cam.zoom * 1.15).clamp(ZOOM_MIN, ZOOM_MAX)
			KEY_MINUS, KEY_KP_SUBTRACT: _cam.zoom = (_cam.zoom / 1.15).clamp(ZOOM_MIN, ZOOM_MAX)
			KEY_TAB: _cycle_selection(-1 if e.shift_pressed else 1)
			KEY_O: _toggle_settings()                            # ⚙ 设置面板开关（NPC 数量/速度/后端）
			KEY_F3: _toggle_perf()                               # dev 性能 overlay 开关
			KEY_ESCAPE: _selected_id = ""; _update_obs()
			KEY_C: _on_player_say("你好，最近怎么样？")        # 快捷：对选中居民打个招呼（也便于无键盘验证）
			# ── 玩家能动性（--player）：WASD 移动 + 对选中居民 G打招呼/F送礼/B八卦/Y约见/P道歉/M调解 ──
			KEY_W, KEY_UP: if _player_mode: Sim.player_move(Vector2i(0, -1))
			KEY_S, KEY_DOWN: if _player_mode: Sim.player_move(Vector2i(0, 1))
			KEY_A, KEY_LEFT: if _player_mode: Sim.player_move(Vector2i(-1, 0))
			KEY_D, KEY_RIGHT: if _player_mode: Sim.player_move(Vector2i(1, 0))
			KEY_G: _player_do("greet")
			KEY_F: _player_do("give")
			KEY_B: _player_do("gossip")
			KEY_Y: _player_do("invite")
			KEY_T: _player_do("confront")
			KEY_P: _player_do("apologize")
			KEY_M: _player_do("mediate")
			KEY_PERIOD: if not Sim.running: Sim.tick()                                   # 单步 +1
			KEY_COMMA: Sim.running = false; Sim.goto_tick(maxi(0, Sim.tick_no - 1)); _after_jump()
			KEY_BRACKETLEFT: Sim.running = false; Sim.goto_tick(maxi(0, Sim.tick_no - Sim.TICKS_PER_DAY)); _after_jump()
			KEY_BRACKETRIGHT: Sim.running = false; Sim.goto_tick(Sim.tick_no + Sim.TICKS_PER_DAY); _after_jump()
		_update_status()
	elif e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			_cam.zoom = (_cam.zoom * 1.12).clamp(ZOOM_MIN, ZOOM_MAX)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			_cam.zoom = (_cam.zoom / 1.12).clamp(ZOOM_MIN, ZOOM_MAX)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				if _in_scrub(e.position):
					_scrubbing = true
					_scrub_to_x(e.position.x)
				else:
					_select_at_mouse()
			else:
				_scrubbing = false
	elif e is InputEventMouseMotion and _scrubbing:
		_scrub_to_x(e.position.x)
