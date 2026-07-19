extends SceneTree
## P2-3 交互格语义验证：跑一局，统计所有【正在 use 家具】的 agent 与家具的曼哈顿距离。
## 期望（改后）：d==1（站在家具旁）占全部；d==0（踩在家具格上）恒为 0。并打印一个可供出图的定格样例。
## 用法：godot --headless --path game --script res://bench/find_use.gd -- [seed]
const SimScript = preload("res://scripts/Sim.gd")
func _init():
	var seed := 20260626
	if OS.get_cmdline_user_args().size() > 0: seed = int(OS.get_cmdline_user_args()[0])
	var S = SimScript.new(); get_root().add_child(S)
	S._load_data(); S.auto_run = false; S.backend = null; S.start_new(seed)
	var TPD := int(S.TICKS_PER_DAY)
	var on_furniture := 0      # d==0：踩在家具格（应为 0）
	var beside := 0            # d==1：站在旁边（期望）
	var far := 0              # d>=2：不该在 use 相里（异常）
	var sample := ""          # 一个 day-time 定格样例（tick/agent/select）
	for t in range(30 * TPD):
		S.tick()
		for ag in S.agents:
			var opt = ag.get("option")
			if opt == null or String(opt.get("kind", "")) != "object" or String(opt.get("phase", "")) != "use":
				continue
			var obj = S.world["objects"].get(String(opt.get("target", "")), {})
			if obj.is_empty(): continue
			var d: int = absi(int(ag["pos"].x) - int(obj["pos"].x)) + absi(int(ag["pos"].y) - int(obj["pos"].y))
			if d == 0: on_furniture += 1
			elif d == 1: beside += 1
			else: far += 1
			# 抓一个白天(tod≈midday)的定格样例供 --shot 眼验
			if sample == "" and d == 1:
				var tod: int = S.tick_no % TPD
				if tod >= 100 and tod <= 140:
					sample = "tick=%d agent=%s obj=%s agent_pos=(%d,%d) obj_pos=(%d,%d)" % [
						S.tick_no, String(ag["id"]), String(opt.get("target", "")),
						int(ag["pos"].x), int(ag["pos"].y), int(obj["pos"].x), int(obj["pos"].y)]
	print("seed %d · 30d · use-phase 家具交互距离统计:" % seed)
	print("  站在旁边 d==1 : %d  ← 期望全部" % beside)
	print("  踩在家具 d==0 : %d  ← 应为 0（P2-3 前是这个值）" % on_furniture)
	print("  异常   d>=2 : %d  ← 应为 0" % far)
	print("  定格样例: %s" % (sample if sample != "" else "（未捕获白天样例，试其他 seed）"))
	quit()
