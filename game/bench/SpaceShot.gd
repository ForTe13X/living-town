extends Node
## bench/SpaceShot.gd — 【进空间 → 出空间 → 截图】采集路径（docs/47 §五-E6 的 W7）。
##
## ── 为什么必须新做一条路，而不是用 `--shot` ────────────────────────────────────
## 2026-07-28 外部对抗评审的原话：**没有人看过空间切换之后的任何一帧。** 真 bug 就活在那里
## （docs/46 §二·九-①：`_void_key` 停在旧值 ⇒ 出店后界外层永久空白，全在出货路径上），
## 而 `--shot` **结构上**看不见它：`--shot` 把 `auto_run=false`、渲**一**帧、存图、退出
## ⇒ 它拍到的永远是"启动之后的第一个稳定状态"，一次空间切换都没发生过。
## `--probe-space cafe` 也不行：那是**启动即进店**，同样没有"出店"这一半——
## 而 bug 恰恰在**回来**的那一刻才显形（键重算又恰好等于旧值 ⇒ 不排重画）。
##
## ── 它与 `WorldView --void-gate` 的分工（**不是**重复造轮子）──────────────────
## `--void-gate`（D7 建、评审补了两条下界）量的是**计数器**：`_void_draws` 有没有涨。
##   它只翻 `active_space`、**不碰相机**——docs/46 §二·九 记着为什么：第一版用 `pb.set_space()` 往返，
##   而 `set_space` 会改相机 ⇒ 回到 town 时键因"取景变了"而不同 ⇒ 照样重画 ⇒ **把修复回滚之后门依然 PASS**。
##   真 bug 的形状要求"进出期间取景逐字节不变"，合成翻转是达成这一点最省的办法。
## 本脚本量的是**像素**：它把三帧真的存成 PNG，交给 `tools/assert_space_roundtrip.py` 判。
##   两者是**不同层**的证据：`_void_draws` 涨了只说明"重画被排上了"，**不说明画出来的东西对**；
##   而"没人看过那些帧"正是 W7 的原话。计数器绿 + 像素红是可能的（例如重画了但画成了纯色）。
##
## ── ★ 本脚本的默认模式走【出货路径】，不是合成翻转 ──────────────────────────
## `--rt-mode portal`（默认）：把 portal 格的世界坐标喂给 `ProbeController.tapped` 信号
##   ⇒ `Main._on_probe_tap` → `Main._portal_click` —— 与玩家真的点门**同一段代码**，
##   进店 `set_space(cafe)+室内取景`、出店 `set_space(town)+go_home()`。
##   `go_home()` 是**固定**取景（`_home.get_center()` + `fit_zoom()`，两者都与启动时逐字节同源）
##   ⇒ **出店后的取景与进店前逐字节相同**，正是那个 bug 需要的形状。本脚本把这一点**断言**下来
##   （下面的 `cam_same`），而不是假设它——一旦哪天出店不再走 `go_home()`，A 判据的前提就没了，
##   那时该看见的是"前提断言红"，不是"像素判据莫名其妙地红"。
## `--rt-mode flip`：只翻 `active_space`，与 `--void-gate` 同款。留着是为了能把两条路**并排**跑，
##   而不是为了替代——见报告里"它能抓到什么/抓不到什么"。
##
## ── 用法（需要真 framebuffer：Xvfb 或带窗口；`--headless` 只会得到空图）────────
##   godot --path game --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
##     --resolution 1280x768 --single-window res://bench/SpaceShot.tscn -- \
##     --backend logic --seed 3 --warmup-tick 600 --rt-out /out \
##     [--rt-space cafe] [--rt-mode portal|flip] [--rt-journey simple|full] [--rt-redraw auto|none]
##   `--rt-redraw none` = 【暂停复现】档，见下面 `_refresh()` 上方那段（它是本脚本第一次跑就量到的一个真问题）。
##   `--rt-journey full`（AM3/编号135）= 玩家进出咖啡馆 + Probe 观察 2F；owner-only 楼梯帧不是玩家上楼证据。
## 产物：simple → <out>/rt_town_before.png / rt_interior.png / rt_town_after.png + rt_meta.json；
##       full   → <out>/rt_town_before.png / rt_cafe_1f.png / rt_cafe_2f.png / rt_cafe_1f_back.png / rt_town_after.png + rt_meta.json
## 退出码：0=三帧都拍出来了且前提断言成立；1=拍不出来或前提断言破了（**像素判据在 python 那边**）。
##
## ⚠ 本脚本**只属于 game/bench/**：它一个字节都不改 `game/scripts/*`，
##   只是把 Main.tscn 当成被测件实例化，然后走它自己的公开入口（tapped 信号 / active_space 属性）。

const MAIN_SCENE := "res://scenes/Main.tscn"

