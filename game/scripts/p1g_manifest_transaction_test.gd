extends Node
## P1-g：CargoManifest 钱/货/cargo receipt 同 txid 原子提交；故障注入不得留下任何可观察残渣。

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

var _fails := 0

func ck(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
	print(("  OK   " if ok else "  FAIL ") + msg)

func _fixture():
	var S = SimScript.new()
	add_child(S)
	S.auto_run = false
	S.backend = null
	S.start_new(1)
	S.tick_no = int(S.TICKS_PER_DAY * 0.25)
	S.day = 3
	S._stock_move("柴薪", -4, "consume", "town", "p1g_fixture")
	S._logi_import()
	return S

func _drop(S) -> void:
	remove_child(S)
	S.free()

func _snapshot(S, manifest_id: String) -> String:
	return JSON.stringify({
		"town": S.town_coin, "external": S.external_coin, "stock": S.town_stock,
		"events": S.event_log, "next": S._next_event_id, "event_digest": S.event_digest,
		"manifest": S.cargo_manifests.get(manifest_id, {}),
	})

func _row44(S) -> Dictionary:
	for row in Inv.check_all(S, 0):
		if int(row.get("id", 0)) == 44:
			return row
	return {}

func _ready() -> void:
	var manifest_id := "manifest_east_ocean_3_0"
	for failpoint in ["after_pay", "after_stock", "after_manifest", "after_receipt"]:
		var F = _fixture()
		var before := _snapshot(F, manifest_id)
		ck(F._commit_manifest_unload(manifest_id, "tao", "port_dock", true, failpoint) == 0,
			"%s 注入返回 0" % failpoint)
		ck(_snapshot(F, manifest_id) == before,
			"%s 精确回滚钱/货/cargo/event_log/id/digest" % failpoint)
		ck(F._commit_manifest_unload(manifest_id, "tao", "port_dock", true) == 4,
			"%s 回滚后同一 manifest 可重试且只成功一次" % failpoint)
		var scan: Dictionary = Inv.import_manifest_tx_scan(F)
		ck((scan["bad"] as Array).is_empty() and int(scan["transactions"]) == 1 and int(scan["related"]) == 3,
			"%s 重试生成一组 exact 三事件 tx" % failpoint)
		_drop(F)

	var S = _fixture()
	var st: Dictionary = S.cargo_status_for_node("port_dock")
	ck(String(st.get("state", "")) == "ready" and String(st.get("good", "")) == "柴薪" and int(st.get("qty", 0)) == 4,
		"玩家港口投影显示真实 ready manifest 的货名与数量")
	S.town_coin = 0
	ck(String(S.cargo_status_for_node("port_dock").get("state", "")) == "blocked_funds",
		"港口投影诚实显示镇库不足")
	S.town_coin = 60
	var cap := int((S.production.get("goods", {}) as Dictionary).get("柴薪", {}).get("cap", 0))
	S.town_stock["柴薪"] = cap
	ck(String(S.cargo_status_for_node("port_dock").get("state", "")) == "blocked_capacity",
		"港口投影诚实显示整单仓位不足")
	S.town_stock["柴薪"] = cap - 4
	var tao: Dictionary = S.get_agent("tao")
	tao["option"] = {"manifest_id": manifest_id, "manifest_authorized": true}
	ck(String(S.cargo_status_for_node("port_dock").get("state", "")) == "working",
		"引擎签发 option 后港口投影显示卸货中")
	tao["option"] = null

	var event0 := int(S.event_log.size())
	ck(S._commit_manifest_unload(manifest_id, "tao", "port_dock", true) == 4, "正向整单提交 4 件")
	var suffix: Array = S.event_log.slice(event0)
	var txid := "cargo_unload/" + manifest_id
	ck(suffix.size() == 3 and suffix.all(func(e): return String(e.get("txid", "")) == txid),
		"pay→stock→cargo receipt 三条共享 manifest-bound txid")
	ck(String(S.cargo_status_for_node("port_dock").get("state", "")) == "empty",
		"提交后玩家港口投影清空，不显示幽灵卸货")
	var row44 := _row44(S)
	ck(not row44.is_empty() and bool(row44.get("ok", false)), "升级后的硬 #44 在真实事务上通过")

	var clean_events: Array = S.event_log.duplicate(true)
	S.event_log[event0 + 1].erase("txid")
	ck(not bool(_row44(S).get("ok", true)), "#44 mutation：stock 缺 txid 必红")
	S.event_log = clean_events.duplicate(true)
	S.event_log[event0 + 2]["note"] = "cargo_unload:%s*3" % manifest_id
	ck(not bool(_row44(S).get("ok", true)), "#44 mutation：cargo receipt 数量不符必红")
	S.event_log = clean_events.duplicate(true)
	S.event_log[event0 + 2]["id"] = int(S.event_log[event0 + 2]["id"]) + 1
	ck(not bool(_row44(S).get("ok", true)), "#44 mutation：事务 event id 非连续必红")
	S.event_log = clean_events.duplicate(true)
	S.event_log[event0 + 2]["txid"] = "cargo_unload/manifest_other"
	ck(not bool(_row44(S).get("ok", true)), "#44 mutation：receipt 绑定别的 manifest 必红")
	S.event_log = clean_events
	ck(bool(_row44(S).get("ok", false)), "恢复原日志后 #44 重新通过")
	_drop(S)

	var Free = _fixture()
	Free.economy = {}
	var free_event0 := int(Free.event_log.size())
	ck(Free._commit_manifest_unload(manifest_id, "tao", "port_dock", true) == 4,
		"economy-off 保留免费整单 off-gate")
	var free_suffix: Array = Free.event_log.slice(free_event0)
	ck(free_suffix.size() == 2 and String(free_suffix[0].get("type", "")) == "import"
		and String(free_suffix[1].get("note", "")).begins_with("cargo_unload:")
		and String(free_suffix[0].get("txid", "")) == String(free_suffix[1].get("txid", ""))
		and bool(_row44(Free).get("ok", false)),
		"免费单仍以 stock→receipt 同 txid 绑定，#44 非真空通过")
	_drop(Free)

	print("p1g_manifest_transaction_test: %s (%d fail)" % [("PASS ✅" if _fails == 0 else "FAIL ❌"), _fails])
	get_tree().quit(1 if _fails > 0 else 0)
