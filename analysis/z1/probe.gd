extends SceneTree
## Z1 量余量的探针（**编号 100 §二.2 那张表就是它印的**）。整个身体写在 _init() 里 —— 照 Harness.gd 的形状
## （docs/41 §2：`--script` 下 autoload 的 _ready() 要等主循环，所以显式调 `_load_data()`）。
##
## 跑法（它必须在 res:// 里才能被 --script 加载，所以先拷进去，跑完删掉）：
##   cp analysis/z1/probe.gd game/bench/_z1_probe.gd
##   godot --headless --path game --script res://bench/_z1_probe.gd > analysis/z1/probe.txt 2>&1
##   rm game/bench/_z1_probe.gd
const SimScript = preload("res://scripts/Sim.gd")

func _init() -> void:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	S.start_new(1)

	var k: float = S._w("obj_survival_pull", 0.0)
	print("GATE=%.6f  k=%.6f  36k=%.6f" % [S.SURVIVAL_GATE, k, S.SURVIVAL_GATE * k])

	var nids: Array = []
	for nd in S.needs_def:
		nids.append(String((nd as Dictionary).get("id", "")))
	print("needs=", nids)

	var socials: Array = []
	var all_adv := {}
	for oid in S.world["objects"]:
		var o: Dictionary = S.world["objects"][oid]
		for adv in o.get("advertises", []):
			if not (adv is Dictionary):
				continue
			var nid := String(adv.get("need", ""))
			var amt := int(adv.get("amount", 0))
			if amt <= 0:
				continue
			all_adv[nid] = int(all_adv.get(nid, 0)) + 1
			if nid == "social":
				socials.append({"o": oid, "type": String(o.get("type", "")),
					"act": String(adv.get("action", "")), "amt": amt})
	print("广告按 need 计数=", all_adv)
	for s in socials:
		var b0: float = 100.0 * float(s["amt"]) / 60.0
		print("  social广告 %-22s %-8s amount=%-4d  cur=0时base benefit=%.4f  36k/benefit=%.4f" % [
			String(s["o"]) + "(" + String(s["type"]) + ")", String(s["act"]), int(s["amt"]), b0,
			(S.SURVIVAL_GATE * k) / b0])

	print("— 响应面（#42 的 A/B 两臂探的就是它）—")
	for nid in nids:
		var row := ""
		for cur in [0.0, 9.0, 18.0, 27.0, 35.9, 36.0, 50.0]:
			row += "%.2f " % S._survival_pull(nid, float(cur), float(cur))
		print("  %-9s cur==min: %s" % [nid, row])
	print("  social cur>min (cur=10,min=5): %.4f" % S._survival_pull("social", 10.0, 5.0))
	print("  social cur==min=0            : %.4f" % S._survival_pull("social", 0.0, 0.0))
	print("obj_dist_penalty=%.4f" % S._w("obj_dist_penalty", 0.4))
	quit(0)