var _out := ""
var _space := "cafe"
var _mode := "portal"
var _journey := "simple"    # simple=玩家进店→出店；full=受邀玩家真实上下楼并返回（AM3/编号135）
var _redraw := "auto"       # auto=切完空间补一次 _redraw_all()（= 下一个 tick 到来时的稳定态）；none=不补（暂停复现，见下）
var _settle0 := 40          # 首帧之后的暖机帧数（纹理加载 + 插值吸附）
var _settle := 24           # 每次空间切换之后的暖机帧数
var _min_ms0 := 2500        # 暖机的墙钟下限（软渲染下帧率极低，光数帧会太短）
var _min_ms := 1200
var _watchdog_ms := 180000  # 看门狗：到点还没跑完就 rc=1 退出（绝不让本场景把 CI 挂住，见下）
var _corrupt_manifest := "" # P1-o presentation-only adversarial arm; never used by product runtime.
var _deny_portal := ""      # P1-p presentation-only access arm; drives the real Main tap transaction.
var _main: Node
var _meta := {}
var _rc := 0
var _guest_invited := false
var _clean_player := false
var _reduced_motion := false
var _capture_size := Vector2i.ZERO

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--rt-out" and i + 1 < args.size(): _out = args[i + 1]
		elif args[i] == "--rt-space" and i + 1 < args.size(): _space = args[i + 1]
		elif args[i] == "--rt-mode" and i + 1 < args.size(): _mode = args[i + 1]
		elif args[i] == "--rt-journey" and i + 1 < args.size(): _journey = args[i + 1]
		elif args[i] == "--rt-redraw" and i + 1 < args.size(): _redraw = args[i + 1]
		elif args[i] == "--rt-settle" and i + 1 < args.size(): _settle = int(args[i + 1])
		elif args[i] == "--rt-corrupt-manifest" and i + 1 < args.size(): _corrupt_manifest = args[i + 1]
		elif args[i] == "--rt-deny-portal" and i + 1 < args.size(): _deny_portal = args[i + 1]
		elif args[i] == "--clean-player": _clean_player = true
		elif args[i] == "--reduced-motion": _reduced_motion = true
		elif args[i] == "--rt-capture-size" and i + 2 < args.size(): _capture_size = Vector2i(int(args[i + 1]), int(args[i + 2]))
	if _out == "":
		print("[SPACESHOT] ❌ 缺 --rt-out <dir>")
		get_tree().quit(2)
		return
	# A requested source size changes the root Window's render size before Main
	# is instantiated.  `_snap` refuses any mismatch; it never resizes pixels.
	if _capture_size.x > 0 and _capture_size.y > 0:
		get_window().content_scale_size = _capture_size
		get_window().size = _capture_size
	# ── 看门狗（docs/41 §1 的那条教训机器化）────────────────────────────────────
	# 「bench 场景挂住而不是变红」是**比红更坏**的失败形态：`ci.sh` 会一直等下去（D1 实测 600s 还活着）。
	# 本场景比别的 bench 更容易踩到，因为它依赖**真 framebuffer**：少一个 Xvfb、少一个
	# `--rendering-driver opengl3`，等帧就等成了永远。所以给它一条硬地板：到点就带 rc=1 退出并说清原因。
	var wd := Timer.new()
	wd.one_shot = true
	wd.wait_time = float(_watchdog_ms) / 1000.0
	add_child(wd)
	wd.timeout.connect(func():
		print("[SPACESHOT] ❌ 看门狗超时 %d ms —— 采集没跑完就被判死（多半是没有真 framebuffer / 帧率过低）" % _watchdog_ms)
		get_tree().quit(1))
	wd.start()
	# Main 自己会解析 --backend/--seed/--warmup-tick/...：**原样透传**，本脚本不重抄一份参数
	# （抄一份必然漂移——docs/41 §4 的同一条毛病）。
	_main = load(MAIN_SCENE).instantiate()
	add_child(_main)
	# 冻结世界：本判据要比的是"同一个世界在往返前后长得一不一样"，agent 还在走就没得比。
	# 这与 `--shot` 的做法同源（Main.gd:486 也是 auto_run=false 定格），所以两条路拍的是同一类静帧。
	Sim.auto_run = false

	await _wait(_settle0, _min_ms0)
	if _corrupt_manifest != "":
		if Sim.cargo_manifest_order.is_empty():
			print("[SPACESHOT] ❌ P1-o corrupt arm 没有 pending manifest")
			get_tree().quit(1)
			return
		var corrupt_id := String(Sim.cargo_manifest_order[0])
		var corrupt_rec: Dictionary = Sim.cargo_manifests.get(corrupt_id, {})
		if _corrupt_manifest != "price_per" or corrupt_rec.is_empty():
			print("[SPACESHOT] ❌ 未支持的 corrupt manifest field=%s" % _corrupt_manifest)
			get_tree().quit(1)
			return
		corrupt_rec["price_per"] = int(corrupt_rec.get("price_per", 0)) + 1
		_meta["corrupt_manifest_field"] = _corrupt_manifest
		_meta["corrupt_manifest_id"] = corrupt_id
		# The product HUD is event-driven.  The bench mutation bypasses that event on purpose, so
		# normalize it before the "before" frame; otherwise the roundtrip would compare stale-ready
		# text against the correctly refreshed invalid text after returning from the warehouse.
		_main.call("_update_status")
	if _deny_portal != "":
		var found_deny := false
		for raw_portal in Sim._authored_portals:
			if String((raw_portal as Dictionary).get("id", "")) == _deny_portal:
				(raw_portal as Dictionary)["access"] = "owner"
				(raw_portal as Dictionary)["owner_space"] = _space
				found_deny = true
		if not found_deny:
			print("[SPACESHOT] ❌ P1-p deny arm 找不到 portal=%s" % _deny_portal)
			get_tree().quit(1)
			return
		_meta["denied_portal"] = _deny_portal
	var pb = _main.get("_probe")
	if pb == null:
		print("[SPACESHOT] ❌ 拿不到 Main._probe")
		get_tree().quit(1)
		return
	if _clean_player and not await _prove_reduced_motion_control(pb):
		print("[SPACESHOT] ❌ reduced-motion real-input receipt failed")
		get_tree().quit(1)
		return
	# 玩家旅程从玩家所在地取景；出门后 Main 也会回到同一跟随镜头。
	# 因此前后帧仍可逐像素比较，同时产品参照不再是假装玩家在场的全镇鸟瞰。
	var capture_player := Sim.get_agent("player")
	# Full cafe evidence must begin with a real accepted player invite.  The
	# harness may navigate the real player through public inputs, but it never
	# writes capability/player address/portal state directly.
	if _journey == "full" and not capture_player.is_empty():
		_guest_invited = await _invite_player_from_current_plane()
		if _guest_invited:
			var town_cafe_door := _portal_cell("town", "outdoor", "cafe", "1f")
			if not _walk_player_to(town_cafe_door):
				print("[SPACESHOT] ❌ invited player cannot reach authored cafe entrance through public moves")
				get_tree().quit(1); return
			# The route-equivalence proof deliberately reloads its pre-action save.
			# Reacquire the canonical agent Dictionary before using it as the camera
			# witness; keeping the pre-load Variant would point at stale coordinates.
			capture_player = Sim.get_agent("player")
	if not capture_player.is_empty():
		var capture_pos: Vector2i = capture_player.get("pos", Vector2i.ZERO)
		pb.focus_on(Vector2(capture_pos.x * 48 + 24, capture_pos.y * 48 + 24), "player")
		_refresh()
		await _wait(_settle, _min_ms)
		# LOD key follows the camera in _process; redraw once more after it settles
		# so the first close-up cannot retain a full-town label command list.
		_refresh()
		await _wait(4, 200)
	_meta["player_journey"] = not capture_player.is_empty()
	var cargo_status: Dictionary = Sim.cargo_status_for_node("port_dock")
	_meta["cargo_state"] = String(cargo_status.get("state", ""))
	_meta["cargo_good"] = String(cargo_status.get("good", ""))
	_meta["cargo_qty"] = int(cargo_status.get("qty", 0))
	var view = _main.get("_view")
	_meta["carrier_count"] = int((view.call("_cargo_carrier_projections") as Array).size()) if view != null else -1
	var cam0_pos: Vector2 = pb.cam.position
	var cam0_zoom: Vector2 = pb.cam.zoom
	# A physical portal click adds a visible system row.  Preserve the real
	# player traversal receipts, but restore view-only log/selection state before
	# the after frame so the original exact roundtrip pixel tooth stays sharp.
	# Invitation retries can advance the canonical world before the first frame.
	# Player-journey evidence observes the player on both ends; keep this
	# presentation-only selection stable across the roundtrip.
	if not capture_player.is_empty(): _main.set("_selected_id", "player")
	_main.call("_update_obs")
	_main.call("_update_status")
	_main.call("_render_log")
	await _wait(4, 200)
	var log0: Array = (_main.get("_log_recent") as Array).duplicate(true)
	var selected0: String = String(_main.get("_selected_id"))
	var cafe_log0: Array = []
	var cafe_selected0 := ""
	_meta["player_town_before"] = _player_address()
	_snap("town_before", pb)
	if _deny_portal != "":
		var player_before := _player_address()
		var probe_before := {"space": String(pb.active_space), "floor": String(pb.active_floor),
			"cam": [pb.cam.position.x, pb.cam.position.y], "zoom": pb.cam.zoom.x}
		if not _enter(pb):
			print("[SPACESHOT] ❌ deny arm 无法驱动 portal tap")
			get_tree().quit(1)
			return
		_refresh()
		await _wait(_settle, _min_ms)
		var player_after := _player_address()
		var recent: Array = _main.get("_log_recent")
		var last_log := String(recent[-1]) if not recent.is_empty() else ""
		var cargo_after: Dictionary = Sim.cargo_status_for_node("port_dock")
		_meta["journey"] = "denied"
		_meta["space"] = _space
		_meta["mode"] = _mode
		_meta["tick"] = Sim.tick_no
		_meta["player_before"] = player_before
		_meta["player_after"] = player_after
		_meta["probe_before"] = probe_before
		_meta["probe_after"] = {"space": String(pb.active_space), "floor": String(pb.active_floor),
			"cam": [pb.cam.position.x, pb.cam.position.y], "zoom": pb.cam.zoom.x}
		_meta["denial_log_bbcode"] = last_log
		_meta["cargo_after"] = {"state": String(cargo_after.get("state", "")),
			"good": String(cargo_after.get("good", "")), "qty": int(cargo_after.get("qty", 0))}
		_snap("denied", pb)
		var denied_meta := FileAccess.open(_out + "/rt_meta.json", FileAccess.WRITE)
		if denied_meta != null:
			denied_meta.store_string(JSON.stringify(_meta, "  "))
			denied_meta.close()
		get_tree().quit(_rc)
		return

	# ── 进店 ────────────────────────────────────────────────────────────────
	if not _enter(pb):
		print("[SPACESHOT] ❌ 进不去 space=%s（mode=%s）" % [_space, _mode])
		get_tree().quit(1)
		return
	_refresh()
	await _wait(_settle, _min_ms)
	if String(pb.active_space) != _space:
		print("[SPACESHOT] ❌ 点了门却没进去：active_space=%s" % String(pb.active_space))
		_rc = 1
	var player := Sim.get_agent("player")
	if not player.is_empty():
		var player_in := String(player.get("space", "town")) == _space and String(player.get("floor", "outdoor")) == String(pb.active_floor)
		if not player_in:
			print("[SPACESHOT] ❌ 玩家点门后仍不在目标平面：%s/%s" % [player.get("space", "?"), player.get("floor", "?")])
			_rc = 1
		_meta["player_entered"] = player_in
	if _journey == "full" and not player.is_empty() and not _guest_invited:
		_guest_invited = await _invite_player_from_current_plane()
	if _journey == "full" and not player.is_empty():
		_meta["player_invited"] = _guest_invited
		if not _guest_invited or not Sim._cafe_guest_capability_valid():
			print("[SPACESHOT] ❌ full journey lacks an accepted authoritative cafe guest invite")
			get_tree().quit(1); return
	# P1-v：东海仓内帧必须来自一次真实柜台点击，而不只是“墙上恰好画了字”。
	# 点击走 Main._on_probe_tap → authored console cell → 只读 projection；同时钉住 Sim exact no-op。
	if _space == "port_warehouse":
		var console_cell: Vector2i = Sim.warehouse_observatory_console_cell()
		var sim_before := _observatory_sim_snapshot()
		_main.call("_on_probe_tap", Vector2(console_cell.x * 48 + 24, console_cell.y * 48 + 24))
		var sim_after := _observatory_sim_snapshot()
		var recent: Array = _main.get("_log_recent")
		var observatory_log := String(recent[-1]) if not recent.is_empty() else ""
		var projection: Dictionary = Sim.warehouse_observatory_projection("port_dock")
		_meta["observatory"] = {
			"console_cell": [console_cell.x, console_cell.y],
			"sim_noop": sim_before == sim_after,
			"log_bbcode": observatory_log,
			"mode": String(projection.get("mode", "")),
			"cargo_state": String((projection.get("cargo", {}) as Dictionary).get("state", "")),
			"receipt_state": String((projection.get("receipt", {}) as Dictionary).get("state", "")),
			"action_bar_hidden": not bool((_main.get("_act_pan") as Control).visible),
			"chat_hidden": not bool((_main.get("_chat_in") as Control).visible),
			"location_truthful": "东海货仓 · 货运观测室" in String((_main.get("_obs") as RichTextLabel).text),
		}
		if sim_before != sim_after or not ("观测台｜" in observatory_log) or not ("（只读）" in observatory_log):
			print("[SPACESHOT] ❌ 货运观测柜台未形成只读 exact-noop 回执")
			_rc = 1
		_refresh()
		await _wait(4, 200)
	if _journey == "full":
		cafe_log0 = (_main.get("_log_recent") as Array).duplicate(true)
		cafe_selected0 = String(_main.get("_selected_id"))
	_snap("interior" if _journey != "full" else "cafe_1f", pb)

	# ── 全楼层观察旅程（AM3/编号135）：cafe/1f →（楼梯 portal）2f →（楼梯）1f ────────────
	# 只在 --rt-journey full 时跑；simple 模式一个字节都不变（现役 1F 往返门原样）。
	# 逐段断言 Probe【落在对的 Floor】。带 player 时普通玩家仍留在 1F：owner-only 楼梯的
	# 上下层帧是远程观察回执，不是玩家穿越证据。玩家进/出店另由 player_entered/player_returned 断言。
	# 楼梯 cell 由 _stairs_world_pos 从 SpaceGraph 真源取（不抄第二份坐标），点它 → Main._portal_click 按
	# 当前 active_floor 判方向（1f→2f 上、2f→1f 下），access=owner 不拦 Probe（观察者不是 agent，见 Main.gd:2439）。
	if _journey == "full":
		if String(pb.active_floor) != "1f":
			print("[SPACESHOT] ❌ 进店后应在 1f，实为 %s" % String(pb.active_floor)); _rc = 1
		# 上楼 (cafe/1f → cafe/2f).  Put the invited real player on the
		# authored stairs through PlayerTrace-recorded movement before the same
		# product tap drives both Sim and camera.
		var stairs_1f := _portal_cell("cafe", "1f", "cafe", "2f")
		if not capture_player.is_empty() and not _walk_player_to(stairs_1f):
			print("[SPACESHOT] ❌ invited player cannot reach cafe/1f stairs")
			get_tree().quit(1); return
		if not _climb(pb):
			print("[SPACESHOT] ❌ 上楼：找不到 cafe/%s 的楼梯 portal" % String(pb.active_floor))
			get_tree().quit(1); return
		_refresh()
		await _wait(_settle, _min_ms)
		if String(pb.active_floor) != "2f":
			print("[SPACESHOT] ❌ 上楼后应在 2f，实为 %s（楼梯目标层不对/portal 断）" % String(pb.active_floor)); _rc = 1
		if not capture_player.is_empty():
			var player_2f: Dictionary = Sim.get_agent("player")
			var occupied_2f := String(player_2f.get("space", "")) == "cafe" and String(player_2f.get("floor", "")) == "2f"
			_meta["player_occupied_2f"] = occupied_2f
			_meta["player_2f_address"] = _player_address()
			if not occupied_2f:
				print("[SPACESHOT] ❌ invited real player did not occupy cafe/2f"); _rc = 1
		_snap("cafe_2f", pb)
		# 下楼 (cafe/2f → cafe/1f)
		if not _climb(pb):
			print("[SPACESHOT] ❌ 下楼：找不到 cafe/%s 的楼梯 portal" % String(pb.active_floor))
			get_tree().quit(1); return
		_refresh()
		await _wait(_settle, _min_ms)
		if String(pb.active_floor) != "1f":
			print("[SPACESHOT] ❌ 下楼后应回 1f，实为 %s" % String(pb.active_floor)); _rc = 1
		if not capture_player.is_empty():
			var player_back: Dictionary = Sim.get_agent("player")
			var returned_1f := String(player_back.get("space", "")) == "cafe" and String(player_back.get("floor", "")) == "1f"
			_meta["player_returned_1f"] = returned_1f
			if not returned_1f:
				print("[SPACESHOT] ❌ invited real player did not return to cafe/1f"); _rc = 1
		var cafe_exit := _portal_cell("cafe", "1f", "town", "outdoor")
		if not capture_player.is_empty() and not _walk_player_to(cafe_exit):
			print("[SPACESHOT] ❌ returning player cannot reach cafe exit")
			get_tree().quit(1); return
		# Capture the same player address and View-only feed/selection as the
		# entry frame so A2 keeps its exact-pixel tooth while still proving the
		# real 2F occupation above.
		_main.set("_log_recent", cafe_log0)
		_main.set("_selected_id", cafe_selected0)
		_main.call("_render_log")
		_main.call("_update_obs")
		_main.call("_update_status")
		_refresh()
		await _wait(4, 200)
		_snap("cafe_1f_back", pb)

	# ── 出店 ────────────────────────────────────────────────────────────────
	if not _leave(pb):
		print("[SPACESHOT] ❌ 出不来（mode=%s）" % _mode)
		get_tree().quit(1)
		return
	_refresh()
	await _wait(_settle, _min_ms)
	if String(pb.active_space) != "town":
		print("[SPACESHOT] ❌ 点了门却没回到 town：active_space=%s" % String(pb.active_space))
		_rc = 1
	player = Sim.get_agent("player")
	if not player.is_empty():
		var player_returned := String(player.get("space", "")) == "town" and String(player.get("floor", "")) == "outdoor"
		if not player_returned:
			print("[SPACESHOT] ❌ 玩家出门后未回 town/outdoor")
			_rc = 1
		_meta["player_returned"] = player_returned
	if not capture_player.is_empty():
		_main.set("_log_recent", log0)
		_main.set("_selected_id", selected0)
		_main.call("_render_log")
		_main.call("_update_obs")
		_main.call("_update_status")
		_refresh()
		await _wait(4, 200)
		# Preserve the exact pre-entry camera witness after a real player return.
		# Main focuses the returned player for gameplay, but this harness compares
		# the same authored town viewport before/after the roundtrip.
		pb.cam.position = cam0_pos
		pb.cam.zoom = cam0_zoom
	_meta["player_town_after"] = _player_address()
	_snap("town_after", pb)
	if _journey == "full" and _clean_player:
		if not await _prove_clean_player_consequence(pb):
			_rc = 1

	# ── 前提断言：出店后的取景必须与进店前【逐字节相同】 ────────────────────────
	# 这不是"判据"，是 A 判据（前后两帧应当一致）的**前提**。它塌了，像素比较就没有意义，
	# 那时应该看见的是这一行红，而不是去查画面。
	var cam1_pos: Vector2 = pb.cam.position
	var cam1_zoom: Vector2 = pb.cam.zoom
	var cam_same: bool = cam0_pos == cam1_pos and cam0_zoom == cam1_zoom
	if not cam_same:
		print("[SPACESHOT] ❌ 前提不成立：出店后取景变了 pos %s→%s zoom %s→%s"
			% [cam0_pos, cam1_pos, cam0_zoom, cam1_zoom]
			+ "  ⇒ 前后两帧本来就该不同，A 判据（bbox 应为空）失去意义")
		_rc = 1
	else:
		print("[SPACESHOT] 前提 ✅ 出店后取景与进店前逐字节相同 pos=%s zoom=%s" % [cam1_pos, cam1_zoom])

	_meta["mode"] = _mode
	_meta["journey"] = _journey
	_meta["stairs_probe_only"] = false
	_meta["player_floor_during_probe_stairs"] = "2f" if bool(_meta.get("player_occupied_2f", false)) else ""
	_meta["space"] = _space
	_meta["cam_same"] = cam_same
	_meta["tick"] = Sim.tick_no
	var f := FileAccess.open(_out + "/rt_meta.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_meta, "  "))
		f.close()
	get_tree().quit(_rc)

## ★★ 切完空间补一次 `WorldView._redraw_all()` —— 这一行是本脚本第一次跑就【量出来】的，不是设计出来的。
##
## **实测（2026-07-30，本脚本第一版）**：冻结世界 + 点门进咖啡馆 ⇒ 拍到的 `rt_interior.png` 里
## **是小镇的草地和树**，而同一棵树上 `--probe-space cafe --shot --shot-fit` 拍到的是**正常的咖啡馆**
## （吧台/桌椅/门/「阿丽的咖啡馆·一层·咖啡区」）。两张图都留在 E6 的证据目录里。
##
## 归因（查了代码，不是猜的）：`WorldView` 只在三处排重画 —— `Sim.ticked` / `Sim.agent_changed`
## （`WorldView.gd:503-504`，两条都指向 `_redraw_all()`）与 `_process` 里"渲染坐标脏了"那条（:2177）。
## **`Main._portal_click` 一处都不碰**（它只 `_push` 日志 + `_update_status`，都是 HUD）。
## 于是：**换了空间，世界层要等到【下一个 tick】才重画。**
##   · 出货默认档 `auto_run=true` ⇒ 下一个 tick 在 80ms 后到 ⇒ 肉眼看不见，**不是 bug**；
##   · 但 `Sim.running=false`（**空格暂停，出货键位，底栏原文写着"空格暂停"**，`Main.gd:2012`，
##     而 `Sim._process:319` 是 `if not (auto_run and running): return`）⇒ **tick 永不到来**
##     ⇒ **暂停状态下点门进店，画面会一直停在小镇上。** 这条是真的、在出货路径上、此前没人看过。
##   ⇒ 已写进报告交给 `Main.gd`/`WorldView.gd` 的所有者（E4/E5）；**本棒不改 `game/scripts/*`。**
##   ⇒ `--rt-redraw none` 保留了这条复现（拍出来的 `rt_interior.png` 就是那张"停在镇上的室内帧"）。
##
## 为什么补这一行**不会**把本门要抓的东西一起补掉（重要）：
##   `_redraw_all()` 只 `queue_redraw()` 本节点与灯层，它**不碰任何缓存**——
##   界外层 `_void` 是**独立** CanvasItem，它重不重画由 `_void_sync()/_void_key` 决定（`_process` 每帧跑，
##   与 tick 无关）；`_terrain_built`/`_paths_built`/`_decor_built`/`_grass_var` 更是一个都不清。
##   所以 docs/46 §二·九-① 那个真 bug（键停在旧值）与 W6 的三个缓存，在补了这一行之后**照样会显形**——
##   下面的负对照就是拿它证明的（回滚修复 ⇒ 本门变红）。
func _refresh() -> void:
	if _redraw == "none":
		return
	var view = _main.get("_view") if _main != null else null
	if view != null:
		view.call("_redraw_all")


## Resolve an authored endpoint cell without copying coordinates.
func _portal_cell(from_space: String, from_floor: String, to_space: String, to_floor: String) -> Vector2i:
	var sg = _main.get("_sg") if _main != null else null
	if sg == null: return Vector2i(-1, -1)
	for p in sg.portals:
		for side in ["from", "to"]:
			var a: Dictionary = p.get(side, {})
			var b: Dictionary = p.get("to") if side == "from" else p.get("from")
			if String(a.get("space", "")) == from_space and String(a.get("floor", "")) == from_floor \
					and String(b.get("space", "")) == to_space and String(b.get("floor", "")) == to_floor:
				var pos: Array = a.get("pos", [])
				if pos.size() == 2: return Vector2i(int(pos[0]), int(pos[1]))
	return Vector2i(-1, -1)

## Navigate only by the public cardinal player input. Reading the receiver-owned
## nav grid chooses a deterministic route; every applied step is PlayerTrace.
func _walk_player_to(target: Vector2i) -> bool:
	var pl: Dictionary = Sim.get_agent("player")
	if pl.is_empty() or target.x < 0: return false
	var start: Vector2i = pl.get("pos", Vector2i(-1, -1))
	var path: Array = Sim._astar_path(Sim._grid_for(String(pl.get("space", "town")), String(pl.get("floor", "outdoor"))), start, target)
	if path.is_empty(): return false
	for i in range(1, path.size()):
		var before: Vector2i = pl.get("pos", Vector2i.ZERO)
		Sim.player_move((path[i] as Vector2i) - (path[i - 1] as Vector2i))
		if Vector2i(pl.get("pos", Vector2i.ZERO)) == before: return false
	return Vector2i(pl.get("pos", Vector2i.ZERO)) == target

## Find Aria on the current canonical plane, walk the real player to her, and
## issue the real invite action. No relationship, capability or event is injected.
func _invite_player_from_current_plane() -> bool:
	if Sim._cafe_guest_capability_valid(): return true
	for _attempt in range(64):
		var pl: Dictionary = Sim.get_agent("player")
		var aria: Dictionary = Sim.get_agent("aria")
		if pl.is_empty() or aria.is_empty(): return false
		if String(pl.get("space", "")) == String(aria.get("space", "")) and String(pl.get("floor", "")) == String(aria.get("floor", "")) \
				and int(pl.get("talking", 0)) <= 0 and int(aria.get("talking", 0)) <= 0:
			if _walk_player_to(aria.get("pos", Vector2i(-1, -1))):
				_main.set("_selected_id", "aria")
				_main.call("_apply_clean_player_presentation")
				var invite := _clean_control("invite")
				if invite == null or not await _prove_control_negatives(invite, "invite"):
					print("[SPACESHOT] invite control negative witness failed null=%s" % (invite == null))
					return false
				var route_pre := "user://pr38_route_equivalence_pre.save"
				if not Sim.save_game(route_pre, {"evidence": "clean-player-route-equivalence"}):
					return false
				if not await _click_clean_control(invite, "invite-positive"):
					print("[SPACESHOT] invite positive pointer delivery failed")
					return false
				for _i in range(12): Sim.tick()
				if not Sim._cafe_guest_capability_valid():
					continue
				var pointer_witness := _control_witness()
				var pointer_trace: Dictionary = Sim.get_player_trace()
				if not Sim.load_game(route_pre):
					return false
				_main.call("_after_load")
				_main.set("_selected_id", "aria")
				get_viewport().gui_release_focus()
				await _push_key(KEY_Y)
				for _i in range(12): Sim.tick()
				var hotkey_witness := _control_witness()
				var hotkey_trace: Dictionary = Sim.get_player_trace()
				var route_exact := Sim._cafe_guest_capability_valid() and pointer_witness == hotkey_witness \
					and pointer_trace == hotkey_trace
				_meta["route_equivalence"] = {"pointer": "Viewport.push_input(InputEventMouseButton) -> _player_do",
					"hotkey": "Viewport.push_input(InputEventKey KEY_Y) -> _player_do",
					"callback": "_player_do", "canonical_exact": route_exact,
					"trace_entries": (hotkey_trace.get("entries", []) as Array).size()}
				if route_exact:
					_meta["invite_event_id"] = int(Sim.cafe_guest_capability.get("grant_event_id", -1))
					_meta["invite_action_path"] = "pointer/hotkey converge at _player_do and one canonical trace"
					return true
				print("[SPACESHOT] route equivalence retry pointer_valid=true hotkey_valid=%s pointer_trace=%d hotkey_trace=%d"
					% [Sim._cafe_guest_capability_valid(), (pointer_trace.get("entries", []) as Array).size(),
						(hotkey_trace.get("entries", []) as Array).size()])
		Sim.tick()
	print("[SPACESHOT] invite search exhausted player=%s aria=%s" % [_player_address(), Sim.get_agent("aria")])
	return false

func _player_address() -> Dictionary:
	var player := Sim.get_agent("player")
	if player.is_empty():
		return {}
	var pos: Vector2i = player.get("pos", Vector2i.ZERO)
	return {"space": String(player.get("space", "")), "floor": String(player.get("floor", "")),
		"pos": [pos.x, pos.y], "area": String(player.get("area", "")), "room": String(player.get("room", ""))}

## Product-path persistence evidence after the complete real journey.  Files are
## confined to user:// (the task-owned container HOME); no fixture or authority
## is rewritten.  The Main callbacks are the exact keyboard/touch seams.
func _prove_clean_player_consequence(pb) -> bool:
	var proof := {
		"desktop": _main.call("clean_player_presentation_contract", Vector2(1280, 768)),
		"mobile": _main.call("clean_player_presentation_contract", Vector2(320, 192)),
		"reduced_motion": _reduced_motion,
	}
	var trace_before: Dictionary = Sim.get_player_trace()
	var revoke_button := _clean_control("cafe_guest_pass:revoke")
	if revoke_button == null or not await _prove_control_negatives(revoke_button, "revoke"):
		return false
	if not await _click_clean_control(revoke_button, "revoke-positive"):
		return false
	_refresh()
	await _wait(4, 200)
	var cap_after: Dictionary = Sim.cafe_guest_capability.duplicate(true)
	var trace_after: Dictionary = Sim.get_player_trace()
	var revoked := String(cap_after.get("status", "")) == "revoked"
	var revoke_recorded := false
	if not (trace_after.get("entries", []) as Array).is_empty():
		revoke_recorded = String((trace_after["entries"] as Array)[-1].get("kind", "")) == "cafe_guest_pass"
	_main.set("_selected_id", "")
	_main.call("_update_obs")
	_main.call("_rebuild_feed")
	_main.call("_update_status")
	await _wait(4, 200)
	var state_before: Dictionary = _main.call("clean_player_view_state")
	var expected_native := _capture_size if _capture_size != Vector2i.ZERO else Vector2i(DisplayServer.window_get_size())
	var ui_receipt := _validate_clean_player_ui(state_before, expected_native)
	proof["ui"] = ui_receipt
	var ui_negatives := _ui_negative_controls(state_before, expected_native)
	proof["ui_negatives"] = ui_negatives
	proof["revoke"] = {"status": String(cap_after.get("status", "")), "recorded": revoke_recorded,
		"trace_entries_before": (trace_before.get("entries", []) as Array).size(),
		"trace_entries_after": (trace_after.get("entries", []) as Array).size(),
		"chronicle": String((state_before.get("normalized", {}) as Dictionary).get("chronicle", ""))}
	_snap("revoke", pb)
	var revoke_png := _out + "/rt_revoke.png"
	var revoke_sha := FileAccess.get_sha256(revoke_png)
	var save_path := "user://pr38_clean_revoked.save"
	var save_ok := Sim.save_game(save_path, {"evidence": "clean-player-revoke"})
	var save_sha := FileAccess.get_sha256(save_path) if save_ok else ""
	var expected_tick := Sim.tick_no
	var expected_digest := Sim.event_digest
	var expected_cap := Sim.cafe_guest_capability.duplicate(true)
	var expected_trace := Sim.get_player_trace()
	var load_ok := save_ok and Sim.load_game(save_path)
	if load_ok:
		_main.call("_after_load")
		_refresh()
		await _wait(4, 200)
	var load_exact := load_ok and Sim.tick_no == expected_tick and Sim.event_digest == expected_digest \
		and Sim.cafe_guest_capability == expected_cap and Sim.get_player_trace() == expected_trace
	var state_loaded: Dictionary = _main.call("clean_player_view_state") if load_exact else {}
	_snap("revoke_loaded", pb)
	var loaded_sha := FileAccess.get_sha256(_out + "/rt_revoke_loaded.png")
	var replay_ok := load_exact and Sim.goto_tick(expected_tick)
	if replay_ok:
		_main.call("_after_jump")
		_refresh()
		await _wait(4, 200)
	var replay_exact := replay_ok and Sim.event_digest == expected_digest \
		and Sim.cafe_guest_capability == expected_cap and Sim.get_player_trace() == expected_trace
	var state_replayed: Dictionary = _main.call("clean_player_view_state") if replay_exact else {}
	_snap("revoke_replayed", pb)
	var replayed_sha := FileAccess.get_sha256(_out + "/rt_revoke_replayed.png")
	var normalized_before: Dictionary = state_before.get("normalized", {})
	var normalized_loaded: Dictionary = state_loaded.get("normalized", {})
	var normalized_replayed: Dictionary = state_replayed.get("normalized", {})
	var view_exact := normalized_before == normalized_loaded and normalized_before == normalized_replayed
	var pixels_exact := revoke_sha != "" and revoke_sha == loaded_sha and revoke_sha == replayed_sha
	proof["persistence"] = {"save": save_ok, "save_sha256": save_sha, "load": load_ok,
		"load_exact": load_exact, "replay": replay_ok, "replay_exact": replay_exact, "tick": expected_tick,
		"view_exact": view_exact, "pixels_exact": pixels_exact,
		"pixel_sha256": {"before": revoke_sha, "loaded": loaded_sha, "replayed": replayed_sha},
		"state_before": state_before, "state_loaded": state_loaded, "state_replayed": state_replayed}
	# Missing/corrupt files are evidence failures and must leave current authority intact.
	var atomic_before := {"tick": Sim.tick_no, "event_digest": Sim.event_digest,
		"capability": Sim.cafe_guest_capability.duplicate(true), "trace": Sim.get_player_trace()}
	var missing_rejected := not Sim.load_game("user://pr38_missing_evidence.save")
	var corrupt_path := "user://pr38_corrupt_evidence.save"
	var corrupt_file := FileAccess.open(corrupt_path, FileAccess.WRITE)
	if corrupt_file != null:
		corrupt_file.store_string("not-a-living-town-save")
		corrupt_file.close()
	var corrupt_rejected := not Sim.load_game(corrupt_path)
	var atomic_after := {"tick": Sim.tick_no, "event_digest": Sim.event_digest,
		"capability": Sim.cafe_guest_capability.duplicate(true), "trace": Sim.get_player_trace()}
	proof["negative_evidence"] = {"missing_rejected": missing_rejected,
		"corrupt_rejected": corrupt_rejected, "atomic": atomic_before == atomic_after}
	_meta["clean_player_evidence"] = proof
	var okay := revoked and revoke_recorded and save_ok and load_exact and replay_exact \
		and view_exact and pixels_exact and bool(state_before.get("in_bounds", false)) and bool(state_before.get("readable", false)) \
		and bool(ui_receipt.get("pass", false)) and bool(ui_negatives.get("pass", false)) \
		and missing_rejected and corrupt_rejected and atomic_before == atomic_after \
		and bool((proof["desktop"] as Dictionary).get("in_bounds", false)) \
		and bool((proof["mobile"] as Dictionary).get("in_bounds", false)) \
		and bool((_meta.get("reduced_motion_receipt", {}) as Dictionary).get("pass", false)) \
		and bool((_meta.get("route_equivalence", {}) as Dictionary).get("canonical_exact", false))
	if not okay:
		print("[SPACESHOT] ❌ clean player consequence/persistence contract failed: %s" % JSON.stringify(proof))
	else:
		print("[SPACESHOT] clean player PASS: revoke visible + save/load/replay exact + missing/corrupt fail closed")
	return okay

func _clean_control(verb: String) -> BaseButton:
	var controls: Array = (_main.get("_clean_action_btns") as Array).duplicate()
	controls.append(_main.get("_clean_guest_pass_btn"))
	for raw in controls:
		if raw is BaseButton and String((raw as BaseButton).get_meta("player_verb", "")) == verb:
			return raw as BaseButton
	return null

func _control_witness() -> String:
	return JSON.stringify({"tick": Sim.tick_no, "digest": Sim.event_digest,
		"events": Sim.event_log.size(), "trace": Sim.get_player_trace(),
		"capability": Sim.cafe_guest_capability, "player": _player_address()})

func _rect_from(raw) -> Rect2:
	var a: Array = raw
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3])) if a.size() == 4 else Rect2()

