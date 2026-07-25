extends SceneTree
## bench/DetGate.gd — 场景确定性门（docs/17 早就开的方子，一直没建）。
## 用法：godot --headless --path game --script res://bench/DetGate.gd [-- --seeds 1-4 --days 20 [--golden <path>] [--bake-golden <path>]]
##
## 为什么必须单独有这一门（不是 Harness 的重复）：
##   1) Invariants.gd:15/18 对【任何非空 scenario】豁免硬不变量 #1「无饿穿」
##      （var harmony := String(S.scenario) == ""）——也就是说定向场景走的是另一条断言路径；
##   2) Harness 根本没有 --scenario 开关 → 内置的 faction / betray / freerider 三条场景
##      在 CI 里跑过的次数是【0】。它们是 S3 派系/背叛/搭便车三套机制唯一的定向压力测试，
##      却从来没有任何自动化证据说它们还是确定的、还是良构的。
##   3) 场景改写开局关系/秘密种子 → 走的是 Sim 里与默认沙盘不同的分支，
##      默认网格的金标锚不到这些分支。
##
## 每条 track（默认 "" / faction / betray / freerider）× 每个 seed 断言三件事：
##   A. 所有【硬】不变量绿（软/诊断只报告——定向场景本就会扭曲涌现统计，Invariants 已按 harmony 豁免）
##   B. 同 seed 两跑：Inv.digest 与 Sim.event_digest 双路都一致（真确定性，不是「跑了没崩」）
##   C. 若 golden_digests.json 里有 scenarios 段 → 跨进程比对（同 Harness 的 L3 锚）
## exit 0/1。

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")
const H = preload("res://bench/Harness.gd")            # 复用金标读写/路径规整（reuse-first）
const SimExt = preload("res://scripts/SimExtensions.gd")
const DataScen = preload("res://scripts/DataScenarioProvider.gd")

const TRACKS := ["", "faction", "betray", "freerider"]
const GOLDEN_DEFAULT := "res://bench/golden_digests.json"

