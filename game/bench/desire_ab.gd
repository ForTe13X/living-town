extends SceneTree
## 欲望 v0 的 A/B（docs/187 §五/§六）：同 seed 同 N，只换 desire_cfg ⇒ 差异纯归因于欲望。
## 用法：godot --headless --path game --script res://bench/desire_ab.gd -- --arm off|on [--bonus 8] [--seeds 1-12] [--days 10] [--n 12]
## 输出：逐 seed 一行 `DESIRE_AB_SEED {...}`（供配对差值）+ 末行 `DESIRE_AB {...}`（均值）。
##
## §六 指标，两类：
##   花样（想要它涨）：social_entropy / variety / event_types / event_entropy / greet_share / deep_share
##   代价（要它不坏）：need_floor / starved / conflicts / completion / dangling / drama_per_day /
##                     target_top_share（被欲望指向最多的一人占有对象者的比例，查模仿滚雪球）/
##                     chain_len（同一 actor 连续深层动作指向同一人的平均链长，查"花样是乱还是戏"）/ ms_per_tick
const SimScript = preload("res://scripts/Sim.gd")
const DEEP := ["give", "invite", "confide"]

func _arg(name: String, dflt: String) -> String:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == name and i + 1 < a.size(): return a[i + 1]
	return dflt

func _seeds(s: String) -> Array:
	var out := []
	if "-" in s:
		var p := s.split("-")
		for v in range(int(p[0]), int(p[1]) + 1): out.append(v)
		return out
	return [int(s)]

func _entropy(counts: Dictionary) -> float:
	var tot := 0.0
	for k in counts: tot += float(counts[k])
	var h := 0.0
	for k in counts:
		var p := float(counts[k]) / maxf(1.0, tot)
		if p > 0.0: h -= p * (log(p) / log(2.0))
	return h

