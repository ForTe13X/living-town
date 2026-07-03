extends Node
## slm_live_test.gd — 真连本地嵌入式 SLM（NobodyWho + GGUF，纯 CPU）实测「效果」。
## 用法：godot --headless --path . res://scenes/slm_live_test.tscn  （镜像 gamecraft-slm:24，含 libvulkan1 loader）
## 测：① 决策 JSON(pick+台词，json_schema 受限解码) ② 玩家自由对话 ③ tok/s 粗测。对照 LM Studio(llm 后端)。

var MODEL_PATH := AIBackend.slm_model_path   # 跟随默认模型（现为 3B）；--model 可覆盖

var _model
var _chat
var _use_gpu := false

func _ready() -> void:
	if not ClassDB.class_exists("NobodyWhoChat"):
		print("❌ NobodyWho 扩展未加载（ClassDB 无 NobodyWhoChat）")
		get_tree().quit(1)
		return
	_use_gpu = "--gpu" in OS.get_cmdline_user_args()   # 本机原生加 --gpu 走 AMD Vulkan；容器省略=CPU
	print("=== 嵌入式 SLM 实测  model=%s  (%s)" % [MODEL_PATH.get_file(), ("GPU" if _use_gpu else "CPU")])
	_model = ClassDB.instantiate("NobodyWhoModel")
	_model.set("model_path", MODEL_PATH)
	_model.set("use_gpu_if_available", _use_gpu)
	add_child(_model)
	Sim.start_new(20260626)
	for i in 1400:                # ~6 sim-日：攒出真实需求/关系/记忆/夜间反思洞察 → prompt 有血肉
		Sim.tick()
	await _run()
	get_tree().quit(0)

## 新建一个 chat worker（system_prompt + 可选 json_schema 约束），返回 chat 节点。
func _new_chat(system_prompt: String, schema_json: String = "") -> Object:
	var chat = ClassDB.instantiate("NobodyWhoChat")
	chat.set("model_node", _model)
	chat.set("system_prompt", system_prompt)
	chat.set("allow_thinking", false)
	add_child(chat)
	chat.call("start_worker")                       # 必须先起 worker，sampler 配置才生效
	if schema_json != "" and chat.has_method("set_sampler_preset_constrain_with_json_schema"):
		chat.call("set_sampler_preset_constrain_with_json_schema", schema_json)
	return chat

func _say_await(chat: Object, msg: String) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	chat.call("ask", msg)                            # say 已弃用→ask（生成响应）
	var resp = await chat.response_finished
	var dt := Time.get_ticks_msec() - t0
	return {"text": String(resp).strip_edges(), "ms": dt}

func _run() -> void:
	var ag: Dictionary = Sim.get_agent("aria")
	if ag.is_empty():
		ag = Sim.agents[0]
	var cands := Sim.agent_candidates(ag)

	# ── ① 决策 JSON（json_schema 受限解码）──
	print("\n① 决策测试  agent=%s  候选数=%d" % [Sim._name(ag), cands.size()])
	var c1 := _new_chat(AIBackend._system_prompt(), JSON.stringify(AIBackend.DECISION_SCHEMA))
	var r1 := await _say_await(c1, AIBackend.build_prompt(ag, cands, Sim._context(ag)))
	print("  耗时 %dms  (%.1f 字/s)" % [int(r1["ms"]), float(String(r1["text"]).length()) / maxf(0.001, float(r1["ms"]) / 1000.0)])
	print("  raw: %s" % r1["text"])
	var intent := AIBackend.parse_decision(String(r1["text"]), cands)
	if intent.is_empty():
		print("  ❌ 解析失败 → 引擎兜底 logic")
	else:
		print("  ✅ 解析: 选了 [%s%s]  台词「%s」" % [
			str(intent.get("action", "")),
			("→" + Sim._name(Sim.get_agent(String(intent.get("partner", ""))))) if String(intent.get("kind", "")) == "social" else "",
			str(intent.get("say", ""))])
	c1.queue_free()

	# ── ② 玩家自由对话 ──
	print("\n② 玩家对话测试  对 %s 说：你最近怎么样？听说镇上要办夜市？" % Sim._name(ag))
	var p: Dictionary = ag.get("persona", {})
	var mm := AIBackend._mood(ag)
	var sys := "你在扮演像素小镇居民「%s」。%s 性格:%s 口吻:%s。此刻是%s，你%s。用一两句中文自然回应玩家，符合人设与当下心情，不要旁白。" % [
		p.get("name", ""), p.get("bio", ""), "·".join(p.get("traits", [])), p.get("style", ""), AIBackend._phase_zh(Sim.time_of_day()), String(mm[0])]
	var c2 := _new_chat(sys)
	var r2 := await _say_await(c2, "你最近怎么样？听说镇上要办夜市？")
	print("  耗时 %dms  (%.1f 字/s)" % [int(r2["ms"]), float(String(r2["text"]).length()) / maxf(0.001, float(r2["ms"]) / 1000.0)])
	print("  %s：%s" % [Sim._name(ag), r2["text"]])
	c2.queue_free()

	# ── ③ LLM 反思润色（把近期记忆/夜间地板洞察 → 一句内心独白）──
	print("\n③ 反思润色测试  agent=%s" % Sim._name(ag))
	var recent: Array = ag["memory"].retrieve([], Sim.tick_no, 5)
	var rsys := "你在扮演像素小镇居民%s（%s，口吻:%s）。回顾最近的经历，用一句你自己口吻的内心独白，说出此刻心境或对某人的看法。第一人称、不超过25字、只输出这一句、不要引号。 /no_think" % [p.get("name", ""), p.get("bio", ""), p.get("style", "")]
	var c3 := _new_chat(rsys)
	var r3 := await _say_await(c3, "最近：" + "；".join(recent) + "。")
	print("  近期记忆：%s" % "；".join(recent))
	print("  内心独白：%s" % r3["text"])
	c3.queue_free()

	print("\n— SLM 实测结论 —")
	print("  嵌入式离线(NobodyWho+%s, %s)：决策/对话 见上。对照 LM Studio(qwen-3-8b) 看延迟与质量。" % [MODEL_PATH.get_file(), ("GPU" if _use_gpu else "CPU")])
