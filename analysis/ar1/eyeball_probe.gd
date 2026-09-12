extends Node
## AR1 眼验（一次性；跑完从 game/ 移除）。把 Story.gd 的**真 panel_text()** 喂进一个与 Main._story_box
## 逐项同配的 RichTextLabel（bbcode + Art.font() 得意黑 + 字号 14），windowed 真 framebuffer 渲一帧存 PNG。
## 合成的因果链里，唯一收场的一段是**带 traded 幕的怨气弧** ⇒ 面板 closed[0] 全文里必现「银钱往来」。
const StoryScript = preload("res://scripts/Story.gd")
const STORY_SZ := Vector2(470.0, 332.0)

func _ev(id: int, tick: int, type: String, actor: String, target: String, accepted: bool,
		subject: String = "", note: String = "", witnesses: Array = []) -> Dictionary:
	return {"id": id, "tick": tick, "type": type, "actor": actor, "target": target,
		"subject": subject, "accepted": accepted, "witnesses": witnesses, "note": note}

func _nm(id: String) -> String:
	return {"aria": "阿丽", "ben": "本", "coco": "可可", "dan": "丹", "ed": "二郎", "fred": "阿福"}.get(id, id)

func _ready() -> void:
	var f: Array = [
		# 唯一收场的一段：怨气弧，中途落一笔买卖(traded)，再当面说开、和解收场 ⇒ closed[0] 全文含「银钱往来」
		_ev(0, 100, "conflict", "aria", "ben", false),
		_ev(1, 120, "gossip_rep", "aria", "coco", false, "ben"),
		_ev(2, 150, "pay", "aria", "ben", true, "", "buy:bread"),
		_ev(3, 170, "gossip_rep", "aria", "dan", false, "ben"),
		_ev(4, 200, "confront", "aria", "ben", true),
		_ev(5, 760, "apologize", "ben", "aria", true),
		# 进行中的一段：手艺弧，也牵着一条银钱往来（在「还在往下走」里露出这条弧）
		_ev(6, 300, "produce", "ed", "town", true, "柴薪", "樵夫*3", ["fred"]),
		_ev(7, 350, "pay", "fred", "ed", true, "", "rent"),
		# 进行中的一段：盟约，也没断银钱往来
		_ev(8, 400, "pact", "coco", "dan", true, "", "formed"),
		_ev(9, 450, "pay", "dan", "coco", true, "", "rent"),
	]
	var story := StoryScript.new()
	story.sync(f)
	var txt := story.panel_text(_nm)
	print("=== 面板文本（去 BBCode）===")
	for line in txt.split("\n"):
		print("  " + line)

	# 先把窗口/视口定成面板尺寸，再铺内容（避免内容缩在左上角）
	var win := Vector2i(int(STORY_SZ.x), int(STORY_SZ.y))
	get_window().size = win
	get_window().content_scale_size = win

	# —— 与 Main._story_pan / _story_box 同配的最小面板（铺满视口）——
	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.06, 0.09, 1.0)         # 近似播报 scrim 的深色底
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := RichTextLabel.new()
	box.bbcode_enabled = true
	box.scroll_active = false
	box.add_theme_font_override("normal_font", Art.font())
	box.add_theme_font_size_override("normal_font_size", 14)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 12
	box.offset_top = 8
	box.offset_right = -12
	box.offset_bottom = -8
	box.text = txt
	add_child(box)

	# 等几帧让字体/排版落定，再抓帧
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := "res://_ar1_story_panel.png"
	var err := img.save_png(out)
	print("save_png(%s) err=%d  size=%dx%d" % [out, err, img.get_width(), img.get_height()])
	get_tree().quit(0 if err == OK else 1)
