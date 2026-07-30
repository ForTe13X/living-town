extends RefCounted
## Story.gd — 「小镇故事」：把 Sim.event_log 折成**一条条有头有尾、系在两个人身上的因果弧**。
## 缺口见 docs/47 §二-E2。它与既有的两块东西各差一件事：
##   · 编年史（Main._render_log）是**倒序事件流**——每一行都对，但"谁跟谁怎么走到这一步"永远拼不回来；
##   · 小镇纪事（Goals.gd）是**还差几件**——它有进度没有主角，而且**永不结束**。
##   故事 = **开头 + 中间几幕 + 一个结局**，且**有方向**（谁委屈、谁低头）。
##
## ★ 架构红线（同 D2 / docs/41 §0.1，比这条玩法本身重要得多）：
##   本文件是**对 Sim.event_log 的只读派生**，与 ProbeController / Goals.gd 同一纪律 —— 只读，**绝不写世界状态**。
##   为此本文件：
##     · 不持有 Sim 引用（`sync()` 由调用方把数组喂进来），不调用 Sim 的任何非 static 成员；
##     · 只从事件字典**取值**，绝不写回（GDScript 的 Dictionary 是引用类型，写一个字段就是改 Sim 的账本）；
##     · 不抽 RNG、**不读墙钟、也不读 Sim.tick_no** —— 见下面「冷场只看事件时刻」那一条；
##     · 名字不在这里查（`nm` 由调用方传 Callable 进来）⇒ 本类在没有 autoload 的环境里也能单测。
##
## 折叠是**纯函数**：`state' = fold(state, event)`。于是「实时增量折」≡「从空态重算全量」。
##
## ⚠️ 「live == replay」**单独没有判别力**（D2 实测：一个什么都不记的 tracker 平凡通过）。
##    故本类同时维护 `chain`（折进来的事件序列的滚动见证），并在 scenes/story_test.tscn 里配了
##    **只喂 greet 的空对照** + **手写因果链的正对照**：前者必须 0 条故事，后者必须给出指定的结局与幕次。
##
## ★ 冷场（"这段就这么冷了下来"）**只看事件时刻，不看当前 tick**。
##   若用 Sim.tick_no 判冷，"实时跑到 T" 与 "goto_tick(T) 重演" 会在**没有事件的那段真空里**分叉
##   —— 那正是回放红线要挡的东西。代价是：一段冷掉的弧要等**下一个事件**（任意一对、任意类型）来推
##   才会被记成 closed；这是刻意的，且它对 live/replay 两条路完全一致。
##
## ★ 冷场阈值不是拍脑袋：`Sim.DRAMA_ERUPT_AFTER = 1200`（~5 天）是**引擎自己的导演定时器**——
##   一段没说开的怨气到点会被安排一次对质。但**光读代码定不出这个数**（我第一版就是这么定的，取 1440，错了）——
##   实测才知道要多大：见 grudge 的 `cold` 字段处那一段（1440 会砍掉 48% 的和解，3600 只砍 4%）。

const SimScript = preload("res://scripts/Sim.gd")   # 只为 static 的 fnv1a32 / fnv1a32_into / TICKS_PER_DAY

## 非居民的 actor/target 占位（election 的 "town"、缺字段的 ""）：故事必须系在**两个人**身上。
const NON_AGENT := ["", "town"]
const KEY_SEP := ">"                  # 有向键 A>B（居民 id 里没有 '>'）；"谁委屈谁低头"是故事的一半
const ARC_SEP := "#"

## 面板/点播报栏那一行用的 meta（Main._on_log_meta 据此分流；居民 id 不会长这样）。
const PANEL_META := "__story__"

## 保留上限。**只封【已收场】的那一半**，进行中的一条都不丢。
##
## ★第一版封的是「弧总数 ≤ 128」，被 N=48 的规模实测直接打死：
##   seed 1 · 48 居民 · 20 天 ⇒ 开过 238 段、进行中 **169** 段。进行中的一条都不能丢（它的结局到了会没处安放），
##   于是那 128 的额度**全被进行中的占满**，裁剪把 **69 段已收场的故事一条不剩地全丢了** ——
##   面板上"近来收场的"整节是空的，而镇上明明刚讲完 69 段。
##   （12 居民那一档完全看不出来：14 天 0 次裁剪、60 天也只裁掉些 promise。**只在出货规模上才现形**。）
## 正确的界限是：进行中的弧**本来就被世界封住了**（每个 (弧种, 有向对) 至多一条），而已收场的会无限堆。
## 32 的依据：面板只讲最近 12 段里最有戏的 3 段（recent_closed 的窗口），32 给了两倍余量。
## 它在 12 居民 60 天、48 居民 20 天两档都会真的触发 ⇒ "裁剪之后 live 仍 ≡ replay"是被跑到过的，不是死代码。
const MAX_CLOSED := 32
const MAX_BEATS := 6                  # 每条弧最多留 6 幕，其余只计数（面板一条弧本来也放不下更多行）

