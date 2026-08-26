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

# ── 有向对怎么从事件里取（W3 新增，docs/90）────────────────────────────────────
## 每个**匹配器**（open / beats[] / ends[] / aside）都可以带一个 `pair`，声明这条弧的 (A,B)
## 从事件的哪两个字段来。**四种取法全部是【事件自带的字段】的直读，一处推断都没有**——
## 这是可追溯性的第一道结构保证，`audit()` 会把同一条计算重跑一遍来核对每一行叙述。
##
##   PAIR_TARGET  (默认)  A=actor      B=target    ← W3 之前的唯一取法，四条老弧全部走它
##   PAIR_SUBJECT         A=actor      B=subject   ← gossip_rep / endorse：被议论的那个人在 subject 里
##   PAIR_TS              A=target     B=subject   ← mediate：actor 是玩家，当事两人在 target/subject
##   PAIR_WIT             A=每个 witness  B=actor   ← produce：**看见他干活的人** → 干活的人（可一对多）
##
## ★为什么 PAIR_WIT 是 (witness, actor) 而不是 (actor, witness)：这样一来
##   ①`gossip_rep`（actor=议论者, subject=被议论者）天然就是这条弧的 aside——`_fold_aside` 一行不用改；
##   ②`shortage`（actor=扑空的人, target=被怪的人）天然是它的**正向**结局。
##   反过来键的话这两条都得反着写，而反着写的方向最后总会有一处忘了改（docs/47 的教训）。
const PAIR_TARGET := "target"
const PAIR_SUBJECT := "subject"
const PAIR_TS := "ts"
const PAIR_WIT := "wit"

## 面板/点播报栏那一行用的 meta（Main._on_log_meta 据此分流；居民 id 不会长这样）。
const PANEL_META := "__story__"

# ── 措辞锁（Y3 新增，docs/98）────────────────────────────────────────────────
## **这一节存在的全部理由是 W3 留下的那个负对照**（docs/90 §七 的 `M2`）：
## 把 grudge 与 pact 的开头文案**对调**，于是屏幕上逐字打出
##   「第1天 阿丽 与 本 结成了互助盟约 … 第2天 · 本 低了头，阿丽 原谅了 —— 这段梁子解开了」
## 而 `audit()` **0 违规**、整门 `rc=0` 全绿。
## ⇒ **那道审计守的是「这句话有依据」，不是「这句话说得对」。**
##
## 措辞锁往"说得对"那一侧挪了一步，机制只有一句话：
##   **一句叙述里若出现了某个【标志性短语】，就等于它在宣称"发生了某一类事"；
##     于是这一行所引用的那条 event，【它自己的 `type`】必须落在该短语允许的类型集合里。**
##
## ★为什么这不是又一份自证（这是本机制唯一值钱的地方）：
##   判据的真值来自 `Sim.event_log` 里那条事件的 `type` 字段 —— **仿真侧写的**，
##   本文件既不产生它、也改不动它。ARCS 表怎么改，都改不了那条事件是不是 `conflict`。
##   对调文案之后，「结成了互助盟约」这句话引用的仍然是一条 `conflict` ⇒ **当场红**。
##
## ★词表本身也不是我一个人说了算：`story_test.gd` 的 `PL` 段拿
##   `Main._event_prose`（编年史，**另一个文件、另一位作者的同一批事件的另一份渲染**）
##   与 `Sim._verb()`（仿真自己的中文动词表）来交叉验：
##     ①**安全向**（断言）：任何一条短语都不许出现在它**不允许**的类型的那份独立渲染里；
##     ②**佐证向**（只报数）：有多少条短语在独立渲染里逐字对得上。
##   W3 说这件事"没有廉价的补法：判对错要有第二份文案的真值" ——
##   **那第二份真值一直在树上，就是编年史**；它只是从没有被当成真值用过。
##
## ⚠️ 它守不住什么，写在 docs/98 的 `does_not_detect` 里，且**是跑出来的不是想出来的**：
##   最刺眼的一条是**同类型内部的语义反转**（把"没人应和"写成"应者云集"——两句都只引 rally_oust）。
##
## ⚠️ 选短语的两条硬约束（踩过才写下来的）：
##   ①**不许互相是子串**，否则会假红。实例：`slipped` 的「%B 在旁人面前说漏了嘴」
##     若把 gossip_rep 的短语定成「在旁人面前」，这一行就会被判成"只有 gossip_rep 能说" ⇒ 假红。
##     故 gossip_rep 取的是「在旁人面前说了」/「在旁人面前提起过」，与「说漏了嘴」不相交。
##   ②**空表 = 没约束**：一条没有任何标志性短语的文案照样过 —— 这不是漏洞，是本机制的定义域。
##     `lint_grammar()` 会把这类"没上锁的文案"逐条报出来（`story_test` 打印，不判红）。
const PHRASE_LOCK := {
	"积起了怨气": ["conflict"],
	"当面把话挑明": ["confront"],
	"当面把话说开": ["confront"],
	"理论": ["confront"],
	"来道了歉": ["apologize"],
	"低了头": ["apologize"],
	"统一了口径": ["endorse"],
	"施压": ["rally_oust"],
	"排挤": ["rally_oust"],
	"扑了个空": ["shortage"],
	"断了货": ["shortage"],
	# 「说和」三类都合法：调解失败只写 mediate，调解成功是补记的 confront/apologize（note=mediated）。
	# 它因此是本表里**唯一**一条多类型的短语，也因此是判别力最弱的一条 —— 照实记着。
	"说和": ["mediate", "confront", "apologize"],
	"话没能递进去": ["mediate"],
	"在旁人面前说了": ["gossip_rep"],
	"在旁人面前提起过": ["gossip_rep"],
	"稍后见面": ["invite"],
	"如约": ["meet"],
	"泡了汤": ["meet"],
	"托付给了": ["confide"],
	"说了一桩": ["confide"],
	"雪中送炭": ["aid"],
	"搭了把手": ["aid"],
	"搭手": ["aid"],
	"说了出去": ["betray"],
	"说漏了嘴": ["leak"],
	"结成了互助盟约": ["pact"],
	"盟约散了": ["pact"],
	"把一批活做成了": ["produce"],
	"出活": ["produce"],
	# Y3 新增的两幕。措辞**刻意抄仿真自己的动词表**（`Sim._verb`："聊起了看法" / "说了会儿悄悄话"），
	# 于是它们在 story_test 的 `PL` 段里是**被独立渲染逐字佐证**的那一档，不是我一个人说了算。
	"聊起了": ["discuss"],
	"悄悄话": ["gossip"],
	# AR1 新增（docs/145）："银钱往来"锁到 `pay`。它**独立渲染里对不上任何一条**——`pay` 在
	# `Main.FEED_SKIP` 里、`Main._event_prose` 无 pay 臂（落"# 兜底"，被 `_prose_by_type` 切掉）、
	# `Sim._verb("pay")` 走 default 返回裸 "pay"。⇒ PL4 佐证向对它归 0（"对不上不算错"），
	# 但安全向（不出现在【不允许】的类型里）成立，且它把三条 pay 幕从"没上锁"抬进"已上锁"。
	"银钱往来": ["pay"],
}

