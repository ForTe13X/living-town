extends RefCounted
## Goals.gd — 「单局形状」：把 Sim.event_log 折成一条**玩家看得见的进度线**。
## docs/01 §3.2 承诺过的社会成就（撮合一对 / 化解一场争执 / 全员到场的场面）在此落地；缺口见 docs/46 §一 #1。
##
## ★ 架构红线（比这条玩法本身重要得多，docs/46 §二-D2 / docs/41 §0.1）：
##   本文件是**对 `Sim.event_log` 的只读派生**，与 ProbeController 同一纪律 —— 只读，**绝不写世界状态**。
##   一旦目标进度能反过来影响仿真，同一份存档在不同【观看路径】下就会回放出不同历史，
##   本项目最老的那条红线（逐字节可重放）当场破掉。为此本文件：
##     · 不持有 Sim 引用（`sync()` 由调用方把数组喂进来），不调用 Sim 的任何非 static 成员；
##     · 只从事件字典 **取值**，绝不写回（GDScript 的 Dictionary 是引用类型，写一个字段就是改 Sim 的账本）；
##     · 不抽 RNG、不读墙钟、不做浮点比较。
##   机器证明在 `scenes/goals_test.tscn`：R2 臂断言 `Sim.goto_tick(t)` 之后从 event_log 重算的目标状态
##   与「一路 tick 过来」的实时状态**逐字段相同**；R3 臂断言挂上本对象前后 `Inv.digest`/`event_digest` 逐字节不动。
##
## 折叠是**纯函数**：`state' = fold(state, event)`。于是
##   「实时增量折」 ≡ 「从空态重算全量」  —— 按构造成立，测试只是把这句话钉死、防后人分叉。
##
## ⚠️ 「进度相同」不是「折的是同一串事件」：一个什么都不记的 tracker 在前者上恒过。
##    故本类同时维护 `chain`（被折进来的事件序列的滚动见证），两条一起断言才有判别力。

const DEF_PATH := "res://data/goals.json"
## 只为拿 static 的 fnv1a32/fnv1a32_into（红线#1：哈希用项目自有实现，不用引擎 String.hash()）。
## preload 脚本资源而不是用 autoload `Sim` —— 本类因此在没有 autoload 的环境里也能单测。
const SimScript = preload("res://scripts/Sim.gd")

## 非居民的 actor/target 占位（election 的 "town"、缺失字段的 ""）：成对类规则必须先把它们挡掉。
const NON_AGENT := ["", "town"]
## 无序对键的分隔符：不加分隔符的话 "ab"+"c" 与 "a"+"bc" 会撞成同一对（居民 id 里没有 '|'）。
const PAIR_SEP := "|"
## 点播报栏顶那一行 / 按 J 展开完整清单用的 meta（Main._on_log_meta 据此分流；居民 id 不会长这样）。
const PANEL_META := "__goals__"

var defs: Array = []          # 目标定义（只读；来自 data/goals.json 的书写序 = 展示序 = 进度线的顺序）
var state: Array = []         # 与 defs 同序：{id,title,hint,target,progress,done,done_tick,done_ev}
var _acc: Array = []          # 与 defs 同序的内部累加器
var _cursor := 0              # 已折到 event_log 的哪个下标（增量折的游标）
var chain := 0                # 折叠见证链：把每个被折进来的事件的稳定标识折成 32 位滚动哈希

# ── 生命周期 ────────────────────────────────────────────────────────────────
func load_defs(path: String = DEF_PATH) -> bool:
	defs = []
	if not FileAccess.file_exists(path):
		reset()
		return false
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (raw is Dictionary):
		reset()
		return false
	for g in (raw as Dictionary).get("goals", []):
		if g is Dictionary and String((g as Dictionary).get("id", "")) != "":
			defs.append(g)
	reset()
	return not defs.is_empty()

## 清空进度。**时间线换了就必须调**（goto_tick 回拨 / 读档 / 换种子）—— 与 Main._rebuild_feed 同一纪律。
func reset() -> void:
	_cursor = 0
	chain = 0
	state = []
	_acc = []
	for d in defs:
		state.append({
			"id": String(d.get("id", "")), "title": String(d.get("title", "")),
			"hint": String(d.get("hint", "")), "target": maxi(1, int(d.get("target", 1))),
			"progress": 0, "done": false, "done_tick": -1, "done_ev": -1})
		_acc.append({"n": 0, "seen": {}, "armed": {}, "hit": {}})