# ── 弧的文法（数据在这里，不另开 json）──────────────────────────────────────
## brief 只给了本棒两个文件（Story.gd / Main.gd），故文法留在代码里而不是新开 data/stories.json。
## 代价写清楚：改文案要改 .gd。收益是没有"缺文件即半个系统"的第二条分支要守。
##
## 每条 def：
##   open      开头匹配器（无同键在跑的弧时才开）           open_text 开头那一句
##   beats     中间幕（可重复，按发生序）                    dir: fwd(默认)/rev/any
##   ends      结局（先匹配到的那条收场）                    tone: warm/cold/grey → 面板配色
##   aside     旁支计数：actor==A 且 subject==B 的事件（"背后议论"）——**编年史里绝对拼不出来的那一维**
##   cold      多少 tick 没有下文算冷场（0 = 永不冷）
##
## dir 的意义（实测口径，全部对着 Sim.gd 核过）：
##   conflict / confront / rally_oust  actor=委屈方 A，target=冒犯方 B      → fwd
##   apologize                          actor=冒犯方 B，target=委屈方 A      → rev（**方向是反的**）
##   invite / meet                      actor=发起方，target=被约方          → fwd（commitment a/b 同序）
##   confide                            actor=托付者，target=被托付者        → fwd
##   betray                             actor=说漏的人，target=被辜负的人    → rev
##   pact formed                        actor/target 任意一侧               → any
##   pact dissolved                     actor=受害方，target=白拿的人        → any（与 formed 未必同序）
const ARCS := [
	{
		"id": "grudge", "label": "梁子", "tone": "cold",
		"open": {"type": ["conflict"]},
		"open_text": "%A 对 %B 积起了怨气",
		"beats": [
			{"id": "heard", "m": {"type": ["confront"], "accepted": true}, "text": "%A 当面把话挑明，%B 听了进去"},
			{"id": "denied", "m": {"type": ["confront"], "accepted": false}, "text": "%A 找 %B 理论，%B 不认 —— 事情闹大了"},
			{"id": "rally", "m": {"type": ["rally_oust"], "accepted": true}, "text": "%A 拉上自己人，一起给 %B 施压"},
			{"id": "alone", "m": {"type": ["rally_oust"], "accepted": false}, "text": "%A 想拉人排挤 %B，没人应和"},
			{"id": "rebuff", "m": {"type": ["apologize"], "accepted": false}, "dir": "rev", "text": "%B 来道了歉，%A 一时还没法原谅"},
			# E1（Wave E 产出闭环）的 shortage：actor=扑了空的人、target=被怪的那个岗位的人，
			# **与怨气弧的有向键同序**（A 委屈 → B 冒犯），所以它天然就是这条弧的一幕，不需要新文法。
			# 这一幕是本棒对 E1 的交接答复：shortage 是那四类里唯一有戏的一条，但它在 Sim 侧不 emit
			# social_event ⇒ 塞进播报会造出"看观看路径的编年史"（见 Main.FEED_SKIP 那段）。
			# 折叠这条路没有这个问题：live 与 replay 按构造同值。
			{"id": "empty", "m": {"type": ["shortage"]}, "text": "%A 又扑了个空 —— 镇上断了货，这笔账记在 %B 头上"},
		],
		"ends": [
			{"id": "mended", "m": {"type": ["apologize"], "accepted": true}, "dir": "rev", "tone": "warm",
			 "text": "%B 低了头，%A 原谅了 —— 这段梁子解开了", "short": "和解了"},
		],
		"aside": {"type": ["gossip_rep"]},
		"aside_text": "这中间 %A 在旁人面前说了 %d 次 %B 的不是",
		# 3600 = 15 天。**这个数是量出来的，而且第一版（1440）被同一次测量证伪了**：
		# 一段最终和解了的怨气，其"相邻两幕最大间隔"的实测分布（8 seed × 60 天，n=230）是
		#   中位 1400 · p75 2132 · p90 3051 · p95 3557 · max 6263
		# ⇒ cold=1440 只保得住 **52%** 的和解，其余 48% 的 apologize+ 会落在一段已被判死的弧后面、无处安放；
		#   cold=2400 → 80%；**cold=3600 → 96%**；4800 → 100%。取 3600。
		# 顺带纠正一条我自己先前写在这里的推理：拿 DRAMA_ERUPT_AFTER=1200 当下限是**不够**的 ——
		# 导演定时器只保证"到点安排一次对质"，而"对质→道歉"本身还要再等一段（中位又是约 1000 tick）。
		"cold": 3600,
		"cold_text": "往后谁也没再提 —— 这段梁子就这么冷着", "cold_short": "冷了",
	},
	{
		"id": "promise", "label": "约定", "tone": "grey",
		"open": {"type": ["invite"], "accepted": true},
		"open_text": "%A 约了 %B 稍后见面",
		"beats": [],
		"ends": [
			{"id": "kept", "m": {"type": ["meet"], "accepted": true}, "tone": "warm", "text": "两人如约见上了面", "short": "如约"},
			{"id": "broken", "m": {"type": ["meet"], "accepted": false}, "tone": "cold", "text": "约会泡了汤 —— 有人没来", "short": "爽约"},
		],
		"aside": {},
		"aside_text": "",
		"cold": 240,
		"cold_text": "这个约就这么不了了之", "cold_short": "没下文",
	},
	{
		"id": "secret", "label": "心事", "tone": "grey",
		"open": {"type": ["confide"]},
		"open_text": "%A 把一桩心事托付给了 %B",
		"beats": [
			{"id": "more", "m": {"type": ["confide"]}, "text": "%A 又对 %B 说了一桩"},
			{"id": "aid", "m": {"type": ["aid"], "accepted": true}, "dir": "any", "text": "两人之间还多了一次雪中送炭"},
		],
		"ends": [
			{"id": "leaked", "m": {"type": ["betray"]}, "dir": "rev", "tone": "cold",
			 "text": "%B 把这桩心事说了出去 —— %A 是从别人嘴里听回来的", "short": "被说了出去"},
			{"id": "slipped", "m": {"type": ["leak"]}, "dir": "rev", "tone": "cold",
			 "text": "%B 在旁人面前说漏了嘴", "short": "说漏了嘴"},
		],
		"aside": {},
		"aside_text": "",
		"cold": 0,
		"cold_text": "", "cold_short": "",
	},
	{
		"id": "pact", "label": "盟约", "tone": "warm",
		"open": {"type": ["pact"], "note_prefix": "formed"},
		"open_text": "%A 与 %B 结成了互助盟约",
		"beats": [
			{"id": "aid", "m": {"type": ["aid"], "accepted": true}, "dir": "any", "text": "有人在对方难处时搭了把手"},
			{"id": "met", "m": {"type": ["meet"], "accepted": true}, "dir": "any", "text": "两人又如约见了一面"},
		],
		"ends": [
			{"id": "dissolved", "m": {"type": ["pact"], "note_prefix": "dissolved"}, "dir": "any", "tone": "cold",
			 "text": "盟约散了 —— 一直只拿不给", "short": "散了"},
		],
		"aside": {},
		"aside_text": "",
		"cold": 0,
		"cold_text": "", "cold_short": "",
	},
]

