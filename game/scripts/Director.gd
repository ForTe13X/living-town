class_name TownDirector
extends RefCounted
## 导演（Project Sid 的 Cognitive Controller 之精神）：偶发地为小镇设定高层意图，写进一块黑板。
## 这里才是值得花「更聪明/云端」调用的地方；个体 NPC 多数走廉价脚本，只在被导演点名/玩家触发时调 LLM。
## 骨架占位，M4 实现。

var blackboard := {
	"town_mood": "calm",      # calm | lively | tense
	"rumor": "",              # 正在流传的八卦
	"spotlight": "",          # 被点名接近玩家的 NPC id
}

## 偶发调用（如每游戏日一次或剧情节点）。M4：可走 LLM 生成镇上意图。
func update(_sim) -> void:
	pass
