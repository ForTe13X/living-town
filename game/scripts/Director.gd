class_name TownDirector
extends RefCounted
## 导演（Project Sid 的 Cognitive Controller 之精神）：偶发地为小镇设定高层意图，写进一块黑板。
## 骨架占位，原计划 M4 实现。
##
## ══════════════════════════════════════════════════════════════════════════
## ★ 2026-08-01（W3，docs/90 §二）：**别按原设计把它实现出来。** 下面是查出来的东西。
##
## ── 它今天是什么状态（`grep` + `git log -S`，两样都跑了）──────────────────
## `grep`：全仓**零引用** —— 没有任何 `preload("res://scripts/Director.gd")`、没有 `TownDirector.new()`、
##   没有任何 `.tscn` 挂它，`project.godot` 的 autoload 里也没有。
## `git log --follow game/scripts/Director.gd`：**只有一条 commit**，`ebac5a3`（首个公开快照）。
##   ⇒ 它自出生起一个字都没改过。
##
## ⚠️ docs/41 §1.5 那条纪律（"看到零调用先跑 `git log -S`"）在这里给出的答案，
##    **既不是"从没接上"、也不是"被有意摘掉"，而是第三种**：
##    **它要做的事已经在别处做成了，而且是用一套不同的架构做的。**
##    `git log -S "TownDirector"` 只有两条命中，第二条 `cb48519` 根本没碰本文件 ——
##    命中的是 `scriptwriter.gd` 抬头的一句注释。那句注释指向的正是接班人。
##
## ── 接班它的两处（都在树上，都能跑）──────────────────────────────────────
##   ① **规则体导演**：`Sim._update_festival()`，注释原文
##      「Wave 2b 节日调度（Director v1=纯规则体,"只撒机会地形不写剧情"）」。
##      日界按 `day % every_days` + 天气开节日、撒对象 —— 纯函数、无 RNG、无墙钟。
##   ② **模型当编剧**：`scripts/scriptwriter.gd`（`cb48519`）。它在**引擎外**离线跑模型，
##      把开局剧本**校验+夹紧+冻结成 data/scenarios/*.json**，仿真只消费数据。
##      那条 commit 自己写下的教训值得抄在这里：
##      "to put something non-deterministic into a deterministic system, don't run it in the loop —
##       have it produce frozen data offline; the system only consumes data."
##
## ── 为什么"按原设计实现"是**违反红线**的 ────────────────────────────────
## 原设计那句「偶发调用（如每游戏日一次或剧情节点）。M4：可走 LLM 生成镇上意图」要求
## **在仿真循环里**跑一次模型，把结果写进一块**世界会去读的**黑板。它同时撞两条红线：
##   · 红线 #1（确定性 + 逐字节重放）：模型输出不是 `(seed, tick, salt, who)` 的纯函数，
##     `goto_tick` 重演给不出同一块黑板 ⇒ 金标当场崩。
##   · 红线 #2（模型永远不能写世界状态）：`town_mood` / `rumor` / `spotlight` 一旦被世界读，
##     写黑板就等于写世界状态 —— 而红线 #2 只允许模型在**引擎枚举出的合法候选**里挑一个下标。
## ⇒ 想做"镇级意图"，正确的形状是上面 ①②：**要么是规则体，要么是离线冻结成数据。**
##
## ── 那为什么不干脆删掉 ──────────────────────────────────────────────────
## 照 docs/41 §0.8 记的那个处置模式（"承认 + 独立开关 + 明写已知状态 + 不出货"）：
## 一个原型可以留在树上，**只要它的状态被写清楚**。删掉它会让这份考据一起消失，
## 而下一个人做静态扫描时仍然会得出"有个导演没接上，接上吧"——这一波已经有三个人在别的符号上栽过同一跤。
## **本注释就是那个开关。** 真要动它的人，请先读上面那两条红线。
##
## ⚠️ 本类**不属于叙述层**：小镇故事在 `scripts/Story.gd`（对 `Sim.event_log` 的只读折叠），
##    "讲哪一段"由 `Story._drama` / `Story.recent_closed()` 排序决定，不需要也没有第二个排序器。

var blackboard := {
	"town_mood": "calm",      # calm | lively | tense
	"rumor": "",              # 正在流传的八卦
	"spotlight": "",          # 被点名接近玩家的 NPC id
}

## 偶发调用（如每游戏日一次或剧情节点）。**保持 no-op**：见抬头，走 LLM 的那一版违反红线 #1/#2。
func update(_sim) -> void:
	pass