# ── 状态 ────────────────────────────────────────────────────────────────────
var arcs: Array = []          # 所有弧实例（按【开场序】；已收场的会被 MAX_CLOSED 从头裁）
var _open: Dictionary = {}    # "arcid#A>B" → 弧实例的**引用**（故裁剪 arcs 不会打断这条索引）
var _cursor := 0              # 已折到 event_log 的哪个下标
var _last_tick := 0           # 折进来的最后一个事件的 tick（冷场判定的唯一时间源；进 digest）
var _dropped := 0             # 被 MAX_CLOSED 裁掉的弧数（进 digest：裁剪也必须是可对拍的）
var chain := 0                # 折叠见证链
var _serial := 0              # 弧序号（稳定身份，进 digest；不受裁剪影响）
## 已折进来的**最后一个**事件的稳定标识 = "喂进来的还是不是同一条时间线"的 O(1) 见证。
## 论证与实测数字见 `Goals.gd` 同名字段（两处刻意同构；W1 收口见 docs/47 §三·七）。
## 一句话：`]` 前向拖动让日志**变长**，而重演在非 logic 后端 / 有玩家时会给出**前缀已经不同**的一份，
## 只看长度会把新尾巴接到旧前缀上。故事比目标更怕这个 —— 目标只会前进，**弧会收场**。
## 诚实标注：必要非充分（见 Goals.gd）；充分那一道是 `recompute`，Main._rebuild_feed 走的正是它。
var _anchor := ""
var resyncs := 0              # 因锚不对而强制整份重折的次数（纯观测；**不进 digest**）
## 终身账（**不受 MAX_CLOSED 裁剪影响**）："<arcid>:@open" → 开过几段；"<arcid>:<endid>" → 各结局各几段。
## ★它是被实测逼出来的，不是设计出来的：第一版只从 `arcs` 里数结局，60 天单 seed 裁掉 36-125 条已收场的弧，
##   于是"和解覆盖率"量出 11.2%（14 天无裁剪时是 90.3%）——**分子被裁剪偷走了，分母没有**。
##   docs/41 §5「注意分母」的同一个失败模板；面板上那句"已收场 N 段"也曾是同一个坏数。
var tally: Dictionary = {}
## 面板重画的**脏标记**：任何一条弧被开/推进/收场/裁掉时 +1。
## 存在的理由是 docs/46 §二·六 那笔账（真机 FPS 88 → 11）：面板一开就每 tick 排一次 128 条弧是白烧的。
## 它是折叠的纯函数（同一串事件必得同一个值），但**刻意不进 digest** —— 它是缓存令牌，不是状态。
var rev := 0

# ── 生命周期 ────────────────────────────────────────────────────────────────
## 清空。**时间线换了就必须调**（goto_tick 回拨 / 读档 / 换种子）——同 Goals.reset 的纪律。
func reset() -> void:
	arcs = []
	_open = {}
	_cursor = 0
	_last_tick = 0
	_dropped = 0
	chain = 0
	_anchor = ""
	_serial = 0
	tally = {}
	rev = 0

