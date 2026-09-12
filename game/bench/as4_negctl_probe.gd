extends SceneTree
## bench/as4_negctl_probe.gd — 车道 E2a 负对照：证 #34/#45/#35 各有判别力（对称 E1 的 #38/#44 负对照）。
##
## 每个负对照跑一份【全新】Sim 到 T，施加一处最小扰动，再 Inv.check_all，报出目标不变量是否变红。
##   ① CLEAN     ：不扰动 ⇒ #34/#45/#35 全绿（基线）。
##   ② NEG_34    ：直接 town_coin−=D（漏贷 external：扣了 town 没贷 external）⇒ money_total 掉 ⇒ #34 红、#45 绿。
##   ③ NEG_45    ：凭空 transfer("town","external",D,"import")（付了没有 import 撑的款）⇒ external>应付 ⇒ #45 红、#34 绿。
##   ④ NEG_35ext ：直接 external_coin=−D（export/选项B 未来某棒让 external 透支的合成）⇒ #35 红。
## 注：③④ 是【合成】扰动（探针直改 S 状态），不改 Sim.gd 源码；②③ 正是 docs/151 §四.1 / docs/154 §四要求的负对照。
##
## 用法：godot --headless --path game -s res://bench/as4_negctl_probe.gd -- --seed 1 --days 60 [--delta 5]
## 输出 [AS4NEG]{...}；期望矩阵不符 quit(1)。

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

func _init() -> void:
	var seed := 1
	var days := 60
	var delta := 5
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seed" and i + 1 < args.size():
			seed = int(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])
		elif args[i] == "--delta" and i + 1 < args.size():
			delta = int(args[i + 1])
	print("=== as4_negctl_probe · seed=%d days=%d delta=%d ===" % [seed, days, delta])
	var clean := _run(seed, days, "CLEAN", delta)
	var n34 := _run(seed, days, "NEG_34", delta)
	var n45 := _run(seed, days, "NEG_45", delta)
	var n35 := _run(seed, days, "NEG_35ext", delta)
	for r in [clean, n34, n45, n35]:
		print("[AS4NEG] " + JSON.stringify(r))
	# 期望矩阵：CLEAN 全绿；NEG_34 只 #34 红；NEG_45 只 #45 红；NEG_35ext #35 红。
	var ok: bool = (bool(clean["i34"]) and bool(clean["i45"]) and bool(clean["i35"])
		and (not bool(n34["i34"])) and bool(n34["i45"])
		and (not bool(n45["i45"])) and bool(n45["i34"])
		and (not bool(n35["i35"])))
	print("[AS4NEGSUM] " + JSON.stringify({"expected_matrix_ok": ok, "seed": seed}))
	quit(0 if ok else 1)

func _run(seed: int, days: int, mode: String, delta: int) -> Dictionary:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data(); S.auto_run = false; S.backend = null
	S.start_new(seed)
	var tpd := int(SimScript.TICKS_PER_DAY)
	for _t in range(days * tpd):
		S.tick()
	var ext_before := int(S.external_coin)
	var mt_before := int(S.money_total())
	match mode:
		"NEG_34":
			S.town_coin -= delta                       # 漏贷：扣 town、external 不贷 ⇒ 总量掉
		"NEG_45":
			S.transfer("town", "external", delta, "import")   # 凭空付款：external 多出没 import 撑的一截
		"NEG_35ext":
			S.external_coin = -delta                    # 合成透支（import 单调增下不可达，仅验判别力）
	var report := Inv.check_all(S, 0)
	var rec := {
		"mode": mode, "seed": seed,
		"external_before": ext_before, "external_after": int(S.external_coin),
		"money_total_before": mt_before, "money_total_after": int(S.money_total()),
		"econ_total0": int(S.econ_total0),
		"i34": _ok(report, 34), "i35": _ok(report, 35), "i45": _ok(report, 45),
		"d34": _detail(report, 34), "d45": _detail(report, 45), "d35": _detail(report, 35),
	}
	get_root().remove_child(S); S.free()
	return rec

func _ok(report: Array, iid: int) -> bool:
	for r in report:
		if int(r.get("id", 0)) == iid:
			return bool(r.get("ok", false))
	return true

func _detail(report: Array, iid: int) -> String:
	for r in report:
		if int(r.get("id", 0)) == iid:
			return String(r.get("detail", ""))
	return ""
