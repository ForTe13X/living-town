class_name MemoryStream
extends RefCounted
## 记忆流（Stanford Generative Agents）：append-only 记忆 + recency/importance/relevance 检索 + 反思 + summarize-and-forget。
## 小世界用算术打分即可，无需 embedding（见 docs/03 §7）。

const CAP := 200
const KEEP := 150

var items: Array = []   # [{text, importance(1-10), tick, tags:[]}]

func add(text: String, importance: int, tick: int, tags: Array = []) -> void:
	items.append({"text": text, "importance": float(importance), "tick": tick, "tags": tags})
	if items.size() > CAP:
		_forget()

## 按 recency(指数衰减) + importance + relevance(标签重叠) 取 top-k。
func retrieve(query_tags: Array, now: int, k: int = 3) -> Array:
	var scored: Array = []
	for it in items:
		var recency: float = exp(-float(now - int(it["tick"])) / 600.0)
		var importance: float = float(it["importance"]) / 10.0
		var relevance := 0.0
		for t in query_tags:
			if t in it["tags"]:
				relevance += 1.0
		scored.append({"text": it["text"], "s": recency + importance + relevance})
	scored.sort_custom(func(a, b): return float(a["s"]) > float(b["s"]))
	var out: Array = []
	for i in min(k, scored.size()):
		out.append(scored[i]["text"])
	return out

## M3：把近期记忆 LLM 提炼成更高层洞察、写回（可再被反思 → 树）。骨架占位。
func reflect(_now: int) -> void:
	pass

## summarize-and-forget：上下文/检索成本有界——丢弃低重要度记忆（M3 可改为聚类+摘要）。
func _forget() -> void:
	items.sort_custom(func(a, b): return float(a["importance"]) > float(b["importance"]))
	items = items.slice(0, KEEP)
