extends SceneTree
## 美术选址用：多 seed × 多 N 跑 D 天，统计每格被居民站过的次数（town Space）。
## 用法：godot --headless --path game --script res://bench/walk_heat.gd -- --out <abs.json> [--seeds 1-6] [--days 6] [--ns 12,24,60]
const SimScript = preload("res://scripts/Sim.gd")

func _arg(name: String, dflt: String) -> String:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == name and i + 1 < a.size(): return a[i + 1]
	return dflt

func _initialize() -> void:
	var sp := _arg("--seeds", "1-6").split("-")
	var days := int(_arg("--days", "6"))
	var heat := {}
	for n in _arg("--ns", "12,24,60").split(","):
		for seed in range(int(sp[0]), int(sp[1]) + 1):
			var S = SimScript.new(); get_root().add_child(S)
			S.auto_run = false; S.backend = null
			if S.world.is_empty(): S._load_data()
			if int(n) > 12: S.spawn_count = int(n)
			S.start_new(seed)
			for t in range(days * S.TICKS_PER_DAY):
				S.tick()
				for ag in S.agents:
					var k := "%d,%d" % [int(ag["pos"].x), int(ag["pos"].y)]
					heat[k] = int(heat.get(k, 0)) + 1
			S.queue_free()
	var f := FileAccess.open(_arg("--out", "user://heat.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(heat))
	f.close()
	quit()