## 增量折到 `events` 末尾，返回**本次新达成**的目标下标数组（调用方拿去播报）。
## 只读 `events`：不排序、不改元素、不持有引用。
func sync(events: Array) -> Array:
	var fresh: Array = []
	if events.size() < _cursor:
		reset()                       # 时间线变短（往回 scrub / 读档 / 换种子）→ 从头折
	while _cursor < events.size():
		var ev: Dictionary = events[_cursor]
		_cursor += 1
		chain = SimScript.fnv1a32_into(chain, _ev_key(ev))
		for i in defs.size():
			if bool(state[i]["done"]):
				continue              # 已达成的不再累加：省成本，且 done_tick 不会被后来的事件挪动
			if _step(i, ev) and bool(state[i]["done"]):
				fresh.append(i)
	return fresh

## 重算口径：从空态把 `events` 全量折一遍。测试的 R2 臂用它对拍实时臂。
func recompute(events: Array) -> Array:
	reset()
	return sync(events)

# ── 折叠核心（纯函数）───────────────────────────────────────────────────────
## 把一个事件折进第 i 条目标。返回 true = 进度有变化。
func _step(i: int, ev: Dictionary) -> bool:
	var d: Dictionary = defs[i]
	var a: Dictionary = _acc[i]
	var st: Dictionary = state[i]
	var before := int(st["progress"])
	match String(d.get("kind", "count")):
		"count":
			# 「发生过 N 次这样的事」
			if _match(d.get("match", {}), ev):
				a["n"] = int(a["n"]) + 1
				st["progress"] = int(a["n"])
		"distinct_pairs":
			# 「有 N 对**不同的**居民之间发生过这样的事」——同一对刷一百次也只算一次
			if _match(d.get("match", {}), ev):
				var k := _pair_key(ev)
				if k != "" and not (a["seen"] as Dictionary).has(k):
					a["seen"][k] = true
					st["progress"] = (a["seen"] as Dictionary).size()
		"distinct_actors":
			# 「有 N 位**不同的**居民参与过这样的事」（include_target=true 时 target 也算参与）
			if _match(d.get("match", {}), ev):
				var ids: Array = [String(ev.get("actor", ""))]
				if bool(d.get("include_target", false)):
					ids.append(String(ev.get("target", "")))
				for who in ids:
					if not (String(who) in NON_AGENT):
						a["seen"][String(who)] = true
				st["progress"] = (a["seen"] as Dictionary).size()
		"distinct_days":
			# 「这样的事发生在 N 个**不同的日子**里」。
			# 存在的理由是一次实测教训：单纯的 count 版「全员到场」在 12/12 个 seed 上都在**第 1 天**就点亮——
			# 开局所有居民就同区，旁观者数一开局即达上限 10（witnesses = 同区全员，Sim.gd:2898），
			# 于是那条判据在「什么都不做的世界」里也恒过（docs/41 §6-★）。按【日】去重才谈得上"又一次聚起来了"。
			if _match(d.get("match", {}), ev):
				var dk := str(int(ev.get("tick", 0)) / int(SimScript.TICKS_PER_DAY))
				if not (a["seen"] as Dictionary).has(dk):
					a["seen"][dk] = true
					st["progress"] = (a["seen"] as Dictionary).size()
		"pair_then":
			# 「同一对居民身上，先发生 first、之后又发生 then」——这是"化解争执""约成一次见面"的形状。
			# 顺序由 event_log 的下标序保证（它就是发生序），不比较浮点、不读时钟。
			var k2 := _pair_key(ev)
			if k2 != "":
				if _match(d.get("first", {}), ev) and not (a["armed"] as Dictionary).has(k2):
					a["armed"][k2] = int(ev.get("tick", 0))
				if (a["armed"] as Dictionary).has(k2) and not (a["hit"] as Dictionary).has(k2) \
						and _match(d.get("then", {}), ev) \
						and int(ev.get("tick", 0)) >= int(a["armed"][k2]) + int(d.get("min_gap", 0)):
					a["hit"][k2] = true
					st["progress"] = (a["hit"] as Dictionary).size()
	if int(st["progress"]) == before:
		return false
	if int(st["progress"]) >= int(st["target"]) and not bool(st["done"]):
		st["done"] = true
		st["done_tick"] = int(ev.get("tick", 0))
		st["done_ev"] = int(ev.get("id", -1))
	return true

## 事件过滤器。空过滤器 = 全匹配（"任何一件事"也是一种条件）。
func _match(f: Dictionary, ev: Dictionary) -> bool:
	if f.is_empty():
		return true
	var t := String(ev.get("type", ""))
	if f.has("type") and not (t in (f["type"] as Array)):
		return false
	if f.has("exclude_type") and (t in (f["exclude_type"] as Array)):
		return false
	if f.has("accepted") and bool(ev.get("accepted", false)) != bool(f["accepted"]):
		return false
	if f.has("note_prefix") and not String(ev.get("note", "")).begins_with(String(f["note_prefix"])):
		return false
	if f.has("min_witnesses") and (ev.get("witnesses", []) as Array).size() < int(f["min_witnesses"]):
		return false
	if f.has("actor") and String(ev.get("actor", "")) != String(f["actor"]):
		return false
	if f.has("between_residents") and bool(f["between_residents"]) and _pair_key(ev) == "":
		return false
	return true

