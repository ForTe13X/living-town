extends Node
## bench/slm_lifecycle_soak.gd — 池化 SLM worker 的【生命周期回归跑】（桌面夜跑，不进 CI）。
##
## 为什么必须有它：docs/34 记着这类 bug 的两次翻车——第一版"根因"(Adreno)被自己的后续测试证伪，
## 第一版"修复"(C1 顺手 free chat)【反而重新引入了它要消灭的 use-after-free】，两次都靠对抗评审才逮到。
## 而现在自动化里【没有任何东西】覆盖这条路：tools/ci.sh 从不跑 BackendBench 或任何 SLM 测试，
## mock 后端直接填 _pending（AIBackend._fire 的 mock 分支）根本走不到 _slm_submit ——
## 于是闭包捕获 epoch、fired[] 去重、finish 里显式断【两条】信号、换模型/换 GPU 的延后拆，全无回归网。
##
## 断言（全部是"上一次真出过的 bug"的直接对应物）：
##   A. 进程活着退出（旧 per-call churn 版在此处段错误 EXIT 139）
##   B. 池化不繁殖：AIBackend 底下活着的 NobodyWhoChat / NobodyWhoModel 恒 ≤ 2（池化=1，容一个拆建重叠）
##   C. C2 信号句柄不累积：response_finished 的连接数恒 ≤ 2；且空闲(_slm_busy=false)时必须归 0
##      —— 这正是 CONNECT_ONE_SHOT 泄漏的直接探针（旧版每成功一发就残留一个死闭包，O(submits) 涨）
##   D. C1 换模型/换 GPU 撞在飞不崩：跑动中周期性 set_model_path / set_slm_use_gpu
##   E. 非空跑（fired>0）：防"什么都没发生"式的假绿
##
## ⚠ 运行方式 = 【场景】，不是 --script。原因（实测）：`--script` 模式下 Godot 完全不注册 autoload，
##    AIBackend.gd 里对全局 Sim 的引用会在【编译期】就报 "Identifier not found: Sim" —— 整个脚本加载失败。
##    BackendBench.gd 头注释记的也是同一件事。故本 bench 走 .tscn，与 BackendBench 同构。
## 用法：
##   godot --headless --path game res://bench/slm_lifecycle_soak.tscn -- [--model PATH] [--seconds 60] [--swap-every 15] [--agents 12]
## 缺 NobodyWho 扩展 / 缺 gguf → 打印原因并 exit 0（SKIP）。它按设计【永远不该】把托管 CI 弄红：
##   扩展二进制与模型权重都被 .gitignore 排除（红线 #4），云端 runner 上本就不存在。

var _seconds := 60          # 跑多久（墙钟秒）
var _swap_every := 15       # 每多少秒做一次 换模型/换 GPU 的生命周期扰动
var _agents := 12
var _violations: Array = []
var _max_chat := 0
var _max_model := 0
var _max_conn := 0
var _idle_conn_leak := 0

