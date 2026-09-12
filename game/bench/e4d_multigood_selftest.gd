extends SceneTree
## bench/e4d_multigood_selftest.gd — E4d-A 合成自测：**证多货 produce 机器真的成立**（consume 侧 E4a 的镜像）。
##
## E4d-A 是纯机器改（docs/169）：让一个【产者】一场做出【多件货】，同时逐字节兼容既有的单货 dict。
## 零金标那一半（单货 dict 分支逐字节不变）由 Harness --golden 12/12 证；本探针证【另一半】：
##   produce Array 分支喂进 2 货真的会：① 两货都入库（各一条 produce 事件、按【列表著者序】）
##   ② work[title] 每【场】只 +1（与产几件货无关）③ #39 溯源【按 subject-good 逐货匹配】、件数各自 ≤ 该货申报批量
##   ④ 缺料缩放【逐货独立】（一件货缺料被整数缩水、另一件不受影响）⑤ #40 原料需求【逐 rec 累加】。
##
## ★不改盘上数据：production.json 一个字节都不动。本探针在【内存里】给一个合成产职注入 2 货 produce、
##   并注入一个合成岗位让 _produce_for 的班次守卫放行，跑完即随 Sim 实例一起释放。它不进金标路、
##   不被 Harness/ci.sh 自动执行（只被 --import 解析），故对零金标与全 CI 判决都零影响。
##
## 用法：
##   godot --headless --path game -s res://bench/e4d_multigood_selftest.gd
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
	print("=== E4d-A 多货 produce 合成自测（证 Array 分支：双入库/著者序/work一次/逐货#39/逐货缺料缩放/逐rec需求）===")
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	S.start_new(1)

	# 选真实货（都有 goods 定义与 cap/blame，_stock_move / _shortage_fallout 才能真跑到底）
	var gA := "口粮"        # cap 130
	var gB := "柴薪"        # cap 80
	var gTile := "屋瓦"     # cap 120（缺料缩放测试的产物）
	var gIn := "柴薪"       # 缺料缩放/需求测试里当【原料】
	for g in [gA, gB, gTile, gIn]:
		_ok(S.production.get("goods", {}).has(g), "前置：goods 含真实货 %s" % g)

	# 注入一个合成岗位，让 _produce_for 的「本职 + 在班」守卫放行（shift=[] ⇒ _in_shift 恒 true）
	var ag: Dictionary = S.agents[0]
	var agid := String(ag["id"])
	var title := "E4D_SELFTEST产职"
	var action := "E4D_SELFTEST出活"
	(S.jobs["jobs"] as Dictionary)[agid] = {"title": title, "action": action, "wage": 3, "shift": []}
	_ok(S._job_action(S._job_of(agid)) == action, "前置：合成岗位本职动作解析为 %s" % action)
	_ok(S._in_shift(S._job_of(agid)) == true, "前置：合成岗位 shift=[] ⇒ 恒在班")

	# ── 测 A：一场做 2 货、足够库容 → 两货各入库、work 只 +1、2 条 produce 事件按著者序 ──────────
	var amtA := 2
	var amtB := 1
	(S.production["produce"] as Dictionary)[title] = [
		{"good": gA, "amount": amtA},
		{"good": gB, "amount": amtB},
	]
	S.town_stock[gA] = 0
	S.town_stock[gB] = 0
	var wk0 := int((S.prod_stats["work"] as Dictionary).get(title, 0))
	var pA0 := int((S.prod_stats["produced"] as Dictionary).get(gA, 0))
	var pB0 := int((S.prod_stats["produced"] as Dictionary).get(gB, 0))
	var ev0: int = S.event_log.size()
	S._produce_for(ag, action)
	_ok(int(S.town_stock[gA]) == amtA, "A: %s 入库 +%d（0→%d）" % [gA, amtA, int(S.town_stock[gA])])
	_ok(int(S.town_stock[gB]) == amtB, "A: %s 入库 +%d（0→%d）" % [gB, amtB, int(S.town_stock[gB])])
	_ok(int(S.prod_stats["produced"][gA]) == pA0 + amtA, "A: produced[%s] += %d" % [gA, amtA])
	_ok(int(S.prod_stats["produced"][gB]) == pB0 + amtB, "A: produced[%s] += %d" % [gB, amtB])
	_ok(int(S.prod_stats["work"][title]) == wk0 + 1, "A: work[title] 每【场】只 +1（与产几件货无关）")
	var new_prod := _new_produce_subjects(S, ev0, agid)
	_ok(new_prod == [gA, gB], "A: event_log 新增【2】条 produce、顺序=列表著者序 %s（实得 %s）" % [str([gA, gB]), str(new_prod)])

	# ── 测 B：#39 溯源【逐货匹配】——两条 produce 事件各自匹配到 subject-good 的申报、件数 ≤ 该货批量 ──
	var prov_bad := _prov_bad_for(S, agid, title)
	_ok(prov_bad.is_empty(), "B: #39 逐货溯源全过（两货各匹配到 .good==subject 的申报、件数≤批量）；异常=%s" % str(prov_bad))

	# ── 测 C：缺料缩放【逐货独立】——只有带 inputs 的那件被整数缩水，另一件不受影响 ─────────────
	#   rec 屋瓦 需料 柴薪×4，库里只有 2 ⇒ 缩水比 2/4 ⇒ 产 4×2/4=2；rec 口粮 无料 ⇒ 满产 2。work 仍只 +1。
	(S.production["produce"] as Dictionary)[title] = [
		{"good": gTile, "amount": 4, "inputs": {gIn: 4}},
		{"good": gA, "amount": 2},
	]
	S._short_day = {}
	S.town_stock[gTile] = 0
	S.town_stock[gA] = 0
	S.town_stock[gIn] = 2                                 # 只够半窑（需 4、有 2）
	var wkC0 := int((S.prod_stats["work"] as Dictionary).get(title, 0))
	var pTile0 := int((S.prod_stats["produced"] as Dictionary).get(gTile, 0))
	var pAc0 := int((S.prod_stats["produced"] as Dictionary).get(gA, 0))
	var shIn0 := int((S.prod_stats["short"] as Dictionary).get(gIn, 0))
	var evC0 := _count_shortage(S)
	S._produce_for(ag, action)
	_ok(int(S.prod_stats["produced"][gTile]) == pTile0 + 2, "C: 缺料的 %s 整数缩水到 2（4×2/4）" % gTile)
	_ok(int(S.prod_stats["produced"][gA]) == pAc0 + 2, "C: 无料的 %s 满产 2（不受另一件缺料影响）" % gA)
	_ok(int((S.prod_stats["short"] as Dictionary).get(gIn, 0)) == shIn0 + 1, "C: 缺的原料 %s short += 1" % gIn)
	_ok(_count_shortage(S) == evC0 + 1, "C: event_log 只新增【1】条缺料 shortage（料:%s）" % gIn)
	_ok(int(S.prod_stats["work"][title]) == wkC0 + 1, "C: 缺料一场仍 work[title] 只 +1")

	# ── 测 D：#40 原料需求【逐 rec 累加】——两条 rec 都以 柴薪 为料，需求 = work × Σ各 rec 用量 ────────
	(S.production["produce"] as Dictionary)[title] = [
		{"good": gTile, "amount": 4, "inputs": {gIn: 4}},
		{"good": gA, "amount": 2, "inputs": {gIn: 1}},
	]
	var nWork := 10
	var dem: Dictionary = _prod_demand_of(S, {title: nWork})   # 只给合成产职非零 work ⇒ 其余产职贡献 0
	var expect := nWork * (4 + 1)
	_ok(int(dem.get(gIn, -1)) == expect, "D: demand[%s] = work(%d)×Σ料(4+1) = %d（实得 %d）" % [gIn, nWork, expect, int(dem.get(gIn, -1))])

	# ── 收尾 ─────────────────────────────────────────────────────────────────────
	get_root().remove_child(S); S.free()
	if _fails.is_empty():
		print("=== E4D SELFTEST: PASS ✅  (多货 produce 机器成立) ===")
		quit(0)
	else:
		print("=== E4D SELFTEST: FAIL ❌  %d 项未过：" % _fails.size())
		for m in _fails:
			print("   - " + m)
		quit(1)

