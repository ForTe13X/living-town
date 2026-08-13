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
		"manifests": S.cargo_manifests, "order": S.cargo_manifest_order,
	})

func _row44(S) -> Dictionary:
	for row in Inv.check_all(S, 0):
		if int(row.get("id", 0)) == 44:
			return row
	return {}

## Adversarial saves must be produced by an offline transformer, never by asking the
## production writer to serialize a state that it correctly rejects.  Keep the valid
## envelope/header intact and mutate only the record field under test.
func _write_manifest_id_mutation(source_path: String, target_path: String, manifest_id: String, mutated_id: String) -> bool:
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null or source.get_length() < 8:
		return false
	var header := source.get_32()
	var raw_blob = source.get_var()
	source.close()
	if not (raw_blob is Dictionary):
		return false
	var blob: Dictionary = (raw_blob as Dictionary).duplicate(true)
	var state = blob.get("state")
	if not (state is Dictionary):
		return false
	var manifests = (state as Dictionary).get("cargo_manifests")
	if not (manifests is Dictionary) or not (manifests as Dictionary).has(manifest_id):
		return false
	var record = (manifests as Dictionary)[manifest_id]
	if not (record is Dictionary):
		return false
	(record as Dictionary)["id"] = mutated_id
	var target := FileAccess.open(target_path, FileAccess.WRITE)
	if target == null:
		return false
	target.store_32(header)
	target.store_var(blob)
	target.close()
	return true

