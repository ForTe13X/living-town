extends RefCounted
## Ledger.gd — docs/195 · P0 账本视图（docs/194 §二·4 / §四 P0）。
##
## 钱的账本 = event_log 里 `pay` 事件的【纯折叠】，不是第二份权威态（同 #38 之于 _stock_move）。
## 每条 pay 事件由 Sim.transfer 写出；自 docs/195 起它带 `amt` 字段。`amt` 不在 Inv.digest / chain_step /
## event_digest 的字段串里 ⇒ 加它不动任何金标（三处都只拼 id/type/actor/target/accepted/subject/tick/witnesses/note/txid）。
##
## 单向：Main → Ledger。Ledger 从不回写 Sim，也不回写 Main 的任何仿真相关字段。
## 回放（goto_tick）/读档让 event_log 变短或换了内容 ⇒ sync 发现尾巴对不上，自动从头重折。

## 分类由 transfer 的 reason 前缀决定（Sim.gd 里恰好六个调用点，reason 前缀一一对应）：
##   price:<动作> 居民→镇库（吃饭等收费）· buy:<动作> 居民→摊贩 · wage:<动作> 镇库→居民
##   rent 房客→房东 · import*<件> 镇库→大他者 · export*<件> 大他者→镇库
##   docs/196：bill:<项> 居民→镇库（水电/炭火/欠费）· bonus:<项> 镇库→居民（全勤奖）
##   docs/197：price:采买 居民→镇库（杂货铺买口粮进食橱）单列为 grocery
##   docs/200：buy:下馆子 居民→厨师（餐馆一顿饭）单列为 restaurant，不混进集市摊贩
##   docs/201：buy:理发 居民→理发师、buy:逛店 居民→店主，各自单列
##   docs/203：buy:下午茶、buy:游船 居民→酒店掌柜，合成一类 hotel
const CATS := ["meal", "grocery", "vendor", "restaurant", "barber", "boutique", "hotel", "wage", "rent", "bill", "bonus", "import", "export", "other"]
const CAT_NAME := {"meal": "饭钱", "grocery": "采买", "vendor": "摊贩", "restaurant": "餐馆", "barber": "理发", "boutique": "小店", "hotel": "酒店", "wage": "工资", "rent": "房租",
	"bill": "账单", "bonus": "奖金", "import": "进口", "export": "出口", "other": "其它"}
## 镇库视角：哪些类是进账、哪些是出账（摊贩与房租是居民之间的钱，不经镇库）。
const TOWN_IN := ["meal", "grocery", "bill", "export"]
const TOWN_OUT := ["wage", "bonus", "import"]

var cursor := 0          # 已折叠到 event_log 的哪个下标（不含）
var _tail := ""          # 最后一条已折叠事件的指纹：id:tick:type —— 回放后同一下标换了内容就对不上
var net := {}            # 账户 id → 累计净流入（收 − 付）；"town" / "external" / 居民 id
var flows := {}          # 类 → {"amt": 累计币数, "n": 笔数}
var by_day := {}         # 天(从 1 起) → {类: 当天币数}
var pays := 0            # 已折叠的 pay 事件条数
var missing_amt := 0     # 没带 amt 的 pay 事件（docs/195 之前的旧存档）⇒ 账本无法核对
var rev := 0             # 脏标记：折进了新的 pay 就 +1（Main 据此决定要不要重排面板）

static func category(note: String) -> String:
	var head := note.split("*")[0].split(":")[0]
	if note == "price:采买": return "grocery"
	if note == "buy:下馆子": return "restaurant"
	if note == "buy:理发": return "barber"
	if note == "buy:逛店": return "boutique"
	if note == "buy:下午茶" or note == "buy:游船": return "hotel"
	if head == "price": return "meal"
	if head == "buy": return "vendor"
	if head in ["wage", "rent", "bill", "bonus", "import", "export"]: return head
	return "other"

static func _fp(e: Dictionary) -> String:
	return "%d:%d:%s" % [int(e.get("id", -1)), int(e.get("tick", -1)), String(e.get("type", ""))]