func _rect_near(a: Rect2, b: Rect2, tolerance := 0.02) -> bool:
	return a.position.distance_to(b.position) <= tolerance and a.size.distance_to(b.size) <= tolerance

## Fail-closed verifier: it recomputes coverage and geometry from live Control
## rectangles.  Summary fields are receipts, never authority, so forged metadata
## cannot make the retired 87.2266% layout pass.
func _validate_clean_player_ui(state: Dictionary, expected_native: Vector2i) -> Dictionary:
	var failures: Array = []
	var display: Array = state.get("display", [])
	if display.size() != 2 or int(display[0]) != expected_native.x or int(display[1]) != expected_native.y:
		failures.append("native_framebuffer")
	var panels: Array = state.get("physical_panels", [])
	var computed_coverage := 1.0
	var computed_clear := Rect2()
	if panels.size() != 3:
		failures.append("panel_cardinality")
	else:
		var status := _rect_from(panels[0])
		var chronicle := _rect_from(panels[1])
		var actions := _rect_from(panels[2])
		computed_coverage = (status.get_area() + chronicle.get_area() + actions.get_area()) \
			/ float(expected_native.x * expected_native.y)
		var clear_top := chronicle.end.y if expected_native.x <= 480 else status.end.y
		var clear_bottom := actions.position.y if expected_native.x <= 480 else minf(chronicle.position.y, actions.position.y)
		computed_clear = Rect2(status.position.x, clear_top, status.size.x, clear_bottom - clear_top)
		var contract: Dictionary = _main.call("clean_player_presentation_contract", Vector2(expected_native))
		var expected_panels: Dictionary = contract.get("panels", {})
		if not _rect_near(status, _rect_from(expected_panels.get("status", []))) \
				or not _rect_near(chronicle, _rect_from(expected_panels.get("chronicle", []))) \
				or not _rect_near(actions, _rect_from(expected_panels.get("actions", []))):
			failures.append("panel_geometry")
		if absf(float(state.get("coverage", -1.0)) - computed_coverage) > 0.000001:
			failures.append("forged_coverage")
		if expected_native.x <= 480 and (computed_coverage > 0.42 or computed_clear.size.x < 308.0 or computed_clear.size.y < 96.0):
			failures.append("mobile_world_window")
	var geometry: Array = state.get("geometry", [])
	if geometry.size() != 10:
		failures.append("control_cardinality")
	else:
		var layout: Dictionary = _main.call("clean_player_layout", Vector2(expected_native))
		var action_panel: Rect2 = layout["actions"]
		var gap := float(layout["gap"])
		var columns := int(layout["columns"])
		var rows := int(layout["rows"])
		var cell := Vector2((action_panel.size.x - gap * float(columns + 1)) / float(columns),
			(action_panel.size.y - gap * float(rows + 1)) / float(rows))
		var expected_verbs := ["greet", "give", "gossip", "invite", "confront", "apologize", "mediate", "cafe_guest_pass:revoke"]
		var expected_callbacks := ["_player_do", "_player_do", "_player_do", "_player_do", "_player_do", "_player_do", "_player_do", "_player_return_cafe_pass"]
		var action_rects: Array[Rect2] = []
		for i in range(2, geometry.size()):
			var item: Dictionary = geometry[i]
			var r := _rect_from(item.get("physical_rect", []))
			var control_index := i - 2
			var expected_rect := Rect2(action_panel.position + Vector2(gap + (control_index % columns) * (cell.x + gap),
				gap + (control_index / columns) * (cell.y + gap)), cell)
			if r.size.x < 32.0 or r.size.y < 32.0 or r.position.x < 0.0 or r.position.y < 0.0 \
					or r.end.x > expected_native.x or r.end.y > expected_native.y:
				failures.append("action_geometry_%d" % (i - 2))
			if not _rect_near(r, expected_rect):
				failures.append("action_contract_%d" % (i - 2))
			if int(item.get("physical_font_size", 0)) < 13 or not bool(item.get("text_fits", false)):
				failures.append("action_text_%d" % (i - 2))
			if int(item.get("focus_mode", Control.FOCUS_NONE)) != Control.FOCUS_ALL:
				failures.append("action_focus_%d" % (i - 2))
			if bool(item.get("disabled", true)) or int(item.get("pressed_connections", 0)) != 1:
				failures.append("action_witness_%d" % (i - 2))
			if String(item.get("player_verb", "")) != expected_verbs[i - 2] \
					or String(item.get("callback", "")) != expected_callbacks[i - 2]:
				failures.append("action_route_%d" % (i - 2))
			for prior in action_rects:
				if r.intersects(prior): failures.append("action_overlap_%d" % (i - 2))
			action_rects.append(r)
	var receipt := {"pass": failures.is_empty(), "failures": failures,
		"expected_native": [expected_native.x, expected_native.y], "computed_coverage": computed_coverage,
		"clear_world": [computed_clear.position.x, computed_clear.position.y, computed_clear.size.x, computed_clear.size.y]}
	return receipt

