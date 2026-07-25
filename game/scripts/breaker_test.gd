extends Node
## breaker_test.gd — 熔断器(docs/34)确定性验证：无需模型/网络/NobodyWho，纯驱动 AIBackend 状态与 decide() 真路径。
## 覆盖：
##   ① 连续 N 次失败 → 熔断 → backend/backend_requested 钉死 logic、原因正确
##   ② 一次成功清零连败（不误熔断）
##   ③ 三条显式复位路径都能重新武装：reset_stats / request_backend / set_model_path
##   ④ decide() 的【超时分支】端到端喂熔断（注入过期 pending，走真正的 timeout→_note_ai_fail→trip）
##   ⑤ 熔断后 decide() 走 logic 地板（非 _wait、非空）且不再 fire 新请求（红线：无模型也能玩）
## 用法：godot --headless --path game res://scenes/breaker_test.tscn

var _fail := 0
var _pass := 0

func _ready() -> void:
	Sim.start_new(20260725)
	print("=== 熔断器验证（无模型，确定性）===")
	var ag: Dictionary = Sim.get_agent("aria")
	if ag.is_empty():
		ag = Sim.agents[0]
	var cands: Array = Sim.agent_candidates(ag)
	var N: int = AIBackend.BREAKER_MAX_FAILS
	print("BREAKER_MAX_FAILS = %d" % N)

	# ① 连续 N 次失败 → 熔断
	AIBackend.backend = "slm"; AIBackend.backend_requested = "slm"
	AIBackend.reset_stats()
	_check("reset 后未熔断", not AIBackend.breaker_tripped)
	for i in N - 1:
		AIBackend._note_ai_fail("timeout")
	_check("N-1 次失败仍未熔断", not AIBackend.breaker_tripped)
	_check("N-1 次后 backend 仍 slm", AIBackend.backend == "slm")
	AIBackend._note_ai_fail("timeout")                    # 第 N 次 → 触发
	_check("第 N 次失败 → 熔断", AIBackend.breaker_tripped)
	_check("熔断后 backend 钉 logic", AIBackend.backend == "logic")
	_check("熔断后 backend_requested 钉 logic", AIBackend.backend_requested == "logic")
	_check("熔断原因 = timeout", AIBackend.breaker_reason == "timeout")

	# ② 一次成功清零连败
	AIBackend.backend = "slm"; AIBackend.backend_requested = "slm"
	AIBackend.reset_stats()
	for i in N - 1:
		AIBackend._note_ai_fail("timeout")
	AIBackend._note_ai_ok()
	_check("一次成功后连败清零", AIBackend._consec_fail == 0)
	for i in N - 1:
		AIBackend._note_ai_fail("timeout")
	_check("清零后再攒 N-1 次仍未熔断（证明确是连续计数）", not AIBackend.breaker_tripped)

	# ③ 三条复位路径
	AIBackend.backend = "slm"; AIBackend.backend_requested = "slm"; AIBackend.reset_stats(); _trip_now()
	AIBackend.reset_stats()
	_check("reset_stats 复位熔断", not AIBackend.breaker_tripped and AIBackend._consec_fail == 0)

	AIBackend.backend = "slm"; AIBackend.backend_requested = "slm"; AIBackend.reset_stats(); _trip_now()
	AIBackend.request_backend("mock")                     # mock 在无 NobodyWho 的桌面也在 available_backends
	_check("request_backend(用户切档) 复位熔断", not AIBackend.breaker_tripped)

	AIBackend.backend = "slm"; AIBackend.backend_requested = "slm"; AIBackend.reset_stats(); _trip_now()
	AIBackend.set_model_path("res://models/__nonexistent__.gguf")
	_check("set_model_path(换模型) 复位熔断", not AIBackend.breaker_tripped)

	# ④ decide() 超时分支端到端喂熔断（注入过期 pending → 真的走 timeout 记账）
	AIBackend.backend = "logic"; AIBackend.backend_requested = "logic"; AIBackend.reset_stats()
	AIBackend.backend = "slm"; AIBackend.backend_requested = "slm"
	var fired_before: int = int(AIBackend.stats["fired"])
	for i in N:
		_inject_expired_pending(ag)
		AIBackend.decide(ag, cands, Sim._context(ag))     # 命中 due_ms 过期 → timeout → _note_ai_fail
	_check("decide() 超时路径端到端 → 熔断", AIBackend.breaker_tripped)
	_check("端到端熔断后 backend logic", AIBackend.backend == "logic")
	_check("熔断过程未 fire 任何真请求", int(AIBackend.stats["fired"]) == fired_before)

	# ⑤ 熔断后 decide() 走 logic 地板、不再 fire
	var r2: Dictionary = AIBackend.decide(ag, cands, Sim._context(ag))
	_check("熔断后 decide 走 logic（非 _wait）", not r2.has("_wait"))
	_check("熔断后 decide 返回具体 intent（非空）", not r2.is_empty())
	var fired2: int = int(AIBackend.stats["fired"])
	AIBackend.decide(ag, cands, Sim._context(ag))
	_check("熔断后 decide 持续不 fire", int(AIBackend.stats["fired"]) == fired2)

	print("\n结果：通过 %d · 失败 %d" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)

## 直接把连败打到阈值（测复位用）。
func _trip_now() -> void:
	for i in AIBackend.BREAKER_MAX_FAILS:
		AIBackend._note_ai_fail("timeout")

## 注入一条【已过截止线、worker 未返回】的在飞请求 → 下一次 decide 命中 timeout 分支（模拟挂死）。
func _inject_expired_pending(ag: Dictionary) -> void:
	var id := String(ag["id"])
	AIBackend._inflight = 1
	AIBackend._pending[id] = {
		"epoch": AIBackend.world_epoch, "req_id": 1, "prompt_tick": Sim.tick_no,
		"snapshot": [], "due_ms": Time.get_ticks_msec() - 1, "ready": Sim.tick_no,
		"raw": "", "has": false, "http": null, "slm_chat": null}

func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ %s" % label)
	else:
		_fail += 1
		print("  ❌ %s" % label)