func reset() -> void:
	cursor = 0
	_tail = ""
	net = {}
	flows = {}
	by_day = {}
	pays = 0
	missing_amt = 0
	rev += 1

## 把 event_log[cursor:] 折进来。返回是否折进了新的 pay（或发生了重折）。
func sync(log: Array, ticks_per_day: int) -> bool:
	var refolded := false
	if cursor > log.size() or (cursor > 0 and _fp(log[cursor - 1]) != _tail):
		reset()
		refolded = true
	if cursor == log.size():
		return refolded
	var changed := refolded
	for i in range(cursor, log.size()):
		var e: Dictionary = log[i]
		if String(e.get("type", "")) != "pay":
			continue
		pays += 1
		changed = true
		if not e.has("amt"):
			missing_amt += 1
			continue
		var amt := int(e["amt"])
		var a := String(e.get("actor", ""))
		var t := String(e.get("target", ""))
		net[a] = int(net.get(a, 0)) - amt
		net[t] = int(net.get(t, 0)) + amt
		var c := category(String(e.get("note", "")))
		var f: Dictionary = flows.get(c, {"amt": 0, "n": 0})
		f["amt"] = int(f["amt"]) + amt
		f["n"] = int(f["n"]) + 1
		flows[c] = f
		var d := int(e.get("tick", 0)) / maxi(1, ticks_per_day) + 1
		var dd: Dictionary = by_day.get(d, {})
		dd[c] = int(dd.get(c, 0)) + amt
		by_day[d] = dd
	cursor = log.size()
	_tail = _fp(log[cursor - 1])
	if changed:
		rev += 1
	return changed

## 一次性折叠（测试与核对用）。
static func fold(log: Array, ticks_per_day: int) -> RefCounted:
	var L = load("res://scripts/Ledger.gd").new()
	L.sync(log, ticks_per_day)
	return L

## 账户的开局额：只由数据决定（Sim._make_agent 给每个 agent 发 economy.start_coin；镇库 town_start；大他者 0）。
static func expected_opening(S, id: String) -> int:
	if S.economy.is_empty():
		return 0
	if id == "town":
		return int(S.economy.get("town_start", 0))
	if id == "external":
		return 0
	return int(S.economy.get("start_coin", 10))

static func _accounts(S) -> Array:
	var ids := ["town", "external"]
	for ag in S.agents:
		ids.append(String(ag["id"]))
	return ids

## 账本核对（docs/194 §三「账本 = event_log 的纯折叠」）：
##   每个账户 现余额 − 折叠净流入 == 它的开局额；每条 pay 都带 amt；有流水的账户都还在账户表里。
## 返回不一致的描述；空 = 一致。绕过 transfer 改钱（直接写 coin / town_coin）⇒ 这里必红。
func verify(S) -> Array:
	var bad: Array = []
	if missing_amt > 0:
		bad.append("%d 条 pay 事件没有 amt（旧存档）" % missing_amt)
	var ids := _accounts(S)
	for id in net:
		if not (String(id) in ids):
			bad.append("账户 %s 有流水但不在账户表里" % String(id))
	for id in ids:
		var live := int(S._coin_of(id))
		var open := live - int(net.get(id, 0))
		var want := expected_opening(S, id)
		if open != want:
			bad.append("%s：余额 %d − 净流入 %d = %d ≠ 开局 %d" % [id, live, int(net.get(id, 0)), open, want])
	return bad

func _amt(c: String) -> int:
	return int((flows.get(c, {}) as Dictionary).get("amt", 0))

func _n(c: String) -> int:
	return int((flows.get(c, {}) as Dictionary).get("n", 0))

func _day_amt(d: int, c: String) -> int:
	return int((by_day.get(d, {}) as Dictionary).get(c, 0))

func _town_net(d: int) -> int:
	var s := 0
	for c in TOWN_IN: s += _day_amt(d, c)
	for c in TOWN_OUT: s -= _day_amt(d, c)
	return s

static func _signed(v: int) -> String:
	return ("+%d" % v) if v > 0 else ("−%d" % -v) if v < 0 else "0"

