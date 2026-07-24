extends SceneTree
## bench/Harness.gd — Causal Bench S0：不变量回归门，跨 seed 网格 + 真确定性校验。
## 用法：godot --headless --path . --script res://bench/Harness.gd -- [--suite S0] [--seeds 1-12] [--days 60] [--det 3]
##   --seeds  种子范围 "a-b" 或单值（默认 1-12）          --days  每局天数（默认 60，覆盖 S2 谣言变冷轨迹）
##   --det    抽样 N 个种子做"同 seed 两跑摘要一致"校验（默认 3，0=跳过）
## 输出：每 seed 一行 [S0]{json}（JSONL，便于机读）+ 每不变量跨 seed 通过率表 + 最终红绿门；任一失败 quit(1)。
## 纪律同 sim_soak：--script 不加载 autoload → preload Sim/Invariants 实例化，backend=null 走确定性 logic。

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

var _shadow := false        # --shadow：开 shadow 探针（Sim.shadow_on）——纯观测，digest 应逐字节不变
var _shadow_dump := ""      # --shadow-dump <path>：把每 seed 的 shadow_trace 追加成 JSONL（供反事实 / #15v2 分析）

func _init() -> void:
	var seeds := _parse_seeds("1-12")
	var days := 60
	var det_n := 3
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])
		elif args[i] == "--det" and i + 1 < args.size():
			det_n = int(args[i + 1])
		elif args[i] == "--shadow":
			_shadow = true
		elif args[i] == "--shadow-dump" and i + 1 < args.size():
			_shadow = true; _shadow_dump = args[i + 1]
		elif args[i] == "--suite" and i + 1 < args.size():
			pass  # 目前仅 S0；保留位给 S5
	if _shadow_dump != "":
		var f0 := FileAccess.open(_shadow_dump, FileAccess.WRITE)   # 清空/新建
		if f0: f0.close()

	print("=== Causal Bench S0 · 不变量回归门  seeds=%s days=%d ===" % [str(seeds), days])
	var inv_pass := {}      # id -> 通过的 seed 数
	var inv_name := {}      # id -> 名称
	var inv_fail_eg := {}   # id -> 一个失败样例 "seed N: detail"
	var seed_pass := 0
	var first_run_digest := {}  # seed -> 批量摘要（供确定性校验）
	var first_run_edig := {}    # seed -> 增量滚动摘要（L4，独立见证）

	for sd in seeds:
		var res := _run_once(sd, days)
		var S = res["S"]
		first_run_digest[sd] = Inv.digest(S)
		first_run_edig[sd] = S.event_digest
		var checks: Array = Inv.check_all(S, int(res["starved"]))
		var hard_fails: Array = []
		var soft_fails: Array = []
		for c in checks:
			inv_name[c["id"]] = c["name"]
			if c["ok"]:
				inv_pass[c["id"]] = int(inv_pass.get(c["id"], 0)) + 1
			else:
				if bool(c.get("hard", false)):
					hard_fails.append(int(c["id"]))
				else:
					soft_fails.append(int(c["id"]))
				if not inv_fail_eg.has(c["id"]):
					inv_fail_eg[c["id"]] = "seed %d: %s" % [sd, c["detail"]]
		# L4 两分落到 CI（docs/12 R2）：硬(结构)不变量每 seed 必绿；软(涌现统计)不再单 seed 硬断言,
		# 改为跨种子通过率门(见下)——单 seed 的涌现反转(如节日桥接派系削掉 inv26 的 margin)不再误伤整门。
		if hard_fails.is_empty():
			seed_pass += 1
		# JSONL 机读行
		print("[S0] " + JSON.stringify({"seed": sd, "days": days, "pass": hard_fails.is_empty(),
			"hard_fails": hard_fails, "soft_fails": soft_fails, "events": S.event_log.size(), "digest": first_run_digest[sd]}))
		_dispose(S)

	# ── 确定性校验：抽样种子两跑，摘要必须一致 ──
	var det_seeds: Array = seeds.slice(0, mini(det_n, seeds.size()))
	var det_ok := 0
	var det_fail: Array = []
	for sd in det_seeds:
		var res2 := _run_once(sd, days)
		var d2: int = Inv.digest(res2["S"])
		var e2: int = res2["S"].event_digest
		_dispose(res2["S"])
		# 两路摘要(批量 + 增量滚动)都须一致 → 双独立见证确定性
		if d2 == int(first_run_digest[sd]) and e2 == int(first_run_edig[sd]):
			det_ok += 1
		else:
			det_fail.append(sd)

	# ── 报告：硬=每 seed 必绿；软=跨种子通过率 ≥ (seeds-1)/seeds（允许单 seed 涌现反转，docs/12 R2 处方）──
	print("\n— 不变量跨 seed 通过率（硬=全绿必需 / 软=允许 1 seed 反转）—")
	var hard_red := false
	var soft_red := false
	var soft_min := seeds.size() - 1
	for id in range(1, 38):
		var p := int(inv_pass.get(id, 0))
		var is_hard: bool = id in Inv.HARD_IDS
		var need := seeds.size() if is_hard else soft_min
		var mark := "✅" if p >= need else "❌"
		if p < need:
			if is_hard: hard_red = true
			else: soft_red = true
		var line := "  %s #%02d %s%s  %d/%d" % [mark, id, ("[硬]" if is_hard else "[软]"), String(inv_name.get(id, "?")), p, seeds.size()]
		if inv_fail_eg.has(id):
			line += "   首违 " + String(inv_fail_eg[id])
		print(line)

	print("\n— 确定性 —")
	if det_n <= 0:
		print("  (跳过)")
	elif det_fail.is_empty():
		print("  ✅ 同 seed 两跑摘要一致(批量+增量滚动)  %d/%d" % [det_ok, det_seeds.size()])
	else:
		print("  ❌ 非确定 seeds=%s" % str(det_fail))

	var gate_ok := (seed_pass == seeds.size()) and not hard_red and not soft_red and (det_n <= 0 or det_fail.is_empty())
	print("\n=== S0 GATE: %s  (硬不变量 seed %d/%d 全绿, 软通过率门%s, det %d/%d) ===" % [
		"PASS ✅" if gate_ok else "FAIL ❌", seed_pass, seeds.size(),
		"过" if not soft_red else "破", det_ok, det_seeds.size()])
	quit(0 if gate_ok else 1)

