extends Node
## player_touch_test.gd — 触屏动作条【与物理键等价】的 headless 硬门（Wave C · C3）。
##
## 要证的命题：手机上新加的 7 个屏幕按钮，走的是与 KEY_G/F/B/Y/T/P/M 完全同一条路径，
## 且那条路径的末端就是 Sim.player_act / Sim.player_mediate —— 没有第二套动作实现在暗处漂移。
##
## 三层断言（一层都不能少，理由见各节）：
##   A) 【字符串】同一 fixture 上 Main._player_do(verb) 与 Sim.player_act(verb, target) 返回同一个串。
##   B) 【接线】button.pressed 发一次 ≡ 直接调 _player_do(verb)：事后 (digest, event_digest, event_log 长度)
##      逐字节相同。这一条才真正钉住"第 i 个按钮绑的是第 i 个动词"——只有 A 的话，7 个按钮全绑 greet 也能过。
##   C) 【校准点】7 个动词在本 fixture 上必须能被区分开（互不相同的 digest ≥ 5 种）。
##      没有这一条，一个"所有动作都被前置校验挡掉、什么也没发生"的坏 fixture 会让 A/B 双双空过
##      （docs/41 §5：数字要有零假设 + 已知答案的校准点）。
##
## 另外顺带守两条 C3 的红线：
##   · 默认【关】玩家模式（digest 零扰动）；开是玩家自己按的受控动作（docs/41 §3）。
##   · 动作条在非玩家模式下不可见（隐藏的 Control 不吃输入 → 世界点选不被吞）。
##
## 跑法：godot --headless --path game res://scenes/player_touch_test.tscn
## （本测试自带 hermetic 的 user://settings.cfg，跑完还原 —— 不依赖也不破坏本机的既有设置。）

const Inv = preload("res://bench/Invariants.gd")
const CFG := "user://settings.cfg"

var _fails := 0
var _main: Node2D
var _cfg_backup: PackedByteArray = PackedByteArray()
var _cfg_existed := false

func _ck(name: String, ok: bool, detail: String = "") -> void:
	print("  %s %s  %s" % [("✅" if ok else "❌"), name, detail])
	if not ok:
		_fails += 1

# ── hermetic 的启动设置 ────────────────────────────────────────────────────
# Main._ready() 会读 user://settings.cfg 决定后端/人数/速度/玩家模式。本机上它可能写着 mock 甚至 slm，
# 那样这个测试在不同机器上跑的就是不同的东西（而且可能真去 load 一个 1.9GB 的 gguf）。
func _pin_settings() -> void:
	_cfg_existed = FileAccess.file_exists(CFG)
	if _cfg_existed:
		_cfg_backup = FileAccess.get_file_as_bytes(CFG)
	var c := ConfigFile.new()
	c.set_value("backend", "mode", "logic")
	c.set_value("sim", "player", false)     # ★默认必须是关 —— 本身就是被断言的一条
	c.set_value("sim", "speed", 1.0)
	c.save(CFG)

func _restore_settings() -> void:
	if _cfg_existed:
		var f := FileAccess.open(CFG, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_cfg_backup)
			f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))

## 每个动词的目标：都要"这个动作在此 fixture 上真的能发生"，否则断言退化成"两边都被挡住"。
func _target_for(verb: String) -> String:
	return "ben" if verb == "mediate" else "aria"

## 造一份【逐字节可复现】的场面：玩家 + aria/ben/coco 贴身、玩家有可传的秘密、
## 一段 player↔aria 冲突（供 confront/apologize）、一段 ben↔coco 冲突（供 mediate，且双方对玩家好感够）。
func _fixture() -> void:
	Sim.backend = null
	Sim.start_new(7)
	Sim.auto_run = false          # Main._ready/_toggle 会把它打开；帧驱动的 tick 会毁掉可复现性
	Sim.running = false
	var pl := Sim.add_player()
	for id in ["aria", "ben", "coco"]:
		var ag: Dictionary = Sim.get_agent(id)
		ag["option"] = null
		ag["talking"] = 0
		ag["space"] = pl.get("space", "town")
		ag["floor"] = pl.get("floor", "outdoor")
		Sim._move_agent(ag, pl["pos"] + Vector2i(1, 0))
		Sim._rel(ag, "player")["affinity"] = 20.0      # > Sim.MEDIATE_AFF(5)，调解听得进去
		Sim._rel(pl, id)["affinity"] = 20.0
	pl["option"] = null
	pl["talking"] = 0
	pl["beliefs"]["R9"] = {"claim": "码头夜里有灯光", "subject": "dan", "source": "player", "via": "seed", "tick": Sim.tick_no}
	# 玩家是被怨的一方 → confront/apologize 两条分支都有事可做
	Sim.conflicts.append({"a": "player", "b": "aria", "status": "simmering", "severity": 6.0,
		"escalations": 0, "confronted": 0, "repaired": 0, "triggered": Sim.tick_no, "lastEscalate": Sim.tick_no})
	Sim.conflicts.append({"a": "ben", "b": "coco", "status": "simmering", "severity": 8.0,
		"escalations": 0, "confronted": 0, "repaired": 0, "triggered": Sim.tick_no, "lastEscalate": Sim.tick_no})

func _state() -> String:
	return "%d/%d/%d/%d" % [Sim.tick_no, Inv.digest(Sim), Sim.event_digest, Sim.event_log.size()]

