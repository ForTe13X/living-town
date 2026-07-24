extends SceneTree
## 室内夜间氛围 headless 验证（无需 framebuffer）：扫 N 天，找 home/1f 同室人数【峰值】那一 tick，
## 确认那时是深夜、床被占（→"床头灯更旺"分支触发），并算出 lit/pool 落在可见区间。给出出图该用的 tick。
## 用法：godot --headless --path game --script res://bench/t_intnight.gd -- [days] [seed]
const SimScript = preload("res://scripts/Sim.gd")

func _night_amt(tod: float) -> float:
	if tod < 0.20: return 1.0
	if tod < 0.32: return 1.0 - (tod - 0.20) / 0.12
	if tod < 0.72: return 0.0
	if tod < 0.88: return (tod - 0.72) / 0.16
	return 1.0

func _init():
	var days := 8; var seed := 1
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: days = int(a[0])
	if a.size() > 1: seed = int(a[1])
	var S = SimScript.new(); get_root().add_child(S)
	S._load_data(); S.auto_run = false; S.backend = null; S.start_new(seed)
	var TPD := int(S.TICKS_PER_DAY)
	var peak := 0; var peak_tick := 0; var peak_cells := {}; var peak_who := []
	for t in range(days * TPD):
		S.tick()
		var occ := 0; var cells := {}; var who := []
		for ag in S.agents:
			if String(ag.get("space","town")) == "home" and String(ag.get("floor","outdoor")) == "1f":
				occ += 1; cells[Vector2i(ag["pos"])] = true; who.append(S._name(ag))
		# 只在深夜采样（night>0.8），找睡觉高峰
		var tod := float(S.tick_no % TPD) / float(TPD)
		if _night_amt(tod) > 0.8 and occ > peak:
			peak = occ; peak_tick = S.tick_no; peak_cells = cells.duplicate(); peak_who = who
	var tod := float(peak_tick % TPD) / float(TPD)
	var night := _night_amt(tod)
	var lit := 0.20 * night + minf(0.12, peak * 0.04) * (0.5 + 0.5 * night)
	print("== 室内夜间氛围·峰值检查 ==  seed %d  扫 %d 天" % [seed, days])
	print("  home/1f 深夜同室人数峰值：%d 人 @tick %d  (tod=%.3f≈%02d:%02d, night=%.2f)" % [peak, peak_tick, tod, int(tod*24), int(fmod(tod*24,1.0)*60), night])
	print("  在场：%s" % ", ".join(peak_who))
	print("  暖底光 lit=%.3f  %s" % [lit, "可见✅" if lit > 0.05 else "太弱"])
	for b in [Vector2i(1,1), Vector2i(6,1)]:
		var occd = peak_cells.has(b) or peak_cells.has(b+Vector2i(0,1)) or peak_cells.has(b+Vector2i(0,-1))
		print("  床 %s：%s  pool=%.3f %s" % [str(b), ("有人✅" if occd else "空"), 0.20*night + (0.16 if occd else 0.0), "(床头灯更旺)" if occd else ""])
	print("  → 出图用 --warmup-tick %d" % peak_tick)
	quit()
