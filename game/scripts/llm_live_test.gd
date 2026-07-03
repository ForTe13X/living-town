extends Node
## llm_live_test.gd — 真连 LM Studio 实测 LLM 后端（容器经 host.docker.internal:1234）。
## 用法：godot --headless --path . res://scenes/llm_live_test.tscn  （docker run 需 --add-host host.docker.internal:host-gateway）
## 测三件事：① 决策 JSON(pick+台词+schema 遵循) ② 玩家自由对话 ③ 简短端到端 backend=llm 不崩。

const ENDPOINT := "http://host.docker.internal:1234/v1/chat/completions"
var MODEL := "qwen-3-8b-instruct"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--model" and i + 1 < args.size():
			MODEL = args[i + 1]
	AIBackend.backend = "llm"
	AIBackend.endpoint = ENDPOINT
	AIBackend.model = MODEL
	Sim.start_new(20260626)
	print("=== LM Studio 实测  model=%s ===" % MODEL)
	await _run()
	get_tree().quit(0)

## 直接打一发 chat-completions（带 json_schema），返回 {code, content}。
func _post(messages: Array, schema) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 40.0
	var body := {"model": MODEL, "max_tokens": 120, "temperature": 0.7, "messages": messages}
	if schema != null:
		body["response_format"] = {"type": "json_schema", "json_schema": {"name": "decision", "schema": schema}}
	var headers := ["Content-Type: application/json", "Authorization: Bearer lm-studio"]
	var err := http.request(ENDPOINT, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		http.queue_free()
		return {"code": -1, "content": "request() err=%d" % err}
	var res = await http.request_completed
	var code: int = res[1]
	var raw_body: PackedByteArray = res[3]
	http.queue_free()
	var content := ""
	if code == 200:
		var j: Variant = JSON.parse_string(raw_body.get_string_from_utf8())
		if j is Dictionary and j.has("choices"):
			content = String(j["choices"][0].get("message", {}).get("content", ""))
	else:
		content = raw_body.get_string_from_utf8().substr(0, 300)
	return {"code": code, "content": content}

func _run() -> void:
	# ── ① 决策 JSON：用真候选 + 我们的 system/build_prompt + json_schema ──
	var ag: Dictionary = Sim.get_agent("aria")
	if ag.is_empty():
		ag = Sim.agents[0]
	var cands := Sim.agent_candidates(ag)
	print("\n① 决策测试  agent=%s  候选数=%d" % [Sim._name(ag), cands.size()])
	var t0 := Time.get_ticks_msec()
	# 镜像生产：不发 json_schema（实测长 prompt 卡死），靠 _system_prompt 里的 /no_think + parse_decision 抽 {…}
	var r1 := await _post([
		{"role": "system", "content": AIBackend._system_prompt()},
		{"role": "user", "content": AIBackend.build_prompt(ag, cands, Sim._context(ag))},
	], null)
	var dt := Time.get_ticks_msec() - t0
	print("  HTTP %d  耗时 %dms" % [int(r1["code"]), dt])
	print("  raw: %s" % str(r1["content"]).strip_edges())
	var intent := AIBackend.parse_decision(String(r1["content"]), cands)
	if intent.is_empty():
		print("  ❌ 解析失败 → 引擎会兜底 logic")
	else:
		print("  ✅ 解析: 选了 [%s%s]  台词「%s」" % [
			str(intent.get("action", "")),
			("→" + Sim._name(Sim.get_agent(String(intent.get("partner", ""))))) if String(intent.get("kind", "")) == "social" else "",
			str(intent.get("say", ""))])

	# ── ② 玩家自由对话（chat 路径）──
	print("\n② 玩家对话测试  对 %s 说：你最近怎么样？听说镇上要办夜市？" % Sim._name(ag))
	var p: Dictionary = ag.get("persona", {})
	var sys := "你在扮演像素小镇居民「%s」。%s 口吻：%s。用一两句中文自然回应玩家，符合人设，不要旁白。 /no_think" % [p.get("name", ""), p.get("bio", ""), p.get("style", "")]
	var t1 := Time.get_ticks_msec()
	var r2 := await _post([{"role": "system", "content": sys}, {"role": "user", "content": "你最近怎么样？听说镇上要办夜市？"}], null)
	print("  HTTP %d  耗时 %dms" % [int(r2["code"]), Time.get_ticks_msec() - t1])
	print("  %s：%s" % [Sim._name(ag), str(r2["content"]).strip_edges()])

	# ── ③ 端到端：backend=llm 真实时跑 ~25s，看异步 LLM 决策真落地（真延迟下需墙钟时间）──
	print("\n③ 端到端 backend=llm 真实时跑 ~25s（让真模型决策有时间解析落地）…")
	Sim.backend = AIBackend
	Sim.auto_run = false
	var before := Sim.event_log.size()
	var llm_says := 0
	var t_end := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < t_end:
		Sim.tick()
		await get_tree().create_timer(0.12).timeout   # 真时推进，给 HTTP 回调时间
	# 统计本段里带 LLM 生成台词的社交事件（last_say 非罐头）
	print("  完成：event_log +%d 条；末态 thinking=%d（真延迟下 LLM 稀疏驱动，引擎兜底其余）" % [
		Sim.event_log.size() - before, Sim.agents.filter(func(a): return bool(a.get("thinking", false))).size()])
	print("\n— 实测结论 —")
	print("  llm 后端解析/对话/端到端链路：见上。模型 = %s" % MODEL)
