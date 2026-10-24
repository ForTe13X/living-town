extends Node
## Compact town presentation around the existing Main controls and callbacks.
## Existing log/card nodes retain visibility ownership for the recording director.
const Look = preload("res://scripts/ui/TownHudStyle.gd")
var main: Node2D
var font: Font
var toolbar: HBoxContainer
var activity: Button
var feedback: RichTextLabel
var expanded: bool = false
var feedback_seconds: float = 0.0
var buttons: Array[Button] = []
var speed_key: String = ""
var full_feed: String = ""
var feedback_suppressed: bool = false

func setup(owner_main: Node2D, hud_font: Font) -> void:
	main = owner_main
	font = hud_font
	var status: RichTextLabel = main.get("_status") as RichTextLabel
	status.add_theme_font_size_override("normal_font_size",16)
	status.add_theme_color_override("default_color",Look.LINEN)
	var status_panel: ColorRect = main.get("_status_pan") as ColorRect
	status_panel.color = Look.INK
	(main.get("_status_line") as ColorRect).hide()
	(main.get("_backend_btn") as Button).hide()
	var menu: Button = main.get("_gear_btn") as Button
	menu.text = "菜单 Menu"
	menu.tooltip_text = "设置、存档 F5、读档 F8、推理与性能详情"
	Look.button(menu,font)
	toolbar = HBoxContainer.new()
	toolbar.name = "TownClockControls"
	toolbar.add_theme_constant_override("separation",4)
	status_panel.add_child(toolbar)
	for value: float in [0.0,1.0,2.0,4.0]:
		var button := Button.new()
		button.text = "暂停" if value == 0.0 else "%d×" % int(value)
		button.custom_minimum_size = Vector2(56 if value == 0 else 40,30)
		button.tooltip_text = "暂停 / Pause（空格或0）" if value == 0 else "速度 %d× / Speed（键%d）" % [int(value),[1.0,2.0,4.0].find(value)+1]
		Look.button(button,font)
		button.pressed.connect(select_speed.bind(value))
		toolbar.add_child(button)
		buttons.append(button)
	var card: Panel = main.get("_log_card") as Panel
	card.add_theme_stylebox_override("panel",Look.panel())
	var log: RichTextLabel = main.get("_logbox") as RichTextLabel
	log.reparent(card)
	log.scroll_active = true
	log.add_theme_font_size_override("normal_font_size",14)
	activity = Button.new()
	activity.name = "ActivityExpand"
	Look.button(activity,font)
	activity.alignment = HORIZONTAL_ALIGNMENT_LEFT
	activity.tooltip_text = "H 展开近况、大事与纪事 / Open activity. 点击居民名查看当事人。"
	activity.pressed.connect(toggle_activity)
	card.add_child(activity)
	feedback = RichTextLabel.new()
	feedback.name = "TownImportantFeedback"
	feedback.bbcode_enabled = true
	feedback.scroll_active = false
	feedback.add_theme_font_override("normal_font",font)
	feedback.add_theme_font_size_override("normal_font_size",15)
	feedback.add_theme_stylebox_override("normal",Look.panel(true))
	feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feedback.hide()
	status_panel.add_child(feedback)
	layout()

func select_speed(value: float) -> void:
	var life: Node = main.get("_life")
	if clock_blocked(): return
	if life != null and bool(life.get("active")):
		life.call("_set_speed",value)
	else:
		main.call("_set_speed",value)
	sync_speed()

func sync_speed() -> void:
	var blocked: bool = clock_blocked()
	var key: String = str(Sim.running)+":"+str(Sim.speed)+":"+str(blocked)
	if key == speed_key: return
	speed_key = key
	for index: int in range(buttons.size()):
		var selected: bool = (not Sim.running and index == 0) or (Sim.running and index > 0 and is_equal_approx(Sim.speed,[0.0,1.0,2.0,4.0][index]))
		var style := Look.panel(selected)
		if selected: style.border_color = Look.ACCENT
		buttons[index].add_theme_stylebox_override("normal",style)
		buttons[index].disabled = blocked

func clock_blocked() -> bool:
	var life: Node = main.get("_life")
	if life != null:
		var chat: Control = life.get("_chat_box") as Control
		if bool(life.get("selecting")) or bool(life.get("_modal_open")) or (chat != null and chat.visible): return true
	for key: String in ["_bank_panel","_civic_panel"]:
		var panel: Control = main.get(key) as Control
		if panel != null and panel.visible: return true
	return false