# ── 极性锁（AA2 新增，docs/105）──────────────────────────────────────────────
## **这一节存在的全部理由是 Y3 自己写下的那条边界**（docs/98 §三·3）：
## 措辞锁跨类型抓 573/573，**同一事件类型内部的语义反转 0/19 一个不抓**。
## 最刺眼的一条是 `promise/end:kept ↔ promise/end:broken`——把"赴约了"换成"放了鸽子"，
## 屏幕上每一句都反了，而锁一声不响：两者都引 `meet`，真假住在 `accepted` 里，而措辞锁不读那个字段。
##
## Y3 **刻意没有顺手加这个检查**，理由逐字抄在这里，因为它仍然成立、并且决定了本节必须长什么样：
##   > 那要在文法表里再声明一份 `accepted` 期望，而**那份声明与匹配器自己的 `accepted`
##   > 是同一个作者写的**，就退回成自证了。要真的守住它，得找到 `accepted` 的**第二个独立来源**。
##
## ★**第二个独立来源找到了，而且有两处**（清单与逐个判定见 docs/105 §二；两处都比 `Story.gd` 老）：
##   ① `Main._event_prose` 的**极性分支**——`meet`/`confront`/`apologize`/`mediate`/`election`
##      按 `accepted` 分岔、`rally_oust`/`pact`/`world` 按 `note` 分岔。
##      **另一个文件、另一位作者、对同一批事件的另一份渲染**，而且那句「约会泡汤了（有人爽约）」
##      从 `ebac5a3`（2026-07-03 首个公开快照）起就在，比 `Story.gd`（2026-07-30）早 27 天。
##      Y3 已经拿它验过**类型**那一维（0 污染 / 31 条短语里 17 条逐字印证），本节用的是它的**分支条件**这一维。
##   ② `data/goals.json` 的 `title`/`hint` 与它自己的极性 `match` **配成对**——
##      `kept_promise` = `{meet, accepted:true}` ↔「对方**真的赴了约**」；
##      `rally` = `{rally_oust, accepted:true}` ↔「而且**真有人应和**」；
##      `quarrel_healed` 的 `then` = `{apologize, accepted:true}` ↔「有人**先低了头**」；
##      `pact_formed` = `{pact, note_prefix:"formed"}` ↔「**结下**一纸盟约」。
##      **另一个文件、另一位作者（D2）、而且是数据不是代码**，2026-07-26，同样早于本文件。
##   两处都**不是**"从同一张语法表里再读一次"——那正是 Y3 说的自证。
##   `story_test` 的 `PL5` 段把这两份独立渲染按极性切开，逐条比对本表（安全向断言 + 佐证向报数）。
##
## ★运行期的**真值**是 `ev["accepted"]` 与 `ev["note"]`——和 `ev["type"]` 一样是**仿真侧写的**，
##   本文件既不产生也改不动。措辞锁值钱的那一句在这里逐字成立。
##
## ⚠️ 它守不住什么，跑出来的名单在 docs/105 §四。**下面这两个数是跑出来的，不是估的**
##   （我第一版按预测写成了「8 个 / 3 个真反转」，全空间重跑之后是这样）：
##   同类型那 19 条漏网现在剩 **6** 条，其中 **5 条是近义对调**（两条文案本来就说得差不多），
##   **只有 1 条是真的反转**（`grudge/aside ↔ craft/aside`，一褒贬一中性）
##   —— 而它缺的是**事件上的一个字段**（`gossip_rep` 不说这次议论是好话还是坏话），不是一道锁。
const POLARITY_LOCK := {
	# accepted 那一维（Sim 侧：2576/2587 meet±、2682/2697 confront±、2723/2729 apologize±、
	#                  4235 rally_oust 的 accepted 就是 `backers > 0`）
	"听了进去": {"accepted": true},
	"不认": {"accepted": false},
	"施压": {"accepted": true},
	"没人应和": {"accepted": false},
	"一时还没法原谅": {"accepted": false},
	"低了头": {"accepted": true},
	"这段梁子解开了": {"accepted": true},
	"如约": {"accepted": true},
	"泡了汤": {"accepted": false},
	# note 那一维（Sim 侧：1077/1079 补记的 confront/apologize note="mediated"；
	#             4376 pact note="formed"、4312 note="dissolved:freerider"）
	"在你的说和下": {"note_prefix": "mediated"},
	"结成了互助盟约": {"note_prefix": "formed"},
	"盟约散了": {"note_prefix": "dissolved"},
}

## 复述标记：这些词宣称"这件事之前发生过"。
## ⚠️ **它不是第二来源，是折叠自身的结构性事实**——所以本文把它单列一行、包络里也单独记数，
##    不许把它的战果算进"第二来源买到了多少"。
##    机制：`narrate_cited` 的 `open` 行按构造是这条弧的**第一行**（`_fold` 的 ③ 只在同键无弧在跑时才 `_start`），
##    于是一句"又……"落在 `open` 行上，讲的是一件这条弧里还没发生过的事。
const REPEAT_MARK := ["又", "还多了一次", "这回", "再一次"]

## 一句**模板**文案与"它所依据的事件类型集合"是否相容。返回违规说明，空数组 = 相容。
##
## ★查的是**模板**（`ARCS` 里的字面量）而不是渲染后的那一行，理由是**居民名会撞词**：
##   `_fill` 只替换 %A/%B/%d，短语判定在替换前后等价，而替换前不可能被人名污染。
static func phrase_conflicts(tpl: String, types: Array) -> Array:
	var out: Array = []
	for p in PHRASE_LOCK:
		if not tpl.contains(String(p)):
			continue
		var allow: Array = PHRASE_LOCK[p]
		for t in types:
			if not (String(t) in allow):
				out.append("措辞「%s」只有 %s 类事件能说，而这里依据的是 `%s`" % [String(p), str(allow), String(t)])
	return out