## 无序对键（a<b 定序 ⇒ 与谁先动手无关）。非居民 actor/target 或自指 → ""（调用方据此跳过）。
func _pair_key(ev: Dictionary) -> String:
	var a := String(ev.get("actor", ""))
	var b := String(ev.get("target", ""))
	if (a in NON_AGENT) or (b in NON_AGENT) or a == b:
		return ""
	return (a + PAIR_SEP + b) if a < b else (b + PAIR_SEP + a)

## 事件的稳定标识（与 Sim._log_event 折 event_digest 用的是同一组字段，口径一致便于对读）。
func _ev_key(ev: Dictionary) -> String:
	return "%d:%s:%s:%s:%d:%s:%d" % [int(ev.get("id", 0)), String(ev.get("type", "")),
		String(ev.get("actor", "")), String(ev.get("target", "")),
		(1 if bool(ev.get("accepted", false)) else 0), String(ev.get("subject", "")), int(ev.get("tick", 0))]

# ── 对外读数 ────────────────────────────────────────────────────────────────
## 目标状态的确定性摘要（回放等价断言比的就是它）。
func digest() -> int:
	var h := SimScript.fnv1a32("goals/v1")
	for s in state:
		h = SimScript.fnv1a32_into(h, "%s:%d:%d:%d:%d" % [String(s["id"]), int(s["progress"]),
			(1 if bool(s["done"]) else 0), int(s["done_tick"]), int(s["done_ev"])])
	return h

func done_count() -> int:
	var n := 0
	for s in state:
		if bool(s["done"]):
			n += 1
	return n

## 第一条未达成的目标（= 进度线上的"下一步"）；全达成则返回 {}。
func next_goal() -> Dictionary:
	for s in state:
		if not bool(s["done"]):
			return s
	return {}

## 已达成的目标 id（按定义序），供测试/报告逐 seed 对读。
func done_ids() -> Array:
	var out: Array = []
	for s in state:
		if bool(s["done"]):
			out.append(String(s["id"]))
	return out

# ── 成文（HUD 唯一口径：一行摘要 + 展开面板共用同一份 state）────────────────
## 播报栏顶上的**一行**。刻意只占一行：docs/46 §一 #5 已经在说 chrome 太多，
## 这条进度线不该再加一块常驻面板 —— 展开档默认是关的（J 键 / 点这一行）。
func summary_line() -> String:
	if state.is_empty():
		return ""
	var nx := next_goal()
	var tail := "[color=#7ed957]全部达成[/color]"
	if not nx.is_empty():
		tail = "[color=#cfe8ff]下一步：%s[/color]  [color=#5a6072]%d/%d[/color]" % [
			String(nx["title"]), mini(int(nx["progress"]), int(nx["target"])), int(nx["target"])]
	return "[url=%s][color=#ffd166]◆ 小镇纪事 %d/%d[/color][/url]  %s" % [
		PANEL_META, done_count(), state.size(), tail]

## 展开档的完整清单。**每条恒占一行**（只有"下一步"那条多一行提示）——
## 行数预算是死的：11 条目标 × 2 行会顶出面板，而 RichTextLabel 的 scroll_active=false 只会静默裁掉尾巴。
func panel_text() -> String:
	var out: Array = ["[color=#ffd166]◆ 小镇纪事 —— %d/%d[/color]" % [done_count(), state.size()]]
	var hinted := false
	for s in state:
		if bool(s["done"]):
			out.append("[color=#7ed957]✓ %s[/color]  [color=#5a6072]第 %d 天[/color]" % [
				String(s["title"]), int(s["done_tick"]) / SimScript.TICKS_PER_DAY + 1])
		else:
			out.append("[color=#9aa0b5]○ %s  (%d/%d)[/color]" % [
				String(s["title"]), mini(int(s["progress"]), int(s["target"])), int(s["target"])])
			if not hinted:
				hinted = true
				out.append("   [color=#5a6072]%s[/color]" % String(s["hint"]))
	out.append("[color=#5a6072]J 键 / 点播报栏顶那一行 = 开关本页[/color]")
	return "\n".join(out)

## 达成瞬间推进播报栏的那一行（进度线上唯一的"事件"）。
func toast(i: int) -> String:
	if i < 0 or i >= state.size():
		return ""
	return "[color=#ffd166]◆ 小镇纪事达成：%s[/color]  [color=#5a6072]%s[/color]" % [
		String(state[i]["title"]), String(state[i]["hint"])]
