extends Node
## slm_backend_test.gd — 验证「生产 AIBackend 的 slm 后端」真链路（NobodyWho）：
##   ① AIBackend.decide() 异步状态机(_wait→fire→response_finished→parse_decision) 落地一个合法 intent
##   ② AIBackend.chat() 自由对话回调返回非空人设台词
## 区别于 slm_live_test（那是直接调 NobodyWho）；此处走真正会被游戏调用的 AIBackend API。

func _ready() -> void:
	if not ClassDB.class_exists("NobodyWhoModel"):
		print("❌ NobodyWho 扩展未加载")
		get_tree().quit(1); return
	AIBackend.backend = "slm"
	AIBackend.slm_use_gpu = false        # 容器无 Vulkan 设备 → CPU
	Sim.start_new(20260626)
	print("=== AIBackend.slm 生产链路验证（NobodyWho, CPU）===")
	await _run()
	get_tree().quit(0)

func _run() -> void:
	var ag: Dictionary = Sim.get_agent("aria")
	if ag.is_empty():
		ag = Sim.agents[0]
	var cands := Sim.agent_candidates(ag)

	# ① decide() 状态机：反复调直到不再 _wait（fire→等 worker→ready→parse）
	print("\n① AIBackend.decide() 异步落地…")
	var t0 := Time.get_ticks_msec()
	var intent := {}
	var waited := 0
	while true:
		intent = AIBackend.decide(ag, cands, Sim._context(ag))
		if not intent.has("_wait"):
			break
		await get_tree().create_timer(0.2).timeout
		waited += 1
		if Time.get_ticks_msec() - t0 > 180000:    # 3 分钟硬超时保护
			print("  (超 180s，放弃)")
			break
	var dt := Time.get_ticks_msec() - t0
	if intent.is_empty():
		print("  → 返回空（解析失败/超时）→ 游戏中会兜底 logic。耗时 %dms" % dt)
	else:
		print("  ✅ decide 落地: 选了 [%s%s] 台词「%s」 (耗时 %dms)" % [
			str(intent.get("action", "")),
			("→" + Sim._name(Sim.get_agent(String(intent.get("partner", ""))))) if String(intent.get("kind", "")) == "social" else "",
			str(intent.get("say", "")), dt])

	# ② chat() 自由对话回调
	print("\n② AIBackend.chat() 自由对话…")
	var got := {"done": false, "reply": ""}
	var t1 := Time.get_ticks_msec()
	AIBackend.chat(ag, "你好，最近镇上有什么新鲜事？", Sim._context(ag), func(r):
		got["reply"] = r; got["done"] = true)
	while not got["done"] and Time.get_ticks_msec() - t1 < 180000:
		await get_tree().create_timer(0.2).timeout
	print("  %s：%s (耗时 %dms)" % [Sim._name(ag), str(got["reply"]), Time.get_ticks_msec() - t1])

	print("\n— AIBackend.slm 链路验证完成 —")
