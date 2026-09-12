extends SceneTree
## bench/cohort_over_time.gd — 诊断真机谜题：LOD cohort 是否随【游戏时长】涨向 N（=克隆镇过度社交把 LOD 打废）？
## 每天报 cohort% / option!=null%(主导 salience 项) / cand/day。若两者随天数涨 → 克隆过度社交坐实、LOD 是稀疏镇才灵。
## 用法：--script res://bench/cohort_over_time.gd -- [N] [days] [seed]
const SimScript = preload("res://scripts/Sim.gd")

func _init():
	var a := OS.get_cmdline_user_args()
	var N := int(a[0]) if a.size() > 0 else 200
	var days := int(a[1]) if a.size() > 1 else 10
	var seed := int(a[2]) if a.size() > 2 else 7
	var S = SimScript.new(); get_root().add_child(S)
	S._load_data(); S.auto_run = false; S.backend = null
	S.spawn_count = N; S.lod_aggregate = true; S.decide_period = 4
	S.start_new(seed)
	var TPD: int = int(S.TICKS_PER_DAY)
	var n: int = S.agents.size()
	print("=== LOD cohort 随游戏时长  N=%d agents=%d days=%d seed=%d ===" % [N, n, days, seed])
	print("  day | cohort%% | option!=null%% | cand/day | 活冲突")
	var last_cand := 0
	for d in range(days):
		var sum_cohort := 0.0; var sum_opt := 0.0
		for t in range(TPD):
			S.tick()
			sum_cohort += float(S._near_set.size())
			var opt := 0
			for ag in S.agents:
				if ag.get("option") != null: opt += 1
			sum_opt += float(opt)
		var cand_day: int = int(S.cand_calls) - last_cand; last_cand = int(S.cand_calls)
		var cf := 0
		for c in S.conflicts:
			if String(c.get("status", "")) in ["simmering", "escalated", "confronted", "lingering"]: cf += 1
		print("  %3d | %5.0f%% | %8.0f%% | %7d | %d" % [d + 1, 100.0*sum_cohort/TPD/n, 100.0*sum_opt/TPD/n, cand_day, cf])
	quit()
