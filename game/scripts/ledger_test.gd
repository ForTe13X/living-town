extends Node
## ledger_test.gd — docs/195 · P0 镇账本的门。
## 用法：godot --headless --path game res://scenes/ledger_test.tscn   （CI_LEDGER_SEEDS=1-3 / CI_LEDGER_DAYS=8）
##
##   LF  账本核对：每个账户 现余额 − 折叠净流入 == 开局额，每条 pay 都带 amt>0。N=12（每个 seed）+ N=16（首个 seed）。
##   LI  增量 ≡ 一次性：边跑边按 tick 增量 sync 的结果与跑完后整条一次折叠逐字段相同。
##   LC  活性（判别力）：饭钱/工资/房租/进口/出口五类至少各一笔 —— 一个什么都不折的实现过得了 LF 却过不了这条。
##   LN  负对照：①绕过 transfer 直接改一人 coin ⇒ 核对变红；②抹掉一条 pay 的 amt ⇒ 变红。
##   LR  回放/读档：goto_tick 回退后增量 sync 自动重折 == 同 tick 一次折叠；存档读档后核对仍绿。
const SimScript = preload("res://scripts/Sim.gd")
const LedgerScript = preload("res://scripts/Ledger.gd")

var _fails := 0
var _seen := {}          # 全体 run 里出现过的流水类（LC 的进出口臂）
func ck(c: bool, m: String) -> void:
	if not c: _fails += 1
	print(("  OK   " if c else "  FAIL ") + m)

func _parse_seeds(s: String) -> Array:
	var out := []
	if "-" in s:
		var p := s.split("-")
		for v in range(int(p[0]), int(p[1]) + 1): out.append(v)
	else:
		out.append(int(s))
	return out

func _same(a, b) -> bool:
	return a.net == b.net and a.flows == b.flows and a.by_day == b.by_day and a.pays == b.pays and a.missing_amt == b.missing_amt

func _run(seed: int, n: int, days: int, deep: bool) -> void:
	var tag := "seed %d N=%d" % [seed, n]
	var S = SimScript.new(); add_child(S)
	if n > 12:
		S.spawn_count = n
	S.start_new(seed)
	var inc = LedgerScript.new()
	var ticks: int = days * int(S.TICKS_PER_DAY)
	for i in range(ticks):
		S.tick()
		if i % 7 == 0:                      # 不齐整的块：增量路径必须与一次性折叠一致
			inc.sync(S.event_log, S.TICKS_PER_DAY)
	inc.sync(S.event_log, S.TICKS_PER_DAY)
	var full = LedgerScript.fold(S.event_log, S.TICKS_PER_DAY)
	var bad: Array = full.verify(S)
	ck(bad.is_empty(), "%s LF 账本核对（%d 条 pay）%s" % [tag, int(full.pays), "" if bad.is_empty() else " → " + String(bad[0])])
	var nonpos := 0
	for e in S.event_log:
		if String(e.get("type", "")) == "pay" and int(e.get("amt", 0)) <= 0:
			nonpos += 1
	ck(nonpos == 0, "%s LF 每条 pay 的 amt > 0（违例 %d）" % [tag, nonpos])
	ck(_same(inc, full), "%s LI 增量 sync ≡ 一次性折叠" % tag)
	# 逐 seed：镇内三类每天都有；进出口按 manifest/地板节奏走，8 天里某些 seed 一笔出口都没有（豆子没过出口地板）
	#   是经济本身的样子，不是账本的错 ⇒ 这两类记进全体并集，在 _ready 末尾要求至少一个 seed 见过。
	var dead := PackedStringArray()
	for c in ["meal", "wage", "rent", "bill", "import", "export"]:
		if int((full.flows.get(c, {}) as Dictionary).get("n", 0)) == 0:
			if c in ["meal", "wage", "rent", "bill"]: dead.append(c)
		else:
			_seen[c] = true
	ck(dead.is_empty(), "%s LC 饭钱/工资/房租/账单都有（缺：%s）" % [tag, ",".join(dead)])
	var txt: String = full.panel_text(S, func(id): return id)
	ck(txt.contains("核对 ✓") and txt.contains("镇库"), "%s 面板正文含核对 ✓" % tag)
	if not deep:
		S.queue_free()
		return

	# LN ① 绕过 transfer 改钱 ⇒ 红
	var victim: Dictionary = S.agents[0]
	victim["inventory"]["coin"] = int(victim["inventory"]["coin"]) + 1
	ck(not full.verify(S).is_empty(), "%s LN① 直接改 %s 的 coin ⇒ 核对变红" % [tag, String(victim["id"])])
	victim["inventory"]["coin"] = int(victim["inventory"]["coin"]) - 1
	ck(full.verify(S).is_empty(), "%s LN① 改回后核对复绿" % tag)
	S.bank_coin += 1
	ck(not full.verify(S).is_empty(), "%s bank cash changed outside transfer is detected" % tag)
	S.bank_coin -= 1
	ck(full.verify(S).is_empty(), "%s restored bank cash reconciles" % tag)
	# LN ② 抹掉一条 amt ⇒ 红（在副本上做，不碰 S.event_log）
	var log2: Array = S.event_log.duplicate(true)
	for e in log2:
		if String(e.get("type", "")) == "pay":
			(e as Dictionary).erase("amt")
			break
	var L2 = LedgerScript.fold(log2, S.TICKS_PER_DAY)
	ck(not L2.verify(S).is_empty(), "%s LN② 抹掉一条 amt ⇒ 核对变红" % tag)

	# LR 存档读档
	var path := "user://ledger_test.dat"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	ck(S.save_game(path, {"name": "ledger"}), "%s LR save_game" % tag)
	var B = SimScript.new(); add_child(B)
	ck(B.load_game(path), "%s LR load_game" % tag)
	var LB = LedgerScript.fold(B.event_log, B.TICKS_PER_DAY)
	ck(LB.verify(B).is_empty() and _same(LB, full), "%s LR 读档后折叠核对仍绿且与存档前相同" % tag)
	for i in range(int(S.TICKS_PER_DAY)):
		B.tick()
	var LB2 = LedgerScript.fold(B.event_log, B.TICKS_PER_DAY)
	ck(LB2.verify(B).is_empty(), "%s LR 读档后续跑一天核对仍绿" % tag)
	B.queue_free()

	# LR goto_tick 回退：增量实例必须自己发现并重折
	var back: int = ticks / 2
	ck(S.goto_tick(back), "%s LR goto_tick(%d)" % [tag, back])
	var refolded: bool = inc.sync(S.event_log, S.TICKS_PER_DAY)
	var fresh = LedgerScript.fold(S.event_log, S.TICKS_PER_DAY)
	ck(refolded and _same(inc, fresh) and fresh.verify(S).is_empty(), "%s LR 回退后增量重折 ≡ 一次折叠且核对绿" % tag)
	S.queue_free()

