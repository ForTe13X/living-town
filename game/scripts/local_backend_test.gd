extends SceneTree
## local_backend_test.gd — 验证 AIBackend 的 local 档（端上 llama.cpp 子进程，docs/191）全链路：
##   ① probe_capability("local") 能起服务 + 测暖延迟 + 启用；② 决策 GBNF 只回合法编号、落地；
##   ③ 生活模式说法（suggest_approaches）回包可解析；④ 玩家对话回包非空；⑤ 退出时杀掉子进程。
## 桌面：LT_LLAMA_SERVER=<llama-server.exe> godot --headless --path game -s res://scripts/local_backend_test.gd -- --model <gguf>
var AIB: Node
var S: Node

func _init() -> void:
	call_deferred("_go")

func _go() -> void:
	AIB = root.get_node("/root/AIBackend")
	S = root.get_node("/root/Sim")
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--model" and i + 1 < args.size():
			AIB.slm_model_override = args[i + 1]
	var fails := 0
	print("available: ", AIB.available_backends())
	if not "local" in AIB.available_backends():
		print("❌ local 档不可用（缺 llama-server 可执行文件）"); quit(1); return
	S.start_new(20260912)
	var ag: Dictionary = S.agents[0]
	var info := [{}]                               # 闭包按值捕获局部变量 → 用数组盒子带回结果
	var t0 := Time.get_ticks_msec()
	await AIB.probe_capability("local", ag, S.agent_candidates(ag), S._context(ag), func(i): info[0] = i)
	print("① probe %s  (incl. spawn+load %dms)" % [str(info[0]), Time.get_ticks_msec() - t0])
	if AIB.backend != "local":
		print("❌ probe 未启用 local"); fails += 1
	# ② 决策：真 decide 状态机，墙钟推进直到落地
	S.backend = AIB
	S.auto_run = false
	AIB.reset_stats()
	var t_end := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < t_end and int(AIB.stats["landed"]) < 5:
		S.tick()
		await create_timer(0.08).timeout
	var st: Dictionary = AIB.decision_stats()
	print("② decide fired=%d landed=%d parse_fail=%d timeout=%d" % [st["fired"], st["landed"], st["parse_fail"], int(AIB.stats["timeout"])])
	if int(st["landed"]) < 1 or int(st["parse_fail"]) > 0:
		print("❌ 决策未落地或有解析失败"); fails += 1
	S.backend = null
	# ③ 说法
	var tgt: Dictionary = S.agents[1]
	var got := [null]
	var t1 := Time.get_ticks_msec()
	AIB.suggest_approaches(ag, tgt, ["greet", "give", "gossip", "invite"], {"tick": S.tick_no, "tod": 0.7}, func(l): got[0] = l)
	while got[0] == null and Time.get_ticks_msec() - t1 < 30000:
		await process_frame
	print("③ approaches %dms → %s" % [Time.get_ticks_msec() - t1, str(got[0])])
	if got[0] == null or (got[0] as Array).is_empty():
		print("❌ 说法无回包"); fails += 1
	# ④ 对话
	var rep := [null]
	var t2 := Time.get_ticks_msec()
	AIB.chat(tgt, "最近码头那边怎么样？", {"tick": S.tick_no, "tod": 0.7}, func(r): rep[0] = r)
	while rep[0] == null and Time.get_ticks_msec() - t2 < 30000:
		await process_frame
	print("④ chat %dms → %s" % [Time.get_ticks_msec() - t2, str(rep[0])])
	if rep[0] == null or String(rep[0]) == "":
		print("❌ 对话无回包"); fails += 1
	# ⑤ 收尾
	var pid: int = AIB.local_llama._pid
	AIB.local_llama.stop()
	await create_timer(0.3).timeout
	print("⑤ server pid %d running after stop: %s" % [pid, OS.is_process_running(pid)])
	print("RESULT: %s" % ("PASS" if fails == 0 else "FAIL x%d" % fails))
	quit(0 if fails == 0 else 1)
