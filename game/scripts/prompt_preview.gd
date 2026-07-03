extends Node
## scripts/prompt_preview.gd — 预览深化后的 LLM prompt（不联网、纯看文本质量）。scene 模式(autoload 可用)。
## 用法：godot --headless --path . res://scenes/prompt_preview.tscn

func _ready() -> void:
	Sim.backend = null            # 纯 logic 推进，攒出需求/关系/记忆/邻近
	Sim.auto_run = false
	Sim.start_new(20260626)
	for i in 1400:                # ~6 sim-日，攒社会史 + 当下邻近
		Sim.tick()
	print("========== [SYSTEM PROMPT] ==========")
	print(AIBackend._system_prompt())
	for id in ["aria", "ben", "coco", "dan"]:
		var ag = Sim.get_agent(id)
		if ag == null:
			continue
		var cands: Array = Sim.agent_candidates(ag)
		print("\n========== 决策 prompt · %s ==========" % Sim._name(ag))
		print(AIBackend.build_prompt(ag, cands, Sim._context(ag)))
	# 聊天 sys prompt 预览（阿丽）
	var aria = Sim.get_agent("aria")
	if aria != null:
		print("\n========== 玩家对话 · 阿丽（sys 前缀）==========")
		var mm = AIBackend._mood(aria)
		print("此刻%s，你%s。（性格:%s 口吻:%s）" % [AIBackend._phase_zh(Sim.time_of_day()), String(mm[0]), "·".join(aria["persona"].get("traits", [])), aria["persona"].get("style", "")])
	get_tree().quit(0)
