extends SceneTree
## bench/as5_negctl_probe.gd — 车道 E-export 负对照矩阵：证 #34/#35/#38/#45/#46(F7) 各有判别力 + F1/F2 命门。
##
## 每个负对照跑一份【全新】Sim 到 T（export lane 激活），施加一处最小扰动，再 Inv.check_all，报目标不变量是否变红。
##   ① CLEAN         ：不扰动 ⇒ 全绿基线（含真 export：#46 逐对绑定绿、#45 双向对账绿）。
##   ② NEG_34        ：town_coin−=D（漏贷）⇒ money_total 掉 ⇒ #34 红、#45/#46 绿。
##   ③ NEG_35ext     ：external_coin=−D（合成透支）⇒ #35 红。
##   ④ NEG_38        ：绕过 _stock_move 直写 town_stock−D（不写 export 事件）⇒ 账本多这截 ⇒ #38 红、#46 绿。
##   ⑤ NEG_45imp     ：凭空 transfer("town","external",D,"import")（付了没 import 撑的款）⇒ external>应值 ⇒ #45 红、#34/#46 绿。
##   ⑥ ★NEG_F1_free  ：【F1 命门】_stock_move(豆子,−D,"export") 出货【但不 transfer 收钱】(免费流失)
##                     ⇒ 现役 #34 绿(钱没变)/#38 绿(库存−D 正常记)——正是外审说的"全绿漏洞"——
##                     而 #46 红(export 货事件无前导 pay) + #45 红(external 高于应值)。★这就是"ship-for-free 现被 F7 抓住"。
##   ⑦ ★NEG_F7_collect：【收钱不发货】transfer("external","town",D,"export*D")【但不出货】⇒ #46 红(pay 无紧随货)+#45 红。
##   ⑧ ★NEG_F7_qty   ：【收 N 发 k】transfer(...,"export*5") 收 5 件的钱、_stock_move(豆子,−3,"export") 只发 3
##                     ⇒ #46 红(pay.qty=5≠stock.qty=3)+#45 红(external 反映实收≠账面)。
##   ⑨ ★NEG_F2_cross ：【F2 跨边抵消】phantom import(+D,良构) + phantom export(−D,良构) 净为 0（无货撑）
##                     ⇒ #45 被净额骗过【绿】(external 净不变) —— 而 #46 红(phantom export pay 无紧随货事件)。证 #46 补 #45 盲区。
##
## 注：⑥⑧ 用真通道 _stock_move（faithful，town_stock 一致 ⇒ #38 绿），其余用合成 transfer/直写。全在跑完后施加、再 check_all。
## 用法：godot --headless --path game -s res://bench/as5_negctl_probe.gd -- --seed 1 --days 60 [--delta 5]
## 输出逐条 [AS5NEG]{...}；期望矩阵不符 quit(1)。

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
	print("=== as5_negctl_probe · seed=%d days=%d delta=%d ===" % [seed, days, delta])
	var modes := ["CLEAN", "NEG_34", "NEG_35ext", "NEG_38", "NEG_45imp",
		"NEG_F1_free", "NEG_F7_collect", "NEG_F7_qty", "NEG_F2_cross"]
	var res := {}
	for m in modes:
		var r := _run(seed, days, m, delta)
		res[m] = r
		print("[AS5NEG] " + JSON.stringify(r))
	# 期望矩阵。
	var c = res["CLEAN"]
	var ok: bool = true
	ok = ok and bool(c["i34"]) and bool(c["i35"]) and bool(c["i38"]) and bool(c["i45"]) and bool(c["i46"])
	ok = ok and (not bool(res["NEG_34"]["i34"])) and bool(res["NEG_34"]["i45"]) and bool(res["NEG_34"]["i46"])
	ok = ok and (not bool(res["NEG_35ext"]["i35"]))
	ok = ok and (not bool(res["NEG_38"]["i38"])) and bool(res["NEG_38"]["i46"])
	ok = ok and (not bool(res["NEG_45imp"]["i45"])) and bool(res["NEG_45imp"]["i34"]) and bool(res["NEG_45imp"]["i46"])
	# F1 命门：现役 #34/#38 绿（外审说的全绿漏洞），F7 的 #46 与 #45 抓住。
	ok = ok and bool(res["NEG_F1_free"]["i34"]) and bool(res["NEG_F1_free"]["i38"]) \
		and (not bool(res["NEG_F1_free"]["i46"])) and (not bool(res["NEG_F1_free"]["i45"]))
	ok = ok and (not bool(res["NEG_F7_collect"]["i46"])) and (not bool(res["NEG_F7_collect"]["i45"])) and bool(res["NEG_F7_collect"]["i34"])
	ok = ok and (not bool(res["NEG_F7_qty"]["i46"])) and (not bool(res["NEG_F7_qty"]["i45"])) and bool(res["NEG_F7_qty"]["i34"])
	# F2 跨边抵消：#45 被净额骗过绿，#46 抓住。
	ok = ok and bool(res["NEG_F2_cross"]["i45"]) and (not bool(res["NEG_F2_cross"]["i46"]))
	print("[AS5NEGSUM] " + JSON.stringify({"expected_matrix_ok": ok, "seed": seed}))
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
			S.town_coin -= delta                                   # 漏贷：扣 town、external 不动 ⇒ 总量掉
		"NEG_35ext":
			S.external_coin = -delta                               # 合成透支
		"NEG_38":
			S.town_stock["豆子"] = int(S.town_stock.get("豆子", 0)) - delta   # 绕 _stock_move 直写（不写 export 事件）
		"NEG_45imp":
			S.transfer("town", "external", delta, "import")        # 凭空 import 付款：external 多出没货撑的一截
		"NEG_F1_free":
			# ★F1：出货但不收钱（免费流失）。用真通道 _stock_move ⇒ town_stock 一致(#38 绿)、写 export 事件(无 pay)。
			S._stock_move("豆子", -delta, "export", "port_dock", "export")
		"NEG_F7_collect":
			# 收钱不发货：一条 export pay、无货事件。
			S.transfer("external", "town", delta, "export*%d" % delta)
		"NEG_F7_qty":
			# 收 N 发 k：收 delta 件的钱、只发 delta-2 件货（数量不符）。
			S.transfer("external", "town", delta, "export*%d" % delta)
			S._stock_move("豆子", -(delta - 2), "export", "port_dock", "export")
		"NEG_F2_cross":
			# ★F2 跨边抵消：phantom import(+delta) + phantom export(−delta) 净为 0，两笔都无货撑。
			S.transfer("town", "external", delta, "import")        # external += delta
			S.transfer("external", "town", delta, "export*%d" % delta)   # external −= delta（净 0）
	var report := Inv.check_all(S, 0)
	var rec := {
		"mode": mode, "seed": seed,
		"external_before": ext_before, "external_after": int(S.external_coin),
		"money_total_before": mt_before, "money_total_after": int(S.money_total()),
		"i34": _ok(report, 34), "i35": _ok(report, 35), "i38": _ok(report, 38),
		"i45": _ok(report, 45), "i46": _ok(report, 46),
		"d38": _detail(report, 38), "d45": _detail(report, 45), "d46": _detail(report, 46),
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