func _init() -> void:
	var arm := _arg("--arm", "off")
	var bonus := float(_arg("--bonus", "8"))
	var seeds := _seeds(_arg("--seeds", "1-12"))
	var days := int(_arg("--days", "10"))
	var n := int(_arg("--n", "12"))
	var acc := {}
	for seed in seeds:
		var S = SimScript.new(); get_root().add_child(S)
		S._load_data()                                      # SceneTree._init 里 _ready 不会触发（同 ab_metrics）
		S.auto_run = false; S.backend = null
		if n > 12: S.spawn_count = n
		S.desire_cfg = {"enabled": true, "gain": 0.15, "mimetic_cap": 5.0, "bonus_k": bonus} if arm == "on" else {}
		if arm == "on" and _arg("--rho", "") != "": S.desire_cfg["rho"] = float(_arg("--rho", "0"))     # 步骤 4：缺键=满足逻辑不跑
		if arm == "on" and _arg("--rmax", "") != "": S.desire_cfg["r_max"] = int(_arg("--rmax", "0"))   # 步骤 4：缺键=放弃逻辑不跑
		if arm == "on" and _arg("--crowd", "") != "": S.desire_cfg["crowd_k"] = float(_arg("--crowd", "0"))  # 拥挤项：缺键=不降权
		if arm == "on" and _arg("--minseen", "") != "": S.desire_cfg["min_seen"] = int(_arg("--minseen", "0"))  # 首选前的最少证据
		if arm == "on" and _arg("--margin", "") != "": S.desire_cfg["switch_margin"] = float(_arg("--margin", "0"))  # 满足后重估的换人门槛
		var prev_t := {}                                    # 日末采样：aid -> 上一日的 target（换手率）
		var changes := 0
		var holder_days := 0
		var holder_share_acc := 0.0
		S.start_new(seed)
		var TPD: int = S.TICKS_PER_DAY
		var need_floor := 100.0
		var tgt_top := 0.0
		var samples := 0
		var t0 := Time.get_ticks_msec()
		for t in range(days * TPD):
			S.tick()
			for ag in S.agents:
				for nid in ag["needs"]:
					need_floor = minf(need_floor, float(ag["needs"][nid]))
			if arm == "on" and t % TPD == TPD - 1:          # 每日末采样一次对象集中度
				var cnt := {}
				var holders := 0
				for ag in S.agents:
					var d = ag.get("desire")
					if d != null and String(d["kind"]) == "person":
						holders += 1
						cnt[d["target"]] = int(cnt.get(d["target"], 0)) + 1
						holder_days += 1
						var aid := String(ag["id"])
						if prev_t.has(aid) and String(prev_t[aid]) != String(d["target"]):
							changes += 1
						prev_t[aid] = String(d["target"])
				holder_share_acc += float(holders) / maxf(1.0, float(S.agents.size()))   # 有 person 对象的居民占比（查"释放后找不到新对象"的饥饿）
				var top := 0
				for k in cnt: top = maxi(top, int(cnt[k]))
				if holders > 0:
					tgt_top += float(top) / float(holders); samples += 1
		var ms := float(Time.get_ticks_msec() - t0) / float(days * TPD)
		# 事件 → 花样
		var types := {}
		var soc := {}
		var per_actor := {}
		var deep_seq := {}                                  # actor -> [partner...]（被接受的深层动作，时间序）
		for e in S.event_log:
			var ty := String(e.get("type", ""))
			types[ty] = int(types.get(ty, 0)) + 1
			if ty in S.KNOWN_SOCIAL_ACTIONS or ty in ["confront", "apologize", "rally_oust"]:
				soc[ty] = int(soc.get(ty, 0)) + 1
				var a := String(e.get("actor", ""))
				if not per_actor.has(a): per_actor[a] = {}
				per_actor[a][ty] = true
				if ty in DEEP and bool(e.get("accepted", false)):
					if not deep_seq.has(a): deep_seq[a] = []
					deep_seq[a].append(String(e.get("target", "")))
		var soc_tot := 0
		for k in soc: soc_tot += int(soc[k])
		var deep_n := 0
		for k in DEEP: deep_n += int(soc.get(k, 0))
		var var_sum := 0.0
		for a in per_actor: var_sum += float((per_actor[a] as Dictionary).size())
		var runs := 0; var run_len := 0
		for a in deep_seq:
			var seq: Array = deep_seq[a]
			var i := 0
			while i < seq.size():
				var j := i
				while j + 1 < seq.size() and seq[j + 1] == seq[i]: j += 1
				runs += 1; run_len += j - i + 1
				i = j + 1
		# 冲突（口径同 ab_metrics）
		var repaired := 0; var faded := 0
		for c in S.conflicts:
			var st := String(c.get("status", ""))
			if st == "repaired": repaired += 1
			if st == "faded": faded += 1
		var nconf: int = S.conflicts.size()
		var drama := int(types.get("confront", 0)) + int(types.get("betray", 0)) + int(types.get("rally_oust", 0))
		var rec := {
			"seed": seed,
			"social_entropy": _entropy(soc), "variety": var_sum / maxf(1.0, float(per_actor.size())),
			"event_types": types.size(), "event_entropy": _entropy(types),
			"greet_share": float(soc.get("greet", 0)) / maxf(1.0, float(soc_tot)),
			"deep_share": float(deep_n) / maxf(1.0, float(soc_tot)),
			"social_per_day": float(soc_tot) / float(days),
			"need_floor": need_floor, "starved": 1.0 if need_floor <= S.STARVE_NEED else 0.0,
			"conflicts": nconf, "completion": (float(repaired + faded) / nconf) if nconf > 0 else 1.0,
			"dangling": float(nconf - repaired - faded), "drama_per_day": float(drama) / float(days),
			"target_top_share": tgt_top / maxf(1.0, float(samples)),
			"chain_len": float(run_len) / maxf(1.0, float(runs)),
			"holder_share": holder_share_acc / float(days) if arm == "on" else 0.0,
			"churn_per_week": 7.0 * float(changes) / maxf(1.0, float(holder_days)),   # 持对象者每周换对象次数（日末采样，低估日内多换）
			"ms_per_tick": ms,
		}
		print("DESIRE_AB_SEED " + JSON.stringify({"arm": arm, "n": n}.merged(rec)))
		for k in rec:
			if k == "seed": continue
			if not acc.has(k): acc[k] = 0.0
			acc[k] += float(rec[k])
		get_root().remove_child(S); S.free()
	var out := {"arm": arm, "bonus": bonus, "n": n, "n_seeds": seeds.size(), "days": days}
	for k in acc: out[k] = snappedf(float(acc[k]) / seeds.size(), 0.0001)
	print("DESIRE_AB " + JSON.stringify(out))
	quit()
