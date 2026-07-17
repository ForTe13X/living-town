extends Node
## save_load_test.gd — R0-2 存档/读档【硬门】。
## 光"能读回来"不算数：读档若漏了任一权威字段 or 没重建共享引用，续跑会【悄悄漂】。
## 所以真正的门是：A 跑到 T 存档 → B(全新实例) 读档 → 两边【各再续跑 N tick】，每 tick 的
## (digest, event_digest) 必须【逐 tick 逐字节相同】。任一处漂 = 漏了状态/引用没修 → FAIL。
## 用法：godot --headless --path game res://scenes/save_load_test.tscn
const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

var _fails := 0
func ck(c: bool, m: String) -> void:
	if not c: _fails += 1
	print(("  OK   " if c else "  FAIL ") + m)

func _ready() -> void:
	var SEED := 20260626
	var T := 160        # 存档点：够深 → 有活跃承诺/冲突/秘密/派系/经济流（把 _active_commitments 重建也压到）
	var N := 60         # 续跑步数：漂了必在这 N 步里现形
	var path := "user://saveload_test.dat"
	if FileAccess.file_exists(path):                 # 清陈档：上一轮失败的旧文件会让后续检查测了个寂寞
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# ── A：跑到 T，存档 ──
	var A = SimScript.new(); add_child(A)
	A.start_new(SEED)
	for i in range(T): A.tick()
	var dA_T := Inv.digest(A); var eA_T: int = A.event_digest
	ck(A.save_game(path, {"name": "test"}), "save_game() 写盘成功")
	ck(FileAccess.file_exists(path), "存档文件存在")

	# 头信息（给 UI 列表用）不落地状态
	var head := A.peek_save(path)
	ck(head.get("saved_tick", -1) == T and head.get("magic", "") == "LTSAVE", "peek_save 头信息正确 (tick=%s)" % head.get("saved_tick"))

	# ── B：全新实例读档 ──
	var B = SimScript.new(); add_child(B)
	ck(B.load_game(path), "load_game() 读回成功")

	# 圆环回放：读档瞬间 digest 必须 == 存档瞬间
	ck(Inv.digest(B) == dA_T, "round-trip: 读档 digest == 存档 digest (%d)" % dA_T)
	ck(B.event_digest == eA_T, "round-trip: event_digest 一致 (%d)" % eA_T)
	ck(B.tick_no == T and B.day == A.day and B.town_coin == A.town_coin, "标量还原 (tick/day/coin)")
	ck(B.agents.size() == A.agents.size() and B.commitments.size() == A.commitments.size(), "集合规模还原")
	# 共享引用重建：改一个 agent 的需求，必须经 _agent_by_id 同一引用可见（否则漂的根源）
	if not B.agents.is_empty():
		var aid := String(B.agents[0]["id"])
		ck(B._agent_by_id.has(aid) and B._agent_by_id[aid] == B.agents[0], "_agent_by_id 重建为同一引用")
	ck(B._active_commitments.all(func(c): return c in B.commitments), "_active_commitments 指向 commitments[] 真引用")

	# ── 续跑 N tick：A 与 B 必须逐 tick 同步（漂即抓）──
	var drift_tick := -1
	for i in range(N):
		A.tick(); B.tick()
		if Inv.digest(A) != Inv.digest(B) or A.event_digest != B.event_digest:
			drift_tick = i
			break
	ck(drift_tick == -1, "续跑 %d tick 逐 tick 一致 (漂移点=%s)" % [N, drift_tick])

	# ── 反向硬门：坏档 / 版本不符必须拒绝，绝不静默套错 ──
	var bad := "user://saveload_bad.dat"
	var bf := FileAccess.open(bad, FileAccess.WRITE); bf.store_32(999); bf.store_var({"magic": "X"}); bf.close()
	var C = SimScript.new(); add_child(C); C.start_new(SEED)
	var pre := Inv.digest(C)
	ck(not C.load_game(bad), "坏档(schema 999)被拒绝")
	ck(Inv.digest(C) == pre, "被拒后状态未被污染")

	print("save_load_test: %s (%d fail)" % [("PASS ✅" if _fails == 0 else "FAIL ❌"), _fails])
	get_tree().quit(1 if _fails > 0 else 0)