## 增量折到 `events` 末尾，返回**本次新收场**的弧（调用方拿去播报——故事只有在有了结局之后才是故事）。
## 只读 `events`：不排序、不改元素、不持有引用。
func sync(events: Array) -> Array:
	var fresh: Array = []
	# 时间线换了 → 从头折。两种换法都要认（`or` 短路 ⇒ 变短那一支不会去索引越界的下标）：
	#   ①日志**变短**（往回 scrub / 读档 / 换种子）；②日志没变短但**前缀已经不是那一条**（见 `_anchor`）。
	if _cursor > 0 and (events.size() < _cursor or _ev_key(events[_cursor - 1]) != _anchor):
		reset()
		resyncs += 1
	while _cursor < events.size():
		var ev: Dictionary = events[_cursor]
		_cursor += 1
		_anchor = _ev_key(ev)                     # 与 chain 共用同一次 _ev_key ⇒ 热循环里零额外开销
		chain = SimScript.fnv1a32_into(chain, _anchor)
		var t := int(ev.get("tick", 0))
		var n0 := fresh.size()
		if t > _last_tick:
			# 冷场清扫：只在**跨到新的一 tick** 时做一次（同一 tick 内的事件顺序因此不影响谁先冷）。
			_sweep_cold(t, fresh)
			_last_tick = t
		_fold(ev, fresh)
		if fresh.size() > n0:
			_trim()                               # 只有真的收场了才可能超上限（见 _trim）
	return fresh

## 重算口径：从空态把 `events` 全量折一遍。测试的重算臂/回放臂用它对拍实时臂。
func recompute(events: Array) -> Array:
	reset()
	return sync(events)

# ── 折叠核心（纯函数）───────────────────────────────────────────────────────
func _fold(ev: Dictionary, fresh: Array) -> void:
	# aside 走的是 (actor, subject)，与 target 无关 ⇒ 必须在下面那道"两个人"的闸之前先给它一次机会。
	_fold_aside(ev)
	var a := String(ev.get("actor", ""))
	var b := String(ev.get("target", ""))
	if (a in NON_AGENT) or (b in NON_AGENT) or a == b:
		return                        # 故事系在两个人身上：election(town) 这类非人 actor、自指事件不进任何弧
	var fwd := a + KEY_SEP + b
	var bwd := b + KEY_SEP + a       # 命名刻意不叫 rev：本类有个成员 rev（面板脏标记），同名会被 GDScript 判为遮蔽
	for di in ARCS.size():
		var d: Dictionary = ARCS[di]
		var did := String(d["id"])
		# ① 结局：先看这条弧有没有在跑，再看这个事件是不是它的结局。
		var closed := false
		for e in (d["ends"] as Array):
			var k := _key_for(did, fwd, bwd, String(e.get("dir", "fwd")))
			if k == "" or not _open.has(k):
				continue
			if not _match(e["m"], ev):
				continue
			var arc: Dictionary = _open[k]
			_close(arc, String(e["id"]), String(e.get("tone", "grey")), ev)
			_open.erase(k)
			fresh.append(arc)
			closed = true
			break
		if closed:
			continue
		# ② 中间幕
		var hit := false
		for bt in (d["beats"] as Array):
			var k2 := _key_for(did, fwd, bwd, String(bt.get("dir", "fwd")))
			if k2 == "" or not _open.has(k2):
				continue
			if not _match(bt["m"], ev):
				continue
			_beat(_open[k2], String(bt["id"]), ev)
			hit = true
			break
		if hit:
			continue
		# ③ 开头：同【有向】键还没有弧在跑，才开新的一条（否则同一对会开出一串重复的开头）。
		#   ★刻意只挡同向、不挡反向：`Sim._find_conflict` 是**有方向的**（`c.a==a and c.b==b`），
		#     "阿雅怨本" 与 "本怨阿雅" 在引擎里就是两段各自独立的冲突 —— 合成一段是把两个故事讲丢一个。
		var k3 := did + ARC_SEP + fwd
		if not _open.has(k3) and _match(d["open"], ev):
			_start(di, a, b, ev)

## 旁支：actor 对**第三方**议论 subject（gossip_rep）。它不改弧的进程，只累加一个计数——
## 这一维正是倒序事件流拼不回来的东西：编年史里每一条 gossip_rep 都是孤立的一行。
func _fold_aside(ev: Dictionary) -> void:
	var a := String(ev.get("actor", ""))
	var s := String(ev.get("subject", ""))
	if (a in NON_AGENT) or (s in NON_AGENT) or a == s:
		return
	var k := a + KEY_SEP + s
	for di in ARCS.size():
		var d: Dictionary = ARCS[di]
		var f: Dictionary = d["aside"]
		if f.is_empty():
			continue
		var kk := String(d["id"]) + ARC_SEP + k
		if _open.has(kk) and _match(f, ev):
			var arc: Dictionary = _open[kk]
			arc["aside"] = int(arc["aside"]) + 1