func _ready() -> void:
	var seeds := _parse_seeds(OS.get_environment("CI_LEDGER_SEEDS") if OS.get_environment("CI_LEDGER_SEEDS") != "" else "1-3")
	var days := int(OS.get_environment("CI_LEDGER_DAYS")) if OS.get_environment("CI_LEDGER_DAYS") != "" else 8
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size(): seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size(): days = int(args[i + 1])
	print("ledger_test: seeds %s × %d 天" % [str(seeds), days])
	# 分类单元：六个 transfer 调用点的 reason 前缀
	ck(LedgerScript.category("price:吃饭") == "meal" and LedgerScript.category("buy:买饭") == "vendor"
		and LedgerScript.category("wage:做活") == "wage" and LedgerScript.category("rent") == "rent"
		and LedgerScript.category("import*4") == "import" and LedgerScript.category("export*6") == "export"
		and LedgerScript.category("bill:水电") == "bill" and LedgerScript.category("bonus:全勤") == "bonus"
		and LedgerScript.category("gift") == "other", "分类：八种 reason 前缀各归其类（含 docs/196 账单/奖金）")
	ck(LedgerScript.category("buy:下馆子") == "restaurant" and LedgerScript.category("buy:赶集") == "vendor",
		"分类：docs/200 餐馆一顿饭单列 restaurant，集市摊仍是 vendor")
	ck(LedgerScript.category("buy:理发") == "barber" and LedgerScript.category("buy:逛店") == "boutique",
		"分类：docs/201 理发、小店各自单列")
	ck(LedgerScript.category("buy:下午茶") == "hotel" and LedgerScript.category("buy:游船") == "hotel",
		"分类：docs/203 下午茶、游船都记在酒店")
	ck(LedgerScript.category("subsidy*12") == "subsidy" and LedgerScript.category("tax*3") == "tax"
		and "subsidy" in LedgerScript.TOWN_IN and "tax" in LedgerScript.TOWN_OUT,
		"分类：docs/204 补贴进镇库、税出镇库")
	for k in seeds.size():
		_run(int(seeds[k]), 12, days, k == 0)
	_run(int(seeds[0]), 16, days, false)
	# docs/198：出口要豆子过地板 + 此前真付过进口款；master 上 N=12 首笔出口也在第 14-20 天，
	#   8 天窗口只靠 N=16 那一跑凑巧第 5 天出了一笔。P2 供养之后那一跑 30 天内都不出口 ⇒ 补一跑够长的
	#   （seed 2 × 24 天，P2 实测首笔出口第 20 天），让 LC 的出口臂测的是账本、而不是某个 seed 的运气。
	if not _seen.has("export"):
		_run(2, 12, 24, false)
	ck(_seen.has("import") and _seen.has("export"), "LC 进口与出口在全体 run 里都出现过（%s）" % ",".join(PackedStringArray(_seen.keys())))
	print("ledger_test: %s (%d fail)" % ["PASS ✅" if _fails == 0 else "FAIL ❌", _fails])
	get_tree().quit(0 if _fails == 0 else 1)
