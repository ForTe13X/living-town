extends SceneTree
## bench/x1_margin.gd — X1：`#01` 的**连续余量**尺子（不是红绿计数）。
##
## 为什么必须是连续量：M2 把 `SURVIVAL_GATE` 32→36 那一次在回执里写得很清楚——
## 「真正的证据不是红绿计数（3→0 只有 3 个事件，Fisher p≈0.25，分辨不出），而是**连续余量**」。
## 本棒要判的东西同样稀疏（N=40 上 120 个 seed 才 2 颗红）⇒ 用红绿计数做剂量-响应，
## 量到的一半是抽签。所以本尺子逐 seed 吐四组连续量：
##   ① 五条 need 各自的**全局地板**（所有 agent × 所有 tick 的最小值）；
##   ② **最长触底段**（need ≤ 0.5 的最长连续 tick）及其归属；
##   ③ **最长「social < SURVIVAL_GATE」段**——这是本棒查出来的那个死锁的**停留时长**，
##      也是唯一一个在红之前就开始变坏的量（红只是它长到把 social 拖到 0 的那一次）；
##   ④ 社交事务的**接受/拒绝分账**（逐动作），因为死锁的燃料是被拒次数。
##
## ⚠ 与 `ScaleSupply.gd` 不重复：那一份量的是 `#40` 的供给满足率，`starve_*` 只是顺带；
##   它**不记 need 地板、不记连续段、不记接受/拒绝分账**——而这三样正是本棒要的。
##   判据仍然只有一份实现：本尺子照样调 `Inv.check_all`，红绿由它给，不自立判据。
##
## 用法：godot --headless --path game -s res://bench/x1_margin.gd -- \
##          --agents 40 --seeds 1-12 --days 60 [--out <path.jsonl>]
const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seeds := _parse_seeds("1-12")
	var seeds_spec := "1-12"
	var days := 60
	var n := 0
	var out_path := ""
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds = _parse_seeds(String(args[i + 1])); seeds_spec = String(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size(): days = int(args[i + 1])
		elif args[i] == "--agents" and i + 1 < args.size(): n = int(args[i + 1])
		elif args[i] == "--out" and i + 1 < args.size(): out_path = String(args[i + 1])
	var f: FileAccess = null
	if out_path != "": f = FileAccess.open(out_path, FileAccess.WRITE)
	print("=== X1 margin · agents=%d seeds=%s days=%d ===" % [n, seeds_spec, days])
	var t_all := Time.get_ticks_msec()
	for sd in seeds:
		var t0 := Time.get_ticks_msec()
		var rec := _run_once(sd, days, n)
		rec["wall_ms"] = Time.get_ticks_msec() - t0
		var line := JSON.stringify(rec)
		print("[X1M] " + line)
		if f: f.store_line(line)
	print("=== X1 margin done  总墙钟=%.1fs ===" % ((Time.get_ticks_msec() - t_all) / 1000.0))
	if f: f.close()
	quit(0)

func _run_once(seed: int, days: int, n: int) -> Dictionary:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data(); S.auto_run = false; S.backend = null
	if n > 0: S.spawn_count = n
	S.start_new(seed)
	var tpd: int = int(S.TICKS_PER_DAY)
	var total: int = days * tpd
	var GATE: float = S.SURVIVAL_GATE

	var starved := 0
	var by_need := {}
	var floors := {}            # need -> 全局地板
	var run_last := {}          # "id/need" -> 上次触底 tick
	var run_start := {}
	var run_max := 0
	var run_key := ""
	var starve_agents := {}
	# social < GATE 的连续段（死锁停留时长）
	var lock_last := {}
	var lock_start := {}
	var lock_max := 0
	var lock_key := ""
	var lock_ticks := 0         # 全镇 social<GATE 的 (agent,tick) 总数——同一件事的"面积"
	for t in range(total):
		S.tick()
		for ag in S.agents:
			var aid := String(ag["id"])
			var soc := float(ag["needs"].get("social", 100.0))
			if soc < GATE:
				lock_ticks += 1
				if int(lock_last.get(aid, -2)) != t - 1: lock_start[aid] = t
				lock_last[aid] = t
				var ll: int = t - int(lock_start[aid]) + 1
				if ll > lock_max: lock_max = ll; lock_key = aid
			for nid in ag["needs"]:
				var v := float(ag["needs"][nid])
				var nk := String(nid)
				if not floors.has(nk) or v < float(floors[nk]): floors[nk] = v
				if v <= 0.5:
					starved += 1
					by_need[nk] = int(by_need.get(nk, 0)) + 1
					starve_agents[aid] = true
					var k := aid + "/" + nk
					if int(run_last.get(k, -2)) != t - 1: run_start[k] = t
					run_last[k] = t
					var rl: int = t - int(run_start[k]) + 1
					if rl > run_max: run_max = rl; run_key = k

	# 社交事务的接受/拒绝分账（逐动作）——死锁的燃料
	var acc := {}
	var ref := {}
	for e in S.event_log:
		var ty := String(e.get("type", ""))
		if not (ty in S.KNOWN_SOCIAL_ACTIONS): continue
		if bool(e.get("accepted", true)): acc[ty] = int(acc.get(ty, 0)) + 1
		else: ref[ty] = int(ref.get(ty, 0)) + 1

	var checks: Array = Inv.check_all(S, starved, by_need)
	var hard := []
	var soft := []
	for c in checks:
		if c["ok"]: continue
		if int(c["id"]) in Inv.DIAG_IDS: continue
		if bool(c.get("hard", false)): hard.append(int(c["id"]))
		else: soft.append(int(c["id"]))
	var inv40 := ""
	for c in checks:
		if int(c["id"]) == 40: inv40 = String(c["detail"])

	var rec := {
		"seed": seed, "n_agents": S.agents.size(), "days": days,
		"starved": starved, "by_need": by_need,
		"starve_agents": starve_agents.keys(),
		"floors": floors,
		"max_starve_run": run_max, "max_starve_run_key": run_key,
		"max_soclock_run": lock_max, "max_soclock_key": lock_key,
		"soclock_ticks": lock_ticks,
		"hard_fails": hard, "soft_fails": soft,
		"inv40_detail": inv40,
		"social_acc": acc, "social_ref": ref,
		"digest": str(Inv.digest(S)), "event_digest": str(S.event_digest),
		"events": S.event_log.size(),
	}
	get_root().remove_child(S)
	S.free()
	return rec

func _parse_seeds(spec: String) -> Array:
	var out: Array = []
	if "-" in spec:
		var p := spec.split("-")
		for i in range(int(p[0]), int(p[1]) + 1): out.append(i)
	else:
		out.append(int(spec))
	return out
