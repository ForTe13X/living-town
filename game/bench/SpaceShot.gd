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
##   `--rt-journey full`（AM3/编号135）= 全楼层旅程 town→cafe/1f→上楼2f→下楼1f→出门，逐段断言落在对的 Floor。
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
var _journey := "simple"    # simple=进店→出店三帧（现役 1F 往返门）；full=全楼层旅程 town→1f→上楼2f→下楼1f→出门（AM3/编号135）
var _redraw := "auto"       # auto=切完空间补一次 _redraw_all()（= 下一个 tick 到来时的稳定态）；none=不补（暂停复现，见下）
var _settle0 := 40          # 首帧之后的暖机帧数（纹理加载 + 插值吸附）
var _settle := 24           # 每次空间切换之后的暖机帧数
var _min_ms0 := 2500        # 暖机的墙钟下限（软渲染下帧率极低，光数帧会太短）
var _min_ms := 1200
var _watchdog_ms := 180000  # 看门狗：到点还没跑完就 rc=1 退出（绝不让本场景把 CI 挂住，见下）
var _main: Node
var _meta := {}
var _rc := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--rt-out" and i + 1 < args.size(): _out = args[i + 1]
		elif args[i] == "--rt-space" and i + 1 < args.size(): _space = args[i + 1]
		elif args[i] == "--rt-mode" and i + 1 < args.size(): _mode = args[i + 1]
		elif args[i] == "--rt-journey" and i + 1 < args.size(): _journey = args[i + 1]
		elif args[i] == "--rt-redraw" and i + 1 < args.size(): _redraw = args[i + 1]
		elif args[i] == "--rt-settle" and i + 1 < args.size(): _settle = int(args[i + 1])
	if _out == "":
		print("[SPACESHOT] ❌ 缺 --rt-out <dir>")
		get_tree().quit(2)
		return
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
	var pb = _main.get("_probe")
	if pb == null:
		print("[SPACESHOT] ❌ 拿不到 Main._probe")
		get_tree().quit(1)
		return
	var cam0_pos: Vector2 = pb.cam.position
	var cam0_zoom: Vector2 = pb.cam.zoom
	_snap("town_before", pb)

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
	_snap("interior" if _journey != "full" else "cafe_1f", pb)

	# ── 全楼层旅程（AM3/编号135）：cafe/1f →（楼梯 portal）2f →（楼梯）1f ──────────────
	# 只在 --rt-journey full 时跑；simple 模式一个字节都不变（现役 1F 往返门原样）。
	# 逐段断言【落在对的 Floor】——这是"目标层改错 ⇒ 门必红"的机器化（与宿主 python 侧的 meta 楼层核对互为双证）。
	# 楼梯 cell 由 _stairs_world_pos 从 SpaceGraph 真源取（不抄第二份坐标），点它 → Main._portal_click 按
	# 当前 active_floor 判方向（1f→2f 上、2f→1f 下），access=owner 不拦 Probe（观察者不是 agent，见 Main.gd:2439）。
	if _journey == "full":
		if String(pb.active_floor) != "1f":
			print("[SPACESHOT] ❌ 进店后应在 1f，实为 %s" % String(pb.active_floor)); _rc = 1
		# 上楼 (cafe/1f → cafe/2f)
		if not _climb(pb):
			print("[SPACESHOT] ❌ 上楼：找不到 cafe/%s 的楼梯 portal" % String(pb.active_floor))
			get_tree().quit(1); return
		_refresh()
		await _wait(_settle, _min_ms)
		if String(pb.active_floor) != "2f":
			print("[SPACESHOT] ❌ 上楼后应在 2f，实为 %s（楼梯目标层不对/portal 断）" % String(pb.active_floor)); _rc = 1
		_snap("cafe_2f", pb)
		# 下楼 (cafe/2f → cafe/1f)
		if not _climb(pb):
			print("[SPACESHOT] ❌ 下楼：找不到 cafe/%s 的楼梯 portal" % String(pb.active_floor))
			get_tree().quit(1); return
		_refresh()
		await _wait(_settle, _min_ms)
		if String(pb.active_floor) != "1f":
			print("[SPACESHOT] ❌ 下楼后应回 1f，实为 %s" % String(pb.active_floor)); _rc = 1
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
	_snap("town_after", pb)

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
	img.save_png(path)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var bounds: Rect2 = _main.call("_space_bounds")
	var tl: Vector2 = (bounds.position - pb.cam.position) * pb.cam.zoom + vp * 0.5
	var br: Vector2 = (bounds.end - pb.cam.position) * pb.cam.zoom + vp * 0.5
	var view = _main.get("_view")
	var vd: int = int(view.get("_void_draws")) if view != null else -1
	_meta[name] = {
		"png": path, "w": img.get_width(), "h": img.get_height(),
		"design_vp": [vp.x, vp.y],
		"map_rect_design": [tl.x, tl.y, br.x - tl.x, br.y - tl.y],
		"space": String(pb.active_space), "floor": String(pb.active_floor),
		"cam": [pb.cam.position.x, pb.cam.position.y], "zoom": pb.cam.zoom.x,
		"void_draws": vd,
	}
	print("[SPACESHOT] %-12s space=%-6s floor=%-8s png=%dx%d cam=(%.1f,%.1f) zoom=%.4f 地图矩形(设计坐标)=(%.1f,%.1f,%.1f,%.1f) void_draws=%d"
		% [name, String(pb.active_space), String(pb.active_floor), img.get_width(), img.get_height(),
			pb.cam.position.x, pb.cam.position.y, pb.cam.zoom.x,
			tl.x, tl.y, br.x - tl.x, br.y - tl.y, vd])

## 等够 n 帧 **且** 够 ms 毫秒。两个条件都要：容器软渲染实测 5-10 fps（docs/41 §6 盲区⑧），
## 光数帧在快机器上会短到纹理还没加载完；光看墙钟在慢机器上会拿到一张半渲的图。
func _wait(n: int, ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	var f := 0
	while f < n or Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame
		f += 1