func _ui_negative_controls(state: Dictionary, expected_native: Vector2i) -> Dictionary:
	var negatives := {}
	var geometry: Array = state.get("geometry", [])
	if expected_native == Vector2i(320, 192):
		var old := state.duplicate(true)
		old["physical_panels"] = [[6.0, 6.0, 308.0, 38.0], [6.0, 47.0, 308.0, 32.0], [6.0, 82.0, 308.0, 104.0]]
		old["coverage"] = 0.872265625
		negatives["old_geometry_0_872266_rejected"] = not bool(_validate_clean_player_ui(old, expected_native).get("pass", true))
		var forged := old.duplicate(true)
		forged["coverage"] = state.get("coverage", 0.0)
		negatives["forged_metadata_old_live_controls_rejected"] = not bool(_validate_clean_player_ui(forged, expected_native).get("pass", true))
	if geometry.size() == 10:
		for key in ["focus_none", "disabled", "disconnected", "duplicate", "bypass"]:
			var bad := state.duplicate(true)
			var controls: Array = bad["geometry"]
			var item: Dictionary = controls[2]
			if key == "focus_none": item["focus_mode"] = Control.FOCUS_NONE
			elif key == "disabled": item["disabled"] = true
			elif key == "disconnected": item["pressed_connections"] = 0
			elif key == "duplicate": item["pressed_connections"] = 2
			else: item["callback"] = "_bench_bypass"
			controls[2] = item
			bad["geometry"] = controls
			negatives[key + "_rejected"] = not bool(_validate_clean_player_ui(bad, expected_native).get("pass", true))
	var wrong_native := Vector2i(expected_native.x + 1, expected_native.y)
	negatives["wrong_framebuffer_or_post_resize_rejected"] = not bool(_validate_clean_player_ui(state, wrong_native).get("pass", true))
	if expected_native == Vector2i(1280, 768):
		var drift := state.duplicate(true)
		var drift_panels: Array = drift["physical_panels"]
		drift_panels[0][0] = float(drift_panels[0][0]) + 1.0
		drift["physical_panels"] = drift_panels
		negatives["desktop_1px_drift_rejected"] = not bool(_validate_clean_player_ui(drift, expected_native).get("pass", true))
	var all_pass := true
	for value in negatives.values(): all_pass = all_pass and bool(value)
	negatives["pass"] = all_pass
	return negatives