## event_log 从 ev0 起【新增】的、由 actor 产的 produce 事件的 subject 序列（= 入库顺序 = 列表著者序）。
func _new_produce_subjects(S, ev0: int, actor: String) -> Array:
	var out: Array = []
	for i in range(ev0, S.event_log.size()):
		var e: Dictionary = S.event_log[i]
		if String(e.get("type", "")) == "produce" and String(e.get("actor", "")) == actor:
			out.append(String(e.get("subject", "")))
	return out

func _count_shortage(S) -> int:
	var n := 0
	for e in S.event_log:
		if String(e.get("type", "")) == "shortage":
			n += 1
	return n

## _amt_of 的逐字副本（Invariants.gd:#39）：note="<title>*<件数>" ⇒ 取末位 * 之后。
func _amt_of(note: String) -> int:
	var i := note.rfind("*")
	return int(note.substr(i + 1)) if i >= 0 else 0

## #39 逐货溯源的逐字副本（Invariants.gd:~701，含 E4d-A 双形状归一化 + subject-good 匹配）。
## 返回异常串数组：对每条 actor 产的 produce 事件，按 subject 找 .good 相同的申报；找不到=产未申报货、件数超批量=红。
func _prov_bad_for(S, actor: String, title: String) -> Array:
	var bad: Array = []
	var praw = S.production.get("produce", {}).get(title, {})
	var precs: Array = praw if praw is Array else [praw]
	var recs2: Array = []
	for pr in precs:
		if pr is Dictionary and not (pr as Dictionary).is_empty():
			recs2.append(pr)
	for e in S.event_log:
		if String(e.get("type", "")) != "produce" or String(e.get("actor", "")) != actor:
			continue
		var subj := String(e.get("subject", ""))
		var matched: Dictionary = {}
		for pr in recs2:
			if String((pr as Dictionary).get("good", "")) == subj:
				matched = pr as Dictionary
				break
		var amt := _amt_of(String(e.get("note", "")))
		if matched.is_empty():
			bad.append("%s 产出了未申报的货 %s" % [title, subj])
		elif amt <= 0 or amt > int(matched.get("amount", 0)):
			bad.append("%s 产 %s 件数=%d 超出申报 %d" % [title, subj, amt, int(matched.get("amount", 0))])
	return bad

## #40 原料需求环的逐字副本（Invariants.gd:~843 / ScaleSupply.gd:~218，含 E4d-A 双形状归一化）。
## demand[原料] = Σ_产职 work[产职] × Σ各 rec 的该料用量；多货 produce 时【逐 rec 累加】、按列表著者序遍历。
func _prod_demand_of(S, work_map: Dictionary) -> Dictionary:
	var demanded: Dictionary = {}
	var demand: Dictionary = {}
	for g in S.production.get("goods", {}):
		demanded[String(g)] = true       # 真实货即有需求资格（镜像真实 #40 的 demanded.has 门）
		demand[String(g)] = 0
	for t in S.production.get("produce", {}):
		var praw = (S.production["produce"] as Dictionary)[String(t)]
		var precs: Array = praw if praw is Array else [praw]
		var nw := int(work_map.get(String(t), 0))
		for prec in precs:
			if not (prec is Dictionary) or (prec as Dictionary).is_empty():
				continue
			var pins = (prec as Dictionary).get("inputs", {})
			if pins is Dictionary:
				for ing in (pins as Dictionary):
					var ig := String(ing)
					if demanded.has(ig):
						demand[ig] = int(demand[ig]) + nw * int((pins as Dictionary)[ing])
	return demand