func _ready() -> void:
	var manifest_id := "manifest_east_ocean_3_0"
	for failpoint in ["after_pay", "after_stock", "after_manifest", "after_receipt", "after_retire"]:
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
	var live_events: Array = S.event_log.duplicate(true)
	for i in range(S.event_log.size() - 1, -1, -1):
		if String(S.event_log[i].get("note", "")).begins_with("cargo_arrive:" + manifest_id):
			S.event_log.remove_at(i)
			break
	var missing_live_receipt := _snapshot(S, manifest_id)
	ck(S._arrive_import_manifest(S.logistics["import_lanes"][0], 0) == ""
		and _snapshot(S, manifest_id) == missing_live_receipt,
		"live manifest 缺 arrival receipt 时 fail-closed，不以 live record 掩盖损坏历史")
	S.event_log = live_events.duplicate(true)
	var live_snapshot := _snapshot(S, manifest_id)
	ck(S._arrive_import_manifest(S.logistics["import_lanes"][0], 0) == manifest_id
		and _snapshot(S, manifest_id) == live_snapshot,
		"live manifest 的同日 arrival replay 仅验证唯一 receipt，不改 cargo/event/digest")
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
	ck(not S.cargo_manifests.has(manifest_id) and S.cargo_manifest_order.find(manifest_id) < 0,
		"成功 receipt 后完成单从 live manifest/order 退休")
	ck(String(S.cargo_status_for_node("port_dock").get("state", "")) == "empty",
		"提交后玩家港口投影清空，不显示幽灵卸货")
	var row44 := _row44(S)
	ck(not row44.is_empty() and bool(row44.get("ok", false)), "升级后的硬 #44 在真实事务上通过")

	# P1-j: a retired manifest id is still consumed by its append-only arrival receipt.
	# Replaying the same authored lane/day must not resurrect cargo or append a second arrival.
	var retired_snapshot := _snapshot(S, manifest_id)
	var retired_events: Array = S.event_log.duplicate(true)
	ck(S._arrive_import_manifest(S.logistics["import_lanes"][0], 0) == manifest_id,
		"retired manifest 的同日 arrival replay 返回既有确定 id")
	ck(_snapshot(S, manifest_id) == retired_snapshot and not S.cargo_manifests.has(manifest_id),
		"retired manifest 的历史 receipt 阻止同 id cargo 复活与重复 arrival")
	for e in S.event_log:
		if String(e.get("note", "")).begins_with("cargo_arrive:" + manifest_id):
			e["actor"] = "other_route"
			break
	var conflicting_history := _snapshot(S, manifest_id)
	ck(S._arrive_import_manifest(S.logistics["import_lanes"][0], 0) == ""
		and _snapshot(S, manifest_id) == conflicting_history,
		"conflicting arrival tombstone fail-closed 且不改 live cargo/event/digest")
	S.event_log = retired_events.duplicate(true)
	S.event_log.append(S.event_log.filter(func(e):
		return String(e.get("note", "")) == "cargo_arrive:%s*4" % manifest_id)[0].duplicate(true))
	var duplicate_history := _snapshot(S, manifest_id)
	ck(S._arrive_import_manifest(S.logistics["import_lanes"][0], 0) == ""
		and _snapshot(S, manifest_id) == duplicate_history,
		"duplicate exact arrival tombstone fail-closed 且不追加第三条 receipt")
	S.event_log = retired_events.duplicate(true)

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
	S.event_log = clean_events.duplicate(true)
	for e in S.event_log:
		if String(e.get("note", "")).begins_with("cargo_arrive:" + manifest_id):
			e["actor"] = "other_route"
			break
	ck(not bool(_row44(S).get("ok", true)), "#44 mutation：arrival route 与 authored lane 不符必红")
	S.event_log = clean_events.duplicate(true)
	var pending: Dictionary = {
		"id": "manifest_east_ocean_6_0", "route_id": "east_ocean", "lane_index": 0,
		"node": "port_dock", "good": "柴薪", "arrived_day": 6, "initial_qty": 4, "remaining_qty": 4,
		"price_per": 3, "price_den": 4, "state": "ready",
	}
	S.cargo_manifests[pending["id"]] = pending
	S.cargo_manifest_order.append(pending["id"])
	S._log_event("world", "other_route", pending["id"], "柴薪", true, [], "cargo_arrive:%s*4" % pending["id"])
	ck(not bool(_row44(S).get("ok", true)), "#44 mutation：live pending arrival 绑定错误 route 必红")
	S.event_log[S.event_log.size() - 1]["actor"] = "east_ocean"
	S.cargo_manifest_order.append(pending["id"])
	ck(not bool(_row44(S).get("ok", true)), "#44 mutation：live pending order 重复 id 必红")
	S.cargo_manifest_order.pop_back()
	S.cargo_manifests.erase(pending["id"])
	S.cargo_manifest_order.erase(pending["id"])
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

	var Long = SimScript.new()
	add_child(Long)
	Long.auto_run = false
	Long.backend = null
	Long.start_new(1)
	Long.tick_no = int(Long.TICKS_PER_DAY * 0.25)
	for d in range(3, 34, 3):
		Long.day = d
		Long._stock_move("柴薪", -4, "consume", "town", "p1h_long_fixture")
		Long._logi_import()
		var mid := "manifest_east_ocean_%d_0" % d
		ck(Long._commit_manifest_unload(mid, "tao", "port_dock", true) == 4,
			"长时 fixture 第%d天完成一单" % d)
		ck(Long.cargo_manifests.is_empty() and Long.cargo_manifest_order.is_empty(),
			"第%d天完成后 live cargo 保持有界为空" % d)
	var long_scan: Dictionary = Inv.import_manifest_tx_scan(Long)
	ck(int(long_scan.get("transactions", 0)) == 11 and (long_scan.get("bad", []) as Array).is_empty(),
		"11 单历史只由 arrival+tx receipts 审计，live queue 不随历史增长")
	_drop(Long)

	var Legacy = _fixture()
	var old_id := "manifest_east_ocean_3_0"
	var old_rec: Dictionary = Legacy.cargo_manifests[old_id].duplicate(true)
	ck(Legacy._commit_manifest_unload(old_id, "tao", "port_dock", true) == 4,
		"旧 P1-g fixture 先生成 exact 完成 tx")
	old_rec["remaining_qty"] = 0
	old_rec["state"] = "complete"
	Legacy.cargo_manifests[old_id] = old_rec
	Legacy.cargo_manifest_order.append(old_id)
	var legacy_path := "user://p1h_complete_manifest_migration.save"
	ck(Legacy.save_game(legacy_path), "含旧 complete record 的 schema-2 fixture 可写盘")
	var Receiver = _fixture()
	ck(Receiver.load_game(legacy_path) and not Receiver.cargo_manifests.has(old_id)
		and Receiver.cargo_manifest_order.find(old_id) < 0 and bool(_row44(Receiver).get("ok", false)),
		"读旧 P1-g 档时仅凭 exact receipts 退休 complete record，历史 #44 仍绿")
	var bad_id_path := "user://p1h_noncanonical_complete_manifest.save"
	Legacy.cargo_manifests[old_id]["id"] = "manifest_east_ocean_99_0"
	if FileAccess.file_exists(bad_id_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(bad_id_path))
	ck(not Legacy.save_game(bad_id_path) and not FileAccess.file_exists(bad_id_path),
		"schema-2 writer 拒绝非 canonical live manifest，且不留下半档")
	Legacy.cargo_manifests[old_id]["id"] = old_id
	ck(_write_manifest_id_mutation(legacy_path, bad_id_path, old_id, "manifest_east_ocean_99_0"),
		"离线 transformer 从合法档构造单字段 manifest-id 负例")
	var IdGuard = _fixture()
	var id_guard_before := _snapshot(IdGuard, old_id)
	ck(not IdGuard.load_game(bad_id_path) and _snapshot(IdGuard, old_id) == id_guard_before,
		"complete record 的 id/route/day/lane 不一致时拒绝且 receiver 原子不变")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bad_id_path))
	_drop(IdGuard)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))
	_drop(Receiver)
	_drop(Legacy)

	var Bad = _fixture()
	var bad_rec: Dictionary = Bad.cargo_manifests[old_id]
	bad_rec["remaining_qty"] = 0
	bad_rec["state"] = "complete"
	var bad_path := "user://p1h_unproven_complete_manifest.save"
	ck(Bad.save_game(bad_path), "无完成 tx 的 complete mutation fixture 可写盘")
	var Guard = _fixture()
	var guard_before := _snapshot(Guard, old_id)
	ck(not Guard.load_game(bad_path) and _snapshot(Guard, old_id) == guard_before,
		"无 exact arrival/tx 证明的 complete record 拒绝且 live receiver 原子不变")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bad_path))
	_drop(Guard)
	_drop(Bad)

	var Orphan = _fixture()
	var orphan_rec: Dictionary = Orphan.cargo_manifests[old_id]
	orphan_rec["remaining_qty"] = 0
	orphan_rec["state"] = "complete"
	Orphan.cargo_manifest_order.clear()
	ck(not Orphan._retire_completed_manifest(old_id) and Orphan.cargo_manifests.has(old_id),
		"order 悬空时 retirement fail-closed，不先擦 dictionary 制造静默丢货")
	_drop(Orphan)

	print("p1g_manifest_transaction_test: %s (%d fail)" % [("PASS ✅" if _fails == 0 else "FAIL ❌"), _fails])
	get_tree().quit(1 if _fails > 0 else 0)
