extends Node
## craft_who.gd — Y3：手艺弧到底"关于谁"。
##
## W3 写下的边界原话是「全镇的手艺弧**只可能是关于同一个居民的**」（docs/90 §五）。
## 这句话有一半要修正，而修正的方向决定了叙述层该不该为它做点什么：
## 手艺弧的有向对是 **(看见的人 A → 干活的人 B)** ⇒ 被钉死在一个人身上的**只有 B**，A 是全镇。
## 本探针把 A、B 两侧的**不同人数**分开数出来，不靠读代码推。

const StoryScript = preload("res://scripts/Story.gd")

func _ready() -> void:
	var seeds := _parse_seeds(_arg("--seeds", "1-3"))
	var days := int(_arg("--days", "60"))
	var total := days * int(Sim.TICKS_PER_DAY)
	print("=== 手艺弧关于谁 · seeds=%s · %d 天 ===" % [str(seeds), days])
	for sd in seeds:
		Sim.backend = null
		Sim.record_decisions = false
		Sim.auto_run = false
		Sim.start_new(sd)
		for t in range(total):
			Sim.tick()
		var st := StoryScript.new()
		st.recompute(Sim.event_log)
		var aset: Dictionary = {}
		var bset: Dictionary = {}
		var n := 0
		for arc in st.arcs:
			if String(st.def_of(arc)["id"]) != "craft":
				continue
			n += 1
			aset[String(arc["a"])] = true
			bset[String(arc["b"])] = true
		# 全镇有几个人在出带目击者的活（= 事件侧的真值，与弧无关）
		var producers: Dictionary = {}
		for e in Sim.event_log:
			if String(e.get("type", "")) == "produce" and not (e.get("witnesses", []) as Array).is_empty():
				producers[String(e.get("actor", ""))] = true
		print("  seed %d · 居民 %d 人 · 手艺弧 %d 条（留存）· 看见的人 A：%d 个不同的人 %s · 干活的人 B：%d 个 %s · 事件侧有目击者的生产者：%d 个" % [
			sd, Sim.agents.size(), n, aset.size(), str(aset.keys()), bset.size(), str(bset.keys()), producers.size()])
	get_tree().quit(0)

func _arg(name: String, dflt: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
	return dflt

func _parse_seeds(spec: String) -> Array:
	var out: Array = []
	if spec.contains("-"):
		var p := spec.split("-")
		for s in range(int(p[0]), int(p[1]) + 1):
			out.append(s)
	else:
		for s in spec.split(","):
			out.append(int(s))
	return out