## 冷场清扫：跨到 tick `t` 时，把"上一幕之后已经 cold 个 tick 没有下文"的弧收场。
func _sweep_cold(t: int, fresh: Array) -> void:
	var dead: Array = []
	for k in _open:
		var arc: Dictionary = _open[k]
		var cold := int((ARCS[int(arc["def"])] as Dictionary)["cold"])
		if cold > 0 and t - int(arc["last"]) > cold:
			dead.append(k)
	for k in dead:
		var arc2: Dictionary = _open[k]
		# 冷场的收场时刻记成"最后一幕 + cold"，而不是"发现它冷了的那一刻"——
		# 否则同一段历史在不同的事件疏密下会记出不同的收场日（而事件疏密与观看路径无关，但与冷场发现点有关）。
		arc2["closed"] = true
		arc2["end"] = "cold"
		arc2["tone"] = "cold"
		arc2["t1"] = int(arc2["last"]) + int((ARCS[int(arc2["def"])] as Dictionary)["cold"])
		arc2["ev1"] = -1
		_bump(String((ARCS[int(arc2["def"])] as Dictionary)["id"]) + ":cold")
		_open.erase(k)
		fresh.append(arc2)

func _start(di: int, a: String, b: String, ev: Dictionary) -> void:
	var t := int(ev.get("tick", 0))
	var arc := {
		"n": _serial, "def": di, "a": a, "b": b,
		"t0": t, "ev0": int(ev.get("id", -1)),
		"beats": [], "extra": 0, "aside": 0, "last": t,
		"closed": false, "end": "", "tone": "grey", "t1": -1, "ev1": -1,
	}
	_serial += 1
	arcs.append(arc)
	_open[String((ARCS[di] as Dictionary)["id"]) + ARC_SEP + a + KEY_SEP + b] = arc
	_bump(String((ARCS[di] as Dictionary)["id"]) + ":@open")

func _bump(k: String) -> void:
	tally[k] = int(tally.get(k, 0)) + 1
	rev += 1

func _beat(arc: Dictionary, bid: String, ev: Dictionary) -> void:
	var t := int(ev.get("tick", 0))
	arc["last"] = t
	rev += 1
	if (arc["beats"] as Array).size() < MAX_BEATS:
		(arc["beats"] as Array).append([bid, t, int(ev.get("id", -1))])
	else:
		arc["extra"] = int(arc["extra"]) + 1     # 超出的只计数：一条弧在面板上本来也放不下更多行

func _close(arc: Dictionary, end_id: String, tone: String, ev: Dictionary) -> void:
	var t := int(ev.get("tick", 0))
	arc["closed"] = true
	arc["end"] = end_id
	arc["tone"] = tone
	arc["t1"] = t
	arc["ev1"] = int(ev.get("id", -1))
	arc["last"] = t
	_bump(String((ARCS[int(arc["def"])] as Dictionary)["id"]) + ":" + end_id)

## 保留上限：只丢**已收场**里最老的几条，直到留下的已收场数 ≤ MAX_CLOSED。进行中的一条都不丢。
## 纯按折叠序 ⇒ 重算与增量折裁掉的必然是同一批（回放等价靠这一条）。
## 只在**真有弧收场**的那一步调用（见 sync）：否则每个事件都要扫一遍 arcs，纯属白烧。
func _trim() -> void:
	var kept := 0
	for arc in arcs:
		if bool(arc["closed"]):
			kept += 1
	if kept <= MAX_CLOSED:
		return
	var need := kept - MAX_CLOSED
	var keep: Array = []
	for arc in arcs:
		if need > 0 and bool(arc["closed"]):
			need -= 1
			_dropped += 1
			continue
		keep.append(arc)
	arcs = keep

## 事件过滤器。空过滤器 = 全匹配。字段与 Goals._match 同名同义（两处口径故意保持一致）。
func _match(f: Dictionary, ev: Dictionary) -> bool:
	if f.is_empty():
		return true
	if f.has("type") and not (String(ev.get("type", "")) in (f["type"] as Array)):
		return false
	if f.has("accepted") and bool(ev.get("accepted", false)) != bool(f["accepted"]):
		return false
	if f.has("note_prefix") and not String(ev.get("note", "")).begins_with(String(f["note_prefix"])):
		return false
	return true

## dir → 要查的那把键。"any" 时先查正向、再查反向（两侧都开着是不可能的：③ 已经互斥了）。
func _key_for(did: String, fwd: String, rev: String, dir: String) -> String:
	match dir:
		"rev": return did + ARC_SEP + rev
		"any":
			var k := did + ARC_SEP + fwd
			return k if _open.has(k) else did + ARC_SEP + rev
		_: return did + ARC_SEP + fwd

## 事件的稳定标识（与 Sim._log_event 折 event_digest、与 Goals._ev_key 用的是同一组字段）。
func _ev_key(ev: Dictionary) -> String:
	return "%d:%s:%s:%s:%d:%s:%d" % [int(ev.get("id", 0)), String(ev.get("type", "")),
		String(ev.get("actor", "")), String(ev.get("target", "")),
		(1 if bool(ev.get("accepted", false)) else 0), String(ev.get("subject", "")), int(ev.get("tick", 0))]

