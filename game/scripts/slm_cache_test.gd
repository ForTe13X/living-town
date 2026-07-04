extends Node
## slm_cache_test.gd — 标定实验③（docs/15 §2 共识）：per-call 一次性 worker vs 持久 worker 的深化 prompt 决策延迟。
## 验证"cache_prompt/前缀 KV 复用能把 2.8s 砍回 <1s"是否成立（成立→AIBackend 改持久 worker 值得做）。
## 用法（本机原生 GPU）：godot --headless --path . res://scenes/slm_cache_test.tscn -- --gpu

var _model

func _ready() -> void:
	if not ClassDB.class_exists("NobodyWhoChat"):
		print("❌ NobodyWho 未加载")
		get_tree().quit(1)
		return
	var gpu := "--gpu" in OS.get_cmdline_user_args()
	_model = ClassDB.instantiate("NobodyWhoModel")
	_model.set("model_path", AIBackend.slm_model_path)
	_model.set("use_gpu_if_available", gpu)
	add_child(_model)
	Sim.backend = null
	Sim.auto_run = false
	Sim.start_new(20260626)
	for i in 1400:
		Sim.tick()
	print("=== 持久 worker / KV 复用标定  model=%s (%s) ===" % [AIBackend.slm_model_path.get_file(), "GPU" if gpu else "CPU"])
	await _run()
	get_tree().quit(0)

func _mk(sys: String) -> Object:
	var c = ClassDB.instantiate("NobodyWhoChat")
	c.set("model_node", _model)
	c.set("system_prompt", sys)
	c.set("allow_thinking", false)
	add_child(c)
	c.call("start_worker")
	return c

func _ask(c: Object, msg: String) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	c.call("ask", msg)
	var resp = await c.response_finished
	return {"ms": Time.get_ticks_msec() - t0, "text": String(resp).strip_edges()}

func _run() -> void:
	var sys := AIBackend._system_prompt()
	var prompts: Array = []
	for id in ["aria", "ben", "coco"]:
		var ag = Sim.get_agent(id)
		prompts.append(AIBackend.build_prompt(ag, Sim.agent_candidates(ag), Sim._context(ag)))

	# A) 现状：per-call 一次性 worker（每次新 worker+prompt 全量 prefill）
	print("\nA) per-call 一次性 worker（现状）")
	for i in 2:
		var c := _mk(sys)
		var r := await _ask(c, String(prompts[i]))
		print("  第%d次: %dms  raw=%s…" % [i + 1, int(r["ms"]), String(r["text"]).substr(0, 40)])
		c.queue_free()

	# B) 持久 worker：同一 worker 连问 3 个 agent 的决策（系统前缀+历史 KV 常驻）
	print("\nB) 持久 worker（KV 常驻,连问 3 个 agent）")
	var cp := _mk(sys)
	for i in 3:
		var r2 := await _ask(cp, String(prompts[i]))
		print("  第%d次: %dms  raw=%s…" % [i + 1, int(r2["ms"]), String(r2["text"]).substr(0, 40)])
	cp.queue_free()
	print("\n判读：B 的第2/3次 vs A——若显著下降(<1s)则持久 worker 值得落进 AIBackend；注意 B 历史会累积(语义需 reset 机制,本测只看延迟)。")
