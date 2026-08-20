extends Node
## P1-v：东海货运观测室是 CargoManifest 的只读、可交互、可审计控制面。

const Inv = preload("res://bench/Invariants.gd")
const CFG := "user://settings.cfg"

var _fails := 0
var _main: Node2D
var _cfg_backup := PackedByteArray()
var _cfg_existed := false

func ck(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
	print(("  OK   " if ok else "  FAIL ") + msg)

func _pin_settings() -> void:
	_cfg_existed = FileAccess.file_exists(CFG)
	if _cfg_existed:
		_cfg_backup = FileAccess.get_file_as_bytes(CFG)
	var cfg := ConfigFile.new()
	cfg.set_value("backend", "mode", "logic")
	cfg.set_value("sim", "player", false)
	cfg.set_value("sim", "speed", 1.0)
	cfg.save(CFG)

func _restore_settings() -> void:
	if _cfg_existed:
		var out := FileAccess.open(CFG, FileAccess.WRITE)
		if out != null:
			out.store_buffer(_cfg_backup)
			out.close()
	elif FileAccess.file_exists(CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))

func _fixture(economy_on: bool = true) -> String:
	Sim.backend = null
	Sim.start_new(1)
	Sim.auto_run = false
	Sim.running = false
	Sim.tick_no = int(Sim.TICKS_PER_DAY * 0.25)
	Sim.day = 3
	if not economy_on:
		Sim.economy = {}
	Sim._stock_move("柴薪", -4, "consume", "town", "p1v_fixture")
	Sim._logi_import()
	return "manifest_east_ocean_3_0"

func _snapshot() -> String:
	var player: Dictionary = Sim.get_agent("player")
	return JSON.stringify({
		"digest": Inv.digest(Sim), "town": Sim.town_coin, "external": Sim.external_coin,
		"stock": Sim.town_stock, "events": Sim.event_log, "next": Sim._next_event_id,
		"event_digest": Sim.event_digest, "manifests": Sim.cargo_manifests,
		"order": Sim.cargo_manifest_order, "path_cache": Sim._path_cache,
		"player": player,
	})

func _safe_invalid_receipt(row: Dictionary) -> bool:
	return String(row.get("state", "")) == "invalid" and String(row.get("manifest_id", "")) == "" \
		and String(row.get("good", "")) == "" and int(row.get("qty", -1)) == 0 \
		and String(row.get("worker_id", "")) == "" and String(row.get("txid", "")) == "" \
		and int(row.get("event_id", -2)) == -1

func _safe_invalid_cargo(row: Dictionary) -> bool:
	return String(row.get("state", "")) == "invalid" and String(row.get("manifest_id", "")) == "" \
		and String(row.get("good", "")) == "" and int(row.get("qty", -1)) == 0 \
		and int(row.get("cost", -1)) == 0 and String(row.get("worker_id", "")) == ""