# ── 对外读数 ────────────────────────────────────────────────────────────────
## 故事状态的确定性摘要（回放等价断言比的就是它 + chain）。
func digest() -> int:
	var h := SimScript.fnv1a32("story/v1")
	h = SimScript.fnv1a32_into(h, "%d:%d:%d:%d" % [_last_tick, _dropped, _serial, arcs.size()])
	# 终身账也进摘要。按 **ARCS 的书写序**遍历（而不是 Dictionary 的插入序）：
	# 插入序虽然对同一串事件也是确定的，但它是"哪个结局先出现"的函数 —— 换个 seed 就换一种顺序，
	# 于是这个摘要就多了一条与状态无关的自由度。写死成静态序，摘要只是状态的函数。
	for d in ARCS:
		var did := String(d["id"])
		h = SimScript.fnv1a32_into(h, "%s:@open:%d" % [did, int(tally.get(did + ":@open", 0))])
		for e in (d["ends"] as Array):
			h = SimScript.fnv1a32_into(h, "%s:%s:%d" % [did, String(e["id"]), int(tally.get(did + ":" + String(e["id"]), 0))])
		h = SimScript.fnv1a32_into(h, "%s:cold:%d" % [did, int(tally.get(did + ":cold", 0))])
	for arc in arcs:
		h = SimScript.fnv1a32_into(h, "%d:%s:%s:%s:%d:%d:%d:%d:%s:%d:%d:%d" % [
			int(arc["n"]), String((ARCS[int(arc["def"])] as Dictionary)["id"]),
			String(arc["a"]), String(arc["b"]), int(arc["t0"]), int(arc["ev0"]),
			int(arc["t1"]), int(arc["ev1"]), String(arc["end"]),
			(arc["beats"] as Array).size(), int(arc["extra"]), int(arc["aside"])])
		for bt in (arc["beats"] as Array):
			h = SimScript.fnv1a32_into(h, "%s:%d:%d" % [String(bt[0]), int(bt[1]), int(bt[2])])
	return h

func def_of(arc: Dictionary) -> Dictionary:
	return ARCS[int(arc["def"])]

func open_count() -> int:
	return _open.size()

## 已收场的段数 —— **终身口径**（含被 MAX_CLOSED 裁掉的）。面板上那句"已收场 N 段"必须用它：
## 用 `arcs` 里数出来的那个数会在长跑里悄悄往回走（裁一条少一条），玩家看到的是"故事越讲越少"。
func closed_count() -> int:
	var n := 0
	for d in ARCS:
		var did := String(d["id"])
		for e in (d["ends"] as Array):
			n += int(tally.get(did + ":" + String(e["id"]), 0))
		n += int(tally.get(did + ":cold", 0))
	return n

## 仍留在 `arcs` 里的已收场段数（面板能翻到的那些）。与 closed_count 的差 = 被裁掉的。
func closed_kept() -> int:
	var n := 0
	for arc in arcs:
		if bool(arc["closed"]):
			n += 1
	return n

## 已收场的弧，**最近收场的在前**。
func closed_arcs() -> Array:
	var out: Array = []
	for arc in arcs:
		if bool(arc["closed"]):
			out.append(arc)
	out.sort_custom(func(x, y): return int(x["t1"]) > int(y["t1"]) if int(x["t1"]) != int(y["t1"]) else int(x["n"]) > int(y["n"]))
	return out

## 进行中的弧，**最近有动静的在前**。
func open_arcs() -> Array:
	var out: Array = []
	for arc in arcs:
		if not bool(arc["closed"]):
			out.append(arc)
	out.sort_custom(func(x, y): return int(x["last"]) > int(y["last"]) if int(x["last"]) != int(y["last"]) else int(x["n"]) > int(y["n"]))
	return out

## 与某人有关的弧（他是主角之一）。按"戏份"排，同分才按最近有动静排 —— 理由见 `_drama`。
func arcs_of(who: String) -> Array:
	var out: Array = []
	for arc in arcs:
		if String(arc["a"]) == who or String(arc["b"]) == who:
			out.append(arc)
	out.sort_custom(_by_drama)
	return out

## 「戏份」= 中间幕数 ×2 + 冷结局加 2。
## ★这条排序不是修辞，是被一张出图逼出来的（R10 全帧眼验，docs/41 §6）：
##   第一版按纯粹的"最近收场"取头条，于是面板把整块最贵的版面给了
##   「第27天 可可约了铁牛稍后见面 / 第27天 两人如约见上了面」——**一段没有中间的故事**。
##   实测口径解释了为什么这不是偶然：6 seed × 60 天里 promise 收场 539 段、grudge 只有 126 段，
##   而 promise 按构造恒为 0 中间幕（invite→meet，MEET_HORIZON=40 tick 内必出结果）
##   ⇒ 「最近收场的一段」有 ~81% 的概率是一段**编年史已经原样播过两行**的东西。
##   加 2 给冷结局：爽约/冷战比"如约见面"更有戏，这一条同样是从 kept=532 vs broken=7 的悬殊里来的。
func _drama(arc: Dictionary) -> int:
	return ((arc["beats"] as Array).size() + int(arc["extra"])) * 2 + (2 if String(arc["tone"]) == "cold" else 0)

func _by_drama(x: Dictionary, y: Dictionary) -> bool:
	var dx := _drama(x)
	var dy := _drama(y)
	if dx != dy:
		return dx > dy
	if int(x["last"]) != int(y["last"]):
		return int(x["last"]) > int(y["last"])
	return int(x["n"]) > int(y["n"])

