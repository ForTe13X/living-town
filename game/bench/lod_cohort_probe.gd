extends SceneTree
## bench/lod_cohort_probe.gd — V5 诚实成本 + V6 liveness floor / cohort 组成。
## 观察无关 aggregate LOD 下每 tick 读 _near_set 尺寸 → 报 cohort 大小(成本代理)、以及【每 agent 是否 span 内必满帧一次】(无永久冻结)。
## 与全量 sim(lod_aggregate=false)对比 cand_calls，如实报 constant-factor（NARROW 指标：只数候选枚举，不含夜间 O(N²)/寻路/渲染）。
## 用法：--script res://bench/lod_cohort_probe.gd -- [N] [days] [seed] [nofull]
const SimScript = preload("res://scripts/Sim.gd")

func _mk(N: int, agg: bool) -> Object:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data(); S.auto_run = false; S.backend = null
	S.spawn_count = N
	S.lod_aggregate = agg
	S.decide_period = 4
	return S

func _init():
	var a := OS.get_cmdline_user_args()
	var N := int(a[0]) if a.size() > 0 else 100
	var days := int(a[1]) if a.size() > 1 else 6
	var seed := int(a[2]) if a.size() > 2 else 7
	var skip_full := a.size() > 3 and String(a[3]) == "nofull"   # 跳过全量基线（大 N 全量 sim 很慢；只看 cohort 组成时用）

	# ── 观察无关 aggregate LOD：逐 tick 采 cohort 尺寸 + liveness ──
	var S := _mk(N, true); S.start_new(seed)
	var total: int = days * int(S.TICKS_PER_DAY)
	var span: int = int(S.lod_rotate_span)
	var sum_full := 0.0
	var last_full := {}          # id -> 最近满帧 tick
	var max_gap := 0             # 全程任一 agent 距上次满帧的最大间隔（应 ≤ span → 无永久冻结）
	var never_full := {}         # 从未满帧过的 id（应为空）
	for ag in S.agents: never_full[ag["id"]] = true
	for t in range(total):
		S.tick()
		sum_full += float(S._near_set.size())
		for id in S._near_set:
			never_full.erase(id)
			if last_full.has(id):
				max_gap = maxi(max_gap, t - int(last_full[id]))
			last_full[id] = t
	for id in last_full:
		max_gap = maxi(max_gap, (total - 1) - int(last_full[id]))
	var agg_cand: int = int(S.cand_calls)
	var n: int = S.agents.size()
	var ticks := float(total)
	S.free()

	# ── 全量 sim 基线（成本对照；可跳过）──
	var full_cand := -1
	if not skip_full:
		var full := _mk(N, false); full.start_new(seed)
		for t in range(total): full.tick()
		full_cand = int(full.cand_calls)
		full.free()

	print("=== LOD cohort 探针  N=%d agents=%d days=%d seed=%d span=%d ===" % [N, n, days, seed, span])
	print("— V6 liveness / cohort 组成（每 tick 均值）—")
	print("  满帧 cohort 大小: %.1f / %d  (%.0f%%)  → cheap(廉价)≈%.1f" % [sum_full/ticks, n, 100.0*sum_full/ticks/n, n - sum_full/ticks])
	print("  从未满帧的 agent 数: %d  (应=0：轮转保证每 id 每 span tick 满帧一次)" % never_full.size())
	# 纯轮转(全程 idle)的 agent 恰每 span tick 满帧一次 → 最坏间隔=span，故 floor 判据是 ≤ span（非 < span）。
	print("  最大满帧间隔: %d tick  (应 ≤ span=%d → 每 agent span 内必满帧一次，无永久冻结/死环)  → %s" % [max_gap, span, "✅" if max_gap <= span else "❌"])
	print("— V5 诚实成本（cand_calls 累计，%d ticks）—" % total)
	if full_cand < 0:
		print("  (跳过全量基线)  观察无关 LOD cand=%d" % agg_cand)
	else:
		print("  全量 sim: %d   观察无关 LOD: %d   → 省 %.0f%%（NARROW：仅候选枚举，【不】含夜间 O(N²)/寻路/渲染；数千 NPC 需正交空间分桶，超范围）" % [
			full_cand, agg_cand, 100.0*(1.0 - float(agg_cand)/maxf(1.0, full_cand))])
	quit(0 if (never_full.size() == 0 and max_gap <= span) else 1)