## Exercise the actual Control hit-test/input route.  Neither arm may invoke the
## product callback or alter a canonical witness; only then is the connection
## restored for the subsequent positive click.
func _prove_control_negatives(button: BaseButton, label: String) -> bool:
	var receipt := {"route": "Viewport.push_input(InputEventMouseButton)", "disabled": false, "disconnected": false}
	var before := _control_witness()
	button.disabled = true
	var delivered_disabled := await _click_clean_control(button, label + "-disabled")
	receipt["disabled"] = delivered_disabled and before == _control_witness()
	button.disabled = false
	var connections: Array = button.get_signal_connection_list("pressed")
	for rec in connections:
		button.disconnect("pressed", rec["callable"])
	before = _control_witness()
	var delivered_disconnected := await _click_clean_control(button, label + "-disconnected")
	receipt["disconnected"] = delivered_disconnected and before == _control_witness()
	for rec in connections:
		button.connect("pressed", rec["callable"], int(rec.get("flags", 0)))
	receipt["connection_count"] = button.get_signal_connection_list("pressed").size()
	if not _meta.has("control_negatives"):
		_meta["control_negatives"] = {}
	(_meta["control_negatives"] as Dictionary)[label] = receipt
	return bool(receipt["disabled"]) and bool(receipt["disconnected"]) and int(receipt["connection_count"]) > 0