## 近来收场的、**最值得讲的**几段：先按收场时刻取最近 `window` 段（保证"近来"），再在其中按戏份排。
## 两步而不是一步：只按戏份排会把开局那段最跌宕的故事永远钉在头条上，玩家再玩十天也换不掉。
func recent_closed(window: int = 12) -> Array:
	var cl := closed_arcs()
	var win: Array = cl.slice(0, mini(window, cl.size()))
	win.sort_custom(_by_drama)
	return win

## 逐弧种统计（测试打矩阵用）。
##   opened/closed/ends = **终身口径**（不受 MAX_CLOSED 裁剪影响）；open/kept = 当下还留在 arcs 里的。
func stats() -> Dictionary:
	var out: Dictionary = {}
	for d in ARCS:
		var did := String(d["id"])
		var ends: Dictionary = {}
		var closed := 0
		for e in (d["ends"] as Array):
			var c := int(tally.get(did + ":" + String(e["id"]), 0))
			if c > 0:
				ends[String(e["id"])] = c
			closed += c
		var cc := int(tally.get(did + ":cold", 0))
		if cc > 0:
			ends["cold"] = cc
		closed += cc
		out[did] = {"opened": int(tally.get(did + ":@open", 0)), "closed": closed, "ends": ends,
			"open": 0, "kept": 0}
	for arc in arcs:
		var row: Dictionary = out[String((ARCS[int(arc["def"])] as Dictionary)["id"])]
		if bool(arc["closed"]):
			row["kept"] = int(row["kept"]) + 1
		else:
			row["open"] = int(row["open"]) + 1
	return out

# ── 成文（唯一口径：播报 / 面板 / 卷宗共用同一批函数）──────────────────────
## `nm` = Callable(id) -> 中文名。本类不认识 Sim，名字由调用方给（也让单测能喂假名字）。
const TONE_COLOR := {"warm": "#7ed957", "cold": "#ff8c42", "grey": "#9aa0b5"}

func _day(t: int) -> int:
	return t / int(SimScript.TICKS_PER_DAY) + 1

func _who(id: String, nm: Callable) -> String:
	var n := String(nm.call(id))
	if n == "":
		n = id
	return "[url=%s]%s[/url]" % [id, n]           # 点名字 → 选中并把镜头飞过去（与编年史同一条 meta 路）

func _fill(tpl: String, arc: Dictionary, nm: Callable) -> String:
	return tpl.replace("%A", _who(String(arc["a"]), nm)).replace("%B", _who(String(arc["b"]), nm))

## 一条弧的**全文**：开头 + 中间几幕 + 结局（每幕一行，行首是第几天）。这就是"故事"与"事件流"的差别。
func narrate(arc: Dictionary, nm: Callable) -> Array:
	var d := def_of(arc)
	var out: Array = ["[color=#5a6072]第%d天[/color] %s" % [_day(int(arc["t0"])), _fill(String(d["open_text"]), arc, nm)]]
	for bt in (arc["beats"] as Array):
		var txt := ""
		for cand in (d["beats"] as Array):
			if String(cand["id"]) == String(bt[0]):
				txt = String(cand["text"])
				break
		if txt != "":
			out.append("[color=#5a6072]第%d天[/color] %s" % [_day(int(bt[1])), _fill(txt, arc, nm)])
	if int(arc["extra"]) > 0:
		out.append("[color=#5a6072]……中间还有 %d 幕[/color]" % int(arc["extra"]))
	if int(arc["aside"]) > 0 and String(d["aside_text"]) != "":
		out.append("[color=#5a6072]%s[/color]" % _fill(String(d["aside_text"]), arc, nm).replace("%d", str(int(arc["aside"]))))
	if bool(arc["closed"]):
		var etxt := String(d["cold_text"]) if String(arc["end"]) == "cold" else _end_text(d, String(arc["end"]))
		out.append("[color=%s]第%d天 · %s[/color]" % [
			TONE_COLOR.get(String(arc["tone"]), "#9aa0b5"), _day(int(arc["t1"])), _fill(etxt, arc, nm)])
	else:
		out.append("[color=#9aa0b5]（还没有结局）[/color]")
	return out

func _end_text(d: Dictionary, end_id: String) -> String:
	for e in (d["ends"] as Array):
		if String(e["id"]) == end_id:
			return String(e["text"])
	return ""

## 一行摘要：`◇ 梁子 · 阿雅与本 第3天→第6天 和解了`。播报/清单/卷宗共用。
func one_line(arc: Dictionary, nm: Callable) -> String:
	var d := def_of(arc)
	var head := "[color=%s]◇ %s[/color] %s与%s" % [
		TONE_COLOR.get(String(arc["tone"]) if bool(arc["closed"]) else String(d["tone"]), "#9aa0b5"),
		String(d["label"]), _who(String(arc["a"]), nm), _who(String(arc["b"]), nm)]
	if bool(arc["closed"]):
		var etxt := String(d["cold_text"]) if String(arc["end"]) == "cold" else _end_text(d, String(arc["end"]))
		return "%s [color=#5a6072]第%d→%d天[/color] %s" % [head, _day(int(arc["t0"])), _day(int(arc["t1"])),
			_strip(_fill(etxt, arc, nm))]
	return "%s [color=#5a6072]第%d天起 · %d幕[/color]" % [head, _day(int(arc["t0"])),
		(arc["beats"] as Array).size() + int(arc["extra"]) + 1]

