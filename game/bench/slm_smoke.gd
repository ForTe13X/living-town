extends SceneTree
## bench/slm_smoke.gd — 最小 SLM 推理冒烟：加载 gguf → 起 chat worker → ask → 看 response_finished 是否返回（还是挂死）。
## 隔离 NobodyWho 集成本身，避开整个游戏。用于诊断真机"推理全超时 0 成功"是模型/集成问题还是设备/GPU 问题。
## 用法：--script res://bench/slm_smoke.gd -- [gpu=0/1] [model_path]  （默认 CPU + 1.5B）
const DEFAULT_MODEL := "res://models/qwen2.5-1.5b-instruct-q4_k_m.gguf"

var _resp := ""
var _done := false

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var use_gpu := a.size() > 0 and String(a[0]) == "1"
	var mpath := String(a[1]) if a.size() > 1 else DEFAULT_MODEL
	print("[SLM-SMOKE] NobodyWhoModel class exists: %s" % ClassDB.class_exists("NobodyWhoModel"))
	if not ClassDB.class_exists("NobodyWhoModel"):
		print("[SLM-SMOKE] ❌ addon/GDExtension not loaded → SLM 不可用（这本身就是一种失败模式）"); quit(1); return
	print("[SLM-SMOKE] model=%s exists=%s  gpu=%s" % [mpath, FileAccess.file_exists(mpath), use_gpu])
	if not FileAccess.file_exists(mpath):
		print("[SLM-SMOKE] ❌ model file missing"); quit(1); return

	var t_load := Time.get_ticks_msec()
	var model: Object = ClassDB.instantiate("NobodyWhoModel")
	model.set("model_path", mpath)
	model.set("use_gpu_if_available", use_gpu)
	get_root().add_child(model)
	var chat: Object = ClassDB.instantiate("NobodyWhoChat")
	chat.set("model_node", model)
	chat.set("system_prompt", "You reply with exactly one short JSON object and nothing else.")
	if chat.has_method("set") : chat.set("allow_thinking", false)
	get_root().add_child(chat)
	chat.call("start_worker")
	chat.connect("response_finished", func(r): _resp = String(r); _done = true)
	print("[SLM-SMOKE] worker started (%dms). firing ask..." % (Time.get_ticks_msec() - t_load))

	var t0 := Time.get_ticks_msec()
	chat.call("ask", "Pick option index 0 or 1. Reply {\"i\":0}.")
	# 轮询等待 response_finished，30s 超时
	while not _done and (Time.get_ticks_msec() - t0) < 30000:
		await process_frame
	var ms := Time.get_ticks_msec() - t0
	if _done:
		print("[SLM-SMOKE] ✅ response in %dms: %s" % [ms, _resp.substr(0, 200)])
	else:
		print("[SLM-SMOKE] ❌❌ HANG — no response_finished after %dms (30s timeout)。这复现了真机的'挂死'。" % ms)
	quit(0 if _done else 2)
