extends Node
## P1-a 功能港口硬门：港口对象、affiliate 一等 agent、池口径与岗位活性必须同时成立。

const SimScript = preload("res://scripts/Sim.gd")

var _fails := 0

func ck(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
	print(("  OK   " if ok else "  FAIL ") + msg)

func _ready() -> void:
	var S = SimScript.new()
	add_child(S)
	S.auto_run = false
	S.backend = null
	S.start_new(1)

	ck(S.core_population == 12 and S.agents.size() == 13,
		"12 核心居民 + 1 affiliate（实得 %d + %d）" % [S.core_population, S.agents.size() - S.core_population])
	ck(S.prod_pool_num == S.prod_pool_den and is_equal_approx(S.work_pull_mult, 1.0),
		"affiliate append-after-pool，不放大产能且不关闭 N=12 export")
	var tao: Dictionary = S.get_agent("tao")
	ck(not tao.is_empty() and bool(tao.get("affiliate", false)), "阿涛是带 affiliate 来源标签的一等 agent")
	var port: Dictionary = S.world.get("objects", {}).get("port_dock", {})
	ck(not port.is_empty() and String(port.get("type", "")) == "码头"
		and not (port.get("advertises", []) as Array).is_empty(), "port_dock 编译成带广告位的真实 world 对象")
	var job: Dictionary = S._job_of("tao")
	ck(String(job.get("title", "")) == "码头工" and String(S._job_action(job)) == "卸货", "affiliate 岗位/动作外键闭合")

	var need0: Dictionary = tao["needs"].duplicate(true)
	for _i in range(20 * int(S.TICKS_PER_DAY)):
		S.tick()

	var wages := 0
	var spending := 0
	var social := 0
	for ev in S.event_log:
		var ty := String(ev.get("type", ""))
		var note := String(ev.get("note", ""))
		if ty == "pay" and String(ev.get("target", "")) == "tao" and note == "wage:卸货":
			wages += 1
		if ty == "pay" and String(ev.get("actor", "")) == "tao" and (note.begins_with("price:") or note.begins_with("buy:")):
			spending += 1
		if bool(ev.get("accepted", false)) and not (ty in ["pay", "world", "election", "produce", "consume", "spoil", "shortage", "import", "export"]):
			if String(ev.get("actor", "")) == "tao" or String(ev.get("target", "")) == "tao":
				social += 1
	ck(wages > 0, "码头工在 20 天内真的卸货并领薪（%d 次）" % wages)
	ck(spending > 0, "affiliate 在镇内真实消费、把工资送回经济环（%d 笔）" % spending)
	ck(social > 0, "affiliate 参与真实社交，而非被 #03 排除（%d 次）" % social)
	ck(tao["needs"] != need0 and (tao["needs"] as Dictionary).values().all(func(v): return float(v) > 0.5),
		"affiliate needs 会衰减/补给且未饿穿")
	ck(not S.election_log.is_empty() and int(S.election_log[-1].get("voters", 0)) == 13,
		"affiliate 进入选举计票（选民=%d）" % int(S.election_log[-1].get("voters", 0) if not S.election_log.is_empty() else 0))

	print("p1a_affiliate_test: %s (%d fail)" % [("PASS ✅" if _fails == 0 else "FAIL ❌"), _fails])
	get_tree().quit(1 if _fails > 0 else 0)