func _ready() -> void:
	var model_path := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--model" and i + 1 < args.size(): model_path = args[i + 1]
		elif args[i] == "--seconds" and i + 1 < args.size(): _seconds = int(args[i + 1])
		elif args[i] == "--swap-every" and i + 1 < args.size(): _swap_every = int(args[i + 1])
		elif args[i] == "--agents" and i + 1 < args.size(): _agents = int(args[i + 1])

	print("=== SLM lifecycle soak（池化 worker 回归跑；桌面夜跑，不进 CI）===")
	# ── SKIP 条件：必须先判，且必须 exit 0 ────────────────────────────────
	if not ClassDB.class_exists("NobodyWhoModel"):
		print("SKIP: NobodyWho GDExtension 未加载（二进制按红线 #4 不入库）→ 无可测对象。exit 0")
		get_tree().quit(0); return
	if model_path != "":
		AIBackend.slm_model_path = model_path
	var resolved: Dictionary = AIBackend.model_status()
	if not bool(resolved["exists"]):
		print("SKIP: 找不到 gguf（解析到 %s）——权重按红线 #4 从不入库。用 --model <绝对路径> 指定。exit 0" % resolved["path"])
		get_tree().quit(0); return
	print("model=%s  seconds=%d  swap-every=%ds  N=%d" % [resolved["path"], _seconds, _swap_every, _agents])

	await _soak()

	# ── 判定 ──────────────────────────────────────────────────────────────
	var st: Dictionary = AIBackend.stats
	print("\n— 结果 —")
	# 刻意【不】在这里打决策占比：本 bench 是尽速推 tick（不按 19.2s/sim-日 的出货节奏），
	# 算出来的占比毫无外推价值，印出来只会被人引用。要占比请跑 BackendBench --realtime（见 docs/35）。
	print("  fired=%d landed=%d bad_parse=%d timeout=%d   （本跑不按出货节奏，故不报决策占比）" % [
		int(st["fired"]), int(st["landed"]), int(st["bad_parse"]), int(st["timeout"])])
	print("  峰值 存活 NobodyWhoChat=%d  NobodyWhoModel=%d  (池化契约: ≤2)" % [_max_chat, _max_model])
	print("  峰值 response_finished 连接数=%d  空闲期残留连接采样次数=%d  (C2 契约: ≤2 且空闲必归 0)" % [_max_conn, _idle_conn_leak])
	if int(st["fired"]) <= 0:
		_violations.append("E: fired=0 —— 一发都没打出去，本跑不构成证据（假绿）")
	if _max_chat > 2: _violations.append("B: 存活 chat 峰值 %d > 2（池化被破坏，回到 per-call churn）" % _max_chat)
	if _max_model > 2: _violations.append("B: 存活 model 峰值 %d > 2" % _max_model)
	if _max_conn > 2: _violations.append("C: response_finished 连接峰值 %d > 2（信号句柄在累积，C2 回归）" % _max_conn)
	if _idle_conn_leak > 0: _violations.append("C: 空闲期仍有 %d 次采样到未断开的连接（finish 没断干净，C2 回归）" % _idle_conn_leak)
	if _violations.is_empty():
		print("=== SLM LIFECYCLE SOAK: PASS ✅（无崩溃、池化不繁殖、信号不累积、换模型撞在飞不崩）===")
		get_tree().quit(0)
	else:
		for v in _violations: print("  ❌ " + v)
		print("=== SLM LIFECYCLE SOAK: FAIL ❌ ===")
		get_tree().quit(1)

## 用真·游戏内路径驱动：Sim.tick() → AIBackend.decide → _fire_slm → _slm_submit。
## 只有走这条路，闭包 epoch / fired[] 去重 / finish 断连 才真的被执行到（mock 后端走不到）。
func _soak() -> void:
	Sim.spawn_count = _agents
	Sim.start_new(1)
	Sim.backend = AIBackend
	Sim.auto_run = false
	AIBackend.backend = "slm"
	AIBackend.backend_requested = "slm"    # 不同步 → decide() 会把 backend 拽回 logic → fired 恒 0
	AIBackend.reset_stats()
	var t0 := Time.get_ticks_msec()
	var next_swap := t0 + _swap_every * 1000
	var phase := 0
	while Time.get_ticks_msec() - t0 < _seconds * 1000:
		Sim.tick()
		await get_tree().process_frame
		_sample()
		if Time.get_ticks_msec() >= next_swap:
			next_swap = Time.get_ticks_msec() + _swap_every * 1000
			phase += 1
			# 三种生命周期扰动轮转，都刻意【不管此刻是否有在飞】——撞上在飞正是 C1 要防的那一刻。
			match phase % 3:
				0:
					print("[soak] set_model_path（撞在飞=%s）" % str(AIBackend._slm_busy))
					AIBackend.set_model_path(AIBackend._resolve_model_path())
				1:
					print("[soak] set_slm_use_gpu(%s)（撞在飞=%s）" % [str(not AIBackend.slm_use_gpu), str(AIBackend._slm_busy)])
					AIBackend.set_slm_use_gpu(not AIBackend.slm_use_gpu)
				2:
					print("[soak] cancel_all（世界重置：迟包必须按 epoch 作废，撞在飞=%s）" % str(AIBackend._slm_busy))
					AIBackend.cancel_all()

## 每帧采样：活着的 worker 节点数 + 池化 chat 上的信号连接数。
## 空闲(_slm_busy=false 且无待拆)时连接数【必须】是 0——finish 里那两条 disconnect 就是为此存在的。
func _sample() -> void:
	var chats := 0
	var models := 0
	for c in AIBackend.get_children():
		match c.get_class():
			"NobodyWhoChat": chats += 1
			"NobodyWhoModel": models += 1
	_max_chat = maxi(_max_chat, chats)
	_max_model = maxi(_max_model, models)
	var chat = AIBackend._slm_chat
	if chat != null and is_instance_valid(chat) and chat.has_signal("response_finished"):
		var n: int = chat.get_signal_connection_list("response_finished").size()
		_max_conn = maxi(_max_conn, n)
		if n > 0 and not AIBackend._slm_busy and not AIBackend._slm_reload_pending:
			_idle_conn_leak += 1
