extends SceneTree
## P3 顾客进店验证：跑一局，统计常客(cafe_regular)进咖啡馆的情况 + 峰值同室人数 + 全员最低需求(#01 眼)。
## 用法：godot --headless --path game --script res://bench/find_patrons.gd -- [seed] [days]
const SimScript = preload("res://scripts/Sim.gd")
func _init():
	var seed := 1; var days := 12
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: seed = int(a[0])
	if a.size() > 1: days = int(a[1])
	var S = SimScript.new(); get_root().add_child(S)
	S._load_data(); S.auto_run = false; S.backend = null; S.start_new(seed)
	var TPD := int(S.TICKS_PER_DAY)
	var visit_ticks := {}          # regular id -> ticks spent in cafe
	var visits := {}               # regular id -> distinct visit count (transitions town->cafe)
	var was_in := {}
	var peak_1f := 0               # 同时在 cafe/1f 的人数峰值
	var peak_names := ""; var peak_tick := 0
	var min_need := 100.0
	var regulars := []
	for ag in S.agents:
		if bool(ag.get("cafe_regular", false)):
			regulars.append(String(ag["id"])); visit_ticks[String(ag["id"])] = 0; visits[String(ag["id"])] = 0; was_in[String(ag["id"])] = false
	for t in range(days * TPD):
		S.tick()
		var on1f := []
		for ag in S.agents:
			for nid in ag["needs"]:
				min_need = minf(min_need, float(ag["needs"][nid]))
			var inc := String(ag.get("space")) == "cafe"
			if String(ag.get("space")) == "cafe" and String(ag.get("floor")) == "1f":
				on1f.append(S._name(ag))
			var id := String(ag["id"])
			if id in regulars:
				if inc:
					visit_ticks[id] += 1
					if not was_in[id]: visits[id] += 1
				was_in[id] = inc
		if on1f.size() > peak_1f:
			peak_1f = on1f.size(); peak_names = ", ".join(on1f); peak_tick = S.tick_no
	print("seed %d · %dd · 顾客进店:" % [seed, days])
	for id in regulars:
		print("  常客 %s：进店 %d 次 · 店内 %d tick" % [S._name(S.get_agent(id)), visits[id], visit_ticks[id]])
	print("  cafe/1f 同室人数峰值: %d  (%s) @tick %d" % [peak_1f, peak_names, peak_tick])
	print("  全员全程最低需求: %.1f  %s" % [min_need, "✅ 不饿穿" if min_need > 0.5 else "❌ 饿穿!"])
	quit()