func _ready() -> void:
	_pin_settings()
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	Sim.auto_run = false
	Sim.running = false

	# 1) 空/ready/invalid：当前泊位完全复用 cargo authority，坏单不泄露业务字段。
	Sim.start_new(1)
	var empty: Dictionary = Sim.warehouse_observatory_projection("port_dock")
	ck(String(empty.get("mode", "")) == "read_only"
		and String((empty.get("cargo", {}) as Dictionary).get("state", "")) == "empty"
		and String((empty.get("receipt", {}) as Dictionary).get("state", "")) == "none",
		"空港投影明确 read_only，泊位 empty、历史 none")
	var manifest_id := _fixture(true)
	var ready: Dictionary = Sim.warehouse_observatory_projection("port_dock")
	var ready_cargo: Dictionary = ready.get("cargo", {})
	ck(String(ready_cargo.get("state", "")) == "ready" and String(ready_cargo.get("good", "")) == "柴薪"
		and int(ready_cargo.get("qty", 0)) == 4 and int((ready.get("stocks", {}) as Dictionary)["柴薪"]["cap"]) > 0,
		"ready 泊位与三类库存来自同一 observatory projection")
	var original_good = Sim.cargo_manifests[manifest_id]["good"]
	Sim.cargo_manifests[manifest_id]["good"] = "豆子"
	var invalid_projection: Dictionary = Sim.warehouse_observatory_projection("port_dock")
	ck(_safe_invalid_cargo(invalid_projection.get("cargo", {})), "坏 manifest 在观测室 fail-closed 且隐藏货/量/工人")
	Sim.cargo_manifests[manifest_id]["good"] = original_good

	# 2) 付费 exact tx 与坏账：合法回执可读，最新坏账绝不回退成更老的好消息。
	var before_commit := _snapshot()
	ck(Sim._commit_manifest_unload(manifest_id, "tao", "port_dock", true) == 4 and _snapshot() != before_commit,
		"既有码头工事务仍是唯一会改钱/货/cargo/event 的路径")
	var complete: Dictionary = Sim.warehouse_observatory_projection("port_dock")
	var receipt: Dictionary = complete.get("receipt", {})
	ck(String((complete.get("cargo", {}) as Dictionary).get("state", "")) == "empty"
		and String(receipt.get("state", "")) == "complete" and String(receipt.get("manifest_id", "")) == manifest_id
		and String(receipt.get("good", "")) == "柴薪" and int(receipt.get("qty", 0)) == 4
		and String(receipt.get("worker_id", "")) == "tao" and String(receipt.get("txid", "")) == "cargo_unload/" + manifest_id,
		"付费 pay→stock→world exact chain 投影为一笔完成回执")
	var clean_events: Array = Sim.event_log.duplicate(true)
	Sim.event_log[Sim.event_log.size() - 1]["note"] = "cargo_unload:%s*3" % manifest_id
	ck(_safe_invalid_receipt(Sim.warehouse_observatory_projection("port_dock")["receipt"]),
		"最新 receipt 数量错绑时 invalid 且不泄露旧明细")
	Sim.event_log = clean_events.duplicate(true)
	Sim._rebuild_cargo_event_index()
	Sim.event_log[Sim.event_log.size() - 1]["note"] = "corrupt"
	ck(_safe_invalid_receipt(Sim.warehouse_observatory_projection("port_dock")["receipt"]),
		"最新 receipt note 丢前缀时仍由 txid 捕获为 invalid，不回退旧账")
	Sim.event_log = clean_events.duplicate(true)
	Sim._rebuild_cargo_event_index()
	var duplicate_stock: Dictionary = Sim.event_log[Sim.event_log.size() - 2].duplicate(true)
	for i in 5001:
		Sim.event_log.append({"id": 900000 + i, "tick": i, "type": "noise", "actor": "noise",
			"target": "noise", "subject": "", "accepted": true, "witnesses": [], "note": "history"})
	Sim.event_log.append(duplicate_stock)
	ck(_safe_invalid_receipt(Sim.warehouse_observatory_projection("port_dock")["receipt"]),
		"相隔 5001 条无关历史后同 txid 多一行仍 exact-set 变红，不以总数近似放行")
	Sim.event_log = clean_events.duplicate(true)
	Sim._rebuild_cargo_event_index()
	Sim.event_log[Sim.event_log.size() - 1]["actor"] = "forged_worker"
	ck(_safe_invalid_receipt(Sim.warehouse_observatory_projection("port_dock")["receipt"]),
		"回执 worker 非 authored 码头工时隐藏业务明细")
	Sim.event_log = clean_events.duplicate(true)
	Sim._rebuild_cargo_event_index()
	for event in Sim.event_log:
		if String(event.get("note", "")).begins_with("cargo_arrive:" + manifest_id):
			event["accepted"] = false
			break
	ck(_safe_invalid_receipt(Sim.warehouse_observatory_projection("port_dock")["receipt"]),
		"退休单缺 exact accepted arrival proof 时历史投影 fail-closed")
	Sim.event_log = clean_events.duplicate(true)
	Sim._rebuild_cargo_event_index()
	ck(String((Sim.warehouse_observatory_projection("port_dock")["receipt"] as Dictionary).get("state", "")) == "complete",
		"恢复 exact event chain 后回执重新可读")

	# 3) economy-off 两行链仍是合法历史，不把“无 pay”误判为残缺。
	manifest_id = _fixture(false)
	ck(Sim._commit_manifest_unload(manifest_id, "tao", "port_dock", true) == 4, "economy-off 仍由既有事务完成整单")
	var free_receipt: Dictionary = Sim.warehouse_observatory_projection("port_dock")["receipt"]
	ck(String(free_receipt.get("state", "")) == "complete" and int(free_receipt.get("qty", 0)) == 4,
		"免费 stock→world 两行 exact chain 也可审计")
	for i in 5000:
		Sim._log_event("debug", "probe", "history_%d" % i, "", true, [], "synthetic_history")
	var reads_before := Sim.observatory_projection_event_reads
	var large_projection: Dictionary = Sim.warehouse_observatory_projection("port_dock")
	var reads_after := Sim.observatory_projection_event_reads
	var query_ops_after := Sim.observatory_projection_query_ops
	ck(String((large_projection.get("receipt", {}) as Dictionary).get("state", "")) == "complete"
		and Sim.event_log.size() > 5000 and reads_after - reads_before <= 2
		and query_ops_after <= Sim.OBSERVATORY_QUERY_OP_BUDGET
		and not Sim.observatory_projection_query_budget_failed,
		"E=5000 无关历史下 projection 总查询工作保持有界（含 ledger/index/tx dereference）")
	var budget_before_mutation := Sim.observatory_projection_query_ops
	Sim.observatory_projection_query_ops = Sim.OBSERVATORY_QUERY_OP_BUDGET
	Sim.observatory_projection_query_budget_failed = false
	Sim._projection_query_op()
	ck(Sim.observatory_projection_query_ops == Sim.OBSERVATORY_QUERY_OP_BUDGET + 1
		and Sim.observatory_projection_query_budget_failed,
		"查询预算负对照：注入一次额外 ledger/index dereference 会真实触发 over-budget")
	Sim.observatory_projection_query_ops = budget_before_mutation
	Sim.observatory_projection_query_budget_failed = false
	ck(Sim.OBSERVATORY_RECEIPT_SCAN_LIMIT == 1024,
		"兼容常量保留但不再作为 redraw 扫描窗口")

	# 4) 真 Main 门路 + 柜台：室内隐藏社交动作，位置写真实 plane；点击只写 UI feed。
	manifest_id = _fixture(true)
	var pl: Dictionary = Sim.add_player(Vector2i(57, 8))
	_main._player_mode = true
	_main._selected_id = "player"
	_main._probe.go_home()
	ck(_main._portal_click(Vector2(57 * 48 + 24, 8 * 48 + 24))
		and String(pl.get("space", "")) == "port_warehouse" and String(pl.get("floor", "")) == "1f",
		"真实产品门点击令 player 进入东海货仓 1f")
	_main._update_status()
	ck(not _main._act_pan.visible and _main._act_btns.all(func(b): return not (b as Button).visible),
		"观测室隐藏七个社交按钮，不暗示货仓操作")
	ck("东海货仓 · 货运观测室" in String(_main._obs.text)
		and "货运观测室（只读）" in String(_main._status.text) and not _main._chat_in.visible,
		"实际观察台/顶栏按真实 plane 显示里程碑，仓内自聊输入框收起")
	var before_chat := _snapshot()
	var c_event := InputEventKey.new()
	c_event.keycode = KEY_C
	c_event.pressed = true
	_main._unhandled_input(c_event)
	ck(_snapshot() == before_chat
		and "货运观测室只读" in String(_main._log_recent[-1]),
		"观测室 C 键快捷入口 fail-closed，仅留下明确 UI 拒绝，不写 Sim 或居民记忆")
	_main._on_player_say("绕过输入框的探针")
	ck(_snapshot() == before_chat
		and "货运观测室只读" in String(_main._log_recent[-1]),
		"观测室直调聊天入口同样 fail-closed，不写 Sim 或居民记忆")
	var aria := Sim.get_agent("aria")
	var aria_pos: Vector2i = aria.get("pos", Vector2i.ZERO)
	_main._selected_id = "player"
	_main._select_at_world(Vector2(aria_pos.x * 48 + 24, aria_pos.y * 48 + 24))
	ck(_main._selected_id == "player", "观测室点选不会跨 space/floor 选中镇上居民")
	_main._focus_agent("aria")
	ck(_main._selected_id == "player", "日志/程序化 focus 也拒绝跨 plane 选人")
	var console_cell := Sim.warehouse_observatory_console_cell()
	ck(console_cell == Vector2i(6, 1), "柜台格来自 interiors authored marker，而非 Main 抄坐标")
	var before_click := _snapshot()
	_main._on_probe_tap(Vector2(console_cell.x * 48 + 24, console_cell.y * 48 + 24))
	ck(_snapshot() == before_click and not _main._log_recent.is_empty()
		and "观测台｜泊位 柴薪×4" in String(_main._log_recent[-1]) and "（只读）" in String(_main._log_recent[-1]),
		"点柜台只追加可读 UI 反馈，Sim 钱/货/cargo/event/digest 精确 no-op")
	var before_social_key := _snapshot()
	ck(_main._player_do("greet") == "货运观测室只读；卸货由码头工执行"
		and _snapshot() == before_social_key,
		"观测室物理社交键同门拒绝且不写 Sim")
	ck(_main._portal_click(Vector2(8 * 48 + 24, 3 * 48 + 24))
		and String(pl.get("space", "")) == "town" and String(pl.get("floor", "")) == "outdoor",
		"右侧木门仍经真实 portal 返回东海码头")
	# P1-ac chat authority: adjacent positive, same-plane remote denial, and delayed reply invalidation.
	var target := Sim.get_agent("tao")
	var target_pos: Vector2i = target.get("pos", Vector2i.ZERO)
	pl["pos"] = target_pos + Vector2i(1, 0)
	_main._selected_id = "tao"
	var chat_token: int = _main._chat_generation
	var sim_identity := Sim.get_instance_id()
	var session_id: int = _main._chat_session_id
	var applied: bool = _main._apply_chat_reply(chat_token, "tao", "town", "outdoor", target_pos,
		"town", "outdoor", pl["pos"], sim_identity, session_id, "hi", "adjacent reply")
	ck(applied, "同平面相邻目标允许聊天回包并写入当前目标")
	var memory_before_move: Array = target["memory"].items.duplicate(true)
	var log_before_move: int = _main._log_recent.size()
	target["thinking"] = true
	target["_chat_request_token"] = str(chat_token)
	target["pos"] = target_pos + Vector2i(1, 0)
	ck(not _main._apply_chat_reply(chat_token, "tao", "town", "outdoor", target_pos,
		"town", "outdoor", pl["pos"], sim_identity, session_id, "hi", "moved reply")
		and bool(target.get("thinking", false))
		and String(target.get("_chat_request_token", "")) == str(chat_token)
		and target["memory"].items == memory_before_move and _main._log_recent.size() == log_before_move,
		"目标在仍可达范围内移动后，旧回包是 literal no-op（不清 thinking/token/UI/记忆）")
	target["pos"] = target_pos
	var memory_before_plane: Array = target["memory"].items.duplicate(true)
	target["space"] = "port_warehouse"; target["floor"] = "1f"
	ck(not _main._apply_chat_reply(chat_token, "tao", "town", "outdoor", target_pos,
		"town", "outdoor", pl["pos"], sim_identity, session_id, "hi", "plane replaced")
		and target["space"] == "port_warehouse" and target["floor"] == "1f"
		and bool(target.get("thinking", false))
		and String(target.get("_chat_request_token", "")) == str(chat_token)
		and target["memory"].items == memory_before_plane
		and _main._log_recent.size() == log_before_move,
		"目标 plane/floor 被替换后，迟到回包仍是 literal no-op")
	target["space"] = "town"; target["floor"] = "outdoor"
	pl["pos"] = target_pos + Vector2i(8, 0)
	var remote_before := _snapshot()
	_main._on_player_say("远程探针")
	ck(_snapshot() == remote_before, "同平面远距离目标被聊天权威拒绝")
	pl["pos"] = target_pos + Vector2i(1, 0)
	chat_token = _main._chat_generation
	var request_a := chat_token + 1
	_main._chat_generation = request_a
	target["_chat_request_token"] = str(request_a)
	target["thinking"] = true
	var request_b := request_a + 1
	_main._chat_generation = request_b
	target["_chat_request_token"] = str(request_b)
	target["thinking"] = true
	var late_a_before := _snapshot()
	ck(not _main._apply_chat_reply(request_a, "tao", "town", "outdoor", target_pos,
		"town", "outdoor", pl["pos"], sim_identity, session_id, "A", "late A")
		and _snapshot() == late_a_before and bool(target.get("thinking", false))
		and String(target.get("_chat_request_token", "")) == str(request_b),
		"请求 B 取代请求 A 后，迟到 A 不清理 B 的 thinking 且不写 UI/记忆")
	var wrong_sim_before := _snapshot()
	var wrong_sim_memory: Array = target["memory"].items.duplicate(true)
	var wrong_sim_token := String(target.get("_chat_request_token", ""))
	var wrong_sim_thinking := bool(target.get("thinking", false))
	ck(not _main._apply_chat_reply(request_b, "tao", "town", "outdoor", target_pos,
		"town", "outdoor", pl["pos"], sim_identity + 1, session_id, "B", "wrong Sim")
		and _snapshot() == wrong_sim_before and target["memory"].items == wrong_sim_memory
		and bool(target.get("thinking", false)) == wrong_sim_thinking
		and String(target.get("_chat_request_token", "")) == wrong_sim_token,
		"wrong Sim instance 的迟到回包是 exact no-op")
	var session_before: int = _main._chat_session_id
	_main._chat_session_id = session_before + 1
	var session_only_before := _snapshot()
	var session_only_memory: Array = target["memory"].items.duplicate(true)
	ck(not _main._apply_chat_reply(request_b, "tao", "town", "outdoor", target_pos,
		"town", "outdoor", pl["pos"], sim_identity, session_before, "B", "wrong session")
		and _snapshot() == session_only_before and target["memory"].items == session_only_memory
		and bool(target.get("thinking", false)) == wrong_sim_thinking
		and String(target.get("_chat_request_token", "")) == wrong_sim_token,
		"仅 session 替换的迟到回包是 exact no-op")
	_main._chat_session_id = session_before
	chat_token = _main._chat_generation
	pl["space"] = "port_warehouse"; pl["floor"] = "1f"
	ck(not _main._apply_chat_reply(chat_token, "tao", "town", "outdoor", target_pos,
		"town", "outdoor", pl["pos"], sim_identity, session_id, "hi", "stale portal"),
		"玩家进仓后延迟回包不写 UI/记忆")
	pl["space"] = "town"; pl["floor"] = "outdoor"; pl["pos"] = target_pos + Vector2i(1, 0)
	chat_token = _main._chat_generation
	_main._invalidate_chat_generation()
	ck(not _main._apply_chat_reply(chat_token, "tao", "town", "outdoor", target_pos,
		"town", "outdoor", pl["pos"], sim_identity, session_id, "hi", "stale load"),
		"load/session generation 替换后延迟回包失效")
	var lifecycle_token: int = _main._chat_generation
	target["thinking"] = true
	target["_chat_request_token"] = str(lifecycle_token)
	var lifecycle_memory: Array = target["memory"].items.duplicate(true)
	var lifecycle_log_size: int = _main._log_recent.size()
	_main._invalidate_chat_generation()
	ck(not bool(target.get("thinking", false)) and not target.has("_chat_request_token")
		and target["memory"].items == lifecycle_memory and _main._log_recent.size() == lifecycle_log_size,
		"生命周期取消在回调之外清理当前拥有的 request，不触碰 UI/记忆")

	_restore_settings()
	print("p1v_warehouse_observatory_test: " + ("PASS ✅" if _fails == 0 else "FAIL ❌ (%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)