## 面板正文（bbcode）。name_of: Callable(id) -> String。
func panel_text(S, name_of: Callable) -> String:
	var today := int(S.tick_no) / maxi(1, int(S.TICKS_PER_DAY)) + 1
	var bad := verify(S)
	var hd := "[color=#c9b27c]"
	var out := PackedStringArray()
	out.append("[b]镇账本[/b] · 第 %d 天    %s" % [today,
		"[color=#8fce8f]核对 ✓[/color]" if bad.is_empty() else "[color=#e07a6a]核对 ✗ %s[/color]" % String(bad[0])])
	var res_total := 0
	var res_n := 0
	var rich: Array = []
	for ag in S.agents:
		var c := int(ag["inventory"].get("coin", 0))
		res_total += c
		res_n += 1
		rich.append([c, String(ag["id"])])
	out.append("镇库 %d 币 · 大他者 %d 币 · 居民 %d 币（%d 人）" % [int(S.town_coin), int(S.external_coin), res_total, res_n])
	out.append(hd + "── 镇库收支（今天 / 累计）──[/color]")
	var inl := PackedStringArray()
	for c in TOWN_IN:
		inl.append("%s +%d / +%d" % [CAT_NAME[c], _day_amt(today, c), _amt(c)])
	out.append(" 收  " + "   ".join(inl))
	var outl := PackedStringArray()
	for c in TOWN_OUT:
		outl.append("%s −%d / −%d" % [CAT_NAME[c], _day_amt(today, c), _amt(c)])
	out.append(" 支  " + "   ".join(outl))
	var tot := 0
	for c in TOWN_IN: tot += _amt(c)
	for c in TOWN_OUT: tot -= _amt(c)
	out.append(" 净  今天 %s · 累计 %s" % [_signed(_town_net(today)), _signed(tot)])
	out.append(hd + "── 居民之间 ──[/color]")
	out.append(" 摊贩 %d 笔 %d 币 · 餐馆 %d 笔 %d 币 · 房租 %d 笔 %d 币" % [_n("vendor"), _amt("vendor"),
		_n("restaurant"), _amt("restaurant"), _n("rent"), _amt("rent")])
	out.append(" 理发 %d 笔 %d 币 · 小店 %d 笔 %d 币 · 酒店 %d 笔 %d 币" % [_n("barber"), _amt("barber"), _n("boutique"), _amt("boutique"),
		_n("hotel"), _amt("hotel")])
	var owe_n := 0
	var owe_sum := 0
	for ag in S.agents:
		var ow := int(ag.get("arrears", 0))
		if ow > 0:
			owe_n += 1
			owe_sum += ow
	if owe_n > 0:
		out.append(" 欠水电费 %d 人，共 %d 币" % [owe_n, owe_sum])
	out.append(hd + "── 大他者（外部世界）──[/color]")
	out.append(" 进口付款 %d · 出口收入 %d · 净头寸 %d" % [_amt("import"), _amt("export"), int(S.external_coin)])
	out.append(hd + "── 近 7 天镇库净额 ──[/color]")
	var week := PackedStringArray()
	for d in range(maxi(1, today - 6), today + 1):
		week.append("%d日 %s" % [d, _signed(_town_net(d))])
	out.append(" " + " · ".join(week))
	out.append(hd + "── 贫富 ──[/color]")
	rich.sort_custom(func(x, y): return int(x[0]) > int(y[0]) or (int(x[0]) == int(y[0]) and String(x[1]) < String(y[1])))
	var top := PackedStringArray()
	var low := PackedStringArray()
	for i in range(mini(3, rich.size())):
		top.append("%s %d" % [String(name_of.call(String(rich[i][1]))), int(rich[i][0])])
		var j := rich.size() - 1 - i
		low.append("%s %d" % [String(name_of.call(String(rich[j][1]))), int(rich[j][0])])
	out.append(" 最富 " + " · ".join(top))
	out.append(" 最穷 " + " · ".join(low))
	return "\n".join(out)