## 一句模板与**被引用的那条事件自己的极性**（`accepted` / `note`）是否相容。
## ★真值是 `ev["accepted"]` / `ev["note"]` —— **仿真侧写的两个字段**，本文件既不产生也改不动，
##   与措辞锁拿 `ev["type"]` 当真值是同一条纪律。运行期（`_audit_one` 第⑥条）走这一支。
static func polarity_conflicts_ev(tpl: String, ev: Dictionary) -> Array:
	var out: Array = []
	for p in POLARITY_LOCK:
		if not tpl.contains(String(p)):
			continue
		var need: Dictionary = POLARITY_LOCK[p]
		if need.has("accepted") and bool(ev.get("accepted", false)) != bool(need["accepted"]):
			out.append("措辞「%s」只有 accepted=%s 的事件能说，而这里依据的那条是 accepted=%s" % [
				String(p), str(bool(need["accepted"])), str(bool(ev.get("accepted", false)))])
		if need.has("note_prefix") and not String(ev.get("note", "")).begins_with(String(need["note_prefix"])):
			out.append("措辞「%s」只有 note 以 `%s` 开头的事件能说，而这里依据的那条 note=`%s`" % [
				String(p), String(need["note_prefix"]), String(ev.get("note", ""))])
	return out

## 同一条极性约束的**静态**一面：拿这个槽位自己的**匹配器**比。
##
## ★判据是「匹配器必须**保证**该极性」，**沉默也算不保证**。这一条是刻意的，而且它正是同类型对调
##   能被抓住的原因：`{"type":["confront"], "accepted": true}` 与 `{"type":["confront"]}` 在类型上
##   一模一样，但前者**筛**了极性、后者没有 —— 把一句带极性的话搬到不筛极性的槽位上，
##   就等于宣称一件"引用到的事件两种都可能"的事。
##
## ⚠️ 这里要说清一件容易被读成自证的事：匹配器里的 `accepted` **不是作者对世界的断言**，
##   它是一道**筛子**——`_match` 拿它去比 `ev["accepted"]`（仿真侧的字段）。写错了不会"骗过检查"，
##   只会让这条幕在真世界里**根本不触发**。所以"匹配器保证了 accepted=true"是一句关于
##   被引用事件的真陈述，不是一句自我声明。剩下那半句作者主张——"短语 P 的意思是极性 X"——
##   才是需要第二来源的，而它由 `story_test` 的 `PL5` 拿两份独立渲染交叉验。
static func polarity_conflicts_matcher(tpl: String, m: Dictionary) -> Array:
	var out: Array = []
	for p in POLARITY_LOCK:
		if not tpl.contains(String(p)):
			continue
		var need: Dictionary = POLARITY_LOCK[p]
		if need.has("accepted"):
			if not m.has("accepted"):
				out.append("措辞「%s」宣称 accepted=%s，而这条槽位的匹配器**不筛** accepted —— 引用到的事件两种都可能" % [
					String(p), str(bool(need["accepted"]))])
			elif bool(m["accepted"]) != bool(need["accepted"]):
				out.append("措辞「%s」宣称 accepted=%s，而这条槽位的匹配器筛的是 accepted=%s" % [
					String(p), str(bool(need["accepted"])), str(bool(m["accepted"]))])
		if need.has("note_prefix"):
			var want := String(need["note_prefix"])
			if not m.has("note_prefix"):
				out.append("措辞「%s」宣称 note 以 `%s` 开头，而这条槽位的匹配器**不筛** note" % [String(p), want])
			elif not String(m["note_prefix"]).begins_with(want):
				out.append("措辞「%s」宣称 note 以 `%s` 开头，而这条槽位的匹配器筛的是 `%s`" % [
					String(p), want, String(m["note_prefix"])])
	return out

## 复述标记不许落在【开头】那一行上（见 `REPEAT_MARK` 抬头：这是结构性事实，不是第二来源）。
static func repeat_conflicts(tpl: String, kind: String) -> Array:
	var out: Array = []
	if kind != "open":
		return out
	for w in REPEAT_MARK:
		if tpl.contains(String(w)):
			out.append("复述标记「%s」落在【开头】那一行上 —— 开头按构造是这条弧的第一件事" % String(w))
	return out

## 静态查一遍**整张文法表**：每个匹配器的文案，与它自己声明的 `type` 是否相容。
## 返回 `{"bad": [...违规...], "unlocked": [...没有任何标志性短语的匹配器...]}`。
##
## ★为什么除了 `audit()` 的运行期检查之外还要有它：运行期只覆盖**真的被渲染出来的那些行**，
##   而 docs/90 §十二 实测过 promise/secret/pact 三条弧在 CI 那一格里一条都开不出来
##   ⇒ 光靠运行期，改坏一条没跑到的文案不会有任何东西响。静态这一遍与夹具是否跑到无关。
static func lint_grammar() -> Dictionary:
	var bad: Array = []
	var unlocked: Array = []
	var pol_locked := 0
	for d in ARCS:
		var did := String(d["id"])
		for row in _grammar_slots(d):
			var tpl := String(row[1])
			var types: Array = row[2]
			if tpl == "":
				continue
			var c := phrase_conflicts(tpl, types)
			# AA2：同一遍扫描里再查两件事——极性（拿槽位自己的匹配器）与复述标记（拿槽位的 kind）。
			c.append_array(polarity_conflicts_matcher(tpl, row[3] as Dictionary))
			c.append_array(repeat_conflicts(tpl, String(row[4])))
			for x in c:
				bad.append("%s/%s：%s" % [did, String(row[0]), String(x)])
			if _locked_phrases(tpl).is_empty():
				unlocked.append("%s/%s：%s" % [did, String(row[0]), tpl])
			if not _polarity_phrases(tpl).is_empty():
				pol_locked += 1
	return {"bad": bad, "unlocked": unlocked, "pol_locked": pol_locked}

## 一条弧定义里所有**带文案且有事件依据**的槽位：
## `[槽位名, 模板, 该槽位声明的事件类型, 该槽位的完整匹配器, 行的 kind]`。
## 冷场文案**不在内**——它依据的正是"此后没有任何事件"，没有类型可比（见 `does_not_detect`）。
##
## ⚠️ AA2 把后两项加进来了（原先只有前三项）。**匹配器整份**都要，因为极性锁查的是
## `accepted`/`note_prefix` 这两个字段，而它们不在 `type` 里；`kind` 则是复述标记那一条要用的。
static func _grammar_slots(d: Dictionary) -> Array:
	var out: Array = [["open", String(d["open_text"]), ((d["open"] as Dictionary).get("type", []) as Array),
		(d["open"] as Dictionary), "open"]]
	for bt in (d["beats"] as Array):
		out.append(["beat:" + String(bt["id"]), String(bt["text"]),
			((bt["m"] as Dictionary).get("type", []) as Array), (bt["m"] as Dictionary), "beat"])
	for e in (d["ends"] as Array):
		out.append(["end:" + String(e["id"]), String(e["text"]),
			((e["m"] as Dictionary).get("type", []) as Array), (e["m"] as Dictionary), "end"])
	if String(d["aside_text"]) != "":
		out.append(["aside", String(d["aside_text"]), ((d["aside"] as Dictionary).get("type", []) as Array),
			(d["aside"] as Dictionary), "aside"])
	return out

