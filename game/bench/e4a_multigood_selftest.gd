extends SceneTree
## bench/e4a_multigood_selftest.gd — E4a 合成自测：**证多货 consume 机器真的成立**。
##
## E4a 是纯机器改（docs/166）：让一个动作能消费【多件货】，同时逐字节兼容既有的单货 dict。
## 零金标那一半（单货 dict 分支逐字节不变）由 Harness --golden 12/12 证；本探针证【另一半】：
##   Array 分支喂进 2 货真的会：① 两货都被消费 ② 两货都触发缺货后果 ③ 半缺时 AND-fold 返回 false
##   ④ #40 需求把两件货各自记上。
##
## ★不改盘上数据：production.json 一个字节都不动。本探针在【内存里】给一个合成动作注入 2 货 consume，
##   跑完即随 Sim 实例一起释放。它不进金标路、不被 Harness/ci.sh 自动执行（只被 --import 解析），
##   故对零金标与全 CI 判决都零影响。
##
## 用法：
##   godot --headless --path game -s res://bench/e4a_multigood_selftest.gd
## 退出码：全绿 0，任一断言失败 1（可直接进脚本判红）。

const SimScript = preload("res://scripts/Sim.gd")

var _fails: Array = []

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ✅ " + msg)
	else:
		_fails.append(msg)
		print("  ❌ " + msg)