## 摘要行里不要嵌 [url]（一行里塞四个可点区域，手机上根本点不准）——只在全文里保留可点名字。
func _strip(s: String) -> String:
	var out := ""
	var depth := 0
	var i := 0
	while i < s.length():
		if s.substr(i, 5) == "[url=":
			depth += 1
			var j := s.find("]", i)
			i = (j + 1) if j >= 0 else s.length()
			continue
		if s.substr(i, 6) == "[/url]":
			depth = maxi(0, depth - 1)
			i += 6
			continue
		out += s[i]
		i += 1
	return out

## 收场那一刻推进播报栏的一行（**故事只有在有了结局之后才播**——这就是它与编年史的分界）。
func toast(arc: Dictionary, nm: Callable) -> String:
	return "[url=%s]%s[/url]" % [PANEL_META, one_line(arc, nm)]

## 展开档面板。行数预算是死的（D2 的教训：RichTextLabel 的 scroll_active=false 只会静默裁掉尾巴）——
## 故这里按 `budget` 行数**自上而下**排，排不下的直接不排，绝不让最后一行悄悄消失。
func panel_text(nm: Callable, budget: int = 16) -> String:
	var out: Array = []
	var closed := recent_closed()
	var opened := open_arcs()
	out.append("[color=#ffd166]◇ 小镇故事 —— 在讲 %d 段 · 已收场 %d 段[/color]" % [opened.size(), closed_count()])
	if closed.is_empty() and opened.is_empty():
		out.append("[color=#9aa0b5]镇上还没有故事 —— 得先有人结下梁子、约上一面，或托付一桩心事。[/color]")
		out.append("[color=#5a6072]K 键 / 点播报里的 ◇ 那一行 = 开关本页[/color]")
		return "\n".join(out)
	# 最近收场的那一段：**讲全文**。故事的价值全在这几行里，其余都是索引。
	if not closed.is_empty():
		out.append("")
		out.append("[color=#cfd3e0]近来收场的[/color]")   # 不写「刚刚」：这里排的是最近 12 段里戏份最足的，不是时间上最新的那一段
		for ln in narrate(closed[0], nm):
			out.append(ln)
		for i in range(1, mini(3, closed.size())):
			if out.size() >= budget - 3:
				break
			out.append(one_line(closed[i], nm))
	if not opened.is_empty() and out.size() < budget - 2:
		out.append("")
		out.append("[color=#cfd3e0]还在往下走[/color]")
		for arc in opened:
			if out.size() >= budget - 1:
				break
			out.append(one_line(arc, nm))
	out.append("[color=#5a6072]K 键 / 点播报里的 ◇ 那一行 = 开关本页[/color]")
	return "\n".join(out)

## 卷宗里的「他的故事」小节（最多 `n` 行）。**故事系在人身上**，这是它落到具体一个人身上的样子。
##
## ★这里**不能**复用 one_line —— R10 全帧眼验抓到的：观察台正文只有 286px 宽，
##   one_line（"◇ 梁子 阿本与可可 第13→17天 可可 低了头，阿本 原谅了 —— 这段梁子解开了"）在那里**折成两行**，
##   于是"我只加了 3 行"实际吃掉 6 行；而 `_panel_text` 的行数预算 OBS_MAX_LINES 数的是**逻辑行**，
##   多出来的那 3 行是从底下静默掉出去的（RichTextLabel 的 scroll_active=false 不报错、只是看不见）。
##   ——D2 那条"展开档没被验收覆盖"的同一个坑，换了个面板复发。
##   故这里用**短结局标签**（ends[].short / cold_short），实测宽度约 220px < 270px 可用宽 ⇒ 保证一行一行。
func person_lines(who: String, nm: Callable, n: int = 2) -> Array:
	var out: Array = []
	for arc in arcs_of(who):
		if out.size() >= n:
			break
		var d := def_of(arc)
		var other := String(arc["b"]) if String(arc["a"]) == who else String(arc["a"])
		var role := "与" if String(arc["a"]) == who else "被"      # 有向：他是起头的那个，还是被冲着来的那个
		var head := "[color=%s]◇ %s[/color] %s%s" % [
			TONE_COLOR.get(String(arc["tone"]) if bool(arc["closed"]) else String(d["tone"]), "#9aa0b5"),
			String(d["label"]), role, _who(other, nm)]
		if bool(arc["closed"]):
			var sh := String(d.get("cold_short", "")) if String(arc["end"]) == "cold" else _end_short(d, String(arc["end"]))
			out.append("%s [color=#5a6072]第%d→%d天[/color] %s" % [head, _day(int(arc["t0"])), _day(int(arc["t1"])), sh])
		else:
			out.append("%s [color=#5a6072]第%d天起 · %d幕[/color]" % [head, _day(int(arc["t0"])),
				(arc["beats"] as Array).size() + int(arc["extra"]) + 1])
	return out

func _end_short(d: Dictionary, end_id: String) -> String:
	for e in (d["ends"] as Array):
		if String(e["id"]) == end_id:
			return String(e.get("short", e["id"]))
	return ""