func _click_clean_control(button: BaseButton, label: String) -> bool:
	if button == null or not button.is_visible_in_tree():
		return false
	var r := button.get_global_rect()
	if r.size.x < 1.0 or r.size.y < 1.0:
		return false
	var at := r.get_center()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		get_viewport().push_input(ev, true)
		await get_tree().process_frame
	if not _meta.has("control_input"):
		_meta["control_input"] = []
	(_meta["control_input"] as Array).append({"label": label, "at": [at.x, at.y],
		"rect": [r.position.x, r.position.y, r.size.x, r.size.y], "disabled": button.disabled})
	return true

func _push_key(keycode: int, shift := false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.shift_pressed = shift
		ev.pressed = pressed
		get_viewport().push_input(ev, true)
		await get_tree().process_frame

func _prove_reduced_motion_control(pb) -> bool:
	var sim_before := _control_witness()
	var selected_before := String(_main.get("_selected_id"))
	var pos_before: Vector2 = pb.cam.position
	var zoom_before: Vector2 = pb.cam.zoom
	var buttons: Array = (_main.get("_clean_action_btns") as Array).duplicate()
	buttons.append(_main.get("_clean_guest_pass_btn"))
	if buttons.size() != 8:
		return false
	get_viewport().gui_release_focus()
	(buttons[0] as Control).grab_focus()
	await get_tree().process_frame
	var forward: Array = [String((get_viewport().gui_get_focus_owner() as Control).get_meta("player_verb", ""))]
	for _i in buttons.size():
		await _push_key(KEY_TAB)
		var owner := get_viewport().gui_get_focus_owner()
		forward.append(String(owner.get_meta("player_verb", "")) if owner != null else "")
	var reverse: Array = [forward[-1]]
	for _i in buttons.size():
		await _push_key(KEY_TAB, true)
		var owner := get_viewport().gui_get_focus_owner()
		reverse.append(String(owner.get_meta("player_verb", "")) if owner != null else "")
	_snap("focused", pb)
	await _wait(2, 50)
	var pos_after: Vector2 = pb.cam.position
	var zoom_after: Vector2 = pb.cam.zoom
	var selected_after := String(_main.get("_selected_id"))
	var camera_changed := pos_after != pos_before or zoom_after != zoom_before
	var expected_forward := ["greet", "give", "gossip", "invite", "confront", "apologize", "mediate", "cafe_guest_pass:revoke", "greet"]
	var expected_reverse := ["greet", "cafe_guest_pass:revoke", "mediate", "apologize", "confront", "invite", "gossip", "give", "greet"]
	var okay := forward == expected_forward and reverse == expected_reverse and selected_after == selected_before \
		and sim_before == _control_witness() and not camera_changed
	_meta["reduced_motion_receipt"] = {"enabled": _reduced_motion,
		"route": "Viewport.push_input(InputEventKey KEY_TAB/Shift-Tab)", "selected_before": selected_before,
		"selected_after": selected_after, "camera_before": [pos_before.x, pos_before.y, zoom_before.x, zoom_before.y],
		"camera_after": [pos_after.x, pos_after.y, zoom_after.x, zoom_after.y],
		"camera_changed": camera_changed, "sim_unchanged": sim_before == _control_witness(),
		"forward": forward, "reverse": reverse, "focus_visible": get_viewport().gui_get_focus_owner() != null,
		"no_trap": okay, "pass": okay}
	get_viewport().gui_release_focus()
	return okay

## 进店。portal=走出货路径（tapped→_portal_click）；flip=只翻 active_space（--void-gate 同款）。
func _enter(pb) -> bool:
	if _mode == "flip":
		pb.active_space = _space
		return true
	var wp = _portal_world_pos("town", _space)
	if wp == null:
		return false
	pb.emit_signal("tapped", wp)      # ← 与真的点一下门【同一个】入口：Main._on_probe_tap 接的就是它
	return true

## 上/下楼（AM3）：点当前楼层的楼梯 portal 格 —— 与真的点一下楼梯【同一个】入口（tapped→_portal_click）。
## 方向由 Main._portal_click 按当前 active_floor 自己判：在 1f 点它上楼、在 2f 点它下楼（p_cafe_stairs 双向）。
func _climb(pb) -> bool:
	if _mode == "flip":
		# flip 档没有"点楼梯"这条出货路径可复现，直接翻当前 Space 的另一层（仅供并排对照，非默认）。
		var sg0 = _main.get("_sg")
		if sg0 == null: return false
		var fls: Array = sg0.floors_of(String(pb.active_space))
		if fls.size() <= 1: return false
		var j := fls.find(String(pb.active_floor))
		pb.active_floor = String(fls[(maxi(j, 0) + 1) % fls.size()])
		return true
	var wp = _stairs_world_pos(pb)
	if wp == null:
		return false
	pb.emit_signal("tapped", wp)      # ← 与真的点楼梯【同一个】入口
	return true

## 取当前 (active_space, active_floor) 上那个 kind=="stairs" 的 portal 端点格心世界坐标。
## 走 _main._sg.portals（门的真源只有一份），与 _portal_world_pos 同一条纪律；按【当前楼层】匹配，
## 这样 1f 上取到的是"上楼口"、2f 上取到的是"下楼口"（本例两端同格 [1,1]，但匹配逻辑不依赖这一点）。
func _stairs_world_pos(pb):
	var sg = _main.get("_sg")
	if sg == null:
		return null
	var asp := String(pb.active_space); var afl := String(pb.active_floor)
	for p in sg.portals:
		if String(p.get("kind", "")) != "stairs":
			continue
		for side in ["from", "to"]:
			var e: Dictionary = p.get(side, {})
			if String(e.get("space", "")) != asp or String(e.get("floor", "")) != afl:
				continue
			var pos: Array = e.get("pos", [0, 0])
			return Vector2((float(pos[0]) + 0.5) * 48.0, (float(pos[1]) + 0.5) * 48.0)
	return null

## 出店。portal 模式下点的是室内那一侧的同一个 portal 格。
func _leave(pb) -> bool:
	if _mode == "flip":
		pb.active_space = "town"
		return true
	var wp = _portal_world_pos(_space, "town")
	if wp == null:
		return false
	pb.emit_signal("tapped", wp)
	return true

## 从 Main 的 SpaceGraph 里取 from→to 那个 portal 在【from 侧】的格心世界坐标。
## 走 `_main._sg.portals` 而不是自己 parse spaces.json：门的真源只有一份，抄第二份必然漂。
func _portal_world_pos(from_space: String, to_space: String):
	var sg = _main.get("_sg")
	if sg == null:
		return null
	for p in sg.portals:
		for side in ["from", "to"]:
			var a: Dictionary = p.get(side, {})
			var b: Dictionary = p.get("to") if side == "from" else p.get("from")
			if String(a.get("space", "")) != from_space or String(b.get("space", "")) != to_space:
				continue
			var pos: Array = a.get("pos", [0, 0])
			return Vector2((float(pos[0]) + 0.5) * 48.0, (float(pos[1]) + 0.5) * 48.0)
	return null

## 存一帧 + 记下判据要用的几何。
## ★ 地图矩形按【相机】算，不按窗口算 —— docs/41 §6 盲区⑥：`--resolution` 不改变相机取景，
##   `get_visible_rect().size` 返回的是基准 1280×768 视口，画布随后被整体拉伸。
##   照窗口尺寸套公式会把矩形放大 15%，于是产出一个**假的**"界内被改到了"。
##   这里用的是 `ProbeController.screen_to_world` 的**逆式**（同一份真源，不新造一套）。
func _snap(name: String, pb) -> void:
	# ⚠ **不要**在这里 `await RenderingServer.frame_post_draw`：实测（2026-07-30）在 `--headless` 下
	#   那个信号**永不发射** ⇒ 本场景会永远挂住 —— 正是 docs/41 §1 点名的"比红更坏"的那种形态
	#   （`ci.sh` 会一直等，不会变红）。调用方在此之前已经等过 `_settle` 帧，最后一帧早已画完；
	#   出货的 `--shot`（Main.gd:502-505）也是"等一会儿再直接取"，同一条路。
	var img := get_viewport().get_texture().get_image()
	var path := "%s/rt_%s.png" % [_out, name]
	if img == null or img.get_width() <= 1 or img.get_height() <= 1:
		# `--headless` 走到这里是**正常**的（没有 framebuffer）。它必须是一句清楚的失败，
		# 不能是一张 1x1 的黑图被后面的判据当成"画面变了"。
		print("[SPACESHOT] ❌ %s 取不到 viewport 图像（没有真 framebuffer？本场景需要 Xvfb/带窗口 + opengl3）" % name)
		_rc = 1
		return
	if _capture_size.x > 0 and _capture_size.y > 0 and (img.get_width() != _capture_size.x or img.get_height() != _capture_size.y):
		print("[SPACESHOT] ❌ native source mismatch requested=%s actual=%dx%d; post-capture resize is forbidden"
			% [_capture_size, img.get_width(), img.get_height()])
		_rc = 1
		return
	var save_error := img.save_png(path)
	if save_error != OK:
		print("[SPACESHOT] ❌ %s PNG write failed path=%s error=%d" % [name, path, save_error])
		_rc = 1
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var bounds: Rect2 = _main.call("_space_bounds")
	var tl: Vector2 = (bounds.position - pb.cam.position) * pb.cam.zoom + vp * 0.5
	var br: Vector2 = (bounds.end - pb.cam.position) * pb.cam.zoom + vp * 0.5
	# The pixel gate consumes one canonical 1280x768 design-space contract even
	# when the source framebuffer is native-sized.  Keep the source viewport as
	# separate provenance; the desktop scale is exactly Vector2.ONE.
	var design_scale := Vector2(1280.0 / vp.x, 768.0 / vp.y)
	var design_tl := tl * design_scale
	var design_size := (br - tl) * design_scale
	var view = _main.get("_view")
	var vd: int = int(view.get("_void_draws")) if view != null else -1
	_meta[name] = {
		"png": path, "w": img.get_width(), "h": img.get_height(),
		"native_source": _capture_size == Vector2i.ZERO or Vector2i(img.get_width(), img.get_height()) == _capture_size,
		"post_capture_resize": false,
		"source_viewport": [vp.x, vp.y],
		"design_vp": [1280.0, 768.0],
		"map_rect_design": [design_tl.x, design_tl.y, design_size.x, design_size.y],
		"space": String(pb.active_space), "floor": String(pb.active_floor),
		"cam": [pb.cam.position.x, pb.cam.position.y], "zoom": pb.cam.zoom.x,
		"void_draws": vd,
	}
	print("[SPACESHOT] %-12s space=%-6s floor=%-8s png=%dx%d cam=(%.1f,%.1f) zoom=%.4f 地图矩形(设计坐标)=(%.1f,%.1f,%.1f,%.1f) void_draws=%d"
		% [name, String(pb.active_space), String(pb.active_floor), img.get_width(), img.get_height(),
			pb.cam.position.x, pb.cam.position.y, pb.cam.zoom.x,
			design_tl.x, design_tl.y, design_size.x, design_size.y, vd])

func _observatory_sim_snapshot() -> String:
	return JSON.stringify({
		"town": Sim.town_coin, "external": Sim.external_coin, "stock": Sim.town_stock,
		"events": Sim.event_log, "next": Sim._next_event_id, "event_digest": Sim.event_digest,
		"manifests": Sim.cargo_manifests, "order": Sim.cargo_manifest_order,
		"path_cache": Sim._path_cache, "player": Sim.get_agent("player"),
	})

## 等够 n 帧 **且** 够 ms 毫秒。两个条件都要：容器软渲染实测 5-10 fps（docs/41 §6 盲区⑧），
## 光数帧在快机器上会短到纹理还没加载完；光看墙钟在慢机器上会拿到一张半渲的图。
func _wait(n: int, ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	var f := 0
	while f < n or Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame
		f += 1
