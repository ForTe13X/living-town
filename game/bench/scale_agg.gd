extends SceneTree
## 隔离【激进 LOD】(出货路径) 的规模天花板：只跑 agg 配置(远端聚合，成本≈O(near-cap) 非 O(N))，N 可到数百。
## 报告：饿穿累计 / 硬不变量失败 / cand_calls / wall。用法：--script res://bench/scale_agg.gd -- [seeds "1-2"] [N] [days]
const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

func _parse(s: String) -> Array:
	if "-" in s:
		var ab := s.split("-"); var o := []
		for i in range(int(ab[0]), int(ab[1]) + 1): o.append(i)
		return o
	return [int(s)]

func _init():
	var a := OS.get_cmdline_user_args()
	var seeds := _parse(a[0]) if a.size() > 0 else [1, 2]
	var N := int(a[1]) if a.size() > 1 else 200
	var days := int(a[2]) if a.size() > 2 else 30
	var t0 := Time.get_ticks_msec()   # 仅 bench 计时(墙钟)，sim 决策逻辑不触碰 → 不破确定性
	var hard_fail := 0; var starv_tot := 0; var cand_sum := 0; var agents_n := 0
	for sd in seeds:
		var S = SimScript.new(); get_root().add_child(S)
		S._load_data(); S.auto_run = false; S.backend = null
		S.spawn_count = N; S.decide_period = 4; S.lod_near_radius = 8; S.lod_near_cap = 12; S.lod_aggregate = true
		S.start_new(sd)
		var starved := 0
		for t in range(days * int(S.TICKS_PER_DAY)):
			S.tick()
			for ag in S.agents:
				for nid in ag["needs"]:
					if float(ag["needs"][nid]) <= 0.5: starved += 1
		var sf: Dictionary = Inv.split_fails(S, starved)
		hard_fail += int(sf["hard"]); starv_tot += starved; cand_sum += int(S.cand_calls); agents_n = S.agents.size()
		print("  seed %d N=%d agents=%d: starve=%d hard_fail=%d cand=%d digest=%d" % [sd, N, S.agents.size(), starved, int(sf["hard"]), int(S.cand_calls), int(Inv.digest(S))])
		get_root().remove_child(S); S.free()
	var wall := (Time.get_ticks_msec() - t0) / 1000.0
	print("=== 激进 LOD  N=%d agents=%d × %d seeds × %dd: hard_fails=%d starve_tot=%d cand_avg=%d  %.1fs ===" % [
		N, agents_n, seeds.size(), days, hard_fail, starv_tot, cand_sum / maxi(1, seeds.size()), wall])
	quit()
