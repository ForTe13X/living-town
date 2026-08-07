extends Node
## AR2 眼验（一次性；跑完从 game/ 移除，只留 PNG）。把一串【固定】事件喂进【真】Main._event_prose，
## 铺进一个与 Main._logbox 逐项同配的 RichTextLabel（Art.font() 得意黑 + 字号 15 + 播报 scrim 底），
## windowed 真 framebuffer 渲一帧存 PNG。事件表按类型分组且同类多条 ⇒ 改前=同句刷屏、改后=同类轮换措辞。
## 用真居民（Sim.start_new）好让 gossip_rep/endorse 的 subject 解析出名字（C!=""）。
## 用法（Windows 真窗口）：godot --path game --resolution 700x600 --single-window res://scenes/ar2_eyeball_probe.tscn -- --out <abs.png>
const MainScript = preload("res://scripts/Main.gd")

func _ev(id: int, tick: int, type: String, actor: String, target: String, accepted: bool,
		subject: String = "", note: String = "") -> Dictionary:
	return {"id": id, "tick": tick, "type": type, "actor": actor, "target": target,
		"subject": subject, "accepted": accepted, "witnesses": [], "note": note}

func _ready() -> void:
	var out_path := "res://_ar2_feed.png"
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out_path = args[i + 1]

	Sim.backend = null
	Sim.record_decisions = false
	Sim.auto_run = false
	Sim.start_new(7)
	var g: Array = []
	for a in Sim.agents:
		g.append(String(a["id"]))
	while g.size() < 6:
		g.append("居民%d" % g.size())
	var main = MainScript.new()

	# 固定事件表：同类多条（不同对/不同 tick），最能看出"同一句刷屏 → 同类轮换"。
	var evs: Array = [
		_ev(0, 100, "greet", g[0], g[1], true),
		_ev(1, 240, "greet", g[2], g[3], true),
		_ev(2, 360, "greet", g[4], g[5], true),
		_ev(3, 520, "greet", g[1], g[4], false),
		_ev(4, 610, "discuss", g[0], g[2], true),
		_ev(5, 705, "discuss", g[3], g[1], true),
		_ev(6, 860, "discuss", g[5], g[4], true),
		_ev(7, 940, "gossip", g[0], g[3], true),
		_ev(8, 1020, "gossip", g[2], g[4], true),
		_ev(9, 1180, "give", g[1], g[2], true),
		_ev(10, 1260, "give", g[4], g[0], false),
		_ev(11, 1330, "gossip_rep", g[0], g[1], true, g[2]),
		_ev(12, 1440, "endorse", g[3], g[4], true, g[5]),
		_ev(13, 1520, "conflict", g[2], g[5], false),
		_ev(14, 1610, "confront", g[2], g[5], true),
		_ev(15, 1980, "apologize", g[5], g[2], true),
		_ev(16, 2100, "aid", g[3], g[0], true),
		_ev(17, 2260, "meet", g[0], g[1], true),
	]
	var lines: Array = ["[color=#ffd166]◆ 编年史 · 播报栏（同一批事件的成文）[/color]"]
	for e in evs:
		lines.append(main._event_prose(e))
	var txt := "\n".join(lines)
	print("=== 编年史成文（%d 行）===" % lines.size())
	for line in lines:
		print("  " + line)
	main.free()

	var win := Vector2i(700, 600)
	get_window().size = win
	get_window().content_scale_size = win
	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.06, 0.09, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := RichTextLabel.new()
	box.bbcode_enabled = true
	box.scroll_active = false
	box.add_theme_font_override("normal_font", Art.font())
	box.add_theme_font_size_override("normal_font_size", 15)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 14
	box.offset_top = 12
	box.offset_right = -14
	box.offset_bottom = -12
	box.text = txt
	add_child(box)

	for _i in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	print("save_png(%s) err=%d size=%dx%d" % [out_path, err, img.get_width(), img.get_height()])
	get_tree().quit(0 if err == OK else 1)