## 跑一局确定性仿真，返回 {S, starved}。S 由调用方 _dispose。
func _run_once(seed: int, days: int) -> Dictionary:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	S.shadow_on = _shadow   # 探针开关（默认 false → 逐字节不变）；set before start_new
	S.start_new(seed)
	var total: int = days * int(S.TICKS_PER_DAY)
	var starved := 0
	for t in range(total):
		S.tick()
		for ag in S.agents:
			for nid in ag["needs"]:
				if float(ag["needs"][nid]) <= 0.5:
					starved += 1
	if _shadow_dump != "":
		_dump_shadow(seed, S.shadow_trace)
	return {"S": S, "starved": starved}

## 把一 seed 的 shadow_trace 追加进 JSONL（每行一条决策，带 seed 前缀）。
func _dump_shadow(seed: int, trace: Array) -> void:
	var f := FileAccess.open(_shadow_dump, FileAccess.READ_WRITE)
	if f == null:
		return
	f.seek_end()
	for rec in trace:
		var r: Dictionary = (rec as Dictionary).duplicate()
		r["seed"] = seed
		f.store_line(JSON.stringify(r))
	f.close()

func _dispose(S) -> void:
	get_root().remove_child(S)
	S.free()

func _parse_seeds(spec: String) -> Array:
	var out: Array = []
	if "-" in spec:
		var ab := spec.split("-")
		var a := int(ab[0])
		var b := int(ab[1])
		for s in range(a, b + 1):
			out.append(s)
	elif "," in spec:
		for s in spec.split(","):
			out.append(int(s))
	else:
		out.append(int(spec))
	return out
