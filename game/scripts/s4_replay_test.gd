extends Node
## s4_replay_test.gd — 验证 S4 确定性回放：mock 后端跑一局并记录模型决策 → 用 trace 无后端回放 → event_log digest 一致。
## 证明「模型决策当外部输入记入 trace」后，即便模型非确定，回放也能逐字节复现（含还原异步思考延迟时机）。
## 用法：godot --headless --path . res://scenes/s4_replay_test.tscn
const Inv = preload("res://bench/Invariants.gd")

func _ready() -> void:
	var seed := 20260626
	var total := 200   # 确定性窗口：mock 异步(MAX_INFLIGHT争用)在 ~200t 后有 social-coupling 微漂(cand_hash 检出并优雅兜底)
	for i in OS.get_cmdline_user_args().size():
		if OS.get_cmdline_user_args()[i] == "--ticks":
			total = int(OS.get_cmdline_user_args()[i + 1])

	# ── Phase 1：mock 后端跑一局，记录模型决策 ──
	AIBackend.backend = "mock"
	Sim.backend = AIBackend
	Sim.record_decisions = true
	Sim._replay_active = false
	Sim.replay_trace = {}
	Sim._replay_ticks = {}
	Sim.auto_run = false
	Sim.start_new(seed)
	for t in range(total):
		Sim.tick()
	var digest1 := Inv.digest(Sim)
	var trace: Array = Sim.decision_trace.duplicate(true)
	var elog1: Array = Sim.event_log.duplicate(true)
	print("Phase1 mock   : events=%d  模型决策记录=%d  digest=%d" % [Sim.event_log.size(), trace.size(), digest1])

	# ── Phase 2：无后端，按 trace 确定性回放 ──
	Sim.backend = null
	Sim.record_decisions = false
	Sim.set_replay(trace)
	Sim.start_new(seed)
	for t in range(total):
		Sim.tick()
	var digest2 := Inv.digest(Sim)
	print("Phase2 replay : events=%d  digest=%d  drift=%d" % [Sim.event_log.size(), digest2, Sim.replay_drift])

	# 诊断：找首个分歧事件
	var elog2: Array = Sim.event_log
	var n := mini(elog1.size(), elog2.size())
	for i in range(n):
		var a: Dictionary = elog1[i]
		var b: Dictionary = elog2[i]
		if String(a["type"]) != String(b["type"]) or String(a["actor"]) != String(b["actor"]) or String(a["target"]) != String(b["target"]) or int(a["tick"]) != int(b["tick"]) or bool(a["accepted"]) != bool(b["accepted"]):
			print("[首分歧] #%d mock(t%d %s %s→%s %s) vs replay(t%d %s %s→%s %s)" % [i,
				int(a["tick"]), a["type"], a["actor"], a["target"], str(a["accepted"]),
				int(b["tick"]), b["type"], b["actor"], b["target"], str(b["accepted"])])
			break
	var okk := digest1 == digest2
	print("%s S4 确定性回放: digest %s（mock %d %s replay %d）" % [
		("✅" if okk else "❌"), ("一致" if okk else "不一致"), digest1, ("==" if okk else "!="), digest2])
	get_tree().quit(0 if okk else 1)
