extends SceneTree
## bench/total_cost.gd — 【总成本】墙钟对照（Codex 评审：cand_calls 只数候选枚举，太窄；要含夜间 O(N²)/寻路/全部）。
## 只计时 tick 主循环（Time.get_ticks_msec，bench 计时不入 sim 逻辑→不破确定性）。全量 sim vs 观察无关 aggregate LOD。
## 墙钟有噪声+机器相关，但这是【总成本】信号（对比 cand_calls 的窄口径）。用法：--script res://bench/total_cost.gd -- [N] [days] [seed]
const SimScript = preload("res://scripts/Sim.gd")

func _mk(N: int, agg: bool) -> Object:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data(); S.auto_run = false; S.backend = null
	S.spawn_count = N; S.lod_aggregate = agg; S.decide_period = 4
	return S

func _time_run(N: int, agg: bool, seed: int, total: int) -> Dictionary:
	var S := _mk(N, agg); S.start_new(seed)
	# 预热 1 tick（首 tick 常含 lazy 构建，不计入）
	S.tick()
	var t0 := Time.get_ticks_msec()
	for t in range(total - 1): S.tick()
	var ms := Time.get_ticks_msec() - t0
	var res := {"ms": ms, "cand": int(S.cand_calls), "n": S.agents.size()}
	S.free()
	return res

func _init():
	var a := OS.get_cmdline_user_args()
	var N := int(a[0]) if a.size() > 0 else 100
	var days := int(a[1]) if a.size() > 1 else 6
	var seed := int(a[2]) if a.size() > 2 else 7
	var total: int = days * int(SimScript.TICKS_PER_DAY)

	var full := _time_run(N, false, seed, total)
	var agg := _time_run(N, true, seed, total)
	var save_ms := 100.0 * (1.0 - float(agg["ms"]) / maxf(1.0, float(full["ms"])))
	var save_cand := 100.0 * (1.0 - float(agg["cand"]) / maxf(1.0, float(full["cand"])))
	print("=== 总成本墙钟  N=%d agents=%d days=%d seed=%d (%d ticks) ===" % [N, int(full["n"]), days, seed, total])
	print("  全量 sim:       %6d ms   cand=%d" % [int(full["ms"]), int(full["cand"])])
	print("  观察无关 LOD:   %6d ms   cand=%d" % [int(agg["ms"]), int(agg["cand"])])
	print("  → 墙钟总成本省 %.0f%%（含夜间 O(N²)/寻路/全部）  |  cand(窄) 省 %.0f%%" % [save_ms, save_cand])
	quit()