func update_status(compact: String, detail: String, player_line: String) -> void:
	var status: RichTextLabel = main.get("_status") as RichTextLabel
	status.text = compact + player_line
	status.tooltip_text = detail
	sync_speed()

func update_feed(lines: Array, hot: Array, recent: Array) -> void:
	full_feed = "\n".join(lines)
	var log: RichTextLabel = main.get("_logbox") as RichTextLabel
	log.text = full_feed
	log.tooltip_text = log.get_parsed_text()
	if not expanded:
		var compact: Array = []
		for line: String in recent.slice(maxi(0,recent.size()-2)):
			if not compact.has(line): compact.append(line)
		log.text = "\n".join(compact) if not compact.is_empty() else "小镇的近况会出现在这里。"
	activity.text = ("收起近况 Activity [H] −" if expanded else "近况 Activity [H] +") + ("  · 大事%d" % hot.size() if not hot.is_empty() else "")

func notify(line: String, critical: bool = false) -> void:
	if not critical and not ("存档" in line or "读档" in line or "失败" in line or "无法" in line or "拒绝" in line or "#f2a3a3" in line or "#ff8c42" in line): return
	feedback.text = line
	feedback.tooltip_text = feedback.get_parsed_text()
	feedback_seconds = 7.0
	feedback.show()

func toggle_activity() -> void:
	expanded = not expanded
	layout()
	main.call("_render_log")

func set_feedback_suppressed(value: bool) -> void:
	# Optional presentation hook; never consumes or removes the retained event.
	feedback_suppressed = value
	if value: feedback.hide()

func layout() -> void:
	if main == null: return
	var vp: Vector2 = main.call("_vp")
	var status: RichTextLabel = main.get("_status") as RichTextLabel
	var panel: ColorRect = main.get("_status_pan") as ColorRect
	var narrow: bool = vp.x < 1000
	var player: bool = bool(main.get("_player_mode"))
	panel.position = Vector2(12,4)
	panel.size = Vector2(maxf(600,vp.x-24),(94 if player else 72) if narrow else (62 if player else 40))
	status.position = Vector2(26,12)
	status.size = Vector2(maxf(250,vp.x-(52 if narrow else 410)),52 if player else 28)
	toolbar.position = Vector2(maxf(356,vp.x-338),(61 if player else 39) if narrow else 5)
	toolbar.size = Vector2(188,30)
	var menu: Button = main.get("_gear_btn") as Button
	menu.position = Vector2(maxf(554,vp.x-120),(65 if player else 43) if narrow else 9)
	menu.size = Vector2(96,30)
	(main.get("_backend_btn") as Button).hide()
	(main.get("_obs_btn") as Button).hide()
	(main.get("_log_pan") as TextureRect).hide()
	var card: Panel = main.get("_log_card") as Panel
	var width: float = minf(384,maxf(280,vp.x*0.34))
	var height: float = minf(306,vp.y*0.45) if expanded else 118.0
	var life: Node = main.get("_life")
	if expanded and life != null:
		var wishes: Control = life.get("_wants_panel") as Control
		if wishes != null and wishes.is_visible_in_tree():
			height = minf(height,maxf(80,vp.y-38-wishes.get_global_rect().end.y-12))
	card.position = Vector2(12,maxf(170,vp.y-height-38))
	card.size = Vector2(width,height)
	activity.position = Vector2(8,6)
	activity.size = Vector2(width-16,26)
	var log: RichTextLabel = main.get("_logbox") as RichTextLabel
	log.position = Vector2(12,38)
	log.size = Vector2(width-24,height-46)
	var feedback_width: float = minf(520,vp.x-(316 if narrow else 48))
	var feedback_x: float = vp.x-feedback_width-12 if narrow else (vp.x-feedback_width)*0.5
	feedback.position = Vector2(feedback_x-panel.position.x,panel.size.y+10)
	feedback.size = Vector2(feedback_width,58)
	var settings: ColorRect = main.get("_settings_panel") as ColorRect
	if settings != null:
		settings.position = Vector2(maxf(8,(vp.x-settings.size.x)*0.5),maxf(8,(vp.y-settings.size.y)*0.5))
		settings.color = Look.INK

func _process(delta: float) -> void:
	sync_speed()
	if feedback_seconds > 0:
		feedback_seconds -= delta
		var life: Node = main.get("_life")
		# The existing director pauses LifeMode's presentation during architecture
		# inspection. New transient chrome follows the same visibility contract.
		feedback.visible = feedback_seconds > 0 and not feedback_suppressed and (life == null or life.is_processing())