static func _locked_phrases(tpl: String) -> Array:
	var out: Array = []
	for p in PHRASE_LOCK:
		if tpl.contains(String(p)):
			out.append(String(p))
	return out

static func _polarity_phrases(tpl: String) -> Array:
	var out: Array = []
	for p in POLARITY_LOCK:
		if tpl.contains(String(p)):
			out.append(String(p))
	return out

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
			# ★W3：三条【玩家/结盟】幕必须排在通用幕**前面**——`_fold` 的 ② 是"首个匹配的幕胜出"，
			#   而 `{"type":["confront"],"accepted":true}` 会把 note="mediated" 的那条一起吃掉。
			#   排序就是这套文法里唯一的优先级机制，写反了不会报错、只会把玩家从故事里抹掉。
			#
			# 调解成功时 `Sim.player_mediate` 会**补记** confront+apologize 两条 note="mediated" 的事件
			# （Sim.gd:1077/:1079，为的是让"先对质后和解"这条硬不变量在有玩家时仍可溯源）。
			# 在 W3 之前，怨气弧照单全收这两条、并把它讲成"%A 当面把话挑明" ——
			# **玩家做了这件事，而故事里没有他。** 这一幕只加一个 note_prefix，不新增任何字段。
			{"id": "mediated", "m": {"type": ["confront"], "accepted": true, "note_prefix": "mediated"},
			 "text": "在你的说和下，%A 与 %B 当面把话说开了"},
			# 调解**失败**只会写一条 mediate 事件（Sim.gd:1100），没有 confront/apologize 陪着 ⇒
			# 在 W3 之前它对故事层完全隐形。mediate 的 actor 是 "player"（非居民），当事两人在
			# target/subject 里 ⇒ 这是 PAIR_TS 存在的唯一理由。
			{"id": "tried", "m": {"type": ["mediate"], "accepted": false}, "pair": PAIR_TS,
			 "text": "你想替 %A 和 %B 说和，话没能递进去"},
			# endorse：actor 跟 target【就 subject 这个人】统一了口径（Sim.gd:2467 的记忆原话是
			# "和%s统一了对%s的看法"）⇒ 被议论的人在 subject 里，故 PAIR_SUBJECT。
			# 它是"拉帮结派"在怨气弧里看得见的那一步，而此前 267 条 endorse 一条都不进故事。
			{"id": "sided", "m": {"type": ["endorse"], "accepted": true}, "pair": PAIR_SUBJECT,
			 "text": "%A 跟旁人对 %B 的看法统一了口径"},
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
			# ── Y3 新增两幕：**梁子还在，可两个人还在说话** ──────────────────────
			# ★选它们的依据是一张"可落地上界"表，不是一个点子（docs/98 §一）。
			#   量的**不是**这类事件有几条（那是虚高得离谱的分母），而是**有几条落在一段已经开着的弧上**：
			#     discuss 1151 条 → grudge 有向对上 319 条（target fwd 173 + rev 146）
			#     gossip   568 条 → grudge 有向对上 110 条（target fwd  75 + rev  35）
			#   作为参照，W3 那一波新加的 `sided`(endorse) 实际落了 147 条 ⇒ 这两幕合起来约是它的 2.9 倍。
			#   **同一张表把 `give` 判了死刑**：432 条只落得上 **4** 条（0.9%）——
			#   `give` 有 trust 门（只送给已经信得过的人），而开着的弧绝大多数是 grudge（敌对有向对），
			#   两者在结构上几乎不相交。"送礼是最有关系含量的动作"这个先验是错的，而**只有量才看得出来**。
			#
			# ★dir 用 `any`：`discuss` 的 `_fj_update` 在 Sim 侧是**双向**跑的（Sim.gd:2407-2408），
			#   `gossip` 虽是单向传播，但"这两个人还在私下说话"这件事本身不分谁先开口。
			# ★措辞刻意**不带褒贬**（同 craft 的旁支那一条）：事件里没有任何字段说这次交谈是修好还是更僵，
			#   写成"两人把话说开了"就是叙述层在发明事实。这里只说他们**说了**。
			{"id": "talked", "m": {"type": ["discuss"]}, "dir": "any",
			 "text": "%A 与 %B 就镇上的事聊起了各自的看法"},
			{"id": "whisper", "m": {"type": ["gossip"]}, "dir": "any",
			 "text": "%A 与 %B 说了会儿悄悄话"},
			# ── AR1 新增：梁子归梁子，买卖照做 ────────────────────────────────────
			# ★选它的依据同 Y3——一张"可落地上界"普查（docs/145，`analysis/ar1/census_60d_paynote.txt`，
			#   12 seed × 60 天）。量的是**有几条 pay 落在一段已开着的怨气弧的有向对上**：
			#     pay 全局 13573（note：price:6321 / wage:3754 / rent:2666 / buy:832）
			#     其中 price:/wage: 一端是镇库（NON_AGENT）⇒ 一条都落不了地；能落的只有 person→person
			#     的 rent 与 buy: 两类。落在怨气弧有向对上：**947 条**（475 fwd + 472 rev），
			#     ⇒ 比 W3 的 `sided`(endorse=147) 高一档，远在 give 判死那条线（4/432）之上。
			# ★措辞**刻意不认哪一笔**：matcher 不筛 note（price:/wage: 反正落不了地），于是它同时收
			#   "买了他一回"（buy:）与"付了他房租"（rent）——两者的共同真值只有一件事：**钱在两人之间动过**。
			#   写成"买了他的手艺"就是发明事实：同一张普查表把那个天真设想**判了死**——
			#   买家=看客、卖家=匠人 那个干净方向（craft 的 buy: fwd）实测是 **0**（见 craft 弧同名幕的注释）。
			#   这里只说"银钱往来"，不说买的是什么、谁付给谁。
			# ★dir="any"：一笔货款/房租落在这条有向对上，与谁先掏钱无关（同 discuss/gossip 那两幕）。
			{"id": "traded", "m": {"type": ["pay"]}, "dir": "any",
			 "text": "梁子归梁子，%A 与 %B 之间的银钱往来一直没断"},
		],
		"ends": [
			# 同样必须排在 `mended` 前面（ends 也是"首个匹配的胜出"）。
			{"id": "mediated", "m": {"type": ["apologize"], "accepted": true, "note_prefix": "mediated"},
			 "dir": "rev", "tone": "warm",
			 "text": "在你的说和下，%B 低了头，%A 也放下了 —— 这段梁子解开了", "short": "你说和的"},
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
			# AR1 新增：盟友之间的银钱往来（docs/145 普查：pay 落在盟约有向对上 181 条 = 122 fwd + 59 rev，
			#   > sided=147 那条下界）。盟约是暖弧、当事人本就互信 ⇒ 一笔货款/借贷落在这里，
			#   与 `aid`(搭把手) 同属"这份交情在钱上也照应着"，措辞同样只说钱动过、不认是买是租。
			{"id": "traded", "m": {"type": ["pay"]}, "dir": "any",
			 "text": "%A 与 %B 之间，银钱往来也没断过"},
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
	# ── 手艺（W3 新增）───────────────────────────────────────────────────────
	## **本弧的全部理由是一张清点表，不是一个点子。**（docs/90 §一，12 seed × 60 天，出货阵容）
	##   `produce` 带目击者 **237 条**（V1 的手艺口碑，docs/84），而它今天：
	##     · 播报侧 —— `Main.FEED_SKIP` 里明写着 `produce`，一条都不上屏；
	##     · 故事侧 —— 弧文法里没有 `produce`，命中 **0/237**。
	##   ⇒ V1 那句"镇上会因为看见他干活而改变对他的看法"在**屏幕上一个字都没有**。
	##   （V1 自己在 docs/84 里明写"没动 Story.gd"，所以这不是它的疏漏，是这一棒该接的那一段。）
	##
	## ★两处**结构性**的好处，不是修辞：
	##   ① `witnesses` 为空 ⇒ `_pairs(ev, PAIR_WIT)` 返回空 ⇒ 本弧一条都开不出来。
	##      而 `witnesses` 恰恰只在 `production.craft_credit` 有该职位时才非空（Sim.gd:3324）。
	##      ⇒ **V1 的回滚（删一个 JSON 键）会把这条弧一起带走，不需要在这里再守一道分支。**
	##   ② A=看见的人、B=干活的人 ⇒ `gossip_rep`(actor,subject) 与 `shortage`(actor,target)
	##      两条都**天然同向**，一行方向转换代码都不用写。
	##
	## ★`cold: 0`（永不冷场）——与 `secret`/`pact` 同一档，**这是"没有量出来的数就别写"**：
	##   grudge 的 3600 是拿 8 seed × 60 天的相邻幕间隔分布量出来的（见上面那段）。
	##   我没有为手艺弧做同一次测量，所以不发明一个阈值；代价写清楚：没有结局的手艺弧会一直挂在
	##   "还在往下走"里。它有天然上界——每个有向对至多一条，12 居民 ⇒ 至多 132 条（实测见 docs/90 §四）。
	{
		"id": "craft", "label": "手艺", "tone": "grey",
		"open": {"type": ["produce"]}, "open_pair": PAIR_WIT,
		"open_text": "%A 看着 %B 把一批活做成了",
		"beats": [
			{"id": "again", "m": {"type": ["produce"]}, "pair": PAIR_WIT, "text": "%A 又一次看着 %B 出活"},
			{"id": "handed", "m": {"type": ["aid"], "accepted": true}, "dir": "any",
			 "text": "两人之间还多了一次搭手"},
			# Y3：同上两幕，落在手艺弧上的量小一档（discuss 106 条 · gossip 28 条，见 docs/98 §一）。
			# 加它们的理由不是那个数，是**同一条事件不该在一条弧上算数、在另一条弧上不算数**：
			# 手艺弧的 (A,B) 是"看着他干活的人 → 干活的人"，这两个人私下聊没聊过，与梁子弧同样是实情。
			{"id": "talked", "m": {"type": ["discuss"]}, "dir": "any",
			 "text": "%A 与 %B 就镇上的事聊起了各自的看法"},
			{"id": "whisper", "m": {"type": ["gossip"]}, "dir": "any",
			 "text": "%A 与 %B 说了会儿悄悄话"},
			# ── AR1 新增：看着他干活的人，也和他有一条银钱往来 ───────────────────────
			# ★这一幕的注释首先要**记下一次被普查判死的天真设想**（docs/145，同 give 的下场）：
			#   本以为最顺的是"看客买下了匠人的活"——买家=看客(A)、卖家=匠人(B) 那个 buy: fwd 方向。
			#   12 seed × 60 天实测：craft 弧上 buy: 的那个干净方向落地 **0 条**（rev 338、fwd 0）。
			#   匠人未必就是摊贩，看他干活的人也未必回头买他的货 —— "手艺=最好卖"这个先验是错的，
			#   而只有量才看得出来。
			# ★活下来的是**不认是买是租**的读法：pay 落在 craft 有向对上共 **1440 条**（880 fwd + 560 rev），
			#   其中绝大多数是 rent（看他干活的人也住在他屋檐下按月缴租，880 fwd 里几乎全是这类）。
			#   同 grudge 的 `traded`：matcher 不筛 note（price:/wage: 一端是镇库、落不了地），
			#   共同真值只有"钱在两人之间动过"。措辞不说买下了他的手艺（那已被判死），只说银钱往来。
			# ★dir="any"：同弧内其余四幕一致。
			{"id": "traded", "m": {"type": ["pay"]}, "dir": "any",
			 "text": "%A 与 %B 之间还牵着一条银钱往来"},
		],
		"ends": [
			# `shortage`：actor=扑了空的人、target=被怪的那个岗位的人（Sim.gd:3397）。
			# 与本弧同向 ⇒ "我一直看着你干活" 与 "这回我扑了空、账记在你头上" 是同一条有向键的两端。
			# 措辞照抄怨气弧那一幕（`empty`）的口径，不多说一个字：事件本身只说"断了货、怪谁"。
			{"id": "failed", "m": {"type": ["shortage"]}, "tone": "cold",
			 "text": "可这回 %A 扑了个空 —— 镇上断了货，这笔账记在 %B 头上", "short": "扑了空"},
			{"id": "allied", "m": {"type": ["pact"], "note_prefix": "formed"}, "dir": "any", "tone": "warm",
			 "text": "%A 与 %B 结成了互助盟约", "short": "结了盟"},
		],
		"aside": {"type": ["gossip_rep"]},
		# ⚠️ 措辞刻意**不带褒贬**：`gossip_rep` 事件里没有任何字段说这次议论是好话还是坏话
		#    （`_event_prose` 也只写"议论起 %s 的为人"）。写成"夸了 %d 次"就是叙述层在发明事实。
		"aside_text": "这中间 %A 在旁人面前提起过 %d 次 %B",
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
## `_fold` 的**每-def 临时**便签（"这条事件在本 def 上已经处理掉了哪些有向对"）。
## 复用一个成员而不是每个 def new 一个 Dictionary：`_fold` 在 12.5 tick/s 的热路径上、
## 每条事件要过 5 个 def，逐 def 分配会白白制造 5 次分配 × 每秒几十条事件。
## **它不是状态**：每个 def 开头 `clear()`，跨事件不携带任何信息 ⇒ 不进 digest、不进 reset 的语义。
var _pdone: Dictionary = {}

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
## 一个匹配器要查的【有向对】列表，元素是 `[A, B]`。**四种取法全部直读事件自带的字段**。
## 空数组 = 这条事件在这种取法下没有合法的两个人（非居民占位 / 自指 / 字段缺失）⇒ 什么都不发生。
func _pairs(ev: Dictionary, mode: String) -> Array:
	var a := String(ev.get("actor", ""))
	match mode:
		PAIR_SUBJECT:
			return _pair1(a, String(ev.get("subject", "")))
		PAIR_TS:
			return _pair1(String(ev.get("target", "")), String(ev.get("subject", "")))
		PAIR_WIT:
			var out: Array = []
			for w in (ev.get("witnesses", []) as Array):
				# 一条 produce 被三个人看见 = 三条独立的手艺弧。这是本文件里唯一的一对多，
				# 而它仍然系在两个人身上：每一条弧的 A、B 都是具体的两个居民 id。
				out.append_array(_pair1(String(w), a))
			return out
		_:
			return _pair1(a, String(ev.get("target", "")))

func _pair1(a: String, b: String) -> Array:
	if (a in NON_AGENT) or (b in NON_AGENT) or a == b:
		return []                     # 故事系在两个人身上：election(town) 这类非人 actor、自指事件不进任何弧
	return [[a, b]]

func _fold(ev: Dictionary, fresh: Array) -> void:
	# aside 走的是 (actor, subject)，与 target 无关 ⇒ 必须在下面那些取对法之前先给它一次机会。
	_fold_aside(ev)
	# 四种取法**每条事件各算一次**（不是每匹配器一次）。绝大多数事件 witnesses 为空、subject 为空，
	# ⇒ 三条新取法在热路径上就是三次立即返回的空数组。
	var pm := {
		PAIR_TARGET: _pairs(ev, PAIR_TARGET),
		PAIR_SUBJECT: _pairs(ev, PAIR_SUBJECT),
		PAIR_TS: _pairs(ev, PAIR_TS),
		PAIR_WIT: _pairs(ev, PAIR_WIT),
	}
	if (pm[PAIR_TARGET] as Array).is_empty() and (pm[PAIR_SUBJECT] as Array).is_empty() \
			and (pm[PAIR_TS] as Array).is_empty() and (pm[PAIR_WIT] as Array).is_empty():
		return
	for di in ARCS.size():
		var d: Dictionary = ARCS[di]
		var did := String(d["id"])
		# 本 def 在本条事件上**已经处理掉的有向对**。它保住了 W3 之前的那条语义：
		# 同一条弧对同一条事件，至多发生 结局 / 中间幕 / 开头 三者之一（原来靠 `break`+`continue` 实现，
		# 现在因为一条事件可能落到**多个**对上，必须按对记）。单对时两种写法逐字等价。
		_pdone.clear()
		# ① 结局：先看这条弧有没有在跑，再看这个事件是不是它的结局。
		for e in (d["ends"] as Array):
			for p in (pm[String(e.get("pair", PAIR_TARGET))] as Array):
				var pk: String = p[0] + KEY_SEP + p[1]
				if _pdone.has(pk):
					continue
				var k := _key_for(did, pk, p[1] + KEY_SEP + p[0], String(e.get("dir", "fwd")))
				if k == "" or not _open.has(k):
					continue
				if not _match(e["m"], ev):
					continue
				var arc: Dictionary = _open[k]
				_close(arc, String(e["id"]), String(e.get("tone", "grey")), ev)
				_open.erase(k)
				fresh.append(arc)
				_pdone[pk] = true
		# ② 中间幕
		for bt in (d["beats"] as Array):
			for p in (pm[String(bt.get("pair", PAIR_TARGET))] as Array):
				var pk2: String = p[0] + KEY_SEP + p[1]
				if _pdone.has(pk2):
					continue
				var k2 := _key_for(did, pk2, p[1] + KEY_SEP + p[0], String(bt.get("dir", "fwd")))
				if k2 == "" or not _open.has(k2):
					continue
				if not _match(bt["m"], ev):
					continue
				_beat(_open[k2], String(bt["id"]), ev)
				_pdone[pk2] = true
		# ③ 开头：同【有向】键还没有弧在跑，才开新的一条（否则同一对会开出一串重复的开头）。
		#   ★刻意只挡同向、不挡反向：`Sim._find_conflict` 是**有方向的**（`c.a==a and c.b==b`），
		#     "阿雅怨本" 与 "本怨阿雅" 在引擎里就是两段各自独立的冲突 —— 合成一段是把两个故事讲丢一个。
		for p in (pm[String(d.get("open_pair", PAIR_TARGET))] as Array):
			var pk3: String = p[0] + KEY_SEP + p[1]
			if _pdone.has(pk3):
				continue
			if not _open.has(did + ARC_SEP + pk3) and _match(d["open"], ev):
				_start(di, String(p[0]), String(p[1]), ev)
				_pdone[pk3] = true

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
			# ★W3 可追溯性：旁支此前**只有一个计数**——面板上那句"说了 137 次"在账本里找不到任何一条依据。
			#   现在按 MAX_BEATS 记下前几条的事件 id（与幕同一个上限、同一条理由）；
			#   `audit()` 会把它们逐条回 event_log 核。**超出上限的那些仍然只是计数，见 audit 的诚实边界。**
			if (arc["aside_ev"] as Array).size() < MAX_BEATS:
				(arc["aside_ev"] as Array).append(int(ev.get("id", -1)))
			# 刻意**不 bump rev**：旁支只出现在 `narrate()` 里，而 `narrate` 只被用在**已收场**的弧上
			# （`panel_text` 的 closed[0]）⇒ 弧还开着时旁支怎么涨都改不到屏幕上的字。
			# 面板脏标记的代价是每次 +1 就重排一次全表（docs/46 §二·六 那笔 88→11 FPS 的账）。

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
		"beats": [], "extra": 0, "aside": 0, "aside_ev": [], "last": t,
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
		# W3：旁支引用也进摘要 —— 它是状态（会被 audit 读），不是缓存令牌。
		for ae in (arc["aside_ev"] as Array):
			h = SimScript.fnv1a32_into(h, "a:%d" % int(ae))
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
## ★W3：本函数现在只是 `narrate_cited()` 的一层薄壳。**屏幕上的每一行都必须从那一个地方出来**——
##   有两个成文入口，就有一个能绕过审计的入口。
func narrate(arc: Dictionary, nm: Callable) -> Array:
	var out: Array = []
	for row in narrate_cited(arc, nm):
		out.append(String((row as Dictionary)["text"]))
	return out

## ★★可追溯性的实现（docs/90 §三）。红线 #2 的精神：模型不写世界状态；**叙述层同理不许发明事实**。
## 本函数把一条弧的全文吐成**带出处**的行，每行一个字典：
##   text  真正上屏的那一行（BBCode 已就位）
##   ev    这一行依据的那条 `event` 的 id；**-1 表示"这一行不是由某一条事件说出来的"**
##   kind  open / beat / end / cold / aside / extra / pending
##   mid   产生这一行的**匹配器**在文法表里的身份（beat/end 的 id；open 为 ""）
##   evs   仅 aside 用：这条计数行背后**逐条记下的**事件 id（上限 MAX_BEATS）
## `audit()` 拿着这四样回 `event_log` 逐行核对。**造不出 event 就印不出那一行**，
## 而全部文案都是 `ARCS` 里的字面量 —— 本文件里没有任何一处把事件内容拼进字符串。
func narrate_cited(arc: Dictionary, nm: Callable) -> Array:
	var d := def_of(arc)
	var out: Array = [{
		"text": "[color=#5a6072]第%d天[/color] %s" % [_day(int(arc["t0"])), _fill(String(d["open_text"]), arc, nm)],
		"ev": int(arc["ev0"]), "kind": "open", "mid": "", "evs": []}]
	for bt in (arc["beats"] as Array):
		var txt := ""
		for cand in (d["beats"] as Array):
			if String(cand["id"]) == String(bt[0]):
				txt = String(cand["text"])
				break
		if txt != "":
			out.append({
				"text": "[color=#5a6072]第%d天[/color] %s" % [_day(int(bt[1])), _fill(txt, arc, nm)],
				"ev": int(bt[2]), "kind": "beat", "mid": String(bt[0]), "evs": []})
	if int(arc["extra"]) > 0:
		# 纯计数行：超出 MAX_BEATS 的那些幕**没有留下 id**（面板本来也放不下）。
		# 它因此是 audit 的一条已知盲区，写在 does_not_detect 里，不假装它有出处。
		out.append({"text": "[color=#5a6072]……中间还有 %d 幕[/color]" % int(arc["extra"]),
			"ev": -1, "kind": "extra", "mid": "", "evs": []})
	if int(arc["aside"]) > 0 and String(d["aside_text"]) != "":
		out.append({
			"text": "[color=#5a6072]%s[/color]" % _fill(String(d["aside_text"]), arc, nm).replace("%d", str(int(arc["aside"]))),
			"ev": -1, "kind": "aside", "mid": "", "evs": (arc["aside_ev"] as Array).duplicate()})
	if bool(arc["closed"]):
		var etxt := String(d["cold_text"]) if String(arc["end"]) == "cold" else _end_text(d, String(arc["end"]))
		out.append({
			"text": "[color=%s]第%d天 · %s[/color]" % [
				TONE_COLOR.get(String(arc["tone"]), "#9aa0b5"), _day(int(arc["t1"])), _fill(etxt, arc, nm)],
			# 冷场那一行**唯一合法地没有事件出处**：它讲的正是"此后没有任何事件"。
			# 它不是凭空的——判据是 t1 == 最后一幕 + cold，story_test F3/F3′ 两面都钉着。
			"ev": int(arc["ev1"]), "kind": ("cold" if String(arc["end"]) == "cold" else "end"),
			"mid": String(arc["end"]), "evs": []})
	else:
		out.append({"text": "[color=#9aa0b5]（还没有结局）[/color]", "ev": -1, "kind": "pending", "mid": "", "evs": []})
	return out

## 审计一条弧的全文：把每一行自称的出处拿回 `by_id`（事件 id → 事件）里核。
## 返回**违规说明**的数组，空数组 = 这条弧的每一行都指得回一条真事件。
##
## 逐行核四件事（缺一不可，少任何一条都能让一句编出来的话过关）：
##   ① 这条 id 在 event_log 里**存在**；
##   ② 它**满足**产生这一行的那个匹配器（拿文法表里同一个 `_match` 重跑）；
##   ③ 它推出来的**有向对**就是这条弧的 (A,B)，方向也对（拿同一个 `_pairs` 重跑）；
##   ④ 它的 `tick` 就是这一行行首印的那个第几天所依据的 tick。
##   ⑤ **（Y3 新增）它的 `type` 与这一行的【措辞】不打架** —— 见 `PHRASE_LOCK`。
##      前四条守的是"这句话有依据"，第五条是往"这句话说得对"挪的那一步：
##      真值取自被引用事件自己的 `type`（**仿真侧写的**），不取自本文法表。
##   ⑥ **（AA2 新增）它的 `accepted` / `note` 与这一行的【措辞】不打架** —— 见 `POLARITY_LOCK`。
##      第⑤条抓的是"这句话在讲另一种事"，第⑥条抓的是"这句话在讲这种事，但讲反了"。
##   ⑦ **（AA2 新增）复述标记不落在开头行上** —— 见 `REPEAT_MARK`（结构性，不是第二来源）。
## 只有 kind=cold / extra / pending 三种行允许 ev=-1，且 cold 只在 end=="cold" 时允许。
func audit(arc: Dictionary, by_id: Dictionary) -> Array:
	var bad: Array = []
	var d := def_of(arc)
	for row in narrate_cited(arc, func(id): return id):
		var r: Dictionary = row
		var kind := String(r["kind"])
		var ev_id := int(r["ev"])
		if kind == "pending":
			continue                                  # "（还没有结局）"：占位行，本来就不自称有出处
		if kind == "aside":
			# 计数与引用必须对得上：旁支不满 MAX_BEATS 时**每一次都必须留下 id**。
			# 这一条挡住的是"引用三条、屏幕上写 99 次"——虚报计数在别处是查不出来的。
			var na := int(arc["aside"])
			var ne := (r["evs"] as Array).size()
			if ne != mini(na, MAX_BEATS):
				bad.append("弧#%d 旁支写着 %d 次，却只留下 %d 条引用（上限 %d）" % [int(arc["n"]), na, ne, MAX_BEATS])
			for ae in (r["evs"] as Array):
				bad.append_array(_audit_one(arc, d["aside"], PAIR_TARGET_FOR_ASIDE, "fwd", int(ae), by_id, -1, "aside",
					String(d["aside_text"])))
			continue
		if kind == "extra":
			# 同理：只有把 MAX_BEATS 个坑位占满了，才可能有"中间还有 N 幕"。
			if (arc["beats"] as Array).size() != MAX_BEATS:
				bad.append("弧#%d 写着还有 %d 幕，但已记下的幕只有 %d 条（未满 %d）" % [
					int(arc["n"]), int(arc["extra"]), (arc["beats"] as Array).size(), MAX_BEATS])
			continue
		if kind == "cold":
			if ev_id != -1:
				bad.append("弧#%d 冷场行不该带出处，却写着 ev=%d" % [int(arc["n"]), ev_id])
			continue
		if ev_id < 0:
			bad.append("弧#%d 的 %s 行没有出处（ev=-1），而只有冷场行可以" % [int(arc["n"]), kind])
			continue
		var m: Dictionary = {}
		var mode := PAIR_TARGET
		var dir := "fwd"
		var want_tick := -1
		var tpl := ""                                  # 这一行的**模板**（措辞锁查的是它，不是渲染后的字；见 phrase_conflicts）
		if kind == "open":
			m = d["open"]
			mode = String(d.get("open_pair", PAIR_TARGET))
			tpl = String(d["open_text"])
			want_tick = int(arc["t0"])
		elif kind == "beat":
			var found := false
			for cand in (d["beats"] as Array):
				if String(cand["id"]) == String(r["mid"]):
					m = cand["m"]; mode = String(cand.get("pair", PAIR_TARGET)); dir = String(cand.get("dir", "fwd"))
					tpl = String(cand["text"])
					found = true
					break
			if not found:
				bad.append("弧#%d 的幕 `%s` 在文法表里查无此条" % [int(arc["n"]), String(r["mid"])])
				continue
			for bt in (arc["beats"] as Array):
				if int(bt[2]) == ev_id:
					want_tick = int(bt[1])
					break
		else:                                          # end
			var found2 := false
			for cand2 in (d["ends"] as Array):
				if String(cand2["id"]) == String(r["mid"]):
					m = cand2["m"]; mode = String(cand2.get("pair", PAIR_TARGET)); dir = String(cand2.get("dir", "fwd"))
					tpl = String(cand2["text"])
					found2 = true
					break
			if not found2:
				bad.append("弧#%d 的结局 `%s` 在文法表里查无此条" % [int(arc["n"]), String(r["mid"])])
				continue
			want_tick = int(arc["t1"])
		bad.append_array(_audit_one(arc, m, mode, dir, ev_id, by_id, want_tick, kind, tpl))
	return bad

## aside 的取对法固定是 (actor, subject)，与 PAIR_SUBJECT 同一个计算 —— 这里给它一个名字，
## 是为了让 `_fold_aside` 那条"不走 pair 字段"的历史事实在审计里也被显式写出来，而不是靠巧合对上。
const PAIR_TARGET_FOR_ASIDE := PAIR_SUBJECT

func _audit_one(arc: Dictionary, m: Dictionary, mode: String, dir: String, ev_id: int,
		by_id: Dictionary, want_tick: int, kind: String, tpl: String = "") -> Array:
	var out: Array = []
	var n := int(arc["n"])
	if not by_id.has(ev_id):
		out.append("弧#%d 的 %s 行引用了 event #%d —— event_log 里没有这条" % [n, kind, ev_id])
		return out
	var ev: Dictionary = by_id[ev_id]
	if not _match(m, ev):
		out.append("弧#%d 的 %s 行引用 event #%d（type=%s accepted=%s note=%s），但它不满足这一行的匹配器 %s" % [
			n, kind, ev_id, String(ev.get("type", "")), str(bool(ev.get("accepted", false))),
			String(ev.get("note", "")), str(m)])
	var a := String(arc["a"])
	var b := String(arc["b"])
	var pairs := _pairs(ev, mode)
	var ok := false
	for p in pairs:
		if (dir != "rev" and String(p[0]) == a and String(p[1]) == b) \
				or (dir != "fwd" and String(p[0]) == b and String(p[1]) == a):
			ok = true
			break
	if not ok:
		out.append("弧#%d(%s>%s) 的 %s 行引用 event #%d，但它在取法 %s/%s 下给出的是 %s —— 系错人了" % [
			n, a, b, kind, ev_id, mode, dir, str(pairs)])
	if want_tick >= 0 and int(ev.get("tick", -1)) != want_tick:
		out.append("弧#%d 的 %s 行印的是 tick %d，而 event #%d 的 tick 是 %d" % [
			n, kind, want_tick, ev_id, int(ev.get("tick", -1))])
	# ⑤ 措辞锁：这一行的**说法**与被引用事件**自己的 type** 不许打架（Y3，见 PHRASE_LOCK）。
	#    真值是 `ev["type"]` —— 仿真侧写的，本文法表改不动它。W3 的 M2（对调两条弧的开头文案）
	#    在这一条上当场红：那句「结成了互助盟约」引用的仍然是一条 conflict。
	for x in phrase_conflicts(tpl, [String(ev.get("type", ""))]):
		out.append("弧#%d 的 %s 行引用 event #%d：%s" % [n, kind, ev_id, String(x)])
	# ⑥ 极性锁（AA2，见 POLARITY_LOCK）：第⑤条守的是"这句话在讲另一种事"，
	#    这一条守的是"这句话在讲这种事，但讲反了"。真值是 `ev["accepted"]` / `ev["note"]`。
	#    Y3 点名的那条 `promise/end:kept ↔ broken`（赴约/爽约对调）在这一条上当场红。
	for y in polarity_conflicts_ev(tpl, ev):
		out.append("弧#%d 的 %s 行引用 event #%d：%s" % [n, kind, ev_id, String(y)])
	# ⑦ 复述标记（AA2，结构性，不是第二来源）。
	for z in repeat_conflicts(tpl, kind):
		out.append("弧#%d 的 %s 行：%s" % [n, kind, String(z)])
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