func _init() -> void:
	print("=== E4a 多货 consume 合成自测（证 Array 分支：双消费 / 双缺货 / 半缺 AND-fold / 双需求）===")
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	S.start_new(1)

	# 选两件【真实货】——都有 goods 定义与 blame，_shortage_fallout 才能真跑到底
	var gA := "口粮"
	var gB := "柴薪"
	_ok(S.production.get("goods", {}).has(gA), "前置：goods 含真实货 %s" % gA)
	_ok(S.production.get("goods", {}).has(gB), "前置：goods 含真实货 %s" % gB)

	# 在内存里给一个合成动作注入【2 货】consume（Array 形状——这正是 Part B 才会入盘的形状）
	var act := "E4A_SELFTEST消费"
	var amtA := 2
	var amtB := 1
	(S.production["consume"] as Dictionary)[act] = [
		{"good": gA, "amount": amtA},
		{"good": gB, "amount": amtB},
	]
	var ag: Dictionary = S.agents[0]

	# ── 测 A：两货都在库 → 都被消费、返回 true、attempts 只 +1 ────────────────────
	S.town_stock[gA] = 100
	S.town_stock[gB] = 100
	var cA0 := int((S.prod_stats["consumed"] as Dictionary).get(gA, 0))
	var cB0 := int((S.prod_stats["consumed"] as Dictionary).get(gB, 0))
	var at0 := int((S.prod_stats["attempts"] as Dictionary).get(act, 0))
	var rA = S._consume_for(ag, act)
	_ok(rA == true, "A: 双货足量 → 返回 true")
	_ok(int(S.town_stock[gA]) == 100 - amtA, "A: %s 库存扣 %d（100→%d）" % [gA, amtA, int(S.town_stock[gA])])
	_ok(int(S.town_stock[gB]) == 100 - amtB, "A: %s 库存扣 %d（100→%d）" % [gB, amtB, int(S.town_stock[gB])])
	_ok(int(S.prod_stats["consumed"][gA]) == cA0 + amtA, "A: consumed[%s] += %d" % [gA, amtA])
	_ok(int(S.prod_stats["consumed"][gB]) == cB0 + amtB, "A: consumed[%s] += %d" % [gB, amtB])
	_ok(int(S.prod_stats["attempts"][act]) == at0 + 1, "A: attempts[act] 只 +1（一次动作一次计数，与货数无关）")

	# ── 测 B：两货都缺 → 两条 shortage 都触发、返回 false ──────────────────────────
	S._short_day = {}                                    # 清日名额，保证本次两货都能写事件
	S.town_stock[gA] = 0
	S.town_stock[gB] = 0
	var sA0 := int((S.prod_stats["short"] as Dictionary).get(gA, 0))
	var sB0 := int((S.prod_stats["short"] as Dictionary).get(gB, 0))
	var ev0 := _count_shortage(S)
	var rB = S._consume_for(ag, act)
	_ok(rB == false, "B: 双货皆缺 → AND-fold 返回 false")
	_ok(int((S.prod_stats["short"] as Dictionary).get(gA, 0)) == sA0 + 1, "B: short[%s] += 1" % gA)
	_ok(int((S.prod_stats["short"] as Dictionary).get(gB, 0)) == sB0 + 1, "B: short[%s] += 1" % gB)
	_ok(_count_shortage(S) == ev0 + 2, "B: event_log 新增【2】条 shortage（两货各一，顺序=列表著者序）")

	# ── 测 C：一有一无 → AND-fold false、有货照消费、只缺的写 shortage ──────────────
	S._short_day = {}
	S.town_stock[gA] = 100
	S.town_stock[gB] = 0
	var cA1 := int((S.prod_stats["consumed"] as Dictionary).get(gA, 0))
	var sA1 := int((S.prod_stats["short"] as Dictionary).get(gA, 0))
	var sB1 := int((S.prod_stats["short"] as Dictionary).get(gB, 0))
	var ev1 := _count_shortage(S)
	var rC = S._consume_for(ag, act)
	_ok(rC == false, "C: 半缺 → 返回 false（任一缺即 false）")
	_ok(int(S.prod_stats["consumed"][gA]) == cA1 + amtA, "C: 有货的 %s 照常消费 += %d" % [gA, amtA])
	_ok(int((S.prod_stats["short"] as Dictionary).get(gA, 0)) == sA1, "C: 有货的 %s 不记 short" % gA)
	_ok(int((S.prod_stats["short"] as Dictionary).get(gB, 0)) == sB1 + 1, "C: 缺货的 %s short += 1" % gB)
	_ok(_count_shortage(S) == ev1 + 1, "C: event_log 只新增【1】条 shortage（缺的那件）")

	# ── 测 D：#40 需求把两件货各自记上 ───────────────────────────────────────────────
	# _demand_of() 是 Invariants.gd:857（#40）与 ScaleSupply.gd:230（4a）**同一份 4 行需求环的逐字副本**。
	# 为什么在这里复刻而不直接调那两处：Invariants #40 的需求只在【完整 60 天 gated 局】里评估（本探针不跑满局），
	# ScaleSupply extends SceneTree ⇒ 一 new() 就跑整场 census（12 seed×60 天）。两者的【单货分支】已由零金标
	# 12/12 逐字节证过；这里只需证【Array 分支】把两件货各自累加。
	var nAtt := 10
	var dem: Dictionary = _demand_of(S, {act: nAtt})     # 只给合成动作非零 attempts ⇒ 其余动作贡献 0
	var dmA := int(dem.get(gA, -1))
	var dmB := int(dem.get(gB, -1))
	_ok(dmA == nAtt * amtA, "D: demand[%s] = attempts(%d)×amt(%d) = %d（实得 %d）" % [gA, nAtt, amtA, nAtt * amtA, dmA])
	_ok(dmB == nAtt * amtB, "D: demand[%s] = attempts(%d)×amt(%d) = %d（实得 %d）" % [gB, nAtt, amtB, nAtt * amtB, dmB])

	# ── 收尾 ─────────────────────────────────────────────────────────────────────
	get_root().remove_child(S); S.free()
	if _fails.is_empty():
		print("=== E4A SELFTEST: PASS ✅  (多货 consume 机器成立) ===")
		quit(0)
	else:
		print("=== E4A SELFTEST: FAIL ❌  %d 项未过：" % _fails.size())
		for m in _fails:
			print("   - " + m)
		quit(1)

func _count_shortage(S) -> int:
	var n := 0
	for e in S.event_log:
		if String(e.get("type", "")) == "shortage":
			n += 1
	return n

## #40 需求环的逐字副本（Invariants.gd:857 / ScaleSupply.gd:230 是同一份 4 行、含 E4a 双形状归一化）。
## demand[good] = Σ_action attempts[action] × amount，多货 consume 时每件货各自累加；按列表著者序遍历。
func _demand_of(S, attempts: Dictionary) -> Dictionary:
	var demand: Dictionary = {}
	for g in S.production.get("goods", {}):
		demand[String(g)] = 0
	for act in S.production.get("consume", {}):
		var craw = (S.production["consume"] as Dictionary)[String(act)]
		var crecs: Array = craw if craw is Array else [craw]
		for crec in crecs:
			if not (crec is Dictionary) or (crec as Dictionary).is_empty():
				continue
			var cg := String((crec as Dictionary).get("good", ""))
			if demand.has(cg):
				demand[cg] = int(demand[cg]) \
					+ int(attempts.get(String(act), 0)) * int((crec as Dictionary).get("amount", 1))
	return demand