func _init() -> void:
	var seeds := _parse_seeds("1-4")
	var seeds_spec := "1-4"
	var days := 20
	var golden_path := GOLDEN_DEFAULT     # 有就比，没有就跳过（不误红）
	var bake_path := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds_spec = args[i + 1]; seeds = _parse_seeds(seeds_spec)
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])
		elif args[i] == "--golden" and i + 1 < args.size():
			golden_path = H.norm_path(args[i + 1])
		elif args[i] == "--bake-golden" and i + 1 < args.size():
			bake_path = H.norm_path(args[i + 1])

	print("=== DetGate · 场景确定性门  tracks=%s seeds=%s days=%d ===" % [str(TRACKS), seeds_spec, days])
	var doc := H.load_golden(golden_path)
	var gold: Dictionary = doc.get("scenarios", {})
	var have_gold := not gold.is_empty()
	if have_gold:
		print("  金标：%s（烘于 godot %s）" % [golden_path, String((doc.get("_meta", {}) as Dictionary).get("godot", "?"))])
	else:
		print("  金标：%s 无 scenarios 段 → 本跑只做 A/B（同 seed 两跑一致）" % golden_path)

	var red := false
	var baked := {}
	var n_hard_ok := 0
	var n_det_ok := 0
	var n_gold_ok := 0
	var n_gold_cmp := 0
	var total := 0
	for track in TRACKS:
		var label: String = track if track != "" else "(default)"
		var tbake := {}
		for sd in seeds:
			total += 1
			var r1 := _run(track, sd, days)
			var checks: Array = Inv.check_all(r1["S"], int(r1["starved"]))
			var hard_fails: Array = []
			for c in checks:
				if bool(c["ok"]): continue
				if int(c["id"]) in Inv.DIAG_IDS: continue      # 诊断档永不成门（#15，见 docs/31）
				if bool(c.get("hard", false)):
					hard_fails.append("#%d %s — %s" % [int(c["id"]), String(c["name"]), String(c["detail"])])
			var d1: int = Inv.digest(r1["S"])
			var e1: int = r1["S"].event_digest
			var nev: int = r1["S"].event_log.size()
			_dispose(r1["S"])

			var r2 := _run(track, sd, days)                    # 同 seed 二跑 → 真确定性
			var d2: int = Inv.digest(r2["S"])
			var e2: int = r2["S"].event_digest
			_dispose(r2["S"])
			var det_ok: bool = (d1 == d2) and (e1 == e2)

			var gold_mark := "—"
			if have_gold and (gold.get(_gkey(track), {}) as Dictionary).has(str(sd)):
				var row: Dictionary = (gold[_gkey(track)] as Dictionary)[str(sd)]
				if int(row.get("days", -1)) == days:
					n_gold_cmp += 1
					if String(row.get("digest", "")) == str(d1) and String(row.get("event_digest", "")) == str(e1):
						gold_mark = "✅"; n_gold_ok += 1
					else:
						gold_mark = "❌ 期望 %s/%s 实得 %s/%s" % [String(row.get("digest", "")), String(row.get("event_digest", "")), str(d1), str(e1)]
						red = true
			if hard_fails.is_empty(): n_hard_ok += 1
			else: red = true
			if det_ok: n_det_ok += 1
			else: red = true

			print("  [%s] seed=%d 事件=%-5d 硬=%s 确定=%s 金标=%s" % [
				label, sd, nev,
				"✅" if hard_fails.is_empty() else ("❌ " + "; ".join(hard_fails)),
				"✅" if det_ok else "❌ digest %d/%d vs %d/%d" % [d1, e1, d2, e2],
				gold_mark])
			tbake[str(sd)] = {"digest": str(d1), "event_digest": str(e1), "days": days, "events": nev}
		baked[_gkey(track)] = tbake

	if bake_path != "":
		var out := H.load_golden(bake_path)
		out["scenarios"] = baked
		var m: Dictionary = out.get("_meta", {})
		m["scenarios_baked_by"] = "godot --headless --path game --script res://bench/DetGate.gd -- --seeds %s --days %d --bake-golden game/bench/golden_digests.json" % [seeds_spec, days]
		m["scenarios_godot"] = H.godot_version()
		out["_meta"] = m
		if H.save_golden(bake_path, out):
			print("\n🔨 已烘 %d 条 track × %d seed 到 %s 的 scenarios 段" % [TRACKS.size(), seeds.size(), bake_path])
		else:
			print("\n❌ 金标写入失败：%s" % bake_path); red = true

	print("\n=== DetGate: %s  (硬不变量 %d/%d, 同seed两跑一致 %d/%d, 金标 %d/%d 可比) ===" % [
		"PASS ✅" if not red else "FAIL ❌", n_hard_ok, total, n_det_ok, total, n_gold_ok, n_gold_cmp])
	quit(0 if not red else 1)

static func _gkey(track: String) -> String:
	return track if track != "" else "default"

## 跑一局定向场景。scenario 必须在 start_new 之前赋值（start_new 内部才调 _seed_scenario）——同 sim_soak.gd:49/61。
func _run(scen: String, seed: int, days: int) -> Dictionary:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null                 # 红线#2：零模型 logic 底座
	S.scenario = scen
	# L7：data/scenarios/<id>.json 存在则走数据驱动 provider（同 sim_soak.gd:51-55）；
	# 内置的 faction/betray/freerider 没有 json → 本分支不触发，走 Sim._seed_scenario 内置分支。
	if scen != "" and FileAccess.file_exists("res://data/scenarios/%s.json" % scen):
		var ext = SimExt.new()
		ext.register_scenario(DataScen.new(scen))
		ext.freeze()
		S.ext = ext
	S.start_new(seed)
	var total: int = days * int(S.TICKS_PER_DAY)
	var starved := 0
	for t in range(total):
		S.tick()
		for ag in S.agents:
			for nid in ag["needs"]:
				if float(ag["needs"][nid]) <= 0.5:
					starved += 1
	return {"S": S, "starved": starved}

func _dispose(S) -> void:
	get_root().remove_child(S)
	S.free()

func _parse_seeds(spec: String) -> Array:
	var out: Array = []
	if "-" in spec:
		var ab := spec.split("-")
		for s in range(int(ab[0]), int(ab[1]) + 1):
			out.append(s)
	elif "," in spec:
		for s in spec.split(","):
			out.append(int(s))
	else:
		out.append(int(spec))
	return out