func _ready() -> void:
	_pin_settings()
	print("=== 触屏动作条 ≡ 物理键 验证（Wave C · C3）===")

	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)                       # 同步触发 Main._ready()
	Sim.auto_run = false
	Sim.running = false
	Sim.backend = null

	# ── 0) 默认关：digest 零扰动 + 动作条不可见 ──
	_ck("默认不入玩家模式", not _main._player_mode and Sim.get_agent("player").is_empty(),
		"agents=%d" % Sim.agents.size())
	_ck("动作条默认隐藏", _main._act_pan != null and not _main._act_pan.visible
		and _main._act_btns.size() == _main.PLAYER_VERBS.size(),
		"btns=%d" % _main._act_btns.size())
	_ck("未开玩家模式时按钮是哑的", _main._player_do("greet") == "未开玩家模式")

	# ── 1) 设置面板那一行真的能开（手机上唯一的入口）──
	_ck("设置面板有玩家模式开关", _main._player_btn != null, str(_main._player_btn.text) if _main._player_btn != null else "null")
	_main._player_btn.pressed.emit()
	_ck("开关 → 玩家入镇", _main._player_mode and not Sim.get_agent("player").is_empty(),
		"agents=%d btn='%s'" % [Sim.agents.size(), _main._player_btn.text])
	_ck("开关 → 动作条现身", _main._act_pan.visible and _main._act_btns[0].visible)

	# ── 2) A/B/C 三层：逐动词 ──
	var digests := {}
	for i in _main.PLAYER_VERBS.size():
		var v: Dictionary = _main.PLAYER_VERBS[i]
		var verb := String(v["verb"])
		var tgt := _target_for(verb)

		# A) 字符串：_player_do(verb) vs 引擎原语
		_fixture()
		_main._player_mode = true
		_main._selected_id = tgt
		var msg_ui: String = _main._player_do(verb)
		_fixture()
		var msg_engine: String = Sim.player_mediate(tgt) if verb == "mediate" else Sim.player_act(verb, tgt)
		_ck("A·%-9s 串相同" % verb, msg_ui == msg_engine, "ui='%s' engine='%s'" % [msg_ui, msg_engine])

		# B) 接线：按钮发一次 ≡ 直接调 _player_do(verb)
		_fixture()
		_main._player_mode = true
		_main._selected_id = tgt
		_main._act_btns[i].pressed.emit()
		for _t in 12:
			Sim.tick()
		var s_btn := _state()
		_fixture()
		_main._player_mode = true
		_main._selected_id = tgt
		_main._player_do(verb)
		for _t2 in 12:
			Sim.tick()
		var s_fn := _state()
		_ck("B·%-9s 按钮≡函数" % verb, s_btn == s_fn, "btn=%s fn=%s" % [s_btn, s_fn])
		digests[verb] = s_btn

		# B') 物理键侧：_unhandled_input 的 7 个 keycode 也从 PLAYER_VERBS 查表分发，
		#     所以"按钮 ≡ 按键"只剩这一条要验：keycode → 同一个动词。
		var kc := OS.find_keycode_from_string(String(v["key"]))
		_ck("B'·%-8s 键位映射" % verb, kc != 0 and _main.verb_for_key(kc) == verb,
			"key '%s'(kc=%d) → '%s'" % [String(v["key"]), kc, _main.verb_for_key(kc)])

	# C) 校准点：7 个动词必须彼此可分（否则 A/B 是在比较"什么都没发生"）
	var uniq := {}
	for k in digests:
		uniq[String(digests[k])] = true
	_ck("C·7 动词可分辨", uniq.size() >= 5, "%d 种不同结局 / 7 个动词：%s" % [uniq.size(), str(digests)])

	# ── 2.5) 设置面板版式：内容必须真的装得下暗底板 ──
	# 加「玩家模式」这一行之前，面板是 9 个子项 / separation 16 / 底板 424px —— 算出来内容就超了，
	# 「关闭 Close」钮实际挂在暗底板【外面】。用 get_combined_minimum_size() 量，不用眼估。
	var vb: Control = _main._settings_panel.get_child(0)
	# ⚠️ 直接读 get_combined_minimum_size() 会被 vb 自己的 custom_minimum_size 顶住（量到的是我设的地板，
	#    不是真实内容高）—— 第一版就这么量出个自证的 480。先把地板临时归零再量。
	var cms: Vector2 = vb.custom_minimum_size
	vb.custom_minimum_size = Vector2(cms.x, 0)
	var need: float = vb.get_combined_minimum_size().y
	vb.custom_minimum_size = cms
	var used: float = vb.position.y + need + 20.0        # 上边距 + 内容 + 下边距
	# 老版式反推：去掉「玩家模式」那一行（按钮 min-height 40 + 1 个 separation 12），再把 separation 12 换回 16（8 段）
	var old_need: float = need - 52.0 + 8.0 * 4.0
	print("  ·  (诊断) 设置面板真实内容 %.0fpx / 底板 %.0fpx；换回改动前的 9 项+separation16 = %.0fpx，"
		% [need, _main._settings_panel.size.y, old_need]
		+ "而老底板 424px 里 vb 从 y=20 起只有 404px 可用 → 老版式%s"
		% ("确实装不下（关闭钮挂在底板外）" if old_need > 404.0 else "其实装得下"))
	_ck("设置面板装得下内容", used <= _main._settings_panel.size.y,
		"需要 %.0fpx，底板 %.0fpx" % [used, _main._settings_panel.size.y])

	# ── 3) 关回去：玩家退镇（同种子重开）──
	_main._player_btn.pressed.emit()
	_ck("关 → 玩家退镇 + 动作条收起",
		not _main._player_mode and Sim.get_agent("player").is_empty() and not _main._act_pan.visible,
		"agents=%d" % Sim.agents.size())

	_restore_settings()
	print("=== 触屏动作条: %s (%d fail) ===" % [("PASS ✅" if _fails == 0 else "FAIL ❌"), _fails])
	get_tree().quit(0 if _fails == 0 else 1)
